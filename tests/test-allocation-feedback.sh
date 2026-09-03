#!/bin/bash
# Tests for scripts/allocation-feedback.sh — the escalation-feedback observation:
# terminal-state evaluation of a unit's allocation ledger, and the once-per-unit
# observation fragment it records through the shared helper (model-allocation
# Task 4; D-11; REQ-F1.2, REQ-E1.1, REQ-E1.2).
#
# What is covered here:
#   - argument and grammar validation, including the hostile and underdetermined
#     input the refusals exist for, each pinned to its documented exit code;
#   - the two firing conditions (ended above the starting tier; the applied-
#     escalation count at the configured threshold), separately and together, at
#     the default threshold and at non-default overlay values including zero;
#   - both terminal states, completion and crash-loop disable;
#   - the non-firing cases: a unit below both conditions, one with no history,
#     one that escalated and then reverted, and a key that inherits its tier;
#   - the shipped posture: with adaptation off nothing reaches either condition;
#   - once-per-unit emission: the ledger mark and its whole payload, and
#     re-evaluation not re-recording;
#   - the guard failing CLOSED: an unreadable ledger refuses rather than risking
#     a duplicate, and an unhealthy one degrades without marking;
#   - a recording-helper failure surfacing non-zero with no mark left behind,
#     and the unit staying retryable afterwards;
#   - the fragment's field shape (spec, task, both tiers) validated by the
#     repo's own check-obs guard, and the absence of ledger free text in it,
#     pinned with a canary planted in the ledger's `inputs` column;
#   - the mark's inertness to the rest of the ledger's readers: `last-tier` (a
#     mark is not a launch) and the derivation (a mark moves no tier);
#   - the knob's config/options-reference lockstep.
#
# The ledger is seeded by driving scripts/allocation-adapt.sh, not by hand-
# writing rows: a fixture the engine produced is the one that proves the two
# scripts agree about what a ledger means.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-feedback.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FB="$here/../scripts/allocation-feedback.sh"
AD="$here/../scripts/allocation-adapt.sh"
LEDGER="$here/../scripts/allocation-ledger.sh"
FUG="$here/../scripts/fleet-usage-gate.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FB" ] || fail "scripts/allocation-feedback.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
mlocal_cfg="$repo/.claude/planwright.local.yml"
obsdir="$tmp/obs"

# The core defaults these scripts read. Every row is the shipped value from
# config/defaults.yml EXCEPT `allocation_adjustment_cap`, deliberately widened
# to 4 so the multi-escalation churn fixtures below are not bounded by the cap
# (the cap's own behavior is tests/test-allocation-clamps.sh's subject, not
# this file's). The knob this suite owns is pinned against the shipped file by
# the config-lockstep section.
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
allocation_adjustment_cap: 4
allocation_feedback_threshold: 2
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
# feedback path, which the determinism floor forbids (REQ-A1.1).
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

run() { env_run "$FB" "$@"; }
run_ad() { env_run "$AD" "$@"; }
run_led() { env_run "$LEDGER" "$@"; }

reset_state() {
  rm -rf "$fleet_home" "$obsdir"
  rm -f "$mlocal_cfg" "$tmp/invocations"
  mkdir -p "$obsdir"
}

field() {
  awk -F "$TAB" -v k="$1" '$1 == k { print $2; exit }'
}

fragments() {
  find "$obsdir/entries" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort
}

frag_count() {
  fragments | awk 'END { print NR + 0 }'
}

# capture_signal <session-pct> <weekly-pct>: seed the usage signal the clamps and
# the escalation-denial rule read.
capture_signal() {
  printf 'Current session\n%s%% used\n\nCurrent week (all models)\n%s%% used\n' "$1" "$2" \
    | env_run "$FUG" capture >/dev/null || fail "capturing the signal failed"
}

# adaptation_on: arm the master knob through the machine-local layer, plus a
# usage signal low enough that escalation is not denied for an unavailable one
# (REQ-D1.2) and no per-tier cap binds, so the ledger these fixtures build is
# the ladder's own history rather than the clamps'.
adaptation_on() {
  printf 'allocation_adaptation: on\n' >"$mlocal_cfg"
  capture_signal 10 10
}

