#!/bin/sh
# allocation-select.sh — the surface-agnostic selection resolver
# (model-allocation Task 1; D-5, D-13, REQ-A1.1, REQ-A1.2, REQ-A1.3,
# REQ-A1.4, REQ-E1.1, REQ-E1.2).
#
# fleet-resource-select.sh shipped one selection table keyed by fleet task
# type. This is that table generalized: one resolver, keyed by SELECTION KEY,
# that ANY launch point can call — fleet dispatch, single-spec /orchestrate
# dispatch, /execute-task's per-step sessions, /offload. fleet-resource-
# select.sh is now a thin fleet-scoped front door onto this table, so
# selection logic lives in exactly one place (D-5, the existing-seam-reuse
# disposition).
#
# Fleet dispatch is the only caller wired so far; the rows for the other three
# surfaces exist and resolve, and Task 6 wires those surfaces to read them.
# Until then they resolve to `inherit` and nothing changes at those surfaces,
# which is the shipped posture anyway (D-13).
#
# Resolution stays DETERMINISTIC table lookup plus config-file reads: no
# network, no LLM call, no subprocess beyond the shared knob resolver chain
# (REQ-A1.1; the D-18 no-LLM-daemon-mechanics floor it inherits).
#
# THE TABLE. One row per selection key:
#
#   key                    model      effort     command       legacy family
#   execution              opus       high       execute-task  fleet_*_execution
#   bookkeeping            sonnet     medium     orchestrate   fleet_*_bookkeeping
#   drain                  sonnet     low        drain         fleet_*_drain
#   orchestrate_dispatch   inherit    inherit    (none)        (none)
#   execute_step           inherit    inherit    (none)        (none)
#   offload                inherit    inherit    (none)        (none)
#
# The first three are the fleet task types, shipped defaults unchanged: their
# cells are the captured golden baseline (REQ-A1.2,
# tests/fixtures/allocation-golden-baseline.tsv). The last three are the
# surfaces that perform no selection today; their shipped default is the
# explicit `inherit` sentinel, so the resolver is consulted but applies
# nothing and the launch keeps its ambient model/effort (D-13). The capability
# therefore ships dark: an operator who configures nothing sees no
# selection-behavior change at any surface.
#
# THE KNOB CHAIN (REQ-A1.3). Each column of each key resolves in this order:
#
#   1. allocation_<column>_<key>, through the shared knob resolver's four
#      overlay layers. The general, surface-agnostic family this spec
#      introduces.
#   2. If that resolves to the `unset` sentinel, fleet_<column>_<key> — the
#      legacy fleet family, kept as a DEPRECATED FALLBACK and never removed,
#      so every overlay written against it keeps working untouched.
#   3. If the key has no legacy counterpart, the key's shipped default.
#
# `unset` is how a flat config file spells "this general knob is not set".
# Core ships it for all nine fleet-keyed general knobs, which is precisely
# what arms step 2 by default and keeps `allocation_*` from silently
# overriding an operator's existing `fleet_*` overlay. Setting the general
# knob at any layer wins over the legacy one; setting it back to `unset`
# re-arms the fallback.
#
# THE `inherit` SENTINEL is legal only where the launching surface HAS an
# ambient value to fall back to — the three non-fleet keys. At a fleet task
# type it is refused as an out-of-enum value under the same by-layer policy as
# any other: fleet dispatch validates the resolved row against the concrete
# enums downstream (fleet-allocate.sh) and has nothing to inherit from, so
# emitting the sentinel there would turn a config choice into a broken-install
# failure at launch time. Refusing it at resolution keeps the diagnostic
# pointed at the knob that is actually wrong.
#
# THE COMMAND COLUMN is fleet-only (D-5): only a fleet dispatch turns a
# selection into a `/<command> <args>` invocation. Non-fleet keys do not carry
# it — `resolve <key> command` is refused for them, and `select`/`list` mark
# it absent with `-` (not a legal command value, so it can never be mistaken
# for one). The command enum stays exactly the dispatch-entry set
# {execute-task orchestrate drain}, which is the carrier of the
# review-sequence-disjointness invariant (REQ-A1.4): none of its members is a
# nestable review skill, and a configured command outside the set is refused
# at every layer, so disjointness holds by CONSTRUCTION rather than only for
# the shipped defaults.
#
# THE STEP-TYPE AXIS (Task 5; D-8, D-12, REQ-C1.3) is the table's SECOND key.
# A selection key prices a whole unit; a step type prices ONE STEP of it — the
# implementation step, or one of the review-sequence step classes. The two axes
# are resolved by separate verbs over separate knob families and never mix:
#
#   allocation_<column>_step_<step-type>    model | effort. No command column.
#
# NO STEP TYPE CARRIES THE COMMAND COLUMN, and that is load-bearing rather than
# an omission. The command enum is the carrier of the review-sequence-
# disjointness invariant (REQ-A1.4, above): it must stay exactly the
# dispatch-entry set and must never name a nestable review skill. Step types
# ARE named after nestable review skills, so letting the two axes share the
# command column is precisely how that invariant would be lost. Keeping the
# axes separate means adding a review step class cannot widen the command enum
# — the enum is untouched by construction, not merely by convention.
#
# THE SHIPPED DEFAULT IS `inherit` for every step type, so a step resolves to
# the unit's own tier and per-step keys change runtime behavior by exactly
# nothing until an operator configures one (D-13).
#
# APPLICATION IS ONE-DIRECTIONAL, and this script does NOT perform it: it only
# resolves the configured cell. allocation-adapt.sh owns the comparison — a
# step tier CHEAPER than the unit's current tier applies for that launch alone
# and is scope-marked in the ledger; an equal or more expensive one is ignored
# with a row (D-8). A step may never ratchet a unit up.
#
# HOW THE CHOICE IS APPLIED is the launching backend's job, per its advertised
# capability — not this script's. This script only resolves.
#
# Usage:
#   allocation-select.sh resolve <key> <column>
#       Print one resolved value: <column> is model | effort | command.
#   allocation-select.sh select <key>
#       Print one TSV row: <model>TAB<effort>TAB<command> ('-' when the key
#       does not carry the command column).
#   allocation-select.sh list
#       Print the full table, one TSV row per key:
#       <key>TAB<model>TAB<effort>TAB<command>.
#   allocation-select.sh step-tier <step-type>
#       Print one step type's configured tier as <model>TAB<effort>, each
#       `inherit` when that column is unconfigured. No command column, ever.
#   allocation-select.sh list-steps
#       Print the shipped step types, one TSV row each:
#       <step-type>TAB<model>TAB<effort>.
#
# Environment: honors every override the shared knob resolver honors
# (PLANWRIGHT_CONFIG_DEFAULTS, PLANWRIGHT_ADOPTER_OVERLAY,
# PLANWRIGHT_REPO_ROOT, PLANWRIGHT_LOCAL_CONFIG, CLAUDE_PLUGIN_ROOT/DATA).
#
# Exit codes: 0 value/row(s) printed; 2 usage error, unknown/hostile key or
# column, or a column the key does not carry (fail closed, never a silent
# default); 4 malformed repo-tracked knob (resolver hard-fail, propagated);
# 5 broken install (resolver unavailable or a core default itself malformed).
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
# hostile key or column token is stripped of control bytes before it reaches a
# diagnostic, so it cannot drive the operator's terminal.
#
# Guarded rather than sourced bare, because a missing helper is not
# self-announcing here. `.` is a POSIX special built-in, so a conforming shell
# aborts on it; bash outside POSIX mode (what this suite and CI run) only warns
# and carries on with sanitize_printable left undefined. The guard makes a
# half-installed tree the documented exit 5 on either shell, the same answer
# require_resolver gives for the other half of the install.
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "allocation-select: echo-discipline sanitizer '$echo_safety' is missing or not readable — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

