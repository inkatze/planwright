#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a worker launched on a spec's
# own sign-off PR (its session record's spec_branch is planwright/<spec>/spec,
# a protected branch) landing a forward-merge of main there. It may build the
# merge with a plain git merge of the PR base in the worktree holding that
# branch, and push the branch, each as the command's only act, when every
# commit the push adds is a merge of main that changes no spec-bundle file and
# the push fast-forwards. Anything else on that branch still refuses, and the
# kickoff remains the only session that writes the spec itself.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
unset PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_SESSION_RECORD
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

# Every git this suite runs, the guard's own reads included, sees scratch
# configuration only.
mkdir -p "$SANDBOX/home" "$SANDBOX/xdg"
: >"$SANDBOX/gitconfig"
HOME=$SANDBOX/home
XDG_CONFIG_HOME=$SANDBOX/xdg
GIT_CONFIG_GLOBAL=$SANDBOX/gitconfig
export HOME XDG_CONFIG_HOME GIT_CONFIG_GLOBAL

SB=planwright/demo/spec
OTHER_SB=planwright/other/spec
MYFL=planwright/flight/spec-sync-0123abcd

put() { # <dir> <path> <text>
  mkdir -p "$1/$(dirname "$2")"
  printf '%s\n' "$3" >"$1/$2"
}

# main carries code and another spec's bundle; demo's spec branch carries its
# own bundle; then main moves on, touching both of main's files.
gitq -C "$SEED" switch main
put "$SEED" src.txt v1
put "$SEED" specs/other/tasks.md 'other v1'
gitq -C "$SEED" add -A
gitq -C "$SEED" commit -m 'main: code and another bundle'
gitq -C "$SEED" push origin main
gitq -C "$SEED" switch "$SB"
gitq -C "$SEED" merge --no-edit main
for f in requirements.md design.md tasks.md test-spec.md kickoff-brief.md; do
  put "$SEED" "specs/demo/$f" "demo $f v1"
done
gitq -C "$SEED" add -A
gitq -C "$SEED" commit -m 'demo: the signed-off bundle'
gitq -C "$SEED" push origin "$SB"
gitq -C "$SEED" switch -c "$OTHER_SB" main
gitq -C "$SEED" commit --allow-empty -m "pushed on $OTHER_SB"
gitq -C "$SEED" push origin "$OTHER_SB"
gitq -C "$SEED" switch main
put "$SEED" src.txt v2
put "$SEED" specs/other/tasks.md 'other v2'
gitq -C "$SEED" add -A
gitq -C "$SEED" commit -m 'main moves on'
gitq -C "$SEED" push origin main

K="$SANDBOX/kick"
gitq clone "$ORIGIN" "$K"
gitq -C "$K" remote set-head origin main
gitq -C "$K" switch --detach main
W="$SANDBOX/w-spec"
FL="$SANDBOX/w-flight"
W_OTHER="$SANDBOX/w-other"
gitq -C "$K" worktree add -b "$SB" "$W" "origin/$SB"
gitq -C "$K" worktree add -b "$MYFL" "$FL" origin/main
gitq -C "$K" worktree add -b "$OTHER_SB" "$W_OTHER" "origin/$OTHER_SB"
# A second clone holding the same branch: a checkout the record does not name.
K2="$SANDBOX/kick2"
gitq clone "$ORIGIN" "$K2"
gitq -C "$K2" remote set-head origin main
gitq -C "$K2" switch --detach main
W2="$SANDBOX/w2-spec"
gitq -C "$K2" worktree add -b "$SB" "$W2" "origin/$SB"

REC="$SANDBOX/records/session.record"
mkdir -p "$SANDBOX/records"
rec() { printf '%s\n' "$@" >"$REC"; }
rec "unit_branch=$MYFL" "spec_branch=$SB"
# pw <command> <cwd> [<project dir>] — the worker launched on demo's spec PR.
pw() { PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker "$1" "$2" "${3:-$2}"; }

# State builders, raw git the guard never sees.
at_pr_head() { gitq -C "$1" reset --hard "origin/$SB"; }
merged() { # <worktree>: a plain merge of main on the PR head
  at_pr_head "$1"
  gitq -C "$1" merge --no-edit origin/main
}

PUSHES=("git push origin $SB" "git push origin HEAD:refs/heads/$SB" "git push origin HEAD:$SB" "git push -u origin HEAD")

echo "# the merge of main builds in the record's spec checkout"
at_pr_head "$W"
for cmd in 'git merge origin/main' 'git merge --no-edit origin/main'; do
  pw "$cmd" "$W"
  expect defer "[worker, record] the PR base merges into the protected spec branch: $cmd"
done

