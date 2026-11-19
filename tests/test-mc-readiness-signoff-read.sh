#!/bin/bash
# Tests for scripts/mc-readiness.sh: a bundle's requirements.md read at the
# head for its sign-off, each way it can fail named apart with its path, and
# the read made the same whatever directory readiness is launched from
# (mission-control REQ-D1.13).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-signoff-read.sh
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
legacy() { # legacy: the demo bundle's requirements.md in the pre-pipeline form, with no Status line
  printf '# Demo Requirements\n\n## Section\n\n- The system shall do the thing.\n' >"$repo/specs/demo/requirements.md"
}
legacy_row="unsigned${tab}its requirements.md has no **Status:** line at the head (a legacy bundle no kickoff signed off): add **Status:** Draft to the header of specs/demo/requirements.md and sign the bundle off with /spec-kickoff, or leave the bundle out of this pull request"

bundle demo Ready signed
spec_pr "$(commit_specs)" specs/demo/design.md
row "a current-format Ready bundle is signed off" "signed${tab}-"

bundle demo Ready none
legacy
spec_pr "$(commit_specs)" specs/demo/design.md
row "a legacy bundle with no Status line is refused by name, the line to add and its path given" "$legacy_row"

bundle demo Ready signed
rm "$repo/specs/demo/requirements.md"
sh_gone=$(commit_specs)
spec_pr "$sh_gone" specs/demo/design.md
row "a bundle with no requirements.md is told apart, its path named" \
  "unsigned${tab}it has no requirements.md at the head (specs/demo/requirements.md)"
spec_pr "$sh_gone" 'specs/demo/requirements.md|DELETED'
row "and so is one whose pull request deletes it" \
  "unsigned${tab}it has no requirements.md at the head (specs/demo/requirements.md)"

bundle demo Ready signed
rm "$repo/specs/demo/requirements.md"
mkdir -p "$repo/specs/demo/requirements.md"
printf 'x\n' >"$repo/specs/demo/requirements.md/inner.md"
spec_pr "$(commit_specs)" specs/demo/design.md
row "a requirements.md that is a directory is unreadable, its path named" \
  "unsigned${tab}its requirements.md cannot be read at the head (specs/demo/requirements.md is not a file)"
rm -rf "$repo/specs/demo/requirements.md"

bundle demo Ready signed
printf '# demo\n\n**Status:** Ready\n**Format-version:** 2\n\nBody.\n' >"$repo/specs/demo/elsewhere.md"
rm "$repo/specs/demo/requirements.md"
ln -s elsewhere.md "$repo/specs/demo/requirements.md"
spec_pr "$(commit_specs)" specs/demo/design.md
row "a requirements.md that is a symbolic link to a Ready file is not followed" \
  "unsigned${tab}its requirements.md cannot be read at the head (specs/demo/requirements.md is not a file)"
rm -f "$repo/specs/demo/requirements.md" "$repo/specs/demo/elsewhere.md"

bundle demo Ready signed
sh_lost=$(commit_specs)
lost=$(git -C "$repo" rev-parse "$sh_lost:specs/demo/requirements.md")
lost_obj="$repo/.git/objects/$(printf '%s' "$lost" | cut -c1-2)/$(printf '%s' "$lost" | cut -c3-)"
mv "$lost_obj" "$tmp/lost-object"
spec_pr "$sh_lost" specs/demo/design.md
row "a requirements.md whose object git cannot read is told apart from a missing one" \
  "unsigned${tab}its requirements.md cannot be read at the head (git could not read specs/demo/requirements.md)"
mv "$tmp/lost-object" "$lost_obj"

bundle demo Ready signed
printf '# demo\n\n**Status:** Ready\n\nA NUL \000 byte.\n' >"$repo/specs/demo/requirements.md"
spec_pr "$(commit_specs)" specs/demo/design.md
row "a NUL-bearing requirements.md is unreadable, its path named" \
  "unsigned${tab}its requirements.md cannot be read at the head (specs/demo/requirements.md holds a NUL byte)"

bundle demo Ready signed
printf '# demo\n\n**Status:** Ready\n**Status:** Draft\n\nBody.\n' >"$repo/specs/demo/requirements.md"
spec_pr "$(commit_specs)" specs/demo/design.md
row "a requirements.md declaring Status twice is told apart, its path named" \
  "unsigned${tab}its requirements.md declares **Status:** more than once at the head (specs/demo/requirements.md)"

# Launched from elsewhere, with a scratch directory given relative to it, the
# read still resolves against the program's repository. The other repository
# holds a Ready bundle of the same name, so a read from the caller's directory
# would report its missing brief instead.
elsewhere="$tmp/elsewhere"
other="$tmp/other-repo"
mkdir -p "$elsewhere/scratch" "$other/specs/demo" "$other/scratch"
git init -q "$other"
printf '# demo\n\n**Status:** Ready\n**Format-version:** 2\n\nBody.\n' >"$other/specs/demo/requirements.md"
bundle demo Ready signed
sh_ready=$(commit_specs)
for dir in "$elsewhere" "$other"; do
  MC_ENV_CWD=$dir TMPDIR=scratch spec_pr "$sh_ready" specs/demo/design.md
  row "a Ready bundle is signed off when readiness is launched from $dir" "signed${tab}-"
done
bundle demo Ready none
legacy
sh_legacy=$(commit_specs)
MC_ENV_CWD=$other TMPDIR=scratch spec_pr "$sh_legacy" specs/demo/design.md
row "a legacy bundle is read from the program's repository, not the caller's" "$legacy_row"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-signoff-read: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-signoff-read: all passed"
