#!/bin/sh
# fleet-tower-launch.sh — start a fleet tower as a detached headless session:
# the launch the continue-as-new handover runs
# (doctrine/context-budget-autoheal.md) to start its replacement
# (fleet-messaging D-8, D-17, D-19).
#
# The launch is `claude -p --name <name> --settings <tower profile>
# --output-format json "<wake prompt>"`, run through fleet-dispatch-env.sh
# with `--inbound accept` (the layer the messaging probe reads beside the
# profile), detached in its own session (setsid, else nohup) in the tower's
# checkout, under the caller's umask, with the retiring tower's identity and
# any worker identity dropped from its environment. A tower's own Bash
# string carrying that --settings flag would be deferred by the tower command
# guard; this script is approved wholesale like every planwright script, and
# it builds the launch itself from validated parts, so no caller-supplied flag
# reaches the CLI.
#
# The name is `planwright-tower-<spec>-<epoch>-<pid>` (`meta` for a
# meta-tower), held to the relay's headless-oneshot grammar. The epoch and
# this launcher's pid keep it apart from the retiring tower's, which is still
# running while its replacement starts, and from a second launch in the same
# second.
# The tower records the name it actually got in its marker at watch-loop start
# (`fleet-messaging.sh self-name`); nothing here reads a name back.
#
# The wake prompt is fixed: `/orchestrate --watch [--unattended] <spec>`, or
# `/orchestrate --meta --watch [--unattended]`. It is the handover document
# (context-budget-autoheal); the fresh tower rebuilds everything else from
# durable state.
#
# Usage: fleet-tower-launch.sh (<spec> | --meta) [--unattended]
#            [--checkout <abs-dir>] [--dry-run]
#   --checkout   the tower's checkout (default: the git top level of the
#                working directory)
#   --dry-run    print the launch as `tower-launch<TAB>argv<TAB><word>...`
#                and start nothing
# Report: `tower-launch<TAB>name|pid|log<TAB><value>` lines. The pid is the
# fresh tower's process, still alive about a second after the launch: the
# liveness evidence a retiring tower confirms before it stops. A tower that
# dies later than that (a refused login, a rate limit) is not caught here;
# the watchdog's next tick, or the next operator, is what notices it. The log
# is `<fleet-home>/tower-launch/<name>.log`, owner-only, never overwritten.
# Exit: 0 started (or planned); 2 usage, a refused input, the tower profile
#   unreadable (named on stderr), no usable CLI, or a log already at the
#   name; 4 the tower exited at once (its log named on stderr).
#
# Test seam, refused unless PLANWRIGHT_TEST_SEAM=1: PLANWRIGHT_TOWER_LAUNCH_CLAUDE
# names the CLI (default `claude` on PATH), an absolute path to an executable
# file.
#
# POSIX sh; no eval; every input is data. Pathname expansion is disabled.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-tower-launch

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$me: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/spec-id-lib.sh
. "$script_dir/spec-id-lib.sh"

TAB=$(printf '\t')

die() {
  printf '%s\n' "$me: $1" >&2
  exit 2
}

usage() {
  die "usage: fleet-tower-launch.sh (<spec> | --meta) [--unattended] [--checkout <abs-dir>] [--dry-run]"
}

spec=''
meta=0
unattended=0
checkout=''
dry=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --meta) meta=1 ;;
    --unattended) unattended=1 ;;
    --dry-run) dry=1 ;;
    --checkout)
      [ "$#" -ge 2 ] || usage
      checkout=$2
      shift
      ;;
    -*) usage ;;
    *)
      [ -z "$spec" ] || usage
      spec=$1
      ;;
  esac
  shift
done

if [ "$meta" = 1 ]; then
  [ -z "$spec" ] || usage
  scope=meta
else
  [ -n "$spec" ] || usage
  spec_id_canon "$spec"
  spec=$SPEC_ID
  case $spec in
    "" | -* | *[!a-z0-9-]* | flight) die "refusing the spec id '$(sanitize_printable "$spec" "(unprintable)")'" ;;
  esac
  [ "${#spec}" -le 64 ] || die "refusing an over-length spec id"
  scope=$spec
