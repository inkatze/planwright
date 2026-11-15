#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the read-only shapes workers hit
# constantly (gh reads, plain reads under a resolved install root, a read-only
# MCP allow list) and the in-worktree in-place edit under the own-branch arm,
# each beside the write form that must keep deferring.
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
STATE=$CORPUS_BOX/state

echo "### read-only gh api: GET only"
assert_allow "gh api compare with -q" "gh api repos/o/r/compare/a...b -q '.files[].filename'" Bash "$WT"
assert_allow "gh api compare as a diff" "gh api repos/o/r/compare/a...b -H 'Accept: application/vnd.github.diff'" Bash "$WT"
assert_allow "gh api contents raw into grep" "gh api \"repos/o/r/contents/p/f.md?ref=abc\" -H 'Accept: application/vnd.github.raw' | grep -n x" Bash "$WT"
assert_allow "gh api contents raw into sed" "gh api \"repos/o/r/contents/p/f.md?ref=abc\" -H 'Accept: application/vnd.github.raw' | sed -n 1,20p" Bash "$WT"
assert_allow "gh api endpoint built from a variable" "P=skills/x/SKILL.md && gh api \"repos/o/r/contents/\$P?ref=abc\" -H 'Accept: application/vnd.github.raw' | grep -n x" Bash "$WT"
assert_allow "gh api --paginate --jq" "gh api repos/o/r/pulls --paginate --jq '.[].number'" Bash "$WT"
assert_allow "gh api explicit GET" "gh api -X GET repos/o/r/pulls" Bash "$WT"
assert_allow "gh api --method GET" "gh api --method GET repos/o/r/pulls" Bash "$WT"
assert_defer "gh api POST" "gh api -X POST repos/o/r/issues" Bash "$WT"
assert_defer "gh api PATCH" "gh api -X PATCH repos/o/r/pulls/1" Bash "$WT"
assert_defer "gh api DELETE" "gh api --method DELETE repos/o/r/git/refs/heads/x" Bash "$WT"
assert_defer "gh api -f field" "gh api repos/o/r/issues -f title=x" Bash "$WT"
assert_defer "gh api -F field" "gh api repos/o/r/issues -F body=@f" Bash "$WT"
assert_defer "gh api --field" "gh api repos/o/r/issues --field title=x" Bash "$WT"
assert_defer "gh api --raw-field" "gh api repos/o/r/issues --raw-field title=x" Bash "$WT"
assert_defer "gh api --input" "gh api repos/o/r/issues --input body.json" Bash "$WT"
assert_defer "gh api graphql mutation" "gh api graphql -f query='mutation { x }'" Bash "$WT"
assert_defer "gh api graphql with a field" "gh api graphql -F query=@q.graphql" Bash "$WT"
assert_defer "gh api variable command word" "\$GH api repos/o/r/pulls" Bash "$WT"

echo "### read-only gh subcommands, alone and in compound read lines"
assert_allow "gh search code" "gh search code 'foo repo:o/r' --json path" Bash "$WT"
assert_allow "gh search issues" "gh search issues foo --repo o/r" Bash "$WT"
assert_allow "gh search prs" "gh search prs foo --repo o/r" Bash "$WT"
assert_allow "gh pr view --json" "gh pr view 5 --json title,state" Bash "$WT"
assert_allow "gh pr checks" "gh pr checks 5" Bash "$WT"
assert_allow "gh pr diff" "gh pr diff 5" Bash "$WT"
assert_allow "gh pr list" "gh pr list --state open" Bash "$WT"
assert_allow "gh run view" "gh run view 12" Bash "$WT"
assert_allow "gh run list" "gh run list --limit 5" Bash "$WT"
assert_allow "gh issue view" "gh issue view 5" Bash "$WT"
assert_allow "gh issue list" "gh issue list" Bash "$WT"
assert_allow "gh repo view" "gh repo view o/r" Bash "$WT"
assert_allow "gh release view" "gh release view v1" Bash "$WT"
assert_allow "compound of reads" "gh pr view 5 --json state && gh pr checks 5" Bash "$WT"
assert_allow "reads piped into jq" "gh pr view 5 --json state | jq -r .state" Bash "$WT"
TMPC=$(cd -P /tmp && pwd -P)
assert_allow "cd /tmp then reads" "cd $TMPC; gh pr view 5 --json state; gh pr checks 5" Bash "$WT"
assert_defer "gh search with --web" "gh search code foo --web" Bash "$WT"
assert_defer "gh search commits unlisted" "gh search commits foo" Bash "$WT"
assert_defer "gh pr merge" "gh pr merge 5 --squash" Bash "$WT"
assert_defer "gh pr ready" "gh pr ready 5" Bash "$WT"
assert_defer "gh pr create" "gh pr create --title x" Bash "$WT"
assert_defer "gh pr comment" "gh pr comment 5 -b x" Bash "$WT"
assert_defer "gh pr edit" "gh pr edit 5 --title x" Bash "$WT"
assert_defer "gh issue create" "gh issue create -t x" Bash "$WT"
assert_defer "gh run rerun" "gh run rerun 12" Bash "$WT"
assert_defer "gh run cancel" "gh run cancel 12" Bash "$WT"
assert_defer "a read followed by a write" "gh pr view 5 && gh pr merge 5" Bash "$WT"

