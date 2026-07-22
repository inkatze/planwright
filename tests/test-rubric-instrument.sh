#!/bin/bash
# Tests for the experiential-quality rubric instrument (operator-dialogue Task 6;
# REQ-H1.3, REQ-D1.1, REQ-D1.5, REQ-G1.4, D-11). Two runnable pieces implement
# the CDC Clear Communication Index + IPDAS balance rubrics over a kickoff run's
# durable artifacts:
#
#   - scripts/rubric-grade.sh — the INDEPENDENT grader form (the `--grader`
#     contract: prints pass/fail and exits 0, or exits non-zero when it cannot
#     grade). This is the experiential-quality instrument the non-Anthropic
#     grader applies, with the human as final rater (REQ-H1.3).
#   - scripts/rubric-self-audit.sh — the NON-SCORING diagnostic pre-pass a skill
#     MAY run on its own session (REQ-H1.3). It emits per-criterion observations
#     and a banner, but produces NO score of record: it never prints a pass/fail
#     verdict or a numeric score, so the independence firewall holds (a skill can
#     never grade its own session, REQ-G1.4).
#
# The two are DISTINCT roles that share the criteria: the grader scores, the
# self-audit only observes. These tests pin that split.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADE="$REPO_ROOT/scripts/rubric-grade.sh"
AUDIT="$REPO_ROOT/scripts/rubric-self-audit.sh"

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
assert_absent() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

