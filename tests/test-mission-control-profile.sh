#!/bin/bash
# config/mission-control-settings.json, the mission-control session's
# settings profile (mission-control REQ-G1.1, REQ-G1.4, REQ-I1.2): the tower
# profile with the ready flip moved from deny to allow, the policy guard at
# its mission-control tier on the Bash, MCP flip and file-tool surfaces, and
# every other entry the tower's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015,SC2016 # ok only prints; the hook text names the root variable literally
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd -P)
MC="$REPO_ROOT/config/mission-control-settings.json"
TOWER="$REPO_ROOT/config/tower-settings.json"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}
ok() { echo "ok: $1"; }

jq -e . "$MC" >/dev/null 2>&1 || {
  echo "FAIL: $MC is missing or not JSON" >&2
  exit 1
}

# --- the deny, ask and allow lists ------------------------------------------

want=$(jq -c '.permissions.deny | map(select(. != "Bash(gh pr ready:*)"))' "$TOWER")
got=$(jq -c '.permissions.deny' "$MC")
if [ "$want" = "$got" ]; then
  ok "the deny list is the tower's, less the ready flip, in the same order"
else
  fail "the deny list drifted from the tower's: missing $(jq -nc --argjson w "$want" --argjson g "$got" '$w - $g'), extra $(jq -nc --argjson w "$want" --argjson g "$got" '$g - $w') (or reordered)"
fi
if jq -e '.permissions.deny | index("Bash(gh pr ready:*)")' "$TOWER" >/dev/null; then
  ok "the tower profile still denies the flip, so the parity above removes a real entry"
else
  fail "the tower profile no longer denies gh pr ready; revisit the mission-control parity rule"
fi
[ "$(jq -c '.permissions.ask' "$MC")" = "$(jq -c '.permissions.ask' "$TOWER")" ] \
  && ok "the ask list (the force-push helper) is the tower's" \
  || fail "the ask list differs from the tower's"
if jq -e --slurpfile t "$TOWER" '.permissions.allow == ($t[0].permissions.allow + ["Bash(gh pr ready:*)"])' "$MC" >/dev/null; then
  ok "the allow list is the tower's plus the ready flip"
else
  fail "the allow list is not the tower's plus Bash(gh pr ready:*)"
fi
[ "$(jq -r '.permissions.defaultMode' "$MC")" = default ] \
  && ok "the default mode is default" || fail "the default mode is not default"

deny=$(jq -r '.permissions.deny[]' "$MC")
ask=$(jq -r '.permissions.ask[]' "$MC")
allow=$(jq -r '.permissions.allow[]' "$MC")
pm_load_rules "$deny" "$ask" "$allow" || fail "the permission model refused the profile's rules"
for c in 'gh pr ready 42' 'gh pr ready 42 --repo acme/widgets'; do
  [ "$(pm_decide "$c")" = allow ] && ok "the profile allows: $c" || fail "the profile does not allow: $c ($(pm_decide "$c"))"
done
for c in 'gh pr merge 42' 'git merge origin/main' 'git push origin main' 'git push --force origin x' 'git rebase origin/main'; do
  [ "$(pm_decide "$c")" = deny ] && ok "the profile denies: $c" || fail "the profile does not deny: $c ($(pm_decide "$c"))"
done
[ "$(pm_decide "$REPO_ROOT/scripts/tower-force-push.sh --branch x")" = ask ] \
  && ok "the force-push helper reaches the operator's prompt" || fail "the force-push helper does not ask"

# --- the hooks --------------------------------------------------------------

suffix="|| { echo 'planwright policy-guard.sh did not run, so this call is refused: export CLAUDE_PLUGIN_ROOT as a planwright plugin root holding scripts/policy-guard.sh, then relaunch mission control' >&2; exit 2; }"
cmds() { # <matcher> — the hook commands that matcher runs, one per line
  jq -r --arg m "$1" '.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[] | .command' "$MC"
}
bash_cmds=$(cmds Bash)
case $bash_cmds in
  *'"$CLAUDE_PLUGIN_ROOT"/scripts/tower-command-guard.sh'*) ok "the Bash matcher runs the tower command guard" ;;
  *) fail "the Bash matcher does not run the tower command guard" ;;
esac
for surface in bash mcp file; do
  case $surface in
    bash) out=$bash_cmds ;;
    mcp) out=$(cmds mcp__github__update_pull_request) ;;
    file) out=$(cmds 'Edit|Write|MultiEdit|NotebookEdit') ;;
  esac
  if printf '%s\n' "$out" | grep -qxF "\"\$CLAUDE_PLUGIN_ROOT\"/scripts/policy-guard.sh mission-control $surface $suffix"; then
    ok "the $surface surface runs the policy guard at the mission-control tier, failing closed"
  else
    fail "the $surface surface does not run 'policy-guard.sh mission-control $surface' with the fail-closed suffix"
  fi
done
file_matcher='Edit|Write|MultiEdit|NotebookEdit'
for tool in Edit Write MultiEdit NotebookEdit; do
  [[ $tool =~ ^($file_matcher)$ ]] && ok "the file matcher covers $tool" || fail "the file matcher misses $tool"
done
for tool in Read Grep Bash; do
  [[ $tool =~ ^($file_matcher)$ ]] && fail "the file matcher also fires on $tool" || ok "the file matcher leaves $tool alone"
done
if jq -e '[.. | objects | .command? // empty | strings | select(test("\\$\\{CLAUDE_PLUGIN_ROOT\\}"))] | length == 0' "$MC" >/dev/null; then
  ok "no hook uses the braced root token, which a --settings profile substitutes empty"
else
  fail "a hook uses \${CLAUDE_PLUGIN_ROOT}"
fi

if [ "$fails" -eq 0 ]; then
  echo "PASS: test-mission-control-profile.sh"
else
  echo "FAIL: test-mission-control-profile.sh ($fails)" >&2
  exit 1
fi
