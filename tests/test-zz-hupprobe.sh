#!/bin/bash
# TEMPORARY diagnostic probe, never merged: run the shard-2 suspects through
# the real runner, in a mini suite, round after round, and report any round
# whose runner ends by a signal.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if [ -z "${PROBE_INNER:-}" ]; then
  export PROBE_INNER=1
  out=$(mktemp)
  # A fresh session: the probe's group then has no member whose parent sits
  # in another group of its session, as under a launchd-started CI runner.
  perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or exit 127' -- \
    /bin/bash "$0" "$@" >"$out" 2>&1 </dev/null &
  p=$!
  wait "$p"
  echo "inner rc=$?"
  cat "$out"
  exit 0
fi
repo=$(cd "$here/.." && pwd)
work=$(mktemp -d)
mk_suite() {
  rm -rf "$work/r"
  mkdir -p "$work/r/tests"
  ln -s "$repo/scripts" "$work/r/scripts"
  ln -s "$repo/config" "$work/r/config"
  for d in lib fixtures behavioral-evals; do ln -s "$repo/tests/$d" "$work/r/tests/$d"; done
  for t in "$@"; do cp "$repo/tests/$t" "$work/r/tests/$t"; done
}
round() {
  PLANWRIGHT_TEST_JOBS=3 PLANWRIGHT_TEST_SLOTS=3 PLANWRIGHT_TEST_SLOT_DIR="$work/slots" \
    PLANWRIGHT_TEST_TIMING_REPORT="$work/rep.tsv" PLANWRIGHT_TEST_DURATIONS='' \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
    /bin/bash "$repo/scripts/run-tests.sh" "$work/r/tests" >"$work/round.out" 2>&1
}
echo "probe pid $$ pgid $(ps -o pgid= -p $$) sess-leader? $(ps -o sess= -p $$ 2>&1)"
for mode in pid mix; do
  case $mode in
    pid) set -- test-fleet-streamjson-pid-identity.sh ;;
    mix) set -- test-fleet-streamjson-pid-identity.sh test-detached-run.sh test-behavioral-eval-mission-control.sh ;;
  esac
  mk_suite "$@"
  runs=${PROBE_RUNS:-8}
  bad=0
  i=1
  while [ "$i" -le "$runs" ]; do
    round
    rc=$?
    if [ "$rc" -ne 0 ]; then
      bad=$((bad + 1))
      echo "round $i: runner rc=$rc"
      tail -n 5 "$work/round.out"
    fi
    i=$((i + 1))
  done
  echo "probe done: $bad of $runs rounds failed ($mode)"
done
