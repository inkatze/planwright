#!/bin/bash
# Tests for scripts/fleet-streamjson.sh: how prompts, frames and answers reach
# the worker, how a worker's end is reported, and how the journal and recover
# locks break (REQ-A1.9, REQ-E1.4, REQ-E1.5).
#   - a prompt larger than the pipe buffer, and one with UTF-8 content, reach
#     the worker intact; a non-zero exit with no result event reads as ended,
#     and a detached launch confirms startup and surfaces a failed supervisor.
#   - a request re-surfacing in a terminal journal state is re-opened, and a
#     re-open that fails fails closed.
#   - a `--deny` always carries a non-empty message free of control characters,
#     and a response-file deny is held to the same check.
#   - obs:81ba2dce: the journal lock and the `recover.lock` break on their
#     holder's absence, never on age, and a legacy lock directory is cleared in
#     place only once its holder is gone.
#
# Companions: tests/test-fleet-streamjson.sh and
# tests/test-fleet-streamjson-status.sh.
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-streamjson-fixture.sh
. "$here/lib/fleet-streamjson-fixture.sh" || exit 1

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
if poll_until --what 'the processes gone' -- sh -c "! kill -0 $big_pid 2>/dev/null"; then
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
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir12/journal" \
  || fail "c12: the pending journal row never appeared"
senv "$home" "$rec" -- answer sjw12 "$req_perm" --allow >/dev/null \
  || fail "c12: answer exited non-zero"
wait "$launch12" || fail "c12: the worker run did not end cleanly"
grep -q "^$req_perm$tab.*${tab}answered" "$wdir12/journal" \
  || fail "c12: the request should be answered after the first run"
# Reported, not just asserted. This invariant is a projection of journal state
# written by two processes, so when it breaks the question is always "what did
# the store say, and when relative to the journal" -- and a bare boolean sends
# the next reader digging for it. The timestamps are the diagnosis: a store row
# stamped at or after the journal's answered row is a write that outlived the
# answer it contradicts.
q12_count="$(aenv "$home" queue --count 2>"$tmp/q12.err")"
if [ "$q12_count" != 0 ]; then
  # Grouped, because `2>&1` on the command catches tr's stderr but not the
  # SHELL's: a missing state file fails at the redirection, before tr runs, so
  # the error goes to the test's own stderr and the captured string is empty --
  # a diagnostic that reports nothing exactly when the file it wanted is the
  # thing that is wrong.
  q12_err="$({ tr '\n' ' ' <"$tmp/q12.err"; } 2>&1)"
  q12_store="$({ tr '\n' '~' <"$home/attention/state"; } 2>&1)"
  q12_journal="$({ tr '\n' '~' <"$wdir12/journal"; } 2>&1)"
  fail "c12: queue should be clear after the answer, got '$q12_count' (stderr: ${q12_err}; store: ${q12_store}; journal: ${q12_journal})"
fi
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
#     The poll helper's default deadline is shrunk to 1s and the worker
#     emits its result 3s late, as a loaded host makes it. The wait for the
#     result lasts while the supervisor lives, so the default never bounds it.
# ---------------------------------------------------------------------------
home="$tmp/h15"
rec="$tmp/r15"
mkdir -p "$rec"
ev="$tmp/ev15"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
printf 'detach me\n' >"$tmp/prompt15"
POLL_UNTIL_DEFAULT_DEADLINE=1
out=$(senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_DELAY=3 -- \
  launch sjw15 execution-backends:4 --prompt-file "$tmp/prompt15") \
  || fail "c15: detached launch exited non-zero"
case $out in
  "launched sjw15 dir "*) : ;;
  *) fail "c15: detached launch should report launched, got: $out" ;;
esac
# `launched` was printed only after supervisor.pid appeared. The supervisor
# records this worker's result event before it removes supervisor.pid, so a
# host slow enough to find the file gone already holds the result.
wdir15="$home/streamjson/sjw15"
sup15=$(cat "$wdir15/supervisor.pid" 2>/dev/null) || sup15=''
if [ -n "$sup15" ]; then
  poll_until --deadline "$supervisor_deadline" --while-alive "$sup15" \
    --what 'the detached supervisor to record its result' -- test -f "$wdir15/result" \
    || fail "c15: the detached supervisor never ran to a result (gave up after ${POLL_UNTIL_ELAPSED}s)"
else
  test -f "$wdir15/result" || fail "c15: the detached supervisor removed supervisor.pid without a result"