# escalate <unit> <key> <step> <event>: drive one launch boundary through the
# engine so the ledger carries a real applied escalation row.
escalate() {
  run_ad resolve "$1" --key "$2" --step "$3" --attempt 1 --event "$4" >/dev/null \
    || fail "seeding an escalation for $1 failed"
}

evaluate() {
  run evaluate "$1" --key "$2" --terminal "$3" --scope planwright --obs-dir "$obsdir"
}

# rc_of <args...>: run and print the exit code, so a refusal test pins WHICH
# refusal it got. Every section below asserts the documented code, not merely
# non-zero: a usage error that exits 1 is indistinguishable to a caller from a
# recording failure, which is the one code it must branch on.
rc_of() {
  local rc=0
  run "$@" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

marks_of() {
  run_led rows "$1" \
    | awk -F "$TAB" 'NF == 15 && $6 == "feedback" { n++ } END { print n + 0 }'
}

# --- 1. usage and argument validation --------------------------------------

reset_state
[ "$(rc_of evaluate)" = 2 ] || fail "1a: a bare evaluate should exit 2"
[ "$(rc_of evaluate s:task-1 --key execution --scope planwright)" = 2 ] \
  || fail "1b: a missing --terminal should exit 2"
[ "$(rc_of evaluate s:task-1 --key execution --terminal wedged --scope planwright)" = 2 ] \
  || fail "1c: an out-of-enum terminal state should exit 2"
[ "$(rc_of evaluate s:task-1 --key nosuchkey --terminal completed --scope planwright)" = 2 ] \
  || fail "1d: an unknown selection key should exit 2"
[ "$(rc_of evaluate s:task-1 --key execution --terminal completed --scope 'bad scope')" = 2 ] \
  || fail "1e: an out-of-grammar scope should exit 2"
# A unit whose key does not encode <spec>:task-<id> cannot name the fields the
# fragment owes, so it is refused rather than recorded with invented ones.
[ "$(rc_of evaluate plainunit --key execution --terminal completed --scope planwright)" = 2 ] \
  || fail "1f: a unit with no derivable spec/task and no overrides should exit 2"
[ "$(frag_count)" = 0 ] || fail "1g: a refused evaluation wrote a fragment"
echo "ok: argument validation refuses hostile, out-of-enum, and underdetermined input"

# --- 2. the identity grammars, each discriminated on its own -----------------

reset_state
# The unit charset. `--spec`/`--task` are supplied so the derivation refusal
# cannot stand in for the charset refusal and mask its removal.
[ "$(rc_of evaluate 'a@b c' --key drain --terminal completed --scope planwright --spec s --task 1)" = 2 ] \
  || fail "2a: a unit carrying whitespace should be refused on the charset"
[ "$(rc_of evaluate -x:task-1 --key drain --terminal completed --scope planwright)" = 2 ] \
  || fail "2b: a hyphen-leading unit should be refused"
# The subject grammar: a dot-run is not an identity token, however legal its
# bytes are, because it is what turns into a traversal the day it shapes a path.
[ "$(rc_of evaluate s:task-1 --key drain --terminal completed --scope planwright --spec .. --task 1)" = 2 ] \
  || fail "2c: a dot-run spec should be refused"
[ "$(rc_of evaluate s:task-1 --key drain --terminal completed --scope planwright --spec -s --task 1)" = 2 ] \
  || fail "2d: a hyphen-leading spec should be refused"
# Two `:task-` runs anchor identically, so the derived task still carries a `:`
# and is refused, rather than silently naming a subject matching no real unit.
[ "$(rc_of evaluate 'alpha:task-1:task-2' --key drain --terminal completed --scope planwright)" = 2 ] \
  || fail "2e: a doubly-keyed unit should be refused, not silently re-anchored"
# --obs-dir: an explicitly empty value is not the same as an omitted flag, and
# a control byte would tear this script's own TAB-separated output.
[ "$(rc_of evaluate s:task-1 --key drain --terminal completed --scope planwright --obs-dir '')" = 2 ] \
  || fail "2f: an empty --obs-dir should be refused, not silently defaulted"
[ "$(rc_of evaluate s:task-1 --key drain --terminal completed --scope planwright --obs-dir "$(printf 'a\tb')")" = 2 ] \
  || fail "2g: an --obs-dir carrying a control byte should be refused"
[ "$(frag_count)" = 0 ] || fail "2h: a refused evaluation wrote a fragment"
echo "ok: the unit, subject, and obs-dir grammars each refuse on their own terms"

# --- 3. a unit ending ABOVE its starting tier fires (REQ-F1.2) --------------

reset_state
adaptation_on
# drain starts at (sonnet, low); one escalation lands it at (sonnet, medium).
escalate model-allocation:task-9 drain s1 step-failure
out=$(evaluate model-allocation:task-9 drain completed) || fail "3: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "3a: a unit above its starting tier did not fire"
[ "$(printf '%s\n' "$out" | field reason)" = above-start ] \
  || fail "3b: the reason should be above-start, got $(printf '%s\n' "$out" | field reason)"
[ "$(printf '%s\n' "$out" | field start)" = sonnet/low ] || fail "3c: the starting tier is wrong"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/medium ] || fail "3d: the final tier is wrong"
[ "$(printf '%s\n' "$out" | field escalations)" = 1 ] || fail "3e: the escalation count is wrong"
[ "$(frag_count)" = 1 ] || fail "3f: want exactly one fragment, got $(frag_count)"
# The emitted fragment field is the path that was actually written.
[ "$(printf '%s\n' "$out" | field fragment)" = "$(fragments)" ] \
  || fail "3g: the emitted fragment path does not match the file on disk"
