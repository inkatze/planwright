#!/bin/bash
# Tests for scripts/review-cost.sh — tokens per convergence run and the
# post-convergence finding rate — over fixture transcripts, fleet events, a
# miss ledger, and a recorded PR history (review-effectiveness REQ-H1.4,
# REQ-H1.1, D-7).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COST="$REPO_ROOT/scripts/review-cost.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rcost.XXXXXX")
trap 'rm -rf "$T"' EXIT

# --- transcripts: two sessions, one polish run ended by PR creation, one
# self-review run ended by a human message ---
proj="$T/projects/demo"
mkdir -p "$proj/s1/subagents"
u() { printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"id":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":%s}%s}}\n' "$@"; }
{
  printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:00Z","sessionId":"s1","message":{"role":"user","content":"<command-name>/planwright:execute-task</command-name>"}}'
  u 2026-10-01T00:01:00Z s1 m1 100 0 10 ''
  u 2026-10-01T00:02:00Z s1 m2 0 1000 0 ',"content":[{"type":"tool_use","name":"Skill","input":{"skill":"planwright:polish"}}]'
  u 2026-10-01T00:03:00Z s1 m3 0 2000 0 ''
  u 2026-10-01T00:03:01Z s1 m3 0 2000 0 ''
  printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:04:00Z","sessionId":"s1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}'
  u 2026-10-01T00:05:00Z s1 m4 0 500 0 ',"content":[{"type":"tool_use","name":"Bash","input":{"command":"gh pr create --draft --title x"}}]'
  u 2026-10-01T00:06:00Z s1 m5 300 0 0 ''
} >"$proj/s1.jsonl"
{
  u 2026-10-01T00:03:30Z s1 a1 0 4000 0 ''
  u 2026-10-01T00:09:00Z s1 a2 0 7000 0 ''
} >"$proj/s1/subagents/agent-x.jsonl"
{
  printf '%s\n' '{"type":"user","timestamp":"2026-10-02T00:00:00Z","sessionId":"s2","message":{"role":"user","content":"<command-message>self-review</command-message>\n<command-name>/self-review</command-name>"}}'
  u 2026-10-02T00:01:00Z s2 m6 0 3000 0 ''
  printf '%s\n' '{"type":"user","timestamp":"2026-10-02T00:02:00Z","sessionId":"s2","message":{"role":"user","content":"thanks, that looks right"}}'
  u 2026-10-02T00:03:00Z s2 m7 1000 0 0 ''
} >"$proj/s2.jsonl"

# --- the fleet events: s2's unit total is larger than its transcript shows ---
events="$T/events.jsonl"
printf '%s\n' '{"type":"result","session_id":"s2","usage":{"input_tokens":8000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}' >"$events"

# --- the PR history and the miss ledger ---
hist="$T/history.json"
cat >"$hist" <<'EOF'
{"repo":"example/repo","prs":[
 {"number":10,"author":"owner","merged_at":"2026-10-01T00:00:00Z","body":"",
  "reviews":[{"author":"helper-bot","bot":true},{"author":"helper-bot","bot":true}],
  "threads":[
   {"path":"a.sh","line":1,"commit":"0123456789abcdef0123456789abcdef01234567","author":"helper-bot","bot":true,"body":"x","replies":[{"author":"owner","body":"Fixed in abc1234"}]},
   {"path":"a.sh","line":9,"commit":"0123456789abcdef0123456789abcdef01234567","author":"helper-bot","bot":true,"body":"y","replies":[{"author":"owner","body":"Addressed in abc1234"}]}]},
 {"number":11,"author":"owner","merged_at":"2026-10-02T00:00:00Z","body":"",
  "reviews":[{"author":"helper-bot","bot":true}],"threads":[]},
 {"number":12,"author":"owner","merged_at":"2026-10-03T00:00:00Z","body":"","reviews":[],"threads":[]},
 {"number":13,"author":"owner","merged_at":"2026-10-04T00:00:00Z","body":"",
  "reviews":[{"author":"helper-bot","bot":true}],"threads":[]}
]}
EOF
ledger="$T/entries"
mkdir -p "$ledger"
printf '%s\n' "- 2026-10-05 [planwright] review-miss(correctness, runtime-tracing): #13 b.sh: a fix the pass missed" >"$ledger/2026-10-05-review-miss-0000aaaa.md"

base="$T/baselines.tsv"
printf 'post_convergence_finding_rate\t0.889\tfixture\nmedian_tokens_per_convergence_run\t17000000\tfixture\n' >"$base"

run() {
  "$COST" --transcripts "$proj" --events "$events" --history "$hist" \
    --ledger-dir "$ledger" --baselines "$base" "$@"
}

out=$(run --prs-from 10 2>&1)
assert_exit "the metric runs over fixtures" 0 $?
assert_contains "counts the convergence runs" "convergence runs: 2" "$out"
assert_contains "the median run spans a PR-creation end, a human-message end, and subagents" "tokens per convergence run (median): 5000" "$out"
assert_contains "the unit share prefers the fleet events' total" "convergence share of unit (median): 0.42" "$out"
assert_contains "counts the externally reviewed PRs in the window" "externally reviewed PRs: 3" "$out"
assert_contains "a ledger entry counts as a post-convergence finding" "PRs with a fixed post-convergence finding: 2" "$out"
assert_contains "computes the finding rate" "post-convergence finding rate: 0.667" "$out"
assert_contains "computes the median fixed findings" "fixed findings per such PR (median): 1.5" "$out"
assert_contains "computes the median review rounds" "review rounds per such PR (median): 1.5" "$out"
assert_contains "counts the miss-ledger entries" "miss-ledger entries in window: 1" "$out"
assert_contains "refuses a verdict on a window under the closeout minimum" "verdict: window too small (3 < 15)" "$out"

out=$(run --prs-from 11 2>&1)
assert_contains "the PR window narrows the rate" "post-convergence finding rate: 0.500" "$out"

out=$(run --prs-from 10 --min-window 1 2>&1)
assert_contains "both metrics below baseline meet the bar" "verdict: met" "$out"
printf 'post_convergence_finding_rate\t0.889\tfixture\nmedian_tokens_per_convergence_run\t1000\tfixture\n' >"$base"
out=$(run --prs-from 10 --min-window 1 2>&1)
assert_contains "tokens above baseline miss the bar" "verdict: missed" "$out"

# --- the committed baselines carry every REQ-H1.1 value ---
B="$REPO_ROOT/tests/fixtures/review-backtest/baselines.tsv"
for k in post_convergence_finding_rate median_fixed_findings_per_pr median_review_rounds_per_pr \
  median_tokens_per_convergence_run convergence_share_of_unit lens_none_share; do
  if grep -q "^$k	" "$B"; then ok "baseline records $k"; else fail "baseline lacks $k"; fi
done
out=$("$COST" --transcripts "$proj" --events "$events" --history "$hist" --ledger-dir "$ledger" 2>&1)
assert_contains "the committed baselines are the default comparison" "baseline: rate 0.889" "$out"

"$COST" --history "$T/absent.json" --transcripts "$proj" >/dev/null 2>&1
assert_exit "an unreadable history is a usage error" 2 $?
"$COST" --history "$hist" --transcripts "$proj" --prs-from x >/dev/null 2>&1
assert_exit "a non-integer window bound is refused" 2 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-cost tests passed"
