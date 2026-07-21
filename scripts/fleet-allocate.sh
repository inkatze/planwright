#!/bin/sh
# fleet-allocate.sh — the budget-aware model/effort/concurrency ALLOCATION layer
# and the capability-only degrade guard (fleet-autonomy Task 10; D-24, D-25,
# D-26, D-28; REQ-E1.8, REQ-E1.9, REQ-E1.10, REQ-E1.4, REQ-F1.3, REQ-G1.2).
#
# Task 7's fleet-resource-select.sh resolves the BASE per-task-type selection
# (which model/effort/command a unit runs, now overlay-configurable — REQ-E1.8).
# Task 9's fleet-usage-gate.sh maps account-global `/usage` to a rung on the
# monotone restriction ladder (normal -> downshift -> reduce-concurrency ->
# defer-heavy -> defer-all) and derives the current rung from the shared audit
# trail (D-28). This script is the layer BETWEEN them: given the current rung and
# the raw usage signal, it applies the rung's VALUES — which cheaper tier
# `downshift` selects, the concurrency limit per rung — plus per-tier budget caps
# (REQ-E1.9) and the per-unit reservation exemption (REQ-E1.10), producing the
# EFFECTIVE allocation a dispatch actually uses. It is pure deterministic script
# logic over structured inputs: no LLM/API call is ever in the path (REQ-G1.2).
#
# DEGRADE CAPABILITY, NEVER SAFETY (REQ-E1.10, D-25). Every degrade step this
# layer takes reduces only CAPABILITY (a cheaper model, lower effort, fewer
# concurrent workers). It NEVER drops below a full session-grade Claude Code
# worker (Out of scope: lighter-weight-script workers), NEVER relaxes the
# autonomous-safe-decision determinism floor (REQ-G1.2), and NEVER engages
# `--permission-mode auto` (REQ-E1.4). The effective model is always a valid
# session-grade alias, and the `guard` subcommand is the explicit assertion of
# these invariants for a proposed dispatch.
#
# THE RUNG VALUES (REQ-E1.10). Keyed off Task 9's derived rung:
#   normal              base selection, full concurrency.
#   downshift           model capped no more expensive than `fleet_downshift_model`
#                       and effort no higher than `fleet_downshift_effort`.
#   reduce-concurrency  the downshift model/effort cap PLUS the reduced
#                       concurrency limit (`fleet_concurrency_reduced`).
#   defer-heavy         heavy (opus/fable) units are withheld (admit=withheld);
#                       cheaper units still dispatch, downshifted, reduced.
#   defer-all           no unit dispatches (admit=withheld), reserved or not.
# The tier/concurrency VALUES all resolve through the four-layer overlay
# (REQ-G1.5); the shipped defaults preserve today's behavior at `normal`.
#
# PER-TIER BUDGET CAPS (REQ-E1.9). A cap is a per-tier GLOBAL-USAGE THRESHOLD,
# never per-model accounting (the account-global `/usage` signal has no per-model
# breakdown, and REQ-E1.5 forbids a reservation ledger): the more expensive a
# tier, the LOWER the global percentage at which it is withdrawn from ROUTINE
# units, so expensive tiers drop out for routine work before cheaper tiers do.
# The comparison is deterministic `>=` against the raw signal (the max of the
# available windows); caps are INACTIVE when the signal is unavailable. No
# per-model accounting state is written — the cap is a stateless threshold read.
#
# THE RESERVATION EXEMPTION (REQ-E1.10). A unit dispatched `--reserved` (the
# operator's "keep the most capable tier for the genuinely-hardest unit") is
# EXEMPT from `downshift` and `defer-heavy` and from per-tier caps — it runs at
# its base tier through normal-and-high pressure — but is NOT exempt from
# `defer-all` or the reactive wall. A reservation is a preference honored up to
# the fleet-critical rung, not an inviolable floor. The shipped default reserves
# nothing (no `--reserved` = every unit follows the ladder).
#
# THE KILL-SWITCH (REQ-E1.10, REQ-F1.3). When the operator kill-switch
# (fleet_daemon_pause) is engaged, the operator has assumed manual control, so
# allocation reverts to the un-degraded `normal` policy (base selection, full
# concurrency, admit): the ladder stops degrading rather than blocking dispatch.
# A malformed kill-switch config or broken install fails closed (propagated).
#
# Usage:
#   fleet-allocate.sh resolve <task-type> [--reserved]
#       Print the effective allocation as TAB-separated `key<TAB>value` lines:
#         admit        yes | withheld
#         model        <effective model alias>
#         effort        <effective effort>
#         command      <dispatch command>
#         concurrency  <max concurrent workers for the current rung>
#         rung         <current restriction rung>
#         reserved     yes | no
#   fleet-allocate.sh guard <model> [<permission-mode>]
#       The capability-only guard. Exit 0 when <model> is a session-grade alias
#       (fable opus sonnet haiku) AND <permission-mode> (if given) is not `auto`.
#       Exit 3 on a guard violation (a non-session-grade worker, or `auto`).
#
# Exit codes: 0 success; 2 usage error / unknown or hostile task type / unknown
#   model (fail closed, never a silent default); 3 guard violation; 4 malformed
#   repo-tracked knob (resolver hard-fail, propagated) or corrupt ladder state;
#   5 broken install (a sibling helper missing/unrunnable, or a core default
#   malformed). Never fails opaquely.
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

