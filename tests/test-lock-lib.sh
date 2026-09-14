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
# a list like that rots the moment someone adopts another script or drops one.
# Compare it against what the tree actually sources, so the claim cannot
# outlive its accuracy.

listed="$(sed -n 's|^#   \(scripts/[a-z0-9-]*\.sh\).*|\1|p' "$LIB" | sort -u)"
# An empty list is a legitimate state, but only when the header SAYS so. Read
# it from an explicit marker rather than inferring it from a parse that found
# nothing, or a header someone reformatted would pass as "no holders".
declares_none=no
grep -q '^#   (none yet: ' "$LIB" && declares_none=yes
# Two signals, because the tree sources it two ways: a literal `. <path>`, and
# where the path goes through a variable, the shellcheck source= directive the
# house style requires at the site. The guard is excluded because its usage
# text shows the remedy as an example, which reads the same to a line scan.
sourcing="$(grep -lE '^[[:space:]]*(\. .*lock-lib\.sh|# shellcheck source=scripts/lock-lib\.sh$)' \
  "$REPO_ROOT"/scripts/*.sh 2>/dev/null \
  | sed "s|^$REPO_ROOT/||" \
  | grep -vE '^scripts/(lock-lib|check-lock-primitive)\.sh$' | sort -u)"
if [ -z "$listed" ] && [ "$declares_none" = no ]; then
  fail "the header's lock-holder list could not be read"
elif [ -n "$listed" ] && [ "$declares_none" = yes ]; then
  fail "the header both names lock holders and declares it has none"
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

# ---------------------------------------------------------------------------
# 32. The break's destructive step is exclusive on its own
# ---------------------------------------------------------------------------
#
# The claim serializes breakers of one dead owner, and until now it was the
# ONLY thing that did: two callers past it both removed the lock and both
# published, so the second took the first's freshly minted link and both
# believed they held it. A gate is a bad place for a single point of failure
# when what it guards is a double grant, so the step guards itself too — it
# claims the dead link by renaming it, which the loser cannot do because the
# source is gone by then.
#
# Staged deterministically: the gate sees the dead owner, and the lock changes
# hands before the destructive step runs.

out="$(run_sh x '
  lockp="$1/excl.lock"
  ln -s "9999999-0-0-1" "$lockp"
  # The flag is a file, not a variable: the calls being shimmed happen inside
  # command substitutions, so a variable set here dies with the subshell and
  # the shim would fire on every call instead of once.
  flag="$1/excl.fired"
  readlink() {
    # The gate reads the dead owner once; by the time the step acts, a
    # successor holds the path.
    if [ ! -f "$flag" ] && [ "$1" = "$lockp" ]; then
      : >"$flag"
      rm -f "$lockp"
      ln -s "successor-token" "$lockp"
      printf "%s\n" "9999999-0-0-1"
      return 0
    fi
    command readlink "$@"
  }
  _pw_lock_break "$lockp" "9999999-0-0-1" "mine-token" 1 >/dev/null 2>&1
  printf "rc=%s\n" "$?"
  printf "link=%s\n" "$(command readlink "$lockp" 2>/dev/null || printf NONE)"
')"
assert_eq "a breaker that lost the path before its destructive step leaves the successor alone" \
  "rc=1
link=successor-token" "$out"
rm -f "$tmp"/excl.lock*

# And the ordinary break still works, leaving no residue of the claim it took.
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null
ln -s "$dead_pid-0-0-1" "$tmp/plain.lock"
run_sh x 'pw_lock_acquire "$1/plain.lock" 20' >/dev/null 2>&1
assert_exit "an uncontested break still takes the lock" 0 $?
left="$(find "$tmp" -maxdepth 1 -name 'plain.lock?*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "and leaves nothing of the claim it took behind" "0" "$left"
rm -f "$tmp"/plain.lock*

# ---------------------------------------------------------------------------
# 33. The depth a shell still owes survives contention, not just the break
# ---------------------------------------------------------------------------
#
# Case 18 covers a re-take that succeeds immediately. When the re-take has to
# WAIT — a successor holds the path for a moment — the owed depth used to be
# computed, dropped with the registry record, and then forgotten, so the next
# spin reacquired at depth one and the first release unlinked while the outer
# sections were still inside.

run_sh x '
  lockp="$1/owed.lock"
  pw_lock_acquire "$lockp" || exit 9
  pw_lock_acquire "$lockp" || exit 8          # this shell owes two
  # The hold is cleared underneath it and a live successor takes the path, so
  # the first re-take attempt has to wait rather than winning at once.
  sleep 45 &
  succ=$!
  rm -f "$lockp"
  ln -s "$succ-0-0-1" "$lockp"
  ( sleep 0.4; rm -f "$lockp"; kill "$succ" 2>/dev/null ) &
  pw_lock_acquire "$lockp" 400 || exit 7      # owes three now
  pw_lock_release "$lockp" || exit 6
  [ -L "$lockp" ] || exit 5
  pw_lock_release "$lockp" || exit 4
  [ -L "$lockp" ] || exit 3
  pw_lock_release "$lockp" || exit 2
  [ ! -L "$lockp" ] || exit 1
