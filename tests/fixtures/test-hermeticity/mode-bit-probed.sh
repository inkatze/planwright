#!/bin/bash
# The conforming twin: the denial is probed first and the case skips by name
# when the running user can still read the file.
here=${BASH_SOURCE[0]%/*}
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
tmp=$(mktemp -d)
printf 'x\n' >"$tmp/locked"
chmod 000 "$tmp/locked"
if hermetic_access_denied r "$tmp/locked"; then
  run_guard "$tmp/locked"
else
  printf '%s\n' "skip: unreadable-file case: the running user reads mode 000"
fi
chmod 644 "$tmp/locked"
