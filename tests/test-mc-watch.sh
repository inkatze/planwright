#!/bin/bash
# Tests for scripts/mc-watch.sh — the watcher runner: arming the enabled
# duties' watchers, re-arming a stopped one with the stop as an event, the
# daemon pause, the budget rungs, and no model on any runner path
# (mission-control REQ-E1.1, REQ-E1.2, REQ-E1.5, REQ-C1.5, REQ-L1.1,
# REQ-L1.2; D-4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-watch.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-watch.sh" ] || {
  echo "FAIL: scripts/mc-watch.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

# shellcheck source=tests/lib/mc-watch-fixture.sh
. "$here/lib/mc-watch-fixture.sh"

# ---------------------------------------------------------------------------
# REQ-E1.1: a pass arms every armed duty's watchers; an `off` duty arms none.
# ---------------------------------------------------------------------------
setup '[alpha-duty, beta-duty]'
mc_run mc-watch.sh pass --program alpha
expect_rc "REQ-E1.1: a pass" 0
expect_out "REQ-E1.1: the live duty's first watcher is armed" "armed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
expect_out "REQ-E1.1: its second watcher is armed" "armed${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
expect_no_out "REQ-E1.1: an off duty arms nothing" "beta-duty"
check "REQ-E1.1: an armed watcher runs" poll_until --what "the first watcher run" -- ran alpha-watch 1
check "REQ-E1.2: the watcher's declared event lands in the attention store" \
  poll_until --what "the watcher's event" -- sh -c "grep -q 'alpha-due' '$WATCH_EVENTS'/e* 2>/dev/null"
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.2: the event carries its kind, subject and text" "alpha-due${tab}pr-7${tab}seven is due"
expect_no_out "REQ-E1.2: a line that is not an event is ignored" "chatter"
watch_slot=$(slot_for alpha-watch.sh)
check "the watcher is told its duty" grep -q '^alpha-duty ' "$WATCH_RUNS/alpha-watch"

mc_run mc-watch.sh pass --program alpha
expect_out "REQ-E1.1: a second pass leaves a live watcher running" "running${tab}alpha-duty${tab}scripts/alpha-watch.sh"
expect_no_out "REQ-E1.1: nothing is re-armed while it runs" "rearmed"

check "the run's status is recorded" poll_until --what "the run record" -- test -s "$wdir/$watch_slot.last"
# A catalog edit to a live watcher's cadence restarts it on the new one.
printf '%s\n' "$(sed 's|scripts/alpha-sweep.sh@1h/medium|scripts/alpha-sweep.sh@2h/medium|' "$core/config/duties.yaml")" >"$tmp/duties.yaml"
cp "$core/config/duties.yaml" "$tmp/duties.orig"
cp "$tmp/duties.yaml" "$core/config/duties.yaml"
sweep_before=$(rec_pid "$(slot_for alpha-sweep.sh)")
mc_run mc-watch.sh pass --program alpha
expect_out "a live watcher whose cadence changed is restarted" "updated${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
if [ "$(cut -f5 "$wdir/$(slot_for alpha-sweep.sh).rec")" = 2h ]; then
  ok "on the new cadence"
else
  fail "the restarted watcher kept its old cadence"
fi
check "its old loop ends" poll_until --what "the old sweep loop's exit" -- pid_gone "$sweep_before"
cp "$tmp/duties.orig" "$core/config/duties.yaml"
mc_run mc-watch.sh pass --program alpha
mc_run mc-watch.sh status --program alpha
expect_out "REQ-L1.4: status shows each watcher with its cadence and cost" "watcher${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}5m${tab}low${tab}running"
expect_out "REQ-L1.4: and the medium-cost sweep" "watcher${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}1h${tab}medium${tab}running"
expect_out "a refused event line is counted, beside the run's exit" "${tab}0${tab}1"
printf '%s\t0\t0\n' 1000 >"$wdir/$watch_slot.last"
mc_run mc-watch.sh status --program alpha --now 1400
expect_out "REQ-L1.4: a run past its cadence shows a negative time to the next, its expiry" "${tab}400${tab}-100${tab}0${tab}0"

