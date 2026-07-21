#!/bin/bash
# Tests for scripts/fleet-allocate.sh — the budget-aware model/effort/
# concurrency ALLOCATION layer and the capability-only degrade guard
# (fleet-autonomy Task 10; D-24, D-25, D-26, D-28; REQ-E1.8, REQ-E1.9,
# REQ-E1.10, REQ-E1.4, REQ-F1.3, REQ-G1.2).
#
# fleet-allocate.sh sits between Task 7's base selection (fleet-resource-select)
# and Task 9's restriction ladder (fleet-usage-gate): given the current rung and
# the raw `/usage` signal it produces the EFFECTIVE allocation, applying the
# rung VALUES (which cheaper tier `downshift` selects, the per-rung concurrency),
# per-tier budget caps, the per-unit reservation exemption, and the kill-switch
# revert — all deterministic, no LLM call.
#
# What is covered (each maps to a Task 10 `Done when:` bullet):
#   - the ladder climbs one rung at a time and its VALUES apply (downshift caps
#     model/effort; reduce-concurrency reduces concurrency);
#   - per-tier caps withdraw expensive tiers from routine units sooner (opus's
#     threshold below sonnet's), by deterministic comparison, no accounting state;
#   - the signal-unavailable behavior: caps inactive;
#   - the reservation exemption: a pinned unit skips downshift/defer-heavy but
#     yields at defer-all; the shipped default reserves nothing;
#   - the capability-only guard: session-grade only, never `--permission-mode auto`;
#   - the kill-switch reverts allocation to the normal policy;
#   - overlay resolution (machine-local wins);
#   - determinism + zero outbound-client invocations (no LLM in the path).
#
# The audit-trail hysteresis/decay of the rung itself is Task 9's mechanism and
# is covered by tests/test-fleet-usage-gate.sh; here the rung is SEEDED directly
# via fleet-audit so allocation is exercised at each rung deterministically.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-allocate.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FAL="$here/../scripts/fleet-allocate.sh"
FA="$here/../scripts/fleet-audit.sh"
FUG="$here/../scripts/fleet-usage-gate.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FAL" ] || fail "scripts/fleet-allocate.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
mlocal_cfg="$repo/.claude/planwright.local.yml"

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
EOF

# Stub outbound clients: any invocation is an LLM/API call in the path, which
# REQ-G1.2 forbids. Each stub records its invocation.
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

run() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FAL" "$@"
}

# Seed the current rung directly into the audit trail (allocation derives the
# rung from it, D-28).
seed_rung() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" record usage-gate "$1" \
    "test-seed" "seed the rung for allocation" >/dev/null || fail "seeding rung $1 failed"
}

# Capture a `/usage` render so allocation's per-tier caps have a signal.
capture_signal() {
  # $1 session %, $2 weekly %
  printf 'Current session\n%s%% used\n\nCurrent week (all models)\n%s%% used\n' "$1" "$2" \
    | PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" /bin/bash "$FUG" capture >/dev/null \
    || fail "capturing the signal failed"
}

reset_state() {
  rm -rf "$fleet_home"
  rm -f "$mlocal_cfg" "$tmp/invocations"
}

# field <key>: extract a value from a resolve output on stdin.
field() {
  awk -F "$TAB" -v k="$1" '$1 == k { print $2; exit }'
}

# 1. Default-preserving normal policy: the base selection is unchanged, full
#    concurrency, admitted (REQ-E1.8/E1.10 — nothing configured reproduces today).
reset_state
out=$(run resolve execution) || fail "resolve execution (normal) exited nonzero"
[ "$(printf '%s\n' "$out" | field admit)" = yes ] || fail "normal: execution must be admitted"
[ "$(printf '%s\n' "$out" | field model)" = opus ] || fail "normal: execution keeps its base opus (got $(printf '%s\n' "$out" | field model))"
[ "$(printf '%s\n' "$out" | field effort)" = high ] || fail "normal: execution keeps high effort"
[ "$(printf '%s\n' "$out" | field command)" = execute-task ] || fail "normal: execution command"
[ "$(printf '%s\n' "$out" | field concurrency)" = 3 ] || fail "normal: full concurrency (3)"
[ "$(printf '%s\n' "$out" | field rung)" = normal ] || fail "normal: rung is normal"
[ "$(printf '%s\n' "$out" | field reserved)" = no ] || fail "normal: the shipped default reserves nothing"
echo "ok: at normal, the base selection is preserved and the unit is admitted"

# 2. The ladder climbs one rung at a time, applying its VALUES: downshift caps
#    model/effort; reduce-concurrency additionally reduces concurrency (REQ-E1.10).
reset_state
seed_rung downshift
out=$(run resolve execution) || fail "resolve execution (downshift) exited nonzero"
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "downshift: model must clamp to the downshift tier (sonnet)"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "downshift: effort must clamp to medium"
[ "$(printf '%s\n' "$out" | field concurrency)" = 3 ] || fail "downshift: concurrency unchanged (3) until reduce-concurrency"
[ "$(printf '%s\n' "$out" | field admit)" = yes ] || fail "downshift: still admitted"
reset_state
seed_rung reduce-concurrency
out=$(run resolve execution) || fail "resolve execution (reduce-concurrency) exited nonzero"
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "reduce-concurrency: model still clamped"
[ "$(printf '%s\n' "$out" | field concurrency)" = 1 ] || fail "reduce-concurrency: concurrency must reduce to 1"
echo "ok: downshift clamps model/effort; reduce-concurrency additionally reduces concurrency"

