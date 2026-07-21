#!/bin/bash
# Tests for the kickoff eval fixture and its measurable-acceptance invariants
# (operator-dialogue Task 6; REQ-H1.2, REQ-H1.4, REQ-C1.1, REQ-C1.2, REQ-C1.5,
# REQ-D1.1, REQ-B1.5, REQ-E1.1, REQ-F1.2, REQ-G1.2, D-11).
#
# Two lanes, both against the SAME kickoff eval fixture
# (tests/behavioral-evals/fixtures/kickoff):
#
#   1. END-TO-END through the real harness (scripts/behavioral-eval.sh) under a
#      STUB tmux — the same faithful double test-behavioral-eval.sh uses: it RUNS
#      the fixture skill, never re-implements it. This proves the persona-driven
#      run completes, is graded by an INDEPENDENT grader over the durable
#      artifacts (not the driver, not a scraped pane), and that the novice/expert
#      pilots produce a graded DIVERGENCE in explanation depth (REQ-H1.4).
#   2. DIRECT invocation of the fixture skill (feeding a persona's answers on
#      stdin, exactly the driver's delivery) for the fine-grained artifact
#      invariants: the self-contained confirmation graded by Task 2's
#      check-confirmation.sh (REQ-E1.1); absence of verdict tokens (REQ-D1.1);
#      verbatim normative-token preservation (REQ-B1.5); the summary emitted
#      before the confirmation (REQ-F1.2); completeness — no readiness while a
#      required decision is undefined, and readiness once supplied (REQ-C1.1);
#      the changed-answer-reopens-dependents path (REQ-C1.2); and input
#      robustness — malformed input re-prompts and leaves the calibration
#      estimate uncorrupted (REQ-C1.5).
#
# These are the on-demand behavioral lane made deterministic: the harness itself
# is never wired into CI (scripts/check-no-ci-evals.sh guards that); this test
# exercises the fixture + harness through the stub, so it is a normal, hermetic
# CI unit test — no real tmux, no model, no API key, no spend.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
CHECK_CONF="$REPO_ROOT/scripts/check-confirmation.sh"
FIXTURE="$REPO_ROOT/tests/behavioral-evals/fixtures/kickoff"
SKILL="$FIXTURE/skill.sh"

failures=0
assert_exit() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_gt() {
  if [ "$2" -gt "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected $2 > $3)" >&2
    failures=$((failures + 1))
  fi
}

for f in "$RUNNER" "$CHECK_CONF" "$SKILL"; do
  [ -f "$f" ] || {
    echo "FAIL: required file missing at $f" >&2
    exit 1
  }
done
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq required for these tests" >&2
  exit 1
}

TMP="$(mktemp -d)" || {
  echo "FAIL: mktemp -d failed" >&2
  exit 1
}
[ -n "$TMP" ] && [ -d "$TMP" ] || {
  echo "FAIL: mktemp -d produced no usable directory ('$TMP')" >&2
  exit 1
}
trap 'rm -rf "$TMP"' EXIT

# ---- feed_persona: extract answer.<N> lines in numeric order --------------
# The driver sends answer.<N> when it sees `EVAL-READY turn=<N>`; feeding those
# same answers in order on stdin reproduces the run's artifacts exactly (the
# skill's output is a pure function of its answer sequence). Awk keys on the
# `answer.<N>=` grammar and prints values by ascending N.
feed_persona() {
  awk -F= '
    /^answer\.[0-9]+=/ {
      n = substr($1, 8) + 0
      v = substr($0, index($0, "=") + 1)
      a[n] = v
      if (n > max) max = n
    }
    END { for (i = 1; i <= max; i++) if (i in a) print a[i] }
  ' "$1"
}

# run_skill <persona> <artdir> — drive the fixture skill directly with a
# persona's answers; artifacts land in <artdir>.
run_skill() {
  mkdir -p "$2"
  feed_persona "$FIXTURE/personas/$1.persona" | /bin/sh "$SKILL" "$2"
}

