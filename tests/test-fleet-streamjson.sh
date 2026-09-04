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
# The close verb and the single-initiator elections on `launch` and `recover`
# come from a later bundle (fleet-lifecycle-closure), and the cases from c19 on
# cover it:
#   - REQ-B1.2: the close terminates the supervisor, the worker, and the
#     worker's children, SIGTERM before SIGKILL, including a grandchild that
#     survives SIGTERM and is reparented away from the tree.
#   - REQ-B1.3: process matching keys on the state directory and the pids it
#     records; a look-alike operator session and a worker whose handle merely
#     extends the stopped one both survive, and a source audit over the kill
#     path asserts no name or command-pattern match.
#   - REQ-B1.4: the runtime classes are released and the durable record is not.
#   - REQ-A1.3 / REQ-B1.7: a release that cannot complete reports partial on
#     its own exit code, a repeat takes exactly what is still held, and a
#     fully released worker reports already-closed without signalling.
#   - obs:81ba2dce / obs:917e384e: a `recover.lock` whose holder is gone is
#     broken, and `launch` elects a single initiator under real contention.
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
#   SHIM_STUBBORN_CHILD  path a SIGTERM-surviving grandchild records its pid in
#   SHIM_IGNORE_TERM=1   survive SIGTERM, recording each one in <record>/signals
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
if [ -n "${SHIM_STUBBORN_CHILD:-}" ]; then
  # A grandchild that outlives SIGTERM. When its parents die it reparents to
  # init, which takes it out of any descendant walk recomputed from scratch.
  #
  # It has to be a separate `sh -c`, not a `( … ) &` subshell: POSIX `$$` in a
  # subshell is the *parent's* pid, so a subshell would record the shim's own
  # pid and every assertion against it would only be re-testing that the worker
  # died.
  sh -c 'trap "" TERM; printf "%s\n" "$$" >"$1"; while :; do sleep 1; done' \
    _ "$SHIM_STUBBORN_CHILD" &
fi
if [ "${SHIM_IGNORE_TERM:-0}" = 1 ]; then
  # A worker that survives SIGTERM: the handler records the signal and the
  # loop keeps running, so only SIGKILL ends this process.
  trap 'printf "term\n" >>"$SHIM_RECORD_DIR/signals"' TERM
  while :; do
    sleep 1
  done
fi
if [ -n "${SHIM_SELF_CLOSE:-}" ]; then
  # Run a command from inside the worker's own process tree and record what it
  # did. This is how an agent closing its own handle reaches the close verb, and
  # it is the only way to exercise that path: nothing the harness runs is a
  # descendant of the supervisor. It waits for a go-file so the harness can
  # record the pre-close state first — otherwise a close that wrongly proceeds
  # deletes the pid files before they can be read, and the case fails during
  # setup instead of on the assertion that names the defect.
  if [ -n "${SHIM_SELF_CLOSE_WHEN:-}" ]; then
    # Bounded: if the case fails before it can create the go-file, the harness
    # tears down its tmp dir and the file can never appear. An unbounded wait
    # here would leave this shim spinning forever, holding out.fifo open so the
    # supervisor never sees EOF either — two processes surviving the run.
    sc_i=0
    while [ ! -e "$SHIM_SELF_CLOSE_WHEN" ] && [ "$sc_i" -lt 600 ]; do
      sleep 0.1
      sc_i=$((sc_i + 1))
    done
  fi
  sh -c "$SHIM_SELF_CLOSE" >"$SHIM_RECORD_DIR/selfclose.out" 2>&1
  printf '%s\n' "$?" >"$SHIM_RECORD_DIR/selfclose.rc"
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

# The ambient overlay/config knobs every hermetic runner strips. Held in one
# array so a knob added here reaches all of them; a runner that hand-copied the
# list would silently stop scrubbing the next one added, and the failure mode is
# a case reading the developer's real fleet home.
env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE
)

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
  env "${env_scrub[@]}" \
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

# ps_rows — one `<pid> <ppid> <args>` row per process, captured through a
# variable so the assertion's own `grep` (whose argv would carry the very path
# being searched for) is never in the snapshot it is searching.
#
# Mirrors the script's own degradation: without the fallback, a host whose `ps`
# rejects `-ww` yields an empty snapshot here, and every "no process survives"
# assertion below passes for the wrong reason.
ps_rows() {
  pr_out=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
  case ${pr_out%%"
"*} in
    *[0-9]*) ;;
    *) pr_out=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || pr_out='' ;;
  esac
  [ -n "$pr_out" ] || fail "ps_rows: this host produced no usable process table"
  printf '%s\n' "$pr_out"
}

# no_proc_under <dir> — true when no live process references <dir> in its argv.
#
# `ps_rows`'s own `fail` cannot end the run from inside a command substitution
# (its `exit` leaves only the subshell), so the emptiness is re-checked here.
# Without it an unusable `ps` yields an empty snapshot and every caller's "no
# process survives" assertion passes over a fully live worker tree.
no_proc_under() {
  np_snap=$(ps_rows) || fail "no_proc_under: this host produced no usable process table"
  [ -n "$np_snap" ] || fail "no_proc_under: this host produced no usable process table"
  ! printf '%s\n' "$np_snap" | grep -Fq -- "$1"
}

# first_child <pid> — the pid of a live child of <pid>, empty when none.
first_child() {
  fc_snap=$(ps_rows) || fail "first_child: this host produced no usable process table"
  printf '%s\n' "$fc_snap" | awk -v p="$1" '$2 == p { print $1; exit }'
}

# Every close assertion rests on the process table, and the helpers above are
# called through `wait_until`, which runs its predicate with both streams
# discarded — a `fail` raised inside one would end the run with nothing on
# screen to say why. Prove the table is readable here instead, once, where the
# message survives.
ps_rows >/dev/null \
  || fail "this host produced no usable process table; the close assertions cannot run"

