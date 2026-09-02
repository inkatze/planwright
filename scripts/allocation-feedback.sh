#!/bin/sh
# allocation-feedback.sh — the ESCALATION FEEDBACK LOOP: at a unit's terminal
# state, decide whether its allocation history is evidence of a chronically
# under-estimated task, and if so record one observation fragment through the
# shared recording helper (model-allocation Task 4; D-11; REQ-F1.2, REQ-E1.1,
# REQ-E1.2).
#
# WHY A SEPARATE SCRIPT (the existing-seam-reuse domain). The nearest seam is
# allocation-adapt.sh, and this script deliberately does NOT extend it: that
# script is the LAUNCH-BOUNDARY resolver, and every line of it answers "what
# tier does this launch use". This runs at the opposite end of a unit's life —
# once, after the last launch, when there is no tier to resolve — and its output
# is an observation, not an allocation. The seam this script does reuse is the
# one that matters: the per-unit allocation ledger (allocation-ledger.sh) as the
# only record it reads, and obs-record.sh as the only way a fragment is written.
# No new store, no new accumulator, no second reader (D-11).
#
# THE TWO FIRING CONDITIONS (REQ-F1.2), evaluated as an OR:
#
#   above-start   the unit's DERIVED final tier is more expensive than its
#                 configured starting tier. It needed more than it was given.
#   threshold     the unit's escalation count over its whole history reached
#                 `allocation_feedback_threshold`. This is the CHURN condition,
#                 and it is why the count is not simply the net displacement: a
#                 unit that climbed twice and was talked back down twice ends at
#                 its starting tier with nothing for `above-start` to see, yet
#                 spent its whole adjustment budget getting there.
#
# TERMINAL STATE IS THE CALLER'S TO REPORT (D-11). Both completion and
# crash-loop disable are terminal, and both record: a unit that crash-looped at
# the top of its ladder is exactly the chronic under-estimate the loop most
# needs. This script does not go looking for the terminal state; it is told,
# through `--terminal`, by whoever owns that transition.
#
# ONCE PER UNIT, LEDGER-MARKED (REQ-F1.2). A successful recording appends a
# `feedback`/`recorded` row to the unit's own ledger, and the presence of that
# row is what makes every later evaluation a no-op. The mark lives in the
# ledger rather than beside the fragment store because the ledger is already the
# unit's authoritative record and is already per-unit locked; a second marker
# file would be a second thing to keep consistent.
#
# THE ORDER IS RECORD, THEN MARK, and the asymmetry is deliberate. Marking first
# would make a crash between the two steps lose the fragment permanently — the
# unit would read as recorded forever with nothing recorded. Recording first
# means the same crash can at worst produce ONE duplicate fragment on the next
# evaluation. A duplicate is noise in a seed pile that is mined by hand; a lost
# one silently defeats the feedback loop. So the loss-shaped failure is the one
# that is engineered out. Within a single evaluation the whole check-derive-
# record-mark sequence is one hold of the unit's lock, so concurrent terminal
# reports of the same unit cannot both record.
#
# WHAT THE FRAGMENT MAY SAY (REQ-F1.2, artifact data hygiene). Every component
# of the text is a validated identity token, an enum value, or a count: the
# spec, the task, the unit, the terminal state, both tiers, the escalation count
# and the threshold. The ledger's `inputs` column — the one place a caller can
# put arbitrary key=value text, and where a worker petition's reason would land
# — is never read into it. There is no path by which worker-authored prose
# reaches a committed artifact.
#
# Usage:
#   allocation-feedback.sh evaluate <unit> --key <selection-key>
#       --terminal <completed|disabled> --scope <scope>
#       [--spec <spec>] [--task <task>] [--obs-dir <dir>]
#
#     <unit> is the ledger's unit identity. `--spec` and `--task` name the
#     fragment's subject; absent, they are derived from the fleet's
#     `<spec>:task-<id>` unit key. A unit key in neither shape with neither flag
#     is REFUSED rather than recorded with invented fields.
#
#     Prints the evaluation as TAB-separated `key<TAB>value` lines:
#       fired         yes | no
#       reason        above-start | threshold | above-start+threshold |
#                     below-thresholds | already-recorded | inherit |
#                     degraded | record-failed
#       terminal      the reported terminal state
#       unit / spec / task    the subject identity
#       start / final the starting and derived final tiers, as <model>/<effort>
#       escalations   applied up-steps over the unit's whole history
#       threshold     the resolved feedback threshold
#       fragment      the recorded fragment's path, or `-`
#
# Exit codes: 0 evaluated (fired or not); 1 the recording helper failed
#   (surfaced, never swallowed — REQ-F1.2); 2 usage error or hostile/
#   out-of-grammar input; 4 a malformed repo-tracked knob (resolver hard-fail,
#   propagated); 5 broken install. A degradation (an unhealthy ledger) is not a
#   failure: it is surfaced, records nothing, and exits 0.
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

