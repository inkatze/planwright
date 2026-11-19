#!/bin/bash
# The freeze (scripts/fleet-stop-lib.sh, stop_freeze) waits until each
# signalled process has actually stopped: `kill -STOP` returns while the
# target can still be running on a loaded host, and a re-read of the process
# table before it stops races a process that can still fork.
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

# shellcheck source=tests/lib/dead-owner.sh
. "$REPO_ROOT/tests/lib/dead-owner.sh"
# shellcheck disable=SC2034 # read by the sourced library
me=test-fleet-stop-await
# shellcheck disable=SC2034 # read by the sourced library
script_dir=$REPO_ROOT/scripts
# shellcheck source=scripts/fleet-stop-lib.sh
. "$REPO_ROOT/scripts/fleet-stop-lib.sh"
# The rungs run with globbing off.
set -f

now_s() { date +%s; }

# start_victim: a running process the cases signal, its pid in `victim`.
start_victim() {
  sleep 60 &
  victim=$!
  pids="$pids $victim"
}

# A stop that lands a moment after the signal: the wait must hold until the
# process is in the stopped state, not return on the queued signal.
start_victim
stop_tracked=$victim
sf_skip=''
freeze_settle=30
(
  sleep 1
  kill -STOP "$victim"
) &
delayed=$!
stop_await_stopped
state=$(stop_state "$victim")
if [ "$state" = T ]; then
  pass "the wait holds until a late stop has taken effect"
else
  fail "the wait returned with the process in state '$state'"
fi
wait "$delayed"

# stop_freeze itself waits: a `kill -STOP` that takes effect only after a
# delay, and a table read that finds nothing new, leave the process stopped
# on return only if the freeze waited before it went on.
kill -CONT "$victim"
(
  kill() {
    if [ "${1:-}" = -STOP ]; then
      (
        sleep 1
        command kill "$@"
      ) 2>>"$T/noise" &
    else
      command kill "$@"
    fi
  }
  stop_candidates() { :; }
  stop_tracked=$victim
  stop_freeze dir match files
)
state=$(stop_state "$victim")
if [ "$state" = T ]; then
  pass "stop_freeze returns with a member whose stop was slow to land stopped"
else
  fail "stop_freeze returned with the process in state '$state'"
fi

# A member that never stops is waited for only to the bound, then skipped for
# the rest of the freeze.
kill -CONT "$victim"
sf_skip=''
freeze_settle=1
start=$(now_s)
stop_await_stopped
elapsed=$(($(now_s) - start))
if [ "$elapsed" -ge 1 ] && [ "$elapsed" -le 8 ]; then
  pass "a member that does not stop is waited for only to freeze_settle"
else
  fail "the bounded wait took ${elapsed} s for a 1 s bound"
fi
case $sf_skip in
  *" $victim "*) pass "the member that did not stop is skipped from then on" ;;
  *) fail "a member that did not stop was not skipped: '$sf_skip'" ;;
esac
start=$(now_s)
stop_await_stopped
elapsed=$(($(now_s) - start))
if [ "$elapsed" -le 1 ]; then
  pass "a skipped member costs no further wait"
else
  fail "a skipped member still took ${elapsed} s"
fi

# A member that is gone is settled at once.
gone=$(dead_owner_pid) || gone=''
if [ -z "$gone" ]; then
  echo "skip: no pid above the host's range to stand for a gone member"
else
  stop_tracked=$gone
  sf_skip=''
  freeze_settle=30
  start=$(now_s)
  stop_await_stopped
  elapsed=$(($(now_s) - start))
  if [ "$elapsed" -le 1 ]; then
    pass "a member that is gone returns without waiting"
  else
    fail "a gone member took ${elapsed} s"
  fi
fi

[ "$failures" = 0 ] || exit 1
echo "ok: the freeze waits for a stop to take effect, bounded"
