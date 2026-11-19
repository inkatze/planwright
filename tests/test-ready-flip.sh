#!/bin/bash
# Suite for scripts/ready-flip.sh: every precondition, the PR record and its
# ordering against the flip, and the parking segment and its composition.
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

echo "# every precondition holds: record, then flip"
fixture
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
check "a passing unit flips (exit 0)" [ "$CODE" = 0 ]
check "the flip call ran once" [ "$(calls 'pr ready')" = 1 ]
check "one record comment" [ "$(calls 'pr comment')" = 1 ]
rec=$(first_line_of 'pr comment')
flp=$(first_line_of 'pr ready')
check "the record precedes the flip in the call log" [ "${rec:-9999}" -lt "${flp:-0}" ]
check "the record names the policy value" grep -q 'unit-owner' "$GHS/comment.1"
check "the record names the head SHA" grep -q "$(gitf rev-parse HEAD)" "$GHS/comment.1"
for p in ready-guard ci-rollup review-converged awaiting-input; do
  check "the record carries a passing row with evidence for $p" grep -Eq "^\| $p \| pass \| [^ |][^|]* \|$" "$GHS/comment.1"
done
check "the record passes the markdown lint" lint_emitted markdown ready-flip.sh "$GHS/comment.1"
check "a pass writes no park" [ "$(leads)" = 0 ]
check "the handoff says flipped" grep -q 'flipped' <<<"$OUT"

echo "# version 3 parks as version 2; an undefined version is refused (invariant-tasks REQ-F1.7)"
# redeclare <version> — the unit's tasks.md re-declared, committed and pushed.
redeclare() {
  sed "s/^\\*\\*Format-version:\\*\\* 2\$/**Format-version:** $1/; s/^- \\*\\*Deliverables:\\*\\* x\$/&\\
- **Repository:** alpha/" "$F/wt/$TASKS" >"$F/wt/$TASKS.new"
  mv "$F/wt/$TASKS.new" "$F/wt/$TASKS"
  gitf commit -q -am "chore: version $1"
  gitf push -q origin "$BRANCH" 2>/dev/null
  record_review
}
for v in 3 4; do
  fixture
  set_policy unit-owner
  redeclare "$v"
  echo failing >"$GHS/ci"
  before=$(origin_head)
  run_helper flip --spec specs/demo --task 1
  if [ "$v" = 3 ]; then
    check "the version 3 fixture carries a Repository: field" grep -q '^- \*\*Repository:\*\* alpha$' "$F/wt/$TASKS"
    check "a version 3 failing rollup parks (exit 4)" [ "$CODE" = 4 ]
    check "the version 3 park names the predicate" grep -q '^- \*\*Task 1\*\* — pending ready-flip: ci-rollup' <<<"$(bullet)"
  else
    check "an undefined version (4) is refused (exit 5)" [ "$CODE" = 5 ]
    check "the undefined-version refusal names the declaration" grep -q 'undefined Format-version' <<<"$OUT"
    check "an undefined version writes no park" [ "$(origin_head)" = "$before" ]
  fi
  check "version $v makes no flip call" [ "$(calls 'pr ready')" = 0 ]
done

echo "# exactly one predicate fails: the PR stays draft and the predicate is parked"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
before=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "a failing rollup parks (exit 4)" [ "$CODE" = 4 ]
check "no flip call" [ "$(calls 'pr ready')" = 0 ]
check "no record comment for an unflipped PR" [ "$(calls 'pr comment')" = 0 ]
check "the park opens with the fixed lead and names the predicate" grep -q '^- \*\*Task 1\*\* — pending ready-flip: ci-rollup' <<<"$(bullet)"
check "the park is one commit on the unit branch, pushed" [ "$(commits_since "$before")" = 1 ]
check "the park commit touches only tasks.md" [ "$(changed_since "$before")" = "$TASKS" ]
check "the park commit carries the task trailer" head_trailer_is 'Planwright-Task: demo/1'
check "the placeholder is gone once a bullet exists" not placeholder_in_section
check "the local checkout matches the pushed park" [ "$(gitf rev-parse HEAD)" = "$(origin_head)" ]
check "the tree is clean after a park" [ -z "$(gitf status --porcelain --untracked-files=no)" ]