RESOLVER="$script_dir/resolve-config-knob.sh"
SELECT="$script_dir/fleet-resource-select.sh"
GATE="$script_dir/fleet-usage-gate.sh"
KILL="$script_dir/fleet-daemon-gate.sh"

MECHANISM=budget-allocate
TAB=$(printf '\t')

MODEL_VALUES="fable opus sonnet haiku"
EFFORT_VALUES="low medium high"
COMMAND_VALUES="execute-task orchestrate drain"

usage() {
  echo "usage: fleet-allocate.sh resolve <task-type> [--reserved] | guard <model> [<permission-mode>]" >&2
}

# in_enum <value> <space-separated-set>: 0 when <value> is a member of the set.
# `set -f` keeps the unquoted $2 word-split (on IFS) from glob-expanding, so a
# token like `*` is compared literally, never expanded.
in_enum() {
  for _ie in $2; do
    [ "$1" = "$_ie" ] && return 0
  done
  return 1
}

# require_exec <path> <label>: fail-closed broken-install guard for a sibling.
require_exec() {
  if [ ! -x "$1" ]; then
    echo "fleet-allocate: $2 '$1' is missing or not executable — broken install" >&2
    exit 5
  fi
}

# model_cost <alias>: the tier COST index, expensive -> cheap. A higher index is
# CHEAPER, so "the cheaper of two models" is a numeric max and stepping down a
# tier is +1. Returns 1 on an unknown alias (caller validates first).
model_cost() {
  case $1 in
    fable) printf 0 ;;
    opus) printf 1 ;;
    sonnet) printf 2 ;;
    haiku) printf 3 ;;
    *) return 1 ;;
  esac
}

# model_at_cost <index>: the alias for a cost index (the inverse). haiku is the
# cheapest floor; an index past it clamps to haiku.
model_at_cost() {
  case $1 in
    0) printf fable ;;
    1) printf opus ;;
    2) printf sonnet ;;
    *) printf haiku ;;
  esac
}

# cheaper_model <a> <b>: print whichever of two aliases is cheaper — the less
# capable, higher cost index. Used as a downshift clamp `cheaper_model $base
# $cap`: the result is never more capable than the cap (an expensive base is
# clamped down to the cap) and never more capable than the base (a base already
# at or below the cap is kept, never upgraded). When the cap is cheaper than the
# base the result IS cheaper than the base — that is the intended downshift.
cheaper_model() {
  cm_a=$(model_cost "$1") || return 1
  cm_b=$(model_cost "$2") || return 1
  if [ "$cm_a" -ge "$cm_b" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# effort_cost <effort>: low<medium<high, so "the lower of two efforts" is a
# numeric min.
effort_cost() {
  case $1 in
    low) printf 0 ;;
    medium) printf 1 ;;
    high) printf 2 ;;
    *) return 1 ;;
  esac
}

