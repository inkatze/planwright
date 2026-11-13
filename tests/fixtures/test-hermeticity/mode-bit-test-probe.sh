#!/bin/bash
# A conforming twin probing inline with test -w on a write-protected file.
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/ro"
chmod a-w "$tmp/ro"
if [ -w "$tmp/ro" ]; then
  printf '%s\n' "skip: read-only case: the running user writes mode 444"
else
  run_guard "$tmp/ro"
fi
chmod u+w "$tmp/ro"
