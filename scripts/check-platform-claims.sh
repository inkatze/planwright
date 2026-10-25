#!/bin/sh
# check-platform-claims.sh — guard the platform-claims register (inception
# Task 14; D-11, REQ-H1.4).
#
# planwright relies on a few facts about hosts it does not control (how Cowork
# runs a session, what a cloud sandbox keeps, what an API accepts). Those rot
# faster than code, so each one is recorded in docs/platform-claims.md with its
# source, the date it was last verified, and the date by which it must be
# verified again.
#
# Two modes:
#   default    the gate: a malformed register fails; a claim past its
#              re-verify date is named on a `due` line but does not fail, so
#              the suite never turns red on a calendar alone.
#   --strict   the release step: a due claim fails too. Re-verify it against
#              its source, then advance Verified and Re-verify-by.
#
# Usage:
#   check-platform-claims.sh [--strict] [--today YYYY-MM-DD] [--root <dir>] [<register>]
#
# <register> defaults to <root>/docs/platform-claims.md; <root> defaults to
# this checkout and is where each `Relied on by` path must exist.
#
# Output: `malformed<TAB><id><TAB><reason>` and `due<TAB><id><TAB><date><TAB>
#   <title>` lines, then a one-line summary.
# Exit: 0 clean (due claims allowed outside --strict) · 1 a malformed or
#   unreadable register, or a due claim under --strict · 2 usage.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: check-platform-claims.sh [--strict] [--today YYYY-MM-DD] [--root <dir>] [<register>]" >&2
  exit 2
}

valid_date() {
  case $1 in
    [0-9][0-9][0-9][0-9]-0[1-9]-[0-3][0-9] | [0-9][0-9][0-9][0-9]-1[0-2]-[0-3][0-9]) ;;
    *) return 1 ;;
  esac
  vd_day=${1##*-}
  vd_month=${1#*-}
  vd_month=${vd_month%-*}
  case $vd_day in
    0[1-9] | 1[0-9] | 2[0-8]) return 0 ;;
    29 | 30 | 31) ;;
    *) return 1 ;;
  esac
  case $vd_month in
    04 | 06 | 09 | 11) [ "$vd_day" != 31 ] ;;
    02)
      [ "$vd_day" = 29 ] || return 1
      # Leading zeros stripped: some shells read 0-led arithmetic as octal.
      vd_year=$(printf '%s\n' "${1%%-*}" | sed 's/^0*//')
      vd_year=${vd_year:-0}
      [ $((vd_year % 4)) -eq 0 ] && { [ $((vd_year % 100)) -ne 0 ] || [ $((vd_year % 400)) -eq 0 ]; }
      ;;
    *) return 0 ;;
  esac
}

# dnum <YYYY-MM-DD> — the date as an integer, for -gt comparison (POSIX test
# has no string ordering).
dnum() {
  printf '%s\n' "$1" | tr -d -
}

strict=0
today=
root=
reg=
while [ $# -gt 0 ]; do
  case $1 in
    --strict)
      strict=1
      shift
      ;;
    --today)
      [ $# -ge 2 ] || usage
      today=$2
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || usage
      root=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$reg" ] || usage
      reg=$1
      shift
      ;;
  esac
done

[ -n "$today" ] || today=$(date +%Y-%m-%d)
valid_date "$today" || usage
[ -n "$root" ] || root=$(cd "$(dirname "$0")/.." && pwd -P) || exit 2
[ -n "$reg" ] || reg=$root/docs/platform-claims.md

if [ ! -f "$reg" ] || [ ! -r "$reg" ]; then
  printf 'malformed\t-\tthe register is missing or unreadable: %s\n' "$reg"
  exit 1
fi

# One `entry` line per claim, tab-separated in field order, and a `malformed`
# line for each structural problem the parse alone can see. Dates and paths are
# checked below, in the shell, where the date rule lives once.
parsed=$(awk '
  # A tab is IFS whitespace to the reader below, so an empty field would
  # collapse and shift the rest; "-" holds its place and fails every check.
  function val(k) { return (k in V && V[k] != "") ? V[k] : "-" }
  function flush() {
    if (id == "") return
    for (i = 1; i <= nf; i++)
      if (!(F[i] in V) || V[F[i]] == "") print "malformed\t" id "\tmissing field " F[i]
    print "entry\t" id "\t" title "\t" val("Verified") "\t" val("Re-verify-by") "\t" val("Relied on by") "\t" val("Source")
    split("", V)
    id = ""
  }
  BEGIN { nf = split("Claim|Relied on by|Source|Verified|Re-verify-by", F, "|") }
  /^### / {
    flush()
    h = substr($0, 5)
    gsub(/\t/, " ", h)
    if (h !~ /^PC-[1-9][0-9]* — ./) { print "malformed\t-\theading is not ### PC-<n> — <title>: " h; next }
    id = h; sub(/ — .*/, "", id)
    title = h; sub(/^[^ ]* — /, "", title)
    if (id in SEEN) print "malformed\t" id "\tduplicate id"
    SEEN[id] = 1
    next
  }
  /^## / { flush(); next }
  id != "" && /^- \*\*[^*]+:\*\* / {
    k = $0; sub(/^- \*\*/, "", k); sub(/:\*\* .*/, "", k)
    v = $0; sub(/^- \*\*[^*]+:\*\* /, "", v)
    gsub(/\t/, " ", v)
    # Trimmed so a field holding only spaces reads as empty, hence missing.
    sub(/^ +/, "", v)
    sub(/ +$/, "", v)
    # A repeated field would let a later line silently mask a bad earlier one.
    if (k in V) print "malformed\t" id "\tduplicate field " k
    V[k] = v
  }
  END { flush() }
' "$reg") || {
  printf 'malformed\t-\tthe register could not be parsed\n'
  exit 1
}