echo "# a re-run replaces its own segment"
run_helper flip --spec specs/demo --task 1
check "a second failing run parks again" [ "$CODE" = 4 ]
check "one lead, never two" [ "$(leads)" = 1 ]
check "one bullet for the task" [ "$(origin_tasks | grep -c '^- \*\*Task 1\*\*')" = 1 ]

echo "# the next passing run removes only its segment and pushes before it evaluates"
echo green >"$GHS/ci"
parked=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "with only its own segment present the run is not blocked" [ "$CODE" = 0 ]
check "the segment is gone" [ "$(leads)" = 0 ]
check "the placeholder returns to an empty section" placeholder_in_section
check "the unpark commit was pushed" [ "$(origin_head)" != "$parked" ]
check "the record names the head after the unpark" grep -q "$(origin_head)" "$GHS/comment.1"
check "a park-only commit since the review head keeps review-converged" grep -q 'review-converged.*pass' "$GHS/comment.1"

echo "# a bundle parks every task, with one trailer each"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
before=$(origin_head)
run_helper flip --spec specs/demo --task 1 --task 2
check "a failing bundle parks (exit 4)" [ "$CODE" = 4 ]
check "the bundle's first task is parked" grep -q '^- \*\*Task 1\*\* — pending ready-flip: ci-rollup' <<<"$(origin_tasks)"
check "the bundle's second task is parked" grep -q '^- \*\*Task 2\*\* — pending ready-flip: ci-rollup' <<<"$(origin_tasks)"
check "the bundle park is one commit" [ "$(commits_since "$before")" = 1 ]
check "the bundle park carries the first task's trailer" head_trailer_is 'Planwright-Task: demo/1'
check "the bundle park carries the second task's trailer" head_trailer_is 'Planwright-Task: demo/2'
check "the bundle park subject names both tasks" grep -q 'tasks 1 2' <<<"$(git --git-dir="$F/origin.git" log -1 --format=%s "refs/heads/$BRANCH")"
echo green >"$GHS/ci"
run_helper flip --spec specs/demo --task 1 --task 2
check "the bundle flips once both segments are cleared" [ "$CODE" = 0 ]
check "no segment is left for either task" [ "$(leads)" = 0 ]

echo "# a composed bullet with a live halt segment still blocks"
fixture
set_policy unit-owner
write_tasks '- **Task 1** — halt: the operator asked a question; pending ready-flip: ci-rollup failed on 000000000000'
gitf commit -q -am 'chore: park by hand'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
run_helper flip --spec specs/demo --task 1
check "a live halt segment blocks (exit 4)" [ "$CODE" = 4 ]
check "no flip call with a live segment" [ "$(calls 'pr ready')" = 0 ]
check "the halt segment survives the re-park" grep -q 'halt: the operator asked a question' <<<"$(bullet)"
check "the park names awaiting-input" grep -q 'pending ready-flip: awaiting-input' <<<"$(bullet)"
check "still exactly one lead" [ "$(leads)" = 1 ]

echo "# an indented line under the helper's own segment is live"
fixture
set_policy unit-owner
write_tasks '- **Task 1** — pending ready-flip: ci-rollup failed on 000000000000' '  the operator added a note here'
gitf commit -q -am 'chore: a note under the park'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
run_helper flip --spec specs/demo --task 1
check "a continuation line under the lead blocks (exit 4)" [ "$CODE" = 4 ]
check "the continuation line survives the re-park" grep -q '^  the operator added a note here$' <<<"$(origin_tasks)"

echo "# fenced illustration is never a park"
fixture
set_policy unit-owner
write_tasks '```markdown' '- **Task 1** — halt: an example, not a park' '```'
gitf commit -q -am 'docs: an illustration'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
run_helper flip --spec specs/demo --task 1
check "a fenced example bullet does not block (exit 0)" [ "$CODE" = 0 ]

echo "# a human park on the base blocks and the park composes with it"
fixture '- **Task 1** — halt: blocked on a design question'
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
check "a live base bullet blocks (exit 4)" [ "$CODE" = 4 ]
check "the composed park carries the base segment first" grep -q '^- \*\*Task 1\*\* — halt: blocked on a design question; pending ready-flip: awaiting-input' <<<"$(bullet)"
check "the composition leaves one bullet for the task" [ "$(origin_tasks | grep -c '^- \*\*Task 1\*\*')" = 1 ]

