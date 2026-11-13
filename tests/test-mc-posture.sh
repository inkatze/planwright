#!/bin/bash
# Tests for scripts/mc-posture.sh, mission control's posture check
# (mission-control REQ-G1.5, D-32): the shipped deny floor in force and the
# guard hooks wired, read from fixture settings layers, each failure one
# line naming its reason. The launcher's refusal on the same result is in
# tests/test-mission-control-launch-tmux.sh.
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
  OUT=$(cd "$proj" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_MC_TOKEN -u PLANWRIGHT_ROOT -u CLAUDE_PROJECT_DIR \
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
jq '{permissions: {deny: (.permissions.deny | .[0:(length / 2 | floor)])}}' "$PROFILE" >"$home/.claude/settings.json"
absolute_profile | jq '.permissions.deny |= .[(length / 2 | floor):]' >"$proj/.claude/settings.local.json"
posture --
expect_pass "the floor split across the user and local layers passes on their union"

# A launched session's token binds it to the launcher's registry row, which
# records the profile it was launched with.
reset
mkdir -p "$tmp/fleet/mission-control/sessions"
printf 'token\t%s\nkind\tmission-control\nprofile\t%s\n' fixture-token-0123456789 "$PROFILE" \
  >"$tmp/fleet/mission-control/sessions/mc-alpha-mission-control-0123456789"
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=fixture-token-0123456789 --
expect_pass "a launched mission-control session reads the profile its registry row records"
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=forged-token-0123456789 --
expect_fail "a token no registry row carries fails" "no launcher registry row carries"
printf 'token\t%s\nkind\tworker\nprofile\t%s\n' worker-token-0123456789 "$PROFILE" \
  >"$tmp/fleet/mission-control/sessions/mc-alpha-worker-0123456789"
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=worker-token-0123456789 --
expect_fail "another kind's row does not vouch for a mission-control session" "no launcher registry row carries"
printf 'token\t%s\nkind\tmission-control\nprofile\t%s\n' linked-token-0123456789 "$PROFILE" >"$tmp/linked-row"
ln -s "$tmp/linked-row" "$tmp/fleet/mission-control/sessions/mc-alpha-mission-control-linked"
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=linked-token-0123456789 --
expect_fail "a registry row that is a symbolic link vouches for nothing" "no launcher registry row carries"
rm -f "$tmp/fleet/mission-control/sessions/mc-alpha-mission-control-linked" "$tmp/linked-row"
printf 'token\t%s\nkind\tmission-control\nprofile\t%s\n' relative-token-0123456789 config/mission-control-settings.json \
  >"$tmp/fleet/mission-control/sessions/mc-alpha-mission-control-relative"
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=relative-token-0123456789 --
expect_fail "a registry row recording a relative profile path fails" "records no absolute profile path"
printf 'token\t%s\nkind\tmission-control\nprofile\t%s\n' gone-token-0123456789 "$tmp/gone-profile.json" \
  >"$tmp/fleet/mission-control/sessions/mc-alpha-mission-control-gone"
posture CLAUDE_PLUGIN_ROOT="$repo_root" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=gone-token-0123456789 --
expect_fail "a registry row recording a profile that is gone fails" "gone-profile.json, does not exist"
rm -rf "$tmp/fleet"
posture PLANWRIGHT_MC_TOKEN=fixture-token-0123456789 PLANWRIGHT_FLEET_STATE_DIR= CLAUDE_PLUGIN_DATA= CLAUDE_DIR= --
expect_fail "a token with no resolvable fleet home fails" "the fleet home holding the launcher's registry cannot be resolved"

reset
mkdir -p "$tmp/scripts"
ln -s "$repo_root" "$tmp/scripts/pw"
jq --arg r "$tmp/scripts/pw" '(.. | objects | select(has("command")) | .command) |= gsub("\"\\$CLAUDE_PLUGIN_ROOT\""; $r)' \
  "$PROFILE" >"$home/.claude/settings.json"
posture --
expect_pass "a planwright root under a path holding a scripts directory passes"
rm -rf "$tmp/scripts"

reset
absolute_profile >"$tmp/managed.json"
posture -- --managed "$tmp/managed.json"
expect_pass "the profile in the managed settings file passes"

reset
mkdir -p "$tmp/config-dir"
absolute_profile >"$tmp/config-dir/settings.json"
posture CLAUDE_CONFIG_DIR="$tmp/config-dir" --
expect_pass "the user layer is read from CLAUDE_CONFIG_DIR when it is set"
rm -rf "$tmp/config-dir"

reset
absolute_profile >"$proj/.claude/settings.json"
(cd "$proj" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
  -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT git init -q . 2>/dev/null)
[ -d "$proj/.git" ] || fail "the fixture project is not a git top level"
mkdir -p "$proj/sub"
in_sub() {
  OUT=$(cd "$proj/sub" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_MC_TOKEN -u PLANWRIGHT_ROOT -u CLAUDE_PROJECT_DIR \
    HOME="$home" "$@" /bin/bash "$POSTURE" check --managed "$absent" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}
in_sub
expect_fail "with no --project, the git top level's project layers are not the session's" "the shipped deny floor is not in force"
mkdir -p "$proj/sub/.claude"
absolute_profile >"$proj/sub/.claude/settings.json"
in_sub
expect_pass "with no --project, the project layers are read from the session's own directory"
rm -rf "$proj/sub/.claude" "$proj/.claude/settings.json"
mkdir -p "$tmp/named/.claude"
absolute_profile >"$tmp/named/.claude/settings.json"
in_sub CLAUDE_PROJECT_DIR="$tmp/named"
expect_pass "the project directory Claude Code names is the session's project"
rm -rf "$tmp/named"

# A floor held only in a parent directory's project layer is not loaded by a
# session rooted in a child: the same start directory gets the same verdict
# whichever way it is named, and the refusal names where the floor must live.
reset
mkdir -p "$tmp/parent/.claude" "$tmp/parent/child/.claude"
absolute_profile >"$tmp/parent/.claude/settings.local.json"
posture -- --project "$tmp/parent/child"
expect_fail "a floor only in a parent directory's layer is not in force for the child" "the shipped deny floor is not in force"
child_explicit=$OUT
OUT=$(cd "$tmp/parent/child" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_MC_TOKEN -u PLANWRIGHT_ROOT -u CLAUDE_PROJECT_DIR \
  HOME="$home" /bin/bash "$POSTURE" check --managed "$absent" 2>"$tmp/err")
RC=$?
[ "$OUT" = "$child_explicit" ] && ok "the child's default start directory gives the same verdict as --project" \
  || fail "the child's default start directory differs from --project: $OUT"
expect_fail "the refusal names the user settings layer as a fix" "the user settings layer"
expect_fail "the refusal names each repository's project layer as a fix" "each repository's .claude/settings.json"
expect_fail "the refusal names the parent layer that is not loaded" "$tmp/parent/.claude/settings.local.json"
OUT=$(cd "$tmp/parent/child" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_MC_TOKEN -u PLANWRIGHT_ROOT -u CLAUDE_PROJECT_DIR \
  HOME="$home" /bin/bash "$POSTURE" check --managed "$absent" --project . 2>"$tmp/err")
RC=$?
expect_fail "a relative --project resolves to its directory and names the parent layer" "$tmp/parent/.claude/settings.local.json"
posture -- --project "$tmp/parent"
expect_pass "the parent directory itself, as the start directory, passes"
reset
absolute_profile >"$home/.claude/settings.json"
printf '%s\n' '{"allowManagedPermissionRulesOnly": true}' >"$tmp/managed-rules.json"
mkdir -p "$home/work/repo"
posture -- --managed "$tmp/managed-rules.json" --project "$home/work/repo"
expect_fail "managed-only permission rules refuse" "the shipped deny floor is not in force"
expect_fail "managed-only permission rules refuse naming the managed settings file as the fix" "the managed settings file"
case $OUT in
  *"the user settings layer"*) fail "the advice names the user layer, which the managed rules-only switch ignores: $OUT" ;;
  *"a parent directory's layer"*) fail "the user layer is named a parent layer that is not loaded: $OUT" ;;
  *) ok "the user layer is never named a parent layer that is not loaded" ;;
