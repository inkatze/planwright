#!/bin/bash
# Tests for scripts/allocation-adapt.sh — the adaptation engine: event-triggered
# tier resolution at a launch boundary, clamp composition over the consumed
# upstream contracts, and the ledger rows both produce (model-allocation Task 2;
# D-1, D-2, D-6, D-8, D-9, D-13; REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5,
# REQ-D1.1, REQ-D1.2, REQ-F1.1).
#
# The ledger store and the ladder math underneath the engine are covered by
# tests/test-allocation-ledger.sh; this file covers what the engine DECIDES.
#
# What is covered here — the engine's CLAMP layer and its records:
#   - the master knob ships `off` and the engine then reproduces today's fleet
#     allocation EXACTLY (D-13, REQ-A1.2): its output is compared field by field
#     against scripts/fleet-allocate.sh across a rung matrix, which is also the
#     anti-drift tripwire behind risk row 4 — the consumed contract and this
#     spec's re-application of it cannot diverge silently (REQ-D1.1);
#   - clamp composition (REQ-C1.4): each clamp binds per its OWN conditionality
#     (rung-conditional downshift, signal-dependent caps, withheld at the defer
#     rungs, reserved-unit exemption), the cheapest survivor wins, every binding
#     clamp is recorded, and an unreadable clamp input fails closed;
#   - the unavailable signal (REQ-D1.2): escalation above the starting tier is
#     denied, an already-escalated unit HOLDS with no claw-back, and a
#     below-starting unit may still climb back;
#   - degraded mode (REQ-F1.1): an unhealthy ledger launches at the last
#     recorded tier with adjustments suspended and the degradation surfaced;
#   - the sparse governance mirror (REQ-F1.1): governance events reach
#     fleet-audit, routine resolutions do not.
#
# The ladder decisions those clamps are applied to live in
# tests/test-allocation-adapt.sh (see its header for why the two are split).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-clamps.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
AD="$here/../scripts/allocation-adapt.sh"
LEDGER="$here/../scripts/allocation-ledger.sh"
FAL="$here/../scripts/fleet-allocate.sh"
FA="$here/../scripts/fleet-audit.sh"
FUG="$here/../scripts/fleet-usage-gate.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$AD" ] || fail "scripts/allocation-adapt.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped core defaults this engine reads, kept in lockstep with
# config/defaults.yml (test 14 asserts the real file carries the same rows).
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_model_execution: opus
fleet_model_bookkeeping: sonnet
fleet_model_drain: sonnet
fleet_effort_execution: high
fleet_effort_bookkeeping: medium
fleet_effort_drain: low
fleet_command_execution: execute-task
fleet_command_bookkeeping: orchestrate
fleet_command_drain: drain
allocation_model_execution: unset
allocation_model_bookkeeping: unset
allocation_model_drain: unset
allocation_effort_execution: unset
allocation_effort_bookkeeping: unset
allocation_effort_drain: unset
allocation_command_execution: unset
allocation_command_bookkeeping: unset
allocation_command_drain: unset
allocation_model_orchestrate_dispatch: inherit
allocation_effort_orchestrate_dispatch: inherit
allocation_model_execute_step: inherit
allocation_effort_execute_step: inherit
allocation_model_offload: inherit
allocation_effort_offload: inherit
allocation_adaptation: off
allocation_adjustment_cap: 2
fleet_usage_read_cadence_seconds: 60
fleet_usage_signal_ttl_seconds: 300
fleet_downshift_model: sonnet
fleet_downshift_effort: medium
fleet_concurrency_normal: 3
fleet_concurrency_reduced: 1
fleet_cap_fable: 55
fleet_cap_opus: 70
fleet_cap_sonnet: 90
fleet_cap_haiku: 100
fleet_crash_backoff_base_seconds: 30
fleet_crash_disable_threshold: 3
EOF

# Stub outbound clients: any invocation would put an LLM/API call in the
# resolution path, which the determinism floor forbids (REQ-A1.1).
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget gh; do
  cat >"$stubbin/$c" <<EOF
#!/bin/sh
echo "$c" >>"$tmp/invocations"
exit 0
EOF
  chmod +x "$stubbin/$c"
done

env_run() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$@"
}

