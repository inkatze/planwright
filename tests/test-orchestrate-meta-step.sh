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
#   - a failed launch clears the marker (exit 6), except where the rung may
#     hold a worker for the unit, which keeps it;
#   - a signal during the launch keeps the marker;
#   - an incomplete record report (exit 5) and a signal landing after the
#     record clear the marker the record stamped;
#   - only the screened copy of the prompt reaches the worker, and a rung's
#     message reaches stderr with control bytes stripped;
#   - expression-only and bare-form entries dispatch; with no remote the gate
#     reads local main, while an unreachable remote or an unresolved anchor
#     parks;
#   - a silent headless launch still reports the rung's handle form;
#   - a bad task id or spec name and an unwired rung are refused;
#   - a lock or fetch refusal, a relocated spec root, or a --repo-root other
#     than the primary checkout is refused (exit 2) before anything is placed.
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
SCRIPTS=$(cd "$here/../scripts" && pwd -P)
CONFIG=$(cd "$here/../config" && pwd -P)
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
    # A pid file can outlive its process, and the pid be reused: signal only
    # a process whose command line names this run's directory.
    case $(ps -ww -o args= -p "$p" 2>/dev/null) in
      *"$tmp"*) kill -9 "$p" 2>/dev/null ;;
    esac
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
# The bundle and its repositories are built once; each case copies them and
# repoints the clone at its own origin, so only the brief commit is per case.
TEMPLATE=$tmp/.template
build_template() {
  git -c init.defaultBranch=main init -q --bare "$TEMPLATE/origin.git"
  git clone -q "$TEMPLATE/origin.git" "$TEMPLATE/primary" 2>/dev/null
  mkdir -p "$TEMPLATE/primary/specs/demo"
  for f in requirements design test-spec; do
    printf '# Demo %s\n\n**Status:** Ready\n\nBody of %s.\n' "$f" "$f" >"$TEMPLATE/primary/specs/demo/$f.md"
  done
  printf '# Demo tasks\n\n**Status:** Ready\n\n## Tasks\n\n### Task 1 — Do the thing\n\n- **Deliverables:** a thing\n- **Done when:** it exists\n- **Dependencies:** none\n- **Citations:** D-1\n- **Estimated effort:** 1 day\n' \
    >"$TEMPLATE/primary/specs/demo/tasks.md"
  gitc "$TEMPLATE/primary" add -A
  gitc "$TEMPLATE/primary" commit -q -m "bundle"
  gitc "$TEMPLATE/primary" branch -M main
  gitc "$TEMPLATE/primary" push -q origin main
  anchor=$(cd "$TEMPLATE/primary" && "$SCRIPTS/spec-anchor.sh" specs/demo) || {
    echo "FAIL: spec-anchor.sh failed on the fixture" >&2
    exit 1
  }
}
build_template

seed() {
  C=$tmp/$1
  seed_mode=${2:-good}
  mkdir -p "$C/rec" "$C/hstate"
  cp -R "$TEMPLATE/origin.git" "$C/origin.git"
  cp -R "$TEMPLATE/primary" "$C/primary"
  P=$C/primary
  gitc "$P" remote set-url origin "$C/origin.git"
  gitc "$P" fetch -q origin
  brief "$seed_mode"
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

# brief <entry-mode> — write, commit and push the case's kickoff brief for one
# entry mode (nobrief removes it), replacing whatever brief the case had.
brief() {
  {
    printf '# Kickoff brief\n'
    case $1 in
      good) brief_entry meaning '§8 (all findings dispositioned)' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      bareform) brief_entry meaning '§8' "$anchor" 'spec-anchor.sh specs/demo' ;;
      expronly) brief_entry expression-only '' "$anchor" 'scripts/spec-anchor.sh specs/demo' ;;
      stale) brief_entry meaning '§8' "$STALE" 'scripts/spec-anchor.sh specs/demo' ;;
      none) printf '\nSigned off, but no anchor line.\n' ;;
      unparseable)
        brief_entry meaning '§8' "$anchor" 'scripts/spec-anchor.sh specs/demo'
        # shellcheck disable=SC2016 # literal backticks: the record format
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
        # shellcheck disable=SC2016 # literal backticks: a fence
        printf '\nClass: meaning\n```\nClass: expression-only\n```\n'
        # shellcheck disable=SC2016 # literal backticks: the record format
        printf 'Anchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' "$anchor"
        ;;
    esac
  } >"$P/specs/demo/kickoff-brief.md"
  [ "$1" != nobrief ] || rm -f "$P/specs/demo/kickoff-brief.md"
  gitc "$P" add -A
  gitc "$P" commit -q --allow-empty -m "brief $1"
  gitc "$P" push -q origin main
}

