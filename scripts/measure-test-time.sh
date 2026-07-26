#!/bin/bash
# Out-of-gate per-file wall-clock measurement for the shell test suite
# (guard-coverage Task 6, REQ-E1.2, D-9). It answers one question: how long
# does each test file take on its own, and how many verdicts does it emit?
#
# This is an INSTRUMENT, not a gate. It never runs inside `mise run check`:
# the numbers it produces are what guard-coverage Task 7's committed
# `check:test-time` budgets are derived FROM, and re-measuring inside the
# 15-minute gated job would both double the suite's cost and perturb the
# very timings being budgeted. The dedicated measurement run lives in
# .github/workflows/test-timing.yml.
#
# Two deliberate departures from scripts/run-tests.sh:
#   - SERIAL. The gated runner saturates every core, so a per-file time taken
#     under it measures contention, not the file. Measurement runs one file at
#     a time.
#   - BEST-OF-N. Each file runs N times (default 3) and the MINIMUM is
#     reported. A minimum is the noise floor: scheduler jitter, page cache
#     misses, and neighbour load only ever push a sample up, so the smallest
#     sample is the closest estimate of the file's own cost. This bounds noise
#     without a whole-suite re-run inside the gated job.
#
# Accounting is positive, mirroring run-tests.sh: a test file that exits
# non-zero on any repeat is named, marked FAILED, and fails the whole run — a
# broken suite never measures into a clean-looking baseline.
#
# The verdict count is each file's own `ok`-prefixed stdout lines, covering
# both house styles (`ok: <label>` and `ok <n>: <label>`). That is the
# mechanically-defined assertion-count metric REQ-E1.2 compares across a
# straggler split: splitting a file moves verdict lines between files but must
# never reduce the total.
#
# Usage: measure-test-time.sh [--repeats N] [suite-dir]
#        (default suite-dir: <repo-root>/tests; default N: 3)
# Exit:  0 all files passed and were measured · 1 a test file failed
#        · 2 usage or environment error
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

