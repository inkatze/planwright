#!/bin/bash
# Tests for scripts/token-spend.sh (rows and report) and scripts/spend-record.sh
# (record and read) over fixture transcripts, a fixture price table, a fixture
# launch record and a pinned fleet home.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEND="$REPO_ROOT/scripts/token-spend.sh"
RECORD="$REPO_ROOT/scripts/spend-record.sh"
# shellcheck source=tests/lib/fleet-home.sh
. "$REPO_ROOT/tests/lib/fleet-home.sh"

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
line_of() { printf '%s\n' "$2" | grep -F -- "$1" | head -n 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/tspend.XXXXXX")
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$T/claude"
unset CLAUDE_PLUGIN_DATA
mkdir -p "$HOME"
fleet_home_pin "$T/fh" || {
  echo "FAIL: could not pin the fleet home" >&2
  exit 1
}

# Prices scaled so every fixture cost prints exactly at two decimals.
prices="$T/prices.tsv"
printf '# fixture\nmodel\tinput\toutput\tcache_read\tcache_write_5m\tcache_write_1h\nm1\t1000\t10000\t100\t1250\t2000\n' >"$prices"

proj="$CLAUDE_CONFIG_DIR/projects/demo"
mkdir -p "$proj/s-a/subagents"
a() { # id ts in cw5m cw1h cr out [branch] [sidechain] [agent]
  printf '{"type":"assistant","timestamp":"%s","sessionId":"s-a","cwd":"/w","gitBranch":"%s","isSidechain":%s,"agentId":"%s","message":{"id":"%s","model":"m1","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
    "$2" "${8:-feat/x}" "${9:-false}" "${10:-}" "$1" "$3" "$(($4 + $5))" "$6" "$7" "$4" "$5"
}
{
  printf '%s\n' '{"type":"user","sessionId":"s-a","message":{"role":"user","content":"<command-name>/planwright:mission-control</command-name> go <!-- mc-rules begin -->RULES<!-- mc-rules end -->"}}'
  a a1 2026-11-01T00:00:00.000Z 10 0 1000 0 100
  a a1 2026-11-01T00:00:00.500Z 10 0 1000 0 100
  a a2 2026-11-01T00:10:00.000Z 0 0 100 1000 50
  a a3 2026-11-01T02:00:00.000Z 0 0 2000 0 10
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-01T02:05:00.000Z","sessionId":"s-a","gitBranch":"feat/x","message":{"id":"a4","model":"m1","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"iterations":[{"input_tokens":1,"cache_read_input_tokens":300000,"cache_creation_input_tokens":0,"output_tokens":5}]}}}'
} >"$proj/s-a.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"s-a","isSidechain":true,"agentId":"ag1","message":{"role":"user","content":"You are a read-only reviewer of one file."}}'
  a b1 2026-11-01T00:05:00.000Z 0 400 0 0 20 feat/x true ag1
} >"$proj/s-a/subagents/agent-ag1.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"s-b","message":{"role":"user","content":"hello"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-02T00:00:00.000Z","sessionId":"s-b","gitBranch":"feat/x","message":{"id":"c1","model":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}'
  printf '%s\n' '{"type":"assistant", torn'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-02T00:01:00.000Z","sessionId":"s-b","gitBranch":"feat/x","message":{"id":"c2","model":"zz","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$proj/s-b.jsonl"

# --- rows ---
"$SPEND" rows >"$T/rows.tsv" 2>"$T/rows.err"
assert_exit "rows over the transcript directory" 0 $?
rows=$(cat "$T/rows.tsv")
assert_contains "rows: the iterations sum stands in for zero top-level counters" "$(printf 'a4\ts-a\tmain\t2026-11-01T02:05:00.000Z\tm1\t1\t0\t0\t0\t300000\t5')" "$rows"
assert_contains "rows: a line past a torn one is still read" "$(printf 'c2\ts-b\tmain')" "$rows"
assert_contains "rows: a sub-agent message carries its agent id" "$(printf '400\t0\t20\t/w\tfeat/x\tag1')" "$rows"
assert_contains "rows: the session line measures the rule block" "$(printf '\t28\t<command-name>/planwright:mission-control')" "$rows"
n=$(grep -c "$(printf '^m\ta1\t')" "$T/rows.tsv")
assert_exit "rows: a message written on two lines prints twice" 2 "$n"
"$SPEND" rows --since 2099-01-01 >"$T/none.tsv"
assert_exit "rows --since a future date reads nothing" 0 "$(wc -l <"$T/none.tsv" | tr -d ' ')"

