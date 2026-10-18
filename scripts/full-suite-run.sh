#!/bin/sh
# full-suite-run.sh — run one full local suite attempt for /execute-task,
# holding a slot of the pool `full_suite_pool` names (doctrine/custom-steps.md,
# *Expensive checks*, The full suite). scripts/step-pool.sh owns the slot
# mechanics; this script is the full-suite owner the doctrine names, so the
# suite command reaches it as argv and runs with no shell or eval in between.
#
# Usage:
#   full-suite-run.sh [--run <id>] -- <command> [<arg>...]
#
# --run names the unit run (a step-record.sh run id): each pooled attempt then
# writes its full-suite record through `step-record.sh write --full-suite`,
# the wait outcome, the seconds waited, and the holders the wait reported
# (doctrine/custom-steps.md, *Expensive checks*, The full suite; an expired
# wait included). An unpooled attempt writes none.
#
# full_suite_pool resolves through scripts/config-get.sh. Empty or set in no
# layer, the command runs unpooled with no output of this script's own. A
# value outside the pool charset, a config read failure, or a pool helper
# failure warns once on stderr and runs the command unpooled: an unusable pool
# never blocks a suite, as step-pool.sh's own unpooled fallback does.
#
# A pooled attempt takes a slot on behalf of this script's own process, waiting
# up to step_pool_wait, and runs the command with PLANWRIGHT_STEP_POOL_HOLD set
# on its command line only. A take that prints `nested` or `unpooled` runs the
# command with the inherited mark, if any, and releases nothing. One attempt is
# one slot, each with its own wait bound: a retry calls this script again.
#
# The command runs in the foreground, its stdin /dev/null. HUP, INT, or TERM
# reaching this script is held until the command has finished (the shell runs
# a trap only then), after which the slot is released and the script exits
# 128+n, so none of them frees the slot while the suite or anything it started
# in the foreground still runs. To stop a suite early, signal its process
# group. A signal the script has already caught when it reaches the command
# runs no command; one during the take ends this script at once. A KILL ends
# it outright, and the pool then reclaims the slot even while a suite it
# started still runs.
#
# Exit:
#   75     the wait passed its bound and the command did not run; stderr
#          carries a line starting `full-suite-run: wait expired`, stdout the
#          pool helper's holder lines
#   2      usage error; the command did not run
#   128+n  this script was stopped by signal n (HUP 129, INT 130, TERM 143)
#   other  the command's own status, except that a command exiting 75 is
#          reported as 1 with one stderr line saying so, so 75 always means
#          an expired wait
set -u
# The command runs in the caller's locale; only this script's own parsing is
# pinned to C.
caller_lc_all=${LC_ALL-}
caller_lc_all_set=${LC_ALL+1}
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ -f "$script_dir/echo-safety.sh" ] && [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  sanitize_printable() {
    _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')
    if [ -z "$_sp" ] && [ $# -ge 2 ]; then
      _sp=$2
    fi
    printf '%s' "$_sp"
  }
fi

usage() {
  printf 'usage: full-suite-run.sh [--run <id>] -- <command> [<arg>...]\n' >&2
  exit 2
}
warn() {
  printf 'full-suite-run: warning: %s; running unpooled\n' "$1" >&2
}

run_id=''
if [ "${1:-}" = --run ]; then
  [ "$#" -ge 2 ] || usage
  case $2 in
    [0-9][0-9][0-9][0-9][0-9][0-9]) run_id=$2 ;;
    *) usage ;;
  esac
  shift 2
fi
[ "${1:-}" = -- ] || usage
shift
[ "$#" -ge 1 ] || usage

valid_pool() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

caught=''
# shellcheck disable=SC2329 # invoked by the traps set below
on_signal() {
  caught=$1
}

# run_suite <mark> <command> [<arg>...] — run the command in the foreground,
# setting suite_rc, unless a signal has already arrived. An empty <mark>
# leaves the inherited one, if any.
run_suite() {
  _rs_mark=$1
  shift
  suite_rc=0
  [ -z "$caught" ] || return 0
  (
    if [ -n "$caller_lc_all_set" ]; then
      LC_ALL=$caller_lc_all
      export LC_ALL
    else
      unset LC_ALL
    fi
    if [ -n "$_rs_mark" ]; then
      PLANWRIGHT_STEP_POOL_HOLD=$_rs_mark
      export PLANWRIGHT_STEP_POOL_HOLD
    fi
    exec "$@" </dev/null
  )
  suite_rc=$?
}

