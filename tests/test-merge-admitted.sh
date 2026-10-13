#!/bin/bash
# Suite for scripts/merge-admitted.sh, the one sanctioned agent merge path
# under merge_policy: policy-class (human-gates REQ-D1.2, REQ-D1.4, REQ-D1.5):
# its own policy re-read, the record before the merge call, the flip of an
# admitted draft through scripts/ready-flip.sh with one CI wait in total, the
# re-pin of head, base, and Awaiting-input before the merge call, the
# fall-through comment, and the merge-call failure. Also the ready-flip modes
# the helper composes (awaiting, park, flip --for-merge) and the wiring that
# has /execute-task call it last.
#
# Hermetic: tests/lib/merge-policy-fixture.sh builds a throwaway origin and a
# unit clone, and a stub gh answers from files. Nothing reaches a real host.
unset CDPATH
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$REPO_ROOT/scripts/merge-admitted.sh"
FLIP="$REPO_ROOT/scripts/ready-flip.sh"

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

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/merge-admitted.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
# shellcheck source=tests/lib/merge-policy-fixture.sh
. "$REPO_ROOT/tests/lib/merge-policy-fixture.sh"

if [ ! -f "$HELPER" ]; then
  fail "the helper exists at scripts/merge-admitted.sh"
  echo "merge-admitted: $passes passed, $failures failed" >&2
  exit 1
fi

admit() { # [<extra policy lines>...]
  mp_fixture
  mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'ready_flip_ci_wait: 30s' "$@"
}
run() { mp_run "$HELPER" --spec specs/demo --task 1 "$@"; }
rollups() { mp_calls 'pr view 42 --json headRefOid,statusCheckRollup'; }
merge_line() { grep '^CALL pr merge' "$GHS/log"; }

# on_comment <n> <branch> <file> <content> — after the nth PR comment, a
# second clone pushes a commit writing <file> to <branch> of the origin.
on_comment() {
  git clone -q "$F/origin.git" "$F/other" 2>/dev/null
  cat >"$GHS/on_comment.$1" <<EOF
cd '$F/other' || exit 1
git -c core.hooksPath='$SANDBOX/nohooks' checkout -q '$2' 2>/dev/null || git checkout -q -b '$2' 'origin/$2'
mkdir -p "\$(dirname '$3')"
printf '%s\n' '$4' >'$3'
git add -f '$3'
git -c user.name=o -c user.email=o@example.invalid -c commit.gpgsign=false -c core.hooksPath='$SANDBOX/nohooks' commit -q -m 'chore: moved meanwhile'
git push -q origin '$2'
EOF
}

mp_fixture
MP_TEMPLATE=$F

echo "# an admitted draft PR: flip, record, then merge"
admit 'ready_flip_policy: human'
run
check "an admitted PR merges (exit 0)" [ "$CODE" = 0 ]
check "the flip call ran once, under ready_flip_policy: human" [ "$(mp_calls 'pr ready')" = 1 ]
check "the merge call ran once" [ "$(mp_calls 'pr merge')" = 1 ]
flp=$(mp_first_line_of 'pr ready')
mrg=$(mp_first_line_of 'pr merge')
check "the flip precedes the merge" [ "${flp:-9999}" -lt "${mrg:-0}" ]
last_comment=$(cat "$GHS/comments")
check "the merge record is the last comment" grep -q 'planwright:merge-admitted' "$GHS/comment.$last_comment"
rec_line=$(grep -n '^CALL pr comment' "$GHS/log" | tail -1 | cut -d: -f1)
check "the merge record precedes the merge call" [ "${rec_line:-9999}" -lt "${mrg:-0}" ]
check "the record names the policy value" grep -q 'policy-class' "$GHS/comment.$last_comment"
check "the record names the head" grep -q "$(mp_origin_head)" "$GHS/comment.$last_comment"
for p in branch sign-off core-zone excluded-paths max-lines strategy awaiting-input review-converged ci-rollup ready-guard; do
  check "the record carries a passing row with evidence for $p" grep -Eq "^\| $p \| pass \| [^ |][^|]* \|$" "$GHS/comment.$last_comment"
done
check "the merge uses the resolved strategy" grep -q -- '--squash' <<<"$(merge_line)"
check "the merge is pinned to the evaluated head" grep -q -- "--match-head-commit $(mp_origin_head)" <<<"$(merge_line)"
check "the merge never deletes the branch" not grep -q -- '--delete-branch\|-d ' <<<"$(merge_line)"
check "one CI wait in total: one polled read, one confirming read" [ "$(rollups)" = 2 ]
check "the handoff says merged" grep -q 'merged PR #42' <<<"$OUT"

