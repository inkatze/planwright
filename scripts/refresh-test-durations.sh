#!/bin/bash
# Regenerate the duration table scripts/run-tests.sh orders its queue by
# (config/test-durations.tsv): one `<file><TAB><seconds>` row per test file,
# longest first. The runner dispatches the longest expected files first so no
# slow file is left running alone at the end of the suite; the table decides
# order only, never which files run or any budget.
#
# Two sources, told apart by their first line:
#   - a timing report scripts/run-tests.sh persisted (tests/.timing-report.tsv,
#     version 2): each file row's execution time, never its pool wait. The
#     report records no verdicts and is written for failing runs too, so use
#     only a green run's report: a file that failed early would be ranked as
#     cheap. One shard's report (its header names the shard) is refused, since
#     it times only that shard's files;
#   - anything else is read as a log carrying check-test-time's ranked table,
#     such as a CI job log (`gh run view <id> --log`), whose CI mode prints
#     every file. Step prefixes and colour codes are tolerated; only
#     `<seconds>s  <file>.sh` cells are read.
# Refresh from the reference runner (the CI log), not a contended dev box:
# the order wants the relative cost each file has where the budget is judged.
#
# Several sources (the check job logs of several sharded runs, say) refresh
# the table together: each file takes the median of the times the sources
# give it, the mean of the middle two for an even count, so one runner that
# ran slow or fast does not move the table. A file one source timed keeps
# that time. Every source is checked as a lone one would be, and one refused
# source refuses the refresh.
#
# Within a source, rows are kept only for files the suite has and the first
# row per file wins. Discovered files no source timed are named on stderr
# (the runner queues those ahead of every timed one). A source yielding no
# usable row, or
# a ranked table check-test-time cut short (its local mode without --all) or
# holding fewer rows than its header announces (an interrupted log), is
# refused and the table left as it was. The table is written atomically.
#
# Usage: refresh-test-durations.sh [--suite <dir>] [--out <path>] <source>...
#        (defaults: <repo-root>/tests, <repo-root>/config/test-durations.tsv)
# Exit:  0 written · 2 usage error, unreadable source, a ranked table cut
#        short, no usable row, or a table that could not be written
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
fi

die() {
  printf 'refresh-test-durations: %s\n' "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: refresh-test-durations.sh [--suite <dir>] [--out <path>] <source>...

Rewrites the duration table scripts/run-tests.sh orders its queue by, from a
timing report the runner persisted or a log carrying check-test-time's ranked
table (a CI job log). With several sources, each file takes the median of
their times. Ordering data only; it gates nothing.

  --suite   the test directory whose *.sh files the table may name
            (default: <repo>/tests)
  --out     the table to write (default: <repo>/config/test-durations.tsv)
EOF
}

suite=""
out=""
srcs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --suite | --out)
      [ "$#" -ge 2 ] || die "$1 needs a value (see --help)"
      case "$1" in
        --suite) suite="$2" ;;
        --out) out="$2" ;;
      esac
      shift 2
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    -*) die "unknown option: $(sanitize_printable "$1" "(unprintable)") (see --help)" ;;
    *)
      srcs+=("$1")
      shift
      ;;
  esac
done
[ "${#srcs[@]}" -gt 0 ] || die "a source file is required (see --help)"
[ -n "$suite" ] || suite="$repo_root/tests"
[ -n "$out" ] || out="$repo_root/config/test-durations.tsv"
k=0
for src in "${srcs[@]}"; do
  safe_src="$(sanitize_printable "$src" "(unprintable path)")"
  [ -f "$src" ] && [ -r "$src" ] || die "source not readable: $safe_src"
  # The same run counted twice would outvote the others in the median, whether
  # named twice or downloaded twice: two runs' logs never match byte for byte.
  j=0
  while [ "$j" -lt "$k" ]; do
    [ ! "${srcs[j]}" -ef "$src" ] || die "source given twice: $safe_src"
    ! cmp -s "${srcs[j]}" "$src" || die "source given twice (same content as an earlier one): $safe_src"
    j=$((j + 1))
  done
  k=$((k + 1))
  # check-test-time's local mode prints only the slowest few rows; a table
  # built from that would queue every file it left out ahead of the slowest
  # ones.
  if grep -q 'more under budget; --all lists them' <"$src"; then
    die "the ranked table in $safe_src is cut short (check-test-time without --all); use a CI log or a timing report"
  fi
  # One shard's report times only that shard's files; the CI check job's log
  # carries the ranked table over every shard.
  src_shard="$(awk -F'\t' 'NR == 1 && $1 == "planwright-test-timing" {
      for (i = 3; i <= NF; i++) if ($i ~ /^shard=[0-9]+\/[0-9]+$/) { sub(/^shard=/, "", $i); print $i }
    }
    { exit }' <"$src")"
  if [ -n "$src_shard" ]; then
    die "$safe_src is the timing report of shard $src_shard only; use the ci workflow's check job log, whose ranked table covers every shard"
  fi
done
[ -d "$suite" ] || die "suite directory not found: $(sanitize_printable "$suite" "(unprintable path)")"
# mv onto a directory would drop the staged table inside it and report success.
[ ! -d "$out" ] || die "--out is a directory, not a table path: $(sanitize_printable "$out" "(unprintable path)")"

work="$(mktemp -d "${TMPDIR:-/tmp}/refresh-test-durations.XXXXXX")" \
  || die "could not create a temporary directory"
out_tmp=""
trap 'rm -rf "$work"; [ -z "$out_tmp" ] || rm -f "$out_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

