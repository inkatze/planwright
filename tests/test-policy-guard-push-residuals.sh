#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: pushes whose real destination
# git reads from somewhere other than the command line (a tag sharing the
# current branch's name, a legacy remotes or branches file, a symbolic ref),
# the plumbing and contrib commands that push (git send-pack, git subtree
# push), and the gh api writes that reach a branch another way: a contents
# write naming heads/<branch>, a rename that takes a unit or spec-family
# branch off the remote, and a change to branch protection or a ruleset.
#
# Each fixture is first checked against real git, a dry run into the sandbox
# origin, so a case whose push would not reach main fails as a broken fixture
# rather than passing for nothing.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

set_knobs 'protected_branches:' 'unpushed_rewrite: allow' 'worker_base_merge: allow'
TAB=$(printf '\t')

# reaches_main <dir> <git push args...> — 0 when a dry run of the push from
# <dir> would update the sandbox origin's main.
reaches_main() {
  local d=$1 out
  shift
  out=$(git -C "$d" push --dry-run --porcelain "$@" 2>&1) || return 1
  case $out in *':refs/heads/main'"$TAB"*) return 0 ;; esac
  return 1
}

fixture() { # <label> <dir> <git push args...>
  local label=$1
  shift
  reaches_main "$@" || fail "fixture: $label does not reach main in real git, so its case would be vacuous"
}

# --- a tag named like the current branch ------------------------------------

echo "# a tag sharing the current branch's name"
TAGD="$SANDBOX/tagmain"
clone_on "$TAGD" main 1
gitq -C "$TAGD" tag main
fixture 'a bare push on main with a tag main' "$TAGD"
fixture 'a push of HEAD on main with a tag main' "$TAGD" origin HEAD
for tier in worker tower; do
  for cmd in 'git push' 'git push origin' 'git push origin HEAD' 'git push origin @'; do
    pg "$tier" "$cmd" "$TAGD"
    expect deny "[$tier] $cmd on main, with a tag named main, denies"
    reason_has 'shares its name' "[$tier] $cmd names the ambiguous branch"
  done
done
TAGU="$SANDBOX/tagunit"
clone_on "$TAGU" planwright/demo/task-1 1
gitq -C "$TAGU" tag planwright/demo/task-1
pg worker 'git push' "$TAGU"
expect deny "[worker] a bare push whose branch shares its name with a tag denies (the branch git reads is ambiguous to the guard)"
reason_has 'shares its name' "the ambiguous-branch deny says why"
pg worker 'git push origin planwright/demo/task-1:planwright/demo/task-1' "$TAGU"
expect defer "[worker] a push naming its destination in full still defers beside a same-named tag"

# --- legacy remotes and branches files --------------------------------------

echo "# legacy remotes/ and branches/ files"
LEG="$SANDBOX/legacy"
clone_on "$LEG" planwright/demo/task-1 1
mkdir -p "$LEG/.git/remotes" "$LEG/.git/branches"
printf 'URL: %s\nPush: refs/heads/planwright/demo/task-1:refs/heads/main\n' "$ORIGIN" >"$LEG/.git/remotes/legacy"
printf '%s#main\n' "$ORIGIN" >"$LEG/.git/branches/leg2"
fixture 'a bare push to a remotes-file remote' "$LEG" legacy
fixture 'a named push to a remotes-file remote' "$LEG" legacy planwright/demo/task-1
fixture 'a bare push to a branches-file remote' "$LEG" leg2
for tier in worker tower; do
  for cmd in 'git push legacy' 'git push legacy planwright/demo/task-1' 'git push leg2' \
    'git push -u leg2 HEAD' 'git push leg2 planwright/demo/task-1:planwright/demo/task-1'; do
    pg "$tier" "$cmd" "$LEG"
    expect deny "[$tier] $cmd, through a legacy remote file, denies"
  done
