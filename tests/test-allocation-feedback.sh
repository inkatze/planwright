#!/bin/bash
# Tests for scripts/allocation-feedback.sh — the escalation-feedback observation:
# terminal-state evaluation of a unit's allocation ledger, and the once-per-unit
# observation fragment it records through the shared helper (model-allocation
# Task 4; D-11; REQ-F1.2, REQ-E1.1, REQ-E1.2).
#
# What is covered here:
#   - the two firing conditions (ended above the starting tier; the escalation
#     count at the configured threshold), at the default threshold and at a
#     non-default overlay value;
#   - both terminal states, completion and crash-loop disable;
#   - the non-firing cases: a unit below both conditions, and one that escalated
#     and then reverted to its starting tier;
#   - once-per-unit emission: the ledger mark, and re-evaluation not re-recording;
#   - a recording-helper failure surfacing non-zero with no mark left behind;
#   - the fragment's field shape (task, spec, starting and final tiers) and the
#     absence of any ledger free text in it;
#   - the mark's inertness to the rest of the ledger's readers, `last-tier` in
#     particular (a mark is not a launch);
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

# The shipped core defaults these scripts read, kept in lockstep with
# config/defaults.yml (test 11 asserts the real file carries the same rows).
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

# adaptation_on: arm the master knob through the machine-local layer, plus a low
# usage signal so escalation is not denied for an unavailable one (REQ-D1.2).
# 10% is below every per-tier cap, so no clamp binds and the ledger these
# fixtures build is the ladder's own history. The adjustment cap stays at the
# fixture config's 4, which is wide enough that no fixture below trips it.
capture_signal() {
  printf 'Current session\n%s%% used\n\nCurrent week (all models)\n%s%% used\n' "$1" "$2" \
    | env_run "$FUG" capture >/dev/null || fail "capturing the signal failed"
}

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

# --- 1. usage and argument validation --------------------------------------

reset_state
if run evaluate >/dev/null 2>&1; then
  fail "1a: a bare evaluate should be a usage error"
fi
if run evaluate s:task-1 --key execution --scope planwright >/dev/null 2>&1; then
  fail "1b: a missing --terminal should be refused"
fi
if run evaluate s:task-1 --key execution --terminal wedged --scope planwright >/dev/null 2>&1; then
  fail "1c: an out-of-enum terminal state should be refused"
fi
if run evaluate 'u;rm -rf /' --key execution --terminal completed --scope planwright >/dev/null 2>&1; then
  fail "1d: a hostile unit key should be refused"
fi
if run evaluate s:task-1 --key nosuchkey --terminal completed --scope planwright >/dev/null 2>&1; then
  fail "1e: an unknown selection key should be refused"
fi
if run evaluate s:task-1 --key execution --terminal completed --scope 'bad scope' >/dev/null 2>&1; then
  fail "1f: an out-of-grammar scope should be refused"
fi
# A unit whose key does not encode <spec>:task-<id> cannot name the fields the
# fragment owes, so it is refused rather than recorded with invented ones.
if run evaluate plainunit --key execution --terminal completed --scope planwright >/dev/null 2>&1; then
  fail "1g: a unit with no derivable spec/task and no overrides should be refused"
fi
[ "$(frag_count)" = 0 ] || fail "1h: a refused evaluation wrote a fragment"
echo "ok: argument validation refuses hostile, out-of-enum, and underdetermined input"

# --- 2. a unit ending ABOVE its starting tier fires (REQ-F1.2) --------------

reset_state
adaptation_on
# drain starts at (sonnet, low); one escalation lands it at (sonnet, medium).
escalate model-allocation:task-9 drain s1 step-failure
out=$(evaluate model-allocation:task-9 drain completed) || fail "2: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "2a: a unit above its starting tier did not fire"
[ "$(printf '%s\n' "$out" | field reason)" = above-start ] \
  || fail "2b: the reason should be above-start, got $(printf '%s\n' "$out" | field reason)"
