#!/usr/bin/env bash
# tower-session.sh — the tower deny floor, enforced from the plugin's own
# hooks in every session marked as a tower, however it was launched.
#
# WHY. The tower profile (config/tower-settings.json) carries the deny list
# and wires the policy guard, but a settings profile loads only with
# `claude --settings <file>`. Plugin hooks load in every session, so this
# script, wired in hooks/hooks.json, runs scripts/policy-guard.sh at the tower
# tier in exactly the sessions marked as towers and defers everywhere else.
# The profile launch stays a second, additional layer; both only deny.
#
# Usage, as hooks/hooks.json wires it:
#   tower-session.sh guard bash    PreToolUse on Bash.
#   tower-session.sh guard mcp     PreToolUse on the GitHub MCP write tools.
#   tower-session.sh prompt-hook   UserPromptSubmit: mark the session when the
#                                  prompt opens with the /tower or /orchestrate
#                                  command, bare or plugin-namespaced.
# And as a tower's bring-up runs it, the activation handshake:
#   tower-session.sh activate      In a session where the guard hook is live,
#                                  the hook marks the session and refuses this
#                                  command with a reason opening with ACTIVE,
#                                  so its body never runs. If it runs, no hook
#                                  stopped it: it says so and exits 3.
#
# DENY-ONLY. A mark only restricts the session carrying it: this path denies
# or defers and never allows, and tower-command-guard.sh's auto-allows stay
# with the profile launch. So marking needs no trust.
#
# THE STORE. A mark is <fleet home>/tower-sessions/<session id>, the fleet
# home resolved as scripts/fleet-state.sh root resolves it (re-implemented in
# the shell so an unmarked session forks nothing; the tests hold the two in
# parity). It is distinct from the tower marker fleet-tower-marker.sh keeps,
# which is keyed per spec. Only these hook processes write marks, so a mark
# lands in the fleet home the guard reads. The store holds the sibling tower
# stores' bar: an owner-only directory and files, no symlink anywhere, the id
# validated as a UUID before it becomes a path, refresh by temp file and
# rename, and every write pruning marks not refreshed within PRUNE_DAYS with a
# find that never follows a link.
#
# FAIL CLOSED, WHERE A TOWER IS. An unmarked session defers after an in-shell
# prefilter that forks nothing: no store, no readable top-level session id,
# or no mark for it. A store that exists but cannot be searched counts as
# marked. In a marked session, and in the handshake, deny traps are installed
# at once, and an oversized or unreadable payload, a mark or store failing the
# bar, a command naming the store, a signal, this script crashing before a
# verdict, and a guard that crashes or answers with anything but a denial each
# deny.
#
# TEST HOOK. PLANWRIGHT_TOWER_SESSION_TEST_PAUSE names a file this script
# creates once the session is found marked, then waits to be signalled; the
# suite uses it to deliver a signal at that point. The environment a hook
# inherits is the launcher's, not the session's shell.
#
# HOOK DISCIPLINE. Every exit is 0 and a verdict is the JSON on stdout. Every
# reason is a constant of this file, never payload text. The prompt hook
# prints nothing on stdout, which on that event would reach the model.
#
# Bash 3.2 floor.
set -uf
unset CDPATH
LC_ALL=C
export LC_ALL

readonly MAX_PAYLOAD_BYTES=2000000
readonly MAX_PROMPT_BYTES=65536
readonly PRUNE_DAYS=30
readonly PREFIX='planwright tower-session: '
readonly STORE_LEAF=tower-sessions
readonly ACTIVE_PHRASE='ACTIVE: the tower deny floor is enforced for this session by the planwright plugin hooks'
# A top-level-or-nested "session_id" member with a UUID-shaped value; the
# slow path reads the top-level one with jq.
readonly RE_SID='"session_id"[[:space:]]*:[[:space:]]*"([0-9A-Fa-f-]{36})"'
# A brace, or a "name" member, in the plugin manifest.
readonly RE_MANIFEST_TOKEN='[{}]|"name"[ '$'\t'']*:[ '$'\t'']*"[^"]*"'
readonly RE_PROMPT='"prompt"[[:space:]]*:[[:space:]]*"([[:space:]]|\\[nrt])*/(planwright:)?(tower|orchestrate)([[:space:]"]|\\[nrt]|$)'

