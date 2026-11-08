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
      --decided-in <hub>

It sends the single keystroke <digit> to the pane of <p>'s mission-control
session, found as scripts/mc-session-pane.sh finds it (never a pane named
by the caller), only when every check holds, and refuses otherwise:
  - <digit> is one of 1 to 9, the whole argument;
  - <hub> is the program mission_control_escalation_hub names, and not <p>;
  - <entry id> names an entry of <hub>'s decisions log (scripts/mc-kb.sh)
    noted as the operator's answer (scripts/mc-decide.sh note --shape
    answer) about this dialog: its subject is `<p> dialog <digest>`, the
    digest the escalation watcher (scripts/mc-escalate.sh) records for the
    dialog and names in its escalation, and its answer is <digit>;
  - the entry was recorded no earlier than the watcher first saw the
    dialog, and no earlier answer used it (<runtime>/escalate/answers.log
    under <p>'s runtime directory, keyed by <hub> and the entry id);
  - exactly one session of <p> is running, it is the session the watcher
    recorded, and its pane shows that same dialog open, read again just
    before the keystroke, its digest covering it whole: from the rule that
    opens it (a line of rule glyphs only) down, with no line cut as
    side-panel text;
  - the pane is not the caller's own, nor one the caller runs under;
  - the dialog's own option run offers <digit>, and its label is one that
    answers this dialog and nothing more: Yes, No, "No, and tell Claude
    what to do differently" or "Yes, but ask again next time". Any other
    label (a rule for later calls, a mode switch, a directory or trust
    grant) is refused, as is a run whose labels wrap or repeat a digit.
After a sent answer the watcher's record of the dialog is dropped while
it still names that dialog, waiting up to about 10 s for the watcher's
pass, so a dialog that follows starts its own hold; a drop it cannot make
is named on stderr and exits 1. Each answer sent, or attempted
and failed, appends one line to <runtime>/escalate/answers.log:
  <epoch> <entry id> <hub> <digit> <pane> <session pid> sent|failed
One answer runs at a time per program.

Output: answered<TAB><program><TAB><pane><TAB><digit><TAB><option label>

Exit codes: 0 sent; 1 a store, the pane, the log or the send that failed,
a sent answer left unlogged or its record not dropped (the output line
still printed), or another answer to <p> in flight; 2 usage; 3 a program is not
configured; 4 refused by a check above (named on stderr).

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-pane-answer.sh --program <p> --choice <digit> --decision <entry id> --decided-in <hub>"
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

# shellcheck disable=SC2329 # mc_knob calls it by name
parse_hub() {
  [ "$1" = none ] || mc_valid_program "$1" || return 1
  printf '%s\n' "$1"
}
HUB=$(mc_knob mission_control_escalation_hub parse_hub) || exit 1
[ "$DECIDED_IN" = "$HUB" ] || refuse "decisions about a stuck mission control are the hub's ($HUB), not $DECIDED_IN's"
[ "$DECIDED_IN" != "$PROGRAM" ] || refuse "a program never answers its own mission control's dialog"

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

# The dialog the watcher recorded.
[ -f "$SELF" ] && [ ! -L "$SELF" ] || refuse "no dialog of $PROGRAM is on record"
msp_record "$SELF"
case $? in
  1) mc_fail "cannot read the dialog record of $PROGRAM" ;;
  2) refuse "no dialog of $PROGRAM is on record" ;;
esac
rec_first=$MSP_REC_FIRST rec_sess=$MSP_REC_SESS rec_print=$MSP_REC_PRINT
mc_valid_uint "$rec_first" && [ -n "$rec_sess" ] && [[ $rec_print =~ ^[0-9a-f]{16}$ ]] || refuse "the dialog record of $PROGRAM is unreadable"

