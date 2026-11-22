#!/bin/bash
# Tests for scripts/mc-keeper.sh's pending-prompt sweep at its edges: a
# pending-age setting the sweeps cannot read, a sweep that ends non-zero, and a
# prompt left pending far past the overdue bound.
#
# Companions: the other tests/test-mc-keeper*.sh suites; all but
# test-mc-keeper-rowless.sh share tests/lib/mc-keeper-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-pending-age.sh
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-keeper-fixture.sh
. "$here/lib/mc-keeper-fixture.sh" || exit 1

mc_row alpha live
mc_row beta live

# A pending-age setting the sweeps cannot read (15m, 0) used to end both
# sweeps non-zero with nothing said, so no prompt was ever announced. It is now
# named on stderr, raised once, and the shipped default stands in for it; any
# sweep that still ends non-zero is raised too.
for bad_age in 15m 0; do
  pp_req cp-badage
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE="$bad_age" /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5000 2>"$tmp/age.err")
  expect_out "a pending age of $bad_age is raised as a failed setting" "announced${tab}keeper-sweep-failed${tab}pending-age-setting"
  expect_out "and the default age still announces the overdue prompt ($bad_age)" "announced${tab}pending-prompt-overdue${tab}cp-badage"
  case $(cat "$tmp/age.err") in
    *"PLANWRIGHT_STREAMJSON_PENDING_AGE is '$bad_age'"*) ok "and says so on stderr ($bad_age)" ;;
    *) fail "a pending age of $bad_age is not named on stderr" ;;
  esac
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE="$bad_age" /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5060 2>/dev/null)
  expect_no_out "the failed setting is raised once ($bad_age)" "keeper-sweep-failed"
  rm -rf "$fleet/streamjson/cp-badage"
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5120 2>/dev/null)
done
mc_run mc-event.sh list --program alpha
expect_out "the failed setting lands in the event store" "keeper-sweep-failed${tab}pending-age-setting"
pp_req cp-failsweep
rm -f "$fleet/mission-control/alpha/keeper-prompts"
mkdir "$fleet/mission-control/alpha/keeper-prompts"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5200 2>"$tmp/sweep.err")
expect_out "a sweep that ends non-zero is raised whatever the cause" "announced${tab}keeper-sweep-failed${tab}pending-prompts"
case $(cat "$tmp/sweep.err") in
  *"the pending-prompts sweep failed"*) ok "and said on stderr" ;;
  *) fail "a failed sweep is not said on stderr" ;;
esac
rmdir "$fleet/mission-control/alpha/keeper-prompts"
rm -rf "$fleet/streamjson/cp-failsweep"

# A prompt left pending for a day (far past the overdue bound) raises the
# overdue event exactly once across passes, and that event's kind wakes the
# supervisor (class blocker, never routine).
pp_req cp-day
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 87400 2>/dev/null)
expect_out "a prompt pending a day raises the overdue event" "announced${tab}pending-prompt-overdue${tab}cp-day"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 87500 2>/dev/null)
expect_no_out "and only once while it stays pending" "pending-prompt-overdue${tab}cp-day"
mc_run mc-event.sh list --program alpha
overdue_n=$(printf '%s\n' "$OUT" | awk -F '\t' '$3 == "pending-prompt-overdue" && $4 == "cp-day" { n++ } END { print n + 0 }')
if [ "$overdue_n" = 1 ]; then
  ok "the store holds exactly one overdue event for it"
else
  fail "the store holds $overdue_n overdue events for it"
fi
if awk -F '\t' '$1 == "pending-prompt-overdue" && $2 == "blocker" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv"; then
  ok "the overdue kind wakes the supervisor (class blocker)"
else
  fail "pending-prompt-overdue is not a waking class"
fi
rm -rf "$fleet/streamjson/cp-day"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-pending-age: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-pending-age: all passed"
