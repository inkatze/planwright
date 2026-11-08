#!/bin/sh
# background-job-guard.sh — the PreToolUse hook that refuses a backgrounded
# Bash call (`run_in_background: true`) in a session on the stream-json
# backend, telling it to run the command in the foreground with an explicit
# timeout instead.
#
# Why: a stream-json session takes its turns from stdin. A background job's
# completion notice starts no new turn there, so a worker that backgrounds a
# command and ends its turn waits forever and reads as stalled. An
# interactive (tmux) session does resume on the notice, so the refusal is
# keyed on PLANWRIGHT_SESSION_BACKEND, which scripts/fleet-streamjson.sh
# exports for every session it launches and the tmux rung's dispatch wrapper
# drops.
#
# Usage: background-job-guard.sh < <PreToolUse payload>
#   Wired on the Bash matcher of config/worker-settings.json.
# Output: a permissionDecision "deny" with its reason, or nothing (defer).
#   Anything it cannot read (no jq, a payload that is not JSON) defers: a
#   refusal here prevents a stall, it guards no security boundary.
# Exit: 0 always.
#
# POSIX sh; jq reads the payload.
set -u
LC_ALL=C
export LC_ALL

[ "${PLANWRIGHT_SESSION_BACKEND:-}" = stream-json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat) || exit 0
bg=$(printf '%s' "$payload" | jq -r 'if .tool_name == "Bash" and .tool_input.run_in_background == true then "yes" else "no" end' 2>/dev/null) || exit 0
[ "$bg" = yes ] || exit 0

jq -nc --arg r "planwright background-job-guard: this session runs on the stream-json backend, which never resumes on a background job's completion notice, so a backgrounded command stalls it once the turn ends. Run the command in the foreground (run_in_background false) with an explicit timeout (the Bash tool allows up to 600000 ms); split a longer run into bounded calls." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null
exit 0
