#!/bin/sh
# deliver.sh <marketplace|writer> <candidate-dir> — install one bake-off B
# candidate through one delivery mode into a fresh home, then run the
# installed copy; exit zero when it runs and answers correctly.
#
#   writer        the ~/.claude/ writer copies files with their modes, so the
#                 installed copy is run directly.
#   marketplace   the plugin marketplace copy is reported to strip execute
#                 bits, so every installed file is made non-executable first.
#                 Shell then runs through `bash`, as a hook registration
#                 calls it. A compiled artifact cannot run from that copy at
#                 all; it runs only by the planned fetch path, which places it
#                 in the plugin data directory and marks it executable, and
#                 that step is what this mode simulates. No release exists to
#                 fetch from at prototype scope, so the download and checksum
#                 steps are not exercised.
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
  [ "$(printf 'ls -l' | "$@" "$bindir/tokenize")" = "$(printf 'W\t0\t0\t-1\t0\t0\t0\t0\t-\tls\nW\t0\t0\t-1\t0\t0\t0\t0\t-\t-l')" ]
  mkdir "$scratch/pr"
  printf '%s' '{"baseRefName":"main","headRefOid":"0123456789abcdef0123456789abcdef01234567","isDraft":true,"mergeable":"CONFLICTING","url":"https://github.com/acme/widget/pull/1"}' >"$scratch/pr/view"
  case $(cd "$scratch/pr" && "$@" "$bindir/ready" - - refuse) in
    *'"permissionDecision":"deny"'*'mergeable is CONFLICTING'*) ;;
    *) return 1 ;;
  esac
}

run_direct() { "$@"; }

if [ -f "$cand/lib/proto.sh" ]; then
  # The shell candidate keeps the production hooks seven levels above its
  # lib/, so the install reproduces that layout.
  rel=tests/fixtures/substrate-bakeoff/bakeoff-b/candidates/shell
  mkdir -p "$dest/scripts" "$dest/$rel"
  cp "$root/scripts/worker-command-guard.sh" "$root/scripts/ready-guard.sh" "$root/scripts/echo-safety.sh" "$dest/scripts/"
  cp -R "$cand/bin" "$cand/lib" "$dest/$rel/"
  bindir=$dest/$rel/bin
  if [ "$mode" = marketplace ]; then
    find "$dest" -type f -exec chmod a-x {} +
    check bash
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