fi

if [ -z "$checkout" ]; then
  checkout=$(git rev-parse --show-toplevel 2>/dev/null) || checkout=$(pwd)
fi
case $checkout in
  /*) ;;
  *) die "--checkout must be an absolute path" ;;
esac
checkout=$(cd "$checkout" 2>/dev/null && pwd -P) || die "--checkout is not an existing directory"

profile=$(/bin/sh "$script_dir/fleet-launch-profile.sh" tower </dev/null) || exit 2

cli=${PLANWRIGHT_TOWER_LAUNCH_CLAUDE:-}
if [ -n "$cli" ] && [ "${PLANWRIGHT_TEST_SEAM:-}" != 1 ]; then
  die "PLANWRIGHT_TOWER_LAUNCH_CLAUDE is a test-only seam (needs PLANWRIGHT_TEST_SEAM=1)"
fi
[ -n "$cli" ] || cli=$(command -v claude 2>/dev/null) || cli=''
case $cli in
  /*) [ -f "$cli" ] && [ -x "$cli" ] || die "the claude CLI is not an executable file: $(sanitize_printable "$cli")" ;;
  *) die "claude does not resolve to an absolute path of an executable file" ;;
esac

epoch=$(date +%s)
case $epoch in
  "" | *[!0-9]*) die "cannot read the clock" ;;
esac
name="planwright-tower-$scope-$epoch-$$"
/bin/sh "$script_dir/orchestrate-relay.sh" validate-handle headless-oneshot "$name" 2>/dev/null \
  || die "the derived session name is outside the headless-oneshot grammar"

if [ "$meta" = 1 ]; then
  prompt="/orchestrate --meta --watch"
else
  prompt="/orchestrate --watch"
fi
[ "$unattended" = 0 ] || prompt="$prompt --unattended"
[ "$meta" = 1 ] || prompt="$prompt $spec"

set -- "$script_dir/fleet-dispatch-env.sh" --inbound accept "$cli" -p --name "$name" \
  --settings "$profile" --output-format json "$prompt"

if [ "$dry" = 1 ]; then
  printf 'tower-launch%sargv' "$TAB"
  for w in "$@"; do printf '\t%s' "$(sanitize_printable "$w")"; done
  printf '\n'
  printf 'tower-launch\tname\t%s\n' "$name"
  exit 0
fi

home=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null) || die "cannot resolve the fleet home for the tower's log"
# Outside towers/: every name there is a spec's marker, and `tower-launch` is
# not a spec id the marker grammar could produce on its own.
logdir="$home/tower-launch"
log="$logdir/$name.log"
old_umask=$(umask)
umask 0077
if ! mkdir -p "$logdir" 2>/dev/null || [ -L "$logdir" ] || [ -e "$log" ] || [ -L "$log" ] \
  || ! (set -C && : >"$log") 2>/dev/null; then
  umask "$old_umask"
  die "cannot create a fresh tower log at $(sanitize_printable "$log") (a symlinked directory, or a log already at that name)"
fi
umask "$old_umask"
if command -v setsid >/dev/null 2>&1; then
  detach="setsid"
else
  detach="nohup"
fi
(
  unset PLANWRIGHT_TOWER_ID PLANWRIGHT_TOWER_SESSION_ID PLANWRIGHT_TOWER_PID \
    PLANWRIGHT_TOWER_CHECKOUT PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE
  cd "$checkout" && exec "$detach" "$@" >>"$log" 2>&1 </dev/null
) &
pid=$!

# A tower that cannot start dies within moments; one still running after a
# short wait is the live replacement a retiring tower may confirm.
n=0
while [ "$n" -lt 10 ]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    printf '%s\n' "$me: the fresh tower exited at once; see its log $log" >&2
    exit 4
  fi
  sleep 0.1
  n=$((n + 1))
done

printf 'tower-launch\tname\t%s\n' "$name"
printf 'tower-launch\tpid\t%s\n' "$pid"
printf 'tower-launch\tlog\t%s\n' "$(sanitize_printable "$log")"
