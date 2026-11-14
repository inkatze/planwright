#!/bin/sh
# allocation-select.sh — resolves the configured model, effort and command for
# a launch, by table lookup plus config reads: no network, no LLM, no
# subprocess beyond the shared knob resolver. It only resolves; applying the
# choice is allocation-apply.sh's job, and comparing a step tier against its
# unit's tier is allocation-adapt.sh's.
#
# Two axes, resolved by separate verbs over separate knob families:
#
#   Selection key (a whole unit). Keys and shipped defaults:
#
#     key                    model    effort   command       legacy family
#     execution              opus     high     execute-task  fleet_*_execution
#     bookkeeping            sonnet   medium   orchestrate   fleet_*_bookkeeping
#     drain                  sonnet   low      drain         fleet_*_drain
#     orchestrate_dispatch   inherit  inherit  (none)        (none)
#     execute_step           inherit  inherit  (none)        (none)
#     offload                inherit  inherit  (none)        (none)
#
#   The first three are the fleet task types; their cells match the golden
#   baseline in tests/fixtures/allocation-golden-baseline.tsv, and
#   fleet-resource-select.sh is a thin front door onto them. The last three
#   are the non-fleet surfaces, which ship `inherit` (apply nothing, keep the
#   launch's ambient value), so an unconfigured operator sees no change.
#
#   Step type (one step of a unit): implementation, or a step id. Only model
#   and effort, as allocation_<column>_step_<step-type>, shipped `inherit`.
#   The key space is open: any charset-valid step type resolves, and an
#   unconfigured one is `inherit`, so a new step needs no edit here.
#
# Knob chain for a selection key's column:
#   1. allocation_<column>_<key>, through the shared resolver's overlay layers.
#   2. If that is the `unset` sentinel, the deprecated legacy knob
#      fleet_<column>_<key>, so existing fleet overlays keep working. Core
#      ships `unset` for the fleet-keyed general knobs to arm this.
#   3. If the key has no legacy counterpart, its shipped default.
# A set general knob returns before the legacy one is read, so a malformed
# legacy knob it shadows does not hard-fail.
#
# Enums are the Claude Code aliases, not dated ids. The model enum is the
# ladder's starting roster, without its escalation-only top model, so a
# config that starts a unit there is refused as out of enum. `inherit` is
# legal only where the surface has an ambient value: the three non-fleet keys
# and step types. At a fleet key it is refused, since fleet dispatch has
# nothing to inherit from.
#
# The command column is fleet-only and is exactly the dispatch-entry set
# {execute-task orchestrate drain}. No step type carries it, so adding a step
# can never widen the set, which keeps it disjoint from every step a point may
# run. For keys without it, `resolve <key> command` is refused and
# `select`/`list` print `-`.
#
# Usage:
#   allocation-select.sh resolve <key> <column>
#       Print one value; <column> is model | effort | command.
#   allocation-select.sh select <key>
#       Print <model>TAB<effort>TAB<command> ('-' without a command column).
#   allocation-select.sh list
#       Print every key as <key>TAB<model>TAB<effort>TAB<command>.
#   allocation-select.sh step-tier <step-type>
#       Print <model>TAB<effort> for one step type.
#   allocation-select.sh list-steps
#       Print the shipped step types as <step-type>TAB<model>TAB<effort>.
#
# Environment: honors every override the shared knob resolver honors
# (PLANWRIGHT_CONFIG_DEFAULTS, PLANWRIGHT_ADOPTER_OVERLAY,
# PLANWRIGHT_REPO_ROOT, PLANWRIGHT_LOCAL_CONFIG, CLAUDE_PLUGIN_ROOT/DATA).
#
# Exit codes: 0 printed; 2 usage error, unknown or hostile key or column, or a
# column the key does not carry (fail closed, never a silent default); 4
# malformed repo-tracked knob (propagated from the resolver); 5 broken
# install (resolver unavailable or a core default itself malformed).
#
# POSIX sh on the macOS + Linux support bar. All input is data. Pathname
# expansion is disabled (set -f).
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
if [ ! -f "$echo_safety" ] || [ ! -r "$echo_safety" ]; then
  printf '%s\n' "allocation-select: echo-discipline sanitizer echo-safety.sh is missing or not readable — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