esac
rm -f "$tmp/managed-rules.json"
reset
posture -- --project "$proj"
expect_fail "a floor held nowhere still refuses" "the shipped deny floor is not in force"
rm -rf "$tmp/parent"

# A launched session's project is the directory its registry row records.
reset
absolute_profile >"$home/.claude/settings.json"
mkdir -p "$tmp/launched/.claude" "$tmp/fleet/mission-control/sessions"
printf '%s\n' '{"disableAllHooks": true}' >"$tmp/launched/.claude/settings.local.json"
printf 'token\t%s\nkind\tmission-control\nprofile\t%s\ncwd\t%s\n' cwd-token-0123456789 "$PROFILE" "$tmp/launched" \
  >"$tmp/fleet/mission-control/sessions/mc-alpha-mission-control-cwd"
posture PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=cwd-token-0123456789 --
expect_fail "a launched session reads the project layers of the directory it was launched in" "disableAllHooks"
mkdir -p "$tmp/clean"
posture PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=cwd-token-0123456789 CLAUDE_PROJECT_DIR="$tmp/clean" --
expect_fail "the directory a launched session was launched in wins over the one Claude Code names" "disableAllHooks"
posture PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_MC_TOKEN=cwd-token-0123456789 -- --project "$tmp/clean"
expect_pass "a --project wins over the directory a launched session was launched in"
rm -rf "$tmp/launched" "$tmp/fleet" "$tmp/clean"

