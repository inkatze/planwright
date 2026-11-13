#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh, in the ready-guard suite's
# style: every case drives the hook with a PreToolUse payload and asserts the
# decision, the reason where it matters, and the policy reads it made. This
# file covers jurisdiction, the pull-request acts and the base-merge git acts;
# tests/test-policy-guard-rewrites.sh covers the rewrites, pushes, protected
# set and fail-closed reads, tests/test-policy-guard-kickoff.sh the kickoff
# sign-off push, and tests/test-policy-guard-gh-api.sh gh api. The harness
# explains the stubs and the repositories; tests/lib/policy-guard-clones.sh
# builds the other-branch, pushed, no-upstream and failed-refresh siblings.
# The guard only ever sees fixture commands.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"


if [ "$(git -C "$UNIT" rev-list --count HEAD --not --remotes)" = 3 ] \
  && [ "$(git -C "$PUSHED" rev-list --count HEAD --not --remotes)" = 0 ]; then
  pass "fixture: the unit clone carries three unpushed commits and the pushed clone none"
else
  fail "fixture: the clones do not carry the expected pushed/unpushed split; every unpushed-commit case here and in tests/test-policy-guard-rewrites.sh would be vacuous"
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
  set_knobs "ready_flip_policy: $v" 'merge_policy: policy-class'
  pg tower 'gh pr ready 42'
  expect deny "[tower] $v: gh pr ready denies"
  reads none "[tower] $v: the tower's flip deny reads no knob"
  # The merge helper flips inside its own process, below the hook, so the
  # hook only ever sees the helper's invocation: under policy-class that must
  # not be refused under either flip value, while the direct flip beside it
  # follows the value.
  pg worker "$REAL_SCRIPTS/merge-admitted.sh 42"
  expect defer "[worker] $v: the merge helper's invocation is not refused (its own flip runs below the hook)"
  reads merge_policy "[worker] $v: the merge helper's invocation reads merge_policy alone, no flip knob"
  pg worker 'gh pr ready 42'
  if [ "$v" = human ]; then
    expect deny "[worker] human: beside it, the direct flip is refused (the value is live)"
  else
    expect defer "[worker] unit-owner: beside it, the direct flip defers (the value is live)"
  fi
done

echo "# the merge helper (REQ-D1.4, REQ-D1.5)"
for v in human on-approval; do
  set_knobs "merge_policy: $v"
  pg worker "$REAL_SCRIPTS/merge-admitted.sh --spec specs/demo --task 1"
  expect deny "[worker] $v: the merge helper is refused"
  reason_has "merge_policy is $v" "[worker] $v: the refusal names the knob"
  reads merge_policy "[worker] $v: the helper's refusal reads merge_policy alone"
done
set_knobs 'merge_policy: policy-class'
pg tower "$REAL_SCRIPTS/merge-admitted.sh --spec specs/demo --task 1"
expect deny "[tower] policy-class: the merge helper is refused at the tower"
reads none "[tower] the tower's helper deny reads no knob"
# shellcheck disable=SC2016 # the unexpanded root is the spelling under test
pg worker '"$ROOT/scripts/merge-admitted.sh" --spec specs/demo --task 1'
expect defer "[worker] policy-class: a variable-rooted helper path is read as the helper"
reads merge_policy "[worker] a variable-rooted helper path reads merge_policy"
set_knobs 'merge_policy: human'
# shellcheck disable=SC2016
pg worker '"$ROOT/scripts/merge-admitted.sh" --spec specs/demo --task 1'
expect deny "[worker] human: a variable-rooted helper path is refused"
pg worker "x=\$(echo 1) && $REAL_SCRIPTS/merge-admitted.sh"
expect deny "[worker] an unanalyzable command naming the helper is refused"
pg worker "grep -n merge_policy $REAL_SCRIPTS/merge-admitted.sh"
expect defer "[worker] reading the helper's text is not running it"
set_knobs 'merge_policy: policy-class'
# shellcheck disable=SC2016 # the unexpanded forms are the spellings under test
pg worker 'bash "$ROOT/scripts/merge-admitted.sh" --spec specs/demo --task 1'
expect defer "[worker] policy-class: a shell running the variable-rooted helper is read as the helper"
# shellcheck disable=SC2016
for spell in 'bash scripts/merge-admit*.sh --spec specs/demo --task 1' \
  'X=sh; bash $R/merge-admitted.$X --spec specs/demo --task 1' \
  'f=$R/merge-admitted.sh; bash $f --spec specs/demo --task 1' \
  'bash < scripts/merge-admitted.sh' \
  'scripts/merge-admi??ed.sh --spec specs/demo --task 1'; do
  pg tower "$spell"
  expect deny "[tower] policy-class: an obfuscated helper spelling is refused: $spell"
