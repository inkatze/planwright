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
# Task 4 owns the mechanically-enforced expected-cell manifest (REQ-D1.1) and
# the worker-settings deny-over-allow outcome test (REQ-D1.2); this suite covers
# Task 2's `Done when:` matrix.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/ready-guard.sh"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

failures=0
passes=0

pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

if [ ! -f "$HOOK" ]; then
  echo "FAIL: ready-guard script missing at $HOOK" >&2
  exit 1
fi
for t in jq timeout gtimeout; do
  command -v "$t" >/dev/null 2>&1 && HAVE_ANY_TIMEOUT=1
done
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
fi
if [ -z "${HAVE_ANY_TIMEOUT:-}" ]; then
  echo "FAIL: neither timeout nor gtimeout is available; the suite cannot exercise the bounded path" >&2
  exit 1
fi

SANDBOX="$(mktemp -d)" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"
STATE="$SANDBOX/state"
WORK="$SANDBOX/work"
mkdir -p "$BIN" "$STATE" "$WORK" "$WORK/sub"

# A hermetic PATH holding ONLY what the guard may use. Absence fixtures delete
# one entry from it, so "jq absent" and "gh absent" are genuinely absent rather
# than shadowed — the ambient PATH is never consulted.
HERMETIC_TOOLS="head tr sleep dirname cat env sed grep"
for t in $HERMETIC_TOOLS; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t"
done
ln -sf "$(command -v jq)" "$BIN/jq"
for t in timeout gtimeout; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t"
done

# The `gh` stub. Records every invocation's argv (tab-separated, one line per
# call) so fixtures can pin the QUERY SHAPE, and answers from env so each
# fixture drives its own decision cell. It answers `pr` and `api` only: a wrong
# subcommand exits 3, which the guard must surface as a denial rather than
# silently treat as an answer.
cat >"$BIN/gh" <<'GHSTUB'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf '\t%s' "$a"; done
  printf '\n'
} >>"$GH_ARGV_LOG"
case "${1:-}" in
  pr)
    n=0
    [ ! -f "$GH_STATE/viewcount" ] || read -r n <"$GH_STATE/viewcount"
    n=$((n + 1))
    printf '%s\n' "$n" >"$GH_STATE/viewcount"
    if [ "$n" = 1 ]; then
      rc=${STUB_VIEW_RC:-0}
      [ "$rc" = 0 ] || exit "$rc"
      printf '%s' "${STUB_VIEW_JSON:-}"
    else
      rc=${STUB_VIEW_RC2:-${STUB_VIEW_RC:-0}}
      [ "$rc" = 0 ] || exit "$rc"
      printf '%s' "${STUB_VIEW_JSON2:-${STUB_VIEW_JSON:-}}"
    fi
    ;;
  api)
    rc=${STUB_COMPARE_RC:-0}
    [ "$rc" = 0 ] || exit "$rc"
    printf '%s\n' "${STUB_COMPARE_OUT:-0}"
    ;;
  *) exit 3 ;;
esac
GHSTUB
chmod +x "$BIN/gh"

# Side-effect sentinels. `git`, `curl`, and `claude` must never run in the
# decision path (REQ-D1.4, D-5): each stub drops a marker file, and the
# assertions require the marker to be absent. They also exit non-zero, so a
# guard that DID call one and depended on its answer would misbehave visibly.
for t in git curl wget claude; do
  cat >"$BIN/$t" <<SENTSTUB
#!/bin/sh
: >"$STATE/sentinel-$t"
exit 97
SENTSTUB
  chmod +x "$BIN/$t"
done

# A conforming PR: currently a draft, mergeable, and current with its base.
VIEW_CONFORMING='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
# A stale PR. It deliberately ALSO reports `mergeStateStatus CLEAN`: on a base
# without "require up to date" protection that is what GitHub says about a
# behind PR, so an implementation that regressed to keying currency on
# mergeStateStatus would read this as conforming and this fixture would catch it
# (test-spec REQ-C1.1).
VIEW_BEHIND='{"baseRefName":"main","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","isDraft":true,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://github.com/acme/widgets/pull/42"}'
VIEW_CONFLICTING='{"baseRefName":"main","headRefOid":"cccccccccccccccccccccccccccccccccccccccc","isDraft":true,"mergeable":"CONFLICTING","url":"https://github.com/acme/widgets/pull/42"}'
VIEW_UNKNOWN='{"baseRefName":"main","headRefOid":"dddddddddddddddddddddddddddddddddddddddd","isDraft":true,"mergeable":"UNKNOWN","url":"https://github.com/acme/widgets/pull/42"}'
# Already ready. Stale AND conflicting on purpose: REQ-C1.8 requires the no-op
# to defer "regardless of currency/mergeability state".
VIEW_ALREADY_READY='{"baseRefName":"main","headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","isDraft":false,"mergeable":"CONFLICTING","url":"https://github.com/acme/widgets/pull/42"}'

