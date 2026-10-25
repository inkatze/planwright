#!/bin/bash
# Tests for scripts/mc-program.sh — the program block read through the
# config resolver: repositories, spec root and its posture, program home,
# enabled duties, budget and the state-source map with its default
# (mission-control REQ-H1.1, REQ-H1.4, REQ-C1.2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-program.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-program.sh" ] || {
  echo "FAIL: scripts/mc-program.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mkdir -p "$repo/specs"

# A program named alpha over two repositories, the spec root inside the first.
other="$tmp/other"
git -C "$tmp" init -q other
alpha_block() { # alpha_block [spec-root]
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo, ~/work/other]
program_alpha_spec_root: ${1:-$repo/specs}
EOF
}

# ---------------------------------------------------------------------------
# No program configured.
# ---------------------------------------------------------------------------
mc_run mc-program.sh list
expect_rc "no program configured lists nothing" 0
expect_eq "the empty program list prints nothing" ""

mc_run mc-program.sh get alpha repositories
expect_rc "an unconfigured program is not found" 3
expect_err "the unconfigured program is named" "alpha"

# ---------------------------------------------------------------------------
# REQ-H1.1: repositories and a spec root.
# ---------------------------------------------------------------------------
alpha_block
mc_run mc-program.sh list
expect_eq "REQ-H1.1: the configured program is listed" "alpha"

mc_run mc-program.sh get alpha repositories
expect_rc "REQ-H1.1: repositories resolve" 0
expect_eq "REQ-H1.1: both repositories resolve, ~/ expanded" "$repo
$fixhome/work/other"

mc_run mc-program.sh get alpha spec_root
expect_eq "REQ-H1.1: the spec root resolves" "$repo/specs"

mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.1: a complete program validates" 0

# REQ-H1.1: the spec root in each posture.
mc_run mc-program.sh posture alpha
expect_eq "REQ-H1.1: a root inside a program repository is same-repo" "same-repo"
mkdir -p "$other/specs"
alpha_block "$other/specs"
mc_run mc-program.sh posture alpha
expect_eq "REQ-H1.1: a root in another repository is separate-repo" "separate-repo"
mkdir -p "$tmp/plain-store"
alpha_block "$tmp/plain-store"
mc_run mc-program.sh posture alpha
expect_eq "REQ-H1.1: a root in no repository is plain" "plain"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.1: a plain-posture program validates" 0

alpha_block "$tmp/no-such-dir"
mc_run mc-program.sh posture alpha
expect_rc "a spec root that is no directory has no posture" 1
expect_err "the missing spec root is named" "spec_root"

# Missing fields are named.
printf 'mission_control_programs: [alpha]\n' >"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.1: a program without repositories or a spec root fails" 1
expect_err "REQ-H1.1: the missing repositories field is named" "alpha: repositories"
expect_err "REQ-H1.1: the missing spec_root field is named" "alpha: spec_root"

printf 'mission_control_programs: [alpha]\nprogram_alpha_repositories: []\nprogram_alpha_spec_root: %s/specs\n' "$repo" >"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.1: an empty repository list fails" 1
expect_err "REQ-H1.1: the empty list is named" "alpha: repositories"

printf 'mission_control_programs: [alpha]\nprogram_alpha_repositories: [relative/path]\nprogram_alpha_spec_root: %s/specs\n' "$repo" >"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "a relative repository path fails" 1
expect_err "the relative path is named" "relative/path"

# ---------------------------------------------------------------------------
# REQ-H1.4: the state-source map.
# ---------------------------------------------------------------------------
alpha_block
mc_run mc-program.sh get alpha sources
expect_rc "REQ-H1.4: a program without a map resolves" 0
expect_eq "REQ-H1.4: a program without a map resolves to the default map" "work-items${tab}specs${tab}record
code-state${tab}forge${tab}snapshot
decisions${tab}specs${tab}record
deadlines${tab}specs${tab}record
designs${tab}-${tab}cited"

printf 'program_alpha_sources: {work-items: jira:cited, code-state: forge:snapshot}\n' >>"$tracked"
mc_run mc-program.sh get alpha sources
expect_eq "REQ-H1.4: a class the map leaves out resolves to cited" "work-items${tab}jira${tab}cited
code-state${tab}forge${tab}snapshot
decisions${tab}-${tab}cited
deadlines${tab}-${tab}cited
designs${tab}-${tab}cited"

alpha_block
printf 'program_alpha_sources: {}\n' >>"$tracked"
mc_run mc-program.sh get alpha sources
expect_out "REQ-H1.4: an explicit empty map leaves every class cited" "work-items${tab}-${tab}cited"

alpha_block
printf 'program_alpha_sources: {code-state: forge:polled}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.4: an unknown mode fails" 1
expect_err "REQ-H1.4: the unknown mode is named" "polled"
mc_run mc-program.sh get alpha sources
expect_rc "REQ-H1.4: an unknown mode refuses the read" 1

