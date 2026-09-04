#!/bin/bash
# Tests for scripts/run-tests.sh — the bounded-parallel shell-test runner
# behind `mise run test`. The runner must divide suite wall-clock by the
# core count without weakening the gate: any single failing file still
# fails the run, is named, and has its captured output printed at the end
# (no interleaved garbage, no silently skipped siblings).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"

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
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2' in output; got: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2' in output; got: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$RUNNER" ]; then
  echo "FAIL: runner script missing at $RUNNER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Fixture suite A: all tests pass.
mkdir -p "$tmp/pass"
cat >"$tmp/pass/test-alpha.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
cat >"$tmp/pass/test-beta.sh" <<'EOF'
#!/bin/bash
echo "beta ran"
EOF

# Fixture suite B: one multi-line failure among passers, plus an exit-255
# test (the xargs abort code — the runner must not let it cancel siblings).
mkdir -p "$tmp/mixed"
cp "$tmp/pass/test-alpha.sh" "$tmp/mixed/test-alpha.sh"
cat >"$tmp/mixed/test-boom.sh" <<'EOF'
#!/bin/bash
echo "boom-line-one"
echo "boom-line-two" >&2
exit 3
EOF
cat >"$tmp/mixed/test-vanish.sh" <<'EOF'
#!/bin/bash
echo "vanish-detail"
exit 255
EOF

# 1. All-pass suite exits 0 and reports each file.
out="$(/bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "all-pass suite exits 0" 0 $?
assert_contains "passing file alpha reported" "test-alpha.sh" "$out"
assert_contains "passing file beta reported" "test-beta.sh" "$out"

# 2. A failing file fails the gate, is NAMED, and its captured stdout+stderr
#    both appear at the end; siblings still run to completion.
out="$(/bin/bash "$RUNNER" "$tmp/mixed" 2>&1)"
assert "mixed suite exits 1" 1 $?
assert_contains "failing file is named" "test-boom.sh" "$out"
assert_contains "failure log stdout is printed" "boom-line-one" "$out"
assert_contains "failure log stderr is printed" "boom-line-two" "$out"
assert_contains "exit-255 file is named (did not cancel the run)" \
  "test-vanish.sh" "$out"
assert_contains "exit-255 file's log is printed" "vanish-detail" "$out"
assert_contains "passing sibling still ran" "test-alpha.sh" "$out"

# 3. The serial degrade path preserves the same contract.
out="$(PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/mixed" 2>&1)"
assert "serial fallback: mixed suite exits 1" 1 $?
assert_contains "serial fallback: failing file named" "test-boom.sh" "$out"
assert_contains "serial fallback: failure log printed" "boom-line-one" "$out"
assert_contains "serial fallback: sibling still ran" "test-alpha.sh" "$out"
out="$(PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "serial fallback: all-pass suite exits 0" 0 $?

# 4. PLANWRIGHT_TEST_JOBS bounds the pool; a garbage value degrades to a
#    sane default instead of breaking the run.
out="$(PLANWRIGHT_TEST_JOBS=1 /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "explicit jobs=1 passes" 0 $?
out="$(PLANWRIGHT_TEST_JOBS=banana /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "non-numeric jobs value degrades sanely" 0 $?

# 5. An empty suite directory is a loud usage error, not a silent green.
mkdir -p "$tmp/empty"
/bin/bash "$RUNNER" "$tmp/empty" >/dev/null 2>&1
assert "empty suite dir is a usage error" 2 $?

# 6. A missing suite directory is the same usage error.
/bin/bash "$RUNNER" "$tmp/no-such-dir" >/dev/null 2>&1
assert "missing suite dir is a usage error" 2 $?

# 7. Concurrent output stays per-file: two chatty passers each keep their
#    own line intact (no split/interleaved fragments of the marker lines).
mkdir -p "$tmp/chatty"
i=1
while [ "$i" -le 6 ]; do
  cat >"$tmp/chatty/test-chat$i.sh" <<EOF
#!/bin/bash
j=1
while [ "\$j" -le 50 ]; do
  echo "chat$i-marker-\$j"
  j=\$((j + 1))
done
EOF
  i=$((i + 1))
done
out="$(/bin/bash "$RUNNER" "$tmp/chatty" 2>&1)"
assert "chatty concurrent suite exits 0" 0 $?
# A passing file's noise stays in its log, not on the runner's stream.
assert_not_contains "passing files' raw output is not interleaved" \
  "chat1-marker-25" "$out"

# 8. Load headroom: the runner saturates every core, so the suite gets a
#    generous SPEC_WALKTHROUGH_DOT_TIMEOUT default (spec-graph's 5s `dot`
#    watchdog fires spuriously mid-run otherwise); an explicit caller
#    value still wins.
mkdir -p "$tmp/env"
cat >"$tmp/env/test-timeout.sh" <<'EOF'
#!/bin/bash
[ "${SPEC_WALKTHROUGH_DOT_TIMEOUT:-}" = "${EXPECTED_DOT_TIMEOUT:?}" ]
EOF
EXPECTED_DOT_TIMEOUT=60 /bin/bash "$RUNNER" "$tmp/env" >/dev/null 2>&1
assert "suite runs get the generous dot-watchdog default" 0 $?
SPEC_WALKTHROUGH_DOT_TIMEOUT=7 EXPECTED_DOT_TIMEOUT=7 \
  /bin/bash "$RUNNER" "$tmp/env" >/dev/null 2>&1
