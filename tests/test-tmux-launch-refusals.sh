#!/bin/bash
# The tmux rung's refusal and failure arms, on the launch fixture harness
# (tests/lib/tmux-launch-harness.sh). Each case fails when its arm is removed.
# Every launch runs under the harness's bounded runner.
#   r1  a worktree path outside the path charset (`#`, `#(...)`, a space, a
#       control byte) is refused with no tmux call and nothing placed
#       (REQ-G1.1)
#   r2  the session-name check refuses each byte outside its charset, a
#       leading `-`, and a name over 128 bytes (REQ-G1.1)
#   r3  a start directory removed between create and launch, and one that is
#       not the placed worktree, are refused before new-session (REQ-G1.2)
#   r4  a live standalone attach is refused with no tmux call; its dry run
#       still prints the detached plan; the dispatch arm's path-escape guard
#       refuses with no tmux call (REQ-G1.3)
#   r5  a live session holding the name aborts before the worktree, branch,
#       marker, or registry record exists (REQ-G1.4)
#   r6  a lost race leaves the winner's worktree, branch, and marker and writes
#       no record (REQ-G1.4)
#   r7  another post-create failure removes this run's worktree and branch and
#       clears its marker, and keeps a branch it adopted (REQ-G1.4)
#   r8  a failing undo step is reported by name, with the original status
#       (REQ-G1.4)
#   r9  a worker CLI that does not resolve to an absolute executable, and a
#       tmux that does not resolve, are refused before any side effect
#       (REQ-G1.5)
#   r10 a refusal from the env wrapper's --check is reported by the dispatch
#       with no new-session call (REQ-F1.5)
#   r11 a decoy pane sitting in the worktree does not change the death handle
#       (REQ-G1.6)
#   r12 a launch word ending in `;`, which tmux reads as a command separator,
#       is refused before anything is placed
#   r13 an env wrapper without its exec bit is refused before anything is
#       placed: tmux execs it directly, where --check runs it through sh
#   r14 a liveness probe reads not live only on tmux's own "no such session"
#       answer; a server it cannot reach reads live, and nothing is placed,
#       removed, or cleared
#   r15 a new-session that never returns is ended at the tmux call bound and
#       fails the launch, and the undo keeps what a session may be using
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-tmux-launch-refusals.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

# shellcheck source=tests/lib/tmux-launch-harness.sh
. "$here/lib/tmux-launch-harness.sh"
# shellcheck source=tests/lib/tmux-launch-cases.sh
. "$here/lib/tmux-launch-cases.sh"

# nothing_placed <label> <id> — no worktree, branch, marker, or record.
nothing_placed() {
  [ ! -e "$P/.claude/worktrees/demo-task-$2" ] || fail "$1: a worktree was placed"
  gitc "$P" show-ref --verify --quiet "refs/heads/planwright/demo/task-$2" && fail "$1: a branch was created"
  [ ! -e "$C/markers/$2" ] || fail "$1: a dispatch marker was written"
  [ ! -s "$C/fleet/registry" ] || fail "$1: a registry record was written"
  return 0
}

tmux_calls_since() {
  tlh_tmux_calls | tail -n "+$(($1 + 1))"
}

calls_now() {
  tlh_tmux_calls | grep -c . || true
}

# --- r1: worktree path charset ------------------------------------------------
r1() {
  local dir before
  for dir in 'hash#dir' 'sub#(touch x)' 'sp ace' "ctl$(printf '\001')x"; do
    new_case "$dir/primary"
    before=$(calls_now)
    tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P"
    [ "$TLH_RC" -eq 9 ] || fail "r1 [$dir]: expected exit 9, got $TLH_RC ($TLH_ERR)"
    case $TLH_ERR in
      *'[A-Za-z0-9._/@+-]'*worktree*path* | *worktree*path*'[A-Za-z0-9._/@+-]'*) ;;
      *) fail "r1 [$dir]: the refusal does not name the value class and the charset: $TLH_ERR" ;;
    esac
    [ -z "$(tmux_calls_since "$before")" ] || fail "r1 [$dir]: tmux was called: $(tmux_calls_since "$before")"
    nothing_placed "r1 [$dir]" 1
  done
  # The create-only arm is not the tmux rung, so it still places the worktree.
  new_case 'hash#dir/primary'
  tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P" --no-attach
  [ "$TLH_RC" -eq 0 ] || fail "r1: --no-attach must not take the tmux rung's charset, got $TLH_RC ($TLH_ERR)"
}

