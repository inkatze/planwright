#!/bin/sh
# allocation-apply.sh — the capability-aware APPLICATION half of launch-point
# selection (model-allocation Task 6; D-4, D-10, D-13; REQ-B1.1, REQ-B1.2).
#
# THE CHOOSE/APPLY SPLIT. allocation-select.sh chooses a tier and
# allocation-adapt.sh records the choice against the unit's ledger. Neither
# asks whether the launching backend can actually SET what was chosen — that is
# this script, and the answer is per DIMENSION: a backend that can fix the
# model but not the reasoning effort applies the model and inherits the ambient
# effort. Capability comes from the backend capability contract's
# `tier_control` column, read through orchestrate-backends.sh's `caps`
# accessor; no backend is special-cased by name (D-10).
#
# WHY EVERY INHERITANCE IS RECORDED (REQ-B1.2). The failure this script exists
# to make impossible is a SILENT ambient launch: work that quietly ran at
# whatever the surrounding session happened to be set to, with nothing in the
# record saying so. Inheritance is a legitimate degradation — refusing dispatch
# over a capability gap would turn it into an availability failure — but it is
# never silent. Full inheritance, partial inheritance, and a capability probe
# that ERRORED (treated as no capability) each write their own ledger row.
#
# TWO ROWS, TWO DIFFERENT FACTS. On a launch where the config named a tier and
# the backend cannot carry all of it, the unit's ledger holds two rows, and
# they are not redundant: allocation-adapt.sh's row says what the POLICY
# resolved, and this script's row says what the BACKEND could apply. Reading
# only the first would claim a tier the worker never ran at. Where the config
# itself resolved to the `inherit` sentinel, the engine has already recorded
# the inheritance and this script adds no second row — the shipped default
# therefore costs exactly one row per launch, unchanged from today (D-13).
#
# ARGV DISCIPLINE (D-10, REQ-B1.2). This script decides; it never builds a
# command line. It prints the values a caller splices into its launch as
# DISCRETE argv elements or launch parameters — `--model` and its value as two
# separate arguments — so a resolved value is never interpolated into a command
# string. Callers construct the launch element by element; the shape is:
#
#   [ "$model" = inherit ] || set -- "$@" --model "$model"
#   [ "$effort" = inherit ] || set -- "$@" --effort "$effort"
#
# A UNIT IS REQUIRED. An inheritance with nowhere to be recorded would be
# exactly the silent ambient launch above, so a plan without a unit identity is
# refused rather than answered (fail closed).
#
# Usage:
#   allocation-apply.sh plan --key <selection-key> --backend <backend>
#       --unit <unit> [--step <step>] [--attempt <n>]
#     Print the launch plan as TAB-separated `key<TAB>value` lines:
#       key             the selection key that was resolved
#       backend         the backend the plan was built for
#       admit           yes | withheld — the admission gate's answer, carried
#                       through from the engine. A withheld unit resolves no
#                       tier and must not be launched (exit 3).
#       capability      both | model | effort | none | error | -
#                       (`error` = the capability probe could not answer, which
#                       is treated as no capability and audited as such; `-` =
#                       the probe never ran. That is the withheld plan: the
#                       admission gate answers before the backend is asked, so
#                       the capability is UNKNOWN, not `none`. Reporting `none`
#                       there would assert the backend cannot set a tier, which
#                       nothing established.)
#       model / effort  the value to APPLY, or `inherit` to apply nothing and
#                       let the launch keep its ambient value
#       model_source    applied | inherit-config | inherit-capability |
#       effort_source   inherit-probe-error | withheld — why each dimension
#                       came out that way, so a reader never has to infer it
#
# Exit codes: 0 a plan was printed; 2 usage error, hostile or out-of-grammar
#   input, or a failed ledger write; 3 the unit is WITHHELD by the admission
#   gate (the plan is printed, carrying `admit withheld`, and applies nothing —
#   a caller must not launch); 4 a malformed repo-tracked knob (propagated from
#   the resolver chain); 5 broken install (a sibling helper missing, a
#   capability accessor answering the wrong arity, or a resolver answering
#   without one of the rows this script reads); 6 the allocation store is
#   unreachable, so no launch can be audited. 6 is deliberately its own code:
#   it is the one failure a caller may reasonably degrade past, and collapsing
#   it into 2 would make every rejected argument look like a missing store.
#   A capability probe that fails is NOT an error — it degrades to inheritance
#   and is audited (D-10).
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=allocation-apply

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  printf '%s\n' "$me: cannot resolve the script directory" >&2
  exit 5
}

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || {
  printf '%s\n' "$me: missing sibling helper: echo-safety.sh" >&2
  exit 5
}

