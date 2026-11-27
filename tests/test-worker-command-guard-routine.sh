#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the five routine command classes
# a worker issues all day and the guard approves without a prompt: (1) the
# installed review-state.sh ledger, lock and register calls, (2) step records
# and audits whose times the tool stamps itself, (3) replies to and resolves of
# review threads only a bot has spoken in, (4) mix ci, format and test while no
# file the run executes differs from the PR base, (5) read-only gh and git.
# Every near spelling still defers.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

B=planwright/flight/demo-0123abcd
CS=$(cd "$SANDBOX" && pwd -P)
HOME_DIR="$CS/home"
STUB="$CS/stub-bin"
SCR="$CS/scratch"
mkdir -p "$HOME_DIR/.claude/scripts" "$STUB" "$SCR" "$CS/records" "$CS/no-home" "$CS/units"
RS="$HOME_DIR/.claude/scripts/review-state.sh"
: >"$RS"
chmod +x "$RS"
SREC="$PLUGIN_ROOT/scripts/step-record.sh"
SRUN="$PLUGIN_ROOT/scripts/step-run.sh"
: >"$SREC"
: >"$SRUN"

# The forge stand-in. Review comments of a pull request come from a table
# keyed on its number; a review thread answers with its first comment's place.
# Every call is logged so a fixture can show the guard only ever reads.
cat >"$STUB/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
  "pr view --json url,headRefName,isCrossRepository,state")
    # The unit's pull request is the one whose comments were just read, bar
    # pull request 27, which is another one.
    n=$(grep -o 'pulls/[0-9]*/comments' "$GH_LOG" | tail -1 | tr -dc 0-9)
    [ "$n" != 27 ] || n=21
    printf '%s\n' "{\"url\":\"https://github.com/o/r/pull/$n\",\"headRefName\":\"$UNIT_BRANCH\",\"isCrossRepository\":false,\"state\":\"${UNIT_STATE:-OPEN}\"}" ;;
  "api user") printf '%s\n' '{"login":"me"}' ;;
  "api --paginate repos/o/r/pulls/21/comments")
    printf '%s\n' '[{"id":1001,"in_reply_to_id":null,"user":{"login":"cubic-dev-ai[bot]","type":"Bot"}}]'
    printf '%s\n' '[{"id":1002,"in_reply_to_id":1001,"user":{"login":"me","type":"User"}}]' ;;
  "api --paginate repos/o/r/pulls/22/comments")
    printf '%s\n' '[{"id":1101,"in_reply_to_id":null,"user":{"login":"cubic-dev-ai[bot]","type":"Bot"}},{"id":1102,"in_reply_to_id":1101,"user":{"login":"alice","type":"User"}}]' ;;
  "api --paginate repos/o/r/pulls/23/comments")
    printf '%s\n' '[{"id":1201,"in_reply_to_id":null,"user":{"login":"alice","type":"User"}},{"id":1202,"in_reply_to_id":1201,"user":{"login":"cubic-dev-ai[bot]","type":"Bot"}}]' ;;
  "api --paginate repos/o/r/pulls/24/comments")
    printf '%s\n' '[{"id":1301,"in_reply_to_id":null,"user":{"login":"notabot","type":"Bot"}}]' ;;
  "api --paginate repos/o/r/pulls/25/comments")
    printf '%s\n' '[{"id":1401,"in_reply_to_id":null,"user":{"login":"x[bot]x","type":"Bot"}}]' ;;
  "api --paginate repos/o/r/pulls/27/comments")
    printf '%s\n' '[{"id":1601,"in_reply_to_id":null,"user":{"login":"cubic-dev-ai[bot]","type":"Bot"}}]' ;;
  "api --paginate repos/o/r/pulls/26/comments")
    printf '%s\n' '[{"id":1501,"in_reply_to_id":null,"user":{"login":"[bot]","type":"Bot"}}]' ;;
  "api graphql -f query=query(\$id:ID!){node(id:\$id){...on PullRequestReviewThread{comments(first:100){totalCount nodes{databaseId pullRequest{number repository{nameWithOwner}}}}}}} -f id=PRRT_bot")
    printf '%s\n' '{"data":{"node":{"comments":{"totalCount":2,"nodes":[{"databaseId":1001,"pullRequest":{"number":21,"repository":{"nameWithOwner":"o/r"}}},{"databaseId":1002,"pullRequest":{"number":21,"repository":{"nameWithOwner":"o/r"}}}]}}}}' ;;
  "api graphql -f query=query(\$id:ID!){node(id:\$id){...on PullRequestReviewThread{comments(first:100){totalCount nodes{databaseId pullRequest{number repository{nameWithOwner}}}}}}} -f id=PRRT_human")
    printf '%s\n' '{"data":{"node":{"comments":{"totalCount":2,"nodes":[{"databaseId":1101,"pullRequest":{"number":22,"repository":{"nameWithOwner":"o/r"}}},{"databaseId":1102,"pullRequest":{"number":22,"repository":{"nameWithOwner":"o/r"}}}]}}}}' ;;
  "api graphql -f query=query(\$id:ID!){node(id:\$id){...on PullRequestReviewThread{comments(first:100){totalCount nodes{databaseId pullRequest{number repository{nameWithOwner}}}}}}} -f id=PRRT_humanfirst")
    printf '%s\n' '{"data":{"node":{"comments":{"totalCount":2,"nodes":[{"databaseId":1201,"pullRequest":{"number":23,"repository":{"nameWithOwner":"o/r"}}},{"databaseId":1202,"pullRequest":{"number":23,"repository":{"nameWithOwner":"o/r"}}}]}}}}' ;;
  "api graphql -f query=query(\$id:ID!){node(id:\$id){...on PullRequestReviewThread{comments(first:100){totalCount nodes{databaseId pullRequest{number repository{nameWithOwner}}}}}}} -f id=PRRT_big")
    printf '%s\n' '{"data":{"node":{"comments":{"totalCount":150,"nodes":[{"databaseId":1001,"pullRequest":{"number":21,"repository":{"nameWithOwner":"o/r"}}}]}}}}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
