#!/bin/sh
# review-corpus-screen.sh — the schema and hygiene screen over a backtest
# corpus file (review-effectiveness REQ-H1.2, REQ-E1.7, D-7, D-16).
#
# The corpus is committed, public, and read by people and by the replay
# harness, so every row must carry only this public repository's data: a PR
# number, a commit id, a repository-relative path and line, the labels, and a
# paraphrased gist. This screen refuses a row that breaks the schema or could
# carry something else: a reviewer login or bot marker, a URL, a home-directory
# path, an overlong gist (a paraphrase is one short line; a pasted comment is
# not), or a name from the product-name list.
#
# THE PRODUCT-NAME LIST IS MACHINE-LOCAL. Which products count as the bot
# reviewer or an external backend is never written into a committed file, so
# the list is passed with --names (the refresh resolves it from the
# machine-local state home and requires it). Without --names the rest of the
# screen runs and the product check is announced as skipped, which is how CI,
# holding no list, runs it. A list is one name per line; blank lines and lines
# starting with `#` are ignored; matching is case-insensitive and whole-word.
# A list with no names is refused like a missing one. A refusal names the row
# and the rule, never the matched text.
#
# What this screen cannot see: whether a gist reproduces reviewer text. That
# needs the original comment, which only the refresh holds, so the refresh
# checks it at write time (review-backtest-refresh.sh).
#
# --text runs only the product-name check, over prose rather than a corpus:
# every regular file under each path given (directories walked recursively,
# a symlink anywhere or a file holding a NUL byte refused), its name and
# each line. It is the operator-local screen over committed prose such as the
# observation fragments, so it requires the list; a refusal names the file and
# line, never the matched text, though a file-name refusal's path carries it.
#
# Usage:
#   review-corpus-screen.sh [--names <file>] [--require-names] <corpus.tsv>
#   review-corpus-screen.sh --text --names <file> <path>...
#
# Exit codes: 0 every row (or file) passes; 1 one or more refused (each named
# on stderr); 2 usage error, an unreadable corpus, list or path, a wrong
# header, or a corpus with zero rows (or paths holding no files).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-corpus-screen
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

usage() {
  printf '%s\n' "usage: $prog [--names <file>] [--require-names] <corpus.tsv>" \
    "       $prog --text --names <file> <path>..." >&2
  exit 2
}

names=
require_names=0
text=0
corpus=
while [ $# -gt 0 ]; do
  case $1 in
    --names)
      [ $# -ge 2 ] || usage
      names=$2
      shift 2
      ;;
    --require-names)
      require_names=1
      shift
      ;;
    --text)
      text=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -h | --help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
if [ "$text" -eq 0 ]; then
  [ $# -eq 1 ] || usage
  corpus=$1
  if [ ! -f "$corpus" ] || [ ! -r "$corpus" ]; then
    printf '%s\n' "$prog: corpus file not readable" >&2
    exit 2
  fi
fi
if [ -n "$names" ]; then
  if [ ! -f "$names" ] || [ ! -r "$names" ]; then
    printf '%s\n' "$prog: product-name list not readable" >&2
    exit 2
  fi
elif [ "$text" -eq 1 ]; then
  printf '%s\n' "$prog: --text needs a product-name list (--names)" >&2
  exit 2
elif [ "$require_names" -eq 1 ]; then
  printf '%s\n' "$prog: --require-names given but no product-name list (--names)" >&2
  exit 2
fi
if [ -n "$names" ]; then
  usable=$(awk '{ sub(/^[ \t]+/, ""); sub(/[ \t\r]+$/, "") } $0 != "" && substr($0, 1, 1) != "#" { n++ } END { print n + 0 }' "$names")
  # An empty list would pass every row while claiming the product check ran.
  [ "$usable" -gt 0 ] || {
    printf '%s\n' "$prog: the product-name list holds no names" >&2
    exit 2
  }
fi

# The list loader and the case-insensitive whole-word matcher both modes share.
# A name matches only where the bytes either side are not [a-z0-9], so a name
# inside a longer word passes.
names_awk='
function loadnames(   line) {
  if (namesf == "") return
  while ((getline line < namesf) > 0) {
    sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line)
    if (line != "" && substr(line, 1, 1) != "#") name[++nnames] = tolower(line)
  }
  close(namesf)
}
function named(text,    t, i, n, nm, pre, post, s, off, at) {
  t = tolower(text)
  for (i = 1; i <= nnames; i++) {
    nm = name[i]
    s = t
    off = 0
    while ((n = index(s, nm)) > 0) {
      at = off + n
      pre = (at == 1) ? "" : substr(t, at - 1, 1)
      post = substr(t, at + length(nm), 1)
      if (pre !~ /[a-z0-9]/ && post !~ /[a-z0-9]/) return 1
      off = at
      s = substr(t, off + 1)
    }
  }
  return 0
}
'

