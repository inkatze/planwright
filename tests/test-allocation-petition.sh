#!/bin/bash
# Tests for scripts/allocation-petition.sh and the petition consumption
# scripts/allocation-adapt.sh performs at a launch boundary (model-allocation
# Task 3; D-7, D-8; REQ-C1.3, REQ-C1.6, REQ-C1.7, REQ-E1.1, REQ-E1.2).
#
# The petition is the one signal in this spec that a WORKER authors, which makes
# its parser the only untrusted-input surface in the allocation path. So the
# fixtures here are weighted toward hostility: everything below the "hostile
# fixtures" banner is a file a compromised or confused worker could leave at the
# pinned path, and every one of them must be consumed, ignored, recorded, and
# echoed sanitized — never acted on, never interpolated, never followed.
#
# What is covered:
#   - the pinned path and the write contract (D-7): temp-then-rename, and a
#     `write` that refuses out-of-grammar input rather than emitting a petition
#     the reader will only throw away;
#   - screening (REQ-C1.6): oversize, out-of-grammar, control bytes, a shell
#     metacharacter reason, a symlink at the pinned path, a non-regular file, a
#     symlinked container directory, a stale unit/step/attempt binding, and a
#     torn (mid-write) read;
#   - the claim (D-7): two concurrent consumers, exactly one of which weighs it;
#   - the single-consumption lifecycle (REQ-C1.7): the artifact is gone after
#     weighing, a re-armed petition is a FRESH signal rather than a replay, and a
#     crash between the claim and the ledger row reconciles as ignored-with-audit
#     at the next boundary;
#   - policy consumption (REQ-C1.3): a valid petition moves the tier one step in
#     its direction, de-escalation reverses the most recent escalation, and a
#     petition is a hint under the clamps and the adjustment cap, never above
#     them;
#   - the `allocation_petition` knob (REQ-E1.1, REQ-E1.2): all four enum states
#     through the overlay layers, subordination to the master knob, and the
#     shipped default plus its options-reference row.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-petition.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
PET="$here/../scripts/allocation-petition.sh"
AD="$here/../scripts/allocation-adapt.sh"
LEDGER="$here/../scripts/allocation-ledger.sh"
FA="$here/../scripts/fleet-audit.sh"
FUG="$here/../scripts/fleet-usage-gate.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$PET" ] || fail "scripts/allocation-petition.sh missing or not executable"
[ -x "$AD" ] || fail "scripts/allocation-adapt.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"
repo="$tmp/repo"
core_cfg="$tmp/core.yml"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped core defaults this engine reads, kept in lockstep with
# config/defaults.yml (the last test asserts the real file carries the knob this
# suite introduces, with the default it claims).
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
allocation_petition: on
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
pet() { env_run "$PET" "$@"; }

field() {
  awk -F "$TAB" -v k="$1" '$1 == k { print $2; exit }'
}

rows_with() {
  run_led rows "$1" | awk -F "$TAB" -v o="$2" 'NF == 15 && $14 == o { n++ } END { print n + 0 }'
}

seed_rung() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" record usage-gate "$1" \
    "test-seed" "seed the rung for allocation" >/dev/null || fail "seeding rung $1 failed"
}

capture_signal() {
  printf 'Current session\n%s%% used\n\nCurrent week (all models)\n%s%% used\n' "$1" "$2" \
    | env_run "$FUG" capture >/dev/null || fail "capturing the signal failed"
}

# A fresh worktree per fixture: the pinned path is worktree-scoped, so reusing
# one across fixtures would let a leftover artifact leak between them.
wt=""
new_wt() {
  wt="$tmp/wt-$1"
  rm -rf "$wt"
  mkdir -p "$wt/.claude"
}

reset_state() {
  rm -rf "$fleet_home"
  rm -f "$mlocal_cfg" "$tmp/invocations"
}

# adaptation_on [cap]: arm the master knob (and optionally the cap) through the
# machine-local overlay layer — which doubles as the overlay-resolution
# assertion for those knobs (REQ-E1.1).
adaptation_on() {
  printf 'allocation_adaptation: on\n' >"$mlocal_cfg"
  if [ "$#" -gt 0 ]; then
    printf 'allocation_adjustment_cap: %s\n' "$1" >>"$mlocal_cfg"
  fi
}

