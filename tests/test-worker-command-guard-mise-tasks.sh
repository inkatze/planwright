#!/bin/bash
# The worker command guard's own-branch arm and the mise task-file opt-in: a
# session record that carries `mise_task_edit=1` (written by the launcher for
# an opted-in launch, never read from config, the checkout or the environment)
# admits writes to mise.toml, .mise.toml, mise-tasks/ and .mise-tasks/ inside
# the worktree, and to nothing else the arm refuses. Without the field, or with
# any value but 1, or twice, the arm is the shipped one. The scratch zone never
# opens, and neither does a write outside the worktree.
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
OPT=$(record_with opt "own-branch scratch" mise_task_edit=1)
OPT_OB=$(record_with optob "own-branch" mise_task_edit=1)
OPT_SC=$(record_with optsc "scratch" mise_task_edit=1)
NOOPT=$(record_with noopt "own-branch scratch")
OPT_ZERO=$(record_with optzero "own-branch scratch" mise_task_edit=0)
OPT_WORD=$(record_with optword "own-branch scratch" mise_task_edit=yes)
OPT_DUP=$(record_with optdup "own-branch scratch" mise_task_edit=1 mise_task_edit=1)
OPT_BLANK=$(record_with optblank "own-branch scratch" mise_task_edit=)

mkdir -p "$WT/mise-tasks" "$WT/.mise-tasks/x" "$WT/tree-ok/mise-tasks" "$WT/tree-bad/mise-tasks" "$WT/sub" "$WT/mise"
: >"$WT/.mise.toml"
: >"$WT/tree-ok/mise-tasks/t"
: >"$WT/tree-ok/mise.toml"
: >"$WT/tree-bad/mise-tasks/t"
: >"$WT/tree-bad/mise.local.toml"
: >"$WT/sub/mise.toml"

OPEN_CMDS=(
  "echo x >> mise.toml"
  "touch .mise.toml"
  "mkdir -p mise-tasks"
  "echo x > mise-tasks/build"
  "touch .mise-tasks/x/y"
  "mkdir -p .mise-tasks/z"
  "touch sub/mise.toml"
  "echo x >> sub/mise.toml"
  "rm mise-tasks/build"
  "rm -r tree-ok"
  "cp f mise-tasks/copy"
  "mv notes.md mise-tasks/notes"
)
SHUT_CMDS=(
  "echo x >> mise.local.toml"
  "touch mise.test.toml"
  "touch .mise.local.toml"
  "touch mise.lock"
  "touch mise.local.lock"
  "touch .miserc.toml"
  "touch .miserc.local.toml"
  "mkdir -p mise/conf.d"
  "touch mise/config.toml"
  "mkdir -p mise/tasks/x"
  "mkdir -p .mise/tasks"
  "touch lefthook.yml"
  "touch .envrc"
  "touch .tool-versions"
  "touch .claude/x"
  "touch githooks/pre-commit"
  "echo x > .git"
  "rm -r tree-bad"
  "touch $OUT_DIR/mise.toml"
  "mkdir -p $OUT_DIR/mise-tasks"
  "cp f \$TMPDIR/mise.toml"
  "mkdir -p \$TMPDIR/mise-tasks"
  "touch \$TMPDIR/.mise.toml"
)

echo "### an opted-in record opens the four task-file names inside the worktree"
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

echo "### the opt-in needs the own-branch arm"
under "$OPT_OB"
assert_allow "own-branch only, opted in: touch mise.toml" "touch mise.toml" Bash "$WT"
under "$OPT_SC"
assert_defer "scratch only, opted in: no worktree write" "touch mise.toml" Bash "$WT"

echo "### a record without exactly one mise_task_edit=1 gets the shipped arm"
for r in "$NOOPT" "$OPT_ZERO" "$OPT_WORD" "$OPT_DUP" "$OPT_BLANK"; do
  under "$r"
  for c in "${OPEN_CMDS[@]}"; do
    assert_defer "[$(basename "$r")] shipped arm: $c" "$c" Bash "$WT"
  done
done

echo "### the opt-in is not read from the environment, the checkout or config"
under "$NOOPT"
HOOK_ENV+=("PLANWRIGHT_MISE_TASK_EDIT=1" "MISE_TASK_EDIT=1")
assert_defer "environment variables do not opt in" "touch mise.toml" Bash "$WT"
printf 'mise_task_edit=1\n' >"$WT/f.record"
printf 'mise_task_edit: true\n' >"$WT/.claude/planwright.local.yml"
under "$NOOPT"
assert_defer "a checkout file and a local config line do not opt in" "touch mise.toml" Bash "$WT"
rm -f "$WT/f.record" "$WT/.claude/planwright.local.yml"

finish_suite worker-command-guard-mise-tasks
