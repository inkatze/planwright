#!/bin/bash
# Tests for scripts/worker-command-guard.sh: inside the worktree its session
# record names, a file the guard trusts by its content (a repository script, a
# bats file, a linter config, a declared command's literal file) is trusted
# only as the base holds it, at the merge base of HEAD and the record's
# pr_base remote-tracking ref. The worker's own commits are not enough: it
# may commit what it wrote, and the guard never sees what the file runs, so a
# script it committed carrying a merge, a ready flip, a push or a gh api write
# prompts. What the base already holds keeps its approval, and so does what the
# worker brings in by merging the base. Every spelling that reaches a committed
# script is paired with the same spelling on a base script, which approves, so
# a guard that refused them all would fail here.
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
  printf '%s\n' "$f"
}
mkdir -p "$CORPUS_BOX/no-hooks"
# wgit <dir> <args>: git as the worker runs it in <dir>, with an identity and
# no hooks.
wgit() {
  local d=$1
  shift
  corpus_git_env -C "$d" -c user.name=w -c user.email=w@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath="$CORPUS_BOX/no-hooks" "$@"
}
# wcommit <dir> <message> <path>...: commit as the worker would, on whatever
# branch <dir> has checked out.
wcommit() {
  local d=$1 m=$2
  shift 2
  wgit "$d" add -- "$@" && wgit "$d" commit -q -m "$m"
}