RESOLVER="$script_dir/resolve-config-knob.sh"

# The stable per-column enums (REQ-A1.4): model to the Claude Code aliases —
# aliases, not dated model ids, so the enum survives model releases; effort to
# the three reasoning tiers; command to the dispatch-entry set.
MODEL_VALUES="fable opus sonnet haiku"
EFFORT_VALUES="low medium high"
COMMAND_VALUES="execute-task orchestrate drain"

# The sentinels. `unset` spells "this general knob is not set" in a flat config
# file; `inherit` spells "apply nothing, keep the launch's ambient value".
# (Quoted: bare `unset` reads as the shell builtin to shellcheck, SC2209.)
UNSET_SENTINEL="unset"
INHERIT_SENTINEL="inherit"
# The `select`/`list` marker for a column the key does not carry. Deliberately
# outside every column enum.
NO_COLUMN=-

# The table's key order, used by `list`.
KEYS="execution bookkeeping drain orchestrate_dispatch execute_step offload"

# The SHIPPED step types, used by `list-steps`: /execute-task's implementation
# step, then one per review-sequence step class.
#
# The step-type key space is OPEN by construction rather than a closed enum.
# The nestable review-skill set is DISCOVERED from the skills tree
# (resolve-review-sequence.sh owns that predicate), so a second copy of it here
# would drift — and a stale copy would REFUSE a legitimately configured step
# class rather than degrade, turning an operator's working config into a launch
# failure. Instead any charset-valid step type resolves, and one with no
# configured knob resolves to `inherit`, which applies nothing. A review skill
# added tomorrow therefore inherits silently and correctly with no edit here.
# This list is what `list-steps` enumerates and what config/defaults.yml ships
# rows for; it is a shipped set, not a validation boundary.
STEP_KEYS="implementation polish self-review"

