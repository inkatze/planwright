#!/bin/bash
# Tests for knowing whether a steer reached the stream-json worker it was
# written to (scripts/fleet-streamjson.sh `steer`, the supervisor's capture and
# the escalation tick). The CLI reads a user frame that lands mid-turn at the
# worker's next tool boundary, or after the turn ends, and writes nothing to
# stdout for it unless the session runs with --replay-user-messages; without
# that, a steer the session never read left no trace, and `steered` was the
# only record there was.
#
#   a1: every launch passes --replay-user-messages, so a frame the session reads
#       comes back on its stdout.
#   a2: a steer frame carries its own uuid, the receipt row records it, and the
#       session's replay of that uuid is recorded as the steer's
#       acknowledgement; an acknowledged steer is never reported.
#   a3: a steer the session never replays, on a worker whose turn then ended,
#       is reported past the grace: a high-priority attention item naming the
#       worker and the message file, raised once however many ticks see it.
#   a4: a steer replayed after the turn's result, within the grace (the
#       message read as the next turn), is not reported.
#   a5: a steer written while the worker is mid-turn says on stderr that it is
#       queued and when the session will read it; one written to an idle
#       worker says nothing.
#   a6: steers to a worker whose runtime predates the acknowledgement record
#       are never judged.
#   a7: `alarm-scan` reports an unread steer of a worker that has since died,
#       which no tick of its own can.
#   a8: no supervisor, tick or shim from this run outlives the suite.
#
# Hermetic: the fleet home and the CLI seam are case-local, the CLI is a shim
# that records its argv and stdin and replays what it is told to. Runs
# standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"
POLL_UNTIL_DEFAULT_DEADLINE=${POLL_UNTIL_DEFAULT_DEADLINE:-300}
# shellcheck source=tests/lib/fixture-procs.sh
. "$here/lib/fixture-procs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required: the launch preflight runs the auto-approve hook"

tmp=$(fixture_scratch) || fail "no scratch directory to run in"
tab=$(printf '\t')
live_pids=''
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  for cl_p in $live_pids; do
    kill "$cl_p" 2>/dev/null || :
  done
  fixture_reap "$tmp/"
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The shim worker. Every stdin line is recorded. A user frame is answered the
# way SHIM_STEER_MODE says (the first one, the launch prompt, by SHIM_FIRST):
#   ack   replay it, when the argv asked for replays, then end the turn
#   drop  end the turn without replaying it (the frame the session never read)
#   late  end the turn, then replay it a second later (read as the next turn)
#   hold  replay it and leave the turn running
# A replay carries the frame's own top-level uuid, as the CLI's does.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >"$SHIM_RECORD_DIR/argv"
replay=0
for a in "$@"; do
  [ "$a" = --replay-user-messages ] && replay=1
done
(sleep "${SHIM_WATCHDOG:-300}" && kill "$$" 2>/dev/null) &
n=0
emit_replay() {
  [ "$replay" = 1 ] || return 0
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"read"}]},"session_id":"s","parent_tool_use_id":null,"uuid":"%s","timestamp":"2026-01-01T00:00:00Z","isReplay":true}\n' "$1"
}
emit_result() {
  printf '{"type":"result","subtype":"success","is_error":false,"result":"done"}\n'
}
while IFS= read -r line; do
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
  case $line in
    '{"type":"user"'*) ;;
    *) continue ;;
  esac
  n=$((n + 1))
  id=$(printf '%s\n' "$line" | sed -n 's/^{"type":"user","uuid":"\([0-9a-f-]*\)".*/\1/p')
  [ -n "$id" ] || id=$(printf '00000000-0000-4000-8000-%012d' "$n")
  mode=${SHIM_STEER_MODE:-ack}
  [ "$n" != 1 ] || mode=${SHIM_FIRST:-ack}
  case $mode in
    ack)
      emit_replay "$id"
      emit_result
      ;;
    drop) emit_result ;;
    late)
      emit_result
      sleep 1
      emit_replay "$id"
      emit_result
      ;;
    hold) emit_replay "$id" ;;
  esac
