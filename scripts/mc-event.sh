#!/usr/bin/env bash
# mc-event.sh — a mission-control program's events, kept in the attention
# store at <fleet-home>/attention/mission-control/<program>/.
#
# `mc-event.sh --help` prints the contract: verbs, outputs, exit codes.
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
  mc_usage_fail "usage: mc-event.sh emit --program <p> [--now <epoch>] [--] <kind> <subject> [<text>] | list --program <p> [--target <t> [--pending]] [--limit <n>] [<id>...] | mark --program <p> --target <t> submitted|staged <id>... | prune --program <p> [--now <epoch>] [--kind <k>] [--older-than <dur>] [--target <t> --submitted] [--dry-run]"
}

# valid_id <id>: e<epoch>.<hex>, the epoch a whole number and the suffix a
# nonempty run of lowercase hex digits.
valid_id() {
  case $1 in
    e*.*) ;;
    *) return 1 ;;
  esac
  vi_rest=${1#e}
  vi_epoch=${vi_rest%%.*}
  vi_hex=${vi_rest#*.}
  mc_valid_uint "$vi_epoch" || return 1
  case $vi_hex in
    "" | *[!0-9a-f]*) return 1 ;;
  esac
}

help_text() {
  cat <<'HELP'
mc-event.sh — a mission-control program's events, kept in the attention
store at <fleet-home>/attention/mission-control/<program>/.

An event is one immutable file under events/, named by its id
(e<epoch>.<hex>), holding one line:
  <epoch><TAB><kind><TAB><subject><TAB><text>
Delivery to a wake target is recorded beside it, never in it: a mark file
marks/<target>/<id> holding submitted or staged.

Usage:
  mc-event.sh emit --program <p> [--now <epoch>] [--] <kind> <subject> [<text>]
      record an event and print its id. <kind> is kebab, at most 64
      characters; <subject> is the
      fleet field grammar (letters, digits, . _ = @ : -), at most 128
      characters; <text> carries no C0 or DEL byte and is at most 512
      bytes. A byte in the C1 range is accepted, since UTF-8 text uses it,
      but every reader drops it on the way to a terminal, so such text
      reads back mangled.
  mc-event.sh list --program <p> [--target <t> [--pending]] [--limit <n>] [<id>...]
      one <id><TAB><epoch><TAB><kind><TAB><subject><TAB><text> line per
      event (only the named ones, when ids are given), in id order, which
      is emission order to the second (events of one second in no set
      order); with --target a sixth field, the target's mark or -;
      --pending keeps only events the target has not been submitted. At
      most --limit events are printed (500 by default), the oldest first;
      when more match, stderr says how many were printed of how many. An
      event whose stored fields break the grammar emit enforces, or whose
      file is a symbolic link, is skipped with a warning on stderr.
  mc-event.sh mark --program <p> --target <t> submitted|staged <id>...
      record a delivery of each event. A submitted mark is final: staging
      never overwrites it. Every id is checked before any is marked; one
      that names no event (pruned since, say) is skipped and named on
      stderr, and the call exits 3 after marking the rest.
  mc-event.sh prune --program <p> [--now <epoch>]
      drop events, and their marks, older than
      mission_control_event_retention; prints `pruned<TAB><n>`.
  mc-event.sh prune --program <p> [--kind <k>] [--older-than <dur>]
      [--target <t> --submitted] [--dry-run] [--now <epoch>]
      drop the events matching every filter given (their kind, older than a
      duration such as 1h, or submitted by the target and by every target
      that holds marks for the store, so no target loses an event it has not
      received), and their marks;
      prints `pruned<TAB><n>`, or `would-prune<TAB><n>` with --dry-run,
      which removes nothing. A filter is required with --dry-run.

Exit codes: 0 done; 1 the store cannot be read or written, or an invalid
retention knob; 2 usage or a value outside its grammar; 3 an id that names
no event (mark).

Portable bash 3.2 / BSD tooling.
HELP
}
case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
target=""
pending=0
now=""
limit=500
kind=""
have_kind=0
older=""
have_older=0
submitted_only=0
dry=0
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now | --limit | --kind | --older-than)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --target) target=$2 ;;
        --now) now=$2 ;;
        --limit) limit=$2 ;;
        --kind) kind=$2; have_kind=1 ;;
        --older-than) older=$2; have_older=1 ;;
      esac
      shift 2
      ;;
    --pending)
      pending=1
      shift
      ;;
    --submitted)
      submitted_only=1
      shift
      ;;
    --dry-run)
      dry=1
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
if [ -L "$store" ] || [ -L "$store/events" ] || [ -L "$store/marks" ]; then
  mc_fail "the event store for '$program' is reached through a symbolic link"
