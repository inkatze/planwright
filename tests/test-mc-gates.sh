#!/bin/bash
# Tests for scripts/mc-gates.sh — gate conditions as data per program,
# repository, label and path, refused at load when one would authorize a
# merge or place a flip below ready_flip_policy (mission-control REQ-I1.7;
# D-26).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-gates.sh
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-gates.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
printf 'ready_flip_policy: unit-owner\n' | write_core_defaults
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
EOF
mkdir -p "$mchome"
gates="$mchome/gates.tsv"

# ---------------------------------------------------------------------------
# No file: every condition takes its default.
# ---------------------------------------------------------------------------
mc_run mc-gates.sh resolve --program alpha --repo acme/web
expect_rc "a program with no gate file resolves" 0
expect_eq "the defaults: offer the flip, recommend once ready, graph order, conflicts to the operator" \
  "ready${tab}flip${tab}offer
merge${tab}recommend${tab}ready
merge${tab}order${tab}graph
merge${tab}method${tab}-
merge${tab}conflicts${tab}operator"

# ---------------------------------------------------------------------------
# REQ-I1.7: per-repository, label and path conditions evaluate as data.
# ---------------------------------------------------------------------------
cat >"$gates" <<'EOF'
# format: 1
# Everything in the program needs the polish pass.
merge	repo	acme/api	method	merge
ready	program	*	steps	polish
ready	repo	acme/web	steps	cubic-pr
ready	label	ui	evidence	screenshot
ready	path	docs/*	body	## Walkthrough
merge	program	*	method	squash
merge	repo	acme/web	conflicts	session
EOF
mc_run mc-gates.sh check --program alpha
expect_rc "REQ-I1.7: a valid gate file loads" 0
mc_run mc-gates.sh resolve --program alpha --repo acme/web --label ui --path docs/guide/intro.md --path src/a.c
expect_rc "a resolve" 0
expect_out "REQ-I1.7: the program's step applies" "ready${tab}steps${tab}polish"
expect_out "REQ-I1.7: the repository's step applies" "ready${tab}steps${tab}cubic-pr"
expect_out "REQ-I1.7: the label's evidence applies" "ready${tab}evidence${tab}screenshot"
expect_out "REQ-I1.7: the path's body text applies, a glob crossing directories" "ready${tab}body${tab}## Walkthrough"
expect_out "the program's method applies where no repository names one" "merge${tab}method${tab}squash"
expect_out "the repository's conflict rule applies" "merge${tab}conflicts${tab}session"
mc_run mc-gates.sh resolve --program alpha --repo acme/api
expect_out "REQ-I1.7: a repository's method wins over the program's, even written earlier" "merge${tab}method${tab}merge"
expect_no_out "REQ-I1.7: another repository's step does not apply" "cubic-pr"
mc_run mc-gates.sh resolve --program alpha --repo ACME/Web --label UI
expect_out "a slug and a label match whatever their case" "ready${tab}evidence${tab}screenshot"
expect_out "the repository's rows too" "ready${tab}steps${tab}cubic-pr"
mc_run mc-gates.sh resolve --program alpha --repo acme/web --label backend --path src/a.c
expect_no_out "an unmatched label adds nothing" "screenshot"
expect_no_out "an unmatched path adds nothing" "Walkthrough"
mc_run mc-gates.sh resolve --program alpha --repo acme/api
expect_out "and the conflicts default stays" "merge${tab}conflicts${tab}operator"
cp "$gates" "$tmp/keep"
printf 'merge\tpath\tsrc/*\tconflicts\tsession\nmerge\tlabel\tui\tconflicts\toperator\nmerge\trepo\tacme/cli\tmethod\tsquash\nmerge\trepo\tacme/cli\tmethod\trebase\nmerge\trepo\t-\tmethod\tmerge\n' >>"$gates"
mc_run mc-gates.sh resolve --program alpha --repo acme/api --label ui --path src/a.c
expect_out "a path's value wins over a label's, written first or not" "merge${tab}conflicts${tab}session"
mc_run mc-gates.sh resolve --program alpha --repo acme/cli
expect_out "a later line wins at the same scope" "merge${tab}method${tab}rebase"
mc_run mc-gates.sh resolve --program alpha
expect_out "with no repository named, no repo line applies" "merge${tab}method${tab}squash"
cp "$tmp/keep" "$gates"
# The runner works from the fixture repository, so this relative name is
# read there; awk would take a bare `bad=1` operand for an assignment.
cp "$gates" "$repo/bad=1"
printf 'merge\tprogram\t*\tauto-merge\ttrue\n' >>"$repo/bad=1"
mc_run mc-gates.sh check --file "bad=1"
expect_rc "a relative file named like an assignment is still read" 1
expect_err "and its merge line refused" "would authorize a merge"

# ---------------------------------------------------------------------------
# REQ-I1.7: a condition that would authorize a merge, or place a flip below
# the policy, is refused at load, and nothing resolves from the file.
# ---------------------------------------------------------------------------
cp "$gates" "$tmp/good"
printf 'merge\trepo\tacme/web\tauto-merge\ttrue\n' >>"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "REQ-I1.7: a merge-authorizing key is refused at load" 1
expect_err "REQ-I1.7: the refusal names the merge" "would authorize a merge"
expect_err "and the line" "gates.tsv:10:"
mc_run mc-gates.sh resolve --program alpha --repo acme/web
expect_rc "REQ-I1.7: nothing resolves from a refused file" 1
expect_eq "no condition is printed" ""

cp "$tmp/good" "$gates"
printf 'merge\tprogram\t*\trecommend\tauto\n' >>"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "REQ-I1.7: a merge recommend value of auto is refused" 1
expect_err "named as authorizing a merge" "would authorize a merge"

cp "$tmp/good" "$gates"
printf 'ready\tprogram\t*\tflip\trequest\n' >>"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "a flip request under ready_flip_policy unit-owner loads" 0
printf 'ready_flip_policy: human\n' >>"$tracked"
mc_run mc-gates.sh check --program alpha
expect_rc "REQ-I1.7: a flip request under ready_flip_policy human is refused" 1
expect_err "REQ-I1.7: named as below the policy" "would place a flip below ready_flip_policy (human)"

cp "$tmp/good" "$gates"
printf 'ready\tprogram\t*\tflip\tauto\n' >>"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "an unknown flip value is refused" 1
expect_err "named against the policy" "would place a flip below ready_flip_policy"

cp "$tmp/good" "$gates"
printf 'ready\tprogram\t*\tskip-checks\tyes\n' >>"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "an unknown ready key is refused" 1
expect_err "named" 'unknown ready key "skip-checks"'

# Each malformed line, its fields joined by `|`.
for bad in 'merge|program|*|order|fifo' 'merge|program|*|method|fast-forward' \
  'merge|program|*|conflicts|anyone' 'ready|program|*|steps|Polish Pass' \
  'ready|program|*|evidence|video' 'ready|program|*|steps' 'ready|program|acme|steps|polish' \
  'ready|team|x|steps|polish' 'deploy|program|*|steps|polish'; do
  cp "$tmp/good" "$gates"
  printf '%s\n' "$bad" | tr '|' '\t' >>"$gates"
  mc_run mc-gates.sh check --program alpha
  expect_rc "a malformed line is refused at load: $bad" 1
done

printf 'format: 2\n' >"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "an unknown format is refused" 1
expect_err "named" "unknown format"
: >"$gates"
mc_run mc-gates.sh check --program alpha
expect_rc "an empty file is refused" 1

mc_run mc-gates.sh check --file "$tmp/good"
expect_rc "a file given directly loads" 0
mc_run mc-gates.sh resolve --program beta
expect_rc "an unconfigured program" 3
mc_run mc-gates.sh check --program alpha --repo acme/web
expect_rc "check takes no pull request" 2
mc_run mc-gates.sh resolve --program alpha --repo not-a-slug
expect_rc "resolve refuses a repository that is not owner/name" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-gates: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-gates: all passed"
