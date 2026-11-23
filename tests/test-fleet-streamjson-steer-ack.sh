#!/bin/bash
# Tests for knowing whether a steer reached the stream-json worker it was
# written to: the CLI writes nothing for a user frame it reads unless the
# session runs with --replay-user-messages.
#
#   a1  every launch passes --replay-user-messages
#   a2  a steer's own uuid is on its receipt row; its replay records it read
#   a3  a steer unread past a later turn end is reported once, high priority
#   a4  a steer replayed just after the turn's result is not reported
#   a5  a mid-turn steer says it is queued; an idle one is quiet
#   a6  a runtime that predates the replay record is never judged
#   a7  alarm-scan reports the unread steer of a worker that has died
#   a9  only a user line ending in the marker is a replay
#   a10 an idle worker's untaken steer is reported by its own age
#   a11 a refused report is retried and pushed once
#   a13 the scan's boundaries
#   a14 a frame read after a result retires it
#   a12 an empty replay record is rewritten at launch
#   a8  nothing from this run outlives the suite
#
# Hermetic: the fleet home and the CLI seam are case-local; the CLI is a shim.
# Runs standalone under /bin/bash (bash 3.2).
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
    swallow) ;;
    next)
      emit_result
      sleep 1
      emit_replay "$id"
      ;;
    forge)
      # Tool input is raw JSON in the stream, so its keys can spell the
      # replay marker; neither line below is a replay.
      printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"isReplay":true,"uuid":"%s"}}]},"uuid":"%s"}\n' "$id" "$id"
      printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"x"}]},"uuid":"../bad","isReplay":true}\n'
      # A replay in a shape the supervisor does not expect, then a real one.
      printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"x"}]},"uuid":"7a7a7a7a-1b1b-4c2c-8d3d-4e4e4e4e4e4e","isReplay":true,"later":1}\n'
      printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"y"}]},"uuid":"8a8a8a8a-1b1b-4c2c-8d3d-4e4e4e4e4e4e","isReplay":true,"later":2}\n'
      printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"x"}]},"uuid":"6a6a6a6a-1b1b-4c2c-8d3d-4e4e4e4e4e4e","isReplay":true}\n'
      printf '{"type":"result","subtype":"success","is_error":false,"result":"done","permission_denials":[{"tool_name":"Bash","tool_input":{"isReplay":true,"uuid":"%s"}}]}\n' "$id"
      ;;
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
    >/dev/null 2>"$tmp/sup-$sw_h.err" &
  live_pids="$live_pids $!"
  poll_until --what 'the launch prompt' -- grep -q '"type":"user"' "$sw_rec/stdin" \
    || fail "$sw_h: the worker never received its launch prompt"
}

