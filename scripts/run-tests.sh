#!/bin/bash
# Bounded-parallel shell-test runner behind `mise run test`. Runs every
# <suite-dir>/*.sh under /bin/bash (the bash 3.2 floor), N files at a time
# (N = hw.ncpu / nproc), capturing each file's stdout+stderr to a per-file
# log so the tests' own concurrent output never interleaves (the runner's
# one-line ok/FAIL markers share the parent's streams and stay whole
# under PIPE_BUF). The gate semantics match the old serial loop: any failing
# file fails the run; every failing file is named and its captured log is
# printed at the end. All files always run to completion (no mid-run
# abort), so one failure never hides another. Completion accounting is
# positive: a file that never produced a verdict marker (worker killed,
# never dispatched) is a failure, never a silent green.
#
# Parallelism comes from `xargs -P` (POSIX-optional but present on macOS
# and GNU userlands alike); when the probe finds no working -P — or
# PLANWRIGHT_TEST_FORCE_SERIAL=1 — the runner degrades to a serial loop
# with the same capture-and-summarize contract.
#
# Timing capture: every worker records its own file's wall-clock at
# sub-second resolution in its own record (no shared-file append race under
# the parallel pool), and the parent aggregates the records into one report
# after the pool drains, written atomically to a stable path beside the suite
# (<suite-dir>/.timing-report.tsv, gitignored; override with
# PLANWRIGHT_TEST_TIMING_REPORT). scripts/check-test-time.sh reads that
# report against the committed budgets instead of re-running the suite. The
# accounting is positive here too: a file with a verdict but no timing record
# fails the run, so the report never carries a silent hole.
#
# Usage: run-tests.sh [suite-dir]   (default: <repo-root>/tests)
# Exit:  0 all pass · 1 any test failed or lost · 2 usage or environment
#        error (bad suite dir, mktemp or self-path resolution failure, a
#        timing report that cannot be persisted).
#
# Environment:
#   PLANWRIGHT_TEST_JOBS           override the job count (default: core count)
#   PLANWRIGHT_TEST_FORCE_SERIAL   1 forces the serial fallback path
#   PLANWRIGHT_TEST_TIMING_REPORT  where to persist the timing report
#                                  (default: <suite-dir>/.timing-report.tsv)
#   SPEC_WALKTHROUGH_DOT_TIMEOUT   exported to every test (default 60 here:
#                                  suite load headroom; caller value wins)
#   PLANWRIGHT_TEST_LOG_DIR        internal: parent-to-worker log dir handoff
#   PLANWRIGHT_TEST_CLOCK          internal: parent-to-worker clock handoff
set -u
unset CDPATH

# Sub-second clock, the same probe scripts/measure-test-time.sh uses: a real
# 9-digit nanosecond field from `date +%N` (GNU and BSD date both have it;
# GNU's `%3N` precision modifier is not portable), else python3, else whole
# seconds as a last resort that says so. The parent probes once and hands the
# choice to every worker so the suite is timed on one clock.
probe_clock() {
  _probe="$(date +%N 2>/dev/null)"
  case "$_probe" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) echo date-ns ;;
    *)
      if command -v python3 >/dev/null 2>&1; then
        echo python3
      else
        echo seconds
      fi
      ;;
  esac
}

# Milliseconds since the epoch on the chosen clock, or nothing at all when
# the clock cannot be read: an empty reading leaves no timing record, which
# the parent's accounting turns into a named failure rather than a guess.
now_ms() {
  case "$clock" in
    date-ns)
      _t="$(date '+%s %N' 2>/dev/null)"
      case "$_t" in
        [0-9]*' '[0-9]*) echo "$((${_t%% *} * 1000 + 10#${_t##* } / 1000000))" ;;
        *) echo "" ;;
      esac
      ;;
    python3)
      python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || echo ""
      ;;
    *)
      _s="$(date +%s 2>/dev/null)"
      case "$_s" in
        [0-9]*) echo "$((_s * 1000))" ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

