#!/usr/bin/env bash
# mc-posture.sh — mission control's posture check: the shipped deny floor in
# force and its guard hooks wired. The skill runs it at bring-up and on every
# failsafe tick, and the launcher before every launch. `--help` holds the
# layers read, the output and the exit codes.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

help_text() {
  cat <<'HELP'
usage: mc-posture.sh check [--settings <file>]... [--project <dir>]
                           [--managed <file>]

The floor is config/mission-control-settings.json under this script's own
root (never an overlay). Every entry of its .permissions.deny must be in the
union of the loaded layers' deny lists, and every guard hook its
.hooks.PreToolUse wires (each `scripts/<guard>.sh <args>` under its matcher)
must be wired under the same matcher in some layer, its path resolving to an
executable file: an absolute directory, or $CLAUDE_PLUGIN_ROOT taken from
this process's environment, which a hook inherits from the same session.

Layers, read by jq projection only (.permissions.deny, .hooks): the user
layer (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json), the project's
.claude/settings.json and .claude/settings.local.json, the managed settings
file, each --settings file, and, with PLANWRIGHT_MC_TOKEN set (handed only to
a mission-control session the launcher started), the profile the launcher
passed it. An absent layer is empty; one that cannot be read or parsed
fails the check.

  --project  the project root (default: the git top level, else the current
             directory)
  --managed  the managed settings file (default: the platform's path)

Output, tab separated, one line:
  posture  pass
  posture  fail  <one-line reason>

Exit codes: 0 pass; 1 fail; 2 usage, or jq absent.
HELP
}

me=mc-posture
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
root=$(cd "$script_dir/.." && pwd -P) || exit 2
floor=$root/config/mission-control-settings.json
TAB=$(printf '\t')

usage() {
  printf '%s\n' "usage: $me check [--settings <file>]... [--project <dir>] [--managed <file>]" >&2
  exit 2
}

# fail <reason>: the one result line, with control characters dropped.
fail() {
  printf 'posture\tfail\t%s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')"
  exit 1
}

case ${1-} in
  -h | --help)
    help_text
    exit 0
    ;;
esac
[ "$#" -ge 1 ] && [ "$1" = check ] || usage
shift
command -v jq >/dev/null 2>&1 || {
  printf '%s\n' "$me: jq is required" >&2
  exit 2
}

layers=()
project='' managed=''
while [ "$#" -gt 0 ]; do
  case $1 in
    --settings | --project | --managed)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --settings) layers+=("$2") ;;
        --project) project=$2 ;;
        --managed) managed=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
if [ -z "$project" ]; then
  project=$(git rev-parse --show-toplevel 2>/dev/null) || project=$(pwd -P) || fail "the current directory cannot be resolved"
fi
if [ -z "$managed" ]; then
  case $(uname -s 2>/dev/null) in
    Darwin) managed='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
    *) managed=/etc/claude-code/managed-settings.json ;;
  esac
fi
user_dir=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
layers+=("$user_dir/settings.json" "$project/.claude/settings.json" "$project/.claude/settings.local.json" "$managed")
if [ -n "${PLANWRIGHT_MC_TOKEN:-}" ]; then
  launched=$(/bin/sh "$script_dir/fleet-launch-profile.sh" mission-control </dev/null 2>/dev/null) \
    || fail "this session was launched as mission control, but the profile it was launched with cannot be found"
  layers+=("$launched")
fi

[ -f "$floor" ] && [ -r "$floor" ] || fail "the shipped mission-control profile ${floor#"$root"/} cannot be read"

# The hook projection: one `<matcher> TAB <command>` per command hook.
# shellcheck disable=SC2016 # jq programs, not shell expansions
hooks_of='.hooks.PreToolUse // [] | if type == "array" then . else error("PreToolUse is not a list") end
  | .[] | (.matcher // "") as $m | (.hooks // [])[] | select(.type == "command")
  | "\($m)\t\(.command)"'
deny_of='.permissions.deny // [] | if type == "array" then .[] | strings else error("deny is not a list") end'

floor_deny=$(jq -r "$deny_of" "$floor" 2>/dev/null) || fail "the shipped deny floor in ${floor#"$root"/} cannot be parsed"
floor_hooks=$(jq -r "$hooks_of" "$floor" 2>/dev/null) || fail "the shipped guard hooks in ${floor#"$root"/} cannot be parsed"
[ -n "$floor_deny" ] || fail "the shipped deny floor in ${floor#"$root"/} is empty"

union_deny=''
union_hooks=''
for l in "${layers[@]}"; do
  [ -e "$l" ] || [ -L "$l" ] || continue
  [ -f "$l" ] && [ -r "$l" ] || fail "the settings layer $l cannot be read"
  d=$(jq -r "$deny_of" "$l" 2>/dev/null) || fail "the settings layer $l cannot be parsed"
  h=$(jq -r "$hooks_of" "$l" 2>/dev/null) || fail "the settings layer $l cannot be parsed"
  union_deny="$union_deny$d"$'\n'
  union_hooks="$union_hooks$h"$'\n'
done

missing=0 first=''
while IFS= read -r e; do
  [ -n "$e" ] || continue
  if ! printf '%s\n' "$union_deny" | grep -qxF -- "$e"; then
    missing=$((missing + 1))
    [ -n "$first" ] || first=$e
  fi
done <<EOF
$floor_deny
EOF
[ "$missing" = 0 ] || fail "the shipped deny floor is not in force: $missing of its entries are in no loaded settings layer, among them $first"

# invocation <command>: the `scripts/<guard>.sh <args>` part of a hook
# command, from its first `/scripts/` up to its first non-word argument.
invocation() {
  local r=${1#*/scripts/}
  [ "$r" != "$1" ] || return 0
  printf 'scripts/%s\n' "$r" | sed -n 's|^\(scripts/[a-z0-9-]*\.sh\( [a-z0-9-][a-z0-9-]*\)*\).*|\1|p'
}
# resolves <command> <invocation>: 0 when the path before the invocation is
# an executable planwright script.
resolves() {
  local pre=${1%%/"${2%% *}"*} dir
  pre=${pre#\"}
  pre=${pre%\"}
  # shellcheck disable=SC2016 # the literal tokens a hook command carries
  case $pre in
    '$CLAUDE_PLUGIN_ROOT' | '${CLAUDE_PLUGIN_ROOT}') dir=${CLAUDE_PLUGIN_ROOT:-} ;;
    /*) dir=$pre ;;
    *) return 1 ;;
  esac
  [ -n "$dir" ] && [ -f "$dir/${2%% *}" ] && [ -x "$dir/${2%% *}" ]
}

while IFS="$TAB" read -r fm fc; do
  [ -n "$fc" ] || continue
  inv=$(invocation "$fc")
  [ -n "$inv" ] || continue
  wired=0 resolved=0
  while IFS="$TAB" read -r lm lc; do
    [ "$lm" = "$fm" ] && [ -n "$lc" ] || continue
    [ "$(invocation "$lc")" = "$inv" ] || continue
    wired=1
    if resolves "$lc" "$inv"; then
      resolved=1
      break
    fi
  done <<EOF
$union_hooks
EOF
  [ "$wired" = 1 ] || fail "the guard hook $inv is not wired for $fm in any loaded settings layer"
  [ "$resolved" = 1 ] || fail "the guard hook $inv is wired for $fm, but its script does not resolve (is CLAUDE_PLUGIN_ROOT a planwright root in this session?)"
done <<EOF
$floor_hooks
EOF

printf 'posture\tpass\n'
exit 0
