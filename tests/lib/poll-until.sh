# shellcheck shell=sh
# poll-until.sh — wait for an event by polling a condition until a generous
# deadline (sourced, never executed). A busy machine stretches how long an
# event takes to happen, not whether it happens, so a wait asserts only that
# the event arrived before a deadline far beyond its usual latency, and a
# timeout reports how long the wait really ran.
#
#   poll_until [--deadline <secs>] [--interval <secs>] [--what <label>]
#              [--while-alive <pid>] [--] <cmd...>
#
# Runs <cmd...> in the calling shell (a function works), its stdout always
# discarded and its stderr while polling, until it succeeds (return 0) or more
# than <secs> of wall clock have passed (return 1). The clock counts whole
# seconds, so a wait gives up between <secs> and <secs>+1 seconds in, never
# before. The condition always runs at least once, and once more after any
# sleep, so an event landing during the last interval still counts. On a
# timeout it runs once more, for the message only, with its stderr shown; the
# message names <label>, the deadline, the elapsed time and that attempt's exit
# status.
# The elapsed whole seconds are left in POLL_UNTIL_ELAPSED for a caller's own
# failure message. A malformed argument returns 2 before any wait.
#
# --while-alive <pid> names the process that brings the event about. The wait
# also gives up (return 1) once that process has exited with the condition
# still false, checked once more after the exit, and the message says the
# process exited first. The deadline is then only a ceiling for a live process
# that never gets there, so it can be generous at no cost to a failing run. A
# child of the calling shell may linger as a zombie until it is waited for, so
# the option suits a process the caller did not start, such as a detached
# supervisor.
#
# The default deadline is 60s, kept in POLL_UNTIL_DEFAULT_DEADLINE (a value
# already in the environment wins, for a host slower than that); the interval
# is 0.1s. A wait shorter than the default needs a reason at its call site; an
# assertion that something did NOT happen within a window is not a wait for
# an event and does not belong here.
#
#   pid_gone <pid...>   succeeds once none of the processes is running, the
#                       usual condition for a wait on an exit

POLL_UNTIL_DEFAULT_DEADLINE=${POLL_UNTIL_DEFAULT_DEADLINE:-60}
POLL_UNTIL_ELAPSED=0

# shellcheck disable=SC3028 # bash's SECONDS reads the clock without a fork; dash falls back to date
poll_until() {
  _pu_deadline=$POLL_UNTIL_DEFAULT_DEADLINE
  _pu_interval=0.1
  _pu_what=''
  _pu_alive=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --deadline | --interval | --what | --while-alive)
        if [ "$#" -lt 2 ]; then
          printf '%s\n' "poll_until: $1 needs a value" >&2
          return 2
        fi
        case $1 in
          --deadline) _pu_deadline=$2 ;;
          --interval) _pu_interval=$2 ;;
          --what) _pu_what=$2 ;;
          --while-alive)
            case $2 in '' | *[!0-9]* | 0*)
              printf '%s\n' "poll_until: --while-alive needs a process id, got '$2'" >&2
              return 2
              ;;
            esac
            _pu_alive=$2
            ;;
        esac
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf '%s\n' "poll_until: unknown option '$1'" >&2
        return 2
        ;;
      *) break ;;
    esac
  done
  case $_pu_deadline in '' | *[!0-9]*)
    printf '%s\n' "poll_until: the deadline must be whole seconds, got '$_pu_deadline'" >&2
    return 2
    ;;
  esac
  case $_pu_interval in '' | *[!0-9.]* | *.*.* | .* | *. | *[!0.]*) ;; *)
    printf '%s\n' "poll_until: the interval must be more than zero seconds, got '$_pu_interval'" >&2
    return 2
    ;;
  esac
  case $_pu_interval in '' | *[!0-9.]* | *.*.* | .* | *.)
    printf '%s\n' "poll_until: the interval must be a number of seconds, got '$_pu_interval'" >&2
    return 2
    ;;
  esac
  if [ "$#" -eq 0 ]; then
    printf '%s\n' "poll_until: no condition to poll" >&2
    return 2
  fi
  [ -n "$_pu_what" ] || _pu_what="'$*'"
  _pu_start=${SECONDS:-$(date +%s)}
  _pu_gone=0
  while :; do
    if "$@" >/dev/null 2>&1; then
      POLL_UNTIL_ELAPSED=$((${SECONDS:-$(date +%s)} - _pu_start))
      return 0
    fi
    POLL_UNTIL_ELAPSED=$((${SECONDS:-$(date +%s)} - _pu_start))
    [ "$_pu_gone" = 0 ] || break
    [ "$POLL_UNTIL_ELAPSED" -le "$_pu_deadline" ] || break
    # The exit is seen after a failed check, so the next pass checks once more
    # for an event the process recorded just before it exited.
    if [ -n "$_pu_alive" ] && ! kill -0 "$_pu_alive" 2>/dev/null; then
      _pu_gone=1
      continue
    fi
    sleep "$_pu_interval"
  done
  _pu_rc=0
  "$@" >/dev/null || _pu_rc=$?
  POLL_UNTIL_ELAPSED=$((${SECONDS:-$(date +%s)} - _pu_start))
  if [ "$_pu_gone" = 1 ]; then
    printf '%s\n' "poll_until: $_pu_what did not hold: process $_pu_alive exited first, ${POLL_UNTIL_ELAPSED}s in (deadline ${_pu_deadline}s, last exit status $_pu_rc)" >&2
  else
    printf '%s\n' "poll_until: $_pu_what did not hold within ${_pu_deadline}s, gave up after ${POLL_UNTIL_ELAPSED}s (last exit status $_pu_rc)" >&2
  fi
  return 1
}

pid_gone() {
  for _pg_pid in "$@"; do
    kill -0 "$_pg_pid" 2>/dev/null && return 1
  done
  return 0
}
