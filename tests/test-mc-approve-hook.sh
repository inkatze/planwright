#!/bin/bash
# Tests for the plugin hook that approves mission control's prompt-answer
# calls (mission-control REQ-G1.6, D-35): scripts/mc-approve-hook.sh and
# the mission-control mark the prompt hook writes. The hook approves one exact
# shape in a marked session and defers on everything else; what authorizes an
# answer is the answer channel's, tests/test-mc-stall.sh's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required" >&2
  exit 1
}

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/mc-approve.XXXXXX") || exit 1
SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT

ROOT="$SANDBOX/cache/planwright/0.71.0"
OTHER_ROOT="$SANDBOX/cache/planwright/0.70.0"
for r in "$ROOT" "$OTHER_ROOT"; do
  mkdir -p "$r/scripts"
  cp "$repo_root/scripts/tower-session.sh" "$repo_root/scripts/mc-approve-hook.sh" "$r/scripts/"
  printf '#!/bin/sh\nexit 0\n' >"$r/scripts/fleet-streamjson.sh"
  chmod +x "$r/scripts/fleet-streamjson.sh"
done
FLEET="$SANDBOX/fleet"
STORE="$FLEET/tower-sessions"
MC=11111111-2222-4333-8444-555555555555
TOWER=22222222-3333-4444-8555-666666666666
NONE=99999999-8888-4777-8666-555555555555
SJ="$ROOT/scripts/fleet-streamjson.sh"

hook() { # <root> <verb> [arg] — payload on stdin; verb approve runs the approval hook
  local script=tower-session.sh
  [ "$2" != approve ] || script=mc-approve-hook.sh
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR PLANWRIGHT_FLEET_STATE_DIR="$FLEET" \
    /bin/bash "$1/scripts/$script" "${@:2}" 2>/dev/null
}
bash_payload() { # <sid> <command>
  jq -nc --arg s "$1" --arg c "$2" '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:"/"}'
}
mark_kind() { # <sid> <suffix> <kind>
  mkdir -p "$STORE"
  chmod 700 "$FLEET" "$STORE"
  printf '%s\t%s\tprompt\n' "$3" "$(date +%s)" >"$STORE/$1$2"
  chmod 600 "$STORE/$1$2"
}
reset_store() {
  chmod -R u+rwx "$FLEET" 2>/dev/null
  rm -rf "$FLEET"
  mark_kind "$MC" .mission-control mission-control
  mark_kind "$TOWER" '' tower
}

# approves <label> <command> [sid] [root]
approves() {
  local out
  out=$(bash_payload "${3:-$MC}" "$2" | hook "${4:-$ROOT}" approve)
  if [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = allow ]; then
    ok "approves: $1"
  else
    fail "did not approve: $1 (output: $out)"
  fi
}
# defers <label> <command> [sid] [root]
defers() {
  local out
  out=$(bash_payload "${3:-$MC}" "$2" | hook "${4:-$ROOT}" approve)
  if [ -z "$out" ]; then
    ok "defers: $1"
  else
    fail "did not defer: $1 (output: $out)"
  fi
}

reset_store

echo "# the exact shape is approved in a mission-control session"
approves "pending, bare" "$SJ pending"
approves "pending with a worker" "$SJ pending worker-1"
approves "answer with allow" "$SJ answer worker-1 req-9 --allow"
approves "answer with deny" "$SJ answer worker-1 req-9 --deny"
approves "answer with a response file" "$SJ answer worker-1 req-9 --response-file $SANDBOX/resp.json"

echo "# the approval carries a reason and never a deny or ask"
out=$(bash_payload "$MC" "$SJ pending" | hook "$ROOT" approve)
if printf '%s' "$out" | jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "allow" and (.permissionDecisionReason | length > 0)' >/dev/null 2>&1; then
  ok "the verdict is a PreToolUse allow with a reason"
else
  fail "unexpected verdict: $out"
fi

echo "# every other verb defers"
for v in launch steer recover status alarm-scan 'pendingx' 'answerx w r' answer; do
  defers "verb '$v'" "$SJ $v"
done
defers "answer with no arguments" "$SJ answer"
defers "the script alone" "$SJ"

echo "# every other shape defers"
defers "an expansion in an argument" "$SJ pending \$(id)"
defers "a variable in an argument" "$SJ pending \$HOME"
defers "backticks" "$SJ pending \`id\`"
defers "a compound with &&" "$SJ pending && id"
defers "a compound with ;" "$SJ pending; id"
defers "a compound with ||" "$SJ pending || id"
defers "a pipe" "$SJ pending | cat"
defers "an output redirect" "$SJ pending > $SANDBOX/out"
defers "an input redirect" "$SJ answer w r --response-file x < $SANDBOX/in"
defers "a stderr redirect" "$SJ pending 2>&1"
defers "a background marker" "$SJ pending &"
defers "a newline compound" "$SJ pending
id"
defers "a quoted argument" "$SJ answer w r --deny --message 'no thanks'"
defers "a double-quoted argument" "$SJ answer w r --deny --message \"no\""
defers "a backslash" "$SJ answer w r --deny --message a\\ b"
defers "a glob" "$SJ pending *"
defers "a brace expansion" "$SJ pending {a,b}"
defers "a double space" "$SJ pending  w"
defers "a trailing space" "$SJ pending w "
defers "a leading command prefix" "env $SJ pending"
defers "a leading variable assignment" "X=1 $SJ pending"
defers "a leading space" " $SJ pending"
defers "a subshell" "($SJ pending)"
defers "a group" "{ $SJ pending; }"
defers "bash -c" "bash -c '$SJ pending'"
defers "sh running the script" "sh $SJ pending"
defers "a tab separator" "$SJ	pending"

