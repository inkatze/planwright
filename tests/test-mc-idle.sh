#!/bin/bash
# Tests for scripts/mc-idle.sh — the idle-capacity duty: with a free worker
# slot, the usage and load gates open and a declared backlog holding a unit,
# it raises an event the holder acts on; it launches nothing itself.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-idle.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-idle.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

# The status-line mirror the usage windows are read from, pinned to the
# scratch tree so a real one on the host never leaks in.
mirror="$tmp/rate-limits.json"
export PLANWRIGHT_USAGE_MIRROR="$mirror"

now=$(date +%s)
write_mirror() { # write_mirror <session pct> <weekly pct>
  printf '{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}\n' \
    "$1" "$((now + 3600))" "$2" "$((now + 86400))" >"$mirror"
  TZ=UTC touch -t "$(date -u -d "@$now" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$now" +%Y%m%d%H%M.%S)" "$mirror"
}

reset_mc_fixture
{
  printf 'fleet_host_max_live_workers: 6\n'
  printf 'fleet_max_parallel_units: 3\n'
} >>"$core/config/defaults.yml"
cp "$repo_root/config/defaults.yml" "$tmp/shipped-defaults.yml"
grep -E '^mission_control_idle_' "$tmp/shipped-defaults.yml" >>"$core/config/defaults.yml"

backlog="$tmp/backlog.txt"
write_tracked() { # write_tracked [<extra line>]
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 100}
EOF
  [ -z "${1:-}" ] || printf '%s\n' "$1" >>"$tracked"
}

reg="$fleet/mission-control/sessions"
mkdir -p "$reg"
add_row() { # add_row <name> <program> <kind>
  {
    printf 'format\t1\nname\t%s\nstate\trunning\nprogram\t%s\nkind\t%s\nlaunched\t%s\n' "$1" "$2" "$3" "$now"
  } >"$reg/$1"
}
clear_rows() { rm -f "$reg"/mc-*; }
events() {
  mc_run mc-event.sh list --program alpha
  EV=$OUT
}
count_kind() { printf '%s\n' "$EV" | K=$1 awk -F '\t' '$3 == ENVIRON["K"] { n++ } END { print n + 0 }'; }
watch() { mc_run mc-idle.sh watch --program alpha --now "$1" --load "${2:-10}"; }

printf '# ranked, first is next\nalpha-unit-one\tthe first unit\nalpha-unit-two\nalpha-unit-three\n' >"$backlog"

# ---------------------------------------------------------------------------
# A free slot with a declared backlog raises the event naming the units.
# ---------------------------------------------------------------------------
write_tracked "program_alpha_idle_backlog: $backlog"
write_mirror 10 10
clear_rows
add_row mc-alpha-worker-aaaaaaaaaa alpha worker
add_row mc-alpha-mission-control-bbbbbbbbbb alpha mission-control
mc_run mc-usage.sh watch --program alpha --now "$now"
watch "$now"
if [ "$RC" -eq 0 ]; then ok "a free slot with backlog: exit 0"; else fail "a free slot with backlog: exit $RC: $ERR"; fi
events
case $EV in
  *"idle-capacity"*"alpha-unit-one"*"alpha-unit-two"*) ok "a free slot with backlog raises the event naming the ranked units" ;;
  *) fail "no idle-capacity event naming the units: $EV" ;;
esac
case $EV in
  *"alpha-unit-three"*) fail "the event names more units than there are free slots" ;;
  *) ok "the event names no more units than free slots (two of three)" ;;
esac

# The same state inside the re-raise interval raises nothing more.
watch $((now + 60))
events
if [ "$(count_kind idle-capacity)" -eq 1 ]; then ok "the same idle state inside the interval is not raised again"; else fail "raised twice inside the interval: $EV"; fi
# Still idle past the interval, it is raised again.
watch $((now + 7200))
events
if [ "$(count_kind idle-capacity)" -eq 2 ]; then ok "still idle past the interval, it is raised again"; else fail "not re-raised past the interval: $EV"; fi