GH_LOG="$SANDBOX/gh.log"
: >"$GH_LOG"

# mkwt <name>: a fresh worktree whose HEAD is the PR base, the trusted remote
# ref in place, a mix project in it, and a session record naming it; WT and
# REC are left set for the assertions after it.
mkwt() {
  WT="$CS/units/$1"
  REC="$CS/records/$1.record"
  mkdir -p "$WT/lib" "$WT/test" "$WT/sub" "$REC.audit"
  fixture_git init -q -b main "$WT" || exit 1
  printf 'defmodule M.MixProject do\nend\n' >"$WT/mix.exs"
  printf 'defmodule A do\nend\n' >"$WT/lib/a.ex"
  printf 'defmodule ATest do\nend\n' >"$WT/test/a_test.exs"
  printf 'readme\n' >"$WT/README.md"
  printf 'ignored_dir/\n_build/\ndeps/\n' >"$WT/.gitignore"
  fixture_git -C "$WT" add -A && fixture_git -C "$WT" commit -q -m base || exit 1
  fixture_git -C "$WT" update-ref refs/remotes/origin/main HEAD
  fixture_git -C "$WT" checkout -q -b "$B"
  printf '%s\n' "policy=" "unit_branch=$B" "worktree_root=$WT" "pr_base=origin/main" \
    "worker_base_merge=allow" "scratch_root=$SCR" \
    "audit_log_home=$(cd -P -- "$REC.audit" && pwd -P)" >"$REC"
  HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC" "PATH=$STUB:$PATH" "HOME=$HOME_DIR" "GH_LOG=$GH_LOG" "UNIT_BRANCH=$B")
}
# commit_wt <message>: commit everything in the current worktree.
commit_wt() {
  fixture_git -C "$WT" add -A && fixture_git -C "$WT" commit -q -m "$1"
}

mkwt main1

