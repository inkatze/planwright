#!/bin/bash
# Tests for the answer verb's self-description and owner check
# (scripts/fleet-streamjson.sh `answer`).
#
#   a1: an answer echoes, before acting, the screened command's first line (and
#       only the first), the worker's name and its owning program, on stderr,
#       so the call that delivers it is self-describing to a reader of the
#       transcript.
#   a2: a mission-control session answering a worker its own program owns
#       passes, echo included, and the answer reaches the worker.
#   a3: a mission-control session answering another program's worker is
#       refused with nothing written, naming the owner; the request stays
#       pending and the owner can still answer it.
#   a4: a token that matches no mission-control row, and a worker with no
#       recorded owner, are refused fail closed.
#   a5: a caller holding no mission-control token (the operator's shell)
#       answers as before.
#   a6: the echo carries no control byte from the command.
#
# Hermetic: the fleet home and the CLI seam are case-local, the CLI is a shim
# that records its stdin. Runs standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"
# shellcheck source=tests/lib/fixture-procs.sh
. "$here/lib/fixture-procs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required: the launch preflight runs the auto-approve hook"

tmp=$(fixture_scratch) || fail "no scratch directory to run in"
tab=$(printf '\t')
live_pids=''
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  for cl_p in $live_pids; do
    kill "$cl_p" 2>/dev/null || :
  done
  fixture_reap "$tmp/"
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
if [ -n "${SHIM_EVENTS:-}" ]; then
  cat "$SHIM_EVENTS"
fi
(sleep "${SHIM_WATCHDOG:-300}" && kill "$$" 2>/dev/null) &
while IFS= read -r line; do
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
done
SHIM
chmod +x "$tmp/bin/claude"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT -u PLANWRIGHT_MC_TOKEN
)

# senv <home> <record-dir> [VAR=val...] -- <args...>
senv() {
  se_home=$1
  se_rec=$2
  shift 2
  se_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    se_pre+=("$1")
    shift
  done
  shift
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$se_home" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$se_rec" \
    ${se_pre[@]+"${se_pre[@]}"} /bin/sh "$SJ" "$@"
}

lines_of() {
  if [ -f "$1" ]; then
    wc -l <"$1" | tr -d ' '
  else
    echo 0
  fi
}

# session_row <home> <name> <program> <kind> <token> — a launcher registry row.
session_row() {
  mkdir -p "$1/mission-control/sessions"
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\t%s\nprogram\t%s\nowner\tmission-control:%s\nkind\t%s\nbackend\tstream-json\nlaunched\t1\n' \
    "$2" "$5" "$3" "$3" "$4" >"$1/mission-control/sessions/$2"
}

start_worker() {
  sw_home=$1
  sw_rec=$2
  sw_h=$3
  shift 3
  mkdir -p "$sw_rec"
  printf 'begin\n' >"$tmp/prompt-$sw_h"
  senv "$sw_home" "$sw_rec" "$@" -- \
    launch "$sw_h" fleet-lifecycle-closure:9 --prompt-file "$tmp/prompt-$sw_h" --foreground \
    >/dev/null 2>&1 &
  live_pids="$live_pids $!"
  poll_until --what 'the user turn' -- grep -q '"type":"user"' "$sw_rec/stdin" \
    || fail "$sw_h: the worker never received its initial prompt"
}

sid='11111111-2222-3333-4444-555555555555'
req='aaaa1111-bbbb-cccc-dddd-eeee00000001'
line_init='{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
# A two-line command whose second line must never be echoed, and a raw ESC in
# the first (as the JSON escape the CLI emits) that must not reach the echo.
line_perm='{"type":"control_request","request_id":"'$req'","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git status --short\u001b[31m\nrm -rf SECONDLINE","description":"d"},"tool_use_id":"t1"}}'
printf '%s\n%s\n' "$line_init" "$line_perm" >"$tmp/ev-perm"

home="$tmp/h1"
rec="$tmp/r1"
start_worker "$home" "$rec" mc-p1-worker-a SHIM_EVENTS="$tmp/ev-perm"
wdir="$home/streamjson/mc-p1-worker-a"
poll_until --what 'the journal row' -- grep -q "^$req" "$wdir/journal" || fail "setup: the pending journal row never appeared"
session_row "$home" mc-p1-worker-a p1 worker -
session_row "$home" mc-p1-mission-control p1 mission-control tok-p1
session_row "$home" mc-p2-mission-control p2 mission-control tok-p2

# a3: another program's mission control is refused, naming the owner.
before=$(lines_of "$rec/stdin")
out=$(senv "$home" "$rec" PLANWRIGHT_MC_TOKEN=tok-p2 -- answer mc-p1-worker-a "$req" --allow 2>&1)
rc=$?
[ "$rc" = 2 ] || fail "a3: another program's answer must be refused with exit 2, got $rc: $out"
case $out in *"owned by mission-control:p1"*"mission-control for p2, not the owner"*) : ;; *) fail "a3: the refusal must name the owner and the caller's program: $out" ;; esac
case $out in *"mc-p1-worker-a"*) : ;; *) fail "a3: the refusal must name the worker: $out" ;; esac
[ "$(lines_of "$rec/stdin")" = "$before" ] || fail "a3: a refused answer reached the worker"
grep -q pending "$wdir/journal" || fail "a3: a refused answer must leave the request pending"
echo "ok: a3 an answer to another program's worker is refused, naming the owner, with nothing written"

