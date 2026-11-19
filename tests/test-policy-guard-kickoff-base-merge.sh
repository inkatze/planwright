#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a kickoff session syncing its
# own spec PR branch with the PR base. A worker whose launch scope names a
# spec's kickoff may merge the PR base, plainly, into the spec branch that
# scope names, checked out in its own linked worktree, under worker_base_merge;
# nothing else on that branch, and nothing on any other.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# The carriers under test come from each case alone, never from the session
# that runs the suite.
unset PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_SESSION_RECORD
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

RW=planwright/demo/spec-rework
AM=planwright/demo/amendment-1
OTHER_RW=planwright/other/spec-rework
NOTES=planwright/demo/notes
for b in "$RW" "$AM" "$OTHER_RW" "$NOTES"; do
  gitq -C "$SEED" switch -c "$b" main
  gitq -C "$SEED" commit --allow-empty -m "pushed on $b"
  gitq -C "$SEED" push origin "$b"
done
gitq -C "$SEED" switch main
gitq -C "$SEED" commit --allow-empty -m "main moves on"
gitq -C "$SEED" push origin main

K="$SANDBOX/kick"
gitq clone "$ORIGIN" "$K"
gitq -C "$K" remote set-head origin main
gitq -C "$K" switch --detach main
W_RW="$SANDBOX/w-rework"
W_SPEC="$SANDBOX/w-spec"
W_AM="$SANDBOX/w-amend"
W_OTHER="$SANDBOX/w-other"
W_NOTES="$SANDBOX/w-notes"
W_MAIN="$SANDBOX/w-main"
gitq -C "$K" worktree add -b "$RW" "$W_RW" "origin/$RW"
gitq -C "$K" worktree add -b planwright/demo/spec "$W_SPEC" origin/planwright/demo/spec
gitq -C "$K" worktree add -b "$AM" "$W_AM" "origin/$AM"
gitq -C "$K" worktree add -b "$OTHER_RW" "$W_OTHER" "origin/$OTHER_RW"
gitq -C "$K" worktree add -b "$NOTES" "$W_NOTES" "origin/$NOTES"
gitq -C "$K" worktree add "$W_MAIN" main
PRIMARY_MAIN="$SANDBOX/primary-main"
gitq clone "$ORIGIN" "$PRIMARY_MAIN"
gitq -C "$PRIMARY_MAIN" remote set-head origin main

# kk <scope> <command> <worktree> [<project dir>] — a worker launched with
# <scope> whose shell is in <worktree>.
kk() { PLANWRIGHT_WORKER_SCOPE=$1 pg worker "$2" "$3" "${4:-$3}"; }

echo "# the kickoff merges the PR base into the spec branch its scope names"
for w in "$W_RW" "$W_SPEC" "$W_AM"; do
  kk kickoff-demo 'git merge origin/main' "$w"
  expect defer "[worker, kickoff-demo] the PR base merges into ${w##*/}"
done
for cmd in 'git merge --no-edit origin/main' "git merge --no-ff -m 'sync main' origin/main" \
  'git merge refs/remotes/origin/main' 'git merge --quiet --no-edit origin/main'; do
  kk kickoff-demo "$cmd" "$W_RW"
  expect defer "[worker, kickoff-demo] a plain spelling of the base merge defers: $cmd"
done
for scope in kickoff-demo-a1 kickoff-demo-a1-delta; do
  kk "$scope" 'git merge origin/main' "$W_AM"
  expect defer "[worker, $scope] an amendment kickoff merges the PR base into its amendment branch"
done

echo "# another spec's branch, main, and a branch the scope does not name"
kk kickoff-demo 'git merge origin/main' "$W_OTHER"
expect deny "[worker, kickoff-demo] another spec's spec-rework branch refuses the merge"
kk kickoff-other 'git merge origin/main' "$W_RW"
expect deny "[worker, kickoff-other] another spec's kickoff refuses the merge on demo's branch"
for w in "$W_MAIN" "$PRIMARY_MAIN"; do
  kk kickoff-demo 'git merge origin/main' "$w"
  expect deny "[worker, kickoff-demo] main refuses the merge (${w##*/})"
done
kk kickoff-demo 'git merge origin/main' "$W_NOTES"
expect deny "[worker, kickoff-demo] a branch of the spec the scope does not name refuses the merge"
for w in "$W_RW" "$W_SPEC"; do
  kk kickoff-demo-a1 'git merge origin/main' "$w"
  expect deny "[worker, kickoff-demo-a1] an amendment kickoff refuses the merge on ${w##*/}"
done
kk kickoff-demo-a2 'git merge origin/main' "$W_AM"
expect deny "[worker, kickoff-demo-a2] another amendment's kickoff refuses the merge on amendment-1"
for scope in kickoff-demox kickoff-dem xkickoff-demo kickoff-demo-x task-1 ''; do
  kk "$scope" 'git merge origin/main' "$W_RW"
  expect deny "[worker, scope '$scope'] a scope that names no demo kickoff refuses the merge"