echo "ok: a unit ending above its starting tier records exactly one fragment"

# --- 4. the fragment's shape, validated by the repo's own guard --------------

frag=$(fragments)
body=$(cat "$frag")
env_run "$here/../scripts/check-obs.sh" --obs-dir "$obsdir" >/dev/null 2>&1 \
  || fail "4a: the recorded fragment does not satisfy scripts/check-obs.sh"
case $frag in
  */entries/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-allocation-escalation-????????.md) : ;;
  *) fail "4b: the fragment filename does not carry the pinned slug: $frag" ;;
esac
case $body in
  "- "*"[planwright] "*) : ;;
  *) fail "4c: the fragment is not the one-line entry form" ;;
esac
[ "$(printf '%s\n' "$body" | awk 'END { print NR }')" = 1 ] || fail "4d: the fragment is not a single line"
for want in model-allocation "task 9" completed sonnet/low sonnet/medium; do
  case $body in
    *"$want"*) : ;;
    *) fail "4e: the fragment does not name '$want': $body" ;;
  esac
done
# The tier it names is the LADDER position, and the prose has to say so: a
# clamped unit's ladder position is not a tier any launch of it ran at.
case $body in
  *"ladder tier"*) : ;;
  *) fail "4f: the fragment does not qualify its tier as a ladder position: $body" ;;
esac
echo "ok: the fragment passes check-obs and names the spec, task, and both tiers"

# --- 5. no ledger free text reaches the fragment (REQ-F1.2) -----------------

# The `inputs` column is the one place a caller can put arbitrary key=value
# text, and it is where a worker petition's reason will land once Task 3 ships.
# A canary is planted there so this asserts the property rather than the absence
# of the engine's own vocabulary, which no code path reads anyway.
reset_state
adaptation_on
escalate model-allocation:task-c drain s1 step-failure
run_led append model-allocation:task-c s2 1 launch sonnet medium - - sonnet medium \
  unit resolved 'trigger=CANARYLEAK;reason=CANARYLEAK' >/dev/null \
  || fail "5: planting the canary row failed"
out=$(evaluate model-allocation:task-c drain completed) || fail "5: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "5a: the canary fixture did not fire"
case $(cat "$(fragments)") in
  *CANARYLEAK*) fail "5b: ledger inputs text reached the committed fragment" ;;
esac
echo "ok: text planted in the ledger's inputs column never reaches the fragment"

# --- 6. the emission is ledger-marked, payload and all ----------------------

reset_state
adaptation_on
escalate model-allocation:task-9 drain s1 step-failure
out=$(evaluate model-allocation:task-9 drain completed) || fail "6: evaluate failed"
mark=$(run_led rows model-allocation:task-9 | awk -F "$TAB" 'NF == 15 && $6 == "feedback"')
[ "$(printf '%s\n' "$mark" | awk 'END { print NR }')" = 1 ] || fail "6a: want exactly one feedback mark row"
[ "$(printf '%s' "$mark" | cut -f5)" = 0 ] || fail "6b: the mark should carry the no-attempt sentinel"
[ "$(printf '%s' "$mark" | cut -f7)/$(printf '%s' "$mark" | cut -f8)" = sonnet/low ] \
  || fail "6c: the mark's proposed columns should carry the starting tier"
