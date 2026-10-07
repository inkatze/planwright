#!/bin/bash
# Tests for scripts/orchestrate-meta-step.sh — the meta-tower's single-spec
# step, run in the meta-tower's own session (REQ-G1.5, D-17). The usage and
# exit codes under test are the script header's.
#
# Contract under test:
#   - takes the per-spec lock (scripts/orchestrate-lock.sh), runs the
#     freshness gate, writes the dispatch record (branch, then marker), and
#     releases the lock before the worker launches;
#   - launches exactly one worker, running /execute-task, in the unit's
#     worktree; a prompt that would start anything else (a /orchestrate
#     tower) is refused before any side effect;
#   - a lock another tower holds, or a unit already in flight, is a clean
#     no-op (exit 1): nothing created, nothing launched;
#   - a freshness-gate halt parks (exit 4) with its own reason, nothing
#     created and the lock released;
#   - a failed launch clears the marker (exit 6), except where the rung
#     reports a live worker for the unit, which keeps it.
#
# The worker CLI is a recording fake (PLANWRIGHT_HEADLESS_CLAUDE) on the
# headless-oneshot rung, and the stream-json rung is a recording stub, so no
# model call is made.
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

WHOLE_FILE='git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin'
STALE=0123456789abcdef0123456789abcdef01234567

# seed <case-dir> [<entry-mode>] — a bare origin and a primary clone holding a
# Ready bundle `specs/demo` whose kickoff brief carries one sign-off record.
# Entry modes and the halt each should produce are listed beside m4. Sets C
# (case dir), P (primary) and FAKE (the worker CLI).
seed() {
  C=$tmp/$1
  seed_mode=${2:-good}
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
    case $seed_mode in
      good) brief_entry meaning '§8 (all findings dispositioned)' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      bareform) brief_entry meaning '§8' "$anchor" 'spec-anchor.sh specs/demo' ;;
      expronly) brief_entry expression-only '' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      stale) brief_entry meaning '§8' "$STALE" 'scripts/spec-anchor.sh specs/demo' ;;
      none) printf '\nSigned off, but no anchor line.\n' ;;
      unparseable)
        brief_entry meaning '§8' "$anchor" 'scripts/spec-anchor.sh specs/demo'
        printf '\nClass: meaning\nLens-pass: §9\nAnchor: `%s` — computed as\n' "$anchor"
        ;;
      nolens) brief_entry meaning '' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      badcmd) brief_entry meaning '§8' "$anchor" 'scripts/spec-anchor.sh specs/other' ;;
      wholefile) brief_entry meaning '§8' "$anchor" "$WHOLE_FILE" ;;
      bare)
        brief_entry meaning '§8' "$STALE" 'scripts/spec-anchor.sh specs/demo'
        # shellcheck disable=SC2016 # literal backticks: the record format
        printf '\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' "$anchor"
        ;;
      dup)
        printf '\nClass: expression-only\n'
        brief_entry meaning '§8' "$anchor" 'scripts/spec-anchor.sh specs/demo'
        ;;
      fenced)
        printf '\nClass: meaning\n```\nClass: expression-only\n```\n'
        # shellcheck disable=SC2016 # literal backticks: the record format
        printf 'Anchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' "$anchor"
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

# copy_root — a copy of the scripts and config trees under $C/root, so a case
# can replace one sibling primitive with a stub. Sets STEP_COPY.
copy_root() {
  mkdir -p "$C/root"
  cp -R "$SCRIPTS" "$C/root/scripts"
  cp -R "$SCRIPTS/../config" "$C/root/config"
  STEP_COPY=$C/root/scripts/orchestrate-meta-step.sh
}

