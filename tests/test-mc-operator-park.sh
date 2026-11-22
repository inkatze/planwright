#!/bin/bash
# Tests for the operator-park alarm: a stream-json worker parked on the
# operator (mission-control-launch.sh wait <name> --on operator, its turn
# ended) past mission_control_worker_completed_grace is raised to its own
# mission control once per park by the session-keeper's watch
# (scripts/mc-keeper.sh), the event ending with the first lines of its last
# result; one its mission control leaves parked a further
# mission_control_escalation_window goes to the hub through the escalation
# watcher (scripts/mc-escalate.sh), as an unanswered request does. Waits on
# CI or a ready flip, and a worker mid-turn, raise nothing.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-operator-park.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset PLANWRIGHT_STREAMJSON_PENDING_AGE

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-operator-park.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required (the fixture writes the workers' event logs with it)" >&2
  exit 1
}

tab=$(printf '\t')
reset_mc_fixture
write_programs() { # write_programs [<extra line>...]
  {
    printf 'mission_control_programs: [alpha, beta, hub]\n'
    for p in alpha beta hub; do
      printf 'program_%s_repositories: [%s]\n' "$p" "$repo"
      printf 'program_%s_spec_root: %s/specs\n' "$p" "$repo"
      printf 'program_%s_home: %s/mchome-%s\n' "$p" "$tmp" "$p"
    done
    printf 'notification_channel: editor-toast\n'
    for l in "$@"; do printf '%s\n' "$l"; done
  } >"$tracked"
}
write_programs

# Stubs: no forge, no tmux server, and a process table with no mission
# control in it, so neither watcher reads this host's own sessions.
real_ps=$(command -v ps)
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 1\n' >"$tmp/bin/gh"
cat >"$tmp/bin/tmux" <<'EOF'
#!/bin/sh
[ "$1" = ls ] && exit 0
exit 1
EOF
cat >"$tmp/bin/ps" <<EOF
#!/bin/sh
case "\$*" in
  '-ww -A -o pid= -o ppid= -o uid= -o args=') : ;;
  *) exec "$real_ps" "\$@" ;;
esac
EOF
chmod +x "$tmp/bin/gh" "$tmp/bin/tmux" "$tmp/bin/ps"
PATH="$tmp/bin:$PATH"
export PATH

T0=1800000000
LAUNCHED=$((T0 - 10))
reg="$fleet/mission-control/sessions"
mkdir -p "$reg"
# worker <name> <program> <wait|-> <turn ended> <final text> [<scope> [<kind>]]:
# a stream-json session launched at LAUNCHED whose last turn ended at <turn
# ended> with <final text>, its registry row recording <wait>, its pidfiles
# present.
worker() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt\npid\t1\nprogram\t%s\nowner\tmission-control:%s\nkind\t%s\nscope\t%s\nbackend\tstream-json\nhandle\t%s\nprofile\tworker\ntier\t-\nbrief\t-\nlaunched\t%s\n' \
    "$1" "$2" "$2" "${7:-worker}" "${6:-s}" "$1" "$LAUNCHED" >"$reg/$1"
  [ "$3" = - ] || printf 'waiting\t%s\n' "$3" >>"$reg/$1"
  mkdir -p "$fleet/streamjson/$1"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  turn "$1" "$4" "$5"
}
# turn <name> <ended> <final text>: the worker's next turn ends.
turn() {
  printf 'result\tsuccess\t%s\tfalse\n' "$2" >"$fleet/streamjson/$1/result"
  jq -nc --arg r "$3" '{type:"result",subtype:"success",result:$r}' >>"$fleet/streamjson/$1/events.jsonl"
}
# steer <name>: a message reaches the worker and its next turn starts.
steer() { printf '{"type":"assistant","message":"reading the answer"}\n' >>"$fleet/streamjson/$1/events.jsonl"; }
# unwait <name>: the worker's row no longer records a wait.
unwait() {
  awk -F '\t' '$1 != "waiting" && $1 != "waited"' "$reg/$1" >"$reg/$1.new" && mv -f "$reg/$1.new" "$reg/$1"
}
# aside <name> / back <name>: a steer's send sets the result record aside,
# and one that delivered nothing puts it back.
aside() { mv -f "$fleet/streamjson/$1/result" "$fleet/streamjson/$1/.result.steer"; }
back() { mv -f "$fleet/streamjson/$1/.result.steer" "$fleet/streamjson/$1/result"; }

