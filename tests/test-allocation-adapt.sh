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
# What is covered here — the engine's LADDER decisions:
#   - the master knob ships `off`, so a trigger event is inert (D-13);
#   - escalation (REQ-C1.2): one ladder step per distinct incident class, one
#     row each; a failure and the retry it caused collapse to one step; the
#     closed trigger allowlist refuses infrastructure failures; a crash replay
#     of the same event re-derives without double-counting;
#   - the per-unit adjustment cap (D-8): bounded in both directions, with
#     reversals refunding budget;
#   - de-escalation (D-8): a petition reverses the most recent unreversed
#     escalation, and with none to reverse it steps below the starting tier;
#     both ladder ends are hard stops that no-op with a row;
#   - inheritance at a non-fleet key, and stuck states folding into the existing
#     crash-loop machinery (REQ-C1.5).
#
# The clamp layer, the golden-baseline equivalence against fleet-allocate.sh,
# degraded mode, and the fleet-audit mirror live in
# tests/test-allocation-clamps.sh, which is a separate file so the two run in
# parallel: each resolve spawns the whole knob-resolver chain, so one combined
# suite is several minutes of wall clock for no extra coverage.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-adapt.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
AD="$here/../scripts/allocation-adapt.sh"
LEDGER="$here/../scripts/allocation-ledger.sh"
FA="$here/../scripts/fleet-audit.sh"
FUG="$here/../scripts/fleet-usage-gate.sh"
FLV="$here/../scripts/fleet-liveness.sh"
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
allocation_model_step_implementation: inherit
allocation_effort_step_implementation: inherit
allocation_model_step_polish: inherit
allocation_effort_step_polish: inherit
allocation_model_step_self_review: inherit
allocation_effort_step_self_review: inherit
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

# --- 2. with adaptation off, a trigger event changes nothing ---------------

reset_state
out=$(run resolve off:unit --key execution --step s1 --attempt 1 --event step-failure) \
  || fail "2: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = opus ] || fail "2a: an event moved the tier with adaptation off"
[ "$(printf '%s\n' "$out" | field adaptation)" = off ] || fail "2b: adaptation is not reported off"
[ "$(rows_with off:unit applied)" = 0 ] || fail "2c: adaptation off still applied a ladder step"
# Telemetry is exempt from the behavior-preservation claim (D-13): the row lands.
[ "$(rows_with off:unit resolved)" = 1 ] || fail "2d: the resolution row was not recorded"
echo "ok: with adaptation off, events are inert but the resolution is still recorded"

# --- 3. escalation: one step per incident class, one row each (REQ-C1.2) ---

reset_state
escalation_ready
out=$(run resolve esc:unit --key drain --step s1 --attempt 1 --event step-failure) \
  || fail "3: resolve failed"
# drain starts at (sonnet, low); one step is (sonnet, medium).
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "3a: model should stay sonnet"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "3a: one step should raise effort to medium"
[ "$(rows_with esc:unit applied)" = 1 ] || fail "3b: one event should append exactly one applied row"

# A failure and the retry it caused are ONE incident: same key, one step.
reset_state
escalation_ready
out=$(run resolve inc:unit --key drain --step s1 --attempt 1 \
  --event step-failure --event retry) || fail "3: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "3c: same-incident classes must not stack"
[ "$(rows_with inc:unit applied)" = 1 ] || fail "3d: same-incident classes appended $(rows_with inc:unit applied) rows, want 1"

# Three INDEPENDENT incident classes at one boundary climb three steps and
# append three rows: (sonnet,low) -> (sonnet,medium) -> (sonnet,high) -> (opus,high).
reset_state
escalation_ready 3
out=$(run resolve stack:unit --key drain --step s1 --attempt 1 \
  --event step-failure --event flailing --event non-convergence) || fail "3: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = opus ] || fail "3e: three steps should reach opus, got $(printf '%s\n' "$out" | field model)"
[ "$(printf '%s\n' "$out" | field effort)" = high ] || fail "3e: the model hinge must keep effort high"
[ "$(rows_with stack:unit applied)" = 3 ] || fail "3f: N classes should append N rows, got $(rows_with stack:unit applied)"
echo "ok: distinct incident classes stack one step each; same-incident classes collapse"

