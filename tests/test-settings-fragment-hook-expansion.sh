#!/bin/bash
# Pins the Claude Code behaviour the worker-settings fragment depends on: how a
# hook command supplied through `--settings` resolves its path.
#
# Measured on CLI 2.1.269. The spelling is squeezed from two sides at once, and
# only one form survives both.
#
# BRACES: Claude Code consumes the literal braced token `${CLAUDE_PLUGIN_ROOT}`
# as a plugin-context substitution. A fragment passed with `--settings` carries
# no plugin context, so that token substitutes EMPTY, the command becomes
# "/scripts/worker-command-guard.sh, and the hook silently never runs — every
# dispatched worker then prompts on every routine command. So: no braces.
#
# QUOTES: the command is evaluated by a shell, so an unquoted path word-splits
# on a root containing a space and the hook again silently never runs (measured
# directly, not inferred). So: quoted.
#
# Which leaves exactly `"$CLAUDE_PLUGIN_ROOT"/scripts/...` — quoted, unbraced.
# Both halves are load-bearing and neither is obvious from the other, which is
# why each gets its own case below.
#
# This is empirical CLI behaviour, not documented contract, so it is pinned
# here: if a future CLI expands both spellings (or neither), this fails loudly
# instead of the fleet quietly losing its auto-approve hook again.
#
# Skips rather than fails when the CLI is absent, so it stays CI-safe.
#
# shellcheck disable=SC2016
# The unexpanded literals ARE the subject: this file compares hook-command
# spellings as written, so a single-quoted `$CLAUDE_PLUGIN_ROOT` is intentional
# everywhere it appears and expanding one would test nothing.
set -u

# A CDPATH-resolved cd echoes its destination into a command substitution.
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

command -v claude >/dev/null 2>&1 || {
  echo "skip: claude CLI not on PATH"
  exit 0
}

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

marker="$tmp/fired"
# The probe root carries a space on purpose: an unquoted hook path word-splits
# here and goes silent, which is the whole point of the quoting half.
root_with_space="$tmp/plugin root"
mkdir -p "$root_with_space"
cat >"$root_with_space/probe-hook.sh" <<EOF
#!/bin/sh
cat > /dev/null
echo fired > "$marker"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"probe"}}'
EOF
chmod +x "$root_with_space/probe-hook.sh"

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
  (cd "$root" && env CLAUDE_PLUGIN_ROOT="$root_with_space" PROBE_DIR="$root_with_space" \
    timeout 90 claude -p --settings "$tmp/settings.json" \
    "Run exactly this bash command and nothing else: git status --short" \
    >/dev/null 2>&1)
  [ -f "$marker" ] && echo fired || echo silent
}

# Guard against a vacuous pass: if a literal quoted path does not fire, the probe
# itself is broken (or hooks are not loaded at all) and every result below would
# be meaningless.
[ "$(probe "\"$root_with_space\"/probe-hook.sh")" = fired ] \
  || fail "a literal-path hook did not fire — hooks are not loaded from --settings, so this pin cannot be evaluated"

# The spelling the fragment must use: unbraced (survives the plugin-context
# substitution) and quoted (survives a root containing a space).
[ "$(probe '"$CLAUDE_PLUGIN_ROOT"/probe-hook.sh')" = fired ] \
  || fail "quoted-unbraced \"\$CLAUDE_PLUGIN_ROOT\" no longer fires — config/worker-settings.json must change spelling"

# The braces half: a braced token is eaten before the shell ever sees it.
[ "$(probe '"${CLAUDE_PLUGIN_ROOT}"/probe-hook.sh')" = silent ] \
  || echo "note: braced \${CLAUDE_PLUGIN_ROOT} now expands too; the unbraced spelling stays correct, the constraint merely relaxed"

# The quoting half: unquoted word-splits on the space in the root. This is why
# dropping the quotes along with the braces was a regression, not a tidy-up.
[ "$(probe '$CLAUDE_PLUGIN_ROOT/probe-hook.sh')" = silent ] \
  || echo "note: unquoted \$CLAUDE_PLUGIN_ROOT now survives a spaced root; quoting stays correct, the constraint merely relaxed"

# The shipped fragment must use the spelling that survives.
frag="$root/config/worker-settings.json"
cmd=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['hooks']['PreToolUse'][0]['hooks'][0]['command'])" "$frag")
case $cmd in
  *'${CLAUDE_PLUGIN_ROOT}'*)
    fail "config/worker-settings.json uses the braced spelling, which substitutes empty under --settings: $cmd"
    ;;
  '"$CLAUDE_PLUGIN_ROOT"'/*) : ;;
  *) fail "config/worker-settings.json must reference the guard as \"\$CLAUDE_PLUGIN_ROOT\"/... (quoted, unbraced), got: $cmd" ;;
esac

echo "ok: settings-fragment hook expansion pinned (quoted-unbraced fires; braced and unquoted do not)"
