#!/bin/bash
# Suite for scripts/ready-flip.sh: every precondition, the PR record and its
# ordering against the flip, the parking segment and its composition, the
# skips, the transient retry, the precondition hand-in, and the wiring that
# keeps a standalone review run and the human policy away from the helper.
#
# Hermetic: each case builds a throwaway origin (a bare repository) and a unit
# clone on a task branch, and a stub `gh` answers from files, reporting the
# PR head as whatever the bare origin holds for the branch, so a park or
# unpark push moves the "PR head" the way GitHub would. Nothing here reaches a
# real host.
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

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/ready-flip.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
STUBBIN="$SANDBOX/bin"
mkdir -p "$STUBBIN" "$SANDBOX/nohooks" "$SANDBOX/noadopter"

# The gh stub. Calls are logged one per line; answers come from files under
# $GHS. The PR head is read from the bare origin, never from a file.
cat >"$STUBBIN/gh" <<'GHSTUB'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf ' %s' "$a"; done
  printf '\n'
} >>"$GHS/log"
head=$(git --git-dir="$GHS_ORIGIN" rev-parse --verify -q "refs/heads/$GHS_BRANCH" 2>/dev/null)
draft=true
[ ! -f "$GHS/ready" ] || draft=false
case "$1 $2" in
  'pr view')
    case "$*" in
      *statusCheckRollup*)
        n=0
        [ ! -f "$GHS/rollup_n" ] || n=$(cat "$GHS/rollup_n")
        n=$((n + 1))
        echo "$n" >"$GHS/rollup_n"
        if [ -f "$GHS/rollup_fail_until" ] && [ "$n" -le "$(cat "$GHS/rollup_fail_until")" ]; then
          echo 'HTTP 502: Bad Gateway' >&2
          exit 1
        fi
        [ ! -f "$GHS/head_override" ] || head=$(cat "$GHS/head_override")
        # head_lag_until reports a stale head for the first n reads.
        [ ! -f "$GHS/head_lag_until" ] || [ "$n" -gt "$(cat "$GHS/head_lag_until")" ] \
          || head=0123456789012345678901234567890123456789
        case $(cat "$GHS/ci") in
          green) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"lint","state":"SUCCESS"}]' ;;
          failing) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
          pending) roll='[{"__typename":"CheckRun","name":"test","status":"IN_PROGRESS","conclusion":""}]' ;;
          none) roll='[]' ;;
          own-status-red) roll='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"planwright/pre-ready-flip","state":"FAILURE"},{"__typename":"StatusContext","context":"planwright/pre-spec-ready-flip","state":"PENDING"}]' ;;
          own-status-only) roll='[{"__typename":"StatusContext","context":"planwright/pre-ready-flip","state":"SUCCESS"}]' ;;
        esac
        printf '{"headRefOid":"%s","statusCheckRollup":%s}\n' "$head" "$roll"
        ;;
      *'--jq .headRefOid'*)
        h=0
        [ ! -f "$GHS/pin_n" ] || h=$(cat "$GHS/pin_n")
        h=$((h + 1))
        echo "$h" >"$GHS/pin_n"
        [ ! -f "$GHS/head_override" ] || head=$(cat "$GHS/head_override")
        [ ! -f "$GHS/head_at_flip" ] || head=$(cat "$GHS/head_at_flip")
        # head_after_record moves the head from the second re-read on.
        [ ! -f "$GHS/head_after_record" ] || [ "$h" -lt 2 ] || head=$(cat "$GHS/head_after_record")
        printf '%s\n' "$head"
        ;;
      *mergeable*)
        printf '{"baseRefName":"main","headRefOid":"%s","isDraft":%s,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}\n' "$head" "$draft"
        ;;
      *)
        if [ -f "$GHS/nopr" ]; then
          echo "no pull requests found for branch \"$GHS_BRANCH\"" >&2
          exit 1
        fi
        l=0
        [ ! -f "$GHS/lookup_n" ] || l=$(cat "$GHS/lookup_n")
        l=$((l + 1))
        echo "$l" >"$GHS/lookup_n"
        if [ -f "$GHS/lookup_fail_until" ] && [ "$l" -le "$(cat "$GHS/lookup_fail_until")" ]; then
          echo 'HTTP 502: Bad Gateway' >&2
          exit 1
        fi
        base=main
        [ ! -f "$GHS/base" ] || base=$(cat "$GHS/base")
        fork=false
        [ ! -f "$GHS/fork" ] || fork=true
        printf '{"number":42,"isDraft":%s,"state":"OPEN","baseRefName":"%s","headRefName":"%s","headRefOid":"%s","isCrossRepository":%s}\n' "$draft" "$base" "$GHS_BRANCH" "$head" "$fork"
        ;;
    esac
    ;;
  'api '*)
    if [ -f "$GHS/behind" ]; then cat "$GHS/behind"; else echo 0; fi
    ;;
  'pr comment')
    c=0
    [ ! -f "$GHS/comments" ] || c=$(cat "$GHS/comments")
    c=$((c + 1))
    echo "$c" >"$GHS/comments"
    prev=''
    for a in "$@"; do
      [ "$prev" != --body-file ] || cp "$a" "$GHS/comment.$c"
      prev=$a
    done
    rc=0
    [ ! -f "$GHS/comment_rc" ] || rc=$(cat "$GHS/comment_rc")
    exit "$rc"
    ;;
  'pr ready')
    rc=0
    [ ! -f "$GHS/ready_rc" ] || rc=$(cat "$GHS/ready_rc")
    [ "$rc" != 0 ] || : >"$GHS/ready"
    exit "$rc"
    ;;
  *) exit 3 ;;
