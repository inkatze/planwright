#!/bin/bash
# Tests for scripts/background-job-guard.sh, the PreToolUse hook that refuses a
# backgrounded Bash call in a session on the stream-json backend, which never
# resumes on the job's completion notice. The guard emits deny, so both
# directions are failures: a missed deny stalls a worker, a spurious one
# blocks a foreground command.
#   DENY  <=> exit 0 and stdout carries permissionDecision "deny" with a reason.
#   DEFER <=> exit 0 and stdout is empty.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/background-job-guard.sh"
WORKER_SETTINGS="$REPO_ROOT/config/worker-settings.json"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

[ -x "$HOOK" ] || {
  echo "FAIL: $HOOK is missing or not executable" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to read the hook's output" >&2
  exit 1
}

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# hook <backend|-> <payload> [ENV=val...]: stdout in OUT, exit status in CODE.
hook() {
  hk_backend=$1
  hk_payload=$2
  shift 2
  if [ "$hk_backend" = - ]; then
    OUT=$(printf '%s' "$hk_payload" | env -u PLANWRIGHT_SESSION_BACKEND "$@" "$HOOK" 2>/dev/null)
  else
    OUT=$(printf '%s' "$hk_payload" | env PLANWRIGHT_SESSION_BACKEND="$hk_backend" "$@" "$HOOK" 2>/dev/null)
  fi
  CODE=$?
}
assert_deny() {
  hook "$@"
  if [ "$CODE" = 0 ] \
    && [ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = deny ] \
    && [ -n "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)" ]; then
    ok "deny: $DESC"
  else
    fail "deny: $DESC (exit $CODE, out '$OUT')"
  fi
}
assert_defer() {
  hook "$@"
  if [ "$CODE" = 0 ] && [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then
    ok "defer: $DESC"
  else
    fail "defer: $DESC (exit $CODE, out '$OUT')"
  fi
}

bg='{"tool_name":"Bash","tool_input":{"command":"tests/test-x.sh","run_in_background":true}}'
fg='{"tool_name":"Bash","tool_input":{"command":"tests/test-x.sh","run_in_background":false}}'
plain='{"tool_name":"Bash","tool_input":{"command":"tests/test-x.sh"}}'

DESC="a backgrounded Bash call on the stream-json backend"
assert_deny stream-json "$bg"
reason=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case $reason in
  *foreground*timeout*) ok "the reason redirects to the foreground with an explicit timeout" ;;
  *) fail "the reason does not redirect to the foreground with a timeout: $reason" ;;
esac
DESC="a foreground Bash call on the stream-json backend"
assert_defer stream-json "$fg"
DESC="a Bash call that does not name run_in_background"
assert_defer stream-json "$plain"
DESC="a string \"true\" is not the flag"
assert_defer stream-json '{"tool_name":"Bash","tool_input":{"command":"x","run_in_background":"true"}}'
DESC="another tool with a background flag"
assert_defer stream-json '{"tool_name":"Agent","tool_input":{"prompt":"x","run_in_background":true}}'
DESC="a backgrounded call on the tmux backend, which resumes on the notice"
assert_defer tmux "$bg"
DESC="a backgrounded call in a session no launcher marked"
assert_defer - "$bg"
DESC="a payload that is not JSON"
assert_defer stream-json 'not json'
DESC="an empty payload"
assert_defer stream-json ''
DESC="no jq on PATH: the flag cannot be read, so nothing is refused"
assert_defer stream-json "$bg" "PATH=$TMP/no-bin"

# The wiring: the worker profile runs the guard on every Bash call, in the
# unbraced spelling a --settings fragment needs.
if jq -e '(.hooks.PreToolUse // []) | map(select(.matcher == "Bash")) | map(.hooks[]? | .command)
  | any(. == "\"$CLAUDE_PLUGIN_ROOT\"/scripts/background-job-guard.sh")' "$WORKER_SETTINGS" >/dev/null 2>&1; then
  ok "the worker profile wires the guard on the Bash matcher"
else
  fail "config/worker-settings.json does not wire \"\$CLAUDE_PLUGIN_ROOT\"/scripts/background-job-guard.sh on Bash"
fi

if [ "$failures" -gt 0 ]; then
  echo "background-job-guard suite: $failures failure(s)" >&2
  exit 1
fi
echo "all background-job-guard tests passed"
