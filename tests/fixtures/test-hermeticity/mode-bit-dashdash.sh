#!/bin/bash
# An end-of-options marker before the mode does not hide it from the guard.
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/locked"
chmod -- 000 "$tmp/locked"
run_guard "$tmp/locked"
assert_exit "an unreadable input is refused" 2 "$?"
chmod 644 "$tmp/locked"
