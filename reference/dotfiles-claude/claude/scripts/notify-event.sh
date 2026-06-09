#!/usr/bin/env bash
# Notification helper for Claude Code hooks. Consumes the hook JSON on stdin
# and queues a tnotify-send with project context so notifications are useful
# when several Claude instances run in parallel.
#
# Usage: notify-event.sh <event>
#   done        - task finished (Stop hook)
#   permission  - permission prompt (Notification matcher=permission_prompt)
#   idle        - idle prompt (Notification matcher=idle_prompt)

set -u

event="${1:-unknown}"
json=$(cat)
[ -z "$json" ] && json='{}'

cwd=$(printf '%s' "$json" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
project=$(basename "$cwd")
branch=$(git -C "$cwd" branch --show-current 2>/dev/null | tr -d '\n\t')

context="$project"
[ -n "$branch" ] && context="$project · $branch"

case "$event" in
    done)
        title="Claude ✓"
        body="Done in $context"
        ;;
    idle)
        title="Claude ⏳"
        body="Waiting for input · $context"
        ;;
    permission)
        msg=$(printf '%s' "$json" | jq -r '.message // empty' 2>/dev/null)
        [ -z "$msg" ] && msg="needs approval"
        title="Claude ?"
        body="$context · $msg"
        ;;
    *)
        title="Claude"
        body="$context"
        ;;
esac

# Strip tabs/newlines (tnotify queue is tab-separated, newline-delimited).
sanitize() { printf '%s' "$1" | tr '\t\n' '  '; }
title=$(sanitize "$title")
body=$(sanitize "$body")

# shellcheck disable=SC2016  # single quotes are intentional: fish does the expansion.
TNOTIFY_TITLE="$title" TNOTIFY_BODY="$body" \
    fish -c 'tnotify-send $TNOTIFY_TITLE $TNOTIFY_BODY' >/dev/null 2>&1 || true
