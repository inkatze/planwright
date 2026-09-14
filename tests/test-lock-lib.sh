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
sleep 120 &
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

sleep 120 &
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
leftovers="$(find "$tmp" -maxdepth 1 -name 'brk.lock?*' 2>/dev/null | wc -l | tr -d ' ')"
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

# Two detached holds taken in the same second are still distinguishable, so one
# caller's release cannot unlink the other's lock.
run_sh x 'pw_lock_acquire_detached "$1/det2.lock"' >/dev/null 2>&1
if [ "$(readlink "$tmp/det.lock")" = "$(readlink "$tmp/det2.lock")" ]; then
  fail "two detached holds get distinct tokens"
else
  pass "two detached holds get distinct tokens"
fi
rm -f "$tmp/det2.lock"

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

# A regular file at a lock path is not a lock either, and no acquire will take
# the path over it — so the escape hatch has to be able to clear it, or nothing
# can.
: >"$tmp/file.lock"
run_sh x 'pw_lock_break_force "$1/file.lock"' >/dev/null 2>&1
assert_exit "break_force clears a regular file squatting the lock path" 0 $?
if [ -e "$tmp/file.lock" ]; then
  fail "break_force removes the squatting file"
else
  pass "break_force removes the squatting file"
fi

# A lock path is a registry key as well as a filename, and the registry is
# newline-delimited: a path carrying a newline would forge a second record
# naming a path the signal handler would then unlink.
run_sh x 'pw_lock_try "$1/a
1 forged /etc/passwd"' >/dev/null 2>&1
assert_exit "a lock path containing a newline is refused" 2 $?
run_sh x 'pw_lock_release "$1/a
1 forged /etc/passwd"' >/dev/null 2>&1
assert_exit "so is releasing one" 2 $?

# An owner pid of zero names no process, so a hold minted from it would read
# dead the instant it existed.
run_sh x 'pw_lock_acquire_for "$1/zero.lock" 0' >/dev/null 2>&1
assert_exit "an owner pid of zero is refused" 2 $?

# A hold taken on behalf of another process must not sit in THIS shell's
# release registry: a trap here would drop a lock the nominated owner is still
# inside.
sleep 120 &
live_pid=$!
run_sh x "pw_lock_trap_install; pw_lock_acquire_for \"\$1/behalf.lock\" $live_pid" >/dev/null 2>&1
if [ -L "$tmp/behalf.lock" ]; then
  pass "a hold taken on behalf of another process survives this shell's exit"
else
  fail "a hold taken on behalf of another process survives this shell's exit"
fi
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp"/behalf.lock*

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

sleep 120 &
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

# ---------------------------------------------------------------------------
# 15. The lock-holder list in the library's header is the truth
# ---------------------------------------------------------------------------
#
# The header names the scripts that take their locks through this library, and
# a list like that rots the moment someone adopts a sixth script or drops one.
# Compare it against what the tree actually sources, so the claim cannot
# outlive its accuracy.

listed="$(sed -n 's|^#   \(scripts/[a-z0-9-]*\.sh\).*|\1|p' "$LIB" | sort -u)"
# Two signals, because the tree sources it two ways: a literal `. <path>`, and
# where the path goes through a variable, the shellcheck source= directive the
# house style requires at the site. The guard is excluded because its usage
# text shows the remedy as an example, which reads the same to a line scan.
sourcing="$(grep -lE '^[[:space:]]*(\. .*lock-lib\.sh|# shellcheck source=scripts/lock-lib\.sh$)' \
  "$REPO_ROOT"/scripts/*.sh 2>/dev/null \
  | sed "s|^$REPO_ROOT/||" \
  | grep -vE '^scripts/(lock-lib|check-lock-primitive)\.sh$' | sort -u)"
if [ -z "$listed" ]; then
  fail "the header's lock-holder list could not be read"
elif [ "$listed" = "$sourcing" ]; then
  pass "every script the header lists sources the library, and no other does"
