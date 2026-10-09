#!/bin/bash
# Bounded-parallel shell-test runner behind `mise run test`. Runs every
# <suite-dir>/*.sh under /bin/bash (the bash 3.2 floor), up to N files at a
# time (N = hw.ncpu / nproc), further bounded by the machine-wide ticket pool
# below, capturing each file's stdout+stderr to a per-file
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
# Machine-wide ticket pool: every run on the host shares one per-user pool of
# tickets, and a worker holds one for as long as its test file runs, so the
# fleet's concurrent suites together execute at most the pool's capacity of
# files at once instead of each saturating every core. A ticket is a numbered
# scripts/lock-lib.sh lock under the pool directory, held by the worker
# process; a ticket whose holder is gone (a killed run) is broken and retaken
# by the next worker that needs one. Runs that set different capacities take
# tickets numbered up to their own value, so the machine-wide bound is the
# LARGEST capacity in use, not the smallest. PLANWRIGHT_TEST_JOBS still caps
# one run's own parallelism beneath the pool. A pool that cannot be used (no
# home to resolve, a symbolic link, another user's directory, unwritable, a
# lock-library error) costs one warning naming the cause and an unpooled run,
# never a blocked or failed one. A runner started from inside a pooled test
# file finds the internal mark and runs unpooled without a warning: its
# parent's ticket already counts the file's work, and waiting on the pool
# there could wait on a ticket its own ancestor holds.
#
# Timing capture: every worker records its own file's wall-clock at
# sub-second resolution in its own record (no shared-file append race under
# the parallel pool), and the parent aggregates the records into one report
# after the pool drains, written atomically to a stable path beside the suite
# (<suite-dir>/.timing-report.tsv, gitignored; override with
# PLANWRIGHT_TEST_TIMING_REPORT). A file's time starts once it holds its
# ticket; the time it waited for one is its own column, so a busy machine
# never makes a file look slow. The suite wall-clock row does include
# waiting. scripts/check-test-time.sh reads that report against the committed
# budgets instead of re-running the suite. The accounting is positive here
# too: a file with a verdict but no timing record fails the run, so the
# report never carries a silent hole.
#
# Usage: run-tests.sh [suite-dir]   (default: <repo-root>/tests)
# Exit:  0 all pass · 1 any test failed or lost · 2 usage or environment
#        error (bad suite dir, mktemp or self-path resolution failure, a
#        timing report that cannot be persisted).
#
# Environment:
#   PLANWRIGHT_TEST_JOBS           override the job count (default: core count)
#   PLANWRIGHT_TEST_SLOTS          the pool's capacity (default: core count);
#                                  set it in mise.local.toml, not per run
#   PLANWRIGHT_TEST_SLOT_DIR       the pool directory, for the runner's own
#                                  tests (default: ${XDG_STATE_HOME:-$HOME/
#                                  .local/state}/planwright/test-slots)
#   PLANWRIGHT_TEST_FORCE_SERIAL   1 forces the serial fallback path
#   PLANWRIGHT_TEST_TIMING_REPORT  where to persist the timing report
#                                  (default: <suite-dir>/.timing-report.tsv)
#   PLANWRIGHT_TEST_DURATIONS      the duration table the queue is ordered
#                                  by (default: <repo-root>/config/
#                                  test-durations.tsv; empty disables it)
#   PLANWRIGHT_FLEET_STATE_DIR     replaced per file by a sentinel fleet home
#   CLAUDE_PLUGIN_DATA, CLAUDE_DIR (the latter two only when set); a file that
#                                  creates anything in that home fails
#   SPEC_WALKTHROUGH_DOT_TIMEOUT   exported to every test (default 60 here:
#                                  suite load headroom; caller value wins)
#   PLANWRIGHT_TEST_IN_POOLED_FILE internal: the mark a pooled worker gives
#                                  its test file; a runner that sees it runs
#                                  unpooled
#   PLANWRIGHT_TEST_POOL_DIR       internal: parent-to-worker pool handoff
#   PLANWRIGHT_TEST_POOL_SLOTS     (both empty for an unpooled run)
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

# ms_to_seconds <ms> — "12.345", the report's unit. A negative interval (the
# wall clock stepped back mid-measurement) reads as zero: printf would render
# it as "0.-500", which the budget gate rightly refuses as non-numeric.
ms_to_seconds() {
  _ms=$1
  [ "$_ms" -ge 0 ] || _ms=0
  printf '%d.%03d' "$((_ms / 1000))" "$((_ms % 1000))"
}

