#!/usr/bin/env bash
# check-kb-copies.sh — the knowledge base cites specs, never copies them: fail
# when a knowledge-base Markdown file carries a line of a spec bundle verbatim.
#
# A line is compared after trimming and collapsing runs of blanks. Only lines
# of at least MIN_CHARS characters count, so a short heading, a list marker or
# a table rule never matches by accident; a longer spec line repeated in the
# knowledge base is a copy, and the fix is a link to it.
#
# Usage: check-kb-copies.sh [--kb <dir>] [--specs <dir>]
#   --kb <dir>     the knowledge base to scan, every *.md under it (default
#                  tests/fixtures/mission-control/kb, the fixtures CI lints)
#   --specs <dir>  the spec root, every *.md under it outside the
#                  underscore-prefixed reserved directories (default the
#                  root scripts/resolve-root.sh resolves)
#
# Exit codes: 0 clean; 1 a copied line (each named as
# <kb-file>:<line>: copies <spec-file>); 2 usage, or an input that would
# narrow the scan to nothing (a missing directory, no knowledge-base file, no
# spec line long enough to compare).
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-kb-copies
MIN_CHARS=60
root=$(cd "$(dirname "$0")/.." && pwd) || exit 2

die() {
  printf '%s\n' "$prog: $1" >&2
  exit 2
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
    *) die "unknown argument: $1" ;;
  esac
done
if [ -z "$specs" ]; then
  specs=$(cd "$root" && /bin/sh scripts/resolve-root.sh spec) || die "the spec root does not resolve (scripts/resolve-root.sh spec)"
fi
[ -d "$kb" ] || die "no knowledge base at $kb"
[ -d "$specs" ] || die "no spec root at $specs"

# collect <dir> <prune-reserved>: every *.md under <dir>, NUL-free names one
# per line; a name carrying a newline or an `=` (awk would read it as an
# assignment) fails the scan rather than being skipped.
collect() {
  if [ "$2" = yes ]; then
    find "$1" -name '_*' -prune -o -type f -name '*.md' -print
  else
    find "$1" -type f -name '*.md' -print
  fi
}
spec_files=()
while IFS= read -r f; do
  case $f in *=*) die "a spec file name carries '=': $f" ;; esac
  spec_files[${#spec_files[@]}]=$f
done <<EOF
$(collect "$specs" yes | sort)
EOF
kb_files=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case $f in *=*) die "a knowledge-base file name carries '=': $f" ;; esac
  kb_files[${#kb_files[@]}]=$f
done <<EOF
$(collect "$kb" no | sort)
EOF
[ "${#kb_files[@]}" -gt 0 ] || die "no Markdown file under $kb"
[ "${#spec_files[@]}" -gt 0 ] && [ -n "${spec_files[0]}" ] || die "no Markdown file under $specs"

MIN=$MIN_CHARS awk '
  function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
  phase != "kb" {
    l = norm($0)
    if (length(l) >= ENVIRON["MIN"] && !(l in seen)) { seen[l] = FILENAME; n++ }
    next
  }
  FNR == 1 && n == 0 { print "check-kb-copies: no spec line is long enough to compare" > "/dev/stderr"; exit 2 }
  {
    l = norm($0)
    if (length(l) >= ENVIRON["MIN"] && (l in seen)) {
      printf "%s:%d: copies %s\n", FILENAME, FNR, seen[l]
      found = 1
    }
  }
  END { if (found) exit 1 }
' "${spec_files[@]}" phase=kb "${kb_files[@]}"
rc=$?
case $rc in
  0) printf '%s\n' "$prog: ${#kb_files[@]} knowledge-base file(s) cite the specs and copy none" ;;
  1) printf '%s\n' "$prog: copied spec lines found; cite the spec section by link instead" >&2 ;;
esac
exit "$rc"
