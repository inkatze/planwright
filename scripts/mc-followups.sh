#!/usr/bin/env bash
# mc-followups.sh — the runner pass's due check: every open follow-up in the
# program's ledger whose date has come, or whose event the attention store
# has seen, is raised as one `followup-due` event, so a due promise, deferral
# or open question wakes a turn that starts it instead of waiting to be
# remembered.
#
# `mc-followups.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-followups
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

EVENT_TEXT_MAX=300

usage() {
  mc_usage_fail "usage: mc-followups.sh raise --program <p> [--now <epoch>]"
}

help_text() {
  cat <<'HELP'
mc-followups.sh — the runner pass's due check: every open follow-up in the
program's ledger (scripts/mc-kb.sh followup) that is due is raised as one
`followup-due` event, so it is started, not remembered.

Usage:
  mc-followups.sh raise --program <p> [--now <epoch>]
      ask the ledger what is due (`mc-kb.sh followup due`) for the UTC day
      of now and every event kind the program's attention store holds, and
      emit one followup-due event per due item, its subject the item's id
      and its text the owner, the trigger and the ask. Prints
      raised<TAB><follow-up id><TAB><event id> per event. An item already
      raised is not raised again while it stays open: its id is kept in
      <runtime>/followups-raised, so pruning the event does not raise it
      afresh. Closing the item (mc-kb.sh followup close) is the act that
      ends it. A program with no ledger yet raises nothing.

Exit codes: 0 done; 1 the ledger, the event store or the record cannot be
read or written; 2 usage; 3 the program is not configured.

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
[ "$verb" = raise ] || usage
program=""
now=""
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
    *) usage ;;
  esac
done
[ -n "$program" ] || usage
mc_now_arg "$now"
mc_require_program "$program"
now_args=()
[ -z "$now" ] || now_args=(--now "$now")

home=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home) || mc_fail "the home of program $program does not resolve"
[ -f "$home/kb/followups.tsv" ] || exit 0
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
raised="$runtime/followups-raised"
[ ! -e "$raised" ] || [ -f "$raised" ] || mc_fail "$raised is not a regular file"

day=$(mc_iso "$NOW") || mc_fail "cannot read the date of now"
day=${day%%T*}

# The event kinds the store holds are the events the pass has seen; the
# followup-due events this script wrote are left out, so an item never
# triggers itself.
events=$(mc_event list --program "$program" --limit 500 2>/dev/null) || mc_fail "cannot read the event store"
event_args=()
for kind in $(printf '%s\n' "$events" | awk -F '\t' '$3 != "followup-due" && $3 != "" { print $3 }' | sort -u); do
  event_args+=(--event "$kind")
done

due=$(mc_kb followup due --program "$program" --date "$day" ${event_args[@]+"${event_args[@]}"}) \
  || mc_fail "cannot read the follow-up ledger"
[ -n "$due" ] || exit 0

seen=""
if [ -f "$raised" ]; then seen=$(cat "$raised") || mc_fail "cannot read $raised"; fi
status=0
while IFS='	' read -r id _ owner trigger _ text _; do
  [ -n "$id" ] || continue
  case "
$seen
" in
    *"
$id
"*) continue ;;
  esac
  text=$(sanitize_printable "$text")
  text=$(printf '%s' "$text" | cut -c "1-$EVENT_TEXT_MAX")
  ev=$(mc_event emit --program "$program" ${now_args[@]+"${now_args[@]}"} -- \
    followup-due "$id" "$owner, trigger $trigger: $text") || {
    status=1
    continue
  }
  # Recorded after the event lands, so a failed write repeats the event on
  # the next pass instead of losing the alert.
  if ! printf '%s\n' "${seen:+$seen
}$id" | mc_write "$raised"; then
    printf '%s\n' "$prog: cannot record $id as raised" >&2
    status=1
  fi
  seen="${seen:+$seen
}$id"
  printf 'raised\t%s\t%s\n' "$id" "$ev"
done <<EOF
$due
EOF
exit "$status"
