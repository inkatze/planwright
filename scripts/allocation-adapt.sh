#!/bin/sh
# allocation-adapt.sh — the ADAPTATION ENGINE: the launch-boundary resolver that
# turns a unit's configured starting tier, its own allocation ledger, and the
# consumed upstream budget contracts into the tier a launch actually uses
# (model-allocation Task 2; D-1, D-2, D-6, D-8, D-9, D-13; REQ-C1.1, REQ-C1.2,
# REQ-C1.4, REQ-C1.5, REQ-D1.1, REQ-D1.2, REQ-F1.1).
#
# WHERE IT SITS. allocation-select.sh resolves the STARTING tier for a selection
# key (Task 1). This script is the layer above it: it derives the unit's CURRENT
# tier from that starting point plus the unit's ledger, moves it at most one
# ladder step per triggering incident, then clamps the result through the
# consumed budget contracts and records every decision. Its output is a superset
# of fleet-allocate.sh's, so a fleet dispatch reads it as a drop-in.
#
# ADAPTATION SHIPS DARK (D-13). `allocation_adaptation` ships `off`, and with it
# off this script's answer for a fleet task type is byte-identical to
# fleet-allocate.sh's — the equivalence is pinned field by field, across every
# rung and with the signal both present and absent, in
# tests/test-allocation-adapt.sh. Trigger events are inert while it is off. The
# ledger rows still land: they are additive telemetry, explicitly exempt from
# the behavior-preservation claim.
#
# TRIGGERS ARE WORK-SHAPED AND CLOSED (D-2, REQ-C1.2). The allowlist lives in
# allocation-ladder.sh and holds exactly the events D-2 names: a step failure or
# retry, a flailing classification, review-sequence non-convergence, and a
# petition. Anything else — an audit write failure, a config hard-fail, a git or
# backend launch error — is refused at the argument boundary, because no model
# tier fixes infrastructure trouble and counting it would burn the adjustment
# cap. There is no confidence score anywhere in this path: resolution is table
# lookup, config reads, and a replay of the unit's own records.
#
# ONE STEP PER INCIDENT, PER BOUNDARY (D-8). Each event carries an idempotency
# identity — unit, step, attempt, and its INCIDENT class. A failure and the retry
# it caused share an incident, so they collapse to one step; independent
# incidents stack, one step and one row each. An incident already recorded as
# applied (or as a ladder-end no-op) is skipped on re-derivation, which is what
# makes a crash replay converge instead of double-counting. A DENIED incident is
# deliberately re-evaluated at the next boundary: every denial is conditional on
# transient state — an unavailable signal, a degraded clamp read, an exhausted
# cap — so the next launch is entitled to a fresh answer.
#
# THE CLAMPS ARE CONSUMED CONTRACTS, APPLIED WITH THEIR OWN SEMANTICS (D-1, D-8,
# REQ-C1.4). This script reads the restriction rung and the raw usage signal
# through fleet-usage-gate.sh's documented `rung` / `signal` interfaces and the
# cap/downshift VALUES through the shared knob resolver, then applies each per
# its own conditionality:
#
#   - the defer rungs are an ADMISSION decision — a withheld unit is returned as
#     `withheld`, never resolved to a tier;
#   - `downshift` values bind at the `downshift` rung and heavier, never at
#     `normal`;
#   - per-tier caps are active only WHILE THE SIGNAL IS AVAILABLE, and a binding
#     cap moves the proposal to the nearest surviving cheaper model with the
#     EFFORT PRESERVED;
#   - a reserved unit passes through exempt from downshift and caps, and still
#     yields at `defer-all`.
#
# It applies them; it never edits them. REQ-D1.1 keeps the consumed
# fleet-autonomy scripts untouched, so their semantics are re-expressed here
# rather than reached into — and the equivalence test above is the tripwire that
# fails the moment the two could disagree.
#
# ONE DERIVATION PER BOUNDARY (D-6). The replay runs ONCE per `resolve`, into
# shell variables held for the life of that invocation and gone when it exits —
# the within-boundary memoization D-6 allows, and the reason a boundary that
# stacks three events still scans the ledger once rather than three times.
# Recompute-identical is preserved by construction: the memo never outlives the
# boundary, so the next launch re-derives from the records on disk.
#
# A CLAMP IS NOT DE-ESCALATION (D-8). A clamped proposal is recorded as clamped;
# the unit's own ladder position is untouched, so the next boundary proposes from
# where the ladder actually is, and clamping consumes no adjustment budget.
#
# FAIL CLOSED (D-8, REQ-D1.2). An unreadable or unrecognized clamp input
# resolves in the spend-safe direction — escalation denied, downshift values
# applied, the degraded read recorded — and never turns a read error into a
# blocked launch. While the usage signal is unavailable, escalation ABOVE the
# starting tier is denied; a unit already above it HOLDS (no claw-back), and a
# unit below it may still climb back to its starting tier.
#
# NO PARALLEL STUCK STATE (D-9, REQ-C1.5). When a unit cannot escalate — a clamp
# denied it, the cap is exhausted, or it sits at the ladder top — this script
# records the denial or no-op and resolves normally. The existing crash-loop
# backoff, disable threshold, and decision-queue escalation govern from there,
# unchanged; the ledger is what explains WHY escalation was unavailable when
# that escalation reaches a human.
#
# Usage:
#   allocation-adapt.sh resolve <unit> --key <selection-key>
#       [--step <step>] [--attempt <n>] [--event <class>]... [--reserved]
#     Print the effective allocation as TAB-separated `key<TAB>value` lines:
#       admit            yes | withheld
#       model / effort   the RESOLVED tier, or `inherit` at a non-fleet surface
#       command          the dispatch command, or `-` where the key has none
#       concurrency      the rung's concurrency limit
#       rung             the current restriction rung
#       reserved         yes | no
#       adaptation       on | off | suspended
#       proposed_model / proposed_effort   the tier BEFORE the clamps
#       net              net ladder displacement from the starting tier
#       degraded         no | ledger | clamp-input
#   allocation-adapt.sh derive <unit> --key <selection-key>
#     Print the unit's derived tier without recording anything (a read-only view
#     for operators and for `/execute-task`-style callers that only need to know
#     where a unit currently sits).
#
# Exit codes: 0 success; 2 usage error or hostile/out-of-grammar input; 4 a
#   malformed repo-tracked knob (resolver hard-fail, propagated); 5 broken
#   install. Degradations (an unhealthy ledger, an unreadable clamp input) are
#   NOT failures: they resolve, record, surface, and exit 0.
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
    echo "allocation-adapt: sibling helper '$script_dir/$dep' is missing or not readable — broken install" >&2
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
GATE="$script_dir/fleet-usage-gate.sh"
KILL="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
ATTENTION="$script_dir/fleet-attention.sh"

