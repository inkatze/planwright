#!/bin/bash
# The tower profile's _about text (tower-placement REQ-D1.5): it says the
# guards receive the Bash command as written, unexpanded; it makes no claim
# that commands arrive expanded; and it no longer says tower scoping is
# enforced only by hook wiring or that the tower commits via git as its reason
# not to need the GitHub MCP write tools. It names the branch-moving and
# stash-writing denies the placement floor adds.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
unset CDPATH
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${TOWER_ABOUT_PROFILE:-$REPO_ROOT/config/tower-settings.json}"

passes=0
failures=0
pass() {
  printf '%s\n' "ok: $1"
  passes=$((passes + 1))
}
fail() {
  printf '%s\n' "FAIL: $1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' "FAIL: jq is required to run this suite" >&2
  exit 1
}

about=$(jq -r '._about // empty' "$PROFILE") || about=''
[ -n "$about" ] || {
  printf '%s\n' "FAIL: $PROFILE has no _about text" >&2
  exit 1
}
has() { printf '%s' "$about" | grep -qiF -- "$1"; }

if has 'receive the Bash command as written, unexpanded'; then
  pass "_about says the guards receive the command as written, unexpanded (REQ-D1.5)"
else
  fail "_about does not say the guards receive the command as written, unexpanded (REQ-D1.5)"
fi
for claim in 'already expanded' 'arrives expanded' 'arrive expanded' 'expanded command' 'command expanded' \
  'tower-scoping is enforced only by where' 'enforced only by where the hook is wired' \
  'commits via git'; do
  if has "$claim"; then
    fail "_about still says '$claim' (REQ-D1.5)"
  else
    pass "_about does not say '$claim' (REQ-D1.5)"
  fi
done
for phrase in 'marked as a tower' 'BRANCH-MOVING AND STASH-WRITING' 'stash list' 'gh repo sync'; do
  if has "$phrase"; then
    pass "_about names '$phrase'"
  else
    fail "_about does not name '$phrase'"
  fi
done

echo
printf '%s\n' "passes: $passes  failures: $failures"
[ "$failures" = 0 ]
