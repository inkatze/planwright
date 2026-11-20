#!/bin/bash
# Tests for scripts/fleet-streamjson.sh, the stream-json-persistent supervisor
# primitive: receipts, the pending-age alarm, answers, crash recovery, and the
# launch shape (D-4, D-5 · REQ-A1.3, REQ-A1.9, REQ-E1.1, REQ-E1.2, REQ-E1.3,
# REQ-E1.4, REQ-E1.5).
#
# Contract under test (one shim fixture per contract clause):
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
#   - REQ-E1.5: receipt state survives a supervisor kill; dedup on request
#     identity holds across the resume boundary.
#   - REQ-A1.3: the observe surface (event-stream capture) exists under the
#     fleet home, and completion/liveness is surfaced from the supervisor +
#     event stream (`status`).
#   - REQ-A1.9 / D-12: prompt text reaches the worker as data on stdin, the
#     launch argv carries the pinned -p stream-json shape, `--bare` is
#     refused, and hostile handles and response bodies are refused.
#
# Companions: tests/test-fleet-streamjson-delivery.sh (prompt and frame
# delivery, deny messages, lock breaks) and tests/test-fleet-streamjson-status.sh
# (launch election, result frames, preflight, escalation tick, status verdicts).
# The close verb's behaviour both session-grade rungs share is the
# rung-parameterised table in tests/lib/fleet-stop-table.sh.
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-streamjson-fixture.sh
. "$here/lib/fleet-streamjson-fixture.sh" || exit 1

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
# The question this writes is what the queue's tally tells an approval by.
[ "$(aenv "$home" queue --tally)" = "operator${tab}0
approvals${tab}1" ] || fail "c1: the request row must tally as an approval, got: $(aenv "$home" queue --tally)"
out=$(senv "$home" "$rec" -- status sjw1) || fail "c1: status exited non-zero"
case $out in
  "status sjw1 completed result=success") : ;;
  *) fail "c1: status should surface completion from the event stream, got: $out" ;;
esac
echo "ok: c1 can_use_tool receipt -> one journal row + one queue item, dedup, capture, completion (REQ-E1.1, REQ-A1.3)"

# ---------------------------------------------------------------------------
# c1f (quota-handling REQ-E1.3): the supervisor keeps the worker's newest
#    rate-limit frame beside its other runtime state, and a malformed one
#    neither replaces it nor stops the capture. Its own variables: c2 reads
#    c1's home and worker directory.
# ---------------------------------------------------------------------------
h1f="$tmp/h1f"
r1f="$tmp/r1f"
mkdir -p "$r1f"
rl() {
  printf '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":%s,"resetsAt":1900000000},"seven_day":{"utilization":%s,"resetsAt":1900500000}}},"session_id":"%s"}' "$1" "$2" "$sid"
}
printf '%s\n%s\n%s\n%s\n%s\n' "$line_init" "$(rl 0.2 0.4)" "$(rl 0.25 0.45)" \
  '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}' "$line_result" >"$tmp/ev1f"
printf 'frames\n' >"$tmp/prompt1f"
senv "$h1f" "$r1f" SHIM_EVENTS="$tmp/ev1f" -- \
  launch sjw1f execution-backends:4 --prompt-file "$tmp/prompt1f" --foreground \
  || fail "c1f: foreground launch exited non-zero"
rlf="$h1f/streamjson/sjw1f/ratelimit"
[ -f "$rlf" ] || fail "c1f: no rate-limit frame stored beside the worker's state"
awk -F "$tab" '$1 == "frame" && $3 == "0.25" && $4 == "1900000000" && $5 == "0.45" && $6 == "1900500000" && $7 == "end"' "$rlf" \
  | grep -q . || fail "c1f: the stored frame is not the newest well-formed one: $(cat "$rlf")"
[ "$(senv "$h1f" "$r1f" -- status sjw1f)" = "status sjw1f completed result=success" ] \
  || fail "c1f: a malformed frame disturbed the capture"
echo "ok: c1f the supervisor stores the newest rate-limit frame (quota-handling REQ-E1.3)"

# ---------------------------------------------------------------------------
# c2 (REQ-E1.1): the pending-age alarm fires past the threshold (escalation
#    only), and stays quiet below it.
# ---------------------------------------------------------------------------
received=$(awk -F'\t' -v id="$req_perm" '$1 == id { print $3 }' "$wdir/journal")
[ -n "$received" ] || fail "c2: cannot read the received epoch"
live_pids "$wdir"
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
# An alarm scan must not publish the projection while another writer holds the
# journal. The sweep reads to find aged requests and then publishes; without
# serialising those two steps an answer landing between them is undone by the
# publish, re-posting a decision the operator just made. The race window itself
# is not stageable deterministically, but the property that closes it is: with
# the journal held by a live holder, the scan must decline to publish and leave
# the request for the next pass rather than writing a row it cannot vouch for.
cp "$wdir/journal" "$tmp/j2.orig" || fail "c2: cannot snapshot the journal"
aenv "$home" clear sjw1 >/dev/null 2>&1 || :
plant_lock "$wdir/journal.lock" $$
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900) \
  || fail "c2: alarm-scan over a held journal exited non-zero"
[ -z "$out" ] || fail "c2: a held journal must yield no alarm line, got: $out"
[ "$(aenv "$home" queue --count)" = 0 ] \
  || fail "c2: an alarm scan must not publish a queue row while the journal is held"
rm -f "$wdir/journal.lock"
# Put the fixture back: later cases share this worker's journal and queue row,
# and a case that leaves borrowed state changed breaks them from a distance,
# which is a worse failure to read than the one it was testing.
cp "$tmp/j2.orig" "$wdir/journal" || fail "c2: cannot restore the journal"
senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900 >/dev/null \
  || fail "c2: cannot restore the escalated queue row"
unlive_pids "$wdir"
echo "ok: c2 an alarm scan declines to publish while the journal is held (REQ-E1.1)"
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
live_pids "$wdir3"
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900) \
  || fail "c3: alarm-scan exited non-zero"
printf '%s\n' "$out" | grep -q "^alarm sjw3 $req_q " \
  || fail "c3: the question item should carry the same alarm coupling, got: $out"
unlive_pids "$wdir3"
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
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir5/journal" \
  || fail "c5: the pending journal row never appeared"
out=$(senv "$home" "$rec" -- status sjw5) || fail "c5: status exited non-zero"
# A live worker parked on a pending receipt is waiting, not running: the
# verdict says so and carries the count and the oldest age.
case $out in
  "status sjw5 awaiting-input pending=1 oldest="*"s supervisor="*" worker="*) : ;;
  *) fail "c5: status should report awaiting-input with the pending count mid-flight, got: $out" ;;
esac
# steer (the steer-in-flight path for this rung): a tower message reaches the
# live worker as a USER turn on its stdin, attributed, with a receipt row —
# and it settles nothing: the pending request is still pending afterwards.
printf 'merge main into your branch.\nthen "re-run" the gate\n' >"$tmp/steer5"
out=$(senv "$home" "$rec" -- steer sjw5 --message-file "$tmp/steer5") \
  || fail "c5: steer exited non-zero"
case $out in
  "steered sjw5 "[0-9]*) : ;;
  *) fail "c5: unexpected steer output: $out" ;;
esac
poll_until --what 'the steered turn' -- grep -q '"type":"user"' "$rec/stdin" \
  || fail "c5: the steered user turn never reached the worker stdin"
grep '"type":"user"' "$rec/stdin" | grep -q '\[planwright tower relay -> sjw5\]\\nmerge main into your branch.\\nthen \\"re-run\\" the gate' \
  || fail "c5: the steer must carry the attribution header and the JSON-encoded message text"
grep -q control_response "$rec/stdin" \
  && fail "c5: steer must never compose a control_response"
grep -q "^$req_perm$tab.*${tab}pending" "$wdir5/journal" \
  || fail "c5: steer must not settle the pending request"
[ "$(wc -l <"$wdir5/steers" | tr -d ' ')" = 1 ] \
  || fail "c5: steer should leave exactly one receipt row"
grep -q "$tab$tmp/steer5\$" "$wdir5/steers" \
  || fail "c5: the steer receipt should name the message file"
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