# escalation_ready [cap]: adaptation on AND a healthy, low usage signal.
# Escalation above the starting tier is denied while the signal is unavailable
# (REQ-D1.2), so any fixture meaning to exercise the ladder must supply one.
escalation_ready() {
  adaptation_on "$@"
  capture_signal 10 10
}

petition_policy() {
  printf 'allocation_petition: %s\n' "$1" >>"$mlocal_cfg"
}

# assert_sanitized <label> <text>: no C0 control or DEL may reach the terminal
# (doctrine/security-posture.md echo discipline; the assertion style follows
# tests/test-echo-safety.sh). Newline and tab are the two structural bytes this
# output legitimately carries.
#
# Scoped to C0 + DEL rather than the sanitizer's full C0 + DEL + C1 range,
# because at the byte level C1 is indistinguishable from a UTF-8 continuation
# byte and the script's own diagnostics are hand-written prose that may contain
# multibyte punctuation. Nothing is lost: an artifact carrying ANY byte outside
# newline plus printable ASCII is refused whole by the byte screen before a
# character of it is echoed, so a C1 byte from the untrusted side can never
# reach this output in the first place.
assert_sanitized() {
  as_bad=$(printf '%s' "$2" | tr -d '\011\012\040-\377' | wc -c | tr -d ' ')
  [ "$as_bad" = 0 ] || fail "$1: $as_bad control byte(s) reached the terminal unsanitized"
}

# --- 1. the pinned path is worktree-scoped and stable ---------------------

new_wt path
p=$(pet path "$wt") || fail "1: path failed"
[ "$p" = "$wt/.claude/allocation-petition" ] \
  || fail "1: the pinned path is '$p', not the worktree's .claude/allocation-petition"
echo "ok: the petition path is pinned under the worker's own worktree"

# --- 2. write then claim: the round trip, and the artifact is gone --------

new_wt roundtrip
pet write --worktree "$wt" --direction escalate --unit u:1 --step impl --attempt 2 \
  --reason 'the remaining steps are far from mechanical' \
  || fail "2: write failed"
[ -f "$wt/.claude/allocation-petition" ] || fail "2a: write left no artifact at the pinned path"
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 2) \
  || fail "2b: claim of a valid petition failed"
[ "$(printf '%s\n' "$out" | field verdict)" = valid ] || fail "2c: a well-formed petition was not valid"
[ "$(printf '%s\n' "$out" | field direction)" = escalate ] || fail "2d: the direction did not round-trip"
[ "$(printf '%s\n' "$out" | field reason)" = 'the remaining steps are far from mechanical' ] \
  || fail "2e: the reason did not round-trip"
[ -e "$wt/.claude/allocation-petition" ] && fail "2f: the artifact survived the claim"
# And nothing is left behind for the next boundary to re-audit.
leftover=$(find "$wt/.claude" -name 'allocation-petition*' | wc -l | tr -d ' ')
[ "$leftover" = 0 ] || fail "2g: the claim left $leftover file(s) behind"
# A second claim has nothing to take.
pet claim --worktree "$wt" --unit u:1 --step impl --attempt 2 >/dev/null 2>&1 \
  && fail "2h: a second claim found something to consume"
echo "ok: a valid petition round-trips once and leaves nothing behind"

# --- 3. write refuses out-of-grammar input at the source ------------------

new_wt writeguard
pet write --worktree "$wt" --direction sideways --unit u:1 --reason ok >/dev/null 2>&1 \
  && fail "3a: write accepted a direction outside the enum"
pet write --worktree "$wt" --direction escalate --unit u:1 \
  --reason "$(printf 'two\nlines')" >/dev/null 2>&1 \
  && fail "3b: write accepted a multi-line reason"
big=$(awk 'BEGIN { while (i++ < 1200) printf "x" }')
pet write --worktree "$wt" --direction escalate --unit u:1 --reason "$big" >/dev/null 2>&1 \
  && fail "3c: write accepted a reason past the size cap"
pet write --worktree "$wt" --direction escalate --unit 'bad unit' --reason ok >/dev/null 2>&1 \
  && fail "3d: write accepted a unit outside the identity grammar"
[ -e "$wt/.claude/allocation-petition" ] && fail "3e: a refused write still left an artifact"
echo "ok: write refuses out-of-grammar input rather than emitting a doomed petition"