watch() { # watch <now>: one session-keeper watch pass for alpha
  mc_run mc-keeper.sh watch --program alpha --now "$1"
}
esc() { mc_run mc-escalate.sh scan --program alpha --now "$1"; }
events_of() { mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program "$1" 2>/dev/null; }
count_of() { printf '%s\n' "$1" | grep -c -F -- "$2"; }
seen="$fleet/mission-control/alpha/keeper-parks"
sent="$fleet/mission-control/alpha/escalate/sent"

rlo=$(printf '\342\200\256')
worker mc-alpha-worker-parked alpha operator "$T0" "Two decisions are yours before I go on:
1. Keep the old flag, or drop it? $(printf '%0200d' 0)
2. Ship the shim now?
The details follow below.
More detail nobody needs in the event."
worker mc-alpha-worker-running alpha - "$T0" "Done with the first half."
steer mc-alpha-worker-running
worker mc-alpha-worker-steered alpha operator "$T0" "Which branch should I base on?"
steer mc-alpha-worker-steered
worker mc-alpha-worker-onci alpha ci "$T0" "Waiting on CI."
worker mc-alpha-worker-onflip alpha ready-flip "$T0" "Waiting on the ready flip."
worker mc-alpha-worker-young alpha operator $((T0 + 200)) "Which of the two${rlo}readings?"
worker mc-alpha-worker-kickoff alpha operator "$T0" "Does section two read right?" kickoff-demo
worker mc-alpha-tower-parked alpha operator "$T0" "A tower talks to the operator itself." s tower
worker mc-beta-worker-parked beta operator "$T0" "Beta needs a call."
worker mc-alpha-worker-gone alpha operator "$T0" "Nobody can answer this."
rm -f "$fleet/streamjson/mc-alpha-worker-gone/supervisor.pid" "$fleet/streamjson/mc-alpha-worker-gone/worker.pid"
worker mc-alpha-worker-late alpha operator $((T0 - 5)) "Done, then parked later."
printf 'waited\t%s\n' $((T0 + 200)) >>"$reg/mc-alpha-worker-late"
worker mc-alpha-worker-stale alpha operator $((LAUNCHED - 100)) "A turn of an earlier launch."

# ---------------------------------------------------------------------------
# The owner hears a park past the alarm, once, naming the worker and ending
# with its last result's first lines.
# ---------------------------------------------------------------------------
watch $((T0 + 400))
expect_out "a worker parked on the operator past the alarm is raised" "announced${tab}worker-parked-on-operator${tab}mc-alpha-worker-parked"
case $ERR in
  *"operator-parks sweep failed"*) fail "the park sweep failed: $ERR" ;;
  *) ok "the park sweep runs clean" ;;
esac
line=$(events_of alpha | grep -F "worker-parked-on-operator${tab}mc-alpha-worker-parked${tab}")
case $line in
  *"worker mc-alpha-worker-parked has been parked on the operator 400s"*) ok "the event names the worker and how long it has waited" ;;
  *) fail "the park event's text: '$line'" ;;
esac
case $line in
  *"fleet-streamjson.sh steer mc-alpha-worker-parked --message-file <file>. Its last result"*) ok "what to do comes before the worker's words, so a long result never cuts it" ;;
  *) fail "the park event lost what to do: '$line'" ;;
esac
case $line in
  *"in its own words, begins: Two decisions are yours before I go on: / 1. Keep the old flag, or drop it? 000"*) ok "and it ends with its last result's first lines" ;;
  *) fail "the park event does not quote the result's first lines: '$line'" ;;
esac
case $line in
  *"More detail nobody needs"*) fail "the park event quotes the whole result: '$line'" ;;
  *) ok "but not the whole result" ;;
esac
expect_no_out "a running worker raises nothing" "mc-alpha-worker-running"
expect_no_out "nor one parked on the operator whose next turn has started" "mc-alpha-worker-steered"
expect_no_out "a wait on CI raises nothing" "mc-alpha-worker-onci"
expect_no_out "nor a wait on a ready flip" "mc-alpha-worker-onflip"
expect_no_out "a park inside the alarm is not raised yet" "mc-alpha-worker-young"
expect_no_out "a kickoff relay, parked on the operator by design, is not raised" "mc-alpha-worker-kickoff"
expect_no_out "nor a tower, which the bounds do not hold either" "mc-alpha-tower-parked"
expect_no_out "another program's worker is its own program's" "mc-beta-worker-parked"
expect_no_out "a worker with no pidfile left is not raised" "mc-alpha-worker-gone"
expect_no_out "a wait set after the turn ended counts from the wait" "mc-alpha-worker-late"
expect_no_out "a result from before this launch is no park" "mc-alpha-worker-stale"
if awk -F '\t' '$1 == "worker-parked-on-operator" && $2 == "decision" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv"; then
  ok "the park event is a decision the operator owes"