# steer refusals on the now-settled (dead-channel) c5 worker: a dead channel is
# a visible exit 3, never a hang on the fifo; a missing, empty, or oversize
# message file is refused (exit 2) before the channel is touched.
senv "$home" "$rec" -- steer sjw5 --message-file "$tmp/steer5" >/dev/null 2>&1
[ $? -eq 3 ] || fail "c5: steer over a dead channel must exit 3"
[ "$(wc -l <"$wdir5/steers" | tr -d ' ')" = 1 ] \
  || fail "c5: a refused steer must leave no receipt row"
senv "$home" "$rec" -- steer sjw5 --message-file "$tmp/no-such-steer" >/dev/null 2>&1
[ $? -eq 2 ] || fail "c5: steer with a missing message file must exit 2"
printf '  \n\n' >"$tmp/steer-empty"
senv "$home" "$rec" -- steer sjw5 --message-file "$tmp/steer-empty" >/dev/null 2>&1
[ $? -eq 2 ] || fail "c5: steer with a blank message file must exit 2"
head -c 65537 /dev/zero | tr '\0' 'x' >"$tmp/steer-big"
senv "$home" "$rec" -- steer sjw5 --message-file "$tmp/steer-big" >/dev/null 2>&1
[ $? -eq 2 ] || fail "c5: steer with an oversize message file must exit 2 (refused whole)"
senv "$home" "$rec" -- steer 'sjw5;x' --message-file "$tmp/steer5" >/dev/null 2>&1
[ $? -eq 2 ] || fail "c5: steer must refuse an out-of-grammar worker handle"
echo "ok: c5b steer refuses a dead channel (3) and bad message files (2) without a receipt"

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
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir7/journal" \
  || fail "c7: the pending journal row never appeared"
sup_pid=$(cat "$wdir7/supervisor.pid")
wrk_pid=$(cat "$wdir7/worker.pid")
kill -9 "$wrk_pid" 2>/dev/null
kill -9 "$sup_pid" 2>/dev/null
wait "$launch_pid" 2>/dev/null
poll_until --what 'the processes gone' -- sh -c "! kill -0 $sup_pid 2>/dev/null && ! kill -0 $wrk_pid 2>/dev/null" \
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
plant_lock "$wdir7/recover.lock" $$
senv "$home" "$rec" -- recover sjw7 --foreground >/dev/null 2>&1
[ $? -eq 3 ] || fail "c7: a concurrent recovery must be refused (exit 3)"
rm -f "$wdir7/recover.lock"
# Orphan liveness: a still-alive worker pid refuses recovery.
sleep 60 &
alive_pid=$!
printf '%s\n' "$alive_pid" >"$wdir7/worker.pid"
# The crashed worker's start record is for another process: the planted live
# one gets its own, or its pid would read as a reissued number.
/bin/sh "$here/../scripts/fleet-death-evidence.sh" start "$alive_pid" >"$wdir7/worker.start" \
  || fail "c7: the planted worker's start must be readable"
senv "$home" "$rec" -- recover sjw7 --foreground >/dev/null 2>&1
[ $? -eq 3 ] || fail "c7: recovery over a live worker must be refused (exit 3)"
kill -9 "$alive_pid" 2>/dev/null
wait "$alive_pid" 2>/dev/null
rm -f "$wdir7/worker.pid" "$wdir7/worker.start"
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
live_pids "$wdir7"
out=$(senv "$home" "$rec" -- alarm-scan --now $((received + 1000)) --threshold 900) \
  || fail "c7: post-recovery alarm-scan exited non-zero"
printf '%s\n' "$out" | grep -q "^alarm sjw7 $req_perm " \
  || fail "c7: the pending item's alarm must re-arm after recovery, got: $out"
unlive_pids "$wdir7"
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
# A recovered mission-control launcher's worker never runs without its launcher
# registry row: the row stays, is restored from the copy the launch kept, or
# the recover is refused; a worker the launcher never launched recovers as before.
# ---------------------------------------------------------------------------
home8r="$tmp/h8r"
rec8r="$tmp/r8r"
ev8r="$tmp/ev8r"
printf '%s\n%s\n' "$line_perm" "$line_result" >"$ev8r"
mkdir -p "$rec8r" "$home8r/dispatch-markers" "$home8r/mission-control/sessions"
row_text="$(printf 'format\t1\nname\tmc-p-worker-0123456789\nstate\tlaunched\ntoken\trowtoken-own\nprogram\tp\nowner\tmission-control:p\nkind\tworker\nscope\tx\nbackend\tstream-json\nlaunched\t1\n')"
mk8r() { # mk8r <worker> [<owner>]: a crashed worker dir, with a dispatch record when an owner is given
  mkdir -p "$home8r/streamjson/$1"
  printf 'execution-backends:4\n' >"$home8r/streamjson/$1/scope"
  printf '%s\n' "$sid" >"$home8r/streamjson/$1/session"
  printf 'worker\n' >"$home8r/streamjson/$1/profile"
  [ -z "${2:-}" ] || printf '%s\tx\t%s\tstream-json-persistent\t%s\t-\n' "$1" "$2" "$home8r/streamjson/$1" >"$home8r/dispatch-markers/$1"
}
w='mc-p-worker-0123456789'
mk8r "$w" mission-control:p
printf '%s\n' "$row_text" >"$home8r/mission-control/sessions/$w"
: >"$rec8r/argv"
senv "$home8r" "$rec8r" SHIM_EVENTS="$ev8r" SHIM_READ_FIRST=0 -- recover "$w" --foreground >"$tmp/o8r1" 2>&1 \
  || fail "c8r: recovering a launcher-registered worker exited non-zero: $(cat "$tmp/o8r1")"
[ "$(cat "$home8r/mission-control/sessions/$w")" = "$row_text" ] \
  || fail "c8r: a recover must leave the worker's launcher row intact"
rm -f "$home8r/mission-control/sessions/$w"
printf '%s\n' "$row_text" >"$home8r/streamjson/$w/launcher-row"
: >"$rec8r/argv"
senv "$home8r" "$rec8r" SHIM_EVENTS="$ev8r" SHIM_READ_FIRST=0 -- recover "$w" --foreground >/dev/null 2>&1 \
  || fail "c8r: recovering a worker whose row is gone, its launch's copy kept, exited non-zero"
[ "$(cat "$home8r/mission-control/sessions/$w" 2>/dev/null)" = "$row_text" ] \
  || fail "c8r: a recover must restore the launcher row from the copy its launch kept"
w2='mc-p-worker-9876543210'
mk8r "$w2" mission-control:p
: >"$rec8r/argv"
senv "$home8r" "$rec8r" SHIM_EVENTS="$ev8r" SHIM_READ_FIRST=0 -- recover "$w2" --foreground >"$tmp/o8r" 2>&1
[ $? -eq 3 ] || fail "c8r: a launcher worker with no row and no copy must be refused (exit 3)"
[ ! -s "$rec8r/argv" ] || fail "c8r: the refused recover must never spawn the worker"
grep -q 'no launcher registry row' "$tmp/o8r" || fail "c8r: the refusal must name its reason: $(cat "$tmp/o8r")"
[ ! -e "$home8r/mission-control/sessions/$w2" ] || fail "c8r: a refused recover must write no row"
w3=sjw8r-plain
mk8r "$w3" tower-abc
: >"$rec8r/argv"
senv "$home8r" "$rec8r" SHIM_EVENTS="$ev8r" SHIM_READ_FIRST=0 -- recover "$w3" --foreground >/dev/null 2>&1 \
  || fail "c8r: a worker the launcher never launched must still recover"
[ ! -e "$home8r/mission-control/sessions/$w3" ] || fail "c8r: a recover must not invent a row for a worker the launcher never launched"
echo "ok: c8r a recover keeps, restores or refuses on the launcher's registry row"

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
senv "$home" "$rec" SHIM_EVENTS="$ev" PLANWRIGHT_MESSAGING_INBOUND=refuse PLANWRIGHT_WORKER_HANDLE=stale \
  PLANWRIGHT_TOWER_ID=stale-tower PLANWRIGHT_TOWER_PID=1 PLANWRIGHT_TOWER_CHECKOUT=/nonexistent \
  PLANWRIGHT_SESSION_BACKEND=tmux -- \
  launch sjw9 execution-backends:4 --prompt-file "$tmp/prompt9" --foreground \
  || fail "c9: launch exited non-zero"
