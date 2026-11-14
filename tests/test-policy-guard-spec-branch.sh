#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the spec PR branch a worker's
# launch names (the session record's spec_branch). The worker may fast-forward
# its own flight branch to that branch's remote-tracking ref and push HEAD to
# that branch by explicit refspec, and nothing wider.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

SB=planwright/demo/amendment-1
SB2=planwright/demo/amendment-2
OTHERFL=planwright/flight/other-worker-0123abcd
MYFL=planwright/flight/spec-sync-0123abcd

# Each spec branch carries a commit main lacks; the other worker's flight
# branch too.
for b in "$SB" "$SB2" "$OTHERFL"; do
  gitq -C "$SEED" switch -c "$b" main
  gitq -C "$SEED" commit --allow-empty -m "pushed on $b"
  gitq -C "$SEED" push origin "$b"
done
gitq -C "$SEED" switch main
gitq -C "$SEED" commit --allow-empty -m "main moves on"
gitq -C "$SEED" push origin main

FL="$SANDBOX/flight"
gitq clone "$ORIGIN" "$FL"
gitq -C "$FL" remote set-head origin main
gitq -C "$FL" switch -c "$MYFL" origin/main
gitq -C "$FL" push -u origin "$MYFL"

# The record sits outside the worktree, this user's own regular file.
REC="$SANDBOX/records/session.record"
mkdir -p "$SANDBOX/records"
rec() { printf '%s\n' "$@" >"$REC"; }
launch() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$@" "$FL" "$FL"; }

echo "# a launch naming the spec branch admits fast-forwarding to it, then the push"
rec "unit_branch=$MYFL" "spec_branch=$SB"
for cmd in "git merge --ff-only origin/$SB" "git merge --ff-only refs/remotes/origin/$SB" "git merge --ff-only --quiet origin/$SB"; do
  launch "$cmd"
  expect defer "[worker] the named spec branch fast-forwards in: $cmd"
done
gitq -C "$FL" merge --ff-only "origin/$SB"
launch 'git merge origin/main'
expect defer "[worker] after the fast-forward, the PR base merges as before"
gitq -C "$FL" merge origin/main
for cmd in "git push origin HEAD:refs/heads/$SB" "git push origin HEAD:$SB"; do
  launch "$cmd"
  expect defer "[worker] the explicit-refspec push to the named spec branch defers: $cmd"
done

echo "# nothing wider is admitted"
launch "git merge origin/$SB"
expect deny "[worker] a merge of the spec branch with no --ff-only denies"
launch "git merge --no-ff origin/$SB"
expect deny "[worker] a --no-ff merge of the spec branch denies"
launch "git merge --ff-only --no-ff origin/$SB"
expect deny "[worker] --no-ff after --ff-only denies"
launch "git merge --ff-only origin/$SB origin/main"
expect deny "[worker] the spec branch beside a second source denies"
launch "git pull origin $SB"
expect deny "[worker] a pull of the spec branch denies (a merge by another name)"
launch "git merge --ff-only origin/$SB2"
expect deny "[worker] a different spec branch denies"
reason_has 'merges only the PR base' "[worker] the other spec branch gets today's text"
launch "git merge --ff-only origin/$OTHERFL"
expect deny "[worker] another worker's flight branch denies"
reason_has 'merges only the PR base' "[worker] the other flight branch gets today's text"
launch 'git merge --ff-only origin/planwright/demo/task-2'
expect deny "[worker] another unit's task branch denies"
launch "git merge --ff-only $SB"
expect deny "[worker] the bare local spelling of the spec branch denies"
launch 'git merge --ff-only HEAD~1'
expect deny "[worker] an arbitrary revision denies"
launch "git merge --ff-only $(git -C "$FL" rev-parse "origin/$SB")"
expect deny "[worker] the spec branch's SHA denies"
gitq -C "$FL" tag spec-tag "origin/$SB"
launch 'git merge --ff-only spec-tag'
expect deny "[worker] a tag at the spec branch denies"
gitq -C "$FL" branch "origin/$SB2" HEAD~1
launch "git merge --ff-only origin/$SB2"
expect deny "[worker] a shadowing local branch of another spec branch still denies"
gitq -C "$FL" branch -D "origin/$SB2"
gitq -C "$FL" branch "origin/$SB" HEAD~1
launch "git merge --ff-only origin/$SB"
expect deny "[worker] a local branch shadowing the named spec branch denies (fail closed)"
gitq -C "$FL" branch -D "origin/$SB"
for cmd in "git push --force origin HEAD:refs/heads/$SB" "git push -f origin HEAD:refs/heads/$SB" \
  "git push --force-with-lease origin HEAD:refs/heads/$SB" "git push origin +HEAD:refs/heads/$SB" \
  "git push origin +HEAD:$SB"; do
  launch "$cmd"
  expect deny "[worker] a force push to the named spec branch denies: $cmd"