[ "$(printf '%s' "$mark" | cut -f11)/$(printf '%s' "$mark" | cut -f12)" = sonnet/medium ] \
  || fail "6d: the mark's resolved columns should carry the final ladder position"
[ "$(printf '%s' "$mark" | cut -f13)" = unit ] || fail "6e: the mark's scope should be unit"
[ "$(printf '%s' "$mark" | cut -f14)" = recorded ] || fail "6f: the mark's outcome should be recorded"
inputs=$(printf '%s' "$mark" | cut -f15)
for want in "terminal=completed" "reason=above-start" "escalations=1" "threshold=2"; do
  case $inputs in
    *"$want"*) : ;;
    *) fail "6g: the mark's inputs omit '$want': $inputs" ;;
  esac
done
# The citation handle: the mark carries the fragment's own 8-hex UID, so the
# ledger row resolves to the fragment from any checkout.
uid=$(basename "$(fragments)" .md)
uid=${uid##*-}
case $inputs in
  *"obs=$uid"*) : ;;
  *) fail "6h: the mark does not cite the fragment's UID ($uid): $inputs" ;;
esac
echo "ok: the mark records the tiers, scope, outcome, and the fragment's citation UID"

# --- 7. re-evaluation does not re-record ------------------------------------

out=$(evaluate model-allocation:task-9 drain completed) || fail "7: re-evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "7a: re-evaluation fired again"
[ "$(printf '%s\n' "$out" | field reason)" = already-recorded ] \
  || fail "7b: the reason should be already-recorded"
# A short-circuit did not derive the ladder, and says so rather than echoing the
# starting tier and a zero, which a consumer would read as "never moved".
[ "$(printf '%s\n' "$out" | field final)" = - ] || fail "7c: a short-circuit should report final as unknown"
[ "$(printf '%s\n' "$out" | field escalations)" = - ] || fail "7d: a short-circuit should report escalations as unknown"
[ "$(frag_count)" = 1 ] || fail "7e: re-evaluation recorded a second fragment"
# The mark is per UNIT, not per terminal state.
out=$(evaluate model-allocation:task-9 drain disabled) || fail "7: re-evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "7f: a different terminal state re-recorded"
[ "$(frag_count)" = 1 ] || fail "7g: a different terminal state recorded a second fragment"
echo "ok: emission is once per unit, ledger-marked, and idempotent across re-derivation"

# --- 8. the mark is inert to the ledger's other readers ---------------------

# The derivation must walk past the mark: if `feedback` ever became a trigger
# event, or the outcome became `applied`, a relaunched unit's tier and count
# would shift under it.
derived=$(run_led derive model-allocation:task-9 sonnet low) || fail "8: derive failed"
[ "$(printf '%s' "$derived" | cut -f1)/$(printf '%s' "$derived" | cut -f2)" = sonnet/medium ] \
  || fail "8a: the mark moved the derived tier"
[ "$(printf '%s' "$derived" | cut -f6)" = 1 ] || fail "8b: the mark changed the escalation count"
# And the ledger must still be healthy with a mark in it.
run_led health model-allocation:task-9 || fail "8c: a marked ledger reads as unhealthy"
echo "ok: the mark moves no tier, changes no count, and keeps the ledger healthy"

# --- 9. the crash-loop disabled terminal state fires too (D-11) -------------

reset_state
adaptation_on
escalate model-allocation:task-8 drain s1 step-failure
out=$(evaluate model-allocation:task-8 drain disabled) || fail "9: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "9a: a disabled unit did not fire"
[ "$(frag_count)" = 1 ] || fail "9b: want exactly one fragment, got $(frag_count)"
case $(cat "$(fragments)") in
  *disabled*) : ;;
  *) fail "9c: the fragment does not name the disabled terminal state" ;;
esac
echo "ok: a crash-loop disabled unit records the same way a completed one does"

# --- 10. a unit below both conditions records nothing -----------------------

reset_state
adaptation_on
# A plain launch: no events, so no escalation and no movement.
run_ad resolve model-allocation:task-7 --key drain >/dev/null || fail "10: seeding failed"
out=$(evaluate model-allocation:task-7 drain completed) || fail "10: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "10a: a unit at its starting tier fired"
[ "$(printf '%s\n' "$out" | field reason)" = below-thresholds ] \
  || fail "10b: the reason should be below-thresholds"
