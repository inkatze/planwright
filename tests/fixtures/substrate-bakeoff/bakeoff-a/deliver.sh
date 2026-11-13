#!/bin/sh
# deliver.sh <marketplace|writer> <candidate-dir> — install one bake-off A
# candidate through one delivery mode into a fresh home, then run the
# installed copy; exit zero when it runs and answers correctly.
#
#   writer        the ~/.claude/ writer copies files with their modes, so the
#                 installed copy is run directly.
#   marketplace   the plugin marketplace copy is reported to strip execute
#                 bits, so every installed file is made
#                 non-executable first. Shell then runs through `sh`, as a hook
#                 or skill must call it. A compiled artifact cannot run from
#                 that copy at all; it runs only by the planned fetch path,
#                 which places it in the plugin data directory and marks
#                 it executable, and that step is what this mode simulates. No
#                 release exists to fetch from at prototype scope, so the
#                 download and checksum steps are not exercised.
#
# Everything lands in a temporary directory of its own, removed on exit, so a
# run outside the harness's fresh home writes nothing that outlives it.
set -eu
unset CDPATH
mode=$1
case $mode in
  marketplace | writer) ;;
  *)
    printf '%s\n' "deliver.sh: unknown delivery mode: $mode" >&2
    exit 2
    ;;
esac
cand=$(cd "$2" && pwd)
root=$(cd "$cand/../../../../../.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/deliver.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
dest=$scratch/install

check() { # check <program-runner...>: run the installed primitives
  if [ -e "$bindir/hello" ]; then
    [ "$("$@" "$bindir/hello" world)" = 'hello world' ]
    return
  fi
  "$@" "$bindir/lock" alive detached-1-1-1-1-1
  printf '### Task 1 \342\200\224 x\n- **Dependencies:** 2\n' >"$scratch/tasks.md"
  [ "$("$@" "$bindir/deps" "$scratch/tasks.md")" = "$(printf 'TASK\t1\nTASKDEP\t1\t2')" ]
}

run_direct() { "$@"; }

if [ -f "$cand/lib/proto.sh" ]; then
  # The shell candidate keeps its production libraries seven levels above its
  # lib/, so the install reproduces that layout.
  rel=tests/fixtures/substrate-bakeoff/bakeoff-a/candidates/shell
  mkdir -p "$dest/scripts" "$dest/$rel"
  cp "$root/scripts/lock-lib.sh" "$root/scripts/spec-parse.sh" "$dest/scripts/"
  cp -R "$cand/bin" "$cand/lib" "$dest/$rel/"
  bindir=$dest/$rel/bin
  if [ "$mode" = marketplace ]; then
    find "$dest" -type f -exec chmod a-x {} +
    check sh
  else
    check run_direct
  fi
  exit 0
fi

mkdir -p "$dest/bin"
cp "$cand"/out/* "$dest/bin/"
bindir=$dest/bin
if [ "$mode" = marketplace ]; then
  chmod a-x "$dest"/bin/*
  mkdir -p "$scratch/data/bin"
  cp "$dest"/bin/* "$scratch/data/bin/"
  chmod 755 "$scratch"/data/bin/*
  bindir=$scratch/data/bin
fi
check run_direct
