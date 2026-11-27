#!/bin/bash
# Tests for the readiness walk's handling of the bot review, which runs on the
# draft when a review is requested: a draft with no PR-Agent run at its head,
# and nothing else owing but the post-pr point that waits on it, is told to
# request the review (`request-review`); a draft whose run is still going or
# failed is not-ready; the flip comes only once the run finished green with its
# findings answered, so a ready pull request can merge at once.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-request-review.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-readiness-request-review.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 143' HUP INT TERM

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
{
  printf 'ready_flip_policy: unit-owner\n'
  grep '^steps_' "$repo_root/config/defaults.yml"
} | write_core_defaults
cp "$repo_root/config/steps.yaml" "$core/config/steps.yaml"
mkdir -p "$core/skills/polish"
printf -- '---\nname: polish\ndescription: fixture stand-in\n---\n' >"$core/skills/polish/SKILL.md"
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF
mkdir -p "$mchome"
printf '# format: 1\nready\tprogram\t*\tsteps\tpolish\n' >"$mchome/gates.tsv"

H=1111111111111111111111111111111111111111
FLIP_T=2026-11-18T00:42:21Z

# A pull request with nothing wrong at its head, then the rows each case adds
# (a row's commas are tabs, one row per argument) after dropping any row a
# case's sed expression names.
base_rows() {
  cat <<EOF
# format: 1
head	$H
repo	acme/web
path	src/app.c
check	build	SUCCESS
thread	t1	resolved
step	polish	applied	$H
cadence	audited	$H
guard	ready-guard	pass	-
EOF
}
walk_rows() { # walk_rows <label> <row>...
  base_rows >"$tmp/ev"
  shift
  for r in "$@"; do printf '%s\n' "$r" | tr ',' '\t' >>"$tmp/ev"; done
  mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
}
lacks() { # lacks <label> <needle>
  case $OUT in
    *"$2"*)
      fail "$1: stdout holds '$2'"
      printf '%s\n' "$OUT" >&2
      ;;
    *) ok "$1" ;;
  esac
}
first_line() { printf '%s\n' "$OUT" | head -n 1; }

DRAFT="state,draft require,pr-agent"
READY_SPEC="state,ready flip,$FLIP_T require,pr-agent"
POST_PR_GAP="cadence,gap,post-pr,incomplete,-"

BOT_DUE="pending${tab}bot-review${tab}no PR-Agent run at 111111111111; request a review (scripts/request-reviewer.sh) on the draft, then wait for the run it fires"
POST_PR_WAITS="; pending the bot review (PR-Agent) a review request fires, which a post-pr step may wait on"
GREEN_RUN="check,PR-Agent,SUCCESS"