run() { env_run "$AD" "$@"; }
run_fal() { env_run "$FAL" "$@"; }
run_led() { env_run "$LEDGER" "$@"; }

seed_rung() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" record usage-gate "$1" \
    "test-seed" "seed the rung for allocation" >/dev/null || fail "seeding rung $1 failed"
}

capture_signal() {
  printf 'Current session\n%s%% used\n\nCurrent week (all models)\n%s%% used\n' "$1" "$2" \
    | env_run "$FUG" capture >/dev/null || fail "capturing the signal failed"
}

reset_state() {
  rm -rf "$fleet_home"
  rm -f "$mlocal_cfg" "$tmp/invocations"
}

field() {
  awk -F "$TAB" -v k="$1" '$1 == k { print $2; exit }'
}

# adaptation_on: turn the master knob on through the machine-local layer, which
# is also the overlay-resolution assertion for it (REQ-E1.1).
adaptation_on() {
  printf 'allocation_adaptation: on\n' >"$mlocal_cfg"
  if [ "$#" -gt 0 ]; then
    printf 'allocation_adjustment_cap: %s\n' "$1" >>"$mlocal_cfg"
  fi
}

# escalation_ready [cap]: arm adaptation AND a healthy, low usage signal.
# Escalation above the starting tier is DENIED while the signal is unavailable
# (REQ-D1.2), so a fixture that means to exercise the ladder must supply one;
# tests 9 and 10 deliberately withhold it to exercise that denial instead. 10%
# is below every per-tier cap, so no cap binds and the ladder is what is under
# test.
escalation_ready() {
  adaptation_on "$@"
  capture_signal 10 10
}

# rows_with <unit> <outcome>: count the unit's ledger rows carrying an outcome.
rows_with() {
  run_led rows "$1" | awk -F "$TAB" -v o="$2" 'NF == 15 && $14 == o { n++ } END { print n + 0 }'
}

# --- 1. the master knob ships off, and the engine then equals fleet-allocate --
#
# Field-by-field equivalence against the CONSUMED contract, at every rung and
# with the signal both available and not. This is REQ-A1.2's defaults-preserve
# claim at the fleet surface and REQ-D1.1's untouched-interface tripwire in one:
# if fleet-autonomy changes a rung or cap semantic under this spec's feet, this
# test goes red rather than the two quietly disagreeing in operation.

check_equivalent() {
  ce_key=$1
  ce_label=$2
  ce_mine=$(run resolve "equiv:$ce_key" --key "$ce_key") \
    || fail "1: allocation-adapt resolve $ce_key failed ($ce_label)"
  ce_theirs=$(run_fal resolve "$ce_key") \
    || fail "1: fleet-allocate resolve $ce_key failed ($ce_label)"
  ce_fields="admit command concurrency rung reserved"
  # A WITHHELD unit is returned as withheld and never resolved to a tier (D-8),
  # where the consumed contract still fills in the model/effort cells it would
  # have used. That difference is not selection behavior — a withheld unit never
  # launches, so no operator observes those cells — so the tier comparison is
  # scoped to units that actually dispatch. The withheld OUTCOME itself is
  # compared on every row via `admit`, and pinned directly in test 8.
  if [ "$(printf '%s\n' "$ce_mine" | field admit)" = yes ]; then
    ce_fields="$ce_fields model effort"
  fi
  for ce_f in $ce_fields; do
    ce_a=$(printf '%s\n' "$ce_mine" | field "$ce_f")
    ce_b=$(printf '%s\n' "$ce_theirs" | field "$ce_f")
    [ "$ce_a" = "$ce_b" ] \
      || fail "1: $ce_label/$ce_key: '$ce_f' is '$ce_a' but fleet-allocate says '$ce_b'"
  done
}

for rung in normal downshift reduce-concurrency defer-heavy defer-all; do
  reset_state
  [ "$rung" = normal ] || seed_rung "$rung"
  for key in execution drain; do
    check_equivalent "$key" "rung=$rung, signal unavailable"
  done
done

reset_state
capture_signal 75 80
for key in execution drain; do
  check_equivalent "$key" "rung=normal, signal 80%"
done
echo "ok: with the master knob off, the engine reproduces fleet-allocate exactly"

# Nothing in the resolution path reached an outbound client.
[ ! -f "$tmp/invocations" ] || fail "1z: an outbound client was invoked in the resolution path"

