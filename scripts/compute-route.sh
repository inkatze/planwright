#!/bin/sh
# compute-route.sh — run a test or lint command on the configured compute host
# (fleet_compute_host) when one is set, else here. The gate runners
# (full-suite-run.sh, step-run.sh command steps) put it in front of their
# command, so one knob moves test and lint runs off a crowded machine.
#
# Usage:
#   compute-route.sh [--check | --task <name> | --test <tests/test-x.sh>] -- <command> [<arg>...]
#
# Without a kind flag the command is mapped by shape: `mise run check` is
# --check, `mise run <task>` is --task, `bash tests/test-<name>.sh` is --test,
# and `bash <file>` on a file holding one such `mise run` line (the saved gate
# command) maps like that line. Anything else runs here.
#
# The host runs the kind through `fleet-remote.sh compute` in the caller's
# worktree. The command runs here instead, with one `compute-route: warning:`
# line, when the host cannot be reached, is over fleet_compute_load_cap (load
# per core), or the run fails before its command starts (a refused target, no
# clone, SSH down); and silently when the knob is `local`. A worktree with
# uncommitted changes also runs here, since the host tests only the committed
# HEAD. A run whose command started is never repeated: its result stands.
#
# Knobs (config-get.sh): fleet_compute_host, fleet_compute_load_cap,
# fleet_compute_timeout (whole seconds; empty takes the channel's default).
# Exit: the command's own status; 2 usage error.
set -u
# The command runs in the caller's locale; only this script's own parsing is
# pinned to C.
caller_lc_all=${LC_ALL-}
caller_lc_all_set=${LC_ALL+1}
LC_ALL=C
export LC_ALL
unset CDPATH

# run_here <command> [<arg>...]: the local form, in the caller's locale.
run_here() {
  if [ -n "$caller_lc_all_set" ]; then
    LC_ALL=$caller_lc_all
    export LC_ALL
  else
    unset LC_ALL
  fi
  exec "$@"
}

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
prog=compute-route
# PLANWRIGHT_FLEET_REMOTE is the tests' seam for a fake channel.
channel=${PLANWRIGHT_FLEET_REMOTE:-$script_dir/fleet-remote.sh}

usage() {
  printf 'usage: compute-route.sh [--check | --task <name> | --test <tests/test-x.sh>] -- <command> [<arg>...]\n' >&2
  exit 2
}
warn() { printf '%s: warning: %s\n' "$prog" "$1" >&2; }

kind=''
value=''
while [ $# -gt 0 ]; do
  case $1 in
    --check)
      kind=check
      shift
      ;;
    --task | --test)
      [ $# -ge 3 ] || usage
      kind=${1#--}
      value=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *) usage ;;
  esac
done
[ $# -ge 1 ] || usage

# gate_file <file>: a small file holding one `mise run <check|task>` line, as
# /execute-task saves its derived gate command, maps like that command.
gate_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  [ "$(wc -c <"$1" | tr -d ' ')" -le 200 ] || return 0
  [ "$(grep -c '' "$1" | tr -d ' ')" -le 1 ] || return 0
  _gf=$(sed -n '1p' "$1")
  case $_gf in
    'mise run check') kind=check ;;
    'mise run '[a-z]*)
      _gf=${_gf#mise run }
      case $_gf in *[!a-z0-9:_-]*) ;; *) kind=task value=$_gf ;; esac
      ;;
  esac
}

conf() {
  # shell-config-pin: runs in the worktree whose gate it routes
  "$script_dir/config-get.sh" "$1" 2>/dev/null
}

# The shipped posture is local: decide that before any mapping work.
host=$(conf fleet_compute_host) || host=''
case $host in
  '' | local) run_here "$@" ;;
  -* | *[!A-Za-z0-9._-]*)
    warn "fleet_compute_host '$host' is not a host alias; running locally"
    run_here "$@"
    ;;
esac

if [ -z "$kind" ]; then
  case $1 in
    mise)
      if [ $# -eq 3 ] && [ "$2" = run ]; then
        case $3 in
          check) kind=check ;;
          [a-z]*) kind=task value=$3 ;;
        esac
      fi
      ;;
    bash | /bin/bash)
      if [ $# -eq 2 ]; then
        case $2 in
          tests/test-*.sh) kind=test value=$2 ;;
          *) gate_file "$2" ;;
        esac
      fi
      ;;
  esac