# run_step <args...> — run the step ($RUN_STEP, default the real script) from
# the primary checkout, isolated from the machine's fleet home and marker
# store. Sets OUT, ERR, RC.
run_step() {
  RC=0
  OUT=$(cd "$P" && env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$C/fleet" \
    PLANWRIGHT_ORCH_STATE_DIR="$C/markers" \
    PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$C/fstate" \
    PLANWRIGHT_DISPATCH_FETCH_RETRIES=0 \
    PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
    PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$C/hstate" \
    "${RUN_STEP:-$STEP}" "$@" </dev/null 2>"$C/err") || RC=$?
  ERR=$(cat "$C/err")
}

dispatch() {
  run_step dispatch specs/demo 1 --backend "${1:-headless-oneshot}" --prompt-file "$C/prompt"
}

field() {
  printf '%s\n' "$OUT" | awk -F"$TAB" -v k="$1" '$1=="meta-step" && $2==k {print $3; exit}'
}

halt_reason() {
  printf '%s\n' "$OUT" | awk -F"$TAB" '$1=="halt" {print $2 "/" $3; exit}'
}

# wait_launch — the headless runner is detached; give the fake a moment.
wait_launch() {
  i=0
  while [ ! -f "$C/rec/launches" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
  done
}

# nothing_created <label> — no branch, worktree, marker, or launch record.
# The headless launcher writes its unit directory before it returns, so its
# absence shows no launch began without waiting on the detached fake.
nothing_created() {
  if gitc "$P" show-ref --verify --quiet refs/heads/planwright/demo/task-1; then
    fail "$1: the task branch was created"
  fi
  [ ! -d "$P/.claude/worktrees/demo-task-1" ] || fail "$1: the worktree was created"
  [ ! -e "$C/markers/1" ] || fail "$1: a dispatch marker was written"
  [ ! -e "$C/hstate/1" ] || fail "$1: a worker launch began"
}

lock_released() {
  [ ! -d "$P/specs/demo/.orchestrate.lock" ] || fail "$1: the per-spec lock was not released"
}

# --- m1: the step launches one /execute-task worker, no tower session ------
m1() {
  begin
  seed m1 || return
  dispatch
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
  lock_released m1
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
  dispatch
  [ "$RC" -eq 1 ] || fail "m2: expected exit 1 (lock busy), got $RC: $ERR"
  [ "$(field lock)" = busy ] || fail "m2: lock line '$(field lock)'"
  nothing_created m2
  [ -d "$P/specs/demo/.orchestrate.lock" ] || fail "m2: the other tower's lock was released"
  (cd "$P" && "$SCRIPTS/orchestrate-lock.sh" release specs/demo)
  dispatch
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
  copy_root
  root=$C/root
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
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 0 ] || fail "m3: dispatch exited $RC: $ERR"
  [ "$(cat "$C/rec/tower-during-record" 2>/dev/null)" = 1 ] \
    || fail "m3: a single-spec tower could take the lock during the record (acquire exit $(cat "$C/rec/tower-during-record" 2>/dev/null))"
  lock_released m3
  pass "m3: a single-spec tower is excluded while the step writes the record"
}

# --- m4: freshness-gate halts park with their own reason ------------------
m4() {
  begin
  for pair in stale:gate/mismatch none:gate/no-entry unparseable:gate/unparseable-entry \
    nolens:gate/no-lens-pass badcmd:gate/non-sanctioned-command \
    wholefile:gate/pre-change-entry bare:gate/non-sanctioned-writer \
    dup:gate/unparseable-entry fenced:gate/no-lens-pass; do
    mode=${pair%%:*}
    want=${pair#*:}
    seed "m4-$mode" "$mode" || continue
    dispatch
    [ "$RC" -eq 4 ] || fail "m4/$mode: expected exit 4 (park), got $RC: $ERR"
    [ "$(halt_reason)" = "$want" ] || fail "m4/$mode: halt '$(halt_reason)', expected '$want'"
    printf '%s\n' "$OUT" | grep -q "^remedy${TAB}" || fail "m4/$mode: no remedy line"
    nothing_created "m4/$mode"
    lock_released "m4/$mode"
  done
  # An edit to anchored content, committed and pushed after sign-off.
  seed m4-edit || return
  printf 'A new requirement.\n' >>"$P/specs/demo/requirements.md"
  gitc "$P" commit -q -am "edit"
  gitc "$P" push -q origin main
  dispatch
  [ "$RC" -eq 4 ] || fail "m4/edit: an edit after sign-off should park (exit 4), got $RC"
  [ "$(halt_reason)" = gate/mismatch ] || fail "m4/edit: halt '$(halt_reason)'"
  nothing_created m4/edit
  pass "m4: each gate halt parks with its own reason, nothing created"
}

# --- m5: refusals before any side effect ----------------------------------
m5() {
  begin
  seed m5 || return
  printf '/orchestrate specs/demo\n' >"$C/tower-prompt"
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/tower-prompt"
  [ "$RC" -eq 2 ] || fail "m5: a tower prompt should be refused (exit 2), got $RC"
  lock_released m5/tower-prompt
  mkdir -p "$P/specs/Bad" "$P/specs/flight" "$C/elsewhere/specs/demo"
  nl_id=$(printf '1\nx')
  for args in "specs/demo 1-2" "specs/demo ../1" "specs/Bad 1" "specs/flight 1" \
    "$C/elsewhere/specs/demo 1"; do
    # shellcheck disable=SC2086 # word-split on purpose: each case is an argv
    run_step dispatch $args --backend headless-oneshot --prompt-file "$C/prompt"
    [ "$RC" -eq 2 ] || fail "m5: '$args' should be refused (exit 2), got $RC"
  done
  run_step dispatch specs/demo "$nl_id" --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 2 ] || fail "m5: a task id carrying a newline should be refused (exit 2), got $RC"
  for rung in tmux subagent print; do
    dispatch "$rung"
    [ "$RC" -eq 2 ] || fail "m5: rung '$rung' should be refused (exit 2), got $RC"
  done
  nothing_created m5
  [ ! -d "$C/fstate" ] || fail "m5: a refusal ran the fetch"
  pass "m5: a tower prompt, a bad id or spec, a foreign spec dir, and an unwired rung are refused up front"
}

# --- m6: valid entries in the other sanctioned shapes dispatch ------------
m6() {
  begin
  for mode in expronly bareform; do
    seed "m6-$mode" "$mode" || continue
    dispatch
    [ "$RC" -eq 0 ] || fail "m6/$mode: expected a dispatch (exit 0), got $RC: $(halt_reason)"
  done
  pass "m6: an expression-only entry and the bare spec-anchor.sh form dispatch"
}

# --- m7: a failed launch clears the marker --------------------------------
m7() {
  begin
  seed m7 || return
  FAKE=$C/no-such-claude
  dispatch
  [ "$RC" -eq 6 ] || fail "m7: a failed launch should exit 6, got $RC: $ERR"
  [ "$(halt_reason | cut -d/ -f1)" = launch ] || fail "m7: halt '$(halt_reason)'"
  [ ! -e "$C/markers/1" ] || fail "m7: the marker survived a launch that started nothing"
  [ -d "$P/.claude/worktrees/demo-task-1" ] || fail "m7: the placed worktree was removed"
  lock_released m7
  pass "m7: a failed launch clears the marker and leaves the worktree"
}

# --- m8: a rung reporting a live worker keeps the marker ------------------
m8() {
  begin
  seed m8 || return
  copy_root
  printf '#!/bin/sh\ncat >/dev/null\necho "already in flight" >&2\nexit 3\n' >"$C/root/scripts/fleet-dispatch-headless.sh"
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 6 ] || fail "m8: a rung exit 3 should exit 6, got $RC: $ERR"
  [ -e "$C/markers/1" ] || fail "m8: the marker of a live worker was cleared"
  pass "m8: a rung that reports a live worker keeps its marker"
}