echo "# the merge takes origin/main alone, plainly, as the only act"
for cmd in "git merge origin/planwright/demo/task-2" "git merge origin/$OTHER_SB" 'git merge HEAD~1' 'git merge' \
  'git merge origin/main origin/planwright/demo/task-2' "git merge --ff-only origin/$SB" \
  'git merge --no-ff origin/main' 'git merge -m sync origin/main' 'git merge --squash origin/main' \
  'git merge -s ours origin/main' 'git merge --no-commit origin/main' 'git pull origin main' \
  'git fetch origin && git merge origin/main' 'git merge origin/main && git push origin HEAD' \
  'git merge origin/main; echo done'; do
  pw "$cmd" "$W"
  expect deny "[worker, record] the spec branch refuses: $cmd"
done
gitq -C "$W" tag base-tag origin/main
pw 'git merge base-tag' "$W"
expect deny "[worker, record] a tag at the PR base's commit refuses"
gitq -C "$W" tag -d base-tag

echo "# the merge builds for the PR's own launch, in its own checkout, alone"
rm -f "$REC"
pw 'git merge origin/main' "$W"
expect deny "[worker] with no record the spec branch refuses the merge"
rec "unit_branch=$MYFL" "spec_branch=$OTHER_SB"
pw 'git merge origin/main' "$W"
expect deny "[worker] a record naming another spec PR refuses the merge"
rec "unit_branch=$MYFL" "spec_branch=$SB"
pw 'git merge origin/main' "$W2" "$W"
expect deny "[worker, record] a merge run from the session's worktree into another checkout refuses"
pw 'git merge origin/main' "$W_OTHER"
expect deny "[worker, record] another spec branch's checkout refuses"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower 'git merge origin/main' "$W" "$W"
expect deny "[tower] the record admits nothing at another tier"
pw 'git merge origin/main' "$K"
expect deny "[worker, record] a primary checkout refuses"

echo "# a push adding only merges of main fast-forwards the spec branch"
merged "$W"
for cmd in "${PUSHES[@]}"; do
  pw "$cmd" "$W"
  expect defer "[worker, record] a merge-only push defers: $cmd"
done
gitq -C "$FL" reset --hard "$(git -C "$W" rev-parse HEAD)"
pw "git push origin HEAD:refs/heads/$SB" "$FL"
expect defer "[worker, record] the same merge pushed from the flight branch defers"
pw "git push origin $SB" "$FL"
expect defer "[worker, record] the local spec branch pushed by name from the flight checkout defers"
at_pr_head "$W"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect defer "[worker, record] a push adding nothing defers"
# A second merge of main after main moves again.
merged "$W"
gitq -C "$SEED" switch main
put "$SEED" src.txt v3
gitq -C "$SEED" commit -am 'main moves again'
gitq -C "$SEED" push origin main
gitq -C "$K" fetch origin
gitq -C "$W" merge --no-edit origin/main
if [ "$(git -C "$W" rev-list --count --merges "origin/$SB..HEAD")" = 2 ]; then
  pass "the two-merge fixture holds two merges"
else
  fail "the two-merge fixture did not build two merges"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect defer "[worker, record] two merges of main in a row defer"

echo "# a merge carrying a spec-bundle edit refuses"
for f in requirements.md design.md tasks.md test-spec.md kickoff-brief.md; do
  at_pr_head "$W"
  gitq -C "$W" merge --no-commit --no-ff origin/main
  put "$W" "specs/demo/$f" "demo $f edited inside the merge"
  gitq -C "$W" add -A
  gitq -C "$W" commit --no-edit
  pw "git push origin HEAD:refs/heads/$SB" "$W"
  expect deny "[worker, record] a merge that edits $f refuses"
done
reason_has 'spec-bundle' "[worker, record] the refusal names the spec-bundle edit"
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
put "$W" specs/demo/notes/tasks.md 'a bundle-named file anywhere'
gitq -C "$W" add -A
gitq -C "$W" commit --no-edit
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge adding a bundle-named file refuses"
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
put "$W" specs/other/tasks.md 'other v1'
gitq -C "$W" add -A
gitq -C "$W" commit --no-edit
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge that drops main's change to a bundle file refuses"
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
gitq -C "$W" rm -q specs/demo/tasks.md
gitq -C "$W" commit --no-edit
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge that deletes a bundle file refuses"
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
put "$W" src.txt 'code resolved inside the merge'
gitq -C "$W" add -A
gitq -C "$W" commit --no-edit
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect defer "[worker, record] a merge that changes only non-bundle files defers"