done
set_knobs 'merge_policy: human'
pg worker 'bash scripts/merge-admit*.sh --spec specs/demo --task 1'
expect deny "[worker] human: a globbed helper spelling is read as the helper and refused"
for tier in worker tower; do
  for v in human policy-class; do
    set_knobs "merge_policy: $v" 'ready_flip_policy: unit-owner'
    pg "$tier" "$REAL_SCRIPTS/ready-flip.sh flip --for-merge --spec specs/demo --task 1"
    expect deny "[$tier] $v: an agent's own ready-flip --for-merge is refused (only the merge helper issues it)"
    pg "$tier" "bash $REAL_SCRIPTS/ready-flip.sh evaluate --for-merge --spec specs/demo --task 1"
    expect deny "[$tier] $v: an agent's own ready-flip evaluate --for-merge is refused"
  done
done
set_knobs 'ready_flip_policy: unit-owner'
pg worker "$REAL_SCRIPTS/ready-flip.sh flip --spec specs/demo --task 1"
expect defer "[worker] a plain ready-flip run is not the merge helper's act"
set_knobs 'merge_policy: policy-class' 'ready_flip_policy: human'
# shellcheck disable=SC2016 # the unexpanded root is the spelling under test
for tier in worker tower; do
  pg "$tier" '"$ROOT/scripts/ready-flip.sh" flip --for-merge --spec specs/demo --task 1'
  expect deny "[$tier] a variable-rooted ready-flip --for-merge is refused too"
done
for spell in 'bash scripts/*-admitted.sh --spec specs/demo --task 1' 'bash scripts/merge-a[d]mitted.sh' \
  'bash scripts/merge-?dmitted.sh' 'scripts/*-admitted.sh --spec specs/demo --task 1' 'bash scripts/merge-a{d,}mitted.sh'; do
  pg tower "$spell"
  expect deny "[tower] a glob or brace spelling that could name the helper is refused: $spell"
done
# shellcheck disable=SC2016 # the unexpanded forms are the spellings under test
for spell in "$REAL_SCRIPTS/ready-flip.sh flip --spec specs/demo --{for-merge,task} 1" \
  "$REAL_SCRIPTS/ready-flip.sh flip --spec specs/demo \$'--for-merge' --task 1" \
  "$REAL_SCRIPTS/ready-flip.sh flip --spec specs/demo --fo\$X --task 1"; do
  for tier in worker tower; do
    pg "$tier" "$spell"
    expect deny "[$tier] an assembled --for-merge spelling is refused: $spell"
  done
done
for spell in 'bash -e < scripts/merge-admitted.sh' 'bash -s -- --spec x < scripts/merge-admitted.sh' \
  'bash -s -- -c < scripts/merge-admitted.sh' 'bash -x scripts/merge-admitted.sh --spec x'; do
  pg tower "$spell"
  expect deny "[tower] a shell with an option reading the helper on stdin is refused: $spell"
done
set_knobs 'merge_policy: policy-class' 'ready_flip_policy: human'
for opts in '-x' '-ex' '-o pipefail' '-euo pipefail' '-eO extglob' '--norc' '--' '-e --'; do
  pg worker "bash $opts $REAL_SCRIPTS/merge-admitted.sh --spec specs/demo --task 1"
  expect defer "[worker] policy-class: bash $opts before the helper is parsed as the shell's options"
  reads merge_policy "[worker] bash $opts before the helper reads merge_policy"
done
# shellcheck disable=SC2016 # the unexpanded forms are the spellings under test
for spell in 'F=$ROOT/scripts/ready-flip.sh; bash "$F" flip --spec x --for-merge # merge-admitted' \
  'bash -s flip --spec x --for-merge < $ROOT/scripts/ready-flip.sh # merge-admitted'; do
  for tier in worker tower; do
    pg "$tier" "$spell"
    expect deny "[$tier] a stem elsewhere in the command does not carry a --for-merge past the guard: $spell"
    [ "$tier" = tower ] || reason_has 'cannot name' "[worker] the deny is the flag check, not another refusal: $spell"
  done
done
# shellcheck disable=SC2016 # the unexpanded forms are the spellings under test
for spell in 'bash scripts/ready-{flip.sh,x} --for-merge' 'bash scripts/$RF --for-merge --spec x'; do
  pg worker "$spell"
  expect deny "[worker] a script name the guard cannot resolve, carrying --for-merge, is refused: $spell"