if [ "$text" -eq 1 ]; then
  T=$(mktemp -d "${TMPDIR:-/tmp}/rcs.XXXXXX") || exit 2
  trap 'rm -rf "$T"' EXIT
  : >"$T/files"
  for p in "$@"; do
    # A leading ./ keeps a path named - from reading as stdin in awk's getline.
    case $p in /*) ;; *) p=./$p ;; esac
    # find -type f skips a symlink, so one would pass unscreened; refuse it
    # rather than read through it, as check-obs.sh does. A trailing slash
    # would make -L test the link's target, so it is tested without one.
    q=$p
    while :; do case $q in ?*/) q=${q%/} ;; *) break ;; esac; done
    if [ -L "$q" ]; then
      printf '%s\n' "$prog: a path is a symlink" >&2
      exit 2
    fi
    if [ -d "$p" ]; then
      # A subdirectory find cannot read would otherwise drop out unscreened.
      find "$p" ! -type d ! -type f -print >"$T/found" || {
        printf '%s\n' "$prog: path not readable" >&2
        exit 2
      }
      if [ -s "$T/found" ]; then
        printf '%s\n' "$prog: a path holds a symlink or other non-regular file" >&2
        exit 2
      fi
      find "$p" -type f -print >"$T/found" || {
        printf '%s\n' "$prog: path not readable" >&2
        exit 2
      }
      sort "$T/found" >>"$T/files"
    elif [ -f "$p" ] && [ -r "$p" ]; then
      printf '%s\n' "$p" >>"$T/files"
    else
      printf '%s\n' "$prog: path not readable" >&2
      exit 2
    fi
  done
  nfiles=$(awk 'END { print NR + 0 }' "$T/files")
  if [ "$nfiles" -eq 0 ]; then
    printf '%s\n' "$prog: the paths hold no files" >&2
    exit 2
  fi
  # awk ends a line at a NUL on some implementations, so a name after one
  # would pass unseen; a file holding one is refused rather than screened.
  # One pass over every file finds whether any holds a NUL (a per-file screen
  # costs seconds over the fragment tree); only then does the shared per-file
  # screen run, to name the file. An unreadable file drops out of both counts
  # alike and is refused by the read below.
  total=$(tr '\n' '\000' <"$T/files" | xargs -0 cat 2>/dev/null | wc -c) || total=
  kept=$(tr '\n' '\000' <"$T/files" | xargs -0 cat 2>/dev/null | tr -d '\000' | wc -c) || kept=
  if [ -z "$total" ] || [ -z "$kept" ]; then
    printf '%s\n' "$prog: the NUL screen could not read the files" >&2
    exit 2
  fi
  if [ "$total" -ne "$kept" ]; then
    # shellcheck source=scripts/spec-parse.sh
    . "$here/spec-parse.sh" || exit 2
    while IFS= read -r f; do
      spec_parse__nul_screen "$f" || exit 2
    done <"$T/files"
    printf '%s\n' "$prog: a file holds a NUL byte" >&2
    exit 2
  fi
  # Each file is read as data: its name screened in BEGIN (an empty file has
  # no first record), then every line. Every non-printable byte in the path,
  # C1 included, is masked before it reaches stderr.
  set +e
  awk -v prog="$prog" -v namesf="$names" -v list="$T/files" "$names_awk"'
