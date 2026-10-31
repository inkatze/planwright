#!/bin/bash
# Tests for scripts/check-test-vacuity.sh, the test-vacuity guard (REQ-F1.4).
#
# shellcheck disable=SC2016,SC1003 # fixture bodies are literal shell the guard reads.
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

check() { /bin/bash "$CHECKER" "$tmp/$1" </dev/null 2>&1; }

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

# More shapes of each rule, and the twins each must leave alone.
expect_shape neg-grep no-positive-control \
  'out=$(run)' '! grep -q error "$log"'
expect_clean test-control \
  'out=$(run)' '[ -n "$out" ] || fail "no output"' 'assert_not_contains "no error" "$out" "error"'
expect_clean grep-control \
  'grep -q done "$log" || fail "not done"' 'assert_not_contains "no error" "$out" "error"'
expect_shape piped-unspaced piped-status \
  'run|tail -1' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape piped-sed piped-status \
  'run | sed -n 1p' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape piped-quoted-assign piped-status \
  'out="$(run | tail -1)"' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape piped-assign-chain piped-status \
  'out=$(run | tail -1) || fail "it failed"'
expect_shape piped-pipefail-off piped-status \
  'set -o pipefail' 'set +o pipefail' 'run | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape piped-before-pipefail piped-status \
  'run | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"' 'set -euo pipefail'
expect_shape piped-continued piped-status \
  'run \' '  | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_clean piped-awk-exit \
  'printf "%s\n" "$out" | awk '"'"'/x/ { f = 1 } END { exit !f }'"'"' || fail "no x"'
expect_clean piped-sort-check \
  'printf "%s\n" "$seqs" | sort -n -c || fail "not sorted"'
expect_clean piped-in-test \
  '[ "$(run | tail -1)" = done ] || fail "not done"'
expect_clean piped-far-read \
  'run | tail -n 5' 'a=1' 'b=2' 'c=3' 'd=4' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape masked-colon masked-status \
  'out=$(run) || :' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_clean self-substitution \
  '[ "$(gen)" = "$(gen)" ] || fail "nondeterministic"'
expect_clean self-in-string \
  'printf "%s\n" "while read r; do' '  [ a = a ]' 'done"' 'assert_contains "x" "$out" "y"'
expect_clean self-in-heredoc \
  'cat >"$f" <<EOF' '[ a = a ]' 'EOF' 'assert_contains "x" "$out" "y"'
expect_clean self-in-continued-heredoc \
  'cat >"$f" <<'"'"'BODY'"'"' &&' '[ a = a ]' 'BODY' '  pass "written"'
expect_shape self-after-shift self-comparison \
  'n=$((1 << 2))' '[ x = x ] && pass "equal"'
expect_clean self-in-comment \
  '# [ x = x ] reads as a comment' 'assert_contains "x" "$out" "y"'
expect_shape counter-incr-form zero-row-floor \
  'while IFS= read -r row; do' '  ((n++))' '  check_row "$row" || fail "row"' \
  'done <"$CORPUS"' '[ "$n" -gt -1 ] || fail "no rows"'
expect_clean counter-array \
  'while IFS= read -r row; do' '  rows+=("$row")' '  check_row "$row" || fail "row"' \
  'done <"$CORPUS"' '[ "${#rows[@]}" -gt 0 ] || fail "no rows"'
expect_clean counter-min-var \
  'while IFS= read -r row; do' '  n=$((n + 1))' '  check_row "$row" || fail "row"' \
  'done <"$CORPUS"' '[ "$n" -lt "$CORPUS_MIN_ROWS" ] && fail "too few rows"'
expect_shape floor-before-loop zero-row-floor \
  '[ "$n" -gt 0 ] || fail "no rows"' 'while IFS= read -r row; do' '  n=$((n + 1))' \
  '  check_row "$row" || fail "row"' 'done <"$CORPUS"'
expect_clean corpus-no-assert \
  'while IFS= read -r row; do' '  printf "%s\n" "$row" >>"$out"' 'done <"$CORPUS"'
expect_shape corpus-nested-pipe zero-row-floor \
  'while IFS= read -r row; do' '  printf "%s\n" "$row" | while read -r y; do :; done' \
  '  check_row "$row" || fail "row"' 'done <"$CORPUS"'
expect_shape corpus-echo-done zero-row-floor \
  'while IFS= read -r row; do' '  log done' '  check_row "$row" || fail "row"' 'done <"$CORPUS"'
expect_shape corpus-inner-assert zero-row-floor \
  'while IFS= read -r row; do' '  for x in a b; do' '    check "$x" || fail "row"' '  done' 'done <"$CORPUS"'

# Round-two shapes: lexing that must not lose its place, and exemptions that
# must not leak.
expect_shape after-ansi self-comparison \
  "echo \$'it\\'s'" '[ x = x ] && pass "equal"'
expect_shape after-escaped-quote self-comparison \
  "echo it\\'s" '[ x = x ] && pass "equal"'
expect_shape after-nested-subst self-comparison \
  'case "$(cell "$(row "it'"'"'s here")")" in' '  x) ok "x" ;;' 'esac' '[ x = x ] && pass "equal"'
expect_shape after-subst-paren self-comparison \
  'x="$(printf %s "$y" | grep -v '"'"'"Bash('"'"')"' '[ x = x ] && pass "equal"'
