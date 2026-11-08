#!/bin/sh
# retask-guard.sh — refuse handing a live repository-changing session a new
# unit of work. Workers are short-lived: new scope, and each new round of
# review feedback, goes to a fresh session carrying a handover brief, never
# into a running one. `--help` prints the contract.
#
# Usage:
#   retask-guard.sh check <message-file> [--to <session>] [--tmux] [--hint <text>]
#   retask-guard.sh log --via <steer|relay|send-message> --to <session> --reason <text> [--now <epoch>] [--check]
#   retask-guard.sh hook
#   retask-guard.sh --help
#
# POSIX sh; no eval; message text is data, read only by awk and jq.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=retask-guard
verb=${1:-}
# The hook runs on every SendMessage in every session: a broken install must
# leave messaging alone rather than block it.
script_dir=$(cd "$(dirname "$0")" && pwd -P) || {
  [ "$verb" != hook ] || exit 0
  exit 2
}
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  [ "$verb" != hook ] || exit 0
  printf '%s\n' "$me: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

OVERRIDE_TAG='[planwright retask-override:'
TAB=$(printf '\t')

help_text() {
  cat <<'EOF'
usage:
  retask-guard.sh check <message-file> [--to <session> [--tmux]] [--hint <text>]
  retask-guard.sh log --via <steer|relay|send-message> --to <session>
      --reason <text> [--now <epoch>] [--check]
  retask-guard.sh hook

check reads a message bound for a live session and refuses one shaped like
a new unit of work: a line opening with a plugin skill command
(`/<plugin>:<skill>`, alone or before a space), a first line of `/clear`
(reusing a session by wiping it), or a line opening with the marker a
composed launch brief carries, the standing-rules block a launch delivers,
or a launch's verification-cadence heading (scripts/mission-control-launch.sh
and scripts/mc-rules.sh write all three). A relay (an operator's answer, a
nudge, a question, a skill named mid-sentence) passes, and so does new scope
written as free prose, which a script cannot tell from a relay;
session-keeper's bounds (scripts/mc-keeper.sh) retire such a session once
idle and ask it to hand over once old. --to names the recipient, a session
name or a tmux window id (`@<n>`); with --tmux it is a tmux target, read as
its window: `<session>:@<n>` directly, any other target (a pane id, a
`<session>:<window>`) resolved through tmux first. One the mission-control launcher registers as a tower,
orchestrator or mission-control session is not bound, so its message
passes; any other recipient is, an unresolvable one included.
  exit 0, nothing printed: not unit-shaped, or the recipient is not bound
  exit 5: unit-shaped; `retask<TAB><why>` on stdout, and on stderr the
          refusal naming the fresh-launch path, then the --hint text

log appends one row to <fleet-home>/mission-control/retasks.log (its first
line "# format: 1", then <epoch> <via> <session> <reason>, tab separated,
control bytes removed) and prints a warning on stderr; with --check it
writes no row and prints nothing, only failing as the append would.
`fleet-streamjson.sh steer --retask <reason>` and `orchestrate-relay.sh
deliver tmux ... --retask <reason>` run --check before the write or paste,
refusing an override that could not be logged, and log once delivered; the
SendMessage hook logs before letting the message through, and denies it
when the row cannot be written.

hook is the PreToolUse hook on SendMessage. It denies a unit-shaped message
to a session the launcher registers as a worker, reviewer or ad-hoc kind,
unless the message's first line is `[planwright retask-override: <reason>]`
with a reason, which it logs and lets through (the rest of the message is
what check reads). Any other recipient, tool or payload is left to the
harness: silence, exit 0. Without jq, or with a broken install, the hook
cannot read the payload and stays silent: it is a brake on a workflow
mistake, not a permission boundary.

Exit codes: 0 done (check: passes); 2 usage, an unreadable message file, a
check that could not run, or a log that could not be written; 5 check
refused the message.
EOF
}