# attention_rows <home> <worker> — count of store rows for <worker>.
attention_rows() {
  ar_store="$1/attention/state"
  [ -f "$ar_store" ] || {
    echo 0
    return 0
  }
  awk -F "$tab" -v w="$2" '($1 "") == (w "") { n++ } END { print n + 0 }' "$ar_store"
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
# REQ-A1.3 steer (message-in) surface: the worker's stdin fifo is the steer
# channel (the answer path in c5 exercises it end-to-end). Assert the surface
# exists as a fifo, so the observe+steer pair REQ-A1.3 names is both covered.
[ -p "$wdir/in.fifo" ] || fail "c1: the steer (message-in) fifo surface must exist (REQ-A1.3)"
[ -p "$wdir/out.fifo" ] || fail "c1: the observe (event-stream) fifo surface must exist (REQ-A1.3)"
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
# REQ-E1.2 "carrying the question payload": the stored envelope must retain
# the question body, so an operator/renderer can reconstruct the choice.
[ -f "$wdir3/req-$req_q.json" ] || fail "c3: the question envelope was not stored"
grep -q 'Which way?' "$wdir3/req-$req_q.json" \
  || fail "c3: the stored envelope must carry the question payload (REQ-E1.2)"
grep -q '"label":"a"' "$wdir3/req-$req_q.json" \
  || fail "c3: the stored envelope must carry the question options (REQ-E1.2)"
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
senv "$home" "$rec" -- launch sjw10 --resume-session '../../etc' >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: an out-of-grammar --resume-session id must be refused"
# A multi-line response file would inject extra frames into the worker's
# stdin protocol: refused fail-closed before any delivery attempt.
printf '{"behavior":"allow"}\ninjected-frame\n' >"$tmp/multiline-resp"
home5="$tmp/h5"
rec5="$tmp/r5"
senv "$home5" "$rec5" -- answer sjw5 "$req_perm" --response-file "$tmp/multiline-resp" \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a multi-line --response-file must be refused (exit 2)"
# A bare-zero numeric would turn `kill -0 "$pid"` into a process-group probe
# (false-alive liveness): valid_posnum refuses 0 at every numeric ingress.
senv "$home" "$rec" -- alarm-scan --now 0 >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a zero --now must be refused (exit 2)"
senv "$home" "$rec" -- alarm-scan --threshold 0 >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: a zero --threshold must be refused (exit 2)"
# An empty response file would emit '"response":' with no value (an invalid
# frame on the worker's stdin): refused before any delivery attempt.
: >"$tmp/empty-resp"
senv "$home5" "$rec5" -- answer sjw5 "$req_perm" --response-file "$tmp/empty-resp" \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: an empty --response-file must be refused (exit 2)"
# An oversize response body must be refused whole, never silently truncated
# into a partial (invalid) JSON frame.
awk 'BEGIN { printf "{\"k\":\""; for (i = 0; i < 70000; i++) printf "x"; printf "\"}" }' \
  >"$tmp/big-resp"
senv "$home5" "$rec5" -- answer sjw5 "$req_perm" --response-file "$tmp/big-resp" \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c10: an oversize --response-file must be refused (exit 2)"
echo "ok: c10 hostile handles, ids, zero numerics, and malformed response bodies are refused (REQ-A1.9 discipline)"

# ---------------------------------------------------------------------------
# c11 (REQ-A1.9 launch): a prompt larger than the pipe buffer must not
#     deadlock. Regression for the synchronous init-write-before-read-loop
#     deadlock: the worker cannot drain its stdin until the supervisor opens
#     the stdout fifo for reading, so a >buffer init write must be backgrounded.
# ---------------------------------------------------------------------------
home="$tmp/h11"
rec="$tmp/r11"
mkdir -p "$rec"
ev="$tmp/ev11"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
# ~300 KB prompt, far past any pipe buffer (16-64 KB). The shim drains all of
# stdin so we can prove the full init message was delivered, not truncated.
awk 'BEGIN { for (i = 0; i < 8000; i++) printf "prompt filler line %d aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", i }' >"$tmp/bigprompt"
# Realistic shim: reads ONE stdin line (the whole init message — newlines are
# escaped, so it is a single line however large) then emits, WITHOUT waiting
# for stdin EOF (the supervisor holds stdin open all run, as the real CLI's
# driver does; a `cat`-to-EOF shim would itself deadlock).
cat >"$tmp/bin/claude-drain" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >>"$SHIM_RECORD_DIR/argv"
IFS= read -r line
printf '%s' "$line" >"$SHIM_RECORD_DIR/stdin_full"
[ -n "${SHIM_EVENTS:-}" ] && cat "$SHIM_EVENTS"
exit 0
SHIM
chmod +x "$tmp/bin/claude-drain"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
  PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude-drain" \
  SHIM_RECORD_DIR="$rec" SHIM_EVENTS="$ev" \
  /bin/sh "$SJ" launch bigw execution-backends:4 --prompt-file "$tmp/bigprompt" --foreground &
big_pid=$!
if wait_until 300 sh -c "! kill -0 $big_pid 2>/dev/null"; then
  wait "$big_pid" || fail "c11: large-prompt launch exited non-zero"
else
  kill -9 "$big_pid" 2>/dev/null
  fail "c11: DEADLOCK - large-prompt launch did not finish (the init write blocked the read loop)"
fi
[ -s "$rec/stdin_full" ] || fail "c11: the worker never received its stdin"
# The full init message reached the worker (not truncated at the buffer).
[ "$(wc -c <"$rec/stdin_full" | tr -d ' ')" -gt 200000 ] \
  || fail "c11: the large init message was truncated, not fully delivered"
echo "ok: c11 a prompt larger than the pipe buffer does not deadlock (REQ-A1.9)"

# ---------------------------------------------------------------------------
# c12 (REQ-E1.5): a request re-surfacing in a terminal journal state (the
#     resume re-issue after a prior answer did not take) is RE-OPENED to
#     pending and re-queued, not swallowed by dedup — the "recover and re-ask"
#     remedy must be reachable, and no request may pend permanently
#     unanswerable.
# ---------------------------------------------------------------------------
home="$tmp/h12"
rec="$tmp/r12"
mkdir -p "$rec"
ev="$tmp/ev12"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'reopen me\n' >"$tmp/prompt12"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw12 execution-backends:4 --prompt-file "$tmp/prompt12" --foreground &
launch12=$!
wdir12="$home/streamjson/sjw12"
wait_until 100 grep -q "^$req_perm$tab" "$wdir12/journal" \
  || fail "c12: the pending journal row never appeared"
senv "$home" "$rec" -- answer sjw12 "$req_perm" --allow >/dev/null \
  || fail "c12: answer exited non-zero"
wait "$launch12" || fail "c12: the worker run did not end cleanly"
grep -q "^$req_perm$tab.*${tab}answered" "$wdir12/journal" \
  || fail "c12: the request should be answered after the first run"
[ "$(aenv "$home" queue --count)" = 0 ] || fail "c12: queue should be clear after the answer"
# Now simulate the resume: the same request id re-surfaces on the event
# stream (the CLI re-issues the unprocessed ask). handle_line must re-open it.
ev_re="$tmp/ev12re"
printf '%s\n%s\n' "$line_perm" "$line_result" >"$ev_re"
senv "$home" "$rec" SHIM_EVENTS="$ev_re" SHIM_READ_FIRST=0 -- \
  launch sjw12 execution-backends:4 --resume-session "$sid" --foreground \
  || fail "c12: resume relaunch exited non-zero"
# Before the fix the journal would still read `answered` (dedup swallowed the
# re-issue) and the queue would be empty — permanently unanswerable. The fix
# re-opens the receipt: a fresh pending row and a re-queued item, so the resume
# ask is answerable again rather than lost.
grep -q "^$req_perm$tab.*${tab}pending" "$wdir12/journal" \
  || fail "c12: the re-issued request must be RE-OPENED to pending, not swallowed"
[ "$(aenv "$home" queue --count)" = 1 ] \
  || fail "c12: the re-opened request must be re-queued (answerable again)"
# The re-opened request is no longer a terminal exit-3 refusal on identity: an
# answer against it now fails only on the (legitimately dead) resumed channel,
# not on an `already answered`/`undeliverable` terminal-state refusal. Prove
# the journal state is the answerable `pending`, which is what makes it so.
grep -q "^$req_perm$tab.*${tab}\(answered\|undeliverable\)" "$wdir12/journal" \
  && fail "c12: the re-issued request must not stay in a terminal state"
echo "ok: c12 a terminal request re-surfacing on resume is re-opened and re-queued (REQ-E1.5)"

# ---------------------------------------------------------------------------
# c13 (REQ-A1.9): a prompt with UTF-8 content reaches the worker intact
#     (regression for the LC_ALL=C [^[:print:]] strip that deleted all
#     non-ASCII bytes).
# ---------------------------------------------------------------------------
home="$tmp/h13"
rec="$tmp/r13"
mkdir -p "$rec"
ev="$tmp/ev13"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
printf 'caf\xc3\xa9 \xe2\x80\x94 \xe6\x97\xa5\xe6\x9c\xac end\n' >"$tmp/prompt13"
cat >"$tmp/bin/claude-drain13" <<'SHIM'
#!/bin/sh
IFS= read -r line
printf '%s' "$line" >"$SHIM_RECORD_DIR/stdin_full"
[ -n "${SHIM_EVENTS:-}" ] && cat "$SHIM_EVENTS"
exit 0
SHIM
chmod +x "$tmp/bin/claude-drain13"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
  PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude-drain13" \
  SHIM_RECORD_DIR="$rec" SHIM_EVENTS="$ev" \
  /bin/sh "$SJ" launch u13 execution-backends:4 --prompt-file "$tmp/prompt13" --foreground \
  || fail "c13: launch exited non-zero"
# The UTF-8 bytes survive into the worker's stdin (é = c3 a9, — = e2 80 94).
grep -q "$(printf 'caf\xc3\xa9')" "$rec/stdin_full" \
  || fail "c13: UTF-8 content was stripped from the prompt on the way to the worker"
grep -q "$(printf '\xe6\x97\xa5\xe6\x9c\xac')" "$rec/stdin_full" \
  || fail "c13: multibyte CJK content was stripped from the prompt"
echo "ok: c13 UTF-8 prompt content reaches the worker intact (REQ-A1.9)"

# ---------------------------------------------------------------------------
# c14: a worker that ends with a non-zero exit and no result event is
#     reported `ended`, never `completed` (positive-evidence completion).
# ---------------------------------------------------------------------------
home="$tmp/h14"
rec="$tmp/r14"
mkdir -p "$rec"
ev="$tmp/ev14"
printf '%s\n' "$line_init" >"$ev"
printf 'fail me\n' >"$tmp/prompt14"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_EXIT=1 -- \
  launch sjw14 execution-backends:4 --prompt-file "$tmp/prompt14" --foreground \
  >/dev/null 2>&1
out=$(senv "$home" "$rec" -- status sjw14) || fail "c14: status exited non-zero"
case $out in
  "status sjw14 ended exit=1") : ;;
  *) fail "c14: a non-zero exit with no result event must render 'ended', got: $out" ;;
esac
echo "ok: c14 a non-zero worker exit is reported ended, not completed"

# ---------------------------------------------------------------------------
# c15: the detached launch confirms the supervisor started and does not report
#     a false success when it cannot. A launch whose CLI dir is missing (the
#     supervisor cannot spawn the worker but mkfifo still runs) still comes up;
#     the real failure surface is a bad --cwd, which fails BEFORE the detached
#     spawn. Here we assert the happy path returns `launched` only after
#     supervisor.pid exists, and that a broken re-exec surfaces non-zero.
# ---------------------------------------------------------------------------
home="$tmp/h15"
rec="$tmp/r15"
mkdir -p "$rec"
ev="$tmp/ev15"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
printf 'detach me\n' >"$tmp/prompt15"
out=$(senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw15 execution-backends:4 --prompt-file "$tmp/prompt15") \
  || fail "c15: detached launch exited non-zero"
