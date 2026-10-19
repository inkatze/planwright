#!/bin/bash
# Adversarial suite for scripts/tower-session.sh, the plugin-wired tower
# floor's session marking (tower-placement REQ-C1.1 to REQ-C1.6, REQ-C1.9):
# the prompt hook's marking, the activation handshake, the unmarked path's
# fork-free prefilter, failing closed in a marked session, the store's safety
# bar and pruning, the fleet-home parity with scripts/fleet-state.sh, and the
# hooks.json wiring (deny-only, timeouts). The deny list's acts are
# tests/test-tower-floor-*.sh's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
# shellcheck disable=SC2034 # the decide globals are read by the shared expect and reason_has
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

cp "$REAL_SCRIPTS/tower-session.sh" "$S/"
TS="$S/tower-session.sh"
FLEET="$SANDBOX/fleet"
STORE="$FLEET/tower-sessions"
MARKED=11111111-2222-4333-8444-555555555555
OTHER=99999999-8888-4777-8666-555555555555
FRESH=33333333-4444-4555-8666-777777777777
PLUGIN_HOOKS="$REPO_ROOT/hooks/hooks.json"
ACTIVATE="\"$S/tower-session.sh\" activate"

# ts_run <args...> — the hook as the plugin runs it, the payload on stdin.
ts_run() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$UNIT" \
    PLANWRIGHT_FLEET_STATE_DIR="${TS_FLEET-$FLEET}" \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/adopter" PLANWRIGHT_REPO_ROOT="$UNIT" \
    PLANWRIGHT_LOCAL_CONFIG="$LOCAL_CFG" /bin/bash "$TS" "$@" 2>/dev/null
}

# decide <surface> <payload> — sets OUT, CODE, DECISION, REASON.
decide() {
  OUT=$(printf '%s' "$2" | ts_run guard "$1")
  CODE=$?
  set_decision
}

set_decision() {
  DECISION=defer
  REASON=''
  case $OUT in
    *[![:space:]]*)
      DECISION=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // "unparsed"' 2>/dev/null) || DECISION=unparsed
      REASON=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null) || REASON=''
      ;;
  esac
}

bash_payload() { # <sid> <command>
  jq -nc --arg s "$1" --arg c "$2" --arg w "$UNIT" '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$w}'
}
ts_bash() { decide bash "$(bash_payload "$1" "$2")"; }

prompt() { # <sid> <prompt text>
  jq -nc --arg s "$1" --arg p "$2" --arg w "$UNIT" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:$p, cwd:$w}' \
    | ts_run prompt-hook >"$SANDBOX/prompt.out"
  PCODE=$?
}

mark() { # <sid>
  mkdir -p "$STORE"
  chmod 700 "$FLEET" "$STORE"
  printf 'tower\t%s\tprompt\n' "$(date +%s)" >"$STORE/$1"
  chmod 600 "$STORE/$1"
}
reset_store() {
  chmod -R u+rwx "$FLEET" 2>/dev/null
  rm -rf "$FLEET"
  mark "$MARKED"
}
is_marked() { [ -f "$STORE/$1" ] && [ ! -L "$STORE/$1" ]; }

reset_store

echo "# an unmarked session is untouched, and its path forks nothing (REQ-C1.6)"
for cmd in 'git reset --hard HEAD' 'git push --force origin main' 'gh pr merge 1' 'ls'; do
  ts_bash "$OTHER" "$cmd"
  expect defer "unmarked session defers: $cmd"
done
STUBS="$SANDBOX/stubs"
FORKLOG="$SANDBOX/fork.log"
mkdir -p "$STUBS"
for t in jq cat id date mktemp mv find head ls rm mkdir sleep awk sed tr env git gh grep wc tail touch chmod stat; do
  printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s"\n' "$t" "$FORKLOG" >"$STUBS/$t"
  chmod +x "$STUBS/$t"
