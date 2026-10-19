#!/bin/bash
# Tests for worker-death classification on every completion reader
# (quota-handling REQ-A1.4, REQ-B1.1, REQ-E1.6): scripts/worker-death.sh, and
# the readers that use it — fleet-streamjson.sh status (the result frame and
# its exit fallback), fleet-dispatch-headless.sh status (result.json), and
# fleet-stuck-detector.sh classify.
#
# Covered:
#   - classify: a 529 death is a failure naming its cause, a rate-limit death
#     is `limited` against claude, a clean run is clean, and an earlier turn's
#     error or a tool result quoting a refusal does not mark a clean last turn;
#   - record: a rate-limit death holds the unit at step `worker` and engages
#     the throttle through `engage --until` with a stated reset time, or
#     `observe` with none (its own parse of the error text);
#   - REQ-A1.4, per reader: a fixture worker ending with a 529 and exit zero is
#     reported a named failure by the reader and the stuck detector, one ending
#     with a rate limit is reported `limited` with the throttle engaged, and no
#     fixture yields a clean completion.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-worker-death.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
WD="$repo_root/scripts/worker-death.sh"
SJ="$repo_root/scripts/fleet-streamjson.sh"
FDH="$repo_root/scripts/fleet-dispatch-headless.sh"
FSD="$repo_root/scripts/fleet-stuck-detector.sh"
FT="$repo_root/scripts/fleet-throttle.sh"
QH="$repo_root/scripts/quota-hold.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
pass() { echo "ok: $1"; }

[ -x "$WD" ] || fail "scripts/worker-death.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required: the stream-json launch preflight runs the auto-approve hook"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
printf 'fleet_daemon_pause: false\nfleet_throttle_default_hold: 120\nnotification_channel: push\nquota_ledger_retention_days: 90\n' >"$core_cfg"

home=""
new_home() {
  home="$tmp/home-$1"
  mkdir -p "$home"
}
# wenv <cmd...> — the case's fleet home and isolated config layers.
wenv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT \
    -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$home/fleet" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    "$@"
}
throttle_until() {
  wenv /bin/sh "$FT" check | sed -n "s/^until$TAB//p"
}
held_unit() {
  wenv /bin/sh "$QH" status --vendor claude | awk -F'\t' -v u="$1" '$1 == "holder" && $3 == u { print $4 }'
}

sid='11111111-2222-3333-4444-555555555555'
line_init='{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
line_clean='{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"'$sid'"}'
line_529='{"type":"result","subtype":"success","is_error":true,"api_error_status":529,"result":"API Error: 529 {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}","session_id":"'$sid'"}'
# The shapes a real rate-limit death leaves: the synthetic assistant frame
# carrying the error kind, then a result frame with the 429 status.
line_rl_msg='{"type":"assistant","message":{"id":"m1","model":"<synthetic>","role":"assistant","type":"message","content":[{"type":"text","text":"You have hit your weekly limit, resets in 2 hours"}]},"session_id":"'$sid'","error":"rate_limit"}'
line_rl_result='{"type":"result","subtype":"success","is_error":true,"api_error_status":429,"terminal_reason":"api_error","result":"You have hit your weekly limit, resets in 2 hours","session_id":"'$sid'"}'
# The 529 a stream can end on with no result frame at all.
line_529_msg='{"type":"assistant","message":{"id":"m2","model":"<synthetic>","role":"assistant","type":"message","content":[{"type":"text","text":"API Error: 529 Overloaded"}]},"session_id":"'$sid'","error":"overloaded"}'
# A tool result quoting a refusal is worker content, never its death.
line_quote='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"grep: rate_limit_error usage limit reached"}]},"session_id":"'$sid'"}'

evf() {
  ev_f="$tmp/ev-$1"
  shift
  printf '%s\n' "$@" >"$ev_f"
  printf '%s' "$ev_f"
}

