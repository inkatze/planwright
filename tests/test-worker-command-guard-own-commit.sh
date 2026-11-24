#!/bin/bash
# Tests for scripts/worker-command-guard.sh: inside the worktree its session
# record names, a file the guard trusts by its content (a repository script, a
# bats file, a linter config, a declared command's literal file) is trusted
# only as the PR base holds it, at the merge base of HEAD and the record's
# pr_base remote-tracking ref. The worker's own commits are not enough: it
# may commit what it wrote, and the guard never sees what the file runs, so a
# script it committed carrying a merge, a ready flip, a push or a gh api write
# prompts. What the base already holds keeps its approval, and so does what the
# worker brings in by merging the base.
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
SC=$CORPUS_SCRATCH
STATE=$CORPUS_BOX/state
MAIN=$CORPUS_BOX/main
UB=$CORPUS_UNIT_BRANCH
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}
# record_with <name> [<field=value>...]: the both-arms record with the named
# fields replaced, or dropped when the value is empty.
record_with() {
  local f=$STATE/$1.record kv k
  shift
  cp "$STATE/record.4" "$f.tmp"
  for kv in "$@"; do
    k=${kv%%=*}
    grep -v "^$k=" "$f.tmp" >"$f.tmp2"
    [ -z "${kv#*=}" ] || printf '%s\n' "$kv" >>"$f.tmp2"
    mv "$f.tmp2" "$f.tmp"
  done
  mv "$f.tmp" "$f"
  mkdir -p "$f.audit"
  printf '%s\n' "$f"
}
# wcommit <dir> <message> <path>...: commit as the worker would, on whatever
# branch <dir> has checked out.
wcommit() {
  local d=$1 m=$2
  shift 2
  corpus_git_env -C "$d" add -- "$@" \
    && corpus_git_env -C "$d" -c user.name=w -c user.email=w@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath="$CORPUS_BOX/no-hooks" commit -q -m "$m"
}
mkdir -p "$CORPUS_BOX/no-hooks"

# One script per reserved act, each committed on the unit branch by the worker.
acts=(
  "merge:gh pr merge 1 --squash"
  "ready:gh pr ready 1"
  "push:git push origin $UB"
  "forcepush:git push --force origin $UB"
  "apiwrite:gh api -X PATCH repos/o/r/pulls/1 -f state=closed"
  "gitc:git -C $WT push --force origin $UB"
)
names=()
for a in "${acts[@]}"; do
  n=${a%%:*}
  printf '#!/bin/sh\n%s\n' "${a#*:}" >"$WT/scripts/act-$n.sh"
  chmod +x "$WT/scripts/act-$n.sh"
  names+=("$n")
done
printf '#!/bin/sh\ngh pr merge 1\n' >"$WT/tests/act.sh"
printf '@test x { gh pr merge 1; }\n' >"$WT/tests/act.bats"
# An edit to a script the base already holds, committed.
printf '#!/bin/sh\ngh pr merge 1\n' >"$WT/tests/ok.sh"
# A symlink committed beside the scripts, and a folder link into scripts/.
ln -s act-merge.sh "$WT/scripts/lnk.sh"
ln -s scripts "$WT/via"
wcommit "$WT" acts scripts tests via || exit 1

REC=$(record_with ob)
under "$REC"

echo "### a script the worker committed on its unit branch prompts"
for n in "${names[@]}"; do
  f=scripts/act-$n.sh
  for c in "bash $f" "sh $f" "./$f" "$f" "$WT/$f" "source $f" ". $f" \
    "FOO=1 bash $f" "FOO=1 $f" "FOO=1 sh $f" "timeout 60 bash $f" "fish -c 'bash $f'" \
    "bash -c '$f'" "bash -c 'bash $f'" "sh -c 'sh $f'" \
    "for x in $f; do bash \$x; done" "git status && bash $f"; do
    assert_defer "$n: $c" "$c" Bash "$WT"
  done
  assert_defer "$n: through a .. walk" "bash ../scripts/act-$n.sh" Bash "$WT/tests"
  assert_defer "$n: after a cd" "cd tests && bash ../$f" Bash "$WT"
  assert_defer "$n: through a folder link" "bash via/act-$n.sh" Bash "$WT"
done
assert_defer "a committed tests/ script" "bash tests/act.sh" Bash "$WT"
assert_defer "a committed edit to a script the base holds" "bash tests/ok.sh" Bash "$WT"
assert_defer "a committed symlink to a committed script" "bash scripts/lnk.sh" Bash "$WT"
assert_defer "bats on a committed file" "bats tests/act.bats" Bash "$WT"
assert_defer "a commit and the run in one command" \
  "git commit -q -m x && bash scripts/act-merge.sh" Bash "$WT"

