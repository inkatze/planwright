#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh, in the ready-guard suite's
# style: every case drives the hook with a PreToolUse payload and asserts the
# decision, the reason where it matters, and the policy reads it made. This
# file covers jurisdiction, the pull-request acts, the git acts, the protected
# set, and the fail-closed reads; tests/test-policy-guard-gh-api.sh covers
# gh api. The harness explains the stubs and the repositories; the siblings
# built here are the other-branch, pushed, no-upstream, and failed-refresh
# cases. The guard only ever sees fixture commands.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

OTHER="$SANDBOX/other"
clone_on "$OTHER" planwright/demo/task-2 1
SPEC="$SANDBOX/spec"
clone_on "$SPEC" planwright/demo/spec 1
MAIN="$SANDBOX/main"
gitq clone "$ORIGIN" "$MAIN"
PUSHED="$SANDBOX/pushed"
clone_on "$PUSHED" planwright/demo/task-1 0
NOUP="$SANDBOX/noup"
clone_on "$NOUP" planwright/demo/task-1 1
gitq -C "$NOUP" branch --unset-upstream
BROKEN="$SANDBOX/broken"
clone_on "$BROKEN" planwright/demo/task-1 1
gitq -C "$BROKEN" remote set-url origin "$SANDBOX/no-such-remote.git"

if [ "$(git -C "$UNIT" rev-list --count HEAD --not --remotes)" = 3 ] \
  && [ "$(git -C "$PUSHED" rev-list --count HEAD --not --remotes)" = 0 ]; then
  pass "fixture: the unit clone carries three unpushed commits and the pushed clone none"
else
  fail "fixture: the clones do not carry the expected pushed/unpushed split; every rewrite case below would be vacuous"
fi

# --- jurisdiction ------------------------------------------------------------

echo "# outside jurisdiction: no tier profile, or a command that performs no act"
for cmd in 'gh pr ready 42' 'gh pr merge 42' 'git merge origin/main' 'git commit --amend --no-edit' \
  "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'" \
  'gh api graphql -F query=@q.graphql' 'git push origin main'; do
  for tier in '' human attended; do
    pg "$tier" "$cmd"
    expect defer "no tier profile ('${tier:-none}') defers: $cmd"
    reads none "no tier profile reads nothing: $cmd"
  done
done
for tier in worker tower; do
  for cmd in 'ls -la' 'git status' 'git log --oneline -5' 'gh pr view 42' 'gh pr create --draft --title t --body b' \
    'echo gh api' 'git commit -m "wip"' 'git merge-base HEAD origin/main' 'git merge --abort' 'git rebase --continue' \
    "git commit -m \"docs: mention gh api graphql and git push origin main\"" 'gh api repos/acme/widgets/pulls/42' \
    'gh api --paginate repos/acme/widgets/pulls/42/comments' 'cat <<EOF
git push origin main
gh api -X PUT repos/acme/widgets/pulls/42/merge
EOF'; do
    pg "$tier" "$cmd"
    expect defer "[$tier] performs no reserved act: $(printf '%s' "$cmd" | head -1)"
    reads none "[$tier] no act, no policy read: $(printf '%s' "$cmd" | head -1)"
  done
done

# --- the flip (REQ-C1.5, REQ-G1.2) ------------------------------------------

