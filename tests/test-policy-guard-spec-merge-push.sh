#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: a worker whose session record
# names a spec's protected sign-off branch (planwright/<spec>/spec) landing a
# forward-merge of main there, as docs/permission-matcher-model.md states it:
# a lone base merge in the worktree holding the branch, and a lone push of
# clean merges of main, judged against the remote's own refs with no local
# state able to steer git's reads. Anything else on that branch refuses.
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
REAL_GIT=$(command -v git)

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
reason_has 'sign-off branch' "[worker, record] the last merge refusal (a second command on the line) names the sign-off route"
gitq -C "$W" tag base-tag origin/main
pw 'git merge base-tag' "$W"
expect deny "[worker, record] a tag at the PR base's commit refuses"
gitq -C "$W" tag -d base-tag
pw 'git pull origin main' "$W"
expect deny "[worker, record] a pull on the sign-off branch refuses"
reason_has 'sign-off branch' "[worker, record] the pull refusal names the sign-off route"

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
  push_ok "[worker, record] a merge-only push defers: $cmd"
done
gitq -C "$FL" reset --hard "$(git -C "$W" rev-parse HEAD)"
pw "git push origin HEAD:refs/heads/$SB" "$FL"
push_ok "[worker, record] the same merge pushed from the flight branch defers"
pw "git push origin $SB" "$FL"
push_ok "[worker, record] the local spec branch pushed by name from the flight checkout defers"
at_pr_head "$W"
pw "git push origin HEAD:refs/heads/$SB" "$W"
push_ok "[worker, record] a push adding nothing defers"
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
push_ok "[worker, record] two merges of main in a row defer"

echo "# a merge whose tree is not the clean merge of its parents refuses"
for f in requirements.md design.md tasks.md test-spec.md kickoff-brief.md; do
  at_pr_head "$W"
  gitq -C "$W" merge --no-commit --no-ff origin/main
  put "$W" "specs/demo/$f" "demo $f edited inside the merge"
  gitq -C "$W" add -A
  gitq -C "$W" commit --no-edit
  pw "git push origin HEAD:refs/heads/$SB" "$W"
  expect deny "[worker, record] a merge that edits $f refuses"
done
reason_has 'clean merge' "[worker, record] the refusal names the edit inside the merge"
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
expect deny "[worker, record] a merge that edits a file outside the bundle refuses too"
reason_has 'clean merge' "[worker, record] the refusal names the clean merge"
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
gitq -C "$W" update-index --chmod=+x specs/demo/tasks.md
gitq -C "$W" commit --no-edit
if [ "$(git -C "$W" ls-tree HEAD specs/demo/tasks.md | cut -c1-6)" = 100755 ]; then
  pass "the mode-change fixture made tasks.md executable"
else
  fail "the mode-change fixture did not change the mode"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge that changes only a bundle file's mode refuses"

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
reason_has 'protected branch' "[worker, record] the last push refusal (no refspec at all) keeps the protected-set refusal"
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
push_ok "[worker, record] a tracking ref moved locally is refreshed before the check"
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

echo "# the base is the remote's own default branch, never a local origin/HEAD"
gitq -C "$FL" reset --hard origin/main
put "$FL" specs/other/tasks.md 'smuggled through a repointed origin/HEAD'
gitq -C "$FL" commit -qam 'a spec edit on a flight branch'
gitq -C "$FL" push -q origin "$MYFL"
gitq -C "$K" remote set-head origin "$MYFL"
at_pr_head "$W"
gitq -C "$W" merge --no-edit "origin/$MYFL"
if [ "$(git -C "$W" rev-parse HEAD^2)" = "$(git -C "$FL" rev-parse HEAD)" ]; then
  pass "the repointed-HEAD fixture merged the flight branch"
else
  fail "the repointed-HEAD fixture did not build its merge"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge of what a repointed origin/HEAD names refuses"
reason_has 'not merges of main' "[worker, record] the repointed origin/HEAD refuses as no merge of main"
gitq -C "$K" remote set-head origin main

