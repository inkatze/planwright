# shellcheck shell=bash
# shellcheck disable=SC2034 # the suites that source this read the clone paths
# policy-guard-clones.sh — the clones the policy-guard git-act suites share
# (sourced after policy-guard-harness.sh, never executed): the other-task, spec,
# main, pushed, no-upstream and broken-remote siblings of the harness unit clone.
OTHER="$SANDBOX/other"
clone_on "$OTHER" planwright/demo/task-2 1
SPEC="$SANDBOX/spec"
clone_on "$SPEC" planwright/demo/spec 1
MAIN="$SANDBOX/main"
gitq clone "$ORIGIN" "$MAIN"
PUSHED="$SANDBOX/pushed"
clone_on "$PUSHED" planwright/demo/task-1 0
NOUP="$SANDBOX/noup"
clone_on "$NOUP" planwright/demo/task-1 1
gitq -C "$NOUP" branch --unset-upstream
BROKEN="$SANDBOX/broken"
clone_on "$BROKEN" planwright/demo/task-1 1
gitq -C "$BROKEN" remote set-url origin "$SANDBOX/no-such-remote.git"