echo "### plain reads under a resolved install root"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
mkdir -p "$PLUGIN_ROOT/skills/x" "$PLUGIN_ROOT/doctrine"
: >"$PLUGIN_ROOT/skills/x/SKILL.md"
: >"$PLUGIN_ROOT/doctrine/rule.md"
assert_allow "cat a skill file" "cat $PLUGIN_ROOT/skills/x/SKILL.md" Bash "$PLUGIN_CWD"
assert_allow "grep in doctrine" "grep -n x $PLUGIN_ROOT/doctrine/rule.md" Bash "$PLUGIN_CWD"
assert_allow "ls a skills dir" "ls $PLUGIN_ROOT/skills" Bash "$PLUGIN_CWD"
assert_allow "sed -n a skill file" "sed -n 1,20p $PLUGIN_ROOT/skills/x/SKILL.md" Bash "$PLUGIN_CWD"
assert_allow "head a doctrine file" "head -n 5 $PLUGIN_ROOT/doctrine/rule.md" Bash "$PLUGIN_CWD"
assert_defer "a write redirect into the root" "echo x > $PLUGIN_ROOT/skills/x/SKILL.md" Bash "$PLUGIN_CWD"
assert_defer "sed -i in the root" "sed -i s/a/b/ $PLUGIN_ROOT/skills/x/SKILL.md" Bash "$PLUGIN_CWD"
assert_defer "rm in the root" "rm $PLUGIN_ROOT/skills/x/SKILL.md" Bash "$PLUGIN_CWD"
assert_defer "a write into a decoy sibling of the root" "echo x > $PLUGIN_DECOY/scripts/plug.sh" Bash "$PLUGIN_CWD"
HOOK_ENV=()

echo "### own-branch: in-place edit of a file in the worktree"
OB=$STATE/readonly-ob.record
{
  printf 'policy=own-branch\n'
  grep -v '^policy=' "$STATE/record.4"
} >"$OB"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$OB")
mkdir -p "$WT/.github/workflows"
: >"$WT/.github/workflows/ci.yml"
assert_allow "sed -i a tracked file" "sed -i s/a/b/ f" Bash "$WT"
# BSD sed reads the file after a bare -i as the script, so a path that is not a
# read-only sed script defers there by design; GNU sed does not.
case $OSTYPE in
  linux*) assert_allow "sed -i a workflow file" "sed -i s/a/b/ .github/workflows/ci.yml" Bash "$WT" ;;
  *) assert_defer "sed -i a workflow file (BSD sed reads the path as a script)" "sed -i s/a/b/ .github/workflows/ci.yml" Bash "$WT" ;;
