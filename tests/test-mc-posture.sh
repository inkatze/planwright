#!/bin/bash
# Tests for scripts/mc-posture.sh, mission control's posture check
# (mission-control REQ-G1.5, D-32): the shipped deny floor in force and the
# guard hooks wired, read from fixture settings layers, each failure one
# line naming its reason. The launcher's refusal on the same result is in
# tests/test-mission-control-launch.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
POSTURE="$repo_root/scripts/mc-posture.sh"
PROFILE="$repo_root/config/mission-control-settings.json"

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-posture.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

proj="$tmp/proj"
home="$tmp/home"
absent="$tmp/absent.json"

# posture [env assignments...] -- [args...]: run the check in the fixture
# project with HOME at the fixture home and no inherited session plumbing.
posture() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  [ "$#" -eq 0 ] || shift
  OUT=$(cd "$proj" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_MC_TOKEN -u PLANWRIGHT_ROOT \
    HOME="$home" ${envs[@]+"${envs[@]}"} /bin/bash "$POSTURE" check --managed "$absent" "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

reset() {
  rm -rf "$proj" "$home"
  mkdir -p "$proj/.claude" "$home/.claude"
}

# absolute_profile: the shipped profile with its hook root made absolute,
# the shape an operator merging it into their own settings writes.
absolute_profile() {
  sed "s|\\\\\"\$CLAUDE_PLUGIN_ROOT\\\\\"|$repo_root|g" "$PROFILE"
}

expect_pass() { # <label>
  if [ "$RC" = 0 ] && [ "$OUT" = "posture${TAB}pass" ]; then
    ok "$1"
  else
    fail "$1: expected a pass, got exit $RC: $OUT $ERR"
  fi
}
expect_fail() { # <label> <needle>
  local lines
  lines=$(printf '%s\n' "$OUT" | grep -c .)
  if [ "$RC" != 1 ]; then
    fail "$1: expected exit 1, got $RC: $OUT $ERR"
  elif [ "$lines" != 1 ]; then
    fail "$1: expected one line, got $lines: $OUT"
  else
    case $OUT in
      "posture${TAB}fail${TAB}"*"$2"*) ok "$1" ;;
      *) fail "$1: the reason lacks '$2': $OUT" ;;
    esac
  fi
}
TAB=$(printf '\t')

echo "# a passing set"
reset
absolute_profile >"$home/.claude/settings.json"
posture --
expect_pass "the profile merged into the user layer, hooks by absolute path, passes"

reset
posture CLAUDE_PLUGIN_ROOT="$repo_root" -- --settings "$PROFILE"
expect_pass "the shipped profile as a --settings layer under its plugin root passes"

reset
jq '{permissions: {deny: .permissions.deny[0:40]}}' "$PROFILE" >"$home/.claude/settings.json"
absolute_profile | jq '.permissions.deny |= .[40:]' >"$proj/.claude/settings.local.json"
posture --
expect_pass "the floor split across the user and local layers passes on their union"

reset
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_MC_TOKEN=fixture-token --
expect_pass "a launched mission-control session reads the profile it was launched with"

echo "# the deny floor"
reset
absolute_profile | jq '.permissions.deny |= map(select(. != "Bash(gh pr merge:*)"))' >"$home/.claude/settings.json"
posture --
expect_fail "a set without one shipped deny entry fails" "the shipped deny floor is not in force: 1 of its entries"
expect_fail "the reason names the missing entry" "Bash(gh pr merge:*)"

reset
absolute_profile | jq 'del(.permissions.deny)' >"$home/.claude/settings.json"
posture --
expect_fail "a set with no deny list fails" "the shipped deny floor is not in force"

reset
posture --
expect_fail "no settings at all fails" "the shipped deny floor is not in force"

echo "# the guard hooks"
reset
absolute_profile | jq 'del(.hooks)' >"$home/.claude/settings.json"
posture --
expect_fail "a set whose guard hooks are not wired fails" "is not wired for"

reset
absolute_profile | jq '.hooks.PreToolUse |= map(select(.matcher != "Edit|Write|MultiEdit|NotebookEdit"))' >"$home/.claude/settings.json"
posture --
expect_fail "the file-tool guard missing fails, naming its matcher" "policy-guard.sh mission-control file is not wired for Edit|Write|MultiEdit|NotebookEdit"

reset
absolute_profile | jq '(.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks) |= map(select(.command | test("tower-command-guard") | not))' >"$home/.claude/settings.json"
posture --
expect_fail "the command guard missing fails" "tower-command-guard.sh mission-control is not wired for Bash"

reset
absolute_profile | jq '(.hooks.PreToolUse[] | select(.matcher == "Bash") | .matcher) |= "Read"' >"$home/.claude/settings.json"
posture --
expect_fail "a guard wired under another matcher fails" "is not wired for Bash"

reset
posture -- --settings "$PROFILE"
expect_fail "hooks wired through an unset CLAUDE_PLUGIN_ROOT fail" "does not resolve"

reset
posture CLAUDE_PLUGIN_ROOT="$tmp/nowhere" -- --settings "$PROFILE"
expect_fail "hooks wired through a root without the guards fail" "does not resolve"

echo "# unreadable layers"
reset
absolute_profile >"$home/.claude/settings.json"
printf '{ not json\n' >"$proj/.claude/settings.local.json"
posture --
expect_fail "a layer that does not parse fails, naming it" "settings.local.json cannot be parsed"

reset
absolute_profile >"$home/.claude/settings.json"
printf '{"permissions":{"deny":"Bash(x)"}}\n' >"$proj/.claude/settings.json"
posture --
expect_fail "a layer whose deny is not a list fails" "settings.json cannot be parsed"

reset
absolute_profile >"$home/.claude/settings.json"
posture -- --settings "$tmp/missing.json"
expect_pass "an absent layer counts as empty"

echo "# usage"
OUT=$(/bin/bash "$POSTURE" 2>&1)
[ "$?" = 2 ] && ok "no verb is a usage error" || fail "no verb did not exit 2"
OUT=$(/bin/bash "$POSTURE" check --bogus 2>&1)
[ "$?" = 2 ] && ok "an unknown flag is a usage error" || fail "an unknown flag did not exit 2"

if [ "$failures" -eq 0 ]; then
  echo "PASS: test-mc-posture.sh"
else
  echo "FAIL: test-mc-posture.sh ($failures)" >&2
  exit 1
fi
