#!/bin/bash
# An exclusion with its reason recorded on the line it excludes.
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/locked"
chmod 000 "$tmp/locked" # hermetic-exempt: asserts only that chmod itself succeeds
chmod 644 "$tmp/locked"
