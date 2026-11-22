#!/bin/bash
# Tests for scripts/mc-keeper.sh's session bounds: a session idle past
# mission_control_worker_idle is retired, one past
# mission_control_worker_lifetime hands over, and the cases each bound leaves
# alone.
#
# Companions: the other tests/test-mc-keeper*.sh suites; all but
# test-mc-keeper-rowless.sh share tests/lib/mc-keeper-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-bounds.sh
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-keeper-fixture.sh
. "$here/lib/mc-keeper-fixture.sh" || exit 1

mc_row alpha live
mc_row beta live

# ---------------------------------------------------------------------------
# Short-lived workers: a session idle past mission_control_worker_idle is
# retired, one past mission_control_worker_lifetime hands over; a tower, a
# kickoff relay, a busy young session and one parked on its own question are
# left alone.
# ---------------------------------------------------------------------------
sleep 600 >/dev/null 2>&1 &
bound_pid=$!
trap 'kill "$bound_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tmux"
cat >"$tmp/bin/tmux" <<'STUB'
#!/bin/sh
verb=$1
shift
# The server's identity is $TMUX_STUB/server. if-shell -F -t <window>
# <condition> <command> runs its command only when the window's server, id
# and name match the pin the condition carries.
srv=$(cat "$TMUX_STUB/server" 2>/dev/null || echo 4242.1700000000)
if [ "$verb" = if-shell ]; then
  t=$3 want=${4##*,}
  want=${want%\}}
  [ -f "$TMUX_STUB/${t#@}.name" ] && [ "$want" = "$srv/$t/$(cat "$TMUX_STUB/${t#@}.name")" ] || exit 0
  # shellcheck disable=SC2086 # the command's words
  exec "$0" $5
fi
w='' fmt=''
while [ "$#" -gt 0 ]; do
  case $1 in
    -t) w=$2; shift 2 ;;
    -F | -p | -a) shift ;;
    *) fmt=$1; shift ;;
  esac
done
n=${w#@}
case $verb in
  ls) exit 0 ;;
  list-windows)
    for f in "$TMUX_STUB"/*.name; do
      [ -f "$f" ] || continue
      id=${f##*/}
      case $fmt in
        '#{pid}.#{start_time} '*) printf '%s @%s %s\n' "$srv" "${id%.name}" "$(cat "$f")" ;;
        *) printf '@%s %s\n' "${id%.name}" "$(cat "$f")" ;;
      esac
    done
    ;;
  display-message)
    [ -n "$w" ] || { printf '%s\n' "$srv"; exit 0; }
    [ -f "$TMUX_STUB/$n.name" ] || { echo "can't find window: $w" >&2; exit 1; }
    pin="$srv/$w/$(cat "$TMUX_STUB/$n.name")"
    case $fmt in
      '#{pane_pid} '*) printf '%s %s\n' "$(cat "$TMUX_STUB/$n.pid")" "$pin" ;;
      *window_name*) printf '%s\n' "$pin" ;;
      *) cat "$TMUX_STUB/$n.pid" ;;
    esac
    ;;
  capture-pane)
    [ -f "$TMUX_STUB/$n.name" ] || exit 1
    # A window with a .switch count shows .pane2 from that capture on.
    if [ -f "$TMUX_STUB/$n.switch" ]; then
      c=$(($(cat "$TMUX_STUB/$n.count" 2>/dev/null || echo 0) + 1))
      echo "$c" >"$TMUX_STUB/$n.count"
      [ "$c" -lt "$(cat "$TMUX_STUB/$n.switch")" ] || { cat "$TMUX_STUB/$n.pane2"; exit 0; }
    fi
    cat "$TMUX_STUB/$n.pane"
    ;;
  kill-window) rm -f "$TMUX_STUB/$n.name" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/tmux"
cat >"$tmp/idle.pane" <<'EOF'
⏺ The pull request is open.

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/question.pane" <<'EOF'
⏺ Two readings of the Done-when fit the code.
  Should I take the narrower one?

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/busy.pane" <<'EOF'
⏺ Running the gate.

