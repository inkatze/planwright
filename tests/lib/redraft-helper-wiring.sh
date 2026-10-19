#!/bin/bash
# Shared pins for the re-draft corrective helper (human-gates REQ-C1.8,
# REQ-G1.5), sourced by both settings-profile wiring suites: under the tier's
# profile and hook set, scripts/request-reviewer.sh run by its literal path is
# approved by the command guard, admitted by the policy guard, and denied by no
# profile rule, while `gh pr ready --undo` stays denied by the profile and the
# policy guard.
#
# The sourcing suite defines ok/fail and REPO_ROOT, and has loaded
# tests/lib/permission-matcher.sh.
unset CDPATH

# rh_decision <hook output> — the hook's permissionDecision, or defer.
rh_decision() {
  if [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then
    printf 'defer'
    return
  fi
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null || printf 'unparsed'
}

# rh_hook <sandbox> <hook script> <command> [<hook args>...] — run a PreToolUse
# hook on a Bash payload and print its decision.
rh_hook() {
  local sb=$1 hook=$2 cmd=$3 payload out rc=0
  shift 3
  payload=$(jq -n --arg c "$cmd" --arg w "$sb" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
  out=$(printf '%s' "$payload" | env -u CLAUDE_DIR HOME="$sb/no-home" CLAUDE_PROJECT_DIR="$sb" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" /bin/bash "$hook" "$@" 2>/dev/null) || rc=$?
  if [ "$rc" != 0 ]; then
    printf 'exit-%s' "$rc"
    return
  fi
  rh_decision "$out"
}

# rh_wiring <tier> <settings file> <command guard script>
rh_wiring() {
  local tier=$1 settings=$2 guard=$3 sb helper got
  helper="$REPO_ROOT/scripts/request-reviewer.sh"
  if [ ! -x "$helper" ]; then
    fail "[$tier] the corrective helper scripts/request-reviewer.sh is missing or not executable"
    return
  fi
  sb=$(mktemp -d "${TMPDIR:-/tmp}/redraft-wiring.XXXXXX") || {
    fail "[$tier] no sandbox for the corrective-helper pins"
    return
  }
  mkdir -p "$sb/no-home"
  local run="$helper --repo acme/widgets --pr 42 --copilot"
  got=$(rh_hook "$sb" "$guard" "$run")
  if [ "$got" = allow ]; then
    ok "[$tier] the command guard approves the corrective helper by its literal path (REQ-G1.5)"
  else
    fail "[$tier] the command guard did not approve the corrective helper ($got) (REQ-G1.5)"
  fi
  got=$(rh_hook "$sb" "$REPO_ROOT/scripts/policy-guard.sh" "$run" "$tier" bash)
  if [ "$got" = defer ]; then
    ok "[$tier] the policy guard admits the corrective helper (REQ-C1.8)"
  else
    fail "[$tier] the policy guard did not admit the corrective helper ($got) (REQ-C1.8)"
  fi
  got=$(rh_hook "$sb" "$REPO_ROOT/scripts/policy-guard.sh" 'gh pr ready 42 --undo' "$tier" bash)
  if [ "$got" = deny ]; then
    ok "[$tier] the policy guard still denies a direct gh pr ready --undo (REQ-C1.8)"
  else
    fail "[$tier] the policy guard did not deny a direct gh pr ready --undo ($got) (REQ-C1.8)"
  fi
  if pm_load_rules "$(jq -r '.permissions.deny // [] | .[]' "$settings")" \
    "$(jq -r '.permissions.ask // [] | .[]' "$settings")" "$(jq -r '.permissions.allow // [] | .[]' "$settings")"; then
    case $(pm_decide "$run") in
      allow | prompt) ok "[$tier] no profile rule refuses the corrective helper (REQ-G1.5)" ;;
      *) fail "[$tier] a profile rule denies or asks on the corrective helper (REQ-G1.5)" ;;
    esac
    case $(pm_decide 'gh pr ready 42 --undo') in
      deny) ok "[$tier] the profile still denies gh pr ready --undo (REQ-C1.8)" ;;
      *) fail "[$tier] the profile no longer denies gh pr ready --undo (REQ-C1.8)" ;;
    esac
  else
    fail "[$tier] the profile's rules did not load into the matcher model"
  fi
  if [ "$tier" = worker ]; then
    local about
    about=$(jq -r '._about // ""' "$settings")
    if [[ $about == *scripts/request-reviewer.sh* ]] && [[ $about != *"never re-draft one"* ]]; then
      ok "[$tier] the profile's description names the helper's corrective re-draft (REQ-C1.8)"
    else
      fail "[$tier] the profile's description still says a worker never re-drafts, or omits the helper (REQ-C1.8)"
    fi
  fi
  rm -rf "$sb"
}