fi
# The channel refuses a target outside its grammar; a command it would refuse
# runs here instead.
case $kind:$value in
  check:) ;;
  task:[a-z]*) case $value in *[!a-z0-9:_-]*) kind='' ;; esac ;;
  test:tests/test-*.sh) case ${value#tests/} in *[!A-Za-z0-9._-]*) kind='' ;; esac ;;
  *) kind='' ;;
esac
[ -n "$kind" ] || run_here "$@"

cap=$(conf fleet_compute_load_cap) || cap=0.4
timeout_secs=$(conf fleet_compute_timeout) || timeout_secs=''
case $cap in *[0-9]*) ;; *) cap=0.4 ;; esac
case $cap in *[!0-9.]* | *.*.*) cap=0.4 ;; esac
case $timeout_secs in '' | *[!0-9]* | 0* | ??????*) timeout_secs='' ;; esac
[ -z "$timeout_secs" ] || [ "$timeout_secs" -le 86400 ] || timeout_secs=''

# The remote runs the committed HEAD only; a dirty tree would be tested as
# something it is not, so it runs here.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  warn "the worktree has uncommitted changes, which a compute run would not test; running locally"
  run_here "$@"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/compute-route.XXXXXX") || {
  warn "cannot create a temporary directory; running locally"
  run_here "$@"
}
child=''
# shellcheck disable=SC2329 # invoked by the traps below
stop() {
  [ -z "$child" ] || kill "$child" 2>/dev/null
  [ -z "${watchdog:-}" ] || kill "$watchdog" 2>/dev/null
  rm -rf "$work"
  exit "$1"
}
trap 'stop 129' HUP
trap 'stop 130' INT
trap 'stop 143' TERM

# The load probe, bounded by a watchdog: ConnectTimeout covers only the connect
# phase, and a host that accepts the connection and then stalls would hang the
# gate here instead of passing the host over.
/bin/sh "$channel" --host "$host" load >"$work/probe" 2>/dev/null </dev/null &
child=$!
(
  sleep 30
  kill "$child" 2>/dev/null
) >/dev/null 2>&1 </dev/null &
watchdog=$!
wait "$child"
prc=$?
child=''
pkill -P "$watchdog" 2>/dev/null
kill "$watchdog" 2>/dev/null
{ wait "$watchdog"; } 2>/dev/null
probe=''
[ "$prc" -ne 0 ] || probe=$(sed -n '1p' "$work/probe")
load=${probe%% *}
cores=${probe#* }
case $load in '' | *[!0-9.]* | *.*.* | .) probe='' ;; esac
case $cores in '' | *[!0-9]*) probe='' ;; esac
if [ -z "$probe" ]; then
  rm -rf "$work"
  warn "compute host unreachable; running locally"
  run_here "$@"
fi
if awk -v l="$load" -v c="$cores" -v cap="$cap" 'BEGIN { exit !(c > 0 && l / c > cap) }'; then
  rm -rf "$work"
  warn "compute host is busy (load $load on $cores cores, cap $cap per core); running locally"
  run_here "$@"
fi

# remote_run: the channel call, in a function so the caller's own command
# stays in the positional parameters for the fallback.
remote_run() {
  set -- /bin/sh "$channel" --host "$host" compute --worktree "$(pwd -P)"
  case $kind in
    check) set -- "$@" --check ;;
    *) set -- "$@" "--$kind" "$value" ;;
  esac
  [ -z "$timeout_secs" ] || set -- "$@" --timeout "$timeout_secs"
  exec "$@" 2>"$work/err"
}
# The channel's diagnostics are held until the run ends, because the lines that
# say whether the command started decide whether a fallback is allowed; the
# command's own output streams.
remote_run &
child=$!
wait "$child"
rc=$?
child=''
started=0
grep -q '^fleet-remote: running ' "$work/err" && started=1
cat "$work/err" >&2
rm -rf "$work"
if [ "$started" -eq 0 ]; then
  # The channel's own pre-start codes: a refused argument, a host not set up,
  # a failed ship, SSH down.
  case $rc in
    2 | 3 | 4 | 255)
      warn "the run on the compute host failed before its command started (exit $rc); running locally"
      run_here "$@"
      ;;
  esac
fi
exit "$rc"