fi
POLL_UNTIL_DEFAULT_DEADLINE=$supervisor_deadline
# The detached launch drops the tower identity too, and under bash (macOS
# /bin/sh) still returns while the session runs: no process it leaves behind
# holds the caller's output open.
rec15t="$tmp/r15t"
mkdir -p "$rec15t"
t15=$(date +%s)
out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$tmp/h15t" PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
  SHIM_RECORD_DIR="$rec15t" SHIM_EVENTS="$ev" SHIM_SLEEP=15 PLANWRIGHT_TOWER_ID=stale-tower \
  bash "$SJ" launch sjw15t execution-backends:4 --prompt-file "$tmp/prompt15" 2>&1) \
  || fail "c15: a detached launch under bash exited non-zero: $out"
[ $(($(date +%s) - t15)) -lt 12 ] || fail "c15: a detached launch under bash held the caller until the session ended"
poll_until --what 'the worker environment' -- grep -q '^tower=' "$rec15t/env" \
  || fail "c15: the detached worker never recorded its environment"
grep -qx 'tower=<unset>/<unset>/<unset>/<unset>' "$rec15t/env" \
  || fail "c15: the dispatcher's tower identity reached the detached worker: $(grep '^tower=' "$rec15t/env")"
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
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir16/journal" \
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
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir17/journal" \
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
# c17b: a deny always carries a non-empty message. The API rejects an error
#     tool_result with empty content (400), which kills the worker. A bare
#     --deny, an empty --message, and a whitespace-only or control-only
#     --message each deliver a default; a given message is delivered unchanged.
# ---------------------------------------------------------------------------
for c17b in bare empty blank ctrl long given; do
  home="$tmp/h17b$c17b"
  rec="$tmp/r17b$c17b"
  mkdir -p "$rec"
  ev="$tmp/ev17b$c17b"
  printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
  printf 'deny me\n' >"$tmp/prompt17b$c17b"
  w17b="sjw17b$c17b"
  senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
    launch "$w17b" execution-backends:4 --prompt-file "$tmp/prompt17b$c17b" --foreground &
  launch17b=$!
  poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$home/streamjson/$w17b/journal" \
    || fail "c17b-$c17b: the pending journal row never appeared"
  case $c17b in
    bare) senv "$home" "$rec" -- answer "$w17b" "$req_perm" --deny >/dev/null ;;
    empty) senv "$home" "$rec" -- answer "$w17b" "$req_perm" --deny --message '' >/dev/null ;;
    blank) senv "$home" "$rec" -- answer "$w17b" "$req_perm" --deny --message "$(printf '  \t \n ')" >/dev/null ;;
    ctrl) senv "$home" "$rec" -- answer "$w17b" "$req_perm" --deny --message "$(printf '\001\002')" >/dev/null ;;
    long) senv "$home" "$rec" -- answer "$w17b" "$req_perm" --deny --message "$(printf '%700s' '')x" >/dev/null ;;
    given) senv "$home" "$rec" -- answer "$w17b" "$req_perm" --deny --message 'use the other path' >/dev/null ;;
  esac || fail "c17b-$c17b: deny answer exited non-zero"
  wait "$launch17b" || fail "c17b-$c17b: the worker run did not end cleanly"
  grep control_response "$rec/stdin" | head -1 >"$tmp/c17b$c17b.line"
  grep -q '"behavior":"deny"' "$tmp/c17b$c17b.line" || fail "c17b-$c17b: no deny delivered"
  if [ "$c17b" = given ]; then
    grep -qF '"message":"use the other path"' "$tmp/c17b$c17b.line" \
      || fail "c17b-$c17b: a given message must be delivered unchanged"
  else
    grep -qF '"message":"Denied by the supervisor; no reason given."' "$tmp/c17b$c17b.line" \
      || fail "c17b-$c17b: expected the default deny message, got: $(cat "$tmp/c17b$c17b.line")"
  fi
done
echo "ok: c17b a deny always carries a non-empty message"

# c17c: a --response-file deny body with an empty or missing message, or one
#     whose message escapes decode only to whitespace or control bytes, is
#     refused (exit 2, nothing written, request stays pending); one with a
#     message is delivered.
home="$tmp/h17c"
rec="$tmp/r17c"
mkdir -p "$rec"
ev="$tmp/ev17c"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'deny me\n' >"$tmp/prompt17c"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw17c execution-backends:4 --prompt-file "$tmp/prompt17c" --foreground &
launch17c=$!
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$home/streamjson/sjw17c/journal" \
  || fail "c17c: the pending journal row never appeared"
