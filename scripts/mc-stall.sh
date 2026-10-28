#!/usr/bin/env bash
# mc-stall.sh — liveness and stall states for every session the
# mission-control launcher registers, whatever its kind.
#
# `mc-stall.sh --help` prints the contract: verbs, states, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-stall
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh fleet-pane-vocabulary.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/fleet-pane-vocabulary.sh
. "$script_dir/fleet-pane-vocabulary.sh" || exit 2

ROW_FORMAT=1
WINDOW_LINES=20
FOOTER_LINES=8

help_text() {
  cat <<'HELP'
mc-stall.sh — liveness and stall states for every session the
mission-control launcher (scripts/mission-control-launch.sh) registers, of
any kind.

Usage:
  mc-stall.sh classify --program <p> [--now <epoch>] [--pane <file>] <name>
      classify one registered session. --pane reads the pane text from a
      file instead of capturing the session's tmux window.
  mc-stall.sh scan --program <p> [--now <epoch>]
      classify every launched session the program's registry rows name.

Liveness is the session's pid as its rung records it (the stream-json
supervisor's worker.pid; the tmux window's pane pid) and that process's
state, never pane text or elapsed time. The states, first match wins:
  dead                   the recorded pid is gone or a zombie
  unknown                no pid could be read; the reason says whether the
                         pane is changing, stable or absent
  open-selector          a dialog or select menu is open in the pane
  unsubmitted-prompt     the input box holds a staged paste
  turn-ended-background  the main turn ended with background agents running
  idle-question          the session is idle and its last line above the
                         input box is a question
  busy-unchanged         a busy session whose pane, spinner lines aside, has
                         not changed across samples spanning the stall window
                         (mission_control_stall_window)
  working                busy, and the pane changed inside the window
  idle                   at the prompt with no question
  live                   the pid is alive and the pane shows none of the above
Elapsed time counts only for busy-unchanged, and only beside a positive busy
marker and a pane unchanged since an earlier sample.

Each pass keeps one sample per session (the pane's hash, when it last
changed, the state) under the program's runtime directory. Entering any
state from dead to busy-unchanged emits one event, kind stall-<state>,
subject the session name (scripts/mc-event.sh); a state held across passes
emits no second one.

Output, one line per session, tab separated:
  <name> <kind> <state> <reason> <event id or ->

Exit codes: 0 classified; 1 a store could not be read or written, or an
event could not be emitted; 2 usage, a malformed name or a registry row of
an unknown format; 3 the program is not configured or no row names the
session.
HELP
}

usage() {
  mc_usage_fail "usage: mc-stall.sh classify --program <p> [--now <epoch>] [--pane <file>] <name> | scan --program <p> [--now <epoch>]"
}

valid_name() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    mc-*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
}

# valid_window <id>: a tmux window id, @ and digits only.
valid_window() {
  case $1 in
    @*) ;;
    *) return 1 ;;
  esac
  mc_valid_uint "${1#@}"
}

row_get() {
  awk -F '\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$1"
}

# pid_state <pid>: alive, gone or zombie from the process table; fails when
# the table cannot be read.
pid_state() {
  command -v ps >/dev/null 2>&1 || return 1
  ps_out=$(ps -o stat= -p "$1" 2>/dev/null)
  ps_out=${ps_out#"${ps_out%%[! ]*}"}
  case $ps_out in
    '') printf 'gone\n' ;;
    Z*) printf 'zombie\n' ;;
    *) printf 'alive\n' ;;
  esac
}

# session_pid <backend> <handle>: the session's pid as its rung records it,
# or nothing.
session_pid() {
  sp=''
  case $1 in
    stream-json)
      sp_f="$FLEET_HOME/streamjson/$2/worker.pid"
      [ -f "$sp_f" ] && [ ! -L "$sp_f" ] && sp=$(head -n 1 "$sp_f" 2>/dev/null)
      ;;
    tmux)
      if valid_window "$2"; then
        sp=$(tmux display-message -p -t "$2" '#{pane_pid}' 2>/dev/null) || sp=''
      fi
      ;;
  esac
  mc_valid_uint "$sp" && [ "$sp" -gt 0 ] && printf '%s\n' "$sp"
}

# capture <backend> <handle>: the visible pane of a tmux session.
capture() {
  [ "$1" = tmux ] && valid_window "$2" || return 1
  tmux capture-pane -p -t "$2" 2>/dev/null
}

