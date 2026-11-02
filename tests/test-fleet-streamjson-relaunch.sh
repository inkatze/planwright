#!/bin/bash
# Tests for the stream-json supervisor's `relaunch` verb (scripts/fleet-streamjson.sh):
# a live worker is stopped and resumed under the profile installed now.
#
#   r1 (REQ-G1.3): refusals leave the worker running and spawn nothing: an
#       unknown handle, a lock a live holder has, no persisted session, and no
#       resolvable worktree.
#   r2 (REQ-G1.3, REQ-G1.2): the relaunch stops the worker and resumes it with
#       `--resume <persisted id>` and the installed worker profile's path, in
#       the worker's own worktree wherever it is run from; the session record
#       is rewritten from current config and the scratch root kept.
#   r3 (REQ-G1.3): a worker that is not running is refused and pointed at
#       `recover`.
#   r4 (REQ-G1.3): the fleet guide states that permissions and the session
#       record load at session start and reach a running worker only by
#       relaunch.
#
# Hermetic: the fleet home, the work repository and the CLI seam are
# case-local; the CLI is a shim that records its argv and environment. Runs
# standalone under /bin/bash (bash 3.2).
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
tmp=$(cd -P -- "$tmp" && pwd -P) || fail "cannot canonicalize the scratch directory"
home="$tmp/h"
rec="$tmp/r"
wdir="$home/streamjson/sjr1"
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  senv -- stop sjr1 --grace 2 >/dev/null 2>&1
  fixture_reap "$tmp/"
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sid='11111111-2222-3333-4444-555555555555'

# The shim worker: records its argv, cwd and environment, announces the
# session, then keeps reading until stdin closes or the watchdog fires.
mkdir -p "$tmp/bin" "$rec"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >>"$SHIM_RECORD_DIR/argv"
printf 'cwd=%s\n' "$(pwd -P)" >>"$SHIM_RECORD_DIR/env"
printf 'record=%s\n' "${PLANWRIGHT_WORKER_SESSION_RECORD-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf 'tmpdir=%s\n' "${TMPDIR-<unset>}" >>"$SHIM_RECORD_DIR/env"
printf '{"type":"system","subtype":"init","cwd":"/x","session_id":"%s","tools":[]}\n' "$SHIM_SID"
(sleep "${SHIM_WATCHDOG:-120}" && kill "$$" 2>/dev/null) &
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

# senv -- <args...> — the supervisor under the case-local home and shim, with
# git's discovery and config pinned so no host repository or config leaks in.
senv() {
  shift
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$rec" SHIM_SID="$sid" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    /bin/sh "$SJ" "$@"
}

argv_lines() {
  if [ -f "$rec/argv" ]; then wc -l <"$rec/argv" | tr -d ' '; else echo 0; fi
}

pid_of() {
  cat "$wdir/$1" 2>/dev/null
}

alive() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

wt="$tmp/wt"
git -c init.defaultBranch=main init -q "$wt" || fail "cannot create the work repository"
mkdir -p "$wt/.claude"
printf 'worker_self_approval: own-branch\n' >"$wt/.claude/planwright.yml"
printf 'begin\n' >"$tmp/prompt"

senv -- launch sjr1 worker-permission-ergonomics:task-13 --prompt-file "$tmp/prompt" --cwd "$wt" >/dev/null \
  || fail "setup: the launch exited non-zero"
poll_until --what 'the persisted session' -- test -s "$wdir/session" \
  || fail "setup: the worker never persisted its session"
wpid=$(pid_of worker.pid)
alive "$wpid" || fail "setup: the worker is not running"
record=$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)
[ -f "$record" ] || fail "setup: the worker got no session record"
grep -qx 'policy=own-branch' "$record" || fail "setup: the session record does not carry the launch-time policy"
root=$(sed -n 's/^scratch_root=//p' "$record")
[ -d "$root" ] || fail "setup: the worker got no scratch root"
: >"$root/kept"

# ---------------------------------------------------------------------------
# r1: refusals touch nothing.
# ---------------------------------------------------------------------------
n=$(argv_lines)
senv -- relaunch sjr-nobody >/dev/null 2>&1
[ $? -eq 2 ] || fail "r1: an unknown handle must be a usage error (exit 2)"

ln -s "$$-$(date +%s)-1" "$wdir/journal.lock" || fail "r1: cannot plant a lock"
err=$(senv -- relaunch sjr1 2>&1 >/dev/null)
rc=$?
rm -f "$wdir/journal.lock"
[ "$rc" -eq 3 ] || fail "r1: a lock a live holder has must refuse the relaunch (exit 3), got $rc: $err"
case $err in
  *journal.lock*) ;;
  *) fail "r1: the lock refusal must name the lock: $err" ;;