# --- 1. classify -------------------------------------------------------------
new_home classify
out=$(wenv /bin/sh "$WD" classify --events "$(evf c529 "$line_init" "$line_529")") || fail "classify 529 exited non-zero"
[ "$out" = "failed${TAB}api-error-529" ] || fail "classify: a 529 death reads '$out'"
out=$(wenv /bin/sh "$WD" classify --events "$(evf crl "$line_init" "$line_rl_msg" "$line_rl_result")") || fail "classify rate limit exited non-zero"
[ "$out" = "limited${TAB}claude${TAB}claude.stream-rate-limit${TAB}-" ] || fail "classify: a rate-limit death reads '$out'"
out=$(wenv /bin/sh "$WD" classify --events "$(evf cok "$line_init" "$line_quote" "$line_clean")") || fail "classify clean exited non-zero"
[ "$out" = clean ] || fail "classify: a clean run quoting a refusal reads '$out'"
out=$(wenv /bin/sh "$WD" classify --events "$(evf cturn "$line_init" "$line_529" "$line_clean")") || fail "classify later turn exited non-zero"
[ "$out" = clean ] || fail "classify: an earlier turn's error marks the clean last turn: '$out'"
out=$(wenv /bin/sh "$WD" classify --events "$(evf crecov "$line_init" "$line_529_msg" "$line_clean")") || fail "classify recovered exited non-zero"
[ "$out" = clean ] || fail "classify: an unflagged result after a recovered error reads '$out'"
long='{"type":"result","subtype":"success","is_error":true,"terminal_reason":"an_unusually_long_terminal_reason_name","result":"x"}'
out=$(wenv /bin/sh "$WD" classify --events "$(evf clong "$line_init" "$long")") || fail "classify long cause exited non-zero"
[ "$out" = "failed${TAB}an-unusually-long-termin" ] || fail "classify: a long cause is not bounded to 24 bytes: '$out'"
out=$(wenv /bin/sh "$WD" classify --events "$(evf cnores "$line_init" "$line_529_msg")") || fail "classify no-result exited non-zero"
[ "$out" = "failed${TAB}api-error-529" ] || fail "classify: a stream ending on a synthetic 529 without a result reads '$out'"
printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"api_error_status":429,"result":"You have hit your weekly limit"}' >"$tmp/rj-rl"
out=$(wenv /bin/sh "$WD" classify --result-json "$tmp/rj-rl") || fail "classify result-json exited non-zero"
[ "$out" = "limited${TAB}claude${TAB}claude.api-rate-limit${TAB}-" ] || fail "classify: a headless 429 reads '$out'"
printf '%s\n' '{"is_error":true,"result":"Bash permission denied"}' >"$tmp/rj-perm"
out=$(wenv /bin/sh "$WD" classify --result-json "$tmp/rj-perm") || fail "classify generic error exited non-zero"
[ "$out" = "failed${TAB}is-error" ] || fail "classify: an error naming no cause reads '$out'"
rc=0
wenv /bin/sh "$WD" classify --events "$tmp/nope" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "classify: an unreadable input exits $rc, expected 6"
rc=0
wenv /bin/sh "$WD" record --unit '../x' --events "$tmp/ev-c529" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "record: a hostile unit exits $rc, expected 2"
pass "classify names a 529's cause, reads a rate limit as limited, and keeps clean turns clean"

# --- 2. record: hold and throttle (REQ-B1.1, REQ-E1.6) -----------------------
new_home record-observe
start=$(date +%s)
out=$(wenv /bin/sh "$WD" record --unit quota-handling:task-5 --events "$tmp/ev-crl" 2>"$tmp/err") || fail "record exited non-zero: $(cat "$tmp/err")"
[ "$out" = "limited${TAB}claude${TAB}claude.stream-rate-limit${TAB}-" ] || fail "record printed '$out'"
[ "$(held_unit quota-handling:task-5)" = worker ] || fail "record: the unit is not held at step worker"
until_v=$(throttle_until)
[ -n "$until_v" ] || fail "record: the throttle is not engaged"
# observe parses "resets in 2 hours" from the error text, not its default.
[ "$until_v" -ge $((start + 7200)) ] && [ "$until_v" -le $(($(date +%s) + 7200)) ] \
  || fail "record: observe did not read the stated relative reset (until $until_v, start $start)"
pass "a rate-limit death with no stated reset holds the unit and engages the throttle through observe"