else
  fail "the header's lock-holder list has drifted from the tree
  listed but not sourcing:  $(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$sourcing") | tr '\n' ' ')
  sourcing but not listed:  $(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$sourcing") | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 16. Breaking a lock whose target happens to be a directory
# ---------------------------------------------------------------------------
#
# The lock is a link and the break must act on the LINK, never on whatever it
# points at. A target that happens to be an existing directory is the shape
# that catches a break built on `mv`: the rename follows the link and files the
# replacement INSIDE that directory, so the lock is never broken, the acquirer
# spins its whole budget, and every spin litters a stray link into somebody
# else's directory.

sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
mkdir -p "$tmp/target-dir"
ln -s "$tmp/target-dir" "$tmp/dirtarget.lock"
run_sh x 'pw_lock_acquire "$1/dirtarget.lock" 20' >/dev/null 2>&1
assert_exit "a lock pointing at a directory is broken like any other" 0 $?
strays="$(find "$tmp/target-dir" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "the break leaves nothing inside the directory it pointed at" "0" "$strays"
if [ -d "$tmp/target-dir" ]; then
  pass "the break leaves the directory it pointed at alone"
else
  fail "the break leaves the directory it pointed at alone"
fi
rm -f "$tmp"/dirtarget.lock*
rm -rf "$tmp/target-dir"

# ---------------------------------------------------------------------------
# 17. The hold is recorded BEFORE the link is published
# ---------------------------------------------------------------------------
#
# The signal handler releases what the registry names, so any instant where the
# link exists on disk and the registry does not know about it is an instant
# where a signal leaks the lock until someone breaks it. The ordering is not
# observable from outside, so it is pinned from the inside: the confirm step
# reads the link back through `readlink`, and a stand-in for `readlink` can
# report what the registry held at that moment.

run_sh x '
  ORDER_TRACE="$1/order.trace"
  readlink() {
    case $PW_LOCK_HELD in
      *order.lock*) printf "registry-first\n" >>"$ORDER_TRACE" ;;
      *) printf "link-first\n" >>"$ORDER_TRACE" ;;
    esac
    command readlink "$@"
  }
  pw_lock_acquire "$1/order.lock"
' >/dev/null 2>&1
assert_eq "the registry knows about the hold before the link is confirmed" \
  "registry-first" "$(sed -n 1p "$tmp/order.trace" 2>/dev/null)"
rm -f "$tmp/order.lock" "$tmp/order.trace"

# ---------------------------------------------------------------------------
# 18. A hold broken underneath a nested holder still owes every release
# ---------------------------------------------------------------------------
#
# The shell holds the path twice, something clears the link out from under it
# (an operator's unconditional release, a stale break), and it takes the lock
# again. It now owes THREE releases, not one: collapsing the depth would make
# the first release unlink while the two outer sections are still inside.

run_sh x '
  pw_lock_acquire "$1/nest.lock" || exit 9
  pw_lock_acquire "$1/nest.lock" || exit 8
  rm -f "$1/nest.lock"
  pw_lock_acquire "$1/nest.lock" || exit 7
  pw_lock_release "$1/nest.lock" || exit 6
  [ -L "$1/nest.lock" ] || exit 5
  pw_lock_release "$1/nest.lock" || exit 4
  [ -L "$1/nest.lock" ] || exit 3
  pw_lock_release "$1/nest.lock" || exit 2
  [ ! -L "$1/nest.lock" ] || exit 1
' >/dev/null 2>&1
assert_exit "a re-take after a break keeps the releases the shell still owes" 0 $?
rm -f "$tmp"/nest.lock*

# ---------------------------------------------------------------------------
# 19. Release unlinks before it forgets
# ---------------------------------------------------------------------------
#
# The mirror of case 17. A record dropped ahead of its unlink is a lock the
# signal handler can no longer see, which is the same leak in the same window
# on the way out.

run_sh x '
  ORDER_TRACE="$1/rel.trace"
  pw_lock_acquire "$1/rel.lock" || exit 9
  readlink() {
    case $PW_LOCK_HELD in
      *rel.lock*) printf "still-recorded\n" >>"$ORDER_TRACE" ;;
      *) printf "already-forgotten\n" >>"$ORDER_TRACE" ;;
    esac
    command readlink "$@"
  }
  pw_lock_release "$1/rel.lock"
' >/dev/null 2>&1
assert_eq "release still has the hold recorded when it verifies ownership" \
  "still-recorded" "$(sed -n 1p "$tmp/rel.trace" 2>/dev/null)"
rm -f "$tmp/rel.lock" "$tmp/rel.trace"

# ---------------------------------------------------------------------------
# 20. Two processes acquiring for one owner in the same second differ
# ---------------------------------------------------------------------------
#
# The token is what a cross-process release compares against, so two CLIs that
# minted the same one would let a replayed release of the first hold unlink the
# second holder's live lock.

