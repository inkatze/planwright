#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a worker carrying a spec PR
# whose branch has fallen behind main reaches its own PR head and syncs it
# with main, with no operator step. On a spec branch its launch names (the
# session record's spec_branch, or its kickoff scope's), checked out in its own
# linked worktree, it may fast-forward to that branch's own remote-tracking ref
# and then merge the PR base; every refusal on that path names the route.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# The carriers under test come from each case alone, never from the session
# that runs the suite.
unset PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_SESSION_RECORD
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

CARRY=planwright/carry/spec-rework
OTHER=planwright/other/spec-rework
for b in "$CARRY" "$OTHER"; do
  gitq -C "$SEED" switch -c "$b" main
  gitq -C "$SEED" commit --allow-empty -m "pushed on $b"
  gitq -C "$SEED" push origin "$b"
done

K="$SANDBOX/carry"
gitq clone "$ORIGIN" "$K"
gitq -C "$K" remote set-head origin main
gitq -C "$K" switch --detach main
W="$SANDBOX/w-carry"
gitq -C "$K" worktree add -b "$CARRY" "$W" "origin/$CARRY"

# The PR head moves on from another checkout, and main moves one commit past
# the spec branch: the reused worktree is behind both.
gitq -C "$SEED" switch "$CARRY"
gitq -C "$SEED" commit --allow-empty -m "pushed from elsewhere"
gitq -C "$SEED" push origin "$CARRY"
gitq -C "$SEED" switch main
gitq -C "$SEED" commit --allow-empty -m "main moves on"
gitq -C "$SEED" push origin main
gitq -C "$K" fetch origin

FL="$SANDBOX/w-flight"
gitq -C "$K" worktree add -b planwright/flight/carry-0123abcd "$FL" origin/main

REC="$SANDBOX/records/session.record"
mkdir -p "$SANDBOX/records"
printf '%s\n' "spec_branch=$CARRY" >"$REC"
NOREC="$SANDBOX/records/none.record"
: >"$NOREC"

# kick <command> [<dir>] — the kickoff session for spec carry; rec — a worker
# whose launch record names the carry branch.
kick() { PLANWRIGHT_WORKER_SCOPE=kickoff-carry PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "$1" "${2:-$W}" "${2:-$W}"; }
rec() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "${2:-$W}" "${2:-$W}"; }

echo "# the carry worker reaches its own PR head"
for who in kick rec; do
  for cmd in "git merge --ff-only origin/$CARRY" "git merge --ff-only refs/remotes/origin/$CARRY" \
    "git merge --ff-only --quiet origin/$CARRY"; do
    "$who" "$cmd"
    expect defer "[$who] the fast-forward to the spec branch's own PR head defers: $cmd"
  done
done

echo "# nothing wider rides on it"
for cmd in "git merge origin/$CARRY" "git merge --no-ff origin/$CARRY" "git merge --ff-only --no-ff origin/$CARRY" \
  "git merge --ff-only origin/$CARRY origin/main" "git merge --ff-only $CARRY" "git merge --ff-only origin/$OTHER" \
  "git merge --ff-only --squash origin/$CARRY" "git merge --ff-only -s ours origin/$CARRY"; do
  kick "$cmd"
  expect deny "[kick] a merge that is not the plain fast-forward to the PR head refuses: $cmd"
done
gitq -C "$W" branch "origin/$CARRY" HEAD
kick "git merge --ff-only origin/$CARRY"
expect deny "[kick] a local branch shadowing the PR head's remote-tracking ref refuses"
gitq -C "$W" branch -D "origin/$CARRY"
gitq -C "$W" tag head-tag "origin/$CARRY"
kick 'git merge --ff-only head-tag'
expect deny "[kick] a tag at the PR head refuses"
PLANWRIGHT_WORKER_SCOPE=kickoff-other PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "git merge --ff-only origin/$CARRY" "$W" "$W"
expect deny "[kickoff-other] another spec's kickoff may not fast-forward this spec branch"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: deny' 'unpushed_rewrite: allow'
kick "git merge --ff-only origin/$CARRY"
expect deny "[kick] worker_base_merge deny refuses the fast-forward too"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

echo "# refusals on the carry path name the route"
kick "git merge origin/$CARRY"
reason_has "git merge --ff-only origin/$CARRY" "[kick] the refused merge of the PR head names the fast-forward"
reason_has 'git merge origin/main' "[kick] the refused merge of the PR head names the base merge"
kick 'git merge HEAD~1'
reason_has "git merge --ff-only origin/$CARRY" "[kick] another source's refusal names the route to the PR head"
for cmd in 'git pull origin main' "git pull --ff-only origin $CARRY" 'git pull' 'git pull --rebase origin main'; do
  rec "$cmd"
  expect deny "[rec] a pull on the spec branch refuses: $cmd"
  reason_has "git merge --ff-only origin/$CARRY" "[rec] the pull refusal names the fast-forward: $cmd"
  reason_has 'git merge origin/main' "[rec] the pull refusal names the base merge: $cmd"
done
rec "git merge origin/$CARRY" "$FL"
expect deny "[rec, flight] merging the spec branch into the flight branch still refuses"
reason_has "git switch $CARRY" "[rec, flight] the refusal names switching to the spec branch"
reason_has "git merge --ff-only origin/$CARRY" "[rec, flight] the refusal names the fast-forward there"

echo "# end to end: the head, then main, each run only once the guard admits it"
kick "git merge --ff-only origin/$CARRY"
expect defer "[kick] the fast-forward to the PR head defers"
[ "$DECISION" != defer ] || gitq -C "$W" merge --ff-only "origin/$CARRY"
kick 'git merge origin/main'
expect defer "[kick] then the PR base merges"
[ "$DECISION" != defer ] || gitq -C "$W" merge --no-edit origin/main
if git -C "$W" merge-base --is-ancestor "origin/$CARRY" HEAD && git -C "$W" merge-base --is-ancestor origin/main HEAD; then
  pass "the spec branch now holds its PR head and main, so its push fast-forwards the PR"
else
  fail "the spec branch is missing its PR head or main after the guard's verdicts"
fi

no_gh_calls
finish