ADAPT="$script_dir/allocation-adapt.sh"
LEDGER="$script_dir/allocation-ledger.sh"
BACKENDS="$script_dir/orchestrate-backends.sh"

for helper in "$ADAPT" "$LEDGER" "$BACKENDS"; do
  [ -r "$helper" ] || {
    printf '%s\n' "$me: broken install: missing $(basename "$helper")" >&2
    exit 5
  }
done

# Every sibling is POSIX sh and is invoked through the interpreter rather than
# relying on its exec bit: a `core.fileMode=false` checkout or a tarball
# extraction can leave the bit off, and a launch must not turn that into a
# silent degrade (the same reason offload-dispatch.sh calls its own siblings
# this way). The readability check above is the real broken-install gate.
run_helper() {
  rh_target=$1
  shift
  /bin/sh "$rh_target" "$@"
}

usage() {
  printf '%s\n' "usage: $me plan --key <selection-key> --backend <backend> --unit <unit> [--step <step>] [--attempt <n>]" >&2
}

# A selection key: the anchored lowercase identifier grammar the resolver's key
# set lives inside. Validated HERE, before the key reaches any command, so a
# hostile token is refused rather than interpolated; whether the (well-formed)
# key actually exists is the resolver's answer, not ours, so the key set is not
# duplicated.
valid_key() {
  case ${1:-} in
    '') return 1 ;;
    [!a-z]*) return 1 ;;
    *[!a-z0-9_]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# A backend name: the identifier grammar orchestrate-backends.sh enforces in
# valid_name(). Same reason for checking it here — the name reaches a command.
valid_backend() {
  case ${1:-} in
    '') return 1 ;;
    [!a-z0-9]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# Unit and step identity: the ledger's own key grammar, checked here so a
# malformed one is named by this script rather than surfacing from two helpers
# deep. Step widens it by the `-` sentinel for a launch with no step identity.
valid_unit() {
  case ${1:-} in
    '' | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

valid_step() {
  [ "${1:-}" = - ] && return 0
  valid_unit "${1:-}"
}

# The engine's attempt grammar, mirrored exactly: it refuses a leading zero
# because `01` and `1` would key the same incident under two spellings, and it
# sets no private length bound. Diverging here would push the refusal two
# helpers deep, which is what checking it locally exists to prevent.
valid_attempt() {
  case ${1:-} in
    '' | *[!0-9]*) return 1 ;;
    0[0-9]*) return 1 ;;
  esac
  return 0
}

sub=${1-}
[ "$#" -gt 0 ] && shift
case "$sub" in
  plan) ;;
  '' | help | -h | --help)
    usage
    exit 2
    ;;
  *)
    printf '%s\n' "$me: unknown subcommand: $(sanitize_printable "$sub" "(unprintable subcommand)")" >&2
    exit 2
    ;;
esac

KEY=''
BACKEND=''
UNIT=''
STEP='-'
ATTEMPT='1'

while [ "$#" -gt 0 ]; do
  case $1 in
    --key)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      KEY=$2
      shift 2
      ;;
    --backend)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      BACKEND=$2
      shift 2
      ;;
    --unit)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      UNIT=$2
      shift 2
      ;;
    --step)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      STEP=$2
      shift 2
      ;;
    --attempt)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      ATTEMPT=$2
      shift 2
      ;;
    *)
      printf '%s\n' "$me: unexpected argument: $(sanitize_printable "$1" "(unprintable argument)")" >&2
      exit 2
      ;;
  esac