bad=0
due=0
count=0
tab=$(printf '\t')
while IFS=$tab read -r kind id title verified reverify relied source; do
  case $kind in
    malformed)
      printf 'malformed\t%s\t%s\n' "$id" "$title"
      bad=$((bad + 1))
      continue
      ;;
    entry) ;;
    *) continue ;;
  esac
  count=$((count + 1))
  if ! valid_date "$verified"; then
    printf 'malformed\t%s\tVerified is not a YYYY-MM-DD date\n' "$id"
    bad=$((bad + 1))
  elif ! valid_date "$reverify"; then
    printf 'malformed\t%s\tRe-verify-by is not a YYYY-MM-DD date\n' "$id"
    bad=$((bad + 1))
  elif [ "$(dnum "$verified")" -gt "$(dnum "$today")" ]; then
    printf 'malformed\t%s\tVerified %s is later than today\n' "$id" "$verified"
    bad=$((bad + 1))
  elif ! [ "$(dnum "$reverify")" -gt "$(dnum "$verified")" ]; then
    printf 'malformed\t%s\tRe-verify-by must be later than Verified\n' "$id"
    bad=$((bad + 1))
  elif [ "$(dnum "$today")" -gt "$(dnum "$reverify")" ]; then
    printf 'due\t%s\t%s\t%s\n' "$id" "$reverify" "$title"
    due=$((due + 1))
  fi
  # markdownlint wants an autolink, so the angle brackets are optional.
  source=${source#<}
  source=${source%>}
  case $source in
    https://?*) ;;
    *)
      printf 'malformed\t%s\tSource must be an https URL\n' "$id"
      bad=$((bad + 1))
      ;;
  esac
  # The first code span names the file that relies on the claim; it must still
  # exist, or the register has drifted from the code.
  # shellcheck disable=SC2016 # the backticks are markdown, matched literally
  path=$(printf '%s\n' "$relied" | sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p')
  case $path in
    '' | /* | *..*)
      printf 'malformed\t%s\tRelied on by must name a repository path in backticks\n' "$id"
      bad=$((bad + 1))
      ;;
    *)
      if [ ! -e "$root/$path" ]; then
        printf 'malformed\t%s\tRelied on by names a path that does not exist: %s\n' "$id" "$path"
        bad=$((bad + 1))
      fi
      ;;
  esac
done <<EOF
$parsed
EOF

if [ "$count" -eq 0 ] && [ "$bad" -eq 0 ]; then
  printf 'malformed\t-\tthe register holds no claims\n'
  bad=1
fi

printf 'check-platform-claims: %s claim(s) checked, %s due, %s malformed\n' "$count" "$due" "$bad"
[ "$bad" -eq 0 ] || exit 1
if [ "$strict" -eq 1 ] && [ "$due" -gt 0 ]; then
  echo "check-platform-claims: re-verify each due claim against its source, then advance Verified and Re-verify-by" >&2
  exit 1
fi
exit 0
