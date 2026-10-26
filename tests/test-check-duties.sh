#!/bin/bash
# Tests for scripts/check-duties.sh — the guard over the merged duties
# catalog, the shipped default duty set and source map, and every configured
# program's enabled list and state-source map (mission-control REQ-C1.1,
# REQ-C1.2, REQ-H1.4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-duties.sh
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

[ -f "$repo_root/scripts/check-duties.sh" ] || {
  echo "FAIL: scripts/check-duties.sh missing" >&2
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

# run_guard [args...]: the guard with the host's plugin and layer context
# cleared, so only what the guard itself selects is read.
run_guard() {
  OUT=$(env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_LOCAL_CONFIG \
    -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    HOME="$fixhome" /bin/bash "$repo_root/scripts/check-duties.sh" "$@" 2>&1)
  RC=$?
  ERR=$OUT
}
run_fixture() { run_guard --core "$core" --repo "$repo"; }
expect_fail() { # expect_fail <label>
  if [ "$RC" -ne 0 ]; then
    ok "$1 (exit $RC)"
  else
    fail "$1: expected a non-zero exit"
    printf '%s\n' "----- output -----" "$OUT" "------------------" >&2
  fi
}

# ---------------------------------------------------------------------------
# The real repository passes, and the guard runs in CI's lint job.
# ---------------------------------------------------------------------------
run_guard
expect_rc "the real repository's catalog and defaults pass" 0

if awk '/^\[/{c=0} /^\[tasks\."check:non-test"\]$/{c=1} c && /"check:duties"/{f=1} END{exit !f}' "$repo_root/mise.toml"; then
  ok "check:duties is a dependency of check:non-test"
else
  fail "check:duties is not wired into mise.toml's check:non-test task"
fi
if grep -q 'run: mise run check:non-test' "$repo_root/.github/workflows/ci.yml"; then
  ok "CI's lint job runs check:non-test"
else
  fail "the CI workflow no longer runs check:non-test"
fi

# ---------------------------------------------------------------------------
# REQ-C1.1: the entry grammar.
# ---------------------------------------------------------------------------
reset_mc_fixture
# The fixture's default duty set names fixture duties.
fixture_defaults() {
  sed -e 's/^mission_control_default_duties: .*/mission_control_default_duties: [alpha-duty]/' \
    "$repo_root/config/defaults.yml" | grep '^mission_control_' >"$core/config/defaults.yml"
}
fixture_defaults
run_fixture
expect_rc "REQ-C1.1: a catalog carrying the full grammar passes" 0

# overlay <yaml-entry-fields...>: a repo-tracked overlay adding one duty.
overlay() {
  {
    printf 'duties:\n'
    cat
  } >"$repo/.claude/catalogs/duties.yaml"
}
full_entry() { # full_entry <field-to-drop> <field-to-replace> <replacement-line>
  awk -v drop="$1" -v repl="$2" -v line="$3" '
    { split($0, kv, ":"); k = kv[1]; sub(/^ *(- )?/, "", k) }
    k == drop { next }
    k == repl { print line; next }
    { print }' <<'EOF'
  - id: gamma-duty
    summary: "A custom duty"
    triggers: [pr-opened]
    watchers: [scripts/gamma.sh@5m/low]
    wake: gamma-due
    rules: []
    kinds: []
    files: gamma
    lifecycle: live
    never-propose: false
EOF
}

full_entry "" "" "" | overlay
run_fixture
expect_rc "REQ-C1.1: an overlay entry carrying the full grammar passes" 0

for field in summary triggers watchers wake rules kinds files lifecycle never-propose; do
  full_entry "$field" "" "" | overlay
  run_fixture
  expect_fail "REQ-C1.1: an entry missing '$field' fails"
  expect_out "REQ-C1.1: the missing '$field' is named with its duty" "gamma-duty: $field"
done

bad_value() { # bad_value <field> <line> <label>
  full_entry "" "$1" "$2" | overlay
  run_fixture
  expect_fail "REQ-C1.1: $3 fails"
  expect_out "REQ-C1.1: $3 names the field" "gamma-duty: $1"
}
bad_value lifecycle "    lifecycle: sometimes" "an unknown lifecycle"
bad_value never-propose "    never-propose: maybe" "a non-boolean never-propose"
bad_value watchers "    watchers: [scripts/gamma.sh@soon/low]" "a watcher with a bad cadence"
bad_value watchers "    watchers: [scripts/gamma.sh@5m/huge]" "a watcher with an unknown cost class"
bad_value watchers "    watchers: [scripts/gamma.sh]" "a watcher without cadence and cost"
bad_value watchers "    watchers: [../escape.sh@5m/low]" "a watcher path with a parent segment"
bad_value watchers "    watchers: [-x.sh@5m/low]" "a watcher path that reads as an option"
bad_value watchers "    watchers: [/tmp/evil.sh@5m/low]" "an absolute watcher path"
bad_value watchers "    watchers: scripts/gamma.sh@5m/low" "a watcher list that is not a list"
bad_value triggers "    triggers: [Not Kebab]" "a trigger that is not kebab"
bad_value kinds "    kinds: [a,,b]" "a kinds list with an empty member"
bad_value wake "    wake: Wake Up" "a wake that is not kebab"
bad_value files "    files: ../kb" "a files directory with a traversal"
bad_value files "    files: alpha" "a files directory another duty owns"
bad_value summary '    summary: ""' "an empty summary"

full_entry "" "" "" | awk '{ print } /^    never-propose:/ { print "    colour: blue" }' | overlay
run_fixture
expect_fail "REQ-C1.1: an unknown field fails"
expect_out "REQ-C1.1: the unknown field is named" "gamma-duty: colour"

# A resolver warning (a duplicate id without a supersede marker) fails.
full_entry "" "" "" | sed 's/gamma-duty/alpha-duty/' | overlay
run_fixture
expect_fail "a duplicate id without a supersede marker fails"
expect_out "the resolver's warning is surfaced" "alpha-duty"

# The core seed alone: the resolver passes a core-only catalog through
# unmerged, so its warnings come only from the merge the check also runs.
reset_mc_fixture
fixture_defaults
awk '{ print } /^    lifecycle: live$/ { print "      stray: indented" }' "$core/config/duties.yaml" >"$tmp/d" && mv "$tmp/d" "$core/config/duties.yaml"
run_fixture
expect_fail "a stray indented line in the core seed fails"
expect_out "the stray line's warning is surfaced" "indented line"

reset_mc_fixture
fixture_defaults
cat >>"$core/config/duties.yaml" <<'EOF'
  - id: beta-duty
    summary: "A second beta"
    triggers: []
    watchers: []
    wake: none
    rules: []
    kinds: []
    files: beta-two
    lifecycle: "off"
    never-propose: false
EOF
run_fixture
expect_fail "a duplicate id in the core seed fails"
expect_out "the duplicate core id is named" "beta-duty"

# The guard reads no host HOME: the shipped ~/ home root is checked for its
# shape, wherever it runs.
reset_mc_fixture
fixture_defaults
OUT=$(env -u HOME -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY \
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_CONFIG_DEFAULTS \
  /bin/bash "$repo_root/scripts/check-duties.sh" --core "$core" --repo "$repo" 2>&1)
RC=$?
expect_rc "the guard passes with no HOME set" 0

# ---------------------------------------------------------------------------
# REQ-C1.2: the default duty set and every program's enabled list name duties
# the catalog holds.
# ---------------------------------------------------------------------------
reset_mc_fixture
sed -e 's/^mission_control_default_duties: .*/mission_control_default_duties: [alpha-duty, ghost-duty]/' \
  "$repo_root/config/defaults.yml" | grep '^mission_control_' >"$core/config/defaults.yml"
run_fixture
expect_fail "REQ-C1.2: a default duty set naming an unknown duty fails"
expect_out "REQ-C1.2: the unknown default duty is named" "ghost-duty"

reset_mc_fixture
fixture_defaults
mkdir -p "$repo/specs"
program() { # program <extra-lines>
  printf 'mission_control_programs: [alpha]\nprogram_alpha_repositories: [%s]\nprogram_alpha_spec_root: %s/specs\n%s\n' \
    "$repo" "$repo" "$1" >"$tracked"
}
program ""
run_fixture
expect_rc "REQ-C1.2: a complete program passes" 0
program "program_alpha_duties: [alpha-duty, phantom-duty]"
run_fixture
expect_fail "REQ-C1.2: a program enabling an unknown duty fails"
expect_out "REQ-C1.2: the unknown enabled duty is named" "phantom-duty"

# ---------------------------------------------------------------------------
# REQ-H1.4: the state-source map's modes.
# ---------------------------------------------------------------------------
program "program_alpha_sources: {work-items: jira:cited, code-state: forge:snapshot}"
run_fixture
expect_rc "REQ-H1.4: a map with known modes passes" 0
program "program_alpha_sources: {code-state: forge:mirrored}"
run_fixture
expect_fail "REQ-H1.4: a map naming an unknown mode fails check:duties"
expect_out "REQ-H1.4: the unknown mode is named" "mirrored"

reset_mc_fixture
sed -e 's/^mission_control_default_sources: .*/mission_control_default_sources: {work-items: specs:recorded}/' \
  -e 's/^mission_control_default_duties: .*/mission_control_default_duties: [alpha-duty]/' \
  "$repo_root/config/defaults.yml" | grep '^mission_control_' >"$core/config/defaults.yml"
run_fixture
expect_fail "REQ-H1.4: a default map naming an unknown mode fails"
expect_out "REQ-H1.4: the default map's unknown mode is named" "recorded"

# A reader that fails without a word still fails the guard: a stub
# mc-program.sh whose program duty read exits 1 silently.
reset_mc_fixture
fixture_defaults
program ""
mkdir -p "$tmp/stubbed"
cp -R "$repo_root/scripts" "$tmp/stubbed/scripts"
cat >"$tmp/stubbed/scripts/mc-program.sh" <<EOF
#!/bin/bash
[ "\$1 \${3:-}" = "get duties" ] && exit 1
exec /bin/bash "$repo_root/scripts/mc-program.sh" "\$@"
EOF
OUT=$(env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_ROOT \
  -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_LOCAL_CONFIG \
  -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
  HOME="$fixhome" /bin/bash "$tmp/stubbed/scripts/check-duties.sh" --core "$core" --repo "$repo" 2>&1)
RC=$?
expect_fail "a program duty read failing silently fails check:duties"
expect_out "the silent failure is named" "program 'alpha' duties: the read failed with no message"

# ---------------------------------------------------------------------------
# Usage.
# ---------------------------------------------------------------------------
run_guard --bogus
expect_rc "an unknown flag is a usage error" 2
run_guard --core "$tmp/nope" --repo "$repo"
expect_rc "a core root without config/defaults.yml is a usage error" 2
mkdir -p "$repo/sub"
run_guard --core "$core" --repo "$repo/sub"
expect_rc "a repository path that is not a git toplevel is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-check-duties: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-duties: all passed"