done
SHIM
chmod +x "$tmp/bin/claude"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT -u PLANWRIGHT_STREAMJSON_STEER_GRACE
)

# senv <home> <record-dir> [VAR=val...] -- <args...>
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

lines_of() {
  if [ -f "$1" ]; then
    wc -l <"$1" | tr -d ' '
  else
    echo 0
  fi
}
lines_cmp() {
  test "$(lines_of "$1")" "$2" "$3"
}

# start_worker <home> <rec> <handle> [VAR=val...] — a live foreground-supervised
# shim worker with a one-second tick and grace, waited on until the launch
# prompt has reached it.
start_worker() {
  sw_home=$1
  sw_rec=$2
  sw_h=$3
  shift 3
  mkdir -p "$sw_rec"
  printf 'begin\n' >"$tmp/prompt-$sw_h"
  senv "$sw_home" "$sw_rec" PLANWRIGHT_STREAMJSON_ALARM_TICK=1 PLANWRIGHT_STREAMJSON_STEER_GRACE=1 "$@" -- \
    launch "$sw_h" fleet-lifecycle-closure:9 --prompt-file "$tmp/prompt-$sw_h" --foreground \
    >/dev/null 2>&1 &
  live_pids="$live_pids $!"
  poll_until --what 'the launch prompt' -- grep -q '"type":"user"' "$sw_rec/stdin" \
    || fail "$sw_h: the worker never received its launch prompt"
}

# reported <home> <worker> — the worker's attention row names an unread steer.
reported() {
  [ -f "$1/attention/state" ] && grep -q "^$2$tab.*steer .*never read" "$1/attention/state"
}

# ---------------------------------------------------------------------------
# a1 + a2: the replay flag, the steer's uuid, its acknowledgement.
# ---------------------------------------------------------------------------
home="$tmp/h2"
rec="$tmp/r2"
start_worker "$home" "$rec" sja2 SHIM_STEER_MODE=ack
wdir="$home/streamjson/sja2"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a2: the launch turn never ended"
case " $(cat "$rec/argv") " in
  *" --replay-user-messages "*) : ;;
  *) fail "a1: the launch must pass --replay-user-messages; argv: $(cat "$rec/argv")" ;;
esac
echo "ok: a1 every launch asks the session to replay the user frames it reads"

printf 'the gate is green, carry on\n' >"$tmp/steer2"
senv "$home" "$rec" -- steer sja2 --message-file "$tmp/steer2" >/dev/null || fail "a2: steer exited non-zero"
poll_until --what 'the steer on stdin' -- lines_cmp "$rec/stdin" -ge 2 || fail "a2: the steer never reached the worker"
a2_id=$(sed -n 2p "$rec/stdin" | jq -r '.uuid // empty')
case $a2_id in
  ????????-????-4???-[89ab]???-????????????) : ;;
  *) fail "a2: the steer frame must carry a v4 uuid of its own; got '$a2_id' in $(sed -n 2p "$rec/stdin")" ;;
esac
[ "$(lines_of "$wdir/steers")" = 1 ] || fail "a2: one steer, one receipt row"
grep -q "^[0-9]*${tab}[0-9]*${tab}$tmp/steer2${tab}$a2_id\$" "$wdir/steers" \
  || fail "a2: the receipt row must end with the steer's uuid: $(cat "$wdir/steers")"
poll_until --what 'the acknowledgement' -- grep -q "$tab$a2_id\$" "$wdir/steer-acks" \
  || fail "a2: the session's replay must be recorded as the steer's acknowledgement: $(cat "$wdir/steer-acks" 2>&1)"
sleep 3
reported "$home" sja2 && fail "a2: an acknowledged steer was reported unread: $(cat "$home/attention/state")"
echo "ok: a2 a steer carries its own uuid, the receipt row records it, and the replay acknowledges it"

