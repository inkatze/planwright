#!/bin/bash
# Suite for scripts/ready-flip.sh: the review-converged precondition, the
# review loop record and the limited-record retirement.
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
# other_head: a commit of the unit's repository that is not its HEAD, reachable
# from no ref; step-record.sh write refuses a head naming no commit.
other_head() { gitf commit-tree -m "fixture: another head" "HEAD^{tree}"; }

# shellcheck source=tests/lib/ready-flip-fixture.sh
. "$REPO_ROOT/tests/lib/ready-flip-fixture.sh"

echo "# the review loop's record must name the head"
fixture
set_policy unit-owner
printf 'more\n' >>"$F/wt/feature.txt"
gitf commit -q -am 'fix: after review'
gitf push -q origin "$BRANCH" 2>/dev/null
run_helper flip --spec specs/demo --task 1
check "a code commit after the review head fails review-converged" [ "$CODE" = 4 ]
check "the park names review-converged" grep -q 'pending ready-flip: review-converged' <<<"$(bullet)"
check "a failing local predicate does not wait on CI" [ "$(rollups)" = 0 ]

echo "# no review record at all fails review-converged"
fixture
set_policy unit-owner
rm -rf "$F/wt/.claude/steps"
run_helper flip --spec specs/demo --task 1
check "a worktree with no review record parks (exit 4)" [ "$CODE" = 4 ]
check "the park names review-converged" grep -q 'review-converged' <<<"$(bullet)"

echo "# a failed review step under the record fails review-converged"
fixture
set_policy unit-owner
run=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run)
/bin/sh "$STEP_RECORD" --worktree "$F/wt" write --run "$run" --point convergence --step polish \
  --kind skill --target polish --hosting in-session --backend in-session --head "$(gitf rev-parse HEAD)" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:09:41Z --outcome failed >/dev/null
/bin/sh "$STEP_RECORD" --worktree "$F/wt" write --completion --run "$run" --point convergence \
  --head "$(gitf rev-parse HEAD)" >/dev/null
run_helper flip --spec specs/demo --task 1
check "a failed review step parks (exit 4)" [ "$CODE" = 4 ]
check "the park names review-converged" grep -q 'review-converged' <<<"$(bullet)"

echo "# an unretired limited record ending on the head fails review-converged (REQ-J1.2)"
fixture
set_policy unit-owner
run=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run)
/bin/sh "$STEP_RECORD" --worktree "$F/wt" write --run "$run" --point post-pr --step cubic \
  --kind skill --target bot-review --hosting in-session --backend in-session --head "$(gitf rev-parse HEAD)" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:09:41Z --outcome limited >/dev/null
run_helper flip --spec specs/demo --task 1
check "a limited post-pr record on the head parks (exit 4)" [ "$CODE" = 4 ]
check "the park names review-converged" grep -q 'review-converged' <<<"$(bullet)"
check "the limited record does not wait on CI" [ "$(rollups)" = 0 ]
fixture
set_policy unit-owner
run=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run)
other=$(other_head)
/bin/sh "$STEP_RECORD" --worktree "$F/wt" write --run "$run" --point post-pr --step cubic \
  --kind skill --target bot-review --hosting in-session --backend in-session \
  --head "$other" --end-head "$other" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:09:41Z --outcome limited >/dev/null \
  || fail "fixture: the limited record on another head was refused"
run_helper flip --spec specs/demo --task 1
check "a limited record ending on another head does not block (exit 0)" [ "$CODE" = 0 ]

echo "# a PR-Agent pass on the head retires a limited cubic-pr; another head does not"
for ph in head other; do
  fixture
  set_policy unit-owner
  hd=$(gitf rev-parse HEAD)
  run=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run)
  /bin/sh "$STEP_RECORD" --worktree "$F/wt" write --run "$run" --point post-pr --step cubic-pr \
    --kind skill --target bot-review --hosting in-session --backend in-session --head "$hd" \
    --start 2026-11-01T10:03:17Z --end 2026-11-01T10:09:41Z --outcome limited >/dev/null
  run2=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run)
  eh=$hd
  [ "$ph" = head ] || eh=$(other_head)
  /bin/sh "$STEP_RECORD" --worktree "$F/wt" write --run "$run2" --point post-pr --step pr-agent-pr \
    --kind skill --target bot-review --hosting in-session --backend in-session --head "$eh" --end-head "$eh" \
    --start 2026-11-01T10:03:17Z --end 2026-11-01T10:09:41Z --outcome passed >/dev/null \
    || fail "fixture: the pr-agent-pr record on the $ph head was refused"
  run_helper flip --spec specs/demo --task 1
  if [ "$ph" = head ]; then
    check "a pr-agent-pr pass on the head retires the limited cubic-pr (exit 0)" [ "$CODE" = 0 ]
  else
    check "a pr-agent-pr pass on another head leaves cubic-pr limited (exit 4)" [ "$CODE" = 4 ]
  fi
done

echo "ready-flip-review: $passes passed, $failures failed"
[ "$failures" = 0 ]
