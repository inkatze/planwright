#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the routine read-only shapes a
# worker runs from its own worktree (jq over local files, gh pr/run reads, a
# bounded foreground poll), and the near misses that must still defer.
# All files source tests/lib/worker-command-guard-harness.sh, which states the
# contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
SC=$CORPUS_SCRATCH
OUT_DIR=$CORPUS_OUTSIDE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
mkdir -p "$SC/work"
: >"$SC/a.json"
: >"$SC/b.json"
: >"$WT/a.json"
: >"$WT/b.json"
: >"$OUT_DIR/c.json"
{
  printf 'policy=scratch\n'
  grep -v '^policy=' "$STATE/record.4"
} >"$STATE/ro.record"
# shellcheck disable=SC2034 # read by the harness's run_hook
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$STATE/ro.record")

echo "### read-only shapes a worker runs from its worktree ALLOW"
assert_allow "jq -r over a worktree file" "jq -r .x a.json" Bash "$WT"
assert_allow "jq -c over two worktree files" "jq -c '.[]' a.json b.json" Bash "$WT"
assert_allow "jq -r over a scratch file" "jq -r .x $SC/a.json" Bash "$WT"
assert_allow "jq -c over two scratch files" "jq -c '.[]' $SC/a.json $SC/b.json" Bash "$WT"
assert_allow "gh pr view with -R and --json" "gh pr view 881 -R inkatze/planwright --json state,mergeable" Bash "$WT"
assert_allow "gh run list with -R, --branch and --json" "gh run list -R inkatze/planwright --branch feat/x --json databaseId,status" Bash "$WT"
assert_allow "gh run view with -R and --json" "gh run view 123 -R inkatze/planwright --json status,conclusion" Bash "$WT"
assert_allow "gh run view --log-failed" "gh run view 123 -R inkatze/planwright --log-failed" Bash "$WT"
assert_allow "a literal-bound for poll" "for i in 1 2 3 4 5; do gh pr view 881 -R inkatze/planwright --json state; sleep 60; done" Bash "$WT"
assert_allow "a literal-bound for poll over a git read" "for i in 1 2 3; do git status; sleep 30; done" Bash "$WT"

assert_allow "jq --rawfile over a worktree file" "jq -n --rawfile s $WT/a.json '\$s'" Bash "$WT"
assert_allow "jq --slurpfile over a scratch file" "jq -n --slurpfile s $SC/a.json '\$s'" Bash "$WT"
assert_allow "env --chdir to the worktree then git diff" "env --chdir=$WT git diff origin/main...HEAD" Bash "$WT"
assert_allow "env --chdir to the worktree then git log" "env --chdir=$WT git log -1" Bash "$WT"
assert_allow "env --chdir to the worktree then git status" "env --chdir=$WT git status" Bash "$WT"
assert_allow "env --chdir to the worktree then grep" "env --chdir=$WT grep -rn foo ." Bash "$WT"
assert_allow "env --chdir to the worktree then ls" "env --chdir=$WT ls" Bash "$WT"
assert_allow "env --chdir to the worktree then cat" "env --chdir=$WT cat a.json" Bash "$WT"
assert_allow "env --chdir to the worktree then jq" "env --chdir=$WT jq -r .x a.json" Bash "$WT"

echo "### near misses still defer"
assert_defer "env --chdir outside the worktree" "env --chdir=$OUT_DIR git status" Bash "$WT"
assert_defer "env --chdir to the scratch root" "env --chdir=$SC git status" Bash "$WT"
assert_defer "env --chdir to /" "env --chdir=/ git status" Bash "$WT"
assert_defer "env --chdir then -i" "env --chdir=$WT -i git status" Bash "$WT"
assert_defer "env -i before --chdir" "env -i --chdir=$WT git status" Bash "$WT"
assert_defer "env --chdir then an assignment" "env --chdir=$WT FOO=bar git status" Bash "$WT"
assert_defer "env --chdir then -u" "env --chdir=$WT -u HOME git status" Bash "$WT"
assert_defer "env --chdir then -S" "env --chdir=$WT -S 'git status' x" Bash "$WT"
assert_defer "env --chdir then a writer" "env --chdir=$WT rm -rf build" Bash "$WT"
assert_defer "env --chdir then a push" "env --chdir=$WT git push origin main" Bash "$WT"
assert_defer "env --chdir then a shell" "env --chdir=$WT sh -c 'git status'" Bash "$WT"
assert_defer "env --chdir with a variable directory" "env --chdir=\$WT git status" Bash "$WT"
assert_defer "env --chdir with nothing to run" "env --chdir=$WT" Bash "$WT"
assert_defer "env --chdir twice" "env --chdir=$WT --chdir=$OUT_DIR git status" Bash "$WT"
assert_defer "env --chdir separated from its value" "env --chdir $WT git status" Bash "$WT"
assert_defer "env -C" "env -C $WT git status" Bash "$WT"
assert_defer "env --chdir to a dotdot path" "env --chdir=$WT/../outside git status" Bash "$WT"
assert_defer "env --chdir then cd" "env --chdir=$WT cd sub" Bash "$WT"
assert_defer "env --chdir then git --output" "env --chdir=$WT git diff --output=x" Bash "$WT"
assert_defer "env --chdir then a second env" "env --chdir=$WT env git status" Bash "$WT"
assert_defer "gh run view with a clustered -XPOST" "gh run view 1 -R inkatze/planwright -XPOST" Bash "$WT"
assert_defer "gh pr view with --method=POST" "gh pr view 881 -R inkatze/planwright --method=POST" Bash "$WT"
assert_defer "jq --rawfile outside the worktree and scratch" "jq -n --rawfile s $OUT_DIR/c.json '\$s'" Bash "$WT"
assert_defer "jq --slurpfile outside the worktree and scratch" "jq -n --slurpfile s $OUT_DIR/c.json '\$s'" Bash "$WT"
assert_defer "jq --rawfile of a secret path" "jq -n --rawfile s /etc/shadow '\$s'" Bash "$WT"
assert_defer "jq --slurpfile of a home secret" "jq -n --slurpfile s \$HOME/.ssh/id_rsa '\$s'" Bash "$WT"
assert_defer "gh pr view with -X" "gh pr view 881 -R inkatze/planwright -X POST" Bash "$WT"
assert_defer "gh run list with --method" "gh run list -R inkatze/planwright --method POST" Bash "$WT"
assert_defer "gh api write" "gh api -X POST repos/inkatze/planwright/issues" Bash "$WT"
assert_defer "gh api --method write" "gh api --method DELETE repos/inkatze/planwright/issues/1" Bash "$WT"
assert_defer "gh run rerun" "gh run rerun 123 -R inkatze/planwright" Bash "$WT"
assert_defer "gh run cancel" "gh run cancel 123 -R inkatze/planwright" Bash "$WT"
assert_defer "a poll with a variable bound" "for i in \$(seq \$N); do git status; sleep 30; done" Bash "$WT"
assert_defer "a poll whose body is not read-only" "for i in 1 2 3; do gh run rerun 123 -R inkatze/planwright; sleep 30; done" Bash "$WT"
assert_defer "a poll whose body writes" "for i in 1 2 3; do touch x; sleep 30; done" Bash "$WT"
assert_defer "timeout around a scratch script (a script of the worker's own is never executed)" "timeout 600 sh $SC/wait.sh" Bash "$WT"

finish_suite "worker-command-guard readonly shapes"