# One script per reserved act, each committed on the unit branch by the worker.
# The guard never reads a script's content, so the full set of spellings runs
# on one of them and the rest are spot-checked.
acts=(
  "merge:gh pr merge 1 --squash"
  "ready:gh pr ready 1"
  "push:git push origin $UB"
  "forcepush:git push --force origin $UB"
  "apiwrite:gh api -X PATCH repos/o/r/pulls/1 -f state=closed"
  "gitcpush:git -C $WT push --force origin $UB"
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

echo "### a script the worker committed on its unit branch prompts; the base's own approves"
# spellings <script> <name>: every spelling the guard approves for a trusted
# script, each naming scripts/<name>.
spellings() {
  local f=scripts/$1
  printf '%s\n' "bash $f" "sh $f" "./$f" "$f" "$WT/$f" "timeout 60 bash $f" \
    "fish -c 'bash $f'" "for x in $f; do bash \$x; done" "git status && bash $f"
}
while IFS= read -r c; do
  assert_defer "committed: $c" "$c" Bash "$WT"
done < <(spellings act-merge.sh)
while IFS= read -r c; do
  assert_allow "base: $c" "$c" Bash "$WT"
done < <(spellings ok.sh)
assert_defer "committed: through a .. walk" "bash ../scripts/act-merge.sh" Bash "$WT/tests"
assert_allow "base: through a .. walk" "bash ../scripts/ok.sh" Bash "$WT/tests"
assert_defer "committed: after a cd" "cd tests && bash ../scripts/act-merge.sh" Bash "$WT"
assert_allow "base: after a cd" "cd tests && bash ../scripts/ok.sh" Bash "$WT"
assert_defer "committed: through a folder link" "bash via/act-merge.sh" Bash "$WT"
assert_allow "base: through a folder link" "bash via/ok.sh" Bash "$WT"
for n in "${names[@]}"; do
  assert_defer "$n: bash" "bash scripts/act-$n.sh" Bash "$WT"
  assert_defer "$n: direct" "./scripts/act-$n.sh" Bash "$WT"
done
assert_defer "a committed tests/ script" "bash tests/act.sh" Bash "$WT"
assert_defer "a committed edit to a script the base holds" "bash tests/ok.sh" Bash "$WT"
assert_defer "bats on a committed file" "bats tests/act.bats" Bash "$WT"
assert_allow "bats on a base file" "bats tests/ok.bats" Bash "$WT"
assert_defer "a commit and the run in one command" \
  "git commit -q -m x && bash scripts/act-merge.sh" Bash "$WT"
assert_allow "a commit and a base script in one command" \
  "git commit -q -m x && bash scripts/ok.sh" Bash "$WT"

echo "### spellings the guard defers whatever the file (regression only)"
# These defer on a base script too, so they cannot show which commit the guard
# holds a file to; they pin that no spelling of the run reopens it.
for f in scripts/act-merge.sh scripts/ok.sh; do
  for c in "source $f" ". $f" "FOO=1 bash $f" "FOO=1 $f" "FOO=1 sh $f" \
    "bash -c '$f'" "bash -c 'bash $f'" "sh -c 'sh $f'"; do
    assert_defer "shape: $c" "$c" Bash "$WT"
  done
done
assert_defer "shape: a committed symlink to a committed script" "bash scripts/lnk.sh" Bash "$WT"

echo "### a local ref named like the base is not the base"
corpus_git_env -C "$WT" branch origin/main HEAD || exit 1
assert_defer "a local origin/main at the worker's commit" "bash scripts/act-merge.sh" Bash "$WT"
assert_allow "the base still answers for its own script" "bash scripts/ok.sh" Bash "$WT"
corpus_git_env -C "$WT" branch -D -q origin/main || exit 1
BASE_OID=$(corpus_git_env -C "$WT" rev-parse refs/remotes/origin/main) || exit 1
# With the tracking ref gone, git's lookup of refs/remotes/origin/main finds a
# local branch of that full name; the guard must not.
corpus_git_env -C "$WT" branch -q -d -r origin/main || exit 1
corpus_git_env -C "$WT" branch refs/remotes/origin/main HEAD || exit 1
assert_defer "a local branch named refs/remotes/origin/main, the tracking ref deleted" \
  "bash scripts/act-merge.sh" Bash "$WT"
assert_defer "the same stand-in, for a base script with nothing to check it by" \
  "bash scripts/ok.sh" Bash "$WT"
corpus_git_env -C "$WT" branch -D -q refs/remotes/origin/main \
  && corpus_git_env -C "$WT" update-ref refs/remotes/origin/main "$BASE_OID" || exit 1
assert_allow "the tracking ref restored" "bash scripts/ok.sh" Bash "$WT"
# show-ref follows a symbolic ref, so one at the base's name is refused.
corpus_git_env -C "$WT" symbolic-ref refs/remotes/origin/main "refs/heads/$UB" || exit 1
assert_defer "the base's name as a symbolic ref to the unit branch" "bash scripts/act-merge.sh" Bash "$WT"
corpus_git_env -C "$WT" symbolic-ref --delete refs/remotes/origin/main \
  && corpus_git_env -C "$WT" update-ref refs/remotes/origin/main "$BASE_OID" || exit 1
assert_allow "the tracking ref restored again" "bash scripts/ok.sh" Bash "$WT"

echo "### the base moves: a script it gains counts once the worker merges it"
mkdir -p "$MAIN/scripts"
printf '#!/bin/sh\nprintf base\\n\n' >"$MAIN/scripts/gained.sh"
wcommit "$MAIN" gained scripts/gained.sh || exit 1
corpus_git_env -C "$MAIN" push -q origin main && corpus_git_env -C "$MAIN" fetch -q origin || exit 1
printf '#!/bin/sh\nprintf base\\n\n' >"$WT/scripts/gained.sh"
assert_defer "a copy of a base script the branch has not merged" "bash scripts/gained.sh" Bash "$WT"
# The base's tip holds these bytes, but the merge base does not: a copy the
# worker commits is still its own.
wcommit "$WT" copy scripts/gained.sh || exit 1
assert_defer "a committed copy of a script only the base's tip holds" "bash scripts/gained.sh" Bash "$WT"
# Regression only: a merge beside any trusted script defers by its shape.
assert_defer "shape: a merge and the run in one command" \
  "git merge -q --no-edit origin/main && bash scripts/gained.sh" Bash "$WT"
assert_defer "a fetch, which moves no merge base, and the run" \
  "git fetch -q origin && bash scripts/gained.sh" Bash "$WT"
wgit "$WT" merge -q --no-edit origin/main || exit 1
assert_allow "the base script, merged in" "bash scripts/gained.sh" Bash "$WT"
assert_defer "the worker's script after the merge" "bash scripts/act-merge.sh" Bash "$WT"

echo "### another branch's HEAD is not the base either"
corpus_git_env -C "$WT" checkout -q -b planwright/demo/task-2 || exit 1
printf '#!/bin/sh\ngh pr merge 1\n' >"$WT/scripts/side.sh"
wcommit "$WT" side scripts/side.sh || exit 1
assert_defer "a script committed on a side branch" "bash scripts/side.sh" Bash "$WT"
assert_allow "a base script on the side branch" "bash scripts/ok.sh" Bash "$WT"
corpus_git_env -C "$WT" checkout -q "$UB" || exit 1

echo "### a linter config and a declared command's file, committed by the worker"
assert_allow "control: the lint with no config" "markdownlint-cli2 --no-globs notes.md" Bash "$WT"
printf '{ "MD013": false }\n' >"$WT/.markdownlint.jsonc"
wcommit "$WT" lint .markdownlint.jsonc || exit 1
assert_defer "a config the worker committed" "markdownlint-cli2 --no-globs notes.md" Bash "$WT"
corpus_git_env -C "$WT" rm -q .markdownlint.jsonc && wgit "$WT" commit -q -m unlint || exit 1
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
ORPHAN=$(wgit "$WT" commit-tree -m orphan 4b825dc642cb6eb9a060e54bf8d69288fbee4904) \
  && corpus_git_env -C "$WT" update-ref refs/remotes/origin/orphan "$ORPHAN" || exit 1
under "$(record_with orphan pr_base=origin/orphan)"
assert_defer "a base with no commit in common" "bash scripts/ok.sh" Bash "$WT"
DUPBASE=$(record_with dupbase)
printf 'pr_base=origin/main\n' >>"$DUPBASE"
under "$DUPBASE"
assert_defer "a repeated pr_base" "bash scripts/ok.sh" Bash "$WT"

echo "### a record that names no usable worktree trusts no worker commit"
DUP=$(record_with dup)
printf 'worktree_root=%s\n' "$WT" >>"$DUP"
under "$DUP"
assert_defer "a repeated worktree_root: a committed script" "bash scripts/act-merge.sh" Bash "$WT"

echo "### a repository nested in the worktree answers to no base"
N=$WT/sub/nested
mkdir -p "$N/scripts"
printf '#!/bin/sh\ngh pr merge 1\n' >"$N/scripts/n.sh"
corpus_git_env init -q "$N" && wcommit "$N" nested scripts || exit 1
under "$REC"
assert_defer "a script a nested repository commits" "bash scripts/n.sh" Bash "$N"
corpus_git_env -C "$N" update-ref refs/remotes/origin/main HEAD || exit 1
assert_defer "a nested repository carrying its own base ref" "bash scripts/n.sh" Bash "$N"

echo "### checkouts beside the worktree keep their HEAD"
# A sibling whose path only shares the worktree's name as a prefix is not in it.
S=${WT}x
mkdir -p "$S/scripts"
printf '#!/bin/sh\nexit 0\n' >"$S/scripts/s.sh"
corpus_git_env init -q "$S" && wcommit "$S" sibling scripts || exit 1
assert_allow "a sibling checkout's committed script, held to its HEAD" "bash scripts/s.sh" Bash "$S"
# A planwright root that is a checkout outside the worktree, under a record.
C=$CORPUS_BOX/pwroot
mkdir -p "$C/scripts"
printf '#!/bin/sh\nexit 0\n' >"$C/scripts/plug.sh"
corpus_git_env init -q "$C" && wcommit "$C" root scripts || exit 1
printf '#!/bin/sh\ngh pr merge 1\n' >"$C/scripts/planted.sh"
HOOK_ENV+=("PLANWRIGHT_ROOT=$C")
assert_allow "a root checkout's committed script" "bash $C/scripts/plug.sh" Bash "$WT"
assert_defer "a script planted in that root" "bash $C/scripts/planted.sh" Bash "$WT"
# A planwright root that is the recorded worktree itself is held to the base.
under "$REC"
HOOK_ENV+=("PLANWRIGHT_ROOT=$WT")
assert_defer "the worktree as a planwright root: a committed script" \
  "bash $WT/scripts/act-merge.sh" Bash "$CORPUS_OUTSIDE"
assert_allow "the worktree as a planwright root: a base script" \
  "bash $WT/scripts/ok.sh" Bash "$CORPUS_OUTSIDE"

echo "### a record set but naming no usable worktree trusts nothing but the hook's own root"
# Such a session can still commit through the static allows, and the guard
# cannot place where: a shell sitting in a repository nested in the one it
# committed in would make the outer one look like a checkout elsewhere.
for r in "$DUP" "$STATE/missing.record" relative.record; do
  under "$r"
  HOOK_ENV+=("PLANWRIGHT_ROOT=$C")
  assert_defer "record $r: the session's own repository" "bash scripts/ok.sh" Bash "$WT"
  assert_defer "record $r: a root checkout elsewhere" "bash $C/scripts/plug.sh" Bash "$WT"
  under "$r"
  HOOK_ENV+=("PLANWRIGHT_ROOT=$WT")
  assert_defer "record $r: the worktree as a root, from a nested repository's directory" \
    "bash $WT/scripts/act-merge.sh" Bash "$N"
  assert_defer "record $r: the worktree as a root, from outside every checkout" \
    "bash $WT/scripts/act-merge.sh" Bash "$CORPUS_OUTSIDE"
done
under "$DUP"
assert_allow "the hook's own root keeps HEAD, so its step scripts still run" \
  "$REPO_ROOT/scripts/step-record.sh args-digest x" Bash "$WT"
under "$REC"
HOOK_ENV+=("PLANWRIGHT_ROOT=$C")
assert_allow "control: the root checkout elsewhere under a usable record" \
  "bash $C/scripts/plug.sh" Bash "$WT"
HOOK_ENV=()

finish_suite worker-command-guard-own-commit