# --- hostile fixtures (REQ-C1.6) -----------------------------------------
#
# Each: consumed (nothing left at the pinned path), verdict invalid, output
# sanitized. `hostile <label> <setup-fn>` runs one.

hostile_check() {
  hc_label=$1
  hc_detail=$2
  hc_out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1 2>&1) \
    || fail "$hc_label: claim exited nonzero on a hostile artifact instead of consuming it"
  [ "$(printf '%s\n' "$hc_out" | field verdict)" = invalid ] \
    || fail "$hc_label: a hostile artifact was not judged invalid"
  [ "$(printf '%s\n' "$hc_out" | field detail)" = "$hc_detail" ] \
    || fail "$hc_label: detail is '$(printf '%s\n' "$hc_out" | field detail)', want '$hc_detail'"
  assert_sanitized "$hc_label" "$hc_out"
  [ -e "$wt/.claude/allocation-petition" ] \
    && fail "$hc_label: the hostile artifact survived the claim"
  hc_left=$(find "$wt/.claude" -name 'allocation-petition*' | wc -l | tr -d ' ')
  [ "$hc_left" = 0 ] || fail "$hc_label: $hc_left claimed file(s) left behind"
  return 0
}

valid_body() {
  printf 'direction=%s\nunit=%s\nstep=%s\nattempt=%s\nreason=%s\n' \
    "$1" "$2" "$3" "$4" "$5"
}

# 4a. oversize
new_wt oversize
{
  valid_body escalate u:1 impl 1 'padded'
  awk 'BEGIN { while (i++ < 1100) printf "x" }'
  printf '\n'
} >"$wt/.claude/allocation-petition"
hostile_check 4a oversize

# 4b. out of grammar: an unknown key
new_wt grammar
printf 'direction=escalate\nunit=u:1\nstep=impl\nattempt=1\nrationale=nope\n' \
  >"$wt/.claude/allocation-petition"
hostile_check 4b grammar

# 4c. out of grammar: a sixth line
new_wt extraline
{
  valid_body escalate u:1 impl 1 'fine'
  printf 'direction=escalate\n'
} >"$wt/.claude/allocation-petition"
hostile_check 4c grammar

# 4d. control bytes in the reason
new_wt controlbytes
printf 'direction=escalate\nunit=u:1\nstep=impl\nattempt=1\nreason=drive \033[31mthe terminal\n' \
  >"$wt/.claude/allocation-petition"
hostile_check 4d control-bytes

# 4e. a NUL byte
new_wt nulbyte
printf 'direction=escalate\nunit=u:1\nstep=impl\nattempt=1\nreason=nul\000here\n' \
  >"$wt/.claude/allocation-petition"
hostile_check 4e control-bytes

# 4f. a torn write: the last line never got its newline
new_wt torn
printf 'direction=escalate\nunit=u:1\nstep=impl\nattempt=1\nreason=half a rea' \
  >"$wt/.claude/allocation-petition"
hostile_check 4f torn

# 4g. an empty file
new_wt emptyfile
: >"$wt/.claude/allocation-petition"
hostile_check 4g empty

# 4h. a symlink at the pinned path — renamed, never followed
new_wt symlink
secret="$tmp/secret-target"
printf 'direction=escalate\nunit=u:1\nstep=impl\nattempt=1\nreason=stolen\n' >"$secret"
ln -s "$secret" "$wt/.claude/allocation-petition"
hostile_check 4h symlink
[ -f "$secret" ] || fail "4h: consuming the symlink deleted its target"
[ "$(head -n 1 "$secret")" = "direction=escalate" ] || fail "4h: the symlink target was modified"

# 4i. a non-regular file (FIFO) — never opened for reading
new_wt fifo
mkfifo "$wt/.claude/allocation-petition"
hostile_check 4i not-regular

# 4j. a symlinked container directory: no channel, and nothing is followed
new_wt container
elsewhere="$tmp/elsewhere"
mkdir -p "$elsewhere"
printf 'direction=escalate\nunit=u:1\nstep=impl\nattempt=1\nreason=outside\n' \
  >"$elsewhere/allocation-petition"
rm -rf "$wt/.claude"
ln -s "$elsewhere" "$wt/.claude"
rc=0
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1 2>&1) || rc=$?
[ "$rc" = 1 ] || fail "4j: a symlinked container yielded rc=$rc, want 1 (no channel)"
assert_sanitized 4j "$out"
[ -f "$elsewhere/allocation-petition" ] \
  || fail "4j: the reader followed the symlinked container and consumed the outside file"