' >/dev/null 2>&1
assert_exit "an owed depth survives a re-take that had to wait for the path" 0 $?
rm -f "$tmp"/owed.lock*

# ---------------------------------------------------------------------------
# 34. The claim sweep takes the links this library made, and nothing else
# ---------------------------------------------------------------------------
#
# The escape hatch collects the break residue by glob. Only links are ever put
# there by this library, so a directory matching the glob belongs to somebody
# else — and recursively deleting somebody else's directory is not a thing a
# lock primitive should do on an operator's behalf.

ln -s "detached-1-1-1" "$tmp/keep.lock"
ln -s "1-1-1-1" "$tmp/keep.lock#break#1_1_1"
mkdir -p "$tmp/keep.lock#break#planted/inner"
: >"$tmp/keep.lock#break#planted/inner/data"
run_sh x 'pw_lock_break_force "$1/keep.lock"' >/dev/null 2>&1
assert_exit "break_force clears the lock" 0 $?
if [ -f "$tmp/keep.lock#break#planted/inner/data" ]; then
  pass "and leaves a directory it did not create alone"
else
  fail "and leaves a directory it did not create alone"
fi
if [ -L "$tmp/keep.lock#break#1_1_1" ]; then
  fail "but still collects the claim links it did create"
else
  pass "but still collects the claim links it did create"
fi
rm -rf "$tmp"/keep.lock*

# ---------------------------------------------------------------------------
# 35. Release takes the link it owns, rather than checking and then removing
# ---------------------------------------------------------------------------
#
# The ownership check and the unlink were two operations. Between them an
# operator break or a sweep can clear the link and a successor can publish, and
# the unlink then took the successor's lock — the clobber the token exists to
# prevent, arriving through the verb that exists to prevent it.

# The check and the removal are one act now — the link is taken by renaming it
# to a path of this caller's own, and what moved is inspected before anything
# is deleted — so a release whose lock changed hands finds a stranger in its
# hand and puts it back, rather than deleting it and reporting success.
run_sh x '
  pw_lock_acquire "$1/rel2.lock" || exit 9
  rm -f "$1/rel2.lock"
  ln -s "successor-token" "$1/rel2.lock"
  pw_lock_release "$1/rel2.lock" && exit 8
  [ "$(command readlink "$1/rel2.lock")" = successor-token ] || exit 7
' >/dev/null 2>&1
assert_exit "a release whose lock changed hands puts the successor back" 0 $?
left="$(find "$tmp" -maxdepth 1 -name 'rel2.lock#*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "and keeps none of the link it borrowed to look at it" "0" "$left"
rm -f "$tmp"/rel2.lock*

# The ordinary release still works, and leaves nothing of its own behind.
run_sh x '
  pw_lock_acquire "$1/rel3.lock" || exit 9
  pw_lock_release "$1/rel3.lock" || exit 8
  [ ! -L "$1/rel3.lock" ] || exit 7
' >/dev/null 2>&1
assert_exit "an ordinary release still clears the lock" 0 $?
left="$(find "$tmp" -maxdepth 1 -name 'rel3.lock?*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "and leaves no residue of its own" "0" "$left"
rm -f "$tmp"/rel3.lock*

# The cross-process release is the same act, so it answers the same way.
out="$(run_sh x '
  pw_lock_acquire "$1/rel4.lock" || exit 9
  printf "%s\n" "$PW_LOCK_TOKEN"
')"
rel4_token="$(printf '%s\n' "$out" | sed -n 1p)"
rm -f "$tmp/rel4.lock"
ln -s "successor-token" "$tmp/rel4.lock"
$SH -c '. "$1"; pw_lock_release_token "$2/rel4.lock" "$3"' sh "$LIB" "$tmp" "$rel4_token" >/dev/null 2>&1
assert_exit "a token release over a successor's lock is refused" 1 $?
assert_eq "and the successor's lock is untouched" \
  "successor-token" "$(readlink "$tmp/rel4.lock")"
rm -f "$tmp"/rel4.lock*

# ---------------------------------------------------------------------------
# 36. A recycled pid is not the owner that minted the token
# ---------------------------------------------------------------------------
#
# The probe reads the pid out of the token and asks whether it is running. On a
# long-lived host the OS recycles pids, so a lock whose owner died can name a
# live unrelated process and read as held forever. The token already carries
# the moment it was minted, and a process that started AFTER that moment cannot
# be the one that minted it — which is the whole of the check, and it can only
# ever turn a live-looking owner into an absent one, never the reverse.

now=$(date +%s)
host_up=$(ps -o etimes= -p 1 2>/dev/null | tr -d ' ')
run_sh x "pw_lock_owner_alive \"\$\$-$now-$host_up-1-1\"" >/dev/null 2>&1
assert_exit "a token minted now by a running process reads alive" 0 $?
# Minted when the host booted, by a shell that started minutes ago: whatever
# else that token is, it is not this process's.
run_sh x "pw_lock_owner_alive \"\$\$-$now-0-1-1\"" >/dev/null 2>&1
assert_exit "a process that started long after the token was minted is not its owner" 1 $?

