# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables the sourcing tests read; set by them
# Shared fixture for the flight-lifecycle tests: the launch harness, the
# fixture repository and fleet state, and the crash-policy helpers the
# tests/test-flight-lifecycle*.sh files all use. Sourced at each test's top
# level (it installs the EXIT trap).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_PLUGIN_DATA PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_TOWER_ID

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

fails=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fails=$((fails + 1))
}

# The relaunch runs the tmux rung's real launch, so it runs on the launch
# fixture harness: a stub tmux whose sessions run the stub worker, which
# records the directory and argv it started with.
# shellcheck source=tests/lib/tmux-launch-harness.sh
. "$here/lib/tmux-launch-harness.sh"
# shellcheck source=tests/lib/tmux-launch-cases.sh
. "$here/lib/tmux-launch-cases.sh"

SCRIPT="$ROOT/scripts/flight-lifecycle.sh"
STATE="$ROOT/scripts/fleet-state.sh"
ATTN="$ROOT/scripts/fleet-attention.sh"

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-lifecycle.sh missing or not executable" >&2
  exit 1
}

tmp="$TLH_SANDBOX/lifecycle"
mkdir -p "$tmp"
tmp=$(cd "$tmp" && pwd -P)
live_pid=''
# The harness owns the one EXIT trap; this suite's own cleanup runs first.
on_exit() {
  on_exit_status=$?
  [ -z "$live_pid" ] || kill "$live_pid" 2>/dev/null
  tlh_teardown "$on_exit_status"
}
trap on_exit EXIT

export CLAUDE_DIR="$tmp/claude"
# A bin for the forge stub one case installs; empty otherwise, so the checkout
# reads as having no forge.
mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"

repo="$tmp/primary"
mkdir -p "$repo"
gitc "$repo" init -q
printf 'x\n' >"$repo/README.md"
gitc "$repo" add -A
gitc "$repo" commit -q -m init
export PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
(umask 077 && mkdir -p "$tmp/fleet/flights")

row() { awk -F "$TAB" -v w="$1" '$1 == w' "$tmp/fleet/attention/state" 2>/dev/null; }
field() { printf '%s\n' "$1" | cut -f"$2"; }

# end_session <flight-id> — end the flight worker's stub session, as its death
# does; the relaunch refuses a name a live session holds.
end_session() {
  /bin/sh "$TLH_BIN/tmux" kill-session -t "=$(expect_session "$repo" "flight-$1")" >/dev/null 2>&1 || :
}

# A flight's fleet-home directory, as dispatch leaves it.
brief_dir() {
  (umask 077 && mkdir -p "$tmp/fleet/flights/$1/record")
  printf '# brief\n' >"$tmp/fleet/flights/$1/brief.md"
  printf '%s\n' "$repo" >"$tmp/fleet/flights/$1/checkout"
}
sleep 3600 &
live_pid=$!
dead_pid() {
  _p=$((99999 - $1))
  while kill -0 "$_p" 2>/dev/null; do _p=$((_p - 7)); done
  printf '%s\n' "$_p"
}
die_as() {
  end_session "$C"
  /bin/sh "$STATE" register "$HC" "flight:$C" --backend tmux --state-dir "$repo/.claude/worktrees/flight-$C" \
    --death-handle "process $(dead_pid "$1")" >/dev/null || fail "fixture: could not register a dead worker"
}
supervise() { (cd "$repo" && "$SCRIPT" supervise --repo-root "$repo" --now "$1" 2>"$tmp/err"); }
# launches — the relaunches so far: new-session calls, which the launch makes
# before it returns, so the count needs no wait.
launches() { calls_matching new-session | grep -c . | tr -d ' '; }
# landed_flight <id> [record|pr] [checked] — a flight worktree that has
# landed: on the file home (record, the default) its record committed on its
# branch, on the PR home nothing local. `checked` gives its brief the landed
# check flight-lifecycle.sh relaunches a landed flight under.
landed_flight() {
  gitc "$repo" worktree add -q -b "planwright/flight/$1" "$repo/.claude/worktrees/flight-$1" HEAD
  if [ "${2:-record}" = record ]; then
    mkdir -p "$repo/.claude/worktrees/flight-$1/specs/_flights"
    printf '# record\n' >"$repo/.claude/worktrees/flight-$1/specs/_flights/$1.md"
    gitc "$repo/.claude/worktrees/flight-$1" add -A
    gitc "$repo/.claude/worktrees/flight-$1" commit -q -m "chore(flight): land the record"
  fi
  brief_dir "$1"
  if [ "${3:-}" = checked ]; then
    printf 'A relaunched worker runs this landed check before it fires any point.\n' >>"$tmp/fleet/flights/$1/brief.md"
  fi
}

mkdir -p "$tmp/cfg"
