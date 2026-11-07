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

PANE_LINES=20
TMUX_BOUND=10
ANCESTRY_MAX=32
EVENT_KIND=mission-control-escalated

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
  a request   a permission or question request of a stream-json worker the
              launcher records for this program (mission-control-launch.sh
              list), still pending in its journal. The owner's own alarm
              fires at PLANWRIGHT_STREAMJSON_PENDING_AGE (900s by default,
              the threshold fleet-streamjson.sh alarm-scan uses); the hub
              hears it at that age plus W, the operator at that age plus 2W.
  the dialog  this program's mission control showing an open dialog (a
              permission prompt or a select menu, the shared pane
              vocabulary) in its tmux pane: the hub hears it once the
              dialog has been open W, the operator at 2W. Its first sight
              is kept under <runtime>/escalate/self and dropped once the
              pane no longer shows one.
The session is the claude process whose last two arguments are
`/planwright:mission-control <program>`, exactly one of them; its pane is
the tmux pane whose process is that one or an ancestor of it. None found
reads `absent` and more than one `ambiguous`; neither raises anything (a
request left by an absent session is still raised).

THE LEVELS. The hub is mission_control_escalation_hub: the hub hears an
escalation as one event in its own store (scripts/mc-event.sh), kind
mission-control-escalated, subject `<program>` or `<program>:<worker>`,
which its wake delivers. With the knob `none`, set to this program, or
naming a program no session holds (no holder record under its runtime
directory), there is no hub and the first level goes straight to the
operator. The operator hears it through the notification seam
(fleet-attention.sh notify, keyed per escalation), so a push is only as
good as the notification_channel the operator chose. Each level is raised
once per request or dialog, recorded in <runtime>/escalate/sent and
dropped once the request is no longer pending or the dialog closes.

Output, one line each, tab separated:
  request <worker> <request id> <age> owner|hub|operator
  self dialog|clear|absent|ambiguous|unreadable <seconds held> owner|hub|operator [<pane>]
  escalated hub|operator <subject>

Exit codes: 0 scanned; 1 a store, knob, the launcher's list or an escalation
that failed (the rest are still raised); 2 usage; 3 the program is not
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
ALARM=${PLANWRIGHT_STREAMJSON_PENDING_AGE:-900}
mc_valid_uint "$ALARM" || mc_fail "PLANWRIGHT_STREAMJSON_PENDING_AGE is not a whole number of seconds"
FLEET_HOME=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
RUNTIME=$(mc_runtime "$PROGRAM") || mc_fail "cannot create the runtime directory of program $PROGRAM"
ESC_DIR="$RUNTIME/escalate"
mkdir -p "$ESC_DIR" 2>/dev/null || mc_fail "cannot create $(sanitize_printable "$ESC_DIR")"
SENT="$ESC_DIR/sent"
SELF="$ESC_DIR/self"
for f in "$SENT" "$SELF"; do
  [ ! -L "$f" ] || mc_fail "refusing the symbolic link $(sanitize_printable "$f")"
done

# The hub, when one holds its name and it is not this program.
HUB_LIVE=""
if [ "$HUB" != none ] && [ "$HUB" != "$PROGRAM" ] && [ -f "$FLEET_HOME/mission-control/$HUB/holder" ]; then
  HUB_LIVE=$HUB
fi

failed=0
LIVE=""
NL='
'
SENT_NOW=""
if [ -e "$SENT" ]; then
  SENT_NOW=$(cat "$SENT") || mc_fail "cannot read $(sanitize_printable "$SENT")"
fi

bounded() { /bin/sh "$script_dir/bounded-run.sh" "$TMUX_BOUND" "$@"; }

# sent_has <key> <level>
sent_has() {
  case "$NL$SENT_NOW$NL" in
    *"$NL$1	$2$NL"*) return 0 ;;
  esac
  return 1
}

# notify_key <key>: the notification seam's dedupe token for an escalation.
notify_key() {
  nk=$(printf '%s' "$1" | mc_sha256) || return 1
  printf 'mc-escalate.%s.%s\n' "$PROGRAM" "$(printf '%s' "$nk" | cut -c1-16)"
}