# --- 4. the closed trigger allowlist refuses infrastructure failures -------

reset_state
adaptation_on
if run resolve infra:unit --key drain --step s1 --attempt 1 \
  --event audit-write-error >/dev/null 2>&1; then
  fail "4a: an infrastructure-failure event class was accepted as a trigger"
fi
if run resolve infra:unit --key drain --step s1 --attempt 1 \
  --event config-hard-fail >/dev/null 2>&1; then
  fail "4b: a config hard-fail was accepted as a trigger"
fi
[ "$(rows_with infra:unit applied)" = 0 ] || fail "4c: a refused event still moved the tier"
echo "ok: the trigger grammar is a closed allowlist; infra failures never escalate"

# --- 4b. the identity grammars are the LEDGER's, checked at the boundary ---

# The engine refuses a malformed step or attempt where the argument enters,
# because past that point the ledger's own refusal arrives as a FAILED APPEND,
# which the engine can only report as a degraded ledger. A plain usage error
# then reads as a corrupt store, and the launch proceeds instead of stopping.

reset_state
adaptation_on
long_step=$(awk 'BEGIN { s = ""; while (length(s) < 200) s = s "a"; print s }')
if run resolve ident:unit --key drain --step "$long_step" --attempt 1 >/dev/null 2>&1; then
  fail "4b-a: a step past the ledger's 128-character bound was accepted"
fi
if run resolve ident:unit --key drain --step s1 --attempt 01 >/dev/null 2>&1; then
  fail "4b-b: an attempt with a leading zero was accepted"
fi
# The boundary must not tighten PAST the store either: `0` is a legal count in
# the ledger's grammar, so refusing it here would reject a launch the ledger
# would have recorded happily.
out=$(run resolve ident:unit --key drain --step s1 --attempt 0) \
  || fail "4b-c: attempt 0 was refused, but the ledger's count grammar accepts it"
[ "$(printf '%s\n' "$out" | field degraded)" = no ] \
  || fail "4b-d: a well-formed launch reported a degraded ledger"
echo "ok: step and attempt are refused at the boundary, never as a degraded ledger"

# --- 5. crash replay: the same event does not double-count (REQ-C1.2) ------

reset_state
escalation_ready
run resolve replay:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "5: first resolve failed"
out=$(run resolve replay:unit --key drain --step s1 --attempt 1 --event step-failure) \
  || fail "5: replayed resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "5a: a replayed event double-counted"
[ "$(rows_with replay:unit applied)" = 1 ] || fail "5b: a replayed event appended a second applied row"
# A genuinely NEW incident (a later attempt) does move the tier.
out=$(run resolve replay:unit --key drain --step s1 --attempt 2 --event step-failure) \
  || fail "5: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = high ] || fail "5c: a new attempt should be a fresh incident"
echo "ok: idempotency keys make a crash replay converge without double-counting"

# --- 6. the per-unit adjustment cap, both directions, with refunds (D-8) --

reset_state
escalation_ready 1
run resolve cap:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "6: resolve failed"
out=$(run resolve cap:unit --key drain --step s2 --attempt 1 --event flailing) \
  || fail "6: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "6a: the cap did not bound the second climb"
[ "$(rows_with cap:unit denied)" -ge 1 ] || fail "6b: a cap-exhausted escalation must record a denial"
[ "$(printf '%s\n' "$out" | field net)" = 1 ] || fail "6c: net displacement should be pinned at the cap"

# A reversal REFUNDS the budget, so a later escalation fits again.
out=$(run resolve cap:unit --key drain --step s3 --attempt 1 --event petition-de-escalate) \
  || fail "6: resolve failed"
[ "$(printf '%s\n' "$out" | field net)" = 0 ] || fail "6d: the reversal did not refund the cap budget"
out=$(run resolve cap:unit --key drain --step s4 --attempt 1 --event step-failure) \
  || fail "6: resolve failed"
[ "$(printf '%s\n' "$out" | field net)" = 1 ] || fail "6e: the refunded budget was not reusable"

# The cap bounds the DOWN direction symmetrically.
reset_state
adaptation_on 1
run resolve down:unit --key drain --step s1 --attempt 1 --event petition-de-escalate >/dev/null \
  || fail "6: resolve failed"