# The model roster and the ladder's rank map, sourced rather than restated:
# allocation-ladder.sh is the single definition, and a second copy here is the
# drift its header exists to prevent. Guarded on the same terms as the
# sanitizer above, for the same reason.
ladder="$script_dir/allocation-ladder.sh"
if [ ! -r "$ladder" ]; then
  printf '%s\n' "allocation-select: tier ladder '$ladder' is missing or not readable — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/allocation-ladder.sh
. "$ladder"

RESOLVER="$script_dir/resolve-config-knob.sh"

# The stable per-column enums (REQ-A1.4): model to the Claude Code aliases the
# ladder's roster names — aliases, not dated model ids, so the enum survives
# model releases; effort to the three reasoning tiers; command to the
# dispatch-entry set.
#
# THE MODEL ENUM IS THE STARTING ROSTER, which is the ladder's roster minus its
# top. The top model is ESCALATION-ONLY: the successor rule raises effort to
# `high` and only then the model one alias, so (top, high) is the top's one
# reachable coordinate. A unit CONFIGURED to start there would begin with the
# ladder's whole headroom already spent and no rung to escalate into, which is
# not a tier this table can price. Naming it in a config is therefore refused
# on exactly the terms `inherit` at a fleet key is refused — as an out-of-enum
# value under the by-layer policy, so the diagnostic points at the knob that is
# wrong. Escalation still reaches the top; only STARTING there is refused.
MODEL_VALUES="$ALLOC_START_MODELS_DESC"
EFFORT_VALUES="$ALLOC_EFFORTS"
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
# step, then one per step id the core steps catalog seeds.
#
# The step-type key space is OPEN by construction rather than a closed enum.
# The step ids are DECLARED in the merged steps catalog
# (resolve-steps.sh owns reading it), so a second copy of them here would
# drift — and a stale copy would REFUSE a legitimately configured step rather
# than degrade, turning an operator's working config into a launch
# failure. Instead any charset-valid step type resolves, and one with no
# configured knob resolves to `inherit`, which applies nothing. A step
# added tomorrow therefore inherits silently and correctly with no edit here.
# This list is what `list-steps` enumerates and what config/defaults.yml ships
# rows for; it is a shipped set, not a validation boundary.
STEP_KEYS="implementation polish self-review"

usage() {
  echo "usage: allocation-select.sh resolve <key> <column> | select <key> | list | step-tier <step-type> | list-steps" >&2
  printf '%s\n' "  keys:       $KEYS" >&2
  echo "  columns:    model | effort | command (command: fleet task types only)" >&2
  printf '%s\n' "  step types: $STEP_KEYS (open set; any unconfigured one resolves to inherit)" >&2
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
    printf '%s\n' "allocation-select: shared knob resolver '$RESOLVER' is missing or not executable — broken install" >&2
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

# valid_step_type <token>: 0 for the step-id charset (^[a-z][a-z0-9-]*$),
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
# names are ^[a-z][a-z0-9_]*$ (config-get's queryable charset) while step
# ids are ^[a-z][a-z0-9-]*$, so `-` maps to `_` (`self-review` ->
# `self_review`). The map is INJECTIVE over the step-id charset — a step id
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
      printf '%s\n' "allocation-select: unknown selection key '$(sanitize_printable "$1" "(unprintable key)")' ($KEYS)" >&2
      exit 2
    fi
    cs_rc=0
    col_spec "$2" || cs_rc=$?
    if [ "$cs_rc" -eq 2 ]; then
      printf '%s\n' "allocation-select: unknown column '$(sanitize_printable "$2" "(unprintable column)")' (model | effort | command)" >&2
      exit 2
    elif [ "$cs_rc" -ne 0 ]; then
      printf '%s\n' "allocation-select: key '$(sanitize_printable "$1" "(unprintable key)")' does not carry column '$(sanitize_printable "$2" "(unprintable column)")' (command is fleet-only)" >&2
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
      printf '%s\n' "allocation-select: unknown selection key '$(sanitize_printable "$1" "(unprintable key)")' ($KEYS)" >&2
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
