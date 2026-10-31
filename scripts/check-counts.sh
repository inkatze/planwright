#!/bin/sh
# check-counts.sh — fail when the sentence introducing a Markdown list or table
# states a count the list below it does not have.
#
# Usage: check-counts.sh [--exempt <tsv>] [<root>]
#   <root>  a git work tree (default: this script's repository)
#   --exempt  the exemption list (default: the one beside this script)
#   check-counts.sh --help | -h
# Exit codes: 0 clean; 1 a finding or a stale exemption; 2 usage error or a
# scan that cannot cover what it claims. --help states what is read and how.
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH
# <root> alone names the repository read, never an inherited one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

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
docs/, the spec home's _pending/, and a spec bundle in the spec home (the
scripts/resolve-root.sh spec answer at <root>, read only when it lies inside
<root>) whose requirements.md declares **Status:** Draft (with no requirements.md tracked yet, a tracked
design.md, tasks.md or test-spec.md declaring it). A bundle at any other
status is skipped: its enumerations are the sign-off cross-check's. Fenced code is not prose.

Checked: a prose line ending in ':' (a paragraph, or a list item's own text)
followed, at most one blank line later, by a list or a table. Its last sentence
must hold exactly one plain count: a number word from two to twenty, or a
numeral of 2 or more before a plural word of four letters or more that no
reference word (task, step, phase, section, wave, stage, round, version,
line, item, pr, issue, run, §) precedes. A count inside a code span, inside
parentheses, or in a hyphenated word is not read; a second distinct count
makes the sentence uncounted.
The list's length is its top-level items (nested items and continuation
paragraphs belong to their item); a table's is its body rows.

Exemptions: one file<TAB>excerpt<TAB>reason row per finding, the excerpt a
substring of the introducing sentence, read from --exempt or else the list
beside this script whatever the root. A row clearing no finding fails, and a
repeated file and excerpt pair is malformed.

A tracked file absent from the work tree is not read.

Exit codes: 0 clean; 1 a finding or a stale exemption; 2 usage error, a root
that is not a git work tree, an unreadable file or exemption list, a Draft
candidate whose requirements.md cannot be parsed, a tracked symlink or
non-regular file, a tracked name holding a newline, a malformed exemption row,
or a scan reaching no files.
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

root_abs=$(cd "$root" && pwd -P) || fail_closed "root could not be resolved"
# The spec home is judged at <root>, never at an inherited repository.
spec_home=$(cd "$root_abs" && PLANWRIGHT_REPO_ROOT='' /bin/sh "$script_dir/resolve-root.sh" spec 2>/dev/null) \
  || fail_closed "the spec home does not resolve"
spec_rel=""
if [ -d "$spec_home" ]; then
  spec_abs=$(cd "$spec_home" && pwd -P) || fail_closed "the spec home could not be resolved"
  case $spec_abs in
    "$root_abs"/*) spec_rel=${spec_abs#"$root_abs"/} ;;
  esac
fi

set -- doctrine skills docs
[ -z "$spec_rel" ] || set -- "$@" "$spec_rel"
git -C "$root" ls-files -z -- "$@" >"$work/tracked" 2>/dev/null \
  || fail_closed "git ls-files failed"

nuls=$(tr -cd '\000' <"$work/tracked" | wc -c) || fail_closed "the file list could not be read"
lines=$(tr '\000' '\n' <"$work/tracked" | wc -l) || fail_closed "the file list could not be read"
[ "$nuls" -eq "$lines" ] || fail_closed "a tracked name holds a newline, refusing to scan"

# A bundle is in scope only at Draft; the status is read once per bundle.
tr '\0' '\n' <"$work/tracked" >"$work/names" || fail_closed "the file list could not be read"
awk -v sp="$spec_rel/" '
  !/\.md$/ { next }
  /^(doctrine|skills|docs)\// { print; next }
  sp != "/" && substr($0, 1, length(sp)) == sp {
    rest = substr($0, length(sp) + 1)
    if (rest ~ /^_pending\//) { print; next }
    if (rest ~ /^[^_\/][^\/]*\//) { b = rest; sub(/\/.*/, "", b); print "B\t" b "\t" $0 }
  }
' <"$work/names" >"$work/candidates" || fail_closed "the file list could not be built"

