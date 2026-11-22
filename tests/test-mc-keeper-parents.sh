#!/bin/bash
# Tests for scripts/mc-keeper.sh's routing of a step session the launcher
# holds no row for: announced to its parent worker's program while the
# parent's own record names one, and raised as unowned when the parent cannot
# be followed.
#
# Companions: the other tests/test-mc-keeper*.sh suites; all but
# test-mc-keeper-rowless.sh share tests/lib/mc-keeper-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-parents.sh
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-keeper-fixture.sh
. "$here/lib/mc-keeper-fixture.sh" || exit 1

mc_row alpha live
mc_row beta live

# A step session launched from inside a worker names it as its parent, and is
# its parent's program's to announce while the parent's own record names one.
parent_of() { printf '%s\n' "$2" >"$fleet/streamjson/$1/parent"; }
own_worker rl-step-parent mission-control:alpha
pp_req rl-step none
parent_of rl-step rl-step-parent
keeper_as alpha 5300
expect_out "a step session is announced to its parent's program" "announced${tab}pending-prompt-overdue${tab}rl-step"
expect_no_out "and is not raised as unowned" "stream-json-worker-unowned${tab}rl-step"
keeper_as beta 5310
expect_no_out "nor by another program" "rl-step"
pp_req rl-step-ghost none
parent_of rl-step-ghost rl-step-nobody
keeper_as alpha 5320
expect_out "a parent with no row or record leaves the session unowned" "announced${tab}stream-json-worker-unowned${tab}rl-step-ghost"
own_worker rl-step-retired mission-control:alpha
rm -f "$fleet/dispatch-markers/rl-step-retired"
pp_req rl-step-late none
parent_of rl-step-late rl-step-retired
keeper_as alpha 5330
expect_out "a retired parent leaves the session unowned" "announced${tab}stream-json-worker-unowned${tab}rl-step-late"
pp_req rl-step-grand none
parent_of rl-step-grand rl-step
keeper_as alpha 5340
expect_out "a parent that is itself only a child is not followed further" "announced${tab}stream-json-worker-unowned${tab}rl-step-grand"
pp_req rl-step-self none
parent_of rl-step-self rl-step-self
keeper_as alpha 5350
expect_out "a session naming itself as parent stays unowned" "announced${tab}stream-json-worker-unowned${tab}rl-step-self"
rm -rf "$fleet/streamjson/rl-step" "$fleet/streamjson/rl-step-ghost" "$fleet/streamjson/rl-step-late" "$fleet/streamjson/rl-step-grand" "$fleet/streamjson/rl-step-self"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-parents: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-parents: all passed"
