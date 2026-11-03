#!/bin/sh
# detached-run.sh — run a long command (a full local suite) detached from the
# launching tool call, proving it started before anything relies on it.
#
# Usage:
#   detached-run.sh start [--dir <parent>] -- <command> [<arg>...]
#   detached-run.sh status <run-dir>
#
# start runs the command in a fresh directory under <parent> (default
# ${TMPDIR:-/tmp}), output to its `log`, printing `run`, `pid` and `log` lines
# once the runner signals its start (exit 4 if it never does). status prints
# running, finished <code>, never-started, or died. Exit 2: usage error.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0") || exit 2
TAB=$(printf '\t')
# A busy machine stretches how long a runner takes to start, not whether it
# does.
START_WAIT_TENTHS=300

usage() {
  sed -n 's/^#   \(detached-run\.sh .*\)$/usage: \1/p' "$SELF" >&2
  exit 2
}

# runner_alive <run-dir> — the recorded runner is still this run's runner,
# not a process that reused its pid.
runner_alive() {
  [ -s "$1/pid" ] || return 1
  _ra_pid=$(cat "$1/pid")
  kill -0 "$_ra_pid" 2>/dev/null || return 1
  case $(ps -p "$_ra_pid" -o args= 2>/dev/null) in
    *"$1"*) return 0 ;;
  esac
  return 1
}

do_start() {
  parent=${TMPDIR:-/tmp}
  if [ "${1:-}" = --dir ]; then
    [ "$#" -ge 2 ] || usage
    parent=$2
    shift 2
  fi
  [ "${1:-}" = -- ] || usage
  shift
  [ "$#" -ge 1 ] || usage

  run=$(mktemp -d "$parent/detached-run.XXXXXX") || {
    printf 'detached-run: cannot make a run directory under %s\n' "$parent" >&2
    exit 2
  }
  run=$(cd "$run" && pwd -P) || exit 2
  date +%s >"$run/launched" || exit 2

  # Overridable so the tests can name a shell that cannot start.
  runner_sh=${PLANWRIGHT_DETACHED_RUN_SH:-/bin/sh}
  # The suite must start with a foreground run's signal dispositions: an
  # ignored signal is inherited and no shell can reset it. A shell without
  # job control starts a background job with SIGINT and SIGQUIT ignored;
  # bash's `set -m` avoids that without a terminal, and `nohup` and `setsid`
  # (absent on macOS) stay out for the same reason.
  if command -v bash >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # expanded by the inner bash
    pid=$(bash -c 'set -m; "$@" </dev/null >/dev/null 2>&1 & echo $!' \
      detached-run "$runner_sh" "$SELF" run-inner "$run" -- "$@")
  else
    printf 'detached-run: warning: no bash on PATH; the run starts with SIGINT and SIGQUIT ignored\n' >&2
    "$runner_sh" "$SELF" run-inner "$run" -- "$@" </dev/null >/dev/null 2>&1 &
    pid=$!
  fi
  printf '%s\n' "$pid" >"$run/pid" || {
    kill "$pid" 2>/dev/null
    printf 'detached-run: cannot record the runner pid in %s\n' "$run" >&2
    exit 4
  }

  waited=0
  while [ ! -e "$run/started" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      [ -e "$run/started" ] && break
      printf 'detached-run: the runner never started (it exited before signalling); run %s\n' "$run" >&2
      exit 4
    fi
    if [ "$waited" -ge "$START_WAIT_TENTHS" ]; then
      kill "$pid" 2>/dev/null
      printf 'detached-run: the runner never started (no signal in %ss); stopped it; run %s\n' \
        "$((START_WAIT_TENTHS / 10))" "$run" >&2
      exit 4
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  [ -f "$run/log" ] || {
    printf 'detached-run: the runner started but its log is missing; run %s\n' "$run" >&2
    exit 4
  }
  printf 'run%s%s\npid%s%s\nlog%s%s\n' "$TAB" "$run" "$TAB" "$pid" "$TAB" "$run/log"
}

do_run_inner() {
  run=$1
  shift 2
  # Caught, not ignored, so a hangup cannot end the run yet the suite's
  # children start with SIGHUP at its default.
  trap ':' HUP
  exec >"$run/log" 2>&1 || exit 125
  : >"$run/started" || exit 125
  "$@" </dev/null
  rc=$?
  printf '%s\n' "$rc" >"$run/exit.tmp" && mv -f "$run/exit.tmp" "$run/exit"
}

do_status() {
  [ "$#" -eq 1 ] || usage
  run=$1
  [ -d "$run" ] && [ -f "$run/launched" ] || {
    printf 'detached-run: not a run directory: %s\n' "$run" >&2
    exit 2
  }
  if [ -s "$run/exit" ]; then
    printf 'finished %s\n' "$(cat "$run/exit")"
  elif runner_alive "$run"; then
    echo running
  elif [ -e "$run/started" ]; then
    echo died
  else
    echo never-started
  fi
}

case ${1:-} in
  start)
    shift
    do_start "$@"
    ;;
  status)
    shift
    do_status "$@"
    ;;
  run-inner)
    shift
    [ "$#" -ge 3 ] && [ "$2" = -- ] || exit 2
    do_run_inner "$@"
    ;;
  *) usage ;;
esac