# --- m9: a unit already in flight is a clean no-op ------------------------
m9() {
  begin
  seed m9 || return
  dispatch
  [ "$RC" -eq 0 ] || fail "m9: first dispatch exited $RC: $ERR"
  wait_launch
  dispatch
  [ "$RC" -eq 1 ] || fail "m9: a second dispatch of an in-flight unit should exit 1, got $RC: $ERR"
  [ "$(field record)" = in-flight ] || fail "m9: record line '$(field record)'"
  [ -e "$C/markers/1" ] || fail "m9: the in-flight unit lost its marker"
  lock_released m9
  pass "m9: re-dispatching an in-flight unit is a clean no-op"
}

# --- m10: the fetch's offline and stale answers ---------------------------
m10() {
  begin
  seed m10-offline || return
  gitc "$P" remote remove origin
  dispatch
  [ "$RC" -eq 0 ] || fail "m10/offline: no remote should gate against local main and dispatch, got $RC: $(halt_reason)"
  [ "$(field ref)" = main ] || fail "m10/offline: ref '$(field ref)', expected main"
  seed m10-stale || return
  gitc "$P" remote set-url origin "$C/gone.git"
  dispatch
  [ "$RC" -eq 4 ] || fail "m10/stale: an unreachable remote should park, got $RC"
  [ "$(halt_reason)" = fetch/stale-transient ] || fail "m10/stale: halt '$(halt_reason)'"
  nothing_created m10/stale
  pass "m10: offline gates against local main; an unreachable remote parks"
}

# --- m11: the stream-json rung gets the worktree, scope, and prompt -------
m11() {
  begin
  seed m11 || return
  copy_root
  cat >"$C/root/scripts/fleet-streamjson.sh" <<EOF
#!/bin/sh
: >"$C/rec/sj-argv"
for a in "\$@"; do printf '%s\n' "\$a" >>"$C/rec/sj-argv"; done
while [ "\$#" -gt 0 ]; do
  [ "\$1" = --prompt-file ] && cp "\$2" "$C/rec/sj-prompt"
  shift
done
exit 0
EOF
  RUN_STEP=$STEP_COPY dispatch stream-json-persistent
  [ "$RC" -eq 0 ] || fail "m11: stream-json dispatch exited $RC: $ERR"
  wt=$(cd "$P/.claude/worktrees/demo-task-1" 2>/dev/null && pwd -P)
  [ "$(sed -n 1p "$C/rec/sj-argv")" = launch ] || fail "m11: not a launch call"
  [ "$(sed -n 2p "$C/rec/sj-argv")" = demo-task-1 ] || fail "m11: worker '$(sed -n 2p "$C/rec/sj-argv")'"
  [ "$(sed -n 3p "$C/rec/sj-argv")" = demo:task-1 ] || fail "m11: scope '$(sed -n 3p "$C/rec/sj-argv")'"
  grep -qx -- "$wt" "$C/rec/sj-argv" || fail "m11: --cwd is not the unit worktree"
  cmp -s "$C/prompt" "$C/rec/sj-prompt" || fail "m11: the worker did not receive the screened prompt"
  [ "$(field handle)" = demo-task-1 ] || fail "m11: handle line '$(field handle)'"
  pass "m11: the stream-json rung launches in the unit worktree with the prompt"
}

m1
m2
m3
m4
m5
m6
m7
m8
m9
m10
m11

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-orchestrate-meta-step.sh"