fi
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
    mc_valid_kebab "$kind" && [ "${#kind}" -le 64 ] || mc_usage_fail "invalid event kind '$(sanitize_printable "$kind")'"
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
    mc_valid_uint "$limit" && [ "$limit" -gt 0 ] || mc_usage_fail "--limit takes a count of at least one"
    shown=0
    total=0
    only=" "
    for id in ${args[@]+"${args[@]}"}; do
      valid_id "$id" || mc_usage_fail "invalid event id '$(sanitize_printable "$id")'"
      only="$only$id "
    done
    set +f
    for f in "$store/events"/e*; do
      [ -f "$f" ] || [ -L "$f" ] || continue
      id=${f##*/}
      valid_id "$id" || continue
      [ "$only" = " " ] || case $only in *" $id "*) ;; *) continue ;; esac
      # A dangling link is named too, not passed over in silence.
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
      if ! mc_valid_uint "$ev_at" || ! mc_valid_kebab "$ev_kind" || [ "${#ev_kind}" -gt 64 ] || ! mc_valid_handle "$ev_subject" \
        || [ "${#ev_text}" -gt 512 ] || ! mc_valid_text "$ev_text"; then
        printf '%s\n' "$prog: skipping $id: its stored fields break the event grammar" >&2
        continue
      fi
      total=$((total + 1))
      [ "$shown" -lt "$limit" ] || continue
      line="$ev_at	$ev_kind	$ev_subject	$(sanitize_printable "$ev_text")"
      if [ -n "$target" ]; then
        printf '%s\t%s\t%s\n' "$id" "$line" "$(sanitize_printable "$mark" -)"
      else
        printf '%s\t%s\n' "$id" "$line"
      fi
      shown=$((shown + 1))
    done
    set -f
    [ "$total" -le "$shown" ] || printf '%s\n' "$prog: listed the first $shown of $total events (--limit $limit); prune the store or raise --limit" >&2
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
    if [ "$have_kind" -eq 1 ] || [ "$have_older" -eq 1 ] || [ "$submitted_only" -eq 1 ]; then
      # A filtered prune: the events matching every filter given, and their
      # marks. --dry-run counts them and removes nothing.
      [ "$have_kind" -eq 0 ] || { [ -n "$kind" ] && mc_valid_kebab "$kind"; } || mc_usage_fail "invalid event kind '$(sanitize_printable "$kind")'"
      [ "$submitted_only" -eq 0 ] || [ -n "$target" ] || mc_usage_fail "--submitted takes --target"
      cutoff=""
      if [ "$have_older" -eq 1 ]; then
        older_secs=$(mc_seconds "$older") || mc_usage_fail "--older-than takes a duration such as 30m or 7d"
        cutoff=$((NOW - older_secs))
      fi
      n=0
      set +f
      for f in "$store/events"/e*; do
        [ -f "$f" ] || continue
        id=${f##*/}
        valid_id "$id" || continue
        at=${id#e}
        at=${at%%.*}
        mc_valid_uint "$at" || continue
        [ -z "$cutoff" ] || [ "$at" -lt "$cutoff" ] || continue
        if [ -n "$kind" ]; then
          IFS="	" read -r ev_at ev_kind _ <"$f" || continue
          [ "$ev_kind" = "$kind" ] || continue
        fi
        if [ "$submitted_only" -eq 1 ]; then
          # Submitted by the named target, and by every target that holds
          # marks for the store, so no target loses an event it has not
          # received.
          t_mk=-
          if [ -f "$store/marks/$target/$id" ]; then
            IFS= read -r t_mk <"$store/marks/$target/$id" || t_mk=-
          fi
          [ "$t_mk" = submitted ] || continue
          all_mk=1
          for md in "$store/marks"/*; do
            [ -d "$md" ] && [ ! -L "$md" ] || continue
            mk=-
            if [ -f "$md/$id" ]; then
              IFS= read -r mk <"$md/$id" || mk=-
            fi
            [ "$mk" = submitted ] || all_mk=0
          done
          [ "$all_mk" -eq 1 ] || continue
        fi
        if [ "$dry" -eq 0 ]; then
          rm -f "$f" || mc_fail "cannot prune $id"
          for md in "$store/marks"/*; do
            [ -d "$md" ] && [ ! -L "$md" ] || continue
            rm -f "$md/$id" || mc_fail "cannot prune the marks of $id"
          done
        fi
        n=$((n + 1))
      done
      set -f
      if [ "$dry" -eq 1 ]; then
        printf 'would-prune\t%s\n' "$n"
      else
        printf 'pruned\t%s\n' "$n"
      fi
      exit 0
    fi
    [ "$dry" -eq 0 ] || mc_usage_fail "--dry-run takes a filter (--kind, --older-than or --submitted)"
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
