#!/bin/bash
# The merge-currency-guard bundle's completeness suite (Task 4): a
# mechanically-enforced expected-cell manifest over scripts/ready-guard.sh
# across both ready-flip surfaces (REQ-D1.1), the deny-over-allow OUTCOME
# against the worker-settings allow entry (REQ-D1.2, REQ-C1.4, D-6), the
# profile-independence of the wiring (REQ-C1.7), the enforcement-by-construction
# check over that wiring (REQ-A1.2), the flipper-agnostic shapes (REQ-A1.3),
# the sync script's required cells (REQ-D1.3), and the no-LLM negative
# assertions for both scripts (REQ-D1.4).
#
# WHY A MANIFEST. tests/test-ready-guard.sh asserts each branch of the guard in
# depth, but a suite can only assert the cells someone remembered to write, and
# a cell that is silently absent (UNKNOWN on the MCP surface, say) leaves the
# suite green. Here the expected cells are DECLARED first, a cell is registered
# only by the assertion that exercised it, and a meta-check fails the suite on
# any declared cell with no fixture, on any fixture claiming an undeclared
# cell, and on a key declared twice. The meta-check is itself given positive
# controls in all three directions, so the enforcement cannot pass vacuously.
#
# The sync cells overlap tests/test-converge-sync-main.sh, which owns the deep
# assertions for that script (every exit code, the abort-failed state, the
# autosetuprebase behavioral fixture, ssh BatchMode). The cells here are the
# REQ-D1.3 required set plus REQ-B1.3/B1.6's dirty-tree and idempotent-resume
# outcomes, pinned coarsely (exit code and reason) so the manifest can protect
# their existence; a case absent from this manifest is scoped to that suite,
# not uncovered.
#
# Contract under test is the harness's (tests/lib/ready-guard-harness.sh):
#   DENY  <=> exit 0 AND a deny decision with a non-empty reason.
#   DEFER <=> exit 0 AND empty stdout.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL
# The sync fixtures run the real git. An inherited repository override (a
# `git bisect run` or `rebase --exec` parent) would redirect their writes at
# the operator's checkout instead of the sandbox clones.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
WORKER_SETTINGS="$REPO_ROOT/config/worker-settings.json"
SYNC="$REPO_ROOT/scripts/converge-sync-main.sh"
TAB=$(printf '\t')

# shellcheck source=tests/lib/ready-guard-harness.sh
. "$REPO_ROOT/tests/lib/ready-guard-harness.sh"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

for f in "$SYNC" "$WORKER_SETTINGS" "$HOOKS_JSON"; do
  [ -f "$f" ] || {
    echo "FAIL: ${f#"$REPO_ROOT"/} is missing" >&2
    exit 1
  }
done
[ -x "$SYNC" ] || {
  echo "FAIL: scripts/converge-sync-main.sh is not executable" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# The expected-cell manifest. One line per cell: <key> <expect>.
#
# Guard cells are <state>/<surface>: the D-3 predicate outcomes (conforming,
# behind, conflicting), the REQ-C1.3 fail-closed causes (unknown, query-error,
# query-timeout, malformed-answer, compare-failure, unreadable-count,
# no-timeout-binary, missing-gh, missing-jq, malformed-payload), the REQ-C1.9
# selector refusal (invalid-selector), and the REQ-C1.8 never-gated transitions
# (undo, already-ready, non-transition). Every state is declared on BOTH
# surfaces. Where a state has no literal MCP spelling, the fixture drives the
# MCP-side analogue, the same transition expressed in that tool's fields
# (`draft: true` is the MCP undo; a call with no `draft` field is the MCP
# non-transition), and likewise for Bash (`gh pr edit` is the Bash
# non-transition). `deny` and `defer` are asserted from the guard's output.
#
# Sync cells are sync/<case>. `exit-N` is asserted against the sync script's
# exit code; `ok` means the fixture's own checks must all have held. Every
# expectation is enforced by assert_cell, which is also the only thing that
# registers a cell, so a cell cannot be registered without its assertion.
# ---------------------------------------------------------------------------
MANIFEST='
conforming/bash defer
conforming/mcp defer
behind/bash deny
behind/mcp deny
conflicting/bash deny
conflicting/mcp deny
unknown/bash deny
unknown/mcp deny
query-error/bash deny
query-error/mcp deny
query-timeout/bash deny
query-timeout/mcp deny
malformed-answer/bash deny
malformed-answer/mcp deny
compare-failure/bash deny
compare-failure/mcp deny
unreadable-count/bash deny
unreadable-count/mcp deny
no-timeout-binary/bash deny
no-timeout-binary/mcp deny
invalid-selector/bash deny
invalid-selector/mcp deny
missing-gh/bash deny
missing-gh/mcp deny
missing-jq/bash deny
missing-jq/mcp deny
malformed-payload/bash deny
malformed-payload/mcp deny
undo/bash defer
undo/mcp defer
already-ready/bash defer
already-ready/mcp defer
non-transition/bash defer
non-transition/mcp defer
sync/clean-merge exit-0
sync/conflict exit-5
sync/idempotent-resume exit-5
sync/fetch-failure exit-4
sync/dirty-tree exit-3
sync/no-pull-no-rebase ok
sync/no-llm ok
'

COVERED=''

# manifest_expect <manifest> <key> — print the expectation for a cell, or
# nothing when the cell is not declared.
manifest_expect() {
  printf '%s\n' "$1" | awk -v k="$2" '$1 == k { print $2; exit }'
}

# assert_cell <key> <label> [<actual>] — assert the manifest's expectation for
# the cell, then register it. deny/defer read the guard's last output; exit-N
# compares <actual> to N; ok requires <actual> to be the literal `ok`. An
# undeclared or unknown expectation fails here AND is registered, so the
# meta-check reports the undeclared key as well.
assert_cell() {
  local key=$1 label=$2 actual=${3:-} expect
  expect=$(manifest_expect "$MANIFEST" "$key")
  case $expect in
    deny) assert_deny "$label" ;;
    defer) assert_defer "$label" ;;
    exit-[0-9]*)
      if [ "$actual" = "${expect#exit-}" ]; then
        pass "$label"
      else
        fail "$label: expected exit ${expect#exit-}, got '${actual:-<none>}'"
      fi
      ;;
    ok)
      if [ "$actual" = ok ]; then
        pass "$label"
      else
        fail "$label: the fixture's own checks did not all hold"
      fi
      ;;
    '') fail "$label: fixture claims cell $key, which the manifest does not declare" ;;
    *) fail "$label: the manifest expects '$expect' for $key, which this suite cannot assert" ;;
  esac
  COVERED="$COVERED$key
