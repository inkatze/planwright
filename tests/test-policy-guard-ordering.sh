#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: git state a command changes
# where the guard reads it too late or not at all. A loop body, a background
# list, a pipeline or a coprocess runs a change written after a reserved act
# before that act; a non-git command (a redirect, cp, tee, sed -i, an echo into
# .git/HEAD) writes git's configuration or HEAD; and a tab or newline in the
# directory splits a queued act's record.
#
# The end-to-end fixtures run each bypass for real against a throwaway origin
# in the sandbox and check that its main moved, so a case that would not reach
# main fails as a broken fixture rather than passing for nothing.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

set_knobs 'protected_branches:' 'unpushed_rewrite: allow' 'worker_base_merge: allow'
TAB=$(printf '\t')
B=planwright/demo/task-1
E2E_N=0

# e2e <label> <prepare> <command> — run <command> with bash in a fresh clone
# of a fresh origin (on $B, one unpushed commit, after <prepare>), and fail
# the fixture unless the origin's main moved.
e2e() {
  local label=$1 prep=$2 cmd=$3 o c before after
  E2E_N=$((E2E_N + 1))
  o="$SANDBOX/e2e-$E2E_N.git"
  c="$SANDBOX/e2e-$E2E_N"
  gitq clone --bare "$ORIGIN" "$o"
  gitq clone "$o" "$c"
  gitq -C "$c" switch "$B"
  gitq -C "$c" commit --allow-empty -m unpushed
  before=$(git -C "$o" rev-parse main)
  (cd "$c" && HOME="$SANDBOX/e2e-home-$E2E_N" && export HOME && mkdir -p "$HOME" && unset GIT_CONFIG_GLOBAL \
    && /bin/bash -c "$prep" && /bin/bash -c "$cmd; wait") >/dev/null 2>&1
  after=$(git -C "$o" rev-parse main)
  [ "$before" != "$after" ] || fail "fixture: $label does not move main when run, so its case would be vacuous"
}

# --- A: a change written after the act can run before it --------------------

echo "# ordering: loops, background lists, pipelines and coprocesses"
CFGPUSH="git config remote.origin.push refs/heads/$B:refs/heads/main"
e2e 'a push in a for loop beside a later push-refspec change' : \
  "for i in 1 2; do git push origin $B; $CFGPUSH; done"
e2e 'a backgrounded push beside a later branch rename' : \
  "sleep 1 && git push origin HEAD & git branch -M main"
for tier in worker tower; do
  for cmd in "for i in 1 2; do git push origin $B; $CFGPUSH; done" \
    "while true; do git push origin $B; $CFGPUSH; done" \
    "until false; do git push origin $B; $CFGPUSH; done" \
    "select x in a b; do git push origin $B; $CFGPUSH; done" \
    'sleep 1 && git push origin HEAD & git branch -M main' \
    'git push origin HEAD & git switch main' \
    "git push origin $B | $CFGPUSH" "git push origin $B |& $CFGPUSH" \
    "coproc git push origin $B; $CFGPUSH" \
    "for i in 1 2; do git push origin HEAD; git switch main; done" \
    "for i in 1 2; do git push origin $B; export GIT_DIR=/tmp/x; done" \
    "for i in 1 2; do git commit --amend --no-edit; git push origin $B; done"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies"
  done
done
pg worker "for i in 1 2; do git push origin $B; $CFGPUSH; done"
reason_has 'order' "the ordering deny says why"
for cmd in "for i in 1 2; do git push origin HEAD; cd /tmp; done" \
  "while true; do git commit --amend --no-edit; pushd /tmp; done" \
  "for i in 1 2; do git commit --amend --no-edit; git fetch origin; done" \
  "until false; do git merge origin/main; git fetch origin main:refs/heads/x; done"; do
  pg worker "$cmd"
  expect deny "[worker] $cmd (a directory change, or a fetch after a rewrite or merge, in a loop) denies"
  reason_has 'order' "[worker] $cmd denies for its ordering"
done
for cmd in "git push origin $B 2>&1 | tail -3" "for i in 1 2; do git push origin $B; done" \
  "git push origin $B & wait" "git status | cat; git push origin $B" \
  "git merge origin/main && git push origin $B:$B 2>&1 | tail -3" \
  "git merge --ff-only origin/main && git push origin $B:$B | cat" \
  "git push origin $B:$B && git push origin HEAD:$B | cat" "git push origin $B; git config user.name x"; do
  pg worker "$cmd"
  expect defer "[worker] $cmd (no state change after the act that the act reads) defers"
done

# --- B: non-git writes to git configuration or HEAD --------------------------

echo "# writes to git state by other commands"
PUSHCFG='[remote "origin"]\n\tpush = refs/heads/planwright/demo/task-1:refs/heads/main\n'
e2e 'an append to .git/config before a push' : \
  "printf '$PUSHCFG' >>.git/config && git push origin $B"
e2e 'a copy over .git/config before a push' "cp .git/config cfg && printf '$PUSHCFG' >>cfg" \
  "cp cfg .git/config && git push origin $B"
e2e 'a copy to ~/.gitconfig before a push' "printf '$PUSHCFG' >gcfg" \
  "cp gcfg ~/.gitconfig && git push origin $B"
e2e 'an echo into .git/HEAD before a push' 'git branch -f main HEAD' \
  "echo 'ref: refs/heads/main' > .git/HEAD && git push origin HEAD"
