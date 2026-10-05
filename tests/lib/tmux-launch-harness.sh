# shellcheck shell=bash
# shellcheck disable=SC2034 # the TLH_* results are read by the sourcing suite
# tmux-launch-harness.sh — the shared fixture harness for the tmux rung's
# launch tests (sourced, never executed). It exists so a launch fixture can
# fail but never hang, cannot pass because the test's own environment leaked
# into the worker, compares paths the way the filesystem resolves them, and
# leaves no process behind. tests/test-tmux-launch-harness.sh is its
# self-test. Safe under `set -e` and `set -u`.
#
# Inputs read before sourcing: TLH_LAUNCH_BOUND_SECONDS (default 30) and
# TLH_CONFIRM_CAP_SECONDS (default 2), whole seconds; TLH_SYMLINKED_TMP;
# TLH_PLUGIN_ROOT.
#
# Sourcing runs setup. It exits the sourcing suite (status 1) when the suite
# has not defined a `fail` function (every assertion here reports through it),
# when the bound or the cap is not whole seconds or the bound does not exceed
# the cap, when a sandbox, checkout, or plugin-root path holds a single quote
# or a newline (or PATH a newline), or when the sandbox cannot be built.
# Setup:
#   - builds the sandbox under a SYMLINKED temporary directory, so
#     $TLH_SANDBOX is never its own physical path and an uncanonicalized path
#     compare fails (TLH_SYMLINKED_TMP=0 before sourcing opts out);
#   - installs `tmux` and `claude` shims in $TLH_BIN and puts $TLH_BIN first on
#     PATH, so no fixture can reach a real tmux server or a real worker CLI;
#   - unsets the worker identity and plugin data the suite may have inherited
#     from a dispatched session, and pins PLANWRIGHT_FLEET_STATE_DIR inside
#     the sandbox, so nothing a fixture starts can write a real fleet home;
#   - writes the stub server's environment (see tlh_server_env);
#   - installs the ONLY EXIT trap, tlh_teardown. A suite that needs its own
#     EXIT trap must capture `$?` first thing and end with
#     `tlh_teardown "$status"`, or it leaks the sandbox, skips the leak check,
#     or loses its own exit status.
#
# The stubs are tests/lib/tmux-launch-stub-tmux.sh and
# tests/lib/tmux-launch-stub-worker.sh, over tests/lib/tmux-launch-stub-common.sh;
# their headers own what each one does and which knobs it reads. The worker
# stub's confirmation hook resolves under TLH_PLUGIN_ROOT (default: this
# checkout), which a fixture may point at a recording stand-in before sourcing.
#
# Interface:
#   TLH_SANDBOX TLH_BIN TLH_STATE   sandbox root, shim dir, stub state dir
#   TLH_LAUNCH_BOUND_SECONDS        the default bound of tlh_run_bounded
#   TLH_CONFIRM_CAP_SECONDS         the shortened confirm cap a launch fixture
#                                   sets through the launch's test seam; the
#                                   harness only holds the bound above it
#   tlh_run_bounded [--bound <s>] <cmd> [args...]
#       run <cmd> with stdin from /dev/null, killing its whole process tree
#       once the bound (whole seconds) elapses. Sets TLH_RC (124 when the run
#       was still going at the bound, whatever status its kill left), TLH_OUT,
#       TLH_ERR, TLH_ELAPSED (whole seconds), and TLH_DIAG (empty unless it
#       was cut off). A malformed bound or a missing command fails, sets
#       TLH_RC 2, and runs nothing.
#   tlh_expect_returned <label>  fail with TLH_DIAG when the last run hung
#   tlh_server_env KEY=VALUE...   add to (or replace in) the server environment
#   tlh_knob <name> <value>       set a stub knob; a value the stub would not
#                                 recognize is refused
#   tlh_tmux_calls                every stub tmux invocation, oldest first, one
#                                 tab-separated argv per line
#   tlh_worker_records            every stub worker record path, oldest first
#   tlh_worker_count / tlh_last_worker_record
#   tlh_wait_workers <n> [<s>]    wait (bounded) until n worker records exist
#   tlh_record_field <record> <key>   the first <key> line's value
#   tlh_worker_env <record> <VAR>     the worker's value of VAR; status 1 when
#                                     VAR was not in its environment
#   tlh_session_pid <name>        the pid of a stub session's command
#   tlh_canon <path>              the physical (`pwd -P`) form of a path whose
#                                 parent directory exists; status 1 otherwise
#   tlh_assert_path_eq <label> <expected> <actual>   compare canonical forms,
#                                 falling back to the raw path for one that
#                                 cannot be canonicalized
#   tlh_stub_pids_alive           pids the stubs started that still run
#   tlh_reap                      kill every stub-started process tree; status
#                                 1 (naming them) when any survive
#   tlh_teardown [<status>]       reap, then fail the suite if a stub-started
#                                 process still runs, remove the sandbox, and
#                                 exit with <status> (default `$?`).
#                                 TLH_REAP=0 skips the reap, so the leak check
#                                 itself can be shown to fail.
unset CDPATH

