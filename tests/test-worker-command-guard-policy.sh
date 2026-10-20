#!/bin/bash
# Tests for the worker command guard's self-approval policy: the session
# record it reads its trust inputs from (REQ-G1.8, REQ-B1.8), the policy knob
# and its fallback (REQ-F1.1), the per-segment evaluation (REQ-F1.2), the
# own-branch arm (REQ-F1.3), the floor under every policy value (REQ-F1.5),
# and the excluded paths (REQ-F1.6); tests/test-worker-command-guard-deny.sh
# asserts the deny block as an outcome (REQ-A1.11). The rows run in the corpus sandbox (tests/lib/
# worker-guard-corpus.sh): a linked worktree on its unit branch whose base
# resolves as origin/main, with one session record per policy column.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
OUT_DIR=$CORPUS_OUTSIDE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")

# under <record>: the hook reads this record from here on.
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}
# record_with <name> <policy> [<field=value>...]: a copy of the
# both-arms record with the policy replaced and the named fields replaced or
# (with an empty value) dropped; prints its path.
record_with() {
  local f=$STATE/$1.record kv k
  shift
  {
    printf 'policy=%s\n' "$1"
    shift
    grep -v '^policy=' "$STATE/record.4"
  } >"$f.tmp"
  for kv in "$@"; do
    k=${kv%%=*}
    grep -v "^$k=" "$f.tmp" >"$f.tmp2"
    [ -z "${kv#*=}" ] || printf '%s\n' "$kv" >>"$f.tmp2"
    mv "$f.tmp2" "$f.tmp"
  done
  mv "$f.tmp" "$f"
  printf '%s\n' "$f"
}
POLICIES=("" "own-branch" "scratch" "own-branch scratch")
OB=$(record_with ob own-branch)

echo "### REQ-F1.3 — the own-branch arm approves writes inside the worktree"
under "$OB"
assert_allow "F1.3: sed -i with a read-only script" "sed -i s/a/b/ f" Bash "$WT"
assert_allow "F1.3: rm -r of a directory" "rm -r build" Bash "$WT"
assert_allow "F1.3: mkdir -p of new components" "mkdir -p build/x/y" Bash "$WT"
assert_allow "F1.3: touch a new file" "touch build/new" Bash "$WT"
assert_allow "F1.3: a write-redirect" "grep -n x f > build/out.txt 2>&1" Bash "$WT"
assert_allow "F1.3: cp a file to a new path" "cp f build/f2" Bash "$WT"
assert_allow "F1.3: cp into an existing directory" "cp f sub" Bash "$WT"
assert_allow "F1.3: cp -r to a new path" "cp -r sub build/sub2" Bash "$WT"
assert_allow "F1.3: mv inside the worktree" "mv build/a build/b" Bash "$WT"
assert_allow "F1.3: tee -a" "echo x | tee -a notes.md" Bash "$WT"
assert_allow "F1.3: an absolute path written under the root" "touch $WT/build/abs" Bash "$WT"
assert_allow "F1.3: git add -A" "git add -A" Bash "$WT"
assert_allow "F1.3: git commit -m" "git commit -m x" Bash "$WT"
assert_allow "F1.3: git commit -am" "git commit -am 'feat: x'" Bash "$WT"
assert_allow "F1.3: git commit -F a file inside" "git commit -q -F build/msg.txt" Bash "$WT"
assert_allow "F1.3: git rm" "git rm -q g" Bash "$WT"
assert_allow "F1.3: git mv" "git mv f h" Bash "$WT"
assert_allow "F1.3: git restore" "git restore f" Bash "$WT"
assert_allow "F1.3: git restore --staged" "git restore --staged f" Bash "$WT"
assert_allow "F1.3: git checkout -- <paths>" "git checkout -- f g" Bash "$WT"
assert_allow "F1.3: git fetch origin" "git fetch origin" Bash "$WT"
assert_allow "F1.3: git fetch origin main" "git fetch origin main" Bash "$WT"
assert_allow "F1.3: git merge of the PR base" "git merge origin/main" Bash "$WT"
assert_allow "F1.3: git merge --no-edit of the PR base" "git merge --no-edit origin/main" Bash "$WT"
assert_allow "F1.3: a cd then a write, resolved from the new directory" "cd sub && touch new" Bash "$WT"

