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
#             stdin, so the wake is SUBMITTED
#   tmux      scripts/orchestrate-relay.sh deliver tmux: a buffer paste with
#             no newline, so the wake is STAGED and waits for a submit
#   any other backend, or a retired worker: unreachable, nothing sent
# The wake text names the pending events and points at
# `mc-event.sh list --program <p> --target <worker> --pending`; it is written
# to <runtime>/wake/<worker>.msg, which a staged pointer reads.
#
# THE TICK is the failsafe for both paths: at most once per
# mission_control_tick_cadence it looks at every target without the mod and
# sends a wake for every event not yet submitted, staged ones included, so
# an event the push missed or only staged is found within one tick. A tick
# with nothing pending sends nothing.
#
# Usage:
#   mc-wake.sh target add --program <p> <worker> [--mod]
#   mc-wake.sh target remove --program <p> <worker>
#   mc-wake.sh target list --program <p>       <worker><TAB>mod|no-mod
#   mc-wake.sh relay --program <p>
#       push each target's unsent events: one line per target,
#         submitted|staged<TAB><worker><TAB><n>
#         mod<TAB><worker>                     the mod wakes it
#         idle<TAB><worker>                    nothing to send
#         unreachable<TAB><worker><TAB><why>
#         refused<TAB><worker><TAB><exit>      the relay declined (a dialog
#                                              open, an earlier wake staged)
#       or `paused` under the fleet daemon pause.
#   mc-wake.sh tick --program <p> [--now <epoch>]
#       `not-due<TAB><seconds left>` before the cadence has passed; else the
#       relay's lines over every event not yet submitted, `tick` first.
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
mc_valid_program "$program" || mc_usage_fail "invalid program name '$(sanitize_printable "$program")'"
if [ -n "$now" ]; then
  mc_valid_uint "$now" || mc_usage_fail "--now takes an epoch"
else
  now=$(mc_now)
fi
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
targets="$runtime/wake-targets"

event() { /bin/bash "$script_dir/mc-event.sh" "$@"; }

# registry_row <worker>: the worker's last registry record, empty when none.
registry_row() {
  /bin/sh "$script_dir/fleet-state.sh" registry 2>/dev/null \
    | W=$1 awk -F '\t' '$2 == ENVIRON["W"] { r = $0 } END { print r }'
}

