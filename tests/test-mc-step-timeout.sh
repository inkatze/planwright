#!/bin/bash
# Tests for the runner's step timeout: a watcher run or a snapshot refresh
# that runs past its timeout knob is stopped, the expiry is an event, the
# pass's other watchers still run, and the watcher runs again on its next
# cadence (mission-control REQ-E1.6, REQ-E1.5; D-40).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-step-timeout.sh
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

# A watcher that never returns, recording when it started and the pid of the
# child it hangs on, a child that ignores TERM.
cat >"$core/scripts/hang-watch.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$(date +%s)" >>"$WATCH_RUNS/hang-start"
printf 'run\n' >>"$WATCH_RUNS/hang-watch"
(trap '' TERM; exec sleep 60) &
printf '%s\n' "$!" >>"$WATCH_RUNS/hang-child"
wait
EOF

# setup_hang <knob lines>: a duty with the hanging watcher and a fast one,
# both on a one-second cadence, and the knob lines in the repo layer.
setup_hang() {
  setup '[hang-duty]'
  cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
duties:
  - id: hang-duty
    summary: "A duty whose first watcher hangs"
    triggers: []
    watchers: [scripts/hang-watch.sh@1s/low, scripts/fast-watch.sh@1s/low]
    wake: none
    rules: []
    kinds: []
    files: hang
    lifecycle: live
    never-propose: false
EOF
  printf '%s\n' "$1" >>"$tracked"
}

# ---------------------------------------------------------------------------
# REQ-E1.6: the default knob stops a hung watcher run within a second of it,
# the event names the expiry, the other watcher keeps running, and the hung
# one runs again.
# ---------------------------------------------------------------------------
# The snapshot refresh keeps a generous override: a loaded host takes a
# couple of seconds over it, which is not what these cases measure.
setup_hang 'mission_control_step_timeout: 2
mission_control_step_timeout_overrides: {snapshot: 120}'
mc_run mc-watch.sh pass --program alpha
expect_rc "REQ-E1.6: a pass arms the hanging watcher" 0
hang_slot=$(slot_for hang-watch.sh)
check "the hung run's end is recorded" poll_until --what "the stopped run's record" -- test -s "$wdir/$hang_slot.last"
started=$(head -n 1 "$WATCH_RUNS/hang-start")
IFS="$tab" read -r stopped_at last_rc _ <"$wdir/$hang_slot.last"
if [ $((stopped_at - started)) -le 3 ]; then
  ok "REQ-E1.6: the run was stopped within a second of the 2s knob"
else
  fail "REQ-E1.6: the run ended $((stopped_at - started))s after it started, past the 2s knob"
fi
check "REQ-E1.6: the stopped run did not exit cleanly" test "$last_rc" != 0
hang_child=$(head -n 1 "$WATCH_RUNS/hang-child")
check "REQ-E1.6: the hung run's own child, which ignored the TERM, is killed" poll_until --deadline 10 --what "the hung child's exit" -- pid_gone "$hang_child"
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.5: the expiry is an event naming the duty" "watcher-timeout${tab}hang-duty${tab}scripts/hang-watch.sh ran past 2s and was stopped"
check "REQ-E1.6: the pass's other watcher still runs" poll_until --what "the fast watcher's run" -- ran fast-watch 2
check "REQ-E1.6: the stopped watcher runs again on its next cadence" poll_until --what "the second hung run" -- ran hang-watch 2

# ---------------------------------------------------------------------------
# REQ-E1.6: a per-watcher override beats the default knob.
# ---------------------------------------------------------------------------
setup_hang 'mission_control_step_timeout: 300
mission_control_step_timeout_overrides: {hang-duty: 2, snapshot: 120}'
mc_run mc-watch.sh pass --program alpha
hang_slot=$(slot_for hang-watch.sh)
check "an override's run is stopped although the default is 300s" poll_until --what "the stopped run's record" -- test -s "$wdir/$hang_slot.last"
mc_run mc-event.sh list --program alpha
expect_out "the override's expiry is an event" "watcher-timeout${tab}hang-duty${tab}scripts/hang-watch.sh ran past 2s and was stopped"

