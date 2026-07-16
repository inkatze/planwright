#!/bin/bash
# Bounded-parallel shell-test runner behind `mise run test`. Runs every
# <suite-dir>/*.sh under /bin/bash (the bash 3.2 floor), N files at a time
# (N = hw.ncpu / nproc, override via PLANWRIGHT_TEST_JOBS), capturing each
# file's stdout+stderr to a per-file log so concurrent output never
# interleaves. The gate semantics match the old serial loop: any failing
# file fails the run; every failing file is named and its captured log is
# printed at the end. All files always run to completion (no mid-run
# abort), so one failure never hides another.
#
# Parallelism comes from `xargs -P` (POSIX-optional but present on macOS
# and GNU userlands alike); when the probe finds no working -P — or
# PLANWRIGHT_TEST_FORCE_SERIAL=1 — the runner degrades to a serial loop
# with the same capture-and-summarize contract.
#
# Usage: run-tests.sh [suite-dir]   (default: <repo-root>/tests)
# Exit:  0 all pass, 1 any test failed, 2 usage error.
set -u
unset CDPATH

# Worker mode: run ONE test file, capturing its output to the log dir the
# parent exported. Always exits 0 — a test's own exit code (255 included,
# which would otherwise make xargs abort the whole run) is recorded as a
# .fail marker for the parent's summary, never propagated to xargs.
if [ "${1:-}" = "--run-one" ]; then
  t="$2"
  name="${t##*/}"
  if /bin/bash "$t" >"$PLANWRIGHT_TEST_LOG_DIR/$name.log" 2>&1; then
    echo "ok: $name"
  else
    echo "FAIL: $name (log printed at end)" >&2
    : >"$PLANWRIGHT_TEST_LOG_DIR/$name.fail"
  fi
  exit 0
fi

self="$(cd "$(dirname "$0")" && pwd)/${0##*/}"
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

if [ "$parallel" -eq 1 ]; then
  echo "run-tests: ${#files[@]} files, $jobs jobs"
  printf '%s\0' "${files[@]}" \
    | xargs -0 -n 1 -P "$jobs" /bin/bash "$self" --run-one
else
  echo "run-tests: ${#files[@]} files, serial (no parallel primitive)"
  for t in "${files[@]}"; do
    /bin/bash "$self" --run-one "$t"
  done
fi

# Summary: name every failing file and replay its captured log.
fails=0
for marker in "$log_dir"/*.fail; do
  [ -e "$marker" ] || continue
  name="${marker##*/}"
  name="${name%.fail}"
  fails=$((fails + 1))
  echo ""
  echo "=== FAIL: $name ==="
  cat "$log_dir/$name.log"
done

if [ "$fails" -gt 0 ]; then
  echo ""
  echo "run-tests: $fails of ${#files[@]} test file(s) failed" >&2
  exit 1
fi
echo "run-tests: all ${#files[@]} test files passed"
