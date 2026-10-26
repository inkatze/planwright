#!/bin/bash
# A mode-bit fixture that asserts the refusal without probing it: under root
# the file stays readable and the assertion fails for the wrong reason.
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/locked"
chmod 000 "$tmp/locked"
run_guard "$tmp/locked"
assert_exit "an unreadable input is refused" 2 "$?"
chmod 644 "$tmp/locked"
