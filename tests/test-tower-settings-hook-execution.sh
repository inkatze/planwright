#!/bin/bash
# Runs every config/tower-settings.json hook command through `sh -c`, the way
# a `--settings` launch runs it, and judges each guard by its own output rather
# than by the command's spelling: a spelling test passed while every one of
# these hooks was dead (tower-placement REQ-C1.13).
#
# With CLAUDE_PLUGIN_ROOT exported, the command guard allows a tmux read and
# each policy hook emits the policy guard's own deny on a reserved act shaped
# for its matcher. With the root unset, empty, naming a directory without the
# guards, or naming guards that are not executable, each policy hook blocks
# (exit 2, a reason on stderr naming the guard and the remedy) and the command
# guard's hook stays non-blocking, exiting neither 0 nor 2 (REQ-C1.12).
#
# Runs standalone: ./tests/test-tower-settings-hook-execution.sh
#
# shellcheck disable=SC2016
# The hook commands are run as written; their `$CLAUDE_PLUGIN_ROOT` is expanded
# by the `sh -c` under test, never by this file.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tower_settings="$REPO_ROOT/config/tower-settings.json"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() {
  echo "ok: $1"
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# hook_cmd <matcher> <script-name> — the profile's command for that guard.
hook_cmd() {
  jq -r --arg m "$1" --arg s "$2" '
    [.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]?
     | select(.type == "command") | .command | select(contains($s))][0] // ""
  ' "$tower_settings"
}

cmd_guard=$(hook_cmd Bash tower-command-guard.sh)
pg_bash=$(hook_cmd Bash policy-guard.sh)
pg_mcp=$(hook_cmd mcp__github__update_pull_request policy-guard.sh)
for pair in "command guard (Bash)|$cmd_guard" "policy guard (Bash)|$pg_bash" \
  "policy guard (MCP)|$pg_mcp"; do
  if [ -n "${pair#*|}" ]; then
    ok "the profile wires the ${pair%%|*} hook"
  else
    fail "the profile wires no ${pair%%|*} hook; nothing below would run it"
  fi
done
# An empty command runs `sh -c ""`, which exits 0, so every case below would
# fail for a reason that is not its own.
[ "$failures" -eq 0 ] || {
  echo "$failures failure(s)" >&2
  exit 1
}

bash_payload() {
  jq -cn --arg c "$1" --arg w "$tmp" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}'
}
mcp_payload=$(jq -cn --arg w "$tmp" '{tool_name:"mcp__github__update_pull_request",
  tool_input:{owner:"acme", repo:"widgets", pullNumber:42, draft:false}, cwd:$w}')

# run_hook <root-mode> <command> <payload> — sets out, err, rc. The root mode
# is `unset` or `=<value>`; nothing else from this shell reaches the hook.
run_hook() {
  local mode=$1 cmd=$2 payload=$3
  if [ "$mode" = unset ]; then
    printf '%s' "$payload" | env -i PATH="$PATH" HOME="$tmp" \
      sh -c "$cmd" >"$tmp/out" 2>"$tmp/err"
  else
    printf '%s' "$payload" | env -i PATH="$PATH" HOME="$tmp" CLAUDE_PLUGIN_ROOT="${mode#=}" \
      sh -c "$cmd" >"$tmp/out" 2>"$tmp/err"
  fi
  rc=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
}

decision() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null
}
# said_by <guard-prefix> <output> — 0 when the decision's reason is that guard's.
said_by() {
  case $(printf '%s' "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null) in
    "$1"*) return 0 ;;
  esac
  return 1
}
# names_remedy <stderr> — 0 when it names the guard and the remedy.
names_remedy() {
  case $1 in
    *policy-guard*"export CLAUDE_PLUGIN_ROOT"*relaunch*) return 0 ;;
  esac
  return 1
}

# --- REQ-C1.13: each hook runs under a resolved root -------------------------
run_hook "=$REPO_ROOT" "$cmd_guard" "$(bash_payload 'tmux capture-pane -p -t worker')"
if [ "$rc" -eq 0 ] && [ "$(decision "$out")" = allow ] && said_by "planwright tower-command-guard:" "$out"; then
  ok "the command guard's hook allows a tmux read in its own words (REQ-C1.13)"
else
  fail "the command guard's hook did not allow a tmux read (rc=$rc, out=$out, err=$err)"
fi

for act in 'gh pr merge 42' 'git -C . merge feature'; do
  run_hook "=$REPO_ROOT" "$pg_bash" "$(bash_payload "$act")"
  if [ "$rc" -eq 0 ] && [ "$(decision "$out")" = deny ] && said_by "planwright policy-guard:" "$out"; then
    ok "the Bash policy hook emits the guard's own deny on '$act' (REQ-C1.13)"
  else
    fail "the Bash policy hook did not deny '$act' in the guard's words (rc=$rc, out=$out, err=$err)"
  fi
done

run_hook "=$REPO_ROOT" "$pg_mcp" "$mcp_payload"
if [ "$rc" -eq 0 ] && [ "$(decision "$out")" = deny ] && said_by "planwright policy-guard:" "$out"; then
  ok "the MCP policy hook emits the guard's own deny on a draft-to-ready update (REQ-C1.13)"
else
  fail "the MCP policy hook did not deny the draft-to-ready update in the guard's words (rc=$rc, out=$out, err=$err)"
fi

# --- REQ-C1.12: a root that does not hold runnable guards ---------------------
mkdir -p "$tmp/empty-root" "$tmp/noexec-root/scripts"
for g in policy-guard.sh tower-command-guard.sh; do
  # A failed copy would leave the guard missing, a different case than this one.
  cp "$REPO_ROOT/scripts/$g" "$tmp/noexec-root/scripts/$g" || exit 2
  chmod 644 "$tmp/noexec-root/scripts/$g" || exit 2
done

for mode in unset '=' "=$tmp/empty-root" "=$tmp/noexec-root"; do
  case $mode in
    unset) label="unset" ;;
    =) label="empty" ;;
    "=$tmp/empty-root") label="a directory without the guard" ;;
    *) label="a guard that is not executable" ;;
  esac
  for surface in Bash MCP; do
    if [ "$surface" = Bash ]; then
      run_hook "$mode" "$pg_bash" "$(bash_payload 'git status')"
    else
      run_hook "$mode" "$pg_mcp" "$mcp_payload"
    fi
    if [ "$rc" -eq 2 ] && names_remedy "$err"; then
      ok "root $label: the $surface policy hook blocks with the guard and remedy on stderr (REQ-C1.12)"
    else
      fail "root $label: the $surface policy hook did not block with its reason (rc=$rc, err=$err)"
    fi
  done
  run_hook "$mode" "$cmd_guard" "$(bash_payload 'tmux capture-pane -p -t worker')"
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    ok "root $label: the command guard's hook stays non-blocking (exit $rc) (REQ-C1.12)"
  else
    fail "root $label: the command guard's hook exited $rc; it must exit neither 0 nor 2"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all tower-settings hook-execution tests passed"
