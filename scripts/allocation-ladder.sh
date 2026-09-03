#!/bin/sh
# allocation-ladder.sh — the tier ladder's math, as a SOURCED library
# (model-allocation Task 2; D-6, D-8; REQ-C1.1, REQ-C1.2).
#
# A tier is a joint (model, effort) point. Two consumers need identical
# arithmetic over it — allocation-ledger.sh, which REPLAYS a unit's recorded
# steps to derive its current tier, and allocation-adapt.sh, which decides the
# NEXT step at a launch boundary. A second implementation of the successor rule
# is exactly the drift this file exists to prevent, so the rules live here once
# and both scripts source it (the scripts/echo-safety.sh precedent).
#
# TWO ORDERINGS, DELIBERATELY DISTINCT (D-8). The MOVEMENT path and the COST
# order are not the same relation and must not be collapsed into one:
#
#   Movement (the successor rule). Escalation raises effort one level until
#   `high`, then raises the model one alias keeping effort `high`:
#       (m, e) -> (m, e+1)     while e < high
#       (m, high) -> (m+1, high)   while m < fable
#   De-escalation below the starting tier mirrors it: lower the effort one level
#   until `low`, then lower the model one alias keeping effort `low`. Both ends
#   are hard stops (`alloc_successor` / `alloc_mirror` refuse there).
#
#   Cost order. "Cheaper than" is MODEL-MAJOR, EFFORT-MINOR: a cheaper model is
#   cheaper at any effort. The successor path SKIPS cost-order points — from
#   (sonnet, high) it reaches (opus, high), never (opus, low) — and that is
#   intended. The ladder is the path; the cost order is the comparator the
#   clamps use.
#
# DERIVATION IS MEMORYLESS (D-6, REQ-C1.1). `alloc_replay` recomputes a unit's
# tier from its ledger rows PLUS the configured starting tier — never from a
# stored current-tier value. Each applied row carries only its DIRECTION (read
# off the event class and outcome columns, no free-text parsing), so replay
# re-derives every intermediate tier itself: change the configured starting
# tier and the whole replay moves with it, which is what REQ-C1.1's
# records-plus-config input set means.
#
# A de-escalation REVERSES the most recent unreversed escalation step, restoring
# that step's pre-escalation tier exactly; with none left to reverse it steps
# below the starting tier by the mirror rule. Replay keeps the unreversed
# escalations on a stack, so the reversal target is derived, never recorded.
#
# NET DISPLACEMENT is a STEP COUNT, not a ladder distance: applied up-steps
# minus applied down-steps. Because the up and down paths need not retrace one
# another (D-8's "re-raise, not retrace"), a ladder distance would be ill-defined
# — the step count is what the per-unit adjustment cap bounds in each direction,
# and reversals refund it.
#
# This file is SOURCED, never executed: it defines functions and sets no traps,
# no `set` flags, and no locale of its own (the sourcing script owns those). All
# functions are prefixed `alloc_` and their locals `al_`/`ar_`, so nothing
# collides with a caller's namespace.

# The model aliases in COST order, cheapest first. Rank is an index into it, so
# a HIGHER rank is a MORE EXPENSIVE model (the opposite polarity from
# fleet-allocate.sh's cost index — that one counts downward from `fable`).
# Keeping the ladder's own polarity ascending is what makes "escalate" a `+1`
# here and keeps the successor rule readable.
#
# Both lists double as the COLUMN ENUMS a sourcing script hands to the shared
# knob resolver as `--values`, which is a use shellcheck cannot see across the
# source boundary — hence the disables.
# shellcheck disable=SC2034 # consumed by the sourcing script, not here
ALLOC_MODELS='haiku sonnet opus fable'
# shellcheck disable=SC2034 # consumed by the sourcing script, not here
ALLOC_EFFORTS='low medium high'
ALLOC_MODEL_TOP=3
ALLOC_EFFORT_TOP=2

# alloc_model_rank <alias>: 0 (haiku) .. 3 (fable). Returns 1 on an unknown
# alias so every caller fails closed rather than defaulting to a tier.
alloc_model_rank() {
  case $1 in
    haiku) printf 0 ;;
    sonnet) printf 1 ;;
    opus) printf 2 ;;
    fable) printf 3 ;;
    *) return 1 ;;
  esac
}

# alloc_model_at <rank>: the inverse. Returns 1 on an out-of-range rank.
alloc_model_at() {
  case $1 in
    0) printf haiku ;;
    1) printf sonnet ;;
    2) printf opus ;;
    3) printf fable ;;
    *) return 1 ;;
  esac
}

# alloc_effort_rank <effort>: 0 (low) .. 2 (high). Returns 1 on an unknown value.
alloc_effort_rank() {
  case $1 in
    low) printf 0 ;;
    medium) printf 1 ;;
    high) printf 2 ;;
    *) return 1 ;;
  esac
}