done
reason_has 'legacy' "the legacy-remote deny names the file kind"
gitq -C "$LEG" config branch.planwright/demo/task-1.remote leg2
pg worker 'git push' "$LEG"
expect deny "[worker] a bare push whose branch.<b>.remote names a branches-file remote denies"
gitq -C "$LEG" config --unset branch.planwright/demo/task-1.remote
pg worker 'git push origin planwright/demo/task-1' "$LEG"
expect defer "[worker] a push to a config remote beside legacy files for other names still defers"
printf 'URL: %s\nPush: refs/heads/planwright/demo/task-1:refs/heads/main\n' "$ORIGIN" >"$LEG/.git/remotes/origin"
pg worker 'git push origin planwright/demo/task-1' "$LEG"
expect deny "[worker] a legacy remotes file named like a configured remote denies, since git may read it"
rm -f "$LEG/.git/remotes/origin"
LEGWT="$SANDBOX/legacy-linked"
gitq -C "$LEG" worktree add -b planwright/demo/task-8 "$LEGWT" HEAD
pg worker 'git push leg2' "$LEGWT"
expect deny "[worker] a linked worktree reads its repository's legacy branches file too"

# --- a local branch that is a symbolic ref ----------------------------------

echo "# symbolic local branches"
SYM="$SANDBOX/symref"
clone_on "$SYM" planwright/demo/task-1 1
gitq -C "$SYM" symbolic-ref refs/heads/x refs/heads/main
gitq -C "$SYM" symbolic-ref refs/heads/y refs/heads/x
gitq -C "$SYM" symbolic-ref refs/heads/z refs/heads/planwright/demo/task-1
fixture 'a push of a branch symref to main' "$SYM" origin x
fixture 'a push of a chained symref to main' "$SYM" origin y
for tier in worker tower; do
  for cmd in 'git push origin x' 'git push origin heads/x' 'git push origin refs/heads/x' 'git push origin y' \
    'git push -u origin planwright/demo/task-1 x'; do
    pg "$tier" "$cmd" "$SYM"
    expect deny "[$tier] $cmd, through a symbolic branch pointing at main, denies"
    reason_has 'protected branch' "[$tier] $cmd denies as a push to the protected branch it resolves to"
  done
done
gitq -C "$SYM" tag t1
gitq -C "$SYM" symbolic-ref refs/heads/w refs/tags/t1
for cmd in 'git push origin z' 'git push origin x:feature-x' 'git push origin w'; do
  pg worker "$cmd" "$SYM"
  expect defer "[worker] $cmd (a symref to an unprotected branch, or a named destination) defers"
done
# A symbolic ref outside refs/ resolves as well: a top-level one, and
# main-worktree/HEAD, which names the branch the primary checkout holds.
gitq -C "$SYM" symbolic-ref FOO refs/heads/main
fixture 'a push of a top-level symref to main' "$SYM" origin FOO
PRIM="$SANDBOX/primary-on-main"
clone_on "$PRIM" main 1
LINKED="$SANDBOX/primary-linked"
gitq -C "$PRIM" worktree add -b planwright/demo/task-9 "$LINKED" HEAD
fixture 'a push of main-worktree/HEAD from a linked worktree' "$LINKED" origin main-worktree/HEAD
for tier in worker tower; do
  pg "$tier" 'git push origin FOO' "$SYM"
  expect deny "[$tier] a push of a top-level symref pointing at main denies"
  pg "$tier" 'git push origin main-worktree/HEAD' "$LINKED" "$LINKED"
  expect deny "[$tier] a push of main-worktree/HEAD, the primary checkout's main, denies"
done
BADREFS="$SANDBOX/bad-refs"
clone_on "$BADREFS" planwright/demo/task-1 1
printf 'not a packed ref line\n' >>"$BADREFS/.git/packed-refs"
pg worker 'git push origin planwright/demo/task-1' "$BADREFS"
expect deny "[worker] a push whose local refs cannot be listed, to resolve its symbolic refs, denies"

# --- git send-pack and git subtree push -------------------------------------