MECHANISM=allocation
TAB=$(printf '\t')

usage() {
  echo "usage: allocation-adapt.sh resolve <unit> --key <selection-key> [--step <step>] [--attempt <n>] [--event <class>]... [--reserved] | derive <unit> --key <selection-key>" >&2
}

require_exec() {
  if [ ! -x "$1" ]; then
    echo "allocation-adapt: $2 '$1' is missing or not executable — broken install" >&2
    exit 5
  fi
}

resolve_enum() {
  re_out=$("$RESOLVER" --key "$1" --type enum --values "$2" --fallback "$3") || exit $?
  printf '%s' "$re_out"
}

resolve_posint() {
  rp_out=$("$RESOLVER" --key "$1" --type posint --fallback "$2") || exit $?
  printf '%s' "$rp_out"
}

resolve_nonnegint() {
  rn_out=$("$RESOLVER" --key "$1" --type nonnegint --fallback "$2") || exit $?
  printf '%s' "$rn_out"
}

# rung_index <name>: the numeric restriction order, in parity with
# fleet-usage-gate.sh's ladder. Returns 1 on an unrecognized rung.
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

# tier_of_model <alias>: heavy or cheap — the same split fleet-usage-gate.sh's
# admission uses, so the two agree on what `defer-heavy` withholds.
tier_of_model() {
  case $1 in
    fable | opus) printf heavy ;;
    sonnet | haiku) printf cheap ;;
    *) return 1 ;;
  esac
}

cap_of() {
  case $1 in
    fable) printf '%s' "$CAP_FABLE" ;;
    opus) printf '%s' "$CAP_OPUS" ;;
    sonnet) printf '%s' "$CAP_SONNET" ;;
    haiku) printf '%s' "$CAP_HAIKU" ;;
    *) return 1 ;;
  esac
}

