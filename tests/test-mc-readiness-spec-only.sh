#!/bin/bash
# Tests for scripts/mc-readiness.sh: a spec-only pull request's scope and its
# bundles' sign-offs read at the head (mission-control REQ-D1.8, REQ-D1.13).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-spec-only.sh
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

# A spec-only pull request: every changed path under the program's spec root,
# each touched bundle's sign-off read at the head from the repository's
# objects, and no cadence audit run (no worktree is needed).
# shellcheck source=tests/lib/mc-readiness-spec-fixture.sh
. "$here/lib/mc-readiness-spec-fixture.sh"
bundle demo Ready signed
sh_ready=$(commit_specs)
spec_pr "$sh_ready" specs/demo/requirements.md specs/demo/design.md specs/_observations/entries/e.md
has "every path under the spec root is a spec-only scope at the head" "scope${tab}spec-only${tab}$sh_ready"
has "the touched bundle's sign-off is read at the head, its anchor recomputed" "signoff${tab}demo${tab}signed${tab}-"
if [ "$(printf '%s\n' "$c" | grep -c "^signoff${tab}")" -eq 1 ]; then ok "one sign-off line per bundle, however many of its files changed"; else fail "the bundle's sign-off is not read exactly once"; fi
hasnt "an observation entry is no bundle" "signoff${tab}_observations"
hasnt "no cadence audit is run or required" "cadence${tab}"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7
expect_no_out "the walk holds it for no cadence" "fail${tab}cadence"
expect_no_out "nor for a gate-data step" "fail${tab}step"
expect_out "while the guard still binds" "fail${tab}guard${tab}ready-guard"
printf '# Specs\n' >"$repo/specs/README.md"
sh_ready=$(commit_specs)
spec_pr "$sh_ready" specs/_observations/entries/e.md specs/README.md
has "an observation and root-file pull request is spec-only" "scope${tab}spec-only${tab}$sh_ready"
hasnt "and touches no bundle to sign off" "signoff${tab}"
mv "$tmp/collected" "$tmp/ev"
mc_run mc-readiness.sh walk --evidence "$tmp/ev" --conditions "$tmp/no-conditions"
expect_no_out "its walk asks for no cadence" "fail${tab}cadence"
expect_no_out "nor for a sign-off" "fail${tab}signoff"
spec_pr "$sh_ready" 'specs/demo/requirements.md|COPIED'
hasnt "a copy into the spec root is no spec-only scope" "scope${tab}"
spec_pr "$sh_ready" 'specs/demo/requirements.md|-'
hasnt "a path with no change type is no spec-only scope" "scope${tab}"
spec_pr "$sh_ready" specs/demo/run.sh
hasnt "a file that is not prose is no spec-only scope" "scope${tab}"
spec_pr "$sh_ready" specs/demo/requirements.md src/app.c
hasnt "a code path beside the bundle is no spec-only scope" "scope${tab}"
has "and its cadence is audited as for any pull request" "cadence${tab}unaudited${tab}"
spec_pr "$sh_ready" specsx/demo/requirements.md
hasnt "a sibling of the spec root sharing its prefix is outside it" "scope${tab}"
spec_pr "$sh_ready" specs/../src/app.c
hasnt "a path climbing out of the spec root is outside it" "scope${tab}"
spec_pr "$sh_ready" specs//demo/requirements.md
hasnt "a path with an empty component is outside it" "scope${tab}"
spec_pr "$sh_ready" 'specs/demo/moved.md|RENAMED'
hasnt "a rename into the spec root, its source unnamed, is no spec-only scope" "scope${tab}"
bundle demo Active signed
bundle other Draft signed
sh_two=$(commit_specs)
spec_pr "$sh_two" specs/demo/design.md specs/other/design.md
has "an Active bundle is signed off" "signoff${tab}demo${tab}signed${tab}-"
has "a Draft bundle beside it is not" "signoff${tab}other${tab}unsigned${tab}its status at the head is Draft"
mv "$tmp/collected" "$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_out "the walk holds the pull request for the unsigned bundle" "fail${tab}signoff${tab}other: its status at the head is Draft"
bundle demo Ready none
sh_nobrief=$(commit_specs)
spec_pr "$sh_nobrief" specs/demo/requirements.md
has "a Ready bundle with no kickoff brief is not signed off" "signoff${tab}demo${tab}unsigned${tab}it has no kickoff brief at the head"
bundle demo Ready signed
# shellcheck disable=SC2016 # the brief's backticks are literal
(cd "$repo/specs/demo" && printf '# Brief\n\nAnchor: `%s` — computed as\n`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`\n' \
  "$(git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin)" >kickoff-brief.md)