"
}

# manifest_gaps <manifest> <covered> — print one line per declared cell with
# no fixture, per covered cell the manifest does not declare, and per key the
# manifest declares more than once; print nothing when all three are clean.
manifest_gaps() {
  local manifest=$1 covered=$2 key expect
  while read -r key expect; do
    [ -n "$key" ] || continue
    printf '%s\n' "$covered" | grep -qxF -- "$key" \
      || printf 'missing fixture: %s (expected %s)\n' "$key" "$expect"
  done <<EOF
$manifest
EOF
  printf '%s\n' "$covered" | sort -u | while IFS= read -r key; do
    [ -n "$key" ] || continue
    printf '%s\n' "$manifest" | awk -v k="$key" '$1 == k { f = 1 } END { exit !f }' \
      || printf 'undeclared cell: %s\n' "$key"
  done
  printf '%s\n' "$manifest" \
    | awk 'NF { n[$1]++ } END { for (k in n) if (n[k] > 1) printf "duplicate manifest key: %s\n", k }' \
    | sort
}

# run_mcp <payload> [removals...] — run_hook on the MCP matcher. The surface
# is set and restored explicitly rather than as a command prefix, so it is
# pinned on every bash the suite may run under.
run_mcp() {
  RG_SURFACE=mcp
  run_hook "$@"
  RG_SURFACE=bash
}
RG_SURFACE=bash

# assert_gh_calls <label> <count> — pin the exact number of stubbed gh calls.
assert_gh_calls() {
  local label=$1 want=$2
  if [ "$(gh_calls)" = "$want" ]; then
    pass "$label"
  else
    fail "$label: expected $want gh call(s), saw $(gh_calls)"
  fi
}

# assert_argv_has <label> <fixed-string> — the recorded gh argv carries it.
assert_argv_has() {
  local label=$1 want=$2
  if grep -qF -- "$want" "$STATE/argv.log" 2>/dev/null; then
    pass "$label"
  else
    fail "$label: '$want' not in the recorded argv: $(cat "$STATE/argv.log" 2>/dev/null)"
  fi
}

# assert_no_mergestatestatus <label> — the D-3 regression pin: the guard never
# asks for mergeStateStatus. Requires the log to exist so a run that never
# queried cannot pass this by having nothing to grep.
assert_no_mergestatestatus() {
  local label=$1
  if [ ! -f "$STATE/argv.log" ]; then
    fail "$label: no argv log was written"
  elif grep -q 'mergeStateStatus' "$STATE/argv.log"; then
    fail "$label: the guard requested mergeStateStatus (D-3 regression)"
  else
    pass "$label"
  fi
}

BASH_FLIP='gh pr ready 42'
GAUNTLET_FLIP='gh pr ready 42 --repo acme/widgets'
MCP_FLIP=$(mcp_payload acme widgets 42 false)

echo "### REQ-D1.1 — the decision matrix, cell by cell, on both surfaces"

echo "# conforming: behind_by 0 + MERGEABLE + draft"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell conforming/bash "bash: a conforming flip defers"
assert_gh_calls "bash: the conforming defer came after view + compare (not a jurisdiction bail-out)" 2
assert_no_mergestatestatus "bash: the conforming query never asks for mergeStateStatus"
assert_no_sentinels "bash: the conforming path invoked no git/curl/wget/claude"
run_mcp "$MCP_FLIP"
assert_cell conforming/mcp "mcp: a conforming draft->ready transition defers"
assert_gh_calls "mcp: the conforming defer came after view + compare" 2
assert_no_mergestatestatus "mcp: the conforming query never asks for mergeStateStatus"
assert_no_sentinels "mcp: the conforming path invoked no git/curl/wget/claude"

echo "# behind: behind_by > 0 on a base WITHOUT require-up-to-date (mergeStateStatus CLEAN)"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell behind/bash "bash: a worker-shaped flip on a behind PR denies"
assert_reason_matches "bash: the behind denial names the staleness" 'commit\(s\) behind'
assert_no_mergestatestatus "bash: currency is not keyed on mergeStateStatus (the CLEAN-but-behind pin)"
assert_no_sentinels "bash: the behind decision path invoked no git/curl/wget/claude"
assert_gh_calls "bash: positive control — the stubbed gh call site was traversed (view + compare)" 2
# REQ-A1.3: the gauntlet's distinct shape on the same behind payload, with the
# distinct part (--repo) pinned to have reached the query.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload "$GAUNTLET_FLIP")"
assert_cell behind/bash "bash: a gauntlet-shaped flip (--repo) on the same behind PR denies"
assert_reason_matches "bash: the gauntlet denial names the same staleness" 'commit\(s\) behind'
assert_argv_has "bash: the gauntlet's --repo selector reached gh as argv" "${TAB}--repo${TAB}acme/widgets${TAB}"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_mcp "$MCP_FLIP"
assert_cell behind/mcp "mcp: a draft->ready transition on a behind PR denies"
assert_reason_matches "mcp: the behind denial names the staleness" 'commit\(s\) behind'
assert_no_mergestatestatus "mcp: currency is not keyed on mergeStateStatus"
assert_no_sentinels "mcp: the behind decision path invoked no git/curl/wget/claude"
assert_gh_calls "mcp: positive control — the stubbed gh call site was traversed (view + compare)" 2

