#!/bin/bash
# Tests for `fleet-streamjson.sh status` telling a parked session from a
# finished one: a turn that ended while the session waits on the operator, CI
# or a ready flip (a registered wait), or on an open question, reads `parked`,
# so no supervisor mistakes it for done work.
#
#   k1: a finished turn with no wait and a statement for its last line reads
#       completed.
#   k2: the same turn with a registered operator, ci or ready-flip wait reads
#       parked and names the wait; clearing the wait reads completed again.
#   k3: a turn whose final text ends in a question reads parked, trailing
#       whitespace and escapes included; a question mid-text does not count.
#   k4: an is_error result is ended, never parked, and a live worker with an
#       event after the result is running, never parked.
#
# Hermetic: the fleet home is case-local and built by hand. Runs standalone
# under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/fleet"
mkdir -p "$home/mission-control/sessions"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
)
st() { env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" status "$1"; }

# turn <worker> <result-text-json-body> [<is_error>]: a worker whose last turn
# ended with that final text; the row is the registry row of the session.
turn() {
  mkdir -p "$home/streamjson/$1"
  printf 'result\tsuccess\t1000\t%s\n' "${3:-false}" >"$home/streamjson/$1/result"
  printf '{"type":"result","subtype":"success","is_error":%s,"result":"%s"}\n' "${3:-false}" "$2" \
    >"$home/streamjson/$1/events.jsonl"
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\talpha\nkind\tad-hoc\nscope\ts\nbackend\tstream-json\nlaunched\t1\n' "$1" \
    >"$home/mission-control/sessions/$1"
}
expect() {
  got=$(st "$1") || fail "$3: status exited non-zero"
  [ "$got" = "$2" ] || fail "$3: want '$2', got '$got'"
  echo "ok: $3"
}

turn sjk1 'Done: the pull request is open.'
expect sjk1 "status sjk1 completed result=success" "k1 a finished turn reads completed"

for why in operator ci ready-flip; do
  turn sjk2 'Done: walked the spec.'
  printf 'waiting\t%s\n' "$why" >>"$home/mission-control/sessions/sjk2"
  expect sjk2 "status sjk2 parked wait=$why result=success" "k2 a registered $why wait reads parked"
done
awk -F '\t' '$1 != "waiting"' "$home/mission-control/sessions/sjk2" >"$tmp/row" && mv "$tmp/row" "$home/mission-control/sessions/sjk2"
expect sjk2 "status sjk2 completed result=success" "k2 clearing the wait reads completed again"

turn sjk3 'Two readings fit.\nShould I take the narrower one?'
expect sjk3 "status sjk3 parked question result=success" "k3 a final question reads parked"
turn sjk3 'Should I take the narrower one?  \n\n'
expect sjk3 "status sjk3 parked question result=success" "k3 trailing whitespace escapes do not hide the question"
turn sjk3 'Should I take the narrower one?\nNo: I took it, and the pull request is open.'
expect sjk3 "status sjk3 completed result=success" "k3 a question mid-text is not an open question"

turn sjk4 'Done.' true
printf 'waiting\toperator\n' >>"$home/mission-control/sessions/sjk4"
got=$(st sjk4) || fail "k4: status exited non-zero"
case $got in "status sjk4 ended "*) echo "ok: k4 an is_error result is ended, never parked" ;; *) fail "k4: got '$got'" ;; esac

turn sjk5 'Should I take the narrower one?'
printf 'waiting\toperator\n' >>"$home/mission-control/sessions/sjk5"
printf '{"type":"assistant","message":"working on the steered turn"}\n' >>"$home/streamjson/sjk5/events.jsonl"
rm -f "$home/streamjson/sjk5/result"
printf '%s\n' "$$" >"$home/streamjson/sjk5/supervisor.pid"
printf '%s\n' "$$" >"$home/streamjson/sjk5/worker.pid"
expect sjk5 "status sjk5 running supervisor=$$ worker=$$" "k5 a live worker past its result reads running, never parked"

echo "all fleet-streamjson parked tests passed"