# ---------------------------------------------------------------------------
# REQ-E1.5, REQ-E1.1: a killed watcher is an event, then re-armed within one
# pass; the event lands before the re-armed watcher runs.
# ---------------------------------------------------------------------------
old=$(rec_pid "$watch_slot")
kill "$old"
check "the killed watcher exits" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh status --program alpha
expect_out "a killed watcher shows stopped" "scripts/alpha-watch.sh${tab}5m${tab}low${tab}stopped"
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-E1.5: the stop is reported with its event" "stopped${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}e"
expect_out "REQ-E1.1: the watcher is re-armed in the same pass" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
order=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "stopped" { s = NR } $1 == "rearmed" { r = NR } END { print (s && r && s < r) ? "ok" : "bad" }')
check "REQ-E1.5: the stop is reported before the re-arm" test "$order" = ok
mc_run mc-event.sh list --program alpha
expect_out "REQ-E1.5: a watcher-stopped event lands in the attention store" "watcher-stopped${tab}alpha-duty${tab}scripts/alpha-watch.sh stopped"
new=$(rec_pid "$watch_slot")
if [ -n "$new" ] && [ "$new" != "$old" ] && kill -0 "$new" 2>/dev/null; then
  ok "REQ-E1.1: the re-armed watcher is a live new process"
else
  fail "REQ-E1.1: no live re-armed watcher"
fi
check "REQ-E1.1: the re-armed watcher runs" poll_until --what "the re-armed watcher's run" -- ran alpha-watch 2
check "REQ-E1.5: the stop event was in the store before the re-armed watcher ran" \
  grep -q '^alpha-duty 1$' "$WATCH_RUNS/alpha-watch"

# A stop alone is routine, so a watcher that keeps dying would stay dead
# unseen: its third stop inside an hour is a watcher-failing event, once.
t_now=$(date +%s)
printf '%s\n%s\n' $((t_now - 120)) $((t_now - 60)) >"$wdir/$watch_slot.stops"
old=$(rec_pid "$watch_slot")
kill "$old"
check "the watcher killed again exits" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh pass --program alpha
expect_out "a third stop inside an hour is a failure" "failing${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}e"
mc_run mc-event.sh list --program alpha
expect_out "the failure lands in the attention store" "watcher-failing${tab}alpha-duty${tab}scripts/alpha-watch.sh stopped 3 times within 60 minutes"
old=$(rec_pid "$watch_slot")
kill "$old"
check "and once more" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh pass --program alpha
expect_out "the fourth stop is still reported" "stopped${tab}alpha-duty"
expect_no_out "but raises no second failure in the same streak" "failing${tab}"
printf '%s\n' $((t_now - 7200)) >"$wdir/$watch_slot.stops"
old=$(rec_pid "$watch_slot")
kill "$old"
check "a stop after a quiet hour" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh pass --program alpha
expect_no_out "starts a new count, raising no failure" "failing${tab}"
if [ "$(grep -c . "$wdir/$watch_slot.stops")" -eq 1 ]; then
  ok "stops older than the hour are dropped"
else
  fail "the stop record kept stops older than the hour: $(cat "$wdir/$watch_slot.stops")"
fi
check "the quiet hour closes the failure streak" test ! -f "$wdir/$watch_slot.failing"
# Stops 25 minutes apart keep exactly three inside the hour on every stop:
# an open streak still raises nothing.
t_now=$(date +%s)
printf '%s\n%s\n' $((t_now - 3000)) $((t_now - 1500)) >"$wdir/$watch_slot.stops"
printf '%s\n' $((t_now - 1500)) >"$wdir/$watch_slot.failing"
old=$(rec_pid "$watch_slot")
kill "$old"
check "a stop inside an open streak" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh pass --program alpha
expect_rc "a pass inside an open streak" 0
expect_no_out "raises no second failure while the streak stays open" "failing${tab}"
# A death seen again after a failed pass carries the same incarnation (its
# pid and armed epoch): one stop. The same pid armed at another time is a
# new incarnation, so a reused pid still counts.
rm -f "$wdir/$watch_slot.failing"
old=$(rec_pid "$watch_slot")
incarnation=$(cut -f1,2 "$wdir/$watch_slot.rec" | tr '\t' ':')
printf '%s %s\n%s %s\n' $((t_now - 120)) "$old:1" $((t_now - 60)) "$incarnation" >"$wdir/$watch_slot.stops"
kill "$old"
check "a death already counted" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh pass --program alpha
expect_rc "a pass over a death already counted" 0
expect_no_out "is not counted twice toward a failure" "failing${tab}"
# A failed alert is retried on the next pass, never lost: a copy of the
# scripts whose event writer refuses one watcher-failing.
flaky="$tmp/flaky"
cp -R "$repo_root/scripts" "$flaky"
mv "$flaky/mc-event.sh" "$flaky/mc-event-real.sh"
cat >"$flaky/mc-event.sh" <<FLAKY
#!/bin/bash
case " \$* " in
  *" watcher-failing "*) if [ -f "$flaky/refuse" ]; then rm -f "$flaky/refuse"; exit 1; fi ;;