assert "an explicit dot-watchdog value is not overridden" 0 $?

# 9. A filename with a space survives dispatch intact.
mkdir -p "$tmp/space"
cat >"$tmp/space/test with space.sh" <<'EOF'
#!/bin/bash
echo "space ran"
exit 4
EOF
out="$(/bin/bash "$RUNNER" "$tmp/space" 2>&1)"
assert "spaced filename failure fails the gate" 1 $?
assert_contains "spaced filename is named" "test with space.sh" "$out"

# 10. Gate integrity: a worker killed before it can record a verdict (here
#     the test SIGKILLs its own worker bash) must fail the run and be named
#     as never-completed. Marker absence is not proof of success: without
#     positive completion accounting this is a false green (the exact
#     regression the serial loop's `|| exit 1` never had).
mkdir -p "$tmp/killer"
cp "$tmp/pass/test-alpha.sh" "$tmp/killer/test-alpha.sh"
cat >"$tmp/killer/test-killer.sh" <<'EOF'
#!/bin/bash
kill -9 $PPID
sleep 1
EOF
out="$(/bin/bash "$RUNNER" "$tmp/killer" 2>&1)"
assert "killed-worker suite fails the gate" 1 $?
assert_contains "killed-worker file is named as not completed" \
  "test-killer.sh" "$out"
out="$(PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/killer" 2>&1)"
assert "serial fallback: killed-worker suite fails the gate" 1 $?
assert_contains "serial fallback: killed-worker file is named" \
  "test-killer.sh" "$out"

# 11. The success contract in full: summary line, per-file duration
#     suffix, and the requested job count reflected in the header.
out="$(PLANWRIGHT_TEST_JOBS=3 /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "success-contract run exits 0" 0 $?
assert_contains "success summary counts every file" \
  "all 2 test files passed" "$out"
assert_contains "requested job count appears in the header" \
  "2 files, 3 jobs" "$out"
case "$out" in
  *"ok: test-alpha.sh ("*"s)"*) echo "ok: ok-line carries a duration suffix" ;;
  *)
    echo "FAIL: ok-line duration suffix missing; got: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 12. Genuine concurrency: two tests that each drop a beacon and wait for
#     the other's can only both pass when they overlap. The serial run of
#     the same fixture is the negative control — it must time out and
#     fail, proving the fixture detects serialized execution (and so that
#     the parallel path is not accidentally serial).
mkdir -p "$tmp/overlap" "$tmp/sync"
for pair in one:two two:one; do
  me="${pair%%:*}"
  peer="${pair##*:}"
  cat >"$tmp/overlap/test-$me.sh" <<EOF
#!/bin/bash
: >"$tmp/sync/$me.here"
i=0
while [ \$i -lt 40 ]; do
  [ -e "$tmp/sync/$peer.here" ] && exit 0
  sleep 0.25
  i=\$((i + 1))
