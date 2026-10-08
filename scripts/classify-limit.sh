#!/bin/sh
# classify-limit.sh — is this captured output a vendor's limit refusal?
# Matches the text against the recognizers the vendor's adapter declares
# (scripts/resolve-vendors.sh) as fixed, case-sensitive substrings; no
# recognizer value is ever executed, evaluated, or used as a pattern.
# docs/quota.md describes the adapter contract; the step runner and the
# worker completion readers are the callers.
#
# Usage:
#   classify-limit.sh --vendor <id> [--input <file>] [--now <epoch>]
#     --vendor   the vendor id, checked against the step-id grammar first
#     --input    the captured output; stdin when absent
#     --now      the clock, in epoch seconds (default: now); fixtures pin it
#
# A match prints, one `<key><TAB><value>` line each:
#   outcome    limited
#   vendor     <id>
#   recognizer <vendor>.<name>
#   reset      <epoch>, only when a stated reset time is accepted
#   excerpt    the screened excerpt, one line per excerpt line
# The winning recognizer is the first declared one matching the earliest
# matching line. The excerpt is that line (a long line cut to a window that
# keeps the match) as scripts/step-record.sh's `excerpt` verb screens and
# bounds a record excerpt; the whole line is screened first, and a line the
# screen flags withholds the excerpt whatever the window holds. The reset time is read from the first occurrence of
# the recognizer's `reset-after` prefix in the output: the word right after
# it (leading blanks skipped, a trailing `.` dropped) is accepted as epoch
# seconds (at most 15 digits) or an ISO-8601 UTC timestamp
# YYYY-MM-DDTHH:MM:SS[.fraction]Z, and only when it lies after --now and no
# further out than the throttle's hold ceiling (`fleet-throttle.sh
# ceiling`); any other value is no stated reset time.
#
# Exit: 0 limited · 1 no recognizer matched (nothing printed) · 2 usage ·
# 3 no resolved adapter declares the vendor · 4/5 propagated from the vendors
# resolver (a malformed repo-tracked catalog, a broken install) · 6 a runtime
# failure (unreadable input, no clock, an adapter or excerpt that could not
# be produced).
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

prog=classify-limit
TAB=$(printf '\t')

usage() {
  printf '%s\n' "usage: classify-limit.sh --vendor <id> [--input <file>] [--now <epoch>]" >&2
  exit 2
}
die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

vendor=""
vendor_set=0
input=""
input_set=0
now=""
now_set=0
while [ $# -gt 0 ]; do
  case $1 in
    --vendor | --input | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --vendor)
          vendor=$2
          vendor_set=1
          ;;
        --input)
          input=$2
          input_set=1
          ;;
        --now)
          now=$2
          now_set=1
          ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ "$vendor_set" -eq 1 ] || usage
case $vendor in
  "" | [!a-z]* | *[!a-z0-9-]*) die 2 "--vendor is outside the step-id grammar" ;;
esac
[ "${#vendor}" -le 64 ] || die 2 "--vendor is outside the step-id grammar"
if [ "$input_set" -eq 1 ] && [ -z "$input" ]; then
  die 2 "--input is empty"
fi
if [ "$now_set" -eq 1 ]; then
  case $now in "" | *[!0-9]*) die 2 "--now is not epoch seconds" ;; esac
  [ "${#now}" -le 15 ] || die 2 "--now is not epoch seconds"
else
  now=$(date +%s)
  case $now in "" | *[!0-9]*) die 6 "cannot read the clock" ;; esac
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6
work=$(mktemp -d "${TMPDIR:-/tmp}/classify-limit.XXXXXX") || die 6 "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 6' HUP INT TERM

if [ -n "$input" ]; then
  [ -f "$input" ] && [ -r "$input" ] || die 6 "--input is not a readable file"
  tr -d '\000' <"$input" >"$work/in" || die 6 "cannot read the input"
else
  tr -d '\000' >"$work/in" || die 6 "cannot read the input"
fi

rc=0
/bin/bash "$script_dir/resolve-vendors.sh" --vendor "$vendor" >"$work/adapter" 2>"$work/err" || rc=$?
tr -d '\000-\011\013-\037\177\200-\237' <"$work/err" >&2
case $rc in
  0) ;;
  3 | 4 | 5) exit "$rc" ;;
  6) die 6 "the vendors resolver could not print its resolution" ;;
  *) die 5 "the vendors resolver failed (exit $rc) (broken install)" ;;