echo "# an admitted PR already ready gets no second flip"
admit
: >"$GHS/ready"
run
check "an already-ready admitted PR merges (exit 0)" [ "$CODE" = 0 ]
check "no flip call for a ready PR" [ "$(mp_calls 'pr ready')" = 0 ]

echo "# the helper re-resolves the policy and fails closed"
for v in human on-approval; do
  mp_fixture
  mp_policy "merge_policy: $v"
  run
  check "under $v the helper skips (exit 3)" [ "$CODE" = 3 ]
  check "under $v no gh call is made" [ "$(mp_calls '')" = 0 ]
done
mp_fixture
mkdir -p "$F/wt/.claude"
printf 'merge_policy: sometimes\n' >"$F/wt/.claude/planwright.yml"
run
check "a malformed repo-tracked merge_policy refuses (exit 5)" [ "$CODE" = 5 ]
check "an unreadable policy makes no gh call" [ "$(mp_calls '')" = 0 ]
mp_fixture
mp_policy 'merge_policy: sometimes'
run
check "a malformed machine-local merge_policy degrades to human (exit 3)" [ "$CODE" = 3 ]

echo "# a PR outside the class falls to on-approval with the reason on the PR"
admit
echo 'merge squash' >"$GHS/methods"
run
check "a fall-through exits 4" [ "$CODE" = 4 ]
check "no merge call" [ "$(mp_calls 'pr merge')" = 0 ]
check "no flip call" [ "$(mp_calls 'pr ready')" = 0 ]
check "one fall-through comment" [ "$(mp_calls 'pr comment')" = 1 ]
check "the comment names the failed predicate" grep -q 'strategy' "$GHS/comment.1"
check "the comment names on-approval" grep -q 'on-approval' "$GHS/comment.1"
check "the comment names the approval act" grep -qi 'auto-merge' "$GHS/comment.1"
admit
printf 'release-please--branches--main\n' >"$GHS/head_name"
run
check "a release PR falls through (exit 4)" [ "$CODE" = 4 ]
check "a release PR is never merged" [ "$(mp_calls 'pr merge')" = 0 ]
check "the release PR's comment names the branch rule" grep -q 'task branch' "$GHS/comment.1"
admit
echo agent-bot >"$GHS/login"
echo 'merge squash' >"$GHS/methods"
run
check "a split identity's fall-through names the approving review" grep -qi 'approving review' "$GHS/comment.1"

echo "# the record write and the merge call"
admit
: >"$GHS/ready"
echo 1 >"$GHS/comment_rc"
run
check "a failing record write yields no merge call" [ "$(mp_calls 'pr merge')" = 0 ]
check "a failing record write exits 5" [ "$CODE" = 5 ]
admit
: >"$GHS/ready"
echo 1 >"$GHS/merge_rc"
before=$(mp_origin_head)
run
check "a failing merge call parks (exit 4)" [ "$CODE" = 4 ]
check "the record and a follow-up were both written" [ "$(mp_calls 'pr comment')" = 2 ]
check "the follow-up names the failed merge" grep -qi 'merge was not made.*gh exit 1' "$GHS/comment.2"
check "the park names merge-call" grep -q 'pending ready-flip: merge-call failed' <<<"$(mp_origin_tasks)"
check "the park is one pushed commit" [ "$(git --git-dir="$F/origin.git" rev-list --count "$before..refs/heads/$MP_BRANCH")" = 1 ]

echo "# a head, a base, or a park that moves after the record refuses the merge"
admit
: >"$GHS/ready"
on_comment 1 "$MP_BRANCH" late.txt late
run
check "a moved head yields no merge call" [ "$(mp_calls 'pr merge')" = 0 ]
check "a moved head exits 4" [ "$CODE" = 4 ]
check "a moved head is said on the PR" grep -qi 'head.*moved' "$GHS/comment.2"
admit
: >"$GHS/ready"
on_comment 1 main elsewhere.txt base-moved
run
check "a moved base yields no merge call" [ "$(mp_calls 'pr merge')" = 0 ]
check "a moved base is said on the PR" grep -qi 'base.*moved' "$GHS/comment.2"
admit
: >"$GHS/ready"
on_comment 1 main "$MP_TASKS" "$(cat "$F/wt/$MP_TASKS" | sed 's/^(none yet)$/- **Task 1** — hold on, a question/' | head -c 4000)"
run
check "a park landing on the base yields no merge call" [ "$(mp_calls 'pr merge')" = 0 ]
check "the park is said on the PR" grep -qi 'awaiting' "$GHS/comment.2"