echo "# the flip"
set_knobs 'ready_flip_policy: unit-owner'
pg worker 'gh pr ready 42'
expect defer "[worker] unit-owner: gh pr ready defers to the ready-guard"
reads ready_flip_policy "[worker] the flip reads only ready_flip_policy"
pg worker 'gh -R acme/widgets pr ready 42'
expect defer "[worker] unit-owner: a --repo-qualified flip defers"
set_knobs 'ready_flip_policy: human'
pg worker 'gh pr ready 42'
expect deny "[worker] human: gh pr ready denies"
reason_has 'ready_flip_policy is human' "[worker] the human-flip deny names the knob"
pg worker 'gh pr ready 42 --undo=false'
expect deny "[worker] human: --undo=false is a flip, and denies"
for v in unit-owner human; do
  set_knobs "ready_flip_policy: $v"
  pg tower 'gh pr ready 42'
  expect deny "[tower] $v: gh pr ready denies"
  reads none "[tower] $v: the tower's flip deny reads no knob"
  # The merge helper flips inside its own process, below the hook, so the
  # hook only ever sees the helper's invocation: that must not be refused
  # under either value, while the direct flip beside it follows the value.
  pg worker "$REAL_SCRIPTS/merge-admitted.sh 42"
  expect defer "[worker] $v: the merge helper's invocation is not refused (its own flip runs below the hook)"
  reads none "[worker] $v: the merge helper's invocation reads no flip knob"
  pg worker 'gh pr ready 42'
  if [ "$v" = human ]; then
    expect deny "[worker] human: beside it, the direct flip is refused (the value is live)"
  else
    expect defer "[worker] unit-owner: beside it, the direct flip defers (the value is live)"
  fi
done

echo "# the MCP flip surface"
mcp() { # <draft-json-or-absent>
  if [ "$1" = absent ]; then
    jq -n --arg w "$UNIT" '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:"acme",repo:"widgets",pullNumber:42,title:"t"}, cwd:$w}'
  else
    jq -n --arg w "$UNIT" --argjson d "$1" '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:"acme",repo:"widgets",pullNumber:42,draft:$d}, cwd:$w}'
  fi
}
set_knobs 'ready_flip_policy: unit-owner'
pg_payload worker mcp "$(mcp false)"
expect defer "[worker] unit-owner: the MCP draft->ready transition defers"
reads ready_flip_policy "[worker] the MCP flip reads only ready_flip_policy"
set_knobs 'ready_flip_policy: human'
pg_payload worker mcp "$(mcp false)"
expect deny "[worker] human: the MCP draft->ready transition denies"
pg_payload tower mcp "$(mcp false)"
expect deny "[tower] the MCP draft->ready transition denies"
reads none "[tower] the MCP flip deny reads no knob"
pg_payload worker mcp "$(mcp true)"
expect deny "[worker] the MCP re-draft denies"
pg_payload worker mcp "$(mcp absent)"
expect defer "[worker] an MCP edit with no draft field defers"
pg_payload worker mcp '{"tool_name":"mcp__github__update_pull_request","tool_input":"nope"}'
expect deny "[worker] a malformed MCP payload denies"
pg_payload worker mcp 'not json'
expect deny "[worker] an unparseable payload on the MCP surface denies"
pg_payload '' mcp "$(mcp false)"
expect defer "no tier: the MCP flip defers"
pg_payload worker mcp '{"tool_name":"mcp__github__update_pull_request_v2","tool_input":{"draft":false}}'
expect deny "[worker] an MCP-surface payload naming another tool denies"
pg_payload worker mcp '{"tool_name":"Bash","tool_input":{"command":"true"}}'
expect deny "[worker] an MCP-surface payload naming Bash denies"
for tier in worker tower; do
  for surface in bash mcp; do
    PG_STDIN=$SANDBOX pg_payload "$tier" "$surface" ''
    expect deny "[$tier] a payload read that fails on the $surface surface denies"
    reads none "[$tier] the failed payload read denies with no read ($surface)"
  done
done

# --- undo and merge (REQ-C1.8, REQ-D1.5) -------------------------------------

echo "# the undo and the direct PR merge"
for tier in worker tower; do
  for cmd in 'gh pr ready 42 --undo' 'gh pr ready --undo 42' 'gh pr ready --undo=true 42' 'gh pr merge 42' \
    'gh pr merge --auto --squash 42' 'gh -R acme/widgets pr merge 42'; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies"
    reads none "[$tier] $cmd reads no knob"
  done
  pg "$tier" 'gh pr merge --help'
  expect defer "[$tier] gh pr merge --help merges nothing"
done
pg worker 'gh pr ready 42 --undo'
reason_has 'corrective helper' "the undo deny names the corrective helper"

# --- base merge (REQ-E1.1, REQ-E1.3) ----------------------------------------

