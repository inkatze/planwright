#!/bin/bash
# Tests for the LAUNCH-POINT WIRING beyond the fleet (model-allocation Task 6;
# D-4, D-10, D-12, D-13; REQ-A1.2, REQ-B1.1, REQ-B1.2, REQ-B1.3).
#
# Task 6's claim is that every launch point planwright ships now consults the
# shared selection policy before it launches work, and applies the answer only
# as far as the backend can carry it. This file is where that claim is
# checked. tests/test-allocation-apply.sh covers the decision itself; here the
# concern is the SURFACES: that each one actually asks, that the shipped
# defaults leave every launch byte-identical to today, and that a resolved
# value reaches a launch as discrete argv rather than as text in a command.
#
# Scriptable vs enumerated (REQ-B1.1). `/offload`'s dispatch step is a script,
# so it is exercised directly. The other two launch points construct their
# launch in SKILL prose, which only an interactive session executes, so they
# are pinned the way this repo pins its other prose-borne launch contracts
# (tests/test-dispatch-launch-pin.sh): a static scan asserting the prose names
# the resolver at the point it launches. That is a weaker guarantee than
# running it, which is exactly why the manual remainder is enumerated BY NAME
# in the test spec and re-verified by a recorded manual pass at review — an
# unenumerated surface must never be able to slip into the manual bucket by
# silence.
#
# What is covered:
#   - defaults-only equivalence at the offload surface (REQ-A1.2, D-13): the
#     print rung's launch line and the tmux rung's worker argv carry no tier
#     flags at all, and the launch is the one shipped today;
#   - a configured tier reaching the launch as DISCRETE argv elements
#     (REQ-B1.2): `--model` and its value are separate arguments in the real
#     argv tmux receives, never a spliced command string;
#   - the audit row every dispatch leaves behind, including the one taken when
#     nothing is applied;
#   - degraded mode: an unreachable allocation store surfaces and launches at
#     the ambient tier rather than refusing to dispatch, and says so;
#   - the prose pin over the enumerated launch points (REQ-B1.1);
#   - the in-session rung's pinned inheritance being documented (REQ-B1.3);
#   - the manual remainder being enumerated by name in the test spec.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-launch-wiring.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
OD="$REPO_ROOT/scripts/offload-dispatch.sh"
LEDGER="$REPO_ROOT/scripts/allocation-ledger.sh"
CONTRACT="$REPO_ROOT/doctrine/backend-capability-contract.md"
TEST_SPEC="$REPO_ROOT/specs/model-allocation/test-spec.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

for f in "$OD" "$LEDGER" "$CONTRACT" "$TEST_SPEC"; do
  [ -e "$f" ] || fail "$f missing"
done

tmp=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
core_cfg="$tmp/core.yml"
stubbin="$tmp/stubbin"
mkdir -p "$fleet_home" "$repo/.claude" "$adopter_root" "$stubbin"
cp "$REPO_ROOT/config/defaults.yml" "$core_cfg" || fail "seeding the core config"

promptfile="$tmp/petition.txt"
printf 'Summarize the release notes.\n' >"$promptfile"

# A tmux stub that records the EXACT argv it was handed, one element per line,
# so "discrete argv elements" is asserted against real argument boundaries
# rather than against a rendered string.
# Appends rather than truncates: one dispatch invokes tmux more than once (the
# spawn, then the observe/attach hint probes), and a truncating stub would keep
# only the last call's argv — the one that carries nothing under test.
cat >"$stubbin/tmux" <<EOF || exit 1
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$tmp/tmux-argv"; done
echo '@7'
EOF
chmod +x "$stubbin/tmux"

# Each case reads only its own dispatch's argv.
reset_argv() { : >"$tmp/tmux-argv"; }
reset_argv

run_od() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$OD" "$@" 2>"$tmp/err"
}

rows_for() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$LEDGER" rows "$1"
}

set_knobs() {
  : >"$repo/.claude/planwright.yml"
  for l in "$@"; do printf '%s\n' "$l" >>"$repo/.claude/planwright.yml"; done
}

# argv_has_pair <flag> <value>: the flag and its value appear as ADJACENT,
# separate elements of the recorded argv. A spliced "--model opus" single
# argument fails this, which is the point.
argv_has_pair() {
  awk -v f="$1" -v v="$2" '
    $0 == f { seen = NR }
    seen && NR == seen + 1 && $0 == v { found = 1 }
    END { exit found ? 0 : 1 }' "$tmp/tmux-argv"
}

