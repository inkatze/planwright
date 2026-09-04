#!/bin/bash
# Tests for scripts/ready-guard.sh — the deterministic, DENY-EMITTING
# PreToolUse hook that refuses a draft->ready pull-request transition unless the
# PR is provably current with its base branch and mergeable
# (merge-currency-guard Task 2; REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.5,
# REQ-C1.6, REQ-C1.7, REQ-C1.8, REQ-C1.9, REQ-C1.10, REQ-D1.4, REQ-K1.1,
# REQ-K1.3; D-2, D-3, D-5, D-8).
#
# WHY THIS SUITE IS SHAPED DIFFERENTLY FROM THE SIBLING GUARD SUITES. The
# worker/tower guard suites hunt exactly one failure direction, the false ALLOW,
# because those guards are allow-only. This guard emits deny, so BOTH directions
# are failures and both are asserted with equal weight:
#   * a MISSED DENY (assert_deny) defeats the guard;
#   * a SPURIOUS DENY (assert_defer) blocks legitimate work.
# Every fixture below states which direction it pins.
#
# Contract under test:
#   DENY  <=> exit 0 AND stdout carries "permissionDecision": "deny" with a
#             non-empty permissionDecisionReason.
#   DEFER <=> exit 0 AND stdout is empty/whitespace.
#   The hook NEVER exits non-zero and NEVER emits allow or ask.
#
# The GitHub surface is stubbed, and the stub RECORDS ITS ARGV: several
# assertions pin the exact argv rather than only the answer, so a stub that
# would answer the same for a wrong subcommand, a wrong PR number, or a wrong
# repo cannot make a fixture pass vacuously.
#
# tests/test-merge-currency-matrix.sh owns the mechanically-enforced
# expected-cell manifest (REQ-D1.1) and the worker-settings deny-over-allow
# outcome test (REQ-D1.2); this suite covers Task 2's `Done when:` matrix
# branch by branch. Both source tests/lib/ready-guard-harness.sh.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/ready-guard.sh"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

# shellcheck source=tests/lib/ready-guard-harness.sh
. "$REPO_ROOT/tests/lib/ready-guard-harness.sh"

# A second cwd for the P1 wrong-repo fixtures: CONF answers conforming, STALE
# answers behind. The gh stub picks its answer from the directory it is invoked
# in, so a fixture can assert WHICH repo the guard queried, not just the verdict.
mkdir -p "$SANDBOX/conf" "$SANDBOX/stale"

echo "### REQ-C1.1 — the predicate: behind_by == 0 AND mergeable == MERGEABLE"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_defer "conforming flip (behind_by 0 + MERGEABLE + draft) defers"
assert_no_sentinels "conforming flip touches no git/curl/claude"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=7
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "behind_by 7 on a mergeStateStatus-CLEAN base denies (the false-allow case)"
assert_reason_matches "behind denial names the staleness" '7 commit'

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=1
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "behind_by 1 denies (the boundary: one commit behind is not current)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFLICTING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "mergeable CONFLICTING denies"
assert_reason_matches "CONFLICTING denial names the conflict" 'conflict'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"cccccccccccccccccccccccccccccccccccccccc","isDraft":true,"mergeable":"BLOCKED","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "an unrecognized mergeable value denies (fail closed on an enum the guard does not know)" 'could not be confirmed'

echo "### REQ-C1.1 / REQ-C1.3 — UNKNOWN is re-queried once, then denies wait-and-retry"

reset_stub_env
STUB_VIEW_JSON=$VIEW_UNKNOWN STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "mergeable UNKNOWN denies after the bounded re-query"
assert_reason_matches "UNKNOWN denial names wait-and-retry" 'wait'
assert_reason_matches "UNKNOWN denial rules a fetch out explicitly (it cannot advance a server-side computation)" 'do not fetch'
assert_reason_lacks "UNKNOWN denial prescribes no fetch command as the remedy" 'run .*fetch|git fetch'
if [ "$(pr_view_calls)" = 2 ]; then
  pass "UNKNOWN re-queries \`gh pr view\` exactly once more before denying"
