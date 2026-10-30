#!/usr/bin/env bash
# mc-decide.sh — a mission-control program's decisions: the
# decided-by-mission-control record and its reasons grammar, the calibration
# ledger over it, the operator's repeats noted for scripts/mc-proposals.sh,
# and the interruption and settled-share measures. Every entry lands in the
# knowledge base's decisions log (scripts/mc-kb.sh).
#
# `mc-decide.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-decide
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

CLASSES="auto-applicable agent-resolvable needs-sign-off hygiene"
ROUTES="human-gate fork hard-disqualifier reserved-proposal"
SHAPES="correction manual answer"

help_text() {
  cat <<'HELP'
mc-decide.sh — a mission-control program's decisions, kept in its knowledge
base's decisions log (scripts/mc-kb.sh).

A decision class is the autonomous-safe-decision bucket a decision maps
onto: auto-applicable, agent-resolvable, needs-sign-off, or hygiene (the
routine operational hygiene doctrine/autonomous-safe-decision.md names).
A decision reaches the operator only by a route: human-gate, fork (one the
record and the sources cannot settle), hard-disqualifier, or
reserved-proposal; or because its class is ask-first. Every other decision
is taken, logged as decided by mission control, and shown for review.

The reasons grammar: each entry this script writes carries grounds
  <reason> <class> <rules>: <text>
reason   settled (taken), ask-first or a route (asked), revoke or confirm
         (the operator's verdict on an entry), or correction, manual or
         answer (a repeat noted for the proposal detector)
class    a decision class, or `-`
rules    the comma-separated rule-store ids the decision acts under, or
         `-`; the self-audit (scripts/mc-audit.sh) flags an act on an
         active rule's subject that does not cite that rule
Entries outside the grammar are someone else's: the ledger, the measures
and the repeat detector skip them, and the self-audit counts them as acts
citing no rule.

Calibration: an operator's revoke of a settled decision lowers its class to
ask-first; mission_control_calibration_restore confirmations of the class's
decisions since the latest revoke restore it.

Usage:
  mc-decide.sh decide --program <p> --subject <s> --act <a> --grounds <g>
      (--class <c> | --route <r>) [--class <c>] [--rule <id>]...
      [--target <t>] [--duty <id>]
      record a decision. Prints decided<TAB><entry id><TAB><class> when
      it is taken, ask<TAB><reason><TAB><entry id> when it goes to the
      operator. A decision of a duty in shadow (scripts/mc-shadow.sh) is
      written to the would-have log instead and prints
      would-have<TAB><entry id>.
  mc-decide.sh revoke --program <p> <entry id> [--grounds <g>]
  mc-decide.sh confirm --program <p> <entry id>
      the operator's verdict: a revoke names a settled decision not yet
      revoked; a confirmation names a settled or ask-first decision
      neither revoked nor confirmed
  mc-decide.sh note --program <p> --shape <correction|manual|answer>
      --subject <s> --text <t> [--target <t>]
      note an operator correction (the quote), a manual step (the act;
      --target the kebab event it followed) or an answer (--target the
      answer, --subject the question); prints noted<TAB><entry id>
  mc-decide.sh ledger --program <p>
      class<TAB><class><TAB><autonomous|ask-first><TAB><decided>
      <TAB><revoked><TAB><confirmations since the latest revoke>
      <TAB><hit rate> per class; the hit rate is the percent of settled
      decisions not revoked, `-` with none
  mc-decide.sh measures --program <p> [--window <cadence>] [--now <epoch>]
      over the window ending now (default mission_control_measure_window):
      window<TAB><seconds>, decisions<TAB><settled plus asked>,
      interruptions<TAB><asked>, interruptions-per-hour<TAB><n.nn>,
      settled-share<TAB><percent, or - with no decision>

Exit codes: 0 done; 1 refused (an entry not found or not in the state the
verb needs, a duty not armed, a knowledge-base refusal); 2 usage or an
invalid value; 3 the program is not configured.
HELP
}
usage() {
  mc_usage_fail "usage: mc-decide.sh decide|revoke|confirm|note|ledger|measures --program <p> ... (mc-decide.sh --help)"
}
in_list() { # in_list <word> <list>
  case " $2 " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
entries() { mc_kb_entries "$PROGRAM" decisions; }
trap mc_kb_unlock EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# append <log> <args...>: an entry through mc-kb.sh; sets ENTRY_ID.
ENTRY_ID=''
append() {
  ENTRY_ID=$(mc_kb append --program "$PROGRAM" "$@")
  case $? in
    0) ;;
    2) exit 2 ;;
    3) exit 3 ;;
    *) mc_fail "the entry was not written" ;;
  esac
}

