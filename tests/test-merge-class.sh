#!/bin/bash
# Suite for scripts/merge-class.sh: one case per predicate of the policy class
# (human-gates REQ-D1.3, REQ-D1.8, REQ-D1.9), run under the scenario titles of
# tests/fixtures/merge-class.feature, plus the evidence record, the single CI
# wait, and the identity detector (REQ-D1.7).
#
# Hermetic: tests/lib/merge-policy-fixture.sh builds a throwaway origin and a
# unit clone, and a stub gh answers from files. Nothing reaches a real host.
unset CDPATH
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLASS="$REPO_ROOT/scripts/merge-class.sh"
FEATURE="$REPO_ROOT/tests/fixtures/merge-class.feature"

failures=0
passes=0
pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
check() { # <label> <command...>
  local label=$1
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}
not() { ! "$@"; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/merge-class.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
# shellcheck source=tests/lib/merge-policy-fixture.sh
. "$REPO_ROOT/tests/lib/merge-policy-fixture.sh"

if [ ! -f "$CLASS" ]; then
  fail "the evaluator exists at scripts/merge-class.sh"
  echo "merge-class: $passes passed, $failures failed" >&2
  exit 1
fi

RAN=''
scenario() { # <title> — a case heading the feature file names
  echo "# Scenario: $1"
  RAN="$RAN<$1>"
}

REC="$SANDBOX/record"
evaluate() {
  rm -f "$REC"
  mp_run "$CLASS" evaluate --spec specs/demo --task 1 --out "$REC"
}
pred() { # <name> <result>
  grep -q "^pred	$1	$2	" "$REC" 2>/dev/null
}
admitted_fixture() { # [<awaiting-input lines on main>...]
  mp_fixture "$@"
  mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'ready_flip_ci_wait: 30s'
}

mp_fixture
MP_TEMPLATE=$F

scenario 'every predicate holds'
admitted_fixture
evaluate
check "an admitted PR exits 0" [ "$CODE" = 0 ]
for p in branch sign-off core-zone excluded-paths max-lines strategy awaiting-input review-converged ci-rollup ready-guard; do
  check "the record carries a passing $p row" pred "$p" pass
done
check "the record names the head" grep -q "^head	$(gitf rev-parse HEAD)$" "$REC"
check "the record names the base and its OID" grep -q "^base	main	$(git --git-dir="$F/origin.git" rev-parse main)$" "$REC"
check "the record names the PR" grep -q '^pr	42$' "$REC"
check "the record names the resolved strategy" grep -q '^strategy	squash$' "$REC"
check "evaluation never merges, flips, or comments" [ "$(($(mp_calls 'pr merge') + $(mp_calls 'pr ready') + $(mp_calls 'pr comment')))" = 0 ]
check "one CI wait: the rollup was read once with the checks green" [ "$(mp_calls 'pr view 42 --json headRefOid,statusCheckRollup')" = 1 ]
mp_run "$CLASS" evaluate --spec specs/demo --task 1
check "with no --out the record goes to stdout" grep -q '^pred	branch	pass' <<<"$OUT"

scenario 'branch - the head is not a task branch'
for h in release-please--branches--main dependabot/npm_and_yarn/lodash-4.17.21 planwright/flight/fix-typo-0a1b2c3d planwright/demo/spec planwright/a/b/task-1; do
  admitted_fixture
  printf '%s\n' "$h" >"$GHS/head_name"
  evaluate
  check "head $h falls to on-approval (exit 4)" [ "$CODE" = 4 ]
  check "head $h fails the branch predicate" pred branch fail
  check "head $h costs no CI wait" [ "$(mp_calls 'pr view 42 --json headRefOid,statusCheckRollup')" = 0 ]
done
admitted_fixture
printf 'release-please--branches--main\n' >"$GHS/head_name"
printf '%s\n' 'merge_policy: policy-class' 'merge_class_max_lines: 100000' 'merge_class_exclude_paths:' >"$F/wt/.claude/planwright.local.yml"
evaluate
check "no bound or layer widens the branch set" [ "$CODE" = 4 ]

scenario 'branch - a task-shaped branch from a fork'
admitted_fixture
: >"$GHS/fork"
evaluate
check "a fork falls to on-approval (exit 4)" [ "$CODE" = 4 ]
check "a fork fails the branch predicate" pred branch fail
check "the evidence names the fork" grep -q 'branch	fail	.*another repository' "$REC"
admitted_fixture
printf 'release-please--branches--main\n' >"$GHS/head_name"
echo 0123456789abcdef0123456789abcdef01234567 >"$GHS/head_override"
evaluate
check "a failed branch predicate records the PR's own head, not the checkout's" grep -q '^head	0123456789abcdef0123456789abcdef01234567$' "$REC"
for p in sign-off core-zone excluded-paths max-lines strategy awaiting-input; do
  check "a failed branch predicate skips $p rather than judge the checkout" pred "$p" skip
done

scenario 'sign-off - a trailer in the range, reverted'
admitted_fixture
mp_commit "$(printf 'fix: a finding\n\nPlanwright-Sign-Off: PS-1')" fix.txt one
signed=$(gitf rev-parse HEAD)
gitf revert --no-edit "$signed" >/dev/null 2>&1
gitf push -q origin "$MP_BRANCH" 2>/dev/null
mp_record_review
evaluate
check "a reverted sign-off commit still refuses (exit 4)" [ "$CODE" = 4 ]
check "the sign-off predicate fails" pred sign-off fail
check "the evidence names the trailered commit" grep -q "sign-off	fail	.*${signed:0:7}" "$REC"
mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100000'
evaluate
check "a sign-off item refuses under the widest bound too" pred sign-off fail
admitted_fixture
mp_commit "$(printf 'fix: a finding\n\nPlanwright-Sign-Off: PS-1')" fix.txt one
mp_commit "$(printf 'revert: drop it\n\nPlanwright-Sign-Off-Rejected: PS-1')" fix.txt two
evaluate
check "a rejected trailer does not clear the raw scan" pred sign-off fail

scenario 'sign-off - a legacy suffixed commit'
admitted_fixture
mp_commit 'fix: a finding [pending-sign-off]' fix.txt one
evaluate
check "a legacy suffix refuses (exit 4)" [ "$CODE" = 4 ]
check "the legacy suffix fails the sign-off predicate" pred sign-off fail
gitf revert --no-edit HEAD >/dev/null 2>&1
gitf push -q origin "$MP_BRANCH" 2>/dev/null
mp_record_review
evaluate
check "a reverted legacy commit still refuses" pred sign-off fail
admitted_fixture
mp_commit 'fix: mention [pending-sign-off] in the middle' fix.txt one
evaluate
check "the marker mid-subject is not a legacy commit" pred sign-off pass

scenario 'core-zone - a path the core zone holds'
for p in hooks/hooks.json config/worker-settings.json scripts/policy-guard.sh scripts/merge-admitted.sh \
  .github/workflows/ci.yml doctrine/human-gates.md tests/fixtures/reserved-control-spellings \
  package-lock.json web/yarn.lock .claude/planwright.yml mise.toml config/defaults.yml scripts/resolve-root.sh; do
  admitted_fixture
  mp_commit 'chore: touch the zone' "$p" x
  evaluate
  check "a change to $p fails the core-zone predicate" pred core-zone fail
  check "a change to $p falls to on-approval (exit 4)" [ "$CODE" = 4 ]
done
admitted_fixture
mp_commit 'chore: touch the zone' hooks/x.sh x
printf '%s\n' 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'merge_class_exclude_paths:' >"$F/wt/.claude/planwright.local.yml"
evaluate
check "an empty exclude list does not shrink the core zone" pred core-zone fail

scenario 'excluded-paths - a path the adopter excludes'
admitted_fixture
mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'merge_class_exclude_paths: docs/*'
mp_commit 'docs: a page' docs/x.md x
evaluate
check "an adopter-excluded path falls to on-approval (exit 4)" [ "$CODE" = 4 ]
check "the excluded-paths predicate fails" pred excluded-paths fail
check "the core zone is not blamed for it" pred core-zone pass

scenario 'max-lines - over the bound, or the bound at 0'
admitted_fixture
mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 2'
mp_commit 'feat: more' big.txt "$(printf 'a\nb\nc\nd')"
evaluate
check "a change over the bound fails max-lines" pred max-lines fail
admitted_fixture
mp_policy 'merge_policy: policy-class'
evaluate
check "the default bound of 0 admits nothing" pred max-lines fail
check "the evidence says the class is closed" grep -q 'max-lines	fail	merge_class_max_lines is 0, so the class admits nothing' "$REC"
admitted_fixture
mp_policy 'merge_policy: policy-class'
chmod +x "$F/wt/feature.txt"
gitf commit -q -am 'chore: a mode change, no lines'
gitf push -q origin "$MP_BRANCH" 2>/dev/null
mp_record_review
evaluate
check "a change of zero lines is still refused at the bound of 0" pred max-lines fail

scenario 'strategy - no single allowed method'
admitted_fixture
echo 'merge squash' >"$GHS/methods"
evaluate
check "several methods under sole-allowed fail the strategy" pred strategy fail
admitted_fixture
mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'merge_class_strategy: squash'
echo 'merge squash' >"$GHS/methods"
evaluate
check "an explicit allowed method passes among several" pred strategy pass
check "the record names the explicit method" grep -q '^strategy	squash$' "$REC"
admitted_fixture
mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'merge_class_strategy: rebase'
evaluate
check "a named method the host disallows fails the strategy" pred strategy fail
admitted_fixture
echo 1 >"$GHS/repo_rc"
evaluate
check "a failed host query fails the strategy" pred strategy fail
check "the evidence names the failed query" grep -qi 'strategy	fail	.*could not' "$REC"
admitted_fixture
echo 'merge' >"$GHS/methods"
evaluate
check "a single allowed merge method is used" grep -q '^strategy	merge$' "$REC"

scenario 'awaiting-input - a human park on the base'
admitted_fixture '- **Task 1** — which way should the flag go?'
evaluate
check "a base park refuses (exit 4)" [ "$CODE" = 4 ]
check "the awaiting-input predicate fails" pred awaiting-input fail

scenario 'awaiting-input - only the ready-flip parking lead'
admitted_fixture '- **Task 1** — pending ready-flip: ci-rollup failed on 0123456789ab'
evaluate
check "a parking lead alone does not block (exit 0)" [ "$CODE" = 0 ]
check "the awaiting-input predicate holds" pred awaiting-input pass

scenario 'ci-rollup - the head is not green'
admitted_fixture
echo failing >"$GHS/ci"
evaluate
check "a red rollup refuses (exit 4)" [ "$CODE" = 4 ]
check "the ci-rollup predicate fails" pred ci-rollup fail

scenario 'review-converged - commits after the reviewed head'
admitted_fixture
printf 'more\n' >"$F/wt/more.txt"
gitf add more.txt
gitf commit -q -m 'feat: unreviewed'
gitf push -q origin "$MP_BRANCH" 2>/dev/null
evaluate
check "an unreviewed head refuses (exit 4)" [ "$CODE" = 4 ]
check "the review-converged predicate fails" pred review-converged fail

scenario 'ready-guard - the head is behind its base'
admitted_fixture
echo 3 >"$GHS/behind"
evaluate
check "a behind head refuses (exit 4)" [ "$CODE" = 4 ]
check "the ready-guard predicate fails" pred ready-guard fail

echo "# exactly one failing predicate is the only fail row"
admitted_fixture
echo 'merge squash' >"$GHS/methods"
evaluate
check "only the strategy row fails" [ "$(grep -c '^pred	[^	]*	fail	' "$REC")" = 1 ]
check "a cheap failure skips the CI wait" pred ci-rollup skip

echo "# skips and refusals"
admitted_fixture
: >"$GHS/nopr"
evaluate
check "no PR skips cleanly (exit 3)" [ "$CODE" = 3 ]
admitted_fixture
gitf checkout -q main
evaluate
check "a checkout off a task branch is refused (exit 5)" [ "$CODE" = 5 ]
admitted_fixture
mp_run "$CLASS" evaluate --spec specs/demo --task '1;x'
check "a malformed task id is a usage error (exit 2)" [ "$CODE" = 2 ]
admitted_fixture
mp_run "$CLASS" evaluate --spec specs/demo --task 2
check "a task the branch does not name is refused (exit 5)" [ "$CODE" = 5 ]
mkdir -p "$F/wt/specs/other"
cp "$F/wt/$MP_TASKS" "$F/wt/specs/other/tasks.md"
mp_run "$CLASS" evaluate --spec specs/other --task 1
check "a spec the branch does not name is refused (exit 5)" [ "$CODE" = 5 ]
admitted_fixture
gitf checkout -q -b planwright/demo/task-3.2-3.10
for ok in 3.5 3.10 3.2; do
  mp_run "$CLASS" evaluate --spec specs/demo --task "$ok"
  check "task $ok is inside the bundle range 3.2-3.10" not grep -q 'is not the unit the branch names' <<<"$OUT"
done
for bad in 3.25 4 3.1 3.11; do
  mp_run "$CLASS" evaluate --spec specs/demo --task "$bad"
  check "task $bad is outside the bundle range 3.2-3.10" grep -q 'is not the unit the branch names' <<<"$OUT"
done
admitted_fixture
echo 2 >"$GHS/lookup_fail_from"
evaluate
check "a ready-flip evaluation that refuses is a refusal, never a fall-through (exit 5)" [ "$CODE" = 5 ]
check "a refusal writes no record" [ ! -s "$REC" ]
admitted_fixture
gitf remote set-url origin "$F/nowhere.git"
evaluate
check "a base that cannot be fetched refuses (exit 5), never a stale ref" [ "$CODE" = 5 ]

echo "# identity: detected, never required"
admitted_fixture
mp_run "$CLASS" identity --pr 42
check "a shared identity still runs (exit 0)" [ "$CODE" = 0 ]
check "a shared identity names the auto-merge act" grep -q '^act	enable-auto-merge$' <<<"$OUT"
check "a shared identity names no approving-review act" not grep -q 'approving-review' <<<"$OUT"
echo agent-bot >"$GHS/login"
mp_run "$CLASS" identity --pr 42
check "a split identity names the auto-merge act" grep -q '^act	enable-auto-merge$' <<<"$OUT"
check "a split identity adds the approving-review act" grep -q '^act	approving-review-with-auto-merge$' <<<"$OUT"

echo "# no model in the decision path"
check "the evaluator calls no model or dispatch backend" not grep -Eq '(^|[^[:alnum:]_./-])(claude|anthropic|offload-dispatch)([^[:alnum:]_-]|$)' "$CLASS"

echo "# every scenario of the feature file ran"
titles=$(sed -n 's/^  Scenario: //p' "$FEATURE" | wc -l | tr -d ' ')
check "the feature file names scenarios, so the loop below checks something" [ "$titles" -gt 0 ]
check "every scenario run is in the feature file, and the counts agree" [ "$titles" = "$(printf '%s' "$RAN" | tr -cd '<' | wc -c | tr -d ' ')" ]
while IFS= read -r title; do
  case $RAN in
    *"<$title>"*) pass "scenario ran: $title" ;;
    *) fail "the feature file's scenario has no case: $title" ;;
  esac
done < <(sed -n 's/^  Scenario: //p' "$FEATURE")

echo "merge-class: $passes passed, $failures failed"
[ "$failures" = 0 ]
