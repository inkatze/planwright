#!/bin/bash
# The merge-currency-guard bundle's completeness suite (Task 4): a
# mechanically-enforced expected-cell manifest over scripts/ready-guard.sh
# across both ready-flip surfaces (REQ-D1.1), the deny-over-allow OUTCOME
# against the worker-settings allow entry (REQ-D1.2, REQ-C1.4, D-6), the
# enforcement-by-construction check over the hook wiring (REQ-A1.2), the
# flipper-agnostic shapes (REQ-A1.3), the sync script's required cells
# (REQ-D1.3), and the no-LLM negative assertions for both scripts (REQ-D1.4).
#
# WHY A MANIFEST. tests/test-ready-guard.sh asserts each branch of the guard in
# depth, but a suite can only assert the cells someone remembered to write, and
# a cell that is silently absent (UNKNOWN on the MCP surface, say) leaves the
# suite green. Here the expected cells are DECLARED first, every fixture
# registers the cell it exercised, and a meta-check fails the suite on any
# declared cell with no fixture and on any fixture claiming an undeclared cell.
# The meta-check is itself given positive controls: run against a coverage
# record with one cell removed it must report exactly that cell, and against a
# record with one cell added it must report exactly that cell, so the
# enforcement cannot pass vacuously.
#
# Contract under test is the harness's (tests/lib/ready-guard-harness.sh):
#   DENY  <=> exit 0 AND a deny decision with a non-empty reason.
#   DEFER <=> exit 0 AND empty stdout.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
WORKER_SETTINGS="$REPO_ROOT/config/worker-settings.json"
SYNC="$REPO_ROOT/scripts/converge-sync-main.sh"
TAB=$(printf '\t')

# shellcheck source=tests/lib/ready-guard-harness.sh
. "$REPO_ROOT/tests/lib/ready-guard-harness.sh"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

[ -x "$SYNC" ] || {
  echo "FAIL: scripts/converge-sync-main.sh missing or not executable" >&2
  exit 1
}
[ -f "$WORKER_SETTINGS" ] || {
  echo "FAIL: config/worker-settings.json missing" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# The expected-cell manifest (REQ-D1.1). One line per cell: <key> <expect>.
#
# Guard cells are <state>/<surface>. The states are the D-3 predicate outcomes
# (conforming, behind, conflicting), the REQ-C1.3 fail-closed causes (unknown,
# compare-failure, invalid-selector, missing-gh, missing-jq, malformed-payload)
# and the REQ-C1.8 never-gated transitions (undo, already-ready,
# non-transition). Every state is declared on BOTH surfaces. Where a state has
# no literal MCP spelling, the fixture drives the MCP-side analogue: the same
# transition expressed in that tool's fields (`draft: true` is the MCP undo; a
# call with no `draft` field is the MCP non-transition), and the same for Bash
# (`gh pr edit` is the Bash non-transition).
#
# Sync cells are sync/<case>, the REQ-D1.3 required set plus the REQ-D1.4
# no-LLM cell. Their expect column is documentary; the fixture asserts the
# exit code and reason itself and then registers the cell.
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
compare-failure/bash deny
compare-failure/mcp deny
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
sync/fetch-failure exit-4
sync/no-pull-no-rebase source
sync/no-llm no-call
'

COVERED=''

# cover <key> — register that a fixture exercised the cell.
cover() {
  COVERED="$COVERED$1
"
}

# manifest_expect <key> — print the manifest's expectation for a cell, or
# nothing when the cell is not declared.
manifest_expect() {
  printf '%s\n' "$MANIFEST" | awk -v k="$1" '$1 == k { print $2; exit }'
}

# assert_cell <key> <label> — assert the guard's decision against the
# manifest's expectation for that cell, then register the cell. The cell is
# registered even when undeclared, so the meta-check below is what reports a
# fixture that claims a cell the manifest never listed.
assert_cell() {
  local key=$1 label=$2 expect
  expect=$(manifest_expect "$key")
  case $expect in
    deny) assert_deny "$label" ;;
    defer) assert_defer "$label" ;;
    *) fail "$label: fixture claims cell $key, which the manifest does not declare as deny/defer" ;;
  esac
  cover "$key"
}

