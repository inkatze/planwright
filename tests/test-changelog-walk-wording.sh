#!/bin/bash
# A changelog line written during a walk sits inside the content the sign-off
# anchors, so it must name the walk and point at the sign-off record, never a
# state that sign-off changes. The rule is prose; this fences that the format
# doctrine and the kickoff skill both carry it.
#
# Runs standalone: ./tests/test-changelog-walk-wording.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

check() {
  # check <label> <file> <fixed string>
  if grep -qF -- "$3" "$2"; then
    echo "ok: $1"
  else
    echo "FAIL: $1 ($2 lacks: $3)" >&2
    failures=$((failures + 1))
  fi
}

check "format doctrine bans sign-off-state wording" \
  "$REPO_ROOT/doctrine/spec-format.md" "never a state that sign-off changes"
check "kickoff skill points walk entries at the sign-off record" \
  "$REPO_ROOT/skills/spec-kickoff/SKILL.md" "never a state that sign-off changes"

[ "$failures" -eq 0 ] || exit 1
