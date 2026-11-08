#!/bin/bash
# Tests for the panel's health line (scripts/mc-panel.sh health, and the
# health records of its digest): each check flags at its bound and clears
# just below it, names its count and worst offender, and a store it cannot
# read reads unknown, never within bounds.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-panel-health.sh
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
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-snapshot-fixture.sh
. "$here/lib/mc-snapshot-fixture.sh"

T=100000
# Above any pid_max, so no process can hold it.
dead_pid=2147483646
home=$fixhome/.config/planwright/mission-control/alpha
runtime=$fleet/mission-control/alpha

fresh() {
  setup
  rm -rf "$home"
  mkdir -p "$runtime" "$fleet/attention" "$home/kb"
  # The registry exists, empty of any session the checks would see.
  mc_run fleet-state.sh register w-seed flight:seed --backend print --death-handle none
}
# reg <epoch> <worker> <scope> <handle>: a registry row registered then.
reg() { printf '%s\t%s\t%s\t-\tstream-json\t-\t%s\n' "$1" "$2" "$3" "$4" >>"$fleet/registry"; }
# attn <worker> <state> <epoch> [<reason>]: an attention row, the reason at
# field 9.
attn() {
  if [ $# -ge 4 ]; then
    printf '%s\t%s\t%s\t%s\t\t\t\t\t%s\n' "$1" "flight:x" "$2" "$3" "$4" >>"$fleet/attention/state"
  else
    printf '%s\t%s\t%s\t%s\n' "$1" "flight:x" "$2" "$3" >>"$fleet/attention/state"
  fi
}
health_at() { mc_run mc-panel.sh health --program alpha --now "$1"; }
expect_empty() {
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    ok "$1"
  else
    fail "$1: exit $RC, stdout '$OUT', stderr '$ERR'"
  fi
}

# ---------------------------------------------------------------------------
# All well: no record, and an empty line.
# ---------------------------------------------------------------------------
fresh
reg $((T - 60)) w-young flight:young "process $$"
health_at "$T"
expect_empty "the health line is empty when every check is within its bound"
mc_run mc-panel.sh digest --program alpha --now "$T"
expect_no_out "an all-well digest carries no health record" "health${tab}"
expect_no_out "an all-well line says nothing of health" "health:"

# ---------------------------------------------------------------------------
# worker-age: a live worker registered past the bound (4h by default).
# ---------------------------------------------------------------------------
fresh
reg $((T - 14400)) w-old flight:old "process $$"
reg $((T - 20000)) w-dead flight:dead "process $dead_pid"
reg $((T - 14400)) mission-control-task-11 mission-control:task-11 "process $$"
reg $((T - 30000)) mc-alpha-mission-control-0123456789 flight:hub "process $$"
reg $((T - 30000)) w-hub gen-2-90000-ab12 "process $$"
# Bounds are cached at the first read's time, so each check is read below
# its bound first, where the later read still hits the cache.
health_at $((T - 1))
expect_empty "worker-age clears just below its bound"
health_at "$T"
expect_out "worker-age flags a live worker at its bound, naming the oldest" "2 workers live 4h or more (oldest w-old, 4h)"
expect_out "a worker of the mission-control spec is still a worker" "2 workers live"
expect_no_out "a dead worker is no live worker" "w-dead"
expect_no_out "a session named for mission control is never a stale worker" "mc-alpha-mission-control"
expect_no_out "a session on a mission control scope is never a stale worker" "w-hub"
mc_run mc-panel.sh digest --program alpha --now "$T"
record() {
  rc_want=$(printf '%s\t' "$@")
  rc_want=${rc_want%"$tab"}
  if printf '%s\n' "$OUT" | grep -qxF -- "$rc_want"; then ok "the digest record $1 $2"; else fail "no digest line '$rc_want'"; fi
}
record health worker-age 2 w-old "2 workers live 4h or more (oldest w-old, 4h)"
expect_out "the line form carries the health text" "; health: 2 workers live 4h or more"

# ---------------------------------------------------------------------------
# idle: a live session idle past the bound (30m).
# ---------------------------------------------------------------------------
fresh
reg $((T - 60)) w-idle flight:idle "process $$"
reg $((T - 60)) w-gone flight:gone "process $dead_pid"
attn w-idle idle $((T - 1800))
attn w-gone idle $((T - 9000))
health_at $((T - 1))
expect_empty "idle clears just below its bound"
health_at "$T"
expect_out "idle flags a live idle session at its bound" "1 session idle 30m or more (longest w-idle, 30m)"
expect_no_out "an idle session whose process is gone is not counted" "w-gone"

# ---------------------------------------------------------------------------
# after-merge: live past the grace (10m) after a merge the attention store
# saw, or at once after a landing the keeper recorded.
# ---------------------------------------------------------------------------
fresh
reg $((T - 60)) w-merged flight:merged "process $$"
attn w-merged merged $((T - 600))
health_at $((T - 1))
expect_empty "after-merge clears inside the grace"
health_at "$T"
expect_out "after-merge flags a live worker at the grace after its merge" "1 worker still live after the pull request landed (w-merged, merged 10m ago)"
reg $((T - 60)) w-landed flight:landed "process $$"
printf 'w-landed\tacme/repo#7\tCLOSED\theld\n' >"$runtime/keeper-announced"
health_at $((T - 1))
expect_out "a held landing with no keeper ledger is unknown" "workers after their merge unknown (the keeper's ledger cannot be read)"
printf '# format: 1\nw-landed\tacme/repo\t7\t/nowhere\n' >"$runtime/keeper.tsv"
health_at $((T - 1))
expect_out "a landing the keeper recorded flags its live worker at once" "1 worker still live after the pull request landed (w-landed, pull request closed)"
health_at "$T"
expect_out "the keeper's landing is the worst offender, with the count of both" "2 workers still live after the pull request landed (w-landed"

# ---------------------------------------------------------------------------
# permissions: a permission prompt pending past the bound (5m).
# ---------------------------------------------------------------------------
fresh
attn w-ask awaiting-input $((T - 300)) permission
attn w-ask2 awaiting-input $((T - 400)) permission
attn w-fork awaiting-input $((T - 9000)) fork
health_at $((T - 1))
expect_out "a prompt is counted from its bound, its session registered or not" "1 permission prompt waiting 5m or more (longest w-ask2, 7m)"
health_at "$T"
expect_out "permissions flags prompts at their bound, naming the longest" "2 permission prompts waiting 5m or more (longest w-ask2, 7m)"
expect_no_out "a question that is no permission prompt is not counted" "w-fork"

# ---------------------------------------------------------------------------
# mc-stuck: the program's mission control held on its own dialog (5m),
# read only while the escalation watcher runs.
# ---------------------------------------------------------------------------
fresh
mkdir -p "$runtime/escalate" "$runtime/watchers"
printf '%s\t%s\tsession-keeper\tscripts/mc-escalate.sh\t1m\tlow\n' "$$" $((T - 3600)) >"$runtime/watchers/session-keeper.1.rec"
printf '%s\t0\t0\n' $((T - 30)) >"$runtime/watchers/session-keeper.1.last"
health_at "$T"
expect_empty "mc-stuck is quiet with its watcher running and no record"
printf 'dialog\t%s\t-\t0123456789abcdef\tauto-mode\n' $((T - 300)) >"$runtime/escalate/self"
health_at $((T - 1))
expect_empty "mc-stuck clears just below its bound"
health_at "$T"
expect_out "mc-stuck flags the mission control at its bound" "mission control alpha held on its own auto-mode prompt for 5m"
printf 'dialog\t%s\t%s\t0123456789abcdef\tdialog\n' $((T - 900)) "$$" >"$runtime/escalate/self"
health_at "$T"
expect_out "mc-stuck names a dialog that is no auto-mode prompt" "mission control alpha held on its own dialog for 15m"
printf 'dialog\t%s\t%s\t0123456789abcdef\tdialog\n' $((T - 900)) "$dead_pid" >"$runtime/escalate/self"
health_at "$T"
expect_empty "a record left by a session that is gone is not stuck"
printf '%s\t0\t0\n' $((T - 180)) >"$runtime/watchers/session-keeper.1.last"
health_at "$T"
expect_empty "a watcher last run at twice its cadence plus a minute still counts"
printf '%s\t0\t0\n' $((T - 181)) >"$runtime/watchers/session-keeper.1.last"
health_at "$T"
expect_out "a watcher that has not run within twice its cadence plus a minute makes it unknown" "own dialog unknown (the escalation watcher last ran 3m ago)"
printf '%s\t1\t0\n' $((T - 30)) >"$runtime/watchers/session-keeper.1.last"
health_at "$T"
expect_out "a failed watcher run makes it unknown" "own dialog unknown (the escalation watcher's last run failed)"
rm -f "$runtime/watchers/session-keeper.1.last"
health_at "$T"
expect_out "a watcher that has not run yet makes it unknown" "own dialog unknown (the escalation watcher has not run)"
printf '%s\t0\t0\n' $((T - 30)) >"$runtime/watchers/session-keeper.1.last"
rm -f "$runtime/escalate/self"
ln -s /etc/hostname "$runtime/escalate/self"
health_at "$T"
expect_out "a symlinked escalation record is unknown" "own dialog unknown (the escalation record cannot be read)"
rm -f "$runtime/escalate/self" "$runtime/watchers"/*
printf 'dialog\t%s\t-\t0123456789abcdef\tdialog\n' $((T - 900)) >"$runtime/escalate/self"
health_at "$T"
expect_out "a record with no escalation watcher armed is unknown, never fine" "own dialog unknown (no escalation watcher is armed)"

# ---------------------------------------------------------------------------
# context: every mission control's reading against its handover threshold.
# ---------------------------------------------------------------------------
fresh
mc_run mc-panel.sh presence --program alpha --refresh --context 42 --threshold 70 --now "$T"
expect_rc "presence takes the context reading" 0
if [ "$(awk -F '\t' '$1 == "percent" || $1 == "threshold" { printf "%s=%s ", $1, $2 }' "$runtime/context")" = "percent=42 threshold=70 " ]; then
  ok "presence writes the reading and its threshold"
else
  fail "the context reading is '$(cat "$runtime/context")'"
fi
mc_run mc-panel.sh presence --program alpha --refresh --context 42 --now "$T"
expect_rc "a context reading without its threshold is refused" 2
mc_run mc-panel.sh presence --program alpha --refresh --threshold 70 --now "$T"
expect_rc "a threshold without its context reading is refused" 2
for bad in "101 70" "4x 70" "42 0" "42 101"; do
  mc_run mc-panel.sh presence --program alpha --refresh --context "${bad% *}" --threshold "${bad#* }" --now "$T"
  expect_rc "presence refuses the context pair '$bad'" 2
done
mc_run mc-panel.sh presence --program alpha --refresh --context - --threshold - --now "$T"
if [ "$RC" -eq 0 ] && [ "$(awk -F '\t' '$1 == "percent" || $1 == "threshold" { printf "%s=%s ", $1, $2 }' "$runtime/context")" = "percent=- threshold=- " ]; then
  ok "presence takes an unmeasured reading and no threshold"
else
  fail "the unmeasured reading: exit $RC, '$(cat "$runtime/context")'"
fi
OUT=$(mc_env env CLAUDE_PID=$$ /bin/bash "$repo_root/scripts/mc-panel.sh" presence --program alpha --refresh --context 42 --threshold 70 --now "$T" 2>&1)
if [ "$(awk -F '\t' '$1 == "pid" { print $2 }' "$runtime/context")" = "$$" ]; then
  ok "presence records the session's process"
else
  fail "the context reading's pid: '$(cat "$runtime/context")' ($OUT)"
fi
mkdir -p "$fleet/mission-control/beta" "$fleet/mission-control/gamma" "$fleet/mission-control/delta"
printf 'format\t1\nwritten\t%s\npercent\t70\nthreshold\t70\npid\t-\n' $((T - 10)) >"$fleet/mission-control/beta/context"
# One that compacts rather than hands over, and a stale one whose session is gone.
printf 'format\t1\nwritten\t%s\npercent\t99\nthreshold\t-\npid\t-\n' $((T - 10)) >"$fleet/mission-control/gamma/context"
printf 'format\t1\nwritten\t%s\npercent\t99\nthreshold\t70\npid\t%s\n' $((T - 1000)) "$dead_pid" >"$fleet/mission-control/delta/context"
health_at "$T"
expect_out "context flags a mission control at its threshold" "1 mission control at or past the handover context (beta 70% of 70%)"
expect_no_out "a session that compacts is not compared" "gamma"
expect_no_out "a stale reading whose session is gone is no mission control" "delta"
printf 'format\t1\nwritten\t%s\npercent\t69\nthreshold\t70\npid\t-\n' $((T - 10)) >"$fleet/mission-control/beta/context"
health_at "$T"
expect_empty "context clears just below the threshold"
printf 'format\t1\nwritten\t%s\npercent\tlots\nthreshold\t70\npid\t-\n' $((T - 10)) >"$fleet/mission-control/beta/context"
health_at "$T"
expect_out "a fresh reading outside its grammar is unknown" "context unknown for beta"
printf 'format\t1\nwritten\t%s\npercent\t69\nthreshold\t70\npid\t-\n' $((T - 10)) >"$fleet/mission-control/beta/context"
printf 'format\t1\nwritten\t%s\npercent\t10\nthreshold\t70\npid\t%s\n' $((T - 1000)) "$$" >"$fleet/mission-control/delta/context"
health_at "$T"
expect_out "a stale reading from a live session is unknown" "context unknown for delta"
printf 'format\t1\nwritten\t%s\npercent\t10\nthreshold\t70\npid\t-\n' $((T - 1000)) >"$fleet/mission-control/delta/context"
health_at "$T"
expect_out "a stale reading naming no session is unknown" "context unknown for delta"
printf 'format\t1\nwritten\t%s\npercent\t10\nthreshold\t70\npid\t-\n' $((T - 90000)) >"$fleet/mission-control/delta/context"
health_at "$T"
expect_empty "a reading naming no session is gone after a day"
rm -f "$runtime/context"
mkdir "$runtime/context"
mc_run mc-panel.sh presence --program alpha --refresh --context 42 --threshold 70 --now "$T"
expect_rc "a directory in the context reading's place is refused" 1

# ---------------------------------------------------------------------------
# ci-queue: the throughput measure's median queue against median run.
# ---------------------------------------------------------------------------
fresh
mkdir -p "$home/kb/throughput"
measure() { # measure <measured> <source state> <ci line>...
  m_at=$1
  m_src=$2
  shift 2
  {
    printf '# format: 1\nmeasured\t%s\nsource\tci\t%s\t%s\n' "$m_at" "$m_src" "$([ "$m_src" = ok ] && echo - || echo "gh is not signed in")"
    for m_l in "$@"; do printf '%s\n' "$m_l"; done
  } >"$home/kb/throughput/measure.tsv"
}
measure $((T - 100)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}600" "ci${tab}lint${tab}5${tab}100${tab}500${tab}100${tab}150"
health_at "$T"
expect_out "ci-queue flags a job queued for its share of the run, naming it" "1 CI job queued for 50% or more of their run (CI / gate: queue 5m, run 10m)"
expect_no_out "a job under the queue floor is not flagged" "lint"
measure $((T - 100)) ok "ci${tab}CI / gate${tab}5${tab}299${tab}1500${tab}400${tab}600"
health_at "$T"
expect_empty "ci-queue clears just below its share"
measure $((T - 100)) ok "ci${tab}CI / gate${tab}5${tab}120${tab}1500${tab}400${tab}200" "ci${tab}lint${tab}5${tab}119${tab}500${tab}100${tab}200"
health_at "$T"
expect_out "a job at the queue floor is flagged" "1 CI job queued for 50% or more of their run (CI / gate: queue 2m, run 3m)"
expect_no_out "a job just under the queue floor is not" "lint"
measure $((T - 100)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}-"
health_at "$T"
expect_out "a queued job with no finished run is flagged" "(CI / gate: queue 5m, no finished run)"
measure $((T - 100)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}0"
health_at "$T"
expect_out "a run of no time is a run" "(CI / gate: queue 5m, run 0s)"
c1=$(printf '\302\233')
measure $((T - 100)) ok "ci${tab}x$(printf '\302\302\233\233')[2Jy${tab}5${tab}300${tab}1500${tab}400${tab}600"
health_at "$T"
expect_out "a job name's controls are dropped" "(x[2Jy: queue 5m"
expect_no_out "a nested C1 pair is not rebuilt" "$c1"
measure $((T - 7200)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}600"
health_at "$T"
expect_out "a measure at twice its cadence still counts" "1 CI job queued"
measure $((T - 7201)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}600"
health_at "$T"
expect_out "a measure older than twice its cadence is unknown" "CI queue times unknown (the throughput measure is 2h old)"
measure $((T - 100)) unknown
health_at "$T"
expect_out "a CI source the measure could not read is unknown" "CI queue times unknown (gh is not signed in)"
printf 'not a measure\n' >"$home/kb/throughput/measure.tsv"
health_at "$T"
expect_out "a measure of another format is unknown" "CI queue times unknown (the throughput measure cannot be read)"
# An armed watcher on a short cadence: the duty's hourly interval still
# sets the staleness, and a measure not written yet is unknown.
mkdir -p "$runtime/watchers"
printf '%s\t%s\tthroughput\tscripts/mc-throughput.sh\t15m\tlow\n' "$$" $((T - 3600)) >"$runtime/watchers/throughput.1.rec"
printf '%s\t0\t0\n' $((T - 60)) >"$runtime/watchers/throughput.1.last"
measure $((T - 7000)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}600"
health_at "$T"
expect_out "a 15m watcher does not make an hour-old measure stale" "1 CI job queued"
rm -f "$home/kb/throughput/measure.tsv"
health_at "$T"
expect_out "an armed watcher with no measure yet is unknown" "CI queue times unknown (no throughput measure yet)"

# ---------------------------------------------------------------------------
# Live and ended: a session the attention store calls pr-ready is probed
# like any other.
# ---------------------------------------------------------------------------
fresh
reg $((T - 14400)) w-ready flight:ready "process $$"
attn w-ready pr-ready $((T - 100))
health_at "$T"
expect_out "a live pr-ready worker is still aged" "1 worker live 4h or more (oldest w-ready, 4h)"
mc_run mc-panel.sh digest --program alpha --now "$T"
expect_no_out "a pr-ready worker is not drawn in flight" "flight${tab}w-ready"

# ---------------------------------------------------------------------------
# A relaunch restarts a worker's age; a re-register on the same handle does
# not. A keeper landing of MERGED names it.
# ---------------------------------------------------------------------------
fresh
reg $((T - 20000)) w-re flight:re "process $$"
printf '%s\t%s\t%s\t-\tstream-json\t-\t%s\tclosed\n' $((T - 19000)) w-re flight:re "process $$" >>"$fleet/registry"
reg $((T - 60)) w-re flight:re "process $$"
reg $((T - 20000)) w-rl flight:rl "process $dead_pid"
reg $((T - 60)) w-rl flight:rl "process $$"
reg $((T - 20000)) w-same flight:same "process $$"
reg $((T - 60)) w-same flight:same "process $$"
health_at "$T"
expect_out "a re-register on the same handle keeps its age" "1 worker live 4h or more (oldest w-same, 6h)"
expect_no_out "a re-register after a retirement restarts the age" "w-re"
expect_no_out "a relaunch on a new handle restarts the age" "w-rl"
printf 'w-same\tacme/repo#8\tMERGED\theld\nw-rl\tacme/repo#9\tMERGED\tretired\n' >"$runtime/keeper-announced"
printf '# format: 1\nw-same\tacme/repo\t8\t/nowhere\n' >"$runtime/keeper.tsv"
health_at "$T"
expect_out "a keeper landing of a merge names it" "1 worker still live after the pull request landed (w-same, pull request merged)"
expect_no_out "a live session under a name the keeper retired is a relaunch" "w-rl,"
printf 'w-same\tacme/repo#8\tMERGED\theld\n' >"$runtime/keeper-announced"
printf '# format: 1\nw-same\tacme/repo\t8\t/nowhere\tretired\n' >"$runtime/keeper.tsv"
health_at "$T"
expect_no_out "a held reclaim after the retire went through is a relaunch" "w-same, pull request"
printf 'not a ledger\n' >"$runtime/keeper.tsv"
health_at "$T"
expect_out "an unreadable keeper ledger makes after-merge unknown" "workers after their merge unknown (the keeper's ledger cannot be read)"

# ---------------------------------------------------------------------------
# A tmux server that does not answer: a count beside it is a floor, and no
# count is unknown.
# ---------------------------------------------------------------------------
fresh
mkdir -p "$tmp/bin-down"
printf '#!/bin/sh\necho "server exited unexpectedly" >&2\nexit 1\n' >"$tmp/bin-down/tmux"
chmod +x "$tmp/bin-down/tmux"
host_path=$PATH
PATH="$tmp/bin-down:$host_path"
reg $((T - 60)) w-win flight:win "tmux-window mc @5"
health_at "$T"
expect_out "worker age behind a silent tmux is unknown" "worker ages unknown for 1 session (tmux does not answer)"
expect_out "idle behind a silent tmux is unknown" "idle sessions unknown for 1 session (tmux does not answer)"
expect_out "after-merge behind a silent tmux is unknown" "workers after their merge unknown for 1 session (tmux does not answer)"
reg $((T - 14400)) w-old flight:old "process $$"
health_at "$T"
expect_out "a count beside a silent tmux is a floor" "1 worker live 4h or more (oldest w-old, 4h) (or more: tmux does not answer)"
PATH=$host_path

# ---------------------------------------------------------------------------
# A bound that cannot be read is unknown, and stays so from the cache.
# ---------------------------------------------------------------------------
fresh
cp "$tracked" "$tmp/tracked.good"
for k in worker_age merged_grace permission_wait idle_after; do printf 'mission_control_health_%s: soon\n' "$k" >>"$tracked"; done
reg $((T - 60)) w-young flight:young "process $$"
health_at "$T"
expect_out "an unreadable bound makes worker-age unknown" "worker ages unknown (its bound cannot be read)"
expect_out "an unreadable bound makes after-merge unknown" "workers after their merge unknown (its bound cannot be read)"
expect_out "an unreadable bound makes permissions unknown" "permission prompts unknown (its bound cannot be read)"
expect_out "an unreadable bound makes idle unknown" "idle sessions unknown (its bound cannot be read)"
cp "$tmp/tracked.good" "$tracked"
health_at $((T + 1))
expect_out "the bounds cache holds a failed bound for its life" "worker ages unknown (its bound cannot be read)"
health_at $((T + 300))
expect_empty "the bounds are read again once the cache expires"
printf 'format\t1\nwritten\t%s\nbound\tworker-age\t0\nbound\tmerged-grace\t600\nbound\tpermission-wait\t300\nbound\tstuck-after\t300\nbound\tci-queue-share\t50\nbound\tci-queue-floor\t120\nbound\tidle-after\t1800\n' "$T" >"$runtime/health-bounds"
health_at $((T + 1))
expect_empty "a cached bound no knob parser would accept is read again"

# ---------------------------------------------------------------------------
# The health verb takes no target and no knobs.
# ---------------------------------------------------------------------------
mc_run mc-panel.sh health --program alpha --target alpha --now "$T"
expect_rc "health refuses --target" 2
mc_run mc-panel.sh health --program alpha --knobs --now "$T"
expect_rc "health refuses --knobs" 2

# ---------------------------------------------------------------------------
# Unreadable stores read unknown, never within bounds.
# ---------------------------------------------------------------------------
fresh
rm -f "$fleet/attention/state"
mkdir "$fleet/attention/state"
health_at "$T"
expect_out "an unreadable attention store makes permissions unknown" "permission prompts unknown (the attention store cannot be read)"
expect_out "an unreadable attention store makes idle unknown" "idle sessions unknown (the attention store cannot be read)"
expect_out "an unreadable attention store makes after-merge unknown" "workers after their merge unknown (the attention store cannot be read)"
mc_run mc-panel.sh digest --program alpha --now "$T"
record health permissions '?' - "permission prompts unknown (the attention store cannot be read)"
mc_run mc-panel.sh text --program alpha
expect_out "the text panel carries the health line" "health: workers after their merge unknown"

echo
if [ "$failures" -eq 0 ]; then
  echo "all mc-panel health tests passed"
  exit 0
fi
echo "$failures mc-panel health test(s) failed"
exit 1