echo "### class 1: review-state.sh ledger, lock and register calls"
LED="--repo o/r --pr 1 --reviewer cubic --key k1 --anchor a1"
assert_allow "ledger record" "$RS ledger record $LED --disposition fixed --head abc123 --reply https://github.com/o/r/pull/1#c1" Bash "$WT"
assert_allow "ledger lookup" "$RS ledger lookup $LED --head abc123" Bash "$WT"
assert_allow "ledger show" "$RS ledger show --repo o/r --pr 1" Bash "$WT"
assert_allow "lock acquire" "$RS lock acquire --session s1 --repo o/r --pr 1 --wait 30" Bash "$WT"
assert_allow "lock release" "$RS lock release --session s1 --token t1 --repo o/r --pr 1" Bash "$WT"
assert_allow "lock handover" "$RS lock handover --session s1 --token t1 --repo o/r --branch $B --pr 1" Bash "$WT"
assert_allow "lock status" "$RS lock status --repo o/r --pr 1" Bash "$WT"
assert_allow "register" "$RS register --name n --skill bot-review --repo o/r --pr 1 --worktree $WT" Bash "$WT"
assert_allow "unregister" "$RS unregister --session s1" Bash "$WT"
assert_allow "sessions" "$RS sessions" Bash "$WT"
assert_allow "register, its result echoed" "$RS register --name n --skill s --repo o/r --branch $B --worktree $WT; echo rc=\$?" Bash "$WT"
assert_defer "evidence run executes its argv" "$RS evidence run --command k -- rm -rf $WT" Bash "$WT"
assert_defer "evidence record" "$RS evidence record --command k --exit 0 --started 1 --ended 2" Bash "$WT"
assert_defer "inbox send" "$RS inbox send --to s1 --from n" Bash "$WT"
assert_defer "loop mark" "$RS loop mark --skill s --iteration 1 --phase start" Bash "$WT"
assert_defer "no verb" "$RS" Bash "$WT"
assert_defer "an unknown ledger verb" "$RS ledger purge --repo o/r --pr 1" Bash "$WT"
assert_defer "an unknown lock verb" "$RS lock break --repo o/r --pr 1" Bash "$WT"
assert_defer "an end-of-options word" "$RS lock status -- --repo o/r --pr 1" Bash "$WT"
assert_defer "a substitution in a value" "$RS lock status --repo \$(id) --pr 1" Bash "$WT"
assert_defer "an unresolved variable" "$RS lock status --repo \$R --pr 1" Bash "$WT"
assert_defer "an environment prefix" "REVIEW_STATE_ROOT=$WT $RS sessions" Bash "$WT"
assert_defer "a tracked assignment before it" "REVIEW_STATE_ROOT=$WT; $RS sessions" Bash "$WT"
HOOK_ENV=("${HOOK_ENV[@]}" "HOME=$WT/inner")
mkdir -p "$WT/inner/.claude/scripts"
: >"$WT/inner/.claude/scripts/review-state.sh"
assert_defer "a HOME inside the worktree" "$WT/inner/.claude/scripts/review-state.sh sessions" Bash "$WT"
HOOK_ENV=("${HOOK_ENV[@]}" "HOME=relative-home")
assert_defer "a relative HOME" "relative-home/.claude/scripts/review-state.sh sessions" Bash "$WT"
HOOK_ENV=("${HOOK_ENV[@]}" "HOME=")
assert_defer "an empty HOME" "/.claude/scripts/review-state.sh sessions" Bash "$WT"
printf '%s\n' "policy=" "unit_branch=$B" "worktree_root=$HOME_DIR/.claude" "pr_base=origin/main" \
  "worker_base_merge=allow" "audit_log_home=$(cd -P -- "$REC.audit" && pwd -P)" >"$REC.home"
