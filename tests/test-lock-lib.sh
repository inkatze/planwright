#!/bin/bash
# Tests for scripts/lock-lib.sh — the one advisory-lock primitive every lock
# holder in the script layer sources (universal-binary D-11, REQ-E1.5).
#
# Contract under test:
#   - acquisition is an ATOMIC CREATE carrying an OWNER TOKEN: the lock is a
#     symlink whose target is the token, so a create cannot succeed for two
#     callers and a holder can always prove the lock is still its own;
#   - release is OWNERSHIP-VERIFIED: a caller that does not hold the lock
#     cannot unlink it, so the classic advisory-lock clobber (a holder
#     returning after its lock was broken and deleting the CURRENT holder's
#     lock) cannot happen;
#   - a lock is STALE when the owner token's PROCESS IS ABSENT, never when it
#     is merely old: an ancient lock whose owner still runs is a live lock,
#     and a fresh lock whose owner died is breakable immediately;
#   - the stale break CANNOT DOUBLE-GRANT: concurrent breakers of the same
#     dead owner serialize, and the critical section is never occupied twice;
#   - release is SIGNAL-SAFE and installed BEFORE the critical section, so a
#     holder killed mid-section does not leak the lock;
#   - acquisition is REENTRANT BY TOKEN: a nested acquire under the same token
#     succeeds and the lock is held until the OUTERMOST release.
#
# Every assertion drives the library through a real shell (POSIX `sh`, which is
# `dash` on the Linux runners), never through bash-only behaviour: the runtime
# floor is portable sh and a test that only proves bash proves the wrong thing.
# shellcheck disable=SC2016 # every body handed to `sh -c` below is literal
# shell text the library's caller runs; expanding it here would run it in the
# wrong shell and defeat the point.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lock-lib.sh"

failures=0

pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

assert_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1 (expected '$2', got '$3')"
  fi
}

assert_exit() {
  if [ "$2" -eq "$3" ]; then
    pass "$1"
  else
    fail "$1 (expected exit $2, got $3)"
  fi
}

if [ ! -f "$LIB" ]; then
  echo "FAIL: lock library missing at $LIB" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# The portable-floor shell the library must run under. `sh` is dash on the
# Linux runners and a bash build on macOS; both are in the support bar, and
# running the library under whichever one this host ships is the point.
SH=/bin/sh

# run_sh <script-body> — run a body with the library sourced, print its stdout,
# return its exit status. The body is passed as the shell's script text, so it
# sees no bash builtins and no bash-only parameter expansions.
run_sh() {
  $SH -c ". \"\$1\"; shift; $2" sh "$LIB" "$tmp"
}

# ---------------------------------------------------------------------------
# 1. Acquisition is an atomic create carrying an owner token
# ---------------------------------------------------------------------------

out="$(run_sh x '
  pw_lock_acquire "$1/a.lock" || exit 9
  [ -L "$1/a.lock" ] || exit 8
  printf "%s\n" "$(readlink "$1/a.lock")"
  printf "%s\n" "$PW_LOCK_TOKEN"
')"
rc=$?
assert_exit "acquire on a free path succeeds" 0 "$rc"
link_target="$(printf '%s\n' "$out" | sed -n 1p)"
token="$(printf '%s\n' "$out" | sed -n 2p)"
assert_eq "the lock is a symlink whose target is the owner token" "$token" "$link_target"
case $token in
  [0-9]*-*) pass "the owner token leads with the holder's pid" ;;
  *) fail "the owner token leads with the holder's pid (got '$token')" ;;
esac
rm -f "$tmp/a.lock"

# ---------------------------------------------------------------------------
# 2. A second caller cannot acquire a held lock
# ---------------------------------------------------------------------------

# A live holder: a background sleep whose pid goes into a hand-built token, so
# the lock's owner is demonstrably a running process that is not this test.
sleep 45 &
live_pid=$!
ln -s "$live_pid-0-1" "$tmp/busy.lock"

run_sh x 'pw_lock_try "$1/busy.lock"' >/dev/null 2>&1
assert_exit "try against a live holder reports busy" 1 $?

run_sh x 'pw_lock_acquire "$1/busy.lock" 5' >/dev/null 2>&1
assert_exit "a bounded acquire against a live holder fails closed" 1 $?

