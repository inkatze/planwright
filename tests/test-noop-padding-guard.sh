#!/bin/bash
# Tests for scripts/noop-padding-guard.sh, the PreToolUse hook that refuses a
# worker's Bash command carrying no-op padding (a redirect to or read of the
# null device, a pass-through stage, an empty heredoc, filler echo, a fixed
# shared name under /tmp, and the other shapes below). The hook emits deny, so
# both directions fail: a missed shape reaches the supervisor, a spurious
# refusal blocks a real command.
#   DENY  <=> exit 0 and stdout carries permissionDecision "deny" with a reason.
#   DEFER <=> exit 0 and stdout is empty.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/noop-padding-guard.sh"
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
  echo "FAIL: jq is required to build and read the hook's payloads" >&2
  exit 1
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-noop-padding-guard.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# hook <command> [tool]: stdout in OUT, exit status in CODE.
hook() {
  hk_payload=$(jq -n --arg c "$1" --arg t "${2:-Bash}" '{tool_name: $t, tool_input: {command: $c}}')
  OUT=$(printf '%s' "$hk_payload" | env TMPDIR="$TMP/session" "$HOOK" 2>"$TMP/stderr")
  CODE=$?
}
deny() {
  hook "$1"
  if [ "$CODE" = 0 ] \
    && [ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>"$TMP/jqerr")" = deny ] \
    && [ -n "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>"$TMP/jqerr")" ]; then
    ok "deny: $2"
  else
    fail "deny: $2 (exit $CODE, out '$OUT')"
  fi
}
defer() {
  hook "$1" "${3:-Bash}"
  if [ "$CODE" = 0 ] && [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then
    ok "defer: $2"
  else
    fail "defer: $2 (exit $CODE, out '$OUT')"
  fi
}

NL=$'\n'
NULL=/dev/null

# --- Shapes to refuse -------------------------------------------------------
deny "ls >$NULL" "redirect stdout to the null device"
deny "ls 2>$NULL" "redirect stderr to the null device"
deny "ls > $NULL 2>&1" "redirect both to the null device"
deny "cat file <$NULL" "read the null device as stdin"
deny "cat > $NULL <<X${NL}hello${NL}X" "cat to the null device with a heredoc"
deny "awk '{print}' f $NULL" "awk with the null device as a file"
deny "grep -c \"\" $NULL" "grep over the null device"
deny "cmp <(ls) $NULL" "cmp against the null device"
deny "diff a.txt $NULL" "diff against the null device"
deny "make || true" "|| true"
deny "ls; true" "; true"
deny "ls | cat" "pass-through | cat"
deny "cat file | head" "cat file piped on"
deny "cat > out.txt <<X${NL}X" "empty heredoc"
deny "cat > out.txt <<'X'${NL}${NL}X" "heredoc of only blank lines"
deny "cat > out.txt" "cat with no input"
deny "echo placeholder > out.txt" "placeholder write"
deny "f() { :; }" "empty function"
deny "f() { true; }" "empty function with true"
deny "echo" "bare echo"
deny "echo ok" "echo ok"
deny "echo done" "echo done"
deny "echo skip" "echo skip"
deny ":" "colon as a step"
deny "true" "true as a step"
deny "python3 -c 1" "python3 -c 1"
deny "cd ." "cd ."
deny "cd /a/b || cd /a/b" "cd X || cd X"
deny "cd /a/b; cd -" "cd X; cd -"
deny "head -0 f" "head -0"
deny "head -n 0 f" "head -n 0"
deny "sed -n 1,0p f" "sed -n 1,0p"
deny "touch /tmp/x.\$\$" "fixed /tmp name with \$\$"
deny "ls > /tmp/out.txt" "fixed /tmp redirect target"
deny "cat /tmp/notes.txt" "fixed /tmp file argument"
deny "FOO=/tmp/x ls" "fixed /tmp name in an assignment"
deny "\$(dirname \$(mktemp -u))/x" "dirname of mktemp -u"
deny "mktemp -u" "mktemp -u"

# The reason names the shape and the allowed alternative, in plain text.
hook "ls >$NULL"
reason=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case $reason in
  *mktemp\ -d*) ok "the reason names the scratch alternative" ;;
  *) fail "the reason does not name mktemp -d: $reason" ;;
esac
case $reason in
  *"ls"*) fail "the reason reflects the command: $reason" ;;
  *) ok "the reason is fixed text, not the command" ;;
esac