done
no_fork() { # <label> <payload> [fleet]
  : >"$FORKLOG"
  printf '%s' "$2" >"$SANDBOX/payload"
  OUT=$(PATH="$STUBS" PLANWRIGHT_FLEET_STATE_DIR="${3:-$FLEET}" /bin/bash "$TS" guard bash <"$SANDBOX/payload" 2>/dev/null)
  if [ -n "$OUT" ]; then
    fail "$1: the hook decided ($OUT)"
  elif [ -s "$FORKLOG" ]; then
    fail "$1: the hook ran an external command: $(head -3 "$FORKLOG")"
  else
    pass "$1: deferred with no external command"
  fi
}
no_fork "unmarked id, store present" "$(bash_payload "$OTHER" 'git reset --hard HEAD')"
no_fork "no store" "$(bash_payload "$MARKED" 'git reset --hard HEAD')" "$SANDBOX/no-fleet"
no_fork "no session id" '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
prefilter_body=$(awk '/^(prefilter|fleet_home|is_uuid|read_payload)\(\) \{/ { on = 1 } on { print } on && /^}/ { on = 0 }' "$REAL_SCRIPTS/tower-session.sh" | grep -v '^[[:space:]]*#')
if [ -z "$prefilter_body" ]; then
  fail "the prefilter functions were not found in tower-session.sh"
elif printf '%s\n' "$prefilter_body" | grep -Eq '\$\([^(]|`|<\(|>\(|(^|[^|])\|([^|]|$)|(^|[[:space:];&])\('; then
  fail "the prefilter holds a command substitution, pipeline, or subshell: $(printf '%s\n' "$prefilter_body" | grep -E '\$\([^(]|`|<\(|>\(|(^|[^|])\|([^|]|$)|(^|[[:space:];&])\(' | head -3)"
else
  pass "the prefilter holds no command substitution, pipeline, or subshell (static check)"
fi

echo "# marking from the prompt's start, bare or plugin-namespaced (REQ-C1.3)"
i=0
for p in '/tower' '/orchestrate tower-placement' '/planwright:tower what is open?' \
  '/planwright:orchestrate --watch' $'  \t/tower' $'\n/orchestrate'; do
  i=$((i + 1))
  sid=$(printf 'aaaaaaaa-0000-4000-8000-%012d' "$i")
  prompt "$sid" "$p"
  if is_marked "$sid" && [ ! -s "$SANDBOX/prompt.out" ] && [ "$PCODE" = 0 ]; then
    pass "a prompt opening with '$p' marks the session, silently"
  else
    fail "a prompt opening with '$p' did not mark the session (exit $PCODE)"
  fi
done
for p in 'please run /tower' 'see <command-name>/tower</command-name>' '/towers' '/tower-x' '/orchestrated' \
  'x /planwright:orchestrate'; do
  i=$((i + 1))
  sid=$(printf 'aaaaaaaa-0000-4000-8000-%012d' "$i")
  prompt "$sid" "$p"
  if is_marked "$sid"; then
    fail "the prompt '$p' marked the session"
  else
    pass "the prompt '$p' does not mark"
  fi
done

echo "# the activation handshake marks and is refused as ACTIVE (REQ-C1.3, REQ-B1.4)"
ts_bash "$FRESH" "$ACTIVATE"
expect deny "the handshake is refused in a wired session"
reason_has '^planwright tower-session: ACTIVE: ' "the refusal opens with the ACTIVE message"
if is_marked "$FRESH"; then pass "the handshake marked the session"; else fail "the handshake did not mark the session"; fi
for form in "$S/tower-session.sh activate" "'$S/tower-session.sh' activate" 'scripts/tower-session.sh activate'; do
  ts_bash "$OTHER" "$form"
  reason_has '^planwright tower-session: ACTIVE: ' "the handshake form is recognized: $form"
