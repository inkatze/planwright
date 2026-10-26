#!/usr/bin/env bash
# check-kb-copies.sh — the knowledge base cites specs, never copies them: fail
# when a knowledge-base Markdown file carries a spec bundle's line verbatim.
# `check-kb-copies.sh --help` prints the comparison rule, options and exit
# codes.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-kb-copies
MIN_CHARS=60
NL='
'
root=$(cd "$(dirname "$0")/.." && pwd) || exit 2

die() {
  printf '%s\n' "$prog: $1" >&2
  exit 2
}
help_text() {
  cat <<EOF
check-kb-copies.sh: fail when a knowledge-base Markdown file carries a line
of a spec bundle verbatim. A line is compared after trimming and collapsing
runs of blanks. Only lines of at least $MIN_CHARS characters count, so a short
heading, a list marker or a table rule never matches by accident; a longer
spec line repeated in the knowledge base is a copy, and the fix is a link.

Usage: check-kb-copies.sh [--kb <dir>] [--specs <dir>]
  --kb <dir>     the knowledge base to scan, every *.md under it (default
                 tests/fixtures/mission-control/kb, the fixtures CI lints)
  --specs <dir>  the spec root, every *.md under it outside the
                 underscore-prefixed reserved directories directly under
                 it (default the root scripts/resolve-root.sh resolves)

Exit codes: 0 clean; 1 a copied line (each named as
<kb-file>:<line>: copies <spec-file>); 2 usage, or an input that would
narrow the scan (a missing or unlistable directory, no knowledge-base file
or line, no spec line long enough to compare).
EOF
}

kb=$root/tests/fixtures/mission-control/kb
specs=''
while [ $# -gt 0 ]; do
  case $1 in
    --kb | --specs)
      [ $# -ge 2 ] || die "$1 needs a value"
      case $1 in
        --kb) kb=$2 ;;
        --specs) specs=$2 ;;
      esac
      shift 2
      ;;
    --help | -h)
      help_text
      exit 0
      ;;
    *) die "unknown argument: $1 (--help for usage)" ;;
  esac
done
if [ -z "$specs" ]; then
  specs=$(cd "$root" && /bin/sh scripts/resolve-root.sh spec) || die "the spec root does not resolve (scripts/resolve-root.sh spec)"
fi
[ -d "$kb" ] || die "no knowledge base at $kb"
[ -d "$specs" ] || die "no spec root at $specs"

scratch=$(mktemp -d) || die "cannot create a scratch directory"
trap 'rm -rf "$scratch"' EXIT

# collect <dir> <prune-reserved> <out>: every *.md under <dir>, sorted, one
# per line into <out>; the reserved directories are the underscore-prefixed
# ones directly under the spec root. find runs from inside <dir>, so neither
# a trailing slash, a glob character nor a leading dash in the path changes
# what it matches. A find that errors (an unreadable subdirectory) fails the
# scan rather than narrowing it.
collect() {
  cl_dir=$(cd -- "$1" && pwd) || die "cannot enter $1"
  # The list is one path per line, so a newline in the root or in any name
  # under it would split a path.
  case $cl_dir in *"$NL"*) die "the path of $1 carries a newline" ;; esac
  (cd -- "$cl_dir" && find . -name "*$NL*" -print) >"$3.nl" || die "cannot list every file under $1"
  [ ! -s "$3.nl" ] || die "a file name under $1 carries a newline"
  if [ "$2" = yes ]; then
    (cd -- "$cl_dir" && find . -path './_*' -type d -prune -o -type f -name '*.md' -print) >"$3.raw"
  else
    (cd -- "$cl_dir" && find . -type f -name '*.md' -print) >"$3.raw"
  fi || die "cannot list every file under $1"
  CL_DIR=$cl_dir awk '{ sub(/^\.\//, ""); print ENVIRON["CL_DIR"] "/" $0 }' "$3.raw" | sort >"$3" \
    || die "cannot sort the file list for $1"
}
# load <list>: FILES from the list. Every path is absolute, so awk never reads
# one as a variable assignment.
load() {
  FILES=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    FILES[${#FILES[@]}]=$f
  done <"$1"
}
collect "$specs" yes "$scratch/spec-list"
collect "$kb" no "$scratch/kb-list"
load "$scratch/spec-list"
spec_files=("${FILES[@]+"${FILES[@]}"}")
load "$scratch/kb-list"
kb_files=("${FILES[@]+"${FILES[@]}"}")
[ "${#kb_files[@]}" -gt 0 ] || die "no Markdown file under $kb"
[ "${#spec_files[@]}" -gt 0 ] || die "no Markdown file under $specs"

MIN=$MIN_CHARS awk '
  function norm(s) { sub(/\r$/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
  phase != "kb" {
    l = norm($0)
    if (length(l) >= ENVIRON["MIN"] && !(l in seen)) { seen[l] = FILENAME; spec_lines++ }
    next
  }
  {
    kb_lines++
    l = norm($0)
    if (length(l) >= ENVIRON["MIN"] && (l in seen)) {
      f = FILENAME; s = seen[l]; gsub(/[[:cntrl:]]/, "?", f); gsub(/[[:cntrl:]]/, "?", s)
      printf "%s:%d: copies %s\n", f, FNR, s
      found = 1
    }
  }
  END {
    if (spec_lines == 0) { print "check-kb-copies: no spec line is long enough to compare" > "/dev/stderr"; exit 2 }
    if (kb_lines == 0) { print "check-kb-copies: the knowledge base holds no line to compare" > "/dev/stderr"; exit 2 }
    if (found) exit 1
  }
' "${spec_files[@]}" phase=kb "${kb_files[@]}"
rc=$?
case $rc in
  0) printf '%s\n' "$prog: ${#kb_files[@]} knowledge-base file(s) cite the specs and copy none" ;;
  1) printf '%s\n' "$prog: copied spec lines found; cite the spec section by link instead" >&2 ;;
esac
exit "$rc"