echo "# a direct spec edit, or any commit that is no merge of main, refuses"
merged "$W"
put "$W" specs/demo/tasks.md 'demo tasks.md edited directly'
gitq -C "$W" commit -am 'direct spec edit'
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a direct spec edit on top of the merge refuses"
at_pr_head "$W"
put "$W" specs/demo/tasks.md 'demo tasks.md edited directly'
gitq -C "$W" commit -am 'direct spec edit'
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a direct spec edit alone refuses"
merged "$W"
put "$W" src.txt 'a code commit'
gitq -C "$W" commit -am 'a non-merge commit'
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a non-merge commit that touches no spec file refuses"
at_pr_head "$W"
gitq -C "$W" merge --no-edit origin/planwright/demo/task-2
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge of a branch other than main refuses"
at_pr_head "$W"
gitq -C "$W" merge --no-edit origin/main origin/planwright/demo/task-2
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] an octopus merge refuses"
# main merged into a side line of main's own commits, then merged in.
at_pr_head "$W"
gitq -C "$W" switch -q --detach origin/main
put "$W" side.txt 'a line main never took'
gitq -C "$W" add -A
gitq -C "$W" commit -m 'side line'
SIDE=$(git -C "$W" rev-parse HEAD)
gitq -C "$W" switch -q "$SB"
at_pr_head "$W"
gitq -C "$W" merge --no-edit "$SIDE"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge of a commit main does not hold refuses"

echo "# the push is the launch's own, alone, to that branch alone"
merged "$W"
rm -f "$REC"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker] with no record a merge-only push refuses"
rec "unit_branch=$MYFL" "spec_branch=$OTHER_SB"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker] a record naming another spec PR refuses the push"
rec "unit_branch=$MYFL" "spec_branch=$SB"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "git push origin HEAD:refs/heads/$SB" "$W" "$W"
expect deny "[worker, kickoff-demo] a kickoff scope with no record still refuses the raw push"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg tower "git push origin HEAD:refs/heads/$SB" "$W" "$W"
expect deny "[tower] the record admits no push at another tier"
for cmd in "git push origin HEAD:refs/heads/$SB HEAD:refs/heads/main" "git push origin HEAD:refs/heads/$OTHER_SB" \
  'git push origin HEAD:refs/heads/main' "git fetch origin && git push origin HEAD:refs/heads/$SB" \
  "git commit --allow-empty -m x && git push origin HEAD:refs/heads/$SB" "git push origin HEAD:refs/heads/$SB; echo pushed" \
  "git push origin HEAD~1:refs/heads/$SB" "git push origin origin/main:refs/heads/$SB" "git push origin" 'git push'; do
  pw "$cmd" "$W"
  expect deny "[worker, record] refuses: $cmd"
done
for cmd in "git push --force origin HEAD:refs/heads/$SB" "git push -f origin HEAD:refs/heads/$SB" \
  "git push --force-with-lease origin HEAD:refs/heads/$SB" "git push origin +HEAD:refs/heads/$SB" \
  "git push --delete origin $SB" "git push origin :refs/heads/$SB"; do
  pw "$cmd" "$W"
  expect deny "[worker, record] a forced or deleting push refuses: $cmd"
done

echo "# the push fast-forwards the PR head as the remote holds it"
merged "$W"
gitq -C "$SEED" switch "$SB"
gitq -C "$SEED" pull -q --no-rebase origin "$SB"
gitq -C "$SEED" commit --allow-empty -m 'the kickoff pushed again'
gitq -C "$SEED" push origin "$SB"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a push that no longer fast-forwards the remote PR head refuses"
reason_has 'fast-forward' "[worker, record] the refusal names the fast-forward"
gitq -C "$K" fetch origin
merged "$W"
gitq -C "$W" update-ref "refs/remotes/origin/$SB" HEAD
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect defer "[worker, record] a tracking ref moved locally is refreshed before the check"
put "$W" specs/demo/tasks.md 'edited after a forged tracking ref'
gitq -C "$W" commit -am 'spec edit'
gitq -C "$W" update-ref "refs/remotes/origin/$SB" HEAD
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a forged PR-head tracking ref hides no spec edit"
gitq -C "$K" fetch origin
at_pr_head "$W"
gitq -C "$W" switch -q --detach origin/main
put "$W" specs/other/tasks.md 'smuggled through main'
gitq -C "$W" commit -qam 'forged main'
FORGED=$(git -C "$W" rev-parse HEAD)
gitq -C "$W" update-ref refs/remotes/origin/main HEAD
gitq -C "$W" switch -q "$SB"
gitq -C "$W" merge --no-edit origin/main
if [ "$(git -C "$W" rev-parse HEAD^2)" = "$FORGED" ]; then
  pass "the forged-main fixture merged the forged commit"
else
  fail "the forged-main fixture did not build its merge"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a forged main tracking ref hides no spec edit"
reason_has 'not merges of main' "[worker, record] the forged main refuses as no merge of main"
gitq -C "$K" fetch origin

no_gh_calls
finish
