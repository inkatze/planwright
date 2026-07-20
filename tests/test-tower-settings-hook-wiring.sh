#!/bin/bash
# Tests for wiring the deterministic tower command-guard into the tower-settings
# profile (fleet-hardening Task 7; REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-E1.4; D-8).
# scripts/tower-command-guard.sh is the PreToolUse hook that auto-approves the
# tower's enumerated known-safe orchestration command set and defers everything
# else; config/tower-settings.json wires it and carries the deny block that is
# the security FLOOR (the guard is allow-only with no default-deny).
#
# This is the JSON-shape assertion Task 7's Done-when calls for: the hook is
# present and correctly shaped in tower-settings.json and ABSENT from the
# plugin-global hooks/hooks.json (tower-scoped only, REQ-C1.2); defaultMode is
# `default` (never `auto`); the deny block denies every dangerous / guardrail op
# across ALL surfaces — shell ops, default-branch / local-main mutation, the
# never-ready `gh pr ready`, and the equivalent GitHub MCP tools (REQ-C1.2 a–d,
# REQ-E1.4); the allow-set carries NO static Bash allow that could bypass the
# guard's escalation pins; the tower safe set DIFFERS from the worker set
# (REQ-C1.2); and _about documents the guard, its posture, and the consciously
# re-opened worker-only-scoping rationale (REQ-C1.3, D-8).
#
# Runs standalone: ./tests/test-tower-settings-hook-wiring.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tower_settings="$REPO_ROOT/config/tower-settings.json"
worker_settings="$REPO_ROOT/config/worker-settings.json"
plugin_hooks="$REPO_ROOT/hooks/hooks.json"
hook_script="$REPO_ROOT/scripts/tower-command-guard.sh"

