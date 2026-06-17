#!/usr/bin/env bash
# install.sh — the ~/.claude/ writer, planwright's fallback delivery mode
# (REQ-I1.2, D-24). v1 stub: copies plugin content into namespaced paths.
#
# Usage: install.sh
#   CLAUDE_DIR overrides the destination (default: ~/.claude).
#
# What it writes (and nothing else):
#   <claude-dir>/planwright/doctrine/   rule docs
#   <claude-dir>/planwright/scripts/    helper scripts (incl. the resolver)
#   <claude-dir>/planwright/config/     tracked default config
#   <claude-dir>/planwright/plugin.json plugin manifest (writer-mode namespace
#                                       source for adopter-overlay resolution)
#   <claude-dir>/skills/<name>/         planwright skills, when present
#   <claude-dir>/commands/<name>.md     planwright commands, when present
#
# It never edits settings.json or any file it does not own: writes are
# confined to the planwright namespace and to skill/command names planwright
# ships (kickoff brief, REQ-I1.2 risk note). Hook wiring needs a settings.json
# merge and is deliberately NOT done here; it is printed as a manual step.
#
# Upgrade/cleanup: a re-install refresh-copies and never deletes, so files
# removed or renamed in a newer planwright would persist as stale copies under
# the namespace. To upgrade cleanly, delete <claude-dir>/planwright/ first and
# re-run the writer (a clean reinstall). The writer deletes nothing on its own:
# removing files under ~/.claude is the operator's deliberate step, not an
# autopilot one. See docs/getting-started.md ("Upgrading and cleaning up").
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
#
# Exit codes: 0 success, 2 environment/validation error (no usable claude
# dir, or running from the installed location). Any other non-zero status is
# a failed write aborting the run: set -e propagates the failing command's
# own exit code (commonly 1 from mkdir/cp).
#
# Fail-fast: any failed write aborts with a non-zero exit (REQ-K1.7: failures
# surface clearly, never as a successful-looking partial install).
set -eu

# Pin the C locale for deterministic glob ordering (defensive; mirrors the
# sibling scripts).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below and
# corrupt the source-root derivation.
unset CDPATH

# Pin a known umask so mkdir -p always creates owner-traversable directories:
# a caller umask that strips user bits (e.g. 0133) would otherwise break the
# install. 077 keeps everything it creates owner-only; file modes are
# preserved from the source tree by cp -p.
umask 077

src_root="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir="$CLAUDE_DIR"
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
else
  echo "planwright writer: set CLAUDE_DIR (or HOME) to locate the Claude config dir" >&2
  exit 2
fi
dest="$claude_dir/planwright"

# Running the installed copy would copy every file onto itself and cannot
# restore skills/commands (they live outside this namespace). Refuse clearly.
# Compare physical paths (pwd -P above; resolve dest when it exists) so a
# symlinked route to the installed location is still caught.
if [ -d "$dest" ]; then
  dest_physical="$(cd "$dest" && pwd -P)"
else
  dest_physical="$dest"
fi
if [ "$src_root" = "$dest_physical" ]; then
  echo "planwright writer: refusing to run from the installed location ($dest);" >&2
  echo "run the writer from the planwright repo or plugin checkout instead" >&2
  exit 2
fi

copy_tree() {
  # copy_tree <src-dir> <dest-dir> — refresh dest from src (BSD/GNU-portable).
  # -p preserves the shipped file modes (notably script executable bits).
  mkdir -p "$2"
  cp -Rp "$1/." "$2/"
}

echo "planwright writer: installing into $claude_dir"

copy_tree "$src_root/doctrine" "$dest/doctrine"
copy_tree "$src_root/scripts" "$dest/scripts"
copy_tree "$src_root/config" "$dest/config"

# Copy the plugin manifest into the namespace root so writer-mode
# adopter-overlay resolution can derive its namespace from the manifest `name`
# (D-3, REQ-A1.5). Plugin mode reads the namespace from $CLAUDE_PLUGIN_DATA and
# never needs this; writer mode has no such variable, so the manifest is its
# only namespace source.
if [ -f "$src_root/.claude-plugin/plugin.json" ]; then
  cp -p "$src_root/.claude-plugin/plugin.json" "$dest/plugin.json"
fi

if [ -d "$src_root/skills" ]; then
  for skill in "$src_root"/skills/*/; do
    [ -d "$skill" ] || continue
    copy_tree "$skill" "$claude_dir/skills/$(basename "$skill")"
  done
fi

if [ -d "$src_root/commands" ]; then
  mkdir -p "$claude_dir/commands"
  for cmd in "$src_root"/commands/*.md; do
    [ -f "$cmd" ] || continue
    cp "$cmd" "$claude_dir/commands/"
  done
fi

echo "planwright writer: done."
echo "  rule docs:  $dest/doctrine"
echo "  config:     $dest/config/defaults.yml"
echo "  per-repo overrides go in <repo>/.claude/planwright.local.yml (gitignored)"
echo "Note: hook wiring requires a settings.json merge and is not performed"
echo "by this stub (it never edits files it does not own). Plugin installs"
echo "get the hooks automatically via hooks/hooks.json; for this writer"
echo "delivery, add to ~/.claude/settings.json hooks:"
echo "  PostToolUse  (matcher \"Bash\"): $dest/scripts/tasks-pr-sync.sh"
echo "  SessionStart:                  $dest/scripts/tool-discovery.sh"
