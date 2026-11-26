#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a spec PR branch outside the
# protected floor (planwright/<spec>/amendment-*, planwright/<spec>/spec-rework*)
# takes one agent push: the worker whose launch record names an
# amendment-<n> or spec-rework branch pushes, from its own worktree holding
# it, a fast-forward adding only clean merges of main (the sign-off branch's
# check). An amendment-<n> branch's content goes out through its kickoff
# session's kickoff-spec-push.sh. Every other push or host ref write to one
# denies at every tier, while the local sync of a spec branch the launch
# names stays admitted.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
unset PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_SESSION_RECORD
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

# A git older than 2.40 cannot read attributes from an empty tree, which the
# clean-merge check needs, so there every push it would admit refuses instead.
PUSH_OK=deny
if git --attr-source="$(git hash-object -t tree /dev/null)" version >/dev/null 2>&1; then
  PUSH_OK=defer
fi
push_ok() { # <label>: a push the check admits, or refuses for the git version
  expect "$PUSH_OK" "$1"
  [ "$PUSH_OK" = defer ] || reason_has '2\.40' "$1 (refused for this git's version)"
}

SB=planwright/demo/amendment-1
RW=planwright/demo/spec-rework
MYFL=planwright/flight/spec-push-0123abcd

# commit_file <dir> <path> <content> — a commit touching one file.
commit_file() {
  mkdir -p "$1/$(dirname "$2")"
  printf '%s\n' "$3" >"$1/$2"
  gitq -C "$1" add -- "$2"
  gitq -C "$1" commit -m "touch $2"
}
# on_branch <dir> <branch> <label> — a setup checkpoint, so a failed fixture
# step never leaves a later deny passing on some other refusal.
on_branch() {
  if [ "$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null)" = "$2" ]; then
    pass "setup: $3"
  else
    fail "setup: $3 ($1 is not on $2)"
  fi
}
# rule_denies <label> — the deny came from the spec PR branch rule.
rule_denies() {
  expect deny "$1"
  reason_has 'a spec PR branch' "$1 (the spec PR branch rule)"
}

for b in "$SB" "$RW"; do
  gitq -C "$SEED" switch -c "$b" main
  commit_file "$SEED" specs/demo/requirements.md "pushed on $b"
  gitq -C "$SEED" push origin "$b"
done
gitq -C "$SEED" switch main
commit_file "$SEED" scripts/main-moves.sh 'main moves on'
gitq -C "$SEED" push origin main

FL="$SANDBOX/flight"
gitq clone "$ORIGIN" "$FL"
gitq -C "$FL" remote set-head origin main
gitq -C "$FL" switch -c "$MYFL" origin/main
gitq -C "$FL" push -u origin "$MYFL"
on_branch "$FL" "$MYFL" 'the flight clone is on its flight branch'

REC="$SANDBOX/records/session.record"
mkdir -p "$SANDBOX/records"
rec() { printf '%s\n' "$@" >"$REC"; }
launch() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "${2:-$FL}" "${2:-$FL}"; }

echo "# a launch naming no spec branch pushes none"
rec "unit_branch=$MYFL"
for b in "$SB" "$RW" planwright/demo/amendment-12 planwright/demo/amendment-x \
  planwright/demo/spec-rework-2 planwright/demo/spec-reworkx; do
  for cmd in "git push origin HEAD:$b" "git push origin HEAD:refs/heads/$b" "git push origin HEAD:heads/$b" \
    "git push origin :$b" "git push --delete origin $b" "git push origin refs/heads/$MYFL:refs/heads/$b"; do
    launch "$cmd"
    rule_denies "[worker, no spec_branch] a push to a spec PR branch denies: $cmd"
  done
done
for cmd in "git push origin HEAD:Planwright/Demo/Amendment-1" "git push origin HEAD:refs/heads/Planwright/Demo/Spec-Rework" \
  "git push origin $MYFL HEAD:$SB" "git push origin HEAD:$RW $MYFL"; do
  launch "$cmd"
  rule_denies "[worker] a case-varied or mixed-refspec push still denies: $cmd"
done
for cmd in "git push origin :refs/heads/$SB" "git push -d origin $SB"; do
  launch "$cmd"
  rule_denies "[worker] a delete spelled past the unit-branch delete check still denies: $cmd"
  reads none "[worker] the spec PR branch rule denies before any protected-set read: $cmd"