# raise <key> <rank> <subject> <hub text> <operator text>: raise the
# escalation to every level its rank (1 the hub, 2 the operator) reaches
# that it has not reached yet. With no hub, rank 1 reaches the operator.
raise() {
  r_key=$1
  r_rank=$2
  LIVE="$LIVE$r_key$NL"
  [ "$r_rank" -ge 1 ] || return 0
  if [ -n "$HUB_LIVE" ] && ! sent_has "$r_key" hub; then
    if mc_event emit --program "$HUB_LIVE" -- "$EVENT_KIND" "$3" "$4" >/dev/null; then
      SENT_NOW="$SENT_NOW$NL$r_key	hub"
      printf 'escalated\thub\t%s\n' "$3"
    else
      printf '%s\n' "$prog: the hub $HUB_LIVE refused the escalation of $3" >&2
      failed=1
    fi
  fi
  if { [ "$r_rank" -ge 2 ] || [ -z "$HUB_LIVE" ]; } && ! sent_has "$r_key" operator; then
    if r_tok=$(notify_key "$r_key") && /bin/sh "$script_dir/fleet-attention.sh" notify "$5" --key "$r_tok" >/dev/null 2>&1; then
      SENT_NOW="$SENT_NOW$NL$r_key	operator"
      printf 'escalated\toperator\t%s\n' "$3"
    else
      printf '%s\n' "$prog: the notification seam refused the escalation of $3" >&2
      failed=1
    fi
  fi
}

# level <rank>: its name.
level() {
  case $1 in
    0) printf 'owner' ;;
    1) printf 'hub' ;;
    *) printf 'operator' ;;
  esac
}

# rank <seconds past the start> : 0, 1 or 2.
rank() {
  if [ "$1" -ge $((2 * WINDOW)) ]; then
    printf '2'
  elif [ "$1" -ge "$WINDOW" ]; then
    printf '1'
  else
    printf '0'
  fi
}

# --- requests ---------------------------------------------------------------
if ! LIST=$(/bin/bash "$script_dir/mission-control-launch.sh" list 2>/dev/null); then
  printf '%s\n' "$prog: the launcher's list cannot be read; no request is raised this pass" >&2
  failed=1
  LIST=""
fi
WORKERS=$(printf '%s\n' "$LIST" | P=$PROGRAM awk -F '\t' 'NF && $2 == ENVIRON["P"] { print $1 }')
while IFS= read -r w; do
  [ -n "$w" ] || continue
  mc_valid_handle "$w" || continue
  j="$FLEET_HOME/streamjson/$w/journal"
  [ -e "$j" ] || continue
  if [ -L "$j" ] || [ ! -r "$j" ]; then
    printf '%s\n' "$prog: cannot read the journal of $(sanitize_printable "$w")" >&2
    failed=1
    continue
  fi
  rows=$(awk -F '\t' '$4 == "pending" && $1 ~ /^[A-Za-z0-9-]+$/ && length($1) <= 64 && $3 ~ /^[0-9]+$/ { print $1 "\t" $3 }' "$j") || {
    failed=1
    continue
  }
  while IFS='	' read -r id recv; do
    [ -n "$id" ] || continue
    mc_valid_uint "$recv" || continue
    age=$((NOW - recv))
    [ "$age" -ge 0 ] || age=0
    past=$((age - ALARM))
    [ "$past" -ge 0 ] || past=-1
    rk=0
    [ "$past" -lt 0 ] || rk=$(rank "$past")
    printf 'request\t%s\t%s\t%s\t%s\n' "$w" "$id" "$age" "$(level "$rk")"
    short=$(printf '%s' "$id" | cut -c1-8)
    raise "request	$w	$id" "$rk" "$PROGRAM:$w" \
      "mission control $PROGRAM has left worker $w's request $short pending ${age}s, past its own alarm at ${ALARM}s; fleet-streamjson.sh pending $w shows it" \
      "$PROGRAM mission control: worker $w has waited ${age}s on request $short with no answer"
  done <<EOF
$rows
EOF
done <<EOF
$WORKERS
EOF

# --- the session's own dialog ----------------------------------------------
# find_session: from the process list in FS_PS, the pid of the program's
# mission-control claude process, or `absent` / `ambiguous`.
find_session() {
  printf '%s\n' "$FS_PS" | P=$PROGRAM awk '
    {
      if ($1 !~ /^[0-9]+$/ || NF < 5) next
      n = split($3, a, "/")
      if (a[n] != "claude") next
      if ($(NF - 1) != "/planwright:mission-control" || $NF != ENVIRON["P"]) next
      c++; pid = $1
    }
    END { if (c == 0) print "absent"; else if (c > 1) print "ambiguous"; else print pid }'
}

