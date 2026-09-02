#!/bin/sh
# fleet-register.sh — the dispatch-time registration seam: the one place a
# dispatch seam turns "I just launched a worker" into a registry record
# (fleet-lifecycle-closure Task 3; D-12, REQ-E1.1, REQ-E1.2, REQ-E1.4,
# REQ-D1.5, REQ-K1.4).
#
# WHY A HELPER AND NOT ONE CALL SITE PER SEAM. The registry primitive
# (fleet-state.sh register) is the store; this is the seam. Every dispatch path
# owes the same three things, and owing them once per seam is how they drift:
#   1. RESOLVE THE OWNER TOKEN the same way, from the presence surface's tower
#      identity, so two towers can never be confused for one another and no
#      seam invents a second notion of who dispatched (REQ-D1.5).
#   2. WRITE THROUGH THE ONE STORE. There is no second store and no second
#      record shape; this script only assembles the call.
#   3. NEVER FAIL THE DISPATCH (REQ-E1.4). A worker that is running is a fact;
#      failing its launch because its bookkeeping did not land would trade a
#      real thing for a record of it. So a registration failure is reported
#      through THIS script's exit and a stderr warning, and every seam ignores
#      that exit.
#
# PER-FIELD DEGRADE, NOT ALL-OR-NOTHING. The store is strict: it refuses a
# malformed field rather than storing it, which is right for a store a
# destructive verb reads. But a strict store plus a pass-through seam means one
# bad optional column costs a LIVE worker its whole record — the exact leak this
# bundle exists to close. So this seam validates each optional field itself
# against the store's own grammar and drops a failing one to absent, warning as
# it goes: an inventory entry with one blank column beats no entry at all. Only
# the handle and scope are load-bearing enough to refuse outright.
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
# A malformed token from any arm is refused and degrades to (4) with its own
# warning — including one that came back from the presence surface, which is
# checked here rather than trusted, so this file's stated guarantee is this
# file's to keep. Mis-attribution is worse than no attribution: a destructive
# verb reads this column.
#
# The CHECKOUT feeds the composite identity's hash, so it must be the same
# checkout the tower published under, not the worker's worktree: --checkout,
# else $PLANWRIGHT_TOWER_CHECKOUT, else the cwd's git toplevel, else the cwd.
# A seam that has cd'd into the worker's directory must pass --checkout
# explicitly; a cwd-derived hash there names a tower that exists nowhere.
#
# Usage:
#   fleet-register.sh --handle <h> --backend <name> [--scope <s>]
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

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  echo "fleet-register: cannot resolve the script's own directory" >&2
  exit 2
}
FS="$script_dir/fleet-state.sh"
FP="$script_dir/fleet-presence.sh"

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# printf, never echo: under dash (/bin/sh on the Linux support bar) `echo`
# re-expands backslash escapes, so a value carrying the four printable
# characters `\`, `0`, `3`, `3` would become a real ESC on the operator's
# terminal — passing straight through sanitize_printable, which strips control
# BYTES and has no such sequence to find. Every diagnostic here takes untrusted
# input, so every one of them uses printf (doctrine/security-posture.md).
warn() {
  printf '%s\n' "$me: $1" >&2
}

usage() {
  printf '%s\n' "usage: $me --handle <h> --backend <name> [--scope <s>] [--state-dir <abs-dir>] [--death-handle <handle>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]" >&2
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

[ -n "$handle" ] && [ -n "$backend" ] || usage
# An absent scope is the store's `-` sentinel, not an invented word: a reader
# must be able to tell "no scope was recorded" from a worker whose scope really
# is `unknown`.
[ -n "$scope" ] || scope="-"

# Containment at this ingress (REQ-K1.4): a handle or scope beginning with a
# dash is an option-injection token the moment any later consumer passes it as
# an argv element, so it is refused here rather than stored and re-read. The
# rest of the field grammar is the store's, checked there — this is the one
# check the store's older, shared grammar does not make. The bare `-` sentinel
# is exempt: it is the store's own absent marker, not a caller's token.
for arg in "$handle" "$scope"; do
  [ "$arg" = "-" ] && continue
  case $arg in
    -*)
      warn "refusing '$(sanitize_printable "$arg" "(unprintable value)")': a handle or scope may not begin with a dash"
      exit 2
      ;;
  esac
done

# Readable, not executable: every caller invokes this script as `/bin/sh <path>`,
# so the exec bit is not what the call depends on. Gating a seam on `-x` means a
# checkout with `core.fileMode=false`, an unzip, or an `rsync` without `-p`
# silently turns registration off fleet-wide with nothing on stderr.
if [ ! -r "$FS" ]; then
  warn "cannot register $(sanitize_printable "$handle" "(unprintable handle)"): the registry store $FS is missing or unreadable (broken install); the dispatch continues unregistered"
  exit 1
