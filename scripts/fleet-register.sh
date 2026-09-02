#!/bin/sh
# fleet-register.sh — the dispatch-time registration seam: the one place a
# dispatch seam turns "I just launched a worker" into a registry record
# (fleet-lifecycle-closure Task 3; D-12, REQ-E1.1, REQ-E1.2, REQ-E1.4,
# REQ-D1.5, REQ-K1.4).
#
# WHY A HELPER AND NOT FIVE CALL SITES. The registry primitive
# (fleet-state.sh register) is the store; this is the seam. Every dispatch path
# — the tmux worktree rung, the headless rung, the stream-json supervisor, and
# /offload's tmux and print rungs — owes the same three things, and owing them
# five times is how they drift:
#   1. RESOLVE THE OWNER TOKEN the same way, from the presence surface's tower
#      identity, so two towers can never be confused for one another and no
#      seam invents a second notion of who dispatched (REQ-D1.5).
#   2. WRITE THROUGH THE ONE STORE. There is no second store and no second
#      record shape; this script only assembles the call.
#   3. NEVER FAIL THE DISPATCH (REQ-E1.4). A worker that is running is a fact;
#      failing its launch because its bookkeeping did not land would trade a
#      real thing for a record of it. So a registration failure is reported
#      through THIS script's exit and a stderr warning, and every seam ignores
#      that exit. The gap self-heals on the next scan, which is the whole
#      reason the registry is a level-triggered inventory rather than an
#      authoritative ledger.
#
# THE OWNER TOKEN, resolved in order, first hit wins:
#   1. --session-id <uuid> | --pid <pid>   an explicit identity, resolved
#      through fleet-presence.sh's `identity` (never re-derived here — the
#      composite shape is that surface's decision, and two derivations would
#      eventually disagree about who a tower is).
#   2. $PLANWRIGHT_TOWER_ID                the tower's ALREADY-RESOLVED token,
#      exported into a seam it invokes. This is the ordinary path: a tower
#      knows its own identity, and a seam should not have to re-derive it.
#   3. $PLANWRIGHT_TOWER_SESSION_ID | $PLANWRIGHT_TOWER_PID   the identity
#      INPUTS carried in the environment, resolved as in (1).
#   4. Nothing resolvable -> the record's owner column is the absent sentinel,
#      and a reader classifies it unknown-owner. Said once on stderr, because
#      an unattributable worker is a thing an operator should be able to see
#      coming rather than discover at reap time.
# A malformed token from any arm is REFUSED, never silently degraded into an
# owner: mis-attribution is worse than no attribution, since a destructive verb
# reads this column. The refusal degrades to (4) with its own warning.
#
# The CHECKOUT feeds the composite identity's hash, so it must be the same
# checkout the tower published under, not the worker's worktree: --checkout,
# else $PLANWRIGHT_TOWER_CHECKOUT, else the cwd's git toplevel, else the cwd.
#
# Usage:
#   fleet-register.sh --handle <h> --scope <s> --backend <name>
#       [--state-dir <abs-dir>] [--death-handle <handle>]
#       [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
#
# Exit codes: 0 registered; 1 registration failed (warned on stderr — callers
#   ignore this, by contract); 2 usage error.
#
# POSIX sh on the macOS + Linux support bar. No eval; every value is data
# (REQ-K1.5). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-register

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
FS="$script_dir/fleet-state.sh"
FP="$script_dir/fleet-presence.sh"

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

warn() {
  echo "$me: $1" >&2
}

usage() {
  echo "usage: $me --handle <h> --scope <s> --backend <name> [--state-dir <abs-dir>] [--death-handle <handle>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]" >&2
  exit 2
}

handle=""
scope=""
backend=""
state_dir=""
death_handle=""
checkout=""
session_id=""
pid=""

while [ "$#" -gt 0 ]; do
  case $1 in
    --handle | --scope | --backend | --state-dir | --death-handle | --checkout | --session-id | --pid)
      [ "$#" -ge 2 ] || usage
      case $1 in
        --handle) handle=$2 ;;
        --scope) scope=$2 ;;
        --backend) backend=$2 ;;
        --state-dir) state_dir=$2 ;;
        --death-handle) death_handle=$2 ;;
        --checkout) checkout=$2 ;;
        --session-id) session_id=$2 ;;
        --pid) pid=$2 ;;
      esac
      shift 2
      ;;
    *)
      warn "unexpected argument '$(sanitize_printable "$1" "(unprintable argument)")'"
      usage
      ;;
  esac
done

[ -n "$handle" ] && [ -n "$scope" ] && [ -n "$backend" ] || usage

