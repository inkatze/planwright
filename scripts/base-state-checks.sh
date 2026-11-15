#!/bin/sh
# base-state-checks.sh — print, as a JSON array of check names, the checks a
# ready flip does not count because they describe the base branch's state, not
# the pull request (the release-window lock is red on every pull request while
# main sits in an untagged release window). Read from the ready_base_state_checks
# knob, in the core and adopter layers only: a repo-side layer sits in a
# checkout the flipping session can edit, so it could not widen what the flip
# ignores. Any failure, a malformed value included, prints [] and exits 0, so
# no failure can relax a flip.
#
# Usage: base-state-checks.sh
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  echo '[]'
  exit 0
}
# The core layer is always this install's own defaults: an inherited
# PLANWRIGHT_CONFIG_DEFAULTS is overridden, since a session could point it at a
# file of its own and widen what the flip ignores.
names=$(PLANWRIGHT_CONFIG_DEFAULTS="$script_dir/../config/defaults.yml" \
  PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG='' \
  /bin/sh "$script_dir/resolve-policy-knob.sh" ready_base_state_checks 2>/dev/null) || names=''
printf '%s\n' "$names" | jq -Rc 'split(" ") | map(select(. != ""))' 2>/dev/null || echo '[]'
