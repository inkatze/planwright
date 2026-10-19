# shellcheck shell=sh
# poll-until.sh — wait for an event by polling a condition until a generous
# deadline (sourced, never executed). A busy machine stretches how long an
# event takes to happen, not whether it happens, so a wait asserts only that
# the event arrived before a deadline far beyond its usual latency, and a
# timeout reports how long the wait really ran.
#
#   poll_until [--deadline <secs>] [--interval <secs>] [--what <label>] [--] <cmd...>
#
# Runs <cmd...> in the calling shell (a function works), its output
# discarded, until it succeeds (return 0) or <secs> of wall clock have passed
# (return 1, naming <label>, the deadline and the elapsed time on stderr). The
# condition always runs at least once, and once more after any sleep, so an
# event landing during the last interval still counts. The elapsed whole
# seconds of the last wait are left in POLL_UNTIL_ELAPSED for a caller's own
# failure message. A malformed argument returns 2 before any wait.
#
# The default deadline is 60s (POLL_UNTIL_DEFAULT_DEADLINE), the interval
# 0.1s. A wait shorter than the default needs a reason at its call site; an
# assertion that something did NOT happen within a window is not a wait for
# an event and does not belong here.

POLL_UNTIL_DEFAULT_DEADLINE=60
POLL_UNTIL_ELAPSED=0

poll_until() {
  _pu_deadline=$POLL_UNTIL_DEFAULT_DEADLINE
  _pu_interval=0.1
  _pu_what=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --deadline | --interval | --what)
        if [ "$#" -lt 2 ]; then
          echo "poll_until: $1 needs a value" >&2
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
        echo "poll_until: unknown option '$1'" >&2
        return 2
        ;;
      *) break ;;
    esac
  done
  case $_pu_deadline in '' | *[!0-9]*)
    echo "poll_until: the deadline must be whole seconds, got '$_pu_deadline'" >&2
    return 2
    ;;
  esac
  case $_pu_interval in '' | *[!0-9.]* | *.*.* | .* | *.)
    echo "poll_until: the interval must be a number of seconds, got '$_pu_interval'" >&2
    return 2
    ;;
  esac
  if [ "$#" -eq 0 ]; then
    echo "poll_until: no condition to poll" >&2
    return 2
  fi
  [ -n "$_pu_what" ] || _pu_what="'$*'"
  _pu_start=$(date +%s)
  while :; do
    if "$@" >/dev/null 2>&1; then
      POLL_UNTIL_ELAPSED=$(($(date +%s) - _pu_start))
      return 0
    fi
    POLL_UNTIL_ELAPSED=$(($(date +%s) - _pu_start))
    [ "$POLL_UNTIL_ELAPSED" -lt "$_pu_deadline" ] || break
    sleep "$_pu_interval"
  done
  echo "poll_until: $_pu_what did not hold within ${_pu_deadline}s, gave up after ${POLL_UNTIL_ELAPSED}s" >&2
  return 1
}