assert_eq "the live holder's lock survives the refused acquire" \
  "$live_pid-0-1" "$(readlink "$tmp/busy.lock")"

# ---------------------------------------------------------------------------
# 3. Staleness is process absence, NEVER age
# ---------------------------------------------------------------------------

# The live holder's lock, back-dated far past any plausible age threshold. An
# age-based break would take it; a liveness-based break must not.
touch -h -t 200001010000 "$tmp/busy.lock" 2>/dev/null \
  || touch -t 200001010000 "$tmp/busy.lock" 2>/dev/null || true
run_sh x 'pw_lock_acquire "$1/busy.lock" 5' >/dev/null 2>&1
assert_exit "an ancient lock whose owner still runs is NOT stale" 1 $?
assert_eq "the ancient live lock is left standing" \
  "$live_pid-0-1" "$(readlink "$tmp/busy.lock")"
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp/busy.lock"

# A dead owner: spawn and reap a child, then use its pid. The pid is free, so
# the token names no running process.
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
ln -s "$dead_pid-0-1" "$tmp/dead.lock"
# Fresh mtime: the break must fire on the absent process, not on an age.
out="$(run_sh x '
  pw_lock_acquire "$1/dead.lock" 5 || exit 9
  printf "%s\n" "$(readlink "$1/dead.lock")"
')"
assert_exit "a FRESH lock whose owner is gone is stale and breakable" 0 $?
case $out in
  "$dead_pid-0-1") fail "the break replaced the dead owner's token" ;;
  '') fail "the break left no lock behind" ;;
  *) pass "the break replaced the dead owner's token" ;;
esac
rm -f "$tmp"/dead.lock*

# A token this library never minted (no pid to probe) names no live owner and
# is breakable, rather than wedging the path forever.
ln -s 'not-a-token' "$tmp/foreign.lock"
run_sh x 'pw_lock_acquire "$1/foreign.lock" 5' >/dev/null 2>&1
assert_exit "a token with no probeable pid is treated as absent" 0 $?
rm -f "$tmp"/foreign.lock*

# ---------------------------------------------------------------------------
# 4. A non-symlink squatting the lock path is refused, not broken
# ---------------------------------------------------------------------------

mkdir "$tmp/legacy.lock"
run_sh x 'pw_lock_acquire "$1/legacy.lock" 5' >/dev/null 2>&1
assert_exit "a directory at the lock path is a real error, not contention" 2 $?
if [ -d "$tmp/legacy.lock" ]; then
  pass "the refused acquire leaves the squatting directory untouched"
else
  fail "the refused acquire leaves the squatting directory untouched"
fi
rmdir "$tmp/legacy.lock"

# ---------------------------------------------------------------------------
# 5. Release is ownership-verified
# ---------------------------------------------------------------------------

sleep 45 &
live_pid=$!
ln -s "$live_pid-0-1" "$tmp/other.lock"
run_sh x 'pw_lock_release "$1/other.lock"' >/dev/null 2>&1
assert_exit "releasing a lock we never took reports not-ours" 1 $?
assert_eq "a lock we never took is left standing" \
  "$live_pid-0-1" "$(readlink "$tmp/other.lock")"
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp/other.lock"

# The clobber this shape exists to prevent: a holder whose lock was broken
# returns and must NOT unlink the CURRENT holder's lock.
out="$(run_sh x '
  pw_lock_acquire "$1/clobber.lock" || exit 9
  mine=$PW_LOCK_TOKEN
  # A successor takes the path out from under us (what a stale break does).
  rm -f "$1/clobber.lock"
  ln -s "successor-token" "$1/clobber.lock"
  pw_lock_release "$1/clobber.lock"
  printf "%s %s\n" "$?" "$(readlink "$1/clobber.lock")"
  printf "%s\n" "$mine" >/dev/null
')"
assert_eq "a broken-and-returned holder cannot unlink the successor's lock" \
  "1 successor-token" "$out"
rm -f "$tmp/clobber.lock"

# ---------------------------------------------------------------------------
# 6. Reentrancy by token
# ---------------------------------------------------------------------------