# copy_root — a copy of the scripts and config trees under $C/root, so a case
# can replace one sibling primitive with a stub. The trees are copied by
# content into fresh directories: copying a symlinked tree as a link would
# let the stubs overwrite the real scripts. Sets STEP_COPY.
copy_root() {
  mkdir -p "$C/root/scripts" "$C/root/config"
  cp -R "$SCRIPTS/." "$C/root/scripts/"
  cp -R "$CONFIG/." "$C/root/config/"
  if [ -L "$C/root/scripts" ] || [ -L "$C/root/config" ]; then
    echo "FAIL: copy_root produced a symlinked tree; refusing to stub through it" >&2
    exit 1
  fi
  STEP_COPY=$C/root/scripts/orchestrate-meta-step.sh
}

# stub <name> <body> — replace one sibling in the copied tree with a shell
# script whose body is <body>.
stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$C/root/scripts/$1"
  chmod +x "$C/root/scripts/$1"
}

# wrap_record <before> — run <before> inside the record primitive's process,
# then the real primitive.
wrap_record() {
  mv "$C/root/scripts/fleet-dispatch-worktree.sh" "$C/root/scripts/fleet-dispatch-worktree.real.sh"
  stub fleet-dispatch-worktree.sh "$1
exec \"$C/root/scripts/fleet-dispatch-worktree.real.sh\" \"\$@\""
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
  wrap_record "rc=0
(cd \"$P\" && \"$C/root/scripts/orchestrate-lock.sh\" acquire specs/demo) >/dev/null 2>&1 || rc=\$?
echo \"\$rc\" >\"$C/rec/tower-during-record\"
[ \"\$rc\" -ne 0 ] || (cd \"$P\" && \"$C/root/scripts/orchestrate-lock.sh\" release specs/demo)"
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
  # Every gate halt creates nothing, so one case serves every mode: each
  # iteration only re-briefs it.
  seed m4 || return
  for pair in stale:gate/mismatch none:gate/no-entry unparseable:gate/unparseable-entry \
    nolens:gate/no-lens-pass badcmd:gate/non-sanctioned-command \
    wholefile:gate/pre-change-entry bare:gate/non-sanctioned-writer \
    dup:gate/unparseable-entry fenced:gate/no-lens-pass nobrief:gate/no-brief; do
    mode=${pair%%:*}
    want=${pair#*:}
    brief "$mode"
    dispatch
    [ "$RC" -eq 4 ] || fail "m4/$mode: expected exit 4 (park), got $RC: $ERR"
    [ "$(halt_reason)" = "$want" ] || fail "m4/$mode: halt '$(halt_reason)', expected '$want'"
    printf '%s\n' "$OUT" | grep -q "^remedy${TAB}" || fail "m4/$mode: no remedy line"
    nothing_created "m4/$mode"
    lock_released "m4/$mode"
  done
  # An edit to anchored content, committed and pushed after sign-off.
  brief good
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
  # A linked worktree's copy of the bundle is a valid spec dir for the lock
  # primitive, so only the primary-bundle check refuses it.
  gitc "$P" worktree add -q --detach "$C/wt2" main
  run_step dispatch "$C/wt2/specs/demo" 1 --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 2 ] || fail "m5: a linked worktree's bundle should be refused (exit 2), got $RC"
  printf '%s\n' "$ERR" | grep -q "not the primary checkout's bundle" \
    || fail "m5: the linked-worktree refusal names another reason: $ERR"
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt" --repo-root ""
  [ "$RC" -eq 2 ] || fail "m5: an empty --repo-root should be refused (exit 2), got $RC"
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
  stub fleet-dispatch-headless.sh 'cat >/dev/null
printf "already in flight \033[31mX \233[32mY \302\233Z \342\200\224 kept\n" >&2
exit 3'
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 6 ] || fail "m8: a rung exit 3 should exit 6, got $RC: $ERR"
  [ -e "$C/markers/1" ] || fail "m8: the marker of a live worker was cleared"
  halt_reason | grep -q "marker is kept" || fail "m8: halt '$(halt_reason)' does not say the marker is kept"
  [ -d "$P/.claude/worktrees/demo-task-1" ] || fail "m8: the placed worktree was removed"
  printf '%s\n' "$ERR" | grep -q "already in flight" || fail "m8: the rung's message was not relayed"
  esc=$(printf '\033')
  case $ERR in *"$esc"*) fail "m8: a control byte from the rung reached stderr" ;; esac
  if printf '%s' "$ERR" | LC_ALL=C grep -q "$(printf '\233')"; then
    fail "m8: a C1 control from the rung reached stderr"
  fi
  printf '%s\n' "$ERR" | grep -q "$(printf '\342\200\224') kept" \
    || fail "m8: valid UTF-8 in the rung's message was mangled"
  pass "m8: a rung that reports a live worker keeps its marker; its message is relayed clean"
}