done

valid_key "$KEY" || {
  printf '%s\n' "$me: refusing malformed selection key: $(sanitize_printable "$KEY" "(unprintable key)")" >&2
  exit 2
}
valid_backend "$BACKEND" || {
  printf '%s\n' "$me: refusing malformed backend name: $(sanitize_printable "$BACKEND" "(unprintable backend)")" >&2
  exit 2
}
# Fail closed rather than answer: a plan with no unit has nowhere to record the
# inheritance it may be about to take, and an unrecorded inheritance is the
# silent ambient launch this script exists to prevent (REQ-B1.2).
[ -n "$UNIT" ] || {
  printf '%s\n' "$me: --unit is required: an inheritance with no unit identity cannot be recorded, and an unrecorded inheritance is a silent ambient launch" >&2
  exit 2
}
valid_unit "$UNIT" || {
  printf '%s\n' "$me: refusing malformed unit: $(sanitize_printable "$UNIT" "(unprintable unit)")" >&2
  exit 2
}
valid_step "$STEP" || {
  printf '%s\n' "$me: refusing malformed step: $(sanitize_printable "$STEP" "(unprintable step)")" >&2
  exit 2
}
if ! valid_attempt "$ATTEMPT"; then
  # The grammar refuses two different things, and the engine spells them apart.
  # Calling `01` non-numeric sends a reader hunting for a character that is not
  # there, so the leading-zero arm says what it actually objects to.
  case $ATTEMPT in
    0[0-9]*)
      printf '%s\n' "$me: refusing attempt $(sanitize_printable "$ATTEMPT" "(unprintable attempt)") — a leading zero is not a count" >&2
      ;;
    *)
      printf '%s\n' "$me: refusing non-numeric attempt: $(sanitize_printable "$ATTEMPT" "(unprintable attempt)")" >&2
      ;;
  esac
  exit 2
fi

# --------------------------------------------------------------------------
# Resolve the tier. The engine owns selection, adaptation, clamps, and the
# config-level ledger row; this script consumes its answer rather than
# re-deriving one (the single-resolver discipline, D-5).
# --------------------------------------------------------------------------
# Probe the store FIRST, so an unreachable one is reported as itself rather
# than as whatever the engine happens to fail with. This is the single
# condition a caller may degrade past, and it must not be confused with a
# rejected argument or a failed write.
alloc_store=$(run_helper "$LEDGER" home 2>/dev/null) || alloc_store=''
# `home` only NAMES the store; a path that cannot be created or written is just
# as unreachable, and it is the shape an operator actually hits (a fleet home
# that is a regular file, a read-only volume). Checking it here is what keeps
# that case on exit 6 instead of surfacing as a generic write failure two
# helpers deep, indistinguishable from a rejected argument. `mkdir -p` on an
# existing store is a no-op, and the store is created on first append anyway.
if [ -z "$alloc_store" ] \
  || ! mkdir -p "$alloc_store" 2>/dev/null \
  || [ ! -w "$alloc_store" ]; then
  printf '%s\n' "$me: the allocation store is unreachable, so no launch can be audited" >&2
  exit 6
fi

adapt_out=$(run_helper "$ADAPT" resolve "$UNIT" --key "$KEY" --step "$STEP" --attempt "$ATTEMPT")
adapt_rc=$?
if [ "$adapt_rc" -ne 0 ]; then
  exit "$adapt_rc"
fi

tier_field() {
  printf '%s\n' "$adapt_out" | awk -F '\t' -v k="$1" '$1 == k { print $2; found = 1 }
    END { if (!found) exit 3 }'
}

