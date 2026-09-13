#!/bin/sh
# resolve-installed-roots.sh — print, one per line, every root Claude Code has
# a planwright plugin installed at: the installPath values its own
# <claude-dir>/plugins/installed_plugins.json records for a `planwright@...`
# plugin, plus every version directory under its marketplace cache
# (<claude-dir>/plugins/cache/<marketplace>/planwright/<version>). Raw
# candidates only — callers canonicalize and existence-check.
#
# Why this is one script and not a helper in each caller: the worker-command-
# guard trusts `scripts/*.sh` under these roots, and the stream-json launch
# proves the guard approves a script call under them before it spawns a
# worker. The class this closes was the two disagreeing about which roots a
# worker runs scripts from (the launcher's own checkout versus the plugin
# Claude Code actually loads the skill from), so the answer is computed in
# exactly one place.
#
# The JSON read goes through jq and yields nothing without it; the cache walk
# needs no jq. Neither half ever guesses. <claude-dir> is $CLAUDE_DIR, else
# $HOME/.claude; with neither set nothing is printed.
#
# Usage:
#   resolve-installed-roots.sh
#   No arguments; <claude-dir> comes from the environment as described above.
#
# Exit codes: 0 always. An unset home, an absent or unreadable record, an
#   absent jq, and an empty cache are each empty output, never a failure:
#   callers read empty as "no installed roots" and the arm it feeds does not
#   fire.
#
# POSIX sh; pathname expansion is used for the cache walk only.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

claude_dir=''
if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir=$CLAUDE_DIR
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
fi
[ -n "$claude_dir" ] || exit 0

f="$claude_dir/plugins/installed_plugins.json"
if [ -r "$f" ] && command -v jq >/dev/null 2>&1; then
  jq -r '(.plugins // {}) | to_entries[]
    | select((.key | type) == "string" and (.key | startswith("planwright@")))
    | (.value | if type == "array" then .[] else . end)
    | (.installPath? // empty)
    | select(type == "string" and startswith("/"))' "$f" 2>/dev/null || :
fi

for d in "$claude_dir"/plugins/cache/*/planwright/*/; do
  [ -d "$d" ] || continue
  printf '%s\n' "${d%/}"
done
exit 0