alpha_block
printf 'program_alpha_sources: {tickets: jira:cited}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.4: an unknown fact class fails" 1
expect_err "REQ-H1.4: the unknown class is named" "tickets"

alpha_block
printf 'program_alpha_sources: {designs: figma:cited, designs: figma:snapshot}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.4: a class named twice fails" 1
expect_err "REQ-H1.4: the repeated class is named" "designs"

alpha_block
printf 'program_alpha_sources: {designs: figma}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.4: an entry without a mode fails" 1
expect_err "REQ-H1.4: the entry without a mode is named" "source:mode"

alpha_block
printf 'program_alpha_sources: [specs]\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.4: a map that is not an inline map fails" 1
expect_err "REQ-H1.4: the malformed map is named" "alpha: sources"

# ---------------------------------------------------------------------------
# REQ-C1.2: enabled duties default to the shipped set.
# ---------------------------------------------------------------------------
alpha_block
mc_run mc-program.sh get alpha duties
expect_rc "REQ-C1.2: enabled duties resolve" 0
want=$(sed -n 's/^mission_control_default_duties: \[\(.*\)\]$/\1/p' "$repo_root/config/defaults.yml" | tr -d ' ' | tr ',' '\n')
[ -n "$want" ] || fail "the shipped defaults carry no mission_control_default_duties list"
expect_eq "REQ-C1.2: a program naming no duties enables the shipped default set" "$want"

printf 'program_alpha_duties: [beta-duty]\n' >>"$tracked"
mc_run mc-program.sh get alpha duties
expect_eq "REQ-C1.2: a program's own list replaces the default set" "beta-duty"

alpha_block
printf 'program_alpha_duties: []\n' >>"$tracked"
mc_run mc-program.sh get alpha duties
expect_rc "REQ-C1.4: an explicit empty duty list resolves" 0
expect_eq "REQ-C1.4: an explicit empty duty list enables nothing, not the default set" ""

# ---------------------------------------------------------------------------
# The program home and the budget.
# ---------------------------------------------------------------------------
alpha_block
mc_run mc-program.sh get alpha home
expect_eq "the home defaults under the configured home root" "$fixhome/.config/planwright/mission-control/alpha"
printf 'mission_control_home_root: %s/homes\n' "$tmp" >>"$tracked"
mc_run mc-program.sh get alpha home
expect_eq "the home root knob moves every program's default home" "$tmp/homes/alpha"
printf 'program_alpha_home: ~/mc/alpha\n' >>"$tracked"
mc_run mc-program.sh get alpha home
expect_eq "a program's own home wins" "$fixhome/mc/alpha"

alpha_block
printf 'program_alpha_home: relative/home\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "a relative home fails" 1
expect_err "the home field is named" "alpha: home"

alpha_block
printf 'program_alpha_spec_root: /x\033[2Jy\n' >"$tmp/cntrl"
{
  grep -v '^program_alpha_spec_root:' "$tracked"
  cat "$tmp/cntrl"
} >"$tmp/t" && mv "$tmp/t" "$tracked"
mc_run mc-program.sh get alpha spec_root
expect_rc "a path carrying a control byte is refused" 1
expect_err "the refused field is named" "alpha: spec_root"

alpha_block
mc_run mc-program.sh get alpha budget
expect_rc "an absent budget resolves" 0
expect_eq "an absent budget is empty" ""
printf 'program_alpha_budget: {sessions: 4, source_polls_per_hour: 120}\n' >>"$tracked"
mc_run mc-program.sh get alpha budget
expect_eq "the budget map resolves entry by entry" "sessions${tab}4
source_polls_per_hour${tab}120"
alpha_block
printf 'program_alpha_budget: {sessions 4}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "a malformed budget fails" 1
expect_err "the budget field is named" "alpha: budget"

# ---------------------------------------------------------------------------
# Program names.
# ---------------------------------------------------------------------------
cat >"$tracked" <<EOF
mission_control_programs: [team-a]
program_team_a_repositories: [$repo]
program_team_a_spec_root: $repo/specs
EOF
mc_run mc-program.sh get team-a spec_root
expect_eq "a hyphenated program name reads its underscored keys" "$repo/specs"

mc_run mc-program.sh get Bad_Name spec_root
expect_rc "a program name outside the grammar is refused" 2
mc_run mc-program.sh get "../x" spec_root
expect_rc "a traversal program name is refused" 2

printf 'mission_control_programs: [Bad]\n' >"$tracked"
mc_run mc-program.sh list
expect_rc "a program list naming an invalid name fails" 1
expect_err "the invalid name is named" "Bad"

printf 'mission_control_programs: [alpha beta]\n' >"$tracked"
mc_run mc-program.sh list
expect_rc "a program list member carrying a space fails" 1
expect_err "the spaced name is named" "alpha beta"

