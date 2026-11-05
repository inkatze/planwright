#!/bin/bash
# The tower floor's branch-move and stash-write acts (tower-placement
# REQ-D1.1, REQ-D1.2, REQ-D1.4): each entry row of those acts in
# tests/fixtures/tower-deny-acts.tsv is matched by its entry and refused in
# a marked session with no profile; every row of those acts is refused under
# the profile launch too, in the tower's own checkout and in another one;
# and what REQ-D1.1 keeps stays deferred and matched by no deny glob.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/tower-floor-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/tower-floor-harness.sh"

echo "# each branch-move and stash-write entry's sample: matched by its entry, refused in a marked session"
entry_rows '^(branch-move|stash-write)$'

echo "# every branch-move and stash-write row: refused under the profile launch, in the tower's own checkout"
while IFS="$TAB" read -r kind a b c; do
  case $kind:$a:$b in
    entry:*:branch-move | entry:*:stash-write) cmd=$c ;;
    spelling:branch-move:* | spelling:stash-write:*) cmd=$c ;;
    *) continue ;;
  esac
  pg tower "$cmd" "$UNIT" "$UNIT"
  expect deny "profile launch: $cmd"
done <"$MAP"

echo "# the acts are refused in a checkout the tower does not own too"
OTHER="$SANDBOX/other"
clone_on "$OTHER" planwright/demo/task-2 0
for cmd in 'git checkout main' 'git switch main' 'git reset --soft HEAD' 'git stash' 'git stash pop' \
  'git branch -m planwright/demo/task-2 x' 'git symbolic-ref HEAD refs/heads/main' 'git fetch origin main:main'; do
  pg tower "$cmd" "$OTHER" "$UNIT"
  expect deny "profile launch, run in another checkout: $cmd"
  pg tower "git -C $OTHER ${cmd#git }" "$UNIT" "$UNIT"
  expect deny "profile launch, aimed at another checkout with -C: $cmd"
done

echo "# what REQ-D1.1 keeps: deferred in a marked session and under the profile launch, matched by no deny glob"
pm_load_rules "$(jq -r '.permissions.deny[]' "$PROFILE")" '' ''
for cmd in \
  'git stash list' \
  'git stash list --date=relative' \
  'git stash show' \
  'git stash show -p stash@{1}' \
  'git commit -m wip' \
  'git branch topic2' \
  'git branch docs/main' \
  'git branch -D planwright/flight/done-0123abcd' \
  'git branch -d topic' \
  'git branch --list' \
  'git worktree add ../w -b docs/main' \
  'git push origin docs/main' \
  'git fetch origin' \
  'git fetch --prune origin' \
  'git fetch --multiple origin upstream' \
  'git remote add upstream ../x' \
  'git remote add -f upstream ../x' \
  'git remote add --mirror=push backup ../x' \
  'git fetch origin main' \
  'git fetch origin main:refs/remotes/origin/main' \
  "git fetch origin '+refs/heads/*:refs/remotes/origin/*'" \
  'git fetch git@example.invalid:o/r.git main' \
  'git symbolic-ref HEAD' \
  'git symbolic-ref --short refs/remotes/origin/HEAD' \
  'git restore README.md' \
  'env git status --short' \
  'nice git -C . log -1' \
  'env git -c core.pager=cat status' \
  'x=$(git rev-parse HEAD)' \
  'gh pr view 42'; do
  ts_bash "$cmd"
  expect defer "marked session keeps: $cmd"
  pg tower "$cmd" "$UNIT" "$UNIT"
  expect defer "profile launch keeps: $cmd"
  if [ "$(pm_decide "$cmd")" != deny ]; then
    pass "no deny glob matches: $cmd"
  else
    fail "a deny glob matches what REQ-D1.1 keeps: $cmd ($(pm_matching_deny_rule "$cmd"))"
  fi
done

no_gh_calls
finish