[ "$(frag_count)" = 0 ] || fail "10c: a non-firing unit wrote a fragment"
# A unit with no ledger at all is the same answer: zero history, no evidence.
out=$(evaluate model-allocation:task-6 drain completed) || fail "10: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "10d: a zero-history unit fired"
[ "$(printf '%s\n' "$out" | field reason)" = below-thresholds ] \
  || fail "10e: a zero-history unit should read below-thresholds, not degraded"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/low ] || fail "10f: a zero-history unit derives its starting tier"
[ "$(frag_count)" = 0 ] || fail "10g: a zero-history unit wrote a fragment"
echo "ok: a unit below both conditions, and one with no history, record nothing"

# --- 11. escalated-then-reverted: back at the start, below threshold --------

reset_state
adaptation_on
escalate model-allocation:task-5 drain s1 step-failure
# A de-escalate petition reverses the most recent unreversed escalation, so the
# unit ends exactly where it started; one applied escalation is below the
# default threshold of 2, so neither condition holds.
escalate model-allocation:task-5 drain s2 petition-de-escalate
out=$(evaluate model-allocation:task-5 drain completed) || fail "11: evaluate failed"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/low ] || fail "11a: the unit did not revert to its starting tier"
[ "$(printf '%s\n' "$out" | field escalations)" = 1 ] || fail "11b: the escalation count should still be 1"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "11c: an escalated-then-reverted unit fired"
[ "$(frag_count)" = 0 ] || fail "11d: an escalated-then-reverted unit wrote a fragment"
echo "ok: a unit that escalated and reverted is below both conditions"

# --- 12. the escalation-count condition at the default threshold ------------

reset_state
adaptation_on
# Two escalations, then two reversals: the unit ends at its starting tier, so
# only the COUNT condition can fire. It reaches the default threshold of 2.
escalate model-allocation:task-4 drain s1 step-failure
escalate model-allocation:task-4 drain s2 flailing
escalate model-allocation:task-4 drain s3 petition-de-escalate
escalate model-allocation:task-4 drain s4 petition-de-escalate
out=$(evaluate model-allocation:task-4 drain completed) || fail "12: evaluate failed"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/low ] || fail "12a: the unit should be back at its starting tier"
[ "$(printf '%s\n' "$out" | field escalations)" = 2 ] \
  || fail "12b: want 2 escalations, got $(printf '%s\n' "$out" | field escalations)"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "12c: the count condition did not fire at the default threshold"
[ "$(printf '%s\n' "$out" | field reason)" = threshold ] \
  || fail "12d: the reason should be threshold alone, got $(printf '%s\n' "$out" | field reason)"
[ "$(printf '%s\n' "$out" | field threshold)" = 2 ] || fail "12e: the default threshold is not 2"
[ "$(frag_count)" = 1 ] || fail "12f: want exactly one fragment, got $(frag_count)"
echo "ok: the escalation-count condition fires at the shipped default threshold"

# --- 13. both conditions at once report the combined reason -----------------

reset_state
adaptation_on
# Two escalations with no reversal: the unit is above its start AND at the
# default threshold, which is the only fixture that exercises the combined
# reason label.
escalate model-allocation:task-b drain s1 step-failure
escalate model-allocation:task-b drain s2 flailing
out=$(evaluate model-allocation:task-b drain completed) || fail "13: evaluate failed"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/high ] || fail "13a: two steps should reach sonnet/high"
[ "$(printf '%s\n' "$out" | field escalations)" = 2 ] || fail "13b: want 2 escalations"
[ "$(printf '%s\n' "$out" | field reason)" = above-start+threshold ] \
  || fail "13c: the combined reason is wrong, got $(printf '%s\n' "$out" | field reason)"
case $(cat "$(fragments)") in
  *"above-start+threshold"*) : ;;
  *) fail "13d: the fragment does not carry the combined reason" ;;
esac
echo "ok: a unit meeting both conditions reports and records the combined reason"

# --- 14. the threshold is operator-configurable (REQ-E1.1) ------------------