if [ "$(type -t fail 2>/dev/null)" != function ]; then
  echo "FAIL: tmux-launch-harness: define a fail function before sourcing" >&2
  exit 1
fi

TLH_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
TLH_REPO_ROOT=$(cd "$TLH_LIB/../.." && pwd -P)
TLH_PLUGIN_ROOT=${TLH_PLUGIN_ROOT:-$TLH_REPO_ROOT}
TLH_CONFIRM_CAP_SECONDS=${TLH_CONFIRM_CAP_SECONDS:-2}
TLH_LAUNCH_BOUND_SECONDS=${TLH_LAUNCH_BOUND_SECONDS:-30}
case "$TLH_CONFIRM_CAP_SECONDS$TLH_LAUNCH_BOUND_SECONDS" in
  *[!0-9]*)
    echo "FAIL: tmux-launch-harness: the launch bound and the confirm cap must be whole seconds" >&2
    exit 1
    ;;
esac
if [ "$TLH_LAUNCH_BOUND_SECONDS" -le "$TLH_CONFIRM_CAP_SECONDS" ]; then
  echo "FAIL: tmux-launch-harness: the launch bound (${TLH_LAUNCH_BOUND_SECONDS}s) must exceed the confirm cap (${TLH_CONFIRM_CAP_SECONDS}s)" >&2
  exit 1
fi

# shellcheck source=tests/lib/tmux-launch-stub-common.sh
. "$TLH_LIB/tmux-launch-stub-common.sh"

_tlh_base=''
STUB_STATE=''

tlh_stub_pids_alive() {
  local f p
  [ -n "$STUB_STATE" ] || return 0
  for f in "$STUB_STATE"/pids/*; do
    [ -f "$f" ] || continue
    p=${f##*/}
    if stub_pid_ours "$p"; then printf '%s\n' "$p"; fi
  done
  return 0
}

tlh_reap() {
  local left members t=0
  left=$(tlh_stub_pids_alive)
  [ -z "$left" ] && return 0
  # shellcheck disable=SC2086 # one root per word
  stub_kill_tree TERM $left
  members=$STUB_TREE
  while [ -n "$left" ] && [ "$t" -lt 10 ]; do
    sleep 0.1
    t=$((t + 1))
    left=$(tlh_stub_pids_alive)
  done
  # Every member the TERM pass froze, recorded or not: a TERM-ignoring
  # descendant whose parent obeyed is no longer under any recorded pid.
  # shellcheck disable=SC2086
  stub_kill_tree KILL $left $members
  t=0
  left=$(tlh_stub_pids_alive)
  while [ -n "$left" ] && [ "$t" -lt 5 ]; do
    sleep 0.1
    t=$((t + 1))
    left=$(tlh_stub_pids_alive)
  done
  [ -z "$left" ] && return 0
  echo "tlh_reap: stub-started process(es) still running: $(printf '%s\n' "$left" | tr '\n' ' ')" >&2
  return 1
}

