#!/bin/bash
# Tests for scripts/fleet-streamjson.sh — the stream-json-persistent
# supervisor primitive (execution-backends Task 4; D-4, D-5 · REQ-A1.3,
# REQ-A1.9, REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5).
#
# Contract under test (one shim fixture per contract clause, per the
# test-spec REQ-E entries):
#   - REQ-E1.1: an injected can_use_tool control_request produces exactly one
#     journal receipt and one decision-queue item; a duplicate delivery of
#     the same request id produces no second item; advancing past the
#     pending threshold fires the alarm; no code path auto-answers.
#   - REQ-E1.2: an AskUserQuestion control_request maps to exactly one queue
#     item with the same alarm coupling; duplicates deduplicate.
#   - REQ-E1.3: a killed-supervisor fixture recovers via `--resume` on the
#     persisted session_id; recovery checks orphan liveness first; a failed
#     resume surfaces a halt (never a silent loss).
#   - REQ-E1.4: a recorded answer is delivered as the control_response to
#     the pending request; an undeliverable answer (unknown request, settled
#     request, dead channel) surfaces a visible attention item, never a
#     silent drop or re-application.
#   - REQ-E1.5: receipt state survives a supervisor kill; the pending-age
#     alarm re-arms after recovery (scan-based over the durable journal);
#     dedup on request identity holds across the resume boundary; a second
#     concurrent recovery attempt is refused (single initiator).
#   - REQ-A1.3 (Task-4 slice): the observe surface (event-stream capture)
#     exists under the fleet home, and completion/liveness is surfaced from
#     the supervisor + event stream (`status`).
#   - REQ-A1.9 / D-12: prompt text reaches the worker as data on stdin (a
#     metacharacter fixture never reaches a shell), the launch argv carries
#     the pinned -p stream-json shape, and `--bare` is refused.
#
# Hermetic: every case pins PLANWRIGHT_FLEET_STATE_DIR to a case-local home
# and PLANWRIGHT_STREAMJSON_CLI to a single env-driven shim (one inode, so a
# macOS Gatekeeper first-exec assessment happens at most once). Runs
# standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"
FA="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')

# --- fixtures ---------------------------------------------------------------

# The single env-driven CLI shim. One inode for the whole suite.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
# stream-json CLI shim (fixture), driven by env:
#   SHIM_RECORD_DIR   records argv + stdin lines (required)
#   SHIM_EVENTS       file of event lines emitted on stdout
#   SHIM_READ_FIRST   stdin lines to read+record before emitting (default 1)
#   SHIM_WAIT_RESPONSE=1  after emitting, read+record stdin until a
#                     control_response arrives, then emit SHIM_RESULT_LINE
#   SHIM_WATCHDOG     seconds before self-kill while waiting (no-auto-answer)
#   SHIM_SLEEP        sleep after emitting (crash-window hold)
#   SHIM_EXIT         exit code (default 0)
printf '%s\n' "$*" >>"$SHIM_RECORD_DIR/argv"
n=${SHIM_READ_FIRST:-1}
i=0
while [ "$i" -lt "$n" ]; do
  IFS= read -r line || break
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
  i=$((i + 1))
done
if [ -n "${SHIM_EVENTS:-}" ]; then
  cat "$SHIM_EVENTS"
fi
if [ -n "${SHIM_WATCHDOG:-}" ]; then
  (sleep "$SHIM_WATCHDOG" && kill "$$" 2>/dev/null) &
fi
if [ "${SHIM_WAIT_RESPONSE:-0}" = 1 ]; then
  while IFS= read -r line; do
    printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
    case $line in
      *control_response*) break ;;
    esac
  done
  if [ -n "${SHIM_RESULT_LINE:-}" ]; then
    printf '%s\n' "$SHIM_RESULT_LINE"
  fi
fi
if [ -n "${SHIM_SLEEP:-}" ]; then
  sleep "$SHIM_SLEEP"
fi
exit "${SHIM_EXIT:-0}"
SHIM
chmod +x "$tmp/bin/claude"

sid='11111111-2222-3333-4444-555555555555'
req_perm='aaaa1111-bbbb-cccc-dddd-eeee00000001'
req_q='aaaa1111-bbbb-cccc-dddd-eeee00000002'

