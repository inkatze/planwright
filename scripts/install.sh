#!/bin/bash
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
#   <claude-dir>/skills/<name>/         planwright skills, when present
#   <claude-dir>/commands/<name>.md     planwright commands, when present
#
# It never edits settings.json or any file it does not own: writes are
# confined to the planwright namespace and to skill/command names planwright
# ships (kickoff brief, REQ-I1.2 risk note). Hook wiring needs a settings.json
# merge and is deliberately NOT done here; it is printed as a manual step.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
#
# Fail-fast: any failed write aborts with a non-zero exit (REQ-K1.7: failures
# surface clearly, never as a successful-looking partial install).
set -eu

src_root="$(cd "$(dirname "$0")/.." && pwd)"
claude_dir="${CLAUDE_DIR:-$HOME/.claude}"
dest="$claude_dir/planwright"

copy_tree() {
  # copy_tree <src-dir> <dest-dir> — refresh dest from src (BSD/GNU-portable).
  mkdir -p "$2"
  cp -R "$1/." "$2/"
}

echo "planwright writer: installing into $claude_dir"

copy_tree "$src_root/doctrine" "$dest/doctrine"
copy_tree "$src_root/scripts" "$dest/scripts"
copy_tree "$src_root/config" "$dest/config"

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
echo "by this stub; it ships with the hooks task and stays a manual step here."