expect_shape after-two-heredocs self-comparison \
  'cmd 3<<A <<B' 'a' 'A' "it's" 'B' '[ x = x ] && pass "equal"'
expect_shape after-digit-delimiter self-comparison \
  "cat <<'1END'" "it's" '1END' '[ x = x ] && pass "equal"'
expect_shape after-here-string self-comparison \
  'grep -q x <<<foo || fail "x"' '[ x = x ] && pass "equal"'
expect_shape piped-subshell piped-status \
  '( run | tail -1 )' '[ $? -eq 0 ] || fail "x"'
expect_shape piped-awk-or-exit piped-status \
  "run | awk '{print \$1}' || exit 1" '[ $? -eq 0 ] || fail "x"'
expect_clean piped-sort-c-alone \
  'printf "%s\n" "$seqs" | sort -c || fail "not sorted"'
expect_clean piped-euo-pipefail \
  'set -euo pipefail' 'run | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_clean piped-split-pipefail \
  'set -e -o pipefail' 'run | tail -n 5' 'rc=$?' 'assert "it ran" 0 "$rc"'
expect_shape corpus-brace-loop zero-row-floor \
  'while IFS= read -r row; do' '  { while read -r b; do echo; done; } <x' \
  '  check_row "$row" || fail "row"' 'done <"$CORPUS"'
expect_shape corpus-fail-counter zero-row-floor \
  'while IFS= read -r row; do' '  check_row "$row" || fails=$((fails + 1))' '  pass "row"' \
  'done <"$CORPUS"' '[ "$fails" -eq 0 ] || fail "rows failed"'
fixture open-quote "x='oops" '[ x = x ]'
out=$(check open-quote)
assert "a quoted string left open at end of file fails closed" 2 $?

# Each rule honours an annotation on the line it reports.
expect_clean annotated-self \
  '[ x = x ] && pass "equal" # vacuity-ok: a smoke line'
expect_clean annotated-piped \
  'run | tail -n 5' 'rc=$? # vacuity-ok: tail is the subject'
expect_clean annotated-chain \
  'run | tee "$log" && pass "it ran" # vacuity-ok: tee is the subject'
expect_clean annotated-masked-if \
  'if run || :; then pass "it ran"; fi # vacuity-ok: run is advisory'
expect_clean annotated-floor \
  'while IFS= read -r row; do' '  check_row "$row" || fail "row"' \
  'done <"$CORPUS" # vacuity-ok: the corpus is generated above'
expect_clean annotated-no-control \
  'out=$(run)' 'assert_not_contains "no error" "$out" "error" # vacuity-ok: run always prints'

# Only tests/test-*.sh files answer for a positive control, and tests/fixtures/
# is data.
fixture helper-file 'out=$(run)'
printf '%s\n' '#!/bin/bash' 'assert_not_contains "no error" "$out" "error"' >"$tmp/helper-file/tests/lib.sh"
out=$(check helper-file)
assert "a helper outside test-*.sh needs no positive control" 0 $?
fixture fixtures-data 'out=$(run)'
mkdir -p "$tmp/fixtures-data/tests/fixtures"
printf '%s\n' '#!/bin/bash' '[ x = x ]' >"$tmp/fixtures-data/tests/fixtures/case.sh"
out=$(check fixtures-data)
assert "tests/fixtures/ is not scanned" 0 $?

# A symlinked test is scanned; a symlink to a directory or device is refused.
fixture linked 'out=$(run)'
printf '%s\n' '#!/bin/bash' '[ x = x ]' >"$tmp/linked/real.sh"
ln -s "$tmp/linked/real.sh" "$tmp/linked/tests/test-link.sh"
out=$(check linked)
assert "a symlinked test is scanned" 1 $?
assert_contains "the symlinked test is named" "$out" "tests/test-link.sh"
fixture linked-dir 'out=$(run)'
ln -s "$tmp" "$tmp/linked-dir/tests/away"
out=$(check linked-dir)
assert "a symlinked directory is refused" 2 $?

# A file name's 8-bit control bytes never reach the output.
fixture c1-name 'out=$(run)'
printf '%s\n' '#!/bin/bash' '[ x = x ]' >"$tmp/c1-name/tests/test-a$(printf '\302\233')b.sh"
out=$(check c1-name)
assert "a finding in a file whose name carries a C1 byte is reported" 1 $?
case "$out" in
  *"$(printf '\233')"*)
    echo "FAIL: a C1 control byte reached the output" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: C1 control bytes are stripped from file names" ;;
esac

# A heredoc left open at end of file cannot be reported clean.
fixture open-heredoc 'cat <<EOF' 'never closed'
out=$(check open-heredoc)
assert "an unterminated heredoc fails closed" 2 $?

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

fixture unreadable 'out=$(run)'
chmod 000 "$tmp/unreadable/tests/test-case.sh"
if [ -r "$tmp/unreadable/tests/test-case.sh" ]; then
  echo "ok: skipped the unreadable-file case: the running user reads mode-000 files"
else
  out=$(check unreadable)
  assert "an unreadable test file fails closed" 2 $?
fi
chmod 644 "$tmp/unreadable/tests/test-case.sh"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "PASS: check-test-vacuity"
