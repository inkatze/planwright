#!/bin/bash
# Tests for scripts/worker-command-guard.sh: a worker's own step-script calls
# carrying the step context as an `env` prefix or plain leading assignments.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

echo "### step-context prefix on an installed root's step scripts"
SR="$PLUGIN_ROOT/scripts/step-run.sh"
SREC="$PLUGIN_ROOT/scripts/step-record.sh"
: >"$SR"
: >"$SREC"
WT="$SANDBOX/install/worktree"
mkdir -p "$WT/scripts"
: >"$WT/.git"
: >"$WT/scripts/step-run.sh"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")

CTX="PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_BRANCH=planwright/flight/x PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE=$WT"
assert_allow "the bare step-record call (baseline)" "$SREC new-run" Bash "$WT"
assert_allow "env + step names + step-record.sh" "env $CTX $SREC new-run" Bash "$WT"
assert_allow "env + step names + step-run.sh" "env $CTX $SR audit --through pre-pr --base origin/main" Bash "$WT"
assert_allow "plain assignments + step-record.sh" "$CTX $SREC new-run" Bash "$WT"
assert_allow "plain assignments + step-run.sh" "$CTX $SR audit --through pre-pr" Bash "$WT"
assert_allow "every documented context name" \
  "env PLANWRIGHT_STEP_SPEC= PLANWRIGHT_STEP_TASK_IDS= $SREC new-run" Bash "$WT"
assert_allow "numeric PR number and task ids" \
  "env PLANWRIGHT_STEP_PR_NUMBER=12 PLANWRIGHT_STEP_TASK_IDS=3.1 $SREC new-run" Bash "$WT"
assert_allow "chained after a known-safe segment" "git status && env $CTX $SREC new-run" Bash "$WT"

assert_defer "a non-step name" "env FOO=1 $SREC new-run" Bash "$WT"
assert_defer "a non-step name among step names" "env $CTX FOO=1 $SREC new-run" Bash "$WT"
assert_defer "PATH" "env PLANWRIGHT_STEP_BRANCH=b PATH=/tmp $SREC new-run" Bash "$WT"
assert_defer "LD_PRELOAD as a plain assignment" "LD_PRELOAD=/tmp/x.so $SREC new-run" Bash "$WT"
assert_defer "a misspelled step name" "env PLANWRIGHT_STEP_BRANC=b $SREC new-run" Bash "$WT"
assert_defer "a step-like name with no underscore" "env PLANWRIGHT_STEPBRANCH=b $SREC new-run" Bash "$WT"
assert_defer "env -i" "env -i $CTX $SREC new-run" Bash "$WT"
assert_defer "env -u" "env -u X $CTX $SREC new-run" Bash "$WT"
assert_defer "env -S" "env -S '$CTX $SREC new-run'" Bash "$WT"
assert_defer "env -C" "env -C /tmp $CTX $SREC new-run" Bash "$WT"
assert_defer "env after the assignments" "$CTX env $SREC new-run" Bash "$WT"
assert_defer "a command substitution in a value" "env PLANWRIGHT_STEP_BRANCH=\$(id) $SREC new-run" Bash "$WT"
assert_defer "a variable in a value" "env PLANWRIGHT_STEP_BRANCH=\$B $SREC new-run" Bash "$WT"
assert_defer "a backtick in a value" "env PLANWRIGHT_STEP_BRANCH=\`id\` $SREC new-run" Bash "$WT"
assert_defer "a glob in a value" "env PLANWRIGHT_STEP_BRANCH=* $SREC new-run" Bash "$WT"
assert_defer "a quote-spliced value" "env PLANWRIGHT_STEP_BRANCH=a'\$(id)'b $SREC new-run" Bash "$WT"
assert_defer "an invalid unit kind" "env PLANWRIGHT_STEP_UNIT_KIND=evil $SREC new-run" Bash "$WT"
assert_defer "the worktree's own scripts/ copy" "env $CTX $WT/scripts/step-run.sh audit" Bash "$WT"
assert_defer "a different command after the prefix" "env $CTX git push origin main" Bash "$WT"
assert_defer "a different installed script after the prefix" "env $CTX $PLUGIN_ROOT/scripts/plug.sh" Bash "$WT"
assert_defer "bash running the step script" "env $CTX bash $SREC new-run" Bash "$WT"
assert_defer "the prefix with no command" "env $CTX" Bash "$WT"
assert_defer "a redirect to a real file" "env $CTX $SREC new-run > out.txt" Bash "$WT"

finish_suite worker-command-guard-stepenv