done
set_knobs 'merge_policy: human' 'ready_flip_policy: unit-owner'
# shellcheck disable=SC2016
pg worker 'bash "$S" --flag "$V"'
expect defer "[worker] an unresolvable script name with no --for-merge is not the flag's act"
for spell in 'bash tests/test-merge-admitted.sh' 'shellcheck scripts/merge-admitted.sh && bash tests/test-merge-admitted.sh' \
  'git commit -m "docs: explain the --for-merge flag"' 'rg -n -- --for-merge scripts/' 'bash tests/test-*.sh' \
  'bash -x tests/test-policy-guard.sh 2>&1 | grep merge-admitted' 'bash -e tests/run.sh && rg -n foo scripts/merge-admitted.sh' \
  "$REAL_SCRIPTS/ready-flip.sh park --spec specs/demo --task 1 --reason 'waiting on {operator}'"; do
  pg worker "$spell"
  expect defer "[worker] naming the helper or its flag without running them is not the act: $spell"
done
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'

echo "# the force-push path is the tower's (REQ-F1.2)"
for cmd in "$REAL_SCRIPTS/tower-force-push.sh push --branch planwright/demo/task-1 --to HEAD --lease HEAD" \
  "$REAL_SCRIPTS/tower-force-push.sh reword --branch planwright/demo/task-1 --commit HEAD --message-file m" \
  'scripts/tower-force-push.sh confirm --branch b --to HEAD' 'bash scripts/tower-force-push.sh push --branch b' \
  'git status && sh scripts/tower-force-push.sh push --branch b'; do
  pg worker "$cmd"
  expect deny "[worker] the force-push helper denies: $cmd"
  reads none "[worker] the force-push helper deny reads no knob: $cmd"
  pg tower "$cmd"
  expect defer "[tower] the force-push helper defers to the operator's prompt: $cmd"
done
pg worker '"$ROOT/scripts/tower-force-push.sh" confirm --branch b'
expect deny "[worker] the force-push helper by a rooted path denies"
for cmd in 'bash -c "scripts/tower-force-push.sh push --branch b"' '. scripts/tower-force-push.sh push --branch b' \
  'source scripts/tower-force-push.sh push' 'echo b | xargs scripts/tower-force-push.sh push --branch' \
  'sudo scripts/tower-force-push.sh push --branch b' 'eval "scripts/tower-force-push.sh push --branch b"' \
  'echo "$(scripts/tower-force-push.sh push --branch b)"' 'scripts/Tower-Force-Push.sh push --branch b' \
  'command -p scripts/tower-force-push.sh push --branch b' 'sudo -u bob scripts/tower-force-push.sh push' \
  'timeout 5 scripts/tower-force-push.sh push' 'env A=1 bash scripts/tower-force-push.sh push' \
  'bash -c "cd x && scripts/tower-force-push.sh push"' '{ scripts/tower-force-push.sh push; }' \
  'bash -c "\"${ROOT}/scripts/tower-force-push.sh\" push"' 'echo `scripts/tower-force-push.sh push`'; do
  pg worker "$cmd"
  expect deny "[worker] the force-push helper behind a wrapper denies: $cmd"
done
# The helper's name outside command position runs nothing.
for cmd in 'grep -n tower-force-push skills/tower/SKILL.md' 'tests/test-tower-force-push.sh' \
  'bash tests/test-tower-force-push.sh' 'sh tests/test-tower-force-push.sh' 'grep tower-force-push file' \
  'bash -c "grep -n tower-force-push skills/tower/SKILL.md"' 'eval "grep tower-force-push file"' \
  'grep "tower-force-push" file' 'rg -l tower-force-push.sh scripts tests'; do
  pg worker "$cmd"
  expect defer "[worker] naming the helper without running it defers: $cmd"
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
reason_has 'request-reviewer\.sh' "the undo deny names the helper's path"

