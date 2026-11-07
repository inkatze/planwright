#!/bin/sh
# retask-guard.sh — refuse handing a live repository-changing session a new
# unit of work. Workers are short-lived: new scope, and each new round of
# review feedback, goes to a fresh session carrying a handover brief, never
# into a running one. `--help` prints the contract.
#
# POSIX sh; no eval; message text is data, read only by awk and grep -F.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=retask-guard
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$me: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

OVERRIDE_TAG='[planwright retask-override:'

help_text() {
  cat <<'EOF'
usage:
  retask-guard.sh check <message-file>
  retask-guard.sh log --via <steer|relay|send-message> --to <session>
      --reason <text> [--now <epoch>]
  retask-guard.sh hook

check reads a message bound for a live session and refuses one shaped like
a new unit of work: one carrying a launch brief's marker line
(`<!-- mission-control launch:`), the standing-rules block a launch
delivers (`<!-- mc-rules begin`), a launch's `## Verification cadence`
heading, or one whose first non-blank line is a skill command (`/<name>`,
alone or before a space), which starts a unit. A plain relay (an operator's
answer, a nudge, a question) passes. A script cannot read intent, so new
scope written as free prose passes too; session-keeper's lifetime and idle
bounds (scripts/mc-keeper.sh) retire such a session regardless.
  exit 0, nothing printed: not unit-shaped
  exit 5, `retask<TAB><why>` on stdout: unit-shaped

log appends one row to <fleet-home>/mission-control/retasks.log ("# format:
1", then <epoch> <via> <session> <reason>, tab separated) and prints a
warning naming the override on stderr. Every override of a refusal is
logged here: `fleet-streamjson.sh steer --retask <reason>`,
`orchestrate-relay.sh deliver tmux ... --retask <reason>`, and a
SendMessage whose first line starts `[planwright retask-override: <reason>]`.

hook is the PreToolUse hook on SendMessage. It denies a message to a
session the mission-control launcher registers as a worker, reviewer or
ad-hoc kind when check refuses it, naming the fresh-launch path, unless its
first line carries the override tag, which it logs and lets through. Any
other recipient, tool or payload is left to the harness: silence, exit 0.
Without jq the hook cannot read the payload and stays silent.

Exit codes: 0 done (check: not unit-shaped); 2 usage, an unreadable message
file, or a log that could not be written; 5 check refused the message.
EOF
}

usage() {
  help_text >&2
  exit 2
}

# brief_why <file> — print why the message is unit-shaped, or return 1.
brief_why() {
  awk '
    !started && $0 ~ /[^[:space:]]/ {
      started = 1
      if ($0 ~ /^[[:space:]]*\/[A-Za-z][A-Za-z0-9:_.-]*([[:space:]]|$)/) { print "it opens with a skill command, which starts a new unit"; found = 1; exit }
    }
    index($0, "<!-- mission-control launch:") == 1 { print "it carries a launch brief (the launcher'"'"'s marker line)"; found = 1; exit }
    index($0, "<!-- mc-rules begin") == 1 { print "it carries the standing-rules block a launch delivers"; found = 1; exit }
    $0 ~ /^## Verification cadence[[:space:]]*$/ { print "it carries a launch'"'"'s verification cadence"; found = 1; exit }
    END { exit !found }
  ' "$1"
}

refusal_text() {
  printf '%s' "re-tasking a live session is refused ($1). Launch a fresh session for new scope (scripts/mission-control-launch.sh launch); for a new review round on an open pull request, launch a successor on the same worktree and branch with a handover brief and /planwright:resume as its entry. Override only when no fresh launch can serve, and say why: $2"
}

cmd_check() {
  [ "$#" -eq 1 ] || usage
  [ -f "$1" ] && [ -r "$1" ] || {
    printf '%s\n' "$me: the message file is missing or unreadable" >&2
    exit 2
  }
  why=$(brief_why "$1") || exit 0
  printf 'retask\t%s\n' "$why"
  exit 5
}

valid_field() {
  case $1 in
    '' | *"$(printf '\t')"* | *'
'*) return 1 ;;
  esac
  return 0
}

# do_log <via> <to> <reason> <now> — append the override row and warn.
do_log() {
  dl_home=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) && [ -n "$dl_home" ] || {
    printf '%s\n' "$me: cannot resolve the fleet home; the override was not logged" >&2
    return 2
  }
  dl_dir="$dl_home/mission-control"
  mkdir -p "$dl_dir" 2>/dev/null || {
    printf '%s\n' "$me: cannot create $(sanitize_printable "$dl_dir"); the override was not logged" >&2
    return 2
  }
  dl_log="$dl_dir/retasks.log"
  dl_reason=$(printf '%s' "$3" | tr '\t\r\n' '   ' | sed 's/^ *//; s/ *$//' | cut -c1-500)
  dl_fresh=1
  [ ! -s "$dl_log" ] || dl_fresh=0
  {
    [ "$dl_fresh" = 0 ] || printf '# format: 1\n'
    printf '%s\t%s\t%s\t%s\n' "$4" "$1" "$2" "$dl_reason"
  } >>"$dl_log" 2>/dev/null || {
    printf '%s\n' "$me: cannot append to $(sanitize_printable "$dl_log"); the override was not logged" >&2
    return 2
  }
  printf '%s\n' "$me: WARNING: re-tasking live session $(sanitize_printable "$2") through $1 on an override ($(sanitize_printable "$dl_reason")); logged in $(sanitize_printable "$dl_log")" >&2
}