echo "# the worker base merge"
set_knobs 'worker_base_merge: allow'
for cmd in 'git merge origin/main' 'git merge --no-edit origin/main' 'git merge refs/remotes/origin/main' \
  'git merge main' "git -C $UNIT merge origin/main" "cd $UNIT && git merge origin/main" 'git pull origin main' \
  'git pull --ff-only origin main' 'git pull --no-rebase origin main' 'git me""rge origin/main'; do
  pg worker "$cmd"
  expect defer "[worker] allow: $cmd defers"
done
pg worker 'git merge origin/main'
reads 'worker_base_merge protected_branches' "[worker] a base merge reads worker_base_merge and the protected set"
gitq -C "$UNIT" fetch origin main
pg worker 'git merge FETCH_HEAD'
expect defer "[worker] allow: a FETCH_HEAD holding the base branch fetched from the base remote defers"
gitq -C "$UNIT" fetch origin planwright/demo/task-2
pg worker 'git merge FETCH_HEAD'
expect deny "[worker] allow: a FETCH_HEAD holding another branch denies"
gitq -C "$UNIT" fetch "$SANDBOX/seed" main
pg worker 'git merge FETCH_HEAD'
expect deny "[worker] allow: a FETCH_HEAD holding main fetched from another repository denies"
rm -f "$UNIT/.git/FETCH_HEAD"
# A local branch named like the remote-tracking base shadows it in git's
# lookup, so the name alone proves nothing.
gitq -C "$UNIT" branch origin/main HEAD~1
pg worker 'git merge origin/main'
expect deny "[worker] allow: a local branch shadowing origin/main denies the merge"
gitq -C "$UNIT" branch -D origin/main
gitq -C "$UNIT" branch -f main origin/planwright/demo/task-2
pg worker 'git merge main'
expect deny "[worker] allow: a local main holding commits the remote base lacks denies"
gitq -C "$UNIT" branch -f main origin/main
pg worker 'git merge main'
expect defer "[worker] allow: a local main equal to the remote base defers"
for cmd in 'git merge origin/planwright/demo/task-2' 'git merge origin/planwright/demo/spec' 'git merge HEAD~1' \
  'git merge origin/main origin/planwright/demo/task-2' 'git pull' 'git pull origin planwright/demo/task-2' \
  'git pull origin main:main' 'git merge $BASE'; do
  pg worker "$cmd"
  expect deny "[worker] allow: $cmd denies (the source is not the PR base)"
done
pg worker 'git merge origin/main' "$OTHER"
expect deny "[worker] allow: a merge in another unit's worktree denies"
pg worker "git -C $OTHER merge origin/main"
expect deny "[worker] allow: a merge into another unit's branch through -C denies"
pg worker 'git merge origin/main' "$MAIN"
expect deny "[worker] allow: a merge into main denies"
pg worker 'git merge origin/main' "$SPEC" "$SPEC"
expect deny "[worker] allow: a session whose project directory holds a spec branch has no unit branch"
pg worker 'git --git-dir=.git merge origin/main'
expect deny "[worker] allow: --git-dir in front of a merge denies"
for cmd in 'git -c alias.x=pull x origin main' 'git -c include.path=/tmp/x.cfg up origin main' \
  'git -c help.autocorrect=immediate pulll origin main'; do
  pg worker "$cmd"
  expect deny "[worker] $cmd denies (the subcommand cannot be read)"
  reads none "[worker] $cmd reads no knob"
done
gitq -C "$UNIT" config alias.up 'pull origin main'
pg worker 'git up'
expect deny "[worker] a configured alias expanding to pull denies"
gitq -C "$UNIT" config alias.up '!git rebase origin/main'
pg worker 'git up'
expect deny "[worker] a configured shell alias naming a rebase denies"
gitq -C "$UNIT" config --unset alias.up
set_knobs 'worker_base_merge: deny'
for cmd in 'git merge origin/main' 'git pull origin main' "git -C $UNIT merge origin/main"; do
  pg worker "$cmd"
  expect deny "[worker] deny: $cmd denies"