# The check degrades rather than guessing: a token that carries no mint-time
# witness says nothing about start times, so the pid alone decides, as it
# always did. That covers every token this library did not mint.
run_sh x 'pw_lock_owner_alive "$$-0-1"' >/dev/null 2>&1
assert_exit "a token with no mint-time witness falls back to the pid" 0 $?
run_sh x 'pw_lock_owner_alive "$$-1-notanumber-1-1"' >/dev/null 2>&1
assert_exit "and so does one whose witness will not parse" 0 $?

# It must not resurrect anything: an absent pid stays absent whatever the epoch.
sh -c 'exit 0' &
gone=$!
wait "$gone" 2>/dev/null
run_sh x "pw_lock_owner_alive \"$gone-$now-$host_up-1-1\"" >/dev/null 2>&1
assert_exit "an absent owner stays absent" 1 $?

# And a lock whose owner pid was recycled is breakable, which is the point.
ln -s "$$-$now-0-1-1" "$tmp/reuse.lock"
run_sh x 'pw_lock_acquire "$1/reuse.lock" 20' >/dev/null 2>&1
assert_exit "a lock naming a recycled pid can be taken" 0 $?
rm -f "$tmp"/reuse.lock*

# ---------------------------------------------------------------------------
# 37. A release that is not this caller's touches nothing at all
# ---------------------------------------------------------------------------
#
# Taking the link by renaming it makes the removal exclusive, but a rename
# VACATES the path, and a rename done before knowing whose the link was vacates
# it in the ordinary case — a hold that was already broken. Anyone may take the
# freed path in that instant, and the restore then has nowhere to put the link
# back, so the one copy of a live holder's lock is destroyed by a release that
# was never entitled to touch it.
#
# So the not-ours answer must cost no filesystem write whatsoever, and the
# observable shape of that is: nothing moves, and nothing is left lying beside
# the lock.

out="$(run_sh x '
  lockp="$1/notmine.lock"
  pw_lock_acquire "$lockp" || exit 9
  rm -f "$lockp"
  ln -s "successor-token" "$lockp"
  # A peer watching the path: if the release vacates it even for an instant,
  # this create wins and the successor is the one that loses its link.
  ( i=0; while [ "$i" -lt 400 ]; do
      ln -s "interloper" "$lockp" 2>/dev/null && exit 0
      i=$((i + 1))
    done ) &
  peer=$!
  pw_lock_release "$lockp" >/dev/null 2>&1
  printf "rc=%s\n" "$?"
  kill "$peer" 2>/dev/null
  wait "$peer" 2>/dev/null
  printf "link=%s\n" "$(command readlink "$lockp" 2>/dev/null || printf NONE)"
')"
assert_eq "a release over a lock that is not this caller's leaves it exactly alone" \
  "rc=1
link=successor-token" "$out"
leftovers="$(find "$tmp" -maxdepth 1 -name 'notmine.lock#*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "and puts nothing beside it on the way" "0" "$leftovers"
rm -f "$tmp"/notmine.lock*

# A restore that cannot land must not be followed by deleting the only copy.
# Staged by holding the path with something the restore cannot displace.
out="$(run_sh x '
  lockp="$1/keepcopy.lock"
  pw_lock_acquire "$lockp" || exit 9
  mine=$PW_LOCK_TOKEN
  flag="$1/keepcopy.fired"
  readlink() {
    # Ownership is confirmed, and the path changes hands before the take.
    if [ ! -f "$flag" ] && [ "$1" = "$lockp" ]; then
      : >"$flag"
      rm -f "$lockp"
      ln -s "successor-token" "$lockp"
      printf "%s\n" "$mine"
      return 0
    fi
    command readlink "$@"
  }
  pw_lock_release "$lockp" >/dev/null 2>&1
  printf "rc=%s\n" "$?"
  # The successor is either back at the lock path or still on disk beside it,
  # but it is never simply gone.
  if [ "$(command readlink "$lockp" 2>/dev/null)" = successor-token ]; then
    printf "successor=restored\n"
  elif command ls "$1" 2>/dev/null | grep -q "keepcopy.lock#"; then
    printf "successor=kept-aside\n"
  else
    printf "successor=DESTROYED\n"
  fi
')"
case $out in
  *successor=DESTROYED*) fail "a release destroyed the only copy of a successor's lock ($out)" ;;
  *) pass "a release that cannot put a successor back keeps it rather than deleting it" ;;
esac
rm -f "$tmp"/keepcopy.lock*

# ---------------------------------------------------------------------------
# 38. No restore anywhere deletes the copy it was holding
# ---------------------------------------------------------------------------
#
# Every place this library moves a link aside owes the same thing: if the path
# is taken again before the link can go back, the link in hand is the ONLY copy
# of a hold somebody may still be inside. Case 37 pinned that for release. The
# break has two more of these, and a rule that holds at one site and not the
# others has not landed — so the rule is asserted here against the one helper
# they all go through.

out="$(run_sh x '
  # A displaced link with the path already taken: nothing may delete it.
  ln -s "displaced-token" "$1/r.aside"
  ln -s "squatter" "$1/r.path"
  _pw_lock_restore_or_keep "$1/r.aside" "$1/r.path" >/dev/null 2>&1
  printf "rc=%s\n" "$?"
  printf "path=%s\n" "$(command readlink "$1/r.path" 2>/dev/null || printf NONE)"
  printf "kept=%s\n" "$(command readlink "$1/r.aside" 2>/dev/null || printf GONE)"