echo "### REQ-F1.3 — what the arm still defers"
assert_defer "F1.3: cp -l from outside" "cp -l $OUT_DIR/x build/x" Bash "$WT"
assert_defer "F1.3: cp -s from outside" "cp -s $OUT_DIR/x build/x" Bash "$WT"
assert_defer "F1.3: cp -a" "cp -a f build/f" Bash "$WT"
assert_defer "F1.3: cp from outside the worktree" "cp $OUT_DIR/x build/x" Bash "$WT"
assert_defer "F1.3: mv from outside the worktree" "mv $OUT_DIR/x build/x" Bash "$WT"
assert_defer "F1.3: mv to outside the worktree" "mv f $OUT_DIR/f" Bash "$WT"
assert_defer "F1.3: sed -i with an exec command" "sed -i '1e touch x' f" Bash "$WT"
assert_defer "F1.3: sed -i with a backup suffix" "sed -i.bak s/a/b/ f" Bash "$WT"
assert_defer "F1.3: sed -i of a missing file" "sed -i s/a/b/ missing" Bash "$WT"
assert_defer "F1.3: sed -i of a file BSD sed would read as a write script" "sed -i s/a/b/ wout" Bash "$WT"
assert_defer "F1.3: a write to a file with a second hard link" "echo x >> hardlinked" Bash "$WT"
assert_defer "F1.3: touch through a symlink" "touch outlink/x" Bash "$WT"
assert_defer "F1.3: rm of the worktree root" "rm -rf $WT" Bash "$WT"
assert_defer "F1.3: rm with a .. component" "rm -rf sub/../build" Bash "$WT"
assert_defer "F1.3: rm of a glob" "rm -rf build/*" Bash "$WT"
assert_defer "F1.3: rm of an unresolved expansion" "rm -rf \$X" Bash "$WT"
assert_defer "F1.3: rm --no-preserve-root" "rm -rf --no-preserve-root build" Bash "$WT"
assert_defer "F1.3: rm of the worktree itself" "rm -rf ." Bash "$WT"
assert_defer "F1.3: a recursive removal over an excluded path" "rm -rf githooks" Bash "$WT"
assert_defer "F1.3: a write following a link-creating segment" "ln -s $OUT_DIR l && touch l/x" Bash "$WT"
assert_defer "F1.3: a write after a recursive copy" "cp -r sub build/s && touch build/s/x" Bash "$WT"
assert_defer "F1.3: a write before a move" "touch build/x && mv build/a build/c" Bash "$WT"
assert_defer "F1.3: a write after a checkout" "git checkout -- f && echo x > g" Bash "$WT"
assert_defer "F1.3: git fetch of a src:dst refspec" "git fetch origin main:main" Bash "$WT"
assert_defer "F1.3: git fetch of a URL" "git fetch https://example.invalid/r.git" Bash "$WT"
assert_defer "F1.3: git fetch of a path" "git fetch ../other" Bash "$WT"
assert_defer "F1.3: git fetch --upload-pack" "git fetch --upload-pack=x origin" Bash "$WT"
assert_defer "F1.3: bare git fetch" "git fetch" Bash "$WT"
assert_defer "F1.3: git merge from another source" "git merge origin/other" Bash "$WT"
assert_defer "F1.3: git merge of two sources" "git merge origin/main origin/other" Bash "$WT"
assert_defer "F1.3: git merge with a strategy option" "git merge -X theirs origin/main" Bash "$WT"
assert_defer "F1.3: git checkout of a branch" "git checkout other" Bash "$WT"
assert_defer "F1.3: git checkout <tree> -- <paths>" "git checkout other -- f" Bash "$WT"
assert_defer "F1.3: git restore with pathspec magic" "git restore ':/'" Bash "$WT"
assert_defer "F1.3: git rm of an excluded path" "git rm -q mise.toml" Bash "$WT"
assert_defer "F1.3: git commit -F a file outside" "git commit -F $OUT_DIR/x" Bash "$WT"
assert_defer "F1.3: git commit opening an editor template" "git commit -t f" Bash "$WT"
assert_defer "F1.3: git add -p is interactive" "git add -p" Bash "$WT"
assert_defer "F1.3: git push gets no guard approval" "git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.3: a write inside a substitution" "echo \$(touch build/x)" Bash "$WT"
assert_defer "F1.3: a write inside fish -c" "fish -c 'touch build/x'" Bash "$WT"
assert_defer "F1.3: a write from a payload directory outside the worktree" "touch x" Bash "$OUT_DIR"

