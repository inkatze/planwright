#!/bin/bash
# The conforming twin for a pinned variable: the suite pins the fleet home
# through the library's helper, then reads it.
here=${BASH_SOURCE[0]%/*}
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
tmp=$(mktemp -d)
fleet_home_pin "$tmp/home"
mkdir -p "$PLANWRIGHT_FLEET_STATE_DIR"
