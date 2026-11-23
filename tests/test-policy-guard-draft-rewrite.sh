#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the draft-branch rewrite
# (human-gates REQ-F1.6) and a worker's deletion of a unit branch
# (REQ-F1.8, REQ-G1.14). A worker mission control launched, whose launch
# record (at the worktree's own path, never one the environment names)
# carries draft_rewrite=allow, may amend, squash, fix up, or rebase commits it
# pushed to its own unit branch, onto the record's PR base or the branch's own
# remote branch, with the range holding only the branch's own commits; every
# other case keeps the unpushed_rewrite rule. The guard decides from local
# state alone: no gh call.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/hermetic-env.sh
. "$REPO_ROOT/tests/lib/hermetic-env.sh"

cp "$REAL_SCRIPTS/worker-session-record.sh" "$REAL_SCRIPTS/fleet-state.sh" "$REAL_SCRIPTS/lock-lib.sh" "$S/"
FLEET="$SANDBOX/fleet"
mkdir -m 700 "$FLEET" "$FLEET/session-records"
PLANWRIGHT_FLEET_STATE_DIR=$FLEET
export PLANWRIGHT_FLEET_STATE_DIR

B=planwright/demo/task-1
PRIM="$SANDBOX/prim"
gitq clone "$ORIGIN" "$PRIM"
gitq -C "$PRIM" remote set-head origin main
WT="$SANDBOX/wt"
gitq -C "$PRIM" worktree add "$WT" "$B"
WT=$(cd "$WT" && pwd -P)
[ "$(git -C "$WT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = "origin/$B" ] \
  || {
    fail "fixture: the worktree's branch does not track origin/$B"
    finish
    exit 1
  }
gitq -C "$WT" commit --allow-empty -m "own pushed 1"
gitq -C "$WT" push origin "$B"
PUSHED_TIP=$(git -C "$WT" rev-parse HEAD)

FIXED="$FLEET/session-records/$(printf '%s' "$WT" | git hash-object --stdin).record"
# record [<line>...] — the worktree's own launch record.
record() {
  {
    printf 'policy=own-branch\nunit_branch=%s\nworktree_root=%s\npr_base=origin/main\n' "$B" "$WT"
    [ "$#" = 0 ] || printf '%s\n' "$@"
  } >"$FIXED"
  chmod 600 "$FIXED"
}
ALLOW=(launcher=mission-control draft_rewrite=allow)
at() { gitq -C "$WT" reset --hard "$1"; } # put the worktree's branch at <commit>
w() { pg worker "$1" "$WT" "$WT"; }       # the worker tier, in the worktree

echo "# under deny, or with no record, a pushed commit stays append-only (REQ-F1.6)"
set_knobs 'unpushed_rewrite: allow'
for rec in none deny absent; do
  case $rec in
    none) rm -f "$FIXED" ;;
    deny) record launcher=mission-control draft_rewrite=deny ;;
    absent) record launcher=mission-control ;;
  esac
  for cmd in 'git commit --amend --no-edit' 'git rebase origin/main' 'git pull --rebase origin main'; do
    w "$cmd"
    expect deny "[worker] record $rec: $cmd over a pushed commit denies"
  done
done
w 'git rebase origin/main'
reason_has 'remote-tracking ref already contains' "[worker] the deny keeps the append-only reason"

echo "# with allow, the own unit branch's pushed commits may be reshaped"
record "${ALLOW[@]}"
for cmd in 'git commit --amend --no-edit' 'git commit --am --no-edit' 'git rebase origin/main' 'git rebase -i origin/main' \
  'git rebase refs/remotes/origin/main' 'git pull --rebase origin main' 'git rebase' "git rebase origin/$B"; do
  w "$cmd"
  expect defer "[worker] allow: $cmd defers"
done
gitq -C "$WT" config "branch.$B.rebase" true
w 'git pull'
expect defer "[worker] allow: a bare git pull under branch rebase=true defers"
gitq -C "$WT" config --unset "branch.$B.rebase"
no_gh_calls

echo "# with allow, every other case keeps its refusal"
w 'git rebase HEAD~1'
expect deny "[worker] allow: a rebase onto a commit that is neither the PR base nor the own remote branch denies"
reason_has 'neither the PR base' "[worker] the upstream refusal names the two admitted upstreams"
w 'git rebase origin/planwright/demo/task-2'
expect deny "[worker] allow: a rebase onto another branch denies"
w 'git rebase --onto origin/main HEAD~1'
expect deny "[worker] allow: a rebase --onto denies"
w 'git rebase --root'
expect deny "[worker] allow: a rebase --root denies"
w 'git pull --rebase origin planwright/demo/task-2'
expect deny "[worker] allow: a rebasing pull of another branch denies"
# A commit another remote ref contains is someone else's history too.
gitq -C "$WT" push origin "HEAD:refs/heads/planwright/flight/copy-0123abcd"
gitq -C "$WT" fetch origin
w 'git commit --amend --no-edit'
expect deny "[worker] allow: a commit another remote ref contains denies"
reason_has 'remote ref other than' "[worker] the other-ref refusal says why"
gitq -C "$WT" push origin --delete planwright/flight/copy-0123abcd
gitq -C "$WT" fetch --prune origin
w 'git commit --amend --no-edit'
expect defer "[worker] allow: once no other remote ref contains it, the amend defers again"
# A mixed range: a never-pushed commit on top of a pushed one.
gitq -C "$WT" commit --allow-empty -m "unpushed"
set_knobs 'unpushed_rewrite: deny'
w 'git rebase origin/main'
expect deny "[worker] allow: a mixed range under unpushed_rewrite deny denies"
reason_has 'mixed range' "[worker] the mixed-range refusal names both knobs"
w 'git commit --amend --no-edit'
expect deny "[worker] allow: an amend of a never-pushed commit under unpushed_rewrite deny denies"
at "$PUSHED_TIP"
w 'git commit --amend --no-edit'
expect defer "[worker] allow: a pushed-only amend under unpushed_rewrite deny defers (draft_rewrite alone governs it)"
set_knobs 'unpushed_rewrite: allow'
gitq -C "$WT" commit --allow-empty -m "unpushed"
w 'git rebase origin/main'
expect defer "[worker] allow: a mixed range under unpushed_rewrite allow defers"
at "$PUSHED_TIP"
gitq -C "$WT" branch --unset-upstream
w 'git commit --amend --no-edit'
expect deny "[worker] allow: no upstream denies"
gitq -C "$WT" branch --set-upstream-to "origin/main"
w 'git commit --amend --no-edit'
expect deny "[worker] allow: an upstream that is not the own remote branch denies"
gitq -C "$WT" branch --set-upstream-to "origin/$B"
url=$(git -C "$WT" remote get-url origin)
gitq -C "$WT" remote set-url origin "$SANDBOX/no-such-remote.git"
w 'git commit --amend --no-edit'
expect deny "[worker] allow: a failed upstream refresh denies"
gitq -C "$WT" remote set-url origin "$url"
set_knobs 'unpushed_rewrite: allow' "protected_branches: $B"
w 'git commit --amend --no-edit'
expect deny "[worker] allow: a protected_branches entry denies"
set_knobs 'unpushed_rewrite: allow'
no_gh_calls