# --- m12: a written record whose report lacks the worktree exits 5 --------
m12() {
  begin
  seed m12 || return
  copy_root
  mv "$C/root/scripts/fleet-dispatch-worktree.sh" "$C/root/scripts/fleet-dispatch-worktree.real.sh"
  stub fleet-dispatch-worktree.sh "\"$C/root/scripts/fleet-dispatch-worktree.real.sh\" \"\$@\" | grep -v '^dispatch${TAB}worktree'
exit 0"
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 5 ] || fail "m12: a record with no worktree line should exit 5, got $RC"
  [ "$(halt_reason)" = "record/no worktree reported" ] || fail "m12: halt '$(halt_reason)'"
  [ ! -e "$C/markers/1" ] || fail "m12: the marker the record stamped survived"
  [ ! -e "$C/hstate/1" ] || fail "m12: a worker launch began"
  lock_released m12
  pass "m12: an incomplete record report exits 5 and clears its marker"
}

# --- m13: a signal after the record stamps its marker clears it -----------
m13() {
  begin
  seed m13 || return
  copy_root
  mv "$C/root/scripts/fleet-dispatch-worktree.sh" "$C/root/scripts/fleet-dispatch-worktree.real.sh"
  stub fleet-dispatch-worktree.sh "\"$C/root/scripts/fleet-dispatch-worktree.real.sh\" \"\$@\"
rc=\$?
kill -TERM \$PPID
exit \$rc"
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 143 ] || fail "m13: a TERM during the record should exit 143, got $RC"
  [ ! -e "$C/markers/1" ] || fail "m13: the marker survived a TERM with no launch behind it"
  [ ! -e "$C/hstate/1" ] || fail "m13: a worker launch began"
  lock_released m13
  pass "m13: a TERM landing after the record clears the marker and the lock"
}

# --- m14: the launch reads the screened copy, not the caller's file -------
m14() {
  begin
  seed m14 || return
  copy_root
  wrap_record "printf '/orchestrate specs/demo\n' >\"$C/prompt\""
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 0 ] || fail "m14: dispatch exited $RC: $ERR"
  wait_launch
  head -n 1 "$C/rec/stdin" 2>/dev/null | grep -q '^/planwright:execute-task specs/demo 1$' \
    || fail "m14: a prompt swapped after the screen reached the worker"
  # A prompt path that starts with a dash is a path, not a cp option.
  seed m14-dash || return
  cp "$C/prompt" "$P/-prompt"
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file -prompt
  [ "$RC" -eq 0 ] || fail "m14: a prompt path starting with a dash was refused ($RC): $ERR"
  pass "m14: only the screened prompt reaches the worker, whatever its path looks like"
}

# --- m15: lock and fetch refusals --------------------------------------------
m15() {
  begin
  seed m15 || return
  copy_root
  stub dispatch-fetch.sh 'echo "refused" >&2; exit 2'
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 2 ] || fail "m15: a fetch refusal should exit 2, got $RC"
  [ -z "$(halt_reason)" ] || fail "m15: a fetch refusal parked as '$(halt_reason)'"
  lock_released m15/fetch2
  stub dispatch-fetch.sh 'exit 5'
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 4 ] || fail "m15: an unresolved anchor should park, got $RC"
  [ "$(halt_reason)" = fetch/anchor-unresolved ] || fail "m15: halt '$(halt_reason)'"
  # shellcheck disable=SC2016 # the stub body expands in the stub, not here
  stub orchestrate-lock.sh '[ "$1" = acquire ] && exit 2; exit 0'
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 2 ] || fail "m15: a lock refusal should exit 2, got $RC"
  nothing_created m15
  pass "m15: a lock or fetch refusal exits 2; an unresolved anchor parks"
}