# An override that is no count of seconds is ignored: the default applies.
setup_hang 'mission_control_step_timeout: 2
mission_control_step_timeout_overrides: {hang-duty: soon, snapshot: 120}'
mc_run mc-watch.sh pass --program alpha
hang_slot=$(slot_for hang-watch.sh)
check "a watcher with an invalid override is stopped at the default" poll_until --what "the stopped run's record" -- test -s "$wdir/$hang_slot.last"
mc_run mc-event.sh list --program alpha
expect_out "and the expiry names the default" "watcher-timeout${tab}hang-duty${tab}scripts/hang-watch.sh ran past 2s and was stopped"

# A default that is no count of seconds fails the read, named.
setup_hang 'mission_control_step_timeout: soon'
mc_run mc-watch.sh pass --program alpha
expect_rc "an invalid repo-layer default fails the pass" 1
expect_err "and names the knob" "mission_control_step_timeout"

# ---------------------------------------------------------------------------
# REQ-E1.6: a hung snapshot refresh is stopped the same way, the pass goes
# on, and the next pass refreshes.
# ---------------------------------------------------------------------------
setup '[beta-duty]' '' '{work-items: tracker:snapshot}'
printf '%s\n' 'mission_control_step_timeout_overrides: {snapshot: 8}' >>"$tracked"
cat >"$repo/scripts/tracker-adapter.sh" <<'EOF'
#!/bin/sh
trap 'date +%s >"$WATCH_RUNS/adapter-term"; exit 143' TERM
date +%s >"$WATCH_RUNS/adapter-start"
sleep 60 &
printf '%s\n' "$!" >>"$WATCH_RUNS/adapter-child"
wait
EOF
mc_run mc-wake.sh target add --program alpha ghost
mc_run mc-event.sh emit --program alpha pr-ready pr-1
mc_run mc-watch.sh pass --program alpha
expect_rc "REQ-E1.6: a pass with a hung refresh fails" 1
expect_out "the stopped refresh is reported" "snapshot${tab}timeout${tab}8"
adapter_started=$(cat "$WATCH_RUNS/adapter-start")
adapter_stopped=""
[ ! -s "$WATCH_RUNS/adapter-term" ] || adapter_stopped=$(cat "$WATCH_RUNS/adapter-term")
if [ -z "$adapter_stopped" ]; then
  fail "REQ-E1.6: the refresh recorded no TERM"
elif [ $((adapter_stopped - adapter_started)) -le 9 ]; then
  ok "REQ-E1.6: the refresh was stopped within a second of the 8s knob"
else
  fail "REQ-E1.6: the refresh was stopped $((adapter_stopped - adapter_started))s after it started, past the 8s knob"
fi
expect_out "REQ-E1.6: the rest of the pass still runs" "wake${tab}unreachable${tab}ghost"
adapter_child=$(head -n 1 "$WATCH_RUNS/adapter-child")
check "the hung adapter's child is stopped" poll_until --deadline 10 --what "the adapter child's exit" -- pid_gone "$adapter_child"
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.5: the refresh expiry is an event" "snapshot-timeout${tab}snapshot${tab}the snapshot refresh ran past 8s and was stopped"
grep -v '^mission_control_step_timeout_overrides:' "$tracked" >"$tmp/tracked.next" && mv "$tmp/tracked.next" "$tracked"
cat >"$repo/scripts/tracker-adapter.sh" <<'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  [ "$1" = --out ] && out=$2
  shift
done
printf 'item\tT-1\topen\n' >"$out"
EOF
mc_run mc-watch.sh pass --program alpha
expect_rc "REQ-E1.6: the next pass runs again" 0
expect_out "and refreshes the snapshot" "snapshot${tab}refreshed${tab}tracker"

# The expiry events are routine: the runner re-arms the step itself, so they
# wake no session.
for kind in watcher-timeout snapshot-timeout; do
  if awk -F '\t' -v k="$kind" '$1 == k && $2 == "routine" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv"; then
    ok "$kind is a routine event"
  else
    fail "$kind has no routine row in config/mc-event-classes.tsv"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
