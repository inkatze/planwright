#!/bin/bash
# Tests for the readiness walk's handling of the bot review that the ready
# flip fires: a draft whose only gap is the post-pr point is told to flip
# (`flip-for-review`), any other gap keeps it not-ready, and a ready pull
# request needs the run the flip fired, finished, with its findings answered.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-flip-review.sh
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-readiness-flip-review.XXXXXX") || exit 1
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
POST_PR_GAP="cadence,gap,post-pr,incomplete,-"

# ---------------------------------------------------------------------------
# A draft whose only gap is the post-pr point is told to flip.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086
walk_rows "draft, post-pr incomplete" $DRAFT "$POST_PR_GAP"
expect_rc "a draft whose only gap is post-pr is not merge-ready" 4
expect_eq "the verdict is the flip token with the head, then what waits" "flip-for-review${tab}$H
pending${tab}post-pr${tab}no completion record; pending the flip, which fires the bot review (PR-Agent) a post-pr step may wait on"
lacks "and names no failure" "fail${tab}"
# shellcheck disable=SC2086
walk_rows "draft, post-pr step missing" $DRAFT "cadence,gap,post-pr,missing,bot-review"
expect_eq "a post-pr step never recorded reads the same" "flip-for-review${tab}$H
pending${tab}post-pr${tab}bot-review is missing; pending the flip, which fires the bot review (PR-Agent) a post-pr step may wait on"
# shellcheck disable=SC2086
walk_rows "draft, two post-pr gaps" $DRAFT "$POST_PR_GAP" "cadence,gap,post-pr,missing,peer-review"
expect_out "each pending row is printed" "pending${tab}post-pr${tab}no completion record"
expect_out "the second too" "pending${tab}post-pr${tab}peer-review is missing"
# shellcheck disable=SC2086
walk_rows "draft, bypass check" $DRAFT "$POST_PR_GAP" "bypass,window-lock,FAILURE"
expect_out "a bypass row follows the flip verdict, as it does a ready one" "may wait on
bypass${tab}window-lock${tab}FAILURE"
# shellcheck disable=SC2086
walk_rows "draft, spec-only" $DRAFT "$POST_PR_GAP" "scope,spec-only,$H"
expect_eq "a spec-only pull request is held for its sign-off, never told to flip" "ready${tab}$H"
# shellcheck disable=SC2086
walk_rows "draft, pending PR-Agent run" $DRAFT "$POST_PR_GAP" "check,PR-Agent,PENDING"
case $(first_line) in "flip-for-review${tab}$H") ok "a draft's own PR-Agent check is left out of the walk" ;; *) fail "a draft's PR-Agent check held the flip verdict: $OUT" ;; esac
# shellcheck disable=SC2086
walk_rows "draft, nothing owing" $DRAFT
expect_rc "a draft with no post-pr gap is flip-ready as before" 0
expect_eq "and reads ready" "ready${tab}$H"

# ---------------------------------------------------------------------------
# Any other gap keeps it not-ready, naming that gap.
# ---------------------------------------------------------------------------
other_gap() { # other_gap <label> <want> <row>...
  label=$1 want=$2
  shift 2
  # shellcheck disable=SC2086
  walk_rows "$label" $DRAFT "$POST_PR_GAP" "$@"
  expect_rc "$label: not-ready, not a flip" 4
  case $(first_line) in "not-ready${tab}$H") ok "$label: opens not-ready" ;; *) fail "$label: opens '$(first_line)'" ;; esac
  expect_out "$label: named" "$want"
  lacks "$label: no flip token" "flip-for-review"
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

# A post-pr gap that is not the wait for the flip's run stays a gap.
# shellcheck disable=SC2086
walk_rows "draft, no PR-Agent in the repository" "state,draft" "$POST_PR_GAP"
expect_rc "without PR-Agent there is no flip to wait for" 4
expect_out "the post-pr gap is named" "fail${tab}cadence${tab}post-pr: no completion record"
lacks "and no flip token" "flip-for-review"
# shellcheck disable=SC2086
walk_rows "draft, stale post-pr" $DRAFT "cadence,gap,post-pr,stale,2222222222222222222222222222222222222222"
expect_out "a post-pr completion at another head stays a gap" "fail${tab}cadence${tab}post-pr: completed only at 222222222222"
lacks "and no flip token either" "flip-for-review"
# A post-pr completion outside the pull request's own history (another unit's,
# left in a reused worktree) is no completion at this head.
FOREIGN_GAP="cadence,gap,post-pr,foreign,2222222222222222222222222222222222222222"
FOREIGN_DETAIL="completed only outside the history of this pull request, newest at 222222222222"
# shellcheck disable=SC2086
walk_rows "draft, foreign post-pr" $DRAFT "$FOREIGN_GAP"
expect_rc "a draft whose only post-pr completion is another unit's is not merge-ready" 4
expect_eq "it is pending the flip, naming the foreign head" "flip-for-review${tab}$H
pending${tab}post-pr${tab}$FOREIGN_DETAIL; pending the flip, which fires the bot review (PR-Agent) a post-pr step may wait on"
# shellcheck disable=SC2086
walk_rows "draft, foreign post-pr, no PR-Agent" "state,draft" "$FOREIGN_GAP"
expect_out "without PR-Agent it stays a gap" "fail${tab}cadence${tab}post-pr: $FOREIGN_DETAIL"
lacks "with no flip token" "flip-for-review"
# shellcheck disable=SC2086
walk_rows "draft, foreign post-pr beside another gap" $DRAFT "$FOREIGN_GAP" "check,lint,FAILURE"
case $(first_line) in "not-ready${tab}$H") ok "a foreign post-pr beside a red check stays not-ready" ;; *) fail "foreign post-pr beside a red check opens '$(first_line)'" ;; esac