HOOK_REL="scripts/tower-command-guard.sh"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() {
  echo "ok: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
fi

for f in "$tower_settings" "$worker_settings" "$plugin_hooks"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# --- REQ-C1.1: the fragment is valid Claude Code settings JSON --------------
if jq -e . "$tower_settings" >/dev/null 2>&1; then
  ok "config/tower-settings.json is valid JSON (REQ-C1.1)"
else
  fail "config/tower-settings.json is not valid JSON (REQ-C1.1)"
  echo "$failures failure(s)" >&2
  exit 1
fi

# --- REQ-C1.1: a PreToolUse (Bash) hook references the script via
#     ${CLAUDE_PLUGIN_ROOT} ---------------------------------------------------
if jq -e '
  (.hooks.PreToolUse // [])
  | map(select(.matcher == "Bash"))
  | map(.hooks[]? | select(.type == "command") | .command)
  | any(test("\\$\\{CLAUDE_PLUGIN_ROOT\\}\"?/scripts/tower-command-guard\\.sh"))
' "$tower_settings" >/dev/null 2>&1; then
  ok "tower-settings carries a PreToolUse(Bash) hook referencing the script via \${CLAUDE_PLUGIN_ROOT} (REQ-C1.1)"
else
  fail "tower-settings has no PreToolUse(Bash) command hook referencing \${CLAUDE_PLUGIN_ROOT}/$HOOK_REL (REQ-C1.1)"
fi

if [ -f "$hook_script" ]; then
  ok "the referenced hook script $HOOK_REL exists (REQ-C1.1)"
else
  fail "the wired hook script $HOOK_REL does not exist (REQ-C1.1)"
fi

# --- REQ-C1.1: defaultMode stays `default` (never auto) ----------------------
mode="$(jq -r '.permissions.defaultMode // empty' "$tower_settings")"
if [ "$mode" = "default" ]; then
  ok "permissions.defaultMode is 'default', never 'auto' (REQ-C1.1)"
else
  fail "permissions.defaultMode is '$mode', expected 'default' (REQ-C1.1)"
fi

# --- REQ-C1.2 (a-d) / REQ-E1.4: the deny block denies every required surface -
# Assert every required deny entry is PRESENT (membership), so a future edit
# that drops one is caught by name, then pin the whole block order-sensitively.
require_deny() {
  # require_deny "<label>" "<exact deny entry>"
  if jq -e --arg e "$2" '.permissions.deny | index($e) != null' "$tower_settings" >/dev/null 2>&1; then
    ok "$1"
  else
    fail "$1 — deny block is missing: \"$2\""
  fi
}
# (a) Shell ops.
require_deny "deny gh pr merge (REQ-C1.2a)" "Bash(gh pr merge:*)"
require_deny "deny git merge (REQ-C1.2a)" "Bash(git merge:*)"
require_deny "deny git rebase (REQ-C1.2a)" "Bash(git rebase:*)"
require_deny "deny git commit --amend (REQ-C1.2a)" "Bash(git commit --amend:*)"
require_deny "deny git commit --squash (REQ-C1.2a)" "Bash(git commit --squash:*)"
require_deny "deny git push --force (REQ-C1.2a)" "Bash(git push --force:*)"
require_deny "deny git push --force-with-lease (REQ-C1.2a)" "Bash(git push --force-with-lease:*)"
require_deny "deny git push -f (REQ-C1.2a)" "Bash(git push -f:*)"
require_deny "deny force flag after remote (REQ-C1.2a)" "Bash(git push * --force*)"
require_deny "deny +refspec force form (REQ-C1.2a)" "Bash(git push *+*)"
# (b) Default-branch writes / local-main mutation.
require_deny "deny push HEAD:main short form (REQ-C1.2b)" "Bash(git push *:main)"
require_deny "deny push origin main bare form (REQ-C1.2b)" "Bash(git push * main)"
require_deny "deny push refs/heads/main (REQ-C1.2b)" "Bash(git push *refs/heads/main)"
require_deny "deny git reset --hard (REQ-C1.2b)" "Bash(git reset --hard:*)"
require_deny "deny git branch -f (REQ-C1.2b)" "Bash(git branch -f:*)"
require_deny "deny git branch --force (REQ-C1.2b)" "Bash(git branch --force:*)"
require_deny "deny git update-ref (REQ-C1.2b)" "Bash(git update-ref:*)"
require_deny "deny push --mirror bulk-ref (REQ-C1.2b)" "Bash(git push --mirror:*)"
require_deny "deny push --all bulk-ref (REQ-C1.2b)" "Bash(git push --all:*)"
# (c) Never-ready: the tower never marks a PR ready (the kickoff exception runs
#     under a different, non-tower session).
require_deny "deny gh pr ready — tower never-ready (REQ-C1.2c, REQ-E1.4)" "Bash(gh pr ready:*)"
# (d) Equivalent GitHub MCP tool surface (a Bash-string guard cannot see MCP).
require_deny "deny MCP merge_pull_request (REQ-C1.2d)" "mcp__github__merge_pull_request"
require_deny "deny MCP update_pull_request draft->ready (REQ-C1.2d)" "mcp__github__update_pull_request"
require_deny "deny MCP push_files default-branch write (REQ-C1.2d)" "mcp__github__push_files"
require_deny "deny MCP create_or_update_file default-branch write (REQ-C1.2d)" "mcp__github__create_or_update_file"
require_deny "deny MCP delete_file default-branch write (REQ-C1.2d)" "mcp__github__delete_file"

# Pin the whole deny block order-sensitively: `jq -cS` normalizes whitespace and
# object-key order but preserves array order, so a reorder or accidental
# perturbation fails here. A legitimate future change updates this pinned list in
# the same commit.
expected_deny='["Bash(gh pr merge:*)","Bash(gh pr ready:*)","Bash(git merge:*)","Bash(git rebase:*)","Bash(git commit --amend:*)","Bash(git commit --squash:*)","Bash(git commit --fixup:*)","Bash(git reset --hard:*)","Bash(git filter-branch:*)","Bash(git filter-repo:*)","Bash(git branch -f:*)","Bash(git branch --force:*)","Bash(git update-ref:*)","Bash(git push --force:*)","Bash(git push --force-with-lease:*)","Bash(git push -f:*)","Bash(git push * --force*)","Bash(git push * -f*)","Bash(git push *+*)","Bash(git push *:main)","Bash(git push * main)","Bash(git push *refs/heads/main)","Bash(git push *heads/main)","Bash(git push --mirror:*)","Bash(git push * --mirror*)","Bash(git push --all:*)","Bash(git push * --all*)","mcp__github__merge_pull_request","mcp__github__update_pull_request","mcp__github__push_files","mcp__github__create_or_update_file","mcp__github__delete_file"]'
actual_deny="$(jq -cS '.permissions.deny' "$tower_settings")"
if [ "$actual_deny" = "$(printf '%s' "$expected_deny" | jq -cS .)" ]; then
  ok "the deny block matches the pinned tower baseline (REQ-C1.2, REQ-E1.4)"
else
  fail "the deny block drifted from the pinned baseline (REQ-C1.2, REQ-E1.4)"
  echo "  expected: $(printf '%s' "$expected_deny" | jq -cS .)" >&2
  echo "  actual:   $actual_deny" >&2
fi

# --- REQ-C1.2: no static Bash allow bypasses the guard's escalation pins ------
# The guard is the SOLE Bash allow mechanism (D-8 rejected brittle static rules).
# A static `Bash(...)` allow could match a `claude --worktree ... --permission-mode`
# or `tmux send-keys` shape and bypass the guard's pins, so the allow list must
# carry no Bash entry at all.
if jq -e '[.permissions.allow[] | select(startswith("Bash("))] | length == 0' "$tower_settings" >/dev/null 2>&1; then
  ok "the allow-set carries no static Bash allow (the guard is the sole Bash allow layer; escalation pins cannot be bypassed) (REQ-C1.2)"
else
  fail "the allow-set carries a static Bash allow that could bypass the guard's --dangerously-*/--permission-*/send-keys pins (REQ-C1.2)"
fi

# --- REQ-C1.2: the tower safe set DIFFERS from the worker set -----------------
# The two allow lists are not identical: the tower's non-Bash-tool allow set and
# the worker's permission allow set differ (the worker statically allows git
# add/commit/push/gh, which the tower routes through its distinct guard instead).
tower_allow="$(jq -cS '.permissions.allow' "$tower_settings")"
worker_allow="$(jq -cS '.permissions.allow' "$worker_settings")"
if [ "$tower_allow" != "$worker_allow" ]; then
  ok "the tower allow set differs from the worker allow set (distinct safe set, REQ-C1.2)"
else
  fail "the tower allow set is a verbatim copy of the worker allow set (REQ-C1.2 forbids verbatim reuse)"
fi

# --- REQ-C1.2: tower-scoped only — NOT in the plugin-global hooks.json --------
if jq -e . "$plugin_hooks" >/dev/null 2>&1; then
  plugin_hooks_valid=1
  ok "hooks/hooks.json is valid JSON (REQ-C1.2)"
else
  plugin_hooks_valid=0
  fail "hooks/hooks.json is not valid JSON (REQ-C1.2)"
fi
if grep -q "tower-command-guard" "$plugin_hooks"; then
  fail "the tower auto-approve hook is registered in the plugin-global hooks/hooks.json — tower-scoping breached (REQ-C1.2)"
else
  ok "the tower auto-approve hook is absent from the plugin-global hooks/hooks.json (REQ-C1.2)"
fi
if [ "$plugin_hooks_valid" -ne 1 ]; then
  : # skipped: hooks.json did not parse; the validity check above already failed
elif jq -e '
  (.hooks.PreToolUse // [])
  | map(.hooks[]? | .command // empty)
  | any(test("tower-command-guard"))
' "$plugin_hooks" >/dev/null 2>&1; then
  fail "a plugin-global PreToolUse entry references the tower guard — tower-scoping breached (REQ-C1.2)"
else
  ok "no plugin-global PreToolUse entry references the tower guard (REQ-C1.2)"
fi

# --- REQ-C1.3 / D-8: _about documents the guard and its posture --------------
about="$(jq -r '._about // empty' "$tower_settings")"
require_phrase() {
  # require_phrase "<label>" "<literal substring>"
  if printf '%s' "$about" | grep -qiF "$2"; then
    ok "$1"
  else
    fail "$1 — missing phrase: \"$2\""
  fi
}
if [ -z "$about" ]; then
  fail "tower-settings has no _about field (REQ-C1.3)"
else
  require_phrase "_about names the tower-command-guard hook (REQ-C1.3)" \
    "tower-command-guard.sh"
  require_phrase "_about documents the no-LLM property (REQ-C1.3, REQ-E1.3)" "no-LLM"
  require_phrase "_about documents the allow-only property (REQ-C1.3)" "allow-only"
  require_phrase "_about documents the deny-precedence property (REQ-C1.3)" \
    "deny-precedence"
  require_phrase "_about documents the fail-closed property (REQ-C1.3)" "fail-closed"
  require_phrase "_about documents the escalation pins (REQ-C1.2)" \
    "ESCALATION PINS"
  require_phrase "_about documents the human-sign-off posture (REQ-C1.3)" \
    "sign-off"
  # The consciously re-opened worker-only-scoping (blast radius) rationale (D-8).
  require_phrase "_about documents the re-opened worker-only-scoping rationale (D-8)" \
    "RE-OPENS"
  require_phrase "_about documents the blast-radius rationale (D-8)" \
    "blast-radius"
  # The never-ready reconciliation with the sanctioned kickoff exception.
  require_phrase "_about reconciles the never-ready deny with the kickoff exception (REQ-C1.2c)" \
    "kickoff-lifecycle D-6"
  # The MCP-deny wholesale floor rationale.
  require_phrase "_about documents the wholesale MCP-deny floor rationale (REQ-C1.2d)" \
    "cannot discriminate"
  # The tower-scoped mis-merge warning.
  require_phrase "_about warns against mis-merging the hook into a non-tower settings file (REQ-C1.2)" \
    "tower-scoping is enforced only by where"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all tower-settings hook-wiring tests passed"
