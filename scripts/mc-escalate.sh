#!/usr/bin/env bash
# mc-escalate.sh — the session-keeper's escalation watcher: what a program's
# mission control has left unanswered goes one level up, to the hub mission
# control and then to the operator, with no model in the path.
#
# `mc-escalate.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-escalate
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
EVENT_KIND=mission-control-escalated
# fleet-streamjson.sh's own pending-age default, which the owner's alarm uses.
ALARM_DEFAULT=900

help_text() {
  cat <<'HELP'
mc-escalate.sh — the session-keeper's escalation watcher: what a program's
mission control has left unanswered goes one level up, to the hub mission
control and then to the operator, with no model in the path.

Usage:
  mc-escalate.sh scan --program <p> [--now <epoch>] [--pane <file>]
  mc-escalate.sh            (the watcher form: the program from
                             PLANWRIGHT_MC_PROGRAM, as scripts/mc-watch.sh
                             runs it)
      --pane reads the mission control's pane from a file instead of
      finding and capturing its tmux pane.

WHAT IT RAISES. Two things, each held against
mission_control_escalation_window (W):
  a request   a permission or question request of a live stream-json worker
              the launcher records for this program (mission-control-launch.sh
              list), still pending in its journal. Its age counts from its
              latest receipt (a re-asked request starts again, where the
              owner's own alarm keeps its first receipt), against
              PLANWRIGHT_STREAMJSON_PENDING_AGE read and defaulted as
              scripts/fleet-streamjson.sh reads it: the hub hears it at that
              age plus W, the operator at that age plus 2W. A worker with
              neither pidfile left is the keeper's alarm scan's to settle,
              never raised here.
  the dialog  this program's mission control showing an open dialog in its
              tmux pane: a permission prompt, a select menu, or auto mode's
              own confirmation after blocked actions (kind auto-mode), which
              shows in the pane but not over Remote Control. A dialog is open
              when its signature has no input prompt, idle anchor or busy
              marker below it (scripts/mc-session-pane.sh). The hub hears it
              once one dialog (the same session, the same dialog text, the
              side panel cutting into it or not) has been
              open W, the operator at 2W. Its first sight, session, digest and kind
              are kept under <runtime>/escalate/self; a different session or
              dialog starts a fresh hold, and a pane that shows none drops it.
              A dialog scripts/mc-pane-answer.sh cannot bind, or one whose
              options offer no label that relay takes, is raised with word
              to answer it at its pane rather than through that relay.
The session is this user's claude process whose last two arguments are
`/planwright:mission-control <program>`, exactly one of them; its pane is
the tmux pane whose process is that one or an ancestor of it. None found
reads `absent` and more than one `ambiguous`; neither raises a dialog (a
request is still raised).

THE LEVELS. The hub is mission_control_escalation_hub, when its holder
(scripts/mc-handover.sh holder) reads live: it hears an escalation as one
event in its own store (scripts/mc-event.sh), kind
mission-control-escalated, subject the worker or this program, which its
wake delivers. The hub's part is to reach the stuck mission control or the
operator; the event names no request content. With the knob `none`, set to
this program, a hub that is not live, or a hub store that refuses the
event, the first level goes straight to the operator. The operator hears it
through the notification seam (fleet-attention.sh notify, keyed per
escalation), so a push is only as good as the notification_channel the
operator chose, and the line names that channel. Each level is recorded in
<runtime>/escalate/sent as it is raised, never twice, and dropped once its
request is no longer pending or its dialog closes; what a pass could not
read keeps its record. One pass runs at a time; a second, or one while
scripts/mc-pane-answer.sh delivers an answer, prints `busy`.

Output, one line each, tab separated:
  request <worker> <request id> <age> owner|hub|operator
  self dialog|auto-mode|clear|absent|ambiguous|unreadable <seconds held> owner|hub|operator [<pane>]
  escalated hub <subject>
  escalated operator <subject> <channel>
  busy

Exit codes: 0 scanned (or busy); 1 a store, knob, the launcher's list, a
journal, the pane or an escalation that failed (once a scan has started,
the rest is still scanned and raised); 2 usage; 3 the program is not
configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-escalate.sh scan --program <p> [--now <epoch>] [--pane <file>]"
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- scan --program "$PLANWRIGHT_MC_PROGRAM"
fi
[ $# -ge 1 ] || usage
verb=$1
shift
[ "$verb" = scan ] || usage
PROGRAM=""
NOW_RAW=""
PANE_FILE=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --pane)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) PROGRAM=$2 ;;
        --now) NOW_RAW=$2 ;;
        --pane) PANE_FILE=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$PROGRAM" ] || usage
