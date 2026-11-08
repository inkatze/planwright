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
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

inherited=$(fleet_home_inherited)
T=$(mktemp -d "${TMPDIR:-/tmp}/tspend.XXXXXX") || exit 1
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
assistant_line() { # id ts in cw5m cw1h cr out [branch] [sidechain] [agent]
  printf '{"type":"assistant","timestamp":"%s","sessionId":"s-a","cwd":"/w","gitBranch":"%s","isSidechain":%s,"agentId":"%s","message":{"id":"%s","model":"m1","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
    "$2" "${8:-feat/x}" "${9:-false}" "${10:-}" "$1" "$3" "$(($4 + $5))" "$6" "$7" "$4" "$5"
}
{
  printf '%s\n' '{"type":"user","sessionId":"s-a","message":{"role":"user","content":"<command-name>/planwright:mission-control</command-name> go <!-- mc-rules begin -->RULES<!-- mc-rules end -->"}}'
  assistant_line a1 2026-11-01T00:00:00.000Z 10 0 1000 0 100
  assistant_line a1 2026-11-01T00:00:00.500Z 10 0 1000 0 100
  assistant_line a2 2026-11-01T00:10:00.000Z 0 0 100 1000 50
  assistant_line a3 2026-11-01T02:00:00.000Z 0 0 2000 0 10
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-01T02:05:00.000Z","sessionId":"s-a","gitBranch":"feat/x","message":{"id":"a4","model":"m1","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"iterations":[{"input_tokens":1,"cache_read_input_tokens":300000,"cache_creation_input_tokens":0,"output_tokens":5}]}}}'
} >"$proj/s-a.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"s-a","isSidechain":true,"agentId":"ag1","message":{"role":"user","content":"You are a read-only reviewer of one file."}}'
  assistant_line b1 2026-11-01T00:05:00.000Z 0 400 0 0 20 feat/x true ag1
} >"$proj/s-a/subagents/agent-ag1.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"s-b","message":{"role":"user","content":"hello"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-02T00:00:00.000Z","sessionId":"s-b","gitBranch":"feat/x","message":{"id":"c1","model":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}'
  printf '%s\n' '{"type":"assistant", torn'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-02T00:01:00.000Z","sessionId":"s-b","gitBranch":"feat/x","message":{"id":"c2","model":"zz","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$proj/s-b.jsonl"
pn="tsp$(printf '%s' "${T##*.}" | tr '[:upper:]' '[:lower:]' | tr -dc 'a-z0-9')"
fleet="$T/fh/fleet"

# --- rows ---
"$SPEND" rows >"$T/rows.tsv" 2>"$T/rows.err"
assert_exit "rows over the transcript directory" 0 $?
rows=$(cat "$T/rows.tsv")
assert_contains "rows: the iterations sum stands in for zero top-level counters" "$(printf 'a4\ts-a\tmain\t2026-11-01T02:05:00.000Z\tm1\t1\t0\t0\t0\t300000\t5')" "$rows"
assert_contains "rows: a line past a torn one is still read" "$(printf 'c2\ts-b\tmain')" "$rows"
assert_eq "rows: a torn file's earlier lines print once" 1 "$(grep -c "$(printf '^m\tc1\t')" "$T/rows.tsv")"
assert_contains "rows: a sub-agent message carries its agent id" "$(printf '400\t0\t20\t/w\tfeat/x\tag1')" "$rows"
assert_contains "rows: the session line measures the rule block" "$(printf '\t28\t<command-name>/planwright:mission-control')" "$rows"
assert_eq "rows: a message written on two lines prints twice" 2 "$(grep -c "$(printf '^m\ta1\t')" "$T/rows.tsv")"
"$SPEND" rows --since 2099-01-01 >"$T/none.tsv"
assert_exit "rows --since a future date exits 0" 0 $?
assert_eq "rows --since a future date reads nothing" 0 "$(wc -l <"$T/none.tsv" | tr -d ' ')"
cp "$proj/s-b.jsonl" "$proj/s-old.jsonl"
sed -i.bak 's/"s-b"/"s-old"/g; s/"c1"/"o1"/; s/"c2"/"o2"/' "$proj/s-old.jsonl" && rm -f "$proj/s-old.jsonl.bak"
touch -t 202001010000 "$proj/s-old.jsonl"
since=$("$SPEND" rows --since 2026-01-01 2>/dev/null)
assert_exit "rows --since a past date exits 0" 0 $?
assert_contains "rows --since keeps a file written since" "$(printf 'c1\ts-b')" "$since"
case $since in *s-old*) fail "rows --since drops a file last written before the date" ;; *) ok "rows --since drops a file last written before the date" ;; esac
rm -f "$proj/s-old.jsonl"
"$SPEND" rows --since 2026-1-1 >/dev/null 2>&1
assert_exit "rows: a malformed --since is a usage error" 2 $?
"$SPEND" rows --since 2026-01-01 "$proj/s-b.jsonl" >/dev/null 2>&1
assert_exit "rows: --since with named files is a usage error" 2 $?
"$SPEND" rows "$T/missing.jsonl" >/dev/null 2>"$T/miss.err"
assert_exit "rows: an unreadable named file exits 1" 1 $?
assert_contains "rows: the unreadable file is named" "unreadable, skipped" "$(cat "$T/miss.err")"