grep -qx 'tower=<unset>/<unset>/<unset>/<unset>' "$rec/env" \
  || fail "c9: the dispatcher's tower identity reached the worker: $(grep '^tower=' "$rec/env")"
# The background-job guard keys on this: a stream-json session never resumes
# on a background job's completion notice.
grep -qx 'backend=stream-json' "$rec/env" \
  || fail "c9: the worker must be told it runs on the stream-json backend: $(grep '^backend=' "$rec/env")"
argv_line=$(cat "$rec/argv")
case $argv_line in
  *"-p "*"--input-format stream-json"*"--output-format stream-json"*"--verbose"*"--permission-prompt-tool stdio"*) : ;;
  *) fail "c9: the launch argv is missing the pinned stream-json shape: $argv_line" ;;
esac
case $argv_line in
  *--bare*) fail "c9: --bare must never appear in a launch argv (D-12)" ;;
esac
# The worker is launched THROUGH the environment-hardening wrapper (D-10,
# REQ-D1.1). The wrapper execs the CLI, so it never appears in the CLI's own
# argv — what it leaves is the environment. Without a resolvable planwright
# root the worker-settings auto-approve hook cannot find its own script, so the
# worker asks permission for commands the guard would have approved, which
# presents as a hung worker rather than a blocked one.
grep -qx 'ghost=false' "$rec/env" \
  || fail "c9: the launched CLI must inherit the ghost-text pin: $(cat "$rec/env" 2>/dev/null)"