usage() {
  help_text >&2
  exit 2
}

# unit_shape_why — read a message on stdin; print why it is unit-shaped and
# return 0, return 1 when it is not, any other status when awk failed.
unit_shape_why() {
  awk '
    { line = $0; sub(/^[[:space:]]+/, "", line); sub(/\r$/, "", line) }
    !started && line != "" {
      started = 1
      if (line ~ /^\/clear([[:space:]]|$)/) { print "it opens by clearing the session to reuse it"; found = 1; exit }
    }
    line ~ /^\/[A-Za-z0-9_-]+:[A-Za-z0-9_.-]+([[:space:]]|$)/ { print "it carries a skill command, which starts a new unit"; found = 1; exit }
    index(line, "<!-- mission-control launch:") == 1 { print "it carries a launch brief (the launcher'"'"'s marker line)"; found = 1; exit }
    index(line, "<!-- mc-rules begin") == 1 { print "it carries the standing-rules block a launch delivers"; found = 1; exit }
    line ~ /^## Verification cadence[[:space:]]*$/ { print "it carries a launch'"'"'s verification cadence"; found = 1; exit }
    END { exit !found }
  '
}

# fleet_home — the fleet home, or return 1.
fleet_home() {
  fh=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) && [ -n "$fh" ] || return 1
  printf '%s\n' "$fh"
}

# session_kind <session name or tmux window id> — print the kind the
# mission-control launcher registers for it, or nothing; return 2 when the
# registry's fleet home cannot be resolved. A name of neither shape is never
# registered, so it costs no fleet-home lookup.
session_kind() {
  case $1 in
    mc-* | @[0-9]*) ;;
    *) return 0 ;;
  esac
  sk_home=$(fleet_home) || return 2
  sk_reg="$sk_home/mission-control/sessions"
  case $1 in
    mc-*)
      case $1 in *[!a-z0-9-]*) return 0 ;; esac
      sk_row="$sk_reg/$1"
      [ -f "$sk_row" ] && [ ! -L "$sk_row" ] && [ -r "$sk_row" ] || return 0
      awk -F '\t' '$1 == "kind" { print substr($0, 6); exit }' "$sk_row"
      ;;
    @[0-9]*)
      case ${1#@} in *[!0-9]*) return 0 ;; esac
      [ -d "$sk_reg" ] || return 0
      set +f
      set -- "$1" "$sk_reg"/mc-*
      set -f
      sk_h=$1
      shift
      for sk_row in "$@"; do
        [ -f "$sk_row" ] && [ ! -L "$sk_row" ] && [ -r "$sk_row" ] || continue
        H=$sk_h awk -F '\t' '$1 == "handle" && substr($0, 8) == ENVIRON["H"] { h = 1 } $1 == "kind" { k = substr($0, 6) } END { if (h) print k }' "$sk_row"
      done | head -n 1
      ;;
  esac
}

refusal_text() {
  printf '%s' "re-tasking a live session is refused ($1). Launch a fresh session for new scope (scripts/mission-control-launch.sh launch). For a new review round on an open pull request, its successor takes the same worktree and branch with a handover brief and /planwright:resume as its entry: hand over through scripts/session-handover.sh where installed, else retire the old session and launch the fresh one there. Override only when no fresh launch can serve, and say why"
}

# tmux_window <target> — the window id a tmux target names: `@<n>` and
# `<session>:@<n>` read directly, any other target resolved through tmux,
# else the target unchanged.
tmux_window() {
  case $1 in
    @[0-9]* | *:@[0-9]*)
      tw_w="@${1##*@}"
      case ${tw_w#@} in
        *[!0-9]*) ;;
        *)
          printf '%s\n' "$tw_w"
          return 0
          ;;
      esac
      ;;
  esac
  tmux display-message -p -t "$1" '#{window_id}' 2>/dev/null || printf '%s\n' "$1"
}