echo "ok: every hostile artifact is consumed, ignored, and echoed sanitized"

# --- 5. stale bindings: the unit/step/attempt identity is asserted --------

new_wt staleunit
valid_body escalate other:9 impl 1 'not mine' >"$wt/.claude/allocation-petition"
hostile_check 5a stale-unit

new_wt stalestep
valid_body escalate u:1 review 1 'wrong step' >"$wt/.claude/allocation-petition"
hostile_check 5b stale-step

new_wt staleattempt
valid_body escalate u:1 impl 7 'wrong attempt' >"$wt/.claude/allocation-petition"
hostile_check 5c stale-attempt

# The positive half of the same binding.
new_wt matched
valid_body de-escalate u:1 impl 1 'the rest is mechanical' >"$wt/.claude/allocation-petition"
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1) || fail "5d: claim failed"
[ "$(printf '%s\n' "$out" | field verdict)" = valid ] || fail "5d: a matching petition was not weighed"
[ "$(printf '%s\n' "$out" | field direction)" = de-escalate ] || fail "5e: direction did not round-trip"
echo "ok: the unit/step/attempt binding is asserted in both directions"

# --- 6. a shell-metacharacter reason is data, never code ------------------

new_wt injection
# shellcheck disable=SC2016 # the un-expanded forms ARE the payload under test
payload='$(touch '"$tmp"'/pwned) `id` ; rm -rf / && :'
valid_body escalate u:1 impl 1 "$payload" >"$wt/.claude/allocation-petition"
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1) || fail "6: claim failed"
[ "$(printf '%s\n' "$out" | field verdict)" = valid ] || fail "6a: printable ASCII is in grammar"
[ -e "$tmp/pwned" ] && fail "6b: the reason was interpolated by a shell"
[ "$(printf '%s\n' "$out" | field reason)" = "$payload" ] \
  || fail "6c: the reason did not echo back literally"
echo "ok: a metacharacter-laden reason is carried as data, never interpolated"

# --- 7. the claim race: two consumers, at most one weighs it -------------

new_wt race
valid_body escalate u:1 impl 1 'contested' >"$wt/.claude/allocation-petition"
pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1 >"$tmp/race-a" 2>"$tmp/race-a.err" &
ra=$!
pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1 >"$tmp/race-b" 2>"$tmp/race-b.err" &
rb=$!
rca=0
rcb=0
wait "$ra" || rca=$?
wait "$rb" || rcb=$?
wins=0
for f in "$tmp/race-a" "$tmp/race-b"; do
  [ "$(field verdict <"$f")" = valid ] && wins=$((wins + 1))
done
if [ "$wins" != 1 ]; then
  # Print what the consumers said before failing. This assertion used to discard
  # both stderrs, and the sweep destroying a live sibling's claim looked exactly
  # like an unexplained flake for as long as it did.
  echo "race-a stderr: $(cat "$tmp/race-a.err" 2>/dev/null)"
  echo "race-b stderr: $(cat "$tmp/race-b.err" 2>/dev/null)"
  echo "race-a: $(tr '\n' ' ' <"$tmp/race-a" 2>/dev/null)"
  echo "race-b: $(tr '\n' ' ' <"$tmp/race-b" 2>/dev/null)"
  fail "7: $wins of two racing consumers weighed the same petition, want exactly 1"
fi
[ "$((rca + rcb))" = 1 ] || fail "7a: the losing consumer did not report 'nothing to claim'"
echo "ok: two racing consumers move the tier at most once"

# --- 7a2. the sweep must not reap a LIVE consumer's claim ----------------
#
# The sweep exists for consumers that died holding a claim. A live sibling's
# claim file matches the same glob, and reaping one destroys the petition that
# sibling is about to weigh, leaving it to screen a file that is no longer there
# and report the artifact malformed. Deterministic here, where case 7 only
# catches it when the interleaving happens to be wide enough.

new_wt livesweep
valid_body escalate u:1 impl 1 'contested' >"$wt/.claude/allocation-petition"
# A real live pid to own the planted claim, and one that outlives the call.
sleep 30 &
live_pid=$!
printf 'x\n' >"$wt/.claude/allocation-petition.claim.$live_pid.0"
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1) \
  || fail "7a2: claim alongside a live sibling's file failed"