else
  fail "config/mc-event-classes.tsv has no decision row for worker-parked-on-operator"
fi

# A steer's send sets the result aside for a moment: the park keeps its
# record, so it is not raised again once the result is back.
aside mc-alpha-worker-parked
watch $((T0 + 460))
expect_no_out "a park whose result is set aside is not raised" "mc-alpha-worker-parked"
if grep -q "^mc-alpha-worker-parked${tab}${T0}\$" "$seen"; then ok "and keeps its record"; else fail "the park's record went while its result was aside: $(cat "$seen" 2>/dev/null)"; fi
back mc-alpha-worker-parked
watch $((T0 + 520))
expect_no_out "the same park is not raised again on a later tick" "worker-parked-on-operator${tab}mc-alpha-worker-parked"
if [ "$(count_of "$(events_of alpha)" "worker-parked-on-operator${tab}mc-alpha-worker-parked${tab}")" = 1 ]; then
  ok "one event across repeated ticks"
else
  fail "the park's events after three ticks: $(events_of alpha)"
fi
expect_out "the young park, now past the alarm, is raised on its own" "announced${tab}worker-parked-on-operator${tab}mc-alpha-worker-young"
expect_out "the wait set late is raised once the alarm has passed since the wait" "announced${tab}worker-parked-on-operator${tab}mc-alpha-worker-late"
ev=$(events_of alpha)
case $(printf '%s\n' "$ev" | grep -F "worker-parked-on-operator${tab}mc-alpha-worker-late${tab}") in
  *"parked on the operator 320s"*) ok "its age counts from the wait" ;;
  *) fail "the late wait's event: $ev" ;;
esac
young=$(printf '%s\n' "$ev" | grep -F "worker-parked-on-operator${tab}mc-alpha-worker-young${tab}")
case $young in
  *"$rlo"*) fail "a direction override reached the event: '$young'" ;;
  *"Which of the tworeadings?"*) ok "a direction override in the worker's words is dropped" ;;
  *) fail "the young park's event: '$young'" ;;
esac

# A worker that unparks and parks again later raises again. Its unparked
# turn ends inside the completed grace, so the bounds leave it running.
steer mc-alpha-worker-parked
unwait mc-alpha-worker-parked
turn mc-alpha-worker-parked $((T0 + 650)) "Unparked: working on the flag."
watch $((T0 + 700))
expect_no_out "a worker whose wait is cleared raises nothing" "mc-alpha-worker-parked"
steer mc-alpha-worker-parked
printf 'waiting\toperator\nwaited\t%s\n' $((T0 + 790)) >>"$reg/mc-alpha-worker-parked"
turn mc-alpha-worker-parked $((T0 + 800)) "Still need the flag call."
watch $((T0 + 1200))
expect_out "a second park of the same worker is raised again" "announced${tab}worker-parked-on-operator${tab}mc-alpha-worker-parked"
if events_of alpha | grep -F "worker-parked-on-operator${tab}mc-alpha-worker-parked${tab}" | grep -q -F "Still need the flag call."; then
  ok "ending with the new park's result"
else
  fail "the second park's event: $(events_of alpha)"
fi

# ---------------------------------------------------------------------------
# Left parked a window past the alarm, the park goes to the hub, once; a
# steer restarts the clock; two windows reach the operator.
# ---------------------------------------------------------------------------
mkdir -p "$fleet/mission-control/hub"
printf 'format\t1\nsession\tmc-hub-attended-0000aaaa\nkind\tattended\nsince\t1\ngeneration\t1\n' >"$fleet/mission-control/hub/holder"
hub_count() { count_of "$(events_of hub)" "mission-control-escalated${tab}mc-alpha-worker-parked${tab}"; }
P1=$((T0 + 800))
esc $((P1 + 1000))
expect_rc "an escalation scan with a park inside the window" 0
expect_out "the park is reported at the owner level" "park${tab}mc-alpha-worker-parked${tab}1000${tab}owner"
expect_no_out "a wait on CI is no park" "mc-alpha-worker-onci"
expect_no_out "nor a wait on a ready flip" "mc-alpha-worker-onflip"
expect_no_out "nor a worker whose next turn has started" "mc-alpha-worker-steered"
expect_no_out "nor a kickoff relay" "mc-alpha-worker-kickoff"
expect_no_out "nor a tower" "mc-alpha-tower-parked"
expect_no_out "nor a turn of an earlier launch" "mc-alpha-worker-stale"
if [ "$(hub_count)" = 0 ]; then ok "the park inside the window does not reach the hub"; else fail "the hub heard early: $(events_of hub)"; fi
expect_out "while the young park, a window past the alarm, does" "escalated${tab}hub${tab}mc-alpha-worker-young"
esc $((P1 + 1300))
expect_out "an unacted park past the escalation alarm goes to the hub" "escalated${tab}hub${tab}mc-alpha-worker-parked"
if events_of hub | grep -F "mission-control-escalated${tab}mc-alpha-worker-parked${tab}" | grep -q -F "parked on the operator"; then
  ok "the hub's event says the worker is parked on the operator"