# stop_worker <home> <handle> — close a case's worker once the case is done, so
# its tick stops loading the host for the cases after it.
stop_worker() {
  senv "$1" "$tmp/r-stop" -- stop "$2" >/dev/null 2>&1 || :
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
grep -q "^[0-9]*${tab}[0-9]*${tab}$tmp/steer2${tab}$a2_id${tab}idle\$" "$wdir/steers" \
  || fail "a2: the receipt row must carry the steer's uuid and that the worker was idle: $(cat "$wdir/steers")"
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
# Given relative, from another directory: the report must still name it whole.
(cd "$tmp" && senv "$home" "$rec" -- steer sja3 --message-file steer3) >/dev/null || fail "a3: steer exited non-zero"
poll_until --what 'the unread-steer report' -- reported "$home" sja3 \
  || fail "a3: a steer the session never read must be reported: $(cat "$home/attention/state" 2>&1)"
grep "^sja3$tab" "$home/attention/state" | grep -q "re-send $tmp/steer3 with" \
  || fail "a3: the report must name the message file to re-send by its full path: $(cat "$home/attention/state")"
awk -F'\t' '$1 == "sja3" && $5 == "high" { f = 1 } END { exit !f }' "$home/attention/state" \
  || fail "a3: the report must be high priority: $(cat "$home/attention/state")"
a3_marks=$(find "$wdir" -name 'steer-lost-*' | wc -l | tr -d ' ')
[ "$a3_marks" = 1 ] || fail "a3: one unread steer, one report mark; got $a3_marks"
# Cleared, then left for more ticks: the mark keeps it from being raised again.
env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$here/../scripts/fleet-attention.sh" clear sja3 >/dev/null \
  || fail "a3: the attention row could not be cleared"
sleep 3
reported "$home" sja3 && fail "a3: an unread steer must be raised once, not on every tick"
stop_worker "$home" sja3
echo "ok: a3 a steer the session never read is reported once, high priority, naming the message file"

# ---------------------------------------------------------------------------
# a4: read as the next turn, after the result and within the grace.
# ---------------------------------------------------------------------------
home="$tmp/h4"
rec="$tmp/r4"
start_worker "$home" "$rec" sja4 SHIM_STEER_MODE=late PLANWRIGHT_STREAMJSON_STEER_GRACE=8
wdir="$home/streamjson/sja4"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a4: the launch turn never ended"
printf 'one more thing\n' >"$tmp/steer4"
senv "$home" "$rec" -- steer sja4 --message-file "$tmp/steer4" >/dev/null || fail "a4: steer exited non-zero"
a4_id=''
poll_until --what 'the steer on stdin' -- lines_cmp "$rec/stdin" -ge 2 || fail "a4: the steer never reached the worker"
a4_id=$(sed -n 2p "$rec/stdin" | jq -r '.uuid // empty')
poll_until --what 'the late acknowledgement' -- grep -q "$tab$a4_id\$" "$wdir/steer-acks" \
  || fail "a4: the late replay was not recorded"
# Past the grace, so an unacknowledged steer would have been reported by now.
sleep 10
reported "$home" sja4 && fail "a4: a steer read as the next turn was reported unread: $(cat "$home/attention/state")"
stop_worker "$home" sja4
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
stop_worker "$tmp/h5" sja5
stop_worker "$tmp/h2" sja2
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
# The control: the same steer is judged once the record is back, so the
# silence above came from the record's absence and not from an idle tick.
printf '1\n' >"$wdir/replay-since"
poll_until --what 'the unread-steer report' -- reported "$home" sja6 \
  || fail "a6: the tick never judged the steer once the record was back"
stop_worker "$home" sja6
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
grep "^sja7$tab" "$home/attention/state" | grep -q 'the worker exited 800s ago' \
  || fail "a7: a worker that exited must not be reported as ending a turn: $(cat "$home/attention/state")"
a7_again=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" alarm-scan --now 2001)
case $a7_again in
  *steer-lost*) fail "a7: a second scan must not report it again: $a7_again" ;;
esac
env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_STREAMJSON_STEER_GRACE=soon \
  /bin/sh "$SJ" alarm-scan --now 2002 >/dev/null 2>"$tmp/a7.err"
grep -q "invalid PLANWRIGHT_STREAMJSON_STEER_GRACE 'soon'; using 60" "$tmp/a7.err" \
  || fail "a7: a malformed grace must be named, not silently replaced: $(cat "$tmp/a7.err")"
echo "ok: a7 alarm-scan reports, once, the unread steer of a worker that has died"

# ---------------------------------------------------------------------------
# a9: only a user line is a replay. A result or assistant line whose tool
#     input spells the marker keeps its own meaning and acknowledges nothing,
#     and a replay whose uuid is out of grammar records nothing.
# ---------------------------------------------------------------------------
home="$tmp/h9"
rec="$tmp/r9"
start_worker "$home" "$rec" sja9 SHIM_STEER_MODE=forge
wdir="$home/streamjson/sja9"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a9: the launch turn never ended"
printf 'forged\n' >"$tmp/steer9"
senv "$home" "$rec" -- steer sja9 --message-file "$tmp/steer9" >/dev/null || fail "a9: steer exited non-zero"
poll_until --what 'the steer on stdin' -- lines_cmp "$rec/stdin" -ge 2 || fail "a9: the steer never reached the worker"
a9_id=$(sed -n 2p "$rec/stdin" | jq -r '.uuid // empty')
poll_until --what 'the forged turn result' -- test -f "$wdir/result" \
  || fail "a9: a result line carrying the marker in its tool input must still record the result"
case $(senv "$home" "$rec" -- status sja9) in
  "status sja9 completed "*) : ;;
  *) fail "a9: the forged turn must read completed: $(senv "$home" "$rec" -- status sja9)" ;;