echo "# the re-draft corrective helper is the one admitted undo"
for tier in worker tower; do
  for cmd in 'scripts/request-reviewer.sh --repo acme/widgets --pr 42 --copilot' \
    'bash scripts/request-reviewer.sh --repo acme/widgets --pr 42 --reviewer octocat --spec specs/demo --task 1'; do
    pg "$tier" "$cmd"
    expect defer "[$tier] the corrective helper is admitted: $cmd"
    reads none "[$tier] the corrective helper reads no knob: $cmd"
  done
  for cmd in 'gh -R acme/widgets pr ready 42 --undo' 'gh pr ready 42 --repo acme/widgets --undo' \
    'gh pr ready 42 --undo=yes' 'env GH_REPO=acme/widgets gh pr ready 42 --undo' \
    "bash -c 'gh pr ready 42 --undo'" 'scripts/request-reviewer.sh --repo acme/widgets --pr 42 --copilot && gh pr ready 42 --undo' \
    "gh api graphql -f query='mutation{convertPullRequestToDraft(input:{pullRequestId:\"PR_x\"}){clientMutationId}}'"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] no other undo spelling is admitted: $cmd"
  done
done

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
  'git merge origin/main origin/planwright/demo/task-2' 'git pull origin planwright/demo/task-2' \
  'git pull origin main:main' 'git merge $BASE' 'git pull origin planwright/demo/task-1:planwright/demo/task-1'; do
  pg worker "$cmd"
  expect deny "[worker] allow: $cmd denies (the source is neither the PR base nor the branch's own remote branch)"
done
echo "# the worker brings its own remote branch in"
for cmd in 'git merge origin/planwright/demo/task-1' 'git merge --ff-only origin/planwright/demo/task-1' \
  'git merge refs/remotes/origin/planwright/demo/task-1' 'git merge' 'git pull' 'git pull origin planwright/demo/task-1' \
  'git pull --ff-only' 'git merge origin/main origin/planwright/demo/task-1'; do
  pg worker "$cmd"
  expect defer "[worker] allow: $cmd defers (its own remote branch)"
done
gitq -C "$UNIT" branch origin/planwright/demo/task-1 HEAD~1
pg worker 'git merge origin/planwright/demo/task-1'
expect deny "[worker] allow: a local branch shadowing the own remote branch denies the merge"
gitq -C "$UNIT" branch -D origin/planwright/demo/task-1
gitq -C "$UNIT" config branch.planwright/demo/task-1.merge refs/heads/planwright/demo/task-2
pg worker 'git merge'
expect deny "[worker] allow: a no-source merge whose upstream is another branch denies"
reason_has 'names no source' "the no-source refusal says why"
pg worker 'git pull'
expect deny "[worker] allow: a no-source pull whose upstream is another branch denies"
gitq -C "$UNIT" config branch.planwright/demo/task-1.merge refs/heads/planwright/demo/task-1
gitq -C "$UNIT" remote add fork "$ORIGIN"
gitq -C "$UNIT" fetch fork
for cmd in 'git merge fork/planwright/demo/task-1' 'git pull fork planwright/demo/task-1'; do
  pg worker "$cmd"
  expect deny "[worker] allow: the same branch on another remote is not its own remote branch: $cmd"
done
gitq -C "$UNIT" remote remove fork
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
set_knobs 'worker_base_merge: allow' 'unpushed_rewrite: deny'
printf '[pull]\n\trebase\n' >>"$UNIT/.git/config"
pg worker 'git pull origin main'
expect deny "[worker] unpushed_rewrite deny: pull.rebase written with no value is a rebasing pull"
reason_has 'unpushed_rewrite is deny' "the valueless-rebase refusal names the knob"
reason_has 'no-rebase merges instead\) is refused\. Merge the PR base instead: git merge origin/main' "the configured-rebase refusal names --no-rebase once and the base by name"
for cmd in 'git pull --rebase origin main' 'git pull -r origin main'; do
  pg worker "$cmd"
  expect deny "[worker] unpushed_rewrite deny: an explicit rebasing pull is refused: $cmd"
  reason_has 'instead: git pull --no-rebase, git merge origin/main' "the explicit rebasing-pull refusal names the merge remedies: $cmd"
done
gitq -C "$UNIT" config --unset pull.rebase
set_knobs 'worker_base_merge: allow'
for cmd in 'git merge origin/main' 'git pull' 'git pull origin main' 'git -C . merge origin/main' 'git "pull" origin main'; do
  pg tower "$cmd"
  expect deny "[tower] $cmd denies under allow"
  reads none "[tower] $cmd reads no knob"
done

echo "# the primary checkout's fast-forward"
# The raw git spellings keep every refusal at both tiers; an ff-only one names
# the sanctioned verb, so a launched session can keep the primary current
# without the operator. The verb itself performs no reserved act here.
FF_VERB='main-currency\.sh ff-primary'
for cmd in "git -C $MAIN merge --ff-only origin/main" "git -C $MAIN pull --ff-only origin main" \
  'git merge --ff-only origin/main' 'git pull --ff-only origin main'; do
  pg tower "$cmd" "$MAIN"
  expect deny "[tower] the raw fast-forward still denies: $cmd"
  reads none "[tower] the raw fast-forward reads no knob: $cmd"
  reason_has "$FF_VERB" "[tower] the fast-forward refusal names the sanctioned verb: $cmd"