echo "# the refs the guard reads are the ones the push meets"
FAKE="$SANDBOX/fake.git"
gitq clone --bare "$ORIGIN" "$FAKE"
gitq -C "$W" switch -q --detach origin/main
put "$W" specs/other/tasks.md 'smuggled through a second remote'
gitq -C "$W" commit -qam 'forged main on another remote'
gitq -C "$W" push -q "$FAKE" HEAD:refs/heads/main
gitq -C "$W" switch -q "$SB"
diverged() { # <label>: merge the fake main and push, expecting the refusal
  gitq -C "$K" fetch origin
  at_pr_head "$W"
  gitq -C "$W" merge --no-edit origin/main
  if [ "$(git -C "$W" rev-parse HEAD^2)" = "$(git --git-dir="$FAKE" rev-parse main)" ]; then
    pass "the $1 fixture merged the other remote's main"
  else
    fail "the $1 fixture did not build its merge"
  fi
  pw "git push origin HEAD:refs/heads/$SB" "$W"
  expect deny "[worker, record] a fetch and push that reach different repositories refuse ($1)"
}
gitq -C "$K" config remote.origin.url "$FAKE"
gitq -C "$K" config remote.origin.pushurl "$ORIGIN"
diverged pushurl
reason_has 'pushurl' "[worker, record] the refusal names the push URL"
gitq -C "$K" config --unset remote.origin.pushurl
gitq -C "$K" config remote.origin.url "$ORIGIN"
gitq -C "$K" config "url.$FAKE.insteadOf" "$ORIGIN"
gitq -C "$K" config "url.$ORIGIN.pushInsteadOf" "$ORIGIN"
if [ "$(git -C "$K" remote get-url origin)" = "$FAKE" ] && [ "$(git -C "$K" remote get-url --push origin)" = "$ORIGIN" ]; then
  pass "the rewrite fixture sends fetches and pushes to different repositories"
else
  fail "the rewrite fixture did not split the URLs"
fi
diverged insteadOf
reason_has 'insteadOf' "[worker, record] the refusal names the URL rewrite"
gitq -C "$K" config --remove-section "url.$FAKE"
gitq -C "$K" config --remove-section "url.$ORIGIN"
gitq -C "$K" fetch origin
merged "$W"
gitq -C "$K" config remote.origin.uploadpack git-upload-pack
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] an upload-pack override refuses"
gitq -C "$K" config --unset remote.origin.uploadpack
gitq -C "$K" remote add mirror "$ORIGIN"
gitq -C "$K" fetch mirror
pw "git push mirror HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a push to a remote other than the branch's own refuses"
gitq -C "$K" remote remove mirror
for kv in remote.origin.receivepack=git-receive-pack core.sshCommand=ssh core.gitProxy=nc \
  remote.origin.vcs=x remote.origin.proxy=http://proxy.invalid; do
  gitq -C "$K" config "${kv%%=*}" "${kv#*=}"
  pw "git push origin HEAD:refs/heads/$SB" "$W"
  expect deny "[worker, record] a transport override refuses: ${kv%%=*}"
  reason_has "$(printf '%s' "${kv%%=*}" | tr '[:upper:]' '[:lower:]')" "[worker, record] the refusal names ${kv%%=*}"
  gitq -C "$K" config --unset "${kv%%=*}"
done
gitq -C "$K" config --add remote.origin.url "$ORIGIN"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a remote with two URLs refuses"
gitq -C "$K" config --unset-all remote.origin.url
gitq -C "$K" config remote.origin.url "ext::git-remote-ext-is-never-run %S"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a remote-helper URL refuses"
reason_has 'remote helper' "[worker, record] the refusal names the remote helper"
gitq -C "$K" config remote.origin.url "$SANDBOX/missing.git"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] an unreachable remote refuses"
reason_has 'reading the pull request head' "[worker, record] the refusal names the failed remote read"
gitq -C "$K" config remote.origin.url "$ORIGIN"
pw "git push origin HEAD:refs/heads/$SB" "$W"
push_ok "[worker, record] with the remote restored the merge-only push defers again"

echo "# local state that changes what git reads of history refuses"
merged "$W"
CLEAN=$(git -C "$W" rev-parse HEAD)
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
put "$W" specs/demo/tasks.md 'edited inside a merge a replace ref hides'
gitq -C "$W" add -A
gitq -C "$W" commit --no-edit
EVIL=$(git -C "$W" rev-parse HEAD)
gitq -C "$W" replace "$EVIL" "$CLEAN"
if [ "$(git -C "$W" rev-parse 'HEAD^{tree}')" = "$(git -C "$W" rev-parse "$CLEAN^{tree}")" ]; then
  pass "the replace fixture makes git read the edited merge as the clean one"
else
  fail "the replace fixture did not take effect"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a replace ref hiding an edited merge refuses"