[ -z "$PANE_FILE" ] || { [ -f "$PANE_FILE" ] && [ -r "$PANE_FILE" ]; } || mc_usage_fail "cannot read the pane file $(sanitize_printable "$PANE_FILE")"
mc_now_arg "$NOW_RAW"
mc_require_program "$PROGRAM"

# shellcheck disable=SC2329 # mc_knob calls it by name
parse_hub() {
  [ "$1" = none ] || mc_valid_program "$1" || return 1
  printf '%s\n' "$1"
}

WINDOW_RAW=$(mc_knob mission_control_escalation_window mc_parse_cadence) || exit 1
WINDOW=$(mc_seconds "$WINDOW_RAW")
HUB=$(mc_knob mission_control_escalation_hub parse_hub) || exit 1
# The owner's threshold, as fleet-streamjson.sh's valid_posnum reads it: a
# positive whole number of at most 15 digits, else its default, warned.
ALARM=${PLANWRIGHT_STREAMJSON_PENDING_AGE:-$ALARM_DEFAULT}
case $ALARM in
  '' | *[!0-9]* | 0*) ALARM='' ;;
esac
if [ -z "$ALARM" ] || [ "${#ALARM}" -gt 15 ]; then
  printf '%s\n' "$prog: warning: PLANWRIGHT_STREAMJSON_PENDING_AGE is not a positive whole number; using ${ALARM_DEFAULT}s" >&2
  ALARM=$ALARM_DEFAULT
fi
FLEET_HOME=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
RUNTIME="$FLEET_HOME/mission-control/$PROGRAM"
ESC_DIR="$RUNTIME/escalate"
for d in "$RUNTIME" "$ESC_DIR"; do
  [ ! -L "$d" ] || mc_fail "refusing the symbolic link $(sanitize_printable "$d")"
done
mkdir -p "$ESC_DIR" 2>/dev/null || mc_fail "cannot create $(sanitize_printable "$ESC_DIR")"
SENT="$ESC_DIR/sent"
SELF="$ESC_DIR/self"

pw_lock_trap_install
pw_lock_try "$ESC_DIR/pass.lock"
case $? in
  0) ;;
  1)
    printf 'busy\n'
    exit 0
    ;;
  *) mc_fail "cannot take the escalation lock" ;;
esac

# plain_file <path>: absent, or a regular file that is not a link.
plain_file() {
  [ ! -L "$1" ] && { [ ! -e "$1" ] || [ -f "$1" ]; }
}
for f in "$SENT" "$SELF"; do
  plain_file "$f" || mc_fail "refusing $(sanitize_printable "$f"): not a regular file"
done

# The hub, when it is not this program and its holder reads live.
HUB_LIVE=""
if [ "$HUB" != none ] && [ "$HUB" != "$PROGRAM" ]; then
  hub_row=$(/bin/bash "$script_dir/mc-handover.sh" holder --program "$HUB" --now "$NOW" 2>/dev/null) || hub_row=""
  case $hub_row in
    *'	live') HUB_LIVE=$HUB ;;
  esac
fi
CHANNEL=$(/bin/sh "$script_dir/resolve-notification-channel.sh" 2>/dev/null) || CHANNEL=unresolved

failed=0
NL='
'
LIVE=""
SENT_NOW=""
if [ -e "$SENT" ]; then
  SENT_NOW=$(cat "$SENT") || mc_fail "cannot read $(sanitize_printable "$SENT")"
