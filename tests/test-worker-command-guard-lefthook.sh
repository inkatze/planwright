#!/bin/bash
# The worker command guard's own-branch arm and the lefthook config opt-in: a
# session record that carries `lefthook_edit=1` (written by the launcher for an
# opted-in launch, never read from config, the checkout or the environment)
# admits writes to lefthook.<ext> files and the lefthook/ directory inside the
# worktree, and to nothing else the arm refuses: not the lefthook-local and
# dot-prefixed variants, not the mise task files, not the hooks directories or
# .git or .claude. Without the field, or with any value but 1, or twice, the arm
# is the shipped one. The scratch zone never opens, and neither does a write
# outside the worktree. The two opt-ins are independent and compose.
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
OUT_DIR=$CORPUS_OUTSIDE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}
# record_with <name> <policy> [<line>...]: the both-arms record with the policy
# replaced and the extra lines appended.
record_with() {
  local f=$STATE/$1.record
  shift
  {
    printf 'policy=%s\n' "$1"
    shift
    grep -v '^policy=' "$STATE/record.4"
    [ "$#" -eq 0 ] || printf '%s\n' "$@"
  } >"$f.tmp" && mv "$f.tmp" "$f"
  printf '%s\n' "$f"
}
OPT=$(record_with opt "own-branch scratch" lefthook_edit=1)
OPT_OB=$(record_with optob "own-branch" lefthook_edit=1)
OPT_SC=$(record_with optsc "scratch" lefthook_edit=1)
OPT_BOTH=$(record_with optboth "own-branch scratch" lefthook_edit=1 mise_task_edit=1)
OPT_MISE=$(record_with optmise "own-branch scratch" mise_task_edit=1)
NOOPT=$(record_with noopt "own-branch scratch")
OPT_ZERO=$(record_with optzero "own-branch scratch" lefthook_edit=0)
OPT_WORD=$(record_with optword "own-branch scratch" lefthook_edit=yes)
OPT_DUP=$(record_with optdup "own-branch scratch" lefthook_edit=1 lefthook_edit=1)
OPT_BLANK=$(record_with optblank "own-branch scratch" lefthook_edit=)

mkdir -p "$WT/lefthook" "$WT/sub" "$WT/tree-ok/lefthook" "$WT/tree-bad/lefthook" "$WT/.githooks" \
  "$WT/.lefthook" "$WT/.lefthook-local" "$WT/tree-mise" "$WT/tree-envrc" "$WT/tree-dot" "$WT/tree-scratch" "$WT/tree-clean"
: >"$WT/tree-clean/plain.txt"
: >"$WT/tree-mise/lefthook.yml"
: >"$WT/tree-mise/mise.toml"
: >"$WT/tree-envrc/lefthook.yml"
: >"$WT/tree-envrc/.envrc"
: >"$WT/tree-dot/lefthook.yml"
: >"$WT/tree-dot/.lefthook.yml"
: >"$WT/tree-scratch/lefthook.yml"
: >"$WT/lefthook.yml"
: >"$WT/lefthook/pre-commit.yml"
: >"$WT/sub/lefthook.yml"
: >"$WT/tree-ok/lefthook/t.yml"
: >"$WT/tree-ok/lefthook.yml"
: >"$WT/tree-bad/lefthook/t.yml"
: >"$WT/tree-bad/lefthook-local.yml"
mkdir -p "$WT/tree-link" "$SC/from-scratch"
ln -s "$OUT_DIR" "$WT/tree-link/lefthook"
ln -s "$OUT_DIR/x" "$WT/tree-link/lefthook.yml"
: >"$SC/from-scratch/lefthook.yml"