# =====================================================================
# Lane 1 — end-to-end through the harness under a stub tmux
# =====================================================================
# The stub is the shared faithful double (tests/behavioral-evals/lib/tmux-stub.sh):
# it backs each session with a state dir, renders the pane by RUNNING the real
# skill, replays accumulated answers on each C-m, and infers session death for the
# invalid-run path. It is a test double for tmux, never for the skill.
STUB="$REPO_ROOT/tests/behavioral-evals/lib/tmux-stub.sh"
[ -f "$STUB" ] || {
  echo "FAIL: shared tmux stub missing at $STUB" >&2
  exit 1
}

# An INDEPENDENT grader (a non-Anthropic mechanical stand-in) that records the
# pitched depth per persona and self-checks it received ONLY structured fixture
# artifacts — never pane text, never a driver/credential key (REQ-G1.3, REQ-G1.4,
# REQ-G1.6). A pass proves the grader graded the durable artifacts alone.
GRADER="$TMP/grader.sh"
cat >"$GRADER" <<GRADER_EOF
#!/bin/sh
merged="\$1"
jq -r '"\(.persona) depth=\(.sign_off.depth) ready=\(.sign_off.ready)"' "\$merged" >>"$TMP/observed.txt" 2>/dev/null
jq -e 'has("sign_off") and has("decision_log")' "\$merged" >/dev/null 2>&1 || { echo fail; exit 0; }
if jq -e 'has("credential") or has("token") or has("driver_id")' "\$merged" >/dev/null 2>&1; then echo fail; exit 0; fi
if grep -q "EVAL-READY" "\$merged" 2>/dev/null; then echo fail; exit 0; fi
echo pass
GRADER_EOF
chmod +x "$GRADER"
rm -f "$TMP/observed.txt"

MAIN="$TMP/main"
mkdir -p "$MAIN/wb" "$MAIN/rec" "$MAIN/state"
mainout="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$MAIN/state" \
  BEHAVIORAL_EVAL_WORKBASE="$MAIN/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$MAIN/rec" --grader "$GRADER" --grader-id ext-rubric-panel "$FIXTURE" 2>&1)"
mainrc=$?

echo "== end-to-end: the persona-driven kickoff run completes and is graded =="
assert_exit "every persona completes end-to-end through the harness" 0 "$mainrc"
assert_contains "an outcome is reported per persona" "outcome=" "$mainout"
assert_eq "the novice run's structural invariants pass" "true" "$(jq -r .structural_pass "$MAIN/rec/kickoff.novice.json" 2>/dev/null)"
assert_eq "the expert run's structural invariants pass" "true" "$(jq -r .structural_pass "$MAIN/rec/kickoff.expert.json" 2>/dev/null)"
assert_eq "the undefined (blocked) run's structural invariants still pass" "true" "$(jq -r .structural_pass "$MAIN/rec/kickoff.undefined.json" 2>/dev/null)"
assert_eq "the independent grader (not the driver) scored the run" "ext-rubric-panel" "$(jq -r .grader_id "$MAIN/rec/kickoff.novice.json" 2>/dev/null)"

echo "== persona pilots: a graded divergence in explanation depth (REQ-H1.4) =="
obs="$(cat "$TMP/observed.txt" 2>/dev/null)"
assert_contains "the novice was pitched at full depth" "novice depth=full" "$obs"
assert_contains "the expert was pitched at brief depth" "expert depth=brief" "$obs"

# =====================================================================
# Lane 2 — direct invocation: the fine-grained artifact invariants
# =====================================================================

echo "== REQ-E1.1/H1.2: the sign-off confirmation is self-contained =="
A_NOV="$TMP/nov"
run_skill novice "$A_NOV" >/dev/null 2>&1
jq -cs '[.[] | select(.kind == "confirmation") | {question, options}]' "$A_NOV/decision-log.jsonl" >"$TMP/conf.json"
confcount="$(jq 'length' "$TMP/conf.json" 2>/dev/null)"
assert_gt "the run emitted a structured confirmation to grade" "$confcount" 0
/bin/bash "$CHECK_CONF" "$TMP/conf.json" >"$TMP/conf.out" 2>&1
assert_exit "Task 2's check-confirmation passes the kickoff confirmation" 0 "$?"