# ---------------------------------------------------------------------------
# A draft with no PR-Agent run at its head is told to request the review.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086
walk_rows "draft, post-pr incomplete" $DRAFT "$POST_PR_GAP"
expect_rc "a draft whose bot review has not run is not merge-ready" 4
expect_eq "the verdict is the request token with the head, then what waits" "request-review${tab}$H
$BOT_DUE
pending${tab}post-pr${tab}no completion record$POST_PR_WAITS"
lacks "and names no failure" "fail${tab}"
lacks "and never tells the caller to flip" "flip-for-review"
# shellcheck disable=SC2086
walk_rows "draft, post-pr step missing" $DRAFT "cadence,gap,post-pr,missing,bot-review"
expect_eq "a post-pr step never recorded reads the same" "request-review${tab}$H
$BOT_DUE
pending${tab}post-pr${tab}bot-review is missing$POST_PR_WAITS"
# shellcheck disable=SC2086
walk_rows "draft, two post-pr gaps" $DRAFT "$POST_PR_GAP" "cadence,gap,post-pr,missing,peer-review"
expect_out "each pending row is printed" "pending${tab}post-pr${tab}no completion record"
expect_out "the second too" "pending${tab}post-pr${tab}peer-review is missing"
# shellcheck disable=SC2086
walk_rows "draft, bypass check" $DRAFT "$POST_PR_GAP" "bypass,window-lock,FAILURE"
expect_out "a bypass row follows the request verdict, as it does a ready one" "may wait on
bypass${tab}window-lock${tab}FAILURE"
# shellcheck disable=SC2086
walk_rows "draft, spec-only" $DRAFT "$POST_PR_GAP" "scope,spec-only,$H"
expect_rc "a spec-only draft is held for its sign-off alone, its review left to the flip (r-18)" 0
expect_eq "and reads ready, its cadence never held" "ready${tab}$H"
# shellcheck disable=SC2086
walk_rows "ready, spec-only, no run yet" $READY_SPEC "scope,spec-only,$H"
expect_rc "once flipped, a spec-only pull request still needs the run its flip fired" 4
expect_out "named" "fail${tab}bot-review${tab}no PR-Agent run at 111111111111"
# shellcheck disable=SC2086
walk_rows "draft, nothing owing" $DRAFT
expect_rc "a draft with no gap but no bot review is not flip-ready" 4
expect_eq "it is told to request the review" "request-review${tab}$H
$BOT_DUE"
# shellcheck disable=SC2086
walk_rows "draft, label opt-out" $DRAFT "check,PR-Agent,SKIPPED"
expect_rc "a skipped run on the draft (the skip-pr-agent label) is the opt-out" 0

# ---------------------------------------------------------------------------
# The flip waits for the draft's run: one still going, or red, holds it.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086
walk_rows "draft, PR-Agent run pending" $DRAFT "$POST_PR_GAP" "check,PR-Agent,PENDING"
expect_rc "a draft whose PR-Agent run is still going is not flip-ready" 4
case $(first_line) in "not-ready${tab}$H") ok "a running draft review opens not-ready" ;; *) fail "a running draft review opens '$(first_line)'" ;; esac
expect_out "the running run is named" "fail${tab}check${tab}PR-Agent is PENDING"
lacks "and no request token: one was made" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "draft, PR-Agent run in progress, nothing else owing" $DRAFT "check,PR-Agent,IN_PROGRESS"
expect_rc "a draft review in progress holds the flip with nothing else owing" 4
expect_out "named" "fail${tab}check${tab}PR-Agent is IN_PROGRESS"
# shellcheck disable=SC2086
walk_rows "draft, PR-Agent run failed" $DRAFT "check,PR-Agent,FAILURE"
expect_rc "a draft whose PR-Agent run failed is not flip-ready" 4
expect_out "named" "fail${tab}check${tab}PR-Agent is FAILURE"

# ---------------------------------------------------------------------------
# Once the draft's run finished, post-pr settles it, then the flip.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086
walk_rows "draft, run finished, post-pr incomplete" $DRAFT "$POST_PR_GAP" "$GREEN_RUN"
expect_rc "a finished draft review leaves post-pr to complete" 4
expect_out "the post-pr gap is a gap now" "fail${tab}cadence${tab}post-pr: no completion record"
lacks "and no request token" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "draft, run finished, finding open" $DRAFT "$GREEN_RUN" "finding,github-actions[bot],t9,unanswered"
expect_rc "an unanswered finding of the draft's run holds the flip" 4
expect_out "named" "fail${tab}finding${tab}github-actions[bot] t9 is unanswered"
# shellcheck disable=SC2086
walk_rows "draft, run finished, nothing owing" $DRAFT "$GREEN_RUN"
expect_rc "a draft whose review finished green with nothing owing is flip-ready" 0
expect_eq "and reads ready" "ready${tab}$H"

