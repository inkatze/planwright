#!/bin/bash
# Tests for scripts/run-tests.sh --shard <i>/<N>, the split CI runs as
# parallel jobs. A shard runs only its share of the suite, so the property
# that matters is the partition's: across the N shards every file runs in
# exactly one, whatever the duration table holds, a file it has no row for
# included. The split balances by expected time, longest first, onto the
# least-loaded shard, and is a pure function of the file names and the table,
# so every job of one CI run computes the same split.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"
CHECKER="$REPO_ROOT/scripts/check-test-time.sh"

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

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-shard.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
export PLANWRIGHT_TEST_SLOT_DIR="$tmp/pool"
tab="$(printf '\t')"

# Each fixture file appends its own name to ORDER_LOG.
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

# run_shard <suite> <table-or-empty> <shard> [report] — the files the shard
# ran, one line in dispatch order. The exit code goes to a file run_rc reads.
run_shard() {
  : >"$tmp/order.log"
  ORDER_LOG="$tmp/order.log" PLANWRIGHT_TEST_JOBS=1 \
    PLANWRIGHT_TEST_DURATIONS="$2" \
    PLANWRIGHT_TEST_TIMING_REPORT="${4:-$tmp/report.tsv}" \
    /bin/bash "$RUNNER" --shard "$3" "$1" >"$tmp/run.out" 2>&1
  echo "$?" >"$tmp/run.rc"
  tr '\n' ' ' <"$tmp/order.log" | sed 's/ $//'
}
run_rc() { cat "$tmp/run.rc"; }

# test-h.sh has a row the table parser rejects and test-i.sh none at all, so
# both are untimed; the table also names a file the suite lacks.
make_suite "$tmp/s" test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh \
  test-f.sh test-g.sh test-h.sh test-i.sh
{
  echo "# fixture durations"
  printf 'test-a.sh%s10\n' "$tab"
  printf 'test-b.sh%s9\n' "$tab"
  printf 'test-c.sh%s8\n' "$tab"
  printf 'test-d.sh%s7\n' "$tab"
  printf 'test-e.sh%s6\n' "$tab"
  printf 'test-f.sh%s5\n' "$tab"
  printf 'test-g.sh%s4\n' "$tab"
  printf 'test-h.sh%sabc\n' "$tab"
  printf 'test-gone.sh%s99\n' "$tab"
} >"$tmp/table.tsv"
all="test-a.sh test-b.sh test-c.sh test-d.sh test-e.sh test-f.sh test-g.sh test-h.sh test-i.sh"

# check_union <label> <table-or-empty> <N> — run every shard of N and prove
# the shards together ran each discovered file exactly once.
check_union() {
  : >"$tmp/union.log"
  _i=1
  _rcs=""
  while [ "$_i" -le "$3" ]; do
    printf '%s\n' "$(run_shard "$tmp/s" "$2" "$_i/$3")" | tr ' ' '\n' | sed '/^$/d' >>"$tmp/union.log"
    _rcs="$_rcs$(run_rc)"
    _i=$((_i + 1))
  done
  assert_eq "$1: every shard of $3 passes" "$(printf '%*s' "$3" '' | tr ' ' 0)" "$_rcs"
  assert_eq "$1: no file runs in two shards of $3" "" "$(sort "$tmp/union.log" | uniq -d | tr '\n' ' ')"
  assert_eq "$1: the shards of $3 together run every file" "$all" \
    "$(sort -u "$tmp/union.log" | tr '\n' ' ' | sed 's/ $//')"
}

# 1. The union of the shards is the full suite, with no duplicates, for every
#    shard count from 1 to 4, with the table, with an unknown file, and with
#    no table at all.
for n in 1 2 3 4; do
  check_union "with a table" "$tmp/table.tsv" "$n"
  check_union "with no table" "" "$n"
  check_union "with an absent table" "$tmp/no-such-table.tsv" "$n"
done

# 2. Longest first onto the least-loaded shard, ties to the lower shard. An
#    untimed file weighs the mean of the timed files (here 7), so it is
#    balanced like a measured one instead of piling onto one shard. Within a
#    shard the queue keeps the unsharded order: untimed first, then longest.
assert_eq "shard 1/2 holds its balanced share" \
  "test-h.sh test-a.sh test-d.sh test-e.sh" "$(run_shard "$tmp/s" "$tmp/table.tsv" 1/2)"
assert_eq "shard 2/2 holds the rest" \
  "test-i.sh test-b.sh test-c.sh test-f.sh test-g.sh" "$(run_shard "$tmp/s" "$tmp/table.tsv" 2/2)"

# 3. The split is a function of the names and the table only: neither the
#    job count nor how the table's path is spelled moves a file.
first="$(run_shard "$tmp/s" "$tmp/table.tsv" 2/3 | tr ' ' '\n' | sort | tr '\n' ' ')"
: >"$tmp/order.log"
(cd "$tmp" && ORDER_LOG="$tmp/order.log" PLANWRIGHT_TEST_JOBS=4 PLANWRIGHT_TEST_DURATIONS=table.tsv \
  PLANWRIGHT_TEST_TIMING_REPORT="$tmp/report.tsv" /bin/bash "$RUNNER" --shard 2/3 "$tmp/s" >"$tmp/run.out" 2>&1)
