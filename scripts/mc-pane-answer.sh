#!/usr/bin/env bash
# mc-pane-answer.sh — deliver the operator's recorded choice to a dialog a
# program's mission control is stuck on, as one digit into its tmux pane,
# and nothing else.
#
# `mc-pane-answer.sh --help` prints the contract: checks, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-pane-answer
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh lock-lib.sh fleet-pane-vocabulary.sh mc-session-pane.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2
# shellcheck source=scripts/fleet-pane-vocabulary.sh
. "$script_dir/fleet-pane-vocabulary.sh" || exit 2
# shellcheck source=scripts/mc-session-pane.sh
. "$script_dir/mc-session-pane.sh" || exit 2

TMUX_BOUND=10

help_text() {
  cat <<'HELP'
mc-pane-answer.sh — deliver the operator's recorded choice to a dialog a
program's mission control is stuck on, as one digit into its tmux pane,
and nothing else.

Usage:
  mc-pane-answer.sh --program <p> --choice <digit> --decision <entry id>
      --decided-in <program>

It sends the single keystroke <digit> to the pane of <p>'s mission-control
session, found as scripts/mc-session-pane.sh finds it (never a pane named
by the caller), only when every check holds, and refuses otherwise:
  - <digit> is one of 1 to 9, the whole argument;
  - <entry id> names an entry of <program>'s decisions log
    (scripts/mc-kb.sh) that records the operator's own words: grounds whose
    reason is `answer` or `correction` (scripts/mc-decide.sh note), or an
    act that opens `operator: "`;
  - the entry was recorded no earlier than the escalation watcher
    (scripts/mc-escalate.sh) first saw the dialog, which it records under
    <p>'s runtime directory, so a decision about an earlier dialog never
    answers this one;
  - no earlier answer used the entry (<runtime>/escalate/answers.log);
  - exactly one session of <p> is running, it is the session the watcher
    recorded, and its pane shows that same dialog open now;
  - the pane is not the caller's own, nor one the caller runs under;
  - the dialog offers option <digit>, and choosing it adds no standing
    permission (an option that allows again, always or for the session).
Each answer sent, or attempted and failed, appends one line to
<runtime>/escalate/answers.log:
  <epoch> <entry id> <program decided in> <digit> <pane> <session pid> sent|failed
One answer runs at a time per program.

Output: answered<TAB><program><TAB><pane><TAB><digit><TAB><option label>

Exit codes: 0 sent; 1 a store, the pane or the send that failed; 2 usage;
3 a program is not configured; 4 refused by a check above (named on
stderr).

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-pane-answer.sh --program <p> --choice <digit> --decision <entry id> --decided-in <program>"
}

refuse() {
  printf '%s\n' "$prog: refused: $1" >&2
  exit 4
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
PROGRAM=""
CHOICE=""
DECISION=""
DECIDED_IN=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --choice | --decision | --decided-in)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) PROGRAM=$2 ;;
        --choice) CHOICE=$2 ;;
        --decision) DECISION=$2 ;;
        --decided-in) DECIDED_IN=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$PROGRAM" ] && [ -n "$CHOICE" ] && [ -n "$DECISION" ] && [ -n "$DECIDED_IN" ] || usage
case $CHOICE in
  [1-9]) ;;
  *) refuse "the choice must be one digit from 1 to 9" ;;
esac
[[ $DECISION =~ ^decisions-[0-9]{6}-[1-9][0-9]{0,8}$ ]] || refuse "the decision must be a decisions-log entry id"
mc_valid_program "$DECIDED_IN" || mc_usage_fail "invalid program name '$(sanitize_printable "$DECIDED_IN")'"
mc_require_program "$PROGRAM"
PLANWRIGHT_MC_CHECKED=""
mc_require_program "$DECIDED_IN"
NOW=$(mc_now)

FLEET_HOME=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
ESC_DIR="$FLEET_HOME/mission-control/$PROGRAM/escalate"
[ -d "$ESC_DIR" ] && [ ! -L "$ESC_DIR" ] && [ ! -L "${ESC_DIR%/escalate}" ] || refuse "no dialog of $PROGRAM is on record"
SELF="$ESC_DIR/self"
LOG="$ESC_DIR/answers.log"
if [ -L "$LOG" ] || { [ -e "$LOG" ] && [ ! -f "$LOG" ]; }; then
  mc_fail "refusing $(sanitize_printable "$LOG"): not a regular file"
fi

pw_lock_trap_install
pw_lock_acquire "$ESC_DIR/answer.lock" 50
case $? in
  0) ;;
  1) mc_fail "another answer to $PROGRAM is in flight" ;;
  *) mc_fail "cannot take the answer lock" ;;
esac