done
for cmd in "git -C $MAIN merge --ff-only origin/main" "git -C $MAIN pull --ff-only origin main"; do
  pg worker "$cmd"
  expect deny "[worker] a fast-forward of the primary's main from a unit worktree still denies: $cmd"
  reason_has "$FF_VERB" "[worker] that refusal names the sanctioned verb: $cmd"
done
pg worker 'git merge --ff-only origin/main' "$MAIN" "$MAIN"
expect deny "[worker] a fast-forward run in the primary itself still denies"
reason_has "$FF_VERB" "[worker] that refusal names the sanctioned verb"
for spec in "tower|git -C $MAIN merge origin/main" "tower|git -C $MAIN merge --no-ff origin/main" \
  "worker|git -C $MAIN merge origin/main" "tower|git -C $MAIN pull origin main"; do
  pg "${spec%%|*}" "${spec#*|}"
  expect deny "[${spec%%|*}] a merge that is not fast-forward-only still denies: ${spec#*|}"
  case $REASON in
    *main-currency.sh*) fail "[${spec%%|*}] a real merge's refusal points at the fast-forward verb: ${spec#*|}" ;;
    *) pass "[${spec%%|*}] a real merge's refusal does not point at the fast-forward verb: ${spec#*|}" ;;
  esac
done
for cmd in 'git merge --ff-only upstream/main' 'git merge --ff-only origin/develop' \
  'git pull --ff-only upstream main' 'git pull --ff-only origin develop'; do
  pg tower "$cmd"
  expect deny "[tower] another remote or branch still denies: $cmd"
  pg worker "$cmd"
  expect deny "[worker] another remote or branch still denies on the unit branch: $cmd"
  case $REASON in
    *main-currency.sh*) fail "[worker] a source refusal on the unit branch points at the primary's fast-forward verb: $cmd" ;;
    *) pass "[worker] a source refusal on the unit branch does not point at the primary's fast-forward verb: $cmd" ;;
  esac
done
for spec in "1|--ff-" "1|--ff-o" "1|--no-ff --ff-only" "0|--ff" "0|--ff-only --no-ff" "0|--ff-only --no-f" "0|--ff-only --ff"; do
  pg tower "git -C $MAIN merge ${spec#*|} origin/main"
  expect deny "[tower] a merge with ${spec#*|} still denies"
  case ${spec%%|*}:$REASON in
    1:*main-currency.sh*) pass "[tower] ${spec#*|} leaves git fast-forward-only, and the refusal names the verb" ;;
    0:*main-currency.sh*) fail "[tower] ${spec#*|} lets git merge for real, yet the refusal names the fast-forward verb" ;;
    1:*) fail "[tower] ${spec#*|} leaves git fast-forward-only, yet the refusal does not name the verb" ;;
    *) pass "[tower] ${spec#*|} lets git merge for real, and the refusal does not name the verb" ;;
  esac
done
pg worker 'git merge --ff-only origin/main'
expect defer "[worker] allow: a fast-forward-only merge of the base into the unit branch defers"
pg worker 'git merge --ff-only origin/planwright/demo/task-2'
expect deny "[worker] allow: a fast-forward-only merge of another source denies"
case $REASON in
  *main-currency.sh*) fail "[worker] a source refusal points at the primary's fast-forward verb" ;;
  *) pass "[worker] a source refusal does not point at the primary's fast-forward verb" ;;
esac
set_knobs 'worker_base_merge: deny'
pg worker 'git merge --ff-only origin/main'
expect deny "[worker] deny: a fast-forward-only base merge denies"
case $REASON in
  *main-currency.sh*) fail "[worker] the worker_base_merge refusal points at the primary's fast-forward verb" ;;
  *) pass "[worker] the worker_base_merge refusal does not point at the primary's fast-forward verb" ;;
esac
set_knobs 'worker_base_merge: allow'
for tier in tower worker; do
  for cmd in "$REPO_ROOT/scripts/main-currency.sh ff-primary" "$REPO_ROOT/scripts/main-currency.sh ff-primary --checkout $MAIN" \
    "/bin/sh $REPO_ROOT/scripts/main-currency.sh ff-primary --checkout $SANDBOX/dotfiles"; do
    pg "$tier" "$cmd"
    expect defer "[$tier] the sanctioned fast-forward verb defers: $cmd"
    reads none "[$tier] the sanctioned fast-forward verb reads no knob: $cmd"
  done
