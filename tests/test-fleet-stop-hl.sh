#!/bin/bash
# The close fixture table (tests/lib/fleet-stop-table.sh) against the headless
# rung, `scripts/fleet-dispatch-headless.sh stop`. Its twin,
# tests/test-fleet-stop-sj.sh, runs the same table against the stream-json
# rung. The source audit reads both rungs' match, so it runs once, here.
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-stop-table.sh
. "$here/lib/fleet-stop-table.sh"
run_table hl
rung=''
c21_audit
echo "ok: the close fixture table passes on the headless rung (REQ-B1.1)"