# lower_effort <a> <b>: print whichever effort is lower (a clamp, same shape as
# cheaper_model).
lower_effort() {
  le_a=$(effort_cost "$1") || return 1
  le_b=$(effort_cost "$2") || return 1
  if [ "$le_a" -le "$le_b" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# rung_index <name>: the numeric restriction order (parity with
# fleet-usage-gate.sh). Returns 1 on an unknown/corrupt rung name.
rung_index() {
  case $1 in
    normal) printf 0 ;;
    downshift) printf 1 ;;
    reduce-concurrency) printf 2 ;;
    defer-heavy) printf 3 ;;
    defer-all) printf 4 ;;
    *) return 1 ;;
  esac
}

# tier_of_model <alias>: heavy (fable opus) or cheap (sonnet haiku) — the same
# split fleet-usage-gate.sh's admit uses, so the two agree on what defer-heavy
# withholds.
tier_of_model() {
  case $1 in
    fable | opus) printf heavy ;;
    sonnet | haiku) printf cheap ;;
    *) return 1 ;;
  esac
}

# resolve_enum <key> <values> <fallback>: resolve one knob through the shared
# resolver (four layers, by-layer malformed policy). Propagates 4/5 verbatim.
resolve_enum() {
  re_out=$("$RESOLVER" --key "$1" --type enum --values "$2" --fallback "$3") || exit $?
  printf '%s' "$re_out"
}

# resolve_posint <key> <fallback>: same, for a positive-integer knob.
resolve_posint() {
  rp_out=$("$RESOLVER" --key "$1" --type posint --fallback "$2") || exit $?
  printf '%s' "$rp_out"
}

# cap_for_model <alias>: the per-tier global-usage cap threshold (1-100) at or
# above which the tier is withdrawn from routine units. Expensive tiers ship a
# LOWER threshold. Validated 1-100; a malformed set is a fail-closed config error.
cap_for_model() {
  case $1 in
    fable) cfm_v=$(resolve_posint fleet_cap_fable 55) || exit $? ;;
    opus) cfm_v=$(resolve_posint fleet_cap_opus 70) || exit $? ;;
    sonnet) cfm_v=$(resolve_posint fleet_cap_sonnet 90) || exit $? ;;
    haiku) cfm_v=$(resolve_posint fleet_cap_haiku 100) || exit $? ;;
    *) return 1 ;;
  esac
  if [ "$cfm_v" -lt 1 ] || [ "$cfm_v" -gt 100 ]; then
    echo "fleet-allocate: per-tier cap for '$1' ($cfm_v) is outside 1-100 — refusing an out-of-range cap" >&2
    exit 4
  fi
  printf '%s' "$cfm_v"
}

# global_usage: the account-global usage percentage the caps compare against —
# the MORE restrictive (higher) of the two available `/usage` windows, or the
# literal `unavailable` when neither window is available (caps then inactive).
# A read-only view via fleet-usage-gate.sh (no lock, no transition).
global_usage() {
  gu_out=$("$GATE" signal) || return $?
  gu_s=$(printf '%s\n' "$gu_out" | awk -F "$TAB" '$1 == "session" { print $2; exit }')
  gu_w=$(printf '%s\n' "$gu_out" | awk -F "$TAB" '$1 == "weekly" { print $2; exit }')
  gu_max=unavailable
  for gu_v in "$gu_s" "$gu_w"; do
    case $gu_v in
      "" | unavailable | *[!0-9]*) continue ;;
    esac
    if [ "$gu_max" = unavailable ] || [ "$gu_v" -gt "$gu_max" ]; then gu_max=$gu_v; fi
  done
  printf '%s' "$gu_max"
}