echo "# a segment copied from the base stops blocking once the base clears it"
# clear_base — a person clears every Awaiting-input bullet on main.
# base_commit <message> [<awaiting-input lines>...] — commit tasks.md with
# those lines on the base and push it.
base_commit() {
  local msg=$1 wt_saved=$F
  shift
  [ -d "$F/main2" ] || {
    git clone -q "$F/origin.git" "$F/main2" 2>/dev/null
    git -C "$F/main2" config user.name 'Fixture'
    git -C "$F/main2" config user.email 'fixture@example.invalid'
    git -C "$F/main2" config commit.gpgsign false
    git -C "$F/main2" config core.hooksPath "$SANDBOX/nohooks"
    mkdir -p "$F/main2-shim"
    ln -s "$F/main2" "$F/main2-shim/wt"
  }
  F="$F/main2-shim"
  write_tasks "$@"
  F=$wt_saved
  git -C "$F/main2" commit -q -am "$msg"
  git -C "$F/main2" push -q origin main 2>/dev/null
}
clear_base() { base_commit 'chore: the question is answered'; }
fixture '- **Task 1** — halt: blocked on a design question'
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
check "the base park blocks first (exit 4)" [ "$CODE" = 4 ]
clear_base
run_helper flip --spec specs/demo --task 1
check "once the base clears it, the copied segment no longer blocks (exit 0)" [ "$CODE" = 0 ]
check "the copied segment is dropped from the branch" not grep -q 'blocked on a design question' <<<"$(origin_tasks)"
fixture '- **Task 1** — halt: blocked on a design question'
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
write_tasks '- **Task 1** — halt: blocked on a design question; halt: a question the unit raised'
gitf commit -q -am 'chore: the unit asks its own question'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
clear_base
run_helper flip --spec specs/demo --task 1
check "a segment the unit wrote itself still blocks (exit 4)" [ "$CODE" = 4 ]
check "the unit's own segment survives" grep -q 'halt: a question the unit raised' <<<"$(bullet)"
check "the cleared base segment is dropped beside it" not grep -q 'blocked on a design question' <<<"$(bullet)"
fixture '- **Task 2** — halt: blocked on a design question'
set_policy unit-owner
write_tasks '- **Task 1** — halt: blocked on a design question'
gitf commit -q -am 'chore: the unit asks the same question'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
clear_base
run_helper flip --spec specs/demo --task 1
check "a unit segment whose text the base once carried for another task still blocks (exit 4)" [ "$CODE" = 4 ]
check "that segment survives" grep -q '^- \*\*Task 1\*\* — halt: blocked on a design question' <<<"$(bullet)"

echo "# a copied segment holding a backslash is matched literally"
fixture '- **Task 1** — halt: wait on C:\new\dir'
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
check "a backslash segment still on the base blocks (exit 4)" [ "$CODE" = 4 ]
check "a backslash segment still on the base is kept" grep -qF 'halt: wait on C:\new\dir' <<<"$(bullet)"
clear_base
run_helper flip --spec specs/demo --task 1
check "once the base clears a backslash segment, it no longer blocks (exit 0)" [ "$CODE" = 0 ]

echo "# a segment the base moved between tasks is found through the move"
fixture '- **Task 2** — halt: blocked on a design question'
set_policy unit-owner
base_commit 'chore: the question belongs to Task 1' '- **Task 1** — halt: blocked on a design question'
write_tasks '- **Task 1** — halt: blocked on a design question'
gitf commit -q -am 'chore: copy the base park'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
clear_base
run_helper flip --spec specs/demo --task 1
check "a copied segment the base carried for this task only after a move is dropped (exit 0)" [ "$CODE" = 0 ]

echo "# another task's bullet does not block this unit"
fixture '- **Task 2** — halt: unrelated'
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
check "a bullet for another task does not block (exit 0)" [ "$CODE" = 0 ]

echo "ready-flip: $passes passed, $failures failed"
[ "$failures" = 0 ]
