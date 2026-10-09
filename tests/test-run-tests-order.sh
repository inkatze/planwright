#!/bin/bash
# Tests for the queue order of scripts/run-tests.sh and for
# scripts/refresh-test-durations.sh, the helper that keeps the committed
# duration table the order is read from. The suite's wall-clock is decided by
# its tail: a slow file dispatched last runs alone while every other job sits
# idle. The runner therefore dispatches the longest expected files first
# (longest-processing-time scheduling), files with no recorded time ahead of
# them all, and the order is the only thing the table may change: every file
# still runs exactly once.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"
REFRESH="$REPO_ROOT/scripts/refresh-test-durations.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2' in output; got: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-order.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
export PLANWRIGHT_TEST_SLOT_DIR="$tmp/pool"

# Each fixture file appends its own name to ORDER_LOG, so a one-job run leaves
# the dispatch order behind.
make_suite() {
  _dir=$1
  shift
  mkdir -p "$_dir"
  for _n in "$@"; do
    cat >"$_dir/$_n" <<'EOF'
#!/bin/bash
printf '%s\n' "${0##*/}" >>"$ORDER_LOG"
EOF
  done
}

# run_order <suite> <table-or-empty> [serial] — the dispatch order, one line.
# Called inside $(...), so the runner's exit code goes to a file run_rc reads.
run_order() {
  : >"$tmp/order.log"
  _serial=0
  [ "${3:-}" = serial ] && _serial=1
  ORDER_LOG="$tmp/order.log" PLANWRIGHT_TEST_JOBS=1 \
    PLANWRIGHT_TEST_FORCE_SERIAL="$_serial" \
    PLANWRIGHT_TEST_DURATIONS="$2" \
    PLANWRIGHT_TEST_TIMING_REPORT="$tmp/report.tsv" \
    /bin/bash "$RUNNER" "$1" >"$tmp/run.out" 2>&1
  echo "$?" >"$tmp/run.rc"
  tr '\n' ' ' <"$tmp/order.log" | sed 's/ $//'
}
run_rc() { cat "$tmp/run.rc"; }

make_suite "$tmp/s" test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh
tab="$(printf '\t')"
{
  echo "# a comment line is skipped"
  printf 'test-a.sh%s10\n' "$tab"
  printf 'test-b.sh%s30.5\n' "$tab"
  printf 'test-c.sh%s20\n' "$tab"
  printf 'test-gone.sh%s99\n' "$tab"
} >"$tmp/table.tsv"

# 1. Known files run longest-first; untimed files (d, e) run before them all,
#    in name order among themselves; an entry for a file the suite lacks adds
#    nothing.
got="$(run_order "$tmp/s" "$tmp/table.tsv")"
assert_eq "parallel path dispatches untimed then longest-first" \
  "test-d.sh test-e.sh test-b.sh test-c.sh test-a.sh" "$got"
assert_eq "ordered run passes" 0 "$(run_rc)"
assert_contains "the run states the order it used" "slowest-first" "$(cat "$tmp/run.out")"

got="$(run_order "$tmp/s" "$tmp/table.tsv" serial)"
assert_eq "serial path uses the same order" \
  "test-d.sh test-e.sh test-b.sh test-c.sh test-a.sh" "$got"

# 2. Every file runs exactly once, and the report and summary still name all.
assert_eq "each file ran exactly once" \
  "test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh" \
  "$(printf '%s\n' "$got" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "timing report has one row per file" 5 "$(grep -c '^file' "$tmp/report.tsv")"
assert_contains "summary counts every file" "all 5 test files passed" "$(cat "$tmp/run.out")"

# 3. Ties keep name order: equal times never reorder against each other.
{
  printf 'test-a.sh%s5\n' "$tab"
  printf 'test-b.sh%s5\n' "$tab"
  printf 'test-c.sh%s5\n' "$tab"
  printf 'test-d.sh%s5\n' "$tab"
  printf 'test-e.sh%s5\n' "$tab"
} >"$tmp/ties.tsv"
assert_eq "equal times keep name order" \
  "test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh" \
  "$(run_order "$tmp/s" "$tmp/ties.tsv")"

# 4. Malformed rows are ignored rather than trusted: a non-numeric time, a
#    row with a third field, and a duplicate (the first row wins).
{
  printf 'test-a.sh%sslow\n' "$tab"
  printf 'test-b.sh%s1%sextra\n' "$tab" "$tab"
  printf 'test-c.sh%s2\n' "$tab"
  printf 'test-c.sh%s50\n' "$tab"
  printf 'test-d.sh%s3\n' "$tab"
  printf 'test-e.sh%s-4\n' "$tab"
} >"$tmp/bad.tsv"
assert_eq "malformed rows count as untimed" \
  "test-a.sh test-b.sh test-e.sh test-d.sh test-c.sh" \
  "$(run_order "$tmp/s" "$tmp/bad.tsv")"

# 5. No table (absent path, or the knob set empty) is name order and a pass,
#    never a failure: the order is an optimisation, not a gate.
got="$(run_order "$tmp/s" "$tmp/no-such-table.tsv")"
assert_eq "absent table falls back to name order" \
  "test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh" "$got"
assert_eq "absent table still passes" 0 "$(run_rc)"
assert_contains "absent table is stated" "name order" "$(cat "$tmp/run.out")"
assert_eq "empty knob disables the table" \
  "test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh" "$(run_order "$tmp/s" "")"