echo "# conflicting: mergeable CONFLICTING"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFLICTING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell conflicting/bash "bash: a conflicting PR denies"
assert_reason_matches "bash: the conflict denial names the conflict" 'mergeable is CONFLICTING'
assert_no_sentinels "bash: the conflict path invoked no git/curl/wget/claude"
run_mcp "$MCP_FLIP"
assert_cell conflicting/mcp "mcp: a conflicting PR denies"
assert_reason_matches "mcp: the conflict denial names the conflict" 'mergeable is CONFLICTING'
assert_no_sentinels "mcp: the conflict path invoked no git/curl/wget/claude"

echo "# unknown: mergeable UNKNOWN, re-queried once, then denied wait-and-retry"
reset_stub_env
STUB_VIEW_JSON=$VIEW_UNKNOWN STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell unknown/bash "bash: UNKNOWN denies after the bounded re-query"
assert_reason_matches "bash: the UNKNOWN denial is the post-re-query one" 'UNKNOWN after a re-query'
assert_reason_lacks "bash: the UNKNOWN denial prescribes no fetch" 'run .*fetch|git fetch'
assert_no_sentinels "bash: the UNKNOWN path invoked no git/curl/wget/claude"
if [ "$(pr_view_calls)" = 2 ]; then
  pass "bash: UNKNOWN re-queried gh pr view exactly once more"
else
  fail "bash: UNKNOWN should issue exactly 2 pr-view calls, saw $(pr_view_calls)"
fi
run_mcp "$MCP_FLIP"
assert_cell unknown/mcp "mcp: UNKNOWN denies after the bounded re-query"
assert_reason_matches "mcp: the UNKNOWN denial is the post-re-query one" 'UNKNOWN after a re-query'
assert_reason_lacks "mcp: the UNKNOWN denial prescribes no fetch" 'run .*fetch|git fetch'
assert_no_sentinels "mcp: the UNKNOWN path invoked no git/curl/wget/claude"
if [ "$(pr_view_calls)" = 2 ]; then
  pass "mcp: UNKNOWN re-queried gh pr view exactly once more (the re-query is not Bash-only)"
else
  fail "mcp: UNKNOWN should issue exactly 2 pr-view calls, saw $(pr_view_calls)"
fi

echo "# query-error: gh pr view exits non-zero"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_VIEW_RC=1
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell query-error/bash "bash: a failing gh pr view denies"
assert_reason_matches "bash: the query-error denial names the query" 'query for this pull request failed'
run_mcp "$MCP_FLIP"
assert_cell query-error/mcp "mcp: a failing gh pr view denies"
assert_reason_matches "mcp: the query-error denial names the query" 'query for this pull request failed'

echo "# query-timeout: gh pr view hits the bounded timeout"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_VIEW_RC=124
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell query-timeout/bash "bash: a timed-out gh pr view denies"
assert_reason_matches "bash: the timeout denial reads as a stall" 'did not finish'
run_mcp "$MCP_FLIP"
assert_cell query-timeout/mcp "mcp: a timed-out gh pr view denies"
assert_reason_matches "mcp: the timeout denial reads as a stall" 'did not finish'

echo "# malformed-answer: gh pr view answers with something unreadable"
reset_stub_env
STUB_VIEW_JSON='{"baseRefName":"main"' STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell malformed-answer/bash "bash: a malformed gh pr view answer denies"
assert_reason_matches "bash: the malformed-answer denial names the unreadable draft state" 'draft state is missing or malformed'
run_mcp "$MCP_FLIP"
assert_cell malformed-answer/mcp "mcp: a malformed gh pr view answer denies"
assert_reason_matches "mcp: the malformed-answer denial names the unreadable draft state" 'draft state is missing or malformed'
reset_stub_env
STUB_VIEW_JSON='' STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell malformed-answer/bash "bash: an empty gh pr view answer denies"
assert_reason_matches "bash: the empty-answer denial names the empty answer" 'returned nothing'
run_mcp "$MCP_FLIP"
assert_cell malformed-answer/mcp "mcp: an empty gh pr view answer denies"
assert_reason_matches "mcp: the empty-answer denial names the empty answer" 'returned nothing'

echo "# compare-failure: the compare endpoint errors"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_RC=1
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell compare-failure/bash "bash: a failing compare call denies"
assert_reason_matches "bash: the compare-failure denial names the compare endpoint" 'compare endpoint'
assert_no_sentinels "bash: the compare-failure path invoked no git/curl/wget/claude"
run_mcp "$MCP_FLIP"
assert_cell compare-failure/mcp "mcp: a failing compare call denies"
assert_reason_matches "mcp: the compare-failure denial names the compare endpoint" 'compare endpoint'
assert_no_sentinels "mcp: the compare-failure path invoked no git/curl/wget/claude"

echo "# unreadable-count: the compare endpoint returns no readable behind_by"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT='not-a-number'
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell unreadable-count/bash "bash: an unreadable behind_by denies"
assert_reason_matches "bash: the unreadable-count denial names it" 'no readable'
run_mcp "$MCP_FLIP"
assert_cell unreadable-count/mcp "mcp: an unreadable behind_by denies"
assert_reason_matches "mcp: the unreadable-count denial names it" 'no readable'

echo "# no-timeout-binary: neither timeout nor gtimeout on PATH"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")" timeout gtimeout
assert_cell no-timeout-binary/bash "bash: no bounding binary denies rather than making an unbounded call"
assert_reason_matches "bash: the unbounded-call denial names the remedy" 'coreutils|timeout'
assert_gh_calls "bash: no query was attempted without a bound" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_mcp "$MCP_FLIP" timeout gtimeout
assert_cell no-timeout-binary/mcp "mcp: no bounding binary denies rather than making an unbounded call"
assert_reason_matches "mcp: the unbounded-call denial names the remedy" 'coreutils|timeout'
assert_gh_calls "mcp: no query was attempted without a bound" 0