# _slot_attempt <path> — one pw_lock_try on one ticket. 0 held (slot_path
# set), 1 busy, 2 give up (slot_err set): anything but a held or busy answer,
# 127 from a library that failed to load included, is not going to clear.
_slot_attempt() {
  pw_lock_try "$1" 2>"$_ts_err"
  slot_rc=$?
  case "$slot_rc" in
    0)
      slot_path=$1
      return 0
      ;;
    1) return 1 ;;
  esac
  slot_err="$(cat "$_ts_err" 2>/dev/null)"
  [ -n "$slot_err" ] || slot_err="lock-lib returned $slot_rc for $1"
  slot_rc=2
  return 2
}

# take_slot <pool-dir> <capacity> <stderr-file> — hold one ticket, waiting with
# a bounded backoff for as long as that takes. Sets slot_rc to 0 and slot_path
# to the ticket, or slot_rc to 2 with slot_err naming the lock library's real
# error. Runs in the worker's own shell, never a subshell: the hold belongs to
# the process that takes it.
take_slot() {
  _ts_dir=$1
  _ts_cap=$2
  _ts_err=$3
  _ts_round=0
  _ts_next=$(($$ % _ts_cap + 1))
  slot_path=""
  slot_err=""
  while :; do
    # The log directory is the parent's: gone means the run is over, and a
    # waiter left behind would otherwise spin on a redirect that now fails.
    [ -d "$PLANWRIGHT_TEST_LOG_DIR" ] || exit 0
    # Free tickets first, looked at without a fork. A taken one is only worth
    # a liveness probe when none is free, and the probe forks several times,
    # so one holder is examined per stride, rotating through the pool; a dead
    # holder's ticket is still reclaimed within a few strides.
    # Each worker starts its scan at its own offset: workers that all began at
    # ticket 1 collided there, and a lost race costs a liveness probe.
    _ts_k=0
    while [ "$_ts_k" -lt "$_ts_cap" ]; do
      _ts_i=$((($$ + _ts_k) % _ts_cap + 1))
      if [ ! -L "$_ts_dir/slot-$_ts_i" ]; then
        _slot_attempt "$_ts_dir/slot-$_ts_i"
        [ "$?" -eq 1 ] || return 0
      fi
      _ts_k=$((_ts_k + 1))
    done
    if [ $((_ts_round % 5)) -eq 0 ]; then
      _slot_attempt "$_ts_dir/slot-$_ts_next"
      [ "$?" -eq 1 ] || return 0
      _ts_next=$((_ts_next % _ts_cap + 1))
    fi
    # Capped low because a ticket sits idle for as long as its next waiter
    # sleeps; a waking round costs only the sleep itself.
    case "$_ts_round" in
      0) _ts_nap=0.05 ;;
      1) _ts_nap=0.1 ;;
      *) _ts_nap=0.2 ;;
    esac
    sleep "$_ts_nap" 2>/dev/null || sleep 1
    _ts_round=$((_ts_round + 1))
  done
}