[ "$(printf '%s\n' "$out" | field reconciled)" = 0 ] \
  || fail "7a2: a live consumer's claim was swept as an orphan"
[ -e "$wt/.claude/allocation-petition.claim.$live_pid.0" ] \
  || fail "7a2: the live consumer's claim file was deleted"
kill "$live_pid" 2>/dev/null || true
# `wait` reports the signal as exit 143, which `set -e` would take as fatal.
wait "$live_pid" 2>/dev/null || true
echo "ok: a live consumer's claim is left alone by the sweep"

# The same file, once its owner is gone, IS an orphan and must be reaped. The
# petition itself was consumed above, so this call has nothing to claim and
# exits non-zero by contract; the reconcile it reports is the assertion.
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1) || true
[ "$(printf '%s\n' "$out" | field reconciled)" = 1 ] \
  || fail "7a3: a dead consumer's claim was not reconciled"
[ ! -e "$wt/.claude/allocation-petition.claim.$live_pid.0" ] \
  || fail "7a3: the dead consumer's claim file survived the sweep"
echo "ok: a dead consumer's claim is reconciled as an orphan"

# --- 7b. `--hold` is the two-phase claim the engine needs ----------------
#
# The engine must not lose the audit if it dies between taking the petition and
# recording it, so it claims with `--hold`: the artifact leaves the pinned path
# (nobody can weigh it again) but the claimed file survives until the ledger row
# lands, where the next boundary's reconcile would find it.

new_wt hold
valid_body escalate u:1 impl 1 'held' >"$wt/.claude/allocation-petition"
out=$(pet claim --worktree "$wt" --unit u:1 --step impl --attempt 1 --hold) \
  || fail "7b: the held claim failed"
[ "$(printf '%s\n' "$out" | field verdict)" = valid ] || fail "7b: the held petition was not valid"
held=$(printf '%s\n' "$out" | field claimed)
[ -f "$held" ] || fail "7b: --hold did not leave the claimed file for the caller to discard"
[ -e "$wt/.claude/allocation-petition" ] && fail "7c: --hold left the artifact weighable at the pinned path"
echo "ok: --hold keeps the claimed file until its ledger row lands"

# --- 8. the engine weighs a valid escalate petition (REQ-C1.3) -----------

reset_state
new_wt engine-esc
escalation_ready
pet write --worktree "$wt" --direction escalate --unit p:esc --step s1 --attempt 1 \
  --reason 'this is harder than the table assumed' || fail "8: write failed"
out=$(run resolve p:esc --key drain --step s1 --attempt 1 --worktree "$wt") \
  || fail "8: resolve failed"
# drain starts at (sonnet, low); one step is (sonnet, medium).
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "8a: the model should stay sonnet"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "8b: the petition should raise effort one step"
[ "$(printf '%s\n' "$out" | field petition)" = escalate ] || fail "8c: the petition was not reported"
[ "$(rows_with p:esc applied)" = 1 ] || fail "8d: want exactly one applied row"
[ -e "$wt/.claude/allocation-petition" ] && fail "8e: the artifact survived being weighed"
echo "ok: a valid escalate petition moves the next launch one step and is consumed"

# --- 9. de-escalation reverses the most recent escalation ----------------

reset_state
new_wt engine-de
escalation_ready
run resolve p:de --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "9: the seeding escalation failed"
pet write --worktree "$wt" --direction de-escalate --unit p:de --step s2 --attempt 1 \
  --reason 'the remaining steps are mechanical' || fail "9: write failed"
out=$(run resolve p:de --key drain --step s2 --attempt 1 --worktree "$wt") \
  || fail "9: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] \
  || fail "9a: the petition should reverse the escalation back to low effort"
[ "$(printf '%s\n' "$out" | field net)" = 0 ] || fail "9b: the reversal should refund the displacement"
[ "$(printf '%s\n' "$out" | field petition)" = de-escalate ] || fail "9c: the direction was not reported"
echo "ok: a de-escalate petition reverses the unit's most recent escalation"

# --- 10. single consumption: a re-armed petition is a FRESH signal -------
#
# REQ-C1.7's distinguishing property. The engine's cross-boundary idempotency
# key would otherwise read the second petition at the same (step, attempt) as a
# replay of the first and skip it; consuming the artifact IS the petition's own
# idempotency mechanism, so re-arming must cost another step.