tlh_teardown() {
  local rc=${1:-$?} left
  set +e
  trap - EXIT
  # bash runs the EXIT trap in a background child signalled before it
  # reaches exec, which inherits it; only the suite's own process tears
  # down. `exec sh` makes the reported parent this process on bash 3.2,
  # which has no BASHPID.
  [ "$(exec sh -c 'echo "$PPID"')" = "$_tlh_owner" ] || exit "$rc"
  [ "${TLH_REAP:-1}" = 1 ] && tlh_reap
  left=$(tlh_stub_pids_alive)
  if [ -n "$left" ]; then
    echo "FAIL: leaked stub process(es) still running after the suite: $(printf '%s\n' "$left" | tr '\n' ' ')" >&2
    rc=1
  fi
  [ -n "$_tlh_base" ] && rm -rf "$_tlh_base"
  exit "$rc"
}

_tlh_setup_fail() {
  echo "FAIL: tmux-launch-harness: $1" >&2
  exit 1
}

_tlh_owner=$(exec sh -c 'echo "$PPID"')
trap tlh_teardown EXIT
_tlh_base=$(mktemp -d "${TMPDIR:-/tmp}/tlh.XXXXXX") || _tlh_setup_fail "cannot create the sandbox"
_tlh_base=$(cd "$_tlh_base" && pwd) || _tlh_setup_fail "cannot resolve the sandbox"
if [ "${TLH_SYMLINKED_TMP:-1}" = 1 ]; then
  { mkdir -p "$_tlh_base/real" && ln -s real "$_tlh_base/link" && mkdir -p "$_tlh_base/link/sb"; } \
    || _tlh_setup_fail "cannot build the symlinked sandbox under $_tlh_base"
  TLH_SANDBOX="$_tlh_base/link/sb"
else
  mkdir -p "$_tlh_base/sb" || _tlh_setup_fail "cannot build the sandbox under $_tlh_base"
  TLH_SANDBOX="$_tlh_base/sb"
fi
TLH_BIN="$TLH_SANDBOX/bin"
TLH_STATE="$TLH_SANDBOX/stub-state"
STUB_STATE=$TLH_STATE
mkdir -p "$TLH_BIN" "$TLH_SANDBOX/server-home" "$TLH_SANDBOX/runs" "$TLH_SANDBOX/fleet" \
  "$TLH_STATE/calls" "$TLH_STATE/seq" "$TLH_STATE/sessions" "$TLH_STATE/sdata" \
  "$TLH_STATE/pids" "$TLH_STATE/workers" "$TLH_STATE/knobs" \
  || _tlh_setup_fail "cannot build the sandbox under $_tlh_base"

# The shims bake their paths in single quotes; the server environment is
# one variable per line.
case "$TLH_STATE$TLH_LIB$TLH_PLUGIN_ROOT" in
  *"'"* | *$'\n'*) _tlh_setup_fail "a sandbox, checkout, or plugin-root path holds a single quote or a newline" ;;
esac
case $PATH in
  *$'\n'*) _tlh_setup_fail "PATH holds a newline" ;;
esac
{
  printf '#!/bin/sh\nexec /bin/sh '\''%s'\'' '\''%s'\'' "$@"\n' \
    "$TLH_LIB/tmux-launch-stub-tmux.sh" "$TLH_STATE" >"$TLH_BIN/tmux" \
    && printf '#!/bin/sh\nexec /bin/sh '\''%s'\'' '\''%s'\'' '\''%s'\'' "$@"\n' \
      "$TLH_LIB/tmux-launch-stub-worker.sh" "$TLH_STATE" "$TLH_PLUGIN_ROOT" >"$TLH_BIN/claude" \
    && chmod +x "$TLH_BIN/tmux" "$TLH_BIN/claude"
} || _tlh_setup_fail "cannot write the stub shims"

# The server's environment is fixed here, at setup, the way a real server
# keeps the environment of the client that started it. Nothing the suite
# exports later reaches a session.
printf '%s\n' "PATH=$TLH_BIN:$PATH" "HOME=$TLH_SANDBOX/server-home" "LC_ALL=C" "SHELL=/bin/sh" \
  "PLANWRIGHT_FLEET_STATE_DIR=$TLH_SANDBOX/fleet" >"$TLH_STATE/server.env" \
  || _tlh_setup_fail "cannot write the server environment"
PATH="$TLH_BIN:$PATH"
export PATH
unset PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_LAUNCH_TOKEN CLAUDE_PLUGIN_DATA
PLANWRIGHT_FLEET_STATE_DIR="$TLH_SANDBOX/fleet"
export PLANWRIGHT_FLEET_STATE_DIR

