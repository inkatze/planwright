#!/bin/bash
# A quoted mkdir mode is still a restrictive mode.
tmp=$(mktemp -d)
mkdir -m "000" "$tmp/locked"
run_guard "$tmp/locked"
assert_exit "an unlistable input is refused" 2 "$?"
chmod 755 "$tmp/locked"
