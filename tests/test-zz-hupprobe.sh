#!/bin/bash
# TEMPORARY diagnostic probe, never merged: run the shard-2 suspects in a
# process group of their own beside a sentinel that logs every signal the
# group receives.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if [ -z "${PROBE_INNER:-}" ]; then
  export PROBE_INNER=1
  exec perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' -- /bin/bash "$0" "$@"
fi
log=$(mktemp -d)
trap 'echo "PROBE-GOT-HUP at run ${i:-?}"' HUP
trap 'echo "PROBE-GOT-TERM at run ${i:-?}"' TERM
bash -c '
  for s in HUP INT TERM QUIT USR1 USR2; do trap "echo got-$s >>\"$1/sentinel\"" $s; done
  while :; do sleep 0.2; done' sentinel "$log" &
sent=$!
echo "probe pid $$ pgid $(ps -o pgid= -p $$) sentinel $sent pgid $(ps -o pgid= -p $sent) sh=$(ls -l /bin/sh /private/var/select/sh 2>&1 | tr '\n' ' ')"
runs=${PROBE_RUNS:-6}
i=1
while [ "$i" -le "$runs" ]; do
  for t in test-detached-run.sh test-fleet-streamjson-pid-identity.sh test-behavioral-eval-mission-control.sh; do
    /bin/bash "$here/$t" >"$log/$t.$i.out" 2>&1 &
  done
  wait_pids=$(jobs -p | grep -vx "$sent")
  for p in $wait_pids; do wait "$p"; echo "run $i pid $p rc=$?"; done
  if [ -s "$log/sentinel" ]; then
    echo "SIGNAL after run $i: $(tr '\n' ' ' <"$log/sentinel")"
    : >"$log/sentinel"
  fi
  i=$((i + 1))
done
kill -KILL "$sent"
echo "probe done"