# a4: an unrecognised token and an unowned worker are refused.
out=$(senv "$home" "$rec" PLANWRIGHT_MC_TOKEN=tok-nobody -- answer mc-p1-worker-a "$req" --allow 2>&1)
rc=$?
[ "$rc" = 2 ] || fail "a4: a token matching no row must be refused with exit 2, got $rc: $out"
case $out in *"owned by mission-control:p1"*"matches no registered mission-control session"*) : ;; *) fail "a4: the refusal must name the owner and the unmatched token: $out" ;; esac
[ "$(lines_of "$rec/stdin")" = "$before" ] || fail "a4: a refused answer reached the worker"
home4="$tmp/h4"
rec4="$tmp/r4"
start_worker "$home4" "$rec4" sj-orphan SHIM_EVENTS="$tmp/ev-perm"
poll_until --what 'the journal row' -- grep -q "^$req" "$home4/streamjson/sj-orphan/journal" || fail "a4: the pending journal row never appeared"
session_row "$home4" mc-p1-mission-control p1 mission-control tok-p1
out=$(senv "$home4" "$rec4" PLANWRIGHT_MC_TOKEN=tok-p1 -- answer sj-orphan "$req" --allow 2>&1)
rc=$?
[ "$rc" = 2 ] || fail "a4: a worker with no recorded owner must be refused with exit 2, got $rc: $out"
case $out in *"has no recorded owner, so no mission-control session may answer it"*) : ;; *) fail "a4: the refusal must say the worker has no recorded owner: $out" ;; esac
[ "$(lines_of "$rec4/stdin")" = 1 ] || fail "a4: a refused answer reached the unowned worker"
echo "ok: a4 an unknown token and an unowned worker are refused"

# a1, a2, a6: the owning mission control passes, and the call describes itself.
out=$(senv "$home" "$rec" PLANWRIGHT_MC_TOKEN=tok-p1 -- answer mc-p1-worker-a "$req" --allow 2>"$tmp/a2.err")
rc=$?
[ "$rc" = 0 ] || fail "a2: the owning program's answer must pass, got $rc: $out $(cat "$tmp/a2.err")"
case $out in "answered mc-p1-worker-a $req") : ;; *) fail "a2: stdout must stay the plain receipt, got: $out" ;; esac
poll_until --what 'the answer on stdin' -- grep -q control_response "$rec/stdin" || fail "a2: the answer never reached the worker"
echo_line=$(grep 'git status --short' "$tmp/a2.err") || fail "a1: no echo of the command's first line: $(cat "$tmp/a2.err")"
case $echo_line in *"mc-p1-worker-a"*"p1"*) : ;; *) fail "a1: the echo must name the worker and its program: $echo_line" ;; esac
grep -q 'SECONDLINE' "$tmp/a2.err" && fail "a1: only the command's first line may be echoed"
LC_ALL=C grep -q "$(printf '\033')" "$tmp/a2.err" && fail "a6: a control byte from the command reached the echo"
echo "ok: a1 a2 a6 the owning program's answer passes and echoes command, worker and program, one sanitized line"

# a5: no token (the operator's shell) answers as before, echo included.
home5="$tmp/h5"
rec5="$tmp/r5"
start_worker "$home5" "$rec5" sj-plain SHIM_EVENTS="$tmp/ev-perm"
poll_until --what 'the journal row' -- grep -q "^$req" "$home5/streamjson/sj-plain/journal" || fail "a5: the pending journal row never appeared"
out=$(senv "$home5" "$rec5" -- answer sj-plain "$req" --allow 2>"$tmp/a5.err") \
  || fail "a5: a caller with no token must answer as before: $out $(cat "$tmp/a5.err")"
poll_until --what 'the answer on stdin' -- grep -q control_response "$rec5/stdin" || fail "a5: the answer never reached the worker"
grep -q 'git status --short' "$tmp/a5.err" || fail "a5: the echo applies to every answer: $(cat "$tmp/a5.err")"
echo "ok: a5 a caller with no mission-control token answers as before"

for sp in "$tmp/h1:mc-p1-worker-a" "$tmp/h4:sj-orphan" "$tmp/h5:sj-plain"; do
  senv "${sp%%:*}" "$tmp/r1" -- stop "${sp##*:}" --grace 1 >/dev/null 2>&1 || :
done
poll_until --what 'no fixture process left' -- fixture_none "$tmp/" \
  || fail "no supervisor, tick, or shim from this run may outlive the suite: $(fixture_report "$tmp/")"
echo "all fleet-streamjson-answer-owner tests passed"