# --- report ---
rep=$("$SPEND" report --prices "$prices" "$T/rows.tsv" 2>"$T/rep.err")
assert_exit "report exits 0" 0 $?
assert_contains "report: each message counted once, priced exactly" "messages 7  sessions 2  dollars \$38.68" "$rep"
assert_contains "report: the totals line splits dollars by class" "input 0.0M (\$0.02)  cache-write 0.0M (\$6.70)  cache-read 0.3M (\$30.10)  output 0.0M (\$1.86)" "$rep"
assert_contains "report: the unpriced model is named" "no price for model zz" "$(cat "$T/rep.err")"
assert_contains "report: by model" "$(printf "\$38.68\t0.3M\tm1")" "$rep"
assert_contains "report: by day" "$(printf "2026-11-01\t\$38.66\t5 msgs")" "$rep"
assert_contains "report: the session kind comes from the first prompt" "$(printf "mission-control\t1\t4\t\$38.66")" "$rep"
assert_contains "report: a session with no special prompt is interactive" "$(printf "interactive\t1\t2\t\$0.02")" "$rep"
assert_contains "report: a rebuild after an idle gap" "$(printf "idle-gap cache rebuilds (gap > 3600s)\t1 rebuilds\t0.0M\t\$4.00")" "$rep"
assert_contains "report: cache reads above the cap" "$(printf "context above 200000, cache-read\t1 turns\t0.1M\t\$10.00")" "$rep"
assert_contains "report: cold starts" "$(printf "cold-start cache writes\t2 sessions\t0.0M\t\$2.00")" "$rep"
assert_contains "report: warm-up writes" "$(printf "warm-up cache writes, main turns 2-10\t-\t0.0M\t\$0.20")" "$rep"
assert_contains "report: sub-agents" "$(printf "sub-agents\t1 agents\t0.0M\t\$0.70")" "$rep"
assert_contains "report: sub-agents classed by prompt, cost split" "$(printf "review-or-verify\t1\t\$0.70\t\$0.50\t\$0.20")" "$rep"
assert_contains "report: the 5-minute cache counterfactual" "$(printf "instead of 1 hour, net\t1 gaps of 5-60 min\t-\t\$1.18")" "$rep"
assert_contains "report: a second session on one branch" "$(printf "repeat sessions on one branch, beyond the first\t1 sessions\t-\t\$0.02")" "$rep"
assert_contains "report: the rule block is found" "$(printf 'mc-rules block re-read every turn, est.\t1 sessions')" "$rep"
rep=$("$SPEND" report --prices "$prices" --context-cap 400000 --idle 99999 --top 1 "$T/rows.tsv" 2>/dev/null)
assert_contains "report: --context-cap moves the cap" "$(printf 'context above 400000, cache-read\t0 turns')" "$rep"
assert_contains "report: --idle moves the gap" "$(printf 'gap > 99999s)\t0 rebuilds')" "$rep"
n=$(printf '%s\n' "$rep" | awk '/^== dearest sessions/ { on = 1; next } /^$/ { on = 0 } on { n++ } END { print n + 0 }')
assert_eq "report: --top bounds the rankings" 1 "$n"
"$SPEND" report --idle x "$T/rows.tsv" 2>/dev/null
assert_exit "report: a non-numeric --idle is a usage error" 2 $?
"$SPEND" report --top 1x "$T/rows.tsv" 2>/dev/null
assert_exit "report: a non-numeric --top is a usage error" 2 $?
"$SPEND" report "$T" 2>/dev/null
assert_exit "report: a directory is not a rows file" 2 $?
"$SPEND" report "$T/missing.tsv" 2>/dev/null
assert_exit "report: an unreadable rows file is a usage error" 2 $?
: >"$T/empty.tsv"
"$SPEND" report --prices "$T/empty.tsv" "$T/rows.tsv" >/dev/null 2>&1
assert_exit "report: an empty price table is refused" 2 $?
printf '# only a comment\n' >"$T/noprices.tsv"
"$SPEND" report --prices "$T/noprices.tsv" "$T/rows.tsv" >/dev/null 2>"$T/np.err"
assert_exit "report: a price table with no model is refused" 2 $?
assert_contains "report: the modelless table is named" "defines no model" "$(cat "$T/np.err")"
printf 'm1\t1000\tx\t100\t1250\t2000\n' >"$T/badprice.tsv"
"$SPEND" report --prices "$T/badprice.tsv" "$T/rows.tsv" >/dev/null 2>"$T/bp.err"
assert_exit "report: a non-numeric price is refused" 2 $?
assert_contains "report: the malformed price line is named" "line 1 is not a model and five prices" "$(cat "$T/bp.err")"
printf 'm1\t1000\t10000\t-100\t1250\t2000\n' >"$T/negprice.tsv"
"$SPEND" report --prices "$T/negprice.tsv" "$T/rows.tsv" >/dev/null 2>&1
assert_exit "report: a negative price is refused" 2 $?
printf 'm1\t1000\t10000\t100\t1250\t2000\nm2\t1\t2\n' >"$T/shortprice.tsv"
"$SPEND" report --prices "$T/shortprice.tsv" "$T/rows.tsv" >/dev/null 2>&1
assert_exit "report: a price row missing a column is refused" 2 $?
"$SPEND" report --prices "$prices" "$T/rows.tsv" "$T/rows.tsv" 2>/dev/null
assert_exit "report: two rows files is a usage error" 2 $?
"$SPEND" nope 2>/dev/null
assert_exit "an unknown verb is a usage error" 2 $?
"$SPEND" --help >/dev/null
assert_exit "--help exits 0" 0 $?
"$SPEND" report "$T/rows.tsv" >"$T/default.out" 2>/dev/null
assert_exit "report: the shipped price table loads" 0 $?