# manifest_gaps <covered> — print one line per declared cell with no fixture
# and per covered cell the manifest does not declare; print nothing when the
# two agree exactly.
manifest_gaps() {
  local covered=$1 key expect
  while read -r key expect; do
    [ -n "$key" ] || continue
    printf '%s\n' "$covered" | grep -qxF -- "$key" \
      || printf 'missing fixture: %s (expected %s)\n' "$key" "$expect"
  done <<EOF
$MANIFEST
EOF
  printf '%s\n' "$covered" | sort -u | while IFS= read -r key; do
    [ -n "$key" ] || continue
    printf '%s\n' "$MANIFEST" | awk -v k="$key" '$1 == k { f = 1 } END { exit !f }' \
      || printf 'undeclared cell: %s\n' "$key"
  done
}

# assert_gh_calls <label> <count> — pin the exact number of stubbed gh calls.
assert_gh_calls() {
  if [ "$(gh_calls)" = "$2" ]; then
    pass "$1"
  else
    fail "$1: expected $2 gh call(s), saw $(gh_calls)"
  fi
}

# assert_no_mergestatestatus <label> — the D-3 regression pin: the guard never
# asks for mergeStateStatus, on either surface.
assert_no_mergestatestatus() {
  if grep -q 'mergeStateStatus' "$STATE/argv.log"; then
    fail "$1: the guard requested mergeStateStatus (D-3 regression)"
  else
    pass "$1"
  fi
}

BASH_FLIP='gh pr ready 42'
GAUNTLET_FLIP='gh pr ready 42 --repo acme/widgets'

echo "### REQ-D1.1 — the decision matrix, cell by cell, on both surfaces"

echo "# conforming: behind_by 0 + MERGEABLE + draft"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell conforming/bash "bash: a conforming flip defers"
assert_no_mergestatestatus "bash: the conforming query never asks for mergeStateStatus"
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)"
assert_cell conforming/mcp "mcp: a conforming draft->ready transition defers"
assert_no_mergestatestatus "mcp: the conforming query never asks for mergeStateStatus"

echo "# behind: behind_by > 0 on a base WITHOUT require-up-to-date (mergeStateStatus CLEAN)"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell behind/bash "bash: a worker-shaped flip on a behind PR denies"
assert_reason_matches "bash: the behind denial names the staleness" 'commit\(s\) behind'
assert_no_mergestatestatus "bash: currency is not keyed on mergeStateStatus (the CLEAN-but-behind pin)"
assert_no_sentinels "bash: the behind decision path invoked no git/curl/wget/claude"
if [ "$(gh_calls)" -ge 2 ]; then
  pass "bash: positive control — the stubbed gh call site was traversed (view + compare)"
else
  fail "bash: positive control failed — $(gh_calls) gh call(s), so the no-LLM assertion would be vacuous"
fi
# REQ-A1.3: the gauntlet's distinct shape on the same behind payload.
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
run_hook "$(bash_payload "$GAUNTLET_FLIP")"
assert_cell behind/bash "bash: a gauntlet-shaped flip (--repo) on the same behind PR denies"
assert_reason_matches "bash: the gauntlet denial names the same staleness" 'commit\(s\) behind'
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=5
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)"
assert_cell behind/mcp "mcp: a draft->ready transition on a behind PR denies"
assert_reason_matches "mcp: the behind denial names the staleness" 'commit\(s\) behind'
assert_no_mergestatestatus "mcp: currency is not keyed on mergeStateStatus"
assert_no_sentinels "mcp: the behind decision path invoked no git/curl/wget/claude"
if [ "$(gh_calls)" -ge 2 ]; then
  pass "mcp: positive control — the stubbed gh call site was traversed (view + compare)"
else
  fail "mcp: positive control failed — $(gh_calls) gh call(s)"
fi

echo "# conflicting: mergeable CONFLICTING"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFLICTING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell conflicting/bash "bash: a conflicting PR denies"
assert_reason_matches "bash: the conflict denial names the conflict" 'conflict'
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)"
assert_cell conflicting/mcp "mcp: a conflicting PR denies"
assert_reason_matches "mcp: the conflict denial names the conflict" 'conflict'

