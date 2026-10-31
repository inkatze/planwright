#!/bin/sh
# check-counts.sh — fail when the sentence introducing a Markdown list or table
# states a count the list below it does not have.
#
# Usage: check-counts.sh [--exempt <tsv>] [<root>]
#   <root>  a git work tree (default: this script's repository)
#   --exempt  the exemption list (default: scripts/check-counts-exempt.tsv)
#   check-counts.sh --help | -h
# Exit codes: 0 clean; 1 a finding or a stale exemption; 2 usage error or a
# scan that cannot cover what it claims. --help states what is read and how.
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-counts
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

spec_parse_sh=$script_dir/spec-parse.sh
[ -r "$spec_parse_sh" ] || {
  printf '%s\n' "$me: required helper spec-parse.sh missing or unreadable" >&2
  exit 2
}
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

fail_closed() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-counts.sh: a stated count must equal the list it introduces.

Usage: check-counts.sh [--exempt <tsv>] [<root>]
       check-counts.sh --help | -h

Read: the files git tracks under <root> ending in .md, in doctrine/, skills/,
docs/, specs/_pending/, and a spec bundle under specs/ whose requirements.md
declares **Status:** Draft. A bundle at any other status is skipped: its
enumerations are the sign-off cross-check's. Fenced code is not prose.

Checked: a prose line ending in ':' (a paragraph, or a list item's own text)
followed, at most one blank line later, by a list or a table. Its last sentence
must hold exactly one plain count: a number word from two to twenty, or a
numeral before a plural word that no reference word (task, step, phase,
section, wave, stage, round, version, line, item) precedes. Code spans,
hyphenated words, and a second distinct count make the sentence uncounted.
The list's length is its top-level items (nested items and continuation
paragraphs belong to their item); a table's is its body rows.

Exemptions: one file<TAB>excerpt<TAB>reason row per finding, the excerpt a
substring of the introducing sentence. A row clearing no finding fails.

Exit codes: 0 clean; 1 a finding or a stale exemption; 2 usage error, a root
that is not a git work tree, an unreadable file or exemption list, a malformed
exemption row, or a scan reaching no files.
EOF
}

exempt=$script_dir/check-counts-exempt.tsv
root=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --help | -h)
      [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
      usage
      exit 0
      ;;
    --exempt)
      [ "$#" -ge 2 ] || fail_closed "--exempt needs a file"
      exempt=$2
      shift 2
      ;;
    -*) fail_closed "unknown option (see --help)" ;;
    *)
      [ -z "$root" ] || fail_closed "too many arguments (expected at most one root)"
      root=$1
      shift
      ;;
  esac
done
[ -n "$root" ] || root=$repo_root