done
rm -f "$STORE/$OTHER"
ts_bash "$OTHER" "$ACTIVATE; touch $SANDBOX/ran"
expect defer "a command that only contains the handshake is not the handshake"
out=$(/bin/bash "$S/tower-session.sh" activate 2>/dev/null)
rc=$?
if [ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'NOT ACTIVE'; then
  pass "the handshake's own body, run where no hook stopped it, reports NOT ACTIVE and exits 3"
else
  fail "the handshake's body exited $rc: $out"
fi
mv "$S/policy-guard.sh" "$S/policy-guard.sh.off"
ts_bash "$FRESH" "$ACTIVATE"
reason_has 'NOT ACTIVE: the policy guard' "the handshake is NOT ACTIVE when the policy guard beside it is missing"
mv "$S/policy-guard.sh.off" "$S/policy-guard.sh"
chmod 770 "$STORE"
ts_bash "$FRESH" "$ACTIVATE"
reason_has 'NOT ACTIVE: this session could not be marked' "the handshake is NOT ACTIVE over a store that is not owner-only"
reset_store

echo "# a self-marked session gains no allow, and the plugin hooks carry no command guard (REQ-C1.2)"
any_allow=0
for cmd in 'tmux list-sessions' 'ls' 'git status' 'git log --oneline -3' "$S/policy-guard.sh" 'mktemp' 'jq -n 1'; do
  ts_bash "$MARKED" "$cmd"
  [ "$DECISION" != allow ] || any_allow=1
done
if [ "$any_allow" = 0 ]; then pass "a marked session's routine commands are never allowed by the plugin path"; else fail "the plugin path allowed a command in a marked session"; fi
if grep -q 'tower-command-guard' "$PLUGIN_HOOKS"; then
  fail "hooks/hooks.json wires tower-command-guard.sh"
else
  pass "tower-command-guard.sh is absent from the plugin hooks"
fi
if grep -Eq 'permissionDecision[\\":]*allow' "$REAL_SCRIPTS/tower-session.sh"; then
  fail "tower-session.sh can emit an allow"
else
  pass "tower-session.sh has no allow verdict to emit"
fi

echo "# fail closed in a marked session (REQ-C1.4)"
ts_bash "$MARKED" 'git reset --hard HEAD'
expect deny "a marked session's reserved act is refused"
ts_bash "$MARKED" "cat $STORE/$MARKED"
expect deny "a command naming the store is refused"
reason_has 'names the tower-sessions store' "the store refusal says why"
ts_bash "$MARKED" "rm -f ~/.claude/plugins/data/x/fleet/tower-sessions/$MARKED"
expect deny "a command naming the store by another path is refused"
printf 'garbage\n' >"$STORE/$MARKED"
ts_bash "$MARKED" 'ls'
expect deny "a corrupt mark denies"
reset_store
chmod 620 "$STORE/$MARKED"
ts_bash "$MARKED" 'ls'
expect deny "a group-writable mark denies"
chmod 602 "$STORE/$MARKED"
ts_bash "$MARKED" 'ls'
expect deny "a world-writable mark denies"
reset_store
printf 'tower\t1\tprompt\n' >"$SANDBOX/elsewhere"
chmod 600 "$SANDBOX/elsewhere"
rm -f "$STORE/$MARKED"
ln -s "$SANDBOX/elsewhere" "$STORE/$MARKED"
ts_bash "$MARKED" 'ls'
expect deny "a symlinked mark denies"
reset_store
mv "$STORE" "$SANDBOX/real-store"
ln -s "$SANDBOX/real-store" "$STORE"
ts_bash "$MARKED" 'ls'
expect deny "a symlinked store denies"
rm -f "$STORE"
mv "$SANDBOX/real-store" "$STORE"
mv "$FLEET" "$SANDBOX/real-fleet"
ln -s "$SANDBOX/real-fleet" "$FLEET"
ts_bash "$MARKED" 'ls'
expect deny "a symlinked fleet home denies"
rm -f "$FLEET"
mv "$SANDBOX/real-fleet" "$FLEET"
chmod 700 "$STORE"
chmod 770 "$FLEET"
ts_bash "$MARKED" 'ls'
expect deny "a group-writable fleet home denies"
reset_store
chmod 600 "$STORE"
ts_bash "$OTHER" 'ls'
expect deny "an unsearchable store counts as marked and denies"
reason_has 'cannot be searched' "the unsearchable-store refusal says why"
reset_store
rm -rf "$STORE"
: >"$STORE"
ts_bash "$OTHER" 'ls'
expect deny "a store that is not a directory counts as unsearchable and denies"
reset_store
TS_FLEET="$SANDBOX/absent-fleet" ts_bash "$MARKED" 'git reset --hard HEAD'
expect defer "a missing store defers"
decide bash '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
expect defer "a payload with no session id defers"
decide bash "$(jq -nc '{session_id:"not-a-uuid", tool_name:"Bash", tool_input:{command:"git reset --hard HEAD"}}')"
expect defer "a session id that is not a UUID defers"
decide bash "{\"session_id\":\"$MARKED\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":"
expect deny "an unparseable payload naming a marked session denies"
big=$SANDBOX/big
{
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"ls","pad":"' "$MARKED"
  head -c 2000100 /dev/zero | tr '\0' a
  printf '"}}'
} >"$big"
OUT=$(ts_run guard bash <"$big")
CODE=$?
set_decision
expect deny "an oversized payload in a marked session denies"
sed "s/$MARKED/$OTHER/" "$big" >"$big.other"
OUT=$(ts_run guard bash <"$big.other")
CODE=$?
set_decision
expect defer "an oversized payload in an unmarked session defers"

echo "# a signal at the pause point after the session is found marked denies (REQ-C1.4)"
set -m
for sig in TERM INT HUP; do
  rm -f "$SANDBOX/paused" "$SANDBOX/sig.out"
  bash_payload "$MARKED" 'ls' >"$SANDBOX/sig.payload"
  env -u CLAUDE_PLUGIN_DATA PATH="$BIN:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$FLEET" \
    PLANWRIGHT_TOWER_SESSION_TEST_PAUSE="$SANDBOX/paused" \
    /bin/bash "$TS" guard bash <"$SANDBOX/sig.payload" >"$SANDBOX/sig.out" 2>/dev/null &
  pid=$!
  n=0
  until [ -e "$SANDBOX/paused" ] || [ "$n" -ge 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -s "$sig" "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  OUT=$(cat "$SANDBOX/sig.out")
  CODE=0
  set_decision
  if [ -e "$SANDBOX/paused" ]; then
    expect deny "SIG$sig at the pause point denies"
  else
    fail "SIG$sig: the hook never reached the pause point"
  fi
done
set +m

echo "# the test pause point is bounded: unsignalled, the hook goes on to its verdict"
rm -f "$SANDBOX/paused" "$SANDBOX/sig.out"
bash_payload "$MARKED" 'git reset --hard HEAD' >"$SANDBOX/sig.payload"
env -u CLAUDE_PLUGIN_DATA PATH="$BIN:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$FLEET" \
  PLANWRIGHT_TOWER_SESSION_TEST_PAUSE="$SANDBOX/paused" \
  /bin/bash "$TS" guard bash <"$SANDBOX/sig.payload" >"$SANDBOX/sig.out" 2>/dev/null &
pid=$!
n=0
while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 300 ]; do
  sleep 0.1
  n=$((n + 1))
done
if kill -0 "$pid" 2>/dev/null; then
  kill -s KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  fail "the hook was still paused after 30s with no signal"
else
  wait "$pid"
  CODE=$?
  OUT=$(cat "$SANDBOX/sig.out")
  set_decision
  expect deny "an unsignalled pause ends in the guard's own verdict"
  reason_has 'git reset --hard' "the verdict after the pause is the guard's, not the internal one"
  [ -e "$SANDBOX/paused" ] || fail "the hook never reached the pause point"
fi

echo "# a crash after the session is found marked, or in the handshake, denies (REQ-C1.4)"
# Each copy dereferences an unset variable under set -u at one point.
crash_copy() { # <dest> <line after which the fault goes>
  awk -v at="$2" '{ print } $0 == at { print "  : \"$TOWER_SESSION_CRASH_PROBE\"" }' "$REAL_SCRIPTS/tower-session.sh" >"$1"
  if [ "$(grep -c 'TOWER_SESSION_CRASH_PROBE' "$1")" != 1 ]; then
    fail "the fault was not injected after: $2"
  fi
}
# The handshake is recognized by its path, so each copy keeps the name.
CRASH_GUARD="$SANDBOX/crash-guard/scripts/tower-session.sh"
CRASH_ACTIVATE="$SANDBOX/crash-activate/scripts/tower-session.sh"
mkdir -p "${CRASH_GUARD%/*}" "${CRASH_ACTIVATE%/*}"
crash_copy "$CRASH_GUARD" '  pause_for_test'
crash_copy "$CRASH_ACTIVATE" 'activate_session() { # <sid>'
TS=$CRASH_GUARD ts_bash "$MARKED" 'ls'
expect deny "a crash in a marked session's guard denies"
reason_has 'stopped before reaching a decision' "the crash refusal is the internal one"
TS=$CRASH_ACTIVATE ts_bash "$FRESH" "\"$CRASH_ACTIVATE\" activate"
expect deny "a crash in the activation handshake denies"
reason_has 'stopped before reaching a decision' "the handshake crash refusal is the internal one"
TS=$CRASH_GUARD ts_bash "$OTHER" 'ls'
expect defer "the fault never reached in an unmarked session leaves it deferring"
ts_bash "$MARKED" 'ls'
expect defer "a marked session's routine read still defers"
reset_store

echo "# the top-level session id only (REQ-C1.5)"
decide bash "$(jq -nc --arg s "$OTHER" --arg n "$MARKED" '{session_id:$s, tool_name:"Bash", tool_input:{command:"git reset --hard HEAD", session_id:$n}}')"
expect defer "a nested marked session_id under an unmarked top-level id defers"
decide bash "$(jq -nc --arg s "$MARKED" --arg n "$OTHER" '{tool_input:{session_id:$n, command:"git reset --hard HEAD"}, tool_name:"Bash", session_id:$s}')"
expect deny "a marked top-level id after a nested unmarked one is enforced"
decide bash "$(jq -nc --arg n "$MARKED" '{tool_name:"Bash", tool_input:{command:"git reset --hard HEAD", session_id:$n}}')"
expect defer "a nested marked id with no top-level id defers"
decide mcp "$(jq -nc --arg s "$MARKED" '{session_id:$s, tool_name:"mcp__github__update_pull_request_branch", tool_input:{pullNumber:1}}')"
expect deny "a marked session's GitHub MCP branch update is refused (REQ-C1.1)"
decide mcp "$(jq -nc --arg s "$OTHER" '{session_id:$s, tool_name:"mcp__github__update_pull_request_branch", tool_input:{pullNumber:1}}')"
expect defer "an unmarked session's GitHub MCP branch update defers"

echo "# hook timeouts exceed the guard's deadline plus margin, below the harness default (REQ-C1.5)"
deadline=$(sed -n 's/^readonly OVERALL_DEADLINE=\([0-9][0-9]*\)$/\1/p' "$REAL_SCRIPTS/policy-guard.sh")
margin=20
entries=$(jq -c '[.hooks[][] | .hooks[] | select(.command | test("tower-session\\.sh"))]' "$PLUGIN_HOOKS")
if [ -z "$deadline" ]; then
  fail "the policy guard's OVERALL_DEADLINE was not found"
elif [ "$(printf '%s' "$entries" | jq 'length')" != 3 ]; then
  fail "expected three tower-session.sh hook entries, found: $entries"
elif printf '%s' "$entries" | jq -e --argjson d "$deadline" --argjson m "$margin" \
  'all(.[]; (.timeout | type) == "number" and .timeout > ($d + $m) and .timeout < 600)' >/dev/null; then
  pass "every tower-session.sh hook entry carries a timeout over ${deadline}s + ${margin}s and under 600s"
else
  fail "a tower-session.sh hook entry's timeout is missing or out of range: $entries"
fi
for want in 'PreToolUse:Bash:guard bash' 'UserPromptSubmit::prompt-hook'; do
  ev=${want%%:*}
  rest=${want#*:}
  m=${rest%%:*}
  arg=${rest#*:}
  if jq -e --arg e "$ev" --arg m "$m" --arg a "$arg" \
    '.hooks[$e][] | select((.matcher // "") == $m) | .hooks[] | select(.command | endswith("tower-session.sh " + $a))' \
    "$PLUGIN_HOOKS" >/dev/null; then
    pass "hooks.json wires tower-session.sh $arg on $ev${m:+ ($m)}"
  else
    fail "hooks.json does not wire tower-session.sh $arg on $ev${m:+ ($m)}"
  fi
done
mcp_matcher=$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | endswith("tower-session.sh guard mcp")) | .matcher' "$PLUGIN_HOOKS")
for tool in $(jq -r '.permissions.deny[] | select(startswith("mcp__")) | sub("^mcp__[*]__"; "mcp__github__")' "$REPO_ROOT/config/tower-settings.json" | sort -u); do
  if [[ $tool =~ $mcp_matcher ]]; then
    pass "the MCP floor hook matches $tool"
  else
    fail "the MCP floor hook does not match $tool (matcher $mcp_matcher)"
  fi
done
for tool in mcp__github__pull_request_read mcp__github__create_pull_request_review mcp__github__list_pull_requests; do
  if [[ $tool =~ $mcp_matcher ]]; then
    fail "the MCP floor hook matches the read or review tool $tool"
  else
    pass "the MCP floor hook leaves $tool alone"
  fi
done

echo "# the store stays bounded: mark writes prune, handshakes refresh (REQ-C1.9)"
reset_store
OLD=44444444-5555-4666-8777-888888888888
mark "$OLD"
touch -t 200001010000 "$STORE/$OLD"
touch -t 200001010000 "$STORE/$MARKED"
printf 'outside\n' >"$SANDBOX/outside"
touch -t 200001010000 "$SANDBOX/outside"
ln -s "$SANDBOX/outside" "$STORE/55555555-6666-4777-8888-999999999999"
ts_bash "$MARKED" "$ACTIVATE"
reason_has '^planwright tower-session: ACTIVE: ' "the handshake over an aged store is ACTIVE"
if [ -e "$STORE/$OLD" ]; then fail "a mark older than the pruning age survived a mark write"; else pass "a mark write prunes a mark older than the pruning age"; fi
if [ -n "$(find "$STORE/$MARKED" -mtime -1 2>/dev/null)" ]; then
  pass "the handshake refreshed the session's own mark, which the prune kept"
else
  fail "the handshake did not refresh the session's own mark"
fi
if [ -f "$SANDBOX/outside" ]; then pass "the prune never follows a planted link"; else fail "the prune followed a planted link"; fi
mark "$OLD"
touch -t 200001010000 "$STORE/$OLD"
prompt "$FRESH" '/tower'
if [ -e "$STORE/$OLD" ]; then fail "the prompt hook's mark write did not prune"; else pass "the prompt hook's mark write prunes too"; fi
# shellcheck disable=SC2012 # the mode column is the point
mode=$(ls -ln "$STORE/$FRESH" | cut -c1-10)
# shellcheck disable=SC2012
dmode=$(ls -ldn "$STORE" | cut -c1-10)
if [ "$mode" = '-rw-------' ] && [ "$dmode" = 'drwx------' ]; then
  pass "marks and their store are owner-only"
else
  fail "marks or the store are not owner-only ($mode, $dmode)"
fi
if grep -nE '(>|tee|mv|cp)[^#]*tower-sessions' "$REPO_ROOT"/scripts/*.sh | grep -v '^[^:]*/tower-session\.sh:' >/dev/null; then
  fail "a script other than tower-session.sh writes into the tower-sessions store"
else
  pass "no script but the hook writes the tower-sessions store"
fi

echo "# the fleet home matches scripts/fleet-state.sh root on every arm"
parity() { # <label> <env assignments...>
  local label=$1 want got sid=66666666-7777-4888-8999-000000000000
  shift
  want=$(env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR "$@" /bin/sh "$REAL_SCRIPTS/fleet-state.sh" root 2>/dev/null) || want=''
  bash_payload "$sid" "$ACTIVATE" >"$SANDBOX/parity.payload"
  env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR PATH="$BIN:$PATH" "$@" \
    /bin/bash "$TS" guard bash <"$SANDBOX/parity.payload" >/dev/null 2>&1
  got=$(find "$SANDBOX/parity" -path "*/tower-sessions/$sid" -type f 2>/dev/null)
  got=${got%/tower-sessions/"$sid"}
  if [ "$got" = "$want" ]; then
    pass "fleet-home parity: $label (${want:-no home})"
  else
    fail "fleet-home parity: $label: fleet-state.sh root '$want', tower-session.sh '$got'"
  fi
  rm -rf "$SANDBOX/parity"
}
mkdir -p "$SANDBOX/parity"
parity 'explicit override' PLANWRIGHT_FLEET_STATE_DIR="$SANDBOX/parity/override"
mkdir -p "$SANDBOX/parity"
parity 'plugin data' CLAUDE_PLUGIN_DATA="$SANDBOX/parity/data/"
writer() { # <claude-dir> <manifest text>
  mkdir -p "$1/planwright"
  printf '%s\n' "$2" >"$1/planwright/plugin.json"
}
writer "$SANDBOX/parity/cd" '{
  "author": { "name": "someone-else" },
  "name": "planwright",
  "version": "1.0.0"
}'
parity 'writer mode, CLAUDE_DIR, nested name first' CLAUDE_DIR="$SANDBOX/parity/cd"
writer "$SANDBOX/parity/h/.claude" '{"name":"pw-dev","author":{"name":"x"}}'
parity 'writer mode, HOME' HOME="$SANDBOX/parity/h"
writer "$SANDBOX/parity/bad" '{"name":"Bad_Name"}'
parity 'writer mode, an invalid name' CLAUDE_DIR="$SANDBOX/parity/bad"
mkdir -p "$SANDBOX/parity/none"
parity 'no manifest' CLAUDE_DIR="$SANDBOX/parity/none"

no_gh_calls
finish
