#!/bin/bash
# The conforming twin: the owner is a PID above the host's assignable range.
here=${BASH_SOURCE[0]%/*}
# shellcheck source=tests/lib/dead-owner.sh
. "$here/lib/dead-owner.sh"
tmp=$(mktemp -d)
gone=$(dead_owner_pid)
ln -s "$gone-0-1" "$tmp/owner.lock"