# A --project that names no directory would read every project layer as
# absent, a disableAllHooks there included, so it fails rather than passes.
reset
absolute_profile >"$home/.claude/settings.json"
posture -- --project "$tmp/no-such-project"
expect_fail "a --project naming no directory fails" "the project root $tmp/no-such-project is not a directory"

echo "# the shipped profile"
# A copy of the check under a root whose own shipped profile is broken.
floor_root="$tmp/floor-root"
mkdir -p "$floor_root/scripts" "$floor_root/config"
cp "$POSTURE" "$floor_root/scripts/mc-posture.sh"
under_floor_root() {
  local real=$POSTURE
  POSTURE="$floor_root/scripts/mc-posture.sh"
  posture "$@"
  POSTURE=$real
}
reset
under_floor_root --
expect_fail "a root with no shipped profile fails" "config/mission-control-settings.json cannot be read"
printf '{ not json\n' >"$floor_root/config/mission-control-settings.json"
under_floor_root --
expect_fail "a shipped profile that does not parse fails" "config/mission-control-settings.json cannot be parsed"
printf '{"permissions": {"deny": []}}\n' >"$floor_root/config/mission-control-settings.json"
under_floor_root --
expect_fail "a shipped profile with no deny entry fails" "deny floor in config/mission-control-settings.json is empty"
printf '{"permissions": {"deny": ["Bash(x)"]}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "true"}]}]}}\n' \
  >"$floor_root/config/mission-control-settings.json"
printf '{"permissions": {"deny": ["Bash(x)"]}}\n' >"$home/.claude/settings.json"
under_floor_root --
expect_fail "a shipped hook naming no planwright script fails" "names no planwright script"
rm -rf "$floor_root"

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

reset
mkdir -p "$tmp/noexec/scripts"
cp "$repo_root/scripts/tower-command-guard.sh" "$repo_root/scripts/policy-guard.sh" "$tmp/noexec/scripts/"
chmod 644 "$tmp/noexec/scripts/"*.sh
posture CLAUDE_PLUGIN_ROOT="$tmp/noexec" -- --settings "$PROFILE"
expect_fail "hooks wired to guards that are not executable fail" "does not resolve"
rm -rf "$tmp/noexec"

reset
absolute_profile | jq '(.. | objects | select(has("command")) | .command) |= (if test("tower-command-guard") then . + " >/dev/null" else . end)' >"$home/.claude/settings.json"
posture --
expect_fail "a guard hook whose verdict is discarded is not wired" "tower-command-guard.sh mission-control is not wired for Bash"

reset
absolute_profile | jq '(.. | objects | select(has("command")) | .command) |= sub(" \\|\\| \\{.*$"; "")' >"$home/.claude/settings.json"
posture --
expect_fail "a policy hook without its fail-closed suffix is not wired" "policy-guard.sh mission-control bash is not wired for Bash"

reset
mkdir -p "$tmp/lookalike/scripts"
cp "$repo_root/scripts/tower-command-guard.sh" "$repo_root/scripts/policy-guard.sh" "$tmp/lookalike/scripts/"
posture CLAUDE_PLUGIN_ROOT="$tmp/lookalike" -- --settings "$PROFILE"
expect_fail "executable guards outside a planwright root do not resolve" "does not resolve to a planwright guard"
rm -rf "$tmp/lookalike"

reset
absolute_profile | jq '.disableAllHooks = true' >"$home/.claude/settings.json"
posture --
expect_fail "a layer turning every hook off fails" "disableAllHooks"

reset
absolute_profile >"$home/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}\n' >"$tmp/managed.json"
posture -- --managed "$tmp/managed.json"
expect_fail "under allowManagedHooksOnly, guards wired outside the managed layer do not count" "is not wired for"
absolute_profile | jq '.allowManagedHooksOnly = true' >"$tmp/managed.json"
posture -- --managed "$tmp/managed.json"
expect_pass "under allowManagedHooksOnly, guards wired in the managed layer count"
reset
absolute_profile | jq '.allowManagedHooksOnly = true' >"$home/.claude/settings.json"
posture --
expect_pass "allowManagedHooksOnly outside the managed layer changes nothing"

reset
absolute_profile >"$home/.claude/settings.json"
printf '{"allowManagedPermissionRulesOnly": true}\n' >"$tmp/managed.json"
posture -- --managed "$tmp/managed.json"
expect_fail "under allowManagedPermissionRulesOnly, deny entries outside the managed layer do not count" "the shipped deny floor is not in force"
absolute_profile | jq '{allowManagedPermissionRulesOnly: true, permissions: {deny: .permissions.deny}}' >"$tmp/managed.json"
posture -- --managed "$tmp/managed.json"
expect_pass "under allowManagedPermissionRulesOnly, the managed layer's deny entries count"
absolute_profile | jq '.allowManagedPermissionRulesOnly = true' >"$home/.claude/settings.json"
posture --
expect_pass "allowManagedPermissionRulesOnly outside the managed layer changes nothing"