# 3. defer-heavy withholds heavy (opus) units but still admits cheaper units;
#    defer-all withholds everything (REQ-E1.10 admission).
reset_state
seed_rung defer-heavy
out=$(run resolve execution) || fail "resolve execution (defer-heavy) exited nonzero"
[ "$(printf '%s\n' "$out" | field admit)" = withheld ] || fail "defer-heavy: a routine heavy (execution/opus) unit must be withheld"
out=$(run resolve drain) || fail "resolve drain (defer-heavy) exited nonzero"
[ "$(printf '%s\n' "$out" | field admit)" = yes ] || fail "defer-heavy: a cheap (drain/sonnet) unit must still dispatch"
reset_state
seed_rung defer-all
[ "$(run resolve drain | field admit)" = withheld ] || fail "defer-all: even a cheap unit must be withheld"
echo "ok: defer-heavy withholds heavy units while admitting cheap ones; defer-all withholds all"

# 4. Per-tier budget caps withdraw expensive tiers from ROUTINE units sooner: at
#    a global signal >= opus's cap (70) but < sonnet's (90), opus is withdrawn
#    for a routine unit while sonnet units still serve — even at the normal rung,
#    by deterministic comparison (REQ-E1.9). No accounting state is written.
reset_state
capture_signal 10 75 # weekly 75 governs: >= opus cap 70, < sonnet cap 90
before=$(find "$fleet_home" -type f | sort)
[ "$(run resolve execution | field model)" = sonnet ] || fail "cap: a routine opus unit must be withdrawn to sonnet at 75% (opus cap 70)"
[ "$(run resolve execution | field rung)" = normal ] || fail "cap: the cap acts independently of the rung (rung stays normal)"
[ "$(run resolve drain | field model)" = sonnet ] || fail "cap: a routine sonnet unit still serves at 75% (sonnet cap 90)"
after=$(find "$fleet_home" -type f | sort)
[ "$before" = "$after" ] || fail "cap: resolution must write NO per-model accounting state (files changed)"
# A lower global figure leaves opus in place (deterministic threshold).
reset_state
capture_signal 10 65 # 65 < opus cap 70
[ "$(run resolve execution | field model)" = opus ] || fail "cap: below the opus cap (65 < 70), opus is kept"
echo "ok: per-tier caps withdraw expensive tiers from routine units sooner, deterministically, no state written"

# 5. Caps are INACTIVE when the signal is unavailable (REQ-E1.9): no capture ->
#    opus is kept at the normal rung (never a guessed withdrawal).
reset_state
[ "$(run resolve execution | field model)" = opus ] || fail "unavailable signal: caps inactive, opus kept"
echo "ok: caps are inactive when the usage signal is unavailable"

# 6. The reservation exemption (REQ-E1.10): a pinned unit is exempt from
#    downshift, defer-heavy, AND caps, but yields at defer-all.
reset_state
seed_rung downshift
[ "$(run resolve execution --reserved | field model)" = opus ] || fail "reserved: exempt from downshift (keeps opus)"
[ "$(run resolve execution --reserved | field effort)" = high ] || fail "reserved: exempt from the effort clamp (keeps high)"
reset_state
seed_rung defer-heavy
[ "$(run resolve execution --reserved | field admit)" = yes ] || fail "reserved: exempt from defer-heavy (admitted)"
[ "$(run resolve execution --reserved | field model)" = opus ] || fail "reserved at defer-heavy: keeps opus"
reset_state
capture_signal 10 75
[ "$(run resolve execution --reserved | field model)" = opus ] || fail "reserved: exempt from the per-tier cap (keeps opus at 75%)"
reset_state
seed_rung defer-all
[ "$(run resolve execution --reserved | field admit)" = withheld ] || fail "reserved: NOT exempt at defer-all (must yield)"
echo "ok: a reserved unit is exempt from downshift/defer-heavy/caps but yields at defer-all"

# 7. The capability-only guard (REQ-E1.10, REQ-E1.4): every effective model is a
#    session-grade alias; `--permission-mode auto` is never engaged; a
#    non-session-grade sentinel is refused.
reset_state
run guard opus >/dev/null 2>&1 || fail "guard: a session-grade opus must pass"
run guard sonnet plan >/dev/null 2>&1 || fail "guard: a session-grade model with a non-auto mode must pass"
rc=0
run guard opus auto >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "guard: '--permission-mode auto' must be refused (exit $rc, expected 3)"
rc=0
run guard script-worker >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "guard: a non-session-grade sentinel must be refused (exit $rc, expected 3)"
# Every degrade step's effective model passes the guard (never a lighter-weight
# worker, never auto): check each rung's resolved model against the guard.
for r in normal downshift reduce-concurrency defer-heavy; do
  reset_state
  seed_rung "$r"
  m=$(run resolve drain | field model)
  run guard "$m" >/dev/null 2>&1 || fail "guard: the degraded model '$m' at rung '$r' must stay session-grade"
