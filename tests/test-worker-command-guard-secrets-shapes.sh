#!/bin/bash
# Tests for scripts/worker-command-guard.sh: further secret-read shapes that
# always defer (tilde forms naming another account, in-tree symlinks followed
# by recursive readers, files named by git options, gh jq/template reads of the
# environment, file-timestamp readers), with the allows that stay beside them.
# Split from the secrets suite to keep each file inside its time budget. All
# suites source tests/lib/worker-command-guard-harness.sh, which states the
# contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

# The harness pins HOME to $SANDBOX/no-home. The directories exist so a path
# the guard resolves (a symlink into them) can be entered.
H=$SANDBOX/no-home
mkdir -p "$H/.ssh" "$H/.gnupg" "$H/.aws" "$H/.config/gh" "$H/.claude" "$SANDBOX/notes"
: >"$H/.ssh/id_rsa"
: >"$H/.claude/.credentials.json"
: >"$SANDBOX/notes/plain.txt"
ln -s "$H/.ssh" "$SANDBOX/sub/sshdir"
ln -s "$H/.ssh/id_rsa" "$SANDBOX/sub/key"
ln -s "$H/.claude/.credentials.json" "$SANDBOX/sub/creds"
ln -s "$SANDBOX/notes" "$SANDBOX/sub/notesdir"
ln -s "$H" "$SANDBOX/sub/homelink"

echo "### Tilde forms naming another account, the cwd or the old cwd"
mkdir -p "$SANDBOX/shadowtree"
: >"$SANDBOX/shadowtree/key"
# shellcheck disable=SC2016,SC2088 # the guard reads the words as written
for c in 'cat ~+/.ssh/id_rsa' 'cat ~-/.ssh/id_rsa' 'cat ~root/.ssh/id_rsa' 'cat ~someone/.aws/credentials' \
  'cat ~root/.ssh/*' 'cat ~someone/.s*/id_rsa' 'cat ~root/{.ssh,x}/id_rsa' 'ls ~root/.ssh' 'ls ~someone/.ssh/' \
  'ls ~root/.config/gh' 'grep -r x ~root' 'grep -r x ~someone' 'grep -r x ~someone/.config' 'ls -R ~root' \
  'find ~someone -name id_rsa' 'rg BEGIN ~root' 'grep -r x ~-' 'grep -r x ~+/..' 'cat ~+/../.ssh/id_rsa' \
  'cat ~-/../.aws/credentials' 'cat ~root/.ss?/id_rsa' 'wc -c < ~someone/.ssh/id_rsa'; do
  assert_defer "secrets: tilde form: $c" "$c"
done
# shellcheck disable=SC2016,SC2088 # the guard reads the words as written
for c in 'cat ~root/.config/*/hosts.yml' 'cat ~root/.config/g[h]/hosts.yml' 'cat ~root/.config/g?/hosts.yml' \
  'cat ~someone/.local/share/keyr*/login.keyring' 'cat ~root/.co*/gh/hosts.yml' 'cat ~root/.CONFIG/*/hosts.yml' \
  'cat ~nobody/.config/*/hosts.yml' 'cat ~+/../.config/*/hosts.yml' 'cat ~-/.config/*/hosts.yml' 'cat ~-/.a*/credentials'; do
  assert_defer "secrets: a glob under a home the guard cannot expand: $c" "$c"
done
# shellcheck disable=SC2088 # the guard reads the words as written
assert_allow "secrets: a glob under ~+ that names no secret" 'cat ~+/scripts/*.sh'

echo "### Recursive readers that follow an in-tree symlink into a secret"
for c in 'grep -R BEGIN sub' 'grep -R BEGIN .' 'grep -Rn BEGIN sub' 'grep -nR BEGIN sub' 'grep --dereference-recursive BEGIN sub' \
  'grep --deref BEGIN sub' 'rg -L BEGIN sub' 'rg --follow BEGIN sub' 'rg -uL BEGIN sub' 'rg -L -l BEGIN' \
  'diff -r sub shadowtree' 'diff -rq shadowtree sub' 'diff -ru sub shadowtree'; do
  assert_defer "secrets: a followed link: $c" "$c"
done
assert_allow "secrets: grep -R over a tree whose only link is harmless" "grep -R BEGIN scripts"
assert_allow "secrets: rg -L over a tree with no link" "rg -L BEGIN scripts"
assert_allow "secrets: grep -R over a linked directory that holds no link" "grep -R BEGIN sub/notesdir"
assert_allow "secrets: diff -r where no link has a counterpart" "diff -r sub notes"

