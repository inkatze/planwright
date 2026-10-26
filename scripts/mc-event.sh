#!/usr/bin/env bash
# mc-event.sh — a mission-control program's events, kept in the attention
# store at <fleet-home>/attention/mission-control/<program>/.
#
# An event is one immutable file under events/, named by its id
# (e<epoch>.<hex>, so ids sort by time), holding one line:
#   <epoch><TAB><kind><TAB><subject><TAB><text>
# Delivery to a wake target is recorded beside it, never in it: a mark file
# marks/<target>/<id> holding submitted or staged.
#
# Usage:
#   mc-event.sh emit --program <p> <kind> <subject> [<text>]
#       record an event and print its id. <kind> is kebab; <subject> is the
#       fleet field grammar (letters, digits, . _ = @ : -), at most 128
#       characters; <text> is printable, at most 512 bytes, tabs refused.
#   mc-event.sh list --program <p> [--target <t> [--pending]]
#       one <id><TAB><epoch><TAB><kind><TAB><subject><TAB><text> line per
#       event, oldest first; with --target a sixth field, the target's mark
#       or -; --pending keeps only events the target has not been submitted.
#   mc-event.sh mark --program <p> --target <t> <id> submitted|staged
#       record a delivery. A submitted mark is final: staging never
#       overwrites it.
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
  mc_usage_fail "usage: mc-event.sh emit --program <p> <kind> <subject> [<text>] | list --program <p> [--target <t> [--pending]] | mark --program <p> --target <t> <id> submitted|staged"
}

valid_text() {
  [ "${#1}" -le 512 ] || return 1
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
  esac
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
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program)
      [ $# -ge 2 ] || usage
      program=$2
      shift 2
      ;;
    --target)
      [ $# -ge 2 ] || usage
      target=$2
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
home=$(mc_events_home "$program") || mc_fail "cannot create the event store for '$program'"

case $verb in
  emit)
    [ "${#args[@]}" -ge 2 ] && [ "${#args[@]}" -le 3 ] || usage
    kind=${args[0]}
    subject=${args[1]}
    text=${args[2]:-}
    mc_valid_kebab "$kind" || mc_usage_fail "invalid event kind '$(sanitize_printable "$kind")'"
    mc_valid_handle "$subject" || mc_usage_fail "invalid event subject '$(sanitize_printable "$subject")'"
    valid_text "$text" || mc_usage_fail "event text carries a control character or is over 512 bytes"
    now=$(mc_now)
    hex=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ -n "$hex" ] || hex=$$
    id="e$now.$hex"
    printf '%s\t%s\t%s\t%s\n' "$now" "$kind" "$subject" "$text" \
      | mc_write "$home/events/$id" || mc_fail "cannot write event $id"
    printf '%s\n' "$id"
    ;;
  list)
    [ "${#args[@]}" -eq 0 ] || usage
    [ "$pending" -eq 0 ] || [ -n "$target" ] || usage
    set +f
    for f in "$home/events"/e*; do
      [ -f "$f" ] || continue
      id=${f##*/}
      valid_id "$id" || continue
      IFS='	' read -r ev_at ev_kind ev_subject ev_text <"$f" || continue
      # Every field was checked on write; the store is still a file anyone
      # running as the operator can edit, so each is cleaned on the way out.
      line="$(sanitize_printable "$ev_at")	$(sanitize_printable "$ev_kind")	$(sanitize_printable "$ev_subject")	$(sanitize_printable "$ev_text")"
      mark=-
      if [ -n "$target" ] && [ -f "$home/marks/$target/$id" ]; then
        IFS= read -r mark <"$home/marks/$target/$id" || mark=-
      fi
      if [ "$pending" -eq 1 ] && [ "$mark" = submitted ]; then
        continue
      fi
      if [ -n "$target" ]; then
        printf '%s\t%s\t%s\n' "$id" "$line" "$(sanitize_printable "$mark" -)"
      else
        printf '%s\t%s\n' "$id" "$line"
      fi
    done
    set -f
    ;;
  mark)
    [ -n "$target" ] && [ "${#args[@]}" -eq 2 ] || usage
    id=${args[0]}
    state=${args[1]}
    valid_id "$id" || mc_usage_fail "invalid event id '$(sanitize_printable "$id")'"
    case $state in
      submitted | staged) ;;
      *) usage ;;
    esac
    [ -f "$home/events/$id" ] || {
      printf '%s\n' "$prog: no event $id" >&2
      exit 3
    }
    mkdir -p "$home/marks/$target" || mc_fail "cannot create the marks for '$target'"
    if [ "$state" = staged ] && [ -f "$home/marks/$target/$id" ]; then
      IFS= read -r was <"$home/marks/$target/$id" || was=""
      [ "$was" != submitted ] || exit 0
    fi
    printf '%s\n' "$state" | mc_write "$home/marks/$target/$id" || mc_fail "cannot mark $id"
    ;;
  *) usage ;;
esac
