#!/bin/bash
# A marker with no reason excludes nothing.
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/locked"
chmod 000 "$tmp/locked" # hermetic-exempt:
chmod 644 "$tmp/locked"
