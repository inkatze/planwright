#!/bin/bash
# Tests for scripts/mc-deadlines.sh — dates from the record and snapshot
# stores and the operator's stated dates driving priority and the first turn
# after silence, with no calendar read (mission-control D-27).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-deadlines.sh
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

tmp=$(mktemp -d) || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
program() { # program <sources map>
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $mchome
program_alpha_sources: $1
EOF
}
program '{deadlines: specs:record}'
mkdir -p "$repo/specs/billing" "$repo/specs/_observations"
cat >"$repo/specs/billing/tasks.md" <<'EOF'
# Billing — Tasks

## Tasks

### Task 1 — Invoices

- **Deliverables:** x
- **Due:** 2026-11-03

### Task 2 — Refunds

- **Deliverables:** y

### Notes on task 2

- **Due:** 2026-11-05

### Task 3 — Credits

- **Due:** 2026-02-31
EOF
printf '%s\n' '# Billing — Requirements' '' '- **Due:** 2026-12-01' >"$repo/specs/billing/requirements.md"
printf '%s\n' '### Task 1 — Ignored' '- **Due:** 2026-10-01' >"$repo/specs/_observations/tasks.md"
# 2026-11-01T12:00:00Z
NOW=1793534400

# ---------------------------------------------------------------------------
# Day-one sources: the record store's dates and the operator's.
# ---------------------------------------------------------------------------
mc_run mc-deadlines.sh list --program alpha --now "$NOW"
expect_rc "list" 0
expect_out "a task block's due line dates its unit" "deadline${tab}billing:task-1${tab}2026-11-03${tab}2${tab}record:specs"
expect_out "a requirements due line dates the bundle" "deadline${tab}billing${tab}2026-12-01${tab}30${tab}record:specs"
expect_no_out "a reserved directory is not a bundle" "2026-10-01"
expect_no_out "a due line under a later H3 is not the task's" "2026-11-05"
expect_no_out "a stored date naming no calendar day is dropped" "billing:task-3"

mc_run mc-deadlines.sh add --program alpha --unit "billing:task-2" --due 2026-10-30 --note "the operator said so"
expect_rc "an operator-stated date is recorded" 0
mc_run mc-deadlines.sh add --program alpha --unit "billing:task-1" --due 2026-11-20
mc_run mc-deadlines.sh list --program alpha --now "$NOW"
expect_out "the operator's date is listed" "deadline${tab}billing:task-2${tab}2026-10-30${tab}-2${tab}operator"
expect_out "and wins over the store's for the same unit" "deadline${tab}billing:task-1${tab}2026-11-20${tab}19${tab}operator"
expect_no_out "the store's date for that unit is dropped" "billing:task-1${tab}2026-11-03"
first=$(printf '%s\n' "$OUT" | head -n 1 | cut -f2)
if [ "$first" = billing:task-2 ]; then ok "earliest first"; else fail "list is not earliest first: $first"; fi
mc_run mc-deadlines.sh add --program alpha --unit x --due 2026-13-01
expect_rc "an invalid month is refused" 2
mc_run mc-deadlines.sh add --program alpha --unit x --due 2026-02-29
expect_rc "a day past its month's end is refused" 2
mc_run mc-deadlines.sh add --program alpha --unit x --due 2028-02-29
expect_rc "a leap day is a day" 0
mc_run mc-deadlines.sh add --program alpha --unit "Q4 launch" --due 2026-11-30
expect_rc "a unit outside the subject grammar is refused" 2
if [ "$(head -n 1 "$mchome/kb/deadline-watch/dates.tsv")" = "# format: 1" ]; then ok "the store carries its format"; else fail "no format line"; fi

# ---------------------------------------------------------------------------
# A fixture deadline raises its unit's priority.
# ---------------------------------------------------------------------------
mc_run mc-deadlines.sh add --program alpha --unit "billing:task-1" --due 2026-11-03
mc_run mc-deadlines.sh rank --program alpha --now "$NOW" "other:task-9" "billing:task-1" "billing" "billing:task-2"
expect_rc "rank" 0
expect_eq "the dated units rise: overdue, then urgent, then the rest in the given order" \
  "rank${tab}1${tab}billing:task-2${tab}overdue${tab}2026-10-30