echo "# forged projections"
reset
absolute_profile | jq '.permissions.deny |= (map(select(. != "Bash(gh pr merge:*)")) + ["Bash(x)\nD Bash(gh pr merge:*)"])' >"$home/.claude/settings.json"
posture --
expect_fail "a deny entry carrying a newline that would forge another entry fails" "control character"

reset
absolute_profile | jq '(.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks) as $h
  | .hooks.PreToolUse |= map(select(.matcher != "Bash"))
  | .hooks.PreToolUse += [{matcher: "Read", hooks: [$h[] | .command = ("true\nH Bash\u001f" + .command)]}]' >"$home/.claude/settings.json"
posture --
expect_fail "a hook command carrying a newline that would forge a wired hook fails" "control character"

reset
absolute_profile | jq '.disableAllHooks = "false\nF false false"' >"$home/.claude/settings.json"
posture --
expect_fail "a hook switch carrying a control character fails" "control character"

reset
absolute_profile | jq '.permissions.deny += ["Bash(x)\u007f"]' >"$home/.claude/settings.json"
posture --
expect_fail "a deny entry carrying a DEL fails" "control character"

reset
absolute_profile | jq '(.hooks.PreToolUse[] | select(.matcher == "Bash") | .matcher) |= "Bash\t"' >"$home/.claude/settings.json"
posture --
expect_fail "a matcher carrying a tab fails" "control character"

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
expect_fail "a layer whose deny is not a list fails" "proj/.claude/settings.json cannot be parsed"

reset
absolute_profile >"$home/.claude/settings.json"
printf '[1]\n' >"$proj/.claude/settings.json"
posture --
expect_fail "a layer that is not an object fails" "proj/.claude/settings.json cannot be parsed"

reset
absolute_profile >"$home/.claude/settings.json"
printf '{"hooks": {"PreToolUse": {"matcher": "Bash"}}}\n' >"$proj/.claude/settings.json"
posture --
expect_fail "a layer whose PreToolUse is not a list fails" "proj/.claude/settings.json cannot be parsed"

reset
absolute_profile >"$home/.claude/settings.json"
ln -s "$tmp/nowhere.json" "$proj/.claude/settings.local.json"
posture --
expect_fail "a layer that is a dangling link fails" "settings.local.json cannot be read"

# A reason carrying a control character is still one line.
reset
absolute_profile >"$home/.claude/settings.json"
posture -- --project "$tmp/no
such"
expect_fail "a reason naming a path with a newline stays one line" "nosuch is not a directory"

reset
absolute_profile >"$home/.claude/settings.json"
posture -- --settings "$tmp/missing.json"
expect_fail "a --settings file that does not exist fails" "missing.json does not exist"

echo "# missing tools"
# A tool the check reads with, gone from PATH, is a check that did not run,
# never a pass.
for gone in jq sed awk grep; do
  reset
  absolute_profile >"$home/.claude/settings.json"
  rm -rf "$tmp/tools"
  mkdir -p "$tmp/tools"
  for t in jq sed awk grep tr mktemp rm dirname uname git cat; do
    [ "$t" = "$gone" ] || ln -s "$(command -v "$t")" "$tmp/tools/$t"
  done
  posture PATH="$tmp/tools" --
  if [ "$RC" = 2 ] && case $ERR in *"$gone is required"*) true ;; *) false ;; esac then
    ok "with $gone missing, the check says it did not run (exit 2)"
  else
    fail "with $gone missing, the check exited $RC: $OUT $ERR"
  fi
done
rm -rf "$tmp/tools"

echo "# usage"
if OUT=$(/bin/bash "$POSTURE" --help 2>&1) && case $OUT in usage:*) true ;; *) false ;; esac then
  ok "--help prints the usage and exits 0"
else
  fail "--help did not print the usage with exit 0"
fi
OUT=$(/bin/bash "$POSTURE" 2>&1)
[ "$?" = 2 ] && ok "no verb is a usage error" || fail "no verb did not exit 2"
OUT=$(/bin/bash "$POSTURE" check --bogus 2>&1)
[ "$?" = 2 ] && ok "an unknown flag is a usage error" || fail "an unknown flag did not exit 2"
OUT=$(/bin/bash "$POSTURE" check --settings '' 2>&1)
[ "$?" = 2 ] && ok "an empty --settings value is a usage error" || fail "an empty --settings value did not exit 2"

if [ "$failures" -eq 0 ]; then
  echo "PASS: test-mc-posture.sh"
else
  echo "FAIL: test-mc-posture.sh ($failures)" >&2
  exit 1
fi