# worker_signal <SIG> — release every ticket, then die by <SIG> itself.
worker_signal() {
  pw_lock_release_all
  trap - "$1"
  kill -s "$1" "$$"
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
  wait_started="$(now_ms)"
  slot_path=""
  if [ -n "${PLANWRIGHT_TEST_POOL_DIR:-}" ]; then
    # shellcheck source=scripts/lock-lib.sh
    if . "${0%/*}/lock-lib.sh"; then
      # The traps release the ticket if this worker is interrupted mid-file; a
      # SIGKILL leaves it to the next run's dead-holder reclaim. They re-raise
      # rather than exit (pw_lock_trap_install's form): a serial parent that
      # sees a plain exit assumes the file handled the interrupt and runs on.
      trap 'pw_lock_release_all' EXIT
      trap 'worker_signal INT' INT
      trap 'worker_signal TERM' TERM
      trap 'worker_signal HUP' HUP
      take_slot "$PLANWRIGHT_TEST_POOL_DIR" "$PLANWRIGHT_TEST_POOL_SLOTS" \
        "$PLANWRIGHT_TEST_LOG_DIR/$name.lockerr"
    else
      slot_rc=2
      slot_err="could not load ${0%/*}/lock-lib.sh"
    fi
    if [ "$slot_rc" -ne 0 ]; then
      # The parent reports these once, after the pool drains.
      printf '%s\n' "$slot_err" >"$PLANWRIGHT_TEST_LOG_DIR/$name.poolerr"
    fi
  fi
  [ -z "$slot_path" ] || export PLANWRIGHT_TEST_IN_POOLED_FILE=1
  # A run started from a fleet worker inherits the operator's real fleet home,
  # so each file gets a home of its own that nothing should ever touch: a file
  # that has created anything there by the time it exits wrote fleet state (a
  # registry record, a dispatch marker, a ledger row) without pinning a fixture
  # home, and fails for it. A detached child writing later still lands in the
  # sentinel, inside this run's log dir, just undetected. The plugin-data and
  # writer arms are redirected only when set, so a file sees the same set/unset
  # shape it would have seen without the runner. Each redirected arm is checked
  # whole rather than at the leaf the resolver derives under it, so the check
  # never depends on that layout: anything written there would have landed in
  # the caller's own directory.
  fleet_sentinel="$PLANWRIGHT_TEST_LOG_DIR/$name.fleet"
  export PLANWRIGHT_FLEET_STATE_DIR="$fleet_sentinel/fleet"
  [ -z "${CLAUDE_PLUGIN_DATA+set}" ] || export CLAUDE_PLUGIN_DATA="$fleet_sentinel/plugin-data"
  [ -z "${CLAUDE_DIR+set}" ] || export CLAUDE_DIR="$fleet_sentinel/claude"
  started="$(now_ms)"
  if /bin/bash "$t" >"$PLANWRIGHT_TEST_LOG_DIR/$name.log" 2>&1; then
    verdict="done"
  else
    verdict="fail"
  fi
  for fh in "$fleet_sentinel/fleet" "$fleet_sentinel/plugin-data" "$fleet_sentinel/claude"; do
    if [ -e "$fh" ] || [ -L "$fh" ]; then
      verdict="fail"
      printf '%s\n' "run-tests: $name wrote into the fleet home it inherited (under a fleet worker, the operator's real one); pin a fixture home per case (tests/lib/fleet-home.sh)" \
        >>"$PLANWRIGHT_TEST_LOG_DIR/$name.log"
      break
    fi
  done
  finished="$(now_ms)"
  [ -z "$slot_path" ] || pw_lock_release "$slot_path" 2>/dev/null || :
  # The timing record is this worker's own file, written before the verdict
  # marker so a marker never exists without its record having been attempted.
  elapsed=""
  if [ -n "$wait_started" ] && [ -n "$started" ] && [ -n "$finished" ]; then
    elapsed="$(ms_to_seconds $((finished - started)))"
    printf '%s\t%s\n' "$elapsed" "$(ms_to_seconds $((started - wait_started)))" \
      >"$PLANWRIGHT_TEST_LOG_DIR/$name.time"
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

self_dir="${self%/*}"
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
cores="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || true)"
jobs="${PLANWRIGHT_TEST_JOBS:-$cores}"
case "$jobs" in
  '' | *[!0-9]*) jobs=4 ;;
esac
[ "$jobs" -ge 1 ] || jobs=1

pool_warn() {
  echo "run-tests: WARNING test pool $1; running unpooled" >&2
}
# Display sanitizer for the caller-supplied paths and values a pool warning
# quotes. The inline fallback keeps the warning safe when the shared helper
# cannot be sourced.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
fi

# Pool capacity: the same fallback and clamp as the job count, but a value
# that needed either is a misconfiguration worth one warning. Five digits is
# already far past any core count, and every waiting worker scans each slot.
slots="${PLANWRIGHT_TEST_SLOTS-$cores}"
case "$slots" in
  '' | *[!0-9]* | ??????*)
    [ -z "${PLANWRIGHT_TEST_SLOTS+set}" ] \
      || echo "run-tests: WARNING test pool: PLANWRIGHT_TEST_SLOTS is not a usable count ($(sanitize_printable "$slots" "(unprintable)")); using 4" >&2
    slots=4
    ;;
  *)
    slots=$((10#$slots))
    if [ "$slots" -lt 1 ]; then
      echo "run-tests: WARNING test pool: PLANWRIGHT_TEST_SLOTS is 0; using 1" >&2
      slots=1
    fi
    ;;
esac

# Resolve the pool, or say once why not. Only the directory's own path is
# checked for a link: a home directory reached through one is ordinary.
pool_dir=""
if [ "${PLANWRIGHT_TEST_IN_POOLED_FILE:-}" != 1 ]; then
  if [ -n "${PLANWRIGHT_TEST_SLOT_DIR:-}" ]; then
    cand="$PLANWRIGHT_TEST_SLOT_DIR"
  elif [ -n "${XDG_STATE_HOME:-}" ]; then
    cand="$XDG_STATE_HOME/planwright/test-slots"
  elif [ -n "${HOME:-}" ]; then
    cand="$HOME/.local/state/planwright/test-slots"
  else
    cand=""
  fi
  # A trailing slash would make the link test below follow a link at the
  # path instead of refusing it.
  while :; do
    case "$cand" in
      ?*/) cand="${cand%/}" ;;
      *) break ;;
    esac
  done
  shown="$(sanitize_printable "$cand" "(unprintable path)")"
  nl='
