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
# Usage: run-tests.sh [suite-dir]   (default: <repo-root>/tests)
# Exit:  0 all pass · 1 any test failed or lost · 2 usage or environment
#        error (bad suite dir, mktemp or self-path resolution failure).
#
# Environment:
#   PLANWRIGHT_TEST_JOBS          override the job count (default: core count)
#   PLANWRIGHT_TEST_FORCE_SERIAL  1 forces the serial fallback path
#   SPEC_WALKTHROUGH_DOT_TIMEOUT  exported to every test (default 60 here:
#                                 suite load headroom; caller value wins)
#   PLANWRIGHT_TEST_LOG_DIR       internal: parent-to-worker log dir handoff
set -u
unset CDPATH

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
  started="$(date +%s)"
  if /bin/bash "$t" >"$PLANWRIGHT_TEST_LOG_DIR/$name.log" 2>&1; then
    : >"$PLANWRIGHT_TEST_LOG_DIR/$name.done"
    echo "ok: $name ($(($(date +%s) - started))s)"
  else
    echo "FAIL: $name (log printed at end)" >&2
    : >"$PLANWRIGHT_TEST_LOG_DIR/$name.fail"
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

log_dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$log_dir"' EXIT
export PLANWRIGHT_TEST_LOG_DIR="$log_dir"

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
if [ "$parallel" -eq 1 ]; then
  echo "run-tests: ${#files[@]} files, $jobs jobs"
  printf '%s\0' "${files[@]}" \
    | xargs -0 -n 1 -P "$jobs" /bin/bash "$self" --run-one \
    || dispatch_failed=1
else
  echo "run-tests: ${#files[@]} files, serial (no parallel primitive)"
  for t in "${files[@]}"; do
    /bin/bash "$self" --run-one "$t" || dispatch_failed=1
  done
fi

# Summary with positive accounting: every input file must have produced a
# verdict marker. A .fail names a real test failure (log replayed); a file
# with neither marker never completed — its worker died or was never
# dispatched — and marker absence must count as failure, never success.
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
  fi
done

if [ "$fails" -gt 0 ]; then
  echo ""
  echo "run-tests: $fails of ${#files[@]} test file(s) failed" >&2
  exit 1
fi
if [ "$dispatch_failed" -ne 0 ]; then
  echo "run-tests: dispatcher exited non-zero with no per-file failure recorded" >&2
  exit 1
fi
echo "run-tests: all ${#files[@]} test files passed"