echo "# invalid-selector: grammar validation refuses before any gh call"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "gh pr ready '1 --repo attacker/clean'")"
assert_cell invalid-selector/bash "bash: an option-bearing selector denies"
assert_reason_matches "bash: the option-bearing denial is the selector grammar's" 'not a plain PR number'
assert_gh_calls "bash: the invalid selector never reached gh" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 43')"
assert_cell invalid-selector/bash "bash: an ambiguous two-target selector denies"
assert_reason_matches "bash: the ambiguous denial names the ambiguity" 'more than one target'
assert_gh_calls "bash: the ambiguous selector never reached gh" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_mcp "$(mcp_payload acme widgets '"42"' false)"
assert_cell invalid-selector/mcp "mcp: a string pullNumber denies"
assert_reason_matches "mcp: the invalid-selector denial names the selector" 'no valid pull-request number'
assert_gh_calls "mcp: the invalid selector never reached gh" 0
reset_stub_env
run_mcp "$(mcp_payload 'acme/../evil' widgets 42 false)"
assert_cell invalid-selector/mcp "mcp: an owner outside GitHub's charset denies"
assert_reason_matches "mcp: the invalid-owner denial is the owner grammar's" 'no valid repository owner'
assert_gh_calls "mcp: the invalid owner never reached gh" 0

echo "# missing-gh"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")" gh
assert_cell missing-gh/bash "bash: an absent gh denies"
assert_reason_matches "bash: the missing-gh denial names gh" 'gh CLI is not on PATH'
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_mcp "$MCP_FLIP" gh
assert_cell missing-gh/mcp "mcp: an absent gh denies"
assert_reason_matches "mcp: the missing-gh denial names gh" 'gh CLI is not on PATH'

echo "# missing-jq"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")" jq
assert_cell missing-jq/bash "bash: an absent jq denies a payload that evidences a flip"
assert_reason_matches "bash: the missing-jq denial names jq" 'jq is not on PATH'
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_mcp "$MCP_FLIP" jq
assert_cell missing-jq/mcp "mcp: an absent jq denies (the tool name is the flip evidence)"
assert_reason_matches "mcp: the missing-jq denial names jq" 'jq is not on PATH'

echo "# malformed-payload"
reset_stub_env
run_hook "$(jq -n '{tool_name:"Bash", tool_input:{command:["gh","pr","ready","42"]}, cwd:"/tmp"}')"
assert_cell malformed-payload/bash "bash: a non-string command whose raw text evidences a flip denies"
assert_reason_matches "bash: the malformed-command denial is the no-readable-command one" 'no readable command string'
reset_stub_env
run_hook ''
assert_cell malformed-payload/bash "bash: an empty PreToolUse payload denies"
assert_reason_matches "bash: the empty-payload denial names the empty payload" 'payload was empty'
reset_stub_env
run_mcp "$(jq -n '{tool_name:"mcp__github__update_pull_request", tool_input:"not-an-object"}')"
assert_cell malformed-payload/mcp "mcp: a non-object tool_input denies"
assert_reason_matches "mcp: the malformed denial names the malformed payload" 'payload is malformed'
reset_stub_env
run_mcp '{not json at all'
assert_cell malformed-payload/mcp "mcp: an unparseable payload on the MCP matcher denies"
assert_reason_matches "mcp: the unparseable denial names the parse failure" 'could not be parsed'

echo "# undo: the ready->draft direction is never gated"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready 42 --undo')"
assert_cell undo/bash "bash: --undo after the number defers even on a behind PR"
assert_gh_calls "bash: --undo issues no network call" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready --undo')"
assert_cell undo/bash "bash: the bare --undo form defers even on a behind PR"
assert_gh_calls "bash: the bare --undo issues no network call" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_mcp "$(mcp_payload acme widgets 42 true)"
assert_cell undo/mcp "mcp: draft:true (re-drafting) defers even on a behind PR"
assert_gh_calls "mcp: re-drafting issues no network call" 0

echo "# already-ready: isDraft false, stale AND conflicting on purpose"
reset_stub_env
STUB_VIEW_JSON=$VIEW_ALREADY_READY STUB_COMPARE_OUT=9
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell already-ready/bash "bash: an already-ready PR defers regardless of currency"
assert_gh_calls "bash: the already-ready defer came from reading the answer (one view, no compare)" 1
run_mcp "$MCP_FLIP"
assert_cell already-ready/mcp "mcp: an already-ready PR defers regardless of currency"
assert_gh_calls "mcp: the already-ready defer came from reading the answer (one view, no compare)" 1

echo "# non-transition: a PR edit that is not a draft->ready flip"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr edit 42 --title t')"
assert_cell non-transition/bash "bash: a non-ready gh pr subcommand defers"
assert_gh_calls "bash: a non-transition issues no network call" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_mcp "$(mcp_payload acme widgets 42)"
assert_cell non-transition/mcp "mcp: update_pull_request with no draft field defers"
assert_gh_calls "mcp: a non-transition issues no network call" 0

echo "### REQ-A1.2 — enforced by construction: the wiring, not prose, is what denies"

