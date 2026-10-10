#!/bin/bash
# The SessionStart arm of scripts/fleet-liveness.sh, the worker's own startup
# confirmation for a tmux launch (fleet-hardening REQ-G1.5, D-15):
#   s1  a valid identity with a launch token writes `working` carrying the
#       token, prints nothing (SessionStart stdout reaches the model), exits 0
#   s2  no identity is a silent no-op
#   s3  a half-set or malformed identity is refused with nothing written
#   s4  a malformed launch token is refused with nothing written
#   s5  a valid identity with no token writes a plain `working` row
#   s6  a queued human decision (an awaiting-input row) is never overwritten
#   s7  hooks/hooks.json wires the arm under both the startup and resume
#       matchers
#   s8  the store's heartbeat refuses a malformed --launch-token
#   s9  the store's --unless-since keeps a row stamped at or after its epoch,
#       replaces an older one, and refuses a malformed epoch
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-liveness-session-start.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FL="$here/../scripts/fleet-liveness.sh"
FA="$here/../scripts/fleet-attention.sh"
HOOKS="$here/../hooks/hooks.json"
TAB=$(printf '\t')
TOK=0123456789abcdef0123456789abcdef

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/t-liveness-ss.XXXXXX") || {
  echo "test-fleet-liveness-session-start: cannot create a temporary directory" >&2
  exit 1
}
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/adopter"
printf 'stale_marker_threshold: 15m\n' >"$tmp/core.yml"

# start <home> <source> [VAR=value...] — fire the arm with a SessionStart
# payload, as Claude Code does, and only the given worker variables set.
# Sets RC, OUT, ERR.
start() {
  local home=$1 src=$2
  shift 2
  printf '{"session_id":"s1","hook_event_name":"SessionStart","source":"%s"}\n' "$src" \
    | env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME -u PLANWRIGHT_ROOT \
      -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u PLANWRIGHT_WORKER_LAUNCH_TOKEN \
      PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core.yml" \
      PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG="" \
      "$@" /bin/sh "$FL" hook session-start >"$tmp/out" 2>"$tmp/err"
  RC=$?
  OUT=$(cat "$tmp/out")
  ERR=$(cat "$tmp/err")
}

attn() {
  local home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FA" "$@"
}

# row_field <home> <worker> <n> — field <n> of the worker's store row.
row_field() {
  [ -f "$1/attention/state" ] || return 0
  awk -F "$TAB" -v w="$2" -v f="$3" '($1 "") == (w "") { print $f }' "$1/attention/state"
}

# --- s1 -------------------------------------------------------------------------
h="$tmp/s1"
before=$(date +%s)
start "$h" startup PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-3 PLANWRIGHT_WORKER_SCOPE=demo:3 \
  PLANWRIGHT_WORKER_LAUNCH_TOKEN=$TOK
[ "$RC" -eq 0 ] || fail "s1: the arm exited $RC ($ERR)"
[ -z "$OUT" ] || fail "s1: the arm printed to stdout, which SessionStart hands the model: $OUT"
[ "$(row_field "$h" tmux-demo-task-3 3)" = working ] \
  || fail "s1: state '$(row_field "$h" tmux-demo-task-3 3)', expected working"
[ "$(row_field "$h" tmux-demo-task-3 2)" = demo:3 ] || fail "s1: the row's scope is not the worker's"
[ "$(row_field "$h" tmux-demo-task-3 9)" = "launch:$TOK" ] \
  || fail "s1: the row does not carry the launch token: '$(row_field "$h" tmux-demo-task-3 9)'"
ts=$(row_field "$h" tmux-demo-task-3 4)
[ -n "$ts" ] && [ "$ts" -ge "$before" ] || fail "s1: the row is not stamped at commit time ($ts < $before)"
# A resumed session confirms the same way.
start "$tmp/s1r" resume PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-3 PLANWRIGHT_WORKER_SCOPE=demo:3 \
  PLANWRIGHT_WORKER_LAUNCH_TOKEN=$TOK
[ "$(row_field "$tmp/s1r" tmux-demo-task-3 9)" = "launch:$TOK" ] || fail "s1: a resume did not confirm"

# --- s2 -------------------------------------------------------------------------
start "$tmp/s2" startup PLANWRIGHT_WORKER_LAUNCH_TOKEN=$TOK
[ "$RC" -eq 0 ] || fail "s2: no identity must exit 0, got $RC"
[ ! -e "$tmp/s2/attention/state" ] || fail "s2: a session with no identity wrote the store"
[ -z "$OUT$ERR" ] || fail "s2: a session with no identity must be silent: $OUT$ERR"