out="$(run_sh x '
  pw_lock_acquire "$1/re.lock" || exit 9
  outer=$PW_LOCK_TOKEN
  pw_lock_acquire "$1/re.lock" || exit 8
  inner=$PW_LOCK_TOKEN
  [ "$outer" = "$inner" ] || exit 7
  pw_lock_release "$1/re.lock" || exit 6
  # The INNER release must not drop the lock.
  [ -L "$1/re.lock" ] && printf "held-after-inner\n"
  pw_lock_release "$1/re.lock" || exit 5
  [ -L "$1/re.lock" ] || printf "gone-after-outer\n"
')"
assert_exit "a nested acquire under the same token succeeds" 0 $?
assert_eq "the lock is held until the OUTERMOST release" \
  "held-after-inner
gone-after-outer" "$out"

# Depth is per lock path, not global: releasing one lock must not affect another.
run_sh x '
  pw_lock_acquire "$1/p.lock" || exit 9
  pw_lock_acquire "$1/q.lock" || exit 8
  pw_lock_release "$1/p.lock" || exit 7
  [ -L "$1/q.lock" ] || exit 6
  [ ! -L "$1/p.lock" ] || exit 5
' >/dev/null 2>&1
assert_exit "reentrancy depth is tracked per lock path" 0 $?
rm -f "$tmp"/p.lock "$tmp"/q.lock

# pw_lock_release_all drops every depth of every held lock.
run_sh x '
  pw_lock_acquire "$1/r1.lock" || exit 9
  pw_lock_acquire "$1/r1.lock" || exit 9
  pw_lock_acquire "$1/r2.lock" || exit 8
  pw_lock_release_all
  [ ! -L "$1/r1.lock" ] || exit 7
  [ ! -L "$1/r2.lock" ] || exit 6
' >/dev/null 2>&1
assert_exit "release_all drops every depth of every held lock" 0 $?

# ---------------------------------------------------------------------------
# 7. Signal-safe release, installed before the critical section
# ---------------------------------------------------------------------------

$SH -c '
  . "$1"
  pw_lock_trap_install
  pw_lock_acquire "$2/sig.lock" || exit 9
  printf "held\n" >"$2/sig.ready"
  # Hold past the kill in short hops: a shell that defers a trap until the
  # foreground command returns still runs it promptly.
  i=0
  while [ "$i" -lt 200 ]; do
    sleep 0.1
    i=$((i + 1))
  done
' sh "$LIB" "$tmp" &
sig_pid=$!
i=0
while [ ! -f "$tmp/sig.ready" ] && [ "$i" -lt 200 ]; do
  sleep 0.05
  i=$((i + 1))
done
if [ -f "$tmp/sig.ready" ]; then
  kill -TERM "$sig_pid" 2>/dev/null
  wait "$sig_pid" 2>/dev/null
  if [ -L "$tmp/sig.lock" ]; then
    fail "a TERM'd holder releases its lock (lock leaked)"
  else
    pass "a TERM'd holder releases its lock"
  fi
else
  kill "$sig_pid" 2>/dev/null
  fail "a TERM'd holder releases its lock (holder never started)"
fi
rm -f "$tmp/sig.lock" "$tmp/sig.ready"

# ---------------------------------------------------------------------------
# 8. Mutual exclusion under contention: no lost update
# ---------------------------------------------------------------------------
#
# The defect this library exists to cure, in its measured shape: concurrent
# same-resource writers doing acquire / read-modify-write / release. Under the
# retired `mkdir` primitive this lost registrations silently while every writer
# exited 0. Every writer must land.

writers=12
printf '0\n' >"$tmp/counter"
rm -f "$tmp/occupancy" "$tmp/violations"
: >"$tmp/violations"
w=0
while [ "$w" -lt "$writers" ]; do
  $SH -c '
    . "$1"
    pw_lock_trap_install
    pw_lock_acquire "$2/race.lock" || exit 1
    # Occupancy detector: only a lock holder may be in here.
    if [ -e "$2/occupancy" ]; then
      printf "double-grant\n" >>"$2/violations"
    fi
    : >"$2/occupancy"
    n=$(cat "$2/counter")
    # A real read-modify-write window, which is where the retired primitive
    # lost its exclusion.
    sleep 0.01
    printf "%s\n" "$((n + 1))" >"$2/counter"
    rm -f "$2/occupancy"
    pw_lock_release "$2/race.lock"
  ' sh "$LIB" "$tmp" &
  w=$((w + 1))