# stack_commands <hooks-json> <tool-name> — the PreToolUse commands Claude
# Code would run for <tool-name>, per the documented matcher rules: an absent
# or empty matcher applies to every tool; otherwise the matcher is an exact
# tool name or a regex matched against the whole name.
stack_commands() {
  jq -r --arg t "$2" '
    .hooks.PreToolUse[]?
    | (.matcher // "") as $m
    | select($m == "" or $m == $t or ($t | test("^(" + $m + ")$")))
    | .hooks[]?.command // empty' "$1"
}

# run_stack <hooks-json> <tool-name> <payload> — dispatch the payload through
# every matching command, collecting stdout into STACK_OUT (kept even when a
# command exits non-zero, so a deny emitted before a crash is not erased),
# the number run into STACK_N, and the number refused into STACK_SKIPPED.
# Only commands under the plugin's own scripts/ are run: this is a model of
# the dispatcher for the guard's benefit, not a way for any hooks.json edit to
# execute arbitrary commands under the test suite. Commands run with
# CLAUDE_PLUGIN_ROOT pointed at this checkout, on the harness's hermetic PATH
# plus a bash for the shebang, with the same stub knobs run_hook passes.
STACKBIN="$SANDBOX/stackbin"
mkdir -p "$STACKBIN"
ln -sf /bin/bash "$STACKBIN/bash"
run_stack() {
  local json=$1 tool=$2 payload=$3 cmd out
  STACK_OUT=''
  STACK_N=0
  STACK_SKIPPED=0
  rm -f "$STATE/viewcount" "$STATE"/sentinel-*
  : >"$STATE/argv.log"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # shellcheck disable=SC2016  # the literal spelling hooks.json uses
    case $cmd in
      '"${CLAUDE_PLUGIN_ROOT}"/scripts/'*) ;;
      *)
        STACK_SKIPPED=$((STACK_SKIPPED + 1))
        continue
        ;;
    esac
    STACK_N=$((STACK_N + 1))
    out=$(printf '%s' "$payload" \
      | env -i PATH="$STACKBIN:$BIN" HOME="$SANDBOX" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
        GH_ARGV_LOG="$STATE/argv.log" GH_STATE="$STATE" \
        PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
        STUB_VIEW_JSON="${STUB_VIEW_JSON:-}" STUB_VIEW_JSON2="${STUB_VIEW_JSON2:-}" \
        STUB_VIEW_RC="${STUB_VIEW_RC:-0}" STUB_VIEW_RC2="${STUB_VIEW_RC2:-}" \
        STUB_COMPARE_OUT="${STUB_COMPARE_OUT:-0}" STUB_COMPARE_RC="${STUB_COMPARE_RC:-0}" \
        /bin/bash -c "$cmd" 2>/dev/null) || :
    STACK_OUT="$STACK_OUT$out
"
  done <<EOF
$(stack_commands "$json" "$tool")
EOF
}
# stack_denies — any collected output carries a deny decision, in either the
# compact or the spaced JSON spelling (the harness's assert_deny tolerates
# both, and so must this).
stack_denies() {
  printf '%s' "$STACK_OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'
}

# The same wiring with every ready-guard command removed and everything else
# kept. The transform's exit status matters: a jq failure here would leave an
# empty file, zero commands, and a "nothing denied" that proves nothing.
UNWIRED_JSON="$SANDBOX/hooks-without-guard.json"
if jq '.hooks.PreToolUse |= map(.hooks |= map(select((.command // "") | test("ready-guard\\.sh") | not)))' \
  "$HOOKS_JSON" >"$UNWIRED_JSON" 2>/dev/null && jq -e . "$UNWIRED_JSON" >/dev/null 2>&1; then
  pass "the unwired hooks.json variant was produced"
else
  fail "the unwired hooks.json variant could not be produced (jq failed), so the unwired half below is not meaningful"
fi

for surface in bash mcp; do
  case $surface in
    bash)
      tool=Bash
      payload=$(bash_payload "$BASH_FLIP")
      ;;
    mcp)
      tool=mcp__github__update_pull_request
      payload=$MCP_FLIP
      ;;
  esac
  wired_n=$(stack_commands "$HOOKS_JSON" "$tool" | grep -c '' || true)
  guard_n=$(stack_commands "$HOOKS_JSON" "$tool" | grep -c 'ready-guard\.sh' || true)
  unwired_n=$(stack_commands "$UNWIRED_JSON" "$tool" | grep -c '' || true)
  if [ "$guard_n" -ge 1 ] && [ "$unwired_n" = $((wired_n - guard_n)) ]; then
    pass "$surface: the unwired variant dropped exactly the $guard_n guard command(s) and kept the other $unwired_n"
  else
    fail "$surface: expected the unwired variant to hold $wired_n - $guard_n commands, it holds $unwired_n"
  fi

  reset_stub_env
  STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=7
  run_stack "$HOOKS_JSON" "$tool" "$payload"
  if [ "$STACK_N" = "$wired_n" ] && [ "$STACK_SKIPPED" = 0 ] && stack_denies; then
    pass "$surface: the wired PreToolUse stack ($STACK_N command(s)) denies a BEHIND flip with no skill-prose step involved"
  else
    fail "$surface: the wired stack ran $STACK_N of $wired_n command(s), skipped $STACK_SKIPPED, and denied: $(stack_denies && echo yes || echo no) — '$STACK_OUT'"
  fi
  assert_no_sentinels "$surface: the wired stack's decision path invoked no git/curl/wget/claude"

  run_stack "$UNWIRED_JSON" "$tool" "$payload"
  if [ "$STACK_N" = "$unwired_n" ] && ! stack_denies; then
    pass "$surface: with ready-guard.sh removed from the wiring (the other $STACK_N command(s) still run) the same BEHIND flip is no longer denied by this bundle's machinery"
  else
    fail "$surface: unwired run: ran $STACK_N of $unwired_n command(s), denied: $(stack_denies && echo yes || echo no) — the guard is not the sole enforcement point this suite believes it is"
  fi
done

echo "### REQ-D1.2 / REQ-C1.4 / D-6 — deny-over-allow OUTCOME against the worker allow entry"

ALLOW_RULE='Bash(gh pr ready:*)'
if jq -e --arg r "$ALLOW_RULE" '.permissions.allow | any(. == $r)' "$WORKER_SETTINGS" >/dev/null 2>&1; then
  pass "worker-settings.json carries the $ALLOW_RULE allow entry (structural)"
else
  fail "worker-settings.json no longer carries $ALLOW_RULE — the outcome test below would be vacuous"
fi

