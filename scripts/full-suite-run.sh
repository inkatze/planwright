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
# full_suite_pool resolves through scripts/config-get.sh. Empty (the core
# default) runs the command unpooled with no output of this script's own, as
# before the pool existed. A value outside the pool charset warns once naming
# the key and runs unpooled: an unusable pool never blocks a suite, as
# step-pool.sh's own unpooled fallback does.
#
# A pooled attempt takes a slot on behalf of this script's own process, waiting
# up to step_pool_wait, runs the command with PLANWRIGHT_STEP_POOL_HOLD set on
# its command line only, and releases whatever the command's exit. A take that
# prints `nested` or `unpooled` runs the command with the inherited mark, if
# any, and releases nothing. The slot frees once this process exits, released
# or not. One attempt is one slot: a retry calls this script again.
#
# Exit: the command's own status; 75 when the wait passed its bound, the
# command not run, stderr carrying a line starting `full-suite-run: wait
# expired` and stdout the pool helper's holder lines; 2 on a usage error, a
# config read failure, or a pool helper failure, the command not run.
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

[ "${1:-}" = -- ] || usage
shift
[ "$#" -ge 1 ] || usage

pool=$("$script_dir/config-get.sh" full_suite_pool) || {
  printf 'full-suite-run: cannot read full_suite_pool; no suite run\n' >&2
  exit 2
}

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

if [ -z "$pool" ]; then
  "$@"
  exit
fi
if ! valid_pool "$pool"; then
  printf "full-suite-run: warning: full_suite_pool '%s' is not a pool name (^[a-z][a-z0-9-]*\$, at most 64 bytes); running unpooled\n" \
    "$(sanitize_printable "$pool" '(unprintable)')" >&2
  "$@"
  exit
fi

owner=$$
state=$("$script_dir/step-pool.sh" take "$pool" "$owner")
rc=$?
case $rc in
  0) ;;
  3)
    printf 'full-suite-run: wait expired for pool %s; no suite run; holders on stdout\n' "$pool" >&2
    printf '%s\n' "$state" | sed -n '2,$p'
    exit 75
    ;;
  *)
    printf 'full-suite-run: pool helper failed (exit %s); no suite run\n' "$rc" >&2
    exit 2
    ;;
esac

case $state in
  taken*)
    PLANWRIGHT_STEP_POOL_HOLD="$pool:$owner" "$@"
    rc=$?
    "$script_dir/step-pool.sh" release "$pool" "$owner" >/dev/null
    exit "$rc"
    ;;
  *)
    "$@"
    ;;
esac