echo "# unknown: mergeable UNKNOWN, re-queried once, then denied wait-and-retry"
reset_stub_env
STUB_VIEW_JSON=$VIEW_UNKNOWN STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell unknown/bash "bash: UNKNOWN denies after the bounded re-query"
assert_reason_matches "bash: the UNKNOWN denial names wait-and-retry" 'wait'
assert_reason_lacks "bash: the UNKNOWN denial prescribes no fetch" 'run .*fetch|git fetch'
if [ "$(pr_view_calls)" = 2 ]; then
  pass "bash: UNKNOWN re-queried gh pr view exactly once more"
else
  fail "bash: UNKNOWN should issue exactly 2 pr-view calls, saw $(pr_view_calls)"
fi
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)"
assert_cell unknown/mcp "mcp: UNKNOWN denies after the bounded re-query"
assert_reason_matches "mcp: the UNKNOWN denial names wait-and-retry" 'wait'
assert_reason_lacks "mcp: the UNKNOWN denial prescribes no fetch" 'run .*fetch|git fetch'
if [ "$(pr_view_calls)" = 2 ]; then
  pass "mcp: UNKNOWN re-queried gh pr view exactly once more (the re-query is not Bash-only)"
else
  fail "mcp: UNKNOWN should issue exactly 2 pr-view calls, saw $(pr_view_calls)"
fi

echo "# compare-failure: the compare endpoint errors"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_RC=1
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell compare-failure/bash "bash: a failing compare call denies"
assert_reason_matches "bash: the compare-failure denial names the compare endpoint" 'compare endpoint'
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)"
assert_cell compare-failure/mcp "mcp: a failing compare call denies"
assert_reason_matches "mcp: the compare-failure denial names the compare endpoint" 'compare endpoint'

echo "# invalid-selector: grammar validation refuses before any gh call"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "gh pr ready '1 --repo attacker/clean'")"
assert_cell invalid-selector/bash "bash: an option-bearing selector denies"
assert_gh_calls "bash: the invalid selector never reached gh" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload 'gh pr ready 42 43')"
assert_cell invalid-selector/bash "bash: an ambiguous two-target selector denies"
assert_reason_matches "bash: the ambiguous denial names the ambiguity" 'more than one target'
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets '"42"' false)"
assert_cell invalid-selector/mcp "mcp: a string pullNumber denies"
assert_reason_matches "mcp: the invalid-selector denial names the selector" 'no valid pull-request number'
assert_gh_calls "mcp: the invalid selector never reached gh" 0
reset_stub_env
RG_SURFACE=mcp run_hook "$(mcp_payload 'acme/../evil' widgets 42 false)"
assert_cell invalid-selector/mcp "mcp: an owner outside GitHub's charset denies"
assert_gh_calls "mcp: the invalid owner never reached gh" 0

echo "# missing-gh"
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
run_hook "$(bash_payload "$BASH_FLIP")" gh
assert_cell missing-gh/bash "bash: an absent gh denies"
assert_reason_matches "bash: the missing-gh denial names gh" 'gh CLI is not on PATH'
reset_stub_env
STUB_VIEW_JSON=$VIEW_CONFORMING STUB_COMPARE_OUT=0
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)" gh
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
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)" jq
assert_cell missing-jq/mcp "mcp: an absent jq denies (the tool name is the flip evidence)"
assert_reason_matches "mcp: the missing-jq denial names jq" 'jq is not on PATH'

echo "# malformed-payload"
reset_stub_env
run_hook "$(jq -n '{tool_name:"Bash", tool_input:{command:["gh","pr","ready","42"]}, cwd:"/tmp"}')"
assert_cell malformed-payload/bash "bash: a non-string command whose raw text evidences a flip denies"
reset_stub_env
run_hook ''
assert_cell malformed-payload/bash "bash: an empty PreToolUse payload denies"
reset_stub_env
RG_SURFACE=mcp run_hook "$(jq -n '{tool_name:"mcp__github__update_pull_request", tool_input:"not-an-object"}')"
assert_cell malformed-payload/mcp "mcp: a non-object tool_input denies"
assert_reason_matches "mcp: the malformed denial names the malformed payload" 'malformed'
reset_stub_env
RG_SURFACE=mcp run_hook '{not json at all'
assert_cell malformed-payload/mcp "mcp: an unparseable payload on the MCP matcher denies"

