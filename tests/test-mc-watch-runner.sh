#!/bin/bash
# Tests for scripts/mc-watch.sh as a daemon: a pass signalled mid-way, an
# install path with a space, unresolvable and disarmed watchers, stop, a
# pass that refreshes snapshots and wakes sessions, and the runner itself
# (mission-control REQ-E1.1, REQ-E1.3, REQ-M1.1; D-4).
#
# tests/test-mc-watch.sh covers arming, re-arming, the rungs and the pause.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-watch-runner.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-watch.sh" ] || {
  echo "FAIL: scripts/mc-watch.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

# shellcheck source=tests/lib/mc-watch-fixture.sh
. "$here/lib/mc-watch-fixture.sh"

# A TERM to a pass lets it finish and then frees the lock, whatever loops it
# armed.
setup '[alpha-duty]'
mc_env /bin/bash "$repo_root/scripts/mc-watch.sh" pass --program alpha >"$tmp/term-pass.out" 2>&1 &
pass_pid=$!
check "a pass arms a watcher" poll_until --what "an armed record" -- sh -c "ls '$wdir'/*.rec >/dev/null 2>&1"
kill "$pass_pid" 2>/dev/null
check "a pass signalled after arming still ends" poll_until --what "the pass's exit" -- pid_gone "$pass_pid"
check "and finishes its steps first" grep -q "^wake${tab}" "$tmp/term-pass.out"
mc_run mc-watch.sh pass --program alpha
expect_no_out "and leaves the runner lock free" "busy"

# A runner installed under a path with a space still recognizes its loops.
setup '[alpha-duty]'
mkdir -p "$tmp/with space"
cp -R "$repo_root/scripts" "$tmp/with space/scripts"
(mc_env /bin/bash "$tmp/with space/scripts/mc-watch.sh" pass --program alpha) >"$tmp/space.out" 2>&1
(mc_env /bin/bash "$tmp/with space/scripts/mc-watch.sh" pass --program alpha) >"$tmp/space.out" 2>&1
if grep -q "^running${tab}alpha-duty${tab}scripts/alpha-watch.sh" "$tmp/space.out"; then
  ok "a loop under an install path with a space is recognized"
else
  fail "a loop under a path with a space was not recognized: $(cat "$tmp/space.out")"
fi
(mc_env /bin/bash "$tmp/with space/scripts/mc-watch.sh" stop --program alpha) >/dev/null 2>&1

# ---------------------------------------------------------------------------
# A watcher that cannot resolve is reported, never armed or evented; a duty
# the program no longer enables is disarmed; stop stops them all.
# ---------------------------------------------------------------------------
setup '[alpha-duty]'
mc_run mc-watch.sh pass --program alpha
sweep_pid=$(rec_pid "$(slot_for alpha-sweep.sh)")
mv "$core/scripts/alpha-sweep.sh" "$tmp/alpha-sweep.sh"
mc_run mc-watch.sh pass --program alpha
expect_out "a live watcher whose script went is reported unresolvable" "unresolvable${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
check "and its loop is stopped" poll_until --what "the orphaned watcher's exit" -- pid_gone "$sweep_pid"
mv "$tmp/alpha-sweep.sh" "$core/scripts/alpha-sweep.sh"

setup '[lost-duty]'
mc_run mc-watch.sh pass --program alpha
expect_rc "an unresolvable watcher fails the pass" 1
expect_out "it is reported" "unresolvable${tab}lost-duty${tab}scripts/nowhere.sh"
mc_run mc-watch.sh pass --program alpha
mc_run mc-event.sh list --program alpha
expect_no_out "and floods no watcher-stopped event" "watcher-stopped"

