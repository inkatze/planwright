#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: spellings that hide a
# reserved act from a parser (quoting, expansions, wrappers, here-documents,
# aliases, configuration and state set earlier in the same command) must
# deny under the permissive policy values, and the routine commands a worker
# runs (heredoc commit messages and PR bodies, test brackets, sync helpers)
# must stay deferred. Split from tests/test-policy-guard.sh to keep each file
# inside the per-file time budget; the harness explains the sandbox.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

echo "# spellings that hide the act deny, under the permissive values"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow' 'protected_branches:'
NL_='
'
HIDDEN=(
  '"g"it push --force origin main' 'gi\t rebase origin/main' 'g""it push --force origin main'
  'x=ush; git p$x --force origin main' 'G=git; $G push --force origin main' 'git $SUB origin/main'
  'm=merge; gh pr $m 12' "git \"pu\\${NL_}sh\" --force origin main" "gh pr \"mer\\${NL_}ge\" 1"
  'echo "git push --force origin main" | bash' "cat <<EOF | bash${NL_}git push --force origin main${NL_}EOF"
  'echo push --force origin main | xargs git' '/usr/bin/env git push --force origin main'
  '/bin/bash -c "git push --force origin main"' 'time -p git push --force origin main'
  'coproc git push --force origin main' "python3 -c \"import os; os.system('git push --force origin main')\""
  '{fd}>/dev/null git push --force origin main'
  "x=\$(date) <<< y${NL_}git push --force origin main" "x=\$((1<<y))${NL_}git push --force origin main"
  'git -c push.default=matching push' 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.st GIT_CONFIG_VALUE_0=rebase git st main'
  "GIT_CONFIG_PARAMETERS=\"'alias.x=rebase'\" git x main" 'GIT_DIR=/tmp/x/.git git commit --amend --no-edit'
  'export GIT_DIR=/tmp/x/.git; git commit --amend --no-edit' 'git -c pull.rebase=true pull origin main'
  'git -c rebase.updateRefs=true rebase -i HEAD~3' 'git pull --reb origin main' 'git pull --no-rebase --rebase origin main'
  'git pull --rebase=false --rebase origin main' 'git rebase --ro' 'git rebase -i HEAD~3 --upd'
  'git config alias.x rebase && git x main' 'git config pull.rebase true && git pull origin main'
  'git checkout main && git push origin HEAD' 'git switch planwright/demo/task-2 && git commit --amend --no-edit'
  'git push origin HEAD && git commit --amend --no-edit' 'git fetch origin x:refs/remotes/origin/main && git merge origin/main'
  'git --attr-source HEAD push --force origin main' 'git REBASE origin/main' 'gh pr -R o/r merge 1' 'gh pr --repo o/r merge 1'
  "git rebase --exec=\"echo continue\" origin/main"
  "echo hi # \$(cat <<'X'${NL_}git push --force origin main${NL_}X${NL_})"
  'a=git; b=push; $a $b --force origin main' 'trap "git push --force origin main" EXIT'
  "declare -i x; x='a[\$(git push --force origin main)]'"
  'git merge origin/main && git rebase -i HEAD~3'
  'PROMPT_COMMAND="git push --force origin main"'
  "echo \"\$(cat <<-EOF${NL_}EOF${NL_}git push --force origin main${NL_}-EOF${NL_})\""
  "eval \"\$(cat <<'EOF'${NL_}git push --force origin main${NL_}EOF${NL_})\""
  "trap \"\$(cat <<'EOF'${NL_}git push --force origin main${NL_}EOF${NL_})\" EXIT"
  "declare -i x; x=\"a[\\\$(git push --force origin main)]\"" "let \"x=a[\\\$(git push --force origin main)]\""
  'a=gi; b=t; X=1 $a$b push --force origin main' 'a=gi; b=t; if $a$b push --force origin main; then :; fi'
  'a=git; b=push; /usr/bin/$a $b --force origin main' 'a=git; b=push; ${a:-/} $b --force origin main'
  "export BASH_ENV=\"\\\$(git push --force origin main)\"; bash -c true"
  "cat <<X${NL_}\$(git push --force origin main)${NL_}X"
)
for cmd in "${HIDDEN[@]}"; do
  pg worker "$cmd"
  expect deny "[worker] hidden: $(printf '%s' "$cmd" | tr '\n' ' ')"
done
for cmd in 'gh pr --repo o/r ready 1' 'gh pr -R o/r ready 1'; do
  pg tower "$cmd"
  expect deny "[tower] a --repo pair before the pr subcommand still reads as a flip: $cmd"
done
gitq -C "$UNIT" config alias.ch 'up'
gitq -C "$UNIT" config alias.up 'push --force origin main'
for cmd in 'git ch' 'git up'; do
  pg worker "$cmd"
  expect deny "[worker] an alias chain or an alias to a forced push denies: $cmd"
done
gitq -C "$UNIT" config alias.up ' push --force origin main'
pg worker 'git up'
expect deny "[worker] an alias value with leading blanks still reads its first word"
gitq -C "$UNIT" config alias.sync '!git up'
pg worker 'git sync'
expect deny "[worker] a shell alias reaching a reserved act through another alias denies"
gitq -C "$UNIT" config --unset alias.sync
gitq -C "$UNIT" config --unset alias.up
gitq -C "$UNIT" config --unset alias.ch

echo "# routine commands stay deferred"
ROUTINE=(
  "git commit -m \"\$(cat <<'EOF'${NL_}feat: guard git push --force spellings and gh api merges${NL_}${NL_}git rebase origin/main is denied.${NL_}EOF${NL_})\" && git push origin HEAD"
  "gh pr create --draft --title \"guard git push spellings\" --body \"\$(cat <<'EOF'${NL_}gh pr merge and gh api mergePullRequest are denied.${NL_}EOF${NL_})\""
  'git merge --help' 'git rebase --cont' 'git merge --ab' 'GIT_EDITOR=true git rebase --continue' 'git rebase -C 4 HEAD~2'
  'git branch --show-current && git push origin HEAD' 'git config --get user.name && git push origin HEAD'
  'git fetch origin && git merge origin/main' 'git add -A && git commit -m wip && git push origin HEAD'
  '"$P/scripts/converge-sync-main.sh"' 'cd "$WT" && mise run check'
  "git commit -m \"\$(cat <<EOF${NL_}docs: say why git rebase is refused${NL_}EOF${NL_})\""
  '[ -d .git ] && git status' '[[ -n "$x" ]] && git log --oneline -1' 'if [ -n "$x" ]; then git status; fi'
  "git commit -m 'refuse \`git rebase\` in workers'" 'for f in a b; do echo "$f"; done'
)
for cmd in "${ROUTINE[@]}"; do
  pg worker "$cmd"
  expect defer "[worker] routine: $(printf '%s' "$cmd" | head -1)"
done
pg tower 'git rebase --help'
expect defer "[tower] git rebase --help rewrites nothing"
pg worker "gh api graphql -f query=\"\$(cat <<'EOF'${NL_}mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}${NL_}EOF${NL_})\""
expect deny "[worker] a gh api query handed over a quoted heredoc is unreadable and denies"

no_gh_calls
finish