# The permission-matcher oracle decides what the allow layer would do with the
# payload; the guard decides what the hook layer does with the same payload.
# The outcome pinned is the pair: allow-layer ALLOW, hook-layer DENY — and the
# hook layer is exercised both directly and through the wiring, so the deny
# is shown to reach a session that runs under this profile.
worker_deny=$(jq -r '.permissions.deny[]?' "$WORKER_SETTINGS")
worker_allow=$(jq -r '.permissions.allow[]?' "$WORKER_SETTINGS")
pm_rc=0
pm_load_rules "$worker_deny" '' "$worker_allow" || pm_rc=$?
if [ "$pm_rc" -eq 0 ]; then
  pass "the worker rule set loaded into the matcher oracle"
else
  fail "the worker rule set did not load into the matcher oracle (rc $pm_rc); the oracle assertions are skipped"
fi

for cmd in "$BASH_FLIP" "$GAUNTLET_FLIP"; do
  if [ "$pm_rc" -eq 0 ]; then
    if [ "$(pm_decide "$cmd")" = allow ]; then
      pass "the allow entry admits '$cmd' (the payload the guard must still deny)"
    else
      fail "the allow entry does not admit '$cmd' (oracle said '$(pm_decide "$cmd")'), so the outcome test is not testing precedence"
    fi
  fi
  reset_stub_env
  STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=7
  run_hook "$(bash_payload "$cmd")"
  assert_deny_because "OUTCOME: '$cmd' on a behind PR is denied by the guard with the allow entry present" 'commit\(s\) behind'
  run_stack "$HOOKS_JSON" Bash "$(bash_payload "$cmd")"
  if [ "$STACK_N" -ge 1 ] && stack_denies; then
    pass "OUTCOME: the wired stack denies '$cmd' on a behind PR too (the deny reaches a session under this profile)"
  else
    fail "OUTCOME: the wired stack did not deny '$cmd' on a behind PR: '$STACK_OUT'"
  fi
  reset_stub_env
  STUB_VIEW_JSON=$VIEW_CONFLICTING STUB_COMPARE_OUT=0
  run_hook "$(bash_payload "$cmd")"
  assert_deny_because "OUTCOME: '$cmd' on a conflicting PR is denied by the guard with the allow entry present" 'mergeable is CONFLICTING'
done

# The split D-6 chose: the allow entry is what lets a CONFORMING flip through.
# The guard contributes nothing to that decision (it never emits allow), so a
# conforming flip must find the guard silent.
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_defer "a conforming flip is left to the allow entry — the guard stays silent, never emits allow"

# The two layers compose in the other direction too: the worker profile denies
# the re-draft at the permission layer, which the guard never gates at all.
if [ "$pm_rc" -eq 0 ]; then
  if [ "$(pm_decide 'gh pr ready 42 --undo')" = deny ]; then
    pass "the worker profile's own deny covers the --undo form the guard leaves ungated"
  else
    fail "the worker profile no longer denies 'gh pr ready 42 --undo' (oracle said '$(pm_decide 'gh pr ready 42 --undo')')"
  fi
fi

echo "### REQ-C1.7 — the deny is not gated behind a settings profile"

# tests/test-ready-guard.sh pins the full wiring shape (both matchers, the
# CLAUDE_PLUGIN_ROOT reference). This block pins only the profile half: the
# guard rides the plugin-global hooks.json and the worker profile carries no
# copy, so a session under any profile (or none) meets the same guard.
if jq -e '[.hooks.PreToolUse[]? | .hooks[]?.command // ""] | any(test("ready-guard\\.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "the guard is wired in the plugin-global hooks.json"
else
  fail "the guard is not wired in hooks/hooks.json"
fi
# Asserted positively (`| not` under -e), so an unreadable file fails instead
# of reading as "not wired".
if jq -e '([.hooks.PreToolUse[]? | .hooks[]?.command // ""] | any(test("ready-guard\\.sh"))) | not' "$WORKER_SETTINGS" >/dev/null 2>&1; then
  pass "the guard is not scoped to the worker profile (worker-settings.json wires no copy of it)"
else
  fail "worker-settings.json wires a copy of the guard, or could not be read — a universal deny must not be profile-scoped"
fi

echo "### REQ-D1.3 / REQ-D1.4 — the sync script's required cells"

# gitq <dir> <args...> — git with a deterministic, signing-free identity.
gitq() {
  git -C "$1" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "${@:2}"
}

# sync_fixture <root> — a bare origin with one commit on main, a seed clone to
# advance it from, and a worker clone on its own task branch with a local
# identity so the script's own merge can commit.
sync_fixture() {
  git -c init.defaultBranch=main init -q --bare "$1/origin.git"
  git clone -q "$1/origin.git" "$1/seed" 2>/dev/null
  printf 'base\n' >"$1/seed/shared.txt"
  gitq "$1/seed" add -A
  gitq "$1/seed" commit -q -m base
  gitq "$1/seed" branch -M main
  gitq "$1/seed" push -q origin main
  git clone -q -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false \
    "$1/origin.git" "$1/worker" 2>/dev/null
  gitq "$1/worker" checkout -q -b task
}

# advance_main <root> <file> <content> — land a commit on origin/main.
advance_main() {
  printf '%s\n' "$3" >"$1/seed/$2"
  gitq "$1/seed" add -A
  gitq "$1/seed" commit -q -m "advance $2"
  gitq "$1/seed" push -q origin main
}

# Every sync run below goes through PATH with the sentinel stubs FIRST, so any
# curl/wget/claude the script reached for on any path (success, conflict,
# fetch failure, dirty tree) would have hit a sentinel. The control run proves
# the sentinels can fire at all before their absence is trusted.
SENT="$SANDBOX/sentbin"
mkdir -p "$SENT"
for t in curl wget claude; do
  printf '#!/bin/sh\n: >"%s/sync-sentinel-%s"\nexit 97\n' "$STATE" "$t" >"$SENT/$t"
  chmod +x "$SENT/$t"