fi
# Raising needs a record it can keep: a level sent but not recorded would be
# sent again on every pass.
SENT_OK=1
if ! { : >>"$SENT"; } 2>/dev/null; then
  printf '%s\n' "$prog: cannot write $(sanitize_printable "$SENT"); nothing is raised this pass" >&2
  SENT_OK=0
  failed=1
fi

bounded() { /bin/sh "$script_dir/bounded-run.sh" "$TMUX_BOUND" "$@"; }

sent_has() { # sent_has <key> <level>: the level is already recorded for the key
  case "$NL$SENT_NOW$NL" in
    *"$NL$1	$2$NL"*) return 0 ;;
  esac
  return 1
}

# record <key> <level>: append the level to the record now, so a pass that
# dies later never raises it again.
record() {
  if printf '%s\t%s\n' "$1" "$2" >>"$SENT"; then
    SENT_NOW="$SENT_NOW$NL$1	$2"
    return 0
  fi
  printf '%s\n' "$prog: cannot record the $2 escalation; it may be raised again" >&2
  failed=1
  return 1
}

# notify_key <key>: the notification seam's dedupe token for an escalation.
notify_key() {
  nk=$(printf '%s' "$1" | mc_sha256) || {
    printf '%s\n' "$prog: no SHA-256 tool to key the notification" >&2
    return 1
  }
  printf 'mc-escalate.%s.%s\n' "$PROGRAM" "${nk%"${nk#????????????????}"}"
}

# raise <key> <rank> <subject> <hub text> <operator text>: raise the
# escalation to every level its rank (1 the hub, 2 the operator) reaches
# that it has not reached yet. With no live hub, or a hub that refuses the
# event, rank 1 reaches the operator.
raise() {
  r_key=$1
  r_rank=$2
  r_subject=$3
  r_hub_text=$4
  r_op_text=$5
  LIVE="$LIVE$r_key$NL"
  [ "$r_rank" -ge 1 ] && [ "$SENT_OK" = 1 ] || return 0
  r_hub_ok=0
  if [ -n "$HUB_LIVE" ]; then
    if sent_has "$r_key" hub; then
      r_hub_ok=1
    elif mc_event emit --program "$HUB_LIVE" -- "$EVENT_KIND" "$r_subject" "$r_hub_text" >/dev/null; then
      r_hub_ok=1
      record "$r_key" hub
      printf 'escalated\thub\t%s\n' "$r_subject"
    else
      printf '%s\n' "$prog: the hub $HUB_LIVE refused the escalation of $r_subject; the operator hears it instead" >&2
      failed=1
    fi
  fi
  if { [ "$r_rank" -ge 2 ] || [ "$r_hub_ok" = 0 ]; } && ! sent_has "$r_key" operator; then
    if r_tok=$(notify_key "$r_key") && /bin/sh "$script_dir/fleet-attention.sh" notify "$r_op_text" --key "$r_tok" >/dev/null; then
      record "$r_key" operator
      printf 'escalated\toperator\t%s\t%s\n' "$r_subject" "$CHANNEL"
    else
      printf '%s\n' "$prog: the notification seam refused the escalation of $r_subject" >&2
      failed=1
    fi
  fi
}

RANK=0
LEVEL=owner
rank_of() { # rank_of <seconds past the start>: sets RANK (0, 1 or 2) and LEVEL
  if [ "$1" -ge $((2 * WINDOW)) ]; then
    RANK=2 LEVEL=operator
  elif [ "$1" -ge "$WINDOW" ]; then
    RANK=1 LEVEL=hub
  else
    RANK=0 LEVEL=owner
  fi
}

# --- requests ---------------------------------------------------------------
# A source this pass could not read keeps the record of what it raised.
CARRY_ALL_REQUESTS=0
CARRY_WORKERS=""
if ! LIST=$(/bin/bash "$script_dir/mission-control-launch.sh" list 2>/dev/null); then
  printf '%s\n' "$prog: the launcher's list cannot be read; no request is raised this pass" >&2
  failed=1
  CARRY_ALL_REQUESTS=1
  LIST=""
fi
WORKERS=$(printf '%s\n' "$LIST" | P=$PROGRAM awk -F '\t' 'NF && $2 == ENVIRON["P"] { print $1 }')
while IFS= read -r w; do
  [ -n "$w" ] || continue
  mc_valid_handle "$w" || continue
  wdir="$FLEET_HOME/streamjson/$w"
  [ -e "$wdir" ] || [ -L "$wdir" ] || continue
  if [ -L "$wdir" ] || [ ! -d "$wdir" ]; then
    printf '%s\n' "$prog: refusing the worker directory of $(sanitize_printable "$w"): not a plain directory" >&2
    failed=1
    CARRY_WORKERS="$CARRY_WORKERS$w$NL"
    continue
  fi
  # Positively dead: neither pidfile left. The keeper's alarm scan settles it.
  [ -e "$wdir/worker.pid" ] || [ -e "$wdir/supervisor.pid" ] || continue
  journal="$wdir/journal"
  [ -e "$journal" ] || [ -L "$journal" ] || continue
  if [ -L "$journal" ] || [ ! -f "$journal" ] || [ ! -r "$journal" ] \
    || ! rows=$(awk -F '\t' '$4 == "pending" && $1 ~ /^[A-Za-z0-9-]+$/ && length($1) <= 64 {
        s = $3; if ($5 ~ /^[0-9]+$/ && $5 + 0 > s + 0) s = $5; print $1 "\t" s }' "$journal"); then
    printf '%s\n' "$prog: cannot read the journal of $(sanitize_printable "$w")" >&2
    failed=1
    CARRY_WORKERS="$CARRY_WORKERS$w$NL"
    continue
  fi
  while IFS='	' read -r id since; do
    [ -n "$id" ] || continue
    mc_valid_uint "$since" || continue
    age=$((NOW - since))
    [ "$age" -ge 0 ] || age=0
    rank_of $((age - ALARM))
    printf 'request\t%s\t%s\t%s\t%s\n' "$w" "$id" "$age" "$LEVEL"
    short=${id%"${id#????????}"}
    [ -n "$short" ] || short=$id
    raise "request	$w	$id	$since" "$RANK" "$w" \
      "mission control $PROGRAM has left worker $w's request $short unanswered ${age}s, past its own alarm at ${ALARM}s: reach mission control $PROGRAM, or tell the operator" \
      "$PROGRAM mission control: worker $w has waited ${age}s on request $short with no answer"
  done <<EOF
$rows
EOF
done <<EOF
$WORKERS
EOF

# --- the session's own dialog ----------------------------------------------
# read_self: the dialog record through msp_record; an unreadable one fails
# the pass and sets self_unread.
self_unread=0
read_self() {
  msp_record "$SELF"
  if [ $? = 1 ]; then
    printf '%s\n' "$prog: cannot read the dialog record" >&2
    failed=1
    self_unread=1
  fi
  rec_first=$MSP_REC_FIRST rec_sess=$MSP_REC_SESS rec_print=$MSP_REC_PRINT
}
S_STATE=""
S_PANE=""
S_PID=-
S_TEXT=""
have_pane=0
if [ -n "$PANE_FILE" ]; then
  S_TEXT=$(cat "$PANE_FILE")
  have_pane=1
elif PS_TABLE=$(bounded /bin/sh -c "$MSP_PS_CMD" 2>/dev/null); then
  S_PID=$(msp_find "$PROGRAM" "$PS_TABLE")
  case $S_PID in
    absent | ambiguous) S_STATE=$S_PID ;;
    *)
      if PANES=$(bounded tmux list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null) \
        && S_PANE=$(msp_pane_of "$S_PID" "$PS_TABLE" "$PANES") \
        && S_TEXT=$(bounded tmux capture-pane -p -t "$S_PANE" 2>/dev/null); then
        have_pane=1
      else
        S_STATE=unreadable
      fi
      ;;
  esac