fixture_git init -q -b main "$HOME_DIR/.claude"
HOOK_ENV=("${HOOK_ENV[@]}" "HOME=$HOME_DIR" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC.home")
assert_defer "the script lies inside the recorded worktree" "$RS sessions" Bash "$SANDBOX"
HOOK_ENV=("${HOOK_ENV[@]}" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC")
# shellcheck disable=SC2088 # the unexpanded tilde is the case under test
assert_defer "a tilde path" "~/.claude/scripts/review-state.sh sessions" Bash "$WT"
assert_defer "a bare name a worker could shadow" "review-state.sh sessions" Bash "$WT"
assert_defer "a copy inside the worktree" "$WT/review-state.sh sessions" Bash "$WT"
mkdir -p "$CS/other-home/.claude/scripts"
: >"$CS/other-home/.claude/scripts/review-state.sh"
assert_defer "another home's copy" "$CS/other-home/.claude/scripts/review-state.sh sessions" Bash "$WT"
assert_defer "a dot-dot spelling" "$HOME_DIR/.claude/scripts/../scripts/review-state.sh sessions" Bash "$WT"
assert_defer "redirected into a file" "$RS sessions > $WT/out.txt" Bash "$WT"

echo "### class 2: step records, only where the tool stamps the times"
CTX="PLANWRIGHT_STEP_UNIT_KIND=flight PLANWRIGHT_STEP_BRANCH=$B PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE=$WT"
assert_allow "a completion write, stamped by the tool" "export $CTX && $SREC write --completion --run 000001 --point pre-pr" Bash "$WT"
assert_allow "render" "$SREC render --run 000001" Bash "$WT"
assert_allow "new-run" "$SREC new-run" Bash "$WT"
assert_allow "step-run audit" "$SRUN audit --through pre-pr --base origin/main" Bash "$WT"
assert_allow "step-run resolve" "$SRUN resolve --run 000001 pre-pr --unattended" Bash "$WT"
assert_allow "step-run begin and end" "$SRUN begin --run 000001 --point pre-pr --step polish && $SRUN end --run 000001 --point pre-pr --step polish" Bash "$WT"
assert_defer "a hand-timed step write (--start)" "$SREC write --run 000001 --point pre-pr --step polish --start 2026-11-22T10:00:00Z --outcome passed" Bash "$WT"
assert_defer "a hand-timed step write (--end)" "$SREC write --run 000001 --point pre-pr --step polish --end 2026-11-22T10:05:00Z --outcome passed" Bash "$WT"
assert_defer "a hand-timed step write (--start=)" "$SREC write --run 000001 --point pre-pr --step polish --start=2026-11-22T10:00:00Z" Bash "$WT"
assert_defer "a completion write with a hand-set time" "$SREC write --completion --run 000001 --point pre-pr --end 2026-11-22T10:05:00Z" Bash "$WT"
assert_defer "a write that is no completion" "$SREC write --run 000001 --point pre-pr --step polish --outcome passed" Bash "$WT"

echo "### class 3: replies to and resolves of review threads only a bot has spoken in"
: >"$GH_LOG"
REPLY="gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body='Fixed in abc123, thanks.'"
assert_allow "a reply in a thread only a bot and the operator spoke in" "$REPLY" Bash "$WT"
assert_allow "a reply with --method POST" "gh api --method POST repos/o/r/pulls/21/comments/1001/replies -f body=ok" Bash "$WT"
assert_allow "a reply in a thread holding the operator's own earlier reply" "gh api -X POST repos/o/r/pulls/21/comments/1002/replies -f body=ok" Bash "$WT"
# shellcheck disable=SC2016 # GraphQL variables, not shell ones
RES='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
assert_allow "a resolve of a thread only a bot and the operator spoke in" "gh api graphql -f query='$RES' -f id=PRRT_bot" Bash "$WT"
HOOK_ENV=("${HOOK_ENV[@]}" "UNIT_STATE=MERGED")
assert_defer "a bot-only thread on a pull request that is no longer open" "$REPLY" Bash "$WT"
HOOK_ENV=("${HOOK_ENV[@]}" "UNIT_STATE=OPEN")
assert_defer "a bot-only thread on a pull request that is not the unit's" "gh api -X POST repos/o/r/pulls/27/comments/1601/replies -f body=ok" Bash "$WT"
assert_defer "a reply where a human has replied" "gh api -X POST repos/o/r/pulls/22/comments/1101/replies -f body=ok" Bash "$WT"
assert_defer "a reply to a human's comment" "gh api -X POST repos/o/r/pulls/23/comments/1201/replies -f body=ok" Bash "$WT"
assert_defer "a thread whose first comment is a human's" "gh api -X POST repos/o/r/pulls/23/comments/1202/replies -f body=ok" Bash "$WT"
assert_defer "a bot-like login without the suffix" "gh api -X POST repos/o/r/pulls/24/comments/1301/replies -f body=ok" Bash "$WT"
assert_defer "a suffix with text after it" "gh api -X POST repos/o/r/pulls/25/comments/1401/replies -f body=ok" Bash "$WT"
assert_defer "a suffix with no login before it" "gh api -X POST repos/o/r/pulls/26/comments/1501/replies -f body=ok" Bash "$WT"
assert_defer "a comment the forge does not list" "gh api -X POST repos/o/r/pulls/21/comments/9999/replies -f body=ok" Bash "$WT"
assert_defer "a pull request the forge cannot read" "gh api -X POST repos/o/r/pulls/99/comments/1001/replies -f body=ok" Bash "$WT"
assert_defer "a resolve of a thread a human replied in" "gh api graphql -f query='$RES' -f id=PRRT_human" Bash "$WT"
assert_defer "a resolve of a thread a human opened" "gh api graphql -f query='$RES' -f id=PRRT_humanfirst" Bash "$WT"
assert_defer "a resolve of a thread past one page of comments" "gh api graphql -f query='$RES' -f id=PRRT_big" Bash "$WT"
assert_defer "a resolve of an unknown thread" "gh api graphql -f query='$RES' -f id=PRRT_nope" Bash "$WT"
assert_defer "a mutation other than resolveReviewThread" "gh api graphql -f query='mutation(\$id:ID!){deleteIssueComment(input:{id:\$id}){clientMutationId}}' -f id=PRRT_bot" Bash "$WT"
assert_defer "a resolve with a second mutation riding along" "gh api graphql -f query='$RES mutation{x}' -f id=PRRT_bot" Bash "$WT"
assert_defer "a resolve through --input" "gh api graphql --input $SCR/q.json" Bash "$WT"
assert_defer "a typed field" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies -F body=@$SCR/b.md" Bash "$WT"
assert_defer "a second field" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok -f event=APPROVE" Bash "$WT"
assert_defer "a header" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok -H X-HTTP-Method-Override:DELETE" Bash "$WT"
assert_defer "another host" "gh api --hostname evil.example -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok" Bash "$WT"
assert_defer "DELETE on the comment" "gh api -X DELETE repos/o/r/pulls/comments/1001" Bash "$WT"
assert_defer "PATCH on the comment" "gh api -X PATCH repos/o/r/pulls/comments/1001 -f body=ok" Bash "$WT"
assert_defer "a review submission" "gh api -X POST repos/o/r/pulls/21/reviews -f event=APPROVE" Bash "$WT"
assert_defer "a reply endpoint with a trailing path" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies/extra -f body=ok" Bash "$WT"
assert_defer "a forge host assigned before the reply" "GH_HOST=evil.example && gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok" Bash "$WT"
assert_defer "a forge token assigned before the reply" "GH_TOKEN=x && gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok" Bash "$WT"
assert_defer "a reply with a variable body" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=\$B" Bash "$WT"
assert_defer "a reply with a substitution body" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=\$(id)" Bash "$WT"
assert_defer "a reply piped on" "gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok | cat" Bash "$WT"
assert_defer "a reply after an earlier failure" "false || gh api -X POST repos/o/r/pulls/21/comments/1001/replies -f body=ok" Bash "$WT"
if grep -Eq 'POST|body=|mutation| -X ' "$GH_LOG"; then
  fail "the guard ran a gh write: $(grep -E 'POST|body=|mutation| -X ' "$GH_LOG" | head -3)"
else
  pass "the guard only reads: none of its gh calls is a write"
fi

echo "### class 4: mix runs, while no file the run executes differs from the PR base"
mkwt mix-clean
assert_allow "mix test" "mix test" Bash "$WT"
assert_allow "mix ci" "mix ci" Bash "$WT"
assert_allow "mix format" "mix format" Bash "$WT"
assert_allow "mix format --check-formatted" "mix format --check-formatted" Bash "$WT"
assert_allow "mix test with a file:line, flags and an option value" "mix test test/a_test.exs:12 --trace --seed 0 --max-failures 3" Bash "$WT"
assert_allow "mix test --failed" "mix test --failed" Bash "$WT"
assert_allow "mix test --seed=0" "mix test --seed=0 --no-color --partitions 2" Bash "$WT"
assert_defer "mix test --seed= with a shell word" "mix test --seed=\$(id)" Bash "$WT"
assert_defer "mix deps.get" "mix deps.get" Bash "$WT"
assert_defer "mix run" "mix run -e 'System.cmd(\"id\", [])'" Bash "$WT"
assert_defer "mix test --require" "mix test --require lib/a.ex" Bash "$WT"
assert_defer "mix format --dot-formatter" "mix format --dot-formatter /etc/x.exs" Bash "$WT"
assert_defer "mix with no task" "mix" Bash "$WT"
assert_defer "mix test of a path outside the worktree" "mix test ../x_test.exs" Bash "$WT"
assert_defer "a line suffix that hides a dot-dot" "mix format 'a:1/../../outside/x.ex'" Bash "$WT"
assert_allow "mix test with two line suffixes" "mix test test/a_test.exs:3:4" Bash "$WT"
assert_defer "mix test of an absolute path" "mix test /etc/x_test.exs" Bash "$WT"
assert_defer "mix test with an option-looking path" "mix test -- -x" Bash "$WT"
assert_defer "an environment prefix" "MIX_ENV=test mix test" Bash "$WT"
assert_defer "a tracked assignment before mix" "MIX_EXS=/tmp/x.exs; mix test" Bash "$WT"
assert_defer "a tracked assignment joined by &&" "MIX_EXS=/tmp/x.exs && mix test" Bash "$WT"
assert_defer "mix inside a substitution" "echo \$(mix test)" Bash "$WT"
assert_defer "a path-prefixed mix" "$WT/mix test" Bash "$WT"
assert_defer "a variable argument" "mix test \$F" Bash "$WT"
assert_defer "a directory with no mix.exs" "mix test" Bash "$WT/sub"
mkdir -p "$CS/outside"
printf 'x\n' >"$CS/outside/mix.exs"
assert_defer "a mix project outside the worktree" "mix test" Bash "$CS/outside"
# A text document is not inert: a base can read or doctest one by spellings no
# pattern lists.
printf 'more\n' >>"$WT/README.md"
assert_defer "an uncommitted markdown change" "mix test" Bash "$WT"
commit_wt docs
assert_defer "a committed markdown change" "mix test" Bash "$WT"
mkwt mix-deleted
rm "$WT/lib/a.ex"
assert_defer "a deleted tracked file" "mix test" Bash "$WT"
mkwt mix-worktree-config
printf 'defmodule C do\nend\n' >"$WT/test/c_test.exs"
mkdir -p "$CS/clean-tree"
fixture_git -C "$WT" archive HEAD | tar -x -C "$CS/clean-tree"
fixture_git -C "$WT" config core.worktree "$CS/clean-tree"
assert_defer "a core.worktree that points git at another tree" "mix test" Bash "$WT"
mkwt mix-flag-value
assert_defer "a flag value that is another flag" "mix test --seed --trace" Bash "$WT"
# A spec PR branch's record names the PR base but no unit branch: mix stays
# the unit's alone, even with the tree at the base.
mkwt mix-spec-branch
fixture_git -C "$WT" checkout -q -b planwright/demo/spec
grep -v '^unit_branch=' "$REC" >"$REC.tmp" && mv "$REC.tmp" "$REC"
assert_defer "a spec PR branch's record, the tree at the base" "mix test" Bash "$WT"

echo "### class 4, the unsafe cases: code that differs from the PR base never runs unprompted"
mkwt mix-commit-test
printf 'defmodule BTest do\nend\n' >"$WT/test/b_test.exs"
commit_wt "add a test"
assert_defer "a committed new test file" "mix test" Bash "$WT"
assert_defer "a committed new test file, mix ci" "mix ci" Bash "$WT"
assert_defer "a committed new test file, mix format" "mix format" Bash "$WT"
mkwt mix-edit-lib
printf 'IO.puts(1)\n' >>"$WT/lib/a.ex"
commit_wt "edit lib"
assert_defer "a committed edit of a lib file" "mix test" Bash "$WT"
mkwt mix-edit-mixexs
printf '# x\n' >>"$WT/mix.exs"
commit_wt "edit mix.exs"
assert_defer "a committed edit of mix.exs" "mix test" Bash "$WT"
mkwt mix-script
mkdir -p "$WT/scripts"
printf '#!/bin/sh\n' >"$WT/scripts/run.sh"
commit_wt "add a script"
assert_defer "a committed script" "mix ci" Bash "$WT"
mkwt mix-uncommitted-edit
printf 'IO.puts(1)\n' >>"$WT/lib/a.ex"
assert_defer "an uncommitted edit of a lib file" "mix test" Bash "$WT"
mkwt mix-staged
printf 'defmodule C do\nend\n' >"$WT/lib/c.ex"
fixture_git -C "$WT" add lib/c.ex
assert_defer "a staged new file" "mix test" Bash "$WT"
mkwt mix-untracked
printf 'defmodule C do\nend\n' >"$WT/test/c_test.exs"
assert_defer "an untracked test file" "mix test" Bash "$WT"
mkwt mix-untracked-script
printf '#!/bin/sh\n' >"$WT/x.sh"
assert_defer "an untracked script" "mix ci" Bash "$WT"
mkwt mix-ignored
mkdir -p "$WT/ignored_dir"
printf 'IO.puts(1)\n' >"$WT/ignored_dir/x.exs"
assert_defer "an ignored directory holding code" "mix test" Bash "$WT"
mkwt mix-ignored-file
printf 'ignored_file.exs\n' >>"$WT/.git/info/exclude"
printf 'IO.puts(1)\n' >"$WT/test/ignored_file.exs"
assert_defer "an ignored file holding code" "mix test" Bash "$WT"
mkwt mix-build
mkdir -p "$WT/_build"
printf 'x\n' >"$WT/_build/x.beam"
assert_defer "ignored build output may hold planted code" "mix test" Bash "$WT"
mkwt mix-deps
mkdir -p "$WT/deps/dep/lib"
printf 'defmodule Evil do\nend\n' >"$WT/deps/dep/lib/evil.ex"
assert_defer "ignored dependencies may hold planted code" "mix test" Bash "$WT"
mkwt mix-evalfile
printf 'import Code\neval_file("rules.txt")\n' >"$WT/test/e_test.exs"
commit_wt "a base that evaluates a text file through an import"
fixture_git -C "$WT" update-ref refs/remotes/origin/main HEAD
printf 'x\n' >"$WT/rules.txt"
assert_defer "a text file the base evaluates is code" "mix test" Bash "$WT"
mkwt mix-image
printf 'png\n' >"$WT/logo.png"
assert_allow "an untracked image" "mix test" Bash "$WT"
assert_defer "an image handed to mix as an operand" "mix test logo.png" Bash "$WT"
mkwt mix-assume
fixture_git -C "$WT" update-index --assume-unchanged lib/a.ex
printf 'IO.puts(1)\n' >>"$WT/lib/a.ex"
assert_defer "an assume-unchanged file the diff cannot see" "mix test" Bash "$WT"
mkwt mix-skip
fixture_git -C "$WT" update-index --skip-worktree lib/a.ex
printf 'IO.puts(1)\n' >>"$WT/lib/a.ex"
assert_defer "a skip-worktree file the diff cannot see" "mix test" Bash "$WT"
mkwt mix-nobase
fixture_git -C "$WT" update-ref -d refs/remotes/origin/main
assert_defer "no trusted base ref" "mix test" Bash "$WT"
mkwt mix-shadow
fixture_git -C "$WT" update-ref -d refs/remotes/origin/main
fixture_git -C "$WT" branch origin/main
assert_defer "a local branch spelled like the base is not the trusted ref" "mix test" Bash "$WT"
mkwt mix-badbase
printf '%s\n' "policy=" "unit_branch=$B" "worktree_root=$WT" "pr_base=origin/../main" \
  "worker_base_merge=allow" "audit_log_home=$(cd -P -- "$REC.audit" && pwd -P)" >"$REC"
assert_defer "a base ref spelled with a dot-dot" "mix test" Bash "$WT"
mkwt mix-noaudit
printf '%s\n' "policy=" "unit_branch=$B" "worktree_root=$WT" "pr_base=origin/main" \
  "worker_base_merge=allow" >"$REC"
assert_defer "a record with no usable audit log" "mix test" Bash "$WT"
mkwt mix-base-ahead
printf 'defmodule Up do\nend\n' >"$WT/lib/up.ex"
commit_wt "upstream change"
fixture_git -C "$WT" update-ref refs/remotes/origin/main HEAD
fixture_git -C "$WT" reset -q --hard HEAD~1
assert_allow "the base moved on: only the merge-base counts" "mix test" Bash "$WT"
mkwt mix-own-branch
mkdir -p "$WT/scripts"
printf '#!/bin/sh\n' >"$WT/scripts/ok.sh"
commit_wt "a repository script"
fixture_git -C "$WT" update-ref refs/remotes/origin/main HEAD
printf '%s\n' "policy=own-branch" "unit_branch=$B" "worktree_root=$WT" "pr_base=origin/main" \
  "worker_base_merge=allow" "scratch_root=$SCR" \
  "audit_log_home=$(cd -P -- "$REC.audit" && pwd -P)" >"$REC"
assert_allow "mix test under the own-branch policy" "mix test" Bash "$WT"
assert_allow "a repository script alone is approved" "bash scripts/ok.sh" Bash "$WT"
assert_defer "a write, then mix, joined by &&" "printf x > lib/b.ex && mix test" Bash "$WT"
assert_defer "a write, then mix, joined by ;" "printf x > lib/b.ex; mix test" Bash "$WT"
assert_defer "tee, then mix" "echo x | tee lib/b.ex && mix test" Bash "$WT"
assert_defer "a repository script, then mix" "bash scripts/ok.sh && mix test" Bash "$WT"
assert_defer "a path-prefixed repository script, then mix" "$WT/scripts/ok.sh && mix test" Bash "$WT"
mkwt mix-no-record
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT" "PATH=$STUB:$PATH" "HOME=$HOME_DIR")
assert_defer "no session record" "mix test" Bash "$WT"

echo "### class 5: read-only gh and git"
mkwt readonly
assert_allow "git status" "git status --short" Bash "$WT"
assert_allow "git log" "git log --oneline -5" Bash "$WT"
assert_allow "git diff against the base" "git diff origin/main...HEAD --stat" Bash "$WT"
assert_allow "git show" "git show HEAD --stat" Bash "$WT"
assert_allow "git rev-parse" "git rev-parse HEAD" Bash "$WT"
assert_allow "git branch --show-current" "git branch --show-current" Bash "$WT"
assert_allow "git ls-files" "git ls-files" Bash "$WT"
assert_allow "git merge-base" "git merge-base origin/main HEAD" Bash "$WT"
assert_allow "git show-ref" "git show-ref --verify refs/remotes/origin/main" Bash "$WT"
assert_allow "gh pr view" "gh pr view 5 --json state" Bash "$WT"
assert_allow "gh pr checks" "gh pr checks 5" Bash "$WT"
assert_allow "gh api GET" "gh api repos/o/r/pulls/5/comments" Bash "$WT"
assert_allow "gh api explicit GET" "gh api -X GET repos/o/r/pulls/5" Bash "$WT"
assert_defer "git commit-less ref write: update-ref" "git update-ref refs/heads/x HEAD" Bash "$WT"
assert_defer "git branch create" "git branch newb" Bash "$WT"
assert_defer "git branch delete" "git branch -D $B" Bash "$WT"
assert_defer "git tag create" "git tag v1" Bash "$WT"
assert_defer "git config write" "git config user.name x" Bash "$WT"
assert_defer "git config --add" "git config --add core.pager x" Bash "$WT"
assert_defer "git -c config override" "git -c core.pager=x log" Bash "$WT"
assert_defer "git add" "git add -A" Bash "$WT"
assert_defer "git stash" "git stash push -u" Bash "$WT"
assert_defer "git checkout" "git checkout main" Bash "$WT"
assert_defer "git clean" "git clean -fd" Bash "$WT"
assert_defer "git remote add" "git remote add x https://example.invalid/x" Bash "$WT"
assert_defer "git worktree add" "git worktree add $CS/units/zz" Bash "$WT"
assert_defer "git gc" "git gc" Bash "$WT"
assert_defer "git diff --output" "git diff --output=$WT/x HEAD" Bash "$WT"
assert_defer "git log with an external diff" "git log -p --ext-diff" Bash "$WT"
assert_defer "gh api -X POST" "gh api -X POST repos/o/r/issues/1/comments" Bash "$WT"
assert_defer "gh api -X PATCH" "gh api -X PATCH repos/o/r/pulls/5" Bash "$WT"
assert_defer "gh api -X DELETE" "gh api -X DELETE repos/o/r/issues/comments/1" Bash "$WT"
assert_defer "gh api --method=PUT" "gh api --method=PUT repos/o/r/pulls/5/merge" Bash "$WT"
assert_defer "gh api -f field" "gh api repos/o/r/issues/1/comments -f body=x" Bash "$WT"
assert_defer "gh api -F field" "gh api repos/o/r/issues/1/comments -F body=x" Bash "$WT"
assert_defer "gh api --field" "gh api repos/o/r/issues/1/comments --field body=x" Bash "$WT"
assert_defer "gh api --raw-field" "gh api repos/o/r/issues/1/comments --raw-field body=x" Bash "$WT"
assert_defer "gh api bundled -iX" "gh api -iX POST repos/o/r/issues/1/comments" Bash "$WT"
assert_defer "gh api --input" "gh api repos/o/r/issues/1/comments --input $SCR/x.json" Bash "$WT"
assert_defer "gh pr merge" "gh pr merge 5 --squash" Bash "$WT"
assert_defer "gh pr ready" "gh pr ready 5" Bash "$WT"
assert_defer "gh pr comment" "gh pr comment 5 --body x" Bash "$WT"
assert_defer "gh pr checkout" "gh pr checkout 5" Bash "$WT"
assert_defer "gh issue create" "gh issue create --title x" Bash "$WT"

finish_suite worker-command-guard-routine