root_line=$(grep '^plugin_root=' "$rec/env" | tail -n 1)
case ${root_line#plugin_root=} in
  /*) [ -f "${root_line#plugin_root=}/scripts/fleet-streamjson.sh" ] \
    || fail "c9: CLAUDE_PLUGIN_ROOT does not point at a planwright root: $root_line" ;;
  *) fail "c9: the launched CLI must inherit an absolute CLAUDE_PLUGIN_ROOT, got: $root_line" ;;
esac
# The permission-mode source is structural, not a caller's responsibility:
# Claude Code honors `defaultMode: "auto"` from the operator's own user
# settings, so a launch carrying no readable --settings fragment silently
# inherits it and fleet-dispatch-guard.sh refuses the argv (risk row 20).
case $argv_line in
  *"--settings "*worker-settings.json*) : ;;
  *) fail "c9: the launch argv must pin --settings <worker-settings fragment>: $argv_line" ;;
esac
# shellcheck disable=SC2086 # the recorded argv must re-split into the guard's argument vector
"$here/../scripts/fleet-dispatch-guard.sh" check-launch $argv_line >/dev/null 2>&1 \
  || fail "c9: the pinned launch argv must pass fleet-dispatch-guard check-launch"
# The session is named after the worker handle, which the relay's
# stream-json-persistent grammar owns, and the worker identity and inbound
# layer reach the worker's environment (fleet-messaging D-8, D-17, D-19).
case "$argv_line " in
  *" --name sjw9 "*) : ;;
  *) fail "c9: the launch argv must name the session after its handle: $argv_line" ;;
esac
"$here/../scripts/orchestrate-relay.sh" validate-handle stream-json-persistent sjw9 \
  || fail "c9: the derived name fails the stream-json-persistent grammar"
for want in handle=sjw9 scope=execution-backends:4 inbound=accept; do
  grep -qx "$want" "$rec/env" || fail "c9: the worker's environment lacks $want: $(cat "$rec/env")"
done
# A handle the stream-json-persistent grammar refuses names no session: the
# launch is refused before anything is spawned.
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch "sjw9=x" execution-backends:4 --prompt-file "$tmp/prompt9" --foreground >/dev/null 2>"$tmp/c9name.err"
[ $? -eq 2 ] || fail "c9: a handle outside the session-name grammar must be refused (exit 2)"
[ ! -s "$rec/argv" ] || fail "c9: the refused name must never spawn the worker"
# A caller-supplied --name would override the session name the handle sets.
for nm in --name --name=other -n; do
  : >"$rec/argv"
  senv "$home" "$rec" -- \
    launch sjw9n execution-backends:4 --prompt-file "$tmp/prompt9" --foreground -- "$nm" other >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c9: a caller-supplied '$nm' must be refused (exit 2)"
  [ ! -s "$rec/argv" ] || fail "c9: the refused '$nm' launch must never spawn the worker"
done
# A relaunch whose launch persisted no scope has no worker scope to export: it
# is refused, naming the missing variable, rather than launched unidentified.
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9r --resume-session 11111111-2222-3333-4444-555555555555 --foreground >/dev/null 2>"$tmp/c9scope.err"
[ $? -eq 2 ] || fail "c9: a relaunch with no recorded scope must be refused (exit 2)"
grep -q PLANWRIGHT_WORKER_SCOPE "$tmp/c9scope.err" || fail "c9: the scope refusal must name the variable: $(cat "$tmp/c9scope.err")"
[ ! -s "$rec/argv" ] || fail "c9: the scope-less relaunch must never spawn the worker"
# shellcheck disable=SC2016 # matching the literal '$(touch' substring, not expanding it
grep -q '\$(touch PWNED-marker)' "$rec/stdin" \
  || fail "c9: the metacharacter prompt must reach the worker as literal data"
grep -q '\\t' "$rec/stdin" || fail "c9: tab should arrive JSON-escaped"
[ ! -e "PWNED-marker" ] && [ ! -e "$tmp/PWNED-marker" ] \
  || fail "c9: prompt text reached a shell (command substitution executed)"
# The posture refusal: a pinned fragment is not a pinned posture if a caller can
# append a flag that overrides it. Each of these either outranks the fragment's
# defaultMode or removes the allowlist from the approval path entirely.
for _flag in --permission-mode --permission-mode=auto --dangerously-skip-permissions; do
  : >"$rec/argv"
  senv "$home" "$rec" -- \
    launch "sjw9m$$" execution-backends:4 --prompt-file "$tmp/prompt9" --foreground -- "$_flag" \
    >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c9: a caller-supplied '$_flag' must be refused (exit 2)"
  [ ! -s "$rec/argv" ] || fail "c9: the refused launch ('$_flag') must never spawn the worker"
done

# The structural refusal: a caller-supplied --bare never launches.
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9b execution-backends:4 --prompt-file "$tmp/prompt9" --foreground -- --bare \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c9: a caller-supplied --bare must be refused (exit 2)"
[ ! -s "$rec/argv" ] || fail "c9: the refused launch must never spawn the worker"
# The same structure for the mode source: a caller-supplied --settings (either
# spelling) would let a second fragment override the pinned one.
for sj_settings in "--settings" "--settings=$tmp/other.json"; do
  : >"$rec/argv"
  senv "$home" "$rec" -- \
    launch sjw9c execution-backends:4 --prompt-file "$tmp/prompt9" --foreground -- \
    "$sj_settings" "$tmp/other.json" >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c9: a caller-supplied $sj_settings must be refused (exit 2)"
  [ ! -s "$rec/argv" ] || fail "c9: the refused --settings launch must never spawn the worker"
done
# Fail closed when the fragment cannot be read: a copy of scripts/ with no
# config/ sibling has no mode source, and must refuse rather than launch a
# worker that inherits the operator's permission mode.
mkdir -p "$tmp/nocfg"
cp -R "$here/../scripts" "$tmp/nocfg/scripts"
: >"$rec/argv"
env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" SHIM_RECORD_DIR="$rec" \
  /bin/sh "$tmp/nocfg/scripts/fleet-streamjson.sh" \
  launch sjw9d execution-backends:4 --prompt-file "$tmp/prompt9" --foreground \
  >/dev/null 2>"$tmp/nocfg.err"
[ $? -eq 7 ] || fail "c9: a missing worker-settings fragment must refuse the launch (exit 7)"
grep -q "worker-settings.json" "$tmp/nocfg.err" \
  || fail "c9: the fragment refusal must name the resolved path"
[ ! -s "$rec/argv" ] || fail "c9: the fragment-less launch must never spawn the worker"
# The same refusal through the planwright-root override: PLANWRIGHT_ROOT names a
# copy of the root whose worker profile cannot be read.
mkdir -p "$tmp/badroot/config" "$tmp/badroot/scripts"
cp "$here/../config/worker-settings.json" "$tmp/badroot/config/"
chmod 000 "$tmp/badroot/config/worker-settings.json"
if [ -r "$tmp/badroot/config/worker-settings.json" ]; then
  echo "skip: c9 unreadable profile: mode 000 does not make a file unreadable to this user"
else
  : >"$rec/argv"
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_ROOT="$tmp/badroot" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" SHIM_RECORD_DIR="$rec" \
    /bin/sh "$here/../scripts/fleet-streamjson.sh" \
    launch sjw9e execution-backends:4 --prompt-file "$tmp/prompt9" --foreground \
    >/dev/null 2>"$tmp/badroot.err"
  [ $? -eq 7 ] || fail "c9: an unreadable profile under PLANWRIGHT_ROOT must refuse the launch (exit 7)"
  grep -qF "$tmp/badroot/config/worker-settings.json" "$tmp/badroot.err" \
    || fail "c9: the unreadable-profile refusal must name the profile: $(cat "$tmp/badroot.err")"
  [ ! -s "$rec/argv" ] || fail "c9: the unreadable-profile launch must never spawn the worker"
fi
chmod 644 "$tmp/badroot/config/worker-settings.json"
echo "ok: c9 pinned non-bare launch shape with the settings pin, prompt-as-data, --bare and --settings refused, missing fragment fails closed (REQ-A1.9, D-12, D-19)"

# ---------------------------------------------------------------------------
# c9p (mission-control REQ-G1.1): --profile pins another shipped fragment by
#    kind, a recover relaunches under the recorded one, and anything else is
#    refused.
# ---------------------------------------------------------------------------
for kind in tower mission-control; do
  : >"$rec/argv"
  senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
    launch "sjw9p-$kind" mission-control:3 --prompt-file "$tmp/prompt9" --profile "$kind" --foreground \
    || fail "c9p: a --profile $kind launch exited non-zero"
  case $(cat "$rec/argv") in
    *"--settings "*"/config/$kind-settings.json"*) : ;;
    *) fail "c9p: a --profile $kind launch must pin $kind-settings.json: $(cat "$rec/argv")" ;;
  esac
  [ "$(cat "$home/streamjson/sjw9p-$kind/profile" 2>/dev/null)" = "$kind" ] \
    || fail "c9p: the launch must record the $kind profile for its recover"
done
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9q mission-control:3 --prompt-file "$tmp/prompt9" --profile "$tmp/other.json" --foreground >/dev/null 2>&1
[ $? -eq 2 ] || fail "c9p: a --profile that is not a shipped kind must be refused (exit 2)"
[ ! -s "$rec/argv" ] || fail "c9p: the refused --profile launch must never spawn the worker"
mkdir -p "$home/streamjson/sjw9t"
printf 'mission-control:3\n' >"$home/streamjson/sjw9t/scope"
printf 'tower\n' >"$home/streamjson/sjw9t/profile"
: >"$rec/argv"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- \
  launch sjw9t --resume-session "$sid" --foreground >/dev/null 2>&1
case $(cat "$rec/argv") in
  *"--settings "*"/config/tower-settings.json"*) : ;;
  *) fail "c9p: a relaunch must pin the recorded tower profile: $(cat "$rec/argv")" ;;
esac
printf 'bogus\n' >"$home/streamjson/sjw9t/profile"
: >"$rec/argv"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- \
  launch sjw9t --resume-session "$sid" --foreground >/dev/null 2>&1
[ $? -eq 7 ] || fail "c9p: a relaunch with an unknown recorded profile must be refused (exit 7)"
[ ! -s "$rec/argv" ] || fail "c9p: the refused relaunch must never spawn the worker"
# Only a worker carries the worker identity.
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" PLANWRIGHT_WORKER_HANDLE=stale PLANWRIGHT_WORKER_LAUNCH_TOKEN=aaaaaaaaaaaaaaaa PLANWRIGHT_MC_TOKEN=callertoken-other -- \
  launch sjw9i mission-control:3 --prompt-file "$tmp/prompt9" --profile tower --foreground \
  || fail "c9p: the identity-case tower launch exited non-zero"
if ! grep -qx 'handle=<unset>' "$rec/env" || ! grep -qx 'scope=<unset>' "$rec/env"; then
  fail "c9p: a tower-profile session must carry no worker identity: $(cat "$rec/env")"
fi
grep -qx 'inbound=accept' "$rec/env" || fail "c9p: a tower-profile session must still accept inbound messages"
grep -qx 'launch_token=<unset>' "$rec/env" || fail "c9p: a tower-profile session must carry no worker launch token"
grep -qx 'mc_token=<unset>' "$rec/env" || fail "c9p: a tower-profile session must drop an inherited mission-control token"
[ "$(cat "$home/streamjson/sjw9i/profile")" = tower ] && [ ! -e "$home/streamjson/sjw9i/profile.tmp" ] \
  || fail "c9p: the profile record must be written whole, with no temporary left"
# A fresh mission-control launch holds a token only as the launcher's
# explicit argument: one inherited from the caller is dropped.
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" PLANWRIGHT_MC_TOKEN=callertoken-other -- \
  launch sjw9m mission-control:3 --prompt-file "$tmp/prompt9" --profile mission-control --foreground \
  || fail "c9p: the inherited-token mission-control launch exited non-zero"
grep -qx 'mc_token=<unset>' "$rec/env" \
  || fail "c9p: a mission-control launch must drop an inherited token: $(grep '^mc_token=' "$rec/env")"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" PLANWRIGHT_MC_TOKEN=callertoken-other -- \
  launch sjw9n mission-control:3 --prompt-file "$tmp/prompt9" --profile mission-control --mc-token argtoken-own --foreground \
  || fail "c9p: the --mc-token mission-control launch exited non-zero"
grep -qx 'mc_token=argtoken-own' "$rec/env" \
  || fail "c9p: a mission-control launch must hold the --mc-token it was given: $(grep '^mc_token=' "$rec/env")"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9o mission-control:3 --prompt-file "$tmp/prompt9" --profile tower --mc-token argtoken-own --foreground \
  || fail "c9p: the --mc-token tower launch exited non-zero"
grep -qx 'mc_token=<unset>' "$rec/env" \
  || fail "c9p: a tower-profile launch must not take a --mc-token: $(grep '^mc_token=' "$rec/env")"
# A recover with no recorded profile: a worker's from before the record
# existed keeps the worker fragment, a mission-control launch's is refused.
mkdir -p "$home/streamjson/sjw9old"
printf 'mission-control:3\n' >"$home/streamjson/sjw9old/scope"
: >"$rec/argv"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- launch sjw9old --resume-session "$sid" --foreground >/dev/null 2>&1
case $(cat "$rec/argv") in
  *"--settings "*"/config/worker-settings.json"*) : ;;
  *) fail "c9p: a recover with no record must keep the worker fragment: $(cat "$rec/argv")" ;;
esac
mkdir -p "$home/streamjson/mc-alpha-tower-0123456789"
printf 'mission-control:3\n' >"$home/streamjson/mc-alpha-tower-0123456789/scope"
: >"$rec/argv"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- launch mc-alpha-tower-0123456789 --resume-session "$sid" --foreground >/dev/null 2>&1
[ $? -eq 7 ] || fail "c9p: a mission-control recover with no recorded profile must be refused (exit 7)"
[ ! -s "$rec/argv" ] || fail "c9p: the refused mission-control recover must never spawn"

# c9m (mise task-file opt-in): `launch --mise-task-edit` on the worker profile
#    passes a per-launch settings file generated from the shipped one and
#    records the opt-in for the guard and for a recover; a launch without it
#    passes the shipped profile untouched; every other shape is refused.
shipped_profile="$here/../config/worker-settings.json"
mkdir -p "$tmp/mwt"
git init -q "$tmp/mwt" || fail "c9m: cannot build the fixture worktree"
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9m1 execution-backends:4 --prompt-file "$tmp/prompt9" --mise-task-edit --cwd "$tmp/mwt" --foreground \
  || fail "c9m: an opted-in launch exited non-zero"
m_settings=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
case $m_settings in
  "$home/streamjson/sjw9m1/"*) : ;;
  *) fail "c9m: the opted-in launch must pass a settings file in the worker's own state folder: $m_settings" ;;
esac
if cmp -s "$m_settings" "$shipped_profile"; then
  fail "c9m: the opted-in launch passed the shipped profile unchanged"
fi
jq -e '.permissions.deny | index("Edit(//**/mise.toml)") | not' "$m_settings" >/dev/null \
  || fail "c9m: the per-launch profile still carries the broad mise.toml deny"