done
echo "ok: the guard keeps every degrade step session-grade and never engages auto"

# 8. The kill-switch reverts allocation to the normal (un-degraded) policy
#    (REQ-E1.10, REQ-F1.3): even seeded at defer-heavy with a tight signal, an
#    engaged kill-switch yields the base selection, full concurrency, admitted.
reset_state
seed_rung defer-heavy
capture_signal 10 95
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
out=$(run resolve execution 2>/dev/null) || fail "resolve under the kill-switch exited nonzero"
[ "$(printf '%s\n' "$out" | field admit)" = yes ] || fail "kill-switch: must revert to admitted"
[ "$(printf '%s\n' "$out" | field model)" = opus ] || fail "kill-switch: must revert to the base opus"
[ "$(printf '%s\n' "$out" | field effort)" = high ] || fail "kill-switch: must revert to base high effort"
[ "$(printf '%s\n' "$out" | field concurrency)" = 3 ] || fail "kill-switch: must revert to full concurrency"
[ "$(printf '%s\n' "$out" | field rung)" = normal ] || fail "kill-switch: must report the normal policy"
rm -f "$mlocal_cfg"
echo "ok: the kill-switch reverts allocation to the normal (un-degraded) policy"

# 9. Overlay resolution: a machine-local downshift-model override wins
#    (REQ-G1.5). Set the downshift tier to haiku; a downshift execution unit
#    then clamps to haiku instead of the core-default sonnet.
reset_state
seed_rung downshift
printf 'fleet_downshift_model: haiku\n' >"$mlocal_cfg"
[ "$(run resolve execution 2>/dev/null | field model)" = haiku ] || fail "overlay: a machine-local fleet_downshift_model (haiku) must win"
rm -f "$mlocal_cfg"
echo "ok: a machine-local knob override wins via the overlay"

# 10. Determinism + no LLM/API call in the path (REQ-G1.2): repeated resolves
#     are byte-identical and no outbound client was ever invoked.
reset_state
seed_rung downshift
capture_signal 10 40
first=$(run resolve execution)
for i in 2 3; do
  again=$(run resolve execution) || fail "determinism: resolve run $i exited nonzero"
  [ "$again" = "$first" ] || fail "determinism: run $i differs from run 1"
done
[ ! -f "$tmp/invocations" ] || fail "an outbound client was invoked during allocation: $(sort -u "$tmp/invocations" | tr '\n' ' ')"
echo "ok: allocation is deterministic with zero outbound-client invocations"

# 11. Usage errors are refused (exit 2), and an unknown/hostile task type is
#     refused with a sanitized diagnostic — never a silent default.
reset_state
for args in "" "bogus" "resolve" "resolve a b" "resolve execution --nope" "guard" "guard a b c"; do
  rc=0
  # shellcheck disable=SC2086
  run $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
rc=0
err=$(run resolve "$(printf 'evil\033[2Jtype')" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "hostile task type: exit $rc, expected 2"
case $err in
  *$(printf '\033')*) fail "hostile task type: diagnostic carries a raw escape byte" ;;
esac
echo "ok: usage errors and unknown/hostile task types are refused (exit 2), diagnostics sanitized"

# 12. Positive control for the zero-invocation stub: the stub IS reachable, so
#     test 10's assertion is not vacuous.
rm -f "$tmp/invocations"
PATH="$stubbin:$PATH" claude >/dev/null 2>&1 || true
[ -f "$tmp/invocations" ] || fail "stub positive control failed (stub not reachable on PATH)"
echo "ok: the no-LLM stub is verified reachable"

# 13. Repo-drift check: the real config/defaults.yml ships every allocation knob
#     with the default the table above assumes.
real_defaults="$here/../config/defaults.yml"
for kv in \
  "fleet_downshift_model: sonnet" "fleet_downshift_effort: medium" \
  "fleet_concurrency_normal: 3" "fleet_concurrency_reduced: 1" \
  "fleet_cap_fable: 55" "fleet_cap_opus: 70" "fleet_cap_sonnet: 90" "fleet_cap_haiku: 100"; do
  grep -q "^$kv" "$real_defaults" || fail "config/defaults.yml does not ship '$kv' (defaults drifted)"
done
# opus's cap must be below sonnet's (expensive withdraws sooner) — the invariant
# REQ-E1.9 rests on, asserted against the shipped file.
opus_cap=$(sed -n 's/^fleet_cap_opus: *//p' "$real_defaults")
sonnet_cap=$(sed -n 's/^fleet_cap_sonnet: *//p' "$real_defaults")
[ "$opus_cap" -lt "$sonnet_cap" ] || fail "shipped caps violate REQ-E1.9: opus ($opus_cap) must be below sonnet ($sonnet_cap)"
echo "ok: shipped allocation defaults match the table and opus's cap is below sonnet's"

echo "ALL PASS: fleet-allocate"
