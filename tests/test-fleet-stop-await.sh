#!/bin/bash
# stop_await_stopped (scripts/fleet-stop-lib.sh): the freeze waits until each
# signalled process has actually stopped, since `kill -STOP` returns while the
# target can still be running on a loaded host. A stop that lands late is the
# race behind the intermittent c25 miss in tests/test-fleet-stop-hl.sh.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL
for v in $(compgen -e); do
  case $v in
    GIT_* | PLANWRIGHT_*) unset "$v" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

T=$(mktemp -d "${TMPDIR:-/tmp}/fleet-stop-await.XXXXXX") || exit 1
pids=''
cleanup() {
  for p in $pids; do
    kill -CONT "$p" 2>>"$T/noise"
    kill -KILL "$p" 2>>"$T/noise"
  done
  rm -rf "$T"
}
trap cleanup EXIT

# shellcheck disable=SC2034 # read by the sourced library
me=test-fleet-stop-await
# shellcheck disable=SC2034 # read by the sourced library
script_dir=$REPO_ROOT/scripts
# shellcheck source=scripts/fleet-stop-lib.sh
. "$REPO_ROOT/scripts/fleet-stop-lib.sh"

now_ms() { date +%s%N | cut -c1-13; }

# A stop that lands 700 ms after the signal returns: the wait must hold until
# the process is in the stopped state, not return on the queued signal.
sleep 60 &
victim=$!
pids="$pids $victim"
stop_tracked=$victim
(
  sleep 0.7
  kill -STOP "$victim"
) &
delayed=$!
start=$(now_ms)
stop_await_stopped
elapsed=$(($(now_ms) - start))
state=$(stop_state "$victim")
if [ "$state" = T ] && [ "$elapsed" -ge 600 ]; then
  pass "the wait holds until a late stop has taken effect (${elapsed} ms)"
else
  fail "the wait returned with the process in state '$state' after ${elapsed} ms"
fi
wait "$delayed"

# A process already stopped costs no wait.
start=$(now_ms)
stop_await_stopped
elapsed=$(($(now_ms) - start))
if [ "$elapsed" -lt 500 ]; then
  pass "an already-stopped member returns without waiting"
else
  fail "an already-stopped member took ${elapsed} ms"
fi

# A process that never stops is waited for only to the bound.
kill -CONT "$victim"
freeze_settle=1
start=$(now_ms)
(
  # Re-arm the stop only after the bound has passed, so the process runs
  # throughout the wait.
  sleep 3
  kill -STOP "$victim"
) &
late=$!
stop_await_stopped
elapsed=$(($(now_ms) - start))
if [ "$elapsed" -ge 900 ] && [ "$elapsed" -lt 2800 ]; then
  pass "a member that does not stop is waited for only to freeze_settle (${elapsed} ms)"
else
  fail "the bounded wait took ${elapsed} ms for a 1 s bound"
fi
kill "$late" 2>>"$T/noise"
wait "$late" 2>>"$T/noise"

# A member that is gone is settled at once.
kill -CONT "$victim"
kill -KILL "$victim"
wait "$victim" 2>>"$T/noise"
pids=''

stop_tracked=$victim
start=$(now_ms)
stop_await_stopped
elapsed=$(($(now_ms) - start))
if [ "$elapsed" -lt 500 ]; then
  pass "a member that is gone returns without waiting"
else
  fail "a gone member took ${elapsed} ms"
fi

[ "$failures" = 0 ] || exit 1
echo "ok: the freeze waits for a stop to take effect, bounded"