')"
assert_eq "a restore that cannot land keeps the displaced link instead of deleting it" \
  "rc=1
path=squatter
kept=displaced-token" "$out"
rm -f "$tmp"/r.aside "$tmp"/r.path

out="$(run_sh x '
  # A free path: the link goes back and the aside is cleaned up.
  ln -s "displaced-token" "$1/r2.aside"
  _pw_lock_restore_or_keep "$1/r2.aside" "$1/r2.path" >/dev/null 2>&1
  printf "rc=%s\n" "$?"
  printf "path=%s\n" "$(command readlink "$1/r2.path" 2>/dev/null || printf NONE)"
  printf "kept=%s\n" "$(command readlink "$1/r2.aside" 2>/dev/null || printf GONE)"
')"
assert_eq "a restore that can land puts it back and leaves nothing behind" \
  "rc=0
path=displaced-token
kept=GONE" "$out"
rm -f "$tmp"/r2.aside "$tmp"/r2.path

# The invariant is that every site goes through the helper, so the shape cannot
# reappear at one of them. Asserted structurally, because a race at each site
# is what this exists to make unnecessary to stage.
strays=$(grep -c 'ln -s "$_pw[a-z]*_back"' "$LIB" || true)
assert_eq "no site restores a displaced link by hand" "0" "$strays"

# ---------------------------------------------------------------------------
# 39. A process this shell may not signal exists, and is still checked
# ---------------------------------------------------------------------------
#
# EPERM means the process IS there and is not ours. Reading it as absent breaks
# a live stranger's lock; reading it as alive and stopping there lets a pid
# recycled by another user wedge the lock forever. Both come from asking "can I
# signal it" instead of "is it there, and is it the one that minted this".

now=$(date +%s)
up=$(ps -o etimes= -p 1 2>/dev/null | tr -d ' ')
run_sh x "pw_lock_owner_alive \"1-$now-$up-1-1\"" >/dev/null 2>&1
assert_exit "a process this shell cannot signal is not absent" 0 $?
# pid 1 started with the host, so no mint time can be earlier than its start
# and it can never fail the second question — which is why the delegation
# itself is asserted here rather than a verdict. Both ways of establishing
# that a process exists must ask it; a branch that answers "alive" on its own
# is the bug this pins.
existence_branches=$(grep -c '_pw_lock_owner_is_minter "\$1" "\$_pwa_pid"' "$LIB" || true)
assert_eq "every path that finds the process existing asks whether it is the minter" \
  "3" "$existence_branches"

# ---------------------------------------------------------------------------
# 40. The mint-time check reads no wall clock
# ---------------------------------------------------------------------------
#
# Its whole purpose is a rule that is never an age, so a clock that steps must
# not change its answer. Pinned by lying about the time: the verdict is taken
# with the clock as it is, then again with `date` an hour ahead and an hour
# behind, and all three must agree.

probe_alive() {
  run_sh x "date() { printf '%s\n' $2; }
    pw_lock_owner_alive \"$1\"" >/dev/null 2>&1
  printf '%s' "$?"
}
up=$(ps -o etimes= -p 1 2>/dev/null | tr -d ' ')
live_tok="$$-$(date +%s)-$up-1-1"
a=$(probe_alive "$live_tok" "$(date +%s)")
b=$(probe_alive "$live_tok" "$(($(date +%s) + 3600))")
c=$(probe_alive "$live_tok" "$(($(date +%s) - 3600))")
assert_eq "a stepped clock does not change a live owner's verdict" "$a$a" "$b$c"
assert_eq "and that verdict is alive" "0" "$a"

# ---------------------------------------------------------------------------
# 41. A token never becomes part of a path unslugged
# ---------------------------------------------------------------------------
#
# A lock's target is whatever a writer put there, and the release verbs take a
# token from a caller that read one — `orchestrate-lock` hands over what it got
# from `readlink`. Those tokens are built into the working paths this library
# renames and removes, so a target carrying `../` reaches `mv` and `rm -f`
# pointed somewhere else entirely. The break already slugs its claim path; the
# rest must too, and the rule is asserted against the one builder they share.

# The chain as a caller actually walks it: a planted lock, its target read back
# with `readlink`, and that same target handed to the release as the token —
# which is exactly what the sweep does. The token then matches, every ownership
# check passes, and the traversal is inside the working path.
mkdir -p "$tmp/victimdir"
: >"$tmp/victimdir/precious"
ln -s "../victimdir/precious" "$tmp/trav.lock"
run_sh x 'pw_lock_release_token "$1/trav.lock" "$(command readlink "$1/trav.lock")"' >/dev/null 2>&1
if [ -f "$tmp/victimdir/precious" ]; then
  pass "a token full of traversal never reaches a path outside the lock's directory"
else
  fail "a token full of traversal never reaches a path outside the lock's directory"
fi

out="$(run_sh x '
  _pw_lock_work_path "$1/w.lock" taken "../../etc/passwd"
  printf "%s\n" "$_pw_lock_work_path_out"
