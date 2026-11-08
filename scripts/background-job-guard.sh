#!/bin/sh
# background-job-guard.sh — the PreToolUse hook that refuses a backgrounded
# Bash call (`run_in_background: true`) in a session on the stream-json
# backend, telling it to run the command in the foreground with a timeout.
#
# Usage: background-job-guard.sh < <PreToolUse payload>
# Output: a permissionDecision "deny" with its reason, or nothing (defer).
#   What it cannot read (no jq, a payload that is not JSON) defers: the
#   refusal prevents a stall, it guards no security boundary.
# Exit: 0 always. POSIX sh; jq reads the payload.
set -u
LC_ALL=C
export LC_ALL

# A stream-json session takes its turns from stdin, and a background job's
# completion notice starts none, so a worker that backgrounds a command and
# ends its turn waits forever. scripts/fleet-streamjson.sh sets this mark; a
# tmux session resumes on the notice and carries none.
[ "${PLANWRIGHT_SESSION_BACKEND:-}" = stream-json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

bg=$(jq -r 'if .tool_name == "Bash" and .tool_input.run_in_background == true then "yes" else "no" end' 2>/dev/null) || exit 0
[ "$bg" = yes ] || exit 0

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright background-job-guard: this session runs on the stream-json backend, which never resumes on a background job'"'"'s completion notice, so a backgrounded command stalls it once the turn ends. Run the command in the foreground (run_in_background false) with an explicit timeout (the Bash tool allows up to 600000 ms); split a longer run into bounded calls."}}'
exit 0