done

echo "# a flight branch named before flight ids is still the session's unit branch"
OLDF="$SANDBOX/oldflight"
gitq -C "$SEED" switch -c planwright/flight/mc-panel-usability main
gitq -C "$SEED" commit --allow-empty -m 'pushed on the older flight'
gitq -C "$SEED" push origin planwright/flight/mc-panel-usability
clone_on "$OLDF" planwright/flight/mc-panel-usability 1
for cmd in 'git merge origin/main' 'git merge --ff-only origin/planwright/flight/mc-panel-usability' 'git pull' \
  'git pull origin main' 'git merge'; do
  pg worker "$cmd" "$OLDF" "$OLDF"
  expect defer "[worker] an older flight branch without an id: $cmd defers"
done
pg worker 'git merge origin/planwright/demo/task-2' "$OLDF" "$OLDF"
expect deny "[worker] an older flight branch still merges no other branch"
pg tower 'git merge origin/main' "$OLDF" "$OLDF"
expect deny "[tower] an older flight branch widens nothing for the tower"

echo "# a session launched at the primary checkout syncs the linked worktree its shell is in"
PRIM="$SANDBOX/prim"
gitq clone "$ORIGIN" "$PRIM"
gitq -C "$PRIM" remote set-head origin main
LWT="$SANDBOX/prim-flight"
gitq -C "$PRIM" worktree add -b planwright/flight/dispatch-backend-0123abcd "$LWT" origin/main
LWT2="$SANDBOX/prim-sibling"
gitq -C "$PRIM" worktree add -b planwright/demo/task-8 "$LWT2" origin/main
mkdir -p "$LWT/sub"
for cmd in 'git merge origin/main' "git -C $LWT merge origin/main" 'git pull origin main'; do
  pg worker "$cmd" "$LWT" "$PRIM"
  expect defer "[worker] project directory on main, shell in its flight worktree: $cmd defers"
done
for cmd in 'git merge origin/main' "git -C $LWT merge origin/main"; do
  pg worker "$cmd" "$LWT/sub" "$PRIM"
  expect defer "[worker] a shell in a subdirectory of its flight worktree owns it: $cmd"
done
pg worker 'git merge origin/main' "$PRIM" "$PRIM"
expect deny "[worker] the primary checkout on main stays refused"
reason_has 'primary checkout' "the refusal on main says the session was launched at the primary checkout"
for cmd in "git -C $LWT merge origin/main" "cd $LWT && git merge origin/main"; do
  pg worker "$cmd" "$PRIM" "$PRIM"
  expect deny "[worker] a worktree the shell is not in is not the session's own: $cmd"
  reason_has 'shell is in none' "the refusal says the shell is in no linked worktree: $cmd"
done
pg worker "git -C $PRIM merge origin/main" "$LWT" "$PRIM"
expect deny "[worker] from its worktree, a -C into the primary checkout is refused"
pg worker "git -C $LWT2 merge origin/main" "$LWT" "$PRIM"
expect deny "[worker] a sibling worktree the shell is not in is refused"
pg worker "git merge origin/main && git -C $LWT2 merge origin/main" "$LWT" "$PRIM"
expect deny "[worker] a compound reaching a second worktree is refused"
XC="$SANDBOX/same-name-clone"
gitq clone "$ORIGIN" "$XC"
gitq -C "$XC" remote set-head origin main
gitq -C "$XC" switch -c planwright/flight/dispatch-backend-0123abcd
for cmd in "git -C $XC merge origin/main" "git merge origin/main && git -C $XC merge origin/main" \
  "git -C $XC merge origin/main && git merge origin/main" "git -C $LWT pull origin main && git -C $XC pull origin main"; do
  pg worker "$cmd" "$LWT" "$PRIM"
  expect deny "[worker] another checkout holding a branch of the same name is refused in any order: $cmd"
