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
# the wait outcome (taken, nested, unpooled, or expired), the seconds waited,
# and the holders (an expired take's holder lines, else the wait report's),
# its start the take or, for an expired wait, the wait's start
# (doctrine/custom-steps.md, *Expensive checks*, The full suite). An attempt
# with no pool to take (none configured, an invalid value, a config read
# failure, or a failed take) writes none.
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

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# record <wait-outcome>: the attempt's full-suite record under --run, holders
# included. A record that cannot be written warns and never changes the
# attempt's exit.
record() {
  [ -n "$run_id" ] || return 0
  set -- --wait-outcome "$1" --start "$started" --end "$(stamp)"
  if [ -n "$tdir" ] && [ -s "$tdir/holders" ]; then
    while IFS= read -r _h; do
      set -- "$@" --holder "$_h"
    done <"$tdir/holders"
  fi
  "$script_dir/step-record.sh" write --full-suite --run "$run_id" --pool "$pool" \
    --wait "$waited" "$@" >/dev/null \
    || printf 'full-suite-run: warning: the full-suite record could not be written\n' >&2
}

# holders: one line per holder into $tdir/holders, from an expired take's
# holder lines, else from the wait report step-pool.sh printed at its start.
holders() {
  if grep -q '^holder	' "$tdir/out"; then
    awk -F '\t' '$1 == "holder" {
      w = ($4 == "(full-suite)") ? "the full-suite run" : "step " $4
      print "pid " $3 " (" w ", worktree " $5 ")"
    }' "$tdir/out"
  else
    sed -n 's/^step-pool: .* waiting up to [0-9]*s on: //p' "$tdir/err" | tail -n 1 \
      | awk '{ n = split($0, a, /; pid /); for (i = 1; i <= n; i++) print (i > 1 ? "pid " : "") a[i] }' \
      | grep -vx 'no live holder found'
  fi >"$tdir/holders"
}

state=''
waited=0
tdir=''
started=$(stamp)
if [ -n "$pool" ]; then
  owner=$$
  if [ -n "$run_id" ]; then
    tdir=$(mktemp -d "${TMPDIR:-/tmp}/full-suite-run.XXXXXX") || tdir=''
  fi
  if [ -n "$tdir" ] && mkfifo "$tdir/fifo"; then
    # The wait report reaches stderr as it is made, not after the wait.
    tee "$tdir/err" <"$tdir/fifo" >&2 &
    teep=$!
    "$script_dir/step-pool.sh" take "$pool" "$owner" >"$tdir/out" 2>"$tdir/fifo"
    take_rc=$?
    wait "$teep"
    state=$(cat "$tdir/out")
    holders
  else
    [ -z "$tdir" ] || rm -rf "$tdir"
    tdir=''
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
      record expired
      [ -z "$tdir" ] || rm -rf "$tdir"
      exit 75
      ;;
    *)
      warn "the pool helper failed (exit $take_rc)"
      state=''
      ;;
  esac
  # A record's start is the take, or the wait's start for an expired one.
  started=$(stamp)
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
  taken* | nested* | unpooled*) record "${state%%"$(printf '\t')"*}" ;;
esac
[ -z "$tdir" ] || rm -rf "$tdir"

[ -z "$caught" ] || exit "$caught"
if [ "$suite_rc" -eq 75 ]; then
  printf 'full-suite-run: the command itself exited 75; reported as 1\n' >&2
  exit 1
fi
exit "$suite_rc"
