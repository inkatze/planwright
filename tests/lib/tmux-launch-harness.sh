# shellcheck shell=bash
# shellcheck disable=SC2034 # the TLH_* results are read by the sourcing suite
# tmux-launch-harness.sh — the shared fixture harness for the tmux rung's
# launch tests (sourced, never executed). It exists so a launch fixture can
# fail but never hang, cannot pass because the test's own environment leaked
# into the worker, compares paths the way the filesystem resolves them, and
# leaves no process behind. tests/test-tmux-launch-harness.sh is its
# self-test.
#
# Sourcing runs setup. It exits the sourcing suite (status 1) when the suite
# has not defined a `fail` function (every assertion here reports through it),
# when the default bound does not exceed the confirm cap, or when the sandbox
# cannot be built. Setup:
#   - builds the sandbox under a SYMLINKED temporary directory, so
#     $TLH_SANDBOX is never its own physical path and an uncanonicalized path
#     compare fails (TLH_SYMLINKED_TMP=0 before sourcing opts out);
#   - installs `tmux` and `claude` shims in $TLH_BIN and puts $TLH_BIN first on
#     PATH, so no fixture can reach a real tmux server or a real worker CLI;
#   - writes the stub server's environment (see tlh_server_env);
#   - installs the ONLY EXIT trap, tlh_teardown. A suite that needs its own
#     EXIT trap must call tlh_teardown from it, or it leaks the sandbox and
#     skips the leak check.
#
# The stubs are tests/lib/tmux-launch-stub-tmux.sh and
# tests/lib/tmux-launch-stub-worker.sh; their headers own what each one does.
#
# Interface:
#   TLH_SANDBOX TLH_BIN TLH_STATE   sandbox root, shim dir, stub state dir
#   TLH_LAUNCH_BOUND_SECONDS        the default bound of tlh_run_bounded
#   TLH_CONFIRM_CAP_SECONDS         the shortened confirm cap launch fixtures
#                                   run under; the bound must exceed it
#   tlh_run_bounded [--bound <s>] <cmd> [args...]
#       run <cmd> with stdin from /dev/null, killing its whole process tree
#       past the bound. Sets TLH_RC (124 on a hang), TLH_OUT, TLH_ERR,
#       TLH_ELAPSED (whole seconds), and TLH_DIAG (empty unless it hung).
#   tlh_expect_returned <label>  fail with TLH_DIAG when the last run hung
#   tlh_server_env KEY=VALUE...   add to (or replace in) the server environment
#   tlh_knob <name> <value>       set a stub knob (names in the stub headers)
#   tlh_tmux_calls                every stub tmux invocation, oldest first, one
#                                 tab-separated argv per line
#   tlh_worker_records            every stub worker record path, oldest first
#   tlh_wait_workers <n> [<s>]    wait (bounded) until n worker records exist
#   tlh_record_field <record> <key>   the first <key> line's value
#   tlh_worker_env <record> <VAR>     the worker's value of VAR; status 1 when
#                                     VAR was not in its environment
#   tlh_canon <path>              the physical (`pwd -P`) form of a path whose
#                                 directory exists
#   tlh_assert_path_eq <label> <expected> <actual>   compare canonical forms
#   tlh_stub_pids_alive           pids the stubs started that still run
#   tlh_reap                      kill every stub-started process tree; status
#                                 1 (naming them) when any survive
#   tlh_teardown                  reap, then fail the suite if a stub-started
#                                 process still runs, and remove the sandbox.
#                                 TLH_REAP=0 skips the reap, so the leak check
#                                 itself can be shown to fail.
unset CDPATH

if [ "$(type -t fail 2>/dev/null)" != function ]; then
  echo "FAIL: tmux-launch-harness: define a fail function before sourcing" >&2
  exit 1
fi