reason_has 'replace refs' "[worker, record] the refusal names the replace refs"
gitq -C "$W" replace -d "$EVIL"
# A clean-merge tree committed on a direct spec edit, grafted to read as a
# merge of the PR head and main.
merged "$W"
CLEAN_TREE=$(git -C "$W" rev-parse 'HEAD^{tree}')
at_pr_head "$W"
put "$W" specs/demo/tasks.md 'a direct spec edit a graft hides'
gitq -C "$W" commit -qam 'a direct spec edit'
SIDE_EDIT=$(git -C "$W" rev-parse HEAD)
HIDDEN=$(git -c user.name=t -c user.email=t@example.invalid -C "$W" commit-tree "$CLEAN_TREE" -p "$SIDE_EDIT" -p origin/main -m 'a merge over a hidden edit')
[ -n "$HIDDEN" ] || fail "the grafts fixture could not build its merge"
gitq -C "$W" reset --hard "$HIDDEN"
GRAFTS=$(git -C "$W" rev-parse --path-format=absolute --git-path info/grafts)
mkdir -p "$(dirname "$GRAFTS")"
printf '%s %s %s\n' "$HIDDEN" "$(git -C "$W" rev-parse "origin/$SB")" "$(git -C "$W" rev-parse origin/main)" >"$GRAFTS"
if [ "$(git -C "$W" rev-parse HEAD)" = "$HIDDEN" ] && [ "$(git -C "$W" rev-list --count --first-parent "origin/$SB..HEAD")" = 1 ]; then
  pass "the grafts fixture hides the direct edit from history reads"
else
  fail "the grafts fixture did not take effect"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a graft hiding a direct spec edit refuses"
reason_has 'grafts' "[worker, record] the refusal names the grafts file"
rm -f "$GRAFTS"
# A link or special file reads as empty to a size test while git reads
# through it; each refuses even under a clean merge.
merged "$W"
INFO_ATTRS=$(git -C "$W" rev-parse --path-format=absolute --git-path info/attributes)
mkdir -p "$(dirname "$INFO_ATTRS")"
if [ -r /proc/self/cmdline ]; then
  ln -s /proc/self/cmdline "$INFO_ATTRS"
  pw "git push origin HEAD:refs/heads/$SB" "$W"
  expect deny "[worker, record] info/attributes linked to a procfs file refuses"
  reason_has 'info/attributes' "[worker, record] the refusal names the linked attributes file"
  rm -f "$INFO_ATTRS"
else
  pass "no procfs here: the procfs-link case does not apply"
fi
mkfifo "$INFO_ATTRS"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] info/attributes as a FIFO refuses"
reason_has 'info/attributes' "[worker, record] the refusal names the FIFO before git reads it"
rm -f "$INFO_ATTRS"
for f in "$INFO_ATTRS" "$GRAFTS"; do
  ln -s "$SANDBOX/nowhere" "$f"
  pw "git push origin HEAD:refs/heads/$SB" "$W"
  expect deny "[worker, record] a dangling link at ${f##*/} refuses"
  rm -f "$f"
done
: >"$INFO_ATTRS"
pw "git push origin HEAD:refs/heads/$SB" "$W"
push_ok "[worker, record] an empty regular info/attributes still defers"
rm -f "$INFO_ATTRS"
INFO_DIR=$(dirname "$INFO_ATTRS")
mv "$INFO_DIR" "$INFO_DIR.real"
ln -s "$INFO_DIR.real" "$INFO_DIR"
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a linked info directory refuses"
rm -f "$INFO_DIR"
mv "$INFO_DIR.real" "$INFO_DIR"
K3="$SANDBOX/kick-shallow"
gitq clone --depth 1 --branch "$SB" "file://$ORIGIN" "$K3"
gitq -C "$K3" remote set-head origin main
pw "git push origin HEAD:refs/heads/$SB" "$K3"
expect deny "[worker, record] a push from a shallow clone refuses"
reason_has 'shallow' "[worker, record] the refusal names the shallow history"
OLDGIT="$SANDBOX/oldgit"
mkdir -p "$OLDGIT"
cat >"$OLDGIT/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  case \$a in --attr-source=*) printf '%s\n' "unknown option: \$a" >&2 && exit 129 ;; esac
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$OLDGIT/git"
merged "$W"
PG_PATH="$OLDGIT:$PATH" pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a git without --attr-source refuses the push"
reason_has '2\.40' "[worker, record] the refusal names the git version it needs"

echo "# the merge line starts on the PR head itself"
# Once main holds the PR head, a merge onto an older commit of the branch
# still fast-forwards it, reaching the head only through main.
OLD_MAIN=$(git --git-dir="$ORIGIN" rev-parse main)
gitq -C "$SEED" switch main
gitq -C "$SEED" fetch origin
gitq -C "$SEED" reset --hard origin/main
gitq -C "$SEED" merge --no-edit "origin/$SB"
gitq -C "$SEED" push -q origin main
gitq -C "$K" fetch origin
PR_HEAD=$(git -C "$W" rev-parse "origin/$SB")
gitq -C "$W" reset --hard "$PR_HEAD^"
gitq -C "$W" merge --no-edit --no-ff origin/main
if [ "$(git -C "$W" rev-parse HEAD^1)" = "$(git -C "$W" rev-parse "$PR_HEAD^")" ] && git -C "$W" merge-base --is-ancestor "$PR_HEAD" HEAD; then
  pass "the rewind fixture merged main onto the head's parent"