# --------------------------------------------------------------------------
# 1. Defaults only: /offload's print rung emits exactly today's launch line
#    (REQ-A1.2, D-13) and still leaves an audit row (REQ-B1.1).
# --------------------------------------------------------------------------
set_knobs
out=$(run_od dispatch print "$promptfile" --unit 'offload:d1') \
  || fail "print dispatch with defaults exited nonzero: $(cat "$tmp/err")"
launch=$(printf '%s\n' "$out" | sed -n 's/^launch\t//p')
[ "$launch" = "claude -- \"\$(cat -- '$promptfile')\"" ] \
  || fail "the defaults-only print launch changed; got: $launch"
[ "$(rows_for 'offload:d1' | awk 'END { print NR + 0 }')" = 1 ] \
  || fail "a defaults-only dispatch left no single audit row"
rows_for 'offload:d1' | grep -q 'inherit=full' \
  || fail "the defaults-only audit row does not record the inheritance"
ok "with defaults the offload print launch is unchanged and still audited"

# --------------------------------------------------------------------------
# 2. Defaults only: the tmux rung's worker argv carries no tier flags.
# --------------------------------------------------------------------------
reset_argv
out=$(run_od dispatch tmux "$promptfile" --unit 'offload:d2') \
  || fail "tmux dispatch with defaults exited nonzero: $(cat "$tmp/err")"
grep -qx -- '--model' "$tmp/tmux-argv" \
  && fail "a defaults-only tmux dispatch passed --model"
grep -qx -- '--effort' "$tmp/tmux-argv" \
  && fail "a defaults-only tmux dispatch passed --effort"
grep -qxF -- "$promptfile" "$tmp/tmux-argv" \
  || fail "the prompt-file path is missing from the worker argv"
ok "with defaults the offload tmux worker argv carries no tier flags"

# --------------------------------------------------------------------------
# 3. A configured tier reaches the launch as DISCRETE argv elements
#    (REQ-B1.2's argv-discipline clause), asserted on real argument
#    boundaries.
# --------------------------------------------------------------------------
set_knobs 'allocation_model_offload: sonnet' 'allocation_effort_offload: low'
reset_argv
out=$(run_od dispatch tmux "$promptfile" --unit 'offload:d3') \
  || fail "tmux dispatch with a configured tier exited nonzero: $(cat "$tmp/err")"
argv_has_pair '--model' sonnet \
  || fail "--model and its value are not adjacent discrete argv elements"
argv_has_pair '--effort' low \
  || fail "--effort and its value are not adjacent discrete argv elements"
# Nothing may arrive pre-joined into one argument.
grep -q -- '--model sonnet' "$tmp/tmux-argv" \
  && fail "the model flag reached the launch spliced into a single argument"
# The petition content still never travels on the command line.
grep -q 'Summarize the release notes' "$tmp/tmux-argv" \
  && fail "petition content was spliced into the worker argv"
ok "a configured tier reaches the tmux launch as discrete quoted argv elements"

# --------------------------------------------------------------------------
# 4. The print rung carries the same resolved tier into the command it hands
#    the operator — dropping it there would be a silent ambient launch by a
#    different route.
# --------------------------------------------------------------------------
out=$(run_od dispatch print "$promptfile" --unit 'offload:d4') \
  || fail "print dispatch with a configured tier exited nonzero"
launch=$(printf '%s\n' "$out" | sed -n 's/^launch\t//p')
case "$launch" in
  *"--model sonnet"*) ;;
  *) fail "the print rung dropped the resolved model: $launch" ;;
esac
case "$launch" in
  *"--effort low"*) ;;
  *) fail "the print rung dropped the resolved effort: $launch" ;;
esac
ok "the print rung carries the resolved tier into the command it hands over"