else
  S_STATE=unreadable
fi
held=0
LEVEL=owner
if [ "$have_pane" = 1 ]; then
  S_TEXT=$(printf '%s\n' "$S_TEXT" | msp_trim)
  if msp_dialog "$S_TEXT"; then
    S_STATE=$MSP_KIND
    read_self
    first=$rec_first
    if ! mc_valid_uint "$first" || [ "$first" -gt "$NOW" ] || [ "$rec_sess" != "$S_PID" ] || [ "$rec_print" != "$MSP_PRINT" ]; then
      first=$NOW
      printf 'dialog\t%s\t%s\t%s\t%s\n' "$first" "$S_PID" "$MSP_PRINT" "$MSP_KIND" | mc_write "$SELF" || {
        printf '%s\n' "$prog: cannot record the open dialog" >&2
        failed=1
      }
    fi
    held=$((NOW - first))
    rank_of "$held"
    what="its own dialog"
    [ "$S_STATE" != auto-mode ] || what="auto mode's confirmation prompt, which Remote Control does not show"
    how="Ask the operator; record their choice with mc-decide.sh note --program $HUB --shape answer --subject '$PROGRAM dialog $MSP_PRINT' --target <digit> --text <their words>, then deliver it with mc-pane-answer.sh --program $PROGRAM --choice <digit> --decision <entry id> --decided-in $HUB"
    [ "$MSP_BINDABLE" = 1 ] || how="The answer relay cannot bind this dialog (no opening rule on screen, or a line cut off as side-panel text), so the operator answers it at its pane."
    if [ "$MSP_BINDABLE" = 1 ] && ! msp_relayable; then
      how="The answer relay offers this dialog no option (none numbered in order, or none that only answers it), so the operator answers it at its pane."
    fi
    raise "self	$first	$S_PID	$MSP_PRINT" "$RANK" "$PROGRAM" \
      "mission control $PROGRAM has been held ${held}s on $what${S_PANE:+ in tmux pane $S_PANE}; it answers no worker until that is answered. $how" \
      "$PROGRAM mission control has been stuck ${held}s on $what${S_PANE:+ (tmux pane $S_PANE)}"
  else
    S_STATE=clear
    [ ! -e "$SELF" ] || rm -f "$SELF" 2>/dev/null || failed=1
  fi
