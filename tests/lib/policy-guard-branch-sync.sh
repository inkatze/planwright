# shellcheck shell=bash
# shellcheck disable=SC2034 # the suites that source this read these names
# policy-guard-branch-sync.sh — the fixture the branch-sync guard suites share
# (sourced after policy-guard-harness.sh and policy-guard-clones.sh, never
# executed): the helper copied beside the sandbox guard, a session record for
# the harness unit clone, and the sync runner that sends a command under it.
unset CDPATH
cp "$REAL_SCRIPTS/worker-branch-sync.sh" "$S/"
H="$S/worker-branch-sync.sh"
B=planwright/demo/task-1
SHA=$(git -C "$UNIT" rev-parse HEAD~1)
UNIT_P=$(cd "$UNIT" && pwd -P)
RECS="$SANDBOX/fleet/session-records"
mkdir -p "$RECS"
# record <name> <unit branch> <worktree root> — a session record, printed path.
record() {
  printf 'policy=own-branch\nunit_branch=%s\nworktree_root=%s\n' "$2" "$3" >"$RECS/$1"
  chmod 600 "$RECS/$1"
  printf '%s' "$RECS/$1"
}
REC=$(record unit.record "$B" "$UNIT_P")
PUSH="$H push --force-with-lease=$B:$SHA --force-if-includes"

# sync <command> [cwd] [project-dir] — the worker tier under the record.
sync() {
  PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$@"
}
