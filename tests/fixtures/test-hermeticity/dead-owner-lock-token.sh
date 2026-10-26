#!/bin/bash
# The conforming twin: a holder takes the lock through the lock library and
# exits; the token it minted, not its PID, is what the case reuses.
tmp=$(mktemp -d)
sh -c '. "$1/scripts/lock-lib.sh" && pw_lock_acquire "$2" && trap - EXIT' _ "$repo" "$tmp/owner.lock" &
holder=$!
wait "$holder"
token=$(readlink "$tmp/owner.lock")
printf '%s\n' "$token" >"$tmp/token"