fi

# The field grammars, kept identical to the store's (fleet-state.sh), so this
# seam never offers the store a value it will refuse — and so a malformed value
# is caught HERE, where dropping one column can still keep the record.
valid_owner() {
  vo_v=$1
  case $vo_v in
    "" | . | .. | unknown-owner | *[!A-Za-z0-9._-]*) return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#vo_v}" -le 128 ]
}

valid_backend() {
  vb_v=$1
  case $vb_v in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#vb_v}" -le 64 ]
}

valid_state_dir() {
  vsd_v=$1
  case $vsd_v in
    / | */../* | */.. | ../*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  [ "${#vsd_v}" -le 4096 ] || return 1
  [ "$(printf '%s' "$vsd_v" | tr -d '\000-\037\177')" = "$vsd_v" ]
}

valid_tmux_token() {
  vtt_v=$1
  case $vtt_v in
    "" | -* | *[!A-Za-z0-9._@%-]*) return 1 ;;
  esac
  [ "${#vtt_v}" -le 128 ]
}

valid_death_handle() {
  vdh_v=$1
  case $vdh_v in
    none) return 0 ;;
    "process "*)
      vdh_pid=${vdh_v#process }
      case $vdh_pid in
        "" | 0* | *[!0-9]*) return 1 ;;
      esac
      [ "${#vdh_pid}" -le 10 ]
      ;;
    "tmux-window "*)
      vdh_rest=${vdh_v#tmux-window }
      case $vdh_rest in
        *" "*) ;;
        *) return 1 ;;
      esac
      valid_tmux_token "${vdh_rest%% *}" && valid_tmux_token "${vdh_rest#* }"
      ;;
    *) return 1 ;;
  esac
}

# keep_or_drop <kind> <value> — print the value when it passes its grammar,
# print nothing and warn when it does not. The per-field degrade: one bad
# optional column costs that column, never the record. The predicate is chosen
# by an explicit case rather than called through a variable, so every one of
# them has a visible call site.
keep_or_drop() {
  kod_kind=$1
  kod_value=$2
  [ -n "$kod_value" ] || return 0
  case $kod_kind in
    backend) valid_backend "$kod_value" && kod_ok=1 || kod_ok=0 ;;
    state-dir) valid_state_dir "$kod_value" && kod_ok=1 || kod_ok=0 ;;
    death-handle) valid_death_handle "$kod_value" && kod_ok=1 || kod_ok=0 ;;
    *) kod_ok=0 ;;
  esac
  if [ "$kod_ok" = 1 ]; then
    printf '%s\n' "$kod_value"
    return 0
  fi
  warn "dropping malformed $kod_kind '$(sanitize_printable "$kod_value" "(unprintable value)")' from the record for $(sanitize_printable "$handle" "(unprintable handle)"); the rest of the record still lands"
  return 0
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
# input, through the presence surface and nowhere else. Its answer is still
# checked against the owner grammar here: the guarantee this file's header
# states is this file's to keep, and an unchecked value would reach the store,
# be refused there, and take the whole record with it.
via_presence() {
  [ -r "$FP" ] || return 1
  vp_out=$(/bin/sh "$FP" identity --checkout "$(resolve_checkout)" "$1" "$2" 2>/dev/null) || return 1
  valid_owner "$vp_out" || return 1
  printf '%s\n' "$vp_out"
}

# resolve_owner — print the owner token, or nothing when none is resolvable.
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
backend=$(keep_or_drop backend "$backend")
state_dir=$(keep_or_drop state-dir "$state_dir")
death_handle=$(keep_or_drop death-handle "$death_handle")

# A backend that failed its grammar leaves the record without the one field that
# says which rung to close it on, which is not a record worth writing.
if [ -z "$backend" ]; then
  warn "cannot register $(sanitize_printable "$handle" "(unprintable handle)"): no usable backend name"
  exit 1
fi

set -- register "$handle" "$scope"
[ -n "$owner" ] && set -- "$@" --owner "$owner"
set -- "$@" --backend "$backend"
[ -n "$state_dir" ] && set -- "$@" --state-dir "$state_dir"
[ -n "$death_handle" ] && set -- "$@" --death-handle "$death_handle"

if /bin/sh "$FS" "$@" >/dev/null; then
  exit 0
fi
# No claim about self-healing here: this registry has exactly one writer (this
# script), and the periodic reconcile that would notice a missing record is a
# later task in this bundle. Until it lands, a failed registration means this
# worker is absent from the fleet's inventory for its whole life, which is
# precisely the thing worth saying out loud.
warn "failed to register $(sanitize_printable "$handle" "(unprintable handle)") in the fleet registry; the dispatch stands, but this worker will not appear in the fleet inventory and no reconcile exists yet to add it"
exit 1
