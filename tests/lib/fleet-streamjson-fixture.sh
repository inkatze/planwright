# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # the fixture reads `here` and sets variables the sourcing suites read
# Shared fixture for the fleet-streamjson suites: the env-driven CLI shim, the
# hermetic supervisor and attention runners (senv, aenv), the lock and liveness
# helpers, and the scratch teardown. The sourcing suite sets `here` to the tests
# directory before sourcing. Sourcing creates the scratch directory `tmp`,
# installs the EXIT, INT and TERM traps that reap everything a case left
# running, and exits 1 when jq or either script is missing. The suites end by
# calling assert_nothing_left_running.
#
# Hermetic: every case pins PLANWRIGHT_FLEET_STATE_DIR to a case-local home
# and PLANWRIGHT_STREAMJSON_CLI to a single env-driven shim (one inode, so a
# macOS Gatekeeper first-exec assessment happens at most once). Runs
# standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
# shellcheck source=tests/lib/dead-owner.sh
. "$here/lib/dead-owner.sh"
SJ="$here/../scripts/fleet-streamjson.sh"
FA="$here/../scripts/fleet-attention.sh"
# Nearly every wait here is on a detached supervisor's record, and a loaded
# macOS runner has taken past the helper's 60s default to reach one.
POLL_UNTIL_DEFAULT_DEADLINE=${POLL_UNTIL_DEFAULT_DEADLINE:-300}
# shellcheck source=tests/lib/fixture-procs.sh
. "$here/lib/fixture-procs.sh"
supervisor_deadline=$POLL_UNTIL_DEFAULT_DEADLINE

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"
# The launch preflight runs the worker-command-guard, whose payload read needs
# jq; without it every launch below would refuse for the wrong reason.
command -v jq >/dev/null 2>&1 || fail "jq is required: the launch preflight runs the auto-approve hook"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(fixture_scratch) || fail "no scratch directory to run in"
# The script reports roots canonically; a symlinked TMPDIR (macOS's /var)
# would otherwise never match them.
tmp=$(cd -P -- "$tmp" && pwd -P) || fail "cannot canonicalize the scratch directory"
# Teardown on every exit, a failed case's and an interrupt's included: close
# each worker whose supervisor is still running through the script's own stop
# path, then reap anything left that carries this run's scratch path, so no
# case's supervisor, tick, or shim survives the suite whichever way it ends.
# A second interrupt is ignored until the reap is done. Several cases leave
# fabricated or stale pid files behind, and `stop` seeds its walk from them
# unchecked, so it runs only where the recorded pid is this run's supervisor.
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  mkdir -p "$tmp/reap"
  for cl_dir in "$tmp"/h*/streamjson/*/; do
    cl_dir=${cl_dir%/}
    cl_pid=$(cat "$cl_dir/supervisor.pid" 2>/dev/null) || continue
    case $cl_pid in '' | *[!0-9]*) continue ;; esac
    case $(ps -ww -p "$cl_pid" -o args= 2>/dev/null) in
      *"_supervise ${cl_dir##*/} $cl_dir "*) ;;
      *) continue ;;
    esac
    senv "${cl_dir%/streamjson/*}" "$tmp/reap" -- stop "${cl_dir##*/}" --grace 2 >/dev/null 2>&1
  done
  fixture_reap "$tmp/"
  # A root outside the fixture (c39's default base) outlives it otherwise.
  for cl_rec in "$tmp"/h*/scratch/*.tmpdir; do
    [ -f "$cl_rec" ] || continue
    cl_home=${cl_rec%/scratch/*}
    cl_root=$(head -n 1 "$cl_rec")
    case $cl_root/ in
      "$tmp"/*) ;;
      *) /bin/sh "$here/../scripts/fleet-scratch.sh" release "$cl_home" "$cl_root" >/dev/null 2>&1 ;;
    esac
  done
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tab=$(printf '\t')

# --- fixtures ---------------------------------------------------------------

# The single env-driven CLI shim. One inode for the whole suite.
mkdir -p "$tmp/bin"
mkdir -m 700 "$tmp/scratch-base"
# Every launch below, through senv or not, keeps its scratch root in the
# fixture; c39's second worker alone takes the default base, on purpose.
export PLANWRIGHT_FLEET_SCRATCH_BASE="$tmp/scratch-base"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
# stream-json CLI shim (fixture), driven by env:
#   SHIM_RECORD_DIR   records argv + stdin lines (required)
#   SHIM_EVENTS       file of event lines emitted on stdout
#   SHIM_READ_FIRST   stdin lines to read+record before emitting (default 1)
#   SHIM_DELAY        sleep before emitting (a slow host's worker)
#   SHIM_WAIT_RESPONSE=1  after emitting, read+record stdin until a
#                     control_response arrives, then emit SHIM_RESULT_LINE
#   SHIM_WATCHDOG     seconds before self-kill while waiting (no-auto-answer)
#   SHIM_SLEEP        sleep after emitting (crash-window hold)
#   SHIM_EXIT         exit code (default 0)
printf '%s\n' "$*" >>"$SHIM_RECORD_DIR/argv"
# The wrapper execs this shim, so it cannot appear in argv; what it leaves
# behind is the environment, which is the property worth asserting.
printf 'ghost=%s\n' "${CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'plugin_root=%s\n' "${CLAUDE_PLUGIN_ROOT-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'spec_root=%s\n' "${PLANWRIGHT_WORKER_SPEC_ROOT-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'record=%s\n' "${PLANWRIGHT_WORKER_SESSION_RECORD-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'tmpdir=%s\n' "${TMPDIR-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'handle=%s\n' "${PLANWRIGHT_WORKER_HANDLE-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'scope=%s\n' "${PLANWRIGHT_WORKER_SCOPE-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'inbound=%s\n' "${PLANWRIGHT_MESSAGING_INBOUND-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'backend=%s\n' "${PLANWRIGHT_SESSION_BACKEND-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'launch_token=%s\n' "${PLANWRIGHT_WORKER_LAUNCH_TOKEN-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'mc_token=%s\n' "${PLANWRIGHT_MC_TOKEN-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'tower=%s/%s/%s/%s\n' "${PLANWRIGHT_TOWER_ID-<unset>}" "${PLANWRIGHT_TOWER_SESSION_ID-<unset>}" \
  "${PLANWRIGHT_TOWER_PID-<unset>}" "${PLANWRIGHT_TOWER_CHECKOUT-<unset>}" >>"$SHIM_RECORD_DIR/env"
n=${SHIM_READ_FIRST:-1}
i=0
while [ "$i" -lt "$n" ]; do
  IFS= read -r line || break
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
  i=$((i + 1))
done
if [ -n "${SHIM_DELAY:-}" ]; then
  sleep "$SHIM_DELAY"
fi
if [ -n "${SHIM_EVENTS:-}" ]; then
  cat "$SHIM_EVENTS"
fi
if [ -n "${SHIM_WATCHDOG:-}" ]; then
  (sleep "$SHIM_WATCHDOG" && kill "$$" 2>/dev/null) &
fi
if [ "${SHIM_WAIT_RESPONSE:-0}" = 1 ]; then
  while IFS= read -r line; do
    printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
    case $line in
      *control_response*) break ;;
    esac
  done
  if [ -n "${SHIM_RESULT_LINE:-}" ]; then
    printf '%s\n' "$SHIM_RESULT_LINE"
  fi
fi
if [ -n "${SHIM_SLEEP:-}" ]; then
  sleep "$SHIM_SLEEP"
fi
exit "${SHIM_EXIT:-0}"
SHIM
chmod +x "$tmp/bin/claude"

sid='11111111-2222-3333-4444-555555555555'
req_perm='aaaa1111-bbbb-cccc-dddd-eeee00000001'
req_q='aaaa1111-bbbb-cccc-dddd-eeee00000002'

line_init='{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
line_perm='{"type":"control_request","request_id":"'$req_perm'","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/x/y.txt","content":"hello {brace} \"quoted\""},"tool_use_id":"t1"}}'
line_q='{"type":"control_request","request_id":"'$req_q'","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Which way?","options":[{"label":"a"},{"label":"b"}]}]},"tool_use_id":"t2"}}'
line_result='{"type":"result","subtype":"success","result":"done","session_id":"'$sid'"}'
# init + one pending permission request, then the worker holds open.
ev_hold="$tmp/ev-hold"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev_hold"

# The ambient overlay/config knobs every hermetic runner strips. Held in one
# array so a knob added here reaches all of them; a runner that hand-copied the
# list would silently stop scrubbing the next one added, and the failure mode is
# a case reading the developer's real fleet home.
env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u PLANWRIGHT_MC_TOKEN
)

# senv <home> <record-dir> [SHIM_VAR=val...] -- <args...> — hermetic
# supervisor invocation: ambient overlay/config knobs stripped, the fleet
# home and shim pinned per case.
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
    PLANWRIGHT_FLEET_SCRATCH_BASE="$tmp/scratch-base" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$se_rec" \
    ${se_pre[@]+"${se_pre[@]}"} /bin/sh "$SJ" "$@"
}

# aenv <home> <args...> — hermetic fleet-attention read (queue assertions).
aenv() {
  ae_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$ae_home" /bin/sh "$FA" "$@"
}

# ps_rows — one `<pid> <ppid> <args>` row per process, captured through a
# variable so the assertion's own `grep` (whose argv would carry the very path
# being searched for) is never in the snapshot it is searching. Mirrors the
# script's own degradation to the narrow form when `ps` rejects `-ww`.
ps_rows() {
  pr_out=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
  case ${pr_out%%"
"*} in
    *[0-9]*) ;;
    *) pr_out=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || pr_out='' ;;
  esac
  [ -n "$pr_out" ] || fail "ps_rows: this host produced no usable process table"
  printf '%s\n' "$pr_out"
}

# plant_lock <lock-path> <owner-pid> — plant a held lock in the shape the
# primitive creates (scripts/lock-lib.sh): a symlink whose target is the owner's
# `<pid>-<epoch>-<seq>` token. Staleness is that owner's absence, so the pid
# handed in is the whole of what a case is saying about the lock. The token is
# published in `planted_token` for cases that assert the lock was left alone.
plant_lock() {
  planted_token="$2-$(date +%s)-1"
  rm -rf "$1"
  ln -s "$planted_token" "$1" || fail "cannot plant a lock at $1"
}

# A pid that is deterministically dead: above every host's pid ceiling, so no
# process can hold it. A reaped child's pid would not do: the host can hand it
# out again while the cases below still read it as gone.
dead_pid=999999999

# live_pids <worker-dir> — make a worker whose run has ended read as live, with
# this suite's own shell standing in for its supervisor and worker; unlive_pids
# takes that back. An ended worker's requests are settled by a scan, never
# escalated, so a case asserting escalation needs a live worker.
live_pids() {
  printf '%s\n' "$$" >"$1/supervisor.pid"
  printf '%s\n' "$$" >"$1/worker.pid"
}
unlive_pids() {
  rm -f "$1/supervisor.pid" "$1/worker.pid"
}

# assert_nothing_left_running — the suite leaves nothing running. Every
# supervisor, tick, and shim a case starts carries this run's scratch directory
# in its argv, so one still running once the cases are done, or a descendant of
# one, is something a case launched and never closed. A tick notices its
# supervisor is gone only at its next step, so the set gets the poll deadline to
# drain before it counts as leaked; every shim a case starts outlives that
# deadline, so a close that missed one is still caught.
assert_nothing_left_running() {
  poll_until --what 'no fixture process left' -- fixture_none "$tmp/" \
    || fail "c37: fixture process(es) still running after every case: $(fixture_report "$tmp/")"
}