RES_MODEL=$(tier_field model) || {
  printf '%s\n' "$me: the resolver returned no model row — broken or outdated install" >&2
  exit 5
}
RES_EFFORT=$(tier_field effort) || {
  printf '%s\n' "$me: the resolver returned no effort row — broken or outdated install" >&2
  exit 5
}
# The PROPOSED tier, for the ledger's proposed columns. The engine reports it
# separately from the resolved tier; writing the resolved value into both would
# make the two columns mean the same thing on this script's rows and a
# different thing on the engine's.
PROP_MODEL=$(tier_field proposed_model) || PROP_MODEL=$RES_MODEL
PROP_EFFORT=$(tier_field proposed_effort) || PROP_EFFORT=$RES_EFFORT

# The ADMISSION gate. A withheld unit resolves no tier at all (the engine
# answers `-` for both dimensions), so there is nothing to apply and nothing
# that may be launched. Treating `-` as a tier would push deferred work past
# the gate at every surface this script serves, which is the opposite of what
# the gate is for — so the plan is printed for the caller to read and the exit
# code refuses the launch outright.
#
# A MISSING admit row fails closed, like the missing model and effort rows
# above and for the same reason: the engine answers all three on this one call,
# so an absent admit is a version-skewed sibling rather than a silence meaning
# `yes`. Defaulting it open would launch exactly the units the gate withheld,
# which is the one direction this script must never fail in.
ADMIT=$(tier_field admit) || {
  printf '%s\n' "$me: the resolver returned no admit row — broken or outdated install" >&2
  exit 5
}
# `admit` is a CLOSED enum, and it is read as one. Testing only for `withheld`
# would send every other token — a version-skewed spelling, a truncated read, a
# torn row — down the admitted path, which is the missing-row fail-open above
# arriving through a value instead of an absence.
case "$ADMIT" in
  yes | withheld) ;;
  *)
    printf '%s\n' "$me: the resolver answered an out-of-enum admit: $(sanitize_printable "$ADMIT" "(unprintable admit)") — broken or outdated install" >&2
    exit 5
    ;;
esac
if [ "$ADMIT" = withheld ]; then
  printf '%s\n' "$me: unit withheld by the admission gate at key $KEY; not launching" >&2
  printf 'key\t%s\n' "$KEY"
  printf 'backend\t%s\n' "$BACKEND"
  printf 'admit\twithheld\n'
  printf 'capability\t-\n'
  printf 'model\tinherit\n'
  printf 'effort\tinherit\n'
  printf 'model_source\twithheld\n'
  printf 'effort_source\twithheld\n'
  exit 3
fi

# --------------------------------------------------------------------------
# Probe the backend's advertised tier_control (field 9 of the capability set).
# A probe that cannot answer is treated as NO capability and audited as such,
# never as a dispatch failure (D-10).
# --------------------------------------------------------------------------
# The accessor's own stderr flows through: a malformed adapter's advertise
# diagnostic is an operator-actionable fact the contract insists is never a
# silent absence, and swallowing it would leave `cause=probe-error` in the
# ledger with nothing saying why.
CAPABILITY=error
if caps_line=$(run_helper "$BACKENDS" caps "$BACKEND"); then
  # Arity is checked before the field is read. A sibling still answering the
  # pre-extension eight-field set would otherwise yield an empty ninth field,
  # which would read as "this backend cannot set a tier" and inherit silently
  # — a version skew wearing a capability gap's clothes. The sibling consumer
  # of this accessor takes the same posture (fleet-liveness.sh).
  # shellcheck disable=SC2086 # deliberate word splitting: that is the count
  set -- $caps_line
  if [ "$#" -ne 9 ]; then
    printf '%s\n' "$me: the capability accessor answered $# field(s), expected 9 — version-skewed install" >&2
    exit 5
  fi
  probe=$9
  case "$probe" in
    both | model | effort | none) CAPABILITY=$probe ;;
    *) CAPABILITY=error ;;
  esac
fi

# can_set <dimension>: 0 when the advertised capability covers it.
can_set() {
  case "$CAPABILITY" in
    both) return 0 ;;
    model) [ "$1" = model ] ;;
    effort) [ "$1" = effort ] ;;
    *) return 1 ;;
  esac
}

