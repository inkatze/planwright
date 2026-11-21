#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the session's own unit acts the
# floor otherwise reserves, approved under the session record whatever its
# policy: a step-context export pinned to its own worktree, a body edit of
# its own open pull request from a file in its own scratch root, and a plain
# push of its own unit branch to origin. Every near spelling still defers.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

B=planwright/flight/demo-0123abcd
OTHER_B=planwright/flight/other-0123abcd
# The record's paths are canonical, as the launcher writes them (macOS's
# /tmp is a link).
CS=$(cd "$SANDBOX" && pwd -P)
WT="$CS/units/own"
OTHER_WT="$CS/units/other"
SCR="$CS/scratch/own"
OUT_DIR="$CS/elsewhere"
STUB="$CS/stub-bin"
mkdir -p "$WT/sub" "$OTHER_WT" "$SCR" "$OUT_DIR" "$STUB" "$CS/records" "$CS/no-home"
# A real repository: a `cd` is approved only where git places the directory
# in the session's own one.
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git init -q "$WT" || exit 1
: >"$OTHER_WT/.git"
printf 'body\n' >"$SCR/body.md"
printf 'body\n' >"$WT/body.md"
printf 'body\n' >"$OUT_DIR/body.md"
mkdir -p "$SCR/dir.md"
ln -s "$OUT_DIR/body.md" "$SCR/link.md"
SREC="$PLUGIN_ROOT/scripts/step-record.sh"
SRUN="$PLUGIN_ROOT/scripts/step-run.sh"
: >"$SREC"
: >"$SRUN"

# record <file> [policy] [unit branch] [scratch root] [audit home]: a session
# record as the launcher writes it, with an audit home of its own unless the
# fifth argument names another (empty: none).
record() {
  mkdir -p -- "$1.audit"
  printf '%s\n' "policy=${2-}" "unit_branch=${3-$B}" "worktree_root=$WT" "pr_base=origin/main" \
    "worker_base_merge=allow" "scratch_root=${4-$SCR}" "audit_log_home=${5-$(cd -P -- "$1.audit" && pwd -P)}" >"$1"
}
REC="$CS/records/own.record"
record "$REC"

# The forge stand-in: `gh pr view <n> --json ...` answers from a table keyed
# on the number; every call is logged, so a fixture can show the guard only
# ever reads.
cat >"$STUB/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$SANDBOX/gh.log"
[ "\$1 \$2" = "pr view" ] || exit 1
case \$3 in
  12) printf '%s\n' '{"headRefName":"$B","isCrossRepository":false,"state":"OPEN"}' ;;
  13) printf '%s\n' '{"headRefName":"$OTHER_B","isCrossRepository":false,"state":"OPEN"}' ;;
  14) printf '%s\n' '{"headRefName":"$B","isCrossRepository":true,"state":"OPEN"}' ;;
  15) printf '%s\n' '{"headRefName":"$B","isCrossRepository":false,"state":"MERGED"}' ;;
  16) printf '%s\n' 'not json' ;;
  17) sleep 30 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
USE_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC" "PATH=$STUB:$PATH")
HOOK_ENV=("${USE_ENV[@]}")

echo "### (a) the step-context export, pinned to the session's own worktree"
CTX="PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_BRANCH=$B PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE=$WT"
assert_allow "export of the step context, then step-record.sh write" \
  "export $CTX && $SREC write --run 000001 --point pre-pr --step x --outcome passed" Bash "$WT"
assert_allow "the shape a worker stalled on: tracked root, export, writes, audit, rc echo" \
  "S=$PLUGIN_ROOT/scripts && export $CTX PLANWRIGHT_STEP_SPEC= PLANWRIGHT_STEP_TASK_IDS= PLANWRIGHT_STEP_PR_NUMBER=268 && \$S/step-record.sh write --run 000003 --point post-pr --step bot-review --outcome passed && \$S/step-record.sh write --completion --run 000003 --point post-pr && \$S/step-run.sh audit --through post-pr --base origin/main; echo rc=\$?" Bash "$WT"
