#!/bin/bash
# Tests for scripts/mc-watch.sh — the watcher runner: arming the enabled
# duties' watchers, re-arming a stopped one with the stop as an event, the
# daemon pause, the budget rungs, and no model on any runner path
# (mission-control REQ-E1.1, REQ-E1.2, REQ-E1.5, REQ-C1.5, REQ-L1.1,
# REQ-L1.2; D-4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-watch.sh
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

wdir="$fleet/mission-control/alpha/watchers"

# Every watcher loop this suite starts is recorded by pid in a .rec file;
# those pids are stopped on the way out, and only while the process is still
# that slot's loop.
reap() {
  for rp_f in "$wdir"/*.rec; do
    [ -f "$rp_f" ] || continue
    rp_pid=$(cut -f1 "$rp_f")
    rp_slot=${rp_f##*/}
    rp_slot=${rp_slot%.rec}
    case $rp_pid in
      "" | *[!0-9]*) continue ;;
    esac
    case $(ps -ww -o args= -p "$rp_pid" 2>/dev/null) in
      "/bin/bash /"*"/mc-watch.sh loop --program alpha --slot $rp_slot") kill "$rp_pid" 2>/dev/null ;;
    esac
  done
}
run_pid=""
cleanup() {
  [ -z "$run_pid" ] || kill "$run_pid" 2>/dev/null
  reap
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

tab=$(printf '\t')

# Fixture watchers: each run logs a line. alpha-watch also reports an event,
# a line the store refuses, and how many watcher-stopped events the store
# held when it ran.
mkdir -p "$core/scripts" "$tmp/runs" "$repo/scripts"
cat >"$core/scripts/alpha-watch.sh" <<'EOF'
#!/bin/sh
seen=$(grep -l watcher-stopped "$WATCH_EVENTS"/e* 2>/dev/null | wc -l | tr -d ' ')
printf '%s %s\n' "$PLANWRIGHT_MC_DUTY" "$seen" >>"$WATCH_RUNS/alpha-watch"
printf 'event\talpha-due\tpr-7\tseven is due\n'
printf 'event\tBad Kind\tpr-7\n'
printf 'chatter that is not an event\n'
EOF
cat >"$core/scripts/alpha-sweep.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/alpha-sweep"
EOF
cat >"$core/scripts/fast-watch.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/fast-watch"
printf 'event\tfast-due\tlast-line'
EOF
cat >"$core/scripts/heavy-watch.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/heavy-watch"
sleep 60 &
printf '%s\n' "$!" >"$WATCH_RUNS/heavy-child"
wait
EOF
cat >"$repo/scripts/tracker-adapter.sh" <<'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  [ "$1" = --out ] && out=$2
  shift
done
printf 'item\tT-1\topen\n' >"$out"
exit "${TRACKER_EXIT:-0}"
EOF
WATCH_RUNS="$tmp/runs"
WATCH_EVENTS="$fleet/attention/mission-control/alpha/events"
export WATCH_RUNS WATCH_EVENTS

# setup <duties> [budget] [sources]: program alpha with a host-load limit no
# host reaches, and the fixture duties fast-duty (a 1s low-cost watcher and
# an hourly high-cost one) and lost-duty (a script that does not exist)
# beside the core seed's.
setup() {
  reap
  reset_mc_fixture
  rm -rf "$fleet" "$tmp/runs"/*
  cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
duties:
  - id: fast-duty
    summary: "A fast fixture duty"
    triggers: []
    watchers: [scripts/fast-watch.sh@1s/low, scripts/heavy-watch.sh@1h/high]
    wake: none
    rules: []
    kinds: []
    files: fast
    lifecycle: live
    never-propose: false
  - id: lost-duty
    summary: "A duty whose watcher is missing"
    triggers: []
    watchers: [scripts/nowhere.sh@5m/low]
    wake: none
    rules: []
    kinds: []
    files: lost
    lifecycle: live
    never-propose: false
EOF
  cat >"$repo/.claude/catalogs/snapshot-adapters.yaml" <<'EOF'
adapters:
  - id: tracker
    summary: "A fixture tracker"
    script: scripts/tracker-adapter.sh
    cadence: 10m
EOF
  st_sources=${3:-'{work-items: specs:record}'}
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: $1
program_alpha_sources: $st_sources
program_alpha_budget: {host_load: 1000000${2:+, $2}}
EOF
}

rec_pid() { cut -f1 "$wdir/$1".rec 2>/dev/null; }
slot_for() { # slot_for <script-basename>: the slot recording that script
  for sf_f in "$wdir"/*.rec; do
    [ -f "$sf_f" ] || continue
    case $(cut -f4 "$sf_f") in
      *"$1")
        sf_s=${sf_f##*/}
        printf '%s\n' "${sf_s%.rec}"
        return 0
        ;;
    esac
  done
  return 1
}
runs_of() { [ -f "$WATCH_RUNS/$1" ] && wc -l <"$WATCH_RUNS/$1" | tr -d ' ' || echo 0; }
ran() { [ "$(runs_of "$1")" -ge "$2" ]; }
check() { # check <label> <command...>
  ck_label=$1
  shift
  if "$@"; then ok "$ck_label"; else fail "$ck_label"; fi
}
seed_polls_now() { # seed_polls_now <n>: poll-log lines stamped now
  mkdir -p "$fleet/mission-control/alpha"
  sp_now=$(date +%s)
  sp_i=0
  while [ "$sp_i" -lt "$1" ]; do
    printf '%s\tforge\n' "$sp_now"
    sp_i=$((sp_i + 1))
  done >>"$fleet/mission-control/alpha/polls"
}