jq -e '.permissions.deny | index("Edit(//**/mise.local.toml)") // index("Edit(//**/mise.*.toml)")' "$m_settings" >/dev/null \
  || fail "c9m: the per-launch profile dropped the local-file deny"
[ "$(cat "$home/streamjson/sjw9m1/mise-task-edit" 2>/dev/null)" = 1 ] \
  || fail "c9m: the launch must record the opt-in for its recover"
m_rec=$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)
grep -qx 'mise_task_edit=1' "$m_rec" || fail "c9m: the session record must carry mise_task_edit=1: $m_rec"
# A recover relaunches under the recorded opt-in, regenerating the file.
rm -f "$m_settings"
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- launch sjw9m1 --resume-session "$sid" --cwd "$tmp/mwt" --foreground >/dev/null 2>&1
m_settings2=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
[ "$m_settings2" = "$m_settings" ] && [ -s "$m_settings2" ] \
  || fail "c9m: a recover must regenerate the per-launch profile: $m_settings2"
grep -qx 'mise_task_edit=1' "$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)" \
  || fail "c9m: a recover must rewrite the session record with the opt-in"
# Without the opt-in: the shipped profile, byte for byte, and no marker.
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9m2 execution-backends:4 --prompt-file "$tmp/prompt9" --foreground \
  || fail "c9m: a plain launch exited non-zero"
m_plain=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
cmp -s "$m_plain" "$shipped_profile" || fail "c9m: a launch without the opt-in must pass the shipped profile byte for byte: $m_plain"
[ ! -e "$home/streamjson/sjw9m2/mise-task-edit" ] || fail "c9m: a plain launch must record no opt-in"
m_plain_rec=$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)
{ [ -s "$m_plain_rec" ] && ! grep -q '^mise_task_edit=' "$m_plain_rec"; } \
  || fail "c9m: a plain launch's session record must exist and carry no opt-in"
# A recover of a worker that never opted in stays on the shipped profile.
mkdir -p "$home/streamjson/sjw9m3"
printf 'execution-backends:4\n' >"$home/streamjson/sjw9m3/scope"
: >"$rec/argv"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- launch sjw9m3 --resume-session "$sid" --foreground >/dev/null 2>&1
m_plain2=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
cmp -s "$m_plain2" "$shipped_profile" || fail "c9m: a recover with no recorded opt-in must keep the shipped profile: $m_plain2"
# Only the worker profile opts in.
for kind in tower mission-control; do
  : >"$rec/argv"
  senv "$home" "$rec" -- \
    launch "sjw9m-$kind" mission-control:3 --prompt-file "$tmp/prompt9" --profile "$kind" --mise-task-edit --foreground >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c9m: --mise-task-edit with the $kind profile must be refused (exit 2)"
  [ ! -s "$rec/argv" ] || fail "c9m: the refused $kind opt-in must never spawn the worker"
done
# c9n (spec-branch launch record): --spec-branch reaches the session record
#    and the worker's state folder, a recover reads it back, a plain launch
#    carries none, and a unit branch, a malformed name or a non-worker profile
#    is refused before the worker spawns.
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9n1 execution-backends:4 --prompt-file "$tmp/prompt9" --spec-branch planwright/demo/amendment-1 --cwd "$tmp/mwt" --foreground \
  || fail "c9n: a launch with --spec-branch exited non-zero"
[ "$(cat "$home/streamjson/sjw9n1/spec-branch" 2>/dev/null)" = planwright/demo/amendment-1 ] \
  || fail "c9n: the launch must record the spec branch for its recover"
grep -qx 'spec_branch=planwright/demo/amendment-1' "$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)" \
  || fail "c9n: the session record must carry spec_branch"
: >"$rec/env"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- launch sjw9n1 --resume-session "$sid" --cwd "$tmp/mwt" --foreground >/dev/null 2>&1
grep -qx 'spec_branch=planwright/demo/amendment-1' "$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)" \
  || fail "c9n: a recover must rewrite the session record with the spec branch"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9n2 execution-backends:4 --prompt-file "$tmp/prompt9" --cwd "$tmp/mwt" --foreground \
  || fail "c9n: a plain launch exited non-zero"
{ [ ! -e "$home/streamjson/sjw9n2/spec-branch" ] && ! grep -q '^spec_branch=' "$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)"; } \
  || fail "c9n: a plain launch must carry no spec branch"
for bad in main planwright/flight/x-0123abcd planwright/demo/task-2 planwright/demo/../x; do
  : >"$rec/argv"
  senv "$home" "$rec" -- \
    launch sjw9n3 execution-backends:4 --prompt-file "$tmp/prompt9" --spec-branch "$bad" --foreground >/dev/null 2>&1
  [ $? -eq 2 ] && [ ! -s "$rec/argv" ] || fail "c9n: --spec-branch $bad must be refused before the worker spawns"
done
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9n4 mission-control:3 --prompt-file "$tmp/prompt9" --profile tower --spec-branch planwright/demo/amendment-1 --foreground >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -s "$rec/argv" ] || fail "c9n: --spec-branch with the tower profile must be refused"
# A worktree path the literal denies cannot name safely refuses the launch.
mkdir -p "$tmp/we*ird"
git init -q "$tmp/we*ird"
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9m4 execution-backends:4 --prompt-file "$tmp/prompt9" --mise-task-edit --cwd "$tmp/we*ird" --foreground >/dev/null 2>&1
[ $? -eq 7 ] || fail "c9m: an opted-in launch in a glob-character path must be refused (exit 7)"
[ ! -s "$rec/argv" ] || fail "c9m: the refused opted-in launch must never spawn the worker"
[ ! -e "$home/streamjson/sjw9m4/mise-task-edit" ] || fail "c9m: a refused opted-in launch must record no opt-in"
echo "ok: c9m mise task-file opt-in: per-launch profile, recorded for recover, shipped profile byte for byte without it"
# c9l (lefthook config opt-in): `launch --lefthook-edit` on the worker profile
#    passes a per-launch settings file whose two broad lefthook denies are
#    replaced, records the opt-in for the guard and for a recover, composes
#    with --mise-task-edit without opening the mise names, and is refused for
#    every other profile and every path the literal denies cannot name.
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9l1 execution-backends:4 --prompt-file "$tmp/prompt9" --lefthook-edit --cwd "$tmp/mwt" --foreground \
  || fail "c9l: an opted-in launch exited non-zero"
l_settings=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
case $l_settings in
  "$home/streamjson/sjw9l1/"*) : ;;
  *) fail "c9l: the opted-in launch must pass a settings file in the worker's own state folder: $l_settings" ;;
esac
jq -e '.permissions.deny | (index("Edit(//**/lefthook.*)") == null) and (index("Edit(//**/lefthook/**)") == null)' "$l_settings" >/dev/null \
  || fail "c9l: the per-launch profile still carries a broad lefthook deny"
jq -e '.permissions.deny | (index("Edit(//**/mise.toml)") != null) and (index("Edit(//**/lefthook-local.*)") != null) and (index("Edit(//**/githooks/**)") != null)' "$l_settings" >/dev/null \
  || fail "c9l: the per-launch profile opened more than the lefthook names"
[ "$(cat "$home/streamjson/sjw9l1/lefthook-edit" 2>/dev/null)" = 1 ] \
  || fail "c9l: the launch must record the opt-in for its recover"
[ ! -e "$home/streamjson/sjw9l1/mise-task-edit" ] || fail "c9l: the lefthook opt-in must not record the mise opt-in"
l_rec=$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)
{ grep -qx 'lefthook_edit=1' "$l_rec" && ! grep -q '^mise_task_edit=' "$l_rec"; } \
  || fail "c9l: the session record must carry lefthook_edit=1 and no mise field: $l_rec"