echo "# plumbing and contrib pushes"
SP="$SANDBOX/sendpack"
clone_on "$SP" planwright/demo/task-1 1
for tier in worker tower; do
  for cmd in "git send-pack $ORIGIN HEAD:refs/heads/main" "git send-pack $ORIGIN HEAD:main" \
    "git send-pack --force $ORIGIN HEAD:refs/heads/feature" "git send-pack $ORIGIN +HEAD:refs/heads/feature" \
    "git send-pack $ORIGIN" "git send-pack --all $ORIGIN" "git send-pack --mirror $ORIGIN" \
    "git send-pack --stdin $ORIGIN" "git send-pack $ORIGIN main" "git send-pack $ORIGIN :refs/heads/main" \
    "git send-pack --receive-pack=x $ORIGIN HEAD:refs/heads/feature" "git send-pack --frob $ORIGIN HEAD:refs/heads/feature" \
    'git subtree push --prefix=d origin main' 'git subtree push -P d origin main' 'git subtree -P d push origin main' \
    'git subtree push -P d origin feature:main' 'git subtree push -P d origin +feature' \
    'git subtree push -P d origin heads/main' 'git subtree push --frob -P d origin feature' \
    'git subtree push -P d origin' 'git SUBTREE push -P d origin main' 'git SEND-PACK . HEAD:refs/heads/main'; do
    pg "$tier" "$cmd" "$SP"
    expect deny "[$tier] $cmd denies"
  done
  for cmd in "git send-pack $ORIGIN HEAD:refs/heads/main" "git send-pack $ORIGIN main" \
    'git subtree push -P d origin main' 'git subtree -P d push origin feature:main'; do
    pg "$tier" "$cmd" "$SP"
    reason_has 'protected branch' "[$tier] $cmd denies as a push to main"
  done
done
for cmd in "git send-pack $ORIGIN HEAD:refs/heads/feature-y" 'git subtree push -P d origin feature-y' \
  'git subtree split -P d' 'git subtree push -P d origin HEAD:feature-y'; do
  pg worker "$cmd" "$SP"
  expect defer "[worker] $cmd (an unprotected destination, or no push) defers"
done
for cmd in "git send-pack --atomic --thin $ORIGIN HEAD:refs/heads/feature-y" "git send-pack --dry-run -v $ORIGIN HEAD:refs/heads/feature-y" \
  "git send-pack --signed=if-asked -- $ORIGIN HEAD:refs/heads/feature-y" 'git subtree push -Pd --squash origin feature-y' \
  'git subtree -m msg split -P d' "git send-pack $ORIGIN :refs/heads/feature-y"; do
  pg worker "$cmd" "$SP"
  expect defer "[worker] $cmd (options that change neither what nor where, or no protected target) defers"
done
for cmd in 'git subtree push -Pd origin main' 'git subtree --message x push -P d origin main' \
  'git subtree push -P d -- origin main' "git send-pack \$URL HEAD:refs/heads/feature-y"; do
  pg worker "$cmd" "$SP"
  expect deny "[worker] $cmd (a protected target, or an expansion) denies"
done
pg worker "git send-pack $ORIGIN :refs/heads/planwright/demo/task-2" "$SP"
expect deny "[worker] a send-pack deleting a unit branch denies, as a push deleting one does"
gitq -C "$SP" config alias.sp send-pack
pg worker "git sp $ORIGIN HEAD:refs/heads/main" "$SP"
expect deny "[worker] an alias expanding to git send-pack denies, as one expanding to git push does"

# --- gh api contents write naming heads/<branch> -----------------------------

echo "# gh api contents branch spellings"
for tier in worker tower; do
  pg "$tier" 'gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=heads/main'
  expect deny "[$tier] a contents write to heads/main denies, since GitHub's contents API reads the ref as main"
  reason_has 'protected branch' "[$tier] the heads/main contents write denies as a write to main"
done
pg worker 'gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=heads/feature'
expect defer "[worker] a contents write to heads/feature still defers"

# --- gh api branch renames that move a branch away --------------------------

