#!/bin/bash
# Tests for the TERMINAL-STATE CALL SITES that invoke
# scripts/allocation-feedback.sh — the two owners of a unit's terminal
# transition (model-allocation D-11; REQ-F1.2, REQ-E1.1).
#
# scripts/allocation-feedback.sh is the escalation feedback loop, and its own
# suite (tests/test-allocation-feedback.sh) proves the evaluation. What that
# suite cannot prove is that anything ever RUNS it: the script's contract says
# the terminal state is the caller's to report, and until these call sites
# existed no caller reported one. This file is the wiring's own suite.
#
# The two owners, and why each is the one:
#   completed  scripts/fleet-fence.sh, wherever a fence is retired: `gc`, the
#              normal transition a tower runs on the unit it just finished, and
#              `sweep`'s terminal branch, the backstop for a tower that exited
#              first. A unit retired by both routes still records once.
#   disabled   scripts/fleet-liveness.sh `crash-record`, in the disable
#              branch. The crash-loop disable is the other terminal state:
#              no further relaunch is ever authorized.
#
# What is covered here:
#   - each owner invoking the evaluation with its own terminal state, the
#     caller-supplied unit identity, selection key and observation scope;
#   - the identity flags being ALL-OR-NONE at each owner: none of them leaves
#     the owner byte-identical to its pre-wiring behavior, and a partial set
#     is a usage error rather than a silently-skipped evaluation;
#   - once-per-unit emission across a REPEATED terminal report (the disable
#     flag is sticky, and a fence sweep re-runs), which is the property the
#     ledger mark exists for;
#   - a recording failure never failing the operation the call hangs off: the
#     disable still commits and the fence is still GC'd, the failure is
#     surfaced on stderr, and NO ledger mark is left, so the unit stays
#     retryable;
#   - the evaluation's stdout never contaminating either owner's own stdout
#     contract (both are parsed record streams);
#   - an `inherit` selection key never being evaluated at all;
#   - THE SHIPPED POSTURE: with the repo's real config/defaults.yml, where
#     allocation_adaptation is `off`, both call sites are a no-op — nothing
#     escalates, so neither firing condition is ever reached and no fragment
#     and no mark are written;
#   - the mark staying inert to the ledger's other readers after a call site
#     wrote it (`last-tier` is a launch tier, never a ladder position).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-feedback-callsites.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REAL_DEFAULTS="$here/../config/defaults.yml"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Every script resolves its siblings through its own dir, so the suite runs
# them out of one copied tree (the sweep suite's fixture shape).
sbin="$tmp/sbin"
mkdir -p "$sbin"
cp "$here/../scripts/"*.sh "$sbin/"

FLV="$sbin/fleet-liveness.sh"
FF="$sbin/fleet-fence.sh"

# The evaluation is invoked as a SIBLING of the call site, so the seam that
# records whether a call site was reached is that sibling's own path. The
# wrapper appends its argv and then execs the real script, so every assertion
# below is made against real behavior, not a stub's.
#
# This is what separates "ran and recorded nothing" from "never ran" — the
# distinction the shipped-posture sections turn on, and one that no assertion
# about absent output can make on its own.
real_afb="$sbin/allocation-feedback.real.sh"
mv "$sbin/allocation-feedback.sh" "$real_afb"
calls="$tmp/afb-calls"
: >"$calls"
cat >"$sbin/allocation-feedback.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$calls"
exec "$real_afb" "\$@"
EOF
chmod +x "$sbin/allocation-feedback.sh"

call_count() {
  awk 'END { print NR + 0 }' "$calls"
}

calls_reset() {
  : >"$calls"
}
AD="$sbin/allocation-adapt.sh"
LEDGER="$sbin/allocation-ledger.sh"
FUG="$sbin/fleet-usage-gate.sh"

[ -x "$FLV" ] || fail "scripts/fleet-liveness.sh missing or not executable"
[ -x "$FF" ] || fail "scripts/fleet-fence.sh missing or not executable"

# Outbound clients are stubbed: an LLM/API call anywhere in a terminal-state
# path would break the determinism floor (REQ-A1.1). `gh` is stubbed
# separately below, because orchestrate-state.sh genuinely probes it.
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget; do
  printf '#!/bin/sh\nexit 0\n' >"$stubbin/$c"
  chmod +x "$stubbin/$c"
done

repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
mlocal_cfg="$repo/.claude/planwright.local.yml"
core_cfg="$tmp/core-defaults.yml"

# The core defaults these call sites read. Every row is the shipped value from
# config/defaults.yml EXCEPT `allocation_adjustment_cap`, widened to 4 so the
# seeded escalation fixtures below are not bounded by the cap. The shipped
# file itself is used verbatim by the shipped-posture section, which is the
# one that has to be about the real values.
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