CAP_FABLE=""
CAP_OPUS=""
CAP_SONNET=""
CAP_HAIKU=""
# resolve_caps: the per-tier cap set, validated once — each 1-100 and the
# cross-knob ordering monotone (fable <= opus <= sonnet <= haiku) so an
# expensive tier can never withdraw LATER than a cheaper one. Same fail-closed
# refusal the consumed contract makes, applied to the same knobs.
resolve_caps() {
  CAP_FABLE=$(resolve_posint fleet_cap_fable 55) || exit $?
  CAP_OPUS=$(resolve_posint fleet_cap_opus 70) || exit $?
  CAP_SONNET=$(resolve_posint fleet_cap_sonnet 90) || exit $?
  CAP_HAIKU=$(resolve_posint fleet_cap_haiku 100) || exit $?
  for rc_v in "$CAP_FABLE" "$CAP_OPUS" "$CAP_SONNET" "$CAP_HAIKU"; do
    if [ "$rc_v" -lt 1 ] || [ "$rc_v" -gt 100 ]; then
      echo "allocation-adapt: a per-tier cap ($rc_v) is outside 1-100 — refusing an out-of-range cap" >&2
      exit 4
    fi
  done
  if [ "$CAP_FABLE" -gt "$CAP_OPUS" ] || [ "$CAP_OPUS" -gt "$CAP_SONNET" ] \
    || [ "$CAP_SONNET" -gt "$CAP_HAIKU" ]; then
    echo "allocation-adapt: per-tier caps are non-monotonic (require fable<=opus<=sonnet<=haiku) — refusing a config that inverts the withdraw ordering" >&2
    exit 4
  fi
}

