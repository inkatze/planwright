#!/bin/sh
# fleet-resource-select.sh — the rule-based, task-type-keyed model/effort/
# command selection table (fleet-autonomy Task 7; D-11, REQ-E1.1, REQ-E1.2).
#
# Per-task selection of which model, reasoning effort, and slash command a
# dispatched unit runs is a DETERMINISTIC rule table keyed by task type —
# never a confidence-calibrated model cascade (D-11: calibrating the
# escalation threshold is an open problem the bundle deliberately does not
# take on) and never an LLM call (the D-18 no-LLM-daemon-mechanics floor;
# every fleet-mechanics decision that needs an LLM call becomes subject to
# the exact rate-limit problem REQ-E1.3 exists to manage). Resolution is
# pure table lookup plus config-file reads: no network, no subprocess beyond
# the shared knob resolver chain (sh/sed/awk).
#
# THE TABLE. One row per task type the fleet dispatches:
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
# (/drain): the lightest tier. The MODEL column is overlay-tunable per task
# type through the shared knob resolver (resolve-config-knob.sh ->
# config-get; D-22/REQ-G1.5, the REQ-E1.4 by-layer malformed policy), values
# restricted to the stable Claude Code model-alias enum (fable opus sonnet
# haiku) — aliases, not dated model ids, so the enum survives model
# releases. Effort and command are FIXED table cells: changing them is a
# table (code) change, reviewed like one.
#
# REVIEW-SEQUENCE DISJOINTNESS (REQ-E1.2). The selectable command set names
# dispatch-entry skills only and must never overlap `review_sequence`'s
# convergence-phase scope (the nestable-review-skill set
# resolve-review-sequence.sh validates against — polish, self-review). The
# cross-check test (tests/test-fleet-resource-select.sh) asserts every
# command in this table fails the nestable predicate, so the two mechanisms
# can never both claim the same skill.
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
# (resolver hard-fail, propagated); 5 broken install (resolver unavailable
# or the core default itself malformed).
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

RESOLVER="$script_dir/resolve-config-knob.sh"

# The stable Claude Code model-alias enum every model knob validates against.
MODEL_VALUES="fable opus sonnet haiku"

usage() {
  echo "usage: fleet-resource-select.sh select <task-type> | list" >&2
  echo "  task types: execution | bookkeeping | drain" >&2
}

# table_row <task-type>: 0 with the row parameters set, 1 for an unknown
# type. The single source of the table; `select` and `list` both read it.
#   row_knob     the model knob key      row_model_default  its core default
#   row_effort   the fixed effort cell   row_command        the fixed command
table_row() {
  case "$1" in
    execution)
      row_knob=fleet_model_execution
      row_model_default=opus
      row_effort=high
      row_command=execute-task
      ;;
    bookkeeping)
      row_knob=fleet_model_bookkeeping
      row_model_default=sonnet
      row_effort=medium
      row_command=orchestrate
      ;;
    drain)
      row_knob=fleet_model_drain
      row_model_default=sonnet
      row_effort=low
      row_command=drain
      ;;
    *) return 1 ;;
  esac
}

# resolve_model: resolve the current row's model knob through the shared
# resolver (four overlay layers, by-layer malformed policy). Propagates the
# resolver's hard-fail exits (4/5) verbatim; the fallback is the row's core
# default so a partial install still resolves (REQ-K1.6).
resolve_model() {
  if [ ! -x "$RESOLVER" ]; then
    echo "fleet-resource-select: shared knob resolver '$RESOLVER' is missing or not executable — broken install" >&2
    exit 5
  fi
  rm_out=$("$RESOLVER" --key "$row_knob" --type enum --values "$MODEL_VALUES" --fallback "$row_model_default") || exit $?
  printf '%s' "$rm_out"
}

emit_row() {
  er_model=$(resolve_model) || exit $?
  printf '%s\t%s\t%s\n' "$er_model" "$row_effort" "$row_command"
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
    if ! table_row "$1"; then
      echo "fleet-resource-select: unknown task type '$(sanitize_printable "$1" "(unprintable type)")' (execution | bookkeeping | drain)" >&2
      exit 2
    fi
    emit_row
    ;;
  list)
    if [ "$#" -ne 0 ]; then
      usage
      exit 2
    fi
    # Resolve every row before emitting any: a later-row resolver hard-fail
    # must not leave partial output on stdout (the fail-before-emitting
    # posture the audit query path holds).
    rows=""
    for lt_type in execution bookkeeping drain; do
      table_row "$lt_type" || exit 5 # unreachable: the loop names table rows
      lt_model=$(resolve_model) || exit $?
      rows="$rows$lt_type	$lt_model	$row_effort	$row_command
"
    done
    printf '%s' "$rows"
    ;;
  *)
    usage
    exit 2
    ;;
esac