done
reason_has 'worker_base_merge is deny' "[worker] the base-merge deny names the knob"
set_knobs 'worker_base_merge: allow'
for cmd in 'git merge origin/main' 'git pull' 'git pull origin main' 'git -C . merge origin/main' 'git "pull" origin main'; do
  pg tower "$cmd"
  expect deny "[tower] $cmd denies under allow"
  reads none "[tower] $cmd reads no knob"
done

# --- history rewrites (REQ-F1.1) ---------------------------------------------

echo "# never-pushed rewrites"
set_knobs 'unpushed_rewrite: allow'
for cmd in 'git commit --amend --no-edit' 'git commit -m wip --amend' 'git commit --am --no-edit' \
  'git commit --squash=HEAD~1' 'git commit --squash HEAD~1' 'git commit --fixup=amend:HEAD~1' \
  'git commit --fixu HEAD~2' 'git rebase -i HEAD~3' 'git rebase HEAD~2'; do
  pg worker "$cmd"
  expect defer "[worker] allow: $cmd on unpushed commits defers"
done
pg worker 'git commit --amend --no-edit'
reads 'unpushed_rewrite protected_branches' "[worker] a rewrite reads unpushed_rewrite and the protected set"
for cmd in 'git rebase origin/main' 'git rebase -i HEAD~4' 'git commit --fixup=HEAD~3' 'git rebase --root' \
  'git pull --rebase origin main' 'git rebase -i HEAD~3 --update-refs'; do
  pg worker "$cmd"
  expect deny "[worker] allow: $cmd reaches a pushed commit (or another branch) and denies"
done
pg worker 'git rebase origin/main'
reason_has 'remote-tracking ref already contains' "the pushed-commit deny says why"
for cmd in "git rebase -i HEAD~3 --exec='git push --force origin main'" \
  "git rebase -i HEAD~3 --exec 'make test'" "git rebase -i HEAD~3 --ex='make test'" \
  "git rebase -i HEAD~3 -x 'make test'" "git rebase -ix 'make test' HEAD~3" \
  "git rebase -i HEAD~3 -x'make test'" \
  'git rebase --no-update-refs --update-refs -i HEAD~3' 'git rebase --no-update-refs --upd -i HEAD~3'; do
  pg worker "$cmd"
  expect deny "[worker] allow: $cmd denies"
done
pg worker "git rebase -i HEAD~3 -x 'make test'"
reason_has 'exec' "the rebase exec deny names the option"
pg worker 'git rebase --update-refs --no-update-refs -i HEAD~3'
expect defer "[worker] allow: the last of --update-refs/--no-update-refs wins, so a trailing --no-update-refs defers"
pg worker 'git commit --amend --no-edit' "$PUSHED" "$PUSHED"
expect deny "[worker] allow: an amend of a commit a remote-tracking ref contains denies"
pg worker 'git commit --amend --no-edit' "$NOUP" "$NOUP"
expect deny "[worker] allow: an amend on a branch with no upstream denies"
reason_has 'no upstream' "the no-upstream deny says why"
pg worker 'git commit --amend --no-edit' "$BROKEN" "$BROKEN"
expect deny "[worker] allow: an amend whose upstream refresh fails denies"
reason_has 'refreshing the upstream' "the failed-refresh deny says why"
pg worker 'git commit --amend --no-edit' "$SPEC" "$SPEC"
expect deny "[worker] allow: an amend of an unpushed commit on a spec branch denies"
pg worker 'git commit --amend --no-edit' "$OTHER"
expect deny "[worker] allow: an amend in another unit's worktree denies"
# A commit pushed from another clone, read as unpushed through a stale
# tracking ref: the refresh must see it.
STALE="$SANDBOX/stale"
clone_on "$STALE" planwright/demo/task-1 1
gitq -C "$PUSHED" pull --ff-only "$STALE" planwright/demo/task-1
gitq -C "$PUSHED" push origin planwright/demo/task-1
if [ "$(git -C "$STALE" rev-list --count HEAD --not --remotes)" = 1 ]; then
  pg worker 'git commit --amend --no-edit' "$STALE" "$STALE"
  expect deny "[worker] allow: a commit another clone pushed is seen after the refresh and denies"
