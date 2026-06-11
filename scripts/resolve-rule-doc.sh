#!/bin/bash
# resolve-rule-doc.sh — print the absolute path of a planwright rule doc.
#
# This is the stable rule-doc resolution path (REQ-I1.1, D-24): skills and
# hooks resolve externalized doctrine docs through one convention that works
# in both delivery modes, with no mode detection.
#
# Usage: resolve-rule-doc.sh <doc-name>
#   <doc-name> is the doc's basename, with or without the .md suffix,
#   matching ^[a-z0-9][a-z0-9-]*$ (the REQ-A1.8 identifier discipline).
#
# Resolution order (first hit wins):
#   1. $PLANWRIGHT_ROOT/doctrine/        explicit override (tests, adopters)
#   2. $CLAUDE_PLUGIN_ROOT/doctrine/     plugin delivery (set by Claude Code)
#   3. <claude-dir>/planwright/doctrine/ writer delivery
#      (<claude-dir> is $CLAUDE_DIR when set, else ~/.claude)
#
# Exit codes: 0 found (path on stdout), 1 not found, 2 usage/invalid name.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale: [a-z] range globs are collation-dependent and would
# otherwise admit uppercase under UTF-8 locales.
LC_ALL=C
export LC_ALL

name="${1:-}"
if [ -z "$name" ]; then
  echo "usage: resolve-rule-doc.sh <doc-name>" >&2
  exit 2
fi

# Strip an optional .md suffix, then validate the bare name before it is
# interpolated into any path (REQ-D1.6 framework-script security).
name="${name%.md}"
case "$name" in
  *[!a-z0-9-]* | -* | "")
    echo "planwright: invalid rule-doc name '$1' (must match ^[a-z0-9][a-z0-9-]*$)" >&2
    exit 2
    ;;
esac

# Writer-mode root: derivable only when CLAUDE_DIR or HOME is present.
# Plugin mode must keep working in HOME-less environments (minimal
# containers), so the earlier chain arms never depend on this one.
writer_root=""
if [ -n "${CLAUDE_DIR:-}" ]; then
  writer_root="$CLAUDE_DIR/planwright"
elif [ -n "${HOME:-}" ]; then
  writer_root="$HOME/.claude/planwright"
fi

for root in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "$writer_root"; do
  [ -n "$root" ] || continue
  if [ -f "$root/doctrine/$name.md" ]; then
    printf '%s\n' "$root/doctrine/$name.md"
    exit 0
  fi
done

echo "planwright: rule doc '$name' not found (checked PLANWRIGHT_ROOT, CLAUDE_PLUGIN_ROOT, ${writer_root:-no writer root: CLAUDE_DIR and HOME unset})" >&2
exit 1