done
launch 'git push origin HEAD:refs/heads/main'
expect deny "[worker] a push to main denies"

echo "# the carrier is the launch record, never the command text"
rm -f "$REC"
launch "git merge --ff-only origin/$SB"
expect deny "[worker] no record: the spec branch denies"
rec "unit_branch=$MYFL"
launch "git merge --ff-only origin/$SB"
expect deny "[worker] a record naming no spec branch denies"
launch "PLANWRIGHT_WORKER_SESSION_RECORD=$REC git merge --ff-only origin/$SB"
expect deny "[worker] a branch named only in command text denies"
rec "spec_branch=$SB" "spec_branch=$SB2"
launch "git merge --ff-only origin/$SB"
expect deny "[worker] a record naming the field twice reads as naming none"
rec "spec_branch=$SB"
FORGED="$FL/forged.record"
cp "$REC" "$FORGED"
PLANWRIGHT_WORKER_SESSION_RECORD=$FORGED pg worker "git merge --ff-only origin/$SB" "$FL" "$FL"
expect deny "[worker] a record inside the worktree is no record"
ln -sf "$REC" "$SANDBOX/records/link.record"
PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/records/link.record pg worker "git merge --ff-only origin/$SB" "$FL" "$FL"
expect deny "[worker] a symlinked record is no record"
for bad in planwright/demo/spec planwright/flight/other-worker-0123abcd planwright/demo/task-2 \
  'planwright/demo/../x' planwright/demo/ 'planwright/demo/a b' refs/heads/planwright/demo/amendment-1; do
  rec "spec_branch=$bad"
  launch "git merge --ff-only origin/$bad"
  expect deny "[worker] a record naming '$bad' admits nothing"
done
rec "spec_branch=$SB"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower "git merge --ff-only origin/$SB" "$FL" "$FL"
expect deny "[tower] the record admits nothing at another tier"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "git merge --ff-only origin/$SB" "$UNIT" "$UNIT"
expect deny "[worker] in a checkout other than the record's flight branch the merge denies"

echo "# a worktree holding the launch-named spec branch takes the PR base, and nothing else"
AM="$SANDBOX/amend"
gitq -C "$FL" worktree add -b "$SB" "$AM" "origin/$SB"
gitq -C "$FL" worktree add -b "$SB2" "$SANDBOX/amend2" "origin/$SB2"
am() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "${2:-$AM}" "${2:-$AM}"; }
rec "spec_branch=$SB"
for cmd in 'git merge origin/main' 'git merge --no-edit origin/main' 'git merge refs/remotes/origin/main'; do
  am "$cmd"
  expect defer "[worker] the named, checked-out spec branch admits: $cmd"
done
for cmd in "git merge origin/$SB2" "git merge origin/$OTHERFL" 'git merge origin/planwright/demo/task-2' \
  "git merge origin/$SB" 'git merge HEAD~1' 'git merge origin/main origin/planwright/demo/task-2' 'git merge' \
  'git merge --ff-only origin/planwright/demo/task-2'; do
  am "$cmd"
  expect deny "[worker] the named spec branch refuses any other source: $cmd"
done
reason_has 'takes only the PR base' "[worker] the other-source refusal names the rule"
am 'git pull origin main'
expect deny "[worker] a pull is not the merge the named spec branch is admitted"
am 'git commit --amend --no-edit'
expect deny "[worker] a commit amend on the named spec branch still denies"
am 'git merge origin/main && git rebase origin/main'
expect deny "[worker] a rebase after the admitted merge still denies (nothing is cached)"
am 'git merge origin/main' "$SANDBOX/amend2"
expect deny "[worker] the same merge in a worktree the record does not name denies"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker 'git merge origin/main' "$FL" "$AM"
expect deny "[worker] the same merge run in another checkout than the spec worktree denies"
rec "spec_branch=$SB2"
am 'git merge origin/main'
expect deny "[worker] a checked-out spec branch the launch record does not name refuses origin/main"
reason_has "allowed only on the session's own unit branch" "[worker] it gets the unit-branch text"
rm -f "$REC"
am 'git merge origin/main'
expect deny "[worker] with no record, the spec branch refuses origin/main"
rec "spec_branch=$SB"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower 'git merge origin/main' "$AM" "$AM"
expect deny "[tower] the record admits nothing at another tier"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: deny' 'unpushed_rewrite: allow'
am 'git merge origin/main'
expect deny "[worker] worker_base_merge deny refuses it on the named spec branch too"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

finish