# ms_to_seconds <ms> — "12.345", the report's unit.
ms_to_seconds() {
  printf '%d.%03d' "$(($1 / 1000))" "$(($1 % 1000))"
}

# Worker mode: run ONE test file, capturing its output to the log dir the
# parent exported. Always exits 0 — a test's own exit code (255 included,
# which would otherwise make xargs abort the whole run) is recorded as a
# .done or .fail marker for the parent's summary, never propagated to
# xargs. The parent requires a marker per input file, so a worker that
# dies before writing one (SIGKILL, ENOSPC, never dispatched) is a
# failure, never a silent green.
if [ "${1:-}" = "--run-one" ]; then
  t="$2"
  name="${t##*/}"
  clock="${PLANWRIGHT_TEST_CLOCK:-}"
  [ -n "$clock" ] || clock="$(probe_clock)"
  started="$(now_ms)"
  if /bin/bash "$t" >"$PLANWRIGHT_TEST_LOG_DIR/$name.log" 2>&1; then
    verdict="done"
  else
    verdict="fail"
  fi
  finished="$(now_ms)"
  # The timing record is this worker's own file, written before the verdict
  # marker so a marker never exists without its record having been attempted.
  elapsed=""
  if [ -n "$started" ] && [ -n "$finished" ]; then
    elapsed="$(ms_to_seconds $((finished - started)))"
    printf '%s\n' "$elapsed" >"$PLANWRIGHT_TEST_LOG_DIR/$name.time"
  fi
  : >"$PLANWRIGHT_TEST_LOG_DIR/$name.$verdict"
  if [ "$verdict" = "done" ]; then
    echo "ok: $name (${elapsed:-?}s)"
  else
    echo "FAIL: $name (log printed at end)" >&2
  fi
  exit 0
fi

self="$(cd "$(dirname "$0")" && pwd)/${0##*/}"
if [ ! -f "$self" ]; then
  echo "run-tests: cannot resolve own path (got: $self)" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
suite_dir="${1:-$repo_root/tests}"

if [ ! -d "$suite_dir" ]; then
  echo "run-tests: suite directory not found: $suite_dir" >&2
  exit 2
fi