: >"$work/list"
while IFS= read -r line; do
  case $line in
    "B	"*)
      rest=${line#B	}
      b=${rest%%	*}
      f=${rest#*	}
      if [ "$b" != "${seen_bundle-}" ]; then
        seen_bundle=$b
        req=$root/$spec_rel/$b/requirements.md
        status=""
        [ ! -L "$req" ] || fail_closed "a bundle's requirements.md is a symlink, refusing to follow it"
        if [ -e "$req" ]; then
          status=$(spec_parse_header_value "$req" Status 2>/dev/null) \
            || fail_closed "a bundle's requirements.md could not be parsed for its status"
        else
          # Absent requirements.md: a sibling at Draft keeps the bundle in scope.
          for sib in design.md tasks.md test-spec.md; do
            grep -Fqx "$spec_rel/$b/$sib" "$work/names" || continue
            sib=$root/$spec_rel/$b/$sib
            [ -e "$sib" ] || [ -L "$sib" ] || continue
            [ ! -L "$sib" ] || fail_closed "a bundle's status file is a symlink, refusing to follow it"
            s_status=$(spec_parse_header_value "$sib" Status 2>/dev/null) \
              || fail_closed "a bundle file could not be parsed for its status"
            [ "$s_status" != Draft ] || status=Draft
          done
        fi
      fi
      [ "$status" = Draft ] || continue
      ;;
    *) f=$line ;;
  esac
  [ -e "$root/$f" ] || [ -L "$root/$f" ] || continue
  # A tracked symlink could print a file from outside the tree, or never end.
  [ ! -L "$root/$f" ] || fail_closed "a tracked file is a symlink, refusing to follow it"
  [ -f "$root/$f" ] || fail_closed "a tracked file is not a regular file"
  [ -r "$root/$f" ] || fail_closed "a tracked file is unreadable"
  printf '%s\n' "$f" >>"$work/list"
done <"$work/candidates"

[ -s "$work/list" ] || fail_closed "the scan reached no files, a broken enumeration rather than a clean tree"

CC_ROOT=$root CC_LIST=$work/list CC_EXEMPT=$exempt CC_ME=$me
export CC_ROOT CC_LIST CC_EXEMPT CC_ME
awk '
  function clean(s) { gsub(/[\001-\037\177\200-\237]/, "", s); return s }
  function indent(s) { match(s, /^ */); return RLENGTH }
  function is_item(s) { return s ~ /^ *([-*+]|[0-9]+[.)])[ \t]+[^ \t]/ && s !~ /^ *(\* *\* *\*[ *]*|- *- *-[ -]*|_ *_ *_[ _]*)$/ }
  function is_table(s) { return s ~ /^ *\|/ }
  function is_heading(s) { return s ~ /^(   |  | )?#/ }
  function words(   i, nw) {
    nw = split("two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty", w, " ")
    for (i = 1; i <= nw; i++) wv[w[i]] = i + 1
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
      if (prev ~ /^(tasks?|steps?|phases?|sections?|waves?|stages?|rounds?|versions?|lines?|items?|prs?|issues?|runs?|§)$/) continue
      if (k + 0 < 2) continue
      if (!n || v != k + 0) { n++; v = k + 0 }
    }
    return n == 1 ? v : 0
  }
  # Abbreviation dots, code spans and parentheses are masked, length kept, so
  # no sentence ends inside them and the cut lands in s itself.
  function blank(s, re,   out, seg, end, keep) {
    out = ""
    while (match(s, re)) {
      seg = substr(s, RSTART, RLENGTH); end = substr(seg, length(seg) - 1)
      keep = end ~ /^[.!?][)]$/ && substr(seg, length(seg) - 3, 2) != ".." && substr(s, RSTART + RLENGTH) !~ /^[)"*_]*[ \t]+[a-z]/
      gsub(/[.!?;]/, "_", seg)
      if (keep) seg = substr(seg, 1, length(seg) - 2) end
      out = out substr(s, 1, RSTART - 1) seg; s = substr(s, RSTART + RLENGTH)
    }
    return out s
  }
  function mask(s) {
    s = blank(s, "(^|[^A-Za-z])(e[.]g|i[.]e|etc|vs)[.]")
    s = blank(s, "`[^`]*`")
    return blank(s, "[(][^()]*[)]")
  }
  function last_sentence(s,   m, start) {
    m = mask(s); start = 1
    while (match(substr(m, start), /([.!?][)"*_]*|;)[ \t]+[^ \t]/)) start += RSTART + RLENGTH - 2
    return substr(s, start)
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
    if (c >= 2 && L[j + 1] ~ /^ *\| *:?-+:? *(\||$)/) c -= 2
    return c
  }
  # A fence closes only on a bare run of its own character at least as long.
  function scan(path, file,   r, line, i, s, k, j, text, sent, want, got, fence, run, key, hit) {
    n = 0; fence = ""
    while ((r = (getline line < path)) > 0) {
      sub(/\r$/, "", line)
      L[++n] = line; code[n] = 0
      if (fence != "") {
        code[n] = 1
        if (match(line, /^ *(```+|~~~+)[ \t]*$/)) {
          run = substr(line, RSTART, RLENGTH); gsub(/[ \t]/, "", run)
          if (substr(run, 1, 1) == substr(fence, 1, 1) && length(run) >= length(fence)) fence = ""
        }
        continue
      }
      if (line ~ /^ *(```+[^`]*|~~~+.*)$/ && match(line, /^ *(```+|~~~+)/)) { code[n] = 1; fence = substr(line, RSTART, RLENGTH); gsub(/ /, "", fence) }
    }
    close(path)
    if (r < 0) { unreadable = 1; return }
    for (i = 1; i <= n; i++) {
      if (code[i] || L[i] !~ /:[ \t]*$/ || is_heading(L[i]) || is_table(L[i])) continue
      j = i + 1
      if (j <= n && L[j] ~ /^[ \t]*$/) j++
      if (j > n || code[j] || !(is_item(L[j]) || is_table(L[j]))) continue
      s = i
      if (!is_item(L[i]))
        for (k = i - 1; k >= 1 && !code[k] && L[k] !~ /^[ \t]*$/ && !is_heading(L[k]) && !is_table(L[k]); k--) { s = k; if (is_item(L[k])) break }
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
      for (key in ex) {
        split(key, p, "\t")
        if (p[1] != file || !index(sent, p[2])) continue
        if (key in used) { printf "%s: %s: exemption %s clears more than one finding\n", ENVIRON["CC_ME"], clean(file), clean(p[2]); bad = 1; continue }
        used[key] = 1; hit = 1
      }
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
      if (split(l, p, "\t") != 3 || p[1] == "" || p[2] == "" || p[3] == "" || ((p[1] "\t" p[2]) in ex)) { malformed = 1; exit }
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
' >"$work/out" </dev/null
rc=$?
cat "$work/out"
case $rc in
  0) printf '%s: clean (%s files)\n' "$me" "$(wc -l <"$work/list" | tr -d ' ')" ;;
  1) ;;
  *) exit 2 ;;
esac
exit "$rc"
