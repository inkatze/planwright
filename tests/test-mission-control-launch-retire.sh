#!/bin/bash
# Tests for scripts/mission-control-launch.sh: the retire verb leaves no row
# and no pane, and a partial release says so (mission-control REQ-D1.5).
#
# Split from tests/test-mission-control-launch.sh so each file fits the
# per-file test-time budget; the shared fixture is
# tests/lib/mc-launch-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
# The usage gate reads the status-line mirror when present; a fixture never
# reads the host's real one.
export PLANWRIGHT_USAGE_MIRROR=""
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

# The finished stream-json worker the retire cases start from.
rec="$tmp/rec-retire-worker"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope spec:alpha-worker --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the worker to retire did not launch: $ERR"
n1=$(field name)
wait_done "$n1"

# The tmux session the pane retire cases start from.
ml launch --program alpha --kind ad-hoc --scope pane-check --brief "$tmp/brief.md" --backend tmux
[ "$RC" = 0 ] || fail "fixture: the tmux session to retire did not launch: $ERR"
pane_name=$(field name)

# The tower and orchestrator sessions the row-tamper cases start from.
for kind in tower orchestrator; do
  rec="$tmp/rec-retire-$kind"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ml launch --program alpha --kind "$kind" --scope "spec:alpha-$kind" --brief "$tmp/brief.md"
  [ "$RC" = 0 ] || fail "fixture: the $kind session did not launch: $ERR"
  wait_done "$(field name)"
done

# ---------------------------------------------------------------------------
# REQ-D1.5: retire leaves no row and no pane; a partial release says so.
# ---------------------------------------------------------------------------
worker_name=$n1
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" heartbeat "$worker_name" spec:alpha-worker working \
  || fail "fixture: the attention row was not seeded"
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" render 2>/dev/null | grep -q "$worker_name" \
  || fail "fixture: the seeded attention row does not render"
ml retire "$worker_name"
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	$worker_name	released	"; then
  ok "retire releases a finished stream-json session"
else
  fail "retire of a finished session: exit $RC, $OUT $ERR"
fi
[ ! -e "$fleet/mission-control/sessions/$worker_name" ] && [ ! -e "$fleet/mission-control/launch/$worker_name" ] \
  && ok "the retired session has no registry row and no launch directory" || fail "retire left the row or the launch directory"
[ ! -e "$fleet/dispatch-markers/$worker_name" ] && ok "the fleet registry marker is retired" || fail "the fleet registry marker remains"
last=$(env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-state.sh" registry 2>/dev/null \
  | awk -F '\t' -v w="$worker_name" '$2 == w { l = $0 } END { print l }')
case $last in *"	closed") ok "the fleet registry record is closed" ;; *) fail "the fleet registry record is not closed: $last" ;; esac
ml list
case $OUT in *"$worker_name"*) fail "list still shows the retired session" ;; *) ok "list no longer shows the retired session" ;; esac
if env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" render 2>/dev/null | grep -q "$worker_name"; then
  fail "the retired session's attention row survived"
else
  ok "the retired session has no attention row"
fi
ml retire "$worker_name"
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	$worker_name	released	released=process,registry,attention	held=-$" \
  && ok "a second retire closes the row-less worker idempotently" || fail "a second retire: exit $RC, $OUT $ERR"

# A worker an older planwright or /orchestrate launched straight on the
# stream-json rung has no row: retire closes it by its handle all the same,
# a dead one included, and its stale attention row goes with it.
old="$fleet/streamjson/cp-task-1"
mkdir -p "$old"
printf '999999999\n' >"$old/supervisor.pid"
printf '999999999\n' >"$old/worker.pid"
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000001\tpermission\t1000\tpending\n' >"$old/journal"
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" decide cp-task-1 cp:task-1 \
  "OVERDUE permission request tool Bash req aaaa1111 - answer via fleet-streamjson.sh answer" deny "allow|deny" high \
  || fail "fixture: the stale attention row was not seeded"
ml retire cp-task-1
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	cp-task-1	released	released=process,registry,attention	held=-$" \
  && ok "retire closes a worker launched without the launcher" || fail "retire of a row-less worker: exit $RC, $OUT $ERR"
if env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" queue 2>/dev/null | grep -q cp-task-1; then
  fail "the row-less worker's attention row survived its retire"
