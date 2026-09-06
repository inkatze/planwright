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
#   completed  scripts/fleet-fence.sh `sweep`, in the TERMINAL branch. The
#              fence's documented lifecycle is "deleted at its unit's terminal
#              transition", and that branch is where the fleet reads the
#              authoritative `completed` derivation and acts on it.
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

worker=headless-demo-task-1
wscope=demo:1
unit=demo:task-1

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
LC_ALL=C grep -q '[[:cntrl:]]' "$err" \
  && fail "A1g: the refusal emitted a control byte: $(od -c <"$err" | head -3)"

# --- A2. no identity flags: the owner is byte-identical to before ----------
reset_liveness
out=$(crash_to_disable A2) || fail "A2: the disabling crash-record failed"
[ "$out" = "disabled 3" ] || fail "A2a: expected 'disabled 3', got '$out'"
[ "$(frag_count "$obsdir")" = 0 ] \
  || fail "A2b: an unwired crash-record recorded an observation"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "A2c: an unwired crash-record wrote a ledger mark"

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

frag=$(fragments "$obsdir")
grep -q 'terminal state disabled' "$frag" \
  || fail "A3d: the fragment does not name the disabled terminal state"
grep -q 'unit demo:task-1' "$frag" \
  || fail "A3e: the fragment does not name the unit the caller reported"

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

# --- A7. an `inherit` selection key is never evaluated ---------------------
reset_liveness
adaptation_on
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
  --event step-failure >/dev/null || fail "A8: the shipped-posture launch failed"
pw_shipped "$AD" resolve "$unit" --key execution --step s2 --attempt 1 \
  --event step-failure >/dev/null || fail "A8: the second shipped-posture launch failed"

pw_shipped "$FLV" crash-record "$worker" "$wscope" --now 1000 >/dev/null \
  || fail "A8: shipped crash 1 failed"
pw_shipped "$FLV" crash-record "$worker" "$wscope" --now 1100 >/dev/null \
  || fail "A8: shipped crash 2 failed"
out=$(pw_shipped "$FLV" crash-record "$worker" "$wscope" --now 1200 \
  --alloc-unit "$unit" --alloc-key execution \
  --obs-scope planwright --obs-dir "$obsdir") \
  || fail "A8a: the shipped-posture disable failed"
[ "$out" = "disabled 3" ] || fail "A8b: expected 'disabled 3', got '$out'"
[ "$(frag_count "$obsdir")" = 0 ] \
  || fail "A8c: the wiring recorded an observation on SHIPPED defaults"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "A8d: the wiring marked a ledger on SHIPPED defaults"

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
# Part B — the COMPLETED owner: scripts/fleet-fence.sh sweep
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

# The new flags belong to `sweep` alone: the sibling discipline is that a flag
# irrelevant to the subcommand is a usage error, never a validated-then-
# ignored no-op.
rc=0
pwf "$FF" gc --checkout "$co" --spec demo 1 \
  --alloc-key execution --obs-scope planwright >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "B1c: the identity flags should be refused for gc, got $rc"

# --- B2. no identity flags: the sweep is byte-identical to before ----------
reset_fence
out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ 2>/dev/null) \
  || fail "B2: the unwired sweep failed"
printf '%s\n' "$out" | grep -q "^gc${TAB}refs/planwright-fence/demo/1$" \
  || fail "B2a: the terminal fence was not GC'd: $out"
[ "$(frag_count "$fence_obs")" = 0 ] \
  || fail "B2b: an unwired sweep recorded an observation"
[ -d "$fence_obs" ] \
  && fail "B2c: an unwired sweep created an observations store"

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
  || fail "B3a: the terminal fence was not GC'd: $out"
printf '%s\n' "$out" | grep -q '^fired' \
  && fail "B3b: the evaluation contaminated the sweep's record stream"
origin_refs | grep -q 'demo/1$' \
  && fail "B3c: the terminal fence survived the sweep"
[ "$(frag_count "$fence_obs")" = 1 ] \
  || fail "B3d: expected one fragment, got $(frag_count "$fence_obs")"
[ "$(marks_of "$fence_unit")" = 1 ] \
  || fail "B3e: expected one feedback mark, got $(marks_of "$fence_unit")"

frag=$(fragments "$fence_obs")
grep -q 'terminal state completed' "$frag" \
  || fail "B3f: the fragment does not name the completed terminal state"
grep -q 'unit demo:task-1' "$frag" \
  || fail "B3g: the fragment does not carry the <spec>:task-<id> unit key"

# --- B4. once per unit across a repeated sweep ----------------------------
#
# The fence is gone after B3, so re-fence to make the terminal branch run
# again — the same shape a crash between the recording and the GC leaves.
refence
out=$(pwf "$FF" sweep --checkout "$co" --spec demo --pid $$ \
  --alloc-key execution --obs-scope planwright 2>/dev/null) \
  || fail "B4: the repeat sweep failed"
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
[ "$(marks_of "$fence_unit")" = 0 ] \
  || fail "B5d: a failed recording still left a mark"
rm -f "$fence_obs"

# --- B6. THE SHIPPED POSTURE: a no-op on the real defaults ----------------
reset_fence
adaptation_off
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

echo "PASS: tests/test-allocation-feedback-callsites.sh"