case $out in
  "launched sjw15 dir "*) : ;;
  *) fail "c15: detached launch should report launched, got: $out" ;;
esac
# `launched` was printed only after supervisor.pid appeared: it exists now.
wdir15="$home/streamjson/sjw15"
wait_until 100 sh -c "[ -f '$wdir15/result' ]" \
  || fail "c15: the detached supervisor never ran to a result"
# A failed detached launch surfaces non-zero. Force the supervisor's mkfifo to
# fail by pre-planting `in.fifo` as a NON-EMPTY directory: supervise's `rm -f`
# cannot clear a non-empty dir, so `mkfifo` fails and supervise returns 2
# before writing supervisor.pid or a result — exactly the "supervisor cannot
# start" signal the launch confirmation must catch. (cmd_launch's own
# `chmod 700 "$dir"` would undo a mere permission trap, so the block must be
# structural.)
home_bad="$tmp/h15b"
mkdir -p "$home_bad/streamjson/sjw15b/in.fifo/block"
senv "$home_bad" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw15b execution-backends:4 --prompt-file "$tmp/prompt15" >/dev/null 2>&1
bad_rc=$?
[ "$bad_rc" = 2 ] \
  || fail "c15: a detached supervisor that cannot start must surface non-zero, got rc=$bad_rc"
echo "ok: c15 detached launch confirms startup and surfaces a failed supervisor (detached-path visibility)"

# ---------------------------------------------------------------------------
# c16 (REQ-E1.5): if the terminal->pending re-open flip FAILS, the request
#     must fail closed — no answerable queue item over a journal that still
#     reads terminal (a subsequent `answer` would refuse on it as already
#     answered); a visible failure item surfaces instead. Fault injection: a
#     poisoned `awk` on PATH that fails only on journal_set_state's re-open
#     signature (the exact arg `st=pending`), passing every other awk call
#     through untouched.
# ---------------------------------------------------------------------------
home="$tmp/h16"
rec="$tmp/r16"
mkdir -p "$rec"
ev="$tmp/ev16"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'reopen fail me\n' >"$tmp/prompt16"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw16 execution-backends:4 --prompt-file "$tmp/prompt16" --foreground &
launch16=$!
wdir16="$home/streamjson/sjw16"
wait_until 100 grep -q "^$req_perm$tab" "$wdir16/journal" \
  || fail "c16: the pending journal row never appeared"
senv "$home" "$rec" -- answer sjw16 "$req_perm" --allow >/dev/null \
  || fail "c16: answer exited non-zero"
wait "$launch16" || fail "c16: the worker run did not end cleanly"
grep -q "^$req_perm$tab.*${tab}answered" "$wdir16/journal" \
  || fail "c16: the request should be answered after the first run"
real_awk=$(command -v awk) || fail "c16: no awk on PATH"
mkdir -p "$tmp/poison"
cat >"$tmp/poison/awk" <<POISON
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = 'st=pending' ] && exit 1
done
exec $real_awk "\$@"
POISON
chmod +x "$tmp/poison/awk"
ev_re="$tmp/ev16re"
printf '%s\n%s\n' "$line_perm" "$line_result" >"$ev_re"
senv "$home" "$rec" SHIM_EVENTS="$ev_re" SHIM_READ_FIRST=0 PATH="$tmp/poison:$PATH" -- \
  launch sjw16 execution-backends:4 --resume-session "$sid" --foreground \
  || fail "c16: resume relaunch exited non-zero"
# Fail closed: the journal still reads terminal (the flip failed) ...
grep -q "^$req_perm$tab.*${tab}answered" "$wdir16/journal" \
  || fail "c16: the journal must still read answered after a failed re-open"
# ... so no answerable queue item may advertise it ...
aenv "$home" queue | grep -q 'answer via fleet-streamjson.sh answer' \
  && fail "c16: a failed re-open must not advertise an answerable queue item"
# ... and the failed re-open surfaces visibly instead (never silent).
aenv "$home" queue | grep -q 'could not re-open' \
  || fail "c16: a failed re-open must surface a visible failure item"
echo "ok: c16 a failed terminal->pending re-open fails closed and surfaces visibly (REQ-E1.5)"

# ---------------------------------------------------------------------------
# c17 (REQ-E1.4): a `--deny --message` whose text carries control characters
#     (TAB, CR) must still deliver a WELL-FORMED control_response. Raw C0
#     bytes inside a JSON string are invalid JSON, so the worker's parser
#     would reject the frame and the answer would be silently lost. The deny
#     body must escape exactly what json_escape_file escapes.
# ---------------------------------------------------------------------------
home="$tmp/h17"
rec="$tmp/r17"
mkdir -p "$rec"
ev="$tmp/ev17"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'deny me\n' >"$tmp/prompt17"
# TAB + CR + the escapes the deny path already handled (backslash, quote), so
# a regression in either half of the escaping surfaces here.
deny_msg=$(printf 'no:\tuse the \\API\r"policy" says no')
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw17 execution-backends:4 --prompt-file "$tmp/prompt17" --foreground &
launch17=$!
wdir17="$home/streamjson/sjw17"
wait_until 100 grep -q "^$req_perm$tab" "$wdir17/journal" \
  || fail "c17: the pending journal row never appeared"
senv "$home" "$rec" -- answer sjw17 "$req_perm" --deny --message "$deny_msg" >/dev/null \
  || fail "c17: deny answer exited non-zero"
wait "$launch17" || fail "c17: the worker run did not end cleanly after the deny"
grep control_response "$rec/stdin" | head -1 >"$tmp/c17line"
[ -s "$tmp/c17line" ] || fail "c17: the control_response never reached the worker stdin"
grep -q "\"request_id\":\"$req_perm\"" "$tmp/c17line" \
  || fail "c17: the response must target the pending request id"
grep -q '"behavior":"deny"' "$tmp/c17line" || fail "c17: the deny behavior was not delivered"
# The defect: raw C0 bytes (a TAB here) emitted inside the JSON string body.
# Detected with `tr -d` over the byte ranges rather than an awk character
# class: BSD awk (macOS) does not honour `[\000-\037\177]` as a byte range, so
# an awk-based detector silently mis-reports on the bash-3.2 floor platform.
# The delimiting newline (\012) is excluded from the ranges below.
LC_ALL=C tr -d '\000-\011\013-\037\177' <"$tmp/c17line" >"$tmp/c17stripped"
cmp -s "$tmp/c17line" "$tmp/c17stripped" \
  || fail "c17: the deny body carries a RAW control character - invalid JSON: $(od -c "$tmp/c17line")"
grep -qF '\t' "$tmp/c17line" || fail "c17: the TAB should be delivered as a \\t escape"
grep -qF '\r' "$tmp/c17line" || fail "c17: the CR should be delivered as a \\r escape"
grep -qF '\\API' "$tmp/c17line" || fail "c17: the backslash escape regressed"
grep -qF '\"policy\"' "$tmp/c17line" || fail "c17: the double-quote escape regressed"
# End-to-end proof with a real JSON parser where one is available (the suite
# does not otherwise require python3; the byte assertions above stand alone).
if command -v python3 >/dev/null 2>&1; then
  python3 - "$tmp/c17line" <<'PY' || fail "c17: the delivered control_response is not valid JSON"
import json
import sys

line = open(sys.argv[1], "rb").read().decode("utf-8")
obj = json.loads(line)
msg = obj["response"]["response"]["message"]
assert msg == 'no:\tuse the \\API\r"policy" says no', repr(msg)
PY
  echo "ok: c17 (python3 json.loads confirms the frame parses and round-trips)"
else
  echo "skip: c17 json.loads round-trip (python3 unavailable)"
fi
echo "ok: c17 a deny message with control characters delivers well-formed JSON (REQ-E1.4)"