for dep in echo-safety.sh allocation-ladder.sh; do
  if [ ! -r "$script_dir/$dep" ]; then
    echo "allocation-feedback: sibling helper '$script_dir/$dep' is missing or not readable — broken install" >&2
    exit 5
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/allocation-ladder.sh
. "$script_dir/allocation-ladder.sh"

RESOLVER="$script_dir/resolve-config-knob.sh"
SELECT="$script_dir/allocation-select.sh"
LEDGER="$script_dir/allocation-ledger.sh"
OBS="$script_dir/obs-record.sh"
ATTENTION="$script_dir/fleet-attention.sh"

TAB=$(printf '\t')

# The fragment's topic token. Cosmetic and renameable (obs-record.sh's slug
# grammar), but stable enough that `/spec-draft`'s seed mining can group these.
SLUG=allocation-escalation

usage() {
  echo "usage: allocation-feedback.sh evaluate <unit> --key <selection-key> --terminal <completed|disabled> --scope <scope> [--spec <spec>] [--task <task>] [--obs-dir <dir>]" >&2
}

require_exec() {
  if [ ! -x "$1" ]; then
    echo "allocation-feedback: $2 '$1' is missing or not executable — broken install" >&2
    exit 5
  fi
}

# valid_key: the ledger's identity charset, mirrored here so a malformed unit is
# refused where the argument enters rather than several sibling calls later.
valid_key() {
  case $1 in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# valid_field: the charset the fragment's spec/task components must satisfy. It
# is obs-record.sh's SCOPE grammar minus the leading-alphanumeric rule, chosen
# because these tokens end up in the same one-line entry: no whitespace, no
# bracket, no control byte, nothing that could tear the `- <date> [<scope>]
# <text>` shape or drive a terminal at render time.
valid_field() {
  case $1 in
    "" | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# valid_scope: obs-record.sh's scope grammar, checked here so an out-of-grammar
# scope is a usage error from this script rather than a helper refusal reported
# as a recording failure.
valid_scope() {
  case $1 in
    "" | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

UNIT=""
KEY=""
TERMINAL=""
SCOPE=""
SPEC=""
TASK=""
OBSDIR=""

parse_args() {
  [ "$#" -ge 1 ] || {
    usage
    exit 2
  }
  UNIT=$1
  shift
  while [ "$#" -gt 0 ]; do
    case $1 in
      --key | --terminal | --scope | --spec | --task | --obs-dir)
        [ "$#" -ge 2 ] || {
          usage
          exit 2
        }
        case $1 in
          --key) KEY=$2 ;;
          --terminal) TERMINAL=$2 ;;
          --scope) SCOPE=$2 ;;
          --spec) SPEC=$2 ;;
          --task) TASK=$2 ;;
          --obs-dir) OBSDIR=$2 ;;
        esac
        shift 2
        ;;
      *)
        echo "allocation-feedback: unknown argument '$(sanitize_printable "$1" "(unprintable argument)")'" >&2
        exit 2
        ;;
    esac
  done

  [ -n "$KEY" ] && [ -n "$TERMINAL" ] && [ -n "$SCOPE" ] || {
    usage
    exit 2
  }

  valid_key "$UNIT" || {
    echo "allocation-feedback: refusing malformed unit '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
    exit 2
  }
  case $TERMINAL in
    completed | disabled) ;;
    *)
      echo "allocation-feedback: '$(sanitize_printable "$TERMINAL" "(unprintable state)")' is not a terminal state (completed | disabled)" >&2
      exit 2
      ;;
  esac
  valid_scope "$SCOPE" || {
    echo "allocation-feedback: refusing scope (must be an identifier token [A-Za-z0-9._-] opening with an alphanumeric, 1-64 bytes)" >&2
    exit 2
  }

  # Derive the fragment's subject from the fleet's `<spec>:task-<id>` unit key
  # when the caller did not name it. A key in neither shape is refused: REQ-F1.2
  # says the fragment NAMES the task and spec, and a fragment naming a task it
  # guessed is worse seed material than no fragment at all.
  if [ -z "$SPEC" ] || [ -z "$TASK" ]; then
    case $UNIT in
      *:task-*)
        [ -n "$SPEC" ] || SPEC=${UNIT%%:task-*}
        [ -n "$TASK" ] || TASK=${UNIT##*:task-}
        ;;
      *)
        echo "allocation-feedback: unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' does not encode <spec>:task-<id>; pass --spec and --task" >&2
        exit 2
        ;;
    esac
  fi
  for pa_f in "$SPEC" "$TASK"; do
    valid_field "$pa_f" || {
      echo "allocation-feedback: refusing spec/task field (must be [A-Za-z0-9._-], 1-64 bytes)" >&2
      exit 2
    }
  done
}