echo "### git readers that open any file named by an option"
for c in 'git blame --ignore-revs-file x -- README.md' 'git blame --ignore-revs-file=/etc/shadow -- README.md' \
  'git blame --ignore-revs-f=x -- README.md' 'git blame --ignore-revs x -- README.md' \
  'git grep -f /etc/shadow x' 'git grep -f/etc/shadow x' 'git grep -nf /home/someone/.aws/credentials' \
  'git log --orderfile=/etc/shadow' 'git diff --orderfile /home/someone/.aws/credentials' 'git diff --order=/etc/shadow' \
  'git show --or=/etc/shadow HEAD' 'git ls-files --exclude-from=/etc/shadow' 'git ls-files -X /etc/shadow' \
  'git ls-files --exclude-f=/etc/shadow' 'git ls-files --exclude-from /home/someone/.aws/credentials'; do
  assert_defer "secrets: git file option: $c" "$c"
done
echo "### git --no-index spelled by any prefix"
for c in 'git diff --no-in /home/someone/.aws/credentials x' 'git diff --no-i /home/someone/.aws/credentials x' \
  'git diff --no-ind /home/someone/.aws/credentials x' 'git grep --no-in -e KEY /home/someone/.aws/credentials' \
  'git grep --no-i -e KEY /home/someone/.aws/credentials' 'git diff --no-index a b' \
  'git diff --no-in sub scripts' 'git diff --no-i sub scripts' 'git diff --no-ind sub scripts'; do
  assert_defer "secrets: no-index prefix: $c" "$c"
done
assert_allow "secrets: git log with --oneline" "git log --oneline -n 3"
assert_allow "secrets: git blame a tracked file" "git blame -L1,3 -- README.md"
assert_allow "secrets: git grep a pattern in the tree" "git grep -n TODO -- scripts"
assert_allow "secrets: git ls-files in the tree" "git ls-files scripts"

echo "### gh read verbs whose jq filter or template could print the environment"
# shellcheck disable=SC2016 # the guard reads the words as written
for c in 'gh pr view 1 --json title --jq env' 'gh pr view 1 --jq=env' 'gh pr view 1 --jq $ENV' 'gh pr view 1 --jq=$ENV.GH_TOKEN' \
  'gh pr view 1 -q env' 'gh pr view 1 -qenv' 'gh pr list --json number -q env' 'gh pr view 1 --template {{env}}' \
  'gh pr view 1 --template={{env}}' 'gh issue view 1 --jq env' 'gh issue list --jq=env' 'gh run view 1 --jq env' \
  'gh run list --json name --jq env' 'gh repo view --jq env' 'gh repo view --json name -q env' \
  'gh release view v1 --jq env' 'gh release list --jq=env' 'gh pr status --jq env' 'gh pr checks 1 --jq=env' \
  'gh api repos/o/r --template {{env}}' 'gh api repos/o/r --template={{env}}'; do
  assert_defer "secrets: gh jq/template: $c" "$c"
done
assert_allow "secrets: gh pr view with a jq field" "gh pr view 1 --json title --jq .title"
assert_allow "secrets: gh run list with a jq filter" "gh run list --json name -q .name"
assert_allow "secrets: gh repo view with a jq filter" "gh repo view --json name --jq .name"
assert_allow "secrets: gh pr view of a branch named like an environment" "gh pr view 1 --json title"

echo "### Other readers: file timestamps and abbreviated options"
for c in 'date -r /home/someone/.aws/credentials' 'date -r ~/.ssh/id_rsa' 'date --reference=/etc/shadow' 'date --ref=/etc/shadow' \
  'date --fil=/etc/shadow' 'date --fi=/etc/shadow' 'tree /home/someone' 'tree ~' 'du -a ~' 'du -a /home/someone' 'du -a /etc'; do
  assert_defer "secrets: $c" "$c"
done
# tree and du are not allow-listed verbs, so the refusals above hold whatever
# the operand is; these two pin that the verbs themselves keep deferring.
assert_defer "secrets: tree over the worktree still defers as a verb" "tree scripts"
assert_defer "secrets: du -a over the worktree still defers as a verb" "du -a scripts"
assert_allow "secrets: date -r of a worktree file" "date -r scripts/ok.sh"


finish_suite worker-command-guard-secrets-shapes