for f in "$GRADE" "$AUDIT"; do
  [ -f "$f" ] || {
    echo "FAIL: required script missing at $f" >&2
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

# A well-formed merged artifacts object for a READY run that honors every
# rubric criterion: a shared-understanding summary naming the downstream effect,
# no lone percentage, a self-contained confirmation with an explicit reject and
# no pre-selected default, and no self-verdict on the spec.
GOOD="$TMP/good.json"
cat >"$GOOD" <<'JSON'
{
  "persona": "novice",
  "decision_log": [
    {"turn": 1, "kind": "explanation", "concept": "confirmation-rule", "normative_tokens": ["SHALL"], "text": "Each option SHALL restate its consequence."},
    {"turn": 3, "kind": "summary", "text": "Here is what you are about to approve; downstream, /execute-task builds from this brief."},
    {"turn": 4, "kind": "confirmation", "question": "Record your sign-off decision for this kickoff run.",
      "options": [
        {"label": "record-approval", "description": "record your approval; the design is accepted"},
        {"label": "record-rejection", "description": "record your rejection; nothing proceeds", "reject": true}
      ], "answer": "record-approval"}
  ],
  "sign_off": {"subject": "operator-dialogue-fixture", "ready": true, "blocked_on": [], "eval_only": true, "authoritative": false}
}
JSON

# A merged object that VIOLATES the rubric: a self-verdict in the summary, a lone
# percentage, and a confirmation with a pre-selected default and no reject.
BAD="$TMP/bad.json"
cat >"$BAD" <<'JSON'
{
  "persona": "novice",
  "decision_log": [
    {"turn": 3, "kind": "summary", "text": "This spec is good and has a 90% chance; I recommend approving it."},
    {"turn": 4, "kind": "confirmation", "question": "Approve?",
      "options": [
        {"label": "approve", "description": "approve", "default": true}
      ], "answer": "approve"}
  ],
  "sign_off": {"subject": "x", "ready": true, "blocked_on": [], "eval_only": true, "authoritative": false}
}
JSON

echo "== rubric-grade: the independent grader scores a compliant run pass =="
out="$(/bin/bash "$GRADE" "$GOOD" 2>&1)"
rc=$?
assert_exit "grading a compliant run exits 0" 0 "$rc"
assert_eq "a compliant run is graded pass" "pass" "$out"

echo "== rubric-grade: a correctly-blocked (not-ready) run is exempt, not failed =="
# A run that correctly HELD (a required decision left undefined) writes a
# ready:false sign-off with no summary/confirmation. The completion criteria
# (summary present, names downstream) must be exempt for it, not failed
# (REQ-C1.1) — otherwise the documented full-fixture grader run false-fails it.
BLOCKED="$TMP/blocked.json"
cat >"$BLOCKED" <<'JSON'
{
  "persona": "undefined",
  "decision_log": [
    {"turn": 1, "kind": "explanation", "normative_tokens": ["SHALL"], "text": "Each option SHALL restate its consequence."},
    {"turn": 2, "kind": "reprompt", "reason": "unparseable", "answer": "@@nope@@"}
  ],
  "sign_off": {"subject": "x", "ready": false, "blocked_on": ["design-decision"], "approved": false, "eval_only": true, "authoritative": false}
}
JSON
out="$(/bin/bash "$GRADE" "$BLOCKED" 2>&1)"
rc=$?
assert_exit "grading a blocked run exits 0" 0 "$rc"
assert_eq "a correctly-blocked run is graded pass (exempt from completion criteria)" "pass" "$out"

echo "== rubric-grade: a rubric-violating run is graded fail =="
out="$(/bin/bash "$GRADE" "$BAD" 2>&1)"
rc=$?
assert_exit "grading a violating run still exits 0 (a verdict, not an error)" 0 "$rc"
assert_eq "a violating run is graded fail" "fail" "$out"

echo "== rubric-grade: the reject check is per-confirmation, not any-confirmation =="
# Two confirmations, only the first balanced: a flattened any-reject check would
# pass; the per-confirmation rule (matching grade.jq) must FAIL it (REQ-E1.2).
MIXEDCONF="$TMP/mixedconf.json"
cat >"$MIXEDCONF" <<'JSON'
{
  "persona": "novice",
  "decision_log": [
    {"turn": 3, "kind": "summary", "text": "downstream effect noted."},
    {"turn": 4, "kind": "confirmation", "question": "First decision.",
      "options": [{"label": "record-a", "description": "x"}, {"label": "record-b", "description": "y", "reject": true}]},
    {"turn": 5, "kind": "confirmation", "question": "Second decision.",
      "options": [{"label": "record-c", "description": "z"}, {"label": "record-d", "description": "w"}]}
  ],
  "sign_off": {"subject": "x", "ready": true, "blocked_on": [], "eval_only": true, "authoritative": false}
}
JSON
out="$(/bin/bash "$GRADE" "$MIXEDCONF" 2>&1)"
assert_eq "a run whose second confirmation lacks a reject is graded fail" "fail" "$out"

echo "== rubric-grade: unparseable input is unavailable (non-zero -> degrade) =="
printf 'not json at all' >"$TMP/junk.json"
/bin/bash "$GRADE" "$TMP/junk.json" >/dev/null 2>&1
assert_exit "an ungradeable input exits non-zero so the harness degrades" 2 "$?"

echo "== rubric-self-audit: a diagnostic pre-pass that emits NO score of record =="
out="$(/bin/bash "$AUDIT" "$GOOD" 2>&1)"
rc=$?
assert_exit "the self-audit exits 0 (a diagnostic never gates the run)" 0 "$rc"
assert_contains "the self-audit is labeled diagnostic-only" "DIAGNOSTIC" "$out"
assert_contains "the self-audit names the CDC Clear Communication Index" "CDC" "$out"
assert_contains "the self-audit names the IPDAS balance criteria" "IPDAS" "$out"
# The firewall: the self-audit produces NO score of record — no pass/fail verdict
# and no numeric score. (Its diagnostic vocabulary deliberately avoids them.)
assert_absent "the self-audit prints no pass verdict" "pass" "$out"
assert_absent "the self-audit prints no fail verdict" "fail" "$out"
assert_absent "the self-audit prints no numeric score" "score=" "$out"

echo "== rubric-self-audit: it still surfaces per-criterion observations on a bad run =="
out="$(/bin/bash "$AUDIT" "$BAD" 2>&1)"
assert_exit "the self-audit exits 0 even when criteria are unmet" 0 "$?"
assert_contains "the self-audit flags the observed shortfall" "not met" "$out"

echo "== rubric-grade wired as the harness --grader over the real kickoff run =="
# End-to-end: the grader is the SAME instrument, applied by an independent id.
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
FIXTURE="$REPO_ROOT/tests/behavioral-evals/fixtures/kickoff"
STUB="$REPO_ROOT/tests/behavioral-evals/lib/tmux-stub.sh"
if [ -x "$RUNNER" ] && [ -f "$STUB" ]; then
  w="$TMP/e2e"
  mkdir -p "$w/wb" "$w/rec" "$w/state"
  out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$w/state" \
    BEHAVIORAL_EVAL_WORKBASE="$w/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
    /bin/sh "$RUNNER" --record "$w/rec" --persona novice \
    --grader "$GRADE" --grader-id ext-rubric-panel "$FIXTURE" 2>&1)"
  assert_exit "the rubric grader passes the real novice kickoff run" 0 "$?"
  assert_eq "the run is recorded as a pass under the rubric grader" "pass" "$(jq -r .outcome "$w/rec/kickoff.novice.json" 2>/dev/null)"
else
  echo "ok: harness/stub not present for the end-to-end wiring check (skipped)"
fi

if [ "$failures" -eq 0 ]; then
  echo "PASS: all rubric-instrument tests passed"
  exit 0
else
  echo "FAIL: $failures assertion(s) failed" >&2
  exit 1
fi