out=$(run resolve down:unit --key drain --step s2 --attempt 1 --event petition-de-escalate) \
  || fail "6: resolve failed"
[ "$(printf '%s\n' "$out" | field net)" = -1 ] || fail "6f: the cap did not bound de-escalation"
[ "$(rows_with down:unit denied)" -ge 1 ] || fail "6g: a cap-exhausted de-escalation must record a denial"
echo "ok: the adjustment cap bounds net displacement in both directions, refunds included"

# --- 7. de-escalation: reversal first, mirror rule after (D-8) -------------

reset_state
escalation_ready 3
# Climb twice from (sonnet, low): -> (sonnet, medium) -> (sonnet, high).
run resolve rev:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null
run resolve rev:unit --key drain --step s2 --attempt 1 --event step-failure >/dev/null
out=$(run resolve rev:unit --key drain --step s3 --attempt 1 --event petition-de-escalate) \
  || fail "7: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] \
  || fail "7a: the reversal should restore the pre-step tier, got $(printf '%s\n' "$out" | field effort)"

# With nothing left to reverse, a petition steps BELOW the starting tier by the
# mirror rule, and the ladder floor is a hard stop that no-ops with a row.
reset_state
adaptation_on 3
out=$(run resolve floor:unit --key drain --step s1 --attempt 1 --event petition-de-escalate) \
  || fail "7: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = haiku ] || fail "7b: the mirror hinge should step the model to haiku"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "7b: the mirror hinge should keep effort low"
out=$(run resolve floor:unit --key drain --step s2 --attempt 1 --event petition-de-escalate) \
  || fail "7: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = haiku ] || fail "7c: the ladder floor is not a hard stop"
[ "$(rows_with floor:unit no-op)" -ge 1 ] || fail "7d: a floored de-escalation must record a no-op row"

# The ladder TOP is a hard stop too, with its own no-op row.
reset_state
adaptation_on 4
printf 'allocation_model_drain: fable\nallocation_effort_drain: high\n' >>"$mlocal_cfg"
capture_signal 10 10
out=$(run resolve top:unit --key drain --step s1 --attempt 1 --event step-failure) \
  || fail "7: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = fable ] || fail "7e: the ladder top should hold at fable"
[ "$(rows_with top:unit no-op)" -ge 1 ] || fail "7f: a ladder-top escalation must record a no-op row"
echo "ok: de-escalation reverses before mirroring; both ladder ends are hard stops"

# --- 13. inherit surfaces, and stuck states folding into crash-loop -------

reset_state
adaptation_on 3
out=$(run resolve inh:unit --key execute_step --step s1 --attempt 1 --event step-failure) \
  || fail "13: resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = inherit ] || fail "13a: a non-fleet key should resolve to inherit"
[ "$(printf '%s\n' "$out" | field effort)" = inherit ] || fail "13a: the effort should inherit too"
[ "$(printf '%s\n' "$out" | field command)" = - ] || fail "13b: a non-fleet key carries no command column"
[ "$(rows_with inh:unit inherit)" -ge 1 ] || fail "13c: an inheritance must be recorded, never silent"

# REQ-C1.5: a unit that cannot escalate introduces NO new hold state — the
# existing crash-loop machinery governs, driven through its own interface.
reset_state
escalation_ready 1
run resolve stuck:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null
run resolve stuck:unit --key drain --step s2 --attempt 1 --event flailing >/dev/null
[ "$(rows_with stuck:unit denied)" -ge 1 ] || fail "13d: the cap-exhausted denial was not recorded"
last_state=""
i=1
while [ "$i" -le 3 ]; do
  last_state=$(env_run "$FLV" crash-record stuck-worker spec-1 2>/dev/null | awk '{ print $1 }') \
    || fail "13e: crash-record failed"
  i=$((i + 1))
done
[ "$last_state" = disabled ] \
  || fail "13e: the existing disable threshold did not govern (got '$last_state')"
# The engine's outcome vocabulary carries no parallel stuck/hold state.
if grep -qE "^ALLOC_OUTCOMES=.*(blocked|hold|stuck|budget-wait)" "$here/../scripts/allocation-ledger.sh"; then
  fail "13f: the ledger introduced a parallel stuck state — REQ-C1.5 forbids one"
fi
echo "ok: inheritance is audited, and a cannot-escalate unit folds into the existing crash-loop path"