fleet_home="$tmp/fleet"
obsdir="$tmp/obs"
mkdir -p "$fleet_home" "$obsdir"
chmod 700 "$fleet_home"

# env_run <defaults-file> <script> <args...>
env_run() {
  er_defaults=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$er_defaults" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$@" </dev/null
}

pw() { env_run "$core_cfg" "$@"; }
pw_shipped() { env_run "$REAL_DEFAULTS" "$@"; }

fragments() {
  find "$1/entries" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort
}

frag_count() {
  fragments "$1" | awk 'END { print NR + 0 }'
}

marks_of() {
  pw "$LEDGER" rows "$1" 2>/dev/null \
    | awk -F "$TAB" 'NF == 15 && $6 == "feedback" && $14 == "recorded" { n++ } END { print n + 0 }'
}

# adaptation_on: arm the master knob through the machine-local layer, plus a
# usage signal low enough that no escalation is denied for an unavailable one
# and no per-tier cap binds — so the seeded ledger is the ladder's own history.
adaptation_on() {
  printf 'allocation_adaptation: on\n' >"$mlocal_cfg"
  printf 'Current session\n10%% used\n\nCurrent week (all models)\n10%% used\n' \
    | env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
      PATH="$stubbin:$PATH" \
      PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
      PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
      PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      /bin/sh "$FUG" capture >/dev/null || fail "seeding the usage signal failed"
}

adaptation_off() {
  rm -f "$mlocal_cfg"
}

# escalate <unit> <key> <step>: drive one launch boundary through the engine so
# the unit's ledger carries a real APPLIED escalation row. Seeding by driving
# the engine (never by hand-writing rows) is what makes the fixture a ledger
# the two scripts agree about.
escalate() {
  pw "$AD" resolve "$1" --key "$2" --step "$3" --attempt 1 --event step-failure \
    >/dev/null || fail "seeding an escalation for $1 failed"
}

# ==========================================================================
# Part A — the DISABLED owner: scripts/fleet-liveness.sh crash-record
# ==========================================================================

worker=headless-alpha-task-1
wscope=alpha:1
unit=alpha:task-1

# crash_to_disable <label> [extra crash-record args...]: three crashes at the
# shipped threshold of 3, the third of which disables. Only the LAST call
# carries the extra args, so a test can assert what the disable transition
# does without the two sub-threshold records seeing the same flags.
crash_to_disable() {
  ctd_label=$1
  shift
  pw "$FLV" crash-record "$worker" "$wscope" --now 1000 >/dev/null \
    || fail "$ctd_label: crash 1 failed"
  pw "$FLV" crash-record "$worker" "$wscope" --now 1100 >/dev/null \
    || fail "$ctd_label: crash 2 failed"
  pw "$FLV" crash-record "$worker" "$wscope" --now 1200 "$@"
}

reset_liveness() {
  rm -rf "$fleet_home" "$obsdir"
  mkdir -p "$fleet_home" "$obsdir"
  chmod 700 "$fleet_home"
  calls_reset
}

# --- A1. the identity flags are all-or-none -------------------------------
#
# A partial set is a USAGE error, not a quietly-skipped evaluation: a caller
# that wired three of the four flags has a bug, and swallowing it would
# reproduce the exact failure this whole change exists to close — a feedback
# loop that never runs and never says so.
reset_liveness
rc=0
pw "$FLV" crash-record "$worker" "$wscope" --now 1000 \
  --alloc-unit "$unit" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "A1a: a lone --alloc-unit should be a usage error (exit 2), got $rc"

rc=0
pw "$FLV" crash-record "$worker" "$wscope" --now 1000 \
  --alloc-unit "$unit" --alloc-key execution --obs-scope planwright >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "A1b: three of the four identity flags should exit 2, got $rc"

rc=0
pw "$FLV" crash-record "$worker" "$wscope" --now 1000 \
  --alloc-key execution >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "A1c: a lone --alloc-key should be a usage error (exit 2), got $rc"

# A refused usage error writes NOTHING — not even the crash counter, since the
# parse fails before the record.
[ ! -e "$fleet_home/liveness/crash/$worker" ] \
  || fail "A1d: a usage error still wrote a crash record"

# A malformed unit is refused where it enters, and the refusal must not
# re-emit what it was handed. `/bin/sh` is dash on Linux, whose `echo`
# re-expands a literal backslash escape into the control byte the sanitizer
# strips — so the diagnostic is checked for the BYTE, not the two characters.
rc=0
err="$tmp/a1.err"
pw "$FLV" crash-record "$worker" "$wscope" --now 1000 \
  --alloc-unit 'demo:task-1\n\033[31mINJECTED' --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "A1e: a malformed --alloc-unit should exit 2, got $rc"