: >"$work/discovered"
for f in "$suite"/*.sh; do
  [ -f "$f" ] || continue
  printf '%s\n' "${f##*/}" >>"$work/discovered"
done

# Emits `<name><TAB><seconds>` per usable source row, first row per name, and
# records the ranked table's announced and seen sizes for the check below.
: >"$work/kept"
for src in "${srcs[@]}"; do
  safe_src="$(sanitize_printable "$src" "(unprintable path)")"
  RD_DISCOVERED="$work/discovered" RD_RANKED="$work/ranked" awk -F'\t' '
  BEGIN {
    # Through ENVIRON, never -v, which would expand backslash escapes in a
    # TMPDIR.
    discovered = ENVIRON["RD_DISCOVERED"]
    while ((getline n < discovered) > 0) want[n] = 1
    close(discovered)
    num = "^[0-9]+(\\.[0-9]+)?$"
  }
  NR == 1 { report = ($1 == "planwright-test-timing" && $2 == "2") }
  report {
    if ($1 == "file" && NF == 4 && $3 ~ num) keep($2, $3)
    next
  }
  {
    line = $0
    gsub(/\033\[[0-9;]*m/, "", line)
    if (match(line, /check-test-time: [0-9]+ files ranked slowest-first/)) {
      split(substr(line, RSTART, RLENGTH), hdr, " ")
      announced = hdr[2] + 0
    }
    if (match(line, /[0-9]+(\.[0-9]+)?s  [A-Za-z0-9._ -]+\.sh( |$)/)) {
      cell = substr(line, RSTART, RLENGTH)
      sub(/ $/, "", cell)
      secs = cell
      sub(/s  .*/, "", secs)
      name = cell
      sub(/^[0-9.]+s  /, "", name)
      if (!(name in ranked)) {
        ranked[name] = 1
        nranked++
      }
      keep(name, secs)
    }
  }
  function keep(name, secs) {
    if ((name in want) && !(name in seen)) {
      seen[name] = 1
      print name "\t" secs
    }
  }
  END { print announced + 0, nranked + 0 > ENVIRON["RD_RANKED"] }
' <"$src" >"$work/src-rows" || die "could not read $safe_src"
  read -r announced nranked <"$work/ranked" || die "could not read $safe_src"
  if [ "$nranked" -lt "$announced" ]; then
    die "$safe_src announces $announced files ranked but lists $nranked (an interrupted or clipped log?); table left unchanged"
  fi
  # Checked per source: among good ones, an empty one would otherwise drop out
  # unnoticed and leave the median to the rest.
  [ -s "$work/src-rows" ] \
    || die "no timed test file found in $safe_src; table left unchanged"
  cat "$work/src-rows" >>"$work/kept" || die "could not read $safe_src"
done
# The median per file, its times sorted in place. A lone source passes each
# time through as written.
awk -F'\t' '
  { n[$1]++; v[$1, n[$1]] = $2 }
  END {
    for (name in n) {
      c = n[name]
      for (i = 2; i <= c; i++) {
        x = v[name, i]
        for (j = i - 1; j >= 1 && v[name, j] + 0 > x + 0; j--) v[name, j + 1] = v[name, j]
        v[name, j + 1] = x
      }
      if (c % 2) m = v[name, (c + 1) / 2]
      else m = sprintf("%.3f", (v[name, c / 2] + v[name, c / 2 + 1]) / 2)
      print name "\t" m
    }
  }
' <"$work/kept" >"$work/median" || die "could not combine the sources' rows"
# A redirect rather than an operand: awk takes an operand shaped like
# `name=value` as an assignment, not a file. Sorted only once awk has
# succeeded, so a failure partway never writes a partial table.
sort -t "$(printf '\t')" -k2,2nr -k1,1 "$work/median" >"$work/rows" \
  || die "could not sort the source's rows"

{
  cat <<'EOF'
# Expected per-file seconds for scripts/run-tests.sh's queue order: the runner
# dispatches the longest first so no slow file is left running alone at the
# end of the suite. Ordering only: nothing here gates, budgets, or selects a
# test (config/test-time-budget.yml holds the budgets). A test file with no row
# runs ahead of every timed one.
#
# Generated by scripts/refresh-test-durations.sh; regenerate rather than
# hand-edit, from reference-runner check:test-time logs (`gh run view --job
# <id> --log`, CI mode prints every file; several runs give each file its
# median) or a tests/.timing-report.tsv.
EOF
  cat "$work/rows"
} >"$work/table" || die "could not stage the table"

out_tmp="$(mktemp "$out.XXXXXX" 2>/dev/null)" \
  || die "could not stage the table beside $(sanitize_printable "$out" "(unprintable path)")"
# mktemp creates the file owner-only; the table is ordinary repository content.
if ! cat "$work/table" >"$out_tmp" || ! chmod 644 "$out_tmp" || ! mv -f "$out_tmp" "$out"; then
  rm -f "$out_tmp"
  die "could not write $(sanitize_printable "$out" "(unprintable path)")"
fi

rows="$(wc -l <"$work/rows" | tr -d ' ')"
untimed="$(cut -f1 "$work/rows" | sort | comm -13 - "$work/discovered" | tr '\n' ' ')"
from=""
[ "${#srcs[@]}" -eq 1 ] || from=" from ${#srcs[@]} sources"
printf 'refresh-test-durations: wrote %s row(s)%s to %s\n' "$rows" "$from" "$(sanitize_printable "$out" "(unprintable path)")"
if [ -n "$untimed" ]; then
  printf 'refresh-test-durations: untimed (queued first): %s\n' "$(sanitize_printable "$untimed" "(unprintable)")" >&2
fi