else
  ok "and its stale attention row is gone"
fi
grep -q "	undeliverable	" "$old/journal" && ok "and its pending receipt is closed" || fail "the receipt stayed: $(cat "$old/journal")"
busy="$fleet/streamjson/orch-busy"
mkdir -p "$busy"
ln -s "$$-$(date +%s)-1" "$busy/recover.lock"
ml retire orch-busy
[ "$RC" = 3 ] && case $ERR in *"recover.lock is held"*) true ;; *) false ;; esac \
  && ok "retire refuses a row-less worker whose recover is in flight, naming the lock" || fail "retire over a held recover lock: exit $RC, $OUT $ERR"
[ -L "$busy/recover.lock" ] && ok "and leaves the recover's lock alone" || fail "the in-flight recover's lock was broken"
rm -rf "$busy"
ml retire nosuch-worker
[ "$RC" = 3 ] && ok "a name with neither a row nor a stream-json worker exits 3" || fail "retire of an unknown name exited $RC"
case $ERR in *"fleet-dispatch-headless.sh stop nosuch-worker"*"tmux kill-window"*) ok "and names the stops that apply" ;; *) fail "the refusal names no stop: $ERR" ;; esac
ml retire mc-alpha-worker-9999999999
[ "$RC" = 3 ] && ok "a launcher name with no row and no worker exits 3" || fail "retire of an unknown launcher name exited $RC"
ml retire "../x"
[ "$RC" = 2 ] && ok "a name outside the handle grammar is refused (exit 2)" || fail "a traversal name exited $RC"

win=$(awk -F '\t' '$1 == "handle" { print $2 }' "$fleet/mission-control/sessions/$pane_name")
[ -e "$tmp/tmux/$win" ] && ok "the tmux session has a live window ($win) before retire" || fail "the tmux launch left no window"
ro=$(reg_owner "$win")
[ "$ro" = mission-control:alpha ] && ok "the fleet registry attributes the tmux session to mission-control:alpha" \
  || fail "the tmux session's fleet record owner is '$ro', not mission-control:alpha"
argv_t=$(cat "$tmp/tmux/argv-$win" 2>/dev/null)
case $argv_t in
  *fleet-dispatch-env.sh*--root*--inbound*--identity*"$pane_name"*--settings*"$repo_root/config/worker-settings.json"*--name*"$pane_name"*) ok "the tmux window runs the session under its profile and name" ;;
  *) fail "the tmux window's argv lacks the profile or name: $argv_t" ;;
esac
if printf '%s\n' "$argv_t" | grep -A2 -x -- '--identity' | tr '\n' ' ' | grep -q "$pane_name pane-check"; then
  ok "the tmux session's worker identity carries its scope"
else
  fail "the tmux session's identity lacks its scope: $argv_t"
fi
grep -qF 'Never hand the operator a pane' "$fleet/mission-control/launch/$pane_name/brief.md" \
  && ok "the tmux session's brief carries the rules" || fail "the tmux session's brief lacks the rules"
TMUX_KILL_FAIL=1 ml retire "$pane_name"
if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q "^retire	$pane_name	partial	released=-	held=pane,registry,attention,row$"; then
  ok "a window that will not close is reported partial, holding its fleet record and attention row (exit 1)"
else
  fail "a failed pane close was not reported partial: exit $RC, $OUT"
fi
[ -f "$fleet/mission-control/sessions/$pane_name" ] && ok "a partial release keeps the row for a retry" || fail "a partial release dropped the row"
: >"$tmp/tmux/calls"
TMUX_LIST_FAIL=1 ml retire "$pane_name"
if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'held=pane' && ! grep -q '^kill-window' "$tmp/tmux/calls"; then
  ok "a tmux server that cannot be listed holds the pane rather than reading it as gone"
else
  fail "an unlistable tmux server was read as released: exit $RC, $OUT"
fi
ML_TMUX_PANE=$win ml retire "$pane_name"
[ "$RC" = 3 ] && ok "retire refuses from inside the session's own window (exit 3)" || fail "a self-window retire exited $RC"
ml retire "$pane_name"
[ "$RC" = 0 ] && ok "a retry completes the release" || fail "the retry exited $RC: $OUT"
[ ! -e "$tmp/tmux/$win" ] && ok "the retired session has no pane" || fail "the pane survived retire"
[ ! -e "$fleet/mission-control/sessions/$pane_name" ] && ok "the retired tmux session has no row" || fail "the tmux row survived retire"