echo "# undo: the ready->draft direction is never gated"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr ready 42 --undo')"
assert_cell undo/bash "bash: --undo defers even on a behind PR"
assert_gh_calls "bash: --undo issues no network call" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 true)"
assert_cell undo/mcp "mcp: draft:true (re-drafting) defers even on a behind PR"
assert_gh_calls "mcp: re-drafting issues no network call" 0

echo "# already-ready: isDraft false, stale AND conflicting on purpose"
reset_stub_env
STUB_VIEW_JSON=$VIEW_ALREADY_READY STUB_COMPARE_OUT=9
run_hook "$(bash_payload "$BASH_FLIP")"
assert_cell already-ready/bash "bash: an already-ready PR defers regardless of currency"
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42 false)"
assert_cell already-ready/mcp "mcp: an already-ready PR defers regardless of currency"

echo "# non-transition: a PR edit that is not a draft->ready flip"
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
run_hook "$(bash_payload 'gh pr edit 42 --title t')"
assert_cell non-transition/bash "bash: a non-ready gh pr subcommand defers"
assert_gh_calls "bash: a non-transition issues no network call" 0
reset_stub_env
STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=9
RG_SURFACE=mcp run_hook "$(mcp_payload acme widgets 42)"
assert_cell non-transition/mcp "mcp: update_pull_request with no draft field defers"
assert_gh_calls "mcp: a non-transition issues no network call" 0

echo "### REQ-D1.2 / REQ-C1.4 / D-6 — deny-over-allow OUTCOME against the worker allow entry"

ALLOW_RULE='Bash(gh pr ready:*)'
if jq -e --arg r "$ALLOW_RULE" '.permissions.allow | any(. == $r)' "$WORKER_SETTINGS" >/dev/null 2>&1; then
  pass "worker-settings.json carries the $ALLOW_RULE allow entry (structural)"
else
  fail "worker-settings.json no longer carries $ALLOW_RULE — the outcome test below would be vacuous"
fi

# The permission-matcher oracle decides what the allow layer would do with the
# payload; the guard decides what the hook layer does with the same payload.
# The outcome pinned is the pair: allow-layer ALLOW, hook-layer DENY.
worker_deny=$(jq -r '.permissions.deny[]?' "$WORKER_SETTINGS")
worker_allow=$(jq -r '.permissions.allow[]?' "$WORKER_SETTINGS")
if pm_load_rules "$worker_deny" '' "$worker_allow"; then
  pass "the worker rule set loaded into the matcher oracle"
else
  fail "the worker rule set did not load into the matcher oracle (rc $?)"
fi

for cmd in "$BASH_FLIP" "$GAUNTLET_FLIP"; do
  if [ "$(pm_decide "$cmd")" = allow ]; then
    pass "the allow entry admits '$cmd' (the payload the guard must still deny)"
  else
    fail "the allow entry does not admit '$cmd' (oracle said '$(pm_decide "$cmd")'), so the outcome test is not testing precedence"
  fi
  reset_stub_env
  STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=7
  run_hook "$(bash_payload "$cmd")"
  assert_deny_because "OUTCOME: '$cmd' on a behind PR is denied by the guard with the allow entry present" 'commit\(s\) behind'
  reset_stub_env
  STUB_VIEW_JSON=$VIEW_CONFLICTING STUB_COMPARE_OUT=0
  run_hook "$(bash_payload "$cmd")"
  assert_deny_because "OUTCOME: '$cmd' on a conflicting PR is denied by the guard with the allow entry present" 'conflict'
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
if [ "$(pm_decide 'gh pr ready 42 --undo')" = deny ]; then
  pass "the worker profile's own deny covers the --undo form the guard leaves ungated"
else
  fail "the worker profile no longer denies 'gh pr ready 42 --undo' (oracle said '$(pm_decide 'gh pr ready 42 --undo')')"
fi

# REQ-C1.7: the deny is not gated behind a settings profile. It rides the
# plugin-global hooks.json, and the worker profile itself carries no copy of
# it, so a session under any profile (or none) meets the same guard.
if jq -e '[.hooks.PreToolUse[]? | .hooks[]?.command // ""] | any(test("ready-guard\\.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "the guard is wired in the plugin-global hooks.json"
else
  fail "the guard is not wired in hooks/hooks.json"
