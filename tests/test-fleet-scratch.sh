#!/bin/bash
# Tests for scripts/fleet-scratch.sh, which places and records the short
# scratch roots fleet workers get as their TMPDIR, and for the final close's
# use of it (scripts/fleet-stop-lib.sh, stop_scratch_root_release): each
# verb's refusals, and that nothing outside a recorded root is ever removed.
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
FS="$REPO_ROOT/scripts/fleet-scratch.sh"

failures=0
passes=0
pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

T=$(mktemp -d) || exit 1
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
HOME_F=$T/fleet
BASE=$T/base
mkdir -p "$HOME_F"
mkdir -m 700 "$BASE"
export PLANWRIGHT_FLEET_SCRATCH_BASE=$BASE

hex40() {
  local s=''
  for _ in $(seq 40); do s=$s$1; done
  printf '%s' "$s"
}
WK=$(hex40 a)
SK=$WK-$(hex40 b)

# run <args...>: run the script, leaving its stdout in OUT and status in RC.
run() {
  OUT=$(/bin/sh "$FS" "$@" 2>"$T/err")
  RC=$?
}

echo "### usage"
for args in "make" "make $HOME_F" "bogus $HOME_F $WK" "make $HOME_F $WK --stale" "make $HOME_F $WK --fresh extra" \
  "make relative $WK" "make $HOME_F not-a-key" "make $HOME_F ${WK}x" "reclaim $HOME_F $SK" "kind $HOME_F"; do
  # shellcheck disable=SC2086 # the words are separate arguments on purpose
  run $args
  if [ "$RC" -eq 2 ]; then
    pass "usage: '$args' is refused with exit 2"
  else
    fail "usage: '$args' exited $RC"
  fi
done

echo "### make"
run make "$HOME_F" "$WK"
root=$OUT
if [ "$RC" -eq 0 ] && [ "${root%/*}" = "$BASE" ] && [ -d "$root" ] \
  && [ "$(cat "$HOME_F/scratch/$WK.tmpdir")" = "$root" ]; then
  pass "make: the root lies under the base and the fleet home records it"
else
  fail "make: rc=$RC root='$root' $(cat "$T/err")"
fi
run make "$HOME_F" "$SK"
if [ "$RC" -eq 0 ] && [ "$OUT" != "$root" ] && [ "${OUT%/*}" = "$BASE" ]; then
  pass "make: a session's root is its own, beside the worktree's"
else
  fail "make: session root '$OUT' (worktree's $root)"
fi
for bad in relative "$T/missing"; do
  PLANWRIGHT_FLEET_SCRATCH_BASE=$bad run make "$HOME_F" "$WK"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && grep -q 'PLANWRIGHT_FLEET_SCRATCH_BASE' "$T/err"; then
    pass "make: the base '$bad' is refused with a reason"
  else
    fail "make: the base '$bad' (rc=$RC, '$OUT')"
  fi
done
mkdir -m 777 "$T/open"
chmod 777 "$T/open"
PLANWRIGHT_FLEET_SCRATCH_BASE=$T/open run make "$HOME_F" "$WK"
if [ "$RC" -eq 1 ] && [ -z "$(ls -A "$T/open")" ]; then
  pass "make: a base others may write is refused, nothing created in it"
else
  fail "make: an open base (rc=$RC, $(ls -A "$T/open"))"
fi
mkdir -m 700 "$HOME_F/inner"
PLANWRIGHT_FLEET_SCRATCH_BASE=$HOME_F/inner run make "$HOME_F" "$WK"
if [ "$RC" -eq 1 ] && [ -z "$(ls -A "$HOME_F/inner")" ]; then
  pass "make: a base inside the fleet home is refused before anything is created"
else
  fail "make: a base inside the fleet home (rc=$RC, $(ls -A "$HOME_F/inner"))"
fi
WK2=$(hex40 c)
mkdir -p "$T/out"
ln -s "$T/out" "$HOME_F/scratch/$WK2.tmpdir"
run make "$HOME_F" "$WK2"
if [ "$RC" -eq 1 ] && [ -z "$(ls -A "$T/out")" ]; then
  pass "make: a record that is a symlink is refused, nothing written through it"
else
  fail "make: a linked record (rc=$RC, $(ls -A "$T/out"))"
fi
rm -f "$HOME_F/scratch/$WK2.tmpdir"
mkdir -m 700 "$T/notours"
: >"$T/notours/keep"
printf '%s\n' "$T/notours" >"$HOME_F/scratch/$WK2.tmpdir"
run make "$HOME_F" "$WK2"
if [ "$RC" -eq 0 ] && [ "${OUT%/*}" = "$BASE" ] && [ -f "$T/notours/keep" ]; then
  pass "make: a record naming a directory of another shape is replaced by the derived root"
else
  fail "make: a tampered record (rc=$RC, '$OUT')"
fi
printf '%s\n' "$T/notours" >"$HOME_F/scratch/$WK2.tmpdir"
run release "$HOME_F" "$T/notours"
if [ "$RC" -eq 1 ] && [ -f "$T/notours/keep" ] && [ -f "$HOME_F/scratch/$WK2.tmpdir" ]; then
  pass "release: a recorded directory of another shape is refused, record kept"
else
  fail "release: a tampered record (rc=$RC)"
fi
rm -f "$HOME_F/scratch/$WK2.tmpdir"

echo "### --fresh and the earlier layout"
: >"$root/old"
run make "$HOME_F" "$WK" --fresh
if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ] && [ -z "$(ls -A "$root")" ]; then
  pass "--fresh: the recorded root comes back empty"
else
  fail "--fresh: rc=$RC '$OUT' $(ls -A "$root" 2>&1)"
