#!/bin/bash
# Tests for the turn-shape invariants (operator-dialogue REQ-M1.1, REQ-M1.4,
# D-19, D-20): scripts/turn-shape-grade.sh, the stand-in fixtures under
# tests/behavioral-evals/turn-shape, and the harness's grading of them.
#
# Three lanes:
#   1. Every fixture, replayed directly, grades exactly as its conf expects.
#   2. Every invariant graded alone against both sides of its fixture pair:
#      it passes on the conforming fixture and fails on the wall, with the
#      thresholds held equal. Plus the sub-rules no wall covers, each made to
#      fail once by a one-field mutation of a conforming run.
#   3. End to end through scripts/behavioral-eval.sh under the stub tmux: the
#      harness runs every persona on every run and grades the turn records,
#      and a wall stripped of its expected failures turns the harness red.
#
# The eval itself stays on demand (the `eval:turn-shape` task, which
# check-no-ci-evals keeps out of CI); this file drives it hermetically through
# the stub, like the kickoff acceptance test.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADE="$REPO_ROOT/scripts/turn-shape-grade.sh"
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
SUITE="$REPO_ROOT/tests/behavioral-evals/turn-shape"
STUB="$REPO_ROOT/tests/behavioral-evals/lib/tmux-stub.sh"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)
      bad "$1 (missing '$2')"
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      ;;
  esac
}

for f in "$GRADE" "$RUNNER" "$STUB" "$SUITE/wall/fixture.conf"; do
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
trap 'rm -rf "$TMP"' EXIT

# replay <fixture> <persona> <artdir> — drive the fixture's skill with the
# persona's answers on stdin, exactly as the driver delivers them. Fails the
# test loudly when the replay does not complete, so a broken stand-in can
# never grade as an empty (and vacuously graded) run.
replay() {
  _fx="$SUITE/$1"
  mkdir -p "$3"
  awk -F= '/^answer\.[0-9]+=/ { n = substr($1, 8) + 0; a[n] = substr($0, index($0, "=") + 1); if (n > m) m = n }
    END { for (i = 1; i <= m; i++) if (i in a) print a[i] }' "$_fx/personas/$2.persona" >"$TMP/answers"
  if ! /bin/sh "$_fx/skill.sh" "$3" <"$TMP/answers" >"$TMP/pane" 2>"$TMP/replay.err"; then
    bad "$1/$2 replay exited non-zero: $(cat "$TMP/replay.err")"
    return 1
  fi
  if [ ! -s "$3/sign-off.json" ] || ! jq -se 'map(select(.kind == "turn")) | length > 0' "$3/decision-log.jsonl" >/dev/null 2>&1; then
    bad "$1/$2 replay wrote no run record or no turn records"
    return 1
  fi
  return 0
}