cmd_log() {
  via='' to='' reason='' now=''
  while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] || usage
    case $1 in
      --via) via=$2 ;;
      --to) to=$2 ;;
      --reason) reason=$2 ;;
      --now) now=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  case $via in steer | relay | send-message) ;; *) usage ;; esac
  valid_field "$to" || usage
  case $reason in *[![:space:]]*) ;; *) usage ;; esac
  case $now in
    '') now=$(date +%s) ;;
    *[!0-9]*) usage ;;
  esac
  do_log "$via" "$to" "$reason" "$now" || exit 2
}

# repo_changing_session <name> — 0 when the launcher registers <name> as a
# worker, reviewer or ad-hoc session.
repo_changing_session() {
  case $1 in
    mc-*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
  rc_home=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) && [ -n "$rc_home" ] || return 1
  rc_row="$rc_home/mission-control/sessions/$1"
  [ -f "$rc_row" ] && [ ! -L "$rc_row" ] && [ -r "$rc_row" ] || return 1
  rc_kind=$(awk -F '\t' '$1 == "kind" { print substr($0, 6); exit }' "$rc_row")
  case $rc_kind in
    worker | reviewer | ad-hoc) return 0 ;;
  esac
  return 1
}

cmd_hook() {
  [ "$#" -eq 0 ] || usage
  command -v jq >/dev/null 2>&1 || exit 0
  input=$(head -c 262144) || exit 0
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
  [ "$tool" = SendMessage ] || exit 0
  to=$(printf '%s' "$input" | jq -r '.tool_input.to // empty' 2>/dev/null) || exit 0
  # A listing's disambiguating ` [ref]` suffix is not part of the name.
  to=${to%% \[*}
  repo_changing_session "$to" || exit 0
  msg=$(mktemp "${TMPDIR:-/tmp}/retask-guard.XXXXXX") || exit 0
  trap 'rm -f "$msg"' EXIT
  printf '%s' "$input" | jq -r '.tool_input.message // empty' >"$msg" 2>/dev/null || exit 0
  first=$(awk 'NF { print; exit }' "$msg")
  reason=''
  case $first in
    "$OVERRIDE_TAG"*)
      reason=${first#"$OVERRIDE_TAG"}
      reason=${reason%%]*}
      # The shape is the rest of the message's, below the tag line.
      awk 'done { print; next } NF { done = 1 }' "$msg" >"$msg.rest" && mv -f "$msg.rest" "$msg" || exit 0
      ;;
  esac
  why=$(brief_why "$msg") || exit 0
  case $reason in
    *[![:space:]]*)
      do_log send-message "$to" "$reason" "$(date +%s)" || :
      exit 0
      ;;
  esac
  text=$(refusal_text "$why" "start the message's first line with $OVERRIDE_TAG <reason>], which is logged.")
  jq -nc --arg r "planwright retask-guard: $text" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
}

[ "$#" -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help) help_text ;;
  check) cmd_check "$@" ;;
  log) cmd_log "$@" ;;
  hook) cmd_hook "$@" ;;
  # The refusal sentence, for the sibling scripts that refuse on check's
  # verdict, so every surface names the same fresh-launch path.
  _refusal)
    [ "$#" -eq 2 ] || usage
    refusal_text "$1" "$2"
    printf '\n'
    ;;
  *) usage ;;
esac