# --------------------------------------------------------------------------
# 5. Degraded mode: an unreachable allocation store does not refuse dispatch,
#    but it is never silent about launching at the ambient tier.
# --------------------------------------------------------------------------
# The knobs stay SET: with an empty config the launch would carry no tier
# whether or not the store were reachable, so the assertion below would hold
# vacuously. Configuring a tier first is what makes "the tier was dropped
# because it could not be recorded" a real claim.
set_knobs 'allocation_model_offload: sonnet' 'allocation_effort_offload: low'
rc=0
out=$(PATH="$stubbin:$PATH" \
  PLANWRIGHT_FLEET_STATE_DIR="" \
  CLAUDE_PLUGIN_DATA="" \
  CLAUDE_DIR="$tmp/no-such-claude-dir" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$OD" dispatch print "$promptfile" 2>"$tmp/err") || rc=$?
[ "$rc" = 0 ] || fail "an unreachable allocation store refused dispatch (exit $rc)"
grep -qi 'degraded' "$tmp/err" \
  || fail "the degraded launch was not surfaced"
launch=$(printf '%s\n' "$out" | sed -n 's/^launch\t//p')
case "$launch" in
  *--model* | *--effort*) fail "a degraded launch applied a tier it could not record" ;;
esac
ok "an unreachable allocation store degrades to an ambient launch and says so"

# --------------------------------------------------------------------------
# 6. The prose pin (REQ-B1.1): each launch point that constructs its launch in
#    SKILL prose names the resolver at the point it launches. Asserted per
#    file so a skill losing the step fails by name rather than in aggregate.
# --------------------------------------------------------------------------
pin_skill() {
  # $1 skill file, $2 the selection key that surface must resolve.
  # The key must appear on the SAME invocation as the helper: a bare `grep` for
  # either alone is satisfiable by prose that has lost the step (and for
  # `offload` the key is a word the file uses throughout), so the pin is the
  # `--key <key>` argument of an `allocation-apply.sh plan` call.
  ps_f="$REPO_ROOT/skills/$1/SKILL.md"
  [ -f "$ps_f" ] || fail "skills/$1/SKILL.md missing"
  # The invocation may wrap across lines, so join the file before matching.
  tr '\n' ' ' <"$ps_f" | grep -q "allocation-apply\.sh plan --key $2" \
    || fail "skills/$1/SKILL.md does not resolve key '$2' through allocation-apply.sh at its launch point"
}
pin_skill orchestrate orchestrate_dispatch
pin_skill execute-task execute_step
pin_skill offload offload
ok "every prose launch point names the apply layer and its own selection key"

# --------------------------------------------------------------------------
# 6b. Naming the resolver is not enough: the prose must also say what to do
#     with the answer's EXIT CODE. A withheld unit gets a well-formed plan
#     carrying `model inherit` / `effort inherit` and then exit 3, so prose
#     that describes only how to apply the plan reads as "apply nothing" and
#     launches the withheld unit at the ambient tier — the fail-open the shell
#     caller already refuses in offload-dispatch.sh. The two layers must not
#     disagree about one contract.
# --------------------------------------------------------------------------
pin_admit() {
  pa_f="$REPO_ROOT/skills/$1/SKILL.md"
  pa_j=$(tr '\n' ' ' <"$pa_f")
  # Scoped to the launch point, not the whole file: `/orchestrate` already says
  # "exit 3" about an unrelated selection hold, and a file-wide grep passes on
  # that while the launch point still says nothing.
  case $pa_j in
    *'allocation-apply.sh plan --key'*) ;;
    *) fail "skills/$1/SKILL.md has no apply invocation to scope the admit pin to" ;;
  esac
  pa_after=${pa_j#*allocation-apply.sh plan --key}
  # Lowercased: the clause opens a sentence at some surfaces and not others,
  # and the pin is about the contract being stated, not its capitalisation.
  pa_window=$(printf '%s\n' "${pa_after:0:400}" | tr '[:upper:]' '[:lower:]')
  case $pa_window in
    *'exit 3'*) ;;
    *) fail "skills/$1/SKILL.md does not name exit 3 at its launch point" ;;
  esac
  case $pa_window in
    *withheld*) ;;
    *) fail "skills/$1/SKILL.md names exit 3 at its launch point without saying the unit is withheld" ;;
  esac
}
pin_admit orchestrate
pin_admit execute-task
pin_admit offload
ok "every prose launch point names the withheld exit code and refuses to launch on it"

# --------------------------------------------------------------------------
# 6c. Reachability: the documented command is EXECUTED, not merely matched.
#     A prose contract nothing runs is how a stale invocation survives review,
#     so each skill's own invocation is lifted out of the file, its <...>
#     placeholders filled, and run against a withheld unit. The assertion is
#     the one the prose now promises: exit 3, and a plan that says withheld.
#     This is the shape used for the reachability pin on the sibling launch
#     contract; it works here because the admission gate answers before the
#     capability probe, so no real backend has to exist for the check.
# --------------------------------------------------------------------------
apply_env() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$@"
}
apply_env "$REPO_ROOT/scripts/fleet-audit.sh" record usage-gate defer-all seed \
  'seed the rung' >/dev/null 2>&1 || fail "seeding the defer-all rung failed"

