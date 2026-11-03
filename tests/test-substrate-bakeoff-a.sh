#!/bin/bash
# Tests for bake-off A's committed prototype
# (tests/fixtures/substrate-bakeoff/bakeoff-a/):
# the hardened-shell candidate against every production differential fixture
# (universal-binary REQ-C1.6), so each matrix platform's CI job runs it, and
# the delivery script's promise that nothing it installs outlives its run.
# The compiled candidates need their toolchains and are measured by the
# harness on demand, not here.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-bakeoff-a.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
BAKEOFF="$REPO_ROOT/tests/fixtures/substrate-bakeoff/bakeoff-a"
SHELL_CAND="$BAKEOFF/candidates/shell"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-bakeoff-a.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- the shell candidate on the production differential set ----------------

n=0
for fx in "$BAKEOFF"/fixtures/*/*/; do
  fx=${fx%/}
  prim=${fx%/*}
  prim=${prim##*/}
  name="$prim/${fx##*/}"
  work="$tmp/fx.$n"
  n=$((n + 1))
  mkdir "$work" "$work.home"
  [ -d "$fx/files" ] && cp -R "$fx/files/." "$work/"
  if [ -f "$fx/links" ]; then
    while IFS="$(printf '\t')" read -r lname ltarget; do ln -s "$ltarget" "$work/$lname"; done <"$fx/links"
  fi
  set --
  if [ -f "$fx/args" ]; then
    while IFS= read -r a; do set -- "$@" "$a"; done <"$fx/args"
  fi
  (cd "$work" && env -i PATH="$PATH" LC_ALL=C HOME="$work.home" "$SHELL_CAND/bin/$prim" "$@" </dev/null >"$work.out" 2>/dev/null)
  st=$?
  want=$(cat "$fx/expected-status")
  if [ "$st" = "$want" ] && cmp -s "$work.out" "$fx/expected-stdout"; then
    ok "shell candidate: $name"
  else
    bad "shell candidate: $name (status $st, expected $want; stdout differs: $(cmp -s "$work.out" "$fx/expected-stdout" && echo no || echo yes))"
  fi
done
if [ "$n" -gt 0 ]; then ok "the fixture set is not empty"; else bad "the fixture set is not empty"; fi

# --- delivery writes nothing that outlives it --------------------------------

for mode in marketplace writer; do
  mkdir -p "$tmp/home-$mode" "$tmp/tmp-$mode"
  HOME="$tmp/home-$mode" TMPDIR="$tmp/tmp-$mode" sh "$SHELL_CAND/delivery/$mode" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then ok "the $mode delivery runs the installed copy"; else bad "the $mode delivery runs the installed copy (exit $rc)"; fi
  left=$(find "$tmp/home-$mode" "$tmp/tmp-$mode" -mindepth 1)
  if [ -z "$left" ]; then ok "the $mode delivery leaves nothing behind"; else bad "the $mode delivery leaves nothing behind (found: $left)"; fi
done

if [ "$failures" -gt 0 ]; then
  echo "test-substrate-bakeoff-a: $failures failure(s)" >&2
  exit 1
fi
echo "test-substrate-bakeoff-a: all passed"