# alloc_effort_at <rank>: the inverse. Returns 1 on an out-of-range rank.
alloc_effort_at() {
  case $1 in
    0) printf low ;;
    1) printf medium ;;
    2) printf high ;;
    *) return 1 ;;
  esac
}

# alloc_valid_tier <model> <effort>: 0 when both are in their enums.
alloc_valid_tier() {
  alloc_model_rank "$1" >/dev/null 2>&1 || return 1
  alloc_effort_rank "$2" >/dev/null 2>&1 || return 1
  return 0
}

# alloc_is_top <model> <effort>: 0 at the ladder top, where a further escalation
# has nowhere to go and is recorded as a no-op.
alloc_is_top() {
  [ "$1" = fable ] && [ "$2" = high ]
}

# alloc_is_bottom <model> <effort>: 0 at the ladder floor.
alloc_is_bottom() {
  [ "$1" = haiku ] && [ "$2" = low ]
}

# alloc_successor <model> <effort>: print the next tier UP the movement path as
# `<model> <effort>`. Returns 1 at the ladder top (a hard stop) and 2 on an
# invalid input tier.
alloc_successor() {
  al_m=$1
  al_e=$2
  al_mr=$(alloc_model_rank "$al_m") || return 2
  al_er=$(alloc_effort_rank "$al_e") || return 2
  if [ "$al_er" -lt "$ALLOC_EFFORT_TOP" ]; then
    printf '%s %s' "$al_m" "$(alloc_effort_at $((al_er + 1)))"
    return 0
  fi
  # At `high`: step the model and KEEP the effort at `high` — the hinge a
  # model-only reading of the ladder gets wrong.
  if [ "$al_mr" -lt "$ALLOC_MODEL_TOP" ]; then
    printf '%s %s' "$(alloc_model_at $((al_mr + 1)))" high
    return 0
  fi
  return 1
}

# alloc_mirror <model> <effort>: print the next tier DOWN the mirror path.
# Returns 1 at the ladder floor and 2 on an invalid input tier.
alloc_mirror() {
  al_m=$1
  al_e=$2
  al_mr=$(alloc_model_rank "$al_m") || return 2
  al_er=$(alloc_effort_rank "$al_e") || return 2
  if [ "$al_er" -gt 0 ]; then
    printf '%s %s' "$al_m" "$(alloc_effort_at $((al_er - 1)))"
    return 0
  fi
  if [ "$al_mr" -gt 0 ]; then
    printf '%s %s' "$(alloc_model_at $((al_mr - 1)))" low
    return 0
  fi
  return 1
}

# alloc_cost_cmp <m1> <e1> <m2> <e2>: print -1 when tier 1 is cheaper, 1 when
# tier 2 is, 0 when they are the same point. Model-major, effort-minor.
# Returns 2 on an invalid tier.
alloc_cost_cmp() {
  al_m1=$(alloc_model_rank "$1") || return 2
  al_e1=$(alloc_effort_rank "$2") || return 2
  al_m2=$(alloc_model_rank "$3") || return 2
  al_e2=$(alloc_effort_rank "$4") || return 2
  if [ "$al_m1" -lt "$al_m2" ]; then
    printf -- '-1'
  elif [ "$al_m1" -gt "$al_m2" ]; then
    printf 1
  elif [ "$al_e1" -lt "$al_e2" ]; then
    printf -- '-1'
  elif [ "$al_e1" -gt "$al_e2" ]; then
    printf 1
  else
    printf 0
  fi
}

# alloc_cheaper <m1> <e1> <m2> <e2>: print the cheaper of two tiers as
# `<model> <effort>` (tier 1 on a tie). Returns 2 on an invalid tier.
alloc_cheaper() {
  al_c=$(alloc_cost_cmp "$@") || return 2
  if [ "$al_c" -le 0 ]; then
    printf '%s %s' "$1" "$2"
  else
    printf '%s %s' "$3" "$4"
  fi
}

# The closed trigger allowlist (D-2, REQ-C1.2) — the whole set of work-shaped
# events that may move a tier, and nothing else. Infrastructure failures (a
# config hard-fail, an audit write error, a git or backend launch error) are
# deliberately absent: no model tier fixes them, and counting them would burn
# the adjustment cap on mechanism trouble.
ALLOC_EVENTS_UP='step-failure retry flailing non-convergence petition-escalate'
ALLOC_EVENTS_DOWN='petition-de-escalate'
# The non-trigger event classes a row may carry: a routine launch-boundary
# resolution, an inheritance, a degraded-mode launch, and the terminal-state
# feedback mark allocation-feedback.sh writes once per unit (REQ-F1.2). None of
# them moves a tier — `alloc_event_dir` answers `none` — so replay walks past
# them, and the feedback mark in particular must stay inert: it is written AFTER
# the unit's last launch and records history rather than making any.
ALLOC_EVENTS_INERT='launch inherit degraded feedback'

