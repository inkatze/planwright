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

# write_budget <path> <per-file> <suite-total>
write_budget() {
  printf -- '---\n# fixture budget\nper_file_seconds: %s\nsuite_total_seconds: %s\n' "$2" "$3" >"$1"
}

# write_report <path> <wall> <name>=<seconds>... — a well-formed report.
write_report() {
  wr_path="$1"
  wr_wall="$2"
  shift 2
  {
    printf 'planwright-test-timing\t1\tclock=fixture\tjobs=1\n'
    for wr_entry in "$@"; do
      printf 'file\t%s\t%s\n' "${wr_entry%%=*}" "${wr_entry#*=}"
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
  printf 'planwright-test-timing\t1\tclock=fixture\tjobs=1\n'
  printf 'file\ttest-alpha.sh\t1\nfile\ttest-beta.sh\t1\nfile\ttest-gamma.sh\t1\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a report without the suite wall-clock row fails closed" 2 $?
assert_contains "the missing-wall failure says so" "$out" "wall"

{
  printf 'planwright-test-timing\t1\tclock=fixture\tjobs=1\n'
  printf 'file\ttest-alpha.sh\t1\nfile\ttest-beta.sh\t1\nfile\ttest-gamma.sh\t1\n'
  printf 'suite\twall\t3\nbogus\trow\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "an unrecognised row fails closed" 2 $?

{
  printf 'planwright-test-timing\t1\tclock=fixture\tjobs=1\n'
  printf 'file\ttest-alpha.sh\t1\nfile\ttest-beta.sh\t1\nfile\ttest-gamma.sh\t1\n'
  printf 'suite\twall\t3\nsuite\twall\t4\n'
} >"$tmp/report.tsv"
out="$(run_check --mode ci)"
assert "a duplicated wall-clock row fails closed" 2 $?

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
  printf 'planwright-test-timing\t1\tclock=fixture\tjobs=1\n'
  for f in "$REPO_ROOT"/tests/*.sh; do
    printf 'file\t%s\t0.001\n' "${f##*/}"
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-test-time tests passed"