[ "$(awk 'END { print NR }' "$err")" = 1 ] \
  || fail "A1f: the refusal spans several lines — an escape was re-expanded: $(od -c <"$err" | head -3)"
if LC_ALL=C grep -q '[[:cntrl:]]' "$err"; then
  fail "A1g: the refusal emitted a control byte: $(od -c <"$err" | head -3)"
fi

# --- A2. no identity flags: the owner is byte-identical to before ----------
reset_liveness
out=$(crash_to_disable A2) || fail "A2: the disabling crash-record failed"
[ "$out" = "disabled 3" ] || fail "A2a: expected 'disabled 3', got '$out'"
[ "$(frag_count "$obsdir")" = 0 ] \
  || fail "A2x1: an unwired crash-record recorded an observation"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "A2x2: an unwired crash-record wrote a ledger mark"
[ "$(call_count)" = 0 ] \
  || fail "A2x3: an unwired crash-record invoked the evaluation anyway"

# --- A2b. a sub-threshold crash reports nothing, flags or no flags ---------
#
# This is what pins the call INSIDE the disable branch. Hoisted one level out,
# every crash would report `disabled`, and every other assertion in Part A
# would still pass.
reset_liveness
out=$(pw "$FLV" crash-record "$worker" "$wscope" --now 1000 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir") \
  || fail "A2b0: the sub-threshold crash-record failed"
case $out in
  "1 "*) ;;
  *) fail "A2b1: expected a backoff line, got '$out'" ;;
esac
[ "$(call_count)" = 0 ] \
  || fail "A2b2: a sub-threshold crash reported a terminal state (calls=$(call_count))"

# --- A3. the disable evaluates, fires, and records exactly one fragment ----
reset_liveness
adaptation_on
escalate "$unit" execution s1
escalate "$unit" execution s2

