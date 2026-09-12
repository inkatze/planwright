#!/bin/bash
# Pins the Claude Code behaviour the worker-settings fragment depends on: how a
# hook command supplied through `--settings` resolves its path.
#
# Measured on CLI 2.1.269. Claude Code consumes the literal braced token
# `${CLAUDE_PLUGIN_ROOT}` as a plugin-context substitution; a fragment passed
# with `--settings` carries no plugin context, so that token substitutes EMPTY
# and the hook command becomes "/scripts/worker-command-guard.sh — a path that
# does not exist, so the hook silently never runs and every dispatched worker
# prompts on every routine command. The bare `$CLAUDE_PLUGIN_ROOT` spelling is
# not matched by that substitution and falls through to ordinary environment
# expansion, which is why the fragment uses it.
#
# This is empirical CLI behaviour, not documented contract, so it is pinned
# here: if a future CLI expands both spellings (or neither), this fails loudly
# instead of the fleet quietly losing its auto-approve hook again.
#
# Skips rather than fails when the CLI is absent, so it stays CI-safe.
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || { echo "skip: claude CLI not on PATH"; exit 0; }

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

marker="$tmp/fired"
cat >"$tmp/probe-hook.sh" <<EOF
#!/bin/sh
cat > /dev/null
echo fired > "$marker"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"probe"}}'
EOF
chmod +x "$tmp/probe-hook.sh"

# probe <hook-command> -> prints "fired" or "silent"
probe() {
  rm -f "$marker"
  PROBE_DIR="$tmp" python3 - "$tmp" "$1" <<'PY'
import json,sys
d,c=sys.argv[1],sys.argv[2]
json.dump({'permissions':{'defaultMode':'default','allow':[]},
 'hooks':{'PreToolUse':[{'matcher':'Bash','hooks':[{'type':'command','command':c}]}]}},
 open(d+'/settings.json','w'))
PY
  (cd "$root" && env CLAUDE_PLUGIN_ROOT="$tmp" PROBE_DIR="$tmp" \
    timeout 90 claude -p --settings "$tmp/settings.json" \
    "Run exactly this bash command and nothing else: git status --short" \
    >/dev/null 2>&1)
  [ -f "$marker" ] && echo fired || echo silent
}

# Guard against a vacuous pass: if a literal absolute path does not fire, the
# probe itself is broken (or hooks are not loaded at all) and every other
# result below would be meaningless.
[ "$(probe "$tmp/probe-hook.sh")" = fired ] \
  || fail "a literal-path hook did not fire — hooks are not loaded from --settings, so this pin cannot be evaluated"

[ "$(probe '$CLAUDE_PLUGIN_ROOT/probe-hook.sh')" = fired ] \
  || fail "bare \$CLAUDE_PLUGIN_ROOT no longer expands — config/worker-settings.json must change spelling"

[ "$(probe '"${CLAUDE_PLUGIN_ROOT}"/probe-hook.sh')" = silent ] \
  || echo "note: braced \${CLAUDE_PLUGIN_ROOT} now expands too; the bare spelling stays correct, the constraint merely relaxed"

# The shipped fragment must use the spelling that survives.
frag="$root/config/worker-settings.json"
cmd=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['hooks']['PreToolUse'][0]['hooks'][0]['command'])" "$frag")
case $cmd in
  '${CLAUDE_PLUGIN_ROOT}'*|'"${CLAUDE_PLUGIN_ROOT}"'*)
    fail "config/worker-settings.json uses the braced spelling, which substitutes empty under --settings: $cmd" ;;
  '$CLAUDE_PLUGIN_ROOT'*) : ;;
  *) fail "unexpected hook command spelling in config/worker-settings.json: $cmd" ;;
esac

echo "ok: settings-fragment hook expansion pinned (bare spelling fires, fragment uses it)"