# ---------------------------------------------------------------------------
# Any other gap keeps it not-ready, naming that gap.
# ---------------------------------------------------------------------------
other_gap() { # other_gap <label> <want> <row>...
  label=$1 want=$2
  shift 2
  # shellcheck disable=SC2086
  walk_rows "$label" $DRAFT "$POST_PR_GAP" "$@"
  expect_rc "$label: not-ready, not a request" 4
  case $(first_line) in "not-ready${tab}$H") ok "$label: opens not-ready" ;; *) fail "$label: opens '$(first_line)'" ;; esac
  expect_out "$label: named" "$want"
  lacks "$label: no request token" "request-review${tab}"
}
other_gap "red check" "fail${tab}check${tab}lint is FAILURE" "check,lint,FAILURE"
other_gap "unfinished check" "fail${tab}check${tab}ci is IN_PROGRESS" "check,ci,IN_PROGRESS"
other_gap "merge conflict" "fail${tab}guard${tab}ready-guard: the pull request conflicts with main" "guard,ready-guard,fail,the pull request conflicts with main"
other_gap "open thread" "fail${tab}thread${tab}t9 is open" "thread,t9,open"
other_gap "unanswered finding" "fail${tab}finding${tab}cubic-dev-ai[bot] t9 is unanswered" "finding,cubic-dev-ai[bot],t9,unanswered"
other_gap "pre-pr gap" "fail${tab}cadence${tab}pre-pr: no completion record" "cadence,gap,pre-pr,incomplete,-"
other_gap "macOS never ran" "fail${tab}macos${tab}macos-suite never ran at 111111111111" "require,macos"
other_gap "unaudited cadence" "fail${tab}cadence${tab}not audited: no worktree holds the branch" "cadence,unaudited,no worktree holds the branch"
other_gap "post-pr record the truth check refuses" "fail${tab}cadence${tab}not audited: post-pr: bot-review fails the step-record truth check" "cadence,gap,post-pr,unaudited,bot-review"
other_gap "cadence audited at another head" "fail${tab}cadence${tab}the configured cadence was not audited at 111111111111" "cadence,audited,2222222222222222222222222222222222222222"
other_gap "failed post-pr step" "fail${tab}cadence${tab}post-pr: bot-review recorded halted" "cadence,gap,post-pr,failed,bot-review:halted"

# A post-pr gap that is not the wait for the draft's review stays a gap.
# shellcheck disable=SC2086
walk_rows "draft, no PR-Agent in the repository" "state,draft" "$POST_PR_GAP"
expect_rc "without PR-Agent there is no review to wait for" 4
expect_out "the post-pr gap is named" "fail${tab}cadence${tab}post-pr: no completion record"
lacks "and no request token" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "draft, stale post-pr" $DRAFT "cadence,gap,post-pr,stale,2222222222222222222222222222222222222222"
expect_out "a post-pr completion at another head stays a gap" "fail${tab}cadence${tab}post-pr: completed only at 222222222222"
lacks "and no request token either" "request-review${tab}"
# A post-pr completion outside the pull request's own history (another unit's,
# left in a reused worktree) is no completion at this head.
FOREIGN_GAP="cadence,gap,post-pr,foreign,2222222222222222222222222222222222222222"
FOREIGN_DETAIL="completed only outside the history of this pull request, newest at 222222222222"
# shellcheck disable=SC2086
walk_rows "draft, foreign post-pr" $DRAFT "$FOREIGN_GAP"
expect_rc "a draft whose only post-pr completion is another unit's is not merge-ready" 4
expect_eq "it is pending the review, naming the foreign head" "request-review${tab}$H
$BOT_DUE
pending${tab}post-pr${tab}$FOREIGN_DETAIL$POST_PR_WAITS"
# shellcheck disable=SC2086
walk_rows "draft, foreign post-pr, no PR-Agent" "state,draft" "$FOREIGN_GAP"
expect_out "without PR-Agent it stays a gap" "fail${tab}cadence${tab}post-pr: $FOREIGN_DETAIL"
lacks "with no request token" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "draft, foreign post-pr beside another gap" $DRAFT "$FOREIGN_GAP" "check,lint,FAILURE"
case $(first_line) in "not-ready${tab}$H") ok "a foreign post-pr beside a red check stays not-ready" ;; *) fail "foreign post-pr beside a red check opens '$(first_line)'" ;; esac

