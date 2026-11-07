#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the step-context prefix on trusted
# repo code. The cadence's step-run.sh and resolve-steps.sh calls read the
# unit's context from PLANWRIGHT_STEP_* variables, and each Bash call is a
# fresh shell, so a worker can carry that context only as literal assignments
# at the head of the one command. The guard approves such a prefix in front of
# a trusted script, the same script it approves bare, when every value is the
# one the worker's session record implies; any other prefix, value, or command
# defers.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

S=$PLUGIN_ROOT/scripts/plug.sh
WT=$(cd -P "$PLUGIN_CWD" && pwd -P)
FLIGHT=planwright/flight/demo-0123abcd
mkdir -p "$SANDBOX/records"
write_record "$SANDBOX/records/flight.record" "$WT" "" "$FLIGHT"
write_record "$SANDBOX/records/task.record" "$WT" "" "planwright/demo/task-7"
write_record "$SANDBOX/records/bundle.record" "$WT" "" "planwright/demo/task-3-4.1"
FLIGHT_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/records/flight.record")
TASK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/records/task.record")
BUNDLE_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/records/bundle.record")
ALL7="PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_SPEC= PLANWRIGHT_STEP_TASK_IDS= PLANWRIGHT_STEP_BRANCH=$FLIGHT PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE=$WT PLANWRIGHT_STEP_PR_NUMBER=12"

echo "### The step context as a literal prefix on a trusted script"
HOOK_ENV=("${FLIGHT_ENV[@]}")
assert_allow "context: one field" "PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve --run 000001 pre-ci --unattended" Bash "$PLUGIN_CWD"
assert_allow "context: the caller's seven fields, empty ids included" "$ALL7 $S begin --run 000001" Bash "$PLUGIN_CWD"
assert_allow "context: quoted values" "PLANWRIGHT_STEP_UNIT_KIND='flight' PLANWRIGHT_STEP_BRANCH=\"$FLIGHT\" PLANWRIGHT_STEP_SPEC='' $S command --run 000001" Bash "$PLUGIN_CWD"
assert_allow "context: the base as its remote-tracking name" "PLANWRIGHT_STEP_BASE_BRANCH=origin/main $S resolve" Bash "$PLUGIN_CWD"
assert_allow "context: the bare script it stands on" "$S resolve --run 000001 pre-ci --unattended" Bash "$PLUGIN_CWD"
HOOK_ENV=("${TASK_ENV[@]}")
assert_allow "context: a task unit" "PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_SPEC=demo PLANWRIGHT_STEP_TASK_IDS=7 $S resolve --run 000002 pre-pr --unattended" Bash "$PLUGIN_CWD"
HOOK_ENV=("${BUNDLE_ENV[@]}")
assert_allow "context: a bundle's task ids" "PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_SPEC=demo PLANWRIGHT_STEP_TASK_IDS='3 4.1' $S resolve" Bash "$PLUGIN_CWD"

echo "### A value the session record does not imply defers"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=")
assert_defer "context: no session record" "PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve" Bash "$PLUGIN_CWD"
HOOK_ENV=("${FLIGHT_ENV[@]}")
assert_defer "context: another unit's branch" "PLANWRIGHT_STEP_BRANCH=main $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: another worktree" "PLANWRIGHT_STEP_WORKTREE=/ $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: another base" "PLANWRIGHT_STEP_BASE_BRANCH=release $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a spec named on a flight" "PLANWRIGHT_STEP_SPEC=demo $S command --run 000001 --point pre-ready-flip --step mc-eval-cadence" Bash "$PLUGIN_CWD"
assert_defer "context: task ids on a flight" "PLANWRIGHT_STEP_TASK_IDS=7 $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a unit kind the branch does not carry" "PLANWRIGHT_STEP_UNIT_KIND=task $S resolve" Bash "$PLUGIN_CWD"
HOOK_ENV=("${TASK_ENV[@]}")
assert_defer "context: another spec on a task" "PLANWRIGHT_STEP_SPEC=other $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: another task's id" "PLANWRIGHT_STEP_TASK_IDS=8 $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: no task ids on a task" "PLANWRIGHT_STEP_TASK_IDS= $S resolve" Bash "$PLUGIN_CWD"

