#!/bin/bash
# Tests for scripts/orchestrate-meta-step.sh — the meta-tower's single-spec
# step, run in the meta-tower's own session instead of a subordinate tower
# (REQ-G1.5, D-17).
#
# Contract under test:
#   orchestrate-meta-step.sh dispatch <spec-dir> <id> --backend <b>
#       --prompt-file <file> [--repo-root <dir>]
#   - takes the per-spec lock (scripts/orchestrate-lock.sh), runs the
#     freshness gate, writes the dispatch record (branch, then marker), and
#     releases the lock before the worker launches;
#   - launches exactly one worker, running /execute-task, in the unit's
#     worktree; a prompt that would start anything else (a subordinate
#     /orchestrate tower) is refused before any side effect;
#   - a lock another tower holds is a clean no-op (exit 1): nothing created,
#     nothing launched, the holder's lock untouched;
#   - a freshness-gate halt (anchor mismatch, no entry, a meaning-class entry
#     without its lens pass, a non-sanctioned command form) parks (exit 4)
#     with nothing created and the lock released.
#
# The worker CLI is a recording fake (PLANWRIGHT_HEADLESS_CLAUDE) on the
# headless-oneshot rung, so no model call is made.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="$(cd "$here/.." && pwd)/scripts"
STEP="$SCRIPTS/orchestrate-meta-step.sh"
TAB=$(printf '\t')