# A row whose window id is live under another name (renamed, or reused by
# another server): neither killed nor read as gone.
reuse_row="$fleet/mission-control/sessions/mc-alpha-ad-hoc-1111111111"
printf 'other-session\n' >"$tmp/tmux/@99"
printf 'format\t1\nname\tmc-alpha-ad-hoc-1111111111\nstate\tlaunched\nbackend\ttmux\nhandle\t@99\n' >"$reuse_row"
: >"$tmp/tmux/calls"
ml retire mc-alpha-ad-hoc-1111111111
if [ "$RC" = 1 ] && [ -e "$tmp/tmux/@99" ] && ! grep -q '^kill-window' "$tmp/tmux/calls" \
  && printf '%s\n' "$OUT" | grep -q 'held=pane'; then
  ok "a window id live under another name is held and not killed"
else
  fail "a window id under another name: exit $RC, $OUT"
fi
rm -f "$tmp/tmux/@99"
TMUX_NO_SERVER=1 ml retire mc-alpha-ad-hoc-1111111111
[ "$RC" = 0 ] && [ ! -e "$reuse_row" ] && ok "with no tmux server the window is gone and retire completes" \
  || fail "a retire with no tmux server: exit $RC, $OUT"

# A tmux reservation that never recorded its window: retire closes the window
# by name and retires the marker under its id.
nh_name=mc-alpha-ad-hoc-4444444444
printf '%s\n' "$nh_name" >"$tmp/tmux/@77"
mkdir -p "$fleet/dispatch-markers"
printf 'format\t1\nname\t%s\nstate\tlaunching\ntoken\tx\nbackend\ttmux\nhandle\t-\n' "$nh_name" >"$fleet/mission-control/sessions/$nh_name"
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-register.sh" --handle @77 --backend tmux \
  --scope offload --death-handle 'tmux-window stub @77' >/dev/null 2>&1
[ -f "$fleet/dispatch-markers/@77" ] || fail "fixture: no marker for @77"
ml retire "$nh_name"
if [ "$RC" = 0 ] && [ ! -e "$tmp/tmux/@77" ] && [ ! -e "$fleet/dispatch-markers/@77" ]; then
  ok "a reservation with no window id closes its window by name and retires its marker"
else
  fail "a no-handle tmux reservation: exit $RC, $OUT, marker $(ls "$fleet/dispatch-markers" 2>/dev/null)"
fi

# A launch that died after its reservation: retire finishes it; a launch
# still in flight is refused.
dead_row="$fleet/mission-control/sessions/mc-alpha-worker-2222222222"
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid"
printf 'format\t1\nname\tmc-alpha-worker-2222222222\nstate\tlaunching\ntoken\tx\npid\t%s\nbackend\tstream-json\nhandle\tmc-alpha-worker-2222222222\n' "$dead_pid" >"$dead_row"
ml retire mc-alpha-worker-2222222222
[ "$RC" = 0 ] && [ ! -e "$dead_row" ] && ok "retire clears the reservation of a launch that died" \
  || fail "a dead launch's reservation was not cleared: exit $RC, $OUT $ERR"
# A launch in flight holds its name's lock, whatever its row says.
printf 'format\t1\nname\tmc-alpha-worker-2222222222\nstate\tlaunching\ntoken\tx\npid\t1\nbackend\tstream-json\nhandle\tmc-alpha-worker-2222222222\n' >"$dead_row"
mkdir -p "$fleet/mission-control/locks"
ln -s "$$-$(date +%s)-1" "$fleet/mission-control/locks/mc-alpha-worker-2222222222"
ml retire mc-alpha-worker-2222222222
[ "$RC" = 3 ] && [ -e "$dead_row" ] && ok "retire refuses a launch still in flight (exit 3)" \
  || fail "an in-flight launch was retired: exit $RC, $OUT"
