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
# A symlink under them, or as the README, fails closed rather than being
# skipped or followed.
#
# MATCHED: each POSIX ERE in config/retired-phrasings.txt against every
# paragraph (a run of non-blank lines) lowercased with its whitespace
# collapsed, Markdown emphasis, code ticks, escapes, inline HTML element tags
# (their text kept), comment delimiters, and blockquote markers dropped, and Unicode or entity spaces read as spaces, so a phrasing wrapped across lines or
# set in emphasis is caught; a hit is reported by the line it ends on. Patterns are lowercase; an uppercase one is refused.
#
# EXEMPT: doctrine/human-gates.md, which names what it supersedes, and the
# first paragraph of doctrine/gate-wiring.md that maps the legacy subject
# marker to its trailer id, for the marker pattern only.
#
# Short phrases no frozen record carries are screened tree-wide by the
# purged-identifier seed instead; config/retired-phrasings.txt says why they
# cannot also be listed there.
#
# Usage: check-retired-phrasings.sh [--root <dir>]
#   --root  the tree to screen (default: this script's repository)
# Exit: 0 clean · 1 a retired phrasing · 2 usage, or an input that would make
#   the scan vacuous (a missing, unreadable, or empty pattern file, a symlink
#   in a surface, a failed listing, a path holding a newline, an unreadable
#   file, zero files), or a paragraph over 256 KiB or 4096 lines, whose
#   quadratic join would stall the gate.
#
# Scanned files are PR-controllable data: read by awk, never executed, and
# every reported path and pattern stripped of control bytes, C1 included.
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
trap 'exit 2' HUP INT TERM
symlink() {
  printf '%s: %s is a symlink, which the scan does not follow; failing closed.\n' "$me" "$1" >&2
  exit 2
}
for d in doctrine skills docs; do
  [ -h "$root/$d" ] && symlink "$d/"
  [ -d "$root/$d" ] || continue
  links=$(find "$root/$d" -type l -print) || links=failed
  find "$root/$d" -type f -print >>"$list" && [ "$links" != failed ] || {
    printf '%s: listing %s/ failed; failing closed.\n' "$me" "$d" >&2
    exit 2
  }
  [ -z "$links" ] || symlink "a path under $d/"
done
[ -h "$root/README.md" ] && symlink README.md
[ -f "$root/README.md" ] && printf '%s\n' "$root/README.md" >>"$list"

ROOT=$root PATTERNS=$patterns LIST=$list ME=$me awk '
# C0 controls, DEL, and C1 controls in their UTF-8 form; other UTF-8 (an
# arrow in a pattern) passes through.
function clean(s) { gsub(/[\001-\037\177]|\302[\200-\237]/, "?", s); return s }
function closed(msg) {
  printf "%s: %s; failing closed.\n", ENVIRON["ME"], msg > "/dev/stderr"
  failed = 1
  exit 2
}
# The line the first match ends on: the first line whose joined end offset
# reaches the end of the match.
function hitline(p,   k, end) {
  match(para, p)
  end = RSTART + RLENGTH - 1
  for (k = 1; k <= nl; k++) if (off[k] >= end) return ln[k]
  return ln[1]
}
function check(rel,   i, n, m) {
  if (para == "") return
  for (i = 1; i <= npat; i++) {
    if (para !~ pat[i]) continue
    if (rel == "doctrine/gate-wiring.md" && pat[i] == "pending-sign-off\\]" &&
        index(para, "planwright-sign-off: ps-legacy-") > 0 && !mapped) {
      m = para
      n = gsub(/pending-sign-off\]/, "", m)
      if (n == 1) { mapped = 1; continue }
    }
    printf "%s:%d: retired phrasing /%s/ (doctrine/human-gates.md)\n", clean(rel), hitline(pat[i]), clean(pat[i])
    hits++
  }
}
BEGIN {
  root = ENVIRON["ROOT"]
  while ((rc = (getline line < ENVIRON["PATTERNS"])) > 0) {
    sub(/\r$/, "", line)
    if (line ~ /^#/ || line ~ /^[ \t]*$/) continue
    sub(/[ \t]+$/, "", line)
    if (line != tolower(line)) closed("config/retired-phrasings.txt holds an uppercase pattern, which never matches the lowercased text")
    pat[++npat] = line
  }
  if (rc < 0) closed("config/retired-phrasings.txt could not be read")
  if (npat == 0) closed("config/retired-phrasings.txt holds no pattern")
  while ((getline path < ENVIRON["LIST"]) > 0) {
    if (index(path, root "/") != 1) closed("a listed path holds a newline")
    rel = substr(path, length(root) + 2)
    if (rel == "doctrine/human-gates.md") continue
    files++
    para = ""; nl = 0; lineno = 0
    while ((rc = (getline line < path)) > 0) {
      lineno++
      if (line ~ /^[ \t\r]*$/) { check(rel); para = ""; nl = 0; continue }
      gsub(/\302\240|\342\200[\200-\213\257]|\342\201\237|&nbsp;|&#160;/, " ", line)
      gsub(/&rarr;/, "\342\206\222", line)
      sub(/^[ \t]*(>[ \t]*)+/, "", line)
      gsub(/<!--|-->/, " ", line)
      gsub(/<\/?(a|abbr|b|code|em|i|kbd|mark|s|small|span|strong|sub|sup|u)( [^>]*)?>/, "", line)
      gsub(/[*_`\\]/, "", line)
      gsub(/[ \t\r]+/, " ", line)
      sub(/^ /, "", line); sub(/ $/, "", line)
      if (line == "") continue
      line = tolower(line)
      para = (para == "" ? "" : para " ") line
      if (length(para) > 262144) closed(clean(rel) ":" lineno ": a paragraph over 256 KiB; break it with a blank line")
      if (nl >= 4096) closed(clean(rel) ":" lineno ": a paragraph over 4096 lines; break it with a blank line")
      nl++; ln[nl] = lineno; off[nl] = length(para)
    }
    if (rc < 0) closed(clean(rel) " could not be read")
    check(rel)
    close(path)
  }
  if (files == 0) closed("zero files screened under doctrine/, skills/, docs/, or README.md")
  if (hits > 0) {
    printf "%s: %d retired phrasing(s); restate the rule by citing doctrine/human-gates.md.\n", ENVIRON["ME"], hits > "/dev/stderr"
    exit 1
  }
  printf "%s: %d file(s) screened, no retired phrasing.\n", ENVIRON["ME"], files
}
'