echo "### REQ-F1.3 — the base merge reads the gate and the branch from the record"
under "$(record_with ob-nomerge own-branch worker_base_merge=deny)"
assert_defer "F1.3: the base merge under worker_base_merge deny" "git merge origin/main" Bash "$WT"
under "$(record_with ob-nobase own-branch pr_base=)"
assert_defer "F1.3: the base merge with no PR base recorded" "git merge origin/main" Bash "$WT"
assert_allow "F1.3: no PR base leaves the rest of the arm working" "touch build/x" Bash "$WT"
under "$(record_with ob-othbase own-branch pr_base=origin/other)"
assert_allow "F1.3: the recorded PR base is what the merge must name" "git merge origin/other" Bash "$WT"
assert_defer "F1.3: and nothing else" "git merge origin/main" Bash "$WT"

echo "### REQ-G1.8 — the unit branch is the record's, not the checkout's"
under "$OB"
corpus_git switch -q other
assert_defer "G1.8: after git switch other, no own-branch git act" "git commit -m x" Bash "$WT"
assert_defer "G1.8: after git switch other, no base merge" "git merge origin/main" Bash "$WT"
corpus_git switch -q "$CORPUS_UNIT_BRANCH"
assert_allow "G1.8: back on the unit branch, the arm approves again" "git commit -m x" Bash "$WT"
under "$(record_with ob-otherunit own-branch unit_branch=planwright/demo/task-2)"
assert_defer "G1.8: a record naming another unit branch approves no git act" "git add -A" Bash "$WT"

echo "### REQ-B1.8 — a missing or unparseable field disables what reads it"
under "$(record_with nounit own-branch unit_branch=)"
assert_defer "B1.8: no unit branch, no own-branch write" "touch build/x" Bash "$WT"
assert_defer "B1.8: no unit branch, no cd" "cd sub && ls" Bash "$WT"
under "$(record_with nowt own-branch worktree_root=)"
assert_defer "B1.8: no worktree root, no own-branch write" "touch build/x" Bash "$WT"
assert_defer "B1.8: no worktree root, no cd" "cd sub && ls" Bash "$WT"
assert_allow "B1.8: the read-only arm stays in force" "grep -n x f" Bash "$WT"
under "$(record_with badunit own-branch unit_branch=main)"
assert_defer "B1.8: a unit branch outside the grammar is dropped" "touch build/x" Bash "$WT"
under "$(record_with relwt own-branch worktree_root=worktree)"
assert_defer "B1.8: a relative worktree root is dropped" "touch build/x" Bash "$WT"
f=$(record_with dup own-branch)
printf 'policy=own-branch\n' >>"$f"
under "$f"
assert_defer "B1.8: a repeated policy field reads as the empty list" "touch build/x" Bash "$WT"
under "$(record_with unknown 'own-branch everything')"
assert_defer "F1.1: an unknown member makes the whole policy empty" "touch build/x" Bash "$WT"
under "$(record_with malformed 'own-branch,scratch')"
assert_defer "F1.1: a malformed policy is the empty list" "touch build/x" Bash "$WT"
under "$STATE/absent.record"
assert_defer "B1.8: an unreadable record leaves no own-branch arm" "touch build/x" Bash "$WT"
assert_allow "B1.8: an unreadable record leaves the read-only arm" "git status" Bash "$WT"
cp "$OB" "$WT/build/inside.record"
under "$WT/build/inside.record"
assert_defer "G1.8: a record inside the worktree it names is no record" "touch build/x" Bash "$WT"
ln -s "$OB" "$STATE/link.record"
under "$STATE/link.record"
assert_defer "G1.8: a record reached through a symlink is no record" "touch build/x" Bash "$WT"
under "$(record_with scratch-only scratch)"
assert_defer "F1.1: the scratch arm alone approves no worktree write" "touch build/x" Bash "$WT"