[ "$(printf '%s\n' "$out" | field start)" = sonnet/low ] || fail "2c: the starting tier is wrong"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/medium ] || fail "2d: the final tier is wrong"
[ "$(frag_count)" = 1 ] || fail "2e: want exactly one fragment, got $(frag_count)"
echo "ok: a unit ending above its starting tier records exactly one fragment"

# --- 3. the fragment's shape: named fields, no ledger free text -------------

frag=$(fragments)
body=$(cat "$frag")
case $frag in
  */entries/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-allocation-escalation-????????.md) : ;;
  *) fail "3a: the fragment filename does not follow the pinned grammar: $frag" ;;
esac
case $body in
  "- "*"[planwright] "*) : ;;
  *) fail "3b: the fragment is not the one-line entry form" ;;
esac
[ "$(printf '%s\n' "$body" | awk 'END { print NR }')" = 1 ] || fail "3c: the fragment is not a single line"
for want in model-allocation "task 9" completed sonnet/low sonnet/medium; do
  case $body in
    *"$want"*) : ;;
    *) fail "3d: the fragment does not name '$want': $body" ;;
  esac
done
# The ledger's `inputs` free text is never carried into the fragment: it is the
# only column a caller can put arbitrary key=value prose in (REQ-F1.2's
# no-worker-authored-prose rule, artifact data hygiene).
case $body in
  *trigger=* | *key=* | *rung=* | *clamps=*) fail "3e: the fragment carries ledger inputs text: $body" ;;
esac
echo "ok: the fragment names the spec, task, and both tiers, and carries no ledger free text"

# --- 4. the emission is ledger-marked and re-evaluation does not re-record --

marks=$(run_led rows model-allocation:task-9 \
  | awk -F "$TAB" 'NF == 15 && $6 == "feedback" && $14 == "recorded" { n++ } END { print n + 0 }')
[ "$marks" = 1 ] || fail "4a: want exactly one feedback mark row, got $marks"
out=$(evaluate model-allocation:task-9 drain completed) || fail "4: re-evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "4b: re-evaluation fired again"
[ "$(printf '%s\n' "$out" | field reason)" = already-recorded ] \
  || fail "4c: the reason should be already-recorded"
[ "$(frag_count)" = 1 ] || fail "4d: re-evaluation recorded a second fragment"
# A terminal state reported differently second time round must not re-record
# either: the mark is per UNIT, not per terminal state (REQ-F1.2).
out=$(evaluate model-allocation:task-9 drain disabled) || fail "4: re-evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "4e: a different terminal state re-recorded"
[ "$(frag_count)" = 1 ] || fail "4f: a different terminal state recorded a second fragment"
echo "ok: emission is once per unit, ledger-marked, and idempotent across re-derivation"

# --- 5. the crash-loop disabled terminal state fires too (D-11) -------------

reset_state
adaptation_on
escalate model-allocation:task-8 drain s1 step-failure
out=$(evaluate model-allocation:task-8 drain disabled) || fail "5: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "5a: a disabled unit did not fire"
[ "$(frag_count)" = 1 ] || fail "5b: want exactly one fragment, got $(frag_count)"
case $(cat "$(fragments)") in
  *disabled*) : ;;
  *) fail "5c: the fragment does not name the disabled terminal state" ;;
esac
echo "ok: a crash-loop disabled unit records the same way a completed one does"

# --- 6. a unit below both conditions records nothing ------------------------

reset_state
adaptation_on
# A plain launch: no events, so no escalation and no movement.
run_ad resolve model-allocation:task-7 --key drain >/dev/null || fail "6: seeding failed"
out=$(evaluate model-allocation:task-7 drain completed) || fail "6: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "6a: a unit at its starting tier fired"
[ "$(printf '%s\n' "$out" | field reason)" = below-thresholds ] \
  || fail "6b: the reason should be below-thresholds"
[ "$(frag_count)" = 0 ] || fail "6c: a non-firing unit wrote a fragment"
# A unit with no ledger at all is the same answer: zero history, no evidence.
out=$(evaluate model-allocation:task-6 drain completed) || fail "6: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "6d: a zero-history unit fired"
[ "$(frag_count)" = 0 ] || fail "6e: a zero-history unit wrote a fragment"
echo "ok: a unit below both conditions, and one with no history, record nothing"