# ---------------------------------------------------------------------------
# A ready pull request needs a finished run at its head, its findings
# answered: the draft's run, from before the flip, is the one wanted.
# ---------------------------------------------------------------------------
READY="state,ready flip,$FLIP_T require,pr-agent"
# shellcheck disable=SC2086
walk_rows "ready, post-pr incomplete" $READY "$POST_PR_GAP" "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a ready pull request with the post-pr gap is not merge-ready" 4
expect_out "named" "fail${tab}cadence${tab}post-pr: no completion record"
lacks "and no request token: it is already flipped" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "ready, foreign post-pr" $READY "$FOREIGN_GAP" "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a ready pull request whose only post-pr completion is another unit's is not merge-ready" 4
expect_out "named as a gap" "fail${tab}cadence${tab}post-pr: $FOREIGN_DETAIL"
lacks "and no request token" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "ready, flipped while the review ran" $READY "check,PR-Agent,IN_PROGRESS" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a flip made while the draft's review still ran is not merge-ready" 4
expect_out "named a too-early flip" "fail${tab}flip${tab}PR-Agent was still running at the flip (run created 2026-11-18T00:40:10Z, before the flip at $FLIP_T): a too-early flip"
# shellcheck disable=SC2086
walk_rows "ready, hand flip, run still running" $READY "check,PR-Agent,IN_PROGRESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a run a hand flip fired, still running, is not merge-ready" 4
expect_out "named as the flip's own run" "fail${tab}check${tab}PR-Agent is IN_PROGRESS (run created 2026-11-18T00:42:23Z, after the flip"
# shellcheck disable=SC2086
walk_rows "ready, no run yet" $READY
expect_rc "a ready pull request with no PR-Agent run yet is not merge-ready" 4
expect_out "named, with the request that starts one" "fail${tab}bot-review${tab}no PR-Agent run at 111111111111; request a review (scripts/request-reviewer.sh)"
# shellcheck disable=SC2086
walk_rows "ready, the draft's run finished before the flip" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a green PR-Agent run from before the flip is the review the flip waited for" 0
expect_eq "and reads ready" "ready${tab}$H"
# shellcheck disable=SC2086
walk_rows "ready, run time unread" $READY "check,PR-Agent,SUCCESS"
expect_rc "a finished green run needs no creation time" 0
# shellcheck disable=SC2086
walk_rows "ready, pending run time unread" $READY "check,PR-Agent,QUEUED"
expect_rc "a pending run of unknown creation still holds merge-ready" 4
expect_out "named plainly pending" "fail${tab}check${tab}PR-Agent is QUEUED"
# shellcheck disable=SC2086
walk_rows "ready, no flip time" "state,ready" "require,pr-agent" "check,PR-Agent,SUCCESS"
expect_rc "a pull request opened ready needs only the finished run" 0
# shellcheck disable=SC2086
walk_rows "ready, a green run beside a red one" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z" "check,PR-Agent (review),FAILURE" "born,PR-Agent (review),2026-11-18T00:40:10Z"
expect_out "the red run still counts as a check" "fail${tab}check${tab}PR-Agent (review) is FAILURE"
lacks "and the bot-review refusal is not raised" "fail${tab}bot-review"
# shellcheck disable=SC2086
walk_rows "ready, hand flip's run finished" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a finished run a hand flip fired, with nothing owing, is merge-ready" 0
# shellcheck disable=SC2086
walk_rows "ready, run finished, finding open" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z" "finding,github-actions[bot],t9,unanswered"
expect_rc "an unanswered finding holds merge-ready" 4
expect_out "named" "fail${tab}finding${tab}github-actions[bot] t9 is unanswered"
# shellcheck disable=SC2086
walk_rows "ready, run finished, finding answered" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z" "finding,github-actions[bot],t9,answered"
expect_rc "once its findings are answered it is merge-ready" 0
# shellcheck disable=SC2086
walk_rows "ready, label opt-out" $READY "check,PR-Agent,SKIPPED" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a skipped run (the skip-pr-agent label) is the opt-out" 0