# A recover relaunches under the recorded opt-in, regenerating the file.
rm -f "$l_settings"
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_READ_FIRST=0 -- launch sjw9l1 --resume-session "$sid" --cwd "$tmp/mwt" --foreground >/dev/null 2>&1
l_settings2=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
{ [ "$l_settings2" = "$l_settings" ] && [ -s "$l_settings2" ] \
  && jq -e '.permissions.deny | index("Edit(//**/lefthook.*)") | not' "$l_settings2" >/dev/null; } \
  || fail "c9l: a recover must regenerate the per-launch profile: $l_settings2"
grep -qx 'lefthook_edit=1' "$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)" \
  || fail "c9l: a recover must rewrite the session record with the opt-in"
# A fresh launch without the flag drops the marker and passes the shipped profile.
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9l1 execution-backends:4 --prompt-file "$tmp/prompt9" --cwd "$tmp/mwt" --foreground \
  || fail "c9l: a plain relaunch of the same worker exited non-zero"
cmp -s "$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)" "$shipped_profile" \
  || fail "c9l: a launch without the opt-in must pass the shipped profile byte for byte"
[ ! -e "$home/streamjson/sjw9l1/lefthook-edit" ] || fail "c9l: a fresh launch without the flag must drop the recorded opt-in"
# Both opt-ins.
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9l2 execution-backends:4 --prompt-file "$tmp/prompt9" --mise-task-edit --lefthook-edit --cwd "$tmp/mwt" --foreground \
  || fail "c9l: a launch with both opt-ins exited non-zero"
b_settings=$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)
jq -e '.permissions.deny | [index("Edit(//**/mise.toml)"), index("Edit(//**/lefthook.*)")] | all(. == null)' "$b_settings" >/dev/null \
  || fail "c9l: both opt-ins must replace the mise and lefthook broad denies"
{ [ "$(cat "$home/streamjson/sjw9l2/lefthook-edit" 2>/dev/null)" = 1 ] && [ "$(cat "$home/streamjson/sjw9l2/mise-task-edit" 2>/dev/null)" = 1 ]; } \
  || fail "c9l: both opt-ins must be recorded"
b_rec=$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)
{ grep -qx 'lefthook_edit=1' "$b_rec" && grep -qx 'mise_task_edit=1' "$b_rec"; } \
  || fail "c9l: the session record must carry both fields when both opt-ins are given: $b_rec"
# The mise opt-in alone never opens the lefthook names.
: >"$rec/argv"
: >"$rec/env"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw9l3 execution-backends:4 --prompt-file "$tmp/prompt9" --mise-task-edit --cwd "$tmp/mwt" --foreground \
  || fail "c9l: a mise-only launch exited non-zero"
jq -e '.permissions.deny | (index("Edit(//**/lefthook.*)") != null) and (index("Edit(//**/lefthook/**)") != null)' \
  "$(sed -n 's/.*--settings \([^ ]*\) .*/\1/p' "$rec/argv" | head -n 1)" >/dev/null \
  || fail "c9l: the mise opt-in alone must leave the broad lefthook denies in place"
[ ! -e "$home/streamjson/sjw9l3/lefthook-edit" ] || fail "c9l: the mise opt-in alone must record no lefthook opt-in"
m_only_rec=$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)
{ grep -qx 'mise_task_edit=1' "$m_only_rec" && ! grep -q '^lefthook_edit=' "$m_only_rec"; } \
  || fail "c9l: the mise opt-in alone must leave lefthook_edit out of the session record: $m_only_rec"
# Only the worker profile opts in, and a repeated flag is a usage error.
for kind in tower mission-control; do
  : >"$rec/argv"
  senv "$home" "$rec" -- \
    launch "sjw9l-$kind" mission-control:3 --prompt-file "$tmp/prompt9" --profile "$kind" --lefthook-edit --foreground >/dev/null 2>&1
  [ $? -eq 2 ] && [ ! -s "$rec/argv" ] || fail "c9l: --lefthook-edit with the $kind profile must be refused (exit 2) before a spawn"
done
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9l4 execution-backends:4 --prompt-file "$tmp/prompt9" --lefthook-edit --lefthook-edit --cwd "$tmp/mwt" --foreground >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -s "$rec/argv" ] || fail "c9l: a repeated --lefthook-edit must be a usage error"
mkdir -p "$tmp/we*ird"
git init -q "$tmp/we*ird"
: >"$rec/argv"
senv "$home" "$rec" -- \
  launch sjw9l5 execution-backends:4 --prompt-file "$tmp/prompt9" --lefthook-edit --cwd "$tmp/we*ird" --foreground >/dev/null 2>&1
l_rc=$?
{ [ "$l_rc" -eq 7 ] && [ ! -s "$rec/argv" ]; } || fail "c9l: an opted-in launch in a glob-character path must be refused (exit 7) before a spawn (exit $l_rc, argv: $(cat "$rec/argv"))"
[ ! -e "$home/streamjson/sjw9l5/lefthook-edit" ] || fail "c9l: a refused opted-in launch must record no opt-in"
# The internal resume seam never takes an opt-in: it would open the profile
# without recording the marker its next recover reads.
for flag in --lefthook-edit --mise-task-edit; do
  : >"$rec/argv"
  senv "$home" "$rec" SHIM_READ_FIRST=0 -- \
    launch sjw9l1 --resume-session "$sid" "$flag" --cwd "$tmp/mwt" --foreground >/dev/null 2>"$tmp/c9l6.err"
  l_rc=$?
  { [ "$l_rc" -eq 2 ] && [ ! -s "$rec/argv" ] && grep -q -- "--resume-session takes no opt-in" "$tmp/c9l6.err"; } \
    || fail "c9l: --resume-session with $flag must be refused (exit 2) before a spawn (exit $l_rc: $(cat "$tmp/c9l6.err"))"
done
# A hook root whose file-tool hook ignores the lefthook argument (a copy from
# before the opt-in judges the mise names only) would leave the lefthook names
# open outside the worktree once the broad denies are gone: the launch refuses.
mkdir -p "$tmp/oldeh"
cp -R "$here/../scripts" "$tmp/oldeh/scripts"
cp -R "$here/../config" "$tmp/oldeh/config"
mv "$tmp/oldeh/scripts/worker-mise-edit-guard.sh" "$tmp/oldeh/scripts/worker-mise-edit-guard.real.sh"
# shellcheck disable=SC2016 # expanded by the stub when it runs
printf '#!/bin/sh\nexec /bin/sh "$(dirname "$0")/worker-mise-edit-guard.real.sh" "$1" mise\n' \
  >"$tmp/oldeh/scripts/worker-mise-edit-guard.sh"
chmod +x "$tmp/oldeh/scripts/worker-mise-edit-guard.sh"
launch_oldeh() {
  : >"$rec/argv"
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_FLEET_SCRATCH_BASE="$tmp/scratch-base" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" SHIM_RECORD_DIR="$rec" SHIM_EVENTS="$ev" "$@" \
    /bin/sh "$tmp/oldeh/scripts/fleet-streamjson.sh" \
    launch sjw9l7 execution-backends:4 --prompt-file "$tmp/prompt9" "$flag" --cwd "$tmp/mwt" --foreground >/dev/null 2>"$tmp/c9l7.err"
}
# The knob that softens the approval proof neither skips nor softens this one.
for mode in refuse warn off; do
  flag=--lefthook-edit
  launch_oldeh PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT="$mode"
  l_rc=$?
  { [ "$l_rc" -eq 9 ] && [ ! -s "$rec/argv" ] && grep -q "does not judge the opted-in names (failed: lefthook)" "$tmp/c9l7.err"; } \
    || fail "c9l: under preflight mode $mode, a hook that ignores the lefthook argument must refuse the launch (exit 9) before a spawn (exit $l_rc: $(cat "$tmp/c9l7.err"))"
  [ ! -e "$home/streamjson/sjw9l7/lefthook-edit" ] || fail "c9l: a launch refused at the preflight must record no opt-in"