echo "== REQ-D1.1/H1.2: no verdict tokens in the run's durable output =="
corpus="$(jq -r '[.text // empty, .question // empty, ((.options // [])[] | .description // empty), ((.options // [])[] | .label // empty)] | join(" ")' "$A_NOV/decision-log.jsonl" | tr '[:upper:]' '[:lower:]')"
for v in "this spec is good" "ready-quality" "i recommend approv" "quality score" "strong spec"; do
  case "$corpus" in
    *"$v"*)
      echo "FAIL: a verdict token leaked into the durable output ('$v')" >&2
      failures=$((failures + 1))
      ;;
    *) : ;;
  esac
done
echo "ok: no verdict token appears in the durable output"

echo "== REQ-B1.5/H1.2: normative tokens preserved verbatim in explanations =="
badnorm="$(jq -r '
  select(.kind == "explanation")
  | . as $e
  | (.normative_tokens // [])[]
  | select($e.text | contains(.) | not)
' "$A_NOV/decision-log.jsonl" 2>/dev/null)"
assert_eq "every recorded normative token appears verbatim in its explanation" "" "$badnorm"

echo "== REQ-F1.2: the shared-understanding summary is emitted BEFORE the decision =="
summ_turn="$(jq -s 'map(select(.kind == "summary") | .turn) | min // empty' "$A_NOV/decision-log.jsonl")"
conf_turn="$(jq -s 'map(select(.kind == "confirmation") | .turn) | min // empty' "$A_NOV/decision-log.jsonl")"
assert_gt "the confirmation turn follows the summary turn" "$conf_turn" "$summ_turn"
assert_eq "the sign-off records the summary-before-confirmation ordering" "true" "$(jq -r .summary_before_confirmation "$A_NOV/sign-off.json")"

echo "== REQ-C1.1: completeness — no readiness while a required decision is undefined =="
A_UND="$TMP/und"
run_skill undefined "$A_UND" >/dev/null 2>&1
assert_eq "an undefined required decision does NOT declare readiness" "false" "$(jq -r .ready "$A_UND/sign-off.json")"
assert_eq "the blocker is recorded so the hold is legible" "design-decision" "$(jq -r '.blocked_on[0]' "$A_UND/sign-off.json")"
assert_eq "the blocked run reaches no confirmation" "0" "$(jq -s '[.[] | select(.kind == "confirmation")] | length' "$A_UND/decision-log.jsonl")"
# supplying the decision lets it proceed to readiness
assert_eq "supplying the decision (novice) reaches readiness" "true" "$(jq -r .ready "$A_NOV/sign-off.json")"

echo "== REQ-C1.2: a changed upstream answer reopens the dependent decision =="
A_REO="$TMP/reo"
run_skill reopen "$A_REO" >/dev/null 2>&1
assert_gt "a reopen event is recorded" "$(jq -s '[.[] | select(.kind == "reopen")] | length' "$A_REO/decision-log.jsonl")" 0
assert_eq "the reopened decision is re-asked, not left stale" "1" "$(jq -s '[.[] | select(.kind == "question" and .concept == "decision-reopened")] | length' "$A_REO/decision-log.jsonl")"
# the final sign-off reflects the NEW answers (expert level, beta decision), not
# the stale ones (novice, alpha).
assert_eq "the sign-off carries the changed upstream level" "expert" "$(jq -r .level "$A_REO/sign-off.json")"
assert_eq "the sign-off carries the reopened decision, not the stale one" "option-beta" "$(jq -r .decision "$A_REO/sign-off.json")"
assert_eq "the reopened flag is set" "true" "$(jq -r .reopened "$A_REO/sign-off.json")"

echo "== REQ-C1.5: malformed input re-prompts and does not corrupt calibration =="
A_MAL="$TMP/mal"
run_skill malformed "$A_MAL" >/dev/null 2>&1
assert_gt "a re-prompt is recorded on unparseable input" "$(jq -s '[.[] | select(.kind == "reprompt")] | length' "$A_MAL/decision-log.jsonl")" 0
assert_eq "the malformed run still reaches readiness after a valid retry" "true" "$(jq -r .ready "$A_MAL/sign-off.json")"
# the calibration estimate recorded on the reprompt equals the estimate recorded
# on the level turn immediately before it: the garbage did not move it.
cal_before="$(jq -s 'map(select(.kind == "question" and .concept == "level") | .calibration) | first' "$A_MAL/decision-log.jsonl")"
cal_reprompt="$(jq -s 'map(select(.kind == "reprompt") | .calibration) | first' "$A_MAL/decision-log.jsonl")"
assert_eq "the calibration estimate is unchanged by the malformed input" "$cal_before" "$cal_reprompt"

echo "== REQ-H1.4/B1.3: novice vs expert pilots diverge, and scaffolding fades =="
A_EXP="$TMP/exp"
run_skill expert "$A_EXP" >/dev/null 2>&1
# Divergence — genuine: the expertise signal flips the base depth full->brief.
nov_s1="$(jq -r '.sections[0].chars' "$A_NOV/sign-off.json")"
exp_s1="$(jq -r '.sections[0].chars' "$A_EXP/sign-off.json")"
assert_gt "the novice section-1 explanation is longer than the expert's" "$nov_s1" "$exp_s1"
# Fade — a COMPUTED decision from run state, not a per-concept string artifact:
# the novice's base level is full, yet section 2 is pitched brief because the
# scaffold faded after section 1. Assert the decision (depth + faded), so a
# regression that deleted the fade logic (leaving section 2 at the base full
# depth) is caught — not just a fixed length difference between two strings.
assert_eq "the novice's first section is at the base (full) depth" "full" "$(jq -r '.sections[0].depth' "$A_NOV/sign-off.json")"
assert_eq "the novice's first section is not faded" "false" "$(jq -r '.sections[0].faded' "$A_NOV/sign-off.json")"
assert_eq "scaffolding fades: the novice's later section drops to brief" "brief" "$(jq -r '.sections[1].depth' "$A_NOV/sign-off.json")"
assert_eq "the later section is marked faded" "true" "$(jq -r '.sections[1].faded' "$A_NOV/sign-off.json")"

echo "== grade.jq floor rejects a non-self-contained confirmation (REQ-E1.1/E1.2) =="
# A ready run whose confirmation carries a pre-selected default and no explicit
# reject must FAIL the structural floor — existence of a confirmation is not
# enough; its self-contained structure is the invariant.
GRADEJQ="$FIXTURE/grade.jq"
printf '%s' '{"persona":"x","decision_log":[{"turn":1,"kind":"explanation","normative_tokens":["SHALL"],"text":"x SHALL y"},{"turn":3,"kind":"summary","text":"downstream ..."},{"turn":4,"kind":"confirmation","question":"Record your decision.","options":[{"label":"record-approval","description":"ok","default":true}]}],"sign_off":{"ready":true,"blocked_on":[],"approved":true,"decision":"option-alpha","summary_before_confirmation":true,"calibration":2,"eval_only":true,"authoritative":false,"normative_tokens_presented":["SHALL"]}}' \
  | jq -e -f "$GRADEJQ" >/dev/null 2>&1
assert_exit "grade.jq rejects a defaulted / reject-less confirmation" 1 "$?"

echo "== the rubric grader over the FULL fixture: the blocked persona is exempt, not failed =="
# The documented on-demand usage runs the whole fixture (all personas). The
# undefined persona correctly HOLDS (ready:false); the experiential rubric must
# exempt it from the completion criteria rather than false-fail it (REQ-C1.1).
RG="$REPO_ROOT/scripts/rubric-grade.sh"
w="$TMP/rgfull"
mkdir -p "$w/wb" "$w/rec" "$w/state"
rgout="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$w/state" \
  BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$w/rec" --grader "$RG" --grader-id ext-rubric-panel "$FIXTURE" 2>&1)"
assert_exit "the whole fixture (incl. the blocked undefined persona) passes the rubric grader" 0 "$?"
assert_contains "the rubric-graded run reports an outcome per persona" "outcome=" "$rgout"
assert_eq "the blocked undefined run is graded pass, not a false-fail" "pass" "$(jq -r .outcome "$w/rec/kickoff.undefined.json" 2>/dev/null)"

if [ "$failures" -eq 0 ]; then
  echo "PASS: all kickoff-acceptance tests passed"
  exit 0
else
  echo "FAIL: $failures assertion(s) failed" >&2
  exit 1
fi