esac

ceiling=$(/bin/sh "$script_dir/fleet-throttle.sh" ceiling) || die 5 "cannot read the throttle's hold ceiling (broken install)"
case $ceiling in "" | *[!0-9]*) die 5 "the throttle's hold ceiling is not a number (broken install)" ;; esac

# The values reach awk as file data, never through -v, which would expand
# backslash escapes in them.
awk -F "$TAB" -v now="$now" -v ceiling="$ceiling" -v linefile="$work/line" -v fullfile="$work/full" '
  # days_from_civil: days since 1970-01-01 for a proleptic Gregorian date.
  function days(y, m, d,   era, yoe, doy, doe) {
    y -= (m <= 2)
    era = int(y / 400)
    yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe - 719468
  }
  function mdays(y, m) {
    if (m == 2) return ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
    return (m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31
  }
  # epoch_of <word>: the accepted reset epoch, or -1.
  function epoch_of(w,   y, mo, d, h, mi, s) {
    if (w ~ /^[0-9]+$/) return (length(w) <= 15) ? w + 0 : -1
    if (w !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z$/) return -1
    y = substr(w, 1, 4) + 0; mo = substr(w, 6, 2) + 0; d = substr(w, 9, 2) + 0
    h = substr(w, 12, 2) + 0; mi = substr(w, 15, 2) + 0; s = substr(w, 18, 2) + 0
    if (mo < 1 || mo > 12 || d < 1 || d > mdays(y, mo) || h > 23 || mi > 59 || s > 59) return -1
    return days(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
  }
  FILENAME == ARGV[1] {
    if ($1 != "recognizer") next
    nr++
    name[nr] = $3
    pat[nr] = $4
    loc[nr] = ($5 == "-") ? "" : $5
    next
  }
  { line[++nl] = $0 }
  END {
    for (i = 1; i <= nl && !hit; i++)
      for (r = 1; r <= nr; r++)
        if ((p = index(line[i], pat[r])) > 0) { hit = r; at = i; break }
    if (!hit) exit 1
    l = line[at]
    print l > fullfile
    if (length(l) > 1900) {
      st = p - 800
      if (st < 1) st = 1
      l = substr(l, st, 1900)
    }
    print l > linefile
    print "recognizer\t" name[hit]
    if (loc[hit] == "") exit 0
    for (i = 1; i <= nl; i++) {
      if ((q = index(line[i], loc[hit])) == 0) continue
      rest = substr(line[i], q + length(loc[hit]))
      sub(/^[ \t]+/, "", rest)
      if (!match(rest, /^[0-9A-Za-z:.+-]+/)) exit 0
      w = substr(rest, 1, RLENGTH)
      sub(/[.]+$/, "", w)
      e = epoch_of(w)
      if (e > now + 0 && e <= now + ceiling) printf "reset\t%.0f\n", e
      exit 0
    }
  }
' "$work/adapter" "$work/in" >"$work/result"
case $? in
  0) ;;
  1) exit 1 ;;
  *) die 6 "the classifier failed" ;;
esac

# The whole matched line is screened before the window is cut, since a cut
# through a secret leaves a remainder the screen no longer recognizes.
excerpt=$(/bin/sh "$script_dir/step-record.sh" excerpt "$work/full") || die 6 "cannot build the excerpt"
case $excerpt in
  "[withheld: "*"]") ;;
  *) cmp -s "$work/full" "$work/line" || excerpt=$(/bin/sh "$script_dir/step-record.sh" excerpt "$work/line") || die 6 "cannot build the excerpt" ;;
esac
recognizer=$(sed -n "s/^recognizer$TAB//p" "$work/result")
reset=$(sed -n "s/^reset$TAB//p" "$work/result")
{
  printf 'outcome\tlimited\n'
  printf 'vendor\t%s\n' "$vendor"
  printf 'recognizer\t%s.%s\n' "$vendor" "$recognizer"
  [ -z "$reset" ] || printf 'reset\t%s\n' "$reset"
  printf '%s\n' "$excerpt" | sed "s/^/excerpt$TAB/"
} || die 6 "cannot print the classification"