esac
exec /bin/bash "$flaky/mc-event-real.sh" "\$@"
FLAKY
: >"$flaky/refuse"
rm -f "$wdir/$watch_slot.failing"
printf '%s\n%s\n' $((t_now - 120)) $((t_now - 60)) >"$wdir/$watch_slot.stops"
old=$(rec_pid "$watch_slot")
kill "$old"
check "a third stop whose alert is refused" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
OUT=$(mc_env /bin/bash "$flaky/mc-watch.sh" pass --program alpha 2>"$tmp/stderr")
RC=$?
expect_rc "the pass whose alert is refused fails" 1
check "and leaves the streak unraised" test ! -f "$wdir/$watch_slot.failing"
mc_run mc-event.sh list --program alpha
stopped_before=$(printf '%s\n' "$OUT" | grep -c "watcher-stopped${tab}alpha-duty")
mc_run mc-watch.sh pass --program alpha
expect_out "the next pass raises the failure" "failing${tab}alpha-duty${tab}scripts/alpha-watch.sh${tab}e"
mc_run mc-event.sh list --program alpha
stopped_after=$(printf '%s\n' "$OUT" | grep -c "watcher-stopped${tab}alpha-duty")
check "the refused pass emitted no stop event, the retry one" test "$stopped_after" -eq $((stopped_before + 1))
# A pid reused by a later loop is a new incarnation, so it still counts.
rm -f "$wdir/$watch_slot.failing"
old=$(rec_pid "$watch_slot")
printf '%s %s\n%s %s\n' $((t_now - 120)) "$old:1" $((t_now - 60)) "$old:2" >"$wdir/$watch_slot.stops"
kill "$old"
check "a stop of a reused pid" poll_until --what "the killed watcher's exit" -- pid_gone "$old"
mc_run mc-watch.sh pass --program alpha
expect_out "counts toward a failure" "failing${tab}alpha-duty"

# A process whose arguments merely end like the slot's loop is not trusted.
loop_pid=$(rec_pid "$watch_slot")
kill "$loop_pid" 2>/dev/null
check "the live loop exits" poll_until --what "the loop's exit" -- pid_gone "$loop_pid"
# shellcheck disable=SC2016 # the decoy's own script, expanded by it
/bin/bash -c 'sleep 30 & s=$!; trap "kill \$s; exit" TERM; wait' /x/mc-watch.sh loop --program alpha --slot "$watch_slot" &
decoy=$!
printf '%s\t1\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' "$decoy" >"$wdir/$watch_slot.rec"
mc_run mc-watch.sh pass --program alpha
expect_out "a decoy ending in the loop's arguments is not taken for it" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "and is left alone" kill -0 "$decoy"
kill "$decoy" 2>/dev/null
new=$(rec_pid "$watch_slot")

# A record whose pid now names some other process is not trusted as live.
printf '%s\t1\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' "$$" >"$wdir/$watch_slot.rec"
kill "$new" 2>/dev/null
mc_run mc-watch.sh pass --program alpha
expect_out "a recycled pid is not taken for the watcher" "rearmed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "the process the stale record named is left alone" kill -0 "$$"

