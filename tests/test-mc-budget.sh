#!/bin/bash
# Tests for scripts/mc-budget.sh — a program's budget, headroom and
# degradation rung (mission-control REQ-L1.2, REQ-M1.6; D-17).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-budget.sh
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

[ -f "$repo_root/scripts/mc-budget.sh" ] || {
  echo "FAIL: scripts/mc-budget.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')

# program <budget map>: a configured program `alpha` with that budget, and a
# clean fleet home.
program() {
  reset_mc_fixture
  write_core_defaults <<'EOF'
notification_channel: none
EOF
  rm -rf "$fleet"
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_budget: $1
EOF
}

rung() { # rung <label> <want> [args...]
  rg_label=$1
  rg_want=$2
  shift 2
  mc_run mc-budget.sh rung --program alpha --now 100000 "$@"
  expect_rc "$rg_label" 0
  expect_eq "$rg_label: the rung" "$rg_want"
}

# seed_polls <n> [epoch]: n poll-log lines, written straight to the store so
# the rung cases do not pay a locked write each; the cap cases use `poll`.
seed_polls() {
  mkdir -p "$fleet/mission-control/alpha"
  sp_i=0
  while [ "$sp_i" -lt "$1" ]; do
    printf '%s\tforge\n' "${2:-100000}"
    sp_i=$((sp_i + 1))
  done >>"$fleet/mission-control/alpha/polls"
}

polls() { # polls <source> <n> [epoch]
  pl_i=0
  while [ "$pl_i" -lt "$2" ]; do
    mc_run mc-budget.sh poll --program alpha "$1" --now "${3:-100000}"
    [ "$RC" -eq 0 ] || fail "poll $pl_i of $1 refused: $OUT $ERR"
    pl_i=$((pl_i + 1))
  done
}

# ---------------------------------------------------------------------------
# REQ-L1.2: the budget file carries its format, every dimension and the rung.
# ---------------------------------------------------------------------------
program '{polls_per_hour: 10, spend_alpha_duty: low}'
mc_run mc-budget.sh report --program alpha --now 100000 --load 10
expect_rc "REQ-L1.2: report" 0
expect_out "REQ-L1.2: the budget file opens with its format" "format${tab}1"
expect_out "REQ-L1.2: the program's limit lays over the default" "dimension${tab}polls_per_hour${tab}0${tab}10${tab}10${tab}0"
expect_out "REQ-L1.2: the default sessions limit" "dimension${tab}sessions${tab}0${tab}4${tab}4${tab}0"
expect_out "REQ-L1.2: context steps are a dimension" "dimension${tab}context_steps${tab}"
expect_out "REQ-L1.2: host load is a dimension" "dimension${tab}host_load${tab}10${tab}100${tab}90${tab}10"
expect_out "REQ-L1.2: the spend ceiling" "spend${tab}ceiling${tab}high"
expect_out "REQ-L1.2: a duty's own spend class is in the file" "spend${tab}alpha-duty${tab}low"
expect_out "REQ-L1.2: an idle program is at the normal rung" "rung${tab}normal"
if [ -f "$fleet/mission-control/alpha/budget" ]; then
  ok "REQ-L1.2: the budget file is written under the fleet home"
else
  fail "REQ-L1.2: no budget file under the fleet home"
fi
mc_run mc-budget.sh read --program alpha
expect_out "REQ-L1.4: read prints the file the panel draws headroom from" "dimension${tab}polls_per_hour"

# ---------------------------------------------------------------------------
# REQ-L1.2: each rung from fixtures, at its threshold exactly.
# ---------------------------------------------------------------------------
program '{polls_per_hour: 20}'
seed_polls 13
rung "REQ-L1.2: under the throttle threshold is normal" normal --load 0
seed_polls 1
rung "REQ-L1.2: 70% of the poll cap throttles" throttle --load 0
seed_polls 3
rung "REQ-L1.2: 85% pauses watchers" pause-watchers --load 0
mc_run mc-budget.sh report --program alpha --now 100000 --load 0
expect_out "REQ-L1.2: the rung names the dimension" "polls_per_hour at 85%"
seed_polls 3
rung "REQ-L1.2: the cap reached holds dispatch" hold-dispatch --load 0
mc_run mc-budget.sh rung --program alpha --now 103601 --load 0
expect_eq "REQ-L1.2: polls an hour old no longer count toward the rung" "normal"

program '{context_steps: 50}'
mc_run mc-budget.sh record --program alpha context_steps 50
expect_rc "record context steps" 0
rung "REQ-L1.2: context steps at their limit hand over" handover --load 0

program '{}'
mc_run quota-hold.sh hold --vendor fixture --unit alpha:1 --step gate --reason "fixture limit" --now 99990
expect_rc "a fixture quota hold" 0
rung "REQ-L1.2: a quota hold (the limited outcome) holds dispatch" hold-dispatch --load 0
mc_run mc-budget.sh report --program alpha --now 100000 --load 0
expect_out "REQ-L1.2: the rung names the quota hold" "a quota hold (limited)"

program '{}'
printf '%s\n' "fleet_daemon_pause: true" >>"$tracked"
rung "REQ-L1.2: the daemon pause is the top rung" paused --load 0

# ---------------------------------------------------------------------------
# REQ-L1.2: a second source's polls count against the one cap; an hour-old
# poll no longer counts.
# ---------------------------------------------------------------------------
program '{polls_per_hour: 4}'
polls forge 2 100000
polls tracker 2 100000
mc_run mc-budget.sh poll --program alpha forge --now 100000
expect_rc "REQ-L1.2: a fifth poll across two sources is refused as capped" 4
expect_out "REQ-L1.2: the refusal says capped" "capped"
mc_run mc-budget.sh poll --program alpha tracker --now 103601
expect_rc "REQ-L1.2: polls older than an hour have aged out" 0

# ---------------------------------------------------------------------------
# REQ-M1.6: heavy work is scheduled by host load, not the session count.
# ---------------------------------------------------------------------------
program '{}'
mc_run mc-budget.sh admit --program alpha heavy --now 100000 --load 80
expect_rc "REQ-M1.6: heavy work at 80% host load is queued" 1
expect_out "REQ-M1.6: it says host load" "host load at 80%"
mc_run mc-budget.sh admit --program alpha heavy --now 100000 --load 20
expect_rc "REQ-M1.6: heavy work at 20% host load is admitted" 0
expect_eq "REQ-M1.6: admitted says so" "admitted"
mc_run mc-budget.sh record --program alpha sessions 3
mc_run mc-budget.sh admit --program alpha session --now 100000 --load 0
expect_rc "REQ-L1.2: a session under the limit is admitted" 0
mc_run mc-budget.sh record --program alpha sessions 4
mc_run mc-budget.sh admit --program alpha heavy --now 100000 --load 0
expect_out "REQ-L1.2: sessions at their limit reach hold-dispatch, which queues heavy work too" "queued${tab}hold-dispatch"
# With hold_dispatch above 100%, sessions at their limit is not yet a rung;
# the session count alone queues the session.
program '{sessions: 5}'
printf '%s\n' "mission_control_budget_ladder: {throttle: 120, pause_watchers: 130, hold_dispatch: 150}" >>"$tracked"
mc_run mc-budget.sh record --program alpha sessions 5
mc_run mc-budget.sh admit --program alpha session --now 100000 --load 0
expect_rc "REQ-L1.2: a session at the sessions limit is queued" 1
expect_out "REQ-L1.2: the queue names the sessions limit" "queued${tab}sessions at their limit"

# ---------------------------------------------------------------------------
# Spend class per duty; invalid input is refused, named.
# ---------------------------------------------------------------------------
program '{spend_ceiling: medium, spend_alpha_duty: low}'
mc_run mc-budget.sh ceiling --program alpha alpha-duty
expect_eq "REQ-L1.2: a duty's own spend class wins" "low"
mc_run mc-budget.sh ceiling --program alpha beta-duty
expect_eq "REQ-L1.2: other duties take the program's ceiling" "medium"

program '{sessionz: 3}'
mc_run mc-budget.sh report --program alpha --now 100000 --load 0
expect_rc "an unknown budget key is refused" 1
expect_err "the unknown key is named" "sessionz"

program '{spend_ceiling: lavish}'
mc_run mc-budget.sh report --program alpha --now 100000 --load 0
expect_rc "an unknown spend class is refused" 1
expect_err "the bad spend class is named" "spend_ceiling"

for key in spend_ spend_BAD spend_alpha-duty spend__alpha; do
  program "{$key: low}"
  mc_run mc-budget.sh report --program alpha --now 100000 --load 0
  expect_rc "a malformed spend key ($key) is refused" 1
  expect_err "the malformed spend key ($key) is named" "$key"
done

program '{}'
mc_run mc-budget.sh record --program alpha sessions 010
expect_rc "a number with a leading zero is refused, never read as octal" 2

program '{}'
mkdir -p "$fleet/mission-control/alpha"
printf 'sessions\t1\n' >"$fleet/mission-control/alpha/in-use"
chmod 000 "$fleet/mission-control/alpha/in-use"
if [ -r "$fleet/mission-control/alpha/in-use" ]; then
  ok "skipped: the unreadable-store case (this user reads a mode-000 file)"
else
  mc_run mc-budget.sh report --program alpha --now 100000 --load 0
  expect_rc "an unreadable in-use record fails, never counted as zero" 1
  mc_run mc-budget.sh record --program alpha context_steps 1
  expect_rc "and is never rewritten over" 1
fi
chmod 600 "$fleet/mission-control/alpha/in-use"
printf 'sessions\tmany\n' >"$fleet/mission-control/alpha/in-use"
mc_run mc-budget.sh admit --program alpha session --now 100000 --load 0
expect_rc "a malformed in-use value fails, never counted as zero" 1
expect_err "the malformed dimension is named" "sessions"

# A poll logged by a caller whose clock reads later survives a rewrite.
program '{polls_per_hour: 10}'
mkdir -p "$fleet/mission-control/alpha"
printf '100010\ttracker\n' >"$fleet/mission-control/alpha/polls"
mc_run mc-budget.sh poll --program alpha forge --now 100000
if grep -q '^100010' "$fleet/mission-control/alpha/polls"; then
  ok "REQ-L1.2: a rewrite of the poll log keeps a later caller's poll"
else
  fail "REQ-L1.2: a later caller's poll was dropped"
fi
printf '100400\ttracker\n' >>"$fleet/mission-control/alpha/polls"
mc_run mc-budget.sh poll --program alpha forge --now 100000
if grep -q '^100400' "$fleet/mission-control/alpha/polls"; then
  fail "a poll stamped past the five-minute skew was kept"
else
  ok "a poll stamped past the five-minute skew is dropped"
fi

program '{}'
mc_run mc-budget.sh report --program alpha --now 100000 --load 0
awk -F '\t' -v OFS='\t' '$1 == "format" { $2 = 9 } { print }' "$fleet/mission-control/alpha/budget" >"$tmp/b" && cp "$tmp/b" "$fleet/mission-control/alpha/budget"
mc_run mc-budget.sh read --program alpha
expect_rc "D-8: a budget file of an unknown format is refused" 1
expect_err "D-8: the refusal names the field" "format"

mc_run mc-budget.sh report --program nosuch
expect_rc "an unconfigured program" 3

# The panel draws a plain name for every limit this script emits, so no
# dimension reaches the operator under its raw key.
panel_src=$repo_root/hooks/mission-control/panel.tsx
budget_dims=$(sed -n 's/^DIMENSIONS="\(.*\)"$/\1/p' "$repo_root/scripts/mc-budget.sh")
for dim in $budget_dims; do
  if grep -Eq "^  $dim: '" "$panel_src"; then
    ok "the panel names the $dim limit in plain words"
  else
    fail "the panel has no plain name for the $dim limit"
  fi
done

# ---------------------------------------------------------------------------
# REQ-L1.7 / D-41: host-shared launch admission. `reserve` admits a launch only
# while the account, the host's load and its memory are each inside their knob,
# the host-wide ceiling has room and the program's own session bound has room,
# and takes a reservation under one lock; `release` gives it back.
# ---------------------------------------------------------------------------
anow=$(date +%s)
mirror="$tmp/rate-limits.json"
export PLANWRIGHT_USAGE_MIRROR="$mirror"
write_mirror() { # write_mirror <session pct> <weekly pct>
  printf '{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}\n' \
    "$1" "$((anow + 3600))" "$2" "$((anow + 86400))" >"$mirror"
  TZ=UTC touch -t "$(date -u -d "@$anow" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$anow" +%Y%m%d%H%M.%S)" "$mirror"
}
store="$fleet/mission-control/admission"
# two_programs <ceiling> [<alpha budget map>]: programs alpha and beta, the
# host-wide ceiling, a healthy account and no sessions.
two_programs() {
  alpha_budget=${2:-"{}"}
  reset_mc_fixture
  rm -rf "$fleet"
  mkdir -p "$fleet/mission-control"
  cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_budget: $alpha_budget
program_beta_repositories: [$repo]
program_beta_spec_root: $repo
fleet_max_parallel_units: $1
EOF
  write_mirror 20 20
}
reserve() { # reserve <program> [args...]
  rv_p=$1
  shift
  mc_run mc-budget.sh reserve --program "$rv_p" --now "$anow" --holder "$$" "$@"
}
# registry_row <name> <program> <launched> [<waiting>]: a launcher registry row.
registry_row() {
  mkdir -p "$fleet/mission-control/sessions"
  {
    printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\t%s\nkind\tworker\nlaunched\t%s\n' "$1" "$2" "$3"
    [ -z "${4:-}" ] || printf 'waiting\t%s\n' "$4"
  } >"$fleet/mission-control/sessions/$1"
}
# dead_pid: a process id that has exited.
dead_pid() {
  sleep 0 &
  dp=$!
  wait "$dp"
  printf '%s\n' "$dp"
}
old=$((anow - 100000))