assert_eq "four jobs and a relative table path give the same shard" "$first" \
  "$(sort "$tmp/order.log" | tr '\n' ' ')"

# 3b. With no table every file weighs the same, so the shards differ in size
#     by at most one file.
assert_eq "with no table shard 1/2 runs five of nine files" 5 \
  "$(run_shard "$tmp/s" "" 1/2 | wc -w | tr -d ' ')"
assert_eq "with no table shard 2/2 runs four of nine files" 4 \
  "$(run_shard "$tmp/s" "" 2/2 | wc -w | tr -d ' ')"

# 4. A shard's report and summary name its own files only, and its header
#    says which shard it is.
run_shard "$tmp/s" "$tmp/table.tsv" 1/2 "$tmp/r1.tsv" >/dev/null
assert_eq "shard report has one row per shard file" 4 "$(grep -c '^file' "$tmp/r1.tsv")"
assert_contains "shard report header names the shard" "${tab}shard=1/2" "$(head -n 1 "$tmp/r1.tsv")"
assert_contains "shard summary counts the shard's files" "all 4 test files passed" "$(cat "$tmp/run.out")"
assert_contains "shard run states its share of the suite" "shard 1/2: 4 of 9 files" "$(cat "$tmp/run.out")"

# 5. The shard reports together satisfy the timing gate, which requires one
#    row for every discovered file; one shard's report alone does not.
run_shard "$tmp/s" "$tmp/table.tsv" 2/2 "$tmp/r2.tsv" >/dev/null
printf -- 'per_file_seconds: 100\nsuite_total_seconds: 1000\n' >"$tmp/budget.yml"
/bin/bash "$CHECKER" --mode ci --suite "$tmp/s" --budget "$tmp/budget.yml" \
  --report "$tmp/r1.tsv" --report "$tmp/r2.tsv" >"$tmp/check.out" 2>&1
assert_eq "both shard reports pass the gate together" 0 "$?"
/bin/bash "$CHECKER" --mode ci --suite "$tmp/s" --budget "$tmp/budget.yml" \
  --report "$tmp/r1.tsv" >"$tmp/check.out" 2>&1
assert_eq "one shard report alone fails the gate closed" 2 "$?"

# 6. A failing file fails the shard it lands in.
make_suite "$tmp/f" test-a.sh
cat >"$tmp/f/test-z.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "${0##*/}" >>"$ORDER_LOG"
exit 1
EOF
fail_rcs=""
for i in 1 2; do
  run_shard "$tmp/f" "" "$i/2" >/dev/null
  fail_rcs="$fail_rcs$(run_rc)"
done
assert_eq "only the shard holding the failing file fails" "01" "$fail_rcs"

# 7. More shards than files: a shard left empty runs nothing and passes, and
#    still writes a report for the gate to read.
make_suite "$tmp/two" test-a.sh test-b.sh
assert_eq "an empty shard runs nothing" "" "$(run_shard "$tmp/two" "" 3/3 "$tmp/r-empty.tsv")"
assert_eq "an empty shard passes" 0 "$(run_rc)"
assert_contains "an empty shard says so" "shard 3/3: 0 of 2 files" "$(cat "$tmp/run.out")"
case "$(cat "$tmp/run.out")" in
  *FAIL*)
    echo "FAIL: an empty shard dispatches no worker (got: $(cat "$tmp/run.out"))" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: an empty shard dispatches no worker" ;;
esac
assert_eq "an empty shard's report has no file rows and its wall row" "0 1" \
  "$(grep -c '^file' "$tmp/r-empty.tsv") $(grep -c '^suite' "$tmp/r-empty.tsv")"

# 8. A malformed shard is a usage error, before anything runs.
for bad in 0/3 4/3 1/0 3 a/3 1/b 1/3/2 -1/3 "" 1/99999; do
  : >"$tmp/order.log"
  ORDER_LOG="$tmp/order.log" /bin/bash "$RUNNER" --shard "$bad" "$tmp/s" >"$tmp/bad.out" 2>&1
  assert_eq "--shard '$bad' is a usage error" 2 "$?"
  assert_eq "--shard '$bad' runs nothing" "" "$(cat "$tmp/order.log")"
done
ORDER_LOG="$tmp/order.log" /bin/bash "$RUNNER" "$tmp/s" --shard >"$tmp/bad.out" 2>&1
assert_eq "--shard with no value is a usage error" 2 "$?"
ORDER_LOG="$tmp/order.log" /bin/bash "$RUNNER" --bogus "$tmp/s" >"$tmp/bad.out" 2>&1
assert_eq "an unknown option is a usage error" 2 "$?"
assert_contains "the unknown option is named" "--bogus" "$(cat "$tmp/bad.out")"
ORDER_LOG="$tmp/order.log" /bin/bash "$RUNNER" "$tmp/s" "$tmp/s" >"$tmp/bad.out" 2>&1
assert_eq "two suite directories are a usage error" 2 "$?"