done
exit 1
EOF
done
PLANWRIGHT_TEST_JOBS=2 /bin/bash "$RUNNER" "$tmp/overlap" >/dev/null 2>&1
assert "overlapping fixtures pass: files genuinely run concurrently" 0 $?
rm -f "$tmp/sync"/*.here
PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/overlap" \
  >/dev/null 2>&1
assert "negative control: serialized execution fails the overlap fixture" \
  1 $?

# 13. Serial fallback also names and logs the exit-255 file (the parallel
#     arm of this guarantee is test 2).
out="$(PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/mixed" 2>&1)"
assert "serial fallback: mixed suite still exits 1" 1 $?
assert_contains "serial fallback: exit-255 file is named" \
  "test-vanish.sh" "$out"
assert_contains "serial fallback: exit-255 file's log is printed" \
  "vanish-detail" "$out"

# 14. The xargs probe itself degrades to serial when -P is unusable (the
#     FORCE_SERIAL override in test 3 bypasses the probe; this drives it).
mkdir -p "$tmp/shim"
cat >"$tmp/shim/xargs" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/shim/xargs"
out="$(PATH="$tmp/shim:$PATH" /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "broken xargs -P degrades to a passing serial run" 0 $?
assert_contains "probe failure is reported as the serial mode" \
  "serial (no parallel primitive)" "$out"

# 15. A failed log-dir mktemp is a loud environment error, never a green.
TMPDIR="$tmp/no-such-tmp/x" /bin/bash "$RUNNER" "$tmp/pass" >/dev/null 2>&1
assert "log-dir mktemp failure exits 2" 2 $?

# 16. Timing capture round-trip (guard-coverage REQ-E1.1, D-8): after a run
#     the runner persists a per-file timing report beside the suite, one
#     entry per file, at sub-second resolution, plus the suite wall-clock.
#     Each worker writes its own record, so the parallel run below is the
#     concurrency case: every file must still have exactly one entry.
mkdir -p "$tmp/timed"
cp "$tmp/pass/test-alpha.sh" "$tmp/timed/test-alpha.sh"
cat >"$tmp/timed/test-sleepy.sh" <<'EOF'
#!/bin/bash
sleep 0.3
echo "sleepy ran"
EOF
cp "$tmp/pass/test-beta.sh" "$tmp/timed/test-beta.sh"
report="$tmp/timed/.timing-report.tsv"
rm -f "$report"
out="$(PLANWRIGHT_TEST_JOBS=3 /bin/bash "$RUNNER" "$tmp/timed" 2>&1)"
assert "timed suite passes" 0 $?
if [ -f "$report" ]; then
  echo "ok: the timing report is written beside the suite"
else
  echo "FAIL: no timing report at $report" >&2
  failures=$((failures + 1))
fi
header="$(head -n 1 "$report" 2>/dev/null)"
case "$header" in
  "planwright-test-timing	1	"*) echo "ok: the report opens with the versioned header" ;;
  *)
    echo "FAIL: unexpected report header: $header" >&2
    failures=$((failures + 1))
    ;;
esac
for name in test-alpha.sh test-sleepy.sh test-beta.sh; do
  n="$(grep -c "^file	$name	[0-9][0-9]*\(\.[0-9][0-9]*\)\?\$" "$report" 2>/dev/null)"
  if [ "$n" -eq 1 ]; then
    echo "ok: exactly one numeric timing entry for $name"
  else
    echo "FAIL: expected one timing entry for $name, found $n" >&2
    failures=$((failures + 1))
  fi
done
sleepy="$(awk -F'\t' '$1=="file" && $2=="test-sleepy.sh"{print $3}' "$report")"
wall="$(awk -F'\t' '$1=="suite" && $2=="wall"{print $3}' "$report")"
case "$header" in
  *"clock=seconds"*)
    echo "ok: no sub-second clock on this host; resolution bound skipped"
    ;;
  *)
    if awk -v t="$sleepy" 'BEGIN{exit !(t >= 0.25 && t < 10)}'; then
      echo "ok: the sleeping file's time is sub-second and plausibly bounded ($sleepy)"
    else
      echo "FAIL: sleeping file's time is not plausibly bounded: '$sleepy'" >&2
      failures=$((failures + 1))
    fi
    ;;
esac
if awk -v w="$wall" -v t="$sleepy" 'BEGIN{exit !(w != "" && t != "" && w >= t)}'; then
  echo "ok: the suite wall-clock row is present and covers the slowest file ($wall)"
else
  echo "FAIL: suite wall-clock row missing or below the slowest file: '$wall'" >&2
  failures=$((failures + 1))
fi
assert_not_contains "the report contains no verdict-less placeholder" \
  "	-" "$(cat "$report")"

# The serial fallback writes the same report.
rm -f "$report"
PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/timed" >/dev/null 2>&1
assert "serial fallback: timed suite passes" 0 $?
n="$(grep -c '^file	' "$report" 2>/dev/null)"
if [ "$n" -eq 3 ]; then
  echo "ok: serial fallback writes one entry per file"
else
  echo "FAIL: serial fallback wrote $n entries, expected 3" >&2
  failures=$((failures + 1))
fi

# 17. The report path is overridable, so a caller can direct it elsewhere
#     without touching the suite directory.
PLANWRIGHT_TEST_TIMING_REPORT="$tmp/elsewhere.tsv" \
  /bin/bash "$RUNNER" "$tmp/pass" >/dev/null 2>&1
assert "an explicit report path is honoured" 0 $?
if grep -q '^file	test-alpha.sh	' "$tmp/elsewhere.tsv" 2>/dev/null; then
  echo "ok: the redirected report holds the entries"
else
  echo "FAIL: redirected report missing or empty" >&2
  failures=$((failures + 1))
fi

# 18. Positive accounting: a file that produced a verdict but no timing entry
#     fails the run. The fault here is real, not injected — with no usable
#     clock at all (date and python3 both broken), the worker cannot time the
#     file, and the run must say so rather than report a green suite whose
#     budget gate would then fail closed on a hole in the report.
mkdir -p "$tmp/noclock"
for bin in date python3; do
  printf '#!/bin/sh\nexit 1\n' >"$tmp/noclock/$bin"
  chmod +x "$tmp/noclock/$bin"
done
out="$(PATH="$tmp/noclock:$PATH" /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "a verdict without a timing entry fails the run" 1 $?
assert_contains "the timing hole is named" "no timing entry" "$out"
assert_contains "the timing hole names the file" "test-alpha.sh" "$out"

# 19. A report that cannot be persisted is a loud environment error: the
#     budget gate downstream would otherwise fail closed on a missing file
#     with no hint of why.
out="$(PLANWRIGHT_TEST_TIMING_REPORT="$tmp/no-such-dir/report.tsv" \
  /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "an unwritable report path exits 2" 2 $?
assert_contains "the unwritable-report failure names the path" \
  "no-such-dir/report.tsv" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all run-tests tests passed"
