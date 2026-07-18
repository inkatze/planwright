#!/bin/sh
# fleet-statusline.sh — the Claude Code statusLine command that renders the
# derived fleet stats natively in the operator's own terminal, gated on the
# `statusline` notification_channel value (fleet-autonomy Task 8: D-14,
# REQ-F1.2).
#
# THE statusLine CONTRACT (code.claude.com/docs/en/statusline.md, verified
# 2026-07-17). The operator wires this script into their own settings.json:
#
#   { "statusLine": { "type": "command",
#                     "command": "<plugin-root>/scripts/fleet-statusline.sh" } }
#
# Claude Code then invokes it, passing a session JSON object on STDIN and using
# the command's STDOUT as the status line. An empty stdout OR a non-zero exit
# BLANKS the line. It is invoked after each assistant message and on a few UI
# events, debounced ~300ms — so it must be FAST and must never hard-fail: a
# broken fleet home has to blank the line, never break the operator's session.
#
# WHAT THIS COMMAND DOES:
#   - reads and DISCARDS the stdin JSON (the stats derive from the fleet home,
#     not the session — so none of cwd/model/context is needed; draining stdin
#     just avoids a stray SIGPIPE on the writer);
#   - resolves notification_channel through the overlay layers
#     (resolve-notification-channel.sh);
#   - when it is `statusline`, prints the compact derived stats line
#     (fleet-stats.sh line) — the rendering function, invoked with the CURRENT
#     stats, already composing fleet-attention.sh's decision-queue length;
#   - otherwise prints NOTHING: planwright drives the operator's status line ONLY
#     when they opt this channel in. So installing the command is harmless until
#     the channel is chosen, and un-choosing it silently returns the line.
#   - ALWAYS exits 0. Any failure (unresolved channel, unreadable home, a broken
#     sibling) blanks the line by printing nothing, never a non-zero exit.
#
# POSIX sh on the macOS + Linux support bar. No eval, no jq (REQ-K1.5). All
# input is data; the stdin JSON is drained, never parsed or interpolated.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

# Drain stdin (the session JSON) so Claude Code's writer never sees a broken
# pipe; we need none of it. Only when stdin is NOT a terminal: Claude Code always
# pipes the JSON in, but a manual run at a shell has a TTY on stdin, and an
# unconditional `cat` would block there waiting for EOF — hanging a surface whose
# whole contract is to stay fast and never block. `[ -t 0 ]` short-circuits the
# drain in that interactive case; the piped Claude Code path still drains.
[ -t 0 ] || cat >/dev/null 2>&1 || true

script_dir=$(cd "$(dirname "$0")" && pwd) 2>/dev/null || exit 0

RNC="$script_dir/resolve-notification-channel.sh"
STATS="$script_dir/fleet-stats.sh"

# Resolve the channel. Any failure (broken/partial install, a hard-failed
# repo-tracked value) blanks the line rather than surfacing an error into the
# operator's status bar — this surface must never be the thing that breaks.
[ -x "$RNC" ] || exit 0
channel=$("$RNC" 2>/dev/null) || exit 0

# Only the statusline channel means "planwright owns this status line."
[ "$channel" = statusline ] || exit 0

# Render the current derived stats line. A stats failure (unreadable home)
# blanks the line; fleet-stats.sh already degrades each stat to a placeholder
# rather than failing, so this is belt-and-suspenders.
[ -x "$STATS" ] || exit 0
line=$("$STATS" line 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0
printf '%s\n' "$line"
exit 0
