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
# tier does this launch use". This runs at the opposite end of a unit's life,
# once, after the last launch, when there is no tier to resolve, and its output
# is an observation rather than an allocation. The seam this script does reuse
# is the one that matters: the per-unit allocation ledger (allocation-ledger.sh)
# as the only record it reads, and obs-record.sh as the only way a fragment is
# written. No new store, no new accumulator, no second reader (D-11).
#
# THE TWO FIRING CONDITIONS (REQ-F1.2), evaluated as an OR:
#
#   above-start   the unit's derived final LADDER POSITION is more expensive
#                 than its configured starting tier. It needed more than it was
#                 given.
#   threshold     the unit's count of APPLIED up-steps over its whole history
#                 reached `allocation_feedback_threshold`. This is the CHURN
#                 condition, and it is the one the first cannot see: a unit that
#                 climbed twice and was talked back down twice ends exactly
#                 where it started, and because a reversal REFUNDS the
#                 adjustment cap (D-8) it does not even register as budget
#                 spent. The applied-up-step count is the only trace it leaves.
#
# LADDER POSITION, NOT A TIER THE UNIT RAN AT. Both the comparison and the
# recorded "final" value are the unit's position on the ladder, derived by
# replaying its ledger against the configured starting tier. That is
# deliberately not the same as the tier its last launch resolved to: a clamp is
# a budget decision, never a de-escalation (D-8), so a unit clamped down from
# fable to sonnet still climbed to fable and its estimate was still wrong. The
# fragment's prose says "ladder tier" for exactly this reason, and the ledger's
# `last-tier` verb excludes these marks so a degraded relaunch never reads a
# ladder position as a tier a launch used.
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
# file would be a second thing to keep consistent. The guard FAILS CLOSED in
# both of its directions: an unhealthy or unreadable ledger degrades, recording
# nothing and marking nothing, so the unit stays recordable once it is repaired;
# and a store that answers the health verb but then cannot be scanned for the
# mark is "cannot prove unrecorded", which refuses rather than publishing a
# possible duplicate. Neither direction ever answers "no mark" on a read error.
#
# THE ORDER IS RECORD, THEN MARK, and the asymmetry is deliberate. Marking first
# would make a crash between the two steps lose the fragment permanently: the
# unit would read as recorded forever with nothing recorded. Recording first
# means the same crash leaves an unmarked fragment, so the next evaluation
# records again — one extra fragment per crashed attempt, not a bound of one
# overall. A duplicate is noise in a seed pile that is mined by hand; a lost one
# silently defeats the feedback loop, so the loss-shaped failure is the one
# engineered out. Within a single evaluation the whole health-check, mark-check,
# derive, record and mark sequence is one hold of the unit's lock, so concurrent
# terminal reports of the same unit cannot both record.
#
# THE FRAGMENT AND THE MARK HAVE DIFFERENT LIFETIMES, and a caller should know
# it. The mark goes to the cross-spec fleet home; the fragment goes to the host
# repo's own `specs/_observations` (obs-record.sh's D-6), which on a worker means
# a branch. A branch abandoned without merging loses its fragment while the mark
# survives, and the unit then reads as recorded forever. That is the same
# exposure every observation a branch records carries, and it is why the caller
# owns `--obs-dir`: point it at a store that outlives the mark.
#
# WHAT THE FRAGMENT MAY SAY (REQ-F1.2, artifact data hygiene). Every component
# of the text is a validated identity token, an enum value, or a count: the
# spec, the task, the unit, the terminal state, both tiers, the escalation
# count, the threshold, and the reason label. The ledger's `inputs` column, the
# one place a caller can put arbitrary key=value text and where a worker
# petition's reason would land, is never read into it. There is no path by which
# worker-authored prose reaches a committed artifact.
#
# Usage:
#   allocation-feedback.sh evaluate <unit> --key <selection-key>
#       --terminal <completed|disabled> --scope <scope>
#       [--spec <spec>] [--task <task>] [--obs-dir <dir>]
#
#     <unit>       the ledger's unit identity (the store's own key grammar).
#     --key        the allocation-select.sh selection key whose configured row
#                  supplies the STARTING tier the derivation replays from.
#     --terminal   which terminal state the caller is reporting.
#     --scope      obs-record.sh's `[<scope>]` bracket token, the repo the
#                  observation belongs to. Unrelated to the ledger's own `scope`
#                  column, which this script always writes as `unit`.
#     --spec       \  the fragment's subject. Absent, both are derived from the
#     --task       /  fleet's `<spec>:task-<id>` unit key; a unit key in neither
#                  shape with neither flag is REFUSED rather than recorded with
#                  invented fields.
#     --obs-dir    the observations store, passed through to obs-record.sh
#                  (which contains and canonicalizes it). Omitted, the helper's
#                  own cwd-relative default applies, so a caller whose cwd is
#                  not a repo root should always pass this.
#
#     Prints the evaluation as TAB-separated `key<TAB>value` lines:
#       fired         yes | no
#       reason        above-start | threshold | above-start+threshold |
#                     below-thresholds | already-recorded | inherit |
#                     degraded | record-failed | mark-failed
#       terminal      the reported terminal state
#       unit / spec / task    the subject identity
#       start         the configured starting tier, as <model>/<effort>
#       final         the derived final ladder position, or `-` where the
#                     evaluation short-circuited before deriving it
#       escalations   applied up-steps over the unit's whole history, or `-`
#                     where they were not derived
#       threshold     the resolved feedback threshold
#       fragment      the recorded fragment's path, or `-`
#
# Exit codes:
#   0  evaluated (fired or not), including the degraded and already-recorded
#      short-circuits: a degradation is surfaced, records nothing, and is not a
#      failure.
#   1  the fragment could not be recorded (`reason record-failed`, nothing
#      published, the unit stays retryable), OR it was recorded and the ledger
#      mark failed (`reason mark-failed`, `fired yes`, a real fragment path).
#      The two are one code because both mean "this evaluation did not complete
#      cleanly"; `fired` and `reason` are what a caller branches on, because
#      retrying the second WILL duplicate the fragment.
#   2  usage error or hostile/out-of-grammar input, and any ledger, lock, or
#      store failure this script cannot classify (fail closed, records nothing).
#   4  a malformed repo-tracked knob (the shared resolver's hard-fail,
#      propagated verbatim, as are any other codes it chooses to pass through).
#   5  broken install (a sibling helper missing or not executable).
#   129/130/143  killed by HUP/INT/TERM; the lock is released on the way out.
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