# --- report ---
rep=$("$SPEND" report --prices "$prices" "$T/rows.tsv" 2>"$T/rep.err")
assert_exit "report exits 0" 0 $?
assert_contains "report: each message counted once, priced exactly" "messages 7  sessions 2  dollars \$38.68" "$rep"
assert_contains "report: the unpriced model is named" "no price for model zz" "$(cat "$T/rep.err")"
assert_contains "report: the session kind comes from the first prompt" "$(printf "mission-control\t1\t4\t\$38.66")" "$rep"
assert_contains "report: a rebuild after an idle gap" "$(printf "idle-gap cache rebuilds (gap > 3600s)\t1 rebuilds\t0.0M\t\$4.00")" "$rep"
assert_contains "report: cache reads above the cap" "$(printf "context above 200000, cache-read\t1 turns\t0.1M\t\$10.00")" "$rep"
assert_contains "report: cold starts" "$(printf "cold-start cache writes\t2 sessions\t0.0M\t\$2.00")" "$rep"
assert_contains "report: warm-up writes" "$(printf "warm-up cache writes, main turns 2-10\t-\t0.0M\t\$0.20")" "$rep"
assert_contains "report: sub-agents" "$(printf "sub-agents\t1 agents\t0.0M\t\$0.70")" "$rep"
assert_contains "report: sub-agents classed by prompt, cost split" "$(printf "review-or-verify\t1\t\$0.70\t\$0.50\t\$0.20")" "$rep"
assert_contains "report: the 5-minute cache counterfactual counts the mid gap" "$(printf 'instead of 1 hour, net\t1 gaps of 5-60 min')" "$rep"
assert_contains "report: a second session on one branch" "$(printf "repeat sessions on one branch, beyond the first\t1 sessions\t-\t\$0.02")" "$rep"
assert_contains "report: the rule block is found" "$(printf 'mc-rules block re-read every turn, est.\t1 sessions')" "$rep"
rep=$("$SPEND" report --prices "$prices" --context-cap 400000 --idle 99999 "$T/rows.tsv" 2>/dev/null)
assert_contains "report: --context-cap moves the cap" "$(printf 'context above 400000, cache-read\t0 turns')" "$rep"
assert_contains "report: --idle moves the gap" "$(printf 'gap > 99999s)\t0 rebuilds')" "$rep"
"$SPEND" report --idle x "$T/rows.tsv" 2>/dev/null
assert_exit "report: a non-numeric --idle is a usage error" 2 $?
"$SPEND" report "$T" 2>/dev/null
assert_exit "report: a directory is not a rows file" 2 $?
"$SPEND" report "$T/missing.tsv" 2>/dev/null
assert_exit "report: an unreadable rows file is a usage error" 2 $?
"$SPEND" nope 2>/dev/null
assert_exit "an unknown verb is a usage error" 2 $?
"$SPEND" --help >/dev/null
assert_exit "--help exits 0" 0 $?

# --- spend-record ---
out=$("$RECORD" record --program demo --session s-a --unit pr-1 --prices "$prices")
assert_exit "record by session" 0 $?
assert_contains "record: totals over the session and its sub-agents" "$(printf 'pr-1\ts-a\t-\tfeat/x\t4\t2026-11-01T00:00:00.000Z\t2026-11-01T02:05:00.000Z\t11\t3500\t301000\t185\t38.6610')" "$out"
store="$T/fh/fleet/mission-control/demo/spend.tsv"
assert_contains "record: the store opens with its format line" "# format: 1" "$(head -n 1 "$store")"
"$RECORD" record --program demo --session s-a --unit pr-1 --prices "$prices" >/dev/null
mkdir -p "$T/fh/fleet/mission-control/sessions" "$T/fh/fleet/streamjson/h1"
printf 'format\t1\nname\tmc-demo-worker-1\nkind\tworker\nscope\tflight-x\nhandle\th1\n' >"$T/fh/fleet/mission-control/sessions/mc-demo-worker-1"
printf 's-b\n' >"$T/fh/fleet/streamjson/h1/session"
out=$("$RECORD" record --program demo --launch mc-demo-worker-1 --prices "$prices" 2>/dev/null)
assert_contains "record by launch: unit and kind from the launch record" "$(printf 'flight-x\ts-b\tworker\tfeat/x\t2')" "$out"
read_all=$("$RECORD" read --program demo)
assert_contains "read: a session recorded twice counts once" "$(printf 'pr-1\t1\t4\t11\t3500\t301000\t185\t38.66')" "$read_all"
assert_contains "read: the total" "$(printf 'total\t2\t6\t22\t3500\t301000\t186\t38.68')" "$read_all"
one=$("$RECORD" read --program demo --unit flight-x)
assert_contains "read --unit keeps only that unit" "$(printf 'total\t1\t2\t11')" "$one"
"$RECORD" record --program demo --session nope >/dev/null 2>&1
assert_exit "record: a session with no transcript exits 1" 1 $?
printf 'format\t1\nhandle\th2\nscope\tz\n' >"$T/fh/fleet/mission-control/sessions/mc-demo-worker-2"
"$RECORD" record --program demo --launch mc-demo-worker-2 >/dev/null 2>&1
assert_exit "record: a launch with no session id exits 1" 1 $?
"$RECORD" record --program demo --session s-a --launch mc-demo-worker-1 >/dev/null 2>&1
assert_exit "record: --session with --launch is a usage error" 2 $?
"$RECORD" record --program 'a b' --session s-a >/dev/null 2>&1
assert_exit "record: a program name with a space is refused" 2 $?
"$RECORD" read --program demo --unit >/dev/null 2>&1
assert_exit "read: a flag without its value is a usage error" 2 $?
if fleet_home_leaked "$T"; then fail "a write leaked into the inherited fleet home"; else ok "no write leaked into the inherited fleet home"; fi

[ "$failures" -eq 0 ] || exit 1
