#!/bin/bash
# Tests for scripts/mc-readiness.sh: spec edits covering a change, their sign-off
# read at the head, the drift and sign-off rows in the walk, and a spec root
# that is the repository root (REQ-D1.13).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-drift-signoff.sh
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

# A spec edit with its anchor re-signed covers the change; a stale anchor does not.
git -C "$repo" reset -q --hard "$dr_base"
printf 'changed\n' >>"$repo/app/run.sh"
printf 'An amendment.\n' >>"$repo/specs/demo/design.md"
dr_stale=$(dr_commit "feat: the file and an unsigned spec edit")
dr_pr "$dr_stale" "## Summary" main app/run.sh specs/demo/design.md
has "the collection ran at the head" "head${tab}$dr_stale"
hasnt "a changed anchored spec covers the file" "drift${tab}"
has "REQ-D1.13: but its edit is read against the sign-off, which no longer matches" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
expect_out "the walk refuses the unsigned edit on a code pull request" "fail${tab}signoff${tab}demo: its content at the head is not what the kickoff signed off"
resign
dr_signed=$(dr_commit "feat: the file and the re-signed spec edit")
dr_pr "$dr_signed" "## Summary" main app/run.sh specs/demo/design.md specs/demo/kickoff-brief.md
hasnt "a re-signed spec edit leaves no drift row" "drift${tab}"
has "and its sign-off is read as signed" "signoff${tab}demo${tab}signed${tab}-"
expect_no_out "the walk raises no drift or sign-off failure for it" "fail${tab}drift"
expect_no_out "nor a sign-off one" "fail${tab}signoff"

# A status annotation alone is no spec edit.
git -C "$repo" reset -q --hard "$dr_base"
printf 'changed\n' >>"$repo/app/run.sh"
sed 's/\*\*Status:\*\* Ready/**Status:** Active/' "$repo/specs/demo/requirements.md" >"$tmp/req" && cat "$tmp/req" >"$repo/specs/demo/requirements.md"
dr_status=$(dr_commit "feat: the file and a status flip")
dr_pr "$dr_status" "## Summary" main app/run.sh specs/demo/requirements.md
has "REQ-D1.13: a status annotation alone does not cover the file" "drift${tab}app/run.sh${tab}demo/1"
git -C "$repo" reset -q --hard "$dr_base"
walk_with "drift row" '-' "drift${tab}app/run.sh${tab}demo/1"
expect_rc "a drift row refuses the walk" 4
walk_with "unsigned edit" '-' "signoff${tab}demo${tab}unsigned${tab}its status at the head is Draft"
expect_out "an unsigned sign-off row binds a pull request that is not spec-only" "fail${tab}signoff${tab}demo: its status at the head is Draft"

# A rename or copy brings the path gates of both its ends; a rename also brings
# the sign-off of the bundle it leaves, which a copy leaves unchanged.
cp "$mchome/gates.tsv" "$tmp/gates.keep"
printf 'ready\tpath\tscripts/*\tsteps\tscripts-gate\n' >>"$mchome/gates.tsv"
gate_fail="fail${tab}step${tab}scripts-gate is not recorded"
dr_pr "$dr_base" "## Summary" main 'tools/tool.sh|RENAMED|scripts/tool.sh'
has "the rename's source is collected" "path${tab}tools/tool.sh${tab}RENAMED${tab}scripts/tool.sh"
expect_out "a rename out of a gated path keeps that path's gate" "$gate_fail"
dr_pr "$dr_base" "## Summary" main 'scripts/tool.sh|RENAMED|tools/tool.sh'
expect_out "a rename into a gated path takes that path's gate" "$gate_fail"
dr_pr "$dr_base" "## Summary" main 'tools/copy.sh|COPIED|scripts/tool.sh'
expect_out "a copy out of a gated path keeps that path's gate" "$gate_fail"
dr_pr "$dr_base" "## Summary" main 'docs/new.md|RENAMED|docs/old.md'
has "the unrelated rename's source is collected" "path${tab}docs/new.md${tab}RENAMED${tab}docs/old.md"
expect_no_out "a rename within an unrelated directory takes no path gate" "$gate_fail"
hasnt "nor a sign-off" "signoff${tab}"
cp "$tmp/gates.keep" "$mchome/gates.tsv"
git -C "$repo" reset -q --hard "$dr_base"
mkdir -p "$repo/docs"
git -C "$repo" mv specs/demo/design.md docs/design.md
dr_out=$(dr_commit "docs: move a spec file out of its bundle")
dr_pr "$dr_out" "## Summary" main 'docs/design.md|RENAMED|specs/demo/design.md'
has "a rename out of a bundle is held for that bundle's sign-off" "signoff${tab}demo${tab}unsigned${tab}"
expect_out "and the walk refuses it" "fail${tab}signoff${tab}demo: "
git -C "$repo" reset -q --hard "$dr_base"
dr_pr "$dr_base" "## Summary" main 'docs/design.md|COPIED|specs/demo/design.md'
has "the copy's source is collected" "path${tab}docs/design.md${tab}COPIED${tab}specs/demo/design.md"
hasnt "a copy out of a bundle holds nothing of the bundle it leaves unchanged" "signoff${tab}demo${tab}"

sed -i.bak "s|^program_alpha_spec_root: .*|program_alpha_spec_root: $repo|" "$tracked"
sh_ready=$dr_base
spec_pr "$sh_ready" specs/demo/requirements.md
hasnt "a spec root that is the repository root exempts nothing" "scope${tab}"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-drift-signoff: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-drift-signoff: all passed"