esac

mv "$wdir/session" "$tmp/session.aside"
senv -- relaunch sjr1 >/dev/null 2>&1
rc=$?
mv "$tmp/session.aside" "$wdir/session"
[ "$rc" -eq 4 ] || fail "r1: a worker with no persisted session must be refused (exit 4), got $rc"

mv "$wdir/scratch-root" "$tmp/scratch-root.aside"
senv -- relaunch sjr1 >/dev/null 2>&1
rc=$?
mv "$tmp/scratch-root.aside" "$wdir/scratch-root"
[ "$rc" -eq 3 ] || fail "r1: a worker whose worktree cannot be found must be refused (exit 3), got $rc"

alive "$wpid" || fail "r1: a refused relaunch stopped the worker"
[ "$(argv_lines)" = "$n" ] || fail "r1: a refused relaunch spawned a session"
echo "ok: r1 a relaunch refuses an unknown handle, a live lock, no session, and no worktree, leaving the worker running (REQ-G1.3)"

# ---------------------------------------------------------------------------
# r2: the relaunch, run from outside the worktree, after a config change.
# ---------------------------------------------------------------------------
printf 'worker_self_approval: own-branch scratch\n' >"$wt/.claude/planwright.yml"
profile=$(env "${env_scrub[@]}" /bin/sh "$here/../scripts/fleet-launch-profile.sh" worker) \
  || fail "r2: cannot resolve the installed worker profile"
out=$(cd "$tmp" && senv -- relaunch sjr1 2>"$tmp/err") || fail "r2: the relaunch exited non-zero: $(cat "$tmp/err")"
printf '%s\n' "$out" | grep -qx "relaunched sjr1 session $sid" || fail "r2: no relaunched line in: $out"
alive "$wpid" && fail "r2: the original worker is still running"
npid=$(pid_of worker.pid)
alive "$npid" || fail "r2: the resumed worker is not running"
[ "$npid" != "$wpid" ] || fail "r2: the resumed worker has the original's pid"
last=$(tail -n 1 "$rec/argv")
case " $last " in
  *" --resume $sid "*) ;;
  *) fail "r2: the resume argv does not carry --resume $sid: $last" ;;
esac
case " $last " in
  *" --settings $profile "*) ;;
  *) fail "r2: the resume argv does not pass the installed profile $profile: $last" ;;
esac
[ "$(sed -n 's/^cwd=//p' "$rec/env" | tail -n 1)" = "$wt" ] \
  || fail "r2: the resumed worker did not run in its worktree"
[ "$(sed -n 's/^record=//p' "$rec/env" | tail -n 1)" = "$record" ] \
  || fail "r2: the resumed worker got a different session record"
grep -qx 'policy=own-branch scratch' "$record" \
  || fail "r2: the session record was not rewritten from current config: $(cat "$record")"
[ "$(sed -n 's/^tmpdir=//p' "$rec/env" | tail -n 1)" = "$root" ] && [ -f "$root/kept" ] \
  || fail "r2: the resumed worker lost its scratch root or its contents"
echo "ok: r2 a relaunch resumes the persisted session under the installed profile in its worktree, rewriting the record and keeping the scratch root (REQ-G1.3, REQ-G1.2)"

# ---------------------------------------------------------------------------
# r3: a stopped worker is recover's, not relaunch's.
# ---------------------------------------------------------------------------
senv -- stop sjr1 --grace 2 >/dev/null 2>&1 || fail "r3: the stop exited non-zero"
n=$(argv_lines)
err=$(senv -- relaunch sjr1 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 3 ] || fail "r3: a relaunch of a stopped worker must be refused (exit 3), got $rc"
case $err in
  *recover*) ;;
  *) fail "r3: the refusal must point at recover: $err" ;;
esac
[ "$(argv_lines)" = "$n" ] || fail "r3: the refused relaunch spawned a session"
echo "ok: r3 a relaunch of a worker that is not running is refused and points at recover (REQ-G1.3)"

# ---------------------------------------------------------------------------
# r4: the fleet guide carries the load-at-session-start statement.
# ---------------------------------------------------------------------------
grep -q 'reach a running worker only by relaunch' "$here/../docs/fleet.md" \
  || fail "r4: docs/fleet.md does not state that permissions reach a running worker only by relaunch"
grep -q 'relaunch <worker>' "$here/../docs/fleet.md" \
  || fail "r4: docs/fleet.md does not document the relaunch verb"
echo "ok: r4 the fleet guide states that permissions load at session start and documents relaunch (REQ-G1.3)"