# valid_unit: the ledger's identity charset, mirrored here so a malformed unit
# is refused where the argument enters rather than several sibling calls later.
# Narrowed by one rule the store's own grammar does not carry: a LEADING HYPHEN
# is refused, because this value becomes `$1` to six sibling invocations and a
# filename component in the store, and a hyphen-leading token is what a future
# flag parser or an unguarded `find` result reads as an option.
valid_unit() {
  case $1 in
    -* | "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# valid_subject_token: the grammar the fragment's spec and task components must
# satisfy. It is obs-record.sh's scope grammar exactly, leading-alphanumeric
# rule included, because these tokens end up in the same one-line entry: no
# whitespace, no bracket, no control byte, nothing that could tear the
# `- <date> [<scope>] <text>` shape or drive a terminal at render time. The
# leading-alphanumeric rule is also what keeps a bare `.` or `..` out, which is
# the sibling identity grammars' posture and the one that survives this value
# ever being used to shape a path.
valid_subject_token() {
  case $1 in
    "" | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# valid_scope: obs-record.sh's scope grammar, checked here so an out-of-grammar
# scope is a usage error from this script rather than a helper refusal reported
# as a recording failure.
valid_scope() {
  valid_subject_token "$1"
}

# has_control: 0 when the value carries a C0 control byte or DEL. Used on the
# two values that are neither an enum nor an identity token yet still reach a
# TAB-separated output line: the caller's `--obs-dir` and the path the helper
# echoes back from it. One of those bytes would tear this script's own output
# contract, and no legitimate store path carries one.
has_control() {
  hc_raw=$(printf '%s' "$1" | wc -c | tr -d ' ')
  hc_strip=$(printf '%s' "$1" | tr -d '\000-\037\177' | wc -c | tr -d ' ')
  [ "$hc_raw" != "$hc_strip" ]
}

UNIT=""
KEY=""
TERMINAL=""
SCOPE=""
SPEC=""
TASK=""
OBSDIR=""
HAVE_OBSDIR=0

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
          --obs-dir)
            OBSDIR=$2
            HAVE_OBSDIR=1
            ;;
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

  valid_unit "$UNIT" || {
    echo "allocation-feedback: refusing malformed unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' (the ledger's identity charset, no leading hyphen, 1-128 bytes)" >&2
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

  # `--obs-dir` is the one caller-supplied value this script cannot
  # grammar-check, because a directory path legitimately carries `/` and almost
  # any byte; obs-record.sh contains it instead. Two things are still refused
  # HERE. An explicitly EMPTY value, because it is indistinguishable downstream
  # from the flag being omitted, and the difference is whether the fragment
  # lands where the caller named or in a cwd-relative default. And a control
  # byte, because the helper echoes this value back and that echo becomes a
  # field of this script's TAB-separated output.
  if [ "$HAVE_OBSDIR" -eq 1 ]; then
    [ -n "$OBSDIR" ] || {
      echo "allocation-feedback: --obs-dir was given an empty value; omit the flag to use the helper's default store, or name one" >&2
      exit 2
    }
    if has_control "$OBSDIR"; then
      echo "allocation-feedback: refusing an --obs-dir carrying a control byte" >&2
      exit 2
    fi
  fi

  # Derive the fragment's subject from the fleet's `<spec>:task-<id>` unit key
  # when the caller did not name it. Both halves anchor on the FIRST `:task-`,
  # so a key carrying two of them yields a task token that still contains a `:`
  # and is refused by the grammar below, rather than silently naming a subject
  # that matches no real unit.
  if [ -z "$SPEC" ] || [ -z "$TASK" ]; then
    case $UNIT in
      *:task-*)
        [ -n "$SPEC" ] || SPEC=${UNIT%%:task-*}
        [ -n "$TASK" ] || TASK=${UNIT#*:task-}
        ;;
      *)
        echo "allocation-feedback: unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' does not encode <spec>:task-<id>; pass --spec and --task" >&2
        exit 2
        ;;
    esac
  fi
  for pa_f in "$SPEC" "$TASK"; do
    valid_subject_token "$pa_f" || {
      echo "allocation-feedback: refusing a spec/task subject token (must be [A-Za-z0-9._-] opening with an alphanumeric, 1-64 bytes)" >&2
      exit 2
    }
  done
}