pool=$("$script_dir/config-get.sh" full_suite_pool 2>/dev/null)
case $? in
  0) ;;
  3) pool='' ;;
  *)
    warn 'cannot read full_suite_pool'
    pool=''
    ;;
esac
if [ -n "$pool" ] && ! valid_pool "$pool"; then
  warn "full_suite_pool '$(sanitize_printable "$pool" '(unprintable)')' is not a pool name (^[a-z][a-z0-9-]*\$, at most 64 bytes)"
  pool=''
fi

# record <wait-outcome> <waited> <end>: the attempt's full-suite record under
# --run, its holders the ones the take's wait report named. A record that
# cannot be written warns and never changes the attempt's exit.
take_err=''
record() {
  [ -n "$run_id" ] || return 0
  set -- "$1" "$2" "$3" --start "$started"
  [ -z "$3" ] || set -- "$@" --end "$3"
  if [ -n "$take_err" ] && [ -f "$take_err" ]; then
    _hl=$(sed -n -e 's/^step-pool: .* waiting up to [0-9]*s on: //p' \
      -e 's/^step-pool: .* held by: //p' "$take_err" | tail -n 1)
    while [ -n "$_hl" ]; do
      case $_hl in
        *'; pid '*)
          set -- "$@" --holder "${_hl%%; pid *}"
          _hl="pid ${_hl#*; pid }"
          ;;
        *)
          set -- "$@" --holder "$_hl"
          _hl=''
          ;;
      esac
    done
  fi
  _wo=$1 _wt=$2
  shift 3
  "$script_dir/step-record.sh" write --full-suite --run "$run_id" --pool "$pool" \
    --wait "$_wt" --wait-outcome "$_wo" "$@" >/dev/null \
    || warn_only 'the full-suite record could not be written'
}
warn_only() {
  printf 'full-suite-run: warning: %s\n' "$1" >&2
}
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

state=''
waited=0
started=$(stamp)
if [ -n "$pool" ]; then
  owner=$$
  [ -z "$run_id" ] || take_err=$(mktemp "${TMPDIR:-/tmp}/full-suite-run.XXXXXX") || take_err=''
  if [ -n "$take_err" ]; then
    state=$("$script_dir/step-pool.sh" take "$pool" "$owner" 2>"$take_err")
    take_rc=$?
    cat "$take_err" >&2
  else
    state=$("$script_dir/step-pool.sh" take "$pool" "$owner")
    take_rc=$?
  fi
  waited=$(printf '%s\n' "$state" | awk -F '\t' 'NR == 1 && $3 ~ /^[0-9]+$/ { print $3 }')
  waited=${waited:-0}
  case $take_rc in
    0) ;;
    3)
      printf 'full-suite-run: wait expired for pool %s; no suite run; holders on stdout\n' "$pool" >&2
      printf '%s\n' "$state" | sed -n '2,$p'
      record expired "$waited" "$(stamp)"
      [ -z "$take_err" ] || rm -f "$take_err"
      exit 75
      ;;
    *)
      warn "the pool helper failed (exit $take_rc)"
      state=''
      ;;
  esac
  case $state in taken*) started=$(stamp) ;; esac
fi

# Set only now: a signal during the take ends this script at once, and the
# helper gives back a slot whose owner is gone.
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

case $state in
  taken*)
    run_suite "$pool:$owner" "$@"
    PLANWRIGHT_STEP_POOL_HOLD='' "$script_dir/step-pool.sh" release "$pool" "$owner" >/dev/null
    ;;
  *) run_suite '' "$@" ;;
esac
case $state in
  taken* | nested* | unpooled*) record "${state%%"$(printf '\t')"*}" "$waited" "$(stamp)" ;;
esac
[ -z "$take_err" ] || rm -f "$take_err"

[ -z "$caught" ] || exit "$caught"
if [ "$suite_rc" -eq 75 ]; then
  printf 'full-suite-run: the command itself exited 75; reported as 1\n' >&2
  exit 1
fi
exit "$suite_rc"
