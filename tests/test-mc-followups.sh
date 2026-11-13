#!/bin/bash
# Tests for scripts/mc-followups.sh — the runner pass's due check: a
# follow-up due by date or by an event the store has seen raises one
# followup-due event, a not-due item raises none, and a later pass does not
# raise one twice (mission-control REQ-F1.10: due items are started, not
# remembered).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-followups.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-followups.sh" ] || {
  echo "FAIL: scripts/mc-followups.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-followups.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-autonomy-fixture.sh
. "$here/lib/mc-autonomy-fixture.sh"

tab=$(printf '\t')
# 2026-11-10T12:00:00Z
today=1794312000
raise() { mc_run mc-followups.sh raise --program alpha --now "$today"; }
# due_count: how many followup-due events the store holds.
due_count() {
  mc_run mc-event.sh list --program alpha
  printf '%s\n' "$OUT" | awk -F '\t' '$3 == "followup-due" { n++ } END { print n + 0 }'
}
expect_due_count() { # expect_due_count <label> <want>
  dc=$(due_count)
  if [ "$dc" = "$2" ]; then ok "$1"; else fail "$1: expected $2 followup-due events, got $dc"; fi
}

mc_run mc-kb.sh followup add --program alpha --owner mission-control --trigger date:2026-11-09 --done operator --text "answer the overdue ask"
due_id=$OUT
mc_run mc-kb.sh followup add --program alpha --owner mission-control --trigger date:2026-12-01 --done operator --text "later duty"
later_id=$OUT
mc_run mc-kb.sh followup add --program alpha --owner mission-control --trigger event:merge-ready --done operator --text "start the landed follow-up"
event_id=$OUT

raise
expect_rc "a pass with a due date item" 0
expect_out "the due date item is raised" "raised${tab}$due_id"
expect_no_out "a not-due date item is not raised" "$later_id"
expect_no_out "an event item whose event has not been seen is not raised" "$event_id"
expect_due_count "exactly one event for the due item" 1
mc_run mc-event.sh list --program alpha
expect_out "the event names the follow-up" "followup-due${tab}$due_id${tab}"
expect_out "the text carries the ask" "answer the overdue ask"

mc_run mc-event.sh emit --program alpha --now "$today" -- merge-ready pr-1
raise
expect_out "a matched event item is raised" "raised${tab}$event_id"
expect_no_out "the already raised date item is not raised again" "raised${tab}$due_id"
expect_due_count "one event per due item" 2

raise
expect_eq "a later pass raises nothing" ""
expect_due_count "no duplicate after a second pass" 2

mc_run mc-event.sh prune --program alpha --kind followup-due --older-than 1s --now $((today + 100))
expect_due_count "the fixture pruned the raised events" 0
mc_run mc-kb.sh followup close --program alpha "$event_id" --evidence "started"
raise
expect_eq "an open item whose event was pruned is not raised again" ""

mc_run mc-kb.sh followup add --program alpha --owner mission-control --trigger date:2026-11-10 --done operator --text "due today"
today_id=$OUT
raise
expect_out "a new item due today is raised" "raised${tab}$today_id"

if grep -q 'mc-followups.sh' "$repo_root/scripts/mc-watch.sh"; then
  ok "the runner pass runs the due check"
else
  fail "scripts/mc-watch.sh does not call mc-followups.sh"
fi
if grep -q '^followup-due' "$repo_root/config/mc-event-classes.tsv"; then
  ok "the event kind has a class"
else
  fail "followup-due has no row in config/mc-event-classes.tsv"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-followups tests passed"