# run_hook — drive the guard with a payload. Env overrides for the stub are
# passed through the caller's environment.
#   run_hook <payload-json> [extra-path-removals...]
run_hook() {
  local payload=$1
  shift
  rm -f "$STATE"/sentinel-* "$STATE/viewcount"
  : >"$STATE/argv.log"
  local path="$BIN"
  local removed t
  for removed in "$@"; do
    rm -f "$BIN/$removed"
  done
  OUT="$(printf '%s' "$payload" \
    | env -i PATH="$path" HOME="$SANDBOX" \
      GH_ARGV_LOG="$STATE/argv.log" GH_STATE="$STATE" \
      PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
      STUB_VIEW_JSON="${STUB_VIEW_JSON:-}" STUB_VIEW_JSON2="${STUB_VIEW_JSON2:-}" \
      STUB_VIEW_RC="${STUB_VIEW_RC:-0}" STUB_VIEW_RC2="${STUB_VIEW_RC2:-}" \
      STUB_COMPARE_OUT="${STUB_COMPARE_OUT:-0}" STUB_COMPARE_RC="${STUB_COMPARE_RC:-0}" \
      /bin/bash "$HOOK" 2>/dev/null)"
  CODE=$?
  # Restore anything an absence fixture removed.
  for removed in "$@"; do
    case $removed in
      gh) chmod +x "$BIN/gh" 2>/dev/null || : ;;
      *) t="$(command -v "$removed" 2>/dev/null)" && ln -sf "$t" "$BIN/$removed" ;;
    esac
  done
  if [ -n "${1:-}" ]; then
    for removed in "$@"; do
      [ "$removed" != gh ] || restore_gh_stub
    done
  fi
}

restore_gh_stub() {
  cp "$SANDBOX/gh.orig" "$BIN/gh"
  chmod +x "$BIN/gh"
}
cp "$BIN/gh" "$SANDBOX/gh.orig"

bash_payload() {
  jq -n --arg c "$1" --arg w "${2:-$WORK}" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}'
}

mcp_payload() {
  # <owner> <repo> <pullNumber-json> [<draft-json>]
  if [ "$#" -ge 4 ]; then
    jq -n --arg o "$1" --arg r "$2" --argjson n "$3" --argjson d "$4" \
      '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:$o, repo:$r, pullNumber:$n, draft:$d}}'
  else
    jq -n --arg o "$1" --arg r "$2" --argjson n "$3" \
      '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:$o, repo:$r, pullNumber:$n, title:"t"}}'
  fi
}

is_deny() {
  printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}
is_empty() { [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; }
reason() {
  printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null
}
# count_lines <pattern> — grep -c exits 1 on zero matches, so the count is
# captured and the status swallowed; a bare `grep -c || echo 0` would print two
# numbers and break every arithmetic comparison downstream.
count_lines() {
  local n
  n=$(grep -c -- "$1" "$STATE/argv.log" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}
gh_calls() { count_lines '^CALL'; }
pr_view_calls() { count_lines $'\tpr\tview'; }

# assert_deny <label> — pins the MISSED-DENY direction.
assert_deny() {
  local label=$1
  if [ "$CODE" != 0 ]; then
    fail "$label: expected exit 0, got $CODE"
    return
  fi
  if printf '%s' "$OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"(allow|ask)"'; then
    fail "$label: emitted allow/ask — the guard must only ever deny or defer"
    return
  fi
  if ! is_deny; then
    fail "$label: expected DENY, got '${OUT:-<empty>}'"
    return
  fi
  if [ -z "$(reason)" ]; then
    fail "$label: denied with an empty reason (REQ-K1.1)"
    return
  fi
  pass "$label"
}

# assert_defer <label> — pins the SPURIOUS-DENY direction.
assert_defer() {
  local label=$1
  if [ "$CODE" != 0 ]; then
    fail "$label: expected exit 0, got $CODE"
    return
  fi
  if ! is_empty; then
    fail "$label: expected DEFER (empty stdout), got '$OUT'"
    return
  fi
  pass "$label"
}

# assert_deny_because <label> <reason-regex> — DENY *and* the specific refusal
# that produced it. Use this wherever more than one branch could plausibly deny
# the same fixture; a bare assert_deny there lets the branch be deleted with the
# suite still green.
assert_deny_because() {
  assert_deny "$1"
  assert_reason_matches "$1 — for the stated reason" "$2"
}

assert_reason_matches() {
  local label=$1 re=$2
  if printf '%s' "$(reason)" | grep -Eqi -- "$re"; then
    pass "$label"
  else
    fail "$label: reason did not match /$re/ — got: $(reason)"
  fi
}

assert_reason_lacks() {
  local label=$1 re=$2
  if printf '%s' "$(reason)" | grep -Eqi -- "$re"; then
    fail "$label: reason should not mention /$re/ — got: $(reason)"
  else
    pass "$label"
  fi
}

assert_no_sentinels() {
  local label=$1 found=''
  local t
  for t in git curl wget claude; do
    [ ! -e "$STATE/sentinel-$t" ] || found="$found $t"
  done
  if [ -n "$found" ]; then
    fail "$label: the decision path invoked$found (REQ-D1.4 / D-5 violation)"
  else
    pass "$label"
  fi
}

reset_stub_env() {
  STUB_VIEW_JSON=''
  STUB_VIEW_JSON2=''
  STUB_VIEW_RC=0
  STUB_VIEW_RC2=''
  STUB_COMPARE_OUT=0
  STUB_COMPARE_RC=0
}
reset_stub_env

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
assert_deny "two positional targets deny (ambiguous)"

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
