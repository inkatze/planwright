#!/bin/bash
# Tests for scripts/mc-keeper.sh's orphan sweep: a stream-json supervisor a
# killed suite left behind, and a holder init adopted, raised once each after a
# minute listed, under one program, and never signalled.
#
# Companions: the other tests/test-mc-keeper*.sh suites; all but
# test-mc-keeper-rowless.sh share tests/lib/mc-keeper-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-orphans.sh
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-keeper-fixture.sh
. "$here/lib/mc-keeper-fixture.sh" || exit 1

mc_row alpha live
mc_row beta live

# A stream-json supervisor a killed suite left behind, its state directory
# and working directory removed with the suite's scratch tree, is raised once
# it has been listed for a minute, under one program only, and never
# signalled. The stand-in ends itself once this suite is gone. These passes
# read the real process table, which every other case leaves empty.
keeper_live() { # keeper_live <program> <now>
  OUT=$(cd "$repo" && mc_env env -u PLANWRIGHT_MC_PROC_ROOT PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM="$1" \
    /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$2" 2>/dev/null)
}
mkdir -p "$tmp/orphan-fx/scripts" "$tmp/orphan-fx/gone/state" "$tmp/orphan-fx/gone/cwd"
cat >"$tmp/orphan-fx/scripts/fleet-streamjson.sh" <<'EOF'
#!/bin/sh
while kill -0 "$FIXTURE_OWNER" 2>/dev/null; do sleep 1; done
EOF
(cd "$tmp/orphan-fx/gone/cwd" && FIXTURE_OWNER=$$ exec /bin/sh "$tmp/orphan-fx/scripts/fleet-streamjson.sh" \
  _supervise mc-alpha-tower-orphaned "$tmp/orphan-fx/gone/state" init) &
orphan_sup=$!
os_i=0
while [ "$os_i" -lt 100 ]; do
  if [ -r "/proc/$orphan_sup/cmdline" ]; then
    os_args=$(tr '\000' ' ' <"/proc/$orphan_sup/cmdline")
  else
    os_args=$(ps -ww -o args= -p "$orphan_sup" 2>&1)
  fi
  case $os_args in *_supervise*) break ;; esac
  sleep 0.1
  os_i=$((os_i + 1))
done
[ "$os_i" -lt 100 ] || fail "the orphan stand-in never ran its supervise argv"
rm -rf "$tmp/orphan-fx/gone"
keeper_live alpha 5300
expect_no_out "an orphan one pass has seen is not raised yet" "mc-alpha-tower-orphaned"
keeper_live beta 5330
expect_no_out "nor by another program's keeper a moment later, before it has settled" "mc-alpha-tower-orphaned"
keeper_live alpha 5360
expect_out "an orphan the next pass sees too is raised" "announced${tab}stream-json-worker-orphaned${tab}mc-alpha-tower-orphaned"
keeper_live beta 5420
expect_no_out "and not again, by any program's keeper" "mc-alpha-tower-orphaned"
keeper_live alpha 5480
expect_no_out "nor by its own" "mc-alpha-tower-orphaned"
mc_run mc-event.sh list --program alpha
expect_out "the event names the process and its gone state directory" "stream-json-worker-orphaned${tab}mc-alpha-tower-orphaned${tab}orphaned stream-json supervisor pid $orphan_sup"
expect_out "the event's reason names the gone state directory" "its state directory $tmp/orphan-fx/gone/state is gone"
# The start it asks the operator to confirm is read the way the listing read it.
if [ -r /proc/self/stat ]; then
  orphan_tick=$(awk '{ sub(/.*\) /, ""); print $20 }' "/proc/$orphan_sup/stat")
  expect_out "the event says where procfs keeps the start it names" "field 22 of /proc/$orphan_sup/stat still reads $orphan_tick"
  expect_out "and where to read what it runs, with no ps flag busybox lacks" "/proc/$orphan_sup/cmdline shows it abandoned"
else
  expect_out "the event says how ps shows the start it names" "ps -o pid,lstart,args -p $orphan_sup shows it started"
fi
mc_run mc-event.sh list --program beta
expect_no_out "and lands under one program" "mc-alpha-tower-orphaned"
if kill -0 "$orphan_sup" 2>/dev/null; then
  ok "the keeper never signals an orphan"
else
  fail "the orphaned stand-in $orphan_sup is gone after the keeper's passes"
fi
kill "$orphan_sup" 2>/dev/null
wait "$orphan_sup" 2>/dev/null
orphan_sup=''

# A holder init adopted (tail -f /dev/null) is raised the same way once it has
# been listed for a minute, worded as a held-open process and not as a
# stream-json session; one whose parent still runs is not.
hold_proc="$tmp/hold-proc"
mkdir -p "$hold_proc/5101" "$hold_proc/5102" "$hold_proc/5103"
printf 'tail\000-f\000/dev/null\000' >"$hold_proc/5101/cmdline"
printf 'tail\000-f\000/dev/null\000' >"$hold_proc/5102/cmdline"
printf '5101 (tail) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 888\n' >"$hold_proc/5101/stat"
printf '5102 (tail) S 5103 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 889\n' >"$hold_proc/5102/stat"
printf 'bash\n' >"$hold_proc/5103/comm"
keeper_hold() { # keeper_hold <now>
  OUT=$(cd "$repo" && mc_env env PLANWRIGHT_MC_PROC_ROOT="$hold_proc" PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha \
    /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$1" 2>/dev/null)
}
keeper_hold 5600
expect_no_out "a holder one pass has seen is not raised yet" "held-open"
keeper_hold 5670
expect_out "a holder the next pass sees a minute on is raised" "announced${tab}stream-json-worker-orphaned"
mc_run mc-event.sh list --program alpha
expect_out "the event words it as a held-open process" "orphaned held-open process pid 5101, which nothing reaps or stops"
expect_no_out "and never as a session someone started by hand" "pid 5101 (-)"
expect_no_out "a holder whose parent runs is not raised" "pid 5102"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-orphans: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-orphans: all passed"