✻ Herding… (12s · esc to interrupt)

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
sessions="$fleet/mission-control/sessions"
mkdir -p "$sessions"
# bound_row <name> <kind> <window n> <launched> <pane> [<scope>]: a launched
# tmux session, its window live in the stub.
bound_row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt\npid\t1\nprogram\talpha\nowner\tmission-control:alpha\nkind\t%s\nscope\t%s\nbackend\ttmux\nhandle\t@%s\nprofile\tworker\ntier\t-\nbrief\t-\ncwd\t-\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t%s\n' \
    "$1" "$2" "${6:-s-$3}" "$3" "$4" >"$sessions/$1"
  printf '%s\n' "$1" >"$tmp/tmux/$3.name"
  printf '%s\n' "$bound_pid" >"$tmp/tmux/$3.pid"
  cp "$5" "$tmp/tmux/$3.pane"
}
# relaunch_row <name> <launched>: the same name, a later launch.
relaunch_row() {
  awk -v l="$2" -F '\t' 'BEGIN { OFS = "\t" } $1 == "launched" { $2 = l } { print }' "$sessions/$1" >"$sessions/$1.new" \
    && mv -f "$sessions/$1.new" "$sessions/$1"
}
# sj_row <name> <launched> <turn ended> <final text> [<is_error>]: a
# stream-json session whose last turn ended at <turn ended>, its final text
# <final text>.
sj_row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\talpha\nkind\tworker\nscope\ts\nbackend\tstream-json\nlaunched\t%s\n' \
    "$1" "$2" >"$sessions/$1"
  mkdir -p "$fleet/streamjson/$1"
  printf 'result\tsuccess\t%s\t%s\n' "$3" "${5:-false}" >"$fleet/streamjson/$1/result"
  jq -nc --arg r "$4" '{type:"result",subtype:"success",result:$r}' >"$fleet/streamjson/$1/events.jsonl"
}
t1=20000
t2=$((t1 + 1900))
bound_row mc-alpha-worker-idle worker 21 "$t1" "$tmp/idle.pane"
bound_row mc-alpha-reviewer-old reviewer 22 0 "$tmp/busy.pane"
bound_row mc-alpha-worker-young worker 23 "$t1" "$tmp/busy.pane"
bound_row mc-alpha-worker-asks worker 24 "$t1" "$tmp/question.pane"
bound_row mc-alpha-tower-old tower 25 0 "$tmp/idle.pane"
bound_row mc-alpha-worker-old worker 26 0 "$tmp/busy.pane"
bound_row mc-alpha-worker-kickoff worker 27 0 "$tmp/idle.pane" kickoff-demo
bound_row mc-alpha-worker-again worker 28 "$t1" "$tmp/idle.pane"
sj_row mc-alpha-worker-sjidle "$t1" "$t1" "Done: the pull request is open."
sj_row mc-alpha-worker-sjasks "$t1" "$t1" "Two readings fit.
Should I take the narrower one?  "
sj_row mc-alpha-worker-sjended "$t1" "$t1" "Done." true
sj_row mc-alpha-worker-sjstale $((t1 + 5)) "$t1" "Done."
bound_row mc-alpha-ad-hoc-idle ad-hoc 30 "$t1" "$tmp/idle.pane"
bound_row mc-beta-worker-idle worker 31 "$t1" "$tmp/idle.pane"
# Input lands after the watch's own stall scan: the re-check samples again.
bound_row mc-alpha-worker-typed worker 32 "$t1" "$tmp/idle.pane"
cp "$tmp/busy.pane" "$tmp/tmux/32.pane2"
echo 1000 >"$tmp/tmux/32.switch"
sj_row mc-alpha-worker-sjbusy "$t1" "$t1" "Done."
printf '{"type":"assistant","message":"working on the steered turn"}\n' >>"$fleet/streamjson/mc-alpha-worker-sjbusy/events.jsonl"
sed -i.bak 's/^program\talpha$/program\tbeta/' "$sessions/mc-beta-worker-idle" && rm -f "$sessions/mc-beta-worker-idle.bak"
bound_env() { mc_env env PATH="$tmp/bin:$PATH" TMUX_STUB="$tmp/tmux" "$@"; }
(bound_env /bin/bash "$repo_root/scripts/mc-stall.sh" scan --program alpha --now "$t1" >/dev/null 2>&1)
# Captures per sample, so the switch lands on the re-check's, after the
# watch's own scan.
echo $(($(cat "$tmp/tmux/32.count") * 2 + 1)) >"$tmp/tmux/32.switch"
# The stall scan sampled mc-alpha-worker-again's first launch; its relaunch
# under the same name has no sample of its own yet.
relaunch_row mc-alpha-worker-again $((t1 + 10))
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now "$t2" 2>"$tmp/stderr")
RC=$?
expect_rc "bounds reads every session" 0
expect_out "idle past the idle bound retires" "retire${tab}mc-alpha-worker-idle${tab}${t1}${tab}idle 1900s, bound 1800s"
expect_out "lived past the lifetime hands over" "handover${tab}mc-alpha-reviewer-old${tab}0${tab}lived ${t2}s, bound 14400s"
expect_out "a stream-json session whose last turn completed past the grace retires, naming its last result" "retire${tab}mc-alpha-worker-sjidle${tab}${t1}${tab}completed result=success 1900s ago, grace 300s"
expect_no_out "a busy young session is left alone" "mc-alpha-worker-young"
expect_no_out "a session parked on its own question is never retired" "mc-alpha-worker-asks"
expect_no_out "nor a stream-json one whose last turn asked" "mc-alpha-worker-sjasks"
expect_no_out "a tower is not bound" "mc-alpha-tower-old"
expect_no_out "a kickoff relay is not bound" "mc-alpha-worker-kickoff"
expect_no_out "a sample from an earlier launch under the name is ignored" "mc-alpha-worker-again"
expect_out "an ad-hoc session is bound too" "retire${tab}mc-alpha-ad-hoc-idle${tab}"
expect_no_out "another program's session is its own program's" "mc-beta-worker-idle"
expect_no_out "a stream-json turn that ended in error is not idle" "mc-alpha-worker-sjended"
expect_no_out "nor one whose result predates its launch" "mc-alpha-worker-sjstale"
expect_no_out "a session whose events follow its last result is mid-turn, not idle" "mc-alpha-worker-sjbusy"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 60)) 2>"$tmp/stderr")
RC=$?
expect_rc "bounds inside the bound" 0
expect_no_out "an idle session inside the bound stays" "mc-alpha-worker-idle"
expect_no_out "a completed stream-json session inside the grace stays" "mc-alpha-worker-sjidle"

