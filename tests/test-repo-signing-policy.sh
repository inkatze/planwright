#!/bin/bash
# Test for planwright's OWN release-signing policy of record (autopilot-reflex
# Task 9, REQ-D1.4, D-4). REQ-D1.4's last clause: "planwright's own repo SHALL
# set `require`." That value lives in the repo-tracked config overlay
# (`<repo>/.claude/planwright.yml`), the team-shared committed layer. This is a
# regression test on the config-of-record — distinct from test-config-get.sh,
# which verifies the reader's generic four-layer resolution with hermetic
# fixtures; here the fixture IS the repo's committed overlay file.
#
# Two assertions:
#   1. The committed overlay exists and sets `require_signed_tags: require`
#      (grounded content check on the config-of-record).
#   2. That committed content resolves to `require` through the real
#      config-get reader, attributed to the repo-tracked layer — proven
#      hermetically (the overlay copied into a throwaway repo root, adopter and
#      machine-local layers absent) so the result does not depend on the
#      runner's own overlay state.
#
# Runs standalone under /bin/bash (the bash 3.2 floor): ./tests/test-repo-signing-policy.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
CG="$repo_root/scripts/config-get.sh"
overlay="$repo_root/.claude/planwright.yml"
defaults="$repo_root/config/defaults.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CG" ] || fail "scripts/config-get.sh missing or not executable"
[ -f "$defaults" ] || fail "config/defaults.yml missing"

# 1. The committed repo-tracked overlay exists and sets require.
[ -f "$overlay" ] \
  || fail "repo config overlay .claude/planwright.yml is missing (REQ-D1.4: planwright's repo SHALL set require)"
grep -Eq '^[[:space:]]*require_signed_tags:[[:space:]]*require[[:space:]]*$' "$overlay" \
  || fail ".claude/planwright.yml does not set 'require_signed_tags: require'"
echo "ok: .claude/planwright.yml sets require_signed_tags: require"

# 2. The committed content resolves to `require` via the real reader,
#    attributed to the repo-tracked layer. Hermetic: the overlay is copied into
#    a throwaway repo root with no adopter and no machine-local layer, so the
#    result reflects the committed file alone, not the runner's environment.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/.claude" "$tmp/adopter"
cp "$overlay" "$tmp/repo/.claude/planwright.yml"

run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp/repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$CG" "$@"
}

got=$(run require_signed_tags)
[ "$got" = require ] \
  || fail "config-get resolved require_signed_tags to '$got', expected 'require'"
echo "ok: config-get resolves require_signed_tags to require from the committed overlay"

# provenance: the resolved value is attributed to the repo-tracked layer
# (--explain prints '<layer>TAB<value>'), confirming the value comes from the
# team-shared overlay and not a leaked default.
explain=$(run --explain require_signed_tags)
[ "$explain" = "$(printf 'repo-tracked\trequire')" ] \
  || fail "--explain attributed require_signed_tags to '$explain', expected 'repo-tracked<TAB>require'"
echo "ok: require_signed_tags is attributed to the repo-tracked overlay layer"

echo "PASS: test-repo-signing-policy.sh"
