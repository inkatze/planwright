#!/bin/bash
# The close fixture table (tests/lib/fleet-stop-table.sh) against the
# stream-json rung, `scripts/fleet-streamjson.sh stop`. Its twin,
# tests/test-fleet-stop-hl.sh, runs the same table against the headless rung.
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-stop-table.sh
. "$here/lib/fleet-stop-table.sh"
run_table sj
echo "ok: the close fixture table passes on the stream-json rung (REQ-B1.1)"