esac
GHSTUB
chmod +x "$STUBBIN/gh"

BRANCH=planwright/demo/task-1
TASKS=specs/demo/tasks.md

gitf() { git -C "$F/wt" "$@"; }

write_tasks() { # <awaiting-input body lines...>
  {
    printf '# Demo — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n'
    printf '### Task 1 — One\n\n- **Deliverables:** x\n\n### Task 2 — Two\n\n- **Deliverables:** y\n\n'
    printf '## Awaiting input\n\n'
    if [ "$#" = 0 ]; then printf '(none yet)\n'; else printf '%s\n' "$@"; fi
    printf '\n## Deferred\n\n(none yet)\n'
  } >"$F/wt/$TASKS"
}

# record_review — a convergence completion record naming the current head.
record_review() {
  local run
  run=$(/bin/sh "$STEP_RECORD" --worktree "$F/wt" new-run) || return 1
  /bin/sh "$STEP_RECORD" --worktree "$F/wt" write --completion --run "$run" \
    --point convergence --head "$(gitf rev-parse HEAD)" >/dev/null
}

# fixture [<awaiting-input lines on main>...] — a fresh origin and unit clone.
# The plain fixture is copied from one built template, which keeps the suite
# inside its time budget; a fixture with a base park is built from scratch.
TEMPLATE=''
fixture() {
  if [ "$#" = 0 ] && [ -n "$TEMPLATE" ]; then
    F=$(mktemp -d "$SANDBOX/fx.XXXXXX")
    cp -R "$TEMPLATE/." "$F/"
    gitf remote set-url origin "$F/origin.git"
    GHS="$F/gh"
    return
  fi
  build_fixture "$@"
}
build_fixture() {
  F=$(mktemp -d "$SANDBOX/fx.XXXXXX")
  git init -q --bare -b main "$F/origin.git"
  git clone -q "$F/origin.git" "$F/wt" 2>/dev/null
  gitf config user.name 'Fixture'
  gitf config user.email 'fixture@example.invalid'
  gitf config commit.gpgsign false
  gitf config core.hooksPath "$SANDBOX/nohooks"
  gitf checkout -q -b main 2>/dev/null
  mkdir -p "$F/wt/specs/demo"
  printf '.claude/\n' >"$F/wt/.gitignore"
  write_tasks
  gitf add -A
  gitf commit -q -m 'chore: seed'
  # The unit branch is cut before any human park lands on main.
  if [ "$#" -gt 0 ]; then
    write_tasks "$@"
    gitf commit -q -am 'chore: a human park on main'
    gitf push -q origin main 2>/dev/null
    gitf checkout -q -b "$BRANCH" HEAD~1
  else
    gitf push -q origin main 2>/dev/null
    gitf checkout -q -b "$BRANCH"
  fi
  printf 'work\n' >"$F/wt/feature.txt"
  gitf add feature.txt
  gitf commit -q -m 'feat: the unit'
  gitf push -q -u origin "$BRANCH" 2>/dev/null
  record_review
  GHS="$F/gh"
  mkdir -p "$GHS"
  echo green >"$GHS/ci"
  : >"$GHS/log"
}

set_policy() { # <value>
  mkdir -p "$F/wt/.claude"
  printf 'ready_flip_policy: %s\nready_flip_ci_wait: 30s\n' "$1" >"$F/wt/.claude/planwright.local.yml"
}