TLH_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
TLH_REPO_ROOT=$(cd "$TLH_LIB/../.." && pwd -P)
TLH_CONFIRM_CAP_SECONDS=${TLH_CONFIRM_CAP_SECONDS:-2}
TLH_LAUNCH_BOUND_SECONDS=${TLH_LAUNCH_BOUND_SECONDS:-30}
if [ "$TLH_LAUNCH_BOUND_SECONDS" -le "$TLH_CONFIRM_CAP_SECONDS" ]; then
  echo "FAIL: tmux-launch-harness: the launch bound (${TLH_LAUNCH_BOUND_SECONDS}s) must exceed the confirm cap (${TLH_CONFIRM_CAP_SECONDS}s)" >&2
  exit 1
fi

_tlh_base=$(mktemp -d "${TMPDIR:-/tmp}/tlh.XXXXXX") || {
  echo "FAIL: tmux-launch-harness: cannot create the sandbox" >&2
  exit 1
}
if [ "${TLH_SYMLINKED_TMP:-1}" = 1 ]; then
  mkdir "$_tlh_base/real" && ln -s real "$_tlh_base/link" && mkdir "$_tlh_base/link/sb"
  TLH_SANDBOX="$_tlh_base/link/sb"
else
  mkdir "$_tlh_base/sb"
  TLH_SANDBOX="$_tlh_base/sb"
fi
TLH_BIN="$TLH_SANDBOX/bin"
TLH_STATE="$TLH_SANDBOX/tmux-state"
mkdir -p "$TLH_BIN" "$TLH_SANDBOX/server-home" "$TLH_SANDBOX/runs" \
  "$TLH_STATE/calls" "$TLH_STATE/seq" "$TLH_STATE/sessions" "$TLH_STATE/pids" \
  "$TLH_STATE/workers" "$TLH_STATE/knobs" || {
  echo "FAIL: tmux-launch-harness: cannot build the sandbox under $_tlh_base" >&2
  exit 1
}

# The shims bake their paths in single quotes, so a quote in one would break
# them; mktemp and a checkout path never carry one in practice.
case "$TLH_STATE$TLH_LIB$TLH_REPO_ROOT" in
  *"'"*)
    echo "FAIL: tmux-launch-harness: a sandbox or checkout path holds a single quote" >&2
    exit 1
    ;;
esac
printf '#!/bin/sh\nexec /bin/sh '\''%s'\'' '\''%s'\'' "$@"\n' \
  "$TLH_LIB/tmux-launch-stub-tmux.sh" "$TLH_STATE" >"$TLH_BIN/tmux"
printf '#!/bin/sh\nexec /bin/sh '\''%s'\'' '\''%s'\'' '\''%s'\'' "$@"\n' \
  "$TLH_LIB/tmux-launch-stub-worker.sh" "$TLH_STATE" "$TLH_REPO_ROOT" >"$TLH_BIN/claude"
chmod +x "$TLH_BIN/tmux" "$TLH_BIN/claude"

# The server's environment is fixed here, at setup, the way a real server
# keeps the environment of the client that started it. Nothing the suite
# exports later reaches a session.
printf '%s\n' "PATH=$TLH_BIN:$PATH" "HOME=$TLH_SANDBOX/server-home" "LC_ALL=C" "SHELL=/bin/sh" \
  >"$TLH_STATE/server.env"
PATH="$TLH_BIN:$PATH"
export PATH

TLH_RC=0
TLH_OUT=''
TLH_ERR=''
TLH_DIAG=''
TLH_ELAPSED=0
_tlh_runs=0

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
    grep -v "^$key=" "$TLH_STATE/server.env" >"$TLH_STATE/server.env.new"
    printf '%s\n' "$kv" >>"$TLH_STATE/server.env.new"
    mv "$TLH_STATE/server.env.new" "$TLH_STATE/server.env"
  done
}

tlh_knob() {
  case $1 in
    new-session | server | worker-confirm | worker-exit) ;;
    *)
      fail "tlh_knob: unknown knob '$1'"
      return 1
      ;;
  esac
  printf '%s\n' "$2" >"$TLH_STATE/knobs/$1"
}

# _tlh_kill_tree <signal> <pid> — the pid and every descendant, children first.
_tlh_kill_tree() {
  local c
  for c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$2" '$2 == p { print $1 }'); do
    _tlh_kill_tree "$1" "$c"
  done
  kill "-$1" "$2" 2>/dev/null
}