done
kk kickoff-demo 'git merge origin/main' "$W_OTHER" "$W_RW"
expect deny "[worker, kickoff-demo] the merge in another spec's worktree than the session's own refuses"
kk kickoff-demo "git -C $W_OTHER merge origin/main" "$W_RW"
expect deny "[worker, kickoff-demo] a -C into another spec's worktree refuses"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg tower 'git merge origin/main' "$W_RW" "$W_RW"
expect deny "[tower, kickoff-demo] the scope admits nothing at another tier"

echo "# the scope comes from the launch, never from the command"
kk '' 'PLANWRIGHT_WORKER_SCOPE=kickoff-demo git merge origin/main' "$W_RW"
expect deny "[worker] a scope named only in the command text admits nothing"
kk '' 'export PLANWRIGHT_WORKER_SCOPE=kickoff-demo && git merge origin/main' "$W_RW"
expect deny "[worker] a scope exported earlier in the command admits nothing"

echo "# the merge takes the PR base and nothing else"
for cmd in "git merge origin/$OTHER_RW" 'git merge origin/planwright/demo/task-1' 'git merge HEAD~1' \
  'git merge' 'git merge origin/main origin/planwright/demo/task-1' "git merge origin/$NOTES" \
  "git merge --ff-only origin/$AM"; do
  kk kickoff-demo "$cmd" "$W_RW"
  expect deny "[worker, kickoff-demo] a source other than the PR base refuses: $cmd"
done
reason_has 'takes only the PR base' "[worker, kickoff-demo] the other-source refusal names the rule"
gitq -C "$W_RW" tag base-tag origin/main
kk kickoff-demo 'git merge base-tag' "$W_RW"
expect deny "[worker, kickoff-demo] a tag at the PR base's commit refuses"
gitq -C "$W_RW" branch origin/main HEAD
kk kickoff-demo 'git merge origin/main' "$W_RW"
expect deny "[worker, kickoff-demo] a local branch shadowing origin/main refuses"
gitq -C "$W_RW" branch -D origin/main
kk kickoff-demo 'git pull origin main' "$W_RW"
expect deny "[worker, kickoff-demo] a pull is not the merge the spec branch is admitted"

echo "# options that change what the merge makes refuse"
for cmd in 'git merge --squash origin/main' 'git merge --sq origin/main' 'git merge -s ours origin/main' \
  'git merge -sours origin/main' 'git merge --strategy=ours origin/main' 'git merge --strategy ours origin/main' \
  'git merge -X theirs origin/main' 'git merge -Xours origin/main' 'git merge --strategy-option=ours origin/main' \
  'git merge --allow-unrelated-histories origin/main' 'git merge --no-commit origin/main' \
  'git merge --autostash origin/main' 'git merge --no-e origin/main' 'git merge "--$OPT" origin/main'; do
  kk kickoff-demo "$cmd" "$W_RW"
  expect deny "[worker, kickoff-demo] a meaning-changing or unreadable option refuses: $cmd"
done
reason_has 'plain merge' "[worker, kickoff-demo] the option refusal names the plain merge it admits"

echo "# no history rewrite rides along"
for cmd in 'git rebase origin/main' 'git pull --rebase origin main' 'git merge origin/main && git rebase origin/main' \
  'git commit --amend --no-edit' 'git push --force origin HEAD' "git push --force-with-lease origin HEAD:$RW" \
  "git push origin +HEAD:$RW"; do
  kk kickoff-demo "$cmd" "$W_RW"
  expect deny "[worker, kickoff-demo] a rewrite or forced push on the spec branch refuses: $cmd"
done
kk kickoff-demo 'git push origin HEAD:planwright/demo/spec' "$W_SPEC"
expect deny "[worker, kickoff-demo] a raw push to the spec branch still refuses"

echo "# worker_base_merge governs it"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: deny' 'unpushed_rewrite: allow'
for w in "$W_RW" "$W_SPEC"; do
  kk kickoff-demo 'git merge origin/main' "$w"
  expect deny "[worker, kickoff-demo] worker_base_merge deny refuses the merge on ${w##*/}"
  reason_has 'worker_base_merge is deny' "[worker, kickoff-demo] the refusal names the knob (${w##*/})"
done
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

echo "# a launch-named spec branch takes the same plain merge"
REC="$SANDBOX/records/session.record"
mkdir -p "$SANDBOX/records"
printf '%s\n' "spec_branch=$AM" >"$REC"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker 'git merge origin/main' "$W_AM" "$W_AM"
expect defer "[worker, record] the launch-named spec branch still merges the PR base"
for cmd in 'git merge --squash origin/main' 'git merge -s ours origin/main'; do
  PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$cmd" "$W_AM" "$W_AM"
  expect deny "[worker, record] the launch-named spec branch refuses: $cmd"
done

no_gh_calls
finish