else
  fail "the rewind fixture did not build its merge"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge onto an older commit than the PR head refuses"
reason_has 'oldest merge' "[worker, record] the refusal names the merge's starting point"
gitq -C "$SEED" push -q --force origin "$OLD_MAIN:refs/heads/main"
gitq -C "$SEED" reset --hard "$OLD_MAIN"
gitq -C "$K" fetch origin
if [ "$(git -C "$K" rev-parse origin/main)" = "$OLD_MAIN" ]; then
  pass "the rewind fixture restored main"
else
  fail "the rewind fixture did not restore main"
fi

echo "# merge drivers and attributes never stand in for a hand resolution"
# The PR head and main now both change src.txt, so their merge conflicts.
gitq -C "$SEED" switch "$SB"
gitq -C "$SEED" pull -q --no-rebase origin "$SB"
put "$SEED" src.txt 'spec side'
gitq -C "$SEED" commit -qam 'the spec branch edits a file main also edits'
gitq -C "$SEED" push -q origin "$SB"
gitq -C "$K" fetch origin
resolved() { # <content>: the conflicting merge, resolved by hand to <content>
  at_pr_head "$W"
  gitq -C "$W" merge --no-edit origin/main
  put "$W" src.txt "$1"
  gitq -C "$W" add src.txt
  gitq -C "$W" commit --no-edit
  if [ "$(git -C "$W" rev-list --count --merges "origin/$SB..HEAD")" = 1 ]; then
    pass "the hand-resolved merge fixture built its merge ($1)"
  else
    fail "the hand-resolved merge fixture did not build its merge ($1)"
  fi
}
resolved 'resolved by hand'
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a hand-resolved conflict refuses"
ATTRS=$(git -C "$W" rev-parse --path-format=absolute --git-path info/attributes)
mkdir -p "$(dirname "$ATTRS")"
gitq -C "$K" config merge.evil.driver 'printf EVIL >%A'
printf '%s\n' 'src.txt merge=evil' >"$ATTRS"
resolved EVIL
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge driver standing in for a hand resolution refuses"
reason_has 'info/attributes' "[worker, record] the driver attack refuses on the attributes file first"
rm -f "$ATTRS"
put "$W" .gitattributes 'src.txt merge=evil'
resolved EVIL
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a configured merge driver alone refuses"
reason_has 'merge driver' "[worker, record] the refusal names the merge driver"
rm -f "$W/.gitattributes"
gitq -C "$K" config --unset merge.evil.driver
printf '%s\n' 'src.txt merge=ours' >"$ATTRS"
resolved 'spec side'
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge=ours attribute in info/attributes refuses"
reason_has 'info/attributes' "[worker, record] the refusal names the attributes file"
rm -f "$ATTRS"
put "$W" .gitattributes 'src.txt merge=ours'
resolved 'spec side'
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] a merge=ours attribute in the worktree refuses"
reason_has 'clean merge' "[worker, record] the worktree attribute is ignored, so the merge is no clean merge"
rm -f "$W/.gitattributes"

echo "# the knob and a kickoff scope beside the record"
at_pr_head "$W"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: deny' 'unpushed_rewrite: allow'
pw 'git merge origin/main' "$W"
expect deny "[worker, record] worker_base_merge deny refuses the sign-off merge"
reason_has 'worker_base_merge is deny' "[worker, record] the refusal names the knob"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
PLANWRIGHT_WORKER_SCOPE=kickoff-demo PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker 'git merge origin/main' "$W" "$W"
expect defer "[worker, kickoff-demo, record] the bare base merge defers"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo PLANWRIGHT_WORKER_SESSION_RECORD=$REC pg worker 'git merge --no-ff origin/main' "$W" "$W"
expect deny "[worker, kickoff-demo, record] the record's narrower merge governs: --no-ff refuses"

echo "# an edited merge whose tree object is missing refuses (last: it damages the repository)"
at_pr_head "$W"
gitq -C "$W" merge --no-commit --no-ff origin/main
put "$W" specs/demo/tasks.md 'edited inside a merge whose tree goes missing'
gitq -C "$W" add -A
gitq -C "$W" commit --no-edit
TREE=$(git -C "$W" rev-parse 'HEAD^{tree}')
LOOSE="$K/.git/objects/${TREE:0:2}/${TREE:2}"
if [ -f "$LOOSE" ]; then
  rm -f "$LOOSE"
  pass "the missing-tree fixture removed the merge's tree"
else
  fail "the missing-tree fixture found no loose tree to remove"
fi
pw "git push origin HEAD:refs/heads/$SB" "$W"
expect deny "[worker, record] an edited merge whose tree object is missing refuses"

no_gh_calls
finish