# send <worker> <all>: deliver one wake for the worker's unsent events
# (<all> 1: every event not submitted; 0: only those with no mark).
send() {
  sd_w=$1
  sd_rows=$(event list --program "$program" --target "$sd_w" --pending) || return 1
  [ "$2" -eq 1 ] || sd_rows=$(printf '%s\n' "$sd_rows" | awk -F '\t' '$NF == "-"')
  sd_n=$(printf '%s' "$sd_rows" | awk 'NF { n++ } END { print n + 0 }')
  if [ "$sd_n" -eq 0 ]; then
    printf 'idle\t%s\n' "$sd_w"
    return 0
  fi
  sd_row=$(registry_row "$sd_w")
  if [ -z "$sd_row" ]; then
    printf 'unreachable\t%s\tnot in the fleet registry\n' "$sd_w"
    return 0
  fi
  sd_backend=$(printf '%s' "$sd_row" | cut -f5)
  if [ "$(printf '%s' "$sd_row" | cut -f8)" = closed ]; then
    printf 'unreachable\t%s\tretired\n' "$sd_w"
    return 0
  fi
  mkdir -p "$runtime/wake" || return 1
  sd_msg="$runtime/wake/$sd_w.msg"
  {
    printf 'mission control (%s): %s event(s) pending.\n' "$program" "$sd_n"
    printf '%s\n' "$sd_rows" | awk -F '\t' 'NF { print "- " $3 " " $4 (($5 == "") ? "" : ": " $5) }'
    printf 'Read them with: %s list --program %s --target %s --pending\n' \
      "$script_dir/mc-event.sh" "$program" "$sd_w"
  } | mc_write "$sd_msg" || return 1
  case $sd_backend in
    stream-json | stream-json-persistent)
      /bin/sh "$script_dir/fleet-streamjson.sh" steer "$sd_w" --message-file "$sd_msg" >/dev/null 2>&1
      sd_rc=$?
      sd_mark=submitted
      ;;
    tmux)
      sd_handle=$(printf '%s' "$sd_row" | cut -f7)
      case $sd_handle in
        "tmux-window "*" "*)
          sd_handle=${sd_handle#tmux-window }
          sd_handle="${sd_handle%% *}:${sd_handle#* }"
          ;;
        *)
          printf 'unreachable\t%s\tno tmux window recorded\n' "$sd_w"
          return 0
          ;;
      esac
      /bin/sh "$script_dir/orchestrate-relay.sh" deliver tmux "$sd_handle" "$sd_msg" >/dev/null 2>&1
      sd_rc=$?
      sd_mark=staged
      ;;
    *)
      printf 'unreachable\t%s\tbackend %s has no session relay\n' "$sd_w" "$(sanitize_printable "$sd_backend" -)"
      return 0
      ;;
  esac
  if [ "$sd_rc" -ne 0 ]; then
    printf 'refused\t%s\t%s\n' "$sd_w" "$sd_rc"
    return 0
  fi
  printf '%s\n' "$sd_rows" | while IFS='	' read -r sd_id _; do
    [ -n "$sd_id" ] || continue
    event mark --program "$program" --target "$sd_w" "$sd_id" "$sd_mark" || exit 1
  done || return 1
  printf '%s\t%s\t%s\n' "$sd_mark" "$sd_w" "$sd_n"
}

# each <all>: send to every target without the mod.
each() {
  [ -f "$targets" ] || return 0
  while IFS='	' read -r ea_w ea_mod; do
    mc_valid_handle "$ea_w" || continue
    if [ "$ea_mod" = mod ]; then
      printf 'mod\t%s\n' "$ea_w"
      continue
    fi
    send "$ea_w" "$1" || mc_fail "cannot read or mark the events for '$ea_w'"
  done <"$targets"
}

gated() {
  if ! /bin/sh "$script_dir/fleet-daemon-gate.sh" mc-wake >/dev/null 2>&1; then
    printf 'paused\n'
    exit 0
  fi
}

case $verb in
  target)
    case $sub in
      add | remove)
        [ "${#args[@]}" -eq 1 ] || usage
        w=${args[0]}
        mc_valid_handle "$w" || mc_usage_fail "invalid worker '$(sanitize_printable "$w")'"
        [ "$sub" = add ] || [ "$mod" -eq 0 ] || usage
        mc_lock || mc_fail "cannot take the fleet lock"
        trap 'mc_unlock' EXIT
        {
          [ ! -f "$targets" ] || W=$w awk -F '\t' '$1 != ENVIRON["W"]' "$targets"
          if [ "$sub" = add ]; then
            if [ "$mod" -eq 1 ]; then printf '%s\tmod\n' "$w"; else printf '%s\tno-mod\n' "$w"; fi
          fi
        } | mc_write "$targets" || mc_fail "cannot write the wake targets"
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
    gated
    each 0
    ;;
  tick)
    [ "${#args[@]}" -eq 0 ] || usage
    gated
    cadence=$(mc_knob mission_control_tick_cadence mc_is_cadence) || exit 1
    secs=$(mc_seconds "$cadence")
    last=0
    if [ -f "$runtime/last-tick" ]; then
      last=$(head -n 1 "$runtime/last-tick")
      mc_valid_uint "$last" || last=0
    fi
    if [ $((now - last)) -lt "$secs" ]; then
      printf 'not-due\t%s\n' $((secs - (now - last)))
      exit 0
    fi
    printf '%s\n' "$now" | mc_write "$runtime/last-tick" || mc_fail "cannot record the tick"
    printf 'tick\n'
    each 1
    ;;
  *) usage ;;
esac