# ---------------------------------------------------------------------------
# A re-run after a fix round reviews the current head, but its check stays on
# the commit the run was first fired at, so no PR-Agent check reaches the head.
# The run's own marker comment names the head instead.
# ---------------------------------------------------------------------------
MARK="botmark,github-actions[bot],4475.3,$H,success,2026-11-18T01:00:00Z"
ATT="botattempt,4475.3,PR-Agent,2026-11-18T00:50:00Z,SUCCESS"
NO_RUN="fail${tab}bot-review${tab}no PR-Agent run at 111111111111"
marker_refused() { # marker_refused <label> <why> <row>...
  label=$1 why=$2
  shift 2
  # shellcheck disable=SC2086
  walk_rows "$label" $READY "$@"
  expect_rc "$label: not merge-ready" 4
  expect_out "$label: no PR-Agent run counted" "$NO_RUN"
  expect_out "$label: the marker's refusal named" "$why"
}
# shellcheck disable=SC2086
walk_rows "ready, re-run marker names the head" $READY "$MARK" "$ATT"
expect_rc "a re-run whose marker names the current head is the bot review" 0
expect_eq "and reads ready" "ready${tab}$H"
# shellcheck disable=SC2086
walk_rows "ready, re-run marker beside a pre-flip check at the head" $READY "$MARK" "$ATT" "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a re-run's marker counts beside an older check at the head" 0
marker_refused "marker names an older head" "run marker 4475.3 names 222222222222, not the head" \
  "botmark,github-actions[bot],4475.3,2222222222222222222222222222222222222222,success,2026-11-18T01:00:00Z" "$ATT"
marker_refused "marker names a prefix of the head" "run marker 4475.3 names 111111111111, not the head" \
  "botmark,github-actions[bot],4475.3,111111111111,success,2026-11-18T01:00:00Z" "$ATT"
marker_refused "marker posted by a person" "run marker 4475.3 was posted by alice, not the PR-Agent workflow" \
  "botmark,alice,4475.3,$H,success,2026-11-18T01:00:00Z" "$ATT"
marker_refused "marker posted by another bot" "run marker 4475.3 was posted by cubic-dev-ai[bot], not the PR-Agent workflow" \
  "botmark,cubic-dev-ai[bot],4475.3,$H,success,2026-11-18T01:00:00Z" "$ATT"
marker_refused "marker status failure" "run marker 4475.3 reports failure" \
  "botmark,github-actions[bot],4475.3,$H,failure,2026-11-18T01:00:00Z" "$ATT"
marker_refused "a later marker of the same attempt reports failure" "run marker 4475.3 reports failure" \
  "$MARK" "botmark,github-actions[bot],4475.3,$H,failure,2026-11-18T01:05:00Z" "$ATT"
marker_refused "a newer failing marker listed first" "run marker 4475.3 reports failure" \
  "botmark,github-actions[bot],4475.3,$H,failure,2026-11-18T01:05:00Z" "$MARK" "$ATT"
# shellcheck disable=SC2086
walk_rows "ready, an older failing marker listed last" $READY "botmark,github-actions[bot],4475.3,$H,success,2026-11-18T01:05:00Z" "$MARK" "botmark,github-actions[bot],4475.3,$H,failure,2026-11-18T00:59:00Z" "$ATT"
expect_rc "the latest marker of an attempt is judged, not the last listed" 0
marker_refused "marker names no commit" "run marker 4475.3 names no commit, not the head" \
  "botmark,github-actions[bot],4475.3,,success,2026-11-18T01:00:00Z" "$ATT"
