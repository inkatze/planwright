#!/bin/bash
# Tests for scripts/mc-duties.sh — the merged duties catalog: the shipped
# set, overlay additions and supersedes, and what an enabled duty arms
# (mission-control REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-duties.sh
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

[ -f "$repo_root/scripts/mc-duties.sh" ] || {
  echo "FAIL: scripts/mc-duties.sh missing" >&2
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

# ---------------------------------------------------------------------------
# REQ-C1.2: the shipped catalog resolves with no overlay, and holds every
# duty the shipped default set enables.
# ---------------------------------------------------------------------------
shipped_core=$core
core=$repo_root
: >"$tracked"
mc_run mc-duties.sh list
expect_rc "REQ-C1.2: the shipped catalog resolves with no overlay" 0
for id in $(sed -n 's/^mission_control_default_duties: \[\(.*\)\]$/\1/p' "$repo_root/config/defaults.yml" | tr ',' ' '); do
  expect_out "REQ-C1.2: the shipped catalog holds default duty '$id'" "$id${tab}core"
done
mc_run mc-duties.sh validate
expect_rc "REQ-C1.1: every shipped entry validates" 0
core=$shipped_core

# ---------------------------------------------------------------------------
# REQ-C1.3: an overlay adds a custom duty and supersedes a shipped one; the
# merged view shows both.
# ---------------------------------------------------------------------------
reset_mc_fixture
cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
duties:
  - id: alpha-duty
    supersede: true
    summary: "The team's own alpha"
    triggers: []
    watchers: [scripts/team-alpha.sh@15m/low]
    wake: alpha-due
    rules: []
    kinds: []
    files: alpha
    lifecycle: live
    never-propose: false
  - id: custom-duty
    summary: "A custom duty no core edit added"
    triggers: []
    watchers: [scripts/custom-watch.sh@2m/medium]
    wake: custom-due
    rules: []
    kinds: [custom-item]
    files: custom
    lifecycle: shadow
    never-propose: false
EOF
mc_run mc-duties.sh list
expect_rc "REQ-C1.3: the overlaid catalog resolves" 0
expect_eq "REQ-C1.3: the merged view shows the superseded and the added duty" "alpha-duty${tab}repo-tracked
beta-duty${tab}core
custom-duty${tab}repo-tracked"
mc_run mc-duties.sh get alpha-duty summary
expect_eq "REQ-C1.3: the superseding entry's fields replace the shipped ones" "The team's own alpha"
mc_run mc-duties.sh get custom-duty watchers
expect_eq "REQ-C1.3: the added duty's fields resolve" "[scripts/custom-watch.sh@2m/medium]"
mc_run mc-duties.sh get no-such-duty summary
expect_rc "an unknown duty is not found" 3
expect_err "the unknown duty is named" "no-such-duty"
mc_run mc-duties.sh get alpha-duty colour
expect_rc "an unknown field is a usage error" 2

# The adopter overlay adds through the same mechanism.
cat >"$adopter/catalogs/duties.yaml" <<'EOF'
duties:
  - id: adopter-duty
    summary: "An adopter's duty"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: []
    files: adopter
    lifecycle: off
    never-propose: false
EOF
mc_run mc-duties.sh list
expect_out "REQ-C1.3: an adopter overlay adds a duty too" "adopter-duty${tab}adopter"

# ---------------------------------------------------------------------------
# REQ-C1.4: what an enabled duty arms; a disabled duty arms nothing and owns
# nothing.
# ---------------------------------------------------------------------------
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, beta-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "REQ-C1.4: watchers resolve for a program" 0
expect_eq "REQ-C1.4: an enabled live duty arms its watchers, an off one none" "alpha-duty${tab}scripts/alpha-watch.sh${tab}5m${tab}low
alpha-duty${tab}scripts/alpha-sweep.sh${tab}1h${tab}medium"
mc_run mc-duties.sh files --program alpha
expect_eq "REQ-C1.4: an enabled live duty owns its directory, an off one none" "alpha-duty${tab}alpha"

# alpha-duty disabled: the program enables only beta-duty, which is off.
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [beta-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "REQ-C1.4: a program with no armed duty resolves" 0
expect_eq "REQ-C1.4: a disabled duty resolves to no watchers" ""
mc_run mc-duties.sh files --program alpha
expect_eq "REQ-C1.4: a disabled duty resolves to no files" ""

cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, ghost-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "REQ-C1.2: an enabled id the catalog lacks fails" 1
expect_err "REQ-C1.2: the unknown id is named" "ghost-duty"

mc_run mc-duties.sh watchers
expect_rc "watchers without --program is a usage error" 2
mc_run mc-duties.sh bogus
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-duties: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-duties: all passed"