OPEN_CMDS=(
  "echo x >> lefthook.yml"
  "touch lefthook.yaml"
  "touch lefthook.json"
  "touch lefthook.toml"
  "mkdir -p lefthook"
  "echo x > lefthook/pre-commit.yml"
  "mkdir -p lefthook/extra"
  "touch lefthook/pre-commit.yml"
  "touch sub/lefthook.yml"
  "echo x >> sub/lefthook.yml"
  "rm lefthook.yml"
  "rm lefthook/pre-commit.yml"
  "rm -r tree-ok"
  "cp f lefthook.yml"
  "mv notes.md lefthook.yml"
  "touch LEFTHOOK.YML"
)
SHUT_CMDS=(
  "touch lefthook-local.yml"
  "touch lefthook-local.yaml"
  "touch .lefthook.yml"
  "touch .lefthook-local.yml"
  "mkdir -p .lefthook"
  "touch .lefthook/x.yml"
  "mkdir -p .lefthook-local"
  "touch mise.toml"
  "touch .mise.toml"
  "mkdir -p mise-tasks"
  "touch mise.local.toml"
  "touch .envrc"
  "touch .tool-versions"
  "touch .claude/x"
  "touch githooks/pre-commit"
  "mkdir -p githooks/x"
  "echo x > .git"
  "echo x >> .git/config"
  "rm -r tree-bad"
  "touch $OUT_DIR/lefthook.yml"
  "mkdir -p $OUT_DIR/lefthook"
  "cp f \$TMPDIR/lefthook.yml"
  "mkdir -p \$TMPDIR/lefthook"
  "touch \$TMPDIR/lefthook.yml"
  "touch Lefthook-Local.yml"
  "touch .LEFTHOOK.yml"
  "touch $CORPUS_BOX/main/lefthook.yml"
  "cd $CORPUS_BOX/main && touch lefthook.yml"
  "touch $CORPUS_BOX/other/lefthook.yml"
  "touch outlink/lefthook.yml"
  "touch sub/../lefthook.yml"
  "touch ../outside/lefthook.yml"
  "touch tree-link/lefthook/pre-commit.yml"
  "echo x > tree-link/lefthook.yml"
  "mv lefthook.yml lefthook-local.yml"
  "cp lefthook.yml .lefthook.yml"
  "mv lefthook .lefthook"
)

echo "### an opted-in record opens the lefthook config names inside the worktree"
under "$OPT"
for c in "${OPEN_CMDS[@]}"; do
  assert_allow "opt-in: $c" "$c" Bash "$WT"
done
echo "### and nothing else the arm refuses"
for c in "${SHUT_CMDS[@]}"; do
  assert_defer "opt-in still refuses: $c" "$c" Bash "$WT"
done
assert_allow "opt-in: a floor-clean read is unaffected" "git status" Bash "$WT"
assert_defer "opt-in: the floor still refuses a push" "git push origin HEAD:main" Bash "$WT"
assert_defer "opt-in: the floor still refuses a hook-skipping commit" "git commit --no-verify -m x" Bash "$WT"
assert_defer "opt-in, run from the primary checkout: touch lefthook.yml" "touch lefthook.yml" Bash "$CORPUS_BOX/main"
assert_defer "opt-in, run from a sibling repository: touch lefthook.yml" "touch lefthook.yml" Bash "$CORPUS_BOX/other"

echo "### the opt-in needs the own-branch arm"
under "$OPT_OB"
assert_allow "own-branch only, opted in: touch lefthook.yml" "touch lefthook.yml" Bash "$WT"
under "$OPT_SC"
assert_defer "scratch only, opted in: no worktree write" "touch lefthook.yml" Bash "$WT"

echo "### a record without exactly one lefthook_edit=1 gets the shipped arm"
for r in "$OPT_ZERO" "$OPT_WORD" "$OPT_DUP" "$OPT_BLANK"; do
  under "$r"
  for c in "echo x >> lefthook.yml" "mkdir -p lefthook" "touch sub/lefthook.yml" "rm -r tree-ok"; do
    assert_defer "[$(basename "$r")] shipped arm: $c" "$c" Bash "$WT"
  done
done
under "$NOOPT"
for c in "${OPEN_CMDS[@]}"; do
  assert_defer "no opt-in, shipped arm: $c" "$c" Bash "$WT"