# --- s3 -------------------------------------------------------------------------
start "$tmp/s3" startup PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-3 PLANWRIGHT_WORKER_LAUNCH_TOKEN=$TOK
[ "$RC" -eq 0 ] || fail "s3: a half-set identity must still exit 0, got $RC"
[ ! -e "$tmp/s3/attention/state" ] || fail "s3: a half-set identity wrote the store"
case $ERR in *refusing*) ;; *) fail "s3: a half-set identity is not refused by name: $ERR" ;; esac
start "$tmp/s3b" startup PLANWRIGHT_WORKER_HANDLE='../x' PLANWRIGHT_WORKER_SCOPE=demo:3
[ "$RC" -eq 0 ] || fail "s3: a malformed handle must still exit 0, got $RC"
[ ! -e "$tmp/s3b/attention/state" ] || fail "s3: a malformed handle wrote the store"

# --- s4 -------------------------------------------------------------------------
for bad in 0123ABCD0123abcd 0123 "$TOK$TOK$TOK" "0123456789abcdef;x"; do
  start "$tmp/s4" startup PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-3 PLANWRIGHT_WORKER_SCOPE=demo:3 \
    PLANWRIGHT_WORKER_LAUNCH_TOKEN="$bad"
  [ "$RC" -eq 0 ] || fail "s4: a malformed token must still exit 0, got $RC"
  [ ! -e "$tmp/s4/attention/state" ] || fail "s4: a malformed token '$bad' wrote the store"
done

# --- s5 -------------------------------------------------------------------------
start "$tmp/s5" startup PLANWRIGHT_WORKER_HANDLE=headless-demo-task-4 PLANWRIGHT_WORKER_SCOPE=demo:4
[ "$(row_field "$tmp/s5" headless-demo-task-4 3)" = working ] || fail "s5: no working row without a token"
[ -z "$(row_field "$tmp/s5" headless-demo-task-4 9)" ] || fail "s5: a row without a token carries field 9"

# --- s6 -------------------------------------------------------------------------
attn "$tmp/s6" decide tmux-demo-task-3 demo:3 "stuck?" park "park|retry" >/dev/null 2>&1 \
  || fail "s6: setup decide failed"
start "$tmp/s6" resume PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-3 PLANWRIGHT_WORKER_SCOPE=demo:3 \
  PLANWRIGHT_WORKER_LAUNCH_TOKEN=$TOK
[ "$(row_field "$tmp/s6" tmux-demo-task-3 3)" = awaiting-input ] \
  || fail "s6: a session start overwrote a queued decision ($(row_field "$tmp/s6" tmux-demo-task-3 3))"

# --- s7 -------------------------------------------------------------------------
for m in startup resume; do
  n=$(jq -r --arg m "$m" '[.hooks.SessionStart[] | select(.matcher == $m) | .hooks[]
      | select(.type == "command" and (.command | endswith("/scripts/fleet-liveness.sh hook session-start")))]
      | length' "$HOOKS" 2>/dev/null) || n=''
  [ "$n" = 1 ] || fail "s7: the SessionStart '$m' matcher does not wire the arm exactly once (got '$n')"
done

# --- s8 -------------------------------------------------------------------------
attn "$tmp/s8" heartbeat w1 demo:1 working --launch-token NOTHEX >/dev/null 2>&1 \
  && fail "s8: heartbeat accepted a malformed launch token"
[ ! -e "$tmp/s8/attention/state" ] || fail "s8: a refused launch token wrote the store"
attn "$tmp/s8" heartbeat w1 demo:1 working --unless-awaiting --launch-token "$TOK" >/dev/null 2>&1 \
  || fail "s8: heartbeat refused a valid launch token"
[ "$(row_field "$tmp/s8" w1 9)" = "launch:$TOK" ] || fail "s8: heartbeat did not record the token"

# --- s9 -------------------------------------------------------------------------
attn "$tmp/s9" heartbeat w2 demo:2 idle >/dev/null 2>&1 || fail "s9: setup heartbeat failed"
s9ts=$(row_field "$tmp/s9" w2 4)
attn "$tmp/s9" heartbeat w2 demo:2 working --unless-since "$s9ts" >/dev/null 2>&1 \
  || fail "s9: --unless-since must be a clean no-op over a newer row"
[ "$(row_field "$tmp/s9" w2 3)" = idle ] || fail "s9: --unless-since overwrote a row stamped at its epoch"
attn "$tmp/s9" heartbeat w2 demo:2 working --unless-since "$((s9ts + 1))" >/dev/null 2>&1 \
  || fail "s9: --unless-since refused a write over an older row"
[ "$(row_field "$tmp/s9" w2 3)" = working ] || fail "s9: --unless-since kept a row stamped before its epoch"
for bad in 0123 -1 12a "" 1234567890123456; do
  attn "$tmp/s9" heartbeat w2 demo:2 idle --unless-since "$bad" >/dev/null 2>&1 \
    && fail "s9: --unless-since accepted '$bad'"
done
[ "$(row_field "$tmp/s9" w2 3)" = working ] || fail "s9: a refused --unless-since wrote the store"

[ "$fails" -eq 0 ] || {
  echo "test-fleet-liveness-session-start: $fails failure(s)" >&2
  exit 1
}
echo "ok: test-fleet-liveness-session-start"