rm -f "$fleet/mission-control/locks/mc-alpha-worker-2222222222" "$dead_row"
ml name --program alpha --kind reviewer --scope locked-launch
mkdir -p "$fleet/mission-control/locks"
ln -s "$$-$(date +%s)-1" "$fleet/mission-control/locks/$OUT"
ll_name=$OUT
ml launch --program alpha --kind reviewer --scope locked-launch --brief "$tmp/brief.md"
[ "$RC" = 3 ] && [ ! -e "$fleet/mission-control/sessions/$ll_name" ] \
  && ok "a launch whose name lock is held is refused (exit 3)" || fail "a locked launch exited $RC: $ERR"
rm -f "$fleet/mission-control/locks/$ll_name"

# A launch or retire of a name whose lock another live process holds.
mkdir -p "$fleet/mission-control/locks"
ln -s "$$-$(date +%s)-1" "$fleet/mission-control/locks/mc-alpha-reviewer-3333333333"
printf 'format\t1\nname\tmc-alpha-reviewer-3333333333\nstate\tlaunched\nbackend\tstream-json\nhandle\tmc-alpha-reviewer-3333333333\n' \
  >"$fleet/mission-control/sessions/mc-alpha-reviewer-3333333333"
ml retire mc-alpha-reviewer-3333333333
[ "$RC" = 3 ] && ok "a retire whose name lock is held is refused (exit 3)" || fail "a locked retire exited $RC: $ERR"
rm -f "$fleet/mission-control/locks/mc-alpha-reviewer-3333333333" "$fleet/mission-control/sessions/mc-alpha-reviewer-3333333333"

# A stream-json rung that refuses after the reservation leaves no row and no
# launch directory, and closes what it may have started.
ml name --program alpha --kind reviewer --scope rung-fails
rf_name=$OUT
sleep 30 &
rf_pid=$!
mkdir -p "$fleet/streamjson/$rf_name"
printf '%s\n' "$rf_pid" >"$fleet/streamjson/$rf_name/supervisor.pid"
ml launch --program alpha --kind reviewer --scope rung-fails --brief "$tmp/brief.md"
if [ "$RC" = 1 ] && [ ! -e "$fleet/mission-control/sessions/$rf_name" ] && [ ! -e "$fleet/mission-control/launch/$rf_name" ]; then
  ok "a rung that does not start leaves no row and no launch directory (exit 1)"
else
  fail "a failed rung start left state: exit $RC, $ERR"
fi
if kill -0 "$rf_pid" 2>/dev/null; then
  ok "a session the rung already held under the name is left running"
  kill "$rf_pid" 2>/dev/null
else
  fail "the failed launch stopped a session it never started"
fi
wait "$rf_pid" 2>/dev/null
rm -rf "${fleet:?}/streamjson/$rf_name"
# A rung that fails for another reason (here its dispatch wrapper is
# missing, exit 8) has nothing running, so the name is released.
mkdir -p "$tmp/s8"
cp -R "$repo_root/scripts" "$tmp/s8/scripts"
mkdir -p "$tmp/s8/config" && cp "$repo_root/config/mission-control-settings.json" "$tmp/s8/config/"
rm -f "$tmp/s8/scripts/fleet-dispatch-env.sh"
LAUNCH="$tmp/s8/scripts/mission-control-launch.sh" ml launch --program alpha --kind reviewer --scope rung-fails-2 --brief "$tmp/brief.md"
rf2_rc=$RC
ml name --program alpha --kind reviewer --scope rung-fails-2
if [ "$rf2_rc" = 1 ] && [ ! -e "$fleet/mission-control/sessions/$OUT" ] && [ ! -e "$fleet/mission-control/launch/$OUT" ]; then
  ok "a rung that fails to start a session leaves no row once nothing runs (exit 1)"
else
  fail "a failed rung start: exit $rf2_rc, row $(cat "$fleet/mission-control/sessions/$OUT" 2>/dev/null)"
fi

# A leftover launch directory with no row is cleared by the next launch.
ml name --program alpha --kind reviewer --scope leftover
lo_name=$OUT
mkdir -p "$fleet/mission-control/launch/$lo_name"
: >"$fleet/mission-control/launch/$lo_name/stale"
rec="$tmp/rec-leftover"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope leftover --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ ! -e "$fleet/mission-control/launch/$lo_name/stale" ] \
  && ok "a launch clears a leftover launch directory of its name" || fail "a leftover launch directory wedged the name: exit $RC, $ERR"
wait_for "$rec/stdin" >/dev/null
wait_done "$lo_name"