sleep 120 &
live_pid=$!
t1="$($SH -c '. "$1"; pw_lock_acquire_for "$2/u1.lock" "$3" >/dev/null 2>&1; printf "%s" "$(readlink "$2/u1.lock")"' sh "$LIB" "$tmp" "$live_pid")"
t2="$($SH -c '. "$1"; pw_lock_acquire_for "$2/u2.lock" "$3" >/dev/null 2>&1; printf "%s" "$(readlink "$2/u2.lock")"' sh "$LIB" "$tmp" "$live_pid")"
if [ -n "$t1" ] && [ "$t1" != "$t2" ]; then
  pass "two processes acquiring for one owner mint distinct tokens"
else
  fail "two processes acquiring for one owner mint distinct tokens (got '$t1' twice)"
fi
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp"/u1.lock* "$tmp"/u2.lock*

# ---------------------------------------------------------------------------
# 21. The escape hatch collects the break residue belonging to its lock
# ---------------------------------------------------------------------------
#
# A breaker killed mid-break leaves a claim link. It is harmless while its
# owner can be probed, and permanent once that pid is recycled — at which point
# the stale break for that lock stops working.

ln -s "detached-1-1-1" "$tmp/res.lock"
ln -s "1-1-1-1" "$tmp/res.lock#break#1_1_1"
run_sh x 'pw_lock_break_force "$1/res.lock"' >/dev/null 2>&1
assert_exit "break_force clears the lock" 0 $?
left="$(find "$tmp" -maxdepth 1 -name 'res.lock*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "break_force collects the break residue too" "0" "$left"

# ---------------------------------------------------------------------------
# 22. The break reclaims a claim its own breaker died holding
# ---------------------------------------------------------------------------
#
# Without this the path is wedged for good: the dead owner's lock is breakable,
# but every breaker finds a claim it must not step on and reports busy.

sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
ln -s "$dead_pid-0-0-1" "$tmp/orphan.lock"
ln -s "$dead_pid-0-0-2" "$tmp/orphan.lock#break#$dead_pid-0-0-1"
run_sh x 'pw_lock_acquire "$1/orphan.lock" 40' >/dev/null 2>&1
assert_exit "a claim left by a dead breaker is reclaimed, not waited on" 0 $?
rm -f "$tmp"/orphan.lock*

# A claim whose breaker is STILL RUNNING is left alone: that breaker is mid-act
# and stepping on it is how two callers end up breaking the same lock.
sleep 120 &
live_pid=$!
ln -s "$dead_pid-0-0-1" "$tmp/held.lock"
ln -s "$live_pid-0-0-1" "$tmp/held.lock#break#$dead_pid-0-0-1"
run_sh x 'pw_lock_acquire "$1/held.lock" 5' >/dev/null 2>&1
rc=$?
if kill -0 "$live_pid" 2>/dev/null; then
  assert_exit "a claim whose breaker is still running is left alone" 1 "$rc"
  assert_eq "and the running breaker's claim survives" \
    "$live_pid-0-0-1" "$(readlink "$tmp/held.lock#break#$dead_pid-0-0-1")"
else
  fail "the live-breaker fixture outlived its own breaker; the case proved nothing"
fi
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp"/held.lock*

# ---------------------------------------------------------------------------
# 23. release_all proves ownership too
# ---------------------------------------------------------------------------
#
# It is the handler that runs after a process has been broken, so it is the one
# release most likely to be looking at somebody else's lock.

out="$(run_sh x '
  pw_lock_acquire "$1/ra.lock" || exit 9
  rm -f "$1/ra.lock"
  ln -s "successor-token" "$1/ra.lock"
  pw_lock_release_all
  printf "%s\n" "$(readlink "$1/ra.lock")"
')"
assert_eq "release_all leaves a successor's lock alone" "successor-token" "$out"
rm -f "$tmp/ra.lock"

# ---------------------------------------------------------------------------
# 24. Trap install is one-shot, so it cannot replace a caller's own handlers
# ---------------------------------------------------------------------------

out="$(run_sh x '
  pw_lock_trap_install
  trap "printf mine" EXIT
  pw_lock_trap_install
')"
assert_eq "a second trap_install leaves the caller's handler in place" "mine" "$out"

# ---------------------------------------------------------------------------
# 25. INT and HUP release too, with the documented exit codes
# ---------------------------------------------------------------------------