# --- m16: a headless launch that reports no handle still names one --------
m16() {
  begin
  seed m16 || return
  copy_root
  stub fleet-dispatch-headless.sh 'cat >/dev/null; exit 0'
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 0 ] || fail "m16: dispatch exited $RC: $ERR"
  [ "$(field handle)" = headless-demo-task-1 ] || fail "m16: handle '$(field handle)'"
  pass "m16: a silent headless launch reports the rung's handle form"
}

# --- m17: stream-json failures clear or keep the marker by meaning --------
m17() {
  begin
  # Exit 2 keeps the marker only with the startup-timeout message; a refusal
  # before any spawn exits 2 too and launched nothing.
  for pair in 1:clear:x 2:clear:refused 2:keep:did-not-start 3:keep:x; do
    code=${pair%%:*}
    rest=${pair#*:}
    want=${rest%%:*}
    msg=${rest#*:}
    [ "$msg" != did-not-start ] || msg='detached supervisor did not start within 5s'
    seed "m17-$code-$want" || continue
    copy_root
    stub fleet-streamjson.sh "echo '$msg' >&2; exit $code"
    RUN_STEP=$STEP_COPY dispatch stream-json-persistent
    [ "$RC" -eq 6 ] || fail "m17/$code: expected exit 6, got $RC"
    if [ "$want" = clear ]; then
      [ ! -e "$C/markers/1" ] || fail "m17/$code: the marker survived a launch that started nothing"
    else
      [ -e "$C/markers/1" ] || fail "m17/$code: the marker of a possibly live worker was cleared"
    fi
  done
  pass "m17: stream-json keeps the marker only on exit 3 or its startup timeout"
}

# --- m19: a signal during the launch keeps the marker ---------------------
# Once the launch has begun a worker may exist, so the marker that holds the
# unit in flight is kept; clearing it could let a later dispatch reclaim a
# live worker's worktree.
m19() {
  begin
  seed m19 || return
  copy_root
  # shellcheck disable=SC2016 # the stub body expands in the stub, not here
  stub fleet-dispatch-headless.sh 'cat >/dev/null
kill -TERM $PPID
exit 0'
  RUN_STEP=$STEP_COPY dispatch
  [ "$RC" -eq 143 ] || fail "m19: a TERM during the launch should exit 143, got $RC"
  [ -e "$C/markers/1" ] || fail "m19: the marker was cleared under a possibly live worker"
  lock_released m19
  pass "m19: a TERM during the launch keeps the marker and releases the lock"
}

# --- m18: the primary checkout and the default spec root are required -----
m18() {
  begin
  seed m18 || return
  PLANWRIGHT_REPO_ROOT=$tmp run_step dispatch specs/demo 1 --backend headless-oneshot \
    --prompt-file "$C/prompt" --repo-root "$P"
  [ "$RC" -eq 0 ] || fail "m18: an inherited PLANWRIGHT_REPO_ROOT should not override --repo-root, got $RC: $ERR"
  seed m18-linked || return
  gitc "$P" worktree add -q --detach "$C/wt2" main
  run_step dispatch specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt" --repo-root "$C/wt2"
  [ "$RC" -eq 2 ] || fail "m18: a linked worktree as --repo-root should be refused, got $RC"
  printf '%s\n' "$ERR" | grep -q "not the primary checkout" || fail "m18: wrong refusal: $ERR"
  seed m18-relocated || return
  mkdir -p "$P/.claude" "$P/docs/specs"
  printf 'spec_root: docs/specs\n' >"$P/.claude/planwright.local.yml"
  printf 'project: relocated\nlayout: 1\n' >"$P/docs/specs/planwright-spec-root.yml"
  cp -R "$P/specs/demo" "$P/docs/specs/demo"
  run_step dispatch docs/specs/demo 1 --backend headless-oneshot --prompt-file "$C/prompt"
  [ "$RC" -eq 2 ] || fail "m18: a relocated spec root should be refused, got $RC"
  printf '%s\n' "$ERR" | grep -q "spec root is relocated" || fail "m18: wrong refusal: $ERR"
  [ ! -d "$C/fstate" ] || fail "m18: the relocated-root refusal ran the fetch"
  pass "m18: the step needs the primary checkout and the default root, whatever the environment says"
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
  awk -v wt="$wt" 'prev == "--cwd" && $0 == wt { found = 1 } { prev = $0 } END { exit !found }' "$C/rec/sj-argv" \
    || fail "m11: --cwd is not the unit worktree"
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
m12
m13
m14
m15
m16
m17
m18
m19

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-orchestrate-meta-step.sh"