# ---------------------------------------------------------------------------
# Nothing raised: no free slot (program cap, then host cap), no backlog,
# usage over its gate, load over its gate.
# ---------------------------------------------------------------------------
new_state() { # a clean event store and dedupe record between cases
  rm -rf "$fleet/attention" "$fleet/mission-control/alpha/idle-raised" "$fleet/mission-control/alpha/idle-undeclared"
}
expect_quiet() { # expect_quiet <label> <now> [<load>]
  new_state
  watch "$2" "${3:-10}"
  events
  if [ "$(count_kind idle-capacity)" -eq 0 ] && [ "$RC" -eq 0 ]; then ok "$1"; else fail "$1: rc=$RC events: $EV $ERR"; fi
}

clear_rows
add_row mc-alpha-worker-aaaaaaaaaa alpha worker
add_row mc-alpha-worker-bbbbbbbbbb alpha worker
add_row mc-alpha-worker-cccccccccc alpha worker
expect_quiet "no free slot under the program cap raises nothing" "$now"

clear_rows
add_row mc-alpha-worker-aaaaaaaaaa alpha worker
for i in 1 2 3 4 5; do add_row "mc-other-worker-$i" other worker; done
expect_quiet "no free slot under the host-wide bound raises nothing" "$now"

clear_rows
printf '# only a comment\n\n' >"$backlog"
expect_quiet "a declared backlog with no unit raises nothing" "$now"
printf 'alpha-unit-one\n' >"$backlog"

write_mirror 95 10
mc_run mc-usage.sh watch --program alpha --now "$now"
expect_quiet "usage over its gate raises nothing" "$now"
write_mirror 10 10
mc_run mc-usage.sh watch --program alpha --now $((now + 4000))

expect_quiet "load over its gate raises nothing" "$((now + 4000))" 99

# ---------------------------------------------------------------------------
# An undeclared backlog is reported once.
# ---------------------------------------------------------------------------
write_tracked
new_state
watch "$now"
events
if [ "$(count_kind idle-capacity-undeclared)" -eq 1 ] && [ "$(count_kind idle-capacity)" -eq 0 ]; then ok "an undeclared backlog is reported"; else fail "undeclared not reported once: $EV"; fi
watch $((now + 7200))
events
if [ "$(count_kind idle-capacity-undeclared)" -eq 1 ]; then ok "an undeclared backlog is reported once, not on every wake"; else fail "undeclared reported again: $EV"; fi

# A declared file that cannot be read says so instead of guessing.
write_tracked "program_alpha_idle_backlog: $tmp/missing.txt"
new_state
watch "$now"
events
if [ "$(count_kind idle-capacity-undeclared)" -eq 1 ]; then ok "an unreadable declared backlog is reported, not guessed"; else fail "unreadable backlog not reported: $EV"; fi

# An undeclared backlog is reported only when a slot is free and the gates
# are open: a full fleet or a closed usage gate raises nothing.
write_tracked
new_state
clear_rows
add_row mc-alpha-worker-aaaaaaaaaa alpha worker
add_row mc-alpha-worker-bbbbbbbbbb alpha worker
add_row mc-alpha-worker-cccccccccc alpha worker
watch "$now"
events
if [ "$(count_kind idle-capacity-undeclared)" -eq 0 ]; then ok "an undeclared backlog with no free slot raises nothing"; else fail "undeclared raised with a full fleet: $EV"; fi

clear_rows
new_state
write_mirror 95 10
mc_run mc-usage.sh watch --program alpha --now "$now"
watch "$now"
events
if [ "$(count_kind idle-capacity-undeclared)" -eq 0 ]; then ok "an undeclared backlog with a closed gate raises nothing"; else fail "undeclared raised with a closed gate: $EV"; fi
write_mirror 10 10
mc_run mc-usage.sh watch --program alpha --now "$((now + 4000))"

# A long backlog names at most five units.
write_tracked "program_alpha_idle_backlog: $backlog
fleet_max_parallel_units: 6"
printf 'u1\nu2\nu3\nu4\nu5\nu6\nu7\n' >"$backlog"
new_state
watch "$now"
events
case $EV in
  *u5*) ok "a long backlog names the first five units" ;;
  *) fail "five units not named: $EV" ;;
esac
case $EV in
  *u6*) fail "the event names more than five units: $EV" ;;
  *) ok "a long backlog names no sixth unit" ;;
esac