done
for b in "$MYFL" planwright/demo/task-7 planwright/demo/amendment planwright/amendment-1 \
  planwright/demo/x/amendment-1 planwright/flight/amendment-branch-push-0123abcd planwright/flight/spec-rework-0123abcd; do
  launch "git push origin HEAD:$b"
  expect defer "[worker] a branch that is no spec PR branch pushes as before: $b"
done

echo "# a bare push whose upstream is a spec PR branch denies"
UP="$SANDBOX/upstream"
gitq clone "$ORIGIN" "$UP"
gitq -C "$UP" remote set-head origin main
gitq -C "$UP" switch -c "$MYFL" "origin/$SB"
gitq -C "$UP" branch --set-upstream-to="origin/$SB" "$MYFL"
on_branch "$UP" "$MYFL" 'the upstream clone tracks the amendment branch'
for cmd in 'git push' 'git push origin'; do
  launch "$cmd" "$UP"
  rule_denies "[worker] a bare push tracking an amendment branch denies: $cmd"
done

echo "# a launch naming the spec branch syncs it locally and pushes it only from its worktree"
rec "unit_branch=$MYFL" "spec_branch=$SB"
launch "git merge --ff-only origin/$SB"
expect defer "[worker] the fast-forward to the named spec branch's PR head stays admitted"
gitq -C "$FL" merge --ff-only "origin/$SB"
gitq -C "$FL" merge --no-edit origin/main
for cmd in "git push origin HEAD:$SB" "git push origin HEAD:refs/heads/$SB"; do
  launch "$cmd"
  rule_denies "[worker, spec_branch=$SB] a clean base merge pushed from the flight checkout denies: $cmd"
  reason_has 'outside the worktree holding' "[worker, spec_branch=$SB] the refusal names the worktree the push runs from: $cmd"
done

AM="$SANDBOX/amend"
gitq -C "$FL" worktree add -b "$SB" "$AM" "origin/$SB"
on_branch "$AM" "$SB" 'the spec worktree holds the amendment branch'
am() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "$AM" "$AM"; }
am 'git merge origin/main'
expect defer "[worker, spec worktree] the base merge on the named spec branch stays admitted"
gitq -C "$AM" merge --no-edit origin/main
for cmd in "git push origin $SB" "git push origin HEAD" "git push origin HEAD:$SB" "git push origin HEAD:refs/heads/$SB" \
  "git push -u origin $SB"; do
  am "$cmd"
  push_ok "[worker, spec worktree] the recorded worker's clean merge of main pushes to its amendment branch: $cmd"
done
for cmd in 'git push' 'git push origin'; do
  am "$cmd"
  rule_denies "[worker, spec worktree] a push naming no refspec still denies: $cmd"
done

echo "# a host ref write to a spec PR branch denies"
for cmd in "gh api -X PATCH repos/acme/widgets/git/refs/heads/$SB -f sha=abc" \
  "gh api -X DELETE repos/acme/widgets/git/refs/heads/$RW" \
  "gh api repos/acme/widgets/git/refs -f ref=refs/heads/$SB -f sha=abc" \
  "gh api repos/acme/widgets/git/refs -f ref=refs/heads/planwright/demo/spec-rework-2 -f sha=abc" \
  "gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=$RW" \
  "gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=refs/heads/$SB" \
  "gh api -X POST repos/acme/widgets/branches/$SB/rename -f new_name=planwright/demo/zzz" \
  "gh api -X POST repos/acme/widgets/branches/planwright/demo/zzz/rename -f new_name=$SB" \
  "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{repositoryNameWithOwner:\"acme/widgets\",branchName:\"$SB\"},message:{headline:\"x\"},expectedHeadOid:\"abc\"}){commit{oid}}}'" \
  "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{qualifiedName:\"refs/heads/$RW\"},message:{headline:\"x\"},expectedHeadOid:\"abc\"}){commit{oid}}}'" \
  "gh api graphql -f query='mutation{createRef(input:{repositoryId:\"R\",name:\"refs/heads/$SB\",oid:\"abc\"}){ref{id}}}'"; do
  launch "$cmd"
  rule_denies "[worker] a host write to a spec PR branch denies: $cmd"
  reads none "[worker] the host write denies before any protected-set read: $cmd"
done
for cmd in "gh api graphql -f query='mutation{createLinkedBranch(input:{issueId:\"I_x\",oid:\"abc\",name:\"$MYFL\"}){linkedBranch{id}}}'" \
  "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{repositoryNameWithOwner:\"acme/widgets\",branchName:\"$MYFL\"},message:{headline:\"x\"},expectedHeadOid:\"abc\"}){commit{oid}}}'"; do
  launch "$cmd"
  expect defer "[worker] a GraphQL write naming a branch outside the rule defers: $cmd"
  reads protected_branches "[worker] it reads the protected set instead: $cmd"