# --- Legitimate neighbours --------------------------------------------------
defer "ls > \"\$SCRATCH/out.txt\"" "output to a scratch file"
defer "make > $TMP/session/out.txt" "a file inside the session's own tmp tree"
defer "cat > f <<'X'${NL}body${NL}X" "heredoc with content"
defer "cat > f <<X${NL}text that mentions $NULL and true${NL}X" "the null device named inside a heredoc body"
defer "cat <<X${NL}hello${NL}X" "cat of a heredoc with content"
defer "echo \"\$var\"" "echo of a variable"
defer "echo hello world" "echo of real text"
defer "echo ok | tee out.txt" "echo ok feeding a pipe"
defer "echo \"a; true\"" "true inside a quoted string"
defer "echo 'x > $NULL'" "the null device inside single quotes"
defer "grep -c \"$NULL\" file" "a quoted null-device string as a pattern"
defer "printf '%s\\n' \"$NULL\"" "printf of the path"
defer "git commit -m \"true\"" "true in a commit message"
defer "if true; then ls; fi" "true as a condition"
defer "while true; do ls; done" "true as a loop condition"
defer "mktemp -d" "mktemp -d"
defer "mktemp -d /tmp/work.XXXXXX" "mktemp -d with a template"
defer "ls /tmp" "listing /tmp itself"
defer "ls /tmp/tmp.AbCdEf1234" "a mktemp result"
defer "ls /tmp/claude-1000/x" "the harness's own task directory"
defer "ls /tmp/\$d/f" "a variable name under /tmp"
defer "cd /a/b && ls" "cd then a command"
defer "cd /a/b || cd /c/d" "cd to two different places"
defer "cd -" "cd - alone"
defer "head -n 5 f" "head with a real count"
defer "head -5 f" "head -5"
defer "sed -n 1,5p f" "sed with a real range"
defer "sed 's/a/b/' f" "an ordinary substitution"
defer "python3 -c 'print(1)'" "python3 -c with a real program"
defer "cat a b | sort" "cat of two files piped on"
defer "git push origin br" "an ordinary command"
defer "ls | grep x" "a real pipeline"
defer "cmd 2>&1" "stderr to stdout"
defer "f() { ls; }" "a function with a body"
defer "ls -l \$(echo x)" "a substitution inside an argument"
defer "echo \"\$(ls)\"" "a substitution inside double quotes defers whole"
defer "ls >" "a truncated redirect"
defer "echo 'unterminated" "an unterminated quote"
defer "x=\$(mktemp -d) && ls \"\$x\"" "assignment from mktemp -d"
defer "FOO=bar ls" "an assignment prefix"
defer "ls $NULL" "ls of the path itself"
defer "ls" "a plain command" Read
defer "" "an empty command"

# A non-Bash tool and a malformed payload defer.
OUT=$(printf '%s' 'not json' | "$HOOK" 2>"$TMP/stderr")
if [ -z "$OUT" ]; then ok "defer: a payload that is not JSON"; else fail "a payload that is not JSON was not deferred: $OUT"; fi
OUT=$(printf '%s' '' | "$HOOK" 2>"$TMP/stderr")
if [ -z "$OUT" ]; then ok "defer: an empty payload"; else fail "an empty payload was not deferred: $OUT"; fi
OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{}}' | "$HOOK" 2>"$TMP/stderr")
if [ -z "$OUT" ]; then ok "defer: a Bash payload with no command"; else fail "a Bash payload with no command was not deferred: $OUT"; fi
OUT=$(printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"command\":\"ls >$NULL\"}}" | "$HOOK" 2>"$TMP/stderr")
if [ -z "$OUT" ]; then ok "defer: a non-Bash tool"; else fail "a non-Bash tool was refused: $OUT"; fi
hook "$(printf 'ls %0.s' $(seq 1 3000))>$NULL"
if [ -z "$OUT" ]; then ok "defer: a command over the length bound is not analyzed"; else fail "an over-long command was analyzed: $OUT"; fi
OUT=$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls >$NULL\"}}" | env PATH="$TMP/no-bin" "$BASH" "$HOOK" 2>"$TMP/stderr")
if [ -z "$OUT" ]; then ok "defer: no jq on PATH, so nothing is refused"; else fail "the hook refused without jq: $OUT"; fi

# --- Wiring -----------------------------------------------------------------
if jq -e '(.hooks.PreToolUse // []) | map(select(.matcher == "Bash")) | map(.hooks[]? | .command)
  | any(. == "\"$CLAUDE_PLUGIN_ROOT\"/scripts/noop-padding-guard.sh")' "$WORKER_SETTINGS" >"$TMP/jqwire" 2>&1; then
  ok "the worker profile wires the guard on the Bash matcher"
else
  fail "config/worker-settings.json does not wire \"\$CLAUDE_PLUGIN_ROOT\"/scripts/noop-padding-guard.sh on Bash"
fi

if [ "$failures" -gt 0 ]; then
  echo "noop-padding-guard suite: $failures failure(s)" >&2
  exit 1
fi
echo "all noop-padding-guard tests passed"