reset_state
adaptation_on
printf 'allocation_feedback_threshold: 1\n' >>"$mlocal_cfg"
# One escalation, reverted: below the DEFAULT threshold (section 11 proved it
# does not fire), at a configured threshold of 1 it does.
escalate model-allocation:task-3 drain s1 step-failure
escalate model-allocation:task-3 drain s2 petition-de-escalate
out=$(evaluate model-allocation:task-3 drain completed) || fail "14: evaluate failed"
[ "$(printf '%s\n' "$out" | field threshold)" = 1 ] || fail "14a: the overlay threshold did not resolve"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/low ] || fail "14b: the fixture should be back at its starting tier"
[ "$(printf '%s\n' "$out" | field reason)" = threshold ] || fail "14c: the reason should be threshold"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "14d: the non-default threshold did not fire"
[ "$(frag_count)" = 1 ] || fail "14e: want exactly one fragment, got $(frag_count)"

# And raising it above the count suppresses a firing the default would allow.
reset_state
adaptation_on
printf 'allocation_feedback_threshold: 9\n' >>"$mlocal_cfg"
escalate model-allocation:task-2 drain s1 step-failure
escalate model-allocation:task-2 drain s2 flailing
escalate model-allocation:task-2 drain s3 petition-de-escalate
escalate model-allocation:task-2 drain s4 petition-de-escalate
out=$(evaluate model-allocation:task-2 drain completed) || fail "14: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "14f: a raised threshold still fired"
[ "$(frag_count)" = 0 ] || fail "14g: a raised threshold wrote a fragment"

# The knob's grammar is NON-NEGATIVE (design D-5), so `0` is legal and means
# "the count condition is always true": every terminal unit records.
reset_state
adaptation_on
printf 'allocation_feedback_threshold: 0\n' >>"$mlocal_cfg"
run_ad resolve model-allocation:task-z --key drain >/dev/null || fail "14: seeding failed"
out=$(evaluate model-allocation:task-z drain completed) || fail "14: evaluate failed"
[ "$(printf '%s\n' "$out" | field threshold)" = 0 ] || fail "14h: a threshold of 0 was not accepted"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "14i: a threshold of 0 should record every terminal unit"
[ "$(frag_count)" = 1 ] || fail "14j: want exactly one fragment at threshold 0"
echo "ok: the feedback threshold resolves through the overlay, zero included"

# --- 15. the adopter overlay layer resolves it too --------------------------

reset_state
adaptation_on
mkdir -p "$adopter_root"
printf 'allocation_feedback_threshold: 1\n' >"$adopter_root/planwright.yml"
escalate model-allocation:task-a drain s1 step-failure
escalate model-allocation:task-a drain s2 petition-de-escalate
out=$(evaluate model-allocation:task-a drain completed) || fail "15: evaluate failed"
rm -f "$adopter_root/planwright.yml"
[ "$(printf '%s\n' "$out" | field threshold)" = 1 ] || fail "15a: the adopter-layer threshold did not resolve"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "15b: the adopter-layer threshold did not fire"
echo "ok: the threshold resolves at the adopter layer, not only machine-local"

# --- 16. the shipped posture records nothing (D-13) -------------------------

reset_state
# No adaptation_on: the master knob ships off, so the trigger event is inert and
# the unit stays at its configured tier with nothing to feed back.
capture_signal 10 10
run_ad resolve model-allocation:task-off --key drain --step s1 --attempt 1 --event step-failure >/dev/null \
  || fail "16: seeding failed"
out=$(evaluate model-allocation:task-off drain completed) || fail "16: evaluate failed"
[ "$(printf '%s\n' "$out" | field escalations)" = 0 ] || fail "16a: adaptation off should leave zero escalations"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "16b: the shipped posture recorded a fragment"
[ "$(frag_count)" = 0 ] || fail "16c: the shipped posture wrote a fragment"
echo "ok: with adaptation off nothing reaches either condition"

# --- 17. a recording-helper failure surfaces non-zero, leaving no mark ------

reset_state
adaptation_on
escalate model-allocation:task-1 drain s1 step-failure
# A regular file where the observations directory belongs: obs-record.sh cannot
# create the store and refuses cleanly, which is the helper failure REQ-F1.2
# says must be surfaced rather than swallowed.
badobs="$tmp/not-a-dir"
: >"$badobs"
set +e
out=$(run evaluate model-allocation:task-1 --key drain --terminal completed \
  --scope planwright --obs-dir "$badobs" 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 1 ] || fail "17a: a helper failure should exit 1, got $rc"
