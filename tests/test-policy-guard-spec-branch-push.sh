#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a spec PR branch outside the
# protected floor (planwright/<spec>/amendment-*, planwright/<spec>/spec-rework*)
# is published only by its kickoff session through kickoff-spec-push.sh. Every
# other push or host ref write to one denies at every tier, whether or not the
# launch record names the branch, while the local sync of a spec branch the
# launch names stays admitted.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
unset PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_SESSION_RECORD
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

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

echo "# a launch naming the spec branch syncs it locally and still pushes it nowhere"
rec "unit_branch=$MYFL" "spec_branch=$SB"
launch "git merge --ff-only origin/$SB"
expect defer "[worker] the fast-forward to the named spec branch's PR head stays admitted"
gitq -C "$FL" merge --ff-only "origin/$SB"
gitq -C "$FL" merge --no-edit origin/main
for cmd in "git push origin HEAD:$SB" "git push origin HEAD:refs/heads/$SB"; do
  launch "$cmd"
  rule_denies "[worker, spec_branch=$SB] a clean base merge pushed to the named spec branch denies: $cmd"
done
reason_has 'kickoff-spec-push\.sh' "[worker] the refusal names the kickoff push as the one route"

AM="$SANDBOX/amend"
gitq -C "$FL" worktree add -b "$SB" "$AM" "origin/$SB"
on_branch "$AM" "$SB" 'the spec worktree holds the amendment branch'
am() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "$AM" "$AM"; }
am 'git merge origin/main'
expect defer "[worker, spec worktree] the base merge on the named spec branch stays admitted"
gitq -C "$AM" merge --no-edit origin/main
for cmd in "git push origin $SB" "git push origin HEAD" "git push origin HEAD:$SB" "git push" "git push -u origin $SB"; do
  am "$cmd"
  rule_denies "[worker, spec worktree] the push of the named spec branch denies: $cmd"
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
  "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{repositoryNameWithOwner:\"acme/widgets\",branchName:\"$SB\"},message:{headline:\"x\"},expectedHeadOid:\"abc\"}){commit{oid}}}'"; do
  launch "$cmd"
  rule_denies "[worker] a host write to a spec PR branch denies: $cmd"
done
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

echo "# every tier"
for b in "$SB" "$RW"; do
  pg tower "git push origin HEAD:$b" "$FL" "$FL"
  expect deny "[tower] a push to a spec PR branch denies: $b"
  pg tower "gh api -X PATCH repos/acme/widgets/git/refs/heads/$b -f sha=abc" "$FL" "$FL"
  rule_denies "[tower] a host ref write to a spec PR branch denies: $b"
  pg mission-control "gh api -X PATCH repos/acme/widgets/git/refs/heads/$b -f sha=abc" "$FL" "$FL"
  expect deny "[mission-control] a host ref write to a spec PR branch denies: $b"
  reason_has 'mission control writes no branch' "[mission-control] it keeps mission control's own refusal: $b"
done

no_gh_calls
finish