# --- r2: the session-name check ----------------------------------------------
r2() {
  local name long rc
  long=a
  while [ "${#long}" -lt 129 ]; do long="${long}b"; done
  for name in 'a#b' 'a#(x)' 'a b' "a$(printf '\001')b" 'a.b' 'a+b' '-ab' '_ab' 'a:b' 'a/b' '' "$long"; do
    rc=0
    "$PRIM" check-session-name "$name" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 10 ] || fail "r2: session name '$name' must be refused (exit 10), got $rc"
  done
  for name in a-b_c@d "${long%b}" 9z; do
    rc=0
    "$PRIM" check-session-name "$name" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || fail "r2: session name '$name' must pass, got $rc"
  done
}

# --- r3: the start directory -------------------------------------------------
r3() {
  local seam mode before
  seam=$(seam_root)
  # swap-root keeps the leaf a real directory, so only the physical-path
  # comparison can refuse it.
  for mode in remove-worktree swap-worktree swap-root; do
    new_case
    before=$(calls_now)
    SEAM_MODE=$mode SEAM_WT="$PP/.claude/worktrees/demo-task-2" \
      tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 2 --repo-root "$P"
    [ "$TLH_RC" -eq 11 ] || fail "r3 [$mode]: expected exit 11, got $TLH_RC ($TLH_ERR)"
    [ -z "$(tmux_calls_since "$before" | awk -F"$TAB" '$1 == "new-session"')" ] \
      || fail "r3 [$mode]: new-session was called"
    [ ! -s "$C/fleet/registry" ] || fail "r3 [$mode]: a registry record was written"
  done
  # The refusal undoes what the run created (the remove-worktree case, where
  # nothing else is in the way).
  new_case
  SEAM_MODE=remove-worktree SEAM_WT="$PP/.claude/worktrees/demo-task-3" \
    tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 3 --repo-root "$P"
  [ "$TLH_RC" -eq 11 ] || fail "r3: expected exit 11, got $TLH_RC"
  nothing_placed "r3 undo" 3
}

# --- r4: live standalone attach, and the path-escape guard -------------------
r4() {
  local before lnk
  new_case
  mkdir -p "$P/.claude/worktrees/demo-task-3"
  before=$(calls_now)
  (cd "$P" && tlh_run_bounded "$PRIM" attach demo-task-3 && exit "$TLH_RC")
  rc=$?
  [ "$rc" -eq 2 ] || fail "r4: a live standalone attach must be refused (exit 2), got $rc"
  [ -z "$(tmux_calls_since "$before")" ] || fail "r4: the refused attach called tmux"
  before=$(calls_now)
  rc=0
  (cd "$P" && tlh_run_bounded "$PRIM" attach demo-task-3 --dry-run && printf '%s\n' "$TLH_OUT" >"$C/plan" \
    && exit "$TLH_RC") || rc=$?
  [ "$rc" -eq 0 ] || fail "r4: the dry-run attach must exit 0, got $rc"
  [ -z "$(tmux_calls_since "$before")" ] || fail "r4: the dry-run attach called tmux: $(tmux_calls_since "$before")"
  grep -q "^attach-plan${TAB}launch${TAB}tmux${TAB}new-session${TAB}-d${TAB}" "$C/plan" \
    || fail "r4: the dry-run attach does not print the detached plan: $(cat "$C/plan")"
  for lnk in .claude .claude/worktrees .claude/worktrees/demo-task-4; do
    new_case
    mkdir -p "$C/outside" "$(dirname "$P/$lnk")"
    rm -rf "${P:?}/$lnk"
    ln -s "$C/outside" "$P/$lnk"
    before=$(calls_now)
    tlh_run_bounded "$PRIM" dispatch demo 4 --repo-root "$P"
    [ "$TLH_RC" -eq 5 ] || fail "r4 [$lnk]: a symlinked component must be refused (exit 5), got $TLH_RC"
    [ -z "$(tmux_calls_since "$before")" ] || fail "r4 [$lnk]: tmux was called"
  done
}