# --- report edge cases: prompt choice, kinds, control bytes, ids, times ---
edge="$T/edge"
mkdir -p "$edge"
esc=$(printf '\033')
bel=$(printf '\007')
{
  printf '%s\n' '{"type":"user","sessionId":"e1","message":{"role":"user","content":"<system-reminder>ignored</system-reminder>"}}'
  printf '%s\n' '{"type":"user","sessionId":"e1","message":{"role":"user","content":[{"type":"text","text":"/planwright:tower hi \u001b[31mred"}]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-03T00:00:00.000Z","sessionId":"e1","gitBranch":"br\u001b]0;T\u0007x","message":{"id":"e1m1","model":"m1[1m]","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
  printf '%s\n' '{"type":"assistant","sessionId":"e1","message":{"id":"e1m2","model":"m1","usage":{"input_tokens":0,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$edge/e1.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"e1","isSidechain":true,"agentId":"x1","message":{"role":"user","content":"Explore the tree for callers."}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-03T00:01:00.000Z","sessionId":"e1","isSidechain":true,"agentId":"x1","message":{"id":"x1m","model":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$edge/x1.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"e1","isSidechain":true,"agentId":"x2","message":{"role":"user","content":"Write the file."}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-03T00:02:00.000Z","sessionId":"e1","isSidechain":true,"agentId":"x2","message":{"id":"x2m","model":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$edge/x2.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"e2","message":{"role":"user","content":"brief <!-- mc-rules end --> x <!-- mc-rules begin -->"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-04T00:00:00.000Z","sessionId":"e2","message":{"model":"m1","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
  printf '%s\n' '{"type":"assistant", torn'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-04T00:01:00.000Z","sessionId":"e2","message":{"model":"m1","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$edge/e2.jsonl"
{
  printf '%s\n' '{"type":"user","sessionId":"e3","message":{"role":"user","content":"Visual flight <!-- mc-rules begin -->R<!-- mc-rules end -->"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-05T00:00:00.000Z","sessionId":"e3","message":{"id":"e3m1","model":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$edge/e3.jsonl"
"$SPEND" rows "$edge/e1.jsonl" "$edge/x1.jsonl" "$edge/x2.jsonl" "$edge/e2.jsonl" "$edge/e3.jsonl" >"$T/edge.tsv"
assert_exit "rows over named files" 0 $?
edge_rows=$(cat "$T/edge.tsv")
assert_contains "rows: the first real prompt, from array content, is the session line" "$(printf 's\te1\tmain\t\t')" "$edge_rows"
assert_contains "rows: a rule end before its begin measures nothing" "$(printf 's\te2\tmain\t\t53\t0\t')" "$edge_rows"
assert_eq "rows: a message with no id prints a dash" 2 "$(grep -c "$(printf '^m\t-\te2\t')" "$T/edge.tsv")"
{
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-04T00:00:00.000Z","sessionId":"e4","message":{"id":"","model":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-04T00:01:00.000Z","sessionId":"e4","message":{"id":"","model":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-04T00:02:00.000Z","sessionId":"e4","uuid":"u9","message":{"id":"","model":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}'
} >"$edge/e4.jsonl"
e4=$("$SPEND" rows "$edge/e4.jsonl")
assert_eq "rows: an empty id prints a dash, never merged" 2 "$(printf '%s\n' "$e4" | grep -c "$(printf '^m\t-\te4\t')")"
assert_contains "rows: an empty id falls back to the uuid" "$(printf 'm\tu9\te4\t')" "$e4"
erep=$("$SPEND" report --prices "$prices" "$T/edge.tsv" 2>"$T/edge.err")
assert_exit "report over the edge rows exits 0" 0 $?
assert_contains "report: messages with no id are each counted once" "messages 7  sessions 3" "$erep"
assert_contains "report: a tower session" "$(printf 'tower\t1\t2')" "$erep"
assert_contains "report: a rule block marks a launched session" "$(printf 'mc-launched\t1\t1')" "$erep"
assert_contains "report: a context-suffixed model is priced by its base id" "$(printf "\$1.25\te1\ttower")" "$erep"
case $(cat "$T/edge.err") in *"m1[1m]"*) fail "report: the base id prices a suffixed model silently" ;; *) ok "report: the base id prices a suffixed model silently" ;; esac
assert_contains "report: an undated message is named" "carry no timestamp" "$(cat "$T/edge.err")"
assert_contains "report: an undated message is no rebuild" "$(printf 'gap > 3600s)\t0 rebuilds')" "$erep"
assert_contains "report: an unsplit cache write is priced at 5 minutes" "$(printf "cold-start cache writes\t3 sessions\t0.0M\t\$1.25")" "$erep"
assert_contains "report: an explore sub-agent" "$(printf 'explore\t1\t')" "$erep"
assert_contains "report: another sub-agent" "$(printf 'other\t1\t')" "$erep"
assert_contains "report: control bytes are dropped from a branch" "br]0;Tx" "$erep"
case $erep in *"$esc"* | *"$bel"*) fail "report: no control byte reaches the terminal" ;; *) ok "report: no control byte reaches the terminal" ;; esac