# ---------------------------------------------------------------------------
# REQ-E1.1: a pass arms every armed duty's watchers; an `off` duty arms none.
# ---------------------------------------------------------------------------
setup '[alpha-duty, beta-duty]'
mc_run mc-watch.sh pass --program alpha
expect_rc "REQ-E1.1: a pass" 0
expect_out "REQ-E1.1: the live duty's first watcher is armed" "armed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
expect_out "REQ-E1.1: its second watcher is armed" "armed${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
expect_no_out "REQ-E1.1: an off duty arms nothing" "beta-duty"
check "REQ-E1.1: an armed watcher runs" poll_until --what "the first watcher run" -- ran alpha-watch 1
check "REQ-E1.2: the watcher's declared event lands in the attention store" \
  poll_until --what "the watcher's event" -- sh -c "grep -q 'alpha-due' '$WATCH_EVENTS'/e* 2>/dev/null"
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.2: the event carries its kind, subject and text" "alpha-due${tab}pr-7${tab}seven is due"
expect_no_out "REQ-E1.2: a line that is not an event is ignored" "chatter"
watch_slot=$(slot_for alpha-watch.sh)
check "the watcher is told its duty" grep -q '^alpha-duty ' "$WATCH_RUNS/alpha-watch"

mc_run mc-watch.sh pass --program alpha
expect_out "REQ-E1.1: a second pass leaves a live watcher running" "running${tab}alpha-duty${tab}scripts/alpha-watch.sh"
expect_no_out "REQ-E1.1: nothing is re-armed while it runs" "rearmed"

check "the run's status is recorded" poll_until --what "the run record" -- test -s "$wdir/$watch_slot.last"
mc_run mc-watch.sh status --program alpha
expect_out "REQ-L1.4: status shows each watcher with its cadence and cost" "watcher${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}5m${tab}low${tab}running"
expect_out "REQ-L1.4: and the medium-cost sweep" "watcher${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}1h${tab}medium${tab}running"
expect_out "a refused event line is counted, beside the run's exit" "${tab}0${tab}1"
printf '%s\t0\t0\n' 1000 >"$wdir/$watch_slot.last"
mc_run mc-watch.sh status --program alpha --now 1400
expect_out "REQ-L1.4: a run past its cadence shows a negative time to the next, its expiry" "${tab}400${tab}-100${tab}0${tab}0"

# ---------------------------------------------------------------------------
# REQ-E1.5, REQ-E1.1: a killed watcher is an event, then re-armed within one
# pass; the event lands before the re-armed watcher runs.
# ---------------------------------------------------------------------------
old=$(rec_pid "$watch_slot")
kill "$old"
check "the killed watcher exits" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh status --program alpha
expect_out "a killed watcher shows stopped" "scripts/alpha-watch.sh${tab}5m${tab}low${tab}stopped"
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-E1.5: the stop is reported with its event" "stopped${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}e"
expect_out "REQ-E1.1: the watcher is re-armed in the same pass" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
order=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "stopped" { s = NR } $1 == "rearmed" { r = NR } END { print (s && r && s < r) ? "ok" : "bad" }')
check "REQ-E1.5: the stop is reported before the re-arm" test "$order" = ok
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.5: a watcher-stopped event lands in the attention store" "watcher-stopped${tab}alpha-duty${tab}scripts/alpha-watch.sh stopped"
new=$(rec_pid "$watch_slot")
if [ -n "$new" ] && [ "$new" != "$old" ] && kill -0 "$new" 2>/dev/null; then
  ok "REQ-E1.1: the re-armed watcher is a live new process"
