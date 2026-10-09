#!/bin/sh
# full-suite-run.sh — run one full local suite attempt for /execute-task,
# holding a slot of the pool `full_suite_pool` names (doctrine/custom-steps.md,
# *Expensive checks*, The full suite). scripts/step-pool.sh owns the slot
# mechanics; this script is the full-suite owner the doctrine names, so the
# suite command reaches it as argv and runs with no shell or eval in between.
#
# Usage:
#   full-suite-run.sh -- <command> [<arg>...]
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
# The command runs as a child this script waits on, its stdin /dev/null. HUP,
# INT, or TERM reaching this script is passed to the command as TERM, and the
# slot is released only after the command has exited, so a signalled attempt
# never frees its slot while its suite still runs. The slot also frees once
# this process exits, released or not.
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
  printf 'usage: full-suite-run.sh -- <command> [<arg>...]\n' >&2
  exit 2
}
warn() {
  printf 'full-suite-run: warning: %s; running unpooled\n' "$1" >&2
}

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

child=''
caught=''
# shellcheck disable=SC2329 # invoked by the traps set below
on_signal() {
  caught=$1
  [ -z "$child" ] || kill -TERM "$child" 2>/dev/null
}

# run_suite <mark> <command> [<arg>...] — run the command as a waited-on
# child and set suite_rc. An empty <mark> leaves the inherited one, if any; a
# wait a trapped signal interrupts is resumed until the child has exited.
run_suite() {
  _rs_mark=$1
  shift
  if [ -n "$_rs_mark" ]; then
    PLANWRIGHT_STEP_POOL_HOLD="$_rs_mark" "$@" </dev/null &
  else
    "$@" </dev/null &
  fi
  child=$!
  while :; do
    wait "$child"
    suite_rc=$?
    kill -0 "$child" 2>/dev/null || break
  done
  child=''
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

state=''
if [ -n "$pool" ]; then
  owner=$$
  state=$("$script_dir/step-pool.sh" take "$pool" "$owner")
  take_rc=$?
  case $take_rc in
    0) ;;
    3)
      printf 'full-suite-run: wait expired for pool %s; no suite run; holders on stdout\n' "$pool" >&2
      printf '%s\n' "$state" | sed -n '2,$p'
      exit 75
      ;;
    *)
      warn "the pool helper failed (exit $take_rc)"
      state=''
      ;;
  esac
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

[ -z "$caught" ] || exit "$caught"
if [ "$suite_rc" -eq 75 ]; then
  printf 'full-suite-run: the command itself exited 75; reported as 1\n' >&2
  exit 1
fi
exit "$suite_rc"
