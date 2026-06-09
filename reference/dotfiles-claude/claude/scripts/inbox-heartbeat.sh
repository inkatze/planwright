#!/usr/bin/env bash
# inbox-heartbeat.sh — refresh an inbox entry's last-heartbeat field
# every 30 seconds while the owning Claude session is alive.
#
# Per D-23: live entries refresh every 30s; readers (dashboard, status) treat
# entries with heartbeat older than 2 minutes as stale.
#
# Usage: inbox-heartbeat.sh <session-id> <claude-pid>
#
# Self-terminates when any of:
#   * the recorded claude PID is no longer alive (session exited / crashed)
#   * the inbox entry file is gone (Stop hook called inbox-write.sh drop)
#
# Designed to be spawned in the background by the SessionStart hook with
# nohup so it survives the hook script's exit:
#
#   nohup ~/.claude/scripts/inbox-heartbeat.sh "$session_id" "$claude_pid" \
#       >/dev/null 2>&1 &
#   disown
#
# No cleanup needed on exit — the entry's own lifecycle is managed elsewhere.

set -u

if [ $# -lt 2 ]; then
    printf 'usage: %s <session-id> <claude-pid>\n' "$(basename "$0")" >&2
    exit 2
fi

SESSION_ID="$1"
CLAUDE_PID="$2"
INTERVAL="${PAIR_FLOW_HEARTBEAT_INTERVAL:-30}"
WRITER="$HOME/.claude/scripts/inbox-write.sh"
INBOX_DIR="${PAIR_FLOW_INBOX:-$HOME/.claude/inbox}"
# Honor PAIR_FLOW_HOST exactly as inbox-write.sh's host_name() does, otherwise
# the heartbeat would tick a different filename than the writer created.
HOST="${PAIR_FLOW_HOST:-$(hostname -s 2>/dev/null || hostname)}"
ENTRY="$INBOX_DIR/$HOST-$SESSION_ID.json"

# Bail fast if the writer isn't available.
[ ! -x "$WRITER" ] && exit 0

while :; do
    # Entry removed → done.
    [ ! -f "$ENTRY" ] && exit 0
    # Parent claude process gone → done.
    kill -0 "$CLAUDE_PID" 2>/dev/null || exit 0
    "$WRITER" tick "$SESSION_ID" >/dev/null 2>&1 || true
    sleep "$INTERVAL"
done
