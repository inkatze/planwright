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
executable file: an absolute directory, or the CLAUDE_PLUGIN_ROOT token
expanded from this process's environment, which a hook inherits from the
same session.

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
[ -d "$project" ] || fail "the project root $project is not a directory"
if [ -z "$managed" ]; then
  case $(uname -s 2>/dev/null) in
    Darwin) managed='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
    *) managed=/etc/claude-code/managed-settings.json ;;
  esac
fi
user_dir=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
# A --settings file is one the caller says is loaded, so it must exist.
for l in ${layers[@]+"${layers[@]}"}; do
  [ -f "$l" ] || fail "the settings layer $l does not exist"
done
layers+=("$user_dir/settings.json" "$project/.claude/settings.json" "$project/.claude/settings.local.json")
if [ -n "${PLANWRIGHT_MC_TOKEN:-}" ]; then
  # The token binds this session to the launcher's registry row, which
  # records the profile the session was launched with.
  fh=$(/bin/sh "$script_dir/fleet-state.sh" root </dev/null 2>/dev/null) || fail "the fleet home holding the launcher's registry cannot be resolved"
  launched=''
  for row in "$fh"/mission-control/sessions/*; do
    [ -f "$row" ] && [ ! -L "$row" ] || continue
    launched=$(awk -F '\t' -v t="$PLANWRIGHT_MC_TOKEN" '
      $1 == "token" { tok = $2 } $1 == "kind" { kind = $2 } $1 == "profile" { prof = $2 }
      END { if (tok == t && kind == "mission-control") print prof }' "$row")
    [ -z "$launched" ] || break
  done
  [ -n "$launched" ] || fail "this session holds a mission-control token that no launcher registry row carries"
  case $launched in /*) ;; *) fail "the launcher registry row records no absolute profile path" ;; esac
  [ -f "$launched" ] || fail "the profile this session was launched with, $launched, does not exist"
  layers+=("$launched")
fi

[ -f "$floor" ] && [ -r "$floor" ] || fail "the shipped mission-control profile ${floor#"$root"/} cannot be read"

US=$(printf '\037')
tmpd=$(mktemp -d "${TMPDIR:-/tmp}/mc-posture.XXXXXX") || fail "a scratch directory cannot be created"
trap 'rm -rf "$tmpd"' EXIT
# One jq run per layer, one line per fact: `F <disableAllHooks>
# <allowManagedHooksOnly>`, `D <deny entry>`, `H <matcher>US<command>`.
# shellcheck disable=SC2016 # a jq program, not shell expansions
project_facts='
  def list(x; what): if x == null then [] elif (x | type) == "array" then x else error(what + " is not a list") end;
  if type != "object" then error("not an object") else . end
  | ("F " + ((.disableAllHooks // false) | tostring) + " " + ((.allowManagedHooksOnly // false) | tostring)),
    (list(.permissions.deny; "deny")[] | strings | "D " + .),
    (list(.hooks.PreToolUse; "PreToolUse")[]
      | (.matcher // "") as $m | list(.hooks; "hooks")[] | select(.type == "command")
      | "H " + $m + "\u001f" + .command)'

facts() { jq -r "$project_facts" "$1" 2>/dev/null; }

floor_facts=$(facts "$floor") || fail "the shipped profile ${floor#"$root"/} cannot be parsed"
printf '%s\n' "$floor_facts" | grep -q '^D ' || fail "the shipped deny floor in ${floor#"$root"/} is empty"

union_deny="$tmpd/deny"
union_hooks="$tmpd/hooks"
managed_hooks="$tmpd/managed-hooks"
: >"$union_deny"
: >"$union_hooks"
: >"$managed_hooks"
managed_only=0
for l in ${layers[@]+"${layers[@]}"} "$managed"; do
  [ -e "$l" ] || [ -L "$l" ] || continue
  [ -f "$l" ] && [ -r "$l" ] || fail "the settings layer $l cannot be read"
  lf=$(facts "$l") || fail "the settings layer $l cannot be parsed"
  case $(printf '%s\n' "$lf" | sed -n 's/^F //p') in
    true\ *) fail "every hook is turned off (disableAllHooks) in the settings layer $l" ;;
    *\ true) managed_only=1 ;;
  esac
  printf '%s\n' "$lf" | sed -n 's/^D //p' >>"$union_deny"
  printf '%s\n' "$lf" | sed -n 's/^H //p' >>"$union_hooks"
  [ "$l" != "$managed" ] || printf '%s\n' "$lf" | sed -n 's/^H //p' >>"$managed_hooks"
done
# Under allowManagedHooksOnly only the managed layer's hooks run.
[ "$managed_only" = 0 ] || union_hooks=$managed_hooks

printf '%s\n' "$floor_facts" | sed -n 's/^D //p' >"$tmpd/floor-deny"
missing=$(awk 'FILENAME == ARGV[1] { have[$0] = 1; next } !($0 in have) { n++; if (n == 1) first = $0 }
  END { if (n) print n "\t" first }' "$union_deny" "$tmpd/floor-deny")
[ -z "$missing" ] || fail "the shipped deny floor is not in force: ${missing%%"$TAB"*} of its entries are in no loaded settings layer, among them ${missing#*"$TAB"}"

# invocation <command>: the `scripts/<guard>.sh <args>` part of a shipped
# hook command, up to its first non-word argument.
invocation() {
  local r=${1#*/scripts/}
  [ "$r" != "$1" ] || return 0
  printf 'scripts/%s\n' "$r" | sed -n 's|^\(scripts/[a-z0-9-]*\.sh\( [a-z0-9-][a-z0-9-]*\)*\).*|\1|p'
}
# guard_dir <prefix>: the directory a hook command's unquoted prefix names.
guard_dir() {
  local pre=${1#\"}
  pre=${pre%\"}
  # shellcheck disable=SC2016 # the literal tokens a hook command carries
  case $pre in
    '$CLAUDE_PLUGIN_ROOT' | '${CLAUDE_PLUGIN_ROOT}') printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-}" ;;
    /*) printf '%s\n' "$pre" ;;
  esac
}
# planwright_guard <dir> <script>: 0 when <dir>/<script> is this root's own
# guard, or an executable guard under a planwright plugin root.
planwright_guard() {
  [ -n "$1" ] && [ -f "$1/$2" ] && [ -x "$1/$2" ] || return 1
  [ "$1/$2" -ef "$root/$2" ] && return 0
  jq -e '.name == "planwright"' "$1/.claude-plugin/plugin.json" >/dev/null 2>&1
}

while IFS= read -r fh_line; do
  fm=${fh_line%%"$US"*}
  fc=${fh_line#*"$US"}
  inv=$(invocation "$fc")
  [ -n "$inv" ] || fail "a shipped guard hook in ${floor#"$root"/} names no planwright script"
  # A wired hook ends exactly as the shipped one does, so one that discards
  # the guard's verdict or drops its fail-closed suffix is not wired.
  tail="/$inv${fc#*"/$inv"}"
  wired=0 resolved=0
  while IFS= read -r l_line; do
    [ "${l_line%%"$US"*}" = "$fm" ] || continue
    lc=${l_line#*"$US"}
    case $lc in *"$tail") ;; *) continue ;; esac
    wired=1
    if planwright_guard "$(guard_dir "${lc%"$tail"}")" "${inv%% *}"; then
      resolved=1
      break
    fi
  done <"$union_hooks"
  [ "$wired" = 1 ] || fail "the guard hook $inv is not wired for $fm in any loaded settings layer"
  [ "$resolved" = 1 ] || fail "the guard hook $inv is wired for $fm, but its script does not resolve to a planwright guard (is CLAUDE_PLUGIN_ROOT a planwright root in this session?)"
done < <(printf '%s\n' "$floor_facts" | sed -n 's/^H //p')

printf 'posture\tpass\n'
exit 0