# A malformed launch bound fails the pass instead of reading as a full fleet.
write_tracked "program_alpha_idle_backlog: $backlog
fleet_host_max_live_workers: banana"
new_state
clear_rows
watch "$now"
if [ "$RC" -ne 0 ]; then ok "a malformed host bound fails the pass"; else fail "a malformed host bound exited 0: $OUT"; fi

# A changed list raises at once, inside the interval.
write_tracked "program_alpha_idle_backlog: $backlog
fleet_max_parallel_units: 6"
printf 'chg-one\nchg-two\n' >"$backlog"
new_state
clear_rows
watch "$now"
printf 'chg-three\nchg-one\n' >"$backlog"
watch $((now + 60))
events
if [ "$(count_kind idle-capacity)" -eq 2 ]; then ok "a changed list is raised at once, inside the interval"; else fail "changed list not raised at once: $EV"; fi

# A program that stops being idle is forgotten and raises afresh on return.
add_row mc-alpha-worker-aaaaaaaaaa alpha worker
for i in 1 2 3 4 5 6; do add_row "mc-alpha-worker-fill$i" alpha worker; done
watch $((now + 120))
clear_rows
watch $((now + 180))
events
if [ "$(count_kind idle-capacity)" -eq 3 ]; then ok "a program no longer idle is forgotten and raises afresh on return"; else fail "not raised afresh after a full spell: $EV"; fi

# Blank, comment and malformed-id lines are skipped; a note after an id is ignored.
printf '# top\n\nbad!id\n-leading-dash\ngood-one\tnote words here\n\ngood-two second note\n' >"$backlog"
new_state
watch "$now"
events
case $EV in
  *good-one*good-two*) ok "blank, comment and malformed-id lines are skipped" ;;
  *) fail "good ids not named: $EV" ;;
esac
case $EV in
  *note*|*bad*|*leading*) fail "a skipped line or a note leaked into the event: $EV" ;;
  *) ok "a note after an id is ignored and malformed ids never named" ;;
esac

# The check verb changes nothing it reads: no event, no dedupe record.
new_state
before=$(find "$fleet" -type f | sort | tr '\n' ' ')
mc_run mc-idle.sh check --program alpha --now "$now" --load 10
after=$(find "$fleet" -type f | sort | tr '\n' ' ')
if [ "$RC" -eq 0 ] && [ "$before" = "$after" ]; then ok "check prints a verdict and writes nothing"; else fail "check wrote state: rc=$RC before=$before after=$after"; fi
case $OUT in
  raise*good-one*|*raise*good-one*) ok "check names the units it would raise" ;;
  *) fail "check did not name the units: $OUT" ;;
esac

# Two programs on one host each read only their own list.
cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_alpha_repositories: [$repo]
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 100}
program_alpha_idle_backlog: $tmp/alpha-list.txt
program_beta_repositories: [$repo]
program_beta_home: $tmp/mchome-beta
program_beta_budget: {host_load: 100}
program_beta_idle_backlog: $tmp/beta-list.txt
EOF
printf 'alpha-only-unit\n' >"$tmp/alpha-list.txt"
printf 'beta-only-unit\n' >"$tmp/beta-list.txt"
rm -rf "$fleet/attention" "$fleet/mission-control/alpha" "$fleet/mission-control/beta"
clear_rows
mc_run mc-idle.sh watch --program alpha --now "$now" --load 10
mc_run mc-event.sh list --program alpha
alpha_ev=$OUT
mc_run mc-idle.sh watch --program beta --now "$now" --load 10
mc_run mc-event.sh list --program beta
beta_ev=$OUT
case $alpha_ev in
  *alpha-only-unit*) ok "program alpha reads its own list" ;;
  *) fail "alpha did not read its own list: $alpha_ev" ;;
esac
case $alpha_ev in
  *beta-only-unit*) fail "alpha read beta's list: $alpha_ev" ;;
  *) ok "program alpha never reads beta's list" ;;
esac
case $beta_ev in
  *beta-only-unit*) ok "program beta reads its own list" ;;
  *) fail "beta did not read its own list: $beta_ev" ;;
esac
case $beta_ev in
  *alpha-only-unit*) fail "beta read alpha's list: $beta_ev" ;;
  *) ok "program beta never reads alpha's list" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "test-mc-idle: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-idle: all passed"
