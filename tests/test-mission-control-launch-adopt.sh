#!/bin/bash
# Tests for scripts/mission-control-launch.sh adopt: a worker a program's
# dispatching session (an orchestrator mission control launched) starts on the
# stream-json rung outside the launcher is that program's worker. The
# dispatching session holds its own handle; --plan names the worker and its
# owner; the record writes the launcher row once the worker's runtime
# directory vouches for it; list, wait, unwait and retire then take the worker
# like a launch of their own, and the keeper raises its prompts to the
# program. A direct launch records no parent and is otherwise unchanged.
#
# The shared fixture is tests/lib/mc-launch-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
export PLANWRIGHT_USAGE_MIRROR=""
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

reg="$fleet/mission-control/sessions"
af() { printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" '$1 == "adopt" && $2 == k { print $3 }'; }

# sj <session handle> <owner or -> <args...> — the stream-json rung run the way
# a dispatching session's own shell runs it: holding that session's handle,
# with the owner the plan named as PLANWRIGHT_TOWER_ID. Sets RC and ERR.
sj() {
  sj_h=$1 sj_o=$2
  shift 2
  RC=0
  (cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_MC_TOKEN \
    PLANWRIGHT_SESSION_HANDLE="$sj_h" ${sj_o:+PLANWRIGHT_TOWER_ID="$sj_o"} \
    PATH="$tmp/bin:$PATH" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" \
    CLAUDE_DIR="$tmp/claude" HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
    SHIM_RECORD_DIR="${SHIM_RECORD_DIR:-$tmp}" \
    /bin/sh "$repo_root/scripts/fleet-streamjson.sh" "$@" >/dev/null 2>"$tmp/sj-stderr") || RC=$?
  ERR=$(cat "$tmp/sj-stderr")
}

# ---------------------------------------------------------------------------
# A launched session holds its own handle; a launch made from inside one
# records no parent.
# ---------------------------------------------------------------------------
rec_o="$tmp/rec-orch"
mkdir -p "$rec_o"
SHIM_RECORD_DIR=$rec_o ml launch --program alpha --kind orchestrator --scope spec:demo --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "the orchestrator launch exited $RC: $ERR"
orch=$(field name)
wait_for "$rec_o/sessionhandle" || fail "the orchestrator session never started"
[ "$(cat "$rec_o/sessionhandle" 2>/dev/null)" = "$orch" ] && ok "a launched session holds its own handle" \
  || fail "the orchestrator session holds handle '$(cat "$rec_o/sessionhandle" 2>/dev/null)', not $orch"
wait_done "$orch"

rec_d="$tmp/rec-direct"
mkdir -p "$rec_d"
SHIM_RECORD_DIR=$rec_d ML_SESSION_HANDLE=$orch ML_WORKER_HANDLE=mc-alpha-worker-0000000001 \
  ml launch --program alpha --kind tower --scope spec:direct --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "the direct launch exited $RC: $ERR"
direct=$(field name)
[ ! -e "$fleet/streamjson/$direct/parent" ] && ok "a direct launch from inside a session records no parent" \
  || fail "a direct launch recorded parent '$(cat "$fleet/streamjson/$direct/parent")'"
[ "$(reg_owner "$direct")" = mission-control:alpha ] && ok "a direct launch is still registered to its mission control" \
  || fail "the direct launch's fleet record names owner '$(reg_owner "$direct")'"
wait_done "$direct"

# ---------------------------------------------------------------------------
# --plan names the worker and its owner from the dispatching session's row.
# ---------------------------------------------------------------------------
want=$(/bin/sh "$LAUNCH" name --program alpha --kind worker --scope demo:task-2)
ml adopt "$orch" --scope demo:task-2 --plan
if [ "$RC" = 0 ] && [ "$(af name)" = "$want" ] && [ "$(af owner)" = mission-control:alpha ] && [ "$(af program)" = alpha ]; then
  ok "--plan names the worker a worker launch of the scope would be, owned by the program's mission control"
else
  fail "--plan exited $RC and printed: $OUT $ERR"
fi
ml adopt mc-alpha-orchestrator-9999999999 --scope demo:task-2 --plan
[ "$RC" = 3 ] && ok "--plan for a session with no row is refused (exit 3)" || fail "--plan for an unknown session exited $RC"
rec_w="$tmp/rec-worker"
mkdir -p "$rec_w"
SHIM_RECORD_DIR=$rec_w ml launch --program alpha --kind worker --scope flight-step --brief "$tmp/brief.md"
stepper=$(field name)
ml adopt "$stepper" --scope demo:task-2 --plan
[ "$RC" = 4 ] && ok "a worker's own launches are its steps, never adopted (exit 4)" || fail "--plan for a worker session exited $RC: $ERR"
half=mc-alpha-orchestrator-7777777777
printf 'format\t1\nname\t%s\nstate\tlaunching\ntoken\tt\nprogram\talpha\nowner\tmission-control:alpha\nkind\torchestrator\nscope\tx\nbackend\tstream-json\nhandle\t%s\nlaunched\t1\n' \
  "$half" "$half" >"$reg/$half"
ml adopt "$half" --scope demo:task-2 --plan
[ "$RC" = 4 ] && ok "a session whose launch is not complete adopts nothing (exit 4)" || fail "--plan for a launching session exited $RC: $ERR"
rm -f "$reg/$half"
wait_done "$stepper"
ml retire "$stepper"

# ---------------------------------------------------------------------------
# The dispatch, then the record.
# ---------------------------------------------------------------------------
wt="$tmp/dispatch-wt"
mkdir -p "$wt"
rec_c="$tmp/rec-child"
mkdir -p "$rec_c"
SHIM_RECORD_DIR=$rec_c sj "$orch" mission-control:alpha launch "$want" demo:task-2 --prompt-file "$tmp/brief.md" --cwd "$wt"
[ "$RC" = 0 ] || fail "the dispatch's rung launch exited $RC: $ERR"
[ "$(reg_owner "$want")" = mission-control:alpha ] && ok "the dispatched worker is registered to the program's mission control" \
  || fail "the dispatched worker's fleet record names owner '$(reg_owner "$want")'"
[ "$(cat "$fleet/streamjson/$want/parent" 2>/dev/null)" = "$orch" ] && ok "the dispatched worker records its dispatching session" \
  || fail "the dispatched worker recorded parent '$(cat "$fleet/streamjson/$want/parent" 2>/dev/null)'"
wait_for "$rec_c/towerid" || fail "the dispatched worker never started"
[ "$(cat "$rec_c/towerid" 2>/dev/null)" = '<unset>' ] && ok "the dispatched worker does not inherit the owner as its own identity" \
  || fail "the dispatched worker inherited PLANWRIGHT_TOWER_ID '$(cat "$rec_c/towerid")'"

ml adopt "$orch" --scope demo:task-3
[ "$RC" = 4 ] && ok "a worker that is not running under the planned name is not adopted (exit 4)" || fail "adopting an absent worker exited $RC: $ERR"
ml adopt "$orch" --scope demo:task-2
if [ "$RC" = 0 ] && [ "$OUT" = "adopt${TAB}$want${TAB}adopted${TAB}alpha" ]; then
  ok "the record adopts the dispatched worker"
else
  fail "the record exited $RC and printed: $OUT $ERR"
fi
row="$reg/$want"
for kv in "program${TAB}alpha" "owner${TAB}mission-control:alpha" "kind${TAB}worker" "scope${TAB}demo:task-2" \
  "backend${TAB}stream-json" "handle${TAB}$want" "state${TAB}launched" "cwd${TAB}$(cd "$wt" && pwd -P)"; do
  grep -qx "$kv" "$row" 2>/dev/null || fail "the adopted row lacks '$kv': $(cat "$row" 2>&1)"
done
cmp -s "$row" "$fleet/streamjson/$want/launcher-row" && ok "the adoption keeps a copy of the row for a recover" \
  || fail "the adopted worker has no copy of its row"
ml adopt "$orch" --scope demo:task-2
[ "$RC" = 3 ] && ok "a second record of the same worker is refused (exit 3)" || fail "a second record exited $RC"
ml adopt "$orch" --scope demo:task-2 --plan
[ "$RC" = 3 ] && ok "--plan refuses a name a row already holds (exit 3)" || fail "--plan over a held name exited $RC"

# A worker that does not record the dispatching session is never adopted.
other=$(/bin/sh "$LAUNCH" name --program alpha --kind worker --scope demo:task-4)
rec_x="$tmp/rec-stray"
mkdir -p "$rec_x"
SHIM_RECORD_DIR=$rec_x sj mc-alpha-tower-0000000000 '' launch "$other" demo:task-4 --prompt-file "$tmp/brief.md" --cwd "$wt"
ml adopt "$orch" --scope demo:task-4
[ "$RC" = 4 ] && ok "a worker launched from another session is not adopted (exit 4)" || fail "adopting a stray worker exited $RC: $ERR"
[ ! -e "$reg/$other" ] || fail "the refused adoption wrote a row"
wait_done "$other"
# Nor one launched under another profile, or for another scope.
printf '%s\n' "$orch" >"$fleet/streamjson/$other/parent"
printf 'tower\n' >"$fleet/streamjson/$other/profile"
ml adopt "$orch" --scope demo:task-4
[ "$RC" = 4 ] && ok "a session not launched under the worker profile is not adopted (exit 4)" || fail "adopting a tower-profile session exited $RC: $ERR"
printf 'worker\n' >"$fleet/streamjson/$other/profile"
printf 'demo:task-9\n' >"$fleet/streamjson/$other/scope"
ml adopt "$orch" --scope demo:task-4
[ "$RC" = 4 ] && ok "a worker whose launch recorded another scope is not adopted (exit 4)" || fail "adopting a worker of another scope exited $RC: $ERR"
[ ! -e "$reg/$other" ] || fail "a refused adoption wrote a row"

# ---------------------------------------------------------------------------
# list, wait, unwait and retire take the adopted worker as alpha's.
# ---------------------------------------------------------------------------
ml list
case "$OUT" in
  *"$want${TAB}alpha${TAB}worker${TAB}demo:task-2${TAB}stream-json${TAB}"*) ok "list shows the adopted worker as alpha's" ;;
  *) fail "list does not show the adopted worker: $OUT" ;;
