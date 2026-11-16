#!/bin/bash
# TEMPORARY diagnostic probe, never merged: run the real shard 2/4 in a fresh
# session whose group holds one stopped process the whole time, so anything
# that orphans the group gets the runner a kernel SIGHUP (exit 129).
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
if [ -z "${PROBE_INNER:-}" ]; then
  export PROBE_INNER=1
  out=$(mktemp)
  perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or exit 127' -- \
    /bin/bash "$0" "$@" >"$out" 2>&1 </dev/null &
  wait "$!"
  echo "inner rc=$?"
  grep -v '^ok: ' "$out" | tail -n 40
  echo "last oks:"
  grep '^ok: ' "$out" | tail -n 6
  exit 0
fi
work=$(mktemp -d)
trap 'echo "PROBE: HUP reached the group"' HUP
sleep 900 &
stopped=$!
kill -STOP "$stopped"
rm -f "$repo/tests/test-zz-hupprobe.sh"
PLANWRIGHT_TEST_SLOT_DIR="$work/slots" PLANWRIGHT_TEST_TIMING_REPORT="$work/rep.tsv" \
  /bin/bash "$repo/scripts/run-tests.sh" --shard "${PROBE_SHARD:-2/4}" 2>&1
echo "runner rc=$?"
kill -CONT "$stopped"
kill "$stopped"