# ---------------------------------------------------------------------------
# a3: the reported shape — the turn ends and the steer was never read.
# ---------------------------------------------------------------------------
home="$tmp/h3"
rec="$tmp/r3"
start_worker "$home" "$rec" sja3 SHIM_STEER_MODE=drop
wdir="$home/streamjson/sja3"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a3: the launch turn never ended"
printf 'answer: take the narrower reading\n' >"$tmp/steer3"
senv "$home" "$rec" -- steer sja3 --message-file "$tmp/steer3" >/dev/null || fail "a3: steer exited non-zero"
poll_until --what 'the unread-steer report' -- reported "$home" sja3 \
  || fail "a3: a steer the session never read must be reported: $(cat "$home/attention/state" 2>&1)"
grep "^sja3$tab" "$home/attention/state" | grep -q "$tmp/steer3" \
  || fail "a3: the report must name the message file to re-send: $(cat "$home/attention/state")"
grep "^sja3$tab" "$home/attention/state" | grep -q "${tab}high$tab\|${tab}high\$" \
  || fail "a3: the report must be high priority: $(cat "$home/attention/state")"
a3_marks=$(find "$wdir" -name 'steer-lost-*' | wc -l | tr -d ' ')
[ "$a3_marks" = 1 ] || fail "a3: one unread steer, one report mark; got $a3_marks"
# Cleared, then left for more ticks: the mark keeps it from being raised again.
env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$here/../scripts/fleet-attention.sh" clear sja3 >/dev/null \
  || fail "a3: the attention row could not be cleared"
sleep 3
reported "$home" sja3 && fail "a3: an unread steer must be raised once, not on every tick"
echo "ok: a3 a steer the session never read is reported once, high priority, naming the message file"

# ---------------------------------------------------------------------------
# a4: read as the next turn, after the result and within the grace.
# ---------------------------------------------------------------------------
home="$tmp/h4"
rec="$tmp/r4"
start_worker "$home" "$rec" sja4 SHIM_STEER_MODE=late PLANWRIGHT_STREAMJSON_STEER_GRACE=4
wdir="$home/streamjson/sja4"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a4: the launch turn never ended"
printf 'one more thing\n' >"$tmp/steer4"
senv "$home" "$rec" -- steer sja4 --message-file "$tmp/steer4" >/dev/null || fail "a4: steer exited non-zero"
a4_id=''
poll_until --what 'the steer on stdin' -- lines_cmp "$rec/stdin" -ge 2 || fail "a4: the steer never reached the worker"
a4_id=$(sed -n 2p "$rec/stdin" | jq -r '.uuid // empty')
poll_until --what 'the late acknowledgement' -- grep -q "$tab$a4_id\$" "$wdir/steer-acks" \
  || fail "a4: the late replay was not recorded"
sleep 6
reported "$home" sja4 && fail "a4: a steer read as the next turn was reported unread: $(cat "$home/attention/state")"
echo "ok: a4 a steer read just after the turn ended is not reported"

# ---------------------------------------------------------------------------
# a5: mid-turn steers say they are queued; idle ones say nothing.
# ---------------------------------------------------------------------------
home="$tmp/h5"
rec="$tmp/r5"
start_worker "$home" "$rec" sja5 SHIM_FIRST=hold SHIM_STEER_MODE=hold
wdir="$home/streamjson/sja5"
poll_until --what 'the launch replay' -- test -s "$wdir/steer-acks" || fail "a5: the launch prompt was never replayed"
[ ! -f "$wdir/result" ] || fail "a5: the fixture turn must still be running"
printf 'stop after the gate\n' >"$tmp/steer5"
senv "$home" "$rec" -- steer sja5 --message-file "$tmp/steer5" >"$tmp/a5.out" 2>"$tmp/a5.err" \
  || fail "a5: steer exited non-zero: $(cat "$tmp/a5.err")"
case $(cat "$tmp/a5.out") in
  "steered sja5 "[0-9]*) : ;;
  *) fail "a5: stdout must stay the plain receipt line: $(cat "$tmp/a5.out")" ;;