done
SYNC_PATH="$SENT:$PATH"
"$SENT/curl" >/dev/null 2>&1 || :
if [ -e "$STATE/sync-sentinel-curl" ]; then
  pass "sync/no-llm: control — a sentinel stub drops its marker when invoked"
  rm -f "$STATE"/sync-sentinel-*
else
  fail "sync/no-llm: control — the sentinel stubs cannot drop a marker, so their absence below would prove nothing"
fi
no_llm_ok=ok

SYNCROOT="$SANDBOX/sync"
mkdir -p "$SYNCROOT"

# sync/clean-merge — a branch with its own commit takes origin/main's advance
# by merge; the advanced commit is in its history and its own commit survives
# (no rewrite).
r="$SYNCROOT/clean"
mkdir -p "$r"
sync_fixture "$r"
base=$(gitq "$r/worker" rev-parse HEAD)
printf 'worker work\n' >"$r/worker/worker.txt"
gitq "$r/worker" add -A
gitq "$r/worker" commit -q -m "worker commit"
own=$(gitq "$r/worker" rev-parse HEAD)
if [ "$own" != "$base" ]; then
  pass "sync/clean-merge: the worker's own commit exists (so its survival below is a real check)"
else
  fail "sync/clean-merge: the worker commit was not created; the survival check would be vacuous"
fi
advance_main "$r" newfile.txt "from main"
adv=$(gitq "$r/seed" rev-parse HEAD)
rc=0
out=$(PATH="$SYNC_PATH" "$SYNC" "$r/worker" 2>"$r/stderr") || rc=$?
assert_cell sync/clean-merge "sync/clean-merge: a clean origin/main advance exits 0" "$rc"
[ "$rc" -eq 0 ] || fail "sync/clean-merge: stderr was: $(tr '\n' ' ' <"$r/stderr")"
case $out in
  "sync${TAB}merged${TAB}"*) pass "sync/clean-merge: the run reports a merge (positive control: the decision path ran)" ;;
  *) fail "sync/clean-merge: expected a sync<TAB>merged record, got '$out'" ;;
esac
if gitq "$r/worker" merge-base --is-ancestor "$adv" HEAD; then
  pass "sync/clean-merge: the advanced origin/main commit is in the branch history"
else
  fail "sync/clean-merge: the advanced commit did not land"
fi
if gitq "$r/worker" merge-base --is-ancestor "$own" HEAD; then
  pass "sync/clean-merge: the worker's own commit survived (a merge, not a rebase)"
else
  fail "sync/clean-merge: the worker's own commit was rewritten"
fi

# sync/conflict — an unresolvable conflict exits 5 with the merge-conflict
# reason and leaves no MERGE_HEAD behind; sync/idempotent-resume — running
# it again on that clean tree re-attempts and reports the same, never a
# lingering-merge wedge (REQ-B1.3).
r="$SYNCROOT/conflict"
mkdir -p "$r"
sync_fixture "$r"
printf 'worker side\n' >"$r/worker/shared.txt"
gitq "$r/worker" add -A
gitq "$r/worker" commit -q -m "worker edits shared.txt"
advance_main "$r" shared.txt "main side"
rc=0
err=$(PATH="$SYNC_PATH" "$SYNC" "$r/worker" 2>&1 >/dev/null) || rc=$?
assert_cell sync/conflict "sync/conflict: an unresolvable conflict exits 5" "$rc"
case $err in
  *merge-conflict*) pass "sync/conflict: the reason names the conflict" ;;
  *) fail "sync/conflict: the reason does not name merge-conflict: $err" ;;
esac
if [ ! -f "$r/worker/.git/MERGE_HEAD" ]; then
  pass "sync/conflict: the merge was aborted (no MERGE_HEAD), so a resume re-attempts cleanly"
else
  fail "sync/conflict: MERGE_HEAD survived — the tree is wedged"
fi
rc=0
err=$(PATH="$SYNC_PATH" "$SYNC" "$r/worker" 2>&1 >/dev/null) || rc=$?
assert_cell sync/idempotent-resume "sync/idempotent-resume: re-invoking after the aborted conflict exits 5 again" "$rc"
case $err in
  *merge-conflict*) pass "sync/idempotent-resume: the re-attempt reports the conflict, not a lingering merge" ;;
  *) fail "sync/idempotent-resume: the re-attempt reported something else: $err" ;;
esac

# sync/fetch-failure — an unreachable remote exits 4 with the fetch reason,
# never misreported as a conflict.
r="$SYNCROOT/fetch"
mkdir -p "$r"
sync_fixture "$r"
git -C "$r/worker" remote set-url origin "$r/nonexistent.git"
rc=0
err=$(PATH="$SYNC_PATH" "$SYNC" "$r/worker" 2>&1 >/dev/null) || rc=$?
assert_cell sync/fetch-failure "sync/fetch-failure: an unreachable remote exits 4" "$rc"
case $err in
  *fetch-failed*) pass "sync/fetch-failure: the reason names the fetch" ;;
  *) fail "sync/fetch-failure: the reason does not name fetch-failed: $err" ;;
esac
case $err in
  *merge-conflict*) fail "sync/fetch-failure: a fetch failure was misreported as a merge conflict: $err" ;;
  *) pass "sync/fetch-failure: the fetch failure is not collapsed into a conflict reason" ;;
esac

# sync/dirty-tree — uncommitted tracked changes exit 3 with their own reason
# before any fetch: the remote is broken here too, so a dirty-tree reason
# (not fetch-failed) is what proves the ordering (REQ-B1.6).
r="$SYNCROOT/dirty"
mkdir -p "$r"
sync_fixture "$r"
git -C "$r/worker" remote set-url origin "$r/nonexistent.git"
printf 'uncommitted\n' >>"$r/worker/shared.txt"
rc=0
err=$(PATH="$SYNC_PATH" "$SYNC" "$r/worker" 2>&1 >/dev/null) || rc=$?
assert_cell sync/dirty-tree "sync/dirty-tree: a pre-existing dirty tree exits 3" "$rc"
case $err in
  *dirty-tree*) pass "sync/dirty-tree: the reason names the dirty tree" ;;
  *) fail "sync/dirty-tree: the reason does not name dirty-tree: $err" ;;