line_init='{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
line_perm='{"type":"control_request","request_id":"'$req_perm'","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/x/y.txt","content":"hello {brace} \"quoted\""},"tool_use_id":"t1"}}'
line_q='{"type":"control_request","request_id":"'$req_q'","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Which way?","options":[{"label":"a"},{"label":"b"}]}]},"tool_use_id":"t2"}}'
line_result='{"type":"result","subtype":"success","result":"done","session_id":"'$sid'"}'

# senv <home> <record-dir> [SHIM_VAR=val...] -- <args...> — hermetic
# supervisor invocation: ambient overlay/config knobs stripped, the fleet
# home and shim pinned per case.
senv() {
  se_home=$1
  se_rec=$2
  shift 2
  se_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    se_pre+=("$1")
    shift
  done
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_STREAMJSON_PENDING_AGE \
    PLANWRIGHT_FLEET_STATE_DIR="$se_home" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$se_rec" \
    ${se_pre[@]+"${se_pre[@]}"} /bin/sh "$SJ" "$@"
}

# aenv <home> <args...> — hermetic fleet-attention read (queue assertions).
aenv() {
  ae_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$ae_home" /bin/sh "$FA" "$@"
}

# wait_until <timeout-tenths> <cmd...> — poll a condition.
wait_until() {
  wu_n=$1
  shift
  wu_i=0
  while [ "$wu_i" -lt "$wu_n" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    wu_i=$((wu_i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# c1 (REQ-E1.1, REQ-A1.3): a can_use_tool receipt produces exactly one
#    journal row and one decision-queue item; the duplicate delivery is
#    deduplicated; the capture and session persist under the fleet home;
#    completion is surfaced from the event stream.
# ---------------------------------------------------------------------------
home="$tmp/h1"
rec="$tmp/r1"
mkdir -p "$rec"
ev="$tmp/ev1"
printf '%s\n%s\n%s\n%s\n' "$line_init" "$line_perm" "$line_perm" "$line_result" >"$ev"
printf 'do the thing\n' >"$tmp/prompt1"

senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw1 execution-backends:4 --prompt-file "$tmp/prompt1" --foreground \
  || fail "c1: foreground launch exited non-zero"

wdir="$home/streamjson/sjw1"
[ -f "$wdir/events.jsonl" ] || fail "c1: no event-stream capture under the fleet home"
[ "$(grep -c control_request "$wdir/events.jsonl")" = 2 ] \
  || fail "c1: capture should hold both duplicate deliveries"
[ "$(cat "$wdir/session")" = "$sid" ] || fail "c1: session_id not persisted"
[ "$(grep -c "^$req_perm$tab" "$wdir/journal")" = 1 ] \
  || fail "c1: expected exactly one journal row for the duplicated request"
grep -q "^$req_perm$tab.*${tab}pending" "$wdir/journal" \
  || fail "c1: journal row should be pending"
[ -f "$wdir/req-$req_perm.json" ] || fail "c1: request envelope not stored"
q=$(aenv "$home" queue) || fail "c1: attention queue read failed"
printf '%s\n' "$q" | grep -q "sjw1" || fail "c1: no queue item for the worker"
printf '%s\n' "$q" | grep -q "permission request tool Write" \
  || fail "c1: queue item should name the permission request"
[ "$(aenv "$home" queue --count)" = 1 ] \
  || fail "c1: exactly one queue item expected (dedup), got: $(aenv "$home" queue --count)"
out=$(senv "$home" "$rec" -- status sjw1) || fail "c1: status exited non-zero"
case $out in
  "status sjw1 completed result=success") : ;;
  *) fail "c1: status should surface completion from the event stream, got: $out" ;;
esac
echo "ok: c1 can_use_tool receipt -> one journal row + one queue item, dedup, capture, completion (REQ-E1.1, REQ-A1.3)"

# ---------------------------------------------------------------------------
# c2 (REQ-E1.1): the pending-age alarm fires past the threshold (escalation
#    only), and stays quiet below it.
# ---------------------------------------------------------------------------
received=$(awk -F'\t' -v id="$req_perm" '$1 == id { print $3 }' "$wdir/journal")
[ -n "$received" ] || fail "c2: cannot read the received epoch"
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 100)) --threshold 900) \
  || fail "c2: below-threshold alarm-scan exited non-zero"