echo "# the flip takes the class's precondition record: one CI wait in total"
admit
printf 'green\npending\ngreen\n' >"$GHS/ci_seq"
run
check "the flip reads the rollup once without waiting, so a check turning pending stops it (exit 4)" [ "$CODE" = 4 ]
check "no merge after a flip that did not go through" [ "$(mp_calls 'pr merge')" = 0 ]
check "the flip never re-evaluated afresh" [ "$(rollups)" = 2 ]
check "a flip that did not go through is said on the PR" grep -qi 'flip.*did not go through' "$GHS/comment.$(cat "$GHS/comments" 2>/dev/null || echo 0)"

echo "# a PR someone flips ready meanwhile still merges"
admit
echo 4 >"$GHS/ready_from_lookup"
run
check "a flip skipped because the PR went ready meanwhile still merges (exit 0)" [ "$CODE" = 0 ]
check "the merge ran" [ "$(mp_calls 'pr merge')" = 1 ]

echo "# --expect-head: the flip runs only on the head the pre-ready-flip point ended on"
admit
run --expect-head 0000000000000000000000000000000000000000
check "a draft whose evaluated head is not the expected one is refused (exit 4)" [ "$CODE" = 4 ]
check "no flip on an unexpected head" [ "$(mp_calls 'pr ready')" = 0 ]
check "no merge on an unexpected head" [ "$(mp_calls 'pr merge')" = 0 ]
check "an unexpected head is said on the PR (exit 4 once said)" grep -qi 'pre-ready-flip point' "$GHS/comment.1"
admit
run --expect-head "$(mp_origin_head)"
check "the expected head flips and merges (exit 0)" [ "$CODE" = 0 ]
admit
: >"$GHS/ready"
echo 1 >"$GHS/merge_rc"
: >"$GHS/merge_lands"
: >"$GHS/merge_moves"
run
check "a PR merged at another head than the recorded one is not claimed as this merge (exit 4)" [ "$CODE" = 4 ]
check "a merge at another head is said as such" grep -qi 'another head' <<<"$OUT"
check "a merge at another head is said on the PR after the record" grep -qi 'another head' "$GHS/comment.2"

echo "# the merge call's outcome is read from the host"
admit
: >"$GHS/ready"
: >"$GHS/merge_queued"
run
check "a merge the host queued is not reported as merged" grep -q 'not merged yet' <<<"$OUT"
check "a queued merge parks nothing" [ "$(mp_calls 'pr comment')" = 1 ]
admit
: >"$GHS/ready"
echo 1 >"$GHS/merge_rc"
: >"$GHS/merge_lands"
before=$(mp_origin_head)
run
check "a merge that landed despite a failing call is reported merged (exit 0)" [ "$CODE" = 0 ]
check "a landed merge gets no park" [ "$(mp_origin_head)" = "$before" ]
admit
: >"$GHS/ready"
echo 1 >"$GHS/merge_rc"
: >"$GHS/merge_moves"
before=$(mp_origin_head)
run
check "a merge refused because the head moved writes no park" [ "$(mp_origin_head)" = "$before" ]
check "a merge refused because the head moved leaves no local commit" [ "$(gitf rev-parse HEAD)" = "$before" ]
check "the moved head is said on the PR" grep -qi 'head.*moved' "$GHS/comment.2"

echo "# the policy is re-read before the merge call"
admit
: >"$GHS/ready"
printf "printf 'merge_policy: human\\\\n' >'%s/wt/.claude/planwright.local.yml'\n" "$F" >"$GHS/on_comment.1"
run
check "a policy changed after evaluation refuses the merge" [ "$(mp_calls 'pr merge')" = 0 ]
check "the policy change is said on the PR" grep -q 'merge_policy' "$GHS/comment.2"

echo "# a refusal whose comment cannot be written exits 5"
admit
: >"$GHS/ready"
on_comment 1 "$MP_BRANCH" late.txt late
echo 2 >"$GHS/comment_rc_at"
run
check "an unrecorded refusal exits 5" [ "$CODE" = 5 ]

echo "# host text reaches a comment inert"
admit
mp_policy 'merge_policy: policy-class' 'merge_class_max_lines: 100' 'merge_class_exclude_paths: docs/*'
mp_commit 'docs: a page' 'docs/@team <!--x.md' x
run
# shellcheck disable=SC2016 # literal backticks of the markdown code span
check "an evidence cell is a code span, so a path cannot mention a team" grep -q '`[^`]*@team[^`]*`' "$GHS/comment.1"
check "an evidence cell cannot open an HTML comment" not grep -q '^[^`]*<!--x' <(grep '^| excluded-paths' "$GHS/comment.1")

echo "# skips"
admit
: >"$GHS/nopr"
run
check "no PR skips cleanly (exit 3)" [ "$CODE" = 3 ]
check "no PR makes no merge call" [ "$(mp_calls 'pr merge')" = 0 ]
admit
run --task '1;x'
check "a malformed task id is a usage error (exit 2)" [ "$CODE" = 2 ]

