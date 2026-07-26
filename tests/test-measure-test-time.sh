#!/bin/bash
# Tests for scripts/measure-test-time.sh — the out-of-gate per-file wall-clock
# measurement instrument (guard-coverage Task 6, REQ-E1.2, D-9).
#
# The instrument is deliberately NOT a gate: Task 7 owns `check:test-time`.
# This one measures, best-of-N and serially, so the numbers Task 7 budgets
# against are not perturbed by the parallel runner. What is asserted here:
#   1. Report shape: a header, one row per discovered file with a sub-second
#      best time and that file's verdict count, and the two total lines.
#   2. Ranking: rows are ordered slowest-first, so the stragglers head the
#      report.
#   3. Verdict accounting: the count is the file's own `ok`-prefixed stdout
#      lines (both house styles, `ok: label` and `ok N: label`), which is the
#      mechanically-defined assertion-count metric REQ-E1.2 compares across a
#      split.
#   4. Positive accounting: a failing test file is named and fails the run, so
#      a broken suite is never measured into a clean-looking baseline.
#   5. Best-of-N: --repeats runs each file N times and reports the minimum.
#   6. Discovery: exactly <suite-dir>/*.sh, matching scripts/run-tests.sh.
#   7. Usage contract: an unknown flag, a flag without its value, a
#      non-numeric or zero --repeats, a missing suite dir, and an empty suite
#      dir all exit 2; -h/--help exits 0.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
MEASURE="$here/../scripts/measure-test-time.sh"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# assert_contains <label> <needle> <haystack>
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)
      bad "$1 (missing '$2')"
      # printf's format string must not lead with a dash: it would be parsed as
      # an option (house pattern).
      printf '%s\n%s\n%s\n' "----- output -----" "$3" "------------------" >&2
      ;;
  esac
}

# assert_exit <label> <expected> <actual>
assert_exit() {
  if [ "$2" -eq "$3" ]; then
    ok "$1"
  else
    bad "$1 (expected exit $2, got $3)"
  fi
}

if [ ! -x "$MEASURE" ]; then
  echo "FAIL: scripts/measure-test-time.sh missing or not executable" >&2
  exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/measure-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# A three-file fixture suite. `slow.sh` sleeps long enough to rank above the
# others on any runner without making the test itself slow; the two quick files
# carry one verdict line each in the two house styles.
suite="$tmp/suite"
mkdir -p "$suite"
cat >"$suite/a-quick.sh" <<'EOF'
#!/bin/sh
echo "ok: quick verdict one"
echo "ok 2: quick verdict two"
echo "not a verdict line"
EOF
cat >"$suite/b-slow.sh" <<'EOF'
#!/bin/sh
sleep 1
echo "ok: slow verdict"
EOF
cat >"$suite/c-silent.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
# Not a *.sh file: discovery must ignore it (run-tests.sh's glob contract).
printf 'echo "ok: must not be discovered"\n' >"$suite/d-ignored.bash"

out=$("$MEASURE" --repeats 1 "$suite" 2>&1)
rc=$?
assert_exit "a clean fixture suite measures successfully" 0 "$rc"
assert_contains "report names the discovered file count" "3 files" "$out"
assert_contains "report states the repeat count" "best of 1" "$out"
assert_contains "report states it measured serially" "serial" "$out"
assert_contains "a two-verdict file reports verdicts=2" "a-quick.sh verdicts=2" "$out"
assert_contains "a one-verdict file reports verdicts=1" "b-slow.sh verdicts=1" "$out"
assert_contains "a verdict-free file reports verdicts=0" "c-silent.sh verdicts=0" "$out"
assert_contains "the total best-time line is emitted" "total-best-seconds" "$out"
assert_contains "the total verdict line is emitted" "total-verdicts 3" "$out"

case "$out" in
  *d-ignored*) bad "discovery must be <suite-dir>/*.sh only (d-ignored.bash appeared)" ;;
  *) ok "discovery is <suite-dir>/*.sh only" ;;
esac

# Progress lines go to STDERR only, one per file as it completes, so a long run
# is observable while stdout stays the clean report a caller tees to an
# artifact. Split the streams to prove the separation rather than assuming it.
prog_err=$("$MEASURE" --repeats 1 "$suite" 2>&1 >/dev/null)
prog_out=$("$MEASURE" --repeats 1 "$suite" 2>/dev/null)
assert_contains "progress counts files as they complete, on stderr" "[1/3]" "$prog_err"
assert_contains "progress reaches the final file" "[3/3]" "$prog_err"
assert_contains "a progress line names its file" "a-quick.sh" "$prog_err"
case "$prog_out" in
  *"[1/3]"*) bad "progress must not pollute stdout (the report is tee'd to an artifact)" ;;
  *) ok "stdout carries no progress lines" ;;
esac

# Sub-second resolution: the slow file's time must carry a fractional part and
# be at least the 1s sleep. Parse its row.
slow_secs=$(printf '%s\n' "$out" | awk '$2 == "b-slow.sh" { print $1; exit }')
case "$slow_secs" in
  *.*) ok "per-file times carry sub-second resolution" ;;
  *) bad "per-file time '$slow_secs' has no fractional part" ;;
esac
if awk -v s="$slow_secs" 'BEGIN { exit !(s >= 1.0) }'; then
  ok "a 1s fixture measures at or above 1.0s"
else
  bad "a 1s fixture measured $slow_secs (expected >= 1.0)"
fi

# Ranking: slowest first. b-slow.sh must precede both quick files.
order=$(printf '%s\n' "$out" | awk '$2 ~ /\.sh$/ { print $2 }' | tr '\n' ' ')
case "$order" in
  "b-slow.sh "*) ok "rows are ranked slowest-first" ;;
  *) bad "rows not ranked slowest-first (order: $order)" ;;