# --- 13b. concurrent same-unit launches serialize on the per-unit lock ----
#
# Two launches of the SAME unit racing at one boundary: the lock makes each
# derive-then-append one critical section, so the second sees the first's row
# and its idempotency key rather than deriving from a pre-move ledger. The unit
# climbs at most one step, exactly one applied row lands, and the ledger stays
# healthy (no duplicate sequence number, no torn row).

reset_state
escalation_ready 3
run resolve race:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null 2>&1 &
run resolve race:unit --key drain --step s1 --attempt 1 --event step-failure >/dev/null 2>&1 &
wait
[ "$(rows_with race:unit applied)" = 1 ] \
  || fail "13g: racing same-unit launches applied $(rows_with race:unit applied) steps, want 1"
out=$(run resolve race:unit --key drain --step s2 --attempt 1) || fail "13: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] \
  || fail "13h: the raced unit is not one step up: $(printf '%s\n' "$out" | field effort)"
run_led health race:unit || fail "13i: racing launches left the ledger unhealthy"
seqs=$(run_led rows race:unit | cut -f1)
[ "$(printf '%s\n' "$seqs" | wc -l)" = "$(printf '%s\n' "$seqs" | sort -n | uniq | wc -l)" ] \
  || fail "13j: racing launches produced duplicate sequence numbers"
echo "ok: concurrent same-unit launches serialize on the per-unit lock"

# --- 13c. a fatal signal ENDS the run; it never resumes unlocked -----------
#
# The lock's whole guarantee is that derive-then-append is one critical section.
# A bare `trap release_unit_lock ... TERM` breaks it: the handler runs, releases
# the lock, and then execution RETURNS into the unfinished section — where
# `record` still exports PLANWRIGHT_ALLOC_LOCK_HELD, so the append skips its own
# acquire too and writes with no lock held at all. The observable contract that
# pins the fix is the exit status: a signalled resolve must terminate, never
# report success. (Verified on both shells of the support bar: dash and bash
# each run the handler and resume.)

reset_state
escalation_ready 3
# Hold the engine INSIDE the armed critical section while the signal lands,
# instead of racing it. The locked append is the only place the engine runs
# `date` with PLANWRIGHT_ALLOC_LOCK_HELD in the environment (`record` sets it
# for exactly that call, strictly after take_unit_lock has armed the traps), so
# a `date` stub that blocks on a fifo under that variable pins the engine
# there: no signal-before-the-traps false pass, and no fast-machine false fail
# where the resolve finishes before the signal arrives. The stub's marker file
# is the synchronization point; the fifo write is the release.
sigstub="$tmp/sigstub"
mkdir -p "$sigstub"
sig_real_date=$(command -v date) || fail "13k: no date on PATH"
mkfifo "$tmp/sig-gate" || fail "13k: could not create the gate fifo"
cat >"$sigstub/date" <<EOF
#!/bin/sh
if [ "\${PLANWRIGHT_ALLOC_LOCK_HELD:-}" = "sig:unit" ] && [ ! -e "$tmp/sig-released" ]; then
  : >"$tmp/sig-blocked"
  cat "$tmp/sig-gate" >/dev/null
fi
exec "$sig_real_date" "\$@"
EOF
chmod +x "$sigstub/date"
# `exec`, so the backgrounded pid IS the engine rather than the env-setting
# subshell around it: signalling the wrapper would report a killed wrapper and
# pass whatever the engine did.
(
  export PATH="$sigstub:$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG=""
  exec /bin/bash "$AD" resolve sig:unit --key drain --step s1 --attempt 1
) >/dev/null 2>&1 &
sig_pid=$!
sig_waited=0
while [ ! -e "$tmp/sig-blocked" ]; do
  sleep 0.05
  sig_waited=$((sig_waited + 1))
  [ "$sig_waited" -lt 600 ] \
    || fail "13k: the resolve never reached the locked append, so the signal had nothing to interrupt"
done
kill -TERM "$sig_pid" 2>/dev/null \
  || fail "13k: the engine was gone before the signal could land"
