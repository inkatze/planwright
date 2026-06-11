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
#   <claude-dir>/skills/<name>/         planwright skills, when present
#   <claude-dir>/commands/<name>.md     planwright commands, when present
#
# It never edits settings.json or any file it does not own: writes are
# confined to the planwright namespace and to skill/command names planwright
# ships (kickoff brief, REQ-I1.2 risk note). Hook wiring needs a settings.json
# merge and is deliberately NOT done here; it is printed as a manual step.
#
# Known stub limitation: re-installs refresh-copy and never delete, so files
# removed or renamed in a newer planwright persist as stale copies under the
# namespace. The packaging-finalization task owns the upgrade/cleanup story.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
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

# Pin a private umask: a restrictive caller umask (e.g. 0133) would strip
# directory traversal bits from mkdir -p and break the install; 077 is never
# less restrictive than the caller intended. File modes are preserved from
# the source tree by cp -p.
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
