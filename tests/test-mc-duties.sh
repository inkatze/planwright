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
default_ids=$(sed -n 's/^mission_control_default_duties: \[\(.*\)\]$/\1/p' "$repo_root/config/defaults.yml" | tr ',' ' ')
[ -n "$default_ids" ] || fail "REQ-C1.2: the shipped defaults carry no mission_control_default_duties list"
for id in $default_ids; do
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

# REQ-C1.4: a shadow duty arms like a live one.
reset_mc_fixture
sed -e 's/^    lifecycle: off$/    lifecycle: shadow/' "$core/config/duties.yaml" >"$tmp/d" && mv "$tmp/d" "$core/config/duties.yaml"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [beta-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_eq "REQ-C1.4: an enabled shadow duty arms its watchers" "beta-duty${tab}scripts/beta-watch.sh${tab}10m${tab}high"
mc_run mc-duties.sh files --program alpha
expect_eq "REQ-C1.4: an enabled shadow duty owns its directory" "beta-duty${tab}beta"

# The by-layer malformed policy: an invalid adopter or machine-local entry is
# skipped with a warning; an invalid repo-tracked or core entry refuses the
# catalog.
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, adopter-duty]
EOF
cat >"$adopter/catalogs/duties.yaml" <<'EOF'
duties:
  - id: adopter-duty
    summary: "An adopter's broken duty"
    triggers: []
    watchers: [scripts/adopter.sh@5m/low]
    wake: none
    rules: []
    kinds: []
    files: adopter
    lifecycle: sometimes
    never-propose: false
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "an invalid adopter entry is skipped, not refused" 0
expect_eq "the valid duties still arm" "alpha-duty${tab}scripts/alpha-watch.sh${tab}5m${tab}low
alpha-duty${tab}scripts/alpha-sweep.sh${tab}1h${tab}medium"
expect_err "the skip is warned about, naming the duty and layer" "adopter-duty"
expect_err "the skip names the layer" "adopter layer"

sed -e 's/^  - id: adopter-duty$/  - id: tracked-duty/' "$adopter/catalogs/duties.yaml" >"$repo/.claude/catalogs/duties.yaml"
rm -f "$adopter/catalogs/duties.yaml"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "an invalid repo-tracked entry refuses the catalog" 1
expect_err "the refusal names the duty" "tracked-duty"
expect_err "the catalog is refused, not the duty skipped" "refusing an invalid catalog"
rm -f "$repo/.claude/catalogs/duties.yaml"

# An adopter override taking a later duty's directory is the adopter's
# fault: the override is skipped and the core duty it collided with stays.
# The core entry the override superseded is gone from the merged catalog,
# so it is not restored.
cat >"$adopter/catalogs/duties.yaml" <<'EOF'
duties:
  - id: alpha-duty
    supersede: true
    summary: "An adopter's override taking beta's directory"
    triggers: []
    watchers: [scripts/alpha-watch.sh@5m/low]
    wake: none
    rules: []
    kinds: []
    files: beta
    lifecycle: live
    never-propose: false
EOF
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, beta-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "an adopter override colliding on a directory is skipped, not refused" 0
expect_eq "the skipped override arms nothing, and the off core duty nothing" ""
expect_err "the override is the one skipped" "skipping duty 'alpha-duty' from the adopter layer"

# A layer is named by id, not by place: the resolver groups its output by
# section while --explain lists merge order, so places can disagree.
cat >"$adopter/catalogs/duties.yaml" <<'EOF'
extra:
  - id: gamma-duty
    summary: "A valid adopter duty in its own section"
    triggers: []
    watchers: [scripts/gamma.sh@5m/low]
    wake: none
    rules: []
    kinds: []
    files: gamma
    lifecycle: live
    never-propose: false
EOF
cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
duties:
  - id: tracked-duty
    summary: "An invalid repo-tracked duty"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: []
    files: tracked
    lifecycle: bogus
    never-propose: false
EOF
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, tracked-duty]
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "an invalid repo-tracked entry refuses, whatever section order the overlays use" 1
expect_err "the repo-tracked refusal is reported" "refusing an invalid catalog"
rm -f "$repo/.claude/catalogs/duties.yaml"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, beta-duty]
EOF

# Ids compare as strings: "01" is not "1".
printf 'duties:\n  - id: "1"\n    summary: "x"\n    triggers: []\n    watchers: []\n    wake: none\n    rules: []\n    kinds: []\n    files: one\n    lifecycle: live\n    never-propose: false\n' >>"$core/config/duties.yaml"
cat >"$adopter/catalogs/duties.yaml" <<'EOF'
duties:
  - id: "1"
    supersede: true
    summary: "An adopter override of 1"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: []
    files: one
    lifecycle: live
    never-propose: false
EOF
cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
duties:
  - id: "01"
    summary: "An invalid repo-tracked duty"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: []
    files: zero-one
    lifecycle: bogus
    never-propose: false
EOF
mc_run mc-duties.sh watchers --program alpha
expect_rc "an invalid repo-tracked 01 is not taken for the adopter's 1" 1
expect_err "the 01 refusal is reported" "refusing an invalid catalog"
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty, beta-duty]
EOF

# An adopter id carrying a tab is still named by its layer and skipped.
printf 'duties:\n  - id: "bad\tid"\n    summary: "x"\n    triggers: []\n    watchers: []\n    wake: none\n    rules: []\n    kinds: []\n    files: odd\n    lifecycle: live\n    never-propose: false\n' >"$adopter/catalogs/duties.yaml"
mc_run mc-duties.sh watchers --program alpha
expect_rc "an adopter id carrying a tab is skipped, not refused" 0
expect_err "the tab id's skip names the adopter layer" "from the adopter layer"
rm -f "$adopter/catalogs/duties.yaml"

