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
for cmd in "git push origin $B 2>&1 | tail -3" "for i in 1 2; do git push origin $B; done" \
  "git push origin $B & wait" "git status | cat; git push origin $B"; do
  pg worker "$cmd"
  expect defer "[worker] $cmd (no state change after the act) defers"
done

no_gh_calls
finish
