#!/bin/bash
# The static profile check (mission-control REQ-G1.1): every profile the
# mission-control launcher delivers covers the commands its sessions run
# routinely, so a sanctioned command never prompts. A command is covered when
# no deny or ask rule of the profile matches it and either a permissions.allow
# rule matches it (tests/lib/permission-matcher.sh, the documented model of
# Claude Code's matcher) or the Bash command guard the profile wires approves
# it. The commands are tests/fixtures/launch-sanctioned.tsv; every profile a
# launcher kind maps to must have rows there.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd -P)
ROWS="$REPO_ROOT/tests/fixtures/launch-sanctioned.tsv"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}
ok() { echo "ok: $1"; }
TAB=$(printf '\t')

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required" >&2
  exit 1
}

# guard_of <profile file> — the command guard script the Bash matcher wires,
# the one hook there that is not the policy guard.
guard_of() {
  jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command
    | capture("^\"\\$CLAUDE_PLUGIN_ROOT\"/scripts/(?<g>[a-z-]+-command-guard\\.sh( [a-z-]+)?)$").g' "$1" | head -1
}

# guard_allows <guard script [mode]> <command>
guard_allows() {
  local out script=${1%% *} mode=''
  [ "$script" = "$1" ] || mode=${1#* }
  out=$(jq -nc --arg c "$2" --arg w "$REPO_ROOT" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w, hook_event_name:"PreToolUse"}' \
    | env CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$REPO_ROOT" /bin/bash "$REPO_ROOT/scripts/$script" ${mode:+"$mode"} 2>/dev/null)
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = allow ]
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pw-launch-profiles.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
PG_CFG="$tmp/local.yml"
PG_ADOPTER="$tmp/adopter"
mkdir -p "$PG_ADOPTER"
printf 'ready_flip_policy: unit-owner\n' >"$PG_CFG"

profiles=$(/bin/sh "$REPO_ROOT/scripts/mission-control-launch.sh" kinds | cut -f2 | sort -u)
[ -n "$profiles" ] || fail "the launcher lists no kind"
for p in $profiles; do
  file="$REPO_ROOT/config/$p-settings.json"
  if [ ! -f "$file" ]; then
    fail "the $p profile a launcher kind maps to does not exist"
    continue
  fi
  n=$(awk -F '\t' -v p="$p" '$1 == p' "$ROWS" | grep -c .)
  if [ "$n" -gt 0 ]; then
    ok "the $p profile has $n sanctioned commands"
  else
    fail "the $p profile has no sanctioned command rows"
    continue
  fi
  guard=$(guard_of "$file")
  [ -n "$guard" ] || fail "the $p profile wires no Bash command guard"
  pm_load_rules "$(jq -r '.permissions.deny[]' "$file")" "$(jq -r '.permissions.ask // [] | .[]' "$file")" \
    "$(jq -r '.permissions.allow[]' "$file")" || fail "the permission model refused the $p profile's rules"
  while IFS="$TAB" read -r prof cmd; do
    case $prof in '' | '#'*) continue ;; esac
    [ "$prof" = "$p" ] || continue
    cmd=${cmd//@ROOT@/$REPO_ROOT}
    verdict=$(pm_decide "$cmd")
    case $verdict in
      deny | ask) fail "[$p] a sanctioned command meets a $verdict rule: $cmd" ;;
      allow) ok "[$p] allowed by the profile's allow list: ${cmd#"$REPO_ROOT"/}" ;;
      *)
        if [ -n "$guard" ] && guard_allows "$guard" "$cmd"; then
          ok "[$p] approved by $guard: ${cmd#"$REPO_ROOT"/}"
        else
          fail "[$p] a sanctioned command would prompt: $cmd"
        fi
        ;;
    esac
    # The mission-control policy guard runs beside the command guard, so a
    # sanctioned command must also pass it with the flip policy permitting.
    if [ "$p" = mission-control ]; then
      pg_out=$(jq -nc --arg c "$cmd" --arg w "$REPO_ROOT" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' \
        | env PLANWRIGHT_LOCAL_CONFIG="$PG_CFG" PLANWRIGHT_ADOPTER_OVERLAY="$PG_ADOPTER" CLAUDE_PROJECT_DIR="$REPO_ROOT" \
          /bin/bash "$REPO_ROOT/scripts/policy-guard.sh" mission-control bash 2>/dev/null)
      case $pg_out in
        *'"deny"'*) fail "[$p] the policy guard refuses a sanctioned command: $cmd" ;;
        *) ok "[$p] the policy guard lets it through: ${cmd#"$REPO_ROOT"/}" ;;
      esac
    fi
  done <"$ROWS"
done
known=" $(printf '%s\n' "$profiles" | tr '\n' ' ') "
while IFS= read -r p; do
  case $known in
    *" $p "*) ;;
    *) fail "the fixture names a profile no launcher kind uses: $p" ;;
  esac
done <<EOF
$(awk -F '\t' '$1 !~ /^#/ && NF > 1 { print $1 }' "$ROWS" | sort -u)
EOF

if [ "$fails" -eq 0 ]; then
  echo "PASS: test-launch-profiles.sh"
else
  echo "FAIL: test-launch-profiles.sh ($fails)" >&2
  exit 1
fi