esac
case $err in
  *fetch-failed* | *merge-conflict*) fail "sync/dirty-tree: a dirty tree was collapsed into a fetch/conflict reason: $err" ;;
  *) pass "sync/dirty-tree: the dirty tree was refused before the (broken) remote was touched" ;;
esac

# sync/no-pull-no-rebase — source-level negative assertions, comments stripped
# so the script may still explain why it avoids them, plus the positive shape.
code=$(sed 's/#.*$//' "$SYNC")
shape_ok=ok
if printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^|;&]*[[:space:]])?pull([^[:alnum:]_-]|$)'; then
  fail "sync/no-pull-no-rebase: the script contains a 'git pull' (REQ-B1.2)"
  shape_ok=fail
else
  pass "sync/no-pull-no-rebase: no 'git pull' in the script"
fi
if printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^|;&]*[[:space:]])?rebase([^[:alnum:]_-]|$)|--rebase|rebase[[:space:]]*=[[:space:]]*(true|1|interactive|merges|always)'; then
  fail "sync/no-pull-no-rebase: the script runs or enables a rebase (REQ-B1.2)"
  shape_ok=fail
else
  pass "sync/no-pull-no-rebase: no rebase in any form in the script (flag, subcommand, or config such as pull.rebase=always)"
fi
if printf '%s\n' "$code" | grep -Eq 'git[^|;&]*fetch[[:space:]]+([^|;&]*[[:space:]])?origin[[:space:]]+main' \
  && printf '%s\n' "$code" | grep -Eq '[[:space:]]merge[[:space:]][^|;&]*FETCH_HEAD'; then
  pass "sync/no-pull-no-rebase: the script runs an explicit 'git fetch origin main' and a 'merge' of FETCH_HEAD (merge-base does not count)"
else
  fail "sync/no-pull-no-rebase: the fetch + merge FETCH_HEAD shape is missing"
  shape_ok=fail
fi
assert_cell sync/no-pull-no-rebase "sync/no-pull-no-rebase: every source-shape check held" "$shape_ok"

# sync/no-llm — behavioral (no sentinel fired across any of the runs above)
# and grep-level over the comment-stripped source.
found=''
for t in curl wget claude; do
  [ ! -e "$STATE/sync-sentinel-$t" ] || found="$found $t"
done
if [ -n "$found" ]; then
  fail "sync/no-llm: a sync run invoked$found (REQ-D1.4 violation)"
  no_llm_ok=fail
else
  pass "sync/no-llm: no sync run (clean, conflict, resume, fetch failure, dirty tree) invoked curl/wget/claude"
fi
NO_LLM_RE='anthropic|openai|api\.claude|claude -p|\bcurl\b|\bwget\b|https?://[a-z]|/dev/tcp'
if printf '%s\n' "$code" | grep -Eqi "$NO_LLM_RE"; then
  fail "sync/no-llm: the sync script's code contains a model/API/network invocation (REQ-D1.4)"
  no_llm_ok=fail
else
  pass "sync/no-llm: the sync script's code contains no model/API/network invocation (grep-level, comments stripped)"
fi
assert_cell sync/no-llm "sync/no-llm: the behavioral and source checks both held" "$no_llm_ok"

echo "### REQ-D1.4 — no-LLM source assertions for the guard"

guard_code=$(sed 's/#.*$//' "$HOOK")
if printf '%s\n' "$guard_code" | grep -Eqi "$NO_LLM_RE"; then
  fail "the guard's code contains a model/API/network invocation (REQ-D1.4)"
else
  pass "the guard's code contains no model/API/network invocation (grep-level, comments stripped)"
fi
if printf '%s\n' "$guard_code" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"(allow|ask)"|permissionDecision:"(allow|ask)"'; then
  fail "the guard's source can emit allow/ask — it must only deny or defer"
else
  pass "the guard's source can only emit deny (never allow/ask)"
fi

echo "### REQ-D1.1 — the manifest meta-check"

gaps=$(manifest_gaps "$MANIFEST" "$COVERED")
if [ -z "$gaps" ]; then
  pass "every manifest cell has a fixture, every fixture names a manifest cell, and no key is declared twice"
else
  fail "manifest gaps:
$gaps"
fi

# Positive controls: the meta-check must be able to go red in all three
# directions.
pruned=$(printf '%s' "$COVERED" | grep -vxF -- 'unknown/mcp')
gaps=$(manifest_gaps "$MANIFEST" "$pruned")
if [ "$gaps" = 'missing fixture: unknown/mcp (expected deny)' ]; then
  pass "positive control: removing the unknown/mcp fixture is reported as exactly that gap"
else
  fail "positive control: the meta-check did not report a removed cell — got '$gaps'"
fi
padded="${COVERED}bogus/bash
"
gaps=$(manifest_gaps "$MANIFEST" "$padded")
if [ "$gaps" = 'undeclared cell: bogus/bash' ]; then
  pass "positive control: a fixture claiming an undeclared cell is reported as exactly that"
else
  fail "positive control: the meta-check did not report an undeclared cell — got '$gaps'"
fi
doubled="${MANIFEST}behind/bash defer
"
gaps=$(manifest_gaps "$doubled" "$COVERED")
if [ "$gaps" = 'duplicate manifest key: behind/bash' ]; then
  pass "positive control: a key declared twice (even with a conflicting expectation) is reported as exactly that"
else
  fail "positive control: the meta-check did not report a duplicated key — got '$gaps'"
fi

echo
echo "passes: $passes  failures: $failures"
[ "$failures" = 0 ]