else
  fail "REQ-E1.1: no live re-armed watcher"
fi
check "REQ-E1.1: the re-armed watcher runs" poll_until --what "the re-armed watcher's run" -- ran alpha-watch 2
check "REQ-E1.5: the stop event was in the store before the re-armed watcher ran" \
  grep -q '^alpha-duty 1$' "$WATCH_RUNS/alpha-watch"

# A process whose arguments merely end like the slot's loop is not trusted.
loop_pid=$(rec_pid "$watch_slot")
kill "$loop_pid" 2>/dev/null
check "the live loop exits" poll_until --what "the loop's exit" -- pid_gone "$loop_pid"
# shellcheck disable=SC2016 # the decoy's own script, expanded by it
/bin/bash -c 'sleep 30 & s=$!; trap "kill \$s; exit" TERM; wait' /x/mc-watch.sh loop --program alpha --slot "$watch_slot" &
decoy=$!
printf '%s\t1\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' "$decoy" >"$wdir/$watch_slot.rec"
mc_run mc-watch.sh pass --program alpha
expect_out "a decoy ending in the loop's arguments is not taken for it" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "and is left alone" kill -0 "$decoy"
kill "$decoy" 2>/dev/null
new=$(rec_pid "$watch_slot")

# A record whose pid now names some other process is not trusted as live.
printf '%s\t1\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' "$$" >"$wdir/$watch_slot.rec"
kill "$new" 2>/dev/null
mc_run mc-watch.sh pass --program alpha
expect_out "a recycled pid is not taken for the watcher" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "the process the stale record named is left alone" kill -0 "$$"

# ---------------------------------------------------------------------------
# REQ-L1.2: the budget rungs pause watchers by cost class; the spend class.
# ---------------------------------------------------------------------------
setup '[alpha-duty, fast-duty]' 'polls_per_hour: 20'
mc_run mc-watch.sh pass --program alpha
expect_out "a high-cost watcher is armed with headroom" "armed${tab}fast-duty${tab}scripts/heavy-watch.sh"
heavy_pid=$(rec_pid "$(slot_for heavy-watch.sh)")
check "the high-cost watcher starts its child" poll_until --what "the watcher's child" -- test -s "$WATCH_RUNS/heavy-child"
seed_polls_now 17
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: pause-watchers stops the high-cost watcher" "paused${tab}fast-duty${tab}scripts/heavy-watch.sh${tab}budget rung pause-watchers"
expect_out "REQ-L1.2: it leaves the medium-cost one" "running${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
check "REQ-L1.2: the paused watcher's process is stopped" poll_until --what "the paused watcher's exit" -- pid_gone "$heavy_pid"
heavy_child=$(cat "$WATCH_RUNS/heavy-child" 2>/dev/null)
if ! command -v setsid >/dev/null 2>&1; then
  ok "skipped: a stop takes a watcher's children only where setsid is available"
  [ -z "$heavy_child" ] || kill "$heavy_child" 2>/dev/null
elif [ -n "$heavy_child" ]; then
  check "a stop takes the watcher run's own children with it" poll_until --what "the watcher's child's exit" -- pid_gone "$heavy_child"
else
  fail "the high-cost watcher never recorded its child"
fi
sweep_pid=$(rec_pid "$(slot_for alpha-sweep.sh)")
mc_run mc-budget.sh record --program alpha context_steps 200
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: handover stops the medium-cost watcher too" "paused${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}budget rung handover"
expect_out "REQ-L1.2: the low-cost watcher keeps running" "running${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "REQ-L1.2: the medium-cost watcher's process is stopped" poll_until --what "the sweep's exit" -- pid_gone "$sweep_pid"
mc_run mc-budget.sh record --program alpha context_steps 0
: >"$fleet/mission-control/alpha/polls"
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: with headroom back the watcher is armed again" "armed${tab}alpha-duty${tab}scripts/alpha-sweep.sh"