done
flag=--mise-task-edit
launch_oldeh
l_rc=$?
[ "$l_rc" -eq 0 ] || fail "c9l: the same hook still judges the mise names, so a mise-only launch passes (exit $l_rc: $(cat "$tmp/c9l7.err"))"
# A hook that refuses every write proves nothing about the names: the plain
# file is the control.
cat >"$tmp/oldeh/scripts/worker-mise-edit-guard.sh" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'
EOF
flag=--lefthook-edit
launch_oldeh
l_rc=$?
{ [ "$l_rc" -eq 9 ] && [ ! -s "$rec/argv" ] && grep -q "failed: the-control-file" "$tmp/c9l7.err"; } \
  || fail "c9l: a hook that refuses a plain file too must refuse the launch (exit 9) before a spawn (exit $l_rc: $(cat "$tmp/c9l7.err"))"
echo "ok: c9l lefthook config opt-in: per-launch profile, recorded for recover, composes with the mise opt-in, refused elsewhere"
# A mission-control recover holds its own row's token, never the caller's,
# and none at all when the row carries none.
mc='mc-beta-tower-0123456789'
mkdir -p "$home/streamjson/$mc" "$home/mission-control/sessions"
printf 'mission-control:3\n' >"$home/streamjson/$mc/scope"
printf 'mission-control\n' >"$home/streamjson/$mc/profile"
printf 'backend\tstream-json\ntoken\trowtoken-own\n' >"$home/mission-control/sessions/$mc"
: >"$rec/env"
senv "$home" "$rec" SHIM_READ_FIRST=0 PLANWRIGHT_MC_TOKEN=callertoken-other -- \
  launch "$mc" --resume-session "$sid" --foreground >/dev/null 2>&1
grep -qx 'mc_token=rowtoken-own' "$rec/env" \
  || fail "c9p: a mission-control recover must hold its own row's token, not the caller's: $(grep '^mc_token=' "$rec/env")"
printf 'backend\tstream-json\n' >"$home/mission-control/sessions/$mc"
: >"$rec/env"
senv "$home" "$rec" SHIM_READ_FIRST=0 PLANWRIGHT_MC_TOKEN=callertoken-other -- \
  launch "$mc" --resume-session "$sid" --foreground >/dev/null 2>&1
grep -qx 'mc_token=<unset>' "$rec/env" \
  || fail "c9p: a mission-control recover whose row has no token must hold none: $(grep '^mc_token=' "$rec/env")"
rm -f "$home/mission-control/sessions/$mc"
: >"$rec/env"
senv "$home" "$rec" SHIM_READ_FIRST=0 PLANWRIGHT_MC_TOKEN=callertoken-other -- \
  launch "$mc" --resume-session "$sid" --foreground >/dev/null 2>&1
grep -qx 'mc_token=<unset>' "$rec/env" \
  || fail "c9p: a mission-control recover with no registry row must hold no token: $(grep '^mc_token=' "$rec/env")"
# The preflight proves the worker guard, so only a worker launch needs it.
mkdir -p "$tmp/nowg"
cp -R "$here/../scripts" "$tmp/nowg/scripts"
cp -R "$here/../config" "$tmp/nowg/config"
rm -f "$tmp/nowg/scripts/worker-command-guard.sh"
for kind in worker tower; do
  : >"$rec/argv"
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$rec" SHIM_EVENTS="$ev" /bin/sh "$tmp/nowg/scripts/fleet-streamjson.sh" \
    launch "sjw9g-$kind" mission-control:3 --prompt-file "$tmp/prompt9" --profile "$kind" --foreground >/dev/null 2>&1
  pf_rc=$?
  case $kind in
    worker) [ "$pf_rc" -eq 9 ] || fail "c9p: a worker launch with no worker guard must fail its preflight (exit 9), got $pf_rc" ;;
    tower) [ "$pf_rc" -eq 0 ] || fail "c9p: a tower launch must not run the worker-guard preflight, got $pf_rc" ;;
  esac
done
echo "ok: c9p --profile pins a shipped fragment by kind and a recover keeps it (mission-control REQ-G1.1)"

