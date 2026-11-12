#!/bin/bash
# Tests for the owner of a stream-json worker's pending prompts: `pending`
# shows who answers each one, and `answer` from another session is refused
# unless it passes --takeover.
#
#   o1: `pending` names the owner the launch recorded in the registry; a worker
#       with no recorded owner prints no owner line.
#   o2: `answer` from a session that is not the owner is refused (exit 3), the
#       message names the owner, nothing is written to the worker and the
#       request stays pending.
#   o3: `answer --takeover` from a non-owner delivers the answer.
#   o4: the owner answers without the flag, and a caller with no identity of
#       its own, or a worker with no recorded owner, is not refused.
#
# Hermetic: the fleet home, registry and worker state are case-local and built
# by hand through the registry's own writer; no worker is launched and no
# machine state is read. Runs standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"
FS="$here/../scripts/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"

tmp=$(mktemp -d)
sleeper=''
reader=''
cleanup() {
  [ -z "$sleeper" ] || kill "$sleeper" 2>&1
  [ -z "$reader" ] || kill "$reader" 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID
  -u PLANWRIGHT_TOWER_CHECKOUT
)

# sj <home> <caller-id|-> <args...> — run the script as the named session.
sj() {
  sj_home=$1
  sj_id=$2
  shift 2
  if [ "$sj_id" = - ]; then
    env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$sj_home" /bin/sh "$SJ" "$@"
  else
    env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$sj_home" PLANWRIGHT_TOWER_ID="$sj_id" /bin/sh "$SJ" "$@"
  fi
}

# register <home> <worker> <owner|-> — the registry row a launch writes.
register() {
  if [ "$3" = - ]; then
    env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$1" /bin/sh "$FS" register "$2" scope:1 \
      --backend stream-json-persistent --state-dir "$1/streamjson/$2" >/dev/null || fail "register $2"
  else
    env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$1" /bin/sh "$FS" register "$2" scope:1 \
      --owner "$3" --backend stream-json-persistent --state-dir "$1/streamjson/$2" >/dev/null || fail "register $2"
  fi
}

# mkreq <worker-dir> <id> — one pending Bash request, as the supervisor writes it.
mkreq() {
  mkdir -p "$1"
  printf '%s\tpermission\t1700000000\tpending\n' "$2" >>"$1/journal"
  printf '{"type":"control_request","request_id":"%s","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git status"},"tool_use_id":"t"}}\n' \
    "$2" >"$1/req-$2.json"
}

id1='bbbb1111-bbbb-cccc-dddd-eeee00000001'
id2='bbbb1111-bbbb-cccc-dddd-eeee00000002'
id3='bbbb1111-bbbb-cccc-dddd-eeee00000003'
id4='bbbb1111-bbbb-cccc-dddd-eeee00000004'
sup='mission-control:planwright'
other='tower:other-session'

# A live channel: both pids name a process that stays up, and a reader drains
# the worker's stdin fifo into a file, so a delivered answer is observable.
sleep 120 &
sleeper=$!

live_channel() {
  printf '%s\n' "$sleeper" >"$1/supervisor.pid"
  printf '%s\n' "$sleeper" >"$1/worker.pid"
  mkfifo "$1/in.fifo" || fail "mkfifo"
}

# ---------------------------------------------------------------------------
# o1: pending names the recorded owner.
# ---------------------------------------------------------------------------
home="$tmp/h1"
mkreq "$home/streamjson/sjo1" "$id1"
mkreq "$home/streamjson/sjo1b" "$id2"
register "$home" sjo1 "$sup"
register "$home" sjo1b -
out=$(sj "$home" - pending sjo1) || fail "o1: pending exit $?"
case $out in
  *"-- owner $sup"*) : ;;
  *) fail "o1: pending does not show the owner, got: $out" ;;
esac
out=$(sj "$home" - pending sjo1b) || fail "o1: pending exit $?"
case $out in
  *"owner"*) fail "o1: a worker with no recorded owner shows one, got: $out" ;;
esac
echo "ok: o1 pending shows the recorded owner"

# ---------------------------------------------------------------------------
# o2: a non-owner answer is refused, naming the owner, and writes nothing.
# ---------------------------------------------------------------------------
home="$tmp/h2"
w="$home/streamjson/sjo2"
mkreq "$w" "$id1"
register "$home" sjo2 "$sup"
live_channel "$w"
cat "$w/in.fifo" >"$tmp/got2" &
reader=$!
err="$tmp/err2"
sj "$home" "$other" answer sjo2 "$id1" --allow >"$tmp/out2" 2>"$err"
rc=$?
[ "$rc" = 3 ] || fail "o2: a non-owner answer exits 3, got $rc"
grep -q "$sup" "$err" || fail "o2: the refusal does not name the owner: $(cat "$err")"
grep -q -- '--takeover' "$err" || fail "o2: the refusal does not name the takeover flag"
[ -z "$(cat "$tmp/out2")" ] || fail "o2: a refused answer printed on stdout"
state=$(awk -F'\t' -v i="$id1" '$1 == i { print $4 }' "$w/journal")
[ "$state" = pending ] || fail "o2: the refused request is $state, not pending"
kill "$reader" 2>&1
reader=''
[ ! -s "$tmp/got2" ] || fail "o2: a refused answer wrote to the worker"
echo "ok: o2 a non-owner answer is refused with the owner named"

# ---------------------------------------------------------------------------
# o3: --takeover from a non-owner delivers.
# ---------------------------------------------------------------------------
cat "$w/in.fifo" >"$tmp/got3" &
reader=$!
out=$(sj "$home" "$other" answer sjo2 "$id1" --allow --takeover 2>&1) || fail "o3: takeover answer failed: $out"
case $out in
  "answered sjo2 $id1") : ;;
  *) fail "o3: unexpected output: $out" ;;
esac
wait "$reader"
reader=''
grep -q "\"request_id\":\"$id1\"" "$tmp/got3" || fail "o3: the answer did not reach the worker"
state=$(awk -F'\t' -v i="$id1" '$1 == i { print $4 }' "$w/journal")
[ "$state" = answered ] || fail "o3: the request is $state, not answered"
echo "ok: o3 --takeover answers as a non-owner"

# ---------------------------------------------------------------------------
# o4: the owner, an unidentified caller and an ownerless worker are not refused.
# ---------------------------------------------------------------------------
mkreq "$w" "$id2"
cat "$w/in.fifo" >"$tmp/got4" &
reader=$!
out=$(sj "$home" "$sup" answer sjo2 "$id2" --allow 2>&1) || fail "o4: the owner was refused: $out"
wait "$reader"
reader=''
grep -q "\"request_id\":\"$id2\"" "$tmp/got4" || fail "o4: the owner's answer did not reach the worker"

mkreq "$w" "$id3"
cat "$w/in.fifo" >"$tmp/got5" &
reader=$!
out=$(sj "$home" - answer sjo2 "$id3" --allow 2>&1) || fail "o4: a caller with no identity was refused: $out"
wait "$reader"
reader=''

home="$tmp/h4"
w="$home/streamjson/sjo4"
mkreq "$w" "$id4"
register "$home" sjo4 -
live_channel "$w"
cat "$w/in.fifo" >"$tmp/got6" &
reader=$!
out=$(sj "$home" "$other" answer sjo4 "$id4" --allow 2>&1) || fail "o4: an ownerless worker refused an answer: $out"
wait "$reader"
reader=''
echo "ok: o4 the owner, an unidentified caller and an ownerless worker answer freely"