assert_allow "export without a worktree field, then step-run.sh" "export PLANWRIGHT_STEP_BRANCH=$B && $SRUN audit --through pre-pr" Bash "$WT"
assert_allow "export, then step-run.sh resolve" "export $CTX && $SRUN resolve --run 000001 pre-pr --unattended" Bash "$WT"
assert_allow "from a subdirectory of the worktree" "export $CTX && $SREC new-run" Bash "$WT/sub"
assert_defer "another worker's run store" "export PLANWRIGHT_STEP_WORKTREE=$OTHER_WT && $SREC write --run 1" Bash "$WT"
assert_defer "a worktree spelled through a dot-dot" "export PLANWRIGHT_STEP_WORKTREE=$WT/../other && $SREC write --run 1" Bash "$WT"
assert_defer "a relative worktree" "export PLANWRIGHT_STEP_WORKTREE=. && $SREC write --run 1" Bash "$WT"
assert_defer "an empty worktree" "export PLANWRIGHT_STEP_WORKTREE= && $SREC write --run 1" Bash "$WT"
assert_defer "a session sitting in another worktree" "export $CTX && $SREC write --run 1" Bash "$OTHER_WT"
assert_defer "a non-step name" "export FOO=1 && $SREC write --run 1" Bash "$WT"
assert_defer "PATH beside the step names" "export $CTX PATH=/tmp && $SREC write --run 1" Bash "$WT"
assert_defer "a misspelled step name" "export PLANWRIGHT_STEP_BRANC=x && $SREC write --run 1" Bash "$WT"
assert_defer "an invalid unit kind" "export PLANWRIGHT_STEP_UNIT_KIND=evil && $SREC write --run 1" Bash "$WT"
assert_defer "a variable in a value" "export PLANWRIGHT_STEP_BRANCH=\$B && $SREC write --run 1" Bash "$WT"
assert_defer "a substitution in a value" "export PLANWRIGHT_STEP_BRANCH=\$(id) && $SREC write --run 1" Bash "$WT"
assert_defer "a quoted value" "export PLANWRIGHT_STEP_BRANCH='$B' && $SREC write --run 1" Bash "$WT"
assert_defer "a glob in a value" "export PLANWRIGHT_STEP_BRANCH=* && $SREC write --run 1" Bash "$WT"
assert_defer "export -n" "export -n PLANWRIGHT_STEP_BRANCH && $SREC write --run 1" Bash "$WT"
assert_defer "export -f" "export -f PLANWRIGHT_STEP_BRANCH && $SREC write --run 1" Bash "$WT"
assert_defer "a bare export" "export && $SREC write --run 1" Bash "$WT"
assert_defer "an export redirected to a file" "export $CTX > $WT/out && $SREC write --run 1" Bash "$WT"
assert_defer "an export inside fish -c" "fish -c 'export $CTX'" Bash "$WT"
assert_defer "an export followed by a command no shape approves" "export $CTX && rm -rf $OTHER_WT" Bash "$WT"

echo "### (b) gh pr edit <n> --body-file <file>, the session's own open PR"
: >"$SANDBOX/gh.log"
assert_allow "the own PR, a body file in the scratch root" "gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_allow "the body file named through a tracked assignment" "D=$SCR && gh pr edit 12 --body-file \$D/body.md" Bash "$WT"
assert_allow "chained after a step write" "$SREC write --run 1 && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}" "TMPDIR=$SCR")
assert_allow "the body file through the recorded \$TMPDIR, under the empty policy" "gh pr edit 12 --body-file \$TMPDIR/body.md" Bash "$WT"
assert_allow "the body file through \${TMPDIR}" "gh pr edit 12 --body-file \${TMPDIR}/body.md" Bash "$WT"
assert_defer "a dot-dot out of \$TMPDIR" "gh pr edit 12 --body-file \$TMPDIR/../../elsewhere/body.md" Bash "$WT"
assert_defer "a quoted \$TMPDIR" "gh pr edit 12 --body-file \"\$TMPDIR/body.md\"" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}" "TMPDIR=$OUT_DIR")
assert_defer "\$TMPDIR when the inherited TMPDIR is not the recorded root" "gh pr edit 12 --body-file \$TMPDIR/body.md" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}")
if grep -q 'edit' "$SANDBOX/gh.log"; then
  fail "the guard ran a gh write: $(cat "$SANDBOX/gh.log")"
else
  pass "the guard only reads the PR: every gh call it made is a view"
fi
assert_defer "another PR number" "gh pr edit 13 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a cross-repository PR on the same branch name" "gh pr edit 14 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a PR that is not open" "gh pr edit 15 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a forge answer that is not JSON" "gh pr edit 16 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a PR the forge cannot read" "gh pr edit 99 --body-file $SCR/body.md" Bash "$WT"
ou_t0=$(date +%s)
assert_defer "a forge read that hangs" "gh pr edit 17 --body-file $SCR/body.md" Bash "$WT"
if [ $(($(date +%s) - ou_t0)) -lt 25 ]; then
  pass "and the hung read is cut at its bound"
else
  fail "the hung forge read was not bounded"