done
wait
assert_eq "twelve concurrent writers all land (no lost update)" \
  "$writers" "$(cat "$tmp/counter")"
assert_eq "no two writers were inside the critical section at once" \
  "" "$(cat "$tmp/violations")"

# ---------------------------------------------------------------------------
# 9. Concurrent stale breaks cannot double-grant
# ---------------------------------------------------------------------------
#
# Every contender starts against the SAME dead owner, so they all reach the
# break path together. Exactly one may come out holding the lock; the rest
# must either wait it out or report busy — never share the section.

sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
rm -f "$tmp"/brk.lock* "$tmp/brk.occupancy" "$tmp/brk.violations" "$tmp/brk.counter"
ln -s "$dead_pid-0-1" "$tmp/brk.lock"
printf '0\n' >"$tmp/brk.counter"
: >"$tmp/brk.violations"
w=0
while [ "$w" -lt 10 ]; do
  $SH -c '
    . "$1"
    pw_lock_trap_install
    pw_lock_acquire "$2/brk.lock" || exit 1
    if [ -e "$2/brk.occupancy" ]; then
      printf "double-grant\n" >>"$2/brk.violations"
    fi
    : >"$2/brk.occupancy"
    n=$(cat "$2/brk.counter")
    sleep 0.01
    printf "%s\n" "$((n + 1))" >"$2/brk.counter"
    rm -f "$2/brk.occupancy"
    pw_lock_release "$2/brk.lock"
  ' sh "$LIB" "$tmp" &
  w=$((w + 1))
done
wait
assert_eq "concurrent breakers of one dead owner never share the section" \
  "" "$(cat "$tmp/brk.violations")"
assert_eq "every breaker's update landed once the dead lock was broken" \
  "10" "$(cat "$tmp/brk.counter")"

# The break leaves no litter behind: the aside and claim links it uses to
# serialize breakers are transient, not state the next acquire has to reason
# about.
leftovers="$(find "$tmp" -maxdepth 1 -name 'brk.lock.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "the stale break leaves no aside or claim links behind" "0" "$leftovers"

# ---------------------------------------------------------------------------
# 10. pw_lock_owner reports the holder, and nothing for a free path
# ---------------------------------------------------------------------------

out="$(run_sh x '
  pw_lock_acquire "$1/own.lock" || exit 9
  pw_lock_owner "$1/own.lock"
  printf "\n"
  pw_lock_release "$1/own.lock"
  pw_lock_owner "$1/own.lock"
  printf "\n"
')"
owner_held="$(printf '%s\n' "$out" | sed -n 1p)"
owner_free="$(printf '%s\n' "$out" | sed -n 2p)"
case $owner_held in
  [0-9]*-*) pass "pw_lock_owner prints the holder's token" ;;
  *) fail "pw_lock_owner prints the holder's token (got '$owner_held')" ;;
esac
assert_eq "pw_lock_owner prints nothing for a free path" "" "$owner_free"

# ---------------------------------------------------------------------------
# 11. Usage errors are errors, not silent successes
# ---------------------------------------------------------------------------

run_sh x 'pw_lock_acquire' >/dev/null 2>&1
assert_exit "acquire with no lock path is a usage error" 2 $?
run_sh x 'pw_lock_release' >/dev/null 2>&1
assert_exit "release with no lock path is a usage error" 2 $?

# ---------------------------------------------------------------------------
# 12. A detached hold has no owning process and is never auto-broken
# ---------------------------------------------------------------------------
#
# The CLI case: acquire in one invocation, release in a later one. Nothing runs
# in between, so there is no pid whose absence could prove the lock dead, and
# the liveness rule must not guess.

run_sh x 'pw_lock_acquire_detached "$1/det.lock"' >/dev/null 2>&1
assert_exit "a detached acquire on a free path succeeds" 0 $?
case "$(readlink "$tmp/det.lock")" in
  detached-*) pass "a detached hold records no pid where a pid would go" ;;
  *) fail "a detached hold records no pid where a pid would go (got '$(readlink "$tmp/det.lock")')" ;;
esac