emit() {
  printf 'fired\t%s\n' "$1"
  printf 'reason\t%s\n' "$2"
  printf 'terminal\t%s\n' "$TERMINAL"
  printf 'unit\t%s\n' "$UNIT"
  printf 'spec\t%s\n' "$SPEC"
  printf 'task\t%s\n' "$TASK"
  printf 'start\t%s/%s\n' "$START_MODEL" "$START_EFFORT"
  printf 'final\t%s/%s\n' "$3" "$4"
  printf 'escalations\t%s\n' "$5"
  printf 'threshold\t%s\n' "$THRESHOLD"
  printf 'fragment\t%s\n' "$6"
}

# The unit lock, released through a trap as well as on the happy path, so a
# fail-closed exit cannot leave it held until the stale break. Same shape as
# allocation-adapt.sh's hold, for the same reason: the fatal-signal traps
# re-`exit` rather than returning into the unfinished critical section.
LOCK_TAKEN=no
LOCK_TOKEN=""
take_unit_lock() {
  LOCK_TOKEN=$("$LEDGER" lock "$UNIT") || exit 2
  LOCK_TAKEN=yes
  trap release_unit_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

release_unit_lock() {
  [ "$LOCK_TAKEN" = yes ] || return 0
  LOCK_TAKEN=no
  "$LEDGER" unlock "$UNIT" "$LOCK_TOKEN" 2>/dev/null || true
}

# surface_degradation <detail>: the stderr line is unconditional (that is what
# makes "never silently" true where no channel is configured); the attention
# seam is best effort.
surface_degradation() {
  echo "allocation-feedback: unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' evaluated DEGRADED — $1" >&2
  [ -x "$ATTENTION" ] || return 0
  "$ATTENTION" notify "allocation: feedback for unit $UNIT degraded — $1" >/dev/null 2>&1 || true
}

# mark_seen: 0 when the unit's ledger already carries a feedback mark. Read
# under the caller's lock hold, so the check and the append it guards are one
# critical section.
mark_seen() {
  ms_file=$("$LEDGER" path "$UNIT" 2>/dev/null) || return 1
  [ -r "$ms_file" ] || return 1
  ms_hit=$(awk -F "$TAB" '
    NF == 15 && $6 == "feedback" && $14 == "recorded" { print "1"; exit }
  ' "$ms_file")
  [ "$ms_hit" = 1 ]
}

cmd_evaluate() {
  parse_args "$@"
  require_exec "$RESOLVER" "shared knob resolver"
  require_exec "$SELECT" "selection resolver"
  require_exec "$LEDGER" "allocation ledger"
  require_exec "$OBS" "observation recording helper"

  THRESHOLD=$("$RESOLVER" --key allocation_feedback_threshold --type posint --fallback 2) || exit $?

  # The starting tier: the same configured point the memoryless derivation
  # replays from, so `above-start` compares like with like.
  base=$("$SELECT" select "$KEY") || exit $?
  START_MODEL=$(printf '%s' "$base" | cut -f1)
  START_EFFORT=$(printf '%s' "$base" | cut -f2)

  # A key whose shipped posture is `inherit` has no ladder and no starting tier
  # to have ended above (D-13): the launch kept its ambient values, so there is
  # no allocation history to feed back.
  if [ "$START_MODEL" = inherit ] || [ "$START_EFFORT" = inherit ]; then
    emit no inherit "$START_MODEL" "$START_EFFORT" 0 -
    return 0
  fi

  # Records that cannot be trusted must not become a committed artifact: an
  # unhealthy ledger degrades loudly and records nothing, rather than emitting a
  # fragment derived from a torn or out-of-enum history (REQ-F1.1's posture,
  # applied at this end of the unit's life).
  if ! "$LEDGER" health "$UNIT" 2>/dev/null; then
    surface_degradation "the allocation ledger is unhealthy; no feedback observation was recorded"
    emit no degraded "$START_MODEL" "$START_EFFORT" 0 -
    return 0
  fi

  take_unit_lock

  if mark_seen; then
    release_unit_lock
    emit no already-recorded "$START_MODEL" "$START_EFFORT" 0 -
    return 0
  fi

  derived=$("$LEDGER" derive "$UNIT" "$START_MODEL" "$START_EFFORT") || {
    release_unit_lock
    echo "allocation-feedback: could not derive the tier for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
    exit 2
  }
  FINAL_MODEL=$(printf '%s' "$derived" | cut -f1)
  FINAL_EFFORT=$(printf '%s' "$derived" | cut -f2)
  ESCALATIONS=$(printf '%s' "$derived" | cut -f6)

  # `alloc_cost_cmp` prints 1 when the SECOND tier is the cheaper one, which is
  # exactly "the unit ended above where it started".
  cmp=$(alloc_cost_cmp "$FINAL_MODEL" "$FINAL_EFFORT" "$START_MODEL" "$START_EFFORT") || cmp=0
  above=no
  [ "$cmp" -gt 0 ] && above=yes
  reached=no
  [ "$ESCALATIONS" -ge "$THRESHOLD" ] && reached=yes

  if [ "$above" = no ] && [ "$reached" = no ]; then
    release_unit_lock
    emit no below-thresholds "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" -
    return 0
  fi
  # Quoted: unquoted, `above-start+threshold` reads as arithmetic (SC2100). It
  # is a reason label, not a sum.
  if [ "$above" = yes ] && [ "$reached" = yes ]; then
    reason="above-start+threshold"
  elif [ "$above" = yes ]; then
    reason="above-start"
  else
    reason=threshold
  fi

  # Every component below is a validated identity token, an enum value, or a
  # count derived from the ledger's own structured columns. Nothing here reads
  # the `inputs` column, which is the only place worker-authored text could sit.
  text="allocation-feedback: spec $SPEC, task $TASK (unit $UNIT) reached terminal state $TERMINAL at tier $FINAL_MODEL/$FINAL_EFFORT, having started at $START_MODEL/$START_EFFORT; $ESCALATIONS escalations against a feedback threshold of $THRESHOLD (fired on $reason)."

  # Every value reaches the helper as its own quoted argv element; nothing is
  # interpolated into a command string (REQ-B1.2's posture, and the reason the
  # text may safely carry the unit key).
  set -- --slug "$SLUG" --scope "$SCOPE" --text "$text"
  [ -z "$OBSDIR" ] || set -- "$@" --obs-dir "$OBSDIR"
  # stdout ONLY. Folding the helper's stderr into this capture would put its
  # diagnostic inside `$fragment` on any run that warned without failing, and
  # that value is about to become a ledger field. The helper's own refusal
  # reaches the operator by flowing straight through to our stderr, which is
  # what REQ-F1.2's "surfaced, never dropped" asks for; it is written never to
  # echo raw untrusted input, so it needs no sanitizing on the way.
  if ! fragment=$("$OBS" "$@"); then
    release_unit_lock
    echo "allocation-feedback: the observation recording helper refused to record for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' (its own reason is above); no ledger mark was written, so this unit stays retryable" >&2
    emit no record-failed "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" -
    exit 1
  fi

  # The UID is the fragment's stable citation handle (`obs:<uid>`), so the mark
  # row carries it rather than the whole path: a path is relative to whatever
  # store the caller named, and the UID is not.
  uid=${fragment##*/}
  uid=${uid%.md}
  uid=${uid##*-}
  case $uid in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) uid=unknown ;;
  esac

  # The mark. Its tier columns carry the two tiers the fragment names, so the
  # ledger alone answers "why was this unit recorded" without the fragment in
  # hand. The attempt is `0` — the ledger's count grammar admits it and this row
  # belongs to no attempt: the identity that matters here is the unit.
  PLANWRIGHT_ALLOC_LOCK_HELD="$UNIT" "$LEDGER" append "$UNIT" - 0 feedback \
    "$START_MODEL" "$START_EFFORT" - - "$FINAL_MODEL" "$FINAL_EFFORT" \
    unit recorded "terminal=$TERMINAL;reason=$reason;escalations=$ESCALATIONS;threshold=$THRESHOLD;obs=$uid" \
    >/dev/null || {
    # The fragment is already published and cannot be unpublished, so a failed
    # mark is reported as what it is: the recording happened, and the next
    # evaluation of this unit may duplicate it.
    echo "allocation-feedback: recorded $fragment but could not mark the ledger for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' — a later evaluation may record a duplicate" >&2
    release_unit_lock
    emit yes "$reason" "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" "$fragment"
    exit 1
  }

  release_unit_lock
  emit yes "$reason" "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" "$fragment"
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift
case "$cmd" in
  evaluate) cmd_evaluate "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
