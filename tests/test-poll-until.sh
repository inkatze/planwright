#!/bin/sh
# Tests for tests/lib/poll-until.sh, the wait-for-an-event helper (REQ-D1.1):
#   p1: a condition that becomes true late, inside the deadline, passes.
#   p2: a condition that never holds fails, the message naming the label, the
#       deadline, and the elapsed time observed.
#   p3: the condition runs at least once, in the calling shell, and stops
#       being polled once it holds.
#   p4: malformed arguments are refused with exit 2 before any wait.
#   p5: the helper documents its default deadline, and uses it.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

fail() {
  echo "FAIL: $1" >&2
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
rc=0
poll_until --deadline 1 --what 'the absent file' -- test -e "$tmp/never" 2>"$tmp/p2.err" || rc=$?
[ "$rc" = 1 ] || fail "p2: a condition that never holds must exit 1, got $rc"
err=$(cat "$tmp/p2.err")
case $err in
  *"the absent file"*"1s"*"after "[0-9]*s*) ;;
  *) fail "p2: the timeout must name the label, the deadline and the elapsed time, got: $err" ;;
esac
elapsed=${err##*after }
elapsed=${elapsed%%s*}
[ "$elapsed" -ge 1 ] || fail "p2: the reported elapsed time must cover the deadline, got ${elapsed}s"
[ "$POLL_UNTIL_ELAPSED" = "$elapsed" ] \
  || fail "p2: POLL_UNTIL_ELAPSED must carry the reported elapsed time, got '$POLL_UNTIL_ELAPSED'"

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
  '--bogus -- true' '--deadline 5 --' ''; do
  rc=0
  # shellcheck disable=SC2086 # each case is a word list
  poll_until $args 2>"$tmp/p4.err" || rc=$?
  [ "$rc" = 2 ] || fail "p4: '$args' must be refused with exit 2, got $rc"
  grep -q 'poll_until:' "$tmp/p4.err" || fail "p4: '$args' must say why"
done

# --- p5 ---------------------------------------------------------------------
grep -q "^# .*default deadline.* ${POLL_UNTIL_DEFAULT_DEADLINE}s" "$here/lib/poll-until.sh" \
  || fail "p5: the header must document the default deadline (${POLL_UNTIL_DEFAULT_DEADLINE:-unset}s)"
[ "$POLL_UNTIL_DEFAULT_DEADLINE" -ge 30 ] \
  || fail "p5: the default deadline must be generous, got ${POLL_UNTIL_DEFAULT_DEADLINE}s"
POLL_UNTIL_DEFAULT_DEADLINE=1
poll_until -- false 2>"$tmp/p5.err" && fail "p5: false must not pass"
grep -q 'within 1s' "$tmp/p5.err" || fail "p5: the call without --deadline must use the default, got: $(cat "$tmp/p5.err")"

echo "PASS: poll-until"