reset_state
new_wt rearm
escalation_ready
for n in 1 2; do
  pet write --worktree "$wt" --direction escalate --unit p:re --step s1 --attempt 1 \
    --reason "petition $n" || fail "10: write $n failed"
  run resolve p:re --key drain --step s1 --attempt 1 --worktree "$wt" >/dev/null \
    || fail "10: resolve $n failed"
done
out=$(run resolve p:re --key drain --step s1 --attempt 1) || fail "10: the read-back resolve failed"
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "10a: two steps from (sonnet, low) stay on sonnet"
[ "$(printf '%s\n' "$out" | field effort)" = high ] || fail "10b: two fresh petitions should climb two steps"
[ "$(rows_with p:re applied)" = 2 ] || fail "10c: want one applied row per fresh petition"
echo "ok: a re-armed petition is a fresh signal, not a replay of the consumed one"

# --- 11. a petition is a hint under the adjustment cap -------------------

reset_state
new_wt capbound
escalation_ready 0
pet write --worktree "$wt" --direction escalate --unit p:cap --step s1 --attempt 1 \
  --reason 'please' || fail "11: write failed"
out=$(run resolve p:cap --key drain --step s1 --attempt 1 --worktree "$wt") \
  || fail "11: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "11a: the petition crossed a zero adjustment cap"
[ "$(rows_with p:cap denied)" = 1 ] || fail "11b: the capped petition should be recorded as denied"
[ "$(rows_with p:cap applied)" = 0 ] || fail "11c: nothing should have been applied"
echo "ok: a petition never spends past the adjustment cap"

# --- 12. a petition is a hint under the clamps --------------------------

reset_state
new_wt clampbound
escalation_ready
seed_rung downshift
pet write --worktree "$wt" --direction escalate --unit p:clamp --step s1 --attempt 1 \
  --reason 'please' || fail "12: write failed"
out=$(run resolve p:clamp --key execution --step s1 --attempt 1 --worktree "$wt") \
  || fail "12: resolve failed"
# execution starts at (opus, high); one step up the ladder is (fable, high). The
# downshift values then clamp the RESOLVED tier to (sonnet, medium).
[ "$(printf '%s\n' "$out" | field proposed_model)" = fable ] \
  || fail "12a: the petition should still propose the successor tier"
[ "$(printf '%s\n' "$out" | field model)" = sonnet ] || fail "12b: the downshift clamp did not bind"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] || fail "12c: the effort clamp did not bind"
echo "ok: a petition proposes; the clamps still decide what launches"

# --- 13. the petition-policy knob's four states (REQ-E1.1) --------------

# 13a. off: a valid petition is consumed and ignored with a ledger row.
reset_state
new_wt knoboff
escalation_ready
petition_policy off
pet write --worktree "$wt" --direction escalate --unit p:off --step s1 --attempt 1 \
  --reason 'ignored' || fail "13a: write failed"
out=$(run resolve p:off --key drain --step s1 --attempt 1 --worktree "$wt") \
  || fail "13a: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "13a: an off knob still moved the tier"
[ "$(printf '%s\n' "$out" | field petition)" = ignored ] || fail "13a: the ignore was not reported"
[ "$(rows_with p:off ignored)" = 1 ] || fail "13a: the ignored petition left no ledger row"
[ -e "$wt/.claude/allocation-petition" ] && fail "13a: an ignored petition was not consumed"

# 13b. escalate-only: the de-escalate direction is filtered.
reset_state
new_wt knobesc
escalation_ready
petition_policy escalate-only
run resolve p:eo --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "13b: the seeding escalation failed"
pet write --worktree "$wt" --direction de-escalate --unit p:eo --step s2 --attempt 1 \
  --reason 'mechanical' || fail "13b: write failed"
out=$(run resolve p:eo --key drain --step s2 --attempt 1 --worktree "$wt") \
  || fail "13b: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = medium ] \
  || fail "13b: escalate-only let a de-escalate petition through"
[ "$(rows_with p:eo ignored)" = 1 ] || fail "13b: the filtered petition left no ledger row"

# ...and lets the escalate direction through.
pet write --worktree "$wt" --direction escalate --unit p:eo --step s3 --attempt 1 \
  --reason 'harder' || fail "13b: the second write failed"
