#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the worker's own branch sync
# through scripts/worker-branch-sync.sh. The guard admits the helper only at
# the worker tier, as its own command or after cd only, by the installed
# copy, in its own grammar, on the session's unit branch in its own checkout,
# where the session record names both, and every near spelling of its
# arguments is refused. The command shapes around a run, the copies that run
# and the mentions that run nothing are tests/test-policy-guard-branch-sync-shapes.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"
# shellcheck source=tests/lib/policy-guard-branch-sync.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-branch-sync.sh"

echo "# the admitted runs"
sync "$H reset origin/$B"
expect defer "[worker] the reset to the own remote-tracking ref defers to the helper"
reads protected_branches "[worker] the admitted reset reads only the protected set"
sync "$RUN"
expect defer "[worker] the fast-forward to a full SHA defers to the helper"
sync "cd \"$UNIT\" && $RUN" "$SANDBOX" "$UNIT"
expect defer "[worker] the fast-forward after a plain cd into the own worktree defers"
reads protected_branches "[worker] the fast-forward after a cd ran the full check"
sync '"$CLAUDE_PLUGIN_ROOT"/scripts/worker-branch-sync.sh ff '"$SHA"
expect defer "[worker] the \$CLAUDE_PLUGIN_ROOT spelling defers"
reads protected_branches "[worker] the \$CLAUDE_PLUGIN_ROOT spelling ran the full check"
sync '${CLAUDE_PLUGIN_ROOT}/scripts/worker-branch-sync.sh reset origin/'"$B"
expect defer "[worker] the braced \$CLAUDE_PLUGIN_ROOT spelling defers"
reads protected_branches "[worker] the braced spelling ran the full check"
sync "$H --help"
expect defer "[worker] the helper's usage text defers"
reads none "[worker] the usage text reads nothing"
PLANWRIGHT_WORKER_SESSION_RECORD='' pg worker "$H --help" "$OTHER" "$OTHER"
expect defer "[worker] the usage text needs no record or unit branch"
sync "$H --help push"
expect deny "[worker] the usage flag beside a verb denies"
no_gh_calls

echo "# push, in every spelling: the helper publishes nothing"
for args in "push --force-with-lease=$B:$SHA --force-if-includes" "push --force-if-includes --force-with-lease=$B:$SHA" \
  "push --force" "push -f" "push --force-if-includes" \
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
sync "$PUSH"
reason_has 'publishes nothing' "[worker] the push refusal says the helper publishes nothing"
reason_has 'worker-branch-sync[.]sh reset origin/<branch> or ff' "[worker] the push refusal names the accepted forms"
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

echo "# the session record"
REC_SAVED=$REC
REC=''
sync "$RUN"
expect deny "[worker] no session record denies"
reason_has 'session record' "[worker] the missing-record refusal names the record"
REC=$(record task-2.record planwright/demo/task-2 "$UNIT_P")
sync "$RUN"
expect deny "[worker] a record naming another branch denies"
REC=$(record other-top.record "$B" "$SANDBOX/other")
sync "$RUN"
expect deny "[worker] a record naming another worktree denies"
REC=$(record twice.record "$B" "$UNIT_P")
printf 'unit_branch=%s\n' "$B" >>"$REC"
sync "$RUN"
expect deny "[worker] a record naming the branch twice denies"
REC="$UNIT/inside.record"
printf 'unit_branch=%s\nworktree_root=%s\n' "$B" "$UNIT_P" >"$REC"
sync "$RUN"
expect deny "[worker] a record inside the worktree denies"
rm -f "$UNIT/inside.record"
ln -s "$REC_SAVED" "$RECS/link.record"
REC="$RECS/link.record"
sync "$RUN"
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
reason_has 'never rewrites history|unit branch' "[worker] the spec-branch refusal is the unit-branch rule's"
REC=$(record main.record main "$(cd "$MAIN" && pwd -P)")
sync "$H reset origin/main" "$MAIN" "$MAIN"
expect deny "[worker] main denies, even when the record names it"
reason_has 'never rewrites history|unit branch' "[worker] the main refusal is the unit-branch rule's"
REC=$REC_SAVED
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow' "protected_branches: $B"
sync "$RUN"
expect deny "[worker] a protected unit branch denies"
reason_has 'protected branch' "[worker] the protected refusal keeps the protected-branch text"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

echo "# other tiers"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower "$RUN"
expect deny "[tower] the helper denies at the tower tier"
reason_has 'worker profile only' "[tower] the tower refusal names the worker tier"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg mission-control "$H reset origin/$B"
expect deny "[mission-control] the helper denies at the mission-control tier"

echo "# the raw acts stay as they were"
sync "git push --force-with-lease=$B:$SHA --force-if-includes origin $B"
expect deny "[worker] a raw leased push still denies"
sync "git push origin +$B"
expect deny "[worker] a raw + refspec push still denies"
sync "git merge --ff-only $SHA"
expect deny "[worker] a raw fast-forward to a SHA still denies"

finish
