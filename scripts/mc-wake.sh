#!/usr/bin/env bash
# mc-wake.sh — the daemon side of mission control's wake: the relay that
# pushes a program's pending events (scripts/mc-event.sh) to its sessions
# that run without the mod, and the failsafe tick behind it.
#
# A WAKE TARGET is a registered session (a fleet registry worker,
# scripts/fleet-state.sh) the program's events should wake, recorded with
# whether the mod loads in it. A session with the mod is woken by the mod,
# which watches the attention store itself; the relay and the tick leave it
# alone.
#
# THE RELAY goes through the fleet's own session relay for the backend the
# registry records for the worker, and it never types into a session:
#   stream-json, stream-json-persistent
#             scripts/fleet-streamjson.sh steer: a user turn on the worker's
#             stdin, so the wake is SUBMITTED and its events marked so
#   tmux      scripts/orchestrate-relay.sh deliver tmux: a buffer paste with
#             no newline, so the wake is STAGED and its events marked staged
#             until the session acknowledges them (below)
#   any other backend, or a retired worker: unreachable, nothing sent
# One wake per target lists the pending events' kinds and subjects (at most
# 20, then a count), never their free text, which the session reads through
# `mc-event.sh list`; it is written to a file of its own under
# <runtime>/wake/, which a staged pointer reads. A staged wake asks the
# session to acknowledge with `mc-event.sh mark ... submitted <id>...` once
# read, which is what moves its events from staged to submitted.
#
# THE TICK is the failsafe for both paths: at most once per
# mission_control_tick_cadence it sends every target without the mod one
# wake for its events not yet submitted, staged ones included, so an event
# the push missed, or staged and nobody acknowledged, is found within one
# tick. A tick with nothing pending sends nothing.
#
# Usage:
#   mc-wake.sh target add --program <p> <worker> [--mod]
#   mc-wake.sh target remove --program <p> <worker>
#   mc-wake.sh target list --program <p>       <worker><TAB>mod|no-mod
#   mc-wake.sh relay --program <p>
#       push each target's events no relay has delivered: one line per
#       target,
#         submitted|staged<TAB><worker><TAB><n>
#         unconfirmed<TAB><worker><TAB><n>     the paste ran but was not seen;
#                                              marked staged, never re-pasted
#                                              by the relay
#         mod<TAB><worker>                     the mod wakes it
#         idle<TAB><worker>                    nothing to send
#         unreachable<TAB><worker><TAB><why>
#         refused<TAB><worker><TAB><exit>      the relay declined (a dialog
#                                              open, an earlier wake staged)
#       or `paused` under the fleet daemon pause (`blocked<TAB><exit>` when
#       the gate itself is broken).
#   mc-wake.sh tick --program <p> [--now <epoch>]
#       `not-due<TAB><seconds left>` before the cadence has passed; else
#       `tick`, then the relay's lines over every event not yet submitted;
#       or `paused` (`blocked`) as the relay.
#
# Exit codes: 0 done (a refused or unreachable target is reported, not a
# failure); 1 a store that cannot be read or written; 2 usage; 3 the program
# is not configured.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-wake
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

LISTED_MAX=20

usage() {
  mc_usage_fail "usage: mc-wake.sh target add|remove|list --program <p> [<worker>] [--mod] | relay --program <p> | tick --program <p> [--now <epoch>]"
}