# The decision: the operator's answer about this dialog, in the hub's log.
ENTRIES=$(/bin/bash "$script_dir/mc-kb.sh" entries --program "$DECIDED_IN" decisions 2>/dev/null) || mc_fail "cannot read the decisions log of $DECIDED_IN"
ENTRY=$(printf '%s\n' "$ENTRIES" | D=$DECISION awk -F '\t' '$1 == ENVIRON["D"] { print; exit }')
[ -n "$ENTRY" ] || refuse "decision $DECISION is not in the decisions log of $DECIDED_IN"
VERDICT=$(printf '%s\n' "$ENTRY" | S="$PROGRAM dialog $rec_print" C=$CHOICE awk -F '\t' "$MC_GROUNDS_AWK"'
  { r = grounds($6) ? G_REASON : ""
    if (r != "answer") print "not the operator'"'"'s answer"
    else if ($3 != ENVIRON["S"]) print "about another dialog"
    else if ($5 != ENVIRON["C"]) print "an answer other than " ENVIRON["C"]
    else print "ok" }')
[ "$VERDICT" = ok ] || refuse "decision $DECISION is $VERDICT"
DECIDED_AT=$(printf '%s\n' "$ENTRY" | awk -F '\t' '{ print $2 }')
[[ $DECIDED_AT =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || refuse "decision $DECISION carries no readable time"
FIRST_AT=$(mc_iso "$rec_first") || mc_fail "cannot format the dialog's first sight"
[[ ! $DECIDED_AT < $FIRST_AT ]] || refuse "decision $DECISION predates the dialog it would answer"
if [ -e "$LOG" ]; then
  USED=$(D=$DECISION H=$DECIDED_IN awk -F '\t' '$2 == ENVIRON["D"] && $3 == ENVIRON["H"] { print "used"; exit }' "$LOG" 2>/dev/null) \
    || mc_fail "cannot read $(sanitize_printable "$LOG") to check decision $DECISION was not used before"
  [ "$USED" != used ] || refuse "decision $DECISION already answered a dialog"
fi

# The session and its pane, found afresh.
bounded() { /bin/sh "$script_dir/bounded-run.sh" "$TMUX_BOUND" "$@"; }
PS_TABLE=$(bounded /bin/sh -c "$MSP_PS_CMD" 2>/dev/null) || mc_fail "cannot read the process table"
S_PID=$(msp_find "$PROGRAM" "$PS_TABLE")
case $S_PID in
  absent) refuse "no mission-control session of $PROGRAM is running" ;;
  ambiguous) refuse "more than one mission-control session of $PROGRAM is running" ;;
esac
[ "$S_PID" = "$rec_sess" ] || refuse "the running session of $PROGRAM is not the one whose dialog is on record"
PANES=$(bounded tmux list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null) || mc_fail "cannot list the tmux panes"
PANE=$(msp_pane_of "$S_PID" "$PS_TABLE" "$PANES") || refuse "the session of $PROGRAM has no tmux pane"
[ "${TMUX_PANE:-}" != "$PANE" ] || refuse "the pane is the caller's own"
PANE_PID=$(printf '%s\n' "$PANES" | P=$PANE awk -F '\t' '$1 == ENVIRON["P"] { print $2; exit }')
! msp_ancestor "$PANE_PID" "$$" "$PS_TABLE" || refuse "the pane is one the caller runs under"

# read_dialog: the pane's dialog now, refused unless it is the recorded one.
read_dialog() {
  rd_text=$(bounded tmux capture-pane -p -t "$PANE" 2>/dev/null) || mc_fail "cannot capture pane $PANE"
  rd_text=$(printf '%s\n' "$rd_text" | msp_trim)
  msp_dialog "$rd_text" || refuse "pane $PANE shows no open dialog"
  [ "$MSP_BINDABLE" = 1 ] || refuse "pane $PANE shows a dialog its digest cannot cover whole (no opening rule on screen, or a line cut as side-panel text); answer it at its pane"
  [ "$MSP_PRINT" = "$rec_print" ] || refuse "pane $PANE shows a different dialog from the one on record"
}
read_dialog
case $MSP_RUN in
  ok) ;;
  none) refuse "the dialog has no numbered options" ;;
  *) refuse "the dialog's options wrap or repeat a digit" ;;
esac
LABEL=$(printf '%s\n' "$MSP_OPTIONS" | C=$CHOICE awk -F '\t' '$1 == ENVIRON["C"] { print $2; exit }')
[ -n "$LABEL" ] || refuse "the dialog offers no option $CHOICE"
msp_answerable "$LABEL" || refuse "option $CHOICE ($(sanitize_printable "$LABEL")) does more than answer this dialog"
read_dialog

if bounded tmux send-keys -t "$PANE" "$CHOICE" 2>/dev/null; then
  outcome=sent
else
  outcome=failed
fi
logged=1
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NOW" "$DECISION" "$DECIDED_IN" "$CHOICE" "$PANE" "$S_PID" "$outcome" >>"$LOG" 2>/dev/null || logged=0
if [ "$outcome" != sent ]; then
  [ "$logged" = 1 ] || mc_fail "the keystroke could not be sent to pane $PANE, and the attempt could not be logged under $(sanitize_printable "$LOG"); do not reuse decision $DECISION"
  mc_fail "the keystroke could not be sent to pane $PANE"
fi
# The watcher's next pass sees whatever dialog follows as a new one, an
# identical one included. A record the watcher wrote since names that next
# dialog and stays.
dropped=0
if pw_lock_acquire "$ESC_DIR/pass.lock" 500; then
  msp_record "$SELF"
  case $? in
    0)
      if [ "$MSP_REC_FIRST/$MSP_REC_SESS/$MSP_REC_PRINT" != "$rec_first/$rec_sess/$rec_print" ] || rm -f "$SELF" 2>/dev/null; then
        dropped=1
      fi
      ;;
    2) dropped=1 ;;
  esac
  pw_lock_release "$ESC_DIR/pass.lock" || :
fi
printf 'answered\t%s\t%s\t%s\t%s\n' "$PROGRAM" "$PANE" "$CHOICE" "$(sanitize_printable "$LABEL")"
[ "$logged" = 1 ] || printf '%s\n' "$prog: the answer was sent but could not be logged under $(sanitize_printable "$LOG"); do not reuse decision $DECISION" >&2
[ "$dropped" = 1 ] || printf '%s\n' "$prog: the answer was sent but the watcher's record of the answered dialog could not be dropped; the same dialog asked again inherits its hold and is not escalated again" >&2
[ "$logged" = 1 ] && [ "$dropped" = 1 ] || exit 1
