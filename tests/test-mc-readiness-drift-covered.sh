#!/bin/bash
# Tests for scripts/mc-readiness.sh: a changed spec deliverable with no spec edit
# is drift, and a Not covered line clears it (mission-control REQ-D1.13).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-drift-covered.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Fixture git calls must reach the fixture repositories, never one an
# inherited selector (a git hook's GIT_DIR, say) points at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-readiness-fixture.sh
. "$here/lib/mc-readiness-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-collect-fixture.sh
. "$here/lib/mc-readiness-collect-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-spec-fixture.sh
. "$here/lib/mc-readiness-spec-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-drift-fixture.sh
. "$here/lib/mc-readiness-drift-fixture.sh"

dr_pr "$dr_a" "## Summary" main app/run.sh
has "REQ-D1.13: a changed listed deliverable with no spec edit is collected as drift" "drift${tab}app/run.sh${tab}demo/1"
expect_rc "the walk refuses it" 4
expect_out "naming the file and the task" "fail${tab}drift${tab}app/run.sh is a deliverable of demo/1"
dr_pr "$dr_a" "Not covered: app/run.sh — a comment fix" main app/run.sh
has "the collection ran at the head" "head${tab}$dr_a"
hasnt "a Not covered line naming the file clears the drift row" "drift${tab}"
expect_no_out "and the walk raises no drift failure" "fail${tab}drift"
dr_pr "$dr_a" "Not covered: src/other.c — a comment fix" main app/run.sh
has "a Not covered line naming another path does not excuse it" "drift${tab}app/run.sh${tab}demo/1"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-drift-covered: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-drift-covered: all passed"
