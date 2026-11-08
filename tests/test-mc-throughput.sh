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
program_alpha_repositories: [$repo, $tmp/plain, $tmp/gone]
program_alpha_home: $mchome
EOF
# A remote URL with a user and a trailing slash still names the slug; a
# repository with no GitHub remote, or not cloned on this machine, is named,
# never a reason to leave the others unmeasured.
git -C "$repo" remote add origin https://user@github.com/acme/widgets/
git init -q "$tmp/plain"
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
printf '%s\n' "$*" >>"$GH_FIXTURE_DIR/calls"
[ -z "${GH_FIXTURE_FAIL:-}" ] || exit 1
[ "$1" = api ] || exit 1
shift
pages=1
[ "$1" != --paginate ] || { pages=all; shift; }
case $1 in
  repos/acme/widgets/actions/runs\?per_page=*)
    if [ -n "${GH_FIXTURE_EMPTY:-}" ]; then echo '{"workflow_runs":[]}'; else cat "$GH_FIXTURE_DIR/runs.json"; fi ;;
  repos/acme/widgets/actions/runs/*/jobs\?per_page=100)
    id=${1#repos/acme/widgets/actions/runs/}; id=${id%%/*}
    cat "$GH_FIXTURE_DIR/jobs-$id.json" || exit 1
    if [ "$pages" = all ] && [ -f "$GH_FIXTURE_DIR/jobs-$id-2.json" ]; then cat "$GH_FIXTURE_DIR/jobs-$id-2.json"; fi ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"
cat >"$tmp/gh/runs.json" <<'EOF'
{"workflow_runs":[{"id":101,"name":"ci","updated_at":"2026-11-01T11:50:00Z"},{"id":102,"name":"ci","updated_at":"2026-11-01T11:55:00Z"},{"id":100,"name":"ci","updated_at":"2026-10-20T00:00:00Z"}]}
EOF
cat >"$tmp/gh/jobs-101.json" <<'EOF'
{"jobs":[
 {"name":"macos-suite","status":"completed","conclusion":"success","created_at":"2026-11-01T11:00:00Z","started_at":"2026-11-01T11:30:00Z","completed_at":"2026-11-01T11:40:00Z"},
 {"name":"linux","status":"completed","conclusion":"success","created_at":"2026-11-01T11:00:00Z","started_at":"2026-11-01T11:00:05Z","completed_at":"2026-11-01T11:05:00Z"},
 {"name":"never-started","status":"completed","conclusion":"cancelled","created_at":"2026-11-01T11:00:00Z","started_at":null,"completed_at":"2026-11-01T11:02:00Z"},
 {"name":"clock\u001b[2Jskew","status":"completed","conclusion":"success","created_at":"2026-11-01T11:00:10Z","started_at":"2026-11-01T11:00:00Z","completed_at":"2026-11-01T11:01:00Z"},
 {"name":"back\\slash","status":"completed","conclusion":"success","created_at":"2026-11-01T11:00:00Z","started_at":"2026-11-01T11:00:01Z","completed_at":"2026-11-01T11:00:02Z"},
 {"name":"old-job","status":"completed","conclusion":"success","created_at":"2026-10-30T00:00:00Z","started_at":"2026-10-30T01:00:00Z","completed_at":"2026-10-30T01:10:00Z"},
 {"name":"skipped-job","status":"completed","conclusion":"skipped","created_at":"2026-11-01T08:00:00Z","started_at":"2026-11-01T08:00:00Z","completed_at":"2026-11-01T08:00:00Z"}]}
EOF
cat >"$tmp/gh/jobs-102.json" <<'EOF'
{"jobs":[
 {"name":"macos-suite","status":"completed","conclusion":"success","created_at":"2026-11-01T11:10:00Z","started_at":"2026-11-01T11:30:00Z","completed_at":"2026-11-01T11:50:00Z"},
 {"name":"queued-job","status":"queued","conclusion":null,"created_at":"2026-11-01T11:55:00Z","started_at":null,"completed_at":null},
 {"name":"requested-job","status":"requested","conclusion":null,"created_at":"2026-11-01T11:50:00Z","started_at":"2026-11-01T11:50:00Z","completed_at":null}]}
EOF
# The second page of run 102's jobs, served only to a paginated read.
cat >"$tmp/gh/jobs-102-2.json" <<'EOF'
{"jobs":[
 {"name":"linux","status":"completed","conclusion":"success","created_at":"2026-11-01T11:10:00Z","started_at":"2026-11-01T11:10:15Z","completed_at":"2026-11-01T11:15:00Z"}]}
EOF
PATH="$stub:$PATH"
GH_FIXTURE_DIR="$tmp/gh"
export PATH GH_FIXTURE_DIR

# ---------------------------------------------------------------------------
# Fixture journals, registry rows, stall samples and step records.
# ---------------------------------------------------------------------------
sj="$fleet/streamjson"
mkdir -p "$sj/mc-alpha-worker-0000000001" "$sj/mc-alpha-worker-0000000002" "$sj/other-worker"
{
  printf 'r1\tpermission\t%s\tanswered\t%s\n' $((NOW - 1000)) $((NOW - 970))
  printf 'r2\tpermission\t%s\tanswered\t%s\n' $((NOW - 900)) $((NOW - 810))
  printf 'r3\tquestion\t%s\tanswered\t%s\n' $((NOW - 900)) $((NOW - 10))
  printf 'r4\tpermission\t%s\tanswered\t%s\n' $((NOW - 200000)) $((NOW - 199000))
} >"$sj/mc-alpha-worker-0000000001/journal"
{
  printf 'r5\tpermission\t%s\tanswered\t%s\n' $((NOW - 500)) $((NOW - 350))
  printf 'r6\tpermission\t%s\tpending\n' $((NOW - 400))
  printf 'r14\tpermission\t%s\tundeliverable\t%s\n' $((NOW - 600)) $((NOW - 500))
} >"$sj/mc-alpha-worker-0000000002/journal"
printf 'r7\tpermission\t%s\tanswered\t%s\n' $((NOW - 9000)) $((NOW - 10)) >"$sj/other-worker/journal"
# Another program whose name shares this one's prefix, and a session under
# the launcher's long-name fallback that only its registry row attributes.
mkdir -p "$sj/mc-alpha-beta-worker-0000000003" "$sj/mc-worker-00000000000000aa"
printf 'r9\tpermission\t%s\tanswered\t%s\n' $((NOW - 9000)) $((NOW - 10)) >"$sj/mc-alpha-beta-worker-0000000003/journal"
printf 'r8\tpermission\t%s\tanswered\t%s\n' $((NOW - 300)) $((NOW - 240)) >"$sj/mc-worker-00000000000000aa/journal"

reg="$fleet/mission-control/sessions"
stall="$fleet/mission-control/alpha/stall"
mkdir -p "$reg" "$stall"
row() { # row <name> <kind> <launched> <token> [<program>]
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\t%s\nprogram\t%s\nkind\t%s\nbackend\ttmux\nlaunched\t%s\n' \
    "$1" "$4" "${5:-alpha}" "$2" "$3" >"$reg/$1"
}
row mc-alpha-worker-0000000001 worker 1793500000 t1
row mc-alpha-worker-0000000003 worker 1793500000 t3
row mc-alpha-mission-control mission-control 1793500000 tm
row mc-alpha-worker-0000000004 worker 1793500000 t4
row mc-worker-00000000000000aa worker 1793500000 ta
# A busy session is no stall however old its sample; a row of another
# program or a session no longer launched is not measured; a launcher-form
# name whose row names another program is that program's.
row mc-alpha-worker-0000000020 worker 1793500000 t20
printf '1793500000:t20\thash\t%s\tbusy\n' $((NOW - 7200)) >"$stall/mc-alpha-worker-0000000020"
row mc-alpha-worker-0000000021 worker 1793500000 t21 beta
printf '1793500000:t21\thash\t%s\tidle\n' $((NOW - 7200)) >"$stall/mc-alpha-worker-0000000021"
row mc-alpha-worker-0000000022 worker 1793500000 t22
sed 's/^state\tlaunched$/state\tretired/' "$reg/mc-alpha-worker-0000000022" >"$reg/x.tmp.1" && mv "$reg/x.tmp.1" "$reg/mc-alpha-worker-0000000022"
printf '1793500000:t22\thash\t%s\tidle\n' $((NOW - 7200)) >"$stall/mc-alpha-worker-0000000022"
row mc-alpha-worker-00000000bb worker 1793500000 tb beta
mkdir -p "$sj/mc-alpha-worker-00000000bb"
printf 'r15\tpermission\t%s\tanswered\t%s\n' $((NOW - 9000)) $((NOW - 10)) >"$sj/mc-alpha-worker-00000000bb/journal"
# A name outside the registry grammar is never the program's, its row aside.
row mc-alpha.odd worker 1793500000 to
mkdir -p "$sj/mc-alpha.odd"
printf 'r13\tpermission\t%s\tanswered\t%s\n' $((NOW - 9000)) $((NOW - 10)) >"$sj/mc-alpha.odd/journal"
printf '1793500000:t1\thash\t%s\tbusy-unchanged\n' $((NOW - 7200)) >"$stall/mc-alpha-worker-0000000001"
printf '1793500000:t3\thash\t%s\tidle\n' $((NOW - 60)) >"$stall/mc-alpha-worker-0000000003"
printf '1793500000:tm\thash\t%s\tidle\n' $((NOW - 90000)) >"$stall/mc-alpha-mission-control"
printf '1700000000:old\thash\t%s\tidle\n' $((NOW - 90000)) >"$stall/mc-alpha-worker-0000000004"
# A row with an empty field, and one whose token carries a control byte that
# scripts/mc-stall.sh drops from the sample's launch key.
row mc-alpha-worker-0000000006 "" 1793500000 t6
printf '1793500000:t6\thash\t%s\tidle\n' $((NOW - 120)) >"$stall/mc-alpha-worker-0000000006"
row mc-alpha-worker-0000000007 worker 1793500000 "$(printf 't\0337')"
printf '1793500000:t7\thash\t%s\tidle\n' $((NOW - 130)) >"$stall/mc-alpha-worker-0000000007"

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
# A reclaimed copy of the worktree still on disk holds the same record, and
# a reclaimed cache of an earlier worktree of the same branch reuses a run
# id and sequence for a different record.
rsteps="$mchome/reclaimed/repo/feature/.claude/steps"
mkdir -p "$rsteps/000001" "$mchome/reclaimed/repo/old/feature/.claude/steps/000001"
cp "$steps/000001/002-step-convergence.rec" "$rsteps/000001/"
rec "$mchome/reclaimed/repo/old/feature/.claude/steps/000001/002-step-convergence.rec" audit 2026-11-01T10:00:00Z 2026-11-01T10:30:00Z passed 000001 002
chmod 700 "$rsteps" "$mchome/reclaimed/repo/old/feature/.claude/steps"

# ---------------------------------------------------------------------------
# Each measurement.
# ---------------------------------------------------------------------------
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "measure" 0
expect_out "the CI source reads, naming the repositories it could not measure" \
  "source${tab}ci${tab}ok${tab}1 repositories; no GitHub remote: $tmp/plain; not on this machine: $tmp/gone"
expect_out "CI queue against run time per workflow and job" "ci${tab}ci / macos-suite${tab}2${tab}1500${tab}3000${tab}1800${tab}900"
expect_out "a fast job is measured too, every page of a run's jobs read" "ci${tab}ci / linux${tab}2${tab}10${tab}20${tab}15${tab}290"
expect_out "a job still queued counts its wait to now" "ci${tab}ci / queued-job${tab}1${tab}300${tab}300${tab}300${tab}-"
expect_out "so does one requested, whatever start time the forge gives it" "ci${tab}ci / requested-job${tab}1${tab}600${tab}600${tab}600${tab}-"
expect_out "a job that finished unstarted waited until it finished, with no run time" "ci${tab}ci / never-started${tab}1${tab}120${tab}120${tab}120${tab}-"
expect_out "a forge clock skew never makes a wait negative, and a job name loses its control bytes" "ci${tab}ci / clock[2Jskew${tab}1${tab}0${tab}0${tab}0${tab}60"
expect_no_out "a skipped job is not measured" "skipped-job"
expect_no_out "a job created before the window is not measured" "old-job"
if grep -q 'actions/runs?per_page=40$' "$tmp/gh/calls"; then ok "the CI run count reaches the forge"; else fail "the runs list was not read 40 at a time: $(cat "$tmp/gh/calls")"; fi
expect_out "a backslash in a job name is kept as written" "ci${tab}ci / back\\slash${tab}1${tab}1${tab}1${tab}1${tab}1"
expect_out "permission waits: answered, undeliverable and pending, inside the window, this program's workers only" \
  "approvals${tab}permission${tab}6${tab}95${tab}830${tab}400${tab}mc-alpha-worker-0000000002${tab}1${tab}400"
expect_no_out "a session named outside the registry grammar is not measured" "mc-alpha.odd"
expect_out "a stalled session" "stall${tab}mc-alpha-worker-0000000001${tab}busy-unchanged${tab}7200"
expect_out "an idle session, under the bound" "stall${tab}mc-alpha-worker-0000000003${tab}idle${tab}60"
expect_no_out "mission control's own session is not a stall" "mc-alpha-mission-control"
expect_no_out "a sample from an earlier launch is not this launch's" "stall${tab}mc-alpha-worker-0000000004"
expect_out "a session with no current sample is named, never read as unstalled" \
  "source${tab}stalls${tab}ok${tab}7 sessions; no current stall sample: mc-alpha-worker-0000000004, mc-worker-00000000000000aa"
expect_no_out "a busy session is no stall" "stall${tab}mc-alpha-worker-0000000020"
expect_no_out "another program's session is not measured" "stall${tab}mc-alpha-worker-0000000021"
expect_no_out "a session no longer launched is not measured" "stall${tab}mc-alpha-worker-0000000022"
expect_out "an empty registry field shifts no other" "stall${tab}mc-alpha-worker-0000000006${tab}idle${tab}120"
expect_out "the launch key is cleaned as the stall detector cleans it" "stall${tab}mc-alpha-worker-0000000007${tab}idle${tab}130"
expect_out "a slow step, naming its branch" "step${tab}polish${tab}2${tab}2400${tab}4800${tab}3000${tab}feature"
expect_no_out "a skipped step is not measured" "cubic-pr"
expect_out "a reclaimed cache's own record, the same run id aside, is measured" "step${tab}audit${tab}1${tab}1800${tab}1800${tab}1800${tab}old/feature"
expect_out "every record folder is read, naming a repository not on this machine" \
  "source${tab}steps${tab}ok${tab}3 record folders; not on this machine: $tmp/gone"
expect_no_out "a step that ended before the window is not measured" "step${tab}lint"
# A record folder with nothing written since the window began is not read:
# a record that ended inside the window was written inside it.
oldrec="$mchome/reclaimed/repo/old/feature/.claude/steps/000001/002-step-convergence.rec"
touch -t 202610300000 "$oldrec"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_no_out "a folder with no record written inside the window is not read" "step${tab}audit"
expect_out "though it is still counted" "source${tab}steps${tab}ok${tab}3 record folders"
touch -t 202611011100 "$oldrec"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "the cut is reckoned from the real clock, so a --now pass reads a record written inside its window" \
  "step${tab}audit${tab}1${tab}1800"
touch "$oldrec"

# ---------------------------------------------------------------------------
# The top bottleneck: of those over their threshold, the most time in all.
# ---------------------------------------------------------------------------
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_rc "top" 0
expect_out "the stall costs the most time" "top${tab}stalls${tab}7200${tab}Top bottleneck over the last 1d: Stalled or idle sessions: 1 past 30m, 2h in all, longest 2h (mc-alpha-worker-0000000001 busy-unchanged)"
rm -f "$stall/mc-alpha-worker-0000000001"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "with the stall gone, the slow step leads" "top${tab}step:polish${tab}4800${tab}"
expect_out "its text carries the numbers" "Slow cadence step polish: median 40m over 2 runs, 1h20m in all, slowest 50m on feature (threshold 20m)"
printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 1h}\n' >>"$tracked"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "a step under a raised threshold is no bottleneck; the CI queue leads" "top${tab}ci:ci / macos-suite${tab}3000${tab}Top bottleneck over the last 1d: CI runner queue, ci / macos-suite: median wait 25m over 2 jobs"
cp "$tracked" "$tracked.keep"
grep -v '^mission_control_throughput_thresholds' "$tracked.keep" >"$tracked"
printf 'mission_control_throughput_thresholds: {ci-queue: 1d, approval-wait: 1d, stall: 1d, step: 1d}\n' >>"$tracked"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_rc "top with nothing over its threshold" 0
expect_out "names no bottleneck" "top${tab}none"
grep -v '^mission_control_throughput_thresholds' "$tracked.keep" >"$tracked"
printf 'mission_control_throughput_thresholds: {ci-queue: 1d, approval-wait: 1d, stall: 1d, step: 40m}\n' >>"$tracked"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "a typical value equal to its threshold reaches it" "top${tab}step:polish${tab}4800"
grep -v '^mission_control_throughput_thresholds' "$tracked.keep" >"$tracked"
printf 'mission_control_throughput_thresholds: {ci-queue: 1d, approval-wait: 1m, stall: 1d, step: 1d}\n' >>"$tracked"
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "the approvals text carries its numbers" \
  "top${tab}approvals${tab}830${tab}Top bottleneck over the last 1d: Permission approvals: median wait 1m over 6 requests, 13m waiting in all, longest 6m on mc-alpha-worker-0000000002, 1 pending now (threshold 1m)"
mv "$tracked.keep" "$tracked"

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
[ "$(id -u)" -eq 0 ] || chmod 000 "$sj/mc-alpha-worker-0000000002/journal" "$steps/000002"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "malformed jobs are unknown, not an empty measurement" "source${tab}ci${tab}unknown${tab}the jobs of acme/widgets run 102 cannot be read"
expect_no_out "and the jobs read before it are not shown" "ci${tab}ci / linux"
if [ "$(id -u)" -ne 0 ]; then
  expect_out "an unreadable journal is unknown" "source${tab}approvals${tab}unknown${tab}cannot read the journal of mc-alpha-worker-0000000002"
  expect_no_out "no approvals measurement is shown" "approvals${tab}permission"
  expect_out "unreadable step records are unknown" "source${tab}steps${tab}unknown${tab}cannot read the step records of $tmp/wt"
  expect_no_out "no step measurement is shown" "step${tab}polish"
  chmod 644 "$sj/mc-alpha-worker-0000000002/journal"
  chmod 755 "$steps/000002"
else
  ok "unreadable journals and step records (skipped as root)"
fi
# Whether a session is the program's, when that cannot be told, leaves its
# sources unknown rather than passing the session over.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$reg/mc-alpha-worker-0000000001"
  mc_run mc-throughput.sh measure --program alpha --now "$NOW"
  expect_out "a registry row that cannot be read leaves approvals unknown" \
    "source${tab}approvals${tab}unknown${tab}cannot tell whether mc-alpha-worker-0000000001 is the program's"
  chmod 644 "$reg/mc-alpha-worker-0000000001"
  chmod 000 "$sj/mc-alpha-worker-0000000002"
  mc_run mc-throughput.sh measure --program alpha --now "$NOW"
  expect_out "a session folder that cannot be searched leaves approvals unknown" \
    "source${tab}approvals${tab}unknown${tab}cannot read the folder of mc-alpha-worker-0000000002"
  chmod 755 "$sj/mc-alpha-worker-0000000002"
  # A linked session folder is passed over before it is judged, whatever
  # it points at.
  mkdir -p "$tmp/locked"
  chmod 000 "$tmp/locked"
  ln -s "$tmp/locked" "$sj/mc-alpha-worker-0000000030"
  mc_run mc-throughput.sh measure --program alpha --now "$NOW"
  expect_out "a linked session folder is passed over" "source${tab}approvals${tab}ok${tab}"
  rm -f "$sj/mc-alpha-worker-0000000030"
  chmod 700 "$tmp/locked"
  chmod 000 "$tmp/wt"
  mc_run mc-throughput.sh measure --program alpha --now "$NOW"
  expect_out "a worktree that cannot be searched leaves the steps unknown" \
    "source${tab}steps${tab}unknown${tab}cannot read the worktree $tmp/wt"
  chmod 755 "$tmp/wt"
else
  ok "sessions that cannot be told apart (skipped as root)"
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
runtime="$fleet/mission-control/alpha"
count_raised() { printf '%s\n' "$OUT" | awk -F '\t' '$3 == "throughput-bottleneck"' | wc -l | tr -d ' '; }

mc_run mc-throughput.sh watch --program alpha --now "$NOW"
expect_rc "watch" 0
expect_out "the top bottleneck is raised" "raised${tab}step:polish${tab}4800"
expect_out "with no stall sample at all, the stalls source is unknown" "source${tab}stalls${tab}unknown${tab}no current stall sample for any of the 7 sessions"
events
expect_out "as a throughput-bottleneck event with its numbers" "throughput-bottleneck${tab}step:polish${tab}Top bottleneck over the last 1d: Slow cadence step polish: median 40m"
if [ "$(count_raised)" = 1 ]; then ok "one event"; else fail "expected one event, got $(count_raised)"; fi
if [ -f "$mchome/kb/throughput/measure.tsv" ] && [ "$(head -n 1 "$mchome/kb/throughput/measure.tsv")" = "# format: 1" ]; then
  ok "the measurement is kept in the program home"
else
  fail "no measurement store"
fi
if grep -q "^measured${tab}$NOW\$" "$mchome/kb/throughput/measure.tsv" && grep -q "^step${tab}polish${tab}" "$mchome/kb/throughput/measure.tsv"; then
  ok "it holds the pass's time and its measurements"
else
  fail "the measurement store lacks the pass: $(cat "$mchome/kb/throughput/measure.tsv")"
fi
if [ "$(head -n 1 "$mchome/kb/throughput/cost-curve.tsv" 2>/dev/null)" = "# format: 1" ] \
  && grep -q "^source${tab}cost${tab}" "$mchome/kb/throughput/cost-curve.tsv" \
  && ! grep -q "^request${tab}" "$mchome/kb/throughput/cost-curve.tsv"; then
  ok "the curve is kept beside it, without its per-request lines"
else
  fail "the curve store is missing or holds request lines"
fi

mc_run mc-throughput.sh watch --program alpha --now $((NOW + 1800))
expect_eq "inside the interval nothing is measured" "skipped${tab}interval"

mc_run mc-throughput.sh watch --program alpha --now $((NOW + 3600))
expect_out "the same bottleneck, no worse, is held" "held${tab}step:polish${tab}4800"
events
if [ "$(count_raised)" = 1 ]; then ok "a held bottleneck emits nothing"; else fail "a held bottleneck emitted: $(count_raised) events"; fi

if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$steps/000002"
  mc_run mc-throughput.sh watch --program alpha --now $((NOW + 7200))
  expect_rc "a watch that cannot read the step records" 0
  expect_no_out "raises nothing" "raised"
  chmod 755 "$steps/000002"
  mc_run mc-throughput.sh watch --program alpha --now $((NOW + 10800))
  expect_out "a bottleneck its source could not see for a pass is held, not raised again" "held${tab}step:polish${tab}4800"
else
  ok "a source unread for a pass (skipped as root)"
fi

rec "$steps/000002/008-step-pre-pr.rec" polish 2026-11-01T13:00:00Z 2026-11-01T13:30:00Z passed 000002 008
rm -f "$runtime/throughput-last"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 12600))
expect_out "a bottleneck grown by less than the worsen percent is held" "held${tab}step:polish${tab}6600"
rec "$steps/000002/006-step-pre-pr.rec" polish 2026-11-01T12:00:00Z 2026-11-01T12:50:00Z passed 000002 006
rm -f "$runtime/throughput-last"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 14400))
expect_out "grown past the worsen percent over the total last raised at, not last held at, it is raised again" "raised${tab}step:polish${tab}9600"
events
if [ "$(count_raised)" = 2 ]; then ok "the worsened bottleneck emits once more"; else fail "expected two events, got $(count_raised)"; fi

printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 2h}\n' >>"$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 18000))
expect_rc "a watch with no bottleneck" 0
expect_no_out "no bottleneck, nothing raised" "raised"
expect_no_out "and nothing held" "held"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 21600))
expect_out "a bottleneck that cleared and returned is raised afresh" "raised${tab}step:polish${tab}9600"

if [ "$(id -u)" -ne 0 ]; then
  rm -f "$runtime/throughput-raised"
  mkdir "$runtime/throughput-raised"
  chmod 500 "$runtime/throughput-raised"
  mc_run mc-throughput.sh watch --program alpha --now $((NOW + 25200))
  expect_rc "a memory that cannot be written fails the watch" 1
  mc_run mc-throughput.sh watch --program alpha --now $((NOW + 26100))
  expect_eq "but the pass was stamped, so the next pass raises nothing again" "skipped${tab}interval"
  chmod 700 "$runtime/throughput-raised"
  rmdir "$runtime/throughput-raised"
  # A pass that cannot stamp itself measures and emits nothing, so a runtime
  # directory gone read-only never repeats an event every run.
  events
  before=$(count_raised)
  rm -f "$runtime/throughput-last"
  mkdir "$runtime/throughput-last"
  chmod 500 "$runtime/throughput-last"
  mc_run mc-throughput.sh watch --program alpha --now $((NOW + 27000))
  expect_rc "a pass that cannot be stamped fails the watch" 1
  expect_no_out "before it measures anything" "source${tab}"
  events
  if [ "$(count_raised)" = "$before" ]; then ok "and it emits nothing"; else fail "an unstamped pass emitted: $(count_raised) events, $before before"; fi
  chmod 700 "$runtime/throughput-last"
  rm -rf "$runtime/throughput-last"
else
  ok "an unwritable memory (skipped as root)"
fi

rm -f "$runtime/throughput-last"
lock_token=$(mc_env /bin/bash "$repo_root/scripts/mc-kb.sh" lock --program alpha throughput/measure.tsv --holder $$ 2>/dev/null)
printf 'mission_control_kb_lock_wait: 1\n' >>"$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 28800))
expect_rc "a knowledge-base write another writer holds fails" 1
expect_err "naming the lock" "kb/throughput/measure.tsv"
(mc_env /bin/bash "$repo_root/scripts/mc-kb.sh" unlock --program alpha throughput/measure.tsv --token "$lock_token") >/dev/null 2>&1
grep -v '^mission_control_kb_lock_wait' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"

rm -f "$runtime/throughput-last"
cp "$tracked" "$tracked.keep"
sed "s#^program_alpha_home: .*#program_alpha_home: $repo/home#" "$tracked.keep" >"$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 28800))
expect_rc "a watch whose program home does not resolve fails" 1
expect_no_out "before it measures anything" "source${tab}"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "measure names the steps unknown instead" "source${tab}steps${tab}unknown${tab}the program home does not resolve"
mv "$tracked.keep" "$tracked"

# A note on what went unmeasured too long to sit beside the bottleneck
# within the event's text bound names the sources alone.
if [ "$(id -u)" -ne 0 ]; then
  # A path that brings the note to about 450 bytes, whatever TMPDIR is.
  pad=$(((450 - 60 - ${#tmp}) / 2))
  long="$tmp/$(printf '%0*d' "$pad" 0)/$(printf '%0*d' "$pad" 0)"
  mkdir -p "${long%/*}"
  git -C "$repo" worktree add -q -b long "$long" 2>/dev/null || fail "fixture long worktree"
  mkdir -p "$long/.claude/steps/000001"
  chmod 000 "$long/.claude/steps/000001"
  mkdir -p "$stall"
  printf '1793500000:t1\thash\t%s\tbusy-unchanged\n' $((NOW + 28800 - 7200)) >"$stall/mc-alpha-worker-0000000001"
  rm -f "$runtime/throughput-last" "$runtime/throughput-raised"
  mc_run mc-throughput.sh watch --program alpha --now $((NOW + 28800))
  expect_out "a stall raised beside an unread source with a long reason" "raised${tab}stalls${tab}7200"
  events
  ev=$(printf '%s\n' "$OUT" | awk -F '\t' '$3 == "throughput-bottleneck" && $4 == "stalls" { t = $5 } END { print t }')
  case $ev in
    "Top bottleneck over the last 1d: Stalled or idle sessions: "*"(mc-alpha-worker-0000000001 busy-unchanged). Not measured: steps")
      ok "the bottleneck is whole, and the unmeasured source is named"
      ;;
    *) fail "the bottleneck or the unmeasured source was cut: $ev" ;;
  esac
  if [ "${#ev}" -le 500 ]; then ok "within the event's text bound"; else fail "the event text is ${#ev} bytes"; fi
  chmod 755 "$long/.claude/steps/000001"
  git -C "$repo" worktree remove --force "$long" 2>/dev/null
  rm -rf "$stall"
else
  ok "the unmeasured note under the text bound (skipped as root)"
fi

# A CI key falls outside the subject grammar, so its event takes a checksum
# subject and carries the key in its text.
unset GH_FIXTURE_EMPTY
cat >"$tmp/gh/jobs-102.json" <<'EOF'
{"jobs":[
 {"name":"macos-suite","status":"completed","conclusion":"success","created_at":"2026-11-01T11:10:00Z","started_at":"2026-11-01T11:30:00Z","completed_at":"2026-11-01T11:50:00Z"}]}
EOF
rm -f "$runtime/throughput-last" "$runtime/throughput-raised"
printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 1d}\n' >>"$tracked"
mc_run mc-throughput.sh watch --program alpha --now $((NOW + 32400))
expect_rc "a watch where CI leads" 0
expect_out "the CI queue is raised" "raised${tab}ci:ci / macos-suite${tab}3000"
events
expect_out "under a checksum subject, the key in its text" \
  "throughput-bottleneck${tab}throughput-$(printf '%s' 'ci:ci / macos-suite' | cksum | awk '{ print $1 }')${tab}Top bottleneck over the last 1d: CI runner queue, ci / macos-suite"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"
export GH_FIXTURE_EMPTY=1

git -C "$repo" remote set-url origin git@github.com:acme/widgets.git
cp "$tmp/gh/runs.json" "$tmp/gh/runs.keep"
printf '%s\n' '{"workflow_runs":[{"id":"12a","name":"ci","updated_at":"2026-11-01T11:50:00Z"}]}' >"$tmp/gh/runs.json"
unset GH_FIXTURE_EMPTY
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "an SSH remote names the slug, and a malformed run id is unknown" \
  "source${tab}ci${tab}unknown${tab}an Actions run id of acme/widgets is malformed"
export GH_FIXTURE_EMPTY=1
mv "$tmp/gh/runs.keep" "$tmp/gh/runs.json"
cp "$tracked" "$tracked.keep"
sed "s#^program_alpha_repositories: .*#program_alpha_repositories: [$tmp/plain, $tmp/gone]#" "$tracked.keep" >"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "with no repository measurable, CI is unknown, naming each" \
  "source${tab}ci${tab}unknown${tab}no repository measured; no GitHub remote: $tmp/plain; not on this machine: $tmp/gone"
# A configured path's C1 control bytes never reach the source line.
sed "s#^program_alpha_repositories: .*#program_alpha_repositories: [$repo, $tmp/gone$(printf '\302\233')2J]#" "$tracked.keep" >"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "a repository path loses its control bytes in the CI source line" "not on this machine: $tmp/gone2J"
expect_out "and in the steps source line" "record folders; not on this machine: $tmp/gone2J"
mv "$tracked.keep" "$tracked"

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
expect_err "naming the knob" "mission_control_throughput_thresholds"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"

printf 'mission_control_throughput_thresholds: {ci-queue: 5m, approval-wait: 1m, stall: 30m, step: 2h, step: 1m}\n' >>"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "a threshold key given twice fails" 1
expect_err "naming the knob" "mission_control_throughput_thresholds"
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"

printf 'mission_control_throughput_ci_runs: 101\n' >>"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "more CI runs than one forge page holds fails" 1
expect_err "naming the knob" "mission_control_throughput_ci_runs"
grep -v '^mission_control_throughput_ci_runs' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"

# A repository whose remote git cannot read is unknown, not one with no
# GitHub remote.
mkdir -p "$tmp/notgit"
cp "$tracked" "$tracked.keep"
sed "s#^program_alpha_repositories: .*#program_alpha_repositories: [$repo, $tmp/notgit]#" "$tracked.keep" >"$tracked"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "an unreadable remote is unknown" "source${tab}ci${tab}unknown${tab}cannot read the origin remote of $tmp/notgit"
mv "$tracked.keep" "$tracked"

# ---------------------------------------------------------------------------
# Cost per model request against context size.
# ---------------------------------------------------------------------------
mkdir -p "$sj/mc-alpha-worker-0000000001" "$sj/mc-alpha-worker-0000000002" "$sj/mc-alpha-worker-0000000005" "$fleet/mission-control/context"
{
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":2,"cache_read_input_tokens":10000,"cache_creation_input_tokens":9998,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":9998},"output_tokens":5}}}'
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":2,"cache_read_input_tokens":10000,"cache_creation_input_tokens":9998,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":9998},"output_tokens":100}}}'
  printf '%s\n' 'not json'
  printf '%s\n' '{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":0,"cache_read_input_tokens":90000,"cache_creation_input_tokens":0,"output_tokens":200}}}'
  printf '%s\n' '{"type":"result","modelUsage":{"claude-opus-5-5":{"contextWindow":200000}}}'
  printf '%s\n' '{"type":"assistant","message":"a frame jq cannot index, last"}'
} >"$sj/mc-alpha-worker-0000000001/events.jsonl"
printf '%s\n' '{"type":"assistant","message":{"id":"m3","usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}' >"$sj/mc-alpha-worker-0000000002/events.jsonl"
printf 'format\t1\npercent\t1\ntokens\t1000\nwindow\t100000\nat\t%s\n' "$NOW" >"$fleet/mission-control/context/mc-alpha-worker-0000000002"
printf '%s\n' '{"type":"assistant","message":{"id":"m4","usage":{"input_tokens":5000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}' >"$sj/mc-alpha-worker-0000000005/events.jsonl"
# Cache writes reported without the 5-minute and 1-hour breakdown, beside a
# context reading of an unknown format; a capture holding only a result
# frame; and a request past its window.
mkdir -p "$sj/mc-alpha-worker-0000000008" "$sj/mc-alpha-worker-0000000009" "$sj/mc-alpha-worker-0000000010"
printf '%s\n' '{"type":"assistant","message":{"id":"m5","usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":1000,"output_tokens":0}}}' >"$sj/mc-alpha-worker-0000000008/events.jsonl"
printf 'format\t2\nwindow\t100000\n' >"$fleet/mission-control/context/mc-alpha-worker-0000000008"
printf '%s\n' '{"type":"result","modelUsage":{"claude-opus-5-5":{"contextWindow":200000}}}' >"$sj/mc-alpha-worker-0000000009/events.jsonl"
printf '%s\n' '{"type":"assistant","message":{"id":"m6","usage":{"input_tokens":120000,"output_tokens":0}}}' >"$sj/mc-alpha-worker-0000000010/events.jsonl"
printf 'format\t1\nwindow\t100000\n' >"$fleet/mission-control/context/mc-alpha-worker-0000000010"
printf 'format\t1\nwindow\t100000\n' >"$fleet/mission-control/context/mc-alpha-worker-0000000001"
mkdir -p "$sj/mc-alpha-worker-0000000014"
printf '%s\n' '{"type":"assistant","message":{"id":"m7","usage":{"input_tokens":7777,"output_tokens":0}}}' >"$sj/mc-alpha-worker-0000000014/events.jsonl"
touch -t 202610300000 "$sj/mc-alpha-worker-0000000014/events.jsonl"
printf 'mission_control_throughput_thresholds: {ci-queue: 5m}\n' >>"$tracked"
mc_run mc-throughput.sh curve --program alpha --now $((NOW + 60))
expect_rc "curve, which reads no threshold" 0
grep -v '^mission_control_throughput_thresholds' "$tracked" >"$tracked.tmp" && mv "$tracked.tmp" "$tracked"
expect_out "a request's last frame, its percent of the capture's window, and its cost" "request${tab}mc-alpha-worker-0000000001${tab}1${tab}10${tab}20000${tab}200000${tab}21498"
expect_out "a later request higher on the curve" "request${tab}mc-alpha-worker-0000000001${tab}2${tab}45${tab}90000${tab}200000${tab}10000"
expect_out "a capture with no result frame takes the session's context reading" "request${tab}mc-alpha-worker-0000000002${tab}1${tab}1${tab}1000${tab}100000${tab}1000"
expect_out "a request with no known window is unknown, not 0%" "request${tab}mc-alpha-worker-0000000005${tab}1${tab}-${tab}5000${tab}-${tab}5000"
expect_out "the bands" "curve${tab}0-9%${tab}1${tab}1000${tab}1000"
expect_out "the 10% band" "curve${tab}10-19%${tab}1${tab}20000${tab}21498"
expect_out "the 40% band" "curve${tab}40-49%${tab}1${tab}90000${tab}10000"
expect_out "unknown-window requests are counted apart" "curve${tab}unknown${tab}2"
expect_out "a frame jq cannot index costs the capture nothing" "source${tab}cost${tab}ok${tab}6 captures"
expect_no_out "a capture last written before the window is not read" "mc-alpha-worker-0000000014"
expect_out "undivided cache writes are priced as 5-minute writes; an unknown context format gives no window" \
  "request${tab}mc-alpha-worker-0000000008${tab}1${tab}-${tab}1000${tab}-${tab}1250"
expect_no_out "a capture of only a result frame adds no request" "request${tab}mc-alpha-worker-0000000009"
expect_out "a request past its window lands in the top band" "curve${tab}100+%${tab}1${tab}120000${tab}120000"
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$sj"
  mc_run mc-throughput.sh curve --program alpha --now $((NOW + 60))
  expect_out "an unreadable capture folder is unknown, not empty" "source${tab}cost${tab}unknown${tab}cannot read $sj"
  chmod 755 "$sj"
else
  ok "an unreadable capture folder (skipped as root)"
fi

# A journal that is not a regular file is never opened (a FIFO would hang
# the watcher); a request pending for no time yet still reports its wait.
rm -rf "$sj"
mkdir -p "$sj/mc-alpha-worker-0000000011" "$sj/mc-alpha-worker-0000000012"
mkfifo "$sj/mc-alpha-worker-0000000011/journal"
# A time too long to be an epoch second is passed over, never summed.
{
  printf 'r10\tpermission\t%s\tpending\n' "$NOW"
  printf 'r12\tpermission\t%s\tanswered\t%s\n' 1234567890123456789012345 1234567890123456789012399
} >"$sj/mc-alpha-worker-0000000012/journal"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_rc "measure beside a FIFO journal" 0
expect_out "a pending request's zero wait is a number" "approvals${tab}permission${tab}1${tab}0${tab}0${tab}0${tab}mc-alpha-worker-0000000012${tab}1${tab}0"
# A journal that is a symbolic link is not read, so no journal counts twice.
mkdir -p "$sj/mc-alpha-worker-0000000013"
ln -s ../mc-alpha-worker-0000000012/journal "$sj/mc-alpha-worker-0000000013/journal"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "a linked journal is not read" "approvals${tab}permission${tab}1${tab}0${tab}0${tab}0${tab}mc-alpha-worker-0000000012${tab}1${tab}0"

# A total counts only the time inside the window: a request, a stall or a
# step that began before it keeps its own length as its typical value.
rm -rf "$sj"
mkdir -p "$sj/mc-alpha-worker-0000000012" "$stall"
printf 'r11\tpermission\t%s\tanswered\t%s\n' $((NOW - 87000)) $((NOW - 86000)) >"$sj/mc-alpha-worker-0000000012/journal"
printf '1793500000:t1\thash\t%s\tidle\n' $((NOW - 90000)) >"$stall/mc-alpha-worker-0000000001"
rec "$steps/000002/007-step-convergence.rec" slowlint 2026-10-31T11:00:00Z 2026-10-31T13:00:00Z passed 000002 007
mc_run mc-throughput.sh top --program alpha --now "$NOW"
expect_out "a request that began before the window adds only its time inside" \
  "approvals${tab}permission${tab}1${tab}1000${tab}400${tab}1000${tab}mc-alpha-worker-0000000012${tab}0${tab}-"
expect_out "a step that began before the window, measured by its end, adds only its time inside" \
  "step${tab}slowlint${tab}1${tab}7200${tab}3600${tab}7200${tab}feature"
expect_out "a stall's total is its time inside the window" \
  "top${tab}stalls${tab}86400${tab}Top bottleneck over the last 1d: Stalled or idle sessions: 1 past 30m, 24h in all, longest 25h"
rm -f "$steps/000002/007-step-convergence.rec"
rm -rf "$stall"

# A branch name's control bytes, C1 ones in UTF-8 included, never reach the
# output.
cbr=$(printf 'feat\302\2332J')
git -C "$repo" worktree add -q -b "$cbr" "$tmp/wtc" 2>/dev/null || fail "fixture control-byte worktree"
mkdir -p "$tmp/wtc/.claude/steps/000001"
rec "$tmp/wtc/.claude/steps/000001/002-step-convergence.rec" ctrlstep 2026-11-01T11:00:00Z 2026-11-01T11:10:00Z passed 000001 002
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "a branch name loses its control bytes" "step${tab}ctrlstep${tab}1${tab}600${tab}600${tab}600${tab}feat2J"
expect_no_out "and none reaches the output" "$cbr"
git -C "$repo" worktree remove --force "$tmp/wtc" 2>/dev/null

# A step cache that is a link is refused by its reader, so the steps are
# unknown, never read as empty.
git -C "$repo" worktree add -q -b linked "$tmp/wtl" 2>/dev/null || fail "fixture linked worktree"
mkdir -p "$tmp/linkedsteps/000001" "$tmp/wtl/.claude"
rec "$tmp/linkedsteps/000001/002-step-convergence.rec" linkstep 2026-11-01T11:00:00Z 2026-11-01T11:10:00Z passed 000001 002
ln -s "$tmp/linkedsteps" "$tmp/wtl/.claude/steps"
mc_run mc-throughput.sh measure --program alpha --now "$NOW"
expect_out "a linked step cache is unknown" "source${tab}steps${tab}unknown${tab}cannot read the step records of $tmp/wtl"
git -C "$repo" worktree remove --force "$tmp/wtl" 2>/dev/null

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
