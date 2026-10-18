#!/bin/sh
# check-retired-phrasings.sh — refuse a rule phrasing doctrine/human-gates.md
# retired (human-gates REQ-H1.2, REQ-D1.6, D-10).
#
# doctrine/human-gates.md states the list of human gates, policies, and
# composition contracts once; every other surface restates it by citation. A
# superseded sentence ("the flip is the review gate", an unconditional never)
# re-grows one convenient edit at a time, so this screen fails on it instead
# of trusting review to notice.
#
# SCANNED: every regular file under doctrine/, skills/, and docs/, and the
# root README.md. The historical surfaces (specs/, the changelog, the
# observations log) are never read: they record the old rules on purpose.
# Symlinks are not followed.
#
# MATCHED: each POSIX ERE in config/retired-phrasings.txt against every
# paragraph (a run of non-blank lines) lowercased with its whitespace
# collapsed, so a phrasing wrapped across lines is caught; a hit is reported
# by the paragraph's first line.
#
# EXEMPT: doctrine/human-gates.md, which names what it supersedes, and the one
# paragraph of doctrine/gate-wiring.md that maps the legacy subject marker to
# its trailer id, for the marker pattern only.
#
# Short phrases no frozen record carries are screened tree-wide by the
# purged-identifier seed instead; config/retired-phrasings.txt says why they
# cannot also be listed there.
#
# Usage: check-retired-phrasings.sh [--root <dir>]
#   --root  the tree to screen (default: this script's repository)
# Exit: 0 clean · 1 a retired phrasing · 2 usage, or an input that would make
#   the scan vacuous (a missing or empty pattern file, zero files scanned).
#
# Scanned files are PR-controllable data: read by awk, never executed, and
# every reported path stripped of control bytes.
#
# POSIX sh and awk.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-retired-phrasings

usage() {
  printf '%s\n' "usage: $me.sh [--root <dir>]" >&2
  exit 2
}

root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || usage
      root=$2
      shift 2
      ;;
    *) usage ;;
  esac
done
if [ -z "$root" ]; then
  root=$(cd "$(dirname "$0")/.." && pwd) || exit 2
fi
[ -d "$root" ] || {
  printf '%s: root is not a directory; failing closed.\n' "$me" >&2
  exit 2
}

patterns="$root/config/retired-phrasings.txt"
if [ ! -f "$patterns" ] || [ ! -r "$patterns" ]; then
  printf '%s: pattern file config/retired-phrasings.txt is missing or unreadable; failing closed.\n' "$me" >&2
  exit 2
fi

list=$(mktemp) || exit 2
trap 'rm -f "$list"' EXIT
for d in doctrine skills docs; do
  [ -d "$root/$d" ] && find "$root/$d" -type f -print
done >"$list"
[ -f "$root/README.md" ] && [ ! -h "$root/README.md" ] && printf '%s\n' "$root/README.md" >>"$list"

ROOT=$root PATTERNS=$patterns LIST=$list ME=$me awk '
function clean(s) { gsub(/[[:cntrl:]]/, "?", s); return s }
function check(rel, start, para,   i, n, m) {
  if (para == "") return
  for (i = 1; i <= npat; i++) {
    if (para !~ pat[i]) continue
    if (rel == "doctrine/gate-wiring.md" && pat[i] == "pending-sign-off\\]" &&
        index(para, "planwright-sign-off: ps-legacy-<sha7>") > 0) {
      m = para
      n = gsub(/pending-sign-off\]/, "", m)
      if (n == 1) continue
    }
    printf "%s:%d: retired phrasing /%s/ (doctrine/human-gates.md)\n", clean(rel), start, pat[i]
    hits++
  }
}
BEGIN {
  root = ENVIRON["ROOT"]
  while ((getline line < ENVIRON["PATTERNS"]) > 0) {
    if (line ~ /^#/ || line ~ /^[ \t]*$/) continue
    pat[++npat] = line
  }
  if (npat == 0) {
    printf "%s: config/retired-phrasings.txt holds no pattern; failing closed.\n", ENVIRON["ME"] > "/dev/stderr"
    exit 2
  }
  while ((getline path < ENVIRON["LIST"]) > 0) {
    rel = substr(path, length(root) + 2)
    if (rel == "doctrine/human-gates.md") { files++; continue }
    files++
    para = ""; start = 0; lineno = 0
    while ((getline line < path) > 0) {
      lineno++
      if (line ~ /^[ \t\r]*$/) { check(rel, start, para); para = ""; continue }
      if (para == "") start = lineno
      gsub(/[ \t\r]+/, " ", line)
      para = para " " tolower(line)
    }
    check(rel, start, para)
    close(path)
  }
  if (files == 0) {
    printf "%s: zero files scanned under doctrine/, skills/, docs/, or README.md; failing closed.\n", ENVIRON["ME"] > "/dev/stderr"
    exit 2
  }
  if (hits > 0) {
    printf "%s: %d retired phrasing(s); restate the rule by citing doctrine/human-gates.md.\n", ENVIRON["ME"], hits > "/dev/stderr"
    exit 1
  }
  printf "%s: %d file(s) screened, no retired phrasing.\n", ENVIRON["ME"], files
}
'
