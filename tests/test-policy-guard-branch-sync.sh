#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the worker's own branch sync
# through scripts/worker-branch-sync.sh. The guard admits the helper only at
# the worker tier, as its own command or after cd only, by the installed
# copy, in its own grammar, on the session's unit branch in its own checkout,
# where the session record names both; every near spelling is refused, and a
# mention that runs nothing passes to the ordinary rules.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"

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

echo "# the admitted runs"
sync "$PUSH"
expect defer "[worker] the leased push of the own unit branch defers to the helper"
reads protected_branches "[worker] the admitted push reads only the protected set"
sync "$H push --force-if-includes --force-with-lease=$B:$SHA"
expect defer "[worker] the two push options in either order defer"
sync "$H reset origin/$B"
expect defer "[worker] the reset to the own remote-tracking ref defers to the helper"
sync "$H ff $SHA"
expect defer "[worker] the fast-forward to a full SHA defers to the helper"
sync "cd \"$UNIT\" && $PUSH" "$SANDBOX" "$UNIT"
expect defer "[worker] the push after a plain cd into the own worktree defers"
reads protected_branches "[worker] the push after a cd ran the full check"
sync '"$CLAUDE_PLUGIN_ROOT"/scripts/worker-branch-sync.sh ff '"$SHA"
expect defer "[worker] the \$CLAUDE_PLUGIN_ROOT spelling defers"
reads protected_branches "[worker] the \$CLAUDE_PLUGIN_ROOT spelling ran the full check"
sync '${CLAUDE_PLUGIN_ROOT}/scripts/worker-branch-sync.sh reset origin/'"$B"
expect defer "[worker] the braced \$CLAUDE_PLUGIN_ROOT spelling defers"
reads protected_branches "[worker] the braced spelling ran the full check"
no_gh_calls

echo "# near spellings of push"
for args in "push --force" "push -f" "push --force-if-includes" \
  "push --force-with-lease --force-if-includes" \
  "push --force-with-lease=$B --force-if-includes" \
  "push --force-with-lease=$B: --force-if-includes" \
  "push --force-with-lease=$B:${SHA%????????} --force-if-includes" \
  "push --force-with-lease=$B:HEAD --force-if-includes" \
  "push --force-with-lease=$B:origin/$B --force-if-includes" \
  "push --force-with-lease=$B:$SHA" \
  "push --force-with-lease=$B:$SHA --force-with-lease=$B:$SHA" \
  "push --force-with-lease=$B:$SHA --force-if-includes +$B" \
  "push --force-with-lease=$B:$SHA --force-if-includes +HEAD:main" \
  "push --force-with-lease=$B:$SHA --force-if-includes origin $B" \
  "push --force-with-lease=planwright/demo/task-2:$SHA --force-if-includes" \
  "push --force-with-lease=main:$SHA --force-if-includes" \
  "push --force-with-lease=refs/heads/$B:$SHA --force-if-includes"; do
  sync "$H $args"
  expect deny "[worker] $args denies"
done
sync "$H push --force-with-lease=$B:$SHA --force-if-includes +$B"
reason_has 'worker-branch-sync[.]sh push --force-with-lease=<branch>' "[worker] a + refspec refusal names the accepted form"
sync "$H push --force-with-lease=$B --force-if-includes"
reason_has 'full (SHA|sha)' "[worker] a lease without a SHA names the full SHA"
sync "$S/worker-branch-\\
sync.sh ff $SHA"
expect defer "[worker] the helper's path split by a line continuation is the same run, and defers"
reads protected_branches "[worker] the split path ran the full check"

echo "# near spellings of reset and ff"
for args in "reset" "reset origin/main" "reset origin/planwright/demo/task-2" "reset $B" \
  "reset refs/remotes/origin/$B" "reset origin/$B~1" "reset --hard origin/$B" "reset origin/$B --hard" \
  "ff" "ff ${SHA%????}" "ff HEAD" "ff origin/$B" "ff $SHA $SHA" "ff --ff-only $SHA" \
  "rebase origin/main" "merge $SHA" ""; do
  sync "$H $args"
  expect deny "[worker] '${args:-no verb}' denies"
done

echo "# the shape of the command"
for c in "PLANWRIGHT_WORKER_SESSION_RECORD=/tmp/x.record $PUSH" "GIT_DIR=/x $PUSH" \
  "env $PUSH" "bash $PUSH" "sh $PUSH" "nohup $PUSH" "command $PUSH" "exec $PUSH" "time $PUSH" "! $PUSH" \
  "$PUSH; git status" "$PUSH && echo done" "git status && $PUSH" "true || $PUSH" "$PUSH &" \
  "$PUSH > $SANDBOX/out" "$PUSH 2>&1" "$PUSH | cat" "echo \$($PUSH)" "bash -c '$PUSH'" \
  "cd \"$UNIT\"; $PUSH" "cd \"$UNIT\" || $PUSH" "false && cd \"$UNIT\" && $PUSH" \
  "if true; then $PUSH; fi" "for i in 1; do $PUSH; done" "x=1 && $PUSH" \
  "$H push --force-with-lease=$B:\$SHA --force-if-includes" "$H ff \"\$X\"" \
  "$S/worker-branch-\\