# ---------------------------------------------------------------------------
# c18 (REQ-E1.5): the mtime probe behind the journal-lock stale-break must
#     yield a real epoch under BOTH stat flavors. On GNU/busybox stat `-f`
#     means --file-system, so a BSD-first `stat -f %m … || stat -c %Y …` chain
#     has its format string consumed as a FILE operand: the call dumps
#     filesystem info on STDOUT and exits non-zero, and the chain CONCATENATES
#     that dump with the fallback's epoch. The result is not merely a wrong
#     mtime — `$((now - mtime))` over it is a fatal arithmetic error that kills
#     the shell (confirmed on Debian/dash and Alpine/busybox).
#
#     The lock is driven through `answer`, whose only pre-lock work is the
#     worker-dir check: a stale-broken lock lets it reach the not-journaled
#     refusal (exit 3), a lock judged fresh reports busy (exit 2). Those two
#     outcomes are what the probe's value decides between, so each flavor is
#     asserted in BOTH directions — a probe returning a constant would pass
#     the stale legs alone.
# ---------------------------------------------------------------------------
# Flavor shims. Each answers only its own flavor's form and reproduces the
# other flavor's real failure mode, so the probe cannot pass by accident of
# ordering: whichever form the script tries first, the value must still be a
# plain epoch. The mtime they report is canned (STAT_SHIM_MTIME) — the legs
# below with no shim on PATH cover the host's real stat against a real file.
mkdir -p "$tmp/statgnu" "$tmp/statbsd"
cat >"$tmp/statgnu/stat" <<'GNUSTAT'
#!/bin/sh
# GNU/busybox stat: -c <fmt> formats; -f is --file-system (fmt becomes a file
# operand), which dumps to stdout and exits non-zero.
case ${1:-} in
  -c)
    [ "${2:-}" = '%Y' ] || exit 1
    printf '%s\n' "$STAT_SHIM_MTIME"
    exit 0
    ;;
  -f)
    echo "stat: cannot read file system information for '${2:-}': No such file or directory" >&2
    printf '  File: "%s"\n    ID: 94674a6d81261f15 Namelen: 255 Type: overlayfs\nBlock size: 4096\n' "${3:-}"
    exit 1
    ;;
esac
exit 1
GNUSTAT
cat >"$tmp/statbsd/stat" <<'BSDSTAT'
#!/bin/sh
# BSD stat: -f <fmt> formats; -c is not an option at all.
case ${1:-} in
  -f)
    [ "${2:-}" = '%m' ] || exit 1
    printf '%s\n' "$STAT_SHIM_MTIME"
    exit 0
    ;;
  -c)
    echo "stat: illegal option -- c" >&2
    echo "usage: stat [-FLnq] [-f format | -l | -r | -s | -x] [-t timefmt] [file ...]" >&2
    exit 1
    ;;
esac
exit 1
BSDSTAT
chmod +x "$tmp/statgnu/stat" "$tmp/statbsd/stat"

home="$tmp/h18"
rec="$tmp/r18"
mkdir -p "$rec"
unknown_req='cccc2222-dddd-eeee-ffff-000011112222'

# lock_leg <name> <path-override|-> <shim-age-secs|-> <touch-stamp|-> <want-rc>
# Plants a worker dir holding a locked journal, runs one `answer` against it,
# and asserts the outcome the stale-break decision produces. The shim's mtime
# is derived from the clock AT CALL TIME (age 0 = fresh, 3600 = well past the
# 60s threshold): each leg spends ~5s in the lock spin, so a timestamp stamped
# once at case start would drift across the threshold on a loaded machine and
# flip the fresh legs.
lock_leg() {
  ll_name=$1
  ll_path=$2
  ll_age=$3
  ll_stamp=$4
  ll_want=$5
  ll_dir="$home/streamjson/$ll_name"
  mkdir -p "$ll_dir/journal.lock" || fail "c18/$ll_name: cannot plant the lock"
  [ "$ll_stamp" = '-' ] || touch -t "$ll_stamp" "$ll_dir/journal.lock" \
    || fail "c18/$ll_name: cannot age the lock"
  ll_pre=()
  [ "$ll_path" = '-' ] || ll_pre+=("PATH=$ll_path:$PATH")
  [ "$ll_age" = '-' ] || ll_pre+=("STAT_SHIM_MTIME=$(($(date +%s) - ll_age))")
  senv "$home" "$rec" ${ll_pre[@]+"${ll_pre[@]}"} -- \
    answer "$ll_name" "$unknown_req" --allow >/dev/null 2>&1
  ll_rc=$?
  [ "$ll_rc" = "$ll_want" ] \
    || fail "c18/$ll_name: expected rc=$ll_want from the stale-break decision, got rc=$ll_rc"
}

# (a) GNU flavor, lock aged well past the 60s threshold -> broken, `answer`
#     reaches the not-journaled refusal. THIS is the regression leg: pre-fix
#     the BSD-first chain concatenates the filesystem dump here.
lock_leg sjw18a "$tmp/statgnu" 3600 - 3
# (b) GNU flavor, lock mtime fresh -> NOT broken, reported busy. Proves the
#     probe's value is actually consumed (a constant would fail this).
lock_leg sjw18b "$tmp/statgnu" 0 - 2
# (c) BSD flavor, aged -> broken. The macOS path must not regress when the
#     probe order flips.
lock_leg sjw18c "$tmp/statbsd" 3600 - 3
# (d) BSD flavor, fresh -> busy.
lock_leg sjw18d "$tmp/statbsd" 0 - 2
# (e)+(f) NO shim: the host's real stat against a real directory mtime, so
#     whichever flavor this platform ships is exercised end to end (GNU on the
#     Linux CI runner, BSD on the macOS floor).
lock_leg sjw18e - - 202001010000.00 3
lock_leg sjw18f - - - 2
echo "ok: c18 the mtime probe yields a real epoch under both stat flavors, in both directions (REQ-E1.5)"

# ---------------------------------------------------------------------------
# c19 (REQ-B1.2, REQ-B1.4, REQ-A1.3): `stop` terminates the supervisor, the
#    worker, and the worker's own children, releases the runtime set, and
#    leaves the durable records the state directory also holds.
# ---------------------------------------------------------------------------
home="$tmp/h19"
rec="$tmp/r19"
mkdir -p "$rec"
# init + one pending permission request, then the worker holds open: every
# runtime class (process tree, scratch fifos, attention record) is occupied.
ev_hold="$tmp/ev-hold"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev_hold"
printf 'hold open\n' >"$tmp/prompt19"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw19 execution-backends:4 --prompt-file "$tmp/prompt19" \
  >/dev/null || fail "c19: detached launch exited non-zero"
wdir19="$home/streamjson/sjw19"
wait_until 100 test -s "$wdir19/worker.pid" || fail "c19: worker.pid never appeared"
sup19=$(cat "$wdir19/supervisor.pid")
wrk19=$(cat "$wdir19/worker.pid")
kid19=''
i=0
while [ "$i" -lt 100 ]; do
  kid19=$(first_child "$wrk19")
  [ -n "$kid19" ] && break
  sleep 0.1
  i=$((i + 1))
done
[ -n "$kid19" ] || fail "c19: the worker's own child never appeared"
# The attention upsert follows the journal append, so waiting on the journal
# file would return before the row this case needs exists.
i=0
while [ "$i" -lt 100 ] && [ "$(attention_rows "$home" sjw19)" = 0 ]; do
  sleep 0.1
  i=$((i + 1))
done
[ "$(attention_rows "$home" sjw19)" != 0 ] || fail "c19: no attention record to release"

out=$(senv "$home" "$rec" -- stop sjw19 --grace 2)
rc=$?
[ "$rc" = 0 ] || fail "c19: stop should exit 0 on a complete release, got rc=$rc ($out)"
case $out in
  "stop sjw19 stopped released="*) : ;;
  *) fail "c19: expected a stopped result, got: $out" ;;
esac
for cls in process scratch attention; do
  case $out in
    *"$cls"*) : ;;
    *) fail "c19: the released set must name $cls, got: $out" ;;
  esac
done
wait_until 100 sh -c \
  "! kill -0 $sup19 2>/dev/null && ! kill -0 $wrk19 2>/dev/null && ! kill -0 $kid19 2>/dev/null" \
  || fail "c19: supervisor, worker, and the worker's child must all be gone"
wait_until 50 no_proc_under "$wdir19" \
  || fail "c19: no process may still reference the worker's state directory"
[ ! -p "$wdir19/in.fifo" ] || fail "c19: the scratch fifos must be released"
[ ! -p "$wdir19/out.fifo" ] || fail "c19: the scratch fifos must be released"
[ "$(attention_rows "$home" sjw19)" = 0 ] || fail "c19: the attention record must be released"
# A close releases runtime resources and never the record of the run.
[ -s "$wdir19/events.jsonl" ] || fail "c19: the event-stream capture must survive a stop"
[ -s "$wdir19/journal" ] || fail "c19: the receipt journal must survive a stop"
[ -s "$wdir19/session" ] || fail "c19: the persisted session must survive a stop"
echo "ok: c19 stop terminates the tree, releases the runtime set, keeps the record (REQ-B1.2, REQ-B1.4, REQ-A1.3)"

# ---------------------------------------------------------------------------
# c20 (REQ-B1.2): SIGTERM first, SIGKILL after the bounded grace — a worker
#    that survives SIGTERM is still gone when `stop` returns.
# ---------------------------------------------------------------------------
home="$tmp/h20"
rec="$tmp/r20"
mkdir -p "$rec"
printf 'ignore term\n' >"$tmp/prompt20"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_IGNORE_TERM=1 -- \
  launch sjw20 execution-backends:4 --prompt-file "$tmp/prompt20" \
  >/dev/null || fail "c20: detached launch exited non-zero"