# global_usage: the account-global percentage the caps compare against — the more
# restrictive (higher) of the two `/usage` windows, or `unavailable` when neither
# is. A read-only view through the gate's documented `signal` interface: no lock,
# no transition, no side effect. A reader that errors or returns garbage IS
# unavailable (REQ-D1.2), never a guessed number.
global_usage() {
  gu_out=$("$GATE" signal 2>/dev/null) || {
    printf unavailable
    return 0
  }
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

# ---------------------------------------------------------------------------
# The clamp composition
# ---------------------------------------------------------------------------
#
# clamp_tier <model> <effort>: apply every consumed contract to a proposal and
# set CL_ADMIT / CL_MODEL / CL_EFFORT / CL_CLAMPS (a comma list of the clamps
# that BOUND, which is what makes composition testable). Reads the resolved
# globals RUNG, RIDX, RESERVED, USAGE.
clamp_tier() {
  CL_MODEL=$1
  CL_EFFORT=$2
  CL_ADMIT=yes
  CL_CLAMPS=""

  # Admission first: the defer rungs are a decision about whether the unit runs
  # at all, evaluated against the PROPOSED tier (an escalation into the heavy
  # band is what `defer-heavy` exists to catch).
  ct_tier=$(tier_of_model "$CL_MODEL") || ct_tier=cheap
  if [ "$RUNG" = defer-all ]; then
    CL_ADMIT=withheld
    CL_CLAMPS="${CL_CLAMPS}defer-all,"
  elif [ "$RUNG" = defer-heavy ] && [ "$ct_tier" = heavy ] && [ "$RESERVED" = no ]; then
    CL_ADMIT=withheld
    CL_CLAMPS="${CL_CLAMPS}defer-heavy,"
  fi

  if [ "$RESERVED" = no ]; then
    # The downshift VALUES, binding at `downshift` and every heavier rung.
    if [ "$RIDX" -ge 1 ]; then
      ct_dm=$(resolve_enum fleet_downshift_model "$ALLOC_MODELS" sonnet) || exit $?
      ct_de=$(resolve_enum fleet_downshift_effort "$ALLOC_EFFORTS" medium) || exit $?
      ct_before="$CL_MODEL/$CL_EFFORT"
      # Clamp each dimension independently: the downshift cap is a ceiling on
      # the model AND on the effort, not a joint tier substitution.
      ct_mr=$(alloc_model_rank "$CL_MODEL") || exit 4
      ct_cr=$(alloc_model_rank "$ct_dm") || exit 4
      [ "$ct_mr" -gt "$ct_cr" ] && CL_MODEL=$ct_dm
      ct_er=$(alloc_effort_rank "$CL_EFFORT") || exit 4
      ct_ce=$(alloc_effort_rank "$ct_de") || exit 4
      [ "$ct_er" -gt "$ct_ce" ] && CL_EFFORT=$ct_de
      [ "$ct_before" = "$CL_MODEL/$CL_EFFORT" ] || CL_CLAMPS="${CL_CLAMPS}downshift,"
    fi
    # Per-tier caps: active only while the signal is available. A binding cap
    # steps to the NEAREST SURVIVING CHEAPER MODEL with the effort preserved.
    if [ "$USAGE" != unavailable ]; then
      resolve_caps
      ct_bound=0
      ct_guard=0
      while [ "$ct_guard" -lt 8 ]; do # bounded: at most four tiers to walk
        ct_guard=$((ct_guard + 1))
        ct_cap=$(cap_of "$CL_MODEL") || exit 4
        [ "$USAGE" -ge "$ct_cap" ] || break
        ct_mr=$(alloc_model_rank "$CL_MODEL") || exit 4
        [ "$ct_mr" -gt 0 ] || break # the haiku floor: nothing cheaper to fall to
        CL_MODEL=$(alloc_model_at $((ct_mr - 1))) || exit 4
        ct_bound=1
      done
      [ "$ct_bound" -eq 0 ] || CL_CLAMPS="${CL_CLAMPS}cap,"
    fi
  else
    CL_CLAMPS="${CL_CLAMPS}reserved-exempt,"
  fi

  CL_CLAMPS=${CL_CLAMPS%,}
  [ -n "$CL_CLAMPS" ] || CL_CLAMPS=none
}

# ---------------------------------------------------------------------------
# Ledger helpers
# ---------------------------------------------------------------------------

# The governance rows queued for the sparse fleet-audit mirror. They are flushed
# AFTER the per-unit lock is released: fleet-audit takes its own (different)
# lock, and keeping the two holds disjoint keeps this critical section short.
MIRROR_QUEUE=""

queue_mirror() {
  MIRROR_QUEUE="$MIRROR_QUEUE$1|$2
"
}

flush_mirror() {
  [ -n "$MIRROR_QUEUE" ] || return 0
  [ -x "$AUDIT" ] || return 0
  fm_ifs=$IFS
  IFS='
'
  for fm_row in $MIRROR_QUEUE; do
    IFS=$fm_ifs
    fm_action=${fm_row%%|*}
    fm_why=${fm_row#*|}
    # A mirror failure is surfaced, never fatal: the AUTHORITATIVE record is the
    # per-unit ledger row, already committed. Losing a dashboard row must not
    # turn a resolved launch into a failed one.
    "$AUDIT" record "$MECHANISM" "$fm_action" "unit-$UNIT" "$fm_why" >/dev/null 2>&1 \
      || echo "allocation-adapt: could not mirror the '$fm_action' governance row into the shared trail" >&2
    IFS='
'
  done
  IFS=$fm_ifs
  MIRROR_QUEUE=""
}

# record <event> <prop-model> <prop-effort> <clamp-model> <clamp-effort>
#        <res-model> <res-effort> <scope> <outcome> <inputs>
record() {
  PLANWRIGHT_ALLOC_LOCK_HELD="$UNIT" "$LEDGER" append "$UNIT" "$STEP" "$ATTEMPT" \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" >/dev/null || {
    # A failed append is an unhealthy ledger by definition: adjustments are
    # already suspended by the time this can matter, and the failure is
    # surfaced rather than swallowed (REQ-F1.1's "never silent").
    echo "allocation-adapt: could not append to the allocation ledger for unit '$(sanitize_printable "$UNIT" "(unprintable unit)")'" >&2
    DEGRADED=ledger
    return 1
  }
  return 0
}

# incident_seen <incident>: 0 when this unit already has a TERMINAL row for the
# (step, attempt, incident) key — applied, or a ladder-end no-op. A prior DENIAL
# is not terminal: it was conditional on transient state, so the next boundary
# re-evaluates it.
incident_seen() {
  is_file=$("$LEDGER" path "$UNIT" 2>/dev/null) || return 1
  [ -r "$is_file" ] || return 1
  is_hit=$(awk -F "$TAB" -v st="$STEP" -v at="$ATTEMPT" -v inc="$1" '
    NF == 15 && $4 == st && $5 == at && ($14 == "applied" || $14 == "no-op") {
      cls = $6
      if (cls == "retry") cls = "step-failure"
      else if (cls == "petition-escalate" || cls == "petition-de-escalate") cls = "petition"
      if (cls == inc) { print "1"; exit }
    }
  ' "$is_file")
  [ "$is_hit" = 1 ]
}

# The unit lock is released through a trap as well as on the happy path: a
# fail-closed `exit` from a malformed knob or an invalid tier would otherwise
# leave the lock held until the stale break, blocking the unit's next launch for
# a minute on what is really a config error. Releasing is idempotent (the
# ledger's `unlock` is an rm), so the trap and the explicit call cannot conflict.
ALLOC_LOCK_TAKEN=no
ALLOC_LOCK_TOKEN=""
take_unit_lock() {
  # `lock` prints the OWNER TOKEN, and the release presents it back: this hold
  # spans several processes (the engine acquires, `append` writes, the engine
  # releases), so ownership cannot be inferred from a pid — it has to be carried.
  ALLOC_LOCK_TOKEN=$("$LEDGER" lock "$UNIT") || exit 2
  ALLOC_LOCK_TAKEN=yes
  trap release_unit_lock EXIT HUP INT TERM
}

release_unit_lock() {
  [ "$ALLOC_LOCK_TAKEN" = yes ] || return 0
  ALLOC_LOCK_TAKEN=no
  "$LEDGER" unlock "$UNIT" "$ALLOC_LOCK_TOKEN" 2>/dev/null || true
}

# surface_degradation <detail>: push the degradation through the existing
# attention seam AND stderr. Best effort on the seam (an absent notification
# channel must not fail a launch); the stderr line is unconditional, which is
# what makes "never silently" true even where no channel is configured.
surface_degradation() {
  echo "allocation-adapt: unit '$(sanitize_printable "$UNIT" "(unprintable unit)")' is launching DEGRADED — $1" >&2
  [ -x "$ATTENTION" ] || return 0
  "$ATTENTION" notify "allocation: unit $UNIT degraded — $1" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# resolve / derive
# ---------------------------------------------------------------------------

UNIT=""
KEY=""
STEP=-
ATTEMPT=1
RESERVED=no
EVENTS=""
DEGRADED=no

parse_args() {
  [ "$#" -ge 1 ] || {
    usage
    exit 2
  }
  UNIT=$1
  shift
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
      --event)
        [ "$#" -ge 2 ] || {
          usage
          exit 2
        }
        # The closed trigger allowlist (REQ-C1.2). A token outside it — an
        # infrastructure failure, a typo, anything hostile — is refused HERE,
        # before it can reach a ledger row or move a tier.
        if ! alloc_event_dir "$2" >/dev/null 2>&1 \
          || [ "$(alloc_event_dir "$2")" = none ]; then
          echo "allocation-adapt: '$(sanitize_printable "$2" "(unprintable event)")' is not a trigger event ($ALLOC_EVENTS_UP $ALLOC_EVENTS_DOWN)" >&2
          exit 2
        fi
        EVENTS="$EVENTS $2"
        shift 2
        ;;
      --reserved)
        RESERVED=yes
        shift
        ;;
      *)
        echo "allocation-adapt: unknown argument '$(sanitize_printable "$1" "(unprintable argument)")'" >&2
        exit 2
        ;;
    esac
  done
  [ -n "$KEY" ] || {
    usage
    exit 2
  }
}