failures=0
case_f0=0
begin() { case_f0=$failures; }
pass() { [ "$failures" -ne "$case_f0" ] || echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

[ -x "$STEP" ] || {
  echo "FAIL: scripts/orchestrate-meta-step.sh missing or not executable" >&2
  exit 1
}

tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  for pf in "$tmp"/*/rec/claude-pid "$tmp"/*/hstate/*/pid; do
    [ -f "$pf" ] || continue
    p=$(cat "$pf" 2>/dev/null) || continue
    case $p in *[!0-9]* | '') continue ;; esac
    kill -9 "$p" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# brief_entry <class> <lens-or-empty> <hash> <command> — one sign-off record.
brief_entry() {
  printf '\nClass: %s\n' "$1"
  [ -z "$2" ] || printf 'Lens-pass: %s\n' "$2"
  # shellcheck disable=SC2016 # literal backticks: the record format
  printf 'Anchor: `%s` — computed as\n`%s`\n' "$3" "$4"
}

# seed <case-dir> [<entry-mode>] — a bare origin and a primary clone holding a
# Ready bundle `specs/demo` whose kickoff brief carries one sign-off record.
# entry-mode: good (default), stale (records a hash that does not match),
# none (no anchor entry), nolens (meaning-class, no Lens-pass), badcmd (a
# command naming another bundle), bare (a matching newest entry with no Class
# of its own after a full older record). Sets C (case dir) and P (primary).
seed() {
  C=$tmp/$1
  mode=${2:-good}
  mkdir -p "$C/rec" "$C/hstate"
  git -c init.defaultBranch=main init -q --bare "$C/origin.git"
  git clone -q "$C/origin.git" "$C/primary" 2>/dev/null
  P=$C/primary
  mkdir -p "$P/specs/demo"
  for f in requirements design test-spec; do
    printf '# Demo %s\n\n**Status:** Ready\n\nBody of %s.\n' "$f" "$f" >"$P/specs/demo/$f.md"
  done
  printf '# Demo tasks\n\n**Status:** Ready\n\n## Tasks\n\n### Task 1 — Do the thing\n\n- **Deliverables:** a thing\n- **Done when:** it exists\n- **Dependencies:** none\n- **Citations:** D-1\n- **Estimated effort:** 1 day\n' \
    >"$P/specs/demo/tasks.md"
  anchor=$(cd "$P" && "$SCRIPTS/spec-anchor.sh" specs/demo) || {
    fail "seed: spec-anchor.sh failed on the fixture"
    return 1
  }
  {
    printf '# Kickoff brief\n'
    case $mode in
      good) brief_entry meaning '§8 (all findings dispositioned)' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      stale) brief_entry meaning '§8' 0123456789abcdef0123456789abcdef01234567 'scripts/spec-anchor.sh specs/demo' ;;
      none) printf '\nSigned off, but no anchor line.\n' ;;
      nolens) brief_entry meaning '' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      badcmd) brief_entry meaning '§8' "$anchor" 'scripts/spec-anchor.sh specs/other' ;;
      bare)
        brief_entry meaning '§8' 0123456789abcdef0123456789abcdef01234567 'scripts/spec-anchor.sh specs/demo'
        # shellcheck disable=SC2016 # literal backticks: the record format
        printf '\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' "$anchor"
        ;;
    esac
  } >"$P/specs/demo/kickoff-brief.md"
  gitc "$P" add -A
  gitc "$P" commit -q -m "spec"
  gitc "$P" branch -M main
  gitc "$P" push -q origin main
  printf '/planwright:execute-task specs/demo 1\n\nRun notes for the worker.\n' >"$C/prompt"
  FAKE=$C/fake-claude
  cat >"$FAKE" <<EOF
#!/bin/sh
rec="$C/rec"
printf '%s\n' "\$PWD" >>"\$rec/cwd"
printf '%s\n' "\$\$" >"\$rec/claude-pid"
if [ -d "$P/specs/demo/.orchestrate.lock" ]; then echo held >>"\$rec/lock-at-launch"; else echo free >>"\$rec/lock-at-launch"; fi
cat >>"\$rec/stdin"
echo launched >>"\$rec/launches"
exit 0
EOF
  chmod +x "$FAKE"
}

# run_step <args...> — run the step from the primary checkout, isolated from
# the machine's fleet home and marker store. Sets OUT, ERR, RC.
run_step() {
  RC=0
  OUT=$(cd "$P" && env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$C/fleet" \
    PLANWRIGHT_ORCH_STATE_DIR="$C/markers" \
    PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$C/fstate" \
    PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
    PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$C/hstate" \
    "$STEP" "$@" </dev/null 2>"$C/err") || RC=$?
  ERR=$(cat "$C/err")
}

field() {
  printf '%s\n' "$OUT" | awk -F"$TAB" -v k="$1" '$1=="meta-step" && $2==k {print $3; exit}'
}

# wait_launch — the headless runner is detached; give the fake a moment.
wait_launch() {
  i=0
  while [ ! -f "$C/rec/launches" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
  done
}

nothing_created() {
  if gitc "$P" show-ref --verify --quiet refs/heads/planwright/demo/task-1; then
    fail "$1: the task branch was created"
  fi
  [ ! -d "$P/.claude/worktrees/demo-task-1" ] || fail "$1: the worktree was created"
  [ ! -e "$C/markers/1" ] || fail "$1: a dispatch marker was written"
  sleep 0.3
  [ ! -f "$C/rec/launches" ] || fail "$1: a worker was launched"
}

# --- m1: the step launches one /execute-task worker, no tower session ------
m1() {
  begin
  seed m1 || return
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 0 ] || {
    fail "m1: dispatch exited $RC (expected 0): $ERR"
    return
  }
  [ "$(field branch)" = planwright/demo/task-1 ] || fail "m1: branch line '$(field branch)'"
  gitc "$P" show-ref --verify --quiet refs/heads/planwright/demo/task-1 \
    || fail "m1: the task branch was not created"
  [ -f "$C/markers/1" ] || fail "m1: the dispatch marker was not written"
  [ "$(field handle)" = headless-demo-task-1 ] || fail "m1: handle line '$(field handle)'"
  wait_launch
  [ "$(wc -l <"$C/rec/launches" 2>/dev/null | tr -d ' ')" = 1 ] \
    || fail "m1: expected exactly one worker launch"
  wt=$(cd "$P/.claude/worktrees/demo-task-1" 2>/dev/null && pwd -P)
  [ "$(cat "$C/rec/cwd" 2>/dev/null)" = "$wt" ] \
    || fail "m1: the worker did not start in the unit's worktree ($(cat "$C/rec/cwd" 2>/dev/null))"
  head -n 1 "$C/rec/stdin" 2>/dev/null | grep -q '^/planwright:execute-task specs/demo 1$' \
    || fail "m1: the worker's prompt is not the /execute-task prompt"
  if grep -q 'orchestrate' "$C/rec/stdin" 2>/dev/null; then
    fail "m1: the launched session was handed a tower prompt"
  fi
  [ ! -d "$P/specs/demo/.orchestrate.lock" ] || fail "m1: the per-spec lock was not released"
  [ "$(cat "$C/rec/lock-at-launch" 2>/dev/null)" = free ] \
    || fail "m1: the worker launched while the per-spec lock was still held"
  [ "$(field gate)" = match ] || fail "m1: gate line '$(field gate)'"
  pass "m1: one /execute-task worker in the unit worktree, lock released before launch"
}

# --- m2: a concurrent single-spec tower's lock excludes the step ----------
m2() {
  begin
  seed m2 || return
  (cd "$P" && "$SCRIPTS/orchestrate-lock.sh" acquire specs/demo) || {
    fail "m2: could not take the lock as the concurrent tower"
    return
  }
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 1 ] || fail "m2: expected exit 1 (lock busy), got $RC: $ERR"
  [ "$(field lock)" = busy ] || fail "m2: lock line '$(field lock)'"
  nothing_created m2
  [ -d "$P/specs/demo/.orchestrate.lock" ] || fail "m2: the other tower's lock was released"
  (cd "$P" && "$SCRIPTS/orchestrate-lock.sh" release specs/demo)
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 0 ] || fail "m2: after the holder released, dispatch exited $RC: $ERR"
  pass "m2: a held per-spec lock is a clean no-op; the step runs once it is free"
}

# --- m3: the step holds the lock across the dispatch record ---------------
# The step takes the lock itself, not only respects it: a single-spec tower's
# acquire attempted while the record is being written finds it busy. The
# record primitive is wrapped in a copy of the scripts tree so the probe runs
# at exactly that point; racing two real processes instead would measure the
# host's mkdir, not this script.
m3() {
  begin
  seed m3 || return
  root=$C/root
  mkdir -p "$root"
  cp -R "$SCRIPTS" "$root/scripts"
  cp -R "$SCRIPTS/../config" "$root/config"
  mv "$root/scripts/fleet-dispatch-worktree.sh" "$root/scripts/fleet-dispatch-worktree.real.sh"
  cat >"$root/scripts/fleet-dispatch-worktree.sh" <<EOF
#!/bin/sh
rc=0
(cd "$P" && "$root/scripts/orchestrate-lock.sh" acquire specs/demo) >/dev/null 2>&1 || rc=\$?
echo "\$rc" >"$C/rec/tower-during-record"
[ "\$rc" -ne 0 ] || (cd "$P" && "$root/scripts/orchestrate-lock.sh" release specs/demo)
exec "$root/scripts/fleet-dispatch-worktree.real.sh" "\$@"
EOF
  chmod +x "$root/scripts/fleet-dispatch-worktree.sh"
  real_step=$STEP
  STEP=$root/scripts/orchestrate-meta-step.sh
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
  STEP=$real_step
  [ "$RC" -eq 0 ] || fail "m3: dispatch exited $RC: $ERR"
  [ "$(cat "$C/rec/tower-during-record" 2>/dev/null)" = 1 ] \
    || fail "m3: a single-spec tower could take the lock during the record (acquire exit $(cat "$C/rec/tower-during-record" 2>/dev/null))"
  [ ! -d "$P/specs/demo/.orchestrate.lock" ] || fail "m3: the per-spec lock was left behind"
  pass "m3: a single-spec tower is excluded while the step writes the record"
}

# --- m4: freshness-gate halts park with nothing created -------------------
m4() {
  begin
  for mode in stale none nolens badcmd bare; do
    seed "m4-$mode" "$mode" || continue
    run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
    [ "$RC" -eq 4 ] || fail "m4/$mode: expected exit 4 (park), got $RC: $ERR"
    printf '%s\n' "$OUT" | grep -q "^halt${TAB}" || fail "m4/$mode: no halt line: $OUT"
    nothing_created "m4/$mode"
    [ ! -d "$P/specs/demo/.orchestrate.lock" ] || fail "m4/$mode: the lock was not released"
  done
  # An uncommitted-to-origin edit to anchored content after sign-off.
  seed m4-edit || return
  printf 'A new requirement.\n' >>"$P/specs/demo/requirements.md"
  gitc "$P" commit -q -am "edit"
  gitc "$P" push -q origin main
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 4 ] || fail "m4/edit: an edit after sign-off should park (exit 4), got $RC"
  nothing_created m4/edit
  pass "m4: gate halts (mismatch, no entry, no lens pass, foreign command, edit) park cleanly"
}

# --- m5: refusals before any side effect ----------------------------------
m5() {
  begin
  seed m5 || return
  printf '/orchestrate specs/demo\n' >"$C/tower-prompt"
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/tower-prompt"
  [ "$RC" -eq 2 ] || fail "m5: a tower prompt should be refused (exit 2), got $RC"
  nothing_created m5/tower-prompt
  [ ! -d "$P/specs/demo/.orchestrate.lock" ] || fail "m5: a refusal took the lock"
  for args in "specs/demo 1-2" "specs/demo ../1" "specs/Bad 1" "specs/demo 1 --backend subagent"; do
    # shellcheck disable=SC2086 # word-split on purpose: each case is an argv
    set -- $args
    case $args in *--backend*) extra= ;; *) extra="--backend headless-oneshot" ;; esac
    # shellcheck disable=SC2086
    run_step dispatch "$@" $extra --prompt-file "$C/prompt"
    [ "$RC" -eq 2 ] || fail "m5: '$args' should be refused (exit 2), got $RC"
  done
  nothing_created m5/args
  pass "m5: a tower prompt, a bad id or spec, and an unwired rung are refused up front"
}

m1
m2
m3
m4
m5

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-orchestrate-meta-step.sh"