# ledger_rows <restore>: the ledger over the decisions log on stdin.
ledger_rows() {
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  R=$1 C=$CLASSES awk -F '\t' "$MC_GROUNDS_AWK"'
    !/^#/ && grounds($6) {
      c = G_CLASS
      if (G_REASON == "settled") decided[c]++
      else if (G_REASON == "revoke") { revoked[c]++; since[c] = 0 }
      else if (G_REASON == "confirm") since[c]++
    }
    END {
      n = split(ENVIRON["C"], cl, " ")
      for (i = 1; i <= n; i++) {
        c = cl[i]
        state = (revoked[c] > 0 && since[c] + 0 < ENVIRON["R"] + 0) ? "ask-first" : "autonomous"
        hit = decided[c] > 0 ? int((decided[c] - revoked[c]) * 100 / decided[c]) : "-"
        printf "class\t%s\t%s\t%d\t%d\t%d\t%s\n", c, state, decided[c], revoked[c], since[c], hit
      }
    }'
}
restore_knob() { mc_knob mission_control_calibration_restore mc_parse_count || exit 1; }

# entry_line <id>: the entry's line, with REVOKED and CONFIRMED set when a
# later revoke or confirmation names it, and REASON and CLASS its grounds'
# (empty outside the grammar).
ENTRY=''
REVOKED=0
CONFIRMED=0
REASON=''
CLASS=''
entry_line() {
  el_all=$(entries) || exit $?
  ENTRY=$(printf '%s\n' "$el_all" | I=$1 awk -F '\t' '$1 == ENVIRON["I"] { print; exit }')
  [ -n "$ENTRY" ] || mc_fail "no decision $1 in the decisions log"
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  el_v=$(printf '%s\n' "$el_all" | I=$1 awk -F '\t' "$MC_GROUNDS_AWK"'
    grounds($6) && $5 == ENVIRON["I"] && G_REASON == "revoke" { r = 1 }
    grounds($6) && $5 == ENVIRON["I"] && G_REASON == "confirm" { c = 1 }
    END { print r + 0, c + 0 }')
  REVOKED=${el_v% *}
  CONFIRMED=${el_v#* }
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  er=$(printf '%s\n' "$ENTRY" | awk -F '\t' "$MC_GROUNDS_AWK"'{ if (grounds($6)) print G_REASON, G_CLASS }')
  REASON=${er% *}
  CLASS=${er#* }
}

# --- verbs -------------------------------------------------------------------

v_decide() {
  subject='' act='' grounds='' class='' route='' target='' duty='' rules=''
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --subject) subject=$2 ;;
      --act) act=$2 ;;
      --grounds) grounds=$2 ;;
      --class) class=$2 ;;
      --route) route=$2 ;;
      --target) target=$2 ;;
      --duty) duty=$2 ;;
      --rule)
        mc_valid_uint "${2#r-}" && [ "${2#r-}" != "$2" ] && [ "${2#r-}" -gt 0 ] || mc_usage_fail "--rule takes a rule-store id, r-<n>"
        rules=${rules:+$rules,}$2
        ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -n "$class" ] || [ -n "$route" ] || mc_usage_fail "a decision names its --class, or the --route that takes it to the operator"
  [ -z "$class" ] || in_list "$class" "$CLASSES" || mc_usage_fail "--class is one of: $CLASSES"
  [ -z "$route" ] || in_list "$route" "$ROUTES" || mc_usage_fail "--route is one of: $ROUTES"
  [ -n "$grounds" ] || mc_usage_fail "--grounds is required: a decision is logged with its grounds"
  mc_require_program "$PROGRAM"

  if [ -n "$duty" ]; then
    mc_valid_kebab "$duty" || mc_usage_fail "--duty takes a duty id"
    mc_duty_armed "$PROGRAM" "$duty" || mc_fail "duty $duty is not armed in program $PROGRAM (not enabled, or off)"
    lifecycle=$(/bin/bash "$script_dir/mc-duties.sh" get "$duty" lifecycle) || mc_fail "the lifecycle of duty $duty does not resolve"
  else
    lifecycle=live
  fi

  reason=${route:-settled}
  if [ -z "$route" ]; then
    # Held to the append, so a revoke cannot land between the class read
    # and the decision taken on it.
    mc_kb_lock "$PROGRAM" verdicts
    restore=$(restore_knob) || exit $?
    all=$(entries) || exit $?
    if printf '%s\n' "$all" | ledger_rows "$restore" \
      | C=$class awk -F '\t' '$2 == ENVIRON["C"] && $3 == "ask-first" { f = 1 } END { exit !f }'; then
      reason=ask-first
    fi
  fi
  full="$reason ${class:--} ${rules:--}: $grounds"
  if [ "$lifecycle" = shadow ]; then
    append would-have --subject "$subject" --act "$act" --target "$target" --grounds "$full" --duty "$duty"
    printf 'would-have\t%s\n' "$ENTRY_ID"
    return 0
  fi
  append decisions --subject "$subject" --act "$act" --target "$target" --grounds "$full" --duty "$duty"
  if [ "$reason" = settled ]; then
    printf 'decided\t%s\t%s\n' "$ENTRY_ID" "$class"
  else
    printf 'ask\t%s\t%s\n' "$reason" "$ENTRY_ID"
  fi
}