emit() {
  printf 'admit\t%s\n' "$1"
  printf 'model\t%s\n' "$2"
  printf 'effort\t%s\n' "$3"
  printf 'command\t%s\n' "$4"
  printf 'concurrency\t%s\n' "$5"
  printf 'rung\t%s\n' "$6"
  printf 'reserved\t%s\n' "$RESERVED"
  printf 'adaptation\t%s\n' "$7"
  printf 'proposed_model\t%s\n' "$8"
  printf 'proposed_effort\t%s\n' "$9"
  printf 'net\t%s\n' "${10}"
  printf 'degraded\t%s\n' "$DEGRADED"
}

cmd_resolve() {
  parse_args "$@"
  require_exec "$RESOLVER" "shared knob resolver"
  require_exec "$SELECT" "selection resolver"
  require_exec "$LEDGER" "allocation ledger"
  require_exec "$GATE" "usage-gate helper"
  require_exec "$KILL" "daemon-gate helper"

  # The starting tier. allocation-select validates the key and propagates the
  # by-layer malformed policy, so a hostile key never reaches a path here.
  base=$("$SELECT" select "$KEY") || exit $?
  START_MODEL=$(printf '%s' "$base" | cut -f1)
  START_EFFORT=$(printf '%s' "$base" | cut -f2)
  COMMAND=$(printf '%s' "$base" | cut -f3)

  # The kill-switch: the operator has taken manual control, so allocation
  # reverts to the un-degraded normal policy rather than degrading further.
  kill_err=$("$KILL" "$MECHANISM" 2>&1)
  kill_rc=$?
  KILLED=no
  case $kill_rc in
    0) ;;
    1) KILLED=yes ;;
    *)
      [ -n "$kill_err" ] && printf '%s\n' "$kill_err" >&2
      exit "$kill_rc"
      ;;
  esac

  # The rung, derived by the consumed contract from the shared trail. A read
  # that fails or yields an unrecognized rung is the FAIL-CLOSED case: treat it
  # as `downshift` (apply the downshift values), deny escalation, and record the
  # degraded read — never a blocked launch, and never a silent `normal`.
  if [ "$KILLED" = yes ]; then
    echo "allocation-adapt: kill-switch engaged — allocation reverted to the normal (un-degraded) policy" >&2
    RUNG=normal
    RIDX=0
  else
    RUNG=$("$GATE" rung 2>/dev/null) || RUNG=""
    if ! RIDX=$(rung_index "$RUNG" 2>/dev/null); then
      DEGRADED=clamp-input
      RUNG=downshift
      RIDX=1
    fi
  fi

  # The raw signal. Unavailable keeps the caps inactive (their own contract) AND
  # denies escalation above the starting tier (REQ-D1.2).
  if [ "$KILLED" = yes ]; then
    USAGE=unavailable
  else
    USAGE=$(global_usage)
  fi

  if [ "$RIDX" -ge 2 ]; then
    CONCURRENCY=$(resolve_posint fleet_concurrency_reduced 1) || exit $?
  else
    CONCURRENCY=$(resolve_posint fleet_concurrency_normal 3) || exit $?
  fi

  ADAPTATION=$(resolve_enum allocation_adaptation "on off" off) || exit $?
  CAP=$(resolve_nonnegint allocation_adjustment_cap 2) || exit $?

  # Take the unit's lock for the WHOLE derive-then-append critical section, so a
  # concurrent same-unit launch cannot read the tier this one is about to move.
  take_unit_lock

  # A non-fleet surface whose shipped default is the `inherit` sentinel: the
  # resolver was consulted (REQ-B1.1 holds), it applies nothing, and the
  # inheritance is RECORDED rather than left as a silent ambient launch.
  if [ "$START_MODEL" = inherit ] || [ "$START_EFFORT" = inherit ]; then
    record inherit "$START_MODEL" "$START_EFFORT" - - "$START_MODEL" "$START_EFFORT" \
      unit inherit "key=$KEY;rung=$RUNG;inherit=full" || true
    release_unit_lock
    queue_mirror inherit "unit $UNIT launched inheriting its ambient model and effort at key $KEY"
    flush_mirror
    emit yes "$START_MODEL" "$START_EFFORT" "$COMMAND" "$CONCURRENCY" "$RUNG" \
      "$ADAPTATION" "$START_MODEL" "$START_EFFORT" 0
    return 0
  fi

  # Ledger health decides whether adjustments run at all (REQ-F1.1).
  LEDGER_OK=yes
  "$LEDGER" health "$UNIT" 2>/dev/null || LEDGER_OK=no

  NET=0
  if [ "$LEDGER_OK" = no ]; then
    DEGRADED=ledger
    ADAPT_STATE=suspended
    # Launch at the LAST RECORDED tier when one is readable, else the starting
    # tier. Never a partial derivation over records that cannot be trusted.
    last=$("$LEDGER" last-tier "$UNIT" 2>/dev/null) || last=""
    if [ -n "$last" ]; then
      CUR_MODEL=$(printf '%s' "$last" | cut -f1)
      CUR_EFFORT=$(printf '%s' "$last" | cut -f2)
      alloc_valid_tier "$CUR_MODEL" "$CUR_EFFORT" || {
        CUR_MODEL=$START_MODEL
        CUR_EFFORT=$START_EFFORT
      }
    else
      CUR_MODEL=$START_MODEL
      CUR_EFFORT=$START_EFFORT
    fi
  elif [ "$ADAPTATION" = off ]; then
    ADAPT_STATE=off
    CUR_MODEL=$START_MODEL
    CUR_EFFORT=$START_EFFORT
  else
    ADAPT_STATE=on
    ledger_file=$("$LEDGER" path "$UNIT")
    alloc_replay "$ledger_file" "$START_MODEL" "$START_EFFORT" || exit 4
    CUR_MODEL=$ALLOC_MODEL
    CUR_EFFORT=$ALLOC_EFFORT
    NET=$ALLOC_NET
    apply_events
  fi

  clamp_tier "$CUR_MODEL" "$CUR_EFFORT"

  if [ "$CL_ADMIT" = withheld ]; then
    res_m=-
    res_e=-
    outcome=withheld
  else
    res_m=$CL_MODEL
    res_e=$CL_EFFORT
    outcome=resolved
    [ "$DEGRADED" = no ] || outcome=degraded
  fi
  record launch "$CUR_MODEL" "$CUR_EFFORT" "$CL_MODEL" "$CL_EFFORT" "$res_m" "$res_e" \
    unit "$outcome" "key=$KEY;rung=$RUNG;clamps=$CL_CLAMPS;signal=$USAGE;adaptation=$ADAPT_STATE" \
    || true

  release_unit_lock

  # The sparse governance mirror (D-6): a withheld unit, a binding clamp, and a
  # degraded launch are governance events; a routine resolution is not.
  if [ "$CL_ADMIT" = withheld ]; then
    queue_mirror withheld "unit $UNIT withheld at rung $RUNG"
  elif [ "$CL_CLAMPS" != none ] && [ "$CL_CLAMPS" != reserved-exempt ]; then
    queue_mirror clamped "unit $UNIT clamped by $CL_CLAMPS at rung $RUNG to $CL_MODEL/$CL_EFFORT"
  fi
  if [ "$DEGRADED" != no ]; then
    surface_degradation "$DEGRADED"
    queue_mirror degraded "unit $UNIT resolved with a degraded $DEGRADED read"
  fi
  flush_mirror

  emit "$CL_ADMIT" "$res_m" "$res_e" "$COMMAND" "$CONCURRENCY" "$RUNG" \
    "$ADAPT_STATE" "$CUR_MODEL" "$CUR_EFFORT" "$NET"
}

