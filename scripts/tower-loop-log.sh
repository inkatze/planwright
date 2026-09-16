#!/bin/sh
# tower-loop-log.sh — the tower loop's two event-log writers (tower-comms
# D-14, D-15; REQ-G1.1, REQ-G1.3, REQ-G1.6, REQ-H1.4), thin over
# `tower-queue.sh log`, which owns the lock, the sequence, the bounded wait,
# the redaction and the tick coalescing.
#
#   tick [--tower <id>] [--now <epoch>]
#       One pass of the loop: count the live workers and append a `tick`
#       carrying that count. A worker is live when its row in the fleet's
#       attention store (`<fleet-home>/attention/state`, the surface every
#       heartbeating backend writes) is in a live state — working, idle,
#       hung, awaiting-input or pr-ready. ended, merged and done are not live,
#       and a row whose state is none of those is corruption and counts
#       nothing. The log verb coalesces the tick with the previous one when
#       the count is unchanged, so a steady fleet costs one line per count
#       change and the scorecard's fleet hours come from these spans. Prints
#       `tick<TAB>live=<n>` on success.
#   delivered [--tower <id>] [--asks <n>] [--now <epoch>]   (text on stdin)
#       A turn the tower delivered to the operator: the text is flattened to
#       one line of printable bytes, bounded to the log's value cap, and
#       appended as a `delivered` line with no item, which the scorecard
#       counts as a prose delivery; `asks` is the number of asks the turn
#       carried, for the multi-ask measure. Prints nothing on success.
#
# The tower identity is `--tower`, else PLANWRIGHT_TOWER_ID, else
# PLANWRIGHT_TOWER_SESSION_ID (the presence surface's UUID form) — the order
# the queue verbs and fleet-register.sh resolve it in — and none resolvable is
# a refusal, because a tick or a delivery with no writing tower is a line the
# scorecard cannot attribute (REQ-G1.6).
#
# Exit: 0 written (a coalesced tick included); 2 usage or refused input (no
#   identity, a malformed one, a non-numeric ask count, an empty turn); 6 the
#   attention store exists but cannot be read; otherwise the log verb's own
#   exit (3 the bounded lock wait expired and the line was dropped, 4 the
#   surface refused, 5 broken install, 6 infrastructure).
#
# Plain portable shell, no model invocation (REQ-H1.4); bash 3.2 / BSD floor.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "tower-loop-log: scripts/echo-safety.sh is missing — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
TQ="$script_dir/tower-queue.sh"

usage() {
  cat >&2 <<'EOF'
usage: tower-loop-log.sh tick [--tower <id>] [--now <epoch>]
       tower-loop-log.sh delivered [--tower <id>] [--asks <n>] [--now <epoch>]   (text on stdin)
EOF
  exit 2
}

err() {
  printf '%s\n' "tower-loop-log: $1" >&2
}

is_tower() {
  case "$1" in
    "" | *[!A-Za-z0-9._-]* | .* | -*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

is_uuid() {
  [ "${#1}" -eq 36 ] || return 1
  case "$1" in
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  _h=$(printf '%s' "$1" | tr -d -- '-')
  [ "${#_h}" -eq 32 ] || return 1
  case "$_h" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  return 0
}

is_count() {
  case "$1" in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

# resolve_tower <flag-value> — the identity in the documented order, or a
# refusal naming the source that failed.
resolve_tower() {
  if [ -n "$1" ]; then
    is_tower "$1" || {
      err "refusing --tower '$(sanitize_printable "$1" "(unprintable identity)")': not a tower identity"
      exit 2
    }
    printf '%s\n' "$1"
    return 0
  fi
  if [ -n "${PLANWRIGHT_TOWER_ID:-}" ]; then
    is_tower "$PLANWRIGHT_TOWER_ID" || {
      err "refusing malformed \$PLANWRIGHT_TOWER_ID '$(sanitize_printable "$PLANWRIGHT_TOWER_ID" "(unprintable identity)")'"
      exit 2
    }
    printf '%s\n' "$PLANWRIGHT_TOWER_ID"
    return 0
  fi
  if [ -n "${PLANWRIGHT_TOWER_SESSION_ID:-}" ]; then
    is_uuid "$PLANWRIGHT_TOWER_SESSION_ID" || {
      err "refusing malformed \$PLANWRIGHT_TOWER_SESSION_ID '$(sanitize_printable "$PLANWRIGHT_TOWER_SESSION_ID" "(unprintable identity)")' (a session UUID)"
      exit 2
    }
    printf '%s\n' "$PLANWRIGHT_TOWER_SESSION_ID"
    return 0
  fi
  err "no tower identity: pass --tower <id>, or set PLANWRIGHT_TOWER_ID or PLANWRIGHT_TOWER_SESSION_ID; every tick and delivery line carries the writing tower"
  exit 2
}

# live_workers — the count from the attention store, 0 when there is none.
live_workers() {
  _home=$("$FS" root 2>/dev/null) || {
    err "cannot resolve the fleet home (fleet-state.sh root failed)"
    exit 6
  }
  _store="$_home/attention/state"
  if [ ! -e "$_store" ]; then
    printf '0\n'
    return 0
  fi
  [ -r "$_store" ] || {
    err "the attention store exists but cannot be read; no tick written rather than a wrong count"
    exit 6
  }
  awk -F'\t' '
    $1 != "" && ($3 == "working" || $3 == "idle" || $3 == "hung" || $3 == "awaiting-input" || $3 == "pr-ready") { n++ }
    END { print n + 0 }' "$_store" 2>/dev/null || {
    err "cannot read the attention store"
    exit 6
  }
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift
case "$cmd" in
  tick | delivered) ;;
  *)
    err "unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (tick | delivered)"
    exit 2
    ;;
esac

tower_arg=""
now=""
asks=""
asks_set=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tower)
      [ "$#" -ge 2 ] || usage
      tower_arg=$2
      shift 2
      ;;
    --now)
      [ "$#" -ge 2 ] || usage
      now=$2
      shift 2
      ;;
    --asks)
      [ "$cmd" = delivered ] || usage
      [ "$#" -ge 2 ] || usage
      asks=$2
      asks_set=1
      shift 2
      ;;
    *) usage ;;
  esac
done

tower=$(resolve_tower "$tower_arg") || exit $?

set -- log "$cmd" --tower "$tower"
[ -z "$now" ] || set -- "$@" --now "$now"

case "$cmd" in
  tick)
    live=$(live_workers) || exit $?
    "$TQ" "$@" "live=$live" || exit $?
    printf 'tick\tlive=%s\n' "$live"
    ;;
  delivered)
    if [ "$asks_set" = 1 ] && ! is_count "$asks"; then
      err "refusing --asks '$(sanitize_printable "$asks" "(unprintable count)")': a non-negative integer"
      exit 2
    fi
    # Flatten, bound, trim: every control byte (newlines and tabs included)
    # becomes a space, the text is cut at the log's value cap, and the edges
    # are trimmed so a turn that ends in a newline does not end in a space.
    text=$(head -c 65536 2>/dev/null | tr '\000-\037\177' ' ' | head -c 4096 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$text" in
      "")
        err "nothing to log: the delivered turn's text on stdin is empty"
        exit 2
        ;;
      '{'*'}' | '['*']') set -- "$@" text_omitted=json-shaped ;;
      *) set -- "$@" "text=$text" ;;
    esac
    [ "$asks_set" = 0 ] || set -- "$@" "asks=$asks"
    "$TQ" "$@" || exit $?
    ;;
esac
exit 0