rank${tab}2${tab}billing:task-1${tab}urgent${tab}2026-11-03
rank${tab}3${tab}other:task-9${tab}none${tab}-
rank${tab}4${tab}billing${tab}dated${tab}2026-12-01"

mc_run mc-deadlines.sh due --program alpha --now "$NOW"
expect_out "the first turn after silence opens with the urgent unit" "billing:task-1"
expect_out "and the overdue one" "billing:task-2"
expect_no_out "not a far date" "2026-12-01"

printf 'mission_control_deadline_horizon: 40d\n' >>"$tracked"
mc_run mc-deadlines.sh rank --program alpha --now "$NOW" billing
expect_out "the horizon is a knob" "rank${tab}1${tab}billing${tab}urgent${tab}2026-12-01"
program '{deadlines: specs:record}'
printf 'mission_control_deadline_horizon: soon\n' >>"$tracked"
mc_run mc-deadlines.sh rank --program alpha --now "$NOW" billing
expect_rc "an invalid repo-tracked horizon fails rank" 1
for v in due watch; do
  mc_run mc-deadlines.sh "$v" --program alpha --now "$NOW"
  expect_rc "an invalid repo-tracked horizon fails $v" 1
done
program '{deadlines: specs:record}'

# ---------------------------------------------------------------------------
# watch: one event per urgent unit per day.
# ---------------------------------------------------------------------------
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-deadlines.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher runs with no arguments under the runner" 0
mc_run mc-deadlines.sh watch --program alpha --now "$NOW"
expect_rc "watch" 0
expect_out "an urgent unit is announced" "announced${tab}deadline-near${tab}billing:task-1"
mc_run mc-event.sh list --program alpha
expect_out "the event lands in the store" "deadline-near${tab}billing:task-1${tab}billing:task-1 due 2026-11-03 (2 days, operator)"
mc_run mc-deadlines.sh watch --program alpha --now $((NOW + 3600))
expect_rc "a second pass" 0
expect_eq "not twice the same day" ""
mc_run mc-deadlines.sh watch --program alpha --now $((NOW + 86400))
expect_out "again the next day" "announced${tab}deadline-near${tab}billing:task-1"

# ---------------------------------------------------------------------------
# The other modes: a snapshot store's due lines; cited reads nothing.
# ---------------------------------------------------------------------------
program '{deadlines: tracker:snapshot}'
printf '%s\n' 'adapters:' '  - id: tracker' '    summary: "A fixture tracker"' '    script: scripts/tracker-adapter.sh' \
  '    cadence: 10m' >"$repo/.claude/catalogs/snapshot-adapters.yaml"
mkdir -p "$fleet/mission-control/alpha/snapshots"
printf 'format\t1\nsource\ttracker\ntaken\t%s\ndue\tPROJ-12\t2026-11-02\ndue\tQ4 launch\t2026-11-02\n' "$NOW" >"$fleet/mission-control/alpha/snapshots/tracker"
mc_run mc-deadlines.sh list --program alpha --now "$NOW"
expect_out "a snapshot store's dates are read" "deadline${tab}PROJ-12${tab}2026-11-02${tab}1${tab}snapshot:tracker"
mc_run mc-deadlines.sh watch --program alpha --now "$NOW"
expect_rc "a store's unit outside the subject grammar still raises its event" 0
expect_out "under a checksum subject" "announced${tab}deadline-near${tab}deadline-"
mc_run mc-event.sh list --program alpha
expect_out "the unit itself in the text" "Q4 launch due 2026-11-02"
expect_no_out "the record store is not, in snapshot mode" "record:specs"
program '{deadlines: calendar:cited}'
mc_run mc-deadlines.sh list --program alpha --now "$NOW"
expect_no_out "a cited source is never read" "PROJ-12"
expect_out "the operator's dates still are" "operator"

printf 'garbage\n' >"$mchome/kb/deadline-watch/dates.tsv"
mc_run mc-deadlines.sh list --program alpha --now "$NOW"
expect_rc "a store with an unknown format is refused" 1
expect_err "named" "unknown format"
mc_run mc-deadlines.sh due --program alpha --now "$NOW"
expect_rc "and due fails rather than report nothing due" 1
mc_run mc-deadlines.sh watch --program alpha --now "$NOW"
expect_rc "and so does the watcher" 1

if [ "$failures" -ne 0 ]; then
  echo "test-mc-deadlines: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-deadlines: all passed"
