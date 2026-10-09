#!/bin/bash
# Regenerate the duration table scripts/run-tests.sh orders its queue by
# (config/test-durations.tsv): one `<file><TAB><seconds>` row per test file,
# longest first. The runner dispatches the longest expected files first so no
# slow file is left running alone at the end of the suite; the table decides
# order only, never which files run or any budget.
#
# Two sources, told apart by their first line:
#   - a timing report scripts/run-tests.sh persisted (tests/.timing-report.tsv,
#     version 2): each file row's execution time, never its pool wait;
#   - anything else is read as a log carrying check-test-time's ranked table,
#     such as a CI job log (`gh run view <id> --log`), whose CI mode prints
#     every file. Step prefixes and colour codes are tolerated; only
#     `<seconds>s  <file>.sh` cells are read.
# Refresh from the reference runner (the CI log), not a contended dev box:
# the order wants the relative cost each file has where the budget is judged.
#
# Rows are kept only for files the suite has, the first row per file wins, and
# discovered files the source did not time are named on stderr (the runner
# queues those ahead of every timed one). A source yielding no usable row, or
# a ranked table check-test-time cut short (its local mode without --all), is
# refused and the table left as it was. The table is written atomically.
#
# Usage: refresh-test-durations.sh [--suite <dir>] [--out <path>] <source>
#        (defaults: <repo-root>/tests, <repo-root>/config/test-durations.tsv)
# Exit:  0 written · 2 usage error, unreadable source, no usable row, or a
#        table that could not be written
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
Usage: refresh-test-durations.sh [--suite <dir>] [--out <path>] <source>

Rewrites the duration table scripts/run-tests.sh orders its queue by, from a
timing report the runner persisted or a log carrying check-test-time's ranked
table (a CI job log). Ordering data only; it gates nothing.

  --suite   the test directory whose *.sh files the table may name
            (default: <repo>/tests)
  --out     the table to write (default: <repo>/config/test-durations.tsv)
EOF
}

suite=""
out=""
source=""
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
      [ -z "$source" ] || die "one source only (see --help)"
      source="$1"
      shift
      ;;
  esac
done
[ -n "$source" ] || die "a source file is required (see --help)"
[ -n "$suite" ] || suite="$repo_root/tests"
[ -n "$out" ] || out="$repo_root/config/test-durations.tsv"
[ -f "$source" ] && [ -r "$source" ] \
  || die "source not readable: $(sanitize_printable "$source" "(unprintable path)")"
[ -d "$suite" ] || die "suite directory not found: $(sanitize_printable "$suite" "(unprintable path)")"

# check-test-time's local mode prints only the slowest few rows; a table built
# from that would queue every file it left out ahead of the slowest ones.
if grep -q 'more under budget; --all lists them' <"$source"; then
  die "the source's ranked table is cut short (check-test-time without --all); use a CI log or a timing report"
fi

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

# Emits `<name><TAB><seconds>` per usable source row, first row per name.
RD_DISCOVERED="$work/discovered" awk -F'\t' '
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
    if (match(line, /[0-9]+(\.[0-9]+)?s  [A-Za-z0-9._-]+\.sh( |$)/)) {
      cell = substr(line, RSTART, RLENGTH)
      sub(/ $/, "", cell)
      split(cell, part, "s  ")
      keep(part[2], part[1])
    }
  }
  function keep(name, secs) {
    if ((name in want) && !(name in seen)) {
      seen[name] = 1
      print name "\t" secs
    }
  }
' <"$source" >"$work/kept" || die "could not read the source"
# A redirect rather than an operand: awk takes an operand shaped like
# `name=value` as an assignment, not a file. Sorted only once awk has
# succeeded, so a failure partway never writes a partial table.
sort -t "$(printf '\t')" -k2,2nr -k1,1 "$work/kept" >"$work/rows" \
  || die "could not sort the source's rows"
[ -s "$work/rows" ] \
  || die "no timed test file found in $(sanitize_printable "$source" "(unprintable path)"); table left unchanged"

{
  cat <<'EOF'
# Expected per-file seconds for scripts/run-tests.sh's queue order: the runner
# dispatches the longest first so no slow file is left running alone at the
# end of the suite. Ordering only: nothing here gates, budgets, or selects a
# test (config/test-time-budget.yml holds the budgets). A test file with no row
# runs ahead of every timed one.
#
# Generated by scripts/refresh-test-durations.sh; regenerate rather than
# hand-edit, from a reference-runner check:test-time log (`gh run view <id>
# --log`, CI mode prints every file) or a tests/.timing-report.tsv.
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
printf 'refresh-test-durations: wrote %s row(s) to %s\n' "$rows" "$(sanitize_printable "$out" "(unprintable path)")"
if [ -n "$untimed" ]; then
  printf 'refresh-test-durations: untimed (queued first): %s\n' "$(sanitize_printable "$untimed" "(unprintable)")" >&2
fi
