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
# those pids, and only those, are stopped on the way out.
reap() {
  for rp_f in "$wdir"/*.rec; do
    [ -f "$rp_f" ] || continue
    rp_pid=$(cut -f1 "$rp_f")
    case $rp_pid in
      "" | *[!0-9]*) ;;
      *) kill "$rp_pid" 2>/dev/null ;;
    esac
  done
}
cleanup() {
  reap
  rm -rf "$tmp"
}
trap cleanup EXIT

tab=$(printf '\t')

# Fixture watchers: each run logs a line; alpha-watch also reports an event.
mkdir -p "$core/scripts" "$tmp/runs"
cat >"$core/scripts/alpha-watch.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$PLANWRIGHT_MC_DUTY" >>"$WATCH_RUNS/alpha-watch"
printf 'event\talpha-due\tpr-7\tseven is due\n'
printf 'chatter that is not an event\n'
EOF
cat >"$core/scripts/alpha-sweep.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/alpha-sweep"
EOF
WATCH_RUNS="$tmp/runs"
export WATCH_RUNS

# setup <duties> [budget]: program alpha with no snapshot source, so a pass
# reads no forge, and a host-load limit no host reaches.
setup() {
  reap
  reset_mc_fixture
  rm -rf "$fleet" "$tmp/runs"/*
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: $1
program_alpha_sources: {work-items: specs:record}
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

# ---------------------------------------------------------------------------
# REQ-E1.1: a pass arms every armed duty's watchers; an `off` duty arms none.
# ---------------------------------------------------------------------------
setup '[alpha-duty, beta-duty]'
mc_run mc-watch.sh pass --program alpha
expect_rc "REQ-E1.1: a pass" 0
expect_out "REQ-E1.1: the live duty's first watcher is armed" "armed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
expect_out "REQ-E1.1: its second watcher is armed" "armed${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
expect_no_out "REQ-E1.1: an off duty arms nothing" "beta-duty"
if poll_until --what "the first watcher run" -- ran alpha-watch 1; then
  ok "REQ-E1.1: an armed watcher runs"
else
  fail "REQ-E1.1: the armed watcher never ran"
fi
if poll_until --what "the watcher's event" -- sh -c "grep -q 'alpha-due' '$fleet'/attention/mission-control/alpha/events/e* 2>/dev/null"; then
  ok "REQ-E1.2: the watcher's declared event lands in the attention store"
else
  fail "REQ-E1.2: the watcher's event never landed"
fi
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.2: the event carries its kind, subject and text" "alpha-due${tab}pr-7${tab}seven is due"
expect_no_out "REQ-E1.2: a line that is not an event is ignored" "chatter"
watch_slot=$(slot_for alpha-watch.sh)
if [ "$(cat "$WATCH_RUNS/alpha-watch")" = alpha-duty ]; then
  ok "the watcher is told its duty"
else
  fail "PLANWRIGHT_MC_DUTY not passed"
fi

mc_run mc-watch.sh pass --program alpha
expect_out "REQ-E1.1: a second pass leaves a live watcher running" "running${tab}alpha-duty${tab}scripts/alpha-watch.sh"
expect_no_out "REQ-E1.1: nothing is re-armed while it runs" "rearmed"

mc_run mc-watch.sh status --program alpha
expect_out "REQ-L1.4: status shows each watcher with its cadence and cost" "watcher${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}5m${tab}low${tab}running"
expect_out "REQ-L1.4: and the medium-cost sweep" "watcher${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}1h${tab}medium${tab}running"

# ---------------------------------------------------------------------------
# REQ-E1.5, REQ-E1.1: a killed watcher is an event, then re-armed within one
# pass.
# ---------------------------------------------------------------------------
old=$(rec_pid "$watch_slot")
kill "$old"
poll_until --what "the killed watcher's exit" -- pid_gone "$old" || fail "the killed watcher outlived its kill"
mc_run mc-watch.sh status --program alpha
expect_out "a killed watcher shows stopped" "scripts/alpha-watch.sh${tab}5m${tab}low${tab}stopped"
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-E1.5: the stop is reported with its event" "stopped${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}e"
expect_out "REQ-E1.1: the watcher is re-armed in the same pass" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
order=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "stopped" { s = NR } $1 == "rearmed" { r = NR } END { print (s && r && s < r) ? "ok" : "bad" }')
if [ "$order" = ok ]; then
  ok "REQ-E1.5: the event comes before the re-arm"
else
  fail "REQ-E1.5: the re-arm preceded the event"
fi
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.5: a watcher-stopped event lands in the attention store" "watcher-stopped${tab}alpha-duty${tab}scripts/alpha-watch.sh stopped"
new=$(rec_pid "$watch_slot")
if [ -n "$new" ] && [ "$new" != "$old" ] && kill -0 "$new" 2>/dev/null; then
  ok "REQ-E1.1: the re-armed watcher is a live new process"
else
  fail "REQ-E1.1: no live re-armed watcher"
fi
if poll_until --what "the re-armed watcher's run" -- ran alpha-watch 2; then
  ok "REQ-E1.1: the re-armed watcher runs"
else
  fail "REQ-E1.1: the re-armed watcher never ran"
fi

# A record whose pid now names some other process is not trusted as live.
printf '%s\t1\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' "$$" >"$wdir/$watch_slot.rec"
kill "$new" 2>/dev/null
mc_run mc-watch.sh pass --program alpha
expect_out "a recycled pid is not taken for the watcher" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
if kill -0 "$$"; then
  ok "the process the stale record named is left alone"
else
  fail "the runner signalled a stranger"
fi

# ---------------------------------------------------------------------------
# REQ-L1.2: the budget rungs pause watchers by cost class; the spend ceiling.
# ---------------------------------------------------------------------------
sweep_slot=$(slot_for alpha-sweep.sh)
sweep_pid=$(rec_pid "$sweep_slot")
mc_run mc-budget.sh record --program alpha sessions 4
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: hold-dispatch pauses the medium-cost watcher" "paused${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}budget rung hold-dispatch"
expect_out "REQ-L1.2: the low-cost watcher keeps running" "running${tab}alpha-duty${tab}scripts/alpha-watch.sh"
if poll_until --what "the paused sweep's exit" -- pid_gone "$sweep_pid"; then
  ok "REQ-L1.2: the paused watcher's process is stopped"
else
  fail "REQ-L1.2: the paused watcher still runs"
fi
mc_run mc-budget.sh record --program alpha sessions 0
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: with headroom back the watcher is armed again" "armed${tab}alpha-duty${tab}scripts/alpha-sweep.sh"

setup '[alpha-duty]' 'spend_alpha_duty: low'
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: a watcher over its duty's spend class is not armed" "paused${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}above the low spend ceiling"
expect_out "REQ-L1.2: one within it is" "armed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
if [ -f "$fleet/mission-control/alpha/budget" ]; then
  ok "REQ-L1.4: a pass keeps the budget file current"
else
  fail "REQ-L1.4: no budget file after a pass"
fi

# ---------------------------------------------------------------------------
# REQ-E1.1: the runner honours the daemon pause.
# ---------------------------------------------------------------------------
watch_slot=$(slot_for alpha-watch.sh)
paused_pid=$(rec_pid "$watch_slot")
printf '%s\n' "fleet_daemon_pause: true" >>"$tracked"
kill "$paused_pid"
poll_until --what "the watcher's exit" -- pid_gone "$paused_pid" || fail "the watcher outlived its kill"
mc_run mc-watch.sh pass --program alpha
expect_eq "REQ-E1.1: a paused pass does nothing but say so" "paused"
if [ "$(rec_pid "$watch_slot")" = "$paused_pid" ]; then
  ok "REQ-E1.1: nothing is re-armed under the pause"
else
  fail "REQ-E1.1: a watcher was re-armed under the pause"
fi
mc_run mc-event.sh list --program alpha
expect_no_out "REQ-E1.1: no event is emitted under the pause" "watcher-stopped"

# ---------------------------------------------------------------------------
# A duty the program no longer enables is disarmed; stop stops them all.
# ---------------------------------------------------------------------------
setup '[alpha-duty]'
mc_run mc-watch.sh pass --program alpha
sweep_pid=$(rec_pid "$(slot_for alpha-sweep.sh)")
sed 's/^program_alpha_duties: .*/program_alpha_duties: [beta-duty]/' "$tracked" >"$tmp/t" && cp "$tmp/t" "$tracked"
mc_run mc-watch.sh pass --program alpha
expect_out "a disabled duty's watchers are disarmed" "disarmed${tab}alpha-duty"
if poll_until --what "the disarmed watcher's exit" -- pid_gone "$sweep_pid"; then
  ok "the disarmed watcher's process is stopped"
else
  fail "a disarmed watcher still runs"
fi
if ls "$wdir"/*.rec >/dev/null 2>&1; then
  fail "a disarmed watcher kept its record"
else
  ok "no record is left"
fi

setup '[alpha-duty]'
mc_run mc-watch.sh pass --program alpha
pids=$(cut -f1 "$wdir"/*.rec)
mc_run mc-watch.sh stop --program alpha
expect_rc "stop" 0
# shellcheck disable=SC2086 # one pid per word
if poll_until --what "every stopped watcher's exit" -- pid_gone $pids; then
  ok "stop ends every watcher"
else
  fail "a watcher outlived stop"
fi

# ---------------------------------------------------------------------------
# REQ-C1.5: no runner, watcher-relay, snapshot or budget path calls a model.
# The gate is checked against a seeded file first, so it can fail.
# ---------------------------------------------------------------------------
no_model() { # no_model <file...>: the code lines that would start a model
  grep -nE '(^|[^A-Za-z0-9_./-])claude([[:space:]]|$)|offload-dispatch|mission-control-launch|streamjson\.sh"?[[:space:]]+launch|anthropic' "$@" \
    | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#'
}
printf '#!/bin/sh\n# claude is only named here\nclaude -p "summarize"\n' >"$tmp/seeded.sh"
if no_model "$tmp/seeded.sh" >/dev/null; then
  ok "REQ-C1.5: the gate catches a seeded model call"
else
  fail "REQ-C1.5: the gate misses a seeded model call"
fi
found=$(no_model "$repo_root"/scripts/mc-watch.sh "$repo_root"/scripts/mc-wake.sh \
  "$repo_root"/scripts/mc-event.sh "$repo_root"/scripts/mc-snapshot.sh \
  "$repo_root"/scripts/mc-adapter-forge.sh "$repo_root"/scripts/mc-budget.sh "$repo_root"/scripts/mc-lib.sh)
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
