#!/bin/bash
# A restrictive mode named only in a trailing comment opens nothing.
tmp=$(mktemp -d)
rm -f "$tmp/x"  # chmod 000 "$tmp/x" would lock it
run_guard "$tmp/x"
assert_exit "a missing input is refused" 2 "$?"