out=$(crash_to_disable A3 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir") \
  || fail "A3: the disabling crash-record failed"

# The owner's own stdout contract is unchanged: the evaluation's TSV must not
# leak into the line a supervisor parses.
[ "$out" = "disabled 3" ] \
  || fail "A3a: the evaluation contaminated crash-record's stdout: '$out'"
[ "$(frag_count "$obsdir")" = 1 ] \
  || fail "A3b: expected exactly one fragment, got $(frag_count "$obsdir")"
[ "$(marks_of "$unit")" = 1 ] \
  || fail "A3c: expected exactly one feedback mark, got $(marks_of "$unit")"

[ "$(call_count)" = 1 ] \
  || fail "A3f: expected exactly one evaluation, got $(call_count)"
grep -q -- '--terminal disabled' "$calls" \
  || fail "A3g: the disable did not report the disabled terminal state: $(cat "$calls")"
grep -q -- "$unit --key execution" "$calls" \
  || fail "A3h: the call site did not pass the caller's unit and key: $(cat "$calls")"

frag=$(fragments "$obsdir")
grep -q 'terminal state disabled' "$frag" \
  || fail "A3d: the fragment does not name the disabled terminal state"
grep -q "unit $unit" "$frag" \
  || fail "A3e: the fragment does not name the unit the caller reported"
grep -q '^- [0-9-]* \[planwright\] ' "$frag" \
  || fail "A3e2: the fragment does not carry the caller's observation scope: $(cat "$frag")"

# --- A4. once per unit across a REPEATED terminal report -------------------
#
# `disabled` is sticky, so a supervisor that records another crash reports the
# same terminal state again. The ledger mark is what makes the second report a
# no-op.
out=$(pw "$FLV" crash-record "$worker" "$wscope" --now 1300 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir") \
  || fail "A4: the repeat crash-record failed"
[ "$out" = "disabled 4" ] || fail "A4a: expected 'disabled 4', got '$out'"
[ "$(frag_count "$obsdir")" = 1 ] \
  || fail "A4b: a repeated terminal report re-recorded ($(frag_count "$obsdir") fragments)"
[ "$(marks_of "$unit")" = 1 ] \
  || fail "A4c: a repeated terminal report wrote a second mark"

# --- A5. the mark is inert to the ledger's other readers -------------------
#
# Already implemented in allocation-ledger.sh; asserted here because a call
# site is the first thing that ever put a mark in a ledger a launch reader
# then reads. `last-tier` answers the last tier a LAUNCH used — never the
# ladder position the mark carries.
lt=$(pw "$LEDGER" last-tier "$unit") || fail "A5: last-tier failed"
mark_final=$(pw "$LEDGER" rows "$unit" \
  | awk -F "$TAB" 'NF == 15 && $6 == "feedback" { print $9 "\t" $10; exit }')
[ -n "$lt" ] || fail "A5a: last-tier answered empty for a unit that launched"
[ "$lt" != "$mark_final" ] \
  || fail "A5b: last-tier answered the mark's ladder position, not a launch tier"

# --- A6. a recording failure never fails the disable -----------------------
#
# The disable is already durable when the evaluation runs. A symlinked obs
# store is refused by the recording helper, so the evaluation exits non-zero
# with nothing published — and the disable must still complete, surface the
# failure, and leave NO mark so the unit stays retryable.
reset_liveness
adaptation_on
escalate "$unit" execution s1
escalate "$unit" execution s2
badobs="$tmp/bad-obs"
rm -rf "$badobs"
ln -s "$tmp/nowhere" "$badobs"

err="$tmp/a6.err"
out=$(crash_to_disable A6 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$badobs" 2>"$err") \
  || fail "A6a: a recording failure failed the disable itself"
[ "$out" = "disabled 3" ] || fail "A6b: expected 'disabled 3', got '$out'"
[ -s "$err" ] || fail "A6c: the recording failure was swallowed (empty stderr)"
grep -q 'allocation-feedback' "$err" \
  || fail "A6d: stderr does not name the failing evaluation: $(cat "$err")"
[ "$(frag_count "$badobs")" = 0 ] \
  || fail "A6e1: a failed recording still published a fragment"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "A6e: a failed recording still left a mark (the unit is no longer retryable)"

# The unit stays retryable: repair the store and the next terminal report
# records.
rm -f "$badobs"
mkdir -p "$badobs"
out=$(pw "$FLV" crash-record "$worker" "$wscope" --now 1300 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$badobs") \
  || fail "A6f: the retry after repair failed"
[ "$(frag_count "$badobs")" = 1 ] \
  || fail "A6g: the unit did not stay retryable after a recording failure"

# --- A6b. a PUBLISHED fragment whose mark failed is not a lost observation --
#
# Exit 1 means two different things and only the evaluation's stdout says
# which. Here the fragment lands and the ledger mark cannot, which the callee
# reports on its own stderr as "recorded a fragment ... but could not mark" —
# so a call site that answered "the observation is LOST" would contradict the
# line printed immediately above it and point the operator the wrong way.
reset_liveness
adaptation_on
escalate "$unit" execution s1
escalate "$unit" execution s2
led_file=$(pw "$LEDGER" path "$unit")
pw "$FLV" crash-record "$worker" "$wscope" --now 1000 >/dev/null \
  || fail "A6b: crash 1 failed"
pw "$FLV" crash-record "$worker" "$wscope" --now 1100 >/dev/null \
  || fail "A6b: crash 2 failed"
chmod 400 "$led_file"
err="$tmp/a6b.err"
out=$(pw "$FLV" crash-record "$worker" "$wscope" --now 1200 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir" 2>"$err") \
  || fail "A6b1: a mark failure failed the disable itself"
chmod 600 "$led_file"
[ "$out" = "disabled 3" ] || fail "A6b2: expected 'disabled 3', got '$out'"
if grep -q 'observation is LOST' "$err"; then
  fail "A6b3: a published fragment was reported as a lost observation: $(cat "$err")"
fi
grep -q 'RECORDED' "$err" \
  || fail "A6b4: the published-but-unmarked state was not surfaced: $(cat "$err")"
[ "$(frag_count "$obsdir")" = 1 ] \
  || fail "A6b5: expected the fragment to be published, got $(frag_count "$obsdir")"

# --- A7. an `inherit` selection key is never evaluated ---------------------
reset_liveness
adaptation_on
escalate "$unit" execution s1
escalate "$unit" execution s2
out=$(crash_to_disable A7 \
  --alloc-unit "$unit" --alloc-key offload \
  --obs-scope planwright --obs-dir "$obsdir") \
  || fail "A7: the disable failed for an inherit key"
[ "$out" = "disabled 3" ] || fail "A7a: expected 'disabled 3', got '$out'"
[ "$(frag_count "$obsdir")" = 0 ] \
  || fail "A7b: an inherit-tier key recorded an observation"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "A7c: an inherit-tier key wrote a ledger mark"

# --- A8. THE SHIPPED POSTURE: a no-op on the real defaults -----------------
#
# Read against config/defaults.yml itself, where allocation_adaptation is
# `off`. Nothing escalates, so the unit's derived final ladder position equals
# its configured start and its applied-escalation count is 0 against a
# threshold of 2: neither firing condition is reachable. The call site runs —
# it is wired — and records nothing.
reset_liveness
adaptation_off
pw_shipped "$AD" resolve "$unit" --key execution --step s1 --attempt 1 \
  --event step-failure >/dev/null || fail "A8s1: the shipped-posture launch failed"
pw_shipped "$AD" resolve "$unit" --key execution --step s2 --attempt 1 \
  --event step-failure >/dev/null || fail "A8s2: the second shipped-posture launch failed"

pw_shipped "$FLV" crash-record "$worker" "$wscope" --now 1000 >/dev/null \
  || fail "A8s3: shipped crash 1 failed"
pw_shipped "$FLV" crash-record "$worker" "$wscope" --now 1100 >/dev/null \
  || fail "A8s4: shipped crash 2 failed"
out=$(pw_shipped "$FLV" crash-record "$worker" "$wscope" --now 1200 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir") \
  || fail "A8a: the shipped-posture disable failed"
[ "$out" = "disabled 3" ] || fail "A8b: expected 'disabled 3', got '$out'"
[ "$(frag_count "$obsdir")" = 0 ] \
  || fail "A8c: the wiring recorded an observation on SHIPPED defaults"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "A8d: the wiring marked a ledger on SHIPPED defaults"
# The no-op is the LADDER's, not a call site that quietly did nothing.
[ "$(call_count)" = 1 ] \
  || fail "A8d2: the shipped-posture disable did not reach the evaluation (calls=$(call_count))"

# The silence has to be the LADDER's, not an empty fixture's: the unit really
# did launch twice on a triggering event, and the evaluation really did run and
# reach neither firing condition. Asserted through the evaluation's own report,
# because the call site discards its stdout.
rows=$(pw_shipped "$LEDGER" rows "$unit" | awk 'END { print NR + 0 }')
[ "$rows" -gt 0 ] \
  || fail "A8e: the shipped-posture unit has no ledger history, so A8c/A8d prove nothing"
verdict=$(pw_shipped "$sbin/allocation-feedback.sh" evaluate "$unit" \
  --key execution --terminal disabled --scope planwright --obs-dir "$obsdir")
printf '%s\n' "$verdict" | grep -q "^fired${TAB}no$" \
  || fail "A8f: the shipped-posture evaluation fired: $verdict"
printf '%s\n' "$verdict" | grep -q "^reason${TAB}below-thresholds$" \
  || fail "A8g: expected below-thresholds on shipped defaults, got: $verdict"
printf '%s\n' "$verdict" | grep -q "^escalations${TAB}0$" \
  || fail "A8h: shipped defaults escalated a unit ($verdict)"
[ "$(frag_count "$obsdir")" = 0 ] \
  || fail "A8i: the shipped-posture evaluation recorded a fragment"

# ==========================================================================
# Part B — the COMPLETED owner: scripts/fleet-fence.sh (gc and sweep)
# ==========================================================================
#
# The sweep needs a real `origin` and a real spec bundle, because terminality
# is the derivation engine's answer read off git ground truth. The fixture is
# the sweep suite's, trimmed to the two units this file needs.

ghbin="$tmp/ghbin"
mkdir -p "$ghbin"
: >"$tmp/gh-prs"
cat >"$ghbin/gh" <<EOF
#!/bin/sh
cat "$tmp/gh-prs"
EOF
chmod +x "$ghbin/gh"

origin="$tmp/origin.git"
git -c init.defaultBranch=main init -q --bare "$origin"
git clone -q "$origin" "$tmp/co" 2>/dev/null
co="$tmp/co"
git -C "$co" config user.email fence@test.invalid
git -C "$co" config user.name fence-test
git -C "$co" symbolic-ref HEAD refs/heads/main

mkdir -p "$co/specs/demo"
cat >"$co/specs/demo/tasks.md" <<'TASKS'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Terminal by trailer

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 2 — Not terminal

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

## Completed

(none yet)

## In progress

(none yet)

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
TASKS

(
  cd "$co"
  git add specs
  git commit -qm "spec fixture"
  git commit -q --allow-empty -m "close task 1

Planwright-Task: demo/1"
  git push -q origin HEAD:refs/heads/main
)
git -C "$co" fetch -q origin

fence_unit=demo:task-1
fence_obs="$co/specs/_observations"

# pwf: Part B's env — Part A's, plus the gh stub the derivation probes and the
# base ref the reachability read measures against.
pwf() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PATH="$ghbin:$stubbin:$PATH" \
    PLANWRIGHT_BASE_REF=main \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$@" </dev/null
}

origin_refs() {
  git -C "$origin" for-each-ref --format='%(refname)' refs/planwright-fence
}

refence() {
  pwf "$FF" fence --checkout "$co" --spec demo 1 >/dev/null \
    || fail "fixture: fencing demo/1 failed"
}

reset_fence() {
  rm -rf "$fleet_home" "$fence_obs"
  mkdir -p "$fleet_home"
  chmod 700 "$fleet_home"
  git -C "$origin" for-each-ref --format='%(refname)' refs/planwright-fence \
    | while read -r r; do
      [ -z "$r" ] || git -C "$origin" update-ref -d "$r"
    done
  calls_reset
  refence
}

# --- B1. the identity flags are all-or-none -------------------------------
reset_fence
rc=0
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1a: a lone --alloc-key on sweep should exit 2, got $rc"
rc=0
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --obs-scope planwright >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1b: a lone --obs-scope on sweep should exit 2, got $rc"

# The flags belong to `gc` as well as `sweep`, and to nothing else: `gc` is the
# NORMAL terminal transition (a tower retiring the fence of a unit it just
# finished) while the sweep is the backstop for a tower that exited first, so
# wiring only the sweep would leave the common case silent.
rc=0
pwf "$FF" fence --checkout "$co" --spec demo 2 \
  --alloc-key execution --obs-scope planwright >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1c: the identity flags should be refused for fence, got $rc"

# An explicitly EMPTY value is not the flag being omitted. Read as omission it
# would silently disable the evaluation, which is what all-or-none exists to
# stop — and the pair being empty TOGETHER is the case the all-or-none test
# alone cannot catch.
rc=0
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key '' --obs-scope '' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1d: an explicitly empty identity pair should exit 2, got $rc"
rc=0
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key '' --obs-scope planwright >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1e: an explicitly empty --alloc-key should exit 2, got $rc"

# A malformed value is refused, and the refusal must not re-emit what it was
# handed. This is Part A's escape assertion on the other owner: its diagnostics
# go through a different helper, and a value that fails the grammar is exactly
# the population that carries a backslash.
rc=0
err="$tmp/b1.err"
pwf "$FF" gc --checkout "$co" --spec demo 1 \
  --alloc-key 'bad\n\033[31mINJECTED' --obs-scope planwright >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "B1f: a malformed --alloc-key should exit 2, got $rc"
[ "$(awk 'END { print NR }' "$err")" = 1 ] \
  || fail "B1g: the refusal spans several lines — an escape was re-expanded: $(od -c <"$err" | head -3)"
if LC_ALL=C grep -q '[[:cntrl:]]' "$err"; then
  fail "B1h: the refusal emitted a control byte: $(od -c <"$err" | head -3)"
fi
rc=0
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope 'bad scope' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1i: a malformed --obs-scope should exit 2, got $rc"

# `--obs-dir` without the identity it belongs to would be accepted and ignored,
# which this file's flag discipline forbids.
rc=0
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --obs-dir "$tmp/elsewhere" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1j: a lone --obs-dir should exit 2, got $rc"

# --- B2. no identity flags: the sweep is byte-identical to before ----------
reset_fence
out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ 2>/dev/null) \
  || fail "B2: the unwired sweep failed"
printf '%s\n' "$out" | grep -q "^gc${TAB}refs/planwright-fence/demo/1$" \
  || fail "B2a: the terminal fence was not GC'd: $out"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B2b: an unwired sweep recorded an observation"
[ ! -d "$fence_obs" ] \
  || fail "B2c: an unwired sweep created an observations store"
[ "$(call_count)" = 0 ] \
  || fail "B2d: an unwired sweep invoked the evaluation anyway"

# --- B3. the terminal branch evaluates, fires, and GCs --------------------
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2

out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright 2>/dev/null) \
  || fail "B3: the wired sweep failed"

# The sweep's stdout is a parsed record stream; the evaluation's TSV must not
# be in it.
printf '%s\n' "$out" | grep -q "^gc${TAB}refs/planwright-fence/demo/1$" \
  || fail "B3x1: the terminal fence was not GC'd: $out"
if printf '%s\n' "$out" | grep -q '^fired'; then
  fail "B3x2: the evaluation contaminated the sweep's record stream"
fi
if origin_refs | grep -q 'demo/1$'; then
  fail "B3x3: the terminal fence survived the sweep"
fi
[ "$(frag_count "$fence_obs")" = 1 ] \
  || fail "B3x4: expected one fragment, got $(frag_count "$fence_obs")"
[ "$(marks_of "$fence_unit")" = 1 ] \
  || fail "B3x5: expected one feedback mark, got $(marks_of "$fence_unit")"

[ "$(call_count)" = 1 ] \
  || fail "B3h: expected exactly one evaluation, got $(call_count)"
grep -q -- '--terminal completed' "$calls" \
  || fail "B3i: the sweep did not report the completed terminal state: $(cat "$calls")"
grep -q -- 'demo:task-1 --key execution' "$calls" \
  || fail "B3j: the sweep did not assemble the <spec>:task-<id> unit key: $(cat "$calls")"

frag=$(fragments "$fence_obs")
grep -q 'terminal state completed' "$frag" \
  || fail "B3x6: the fragment does not name the completed terminal state"
grep -q 'unit demo:task-1' "$frag" \
  || fail "B3x7: the fragment does not carry the <spec>:task-<id> unit key"

# --- B3a. a NON-terminal fence in the same pass reports nothing -----------
#
# This is what pins the call INSIDE the sweep's terminal branch. Moved up into
# the loop body, every fenced unit would report `completed`, and every other
# assertion in Part B would still pass. Unit 2 has no merge, no trailer and no
# PR, so the derivation holds it non-terminal.
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2
escalate "demo:task-2" execution s1
escalate "demo:task-2" execution s2
pwf "$FF" fence --checkout "$co" --spec demo 2 >/dev/null \
  || fail "B3a0: fencing the non-terminal unit failed"
calls_reset

out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ --min-interval 0 \
  --alloc-key execution --obs-scope planwright 2>/dev/null) \
  || fail "B3a1: the mixed sweep failed"
[ "$(call_count)" = 1 ] \
  || fail "B3a2: expected one evaluation for the one terminal unit, got $(call_count): $(cat "$calls")"
if grep -q 'demo:task-2' "$calls"; then
  fail "B3a3: a NON-terminal unit was reported as completed: $(cat "$calls")"
fi
origin_refs | grep -q 'demo/2$' \
  || fail "B3a4: the non-terminal fence was retired"
[ "$(marks_of "demo:task-2")" = 0 ] \
  || fail "B3a5: a non-terminal unit was marked"

# --- B3b. the normal terminal transition (`gc`) reports too ---------------
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2

out=$(pwf "$FF" gc --checkout "$co" --spec demo 1 \
  --alloc-key execution --obs-scope planwright 2>/dev/null) \
  || fail "B3b0: the wired gc failed"
printf '%s\n' "$out" | grep -q "^gc${TAB}refs/planwright-fence/demo/1$" \
  || fail "B3b1: gc did not retire the fence: $out"
if printf '%s\n' "$out" | grep -q '^fired'; then
  fail "B3b2: the evaluation contaminated gc's record stream"
fi
[ "$(call_count)" = 1 ] \
  || fail "B3b3: gc did not reach the evaluation (calls=$(call_count))"
grep -q -- '--terminal completed' "$calls" \
  || fail "B3b4: gc did not report the completed terminal state: $(cat "$calls")"
[ "$(frag_count "$fence_obs")" = 1 ] \
  || fail "B3b5: expected one fragment from gc, got $(frag_count "$fence_obs")"

# A unit that travels BOTH routes records once: the mark bounds emission, not
# the route it arrived by.
refence
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright >/dev/null 2>&1 \
  || fail "B3b6: the sweep after a gc failed"
[ "$(frag_count "$fence_obs")" = 1 ] \
  || fail "B3b7: a unit retired by both routes recorded twice"
[ "$(marks_of "$fence_unit")" = 1 ] \
  || fail "B3b8: a unit retired by both routes carries two marks"

# --- B3c. an unhealthy ledger degrades: nothing recorded, nothing failed ---
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2
led=$(pw "$LEDGER" path "$fence_unit") || fail "B3c0: could not resolve the ledger path"
printf 'torn\trow\n' >>"$led"
out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright 2>/dev/null) \
  || fail "B3c1: an unhealthy ledger failed the sweep"
printf '%s\n' "$out" | grep -q "^gc${TAB}refs/planwright-fence/demo/1$" \
  || fail "B3c2: an unhealthy ledger held the fence: $out"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B3c3: an unhealthy ledger still recorded a fragment"

# --- B3e. the caller may name the observations store ----------------------
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2
named="$tmp/named-obs"
rm -rf "$named"
pwf "$FF" gc --checkout "$co" --spec demo 1 \
  --alloc-key execution --obs-scope planwright --obs-dir "$named" >/dev/null 2>&1 \
  || fail "B3e0: the gc with a named store failed"
[ "$(frag_count "$named")" = 1 ] \
  || fail "B3e1: the fragment did not land in the caller's store"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B3e2: the fragment also landed in the default store"

# A relative store is the checkout's, not the tower's cwd — this command has a
# repo root and uses it.
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2
rm -rf "$co/rel-obs"
pwf "$FF" gc --checkout "$co" --spec demo 1 \
  --alloc-key execution --obs-scope planwright --obs-dir rel-obs >/dev/null 2>&1 \
  || fail "B3e3: the gc with a relative store failed"
[ "$(frag_count "$co/rel-obs")" = 1 ] \
  || fail "B3e4: a relative --obs-dir did not resolve against the checkout"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B3e5: a relative --obs-dir also wrote to the default store"
rm -rf "$co/rel-obs"

# --- B4. once per unit across a repeated sweep ----------------------------
#
# The fence is gone after the pass above, so re-fence to make the terminal
# branch run again — the same shape a crash between the recording and the GC
# leaves.
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright >/dev/null 2>&1 \
  || fail "B4s1: seeding the first recording failed"
[ "$(frag_count "$fence_obs")" = 1 ] || fail "B4s2: the seeding pass did not record"
refence
pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright >/dev/null 2>&1 \
  || fail "B4c: the repeat sweep failed"
[ "$(frag_count "$fence_obs")" = 1 ] \
  || fail "B4a: a repeated sweep re-recorded ($(frag_count "$fence_obs") fragments)"
[ "$(marks_of "$fence_unit")" = 1 ] \
  || fail "B4b: a repeated sweep wrote a second mark"

# --- B5. a recording failure never fails the sweep ------------------------
reset_fence
adaptation_on
escalate "$fence_unit" execution s1
escalate "$fence_unit" execution s2
rm -rf "$fence_obs"
ln -s "$tmp/nowhere" "$fence_obs"

err="$tmp/b5.err"
out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright 2>"$err") \
  || fail "B5a: a recording failure failed the sweep itself"