esac
ml wait "$want" --on ci
[ "$RC" = 0 ] && [ "$OUT" = "wait${TAB}$want${TAB}waiting${TAB}ci" ] && ok "the adopted worker can be marked waiting" \
  || fail "wait exited $RC: $OUT $ERR"
ml unwait "$want"
[ "$RC" = 0 ] && [ "$OUT" = "wait${TAB}$want${TAB}working" ] && ok "the adopted worker can be marked working again" \
  || fail "unwait exited $RC: $OUT $ERR"

# The keeper raises the adopted worker's waiting prompt to alpha: a request
# overdue under live pids, and a live mission control for the program.
mcn=mc-alpha-mission-control-00000000aa
mkdir -p "$reg" "$fleet/streamjson/$mcn"
printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\talpha\nkind\tmission-control\nscope\tx\nbackend\tstream-json\nhandle\t%s\nlaunched\t1\n' \
  "$mcn" "$mcn" >"$reg/$mcn"
printf '%s\n' "$$" >"$fleet/streamjson/$mcn/worker.pid"
wait_done "$want"
wdir="$fleet/streamjson/$want"
rm -f "$wdir/result" "$wdir/supervisor.start" "$wdir/worker.start"
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000002\tpermission\t1000\tpending\n' >"$wdir/journal"
printf '%s\n' "$$" >"$wdir/supervisor.pid"
printf '%s\n' "$$" >"$wdir/worker.pid"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5300 2>/dev/null)
case "$OUT" in
  *"announced${TAB}pending-prompt-overdue${TAB}$want"*) ok "the keeper raises the adopted worker's prompt to its program" ;;
  *) fail "the keeper did not raise the adopted worker's prompt to alpha: $OUT" ;;
esac
case "$OUT" in
  *"stream-json-worker-unowned${TAB}$want"* | *"stream-json-worker-unregistered${TAB}$want"*) fail "the keeper raised the adopted worker as unowned or unregistered: $OUT" ;;
esac
rm -f "$wdir/journal" "$wdir/supervisor.pid" "$wdir/worker.pid"
rm -rf "${reg:?}/$mcn" "${fleet:?}/streamjson/$mcn"

ml retire "$want"
if [ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | cut -f1-3)" = "retire${TAB}$want${TAB}released" ] && [ ! -e "$row" ]; then
  ok "retire releases the adopted worker and its row"
else
  fail "retire exited $RC: $OUT $ERR"
fi

for n in "$orch" "$direct" "$other"; do
  ml retire "$n" >/dev/null 2>&1 || :
done

if [ "$failures" -ne 0 ]; then
  printf 'test-mission-control-launch-adopt: %s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "test-mission-control-launch-adopt: all passed"
