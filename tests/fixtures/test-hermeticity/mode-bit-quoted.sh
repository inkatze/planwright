#!/bin/bash
# A quoted mode is still a restrictive mode: the guard reads through the quotes.
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/locked"
chmod "000" "$tmp/locked"
run_guard "$tmp/locked"
assert_exit "an unreadable input is refused" 2 "$?"
chmod 644 "$tmp/locked"