two_programs 5
reserve alpha --load 95 --mem 80
expect_rc "REQ-L1.7: load past its knob holds the launch" 1
expect_out "REQ-L1.7: the hold names the load axis" "queued${tab}load"
two_programs 5
reserve alpha --load 10 --mem 5
expect_rc "REQ-L1.7: memory under its knob holds the launch" 1
expect_out "REQ-L1.7: the hold names the memory axis" "queued${tab}memory"
two_programs 5
write_mirror 20 95
reserve alpha --load 10 --mem 80
expect_rc "REQ-L1.7: spent account headroom holds the launch" 1
expect_out "REQ-L1.7: the hold names the account axis" "queued${tab}account"
two_programs 5
write_mirror 95 20
reserve alpha --load 10 --mem 80
expect_out "REQ-L1.7: the session window counts as account headroom too" "queued${tab}account"
two_programs 5
rm -f "$mirror"
reserve alpha --load 10 --mem 80
expect_rc "REQ-L1.7: an unreadable usage cache holds the launch" 1
expect_out "REQ-L1.7: the unreadable cache is an account hold" "queued${tab}account"

two_programs 5
reserve alpha --load 10 --mem 80
expect_rc "REQ-L1.7: a launch inside every limit is admitted" 0
expect_out "REQ-L1.7: admission prints a reservation" "reserved${tab}"
if [ "$(head -n 1 "$store")" = "format${tab}1" ]; then
  ok "REQ-L1.7: the reservation store opens with its format, under the fleet home"