# pane_of <pid>: the tmux pane whose process is <pid> or an ancestor of it.
pane_of() {
  po_panes=$(bounded tmux list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null) || return 1
  {
    printf '%s\n' "$po_panes" | awk -F '\t' 'NF == 2 { print "pane\t" $1 "\t" $2 }'
    printf '%s\n' "$FS_PS" | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print "proc\t" $1 "\t" $2 }'
  } | S=$1 M=$ANCESTRY_MAX awk -F '\t' '
    $1 == "pane" && $2 ~ /^%[0-9]+$/ { pane[$3] = $2 }
    $1 == "proc" { parent[$2] = $3 }
    END {
      p = ENVIRON["S"]
      for (i = 0; i < ENVIRON["M"] + 0 && p != "" && p > 1; i++) {
        if (p in pane) { print pane[p]; exit 0 }
        p = parent[p]
      }
      exit 1
    }'
}

S_STATE=""
S_PANE=""
S_TEXT=""
if [ -n "$PANE_FILE" ]; then
  S_TEXT=$(cat "$PANE_FILE")
  S_STATE='captured'
else
  if FS_PS=$(bounded ps -ww -A -o pid= -o ppid= -o args= 2>/dev/null); then
    sess=$(find_session)
  else
    sess=unreadable
  fi
  case $sess in
    absent | ambiguous | unreadable) S_STATE=$sess ;;
    *)
      if S_PANE=$(pane_of "$sess") && S_TEXT=$(bounded tmux capture-pane -p -t "$S_PANE" 2>/dev/null); then
        S_STATE='captured'
      else
        S_STATE=unreadable
      fi
      ;;
  esac
fi
held=0
srk=0
if [ "$S_STATE" = captured ]; then
  S_TEXT=$(printf '%s\n' "$S_TEXT" | awk 'NF { last = NR } { l[NR] = $0 } END { for (i = 1; i <= last; i++) print l[i] }' | tail -n "$PANE_LINES")
  if selection_prompt_present "$S_TEXT"; then
    S_STATE=dialog
    first=""
    [ ! -f "$SELF" ] || first=$(awk -F '\t' '$1 == "dialog" { print $2; exit }' "$SELF")
    if ! mc_valid_uint "$first" || [ "$first" -gt "$NOW" ]; then
      first=$NOW
      printf 'dialog\t%s\n' "$first" | mc_write "$SELF" || {
        printf '%s\n' "$prog: cannot record the open dialog" >&2
        failed=1
      }
    fi
    held=$((NOW - first))
    srk=$(rank "$held")
    raise "self	$first" "$srk" "$PROGRAM" \
      "mission control $PROGRAM has had its own dialog open ${held}s${S_PANE:+ in tmux pane $S_PANE}; it answers no worker until that dialog is answered" \
      "$PROGRAM mission control has been stuck on its own dialog for ${held}s${S_PANE:+ (tmux pane $S_PANE)}"
  else
    S_STATE=clear
    rm -f "$SELF" 2>/dev/null || failed=1
  fi
fi
case $S_STATE in
  dialog) ;;
  # An unread pane neither opens nor closes the hold: the dialog last seen
  # stays live until a read pane shows it closed.
  absent | ambiguous | unreadable)
    if [ -f "$SELF" ]; then
      first=$(awk -F '\t' '$1 == "dialog" { print $2; exit }' "$SELF")
      ! mc_valid_uint "$first" || LIVE="${LIVE}self	$first$NL"
    fi
    ;;
esac
printf 'self\t%s\t%s\t%s%s\n' "$S_STATE" "$held" "$(level "$srk")" "${S_PANE:+	$S_PANE}"

# --- the record: only what is still live ------------------------------------
KEPT=$(printf '%s\n' "$SENT_NOW" | LIVE=$LIVE awk -F '\t' '
  BEGIN { n = split(ENVIRON["LIVE"], l, "\n"); for (i = 1; i <= n; i++) if (l[i] != "") live[l[i]] = 1 }
  NF >= 2 {
    k = $1; for (i = 2; i < NF; i++) k = k "\t" $i
    if ((k in live) && !($0 in seen)) { seen[$0] = 1; print }
  }')
if [ -n "$KEPT" ]; then
  printf '%s\n' "$KEPT" | mc_write "$SENT" || failed=1
else
  rm -f "$SENT" 2>/dev/null || failed=1
fi
exit "$failed"