case ${BASH_SOURCE[0]} in
  */*) SD=${BASH_SOURCE[0]%/*} ;;
  *) SD=. ;;
esac

# --------------------------------------------------------------------------
# The fleet home, as scripts/fleet-state.sh resolve_root has it, in builtins.

# fleet_home — set FH, or return 1 when no arm is derivable.
fleet_home() {
  FH=''
  if [ -n "${PLANWRIGHT_FLEET_STATE_DIR:-}" ]; then
    FH=$PLANWRIGHT_FLEET_STATE_DIR
    return 0
  fi
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    FH="${CLAUDE_PLUGIN_DATA%/}/fleet"
    return 0
  fi
  local dir='' manifest line tok val='' depth=0
  if [ -n "${CLAUDE_DIR:-}" ]; then
    dir=$CLAUDE_DIR
  elif [ -n "${HOME:-}" ]; then
    dir="$HOME/.claude"
  fi
  [ -n "$dir" ] || return 1
  manifest="$dir/planwright/plugin.json"
  [ -r "$manifest" ] || return 1
  # The manifest's top-level "name", tracking brace depth line by line as
  # fleet-state.sh's awk does.
  while IFS= read -r line || [ -n "$line" ]; do
    while [[ $line =~ $RE_MANIFEST_TOKEN ]]; do
      tok=${BASH_REMATCH[0]}
      line=${line#*"$tok"}
      case $tok in
        '{') depth=$((depth + 1)) ;;
        '}') depth=$((depth - 1)) ;;
        *)
          if [ "$depth" = 1 ] && [ -z "$val" ]; then
            val=${tok#*:}
            val=${val#*\"}
            val=${val%%\"*}
          fi
          ;;
      esac
    done
  done <"$manifest"
  [ -n "$val" ] || return 1
  case $val in
    -*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#val}" -le 64 ] || return 1
  FH="${dir%/}/planwright/$val/fleet"
}

is_uuid() {
  [ "${#1}" -eq 36 ] || return 1
  case $1 in
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  local hex=${1//-/}
  [ "${#hex}" -eq 32 ] || return 1
  case $hex in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
}

# read_payload <cap> — PAYLOAD holds at most <cap>+1 bytes of stdin, read by
# the shell itself.
read_payload() {
  PAYLOAD=''
  IFS= read -r -d '' -n "$(($1 + 1))" PAYLOAD || :
}

# drain — consume what a bounded read left, so the harness's write never
# meets a closed pipe.
drain() {
  [ "${#PAYLOAD}" -le "$1" ] || cat >/dev/null 2>&1 || :
}

# --------------------------------------------------------------------------
# Verdicts.

# DECIDED is 1 once a verdict, a deny or a deliberate defer, is reached; the
# exit trap denies any exit before that.
DECIDED=0

emit_deny() { # <constant reason>
  DECIDED=1
  printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$PREFIX$1\"}}"
  exit 0
}

deny_internal() {
  emit_deny 'the tower floor stopped before reaching a decision in this tower session (an internal error or a signal), so this call could not be checked - refusing (fail closed). Retry; report a floor that keeps failing.'
}

deny_unless_decided() {
  [ "$DECIDED" = 1 ] || deny_internal
}

deny_inactive() { # <constant cause>
  emit_deny "NOT ACTIVE: $1, so the tower deny floor is not enforced from the plugin for this session. Treat the floor as missing until a handshake is refused as ACTIVE."
}

warn() {
  printf '%s\n' "$PREFIX$1" >&2
}

# --------------------------------------------------------------------------
# The store's bar: the private-surface checks tower-reply-hook.sh keeps,
# returning 1 instead of repairing anything.

MY_UID=''
ls_fields() { # <ls flags> <path> — set LS_MODE and LS_UID from ls -n
  local l
  # shellcheck disable=SC2012
  l=$(ls "$1" -- "$2" 2>/dev/null) || l=''
  # shellcheck disable=SC2086
  set -- $l
  LS_MODE=${1:-}
  LS_UID=${3:-}
}

check_home() {
  [ ! -L "$FH" ] || return 1
  ls_fields -ldn "$FH"
  case $LS_MODE in
    d????-??-? | d????-??-?[@.]*) ;;
    *) return 1 ;;
  esac
  [ "$LS_UID" = "$MY_UID" ]
}

check_store() {
  [ ! -L "$STORE" ] || return 1
  ls_fields -ldn "$STORE"
  case $LS_MODE in
    d???--[-S]--[-T] | d???--[-S]--[-T][@.]*) ;;
    *) return 1 ;;
  esac
  [ "$LS_UID" = "$MY_UID" ]
}

check_mark() { # <path>
  local content tab=$'\t'
  [ ! -L "$1" ] && [ -f "$1" ] || return 1
  ls_fields -ln "$1"
  case $LS_MODE in
    -???------ | -???------[@.]*) ;;
    *) return 1 ;;
  esac
  [ "$LS_UID" = "$MY_UID" ] || return 1
  content=$(head -c 129 -- "$1" 2>/dev/null) || return 1
  [ "${#content}" -le 128 ] || return 1
  [[ $content =~ ^tower"$tab"[0-9]{1,12}"$tab"(prompt|activate)$ ]]
}

# write_mark <sid> <source> — create or refresh the mark by temp file and
# rename, then prune; 0 only when the mark passes the bar afterwards.
write_mark() {
  local tmp now
  MY_UID=$(id -u 2>/dev/null) || return 1
  umask 077
  if [ ! -e "$FH" ] && [ ! -L "$FH" ]; then
    mkdir -p -- "$FH" 2>/dev/null || return 1
  fi
  check_home || return 1
  if [ ! -e "$STORE" ] && [ ! -L "$STORE" ]; then
    # not-a-lock: a peer winning the create is success
    mkdir -- "$STORE" 2>/dev/null || [ -d "$STORE" ] || return 1
  fi
  check_store || return 1
  now=$(date +%s 2>/dev/null) || return 1
  tmp=$(mktemp "$STORE/.$1.XXXXXX" 2>/dev/null) || return 1
  if ! printf 'tower\t%s\t%s\n' "$now" "$2" >"$tmp" 2>/dev/null || ! mv -f -- "$tmp" "$STORE/$1" 2>/dev/null; then
    rm -f -- "$tmp" 2>/dev/null
    return 1
  fi
  find "$STORE" -mindepth 1 -maxdepth 1 -type f -mtime +$((PRUNE_DAYS - 1)) -exec rm -f -- {} + 2>/dev/null || :
  check_mark "$STORE/$1"
}

# --------------------------------------------------------------------------
# The PreToolUse guard.

# The prefilter: builtins only, no command substitution, pipeline, or
# subshell, so an unmarked session forks nothing before it defers. It sets
# PF to `defer` or `check`, and CAND to 1 when some session id in the payload
# is marked, or the store cannot be searched, which puts the session in the
# fail-closed set before its payload is parsed.
prefilter() {
  local rest id
  PF=defer
  CAND=0
  [ -n "$PAYLOAD" ] || return 0
  fleet_home || return 0
  STORE="$FH/$STORE_LEAF"
  case $PAYLOAD in
    *tower-session.sh*activate*) PF=check ;;
  esac
  [ -e "$STORE" ] || [ -L "$STORE" ] || return 0
  [[ $PAYLOAD =~ $RE_SID ]] || return 0
  if [ ! -d "$STORE" ] || [ ! -x "$STORE" ]; then
    PF=check
    CAND=1
    return 0
  fi
  rest=$PAYLOAD
  while [[ $rest =~ $RE_SID ]]; do
    id=${BASH_REMATCH[1]}
    if is_uuid "$id" && { [ -e "$STORE/$id" ] || [ -L "$STORE/$id" ]; }; then
      PF=check
      CAND=1
      return 0
    fi
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
}

# is_activation <command> — the activation handshake: a path ending in
# scripts/tower-session.sh, quoted or not, then `activate`, and nothing else.
is_activation() {
  local p re
  p='([^'"'"'"[:space:]$`\\;&|<>()]*/)?scripts/tower-session\.sh'
  re="^[[:space:]]*($p|'$p'|\"$p\")[[:space:]]+activate[[:space:]]*\$"
  [[ $1 =~ $re ]]
}