setup '[alpha-duty]' 'spend_alpha_duty: low'
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: a watcher over its duty's spend class is not armed" "paused${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}above the low spend class"
expect_out "REQ-L1.2: one within it is" "armed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "REQ-L1.4: a pass keeps the budget file current" test -f "$fleet/mission-control/alpha/budget"

# ---------------------------------------------------------------------------
# REQ-E1.1: the runner and every live loop honour the daemon pause; a loop
# whose state is gone exits.
# ---------------------------------------------------------------------------
setup '[fast-duty]'
mc_run mc-watch.sh pass --program alpha
check "a 1s watcher runs repeatedly" poll_until --what "three fast runs" -- ran fast-watch 3
mc_run mc-event.sh list --program alpha
expect_out "an event on a last line with no newline still lands" "fast-due${tab}last-line"
fast_pid=$(rec_pid "$(slot_for fast-watch.sh)")
printf '%s\n' "fleet_daemon_pause: true" >>"$tracked"
# Let a run already past the gate finish, then hold a window: an assertion
# that nothing happens, so a fixed wait rather than a poll.
sleep 2
before=$(runs_of fast-watch)
sleep 3
if [ "$(runs_of fast-watch)" -eq "$before" ]; then
  ok "REQ-E1.1: a live watcher loop skips its runs under the pause"
else
  fail "REQ-E1.1: a watcher ran under the pause ($before then $(runs_of fast-watch) runs)"
fi
kill "$(rec_pid "$(slot_for heavy-watch.sh)")" 2>/dev/null
mc_run mc-watch.sh pass --program alpha
expect_eq "REQ-E1.1: a paused pass does nothing but say so" "paused"
mc_run mc-event.sh list --program alpha
expect_no_out "REQ-E1.1: no event is emitted under the pause" "watcher-stopped"
rm -rf "$wdir"
check "a loop whose state directory is gone exits" poll_until --what "the orphaned loop's exit" -- pid_gone "$fast_pid"

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

# ---------------------------------------------------------------------------
# REQ-C1.5: no runner, relay, snapshot or budget path calls a model. The gate
# is checked against one seeded file per spelling first, so it can fail.
# ---------------------------------------------------------------------------
no_model() { # no_model <file...>: the code lines that would start a model
  grep -nE '(^|[^A-Za-z0-9_.-])"?(/[A-Za-z0-9_./-]*/)?(claude|gemini|codex)"?([[:space:]]|$)|\$\{?[A-Z_]*(CLAUDE|MODEL|LLM)[A-Z_]*|offload-dispatch|mission-control-launch|fleet-[a-z-]*\.sh"?[[:space:]]+launch|anthropic' "$@" \
    | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#'
}
# shellcheck disable=SC2016 # the seeds are source text, never expanded
for seeded in 'claude -p "summarize"' '"claude" -p x' '/usr/local/bin/claude -p x' \
  'gemini -p x' 'codex exec x' '${CLAUDE_BIN:-claude} -p x' \
  '/bin/sh "$d/fleet-streamjson.sh" launch w s' 'fleet-tmux.sh launch w'; do
  printf '#!/bin/sh\n# claude is only named here\n%s\n' "$seeded" >"$tmp/seeded.sh"
  if no_model "$tmp/seeded.sh" >/dev/null; then
    ok "REQ-C1.5: the gate catches: $seeded"
  else
    fail "REQ-C1.5: the gate misses: $seeded"
  fi
done
found=$(no_model "$repo_root"/scripts/mc-watch.sh "$repo_root"/scripts/mc-wake.sh \
  "$repo_root"/scripts/mc-event.sh "$repo_root"/scripts/mc-snapshot.sh \
  "$repo_root"/scripts/mc-adapter-forge.sh "$repo_root"/scripts/mc-budget.sh \
  "$repo_root"/scripts/mc-lib.sh "$repo_root"/scripts/mc-duties.sh "$repo_root"/scripts/mc-program.sh)
if [ -z "$found" ]; then
  ok "REQ-C1.5: no runner step calls a model"
else
  fail "REQ-C1.5: a runner path names a model call: $found"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-watch: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-watch: all passed"