'
  if [ -z "$cand" ]; then
    pool_warn "has no location: neither HOME nor XDG_STATE_HOME is set"
  else
    case "$cand" in
      /*) ;;
      *)
        pool_warn "directory must be an absolute path: $shown"
        cand=""
        ;;
    esac
  fi
  case "$cand" in
    */. | */..)
      # The link test asks about the last component, and "." or ".." there
      # resolves through whatever link precedes it.
      pool_warn "directory path must not end in '.' or '..': $shown"
      cand=""
      ;;
    *'#'* | *"$nl"*)
      pool_warn "directory path contains '#' or a newline, which lock paths refuse: $shown"
      cand=""
      ;;
  esac
  if [ -n "$cand" ]; then
    if [ ! -L "$cand" ] && [ ! -e "$cand" ]; then
      # Owner-only from the first instant, parents included.
      (umask 077 && mkdir -p "$cand") 2>/dev/null
    fi
    # The numeric owner, the one field ls prints the same on BSD and GNU;
    # stat's flags differ between them. A single known path, so SC2012's
    # filename concern does not apply.
    # shellcheck disable=SC2012
    owner="$(ls -ldn "$cand" 2>/dev/null | awk '{ print $3 }')"
    me="$(id -u 2>/dev/null)"
    if [ -L "$cand" ]; then
      pool_warn "directory is a symbolic link, refused: $shown"
    elif [ ! -d "$cand" ]; then
      pool_warn "directory could not be created: $shown"
    elif [ -z "$owner" ] || [ -z "$me" ] || [ "$owner" != "$me" ]; then
      pool_warn "directory is not owned by the running user, refused: $shown"
    elif [ ! -w "$cand" ] || [ ! -x "$cand" ]; then
      pool_warn "directory is not writable: $shown"
    elif [ ! -r "$self_dir/lock-lib.sh" ]; then
      pool_warn "lock library is missing: $(sanitize_printable "$self_dir/lock-lib.sh" "(unprintable path)")"
    else
      pool_dir="$cand"
    fi
  fi
fi
if [ -n "$pool_dir" ]; then
  export PLANWRIGHT_TEST_POOL_DIR="$pool_dir" PLANWRIGHT_TEST_POOL_SLOTS="$slots"
  pool_field="$slots"
  pool_desc="pool $slots slots"
else
  export PLANWRIGHT_TEST_POOL_DIR="" PLANWRIGHT_TEST_POOL_SLOTS=""
  pool_field=off
  pool_desc="unpooled"
fi

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