esac
grep -q 'is mid-turn: the message is queued' "$tmp/a5.err" \
  || fail "a5: a mid-turn steer must say it is queued: $(cat "$tmp/a5.err")"
grep -q 'a long-running command delays it' "$tmp/a5.err" \
  || fail "a5: the note must say a long tool call delays it: $(cat "$tmp/a5.err")"
home="$tmp/h2"
rec="$tmp/r2"
poll_until --what 'the idle result' -- test -f "$home/streamjson/sja2/result" || fail "a5: the a2 worker never went idle"
senv "$home" "$rec" -- steer sja2 --message-file "$tmp/steer2" >/dev/null 2>"$tmp/a5i.err" || fail "a5: idle steer exited non-zero"
[ ! -s "$tmp/a5i.err" ] || fail "a5: a steer to an idle worker must print nothing on stderr: $(cat "$tmp/a5i.err")"
echo "ok: a5 a mid-turn steer says it is queued until a tool call or the turn ends; an idle one says nothing"

# ---------------------------------------------------------------------------
# a6: a runtime with no acknowledgement record is never judged.
# ---------------------------------------------------------------------------
home="$tmp/h6"
rec="$tmp/r6"
start_worker "$home" "$rec" sja6 SHIM_STEER_MODE=drop
wdir="$home/streamjson/sja6"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a6: the launch turn never ended"
rm -f "$wdir/replay-since"
printf 'legacy\n' >"$tmp/steer6"
senv "$home" "$rec" -- steer sja6 --message-file "$tmp/steer6" >/dev/null || fail "a6: steer exited non-zero"
poll_until --what 'the steer on stdin' -- lines_cmp "$rec/stdin" -ge 2 || fail "a6: the steer never reached the worker"
sleep 4
reported "$home" sja6 && fail "a6: a steer to a runtime with no acknowledgement record was judged"
echo "ok: a6 a runtime that predates the acknowledgement record is never judged"

# ---------------------------------------------------------------------------
# a7: alarm-scan reports a dead worker's unread steer.
# ---------------------------------------------------------------------------
home="$tmp/h7"
wdir="$home/streamjson/sja7"
mkdir -p "$wdir"
a7_id='0a0a0a0a-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
printf '1000\n' >"$wdir/replay-since"
printf '1100\t12\t%s\t%s\n' "$tmp/steer7" "$a7_id" >"$wdir/steers"
printf '1050\t0b0b0b0b-1b1b-4c2c-8d3d-4e4e4e4e4e4e\n' >"$wdir/steer-acks"
printf 'exit\t0\t1200\n' >"$wdir/result"
a7_out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" alarm-scan --now 2000) \
  || fail "a7: alarm-scan exited non-zero"
case $a7_out in
  *"steer-lost sja7 $a7_id"*) : ;;
  *) fail "a7: alarm-scan must report the dead worker's unread steer; got: $a7_out" ;;
esac
reported "$home" sja7 || fail "a7: the unread steer must reach the attention store: $(cat "$home/attention/state" 2>&1)"
a7_again=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" alarm-scan --now 2001)
case $a7_again in
  *steer-lost*) fail "a7: a second scan must not report it again: $a7_again" ;;
esac
echo "ok: a7 alarm-scan reports, once, the unread steer of a worker that has died"

# ---------------------------------------------------------------------------
# a8: nothing outlives the suite.
# ---------------------------------------------------------------------------
for h in sja2 sja3 sja4 sja5 sja6; do
  for d in "$tmp"/h*/streamjson/"$h"; do
    [ -d "$d" ] || continue
    senv "${d%/streamjson/*}" "$tmp/r-stop" -- stop "$h" >/dev/null 2>&1 || :
  done
done
poll_until --what 'the fixture processes to exit' -- fixture_none "$tmp/" \
  || fail "a8: fixture processes outlived their close: $(fixture_report "$tmp/")"
echo "ok: a8 no supervisor, tick, or shim outlives the suite"