echo "# gh api renames of a unit or spec-family branch"
# A rename takes the branch off the remote as a delete does, so it is refused
# where the matching delete is: a unit branch for a worker, a spec's amendment
# or spec-rework branch for a worker or the tower.
for tier in worker tower; do
  for b in planwright/demo/amendment-2 planwright/demo/spec-rework Planwright/Demo/Amendment-3; do
    pg "$tier" "gh api -X POST repos/acme/widgets/branches/$b/rename -f new_name=feature-z"
    expect deny "[$tier] a rename of $b denies, as its delete does"
    reason_has 'rename' "[$tier] the $b rename deny names the rename"
  done
done
for b in planwright/demo/task-2 planwright/flight/other-1; do
  pg worker "gh api -X POST repos/acme/widgets/branches/$b/rename -f new_name=feature-z"
  expect deny "[worker] a rename of the unit branch $b denies, as its delete does"
done
for b in planwright/demo/amendment-x planwright/demo/spec-reworks feature-x; do
  pg worker "gh api -X POST repos/acme/widgets/branches/$b/rename -f new_name=feature-z"
  expect defer "[worker] a rename of $b (no unit or spec-family branch) defers"
done
pg tower 'gh api -X POST repos/acme/widgets/branches/planwright/demo/task-2/rename -f new_name=feature-z'
expect defer "[tower] a rename of a unit branch defers, as its delete does at the tower"

# --- branch protection and rulesets -----------------------------------------

echo "# gh api writes to branch protection or a ruleset"
for tier in worker tower; do
  for cmd in 'gh api -X DELETE repos/acme/widgets/branches/main/protection' \
    'gh api -X DELETE repos/acme/widgets/branches/main/protection/required_status_checks' \
    'gh api -X DELETE repos/acme/widgets/branches/main/protection/enforce_admins' \
    'gh api -X PUT repos/acme/widgets/branches/main/protection -F enforce_admins=false' \
    'gh api -X PATCH repos/acme/widgets/branches/planwright/demo/spec/protection/required_pull_request_reviews -F required_approving_review_count=0' \
    'gh api --method DELETE REPOS/Acme/Widgets/Branches/Main/Protection' \
    'gh api -X DELETE /repos/acme/widgets/branches/feature-x/protection' \
    'gh api -X DELETE repos/acme/widgets/rulesets/42' \
    'gh api -X PUT repos/acme/widgets/rulesets/42 -f enforcement=disabled' \
    'gh api -X DELETE orgs/acme/rulesets/7' \
    "gh api graphql -f query='mutation { deleteBranchProtectionRule(input: {branchProtectionRuleId: \"X\"}) { clientMutationId } }'" \
    "gh api graphql -f query='mutation { updateBranchProtectionRule(input: {branchProtectionRuleId: \"X\", requiresApprovingReviews: false}) { clientMutationId } }'" \
    "gh api graphql -f query='mutation { deleteRepositoryRuleset(input: {repositoryRulesetId: \"X\"}) { clientMutationId } }'" \
    "gh api graphql -f query='mutation { createBranchProtectionRule(input: {repositoryId: \"R\", pattern: \"x\"}) { clientMutationId } }'" \
    'gh api -X DELETE repositories/123/branches/main/protection' 'gh api -X DELETE repositories/123/rulesets/4'; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies"
    reason_has 'protection or a ruleset' "[$tier] $cmd denies as a protection change"
  done
done
for cmd in 'gh api repos/acme/widgets/branches/main/protection' 'gh api repos/acme/widgets/rulesets' \
  'gh api -X GET repos/acme/widgets/rulesets/42' 'gh api -X GET repos/acme/widgets/branches/main/protection/required_status_checks' \
  'gh api -X PUT repos/acme/widgets/contents/.github/rulesets/main.json -f message=m -f content=eA== -f branch=feature' \
  'gh api -X PUT repos/acme/widgets/contents/docs/protection/x.md -f message=m -f content=eA== -f branch=feature' \
  "gh api graphql -f query='query { repository(owner: \"a\", name: \"b\") { branchProtectionRules(first: 1) { nodes { ... on BranchProtectionRule { pattern } } } } }'"; do
  pg worker "$cmd"
  expect defer "[worker] $cmd (a read, or a write whose path only names protection or rulesets) defers"
done

no_gh_calls
finish