fi
assert_defer "a number with a leading zero" "gh pr edit 012 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a number given as #12" "gh pr edit '#12' --body-file $SCR/body.md" Bash "$WT"
assert_defer "a PR named by URL" "gh pr edit https://github.com/o/r/pull/12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a PR named by branch" "gh pr edit $B --body-file $SCR/body.md" Bash "$WT"
assert_defer "no number" "gh pr edit --body-file $SCR/body.md" Bash "$WT"
assert_defer "the flags reordered" "gh pr edit --body-file $SCR/body.md 12" Bash "$WT"
assert_defer "--repo" "gh pr edit 12 --repo o/r --body-file $SCR/body.md" Bash "$WT"
assert_defer "--title" "gh pr edit 12 --body-file $SCR/body.md --title x" Bash "$WT"
assert_defer "--add-label" "gh pr edit 12 --body-file $SCR/body.md --add-label x" Bash "$WT"
assert_defer "--base" "gh pr edit 12 --body-file $SCR/body.md --base main" Bash "$WT"
assert_defer "--body" "gh pr edit 12 --body x" Bash "$WT"
assert_defer "-F" "gh pr edit 12 -F $SCR/body.md" Bash "$WT"
assert_defer "--body-file=<file>" "gh pr edit 12 --body-file=$SCR/body.md" Bash "$WT"
assert_defer "a body read from stdin" "gh pr edit 12 --body-file -" Bash "$WT"
assert_defer "a body file in the worktree" "gh pr edit 12 --body-file $WT/body.md" Bash "$WT"
assert_defer "a body file elsewhere" "gh pr edit 12 --body-file $OUT_DIR/body.md" Bash "$WT"
assert_defer "a secret as the body" "gh pr edit 12 --body-file $HOME/.ssh/id_rsa" Bash "$WT"
assert_defer "a symlink in the scratch root pointing out" "gh pr edit 12 --body-file $SCR/link.md" Bash "$WT"
assert_defer "a dot-dot out of the scratch root" "gh pr edit 12 --body-file $SCR/../../elsewhere/body.md" Bash "$WT"
assert_defer "a directory" "gh pr edit 12 --body-file $SCR/dir.md" Bash "$WT"
assert_defer "a missing file" "gh pr edit 12 --body-file $SCR/absent.md" Bash "$WT"
assert_defer "a relative body file" "gh pr edit 12 --body-file body.md" Bash "$SCR"
assert_defer "a quoted body file" "gh pr edit 12 --body-file '$SCR/body.md'" Bash "$WT"
assert_defer "a session sitting outside its worktree" "gh pr edit 12 --body-file $SCR/body.md" Bash "$OUT_DIR"
assert_defer "a merge smuggled after it" "gh pr edit 12 --body-file $SCR/body.md && gh pr merge 12" Bash "$WT"
assert_defer "a ready flip smuggled after it" "gh pr edit 12 --body-file $SCR/body.md; gh pr ready 12" Bash "$WT"
assert_defer "inside a substitution" "echo \$(gh pr edit 12 --body-file $SCR/body.md)" Bash "$WT"
assert_defer "inside fish -c" "fish -c 'gh pr edit 12 --body-file $SCR/body.md'" Bash "$WT"
assert_defer "a leading assignment" "GH_REPO=o/r gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "gh by path" "$STUB/gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"

echo "### (c) git push origin <own branch>"
assert_allow "the own branch" "git push origin $B" Bash "$WT"
assert_allow "the own branch's explicit refspec" "git push origin $B:$B" Bash "$WT"
assert_allow "after a cd into the worktree" "cd $WT && git push origin $B" Bash "$WT/sub"
assert_allow "chained after a read" "git status && git push origin $B" Bash "$WT"
assert_defer "another branch" "git push origin $OTHER_B" Bash "$WT"
assert_defer "the own branch onto another" "git push origin $B:$OTHER_B" Bash "$WT"
assert_defer "another branch onto the own" "git push origin $OTHER_B:$B" Bash "$WT"
assert_defer "HEAD onto the own branch" "git push origin HEAD:$B" Bash "$WT"
assert_defer "main" "git push origin main" Bash "$WT"
assert_defer "the own branch onto main" "git push origin $B:main" Bash "$WT"
assert_defer "refs/heads/ spelling" "git push origin $B:refs/heads/$B" Bash "$WT"
assert_defer "--force" "git push --force origin $B" Bash "$WT"
assert_defer "--force after the branch" "git push origin $B --force" Bash "$WT"
assert_defer "-f" "git push -f origin $B" Bash "$WT"
assert_defer "--force-with-lease" "git push --force-with-lease origin $B" Bash "$WT"
assert_defer "--force-with-lease=<ref>:<sha>" "git push --force-with-lease=$B:abc123 origin $B" Bash "$WT"
assert_defer "--force-if-includes" "git push --force-if-includes origin $B" Bash "$WT"
assert_defer "a + refspec" "git push origin +$B" Bash "$WT"
assert_defer "a + refspec onto the own branch" "git push origin +$B:$B" Bash "$WT"
assert_defer "-d" "git push -d origin $B" Bash "$WT"
assert_defer "--delete" "git push origin --delete $B" Bash "$WT"
assert_defer "a delete refspec" "git push origin :$B" Bash "$WT"
assert_defer "a different remote" "git push upstream $B" Bash "$WT"
assert_defer "a remote URL" "git push https://example.invalid/r.git $B" Bash "$WT"
assert_defer "-u" "git push -u origin $B" Bash "$WT"
assert_defer "--no-verify" "git push --no-verify origin $B" Bash "$WT"
assert_defer "--tags" "git push origin $B --tags" Bash "$WT"
assert_defer "--dry-run" "git push --dry-run origin $B" Bash "$WT"
assert_defer "a push option" "git push -o ci.skip origin $B" Bash "$WT"
assert_defer "--receive-pack" "git push --receive-pack=x origin $B" Bash "$WT"
assert_defer "two refspecs" "git push origin $B $OTHER_B" Bash "$WT"
assert_defer "no refspec" "git push origin" Bash "$WT"
assert_defer "a bare push" "git push" Bash "$WT"
assert_defer "git -C" "git -C $WT push origin $B" Bash "$WT"
assert_defer "git -c" "git -c push.default=matching push origin $B" Bash "$WT"
assert_defer "a quoted branch" "git push origin '$B'" Bash "$WT"
assert_defer "the branch through a variable" "R=$B && git push origin \$R" Bash "$WT"
assert_defer "a leading assignment" "GIT_DIR=$OTHER_WT/.git git push origin $B" Bash "$WT"
assert_defer "main smuggled after it" "git push origin $B && git push origin main" Bash "$WT"
assert_defer "a force smuggled after a separator" "git push origin $B; git push --force origin $B" Bash "$WT"
assert_defer "a pipe into a shell" "git push origin $B | sh" Bash "$WT"
assert_defer "a redirect" "git push origin $B > $WT/out" Bash "$WT"
assert_defer "backgrounded with a write after" "git push origin $B & rm -rf $OTHER_WT" Bash "$WT"
assert_defer "inside a substitution" "echo \$(git push origin $B)" Bash "$WT"
assert_defer "inside fish -c" "fish -c 'git push origin $B'" Bash "$WT"
assert_defer "inside bash -c" "bash -c 'git push origin $B'" Bash "$WT"
assert_defer "a session sitting in another worktree" "git push origin $B" Bash "$OTHER_WT"
assert_defer "a cd out of the worktree first" "cd $OTHER_WT && git push origin $B" Bash "$WT"