else
  fail "fixture: the stale clone does not read its commit as unpushed before the refresh; the stale-ref case would be vacuous"
fi
set_knobs 'unpushed_rewrite: allow' 'worker_base_merge: allow'
gitq -C "$UNIT" config pull.rebase true
pg worker 'git pull origin main'
expect deny "[worker] under pull.rebase=true a plain git pull of the base is a rebase over pushed commits, and denies"
pg worker 'git pull'
expect defer "[worker] under pull.rebase=true a bare git pull rebases only the unpushed commits onto the upstream, and defers"
pg worker 'git pull --no-rebase origin main'
expect defer "[worker] --no-rebase overrides pull.rebase, so the base merge defers"
gitq -C "$UNIT" config --unset pull.rebase
gitq -C "$UNIT" config rebase.updateRefs true
pg worker 'git rebase -i HEAD~3'
expect deny "[worker] rebase.updateRefs makes a rebase move other branches, and denies"
pg worker 'git rebase -i --no-update-refs HEAD~3'
expect defer "[worker] --no-update-refs overrides rebase.updateRefs"
gitq -C "$UNIT" config --unset rebase.updateRefs
set_knobs 'unpushed_rewrite: deny'
for cmd in 'git commit --amend --no-edit' 'git rebase -i HEAD~3' 'git commit --fixup=HEAD~1'; do
  pg worker "$cmd"
  expect deny "[worker] deny: $cmd denies"
done
reason_has 'unpushed_rewrite is deny' "[worker] the rewrite deny names the knob"
set_knobs 'unpushed_rewrite: allow'
for cmd in 'git commit --amend --no-edit' 'git commit --am""end --no-edit' 'git rebase -i HEAD~3' 'git re""base origin/main' \
  'git commit --squash=HEAD~1' 'git commit --fix=HEAD~1'; do
  pg tower "$cmd"
  expect deny "[tower] $cmd denies under allow"
  reads none "[tower] $cmd reads no knob"
done

# --- pushes and the protected set (REQ-F1.5) ---------------------------------

echo "# pushes and the protected set"
set_knobs 'protected_branches:'
for tier in worker tower; do
  for cmd in 'git push origin main' 'git push origin HEAD:refs/heads/main' 'git push origin HEAD:heads/master' \
    'git push origin planwright/demo/spec' 'git push -u origin Main' 'git push origin --delete main' 'git push origin :main'; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies (protected)"
  done
  pg "$tier" 'git push origin main'
  reads protected_branches "[$tier] a push reads only the protected set"
  for cmd in 'git push --force origin feature' 'git push -fu origin feature' 'git push origin +feature' \
    'git push --force-with-lease=feature origin feature' 'git push --mirr origin' 'git push origin --al' \
    'git push --b origin' 'git push origin :' "git push origin 'refs/heads/*:refs/heads/*'"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies (force or bulk)"
    reads none "[$tier] $cmd reads no knob"
  done
  for cmd in 'git push origin planwright/demo/task-1' 'git push -u origin HEAD' 'git push origin feature/c++' \
    'git push origin planwright/demo/spec-notes' 'git push --tags origin' 'git push origin v1.0:refs/tags/v1.0'; do
    pg "$tier" "$cmd"
    expect defer "[$tier] $cmd defers"
  done
done
pg worker 'git push origin $BRANCH'
expect deny "[worker] a push naming its target through a variable denies"
set_knobs 'protected_branches: release/*'
pg worker 'git push origin release/1.0'
expect deny "[worker] an overlay glob in protected_branches protects its matches"
pg worker 'git push origin release/1.0/rc'
expect defer "[worker] an overlay glob's * does not span a /"
set_knobs 'protected_branches: feature-x'
pg worker 'git push origin main'
expect deny "[worker] an overlay naming only a feature branch leaves main protected"
set_knobs 'protected_branches: main,master'
pg worker 'git push origin feature-y'
expect deny "[worker] a malformed protected_branches denies the push"
set_knobs 'protected_branches:'
pg worker "git push origin 'feat$(printf '\033')x'"
expect deny "[worker] a control sequence in a branch name is refused"
case $OUT in
  *"$(printf '\033')"*) fail "the deny reason carries a raw control byte" ;;
  *) pass "the deny reason is stripped of control bytes" ;;
