#!/bin/bash
# Tests for scripts/bounded-run.sh, timeout(1)'s contract for hosts that ship
# neither timeout nor gtimeout (stock macOS), which the guards fall back to.
#
# What is covered:
#   - a command inside its bound returns its own status and output;
#   - the bound is the full number of seconds, never cut short, and the
#     caller's stdin reaches the command;
#   - an overrun is ended within the bound and reads 124, and the bound takes
#     the command's whole process tree, so a grandchild holding the output
#     pipe cannot keep a command substitution waiting;
#   - -k: a command and its children that ignore TERM are killed after the
#     grace;
#   - a malformed bound (leading zeros included) or a missing command is a
#     usage error (125), and 0 runs the command unbounded;
#   - a runner that is itself terminated takes its command's tree with it.
#
# Runs standalone under /bin/bash (the bash 3.2 floor), and drives the runner
# under /bin/sh, as the guards do:
#   ./tests/test-bounded-run.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
BR="$here/../scripts/bounded-run.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -r "$BR" ] || fail "scripts/bounded-run.sh is missing"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-bounded-run.XXXXXX") || fail "mktemp -d failed"
trap 'rm -rf "$tmp"' EXIT

br() {
  /bin/sh "$BR" "$@"
}

# alive <pid> — true while the pid names a live, non-zombie process.
alive() {
  kill -0 "$1" 2>/dev/null || return 1
  case $(ps -o stat= -p "$1" 2>/dev/null || awk '{ sub(/.*\) /, ""); print $1 }' "/proc/$1/stat" 2>/dev/null) in
    Z*) return 1 ;;
  esac
  return 0
}

# --- inside the bound: the command's own answer ------------------------------

out=$(br 5 /bin/sh -c 'printf "%s\n" hello; exit 3') && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "in bound: exit $rc, expected the command's own 3"
[ "$out" = hello ] || fail "in bound: output '$out', expected 'hello'"
rc=0
br -k 1 5 true || rc=$?
[ "$rc" = 0 ] || fail "in bound with -k: exit $rc, expected 0"
echo "ok: a command inside its bound returns its own status and output"

# The bound is not cut short by where in a second the run started.
for _ in 1 2 3 4 5; do
  rc=0
  br 2 sleep 1.3 || rc=$?
  [ "$rc" = 0 ] || fail "full bound: a 1.3s command under a 2s bound exited $rc"
done
out=$(printf 'from stdin\n' | br 5 cat)
[ "$out" = 'from stdin' ] || fail "stdin: the command read '$out', not the caller's stdin"
rm -f "$tmp/ran"
# shellcheck disable=SC2016 # expanded by the inner shell
br 5 /bin/sh -c ': >"$1/ran"' _ "$tmp" <&- || :
[ -e "$tmp/ran" ] || fail "closed stdin: the runner failed rather than running the command"
echo "ok: the bound is the full number of seconds and the caller's stdin reaches the command"

# watcher_sleeps <bound> — how many watcher sleeps of that bound are running.
# Each bound below is unique to this run, so a concurrent run's watchers are
# never counted as this one's leaks.
watcher_sleeps() {
  # shellcheck disable=SC2009 # pgrep is not on every host the suite runs on
  ps -A -o args= 2>/dev/null | grep -c "^sleep $1\$" || :
}
bound=$((100000 + $$ % 800000))
# A ps that fails or cannot see args would count no leaks at all.
sleep "$bound" &
probe=$!
i=0
while [ "$(watcher_sleeps "$bound")" != 1 ] && [ "$i" -lt 20 ]; do
  sleep 0.1
  i=$((i + 1))
done
seen=$(watcher_sleeps "$bound")
kill "$probe"
wait "$probe" 2>/dev/null || :
[ "$seen" = 1 ] || fail "prompt return: ps does not show a running sleep of the bound, so a leak would go uncounted"

# A command that ends at once ends the call at once, and the watcher leaves no
# sleep behind. The watcher can be still forking its sleep when the command
# ends, a window load widens, so a few lanes of calls run side by side too.
start=$(date +%s)
for _ in 1 2 3 4 5 6 7 8; do
  br "$bound" true || fail "prompt return: a ${bound}s-bounded true failed"
done
took=$(($(date +%s) - start))
[ "$took" -le 6 ] || fail "prompt return: eight instant commands took ${took}s"
lanes=''
for _ in 1 2 3 4; do
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    br "$bound" true || exit 1
  done &
  lanes="$lanes $!"
done
for lane in $lanes; do
  wait "$lane" || fail "prompt return: a ${bound}s-bounded true failed in a lane"
done
# A KILLed sleep is gone within moments; a leaked one lives the whole bound.
i=0
while left=$(watcher_sleeps "$bound") && [ "$left" != 0 ] && [ "$i" -lt 20 ]; do
  sleep 0.1
  i=$((i + 1))
done
[ "$left" = 0 ] || fail "prompt return: $left watcher sleep(s) outlived their runner"
echo "ok: a command that ends at once ends the call, and no watcher sleep is left"