# The script's OWN diagnostic, not merely the helper's passed-through stderr:
# this is the line that tells the operator no mark was written.
grep -q 'allocation-feedback: the observation recording helper refused' "$tmp/err" \
  || fail "17b: the script's own recording-failure diagnostic is missing"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "17c: a failed recording reported fired=yes"
[ "$(printf '%s\n' "$out" | field reason)" = record-failed ] || fail "17d: the reason should be record-failed"
[ "$(printf '%s\n' "$out" | field fragment)" = - ] || fail "17e: a failed recording named a fragment"
# No mark: the next evaluation must be free to retry, so the mark is written
# only after the helper reports success.
[ "$(marks_of model-allocation:task-1)" = 0 ] || fail "17f: a failed recording left a mark row behind"
# Retry against a working store: the unit still records.
out=$(evaluate model-allocation:task-1 drain completed) || fail "17: retry failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "17g: the retry after a helper failure did not record"
[ "$(frag_count)" = 1 ] || fail "17h: the retry did not write exactly one fragment"
echo "ok: a recording-helper failure surfaces non-zero and leaves the unit retryable"

# --- 18. the knob ships in the tracked config and the options reference -----

cfg="$here/../config/defaults.yml"
grep -q '^allocation_feedback_threshold: 2$' "$cfg" \
  || fail "18a: config/defaults.yml does not ship allocation_feedback_threshold: 2"
# shellcheck disable=SC2016 # the backticks are the reference's markdown, not a substitution
grep -q '^| `allocation_feedback_threshold` | `2` |' "$here/../docs/options-reference.md" \
  || fail "18b: docs/options-reference.md has no allocation_feedback_threshold row"
echo "ok: the feedback threshold ships in the tracked config with an options-reference row"

# --- 19. an inherit key has no tier ladder to evaluate ----------------------

reset_state
adaptation_on
out=$(evaluate model-allocation:task-0 execute_step completed) || fail "19: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "19a: an inherit key fired"
[ "$(printf '%s\n' "$out" | field reason)" = inherit ] || fail "19b: the reason should be inherit"
[ "$(frag_count)" = 0 ] || fail "19c: an inherit key wrote a fragment"
echo "ok: a key that inherits its tier has no escalation history to feed back"

# --- 20. an unhealthy ledger degrades; an unreadable one refuses ------------

reset_state
adaptation_on
escalate model-allocation:task-x drain s1 step-failure
led=$(run_led path model-allocation:task-x)
printf 'torn\trow\n' >>"$led"
out=$(evaluate model-allocation:task-x drain completed 2>"$tmp/err") || fail "20: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "20a: an unhealthy ledger still recorded"
[ "$(printf '%s\n' "$out" | field reason)" = degraded ] || fail "20b: the reason should be degraded"
grep -q -i degraded "$tmp/err" || fail "20c: the degradation was not surfaced"
[ "$(frag_count)" = 0 ] || fail "20d: an unhealthy ledger wrote a fragment"
# A degraded evaluation must leave no mark, or the unit is silenced forever by a
# transient corruption; repairing the ledger makes it record.
[ "$(marks_of model-allocation:task-x)" = 0 ] || fail "20e: a degraded evaluation left a mark row"
grep -v '^torn' "$led" >"$led.fixed" && mv "$led.fixed" "$led"
out=$(evaluate model-allocation:task-x drain completed) || fail "20: post-repair evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "20f: a repaired ledger did not record"

# An UNREADABLE ledger reaches the same place by a different route: the store's
# health verb reports it as unhealthy, so it degrades rather than recording from
# records nobody could read. What matters either way is that no fragment and no
# mark land, so the unit is still recordable once the file is readable again.
reset_state
adaptation_on
escalate model-allocation:task-w drain s1 step-failure
led=$(run_led path model-allocation:task-w)
chmod 000 "$led"
set +e
out=$(run evaluate model-allocation:task-w --key drain --terminal completed \
  --scope planwright --obs-dir "$obsdir" 2>/dev/null)
