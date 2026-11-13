#!/bin/bash
# Tests for the stream-json rung's process identity (scripts/fleet-streamjson.sh):
# a launch records when each of its processes began beside its pid, and a
# recorded pid the host reissued to another process reads dead and is never
# signalled by a close.
#
#   i1: a launch records supervisor.start and worker.start, each matching the
#       live process's own start; a close removes them with the pid files.
#   i2: a worker whose recorded pid now belongs to a different process reads
#       dead in `status`, and a final close releases it without signalling the
#       stranger.
#   i3: a record with no start (an older launch) keeps the pid-only reading.
#
# Hermetic: the fleet home and CLI seam are case-local. Runs under bash 3.2.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"
FDE="$here/../scripts/fleet-death-evidence.sh"
# shellcheck source=tests/lib/fixture-procs.sh
. "$here/lib/fixture-procs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"

tmp=$(fixture_scratch) || fail "no scratch directory to run in"
tmp=$(cd -P -- "$tmp" && pwd -P) || fail "cannot canonicalize the scratch directory"
home="$tmp/h"
rec="$tmp/r"
wdir="$home/streamjson/sji1"
stranger=''
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  [ -z "$stranger" ] || kill "$stranger" 2>/dev/null
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$SJ" stop sji1 --grace 2 --final >"$tmp/cleanup.out" 2>&1
  fixture_reap "$tmp/"
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sid='11111111-2222-3333-4444-555555555555'
mkdir -p "$tmp/bin" "$rec"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
printf '{"type":"system","subtype":"init","cwd":"/x","session_id":"%s","tools":[]}\n' "$SHIM_SID"
(sleep 120 && kill "$$" 2>/dev/null) &
while IFS= read -r line; do :; done
SHIM
chmod +x "$tmp/bin/claude"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u PLANWRIGHT_MC_TOKEN
  -u PLANWRIGHT_WORKER_SESSION_RECORD -u PLANWRIGHT_WORKER_SPEC_ROOT
)

senv() {
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$rec" SHIM_SID="$sid" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    /bin/sh "$SJ" "$@"
}

wt="$tmp/wt"
git -c init.defaultBranch=main init -q "$wt" || fail "cannot create the work repository"
mkdir -p "$wt/.claude"
printf 'worker_self_approval: own-branch\n' >"$wt/.claude/planwright.yml"
printf 'begin\n' >"$tmp/prompt"

# i1
senv launch sji1 identity:task-1 --prompt-file "$tmp/prompt" --cwd "$wt" >"$tmp/launch.out" \
  || fail "i1: the launch exited non-zero"
poll_until --what 'the start records' -- test -s "$wdir/worker.start" -a -s "$wdir/supervisor.start" -a -s "$wdir/worker.pid" \
  || fail "i1: the launch recorded no process start beside its pids"
for f in supervisor worker; do
  want=$(/bin/sh "$FDE" start "$(cat "$wdir/$f.pid")") || fail "i1: cannot read the live $f's start"
  [ "$(cat "$wdir/$f.start")" = "$want" ] || fail "i1: $f.start does not match the live $f's own start"
done
out=$(senv status sji1) || fail "i1: status exited non-zero"
case $out in
  "status sji1 running "* | "status sji1 awaiting-input "*) ;;
  *) fail "i1: a live worker with matching starts did not read live: $out" ;;
esac
echo "ok: i1 a launch records each process's start, and matching starts read live"

# i2: the host reissues both recorded pids to an unrelated process.
senv stop sji1 --grace 2 >"$tmp/stop1.out" || fail "i2: the stop exited non-zero"
[ ! -e "$wdir/worker.start" ] && [ ! -e "$wdir/supervisor.start" ] \
  || fail "i2: a close left start records beside pid files it dropped"
sleep 600 &
stranger=$!
printf '%s\n' "$stranger" >"$wdir/supervisor.pid"
printf '%s\n' "$stranger" >"$wdir/worker.pid"
printf 'p1\n' >"$wdir/supervisor.start"
printf 'p1\n' >"$wdir/worker.start"
out=$(senv status sji1) || fail "i2: status exited non-zero"
case $out in
  "status sji1 dead "*) ;;
  *) fail "i2: a reissued pid did not read dead: $out" ;;
esac
out=$(senv stop sji1 --grace 2 --final) || fail "i2: the close over a reissued pid exited non-zero: $out"
case $out in
  "stop sji1 stopped "* | "stop sji1 already-closed") ;;
  *) fail "i2: the close over a reissued pid left the worker held: $out" ;;
esac
kill -0 "$stranger" 2>/dev/null || fail "i2: the close signalled the process that reused the pid"
echo "ok: i2 a reissued pid reads dead and is never signalled"

# i3: no start record, the pid alone is read as it always was.
rm -f "$wdir/supervisor.start" "$wdir/worker.start"
mkdir -p "$wdir"
printf '%s\n' "$stranger" >"$wdir/supervisor.pid"
printf '%s\n' "$stranger" >"$wdir/worker.pid"
out=$(senv status sji1) || fail "i3: status exited non-zero"
case $out in
  "status sji1 running "*) ;;
  *) fail "i3: a pid with no start record did not read live: $out" ;;
esac
rm -f "$wdir/supervisor.pid" "$wdir/worker.pid"
echo "ok: i3 a record with no start keeps the pid-only reading"

echo "all fleet-streamjson-pid-identity tests passed"
