#!/bin/bash
# Tests for wiring the deterministic auto-approve hook into the worker-settings
# profile (worker-permission-ergonomics Task 2; REQ-C1.1, REQ-C1.2, REQ-C1.3,
# REQ-A1.3). Task 1 shipped scripts/worker-command-guard.sh (the PreToolUse hook
# that auto-approves an enumerated known-safe Bash command set and defers
# everything else); Task 2 wires it into config/worker-settings.json — the
# existing human-reviewed worker-permissions fragment — without touching the
# deny block or the plugin-global hooks/hooks.json.
#
# This is the JSON-shape assertion Task 2's Done-when calls for: it confirms the
# hook is present and correctly shaped in worker-settings.json and ABSENT from
# the plugin-global hooks/hooks.json (worker-scoped only, REQ-C1.2), that
# defaultMode stays `default` and the deny block is byte-for-byte unchanged from
# baseline (REQ-C1.1, REQ-A1.3), and that _about documents the hook and its
# posture (REQ-C1.3).
#
# Runs standalone: ./tests/test-worker-settings-hook-wiring.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
worker_settings="$REPO_ROOT/config/worker-settings.json"
plugin_hooks="$REPO_ROOT/hooks/hooks.json"
hook_script="$REPO_ROOT/scripts/worker-command-guard.sh"

# The hook script's repo-relative path, as it appears in the wiring reference.
HOOK_REL="scripts/worker-command-guard.sh"

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

for f in "$worker_settings" "$plugin_hooks"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# --- REQ-C1.1: the fragment is valid Claude Code settings JSON --------------
if jq -e . "$worker_settings" >/dev/null 2>&1; then
  ok "config/worker-settings.json is valid JSON (REQ-C1.1)"
else
  fail "config/worker-settings.json is not valid JSON (REQ-C1.1)"
  # Nothing below can be trusted if the file does not parse.
  echo "$failures failure(s)" >&2
  exit 1
fi

