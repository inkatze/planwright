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
# A refusal names the row and the rule, never the matched text.
#
# What this screen cannot see: whether a gist reproduces reviewer text. That
# needs the original comment, which only the refresh holds, so the refresh
# checks it at write time (review-backtest-refresh.sh).
#
# Usage:
#   review-corpus-screen.sh [--names <file>] [--require-names] <corpus.tsv>
#
# Exit codes: 0 every row passes; 1 one or more rows refused (each named on
# stderr); 2 usage error, an unreadable corpus or list, a wrong header, or a
# corpus with zero rows.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-corpus-screen
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

usage() {
  printf '%s\n' "usage: $prog [--names <file>] [--require-names] <corpus.tsv>" >&2
  exit 2
}

names=
require_names=0
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
    -h | --help) usage ;;
    -*) usage ;;
    *)
      [ -z "$corpus" ] || usage
      corpus=$1
      shift
      ;;
  esac
done
[ -n "$corpus" ] || usage

if [ ! -f "$corpus" ] || [ ! -r "$corpus" ]; then
  printf '%s\n' "$prog: corpus file not readable" >&2
  exit 2
fi
if [ -n "$names" ]; then
  if [ ! -f "$names" ] || [ ! -r "$names" ]; then
    printf '%s\n' "$prog: product-name list not readable" >&2
    exit 2
  fi
elif [ "$require_names" -eq 1 ]; then
  printf '%s\n' "$prog: --require-names given but no product-name list (--names)" >&2
  exit 2
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
function hygiene(field, text,    t, i, n, nm, pre, post, s, off, at) {
  if (text ~ /(^|[^A-Za-z0-9_.-])@[A-Za-z0-9][A-Za-z0-9-]*/ || text ~ /\[bot\]/)
    refuse(field " carries a reviewer login or bot marker")
  if (text ~ /[A-Za-z][A-Za-z0-9+.-]*:\/\//)
    refuse(field " carries a url")
  if (text ~ /(^|[^A-Za-z0-9_.-])(\/home\/|\/Users\/|\/root\/|~\/)/)
    refuse(field " carries a home path")
  t = tolower(text)
  for (i = 1; i <= nnames; i++) {
    nm = name[i]
    s = t
    off = 0
    while ((n = index(s, nm)) > 0) {
      at = off + n
      pre = (at == 1) ? "" : substr(t, at - 1, 1)
      post = substr(t, at + length(nm), 1)
      if (pre !~ /[a-z0-9]/ && post !~ /[a-z0-9]/) {
        refuse(field " names a listed product")
        return
      }
      off = at
      s = substr(t, off + 1)
    }
  }
}
BEGIN {
  if (namesf != "") {
    while ((getline line < namesf) > 0) {
      sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line)
      if (line != "" && substr(line, 1, 1) != "#") name[++nnames] = tolower(line)
    }
    close(namesf)
  }
}
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
