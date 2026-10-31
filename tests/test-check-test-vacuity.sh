#!/bin/bash
# Tests for scripts/check-test-vacuity.sh, the test-vacuity guard (REQ-F1.4).
#
# shellcheck disable=SC2016 # fixture bodies are literal shell the guard reads.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-test-vacuity.sh"

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

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-check-test-vacuity.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

# fixture <name> <line>...: a root whose tests/test-case.sh holds the lines,
# beside a conforming suite so the scan never reaches zero files.
fixture() {
  f_root="$tmp/$1"
  shift
  mkdir -p "$f_root/tests" || exit 1
  printf '%s\n' '#!/bin/bash' 'out=$(run)' 'assert_contains "runs" "$out" "done"' \
    >"$f_root/tests/test-conforming.sh" || exit 1
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' "$@"
  } >"$f_root/tests/test-case.sh" || exit 1
}

check() { /bin/bash "$CHECKER" "$tmp/$1" 2>&1; }

# expect_shape <name> <rule> <line>...: the fixture fails naming the rule.
expect_shape() {
  e_name=$1 e_rule=$2
  shift 2
  fixture "$e_name" "$@"
  out=$(check "$e_name")
  assert "REQ-F1.4: $e_name fails" 1 $?
  assert_contains "REQ-F1.4: $e_name names $e_rule" "$out" "$e_rule"
  assert_contains "REQ-F1.4: $e_name names the file" "$out" "tests/test-case.sh"
}

# expect_clean <name> <line>...: the conforming twin passes.
expect_clean() {
  c_name=$1
  shift
  fixture "$c_name" "$@"
  out=$(check "$c_name")
  assert "REQ-F1.4: $c_name passes" 0 $?
}

# No positive control: only absences are asserted, so an empty output passes.
expect_shape no-control no-positive-control \
  'out=$(run)' 'assert_not_contains "no error" "$out" "error"'
expect_clean controlled \
  'out=$(run)' 'assert_contains "it ran" "$out" "done"' \
  'assert_not_contains "no error" "$out" "error"'

# A piped status read from a filter stage, not the command under test.
expect_shape piped-next piped-status \
  'run 2>&1 | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape piped-same piped-status \
  'out=$(run | head -n 1); rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape piped-chain piped-status \
  'run | tee "$log" && pass "it ran"'
expect_clean piped-under-test \
  'out=$(printf x | run); rc=$?' 'assert "it ran" 0 "$rc"'
expect_clean piped-pipefail \
  'set -o pipefail' 'run | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"'

# An asserted command masked by an always-true alternative.
expect_shape masked-next masked-status \
  'out=$(run) || true' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape masked-if masked-status \
  'if run || :; then pass "it ran"; fi'
expect_clean unmasked \
  'out=$(run)' 'rc=$?' 'assert "it ran" 0 "$rc"' 'cleanup || true'

# A constant compared to itself.
expect_shape self-literal self-comparison \
  '[ "x" = "x" ] && pass "equal"'
expect_shape self-variable self-comparison \
  'if [[ $rc -eq $rc ]]; then pass "equal"; fi'
expect_clean compared \
  '[ "$rc" = "0" ] && pass "equal"'

# A corpus harness with no row floor, or a floor of zero.
expect_shape no-floor zero-row-floor \
  'while IFS= read -r row; do' '  check_row "$row" || fail "row $row"' \
  'done <"$CORPUS"'
expect_shape zero-floor zero-row-floor \
  'n=0' 'while IFS= read -r row; do' '  n=$((n + 1))' \
  '  check_row "$row" || fail "row $row"' 'done <fixtures/cases.tsv' \
  '[ "$n" -ge 0 ] || fail "no rows"'
expect_clean floored \
  'n=0' 'while IFS= read -r row; do' '  n=$((n + 1))' \
  '  check_row "$row" || fail "row $row"' 'done <"$CORPUS"' \
  '[ "$n" -gt 0 ] || fail "the corpus has no rows"'
expect_clean not-a-corpus \
  'while IFS= read -r row; do' '  check_row "$row" || fail "row $row"' \
  'done <"$tmp/out"'

# An annotated line is a recorded exclusion; an empty reason is not.
expect_clean annotated \
  'out=$(run) || true' 'rc=$? # vacuity-ok: run always exits 0, the output is the subject' \
  'assert_contains "it ran" "$out" "done"'
expect_shape annotated-empty masked-status \
  'out=$(run) || true' 'rc=$? # vacuity-ok:' 'assert "it ran" 0 "$rc"'

# Fail closed: no tests directory, no shell files, a bad argument.
mkdir -p "$tmp/no-tests"
out=$(check no-tests)
assert "a root without tests/ fails closed" 2 $?
mkdir -p "$tmp/no-files/tests"
printf 'data\n' >"$tmp/no-files/tests/notes.txt"
out=$(check no-files)
assert "a scan reaching no shell files fails closed" 2 $?
assert_contains "the empty scan says so" "$out" "no shell files"
out=$(/bin/bash "$CHECKER" --bogus 2>&1)
assert "an unknown option is a usage error" 2 $?

# The shipped test surface is green.
out=$(/bin/bash "$CHECKER" 2>&1)
rc=$?
assert "this repository's test surface is green" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "PASS: check-test-vacuity"