esac

# --- fail-closed reads (REQ-G1.4) --------------------------------------------

echo "# fail-closed reads"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
for spec in 'ready_flip_policy|gh pr ready 42' 'worker_base_merge|git merge origin/main' \
  'unpushed_rewrite|git commit --amend --no-edit' 'protected_branches|git push origin feature'; do
  knob=${spec%%|*}
  STUB_FAIL_KNOB=$knob pg worker "${spec#*|}"
  expect deny "[worker] an unresolvable $knob denies ${spec#*|}"
  reason_has 'could not be' "the read-failure deny says the knob could not be read"
done
# A broken install beside the guard (the sanitizer missing) makes the
# protected-set reader exit 5, and the push is still refused as a read failure.
mv "$S/echo-safety.sh" "$S/echo-safety.sh.away"
pg worker 'git push origin feature'
expect deny "[worker] a missing echo-safety.sh beside the reader denies the push"
reason_has 'could not be read \(exit 5\)' "the broken-install deny names the read failure, not a bad branch name"
mv "$S/echo-safety.sh.away" "$S/echo-safety.sh"
set_knobs 'ready_flip_policy: agent'
pg worker 'gh pr ready 42'
expect deny "[worker] a malformed machine-local ready_flip_policy degrades to human and denies"
set_knobs 'ready_flip_policy: unit-owner'
STUB_SLEEP=3 PG_TIMEOUT=1 pg worker 'git push origin feature'
expect deny "[worker] a protected-set read past the wall-clock bound denies"
reason_has 'protected set did not finish' "the protected-set timeout deny names the timeout"
# An upstream refresh that hangs is cut off at its bound and refuses.
SLOW="$SANDBOX/slow"
clone_on "$SLOW" planwright/demo/task-1 1
gitq -C "$SLOW" remote set-url origin 'ssh://example.invalid/x.git'
GIT_SSH_COMMAND='sleep 5; :' PLANWRIGHT_POLICY_GUARD_FETCH_TIMEOUT=1 pg worker 'git commit --amend --no-edit' "$SLOW" "$SLOW"
expect deny "[worker] an upstream refresh past its bound denies the rewrite"
reason_has 'exit 124' "the refresh-timeout deny reports the timeout's exit"
STUB_SLEEP=3 PG_TIMEOUT=1 pg worker 'gh pr ready 42'
expect deny "[worker] a policy read past the wall-clock bound denies"
reason_has 'timeout' "the timeout deny names the timeout"
pg worker 'git merge origin/main' "$UNIT" "$SANDBOX/no-such-dir"
expect deny "[worker] a base merge with no readable project directory denies"
pg worker ''
expect defer "[worker] an empty command string defers"
pg_payload worker bash ''
expect deny "[worker] an empty payload denies"
pg_payload worker bash 'not json git push origin main'
expect deny "[worker] an unparseable payload naming a reserved act denies"
pg_payload worker bash 'not json at all'
expect defer "[worker] an unparseable payload naming no act defers"
pg worker 'x=$(git rev-parse HEAD); echo "$x"'
expect defer "[worker] a substitution naming no act defers"
pg worker 'x=$(git rebase origin/main)'
expect deny "[worker] a substitution hiding a rebase denies"
pg worker '(git merge origin/main)'
expect deny "[worker] a subshell hiding a merge denies"
pg worker 'git commit -m "$(cat <<'"'"'EOF'"'"'
feat: describe git push origin main and gh api graphql
EOF
)"'
expect defer "[worker] a heredoc commit message naming reserved acts defers"
pg worker "timeout 30 git rebase origin/main"
expect deny "[worker] a wrapper hiding a rebase denies"
pg worker 'sh <<EOF
git push origin main
EOF'
expect deny "[worker] a here-document fed to a shell naming a push denies"
mkdir -p "$SANDBOX/nojq"
for t in head tr dirname cat; do ln -sf "$(command -v "$t")" "$SANDBOX/nojq/$t"; done
NOJQ_OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr ready 42"}}' \
  | env -i PATH="$SANDBOX/nojq" /bin/bash "$HOOK" worker bash 2>/dev/null)