# 9. The option may follow the suite directory, and --shard=<i>/<N> is the
#    same option.
: >"$tmp/order.log"
ORDER_LOG="$tmp/order.log" PLANWRIGHT_TEST_JOBS=1 PLANWRIGHT_TEST_DURATIONS="$tmp/table.tsv" \
  PLANWRIGHT_TEST_TIMING_REPORT="$tmp/report.tsv" \
  /bin/bash "$RUNNER" "$tmp/s" --shard=1/2 >"$tmp/run.out" 2>&1
assert_eq "--shard= after the suite directory selects the same shard" \
  "test-h.sh test-a.sh test-d.sh test-e.sh" "$(tr '\n' ' ' <"$tmp/order.log" | sed 's/ $//')"

# 10. `--` ends the options, as a task runner forwarding arguments may send.
: >"$tmp/order.log"
ORDER_LOG="$tmp/order.log" PLANWRIGHT_TEST_JOBS=1 PLANWRIGHT_TEST_DURATIONS="$tmp/table.tsv" \
  PLANWRIGHT_TEST_TIMING_REPORT="$tmp/report.tsv" \
  /bin/bash "$RUNNER" -- --shard=1/2 >"$tmp/run.out" 2>&1
assert_eq "an option after -- is a suite directory, not an option" 2 "$?"
assert_contains "the misplaced option is reported as a missing suite" "suite directory not found" "$(cat "$tmp/run.out")"
ORDER_LOG="$tmp/order.log" PLANWRIGHT_TEST_JOBS=1 PLANWRIGHT_TEST_DURATIONS="$tmp/table.tsv" \
  PLANWRIGHT_TEST_TIMING_REPORT="$tmp/report.tsv" \
  /bin/bash "$RUNNER" --shard 1/2 -- "$tmp/s" >"$tmp/run.out" 2>&1
assert_eq "options before -- still apply" \
  "test-h.sh test-a.sh test-d.sh test-e.sh" "$(tr '\n' ' ' <"$tmp/order.log" | sed 's/ $//')"

# 10b. A split that cannot be computed is an error, never a shard that runs
#      some or none of its files and passes: here `sort` fails.
mkdir -p "$tmp/shim"
printf '#!/bin/sh\nexit 1\n' >"$tmp/shim/sort"
chmod 755 "$tmp/shim/sort"
: >"$tmp/order.log"
ORDER_LOG="$tmp/order.log" PATH="$tmp/shim:$PATH" PLANWRIGHT_TEST_JOBS=1 \
  PLANWRIGHT_TEST_DURATIONS="" PLANWRIGHT_TEST_TIMING_REPORT="$tmp/report.tsv" \
  /bin/bash "$RUNNER" --shard 1/2 "$tmp/s" >"$tmp/run.out" 2>&1
assert_eq "a failed split exits 2" 2 "$?"
assert_eq "a failed split runs nothing" "" "$(cat "$tmp/order.log")"
assert_contains "a failed split says so" "could not compute shard 1/2" "$(cat "$tmp/run.out")"

# 10c. --shard given twice is a usage error, not a silent last-one-wins.
: >"$tmp/order.log"
ORDER_LOG="$tmp/order.log" /bin/bash "$RUNNER" --shard 2/3 --shard=1/3 "$tmp/s" >"$tmp/bad.out" 2>&1
assert_eq "--shard given twice is a usage error" 2 "$?"
assert_contains "the repeated option is named" "given twice" "$(cat "$tmp/bad.out")"

# 11. The split never depends on the runner's locale: glob order follows
#     collation, so ties are broken by name in the C locale, never by
#     discovery order. Run where a collating locale that orders these names
#     differently from C is installed.
coll=""
for l in en_US.UTF-8 en_US.utf8 C.UTF-8; do
  if [ "$(LC_ALL=$l locale charmap 2>/dev/null)" = UTF-8 ] && [ "$l" != C.UTF-8 ]; then
    coll=$l
    break
  fi
done
if [ -n "$coll" ]; then
  make_suite "$tmp/loc" test-a-c.sh test-ab.sh test-a-d.sh test-ae.sh
  for i in 1 2; do
    c_set="$(LC_ALL=C run_shard "$tmp/loc" "" "$i/2" | tr ' ' '\n' | sort | tr '\n' ' ')"
    l_set="$(LC_ALL=$coll run_shard "$tmp/loc" "" "$i/2" | tr ' ' '\n' | sort | tr '\n' ' ')"
    assert_eq "shard $i/2 holds the same files under C and $coll" "$c_set" "$l_set"
  done
else
  echo "skip: no collating locale installed to compare against C"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "all run-tests shard assertions passed"