new_home record-until
reset=$(($(date +%s) + 5400))
line_ul='{"type":"result","subtype":"success","is_error":true,"result":"Claude AI usage limit reached|'$reset'","session_id":"'$sid'"}'
out=$(wenv /bin/sh "$WD" record --unit spec-a:task-1 --events "$(evf cul "$line_init" "$line_ul")" 2>"$tmp/err") || fail "record (reset) exited non-zero: $(cat "$tmp/err")"
[ "$out" = "limited${TAB}claude${TAB}claude.usage-limit${TAB}$reset" ] || fail "record (reset) printed '$out'"
[ "$(throttle_until)" = "$reset" ] || fail "record: the throttle state does not carry the stated reset $reset: $(throttle_until)"
wenv /bin/sh "$QH" status --vendor claude | grep -q "^vendor${TAB}claude${TAB}held${TAB}[0-9]*${TAB}${reset}${TAB}1${TAB}" \
  || fail "record: the hold does not carry the stated reset"
pass "a rate-limit death with a stated reset engages the throttle through engage --until at that time"

new_home record-529
out=$(wenv /bin/sh "$WD" record --unit spec-a:task-1 --events "$tmp/ev-c529") || fail "record 529 exited non-zero"
[ "$out" = "failed${TAB}api-error-529" ] || fail "record 529 printed '$out'"
[ ! -d "$home/fleet/quota/claude" ] || fail "record: a 529 death held the vendor"
wenv /bin/sh "$FT" check >/dev/null || fail "record: a 529 death engaged the throttle"
pass "a non-limit API error holds nothing and leaves the throttle alone"

# --- 3. the stream-json reader: result frame and exit fallback --------------
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
IFS= read -r _line
cat "$SHIM_EVENTS"
exit "${SHIM_EXIT:-0}"
SHIM
chmod +x "$tmp/bin/claude"
printf 'work\n' >"$tmp/prompt"
sj() {
  wenv PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" /bin/sh "$SJ" "$@"
}
sj_case() {
  # sj_case <worker> <events-file> — run one foreground worker to its end.
  SHIM_EVENTS=$2 sj launch "$1" quota-handling:task-5 --prompt-file "$tmp/prompt" --foreground >/dev/null 2>"$tmp/err-$1" \
    || fail "stream-json $1: launch exited non-zero: $(cat "$tmp/err-$1")"
}
detect() {
  # detect <worker> <state-dir> <backend> — the stuck detector's completion reason.
  wenv /bin/sh "$FSD" classify "$1" --backend "$3" --state-dir "$2" --death-handle none \
    | awk -F'\t' '$1 == "worker" { print $3 " " $6 }'
}

for mode in result fallback; do
  new_home "sj-529-$mode"
  if [ "$mode" = result ]; then
    sj_case w529 "$tmp/ev-c529"
  else
    sj_case w529 "$tmp/ev-cnores"
  fi
  out=$(sj status w529) || fail "stream-json $mode 529: status exited non-zero"
  case $out in
    "status w529 ended "*"/cause=api-error-"*) ;;
    *) fail "stream-json $mode: a 529 death must be ended naming its cause, got: $out" ;;
  esac
  d=$(detect w529 "$home/fleet/streamjson/w529" stream-json-persistent)
  case $d in
    "unclassified completion-failed:"*"/cause=api-error-"*) ;;
    *) fail "stuck detector, stream-json $mode: a 529 death reads '$d'" ;;
  esac
  [ ! -d "$home/fleet/quota/claude" ] || fail "stream-json $mode: a 529 death held the vendor"

  new_home "sj-rl-$mode"
  if [ "$mode" = result ]; then
    sj_case wrl "$tmp/ev-crl"
  else
    sj_case wrl "$(evf "rlnores" "$line_init" "$line_rl_msg")"
  fi
  out=$(sj status wrl) || fail "stream-json $mode rate limit: status exited non-zero"
  case $out in
    "status wrl limited "*"/limited=claude") ;;
    *) fail "stream-json $mode: a rate-limit death must be limited against claude, got: $out" ;;
  esac
  d=$(detect wrl "$home/fleet/streamjson/wrl" stream-json-persistent)
  case $d in
    "unclassified completion-failed:"*"/limited=claude") ;;
    *) fail "stuck detector, stream-json $mode: a rate-limit death reads '$d'" ;;
  esac
  [ "$(held_unit quota-handling:task-5)" = worker ] || fail "stream-json $mode: the unit is not held at step worker"
  [ -n "$(throttle_until)" ] || fail "stream-json $mode: the throttle is not engaged"
