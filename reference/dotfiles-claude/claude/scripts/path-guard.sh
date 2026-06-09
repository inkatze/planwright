#!/usr/bin/env bash
# PreToolUse hook that catches file-path mistakes before they waste a tool
# turn. Targets Read, Edit, and Write per D-26 in specs/pair-flow/design.md.
# Bash and NotebookEdit are out of scope (D-26).
#
# Friction this addresses: ~82/month file-path mistakes observed in the
# April-May 2026 transcript analysis. The dominant failure mode is path
# typos and stale paths from refactors. Stopping the tool call with a
# clean reason is materially cheaper than letting the model burn a turn
# on an Edit that misses, then another reading directory contents to
# self-correct.
#
# Behavior:
#   Read, Edit    -> file_path must exist as a regular file (or symlink to one)
#   Write         -> parent directory must exist
#   anything else -> allow
#
# A deny is reported via the JSON permissionDecision envelope so the model
# sees a structured reason rather than a stderr-only message.

set -u

# This hook is an optimization (catch path typos), not a security boundary, and
# it needs jq to parse the payload. Degrade to allow if jq is unavailable (fresh
# machine / partial bootstrap) rather than risking any tool-call friction.
command -v jq >/dev/null 2>&1 || exit 0

# Read the entire JSON payload from stdin.
payload=$(cat)
if [ -z "$payload" ]; then
    exit 0
fi

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only validate the three tools per D-26. Anything else: silent allow.
case "$tool_name" in
    Read|Edit|Write) ;;
    *) exit 0 ;;
esac

# Some pathological inputs: empty file_path. Let Claude Code surface its
# own validation rather than us double-reporting.
[ -z "$file_path" ] && exit 0

deny() {
    local reason="$1"
    # Use the JSON envelope so the model gets a structured reason; this is
    # cleaner than exit-2 + stderr for an LLM consumer.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(printf '%s' "$reason" | jq -Rs .)"
    exit 0
}

case "$tool_name" in
    Read|Edit)
        if [ ! -e "$file_path" ]; then
            deny "path-guard: file does not exist: $file_path. Verify the path (try \`ls\` on the parent dir) before retrying."
        fi
        if [ -d "$file_path" ]; then
            deny "path-guard: path is a directory, not a file: $file_path. Use the appropriate listing tool, not $tool_name."
        fi
        ;;
    Write)
        parent=$(dirname "$file_path")
        if [ ! -d "$parent" ]; then
            deny "path-guard: parent directory does not exist: $parent. Create it first (or correct the path) before writing $file_path."
        fi
        ;;
esac

exit 0