fi
case $S_STATE in
  unreadable)
    failed=1
    ;;
esac
# A pane not read, or no single session to read, neither opens nor closes
# the hold: the dialog last seen keeps its record until a read pane shows it
# closed or another dialog; an unreadable record keeps whatever it raised.
CARRY_SELF=0
case $S_STATE in
  absent | ambiguous | unreadable)
    read_self
    CARRY_SELF=$self_unread
    ! mc_valid_uint "$rec_first" || LIVE="${LIVE}self	$rec_first	$rec_sess	$rec_print$NL"
    ;;
esac
printf 'self\t%s\t%s\t%s%s\n' "$S_STATE" "$held" "$LEVEL" "${S_PANE:+	$S_PANE}"

# --- the record: what is still live, and what this pass could not read -----
KEPT=$(printf '%s\n' "$SENT_NOW" | LIVE=$LIVE CW=$CARRY_WORKERS CA=$CARRY_ALL_REQUESTS CS=$CARRY_SELF awk -F '\t' '
  BEGIN {
    n = split(ENVIRON["LIVE"], l, "\n"); for (i = 1; i <= n; i++) if (l[i] != "") live[l[i]] = 1
    n = split(ENVIRON["CW"], c, "\n"); for (i = 1; i <= n; i++) if (c[i] != "") carry[c[i]] = 1
  }
  NF >= 2 {
    k = $1; for (i = 2; i < NF; i++) k = k "\t" $i
    keep = (k in live) || ($1 == "request" && (ENVIRON["CA"] == "1" || ($2 in carry))) || ($1 == "self" && ENVIRON["CS"] == "1")
    if (keep && !($0 in seen)) { seen[$0] = 1; print }
  }')
if [ "$KEPT" != "$(cat "$SENT" 2>/dev/null)" ]; then
  if [ -n "$KEPT" ]; then
    printf '%s\n' "$KEPT" | mc_write "$SENT" || failed=1
  else
    rm -f "$SENT" 2>/dev/null || failed=1
  fi
fi
exit "$failed"
