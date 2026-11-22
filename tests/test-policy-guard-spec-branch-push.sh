#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a spec PR branch outside the
# protected floor (planwright/<spec>/amendment-<n>, planwright/<spec>/spec-rework)
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

REC="$SANDBOX/records/session.record"
mkdir -p "$SANDBOX/records"
rec() { printf '%s\n' "$@" >"$REC"; }
launch() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "${2:-$FL}" "${2:-$FL}"; }

echo "# a launch naming no spec branch pushes none"
rec "unit_branch=$MYFL"
for b in "$SB" "$RW"; do
  for cmd in "git push origin HEAD:$b" "git push origin HEAD:refs/heads/$b" "git push origin :$b" \
    "git push --delete origin $b"; do
    launch "$cmd"
    expect deny "[worker, no spec_branch] a push to a spec PR branch denies: $cmd"
  done
done
launch "git push origin HEAD:Planwright/Demo/Amendment-1"
expect deny "[worker] a case-varied spelling of an amendment branch denies"
launch "git push origin HEAD:$MYFL"
expect defer "[worker] the push of its own flight branch is unchanged"

echo "# a launch naming the spec branch syncs it locally and still pushes it nowhere"
rec "unit_branch=$MYFL" "spec_branch=$SB"
launch "git merge --ff-only origin/$SB"
expect defer "[worker] the fast-forward to the named spec branch's PR head stays admitted"
gitq -C "$FL" merge --ff-only "origin/$SB"
gitq -C "$FL" merge --no-edit origin/main
for cmd in "git push origin HEAD:$SB" "git push origin HEAD:refs/heads/$SB"; do
  launch "$cmd"
  expect deny "[worker, spec_branch=$SB] a clean base merge pushed to the named spec branch denies: $cmd"
done
reason_has 'kickoff-spec-push\.sh' "[worker] the refusal names the kickoff push as the one route"
commit_file "$FL" scripts/policy-guard.sh 'a guard edit'
launch "git push origin HEAD:$SB"
expect deny "[worker, spec_branch=$SB] a non-spec commit pushed to the named spec branch denies"
gitq -C "$FL" reset --hard "origin/$MYFL"

AM="$SANDBOX/amend"
gitq -C "$FL" worktree add -b "$SB" "$AM" "origin/$SB"
am() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "$AM" "$AM"; }
am 'git merge origin/main'
expect defer "[worker, spec worktree] the base merge on the named spec branch stays admitted"
gitq -C "$AM" merge --no-edit origin/main
for cmd in "git push origin $SB" "git push origin HEAD" "git push origin HEAD:$SB" "git push" "git push -u origin $SB"; do
  am "$cmd"
  expect deny "[worker, spec worktree] the push of the named spec branch denies: $cmd"
done

echo "# a host ref write to a spec PR branch denies"
for cmd in "gh api -X PATCH repos/acme/widgets/git/refs/heads/$SB -f sha=abc" \
  "gh api -X DELETE repos/acme/widgets/git/refs/heads/$RW" \
  "gh api repos/acme/widgets/git/refs -f ref=refs/heads/$SB -f sha=abc" \
  "gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=$RW"; do
  launch "$cmd"
  expect deny "[worker] a host write to a spec PR branch denies: $cmd"
done

echo "# the kickoff publishes only through its push helper"
KICKOFF_PUSH='"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo'
NOREC="$SANDBOX/records/none.record"
: >"$NOREC"
kick() { PLANWRIGHT_WORKER_SCOPE=kickoff-demo PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "$1" "$AM" "$AM"; }
kick "$KICKOFF_PUSH"
expect defer "[kickoff-demo] the kickoff push helper on its amendment branch still defers"
for cmd in "git push origin $SB" "git push -u origin $SB" "git push origin HEAD"; do
  kick "$cmd"
  expect deny "[kickoff-demo] a plain push of its amendment branch denies: $cmd"
done
KO="$SANDBOX/kick"
gitq -C "$FL" worktree add -b "$RW" "$KO" "origin/$RW"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo PLANWRIGHT_WORKER_SESSION_RECORD=$NOREC pg worker "git push origin $RW" "$KO" "$KO"
expect deny "[kickoff-demo] a plain push of its spec-rework branch denies"

echo "# every tier"
pg tower "git push origin HEAD:$SB" "$FL" "$FL"
expect deny "[tower] a push to an amendment branch denies"
pg tower "git push origin HEAD:$RW" "$FL" "$FL"
expect deny "[tower] a push to a spec-rework branch denies"

no_gh_calls
finish