esac
assert_allow "perl -pi a tracked file" "perl -pi -e 's/a/b/' f" Bash "$WT"
assert_defer "sed -i a file in .git" "sed -i s/a/b/ .git/config" Bash "$WT"
assert_defer "sed -i a hook" "sed -i s/a/b/ githooks/pre-commit" Bash "$WT"
assert_defer "sed -i under .claude" "sed -i s/a/b/ .claude/settings.json" Bash "$WT"
assert_defer "sed -i the mise config" "sed -i s/a/b/ mise.toml" Bash "$WT"
assert_defer "sed -i outside the worktree" "sed -i s/a/b/ $CORPUS_OUTSIDE/f" Bash "$WT"
assert_defer "perl -pi a hook" "perl -pi -e 's/a/b/' githooks/pre-commit" Bash "$WT"
assert_defer "perl -pi with a code-running program" "perl -pi -e 'system(\"x\")' f" Bash "$WT"
HOOK_ENV=()

echo "### the same reads from a worker under a policy arm, root named by a variable or glob"
IR=$SANDBOX/home/.claude/plugins/cache/planwright/planwright/0.74.0
mkdir -p "$IR/scripts" "$IR/skills/x" "$IR/doctrine"
: >"$IR/skills/x/SKILL.md"
: >"$IR/doctrine/rule.md"
HOOK_ENV=("PLANWRIGHT_ROOT=$IR" "GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$OB")
assert_allow "own-branch: cat under the installed root" "cat $IR/skills/x/SKILL.md" Bash "$WT"
assert_allow "own-branch: grep under the installed root" "grep -n x $IR/doctrine/rule.md" Bash "$WT"
assert_allow "own-branch: grep -r under the installed root" "grep -rn x $IR/doctrine" Bash "$WT"
assert_allow "own-branch: ls under the installed root" "ls $IR/skills" Bash "$WT"
assert_allow "own-branch: sed -n under the installed root" "sed -n 1,5p $IR/skills/x/SKILL.md" Bash "$WT"
assert_allow "own-branch: head under the installed root" "head -n 5 $IR/doctrine/rule.md" Bash "$WT"
assert_allow "own-branch: a glob under the installed root" "cat $IR/skills/*/SKILL.md" Bash "$WT"
assert_allow "own-branch: root held in a variable" "R=$IR && cat \$R/skills/x/SKILL.md" Bash "$WT"
assert_allow "own-branch: root variable, grep" "R=$IR && grep -n x \$R/doctrine/rule.md" Bash "$WT"
assert_defer "own-branch: a write redirect into the root" "echo x > $IR/skills/x/SKILL.md" Bash "$WT"
assert_defer "own-branch: sed -i in the root" "sed -i s/a/b/ $IR/skills/x/SKILL.md" Bash "$WT"
assert_defer "own-branch: rm in the root" "rm $IR/skills/x/SKILL.md" Bash "$WT"
HOOK_ENV=()

echo "### perl -pi: a lone literal substitution, own-branch only"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$OB")
assert_allow "perl -pi with a | delimiter" "perl -pi -e 's|a|b|g' f" Bash "$WT"
assert_allow "perl -i -pe form" "perl -i -pe 's/a/b/' f" Bash "$WT"
assert_allow "perl -pi with a backreference" "perl -pi -e 's/(a)/<\$1>/' f" Bash "$WT"
assert_defer "perl -pi with the e flag" "perl -pi -e 's/a/b/e' f" Bash "$WT"
assert_defer "perl -pi with a variable in the replacement" "perl -pi -e 's/a/\$x/' f" Bash "$WT"
assert_defer "perl -pi with an array interpolation" "perl -pi -e 's/a/@x/' f" Bash "$WT"
assert_defer "perl -pi with a code block" "perl -pi -e 's/(?{ system(1) })/b/' f" Bash "$WT"
assert_defer "perl -pi with a backtick" "perl -pi -e 's/a/\`id\`/' f" Bash "$WT"
assert_defer "perl -pi with a backup suffix" "perl -pi.bak -e 's/a/b/' f" Bash "$WT"
assert_defer "perl -pi with two statements" "perl -pi -e 's/a/b/;system(1)' f" Bash "$WT"
assert_defer "perl -e alone" "perl -e 's/a/b/' f" Bash "$WT"
assert_defer "perl running a script" "perl x.pl" Bash "$WT"
assert_defer "perl -pi with no file" "perl -pi -e 's/a/b/'" Bash "$WT"
HOOK_ENV=()
assert_defer "perl -pi without the own-branch arm" "perl -pi -e 's/a/b/' f" Bash "$WT"