# --- resolve --------------------------------------------------------------

cmd_resolve() {
  reserved=no
  cr_type=""
  # Parse: exactly one task-type positional and an optional --reserved flag.
  while [ "$#" -gt 0 ]; do
    case $1 in
      --reserved)
        reserved=yes
        ;;
      --*)
        echo "fleet-allocate: unknown flag '$(sanitize_printable "$1" "(unprintable flag)")'" >&2
        return 2
        ;;
      *)
        if [ -n "$cr_type" ]; then
          usage
          return 2
        fi
        cr_type=$1
        ;;
    esac
    shift
  done
  [ -n "$cr_type" ] || {
    usage
    return 2
  }

  require_exec "$RESOLVER" "shared knob resolver"
  require_exec "$SELECT" "resource-select helper"
  require_exec "$GATE" "usage-gate helper"
  require_exec "$KILL" "daemon-gate helper"

  # Base selection FIRST (validates the task type: an unknown/hostile type is
  # refused here with a sanitized diagnostic, exit 2 — never a silent default).
  base=$("$SELECT" select "$cr_type") || exit $?
  base_model=$(printf '%s' "$base" | cut -f1)
  base_effort=$(printf '%s' "$base" | cut -f2)
  base_command=$(printf '%s' "$base" | cut -f3)
  # fleet-resource-select's exit-0 contract is a 3-column TSV of valid-enum
  # values. Validate all three fields here so a truncated/corrupt row or an
  # unexpectedly-older helper fails closed as a broken install (exit 5) instead
  # of emitting an empty or invalid effort/command into the allocation. This
  # validates base_model symmetrically with effort/command (not only via the
  # tier derivation below), closing the model-vs-effort/command asymmetry.
  if ! in_enum "$base_model" "$MODEL_VALUES" \
    || ! in_enum "$base_effort" "$EFFORT_VALUES" \
    || ! in_enum "$base_command" "$COMMAND_VALUES"; then
    echo "fleet-allocate: resource-select returned a malformed row (model='$(sanitize_printable "$base_model" "?")' effort='$(sanitize_printable "$base_effort" "?")' command='$(sanitize_printable "$base_command" "?")') — broken or outdated install" >&2
    exit 5
  fi

  # The un-degraded normal policy, resolved once (also the kill-switch answer).
  conc_normal=$(resolve_posint fleet_concurrency_normal 3) || exit $?

  # The kill-switch: engaged -> revert to the normal (un-degraded) policy
  # (REQ-E1.10) rather than the gate's generic "pause the action". A malformed
  # switch / broken install fails closed (its diagnostic surfaced, propagated).
  # The gate emits only stderr + an exit code, so capture the stderr and replay
  # it only on the fail-closed arms.
  kill_err=$("$KILL" "$MECHANISM" 2>&1)
  kill_rc=$?
  case $kill_rc in
    0) ;; # proceed with rung-based allocation
    1)
      echo "fleet-allocate: kill-switch engaged — allocation reverted to the normal (un-degraded) policy" >&2
      emit_alloc yes "$base_model" "$base_effort" "$base_command" "$conc_normal" normal "$reserved"
      return 0
      ;;
    *)
      [ -n "$kill_err" ] && printf '%s\n' "$kill_err" >&2
      exit "$kill_rc" # 2/4/5 fail closed
      ;;
  esac

  # The current rung, derived from the shared audit trail (D-28).
  rung=$("$GATE" rung) || exit $?
  ridx=$(rung_index "$rung") || {
    echo "fleet-allocate: usage-gate returned an unrecognized rung '$(sanitize_printable "$rung" "(unprintable)")'" >&2
    exit 4
  }

  # Admission (REQ-E1.6/E1.10). defer-all withholds everything (reserved too);
  # defer-heavy withholds heavy units unless reserved.
  admit=yes
  base_tier=$(tier_of_model "$base_model") || {
    echo "fleet-allocate: base selection yielded an unknown model '$(sanitize_printable "$base_model" "(unprintable)")'" >&2
    exit 4
  }
  if [ "$rung" = defer-all ]; then
    admit=withheld
  elif [ "$rung" = defer-heavy ] && [ "$base_tier" = heavy ] && [ "$reserved" = no ]; then
    admit=withheld
  fi

  # Effective model/effort. A reserved unit is EXEMPT from downshift and caps
  # (it keeps its base tier through downshift/defer-heavy); it still yields at
  # defer-all via the admission gate above.
  eff_model=$base_model
  eff_effort=$base_effort
  if [ "$reserved" = no ]; then
    # Downshift rung value: cap model/effort no more capable than the downshift
    # tier, for the downshift rung and every heavier rung.
    if [ "$ridx" -ge 1 ]; then
      ds_model=$(resolve_enum fleet_downshift_model "$MODEL_VALUES" sonnet) || exit $?
      ds_effort=$(resolve_enum fleet_downshift_effort "$EFFORT_VALUES" medium) || exit $?
      eff_model=$(cheaper_model "$eff_model" "$ds_model") || exit 4
      eff_effort=$(lower_effort "$eff_effort" "$ds_effort") || exit 4
    fi
    # Per-tier budget caps: withdraw expensive tiers from routine units when the
    # global signal is at/above the tier's cap. Inactive when unavailable.
    gpct=$(global_usage) || exit $?
    if [ "$gpct" != unavailable ]; then
      cap_guard=0
      while [ "$cap_guard" -lt 8 ]; do # bounded: at most 4 tiers to step through
        cap_guard=$((cap_guard + 1))
        capval=$(cap_for_model "$eff_model") || exit $?
        if [ "$gpct" -ge "$capval" ]; then
          emcost=$(model_cost "$eff_model")
          [ "$emcost" -ge 3 ] && break # haiku floor: nothing cheaper to fall to
          eff_model=$(model_at_cost "$((emcost + 1))")
        else
          break
        fi
      done
    fi
  fi

  # Concurrency: reduced at reduce-concurrency and every heavier rung.
  if [ "$ridx" -ge 2 ]; then
    concurrency=$(resolve_posint fleet_concurrency_reduced 1) || exit $?
  else
    concurrency=$conc_normal
  fi

  emit_alloc "$admit" "$eff_model" "$eff_effort" "$base_command" "$concurrency" "$rung" "$reserved"
}