# Release the gate AFTER the signal is delivered: the pending TERM fires at the
# next command boundary inside the critical section. The released marker keeps
# any later locked `date` call from re-blocking on a fifo nobody will write.
: >"$tmp/sig-released"
printf '' >"$tmp/sig-gate"
sig_rc=0
wait "$sig_pid" 2>/dev/null || sig_rc=$?
[ "$sig_rc" = 143 ] \
  || fail "13k: a SIGTERM'd resolve exited $sig_rc, want 143 — the handler released the lock and the run resumed unlocked"
echo "ok: a fatal signal ends the run rather than resuming the critical section unlocked"

# --- 14. the shipped config carries the knobs this engine reads -----------

real_cfg="$here/../config/defaults.yml"
for k in allocation_adaptation allocation_adjustment_cap; do
  grep -q "^$k:" "$real_cfg" || fail "14: config/defaults.yml is missing '$k'"
done
# Quoted in the shipped file: bare `off` is a YAML boolean. The resolver strips
# the quotes, so both spellings resolve to the same enum member.
grep -qE '^allocation_adaptation: "?off"?$' "$real_cfg" \
  || fail "14: the master knob must ship 'off' (D-13)"


# --- 15. per-step selection keys (Task 5; D-8, D-12, REQ-C1.3) -------------
#
# A step-type tier is STATIC configuration keyed by step class, not adaptation:
# it never moves the unit's own ladder position. Its application is strictly
# ONE-DIRECTIONAL — a cheaper configured tier applies for that step's launch
# only and is scope-marked in the ledger; an equal or more expensive one is
# ignored with a row. A step may never ratchet a unit up.

# step_knobs <step-type-suffix> <model> <effort>: configure one step type
# through the machine-local layer (also the REQ-E1.1 overlay assertion for it).
# `-` leaves that column unconfigured, which is the shipped `inherit`.
step_knobs() {
  [ "$2" = - ] || printf 'allocation_model_step_%s: %s\n' "$1" "$2" >>"$mlocal_cfg"
  [ "$3" = - ] || printf 'allocation_effort_step_%s: %s\n' "$1" "$3" >>"$mlocal_cfg"
}

# step_rows <unit>: the unit's STEP-scoped ledger rows (column 13).
step_rows() {
  run_led rows "$1" | awk -F "$TAB" 'NF == 15 && $13 == "step" { print }'
}

# --- 15a. defaults: every step resolves to the unit's tier -----------------
#
# The golden baseline (opus/high at `execution`), reached through the step-type
# path with nothing configured. This is the claim that landing per-step keys
# changes runtime behavior by exactly nothing.

reset_state
out=$(run resolve stepdef:unit --key execution --step-type implementation) \
  || fail "15a: resolve with a step type failed"
[ "$(printf '%s\n' "$out" | field model)" = opus ] \
  || fail "15a: an unconfigured step type must resolve to the unit's tier, got $(printf '%s\n' "$out" | field model)"
[ "$(printf '%s\n' "$out" | field effort)" = high ] \
  || fail "15a: an unconfigured step type must keep the unit's effort"
[ "$(printf '%s\n' "$out" | field step_scope)" = inherit ] \
  || fail "15a: an unconfigured step type must report an inherit step scope"
echo "ok: with defaults a step resolves to the unit's tier"

# Every shipped review-sequence step class behaves the same way by default.
for st in polish self-review; do
  reset_state
  out=$(run resolve "stepdef:$st" --key execution --step-type "$st") \
    || fail "15a: resolve --step-type $st failed"
  [ "$(printf '%s\n' "$out" | field model)/$(printf '%s\n' "$out" | field effort)" = opus/high ] \
    || fail "15a: review step class '$st' must default to the unit's tier"
done
echo "ok: every shipped review-sequence step class defaults to the unit's tier"

# --- 15b. a cheaper configured step tier applies, scope-marked -------------

reset_state
step_knobs self_review haiku low
out=$(run resolve cheap:unit --key execution --step-type self-review) \
  || fail "15b: resolve with a cheaper step tier failed"
[ "$(printf '%s\n' "$out" | field model)" = haiku ] \
  || fail "15b: a cheaper step tier must apply, got $(printf '%s\n' "$out" | field model)"
[ "$(printf '%s\n' "$out" | field effort)" = low ] \
  || fail "15b: the cheaper step tier's effort must apply"
[ "$(printf '%s\n' "$out" | field step_scope)" = applied ] \
  || fail "15b: an applied step tier must report an applied step scope"