# --- report over crafted rows: input no transcript produces ---
crafted="$T/crafted.tsv"
{
  printf 'm\tk1\tk\tmain\t2026-11-06T00:00:00.000Z\tm1\t10\t0\t0\t0\t0\t0\t/w\tc\302\302\233\233x\t\n'
  printf 'm\tk2\tk\tsub\t2026-11-06T00:01:00.000Z\tm1\t5000000\t0\t0\t0\t0\t0\t/w\tcx\tag\n'
} >"$crafted"
crep=$("$SPEND" report --prices "$prices" "$crafted" 2>/dev/null)
assert_exit "report over crafted rows exits 0" 0 $?
c1=$(printf '\302\233')
case $crep in *"$c1"*) fail "report: a C1 control split by another is still dropped" ;; *) ok "report: a C1 control split by another is still dropped" ;; esac
assert_contains "report: peak context counts main turns only" "$(printf '\tk\tunknown\t1\t0.0\t0.0M\t')" "$crep"

# --- spend-record ---
out=$("$RECORD" record --program "$pn" --session s-a --unit pr-1 --prices "$prices")
assert_exit "record by session" 0 $?
assert_contains "record: totals over the session and its sub-agents" "$(printf 'pr-1\ts-a\t-\tfeat/x\t4\t2026-11-01T00:00:00.000Z\t2026-11-01T02:05:00.000Z\t11\t3500\t301000\t185\t38.6610')" "$out"
store="$fleet/mission-control/$pn/spend.tsv"
assert_eq "record: the store opens with its format line" "# format: 1" "$(head -n 1 "$store")"
"$RECORD" record --program "$pn" --session s-a --unit pr-1 --prices "$prices" >/dev/null
out=$("$RECORD" record --program "$pn" --session s-b --prices "$prices" 2>"$T/rec.err")
assert_contains "record: the unit defaults to the session id" "$(printf 's-b\ts-b\t-')" "$out"
assert_contains "record: an unpriced model is named" "no price for model zz" "$(cat "$T/rec.err")"
mkdir -p "$fleet/mission-control/sessions" "$fleet/streamjson/h1"
printf 'format\t1\nname\tmc-demo-worker-1\nprogram\t%s\nkind\tworker\nscope\tflight-x\nhandle\th1\n' "$pn" >"$fleet/mission-control/sessions/mc-demo-worker-1"
printf 's-b\n' >"$fleet/streamjson/h1/session"
out=$("$RECORD" record --program "$pn" --launch mc-demo-worker-1 --prices "$prices" 2>/dev/null)
assert_contains "record by launch: unit and kind from the launch record" "$(printf 'flight-x\ts-b\tworker\tfeat/x\t2')" "$out"
out=$("$RECORD" record --program "$pn" --launch mc-demo-worker-1 --unit u2 --kind k2 --prices "$prices" 2>/dev/null)
assert_contains "record by launch: --unit and --kind override" "$(printf 'u2\ts-b\tk2\t')" "$out"
read_all=$("$RECORD" read --program "$pn")
assert_contains "read: a session recorded twice counts once" "$(printf 'pr-1\t1\t4\t11\t3500\t301000\t185\t38.66')" "$read_all"
assert_contains "read: the total" "$(printf 'total\t2\t6\t22\t3500\t301000\t186\t38.68')" "$read_all"
one=$("$RECORD" read --program "$pn" --unit pr-1)
assert_contains "read --unit keeps only that unit" "$(printf 'total\t1\t4\t11')" "$one"

