#!/bin/bash
# Suite for scripts/ready-flip.sh: the skips, the park write guards, the
# argument refusals, the precondition hand-in, reconcile, the head re-reads,
# the clock-bounded CI wait, and the wiring that keeps a standalone review run
# and the human policy away from the helper.
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

echo "# skips: no PR, no host CLI, already ready, the human policy"
fixture
set_policy unit-owner
: >"$GHS/nopr"
before=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "no PR skips cleanly (exit 3)" [ "$CODE" = 3 ]
check "no PR writes no park" [ "$(origin_head)" = "$before" ]
check "the skip is said in the handoff" grep -qi 'skipped.*no pull request' <<<"$OUT"
fixture
set_policy unit-owner
before=$(origin_head)
nogh="$SANDBOX/nogh-$RANDOM"
mkdir -p "$nogh"
for t in git jq sh bash cat sed awk grep tr date mktemp head tail wc cut sort printf env dirname basename rm mv cp mkdir timeout sleep cmp; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$nogh/$t"
done
OUT=$(cd "$F/wt" && env PATH="$nogh" PLANWRIGHT_REPO_ROOT="$F/wt" PLANWRIGHT_LOCAL_CONFIG= \
  PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" /bin/bash "$HELPER" flip --spec specs/demo --task 1 2>&1)
CODE=$?
check "no host CLI skips cleanly (exit 3)" [ "$CODE" = 3 ]
check "no host CLI writes no park" [ "$(origin_head)" = "$before" ]
check "the no-CLI skip is said" grep -qi 'skipped.*gh' <<<"$OUT"
fixture
set_policy unit-owner
: >"$GHS/ready"
run_helper flip --spec specs/demo --task 1
check "an already-ready PR skips (exit 3)" [ "$CODE" = 3 ]
check "an already-ready PR gets no second flip" [ "$(calls 'pr ready')" = 0 ]
fixture
set_policy human
before=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "under human the helper refuses to flip (exit 3)" [ "$CODE" = 3 ]
check "under human no gh call is made" [ "$(calls '')" = 0 ]
check "under human no park is written" [ "$(origin_head)" = "$before" ]
fixture
mkdir -p "$F/wt/.claude"
printf 'ready_flip_policy: agent\n' >"$F/wt/.claude/planwright.local.yml"
run_helper flip --spec specs/demo --task 1
check "a malformed machine-local value degrades to human (exit 3)" [ "$CODE" = 3 ]
check "a malformed machine-local value does not flip" [ "$(calls 'pr ready')" = 0 ]

echo "# a park that cannot be written leaves the tree clean"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
mkdir -p "$F/hooks"
printf '#!/bin/sh\nexit 1\n' >"$F/hooks/pre-commit"
chmod +x "$F/hooks/pre-commit"
gitf config core.hooksPath "$F/hooks"
before=$(gitf rev-parse HEAD)
run_helper flip --spec specs/demo --task 1
check "an unwritable park exits 5" [ "$CODE" = 5 ]
check "the tree is clean" [ -z "$(gitf status --porcelain --untracked-files=no)" ]
check "no commit was left behind" [ "$(gitf rev-parse HEAD)" = "$before" ]
check "the handoff names the unwritten park" grep -qi 'park.*not written\|could not write' <<<"$OUT"

echo "# the park's commit and push run the adopter's hooks under the caller's locale"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
mkdir -p "$F/hooks"
for hook in pre-commit pre-push; do
  # shellcheck disable=SC2016 # literal hook source, expanded by the hook
  printf '#!/bin/sh\nl=${LC_ALL:-${LC_CTYPE:-${LANG:-C}}}\nprintf "%%s\\n" "$l" >>"%s/locale.%s"\ncase $l in *[Uu][Tt][Ff]-8*) exit 0 ;; esac\necho "non-UTF-8 locale: $l" >&2\nexit 1\n' \
    "$F" "$hook" >"$F/hooks/$hook"
  chmod +x "$F/hooks/$hook"
done
gitf config core.hooksPath "$F/hooks"
before=$(origin_head)
(
  unset LC_ALL LC_CTYPE
  export LANG=C.UTF-8
  run_helper flip --spec specs/demo --task 1
  printf '%s\n' "$CODE" >"$F/loc.code"
)
CODE=$(cat "$F/loc.code")
check "a park whose hooks demand UTF-8 still lands under a UTF-8 caller (exit 4)" [ "$CODE" = 4 ]
check "the park was pushed past the pre-push hook" [ "$(commits_since "$before")" = 1 ]
check "the pre-commit hook saw the caller's locale" [ "$(cat "$F/locale.pre-commit")" = C.UTF-8 ]
check "the pre-push hook saw the caller's locale" [ "$(cat "$F/locale.pre-push")" = C.UTF-8 ]

echo "# a tasks.md that cannot be written is never committed"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
chmod 444 "$F/wt/$TASKS"
if [ -w "$F/wt/$TASKS" ]; then
  # Root, or any process with DAC override, still writes a mode-444 file.
  chmod 644 "$F/wt/$TASKS"
  echo "skip: this user can write a mode-444 file, so an unwritable tasks.md cannot be staged"
else
  before=$(gitf rev-parse HEAD)
  run_helper flip --spec specs/demo --task 1
  chmod 644 "$F/wt/$TASKS"
  check "an unwritable tasks.md exits 5" [ "$CODE" = 5 ]
  check "an unwritable tasks.md makes no commit" [ "$(gitf rev-parse HEAD)" = "$before" ]
  check "an unwritable tasks.md is named" grep -q 'could not be written' <<<"$OUT"
  check "an unwritable tasks.md keeps its content" grep -q '### Task 1' "$F/wt/$TASKS"
fi

echo "# argument and branch refusals"
fixture
set_policy unit-owner
run_helper flip --spec ../outside --task 1
check "a spec path escaping the checkout is refused (exit 2)" [ "$CODE" = 2 ]
run_helper flip --spec specs/demo --task '1;rm'
check "a malformed task id is refused (exit 2)" [ "$CODE" = 2 ]
gitf checkout -q main
run_helper flip --spec specs/demo --task 1
check "a checkout not on a task branch is refused (exit 5)" [ "$CODE" = 5 ]
check "no gh call from a non-task branch" [ "$(calls 'pr ready')" = 0 ]

fixture
set_policy unit-owner
echo '--upload-pack=touch' >"$GHS/base"
run_helper flip --spec specs/demo --task 1
check "a base name shaped like an option is never used (exit 4)" [ "$CODE" = 4 ]
check "an option-shaped base parks as an unreadable PR" grep -q 'pending ready-flip: pr-lookup' <<<"$(bullet)"
check "an option-shaped base gets no flip" [ "$(calls 'pr ready')" = 0 ]

fixture
set_policy unit-owner
cp -R "$F/wt" "$F/-wt"
OUT=$(cd "$F" && env PATH="$STUBBIN:$PATH" GHS="$GHS" GHS_ORIGIN="$F/origin.git" \
  GHS_BRANCH="$BRANCH" PLANWRIGHT_REPO_ROOT="$F/-wt" PLANWRIGHT_LOCAL_CONFIG= \
  PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" PLANWRIGHT_READY_FLIP_POLL_SECONDS=0 \
  PLANWRIGHT_READY_FLIP_MAX_POLLS=3 PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
  /bin/bash "$HELPER" reconcile --spec specs/demo --task 1 --worktree -wt 2>&1)
CODE=$?
check "a --worktree starting with a dash names that directory, not a cd option" [ "$CODE" = 0 ]

echo "# the precondition hand-in runs the CI wait once"
fixture
set_policy unit-owner
hand="$SANDBOX/hand-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$hand"
check "evaluate passes (exit 0)" [ "$CODE" = 0 ]
check "evaluate never flips" [ "$(calls 'pr ready')" = 0 ]
check "evaluate never comments" [ "$(calls 'pr comment')" = 0 ]
check "the hand-in names the head" grep -q "^head	$(gitf rev-parse HEAD)$" "$hand"
before=$(rollups)
run_helper flip --spec specs/demo --task 1 --preconditions "$hand"
check "a flip with a matching hand-in flips" [ "$CODE" = 0 ]
check "a matching hand-in still reads the rollup once, without waiting" [ "$(rollups)" = "$((before + 2))" ]

echo "# a hand-in skips only the wait, never a check"
fixture
set_policy unit-owner
hand5="$SANDBOX/hand5-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$hand5"
echo failing >"$GHS/ci"
run_helper flip --spec specs/demo --task 1 --preconditions "$hand5"
check "a hand-in claiming green over a red rollup does not flip" [ "$(calls 'pr ready')" = 0 ]
check "a hand-in claiming green over a red rollup parks ci-rollup" grep -q 'pending ready-flip: ci-rollup' <<<"$(bullet)"
fixture
set_policy unit-owner
hand6="$SANDBOX/hand6-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$hand6"
echo pending >"$GHS/ci"
before=$(rollups)
run_helper flip --spec specs/demo --task 1 --preconditions "$hand6"
check "a hand-in claiming green over a pending rollup does not flip" [ "$(calls 'pr ready')" = 0 ]
check "a valid hand-in does not wait: one rollup read, not the bounded poll" [ "$(rollups)" = "$((before + 1))" ]
fixture
set_policy unit-owner
hand7="$SANDBOX/hand7-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$hand7"
rm -rf "$F/wt/.claude/steps"
run_helper flip --spec specs/demo --task 1 --preconditions "$hand7"
check "a hand-in cannot stand in for a missing review record" [ "$(calls 'pr ready')" = 0 ]
fixture
set_policy unit-owner
printf 'head\t%s\npred\tci-rollup\tpass\tx\npred\treview-converged\tpass\tx\npred\tawaiting-input\tpass\tx\npred\tready-guard\tpass\tx\n' \
  "$(gitf rev-parse HEAD)" >"$SANDBOX/hand8"
echo failing >"$GHS/ci"
run_helper flip --spec specs/demo --task 1 --preconditions "$SANDBOX/hand8"
check "a hand-written all-pass hand-in over a red rollup does not flip" [ "$(calls 'pr ready')" = 0 ]
fixture
set_policy unit-owner
hand2="$SANDBOX/hand2-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$hand2"
printf 'x\n' >>"$F/wt/feature.txt"
gitf commit -q -am 'fix: late'
gitf push -q origin "$BRANCH" 2>/dev/null
record_review
run_helper flip --spec specs/demo --task 1 --preconditions "$hand2"
check "a hand-in for another head still flips after re-evaluating" [ "$CODE" = 0 ]
check "a hand-in for another head is not trusted: the CI wait re-runs" [ "$(rollups)" = 4 ]

echo "# reconcile alone"
fixture
set_policy unit-owner
write_tasks '- **Task 1** — pending ready-flip: ci-rollup failed on 000000000000'
gitf commit -q -am 'chore: park'
gitf push -q origin "$BRANCH" 2>/dev/null
run_helper reconcile --spec specs/demo --task 1
check "reconcile exits 0" [ "$CODE" = 0 ]
check "reconcile removes its own segment and pushes" [ "$(leads)" = 0 ]
check "reconcile prints the head it pushed" grep -q "$(origin_head)" <<<"$OUT"
check "reconcile makes no gh call" [ "$(calls '')" = 0 ]

echo "# reconcile leaves a person's bullet and a missing section alone"
fixture
set_policy unit-owner
write_tasks '- **Task 1**: a question a;b  with spacing'
gitf commit -q -am 'chore: a human question'
gitf push -q origin "$BRANCH" 2>/dev/null
before=$(origin_head)
run_helper reconcile --spec specs/demo --task 1
check "reconcile with no own segment exits 0" [ "$CODE" = 0 ]
check "a bullet with no own segment is not rewritten" grep -qx -- '- \*\*Task 1\*\*: a question a;b  with spacing' <<<"$(origin_tasks)"
check "a bullet with no own segment makes no commit" [ "$(origin_head)" = "$before" ]
fixture
set_policy unit-owner
printf '# Demo — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n### Task 1 — One\n' >"$F/wt/$TASKS"
gitf commit -q -am 'chore: no awaiting-input section'
gitf push -q origin "$BRANCH" 2>/dev/null
before=$(origin_head)
run_helper reconcile --spec specs/demo --task 1
check "reconcile over a bundle with no section makes no commit" [ "$(origin_head)" = "$before" ]
check "reconcile never empties tasks.md" grep -q '### Task 1' "$F/wt/$TASKS"

echo "# --expect-head refuses a head the point did not end on"
fixture
set_policy unit-owner
run_helper flip --spec specs/demo --task 1 --expect-head 0123456789012345678901234567890123456789
check "a head other than the expected one is refused (exit 5)" [ "$CODE" = 5 ]
check "no flip call against an unexpected head" [ "$(calls 'pr ready')" = 0 ]
fixture
set_policy unit-owner
run_helper flip --spec specs/demo --task 1 --expect-head "$(gitf rev-parse HEAD)"
check "the expected head flips" [ "$CODE" = 0 ]

echo "# the PR head is re-read before the record and before the flip"
fixture
set_policy unit-owner
echo 0123456789012345678901234567890123456789 >"$GHS/head_at_flip"
run_helper flip --spec specs/demo --task 1
check "a head that moved after the checks is not flipped" [ "$(calls 'pr ready')" = 0 ]
check "a head that moved after the checks writes no record" [ "$(calls 'pr comment')" = 0 ]

fixture
set_policy unit-owner
echo 0123456789012345678901234567890123456789 >"$GHS/head_after_record"
before=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "a head that moves after the record is not flipped (exit 5)" [ "$CODE" = 5 ]
check "no flip call once the head moved after the record" [ "$(calls 'pr ready')" = 0 ]
check "the record and its follow-up were both written" [ "$(calls 'pr comment')" = 2 ]
check "the follow-up says the head moved and nothing was parked" grep -q 'head moved.*no park was written' "$GHS/comment.2"
check "no park is pushed on top of a moved branch" [ "$(origin_head)" = "$before" ]
check "no local park commit is stranded" [ "$(gitf rev-parse HEAD)" = "$before" ]
fixture
set_policy unit-owner
echo 0123456789012345678901234567890123456789 >"$GHS/head_override"
before=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "a head someone else moved refuses with no park (exit 5)" [ "$CODE" = 5 ]
check "a moved branch gets no stranded park commit" [ "$(gitf rev-parse HEAD)" = "$before" ]
fixture
set_policy unit-owner
echo 1 >"$GHS/head_lag_until"
run_helper flip --spec specs/demo --task 1
check "a host lagging one read behind the push still flips" [ "$CODE" = 0 ]

fixture
set_policy unit-owner
echo 1 >"$GHS/head_lag_until"
OUT=$(cd "$F/wt" && env PATH="$STUBBIN:$PATH" GHS="$GHS" GHS_ORIGIN="$F/origin.git" \
  GHS_BRANCH="$BRANCH" PLANWRIGHT_REPO_ROOT="$F/wt" PLANWRIGHT_LOCAL_CONFIG= \
  PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" PLANWRIGHT_READY_FLIP_POLL_SECONDS=0 \
  PLANWRIGHT_READY_FLIP_MAX_POLLS=1 PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
  /bin/bash "$HELPER" flip --spec specs/demo --task 1 2>&1)
CODE=$?
check "with a single CI read, one lagging head read still flips" [ "$CODE" = 0 ]

echo "# an unreadable head after the record parks and says so"
fixture
set_policy unit-owner
printf '' >"$GHS/head_after_record"
run_helper flip --spec specs/demo --task 1
check "an unreadable head after the record parks (exit 4)" [ "$CODE" = 4 ]
check "no flip when the head cannot be re-read" [ "$(calls 'pr ready')" = 0 ]
check "the follow-up says the head could not be re-read" grep -q 'could not be re-read.*parked under' "$GHS/comment.2"

echo "# the CI wait is bounded by the clock too"
fixture
mkdir -p "$F/wt/.claude"
printf 'ready_flip_policy: unit-owner\nready_flip_ci_wait: 2s\n' >"$F/wt/.claude/planwright.local.yml"
echo 0123456789012345678901234567890123456789 >"$GHS/head_override"
printf '' >"$GHS/head_at_flip"
OUT=$(cd "$F/wt" && env PATH="$STUBBIN:$PATH" GHS="$GHS" GHS_ORIGIN="$F/origin.git" \
  GHS_BRANCH="$BRANCH" PLANWRIGHT_REPO_ROOT="$F/wt" PLANWRIGHT_LOCAL_CONFIG= \
  PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" PLANWRIGHT_READY_FLIP_POLL_SECONDS=1 \
  PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 /bin/bash "$HELPER" flip --spec specs/demo --task 1 2>&1)
check "head re-reads inside an attempt do not stretch the wait past its bound" [ "$(rollups)" = 1 ]

echo "# the CI wait reads the rollup at its deadline too"
fixture
mkdir -p "$F/wt/.claude"
printf 'ready_flip_policy: unit-owner\nready_flip_ci_wait: 6s\n' >"$F/wt/.claude/planwright.local.yml"
echo pending >"$GHS/ci"
echo 3 >"$GHS/ci_green_from"
run_polled 3 '' flip --spec specs/demo --task 1
check "checks going green by the deadline flip (exit 0)" [ "$CODE" = 0 ]
check "a 6s wait polled every 3s reads at 0s, 3s and 6s" [ "$(rollups)" = 4 ]

echo "# a wait that is not a multiple of the poll interval still reads at its deadline"
fixture
mkdir -p "$F/wt/.claude"
printf 'ready_flip_policy: unit-owner\nready_flip_ci_wait: 5s\n' >"$F/wt/.claude/planwright.local.yml"
echo pending >"$GHS/ci"
echo 3 >"$GHS/ci_green_from"
run_polled 3 '' flip --spec specs/demo --task 1
check "checks going green between the last interval and the deadline flip (exit 0)" [ "$CODE" = 0 ]

echo "# a poll interval with leading zeros is decimal"
fixture
set_policy unit-owner
echo pending >"$GHS/ci"
echo 2 >"$GHS/ci_green_from"
run_polled 00 2 flip --spec specs/demo --task 1
check "a poll interval of 00 behaves as 0 (exit 0)" [ "$CODE" = 0 ]
check "a poll interval of 00 makes the max-polls reads" [ "$(rollups)" = 3 ]
check "a poll interval of 00 raises no arithmetic error" not grep -qi 'division\|syntax error\|value too great' <<<"$OUT"
fixture
set_policy unit-owner
run_polled 08 '' flip --spec specs/demo --task 1
check "a poll interval of 08 is decimal, not an octal error" not grep -qi 'value too great\|syntax error' <<<"$OUT"
check "a poll interval of 08 flips on green checks (exit 0)" [ "$CODE" = 0 ]

echo "# an unreadable re-read is not a moved head"
fixture
set_policy unit-owner
echo 1 >"$GHS/head_lag_until"
echo 2 >"$GHS/rollup_fail_at"
run_polled 0 1 evaluate --spec specs/demo --task 1
check "an empty re-read fails ci-rollup as unreadable" grep -q 'ci-rollup	fail	the check rollup could not be read' <<<"$OUT"
check "an empty re-read is not reported as an unsettled head" not grep -q 'did not settle' <<<"$OUT"
fixture
set_policy unit-owner
echo 1 >"$GHS/head_lag_until"
echo 2 >"$GHS/rollup_garbage_at"
run_polled 0 1 evaluate --spec specs/demo --task 1
check "an unparseable re-read fails ci-rollup as unreadable" grep -q 'ci-rollup	fail	the check rollup could not be read' <<<"$OUT"
check "an unparseable re-read is not reported as an unsettled head" not grep -q 'did not settle' <<<"$OUT"
fixture
set_policy unit-owner
echo 9 >"$GHS/head_lag_until"
echo 3 >"$GHS/rollup_fail_at"
run_polled 0 2 evaluate --spec specs/demo --task 1
check "a failed last read after an unsettled head ends as unreadable" grep -q 'ci-rollup	fail	the check rollup could not be read' <<<"$OUT"

echo "# no tracking ref: reconcile fetches one before deciding what to push"
fixture
set_policy unit-owner
gitf update-ref -d "refs/remotes/origin/$BRANCH"
run_helper reconcile --spec specs/demo --task 1
check "reconcile with no tracking ref and nothing to clear exits 0" [ "$CODE" = 0 ]
check "reconcile restores the tracking ref" gitf rev-parse --verify -q "refs/remotes/origin/$BRANCH"
fixture
set_policy unit-owner
printf 'local\n' >>"$F/wt/feature.txt"
gitf commit -q -am 'chore: a commit the push missed'
gitf update-ref -d "refs/remotes/origin/$BRANCH"
run_helper reconcile --spec specs/demo --task 1
check "a commit stranded without a tracking ref is pushed by reconcile" [ "$(origin_head)" = "$(gitf rev-parse HEAD)" ]

echo "# a hand-in that failed, or names too little, is never trusted"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
hand3="$SANDBOX/hand3-$RANDOM"
run_helper evaluate --spec specs/demo --task 1 --out "$hand3"
check "evaluate with a failing precondition exits 4" [ "$CODE" = 4 ]
check "evaluate never parks" [ "$(leads)" = 0 ]
check "the failing record says fail" grep -q '^pred	ci-rollup	fail' "$hand3"
echo green >"$GHS/ci"
before=$(rollups)
run_helper flip --spec specs/demo --task 1 --preconditions "$hand3"
check "a failed hand-in is re-evaluated: the CI wait runs again" [ "$(rollups)" -gt "$before" ]
fixture
set_policy unit-owner
printf 'head\t%s\npred\tci-rollup\tpass\tx\n' "$(gitf rev-parse HEAD)" >"$SANDBOX/hand4"
before=$(rollups)
run_helper flip --spec specs/demo --task 1 --preconditions "$SANDBOX/hand4"
check "a hand-in missing predicates is re-evaluated" [ "$(rollups)" -gt "$before" ]

echo "# the PR lookup retries a transient failure, and refuses a fork"
fixture
set_policy unit-owner
echo 2 >"$GHS/lookup_fail_until"
run_helper flip --spec specs/demo --task 1
check "a transient lookup failure is retried, then flips" [ "$CODE" = 0 ]
fixture
mkdir -p "$F/wt/.claude"
printf 'ready_flip_policy: unit-owner\nready_flip_ci_wait: 2s\n' >"$F/wt/.claude/planwright.local.yml"
echo 1 >"$GHS/lookup_fail_until"
run_polled 3 '' flip --spec specs/demo --task 1
check "a wait shorter than one poll interval gives the lookup no retry nap" [ "$(cat "$GHS/lookup_n")" = 1 ]
fixture
set_policy unit-owner
: >"$GHS/fork"
run_helper flip --spec specs/demo --task 1
check "a PR from a fork is refused (exit 5)" [ "$CODE" = 5 ]
check "a fork PR gets no flip" [ "$(calls 'pr ready')" = 0 ]

echo "# a park whose push fails is named, and the next run pushes it first"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
printf '#!/bin/sh\nexit 1\n' >"$F/origin.git/hooks/pre-receive"
chmod +x "$F/origin.git/hooks/pre-receive"
before=$(origin_head)
run_helper flip --spec specs/demo --task 1
check "an unpushed park exits 5" [ "$CODE" = 5 ]
check "an unpushed park is named as local only" grep -q 'local only' <<<"$OUT"
check "the remote did not move" [ "$(origin_head)" = "$before" ]
rm -f "$F/origin.git/hooks/pre-receive"
run_helper reconcile --spec specs/demo --task 1
check "the next reconcile pushes the stranded commit" [ "$(origin_head)" = "$(gitf rev-parse HEAD)" ]

echo "# a mergeability conflict is the ready-guard's refusal"
fixture
set_policy unit-owner
echo 1 >"$GHS/behind"
run_helper evaluate --spec specs/demo --task 1
check "a behind head fails ready-guard in evaluate" grep -q 'ready-guard	fail' <<<"$OUT"

echo "# no model in the decision path"
check "the helper calls no model or dispatch backend" not grep -Eq '(^|[^[:alnum:]_-])(claude|anthropic|offload-dispatch)([^[:alnum:]_-]|$)' "$HELPER"

echo "# wiring: who calls the helper"
check "/execute-task calls the helper only under unit-owner" grep -Eq 'ready_flip_policy.*unit-owner.*ready-flip\.sh|ready-flip\.sh.*ready_flip_policy.*unit-owner' <(tr '\n' ' ' <"$REPO_ROOT/skills/execute-task/SKILL.md")
for s in polish self-review; do
  check "a standalone /$s run never calls the helper" not grep -q 'ready-flip\.sh' "$REPO_ROOT/skills/$s/SKILL.md"
done
# shellcheck disable=SC2016 # literal backticks of the markdown row
check "the spec-PR knob is documented as the same kind" grep -q '^| `mark_spec_pr_ready_on_kickoff` |.*spec-PR instance of the `ready_flip_policy` kind' "$REPO_ROOT/docs/options-reference.md"
check "the spec-PR knob keeps its default" grep -q '^mark_spec_pr_ready_on_kickoff: true$' "$REPO_ROOT/config/defaults.yml"

echo "ready-flip-handin: $passes passed, $failures failed"
[ "$failures" = 0 ]