echo "### the act stands at the top level of the session's own repository"
# A nested repository, and a directory whose .git points at another one, lie
# under the worktree path but are other repositories.
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git init -q "$WT/nested" || exit 1
mkdir -p "$WT/pointer"
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git init -q "$CS/foreign" || exit 1
printf 'gitdir: %s\n' "$CS/foreign/.git" >"$WT/pointer/.git"
assert_defer "a push from a nested repository" "git push origin $B" Bash "$WT/nested"
assert_defer "a body edit from a nested repository" "gh pr edit 12 --body-file $SCR/body.md" Bash "$WT/nested"
assert_defer "an export from a nested repository" "export $CTX && $SREC write --run 1" Bash "$WT/nested"
assert_defer "a push from a gitdir pointer to another repository" "git push origin $B" Bash "$WT/pointer"
# The nested check runs no git there: a repository whose config would run a
# program on any git read is never read.
mkdir -p "$WT/planted/sub"
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git init -q "$WT/planted" || exit 1
printf '#!/bin/sh\n: >"%s/planted-ran"\n' "$CS" >"$CS/planted.sh"
chmod +x "$CS/planted.sh"
printf '[core]\n\tfsmonitor = %s\n[alias]\n\trev-parse = !%s\n' "$CS/planted.sh" "$CS/planted.sh" >>"$WT/planted/.git/config"
assert_defer "a push from inside a planted nested repository" "git push origin $B" Bash "$WT/planted/sub"
if [ -e "$CS/planted-ran" ]; then
  fail "the nested-repository check ran the planted repository's program"
else
  pass "the nested-repository check runs no git in the planted repository"
fi
assert_defer "inside a while loop" "while true; do git push origin $B; done" Bash "$WT"
assert_defer "inside a for loop" "for x in a; do git push origin $B; done" Bash "$WT"
assert_defer "inside an if body" "if git status; then git push origin $B; fi" Bash "$WT"
assert_defer "inside a case body" "case x in x) git push origin $B ;; esac" Bash "$WT"
assert_defer "after ||" "git status || git push origin $B" Bash "$WT"
assert_defer "after || and a later &&" "git status || git status && git push origin $B" Bash "$WT"
assert_defer "after || over a line break" "git status ||
git status && git push origin $B" Bash "$WT"
assert_allow "after a list ended by ; that held ||" "git status || git status; git push origin $B" Bash "$WT"
assert_defer "piped into a reader" "git push origin $B | cat" Bash "$WT"
assert_defer "at the end of a pipeline" "git status | git push origin $B" Bash "$WT"
assert_defer "at the end of a pipeline over a line break" "git status |
git push origin $B" Bash "$WT"
assert_defer "at the end of a chained pipeline over a line break" "git status && git status |
git push origin $B" Bash "$WT"
assert_defer "at the end of a pipeline over two line breaks" "git status |