is_deny() { # <json>
  case $1 in
    *'"permissionDecision":"deny"'* | *'"permissionDecision": "deny"'*) return 0 ;;
  esac
  return 1
}

self_test() {
  local out
  [ -x "$SD/policy-guard.sh" ] || return 1
  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git update-ref refs/heads/main HEAD"},"cwd":"/"}' \
    | "$SD/policy-guard.sh" tower bash 2>/dev/null) || return 1
  is_deny "$out"
}

pause_for_test() {
  [ -n "${PLANWRIGHT_TOWER_SESSION_TEST_PAUSE:-}" ] || return 0
  : >"$PLANWRIGHT_TOWER_SESSION_TEST_PAUSE" 2>/dev/null || return 0
  while :; do
    sleep 5 &
    wait $! 2>/dev/null
  done
}

activate_session() { # <sid>
  write_mark "$1" activate || deny_inactive 'this session could not be marked (the fleet home or its tower-sessions store is missing, unwritable, a symlink, or not owner-only)'
  self_test || deny_inactive 'the policy guard beside this hook did not refuse its self-test'
  emit_deny "$ACTIVE_PHRASE. This command is the activation handshake and never runs here; every Bash call and the GitHub MCP write tools run the policy guard at the tower tier."
}

guard() {
  local surface=$1 fields sid rest cmd out rc=0
  case $surface in bash | mcp) ;; *) exit 0 ;; esac
  read_payload "$MAX_PAYLOAD_BYTES"
  prefilter
  drain "$MAX_PAYLOAD_BYTES"
  [ "$PF" = check ] || exit 0
  if [ "${#PAYLOAD}" -gt "$MAX_PAYLOAD_BYTES" ]; then
    [ "$CAND" = 0 ] || emit_deny 'this tower session sent a payload larger than the floor reads - refusing (fail closed). Issue the command on its own.'
    exit 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    [ "$CAND" = 0 ] || emit_deny 'jq is not on PATH, so this tower session'"'"'s payload cannot be read - refusing (fail closed). Install jq.'
    exit 0
  fi
  fields=$(printf '%s' "$PAYLOAD" | jq -j '
    def s: if type == "string" then gsub("[\u0000\n]"; " ") else "" end;
    if type != "object" then error("not an object") else
      (.session_id | s) + "\n" +
      (if (.tool_input | type) == "object" and (.tool_input.command | type) == "string"
       then .tool_input.command | gsub("\u0000"; "") else "" end)
    end' 2>/dev/null) || rc=$?
  if [ "$rc" != 0 ]; then
    [ "$CAND" = 0 ] || emit_deny 'this tower session sent a payload the floor cannot parse - refusing (fail closed). This is a hook-contract violation; report it.'
    exit 0
  fi
  sid=${fields%%$'\n'*}
  cmd=${fields#*$'\n'}
  # Only the top-level id counts: a nested one marks nothing.
  is_uuid "$sid" || exit 0
  if [ "$surface" = bash ] && is_activation "$cmd"; then
    trap 'deny_internal' HUP INT TERM
    trap 'deny_unless_decided' EXIT
    activate_session "$sid"
  fi
  [ "$CAND" = 1 ] || exit 0
  if [ -d "$STORE" ] && [ -x "$STORE" ]; then
    [ -e "$STORE/$sid" ] || [ -L "$STORE/$sid" ] || exit 0
  fi
  trap 'deny_internal' HUP INT TERM
  trap 'deny_unless_decided' EXIT
  pause_for_test
  [ -d "$STORE" ] && [ -x "$STORE" ] \
    || emit_deny 'the tower-sessions store exists but cannot be searched, so this session counts as a tower - refusing (fail closed). Repair the store under the fleet home (an owner-only directory).'
  MY_UID=$(id -u 2>/dev/null) || deny_internal
  { check_home && check_store && check_mark "$STORE/$sid"; } \
    || emit_deny 'this session'"'"'s tower mark, its store, or the fleet home fails the store'"'"'s safety bar (a symlink, a corrupt mark, or a surface that is not owner-only) - refusing (fail closed). Repair the store, then re-run the activation handshake.'
  case $cmd in
    *"$STORE_LEAF"*)
      emit_deny 'this command names the tower-sessions store, which a tower session never touches - refusing.'
      ;;
  esac
  [ -x "$SD/policy-guard.sh" ] \
    || emit_deny 'the policy guard is missing beside this hook, so this tower call could not be checked - refusing (fail closed). Reinstall planwright.'
  out=$(printf '%s' "$PAYLOAD" | "$SD/policy-guard.sh" tower "$surface" 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] || deny_internal
  if [ -n "$out" ]; then
    is_deny "$out" || deny_internal
    printf '%s\n' "$out"
  fi
  DECIDED=1
  exit 0
}