else
  fail "REQ-L1.7: no reservation store opening with a format field at $store"
fi
rid=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "reserved" { print $2 }')
mc_run mc-budget.sh release --program alpha "$rid"
expect_rc "D-41: a reservation is released by its id" 0
if grep -q "$rid" "$store"; then fail "D-41: the released reservation is still stored"; else ok "D-41: the released reservation is gone"; fi

# Four concurrent admissions from two programs, capacity for two.
two_programs 2
mkdir -p "$tmp/conc"
rm -f "$tmp"/conc/*
ci=0
for p in alpha beta alpha beta; do
  ci=$((ci + 1))
  (mc_env /bin/bash "$repo_root/scripts/mc-budget.sh" reserve --program "$p" --now "$anow" --holder "$$" --load 10 --mem 80 >"$tmp/conc/$ci" 2>&1) &
done
wait
admitted=$(cat "$tmp"/conc/* | grep -c "^reserved")
if [ "$admitted" -eq 2 ]; then
  ok "REQ-L1.7: four concurrent admissions from two programs admit exactly two"
else
  fail "REQ-L1.7: four concurrent admissions admitted $admitted, not two"
  cat "$tmp"/conc/* >&2
fi

# The ceiling caps a host with room to spare, whatever registered sessions it
# counts; a waiting session holds no slot.
two_programs 1
registry_row mc-fix-1 beta "$old"
reserve alpha --load 0 --mem 99
expect_rc "REQ-L1.7: the ceiling caps a host with load and memory to spare" 1
expect_out "REQ-L1.7: the hold names the ceiling" "queued${tab}ceiling"
two_programs 1
registry_row mc-fix-1 beta "$old" ci
reserve alpha --load 0 --mem 99
expect_rc "REQ-L1.7: a waiting session holds no slot" 0

# A program's own session bound still caps it beneath the shared total.
two_programs 9 '{sessions: 1}'
registry_row mc-fix-1 alpha "$old"
reserve alpha --load 0 --mem 99
expect_rc "REQ-L1.2: the program's own session bound caps it under the shared total" 1
expect_out "REQ-L1.2: the hold names the program's sessions" "queued${tab}sessions"
reserve beta --load 0 --mem 99
expect_rc "REQ-L1.2: another program is not held by it" 0

# Warm-up: a reservation counts at its configured share, so a lagging load
# reading never admits a burst.
two_programs 9
printf '%s\n' 'mission_control_admit_load: 85' 'mission_control_admit_warmup: {seconds: 120, load: 10, memory: 5}' >>"$tracked"
reserve alpha --load 78 --mem 99
expect_rc "REQ-L1.7: the first launch at 78% load is admitted" 0
reserve beta --load 78 --mem 99
expect_rc "REQ-L1.7: the reservation's warm-up share holds the next launch" 1
expect_out "REQ-L1.7: the warm-up hold names load" "queued${tab}load"
two_programs 9
printf '%s\n' 'mission_control_admit_load: 85' 'mission_control_admit_warmup: {seconds: 120, load: 10, memory: 5}' >>"$tracked"
registry_row mc-fix-1 alpha "$((anow - 30))"
reserve beta --load 70 --mem 99
expect_rc "REQ-L1.7: a session younger than the warm-up counts at its share" 0
expect_out "REQ-L1.7: a lone warm session leaves 70+10 under the knob" "reserved${tab}"
registry_row mc-fix-2 alpha "$((anow - 30))"
registry_row mc-fix-3 alpha "$((anow - 30))"
reserve beta --load 70 --mem 99
expect_rc "REQ-L1.7: three warm sessions push the projection over the knob" 1
two_programs 9
printf '%s\n' 'mission_control_admit_load: 85' 'mission_control_admit_warmup: {seconds: 120, load: 10, memory: 5}' >>"$tracked"
registry_row mc-fix-1 alpha "$old"
registry_row mc-fix-2 alpha "$old"
registry_row mc-fix-3 alpha "$old"
reserve beta --load 70 --mem 99
expect_rc "REQ-L1.7: a session past the warm-up is measured, not counted again" 0

# Reclaim: a reservation whose holder is dead, or older than the timeout, goes.
two_programs 1
mkdir -p "$fleet/mission-control"
printf 'format\t1\nreservation\tr1.1\tbeta\t%s\t%s\t-\n' "$(dead_pid)" "$anow" >"$store"
reserve alpha --load 10 --mem 80
expect_rc "D-41: the next admitter reclaims a dead holder's reservation" 0
expect_out "D-41: the reclaim is logged" "reclaimed${tab}r1.1"
two_programs 1
printf 'mission_control_admit_timeout: 5m\n' >>"$tracked"
printf 'format\t1\nreservation\tr1.1\tbeta\t%s\t%s\t-\n' "$$" "$((anow - 400))" >"$store"
reserve alpha --load 10 --mem 80
expect_rc "D-41: a reservation older than the timeout is reclaimed" 0
expect_out "D-41: the timeout reclaim is logged" "reclaimed${tab}r1.1"
two_programs 1
printf 'format\t1\nreservation\tr1.1\tbeta\t%s\t%s\t-\n' "$$" "$((anow - 30))" >"$store"
reserve alpha --load 10 --mem 80
expect_rc "D-41: a live young reservation holds its slot" 1
# A reservation whose session registered is released: counted once, as a session.
two_programs 2
printf 'format\t1\nreservation\tr1.1\tbeta\t%s\t%s\tmc-fix-1\n' "$$" "$((anow - 30))" >"$store"
registry_row mc-fix-1 beta "$old"
reserve alpha --load 10 --mem 80
expect_rc "D-41: a reservation is released once its session registers" 0

# The budget output names the held axis, so the panel can show it.
two_programs 5
mc_run mc-budget.sh report --program alpha --now "$anow" --load 10 --mem 80
expect_out "REQ-L1.4: the budget names an open admission" "admission${tab}open"
two_programs 5
mc_run mc-budget.sh report --program alpha --now "$anow" --load 95 --mem 80
expect_out "REQ-L1.4: the budget names the load axis holding launches" "admission${tab}load${tab}"
two_programs 5
mc_run mc-budget.sh report --program alpha --now "$anow" --load 10 --mem 5
expect_out "REQ-L1.4: the budget names the memory axis holding launches" "admission${tab}memory${tab}"
if grep -q "^admission${tab}memory" "$fleet/mission-control/alpha/budget"; then
  ok "REQ-L1.4: the budget file the panel reads carries the held axis"
else
  fail "REQ-L1.4: the budget file lacks the held axis"
fi

# A lock not taken in time holds the launch.
two_programs 5
sleep 30 &
holder=$!
tok=$(mc_env /bin/sh "$repo_root/scripts/fleet-state.sh" lock --owner-pid "$holder")
MC_LOCK_TRIES=3 reserve alpha --load 10 --mem 80
expect_rc "REQ-L1.7: a lock not taken in time holds the launch" 1
expect_out "REQ-L1.7: the lock hold is named" "queued${tab}lock"
(mc_env /bin/sh "$repo_root/scripts/fleet-state.sh" unlock "$tok" >"$tmp/unlock.out" 2>&1)
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null

# A store of an unknown format is refused.
two_programs 5
mkdir -p "$fleet/mission-control"
printf 'format\t9\n' >"$store"
reserve alpha --load 10 --mem 80
expect_rc "D-8: a reservation store of an unknown format is refused" 1
expect_err "D-8: the refusal names the field" "format"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-budget: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-budget: all passed"