printf 'format\t1\nprogram\tother\nhandle\th1\nscope\tz\n' >"$fleet/mission-control/sessions/mc-demo-worker-3"
"$RECORD" record --program "$pn" --launch mc-demo-worker-3 --prices "$prices" >/dev/null 2>&1
assert_exit "record: another program's launch is refused" 1 $?
ln -s "$fleet/mission-control/sessions/mc-demo-worker-1" "$fleet/mission-control/sessions/mc-demo-link"
"$RECORD" record --program "$pn" --launch mc-demo-link --prices "$prices" >/dev/null 2>&1
assert_exit "record: a symlinked launch record is refused" 1 $?
printf 'format\t1\nprogram\t%s\nhandle\th2\nscope\tz\n' "$pn" >"$fleet/mission-control/sessions/mc-demo-worker-2"
"$RECORD" record --program "$pn" --launch mc-demo-worker-2 --prices "$prices" >/dev/null 2>&1
assert_exit "record: a launch with no session id exits 1" 1 $?
"$RECORD" record --program "$pn" --launch mc-nope --prices "$prices" >/dev/null 2>&1
assert_exit "record: a missing launch record exits 1" 1 $?
"$RECORD" record --program "$pn" --launch ../../x --prices "$prices" >/dev/null 2>&1
assert_exit "record: a launch name with a path is refused" 2 $?
"$RECORD" record --program ../../x --session s-a --prices "$prices" >/dev/null 2>&1
assert_exit "record: a program name with a path is refused" 2 $?
if [ ! -e "$T/fh/x" ] && [ ! -e "$fleet/x" ]; then ok "record: a refused program name writes nothing"; else fail "record: a refused program name writes nothing"; fi
"$RECORD" record --program "$pn" --session 'a/b' --prices "$prices" >/dev/null 2>&1
assert_exit "record: a session id with a path is refused" 2 $?
"$RECORD" record --program "$pn" --session nope --prices "$prices" >/dev/null 2>&1
assert_exit "record: a session with no transcript exits 1" 1 $?
mkdir -p "$proj/s-empty"
printf '%s\n' '{"type":"user","sessionId":"s-empty","message":{"role":"user","content":"hi"}}' >"$proj/s-empty.jsonl"
before=$(wc -l <"$store")
"$RECORD" record --program "$pn" --session s-empty --prices "$prices" >/dev/null 2>&1
assert_exit "record: a transcript with no usage exits 1" 1 $?
cp "$proj/s-b.jsonl" "$proj/s-locked.jsonl"
mkdir -p "$proj/s-locked/subagents"
cp "$proj/s-a/subagents/agent-ag1.jsonl" "$proj/s-locked/subagents/"
# Root reads a mode-000 file, so the unreadable case only holds for others.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$proj/s-locked.jsonl"
  "$RECORD" record --program "$pn" --session s-locked --prices "$prices" >/dev/null 2>&1
  assert_exit "record: a transcript that cannot be read exits 1" 1 $?
  chmod 600 "$proj/s-locked.jsonl"