# pane_hash <text>: the hash of the pane with every line carrying a busy
# marker or spinner word dropped, so a spinner's ticking timer is no change.
pane_hash() {
  printf '%s\n' "$1" | {
    while IFS= read -r ph_line; do
      ph_lc=$(printf '%s' "$ph_line" | tr '[:upper:]' '[:lower:]')
      if printf '%s\n%s\n' "$(busy_markers)" "$(spinner_words)" | contains_any "$ph_lc"; then
        continue
      fi
      printf '%s\n' "$ph_line"
    done
  } | mc_sha256
}

# question_above_input <window>: the last non-blank line above the input box
# ends in a question mark. The input box is found positively, by its prompt
# glyph, so a pane with no input box carries no question.
question_above_input() {
  printf '%s\n' "$1" | awk '
    { l[NR] = $0 }
    END {
      p = 0
      for (i = NR; i > 0; i--) if (l[i] ~ /^[ \t]*(❯|>|│ >)([ \t]|$)/) { p = i; break }
      if (!p) exit 1
      for (i = p - 1; i > 0; i--) {
        t = l[i]; sub(/[ \t]+$/, "", t)
        if (t ~ /^[ \t]*$/ || t ~ /^[ \t]*[╭─]/) continue
        exit !(t ~ /\?$/)
      }
      exit 1
    }'
}

# classify_one <row>: print the session's line, keep its sample, emit an
# event on entering a stall state.
classify_one() {
  c_row=$1
  c_name=$(row_get "$c_row" name)
  c_kind=$(row_get "$c_row" kind)
  c_backend=$(row_get "$c_row" backend)
  c_handle=$(row_get "$c_row" handle)
  mc_valid_kebab "$c_kind" || c_kind=-

  c_pane=''
  c_have_pane=0
  if [ -n "$PANE_FILE" ]; then
    c_pane=$(tail -n "$WINDOW_LINES" "$PANE_FILE") || mc_usage_fail "cannot read the pane file $(sanitize_printable "$PANE_FILE")"
    c_have_pane=1
  elif c_cap=$(capture "$c_backend" "$c_handle"); then
    c_pane=$(printf '%s\n' "$c_cap" | awk 'NF { last = NR } { l[NR] = $0 } END { for (i = 1; i <= last; i++) print l[i] }' | tail -n "$WINDOW_LINES")
    c_have_pane=1
  fi

  c_sample="$STALL_DIR/$c_name"
  c_prev_hash='' c_prev_since='' c_prev_state=''
  if [ -f "$c_sample" ] && [ ! -L "$c_sample" ]; then
    IFS='	' read -r c_prev_hash c_prev_since c_prev_state <"$c_sample" || :
    mc_valid_uint "$c_prev_since" || c_prev_hash=''
  fi
  c_hash=-
  c_since=$NOW
  if [ "$c_have_pane" = 1 ]; then
    c_hash=$(pane_hash "$c_pane") || mc_fail "no SHA-256 tool to sample the pane"
    [ "$c_hash" != "$c_prev_hash" ] || c_since=$c_prev_since
  fi

  c_pid=$(session_pid "$c_backend" "$c_handle") || c_pid=''
  c_ps=''
  [ -z "$c_pid" ] || c_ps=$(pid_state "$c_pid") || c_ps=''

  c_footer=$(printf '%s\n' "$c_pane" | tail -n "$FOOTER_LINES")
  c_footer_lc=$(printf '%s' "$c_footer" | tr '[:upper:]' '[:lower:]')

  if [ -n "$c_ps" ] && [ "$c_ps" != alive ]; then
    c_state=dead c_reason="pid $c_pid $c_ps"
  elif [ -z "$c_ps" ]; then
    c_state=unknown
    if [ "$c_have_pane" = 0 ]; then
      c_reason='no-pid no-pane'
    elif [ -z "$c_prev_hash" ]; then
      c_reason='no-pid pane-first-sample'
    elif [ "$c_hash" != "$c_prev_hash" ]; then
      c_reason='no-pid pane-changing'
    else
      c_reason='no-pid pane-stable'
    fi
  elif [ "$c_have_pane" = 0 ]; then
    c_state=live c_reason="pid $c_pid alive, no pane"
  elif selection_prompt_present "$c_pane"; then
    c_state=open-selector c_reason='dialog signature in the pane'
  elif staged_paste_present "$c_pane"; then
    c_state=unsubmitted-prompt c_reason='staged paste in the input box'
  else
    c_main_busy=0 c_bg=0
    printf '%s\n%s\n' 'esc to interrupt' "$(spinner_words)" | contains_any "$c_footer_lc" && c_main_busy=1
    printf '%s\n%s\n' 'background agent' 'to manage' | contains_any "$c_footer_lc" && c_bg=1
    c_raw=$(raw_classify "$c_footer")
    if [ "$c_main_busy" = 0 ] && [ "$c_bg" = 1 ]; then
      c_state=turn-ended-background c_reason='background agents running after the turn'
    elif [ "$c_raw" = idle ] && question_above_input "$c_pane"; then
      c_state=idle-question c_reason='question above the input box'
    elif [ "$c_raw" = busy ]; then
      if [ -n "$c_prev_hash" ] && [ "$c_hash" = "$c_prev_hash" ] && [ $((NOW - c_since)) -ge "$WINDOW" ]; then
        c_state=busy-unchanged c_reason="busy, pane unchanged since $c_since"
      else
        c_state=working c_reason='busy'
      fi
    elif [ "$c_raw" = idle ]; then
      c_state=idle c_reason='at the prompt'
    else
      c_state=live c_reason="pid $c_pid alive, pane indeterminate"
    fi
  fi

  c_event=-
  case $c_state in
    working | idle | live) ;;
    *)
      if [ "$c_state" != "$c_prev_state" ]; then
        c_event=$(mc_event emit --program "$PROGRAM" --now "$NOW" -- "stall-$c_state" "$c_name" "$c_kind: $c_reason") \
          || mc_fail "the stall-$c_state event for $c_name was not emitted"
      fi
      ;;
  esac

  c_tmp="$c_sample.tmp.$$"
  if ! printf '%s\t%s\t%s\n' "$c_hash" "$c_since" "$c_state" >"$c_tmp" || ! mv -f "$c_tmp" "$c_sample"; then
    rm -f "$c_tmp"
    mc_fail "cannot keep the sample for $c_name"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$c_name" "$c_kind" "$c_state" "$c_reason" "$c_event"
}