setup '[alpha-duty]'
mc_run mc-watch.sh pass --program alpha
sweep_pid=$(rec_pid "$(slot_for alpha-sweep.sh)")
sed 's/^program_alpha_duties: .*/program_alpha_duties: [beta-duty]/' "$tracked" >"$tmp/t" && cp "$tmp/t" "$tracked"
mc_run mc-watch.sh pass --program alpha
expect_out "a disabled duty's watchers are disarmed" "disarmed${tab}alpha-duty"
check "the disarmed watcher's process is stopped" poll_until --what "the disarmed watcher's exit" -- pid_gone "$sweep_pid"
if ls "$wdir"/*.rec >/dev/null 2>&1; then fail "a disarmed watcher kept its record"; else ok "no record is left"; fi

setup '[alpha-duty]'
mc_run mc-watch.sh pass --program alpha
pids=$(cut -f1 "$wdir"/*.rec)
mc_run mc-watch.sh stop --program alpha
expect_rc "stop" 0
expect_out "stop names what it disarmed" "disarmed${tab}alpha-duty"
# shellcheck disable=SC2086 # one pid per word
check "stop ends every watcher" poll_until --what "every stopped watcher's exit" -- pid_gone $pids

# ---------------------------------------------------------------------------
# REQ-E1.3, REQ-M1.1: a pass refreshes the snapshots and runs the relay and
# the tick; a failed step fails the pass.
# ---------------------------------------------------------------------------
setup '[beta-duty]' '' '{work-items: tracker:snapshot}'
mc_run mc-wake.sh target add --program alpha ghost
mc_run mc-event.sh emit --program alpha pr-ready pr-1
mc_run mc-watch.sh pass --program alpha
expect_rc "a pass with a source and a wake target" 0
expect_out "REQ-M1.1: the pass refreshes the snapshot" "snapshot${tab}refreshed${tab}tracker"
expect_out "REQ-E1.3: the pass relays the wake" "wake${tab}unreachable${tab}ghost"
expect_out "REQ-E1.3: the pass runs the tick" "wake${tab}tick"
TRACKER_EXIT=1 mc_run mc-watch.sh pass --program alpha --now "$(($(date +%s) + 3600))"
expect_rc "a failed snapshot step fails the pass" 1
expect_out "and is reported" "snapshot${tab}failed${tab}tracker${tab}1"

# ---------------------------------------------------------------------------
# The runner: run --once, and one runner per program.
# ---------------------------------------------------------------------------
setup '[beta-duty]'
mc_run mc-watch.sh run --program alpha --once
expect_rc "run --once makes one pass and exits" 0
mc_env /bin/bash "$repo_root/scripts/mc-watch.sh" run --program alpha >/dev/null 2>&1 &
run_pid=$!
check "a runner holds the runner lock" poll_until --deadline 30 --what "the runner's lock" -- sh -c "[ -L '$fleet/mission-control/alpha/runner.lock' ] || [ -e '$fleet/mission-control/alpha/runner.lock' ]"
mc_run mc-watch.sh pass --program alpha
expect_eq "a second runner's pass stands aside" "busy"
mc_run mc-watch.sh stop --program alpha
expect_rc "stop beside a live runner refuses" 1
expect_eq "and says busy" "busy"
# The tick stamps last at the end of a pass, so the runner is now asleep.
check "the runner's first pass ends" poll_until --what "the first pass's tick" -- test -f "$fleet/mission-control/alpha/last-tick"
sleep 1
kill "$run_pid" 2>/dev/null
# The runner sleeps out a 1m interval: a TERM handled only after it would
# miss this deadline.
check "the runner exits on TERM at once" poll_until --deadline 10 --what "the runner's exit" -- pid_gone "$run_pid"
run_pid=""
mc_run mc-watch.sh pass --program alpha
expect_rc "the lock is free once the runner is gone" 0

setup '[lost-duty]'
mc_run mc-watch.sh run --program alpha --once
expect_rc "run --once exits with the pass's status" 1
printf '%s\n' "mission_control_runner_interval: 1s" >>"$tracked"
mc_env /bin/bash "$repo_root/scripts/mc-watch.sh" run --program alpha >/dev/null 2>"$tmp/run.err" &
run_pid=$!
check "a failed pass is retried at the next interval" poll_until --what "two failed passes" -- \
  sh -c "[ \"\$(grep -c 'the pass failed' '$tmp/run.err')\" -ge 2 ]"
kill "$run_pid" 2>/dev/null
check "the retrying runner exits on TERM once its pass ends" poll_until --deadline 60 --what "the runner's exit" -- pid_gone "$run_pid"
run_pid=""

setup '[alpha-duty]'
mc_run mc-watch.sh pass --program alpha
pids=$(cut -f1 "$wdir"/*.rec)
printf '%s\n' "mission_control_programs: []" >"$tracked"
mc_run mc-watch.sh stop --program alpha
expect_rc "a program dropped from configuration can still be stopped" 0
mc_run mc-watch.sh stop --program nosuch
expect_rc "a program that never ran here has nothing to stop" 3
# shellcheck disable=SC2086 # one pid per word
check "its watchers end" poll_until --what "the dropped program's watchers' exit" -- pid_gone $pids

if [ "$failures" -ne 0 ]; then
  echo "test-mc-watch-runner: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-watch-runner: all passed"
