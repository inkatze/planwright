#!/bin/bash
# Tests for scripts/base-state-checks.sh: the list of check names a ready flip
# does not count because they describe the base branch, not the pull request.
#
# Runs standalone under /bin/bash:
#   ./tests/test-base-state-checks.sh
set -euf
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
BSC="$here/../scripts/base-state-checks.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -r "$BSC" ] || fail "scripts/base-state-checks.sh is missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/adopter" "$tmp/repo/.claude"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$tmp/repo"

run() {
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_REPO_ROOT="$tmp/repo" \
    PLANWRIGHT_LOCAL_CONFIG="" /bin/sh "$BSC"
}
expect() { # expect <label> <json>
  got=$(run) || fail "$1: exited non-zero"
  [ "$got" = "$2" ] || fail "$1: got '$got', expected '$2'"
  ok "$1"
}

expect "the shipped default is window-lock alone" '["release-window/window-lock"]'

printf 'ready_base_state_checks: release-window/window-lock ci/release-note\n' >"$tmp/adopter/planwright.yml"
expect "an adopter list is honored" '["release-window/window-lock","ci/release-note"]'

printf 'ready_base_state_checks:\n' >"$tmp/adopter/planwright.yml"
expect "an empty adopter list excludes nothing" '[]'

printf 'ready_base_state_checks: bad;name\n' >"$tmp/adopter/planwright.yml"
expect "a malformed list excludes nothing" '[]'

rm -f "$tmp/adopter/planwright.yml"
printf 'ready_base_state_checks: sneaky\n' >"$tmp/repo/.claude/planwright.yml"
printf 'ready_base_state_checks: sneaky\n' >"$tmp/repo/.claude/planwright.local.yml"
expect "a repo-side value is ignored, since a session can edit it" '["release-window/window-lock"]'

mkdir -p "$tmp/inst/scripts" && cp "$BSC" "$here/../scripts/resolve-policy-knob.sh" "$here/../scripts/resolve-config-knob.sh" "$here/../scripts/echo-safety.sh" "$tmp/inst/scripts/"
got=$(PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG="" /bin/sh "$tmp/inst/scripts/base-state-checks.sh") || fail "an unreadable core: exited non-zero"
[ "$got" = '[]' ] || fail "an unreadable core: got '$got', expected []"
ok "a list that cannot be read excludes nothing"
printf 'ready_base_state_checks: widened\n' >"$tmp/envcore.yml"
got=$(PLANWRIGHT_CONFIG_DEFAULTS="$tmp/envcore.yml" run) || fail "env override: exited non-zero"
[ "$got" = '["release-window/window-lock"]' ] || fail "an inherited PLANWRIGHT_CONFIG_DEFAULTS widened the list: $got"
ok "an environment core override does not widen the list"
echo "all base-state-checks tests passed"