# A launch directory that cannot be removed holds the row.
mkdir -p "$fleet/mission-control/launch/$lo_name/locked"
: >"$fleet/mission-control/launch/$lo_name/locked/f"
chmod 500 "$fleet/mission-control/launch/$lo_name/locked"
if [ -w "$fleet/mission-control/launch/$lo_name/locked" ]; then
  ok "skip: mode 500 does not stop this user removing files"
else
  ml retire "$lo_name"
  if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'held=row' && [ -e "$fleet/mission-control/sessions/$lo_name" ]; then
    ok "a launch directory that will not go holds the row (exit 1)"
  else
    fail "an unremovable launch directory was reported released: exit $RC, $OUT"
  fi
fi
chmod 700 "$fleet/mission-control/launch/$lo_name/locked"
ml retire "$lo_name"
[ "$RC" = 0 ] && ok "the retry releases it" || fail "the retry after the launch directory exited $RC: $OUT"

# A fleet marker that does not match its record is not counted released.
ml name --program alpha --kind orchestrator --scope spec:alpha-orchestrator
orch=$OUT
if [ -f "$fleet/dispatch-markers/$orch" ]; then
  awk -F '\t' 'BEGIN { OFS = "\t" } { $2 = "spec:tampered"; print }' "$fleet/dispatch-markers/$orch" >"$tmp/marker"
  cat "$tmp/marker" >"$fleet/dispatch-markers/$orch"
  ml retire "$orch"
  if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'held=registry'; then
    ok "a marker the fleet registry would not retire holds the registry class"
  else
    fail "a mismatched marker was counted released: exit $RC, $OUT"
  fi
else
  fail "fixture: the orchestrator session has no fleet marker"
fi

# A session that started but whose row could not be written is stopped.
ml name --program alpha --kind ad-hoc --scope row-fails
rw_name=$OUT
before=$(cat "$tmp/tmux/next" 2>/dev/null)
TMUX_LOCK_DIR="$fleet/mission-control/sessions" ml launch --program alpha --kind ad-hoc --scope row-fails \
  --brief "$tmp/brief.md" --backend tmux
chmod 700 "$fleet/mission-control/sessions"
said_stopped=0
case $ERR in *"was stopped"*) said_stopped=1 ;; esac
if [ "$RC" = 1 ] && [ ! -e "$tmp/tmux/@$before" ] && [ "$said_stopped" = 1 ]; then
  ok "a session whose row cannot be written is stopped (exit 1)"
else
  fail "a started session with no row was left running: exit $RC, $ERR"
fi
[ ! -e "$fleet/dispatch-markers/@$before" ] && ok "the stopped session's fleet marker is retired" \
  || fail "the stopped session's fleet marker was left behind"
rm -f "$fleet/mission-control/sessions/$rw_name"

# A window the rung created but could not name is closed by name before the
# reservation is released.
bad_before=$(cat "$tmp/tmux/next" 2>/dev/null)
TMUX_BAD_ID=1 ml launch --program alpha --kind ad-hoc --scope bad-window --brief "$tmp/brief.md" --backend tmux
bad_rc=$RC
ml name --program alpha --kind ad-hoc --scope bad-window
if [ "$bad_rc" = 1 ] && [ ! -e "$tmp/tmux/@$bad_before" ] && [ ! -e "$fleet/mission-control/sessions/$OUT" ]; then
  ok "a window the rung could not name is closed and the name released (exit 1)"
else
  fail "a window with an unusable id: exit $bad_rc, window $(ls "$tmp/tmux/@$bad_before" 2>&1), row $(cat "$fleet/mission-control/sessions/$OUT" 2>/dev/null)"
fi

# A row whose window id is not @ and digits never reaches tmux.
bad_row="$fleet/mission-control/sessions/mc-alpha-ad-hoc-0000000000"
printf 'format\t1\nname\tmc-alpha-ad-hoc-0000000000\nbackend\ttmux\nhandle\t@1;x\n' >"$bad_row"
: >"$tmp/tmux/calls"
ml retire mc-alpha-ad-hoc-0000000000
if [ "$RC" = 2 ] && [ ! -s "$tmp/tmux/calls" ]; then
  ok "a row naming a malformed window id is refused before any tmux call"