fi
if jq -e '[.hooks.PreToolUse[]? | .hooks[]?.command // ""] | any(test("ready-guard\\.sh"))' "$WORKER_SETTINGS" >/dev/null 2>&1; then
  fail "the guard is wired inside worker-settings.json — that would scope a universal deny to one profile"
else
  pass "the guard is not scoped to the worker profile (worker-settings.json wires no copy of it)"
fi

echo "### REQ-A1.2 — enforced by construction: the wiring, not prose, is what denies"

# run_stack <hooks-json> <tool-name> <payload> — dispatch the payload through
# every PreToolUse entry of <hooks-json> whose matcher applies to <tool-name>,
# the way Claude Code does, and collect their stdout into STACK_OUT and the
# number of commands run into STACK_N. This is a MODEL of the dispatcher, kept
# to what the documentation states: an absent or empty matcher applies to
# every tool; otherwise the matcher is an exact tool name or a regex matched
# against the whole name. Commands run with CLAUDE_PLUGIN_ROOT pointed at this
# checkout, on the harness's hermetic PATH plus a bash for the shebang.
STACKBIN="$SANDBOX/stackbin"
mkdir -p "$STACKBIN"
ln -sf /bin/bash "$STACKBIN/bash"
run_stack() {
  local json=$1 tool=$2 payload=$3 cmd out
  STACK_OUT=''
  STACK_N=0
  rm -f "$STATE/viewcount"
  : >"$STATE/argv.log"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    STACK_N=$((STACK_N + 1))
    out=$(printf '%s' "$payload" \
      | env -i PATH="$STACKBIN:$BIN" HOME="$SANDBOX" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
        GH_ARGV_LOG="$STATE/argv.log" GH_STATE="$STATE" \
        PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
        STUB_VIEW_JSON="${STUB_VIEW_JSON:-}" STUB_VIEW_RC="${STUB_VIEW_RC:-0}" \
        STUB_COMPARE_OUT="${STUB_COMPARE_OUT:-0}" STUB_COMPARE_RC="${STUB_COMPARE_RC:-0}" \
        /bin/bash -c "$cmd" 2>/dev/null) || out=''
    STACK_OUT="$STACK_OUT$out"
  done <<EOF
$(jq -r --arg t "$tool" '
  .hooks.PreToolUse[]?
  | (.matcher // "") as $m
  | select($m == "" or $m == $t or ($t | test("^(" + $m + ")$")))
  | .hooks[]?.command // empty' "$json")
EOF
}
stack_denies() {
  printf '%s' "$STACK_OUT" | grep -q '"permissionDecision":"deny"'
}

UNWIRED_JSON="$SANDBOX/hooks-without-guard.json"
jq '.hooks.PreToolUse |= map(.hooks |= map(select(.command | test("ready-guard\\.sh") | not)))' \
  "$HOOKS_JSON" >"$UNWIRED_JSON"

for surface in bash mcp; do
  case $surface in
    bash)
      tool=Bash
      payload=$(bash_payload "$BASH_FLIP")
      ;;
    mcp)
      tool=mcp__github__update_pull_request
      payload=$(mcp_payload acme widgets 42 false)
      ;;
  esac
  reset_stub_env
  STUB_VIEW_JSON=$VIEW_BEHIND STUB_COMPARE_OUT=7
  run_stack "$HOOKS_JSON" "$tool" "$payload"
  if [ "$STACK_N" -ge 1 ] && stack_denies; then
    pass "$surface: the wired PreToolUse stack denies a BEHIND flip with no skill-prose step involved"
  else
    fail "$surface: the wired stack ran $STACK_N command(s) and emitted no deny: '$STACK_OUT'"
  fi
  run_stack "$UNWIRED_JSON" "$tool" "$payload"
  if stack_denies; then
    fail "$surface: with ready-guard.sh removed from the wiring something else still denied — the guard is not the sole enforcement point this suite believes it is"
  else
    pass "$surface: with ready-guard.sh removed from the wiring the same BEHIND flip is no longer denied by this bundle's machinery"
  fi
done

echo "### REQ-D1.3 / REQ-D1.4 — the sync script's required cells"