[ -z "$out" ] || fail "c2: alarm fired below the threshold: $out"
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900) \
  || fail "c2: past-threshold alarm-scan exited non-zero"
printf '%s\n' "$out" | grep -q "^alarm sjw1 $req_perm " \
  || fail "c2: expected an alarm line for the pending request, got: $out"
q=$(aenv "$home" queue)
printf '%s\n' "$q" | grep -q "OVERDUE" \
  || fail "c2: the escalated queue item should be marked OVERDUE"
# Escalation never auto-answers: the row is still pending.
grep -q "^$req_perm$tab.*${tab}pending" "$wdir/journal" \
  || fail "c2: alarm escalation must not settle the request"
echo "ok: c2 pending-age alarm fires past threshold, escalation only (REQ-E1.1)"

# ---------------------------------------------------------------------------
# c3 (REQ-E1.2): an AskUserQuestion control_request maps 1:1 onto a queue
#    item (kind=question), duplicates deduplicate, same alarm coupling.
# ---------------------------------------------------------------------------
home="$tmp/h3"
rec="$tmp/r3"
mkdir -p "$rec"
ev="$tmp/ev3"
printf '%s\n%s\n%s\n' "$line_init" "$line_q" "$line_q" >"$ev"
printf 'ask me\n' >"$tmp/prompt3"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw3 execution-backends:4 --prompt-file "$tmp/prompt3" --foreground \
  || fail "c3: launch exited non-zero"
wdir3="$home/streamjson/sjw3"
[ "$(grep -c "^$req_q$tab" "$wdir3/journal")" = 1 ] \
  || fail "c3: expected exactly one journal row for the duplicated question"
grep -q "^$req_q${tab}question$tab" "$wdir3/journal" \
  || fail "c3: the row should be kind=question"
[ "$(aenv "$home" queue --count)" = 1 ] || fail "c3: exactly one queue item expected"
aenv "$home" queue | grep -q "worker question (AskUserQuestion)" \
  || fail "c3: queue item should name the question kind"
received=$(awk -F'\t' -v id="$req_q" '$1 == id { print $3 }' "$wdir3/journal")
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900) \
  || fail "c3: alarm-scan exited non-zero"
printf '%s\n' "$out" | grep -q "^alarm sjw3 $req_q " \
  || fail "c3: the question item should carry the same alarm coupling, got: $out"
echo "ok: c3 AskUserQuestion maps 1:1 with dedup and the same alarm coupling (REQ-E1.2)"

# ---------------------------------------------------------------------------
# c4 (REQ-E1.1 no-auto-answer): with a pending request and NO answer command,
#    nothing ever writes a control_response to the worker's stdin.
# ---------------------------------------------------------------------------
home="$tmp/h4"
rec="$tmp/r4"
mkdir -p "$rec"
ev="$tmp/ev4"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'quiet\n' >"$tmp/prompt4"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_WATCHDOG=3 -- \
  launch sjw4 execution-backends:4 --prompt-file "$tmp/prompt4" --foreground \
  >/dev/null 2>&1
# The shim's watchdog killed it after 3s of waiting: the only stdin line must
# be the initial user message — no control_response was ever written.
[ -f "$rec/stdin" ] || fail "c4: shim recorded no stdin at all"
[ "$(wc -l <"$rec/stdin" | tr -d ' ')" = 1 ] \
  || fail "c4: worker stdin should hold exactly the initial message, got: $(cat "$rec/stdin")"
grep -q control_response "$rec/stdin" \
  && fail "c4: a control_response reached the worker without an operator answer"
grep -q '"type":"user"' "$rec/stdin" \
  || fail "c4: the initial user message never reached the worker"
echo "ok: c4 no code path auto-answers a pending control_request (REQ-E1.1)"