git push origin $B" Bash "$WT"
assert_allow "after a pipeline the line break ends (control)" "git status | cat
git push origin $B" Bash "$WT"
assert_defer "at the end of a pipeline a loop opens, over a line break" "while false; do git status; done |
git push origin $B" Bash "$WT"
assert_defer "backgrounded" "git push origin $B &" Bash "$WT"
assert_defer "a body edit backgrounded" "gh pr edit 12 --body-file $SCR/body.md & git status" Bash "$WT"
assert_defer "an export inside a loop" "for x in a; do export $CTX; done && $SREC write --run 1" Bash "$WT"
# A trailing `&` backgrounds the whole and-or list since the last top-level
# `;` or newline, so an act earlier in that list is backgrounded too.
assert_defer "a list a later & backgrounds, after &&" "git push origin $B && git status &" Bash "$WT"
assert_defer "a list a later & backgrounds, after ||" "git push origin $B || git status &" Bash "$WT"
assert_defer "a list a later & backgrounds, through a pipeline" "git push origin $B && git status | cat &" Bash "$WT"
assert_defer "a list a later & backgrounds, with more after it" "git push origin $B && git status & git log" Bash "$WT"
assert_defer "a list a later & backgrounds, through a loop" "git push origin $B && for x in a; do git status; done &" Bash "$WT"
assert_defer "a list a later & backgrounds, over a line break" "git push origin $B &&
git status &" Bash "$WT"
assert_defer "a body edit in a list a later & backgrounds" "gh pr edit 12 --body-file $SCR/body.md && git status &" Bash "$WT"
assert_defer "an export in a list a later & backgrounds" "export $CTX && $SREC new-run &" Bash "$WT"
assert_allow "a list ended by ; before a later background job" "git push origin $B; git status &" Bash "$WT"
assert_allow "a list ended by a line break before a later background job" "git push origin $B
git status &" Bash "$WT"
assert_allow "followed by a read after ;" "git push origin $B; git status" Bash "$WT"
assert_allow "followed by || on its failure" "git push origin $B || git status" Bash "$WT"

echo "### an exported step name keeps its checked value"
assert_defer "a re-assignment after the export" \
  "export PLANWRIGHT_STEP_WORKTREE=$WT && PLANWRIGHT_STEP_WORKTREE=$OTHER_WT && $SREC write --run 1" Bash "$WT"
assert_defer "a re-assignment of another exported name" \
  "export PLANWRIGHT_STEP_BRANCH=$B && PLANWRIGHT_STEP_BRANCH=x; $SREC write --run 1" Bash "$WT"
assert_defer "a read into an exported name" \
  "export PLANWRIGHT_STEP_WORKTREE=$WT && read -r PLANWRIGHT_STEP_WORKTREE && $SREC write --run 1" Bash "$WT"
for ou_setter in "read -a PLANWRIGHT_STEP_WORKTREE" "read PLANWRIGHT_STEP_WORKTREE" "mapfile PLANWRIGHT_STEP_WORKTREE" \
  "readarray PLANWRIGHT_STEP_WORKTREE" "printf -v PLANWRIGHT_STEP_WORKTREE %s $OTHER_WT" \
  "declare PLANWRIGHT_STEP_WORKTREE=$OTHER_WT" "declare -x PLANWRIGHT_STEP_WORKTREE=$OTHER_WT" \
  "typeset PLANWRIGHT_STEP_WORKTREE=$OTHER_WT" "local PLANWRIGHT_STEP_WORKTREE=$OTHER_WT" \
  "unset PLANWRIGHT_STEP_WORKTREE"; do
  assert_defer "$ou_setter after the export" \
    "export PLANWRIGHT_STEP_WORKTREE=$WT && $ou_setter && $SREC write --run 1" Bash "$WT"
done
assert_allow "a read into another name after the export (control)" \
  "export PLANWRIGHT_STEP_WORKTREE=$WT && read -r X && $SREC write --run 1" Bash "$WT"
assert_defer "a loop over an exported name" \
  "export PLANWRIGHT_STEP_WORKTREE=$WT && for PLANWRIGHT_STEP_WORKTREE in $OTHER_WT; do $SREC write --run 1; done" Bash "$WT"
assert_defer "a plain step assignment before the export" \
  "PLANWRIGHT_STEP_WORKTREE=$OTHER_WT; export PLANWRIGHT_STEP_BRANCH=$B && $SREC write --run 1" Bash "$WT"
assert_defer "a plain step assignment chained before the export" \
  "PLANWRIGHT_STEP_WORKTREE=$OTHER_WT && export PLANWRIGHT_STEP_BRANCH=$B && $SREC write --run 1" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}" "PLANWRIGHT_STEP_WORKTREE=$WT")
assert_defer "a plain re-assignment of an inherited exported step name before the export" \
  "PLANWRIGHT_STEP_WORKTREE=$OTHER_WT; export PLANWRIGHT_STEP_BRANCH=$B && $SREC write --run 1" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}")