wdir20="$home/streamjson/sjw20"
wait_until 100 test -s "$wdir20/worker.pid" || fail "c20: worker.pid never appeared"
wrk20=$(cat "$wdir20/worker.pid")
# The shim installs its TERM handler only after emitting, and the hold loop's
# own `sleep` child is the first thing that exists afterwards. Waiting for that
# child is what proves the handler is in place; the journal row would only
# prove the supervisor consumed the emitted line.
i=0
while [ "$i" -lt 100 ] && [ -z "$(first_child "$wrk20")" ]; do
  sleep 0.1
  i=$((i + 1))
done
[ -n "$(first_child "$wrk20")" ] || fail "c20: the worker never reached its hold loop"
started=$(date +%s)
out=$(senv "$home" "$rec" -- stop sjw20 --grace 2)
rc=$?
elapsed=$(($(date +%s) - started))
[ "$rc" = 0 ] || fail "c20: stop should exit 0 after escalating, got rc=$rc ($out)"
grep -q term "$rec/signals" 2>/dev/null \
  || fail "c20: SIGTERM must be sent before the escalation"
[ "$elapsed" -ge 2 ] || fail "c20: the grace must elapse before SIGKILL, took ${elapsed}s"
wait_until 100 sh -c "! kill -0 $wrk20 2>/dev/null" \
  || fail "c20: a worker ignoring SIGTERM must be SIGKILLed after the grace"
wait_until 50 no_proc_under "$wdir20" \
  || fail "c20: no process may still reference the state directory after the escalation"
# The close must wait out the grace it was *given*, not a fixed one. An absolute
# bound cannot show that: the default grace and the settling wait together sit
# inside any window wide enough to be non-flaky, so a stop that dropped --grace
# entirely would still pass one. Two closes at different graces do show it,
# and the comparison is immune to how fast the host is.
printf 'ignore term longer\n' >"$tmp/prompt20b"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_IGNORE_TERM=1 -- \
  launch sjw20b execution-backends:4 --prompt-file "$tmp/prompt20b" \
  >/dev/null || fail "c20: the second launch exited non-zero"
wdir20b="$home/streamjson/sjw20b"
wait_until 100 test -s "$wdir20b/worker.pid" || fail "c20: sjw20b worker.pid never appeared"
wrk20b=$(cat "$wdir20b/worker.pid")
i=0
while [ "$i" -lt 100 ] && [ -z "$(first_child "$wrk20b")" ]; do
  sleep 0.1
  i=$((i + 1))
done
[ -n "$(first_child "$wrk20b")" ] || fail "c20: sjw20b never reached its hold loop"
started=$(date +%s)
senv "$home" "$rec" -- stop sjw20b --grace 6 >/dev/null || fail "c20: the long-grace stop failed"
elapsed_long=$(($(date +%s) - started))
[ $((elapsed_long - elapsed)) -ge 2 ] \
  || fail "c20: --grace must set the wait; 2s took ${elapsed}s and 6s took ${elapsed_long}s"
# The difference pins that --grace is read at all; this pins the unit. A close
# reading the grace as tenths already fails the difference check above (0.4s
# apart), but one reading it as minutes passes it comfortably, so the only unit
# error left to catch is a too-large one — hence an upper bound and no lower
# one. It is set far above any plausible scheduling delay, since this suite is
# expected to run alongside a parallel `mise run check`.
[ "$elapsed_long" -lt 120 ] || fail "c20: a 6s grace should not take ${elapsed_long}s"
wait_until 50 no_proc_under "$wdir20b" \
  || fail "c20: the long-grace worker left a process referencing its state directory"
echo "ok: c20 SIGTERM first, SIGKILL after the grace the caller set (REQ-B1.2)"

# ---------------------------------------------------------------------------
# c21 (REQ-B1.3): process matching keys on the state directory. An operator
#    session sharing the worker's command shape survives the stop, and a
#    source audit confirms no bare-name or command-pattern match exists in
#    the kill path.
# ---------------------------------------------------------------------------
home="$tmp/h21"
rec="$tmp/r21"
mkdir -p "$rec"
# The decoy: the worker's exact command shape, belonging to nobody's state dir.
env SHIM_RECORD_DIR="$rec" SHIM_READ_FIRST=0 SHIM_SLEEP=120 \
  "$tmp/bin/claude" -p --input-format stream-json --output-format stream-json \
  --verbose --permission-prompt-tool stdio </dev/null >/dev/null 2>&1 &
decoy=$!
printf 'decoy neighbour\n' >"$tmp/prompt21"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw21 execution-backends:4 --prompt-file "$tmp/prompt21" \
  >/dev/null || fail "c21: detached launch exited non-zero"
wdir21="$home/streamjson/sjw21"
wait_until 100 test -s "$wdir21/worker.pid" || fail "c21: worker.pid never appeared"
wrk21=$(cat "$wdir21/worker.pid")
kill -0 "$decoy" 2>/dev/null || fail "c21: the decoy session did not start"
senv "$home" "$rec" -- stop sjw21 --grace 2 >/dev/null \
  || fail "c21: stop exited non-zero"
wait_until 100 sh -c "! kill -0 $wrk21 2>/dev/null" \
  || fail "c21: the worker must be terminated"
kill -0 "$decoy" 2>/dev/null \
  || fail "c21: the operator session sharing the worker's command shape must survive"
decoy_kid=$(first_child "$decoy")
kill -9 "$decoy" 2>/dev/null
[ -z "$decoy_kid" ] || kill -9 "$decoy_kid" 2>/dev/null
wait "$decoy" 2>/dev/null
# A sibling worker whose handle this one is a prefix of. An unanchored search
# for the state-directory path finds its supervisor, whose argv carries
# `.../sjw21x` — and then kills a healthy unrelated worker's whole tree.
printf 'prefix sibling\n' >"$tmp/prompt21x"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw21x execution-backends:4 --prompt-file "$tmp/prompt21x" \
  >/dev/null || fail "c21: the prefix-sibling launch exited non-zero"
wdir21x="$home/streamjson/sjw21x"
wait_until 100 test -s "$wdir21x/worker.pid" || fail "c21: sibling worker.pid never appeared"
wrk21x=$(cat "$wdir21x/worker.pid")
sup21x=$(cat "$wdir21x/supervisor.pid")
out=$(senv "$home" "$rec" -- stop sjw21 --grace 2)
case $out in
  "stop sjw21 already-closed") : ;;
  *) fail "c21: the already-closed worker must stay closed, got: $out" ;;
esac
kill -0 "$wrk21x" 2>/dev/null \
  || fail "c21: a worker whose handle merely extends the stopped one must survive"
kill -0 "$sup21x" 2>/dev/null \
  || fail "c21: the prefix sibling's supervisor must survive"
senv "$home" "$rec" -- stop sjw21x --grace 2 >/dev/null || fail "c21: sibling stop failed"
# Source audit over the whole kill path — selection *and* the signalling that
# consumes it. It may key on the state directory and on the pids the worker's
# own state records, and on nothing else.
audit=$(
  awk '/^stop_candidates\(\)/, /^}/' "$SJ"
  awk '/^release_processes\(\)/, /^}/' "$SJ"
)
[ -n "$audit" ] || fail "c21: the kill path was not found for the audit"
printf '%s\n' "$audit" | grep -q '_supervise' \
  || fail "c21: the kill path must key on the supervisor's own state-directory argv"
printf '%s\n' "$audit" | grep -q 'supervisor.pid' \
  || fail "c21: the kill path must key on the pids the state directory records"
for bad in claude pgrep killall pkill 'input-format' 'permission-prompt-tool'; do
  printf '%s\n' "$audit" | grep -q -- "$bad" \
    && fail "c21: the kill path must not match on '$bad' (name or command-pattern matching)"
done
echo "ok: c21 state-directory matching spares a look-alike session and a prefix-sibling worker (REQ-B1.3)"

# ---------------------------------------------------------------------------
# c22 (REQ-B1.7): a second stop against a worker with nothing still held
#    returns the distinct already-closed result with exit 0 and signals
#    nothing.
# ---------------------------------------------------------------------------
home="$tmp/h22"
rec="$tmp/r22"
mkdir -p "$rec"
printf 'idempotent\n' >"$tmp/prompt22"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_IGNORE_TERM=1 -- \
  launch sjw22 execution-backends:4 --prompt-file "$tmp/prompt22" \
  >/dev/null || fail "c22: detached launch exited non-zero"