# The decision: the operator's own words, in the named program's log.
ENTRIES=$(/bin/bash "$script_dir/mc-kb.sh" entries --program "$DECIDED_IN" decisions 2>/dev/null) || mc_fail "cannot read the decisions log of $DECIDED_IN"
ENTRY=$(printf '%s\n' "$ENTRIES" | D=$DECISION awk -F '\t' '$1 == ENVIRON["D"] { print; exit }')
[ -n "$ENTRY" ] || refuse "decision $DECISION is not in the decisions log of $DECIDED_IN"
QUOTE_OK=$(printf '%s\n' "$ENTRY" | awk -F '\t' "$MC_GROUNDS_AWK"'
  { r = grounds($6) ? G_REASON : ""
    print ((r == "answer" || r == "correction" || index($4, "operator: \"") == 1) ? "yes" : "no") }')
[ "$QUOTE_OK" = yes ] || refuse "decision $DECISION does not record the operator's words"
DECIDED_AT=$(printf '%s\n' "$ENTRY" | awk -F '\t' '{ print $2 }')
[[ $DECIDED_AT =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || refuse "decision $DECISION carries no readable time"
if [ -f "$LOG" ] && D=$DECISION awk -F '\t' '$2 == ENVIRON["D"] { f = 1; exit } END { exit !f }' "$LOG"; then
  refuse "decision $DECISION already answered a dialog"
fi

# The dialog the watcher recorded, which the decision must postdate.
[ -f "$SELF" ] && [ ! -L "$SELF" ] || refuse "no dialog of $PROGRAM is on record"
rec_first="" rec_sess="" rec_print=""
IFS='	' read -r _ rec_first rec_sess rec_print _ <"$SELF" || :
mc_valid_uint "$rec_first" && [ -n "$rec_print" ] || refuse "the dialog record of $PROGRAM is unreadable"
FIRST_AT=$(mc_iso "$rec_first") || mc_fail "cannot format the dialog's first sight"
[[ ! $DECIDED_AT < $FIRST_AT ]] || refuse "decision $DECISION predates the dialog it would answer"

# The session and its pane, found afresh.
bounded() { /bin/sh "$script_dir/bounded-run.sh" "$TMUX_BOUND" "$@"; }
PS_TABLE=$(bounded /bin/sh -c 'ps -ww -A -o pid= -o ppid= -o uid= -o args=' 2>/dev/null) || mc_fail "cannot read the process table"
S_PID=$(msp_find "$PROGRAM" "$PS_TABLE")
case $S_PID in
  absent) refuse "no mission-control session of $PROGRAM is running" ;;
  ambiguous) refuse "more than one mission-control session of $PROGRAM is running" ;;
esac
[ "$S_PID" = "$rec_sess" ] || refuse "the running session of $PROGRAM is not the one whose dialog is on record"
PANES=$(bounded tmux list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null) || mc_fail "cannot list the tmux panes"
PANE=$(msp_pane_of "$S_PID" "$PS_TABLE" "$PANES") || refuse "the session of $PROGRAM has no tmux pane"
[ "${TMUX_PANE:-}" != "$PANE" ] || refuse "the pane is the caller's own"
# The caller runs under the pane when the pane's process is an ancestor of
# this shell.
PANE_PID=$(printf '%s\n' "$PANES" | P=$PANE awk -F '\t' '$1 == ENVIRON["P"] { print $2; exit }')
if printf '%s\n' "$PS_TABLE" | S=$$ T=$PANE_PID M=$MSP_ANCESTRY_MAX awk '
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { parent[$1] = $2 }
  END { p = ENVIRON["S"]; for (i = 0; i < ENVIRON["M"] + 0 && p + 0 > 1; i++) { if (p == ENVIRON["T"]) exit 0; p = parent[p] } exit 1 }'; then
  refuse "the pane is one the caller runs under"
fi
TEXT=$(bounded tmux capture-pane -p -t "$PANE" 2>/dev/null) || mc_fail "cannot capture pane $PANE"
TEXT=$(printf '%s\n' "$TEXT" | msp_trim)
msp_dialog "$TEXT" || refuse "pane $PANE shows no open dialog"
[ "$MSP_PRINT" = "$rec_print" ] || refuse "pane $PANE shows a different dialog from the one on record"
LABEL=$(msp_options "$TEXT" | C=$CHOICE awk -F '\t' '$1 == ENVIRON["C"] { print $2; exit }')
[ -n "$LABEL" ] || refuse "the dialog offers no option $CHOICE"
! msp_widening "$LABEL" || refuse "option $CHOICE adds a standing permission"

if bounded tmux send-keys -t "$PANE" "$CHOICE" 2>/dev/null; then
  outcome=sent
else
  outcome=failed
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NOW" "$DECISION" "$DECIDED_IN" "$CHOICE" "$PANE" "$S_PID" "$outcome" >>"$LOG" \
  || printf '%s\n' "$prog: cannot log the answer under $(sanitize_printable "$LOG")" >&2
[ "$outcome" = sent ] || mc_fail "the keystroke could not be sent to pane $PANE"
printf 'answered\t%s\t%s\t%s\t%s\n' "$PROGRAM" "$PANE" "$CHOICE" "$(sanitize_printable "$LABEL")"