for body17c in '{"behavior":"deny"}' '{"behavior":"deny","message":""}' '{"behavior":"deny","message":"   "}' '{ "behavior" : "deny" , "message" : "\n" }' '{"message":"","behavior":"deny"}' '{"behavior":"deny","message":null}'; do
  printf '%s\n' "$body17c" >"$tmp/c17c.resp"
  senv "$home" "$rec" -- answer sjw17c "$req_perm" --response-file "$tmp/c17c.resp" >/dev/null 2>"$tmp/c17c.err"
  [ $? -eq 2 ] || fail "c17c: a deny body without a message must be refused: $body17c"
  grep -q 'deny body needs a non-empty message' "$tmp/c17c.err" \
    || fail "c17c: the refusal must be the deny-message check, got: $(cat "$tmp/c17c.err")"
done
# %b turns each \\ into the single backslash of a JSON escape.
for esc17c in '{"behavior":"deny","message":"\\u0020"}' '{"behavior":"deny","message":"\\t\\r"}' '{"behavior":"deny","message":" \\f\\b\\u0001\\u007f"}' '{"behavior":"deny","message":"\\u001F\\u007F\\u000A"}'; do
  printf '%b\n' "$esc17c" >"$tmp/c17c.resp"
  senv "$home" "$rec" -- answer sjw17c "$req_perm" --response-file "$tmp/c17c.resp" >/dev/null 2>"$tmp/c17c.err"
  [ $? -eq 2 ] || fail "c17c: a deny message of blank escapes must be refused: $(cat "$tmp/c17c.resp")"
  grep -q 'deny body needs a non-empty message' "$tmp/c17c.err" \
    || fail "c17c: the refusal must be the deny-message check, got: $(cat "$tmp/c17c.err")"
done
[ ! -s "$rec/stdin" ] || ! grep -q control_response "$rec/stdin" \
  || fail "c17c: a refused deny body must write nothing to the worker"
grep -q "^$req_perm$tab.*${tab}pending" "$home/streamjson/sjw17c/journal" \
  || fail "c17c: a refused deny body must leave the request pending"
printf '%s\n' '{"behavior":"deny","message":"\"quoted\" reason"}' >"$tmp/c17c.resp"
senv "$home" "$rec" -- answer sjw17c "$req_perm" --response-file "$tmp/c17c.resp" >/dev/null \
  || fail "c17c: a deny body whose message starts with an escape must be delivered"
wait "$launch17c" || fail "c17c: the worker run did not end cleanly"
grep control_response "$rec/stdin" | head -1 | grep -qF "\"response\":$(cat "$tmp/c17c.resp")}}" \
  || fail "c17c: the delivered deny must reach the worker unchanged, got: $(grep control_response "$rec/stdin")"
echo "ok: c17c a response-file deny without a message is refused"

# c17d: the deny-message check refuses nothing it should deliver: a non-deny
#     body with no message, a plain-text deny, a deny whose message opens with
#     a blank escape before a \u escape of real content, and denies whose
#     first real content is a \u escape just past a blank range (one of them
#     after an upper-case blank escape), each reach the worker as sent.
for c17d in allow plain uesc lowu upperu; do
  home="$tmp/h17d$c17d"
  rec="$tmp/r17d$c17d"
  mkdir -p "$rec"
  ev="$tmp/ev17d$c17d"
  printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
  printf 'answer me\n' >"$tmp/prompt17d$c17d"
  case $c17d in
    allow) printf '%s\n' '{"behavior":"allow","updatedInput":{"file_path":"/x/y.txt"}}' >"$tmp/c17d$c17d.resp" ;;
    plain) printf '%s\n' '{"behavior":"deny","message":"no"}' >"$tmp/c17d$c17d.resp" ;;
    uesc) printf '%b\n' '{"behavior":"deny","message":"\\n\\u00e9"}' >"$tmp/c17d$c17d.resp" ;;
    lowu) printf '%b\n' '{"behavior":"deny","message":"\\u0021"}' >"$tmp/c17d$c17d.resp" ;;
    upperu) printf '%b\n' '{"behavior":"deny","message":"\\u007F\\u007E"}' >"$tmp/c17d$c17d.resp" ;;
  esac
  senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
    launch "sjw17d$c17d" execution-backends:4 --prompt-file "$tmp/prompt17d$c17d" --foreground &
  launch17d=$!
  poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$home/streamjson/sjw17d$c17d/journal" \
    || fail "c17d-$c17d: the pending journal row never appeared"
  senv "$home" "$rec" -- answer "sjw17d$c17d" "$req_perm" --response-file "$tmp/c17d$c17d.resp" >/dev/null \
    || fail "c17d-$c17d: the body must be delivered: $(cat "$tmp/c17d$c17d.resp")"
  wait "$launch17d" || fail "c17d-$c17d: the worker run did not end cleanly"
  grep control_response "$rec/stdin" | head -1 | grep -qF "\"response\":$(cat "$tmp/c17d$c17d.resp")}}" \
    || fail "c17d-$c17d: the body must reach the worker unchanged, got: $(grep control_response "$rec/stdin")"