# ---------------------------------------------------------------------------
# c39 (custom-spec-location REQ-E1.7): the spec-root hand-off. A worker whose
#     work repository keeps its spec root outside it (here a plain store) gets
#     that root as PLANWRIGHT_WORKER_SPEC_ROOT; a worker whose root is in its
#     own repository gets none, and an inherited value never stands. Every
#     inherited PLANWRIGHT_* variable is dropped, git's discovery and config
#     are pinned and HOME is left unset (senv strips it), since a host overlay
#     or config would hand the resolver a root of its own.
# ---------------------------------------------------------------------------
launch_c39() {
  (
    for _v in $(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/\1/p'); do
      unset "$_v"
    done
    export PLANWRIGHT_WORKER_SPEC_ROOT=/stale PLANWRIGHT_WORKER_SESSION_RECORD=/stale \
      GIT_CEILING_DIRECTORIES="$tmp" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    # The second worker gets the default base, what a worker really gets;
    # its final stop below removes its root. The first keeps the suite's.
    c39_base=$tmp/scratch-base
    [ "$1" != sjw39b ] || c39_base=''
    senv "$tmp/h39" "$tmp/r39" SHIM_EVENTS="$tmp/ev9" PLANWRIGHT_FLEET_SCRATCH_BASE="$c39_base" -- \
      launch "$1" execution-backends:4 --prompt-file "$tmp/prompt9" --cwd "$tmp/wt39" --foreground
  )
}
mkdir -p "$tmp/r39" "$tmp/store39" "$tmp/wt39/.claude"
git -c init.defaultBranch=main init -q "$tmp/wt39" || fail "c39: cannot create the work repository"
printf 'project: fixture\nlayout: 1\n' >"$tmp/store39/planwright-spec-root.yml"
printf 'spec_root: %s\n' "$tmp/store39" >"$tmp/wt39/.claude/planwright.local.yml"
launch_c39 sjw39 >/dev/null || fail "c39: launch exited non-zero"
store39=$(cd "$tmp/store39" && pwd -P)
got39=$(grep '^spec_root=' "$tmp/r39/env" | tail -n 1)
[ "${got39#spec_root=}" = "$store39" ] \
  || fail "c39: the worker got '${got39#spec_root=}' as PLANWRIGHT_WORKER_SPEC_ROOT, expected the store"
rm -f "$tmp/wt39/.claude/planwright.local.yml"
launch_c39 sjw39b >/dev/null || fail "c39: second launch exited non-zero"
got39=$(grep '^spec_root=' "$tmp/r39/env" | tail -n 1)
[ "${got39#spec_root=}" = "<unset>" ] \
  || fail "c39: an inherited PLANWRIGHT_WORKER_SPEC_ROOT reached a same-repo worker: '${got39#spec_root=}'"
echo "ok: c39 the worker gets the outside spec root, and an inherited one never stands (REQ-E1.7)"
# The session record its command guard reads (worker-permission-ergonomics
# REQ-G1.8): written for the worker's own directory, under the fleet home,
# and an inherited path never stands.
rec39=$(grep '^record=' "$tmp/r39/env" | tail -n 1)
rec39=${rec39#record=}
case $rec39 in
  "$(cd "$tmp/h39" 2>/dev/null && pwd -P)"/session-records/*.record) ;;
  *) fail "c39: the worker got '$rec39' as PLANWRIGHT_WORKER_SESSION_RECORD, expected a record under its fleet home" ;;
esac
grep -qx "worktree_root=$(cd "$tmp/wt39" && pwd -P)" "$rec39" 2>/dev/null \
  || fail "c39: the worker's session record does not name its worktree"
grep -qx "launch_backend=stream-json" "$rec39" 2>/dev/null \
  || fail "c39: the worker's session record does not name the stream-json backend"
echo "ok: c39 the worker gets a fresh session record, never an inherited one (REQ-G1.8)"
# The worker's scratch root (worker-permission-ergonomics REQ-G1.2): its
# TMPDIR, and only the worker's, is its own root, which its session record
# names; a recover keeps it, contents and all, and so does a stop, which a
# recover may follow. It is short and outside any .claude directory: Linux
# caps a Unix socket path at 108 bytes, and a path under ~/.claude reads as a
# settings path to the guards a worker's tests exercise.
tmp39=$(grep '^tmpdir=' "$tmp/r39/env" | tail -n 1)
root39=${tmp39#tmpdir=}
if [ ! -d "$root39" ] || ! grep -qx "scratch_root=$root39" "$rec39" 2>/dev/null; then
  fail "c39: the worker's TMPDIR '$root39' is not the scratch root its session record names"
fi
[ "${#root39}" -lt 60 ] || fail "c39: the worker's TMPDIR is ${#root39} characters long: $root39"
case $root39/ in
  */.claude/* | "$(cd "$tmp/h39" 2>/dev/null && pwd -P)"/*) fail "c39: the worker's TMPDIR lies under .claude or the fleet home: $root39" ;;
esac
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.close()' \
    "$root39/rpc.sock" 2>/dev/null \
    || fail "c39: a Unix socket cannot be bound in the worker's TMPDIR $root39"
  rm -f "$root39/rpc.sock"
else
  echo "skip: c39 the socket bind needs python3"
fi
: >"$root39/kept"
recover39() {
  (
    for _v in $(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/\1/p'); do
      unset "$_v"
    done
    cd "$tmp/wt39" && senv "$tmp/h39" "$tmp/r39" GIT_CEILING_DIRECTORIES="$tmp" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 SHIM_EVENTS="$tmp/ev9" SHIM_READ_FIRST=0 -- \
      recover sjw39b --foreground
  ) >/dev/null 2>&1
}
n39=$(grep -c '^tmpdir=' "$tmp/r39/env")
recover39 || fail "c39: the recover exited non-zero"
tmp39=$(grep '^tmpdir=' "$tmp/r39/env" | tail -n 1)
[ "$(grep -c '^tmpdir=' "$tmp/r39/env")" -gt "$n39" ] && [ "${tmp39#tmpdir=}" = "$root39" ] \
  && [ -f "$root39/kept" ] \
  || fail "c39: the recovered worker's TMPDIR was '${tmp39#tmpdir=}', or it never ran, or the root lost its contents"
senv "$tmp/h39" "$tmp/r39" -- stop sjw39b --grace 2 >/dev/null 2>&1 || fail "c39: the stop exited non-zero"
[ -f "$root39/kept" ] || fail "c39: the stop removed the scratch root a recover may still need"
n39=$(grep -c '^tmpdir=' "$tmp/r39/env")
recover39 || fail "c39: the recover after the stop exited non-zero"
[ "$(grep -c '^tmpdir=' "$tmp/r39/env")" -gt "$n39" ] && [ -f "$root39/kept" ] \
  || fail "c39: the recover after a stop did not find the same root"
senv "$tmp/h39" "$tmp/r39" -- stop sjw39b --grace 2 --final >/dev/null 2>&1 || fail "c39: the final stop exited non-zero"
[ ! -e "$root39" ] && [ ! -e "$tmp/h39/streamjson/sjw39b/scratch-root" ] \
  || fail "c39: the final stop left the scratch root or its pointer behind"
! grep -rqxF "$root39" "$tmp/h39/scratch" 2>/dev/null \
  || fail "c39: the final stop left the fleet home's record of the scratch root"
echo "ok: c39 the worker's TMPDIR is its own short scratch root outside .claude, kept across a recover and a stop, removed by the final stop (REQ-G1.2)"
# The final close removes only a root the fleet home records, or one of the
# earlier layout's shapes, <fleet-home>/scratch/<hash> or <hash>/<hash>, and
# never through a symlink; a read-only directory the worker left does not stop
# the removal.
h39r=$(cd "$tmp/h39" && pwd -P)
mkdir -p "$tmp/u39" "$tmp/out39/keep" "$h39r/scratch/$(printf 'a%.0s' $(seq 40))/ro/deep"
chmod 500 "$h39r/scratch/$(printf 'a%.0s' $(seq 40))/ro"
ro39a=0
if hermetic_access_denied w "$h39r/scratch/$(printf 'a%.0s' $(seq 40))/ro"; then ro39a=1; fi
ln -s "$tmp/out39" "$h39r/scratch/$(printf 'b%.0s' $(seq 40))"
release39() {
  printf '%s\n' "$1" >"$tmp/u39/scratch-root"
  (
    script_dir=$here/../scripts
    # shellcheck source=scripts/fleet-stop-lib.sh
    . "$here/../scripts/fleet-stop-lib.sh"
    stop_scratch_root_release "$tmp/u39" "$tmp/h39"
  )
}
mkdir -m 700 "$tmp/base39"
base39=$(cd "$tmp/base39" && pwd -P)
make39() {
  PLANWRIGHT_FLEET_SCRATCH_BASE=$base39 /bin/sh "$here/../scripts/fleet-scratch.sh" make "$tmp/h39" "$1"
}
new39=$(make39 "$(printf 'a%.0s' $(seq 40))") || fail "c39: no recorded root to release"
mkdir -p "$new39/ro/deep" "$base39/0123456789abcdef/keep"
chmod 500 "$new39/ro"
ro39b=0
if hermetic_access_denied w "$new39/ro"; then ro39b=1; fi
! release39 "$base39/0123456789abcdef" && [ -d "$base39/0123456789abcdef/keep" ] \
  || fail "c39: the final close removed a root the fleet home does not record"
if [ "$ro39b" -eq 0 ]; then
  echo "skip: c39: the running user still writes $new39/ro under mode 500, so no read-only directory is held"
elif ! release39 "$new39" || [ -e "$new39" ] || [ -e "$tmp/u39/scratch-root" ] \
  || grep -rqxF "$new39" "$h39r/scratch"; then
  fail "c39: the final close did not remove a recorded root holding a read-only directory, and its record"
fi
for bad39 in "$tmp/out39" "$h39r/scratch/../../out39" "$h39r/scratch/$(printf 'g%.0s' $(seq 40))" \
  "$h39r/scratch/$(printf 'a%.0s' $(seq 39))" "$h39r/scratch/$(printf 'a%.0s' $(seq 40))/ro"; do
  ! release39 "$bad39" && [ -f "$tmp/u39/scratch-root" ] \
    || fail "c39: the final close accepted the pointer '$bad39'"
done
[ -d "$tmp/out39/keep" ] && [ -d "$h39r/scratch/$(printf 'a%.0s' $(seq 40))/ro/deep" ] \
  || fail "c39: a refused pointer removed something"
release39 "$h39r/scratch/$(printf 'b%.0s' $(seq 40))" >/dev/null 2>&1
[ -d "$tmp/out39/keep" ] || fail "c39: the final close followed a symlinked root out of the fleet home"
if [ "$ro39a" -eq 0 ]; then
  echo "skip: c39: the running user still writes the scratch root's ro directory under mode 500, so no read-only directory is held"
else
  release39 "$h39r/scratch/$(printf 'a%.0s' $(seq 40))" && [ ! -e "$h39r/scratch/$(printf 'a%.0s' $(seq 40))" ] \
    && [ ! -e "$tmp/u39/scratch-root" ] \
    || fail "c39: the final close did not remove a root holding a read-only directory"
fi
sess39="$h39r/scratch/$(printf 'c%.0s' $(seq 40))"
mkdir -p "$sess39/$(printf 'd%.0s' $(seq 40))/f" "$sess39/$(printf 'e%.0s' $(seq 40))/f"
release39 "$sess39/$(printf 'd%.0s' $(seq 40))" && [ ! -e "$sess39/$(printf 'd%.0s' $(seq 40))" ] \
  && [ -d "$sess39/$(printf 'e%.0s' $(seq 40))/f" ] \
  || fail "c39: a session's final close must remove its own root and leave its sibling's"
for bad39 in "$sess39/" "$sess39/$(printf 'e%.0s' $(seq 40))/f"; do
  ! release39 "$bad39" || fail "c39: the final close accepted the pointer '$bad39'"
done
[ -d "$sess39/$(printf 'e%.0s' $(seq 40))/f" ] || fail "c39: a refused session pointer removed something"
echo "ok: c39 the final close removes only a scratch root of the writer's shape, through no symlink (REQ-G1.2)"

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

assert_nothing_left_running

echo "all fleet-streamjson tests passed"
