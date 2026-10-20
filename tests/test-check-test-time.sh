#!/bin/bash
# Tests for scripts/check-test-time.sh — the test wall-clock budget gate
# (guard-coverage Task 7; REQ-E1.1, REQ-H1.3; D-8).
#
# The gate reads the timing report scripts/run-tests.sh persists after a suite
# run and compares it against the committed budgets; it never re-runs the
# suite. The cases below pin the comparison (at-or-over trips, under passes,
# for the per-file and the suite-total budget alike), the CI-hard-fail versus
# local-loud-warn split, and the fail-closed arm (REQ-H1.3): a report that is
# missing, empty, malformed, stale, or short of an entry for a discovered test
# file exits non-zero rather than passing vacuously, and so does a budget file
# the gate cannot read.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-test-time.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*)
      echo "FAIL: $1 (output mentioned '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# The gate runs with the ambient CI variable cleared so every case below
# chooses its mode explicitly; the env-derived default has its own case.
unset GITHUB_ACTIONS

# A fixture suite of three discoverable test files. The gate only reads their
# names, so the bodies are placeholders.
suite="$tmp/suite"
mkdir -p "$suite"
for n in alpha beta gamma; do
  printf '#!/bin/bash\nexit 0\n' >"$suite/test-$n.sh"
done

# write_budget <path> <per-file> <suite-total> [<shard-wall>] — the shard
# ceiling defaults below the suite total, so a case shows which one tripped.
write_budget() {
  printf -- '---\n# fixture budget\nper_file_seconds: %s\nsuite_total_seconds: %s\nshard_wall_seconds: %s\n' "$2" "$3" "${4:-20}" >"$1"
}

# write_report <path> <wall> <name>=<seconds>... — a well-formed report.
write_report() {
  wr_path="$1"
  wr_wall="$2"
  shift 2
  {
    printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
    for wr_entry in "$@"; do
      printf 'file\t%s\t%s\t0.000\n' "${wr_entry%%=*}" "${wr_entry#*=}"
    done
    printf 'suite\twall\t%s\n' "$wr_wall"
  } >"$wr_path"
}

run_check() {
  /bin/bash "$CHECKER" --suite "$suite" --report "$tmp/report.tsv" --budget "$tmp/budget.yml" "$@" 2>&1
}

write_budget "$tmp/budget.yml" 10 30

# ---------------------------------------------------------------------------
# 1. Under budget passes in both modes, and the clean line carries the count
#    (the only evidence the gate looked at every discovered file).
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 12.5 test-alpha.sh=1.250 test-beta.sh=9.999 test-gamma.sh=0.010
out="$(run_check --mode ci)"
assert "an under-budget report passes in CI mode" 0 $?
assert_contains "the clean run reports the file count" "$out" "clean (3 files"
out="$(run_check --mode local)"
assert "an under-budget report passes in local mode" 0 $?
assert_not_contains "a clean local run carries no warning" "$out" "WARNING"

# ---------------------------------------------------------------------------
# 2. Boundary: a per-file time exactly AT the budget trips (measured >= budget,
#    the check:instructions convention D-8 adopts); one just under does not.
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 12.5 test-alpha.sh=10.000 test-beta.sh=1 test-gamma.sh=0.010
out="$(run_check --mode ci)"
assert "a per-file time at the budget fails in CI" 1 $?
assert_contains "the failure names the offending file" "$out" "test-alpha.sh"
assert_contains "the failure names the per-file budget" "$out" "per-file budget"

write_report "$tmp/report.tsv" 12.5 test-alpha.sh=9.999 test-beta.sh=1 test-gamma.sh=0.010
run_check --mode ci >/dev/null
assert "a per-file time just under the budget passes" 0 $?

# ---------------------------------------------------------------------------
# 3. The suite-total budget is judged on the runner's wall-clock row, with
#    the same boundary.
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 30 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1
out="$(run_check --mode ci)"
assert "a suite wall-clock at the total budget fails in CI" 1 $?
assert_contains "the failure names the suite-total budget" "$out" "suite-total budget"