cmd_check() {
  [ "$#" -ge 1 ] || usage
  ck_file=$1
  shift
  ck_to='' ck_hint='' ck_tmux=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --tmux)
        ck_tmux=1
        shift
        continue
        ;;
    esac
    [ "$#" -ge 2 ] || usage
    case $1 in
      --to) ck_to=$2 ;;
      --hint) ck_hint=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -f "$ck_file" ] && [ -r "$ck_file" ] || {
    printf '%s\n' "$me: the message file is missing or unreadable" >&2
    exit 2
  }
  why=$(unit_shape_why <"$ck_file")
  case $? in
    0) ;;
    1) exit 0 ;;
    *)
      printf '%s\n' "$me: the message could not be read" >&2
      exit 2
      ;;
  esac
  if [ -n "$ck_to" ]; then
    [ "$ck_tmux" = 0 ] || ck_to=$(tmux_window "$ck_to")
    ck_kind=$(session_kind "$ck_to") || {
      printf '%s\n' "$me: the fleet home cannot be resolved, so the recipient's kind is unknown" >&2
      exit 2
    }
    case $ck_kind in
      tower | orchestrator | mission-control) exit 0 ;;
    esac
  fi
  printf 'retask\t%s\n' "$why"
  printf '%s\n' "$me: $(refusal_text "$why")${ck_hint:+: $ck_hint}" >&2
  exit 5
}

# The union of the steer and tmux relay handle grammars, so an override
# either one delivers can always be logged.
valid_to() {
  case $1 in
    '' | -* | *[!A-Za-z0-9@%:._=/-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# utf8_only — stdin with invalid UTF-8 dropped; without iconv, every byte a
# C1 control could be.
utf8_only() {
  if command -v iconv >/dev/null 2>&1; then
    iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || :
  else
    tr -d '\200-\237'
  fi
}

# do_log <via> <to> <reason> <now> [check] — append the override row and
# warn; with check, only make sure the append would succeed.
do_log() {
  valid_to "$2" || {
    printf '%s\n' "$me: the session handle is not one a row can carry; the override was not logged" >&2
    return 2
  }
  # No C0, DEL or C1 control reaches a reader's terminal (a raw 0x9B is a
  # CSI), and the rest of the UTF-8 survives: what iconv rejects, raw C1
  # among it, is dropped before the encoded C1 range is.
  dl_reason=$(printf '%s' "$3" | tr '\t\r\n' '   ' | tr -d '\000-\037\177' \
    | awk '{ sub(/^ +/, ""); sub(/ +$/, ""); print substr($0, 1, 500) }' | utf8_only \
    | awk '{ gsub(/\302[\200-\237]/, ""); print }')
  case $dl_reason in
    *[![:space:]]*) ;;
    *)
      printf '%s\n' "$me: the reason holds nothing printable; the override was not logged" >&2
      return 2
      ;;
  esac
  dl_home=$(fleet_home) || {
    printf '%s\n' "$me: cannot resolve the fleet home; the override was not logged" >&2
    return 2
  }
  dl_dir="$dl_home/mission-control"
  mkdir -p "$dl_dir" 2>/dev/null || {
    printf '%s\n' "$me: cannot create $(sanitize_printable "$dl_dir"); the override was not logged" >&2
    return 2
  }
  dl_log="$dl_dir/retasks.log"
  # Created whole by a link, which fails when the file exists, so two first
  # overrides never write the format line twice or over each other's row.
  if [ ! -e "$dl_log" ]; then
    dl_new=$(mktemp "$dl_dir/.retasks.XXXXXX" 2>/dev/null) && {
      printf '# format: 1\n' >"$dl_new" && ln "$dl_new" "$dl_log" 2>/dev/null
      rm -f "$dl_new"
    }
  fi
  if [ "${5:-}" = check ]; then
    { : >>"$dl_log"; } 2>/dev/null && return 0
    printf '%s\n' "$me: cannot append to $(sanitize_printable "$dl_log"), so the override could not be logged" >&2
    return 2
  fi
  if ! { printf '%s\t%s\t%s\t%s\n' "$4" "$1" "$2" "$dl_reason" >>"$dl_log"; } 2>/dev/null; then
    printf '%s\n' "$me: cannot append to $(sanitize_printable "$dl_log"); the override was not logged" >&2
    return 2
  fi
  printf '%s\n' "$me: WARNING: re-tasking live session $(sanitize_printable "$2") through $1 on an override ($(sanitize_printable "$dl_reason")); logged in $(sanitize_printable "$dl_log")" >&2
}