# gitq <dir> <args...> — git with a deterministic, signing-free identity.
gitq() {
  git -C "$1" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "${@:2}"
}

# sync_fixture <root> — a bare origin with one commit on main, a seed clone to
# advance it from, and a worker clone on its own task branch.
sync_fixture() {
  git -c init.defaultBranch=main init -q --bare "$1/origin.git"
  git clone -q "$1/origin.git" "$1/seed" 2>/dev/null
  printf 'base\n' >"$1/seed/shared.txt"
  gitq "$1/seed" add -A
  gitq "$1/seed" commit -q -m base
  gitq "$1/seed" branch -M main
  gitq "$1/seed" push -q origin main
  git clone -q "$1/origin.git" "$1/worker" 2>/dev/null
  git -C "$1/worker" config user.name test
  git -C "$1/worker" config user.email test@example.invalid
  git -C "$1/worker" config commit.gpgsign false
  gitq "$1/worker" checkout -q -b task
}

# advance_main <root> <file> <content> — land a commit on origin/main.
advance_main() {
  printf '%s\n' "$3" >"$1/seed/$2"
  gitq "$1/seed" add -A
  gitq "$1/seed" commit -q -m "advance $2"
  gitq "$1/seed" push -q origin main
}

SYNCROOT="$SANDBOX/sync"
mkdir -p "$SYNCROOT"

# sync/clean-merge — a branch with its own commit takes origin/main's advance
# by merge; the advanced commit is in its history and its own commit survives
# (no rewrite). This run doubles as the no-LLM behavioral fixture: the
# sentinel stubs sit FIRST on PATH, so any curl/wget/claude the script reached
# for would have hit them.
SENT="$SANDBOX/sentbin"
mkdir -p "$SENT"
for t in curl wget claude; do
  printf '#!/bin/sh\n: >"%s/sync-sentinel-%s"\nexit 97\n' "$STATE" "$t" >"$SENT/$t"
  chmod +x "$SENT/$t"
done
rm -f "$STATE"/sync-sentinel-*
r="$SYNCROOT/clean"
mkdir -p "$r"
sync_fixture "$r"
printf 'worker work\n' >"$r/worker/worker.txt"
gitq "$r/worker" add -A
gitq "$r/worker" commit -q -m "worker commit"
own=$(gitq "$r/worker" rev-parse HEAD)
advance_main "$r" newfile.txt "from main"
adv=$(gitq "$r/seed" rev-parse HEAD)
rc=0
out=$(PATH="$SENT:$PATH" "$SYNC" "$r/worker" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "sync/clean-merge: a clean origin/main advance exits 0"
else
  fail "sync/clean-merge: expected exit 0, got $rc"
fi
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
cover sync/clean-merge
found=''
for t in curl wget claude; do
  [ ! -e "$STATE/sync-sentinel-$t" ] || found="$found $t"
done
if [ -n "$found" ]; then
  fail "sync/no-llm: the sync's decision path invoked$found (REQ-D1.4 violation)"
else
  pass "sync/no-llm: the sync's decision path invoked no curl/wget/claude (behavioral, with the merge above as the positive control)"
fi
if grep -Eqi 'anthropic|openai|api\.claude|claude -p|\bcurl\b|\bwget\b|https?://[a-z]' "$SYNC"; then
  fail "sync/no-llm: the sync script's source contains a model/API/network invocation (REQ-D1.4)"
else
  pass "sync/no-llm: the sync script's source contains no model/API/network invocation (grep-level)"
fi
cover sync/no-llm

# sync/conflict — an unresolvable conflict exits 5 with the merge-conflict
# reason and leaves no MERGE_HEAD behind.
r="$SYNCROOT/conflict"
mkdir -p "$r"
sync_fixture "$r"
printf 'worker side\n' >"$r/worker/shared.txt"
gitq "$r/worker" add -A
gitq "$r/worker" commit -q -m "worker edits shared.txt"
advance_main "$r" shared.txt "main side"
rc=0
err=$("$SYNC" "$r/worker" 2>&1 >/dev/null) || rc=$?
if [ "$rc" -eq 5 ]; then
  pass "sync/conflict: an unresolvable conflict exits 5"
else
  fail "sync/conflict: expected exit 5, got $rc"
fi
case $err in
  *merge-conflict*) pass "sync/conflict: the reason names the conflict" ;;
  *) fail "sync/conflict: the reason does not name merge-conflict: $err" ;;