write_report "$tmp/report.tsv" 29.999 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1
run_check --mode ci >/dev/null
assert "a suite wall-clock just under the total budget passes" 0 $?

write_report "$tmp/report.tsv" 45.5 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1
out="$(run_check --mode ci)"
assert "a suite wall-clock over the total budget fails in CI" 1 $?

# One report is an unsharded run: the per-shard ceiling does not apply to it,
# so a local `mise run check` is judged on the suite total alone.
write_report "$tmp/report.tsv" 25 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1
out="$(run_check --mode ci)"
assert "one report over the shard ceiling but under the suite total passes" 0 $?
assert_not_contains "an unsharded run states no shard ceiling" "$out" "per-shard"

# ---------------------------------------------------------------------------
# 4. Every offender is reported, not just the first.
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 12 test-alpha.sh=11 test-beta.sh=1 test-gamma.sh=12
out="$(run_check --mode ci)"
assert "two per-file offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "test-alpha.sh"
assert_contains "the second offender is named" "$out" "test-gamma.sh"

# ---------------------------------------------------------------------------
# 5. The CI-hard / local-warn split (D-8). Locally the same over-budget
#    report exits 0 but says so loudly, naming the offender and the fact that
#    CI would fail — a silent local pass is exactly the boiling-frog path the
#    hard-fail decision rejected.
# ---------------------------------------------------------------------------
out="$(run_check --mode local)"
assert "an over-budget report exits 0 in local mode" 0 $?
assert_contains "the local run warns loudly" "$out" "WARNING"
assert_contains "the local warning says CI would fail" "$out" "would fail in CI"
assert_contains "the local warning names the offender" "$out" "test-alpha.sh"

# The mode defaults from the environment: GITHUB_ACTIONS=true is the reference
# runner and hard-fails; anything else is local.
out="$(GITHUB_ACTIONS=true /bin/bash "$CHECKER" --suite "$suite" --report "$tmp/report.tsv" --budget "$tmp/budget.yml" 2>&1)"
assert "GITHUB_ACTIONS=true selects CI mode" 1 $?
out="$(/bin/bash "$CHECKER" --suite "$suite" --report "$tmp/report.tsv" --budget "$tmp/budget.yml" 2>&1)"
assert "without GITHUB_ACTIONS the default is local mode" 0 $?
assert_contains "the env-defaulted local run still warns" "$out" "WARNING"

out="$(run_check --mode nightly)"
assert "an unknown mode fails closed" 2 $?

# ---------------------------------------------------------------------------
# 6. Positive accounting (REQ-H1.3): a report short of an entry for a
#    discovered file fails closed in BOTH modes — this is structural, not a
#    budget verdict, so the local-warn split does not soften it.
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 3 test-alpha.sh=1 test-beta.sh=1
out="$(run_check --mode ci)"
assert "a report missing a discovered file fails closed in CI" 2 $?
assert_contains "the missing-entry failure names the file" "$out" "test-gamma.sh"
out="$(run_check --mode local)"
assert "a report missing a discovered file fails closed locally too" 2 $?
assert_contains "the local missing-entry failure names the file" "$out" "test-gamma.sh"

# An entry for a file the suite no longer has is a stale report: the gate
# would be judging a different suite than the one on disk.
write_report "$tmp/report.tsv" 4 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1 test-delta.sh=1
out="$(run_check --mode ci)"
assert "a report naming an undiscovered file fails closed" 2 $?
assert_contains "the stale-entry failure names the extra file" "$out" "test-delta.sh"

# ---------------------------------------------------------------------------
# 7. Empty, malformed, and missing reports fail closed.
# ---------------------------------------------------------------------------
: >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "an empty report fails closed" 2 $?
assert_contains "the empty-report failure says so" "$out" "empty"

rm -f "$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a missing report fails closed" 2 $?
assert_contains "the missing-report failure names the path" "$out" "report.tsv"
assert_contains "the missing-report failure points at the runner" "$out" "mise run test"