printf '%s\n' "$out" | grep -q "^gc${TAB}refs/planwright-fence/demo/1$" \
  || fail "B5b: the fence was not GC'd after a recording failure: $out"
grep -q 'allocation-feedback' "$err" \
  || fail "B5c: the recording failure was swallowed: $(cat "$err")"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B5d1: a failed recording still published a fragment"
[ "$(marks_of "$fence_unit")" = 0 ] \
  || fail "B5d: a failed recording still left a mark"
rm -f "$fence_obs"

# --- B6. THE SHIPPED POSTURE: a no-op on the real defaults ----------------
reset_fence
adaptation_off
pw_shipped "$AD" resolve "$fence_unit" --key execution --step s1 --attempt 1 \
  --event step-failure >/dev/null || fail "B6s1: the shipped-posture launch failed"
pw_shipped "$AD" resolve "$fence_unit" --key execution --step s2 --attempt 1 \
  --event step-failure >/dev/null || fail "B6s2: the second shipped-posture launch failed"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
  PATH="$ghbin:$stubbin:$PATH" \
  PLANWRIGHT_BASE_REF=main \
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$REAL_DEFAULTS" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/sh "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright >/dev/null 2>&1 \
  || fail "B6a: the shipped-posture sweep failed"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B6b: the wiring recorded an observation on SHIPPED defaults"