for sig in INT HUP; do
  case $sig in
    INT) want=130 ;;
    *) want=129 ;;
  esac
  rm -f "$tmp/s.lock" "$tmp/s.ready"
  $SH -c '
    . "$1"
    pw_lock_trap_install
    pw_lock_acquire "$2/s.lock" || exit 9
    printf "held\n" >"$2/s.ready"
    i=0
    while [ "$i" -lt 200 ]; do
      sleep 0.1
      i=$((i + 1))
    done
  ' sh "$LIB" "$tmp" &
  sig_pid=$!
  i=0
  while [ ! -f "$tmp/s.ready" ] && [ "$i" -lt 200 ]; do
    sleep 0.05
    i=$((i + 1))
  done
  got=0
  kill -"$sig" "$sig_pid" 2>/dev/null
  wait "$sig_pid" || got=$?
  if [ -L "$tmp/s.lock" ]; then
    fail "a $sig'd holder releases its lock"
  else
    pass "a $sig'd holder releases its lock"
  fi
  # The exit code is asserted for every signal a bash parent can actually
  # observe. It cannot observe INT: a non-interactive bash reports 0 from
  # `wait` for a child that handled SIGINT and exited, whatever the child
  # exited with. Asserting it there would pin bash's reporting, not the
  # library's behaviour.
  if [ "$sig" != INT ]; then
    assert_eq "a $sig'd holder exits $want" "$want" "$got"
  fi
done
rm -f "$tmp/s.lock" "$tmp/s.ready"

# ---------------------------------------------------------------------------
# 26. clear_legacy takes a directory and refuses everything else
# ---------------------------------------------------------------------------

mkdir "$tmp/leg.lock"
run_sh x 'pw_lock_clear_legacy "$1/leg.lock"' >/dev/null 2>&1
assert_exit "clear_legacy takes a lock directory" 0 $?
if [ -e "$tmp/leg.lock" ]; then
  fail "clear_legacy removed the directory"
else
  pass "clear_legacy removed the directory"
fi

# A SYMLINK is a live lock. Clearing one out of a recovery path is how two
# callers end up inside the same critical section.
sleep 120 &
live_pid=$!
ln -s "$live_pid-0-0-1" "$tmp/leg.lock"
run_sh x 'pw_lock_clear_legacy "$1/leg.lock"' >/dev/null 2>&1
assert_exit "clear_legacy refuses a live lock" 1 $?
assert_eq "and leaves it exactly as it found it" \
  "$live_pid-0-0-1" "$(readlink "$tmp/leg.lock")"
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp"/leg.lock*

run_sh x 'pw_lock_clear_legacy "$1/absent.lock"' >/dev/null 2>&1
assert_exit "clear_legacy on a free path is a clean nothing-to-do" 1 $?

# ---------------------------------------------------------------------------
# 27. The liveness probe's edges
# ---------------------------------------------------------------------------
#
# A process this shell may not signal answers EPERM, and reading that as absent
# would break a live holder's lock — the double-grant the whole design exists
# to prevent. pid 1 is the one process every host has and no ordinary user may
# signal.

run_sh x 'pw_lock_owner_alive "1-0-0-1"' >/dev/null 2>&1
assert_exit "a process this shell may not signal reads as alive" 0 $?
run_sh x 'pw_lock_owner_alive "0-0-0-1"' >/dev/null 2>&1
assert_exit "pid zero names no process" 1 $?
run_sh x 'pw_lock_owner_alive "99999999999999999999-0-0-1"' >/dev/null 2>&1
assert_exit "a pid wider than any host assigns names no process" 1 $?
run_sh x 'pw_lock_owner_alive' >/dev/null 2>&1
assert_exit "and asking about nothing is not an error a caller has to handle" 1 $?

# ---------------------------------------------------------------------------
# 28. A budget of zero or nonsense means the default, never no waiting at all
# ---------------------------------------------------------------------------

sleep 120 &
live_pid=$!
ln -s "$live_pid-0-0-1" "$tmp/bud.lock"
start=$(date +%s)
run_sh x 'pw_lock_acquire "$1/bud.lock" 25' >/dev/null 2>&1
rc=$?
mid=$(date +%s)
if kill -0 "$live_pid" 2>/dev/null; then
  assert_exit "a bounded acquire against a live holder reports busy" 1 "$rc"
  if [ "$((mid - start))" -le 30 ]; then
    pass "and a small budget really is small"
  else
    fail "and a small budget really is small (took $((mid - start))s)"
  fi