done
pass "the stream-json result frame and its exit fallback name a 529 and read a rate limit as limited (REQ-A1.4)"

# A hand-corrupted cause field is dropped, never rendered.
sd_bad="$tmp/sd-bad"
mkdir -p "$sd_bad"
# shellcheck disable=SC2016 # the unexpanded substitution is the fixture
printf 'result\tsuccess\t1700000000\ttrue\tcause=$(x)\n' >"$sd_bad/result"
new_home sd-bad
d=$(detect wbad "$sd_bad" stream-json-persistent)
[ "$d" = "unclassified completion-failed:result=success/is_error=true" ] || fail "stuck detector: a hostile cause field reads '$d'"
pass "the stuck detector drops a cause field outside its grammar"

# --- 4. the headless reader: result.json -------------------------------------
cat >"$tmp/bin/headless-claude" <<'SHIM'
#!/bin/sh
cat >/dev/null
cat "$SHIM_RESULT"
exit 0
SHIM
chmod +x "$tmp/bin/headless-claude"
printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"api_error_status":529,"result":"API Error: 529 Overloaded"}' >"$tmp/rj-529"
hl() {
  wenv PLANWRIGHT_HEADLESS_CLAUDE="$tmp/bin/headless-claude" PLANWRIGHT_HEADLESS_STATE_DIR="$home/headless" \
    /bin/sh "$FDH" "$@"
}
hl_case() {
  # hl_case <id> <result-json> — launch one one-shot and wait for its record.
  mkdir -p "$home/wt"
  printf 'work\n' | SHIM_RESULT=$2 hl launch quota-handling "$1" --worktree "$home/wt" >/dev/null 2>"$tmp/err-hl" \
    || fail "headless $1: launch exited non-zero: $(cat "$tmp/err-hl")"
  n=0
  while [ ! -f "$home/headless/$1/exit" ] && [ "$n" -lt 300 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -f "$home/headless/$1/exit" ] || fail "headless $1: no completion record"
}
new_home hl-529
hl_case 5 "$tmp/rj-529"
rc=0
out=$(hl status quota-handling 5) || rc=$?
[ "$out" = "ended 0 api-error-529" ] && [ "$rc" = 6 ] || fail "headless: a 529 death reads '$out' (exit $rc), expected 'ended 0 api-error-529' (exit 6)"
d=$(detect headless-quota-handling-task-5 "$home/headless/5" headless-oneshot)
[ "$d" = "unclassified completion-failed:exit=0/is_error=true/cause=api-error-529" ] || fail "stuck detector, headless: a 529 death reads '$d'"
[ ! -d "$home/fleet/quota/claude" ] || fail "headless: a 529 death held the vendor"

new_home hl-rl
hl_case 5 "$tmp/rj-rl"
rc=0
out=$(hl status quota-handling 5) || rc=$?
[ "$out" = "limited 0 claude" ] && [ "$rc" = 7 ] || fail "headless: a rate-limit death reads '$out' (exit $rc), expected 'limited 0 claude' (exit 7)"
d=$(detect headless-quota-handling-task-5 "$home/headless/5" headless-oneshot)
[ "$d" = "unclassified completion-failed:exit=0/is_error=true/limited=claude" ] || fail "stuck detector, headless: a rate-limit death reads '$d'"
[ "$(held_unit quota-handling:5)" = worker ] || fail "headless: the unit is not held at step worker"
[ -n "$(throttle_until)" ] || fail "headless: the throttle is not engaged"

new_home hl-clean
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"done"}' >"$tmp/rj-ok"
hl_case 5 "$tmp/rj-ok"
out=$(hl status quota-handling 5) || fail "headless clean: status exited non-zero"
[ "$out" = "completed 0" ] || fail "headless: a clean run reads '$out'"
pass "the headless result.json reader names a 529 and reads a rate limit as limited (REQ-A1.4)"