# --- REQ-C1.1: a PreToolUse (Bash) hook references the script via
#     ${CLAUDE_PLUGIN_ROOT} ---------------------------------------------------
# The hook must live under a Bash matcher (it only analyzes Bash commands,
# REQ-A1.7) and reference the plugin script through the same
# ${CLAUDE_PLUGIN_ROOT} mechanism hooks/hooks.json uses, so it resolves under a
# marketplace install. Anchor the two required substrings into ONE contiguous
# pattern (`${CLAUDE_PLUGIN_ROOT}`, an optional closing quote, then the exact
# `/scripts/worker-command-guard.sh` path) rather than testing each substring
# independently: two independent `test()`s could pass a malformed command that
# merely mentions both tokens in unrelated positions, which would not pin the
# exact wiring REQ-C1.1 requires.
if jq -e '
  (.hooks.PreToolUse // [])
  | map(select(.matcher == "Bash"))
  | map(.hooks[]? | select(.type == "command") | .command)
  | any(test("\\$\\{CLAUDE_PLUGIN_ROOT\\}\"?/scripts/worker-command-guard\\.sh"))
' "$worker_settings" >/dev/null 2>&1; then
  ok "worker-settings carries a PreToolUse(Bash) hook referencing the script via \${CLAUDE_PLUGIN_ROOT} (REQ-C1.1)"
else
  fail "worker-settings has no PreToolUse(Bash) command hook referencing \${CLAUDE_PLUGIN_ROOT}/$HOOK_REL (REQ-C1.1)"
fi

# The wiring must point at a hook script that actually exists (Task 1 shipped it).
if [ -f "$hook_script" ]; then
  ok "the referenced hook script $HOOK_REL exists (REQ-C1.1)"
else
  fail "the wired hook script $HOOK_REL does not exist (REQ-C1.1)"
fi

# --- REQ-C1.1: defaultMode stays `default` ----------------------------------
mode="$(jq -r '.permissions.defaultMode // empty' "$worker_settings")"
if [ "$mode" = "default" ]; then
  ok "permissions.defaultMode is 'default' (REQ-C1.1)"
else
  fail "permissions.defaultMode is '$mode', expected 'default' (REQ-C1.1)"
fi

# --- REQ-C1.1 / REQ-A1.3: the deny block is byte-for-byte unchanged ----------
# The deny block encodes planwright's hard invariants (never merge / force-push
# / amend / squash / rebase / push-to-main); Task 2 must not perturb it. This
# pins the deny array against the pre-edit baseline with an order-sensitive
# compact string compare: `jq -cS` normalizes whitespace (and object-key
# order), but does NOT reorder array elements, so reordering the deny list
# fails here too. A LEGITIMATE future change to the deny block updates this
# pinned list in the same commit; an accidental Task-2 perturbation fails here.
expected_deny='["Bash(gh pr merge:*)","Bash(gh pr ready --undo:*)","Bash(gh pr ready * --undo*)","Bash(git merge:*)","Bash(git rebase:*)","Bash(git commit --amend:*)","Bash(git commit --squash:*)","Bash(git commit --fixup:*)","Bash(git reset --hard:*)","Bash(git filter-branch:*)","Bash(git filter-repo:*)","Bash(git push --force:*)","Bash(git push --force-with-lease:*)","Bash(git push -f:*)","Bash(git push * --force*)","Bash(git push * -f*)","Bash(git push *+*)","Bash(git push *:main)","Bash(git push * main)","Bash(git push *refs/heads/main)","Bash(git push *heads/main)","Bash(git push --mirror:*)","Bash(git push * --mirror*)","Bash(git push --all:*)","Bash(git push * --all*)"]'
actual_deny="$(jq -cS '.permissions.deny' "$worker_settings")"
if [ "$actual_deny" = "$(printf '%s' "$expected_deny" | jq -cS .)" ]; then
  ok "the deny block is byte-for-byte unchanged from baseline (REQ-C1.1, REQ-A1.3)"
else
  fail "the deny block changed from baseline (REQ-C1.1, REQ-A1.3)"
  echo "  expected: $(printf '%s' "$expected_deny" | jq -cS .)" >&2
  echo "  actual:   $actual_deny" >&2
fi

# --- REQ-C1.2: worker-scoped only — NOT in the plugin-global hooks.json ------
if jq -e . "$plugin_hooks" >/dev/null 2>&1; then
  plugin_hooks_valid=1
  ok "hooks/hooks.json is valid JSON (REQ-C1.2)"
else
  plugin_hooks_valid=0
  fail "hooks/hooks.json is not valid JSON (REQ-C1.2)"
fi
# The auto-approve hook must never be registered plugin-globally: that would
# load it into tower and human interactive sessions, the blast radius D-5/R7
# rejects. Assert the script is referenced nowhere in hooks/hooks.json.
if grep -q "worker-command-guard" "$plugin_hooks"; then
  fail "the auto-approve hook is registered in the plugin-global hooks/hooks.json (REQ-C1.2)"
else
  ok "the auto-approve hook is absent from the plugin-global hooks/hooks.json (REQ-C1.2)"
fi
# Structural belt-and-suspenders: no PreToolUse command entry in the
# plugin-global hooks references the guard script. Scoped to the guard script
# (not "no PreToolUse hook at all") so an unrelated future plugin-global
# PreToolUse hook does not falsely trip this — REQ-C1.2 forbids only the
# auto-approve hook plugin-globally, not every PreToolUse hook.
# Gate on plugin_hooks_valid: a non-zero `jq -e` exit on an INVALID JSON file
# is a parse error, not a passing structural assertion, so without this guard
# the `else` below would print a misleading `ok` on a corrupt hooks.json (the
# validity check above already fails the suite in that case).
if [ "$plugin_hooks_valid" -ne 1 ]; then
  : # skipped: hooks.json did not parse; the validity check above already failed
elif jq -e '
  (.hooks.PreToolUse // [])
  | map(.hooks[]? | .command // empty)
  | any(test("worker-command-guard"))
' "$plugin_hooks" >/dev/null 2>&1; then
  fail "a plugin-global PreToolUse entry references the auto-approve hook — worker-scoping breached (REQ-C1.2)"
else
  ok "no plugin-global PreToolUse entry references the auto-approve hook (REQ-C1.2)"
fi

# --- REQ-C1.3: _about documents the hook and its posture --------------------
# Assert on distinctive LITERAL phrases (grep -F) rather than `.*`-bridged
# patterns: _about is a single long line, so an unbounded `.*` alternation
# silently matches across unrelated clauses. Each assertion below pins a fixed
# substring the rewrite must carry.
about="$(jq -r '._about // empty' "$worker_settings")"
require_phrase() {
  # require_phrase "<label> (REQ)" "<literal substring>"
  if printf '%s' "$about" | grep -qiF "$2"; then
    ok "$1"
  else
    fail "$1 — missing phrase: \"$2\""
  fi
}
if [ -z "$about" ]; then
  fail "worker-settings has no _about field (REQ-C1.3)"
else
  # The hook itself is named (REQ-C1.3).
  require_phrase "_about names the worker-command-guard hook (REQ-C1.3)" \
    "worker-command-guard.sh"
  # The three named properties the deliverable requires: no-LLM, allow-only,
  # deny-precedence (REQ-C1.3, task Done-when).
  require_phrase "_about documents the no-LLM property (REQ-C1.3)" "no-LLM"
  require_phrase "_about documents the allow-only property (REQ-C1.3)" "allow-only"
  require_phrase "_about documents the deny-precedence property (REQ-C1.3)" \
    "deny-precedence"
  # Human-sign-off posture (REQ-C1.3) — carried over from the pre-edit fragment.
  require_phrase "_about documents the human-sign-off posture (REQ-C1.3)" \
    "sign-off"
  # R7 mis-merge warning: do not merge the auto-approve stanza into a general
  # (tower/human) settings.json; worker-scoping is enforced only by where the
  # hook is wired (REQ-C1.2; brief §7 R7).
  require_phrase "_about warns against mis-merging the hook into a non-worker settings file (REQ-C1.2, R7)" \
    "worker-scoping is enforced only by where"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all worker-settings hook-wiring tests passed"