case $NOJQ_OUT in
  *'"deny"'*) pass "[worker] with jq absent a payload naming a flip denies" ;;
  *) fail "[worker] with jq absent a payload naming a flip did not deny: $NOJQ_OUT" ;;
esac
NOJQ_OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | env -i PATH="$SANDBOX/nojq" /bin/bash "$HOOK" worker bash 2>/dev/null)
if [ -z "$NOJQ_OUT" ]; then
  pass "[worker] with jq absent a payload naming no act defers"
else
  fail "[worker] with jq absent an unrelated payload did not defer: $NOJQ_OUT"
fi

# --- static properties -------------------------------------------------------

echo "# static properties"
if grep -Eq '(^|[^[:alnum:]_-])(claude|anthropic|curl|wget)([^[:alnum:]_-]|$)' <(grep -v '^[[:space:]]*#' "$REAL_SCRIPTS/policy-guard.sh"); then
  fail "the guard's code names a model or network client"
else
  pass "the guard's code names no model or network client"
fi
if grep -Eq '^[[:space:]]*\.[[:space:]]+"[^"]*/echo-safety\.sh"' "$REAL_SCRIPTS/policy-guard.sh"; then
  pass "the guard sources scripts/echo-safety.sh"
else
  fail "the guard does not source scripts/echo-safety.sh"
fi

echo "# policy is read from the primary checkout, never the command's own worktree"
WT="$SANDBOX/linked"
gitq -C "$UNIT" worktree add -b planwright/demo/task-7 "$WT" HEAD
mkdir -p "$UNIT/.claude" "$WT/.claude"
printf 'ready_flip_policy: human\n' >"$UNIT/.claude/planwright.local.yml"
printf 'ready_flip_policy: unit-owner\n' >"$WT/.claude/planwright.local.yml"
printf 'ready_flip_policy: unit-owner\n' >"$WT/.claude/planwright.yml"
PG_LOCAL_CONFIG='' PG_REPO_ROOT='' pg worker 'gh pr ready 42' "$WT" "$WT"
expect deny "[worker] a worktree's own config cannot raise ready_flip_policy over the primary checkout's"
printf 'ready_flip_policy: unit-owner\n' >"$UNIT/.claude/planwright.local.yml"
printf 'ready_flip_policy: human\n' >"$WT/.claude/planwright.local.yml"
PG_LOCAL_CONFIG='' PG_REPO_ROOT='' pg worker 'gh pr ready 42' "$WT" "$WT"
expect defer "[worker] the primary checkout's ready_flip_policy governs a linked worktree"
rm -f "$UNIT/.claude/planwright.local.yml" "$WT/.claude/planwright.local.yml" "$WT/.claude/planwright.yml"
printf 'protected_branches: release/*\n' >"$UNIT/.claude/planwright.yml"
printf 'protected_branches:\n' >"$WT/.claude/planwright.yml"
PG_LOCAL_CONFIG='' PG_REPO_ROOT='' pg worker 'gh api -X PATCH repos/acme/widgets/git/refs/heads/release/1 -f sha=abc' "$WT" "$WT"
expect deny "[worker] a worktree's own config cannot shrink the primary checkout's protected set"
rm -f "$UNIT/.claude/planwright.yml" "$WT/.claude/planwright.yml"
BARE="$SANDBOX/bare.git"
BWT="$SANDBOX/bare-linked"
gitq clone --bare "$ORIGIN" "$BARE"
gitq -C "$BARE" worktree add "$BWT" planwright/demo/task-1
for d in "$BWT" "$SANDBOX"; do
  pg worker 'gh pr ready 42' "$d" "$d"
  expect deny "[worker] no primary checkout to read policy from denies: $d"
  reads none "[worker] the unresolvable primary checkout denies before any read: $d"
done
reason_has 'primary checkout' "the unresolvable-primary deny says why"

no_gh_calls
finish
