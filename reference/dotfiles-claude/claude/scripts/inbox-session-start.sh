#!/usr/bin/env bash
# inbox-session-start.sh — SessionStart hook for the cross-session inbox.
#
# Two responsibilities:
#   1. Initialize the inbox entry for this session (state=working).
#   2. Spawn the 30s heartbeat refresher in the background, detached from
#      this hook script so it survives the hook's exit. It self-terminates
#      when the parent Claude PID dies (kill -9, terminal closed, normal
#      exit), so no cleanup hook is required.
#
# Reads the hook payload on stdin (Claude Code passes JSON with session_id
# and cwd).

set -u

WRITER="$HOME/.claude/scripts/inbox-write.sh"
HEARTBEAT="$HOME/.claude/scripts/inbox-heartbeat.sh"

[ ! -x "$WRITER" ] && exit 0
[ ! -x "$HEARTBEAT" ] && exit 0

# Needs jq to parse the hook payload (and the writer needs it too); degrade
# silently if absent rather than spawning a heartbeat with no entry to tick.
command -v jq >/dev/null 2>&1 || exit 0

# Buffer stdin so we can both feed it to inbox-write and extract session_id
# for the heartbeat spawn.
payload=""
if [ ! -t 0 ]; then
    payload=$(cat)
fi
session_id=""
if [ -n "$payload" ]; then
    session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
fi
[ -z "$session_id" ] && session_id="${CLAUDE_SESSION_ID:-}"
[ -z "$session_id" ] && exit 0

# Initialize the entry (writer also captures repo, branch, tmux target, pid).
printf '%s' "$payload" | "$WRITER" hook-event working >/dev/null 2>&1 || true

# Discover the claude PID for the heartbeat to watch. Walk up the ancestry
# from this script's PPID looking for a `claude` process; fall back to PPID.
discover_claude_pid() {
    local pid="$PPID"
    local depth=0
    while [ "$pid" != "1" ] && [ "$depth" -lt 6 ]; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null | awk -F/ '{print $NF}')
        case "$comm" in
            claude|claude-code)
                printf '%s\n' "$pid"
                return 0
                ;;
        esac
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] && break
        depth=$((depth + 1))
    done
    printf '%s\n' "$PPID"
}
claude_pid=$(discover_claude_pid)

# Spawn the heartbeat detached. nohup + disown so the hook script returning
# doesn't take it down; setsid would be nicer but isn't on BSD.
nohup "$HEARTBEAT" "$session_id" "$claude_pid" >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