echo "### REQ-F1.2 — the policy applies per segment"
under "$OB"
assert_defer "F1.2: an approved write beside a floor write" "git add f && rm -rf /" Bash "$WT"
assert_defer "F1.2: an approved write beside an unapproved verb" "touch build/x && python3 -c 1" Bash "$WT"

echo "### REQ-F1.6 — execution-bearing paths are closed to the arm"
for c in "echo x > .git" "echo x >> .git/config" "touch githooks/pre-commit" "mkdir -p githooks/x" \
  "touch .claude/settings.json" "cp f .claude/x" "echo x >> mise.toml" "sed -i s/a/b/ mise.local.toml" \
  "mkdir -p .mise/tasks" "rm lefthook.yml" "touch sub/mise.toml" "touch sub/.CLAUDE" "touch .envrc" \
  "mv f lefthook-local.yml" "mkdir -p .config/x"; do
  assert_defer "F1.6: $c" "$c" Bash "$WT"
done
assert_allow "F1.6: editing a repo script stays approvable" "echo 'echo hi' >> scripts/ok.sh" Bash "$WT"
assert_allow "F1.6: then running it" "bash scripts/ok.sh" Bash "$WT"

echo "### REQ-F1.5 — the floor holds under every policy value"
for col in 1 2 3 4; do
  under "$STATE/record.$col"
  p=${POLICIES[col - 1]}
  for c in "gh pr merge 5" "gh pr ready 5" "gh pr ready 5 --undo" "git push --force origin x" \
    "git commit --amend -m x" "git commit -n -m x" "git commit -qn -m x" "git rebase origin/main" \
    "git reset --hard origin/main" "git push origin HEAD:main" "git push origin other" \
    "touch $OUT_DIR/x" "echo x > /tmp/out" "gh pr comment 5 --body x" "git merge --squash origin/main"; do
    assert_defer "F1.5 [$p]: $c" "$c" Bash "$WT"
  done
  assert_allow "F1.5 [$p]: /dev/null is not a floor write" "cat f >/dev/null 2>&1" Bash "$WT"
done
under "$OB"
assert_allow "F1.5: git commit is not refused for writing git's own directory" "git commit -m x" Bash "$WT"
# A floor command the arm would otherwise approve: the excluded-path write is
# a write the arm's writer screen admits in every other respect, and the
# deny-matched read is one the read-only arm approves.
assert_allow "F1.5: the arm approves this write shape" "echo x >> notes.md" Bash "$WT"
assert_defer "F1.5: the floor refuses the same shape on an excluded path" "echo x >> mise.toml" Bash "$WT"
assert_allow "F1.5: the read-only arm approves this read shape" "git config --get user.name" Bash "$WT"
assert_defer "F1.5: the floor refuses it once a deny rule matches" "git config --get core.hooksPath" Bash "$WT"

finish_suite worker-command-guard-policy
