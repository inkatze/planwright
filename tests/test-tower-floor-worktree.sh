#!/bin/bash
# The tower deny floor's git worktree rows (tower-placement REQ-C1.1,
# REQ-D1.4): each worktree entry of config/tower-settings.json's deny list,
# through its tests/fixtures/tower-deny-acts.tsv sample, is refused by
# scripts/tower-session.sh in a marked session with no profile, while forms
# that only contain a protected name, plain deletion, and reads defer.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/tower-floor-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/tower-floor-harness.sh"

echo "# each worktree entry's sample: matched by its entry, refused in a marked session"
entry_rows '^worktree$'

echo "# what only contains a protected name, plain deletion, and reads stay deferred (REQ-D1.4)"
for cmd in \
  'git worktree add ../w -b docs/main' \
  'git worktree add ../w -b feature main' \
  'git worktree add ../w HEAD' \
  'git push origin docs/main' \
  'git branch -D planwright/flight/done-0123abcd' \
  'git branch -d -f planwright/flight/done-0123abcd' \
  'git branch -D "$b"' \
  'git branch --sort -committerdate -D planwright/flight/done-0123abcd' \
  "git branch --format='%(refname)' --list" \
  'git branch docs/main' \
  'git reset --soft HEAD' \
  'git worktree remove ../w' \
  'git worktree list --porcelain'; do
  ts_bash "$cmd"
  expect defer "deferred in a marked session: $cmd"
done

no_gh_calls
finish