usage() {
  echo "usage: allocation-select.sh resolve <key> <column> | select <key> | list | step-tier <step-type> | list-steps" >&2
  echo "  keys:       $KEYS" >&2
  echo "  columns:    model | effort | command (command: fleet task types only)" >&2
  echo "  step types: $STEP_KEYS (open set; any unconfigured one resolves to inherit)" >&2
}

# key_row <key>: 0 with the row parameters set, 1 for an unknown key. The
# single source of the table; every verb reads it.
#   row_legacy    1 when a fleet_<column>_<key> counterpart exists (the
#                 deprecated fallback), 0 otherwise
#   row_inherit   1 when the `inherit` sentinel is legal for this key
#   row_command   1 when the key carries the command column
#   row_<col>_default   the key's shipped default for that column
key_row() {
  row_legacy=1
  row_inherit=0
  row_command=1
  row_command_default=""
  case "$1" in
    execution)
      row_model_default=opus
      row_effort_default=high
      row_command_default=execute-task
      ;;
    bookkeeping)
      row_model_default=sonnet
      row_effort_default=medium
      row_command_default=orchestrate
      ;;
    drain)
      row_model_default=sonnet
      row_effort_default=low
      row_command_default=drain
      ;;
    orchestrate_dispatch | execute_step | offload)
      # The surfaces that perform no selection today: consulted, applying
      # nothing, until an operator configures them (D-13).
      row_legacy=0
      row_inherit=1
      row_command=0
      row_model_default=$INHERIT_SENTINEL
      row_effort_default=$INHERIT_SENTINEL
      ;;
    *) return 1 ;;
  esac
}

# col_spec <column>: 0 with col_values / col_default set for the current row,
# 1 for a real column this row does not carry, 2 for a token that is not a
# column at all. The two failures are distinct because only the first is about
# the key: telling someone who typo'd a column name that their key "does not
# carry" it sends them looking for the key that does. emit_row passes column
# names it owns, so nonzero there stays the unreachable case its exit 5 covers.
# Requires key_row to have run.
col_spec() {
  case "$1" in
    model)
      col_values=$MODEL_VALUES
      col_default=$row_model_default
      ;;
    effort)
      col_values=$EFFORT_VALUES
      col_default=$row_effort_default
      ;;
    command)
      [ "$row_command" -eq 1 ] || return 1
      col_values=$COMMAND_VALUES
      col_default=$row_command_default
      ;;
    *) return 2 ;;
  esac
}