wdir22="$home/streamjson/sjw22"
wait_until 100 test -s "$wdir22/worker.pid" || fail "c22: worker.pid never appeared"
senv "$home" "$rec" -- stop sjw22 --grace 2 >/dev/null || fail "c22: the first stop failed"
# The shim records every SIGTERM it survives. A repeat stop that re-signalled
# the stale recorded pids would add to that file; a repeat that honours the
# release set signals nothing at all.
before=$(wc -l <"$rec/signals" 2>/dev/null || echo 0)
out=$(senv "$home" "$rec" -- stop sjw22 --grace 2)
rc=$?
after=$(wc -l <"$rec/signals" 2>/dev/null || echo 0)
[ "$rc" = 0 ] || fail "c22: a repeat stop must succeed, got rc=$rc ($out)"
[ "$out" = "stop sjw22 already-closed" ] \
  || fail "c22: a repeat stop must return the distinct already-closed result, got: $out"
[ "$before" = "$after" ] || fail "c22: a repeat stop must send no signal"
echo "ok: c22 idempotent close returns a distinct already-closed result and signals nothing (REQ-B1.7)"

# ---------------------------------------------------------------------------
# c22b (REQ-B1.2, REQ-B1.4): a grandchild that survives SIGTERM is reparented
#    to init when its parents die, which takes it out of any descendant walk
#    recomputed from scratch. The close must still account for it rather than
#    report the process class released over a survivor.
# ---------------------------------------------------------------------------
home="$tmp/h22b"
rec="$tmp/r22b"
mkdir -p "$rec"
printf 'stubborn grandchild\n' >"$tmp/prompt22b"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 \
  SHIM_STUBBORN_CHILD="$tmp/stubborn22b.pid" -- \
  launch sjw22b execution-backends:4 --prompt-file "$tmp/prompt22b" \
  >/dev/null || fail "c22b: detached launch exited non-zero"
wdir22b="$home/streamjson/sjw22b"
wait_until 100 test -s "$tmp/stubborn22b.pid" || fail "c22b: the stubborn grandchild never started"
stubborn=$(cat "$tmp/stubborn22b.pid")
kill -0 "$stubborn" 2>/dev/null || fail "c22b: the stubborn grandchild is not running"
# The whole case turns on this pid being a *different* process from the worker.
# Recorded with a subshell rather than a separate shell it would silently be
# the worker's own pid, and every assertion below would re-test c19.
wait_until 100 test -s "$wdir22b/worker.pid" || fail "c22b: worker.pid never appeared"
[ "$stubborn" != "$(cat "$wdir22b/worker.pid")" ] \
  || fail "c22b: the grandchild pid must not be the worker's own"
# It must also be invisible to a state-directory match, so that only the
# accumulated target set can account for it once it reparents.
stub_args=$(ps -p "$stubborn" -o args= 2>/dev/null)
[ -n "$stub_args" ] || fail "c22b: cannot read the grandchild's argv to check it"
case $stub_args in
  *"$wdir22b"*) fail "c22b: the grandchild must not carry the state dir in its argv" ;;
esac
out=$(senv "$home" "$rec" -- stop sjw22b --grace 2)
rc=$?
[ "$rc" = 0 ] || fail "c22b: stop should close the whole tree, got rc=$rc ($out)"
case $out in
  "stop sjw22b stopped released="*) : ;;
  *) fail "c22b: expected a stopped result, got: $out" ;;
esac
wait_until 100 sh -c "! kill -0 $stubborn 2>/dev/null" \
  || fail "c22b: a reparented grandchild must not survive a close that reports success"
wait_until 50 no_proc_under "$wdir22b" || fail "c22b: the state directory is still referenced"
echo "ok: c22b a reparented SIGTERM-surviving grandchild is still closed (REQ-B1.2)"

# ---------------------------------------------------------------------------
# c22d (REQ-B1.3, REQ-B1.4): a close invoked from inside the worker's own tree
#    is refused. The candidate walk excludes the closer and its ancestors, so
#    such a close cannot see the supervisor it is meant to signal; left to
#    proceed it reports the whole release set free over a live worker and
#    deletes the pid files that would otherwise stop a second launch.
# ---------------------------------------------------------------------------
home="$tmp/h22d"
rec="$tmp/r22d"
mkdir -p "$rec"
printf 'self close\n' >"$tmp/prompt22d"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 \
  SHIM_SELF_CLOSE="/bin/sh '$SJ' stop sjw22d --grace 2" \
  SHIM_SELF_CLOSE_WHEN="$tmp/go22d" -- \
  launch sjw22d execution-backends:4 --prompt-file "$tmp/prompt22d" \
  >/dev/null || fail "c22d: detached launch exited non-zero"
wdir22d="$home/streamjson/sjw22d"
wait_until 100 test -s "$wdir22d/worker.pid" || fail "c22d: worker.pid never appeared"
sup22d=$(cat "$wdir22d/supervisor.pid")
wrk22d=$(cat "$wdir22d/worker.pid")
: >"$tmp/go22d"
wait_until 100 test -s "$rec/selfclose.rc" || fail "c22d: the self-close never ran"
[ "$(cat "$rec/selfclose.rc")" = 3 ] \
  || fail "c22d: a self-close must be refused (exit 3), got $(cat "$rec/selfclose.rc"): $(cat "$rec/selfclose.out")"
# Exit 3 is shared with every other semantic refusal, so the code alone would
# also be satisfied by, say, the launch-in-flight arm firing for another reason.
grep -q 'from inside its own process tree' "$rec/selfclose.out" \
  || fail "c22d: the refusal must be the self-close one, got: $(cat "$rec/selfclose.out")"
# Refused means nothing was touched: the tree is intact, and the pid files that
# stop a second launch are still there. A close that proceeded would report the
# whole set released, delete both files, and let `launch` start a second
# supervisor over this one.
kill -0 "$sup22d" 2>/dev/null || fail "c22d: the refused close killed the supervisor"
kill -0 "$wrk22d" 2>/dev/null || fail "c22d: the refused close killed the worker"
[ -s "$wdir22d/supervisor.pid" ] || fail "c22d: the refused close cleared supervisor.pid"
[ -s "$wdir22d/worker.pid" ] || fail "c22d: the refused close cleared worker.pid"
[ -p "$wdir22d/in.fifo" ] || fail "c22d: the refused close deleted the worker's channel"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw22d execution-backends:4 --prompt-file "$tmp/prompt22d" >/dev/null 2>&1
[ $? -eq 3 ] || fail "c22d: a launch over the still-live worker must still be refused"
# And a close from outside still works.
senv "$home" "$rec" -- stop sjw22d --grace 2 >/dev/null || fail "c22d: the outside close failed"
wait_until 100 sh -c "! kill -0 $sup22d 2>/dev/null" || fail "c22d: the supervisor survived"
echo "ok: c22d a close from inside the worker's own tree is refused (REQ-B1.3)"

# ---------------------------------------------------------------------------
# c22e (REQ-B1.3): on a host whose `ps` gives full argv, a recorded pid that is
#    an ancestor of the closer must NOT read as a self-close. A pid file
#    outlives the process it names, and a recycled pid is very often an ancestor
#    of every shell on the host; refusing on one would wedge the handle forever,
#    and since `stop` is the only verb that clears those files, `launch` and
#    `recover` would refuse it too — unclosable, unlaunchable, unrecoverable.
# ---------------------------------------------------------------------------
wdir22e="$home/streamjson/sjw22e"
mkdir -p "$wdir22e" || fail "c22e: cannot plant the state dir"
# The planted pid is the closer's own: a wrapper records `$$` and then `exec`s
# the close, so the recorded pid is the process that runs it — the i=0 element
# of the ancestry walk. It has to be something the walk reaches AND something
# with no other descendants, because `stop_candidates` still seeds `want` from
# this file and expands downward; anything under the planted pid that is not
# also under the closer would be signalled for real. Planting the test shell's
# parent reaches the walk but violates the second condition: every sibling of
# this suite, including a parallel `mise` task, sits under it.
# selfpid_close <home> <rec> <pidfile> <worker> [env=val...] — run `stop` from a
# wrapper that records its own pid into <pidfile> and then execs, so the
# recorded pid is the closing process itself.
# shellcheck disable=SC2016 # $$/$1/$@ belong to the inner shell, which has to
# record its own pid before exec'ing; expanding them here would defeat that.
selfpid_close() {
  spc_home=$1
  spc_rec=$2
  spc_file=$3
  spc_worker=$4
  shift 4
  env "${env_scrub[@]}" "$@" \
    PLANWRIGHT_FLEET_STATE_DIR="$spc_home" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$spc_rec" \
    /bin/sh -c 'printf "%s\n" "$$" >"$1"; shift; exec "$@"' _ \
    "$spc_file" /bin/sh "$SJ" stop "$spc_worker" --grace 2 2>&1
}
out=$(selfpid_close "$home" "$rec" "$wdir22e/supervisor.pid" sjw22e)
rc=$?
[ "$rc" != 3 ] \
  || fail "c22e: a recorded pid that is an ancestor must not read as a self-close: $out"