echo "# only the literal installed root's path"
defers "a relative path" "scripts/fleet-streamjson.sh pending"
defers "a dot-relative path" "./scripts/fleet-streamjson.sh pending"
defers "a variable root" '${CLAUDE_PLUGIN_ROOT}/scripts/fleet-streamjson.sh pending'
defers "a quoted variable root" '"${CLAUDE_PLUGIN_ROOT}"/scripts/fleet-streamjson.sh pending'
# shellcheck disable=SC2088 # the literal tilde is the input under test
defers "a tilde path" "~/scripts/fleet-streamjson.sh pending"
defers "a dot-dot path to the same file" "$ROOT/scripts/../scripts/fleet-streamjson.sh pending"
defers "a quoted literal path" "'$SJ' pending"
defers "another version's path" "$OTHER_ROOT/scripts/fleet-streamjson.sh pending"
defers "another version's path run by this root's hook" "$OTHER_ROOT/scripts/fleet-streamjson.sh answer w r --allow"
defers "a different script in this root" "$ROOT/scripts/fleet-attention.sh pending"
defers "a prefix-sharing path" "$ROOT/scripts/fleet-streamjson.sh.bak pending"

echo "# a link out of the root defers"
ln -s "$SANDBOX/cache/planwright/0.71.0" "$SANDBOX/alias"
defers "the root named through a symlink" "$SANDBOX/alias/scripts/fleet-streamjson.sh pending"
LROOT="$SANDBOX/linked/root"
mkdir -p "$LROOT/scripts" "$SANDBOX/elsewhere"
cp "$repo_root/scripts/tower-session.sh" "$repo_root/scripts/mc-approve-hook.sh" "$LROOT/scripts/"
printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/elsewhere/fleet-streamjson.sh"
chmod +x "$SANDBOX/elsewhere/fleet-streamjson.sh"
ln -s "$SANDBOX/elsewhere/fleet-streamjson.sh" "$LROOT/scripts/fleet-streamjson.sh"
defers "the script a symlink to elsewhere" "$LROOT/scripts/fleet-streamjson.sh pending" "$MC" "$LROOT"
SROOT="$SANDBOX/linkedscripts/root"
mkdir -p "$SROOT" "$SANDBOX/realscripts"
cp "$repo_root/scripts/tower-session.sh" "$repo_root/scripts/mc-approve-hook.sh" "$SANDBOX/realscripts/"
printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/realscripts/fleet-streamjson.sh"
chmod +x "$SANDBOX/realscripts/fleet-streamjson.sh"
ln -s "$SANDBOX/realscripts" "$SROOT/scripts"
defers "the scripts directory a symlink to elsewhere" "$SROOT/scripts/fleet-streamjson.sh pending" "$MC" "$SROOT"

echo "# only a mission-control session"
defers "an unmarked session" "$SJ pending" "$NONE"
defers "a tower-marked session" "$SJ pending" "$TOWER"
noid=$(jq -nc --arg c "$SJ pending" '{tool_name:"Bash", tool_input:{command:$c}}')
if [ -z "$(printf '%s' "$noid" | hook "$ROOT" approve)" ]; then
  ok "defers: a payload with no session id"
else
  fail "approved a payload with no session id"
fi
nested=$(jq -nc --arg s "$MC" --arg c "$SJ pending" '{session_id:"", tool_name:"Bash", tool_input:{command:$c}, meta:{session_id:$s}}')
if [ -z "$(printf '%s' "$nested" | hook "$ROOT" approve)" ]; then
  ok "defers: a nested session id marks nothing"
else
  fail "approved on a nested session id"
fi
nonbash=$(jq -nc --arg s "$MC" --arg c "$SJ pending" '{session_id:$s, tool_name:"Read", tool_input:{command:$c}}')
if [ -z "$(printf '%s' "$nonbash" | hook "$ROOT" approve)" ]; then
  ok "defers: a non-Bash tool"
else
  fail "approved a non-Bash tool"
fi
if [ -z "$(printf '%s' 'not json fleet-streamjson.sh' | hook "$ROOT" approve)" ] && [ -z "$(printf '' | hook "$ROOT" approve)" ]; then
  ok "defers: unparseable and empty payloads"
else
  fail "approved an unparseable or empty payload"
fi

