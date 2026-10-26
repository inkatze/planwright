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

program '{}'
mc_run mc-budget.sh report --program alpha --now 100000 --load 0
sed 's/^format\t1$/format\t9/' "$fleet/mission-control/alpha/budget" >"$tmp/b" && cp "$tmp/b" "$fleet/mission-control/alpha/budget"
mc_run mc-budget.sh read --program alpha
expect_rc "D-8: a budget file of an unknown format is refused" 1
expect_err "D-8: the refusal names the field" "format"

mc_run mc-budget.sh report --program nosuch
expect_rc "an unconfigured program" 3

if [ "$failures" -ne 0 ]; then
  echo "test-mc-budget: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-budget: all passed"