[ -d "$root" ] || fail_closed "root not found or not a directory"
[ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
  || fail_closed "root is not a git work tree"
[ -r "$exempt" ] || fail_closed "the exemption list is unreadable"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-counts.XXXXXX") \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

git -C "$root" ls-files -z -- doctrine skills docs specs >"$work/tracked" 2>"$work/err" \
  || fail_closed "git ls-files failed"

# A bundle is in scope only at Draft; the status is read once per bundle.
tr '\0' '\n' <"$work/tracked" | awk '
  /\.md$/ && /^(doctrine|skills|docs|specs\/_pending)\// { print; next }
  /\.md$/ && /^specs\/[^_\/][^\/]*\// { b = $0; sub(/^specs\//, "", b); sub(/\/.*/, "", b); print "B\t" b "\t" $0 }
' >"$work/candidates" || fail_closed "the file list could not be built"

: >"$work/list"
while IFS= read -r line; do
  case $line in
    "B	"*)
      rest=${line#B	}
      b=${rest%%	*}
      f=${rest#*	}
      if [ "$b" != "${seen_bundle-}" ]; then
        seen_bundle=$b
        req=$root/specs/$b/requirements.md
        status=""
        if [ -r "$req" ]; then
          status=$(spec_parse_header_value "$req" Status 2>/dev/null) || status=""
        fi
      fi
      [ "$status" = Draft ] || continue
      ;;
    *) f=$line ;;
  esac
  [ -r "$root/$f" ] || fail_closed "a tracked file is unreadable"
  printf '%s\n' "$f" >>"$work/list"
done <"$work/candidates"

[ -s "$work/list" ] || fail_closed "the scan reached no files, a broken enumeration rather than a clean tree"

CC_ROOT=$root CC_LIST=$work/list CC_EXEMPT=$exempt CC_ME=$me
export CC_ROOT CC_LIST CC_EXEMPT CC_ME
awk '
  function clean(s) { gsub(/[\001-\037\177]/, "", s); return s }
  function indent(s) { match(s, /^ */); return RLENGTH }
  function is_item(s) { return s ~ /^ *([-*+]|[0-9]+[.)])[ \t]+[^ \t]/ }
  function is_table(s) { return s ~ /^ *\|/ }
  function is_heading(s) { return s ~ /^ {0,3}#/ }
  function words(   i) {
    split("two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty", w, " ")
    for (i = 1; i <= 19; i++) wv[w[i]] = i + 1
  }
  # The one count a sentence states, or 0 when it states none or several.
  function stated(s,   t, n, k, v, tok, pre, prev) {
    t = " " tolower(s) " "
    gsub(/`[^`]*`/, " ", t)
    while (gsub(/\([^()]*\)/, " ", t)) ;
    n = 0
    for (k in wv) {
      tok = t
      while (match(tok, "[^a-z0-9-]" k "[^a-z0-9-]")) { if (!n || v != wv[k]) { n++; v = wv[k] }; tok = substr(tok, RSTART + RLENGTH - 1) }
    }
    tok = t
    while (match(tok, /[ (][0-9]+ [a-z][a-z][a-z]+s[^a-z-]/)) {
      pre = substr(tok, 1, RSTART)
      k = substr(tok, RSTART + 1, RLENGTH - 1); sub(/ .*/, "", k)
      tok = substr(tok, RSTART + RLENGTH - 1)
      prev = pre; sub(/[ (]+$/, "", prev); sub(/.*[ (-]/, "", prev)
      if (prev ~ /^(tasks?|steps?|phases?|sections?|waves?|stages?|rounds?|versions?|lines?|items?|§)$/) continue
      if (k + 0 < 2) continue
      if (!n || v != k + 0) { n++; v = k + 0 }
    }
    return n == 1 ? v : 0
  }
  function last_sentence(s,   t) {
    t = s
    gsub(/(e\.g|i\.e|etc|vs)\./, "x", t)
    while (match(t, /([.!?][)"*_]*|;)[ \t]+[^ \t]/)) t = substr(t, RSTART + RLENGTH - 1)
    return t
  }
  function count_items(j,   k, I, c, prevblank, ind) {
    I = indent(L[j]); c = 0; prevblank = 0
    for (k = j; k <= n; k++) {
      if (code[k]) { if (indent(L[k]) > I) { prevblank = 0; continue } break }
      if (L[k] ~ /^[ \t]*$/) { prevblank = 1; continue }
      if (is_heading(L[k])) break
      ind = indent(L[k])
      if (ind < I) break
      if (ind == I) {
        if (is_item(L[k])) c++
        else if (prevblank) break
      }
      prevblank = 0
    }
    return c
  }
  function count_rows(j,   k, c) {
    c = 0
    for (k = j; k <= n && !code[k] && is_table(L[k]); k++) c++
    if (j + 1 <= n && L[j + 1] ~ /^ *\|? *:?-{3,}/) c -= 2
    return c
  }
  function scan(path, file,   r, line, i, s, k, j, text, sent, want, got, fence, key, hit) {
    n = 0; fence = ""
    while ((r = (getline line < path)) > 0) {
      sub(/\r$/, "", line)
      L[++n] = line; code[n] = 0
      if (fence != "") { code[n] = 1; if (line ~ ("^ *" fence)) fence = ""; continue }
      if (match(line, /^ *(```|~~~)/)) { code[n] = 1; fence = substr(line, RSTART + RLENGTH - 3, 3) }
    }
    close(path)
    if (r < 0) { unreadable = 1; return }
    for (i = 1; i <= n; i++) {
      if (code[i] || L[i] !~ /:[ \t]*$/ || is_heading(L[i]) || is_table(L[i])) continue
      s = i
      if (!is_item(L[i]))
        for (k = i - 1; k >= 1 && !code[k] && L[k] !~ /^[ \t]*$/ && !is_heading(L[k]) && !is_table(L[k]); k--) { s = k; if (is_item(L[k])) break }
      j = i + 1
      if (j <= n && L[j] ~ /^[ \t]*$/) j++
      if (j > n || code[j]) continue
      if (is_item(L[s]) ? indent(L[j]) <= indent(L[s]) : indent(L[j]) < indent(L[s])) continue
      if (is_item(L[j])) got = count_items(j)
      else if (is_table(L[j])) got = count_rows(j)
      else continue
      text = ""
      for (k = s; k <= i; k++) text = text " " L[k]
      sub(/^ *([-*+]|[0-9]+[.)])[ \t]+/, "", text)
      gsub(/\]\([^)]*\)/, "]", text)
      sent = last_sentence(text)
      want = stated(sent)
      if (!want || want == got) continue
      hit = 0
      for (key in ex) { split(key, p, "\t"); if (p[1] == file && index(sent, p[2])) { used[key] = 1; hit = 1 } }
      if (hit) continue
      sub(/^[ \t]+/, "", sent)
      printf "%s: %s:%d: states %d, lists %d: %s\n", ENVIRON["CC_ME"], clean(file), i, want, got, clean(sent)
      bad = 1
    }
  }
  BEGIN {
    words()
    f = ENVIRON["CC_EXEMPT"]
    while ((r = (getline l < f)) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      if (split(l, p, "\t") != 3 || p[1] == "" || p[2] == "" || p[3] == "") { malformed = 1; exit }
      ex[p[1] "\t" p[2]] = 1
    }
    if (r < 0) { unreadable = 1; exit }
    lf = ENVIRON["CC_LIST"]
    while ((r = (getline file < lf)) > 0) { scan(ENVIRON["CC_ROOT"] "/" file, file); if (unreadable) exit }
    if (r < 0) unreadable = 1
  }
  END {
    if (malformed) { print ENVIRON["CC_ME"] ": malformed exemption row (want file<TAB>excerpt<TAB>reason)" > "/dev/stderr"; exit 2 }
    if (unreadable) { print ENVIRON["CC_ME"] ": a file could not be read during the scan" > "/dev/stderr"; exit 2 }
    for (k in ex) if (!(k in used)) { split(k, p, "\t"); printf "%s: stale exemption: %s %s clears no finding\n", ENVIRON["CC_ME"], clean(p[1]), clean(p[2]); bad = 1 }
    exit bad ? 1 : 0
  }
' >"$work/out"
rc=$?
cat "$work/out"
case $rc in
  0) printf '%s: clean (%s files)\n' "$me" "$(wc -l <"$work/list" | tr -d ' ')" ;;
  1) ;;
  *) exit 2 ;;
esac
exit "$rc"