echo "# main, master, and a spec branch, even with an allowing record naming them"
for br in main master planwright/demo/spec; do
  d="$SANDBOX/wt-$(printf '%s' "$br" | tr / -)"
  case $br in
    master) gitq -C "$PRIM" branch master origin/main ;;
  esac
  gitq -C "$PRIM" worktree add --force "$d" "$br"
  d=$(cd "$d" && pwd -P)
  f="$FLEET/session-records/$(printf '%s' "$d" | git hash-object --stdin).record"
  printf 'unit_branch=%s\nworktree_root=%s\npr_base=origin/main\nlauncher=mission-control\ndraft_rewrite=allow\n' "$br" "$d" >"$f"
  chmod 600 "$f"
  pg worker 'git rebase origin/main' "$d" "$d"
  expect deny "[worker] allow: a rebase on $br denies"
  pg worker 'git commit --amend --no-edit' "$d" "$d"
  expect deny "[worker] allow: an amend on $br denies"
done
no_gh_calls

echo "# the record's authority: launcher, branch, worktree, path"
for bad in launcher=tower ''; do
  if [ -n "$bad" ]; then record "$bad" draft_rewrite=allow; else record draft_rewrite=allow; fi
  w 'git commit --amend --no-edit'
  expect deny "[worker] a record naming ${bad:-no launcher} denies the pushed rewrite"
done
record "${ALLOW[@]}"
sed "s|^unit_branch=.*|unit_branch=planwright/demo/task-2|" "$FIXED" >"$SANDBOX/r" && mv "$SANDBOX/r" "$FIXED" && chmod 600 "$FIXED"
w 'git commit --amend --no-edit'
expect deny "[worker] a record naming another unit's branch denies"
record "${ALLOW[@]}"
sed "s|^worktree_root=.*|worktree_root=$SANDBOX/elsewhere|" "$FIXED" >"$SANDBOX/r" && mv "$SANDBOX/r" "$FIXED" && chmod 600 "$FIXED"
w 'git commit --amend --no-edit'
expect deny "[worker] a record naming another worktree denies"
record "${ALLOW[@]}" draft_rewrite=allow
w 'git commit --amend --no-edit'
expect deny "[worker] a record giving draft_rewrite twice denies"
record "${ALLOW[@]}"
chmod 666 "$FIXED"
w 'git commit --amend --no-edit'
expect deny "[worker] a record others can write denies"
chmod 600 "$FIXED"
# A record the environment names is never read: the worktree's own path is.
cp "$FIXED" "$SANDBOX/forged.record"
record launcher=mission-control draft_rewrite=deny
PLANWRIGHT_WORKER_SESSION_RECORD="$SANDBOX/forged.record" w 'git commit --amend --no-edit'
expect deny "[worker] an allowing record the environment names does not stand in for the worktree's"
record "${ALLOW[@]}"
pg tower 'git commit --amend --no-edit' "$WT" "$WT"
expect deny "[tower] the draft-branch rewrite is the worker's alone"
pg worker 'git rebase origin/main' "$UNIT" "$UNIT"
expect deny "[worker] a plain clone (no linked worktree, no launch record) keeps the append-only rule"
no_gh_calls

echo "# a worker never deletes a unit branch on the remote (REQ-F1.8, REQ-G1.14)"
for cmd in "git push origin --delete $B" "git push origin :$B" "git push -d origin $B" "git push --delete origin $B" \
  "git push origin :refs/heads/$B" "git push origin --del $B" "git push origin $B :$B" \
  'git push origin --delete planwright/flight/other-0123abcd' \
  "gh api -X DELETE repos/acme/widgets/git/refs/heads/$B" \
  'gh api --method DELETE repos/acme/widgets/git/refs/heads/planwright/demo/task-2' \
  "gh api graphql -f query='mutation{deleteRef(input:{refId:\"R\"}){clientMutationId}}'"; do
  w "$cmd"
  expect deny "[worker] $cmd denies"
done
w "git push origin --delete $B"
reason_has 'never deletes a unit branch' "[worker] the deletion refusal says why"
w "git push origin $B"
expect defer "[worker] a plain push of the own unit branch still defers"
w "git push -u origin $B"
expect defer "[worker] a plain push with -u still defers"
no_gh_calls

finish