# A completed stream-json worker stops holding a slot after the grace, well
# inside the idle bound; a running one, an unreadable one and a tmux one
# are left alone.
sj_row mc-alpha-worker-sjgrace "$t1" "$t1" "Done: the pull request is open."
sj_row mc-alpha-worker-sjunread "$t1" "$t1" "Done."
chmod 000 "$fleet/streamjson/mc-alpha-worker-sjunread/result"
sj_unread_denied=0
if hermetic_access_denied r "$fleet/streamjson/mc-alpha-worker-sjunread/result"; then sj_unread_denied=1; fi
sj_row mc-alpha-worker-sjrunning "$t1" "$t1" "Done."
printf '{"type":"assistant","message":"next turn"}\n' >>"$fleet/streamjson/mc-alpha-worker-sjrunning/events.jsonl"
bound_row mc-alpha-worker-tmuxgrace worker 33 "$t1" "$tmp/busy.pane"
mkdir -p "$fleet/streamjson/mc-alpha-worker-tmuxgrace"
printf 'result\tsuccess\t%s\tfalse\n' "$t1" >"$fleet/streamjson/mc-alpha-worker-tmuxgrace/result"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 400)) 2>"$tmp/stderr")
expect_out "a completed stream-json worker retires after the grace, far inside the idle bound" "retire${tab}mc-alpha-worker-sjgrace${tab}${t1}${tab}completed result=success 400s ago, grace 300s"
if [ "$sj_unread_denied" -eq 1 ]; then
  expect_no_out "a stream-json worker whose status cannot be read counts as live" "mc-alpha-worker-sjunread"
else
  echo "skip: a stream-json worker whose status cannot be read: the file is still readable here"
fi
expect_no_out "a running stream-json worker is untouched" "mc-alpha-worker-sjrunning"
expect_no_out "a tmux worker is untouched by the completed rule" "mc-alpha-worker-tmuxgrace"
chmod 600 "$fleet/streamjson/mc-alpha-worker-sjunread/result"

