#!/bin/bash
# Tests for bake-off B's committed prototype
# (tests/fixtures/substrate-bakeoff/bakeoff-b/): the hardened-shell candidate
# against every production differential fixture (universal-binary REQ-C1.6),
# so each matrix platform's CI job runs it; the false-allow vector list
# against the tokenizer fixtures, so removing a vector's case fails here;
# and the delivery script's promise that nothing it installs outlives its
# run. The compiled candidates need their toolchains and are measured by the
# harness on demand, not here.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-bakeoff-b.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
BAKEOFF="$REPO_ROOT/tests/fixtures/substrate-bakeoff/bakeoff-b"
SHELL_CAND="$BAKEOFF/candidates/shell"
REQS="$REPO_ROOT/specs/universal-binary/requirements.md"
TAB=$(printf '\t')

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-bakeoff-b.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- the shell candidate on the production differential set ----------------

# Staged the way the harness stages a fixture: files/, the fixture's stdin,
# and a fresh home that is also TMPDIR.
ntok=0
nready=0
nfx=0
for fx in "$BAKEOFF"/fixtures/*/*/; do
  [ -d "$fx" ] || continue
  fx=${fx%/}
  prim=${fx%/*}
  prim=${prim##*/}
  name="$prim/${fx##*/}"
  case $prim in
    tokenize) ntok=$((ntok + 1)) ;;
    ready) nready=$((nready + 1)) ;;
  esac
  nfx=$((nfx + 1))
  work="$tmp/fx.$nfx"
  if ! mkdir -p "$work" "$work.home"; then
    bad "shell candidate: $name (could not make its working directory)"
    continue
  fi
  if [ -d "$fx/files" ] && ! cp -R "$fx/files/." "$work/"; then
    bad "shell candidate: $name (could not stage files/)"
    continue
  fi
  set --
  if [ -f "$fx/args" ]; then
    while IFS= read -r a || [ -n "$a" ]; do set -- "$@" "$a"; done <"$fx/args"
  fi
  stdin=/dev/null
  [ -f "$fx/stdin" ] && stdin=$fx/stdin
  (cd "$work" && env -i PATH="$PATH" LC_ALL=C HOME="$work.home" TMPDIR="$work.home" "$SHELL_CAND/bin/$prim" "$@" <"$stdin" >"$work.out" 2>"$work.err")
  st=$?
  want=$(cat "$fx/expected-status")
  if [ "$st" = "$want" ] && cmp -s "$work.out" "$fx/expected-stdout"; then
    ok "shell candidate: $name"
  else
    bad "shell candidate: $name (status $st, expected $want; stdout differs: $(cmp -s "$work.out" "$fx/expected-stdout" && echo no || echo yes); stderr: $(cat "$work.err"))"
  fi
done
if [ "$ntok" -gt 0 ]; then ok "the tokenize fixture set is not empty"; else bad "the tokenize fixture set is not empty"; fi
if [ "$nready" -gt 0 ]; then ok "the ready fixture set is not empty"; else bad "the ready fixture set is not empty"; fi

# --- one tokenizer fixture per enumerated false-allow vector ----------------

# The parser-fragility line of the bundle's Sources, through to the next
# bullet: the UIDs a vector may cite.
sources=$(awk '
  /^- \*\*Observations, parser-fragility class:\*\*/ { on = 1 }
  on && /^- / && !/parser-fragility class/ { exit }
  on { print }
' "$REQS")
if [ -n "$sources" ]; then ok "the parser-fragility Sources line is found"; else bad "the parser-fragility Sources line is found"; fi

nvec=0
listed=" "
while IFS="$TAB" read -r vid uid fcase desc || [ -n "$vid" ]; do
  case $vid in '' | '#'*) continue ;; esac
  nvec=$((nvec + 1))
  listed="$listed$fcase "
  if [ -z "$desc" ]; then
    bad "vector $vid has four columns"
    continue
  fi
  # A whole UID: each is followed by a comma, or a period after the last.
  case $sources in
    *"obs:$uid,"* | *"obs:$uid."*) ok "vector $vid cites a parser-fragility observation" ;;
    *) bad "vector $vid cites a parser-fragility observation (obs:$uid is not in the Sources line)" ;;
  esac
  d="$BAKEOFF/fixtures/tokenize/$fcase"
  if [ -f "$d/stdin" ] && [ -f "$d/expected-stdout" ] && [ -f "$d/expected-status" ]; then
    ok "vector $vid has its tokenizer fixture"
  else
    bad "vector $vid has its tokenizer fixture (fixtures/tokenize/$fcase is missing or incomplete)"
  fi
done <"$BAKEOFF/vectors.tsv"
if [ "$nvec" -gt 0 ]; then ok "the vector list is not empty"; else bad "the vector list is not empty"; fi

# A vec- fixture no row names is a vector vectors.tsv does not list.
for d in "$BAKEOFF"/fixtures/tokenize/vec-*/; do
  [ -d "$d" ] || continue
  d=${d%/}
  case $listed in
    *" ${d##*/} "*) ;;
    *) bad "fixture ${d##*/} is listed in vectors.tsv" ;;
  esac
done

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
  echo "test-substrate-bakeoff-b: $failures failure(s)" >&2
  exit 1
fi
echo "test-substrate-bakeoff-b: all passed"