esac
grep -q "$a9_id" "$wdir/steer-acks" && fail "a9: a marker inside tool input acknowledged the steer: $(cat "$wdir/steer-acks")"
grep -q 'bad' "$wdir/steer-acks" && fail "a9: an out-of-grammar replay uuid was recorded: $(cat "$wdir/steer-acks")"
grep -q '6a6a6a6a-1b1b-4c2c-8d3d-4e4e4e4e4e4e' "$wdir/steer-acks" \
  || fail "a9: the real replay beside the forged lines must still be recorded: $(cat "$wdir/steer-acks")"
grep -q '7a7a7a7a' "$wdir/steer-acks" && fail "a9: a replay in an unexpected shape was recorded"
[ "$(grep -c 'a replay line in an unexpected shape' "$tmp/sup-sja9.err")" = 1 ] \
  || fail "a9: replays in an unexpected shape must be named once per run: $(cat "$tmp/sup-sja9.err")"
stop_worker "$home" sja9
echo "ok: a9 only a user line is a replay, and an out-of-grammar uuid records nothing"

# ---------------------------------------------------------------------------
# a10: a steer to an idle worker that the session never takes opens no turn,
#      so no later result exists to judge it by; its own age past the grace
#      is enough.
# ---------------------------------------------------------------------------
home="$tmp/h10"
rec="$tmp/r10"
start_worker "$home" "$rec" sja10 SHIM_STEER_MODE=swallow
wdir="$home/streamjson/sja10"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a10: the launch turn never ended"
printf 'are you there\n' >"$tmp/steer10"
senv "$home" "$rec" -- steer sja10 --message-file "$tmp/steer10" >/dev/null 2>"$tmp/a10.err" || fail "a10: steer exited non-zero"
[ ! -s "$tmp/a10.err" ] || fail "a10: a steer to an idle worker is not queued: $(cat "$tmp/a10.err")"
poll_until --what 'the unread-steer report' -- reported "$home" sja10 \
  || fail "a10: an idle worker's untaken steer must be reported: $(cat "$home/attention/state" 2>&1)"
grep "^sja10$tab" "$home/attention/state" | grep -q 'idle' \
  || fail "a10: the report must say the worker was idle: $(cat "$home/attention/state")"
stop_worker "$home" sja10
echo "ok: a10 a steer an idle worker never takes is reported by its own age"

# ---------------------------------------------------------------------------
# a11: a report the attention store refused is retried by the next scan, and
#      a mark that cannot be written still reports.
# ---------------------------------------------------------------------------
home="$tmp/h11"
wdir="$home/streamjson/sja11"
mkdir -p "$wdir"
a11_id='1a1a1a1a-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
printf '1000\n' >"$wdir/replay-since"
printf '1100\t12\t%s\t%s\tbusy\n' "$tmp/steer11" "$a11_id" >"$wdir/steers"
printf 'exit\t0\t1200\n' >"$wdir/result"
printf 'not a directory\n' >"$home/attention"
a11_out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" alarm-scan --now 2000 2>/dev/null)
case $a11_out in
  *steer-lost*) fail "a11: a report the store refused must not read as made: $a11_out" ;;
esac
[ ! -e "$wdir/steer-lost-$a11_id" ] || fail "a11: a refused report must not keep its mark"
rm -f "$home/attention"
a11_out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" alarm-scan --now 2001)
case $a11_out in
  *"steer-lost sja11 $a11_id"*) : ;;
  *) fail "a11: the next scan must report what the store refused: $a11_out" ;;
esac
if [ "$(id -u)" != 0 ]; then
  a11_id2='2a2a2a2a-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
  printf '1150\t12\t%s\t%s\tbusy\n' "$tmp/steer11b" "$a11_id2" >>"$wdir/steers"
  chmod 555 "$wdir"
  a11_out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" alarm-scan --now 2002 2>/dev/null)
  chmod 755 "$wdir"
  case $a11_out in
    *"steer-lost sja11 $a11_id2"*) : ;;
    *) fail "a11: a mark that cannot be written must still report: $a11_out" ;;
  esac