# --- 7. escalated-then-reverted: back at the starting tier, below threshold -

reset_state
adaptation_on
escalate model-allocation:task-5 drain s1 step-failure
# A de-escalate petition reverses the most recent unreversed escalation, so the
# unit ends exactly where it started; one escalation is below the default
# threshold of 2, so neither condition holds.
escalate model-allocation:task-5 drain s2 petition-de-escalate
out=$(evaluate model-allocation:task-5 drain completed) || fail "7: evaluate failed"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/low ] || fail "7a: the unit did not revert to its starting tier"
[ "$(printf '%s\n' "$out" | field escalations)" = 1 ] || fail "7b: the escalation count should still be 1"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "7c: an escalated-then-reverted unit fired"
[ "$(frag_count)" = 0 ] || fail "7d: an escalated-then-reverted unit wrote a fragment"
echo "ok: a unit that escalated and reverted is below both conditions"

# --- 8. the escalation-count condition at the default threshold -------------

reset_state
adaptation_on
# Two escalations, then two reversals: the unit ends at its starting tier, so
# only the COUNT condition can fire. It reaches the default threshold of 2.
escalate model-allocation:task-4 drain s1 step-failure
escalate model-allocation:task-4 drain s2 flailing
escalate model-allocation:task-4 drain s3 petition-de-escalate
escalate model-allocation:task-4 drain s4 petition-de-escalate
out=$(evaluate model-allocation:task-4 drain completed) || fail "8: evaluate failed"
[ "$(printf '%s\n' "$out" | field final)" = sonnet/low ] || fail "8a: the unit should be back at its starting tier"
[ "$(printf '%s\n' "$out" | field escalations)" = 2 ] \
  || fail "8b: want 2 escalations, got $(printf '%s\n' "$out" | field escalations)"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "8c: the count condition did not fire at the default threshold"
[ "$(printf '%s\n' "$out" | field reason)" = threshold ] \
  || fail "8d: the reason should be threshold alone, got $(printf '%s\n' "$out" | field reason)"
[ "$(printf '%s\n' "$out" | field threshold)" = 2 ] || fail "8e: the default threshold is not 2"
[ "$(frag_count)" = 1 ] || fail "8f: want exactly one fragment, got $(frag_count)"
echo "ok: the escalation-count condition fires at the shipped default threshold"

# --- 9. the threshold is operator-configurable (REQ-E1.1) -------------------

reset_state
adaptation_on
printf 'allocation_feedback_threshold: 1\n' >>"$mlocal_cfg"
# One escalation, reverted: below the DEFAULT threshold (test 7 proved it does
# not fire), at a configured threshold of 1 it does.
escalate model-allocation:task-3 drain s1 step-failure
escalate model-allocation:task-3 drain s2 petition-de-escalate
out=$(evaluate model-allocation:task-3 drain completed) || fail "9: evaluate failed"
[ "$(printf '%s\n' "$out" | field threshold)" = 1 ] || fail "9a: the overlay threshold did not resolve"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "9b: the non-default threshold did not fire"
[ "$(frag_count)" = 1 ] || fail "9c: want exactly one fragment, got $(frag_count)"

# And raising it above the count suppresses a firing the default would allow.
reset_state
adaptation_on
printf 'allocation_feedback_threshold: 9\n' >>"$mlocal_cfg"
escalate model-allocation:task-2 drain s1 step-failure
escalate model-allocation:task-2 drain s2 flailing
escalate model-allocation:task-2 drain s3 petition-de-escalate
escalate model-allocation:task-2 drain s4 petition-de-escalate
out=$(evaluate model-allocation:task-2 drain completed) || fail "9: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "9d: a raised threshold still fired"
[ "$(frag_count)" = 0 ] || fail "9e: a raised threshold wrote a fragment"
echo "ok: the feedback threshold resolves through the config overlay in both directions"