')"
# The property is that the token contributes a NAME, never a path: whatever it
# carried, the result sits in the same directory as the lock.
if [ "$(dirname "$out")" = "$tmp" ] && [ -n "$out" ]; then
  pass "a derived working path stays beside the lock it belongs to"
else
  fail "a derived working path left the lock's directory ($out)"
fi
# A traversal needs a SEPARATOR; `..` among other characters is just a name.
# What must not survive is any `/`, and the name must not itself be a directory
# reference — which the caller-unique suffix also guarantees.
wp_name=$(basename "$out")
case $wp_name in
  */* | . | ..) fail "a derived working path's name can still traverse ($wp_name)" ;;
  *) pass "and its name is a name, not a path" ;;
esac
rm -rf "$tmp"/trav.lock* "$tmp/victimdir" "$tmp"/w.lock*

# ---------------------------------------------------------------------------
# 42. Two callers doing the same work do not share the workspace
# ---------------------------------------------------------------------------
#
# The break's claim path is shared ON PURPOSE — it IS the serialization point,
# one claim per dead owner. Every other derived path is one caller's private
# scratch, and two releasers of the same lock holding the same token would
# otherwise race on the same aside and delete each other's displaced link
# mid-release, each then reporting a failure that did not happen.

a=$(run_sh x '_pw_lock_work_path "$1/s.lock" taken "sametoken"; printf "%s\n" "$_pw_lock_work_path_out"')
b=$(run_sh x '_pw_lock_work_path "$1/s.lock" taken "sametoken"; printf "%s\n" "$_pw_lock_work_path_out"')
if [ -n "$a" ] && [ "$a" != "$b" ]; then
  pass "two callers deriving the same kind of working path get different ones"
else
  fail "two callers deriving the same kind of working path collide (both '$a')"
fi
# Twice within one caller, too: a release that displaces a link and a break that
# follows it in the same shell must not reuse one scratch name.
c1=$(run_sh x '_pw_lock_work_path "$1/s.lock" taken "t"; printf "%s\n" "$_pw_lock_work_path_out"
  _pw_lock_work_path "$1/s.lock" taken "t"; printf "%s\n" "$_pw_lock_work_path_out"' | sed -n 1p)
c2=$(run_sh x '_pw_lock_work_path "$1/s.lock" taken "t"; printf "%s\n" "$_pw_lock_work_path_out"
  _pw_lock_work_path "$1/s.lock" taken "t"; printf "%s\n" "$_pw_lock_work_path_out"' | sed -n 2p)
if [ -n "$c1" ] && [ "$c1" != "$c2" ]; then
  pass "and so do two derivations within one caller"
else
  fail "and so do two derivations within one caller (both '$c1')"
fi
rm -f "$tmp"/s.lock*

# ---------------------------------------------------------------------------
# 43. The spin loop does not fork for the host's uptime
# ---------------------------------------------------------------------------
#
# The waiter strides its holder probe precisely so contention does not cost a
# process per spin. Minting a token reads the host's uptime, and a host boots
# once, so reading it on every spin puts back the fork the stride removed.
# Count the `ps` invocations a bounded spin makes against a live holder.

mkdir -p "$tmp/shim"
cat >"$tmp/shim/ps" <<'SHIM'
#!/bin/sh
echo x >>"$PS_COUNT"
exec /bin/ps "$@"
SHIM
chmod +x "$tmp/shim/ps"
sh -c 'sleep 30 & echo $!' >"$tmp/holder.pid"
holder=$(cat "$tmp/holder.pid")
# A token the minter check accepts, or the first probe reads the holder as a
# recycled pid, breaks the lock, and the wait never spins at all.
up=$(ps -o etimes= -p 1 | tr -d ' ')
ln -s "$holder-$(date +%s)-$up-$holder-1" "$tmp/spin.lock"
: >"$tmp/pscount"
PS_COUNT="$tmp/pscount" PATH="$tmp/shim:$PATH" \
  run_sh x 'pw_lock_acquire "$1/spin.lock" 120' >/dev/null 2>&1
spins=$(grep -c '' "$tmp/pscount" 2>/dev/null || echo 0)
# The stride allows a probe every PW_LOCK_PROBE_EVERY spins, each of which may
# read `ps` twice for the liveness verdict. A per-spin mint blows past that by
# an order of magnitude.
if [ "$spins" -le 20 ]; then
  pass "a 120-spin wait forks ps $spins time(s), not once per spin"
else
  fail "a 120-spin wait forked ps $spins times — the uptime read is inside the loop"
fi
kill "$holder" 2>/dev/null || :
rm -f "$tmp"/spin.lock* "$tmp/pscount"

# ---------------------------------------------------------------------------
# 44. Nothing this library hands a tool can be read as options
# ---------------------------------------------------------------------------
#
# Two halves of one rule. A lock path that begins with a dash is refused at the
# gate, which covers every derived path too, since each is that path plus a
# suffix — without it the tools read the dash as options and the lock silently
# never works, with the diagnostics blaming contention. A link TARGET is
# whatever a writer put there and no gate can constrain it, so the create takes
# `--` and a dash-leading target is stored and read back intact.

dashdir="$tmp/dash"
mkdir -p "$dashdir"
out=$(cd "$dashdir" && $SH -c '. "$1"; pw_lock_acquire "-dash.lock" 5' sh "$LIB" 2>&1)
rc=$?
assert_exit "a lock path beginning with a dash is refused" 2 $rc
case $out in
  *"beginning with '-'"*) pass "and the refusal says why" ;;
  *) fail "and the refusal says why (got '$out')" ;;
esac
if [ -e "$dashdir/-dash.lock" ] || [ -L "$dashdir/-dash.lock" ]; then
  fail "the refused path was written to anyway"
else
  pass "and nothing was written at the refused path"
fi
# Every verb, not just the one: a gate one entry point skips is not a gate.
for verb in pw_lock_try pw_lock_acquire pw_lock_try_detached \
  pw_lock_acquire_detached pw_lock_release pw_lock_break_force pw_lock_clear_legacy; do
  (cd "$dashdir" && $SH -c ". \"\$1\"; $verb \"-dash.lock\"" sh "$LIB" >/dev/null 2>&1)
  if [ $? -eq 2 ]; then
    pass "$verb refuses it too"
  else
    fail "$verb accepted a dash-leading lock path"
  fi
done
rm -rf "$dashdir"
# A target beginning with a dash survives the create and comes back whole.
ln -s -- "-not-an-option" "$tmp/target.lock" 2>/dev/null
got=$(run_sh x 'pw_lock_owner "$1/target.lock"')
assert_eq "a dash-leading link target is read back intact" "-not-an-option" "$got"
rm -f "$tmp"/target.lock*

# ---------------------------------------------------------------------------
# 45. A detached hold outlives the shell that took it
# ---------------------------------------------------------------------------
#
# A detached hold exists precisely to span invocations: a CLI acquires in one
# and releases in a later one. If it sits in this shell's release registry, the
# armed EXIT trap unlinks it the moment that CLI exits, which is the one thing
# the hold is for.

run_sh x 'pw_lock_trap_install; pw_lock_acquire_detached "$1/spanning.lock" 5' >/dev/null 2>&1
rc=$?
assert_exit "a detached acquire under an armed trap succeeds" 0 $rc
if [ -L "$tmp/spanning.lock" ]; then
  pass "and the hold survives the shell that took it"
else
  fail "the exit trap released a detached hold, which is what detached means not to do"
fi
rm -f "$tmp"/spanning.lock*
run_sh x 'pw_lock_trap_install; pw_lock_try_detached "$1/spanning2.lock"' >/dev/null 2>&1
if [ -L "$tmp/spanning2.lock" ]; then
  pass "the same for the non-spinning form"
else
  fail "the exit trap released a detached hold taken by pw_lock_try_detached"
fi
rm -f "$tmp"/spanning2.lock*

# ---------------------------------------------------------------------------
# 46. The mint-time witness survives a `ps` that has no `etimes`
# ---------------------------------------------------------------------------
#
# `etimes` is a procps extension. The BSD `ps` macOS ships answers `etime`
# instead, in `[[dd-]hh:]mm:ss`, and a library that asks only for `etimes`
# there gets nothing back — no mint-time witness in any token, and the
# recycled-pid check silently degraded to pid-only on a platform in the support
# bar. Shim a `ps` that behaves the BSD way and check the witness is still
# there and still a number.

mkdir -p "$tmp/bsd"
cat >"$tmp/bsd/ps" <<'SHIM'
#!/bin/sh
for a in "$@"; do
  case $a in
    etimes=) exit 1 ;;
  esac
done
exec /bin/ps "$@"
SHIM
chmod +x "$tmp/bsd/ps"
tok=$(PATH="$tmp/bsd:$PATH" run_sh x 'pw_lock_acquire "$1/bsd.lock" 5 >/dev/null && pw_lock_owner "$1/bsd.lock"')
# Field 3 is the uptime at mint.
f3=${tok#*-}
f3=${f3#*-}
f3=${f3%%-*}
case $f3 in
  '' | *[!0-9]*) fail "with a BSD-shaped ps the token carries no mint-time witness (token '$tok')" ;;
  *) pass "a BSD-shaped ps still yields a numeric mint-time witness" ;;
esac
# And it is the same quantity, not a differently-scaled one: both spellings
# describe pid 1, so they must agree within the slack the check already allows.
real=$(ps -o etimes= -p 1 | tr -d ' ')
if [ "$((f3 - real))" -le 5 ] && [ "$((real - f3))" -le 5 ]; then
  pass "and it agrees with the seconds the other spelling reports"
else
  fail "the etime fallback disagrees with etimes ($f3 vs $real)"
fi
rm -f "$tmp"/bsd.lock*
rm -rf "$tmp/bsd"

# ---------------------------------------------------------------------------
# 47. Two sibling subshells releasing one hold cannot destroy each other's work
# ---------------------------------------------------------------------------
#
# A subshell inherits `$$`, the sequence counter and the hold registry, so two
# of them derive the SAME working path for the same lock. What keeps that from
# mattering is the ordering: the working path is derived only AFTER the caller
# has confirmed the link is still its own, and only one caller can pass that
# check and then move the link. Pin the ordering here, because it is the only
# reason the shared name is harmless.

run_sh x 'pw_lock_acquire "$1/sib.lock" 50 >/dev/null || exit 1
  ( pw_lock_release "$1/sib.lock"; echo "a $?" ) &
  ( pw_lock_release "$1/sib.lock"; echo "b $?" ) &
  wait' >"$tmp/sib.out" 2>"$tmp/sib.err"
zero=$(grep -c ' 0$' "$tmp/sib.out" 2>/dev/null || echo 0)
assert_eq "exactly one of two sibling subshells releases the hold" "1" "$zero"
if [ -L "$tmp/sib.lock" ] || [ -e "$tmp/sib.lock" ]; then
  fail "the lock outlived a release by a subshell"
else
  pass "and the lock is gone afterwards"
fi
strays=$(find "$tmp" -maxdepth 1 -name 'sib.lock#*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no working path is left behind by either" "0" "$strays"
if [ -s "$tmp/sib.err" ]; then
  fail "the losing subshell printed a diagnostic: $(cat "$tmp/sib.err")"
else
  pass "and the loser says nothing, because nothing went wrong"
fi
rm -f "$tmp"/sib.lock* "$tmp/sib.out" "$tmp/sib.err"

# ---------------------------------------------------------------------------
# 48. Every create in this library is confirmed before it is believed
# ---------------------------------------------------------------------------
#
# `ln -s target dir` files the link INSIDE a directory squatting the path and
# still exits 0. The publish guards that; the restore did not, so a directory
# on the lock path made the restore report success, file the link inside it,
# and then delete the aside — destroying the only copy, in the function whose
# whole job is to never do that.

mkdir -p "$tmp/sq.lock"
ln -s "displaced-token" "$tmp/sq.aside"
run_sh x '_pw_lock_restore_or_keep "$1/sq.aside" "$1/sq.lock"' >/dev/null 2>"$tmp/sq.err"
rc=$?
assert_exit "a restore onto a squatting directory reports failure" 1 $rc
if [ -L "$tmp/sq.aside" ]; then
  pass "and the displaced link is kept, not deleted"
else
  fail "the restore deleted the only copy of the displaced link"
fi
inside=$(find "$tmp/sq.lock" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
assert_eq "and nothing is filed inside the directory" "0" "$inside"
rm -rf "$tmp/sq.lock" "$tmp/sq.aside" "$tmp/sq.err"
# The same hazard at the publish, which is where it was first handled: a
# directory on the path is not a hold.
mkdir -p "$tmp/sq2.lock"
run_sh x 'pw_lock_try "$1/sq2.lock"' >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "a directory on the lock path is never reported as a hold"
else
  fail "a directory on the lock path was reported as a hold"
fi
inside=$(find "$tmp/sq2.lock" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
assert_eq "and the publish leaves nothing inside it" "0" "$inside"
rm -rf "$tmp/sq2.lock"

# ---------------------------------------------------------------------------
# 49. The claim sweep does not depend on the caller's IFS
# ---------------------------------------------------------------------------
#
# This library is SOURCED, so it runs with whatever field separator its caller
# set. A restore-the-globbing-state step written as an unquoted variable is
# split by that IFS: under a caller that changed it the command is not found,
# and the shell is left with globbing disabled for good.

# Globbing OFF is the state that shows it: the sweep turns globbing on to
# expand its own patterns, and a restore step the caller's IFS mangles never
# turns it back.
ln -s "dead-token" "$tmp/ifs.lock#break#x"
out=$(run_sh x 'set -f
  IFS=:
  pw_lock_break_force "$1/ifs.lock" >/dev/null 2>&1
  case $- in *f*) printf "globbing-off\n" ;; *) printf "globbing-on\n" ;; esac' 2>/dev/null)
assert_eq "a caller with a non-standard IFS gets its globbing state back" "globbing-off" "$out"
if [ -e "$tmp/ifs.lock#break#x" ] || [ -L "$tmp/ifs.lock#break#x" ]; then
  fail "the sweep did not run under a non-standard IFS"
else
  pass "and the sweep still cleared the claim"
fi
rm -f "$tmp"/ifs.lock*
# Nothing is printed on the way, either: a command the caller never wrote
# failing is a diagnostic the caller cannot act on.
err=$(run_sh x 'set -f
  IFS=:
  pw_lock_break_force "$1/ifs2.lock" >/dev/null' 2>&1)
case $err in
  *'set -f'* | *'set +f'* | *'not found'*)
    fail "the restore step ran as a command under the caller's IFS: $err"
    ;;
  *) pass "and nothing complains about a command the caller never wrote" ;;
esac
rm -f "$tmp"/ifs2.lock*
# The ordinary caller is unchanged: globbing on stays on.
out=$(run_sh x 'pw_lock_break_force "$1/ifs3.lock" >/dev/null 2>&1
  case $- in *f*) printf "globbing-off\n" ;; *) printf "globbing-on\n" ;; esac' 2>/dev/null)
assert_eq "a caller that had globbing on keeps it on" "globbing-on" "$out"
rm -f "$tmp"/ifs3.lock*

# ---------------------------------------------------------------------------
# 50. The single-site rules the library states about itself are true of it
# ---------------------------------------------------------------------------
#
# Four times now a hazard has been handled in one function and omitted in a
# sibling that had the same hazard. The answer each time was to give the rule
# one owner, which only helps for as long as nothing grows a second call site —
# and a comment claiming to be the only place is exactly the claim that rots
# quietly. Read the source and count.

lnsites=$(grep -cE '^[^#]*(^|[^[:alnum:]_])ln ' "$LIB" || :)
assert_eq "only one place in the library runs ln" "1" "$lnsites"
etimesites=$(grep -cE '^[^#]*(^|[^[:alnum:]_])ps -o etime' "$LIB" || :)
assert_eq "only one function reads an elapsed time" "2" "$etimesites"
# The disown rule has one owner too, and the way that stays true is that every
# verb whose owner is not this shell reaches the lock through it.
for v in pw_lock_try_detached pw_lock_acquire_detached pw_lock_acquire_for; do
  body=$(sed -n "/^$v() {/,/^}/p" "$LIB")
  case $body in
    *_pw_lock_take_disowned*) pass "$v takes its hold through the disown verb" ;;
    *) fail "$v reaches the lock without going through _pw_lock_take_disowned" ;;
  esac
done

# ---------------------------------------------------------------------------
# 51. Every zero-padded field of a BSD elapsed time is read as decimal
# ---------------------------------------------------------------------------
#
# `ps -o etime=` pads hours, minutes and seconds to two digits and leaves days
# unpadded, so `08:09:05` is the ordinary shape for ten hours of every day.
# Dash reads a leading zero as octal and REFUSES `08` outright, which would
# take the mint-time witness out of every token minted in that window. The
# days branch alone does not exercise this — its field is the one that is never
# padded.

mkdir -p "$tmp/etshim"
cat >"$tmp/etshim/ps" <<'SHIM'
#!/bin/sh
for a in "$@"; do
  case $a in
    etimes=) exit 1 ;;
  esac
done
printf '%s\n' "$FAKE_ETIME"
SHIM
chmod +x "$tmp/etshim/ps"
# shape                expected seconds
set -- \
  '08:09:05' 29345 \
  '00:00:07' 7 \
  '09:05' 545 \
  '2-08:09:05' 202145 \
  '08-08:08:08' 720488 \
  '10-00:00:00' 864000
while [ "$#" -ge 2 ]; do
  got=$(PATH="$tmp/etshim:$PATH" FAKE_ETIME="$1" \
    $SH -c '. "$1"; _pw_lock_etimes 1; printf "%s" "$_pw_lock_etimes_out"' sh "$LIB" 2>&1)
  assert_eq "an elapsed time of $1 reads as $2 seconds" "$2" "$got"
  shift 2
done
rm -rf "$tmp/etshim"

# ---------------------------------------------------------------------------
# 52. A derived working path is handed out only when nothing occupies it
# ---------------------------------------------------------------------------
#
# `mv src dir` files the source INSIDE the directory and exits 0, so a
# directory sitting on a `#taken#` path turns the displacement step into a
# silent vacate: the live lock ends up inside it, the restore cannot find a
# link to put back, and the path is left unlocked. Nothing here needs an
# attacker — a leftover from a killed run is the same shape.

# Both derivations have to happen in ONE shell: the path carries the deriving
# shell's pid, so two invocations differ for a reason that has nothing to do
# with what is being tested.
out=$(run_sh x 'PW_LOCK_SEQ=0
  _pw_lock_work_path "$1/wp.lock" taken tok
  first=$_pw_lock_work_path_out
  mkdir -p "$first"
  PW_LOCK_SEQ=0
  _pw_lock_work_path "$1/wp.lock" taken tok
  printf "%s\n%s\n" "$first" "$_pw_lock_work_path_out"')
first=$(printf '%s\n' "$out" | sed -n 1p)
again=$(printf '%s\n' "$out" | sed -n 2p)
if [ -n "$again" ] && [ "$again" != "$first" ]; then
  pass "a derived path that is occupied is skipped for a free one"
else
  fail "the derivation handed back an occupied path ('$again')"
fi
rm -rf "$first"
# End to end, in one shell for the same reason: with a directory sitting on the
# path the release would have used, the release still releases and the lock is
# not filed inside it.
trap_path=$(run_sh x 'PW_LOCK_SEQ=0
  pw_lock_try "$1/wp2.lock" >/dev/null || exit 1
  PW_LOCK_SEQ=0
  _pw_lock_work_path "$1/wp2.lock" taken "$PW_LOCK_TOKEN"
  mkdir -p "$_pw_lock_work_path_out"
  printf "%s\n" "$_pw_lock_work_path_out"
  PW_LOCK_SEQ=0
  pw_lock_release "$1/wp2.lock" || exit 3' 2>/dev/null)
rc=$?
assert_exit "a release past an occupied working path still releases" 0 $rc
if [ -L "$tmp/wp2.lock" ] || [ -e "$tmp/wp2.lock" ]; then
  fail "the lock survived the release"
else
  pass "and the lock is gone, not filed inside the directory"
fi
inside=$(find "$trap_path" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
assert_eq "and nothing was filed inside the occupying directory" "0" "$inside"
rm -rf "$trap_path"
rm -f "$tmp"/wp2.lock*

if [ "$failures" -eq 0 ]; then
  echo "All lock-lib tests passed."
else
  echo "$failures lock-lib test(s) failed." >&2
fi
exit $((failures > 0))