fi
assert_eq "record: a failed record appends nothing" "$before" "$(wc -l <"$store")"
"$RECORD" record --program "$pn" --session s-a --prices "$T/empty.tsv" >/dev/null 2>&1
assert_exit "record: an empty price table is refused" 2 $?
"$RECORD" record --program "$pn" --session s-a --prices "$T/badprice.tsv" >/dev/null 2>&1
assert_exit "record: a malformed price table is refused" 2 $?
"$RECORD" record --program "$pn" --session s-a --launch mc-demo-worker-1 >/dev/null 2>&1
assert_exit "record: --session with --launch is a usage error" 2 $?
"$RECORD" record --program 'a b' --session s-a >/dev/null 2>&1
assert_exit "record: a program name with a space is refused" 2 $?
"$RECORD" read --program "$pn" --unit >/dev/null 2>&1
assert_exit "read: a flag without its value is a usage error" 2 $?

hand="tsphand${pn#tsp}"
mkdir -p "$fleet/mission-control/$hand"
{
  printf '# format: 1\n'
  printf '200\tu\tsx\t-\t-\t9\t2026-11-01T00:00:00Z\t2026-11-01T05:00:00Z\t9\t9\t9\t9\t9.0000\n'
  printf '300\tu\tsx\t-\t-\t1\t2026-11-01T00:00:00Z\t2026-11-01T01:00:00Z\t1\t1\t1\t1\t1.0000\n'
  printf 'torn\tline\n'
  printf '\n'
} >"$fleet/mission-control/$hand/spend.tsv"
assert_contains "read: the row with the latest last-ts wins" "$(printf 'u\t1\t9\t9\t9\t9\t9\t9.00')" "$("$RECORD" read --program "$hand")"
fresh="tspfresh${pn#tsp}"
assert_eq "read: a program with no store prints a zero total" "$(printf 'total\t0\t0\t0\t0\t0\t0\t0.00')" "$("$RECORD" read --program "$fresh")"
if [ ! -e "$fleet/mission-control/$fresh" ]; then ok "read: reading creates nothing"; else fail "read: reading creates nothing"; fi
bad="tspbad${pn#tsp}"
mkdir -p "$fleet/mission-control/$bad"
printf 'no format line\n' >"$fleet/mission-control/$bad/spend.tsv"
"$RECORD" read --program "$bad" >/dev/null 2>&1
assert_exit "read: a store with an unknown format is refused" 2 $?
"$RECORD" record --program "$bad" --session s-a --prices "$prices" >/dev/null 2>&1
assert_exit "record: a store with an unknown format is refused" 2 $?
linked="tsplink${pn#tsp}"
mkdir -p "$fleet/mission-control/$linked"
printf '# format: 1\n' >"$T/elsewhere.tsv"
ln -s "$T/elsewhere.tsv" "$fleet/mission-control/$linked/spend.tsv"
"$RECORD" record --program "$linked" --session s-a --prices "$prices" >/dev/null 2>&1
assert_exit "record: a symlinked store is refused" 2 $?
assert_eq "record: a symlinked store's target is untouched" 1 "$(wc -l <"$T/elsewhere.tsv" | tr -d ' ')"
"$RECORD" read --program "$linked" >/dev/null 2>&1
assert_exit "read: a symlinked store is refused" 2 $?
rm -f "$T/elsewhere.tsv"
"$RECORD" read --program "$linked" >/dev/null 2>&1
assert_exit "read: a dangling symlinked store is refused" 2 $?

: >"$T/blocker"
PLANWRIGHT_FLEET_STATE_DIR="$T/blocker/fleet" "$RECORD" record --program "$pn" --session s-a --prices "$prices" >/dev/null 2>&1
assert_exit "record: a store directory that cannot be created exits 2" 2 $?

if [ -n "$inherited" ] && [ -e "$inherited/mission-control/$pn" ]; then
  fail "a write leaked into the inherited fleet home"
else
  ok "no write leaked into the inherited fleet home"
fi

[ "$failures" -eq 0 ] || exit 1