esac
if [ ! -f "$r/worker/.git/MERGE_HEAD" ]; then
  pass "sync/conflict: the merge was aborted (no MERGE_HEAD), so a resume re-attempts cleanly"
else
  fail "sync/conflict: MERGE_HEAD survived — the tree is wedged"
fi
cover sync/conflict

# sync/fetch-failure — an unreachable remote exits 4 with the fetch reason,
# never misreported as a conflict.
r="$SYNCROOT/fetch"
mkdir -p "$r"
sync_fixture "$r"
git -C "$r/worker" remote set-url origin "$r/nonexistent.git"
rc=0
err=$("$SYNC" "$r/worker" 2>&1 >/dev/null) || rc=$?
if [ "$rc" -eq 4 ]; then
  pass "sync/fetch-failure: an unreachable remote exits 4"
else
  fail "sync/fetch-failure: expected exit 4, got $rc"
fi
case $err in
  *fetch-failed*) pass "sync/fetch-failure: the reason names the fetch" ;;
  *) fail "sync/fetch-failure: the reason does not name fetch-failed: $err" ;;
esac
case $err in
  *merge-conflict*) fail "sync/fetch-failure: a fetch failure was misreported as a merge conflict: $err" ;;
  *) pass "sync/fetch-failure: the fetch failure is not collapsed into a conflict reason" ;;
esac
cover sync/fetch-failure

# sync/no-pull-no-rebase — source-level negative assertions, comments stripped
# so the script may still explain why it avoids them, plus the positive shape.
code=$(sed 's/#.*$//' "$SYNC")
if printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^|;&]*[[:space:]])?pull([^[:alnum:]_-]|$)'; then
  fail "sync/no-pull-no-rebase: the script contains a 'git pull' (REQ-B1.2)"
else
  pass "sync/no-pull-no-rebase: no 'git pull' in the script"
fi
if printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^|;&]*[[:space:]])?rebase([^[:alnum:]_-]|$)|--rebase|rebase[[:space:]]*=[[:space:]]*(true|1|interactive|merges)'; then
  fail "sync/no-pull-no-rebase: the script runs or enables a rebase (REQ-B1.2)"
else
  pass "sync/no-pull-no-rebase: no rebase in any form in the script"
fi
if printf '%s\n' "$code" | grep -Eq 'git[^|;&]*fetch[[:space:]]+([^|;&]*[[:space:]])?origin[[:space:]]+main' \
  && printf '%s\n' "$code" | grep -Eq 'merge[^|;&]*FETCH_HEAD'; then
  pass "sync/no-pull-no-rebase: the script is an explicit 'git fetch origin main' followed by a merge of FETCH_HEAD"
else
  fail "sync/no-pull-no-rebase: the fetch + merge FETCH_HEAD shape is missing"
fi
cover sync/no-pull-no-rebase

echo "### REQ-D1.4 — no-LLM source assertions for the guard"

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

echo "### REQ-D1.1 — the manifest meta-check"

gaps=$(manifest_gaps "$COVERED")
if [ -z "$gaps" ]; then
  pass "every manifest cell has a fixture and every fixture names a manifest cell"
else
  fail "manifest gaps:
$gaps"
fi

# Positive controls: the meta-check must be able to go red in both directions.
pruned=$(printf '%s' "$COVERED" | grep -vxF -- 'unknown/mcp')
gaps=$(manifest_gaps "$pruned")
if [ "$gaps" = 'missing fixture: unknown/mcp (expected deny)' ]; then
  pass "positive control: removing the unknown/mcp fixture is reported as exactly that gap"
else
  fail "positive control: the meta-check did not report a removed cell — got '$gaps'"
fi
padded="${COVERED}bogus/bash
"
gaps=$(manifest_gaps "$padded")
if [ "$gaps" = 'undeclared cell: bogus/bash' ]; then
  pass "positive control: a fixture claiming an undeclared cell is reported as exactly that"
else
  fail "positive control: the meta-check did not report an undeclared cell — got '$gaps'"
fi

echo
echo "passes: $passes  failures: $failures"
[ "$failures" = 0 ]