sync.sh ff $SHA; git status" "${H//worker/WORKER} ff $SHA" "x=\$(true) $PUSH" \
  "find . -name x -exec $H ff $SHA ;" "$S/\"worker-branch-sync.sh\" ff $SHA; true"; do
  sync "$c"
  expect deny "[worker] the shape '$(printf '%s' "$c" | tr '\n' ' ' | cut -c1-80)' denies"
done

echo "# the copy that runs"
mkdir -p "$UNIT/scripts" "$SANDBOX/elsewhere"
cp "$H" "$UNIT/scripts/"
cp "$H" "$SANDBOX/elsewhere/"
sync "$UNIT/scripts/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a copy inside the worktree denies"
reason_has 'not the installed' "[worker] the worktree-copy refusal says it is not the installed copy"
sync "scripts/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a relative path denies"
sync "$SANDBOX/elsewhere/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a copy outside every installed root denies"
sync '"$ROOT"/scripts/worker-branch-sync.sh ff '"$SHA"
expect deny "[worker] another variable root denies"
rm -rf "${UNIT:?}/scripts"

echo "# the session record"
REC_SAVED=$REC
REC=''
sync "$PUSH"
expect deny "[worker] no session record denies"
reason_has 'session record' "[worker] the missing-record refusal names the record"
REC=$(record task-2.record planwright/demo/task-2 "$UNIT_P")
sync "$PUSH"
expect deny "[worker] a record naming another branch denies"
REC=$(record other-top.record "$B" "$SANDBOX/other")
sync "$PUSH"
expect deny "[worker] a record naming another worktree denies"
REC=$(record twice.record "$B" "$UNIT_P")
printf 'unit_branch=%s\n' "$B" >>"$REC"
sync "$PUSH"
expect deny "[worker] a record naming the branch twice denies"
REC="$UNIT/inside.record"
printf 'unit_branch=%s\nworktree_root=%s\n' "$B" "$UNIT_P" >"$REC"
sync "$PUSH"
expect deny "[worker] a record inside the worktree denies"
rm -f "$UNIT/inside.record"
ln -s "$REC_SAVED" "$RECS/link.record"
REC="$RECS/link.record"
sync "$PUSH"
expect deny "[worker] a record that is a symlink denies"
REC=$REC_SAVED

echo "# the branch and the checkout"
sync "$H push --force-with-lease=planwright/demo/task-2:$SHA --force-if-includes" "$OTHER" "$OTHER"
expect deny "[worker] another unit branch's checkout, under this session's record, denies"
sync "cd \"$OTHER\" && $H reset origin/planwright/demo/task-2" "$UNIT" "$UNIT"
expect deny "[worker] a cd into another checkout denies"
sync "cd \"$OTHER\" && $H reset origin/$B" "$UNIT" "$UNIT"
expect deny "[worker] the own branch name run from another checkout denies"
REC=$(record spec.record planwright/demo/spec "$(cd "$SPEC" && pwd -P)")
sync "$H reset origin/planwright/demo/spec" "$SPEC" "$SPEC"
expect deny "[worker] a spec branch denies, even when the record names it"
REC=$(record main.record main "$(cd "$MAIN" && pwd -P)")
sync "$H reset origin/main" "$MAIN" "$MAIN"
expect deny "[worker] main denies, even when the record names it"
REC=$REC_SAVED
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow' "protected_branches: $B"
sync "$PUSH"
expect deny "[worker] a protected unit branch denies"
reason_has 'protected branch' "[worker] the protected refusal keeps the protected-branch text"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

echo "# other tiers"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower "$PUSH"
expect deny "[tower] the helper denies at the tower tier"
reason_has 'worker profile only' "[tower] the tower refusal names the worker tier"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg mission-control "$H reset origin/$B"
expect deny "[mission-control] the helper denies at the mission-control tier"

echo "# mentions that run nothing"
for c in "grep -n lease $H" "cat $H" "shellcheck scripts/worker-branch-sync.sh" \
  "bash tests/test-worker-branch-sync.sh" "git log --oneline -- scripts/worker-branch-sync.sh" \
  "git add scripts/worker-branch-sync.sh" "sed -n 1,20p scripts/worker-branch-sync.sh"; do
  sync "$c"
  expect defer "[worker] the mention '$c' defers"
  reads none "[worker] the mention '$c' is not read as a run"
  pg tower "$c"
  expect defer "[tower] the mention '$c' defers"
done

echo "# the raw acts stay as they were"
sync "git push --force-with-lease=$B:$SHA --force-if-includes origin $B"
expect deny "[worker] a raw leased push still denies"
sync "git push origin +$B"
expect deny "[worker] a raw + refspec push still denies"
sync "git merge --ff-only $SHA"
expect deny "[worker] a raw fast-forward to a SHA still denies"

finish