done
pg worker "git merge origin/main && git -C $XC merge origin/main" "$LWT" "$PRIM"
reason_has 'other than this session' "the same-name refusal names the other checkout"
gitq -C "$XC" switch planwright/demo/task-1
pg worker "git merge origin/main && git -C $XC merge origin/main" "$UNIT" "$UNIT"
expect deny "[worker] a session launched into its unit checkout never reaches a same-named branch elsewhere"
for cmd in 'git commit --amend --no-edit' 'git rebase origin/main' 'git pull --rebase origin main' \
  'git merge origin/main && git pull --rebase origin main' 'git pull origin main && git pull --rebase origin main'; do
  pg worker "$cmd" "$LWT" "$PRIM"
  expect deny "[worker] the shell's worktree is a base sync only, never a rewrite: $cmd"
  reason_has 'never rewrites history' "the rewrite refusal says a primary launch never rewrites: $cmd"
done
pg worker 'git commit --amend --no-edit' "$PRIM" "$PRIM"
expect deny "[worker] a rewrite from the primary checkout itself is refused"
reason_has 'never rewrites history' "a rewrite gets the rewrite refusal before any shell-directory refusal"
printf '[pull]\n\trebase\n' >>"$PRIM/.git/config"
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect deny "[worker] pull.rebase written with no value rebases, so it is a rewrite on the shell path"
gitq -C "$PRIM" config --unset pull.rebase
gitq -C "$PRIM" config pull.rebase false
gitq -C "$PRIM" config branch.planwright/flight/dispatch-backend-0123abcd.rebase true
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect deny "[worker] the branch rebase key wins over pull.rebase false"
gitq -C "$PRIM" config --unset branch.planwright/flight/dispatch-backend-0123abcd.rebase
printf '[branch "planwright/flight/dispatch-backend-0123abcd"]\n\trebase\n' >>"$PRIM/.git/config"
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect deny "[worker] a branch rebase key written with no value wins over pull.rebase false"
gitq -C "$PRIM" config --unset branch.planwright/flight/dispatch-backend-0123abcd.rebase
gitq -C "$PRIM" config pull.rebase true
gitq -C "$PRIM" config branch.planwright/flight/dispatch-backend-0123abcd.rebase false
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect defer "[worker] a branch rebase key of false wins over pull.rebase true"
gitq -C "$PRIM" config --unset branch.planwright/flight/dispatch-backend-0123abcd.rebase
gitq -C "$PRIM" config --unset pull.rebase
printf '[pull]\n\trebase =\n' >>"$PRIM/.git/config"
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect defer "[worker] pull.rebase set to an empty value is false to git, so the pull merges"
gitq -C "$PRIM" config --unset pull.rebase
gitq -C "$PRIM" config pull.rebase merges
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect deny "[worker] pull.rebase merges rebases, so it is a rewrite on the shell path"
gitq -C "$PRIM" config --unset pull.rebase
gitq -C "$PRIM" config pull.rebase false
gitq -C "$PRIM" config branch.planwright/flight/dispatch-backend-0123abcd.rebase merges
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect deny "[worker] a branch rebase key git's bool parser rejects still wins over pull.rebase false"
gitq -C "$PRIM" config --unset branch.planwright/flight/dispatch-backend-0123abcd.rebase
gitq -C "$PRIM" config --unset pull.rebase
gitq -C "$LWT" config branch.planwright/flight/dispatch-backend-0123abcd.rebase true
pg worker 'git pull origin main' "$LWT" "$PRIM"
expect deny "[worker] a pull that rebases by configuration is a rewrite on the shell path"
reason_has 'no-rebase merges instead' "the configured-rebase refusal names git pull --no-rebase"
pg worker 'git pull --no-rebase origin main' "$LWT" "$PRIM"
expect defer "[worker] git pull --no-rebase overrides the configured rebase on the shell path"
gitq -C "$LWT" config --unset branch.planwright/flight/dispatch-backend-0123abcd.rebase
pg worker 'git merge origin/planwright/flight/dispatch-backend-0123abcd' "$LWT" "$PRIM"
expect deny "[worker] a never-pushed branch has no own remote branch to merge"
reason_has 'missing or a local branch or tag' "the missing own-remote-branch refusal says why"
gitq -C "$LWT" commit --allow-empty -m 'flight work'
gitq -C "$LWT" push -u origin planwright/flight/dispatch-backend-0123abcd
for cmd in 'git merge origin/planwright/flight/dispatch-backend-0123abcd' 'git merge' 'git pull'; do
  pg worker "$cmd" "$LWT" "$PRIM"
  expect defer "[worker] once pushed, the shell's worktree brings its own remote branch in: $cmd"