echo "# the ready-flip modes the helper composes"
mp_fixture '- **Task 1** — which way should the flag go?'
mp_run "$FLIP" awaiting --spec specs/demo --task 1 --base main
check "awaiting reads a base park as live (exit 4)" [ "$CODE" = 4 ]
check "awaiting prints the predicate line" grep -q '^pred	awaiting-input	fail	' <<<"$OUT"
check "awaiting makes no host call" [ "$(mp_calls '')" = 0 ]
mp_fixture
mp_run "$FLIP" awaiting --spec specs/demo --task 1 --base main
check "awaiting passes with no live entry (exit 0)" [ "$CODE" = 0 ]
mp_run "$FLIP" awaiting --spec specs/demo --task 1
check "awaiting without --base is a usage error" [ "$CODE" = 2 ]
mp_run "$FLIP" park --spec specs/demo --task 1 --reason merge-call --base main
check "park writes the segment (exit 4)" [ "$CODE" = 4 ]
check "the parked segment opens with the fixed lead" grep -q '^- \*\*Task 1\*\* — pending ready-flip: merge-call failed on ' <<<"$(mp_origin_tasks)"
mp_run "$FLIP" park --spec specs/demo --task 1 --reason 'Bad Reason'
check "a malformed park reason is a usage error" [ "$CODE" = 2 ]
mp_fixture
mp_policy 'merge_policy: human' 'ready_flip_policy: unit-owner'
mp_run "$FLIP" flip --for-merge --spec specs/demo --task 1
check "flip --for-merge refuses unless merge_policy is policy-class (exit 3)" [ "$CODE" = 3 ]
check "flip --for-merge under human makes no gh call" [ "$(mp_calls '')" = 0 ]
mp_run "$FLIP" reconcile --for-merge --spec specs/demo --task 1
check "--for-merge belongs to evaluate and flip" [ "$CODE" = 2 ]

echo "# no model in the decision path"
check "the helper calls no model or dispatch backend" not grep -Eq '(^|[^[:alnum:]_./-])(claude|anthropic|offload-dispatch)([^[:alnum:]_-]|$)' "$HELPER"

echo "# wiring: who calls the helper"
check "/execute-task calls the helper only under policy-class" grep -Eq 'policy-class.*merge-admitted\.sh|merge-admitted\.sh.*policy-class' <(tr '\n' ' ' <"$REPO_ROOT/skills/execute-task/SKILL.md")
for s in polish self-review tower orchestrate; do
  check "/$s never calls the helper" not grep -q 'merge-admitted\.sh' "$REPO_ROOT/skills/$s/SKILL.md"
done

echo "# the release rule on every passage describing the release approval (REQ-D1.9)"
RULE='never a class admission'
point() { # <n> — release-tagging.md's numbered point <n>, joined to one line
  awk -v n="$1" '$0 ~ "^" n "\\. " { on = 1 } on && $0 ~ "^(" n + 1 "\\. |## )" { exit } on' \
    "$REPO_ROOT/doctrine/release-tagging.md" | tr '\n' ' ' | tr -s ' '
}
for n in 2 5; do
  check "release-tagging point $n states the rule" grep -q "$RULE" <<<"$(point "$n")"
done
check "release-tagging point 2 no longer claims no merge call site exists" not grep -q 'no merge call sites exist' <<<"$(point 2)"
joined() { tr '\n' ' ' <"$1" | tr -s ' '; }
check "the human-gates merge-policy row states the rule" grep -q "^| Executing an authorized merge |.*$RULE" "$REPO_ROOT/doctrine/human-gates.md"
check "the human-gates citation header cites REQ-D1.9 and D-15" grep -q 'REQ-D1.9.*D-15' <<<"$(sed -n '/^Citations:/,/^$/p' "$REPO_ROOT/doctrine/human-gates.md" | tr '\n' ' ')"
check "guard-catalog's approval line states the rule" grep -q "approval the human merge under every .merge_policy. value (a release PR is $RULE" <<<"$(joined "$REPO_ROOT/doctrine/guard-catalog.md")"
for d in human-gates release-tagging guard-catalog; do
  check "the doctrine README row of $d.md states the rule" grep -q "^| \[$d.md\].*$RULE.*REQ-D1.9" "$REPO_ROOT/doctrine/README.md"
done
check "getting-started's release step states the rule" grep -q "2\. \*\*You merge the release PR\.\*\*.*$RULE" <<<"$(joined "$REPO_ROOT/docs/getting-started.md")"
check "the release-please template README states the rule twice" [ "$(joined "$REPO_ROOT/templates/release-please/README.md" | grep -o "$RULE" | wc -l | tr -d ' ')" -ge 2 ]

echo "merge-admitted: $passes passed, $failures failed"
[ "$failures" = 0 ]