done
launch "gh api graphql -f query='mutation{createLinkedBranch(input:{issueId:\"I_x\",oid:\"abc\",name:\"$SB\"}){linkedBranch{id}}}'"
rule_denies "[worker] a createLinkedBranch mutation naming a spec PR branch denies"
for b in "$SB" main; do
  for cmd in "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{repositoryNameWithOwner:\"acme/widgets\",branchName:\"\"\"$b\"\"\"},message:{headline:\"x\"},expectedHeadOid:\"abc\"}){commit{oid}}}'" \
    "gh api graphql -f query='mutation{createLinkedBranch(input:{issueId:\"I_x\",oid:\"abc\",name:\"\"\"$b\"\"\"}){linkedBranch{id}}}'"; do
    launch "$cmd"
    expect deny "[worker] a GraphQL block string naming the branch denies: $b"
    reason_has 'block string' "[worker] the refusal names the unread block string: $b"
  done
done
launch "gh api graphql -f query='mutation{createLinkedBranch(input:{issueId:\"I_x\",oid:\"abc\",name:\"main\"}){linkedBranch{id}}}'"
expect deny "[worker] a createLinkedBranch mutation naming main denies on the protected set"
launch "gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f 'branch=planwright/demo/amendment-1 run this'"
expect deny "[worker] a host write naming an unreadable branch still denies"
reason_has 'will not check' "[worker] an unreadable name gets the unchecked-name refusal, not the spec PR branch rule"

echo "# the kickoff publishes only through its push helper"
KICKOFF_PUSH='"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo'
NOREC="$SANDBOX/records/none.record"
: >"$NOREC"
kick() { PLANWRIGHT_WORKER_SCOPE=kickoff-demo PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "$1" "${2:-$AM}" "${2:-$AM}"; }
kick "$KICKOFF_PUSH"
expect defer "[kickoff-demo] the kickoff push helper on its amendment branch still defers"
for cmd in "git push origin $SB" "git push -u origin $SB" "git push origin HEAD"; do
  kick "$cmd"
  rule_denies "[kickoff-demo] a plain push of its amendment branch denies: $cmd"
done
KO="$SANDBOX/kick"
gitq -C "$FL" worktree add -b "$RW" "$KO" "origin/$RW"
on_branch "$KO" "$RW" 'the kickoff worktree holds the spec-rework branch'
kick "git push origin $RW" "$KO"
rule_denies "[kickoff-demo] a plain push of its spec-rework branch denies"
for cmd in "git push origin $RW" "git push origin HEAD:planwright/demo/amendment-x" "git push origin HEAD:Planwright/Demo/Amendment-1" \
  "git push origin HEAD:planwright/Demo/amendment-1"; do
  kick "$cmd" "$KO"
  rule_denies "[kickoff-demo] a hit the kickoff push helper does not take denies: $cmd"
  reason_has 'the operator publishes anything else' "[kickoff-demo] the refusal names the operator as the route: $cmd"
  case $REASON in
    *kickoff-spec-push.sh*) fail "[kickoff-demo] the refusal sends it to the kickoff push helper, which refuses it: $cmd" ;;
    *) pass "[kickoff-demo] the refusal does not send it to the kickoff push helper: $cmd" ;;
  esac
done
for cmd in "git push origin $SB" "git push origin HEAD"; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a1 PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "$cmd" "$AM" "$AM"
  rule_denies "[kickoff-demo-a1] the amendment kickoff's plain push of its own branch denies: $cmd"
done

echo "# the recorded worker's push is a pure merge of main and nothing else"
at_pr_head() { gitq -C "$1" reset -q --hard "origin/$2"; }
merged() { # <worktree> <branch>: a plain merge of main on the PR head
  at_pr_head "$1" "$2"
  gitq -C "$1" merge -q --no-edit origin/main
}
rec "unit_branch=$MYFL" "spec_branch=$RW"
ko() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "$KO" "$KO"; }
merged "$KO" "$RW"
for cmd in "git push origin $RW" "git push origin HEAD:refs/heads/$RW"; do
  ko "$cmd"
  push_ok "[worker, spec_branch=$RW] the recorded worker's clean merge of main pushes to its spec-rework branch: $cmd"