rc=$?
set -e
chmod 644 "$led"
[ "$rc" = 0 ] || fail "20g: an unreadable ledger should degrade, not fail; got exit $rc"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "20h: an unreadable ledger recorded"
[ "$(printf '%s\n' "$out" | field reason)" = degraded ] || fail "20i: the reason should be degraded"
[ "$(frag_count)" = 0 ] || fail "20j: an unreadable ledger wrote a fragment"
[ "$(marks_of model-allocation:task-w)" = 0 ] || fail "20k: an unreadable ledger left a mark row"
echo "ok: an unhealthy or unreadable ledger degrades without recording or marking"

# --- 21. a broken install is exit 5, never a recording failure --------------

reset_state
adaptation_on
brokendir="$tmp/broken"
mkdir -p "$brokendir"
cp "$here/../scripts/"*.sh "$brokendir/"
rm -f "$brokendir/obs-record.sh"
set +e
PATH="$stubbin:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$brokendir/allocation-feedback.sh" evaluate model-allocation:task-i \
  --key drain --terminal completed --scope planwright --obs-dir "$obsdir" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = 5 ] || fail "21: a missing recording helper should exit 5 (broken install), got $rc"
echo "ok: a missing helper is a broken install, not a retryable recording failure"

# --- 22. the mark is not a launch: `last-tier` must not answer from it ------

# A degraded relaunch launches at the ledger's last recorded tier, and that has
# to be a tier the unit ACTUALLY RAN AT. The feedback mark carries the derived
# final tier, which is a ladder position and never post-clamp, so if `last-tier`
# answered from it a unit whose last launch was clamped down would relaunch
# above where it ran. The fixture is built to make the two differ: at 75% usage
# the fable and opus caps both bind, so the unit's ladder climbs to fable/high
# while the launch it climbed on resolves at sonnet/high.
reset_state
adaptation_on
capture_signal 75 75
escalate model-allocation:task-y execution s1 step-failure
before=$(run_led last-tier model-allocation:task-y)
[ "$before" = "sonnet${TAB}high" ] \
  || fail "22a: the fixture's last launch should be cap-clamped to sonnet/high, got '$before'"
out=$(evaluate model-allocation:task-y execution completed) || fail "22: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "22b: the fixture did not record a mark"
[ "$(printf '%s\n' "$out" | field final)" = fable/high ] \
  || fail "22c: the fixture's ladder position should be fable/high, got $(printf '%s\n' "$out" | field final)"
after=$(run_led last-tier model-allocation:task-y)
[ "$after" = "$before" ] || fail "22d: the feedback mark changed last-tier from '$before' to '$after'"
echo "ok: the terminal-state mark is inert to last-tier, which answers for launches only"

# --- 23. the feedback/recorded pairing is enforced by the store -------------

# The two enum values only mean anything as a pair: a `feedback`/`applied` row
# would be silently inert to replay while reading as a real ladder step, and a
# `launch`/`recorded` row would read as a mark to the once-per-unit guard.
reset_state
if run_led append pair:unit - 0 feedback sonnet low - - sonnet low unit resolved 'k=v' >/dev/null 2>&1; then
  fail "23a: a feedback row with a non-recorded outcome was accepted"
fi
if run_led append pair:unit - 1 launch sonnet low - - sonnet low unit recorded 'k=v' >/dev/null 2>&1; then
  fail "23b: a recorded outcome on a non-feedback event was accepted"
fi
run_led append pair:unit - 0 feedback sonnet low - - sonnet low unit recorded 'k=v' >/dev/null \
  || fail "23c: the well-formed pairing was refused"
run_led health pair:unit || fail "23d: a well-formed mark reads as unhealthy"
echo "ok: the feedback event and the recorded outcome may appear only together"

# --- 24. no outbound client is ever invoked --------------------------------

# The stub directory is proven reachable first, so this cannot pass by being
# unable to fail.
PATH="$stubbin:$PATH" claude >/dev/null 2>&1 || fail "24a: the outbound-client stubs are not on PATH"
[ -s "$tmp/invocations" ] || fail "24b: the positive control did not record an invocation"
rm -f "$tmp/invocations"
reset_state
adaptation_on
escalate model-allocation:task-n drain s1 step-failure
evaluate model-allocation:task-n drain completed >/dev/null || fail "24: evaluate failed"
[ ! -s "$tmp/invocations" ] || fail "24c: an outbound client was invoked: $(cat "$tmp/invocations")"
echo "ok: the feedback path makes no outbound call"

echo "all allocation-feedback tests passed"