else
  fail "a malformed window id reached retire: exit $RC, calls: $(cat "$tmp/tmux/calls")"
fi
rm -f "$bad_row"

# A row in a format the launcher does not know is refused, naming the field.
ml name --program alpha --kind tower --scope spec:alpha-tower
tower_row="$fleet/mission-control/sessions/$OUT"
sed 's/^format	1$/format	9/' "$tower_row" >"$tmp/row9" && cat "$tmp/row9" >"$tower_row"
ml retire "$OUT"
[ "$RC" = 2 ] && case $ERR in *format*) true ;; *) false ;; esac \
  && ok "a row with an unknown format is refused, naming the field" || fail "an unknown-format row was not refused: $RC $ERR"
ml kinds
want_kinds=$(printf '%s\t%s\t%s\n' tower tower orchestrate_dispatch orchestrator tower bookkeeping worker worker execution \
  reviewer worker execute_step ad-hoc worker offload mission-control mission-control orchestrate_dispatch)
[ "$OUT" = "$want_kinds" ] && ok "kinds prints each kind's profile and key" || fail "kinds: $OUT"
ml list
if [ "$RC" = 0 ] && case $ERR in *"format field is not"*) true ;; *) false ;; esac \
  && printf '%s\n' "$OUT" | grep -q '^mc-alpha-orchestrator'; then
  ok "list warns on an unknown-format row and still lists the rest"
else
  fail "list with an unknown-format row: exit $RC, out $OUT, err $ERR"
fi
chmod 000 "$fleet/mission-control/sessions"
if [ -r "$fleet/mission-control/sessions" ]; then
  ok "skip: mode 000 does not stop this user reading the registry"
else
  ml list
  [ "$RC" = 2 ] && ok "list on an unreadable registry fails (exit 2)" || fail "list on an unreadable registry exited $RC: $OUT"
fi
chmod 700 "$fleet/mission-control/sessions"
if empty_out=$(env PLANWRIGHT_FLEET_STATE_DIR="$tmp/empty-fleet" /bin/sh "$LAUNCH" list 2>&1) && [ -z "$empty_out" ]; then
  ok "list with no registry prints nothing"
else
  fail "list with no registry: $empty_out"
fi

# ---------------------------------------------------------------------------
# A parked session (a live operator, ci or ready-flip wait) is never retired
# by accident: the refusal names the wait, --force-parked overrides it, and
# clearing the wait restores the plain retire.
# ---------------------------------------------------------------------------
rec="$tmp/rec-retire-parked"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope parked-kickoff --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the parked session did not launch: $ERR"
parked=$(field name)
wait_done "$parked"
for why in operator ci ready-flip; do
  ml wait "$parked" --on "$why"
  [ "$RC" = 0 ] || fail "fixture: wait --on $why exited $RC: $ERR"
  ml retire "$parked"
  if [ "$RC" = 4 ] && case $ERR in *"waiting on $why"*) true ;; *) false ;; esac \
    && [ -f "$fleet/mission-control/sessions/$parked" ]; then
    ok "retire refuses a session with a live $why wait, names it and leaves the row"
  else
    fail "retire of a session waiting on $why: exit $RC, out $OUT, err $ERR"
  fi
done
ml retire "$parked" --force-parked --bogus
[ "$RC" = 2 ] && ok "retire still refuses an unknown flag" || fail "retire with an unknown flag exited $RC"
ml unwait "$parked"
ml retire "$parked"
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	$parked	released	" \
  && [ ! -e "$fleet/mission-control/sessions/$parked" ]; then
  ok "clearing the wait restores the plain retire"
else
  fail "retire after unwait: exit $RC, $OUT $ERR"
fi
rec="$tmp/rec-retire-forced"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope forced-kickoff --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the second parked session did not launch: $ERR"
forced=$(field name)
wait_done "$forced"
ml wait "$forced" --on operator
ml retire "$forced" --force-parked
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	$forced	released	" \
  && [ ! -e "$fleet/mission-control/sessions/$forced" ]; then
  ok "--force-parked retires a parked session"
else
  fail "retire --force-parked: exit $RC, $OUT $ERR"
fi
ml retire "$n1" --force-parked
[ "$RC" = 3 ] && ok "--force-parked on an unknown name still reports no such session" || fail "force on a retired name exited $RC"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