# emit_alloc <admit> <model> <effort> <command> <concurrency> <rung> <reserved>:
# the single structured-output writer, so every path emits the same shape.
emit_alloc() {
  printf 'admit\t%s\n' "$1"
  printf 'model\t%s\n' "$2"
  printf 'effort\t%s\n' "$3"
  printf 'command\t%s\n' "$4"
  printf 'concurrency\t%s\n' "$5"
  printf 'rung\t%s\n' "$6"
  printf 'reserved\t%s\n' "$7"
}

# --- guard ----------------------------------------------------------------

cmd_guard() {
  if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    return 2
  fi
  g_model=$1
  g_mode=${2-}
  # Session-grade floor: the model must be a real Claude Code session alias,
  # never a lighter-weight-script sentinel (Out of scope) or any other token.
  if ! tier_of_model "$g_model" >/dev/null 2>&1; then
    echo "fleet-allocate: guard violation — '$(sanitize_printable "$g_model" "(unprintable model)")' is not a session-grade model alias (fable opus sonnet haiku); degrade never drops below a full session-grade worker" >&2
    return 3
  fi
  # Determinism/permission floor: never `--permission-mode auto` (REQ-E1.4).
  if [ "$g_mode" = auto ]; then
    echo "fleet-allocate: guard violation — '--permission-mode auto' is never engaged by any degrade step (REQ-E1.4)" >&2
    return 3
  fi
  return 0
}

# --- dispatch -------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi
cmd=$1
shift
case "$cmd" in
  resolve) cmd_resolve "$@" ;;
  guard) cmd_guard "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