# ---------------------------------------------------------------------------
# REQ-L1.2: the budget rungs pause watchers by cost class; the spend class.
# ---------------------------------------------------------------------------
setup '[alpha-duty, fast-duty]' 'polls_per_hour: 20'
mc_run mc-watch.sh pass --program alpha
expect_out "a high-cost watcher is armed with headroom" "armed${tab}fast-duty${tab}scripts/heavy-watch.sh"
heavy_pid=$(rec_pid "$(slot_for heavy-watch.sh)")
check "the high-cost watcher starts its child" poll_until --what "the watcher's child" -- test -s "$WATCH_RUNS/heavy-child"
seed_polls_now 17
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: pause-watchers stops the high-cost watcher" "paused${tab}fast-duty${tab}scripts/heavy-watch.sh${tab}budget rung pause-watchers"
expect_out "REQ-L1.2: it leaves the medium-cost one" "running${tab}alpha-duty${tab}scripts/alpha-sweep.sh"
check "REQ-L1.2: the paused watcher's process is stopped" poll_until --what "the paused watcher's exit" -- pid_gone "$heavy_pid"
heavy_child=$(cat "$WATCH_RUNS/heavy-child" 2>/dev/null)
if ! command -v setsid >/dev/null 2>&1; then
  ok "skipped: a stop takes a watcher's children only where setsid is available"
  [ -z "$heavy_child" ] || kill "$heavy_child" 2>/dev/null
elif [ -n "$heavy_child" ]; then
  check "a stop takes the watcher run's own children with it" poll_until --what "the watcher's child's exit" -- pid_gone "$heavy_child"
else
  fail "the high-cost watcher never recorded its child"
fi
sweep_pid=$(rec_pid "$(slot_for alpha-sweep.sh)")
mc_run mc-budget.sh record --program alpha context_steps 200
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: handover stops the medium-cost watcher too" "paused${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}budget rung handover"
expect_out "REQ-L1.2: the low-cost watcher keeps running" "running${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "REQ-L1.2: the medium-cost watcher's process is stopped" poll_until --what "the sweep's exit" -- pid_gone "$sweep_pid"
mc_run mc-budget.sh record --program alpha context_steps 0
: >"$fleet/mission-control/alpha/polls"
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: with headroom back the watcher is armed again" "armed${tab}alpha-duty${tab}scripts/alpha-sweep.sh"

setup '[alpha-duty]' 'spend_alpha_duty: low'
mc_run mc-watch.sh pass --program alpha
expect_out "REQ-L1.2: a watcher over its duty's spend class is not armed" "paused${tab}alpha-duty${tab}scripts/alpha-sweep.sh${tab}above the low spend class"
expect_out "REQ-L1.2: one within it is" "armed${tab}alpha-duty${tab}scripts/alpha-watch.sh"
check "REQ-L1.4: a pass keeps the budget file current" test -f "$fleet/mission-control/alpha/budget"

# ---------------------------------------------------------------------------
# REQ-E1.1: the runner and every live loop honour the daemon pause; a loop
# whose state is gone exits.
# ---------------------------------------------------------------------------
setup '[fast-duty]'
mc_run mc-watch.sh pass --program alpha
check "a 1s watcher runs repeatedly" poll_until --what "three fast runs" -- ran fast-watch 3
mc_run mc-event.sh list --program alpha
expect_out "an event on a last line with no newline still lands" "fast-due${tab}last-line"
fast_pid=$(rec_pid "$(slot_for fast-watch.sh)")
printf '%s\n' "fleet_daemon_pause: true" >>"$tracked"
# Let a run already past the gate finish, then hold a window: an assertion
# that nothing happens, so a fixed wait rather than a poll.
sleep 2
before=$(runs_of fast-watch)
sleep 3
if [ "$(runs_of fast-watch)" -eq "$before" ]; then
  ok "REQ-E1.1: a live watcher loop skips its runs under the pause"
else
  fail "REQ-E1.1: a watcher ran under the pause ($before then $(runs_of fast-watch) runs)"
fi
kill "$(rec_pid "$(slot_for heavy-watch.sh)")" 2>/dev/null
mc_run mc-watch.sh pass --program alpha
expect_eq "REQ-E1.1: a paused pass does nothing but say so" "paused"
mc_run mc-event.sh list --program alpha
expect_no_out "REQ-E1.1: no event is emitted under the pause" "watcher-stopped"
rm -rf "$wdir"
check "a loop whose state directory is gone exits" poll_until --what "the orphaned loop's exit" -- pid_gone "$fast_pid"