# --- 8. clamp composition per upstream semantics (REQ-C1.4) ---------------

# Downshift is RUNG-CONDITIONAL: it binds at `downshift`, not at `normal`.
reset_state
escalation_ready 3
out=$(run resolve clamp:unit --key drain --step s1 --attempt 1 \
  --event step-failure --event flailing --event non-convergence) || fail "8: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = opus ] || fail "8a: at normal nothing should clamp"

reset_state
escalation_ready 3
seed_rung downshift
out=$(run resolve clamp2:unit --key drain --step s1 --attempt 1 \
  --event step-failure --event flailing --event non-convergence) || fail "8: resolve failed"
[ "$(printf '%s\n' "$out" | field proposed_model)" = opus ] || fail "8b: the PROPOSAL should still climb to opus"
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "8b: downshift should clamp the resolved model to sonnet"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "8b: downshift should clamp the resolved effort to medium"
# A clamp is recorded as CLAMPED, never as de-escalation: the unit's own tier is
# unmoved, so the next boundary still proposes from opus.
[ "$(printf '%s\n' "$out" | field net)" = 3 ] || fail "8c: a clamp must not consume adjustment budget"
run_led rows clamp2:unit | grep -q "downshift" || fail "8d: the binding clamp was not recorded in the row"

# Per-tier caps are SIGNAL-DEPENDENT: active only while the signal is available,
# and they move the proposal to the nearest surviving cheaper model with the
# EFFORT PRESERVED.
reset_state
adaptation_on 3
capture_signal 75 75
out=$(run resolve cap2:unit --key drain --step s1 --attempt 1 \
  --event step-failure --event flailing --event non-convergence) || fail "8: resolve failed"
[ "$(printf '%s\n' "$out" | field proposed_model)" = opus ] || fail "8e: the proposal should be opus"
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "8e: at 75% the opus cap (70) should bind down to sonnet"
[ "$(printf '%s\n' "$out" | field effort)" = high ] || fail "8e: a cap clamp preserves the effort"

# The defer rungs yield a WITHHELD unit, never a tier.
reset_state
adaptation_on
seed_rung defer-all
out=$(run resolve wh:unit --key drain --step s1 --attempt 1) || fail "8: resolve failed"
[ "$(printf '%s\n' "$out" | field admit)" = withheld ] || fail "8f: defer-all must withhold"
[ "$(rows_with wh:unit withheld)" -ge 1 ] || fail "8g: a withheld unit must record a withheld row"

# The reserved-unit exemption passes through untouched.
reset_state
adaptation_on
seed_rung downshift
out=$(run resolve res:unit --key execution --step s1 --attempt 1 --reserved) || fail "8: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = opus ] || fail "8h: a reserved unit is exempt from downshift"
[ "$(printf '%s\n' "$out" | field reserved)" = yes ] || fail "8h: the reserved flag is not reported"

# Composition: two clamps in conflict, the CHEAPEST survivor wins and both are
# recorded. At `downshift` (cap sonnet/medium) with the signal at 92% (sonnet's
# cap is 90) the cap pushes past the downshift model to haiku.
reset_state
adaptation_on 3
seed_rung downshift
capture_signal 92 92
out=$(run resolve comp:unit --key drain --step s1 --attempt 1 \
  --event step-failure --event flailing --event non-convergence) || fail "8: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = haiku ] || fail "8i: composition should pick the cheapest survivor (haiku)"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "8i: the downshift effort clamp should still bind"
row=$(run_led rows comp:unit | awk -F "$TAB" 'NF == 15 && $14 == "resolved" { r = $15 } END { print r }')
case $row in
  *downshift*) ;;
  *) fail "8j: the downshift clamp is missing from the composed row: '$row'" ;;
esac
case $row in
  *cap*) ;;
  *) fail "8j: the cap clamp is missing from the composed row: '$row'" ;;
esac
echo "ok: each clamp binds per its own conditionality and composition picks the cheapest survivor"

# --- 9. an unreadable clamp input fails closed (D-8) ----------------------

reset_state
adaptation_on 3
# A corrupt trail: the last usage-gate action is not a known rung, so the gate
# refuses to derive one — the unreadable-clamp-input case.
PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" record usage-gate not-a-rung \
  "test-seed" "corrupt the derived rung" >/dev/null || fail "9: seeding failed"