esac

# Best-of-N: the minimum is reported. A fixture whose first run is slow and
# whose later runs are fast must report the fast time, so the report is a
# floor, not a first-run artifact.
bo="$tmp/bestof"
mkdir -p "$bo"
cat >"$bo/varies.sh" <<'EOF'
#!/bin/sh
n=$(cat "$MEASURE_FIXTURE_STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$MEASURE_FIXTURE_STATE"
[ "$n" -eq 1 ] && sleep 2
echo "ok: varies"
exit 0
EOF
MEASURE_FIXTURE_STATE="$tmp/varies-state"
export MEASURE_FIXTURE_STATE
out=$("$MEASURE" --repeats 3 "$bo" 2>&1)
rc=$?
assert_exit "a best-of-3 run over a varying fixture succeeds" 0 "$rc"
varies_secs=$(printf '%s\n' "$out" | awk '$2 == "varies.sh" { print $1; exit }')
if awk -v s="$varies_secs" 'BEGIN { exit !(s < 1.5) }'; then
  ok "best-of-N reports the minimum, not the first run"
else
  bad "best-of-N reported $varies_secs (expected the fast run, < 1.5s)"
fi
assert_contains "the repeat count is echoed for a best-of-3 run" "best of 3" "$out"
unset MEASURE_FIXTURE_STATE

# Positive accounting: a failing file is named and fails the run.
brk="$tmp/broken"
mkdir -p "$brk"
cat >"$brk/fine.sh" <<'EOF'
#!/bin/sh
echo "ok: fine"
EOF
cat >"$brk/broken.sh" <<'EOF'
#!/bin/sh
echo "ok: partial"
echo "FAIL: deliberate" >&2
exit 1
EOF
out=$("$MEASURE" --repeats 1 "$brk" 2>&1)
rc=$?
assert_exit "a failing test file fails the measurement run" 1 "$rc"
assert_contains "the failing file is named" "broken.sh" "$out"
assert_contains "the failure is called out, not just timed" "FAILED" "$out"
# A failure is visible in the progress stream too, so a watcher sees it when it
# happens rather than only in the end-of-run report.
brk_err=$("$MEASURE" --repeats 1 "$brk" 2>&1 >/dev/null)
assert_contains "progress marks a failing file as it completes" "broken.sh best=" "$brk_err"
case "$brk_err" in
  *"broken.sh"*FAILED*) ok "the progress line for a failing file carries FAILED" ;;
  *) bad "progress line for broken.sh lacks FAILED (got: $brk_err)" ;;
esac

# The diagnostic block must carry the output of the repeat that ACTUALLY failed.
# Under best-of-N a file can fail one repeat and pass the next, and the whole
# point of the block is to say why the run is not a valid baseline — printing a
# later clean repeat's output there reports a failure with no evidence of it.
flk="$tmp/flaky"
mkdir -p "$flk"
cat >"$flk/flaky.sh" <<'EOF'
#!/bin/sh
n=$(cat "$MEASURE_FIXTURE_STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$MEASURE_FIXTURE_STATE"
if [ "$n" -eq 1 ]; then
  echo "MARKER-FAILING-REPEAT" >&2
  exit 1
fi
echo "ok: MARKER-CLEAN-REPEAT"
exit 0
EOF
MEASURE_FIXTURE_STATE="$tmp/flaky-state"
export MEASURE_FIXTURE_STATE
out=$("$MEASURE" --repeats 2 "$flk" 2>/dev/null)
rc=$?
assert_exit "a file failing only its first repeat still fails the run" 1 "$rc"
assert_contains "the diagnostic block carries the failing repeat's output" \
  "MARKER-FAILING-REPEAT" "$out"
case "$out" in
  *MARKER-CLEAN-REPEAT*)
    bad "the diagnostic block substituted a later clean repeat's output"
    printf '%s\n%s\n%s\n' "----- output -----" "$out" "------------------" >&2
    ;;
  *) ok "the diagnostic block does not substitute a clean repeat's output" ;;
esac
unset MEASURE_FIXTURE_STATE

# Usage contract.
rc=0
"$MEASURE" --nope "$suite" >/dev/null 2>&1 || rc=$?
assert_exit "an unknown flag exits 2" 2 "$rc"
rc=0
"$MEASURE" --repeats >/dev/null 2>&1 || rc=$?
assert_exit "a flag without its value exits 2" 2 "$rc"
rc=0
"$MEASURE" --repeats 0 "$suite" >/dev/null 2>&1 || rc=$?
assert_exit "--repeats 0 exits 2" 2 "$rc"
rc=0
"$MEASURE" --repeats abc "$suite" >/dev/null 2>&1 || rc=$?
assert_exit "a non-numeric --repeats exits 2" 2 "$rc"
rc=0
"$MEASURE" --repeats 1 "$tmp/no-such-dir" >/dev/null 2>&1 || rc=$?
assert_exit "a missing suite directory exits 2" 2 "$rc"
mkdir -p "$tmp/empty"
rc=0
"$MEASURE" --repeats 1 "$tmp/empty" >/dev/null 2>&1 || rc=$?
assert_exit "an empty suite directory exits 2" 2 "$rc"
rc=0
"$MEASURE" --repeats 1 "$suite" extra >/dev/null 2>&1 || rc=$?
assert_exit "a trailing extra argument exits 2" 2 "$rc"
rc=0
"$MEASURE" -h >/dev/null 2>&1 || rc=$?
assert_exit "-h exits 0" 0 "$rc"
rc=0
"$MEASURE" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures assertion(s) failed" >&2
  exit 1
fi
echo "all measure-test-time checks passed"
