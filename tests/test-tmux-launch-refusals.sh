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
  for mode in remove-worktree swap-worktree; do
    new_case
    before=$(calls_now)
    SEAM_MODE=$mode SEAM_WT="$PP/.claude/worktrees/demo-task-2" \
      tlh_run_bounded "$seam/fleet-dispatch-worktree.sh" dispatch demo 2 --repo-root "$P"
    [ "$TLH_RC" -eq 11 ] || fail "r3 [$mode]: expected exit 11, got $TLH_RC ($TLH_ERR)"
    [ -z "$(tmux_calls_since "$before" | awk -F"$TAB" '$1 == "new-session"')" ] \
      || fail "r3 [$mode]: new-session was called"
    [ ! -s "$C/fleet/registry" ] || fail "r3 [$mode]: a registry record was written"
  done
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
  (cd "$P" && tlh_run_bounded "$PRIM" attach demo-task-3 --dry-run && printf '%s\n' "$TLH_OUT" >"$C/plan")
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
  [ -z "$(tmux_calls_since "$before" | awk -F"$TAB" '$1 == "new-session"')" ] || fail "r12: new-session was called"
  nothing_placed r12 1
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

[ "$fails" -eq 0 ] || {
  echo "test-tmux-launch-refusals: $fails failure(s)" >&2
  exit 1
}
echo "ok: test-tmux-launch-refusals"