done
ko "git push origin HEAD:refs/heads/$SB"
rule_denies "[worker, spec_branch=$RW] a push to a spec PR branch the record does not name denies"
rec "unit_branch=$MYFL" "spec_branch=$SB"
merged "$AM" "$SB"
for cmd in "git push origin HEAD:Planwright/Demo/Amendment-1" "git push origin HEAD:refs/heads/$SB HEAD:refs/heads/$RW" \
  "git fetch origin && git push origin HEAD:refs/heads/$SB" "git push origin HEAD:refs/heads/$SB; echo pushed" \
  "git push --force origin HEAD:refs/heads/$SB" "git push origin +HEAD:refs/heads/$SB" "git push --delete origin $SB" \
  "git push origin :refs/heads/$SB" "git push origin origin/main:refs/heads/$SB" "git push origin HEAD~1:refs/heads/$SB"; do
  am "$cmd"
  expect deny "[worker, spec worktree] the record admits nothing else: $cmd"
done
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower "git push origin HEAD:refs/heads/$SB" "$AM" "$AM"
rule_denies "[tower] the record admits no push at another tier"

echo "# an unrecorded pusher is refused"
for r in "$NOREC" "$SANDBOX/records/missing.record"; do
  PLANWRIGHT_WORKER_SESSION_RECORD=$r pg worker "git push origin HEAD:refs/heads/$SB" "$AM" "$AM"
  rule_denies "[worker, no spec_branch] the clean merge pushed from the spec worktree denies (${r##*/})"
done
PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "PLANWRIGHT_WORKER_SESSION_RECORD=$REC git push origin HEAD:refs/heads/$SB" "$AM" "$AM"
expect deny "[worker, no spec_branch] an inline record assignment on the command opens no push"
PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "env PLANWRIGHT_WORKER_SESSION_RECORD=$REC git push origin HEAD:refs/heads/$SB" "$AM" "$AM"
expect deny "[worker, no spec_branch] an env-prefixed record assignment opens no push"
rec "unit_branch=$MYFL" "spec_branch=$RW"
am "git push origin HEAD:refs/heads/$SB"
rule_denies "[worker, spec_branch=$RW] a record naming another spec PR branch denies the push"
rec "unit_branch=$MYFL" "spec_branch=$SB"
rec "unit_branch=$MYFL" "spec_branch=$SB" "spec_branch=$SB"
am "git push origin HEAD:refs/heads/$SB"
rule_denies "[worker] a record naming the branch twice denies the push"
rec "unit_branch=$MYFL" "spec_branch=$SB"
kick "git push origin HEAD:refs/heads/$SB"
rule_denies "[kickoff-demo] a kickoff scope with no record still denies the raw push of the merge"

echo "# a merge carrying any extra change is refused"
for f in specs/demo/requirements.md scripts/main-moves.sh brand-new.txt; do
  at_pr_head "$AM" "$SB"
  gitq -C "$AM" merge -q --no-commit --no-ff origin/main
  commit_file "$AM" "$f" 'edited inside the merge'
  if [ "$(git -C "$AM" rev-list --count --merges "origin/$SB..HEAD")" = 1 ]; then
    pass "setup: the edited-merge fixture built one merge ($f)"
  else
    fail "setup: the edited-merge fixture did not build its merge ($f)"
  fi
  am "git push origin HEAD:refs/heads/$SB"
  expect deny "[worker, spec worktree] a merge that also changes $f denies"
  reason_has 'clean merge' "[worker, spec worktree] the refusal names the clean merge ($f)"
done
at_pr_head "$AM" "$SB"
gitq -C "$AM" merge -q --no-commit --no-ff origin/main
gitq -C "$AM" rm -q -f scripts/main-moves.sh
gitq -C "$AM" commit -q --no-edit
if [ "$(git -C "$AM" rev-list --count --merges "origin/$SB..HEAD")" = 1 ] && [ -z "$(git -C "$AM" ls-tree HEAD scripts/main-moves.sh)" ]; then
  pass "setup: the dropped-file fixture built a merge without main's file"
else
  fail "setup: the dropped-file fixture did not build its merge"
fi
am "git push origin HEAD:refs/heads/$SB"
expect deny "[worker, spec worktree] a merge that drops one of main's files denies"