# shellcheck disable=SC2086
walk_rows "ready, a person's later failing marker for the same attempt" $READY "$MARK" "botmark,alice,4475.3,$H,failure,2026-11-18T01:10:00Z" "$ATT"
expect_rc "a person's marker never overrides the workflow's for the same attempt" 0
# shellcheck disable=SC2086
walk_rows "ready, attempt started at the flip" $READY "$MARK" "botattempt,4475.3,PR-Agent,$FLIP_T,SUCCESS"
expect_rc "an attempt that started at the flip counts" 0
# shellcheck disable=SC2086
walk_rows "ready, good marker beside a red PR-Agent check" $READY "$MARK" "$ATT" "check,PR-Agent,FAILURE" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a good marker never clears a red check at the head" 4
expect_out "the red check is still named" "fail${tab}check${tab}PR-Agent is FAILURE"
# shellcheck disable=SC2086
walk_rows "ready, green check beside a refused marker" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z" "botmark,alice,4475.3,$H,success,2026-11-18T01:00:00Z" "$ATT"
expect_rc "a green check at the head is the bot review whatever a refused marker says" 0
# shellcheck disable=SC2086
walk_rows "ready, attempt started before the flip" $READY "$MARK" "botattempt,4475.3,PR-Agent,2026-11-18T00:40:00Z,SUCCESS"
expect_rc "a draft run's marker, from before the flip, is the bot review" 0
marker_refused "attempt start unread" "run attempt 4475.3 has no start time read" \
  "$MARK" "botattempt,4475.3,PR-Agent,,SUCCESS"
marker_refused "attempt not read" "run attempt 4475.3 was not read" "$MARK"
marker_refused "attempt still running" "run attempt 4475.3 is IN_PROGRESS" \
  "$MARK" "botattempt,4475.3,PR-Agent,2026-11-18T00:50:00Z,IN_PROGRESS"
marker_refused "attempt of another workflow" "run attempt 4475.3 belongs to ci, not PR-Agent" \
  "$MARK" "botattempt,4475.3,ci,2026-11-18T00:50:00Z,SUCCESS"
# shellcheck disable=SC2086
walk_rows "ready, a refused marker beside a good one" $READY "botmark,alice,9.1,$H,success,2026-11-18T01:10:00Z" "$MARK" "$ATT"
expect_rc "one good marker is enough" 0
walk_rows "ready, no flip time, re-run marker" "state,ready" "require,pr-agent" "$MARK" "$ATT"
expect_rc "a pull request opened ready has no flip to date the re-run against" 0
# shellcheck disable=SC2086
walk_rows "draft, re-run marker" $DRAFT "$MARK" "$ATT"
expect_eq "a draft's marker naming its head is its bot review" "ready${tab}$H"
# shellcheck disable=SC2086
walk_rows "draft, good marker beside a red PR-Agent check" $DRAFT "$MARK" "$ATT" "check,PR-Agent,FAILURE"
expect_rc "a good marker never clears a red check on the draft" 4
expect_out "the red check is named" "fail${tab}check${tab}PR-Agent is FAILURE"
lacks "and no request token" "request-review${tab}"
# shellcheck disable=SC2086
walk_rows "draft, refused marker" $DRAFT "botmark,alice,4475.3,$H,success,2026-11-18T01:00:00Z" "$ATT"
expect_rc "a draft whose only marker is refused still needs the review" 4
expect_out "it is told to request it, naming the refused marker" "$BOT_DUE; run marker 4475.3 was posted by alice, not the PR-Agent workflow"

# ---------------------------------------------------------------------------
# The contract names the token.
# ---------------------------------------------------------------------------
mc_run mc-readiness.sh --help
expect_out "--help states the request verdict" "request-review<TAB><head>"
lacks "--help no longer names the flip-first verdict" "flip-for-review"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-request-review: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-request-review: all passed"