assert_allow "a non-step assignment before the export" \
  "S=$PLUGIN_ROOT/scripts && export PLANWRIGHT_STEP_BRANCH=$B && \$S/step-record.sh new-run" Bash "$WT"
assert_defer "a re-export of an exported name, same value" \
  "export PLANWRIGHT_STEP_WORKTREE=$WT && export PLANWRIGHT_STEP_WORKTREE=$WT && $SREC new-run" Bash "$WT"
assert_defer "a re-export of an exported name after ;" \
  "export PLANWRIGHT_STEP_BRANCH=$B; export PLANWRIGHT_STEP_BRANCH=x; $SREC new-run" Bash "$WT"
assert_allow "a second checked export" "export PLANWRIGHT_STEP_BRANCH=$B && export PLANWRIGHT_STEP_WORKTREE=$WT && $SREC new-run" Bash "$WT"

echo "### the step worktree is pinned in every spelling under a record"
assert_defer "the prefix spelling naming another worktree" "PLANWRIGHT_STEP_WORKTREE=$OTHER_WT $SREC write --run 1" Bash "$WT"
assert_defer "the env spelling naming another worktree" "env PLANWRIGHT_STEP_WORKTREE=$OTHER_WT $SREC write --run 1" Bash "$WT"
assert_allow "the prefix spelling naming the session's own" "PLANWRIGHT_STEP_WORKTREE=$WT $SREC write --run 1" Bash "$WT"

echo "### an own-unit act never shares a command with a policy-arm act"
ARMS="$CS/records/arms.record"
record "$ARMS" "own-branch scratch"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$ARMS" "PATH=$STUB:$PATH" "TMPDIR=$SCR")
assert_allow "the scratch arm's write alone (control)" "mkdir $SCR/made" Bash "$WT"
assert_allow "the own-branch arm's write alone (control)" "touch $WT/made" Bash "$WT"
assert_allow "the push alone under the arms (control)" "git push origin $B" Bash "$WT"
assert_defer "a push chained after a scratch-arm write" "mkdir $SCR/made2 && git push origin $B" Bash "$WT"
assert_defer "a push chained after an own-branch write" "touch $WT/made2 && git push origin $B" Bash "$WT"
assert_defer "a body edit chained after a scratch-arm write" "mkdir $SCR/made3 && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "an export chained before an own-branch write" "export $CTX && touch $WT/made3" Bash "$WT"
assert_allow "a scratch read beside a push stays allowed" "cat \$TMPDIR/body.md && git push origin $B" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}")
# A fetch writes remote-tracking refs: it is no read-only segment, so it
# never shares a command with an own-unit act, under any policy.
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$WT" remote add origin "$CS/no-such-origin.git" || exit 1
assert_allow "a plain fetch alone (control)" "git fetch origin" Bash "$WT"
assert_defer "a push after a fetch" "git fetch origin && git push origin $B" Bash "$WT"
assert_defer "a body edit after a fetch" "git fetch origin && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "an export after a fetch" "git fetch origin && export $CTX && $SREC write --run 1" Bash "$WT"
assert_defer "a push after a fetch of its branch" "git fetch origin $B && git push origin $B" Bash "$WT"
# Chain partners: a git add or commit the policy approves on its own, and a
# trusted repository task, may come before the act, joined to it by `&&`.
mkdir -p "$WT/scripts" "$WT/tests"
: >"$WT/scripts/check.sh"
: >"$WT/tests/x.sh"
: >"$WT/f"
assert_allow "a mise task alone (control)" "mise run check" Bash "$WT"
assert_allow "a repo test alone (control)" "bash tests/x.sh" Bash "$WT"
assert_allow "a repo script alone (control)" "scripts/check.sh" Bash "$WT"
assert_allow "a push after a mise task" "mise run check && git push origin $B" Bash "$WT"
assert_allow "a push after a repo test run by bash" "bash tests/x.sh && git push origin $B" Bash "$WT"
assert_allow "a push after a repo script" "scripts/check.sh && git push origin $B" Bash "$WT"
assert_allow "a body edit after a mise task" "mise run check && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_allow "an installed step script beside a push stays allowed" "$SREC write --run 1 && git push origin $B" Bash "$WT"
assert_defer "an export before a repo script (a partner after the act)" "export $CTX && scripts/check.sh" Bash "$WT"
assert_defer "a gate after the push" "git push origin $B && mise run check" Bash "$WT"
assert_defer "a gate joined to the push by ;" "mise run check; git push origin $B" Bash "$WT"
assert_defer "a gate joined by a chain the ; breaks" "mise run check && git status; git push origin $B" Bash "$WT"
assert_defer "a gate piped" "mise run check | cat && git push origin $B" Bash "$WT"
assert_defer "a gate backgrounded" "mise run check & git push origin $B" Bash "$WT"
assert_defer "a gate in a loop" "for x in a; do mise run check; done && git push origin $B" Bash "$WT"
assert_defer "a gate after ||" "git status || mise run check && git push origin $B" Bash "$WT"
assert_defer "a gate chain over a line break" "mise run check &&
git push origin $B" Bash "$WT"
: >"$WT/tests/x.bats"
assert_allow "a push after lefthook run" "lefthook run pre-commit && git push origin $B" Bash "$WT"
assert_allow "a push after bats" "bats tests/x.bats && git push origin $B" Bash "$WT"
assert_allow "a push after a repo test run by sh" "sh tests/x.sh && git push origin $B" Bash "$WT"
assert_allow "an export after a gate" "mise run check && export $CTX && $SREC write --run 1" Bash "$WT"
assert_defer "a gate, a read and ; before the push" "mise run check && echo ok; git push origin $B" Bash "$WT"
assert_defer "a gate joined to the push by &" "mise run check && git status & git push origin $B" Bash "$WT"
assert_defer "a plugin script other than a step script before the push" "$PLUGIN_ROOT/scripts/plug.sh && git push origin $B" Bash "$WT"
assert_defer "bash running a plugin script before the push" "bash $PLUGIN_ROOT/scripts/plug.sh && git push origin $B" Bash "$WT"
assert_defer "a plugin script after the push" "git push origin $B && $PLUGIN_ROOT/scripts/plug.sh" Bash "$WT"
# The compute router is a plugin script too: a routed gate stays a call of its own.
: >"$PLUGIN_ROOT/scripts/compute-route.sh"
CR=$PLUGIN_ROOT/scripts/compute-route.sh
assert_allow "a routed gate alone (control)" "$CR --check -- mise run check" Bash "$WT"
assert_defer "a push after a routed check gate" "$CR --check -- mise run check && git push origin $B" Bash "$WT"
assert_defer "a push after a routed test gate" "$CR --test tests/x.sh -- bash tests/x.sh && git push origin $B" Bash "$WT"
assert_defer "a body edit after a routed gate" "$CR --check -- mise run check && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "an export after a routed gate" "$CR --check -- mise run check && export $CTX && $SREC write --run 1" Bash "$WT"
rm -f "$REC.audit/own.log"
assert_allow "a gate chain, for its audit line" "mise run check && git push origin $B" Bash "$WT"
if grep -q ' arm=own-unit ' "$REC.audit/own.log" 2>/dev/null; then
  pass "a gate chain's audit line reads own-unit"