# apply_events: move the ladder at most one step per distinct INCIDENT class, in
# the order the caller supplied them, recording every outcome. Reads and updates
# CUR_MODEL / CUR_EFFORT / NET and the ALLOC_STACK the replay left behind.
apply_events() {
  ae_seen=""
  for ae_ev in $EVENTS; do
    ae_inc=$(alloc_incident "$ae_ev") || continue
    # One step per incident class AT THIS BOUNDARY.
    case " $ae_seen " in
      *" $ae_inc "*) continue ;;
    esac
    ae_seen="$ae_seen $ae_inc"
    # And never twice for the same incident across boundaries.
    incident_seen "$ae_inc" && continue

    ae_dir=$(alloc_event_dir "$ae_ev")
    if [ "$ae_dir" = up ]; then
      apply_up "$ae_ev"
    else
      apply_down "$ae_ev"
    fi
  done
}

apply_up() {
  au_ev=$1
  # The ladder top first: there is no tier above, so this is a structural no-op
  # rather than a policy denial, and it is the same answer under every clamp.
  if alloc_is_top "$CUR_MODEL" "$CUR_EFFORT"; then
    record "$au_ev" "$CUR_MODEL" "$CUR_EFFORT" - - "$CUR_MODEL" "$CUR_EFFORT" \
      unit no-op "trigger=$au_ev;reason=ladder-top" || true
    queue_mirror noop-ladder-top "unit $UNIT is at the ladder top; $au_ev could not escalate"
    return 0
  fi
  # While the signal is unavailable, escalation ABOVE the starting tier is
  # denied and a unit already above it holds — but a unit BELOW its starting
  # tier may still climb back to it (REQ-D1.2).
  if [ "$USAGE" = unavailable ] && [ $((NET + 1)) -gt 0 ]; then
    deny_up "$au_ev" signal-unavailable
    return 0
  fi
  if [ "$DEGRADED" = clamp-input ]; then
    deny_up "$au_ev" clamp-input
    return 0
  fi
  if [ $((NET + 1)) -gt "$CAP" ]; then
    deny_up "$au_ev" adjustment-cap
    return 0
  fi
  au_next=$(alloc_successor "$CUR_MODEL" "$CUR_EFFORT") || return 0
  au_from="$CUR_MODEL:$CUR_EFFORT"
  CUR_MODEL=${au_next% *}
  CUR_EFFORT=${au_next#* }
  NET=$((NET + 1))
  ALLOC_STACK="$ALLOC_STACK $au_from"
  record "$au_ev" "$CUR_MODEL" "$CUR_EFFORT" - - "$CUR_MODEL" "$CUR_EFFORT" \
    unit applied "trigger=$au_ev;dir=up;net=$NET" || true
  queue_mirror escalate "unit $UNIT escalated to $CUR_MODEL/$CUR_EFFORT on $au_ev"
}

deny_up() {
  record "$1" "$CUR_MODEL" "$CUR_EFFORT" - - - - unit denied "trigger=$1;reason=$2" || true
  queue_mirror denied "unit $UNIT could not escalate on $1: $2"
}

apply_down() {
  ad_ev=$1
  if [ $((NET - 1)) -lt $((0 - CAP)) ]; then
    record "$ad_ev" "$CUR_MODEL" "$CUR_EFFORT" - - - - unit denied \
      "trigger=$ad_ev;reason=adjustment-cap" || true
    queue_mirror denied "unit $UNIT could not de-escalate on $ad_ev: adjustment-cap"
    return 0
  fi
  if [ -n "$ALLOC_STACK" ]; then
    # Reverse the most recent unreversed escalation, restoring its pre-step tier
    # exactly — the reversal target is DERIVED from the replay, never recorded.
    ad_top=${ALLOC_STACK##* }
    ALLOC_STACK=${ALLOC_STACK% *}
    CUR_MODEL=${ad_top%:*}
    CUR_EFFORT=${ad_top#*:}
  else
    if alloc_is_bottom "$CUR_MODEL" "$CUR_EFFORT"; then
      record "$ad_ev" "$CUR_MODEL" "$CUR_EFFORT" - - "$CUR_MODEL" "$CUR_EFFORT" \
        unit no-op "trigger=$ad_ev;reason=ladder-floor" || true
      queue_mirror noop-ladder-floor "unit $UNIT is at the ladder floor; $ad_ev could not de-escalate"
      return 0
    fi
    ad_next=$(alloc_mirror "$CUR_MODEL" "$CUR_EFFORT") || return 0
    CUR_MODEL=${ad_next% *}
    CUR_EFFORT=${ad_next#* }
  fi
  NET=$((NET - 1))
  record "$ad_ev" "$CUR_MODEL" "$CUR_EFFORT" - - "$CUR_MODEL" "$CUR_EFFORT" \
    unit applied "trigger=$ad_ev;dir=down;net=$NET" || true
  queue_mirror de-escalate "unit $UNIT de-escalated to $CUR_MODEL/$CUR_EFFORT on $ad_ev"
}

cmd_derive() {
  parse_args "$@"
  require_exec "$SELECT" "selection resolver"
  require_exec "$LEDGER" "allocation ledger"
  base=$("$SELECT" select "$KEY") || exit $?
  d_model=$(printf '%s' "$base" | cut -f1)
  d_effort=$(printf '%s' "$base" | cut -f2)
  if [ "$d_model" = inherit ] || [ "$d_effort" = inherit ]; then
    printf 'model\t%s\neffort\t%s\nnet\t0\n' "$d_model" "$d_effort"
    return 0
  fi
  "$LEDGER" derive "$UNIT" "$d_model" "$d_effort" \
    | awk -F "$TAB" '{ printf "model\t%s\neffort\t%s\nnet\t%s\n", $1, $2, $3 }'
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift
case "$cmd" in
  resolve) cmd_resolve "$@" ;;
  derive) cmd_derive "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