echo "### Anything else in the prefix defers"
HOOK_ENV=("${FLIGHT_ENV[@]}")
assert_defer "context: a name outside the context fields" "PLANWRIGHT_STEP_OTHER=x $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: the pool hold mark is the runner's own" "PLANWRIGHT_STEP_POOL_HOLD=gate:123 $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a field the runner computes itself" "PLANWRIGHT_STEP_PREV_RECORD=/etc/shadow $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: the point is the runner's own" "PLANWRIGHT_STEP_POINT=pre-pr $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a non-context variable beside one" "PLANWRIGHT_STEP_UNIT_KIND=flight FOO=bar $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a loader variable" "PLANWRIGHT_STEP_UNIT_KIND=flight LD_PRELOAD=/tmp/x.so $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a repeated field" "PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a unit kind outside its grammar" "PLANWRIGHT_STEP_UNIT_KIND=other $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a PR number that is not a number" "PLANWRIGHT_STEP_PR_NUMBER=12a $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value with a variable" "PLANWRIGHT_STEP_BRANCH=\$B $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value from a tracked assignment" "B=$FLIGHT && PLANWRIGHT_STEP_BRANCH=\$B $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value with a substitution" "PLANWRIGHT_STEP_BRANCH=\$(git branch --show-current) $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value with a backtick" "PLANWRIGHT_STEP_BRANCH=\`id\` $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value the shell tilde-expands" "PLANWRIGHT_STEP_WORKTREE=~/x $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a tilde after a colon" "PLANWRIGHT_STEP_WORKTREE=$WT:~ $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a quoted name is a command, not an assignment" "'PLANWRIGHT_STEP_SPEC'= $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a quote on the = is a command, not an assignment" "PLANWRIGHT_STEP_SPEC'=' $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a quote inside the name is a command, not an assignment" "PLANWRIGHT_STEP_\"SPEC\"= $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: an unquoted glob in a value" "PLANWRIGHT_STEP_SPEC=demo* $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: assignments with nothing left to run" "PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_SPEC=" Bash "$PLUGIN_CWD"

echo "### A prefix that only appears after expansion is a command name"
assert_defer "context: an empty variable ahead of the prefix" "E=; \$E PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: the assignment held in a variable" "X=PLANWRIGHT_STEP_UNIT_KIND=flight; \$X $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: the name built from a variable" "N=PLANWRIGHT_STEP_UNIT_KIND; \$N=flight $S resolve" Bash "$PLUGIN_CWD"

echo "### The command after the prefix is held to what it would be bare"
assert_defer "context: an untrusted script" "PLANWRIGHT_STEP_UNIT_KIND=flight $PLUGIN_DECOY/scripts/plug.sh resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a script outside any root" "PLANWRIGHT_STEP_UNIT_KIND=flight /tmp/x.sh" Bash "$PLUGIN_CWD"
assert_defer "context: a plain verb" "PLANWRIGHT_STEP_UNIT_KIND=flight cat README.md" Bash "$PLUGIN_CWD"
assert_defer "context: sh running a script" "PLANWRIGHT_STEP_UNIT_KIND=flight sh $S" Bash "$PLUGIN_CWD"
assert_defer "context: bash running a script" "PLANWRIGHT_STEP_UNIT_KIND=flight bash $S" Bash "$PLUGIN_CWD"
assert_defer "context: a repo task runner" "PLANWRIGHT_STEP_UNIT_KIND=flight mise run check" Bash "$PLUGIN_CWD"
assert_defer "context: a bare script name with no path" "PLANWRIGHT_STEP_UNIT_KIND=flight plug.sh resolve" Bash "$PLUGIN_CWD"
assert_defer "context: inside a substitution" "echo \"\$(PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve)\"" Bash "$PLUGIN_CWD"
assert_allow "context: a prefixed segment leaves the next segment to stand alone" "PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve && cat README.md" Bash "$PLUGIN_CWD"
assert_defer "context: env in front" "env PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a write redirect" "PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve > $PLUGIN_CWD/out" Bash "$PLUGIN_CWD"
assert_defer "context: a push behind the prefix" "PLANWRIGHT_STEP_UNIT_KIND=flight git push origin main" Bash "$PLUGIN_CWD"
assert_defer "context: the force-push helper stays on the floor" "PLANWRIGHT_STEP_UNIT_KIND=flight $PLUGIN_ROOT/scripts/tower-force-push.sh" Bash "$PLUGIN_CWD"
assert_defer "context: the force-push helper under another name" "PLANWRIGHT_STEP_UNIT_KIND=flight $PLUGIN_ROOT/scripts/plug-fph.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()

finish_suite worker-command-guard-step-context
