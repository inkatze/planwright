#!/bin/sh
# Tests for tests/lib/poll-until.sh, the wait-for-an-event helper (REQ-D1.1):
#   p1: a condition that becomes true late, inside the deadline, passes.
#   p2: a condition that never holds fails, the message naming the label, the
#       deadline, and the elapsed time observed.
#   p3: the condition runs at least once, in the calling shell, and stops
#       being polled once it holds.
#   p4: malformed arguments are refused with exit 2 before any wait.
#   p5: the helper documents its default deadline, uses it, and honours one
#       the environment already set.
#   p6: the condition's stdout is discarded; on a timeout the last attempt's
#       exit status and stderr are shown.
#   p7: pid_gone holds only once every named process has exited.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
unset POLL_UNTIL_DEFAULT_DEADLINE
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/poll-until.XXXXXX") || fail "no scratch directory"
trap 'rm -rf "$tmp"' EXIT

# --- p1 ---------------------------------------------------------------------
(sleep 1 && : >"$tmp/late") &
poll_until --deadline 30 --what 'the late file' -- test -e "$tmp/late" 2>"$tmp/p1.err" \
  || fail "p1: a condition true after a second must pass, got: $(cat "$tmp/p1.err")"
wait
[ ! -s "$tmp/p1.err" ] || fail "p1: a passing wait must print nothing, got: $(cat "$tmp/p1.err")"

# --- p2 ---------------------------------------------------------------------
# A condition slower than the deadline makes the elapsed time differ from it,
# and an independent clock read proves the wait ran past the deadline.
rc=0
t0=$(date +%s)
poll_until --deadline 1 --what 'the slow check' -- sh -c 'sleep 2; exit 1' 2>"$tmp/p2.err" || rc=$?
t1=$(date +%s)
[ "$rc" = 1 ] || fail "p2: a condition that never holds must exit 1, got $rc"
err=$(cat "$tmp/p2.err")
case $err in
  *"the slow check"*"within 1s"*"after "[0-9]*s*) ;;
  *) fail "p2: the timeout must name the label, the deadline and the elapsed time, got: $err" ;;
esac
elapsed=${err##*after }
elapsed=${elapsed%%s*}
[ "$elapsed" -ge 2 ] || fail "p2: the reported elapsed time must be what the wait observed, got ${elapsed}s"
[ "$POLL_UNTIL_ELAPSED" = "$elapsed" ] \
  || fail "p2: POLL_UNTIL_ELAPSED must carry the reported elapsed time, got '$POLL_UNTIL_ELAPSED'"
rc=0
t0=$(date +%s)
poll_until --deadline 1 -- false 2>/dev/null || rc=$?
t1=$(date +%s)
[ "$rc" = 1 ] || fail "p2: false must time out, got $rc"
[ $((t1 - t0)) -ge 1 ] || fail "p2: a 1s deadline must not give up early, waited $((t1 - t0))s"
[ "$POLL_UNTIL_ELAPSED" -gt 1 ] || fail "p2: the wait must run past the deadline, reported ${POLL_UNTIL_ELAPSED}s"

# --- p3 ---------------------------------------------------------------------
poll_until --deadline 0 -- true 2>/dev/null \
  || fail "p3: a zero deadline must still check the condition once"
n=0
second_call() {
  n=$((n + 1))
  [ "$n" -ge 2 ]
}
poll_until --deadline 30 --interval 0.1 -- second_call 2>/dev/null \
  || fail "p3: a function condition must be re-run in the calling shell"
[ "$n" = 2 ] || fail "p3: the condition must stop being polled once it holds, ran $n times"

# --- p4 ---------------------------------------------------------------------
for args in '--deadline x -- true' '--deadline -1 -- true' '--interval -- true' \
  '--bogus -- true' '--deadline 5 --' '' '--deadline' '--interval 0 -- true' \
  '--interval 0.0 -- true' '--interval .5 -- true' '--interval 5. -- true' \
  '--interval 1.2.3 -- true'; do
  rc=0
  # shellcheck disable=SC2086 # each case is a word list
  poll_until $args 2>"$tmp/p4.err" || rc=$?
  [ "$rc" = 2 ] || fail "p4: '$args' must be refused with exit 2, got $rc"
  grep -q 'poll_until:' "$tmp/p4.err" || fail "p4: '$args' must say why"
done

# --- p5 ---------------------------------------------------------------------
[ "$POLL_UNTIL_DEFAULT_DEADLINE" = 60 ] \
  || fail "p5: the default deadline must be 60s, got ${POLL_UNTIL_DEFAULT_DEADLINE}s"
grep -q "^# .*default deadline is 60s" "$here/lib/poll-until.sh" \
  || fail "p5: the header must document the 60s default deadline"
inherited=$(POLL_UNTIL_DEFAULT_DEADLINE=300 sh -c '. "$1"; printf %s "$POLL_UNTIL_DEFAULT_DEADLINE"' _ "$here/lib/poll-until.sh")
[ "$inherited" = 300 ] || fail "p5: a default the environment set must be kept, got '$inherited'"
POLL_UNTIL_DEFAULT_DEADLINE=1
poll_until -- false 2>"$tmp/p5.err" && fail "p5: false must not pass"
grep -q 'within 1s' "$tmp/p5.err" || fail "p5: the call without --deadline must use the default, got: $(cat "$tmp/p5.err")"
POLL_UNTIL_DEFAULT_DEADLINE=60

# --- p6 ---------------------------------------------------------------------
out=$(poll_until --deadline 5 -- echo noise 2>/dev/null)
[ -z "$out" ] || fail "p6: the condition's stdout must be discarded, got: $out"
rc=0
poll_until --deadline 0 --what 'the broken check' -- sh -c 'echo diag-line >&2; exit 3' 2>"$tmp/p6.err" || rc=$?
[ "$rc" = 1 ] || fail "p6: a failing condition must time out with 1, got $rc"
grep -q 'last exit status 3' "$tmp/p6.err" || fail "p6: the timeout must name the last exit status, got: $(cat "$tmp/p6.err")"
grep -q 'diag-line' "$tmp/p6.err" || fail "p6: the last attempt's stderr must be shown, got: $(cat "$tmp/p6.err")"

# --- p7 ---------------------------------------------------------------------
sleep 30 &
live=$!
sh -c 'exit 0' &
dead=$!
wait "$dead"
pid_gone "$dead" || fail "p7: an exited process must count as gone"
pid_gone "$dead" "$live" && fail "p7: a live process must keep pid_gone false"
kill "$live"
wait "$live" 2>/dev/null
pid_gone "$live" || fail "p7: a killed process must count as gone"

echo "PASS: poll-until"