# A session with a live wait (operator, ci or ready-flip) is parked, not
# finished: no bound retires it, whichever rung it runs on and however long
# its last turn ended ago. Clearing the wait makes it retire as any other.
sj_row mc-alpha-worker-sjparked "$t1" "$t1" "Done: walked the spec."
printf 'waiting\toperator\n' >>"$sessions/mc-alpha-worker-sjparked"
sj_row mc-alpha-worker-sjci "$t1" "$t1" "Done."
printf 'waiting\tci\n' >>"$sessions/mc-alpha-worker-sjci"
bound_row mc-alpha-worker-tmuxparked worker 34 "$t1" "$tmp/idle.pane"
printf 'waiting\tready-flip\n' >>"$sessions/mc-alpha-worker-tmuxparked"
printf '%s:t\th\t%s\tidle\n' "$t1" "$t1" >"$fleet/mission-control/alpha/stall/mc-alpha-worker-tmuxparked"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now "$t2" 2>"$tmp/stderr")
expect_no_out "a completed stream-json session with an operator wait is never retired" "retire${tab}mc-alpha-worker-sjparked"
expect_no_out "nor one with a ci wait" "retire${tab}mc-alpha-worker-sjci"
expect_no_out "nor an idle tmux session with a ready-flip wait" "retire${tab}mc-alpha-worker-tmuxparked"
awk -F '\t' '$1 != "waiting"' "$sessions/mc-alpha-worker-sjci" >"$sessions/mc-alpha-worker-sjci.new" && mv -f "$sessions/mc-alpha-worker-sjci.new" "$sessions/mc-alpha-worker-sjci"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now "$t2" 2>"$tmp/stderr")
expect_out "clearing the wait restores the retire" "retire${tab}mc-alpha-worker-sjci${tab}${t1}${tab}completed result=success"
rm -f "$sessions/mc-alpha-worker-sjci" && rm -rf "$fleet/streamjson/mc-alpha-worker-sjci"
bound_row mc-alpha-worker-tmuxfree worker 35 "$t1" "$tmp/idle.pane"
printf '%s:t\th\t%s\tidle\n' "$t1" "$t1" >"$fleet/mission-control/alpha/stall/mc-alpha-worker-tmuxfree"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now "$t2" 2>"$tmp/stderr")
expect_out "an idle tmux session with no wait retires, so the parked one's stay is the wait's doing" "retire${tab}mc-alpha-worker-tmuxfree${tab}${t1}${tab}idle"
rm -f "$sessions/mc-alpha-worker-tmuxfree" "$tmp/tmux/35.name"

# A landed unit ends its session's wait: the landing sweep retires a session
# whose row still records a ci wait, rather than holding it as parked.
sj_row mc-alpha-worker-sjlanded "$t1" "$t1" "Waiting on CI."
printf 'waiting\tci\n' >>"$sessions/mc-alpha-worker-sjlanded"
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-sjlanded --repo acme/web --pr 7
echo MERGED >"$tmp/state7"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_out "a landed session with a stale wait is retired by the landing sweep" "retired${tab}mc-alpha-worker-sjlanded"
expect_no_out "and is not held as parked" "held${tab}mc-alpha-worker-sjlanded"
if [ ! -e "$sessions/mc-alpha-worker-sjlanded" ]; then ok "and its row released"; else fail "the landed parked session's row stayed: $OUT $ERR"; fi
rm -rf "$fleet/streamjson/mc-alpha-worker-sjlanded"
for s in mc-alpha-worker-sjunread mc-alpha-worker-sjrunning mc-alpha-worker-tmuxgrace; do rm -f "$sessions/$s" && rm -rf "$fleet/streamjson/$s"; done

# The bounds are knobs.
cp "$tracked" "$tmp/tracked.keep"
printf 'mission_control_worker_idle: 1m\nmission_control_worker_lifetime: 30m\n' >>"$tracked"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 1801)) 2>/dev/null)
expect_out "a shorter idle knob retires sooner" "retire${tab}mc-alpha-worker-idle${tab}${t1}${tab}idle 1801s, bound 60s"
expect_out "a shorter lifetime knob hands over sooner" "handover${tab}mc-alpha-worker-young${tab}${t1}${tab}lived 1801s, bound 1800s"
expect_no_out "a session past both bounds is retired, not asked to hand over" "handover${tab}mc-alpha-worker-idle"
cp "$tmp/tracked.keep" "$tracked"
for s in mc-alpha-worker-sjasks mc-alpha-worker-sjended mc-alpha-worker-sjstale mc-alpha-worker-sjbusy; do rm -f "$sessions/$s" && rm -rf "$fleet/streamjson/$s"; done

# watch acts: the idle session is retired through the launcher, its window
# closed and row gone; each old one's handover is announced once per launch.
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$t2" 2>"$tmp/stderr")
ERR=$(cat "$tmp/stderr")
expect_out "the idle retire is announced" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-idle"
if [ ! -e "$sessions/mc-alpha-worker-idle" ] && [ ! -e "$tmp/tmux/21.name" ]; then
  ok "the idle session is retired: its window closed and its row released"