# emit <fired> <reason> <final-model|-> <final-effort|-> <escalations|-> <fragment|->
# The `-` values are the UNKNOWN sentinel, not a value: a path that short-
# circuits before deriving the ladder says so rather than echoing the starting
# tier and a zero, which a consumer would read as "this unit never moved".
emit() {
  em_final=$3
  [ "$3" = - ] || em_final="$3/$4"
  printf 'fired\t%s\n' "$1"
  printf 'reason\t%s\n' "$2"
  printf 'terminal\t%s\n' "$TERMINAL"
  printf 'unit\t%s\n' "$UNIT"
  printf 'spec\t%s\n' "$SPEC"
  printf 'task\t%s\n' "$TASK"
  printf 'start\t%s/%s\n' "$START_MODEL" "$START_EFFORT"
  printf 'final\t%s\n' "$em_final"
  printf 'escalations\t%s\n' "$5"
  printf 'threshold\t%s\n' "$THRESHOLD"
  printf 'fragment\t%s\n' "$6"
}

# The unit lock, released through a trap as well as on the happy path, so a
# fail-closed exit cannot leave it held until the stale break. Same shape as
# allocation-adapt.sh's hold, for the same reason: the fatal-signal traps
# re-`exit` rather than returning into the unfinished critical section.
#
# A caller that ALREADY holds this unit's lock says so the way the ledger
# documents, by exporting PLANWRIGHT_ALLOC_LOCK_HELD, and this script honors it
# the way `append` does. Acquiring unconditionally would deadlock against a
# terminal-state owner that is itself a ledger writer: the primitive is not
# reentrant, so the nested acquire would spin out its whole budget and refuse,
# naming contention that was never there.
ALLOC_LOCK_TAKEN=no
ALLOC_LOCK_TOKEN=""
take_unit_lock() {
  # An inherited hold needs no bookkeeping of its own: ALLOC_LOCK_TAKEN stays
  # `no`, so release_unit_lock is already the right no-op, and the ancestor
  # keeps ownership of a lock it never handed over.
  if [ "${PLANWRIGHT_ALLOC_LOCK_HELD:-}" = "$UNIT" ]; then
    return 0
  fi
  ALLOC_LOCK_TOKEN=$("$LEDGER" lock "$UNIT") || {
    echo "allocation-feedback: could not take the per-unit allocation lock for '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
    exit 2
  }
  ALLOC_LOCK_TAKEN=yes
  trap release_unit_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

release_unit_lock() {
  [ "$ALLOC_LOCK_TAKEN" = yes ] || return 0
  ALLOC_LOCK_TAKEN=no
  "$LEDGER" unlock "$UNIT" "$ALLOC_LOCK_TOKEN" 2>/dev/null || true
}

# ledger_append: the mark write, routed through whichever lock this script is
# operating under. The env var is what tells the ledger its caller already holds
# the lock, and it is set for an inherited hold too, since the ancestor's hold
# is just as real as our own.
ledger_append() {
  PLANWRIGHT_ALLOC_LOCK_HELD="$UNIT" "$LEDGER" append "$@"
}

# surface_degradation <detail>: the stderr line is unconditional (that is what
# makes "never silently" true where no channel is configured); the attention
# seam is best effort.
surface_degradation() {
  echo "allocation-feedback: unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' evaluated DEGRADED — $1" >&2
  [ -x "$ATTENTION" ] || return 0
  "$ATTENTION" notify "allocation: feedback for unit $UNIT degraded — $1" >/dev/null 2>&1 || true
}

# mark_seen: the once-per-unit guard, as a TRI-STATE, because the two ways of
# not finding a mark are not the same answer.
#   0  a mark is present
#   1  the unit definitively has no mark (no ledger file yet, or a readable one
#      carrying no mark row)
#   2  the ledger could not be read, so the absence of a mark cannot be proved
# The caller refuses on 2. A guard that answered "no mark" for a read failure
# would fail OPEN, and its failure direction would be the one that publishes a
# duplicate committed artifact on every retry. In practice the health gate above
# catches the common unreadable case first and degrades instead; 2 is the depth
# behind it, for a store that answers the health verb and then cannot be read.
mark_seen() {
  ms_file=$("$LEDGER" path "$UNIT" 2>/dev/null) || return 2
  [ -n "$ms_file" ] || return 2
  # An absent file is a unit with no history, which is a real "no mark". Any
  # other unreadable state is not.
  [ -e "$ms_file" ] || return 1
  [ -r "$ms_file" ] || return 2
  # The verdict is awk's own exit status, so a scan that COMPLETED and found
  # nothing (1) stays distinguishable from a scan that could not run (anything
  # else). Reading it off stdout instead would make an awk that died mid-file
  # indistinguishable from a clean miss.
  awk -F "$TAB" '
    NF == 15 && $6 == "feedback" && $14 == "recorded" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$ms_file" && return 0
  [ "$?" -eq 1 ] || return 2
  return 1
}

cmd_evaluate() {
  parse_args "$@"
  require_exec "$RESOLVER" "shared knob resolver"
  require_exec "$SELECT" "selection resolver"
  require_exec "$LEDGER" "allocation ledger"
  require_exec "$OBS" "observation recording helper"

  # Non-negative, per D-5's pinned numeric grammar for this spec's numeric
  # knobs. `0` therefore means "every terminal unit qualifies on the count
  # condition", the record-everything end of the dial, symmetric with the
  # adjustment cap's `0` meaning "freeze".
  THRESHOLD=$("$RESOLVER" --key allocation_feedback_threshold --type nonnegint --fallback 2) || exit $?

  # The starting tier: the same configured point the memoryless derivation
  # replays from, so `above-start` compares like with like.
  base=$("$SELECT" select "$KEY") || exit $?
  START_MODEL=$(printf '%s' "$base" | cut -f1)
  START_EFFORT=$(printf '%s' "$base" | cut -f2)

  # A key whose shipped posture is `inherit` has no ladder and no starting tier
  # to have ended above (D-13): the launch kept its ambient values, so there is
  # no allocation history to feed back.
  if [ "$START_MODEL" = inherit ] || [ "$START_EFFORT" = inherit ]; then
    emit no inherit - - - -
    return 0
  fi

  # The lock is taken BEFORE the health check, so the verdict that authorizes
  # recording and the derivation it authorizes read the same snapshot. Checking
  # health first would leave a window in which a concurrent writer lands a row
  # the health pass never saw, and `derive` does no health check of its own.
  # This is also the sibling's ordering (allocation-adapt.sh).
  take_unit_lock

  # `health` reports an unhealthy LEDGER as exit 3. Any other non-zero is the
  # store failing to answer at all (an unresolvable fleet home, a broken
  # install), which is not a data degradation and must not be reported as one:
  # a degradation exits 0, and a caller that reads success for a unit whose
  # terminal state will never recur loses the observation permanently.
  health_rc=0
  health_err=$("$LEDGER" health "$UNIT" 2>&1) || health_rc=$?
  case $health_rc in
    0) ;;
    3)
      release_unit_lock
      surface_degradation "the allocation ledger is unhealthy ($(sanitize_printable "$health_err" "(unprintable detail)")); no feedback observation was recorded"
      emit no degraded - - - -
      return 0
      ;;
    *)
      release_unit_lock
      echo "allocation-feedback: could not read the allocation ledger for '$(sanitize_printable "$UNIT" "(unprintable unit)")' (health exit $health_rc): $(sanitize_printable "$health_err" "(unprintable detail)")" >&2
      exit 2
      ;;
  esac

  seen_rc=0
  mark_seen || seen_rc=$?
  case $seen_rc in
    0)
      release_unit_lock
      emit no already-recorded - - - -
      return 0
      ;;
    1) ;;
    *)
      release_unit_lock
      echo "allocation-feedback: could not read the feedback mark for '$(sanitize_printable "$UNIT" "(unprintable unit)")'; refusing rather than risking a duplicate observation" >&2
      exit 2
      ;;
  esac

  derived=$("$LEDGER" derive "$UNIT" "$START_MODEL" "$START_EFFORT") || {
    release_unit_lock
    echo "allocation-feedback: could not derive the tier for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
    exit 2
  }
  FINAL_MODEL=$(printf '%s' "$derived" | cut -f1)
  FINAL_EFFORT=$(printf '%s' "$derived" | cut -f2)
  # Column 6 of the ledger's `derive` output is the applied-up-step count over
  # the unit's whole history (allocation-ledger.sh's `derive` contract).
  ESCALATIONS=$(printf '%s' "$derived" | cut -f6)
  case $ESCALATIONS in
    "" | *[!0-9]*)
      release_unit_lock
      echo "allocation-feedback: the ledger's derivation returned a non-numeric escalation count for '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
      exit 2
      ;;
  esac

  # A comparison error is refused rather than folded into "did not fire": both
  # `test` and `alloc_cost_cmp` report failure the same way a false condition
  # does, and silently answering "no" is the loss-shaped direction.
  cmp=$(alloc_cost_cmp "$FINAL_MODEL" "$FINAL_EFFORT" "$START_MODEL" "$START_EFFORT") || {
    release_unit_lock
    echo "allocation-feedback: could not compare the derived tier against the starting tier for '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
    exit 2
  }
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
  text="allocation-feedback: spec $SPEC, task $TASK (unit $UNIT) reached terminal state $TERMINAL at ladder tier $FINAL_MODEL/$FINAL_EFFORT, having started at $START_MODEL/$START_EFFORT; $ESCALATIONS applied escalations against a feedback threshold of $THRESHOLD (fired on $reason)."

  # Every value reaches the helper as its own quoted argv element; nothing is
  # interpolated into a command string (REQ-B1.2's posture, and the reason the
  # text may safely carry the unit key).
  set -- --slug "$SLUG" --scope "$SCOPE" --text "$text"
  [ "$HAVE_OBSDIR" -eq 1 ] && set -- "$@" --obs-dir "$OBSDIR"
  # stdout ONLY. Folding the helper's stderr into this capture would put its
  # diagnostic inside `$fragment` on any run that warned without failing, and
  # that value is about to become a ledger field. The helper's own refusal
  # reaches the operator by flowing straight through to our stderr, which is
  # what REQ-F1.2's "surfaced, never dropped" asks for.
  if ! fragment=$("$OBS" "$@"); then
    release_unit_lock
    echo "allocation-feedback: the observation recording helper refused to record for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' (its own reason is above); no ledger mark was written, so this unit stays retryable" >&2
    emit no record-failed "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" -
    exit 1
  fi

  # The helper's stdout contract is one path on one line. A value that breaks it
  # cannot be emitted as a field or cited in the ledger, but the fragment IS
  # already published, so the mark still has to land: the once-per-unit
  # invariant outranks the citation, and dropping the mark here would duplicate
  # the fragment on the next evaluation.
  fragment_ok=yes
  if [ -z "$fragment" ] || has_control "$fragment"; then
    echo "allocation-feedback: the recording helper returned a fragment path that is empty or carries a control byte; the fragment is published but cannot be cited" >&2
    fragment_ok=no
  fi

  # The UID is the fragment's stable citation handle (`obs:<uid>`), so the mark
  # row carries it rather than the whole path: a path is relative to whatever
  # store the caller named, and the UID is not.
  uid=unknown
  if [ "$fragment_ok" = yes ]; then
    uid=${fragment##*/}
    uid=${uid%.md}
    uid=${uid##*-}
    case $uid in
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
      *)
        echo "allocation-feedback: could not read an 8-hex UID off '$(sanitize_printable "$fragment" "(unprintable path)")'; the mark will carry obs=unknown and the ledger loses its citation handle" >&2
        uid=unknown
        ;;
    esac
  fi

  # The mark. Its tier columns carry the two tiers the fragment names, so the
  # ledger alone answers "why was this unit recorded" without the fragment in
  # hand; the ledger's own schema comment records that a `feedback` row's tier
  # and scope columns are descriptive rather than a proposal or a movement. The
  # attempt is `0`, which the ledger's count grammar admits and which this
  # schema reads as "belongs to no attempt": the identity that matters here is
  # the unit.
  if ! ledger_append "$UNIT" - 0 feedback \
    "$START_MODEL" "$START_EFFORT" - - "$FINAL_MODEL" "$FINAL_EFFORT" \
    unit recorded "terminal=$TERMINAL;reason=$reason;escalations=$ESCALATIONS;threshold=$THRESHOLD;obs=$uid" \
    >/dev/null; then
    # Release BEFORE the diagnostic: a stderr write that dies on SIGPIPE (a
    # consumer piping this through `head`) would otherwise skip the release and
    # leave the unit's lock held until the stale break.
    release_unit_lock
    echo "allocation-feedback: recorded a fragment for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' but could not mark the ledger; a later evaluation will record a duplicate" >&2
    em_frag=-
    [ "$fragment_ok" = no ] || em_frag=$fragment
    emit yes mark-failed "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" "$em_frag"
    exit 1
  fi

  release_unit_lock
  em_frag=-
  [ "$fragment_ok" = no ] || em_frag=$fragment
  emit yes "$reason" "$FINAL_MODEL" "$FINAL_EFFORT" "$ESCALATIONS" "$em_frag"
  return 0
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