# ---------------------------------------------------------------------------
# c5 (REQ-E1.4): a recorded answer is delivered as the control_response to
#    the pending request; the journal settles; the queue clears.
# ---------------------------------------------------------------------------
home="$tmp/h5"
rec="$tmp/r5"
mkdir -p "$rec"
ev="$tmp/ev5"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'answer me\n' >"$tmp/prompt5"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw5 execution-backends:4 --prompt-file "$tmp/prompt5" --foreground &
launch_pid=$!
wdir5="$home/streamjson/sjw5"
wait_until 100 grep -q "^$req_perm$tab" "$wdir5/journal" \
  || fail "c5: the pending journal row never appeared"
out=$(senv "$home" "$rec" -- status sjw5) || fail "c5: status exited non-zero"
case $out in
  "status sjw5 running "*) : ;;
  *) fail "c5: status should report running mid-flight, got: $out" ;;
esac
out=$(senv "$home" "$rec" -- answer sjw5 "$req_perm" --allow) \
  || fail "c5: answer exited non-zero"
[ "$out" = "answered sjw5 $req_perm" ] || fail "c5: unexpected answer output: $out"
wait "$launch_pid" || fail "c5: the worker run did not end cleanly after the answer"
grep -q control_response "$rec/stdin" \
  || fail "c5: the control_response never reached the worker stdin"
grep "control_response" "$rec/stdin" | grep -q "\"request_id\":\"$req_perm\"" \
  || fail "c5: the response must target the pending request id"
grep "control_response" "$rec/stdin" | grep -q '"behavior":"allow"' \
  || fail "c5: the allow behavior was not delivered"
grep "control_response" "$rec/stdin" | grep -q '"updatedInput":{"file_path"' \
  || fail "c5: --allow should carry updatedInput sliced from the stored envelope"
grep -q "^$req_perm$tab.*${tab}answered" "$wdir5/journal" \
  || fail "c5: the journal row should settle to answered"
[ "$(aenv "$home" queue --count)" = 0 ] \
  || fail "c5: the queue should clear once the only pending request settles"
echo "ok: c5 recorded answer delivered as the control_response; journal + queue settle (REQ-E1.4)"

# ---------------------------------------------------------------------------
# c6 (REQ-E1.4): undeliverable answers surface visibly — unknown request,
#    already-answered request, dead channel — never a silent drop.
# ---------------------------------------------------------------------------
# (a) unknown request id on the settled c5 worker.
senv "$home" "$rec" -- answer sjw5 "ffff0000-0000-0000-0000-000000000000" --allow \
  >/dev/null 2>&1
[ $? -eq 3 ] || fail "c6a: unknown request should be a semantic refusal (exit 3)"
aenv "$home" queue | grep -q "undeliverable answer" \
  || fail "c6a: the undeliverable answer must surface as an attention item"
# (b) a second answer to the already-answered request is refused (never
#     silently re-applied).
senv "$home" "$rec" -- answer sjw5 "$req_perm" --deny >/dev/null 2>&1
[ $? -eq 3 ] || fail "c6b: an already-answered request should refuse (exit 3)"
before=$(grep -c control_response "$rec/stdin")
[ "$before" = 1 ] || fail "c6b: the second answer must not reach the worker"
# (c) dead channel: c1's worker completed long ago but still carries a
#     pending row; the answer becomes undeliverable and says so.
home1="$tmp/h1"
rec1="$tmp/r1"
senv "$home1" "$rec1" -- answer sjw1 "$req_perm" --allow >/dev/null 2>&1
[ $? -eq 3 ] || fail "c6c: a dead channel should be a semantic refusal (exit 3)"
grep -q "^$req_perm$tab.*${tab}undeliverable" "$home1/streamjson/sjw1/journal" \
  || fail "c6c: the journal row should be marked undeliverable"
aenv "$home1" queue | grep -q "undeliverable answer" \
  || fail "c6c: the dead-channel failure must surface as an attention item"
echo "ok: c6 undeliverable answers surface visibly, never silently (REQ-E1.4)"

# ---------------------------------------------------------------------------
# c7 (REQ-E1.3, REQ-E1.5): killed-supervisor crash window — the receipt
#    survives, recovery is single-initiator, checks orphan liveness, resumes
#    on the persisted session_id, dedups across the boundary, and the alarm
#    re-arms after recovery.
# ---------------------------------------------------------------------------
home="$tmp/h7"
rec="$tmp/r7"
mkdir -p "$rec"
ev="$tmp/ev7"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'crash me\n' >"$tmp/prompt7"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_SLEEP=60 -- \
  launch sjw7 execution-backends:4 --prompt-file "$tmp/prompt7" --foreground &