TLH_RC=0
TLH_OUT=''
TLH_ERR=''
TLH_DIAG=''
TLH_ELAPSED=0
_tlh_runs=0

_tlh_whole_seconds() {
  case $1 in '' | *[!0-9]*) return 1 ;; esac
  [ "$1" -gt 0 ]
}

tlh_server_env() {
  local kv key
  for kv in "$@"; do
    key=${kv%%=*}
    case $kv in
      *=*) ;;
      *)
        fail "tlh_server_env: '$kv' is not KEY=VALUE"
        return 1
        ;;
    esac
    case $key in
      '' | [0-9]* | *[!A-Za-z0-9_]*)
        fail "tlh_server_env: '$key' is not a variable name"
        return 1
        ;;
    esac
    case $kv in
      *$'\n'*)
        fail "tlh_server_env: the value of $key holds a newline"
        return 1
        ;;
    esac
    if ! {
      { grep -v "^$key=" "$TLH_STATE/server.env" || [ $? -eq 1 ]; } >"$TLH_STATE/server.env.new" \
        && printf '%s\n' "$kv" >>"$TLH_STATE/server.env.new" \
        && mv -f "$TLH_STATE/server.env.new" "$TLH_STATE/server.env"
    }; then
      fail "tlh_server_env: cannot rewrite the server environment"
      return 1
    fi
  done
  return 0
}

tlh_knob() {
  local ok ok_hit
  case $1 in
    new-session) ok='ok fail duplicate block' ;;
    server) ok='up none unreachable' ;;
    remain-on-exit | worker-confirm) ok='on off' ;;
    worker-exit) ok='run' ;;
    *)
      fail "tlh_knob: unknown knob '$1'"
      return 1
      ;;
  esac
  case " $ok " in
    *" ${2:-} "*) case ${2:-} in '' | *' '*) ok_hit=0 ;; *) ok_hit=1 ;; esac ;;
    *) ok_hit=0 ;;
  esac
  if [ "$ok_hit" = 0 ]; then
    case $1/${2:-} in
      worker-exit/[0-9] | worker-exit/[1-9][0-9] | worker-exit/1[0-9][0-9] | worker-exit/2[0-4][0-9] | worker-exit/25[0-5]) ;;
      *)
        fail "tlh_knob: '${2:-}' is not a value of knob '$1' (one of: $ok$([ "$1" = worker-exit ] && printf ' 0-255'))"
        return 1
        ;;
    esac
  fi
  stub_write_file "$TLH_STATE/knobs/$1" "$2"$'\n' || {
    fail "tlh_knob: cannot write knob '$1'"
    return 1
  }
}

