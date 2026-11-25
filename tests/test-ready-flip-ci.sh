#!/bin/bash
# Suite for scripts/ready-flip.sh: the ci-rollup precondition (the wait, an
# empty rollup, transient failures, own contexts), the ready-guard as the
# currency floor, and the record write and the flip call.
#
# Hermetic: each case builds a throwaway origin (a bare repository) and a unit
# clone on a task branch, and a stub `gh` answers from files, reporting the
# PR head as whatever the bare origin holds for the branch, so a park or
# unpark push moves the "PR head" the way GitHub would. Nothing here reaches a
# real host.
# shellcheck disable=SC2119 # fixture takes optional arguments of its own, never the script's
unset CDPATH
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$REPO_ROOT/scripts/ready-flip.sh"
STEP_RECORD="$REPO_ROOT/scripts/step-record.sh"

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

# shellcheck source=tests/lib/ready-flip-fixture.sh
. "$REPO_ROOT/tests/lib/ready-flip-fixture.sh"

echo "# CI: pending past the wait, an empty rollup, transient failures, own contexts"
fixture
set_policy unit-owner
echo pending >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a rollup still pending at the bound parks (exit 4)" [ "$CODE" = 4 ]
check "the wait polled to its bound" [ "$(rollups)" = 3 ]
fixture
set_policy unit-owner
echo pending-macos >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a queued macOS shard keeps the flip parked (exit 4)" [ "$CODE" = 4 ]
check "the flip is not made over a queued macOS shard" [ "$(calls 'pr ready')" = 0 ]
fixture
set_policy unit-owner
echo pending-macos >"$GHS/ci"
handp="$SANDBOX/handp-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$handp"
check "the evaluation names the pending macOS shard" grep -q 'macos-suite (shard 2/4)' "$handp"
fixture
set_policy unit-owner
echo none >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "an empty rollup is not green (exit 4)" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo 2 >"$GHS/rollup_fail_until"
run_helper flip --spec specs/demo --task 1
check "a transient host failure inside the wait is retried, then flips" [ "$CODE" = 0 ]
check "the failed reads were retried" [ "$(rollups)" = 4 ]
fixture
set_policy unit-owner
echo 9 >"$GHS/rollup_fail_until"
run_helper flip --spec specs/demo --task 1
check "a host failure past the wait counts as a failed precondition (exit 4)" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo own-status-red >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "the planwright point statuses are excluded from the rollup judgement" [ "$CODE" = 0 ]
fixture
set_policy unit-owner
echo own-status-only >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a point status alone is no positive green" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo own-name-checkrun-red >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a check run named like a point status is judged, not excluded" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo superseded-red >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a failed run superseded by a passing re-run of its check is green, the newer listed first" [ "$CODE" = 0 ]
fixture
set_policy unit-owner
echo superseded-red-first >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "and with the older failure listed first" [ "$CODE" = 0 ]
fixture
set_policy unit-owner
echo superseded-red >"$GHS/ci"
run_helper evaluate --spec specs/demo --task 1
check "the green count is one per check context, not per run" grep -q 'ci-rollup	pass	1 check(s) green' <<<"$OUT"
fixture
set_policy unit-owner
echo window-lock-red >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a red window-lock beside green checks never holds the flip" [ "$CODE" = 0 ]
fixture
set_policy unit-owner
echo window-lock-red >"$GHS/ci"
run_helper evaluate --spec specs/demo --task 1
check "the evaluation names window-lock as the check the operator bypasses" grep -q 'ci-rollup	pass	1 check(s) green.*bypasses at merge: window-lock' <<<"$OUT"
fixture
set_policy unit-owner
echo window-lock-pending >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a window-lock still running holds the flip (exit 4)" [ "$CODE" = 4 ]
check "no flip is made over a window-lock still running" [ "$(calls 'pr ready')" = 0 ]
fixture
set_policy unit-owner
echo window-lock-and-red >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a red window-lock beside another red check still refuses (exit 4)" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo window-lock-foreign >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a window-lock from another workflow still refuses (exit 4)" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo window-lock-only >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a red window-lock alone is no positive green (exit 4)" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo tied-red >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a failure started in the same second as a success of its check is not green" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo capped >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a check list at its cap of 100 is a failed precondition" [ "$CODE" = 4 ]
fixture
set_policy unit-owner
echo 0123456789012345678901234567890123456789 >"$GHS/head_override"
run_helper flip --spec specs/demo --task 1
check "a rollup that keeps naming another head is refused unparked (exit 5)" [ "$CODE" = 5 ]
check "no flip on a moved head" [ "$(calls 'pr ready')" = 0 ]

echo "# the ready-guard is the currency floor"
fixture
set_policy unit-owner
echo 3 >"$GHS/behind"
run_helper flip --spec specs/demo --task 1
check "a behind PR parks (exit 4)" [ "$CODE" = 4 ]
check "the park names ready-guard" grep -q 'pending ready-flip: ready-guard' <<<"$(bullet)"
check "no flip when the guard denies" [ "$(calls 'pr ready')" = 0 ]

echo "# the record write and the flip call"
fixture
set_policy unit-owner
echo 1 >"$GHS/comment_rc"
run_helper flip --spec specs/demo --task 1
check "a failing record write parks (exit 4)" [ "$CODE" = 4 ]
check "a failing record write yields no flip call" [ "$(calls 'pr ready')" = 0 ]
check "the park names record-write" grep -q 'pending ready-flip: record-write' <<<"$(bullet)"
fixture
set_policy unit-owner
echo 1 >"$GHS/ready_rc"
run_helper flip --spec specs/demo --task 1
check "a failing flip call parks (exit 4)" [ "$CODE" = 4 ]
check "the record and a follow-up comment were both written" [ "$(calls 'pr comment')" = 2 ]
check "the follow-up names the failed flip" grep -qi 'flip was not made.*gh exit 1' "$GHS/comment.2"
check "the follow-up says the flip was parked" grep -q 'parked under' "$GHS/comment.2"
check "the follow-up passes the markdown lint" lint_emitted markdown ready-flip.sh "$GHS/comment.2"
check "the park names flip-call" grep -q 'pending ready-flip: flip-call' <<<"$(bullet)"

echo "ready-flip-ci: $passes passed, $failures failed"
[ "$failures" = 0 ]
