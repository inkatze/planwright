#!/bin/bash
# The conforming twin: the library clears the variable before the read.
here=${BASH_SOURCE[0]%/*}
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
root=${PLANWRIGHT_ROOT:-$(pwd)}
/bin/sh "$root/scripts/resolve-root.sh" spec