# The watchdog kills the run's tree within a tenth of a second of the bound;
# a run that ends first is reaped by `wait` and its watchdog killed, so a
# short run pays no polling floor. The watchdog's marker alone decides the
# verdict: a launch that traps TERM and exits 0 when cut off still hung.
tlh_run_bounded() {
  local bound=$TLH_LAUNCH_BOUND_SECONDS pid dog timer dir start
  if [ "${1:-}" = --bound ]; then
    bound=${2:-}
    shift
    [ $# -gt 0 ] && shift
  fi
  TLH_DIAG=''
  TLH_OUT=''
  TLH_ERR=''
  TLH_ELAPSED=0
  if ! _tlh_whole_seconds "$bound"; then
    TLH_RC=2
    fail "tlh_run_bounded: the bound must be a positive whole number of seconds, got '$bound'"
    return 0
  fi
  if [ $# -eq 0 ]; then
    TLH_RC=2
    fail "tlh_run_bounded: no command to run"
    return 0
  fi
  _tlh_runs=$((_tlh_runs + 1))
  dir="$TLH_SANDBOX/runs/$_tlh_runs"
  mkdir -p "$dir"
  start=$SECONDS
  "$@" </dev/null >"$dir/out" 2>"$dir/err" &
  pid=$!
  # The timer is this shell's own child, so it is always reapable here; the
  # watchdog only watches it.
  sleep "$bound" &
  timer=$!
  (
    while kill -0 "$timer" 2>/dev/null; do sleep 0.1; done
    kill -0 "$pid" 2>/dev/null || exit 0
    : >"$dir/hung"
    stub_kill_tree TERM "$pid"
    sleep 0.2
    # shellcheck disable=SC2086 # one root per word
    stub_kill_tree KILL $STUB_TREE
  ) </dev/null >/dev/null 2>&1 &
  dog=$!
  TLH_RC=0
  { wait "$pid"; } 2>/dev/null || TLH_RC=$?
  if [ -e "$dir/hung" ]; then
    { wait "$dog"; } 2>/dev/null || true
    TLH_RC=124
    TLH_DIAG="blocking launch: '${1##*/}' did not return within ${bound}s and was killed with its process tree; a launch that waits on its worker blocks the dispatch"
  else
    # The watchdog first, so it cannot see the timer end and signal a pid
    # `wait` has already released; then the timer.
    kill -KILL "$dog" 2>/dev/null || true
    { wait "$dog"; } 2>/dev/null || true
    # KILL, not TERM: a timer not yet at exec would run the EXIT trap.
    kill -KILL "$timer" 2>/dev/null || true
  fi
  { wait "$timer"; } 2>/dev/null || true
  TLH_ELAPSED=$((SECONDS - start))
  TLH_OUT=$(cat "$dir/out")
  TLH_ERR=$(cat "$dir/err")
  return 0
}

tlh_expect_returned() {
  [ -z "$TLH_DIAG" ] && return 0
  fail "$1: $TLH_DIAG"
  return 1
}

tlh_tmux_calls() {
  local f
  for f in "$TLH_STATE"/calls/[0-9]*; do
    [ -f "$f" ] && cat "$f"
  done
  return 0
}

tlh_worker_records() {
  local f
  for f in "$TLH_STATE"/workers/[0-9]*; do
    case $f in *.confirm.err) continue ;; esac
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

tlh_worker_count() {
  tlh_worker_records | wc -l | tr -d ' '
}

tlh_last_worker_record() {
  tlh_worker_records | tail -n 1
}

tlh_wait_workers() {
  local want=$1 bound=${2:-$TLH_LAUNCH_BOUND_SECONDS} start=$SECONDS
  case $want in '' | *[!0-9]*)
    fail "tlh_wait_workers: '$want' is not a record count"
    return 1
    ;;
  esac
  _tlh_whole_seconds "$bound" || {
    fail "tlh_wait_workers: the bound must be a positive whole number of seconds, got '$bound'"
    return 1
  }
  while [ "$(tlh_worker_count)" -lt "$want" ]; do
    if [ $((SECONDS - start)) -ge "$bound" ]; then
      fail "tlh_wait_workers: $want worker record(s) did not appear within ${bound}s"
      return 1
    fi
    sleep 0.1
  done
  return 0
}

tlh_record_field() {
  awk -F'\t' -v k="$2" '$1 == k {
      i = index($0, "\t")
      print (i ? substr($0, i + 1) : "")
      exit
    }' "$1"
}

tlh_worker_env() {
  local key
  key=$(printf 'env\t%s=' "$2")
  awk -v k="$key" 'index($0, k) == 1 { print substr($0, length(k) + 1); found = 1; exit }
    END { exit !found }' "$1"
}

tlh_session_pid() {
  local p=''
  if [ -r "$TLH_STATE/sessions/$1/pid" ]; then
    IFS= read -r p <"$TLH_STATE/sessions/$1/pid" || true
  fi
  printf '%s\n' "$p"
}

tlh_canon() {
  local parent base dir
  if [ -d "$1" ]; then
    (cd "$1" && pwd -P)
    return
  fi
  case $1 in
    */*)
      parent=${1%/*}
      base=${1##*/}
      ;;
    *)
      parent=.
      base=$1
      ;;
  esac
  [ -n "$base" ] || return 1
  [ -n "$parent" ] || parent=/
  dir=$(cd "$parent" 2>/dev/null && pwd -P) || return 1
  [ "$dir" = / ] && dir=''
  printf '%s/%s\n' "$dir" "$base"
}

tlh_assert_path_eq() {
  local want got
  want=$(tlh_canon "$2") || want=$2
  got=$(tlh_canon "$3") || got=$3
  [ -n "$want" ] && [ "$want" = "$got" ] && return 0
  fail "$1: expected path $want, got $got"
  return 1
}