fi
WK3=$(hex40 d)
SK3=$WK3-$(hex40 e)
mkdir -p "$T/elsewhere/$(hex40 e)/precious"
ln -s "$T/elsewhere" "$HOME_F/scratch/$WK3"
run make "$HOME_F" "$SK3" --fresh
if [ "$RC" -eq 1 ] && [ -d "$T/elsewhere/$(hex40 e)/precious" ]; then
  pass "--fresh: a session's earlier-layout root under a linked worktree root is refused, nothing removed"
else
  fail "--fresh: a linked earlier-layout worktree root (rc=$RC)"
fi
rm -f "$HOME_F/scratch/$WK3"
mkdir -p "$HOME_F/scratch/$WK3/$(hex40 e)/f"
run make "$HOME_F" "$SK3" --fresh
if [ "$RC" -eq 0 ] && [ ! -e "$HOME_F/scratch/$WK3/$(hex40 e)" ] && [ -d "$HOME_F/scratch/$WK3" ]; then
  pass "--fresh: a session's earlier-layout root goes, its worktree's root stays"
else
  fail "--fresh: earlier-layout session root (rc=$RC)"
fi

echo "### kind, release, reclaim"
run make "$HOME_F" "$SK"
sroot=$OUT
run kind "$HOME_F" "$root"
k1=$OUT
run kind "$HOME_F" "$sroot"
if [ "$k1" = worktree ] && [ "$OUT" = session ]; then
  pass "kind: a worktree's root and a session's are told apart"
else
  fail "kind: '$k1' and '$OUT'"
fi
mkdir -m 700 "$BASE/0123456789abcdef"
run kind "$HOME_F" "$BASE/0123456789abcdef"
k2=$RC
run release "$HOME_F" "$BASE/0123456789abcdef"
if [ "$k2" -eq 1 ] && [ "$RC" -eq 1 ] && [ -d "$BASE/0123456789abcdef" ]; then
  pass "kind and release: a root of the right shape that no record names is left alone"
else
  fail "kind and release: an unrecorded root (kind=$k2 release=$RC)"
fi
mkdir -p "$sroot/ro/deep"
chmod 500 "$sroot/ro"
run release "$HOME_F" "$sroot"
if [ "$RC" -eq 0 ] && [ ! -e "$sroot" ] && [ ! -e "$HOME_F/scratch/$SK.tmpdir" ] && [ -d "$root" ]; then
  pass "release: a recorded root holding a read-only directory goes with its record, its sibling stays"
else
  fail "release: rc=$RC"
fi
run make "$HOME_F" "$SK"
sroot=$OUT
: >"$HOME_F/scratch/.$WK.abc123"
: >"$HOME_F/scratch/.$SK.def456"
mkdir -p "$HOME_F/scratch/$WK/legacy"
run make "$HOME_F" "$WK2"
other=$OUT
run reclaim "$HOME_F" "$WK"
if [ "$RC" -eq 0 ] && [ ! -e "$root" ] && [ ! -e "$sroot" ] && [ ! -e "$HOME_F/scratch/$WK" ] \
  && [ ! -e "$HOME_F/scratch/$WK.tmpdir" ] && [ ! -e "$HOME_F/scratch/$SK.tmpdir" ] \
  && [ ! -e "$HOME_F/scratch/.$WK.abc123" ] && [ ! -e "$HOME_F/scratch/.$SK.def456" ] \
  && [ -d "$other" ] && [ -f "$HOME_F/scratch/$WK2.tmpdir" ]; then
  pass "reclaim: the worktree's roots, records, leftovers, and earlier-layout root go; another worktree's stay"
else
  fail "reclaim: rc=$RC, left $(find "$HOME_F/scratch" "$BASE" -mindepth 1 2>&1 | tr '\n' ' ')"
fi

echo "### the final close"
# release_ptr <pointer>: the close every rung shares, on a runtime directory
# whose pointer names <pointer>.
release_ptr() {
  mkdir -p "$T/unit"
  printf '%s\n' "$1" >"$T/unit/scratch-root"
  (
    # shellcheck disable=SC2034 # read by the sourced close
    script_dir=$REPO_ROOT/scripts
    # shellcheck source=scripts/fleet-stop-lib.sh
    . "$REPO_ROOT/scripts/fleet-stop-lib.sh"
    stop_scratch_root_release "$T/unit" "$HOME_F"
  )
}
run make "$HOME_F" "$WK"
root=$OUT
run reclaim "$HOME_F" "$WK"
if release_ptr "$root" && [ ! -e "$T/unit/scratch-root" ]; then
  pass "final close: a root the worktree reclaim already took leaves only the pointer to drop"
else
  fail "final close: a reclaimed root kept its pointer"
fi
if ! release_ptr "$BASE/0123456789abcdef" && [ -f "$T/unit/scratch-root" ] && [ -d "$BASE/0123456789abcdef" ]; then
  pass "final close: an unrecorded root that still exists keeps its pointer and its files"
else
  fail "final close: an unrecorded existing root"
fi
run make "$HOME_F" "$WK"
root=$OUT
mkdir -p "$HOME_F/streamjson/other"
printf '%s\n' "$root" >"$HOME_F/streamjson/other/scratch-root"
if release_ptr "$root" && [ -d "$root" ] && [ ! -e "$T/unit/scratch-root" ]; then
  pass "final close: a worktree's root another worker records stays, the pointer goes"
else
  fail "final close: a shared worktree root"
fi
rm -f "$HOME_F/streamjson/other/scratch-root"
if release_ptr "$root" && [ ! -e "$root" ]; then
  pass "final close: the last worker's close removes the worktree's root"
else
  fail "final close: the last close left $root"
fi

echo "fleet-scratch: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
