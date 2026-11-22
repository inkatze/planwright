#!/bin/bash
# Tests for scripts/mc-keeper.sh's routing of a stream-json worker the
# launcher holds no row for: by the owner its dispatch record keeps, and raised
# once as unowned when no owner can be told; a program never escalates to
# itself.
#
# Companions: the other tests/test-mc-keeper*.sh suites; all but
# test-mc-keeper-rowless.sh share tests/lib/mc-keeper-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-unowned.sh
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-keeper-fixture.sh
. "$here/lib/mc-keeper-fixture.sh" || exit 1

mc_row alpha live
mc_row beta live

# A worker with no launcher row is routed by the owner its dispatch record
# keeps (mission-control:<program>), so only that program announces it; one
# whose owner cannot be told is raised once, as unowned, never to every program.
pp_req rl-beta mission-control:beta
keeper_as alpha 5000
expect_no_out "a row-less worker its record gives to another program is not announced here" "rl-beta"
pp_req rl-alpha
keeper_as alpha 5000
expect_out "a row-less worker its record gives to this program is announced" "announced${tab}pending-prompt-overdue${tab}rl-alpha"
pp_req rl-orphan none
keeper_as alpha 5000
expect_out "a worker no row or record owns is raised once, as unowned" "announced${tab}stream-json-worker-unowned${tab}rl-orphan"
expect_no_out "and its prompt is not announced as the program's own" "pending-prompt-overdue${tab}rl-orphan"
keeper_as alpha 5060
expect_no_out "and the unowned event is not raised again" "stream-json-worker-unowned"
if [ -e "$fleet/streamjson/rl-orphan/unowned-announced.aaaa1111-bbbb-cccc-dddd-eeee00000001" ]; then
  ok "the raise is claimed in the worker's directory, for every keeper to see"
else
  fail "the unowned raise left no claim in the worker's directory"
fi
keeper_as beta 5120
expect_no_out "nor raised under a second program" "rl-orphan"
mc_run mc-event.sh list --program alpha
expect_out "with no hub program configured, it falls back to the finding program" "rl-orphan"
pp_req rl-fresh-orphan none
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000002\tpermission\t5190\tpending\n' >"$fleet/streamjson/rl-fresh-orphan/journal"
keeper_as alpha 5200
expect_out "a request that has just arrived on a worker no one owns is raised as unowned too" "announced${tab}stream-json-worker-unowned${tab}rl-fresh-orphan"
pp_req rl-gone mission-control:removedprog
keeper_as alpha 5260
expect_out "a worker whose record names a program no longer configured is raised as unowned" "announced${tab}stream-json-worker-unowned${tab}rl-gone"
# A program never escalates to itself: with no hub, the request of a worker
# whose own mission control is dead is raised by another program's keeper.
mc_row beta dead
pp_req rl-self mission-control:beta
keeper_as beta 5270
expect_no_out "the dead program's own keeper does not raise its worker to itself" "stream-json-worker-unowned${tab}rl-self"
keeper_as alpha 5280
expect_out "another program's keeper raises it" "announced${tab}stream-json-worker-unowned${tab}rl-self"
mc_run mc-event.sh list --program beta
expect_no_out "and nothing is raised into the dead program's own queue" "stream-json-worker-unowned${tab}rl-self"
mc_row beta live
rm -rf "$fleet/streamjson/rl-beta" "$fleet/streamjson/rl-alpha" "$fleet/streamjson/rl-orphan" "$fleet/streamjson/rl-fresh-orphan" "$fleet/streamjson/rl-gone" "$fleet/streamjson/rl-self" "$fleet/dispatch-markers"
rm -f "$fleet/mission-control/alpha/keeper-prompts" "$fleet/mission-control/alpha/keeper-unowned"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-unowned: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-unowned: all passed"