function show(p) { gsub(/[^[:print:]]/, "?", p); return p }
function base(p) { sub(/.*\//, "", p); return p }
BEGIN {
  loadnames()
  while ((getline f < list) > 0) {
    if (named(base(f))) { printf "%s: %s: file name names a listed product\n", prog, show(f) > "/dev/stderr"; bad++ }
    while ((r = (getline line < f)) > 0) {
      n++
      if (named(line)) { printf "%s: %s:%d: names a listed product\n", prog, show(f), n > "/dev/stderr"; bad++ }
    }
    if (r < 0) { printf "%s: %s: not readable\n", prog, show(f) > "/dev/stderr"; err = 1 }
    close(f)
    n = 0
  }
  close(list)
  if (err) exit 2
  if (bad > 0) { printf "%s: %d refusal(s)\n", prog, bad > "/dev/stderr"; exit 1 }
}'
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || exit "$rc"
  printf '%s\n' "$prog: $nfiles file(s) pass"
  exit 0
fi

first=$(sed -n 1p "$corpus")
if [ "$first" != "$RBT_HEADER" ]; then
  printf '%s\n' "$prog: header does not match the corpus schema" >&2
  exit 2
fi
rows=$(awk 'NR > 1 && $0 != "" { n++ } END { print n + 0 }' "$corpus")
if [ "$rows" -eq 0 ]; then
  printf '%s\n' "$prog: corpus holds zero rows" >&2
  exit 2
fi

if [ -z "$names" ]; then
  printf '%s\n' "$prog: product-name screen skipped (no name list; the refresh requires one)" >&2
fi

# One awk pass over the corpus, the list read in BEGIN. Every message carries
# the row id only when it is well formed, else the line number, so no field
# text reaches the terminal.
set +e
awk -F '\t' \
  -v reasons="$RBT_REASONS" -v categories="$RBT_CATEGORIES" \
  -v sources="$RBT_LABEL_SOURCES" -v prog="$prog" -v namesf="$names" '
function inlist(w, l) { return index(" " l " ", " " w " ") > 0 }
function refuse(rule) {
  printf "%s: %s: %s\n", prog, where, rule > "/dev/stderr"
  bad++
}
function hygiene(field, text) {
  if (text ~ /(^|[^A-Za-z0-9_.-])@[A-Za-z0-9][A-Za-z0-9-]*/ || text ~ /\[bot\]/)
    refuse(field " carries a reviewer login or bot marker")
  if (text ~ /[A-Za-z][A-Za-z0-9+.-]*:\/\//)
    refuse(field " carries a url")
  if (text ~ /(^|[^A-Za-z0-9_.-])(\/home\/|\/Users\/|\/root\/|~\/)/)
    refuse(field " carries a home path")
  if (named(text)) refuse(field " names a listed product")
}
'"$names_awk"'
BEGIN { loadnames() }
FNR == 1 { next }
$0 == "" { next }
{
  where = "line " FNR
  if ($1 ~ /^r[0-9][0-9][0-9][0-9]+$/) where = "row " $1
  if (NF != 11) { refuse("expected 11 fields, got " NF); next }
  if ($1 !~ /^r[0-9][0-9][0-9][0-9]+$/) refuse("id is not r<digits>")
  else if ($1 in seen) refuse("duplicate id")
  seen[$1] = 1
  if ($2 !~ /^[1-9][0-9]*$/) refuse("pr is not a positive integer")
  if ($3 !~ /^[0-9a-f]+$/ || length($3) != 40) refuse("commit is not a 40-hex id")
  p = $4
  if (p == "" || p ~ /^\// || p ~ /^~/ || p ~ /^-/ || p ~ /(^|\/)\.\.(\/|$)/ || p ~ /[^ -~]/)
    refuse("path is not repository-relative")
  if ($5 !~ /^[1-9][0-9]*$/) refuse("line is not a positive integer")
  if (!inlist($6, categories)) refuse("category is not in the vocabulary")
  if (!inlist($7, reasons)) refuse("reason is not in the vocabulary")
  if ($8 != "yes" && $8 != "no") refuse("replayable is not yes or no")
  if (!inlist($9, sources)) refuse("label_source is not in the vocabulary")
  if ($9 == "fallback" && $7 != "other") refuse("a fallback row must carry reason other")
  if ($9 == "declined-log" && $7 != "declined") refuse("a declined-log row must carry reason declined")
  if ($10 == "" || $10 == "-") refuse("gist is empty")
  else if (length($10) > 240) refuse("gist is longer than 240 characters")
  if ($7 == "declined") {
    if ($11 == "" || $11 == "-") refuse("a declined row needs its dismissal")
    else if (length($11) > 240) refuse("dismissal is longer than 240 characters")
  } else if ($11 != "-") refuse("dismissal is set on a row that is not declined")
  hygiene("gist", $10)
  if ($11 != "-") hygiene("dismissal", $11)
  hygiene("path", $4)
}
END {
  if (bad > 0) { printf "%s: %d refusal(s)\n", prog, bad > "/dev/stderr"; exit 1 }
}
' "$corpus"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  exit 1
fi
printf '%s\n' "$prog: $rows row(s) pass"
