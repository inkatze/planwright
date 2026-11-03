#!/bin/sh
# detached-run.sh — run a long command (a full local suite) detached from the
# launching tool call, proving it started before anything relies on it.
#
# Usage:
#   detached-run.sh start [--dir <parent>] -- <command> [<arg>...]
#   detached-run.sh status <run-dir>
#
# start prints `run`, `pid` and `log` lines once the runner signals its start
# in a fresh dir under <parent> (default ${TMPDIR:-/tmp}); exit 4 if it never
# does. status prints running, finished <code>, never-started, or died; stop
# a run with `kill -- -<pid>`. Exit 2: usage error. run-inner is internal.
set -u
unset CDPATH

TAB=$(printf '\t')

self_path() {
  _sp_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
  SELF=$_sp_dir/$(basename "$0")
}

usage() {
  self_path
  LC_ALL=C sed -n 's/^#   \(detached-run\.sh .*\)$/usage: \1/p' "$SELF" >&2
  exit 2
}

is_count() {
  case $1 in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# runner_alive <canonical-run-dir> — the recorded runner is still this run's
# runner, not a process that reused its pid. Where ps cannot answer, a live
# pid is taken as the runner.
runner_alive() {
  _ra_pid=$(cat "$1/pid" 2>/dev/null) || return 1
  is_count "$_ra_pid" || return 1
  kill -0 "$_ra_pid" 2>/dev/null || return 1
  _ra_args=$(ps -ww -p "$_ra_pid" -o args= 2>/dev/null) || _ra_args=''
  case $_ra_args in
    '' | *" run-inner $1 -- "*) return 0 ;;
  esac
  return 1
}

# stop <pid> — the runner leads its own process group on the bash path; the
# fallback's runner shares the caller's group, so only the runner is signalled.
stop() {
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null
}

# failed <message> — report a start that did not start, naming the run and
# any reason the runner gave before it opened its log.
failed() {
  printf 'detached-run: %s; run %s\n' "$1" "$run" >&2
  [ ! -s "$run/runner.err" ] || sed 's/^/detached-run: runner: /' "$run/runner.err" >&2
  exit 4
}

do_start() {
  parent=${TMPDIR:-/tmp}
  if [ "${1:-}" = --dir ]; then
    [ "$#" -ge 2 ] && [ -n "$2" ] || usage
    parent=$2
    shift 2
  fi
  [ "${1:-}" = -- ] || usage
  shift
  [ "$#" -ge 1 ] || usage
  self_path

  run=$(mktemp -d "$parent/detached-run.XXXXXX") || {
    printf 'detached-run: cannot make a run directory under %s\n' "$parent" >&2
    exit 4
  }
  run=$(cd "$run" && pwd -P) || failed 'cannot resolve the run directory'
  date +%s >"$run/launched" || failed 'cannot write the launch marker'

  # Overridable so the tests can name a shell that cannot start.
  runner_sh=${PLANWRIGHT_DETACHED_RUN_SH:-/bin/sh}
  # The suite must start with a foreground run's signal dispositions: an
  # ignored signal is inherited and no shell can reset it. A shell without
  # job control starts a background job with SIGINT and SIGQUIT ignored;
  # bash's `set -m` avoids that without a terminal, and `nohup` and `setsid`
  # (absent on macOS) stay out for the same reason.
  if command -v bash >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # expanded by the inner bash
    pid=$(BASH_ENV='' ENV='' bash -c \
      'set -m; e=$1; shift; "$@" </dev/null >/dev/null 2>"$e" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- & echo $!' \
      detached-run "$run/runner.err" "$runner_sh" "$SELF" run-inner "$run" -- "$@")
  else
    printf 'detached-run: warning: no bash on PATH; the run starts with SIGINT and SIGQUIT ignored, in the caller'"'"'s process group\n' >&2
    "$runner_sh" "$SELF" run-inner "$run" -- "$@" </dev/null >/dev/null 2>"$run/runner.err" \
      3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
    pid=$!
  fi
  is_count "$pid" || failed 'could not read the runner pid'
  # From here a stopped start stops the run too, rather than leaving one no
  # caller knows about.
  trap 'stop "$pid"; failed "start interrupted; stopped the run"' HUP INT TERM
  printf '%s\n' "$pid" >"$run/pid" || {
    stop "$pid"
    failed 'cannot record the runner pid; stopped the run'
  }

  # A busy machine stretches how long a runner takes to start, not whether it
  # does. Overridable so the tests can reach the timeout.
  wait_s=${PLANWRIGHT_DETACHED_RUN_START_WAIT:-30}
  is_count "$wait_s" || usage
  waited=0
  while [ ! -e "$run/started" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      [ -e "$run/started" ] && break
      failed 'the runner never started (it exited before signalling)'
    fi
    if [ "$waited" -ge "$((wait_s * 10))" ]; then
      stop "$pid"
      failed "the runner never started (no signal in ${wait_s}s); stopped it"
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  trap - HUP INT TERM
  [ -f "$run/log" ] || failed 'the runner started but its log is missing'
  printf 'run%s%s\npid%s%s\nlog%s%s\n' "$TAB" "$run" "$TAB" "$pid" "$TAB" "$run/log"
}

do_run_inner() {
  run=$1
  shift 2
  [ -f "$run/launched" ] && [ ! -e "$run/started" ] || exit 2
  # Caught, not ignored, so a hangup cannot end the run yet the suite's
  # children start with SIGHUP at its default.
  trap ':' HUP
  exec >"$run/log" 2>&1 || exit 125
  : >"$run/started" || exit 125
  "$@" </dev/null
  rc=$?
  printf '%s\n' "$rc" >"$run/exit.tmp" && mv -f "$run/exit.tmp" "$run/exit"
}

# exit_code <run-dir> — the recorded exit status, or nothing.
exit_code() {
  _ec=$(head -n 1 "$1/exit" 2>/dev/null) || _ec=''
  is_count "$_ec" && printf '%s' "$_ec"
}

do_status() {
  [ "$#" -eq 1 ] || usage
  run=$(cd "$1" 2>/dev/null && pwd -P) && [ -f "$run/launched" ] || {
    printf 'detached-run: not a run directory: %s\n' "$1" >&2
    exit 2
  }
  if rc=$(exit_code "$run"); then
    printf 'finished %s\n' "$rc"
  elif runner_alive "$run"; then
    echo running
  elif rc=$(exit_code "$run"); then
    # The run finished between the two reads.
    printf 'finished %s\n' "$rc"
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