done
gitq -C "$LWT" tag origin/planwright/flight/dispatch-backend-0123abcd HEAD~1
pg worker 'git merge origin/planwright/flight/dispatch-backend-0123abcd' "$LWT" "$PRIM"
expect deny "[worker] a tag shadowing the own remote branch is refused"
reason_has 'missing or a local branch or tag' "the shadowed own-remote-branch refusal says why"
gitq -C "$LWT" tag -d origin/planwright/flight/dispatch-backend-0123abcd
gitq -C "$LWT" tag origin/planwright/flight/dispatch-backend-0123abcd HEAD
pg worker 'git merge origin/planwright/flight/dispatch-backend-0123abcd' "$LWT" "$PRIM"
expect defer "[worker] a tag of that name at the same commit is admitted: the merge takes that very commit"
gitq -C "$LWT" tag -d origin/planwright/flight/dispatch-backend-0123abcd
XCW="$SANDBOX/same-name-worktree-clone"
gitq clone "$ORIGIN" "$XCW"
gitq -C "$XCW" switch planwright/flight/dispatch-backend-0123abcd
gitq -C "$XCW" config core.worktree "$LWT"
pg worker "git -C $XCW merge origin/main" "$LWT" "$PRIM"
expect deny "[worker] another repository whose core.worktree names the session's worktree is not its checkout"
reason_has 'core.worktree' "the core.worktree refusal names the other repository's git directory"
gitq -C "$PRIM" switch --detach
pg worker 'git merge origin/main' "$LWT" "$PRIM"
expect deny "[worker] a detached primary checkout owns no worktree"
gitq -C "$PRIM" switch main
pg worker 'git merge origin/main' "$LWT2" "$LWT"
expect deny "[worker] a session launched into its own unit worktree never owns a sibling"
LDET="$SANDBOX/prim-detached"
gitq -C "$PRIM" worktree add --detach "$LDET" origin/main
LREL="$SANDBOX/prim-release"
gitq -C "$PRIM" worktree add -b release/1 "$LREL" origin/main
for proj in "$LDET" "$LREL" "$SANDBOX/not-a-repo"; do
  mkdir -p "$proj"
  pg worker 'git merge origin/main' "$LWT" "$proj"
  expect deny "[worker] only a primary-checkout launch owns the shell's worktree: project directory $proj"
done
pg worker 'git merge origin/main' "$LDET" "$PRIM"
expect deny "[worker] a detached HEAD in the shell's worktree is refused"
reason_has 'no branch' "the detached refusal says no branch is checked out"
for b in planwright/flight/task-9 planwright/flight/foo- planwright/flight/Foo planwright/flight/a/b; do
  d="$SANDBOX/prim-bad-$(printf '%s' "$b" | tr '/' '_')"
  gitq -C "$PRIM" worktree add -b "$b" "$d" origin/main
  pg worker 'git merge origin/main' "$d" "$PRIM"
  expect deny "[worker] a linked worktree on a non-unit branch stays refused: $b"
done
pg worker 'git merge origin/main' "$LREL" "$PRIM"
expect deny "[worker] a linked worktree on a release branch stays refused"
set_knobs 'worker_base_merge: allow' 'protected_branches: planwright/flight/*'
pg worker 'git merge origin/main' "$LWT" "$PRIM"
expect deny "[worker] a protected flight branch in the shell's worktree stays refused"
set_knobs 'worker_base_merge: allow'
XWT="$SANDBOX/other-flight"
gitq -C "$OTHER" worktree add -b planwright/flight/foreign-0123abcd "$XWT" HEAD
pg worker 'git merge origin/main' "$XWT" "$PRIM"
expect deny "[worker] a worktree of another repository is not the session's own"
reason_has 'shell is in none' "the other-repository refusal says the shell is in none of this repository's worktrees"
# The guard falls back to its own directory for a missing cwd; run from the
# worktree so the case fails only if that fallback is trusted.
cd "$LWT" || exit 1
pg_payload worker bash "$(jq -n '{tool_name:"Bash", tool_input:{command:"git merge origin/main"}}')" "$PRIM"
expect deny "[worker] a payload reporting no cwd owns no worktree"
reason_has 'no shell directory' "the no-cwd refusal says the hook was told no shell directory"
pg_payload worker bash "$(jq -n '{tool_name:"Bash", tool_input:{command:"git merge origin/main"}, cwd:""}')" "$PRIM"
expect deny "[worker] a payload with an empty cwd owns no worktree"
cd - >/dev/null || exit 1
for tier in tower mission-control; do
  pg "$tier" 'git merge origin/main' "$LWT" "$PRIM"
  expect deny "[$tier] the shell's worktree widens nothing for $tier"
done

no_gh_calls
finish