else
  fail "the hub's events: $(events_of hub)"
fi

# What a pass cannot read keeps what it raised: a result set aside, an
# unreadable launcher list, a park alarm that does not parse.
aside mc-alpha-worker-parked
esc $((P1 + 1350))
expect_no_out "a park whose result is set aside is not reported" "park${tab}mc-alpha-worker-parked"
if grep -q "^park${tab}mc-alpha-worker-parked${tab}${P1}${tab}hub\$" "$sent"; then ok "and keeps its escalation record"; else fail "the sent record after a result set aside: $(cat "$sent" 2>/dev/null)"; fi
back mc-alpha-worker-parked
esc $((P1 + 1400))
if [ "$(hub_count)" = 1 ]; then ok "the same park reaches the hub once"; else fail "the hub's events after a repeat scan: $(events_of hub)"; fi
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$reg/mc-alpha-worker-running"
  if hermetic_access_denied r "$reg/mc-alpha-worker-running"; then
    esc $((P1 + 1420))
    expect_rc "an unreadable launcher list fails the pass" 1
    expect_err "and says no park is raised" "no request or park is raised this pass"
    if grep -q "^park${tab}mc-alpha-worker-parked${tab}${P1}${tab}hub\$" "$sent"; then ok "the park keeps its record"; else fail "the sent record after an unread list: $(cat "$sent" 2>/dev/null)"; fi
  else
    echo "skip: an unreadable launcher list (the mode does not deny access here)"
  fi
  chmod 600 "$reg/mc-alpha-worker-running"
fi
write_programs "mission_control_worker_completed_grace: soon"
esc $((P1 + 1440))
expect_rc "a park alarm that does not parse fails the pass" 1
expect_out "while the dialog half still runs" "self${tab}"
if grep -q "^park${tab}mc-alpha-worker-parked${tab}${P1}${tab}hub\$" "$sent"; then ok "and the park keeps its record"; else fail "the sent record after a bad alarm: $(cat "$sent" 2>/dev/null)"; fi
write_programs
esc $((P1 + 1460))
if [ "$(hub_count)" = 1 ]; then ok "once it all reads again nothing is raised twice"; else fail "the hub's events after the unread passes: $(events_of hub)"; fi

steer mc-alpha-worker-parked
esc $((P1 + 1500))
expect_no_out "a steered park is no longer reported" "park${tab}mc-alpha-worker-parked"
if ! grep -q "^park${tab}mc-alpha-worker-parked${tab}" "$sent" 2>/dev/null; then
  ok "and its escalation record is pruned"
else
  fail "the sent record keeps the answered park: $(cat "$sent")"
fi
P2=$((P1 + 1600))
turn mc-alpha-worker-parked "$P2" "Still blocked on the flag."
esc $((P2 + 100))
expect_out "parked again, its clock starts over" "park${tab}mc-alpha-worker-parked${tab}100${tab}owner"
esc $((P2 + 2100))
expect_out "two windows past the alarm, the operator is pushed" "escalated${tab}operator${tab}mc-alpha-worker-parked"
if [ "$(hub_count)" = 2 ]; then ok "and the new park reaches the hub too"; else fail "the hub's events for the second park: $(events_of hub)"; fi
esc $((P2 + 2200))
if [ "$(count_of "$(cat "$fleet/attention/toasts" 2>/dev/null)" "mc-alpha-worker-parked")" = 1 ]; then
  ok "one push names the parked worker, however many scans follow"
else
  fail "toasts: $(cat "$fleet/attention/toasts" 2>/dev/null)"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-operator-park: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-operator-park: all passed"
