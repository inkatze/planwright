#!/bin/sh
# fleet-reap-lock.sh — the per-worker reap lock: one reaper closes a worker at
# a time, however many towers are sweeping (fleet-lifecycle-closure REQ-D1.6).
#
# WHY. Without it, N towers whose sweeps meet the same dead owner's worker each
# call the rung's `stop`, each finds the process class held, each signals the
# tree, and each records a termination: one worker, N reaps in the audit trail,
# N signal storms at one process tree. The rung's close is idempotent over its
# release set, but only in sequence; the lock is what makes the reaps a
# sequence.
#
# THE HOLD BELONGS TO THE REAPER, not to this short-lived CLI: `take` acquires
# on behalf of the caller's pid (lock-lib's pw_lock_acquire_for), so a reaper
# killed mid-reap leaves a hold whose owner is gone, which the next reaper
# breaks on that absence rather than waiting out an age. The break cannot
# admit two holders (lock-lib's claim-link break). `drop` releases by token,
# and only while the lock is still that token's.
#
# A reaper that does not get the lock stands down for this cycle: the holder
# is closing the worker, and a later sweep finds it already closed.
#
# The lock lives at <fleet-home>/reap-locks/<worker>, beside nothing else.
#
# Usage:
#   fleet-reap-lock.sh take <worker> <owner-pid>   prints the token on stdout
#   fleet-reap-lock.sh drop <worker> <token>
#
# Exit codes: 0 taken / dropped; 1 another live reaper holds it (take), or it
#   is not that token's (drop); 2 usage, refused input, or a lock error.
#
# POSIX sh on the macOS + Linux support bar. All input is data; no eval.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"

warn() { printf 'fleet-reap-lock: %s\n' "$*" >&2; }

usage() {
  warn "usage: fleet-reap-lock.sh take <worker> <owner-pid> | drop <worker> <token>"
  exit 2
}

[ "$#" -eq 3 ] || usage
verb=$1
worker=$2
arg=$3

# The worker-handle grammar every fleet store uses, with no leading dash: the
# handle becomes a path component.
case $worker in
  "" | . | .. | -* | *[!A-Za-z0-9._=@:-]*)
    warn "refusing a malformed worker handle"
    exit 2
    ;;
esac
[ "${#worker}" -le 128 ] || {
  warn "refusing an over-length worker handle"
  exit 2
}

root=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) || root=""
[ -n "$root" ] || {
  warn "cannot resolve the fleet home"
  exit 2
}
dir="$root/reap-locks"
if [ -L "$dir" ]; then
  warn "refusing the reap-lock directory: it is a symbolic link"
  exit 2
fi
umask 077
mkdir -p "$dir" 2>/dev/null
[ -d "$dir" ] || {
  warn "cannot create the reap-lock directory"
  exit 2
}

case $verb in
  take)
    case $arg in
      "" | 0 | *[!0-9]*) usage ;;
    esac
    # A short budget: long enough to break a dead reaper's hold and to ride out
    # a peer breaking it at the same instant, short enough that a live holder
    # means "stand down this cycle".
    take_rc=0
    pw_lock_acquire_for "$dir/$worker" "$arg" 25 || take_rc=$?
    [ "$take_rc" = 0 ] || exit "$take_rc"
    printf '%s\n' "$PW_LOCK_TOKEN"
    exit 0
    ;;
  drop)
    [ -n "$arg" ] || usage
    drop_rc=0
    pw_lock_release_token "$dir/$worker" "$arg" || drop_rc=$?
    exit "$drop_rc"
    ;;
  *) usage ;;
esac