out=$(run resolve closed:unit --key drain --step s1 --attempt 1 --event step-failure) \
  || fail "9: resolve should degrade, not abort"
[ "$(printf '%s\n' "$out" | field degraded)" = clamp-input ] || fail "9a: the degraded read was not recorded"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "9b: escalation must be denied on an unreadable clamp input"
[ "$(rows_with closed:unit denied)" -ge 1 ] || fail "9c: the denial was not recorded"
# Downshift VALUES are applied in the spend-safe direction.
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "9d: downshift values should apply on a degraded read"
echo "ok: an unreadable clamp input fails closed — escalation denied, downshift applied, read recorded"

# --- 10. the unavailable signal denies escalation and holds (REQ-D1.2) ----

reset_state
adaptation_on 3
# No captured signal at all: unavailable.
out=$(run resolve sig:unit --key drain --step s1 --attempt 1 --event step-failure) \
  || fail "10: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "10a: escalation above the starting tier must be denied"
[ "$(rows_with sig:unit denied)" -ge 1 ] || fail "10b: the denial was not recorded"

# An already-escalated unit HOLDS its tier — no claw-back.
reset_state
adaptation_on 3
capture_signal 10 10
run resolve hold:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "10: resolve failed"
rm -rf "$fleet_home/usage"
out=$(run resolve hold:unit --key drain --step s2 --attempt 1 --event flailing) \
  || fail "10: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "10c: an escalated unit must hold, not claw back"
[ "$(printf '%s\n' "$out" | field net)" = 1 ] || fail "10c: the held unit's displacement changed"

# A BELOW-starting unit may still climb back TO its starting tier.
reset_state
adaptation_on 3
out=$(run resolve back:unit --key drain --step s1 --attempt 1 --event petition-de-escalate) \
  || fail "10: resolve failed"
[ "$(printf '%s\n' "$out" | field net)" = -1 ] || fail "10d: the de-escalation did not take"
out=$(run resolve back:unit --key drain --step s2 --attempt 1 --event step-failure) \
  || fail "10: resolve failed"
[ "$(printf '%s\n' "$out" | field net)" = 0 ] || fail "10e: a below-starting unit must be able to climb back"
echo "ok: an unavailable signal denies escalation above start, holds altitude, and allows climb-back"

# --- 11. degraded mode on an unhealthy ledger (REQ-F1.1) ------------------

reset_state
adaptation_on 3
capture_signal 10 10
run resolve deg:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "11: resolve failed"
led_file=$(run_led path deg:unit)
printf 'torn\trow\n' >>"$led_file"
err="$tmp/deg.err"
out=$(run resolve deg:unit --key drain --step s2 --attempt 1 --event flailing 2>"$err") \
  || fail "11a: an unhealthy ledger must degrade, never block the launch"
[ "$(printf '%s\n' "$out" | field adaptation)" = suspended ] || fail "11b: adjustments were not suspended"
[ "$(printf '%s\n' "$out" | field degraded)" = ledger ] || fail "11c: the degradation was not reported"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "11d: a degraded launch must use the LAST RECORDED tier"
[ -s "$err" ] || fail "11e: the degradation was not surfaced — a silent degrade is the failure mode"
echo "ok: an unhealthy ledger launches degraded at the last recorded tier, surfaced, never silent"

# --- 12. the sparse governance mirror into fleet-audit (REQ-F1.1) ---------

mirror_rows() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" query --mechanism allocation 2>/dev/null \
    | awk -F "$TAB" 'NF >= 4 { n++ } END { print n + 0 }'
}

reset_state
escalation_ready 3
run resolve routine:unit --key drain --step s1 --attempt 1 >/dev/null || fail "12: resolve failed"
[ "$(mirror_rows)" = 0 ] || fail "12a: a routine resolution must not touch the shared trail"
run resolve routine:unit --key drain --step s2 --attempt 1 --event step-failure >/dev/null \
  || fail "12: resolve failed"
[ "$(mirror_rows)" -ge 1 ] || fail "12b: an escalation must mirror one governance row into fleet-audit"
echo "ok: governance events mirror into fleet-audit; routine resolutions do not"

echo "PASS: allocation-clamps ($(basename "$0"))"
