#!/bin/bash
# A dead-owner fixture reusing a PID the test spawned and reaped: the host may
# already have handed it to a live process.
tmp=$(mktemp -d)
sh -c 'exit 0' &
gone=$!
wait "$gone"
ln -s "$gone-0-1" "$tmp/owner.lock"