reach_skill() {
  # Saved before the `set --` below rebinds the positionals out from under it.
  rs_skill=$1
  # Lift this skill's own invocation out of its prose (it may wrap across
  # lines, and it is delimited by the closing backtick of its code span).
  rs_cmd=$(tr '\n' ' ' <"$REPO_ROOT/skills/$rs_skill/SKILL.md" \
    | grep -o 'scripts/allocation-apply\.sh plan --key [^`]*' | head -1)
  [ -n "$rs_cmd" ] || fail "skills/$rs_skill/SKILL.md has no extractable apply invocation"
  # Fill every <placeholder> with a token legal in all three grammars, so what
  # runs is the documented command rather than a rewritten one.
  rs_cmd=$(printf '%s\n' "$rs_cmd" | sed 's/<[^<>]*>/u/g')
  case $rs_cmd in
    *'<'* | *'>'*) fail "skills/$rs_skill/SKILL.md left an unfilled placeholder: $rs_cmd" ;;
  esac
  # The gate withholds a configured tier; under the shipped `inherit` default
  # it has nothing to withhold and answers `yes`. So configure this surface's
  # own key first, or the case would pass for the wrong reason.
  rs_key=$(printf '%s\n' "$rs_cmd" | sed -n 's/.*--key \([a-z_][a-z_]*\).*/\1/p')
  [ -n "$rs_key" ] || fail "skills/$rs_skill/SKILL.md's invocation names no selection key"
  set_knobs "allocation_model_$rs_key: opus" "allocation_effort_$rs_key: high"
  # shellcheck disable=SC2086 # the lifted invocation is the argv under test
  set -- $rs_cmd
  shift
  rs_rc=0
  rs_out=$(apply_env "$REPO_ROOT/scripts/allocation-apply.sh" "$@" 2>"$tmp/err") || rs_rc=$?
  [ "$rs_rc" = 3 ] \
    || fail "skills/$rs_skill/SKILL.md's documented command exited $rs_rc on a withheld unit, expected 3: $rs_cmd"
  printf '%s\n' "$rs_out" | grep -q "^admit	withheld$" \
    || fail "skills/$rs_skill/SKILL.md's documented command did not report the unit withheld: $rs_out"
}
reach_skill orchestrate
reach_skill execute-task
reach_skill offload
apply_env "$REPO_ROOT/scripts/fleet-audit.sh" record usage-gate normal seed \
  'reset the rung' >/dev/null 2>&1 || fail "resetting the rung failed"
ok "each documented launch command runs and refuses a withheld unit with exit 3"

# --------------------------------------------------------------------------
# 7. REQ-B1.3: the in-session rung's inheritance is documented as its pinned
#    degradation — a content check, not mere existence.
# --------------------------------------------------------------------------
grep -q 'in-session' "$CONTRACT" \
  || fail "the capability contract does not name the in-session rung"
grep -qi 'pinned degradation' "$CONTRACT" \
  || fail "the in-session rung's inheritance is not called a pinned degradation"
grep -qi 'inherits the operator' "$CONTRACT" \
  || fail "the contract does not state that in-session work inherits the session's tier"
# ...and it advertises no tier control, so the doc and the registry agree.
[ "$(/bin/sh "$REPO_ROOT/scripts/orchestrate-backends.sh" caps in-session | awk '{ print $9 }')" = none ] \
  || fail "the in-session rung advertises a tier_control other than none"
ok "the in-session rung's inheritance is documented as its pinned degradation"

# --------------------------------------------------------------------------
# 8. REQ-B1.1's anti-silence clause: the non-scriptable remainder is
#    enumerated BY NAME in the test spec, so a surface can never be reclassified
#    as manual by omission.
# --------------------------------------------------------------------------
grep -q 'per-step session launch' "$TEST_SPEC" \
  || fail "the test spec does not enumerate the per-step session launch surface by name"
grep -q 'single-spec dispatch launch' "$TEST_SPEC" \
  || fail "the test spec does not enumerate the single-spec dispatch launch surface by name"
ok "the manual remainder is enumerated by name in the test spec"

echo "ALL PASS: allocation-launch-wiring"
