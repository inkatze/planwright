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
#       capability      both | model | effort | none | error
#                       (`error` = the capability probe could not answer, which
#                       is treated as no capability and audited as such)
#       model / effort  the value to APPLY, or `inherit` to apply nothing and
#                       let the launch keep its ambient value
#       model_source    applied | inherit-config | inherit-capability |
#       effort_source   inherit-probe-error — why each dimension came out that
#                       way, so a reader never has to infer it
#
# Exit codes: 0 a plan was printed; 2 usage error, hostile or out-of-grammar
#   input, or a missing unit; 4 a malformed repo-tracked knob (propagated from
#   the resolver chain); 5 broken install (a sibling helper missing). A
#   capability probe that fails is NOT an error — it degrades to inheritance
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

valid_step() {
  case ${1:-} in
    '') return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

valid_attempt() {
  case ${1:-} in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 9 ]
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
valid_step "$STEP" || {
  printf '%s\n' "$me: refusing malformed step: $(sanitize_printable "$STEP" "(unprintable step)")" >&2
  exit 2
}
valid_attempt "$ATTEMPT" || {
  printf '%s\n' "$me: refusing non-numeric attempt: $(sanitize_printable "$ATTEMPT" "(unprintable attempt)")" >&2
  exit 2
}

# --------------------------------------------------------------------------
# Resolve the tier. The engine owns selection, adaptation, clamps, and the
# config-level ledger row; this script consumes its answer rather than
# re-deriving one (the single-resolver discipline, D-5).
# --------------------------------------------------------------------------
adapt_out=$("$ADAPT" resolve "$UNIT" --key "$KEY" --step "$STEP" --attempt "$ATTEMPT")
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

# --------------------------------------------------------------------------
# Probe the backend's advertised tier_control (field 9 of the capability set).
# A probe that cannot answer is treated as NO capability and audited as such,
# never as a dispatch failure (D-10).
# --------------------------------------------------------------------------
CAPABILITY=error
if caps_line=$("$BACKENDS" caps "$BACKEND" 2>/dev/null); then
  probe=$(printf '%s\n' "$caps_line" | awk '{ print $9 }')
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
  inputs="key=$KEY;backend=$BACKEND;cap=$CAPABILITY;inherit=$extent;cause=$cause;dim=$dims"
  # The proposed tier is what the policy resolved; the resolved cells are what
  # the launch actually carries, per dimension — `inherit` where the backend
  # could not set it. Clamp cells are `-`: this layer applies no clamp, the
  # engine owns those.
  "$LEDGER" append "$UNIT" "$STEP" "$ATTEMPT" inherit \
    "$RES_MODEL" "$RES_EFFORT" - - \
    "$APPLY_MODEL" "$APPLY_EFFORT" unit inherit "$inputs" >/dev/null || {
    printf '%s\n' "$me: could not record the inheritance for unit $(sanitize_printable "$UNIT" "(unprintable unit)")" >&2
    exit 2
  }
fi

printf 'key\t%s\n' "$KEY"
printf 'backend\t%s\n' "$BACKEND"
printf 'capability\t%s\n' "$CAPABILITY"
printf 'model\t%s\n' "$APPLY_MODEL"
printf 'effort\t%s\n' "$APPLY_EFFORT"
printf 'model_source\t%s\n' "$MODEL_SOURCE"
printf 'effort_source\t%s\n' "$EFFORT_SOURCE"