# Queue order: longest expected file first (longest-processing-time
# scheduling). In name order a slow file dispatched near the end ran alone
# while the other jobs sat idle, and that tail decided the suite's wall-clock.
# Expected times come from the committed duration table, kept by
# scripts/refresh-test-durations.sh; a file with no usable row is ranked ahead
# of every timed one, since an unmeasured file placed last could be the tail.
# The table only ever reorders: rows for files the suite lacks are ignored,
# every discovered file is queued exactly once, ties keep name order, and a
# missing or unreadable table is name order, never a failure. `files` keeps
# name order for the summary and report below.
tab="$(printf '\t')"
durations="${PLANWRIGHT_TEST_DURATIONS-$repo_root/config/test-durations.tsv}"
queue=("${files[@]}")
if [ -n "$durations" ] && [ -f "$durations" ] && [ -r "$durations" ]; then
  ranked="$(
    i=0
    for t in "${files[@]}"; do
      printf '%s\t%s\n' "$i" "${t##*/}"
      i=$((i + 1))
    done | RT_DURATIONS="$durations" awk -F'\t' '
      BEGIN {
        # Through ENVIRON, never -v, which would expand backslash escapes in
        # the path.
        table = ENVIRON["RT_DURATIONS"]
        while ((getline line < table) > 0) {
          if (line ~ /^#/) continue
          if (split(line, f, "\t") != 2) continue
          if (f[2] !~ /^[0-9]+(\.[0-9]+)?$/ || (f[1] in dur)) continue
          dur[f[1]] = f[2]
        }
        close(table)
      }
      NF == 2 && $1 ~ /^[0-9]+$/ {
        if ($2 in dur) print 1 "\t" dur[$2] "\t" $1
        else print 0 "\t0\t" $1
      }
    ' | LC_ALL=C sort -t "$tab" -k1,1n -k2,2nr -k3,3n
  )"
  queue=()
  queued=()
  timed=0
  while IFS="$tab" read -r cls _ idx; do
    case "$idx" in
      '' | *[!0-9]*) continue ;;
    esac
    [ "$idx" -lt "${#files[@]}" ] || continue
    [ -z "${queued[$idx]:-}" ] || continue
    queued[idx]=1
    queue+=("${files[$idx]}")
    [ "$cls" != 1 ] || timed=$((timed + 1))
  done <<EOF
$ranked
EOF
  # A name the awk pass could not key (a tab or newline in it) still runs.
  i=0
  while [ "$i" -lt "${#files[@]}" ]; do
    [ -n "${queued[$i]:-}" ] || queue+=("${files[$i]}")
    i=$((i + 1))
  done
  order_desc="slowest-first ($timed of ${#files[@]} files timed by $(sanitize_printable "$durations" "(unprintable path)"); untimed files first)"
elif [ -n "$durations" ]; then
  order_desc="name order (no readable duration table at $(sanitize_printable "$durations" "(unprintable path)"))"
else
  order_desc="name order (duration table disabled)"
fi

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
  echo "run-tests: ${#files[@]} files, $jobs jobs, $pool_desc"
  echo "run-tests: queue $order_desc"
  printf '%s\0' "${queue[@]}" \
    | xargs -0 -n 1 -P "$jobs" /bin/bash "$self" --run-one \
    || dispatch_failed=1
else
  mode=serial
  echo "run-tests: ${#files[@]} files, serial (no parallel primitive), $pool_desc"
  echo "run-tests: queue $order_desc"
  for t in "${queue[@]}"; do
    /bin/bash "$self" --run-one "$t" || dispatch_failed=1
  done
fi
suite_finished="$(now_ms)"

# A worker whose ticket the lock library refused ran its file unpooled and
# left the cause behind; one warning covers them all.
unpooled=0
pool_cause=""
for t in "${files[@]}"; do
  name="${t##*/}"
  if [ -s "$log_dir/$name.poolerr" ]; then
    unpooled=$((unpooled + 1))
    [ -n "$pool_cause" ] || IFS= read -r pool_cause <"$log_dir/$name.poolerr"
  fi
done
if [ "$unpooled" -gt 0 ]; then
  echo "run-tests: WARNING test pool refused a ticket ($(sanitize_printable "$pool_cause" "(unprintable)")); $unpooled file(s) ran unpooled" >&2
fi

# Summary with positive accounting: every input file must have produced a
# verdict marker. A .fail names a real test failure (log replayed); a file
# with neither marker never completed — its worker died or was never
# dispatched — and marker absence must count as failure, never success.
# The timing report is aggregated from the per-worker records only now,
# after the pool has drained, so no two writers ever touch it. A file with a
# verdict marker but no record is a hole the budget gate would fail closed
# on; naming it here is the honest half of that contract.
# Staged beside its destination under an explicit mktemp template (a
# predictable name would be a symlink target for anyone sharing the
# directory), then moved into place in one step.
report_tmp="$(mktemp "$report.XXXXXX" 2>/dev/null)" || report_tmp=""
if [ -n "$report_tmp" ]; then
  printf 'planwright-test-timing\t2\tclock=%s\tmode=%s\tjobs=%s\tpool=%s\n' "$clock" "$mode" "$jobs" "$pool_field" >"$report_tmp" \
    || report_tmp=""
fi

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
      IFS="$(printf '\t')" read -r elapsed waited <"$log_dir/$name.time"
      printf 'file\t%s\t%s\t%s\n' "$name" "$elapsed" "$waited" >>"$report_tmp"
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