[ "$(step_rows cheap:unit | wc -l | tr -d ' ')" = 1 ] \
  || fail "15b: an applied step tier must leave exactly one step-scoped ledger row"
[ "$(step_rows cheap:unit | awk -F "$TAB" '{ print $14 }')" = applied ] \
  || fail "15b: the step-scoped row must carry the applied outcome"
echo "ok: a cheaper configured step tier applies and is scope-marked"

# --- 15c. the restore-after fixture ----------------------------------------
#
# The one property that makes step scope safe: a scope-marked step launch must
# not leak into the unit's own ladder position. Run it against a unit that has
# ACTUALLY MOVED — a defaults-only unit sits at its starting tier either way, so
# it cannot tell a preserved ladder from an absent one.

reset_state
escalation_ready
step_knobs self_review haiku low
# One escalation: bookkeeping starts at sonnet/medium, so this lands sonnet/high.
out=$(run resolve restore:unit --key bookkeeping --step s1 --attempt 1 --event step-failure) \
  || fail "15c: the seeding escalation failed"
[ "$(printf '%s\n' "$out" | field effort)" = high ] \
  || fail "15c: the fixture unit did not escalate, so there is no ladder position to preserve"
pre=$(run derive restore:unit --key bookkeeping) || fail "15c: derive before the step failed"
pre_tier="$(printf '%s\n' "$pre" | field model)/$(printf '%s\n' "$pre" | field effort)"
[ "$pre_tier" = sonnet/high ] || fail "15c: the pre-step tier should be sonnet/high, got $pre_tier"

out=$(run resolve restore:unit --key bookkeeping --step s2 --attempt 1 --step-type self-review) \
  || fail "15c: the scope-marked step launch failed"
[ "$(printf '%s\n' "$out" | field model)/$(printf '%s\n' "$out" | field effort)" = haiku/low ] \
  || fail "15c: the cheaper step tier did not take effect at the step's launch"
[ "$(printf '%s\n' "$out" | field step_scope)" = applied ] \
  || fail "15c: the step launch was not scope-marked"

post=$(run derive restore:unit --key bookkeeping) || fail "15c: derive after the step failed"
post_tier="$(printf '%s\n' "$post" | field model)/$(printf '%s\n' "$post" | field effort)"
[ "$post_tier" = "$pre_tier" ] \
  || fail "15c: RESTORE-AFTER: the unit's derived tier changed across a scope-marked step launch ($pre_tier -> $post_tier)"
[ "$(printf '%s\n' "$post" | field net)" = 1 ] \
  || fail "15c: a scope-marked step launch must not consume adjustment budget"
echo "ok: restore-after — a scope-marked step launch leaves the unit's ladder position untouched"

# --- 15d. an equal or more expensive step tier is IGNORED with a row -------

reset_state
step_knobs polish fable high
out=$(run resolve up:unit --key execution --step-type polish) \
  || fail "15d: resolve with a more expensive step tier failed"
[ "$(printf '%s\n' "$out" | field model)" = opus ] \
  || fail "15d: a more expensive step tier must be IGNORED, got $(printf '%s\n' "$out" | field model)"
[ "$(printf '%s\n' "$out" | field effort)" = high ] \
  || fail "15d: the unit's effort must be untouched by an ignored step tier"
[ "$(printf '%s\n' "$out" | field step_scope)" = ignored ] \
  || fail "15d: an ignored step tier must report an ignored step scope"
[ "$(step_rows up:unit | awk -F "$TAB" '{ print $14 }')" = ignored ] \
  || fail "15d: an ignored step tier must leave a step-scoped ledger row recording the ignore"
echo "ok: a more expensive step tier is ignored with a ledger row"

# An EQUAL tier is ignored on the same terms: one-directional means strictly
# cheaper, so a step tier that merely restates the unit's tier records an
# ignore rather than a spurious application.
reset_state
step_knobs polish opus high
out=$(run resolve eq:unit --key execution --step-type polish) \
  || fail "15d: resolve with an equal step tier failed"
[ "$(printf '%s\n' "$out" | field step_scope)" = ignored ] \
  || fail "15d: a step tier equal to the unit's tier must be ignored, not applied"