# Containment at this ingress (REQ-K1.4): a handle or scope beginning with a
# dash is an option-injection token the moment any later consumer passes it as
# an argv element, so it is refused here rather than stored and re-read. The
# rest of the field grammar is the store's, checked there — this is the one
# check the store's older, shared grammar does not make.
for arg in "$handle" "$scope"; do
  case $arg in
    -*)
      warn "refusing '$(sanitize_printable "$arg" "(unprintable value)")': a handle or scope may not begin with a dash"
      exit 2
      ;;
  esac
done

if [ ! -x "$FS" ]; then
  warn "cannot register $(sanitize_printable "$handle" "(unprintable handle)"): the registry store $FS is missing or not executable (broken install); the dispatch continues unregistered"
  exit 1
fi

# The owner-token grammar, kept identical to the store's (fleet-state.sh
# valid_owner) so this seam never offers the store a token it will refuse — and
# so a malformed value is caught HERE, where the fallback to unknown-owner can
# still keep the record.
valid_owner() {
  vo_v=$1
  case $vo_v in
    "" | . | .. | *[!A-Za-z0-9._-]*) return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#vo_v}" -le 128 ]
}

resolve_checkout() {
  if [ -n "$checkout" ]; then
    printf '%s\n' "$checkout"
    return 0
  fi
  if [ -n "${PLANWRIGHT_TOWER_CHECKOUT:-}" ]; then
    printf '%s\n' "$PLANWRIGHT_TOWER_CHECKOUT"
    return 0
  fi
  rc_top=$(git rev-parse --show-toplevel 2>/dev/null) || rc_top=""
  if [ -n "$rc_top" ]; then
    printf '%s\n' "$rc_top"
    return 0
  fi
  pwd
}

# via_presence <flag> <value> — the tower identity for an explicit identity
# input, through the presence surface and nowhere else.
via_presence() {
  [ -x "$FP" ] || return 1
  vp_out=$(/bin/sh "$FP" identity --checkout "$(resolve_checkout)" "$1" "$2" 2>/dev/null) || return 1
  [ -n "$vp_out" ] || return 1
  printf '%s\n' "$vp_out"
}

# resolve_owner — print the owner token, or nothing when none is resolvable.
# Every refusal it makes is announced by the caller, not swallowed here.
resolve_owner() {
  if [ -n "$session_id" ]; then
    via_presence --session-id "$session_id" && return 0
    warn "could not resolve a tower identity from --session-id; recording this dispatch as unknown-owner"
    return 1
  fi
  if [ -n "$pid" ]; then
    via_presence --pid "$pid" && return 0
    warn "could not resolve a tower identity from --pid; recording this dispatch as unknown-owner"
    return 1
  fi
  if [ -n "${PLANWRIGHT_TOWER_ID:-}" ]; then
    if valid_owner "$PLANWRIGHT_TOWER_ID"; then
      printf '%s\n' "$PLANWRIGHT_TOWER_ID"
      return 0
    fi
    warn "refusing malformed \$PLANWRIGHT_TOWER_ID '$(sanitize_printable "$PLANWRIGHT_TOWER_ID" "(unprintable token)")'; recording this dispatch as unknown-owner rather than mis-attributing it"
    return 1
  fi
  if [ -n "${PLANWRIGHT_TOWER_SESSION_ID:-}" ]; then
    via_presence --session-id "$PLANWRIGHT_TOWER_SESSION_ID" && return 0
    warn "could not resolve a tower identity from \$PLANWRIGHT_TOWER_SESSION_ID; recording this dispatch as unknown-owner"
    return 1
  fi
  if [ -n "${PLANWRIGHT_TOWER_PID:-}" ]; then
    via_presence --pid "$PLANWRIGHT_TOWER_PID" && return 0
    warn "could not resolve a tower identity from \$PLANWRIGHT_TOWER_PID; recording this dispatch as unknown-owner"
    return 1
  fi
  warn "no tower identity available (set \$PLANWRIGHT_TOWER_ID, or pass --session-id/--pid); recording this dispatch as unknown-owner"
  return 1
}

owner=$(resolve_owner) || owner=""

set -- register "$handle" "$scope"
[ -n "$owner" ] && set -- "$@" --owner "$owner"
set -- "$@" --backend "$backend"
[ -n "$state_dir" ] && set -- "$@" --state-dir "$state_dir"
[ -n "$death_handle" ] && set -- "$@" --death-handle "$death_handle"

if /bin/sh "$FS" "$@" >/dev/null; then
  exit 0
fi
warn "failed to register $(sanitize_printable "$handle" "(unprintable handle)") in the fleet registry; the dispatch stands and the next scan reconciles it"
exit 1