# --------------------------------------------------------------------------
# The prompt hook.

prompt_hook() {
  local fields sid prompt re
  trap 'exit 0' HUP INT TERM PIPE
  read_payload "$MAX_PROMPT_BYTES"
  drain "$MAX_PROMPT_BYTES"
  [[ $PAYLOAD =~ $RE_PROMPT ]] || exit 0
  [[ $PAYLOAD =~ $RE_SID ]] || exit 0
  fleet_home || exit 0
  STORE="$FH/$STORE_LEAF"
  command -v jq >/dev/null 2>&1 || exit 0
  fields=$(printf '%s' "$PAYLOAD" | jq -j '
    def s: if type == "string" then gsub("[\u0000\n]"; " ") else "" end;
    (.session_id | s) + "\n" + (.prompt | s)' 2>/dev/null) || exit 0
  sid=${fields%%$'\n'*}
  prompt=${fields#*$'\n'}
  is_uuid "$sid" || exit 0
  re='^[[:space:]]*/(planwright:)?(tower|orchestrate)([[:space:]]|$)'
  [[ $prompt =~ $re ]] || exit 0
  write_mark "$sid" prompt || warn 'this tower session could not be marked; its bring-up handshake reports the floor as not active'
  exit 0
}

case ${1:-} in
  guard) guard "${2:-}" ;;
  prompt-hook) prompt_hook ;;
  activate)
    printf '%s\n' "${PREFIX}NOT ACTIVE: this command ran, so no planwright hook intercepted it and the tower deny floor is not enforced from the plugin for this session."
    exit 3
    ;;
  *)
    printf '%s\n' 'usage: tower-session.sh guard bash|mcp | prompt-hook | activate' >&2
    exit 2
    ;;
esac