launch_pid=$!
wdir7="$home/streamjson/sjw7"
wait_until 100 grep -q "^$req_perm$tab" "$wdir7/journal" \
  || fail "c7: the pending journal row never appeared"
sup_pid=$(cat "$wdir7/supervisor.pid")
wrk_pid=$(cat "$wdir7/worker.pid")
kill -9 "$wrk_pid" 2>/dev/null
kill -9 "$sup_pid" 2>/dev/null
wait "$launch_pid" 2>/dev/null
wait_until 50 sh -c "! kill -0 $sup_pid 2>/dev/null && ! kill -0 $wrk_pid 2>/dev/null" \
  || fail "c7: the crashed processes did not die"
# The durable receipt survived the kill (REQ-E1.5).
grep -q "^$req_perm$tab.*${tab}pending" "$wdir7/journal" \
  || fail "c7: the pending receipt must survive a supervisor kill"
# Positive-evidence death via status.
out=$(senv "$home" "$rec" -- status sjw7) || fail "c7: status exited non-zero"
case $out in
  "status sjw7 dead "*) : ;;
  *) fail "c7: status should report positive-evidence death, got: $out" ;;
esac
# Single initiator: a recovery already in flight is refused.
mkdir "$wdir7/recover.lock"
senv "$home" "$rec" -- recover sjw7 --foreground >/dev/null 2>&1
[ $? -eq 3 ] || fail "c7: a concurrent recovery must be refused (exit 3)"
rmdir "$wdir7/recover.lock"
# Orphan liveness: a still-alive worker pid refuses recovery.
sleep 60 &
alive_pid=$!
printf '%s\n' "$alive_pid" >"$wdir7/worker.pid"
senv "$home" "$rec" -- recover sjw7 --foreground >/dev/null 2>&1
[ $? -eq 3 ] || fail "c7: recovery over a live worker must be refused (exit 3)"
kill -9 "$alive_pid" 2>/dev/null
wait "$alive_pid" 2>/dev/null
rm -f "$wdir7/worker.pid"
# The real recovery: the relaunch argv carries --resume <sid>; the re-issued
# duplicate request dedups across the boundary; the alarm re-arms.
ev_resume="$tmp/ev7r"
printf '%s\n%s\n' "$line_perm" "$line_result" >"$ev_resume"
: >"$rec/argv"
senv "$home" "$rec" SHIM_EVENTS="$ev_resume" SHIM_READ_FIRST=0 -- \
  recover sjw7 --foreground || fail "c7: recovery exited non-zero"
grep -q -- "--resume $sid" "$rec/argv" \
  || fail "c7: the relaunch must use --resume with the persisted session_id, got: $(cat "$rec/argv")"
[ "$(grep -c "^$req_perm$tab" "$wdir7/journal")" = 1 ] \
  || fail "c7: dedup on request identity must hold across the resume boundary"
received=$(awk -F'\t' -v id="$req_perm" '$1 == id { print $3 }' "$wdir7/journal")
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900) \
  || fail "c7: post-recovery alarm-scan exited non-zero"
printf '%s\n' "$out" | grep -q "^alarm sjw7 $req_perm " \
  || fail "c7: the pending item's alarm must re-arm after recovery, got: $out"
echo "ok: c7 crash window - durable receipt, single initiator, liveness check, --resume, dedup, alarm re-arm (REQ-E1.3, REQ-E1.5)"

# ---------------------------------------------------------------------------
# c8 (REQ-E1.5): a failed --resume surfaces a halt; a missing session halts;
#    the tower is told via the attention surface, never a silent loss.
# ---------------------------------------------------------------------------
# (a) failed relaunch: the shim exits 7 immediately.
rm -f "$wdir7/result"
: >"$rec/argv"
senv "$home" "$rec" SHIM_READ_FIRST=0 SHIM_EXIT=7 -- recover sjw7 --foreground \
  >/dev/null 2>&1
