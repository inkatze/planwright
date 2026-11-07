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
reg $((T - 30000)) pw-mission-control-a1 gen-2 "process $$"
health_at "$T"
expect_out "worker-age flags a live worker at its bound, naming the oldest" "1 worker live past 4h (oldest w-old, 4h)"
expect_no_out "a dead worker is no live worker" "w-dead"
expect_no_out "a mission control session is never a stale worker" "pw-mission-control"
health_at $((T - 1))
expect_empty "worker-age clears just below its bound"
mc_run mc-panel.sh digest --program alpha --now "$T"
record() {
  rc_want=$(printf '%s\t' "$@")
  rc_want=${rc_want%"$tab"}
  if printf '%s\n' "$OUT" | grep -qxF -- "$rc_want"; then ok "the digest record $1 $2"; else fail "no digest line '$rc_want'"; fi
}
record health worker-age 1 w-old "1 worker live past 4h (oldest w-old, 4h)"
expect_out "the line form carries the health text" "; health: 1 worker live past 4h"

# ---------------------------------------------------------------------------
# idle: a live session idle past the bound (30m).
# ---------------------------------------------------------------------------
fresh
reg $((T - 60)) w-idle flight:idle "process $$"
reg $((T - 60)) w-gone flight:gone "process $dead_pid"
attn w-idle idle $((T - 1800))
attn w-gone idle $((T - 9000))
health_at "$T"
expect_out "idle flags a live idle session at its bound" "1 session idle past 30m (longest w-idle, 30m)"
expect_no_out "an idle session whose process is gone is not counted" "w-gone"
health_at $((T - 1))
expect_empty "idle clears just below its bound"

# ---------------------------------------------------------------------------
# after-merge: live past the grace (10m) after a merge the attention store
# saw, or at once after a landing the keeper recorded.
# ---------------------------------------------------------------------------
fresh
reg $((T - 60)) w-merged flight:merged "process $$"
attn w-merged merged $((T - 600))
health_at "$T"
expect_out "after-merge flags a live worker at the grace after its merge" "1 worker still live after the pull request landed (w-merged, merged 10m ago)"
health_at $((T - 1))
expect_empty "after-merge clears inside the grace"
reg $((T - 60)) w-landed flight:landed "process $$"
printf 'w-landed\tacme/repo#7\tCLOSED\theld\n' >"$runtime/keeper-announced"
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
health_at "$T"
expect_out "permissions flags prompts at their bound, naming the longest" "2 permission prompts waiting past 5m (longest w-ask2, 7m)"
expect_no_out "a question that is no permission prompt is not counted" "w-fork"
health_at $((T - 101))
expect_empty "permissions clears just below its bound"

# ---------------------------------------------------------------------------
# mc-stuck: the program's mission control held on its own dialog (5m),
# read only while the escalation watcher runs.
# ---------------------------------------------------------------------------
fresh
mkdir -p "$runtime/escalate" "$runtime/watchers"
printf '%s\t%s\tsession-keeper\tscripts/mc-escalate.sh\t1m\tlow\n' "$$" $((T - 3600)) >"$runtime/watchers/session-keeper.1.rec"
printf '%s\t0\t0\n' $((T - 30)) >"$runtime/watchers/session-keeper.1.last"
printf 'dialog\t%s\t-\t0123456789abcdef\tauto-mode\n' $((T - 300)) >"$runtime/escalate/self"
health_at "$T"
expect_out "mc-stuck flags the mission control at its bound" "mission control alpha held on its own auto-mode prompt for 5m"
health_at $((T - 1))
expect_empty "mc-stuck clears just below its bound"
printf '%s\t0\t0\n' $((T - 200)) >"$runtime/watchers/session-keeper.1.last"
health_at "$T"
expect_out "a watcher that has not run within twice its cadence makes it unknown" "own dialog unknown (the escalation watcher last ran 3m ago)"
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
printf 'format\t1\nwritten\t%s\npercent\t10\nthreshold\t70\npid\t%s\n' $((T - 1000)) "$$" >"$fleet/mission-control/delta/context"
health_at "$T"
expect_out "a stale reading from a live session is unknown" "context unknown for delta"

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
measure $((T - 8000)) ok "ci${tab}CI / gate${tab}5${tab}300${tab}1500${tab}400${tab}600"
health_at "$T"
expect_out "a measure older than twice its cadence is unknown" "CI queue times unknown (the throughput measure is 2h old)"
measure $((T - 100)) unknown
health_at "$T"
expect_out "a CI source the measure could not read is unknown" "CI queue times unknown (gh is not signed in)"
printf 'not a measure\n' >"$home/kb/throughput/measure.tsv"
health_at "$T"
expect_out "a measure of another format is unknown" "CI queue times unknown (the throughput measure cannot be read)"

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