[ "$rc" = 0 ] || fail "c22e: the close should have succeeded, got rc=$rc ($out)"
[ ! -e "$wdir22e/supervisor.pid" ] \
  || fail "c22e: the close must clear the stale pid file, or the handle stays wedged"
echo "ok: c22e a recorded pid in the closer's ancestry is not a self-close (REQ-B1.3)"

# ---------------------------------------------------------------------------
# c22f (REQ-B1.3): the other half of the same conditional. On a host whose `ps`
#    truncates argv, a missing supervisor match is not evidence of absence, so
#    the recorded pids ARE consulted and the close fails closed. Without a case
#    here the narrow-host branch never executes and could be deleted whole with
#    the suite still green.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/narrowbin"
# A `ps` that rejects -ww and truncates args, the busybox shape the script
# degrades for. It must still emit real pids and ppids, so the ancestry walk is
# genuine and only the argv is missing.
cat >"$tmp/narrowbin/ps" <<'NPS'
#!/bin/sh
for a in "$@"; do
  case $a in
    -ww) exit 1 ;;
  esac
done
/bin/ps "$@" | cut -c1-40
NPS
chmod +x "$tmp/narrowbin/ps"
wdir22f="$home/streamjson/sjw22f"
mkdir -p "$wdir22f" || fail "c22f: cannot plant the state dir"
out=$(selfpid_close "$home" "$rec" "$wdir22f/supervisor.pid" sjw22f \
  PATH="$tmp/narrowbin:$PATH")
rc=$?
[ "$rc" = 3 ] \
  || fail "c22f: with truncated argv the recorded pid must fail closed (exit 3), got rc=$rc ($out)"
grep -q 'from inside its own process tree' <<EOF || fail "c22f: wrong refusal: $out"
$out
EOF
echo "ok: c22f a truncated-argv host consults the recorded pids and fails closed (REQ-B1.3)"

# ---------------------------------------------------------------------------
# c22g (REQ-B1.3): a process table that cannot be read at all is a third answer,
#    not "not self-hosted". Every other probe in the close path fails closed;
#    this one used to be the exception, and a momentary fork exhaustion was
#    enough to let a self-close through.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/deadbin"
printf '#!/bin/sh\nexit 1\n' >"$tmp/deadbin/ps"
chmod +x "$tmp/deadbin/ps"
wdir22g="$home/streamjson/sjw22g"
mkdir -p "$wdir22g" || fail "c22g: cannot plant the state dir"
out=$(selfpid_close "$home" "$rec" "$wdir22g/supervisor.pid" sjw22g \
  PATH="$tmp/deadbin:$PATH")
rc=$?
[ "$rc" = 2 ] \
  || fail "c22g: an unreadable process table must refuse the close (exit 2), got rc=$rc ($out)"
[ -e "$wdir22g/supervisor.pid" ] \
  || fail "c22g: a refused close must not have cleared the pid file"
echo "ok: c22g an unreadable process table refuses rather than proceeds (REQ-B1.3)"

# ---------------------------------------------------------------------------
# c22c (REQ-A1.3, REQ-B1.4): the lock class is released and named, and an
#    unknown handle is refused rather than reported closed.
# ---------------------------------------------------------------------------
# Continues against c22's worker, which is already closed and so holds nothing
# but the lock planted below. The home is rebound rather than inherited: every
# other case opens with its own pair, and a case inserted above this one would
# otherwise silently point these assertions at a different fleet.
home="$tmp/h22"
rec="$tmp/r22"
mkdir -p "$wdir22/launch.lock" || fail "c22c: cannot plant the lock"
out=$(senv "$home" "$rec" -- stop sjw22 --grace 2)
rc=$?
[ "$rc" = 0 ] || fail "c22c: stop should release a stranded lock, got rc=$rc ($out)"
[ "$out" = "stop sjw22 stopped released=locks" ] \
  || fail "c22c: the lock class must be released and named, got: $out"
[ ! -e "$wdir22/launch.lock" ] || fail "c22c: the stranded lock must be gone"
senv "$home" "$rec" -- stop sjw-never-launched >/dev/null 2>&1
[ $? -eq 2 ] || fail "c22c: an unknown handle must be refused (exit 2), never already-closed"
senv "$home" "$rec" -- stop sjw22 --grace 0 >/dev/null 2>&1
[ $? -eq 2 ] || fail "c22c: --grace 0 must be refused"
senv "$home" "$rec" -- stop sjw22 --grace 99999999 >/dev/null 2>&1
[ $? -eq 2 ] || fail "c22c: an out-of-range --grace must be refused"
echo "ok: c22c the lock class releases, and bad handles and graces are refused (REQ-A1.3)"

# ---------------------------------------------------------------------------
# c23 (REQ-A1.3, REQ-B1.7): a release that cannot complete is reported as
#    partial, never as success, and the retry takes exactly the classes still
#    held rather than reporting already-closed.
# ---------------------------------------------------------------------------
if [ "$(id -u)" = 0 ]; then
  echo "skip: c23 partial-close injection needs a non-root user (running as root)"
else
  home="$tmp/h23"
  rec="$tmp/r23"
  mkdir -p "$rec"
  ev23="$tmp/ev23"
  printf '%s\n%s\n%s\n' "$line_init" "$line_perm" "$line_result" >"$ev23"
  printf 'partial close\n' >"$tmp/prompt23"
  senv "$home" "$rec" SHIM_EVENTS="$ev23" -- \
    launch sjw23 execution-backends:4 --prompt-file "$tmp/prompt23" --foreground \
    || fail "c23: foreground launch exited non-zero"
  [ "$(attention_rows "$home" sjw23)" != 0 ] || fail "c23: no attention record to withhold"
  # Make the attention store unwritable: `clear` fails, the row stays held.
  chmod 500 "$home/attention" || fail "c23: cannot make the attention store unwritable"
  out=$(senv "$home" "$rec" -- stop sjw23 --grace 2 2>/dev/null)
  rc=$?
  chmod 700 "$home/attention" || fail "c23: cannot restore the attention store"
  [ "$rc" = 6 ] || fail "c23: a partial close must report the partial exit code, got rc=$rc ($out)"
  [ "$out" = "stop sjw23 partial released=scratch held=attention" ] \
    || fail "c23: expected the released and held sets named exactly, got: $out"
  case ${out#*held=} in
    *attention*) : ;;
    *) fail "c23: the partial result must name the class it could not release, got: $out" ;;
  esac
  [ "$(attention_rows "$home" sjw23)" != 0 ] || fail "c23: the withheld class must still be held"
  # The retry takes exactly the class still held — and is not already-closed.
  out=$(senv "$home" "$rec" -- stop sjw23 --grace 2)
  rc=$?
  [ "$rc" = 0 ] || fail "c23: the retry should complete the release, got rc=$rc ($out)"
  [ "$out" = "stop sjw23 stopped released=attention" ] \
    || fail "c23: the retry must take exactly the class still held, got: $out"
  [ "$(attention_rows "$home" sjw23)" = 0 ] || fail "c23: the retry must release the class"
  out=$(senv "$home" "$rec" -- stop sjw23 --grace 2)
  [ "$out" = "stop sjw23 already-closed" ] \
    || fail "c23: only a fully released worker reports already-closed, got: $out"
  echo "ok: c23 a partial close reports partial and the retry drains what is still held (REQ-A1.3, REQ-B1.7)"
fi

# ---------------------------------------------------------------------------
# c24 (obs:81ba2dce): a `recover.lock` left behind by a killed recovery is
#    broken past the documented stale age, so one SIGKILL cannot wedge the
#    verb permanently; a lock younger than that still refuses.
# ---------------------------------------------------------------------------
home="$tmp/h24"
rec="$tmp/r24"
mkdir -p "$rec"
ev24="$tmp/ev24"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev24"
printf 'stale lock\n' >"$tmp/prompt24"
senv "$home" "$rec" SHIM_EVENTS="$ev24" -- \
  launch sjw24 execution-backends:4 --prompt-file "$tmp/prompt24" --foreground \
  || fail "c24: foreground launch exited non-zero"
wdir24="$home/streamjson/sjw24"
[ "$(cat "$wdir24/session")" = "$sid" ] || fail "c24: session_id not persisted"
# (a) a fresh lock is still a live recovery: refused, never broken.
mkdir "$wdir24/recover.lock" || fail "c24: cannot plant the lock"
senv "$home" "$rec" SHIM_EVENTS="$ev24" SHIM_READ_FIRST=0 -- \
  recover sjw24 --foreground >/dev/null 2>&1