else
  fail "the idle session was not retired: $(ls "$sessions") $ERR"
fi
expect_out "an idle stream-json session is retired too" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-sjidle"
if [ ! -e "$sessions/mc-alpha-worker-sjidle" ]; then ok "and its row released"; else fail "the stream-json session's row stayed: $ERR"; fi
expect_no_out "a parked session is not retired by the watch" "worker-retired-idle${tab}mc-alpha-worker-sjparked"
expect_no_out "nor a parked tmux session" "worker-retired-idle${tab}mc-alpha-worker-tmuxparked"
if [ -e "$sessions/mc-alpha-worker-sjparked" ] && [ -e "$sessions/mc-alpha-worker-tmuxparked" ] && [ -d "$fleet/streamjson/mc-alpha-worker-sjparked" ] && [ -e "$tmp/tmux/34.name" ]; then
  ok "and both stay, row, runtime and window"
else
  fail "a parked session was retired by the watch: $(ls "$sessions") $ERR"
fi
case $ERR in
  *"mc-alpha-worker-sjparked"* | *"mc-alpha-worker-tmuxparked"*) fail "a parked session was reported as a failed retire: $ERR" ;;
  *) ok "and the watch reports nothing of them" ;;
esac
expect_out "the lifetime handover is announced" "announced${tab}worker-handover-due${tab}mc-alpha-reviewer-old"
expect_out "each session's own" "announced${tab}worker-handover-due${tab}mc-alpha-worker-old"
expect_no_out "input since the scan stops the retire" "worker-retired-idle${tab}mc-alpha-worker-typed"
if [ -e "$sessions/mc-alpha-worker-typed" ]; then ok "and the session stays"; else fail "a session typed into was retired"; fi
if [ -e "$sessions/mc-alpha-reviewer-old" ] && [ -e "$sessions/mc-alpha-worker-kickoff" ]; then
  ok "a handover leaves the session running, and a kickoff relay stays"
else
  fail "a session that should stay was retired: $(ls "$sessions")"
fi
case $ERR in
  *"not fully retired"* | *"could not be requested"* | *"bounds lock"* | *"left for a pass"* | *"cannot be listed"*)
    fail "the happy path's bounds reported an error: $ERR"
    ;;
  *) ok "the happy path's bounds report no error" ;;
esac
mc_run mc-event.sh list --program alpha
expect_out "the retire lands in the event store" "worker-retired-idle${tab}mc-alpha-worker-idle${tab}mc-alpha-worker-idle retired: idle 1900s, bound 1800s"
expect_out "the completed worker's retire event names it and its last result" "worker-retired-idle${tab}mc-alpha-worker-sjgrace${tab}mc-alpha-worker-sjgrace retired: completed result=success 1900s ago, grace 300s"
if [ "$(printf '%s\n' "$OUT" | grep -c "worker-retired-idle${tab}mc-alpha-worker-sjgrace${tab}")" = 1 ]; then ok "and it is raised once, under the owning program"; else fail "the completed worker's event count: $OUT"; fi
expect_out "the handover names the successor launch where no handover path is installed" "worker-handover-due${tab}mc-alpha-reviewer-old${tab}mc-alpha-reviewer-old is past its lifetime (lived ${t2}s, bound 14400s); retire it and launch its successor"

# Where scripts/session-handover.sh is installed, the handover is requested
# through it, so the session hands over at its own next safe point. A
# relaunch under the name is a new launch, so it is raised again; a session
# already raised for its launch is not.
cp -R "$repo_root/scripts" "$tmp/scripts-alt"
cat >"$tmp/scripts-alt/session-handover.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$tmp/handover-requests"
printf 'requested\t%s\n' "\$3"
EOF
relaunch_row mc-alpha-reviewer-old 1
printf 'mc-alpha-worker-gone\tidle 9999s, bound 1800s\n' >"$fleet/mission-control/alpha/keeper-retired-owed"
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$tmp/scripts-alt/mc-keeper.sh" watch --now $((t2 + 60)) 2>/dev/null)
expect_out "a retire event the store refused earlier is raised" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-gone"
if [ ! -s "$fleet/mission-control/alpha/keeper-retired-owed" ]; then ok "and no longer owed"; else fail "the owed event stayed owed"; fi
expect_out "a relaunch past its lifetime is raised again, through the installed path" "announced${tab}worker-handover-due${tab}mc-alpha-reviewer-old"
expect_no_out "the handover is raised once per launch" "worker-handover-due${tab}mc-alpha-worker-old"
if grep -q "^request --session mc-alpha-reviewer-old --reason lived " "$tmp/handover-requests" 2>/dev/null \
  && ! grep -q "mc-alpha-worker-old" "$tmp/handover-requests"; then
  ok "the lifetime bound requests the session's own handover, once per launch"