[ $# -ge 1 ] || usage
verb=$1
shift
sub=""
if [ "$verb" = target ]; then
  [ $# -ge 1 ] || usage
  sub=$1
  shift
fi
program=""
now=""
mod=0
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    --mod)
      mod=1
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
[ -n "$program" ] || usage
mc_now_arg "$now"
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
targets="$runtime/wake-targets"

# send <worker> unmarked|unsubmitted: one wake for the worker's events that
# carry no mark, or that are not yet submitted.
send() {
  sd_w=$1
  sd_row=$(printf '%s\n' "$REGISTRY" | W=$sd_w awk -F '\t' '$2 == ENVIRON["W"] { r = $0 } END { print r }')
  if [ -z "$sd_row" ]; then
    printf 'unreachable\t%s\tnot in the fleet registry\n' "$sd_w"
    return 0
  fi
  if [ "$(printf '%s\n' "$sd_row" | awk -F '\t' '{ print (NF == 8 && $8 == "closed") ? "closed" : "live" }')" = closed ]; then
    printf 'unreachable\t%s\tretired\n' "$sd_w"
    return 0
  fi
  sd_backend=$(printf '%s' "$sd_row" | cut -f5)
  sd_handle=""
  case $sd_backend in
    stream-json | stream-json-persistent) sd_mark=submitted ;;
    tmux)
      sd_mark=staged
      sd_handle=$(printf '%s' "$sd_row" | cut -f7)
      case $sd_handle in
        "tmux-window "*" "*)
          sd_handle=${sd_handle#tmux-window }
          sd_handle="${sd_handle%% *}:${sd_handle#* }"
          ;;
        *) sd_handle="" ;;
      esac
      if [ -z "$sd_handle" ] || ! /bin/sh "$script_dir/orchestrate-relay.sh" validate-handle tmux "$sd_handle" 2>/dev/null; then
        printf 'unreachable\t%s\tno valid tmux window recorded\n' "$sd_w"
        return 0
      fi
      ;;
    *)
      printf 'unreachable\t%s\tbackend %s has no session relay\n' "$sd_w" "$(sanitize_printable "$sd_backend" -)"
      return 0
      ;;
  esac
  sd_rows=$(mc_event list --program "$program" --target "$sd_w" --pending) || return 1
  [ "$2" = unsubmitted ] || sd_rows=$(printf '%s\n' "$sd_rows" | awk -F '\t' '$NF == "-"')
  sd_n=$(printf '%s' "$sd_rows" | awk 'NF { n++ } END { print n + 0 }')
  if [ "$sd_n" -eq 0 ]; then
    printf 'idle\t%s\n' "$sd_w"
    return 0
  fi
  sd_ids=$(printf '%s\n' "$sd_rows" | awk -F '\t' 'NF { print $1 }')
  mkdir -p "$runtime/wake" || return 1
  sd_msg=$(mktemp "$runtime/wake/$sd_w.XXXXXX") || return 1
  {
    printf 'mission control (%s): %s event(s) pending.\n' "$program" "$sd_n"
    printf '%s\n' "$sd_rows" | M=$LISTED_MAX awk -F '\t' 'NF { n++; if (n <= ENVIRON["M"] + 0) print "- " $3 " " $4 }
      END { if (n > ENVIRON["M"] + 0) print "- and " (n - ENVIRON["M"]) " more" }'
    printf 'Read them with: %s list --program %s --target %s --pending\n' \
      "$script_dir/mc-event.sh" "$program" "$sd_w"
    if [ "$sd_mark" = staged ]; then
      printf 'Then acknowledge them with: %s mark --program %s --target %s submitted %s\n' \
        "$script_dir/mc-event.sh" "$program" "$sd_w" "$(printf '%s\n' "$sd_ids" | tr '\n' ' ' | sed 's/ $//')"
    fi
  } >"$sd_msg" || {
    rm -f "$sd_msg"
    return 1
  }
  if [ "$sd_mark" = submitted ]; then
    /bin/sh "$script_dir/fleet-streamjson.sh" steer "$sd_w" --message-file "$sd_msg" >/dev/null 2>&1
  else
    /bin/sh "$script_dir/orchestrate-relay.sh" deliver tmux "$sd_handle" "$sd_msg" >/dev/null 2>&1
  fi
  sd_rc=$?
  sd_said=$sd_mark
  case $sd_rc in
    0) ;;
    4)
      # The paste ran, or may have, but its tag never showed: pasting again
      # would stage a duplicate, so it is marked staged and left to the tick.
      [ "$sd_mark" = staged ] || {
        rm -f "$sd_msg"
        printf 'refused\t%s\t%s\n' "$sd_w" "$sd_rc"
        return 0
      }
      sd_said=unconfirmed
      ;;
    *)
      rm -f "$sd_msg"
      printf 'refused\t%s\t%s\n' "$sd_w" "$sd_rc"
      return 0
      ;;
  esac
  # shellcheck disable=SC2086 # one event id per word
  mc_event mark --program "$program" --target "$sd_w" "$sd_mark" $sd_ids || return 1
  printf '%s\t%s\t%s\n' "$sd_said" "$sd_w" "$sd_n"
}

# each unmarked|unsubmitted: send to every target without the mod.
each() {
  [ -f "$targets" ] || return 0
  REGISTRY=$(/bin/sh "$script_dir/fleet-state.sh" registry 2>/dev/null) || mc_fail "cannot read the fleet registry"
  ea_list=$(cat "$targets") || mc_fail "cannot read the wake targets"
  while IFS='	' read -r ea_w ea_mod; do
    mc_valid_handle "$ea_w" || continue
    if [ "$ea_mod" = mod ]; then
      printf 'mod\t%s\n' "$ea_w"
      continue
    fi
    send "$ea_w" "$1" || mc_fail "cannot read or mark the events for '$ea_w'"
  done <<EOF
$ea_list
EOF
}

case $verb in
  target)
    case $sub in
      add | remove)
        [ "${#args[@]}" -eq 1 ] || usage
        w=${args[0]}
        mc_valid_handle "$w" || mc_usage_fail "invalid worker '$(sanitize_printable "$w")'"
        [ "$sub" = add ] || [ "$mod" -eq 0 ] || usage
        line=""
        if [ "$sub" = add ]; then
          if [ "$mod" -eq 1 ]; then line="$w	mod"; else line="$w	no-mod"; fi
        fi
        mc_lock || mc_fail "cannot take the fleet lock"
        trap 'mc_unlock' EXIT
        mc_upsert "$targets" "$w" "$line" || mc_fail "cannot read or write the wake targets"
        ;;
      list)
        [ "${#args[@]}" -eq 0 ] || usage
        [ ! -f "$targets" ] || mc_clean <"$targets"
        ;;
      *) usage ;;
    esac
    ;;
  relay)
    [ "${#args[@]}" -eq 0 ] || usage
    mc_gate_or_exit mc-wake
    each unmarked
    ;;
  tick)
    [ "${#args[@]}" -eq 0 ] || usage
    mc_gate_or_exit mc-wake
    cadence=$(mc_knob mission_control_tick_cadence mc_parse_cadence) || exit 1
    secs=$(mc_seconds "$cadence")
    last=0
    if [ -f "$runtime/last-tick" ]; then
      last=$(head -n 1 "$runtime/last-tick")
      # A stamp from the future (a clock step, an edited file) never holds
      # the failsafe off.
      mc_valid_uint "$last" && [ "$last" -le "$NOW" ] || last=0
    fi
    if [ $((NOW - last)) -lt "$secs" ]; then
      printf 'not-due\t%s\n' $((secs - (NOW - last)))
      exit 0
    fi
    printf 'tick\n'
    each unsubmitted
    printf '%s\n' "$NOW" | mc_write "$runtime/last-tick" || mc_fail "cannot record the tick"
    if [ -d "$runtime/wake" ]; then
      # Wake files a week old have long been read or superseded.
      find "$runtime/wake" -type f -mtime +7 -exec rm -f {} + 2>/dev/null || :
    fi
    ;;
  *) usage ;;
esac