require_resolver() {
  if [ ! -x "$RESOLVER" ]; then
    echo "allocation-select: shared knob resolver '$RESOLVER' is missing or not executable — broken install" >&2
    exit 5
  fi
}

# resolve_col <key> <column>: print the resolved value for one cell, walking
# the general -> legacy -> shipped-default chain. Requires key_row/col_spec to
# have run for this key and column. Propagates the shared resolver's hard-fail
# exits (4/5) verbatim; the per-step fallbacks keep a partial install resolving
# (REQ-K1.6) and an unconfigured operator on the shipped table (REQ-A1.2).
#
# THE CHAIN SHORT-CIRCUITS, deliberately. A set general knob returns before the
# legacy knob is read at all, so a malformed `fleet_<column>_<key>` sitting in
# a repo-tracked overlay does NOT hard-fail while the general knob shadows it —
# whereas it would if the general knob were `unset`. That is the intended
# reading of REQ-A1.3: the by-layer malformed policy governs the value a caller
# actually consumes, not every value present in the config, and a knob nothing
# reads should not be able to block a launch. Validating the shadowed knob too
# would also add a resolver call per column on the dispatch path the
# call-amplification observation already flags.
resolve_col() {
  require_resolver
  # The general knob's legal set is the column enum widened by the sentinels
  # this key admits. `unset` is always legal — it is how core spells "not set".
  rc_enum="$col_values $UNSET_SENTINEL"
  [ "$row_inherit" -eq 1 ] && rc_enum="$rc_enum $INHERIT_SENTINEL"
  rc_out=$("$RESOLVER" --key "allocation_$2_$1" --type enum --values "$rc_enum" --fallback "$UNSET_SENTINEL") || exit $?
  if [ "$rc_out" != "$UNSET_SENTINEL" ]; then
    printf '%s' "$rc_out"
    return 0
  fi
  if [ "$row_legacy" -eq 1 ]; then
    # The deprecated fallback. Its enum stays exactly what it ships today — no
    # sentinel widening — so the legacy knobs behave identically to before.
    rc_out=$("$RESOLVER" --key "fleet_$2_$1" --type enum --values "$col_values" --fallback "$col_default") || exit $?
    printf '%s' "$rc_out"
    return 0
  fi
  printf '%s' "$col_default"
}

# emit_row <key>: the TSV row for one key. Requires key_row to have run.
emit_row() {
  col_spec model || exit 5 # unreachable: every row carries model/effort
  er_model=$(resolve_col "$1" model) || exit $?
  col_spec effort || exit 5
  er_effort=$(resolve_col "$1" effort) || exit $?
  if [ "$row_command" -eq 1 ]; then
    col_spec command || exit 5
    er_command=$(resolve_col "$1" command) || exit $?
  else
    er_command=$NO_COLUMN
  fi
  printf '%s\t%s\t%s\n' "$er_model" "$er_effort" "$er_command"
}

