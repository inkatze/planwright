#!/usr/bin/env bash
# mc-event.sh — a mission-control program's events, kept in the attention
# store at <fleet-home>/attention/mission-control/<program>/.
#
# An event is one immutable file under events/, named by its id
# (e<epoch>.<hex>), holding one line:
#   <epoch><TAB><kind><TAB><subject><TAB><text>
# Delivery to a wake target is recorded beside it, never in it: a mark file
# marks/<target>/<id> holding submitted or staged.
#
# Usage:
#   mc-event.sh emit --program <p> [--] <kind> <subject> [<text>]
#       record an event and print its id. <kind> is kebab; <subject> is the
#       fleet field grammar (letters, digits, . _ = @ : -), at most 128
#       characters; <text> is printable (no control byte, C1 included), at
#       most 512 bytes.
#   mc-event.sh list --program <p> [--target <t> [--pending]]
#       one <id><TAB><epoch><TAB><kind><TAB><subject><TAB><text> line per
#       event, ordered by the second it was emitted (events of one second in
#       no set order); with --target a sixth field, the target's mark or -;
#       --pending keeps only events the target has not been submitted.
#   mc-event.sh mark --program <p> --target <t> submitted|staged <id>...
#       record a delivery of each event. A submitted mark is final: staging
#       never overwrites it.
#   mc-event.sh prune --program <p> [--now <epoch>]
#       drop events, and their marks, older than
#       mission_control_event_retention; prints `pruned<TAB><n>`.
#
# Exit codes: 0 done; 1 the store cannot be read or written; 2 usage or a
# value outside its grammar; 3 no such event (mark).
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-event
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
  mc_usage_fail "usage: mc-event.sh emit --program <p> [--] <kind> <subject> [<text>] | list --program <p> [--target <t> [--pending]] | mark --program <p> --target <t> submitted|staged <id>... | prune --program <p> [--now <epoch>]"
}

valid_id() {
  case $1 in
    e[0-9]*.*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9.]* | *.*.*) return 1 ;;
  esac
}

[ $# -ge 1 ] || usage
verb=$1
shift
program=""
target=""
pending=0
now=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --target) target=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    --pending)
      pending=1
      shift
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        args+=("$1")
        shift
      done
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
[ -n "$program" ] || usage
mc_valid_program "$program" || mc_usage_fail "invalid program name '$(sanitize_printable "$program")'"
if [ -n "$target" ]; then
  mc_valid_handle "$target" || mc_usage_fail "invalid target '$(sanitize_printable "$target")'"
fi
mc_now_arg "$now"
store=$(mc_event_store "$program") || mc_fail "cannot create the event store for '$program'"
[ -r "$store/events" ] && [ -x "$store/events" ] || mc_fail "cannot read the event store for '$program'"

case $verb in
  emit)
    [ "${#args[@]}" -ge 2 ] && [ "${#args[@]}" -le 3 ] || usage
    kind=${args[0]}
    subject=${args[1]}
    text=${args[2]:-}
    mc_valid_kebab "$kind" || mc_usage_fail "invalid event kind '$(sanitize_printable "$kind")'"
    mc_valid_handle "$subject" || mc_usage_fail "invalid event subject '$(sanitize_printable "$subject")'"
    if [ "${#text}" -gt 512 ] || ! mc_valid_text "$text"; then
      mc_usage_fail "event text carries a control character or is over 512 bytes"
    fi
    hex=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ -n "$hex" ] || hex=$$
    id="e$NOW.$hex"
    printf '%s\t%s\t%s\t%s\n' "$NOW" "$kind" "$subject" "$text" \
      | mc_write "$store/events/$id" || mc_fail "cannot write event $id"
    printf '%s\n' "$id"
    ;;
  list)
    [ "${#args[@]}" -eq 0 ] || usage
    [ "$pending" -eq 0 ] || [ -n "$target" ] || usage
    set +f
    for f in "$store/events"/e*; do
      [ -f "$f" ] || continue
      id=${f##*/}
      valid_id "$id" || continue
      mark=-
      if [ -n "$target" ] && [ -f "$store/marks/$target/$id" ]; then
        IFS= read -r mark <"$store/marks/$target/$id" || mark=-
      fi
      if [ "$pending" -eq 1 ] && [ "$mark" = submitted ]; then
        continue
      fi
      IFS='	' read -r ev_at ev_kind ev_subject ev_text <"$f" || continue
      # Every field was checked on write; the store is still a file anyone
      # running as the operator can edit, so each is cleaned on the way out.
      line="$(sanitize_printable "$ev_at")	$(sanitize_printable "$ev_kind")	$(sanitize_printable "$ev_subject")	$(sanitize_printable "$ev_text")"
      if [ -n "$target" ]; then
        printf '%s\t%s\t%s\n' "$id" "$line" "$(sanitize_printable "$mark" -)"
      else
        printf '%s\t%s\n' "$id" "$line"
      fi
    done
    set -f
    ;;
  mark)
    [ -n "$target" ] && [ "${#args[@]}" -ge 2 ] || usage
    state=${args[0]}
    case $state in
      submitted | staged) ;;
      *) usage ;;
    esac
    mkdir -p "$store/marks/$target" || mc_fail "cannot create the marks for '$target'"
    for id in "${args[@]:1}"; do
      valid_id "$id" || mc_usage_fail "invalid event id '$(sanitize_printable "$id")'"
      [ -f "$store/events/$id" ] || {
        printf '%s\n' "$prog: no event $id" >&2
        exit 3
      }
      if [ "$state" = submitted ]; then
        printf 'submitted\n' | mc_write "$store/marks/$target/$id" || mc_fail "cannot mark $id"
      elif [ ! -e "$store/marks/$target/$id" ]; then
        # Created only where no mark exists, so a staging that races a
        # submission never overwrites it.
        (
          set -C
          printf 'staged\n' >"$store/marks/$target/$id"
        ) 2>/dev/null || [ -e "$store/marks/$target/$id" ] || mc_fail "cannot mark $id"
      fi
    done
    ;;
  prune)
    [ "${#args[@]}" -eq 0 ] || usage
    retention=$(mc_knob mission_control_event_retention mc_parse_cadence) || exit 1
    cutoff=$((NOW - $(mc_seconds "$retention")))
    n=0
    set +f
    for f in "$store/events"/e*; do
      [ -f "$f" ] || continue
      id=${f##*/}
      valid_id "$id" || continue
      at=${id#e}
      at=${at%%.*}
      mc_valid_uint "$at" && [ "$at" -lt "$cutoff" ] || continue
      rm -f "$f" "$store/marks"/*/"$id" || mc_fail "cannot prune $id"
      n=$((n + 1))
    done
    set -f
    printf 'pruned\t%s\n' "$n"
    ;;
  *) usage ;;
esac