# --- r5: a live session already holds the name -------------------------------
r5() {
  local s
  new_case
  s=$(expect_session "$PP" demo-task-5)
  tmux new-session -d -s "$s"
  tlh_run_bounded "$PRIM" dispatch demo 5 --repo-root "$P"
  [ "$TLH_RC" -eq 3 ] || fail "r5: a live session holding the name must abort in flight (exit 3), got $TLH_RC"
  nothing_placed r5 5
  [ "$(calls_matching new-session | grep -cE "$TAB-s$TAB$s($TAB|\$)")" = 1 ] \
    || fail "r5: the dispatch reached new-session"
  tmux kill-session -t "=$s"
}

# --- r6: a lost race ----------------------------------------------------------
r6() {
  new_case
  tlh_knob new-session duplicate
  tlh_run_bounded "$PRIM" dispatch demo 6 --repo-root "$P"
  tlh_knob new-session ok
  [ "$TLH_RC" -eq 3 ] || fail "r6: a lost race must abort in flight (exit 3), got $TLH_RC ($TLH_ERR)"
  [ -d "$P/.claude/worktrees/demo-task-6" ] || fail "r6: the winner's worktree was removed"
  gitc "$P" show-ref --verify --quiet refs/heads/planwright/demo/task-6 || fail "r6: the winner's branch was deleted"
  [ -e "$C/markers/6" ] || fail "r6: the winner's marker was cleared"
  [ ! -s "$C/fleet/registry" ] || fail "r6: the loser wrote a registry record"
}

# --- r7: another post-create failure ------------------------------------------
r7() {
  new_case
  tlh_knob new-session fail
  tlh_run_bounded "$PRIM" dispatch demo 7 --repo-root "$P"
  [ "$TLH_RC" -eq 13 ] || fail "r7: a failed new-session must exit 13, got $TLH_RC ($TLH_ERR)"
  nothing_placed r7 7
  # An adopted branch stays; the worktree this run placed on it goes.
  stale_branch() {
    gitc "$P" branch "planwright/demo/task-$1" main
    gitc "$P" checkout -q "planwright/demo/task-$1"
    printf 'w\n' >"$P/work-$1"
    gitc "$P" add -A
    gitc "$P" commit -q -m work
    gitc "$P" checkout -q main
  }
  stale_branch 8
  tlh_run_bounded "$PRIM" dispatch demo 8 --repo-root "$P"
  tlh_knob new-session ok
  [ "$TLH_RC" -eq 13 ] || fail "r7: a failed new-session over an adopted branch must exit 13, got $TLH_RC"
  gitc "$P" show-ref --verify --quiet refs/heads/planwright/demo/task-8 || fail "r7: the adopted branch was deleted"
  [ ! -e "$P/.claude/worktrees/demo-task-8" ] || fail "r7: the worktree placed on the adopted branch stayed"
  [ ! -e "$C/markers/8" ] || fail "r7: the marker stayed"
  [ ! -s "$C/fleet/registry" ] || fail "r7: a failed launch wrote a registry record"
}

# --- r8: a failing undo step is named -----------------------------------------
r8() {
  local seam
  seam=$(seam_root)
  new_case
  tlh_knob new-session fail
  SEAM_MODE=fail-clear tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 9 --repo-root "$P"
  tlh_knob new-session ok
  [ "$TLH_RC" -eq 13 ] || fail "r8: the original failure's status must survive a failed undo, got $TLH_RC"
  case $TLH_ERR in
    *undo*marker*) ;;
    *) fail "r8: the failed undo step is not named: $TLH_ERR" ;;
  esac
}