# The inheritance reason for a dimension the backend cannot set: an errored
# probe is distinguished from an honest `none` so the ledger says which
# happened — a probe that broke is an operator-actionable fact, an advertised
# `none` is not.
cap_reason() {
  if [ "$CAPABILITY" = error ]; then
    printf 'inherit-probe-error'
  else
    printf 'inherit-capability'
  fi
}

APPLY_MODEL=inherit
MODEL_SOURCE='inherit-config'
if [ "$RES_MODEL" != inherit ]; then
  if can_set model; then
    APPLY_MODEL=$RES_MODEL
    MODEL_SOURCE=applied
  else
    MODEL_SOURCE=$(cap_reason)
  fi
fi

APPLY_EFFORT=inherit
EFFORT_SOURCE='inherit-config'
if [ "$RES_EFFORT" != inherit ]; then
  if can_set effort; then
    APPLY_EFFORT=$RES_EFFORT
    EFFORT_SOURCE=applied
  else
    EFFORT_SOURCE=$(cap_reason)
  fi
fi

# --------------------------------------------------------------------------
# Record the CAPABILITY-driven inheritance, if any. A dimension the config
# itself left as `inherit` is already on the record (the engine wrote that row
# on the way in), so only a dimension the backend could not carry is news.
# --------------------------------------------------------------------------
cap_inherited=no
case "$MODEL_SOURCE" in inherit-capability | inherit-probe-error) cap_inherited=yes ;; esac
case "$EFFORT_SOURCE" in inherit-capability | inherit-probe-error) cap_inherited=yes ;; esac
# A probe that ERRORED is worth a row even when the config resolved to
# `inherit` and nothing was going to be applied anyway. Under the shipped
# default that is the common case, and without this a broken adapter would
# never appear in the audit record at all — the one operator-actionable half
# of an inheritance, permanently invisible.
[ "$CAPABILITY" = error ] && cap_inherited=yes

if [ "$cap_inherited" = yes ]; then
  if [ "$MODEL_SOURCE" = applied ] || [ "$EFFORT_SOURCE" = applied ]; then
    extent=partial
  else
    extent=full
  fi
  if [ "$CAPABILITY" = error ]; then
    cause='probe-error'
  else
    cause=capability
  fi
  # Name the dimensions that inherited, so a reader of the row never has to
  # cross-reference the capability table to learn which half was lost.
  dims=''
  case "$MODEL_SOURCE" in inherit-capability | inherit-probe-error) dims=model ;; esac
  case "$EFFORT_SOURCE" in
    inherit-capability | inherit-probe-error)
      if [ -n "$dims" ]; then dims="$dims,effort"; else dims=effort; fi
      ;;
  esac
  # `cap` records what was advertised; on an errored probe there is no
  # advertised value, so it records the probe outcome instead.
  [ -n "$dims" ] || dims=none
  inputs="key=$KEY;backend=$BACKEND;cap=$CAPABILITY;inherit=$extent;cause=$cause;dim=$dims"
  # The proposed tier is what the policy resolved; the resolved cells are what
  # the launch actually carries, per dimension — `inherit` where the backend
  # could not set it. Clamp cells are `-`: this layer applies no clamp, the
  # engine owns those.
  run_helper "$LEDGER" append "$UNIT" "$STEP" "$ATTEMPT" inherit \
    "$PROP_MODEL" "$PROP_EFFORT" - - \
    "$APPLY_MODEL" "$APPLY_EFFORT" unit inherit "$inputs" >/dev/null || {
    printf '%s\n' "$me: could not record the inheritance for unit $(sanitize_printable "$UNIT" "(unprintable unit)")" >&2
    exit 2
  }
fi

printf 'key\t%s\n' "$KEY"
printf 'backend\t%s\n' "$BACKEND"
printf 'admit\tyes\n'
printf 'capability\t%s\n' "$CAPABILITY"
printf 'model\t%s\n' "$APPLY_MODEL"
printf 'effort\t%s\n' "$APPLY_EFFORT"
printf 'model_source\t%s\n' "$MODEL_SOURCE"
printf 'effort_source\t%s\n' "$EFFORT_SOURCE"

exit 0