done
echo "ok: c17d a response-file body the deny check should pass is delivered unchanged"

# c17e: every shape of real content opening a deny message passes the check.
#     The check runs before the worker lookup, so against a worker that does
#     not exist a passing body is refused as an unknown worker and a failing
#     one by the deny-message check, with no launch needed.
home="$tmp/h17e"
mkdir -p "$home" "$tmp/r17e"
for body17e in '{"behavior":"deny","message":"  no"}' '{"behavior":"deny","message":"\\u4e2d"}' '{"behavior":"deny","message":"\\u0100"}' '{"behavior":"deny","message":"\\u0041"}' '{"behavior":"deny","message":"\\u0080"}' '{"behavior":"deny","message":"\\u0000x"}' '{"behavior":"deny","message":"\\\\"}' '{"behavior":"deny","message":"\\/"}' '{"behavior":"deny","message":"\303\251"}'; do
  printf '%b\n' "$body17e" >"$tmp/c17e.resp"
  senv "$home" "$tmp/r17e" -- answer sjw17enone "$req_perm" --response-file "$tmp/c17e.resp" >/dev/null 2>"$tmp/c17e.err"
  grep -q 'unknown worker' "$tmp/c17e.err" \
    || fail "c17e: a deny message opening with real content must pass the check: $(cat "$tmp/c17e.resp"), got: $(cat "$tmp/c17e.err")"
done
echo "ok: c17e every opening of real content passes the response-file deny check"

# ---------------------------------------------------------------------------
# c18 (REQ-E1.5): the journal lock's break is decided by the holder's PROCESS
#     and never by the lock's age. Both directions are asserted, because only
#     the pair pins the rule: an implementation that broke every lock passes the
#     absent-holder legs alone, and one that broke none passes the live ones.
#
#     The lock is driven through `answer`, whose only pre-lock work is the
#     worker-dir check: a broken lock lets it reach the not-journaled refusal
#     (exit 3), a lock it must not break reports busy (exit 2). Those two
#     outcomes are what the liveness probe decides between.
# ---------------------------------------------------------------------------
home="$tmp/h18"
rec="$tmp/r18"
mkdir -p "$rec"
unknown_req='cccc2222-dddd-eeee-ffff-000011112222'

# lock_leg <name> <owner-pid> <back-date|-> <want-rc> — plant a worker dir
# holding a locked journal, run one `answer` against it, and assert the outcome
# the break decision produces.
lock_leg() {
  ll_name=$1
  ll_owner=$2
  ll_stamp=$3
  ll_want=$4
  ll_dir="$home/streamjson/$ll_name"
  mkdir -p "$ll_dir" || fail "c18/$ll_name: cannot plant the worker dir"
  plant_lock "$ll_dir/journal.lock" "$ll_owner"
  # `-h`: the stamp belongs on the LINK. Without it `touch` follows the link to
  # a target that is a token rather than a file, and the leg silently ages
  # nothing.
  [ "$ll_stamp" = '-' ] || touch -h -t "$ll_stamp" "$ll_dir/journal.lock" \
    || fail "c18/$ll_name: cannot back-date the lock"
  senv "$home" "$rec" -- answer "$ll_name" "$unknown_req" --allow >/dev/null 2>&1
  ll_rc=$?
  [ "$ll_rc" = "$ll_want" ] \
    || fail "c18/$ll_name: expected rc=$ll_want from the break decision, got rc=$ll_rc"
}

# (a) a lock whose holder's process is gone: broken at once, and `answer`
#     reaches the not-journaled refusal. Nothing waits for a threshold.
lock_leg sjw18a "$dead_pid" - 3
# (b) the same lock held by a live process: refused, the lock untouched.
lock_leg sjw18b $$ - 2
# (c) an ANCIENT lock whose holder is still running, still refused. This is the
#     load-bearing leg: under the age rule this replaces, a lock this old was
#     broken on sight and its live holder found itself sharing the critical
#     section with the breaker.
lock_leg sjw18c $$ 200001010000 2
# Asserted here rather than after the last leg, because `planted_token` names
# the most recent plant. Refusing is not the same as refusing and then meddling.
[ "$(readlink "$home/streamjson/sjw18c/journal.lock")" = "$planted_token" ] \
  || fail "c18/sjw18c: a refused break must leave the holder's own lock in place"
