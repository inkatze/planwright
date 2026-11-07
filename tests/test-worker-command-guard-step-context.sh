#!/bin/bash
# The step-context prefix (worker-permission-ergonomics, read-only shapes): the
# cadence's step-run.sh and step-record.sh calls read the unit's context from
# PLANWRIGHT_STEP_* variables, and each Bash call is a fresh shell, so a worker
# can carry that context only as literal assignments at the head of the one
# command. The guard approves such a prefix in front of a trusted script, the
# same script it approves bare; any other prefix, value, or command defers.
# Every assertion uses the shared harness, and the ALLOW/DEFER contract is the
# harness's.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

S=$PLUGIN_ROOT/scripts/plug.sh
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")

echo "### The step context as a literal prefix on a trusted script"
assert_allow "context: one field" "PLANWRIGHT_STEP_UNIT_KIND=flight $S resolve --run 000001 pre-ci --unattended" Bash "$PLUGIN_CWD"
assert_allow "context: the caller's seven fields, empty ids included" \
  "PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_SPEC= PLANWRIGHT_STEP_TASK_IDS= PLANWRIGHT_STEP_BRANCH=planwright/flight/x PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE=$PLUGIN_CWD PLANWRIGHT_STEP_PR_NUMBER=12 $S begin --run 000001" Bash "$PLUGIN_CWD"
assert_allow "context: quoted values" "PLANWRIGHT_STEP_UNIT_KIND='task' PLANWRIGHT_STEP_TASK_IDS='3 4.1' PLANWRIGHT_STEP_SPEC=\"demo\" $S command --run 000001" Bash "$PLUGIN_CWD"
assert_allow "context: a task unit" "PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_SPEC=demo PLANWRIGHT_STEP_TASK_IDS=7 $S resolve --run 000002 pre-pr --unattended" Bash "$PLUGIN_CWD"
assert_allow "context: the bare script it stands on" "$S resolve --run 000001 pre-ci --unattended" Bash "$PLUGIN_CWD"

echo "### Anything else in the prefix defers"
assert_defer "context: a name outside the context fields" "PLANWRIGHT_STEP_OTHER=x $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: the pool hold mark is the runner's own" "PLANWRIGHT_STEP_POOL_HOLD=gate:123 $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a non-context variable beside one" "PLANWRIGHT_STEP_UNIT_KIND=flight FOO=bar $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a loader variable" "PLANWRIGHT_STEP_UNIT_KIND=flight LD_PRELOAD=/tmp/x.so $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a repeated field" "PLANWRIGHT_STEP_SPEC=a PLANWRIGHT_STEP_SPEC=b $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a unit kind outside its grammar" "PLANWRIGHT_STEP_UNIT_KIND=other $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a PR number that is not a number" "PLANWRIGHT_STEP_PR_NUMBER=12a $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value with a variable" "PLANWRIGHT_STEP_BRANCH=\$B $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value with a substitution" "PLANWRIGHT_STEP_BRANCH=\$(git branch --show-current) $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a value with a backtick" "PLANWRIGHT_STEP_BRANCH=\`id\` $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a quoted name is a command, not an assignment" "'PLANWRIGHT_STEP_SPEC'=x $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a quote on the = is a command, not an assignment" "PLANWRIGHT_STEP_SPEC'='x $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: a quote inside the name is a command, not an assignment" "PLANWRIGHT_STEP_\"SPEC\"=x $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: an unquoted glob in a value" "PLANWRIGHT_STEP_SPEC=demo* $S resolve" Bash "$PLUGIN_CWD"
assert_defer "context: assignments with nothing left to run" "PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_SPEC=demo" Bash "$PLUGIN_CWD"

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