else
  fail "a gate chain's audit line: $(cat "$REC.audit/own.log" 2>&1)"
fi
assert_defer "a commit chain under a policy without the own-branch arm" "git commit -m x && git push origin $B" Bash "$WT"
# git add and commit need the own-branch arm on the unit branch.
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git -C "$WT" checkout -q -b "$B" || exit 1
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$ARMS" "PATH=$STUB:$PATH" "TMPDIR=$SCR")
assert_allow "git add and commit alone (control)" "git add -A && git commit -m x" Bash "$WT"
assert_allow "a push after add and commit" "git add -A && git commit -m x && git push origin $B" Bash "$WT"
assert_allow "a push after a commit and a gate" "git commit -m x && mise run check && git push origin $B" Bash "$WT"
assert_allow "a push after a mise task under the arm" "mise run check && git push origin $B" Bash "$WT"
assert_allow "a push after a repo test run by bash under the arm" "bash tests/x.sh && git push origin $B" Bash "$WT"
assert_allow "a push after a repo script under the arm" "scripts/check.sh && git push origin $B" Bash "$WT"
assert_allow "a push after lefthook run under the arm" "lefthook run pre-commit && git push origin $B" Bash "$WT"
assert_allow "a push after bats under the arm" "bats tests/x.bats && git push origin $B" Bash "$WT"
assert_defer "a commit with a flag the arm refuses before the push" "git commit --amend -m x && git push origin $B" Bash "$WT"
assert_allow "a body edit after a commit" "git commit -m x && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_allow "an export after a commit" "git commit -m x && export $CTX && $SREC write --run 1" Bash "$WT"
assert_defer "a commit joined to the push by ;" "git commit -m x; git push origin $B" Bash "$WT"
assert_defer "a commit after the push" "git push origin $B && git commit -m x" Bash "$WT"
assert_defer "a commit backgrounded" "git commit -m x & git push origin $B" Bash "$WT"
assert_defer "a commit piped" "git commit -m x | cat && git push origin $B" Bash "$WT"
assert_defer "a commit after ||" "git status || git commit -m x && git push origin $B" Bash "$WT"
assert_defer "a file write between the commit and the push" "git commit -m x && touch $WT/made4 && git push origin $B" Bash "$WT"
assert_defer "an in-place edit before the push" "sed -i s/a/b/ f && git push origin $B" Bash "$WT"
assert_defer "a write-redirect before the push" "git status > $WT/out && git push origin $B" Bash "$WT"
assert_defer "a commit with a message file outside the worktree" "git commit -F $OUT_DIR/body.md && git push origin $B" Bash "$WT"
for ou_off in "git rm -q f" "git restore f" "git checkout -- f" "git fetch origin" "git merge origin/main" "git mv f g"; do
  assert_defer "$ou_off before a push (not a partner)" "$ou_off && git push origin $B" Bash "$WT"
