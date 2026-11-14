#!/bin/bash
# A long option before the mode does not hide it from the guard.
tmp=$(mktemp -d)
mkdir "$tmp/locked"
chmod --recursive 000 "$tmp/locked"
run_guard "$tmp/locked"
assert_exit "an unlistable input is refused" 2 "$?"
chmod 755 "$tmp/locked"