# A loop that exits between the procfs readability test and the read is not
# ours, and says nothing on stderr. The race cannot be timed, so the script's
# own read runs against a cmdline that cannot be opened.
read_line=$(awk 'index($0, "<\"/proc/$1/cmdline\"") { print; if (!/\{$/) exit; p = 1; next } p { print } p && /^    }$/ { exit }' "$repo_root/scripts/mc-watch.sh")
if [ -z "$read_line" ]; then
  fail "the procfs cmdline read is not found in mc-watch.sh"
else
  vanished="$tmp/vanished-pid/cmdline"
  read_line=${read_line//\/proc\/\$1\/cmdline/$vanished}
  true &
  vanished_pid=$!
  wait "$vanished_pid"
  read_err=$(/bin/bash -c "f() { $read_line; return 0; }; f $vanished_pid" 2>&1)
  read_rc=$?
  if [ "$read_rc" -eq 1 ] && [ -z "$read_err" ]; then
    ok "a vanished pid's unreadable cmdline reads as not ours, silently"
  else
    fail "a vanished pid's cmdline read: rc $read_rc, stderr '$read_err'"
  fi
fi

# ---------------------------------------------------------------------------
# REQ-C1.5: no runner, relay, snapshot or budget path calls a model. The gate
# is checked against one seeded file per spelling first, so it can fail.
# ---------------------------------------------------------------------------
no_model() { # no_model <file...>: the code lines that would start a model
  # CLAUDE_DIR names the config directory, not a model; it is dropped before
  # matching so the rest of its line is still checked.
  for nm_f in "$@"; do
    sed 's/\$[{]\{0,1\}CLAUDE_DIR//g' "$nm_f" \
      | grep -nE '(^|[^A-Za-z0-9_.-])"?(/[A-Za-z0-9_./-]*/)?(claude|gemini|codex)"?([[:space:]]|$)|\$\{?[A-Z_]*(CLAUDE|MODEL|LLM)[A-Z_]*|offload-dispatch|mission-control-launch|fleet-[a-z-]*\.sh"?[[:space:]]+launch|anthropic' \
      | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$nm_f:|"
  done
}
# shellcheck disable=SC2016 # the seeds are source text, never expanded
for seeded in 'claude -p "summarize"' '"claude" -p x' '/usr/local/bin/claude -p x' \
  'gemini -p x' 'codex exec x' '${CLAUDE_BIN:-claude} -p x' \
  'cat "$CLAUDE_DIR/x"; claude -p x' \
  '/bin/sh "$d/fleet-streamjson.sh" launch w s' 'fleet-tmux.sh launch w'; do
  printf '#!/bin/sh\n# claude is only named here\n%s\n' "$seeded" >"$tmp/seeded.sh"
  if [ -n "$(no_model "$tmp/seeded.sh")" ]; then
    ok "REQ-C1.5: the gate catches: $seeded"
  else
    fail "REQ-C1.5: the gate misses: $seeded"
  fi
done
# shellcheck disable=SC2016 # source text, never expanded
printf '%s\n' 'r=${CLAUDE_DIR:-$HOME/.claude}/plugins/x.json' >"$tmp/seeded.sh"
if [ -z "$(no_model "$tmp/seeded.sh")" ]; then
  ok "REQ-C1.5: a config-directory read is not a model call"
else
  fail "REQ-C1.5: the gate flags a config-directory read"
fi
found=$(no_model "$repo_root"/scripts/mc-watch.sh "$repo_root"/scripts/mc-wake.sh \
  "$repo_root"/scripts/mc-event.sh "$repo_root"/scripts/mc-snapshot.sh \
  "$repo_root"/scripts/mc-adapter-forge.sh "$repo_root"/scripts/mc-budget.sh \
  "$repo_root"/scripts/mc-lib.sh "$repo_root"/scripts/mc-duties.sh "$repo_root"/scripts/mc-program.sh)
if [ -z "$found" ]; then
  ok "REQ-C1.5: no runner step calls a model"
else
  fail "REQ-C1.5: a runner path names a model call: $found"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-watch: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-watch: all passed"
