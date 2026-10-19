# shellcheck shell=sh
# poll-until.sh — wait for an event by polling a condition until a generous
# deadline (sourced, never executed). A busy machine stretches how long an
# event takes to happen, not whether it happens, so a wait asserts only that
# the event arrived before a deadline far beyond its usual latency, and a
# timeout reports how long the wait really ran.
#
#   poll_until [--deadline <secs>] [--interval <secs>] [--what <label>] [--] <cmd...>
#
# Runs <cmd...> in the calling shell (a function works), its stdout always
# discarded and its stderr while polling, until it succeeds (return 0) or more
# than <secs> of wall clock have passed (return 1). The clock counts whole
# seconds, so a wait gives up between <secs> and <secs>+1 seconds in, never
# before. The condition always runs at least once, and once more after any
# sleep, so an event landing during the last interval still counts. On a
# timeout it runs once more with its stderr shown, and the message names
# <label>, the deadline, the elapsed time and that last attempt's exit status.
# The elapsed whole seconds are left in POLL_UNTIL_ELAPSED for a caller's own
# failure message. A malformed argument returns 2 before any wait.
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
  while [ "$#" -gt 0 ]; do
    case $1 in
      --deadline | --interval | --what)
        if [ "$#" -lt 2 ]; then
          printf '%s\n' "poll_until: $1 needs a value" >&2
          return 2
        fi
        case $1 in
          --deadline) _pu_deadline=$2 ;;
          --interval) _pu_interval=$2 ;;
          --what) _pu_what=$2 ;;
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
  while :; do
    if "$@" >/dev/null 2>&1; then
      POLL_UNTIL_ELAPSED=$((${SECONDS:-$(date +%s)} - _pu_start))
      return 0
    fi
    POLL_UNTIL_ELAPSED=$((${SECONDS:-$(date +%s)} - _pu_start))
    [ "$POLL_UNTIL_ELAPSED" -le "$_pu_deadline" ] || break
    sleep "$_pu_interval"
  done
  "$@" >/dev/null && return 0
  _pu_rc=$?
  printf '%s\n' "poll_until: $_pu_what did not hold within ${_pu_deadline}s, gave up after ${POLL_UNTIL_ELAPSED}s (last exit status $_pu_rc)" >&2
  return 1
}

pid_gone() {
  for _pg_pid in "$@"; do
    kill -0 "$_pg_pid" 2>/dev/null && return 1
  done
  return 0
}