echo "# a non-merge push is refused"
at_pr_head "$AM" "$SB"
commit_file "$AM" specs/demo/requirements.md 'a direct edit'
am "git push origin HEAD:refs/heads/$SB"
expect deny "[worker, spec worktree] a plain commit on the PR head denies"
merged "$AM" "$SB"
commit_file "$AM" README.md 'a commit after the merge'
am "git push origin HEAD:refs/heads/$SB"
expect deny "[worker, spec worktree] a plain commit on top of a clean merge denies"
at_pr_head "$AM" "$SB"
am "git push origin HEAD:refs/heads/$SB"
push_ok "[worker, spec worktree] a push adding nothing pushes, as on the sign-off branch"
gitq -C "$AM" switch -q --detach origin/main
commit_file "$AM" side.txt 'a line main never took'
SIDE=$(git -C "$AM" rev-parse HEAD)
gitq -C "$AM" switch -q "$SB"
at_pr_head "$AM" "$SB"
gitq -C "$AM" merge -q --no-edit "$SIDE"
if [ "$(git -C "$AM" rev-parse HEAD^2)" = "$SIDE" ]; then
  pass "setup: the side-line fixture merged a commit main does not hold"
else
  fail "setup: the side-line fixture did not build its merge"
fi
am "git push origin HEAD:refs/heads/$SB"
expect deny "[worker, spec worktree] a merge of a commit main does not hold denies"

echo "# a merge of any commit main holds, or two in a row, pushes"
merged "$AM" "$SB"
commit_file "$SEED" scripts/main-moves.sh 'main moves again'
gitq -C "$SEED" push -q origin main
am "git push origin HEAD:refs/heads/$SB"
push_ok "[worker, spec worktree] a merge of a main commit that is no longer the tip pushes"
gitq -C "$FL" fetch -q origin
gitq -C "$AM" merge -q --no-edit origin/main
if [ "$(git -C "$AM" rev-list --count --merges "origin/$SB..HEAD")" = 2 ]; then
  pass "setup: the two-merge fixture holds two merges"
else
  fail "setup: the two-merge fixture did not build two merges"
fi
am "git push origin HEAD:refs/heads/$SB"
push_ok "[worker, spec worktree] two merges of main in a row push"

echo "# worker_base_merge deny refuses the push"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: deny' 'unpushed_rewrite: allow'
am "git push origin HEAD:refs/heads/$SB"
expect deny "[worker, spec worktree] worker_base_merge deny refuses the recorded merge push"
reason_has 'worker_base_merge is deny' "[worker, spec worktree] the refusal names the knob"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
am "git push origin HEAD:refs/heads/$SB"
push_ok "[worker, spec worktree] with the knob back to allow the push is admitted again"

echo "# a recorded spelling outside the merge route still denies"
AX=planwright/demo/amendment-x
gitq -C "$SEED" push -q origin "$SB:refs/heads/$AX"
gitq -C "$FL" fetch -q origin
AXW="$SANDBOX/amend-x"
gitq -C "$FL" worktree add -b "$AX" "$AXW" "origin/$AX"
on_branch "$AXW" "$AX" 'the worktree holds the off-route amendment spelling'
gitq -C "$AXW" merge -q --no-edit origin/main
rec "unit_branch=$MYFL" "spec_branch=$AX"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker 'git merge origin/main' "$AXW" "$AXW"
expect defer "[worker, spec_branch=$AX] the record still syncs the branch locally"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "git push origin HEAD:refs/heads/$AX" "$AXW" "$AXW"
rule_denies "[worker, spec_branch=$AX] the clean merge pushed to an amendment branch with no number denies"
rec "unit_branch=$MYFL" "spec_branch=$SB"

echo "# every tier"
for b in "$SB" "$RW"; do
  for cmd in "git push origin HEAD:$b" "git push origin :$b" "git push --delete origin $b" \
    "gh api -X PATCH repos/acme/widgets/git/refs/heads/$b -f sha=abc" "gh api -X DELETE repos/acme/widgets/git/refs/heads/$b"; do
    pg tower "$cmd" "$FL" "$FL"
    rule_denies "[tower] a push or host ref write to a spec PR branch denies: $cmd"
  done
  pg mission-control "gh api -X PATCH repos/acme/widgets/git/refs/heads/$b -f sha=abc" "$FL" "$FL"
  expect deny "[mission-control] a host ref write to a spec PR branch denies: $b"
  reason_has 'mission control writes no branch' "[mission-control] it keeps mission control's own refusal: $b"
done
pg tower "git push origin HEAD:$MYFL" "$FL" "$FL"
expect defer "[tower] a push to a branch outside the rule defers"
reads protected_branches "[tower] it reads the protected set instead"

no_gh_calls
finish
