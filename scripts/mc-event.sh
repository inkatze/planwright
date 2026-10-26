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
#   mc-event.sh emit --program <p> [--now <epoch>] [--] <kind> <subject> [<text>]
#       record an event and print its id. <kind> is kebab; <subject> is the
#       fleet field grammar (letters, digits, . _ = @ : -), at most 128
#       characters; <text> carries no control byte and is at most 512 bytes.
#   mc-event.sh list --program <p> [--target <t> [--pending]] [<id>...]
#       one <id><TAB><epoch><TAB><kind><TAB><subject><TAB><text> line per
#       event (only the named ones, when ids are given), in id order, which
#       is emission order to the second (events of one second in no set
#       order); with --target a sixth field, the target's mark or -;
#       --pending keeps only events the target has not been submitted. An
#       event whose stored fields break the grammar emit enforces, or whose
#       file is a symbolic link, is skipped with a warning on stderr.
#   mc-event.sh mark --program <p> --target <t> submitted|staged <id>...
#       record a delivery of each event. A submitted mark is final: staging
#       never overwrites it. Every id is checked before any is marked; one
#       that names no event (pruned since, say) is skipped and named on
#       stderr, and the call exits 3 after marking the rest.
#   mc-event.sh prune --program <p> [--now <epoch>]
#       drop events, and their marks, older than
#       mission_control_event_retention; prints `pruned<TAB><n>`.
#
# Exit codes: 0 done; 1 the store cannot be read or written, or an invalid
# retention knob; 2 usage or a value outside its grammar; 3 an id that names
# no event (mark).
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
  mc_usage_fail "usage: mc-event.sh emit --program <p> [--now <epoch>] [--] <kind> <subject> [<text>] | list --program <p> [--target <t> [--pending]] [<id>...] | mark --program <p> --target <t> submitted|staged <id>... | prune --program <p> [--now <epoch>]"
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
if [ -n "$target" ] && [ -L "$store/marks/$target" ]; then
  mc_fail "the marks for '$target' are a symbolic link"
fi

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
    [ "$pending" -eq 0 ] || [ -n "$target" ] || usage
    only=" "
    for id in ${args[@]+"${args[@]}"}; do
      valid_id "$id" || mc_usage_fail "invalid event id '$(sanitize_printable "$id")'"
      only="$only$id "
    done
    set +f
    for f in "$store/events"/e*; do
      [ -f "$f" ] || continue
      id=${f##*/}
      valid_id "$id" || continue
      [ "$only" = " " ] || case $only in *" $id "*) ;; *) continue ;; esac
      if [ -L "$f" ]; then
        printf '%s\n' "$prog: skipping $id: a symbolic link" >&2
        continue
      fi
      mark=-
      if [ -n "$target" ] && [ -f "$store/marks/$target/$id" ]; then
        IFS= read -r mark <"$store/marks/$target/$id" || mark=-
      fi
      if [ "$pending" -eq 1 ] && [ "$mark" = submitted ]; then
        continue
      fi
      IFS='	' read -r ev_at ev_kind ev_subject ev_text <"$f" || [ -n "$ev_at" ] || continue
      # Every field was checked on write, but the store is a file anyone
      # running as the operator can edit, and a wake carries its kind and
      # subject into a session: each is checked again here.
      if ! mc_valid_uint "$ev_at" || ! mc_valid_kebab "$ev_kind" || ! mc_valid_handle "$ev_subject" \
        || [ "${#ev_text}" -gt 512 ] || ! mc_valid_text "$ev_text"; then
        printf '%s\n' "$prog: skipping $id: its stored fields break the event grammar" >&2
        continue
      fi
      line="$ev_at	$ev_kind	$ev_subject	$(sanitize_printable "$ev_text")"
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
    for id in "${args[@]:1}"; do
      valid_id "$id" || mc_usage_fail "invalid event id '$(sanitize_printable "$id")'"
    done
    mkdir -p "$store/marks/$target" || mc_fail "cannot create the marks for '$target'"
    missing=0
    for id in "${args[@]:1}"; do
      if [ ! -f "$store/events/$id" ]; then
        printf '%s\n' "$prog: no event $id" >&2
        missing=1
        continue
      fi
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
    [ "$missing" -eq 0 ] || exit 3
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
      rm -f "$f" || mc_fail "cannot prune $id"
      for md in "$store/marks"/*; do
        [ -d "$md" ] && [ ! -L "$md" ] || continue
        rm -f "$md/$id" || mc_fail "cannot prune the marks of $id"
      done
      n=$((n + 1))
    done
    set -f
    printf 'pruned\t%s\n' "$n"
    ;;
  *) usage ;;
esac