else
  fail "the handover requests: $(cat "$tmp/handover-requests" 2>&1)"
fi
mc_run mc-event.sh list --program alpha
expect_out "the installed path's event says the session hands over itself" "mc-alpha-reviewer-old is past its lifetime (lived $((t2 + 59))s, bound 14400s); it hands over at its next safe point"

# A failed handover request is not announced, and a pass whose stall scan
# failed retires no tmux session, its samples possibly stale; a stream-json
# one is still tried, here by a launcher whose retire fails.
printf '#!/bin/sh\nexit 1\n' >"$tmp/scripts-alt/session-handover.sh"
printf '#!/bin/sh\nexit 1\n' >"$tmp/scripts-alt/mc-stall.sh"
mv "$tmp/scripts-alt/mission-control-launch.sh" "$tmp/scripts-alt/mission-control-launch.real.sh"
cat >"$tmp/scripts-alt/mission-control-launch.sh" <<'EOF'
#!/bin/bash
if [ "$1" = retire ]; then
  case $2 in
    *-sjgone)
      rm -f "$PLANWRIGHT_FLEET_STATE_DIR/mission-control/sessions/$2"
      exit 3
      ;;
    *) printf 'retire\t%s\tpartial\n' "$2" ;;
  esac
  exit 6
fi
exec /bin/bash "$(dirname "$0")/mission-control-launch.real.sh" "$@"
EOF
sj_row mc-alpha-worker-sjidle2 "$t1" "$t1" "Done."
sj_row mc-alpha-worker-sjgone "$t1" "$t1" "Done."
relaunch_row mc-alpha-reviewer-old 2
bound_row mc-alpha-worker-idle2 worker 29 "$t1" "$tmp/idle.pane"
printf '%s:t\th\t%s\tidle\n' "$t1" "$t1" >"$fleet/mission-control/alpha/stall/mc-alpha-worker-idle2"
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$tmp/scripts-alt/mc-keeper.sh" watch --now $((t2 + 120)) 2>"$tmp/stderr")
ERR=$(cat "$tmp/stderr")
expect_no_out "a failed handover request is not announced" "worker-handover-due${tab}mc-alpha-reviewer-old"
case $ERR in *"the handover of mc-alpha-reviewer-old could not be requested"*) ok "and is reported" ;; *) fail "the failed request was not reported: $ERR" ;; esac
expect_no_out "a pass whose stall scan failed retires nothing" "worker-retired-idle"
if [ -e "$sessions/mc-alpha-worker-idle2" ] && [ -e "$tmp/tmux/29.name" ]; then
  ok "the idle session waits for a pass whose scan succeeds"
else
  fail "the idle session was retired on a failed scan"
fi
case $ERR in *"mc-alpha-worker-idle2 is idle past its bound, left for a pass whose stall scan succeeds"*) ok "and says so" ;; *) fail "the skipped retire was not reported: $ERR" ;; esac
case $ERR in *"the idle session mc-alpha-worker-sjidle2 was not fully retired: retire"*) ok "a stream-json retire is still tried, and its failure reported" ;; *) fail "the stream-json retire on a failed scan: $ERR" ;; esac
case $ERR in *mc-alpha-worker-sjgone*) fail "a session retired meanwhile was reported: $ERR" ;; *) ok "a session retired meanwhile is not a failed retire" ;; esac
if [ ! -e "$sessions/mc-alpha-worker-sjgone" ]; then ok "(its retire was reached)"; else fail "the gone-meanwhile retire was never reached"; fi

kill "$bound_pid" 2>/dev/null
rm -rf "$tmp/scripts-alt"
for s in mc-alpha-reviewer-old mc-alpha-worker-young mc-alpha-worker-asks mc-alpha-tower-old mc-alpha-worker-old \
  mc-alpha-worker-kickoff mc-alpha-worker-again mc-alpha-worker-idle2 mc-beta-worker-idle mc-alpha-worker-sjidle2 \
  mc-alpha-worker-sjgone mc-alpha-worker-typed; do
  rm -f "$sessions/$s" && rm -rf "$fleet/streamjson/$s"
done

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-bounds: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-bounds: all passed"