[ $? -eq 5 ] || fail "c8a: a failed --resume must halt with exit 5"
aenv "$home" queue | grep -q "resume halt" \
  || fail "c8a: the failed resume must surface as an attention item"
# (b) no usable session: a worker dir without a session file.
home8="$tmp/h8"
mkdir -p "$home8/streamjson/sjw8"
printf 'execution-backends:4\n' >"$home8/streamjson/sjw8/scope"
rec8="$tmp/r8"
mkdir -p "$rec8"
senv "$home8" "$rec8" -- recover sjw8 --foreground >/dev/null 2>&1
[ $? -eq 4 ] || fail "c8b: a missing session must halt with exit 4"
aenv "$home8" queue | grep -q "resume halt" \
  || fail "c8b: the missing-session halt must surface as an attention item"
echo "ok: c8 failed resume and missing session halt visibly (REQ-E1.5)"

# ---------------------------------------------------------------------------
# c9 (REQ-A1.9, D-12): the launch argv carries the pinned non-bare
#    stream-json shape; prompt text reaches the worker as data (a
#    metacharacter fixture never reaches a shell); --bare is refused.
# ---------------------------------------------------------------------------
home="$tmp/h9"
rec="$tmp/r9"
mkdir -p "$rec"
ev="$tmp/ev9"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
cat >"$tmp/prompt9" <<'EOF'
run this: $(touch PWNED-marker) `touch PWNED-marker` "quoted" 'single'
second line	with a tab
EOF
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9 execution-backends:4 --prompt-file "$tmp/prompt9" --foreground \
  || fail "c9: launch exited non-zero"
argv_line=$(cat "$rec/argv")
case $argv_line in
  *"-p "*"--input-format stream-json"*"--output-format stream-json"*"--verbose"*"--permission-prompt-tool stdio"*) : ;;
  *) fail "c9: the launch argv is missing the pinned stream-json shape: $argv_line" ;;
esac
case $argv_line in
  *--bare*) fail "c9: --bare must never appear in a launch argv (D-12)" ;;
esac
# shellcheck disable=SC2016 # matching the literal '$(touch' substring, not expanding it
grep -q '\$(touch PWNED-marker)' "$rec/stdin" \
  || fail "c9: the metacharacter prompt must reach the worker as literal data"
grep -q '\\t' "$rec/stdin" || fail "c9: tab should arrive JSON-escaped"
[ ! -e "PWNED-marker" ] && [ ! -e "$tmp/PWNED-marker" ] \
  || fail "c9: prompt text reached a shell (command substitution executed)"
# The structural refusal: a caller-supplied --bare never launches.
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9b execution-backends:4 --prompt-file "$tmp/prompt9" --foreground -- --bare \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c9: a caller-supplied --bare must be refused (exit 2)"
[ ! -s "$rec/argv" ] || fail "c9: the refused launch must never spawn the worker"
echo "ok: c9 pinned non-bare launch shape, prompt-as-data, --bare refused (REQ-A1.9, D-12)"

# ---------------------------------------------------------------------------
# c10: hostile inputs are refused before any path use.
# ---------------------------------------------------------------------------
home="$tmp/h10"
rec="$tmp/r10"
mkdir -p "$rec"
senv "$home" "$rec" -- launch '../escape' scope:1 --prompt-file "$tmp/prompt9" \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a traversal worker handle must be refused"
senv "$home" "$rec" -- status 'a;b' >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a metacharacter worker handle must be refused"
senv "$home" "$rec" -- answer sjw1 '../../etc/passwd' --allow >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a traversal request id must be refused"
senv "$home" "$rec" -- alarm-scan --now 'evil' >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a non-numeric --now must be refused"
# A multi-line response file would inject extra frames into the worker's
# stdin protocol: refused fail-closed before any delivery attempt.
printf '{"behavior":"allow"}\ninjected-frame\n' >"$tmp/multiline-resp"
home5="$tmp/h5"
rec5="$tmp/r5"
senv "$home5" "$rec5" -- answer sjw5 "$req_perm" --response-file "$tmp/multiline-resp" \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a multi-line --response-file must be refused (exit 2)"
echo "ok: c10 hostile handles, ids, and multi-line response bodies are refused (REQ-A1.9 discipline)"

echo "all fleet-streamjson tests passed"
