#!/bin/bash
# Tests for scripts/mc-readiness.sh: a drift check that cannot run is a row with
# its reason, and a change touching no listed deliverable passes (REQ-D1.13).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-drift-base.sh
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

# shellcheck source=tests/lib/mc-readiness-fixture.sh
. "$here/lib/mc-readiness-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-collect-fixture.sh
. "$here/lib/mc-readiness-collect-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-spec-fixture.sh
. "$here/lib/mc-readiness-spec-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-drift-fixture.sh
. "$here/lib/mc-readiness-drift-fixture.sh"

dr_pr "$dr_a" "## Summary" nosuchbase app/run.sh
has "REQ-D1.13: a drift check that cannot run is a row with its reason" "drift${tab}*${tab}the base refs/remotes/origin/nosuchbase is not a commit"
expect_out "and the walk refuses with it" "fail${tab}drift${tab}the spec-drift check could not run: the base refs/remotes/origin/nosuchbase is not a commit"
dr_pr "$dr_a" "## Summary" "" app/run.sh
has "a pull request naming no base branch cannot be checked" "drift${tab}*${tab}the pull request names no base branch"
git -C "$repo" reset -q --hard "$dr_base"
printf 'prose change\n' >>"$repo/app/prose.sh"
printf 'x\n' >>"$repo/src/other.c"
dr_u=$(dr_commit "feat: unlisted")
dr_pr "$dr_u" "## Summary" main src/other.c app/prose.sh
has "the collection ran at the head" "head${tab}$dr_u"
hasnt "a change touching no listed deliverable (prose path included) passes untouched" "drift${tab}"
hasnt "and edits no bundle, so reads no sign-off" "signoff${tab}"
expect_no_out "the walk raises no drift or sign-off failure" "fail${tab}drift"
dr_pr "$dr_base" "## Summary" main src/other.c specs/gone/design.md
has "the collection ran at the head" "head${tab}$dr_base"
hasnt "a bundle absent at the head (removed or moved) has no sign-off to read" "signoff${tab}gone"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-drift-base: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-drift-base: all passed"