# An id carrying the unit separator still names its layer intact.
printf 'duties:\n  - id: "bad%sid"\n    summary: "x"\n    triggers: []\n    watchers: []\n    wake: none\n    rules: []\n    kinds: []\n    files: odd\n    lifecycle: live\n    never-propose: false\n' \
  "$(printf '\037')" >"$adopter/catalogs/duties.yaml"
mc_run mc-duties.sh watchers --program alpha
expect_rc "an adopter id carrying the unit separator is skipped" 0
expect_err "its skip names the adopter layer whole" "from the adopter layer;"
rm -f "$adopter/catalogs/duties.yaml"

# An adopter entry whose id cannot be printed is still named by its layer.
printf 'duties:\n  - id: bad%sid\n    summary: "x"\n    triggers: []\n    watchers: []\n    wake: none\n    rules: []\n    kinds: []\n    files: odd\n    lifecycle: live\n    never-propose: false\n' \
  "$(printf '\001')" >"$adopter/catalogs/duties.yaml"
mc_run mc-duties.sh watchers --program alpha
expect_rc "an adopter id carrying a control character is skipped, not refused" 0
expect_err "the skip names the layer" "from the adopter layer"
rm -f "$adopter/catalogs/duties.yaml"

# ---------------------------------------------------------------------------
# REQ-C1.1: what the resolver passes through is still checked.
# ---------------------------------------------------------------------------
# A duplicate id in the core seed: the resolver keeps the first entry, and so
# does every read here; validate reports the duplicate.
reset_mc_fixture
cat >>"$core/config/duties.yaml" <<'EOF'
  - id: alpha-duty
    summary: "A second alpha"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: []
    files: alpha-two
    lifecycle: "off"
    never-propose: false
EOF
mc_run mc-duties.sh get alpha-duty summary
expect_eq "a duplicate id reads the first entry, as the resolver keeps it" "A shipped live duty"
mc_run mc-duties.sh validate
expect_rc "REQ-C1.1: a duplicate id fails validation" 1
expect_err "REQ-C1.1: the duplicate id is named" "alpha-duty: id"

reset_mc_fixture
awk '{ print } /^    lifecycle: live$/ { print "    lifecycle: \"off\"" }' "$core/config/duties.yaml" >"$tmp/d" && mv "$tmp/d" "$core/config/duties.yaml"
mc_run mc-duties.sh validate
expect_rc "REQ-C1.1: a field named twice in one entry fails validation" 1
expect_err "REQ-C1.1: the repeated field is named" "alpha-duty: lifecycle"

reset_mc_fixture
sed -e "s/A shipped live duty/A shipped $(printf '\033')[2J duty/" "$core/config/duties.yaml" >"$tmp/d" && mv "$tmp/d" "$core/config/duties.yaml"
mc_run mc-duties.sh validate
expect_rc "a value carrying a control character fails validation" 1
expect_err "the field carrying it is named" "alpha-duty: summary"
mc_run mc-duties.sh get alpha-duty summary
expect_rc "get refuses a value carrying a control character" 1

# A failing catalog reader is a failure, never a clean catalog: an awk shim
# that fails for the reader's own pass (the one carrying MODE).
reset_mc_fixture
real_awk=$(command -v awk)
mkdir -p "$tmp/shim"
# shellcheck disable=SC2016 # the shim's own expansions run when it does
printf '#!/bin/sh\nif [ -n "${MODE:-}" ]; then echo "awk: simulated failure" >&2; exit 2; fi\nexec "%s" "$@"\n' "$real_awk" >"$tmp/shim/awk"
chmod +x "$tmp/shim/awk"
saved_path=$PATH
PATH="$tmp/shim:$PATH"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: [alpha-duty]
EOF
mc_run mc-duties.sh validate
validate_rc=$RC validate_err=$ERR
mc_run mc-duties.sh watchers --program alpha
PATH=$saved_path
watchers_rc=$RC watchers_out=$OUT
RC=$validate_rc ERR=$validate_err
expect_rc "a failing catalog reader fails validate" 1
expect_err "the reader failure is named" "the catalog reader failed"
RC=$watchers_rc OUT=$watchers_out
expect_rc "a failing catalog reader fails watchers, arming nothing" 1
expect_eq "nothing is armed past a failed reader" ""

# A reader that validates but fails the arming or get pass.
# shellcheck disable=SC2016 # the shim's own expansions run when it does
printf '#!/bin/sh\ncase "${MODE:-}" in "" | validate | ids) exec "%s" "$@" ;; esac\necho "awk: simulated failure" >&2\nexit 2\n' "$real_awk" >"$tmp/shim/awk"
PATH="$tmp/shim:$PATH"
mc_run mc-duties.sh watchers --program alpha
watchers_rc=$RC watchers_err=$ERR
mc_run mc-duties.sh get alpha-duty summary
PATH=$saved_path
expect_rc "a failing get pass fails get" 1
expect_err "the get failure names the reader" "the catalog reader failed"
RC=$watchers_rc ERR=$watchers_err
expect_rc "a failing arming pass fails watchers" 1
expect_err "the arming failure names the reader" "the catalog reader failed"

mc_run mc-duties.sh watchers
expect_rc "watchers without --program is a usage error" 2
mc_run mc-duties.sh bogus
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-duties: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-duties: all passed"
