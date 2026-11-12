#!/bin/bash
# Tests for the shipped default duties in config/duties.yaml: each resolves
# from the catalog for a program on the default duty set, and its watchers
# arm under the runner (mission-control D-3, D-27).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-default-duties.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Fixture git calls must reach the fixture repositories, never one an
# inherited selector (a git hook's GIT_DIR, say) points at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-default-duties.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

cleanup() {
  (mc_env /bin/bash "$repo_root/scripts/mc-watch.sh" stop --program alpha >/dev/null 2>&1)
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tab=$(printf '\t')
reset_mc_fixture
cp "$repo_root/config/duties.yaml" "$core/config/duties.yaml"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 1000000}
program_alpha_sources: {work-items: specs:record}
EOF
# The watchers' behaviour has its own tests; here each is a no-op stand-in
# under the fixture core, so arming runs nothing that reads a forge.
mkdir -p "$core/scripts"
for s in mc-keeper.sh mc-escalate.sh mc-readiness.sh mc-merge-ready.sh mc-radar.sh mc-deadlines.sh mc-throughput.sh mc-usage.sh; do
  printf '#!/bin/sh\n:\n' >"$core/scripts/$s"
done

mc_run mc-duties.sh files --program alpha
expect_rc "the default duty set resolves" 0
for d in session-keeper inbox readiness-check conflict-radar deadline-watch prepared-moments; do
  expect_out "D-27: $d resolves from the catalog and is armed" "$d${tab}"
done
expect_out "throughput resolves from the catalog and is armed" "throughput${tab}"

mc_run mc-duties.sh get session-keeper triggers
expect_out "the shipped wrapped trigger list joins whole" "stall-dead, stall-open-selector, stall-unsubmitted-prompt, stall-turn-ended-background, stall-idle-question, stall-busy-unchanged, stall-unknown, session-landed, pending-prompt, pending-prompt-overdue, stream-json-worker-dead, stream-json-worker-unowned, keeper-sweep-failed, worker-handover-due, worker-retired-idle, mission-control-escalated]"

mc_run mc-duties.sh watchers --program alpha
expect_rc "the watchers resolve" 0
expect_out "session-keeper's watcher" "session-keeper${tab}scripts/mc-keeper.sh${tab}2m${tab}low"
expect_out "session-keeper's escalation watcher" "session-keeper${tab}scripts/mc-escalate.sh${tab}1m${tab}low"
expect_out "readiness-check's watcher" "readiness-check${tab}scripts/mc-readiness.sh${tab}5m${tab}low"
expect_out "readiness-check's merge watcher" "readiness-check${tab}scripts/mc-merge-ready.sh${tab}5m${tab}low"
expect_out "conflict-radar's watcher" "conflict-radar${tab}scripts/mc-radar.sh${tab}15m${tab}medium"
expect_out "deadline-watch's watcher" "deadline-watch${tab}scripts/mc-deadlines.sh${tab}1h${tab}low"
expect_out "throughput's watcher" "throughput${tab}scripts/mc-throughput.sh${tab}15m${tab}medium"
expect_out "usage-window's watcher" "usage-window${tab}scripts/mc-usage.sh${tab}2m${tab}low"

mc_run mc-watch.sh pass --program alpha
expect_rc "a runner pass" 0
for w in session-keeper:mc-keeper.sh session-keeper:mc-escalate.sh readiness-check:mc-readiness.sh readiness-check:mc-merge-ready.sh conflict-radar:mc-radar.sh deadline-watch:mc-deadlines.sh usage-window:mc-usage.sh; do
  expect_out "D-27: the watcher arms under the runner: ${w%%:*}" "armed${tab}${w%%:*}${tab}scripts/${w#*:}"
done
expect_out "the watcher arms under the runner: throughput" "armed${tab}throughput${tab}scripts/mc-throughput.sh"
expect_no_out "nothing is unresolvable" "unresolvable"
mc_run mc-watch.sh stop --program alpha
expect_rc "the watchers stop" 0

for s in mc-keeper.sh mc-escalate.sh mc-readiness.sh mc-merge-ready.sh mc-radar.sh mc-deadlines.sh mc-throughput.sh mc-usage.sh; do
  if [ -x "$repo_root/scripts/$s" ]; then ok "the shipped $s exists"; else fail "the shipped $s is missing"; fi
done

if [ "$failures" -ne 0 ]; then
  echo "test-mc-default-duties: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-default-duties: all passed"