echo "### gh api: only a literal GET spells the method"
assert_allow "gh api --method=GET" "gh api --method=GET repos/o/r/pulls" Bash "$WT"
assert_defer "gh api -X with no value" "gh api repos/o/r/pulls -X" Bash "$WT"
assert_defer "gh api -X GET then a field" "gh api -X GET repos/o/r/issues -f title=x" Bash "$WT"
assert_defer "gh api -X GET then --input" "gh api -X GET repos/o/r/issues --input f" Bash "$WT"
assert_defer "gh api -X GET, later -X POST" "gh api -X GET -X POST repos/o/r/issues" Bash "$WT"
assert_defer "gh api -X from a variable" "gh api -X \$M repos/o/r/issues" Bash "$WT"
assert_defer "gh api -X GETX" "gh api -X GETX repos/o/r/issues" Bash "$WT"
assert_defer "gh api --method=POST" "gh api --method=POST repos/o/r/issues" Bash "$WT"
assert_defer "gh api -X PUT" "gh api -X PUT repos/o/r/pulls/1/merge" Bash "$WT"
assert_defer "gh api bundled -iX POST" "gh api -iX POST repos/o/r/issues" Bash "$WT"

echo "### cd outside the worktree: only pure reads may follow"
SBXP=$(cd -P "$SANDBOX" && pwd -P)
OUTD=$SBXP/install/outside
mkdir -p "$OUTD/sub"
: >"$OUTD/f"
ln -sf /tmp "$SBXP/outlink"
assert_defer "cd outside in an && chain stays deferred" "cd $OUTD && cat f && ls" Bash "$WT"
assert_allow "cd outside with ;, then reads" "cd $OUTD; cat f; ls" Bash "$WT"
assert_allow "cd outside, then a gh read" "cd $OUTD; gh pr view 5 --json state" Bash "$WT"
assert_allow "cd outside, then a stderr redirect to /dev/null" "cd $OUTD; cat f 2>/dev/null" Bash "$WT"
assert_defer "cd outside, then rm" "cd $OUTD && rm f" Bash "$WT"
assert_defer "cd outside, then touch" "cd $OUTD; touch f" Bash "$WT"
assert_defer "cd outside, then a file redirect" "cd $OUTD; cat f > out" Bash "$WT"
assert_defer "cd outside, then an echo redirect" "cd $OUTD; echo x > out" Bash "$WT"
assert_defer "cd outside, then git" "cd $OUTD; git status" Bash "$WT"
assert_defer "cd outside, then a repo script" "cd $OUTD; ./scripts/ok.sh" Bash "$WT"
assert_defer "cd outside, then sed -i" "cd $OUTD; sed -i s/a/b/ f" Bash "$WT"
assert_defer "cd outside, then mkdir" "cd $OUTD; mkdir z" Bash "$WT"
assert_defer "cd outside, then a relative cd" "cd $OUTD; cd sub; rm x" Bash "$WT"
assert_defer "cd outside, then bash" "cd $OUTD; bash x.sh" Bash "$WT"
assert_defer "cd outside, then a substitution that writes" "cd $OUTD; echo \$(touch z)" Bash "$WT"
assert_defer "cd outside inside a loop" "for d in a; do cd $OUTD; rm x; done" Bash "$WT"
assert_defer "cd into /proc" "cd /proc/self; cat environ" Bash "$WT"
assert_defer "cd into /dev" "cd /dev; ls" Bash "$WT"
assert_defer "cd through a symlink" "cd $SBXP/outlink; ls" Bash "$WT"
assert_defer "cd with a .. component" "cd $OUTD/../outside; ls" Bash "$WT"
assert_defer "cd to a missing directory" "cd $OUTD/nope; ls" Bash "$WT"
assert_defer "cd to a variable" "cd \$D; ls" Bash "$WT"
assert_defer "cd with no operand" "cd; ls" Bash "$WT"
assert_defer "cd outside in a subshell" "(cd $OUTD; ls)" Bash "$WT"
assert_defer "cd outside after a pipe" "ls | cd $OUTD" Bash "$WT"

finish_suite "worker-command-guard readonly"
