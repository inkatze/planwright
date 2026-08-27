#!/bin/sh
# fleet-resource-select.sh — the fleet-scoped front door onto the selection
# table (fleet-autonomy Task 7; D-11, REQ-E1.1, REQ-E1.2).
#
# The table itself now lives in scripts/allocation-select.sh, generalized to
# every launch point rather than fleet dispatch alone (model-allocation D-5,
# REQ-A1.1): this script keeps the fleet's established CLI, task-type
# vocabulary, and exit contract, and delegates the actual resolution there, so
# selection logic exists in exactly ONE place. Fleet callers
# (scripts/fleet-allocate.sh, /orchestrate's dispatch step) need no change,
# and the shipped defaults are pinned to the captured golden baseline
# (tests/fixtures/allocation-golden-baseline.tsv) at both entry points.
#
# Per-task selection of which model, reasoning effort, and slash command a
# dispatched unit runs is a DETERMINISTIC rule table keyed by task type —
# never a confidence-calibrated model cascade (D-11: calibrating the
# escalation threshold is an open problem the bundle deliberately does not
# take on) and never an LLM call (the D-18 no-LLM-daemon-mechanics floor;
# every fleet-mechanics decision that needs an LLM call becomes subject to
# the exact rate-limit problem REQ-E1.3 exists to manage). Resolution is
# pure table lookup plus config-file reads: no network, no subprocess beyond
# the delegate and the shared knob resolver chain (sh/sed/awk).
#
# THE FLEET ROWS. One per task type the fleet dispatches:
#
#   task type    model (knob-resolved)          effort   command
#   execution    fleet_model_execution (opus)   high     execute-task
#   bookkeeping  fleet_model_bookkeeping        medium   orchestrate
#                (sonnet)
#   drain        fleet_model_drain (sonnet)     low      drain
#
# `execution` is a spec task unit (the /execute-task workhorse): judgment-
# heavy, routed to the strong-model/high-effort tier. `bookkeeping` is the
# tower's reconcile/drain sweep pass (/orchestrate --bookkeeping):
# mechanical, mid-tier. `drain` is the read-only gate-evaluation pass
# (/drain): the lightest tier. ALL THREE columns — model, effort, and command
# — are overlay-tunable per task type (fleet-autonomy Task 10, D-24,
# REQ-E1.8). Each now resolves through the general `allocation_<column>_<type>`
# knob first and falls back to the `fleet_<column>_<type>` knob named above,
# which stays a DEPRECATED FALLBACK — documented, never removed — so every
# overlay written against the fleet family keeps working unchanged
# (model-allocation REQ-A1.3). Each column's values are restricted to a stable
# enum: model to the Claude Code model aliases (fable opus sonnet haiku) —
# aliases, not dated model ids, so the enum survives model releases; effort to
# (low medium high); command to the dispatch-entry set (execute-task
# orchestrate drain).
#
# REVIEW-SEQUENCE DISJOINTNESS (REQ-E1.2). The selectable command set names
# dispatch-entry skills only and must never overlap `review_sequence`'s
# convergence-phase scope (the nestable-review-skill set
# resolve-review-sequence.sh validates against — polish, self-review). The
# command column being overlay-tunable does NOT reopen this: the command enum
# in the delegate is exactly the dispatch-entry set {execute-task orchestrate
# drain}, none of which is a nestable review skill, so any configured command
# outside that set is refused (by-layer malformed policy) and disjointness
# holds by CONSTRUCTION at every layer, not merely for the shipped defaults.
# The cross-check tests (tests/test-fleet-resource-select.sh,
# tests/test-allocation-select.sh) assert every command this table can emit
# fails the nestable predicate, so the two mechanisms can never both claim the
# same skill.
#
# HOW THE CHOICE IS APPLIED. This script only RESOLVES the choice; applying
# it is the dispatching backend's job (`claude --model <model>` at launch,
# the Agent tool's model/effort parameters for a subagent worker, the
# command as the dispatched `/<command> <args>` slash invocation). Selection
# is not a daemon action under REQ-F1.4's enumeration (it nudges/cleans/
# restarts/throttles nothing), so it takes no kill-switch gate and writes no
# audit row.
#
# Usage:
#   fleet-resource-select.sh select <task-type>
#       Print one TSV row on stdout: <model>TAB<effort>TAB<command>.
#   fleet-resource-select.sh list
#       Print the full table, one TSV row per task type:
#       <task-type>TAB<model>TAB<effort>TAB<command>.
#
# Environment: honors every override the shared knob resolver honors
# (PLANWRIGHT_CONFIG_DEFAULTS, PLANWRIGHT_ADOPTER_OVERLAY,
# PLANWRIGHT_REPO_ROOT, PLANWRIGHT_LOCAL_CONFIG, CLAUDE_PLUGIN_ROOT/DATA).
#
# Exit codes: 0 row(s) printed; 2 usage error or unknown/hostile task type (fail
# closed, never a silent default); 4 malformed repo-tracked model knob
# (resolver hard-fail, propagated); 5 broken install (the delegate or shared
# resolver unavailable, or the core default itself malformed).
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
# Pathname expansion is disabled (set -f).
set -uf

# Pin C so the charset checks below mean exactly their ASCII range on every
# host (house pattern). A CDPATH-resolved cd would echo into the script-dir
# command substitution.
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md): a
# hostile task-type token is stripped of control bytes before it reaches a
# diagnostic, so it cannot drive the operator's terminal.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

DELEGATE="$script_dir/allocation-select.sh"

# The fleet's task types. This allowlist is what keeps the fleet CLI's
# vocabulary fleet-scoped: the delegate's table also carries the non-fleet
# surface keys, and `fleet-resource-select.sh select offload` must stay a
# refusal, not a surprise row.
TASK_TYPES="execution bookkeeping drain"

usage() {
  echo "usage: fleet-resource-select.sh select <task-type> | list" >&2
  echo "  task types: execution | bookkeeping | drain" >&2
}

require_delegate() {
  if [ ! -x "$DELEGATE" ]; then
    echo "fleet-resource-select: selection resolver '$DELEGATE' is missing or not executable — broken install" >&2
    exit 5
  fi
}

# known_type <task-type>: 0 when the token is one of the fleet's task types.
# The candidate is quoted in the test, which is what makes a hostile token like
# `*` compare literally rather than match anything. `set -f` covers the other
# side: the unquoted $TASK_TYPES word-split cannot glob against the working
# directory should that list ever carry a metacharacter.
known_type() {
  for _kt in $TASK_TYPES; do
    [ "$1" = "$_kt" ] && return 0
  done
  return 1
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift

case "$cmd" in
  select)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    if ! known_type "$1"; then
      echo "fleet-resource-select: unknown task type '$(sanitize_printable "$1" "(unprintable type)")' (execution | bookkeeping | drain)" >&2
      exit 2
    fi
    require_delegate
    "$DELEGATE" select "$1" || exit $?
    ;;
  list)
    if [ "$#" -ne 0 ]; then
      usage
      exit 2
    fi
    require_delegate
    # Resolve every row before emitting any: a later-row resolver hard-fail
    # must not leave partial output on stdout (the fail-before-emitting
    # posture the audit query path holds).
    rows=""
    for lt_type in $TASK_TYPES; do
      lt_row=$("$DELEGATE" select "$lt_type") || exit $?
      rows="$rows$lt_type	$lt_row
"
    done
    printf '%s' "$rows"
    ;;
  *)
    usage
    exit 2
    ;;
esac