# run_helper <args...> — the helper from the unit clone, stub first on PATH.
run_helper() {
  OUT=$(cd "$F/wt" && env PATH="$STUBBIN:$PATH" GHS="$GHS" GHS_ORIGIN="$F/origin.git" \
    GHS_BRANCH="$BRANCH" PLANWRIGHT_REPO_ROOT="$F/wt" PLANWRIGHT_LOCAL_CONFIG= \
    PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/noadopter" PLANWRIGHT_READY_FLIP_POLL_SECONDS=0 \
    PLANWRIGHT_READY_FLIP_MAX_POLLS=3 PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
    /bin/bash "$HELPER" "$@" 2>&1)
  CODE=$?
}

calls() { grep -c "^CALL $1" "$GHS/log" 2>/dev/null || true; }
rollups() { grep -c 'statusCheckRollup' "$GHS/log" 2>/dev/null || true; }
first_line_of() { grep -n "^CALL $1" "$GHS/log" | head -1 | cut -d: -f1; }
origin_tasks() { git --git-dir="$F/origin.git" show "refs/heads/$BRANCH:$TASKS"; }
origin_head() { git --git-dir="$F/origin.git" rev-parse "refs/heads/$BRANCH"; }
bullet() { origin_tasks | grep '^- \*\*Task 1\*\*'; }
leads() { origin_tasks | grep -o 'pending ready-flip:' | wc -l | tr -d ' '; }
placeholder_in_section() { origin_tasks | sed -n '/^## Awaiting input/,/^## Deferred/p' | grep -q 'none yet'; }
head_trailer_is() { git --git-dir="$F/origin.git" log -1 --format=%B "refs/heads/$BRANCH" | grep -qx "$1"; }
commits_since() { git --git-dir="$F/origin.git" rev-list --count "$1..refs/heads/$BRANCH"; }
changed_since() { git --git-dir="$F/origin.git" diff --name-only "$1" "refs/heads/$BRANCH"; }

if [ ! -f "$HELPER" ]; then
  fail "the helper exists at scripts/ready-flip.sh"
  echo "ready-flip: $passes passed, $failures failed" >&2
  exit 1
fi

build_fixture
TEMPLATE=$F

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
check "a pass writes no park" [ "$(leads)" = 0 ]
check "the handoff says flipped" grep -q 'flipped' <<<"$OUT"

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

echo "# another task's bullet does not block this unit"
fixture '- **Task 2** — halt: unrelated'
set_policy unit-owner
run_helper flip --spec specs/demo --task 1
check "a bullet for another task does not block (exit 0)" [ "$CODE" = 0 ]

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
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
/bin/sh "$STEP_RECORD" --worktree "$F/wt" write --run "$run" --point convergence --step polish \
  --kind skill --target polish --hosting in-session --backend terminal --head "$(gitf rev-parse HEAD)" \
  --start "$now" --end "$now" --outcome failed >/dev/null
/bin/sh "$STEP_RECORD" --worktree "$F/wt" write --completion --run "$run" --point convergence \
  --head "$(gitf rev-parse HEAD)" >/dev/null
run_helper flip --spec specs/demo --task 1
check "a failed review step parks (exit 4)" [ "$CODE" = 4 ]
check "the park names review-converged" grep -q 'review-converged' <<<"$(bullet)"

echo "# CI: pending past the wait, an empty rollup, transient failures, own contexts"
fixture
set_policy unit-owner
echo pending >"$GHS/ci"
run_helper flip --spec specs/demo --task 1
check "a rollup still pending at the bound parks (exit 4)" [ "$CODE" = 4 ]
check "the wait polled to its bound" [ "$(rollups)" = 3 ]
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
check "the failed reads were retried" [ "$(rollups)" = 3 ]
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
check "the park names flip-call" grep -q 'pending ready-flip: flip-call' <<<"$(bullet)"

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
for t in git jq sh bash cat sed awk grep tr date mktemp head tail wc cut sort printf env dirname basename rm mv cp mkdir timeout sleep; do
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

echo "# a tasks.md that cannot be written is never committed"
fixture
set_policy unit-owner
echo failing >"$GHS/ci"
chmod 444 "$F/wt/$TASKS"
before=$(gitf rev-parse HEAD)
run_helper flip --spec specs/demo --task 1
chmod 644 "$F/wt/$TASKS"
check "an unwritable tasks.md exits 5" [ "$CODE" = 5 ]
check "an unwritable tasks.md makes no commit" [ "$(gitf rev-parse HEAD)" = "$before" ]
check "an unwritable tasks.md is named" grep -q 'could not be written' <<<"$OUT"
check "an unwritable tasks.md keeps its content" grep -q '### Task 1' "$F/wt/$TASKS"

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
check "the CI wait ran once in total" [ "$(rollups)" = "$before" ]
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
check "a hand-in for another head is not trusted: the CI wait re-runs" [ "$(rollups)" = 2 ]

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

echo "ready-flip: $passes passed, $failures failed"
[ "$failures" = 0 ]
