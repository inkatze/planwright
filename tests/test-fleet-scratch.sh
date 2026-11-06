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
  "make relative $WK" "make $HOME_F not-a-key" "make $HOME_F ${WK}x" "reclaim $HOME_F $SK" "release $HOME_F" "kind $HOME_F $WK"; do
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
NEW=$(hex40 9)
for bad in relative "$T/missing"; do
  PLANWRIGHT_FLEET_SCRATCH_BASE=$bad run make "$HOME_F" "$NEW"
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && grep -q 'PLANWRIGHT_FLEET_SCRATCH_BASE' "$T/err"; then
    pass "make: the base '$bad' is refused with a reason"
  else
    fail "make: the base '$bad' (rc=$RC, '$OUT')"
  fi
done
mkdir -m 777 "$T/open"
chmod 777 "$T/open"
PLANWRIGHT_FLEET_SCRATCH_BASE=$T/open run make "$HOME_F" "$NEW"
if [ "$RC" -eq 1 ] && [ -z "$(ls -A "$T/open")" ]; then
  pass "make: a base others may write is refused, nothing created in it"
else
  fail "make: an open base (rc=$RC, $(ls -A "$T/open"))"
fi
mkdir -m 700 "$HOME_F/inner"
PLANWRIGHT_FLEET_SCRATCH_BASE=$HOME_F/inner run make "$HOME_F" "$NEW"
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

W64=$(hex40 7)$(printf '%s' 777777777777777777777777)
S64=$W64-$(hex40 6)$(printf '%s' 666666666666666666666666)
run make "$HOME_F" "$S64"
s64=$OUT
run make "$HOME_F" "$W64"
if [ "$RC" -eq 0 ] && [ -d "$s64" ] && [ -d "$OUT" ] && /bin/sh "$FS" reclaim "$HOME_F" "$W64" \
  && [ ! -e "$s64" ] && [ ! -e "$OUT" ]; then
  pass "make and reclaim: a SHA-256 repository's keys are a worktree's and a session's"
else
  fail "make: SHA-256 keys (rc=$RC, $(cat "$T/err"))"
fi
mkdir -m 700 "$T/nl
base"
before=$(ls -A "$T/nl
base")
PLANWRIGHT_FLEET_SCRATCH_BASE="$T/nl
base" run make "$HOME_F" "$NEW"
if [ "$RC" -eq 1 ] && [ "$(ls -A "$T/nl
base")" = "$before" ] && grep -q 'control character' "$T/err"; then
  pass "make: a base holding a control character is refused before anything is created"
else
  fail "make: a control-character base (rc=$RC, $(cat "$T/err"))"
fi

echo "### --fresh and the earlier layout"
: >"$root/old"
run make "$HOME_F" "$WK" --fresh
if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ] && [ -z "$(ls -A "$root")" ]; then
  pass "--fresh: the recorded root comes back empty"
else
  fail "--fresh: rc=$RC '$OUT' $(ls -A "$root" 2>&1)"
fi
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$HOME_F/scratch/$WK.tmpdir"
  run make "$HOME_F" "$WK" --fresh
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ] && [ "$(cat "$HOME_F/scratch/$WK.tmpdir")" = "$root" ]; then
    pass "--fresh: a record that cannot be read is replaced"
  else
    fail "--fresh: an unreadable record (rc=$RC, $(cat "$T/err"))"
  fi
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

echo "### the recorded root stands"
mkdir -m 700 "$T/base2"
PLANWRIGHT_FLEET_SCRATCH_BASE=$T/base2 run make "$HOME_F" "$WK"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ]; then
  pass "make: a recorded root stands over another base"
else
  fail "make: another base moved the root to '$OUT'"
fi
PLANWRIGHT_FLEET_SCRATCH_BASE=$T/missing run make "$HOME_F" "$WK"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ]; then
  pass "make: a recorded root stands while this launch's base is unusable"
else
  fail "make: an unusable base refused a usable recorded root (rc=$RC)"
fi
chmod 755 "$root"
run make "$HOME_F" "$WK"
mode=$(stat -c %a "$root" 2>/dev/null || stat -f %Lp "$root" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ] && [ "$mode" = 700 ]; then
  pass "make: a recorded root someone opened is closed again"
else
  fail "make: the recorded root stood at mode $mode"
fi
if [ "$(id -u)" = 0 ]; then
  echo "skip: make with an unwritable record directory (root ignores directory modes)"
else
  WK4=$(hex40 f)
  before=$(ls -A "$BASE")
  chmod 500 "$HOME_F/scratch"
  run make "$HOME_F" "$WK4"
  chmod 700 "$HOME_F/scratch"
  if [ "$RC" -eq 1 ] && [ "$(wc -l <"$T/err")" -eq 1 ] && grep -q 'cannot record the root' "$T/err" \
    && [ "$(ls -A "$BASE")" = "$before" ]; then
    pass "make: a root whose record cannot be written is removed, the one reason printed"
  else
    fail "make: unrecordable root (rc=$RC, $(cat "$T/err"), $(ls -A "$BASE"))"
  fi
  chmod 000 "$HOME_F/scratch/$WK.tmpdir"
  run make "$HOME_F" "$WK"
  chmod 600 "$HOME_F/scratch/$WK.tmpdir"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$root" ] && [ ! -s "$T/err" ]; then
    pass "make: an unreadable record prints nothing beside the root"
  else
    fail "make: an unreadable record (rc=$RC, '$OUT', $(cat "$T/err"))"
  fi
fi

echo "### release, reclaim"
run make "$HOME_F" "$SK"
sroot=$OUT
mkdir -m 700 "$BASE/0123456789abcdef"
run release "$HOME_F" "$BASE/0123456789abcdef"
if [ "$RC" -eq 1 ] && [ -d "$BASE/0123456789abcdef" ]; then
  pass "release: a root of the right shape that no record names is left alone"
else
  fail "release: an unrecorded root (rc=$RC)"
fi
mkdir -p "$sroot/ro/deep"
chmod 500 "$sroot/ro"
run release "$HOME_F" "$sroot"
if [ "$RC" -eq 0 ] && [ ! -e "$sroot" ] && [ ! -e "$HOME_F/scratch/$SK.tmpdir" ] && [ -d "$root" ]; then
  pass "release: a recorded root holding a read-only directory goes with its record, its sibling stays"
else
  fail "release: rc=$RC"
fi
run release "$HOME_F" "$sroot"
if [ "$RC" -eq 0 ]; then
  pass "release: a root already released is done"
else
  fail "release: a second release exited $RC"
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
if release_ptr "$root" && [ ! -e "$root" ] && [ ! -e "$T/unit/scratch-root" ]; then
  pass "final close: a recorded root goes with its pointer"
else
  fail "final close: left $root or its pointer"
fi

echo "fleet-scratch: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