# ---------------------------------------------------------------------------
# After the flip the run it fired is required, finished and answered.
# ---------------------------------------------------------------------------
READY="state,ready flip,$FLIP_T require,pr-agent"
# shellcheck disable=SC2086
walk_rows "ready, post-pr incomplete" $READY "$POST_PR_GAP" "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a ready pull request with the post-pr gap is not merge-ready" 4
expect_out "named" "fail${tab}cadence${tab}post-pr: no completion record"
lacks "and no flip token: it is already flipped" "flip-for-review"
# shellcheck disable=SC2086
walk_rows "ready, foreign post-pr" $READY "$FOREIGN_GAP" "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a ready pull request whose only post-pr completion is another unit's is not merge-ready" 4
expect_out "named as a gap" "fail${tab}cadence${tab}post-pr: $FOREIGN_DETAIL"
lacks "and no flip token" "flip-for-review"
# shellcheck disable=SC2086
walk_rows "ready, run still running" $READY "check,PR-Agent,IN_PROGRESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a flip-fired run still running is not merge-ready" 4
expect_out "named as the flip's own run" "fail${tab}check${tab}PR-Agent is IN_PROGRESS (run created 2026-11-18T00:42:23Z, after the flip"
# shellcheck disable=SC2086
walk_rows "ready, no run yet" $READY
expect_rc "a ready pull request with no PR-Agent run yet is not merge-ready" 4
expect_out "named" "fail${tab}bot-review${tab}no PR-Agent run at 111111111111"
# shellcheck disable=SC2086
walk_rows "ready, run predates the flip" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:40:10Z"
expect_rc "a green PR-Agent run from before the flip is not the run the flip fired" 4
expect_out "named, with when the run was created and when the flip was" "fail${tab}bot-review${tab}the only PR-Agent run at 111111111111 was created 2026-11-18T00:40:10Z, before the flip at $FLIP_T; wait for the run the flip fires"
# shellcheck disable=SC2086
walk_rows "ready, run time unread" $READY "check,PR-Agent,SUCCESS"
expect_rc "a green run whose creation time was not read cannot be told from a pre-flip one" 4
expect_out "named, asking for another read" "fail${tab}bot-review${tab}the creation time of the PR-Agent run at 111111111111 is unknown"
# shellcheck disable=SC2086
walk_rows "ready, no flip time" "state,ready" "require,pr-agent" "check,PR-Agent,SUCCESS"
expect_rc "a pull request opened ready has no flip to date the run against" 0
# shellcheck disable=SC2086
walk_rows "ready, pre-flip run and a re-run after" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z" "check,PR-Agent (review),FAILURE" "born,PR-Agent (review),2026-11-18T00:40:10Z"
expect_out "a run of the flip is enough for the bot-review condition, the pre-flip red run still counts as a check" "fail${tab}check${tab}PR-Agent (review) is FAILURE"
lacks "and the bot-review refusal is not raised" "fail${tab}bot-review"
# shellcheck disable=SC2086
walk_rows "ready, flip-fired run finished"$READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a finished flip-fired run with nothing owing is merge-ready" 0
expect_eq "and reads ready" "ready${tab}$H"
# shellcheck disable=SC2086
walk_rows "ready, run finished, finding open" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z" "finding,github-actions[bot],t9,unanswered"
expect_rc "an unanswered finding of the flip-fired run holds merge-ready" 4
expect_out "named" "fail${tab}finding${tab}github-actions[bot] t9 is unanswered"
# shellcheck disable=SC2086
walk_rows "ready, run finished, finding answered" $READY "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z" "finding,github-actions[bot],t9,answered"
expect_rc "once its findings are answered it is merge-ready" 0
# shellcheck disable=SC2086
walk_rows "ready, label opt-out" $READY "check,PR-Agent,SKIPPED" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a skipped run after the flip (the skip-pr-agent label) is the opt-out" 0

# ---------------------------------------------------------------------------
# The contract names the token.
# ---------------------------------------------------------------------------
mc_run mc-readiness.sh --help
expect_out "--help states the flip verdict" "flip-for-review<TAB><head>"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-flip-review: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-flip-review: all passed"