fixtures=""
for d in "$SUITE"/*/; do
  fixtures="$fixtures $(basename "$d")"
done

echo "== lane 1: every fixture grades as its conf expects, for every persona =="
for fx in $fixtures; do
  for persona in novice expert; do
    art="$TMP/l1/$fx.$persona"
    replay "$fx" "$persona" "$art" || continue
    out="$(/bin/sh "$GRADE" --conf "$SUITE/$fx/fixture.conf" "$art" 2>&1)"
    rc=$?
    assert_exit "$fx/$persona grades as expected" 0 "$rc"
    [ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2
  done
done

echo "== lane 2: each invariant alone, both sides of its fixture pair =="
# pair <invariant> <conforming> <wall> — the wall is graded with the
# conforming fixture's conf, so only the emitted turns differ.
pair() {
  _pass_art="$TMP/l2/$2"
  _wall_art="$TMP/l2/$3"
  [ -d "$_pass_art" ] || replay "$2" novice "$_pass_art" || return
  [ -d "$_wall_art" ] || replay "$3" novice "$_wall_art" || return
  out="$(/bin/sh "$GRADE" --conf "$SUITE/$2/fixture.conf" --invariants "$1" --expect-fail "" "$_pass_art" 2>&1)"
  assert_exit "$1 passes on $2" 0 "$?"
  out="$(/bin/sh "$GRADE" --conf "$SUITE/$2/fixture.conf" --invariants "$1" --expect-fail "" "$_wall_art" 2>&1)"
  assert_exit "$1 fails on $3" 1 "$?"
  assert_contains "$1 names itself as the failure on $3" "FAIL $1:" "$out"
  printf '  %s on %s -> %s\n' "$1" "$3" "$out"
}
pair no-table-dump projection wall
pair projection-present projection wall
pair decisions-first projection wall
pair decisions-first orchestrate-halts orchestrate-wall
pair step-report-slots orchestrate-halts orchestrate-wall
pair no-monotonic-growth kickoff-multiphase kickoff-wall
pair identifier-density kickoff-multiphase kickoff-wall
pair capture-at-birth kickoff-multiphase kickoff-wall
pair open-captures-list kickoff-multiphase kickoff-wall

# mutate <src-art> <dst-art> <jq filter over one log record> — copy a
# conforming run and rewrite its log record by record.
mutate() {
  rm -rf "$2"
  mkdir -p "$(dirname "$2")"
  cp -R "$1" "$2"
  jq -c "$3" "$1/decision-log.jsonl" >"$2/decision-log.jsonl"
}
# grade_one <invariant> <fixture-conf> <art> — grade one invariant alone.
grade_one() {
  /bin/sh "$GRADE" --conf "$SUITE/$2/fixture.conf" --invariants "$1" --expect-fail "" "$3" 2>&1
}

replay kickoff-resumed novice "$TMP/l2/kickoff-resumed"
mutate "$TMP/l2/kickoff-resumed" "$TMP/m/resume-replay" \
  'if .projection == "resume-confirmation" then .sections[1].text = "Requirements: signed 2026-09-20.\nGroups A to D walked, two decisions recorded." | .text = ([.sections[].text] | join("\n\n")) else . end'
out="$(grade_one no-monotonic-growth kickoff-resumed "$TMP/m/resume-replay")"
assert_exit "a resume confirmation replaying a section fails no-monotonic-growth" 1 "$?"
assert_contains "the resume failure says why" "more than one line" "$out"

mutate "$TMP/l2/kickoff-multiphase" "$TMP/m/declined" \
  'if .confirms == "readme-link" then del(.confirms) | .declines = "readme-link" else . end'
out="$(grade_one capture-at-birth kickoff-multiphase "$TMP/m/declined")"
assert_exit "a declined item that was still tracked fails capture-at-birth" 1 "$?"
assert_contains "the declined failure says why" "declined yet tracked" "$out"

mutate "$TMP/l2/kickoff-multiphase" "$TMP/m/unproposed" 'del(.captures)'
out="$(grade_one capture-at-birth kickoff-multiphase "$TMP/m/unproposed")"
assert_exit "a capture the skill never proposed fails capture-at-birth" 1 "$?"
assert_contains "the proposal failure says why" "without the skill first proposing" "$out"

mutate "$TMP/l2/projection" "$TMP/m/no-pointer" \
  'if .kind == "turn" then .sections |= map(select(.role != "bookkeeping")) | .text = ([.sections[].text] | join("\n\n")) else . end'
out="$(grade_one projection-present projection "$TMP/m/no-pointer")"
assert_exit "a projection that hides its pointer fails projection-present" 1 "$?"
assert_contains "the pointer failure says why" "never shows the operator its pointer" "$out"

mutate "$TMP/l2/projection" "$TMP/m/thin-record" '.'
printf 'Two findings applied.\n' >"$TMP/m/thin-record/audit-record.md"
out="$(grade_one projection-present projection "$TMP/m/thin-record")"
assert_exit "a full record thinner than the turn fails projection-present" 1 "$?"

echo "== the grader fails closed and never passes on nothing =="
mkdir -p "$TMP/empty"
out="$(/bin/sh "$GRADE" --conf "$SUITE/projection/fixture.conf" "$TMP/empty" 2>&1)"
assert_exit "an empty run fails every invariant" 1 "$?"
assert_contains "the empty run says there is nothing to grade" "no turn records to grade" "$out"
out="$(/bin/sh "$GRADE" --conf "$SUITE/wall/fixture.conf" "$TMP/empty" 2>&1)"
assert_exit "an empty run never satisfies a wall's expected failures" 1 "$?"
assert_contains "the vacuous expected failure is named" "expected, but nothing to grade" "$out"

out="$(/bin/sh "$GRADE" --conf "$SUITE/projection/fixture.conf" --invariants no-table-dump \
  --expect-fail no-table-dump "$TMP/l2/projection" 2>&1)"
assert_exit "an expected failure that passes is an error" 1 "$?"
assert_contains "the unexpected pass is named" "UNEXPECTED-PASS no-table-dump" "$out"

mutate "$TMP/l2/projection" "$TMP/m/v1-turn" 'if .kind == "turn" then .v = 1 else . end'
/bin/sh "$GRADE" --conf "$SUITE/projection/fixture.conf" "$TMP/m/v1-turn" >/dev/null 2>&1
assert_exit "a turn record off schema v2 is a schema error" 3 "$?"

printf 'id=bare\nturn_invariants=no-table-dump\n' >"$TMP/bare.conf"
/bin/sh "$GRADE" --conf "$TMP/bare.conf" "$TMP/l2/projection" >/dev/null 2>&1
assert_exit "a listed invariant without its fixture threshold is a config error" 2 "$?"
/bin/sh "$GRADE" --conf "$SUITE/projection/fixture.conf" --invariants bogus "$TMP/l2/projection" >/dev/null 2>&1
assert_exit "an unknown invariant is a usage error" 2 "$?"

echo "== lane 3: the harness grades fixtures, personas x runs =="
# Trimmed to fit the per-file test-time budget: the whole suite through the
# harness ran past it under load. Lane 1 still grades every fixture with the
# same grader and conf; only these four also run the harness path (stub TTY,
# runs, recording), which `mise run eval:turn-shape` covers for all of them.
lane3="projection wall kickoff-multiphase orchestrate-wall"
H="$TMP/h"
mkdir -p "$H/wb" "$H/rec" "$H/state"
set --
for fx in $lane3; do set -- "$@" "$SUITE/$fx"; done
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$H/state" \
  BEHAVIORAL_EVAL_WORKBASE="$H/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$H/rec" "$@" 2>&1)"
rc=$?
assert_exit "conforming fixtures and walls pass end to end" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2
assert_contains "the harness reports a wall's planted failure" "[wall/novice] turn-shape: FAIL no-table-dump (expected)" "$out"
expected_runs=0
for fx in $lane3; do
  runs="$(sed -n 's/^runs=//p' "$SUITE/$fx/fixture.conf")"
  n="$(sed -n 's/^personas=//p' "$SUITE/$fx/fixture.conf" | wc -w | tr -d ' ')"
  expected_runs=$((expected_runs + runs * n))
done
recorded="$(find "$H/rec" -name '*.json' | wc -l | tr -d ' ')"
if [ "$expected_runs" -gt 0 ]; then ok "the lane expects runs"; else bad "the lane expects no runs, so the count proves nothing"; fi
assert_exit "one recorded result per persona per run" "$expected_runs" "$recorded"
assert_exit "every recorded run passed its structural grade" 0 \
  "$(jq -s 'map(select(.structural_pass != true)) | length' "$H"/rec/*.json)"

# A wall without its expected failures must turn the harness red. The copy
# keeps the fixture's relative path to the shared stand-in.
mkdir -p "$TMP/red/suite"
ln -s "$REPO_ROOT/tests/behavioral-evals/lib" "$TMP/red/lib"
cp -R "$SUITE/wall" "$TMP/red/suite/wall"
sed -i.bak '/^turn_expect_fail=/d' "$TMP/red/suite/wall/fixture.conf"
rm -f "$TMP/red/suite/wall/fixture.conf.bak"
mkdir -p "$H/wb2" "$H/state2"
out="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$H/state2" \
  BEHAVIORAL_EVAL_WORKBASE="$H/wb2" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --persona novice "$TMP/red/suite/wall" 2>&1)"
assert_exit "an unexpected wall is a graded failure through the harness" 1 "$?"
assert_contains "the harness surfaces the failing invariant" "FAIL no-table-dump" "$out"

echo "== registration: on demand under eval:, never in check =="
MISE="$REPO_ROOT/mise.toml"
body="$(awk '/^\[tasks\."eval:turn-shape"\]/{f=1;next} /^\[/{f=0} f' "$MISE")"
assert_contains "eval:turn-shape runs the harness over the turn-shape suite" \
  "behavioral-eval.sh --suite tests/behavioral-evals/turn-shape" "$body"
/bin/sh "$REPO_ROOT/scripts/check-no-ci-evals.sh" >/dev/null 2>&1
assert_exit "check-no-ci-evals passes with the turn-shape eval registered" 0 "$?"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all turn-shape eval tests passed"
