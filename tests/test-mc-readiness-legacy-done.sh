#!/bin/bash
# Tests for scripts/mc-readiness.sh: a Done bundle finished before kickoff
# existed, with no kickoff brief at the head or at the pull request's base,
# is accepted as legacy and named so on its signoff row; every other bundle
# with no brief, a brief that fails its anchor, a brief the pull request
# deletes, and a base that cannot be read still refuse.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-legacy-done.sh
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

row() { # row <label> <want>: the demo bundle's signoff row is exactly <want>
  if printf '%s\n' "$c" | grep -qxF "signoff${tab}demo${tab}$2"; then
    ok "$1"
  else
    fail "$1: want 'signoff${tab}demo${tab}$2', got: $(printf '%s\n' "$c" | grep "^signoff${tab}" | head -n 3)"
  fi
}
walk_collected() { # walk_collected: walk the evidence spec_pr collected
  mv "$tmp/collected" "$tmp/ev"
  mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
}
base_at() { # base_at <sha>: the pull request's base, origin/main, at <sha>
  git -C "$repo" update-ref refs/remotes/origin/main "$1"
}
edit() { # edit: change the demo bundle's design, print the new head
  printf 'An edit.\n' >>"$repo/specs/demo/design.md"
  commit_specs
}
nobrief="unsigned${tab}it has no kickoff brief at the head"

# A legacy Done bundle, briefless at the base and the head, is accepted.
bundle demo Done none
base_at "$(commit_specs)"
spec_pr "$(edit)" specs/demo/design.md
row "a Done bundle with no kickoff brief at the head or the base is accepted as legacy" \
  "signed${tab}legacy, no kickoff brief"
walk_collected
expect_no_out "the walk raises no sign-off failure for the legacy bundle" "fail${tab}signoff"
mkdir -p "$repo/app"
printf 'run\n' >"$repo/app/run.sh"
git -C "$repo" add app
spec_pr "$(edit)" specs/demo/design.md app/run.sh
hasnt "a pull request that also changes code is no spec-only scope" "scope${tab}"
row "and the legacy bundle it edits is accepted there too" "signed${tab}legacy, no kickoff brief"
git -C "$repo" rm -rq app

# A base that does not hold the bundle at all is briefless too.
git -C "$repo" rm -rq specs/demo
base_at "$(commit_specs)"
bundle demo Done none
spec_pr "$(commit_specs)" 'specs/demo/requirements.md|ADDED' 'specs/demo/design.md|ADDED'
row "a legacy Done bundle the base lacks is accepted" "signed${tab}legacy, no kickoff brief"

# Only Done is legacy.
for st in Active Ready Draft; do
  bundle demo "$st" none
  base_at "$(commit_specs)"
  spec_pr "$(edit)" specs/demo/design.md
  case $st in
    Draft) row "a Draft bundle with no kickoff brief is refused by its status" "unsigned${tab}its status at the head is Draft" ;;
    *) row "an $st bundle with no kickoff brief is refused" "$nobrief" ;;
  esac
done

# A Done bundle whose brief exists but fails its anchor is never legacy.
bundle demo Done stale
base_at "$(commit_specs)"
spec_pr "$(edit)" specs/demo/design.md
row "a Done bundle whose brief's anchor no longer recomputes is refused" \
  "unsigned${tab}its content at the head is not what the kickoff signed off (the anchor differs)"
bundle demo Done none
printf '# Brief\n\nNo anchor here.\n' >"$repo/specs/demo/kickoff-brief.md"
base_at "$(commit_specs)"
spec_pr "$(edit)" specs/demo/design.md
row "a Done bundle with a hand-written brief recording no anchor is refused" \
  "unsigned${tab}its kickoff brief records no anchor"
bundle demo Done none
mkdir -p "$repo/specs/demo/kickoff-brief.md"
printf 'x\n' >"$repo/specs/demo/kickoff-brief.md/inner.md"
base_at "$(commit_specs)"
spec_pr "$(edit)" specs/demo/design.md
row "a Done bundle whose kickoff-brief.md is a directory is not legacy" \
  "unsigned${tab}its kickoff-brief.md cannot be read at the head (specs/demo/kickoff-brief.md is not a file)"
rm -rf "$repo/specs/demo/kickoff-brief.md"

# The deletion path: a brief the base holds, or the diff deletes, is not legacy.
bundle demo Done signed
base_at "$(commit_specs)"
rm "$repo/specs/demo/kickoff-brief.md"
sh_deleted=$(commit_specs)
spec_pr "$sh_deleted" 'specs/demo/kickoff-brief.md|DELETED'
row "a Done bundle whose brief the pull request deletes is refused" \
  "unsigned${tab}it has no kickoff brief at the head, and the pull request deletes specs/demo/kickoff-brief.md"
spec_pr "$sh_deleted" specs/demo/design.md
row "and so it is when the forge's file list does not show the deletion" \
  "unsigned${tab}it has no kickoff brief at the head, but the pull request's base origin/main holds one (specs/demo/kickoff-brief.md)"
base_at "$sh_deleted"
spec_pr "$sh_deleted" 'specs/demo/kickoff-brief.md|DELETED'
row "a deletion the forge's file list shows is refused even when the base lacks the brief" \
  "unsigned${tab}it has no kickoff brief at the head, and the pull request deletes specs/demo/kickoff-brief.md"

# A base that cannot be read refuses rather than guesses.
bundle demo Done none
sh_unread=$(commit_specs)
git -C "$repo" update-ref -d refs/remotes/origin/main
spec_pr "$sh_unread" specs/demo/design.md
row "a Done bundle whose base is not in the repository is refused, the fetch named" \
  "unsigned${tab}it has no kickoff brief at the head, and the pull request's base origin/main is not in this repository to rule out a deleted one; fetch it"

# A Done bundle with a brief that recomputes is signed off as before.
bundle demo Done signed
base_at "$(commit_specs)"
spec_pr "$(commit_specs)" specs/demo/design.md
row "a Done bundle with a recomputing brief is signed off, not legacy" "signed${tab}-"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-legacy-done: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-legacy-done: all passed"