# --- an overrun: 124, promptly, the whole group ---------------------------------

start=$(date +%s)
rc=0
# shellcheck disable=SC2016 # expanded by the inner shell
out=$(br 1 /bin/sh -c 'sleep 30 & echo "$!" >"$1/grandchild"; wait' _ "$tmp") || rc=$?
took=$(($(date +%s) - start))
[ "$rc" = 124 ] || fail "overrun: exit $rc, expected 124"
[ "$took" -le 6 ] || fail "overrun: took ${took}s past a 1s bound (a grandchild held the output?)"
gc=$(cat "$tmp/grandchild")
i=0
while alive "$gc" && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
! alive "$gc" || fail "overrun: the grandchild $gc outlived the bound"
echo "ok: an overrun reads 124 within the bound and the bound takes the command's tree"

# --- -k: a command that ignores TERM ----------------------------------------------

start=$(date +%s)
rc=0
# shellcheck disable=SC2016 # expanded by the inner shell
br -k 1 1 /bin/sh -c 'trap "" TERM; sleep 30 & echo "$!" >"$1/stubborn"; wait; sleep 30' _ "$tmp" || rc=$?
took=$(($(date +%s) - start))
[ "$rc" = 124 ] || fail "TERM-ignoring overrun: exit $rc, expected 124"
[ "$took" -le 8 ] || fail "TERM-ignoring overrun: took ${took}s with a 1s grace"
st=$(cat "$tmp/stubborn")
i=0
while alive "$st" && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
! alive "$st" || fail "TERM-ignoring overrun: its TERM-ignoring child $st outlived the grace"
# A command that dies on TERM inside the grace still has its TERM-ignoring
# child killed once the grace is spent, and the call does not wait on it.
start=$(date +%s)
rc=0
# shellcheck disable=SC2016 # expanded by the inner shell
out=$(br -k 1 1 /bin/sh -c '/bin/sh -c "trap \"\" TERM; exec sleep 30" & echo "$!" >"$1/orphan"; sleep 30' _ "$tmp") || rc=$?
took=$(($(date +%s) - start))
[ "$rc" = 124 ] || fail "TERM-dying overrun: exit $rc, expected 124"
[ "$took" -le 8 ] || fail "TERM-dying overrun: took ${took}s, its TERM-ignoring child held the call"
orph=$(cat "$tmp/orphan")
i=0
while alive "$orph" && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
! alive "$orph" || fail "TERM-dying overrun: its TERM-ignoring child $orph outlived the grace"
echo "ok: -k kills a command that ignores TERM once the grace is spent"

# --- usage ----------------------------------------------------------------------

for args in '' 'x true' '-1 true' '1.5 true' '08 true' '010 true' '5' '-k x 5 true' '-k 01 5 true' '-k' '-k 1 5'; do
  rc=0
  # shellcheck disable=SC2086 # each case is meant to word-split
  br $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 125 ] || fail "usage '$args': exit $rc, expected 125"
done
rc=0
br 0 /bin/sh -c 'exit 7' || rc=$?
[ "$rc" = 7 ] || fail "a 0 bound: exit $rc, expected the command's own 7 (0 means unbounded)"
start=$(date +%s)
rc=0
br -k 0 1 /bin/sh -c 'trap "" TERM; sleep 3' || rc=$?
took=$(($(date +%s) - start))
[ "$rc" = 124 ] && [ "$took" -ge 2 ] || fail "a 0 grace: exit $rc after ${took}s, expected 124 with no KILL"
echo "ok: a malformed bound or a missing command is a usage error (125), a 0 bound is unbounded and a 0 grace sends no KILL"

# --- a terminated runner takes its command with it ------------------------------

# shellcheck disable=SC2016 # expanded by the inner shell
/bin/sh "$BR" -k 1 "$bound" /bin/sh -c 'echo "$$" >"$1/cmd"; trap "" TERM; sleep 30 & echo "$!" >"$1/cmdchild"; wait' _ "$tmp" &
runner=$!
i=0
while [ ! -s "$tmp/cmdchild" ] && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
[ -s "$tmp/cmdchild" ] || fail "terminated runner: the command never started"
cmd=$(cat "$tmp/cmd")
kill -TERM "$runner"
wait "$runner" 2>/dev/null || :
i=0
while alive "$cmd" && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
! alive "$cmd" || fail "terminated runner: its command $cmd outlived it"
cc=$(cat "$tmp/cmdchild")
i=0
while alive "$cc" && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done
! alive "$cc" || fail "terminated runner: its command's child $cc outlived it"
i=0
while left=$(watcher_sleeps "$bound") && [ "$left" != 0 ] && [ "$i" -lt 20 ]; do
  sleep 0.1
  i=$((i + 1))
done
[ "$left" = 0 ] || fail "terminated runner: $left watcher sleep(s) outlived it"
echo "ok: a runner that is terminated ends its command's tree, TERM-ignoring included, and its watcher's sleep"

echo "all bounded-run tests passed"
