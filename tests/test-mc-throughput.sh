#!/bin/bash
# Tests for scripts/mc-throughput.sh — the throughput duty: CI queue against
# run time, permission waits, stalled sessions and slow cadence steps,
# measured read-only; the single top bottleneck raised once unless it
# worsens; an unread source named unknown, never zero; and cost per model
# request against context size.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-throughput.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-mc-throughput: skipped (jq is not on PATH)"
  exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-throughput.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_home: $mchome
EOF
git -C "$repo" remote add origin https://github.com/acme/widgets.git
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$repo" worktree add -q -b feature "$tmp/wt" 2>/dev/null || fail "fixture worktree"

# 2026-11-01T12:00:00Z
NOW=1793534400

# ---------------------------------------------------------------------------
# A gh stand-in serving fixture Actions runs and jobs; GH_FIXTURE_FAIL makes
# every call fail, GH_FIXTURE_EMPTY serves no runs.
# ---------------------------------------------------------------------------
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/gh"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
[ -z "${GH_FIXTURE_FAIL:-}" ] || exit 1
[ "$1" = api ] || exit 1
case $2 in
  repos/acme/widgets/actions/runs\?per_page=*)
    if [ -n "${GH_FIXTURE_EMPTY:-}" ]; then echo '{"workflow_runs":[]}'; else cat "$GH_FIXTURE_DIR/runs.json"; fi ;;
  repos/acme/widgets/actions/runs/*/jobs\?per_page=100)
    id=${2#repos/acme/widgets/actions/runs/}; id=${id%%/*}
    cat "$GH_FIXTURE_DIR/jobs-$id.json" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"
cat >"$tmp/gh/runs.json" <<'EOF'
{"workflow_runs":[{"id":101,"name":"ci"},{"id":102,"name":"ci"}]}
EOF
cat >"$tmp/gh/jobs-101.json" <<'EOF'
{"jobs":[
 {"name":"macos-suite","status":"completed","conclusion":"success","created_at":"2026-11-01T11:00:00Z","started_at":"2026-11-01T11:30:00Z","completed_at":"2026-11-01T11:40:00Z"},
 {"name":"linux","status":"completed","conclusion":"success","created_at":"2026-11-01T11:00:00Z","started_at":"2026-11-01T11:00:05Z","completed_at":"2026-11-01T11:05:00Z"},
 {"name":"skipped-job","status":"completed","conclusion":"skipped","created_at":"2026-11-01T08:00:00Z","started_at":"2026-11-01T08:00:00Z","completed_at":"2026-11-01T08:00:00Z"}]}
EOF
cat >"$tmp/gh/jobs-102.json" <<'EOF'
{"jobs":[
 {"name":"macos-suite","status":"completed","conclusion":"success","created_at":"2026-11-01T11:10:00Z","started_at":"2026-11-01T11:30:00Z","completed_at":"2026-11-01T11:50:00Z"}]}
EOF
PATH="$stub:$PATH"
GH_FIXTURE_DIR="$tmp/gh"
export PATH GH_FIXTURE_DIR

# ---------------------------------------------------------------------------
# Fixture journals, registry rows, stall samples and step records.
# ---------------------------------------------------------------------------
sj="$fleet/streamjson"
mkdir -p "$sj/mc-alpha-worker-1" "$sj/mc-alpha-worker-2" "$sj/other-worker"
{
  printf 'r1\tpermission\t%s\tanswered\t%s\n' $((NOW - 1000)) $((NOW - 970))
  printf 'r2\tpermission\t%s\tanswered\t%s\n' $((NOW - 900)) $((NOW - 810))
  printf 'r3\tquestion\t%s\tanswered\t%s\n' $((NOW - 900)) $((NOW - 10))
  printf 'r4\tpermission\t%s\tanswered\t%s\n' $((NOW - 200000)) $((NOW - 199000))
} >"$sj/mc-alpha-worker-1/journal"
{
  printf 'r5\tpermission\t%s\tanswered\t%s\n' $((NOW - 500)) $((NOW - 350))
  printf 'r6\tpermission\t%s\tpending\n' $((NOW - 400))
} >"$sj/mc-alpha-worker-2/journal"
printf 'r7\tpermission\t%s\tanswered\t%s\n' $((NOW - 9000)) $((NOW - 10)) >"$sj/other-worker/journal"

reg="$fleet/mission-control/sessions"
stall="$fleet/mission-control/alpha/stall"
mkdir -p "$reg" "$stall"
row() { # row <name> <kind> <launched> <token> [<program>]
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\t%s\nprogram\t%s\nkind\t%s\nbackend\ttmux\nlaunched\t%s\n' \
    "$1" "$4" "${5:-alpha}" "$2" "$3" >"$reg/$1"
}
row mc-alpha-worker-1 worker 1793500000 t1
row mc-alpha-worker-3 worker 1793500000 t3
row mc-alpha-mission-control mission-control 1793500000 tm
row mc-alpha-worker-4 worker 1793500000 t4
printf '1793500000:t1\thash\t%s\tbusy-unchanged\n' $((NOW - 7200)) >"$stall/mc-alpha-worker-1"
printf '1793500000:t3\thash\t%s\tidle\n' $((NOW - 60)) >"$stall/mc-alpha-worker-3"
printf '1793500000:tm\thash\t%s\tidle\n' $((NOW - 90000)) >"$stall/mc-alpha-mission-control"
printf '1700000000:old\thash\t%s\tidle\n' $((NOW - 90000)) >"$stall/mc-alpha-worker-4"

steps="$tmp/wt/.claude/steps"
mkdir -p "$steps/000001" "$steps/000002"
rec() { # rec <file> <step> <start> <end> <outcome> <run> <seq>
  printf 'type\tstep\nrun\t%s\nseq\t%s\npoint\tconvergence\nstep\t%s\nstart\t%s\nend\t%s\noutcome\t%s\n' \
    "$6" "$7" "$2" "$3" "$4" "$5" >"$1"
}
rec "$steps/000001/002-step-convergence.rec" polish 2026-11-01T11:00:00Z 2026-11-01T11:50:00Z passed 000001 002
rec "$steps/000002/002-step-convergence.rec" polish 2026-11-01T11:20:00Z 2026-11-01T11:50:00Z passed 000002 002
rec "$steps/000002/003-step-convergence.rec" cubic-pr 2026-11-01T11:00:00Z 2026-11-01T11:59:00Z skipped 000002 003
rec "$steps/000002/004-step-convergence.rec" lint 2026-10-29T11:00:00Z 2026-10-29T13:00:00Z passed 000002 004
printf 'type\tcompletion\nrun\t000002\nseq\t005\npoint\tconvergence\n' >"$steps/000002/005-done-convergence.rec"

# ---------------------------------------------------------------------------
# Each measurement.
# ---------------------------------------------------------------------------
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "measure" 0
expect_out "the CI source reads" "source${tab}ci${tab}ok"
expect_out "CI queue against run time per workflow and job" "ci${tab}ci / macos-suite${tab}2${tab}1500${tab}3000${tab}1800${tab}900"
expect_out "a fast job is measured too" "ci${tab}ci / linux${tab}1${tab}5${tab}5${tab}5${tab}295"
expect_no_out "a skipped job is not measured" "skipped-job"
expect_out "permission waits: answered and pending, inside the window, this program's workers only" \
  "approvals${tab}permission${tab}4${tab}120${tab}670${tab}400${tab}mc-alpha-worker-2${tab}1${tab}400"
expect_out "a stalled session" "stall${tab}mc-alpha-worker-1${tab}busy-unchanged${tab}7200"
expect_out "an idle session, under the bound" "stall${tab}mc-alpha-worker-3${tab}idle${tab}60"
expect_no_out "mission control's own session is not a stall" "mc-alpha-mission-control"
expect_no_out "a sample from an earlier launch is not this launch's" "mc-alpha-worker-4"
expect_out "a slow step, naming its branch" "step${tab}polish${tab}2${tab}2400${tab}4800${tab}3000${tab}feature"
expect_no_out "a skipped step is not measured" "cubic-pr"
expect_no_out "a step that ended before the window is not measured" "step${tab}lint"

# ---------------------------------------------------------------------------
# The top bottleneck: of those over their threshold, the most time in all.
# ---------------------------------------------------------------------------
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_rc "top" 0
expect_out "the stall costs the most time" "top${tab}stalls${tab}7200${tab}Top bottleneck over the last 1d: Stalled or idle sessions: 1 past 30m, 2h in all, longest 2h (mc-alpha-worker-1 busy-unchanged)"
rm -f "$stall/mc-alpha-worker-1"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "with the stall gone, the slow step leads" "top${tab}step:polish${tab}4800${tab}"
expect_out "its text carries the numbers" "Slow cadence step polish: median 40m over 2 runs, 1h20m in all, slowest 50m on feature (threshold 20m)"
printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 1h}\n' >>"$tracked"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "a step under a raised threshold is no bottleneck; the CI queue leads" "top${tab}ci:ci / macos-suite${tab}3000${tab}Top bottleneck over the last 1d: CI runner queue, ci / macos-suite: median wait 25m over 2 jobs"

# ---------------------------------------------------------------------------
# A source that cannot be read is unknown, never zero.
# ---------------------------------------------------------------------------
OUT=$(GH_FIXTURE_FAIL=1 mc_env /bin/bash "$repo_root/scripts/mc-throughput.sh" top --program alpha --now "$NOW" 2>"$tmp/stderr")
RC=$?
expect_rc "top with gh failing" 0
expect_out "the CI source is named unknown" "source${tab}ci${tab}unknown${tab}the Actions runs of acme/widgets cannot be read"
expect_no_out "no CI measurement is shown" "${tab}ci / macos-suite"
expect_out "the item names what was not measured" "Not measured: ci (the Actions runs of acme/widgets cannot be read)"
printf '{"jobs":' >"$tmp/gh/jobs-102.json"
[ "$(id -u)" -eq 0 ] || chmod 000 "$sj/mc-alpha-worker-2/journal" "$steps/000002"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "malformed jobs are unknown, not an empty measurement" "source${tab}ci${tab}unknown${tab}the jobs of acme/widgets run 102 cannot be read"
expect_no_out "and the jobs read before it are not shown" "ci${tab}ci / linux"
if [ "$(id -u)" -ne 0 ]; then
  expect_out "an unreadable journal is unknown" "source${tab}approvals${tab}unknown${tab}cannot read the journal of mc-alpha-worker-2"
  expect_no_out "no approvals measurement is shown" "approvals${tab}permission"
  expect_out "unreadable step records are unknown" "source${tab}steps${tab}unknown${tab}cannot read the step records of $tmp/wt"
  expect_no_out "no step measurement is shown" "step${tab}polish"
  chmod 644 "$sj/mc-alpha-worker-2/journal"
  chmod 755 "$steps/000002"
else
  ok "unreadable journals and step records (skipped as root)"
fi

# ---------------------------------------------------------------------------
# The watcher: raised once, held until it worsens, forgotten once it clears.
# Only the step records remain, so nothing else moves with the clock.
# ---------------------------------------------------------------------------
: >"$tracked.tmp"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"
rm -rf "$sj" "$stall"
export GH_FIXTURE_EMPTY=1
events() { mc_run mc-event.sh list --program alpha; }
count_raised() { printf '%s\n' "$OUT" | awk -F '\t' '$3 == "throughput-bottleneck"' | wc -l | tr -d ' '; }

mc_run mc-throughput.sh watch --program alpha --now "$NOW"
expect_rc "watch" 0
expect_out "the top bottleneck is raised" "raised${tab}step:polish${tab}4800"
events
expect_out "as a throughput-bottleneck event with its numbers" "throughput-bottleneck${tab}step:polish${tab}Top bottleneck over the last 1d: Slow cadence step polish: median 40m"
if [ "$(count_raised)" = 1 ]; then ok "one event"; else fail "expected one event, got $(count_raised)"; fi
if [ -f "$mchome/kb/throughput/measure.tsv" ] && [ "$(head -n 1 "$mchome/kb/throughput/measure.tsv")" = "# format: 1" ]; then
  ok "the measurement is kept in the program home"
else
  fail "no measurement store"
fi

mc_run mc-throughput.sh watch --program alpha --now $((NOW + 1800))
expect_eq "inside the interval nothing is measured" "skipped${tab}interval"

mc_run mc-throughput.sh watch --program alpha --now $((NOW + 3600))
expect_out "the same bottleneck, no worse, is held" "held${tab}step:polish${tab}4800"
events
if [ "$(count_raised)" = 1 ]; then ok "a held bottleneck emits nothing"; else fail "a held bottleneck emitted: $(count_raised) events"; fi

rec "$steps/000002/006-step-pre-pr.rec" polish 2026-11-01T12:00:00Z 2026-11-01T12:50:00Z passed 000002 006
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 7200))
expect_out "a bottleneck grown past the worsen percent is raised again" "raised${tab}step:polish${tab}7800"
events
if [ "$(count_raised)" = 2 ]; then ok "the worsened bottleneck emits once more"; else fail "expected two events, got $(count_raised)"; fi

printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 2h}\n' >>"$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 10800))
expect_no_out "no bottleneck, nothing raised" "raised"
expect_no_out "and nothing held" "held"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 14400))
expect_out "a bottleneck that cleared and returned is raised afresh" "raised${tab}step:polish${tab}7800"

# ---------------------------------------------------------------------------
# Knobs.
# ---------------------------------------------------------------------------
printf 'mission_control_throughput_thresholds: {ci-queue: 5m, stall: 30m, step: 2h}\n' >>"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "a thresholds map missing a key fails" 1
expect_err "naming the knob" "mission_control_throughput_thresholds"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"
printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 2h, extra: 1m}\n' >>"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "an unknown threshold key fails" 1
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"

# ---------------------------------------------------------------------------
# Cost per model request against context size.
# ---------------------------------------------------------------------------
mkdir -p "$sj/mc-alpha-worker-1" "$sj/mc-alpha-worker-2" "$sj/mc-alpha-worker-5" "$fleet/mission-control/context"
{
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":2,"cache_read_input_tokens":10000,"cache_creation_input_tokens":9998,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":9998},"output_tokens":5}}}'
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":2,"cache_read_input_tokens":10000,"cache_creation_input_tokens":9998,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":9998},"output_tokens":100}}}'
  printf '%s\n' 'not json'
  printf '%s\n' '{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":0,"cache_read_input_tokens":90000,"cache_creation_input_tokens":0,"output_tokens":200}}}'
  printf '%s\n' '{"type":"result","modelUsage":{"claude-opus-5-5":{"contextWindow":200000}}}'
} >"$sj/mc-alpha-worker-1/events.jsonl"
printf '%s\n' '{"type":"assistant","message":{"id":"m3","usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}' >"$sj/mc-alpha-worker-2/events.jsonl"
printf 'format\t1\npercent\t1\ntokens\t1000\nwindow\t100000\nat\t%s\n' "$NOW" >"$fleet/mission-control/context/mc-alpha-worker-2"
printf '%s\n' '{"type":"assistant","message":{"id":"m4","usage":{"input_tokens":5000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}' >"$sj/mc-alpha-worker-5/events.jsonl"
mc_run mc-throughput.sh curve --program alpha --now $((NOW + 60))
expect_rc "curve" 0
expect_out "a request's last frame, its percent of the capture's window, and its cost" "request${tab}mc-alpha-worker-1${tab}1${tab}10${tab}20000${tab}200000${tab}21498"
expect_out "a later request higher on the curve" "request${tab}mc-alpha-worker-1${tab}2${tab}45${tab}90000${tab}200000${tab}10000"
expect_out "a capture with no result frame takes the session's context reading" "request${tab}mc-alpha-worker-2${tab}1${tab}1${tab}1000${tab}100000${tab}1000"
expect_out "a request with no known window is unknown, not 0%" "request${tab}mc-alpha-worker-5${tab}1${tab}-${tab}5000${tab}-${tab}5000"
expect_out "the bands" "curve${tab}0-9%${tab}1${tab}1000${tab}1000"
expect_out "the 10% band" "curve${tab}10-19%${tab}1${tab}20000${tab}21498"
expect_out "the 40% band" "curve${tab}40-49%${tab}1${tab}90000${tab}10000"
expect_out "unknown-window requests are counted apart" "curve${tab}unknown${tab}1"

# ---------------------------------------------------------------------------
# Under the runner: no arguments, the program from the environment.
# ---------------------------------------------------------------------------
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-throughput.sh" 2>"$tmp/stderr")
RC=$?
expect_rc "a bare run under the runner watches" 0
case $OUT in
  *"source${tab}ci${tab}"*) ok "it ran the watch" ;;
  *) fail "a bare run did not watch: $OUT" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "test-mc-throughput: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-throughput: all passed"