sh_interim=$(commit_specs)
spec_pr "$sh_interim" specs/demo/requirements.md
has "a brief anchored by the interim whole-file form is signed off" "signoff${tab}demo${tab}signed${tab}-"
anchor_form() { # anchor_form <recorded command>: a signed bundle whose brief records that command
  bundle demo Ready signed
  # shellcheck disable=SC2016 # the brief's backticks are literal
  printf '# Brief\n\nAnchor: `%s` — computed as\n`%s`\n' \
    "$(/bin/sh "$repo_root/scripts/spec-anchor.sh" "$repo/specs/demo")" "$1" >"$repo/specs/demo/kickoff-brief.md"
}
anchor_form 'spec-anchor.sh specs/demo'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a brief anchored by the logical form is signed off" "signoff${tab}demo${tab}signed${tab}-"
anchor_form 'scripts/spec-anchor.sh specs/demo'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a brief anchored by the canonical form is signed off" "signoff${tab}demo${tab}signed${tab}-"
anchor_form 'spec-anchor.sh specs/demo'
printf 'An edit after the sign-off.\n' >>"$repo/specs/demo/design.md"
spec_pr "$(commit_specs)" specs/demo/design.md
has "a logical-form brief over edited content is not signed off" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
anchor_form 'spec-anchor.sh specs/elsewhere'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a logical form naming another directory is not recomputed" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's anchor uses a form this check does not recompute"
anchor_form 'sh ./spec-anchor.sh specs/demo'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a script form with a prefix is not recomputed" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's anchor uses a form this check does not recompute"
# shellcheck disable=SC2016 # the brief's backticks are literal
printf 'Anchor: `%s` — computed as\n`sha1sum specs/demo/*`\n' 0123456789abcdef0123456789abcdef01234567 >>"$repo/specs/demo/kickoff-brief.md"
sh_otherform=$(commit_specs)
spec_pr "$sh_otherform" specs/demo/requirements.md
has "a brief anchored by a form the check does not recompute is not signed off" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's anchor uses a form this check does not recompute"
spec_pr "$sh_ready" 'specs/demo/requirements.md|CHANGED'
hasnt "a type change under the spec root is no spec-only scope" "scope${tab}"
bundle demo Ready stale
sh_stale=$(commit_specs)
spec_pr "$sh_stale" specs/demo/design.md
has "a bundle edited after its sign-off is not signed off" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
bundle demo Ready signed
printf '# demo\n\nBody.\n' >"$repo/specs/demo/requirements.md"
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a requirements.md with no status is not signed off" "signoff${tab}demo${tab}unsigned${tab}its requirements.md has no **Status:** value in its header at the head"
bundle demo Ready signed
printf '# Brief\n\nAnchor: not a hash\n' >"$repo/specs/demo/kickoff-brief.md"
spec_pr "$(commit_specs)" specs/demo/kickoff-brief.md
has "a half-written newest anchor entry is not signed off" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's latest anchor entry does not parse"
bundle demo Ready signed
printf '# Brief\n\nNo sign-off yet.\n' >"$repo/specs/demo/kickoff-brief.md"
spec_pr "$(commit_specs)" specs/demo/kickoff-brief.md
has "a brief recording no anchor is not signed off" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief records no anchor"
bundle demo Ready signed
rm "$repo/specs/demo/design.md"
spec_pr "$(commit_specs)" specs/demo/design.md
has "a bundle whose anchor cannot be recomputed at the head is not signed off" "signoff${tab}demo${tab}unsigned${tab}its anchor cannot be recomputed at the head"
spec_pr 5555555555555555555555555555555555555555 specs/demo/requirements.md
has "a head the repository does not hold is a spec-only scope" "scope${tab}spec-only${tab}5555555555555555555555555555555555555555"
has "held by one unsigned sign-off naming the fetch" "signoff${tab}*${tab}unsigned${tab}the head is not in"
spec_pr "$sh_ready" 'specs/Bad Name/requirements.md'
has "a bundle directory outside the spec identifier grammar is refused" "signoff${tab}Bad Name${tab}unsigned${tab}not a spec identifier"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-spec-only: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-spec-only: all passed"