else
  fail "the live-holder fixture outlived its own holder; the case proved nothing"
fi
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp/bud.lock"

# ---------------------------------------------------------------------------
# 29. A hold cannot be handed to somebody else from inside it
# ---------------------------------------------------------------------------
#
# A shell that already holds the path cannot delegate it: the hold it would be
# giving away is the one it is standing in. Reporting success and quietly
# deepening its own hold instead is the worst of the three answers, because the
# bookkeeping is then dropped and the shell can no longer release at all.

out="$(run_sh x '
  pw_lock_acquire "$1/give.lock" 3 || exit 9
  mine=$PW_LOCK_TOKEN
  pw_lock_acquire_for "$1/give.lock" 999999 1
  printf "for-rc=%s\n" "$?"
  printf "target-changed=%s\n" "$([ "$(readlink "$1/give.lock")" = "$mine" ] && printf no || printf yes)"
  pw_lock_release "$1/give.lock"
  printf "release-rc=%s\n" "$?"
  printf "still-there=%s\n" "$([ -L "$1/give.lock" ] && printf yes || printf no)"
')"
assert_eq "handing a held lock to another process is refused, and leaves the hold releasable" \
  "for-rc=2
target-changed=no
release-rc=0
still-there=no" "$out"
rm -f "$tmp"/give.lock*

# On a free path it still works, which is the case the verb exists for.
sleep 120 &
live_pid=$!
run_sh x "pw_lock_acquire_for \"\$1/free.lock\" $live_pid 3" >/dev/null 2>&1
assert_exit "acquiring for another process on a free path still succeeds" 0 $?
case "$(readlink "$tmp/free.lock")" in
  "$live_pid"-*) pass "and the hold is the nominated process's" ;;
  *) fail "and the hold is the nominated process's (got '$(readlink "$tmp/free.lock")')" ;;
esac
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$tmp"/free.lock*

# ---------------------------------------------------------------------------
# 30. The legacy clear never overwrites a lock that arrived while it worked
# ---------------------------------------------------------------------------
#
# The clear renames the directory aside so the two steps cannot be raced. What
# it must not do is rename it BACK over whatever holds the path by then: a
# rename lands regardless of what is in the way, so the restore that exists to
# undo a mistake would destroy a live successor's lock instead.

out="$(run_sh x '
  lockp="$1/race.lock"
  mkdir "$lockp"
  real_mv=$(command -v mv)
  moved=0
  mv() {
    if [ "$moved" = 0 ]; then
      moved=1
      # A peer wins the path between the shape test and the rename: it clears
      # the legacy directory and takes a real lock, so what gets renamed aside
      # is that peer.
      rm -rf "$lockp"
      ln -s "peer-one" "$lockp"
      "$real_mv" "$@"
      # ...and a second peer takes the freed path before the restore runs.
      ln -s "peer-two" "$lockp"
      return 0
    fi
    "$real_mv" "$@"
  }
  pw_lock_clear_legacy "$lockp" >/dev/null 2>&1
  printf "%s\n" "$(readlink "$lockp")"
')"
assert_eq "the legacy clear leaves a lock taken while it worked exactly as it found it" \
  "peer-two" "$out"
rm -rf "$tmp"/race.lock*

# ---------------------------------------------------------------------------
# 31. A lock path may not carry the character the library derives paths with
# ---------------------------------------------------------------------------
#
# The break claim, its aside and the legacy aside all hang off the lock path
# with a `#`. A caller that could name a lock containing one could name another
# lock's working path, which is the collision the separator was chosen to
# prevent — so the rule is enforced here rather than asked of callers.

run_sh x 'pw_lock_try "$1/has#hash.lock"' >/dev/null 2>&1
assert_exit "a lock path containing the derivation separator is refused" 2 $?
run_sh x 'pw_lock_release "$1/has#hash.lock"' >/dev/null 2>&1
assert_exit "so is releasing one" 2 $?
run_sh x 'pw_lock_clear_legacy "$1/has#hash.lock"' >/dev/null 2>&1
assert_exit "and so is clearing one" 2 $?

if [ "$failures" -eq 0 ]; then
  echo "All lock-lib tests passed."
else
  echo "$failures lock-lib test(s) failed." >&2
fi
exit $((failures > 0))