# --- 10. a recording-helper failure surfaces non-zero, leaving no mark ------

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
[ "$rc" -ne 0 ] || fail "10a: a helper failure exited 0"
grep -q . "$tmp/err" || fail "10b: a helper failure printed nothing to stderr"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "10c: a failed recording reported fired=yes"
# No mark: the next evaluation must be free to retry, so the mark is written
# only after the helper reports success.
marks=$(run_led rows model-allocation:task-1 \
  | awk -F "$TAB" 'NF == 15 && $6 == "feedback" { n++ } END { print n + 0 }')
[ "$marks" = 0 ] || fail "10d: a failed recording left a mark row behind"
# Retry against a working store: the unit still records.
out=$(evaluate model-allocation:task-1 drain completed) || fail "10: retry failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "10e: the retry after a helper failure did not record"
[ "$(frag_count)" = 1 ] || fail "10f: the retry did not write exactly one fragment"
echo "ok: a recording-helper failure surfaces non-zero and leaves the unit retryable"

# --- 11. the knob ships in the tracked config and the options reference -----

cfg="$here/../config/defaults.yml"
grep -q '^allocation_feedback_threshold: 2$' "$cfg" \
  || fail "11a: config/defaults.yml does not ship allocation_feedback_threshold: 2"
# shellcheck disable=SC2016 # the backticks are the reference's markdown, not a substitution
grep -q '^| `allocation_feedback_threshold` | `2` |' "$here/../docs/options-reference.md" \
  || fail "11b: docs/options-reference.md has no allocation_feedback_threshold row"
echo "ok: the feedback threshold ships in the tracked config with an options-reference row"

# --- 12. an inherit key has no tier ladder to evaluate ----------------------

reset_state
adaptation_on
out=$(evaluate model-allocation:task-0 execute_step completed) || fail "12: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "12a: an inherit key fired"
[ "$(printf '%s\n' "$out" | field reason)" = inherit ] || fail "12b: the reason should be inherit"
[ "$(frag_count)" = 0 ] || fail "12c: an inherit key wrote a fragment"
echo "ok: a key that inherits its tier has no escalation history to feed back"

# --- 13. an unhealthy ledger degrades rather than recording on bad records --

reset_state
adaptation_on
escalate model-allocation:task-x drain s1 step-failure
led=$(run_led path model-allocation:task-x)
printf 'torn\trow\n' >>"$led"
out=$(evaluate model-allocation:task-x drain completed 2>"$tmp/err") || fail "13: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = no ] || fail "13a: an unhealthy ledger still recorded"
[ "$(printf '%s\n' "$out" | field reason)" = degraded ] || fail "13b: the reason should be degraded"
grep -q -i degraded "$tmp/err" || fail "13c: the degradation was not surfaced"
[ "$(frag_count)" = 0 ] || fail "13d: an unhealthy ledger wrote a fragment"
echo "ok: an unhealthy ledger degrades and surfaces instead of recording on untrusted records"

# --- 14. the mark is not a launch: `last-tier` must not answer from it ------

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
  || fail "14a: the fixture's last launch should be cap-clamped to sonnet/high, got '$before'"
out=$(evaluate model-allocation:task-y execution completed) || fail "14: evaluate failed"
[ "$(printf '%s\n' "$out" | field fired)" = yes ] || fail "14b: the fixture did not record a mark"
[ "$(printf '%s\n' "$out" | field final)" = fable/high ] \
  || fail "14c: the fixture's ladder position should be fable/high, got $(printf '%s\n' "$out" | field final)"
after=$(run_led last-tier model-allocation:task-y)
[ "$after" = "$before" ] || fail "14d: the feedback mark changed last-tier from '$before' to '$after'"
echo "ok: the terminal-state mark is inert to last-tier, which answers for launches only"

# --- 15. no outbound client is ever invoked --------------------------------

[ ! -s "$tmp/invocations" ] || fail "15: an outbound client was invoked: $(cat "$tmp/invocations")"
echo "ok: the feedback path makes no outbound call"

echo "all allocation-feedback tests passed"
