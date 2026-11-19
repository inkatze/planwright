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
    && printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>"$TMP/jqerr" | grep -qF -- "$3"; then
    ok "deny: $2"
  else
    fail "deny: $2 (exit $CODE, expected reason containing '$3', out '$OUT')"
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
# deny <command> <label> <reason fragment>: the reason must name the shape that
# fired, so a row cannot pass because another shape caught the command.
deny "ls >$NULL" "redirect stdout to the null device" "/dev/null"
deny "ls 2>$NULL" "redirect stderr to the null device" "/dev/null"
deny "ls > $NULL 2>&1" "redirect both to the null device" "/dev/null"
deny "ls &>$NULL" "redirect with &>" "/dev/null"
deny "ls 2>>$NULL" "append to the null device" "/dev/null"
deny "ls >\"$NULL\"" "quoted null-device redirect target" "/dev/null"
deny "cat file <$NULL" "read the null device as stdin" "/dev/null"
deny "cat > $NULL <<X${NL}hello${NL}X" "cat to the null device with a heredoc" "/dev/null"
deny "awk '{print}' f $NULL" "awk with the null device as a file" "/dev/null"
deny "grep -c \"\" $NULL" "grep over the null device" "/dev/null"
deny "cmp <(ls) $NULL" "cmp against the null device" "/dev/null"
deny "diff a.txt $NULL" "diff against the null device" "/dev/null"
deny "make || true" "|| true" "true or :"
deny "ls; true" "; true" "true or :"
deny "ls | cat" "pass-through | cat" "pass-through"
deny "cat file | head" "cat file piped on" "pass-through"
deny "cat > out.txt <<X${NL}X" "empty heredoc" "empty heredoc"
deny "cat > out.txt <<-X${NL}X" "empty tab-stripped heredoc" "empty heredoc"
deny "cat > out.txt <<'X'${NL}${NL}X" "heredoc of only blank lines" "empty heredoc"
deny "cat > out.txt" "cat with no input" "cat with no input"
deny "cat >> out.txt" "cat append with no input" "cat with no input"
deny "echo placeholder > out.txt" "placeholder write" "placeholder"
deny "printf dummy > out.txt" "dummy write" "placeholder"
deny "f() { :; }" "empty function" "empty function"
deny "f() { true; }" "empty function with true" "empty function"
deny "echo" "bare echo" "bare echo"
deny "echo ok" "echo ok" "filler"
deny "echo done" "echo done" "filler"
deny "echo skip" "echo skip" "filler"
deny "ls && echo done" "echo done after a command" "filler"
deny ":" "colon as a step" "true or :"
deny "true" "true as a step" "true or :"
deny "python3 -c 1" "python3 -c 1" "python -c"
deny "python3 -c pass" "python3 -c pass" "python -c"
deny "cd ." "cd ." "cd ."
deny "cd ./" "cd ./" "cd ."
deny "cd /a/b || cd /a/b" "cd X || cd X" "repeats itself"
deny "cd /a/b; cd -" "cd X; cd -" "cd -"
deny "cd /a/b && cd -" "cd X && cd -" "cd -"
deny "head -0 f" "head -0" "count of zero"
deny "head -n 0 f" "head -n 0" "count of zero"
deny "head -c0 f" "head -c0" "count of zero"
deny "sed -n 1,0p f" "sed -n 1,0p" "sed range"
deny "touch /tmp/x.\$\$" "fixed /tmp name with \$\$" "/tmp"
deny "ls > /tmp/out.txt" "fixed /tmp redirect target" "/tmp"
deny "cat /tmp/notes.txt" "fixed /tmp file argument" "/tmp"
deny "FOO=/tmp/x ls" "fixed /tmp name in an assignment" "/tmp"
deny "\$(dirname \$(mktemp -u))/x" "dirname of mktemp -u" "mktemp -u"
deny "mktemp -u" "mktemp -u" "mktemp -u"
deny "mktemp -ud" "mktemp -ud" "mktemp -u"
deny "mktemp --dry-run" "mktemp --dry-run" "mktemp -u"
deny "echo \$(mktemp -d -u)/x" "mktemp -d -u inside a word" "mktemp -u"
deny "tail -f $NULL" "tail -f on the null device" "hold a process open"
deny "tail -F $NULL" "tail -F on the null device" "hold a process open"
deny "tail --follow=name $NULL" "tail --follow on the null device" "hold a process open"
deny "tail -n 0 -f $NULL" "tail -n 0 -f on the null device" "hold a process open"
deny "timeout 100 tail -f $NULL" "a timeout around tail -f on the null device" "hold a process open"
deny "nohup tail -f $NULL &" "nohup tail -f on the null device" "hold a process open"
deny "sleep infinity" "sleep infinity" "hold a process open"
deny "timeout -k 5 100 sleep inf" "a timeout around sleep inf" "hold a process open"
deny "timeout 100 bash -c 'i=0; while [ \$i -lt 90 ]; do i=\$((i+1)); read -t 1 _x < <(tail -f $NULL); done'" "the wait loop that leaked tail holders" "hold a process open"
deny "bash -c \"tail -f $NULL\"" "a double-quoted shell body holding tail" "hold a process open"
deny "sh -c 'sleep infinity'" "a shell body running sleep infinity" "hold a process open"
deny "read -t 1 x < <(tail -f $NULL)" "a process substitution holding tail" "hold a process open"
deny "x=\$(sleep infinity)" "a command substitution holding sleep infinity" "hold a process open"
deny "tail --follow $NULL" "a bare --follow on the null device" "hold a process open"
deny "timeout -s TERM 100 tail -f $NULL" "a timeout with a signal option" "hold a process open"
deny "timeout --foreground 100 sleep infinity" "a timeout with a flag option" "hold a process open"
deny "setsid sleep infinity" "setsid sleep infinity" "hold a process open"
deny "exec -a keep sleep infinity" "exec -a naming the process" "hold a process open"
deny "/usr/bin/sleep infinity" "a path-qualified sleep" "hold a process open"
deny "/usr/bin/tail -f $NULL" "a path-qualified tail" "hold a process open"
deny "sleep Infinity" "sleep Infinity" "hold a process open"
deny "sleep +inf" "sleep +inf" "hold a process open"
deny "bash -lc 'sleep infinity'" "a login shell -c body" "hold a process open"
deny "dash -c 'sleep infinity'" "a dash -c body" "hold a process open"
deny "bash -c 'tail -n 0 -f $NULL'" "a shell body with an option between tail and the path" "hold a process open"
deny "bash -c 'echo hi; sleep infinity'" "a holder after a separator in a shell body" "hold a process open"
deny "echo \$(sleep infinity)" "a command substitution argument" "hold a process open"
deny "cat <(sleep infinity)" "a process substitution argument" "hold a process open"
deny "cat > >(tail -f $NULL)" "an output process substitution target" "hold a process open"

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
defer "mktemp --suffix=.sh" "mktemp with a long option holding a u"
defer "mktemp -d --tmpdir=/home/u/x" "mktemp -d with a long option value"
defer "mktemp -p/home/u/x -d" "mktemp with an attached option value holding a u"
defer "curl -s -o $NULL -w '%{http_code}' http://x" "curl discarding the body to read a status"
defer "ssh -F $NULL host ls" "ssh with an empty config"
defer "cp a $NULL" "cp to the path"
defer "test -e $NULL" "test of the path"
defer "git diff --no-index a $NULL" "git diff against the path"
defer "cd /a || cd -" "cd - after || runs only on failure"
defer "cd /a & cd -" "cd - after a backgrounded cd"
defer "cd /a | cd -" "cd - in a pipeline"
defer "cd /a; cd /a" "two cds to one place on purpose"
defer "grep -r \"/tmp/foo\" src" "a quoted /tmp string as a pattern"
defer "echo \"/tmp/x\"" "a quoted /tmp path printed"
defer "head -c10 f" "head -c10"
defer "cat -n f | head" "cat with an option piped on"
defer "cat < f | sort" "cat reading a redirect piped on"
defer "cat > f < in" "cat with a redirected input"
defer "echo ok > out.txt" "echo ok written to a file"
defer "echo ok >&2" "echo ok to stderr"
defer "timeout 5 true" "true as an argument"
defer "python3 -c 1 f" "python with an extra argument"
defer "sed -n 2,5p f" "sed with a real range"
defer "sleep 30" "a bounded sleep"
defer "sleep 0.5" "a fractional sleep"
defer "timeout 30 tail -f \"\$LOG\"" "a bounded follow of a real log file"
defer "timeout 30 tail -f $TMP/session/run.log" "a bounded follow of a file in scratch"
defer "tail -n 20 $TMP/session/run.log" "a plain tail of a file"
defer "timeout 30 bash -c 'sleep 5'" "a shell body with a bounded sleep"
defer "bash -c 'tail -f \"\$LOG\"'" "a shell body following a real file"
defer "git commit -m 'mention tail -f $NULL and sleep infinity'" "the holder shapes named in a commit message"
defer "echo 'sleep infinity'" "the holder named in an echoed string"
defer "cat > f <<X${NL}tail -f $NULL${NL}sleep infinity${NL}X" "the holder shapes inside a heredoc body"
defer "bash -c 'grep \"sleep infinity\" notes.txt'" "the holder named as a grep pattern in a shell body"
defer "bash -c 'echo sleep infinity'" "the holder named as an echo argument in a shell body"
defer "x=\$(echo 'use sleep infinity')" "the holder named in a string inside a substitution"
defer "x=\$(grep -c 'tail -f $NULL' notes.txt)" "the holder named as a grep pattern inside a substitution"
defer "diff <(echo 'sleep infinity') f" "the holder named in a string inside a process substitution"
defer "echo '\$(sleep infinity)'" "a single-quoted substitution is text"
defer "bash tests/run.sh -ac 'sleep infinity'" "a script's own -c argument is no shell body"
defer "command -v sleep infinity" "command -v is a lookup, not a run"
defer "timeout 30 tail --pid=\$\$ -f $NULL" "a follow bounded by a pid"
defer "sleep 1e9" "a long but bounded sleep"
defer "timeout 5 sleep 30" "a timeout around a bounded sleep"
defer "nohup make > $TMP/session/out.log" "nohup around an ordinary command"
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

# A TMPDIR of /tmp itself must not switch the fixed-name check off.
OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls /tmp/foo"}}' | env TMPDIR=/tmp "$HOOK" 2>"$TMP/stderr")
case $OUT in
  *'"deny"'*) ok "deny: a fixed /tmp name still refused when TMPDIR is /tmp" ;;
  *) fail "TMPDIR=/tmp disabled the fixed-name check: '$OUT'" ;;
esac

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