done

echo "### the mise opt-in does not open lefthook names, nor this one the mise names"
under "$OPT_MISE"
for c in "touch lefthook.yml" "mkdir -p lefthook" "rm -r tree-ok"; do
  assert_defer "mise opt-in alone: $c" "$c" Bash "$WT"
done
under "$OPT"
for c in "rm -r tree-mise" "rm -r tree-envrc" "rm -r tree-dot"; do
  assert_defer "lefthook opt-in alone, a tree holding another excluded name: $c" "$c" Bash "$WT"
done
assert_defer "lefthook opt-in alone: touch mise.toml inside a nested directory" "touch sub/mise.toml" Bash "$WT"
echo "### an opt-in's names move only inside the worktree, never into scratch"
assert_defer "copy a tree holding lefthook.yml into scratch" "cp -r tree-scratch \$TMPDIR/copy" Bash "$WT"
assert_defer "move a tree holding lefthook.yml into scratch" "mv tree-scratch \$TMPDIR/moved" Bash "$WT"
assert_allow "copy a clean tree into scratch (the refusals above come from the tree's names)" "cp -r tree-clean \$TMPDIR/clean-copy" Bash "$WT"
assert_allow "move a clean tree into scratch" "mv tree-clean \$TMPDIR/clean-moved" Bash "$WT"
assert_allow "copy the same tree inside the worktree" "cp -r tree-scratch tree-scratch2" Bash "$WT"
assert_allow "move the same tree inside the worktree" "mv tree-scratch tree-moved" Bash "$WT"
assert_allow "copy a scratch tree holding lefthook.yml into the worktree" "cp -r \$TMPDIR/from-scratch from-scratch-copy" Bash "$WT"
echo "### the two opt-ins compose"
under "$OPT_BOTH"
for c in "touch lefthook.yml" "touch mise.toml" "mkdir -p mise-tasks" "mkdir -p lefthook"; do
  assert_allow "both opt-ins: $c" "$c" Bash "$WT"
done
for c in "touch lefthook-local.yml" "touch .lefthook.yml" "touch githooks/pre-commit" "touch mise.local.toml" "echo x > .git"; do
  assert_defer "both opt-ins still refuse: $c" "$c" Bash "$WT"
done

echo "### whichever directory core.hooksPath names stays closed, a dotted one included"
git -C "$WT" config core.hooksPath .githooks
under "$OPT_BOTH"
for c in "touch .githooks/pre-commit" "mkdir -p .githooks/x" "echo x > .githooks/pre-commit" "rm -r .githooks"; do
  assert_defer "hooks path .githooks, both opt-ins: $c" "$c" Bash "$WT"
done
assert_allow "hooks path .githooks, both opt-ins: lefthook.yml still opens" "touch lefthook.yml" Bash "$WT"
git -C "$WT" config core.hooksPath lefthook
for c in "touch lefthook/x.yml" "echo x > lefthook/pre-commit.yml" "rm lefthook/pre-commit.yml" "rm -r lefthook"; do
  assert_defer "a hooks path named like a lefthook directory stays closed: $c" "$c" Bash "$WT"
done
git -C "$WT" config core.hooksPath githooks

echo "### the opt-in is not read from the environment, the checkout or config"
under "$NOOPT"
HOOK_ENV+=("PLANWRIGHT_LEFTHOOK_EDIT=1" "LEFTHOOK_EDIT=1")
assert_defer "environment variables do not opt in" "touch lefthook.yml" Bash "$WT"
printf 'lefthook_edit=1\n' >"$WT/f.record"
printf 'lefthook_edit: true\n' >"$WT/.claude/planwright.local.yml"
under "$NOOPT"
assert_defer "a checkout file and a local config line do not opt in" "touch lefthook.yml" Bash "$WT"
rm -f "$WT/f.record" "$WT/.claude/planwright.local.yml"

finish_suite worker-command-guard-lefthook
