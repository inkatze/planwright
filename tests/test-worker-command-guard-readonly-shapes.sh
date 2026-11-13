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

echo "### near misses still defer"
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
assert_defer "timeout over 600 around a scratch script" "timeout 601 sh $SC/wait.sh" Bash "$WT"
assert_defer "timeout 600 around a scratch script (a script of the worker's own is never executed)" "timeout 600 sh $SC/wait.sh" Bash "$WT"

finish_suite "worker-command-guard readonly shapes"