# valid_step_type <token>: 0 for the SKILL-NAME charset (^[a-z][a-z0-9-]*$),
# bounded at 64 bytes. Checked BEFORE the token is spliced into a knob name, so
# a hostile step type never reaches the shared resolver, config-get, or a path.
# The 64-byte bound is this file's own: neither config-get nor the shared knob
# resolver caps a key's length, so nothing downstream requires it. It exists to
# keep the derived knob name readable in a config file and the step type inside
# the ledger `inputs` budget it is interpolated into.
valid_step_type() {
  case $1 in
    "" | [!a-z]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# step_knob_suffix <step-type>: the knob-name spelling of a step type. Knob
# names are ^[a-z][a-z0-9_]*$ (config-get's queryable charset) while skill
# names are ^[a-z][a-z0-9-]*$, so `-` maps to `_` (`self-review` ->
# `self_review`). The map is INJECTIVE over the skill charset — a skill name
# can never contain `_` — so two distinct step types can never collide on one
# knob, which is what keeps the config file's keys unambiguous.
step_knob_suffix() {
  printf '%s' "$1" | tr -- - _
}

# resolve_step_col <step-type> <column>: one cell of a step type's configured
# tier. Deliberately NOT resolve_col: there is no legacy `fleet_*` counterpart
# to fall back to (these knobs are new, so no overlay can predate them) and no
# `unset` sentinel, because `inherit` already IS this family's shipped default
# and a second "not set" spelling would only be ambiguous. `command` is not a
# case here at all — see the header on why the axes stay separate.
resolve_step_col() {
  require_resolver
  rsc_suffix=$(step_knob_suffix "$1")
  case $2 in
    model) rsc_enum=$MODEL_VALUES ;;
    effort) rsc_enum=$EFFORT_VALUES ;;
    *) exit 5 ;; # unreachable: callers pass column names they own
  esac
  rsc_out=$("$RESOLVER" --key "allocation_$2_step_$rsc_suffix" --type enum \
    --values "$rsc_enum $INHERIT_SENTINEL" --fallback "$INHERIT_SENTINEL") || exit $?
  printf '%s' "$rsc_out"
}

# emit_step_row <step-type>: the TSV tier for one step type. Two columns, never
# three: a step type carries no command column.
emit_step_row() {
  esr_model=$(resolve_step_col "$1" model) || exit $?
  esr_effort=$(resolve_step_col "$1" effort) || exit $?
  printf '%s\t%s\n' "$esr_model" "$esr_effort"
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift

case "$cmd" in
  resolve)
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    if ! key_row "$1"; then
      echo "allocation-select: unknown selection key '$(sanitize_printable "$1" "(unprintable key)")' ($KEYS)" >&2
      exit 2
    fi
    cs_rc=0
    col_spec "$2" || cs_rc=$?
    if [ "$cs_rc" -eq 2 ]; then
      echo "allocation-select: unknown column '$(sanitize_printable "$2" "(unprintable column)")' (model | effort | command)" >&2
      exit 2
    elif [ "$cs_rc" -ne 0 ]; then
      echo "allocation-select: key '$(sanitize_printable "$1" "(unprintable key)")' does not carry column '$(sanitize_printable "$2" "(unprintable column)")' (command is fleet-only)" >&2
      exit 2
    fi
    resolve_col "$1" "$2" || exit $?
    printf '\n'
    ;;
  select)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    if ! key_row "$1"; then
      echo "allocation-select: unknown selection key '$(sanitize_printable "$1" "(unprintable key)")' ($KEYS)" >&2
      exit 2
    fi
    emit_row "$1"
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
    for lt_key in $KEYS; do
      key_row "$lt_key" || exit 5 # unreachable: the loop names table rows
      lt_row=$(emit_row "$lt_key") || exit $?
      rows="$rows$lt_key	$lt_row
"
    done
    printf '%s' "$rows"
    ;;
  step-tier)
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    if ! valid_step_type "$1"; then
      printf 'allocation-select: refusing malformed step type %s (must match ^[a-z][a-z0-9-]*$, at most 64 bytes)\n' \
        "'$(sanitize_printable "$1" "(unprintable step type)")'" >&2
      exit 2
    fi
    emit_step_row "$1"
    ;;
  list-steps)
    if [ "$#" -ne 0 ]; then
      usage
      exit 2
    fi
    # Same all-or-nothing posture as `list`: a later-row resolver hard-fail
    # must not leave partial output on stdout.
    st_rows=""
    for st_key in $STEP_KEYS; do
      st_row=$(emit_step_row "$st_key") || exit $?
      st_rows="$st_rows$st_key	$st_row
"
    done
    printf '%s' "$st_rows"
    ;;
  *)
    usage
    exit 2
    ;;
esac