for tier in worker tower; do
  for cmd in "printf '$PUSHCFG' >> .git/config && git push origin $B" \
    "printf '$PUSHCFG' | tee -a .git/config && git push origin $B" \
    "cp cfg .git/config && git push origin $B" "cp gcfg ~/.gitconfig && git push origin $B" \
    "cp gcfg \$HOME/.gitconfig; git push origin $B" "cp gcfg ~/.config/git/config; git push origin $B" \
    "sed -i s/a/b/ .git/config; git push origin $B" "mv cfg ./.git/config; git push origin $B" \
    "echo 'ref: refs/heads/main' > .git/HEAD && git push origin HEAD" \
    "cd .git && printf x >> config && cd .. && git push origin $B" \
    "printf x > \"$UNIT/.git/config\"; git push origin $B" \
    "git push origin $B & printf '$PUSHCFG' >> .git/config"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies"
  done
done
for cmd in "printf x >> \".git\"/config && git push origin $B" "printf x >> .gi''t/config && git push origin $B" \
  "printf x >> .gi\\t/config && git push origin $B" "printf x >> .GIT/config && git push origin $B" \
  "cp cfg .GIT/config; git push origin $B" "cp gcfg ~/.GITCONFIG; git push origin $B" \
  "xxd -r -p cfg.hex .git/config && git push origin $B" "cp cfg .gi?/config; git push origin $B" \
  "cp cfg .[g]it/config; git push origin $B" "d=.git/config; cp cfg \"\$d\"; git push origin $B" \
  "printf x > \"\$f\"; git push origin $B" "cp gcfg /etc/gitconfig; git push origin $B" \
  "cp gcfg ~/.gitconfig.local; git push origin $B"; do
  pg worker "$cmd"
  expect deny "[worker] $cmd (a quoted, folded, globbed or expanded git state path) denies"
done
for cmd in "cat .git/HEAD && git push origin $B" "printf x > notes.txt && git push origin $B" \
  "printf x >> .git/config" "grep x .git/config && git push origin $B" \
  "printf x >> .gitignore && git push origin $B" "printf x > .github/ci.yml && git push origin $B" \
  "printf x >> docs/gitconfig.md && git push origin $B" "echo \$HOME; git push origin $B" \
  "git push origin $B; cp cfg .git/config"; do
  pg worker "$cmd"
  expect defer "[worker] $cmd (a read, a write outside git's state, no act, or a change after the act in plain sequence) defers"
done

# --- D: a tab or newline in the directory -----------------------------------

echo "# a tab or newline in an act's directory"
# The record is tab-separated; a directory named <real clone><TAB>... would
# be read as that real clone, with the rest shifting the record's fields.
TABD="$UNIT${TAB}x"
clone_on "$TABD" "$B" 0
NLD="$UNIT
x"
clone_on "$NLD" "$B" 0
for d in "$TABD" "$NLD"; do
  for cmd in 'git commit --amend --no-edit' 'git rebase -i HEAD~1' 'git merge origin/main' \
    'git merge --ff-only origin/main' 'git pull' 'git pull origin main' 'git push origin HEAD' \
    "git send-pack $ORIGIN HEAD:refs/heads/feature-y"; do
    for proj in "$d" "$UNIT"; do
      pg worker "$cmd" "$d" "$proj"
      expect deny "[worker] $cmd in a directory carrying a tab or newline denies (project $([ "$proj" = "$UNIT" ] && printf 'the clone it names' || printf 'that directory'))"
      reason_has 'tab or newline' "[worker] $cmd denies as a split record"
    done
  done
done
for cmd in "git rebase 'HEAD~1${TAB}1'" "git merge 'origin/main${TAB}x'" \
  "git pull origin 'main${TAB}x'" "git commit --fixup='HEAD${TAB}x'" "git rebase 'HEAD~1
x'"; do
  pg worker "$cmd"
  expect deny "[worker] $cmd (a tab or newline in an argument the record carries) denies"
  reason_has 'tab or newline' "[worker] $cmd denies as a split record"
done
pg worker "git commit --amend --no-edit -m 'a${TAB}b'"
expect defer "[worker] a tab in a commit message, which no record carries, still defers"

# --- F1: a loop body that shares its loop's segment --------------------------

echo "# loop bodies with no list or no separator"
# `for x do ...` (no in list) and zsh's `repeat <n> <command>` carry their
# body in the loop's own segment, so it must be read as a command there.
e2e 'a for with no in list, over set positional parameters' : \
  'set -- 1; for x do git push origin HEAD:refs/heads/main; done'
for tier in worker tower; do
  for cmd in 'for x do git push origin main; done' 'set -- 1; for x do git push origin HEAD:refs/heads/main; done' \
    'for x do git push --force origin feature; done' 'for x do gh pr merge 5; done' \
    'select x do git push origin main; done' 'for x do for y do git push origin main; done; done' \
    'time for x do git push origin main; done' '! for x do git push origin main; done' \
    'repeat 2 git push origin main' 'repeat 2 do git push origin main; done' \
    'for x in a b; do for y do git push origin main; done; done'; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies"
  done
done
for cmd in 'for x do git status; done' 'for x in a b; do echo hi; done' 'for x do echo do; done' \
  "for x do git push origin $B:$B; done" 'repeat 2 echo hi'; do
  pg worker "$cmd"
  expect defer "[worker] $cmd (no reserved act, or an unprotected push) defers"
done

no_gh_calls
finish