[ "$(marks_of "$fence_unit")" = 0 ] \
  || fail "B6c: the wiring marked a ledger on SHIPPED defaults"
[ "$(call_count)" = 1 ] \
  || fail "B6d: the shipped-posture sweep did not reach the evaluation (calls=$(call_count))"

# As in Part A, the silence has to be the LADDER's rather than an empty
# fixture's: the unit launched twice on a triggering event under the shipped
# defaults, and the evaluation still reached neither firing condition.
rows=$(pw_shipped "$LEDGER" rows "$fence_unit" | awk 'END { print NR + 0 }')
[ "$rows" -gt 0 ] \
  || fail "B6e: the shipped-posture unit has no ledger history, so B6b/B6c prove nothing"
verdict=$(pw_shipped "$sbin/allocation-feedback.sh" evaluate "$fence_unit" \
  --key execution --terminal completed --scope planwright --obs-dir "$fence_obs")
printf '%s\n' "$verdict" | grep -q "^fired${TAB}no$" \
  || fail "B6f: the shipped-posture evaluation fired: $verdict"
printf '%s\n' "$verdict" | grep -q "^reason${TAB}below-thresholds$" \
  || fail "B6g: expected below-thresholds on shipped defaults, got: $verdict"
printf '%s\n' "$verdict" | grep -q "^escalations${TAB}0$" \
  || fail "B6h: shipped defaults escalated a unit ($verdict)"

echo "PASS: tests/test-allocation-feedback-callsites.sh"