v_verdict() { # v_verdict <revoke|confirm> <args...>
  verdict=$1
  shift
  [ $# -ge 1 ] || usage
  id=$1
  shift
  text=''
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --grounds)
        [ "$verdict" = revoke ] || usage
        text=$2
        ;;
      *) usage ;;
    esac
    shift 2
  done
  mc_valid_entry_id decisions "$id" || mc_usage_fail "a decision id is decisions-<YYYYMM>-<n>"
  mc_require_program "$PROGRAM"
  mc_kb_lock "$PROGRAM" verdicts
  entry_line "$id"
  [ "$REVOKED" -eq 0 ] || mc_fail "decision $id is already revoked"
  if [ "$verdict" = revoke ]; then
    [ "$REASON" = settled ] || mc_fail "decision $id was not taken by mission control, so there is nothing to revoke"
    act=revoked
    text=${text:-revoked by the operator}
  else
    case $REASON in
      settled | ask-first) ;;
      *) mc_fail "decision $id carries no decision class to confirm" ;;
    esac
    [ "$CONFIRMED" -eq 0 ] || mc_fail "decision $id is already confirmed"
    act=confirmed
    text='confirmed by the operator'
  fi
  subject=$(printf '%s\n' "$ENTRY" | cut -f 3)
  append decisions --subject "$subject" --act "$act" --target "$id" --grounds "$verdict $CLASS -: $text"
  printf '%s\t%s\t%s\n' "$act" "$id" "$ENTRY_ID"
}

v_note() {
  shape='' subject='' text='' target=''
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --shape) shape=$2 ;;
      --subject) subject=$2 ;;
      --text) text=$2 ;;
      --target) target=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  in_list "$shape" "$SHAPES" || mc_usage_fail "--shape is one of: $SHAPES"
  [ -n "$subject" ] || mc_usage_fail "--subject is required"
  [ -n "$text" ] || mc_usage_fail "--text is required: the quote or the act"
  case $shape in
    manual)
      [ -n "$target" ] || mc_usage_fail "a manual step names the event it followed (--target)"
      mc_valid_kebab "$target" || mc_usage_fail "a manual step's --target is a kebab event name"
      ;;
    answer)
      case $target in
        *[!\ ]*) ;;
        *) mc_usage_fail "an answer names the answer given (--target)" ;;
      esac
      ;;
  esac
  mc_require_program "$PROGRAM"
  append decisions --subject "$subject" --act "$text" --target "$target" --grounds "$shape - -: noted"
  printf 'noted\t%s\n' "$ENTRY_ID"
}

v_ledger() {
  [ $# -eq 0 ] || usage
  mc_require_program "$PROGRAM"
  r=$(restore_knob) || exit $?
  all=$(entries) || exit $?
  printf '%s\n' "$all" | ledger_rows "$r"
}

v_measures() {
  window='' now_raw=''
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --window) window=$2 ;;
      --now) now_raw=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  mc_now_arg "$now_raw"
  if [ -n "$window" ]; then
    secs=$(mc_seconds "$window") || mc_usage_fail "--window takes a cadence: a positive count of s, m, h or d"
  fi
  mc_require_program "$PROGRAM"
  if [ -z "$window" ]; then
    window=$(mc_knob mission_control_measure_window mc_parse_cadence) || exit 1
    secs=$(mc_seconds "$window")
  fi
  all=$(entries) || exit $?
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  printf '%s\n' "$all" | FROM=$(mc_iso $((NOW - secs))) TO=$(mc_iso "$NOW") W=$secs awk -F '\t' "$MC_GROUNDS_AWK"'
    !/^#/ && $2 >= ENVIRON["FROM"] && $2 <= ENVIRON["TO"] && grounds($6) {
      if (G_REASON == "settled") s++
      else if (asked(G_REASON)) a++
    }
    END {
      d = s + a
      printf "window\t%d\ndecisions\t%d\ninterruptions\t%d\n", ENVIRON["W"], d, a
      printf "interruptions-per-hour\t%.2f\n", a * 3600 / ENVIRON["W"]
      if (d > 0) printf "settled-share\t%d\n", int(s * 100 / d + 0.5)
      else print "settled-share\t-"
    }'
}

# --- dispatch ----------------------------------------------------------------

[ $# -ge 1 ] || usage
case $1 in
  --help | -h | help)
    help_text
    exit 0
    ;;
esac
verb=$1
shift
[ $# -ge 2 ] && [ "$1" = --program ] || mc_usage_fail "--program <name> follows the verb"
PROGRAM=$2
shift 2
case $verb in
  decide) v_decide "$@" ;;
  revoke) v_verdict revoke "$@" ;;
  confirm) v_verdict confirm "$@" ;;
  note) v_note "$@" ;;
  ledger) v_ledger "$@" ;;
  measures) v_measures "$@" ;;
  *) usage ;;
esac