else
  fail "UNKNOWN should issue exactly 2 pr-view calls, saw $(pr_view_calls)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_UNKNOWN STUB_VIEW_JSON2=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_defer "UNKNOWN that resolves to MERGEABLE on the re-query defers (no spurious deny)"

echo "### REQ-C1.3 — fail closed on any doubt"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_VIEW_RC=1
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a failing \`gh pr view\` denies"
assert_reason_matches "the failing-query denial names the query, not a downstream symptom" 'query for this pull request failed'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_VIEW_RC=124
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a timed-out \`gh pr view\` denies"
assert_reason_matches "the timeout denial reads as a stall, not a malformed answer" 'did not finish'

reset_stub_env
STUB_VIEW_JSON='' STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "an empty \`gh pr view\` answer denies"
assert_reason_matches "the empty-answer denial names the empty answer" 'returned nothing'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main"' STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a malformed \`gh pr view\` answer denies"
assert_reason_matches "the malformed-answer denial names the unreadable draft state" 'draft state is missing or malformed'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_RC=1
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a failing compare call denies"
assert_reason_matches "the compare-failure denial names the compare endpoint" 'compare endpoint could not be reached'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_RC=124
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a timed-out compare call denies"
assert_reason_matches "the compare-timeout denial reads as a stall" 'compare query did not finish'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT='not-a-number'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "an unreadable behind_by denies"
assert_reason_matches "the unreadable-behind_by denial names the unreadable count" 'no readable'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING
run_hook "$(bash_payload 'gh pr ready 42')" gh
assert_deny_because "a missing gh binary denies" 'gh CLI is not on PATH'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING
run_hook "$(bash_payload 'gh pr ready 42')" jq
assert_deny "a missing \`jq\` binary denies a payload that still evidences a flip"

reset_stub_env
run_hook "$(bash_payload 'ls -la')" jq
assert_defer "a missing \`jq\` binary defers a payload with no ready-flip evidence (no session brick)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING
run_hook "$(bash_payload 'gh pr ready 42')" timeout gtimeout
assert_deny "no timeout/gtimeout binary denies rather than making an unbounded call"
assert_reason_matches "the unbounded-call denial names the remedy" 'coreutils|timeout'

reset_stub_env
run_hook ''
assert_deny "an empty PreToolUse payload denies"

reset_stub_env
run_hook 'gh pr ready 42 {not json'
assert_deny "an unparseable payload that evidences a flip denies"

reset_stub_env
run_hook '{not json at all'
assert_defer "an unparseable payload with no flip evidence defers"

reset_stub_env
run_hook "$(jq -n '{tool_name:"Bash", tool_input:{command:{"verb":"ls -la"}}, cwd:"/tmp"}')"
assert_defer "a non-string Bash command with no flip evidence in its text defers"

reset_stub_env
run_hook "$(jq -n '{tool_name:"Bash", tool_input:{command:["gh","pr","ready","5"]}, cwd:"/tmp"}')"
assert_deny "a malformed Bash command whose raw text evidences a flip denies"

echo "### REQ-C1.3 — an answer the guard cannot trust field-by-field"

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"not-a-hex-oid","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a head commit id that is not plain hex denies" 'hex object id'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"../../etc","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a base branch name the guard will not put in a compare URL denies" 'compare query'

reset_stub_env
STUB_VIEW_JSON='{"isDraft":true,"mergeable":"MERGEABLE"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "an answer missing the fields the predicate needs denies" 'incomplete answer'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a PR URL with no /pull/ segment denies" 'URL GitHub returned could not be read'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/not-a-number"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a PR URL not ending in a number denies" 'does not end in a pull-request number'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/ac me/widgets/pull/42"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a PR URL with an unreadable owner denies" 'no readable repository owner'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/wid gets/pull/42"}'
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a PR URL with an unreadable repository denies" 'no readable repository'

echo "### REQ-C1.8 — --undo, already-ready no-ops, and non-transitions are never blocked"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready --undo')"
assert_defer "\`gh pr ready --undo\` defers"
if [ "$(gh_calls)" = 0 ]; then
  pass "\`--undo\` issues no network call at all"
else
  fail "\`--undo\` should issue no network call, saw $(gh_calls)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready 42 --undo')"
assert_defer "\`gh pr ready 42 --undo\` defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_ALREADY_READY STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready 42')"
assert_defer "Bash surface: an already-ready PR defers even when stale and conflicting"

reset_stub_env
STUB_VIEW_JSON=$VIEW_ALREADY_READY STUB_COMPARE_OUT=9
run_hook "$(mcp_payload acme widgets 42 false)"
assert_defer "MCP surface: an already-ready PR defers (symmetric with the Bash gate)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(mcp_payload acme widgets 42)"
assert_defer "MCP \`update_pull_request\` with no draft field defers (non-transition)"
if [ "$(gh_calls)" = 0 ]; then
  pass "a non-transitioning MCP call issues no network call"
else
  fail "a non-transitioning MCP call should issue no network call, saw $(gh_calls)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(mcp_payload acme widgets 42 true)"
assert_defer "MCP \`draft: true\` (re-drafting) defers"

echo "### REQ-C1.6 / REQ-A1.3 — both surfaces, flipper-agnostic"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=3
run_hook "$(mcp_payload acme widgets 42 false)"
assert_deny "MCP draft->ready on a stale PR denies"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(mcp_payload acme widgets 42 false)"
assert_defer "MCP draft->ready on a conforming PR defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=3
run_hook "$(bash_payload 'gh pr ready 42 --repo acme/widgets')"
assert_deny "gauntlet-shaped \`gh pr ready <n> --repo <owner>/<repo>\` on a stale PR denies"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=3
run_hook "$(bash_payload 'gh pr ready')"
assert_deny "a bare \`gh pr ready\` (current branch's PR) on a stale PR denies"

reset_stub_env
run_hook "$(jq -n '{tool_name:"Read", tool_input:{file_path:"/tmp/x"}}')"
assert_defer "a non-Bash, non-MCP tool defers"

echo "### REQ-C1.10 — the leading \`cd <path> &&\` worktree form"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=4
run_hook "$(bash_payload "cd $WORK/sub && gh pr ready 42")"
assert_deny "\`cd <path> && gh pr ready <n>\` on a stale PR is gated, not slipped"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "cd $WORK/sub && gh pr ready 42")"
assert_defer "\`cd <path> && gh pr ready <n>\` on a conforming PR defers (no spurious deny on the common worker form)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "echo hi && cd $WORK/sub && gh pr ready")"
assert_deny "a multi-step command whose bare flip could target any repo denies (ambiguous)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'echo hi && gh pr ready 42 --repo acme/widgets')"
assert_defer "a multi-step command whose flip names both repo and number is unambiguous and defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
run_hook "$(bash_payload 'gh pr ready 42 >/dev/null')"
assert_deny "a redirect does not slip the gate"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
run_hook "$(bash_payload '2>/dev/null gh pr ready 42')"
assert_deny_because "a leading fd-redirect prefix (2>/dev/null) does not slip the gate" 'commit\(s\) behind'

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
run_hook "$(bash_payload '>/dev/null 2>&1 gh pr ready 42')"
assert_deny_because "a stacked prefix redirect does not slip the gate" 'commit\(s\) behind'

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
run_hook "$(bash_payload "cd $WORK && 2>/dev/null gh pr ready 42")"
assert_deny_because "an fd-redirect prefix behind a cd does not slip the gate" 'commit\(s\) behind'

# A QUOTED all-digit word is a real argument in bash, not an fd designator.
# Reason alone cannot pin this (dropping "42" leaves a bare flip that also
# denies as behind), so the ARGV is what proves the selector survived.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
run_hook "$(bash_payload 'gh pr ready "42" >/dev/null')"
assert_deny_because "a quoted all-digit selector stays an argument" 'commit\(s\) behind'
if grep -q $'\tpr\tview\t42\t' "$STATE/argv.log"; then
  pass "the quoted selector still reached gh as the PR number, not dropped as an fd designator"
else
  fail "the quoted selector was dropped: argv was $(cat "$STATE/argv.log")"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload '2>/dev/null ls -la')"
assert_defer "an fd-redirect prefix on an unrelated command still defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
run_hook "$(bash_payload 'gh pr ready --repo --undo')"
assert_deny "--undo consumed as a --repo VALUE is not mistaken for a re-draft"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=2
# shellcheck disable=SC2016  # literal, unexpanded by design: that is the assertion
run_hook "$(bash_payload 'echo "$(gh pr ready 42)"')"
assert_deny "a command-substitution form the tokenizer will not analyze denies (fail closed)"

echo "### REQ-C1.9 — selector resolution, grammar validation, and injection safety"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 --repo acme/widgets')"
if grep -q $'\tpr\tview\t42\t--repo\tacme/widgets\t--json\t' "$STATE/argv.log"; then
  pass "the explicit selector reaches \`gh\` as exact, separate argv (query shape pinned)"
else
  fail "expected argv 'pr view 42 --repo acme/widgets --json ...', got: $(cat "$STATE/argv.log")"
fi
if grep -q 'mergeStateStatus' "$STATE/argv.log"; then
  fail "the guard requested mergeStateStatus — currency must not be keyed on it (D-3)"
else
  pass "the guard never requests mergeStateStatus (D-3 regression pin)"
fi
if grep -q $'\tapi\trepos/acme/widgets/compare/main\.\.\.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$STATE/argv.log"; then
  pass "the compare call targets <base>...<headRefOid> on the resolved repo (query shape pinned)"
else
  fail "compare argv not as expected, got: $(cat "$STATE/argv.log")"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
# shellcheck disable=SC2016  # literal, unexpanded by design: that is the assertion
run_hook "$(bash_payload 'gh pr ready $(touch '"$STATE"'/sentinel-subst)')"
assert_deny "a command-substitution selector denies"
if [ -e "$STATE/sentinel-subst" ]; then
  fail "the hostile selector EXECUTED — REQ-C1.5 violation"
else
  pass "the hostile selector was never executed (inert data)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "gh pr ready '1 --repo attacker/clean'")"
assert_deny "a quoted option-bearing selector fails grammar validation and denies"
if [ "$(gh_calls)" = 0 ]; then
  pass "grammar validation rejects the selector BEFORE any \`gh\` call runs"
else
  fail "the guard queried gh with an invalid selector (saw $(gh_calls) calls)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready my-branch')"
assert_deny "a non-numeric positional selector denies (grammar: a PR is digits)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 43')"
# Reason-pinned: the P9 URL cross-check would also deny this fixture (the stub
# answers about PR 42 while the second positional makes the selector 43), so a
# bare deny let the multiple-target refusal be deleted with the suite green.
assert_deny_because "two positional targets deny (ambiguous)" 'more than one target'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 --hostname evil.example')"
assert_deny_because "an unrecognized option denies (it could redirect the flip)" 'does not recognize'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 && gh pr ready 43')"
assert_deny "two ready-flips in one command deny (unattributable)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 --repo acme/not-widgets')"
assert_deny "a PR that resolves to a different repo than the call named denies"

reset_stub_env
run_hook "$(jq -n '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:"acme", repo:"wid gets", pullNumber:42, draft:false}}')"
assert_deny_because "an MCP repo outside GitHub charset denies" 'no valid repository'

reset_stub_env
run_hook "$(mcp_payload acme widgets '"42"' false)"
assert_deny_because "an MCP pullNumber that is a string, not a number, denies" 'no valid pull-request number'

reset_stub_env
run_hook "$(mcp_payload acme widgets 42.5 false)"
assert_deny_because "a non-integral MCP pullNumber denies" 'no valid pull-request number'

reset_stub_env
run_hook "$(mcp_payload 'acme/../evil' widgets 42 false)"
assert_deny_because "an MCP owner outside GitHub charset denies" 'no valid repository owner'

reset_stub_env
run_hook "$(jq -n '{tool_name:"mcp__github__update_pull_request", tool_input:"not-an-object"}')"
assert_deny_because "a malformed MCP payload denies (jurisdiction is the tool name)" 'payload is malformed'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(mcp_payload acme widgets 42 false)"
if grep -q $'\tpr\tview\t42\t--repo\tacme/widgets\t' "$STATE/argv.log"; then
  pass "the MCP selector is queried against exactly that owner/repo/number"
else
  fail "MCP argv not as expected, got: $(cat "$STATE/argv.log")"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 --repo')"
assert_deny_because "--repo with no value denies" 'with no value'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 --repo not-an-owner-repo')"
assert_deny_because "a --repo value that is not <owner>/<repo> denies" 'not a valid'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 --repo acme/widgets && gh pr ready 43 --repo acme/widgets')"
assert_deny_because "two fully-qualified ready-flips in one command deny (unattributable)" 'more than one'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready' '/no/such/directory')"
assert_deny_because "a bare flip whose working directory does not exist denies" 'no usable working directory'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(jq -n --arg w "$WORK" '{tool_name:"Bash", tool_input:{command:"gh pr ready 42"}, cwd:{"path":$w}}')"
assert_deny_because "a Bash payload with a malformed cwd denies" 'malformed cwd'

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
LONG_PAD="$(printf 'x%.0s' $(seq 1 9000))"
run_hook "$(bash_payload "gh pr ready 42 # $LONG_PAD")"
assert_deny_because "a command too long to analyze that names a ready-flip denies" 'too long to analyze'

echo "### REQ-C1.5 — the server's answer is inert data too"

reset_stub_env
# shellcheck disable=SC2016  # literal, unexpanded by design: that is the assertion
STUB_VIEW_JSON='{"baseRefName":"$(touch '"$STATE"'/sentinel-base)","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a metacharacter-laden base branch name in the server's answer denies"
if [ -e "$STATE/sentinel-base" ]; then
  fail "a server-supplied field EXECUTED — REQ-C1.5 violation"
else
  pass "the server-supplied field was compared as inert data, never executed"
fi

echo "### REQ-K1.3 — echo safety on emitted untrusted content"

reset_stub_env
STUB_VIEW_JSON=$(jq -nc '{baseRefName:("re" + ([27] | implode) + "[31mlease"), headRefOid:"ffffffffffffffffffffffffffffffffffffffff", isDraft:true, mergeable:"CONFLICTING", url:"https://github.com/acme/widgets/pull/42"}')
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "a branch name carrying a terminal escape still denies"
if printf '%s' "$(reason)" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  fail "the denial reason emitted a control byte (REQ-K1.3 violation)"
else
  pass "the denial reason is stripped of non-printable bytes"
fi
if printf '%s' "$(reason)" | grep -q '31mlease'; then
  pass "the sanitized branch text is still shown (stripped, not dropped)"
else
  fail "the branch name vanished from the reason entirely: $(reason)"
fi

echo "### REQ-C1.2 / REQ-D1.4 — deny-emitting, deterministic, no LLM or API in the decision path"

if grep -Eqi 'anthropic|openai|api\.claude|claude -p|\bcurl\b|\bwget\b|https?://[a-z]' "$HOOK"; then
  fail "the guard's source contains a model/API/network invocation (REQ-D1.4)"
else
  pass "the guard's source contains no model/API/network invocation (grep-level)"
fi

if grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"(allow|ask)"|permissionDecision:"(allow|ask)"' "$HOOK"; then
  fail "the guard's source can emit allow/ask — it must only deny or defer"
else
  pass "the guard's source can only emit deny (never allow/ask)"
fi

# D-5: the guard reads no local git state. Comment lines and `emit_deny`
# argument strings are excluded because both are TEXT — a remedy sentence shown
# to the operator, never executed. What proves that distinction is real is the
# behavioral fixture below, whose `git` stub drops a sentinel the assertions
# require to be absent; this grep is the cheap structural companion to it.
if grep -vE '^[[:space:]]*#' "$HOOK" \
  | grep -v 'emit_deny' \
  | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*git[[:space:]]+[a-z]'; then
  fail "the guard invokes a local git command (D-5 violation)"
else
  pass "the guard invokes no local git command (D-5)"
fi

# Behavioral counterpart to the greps, with a POSITIVE CONTROL so it cannot
# pass vacuously: the same fixture asserts the stubbed `gh` WAS reached, so the
# "no git/curl/claude" assertion is made about a decision path that actually ran
# (the test-tower-command-guard.sh no-LLM-stub-reachability precedent).
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny "behavioral no-LLM fixture reaches a decision"
assert_no_sentinels "behavioral: no git/curl/wget/claude in the decision path"
if [ "$(gh_calls)" -ge 2 ]; then
  pass "positive control: the stubbed \`gh\` call site was actually traversed"
else
  fail "positive control failed: the guard made $(gh_calls) gh calls, so the no-LLM assertion would be vacuous"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload 'gh pr ready 42')"
FIRST=$OUT
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload 'gh pr ready 42')"
if [ "$FIRST" = "$OUT" ]; then
  pass "repeated runs on identical input are byte-identical (deterministic)"
else
  fail "the guard is non-deterministic: '$FIRST' vs '$OUT'"
fi

echo "### REQ-C1.3 — a non-matching Bash command costs nothing"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'ls -la /tmp')"
assert_defer "an unrelated Bash command defers"
if [ "$(gh_calls)" = 0 ]; then
  pass "an unrelated Bash command issues no network call (zero cost fast path)"
else
  fail "an unrelated Bash command issued $(gh_calls) network call(s)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'echo "gh pr ready 5"')"
assert_defer "a quoted mention of the command inside another verb defers (no spurious deny)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'grep -rn "gh pr ready" scripts/')"
assert_defer "grepping for the command text defers (no spurious deny)"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
# shellcheck disable=SC2016  # literal, unexpanded by design: that is the assertion
run_hook "$(bash_payload 'echo "$(date)" && ls')"
assert_defer "a command-substitution command with no flip evidence defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
# shellcheck disable=SC2016  # literal, unexpanded by design: that is the assertion
run_hook "$(bash_payload 'echo `date`')"
assert_defer "a backtick command with no flip evidence defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload '{ echo hi; }')"
assert_defer "a brace-grouped command with no flip evidence defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload "echo $LONG_PAD")"
assert_defer "an over-long command with no flip evidence defers"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(jq -n '{tool_name:"Bash", tool_input:{command:"ls -la"}, cwd:{"path":"/tmp"}}')"
assert_defer "a malformed cwd with no flip evidence defers"

echo "### Panel-pass regressions — bash-word-splitting divergences are bypasses"
# Root cause shared by these: the guard re-implements bash word splitting, so
# every divergence from bash's real behaviour is a BYPASS, not a cosmetic bug.
# Each fixture below is reason- or argv-pinned, never a bare deny, so the
# specific branch cannot be deleted with the suite still green.

# P3 — backslash-newline is a line continuation: bash joins `rea\<nl>dy` into
# the single word `ready` before word splitting.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload "$(printf 'gh pr rea\\\ndy 42')")"
assert_deny_because "a backslash-newline continuation inside the verb does not slip the gate" 'commit\(s\) behind'
if grep -q $'\tpr\tview\t42\t' "$STATE/argv.log"; then
  pass "the continuation rejoined into $(ready) and PR 42 was queried"
else
  fail "continuation not rejoined: argv was $(cat "$STATE/argv.log")"
fi

# P4 — simple-command prefixes and pre-subcommand global flags.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'X=1 gh pr ready 42')"
assert_deny_because "an assignment prefix (X=1 gh pr ready) does not slip the gate" 'commit\(s\) behind'

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'command gh pr ready 42')"
assert_deny_because "a command prefix does not slip the gate" 'commit\(s\) behind'

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'exec gh pr ready 42')"
assert_deny_because "an exec prefix does not slip the gate" 'commit\(s\) behind'

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'gh -R acme/widgets pr ready 42')"
assert_deny_because "a global -R before the subcommand does not slip the gate" 'commit\(s\) behind'
if grep -q $'\tpr\tview\t42\t--repo\tacme/widgets\t' "$STATE/argv.log"; then
  pass "the pre-subcommand --repo was carried into the query argv"
else
  fail "pre-subcommand --repo lost: argv was $(cat "$STATE/argv.log")"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'gh --repo=acme/widgets pr ready 42')"
assert_deny_because "a global --repo= before the subcommand does not slip the gate" 'commit\(s\) behind'

# A word that merely LOOKS like an assignment must stay an argument.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'grep a=b file')"
assert_defer "an assignment-shaped argument to another verb still defers"

# P1 — a cd prefix may only move the query cwd for operators that run it in the
# CURRENT shell. The two directories are distinguished by their `gh pr view`
# answer, not by behind_by: the compare call is repo-absolute and correctly runs
# without a cwd, so it cannot carry the signal.
#   conf/  -> isDraft false (already ready)  => DEFER if queried
#   stale/ -> isDraft true + behind          => DENY  if queried
# Each fixture also asserts the queried cwd directly, so a future change that
# gets the right verdict for the wrong reason still fails.
printf '%s' "$VIEW_ALREADY_READY" >"$SANDBOX/conf/view.json"
printf '%s' "$VIEW_BEHIND" >"$SANDBOX/stale/view.json"

reset_stub_env
STUB_COMPARE_OUT=6
run_hook "$(bash_payload "cd $SANDBOX/conf && gh pr ready" "$SANDBOX/stale")"
assert_defer "cd A && gh pr ready resolves to A (the cd really moves the cwd)"
assert_queried_in "cd A && gh pr ready queried A" "$SANDBOX/conf"

reset_stub_env
STUB_COMPARE_OUT=6
run_hook "$(bash_payload "cd $SANDBOX/conf ; gh pr ready" "$SANDBOX/stale")"
assert_defer "cd A ; gh pr ready resolves to A"
assert_queried_in "cd A ; gh pr ready queried A" "$SANDBOX/conf"

reset_stub_env
STUB_COMPARE_OUT=6
run_hook "$(bash_payload "cd $SANDBOX/conf | gh pr ready" "$SANDBOX/stale")"
assert_deny_because "cd A | gh pr ready does not inherit A (the cd ran in a subshell)" 'commit\(s\) behind'
assert_queried_in "cd A | gh pr ready queried the payload cwd, not A" "$SANDBOX/stale"

reset_stub_env
STUB_COMPARE_OUT=6
run_hook "$(bash_payload "cd $SANDBOX/conf & gh pr ready" "$SANDBOX/stale")"
assert_deny_because "cd A & gh pr ready does not inherit A (the cd ran in a subshell)" 'commit\(s\) behind'
assert_queried_in "cd A & gh pr ready queried the payload cwd, not A" "$SANDBOX/stale"

reset_stub_env
STUB_COMPARE_OUT=6
run_hook "$(bash_payload "cd $SANDBOX/conf || gh pr ready" "$SANDBOX/stale")"
assert_deny_because "cd A || gh pr ready does not inherit A (gh runs only if the cd failed)" 'commit\(s\) behind'
assert_queried_in "cd A || gh pr ready queried the payload cwd, not A" "$SANDBOX/stale"

# P12 — a quoted redirect target must not make a conforming flip unanalyzable.
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 >"ready output.log"')"
assert_defer "a quoted redirect target does not falsely deny a conforming flip"

reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "gh pr ready 42 >'single quoted.log'")"
assert_defer "a single-quoted redirect target does not falsely deny a conforming flip"

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'gh pr ready 42 >"ready output.log"')"
assert_deny_because "a quoted redirect target still does not slip a stale flip" 'commit\(s\) behind'

# P11 — --help and -h mutate nothing.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready --help')"
assert_defer "gh pr ready --help defers (it prints usage, it does not flip)"
if [ "$(gh_calls)" = 0 ]; then
  pass "--help issues no network call"
else
  fail "--help issued $(gh_calls) network call(s)"
fi

reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready -h')"
assert_defer "gh pr ready -h defers"

# P6 — a jq that is ON PATH but broken must still produce a decision.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=6
rm -f "$BIN/jq"
printf '#!/bin/sh\nexit 1\n' >"$BIN/jq"
chmod +x "$BIN/jq"
OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr ready 42"},"cwd":"/tmp"}' \
  | env -i PATH="$BIN" HOME="$SANDBOX" /bin/bash "$HOOK" bash 2>/dev/null)"
CODE=$?
assert_deny "a present-but-broken jq still emits a decision (never a silent fail-open)"
assert_reason_matches "the broken-jq denial names the jq failure" 'did not run'
rm -f "$BIN/jq"
ln -sf "$(command -v jq)" "$BIN/jq"

# P5 — head -c exits 0 when it TRUNCATES, so an over-cap payload must deny.
reset_stub_env
OUT="$({
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp","pad":"'
  /bin/bash -c 'printf "%0.sx" $(seq 1 2000050)'
  printf '%s' '"}'
} | env -i PATH="$BIN" HOME="$SANDBOX" /bin/bash "$HOOK" bash 2>/dev/null)"
CODE=$?
assert_deny "a payload larger than the read cap denies (truncation is detected)"
assert_reason_matches "the over-cap denial names the size" 'larger than'

# P7 — MCP jurisdiction is the MATCHER, which only the wiring knows.
reset_stub_env
RG_SURFACE=mcp run_hook "$(jq -n '{tool_input:{owner:"acme",repo:"widgets",pullNumber:42,draft:false}}')"
assert_deny_because "a tool_name-less payload on the MCP matcher denies" 'could not be parsed'

reset_stub_env
RG_SURFACE=bash run_hook "$(jq -n '{tool_input:{owner:"acme",repo:"widgets",pullNumber:42,draft:false}}')"
assert_defer "the same payload on the Bash matcher defers (no flip evidence in its text)"

# P8 — isDraft must be a JSON boolean, not any scalar that renders as "false".
reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","isDraft":"false","mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "isDraft as the STRING false denies (only a real boolean defers)" 'draft state is missing or malformed'

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","isDraft":1,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=6
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "isDraft as a NUMBER denies" 'draft state is missing or malformed'

# P9 — the answer must be about the PR the call named.
reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/43"}'
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_deny_because "a conforming answer about a DIFFERENT PR number denies" 'not the one this call named'

# P13 — + and @ are valid in git ref names and unambiguous in a URL path.
reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"release+hotfix","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_defer "a conforming PR on a base branch containing + is not falsely denied"

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"team@release","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_defer "a conforming PR on a base branch containing @ is not falsely denied"

reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"release/2.0","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42')"
assert_defer "a conforming PR on a slashed base branch is not falsely denied"
if grep -q $'compare/release/2\.0\.\.\.' "$STATE/argv.log"; then
  pass "the slashed base ref reaches the compare path as-is (GitHub accepts it)"
else
  fail "slashed base ref not in the compare argv: $(cat "$STATE/argv.log")"
fi

echo "### REQ-C1.7 — global wiring in hooks/hooks.json"

if [ ! -f "$HOOKS_JSON" ]; then
  fail "hooks/hooks.json is missing"
else
  if jq -e '.hooks.PreToolUse' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "hooks.json declares a PreToolUse stack"
  else
    fail "hooks.json declares no PreToolUse stack"
  fi
  wired="$(jq -r '[.hooks.PreToolUse[]? | select([.hooks[]?.command // ""] | any(test("ready-guard\\.sh")))] | length' "$HOOKS_JSON" 2>/dev/null || echo 0)"
  if [ "${wired:-0}" -ge 2 ]; then
    pass "both PreToolUse matchers are wired to ready-guard.sh"
  else
    fail "expected 2 PreToolUse entries wired to ready-guard.sh, found ${wired:-0}"
  fi
  if jq -e '[.hooks.PreToolUse[]? | select([.hooks[]?.command // ""] | any(test("ready-guard\\.sh"))) | .matcher] | any(. == "Bash")' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "the Bash surface is wired"
  else
    fail "no PreToolUse Bash matcher for ready-guard.sh"
  fi
  if jq -e '[.hooks.PreToolUse[]? | select([.hooks[]?.command // ""] | any(test("ready-guard\\.sh"))) | .matcher] | any(test("mcp__github__update_pull_request"))' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "the MCP update_pull_request surface is wired"
  else
    fail "no PreToolUse MCP matcher for ready-guard.sh"
  fi
  if jq -e '[.hooks.PreToolUse[]? | .hooks[]?.command // ""] | any(test("\\$\\{CLAUDE_PLUGIN_ROOT\\}"))' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "the wiring references the script via \${CLAUDE_PLUGIN_ROOT} (marketplace-install-safe)"
  else
    fail "the ready-guard wiring does not use \${CLAUDE_PLUGIN_ROOT}"
  fi
fi

echo
echo "passes: $passes  failures: $failures"
[ "$failures" = 0 ]
