#!/usr/bin/env bash
# mc-approve-hook.sh — the plugin hook that approves mission control's own
# prompt-answer calls, wired in hooks/hooks.json on PreToolUse Bash.
#
# WHY. Approvals for `fleet-streamjson.sh pending|answer` used to rest on
# user-scope allow rules naming one plugin version's install path, so every
# release broke them. This hook, shipped with the plugin, approves the same
# calls from the root it runs from, in a mission-control session only.
#
# The session test is the mission-control mark scripts/tower-session.sh's
# prompt hook writes, a sibling of a tower mark named for the session id plus
# .mission-control, under the tower store's bar; this file sources tower-session.sh for the
# store functions. Allow-only: every other session, shape or failure prints
# nothing, so the harness decides as it would without this hook. The hook
# judges the call's shape only; what authorizes an answer (a standing
# decision claimed through the answer channel, or the operator's own answer)
# is unchanged and is not checked here. A settings deny or ask rule is the
# harness's to apply and this hook never prints either.
#
# Bash 3.2 floor.
set -uf
unset CDPATH
LC_ALL=C
export LC_ALL
case ${BASH_SOURCE[0]} in
  */*) SD=${BASH_SOURCE[0]%/*} ;;
  *) SD=. ;;
esac
# shellcheck source=scripts/tower-session.sh
. "$SD/tower-session.sh" || exit 0

# approve — PreToolUse on Bash. In a session the prompt hook marked as mission
# control, approve exactly the literal physical path of this install's
# scripts/fleet-streamjson.sh with `pending` or `answer`, as one simple
# command. Allow-only: every other shape, every other session and every
# failure defers (prints nothing), so the harness decides as it would without
# this hook. The call's shape is all it judges; what authorizes an answer
# stays with the answer channel.
approve() {
  local fields sid cmd root script verb args id rest re
  trap 'exit 0' HUP INT TERM PIPE
  read_payload "$MAX_PAYLOAD_BYTES"
  drain "$MAX_PAYLOAD_BYTES"
  [ "${#PAYLOAD}" -le "$MAX_PAYLOAD_BYTES" ] || exit 0
  # Cheap exits first, builtins only: no call naming the script, no store.
  case $PAYLOAD in *fleet-streamjson.sh*) ;; *) exit 0 ;; esac
  fleet_home || exit 0
  STORE="$FH/$STORE_LEAF"
  [ -d "$STORE" ] && [ ! -L "$STORE" ] || exit 0
  [[ $PAYLOAD =~ $RE_SID ]] || exit 0
  id=''
  rest=$PAYLOAD
  while [[ $rest =~ $RE_SID ]]; do
    if is_uuid "${BASH_REMATCH[1]}" && [ -f "$STORE/${BASH_REMATCH[1]}.mission-control" ]; then
      id=${BASH_REMATCH[1]}
      break
    fi
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
  [ -n "$id" ] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  fields=$(printf '%s' "$PAYLOAD" | jq -j '
    def s: if type == "string" then gsub("[\u0000\n]"; " ") else "" end;
    if type != "object" or .tool_name != "Bash" then error("not a Bash call") else
      (.session_id | s) + "\n" +
      (if (.tool_input | type) == "object" and (.tool_input.command | type) == "string"
       then .tool_input.command else "" end)
    end' 2>/dev/null) || exit 0
  sid=${fields%%$'\n'*}
  cmd=${fields#*$'\n'}
  # Only the top-level id counts: a nested one marks nothing.
  [ "$sid" = "$id" ] || exit 0
  MY_UID=$(id -u 2>/dev/null) || exit 0
  { check_home && check_store && check_mark "$STORE/$sid.mission-control" mission-control; } || exit 0
  root=$(cd -P -- "$SD/.." 2>/dev/null && pwd -P) || exit 0
  [ -n "$root" ] && [ "${root#/}" != "$root" ] || exit 0
  script="$root/scripts/fleet-streamjson.sh"
  [ -f "$script" ] && [ ! -L "$script" ] || exit 0
  [ ! -L "$root/scripts" ] || exit 0
  [ "$(cd -P -- "$root/scripts" 2>/dev/null && pwd -P)" = "$root/scripts" ] || exit 0
  # One simple command: the literal path, one space, the verb, then plain
  # words of a safe alphabet, single-spaced. A newline, quote, backslash,
  # expansion, separator, redirection or background marker is outside it.
  case $cmd in
    "$script pending" | "$script pending "* | "$script answer "*) ;;
    *) exit 0 ;;
  esac
  verb=${cmd#"$script "}
  args=${verb#pending}
  [ "$args" != "$verb" ] || args=${verb#answer}
  re='^( [A-Za-z0-9_./:=@,+-]+)*$'
  [[ $args =~ $re ]] || exit 0
  DECIDED=1
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"planwright tower-session: the exact installed fleet-streamjson.sh pending or answer call, from a mission-control session; the call'"'"'s shape only, an answer still needs its standing decision or the operator'"'"'s own answer."}}'
  exit 0
}

approve
