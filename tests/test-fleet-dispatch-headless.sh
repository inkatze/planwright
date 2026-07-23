#!/bin/bash
# Tests for the headless-oneshot dispatch primitive
# (execution-backends Task 3; D-3, D-12; REQ-A1.2, REQ-A1.5, REQ-A1.9).
#
# scripts/fleet-dispatch-headless.sh launches a detached one-shot worker
# (`claude --print`) into an existing worktree and gives the tower a
# consumable completion signal plus positive-evidence-of-death liveness. The
# suite drives the REAL primitive against a recording fake CLI
# (PLANWRIGHT_HEADLESS_CLAUDE), so every contract clause is asserted on the
# launched process's actual environment, argv, stdin, and lifecycle — never
# on prose.
#
# Coverage (mapped to the task Done-when and the test-spec entries):
#   h1 (REQ-A1.9): the launch is detached and the prompt reaches the worker
#      as STDIN DATA — a metacharacter prompt ($(...), backticks, quotes,
#      newlines) is delivered byte-for-byte and never shell-interpolated.
#      The worker runs in the worktree cwd through fleet-dispatch-env.sh
#      (ghost pin) with the identity env (handle/scope) exported, and the
#      argv carries the pinned flags: `--print --output-format json`, never
#      `--bare`, never `--permission-prompt-tool` (REQ-A1.2, REQ-A1.5).
#   h2 (REQ-A1.2): the completion signal — a worker exiting rc=7 yields an
#      `exit` file (`<rc> <epoch>`) and `status` prints `completed 7`.
#   h3 (REQ-A1.2): liveness while in flight — `status` answers `running
#      <pid>` for a live runner, then `completed 0` after it finishes.
#   h4 (REQ-A1.2): positive-evidence-of-death — a killed runner (no exit
#      record) classifies `died`, from the death-evidence predicate, never
#      from silence.
#   h5 (REQ-A1.5, REQ-A1.9): construction-layer refusals — `--bare` or
#      `--permission-prompt-tool` in the passthrough args, an empty prompt,
#      a hostile spec/id, or a missing worktree each exit 2 with nothing
#      launched.
#   h6 (REQ-A1.2): the no-pend permission posture — a worker whose result
#      reports a permission refusal terminates: the failure lands in
#      result.json and the completion signal fires (`completed <rc>`),
#      never a pend.
#   h7: already-in-flight — a second launch for a unit with a live runner
#      is refused (exit 3) and does not disturb the first.
#   h8: status edges — `absent` for a never-dispatched unit; a garbled pid
#      record is `unknown` (refuse to guess), never death.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dispatch-headless.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
FDH="$REPO_ROOT/scripts/fleet-dispatch-headless.sh"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

[ -f "$FDH" ] || {
  echo "FAIL: $FDH missing" >&2
  exit 1
}