tlh_run_bounded() {
  local bound=$TLH_LAUNCH_BOUND_SECONDS pid start dir
  if [ "${1:-}" = --bound ]; then
    bound=$2
    shift 2
  fi
  _tlh_runs=$((_tlh_runs + 1))
  dir="$TLH_SANDBOX/runs/$_tlh_runs"
  mkdir -p "$dir"
  start=$SECONDS
  "$@" </dev/null >"$dir/out" 2>"$dir/err" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ $((SECONDS - start)) -lt "$bound" ]; do
    sleep 0.1
  done
  TLH_DIAG=''
  if kill -0 "$pid" 2>/dev/null; then
    _tlh_kill_tree TERM "$pid"
    sleep 0.2
    _tlh_kill_tree KILL "$pid"
    wait "$pid" 2>/dev/null
    TLH_RC=124
    TLH_DIAG="hang: '${1##*/}' did not return within ${bound}s and was killed with its process tree; a launch that waits on its worker blocks the dispatch"
  else
    wait "$pid"
    TLH_RC=$?
  fi
  TLH_ELAPSED=$((SECONDS - start))
  TLH_OUT=$(cat "$dir/out")
  TLH_ERR=$(cat "$dir/err")
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
}

tlh_worker_records() {
  local f
  for f in "$TLH_STATE"/workers/[0-9]*; do
    case $f in *.confirm.err) continue ;; esac
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

tlh_wait_workers() {
  local want=$1 bound=${2:-$TLH_LAUNCH_BOUND_SECONDS} start=$SECONDS
  while [ "$(tlh_worker_records | wc -l | tr -d ' ')" -lt "$want" ]; do
    if [ $((SECONDS - start)) -ge "$bound" ]; then
      fail "tlh_wait_workers: $want worker record(s) did not appear within ${bound}s"
      return 1
    fi
    sleep 0.1
  done
}

tlh_record_field() {
  awk -F'\t' -v k="$2" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }' "$1"
}

tlh_worker_env() {
  awk -v k="env	$2=" 'index($0, k) == 1 { print substr($0, length(k) + 1); found = 1; exit }
    END { exit !found }' "$1"
}

tlh_canon() {
  if [ -d "$1" ]; then
    (cd "$1" && pwd -P)
  else
    printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "${1##*/}"
  fi
}

tlh_assert_path_eq() {
  local want got
  want=$(tlh_canon "$2" 2>/dev/null) || want=$2
  got=$(tlh_canon "$3" 2>/dev/null) || got=$3
  [ -n "$want" ] && [ "$want" = "$got" ] && return 0
  fail "$1: expected path $want, got $got"
  return 1
}

tlh_stub_pids_alive() {
  local f p
  for f in "$TLH_STATE"/pids/*; do
    [ -f "$f" ] || continue
    p=${f##*/}
    kill -0 "$p" 2>/dev/null && printf '%s\n' "$p"
  done
}

tlh_reap() {
  local p left
  for p in $(tlh_stub_pids_alive); do _tlh_kill_tree TERM "$p"; done
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -z "$(tlh_stub_pids_alive)" ] && return 0
    sleep 0.1
  done
  for p in $(tlh_stub_pids_alive); do _tlh_kill_tree KILL "$p"; done
  sleep 0.1
  left=$(tlh_stub_pids_alive)
  [ -z "$left" ] && return 0
  echo "tlh_reap: stub-started process(es) still running: $(printf '%s\n' "$left" | tr '\n' ' ')" >&2
  return 1
}

tlh_teardown() {
  local rc=$? left
  trap - EXIT
  [ "${TLH_REAP:-1}" = 1 ] && tlh_reap
  left=$(tlh_stub_pids_alive)
  if [ -n "$left" ]; then
    echo "FAIL: leaked stub process(es) still running after the suite: $(printf '%s\n' "$left" | tr '\n' ' ')" >&2
    rc=1
  fi
  rm -rf "$_tlh_base"
  exit "$rc"
}
trap tlh_teardown EXIT