cmd_log() {
  via='' to='' reason='' now='' lg_check=''
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --check ]; then
      lg_check=check
      shift
      continue
    fi
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
  valid_to "$to" || usage
  case $reason in *[![:space:]]*) ;; *) usage ;; esac
  case $now in
    '') now=$(date +%s) ;;
    *[!0-9]*) usage ;;
  esac
  do_log "$via" "$to" "$reason" "$now" $lg_check || exit 2
}

deny() {
  jq -nc --arg r "planwright retask-guard: $1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

cmd_hook() {
  [ "$#" -eq 0 ] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  input=$(cat) || exit 0
  head=$(printf '%s' "$input" | jq -r '[.tool_name // "", (.tool_input.to // "" | tostring)] | @tsv' 2>/dev/null) || exit 0
  tool=${head%%"$TAB"*}
  to=${head#*"$TAB"}
  [ "$tool" = SendMessage ] || exit 0
  # A listing's disambiguating ` [ref]` suffix is not part of the name.
  to=${to%% \[*}
  hk_kind=$(session_kind "$to") || exit 0
  case $hk_kind in
    worker | reviewer | ad-hoc) ;;
    *) exit 0 ;;
  esac
  work=$(mktemp -d "${TMPDIR:-/tmp}/retask-guard.XXXXXX") || exit 0
  trap 'rm -rf "$work"' EXIT
  printf '%s' "$input" | jq -r 'if (.tool_input.message | type) == "string" then .tool_input.message else empty end' >"$work/msg" 2>/dev/null || exit 0
  first=$(awk '{ l = $0; sub(/^[[:space:]]+/, "", l); sub(/\r$/, "", l) } l != "" { print l; exit }' "$work/msg") || exit 0
  reason=''
  tagged=0
  case $first in
    "$OVERRIDE_TAG"*)
      tagged=1
      reason=${first#"$OVERRIDE_TAG"}
      reason=${reason%%]*}
      # The rest of the message, below the tag line, is what gets checked.
      awk 'done { print; next } { l = $0; sub(/^[[:space:]]+/, "", l); sub(/\r$/, "", l) } l != "" { done = 1 }' "$work/msg" >"$work/rest" || exit 0
      mv -f "$work/rest" "$work/msg" || exit 0
      ;;
  esac
  why=$(unit_shape_why <"$work/msg") || exit 0
  if [ "$tagged" = 1 ]; then
    case $reason in
      *[![:space:]]*)
        do_log send-message "$to" "$reason" "$(date +%s)" 2>/dev/null \
          || deny "the re-task override could not be logged, so it is refused: it needs a printable reason and a writable mission-control directory in the fleet home."
        exit 0
        ;;
    esac
    deny "the re-task override needs a reason after the colon, which is logged: $OVERRIDE_TAG <reason>]."
  fi
  deny "$(refusal_text "$why"): start the message's first line with $OVERRIDE_TAG <reason>], which is logged."
}

[ "$#" -ge 1 ] || usage
shift
case $verb in
  -h | --help) help_text ;;
  check) cmd_check "$@" ;;
  log) cmd_log "$@" ;;
  hook) cmd_hook "$@" ;;
  *) usage ;;
esac