printf 'not a timing report\n' >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a report without the header fails closed" 2 $?
assert_contains "the header failure says so" "$out" "header"

write_report "$tmp/report.tsv" 3 test-alpha.sh=1 test-beta.sh=fast test-gamma.sh=1
out="$(run_check --mode ci)"
assert "a non-numeric time fails closed" 2 $?
assert_contains "the non-numeric failure names the row" "$out" "test-beta.sh"

write_report "$tmp/report.tsv" 3 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1 test-alpha.sh=2
out="$(run_check --mode ci)"
assert "a duplicated file row fails closed" 2 $?
assert_contains "the duplicate failure names the file" "$out" "test-alpha.sh"

{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-alpha.sh\t1\t0\nfile\ttest-beta.sh\t1\t0\nfile\ttest-gamma.sh\t1\t0\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a report without the suite wall-clock row fails closed" 2 $?
assert_contains "the missing-wall failure says so" "$out" "wall"

{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-alpha.sh\t1\t0\nfile\ttest-beta.sh\t1\t0\nfile\ttest-gamma.sh\t1\t0\n'
  printf 'suite\twall\t3\nbogus\trow\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "an unrecognised row fails closed" 2 $?

{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-alpha.sh\t1\t0\nfile\ttest-beta.sh\t1\t0\nfile\ttest-gamma.sh\t1\t0\n'
  printf 'suite\twall\t3\nsuite\twall\t4\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a duplicated wall-clock row fails closed" 2 $?

# The version-2 row carries the ticket wait beside the execution time. The
# wait is never budgeted, the pre-wait version-1 report is refused rather than
# misread, and a row missing its wait or carrying a non-numeric one is malformed.
{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-alpha.sh\t1\t500\nfile\ttest-beta.sh\t1\t0\nfile\ttest-gamma.sh\t1\t0\n'
  printf 'suite\twall\t3\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a wait far over the per-file budget does not trip it" 0 $?
{
  printf 'planwright-test-timing\t1\tclock=fixture\tjobs=1\n'
  printf 'file\ttest-alpha.sh\t1\nfile\ttest-beta.sh\t1\nfile\ttest-gamma.sh\t1\n'
  printf 'suite\twall\t3\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a version-1 report fails closed" 2 $?
assert_contains "the version failure asks for a fresh run" "$out" "mise run test"
{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-alpha.sh\t1\nfile\ttest-beta.sh\t1\t0\nfile\ttest-gamma.sh\t1\t0\n'
  printf 'suite\twall\t3\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a file row without its wait fails closed" 2 $?
{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-alpha.sh\t1\tlong\nfile\ttest-beta.sh\t1\t0\nfile\ttest-gamma.sh\t1\t0\n'
  printf 'suite\twall\t3\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a non-numeric wait fails closed" 2 $?
assert_contains "the non-numeric wait failure names the row" "$out" "test-alpha.sh"

# ---------------------------------------------------------------------------
# 7b. Several reports, one per CI shard: judged as one suite. Their file rows
#     together must name every discovered file exactly once, every report
#     must be well formed with its own wall-clock row. The suite-total budget
#     is judged on the wall-clocks summed over the reports, the runner time
#     the whole suite took, and the per-shard budget on the slowest report's.
# ---------------------------------------------------------------------------
run_multi() {
  /bin/bash "$CHECKER" --suite "$suite" --budget "$tmp/budget.yml" --mode ci "$@" 2>&1
}
write_report "$tmp/r1.tsv" 5 test-alpha.sh=1 test-beta.sh=2
write_report "$tmp/r2.tsv" 8 test-gamma.sh=3
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "shard reports covering the suite pass together" 0 $?
assert_contains "the clean multi-report run counts every file" "$out" "clean (3 files"
assert_contains "the suite wall-clock judged is the reports' sum" "$out" "suite wall-clock 13s, summed over 2 reports"
assert_contains "the shard wall-clock judged is the slowest report's" "$out" "slowest shard wall-clock 8s (per-shard budget 20s)"
out="$(run_multi --report "$tmp/r2.tsv" --report "$tmp/r1.tsv")"
assert "report order does not matter" 0 $?
assert_contains "the slowest shard is judged whichever report comes first" "$out" "slowest shard wall-clock 8s"

write_report "$tmp/r2.tsv" 20 test-gamma.sh=3
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "one report's wall-clock at the per-shard budget fails in CI" 1 $?
assert_contains "the shard failure names the per-shard budget" "$out" "at or over the per-shard budget of 20s"
assert_not_contains "a sum under the suite total is not called over it" "$out" "at or over the suite-total budget"
run_multi --report "$tmp/r2.tsv" --report "$tmp/r1.tsv" >/dev/null
assert "the report at the per-shard budget fails in CI when it comes first" 1 $?

write_report "$tmp/r1.tsv" 12 test-alpha.sh=1 test-beta.sh=2
write_report "$tmp/r2.tsv" 18 test-gamma.sh=3
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "shards each under their ceiling but summing to the total fail in CI" 1 $?
assert_contains "the summed failure names the suite-total budget" "$out" "suite wall-clock 30s at or over the suite-total budget of 30s"
assert_not_contains "a shard under its ceiling is not called over it" "$out" "at or over the per-shard budget"
write_report "$tmp/r1.tsv" 5 test-alpha.sh=1 test-beta.sh=2

# Just under the per-shard ceiling passes, and fractional wall-clocks sum
# exactly.
write_report "$tmp/r1.tsv" 5.25 test-alpha.sh=1 test-beta.sh=2
write_report "$tmp/r2.tsv" 19.999 test-gamma.sh=3
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "one report's wall-clock just under the per-shard budget passes" 0 $?
assert_contains "fractional wall-clocks sum exactly" "$out" "suite wall-clock 25.249s, summed over 2 reports"
write_report "$tmp/r1.tsv" 5 test-alpha.sh=1 test-beta.sh=2

# Local mode warns on the per-shard ceiling rather than failing.
write_report "$tmp/r2.tsv" 20 test-gamma.sh=3
out="$(/bin/bash "$CHECKER" --suite "$suite" --budget "$tmp/budget.yml" --mode local \
  --report "$tmp/r1.tsv" --report "$tmp/r2.tsv" 2>&1)"
assert "a report at the per-shard budget only warns locally" 0 $?
assert_contains "the local warning names the per-shard budget" "$out" "WARNING: slowest shard wall-clock 20s at or over the per-shard budget of 20s"

write_report "$tmp/r2.tsv" 8 test-gamma.sh=3 test-beta.sh=2
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "a file in two reports fails closed" 2 $?
assert_contains "the cross-report duplicate names the file" "$out" "duplicate entry for test-beta.sh"

write_report "$tmp/r2.tsv" 8
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "a file in no report fails closed" 2 $?
assert_contains "the multi-report missing entry names the file" "$out" "test-gamma.sh"

{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-gamma.sh\t3\t0\n'
} >"$tmp/r2.tsv"
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "a report without its own wall-clock row fails closed" 2 $?
assert_contains "the per-report missing wall names the report" "$out" "report 2 has no suite wall-clock row"

{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  printf 'file\ttest-gamma.sh\t3\t0\nsuite\twall\t3\nsuite\twall\t4\n'
} >"$tmp/r2.tsv"
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "a duplicated wall-clock row within one report fails closed" 2 $?

printf 'not a timing report\n' >"$tmp/r2.tsv"
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "a second report without the header fails closed" 2 $?
assert_contains "the second report's header failure says so" "$out" "header"

: >"$tmp/r2.tsv"
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv")"
assert "an empty second report fails closed" 2 $?

out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/absent.tsv")"
assert "a missing second report fails closed" 2 $?
assert_contains "the missing second report is named" "$out" "absent.tsv"

out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r1.tsv")"
assert "the same report given twice fails closed" 2 $?
assert_contains "the repeated report is named as such" "$out" "given twice"
# An empty shard's report has no file rows to collide on, so only the
# repeated-path check catches it, under another spelling of the path too.
write_report "$tmp/r-none.tsv" 1
write_report "$tmp/r-all.tsv" 5 test-alpha.sh=1 test-beta.sh=2 test-gamma.sh=3
out="$(run_multi --report "$tmp/r-all.tsv" --report "$tmp/r-none.tsv" --report "$tmp/./r-none.tsv")"
assert "an empty report given twice fails closed" 2 $?
assert_contains "the repeated empty report is named as such" "$out" "given twice"

# A directory is not a report, even when the other reports cover the suite
# (one awk skips a directory operand with only a warning).
write_report "$tmp/r2.tsv" 8 test-gamma.sh=3
mkdir -p "$tmp/rdir"
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv" --report "$tmp/rdir" </dev/null)"
assert "a directory given as a report fails closed" 2 $?
assert_contains "the directory refusal says so" "$out" "not a regular file"

# A bad header names the report it is in.
printf 'not a timing report\n' >"$tmp/r2.tsv"
out="$(run_multi --report "$tmp/r1.tsv" --report "$tmp/r2.tsv" </dev/null)"
assert_contains "the header failure names the report" "$out" "header of report 2"

# A relative report path shaped like an awk assignment is still read as a file.
mkdir -p "$tmp/eq"
write_report "$tmp/eq/r=1" 5 test-alpha.sh=1 test-beta.sh=2 test-gamma.sh=3
out="$(cd "$tmp/eq" && run_multi --report "r=1")"
assert "a report named like an awk assignment is read" 0 $?

# ---------------------------------------------------------------------------
# 8. The budget file: missing, unreadable keys, non-positive, duplicated, or
#    non-numeric values all fail closed. A budget the gate cannot trust is
#    not a budget of zero.
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 3 test-alpha.sh=1 test-beta.sh=1 test-gamma.sh=1

rm -f "$tmp/budget.yml"
out="$(run_check --mode ci)"
assert "a missing budget file fails closed" 2 $?
assert_contains "the missing-budget failure names the path" "$out" "budget.yml"

printf -- '---\nper_file_seconds: 10\n' >"$tmp/budget.yml"
out="$(run_check --mode ci)"
assert "a budget file missing a key fails closed" 2 $?
assert_contains "the missing-key failure names the key" "$out" "suite_total_seconds"

printf -- '---\nper_file_seconds: 10\nsuite_total_seconds: 30\n' >"$tmp/budget.yml"
out="$(run_check --mode ci)"
assert "a budget file without the per-shard key fails closed" 2 $?
assert_contains "the missing per-shard key is named" "$out" "shard_wall_seconds"

write_budget "$tmp/budget.yml" 10 30 0
out="$(run_check --mode ci)"
assert "a zero per-shard budget fails closed" 2 $?
assert_contains "the zero per-shard budget failure names the key" "$out" "shard_wall_seconds"

printf -- '---\nper_file_seconds: 10\nsuite_total_seconds: 30\nshard_wall_seconds: 20\nshard_wall_seconds: 25\n' >"$tmp/budget.yml"
out="$(run_check --mode ci)"
assert "a duplicated per-shard key fails closed" 2 $?

write_budget "$tmp/budget.yml" ten 30
out="$(run_check --mode ci)"
assert "a non-numeric budget fails closed" 2 $?
assert_contains "the non-numeric budget failure names the key" "$out" "per_file_seconds"

write_budget "$tmp/budget.yml" 10 0
out="$(run_check --mode ci)"
assert "a zero budget fails closed" 2 $?

printf -- '---\nper_file_seconds: 10\nsuite_total_seconds: 30\nper_file_seconds: 20\n' >"$tmp/budget.yml"
out="$(run_check --mode ci)"
assert "a duplicated budget key fails closed" 2 $?

# A decimal budget is honoured (the derivation may well land on one).
write_budget "$tmp/budget.yml" 1.5 30
write_report "$tmp/report.tsv" 3 test-alpha.sh=1.5 test-beta.sh=1 test-gamma.sh=1
run_check --mode ci >/dev/null
assert "a decimal budget compares at its boundary" 1 $?
write_report "$tmp/report.tsv" 3 test-alpha.sh=1.499 test-beta.sh=1 test-gamma.sh=1
run_check --mode ci >/dev/null
assert "a time under a decimal budget passes" 0 $?
write_budget "$tmp/budget.yml" 10 30

# ---------------------------------------------------------------------------
# 9. A suite that discovers zero test files, or does not exist, fails closed:
#    a report cannot be checked against nothing.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/nosuite"
out="$(/bin/bash "$CHECKER" --suite "$tmp/nosuite" --report "$tmp/report.tsv" --budget "$tmp/budget.yml" --mode ci 2>&1)"
assert "a suite with no test files fails closed" 2 $?
assert_contains "the zero-file failure says so" "$out" "no *.sh test files"
out="$(/bin/bash "$CHECKER" --suite "$tmp/absent" --report "$tmp/report.tsv" --budget "$tmp/budget.yml" --mode ci 2>&1)"
assert "a missing suite directory fails closed" 2 $?

# ---------------------------------------------------------------------------
# 10. The report is printed ranked slowest-first so the CI log doubles as
#     the baseline a budget is derived from; CI mode prints every file, local
#     mode the slowest few unless --all.
# ---------------------------------------------------------------------------
write_report "$tmp/report.tsv" 5 test-alpha.sh=0.5 test-beta.sh=3 test-gamma.sh=1
out="$(run_check --mode ci)"
assert "the ranked run passes" 0 $?
beta_pos="${out%%test-beta.sh*}"
gamma_pos="${out%%test-gamma.sh*}"
alpha_pos="${out%%test-alpha.sh*}"
if [ "${#beta_pos}" -lt "${#gamma_pos}" ] && [ "${#gamma_pos}" -lt "${#alpha_pos}" ]; then
  echo "ok: files are ranked slowest-first"
else
  echo "FAIL: files are not ranked slowest-first: $out" >&2
  failures=$((failures + 1))
fi
assert_contains "the ranking states the per-file budget" "$out" "per-file budget 10"
assert_contains "the ranking states the suite-total budget" "$out" "suite-total budget 30"

# Argument handling.
out="$(run_check --mode ci --bogus)"
assert "an unknown option fails closed" 2 $?
assert_contains "the unknown-option failure names it" "$out" "--bogus"
out="$(/bin/bash "$CHECKER" --help 2>&1)"
assert "--help exits clean" 0 $?
assert_contains "--help records the bump-consciously rule" "$out" "bump"
assert_contains "--help records the CI/local split" "$out" "warns"

# ---------------------------------------------------------------------------
# 11. The committed budget file and the real suite: a synthetic report that
#     names every real tests/*.sh file with a tiny time passes against the
#     committed budgets, proving the budget file parses and the discovery
#     covers the whole suite. (The real report is not asserted here: it is
#     written by the suite run this test is part of.)
# ---------------------------------------------------------------------------
{
  printf 'planwright-test-timing\t2\tclock=fixture\tjobs=1\tpool=1\n'
  for f in "$REPO_ROOT"/tests/*.sh; do
    printf 'file\t%s\t0.001\t0.000\n' "${f##*/}"
  done
  printf 'suite\twall\t0.5\n'
} >"$tmp/real-report.tsv"
out="$(/bin/bash "$CHECKER" --suite "$REPO_ROOT/tests" --report "$tmp/real-report.tsv" --budget "$REPO_ROOT/config/test-time-budget.yml" --mode ci 2>&1)"
assert "the committed budget file parses against the real suite" 0 $?
real_count="$(printf '%s' "$out" | sed -n 's/.*clean (\([0-9]*\) files.*/\1/p')"
if [ -n "$real_count" ] && [ "$real_count" -ge 100 ]; then
  echo "ok: discovery reached the whole real suite ($real_count files)"
else
  echo "FAIL: discovery covered implausibly few real files (got '$real_count')" >&2
  failures=$((failures + 1))
fi
if grep -qi 'bump' "$REPO_ROOT/config/test-time-budget.yml" && grep -qi 'warn' "$REPO_ROOT/config/test-time-budget.yml"; then
  echo "ok: the budget file's header documents the bump rule and the CI/local split"
else
  echo "FAIL: config/test-time-budget.yml does not document the bump rule and the CI/local split" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 12. Wiring: the gate is a mise task in the check aggregate, ordered after
#     the suite through a depends edge, so it reads a fresh report and never
#     runs the suite itself.
# ---------------------------------------------------------------------------
if grep -q '^\[tasks\."check:test-time"\]' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:test-time is defined as a mise task"
else
  echo "FAIL: mise.toml defines no check:test-time task" >&2
  failures=$((failures + 1))
fi
if grep -q '^  "check:test-time",' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:test-time is wired into the check aggregate"
else
  echo "FAIL: check:test-time is not in the check aggregate's depends list" >&2
  failures=$((failures + 1))
fi
if awk '/^\[tasks\."check:test-time"\]/{f=1;next} /^\[/{f=0} f && /^depends = \["test"\]/{found=1} END{exit !found}' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:test-time depends on test"
else
  echo "FAIL: the check:test-time task does not declare depends = [\"test\"]" >&2
  failures=$((failures + 1))
fi
if grep -q '^tests/\.timing-report\.tsv$' "$REPO_ROOT/.gitignore"; then
  echo "ok: the timing report path is gitignored"
else
  echo "FAIL: .gitignore does not ignore tests/.timing-report.tsv" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 13. CI wiring: the suite runs in shard jobs, and the gate runs in the
#     aggregate job whose id `check` is the status branch protection and the
#     ready-flip tooling read. That job must run whatever the jobs it needs
#     did, fail unless they all passed, and judge every shard's report at once.
# ---------------------------------------------------------------------------
ci="$REPO_ROOT/.github/workflows/ci.yml"
job_block() {
  awk -v want="  $1:" '
    $0 == want { f = 1; next }
    f && /^  [A-Za-z0-9_-]+:[ \t]*$/ { exit }
    f && !/^[ \t]*#/ { print }
  ' "$ci"
}
check_block="$(job_block check)"
test_block="$(job_block test)"
lint_block="$(job_block lint)"
# The expected strings are workflow text, so `$` and `${{` in them are literal.
# shellcheck disable=SC2016
{
  assert_contains "ci.yml has an aggregate check job needing lint and test" "$check_block" "needs: [lint, test]"
  assert_contains "the check job runs whatever its needs did" "$check_block" 'if: ${{ always() }}'
  assert_contains "the check job fails unless lint and test both passed" "$check_block" \
    '[ "$LINT_RESULT" = success ] && [ "$TEST_RESULT" = success ]'
  assert_contains "the check job reads every shard's report" "$check_block" "pattern: timing-report-*"
  assert_contains "the check job runs the gate over the reports" "$check_block" \
    '/bin/bash scripts/check-test-time.sh "$@"'
  assert_contains "the check job passes each report as --report" "$check_block" 'set -- "$@" --report "$r"'
  assert_contains "the test job runs one shard of the suite" "$test_block" 'mise run test -- --shard "$SHARD/$SHARDS"'
  assert_contains "the shard count comes from the matrix" "$test_block" 'SHARDS: ${{ strategy.job-total }}'
  assert_contains "each shard uploads its timing report" "$test_block" 'name: timing-report-${{ matrix.shard }}'
  assert_contains "the lint job runs every other gate" "$lint_block" "mise run check:non-test"
}

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-test-time tests passed"