# The acquiring process is long gone, and the hold still stands.
run_sh x 'pw_lock_acquire "$1/det.lock" 5' >/dev/null 2>&1
assert_exit "a detached hold survives its acquirer and is not broken" 1 $?
run_sh x 'pw_lock_acquire_detached "$1/det.lock" 5' >/dev/null 2>&1
assert_exit "a second detached acquire is refused too" 1 $?

# pw_lock_break_force is the recovery path, and the only one.
run_sh x 'pw_lock_break_force "$1/det.lock"' >/dev/null 2>&1
assert_exit "break_force clears a detached hold" 0 $?
if [ -L "$tmp/det.lock" ] || [ -e "$tmp/det.lock" ]; then
  fail "break_force leaves the path clear"
else
  pass "break_force leaves the path clear"
fi

# It also clears a directory left by the retired `mkdir` shape, which is what
# makes an in-place upgrade possible.
mkdir "$tmp/old.lock"
run_sh x 'pw_lock_break_force "$1/old.lock"' >/dev/null 2>&1
assert_exit "break_force clears a legacy mkdir lock directory" 0 $?
if [ -e "$tmp/old.lock" ]; then
  fail "break_force removes the legacy lock directory"
else
  pass "break_force removes the legacy lock directory"
fi

# A regular file is not a lock and is not something to guess about.
: >"$tmp/file.lock"
run_sh x 'pw_lock_break_force "$1/file.lock"' >/dev/null 2>&1
assert_exit "break_force refuses to remove a regular file" 2 $?
rm -f "$tmp/file.lock"

# ---------------------------------------------------------------------------
# 13. The cross-process release still proves ownership
# ---------------------------------------------------------------------------

out="$(run_sh x '
  pw_lock_acquire "$1/xp.lock" || exit 9
  printf "%s\n" "$PW_LOCK_TOKEN"
')"
xp_token="$(printf '%s\n' "$out" | sed -n 1p)"
run_sh x 'pw_lock_release_token "$1/xp.lock" "not-the-token"' >/dev/null 2>&1
assert_exit "a stranger's token cannot release the lock" 1 $?
assert_eq "the lock survives the stranger's release" \
  "$xp_token" "$(readlink "$tmp/xp.lock")"
$SH -c '. "$1"; pw_lock_release_token "$2/xp.lock" "$3"' sh "$LIB" "$tmp" "$xp_token" >/dev/null 2>&1
assert_exit "the owner's token releases it from another process" 0 $?
if [ -L "$tmp/xp.lock" ]; then
  fail "the cross-process release unlinks the lock"
else
  pass "the cross-process release unlinks the lock"
fi

# ---------------------------------------------------------------------------
# 14. A lock taken on behalf of another process is owned by that process
# ---------------------------------------------------------------------------
#
# A short-lived CLI that acquires for a caller would otherwise name ITSELF as
# owner, and the lock would read as dead the instant the CLI exited.

sleep 45 &
live_pid=$!
$SH -c '. "$1"; pw_lock_acquire_for "$2/for.lock" "$3"' sh "$LIB" "$tmp" "$live_pid" >/dev/null 2>&1
assert_exit "acquire_for takes the lock" 0 $?
case "$(readlink "$tmp/for.lock")" in
  "$live_pid"-*) pass "the token names the owner this caller nominated" ;;
  *) fail "the token names the owner this caller nominated (got '$(readlink "$tmp/for.lock")')" ;;
esac
# The acquiring shell is long gone; the nominated owner is not, so the hold
# stands.
run_sh x 'pw_lock_acquire "$1/for.lock" 5' >/dev/null 2>&1
assert_exit "the hold outlives the process that took it" 1 $?
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
# Once the nominated owner is gone, the lock is breakable at once.
run_sh x 'pw_lock_acquire "$1/for.lock" 5' >/dev/null 2>&1
assert_exit "the hold dies with the owner it nominated" 0 $?
rm -f "$tmp"/for.lock*

run_sh x 'pw_lock_acquire_for "$1/bad.lock" "not-a-pid"' >/dev/null 2>&1
assert_exit "a non-numeric owner pid is a usage error" 2 $?

if [ "$failures" -eq 0 ]; then
  echo "All lock-lib tests passed."
else
  echo "$failures lock-lib test(s) failed." >&2
fi
exit $((failures > 0))
