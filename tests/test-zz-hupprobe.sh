#!/bin/bash
# TEMPORARY diagnostic probe, never merged: hold a stopped process in the
# probe's own process group, run one suspect, and report whether the group got
# a SIGHUP (the kernel's orphaned-group rule), in a fresh session and in a
# group anchored by a parent in another group.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if [ -z "${PROBE_INNER:-}" ]; then
  export PROBE_INNER=1
  for kind in fresh anchored; do
    for t in none control test-detached-run.sh test-fleet-streamjson-pid-identity.sh test-behavioral-eval-mission-control.sh; do
      out=$(mktemp)
      if [ "$kind" = fresh ]; then
        perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or exit 127' -- \
          /bin/bash "$0" "$t" >"$out" 2>&1 </dev/null &
      else
        perl -e 'setpgrp(0, 0) or die "setpgrp: $!"; exec @ARGV or exit 127' -- \
          /bin/bash "$0" "$t" >"$out" 2>&1 </dev/null &
      fi
      wait "$!"
      echo "$kind $t: inner rc=$? $(grep -E 'GOT|rc=' "$out" | tr '\n' ' ')"
    done
  done
  exit 0
fi
t=$1
got=$(mktemp)
trap 'echo HUP >>"$got"' HUP
trap 'echo CONT >>"$got"' CONT
sleep 300 &
stopped=$!
kill -STOP "$stopped"
if [ "$t" = control ]; then
  # A process of this group with a child left here moves to a group of its
  # own, then exits: the group's last qualifying link goes with it.
  perl -e 'my $c = fork(); if (!$c) { sleep 3; exit 0 } setpgrp(0, 0); sleep 1; exit 0'
  echo "test rc=$?"
elif [ "$t" != none ]; then
  /bin/bash "$here/$t" >"$got.out" 2>&1
  echo "test rc=$?"
fi
sleep 1
kill -CONT "$stopped"
kill "$stopped"
echo "GOT: $(tr '\n' ' ' <"$got")"