[ $? -eq 3 ] || fail "c24a: a fresh recover.lock must still refuse (exit 3)"
[ -d "$wdir24/recover.lock" ] || fail "c24a: a fresh lock must not be broken"
# (b) the same lock aged past the threshold is broken and recovery proceeds.
touch -t 202001010000.00 "$wdir24/recover.lock" || fail "c24: cannot age the lock"
: >"$rec/argv"
senv "$home" "$rec" SHIM_EVENTS="$ev24" SHIM_READ_FIRST=0 -- \
  recover sjw24 --foreground >/dev/null 2>&1 \
  || fail "c24b: a stale recover.lock must be broken and recovery must succeed"
grep -q -- "--resume $sid" "$rec/argv" \
  || fail "c24b: the relaunch after the stale break must resume the persisted session"
[ ! -d "$wdir24/recover.lock" ] || fail "c24b: the lock must be released after recovery"
echo "ok: c24 a stale recover.lock is broken, a fresh one still refuses (obs:81ba2dce)"

# ---------------------------------------------------------------------------
# c25 (obs:917e384e): `launch` elects a single initiator, so two concurrent
#    launches for one worker leave exactly one supervisor and one pid file.
# ---------------------------------------------------------------------------
home="$tmp/h25"
rec="$tmp/r25"
mkdir -p "$rec"
printf 'one initiator\n' >"$tmp/prompt25"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" \
  >/dev/null || fail "c25: the first launch exited non-zero"
wdir25="$home/streamjson/sjw25"
wait_until 100 test -s "$wdir25/supervisor.pid" || fail "c25: supervisor.pid never appeared"
sup25=$(cat "$wdir25/supervisor.pid")
# (a) a launch arriving while this worker's supervisor is up is refused, so a
#     second supervisor never overwrites the first one's pid file.
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" >"$tmp/o25a" 2>&1
[ $? -eq 3 ] || fail "c25a: a launch over a live supervisor must be refused (exit 3)"
grep -q "already running" "$tmp/o25a" \
  || fail "c25a: the refusal must be the live-supervisor one, got: $(cat "$tmp/o25a")"
[ "$(cat "$wdir25/supervisor.pid")" = "$sup25" ] \
  || fail "c25a: the refused launch must not have replaced the supervisor pid file"
snap25=$(ps_rows)
n25=$(printf '%s\n' "$snap25" | grep -Fc -- "_supervise sjw25 $wdir25")
[ "$n25" = 1 ] || fail "c25a: exactly one supervisor expected for the worker, found $n25"
senv "$home" "$rec" -- stop sjw25 --grace 2 >/dev/null || fail "c25: stop exited non-zero"
# (b) the election itself, under genuine contention: several launches start at
#     once with no supervisor up, so the atomic mkdir is what decides. Exactly
#     one may win, and the losers must refuse rather than race into `supervise`.
#
# Only meaningful on a host whose `mkdir` is actually atomic, which is not
# universal: uutils coreutils 0.8.0, the /usr/bin/mkdir on some images, returns
# success to several concurrent creators of one path (its sequential EEXIST is
# correct, so only contention exposes it). That loses the election underneath
# the script rather than inside it, and the case would report a defect the code
# does not have. Probed rather than assumed, and skipped out loud: a silent
# pass here would read as evidence the election holds.
atomic=1
mkdir -p "$tmp/mkatom"
for probe in $(seq 1 25); do
  : >"$tmp/mkatom/w"
  for n in 1 2 3 4 5 6 7 8; do
    (mkdir "$tmp/mkatom/l.$probe" 2>/dev/null && printf 'x\n' >>"$tmp/mkatom/w") &
  done
  wait
  [ "$(wc -l <"$tmp/mkatom/w" | tr -d ' ')" = 1 ] || atomic=0
done
c25b_ran=1
if [ "$atomic" = 0 ]; then
  # On stdout, in the suite's own skip form: a run whose only trace of this is
  # a stderr line reads, in a captured CI log, exactly like one that tested the
  # election and passed.
  c25b_ran=0
  echo "skip: c25b concurrent-election race ($(command -v mkdir) admits several concurrent mkdir winners)"
else
  for n in 1 2 3; do
    senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
      launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" \
      >"$tmp/o25b.$n" 2>&1 &
  done
  wait
  won=0
  lost=0
  for n in 1 2 3; do
    if grep -q "^launched sjw25 " "$tmp/o25b.$n"; then
      won=$((won + 1))
    elif grep -qE "already in flight|already running" "$tmp/o25b.$n"; then
      # How a loser lost is the point: a crash and a single-initiator refusal
      # both leave one winner, and only one of them is the election working.
      lost=$((lost + 1))
    fi
  done
  if [ "$won" != 1 ] || [ "$lost" != 2 ]; then
    for n in 1 2 3; do
      printf 'c25b launch %s said: %s\n' "$n" "$(cat "$tmp/o25b.$n")" >&2
    done
    fail "c25b: expected one winner and two refusals, got $won and $lost"
  fi
  snap25=$(ps_rows)
  n25=$(printf '%s\n' "$snap25" | grep -Fc -- "_supervise sjw25 $wdir25")
  [ "$n25" = 1 ] || fail "c25b: exactly one supervisor expected after the race, found $n25"
  # "one supervisor AND one pid file": the criterion is not met if a loser
  # overwrote the winner's pid file on its way out.
  sup25b=$(cat "$wdir25/supervisor.pid" 2>/dev/null) || sup25b=''
  [ -n "$sup25b" ] || fail "c25b: no supervisor pid file survived the race"
  printf '%s\n' "$snap25" \
    | awk -v p="$sup25b" -v m="_supervise sjw25 $wdir25" \
      '$1 == p && index($0, m) { f = 1 } END { exit f ? 0 : 1 }' \
    || fail "c25b: supervisor.pid ($sup25b) does not name the surviving supervisor"
  senv "$home" "$rec" -- stop sjw25 --grace 2 >/dev/null || fail "c25b: stop exited non-zero"
fi
# (c) a lock whose holder is gone is broken, so one hard kill cannot wedge
#     `launch` the way it used to wedge `recover`; a lock whose holder is this
#     very shell is not.
# Bare `mkdir`, not `-p`: if the preceding launch leaked its lock, `-p` would
# silently adopt the leak and the case would test nothing.
mkdir "$wdir25/launch.lock" || fail "c25c: a launch leaked its lock, or it cannot be planted"
printf '%s\n' "$$" >"$wdir25/launch.lock/holder"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" >/dev/null 2>&1
[ $? -eq 3 ] || fail "c25c: a launch whose holder is alive must refuse the second caller (exit 3)"
printf '%s\n' 999999999 >"$wdir25/launch.lock/holder"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" >/dev/null \
  || fail "c25c: a lock whose holder is gone must be broken and the launch proceed"
senv "$home" "$rec" -- stop sjw25 --grace 2 >/dev/null || fail "c25c: stop exited non-zero"
# (d) the pid files are published by rename, never by a bare redirect. A
#     redirect creates the file before the write lands, and every reader treats
#     an empty pid file as nothing-recorded — which is what let a second launch
#     call a live worker dead and start a supervisor over it, and would let
#     `recover` resume a session that is still running. The window is too
#     narrow to hit on demand, so the mechanism is what gets pinned.
#     The helper's own body is audited too, not just its call sites: an audit
#     that only checked `supervise` would still pass if `write_pidfile` were
#     reverted to a bare redirect, which is exactly the defect being pinned.
audit=$(awk '/^supervise\(\)/, /^}/' "$SJ")
[ -n "$audit" ] || fail "c25d: the supervisor body was not found for the audit"
for f in supervisor worker; do
  printf '%s\n' "$audit" | grep -qF "write_pidfile \"\$sv_dir/$f.pid\"" \
    || fail "c25d: $f.pid must be published through the atomic helper"
done
helper=$(awk '/^write_pidfile\(\)/, /^}/' "$SJ")
[ -n "$helper" ] || fail "c25d: write_pidfile was not found for the audit"
printf '%s\n' "$helper" | grep -q 'mv ' \
  || fail "c25d: write_pidfile must publish by rename"
# No redirect anywhere on the publication path may name the target itself,
# quoted or bare — both forms are the same defect.
printf '%s\n' "$audit" "$helper" | grep -qE '>[[:space:]]*"?[^ "|&;]*\.pid"?([[:space:]]|$)' \
  && fail "c25d: a pid file must not be published by a bare redirect"
# The helper writes its temp and renames it; if the temp were the target the
# rename would be a no-op and the window would be back.
printf '%s\n' "$helper" | grep -qE "mv[[:space:]]+\"[\$]wp_tmp\"[[:space:]]+\"[\$]1\"" \
  || fail "c25d: write_pidfile must rename its staging temp over the target"
if [ "$c25b_ran" = 1 ]; then
  echo "ok: c25 launch elects a single initiator under contention and breaks a dead holder's lock (obs:917e384e)"
else
  echo "ok: c25 launch refuses a second caller and breaks a dead holder's lock (contention leg skipped) (obs:917e384e)"
fi

echo "all fleet-streamjson tests passed"