# (d) an ancient lock whose holder is gone is broken like any other, so age has
#     not come back as a quiet second condition on the break.
lock_leg sjw18d "$dead_pid" 200001010000 3
echo "ok: c18 the journal lock breaks on the holder's absence, never on age (REQ-E1.5)"

# ---------------------------------------------------------------------------
# c24 (obs:81ba2dce): a `recover.lock` left behind by a killed recovery is
#    broken on its holder's absence, so one SIGKILL cannot wedge the verb
#    permanently; a lock whose holder is still running refuses however old it
#    is, and a lock left as a DIRECTORY by the retired `mkdir` shape is cleared
#    in place rather than wedging the verb for good.
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
# (a) a lock whose holder is live is a recovery in flight: refused, never
#     broken, and back-dated to the century mark to say so. The age rule this
#     replaces broke a lock like this one on sight, taking the critical section
#     out from under a recovery that was running perfectly well.
plant_lock "$wdir24/recover.lock" $$
touch -h -t 200001010000 "$wdir24/recover.lock" || fail "c24: cannot back-date the lock"
live_token=$planted_token
senv "$home" "$rec" SHIM_EVENTS="$ev24" SHIM_READ_FIRST=0 -- \
  recover sjw24 --foreground >/dev/null 2>&1
[ $? -eq 3 ] || fail "c24a: a recovery whose initiator is live must refuse (exit 3)"
[ -L "$wdir24/recover.lock" ] \
  || fail "c24a: an ancient lock whose holder still runs must not be broken"
[ "$(readlink "$wdir24/recover.lock")" = "$live_token" ] \
  || fail "c24a: the live holder's lock must not have been replaced"
# (b) the same lock with its holder's process gone is broken and recovery
#     proceeds, with no threshold to wait out first.
plant_lock "$wdir24/recover.lock" "$dead_pid"
: >"$rec/argv"
senv "$home" "$rec" SHIM_EVENTS="$ev24" SHIM_READ_FIRST=0 -- \
  recover sjw24 --foreground >/dev/null 2>&1 \
  || fail "c24b: a lock whose holder is gone must be broken and recovery succeed"
grep -q -- "--resume $sid" "$rec/argv" \
  || fail "c24b: the relaunch after the break must resume the persisted session"
{ [ ! -L "$wdir24/recover.lock" ] && [ ! -e "$wdir24/recover.lock" ]; } \
  || fail "c24b: the lock must be released after recovery"
# (c) a lock left as a DIRECTORY by the retired `mkdir` shape. No acquire goes
#     over one, so without an in-place clear a fleet home carrying it could
#     never recover this worker again. `recover` is where that clear lives.
mkdir -p "$wdir24/recover.lock" || fail "c24: cannot plant the legacy lock directory"
printf '%s\n' 999999999 >"$wdir24/recover.lock/holder"
: >"$rec/argv"
senv "$home" "$rec" SHIM_EVENTS="$ev24" SHIM_READ_FIRST=0 -- \
  recover sjw24 --foreground >/dev/null 2>&1 \
  || fail "c24c: a lock left as a directory must be cleared, not wedge the verb"
grep -q -- "--resume $sid" "$rec/argv" \
  || fail "c24c: the relaunch after the in-place clear must resume the session"
# (d) the in-place clear is for a directory whose recorded holder is gone. One
#     whose holder still runs, or that never recorded one, may belong to a
#     recovery from before the upgrade that is still going: refused as
#     contention and left standing, never removed from under it.
for c24_holder in $$ ''; do
  mkdir -p "$wdir24/recover.lock" || fail "c24d: cannot plant the legacy lock directory"
  rm -f "$wdir24/recover.lock/holder"
  [ -z "$c24_holder" ] || printf '%s\n' "$c24_holder" >"$wdir24/recover.lock/holder"
  rc24=0
  senv "$home" "$rec" SHIM_EVENTS="$ev24" SHIM_READ_FIRST=0 -- \
    recover sjw24 --foreground >/dev/null 2>"$tmp/err24" || rc24=$?
  [ "$rc24" -eq 3 ] \
    || fail "c24d: a legacy lock directory whose holder may still run (holder '${c24_holder}') must refuse with 3, got $rc24: $(cat "$tmp/err24")"
  [ -d "$wdir24/recover.lock" ] \
    || fail "c24d: a legacy lock directory whose holder may still run (holder '${c24_holder}') was removed"
  rm -rf "$wdir24/recover.lock"
done
echo "ok: c24 a recover.lock breaks on its holder's absence, and a legacy lock directory is cleared in place only once its holder is gone (obs:81ba2dce)"

assert_nothing_left_running

echo "all fleet-streamjson delivery tests passed"