# alloc_event_dir <event>: print `up`, `down`, or `none`. Returns 1 for a token
# outside the closed set, so an unrecognized event is a refusal, never a
# silently-ignored trigger.
alloc_event_dir() {
  for al_v in $ALLOC_EVENTS_UP; do
    [ "$1" = "$al_v" ] && {
      printf up
      return 0
    }
  done
  for al_v in $ALLOC_EVENTS_DOWN; do
    [ "$1" = "$al_v" ] && {
      printf down
      return 0
    }
  done
  for al_v in $ALLOC_EVENTS_INERT; do
    [ "$1" = "$al_v" ] && {
      printf none
      return 0
    }
  done
  return 1
}

# alloc_incident <event>: the IDEMPOTENCY CLASS an event belongs to (D-8). A
# step failure and the retry it caused are one incident, so they share a key and
# collapse to a single ladder step at a boundary; an escalate and a de-escalate
# petition are one channel. Independent incidents keep distinct keys and stack.
# Returns 1 outside the closed set.
alloc_incident() {
  case $1 in
    step-failure | retry) printf step-failure ;;
    flailing) printf flailing ;;
    non-convergence) printf non-convergence ;;
    petition-escalate | petition-de-escalate) printf petition ;;
    *) return 1 ;;
  esac
}

# alloc_replay <ledger-file> <start-model> <start-effort>: replay a unit's
# ledger and set, in the CALLER's shell:
#   ALLOC_MODEL / ALLOC_EFFORT   the derived current tier
#   ALLOC_NET                    net displacement in steps (may be negative)
#   ALLOC_STACK                  unreversed escalations, oldest first, each the
#                                `<model>:<effort>` the step climbed FROM
#   ALLOC_ROWS                   rows scanned
#   ALLOC_ESCALATIONS            applied up-steps over the unit's whole history
#
# Only UNIT-scoped rows whose outcome is `applied` move anything: a denial, a
# no-op, an ignore, a clamped resolution, and every step-scoped row are inert to
# unit-tier derivation by construction (a clamp is recorded as clamped, never as
# de-escalation — D-8). An absent file is a zero-history unit at its starting
# tier. Returns 1 only when the starting tier itself is invalid.
#
# The scan is a single pass of shell built-ins over one unit's own file, with no
# fork per row and no subshell (the redirect keeps the accumulators in scope),
# so a long history costs one read and a bounded loop.
alloc_replay() {
  ar_file=$1
  alloc_valid_tier "$2" "$3" || return 1
  ALLOC_MODEL=$2
  ALLOC_EFFORT=$3
  ALLOC_NET=0
  ALLOC_STACK=''
  ALLOC_ROWS=0
  ALLOC_ESCALATIONS=0
  [ -r "$ar_file" ] || return 0

  # Every one of the fifteen columns is named even though replay reads only
  # four: naming them is what makes `read` consume a whole row per iteration,
  # and it documents the schema at the one place that parses it. A trailing
  # catch-all instead would silently absorb a row that grew a column.
  # shellcheck disable=SC2034 # the unread columns are named to consume the row
  while IFS='	' read -r ar_seq ar_ts ar_unit ar_step ar_att ar_event \
    ar_pm ar_pe ar_cm ar_ce ar_rm ar_re ar_scope ar_outcome ar_inputs; do
    ALLOC_ROWS=$((ALLOC_ROWS + 1))
    [ "$ar_scope" = unit ] || continue
    [ "$ar_outcome" = applied ] || continue
    ar_dir=$(alloc_event_dir "$ar_event") || continue
    if [ "$ar_dir" = up ]; then
      ar_next=$(alloc_successor "$ALLOC_MODEL" "$ALLOC_EFFORT") || continue
      ALLOC_STACK="$ALLOC_STACK $ALLOC_MODEL:$ALLOC_EFFORT"
      ALLOC_MODEL=${ar_next% *}
      ALLOC_EFFORT=${ar_next#* }
      ALLOC_NET=$((ALLOC_NET + 1))
      ALLOC_ESCALATIONS=$((ALLOC_ESCALATIONS + 1))
    elif [ "$ar_dir" = down ]; then
      if [ -n "$ALLOC_STACK" ]; then
        # Reverse the most recent unreversed escalation: pop the tier it climbed
        # from. `${x##* }` takes the last space-separated token.
        ar_top=${ALLOC_STACK##* }
        ALLOC_STACK=${ALLOC_STACK% *}
        ALLOC_MODEL=${ar_top%:*}
        ALLOC_EFFORT=${ar_top#*:}
      else
        ar_next=$(alloc_mirror "$ALLOC_MODEL" "$ALLOC_EFFORT") || continue
        ALLOC_MODEL=${ar_next% *}
        ALLOC_EFFORT=${ar_next#* }
      fi
      ALLOC_NET=$((ALLOC_NET - 1))
    fi
  done <"$ar_file"
  return 0
}