# Physical temp path (macOS /var -> /private/var).
tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  # Reap any worker the fixtures left running before removing the tree.
  for pf in "$tmp"/rec-*/claude-pid "$tmp"/state*/*/pid; do
    [ -f "$pf" ] || continue
    p=$(cat "$pf" 2>/dev/null) || continue
    case $p in *[!0-9]* | '') continue ;; esac
    kill -9 "$p" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# run_fdh <args...>: invoke the primitive via /bin/sh (never a temp-script
# direct exec) with a hermetic env.
run_fdh() {
  env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$STATE" \
    /bin/sh "$FDH" "$@"
}

# make_fake <rec-dir>: a recording fake CLI. It records cwd, its own pid,
# argv (one token per line), the ghost-text and identity env, and its full
# stdin; optionally holds (rec/hold present), emits a canned result
# (rec/emit), and exits rec/rc (default 0).
make_fake() {
  mf_rec=$1
  mkdir -p "$mf_rec"
  FAKE="$mf_rec/fake-claude"
  cat >"$FAKE" <<EOF
#!/bin/sh
rec="$mf_rec"
printf '%s\n' "\$PWD" >"\$rec/cwd"
printf '%s\n' "\$\$" >"\$rec/claude-pid"
: >"\$rec/argv"
for a in "\$@"; do printf '%s\n' "\$a" >>"\$rec/argv"; done
printf '%s\n' "\${CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION-<unset>}" >"\$rec/ghost"
printf '%s\n' "\${PLANWRIGHT_WORKER_HANDLE-<unset>}" >"\$rec/handle"
printf '%s\n' "\${PLANWRIGHT_WORKER_SCOPE-<unset>}" >"\$rec/scope"
cat >"\$rec/stdin"
while [ -f "\$rec/hold" ]; do sleep 0.1; done
[ -f "\$rec/emit" ] && cat "\$rec/emit"
rc=0
[ -f "\$rec/rc" ] && rc=\$(cat "\$rec/rc")
exit "\$rc"
EOF
  chmod +x "$FAKE"
  # Pre-warm: absorb the macOS Gatekeeper first-exec assessment during
  # setup so the timed assertions below never read a stall as a hang.
  touch "$mf_rec/hold"
  rm -f "$mf_rec/hold"
  "$FAKE" --prewarm </dev/null >/dev/null 2>&1 || true
  rm -f "$mf_rec/cwd" "$mf_rec/claude-pid" "$mf_rec/argv" "$mf_rec/ghost" \
    "$mf_rec/handle" "$mf_rec/scope" "$mf_rec/stdin"
}

# wait_for <path> <tenths>: poll for a file, bounded.
wait_for() {
  wf_n=0
  while [ ! -e "$1" ] && [ "$wf_n" -lt "$2" ]; do
    sleep 0.1
    wf_n=$((wf_n + 1))
  done
  [ -e "$1" ]
}

SPEC=execution-backends
ID=3

# --- h1: detached launch, prompt as stdin data, pinned flags, identity env ----
h1() {
  local rec wt out prompt
  rec="$tmp/rec-h1"
  STATE="$tmp/state-h1"
  wt="$tmp/wt-h1"
  mkdir -p "$wt"
  make_fake "$rec"
  # A hostile prompt: if any construction step re-entered a shell, the
  # substitution would run and drop a PWNED file. The $(...) must NOT expand
  # here — that unexpanded literal is the fixture.
  # shellcheck disable=SC2016
  prompt='line one $(touch '"$tmp"'/PWNED) `touch '"$tmp"'/PWNED` "quoted" '"'"'apos'"'"'
line two'
  out=$(printf '%s' "$prompt" | run_fdh launch "$SPEC" "$ID" --worktree "$wt") || {
    fail "h1: launch exited non-zero"
    return
  }
  printf '%s\n' "$out" | grep -q "headless	handle	headless-$SPEC-task-$ID" \
    || fail "h1: launch did not print the worker handle line, got: $out"
  printf '%s\n' "$out" | grep -q "headless	pid	" \
    || fail "h1: launch did not print the pid line"
  printf '%s\n' "$out" | grep -q "headless	state-dir	" \
    || fail "h1: launch did not print the state-dir line"
  wait_for "$STATE/$ID/exit" 300 || {
    fail "h1: worker never completed (no exit file)"
    return
  }
  [ -e "$tmp/PWNED" ] && fail "h1: prompt metacharacters reached a shell (injection)"
  if ! printf '%s' "$prompt" | cmp -s - "$rec/stdin"; then
    fail "h1: prompt was not delivered byte-for-byte on stdin"
  fi
  [ "$(cat "$rec/cwd")" = "$wt" ] || fail "h1: worker did not run in the worktree cwd"
  [ "$(cat "$rec/ghost")" = false ] || fail "h1: ghost-text pin not applied to the worker env"
  [ "$(cat "$rec/handle")" = "headless-$SPEC-task-$ID" ] \
    || fail "h1: PLANWRIGHT_WORKER_HANDLE not set per the identity contract"
  [ "$(cat "$rec/scope")" = "$SPEC:$ID" ] \
    || fail "h1: PLANWRIGHT_WORKER_SCOPE not set per the identity contract"
  grep -qx -- '--print' "$rec/argv" || fail "h1: argv missing the pinned --print form"
  grep -qx -- '--output-format' "$rec/argv" || fail "h1: argv missing --output-format"
  grep -qx -- 'json' "$rec/argv" || fail "h1: argv missing the json output format"
  grep -qx -- '--bare' "$rec/argv" && fail "h1: argv carries --bare (launch pin violated)"
  grep -qx -- '--permission-prompt-tool' "$rec/argv" \
    && fail "h1: argv carries --permission-prompt-tool (one-shot posture violated)"
  pass "h1: detached launch delivers the prompt as data with pinned flags and identity env (REQ-A1.9, REQ-A1.5)"
}

# --- h2: the completion signal carries the worker's exit code -----------------
h2() {
  local rec wt st
  rec="$tmp/rec-h2"
  STATE="$tmp/state-h2"
  wt="$tmp/wt-h2"
  mkdir -p "$wt"
  make_fake "$rec"
  printf 7 >"$rec/rc"
  printf 'do the task' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h2: launch exited non-zero"
    return
  }
  wait_for "$STATE/$ID/exit" 300 || {
    fail "h2: no completion signal"
    return
  }
  grep -Eq '^7 [0-9]+$' "$STATE/$ID/exit" \
    || fail "h2: exit file is not '<rc> <epoch>', got: $(cat "$STATE/$ID/exit")"
  if ! st=$(run_fdh status "$SPEC" "$ID"); then
    fail "h2: status on a completed unit should exit 0"
  fi
  [ "$st" = "completed 7" ] || fail "h2: status should print 'completed 7', got '$st'"
  pass "h2: completion signal records the worker's exit code and status consumes it (REQ-A1.2)"
}

# --- h3: running while live, completed after ---------------------------------
h3() {
  local rec wt st code
  rec="$tmp/rec-h3"
  STATE="$tmp/state-h3"
  wt="$tmp/wt-h3"
  mkdir -p "$wt"
  make_fake "$rec"
  touch "$rec/hold"
  printf 'work' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h3: launch exited non-zero"
    return
  }
  wait_for "$rec/stdin" 300 || {
    fail "h3: worker never started"
    rm -f "$rec/hold"
    return
  }
  code=0
  st=$(run_fdh status "$SPEC" "$ID") || code=$?
  [ "$code" -eq 1 ] || fail "h3: status on a live runner should exit 1, got $code"
  case $st in
    "running "*) pass "h3a: a live runner classifies running (REQ-A1.2)" ;;
    *) fail "h3: status should print 'running <pid>', got '$st'" ;;
  esac
  rm -f "$rec/hold"
  wait_for "$STATE/$ID/exit" 300 || {
    fail "h3: worker never completed after release"
    return
  }
  st=$(run_fdh status "$SPEC" "$ID") || fail "h3: status after completion exited non-zero"
  [ "$st" = "completed 0" ] || fail "h3: status after completion should print 'completed 0', got '$st'"
  pass "h3b: the same unit reads completed after the worker finishes"
}

# --- h4: a killed runner is died by positive evidence, never by silence -------
h4() {
  local rec wt st code rpid cpid
  rec="$tmp/rec-h4"
  STATE="$tmp/state-h4"
  wt="$tmp/wt-h4"
  mkdir -p "$wt"
  make_fake "$rec"
  touch "$rec/hold"
  printf 'work' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h4: launch exited non-zero"
    return
  }
  wait_for "$rec/stdin" 300 || {
    fail "h4: worker never started"
    rm -f "$rec/hold"
    return
  }
  rpid=$(cat "$STATE/$ID/pid")
  cpid=$(cat "$rec/claude-pid" 2>/dev/null || echo "")
  kill -9 "$rpid" 2>/dev/null
  case $cpid in *[!0-9]* | '') ;; *) kill -9 "$cpid" 2>/dev/null ;; esac
  # Wait for the pid to actually be reaped before classifying.
  wf_n=0
  while kill -0 "$rpid" 2>/dev/null && [ "$wf_n" -lt 100 ]; do
    sleep 0.1
    wf_n=$((wf_n + 1))
  done
  code=0
  st=$(run_fdh status "$SPEC" "$ID") || code=$?
  [ "$code" -eq 3 ] || fail "h4: status on a killed runner should exit 3, got $code"
  case $st in
    "died "*) pass "h4: a killed runner classifies died from positive evidence (REQ-A1.2)" ;;
    *) fail "h4: status should print 'died <pid>', got '$st'" ;;
  esac
  [ -e "$STATE/$ID/exit" ] && fail "h4: a killed runner must not have a completion record"
}

# --- h5: construction-layer refusals -----------------------------------------
h5() {
  local rec wt code
  rec="$tmp/rec-h5"
  STATE="$tmp/state-h5"
  wt="$tmp/wt-h5"
  mkdir -p "$wt"
  make_fake "$rec"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" -- --bare >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h5: --bare in the passthrough args should exit 2, got $code"
  [ -e "$STATE/$ID/pid" ] && fail "h5: a refused --bare launch must launch nothing"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" -- --permission-prompt-tool stdio \
    >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h5: --permission-prompt-tool should exit 2, got $code"
  code=0
  printf '' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h5: an empty prompt should exit 2, got $code"
  code=0
  printf 'p' | run_fdh launch "../evil" "$ID" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h5: a hostile spec token should exit 2, got $code"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "3;rm" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h5: a hostile id token should exit 2, got $code"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$tmp/no-such-dir" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h5: a missing worktree should exit 2, got $code"
  pass "h5: hostile or unpinned launch requests are refused before any side effect (REQ-A1.5, REQ-A1.9)"
}

# --- h6: the no-pend posture — a permission refusal lands in the result -------
h6() {
  local rec wt st
  rec="$tmp/rec-h6"
  STATE="$tmp/state-h6"
  wt="$tmp/wt-h6"
  mkdir -p "$wt"
  make_fake "$rec"
  printf '%s' '{"is_error":true,"result":"Bash permission denied: mkfifo requires approval"}' \
    >"$rec/emit"
  printf 1 >"$rec/rc"
  printf 'run mkfifo' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h6: launch exited non-zero"
    return
  }
  wait_for "$STATE/$ID/exit" 300 || {
    fail "h6: a permission-refused one-shot must still complete (no pend), but no completion signal fired"
    return
  }
  st=$(run_fdh status "$SPEC" "$ID") || true
  [ "$st" = "completed 1" ] || fail "h6: status should print 'completed 1', got '$st'"
  grep -q "permission denied" "$STATE/$ID/result.json" \
    || fail "h6: the permission failure must be visible in the captured result"
  pass "h6: an unauthorized ask fails visibly in the result and completion signal, never a pend (REQ-A1.2)"
}

# --- h7: a live unit refuses a second launch ---------------------------------
h7() {
  local rec wt code pid1
  rec="$tmp/rec-h7"
  STATE="$tmp/state-h7"
  wt="$tmp/wt-h7"
  mkdir -p "$wt"
  make_fake "$rec"
  touch "$rec/hold"
  printf 'work' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h7: first launch exited non-zero"
    return
  }
  wait_for "$rec/stdin" 300 || {
    fail "h7: worker never started"
    rm -f "$rec/hold"
    return
  }
  pid1=$(cat "$STATE/$ID/pid")
  code=0
  printf 'work again' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 3 ] || fail "h7: a second launch over a live runner should exit 3, got $code"
  [ "$(cat "$STATE/$ID/pid")" = "$pid1" ] \
    || fail "h7: the refused second launch must not disturb the live dispatch record"
  rm -f "$rec/hold"
  wait_for "$STATE/$ID/exit" 300 || fail "h7: worker never completed after release"
  pass "h7: a unit with a live runner refuses a concurrent re-dispatch (exit 3)"
}

# --- h8: status edges — absent, and refuse-to-guess on a garbled record -------
h8() {
  local st code
  STATE="$tmp/state-h8"
  FAKE="$tmp/rec-h8-unused"
  code=0
  st=$(run_fdh status "$SPEC" 9) || code=$?
  [ "$code" -eq 5 ] || fail "h8: status on a never-dispatched unit should exit 5, got $code"
  [ "$st" = "absent" ] || fail "h8: status should print 'absent', got '$st'"
  mkdir -p "$STATE/7"
  printf 'not-a-pid\n' >"$STATE/7/pid"
  code=0
  st=$(run_fdh status "$SPEC" 7) || code=$?
  [ "$code" -eq 4 ] || fail "h8: a garbled pid record should exit 4 (unknown), got $code"
  [ "$st" = "unknown" ] || fail "h8: a garbled pid record should print 'unknown', got '$st'"
  code=0
  run_fdh status "bad spec" 7 >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h8: a hostile status spec token should exit 2, got $code"
  pass "h8: absent and garbled records answer absent/unknown — never guessed death"
}

# --- h9: launch-arg allowlist (S1) — sanctioned pass, escalation refused ------
h9() {
  local rec wt code
  rec="$tmp/rec-h9"
  STATE="$tmp/state-h9"
  wt="$tmp/wt-h9"
  mkdir -p "$wt"
  make_fake "$rec"
  # A sanctioned flag (--model) is forwarded to the worker argv.
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" -- --model opus >/dev/null || {
    fail "h9: an allowlisted --model launch should succeed"
    return
  }
  wait_for "$STATE/$ID/exit" 300 || fail "h9: allowlisted launch never completed"
  if ! { grep -qx -- '--model' "$rec/argv" && grep -qx -- 'opus' "$rec/argv"; }; then
    fail "h9: the sanctioned --model flag was not forwarded to the worker argv"
  fi
  # An escalation flag off the allowlist is refused before any side effect.
  rm -rf "$STATE"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" -- --dangerously-skip-permissions \
    >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h9: --dangerously-skip-permissions must be refused (exit 2), got $code"
  [ -e "$STATE/$ID/pid" ] && fail "h9: a refused escalation launch must launch nothing"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" -- --add-dir / >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h9: --add-dir off the allowlist must be refused (exit 2), got $code"
  pass "h9: launch args are a strict allowlist — sanctioned pass, escalation refused (S1)"
}

# --- h10: destructive-path containment (S2) — symlinked base refused ----------
h10() {
  local realbase wt code victim
  wt="$tmp/wt-h10"
  mkdir -p "$wt"
  make_fake "$tmp/rec-h10"
  # A hostile state base whose leaf is a symlink pointing outside: the rm -rf /
  # mkdir reclaim must refuse rather than follow it.
  victim="$tmp/victim-h10"
  mkdir -p "$victim"
  printf 'precious\n' >"$victim/keep.txt"
  realbase="$tmp/statebase-h10"
  ln -s "$victim" "$realbase" # the base itself is a symlink
  code=0
  printf 'p' | env PLANWRIGHT_HEADLESS_STATE_DIR="$realbase" \
    PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    /bin/sh "$FDH" launch "$SPEC" "$ID" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h10: a symlinked state base must be refused (exit 2), got $code"
  [ -f "$victim/keep.txt" ] || fail "h10: the symlink target was destroyed (path-escape not guarded)"
  pass "h10: the destructive reclaim refuses a symlinked state base (S2)"
}

# --- h11: state files are owner-only (S3) -------------------------------------
h11() {
  local rec wt perms f
  rec="$tmp/rec-h11"
  STATE="$tmp/state-h11"
  wt="$tmp/wt-h11"
  mkdir -p "$wt"
  make_fake "$rec"
  printf 'secret task text' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h11: launch exited non-zero"
    return
  }
  wait_for "$STATE/$ID/exit" 300 || {
    fail "h11: worker never completed"
    return
  }
  for f in "$STATE/$ID/prompt" "$STATE/$ID/result.json"; do
    [ -f "$f" ] || {
      fail "h11: expected state file missing: $f"
      continue
    }
    # ls -l mode string: positions 5-10 are group+other rwx; owner-only => all '-'.
    # Fixture filenames are fixed (prompt/result.json), so ls is safe here.
    # shellcheck disable=SC2012
    perms=$(ls -l "$f" | cut -c1-10)
    if [ "$(printf '%s' "$perms" | cut -c5-10)" != "------" ]; then
      fail "h11: $f is group/other-readable ($perms); state files must be owner-only (S3)"
    fi
  done
  pass "h11: prompt and result.json are created owner-only (S3)"
}

# --- h12: --worktree symlink refusal (S4) -------------------------------------
h12() {
  local realwt code
  make_fake "$tmp/rec-h12"
  STATE="$tmp/state-h12"
  realwt="$tmp/realwt-h12"
  mkdir -p "$realwt"
  ln -s "$realwt" "$tmp/wtlink-h12"
  code=0
  printf 'p' | run_fdh launch "$SPEC" "$ID" --worktree "$tmp/wtlink-h12" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h12: a symlinked --worktree must be refused (exit 2), got $code"
  [ -e "$STATE/$ID/pid" ] && fail "h12: a refused symlinked worktree must launch nothing"
  pass "h12: a symlinked --worktree is refused (S4)"
}

# --- h13: torn-launch collision window (C1) -----------------------------------
h13() {
  local wt code
  STATE="$tmp/state-h13"
  wt="$tmp/wt-h13"
  mkdir -p "$wt"
  make_fake "$tmp/rec-h13"
  # A torn launch: state dir with a RECENT launched marker, a prompt, no pid,
  # no exit — a concurrent/retry launch must refuse (fail safe toward live).
  mkdir -p "$STATE/$ID"
  printf 'prior task' >"$STATE/$ID/prompt"
  date +%s >"$STATE/$ID/launched"
  code=0
  printf 'p' | env PLANWRIGHT_HEADLESS_LIVENESS_TTL=2 PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$STATE" /bin/sh "$FDH" launch "$SPEC" "$ID" \
    --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 3 ] || fail "h13: a recent torn launch must be refused (exit 3), got $code"
  [ "$(cat "$STATE/$ID/prompt")" = "prior task" ] \
    || fail "h13: the refused retry must not clobber the in-flight state dir"
  # An ABSENT launched marker (prompt present, no launched/pid/exit) is
  # ambiguous, NOT reclaimable: the empty read joins the non-numeric arm and
  # fails safe toward live (refuse), and must not clobber the state dir.
  rm -f "$STATE/$ID/launched"
  code=0
  printf 'p' | env PLANWRIGHT_HEADLESS_LIVENESS_TTL=2 PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$STATE" /bin/sh "$FDH" launch "$SPEC" "$ID" \
    --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 3 ] || fail "h13: an absent launch marker must be refused (exit 3), got $code"
  [ "$(cat "$STATE/$ID/prompt")" = "prior task" ] \
    || fail "h13: the refused absent-marker retry must not clobber the state dir"
  # An OLD launched marker (older than the TTL) is stale and reclaimable.
  printf '%s\n' "$(($(date +%s) - 10))" >"$STATE/$ID/launched"
  printf 'fresh task' | env PLANWRIGHT_HEADLESS_LIVENESS_TTL=2 PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$STATE" /bin/sh "$FDH" launch "$SPEC" "$ID" \
    --worktree "$wt" >/dev/null 2>&1 || {
    fail "h13: a stale (aged-out) torn launch should be reclaimed, not refused"
    return
  }
  wait_for "$STATE/$ID/exit" 300 || fail "h13: the reclaimed launch never completed"
  pass "h13: the torn-launch window fails safe (refuse recent, refuse absent, reclaim stale) (C1)"
}

# --- h14: trap-forward supervision (C2) — TERM the runner, worker dies, no orphan
h14() {
  local rec wt rpid cpid st
  rec="$tmp/rec-h14"
  STATE="$tmp/state-h14"
  wt="$tmp/wt-h14"
  mkdir -p "$wt"
  make_fake "$rec"
  touch "$rec/hold"
  printf 'work' | run_fdh launch "$SPEC" "$ID" --worktree "$wt" >/dev/null || {
    fail "h14: launch exited non-zero"
    return
  }
  wait_for "$rec/claude-pid" 300 || {
    fail "h14: worker never started"
    rm -f "$rec/hold"
    return
  }
  rpid=$(cat "$STATE/$ID/pid")
  cpid=$(cat "$rec/claude-pid")
  # A GRACEFUL kill of the runner: the trap must forward it to the worker and
  # record a terminal completion (143), never orphan the worker.
  kill -TERM "$rpid" 2>/dev/null
  rm -f "$rec/hold"
  if ! wait_for "$STATE/$ID/exit" 300; then
    fail "h14: TERM of the runner did not produce a terminal completion record (orphan risk)"
    kill -9 "$cpid" 2>/dev/null
    return
  fi
  grep -Eq '^143 ' "$STATE/$ID/exit" \
    || fail "h14: a forwarded TERM should record exit 143, got: $(cat "$STATE/$ID/exit")"
  # The worker must be gone (no orphan). Give it a beat to be reaped.
  wf_n=0
  while kill -0 "$cpid" 2>/dev/null && [ "$wf_n" -lt 100 ]; do
    sleep 0.1
    wf_n=$((wf_n + 1))
  done
  kill -0 "$cpid" 2>/dev/null && {
    fail "h14: the worker survived the runner's TERM (orphaned)"
    kill -9 "$cpid" 2>/dev/null
  }
  st=$(run_fdh status "$SPEC" "$ID") || true
  [ "$st" = "completed 143" ] || fail "h14: status after a forwarded TERM should be 'completed 143', got '$st'"
  pass "h14: a graceful kill of the runner forwards to the worker and records completion — no orphan (C2)"
}

# --- h15: fail-fast infra pre-check (C9/C10) ----------------------------------
h15() {
  local wt code
  STATE="$tmp/state-h15"
  wt="$tmp/wt-h15"
  mkdir -p "$wt"
  make_fake "$tmp/rec-h15"
  # A missing launch wrapper is a broken install: refuse at launch, not later.
  code=0
  printf 'p' | env PLANWRIGHT_HEADLESS_ENVWRAP="$tmp/no-such-wrapper" \
    PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" PLANWRIGHT_HEADLESS_STATE_DIR="$STATE" \
    /bin/sh "$FDH" launch "$SPEC" "$ID" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h15: a missing launch wrapper must fail fast (exit 2), got $code"
  [ -e "$STATE/$ID/pid" ] && fail "h15: a broken-wrapper launch must dispatch nothing"
  # A missing worker CLI likewise fails fast rather than becoming completed 127.
  code=0
  printf 'p' | env PLANWRIGHT_HEADLESS_CLAUDE="$tmp/no-such-claude" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$STATE" \
    /bin/sh "$FDH" launch "$SPEC" "$ID" --worktree "$wt" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "h15: a missing worker CLI must fail fast (exit 2), got $code"
  pass "h15: a broken install (missing wrapper or CLI) fails at launch, not as a phantom completion (C9/C10)"
}

# --- h16: a finish-error marker reads unknown, never died (C7) -----------------
h16() {
  local st code
  STATE="$tmp/state-h16"
  mkdir -p "$STATE/$ID"
  # Simulate a worker that finished but could not record its exit: a dead pid
  # plus a finish-error marker. status must refuse to guess (unknown), not died.
  printf '999999999\n' >"$STATE/$ID/pid" # a pid that is not alive
  : >"$STATE/$ID/finish-error"
  code=0
  st=$(run_fdh status "$SPEC" "$ID") || code=$?
  [ "$code" -eq 4 ] || fail "h16: a finish-error marker should read unknown (exit 4), got $code"
  [ "$st" = "unknown" ] || fail "h16: a completed-but-unrecorded worker must be 'unknown', not 'died', got '$st'"
  pass "h16: a swallowed completion write surfaces as unknown, never a false death (C7)"
}

h1
h2
h3
h4
h5
h6
h7
h8
h9
h10
h11
h12
h13
h14
h15
h16

if [ "$failures" -ne 0 ]; then
  echo "test-fleet-dispatch-headless: $failures failure(s)" >&2
  exit 1
fi
echo "ok: test-fleet-dispatch-headless"