printf 'mission_control_programs: [alpha, alpha]\n' >"$tracked"
mc_run mc-program.sh list
expect_rc "a program named twice fails" 1

alpha_block
mc_run mc-program.sh get "$(printf 'alpha\nbeta')" spec_root
expect_rc "a program name carrying a newline is refused" 2

# ---------------------------------------------------------------------------
# Members are whole: no word splitting, no repeats.
# ---------------------------------------------------------------------------
alpha_block
printf 'program_alpha_duties: [alpha-duty beta-duty]\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "a duty member carrying a space fails" 1
expect_err "the spaced duty member is named" "alpha-duty beta-duty"

alpha_block
printf 'program_alpha_duties: [alpha-duty, alpha-duty]\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "a duty enabled twice fails" 1
expect_err "the repeated duty is named" "alpha-duty"

cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo, $repo]
program_alpha_spec_root: $repo/specs
EOF
mc_run mc-program.sh validate alpha
expect_rc "a repository named twice fails" 1
expect_err "the repeated repository field is named" "alpha: repositories"

alpha_block
printf 'program_alpha_budget: {sessions: 4, sessions: 5}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "a budget key named twice fails" 1
expect_err "the repeated budget key is named" "sessions"

alpha_block
printf 'program_alpha_sources: {work-items code-state: specs:record}\n' >>"$tracked"
mc_run mc-program.sh validate alpha
expect_rc "REQ-H1.4: a source class carrying a space fails" 1
expect_err "REQ-H1.4: the spaced class is named" "work-items code-state"

# Posture needs a listed repository that exists here.
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$tmp/no-such-repo]
program_alpha_spec_root: $other/specs
EOF
mc_run mc-program.sh posture alpha
expect_rc "posture with no listed repository on this machine fails" 1
expect_err "the missing repositories are named" "alpha: repositories"

# ---------------------------------------------------------------------------
# The by-layer malformed policy: an invalid adopter or machine-local value
# degrades to the next lower layer with a warning; an invalid repo-tracked
# value, or a malformed repo-tracked file, fails.
# ---------------------------------------------------------------------------
alpha_block
printf 'program_alpha_duties: beta-duty\n' >"$adopter/planwright.yml"
mc_run mc-program.sh get alpha duties
expect_rc "an invalid adopter value degrades rather than failing" 0
expect_eq "the degraded read falls back to the shipped default set" "$want"
expect_err "the degrade is warned about, naming the layer" "adopter"
expect_err "the warning carries the parser's reason" "is not an inline list"
mc_run mc-program.sh validate alpha
expect_rc "validate reports a value that only degrades at read time" 1

printf 'program_alpha_duties: [alpha-duty]\n' >"$adopter/planwright.yml"
printf 'program_alpha_duties: [Not An Id]\n' >"$tmp/local.yml"
OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_CONFIG_DEFAULTS \
  PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/local.yml" CLAUDE_DIR="$tmp/claude" HOME="$fixhome" \
  /bin/bash "$repo_root/scripts/mc-program.sh" get alpha duties 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "an invalid machine-local value degrades" 0
expect_eq "it degrades to the adopter layer's value" "alpha-duty"
expect_err "the machine-local degrade is warned about" "machine-local"
rm -f "$adopter/planwright.yml"

alpha_block
printf 'program_alpha_duties: beta-duty\n' >>"$tracked"
mc_run mc-program.sh get alpha duties
expect_rc "an invalid repo-tracked value fails" 1

# validate sees every layer: a value a degrade would hide, the program list
# included, and an invalid value a valid higher layer shadows.
alpha_block
printf 'mission_control_programs: [Alpha, alpha]\n' >"$tmp/local.yml"
OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_CONFIG_DEFAULTS \
  PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/local.yml" CLAUDE_DIR="$tmp/claude" HOME="$fixhome" \
  /bin/bash "$repo_root/scripts/mc-program.sh" validate alpha 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "validate fails on a program list only a degrade would hide" 1

alpha_block
printf 'program_alpha_duties: [Bad_Duty]\n' >>"$tracked"
printf 'program_alpha_duties: [alpha-duty]\n' >"$tmp/local.yml"
OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_CONFIG_DEFAULTS \
  PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/local.yml" CLAUDE_DIR="$tmp/claude" HOME="$fixhome" \
  /bin/bash "$repo_root/scripts/mc-program.sh" validate alpha 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "validate fails on an invalid value a higher layer shadows" 1
expect_err "the shadowed value is named" "Bad_Duty"

alpha_block
printf 'nested:\n  child: 1\n' >>"$tracked"
mc_run mc-program.sh list
expect_rc "a malformed repo-tracked file fails the read, never reads as unset" 1
mc_run mc-program.sh default duties
expect_rc "a malformed repo-tracked file fails a default read too" 1

alpha_block
mc_run mc-program.sh get alpha nonsense
expect_rc "an unknown field is a usage error" 2
mc_run mc-program.sh bogus
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-program: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-program: all passed"