# row_ok <row>: a regular file of the known format, for this program.
row_ok() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] || return 1
  [ "$(row_get "$1" format)" = "$ROW_FORMAT" ] || return 2
  [ "$(row_get "$1" program)" = "$PROGRAM" ] || return 3
}

PROGRAM='' NOW_RAW='' PANE_FILE='' NAME=''
[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help)
    help_text
    exit 0
    ;;
  classify | scan) ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --pane)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) PROGRAM=$2 ;;
        --now) NOW_RAW=$2 ;;
        --pane)
          [ "$verb" = classify ] || usage
          PANE_FILE=$2
          ;;
      esac
      shift 2
      ;;
    -*) usage ;;
    *)
      [ "$verb" = classify ] && [ -z "$NAME" ] || usage
      NAME=$1
      shift
      ;;
  esac
done
[ -n "$PROGRAM" ] || usage
[ "$verb" = scan ] || [ -n "$NAME" ] || usage
[ -z "$NAME" ] || valid_name "$NAME" || mc_usage_fail "invalid session name '$(sanitize_printable "$NAME")'"
[ -z "$PANE_FILE" ] || [ -r "$PANE_FILE" ] || mc_usage_fail "cannot read the pane file $(sanitize_printable "$PANE_FILE")"
mc_now_arg "$NOW_RAW"
mc_require_program "$PROGRAM"

WINDOW_RAW=$(mc_knob mission_control_stall_window mc_parse_cadence) || exit 1
WINDOW=$(mc_seconds "$WINDOW_RAW")
FLEET_HOME=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
REG="$FLEET_HOME/mission-control/sessions"
RUNTIME=$(mc_runtime "$PROGRAM") || mc_fail "cannot create the runtime directory of program $PROGRAM"
STALL_DIR="$RUNTIME/stall"
mkdir -p "$STALL_DIR" 2>/dev/null || mc_fail "cannot create $(sanitize_printable "$STALL_DIR")"

case $verb in
  classify)
    row="$REG/$NAME"
    row_ok "$row"
    case $? in
      0) ;;
      2) mc_usage_fail "refusing the registry row $NAME: its format field is $(sanitize_printable "$(row_get "$row" format)" missing), not $ROW_FORMAT" ;;
      *)
        printf '%s\n' "$prog: no session of program $PROGRAM is registered as $NAME" >&2
        exit 3
        ;;
    esac
    classify_one "$row"
    ;;
  scan)
    [ -d "$REG" ] || exit 0
    set +f
    set -- "$REG"/mc-*
    set -f
    for row in "$@"; do
      case ${row##*/} in *.tmp.*) continue ;; esac
      valid_name "${row##*/}" || continue
      row_ok "$row"
      case $? in
        0) ;;
        2)
          printf '%s\n' "$prog: skipping the registry row $(sanitize_printable "${row##*/}"): its format field is not $ROW_FORMAT" >&2
          continue
          ;;
        *) continue ;;
      esac
      [ "$(row_get "$row" state)" = launched ] || continue
      classify_one "$row"
    done
    ;;
esac