out=$(run resolve p:eo --key drain --step s3 --attempt 1 --worktree "$wt") \
  || fail "13b: the second resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = high ] \
  || fail "13b: escalate-only blocked the direction it names"

# 13c. de-escalate-only: the mirror of 13b.
reset_state
new_wt knobde
escalation_ready
petition_policy de-escalate-only
pet write --worktree "$wt" --direction escalate --unit p:do --step s1 --attempt 1 \
  --reason 'harder' || fail "13c: write failed"
out=$(run resolve p:do --key drain --step s1 --attempt 1 --worktree "$wt") \
  || fail "13c: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] \
  || fail "13c: de-escalate-only let an escalate petition through"
[ "$(rows_with p:do ignored)" = 1 ] || fail "13c: the filtered petition left no ledger row"
echo "ok: the petition-policy knob's off and direction-filtered states ignore with a row"

# --- 14. the knob is subordinate to the master knob ---------------------

reset_state
new_wt subordinate
pet write --worktree "$wt" --direction escalate --unit p:sub --step s1 --attempt 1 \
  --reason 'harder' || fail "14: write failed"
out=$(run resolve p:sub --key drain --step s1 --attempt 1 --worktree "$wt") \
  || fail "14: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "14a: adaptation off still moved the tier"
[ "$(printf '%s\n' "$out" | field petition)" = none ] \
  || fail "14b: the channel was read with the master knob off"
[ -f "$wt/.claude/allocation-petition" ] \
  || fail "14c: adaptation off consumed a petition it can never weigh"
echo "ok: with the master knob off the petition channel is not read at all"

# --- 15. no worktree: a documented degradation, never an error ----------

reset_state
escalation_ready
out=$(run resolve p:nowt --key drain --step s1 --attempt 1) || fail "15: resolve failed"
[ "$(printf '%s\n' "$out" | field petition)" = none ] || fail "15a: a petition was reported with no channel"
[ "$(rows_with p:nowt ignored)" = 0 ] || fail "15b: the absent channel produced an ignore row"
echo "ok: a rung with no worktree simply has no petition channel"

# --- 16. a crash between the claim and the ledger row reconciles --------
#
# The claim renames the artifact aside before validating, so a consumer that
# dies mid-weigh leaves a claimed file nobody recorded. The next boundary must
# find it, record it as ignored-with-audit, and clear it — never weigh it, and
# never leave it to be re-audited forever.

reset_state
new_wt crashed
escalation_ready
valid_body escalate p:crash s1 1 'interrupted' >"$wt/.claude/allocation-petition.claim.stale"
out=$(run resolve p:crash --key drain --step s1 --attempt 1 --worktree "$wt") \
  || fail "16: resolve failed"
[ "$(printf '%s\n' "$out" | field effort)" = low ] || fail "16a: an unreconciled claim moved the tier"
[ "$(rows_with p:crash ignored)" = 1 ] || fail "16b: the orphaned claim left no audit row"
left=$(find "$wt/.claude" -name 'allocation-petition*' | wc -l | tr -d ' ')
[ "$left" = 0 ] || fail "16c: the orphaned claim was not cleared"
# And a second boundary does not re-audit what is already gone.
run resolve p:crash --key drain --step s1 --attempt 1 --worktree "$wt" >/dev/null \
  || fail "16: the second resolve failed"
[ "$(rows_with p:crash ignored)" = 1 ] || fail "16d: the reconciled claim was audited twice"
echo "ok: a crash between the claim and the ledger row reconciles as ignored-with-audit"

# --- 17. the shipped config and its options-reference row (REQ-E1.2) ----

real_cfg="$here/../config/defaults.yml"
grep -qE '^allocation_petition: "?on"?$' "$real_cfg" \
  || fail "17a: config/defaults.yml must ship allocation_petition: on"
# shellcheck disable=SC2016 # backticks are markdown here, not a substitution
grep -q '`allocation_petition`' "$here/../docs/options-reference.md" \
  || fail "17b: allocation_petition has no options-reference row (REQ-E1.2)"
/bin/bash "$here/../scripts/check-options-reference.sh" >/dev/null \
  || fail "17c: check-options-reference failed"
echo "ok: the knob ships documented and the options-reference guard passes"

echo "PASS: allocation-petition ($(basename "$0"))"