files=("$suite_dir"/*.sh)
if [ "${#files[@]}" -eq 0 ] || [ ! -e "${files[0]}" ]; then
  echo "run-tests: no *.sh test files in $suite_dir" >&2
  exit 2
fi

# Job count: explicit override wins; else the machine's core count
# (sysctl on darwin, nproc on GNU); a missing or garbage value degrades
# to a safe fixed default rather than failing the gate.
jobs="${PLANWRIGHT_TEST_JOBS:-}"
if [ -z "$jobs" ]; then
  jobs="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || true)"
fi
case "$jobs" in
  '' | *[!0-9]*) jobs=4 ;;
esac
[ "$jobs" -ge 1 ] || jobs=1

# Load headroom: the suite saturates every core, so latency-sensitive
# watchdogs calibrated for an idle interactive run — spec-graph.sh's 5s
# `dot` bound — fire spuriously mid-suite and flake layout/determinism
# assertions. Grant the whole suite a generous bound; an explicit caller
# value still wins. No test asserts the watchdog's default, so this
# weakens no assertion.
export SPEC_WALKTHROUGH_DOT_TIMEOUT="${SPEC_WALKTHROUGH_DOT_TIMEOUT:-60}"

# Explicit template: a bare `mktemp` default template is not portable to
# BSD mktemp (the house pattern, see scripts/spec-graph.sh).
log_dir="$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")" || exit 2
trap 'rm -rf "$log_dir"' EXIT
export PLANWRIGHT_TEST_LOG_DIR="$log_dir"

clock="$(probe_clock)"
export PLANWRIGHT_TEST_CLOCK="$clock"
if [ "$clock" = seconds ]; then
  echo "run-tests: WARNING no sub-second clock available; times are whole seconds" >&2
fi
report="${PLANWRIGHT_TEST_TIMING_REPORT:-$suite_dir/.timing-report.tsv}"

# Probe for a working `xargs -P` before relying on it; degrade to the
# serial loop when it is absent or explicitly disabled.
parallel=1
if [ "${PLANWRIGHT_TEST_FORCE_SERIAL:-0}" = "1" ]; then
  parallel=0
elif ! printf 'x\0' | xargs -0 -n 1 -P 2 true >/dev/null 2>&1; then
  parallel=0
fi

# A non-zero dispatcher exit (xargs aborting on a signal-killed worker, a
# failed exec) is a gate failure in its own right; the reconciliation
# below then names the files that never produced a verdict.
dispatch_failed=0
suite_started="$(now_ms)"
if [ "$parallel" -eq 1 ]; then
  mode=parallel
  echo "run-tests: ${#files[@]} files, $jobs jobs"
  printf '%s\0' "${files[@]}" \
    | xargs -0 -n 1 -P "$jobs" /bin/bash "$self" --run-one \
    || dispatch_failed=1
else
  mode=serial
  echo "run-tests: ${#files[@]} files, serial (no parallel primitive)"
  for t in "${files[@]}"; do
    /bin/bash "$self" --run-one "$t" || dispatch_failed=1
  done
fi
suite_finished="$(now_ms)"

# Summary with positive accounting: every input file must have produced a
# verdict marker. A .fail names a real test failure (log replayed); a file
# with neither marker never completed — its worker died or was never
# dispatched — and marker absence must count as failure, never success.
# The timing report is aggregated from the per-worker records only now,
# after the pool has drained, so no two writers ever touch it. A file with a
# verdict marker but no record is a hole the budget gate would fail closed
# on; naming it here is the honest half of that contract.
report_tmp="$report.tmp.$$"
{
  printf 'planwright-test-timing\t1\tclock=%s\tmode=%s\tjobs=%s\n' "$clock" "$mode" "$jobs"
} >"$report_tmp" 2>/dev/null || report_tmp=""

fails=0
for t in "${files[@]}"; do
  name="${t##*/}"
  if [ -e "$log_dir/$name.fail" ]; then
    fails=$((fails + 1))
    echo ""
    echo "=== FAIL: $name ==="
    cat "$log_dir/$name.log" 2>/dev/null || echo "(no captured log)"
  elif [ ! -e "$log_dir/$name.done" ]; then
    fails=$((fails + 1))
    echo ""
    echo "=== FAIL: $name (never completed: worker died or was not dispatched) ==="
    cat "$log_dir/$name.log" 2>/dev/null || echo "(no captured log)"
    continue
  fi
  if [ -s "$log_dir/$name.time" ]; then
    if [ -n "$report_tmp" ]; then
      IFS= read -r elapsed <"$log_dir/$name.time"
      printf 'file\t%s\t%s\n' "$name" "$elapsed" >>"$report_tmp"
    fi
  else
    fails=$((fails + 1))
    echo ""
    echo "=== FAIL: $name (verdict recorded but no timing entry: the clock could not be read) ==="
  fi
done

report_failed=0
if [ -n "$report_tmp" ] && [ -n "$suite_started" ] && [ -n "$suite_finished" ]; then
  printf 'suite\twall\t%s\n' "$(ms_to_seconds $((suite_finished - suite_started)))" >>"$report_tmp"
fi
if [ -z "$report_tmp" ] || ! mv -f "$report_tmp" "$report" 2>/dev/null; then
  rm -f "$report_tmp"
  echo "run-tests: could not persist the timing report at $report" >&2
  report_failed=1
fi

if [ "$fails" -gt 0 ]; then
  echo ""
  echo "run-tests: $fails of ${#files[@]} test file(s) failed" >&2
  exit 1
fi
if [ "$dispatch_failed" -ne 0 ]; then
  echo "run-tests: dispatcher exited non-zero with no per-file failure recorded" >&2
  exit 1
fi
if [ "$report_failed" -ne 0 ]; then
  exit 2
fi
echo "run-tests: all ${#files[@]} test files passed"