echo "### what the base holds keeps its approval"
for c in "bash scripts/ok.sh" "sh scripts/ok.sh" "./scripts/ok.sh" "scripts/ok.sh" \
  "timeout 60 bash scripts/ok.sh" "bats tests/ok.bats" \
  "git commit -q -m x && bash scripts/ok.sh"; do
  assert_allow "base: $c" "$c" Bash "$WT"
done

echo "### a local branch that shadows the base's short name is not the base"
corpus_git_env -C "$WT" branch origin/main HEAD
assert_defer "a local origin/main at the worker's commit" "bash scripts/act-merge.sh" Bash "$WT"
assert_allow "the base still answers for its own script" "bash scripts/ok.sh" Bash "$WT"
corpus_git_env -C "$WT" branch -D -q origin/main

echo "### the base moves: a script it gains counts once the worker merges it"
mkdir -p "$MAIN/scripts"
printf '#!/bin/sh\nprintf base\\n\n' >"$MAIN/scripts/gained.sh"
wcommit "$MAIN" gained scripts/gained.sh || exit 1
corpus_git_env -C "$MAIN" push -q origin main && corpus_git_env -C "$MAIN" fetch -q origin || exit 1
printf '#!/bin/sh\nprintf base\\n\n' >"$WT/scripts/gained.sh"
assert_defer "a copy of a base script the branch has not merged" "bash scripts/gained.sh" Bash "$WT"
rm -f "$WT/scripts/gained.sh"
corpus_git_env -C "$WT" -c user.name=w -c user.email=w@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath="$CORPUS_BOX/no-hooks" merge -q --no-edit origin/main || exit 1
assert_allow "the base script, merged in" "bash scripts/gained.sh" Bash "$WT"
assert_defer "the worker's script after the merge" "bash scripts/act-merge.sh" Bash "$WT"

echo "### another branch's HEAD is not the base either"
corpus_git_env -C "$WT" checkout -q -b planwright/demo/task-2
printf '#!/bin/sh\ngh pr merge 1\n' >"$WT/scripts/side.sh"
wcommit "$WT" side scripts/side.sh || exit 1
assert_defer "a script committed on a side branch" "bash scripts/side.sh" Bash "$WT"
corpus_git_env -C "$WT" checkout -q "$UB"

echo "### a linter config and a declared command's file, committed by the worker"
assert_allow "control: the lint with no config" "markdownlint-cli2 --no-globs notes.md" Bash "$WT"
printf '{ "MD013": false }\n' >"$WT/.markdownlint.jsonc"
wcommit "$WT" lint .markdownlint.jsonc || exit 1
assert_defer "a config the worker committed" "markdownlint-cli2 --no-globs notes.md" Bash "$WT"
corpus_git_env -C "$WT" rm -q .markdownlint.jsonc \
  && corpus_git_env -C "$WT" -c user.name=w -c user.email=w@example.invalid -c commit.gpgsign=false \
    -c core.hooksPath="$CORPUS_BOX/no-hooks" commit -q -m unlint || exit 1
DECL=$(record_with decl "check_commands=scripts/act-merge.sh <word>; scripts/ok.sh <word>")
under "$DECL"
assert_defer "a declared command naming a committed script" "scripts/act-merge.sh lint" Bash "$WT"
assert_allow "a declared command naming a base script" "scripts/ok.sh lint" Bash "$WT"

echo "### no base to hold the file to"
under "$(record_with nobase pr_base=)"
assert_defer "no pr_base: a committed script" "bash scripts/act-merge.sh" Bash "$WT"
assert_defer "no pr_base: a base script, with nothing to check it by" "bash scripts/ok.sh" Bash "$WT"
under "$(record_with gone pr_base=origin/gone)"
assert_defer "a pr_base with no remote-tracking ref" "bash scripts/ok.sh" Bash "$WT"

echo "### a repository nested in the worktree answers to no base"
N=$WT/sub/nested
mkdir -p "$N/scripts"
printf '#!/bin/sh\ngh pr merge 1\n' >"$N/scripts/n.sh"
corpus_git_env init -q "$N" && wcommit "$N" nested scripts || exit 1
under "$REC"
assert_defer "a script a nested repository commits" "bash scripts/n.sh" Bash "$N"
HOOK_ENV=()

finish_suite worker-command-guard-own-commit