fi
# Retries are pushed once: the store refuses the item (its directory is read
# only) while pushes still land in the existing toast file.
if [ "$(id -u)" != 0 ]; then
  home="$tmp/h11b"
  wdir="$home/streamjson/sja11"
  mkdir -p "$wdir" "$home/attention"
  : >"$home/attention/toasts"
  chmod 555 "$home/attention"
  printf '1000\n' >"$wdir/replay-since"
  printf '1100\t12\t%s\t%s\tbusy\n' "$tmp/steer11" "$a11_id" >"$wdir/steers"
  printf 'exit\t0\t1200\n' >"$wdir/result"
  printf 'notification_channel: none\n' >"$tmp/a11-core.yml"
  printf 'notification_channel: editor-toast\n' >"$tmp/a11-pin.yml"
  for a11_now in 2000 2001 2002; do
    env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_REPO_ROOT=none \
      PLANWRIGHT_CONFIG_DEFAULTS="$tmp/a11-core.yml" PLANWRIGHT_LOCAL_CONFIG="$tmp/a11-pin.yml" \
      /bin/sh "$SJ" alarm-scan --now "$a11_now" >/dev/null 2>&1
  done
  chmod 755 "$home/attention"
  [ ! -e "$wdir/steer-lost-$a11_id" ] || fail "a11: the store never took the report, so its mark must be free"
  [ -f "$wdir/steer-pushed-$a11_id" ] || fail "a11: a refused report must record that its push was made"
  a11_pushes=$(grep -c 'never read' "$home/attention/toasts")
  [ "$a11_pushes" = 1 ] || fail "a11: three refused scans must push once, pushed $a11_pushes: $(cat "$home/attention/toasts")"
  # The store is back: the retry lands the item, pushes nothing more, and
  # clears the push record.
  a11_out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_CONFIG_DEFAULTS="$tmp/a11-core.yml" PLANWRIGHT_LOCAL_CONFIG="$tmp/a11-pin.yml" \
    /bin/sh "$SJ" alarm-scan --now 2003 2>/dev/null)
  case $a11_out in
    *"steer-lost sja11 $a11_id"*) : ;;
    *) fail "a11: the retry must land once the store is back: $a11_out" ;;
  esac
  [ "$(grep -c 'never read' "$home/attention/toasts")" = 1 ] || fail "a11: the landed retry must not push again"
  [ ! -e "$wdir/steer-pushed-$a11_id" ] || fail "a11: a landed retry must clear its push record"
  # A link planted at the push record's name is never written through.
  a11_id3='3b3b3b3b-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
  printf '1160\t12\t%s\t%s\tbusy\n' "$tmp/steer11c" "$a11_id3" >>"$wdir/steers"
  ln -s "$tmp/a11-target" "$wdir/steer-pushed-$a11_id3"
  chmod 555 "$home/attention"
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_CONFIG_DEFAULTS="$tmp/a11-core.yml" PLANWRIGHT_LOCAL_CONFIG="$tmp/a11-pin.yml" \
    /bin/sh "$SJ" alarm-scan --now 2004 >/dev/null 2>&1
  chmod 755 "$home/attention"
  [ ! -e "$tmp/a11-target" ] || fail "a11: the push record was written through a planted link"
fi
echo "ok: a11 a refused report is retried without another push, and an unwritable mark still reports"

# ---------------------------------------------------------------------------
# a13: the scan's boundaries, on a hand-built runtime: a steer older than the
#      replay record, a busy steer newer than the last turn's end, and one
#      inside the grace are not judged; the turn's end and the grace count
#      inclusively.
# ---------------------------------------------------------------------------
home="$tmp/h13"
wdir="$home/streamjson/sja13"
mkdir -p "$wdir"
a13_old='3a3a3a3a-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
a13_new='4a4a4a4a-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
a13_edge='5a5a5a5a-1b1b-4c2c-8d3d-4e4e4e4e4e4e'
printf '1000\n' >"$wdir/replay-since"
{
  printf '999\t1\t%s\t%s\tbusy\n' "$tmp/old" "$a13_old"
  printf '1300\t1\t%s\t%s\tbusy\n' "$tmp/new" "$a13_new"
  printf '1200\t1\t%s\t%s\tbusy\n' "$tmp/edge" "$a13_edge"
} >"$wdir/steers"
printf 'result\tsuccess\t1200\tfalse\n' >"$wdir/result"
a13_scan() {
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_STREAMJSON_STEER_GRACE=60 \
    /bin/sh "$SJ" alarm-scan --now "$1"
}
a13_out=$(a13_scan 1259)
[ -z "$a13_out" ] || fail "a13: nothing is judged inside the grace: $a13_out"
a13_out=$(a13_scan 1260)
[ "$a13_out" = "steer-lost sja13 $a13_edge" ] \
  || fail "a13: only the steer at the turn's end is judged, at exactly the grace; got: $a13_out"