echo "# a mark failing the store's bar defers"
reset_store
chmod 644 "$STORE/$MC.mission-control"
defers "a group-readable mark" "$SJ pending"
reset_store
printf 'tower\t1\tprompt\n' >"$STORE/$MC.mission-control"
chmod 600 "$STORE/$MC.mission-control"
defers "a mark of the wrong kind" "$SJ pending"
reset_store
rm "$STORE/$MC.mission-control"
printf 'mission-control\t1\tprompt\n' >"$SANDBOX/real-mark"
chmod 600 "$SANDBOX/real-mark"
ln -s "$SANDBOX/real-mark" "$STORE/$MC.mission-control"
defers "a symlinked mark" "$SJ pending"
reset_store
chmod 755 "$STORE"
defers "a store that is not owner-only" "$SJ pending"
reset_store
no_store_out=$(bash_payload "$MC" "$SJ pending" | PLANWRIGHT_FLEET_STATE_DIR="$SANDBOX/absent" /bin/bash "$ROOT/scripts/mc-approve-hook.sh" 2>/dev/null)
if [ -z "$no_store_out" ]; then ok "defers: no store"; else fail "approved with no store"; fi

echo "# the mission-control mark does not make the tower guard fire"
out=$(bash_payload "$MC" 'git reset --hard HEAD' | hook "$ROOT" guard bash)
if [ -z "$out" ]; then ok "the tower guard defers for a mission-control-only mark"; else fail "the tower guard acted on a mission-control mark: $out"; fi

echo "# the prompt hook writes the mission-control mark"
reset_store
prompt() { # <sid> <text>
  jq -nc --arg s "$1" --arg p "$2" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:$p, cwd:"/"}' | hook "$ROOT" prompt-hook
}
i=0
for p in '/mission-control planwright' '/planwright:mission-control' '  /mission-control'; do
  i=$((i + 1))
  sid=$(printf 'bbbbbbbb-0000-4000-8000-%012d' "$i")
  prompt "$sid" "$p" >"$SANDBOX/prompt.out"
  if [ -f "$STORE/$sid.mission-control" ] && [ ! -e "$STORE/$sid" ] && [ ! -s "$SANDBOX/prompt.out" ] \
    && [ "$(stat -c %a "$STORE/$sid.mission-control" 2>/dev/null || stat -f %Lp "$STORE/$sid.mission-control")" = 600 ] \
    && head -1 "$STORE/$sid.mission-control" | grep -Eq '^mission-control	[0-9]+	prompt$'; then
    ok "'$p' writes an owner-only mission-control mark, silently, and no tower mark"
  else
    fail "'$p' did not write exactly the mission-control mark"
  fi
  approves "after '$p'" "$SJ pending" "$sid"
done
for p in 'please run /mission-control' '/mission-controller' '/mission-control-x' 'x /planwright:mission-control' '/missioncontrol'; do
  i=$((i + 1))
  sid=$(printf 'bbbbbbbb-0000-4000-8000-%012d' "$i")
  prompt "$sid" "$p" >/dev/null
  if [ -e "$STORE/$sid.mission-control" ] || [ -e "$STORE/$sid" ]; then
    fail "'$p' marked the session"
  else
    ok "'$p' does not mark"
  fi
done
prompt "ccccccccc-bad" '/mission-control' >/dev/null
stray=0
for f in "$STORE"/*; do
  case ${f##*/} in bbbbbbbb-* | "$MC"* | "$TOWER"*) ;; *) stray=1 ;; esac
done
if [ "$stray" = 0 ]; then ok "a non-UUID session id writes nothing"; else fail "a non-UUID id wrote a mark"; fi
sid=dddddddd-0000-4000-8000-000000000001
prompt "$sid" '/tower' >/dev/null
if [ -f "$STORE/$sid" ] && [ ! -e "$STORE/$sid.mission-control" ] && head -1 "$STORE/$sid" | grep -q '^tower'; then
  ok "/tower still writes the tower mark alone"
else
  fail "/tower no longer writes only the tower mark"
fi

echo "# wiring"
n=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | endswith("mc-approve-hook.sh"))] | length' "$repo_root/hooks/hooks.json")
if [ "$n" = 1 ] \
  && jq -e '[.hooks[][] | .hooks[] | select(.command | test("mc-approve-hook\\.sh$"))] | length == 1' "$repo_root/hooks/hooks.json" >/dev/null \
  && jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | endswith("mc-approve-hook.sh")) | (.timeout | type) == "number" and .timeout > 0 and .timeout < 90' "$repo_root/hooks/hooks.json" >/dev/null; then
  ok "hooks.json wires mc-approve-hook.sh once, on PreToolUse Bash, with a numeric timeout under the guard's"
else
  fail "hooks.json does not wire mc-approve-hook.sh exactly once on PreToolUse Bash with a numeric timeout under the guard's"
fi
if ! grep -v '^[[:space:]]*#' "$repo_root/config/mission-control-verbs.txt" | grep -q 'fleet-streamjson.sh answer'; then
  ok "the guard tier's verb list still excludes the raw answer verb"
else
  fail "config/mission-control-verbs.txt lists the raw answer verb"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed" >&2
  exit 1
fi