done
ARMS_LOG="$ARMS.audit/arms.log"
rm -f "$ARMS_LOG"
assert_allow "a commit chain, for its audit line" "git add -A && git commit -m x && git push origin $B" Bash "$WT"
if grep -q ' arm=own-branch,own-unit ' "$ARMS_LOG" 2>/dev/null; then
  pass "a commit chain's audit line reads own-branch,own-unit"
else
  fail "a commit chain's audit line: $(cat "$ARMS_LOG" 2>&1)"
fi
# Off the unit branch the arm approves no commit, so no chain either. The
# fixture repository has no commits, so HEAD is moved by symbolic-ref.
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git -C "$WT" symbolic-ref HEAD refs/heads/off-unit || exit 1
assert_defer "a commit chain off the unit branch" "git commit -m x && git push origin $B" Bash "$WT"
env -u GIT_DIR -u GIT_WORK_TREE HOME="$CS/no-home" XDG_CONFIG_HOME="$CS/no-home" \
  GIT_CONFIG_GLOBAL="$CS/no-home/gitconfig" GIT_CONFIG_NOSYSTEM=1 git -C "$WT" symbolic-ref HEAD "refs/heads/$B" || exit 1
HOOK_ENV=("${USE_ENV[@]}")
# Nor with a write the spec-root zone approves under any policy.
SZ="$CS/specroot"
mkdir -p "$SZ/demo"
: >"$SZ/planwright-spec-root.yml"
: >"$SZ/demo/requirements.md"
HOOK_ENV=("${USE_ENV[@]}" "PLANWRIGHT_WORKER_SPEC_ROOT=$SZ")
assert_allow "a spec-root write alone (control)" "mkdir -p $SZ/demo/sub" Bash "$WT"
assert_defer "a push after a spec-root mkdir" "mkdir -p $SZ/demo/sub2 && git push origin $B" Bash "$WT"
assert_defer "a push after a spec-root redirect" "echo x > $SZ/demo/notes.md && git push origin $B" Bash "$WT"
assert_defer "a body edit after a spec-root tee" "echo x | tee $SZ/demo/n.md && gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
HOOK_ENV=("${USE_ENV[@]}")

echo "### every class needs a usable session record"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PATH=$STUB:$PATH")
assert_defer "no record: push" "git push origin $B" Bash "$WT"
assert_defer "no record: body edit" "gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "no record: export" "export $CTX && $SREC write --run 1" Bash "$WT"
NOUNIT="$CS/records/nounit.record"
record "$NOUNIT" '' ''
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$NOUNIT" "PATH=$STUB:$PATH")
assert_defer "a record with no unit branch: push" "git push origin $B" Bash "$WT"
MAINREC="$CS/records/main.record"
record "$MAINREC" '' main
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$MAINREC" "PATH=$STUB:$PATH")
assert_defer "a record naming main as the unit: push" "git push origin main" Bash "$WT"
NOSCR="$CS/records/noscratch.record"
record "$NOSCR" '' "$B" ''
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$NOSCR" "PATH=$STUB:$PATH")
assert_defer "a record with no scratch root: body edit" "gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
NOAUDIT="$CS/records/noaudit.record"
record "$NOAUDIT" '' "$B" "$SCR" ''
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$NOAUDIT" "PATH=$STUB:$PATH")
assert_defer "a record with no audit home: push" "git push origin $B" Bash "$WT"
assert_defer "a record with no audit home: body edit" "gh pr edit 12 --body-file $SCR/body.md" Bash "$WT"
assert_defer "a record with no audit home: export" "export $CTX && $SREC new-run" Bash "$WT"

echo "### the approval is audited under its own arm"
HOOK_ENV=("${USE_ENV[@]}")
rm -f "$REC.audit/own.log"
assert_allow "a push, for the audit line" "git push origin $B" Bash "$WT"
for ou_act in "gh pr edit 12 --body-file $SCR/body.md" "export $CTX"; do
  assert_allow "$ou_act, for the audit line" "$ou_act" Bash "$WT"
done
ou_lines=$(grep -c ' arm=own-unit ' "$REC.audit/own.log" 2>/dev/null)
if [ "$ou_lines" = 3 ]; then
  pass "each own-unit approval (push, body edit, export) is audited under the own-unit arm"
else
  fail "expected 3 own-unit audit lines, got ${ou_lines:-none}: $(cat "$REC.audit/own.log" 2>&1)"
fi

finish_suite worker-command-guard-own-unit