usage() {
  cat <<'EOF'
Usage: measure-test-time.sh [--repeats N] [suite-dir]

Measures each <suite-dir>/*.sh test file's wall-clock time serially,
best-of-N, and reports it alongside the file's emitted verdict count.
An instrument, not a gate: never wire this into `mise run check`.

  --repeats N   runs per file, minimum reported (default 3, range 1-99)
  -h, --help    this message

Report: one row per file, ranked slowest-first, as
  <best-seconds> <file> verdicts=<n> [FAILED]
followed by `total-best-seconds <sum>` and `total-verdicts <sum>`.
EOF
}

repeats=3
suite_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repeats)
      [ "$#" -ge 2 ] || {
        echo "measure-test-time: --repeats needs a value" >&2
        exit 2
      }
      repeats="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "measure-test-time: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      [ -z "$suite_dir" ] || {
        echo "measure-test-time: unexpected extra argument: $1" >&2
        exit 2
      }
      suite_dir="$1"
      shift
      ;;
  esac
done

repeats_max=99
case "$repeats" in
  '' | *[!0-9]*)
    echo "measure-test-time: --repeats must be a positive integer (got: $repeats)" >&2
    exit 2
    ;;
esac
# Digit-only is not yet safe: a value past the shell's signed-integer range
# makes every `[ -lt ]` below error out, and an errored test reads as FALSE.
# Unguarded, `--repeats 9223372036854775808` would clear the `< 1` check, then
# fail the loop's own bound the same way, run zero repeats, and print an
# all-zero report while exiting 0 — a silently invalid baseline, the one
# outcome an instrument feeding Task 7's budgets must never produce. So the
# length is checked BEFORE any arithmetic touches the value. run-tests.sh dodges
# this by falling back to a safe default (`[ "$jobs" -ge 1 ] || jobs=1`); here a
# wrong N must be refused rather than silently substituted, because the caller
# asked for a specific measurement.
#
# The same guard caps the work factor. This runs serially, so cost is N x a full
# serial suite pass — already hours at the default N=3. Nothing needs more than
# a couple of dozen repeats to bound noise, and an in-range typo like 100000
# would otherwise burn the job's whole 330-minute budget and produce nothing.
if [ "${#repeats}" -gt "${#repeats_max}" ] \
  || [ "$repeats" -lt 1 ] || [ "$repeats" -gt "$repeats_max" ]; then
  echo "measure-test-time: --repeats must be between 1 and $repeats_max (got: $repeats)" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
[ -n "$suite_dir" ] || suite_dir="$repo_root/tests"
if [ ! -d "$suite_dir" ]; then
  echo "measure-test-time: suite directory not found: $suite_dir" >&2
  exit 2
fi

# Discovery matches run-tests.sh exactly — <suite-dir>/*.sh, non-recursive —
# so the measured set is the gated set, never a superset or subset of it.
files=("$suite_dir"/*.sh)
if [ "${#files[@]}" -eq 0 ] || [ ! -e "${files[0]}" ]; then
  echo "measure-test-time: no *.sh test files in $suite_dir" >&2
  exit 2
fi

# Sub-second clock. `%N` (nanoseconds) is supported by GNU date and by the BSD
# date macOS ships, but GNU's precision modifier (`%3N`) is NOT portable — BSD
# emits a literal "3N" for it — so the seconds and nanoseconds are taken as two
# fields and combined here. Probe for a real 9-digit nanosecond field before
# trusting it; python3 is the fallback (present on the reference runner and on
# macOS dev boxes); whole seconds is the last resort and says so, because a
# 0.000-resolution report would silently understate every fast file.
clock=seconds
probe="$(date +%N 2>/dev/null)"
case "$probe" in
  # A literal "N" (unsupported), an empty probe, or anything non-numeric means
  # there is no usable nanosecond field.
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) clock=date-ns ;;
  *) ;;
esac
if [ "$clock" = seconds ] && command -v python3 >/dev/null 2>&1; then
  clock=python3
fi

now_ms() {
  case "$clock" in
    date-ns)
      # `10#` forces base 10: a nanosecond field with leading zeros would
      # otherwise be read as octal and reject its 8/9 digits.
      _t="$(date '+%s %N')"
      echo "$((${_t%% *} * 1000 + 10#${_t##* } / 1000000))"
      ;;
    python3) python3 -c 'import time; print(int(time.time() * 1000))' ;;
    *) echo "$(($(date +%s) * 1000))" ;;
  esac
}

# The same environment run-tests.sh grants the suite, so a file measured here
# behaves as it does under the gate (SPEC_WALKTHROUGH_DOT_TIMEOUT in
# particular: without it, spec-graph's 5s `dot` bound flakes).
export SPEC_WALKTHROUGH_DOT_TIMEOUT="${SPEC_WALKTHROUGH_DOT_TIMEOUT:-60}"

echo "measure-test-time: ${#files[@]} files, best of $repeats, serial (clock: $clock)"
if [ "$clock" = seconds ]; then
  echo "measure-test-time: WARNING no sub-second clock available; times are whole seconds" >&2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/measure-test-time.XXXXXX")" || exit 2
trap 'rm -rf "$work"' EXIT
rows="$work/rows"
: >"$rows"

# Progress goes to STDERR, one line per file as it completes, so stdout stays
# the clean report the caller tees to an artifact. A serial best-of-N pass over
# a large suite runs for a long time and the report only prints at the end;
# without this a watcher cannot tell a slow run from a hung one, or estimate
# whether it will finish inside the job's timeout.
any_failed=0
done_n=0
for t in "${files[@]}"; do
  name="${t##*/}"
  best_ms=""
  verdicts=0
  failed=0
  r=0
  while [ "$r" -lt "$repeats" ]; do
    r=$((r + 1))
    start="$(now_ms)"
    if ! /bin/bash "$t" >"$work/out" 2>"$work/err"; then
      # Preserve the FIRST failing repeat's streams. Under best-of-N a file can
      # fail one repeat and pass the next, and $work/out is reused every repeat,
      # so the diagnostic block below would otherwise report a failure while
      # printing a later clean run's output — a failure with no evidence of it.
      if [ "$failed" -eq 0 ]; then
        cp "$work/out" "$work/fail-out" 2>/dev/null
        cp "$work/err" "$work/fail-err" 2>/dev/null
      fi
      failed=1
    fi
    end="$(now_ms)"
    elapsed=$((end - start))
    [ "$elapsed" -ge 0 ] || elapsed=0
    if [ -z "$best_ms" ] || [ "$elapsed" -lt "$best_ms" ]; then
      best_ms="$elapsed"
    fi
    # Verdicts come from the LAST repeat only: counting every repeat would
    # multiply the metric by N. Every repeat runs the same file, so the count
    # is repeat-invariant in practice; taking one keeps the sum comparable to
    # a single-run baseline by construction.
    verdicts="$(grep -c '^ok[ :]' "$work/out" 2>/dev/null)" || verdicts=0
  done
  if [ "$failed" -ne 0 ]; then
    any_failed=1
    printf '%s %s verdicts=%s FAILED\n' "$best_ms" "$name" "$verdicts" >>"$rows"
    {
      echo "=== FAILED: $name ==="
      cat "$work/fail-out" 2>/dev/null
      cat "$work/fail-err" 2>/dev/null
    } >>"$work/failures"
    # Cleared per file so a later file's block can never inherit this one's.
    rm -f "$work/fail-out" "$work/fail-err"
  else
    printf '%s %s verdicts=%s\n' "$best_ms" "$name" "$verdicts" >>"$rows"
  fi
  done_n=$((done_n + 1))
  printf 'measure-test-time: [%s/%s] %s best=%s.%03ss verdicts=%s%s\n' \
    "$done_n" "${#files[@]}" "$name" "$((best_ms / 1000))" \
    "$(printf '%03d' "$((best_ms % 1000))")" "$verdicts" \
    "$([ "$failed" -ne 0 ] && printf ' FAILED')" >&2
done

# Render: milliseconds become seconds at 3dp, ranked slowest-first, with the
# two totals the Task 7 budget derivation reads.
sort -t' ' -k1,1nr "$rows" | awk '
  { ms = $1; $1 = ""; sub(/^ /, ""); printf "%.3f %s\n", ms / 1000, $0 }
'
awk '
  { total_ms += $1
    for (i = 1; i <= NF; i++) if ($i ~ /^verdicts=/) { split($i, kv, "="); v += kv[2] } }
  END { printf "total-best-seconds %.3f\ntotal-verdicts %d\n", total_ms / 1000, v }
' "$rows"

if [ "$any_failed" -ne 0 ]; then
  echo ""
  cat "$work/failures" 2>/dev/null
  echo "measure-test-time: at least one test file FAILED; the baseline is not valid" >&2
  exit 1
fi