echo "ok: a step tier equal to the unit's tier is ignored"

# --- 15e. a step tier never ratchets the unit UP ---------------------------
#
# The ignore must be inert to derivation as well as to the launch: a unit that
# saw a more expensive step tier is still at the tier its own ladder says.

reset_state
escalation_ready
step_knobs polish fable high
run resolve noratchet:unit --key bookkeeping --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "15e: the seeding escalation failed"
run resolve noratchet:unit --key bookkeeping --step s2 --attempt 1 --step-type polish >/dev/null \
  || fail "15e: the ignored step launch failed"
out=$(run derive noratchet:unit --key bookkeeping) || fail "15e: derive failed"
[ "$(printf '%s\n' "$out" | field model)/$(printf '%s\n' "$out" | field effort)" = sonnet/high ] \
  || fail "15e: an ignored step tier ratcheted the unit's own tier"
[ "$(printf '%s\n' "$out" | field net)" = 1 ] \
  || fail "15e: an ignored step tier moved the unit's net displacement"
echo "ok: a step tier never ratchets a unit up"

# --- 15f. a partially configured step tier composes, then compares ---------
#
# A tier is a JOINT point, so an unconfigured column is filled from the unit's
# current tier before the comparison — which is what makes "just run reviews at
# low effort" express, and keeps the one-directional test on the joint result.

reset_state
step_knobs polish - low
out=$(run resolve part:unit --key execution --step-type polish) \
  || fail "15f: resolve with an effort-only step tier failed"
[ "$(printf '%s\n' "$out" | field model)/$(printf '%s\n' "$out" | field effort)" = opus/low ] \
  || fail "15f: an effort-only cheaper step tier must compose with the unit's model"
[ "$(printf '%s\n' "$out" | field step_scope)" = applied ] || fail "15f: it should have applied"
echo "ok: a partially configured step tier composes with the unit's tier"

# The same composition in the expensive direction is still ignored.
reset_state
step_knobs polish - high
out=$(run resolve partup:unit --key bookkeeping --step-type polish) \
  || fail "15f: resolve with an effort-only raise failed"
[ "$(printf '%s\n' "$out" | field model)/$(printf '%s\n' "$out" | field effort)" = sonnet/medium ] \
  || fail "15f: an effort-only RAISE must be ignored"
[ "$(printf '%s\n' "$out" | field step_scope)" = ignored ] || fail "15f: it should have been ignored"
echo "ok: a partially configured step tier is one-directional too"

# --- 15g. no step type at all is the unchanged path ------------------------

reset_state
step_knobs self_review haiku low
out=$(run resolve nostep:unit --key execution) || fail "15g: resolve without a step type failed"
[ "$(printf '%s\n' "$out" | field model)/$(printf '%s\n' "$out" | field effort)" = opus/high ] \
  || fail "15g: a launch that names no step type must not pick up a step tier"
[ "$(printf '%s\n' "$out" | field step_scope)" = none ] \
  || fail "15g: a launch with no step type must report step_scope none"
[ -z "$(step_rows nostep:unit)" ] \
  || fail "15g: a launch with no step type must leave no step-scoped ledger row"
echo "ok: a launch naming no step type is the unchanged path"

# --- 15h. a hostile step type is refused at the argument boundary ----------

reset_state
for bad in "" "../etc" "a b" "Self-Review" "step;rm" "_leading"; do
  rc=0
  run resolve hostile:unit --key execution --step-type "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] \
    || fail "15h: step type '$bad' exited $rc, want 2 (refused at the argument boundary)"
done
echo "ok: a hostile step type is refused before it reaches a knob name"

# --- 15i. the shipped config carries the step-type knobs -------------------

for k in allocation_model_step_implementation allocation_effort_step_implementation \
  allocation_model_step_polish allocation_effort_step_polish \
  allocation_model_step_self_review allocation_effort_step_self_review; do
  grep -q "^$k:" "$real_cfg" || fail "15i: config/defaults.yml is missing '$k'"
  grep -qE "^$k: inherit\$" "$real_cfg" \
    || fail "15i: '$k' must ship 'inherit' so defaults reproduce today's behavior (D-13)"
done
echo "ok: every step-type knob ships the inherit sentinel"
echo "PASS: allocation-adapt ($(basename "$0"))"