# An idle steer a turn has ended after is judged from that end, not its own age.
home="$tmp/h13b"
wdir="$home/streamjson/sja13"
mkdir -p "$wdir"
printf '1000\n' >"$wdir/replay-since"
printf '1100\t1\t%s\t%s\tidle\n' "$tmp/idle" "$a13_edge" >"$wdir/steers"
printf 'result\tsuccess\t1200\tfalse\n' >"$wdir/result"
a13_out=$(a13_scan 1170)
[ -z "$a13_out" ] || fail "a13: an idle steer with a later turn end is judged from that end: $a13_out"
a13_out=$(a13_scan 1260)
[ "$a13_out" = "steer-lost sja13 $a13_edge" ] || fail "a13: the idle steer must be judged once the end is old enough; got: $a13_out"
echo "ok: a13 the replay record, the turn's end and the grace bound what is judged"

# ---------------------------------------------------------------------------
# a14: a frame read after the turn's result starts a new turn, so that result
#      stops speaking for the worker: it reads running, and the next steer is
#      queued, not idle.
# ---------------------------------------------------------------------------
home="$tmp/h14"
rec="$tmp/r14"
start_worker "$home" "$rec" sja14 SHIM_STEER_MODE=next
wdir="$home/streamjson/sja14"
poll_until --what 'the launch turn result' -- test -f "$wdir/result" || fail "a14: the launch turn never ended"
printf 'first\n' >"$tmp/steer14"
senv "$home" "$rec" -- steer sja14 --message-file "$tmp/steer14" >/dev/null 2>&1 || fail "a14: steer exited non-zero"
poll_until --what 'the steer on stdin' -- lines_cmp "$rec/stdin" -ge 2 || fail "a14: the steer never reached the worker"
a14_id=$(sed -n 2p "$rec/stdin" | jq -r '.uuid // empty')
poll_until --what 'the acknowledgement' -- grep -q "$tab$a14_id\$" "$wdir/steer-acks" || fail "a14: the replay was not recorded"
case $(senv "$home" "$rec" -- status sja14) in
  "status sja14 running "*) : ;;
  *) fail "a14: a turn started by a read frame must read running: $(senv "$home" "$rec" -- status sja14)" ;;
esac
printf 'second\n' >"$tmp/steer14b"
senv "$home" "$rec" -- steer sja14 --message-file "$tmp/steer14b" >/dev/null 2>"$tmp/a14.err" || fail "a14: second steer exited non-zero"
grep -q 'is mid-turn: the message is queued' "$tmp/a14.err" || fail "a14: the second steer must be queued: $(cat "$tmp/a14.err")"
tail -n 1 "$wdir/steers" | grep -q "${tab}busy\$" || fail "a14: the second steer must be recorded busy: $(tail -n 1 "$wdir/steers")"
stop_worker "$home" sja14
echo "ok: a14 a frame read after the result retires it, so the next steer is queued"

# ---------------------------------------------------------------------------
# a12: an empty replay record is rewritten at launch, never kept.
# ---------------------------------------------------------------------------
home="$tmp/h12"
rec="$tmp/r12"
mkdir -p "$home/streamjson/sja12"
: >"$home/streamjson/sja12/replay-since"
start_worker "$home" "$rec" sja12
grep -Eq '^[1-9][0-9]*$' "$home/streamjson/sja12/replay-since" \
  || fail "a12: an empty replay record must be rewritten: '$(cat "$home/streamjson/sja12/replay-since")'"
stop_worker "$home" sja12
echo "ok: a12 an empty replay record is rewritten at launch"

# ---------------------------------------------------------------------------
# a8: nothing outlives the suite.
# ---------------------------------------------------------------------------
for h in sja2 sja3 sja4 sja5 sja6 sja9 sja10 sja12 sja14; do
  for d in "$tmp"/h*/streamjson/"$h"; do
    [ -d "$d" ] || continue
    senv "${d%/streamjson/*}" "$tmp/r-stop" -- stop "$h" >/dev/null 2>&1 || :
  done
done
poll_until --what 'the fixture processes to exit' -- fixture_none "$tmp/" \
  || fail "a8: fixture processes outlived their close: $(fixture_report "$tmp/")"
echo "ok: a8 no supervisor, tick, or shim outlives the suite"