# 6. A failing file still fails the run wherever the order puts it.
make_suite "$tmp/f" test-a.sh test-b.sh
cat >"$tmp/f/test-z.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "${0##*/}" >>"$ORDER_LOG"
exit 1
EOF
printf 'test-z.sh%s1\ntest-a.sh%s9\n' "$tab" "$tab" >"$tmp/f.tsv"
assert_eq "failing file runs in its ranked place" \
  "test-b.sh test-a.sh test-z.sh" "$(run_order "$tmp/f" "$tmp/f.tsv")"
assert_eq "a failing file still fails the ordered run" 1 "$(run_rc)"

# --- refresh-test-durations.sh ---------------------------------------------

# 7. From a check-test-time ranked log as CI prints it (step prefixes and
#    colour codes included): only discovered files are kept, longest first.
esc="$(printf '\033')"
cat >"$tmp/ci.log" <<EOF
check${tab}UNKNOWN STEP${tab}2026-10-09T04:05:51Z ${esc}[34m[check:test-time]${esc}[0m check-test-time: 4 files ranked slowest-first (per-file budget 120s)
check${tab}UNKNOWN STEP${tab}2026-10-09T04:05:51Z ${esc}[34m[check:test-time]${esc}[0m       41.250s  test-c.sh
check${tab}UNKNOWN STEP${tab}2026-10-09T04:05:51Z ${esc}[34m[check:test-time]${esc}[0m        9.000s  test-a.sh
check${tab}UNKNOWN STEP${tab}2026-10-09T04:05:51Z ${esc}[34m[check:test-time]${esc}[0m       12.500s  test-gone.sh
check${tab}UNKNOWN STEP${tab}2026-10-09T04:05:51Z ${esc}[34m[check:test-time]${esc}[0m      130.000s  test-b.sh  >= per-file budget
check${tab}UNKNOWN STEP${tab}2026-10-09T04:05:51Z ${esc}[34m[check:test-time]${esc}[0m   suite wall-clock 764.038s (suite-total budget 780s)
EOF
/bin/bash "$REFRESH" --suite "$tmp/s" --out "$tmp/fresh.tsv" "$tmp/ci.log" >"$tmp/refresh.out" 2>&1
assert_eq "refresh from a CI log exits 0" 0 "$?"
assert_eq "refreshed rows from a CI log" \
  "test-b.sh:130.000 test-c.sh:41.250 test-a.sh:9.000" \
  "$(grep -v '^#' "$tmp/fresh.tsv" | tr '\t' ':' | tr '\n' ' ' | sed 's/ $//')"
assert_contains "refresh names the files left untimed" "test-d.sh" "$(cat "$tmp/refresh.out")"

# 8. The refreshed table drives the runner.
assert_eq "refreshed table orders the run" \
  "test-d.sh test-e.sh test-b.sh test-c.sh test-a.sh" \
  "$(run_order "$tmp/s" "$tmp/fresh.tsv")"

# 9. From a timing report the runner wrote: its execution column, not wait.
{
  printf 'planwright-test-timing\t2\tclock=date-ns\tmode=parallel\tjobs=4\tpool=4\n'
  printf 'file\ttest-a.sh\t3.100\t50.000\n'
  printf 'file\ttest-e.sh\t7.200\t0.000\n'
  printf 'suite\twall\t60.000\n'
} >"$tmp/report-in.tsv"
/bin/bash "$REFRESH" --suite "$tmp/s" --out "$tmp/fresh2.tsv" "$tmp/report-in.tsv" >/dev/null 2>&1
assert_eq "refresh from a timing report exits 0" 0 "$?"
assert_eq "refreshed rows from a timing report" \
  "test-e.sh:7.200 test-a.sh:3.100" \
  "$(grep -v '^#' "$tmp/fresh2.tsv" | tr '\t' ':' | tr '\n' ' ' | sed 's/ $//')"

# 10. A source with no usable row is refused and the table left alone.
printf 'keep\n' >"$tmp/keep.tsv"
printf 'nothing to see\n' >"$tmp/empty.log"
/bin/bash "$REFRESH" --suite "$tmp/s" --out "$tmp/keep.tsv" "$tmp/empty.log" >/dev/null 2>&1
assert_eq "a source with no rows exits 2" 2 "$?"
assert_eq "a refused refresh leaves the table untouched" keep "$(cat "$tmp/keep.tsv")"

# 11. The committed table is current enough to be worth reading: it parses,
#     and every row names a file the suite has.
committed="$REPO_ROOT/config/test-durations.tsv"
if [ -f "$committed" ]; then
  echo "ok: committed duration table exists"
  stale="$(grep -v '^#' "$committed" | cut -f1 | while IFS= read -r n; do
    [ -f "$REPO_ROOT/tests/$n" ] || printf '%s ' "$n"
  done)"
  assert_eq "committed table names only existing test files" "" "$stale"
  assert_eq "committed table rows are name<TAB>seconds" "" \
    "$(grep -v '^#' "$committed" | grep -vE "^[A-Za-z0-9._-]+\.sh${tab}[0-9]+(\.[0-9]+)?$")"
else
  echo "FAIL: committed duration table missing at $committed" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "all run-tests order assertions passed"