# --- r9: worker CLI and tmux resolution --------------------------------------
# path_without_tmux — PATH minus every tmux: a directory holding one is
# replaced by a farm of links to everything else in it.
path_without_tmux() {
  local d out='' farm i=0 IFS=:
  for d in $PATH; do
    [ "$d" = "$TLH_BIN" ] && continue
    if [ -e "$d/tmux" ]; then
      i=$((i + 1))
      farm="$C/farm$i"
      mkdir -p "$farm"
      ln -s "$d"/* "$farm"/ 2>/dev/null
      rm -f "$farm/tmux"
      d=$farm
    fi
    out=${out:+$out:}$d
  done
  printf '%s\n' "$out"
}

r9() {
  local label bin before rc
  for label in relative missing non-executable; do
    new_case
    bin="$C/cli"
    mkdir -p "$bin"
    case $label in
      relative) cp "$TLH_BIN/claude" "$bin/claude" ;;
      missing) ln -s "$C/nowhere" "$bin/claude" ;;
      non-executable) printf '#!/bin/sh\n' >"$bin/claude" ;;
    esac
    before=$(calls_now)
    if [ "$label" = relative ]; then
      # Only a /bin/sh whose `command -v` reports a relative PATH entry as
      # relative (dash does; bash absolutizes it) can produce this case.
      case $(cd "$C" && PATH="cli:$PATH" /bin/sh -c 'command -v claude') in
        /*)
          echo "skip r9 [relative claude]: this /bin/sh absolutizes a relative PATH match"
          continue
          ;;
      esac
      rc=0
      (cd "$C" && PATH="cli:$PATH" tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P" && exit "$TLH_RC") || rc=$?
    else
      # Only the stub tmux stays reachable, so the bad worker CLI is the one found.
      mkdir -p "$C/tonly"
      ln -s "$TLH_BIN/tmux" "$C/tonly/tmux"
      rc=0
      (PATH="$bin:$C/tonly:$(path_without_claude)" tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P" && exit "$TLH_RC") || rc=$?
    fi
    [ "$rc" -eq 7 ] || fail "r9 [$label claude]: expected exit 7, got $rc"
    [ -z "$(tmux_calls_since "$before")" ] || fail "r9 [$label claude]: tmux was called"
    nothing_placed "r9 [$label claude]" 1
  done
  new_case
  mkdir -p "$C/conly"
  ln -s "$TLH_BIN/claude" "$C/conly/claude"
  rc=0
  (PATH="$C/conly:$(path_without_tmux)" tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P" && exit "$TLH_RC") || rc=$?
  [ "$rc" -eq 8 ] || fail "r9 [tmux]: an unresolvable tmux must exit 8, got $rc"
  nothing_placed "r9 [tmux]" 1
  # A tmux found through a relative PATH entry is a file in whatever directory
  # the dispatch runs from, so it is refused like a relative worker CLI.
  new_case
  mkdir -p "$C/tcli"
  cp "$TLH_BIN/tmux" "$C/tcli/tmux"
  case $(cd "$C" && PATH="tcli:$PATH" /bin/sh -c 'command -v tmux') in
    /*) echo "skip r9 [relative tmux]: this /bin/sh absolutizes a relative PATH match" ;;
    *)
      rc=0
      (cd "$C" && PATH="tcli:$PATH" tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P" && exit "$TLH_RC") || rc=$?
      [ "$rc" -eq 8 ] || fail "r9 [relative tmux]: expected exit 8, got $rc"
      nothing_placed "r9 [relative tmux]" 1
      ;;
  esac
}

# path_without_claude — PATH minus the harness's shims and any real claude.
path_without_claude() {
  local d out='' farm i=0 IFS=:
  for d in $PATH; do
    [ "$d" = "$TLH_BIN" ] && continue
    if [ -e "$d/claude" ]; then
      i=$((i + 1))
      farm="$C/cfarm$i"
      mkdir -p "$farm"
      ln -s "$d"/* "$farm"/ 2>/dev/null
      rm -f "$farm/claude"
      d=$farm
    fi
    out=${out:+$out:}$d
  done
  printf '%s\n' "$out"
}

# --- r10: the env wrapper's --check refusal -----------------------------------
r10() {
  local seam before
  seam=$(seam_root)
  new_case
  before=$(calls_now)
  SEAM_MODE=refuse-check tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 1 --repo-root "$P"
  [ "$TLH_RC" -eq 12 ] || fail "r10: a --check refusal must exit 12, got $TLH_RC ($TLH_ERR)"
  case $TLH_ERR in *'refused by the seam'*) ;; *) fail "r10: the wrapper's refusal is not reported: $TLH_ERR" ;; esac
  [ -z "$(tmux_calls_since "$before" | awk -F"$TAB" '$1 == "new-session"')" ] || fail "r10: new-session was called"
  nothing_placed r10 1
}

# --- r11: a decoy pane in the worktree ----------------------------------------
r11() {
  local seam s
  seam=$(seam_root)
  new_case
  SEAM_MODE=decoy-pane SEAM_WT="$PP/.claude/worktrees/demo-task-1" \
    tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 1 --repo-root "$P"
  [ "$TLH_RC" -eq 14 ] || fail "r11: expected started-unconfirmed, got $TLH_RC ($TLH_ERR)"
  tmux has-session -t =decoy-pane 2>/dev/null || fail "r11: the decoy pane was not created"
  s=$(expect_session "$PP" demo-task-1)
  [ "$(registry_col 7)" = "tmux-window $s $(launch_field window)" ] \
    || fail "r11: the decoy changed the death handle: '$(registry_col 7)'"
  tmux kill-session -t =decoy-pane
}

# --- r12: a launch word ending in `;` -----------------------------------------
# tmux would end the launch command at it, so the worker would lose its argv.
r12() {
  local before
  new_case
  before=$(calls_now)
  tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P" -- --model 'opus;'
  [ "$TLH_RC" -eq 2 ] || fail "r12: a launch word ending in ';' must be refused (exit 2), got $TLH_RC ($TLH_ERR)"
  case $TLH_ERR in
    *'command separator'*) ;;
    *) fail "r12: the refusal is not the separator arm's: $TLH_ERR" ;;
  esac
  [ -z "$(tmux_calls_since "$before" | awk -F"$TAB" '$1 == "new-session"')" ] || fail "r12: new-session was called"
  nothing_placed r12 1
}

# --- r13: an env wrapper tmux cannot exec -------------------------------------
# --check runs the wrapper through sh, while the session's command execs it, so
# a wrapper without its exec bit would pass the check and die in the pane.
r13() {
  local seam before
  seam=$(seam_root)
  new_case
  chmod a-x "$seam/fleet-dispatch-env.sh"
  before=$(calls_now)
  tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 1 --repo-root "$P"
  chmod a+x "$seam/fleet-dispatch-env.sh"
  [ "$TLH_RC" -eq 12 ] || fail "r13: a non-executable env wrapper must be refused (exit 12), got $TLH_RC ($TLH_ERR)"
  [ -z "$(tmux_calls_since "$before" | awk -F"$TAB" '$1 == "new-session"')" ] || fail "r13: new-session was called"
  nothing_placed r13 1
}

# work_branch <id> — a branch carrying a commit and no worktree: the create
# collides with it and the dispatch must decide whether a worker holds it.
work_branch() {
  gitc "$P" branch "planwright/demo/task-$1" main
  gitc "$P" checkout -q "planwright/demo/task-$1"
  printf 'w\n' >"$P/work-$1"
  gitc "$P" add -A
  gitc "$P" commit -q -m "work $1"
  gitc "$P" checkout -q main
}

branch_has_work() {
  [ "$(gitc "$P" log -1 --format=%s "planwright/demo/task-$1" 2>/dev/null)" = "work $1" ]
}

# --- r14: what a liveness probe's answer means -------------------------------
# orphan_worktree <id> — a registered worktree carrying work, with no session
# and no marker: the stale-orphan reconcile removes it only on a definite
# "no session" answer.
orphan_worktree() {
  gitc "$P" worktree add -q -b "planwright/demo/task-$1" "$P/.claude/worktrees/demo-task-$1" main
  printf 'w\n' >"$P/.claude/worktrees/demo-task-$1/work-$1"
  gitc "$P/.claude/worktrees/demo-task-$1" add -A
  gitc "$P/.claude/worktrees/demo-task-$1" commit -q -m "work $1"
}

r14() {
  local s
  # A reachable server that says the session is not there: not live, so the
  # stale branch is adopted and launched.
  new_case
  tmux new-session -d -s r14-unrelated
  work_branch 4
  s=$(expect_session "$PP" demo-task-4)
  tlh_run_bounded "$PRIM" dispatch demo 4 --repo-root "$P"
  [ "$TLH_RC" -eq 14 ] || fail "r14: a session absent from a reachable server must read not live (launch, exit 14), got $TLH_RC ($TLH_ERR)"
  calls_matching has-session | grep -q "$TAB=$s\$" || fail "r14: the new name was never probed"
  tmux kill-session -t =r14-unrelated
  tmux kill-session -t "=$s"
  # No socket to reach a server at is a definite "none" too.
  new_case
  work_branch 8
  tmux_shim "$C/nosock" no-socket
  PATH="$C/nosock:$PATH" tlh_run_bounded "$PRIM" dispatch demo 8 --repo-root "$P" --no-attach
  [ "$TLH_RC" -eq 0 ] || fail "r14: a probe with no socket to connect to must read not live (adopt, exit 0), got $TLH_RC ($TLH_ERR)"
  # The collision reconcile (the create-only arm skips the launch's pre-check)
  # on a server it cannot reach: the answer is unknown, so the orphan reads
  # live and its worktree, branch, and work stay.
  new_case
  orphan_worktree 5
  tlh_knob server unreachable
  tlh_run_bounded "$PRIM" dispatch demo 5 --repo-root "$P" --no-attach
  tlh_knob server up
  [ "$TLH_RC" -eq 3 ] || fail "r14: a probe tmux cannot answer must read live (exit 3), got $TLH_RC ($TLH_ERR)"
  [ -f "$P/.claude/worktrees/demo-task-5/work-5" ] || fail "r14: the worktree was removed on an uncertain answer"
  branch_has_work 5 || fail "r14: the branch's work was touched on an uncertain answer"
  # The same through the launch's own pre-check: nothing is placed.
  new_case
  work_branch 6
  tlh_knob server unreachable
  tlh_run_bounded "$PRIM" dispatch demo 6 --repo-root "$P"
  tlh_knob server up
  [ "$TLH_RC" -eq 3 ] || fail "r14: the launch pre-check must read an unanswered probe as live (exit 3), got $TLH_RC"
  [ ! -e "$P/.claude/worktrees/demo-task-6" ] || fail "r14: a worktree was placed on an uncertain answer"
  [ ! -e "$C/markers/6" ] || fail "r14: a marker was written on an uncertain answer"
  # A probe that never answers is ended at the call bound and reads live, on
  # the reconcile path.
  new_case
  orphan_worktree 7
  tmux_shim "$C/hang" hang-probe
  PATH="$C/hang:$PATH" PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 \
    tlh_run_bounded --bound 20 "$PRIM" dispatch demo 7 --repo-root "$P" --no-attach
  tlh_expect_returned "r14: a hung probe must be ended" || return
  [ "$TLH_RC" -eq 3 ] || fail "r14: a probe that never answers must read live (exit 3), got $TLH_RC ($TLH_ERR)"
  [ -f "$P/.claude/worktrees/demo-task-7/work-7" ] || fail "r14: the worktree was removed on an unanswered probe"
}

# --- r15: a tmux that never returns -------------------------------------------
r15() {
  local s
  # No session came of it: the launch fails and undoes what it created,
  # keeping the branch it adopted.
  new_case
  work_branch 9
  tmux_shim "$C/hang" hang-new
  PATH="$C/hang:$PATH" PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 \
    tlh_run_bounded --bound 20 "$PRIM" dispatch demo 9 --repo-root "$P"
  tlh_expect_returned "r15: the dispatch must end a hung new-session itself" || return
  [ "$TLH_RC" -eq 13 ] || fail "r15: a hung new-session with no session must fail the launch (exit 13), got $TLH_RC ($TLH_ERR)"
  case $TLH_ERR in *'did not return'*) ;; *) fail "r15: the report does not name the hang: $TLH_ERR" ;; esac
  branch_has_work 9 || fail "r15: the adopted branch was touched"
  [ ! -e "$P/.claude/worktrees/demo-task-9" ] || fail "r15: the worktree this run placed was not undone"
  [ ! -e "$C/markers/9" ] || fail "r15: the marker this run set was not cleared"
  [ ! -s "$C/fleet/registry" ] || fail "r15: a failed launch wrote a registry record"
  # A client that exits 1 on the bound's TERM, as tmux does, is still a hang.
  new_case
  work_branch 12
  tmux_shim "$C/hang" hang-new-term1
  PATH="$C/hang:$PATH" PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 \
    tlh_run_bounded --bound 20 "$PRIM" dispatch demo 12 --repo-root "$P"
  [ "$TLH_RC" -eq 13 ] || fail "r15: a TERM-handling hung client must fail the launch (exit 13), got $TLH_RC"
  case $TLH_ERR in *'did not return'*) ;; *) fail "r15: a TERM-handling hung client is not reported as a hang: $TLH_ERR" ;; esac
  # tmux cannot then say whether a session exists: nothing is removed.
  new_case
  work_branch 10
  tmux_shim "$C/hang" hang-new-unsure
  PATH="$C/hang:$PATH" PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 \
    tlh_run_bounded --bound 30 "$PRIM" dispatch demo 10 --repo-root "$P"
  tlh_expect_returned "r15: an unsure undo must still return" || return
  [ "$TLH_RC" -eq 13 ] || fail "r15: a hung, unconfirmable launch must exit 13, got $TLH_RC ($TLH_ERR)"
  [ -d "$P/.claude/worktrees/demo-task-10" ] || fail "r15: a worktree a session may run in was removed"
  [ -e "$C/markers/10" ] || fail "r15: the marker beside a possibly running session was cleared"
  [ ! -s "$C/fleet/registry" ] || fail "r15: an unconfirmed session was registered"
  # The hung call did make its session: it is placed and registered.
  new_case
  work_branch 11
  s=$(expect_session "$PP" demo-task-11)
  tlh_knob new-session block
  PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 tlh_run_bounded --bound 20 "$PRIM" dispatch demo 11 --repo-root "$P"
  tlh_knob new-session ok
  tlh_expect_returned "r15: the dispatch must end a hung new-session that made its session" || return
  [ "$TLH_RC" -eq 14 ] || fail "r15: a hung new-session whose session exists is placed (exit 14), got $TLH_RC ($TLH_ERR)"
  case $TLH_ERR in *'did not return'*'exists'*) ;; *) fail "r15: the placed launch does not name the hang: $TLH_ERR" ;; esac
  [ "$(registry_col 2)" = tmux-demo-task-11 ] || fail "r15: the placed worker was not registered"
  tmux kill-session -t "=$s"
}

r1
r2
r3
r4
r5
r6
r7
r8
r9
r10
r11
r12
r13
r14
r15

[ "$fails" -eq 0 ] || {
  echo "test-tmux-launch-refusals: $fails failure(s)" >&2
  exit 1
}
echo "ok: test-tmux-launch-refusals"
