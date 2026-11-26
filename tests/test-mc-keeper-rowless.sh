#!/bin/bash
# Tests for scripts/mc-keeper.sh's routing of a live stream-json worker that
# no launcher row names (launched outside the launcher, its row lost, or a
# polish session a worker spawned, whose dispatch record names no owner): its
# prompts are heard by its record's, parent's or name's program, plus one
# event there saying it has no row; else each request goes to the hub as
# unowned, as does each request of a worker whose program has no live
# mission control. Who may answer is unchanged.
#
# Companions: the other tests/test-mc-keeper*.sh suites, which share
# tests/lib/mc-keeper-fixture.sh; this one keeps its own setup.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-rowless.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-keeper-rowless.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha, beta, hub]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 1000000}
program_beta_repositories: [$repo]
program_beta_spec_root: $repo/specs
program_beta_home: $tmp/mchome
program_beta_budget: {host_load: 1000000}
program_hub_repositories: [$repo]
program_hub_spec_root: $repo/specs
program_hub_home: $tmp/mchome
program_hub_budget: {host_load: 1000000}
EOF
mkdir -p "$tmp/bin" "$fleet/mission-control/sessions"
# A forge stub that answers nothing, so no pass can reach the real gh.
printf '#!/bin/sh\nexit 1\n' >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"

own_worker() { # own_worker <worker> <owner>: the dispatch record's owner
  mkdir -p "$fleet/dispatch-markers"
  printf '%s\t%s\t%s\tstream-json-persistent\t%s\t-\n' "$1" "demo:task-9" "$2" "$fleet/streamjson/$1" >"$fleet/dispatch-markers/$1"
}
pp_req() { # pp_req <worker> [<owner>|-|none]: an overdue pending request under live pids, owned by alpha unless said; - a record naming no owner, none no record
  mkdir -p "$fleet/streamjson/$1"
  printf 'aaaa1111-bbbb-cccc-dddd-eeee00000001\tpermission\t1000\tpending\n' >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
  [ "${2:-}" = none ] || own_worker "$1" "${2:-mission-control:alpha}"
}
pp_fresh() { # pp_fresh <worker> <request-suffix> <received> [none]: as pp_req, the request fresh; none leaves no record
  mkdir -p "$fleet/streamjson/$1"
  printf 'bbbb2222-bbbb-cccc-dddd-eeee0000000%s\tpermission\t%s\tpending\n' "$2" "$3" >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
  [ "${4:-}" = none ] || own_worker "$1" mission-control:alpha
}
mc_row() { # mc_row <program> live|dead|none: the program's launched mission-control row, its stream-json pid alive or gone, or no row
  mr_n="mc-$1-mission-control-00000000aa"
  rm -rf "$fleet/mission-control/sessions/$mr_n" "$fleet/streamjson/$mr_n"
  [ "$2" != none ] || return 0
  mkdir -p "$fleet/mission-control/sessions" "$fleet/streamjson/$mr_n"
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\t%s\nkind\tmission-control\nscope\tx\nbackend\tstream-json\nhandle\t%s\nlaunched\t1\n' \
    "$mr_n" "$1" "$mr_n" >"$fleet/mission-control/sessions/$mr_n"
  if [ "$2" = live ]; then
    printf '%s\n' "$$" >"$fleet/streamjson/$mr_n/worker.pid"
  else
    printf '999999999\n' >"$fleet/streamjson/$mr_n/worker.pid"
  fi
}
keeper_as() { # keeper_as <program> <now>: one watch pass as that program
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM="$1" /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$2" 2>/dev/null)
}
ev_of() { # ev_of <program> <worker>: that program's stored events for the worker
  mc_run mc-event.sh list --program "$1"
  printf '%s\n' "$OUT" | awk -F '\t' -v w="$2" '$4 == w'
}
mc_row alpha live
mc_row beta live

# The ruling: the unowned event goes to the hub program, the one whose mission
# control sees every program, raised once however many keepers see it.
pp_req rl-hubbed none
keeper_as alpha 5000
expect_out "an unowned worker is raised once" "announced${tab}stream-json-worker-unowned${tab}rl-hubbed"
keeper_as beta 5060
expect_no_out "and not again by another program's keeper" "rl-hubbed"
keeper_as hub 5120
expect_no_out "nor by the hub's own" "rl-hubbed"
mc_run mc-event.sh list --program hub
expect_out "the event lands under the hub program" "rl-hubbed"
mc_run mc-event.sh list --program alpha
expect_no_out "never under the finding program" "rl-hubbed"
mc_run mc-event.sh list --program beta
expect_no_out "nor under another" "rl-hubbed"

# Every request an unowned worker holds is raised, each once, so a request
# arriving after the first is never left unseen behind the first one's claim.
pp_req rl-many none
keeper_as alpha 5000
expect_out "an unowned worker's first request is raised" "announced${tab}stream-json-worker-unowned${tab}rl-many"
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000003\tpermission\t5100\tpending\n' >>"$fleet/streamjson/rl-many/journal"
keeper_as beta 5110
expect_out "a later request on it is raised too, by whichever keeper sees it" "announced${tab}stream-json-worker-unowned${tab}rl-many"
keeper_as hub 5120
expect_no_out "and each request only once" "rl-many"
mc_run mc-event.sh list --program hub
rl_many_n=$(printf '%s\n' "$OUT" | grep -c "stream-json-worker-unowned${tab}rl-many${tab}")
if [ "$rl_many_n" = 2 ]; then
  ok "the hub holds one event per request"
else
  fail "the hub holds $rl_many_n unowned events for rl-many, not 2: $OUT"
fi
expect_out "each event names its request" "stream-json-worker-unowned${tab}rl-many${tab}stream-json worker rl-many has request aaaa1111"
expect_out "and the later one is named too" "request aaaa1111-bbbb-cccc-dddd-eeee00000003"
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000001\tpermission\t1000\tanswered\t5130\naaaa1111-bbbb-cccc-dddd-eeee00000003\tpermission\t5100\tanswered\t5130\n' \
  >"$fleet/streamjson/rl-many/journal"
keeper_as alpha 5140
rl_many_claims=0
for rl_c in "$fleet/streamjson/rl-many/"unowned-announced*; do
  [ ! -e "$rl_c" ] || rl_many_claims=$((rl_many_claims + 1))
done
if [ "$rl_many_claims" = 0 ]; then
  ok "a settled request's claim is dropped"
else
  fail "claims outlive their settled requests: $(ls "$fleet/streamjson/rl-many/")"
fi
# A worker directory that is a link is never pruned through.
mkdir -p "$tmp/linked-worker"
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000009\tpermission\t1000\tanswered\t1100\n' >"$tmp/linked-worker/journal"
: >"$tmp/linked-worker/unowned-announced.aaaa1111-bbbb-cccc-dddd-eeee00000009"
ln -s "$tmp/linked-worker" "$fleet/streamjson/rl-linked"
keeper_as alpha 5150
if [ -e "$tmp/linked-worker/unowned-announced.aaaa1111-bbbb-cccc-dddd-eeee00000009" ]; then
  ok "a linked worker directory's files are left alone"
else
  fail "the prune removed a file through a linked worker directory"
fi
rm -f "$fleet/streamjson/rl-linked"
keeper_as hub 5150
if grep -q "^rl-many${tab}" "$fleet/mission-control/hub/keeper-unowned" 2>/dev/null; then
  fail "the hub's unowned set keeps settled requests: $(cat "$fleet/mission-control/hub/keeper-unowned")"
else
  ok "and the program's unowned set drops them too, so it never outgrows what is pending"
fi

# A worker whose program has no live mission control (no launched row, or
# every one positively dead) has each request raised to the hub as well, so
# its prompts still reach a mission control. One whose mission control lives
# is left to its own program, never announced twice.
mc_row beta dead
pp_req og-beta mission-control:beta
keeper_as alpha 5000
expect_out "a worker whose program's mission control is dead is raised to the hub" "announced${tab}stream-json-worker-unowned${tab}og-beta"
keeper_as hub 5010
expect_no_out "once, whichever keeper sees it" "og-beta"
mc_run mc-event.sh list --program hub
expect_out "the event says the owner's mission control is gone" "the mission control of its program beta is gone"
mc_row alpha none
pp_req og-alpha
keeper_as hub 5020
expect_out "a worker whose program has no mission-control row is raised to the hub" "announced${tab}stream-json-worker-unowned${tab}og-alpha"
mc_row alpha live
mc_row beta live
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000004\tpermission\t5030\tpending\n' >>"$fleet/streamjson/og-beta/journal"
keeper_as hub 5040
expect_no_out "a request on a worker whose mission control lives is not raised to the hub" "og-beta"
keeper_as beta 5050
expect_out "its own program announces it" "announced${tab}pending-prompt${tab}og-beta"
expect_no_out "and no keeper raises it as well" "stream-json-worker-unowned"
keeper_as alpha 5060
expect_no_out "nor another program's" "og-beta"
# The hub's own mission control gone, a hub worker's request is raised by
# another program's keeper under its own program, never into the hub's queue.
pp_req og-hub mission-control:hub
keeper_as hub 5070
expect_no_out "the hub's keeper does not raise its own worker to itself" "stream-json-worker-unowned${tab}og-hub"
keeper_as alpha 5080
expect_out "another program's keeper raises it" "announced${tab}stream-json-worker-unowned${tab}og-hub"
mc_run mc-event.sh list --program alpha
expect_out "under that keeper's program, saying why" "stream-json-worker-unowned${tab}og-hub${tab}stream-json worker og-hub has request aaaa1111-bbbb-cccc-dddd-eeee00000001 waiting but the mission control of its program hub is gone"
# A request that has just arrived, inside the pending bound, on a worker whose
# mission control is dead is raised too, not only an overdue one.
mc_row beta dead
pp_req og-fresh mission-control:beta
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000005\tpermission\t5085\tpending\n' >"$fleet/streamjson/og-fresh/journal"
keeper_as alpha 5090
expect_out "a fresh request on a worker whose mission control is dead is raised" "announced${tab}stream-json-worker-unowned${tab}og-fresh"
# A mission control whose liveness cannot be told counts as live, so its
# workers' requests are left to it rather than raised to the hub.
mc_row beta live
rm -rf "$fleet/streamjson/mc-beta-mission-control-00000000aa"
pp_req og-unknown mission-control:beta
keeper_as alpha 5100
expect_no_out "a mission control with no liveness evidence is not taken for gone" "og-unknown"
mc_row beta live
rm -rf "$fleet/streamjson/rl-many" "$fleet/streamjson/og-beta" "$fleet/streamjson/og-alpha" "$fleet/streamjson/og-hub" "$fleet/streamjson/og-fresh" "$fleet/streamjson/og-unknown" "$fleet/streamjson/rl-hubbed" "$fleet/dispatch-markers"
rm -f "$fleet/mission-control/alpha/keeper-unowned" "$fleet/mission-control/hub/keeper-unowned" \
  "$fleet/mission-control/alpha/keeper-prompts" "$fleet/mission-control/beta/keeper-prompts" "$fleet/mission-control/hub/keeper-prompts" \
  "$fleet/mission-control/alpha/keeper-arrivals" "$fleet/mission-control/beta/keeper-arrivals" "$fleet/mission-control/hub/keeper-arrivals"

# A row-less worker whose name carries its program.
pp_req mc-alpha-worker-0a1b2c3d4e-polish -
keeper_as alpha 5000
expect_out "an unregistered worker whose name carries its program raises its prompt to that program" "announced${tab}pending-prompt-overdue${tab}mc-alpha-worker-0a1b2c3d4e-polish"
expect_out "and one event says it has no registry row" "announced${tab}stream-json-worker-unregistered${tab}mc-alpha-worker-0a1b2c3d4e-polish"
case $(ev_of alpha mc-alpha-worker-0a1b2c3d4e-polish) in
  *"stream-json-worker-unregistered${tab}mc-alpha-worker-0a1b2c3d4e-polish${tab}"*"no launcher row"*"retire mc-alpha-worker-0a1b2c3d4e-polish"*) ok "the no-row event names the worker and how to retire it" ;;
  *) fail "the no-row event: $(ev_of alpha mc-alpha-worker-0a1b2c3d4e-polish)" ;;
esac
keeper_as beta 5030
expect_no_out "another program's keeper leaves it alone" "mc-alpha-worker-0a1b2c3d4e-polish"
keeper_as hub 5040
expect_no_out "and so does the hub's" "mc-alpha-worker-0a1b2c3d4e-polish"
keeper_as alpha 5060
expect_no_out "the no-row event fires once" "stream-json-worker-unregistered"
expect_no_out "and the overdue prompt is not announced again" "pending-prompt-overdue${tab}mc-alpha-worker-0a1b2c3d4e-polish"
if [ "$(ev_of alpha mc-alpha-worker-0a1b2c3d4e-polish | awk -F '\t' '$3 == "stream-json-worker-unregistered"' | wc -l | tr -d ' ')" = 1 ]; then
  ok "the store holds the no-row event once"
else
  fail "the no-row events stored: $(ev_of alpha mc-alpha-worker-0a1b2c3d4e-polish)"
fi
pp_fresh mc-alpha-worker-0a1b2c3d4e-polish2 4 5070 none
pp_req mc-alpha-worker-0a1b2c3d4e-polish3 none
# No pid file and no result: not provably dead, so its prompt is raised, but
# the rung does not report it waiting, so no one-time event is.
pp_req mc-alpha-worker-0a1b2c3d4e-polish4 none
rm -f "$fleet/streamjson/mc-alpha-worker-0a1b2c3d4e-polish4/supervisor.pid" "$fleet/streamjson/mc-alpha-worker-0a1b2c3d4e-polish4/worker.pid"
bad_names="mc-gamma-worker-0a1b2c3d4e mc-alpha-painter-0a1b2c3d4e mc-alpha-worker-fedcba987 mc-alpha-worker-0a1b2c3d4eX"
for bad in $bad_names; do pp_req "$bad" none; done
keeper_as alpha 5080
expect_out "a fresh request on an unregistered sub-session is announced as it arrives" "announced${tab}pending-prompt${tab}mc-alpha-worker-0a1b2c3d4e-polish2"
expect_out "and its own no-row event fires" "announced${tab}stream-json-worker-unregistered${tab}mc-alpha-worker-0a1b2c3d4e-polish2"
expect_out "a name with no dispatch record at all still routes by its program" "announced${tab}pending-prompt-overdue${tab}mc-alpha-worker-0a1b2c3d4e-polish3"
expect_out "a worker the rung cannot show waiting still has its prompt raised" "announced${tab}pending-prompt-overdue${tab}mc-alpha-worker-0a1b2c3d4e-polish4"
expect_no_out "but no one-time event calls it live" "stream-json-worker-unregistered${tab}mc-alpha-worker-0a1b2c3d4e-polish4"
for bad in $bad_names; do
  expect_no_out "a name outside the grammar or naming no configured program derives no owner: $bad" "pending-prompt-overdue${tab}$bad"
  rm -rf "${fleet:?}/streamjson/$bad"
done
case $(ev_of alpha mc-alpha-worker-0a1b2c3d4e-polish3) in
  *"stream-json worker mc-alpha-worker-0a1b2c3d4e-polish3 (no launcher row) has waited"*) ok "a row-less worker's prompt says it has no launcher row" ;;
  *) fail "the row-less prompt's text: $(ev_of alpha mc-alpha-worker-0a1b2c3d4e-polish3)" ;;
esac

# A launcher list that cannot be read cannot tell a row from its absence, so
# a registered worker is never called row-less, though its prompt is raised.
pp_req mc-alpha-worker-1111111111
printf 'format\t1\nname\tmc-alpha-worker-1111111111\nprogram\talpha\nkind\tworker\nscope\tx\nbackend\tstream-json\nlaunched\t1\n' \
  >"$fleet/mission-control/sessions/mc-alpha-worker-1111111111"
printf 'format\t1\nname\tmc-alpha-worker-2222222222\n' >"$fleet/mission-control/sessions/mc-alpha-worker-2222222222"
chmod 000 "$fleet/mission-control/sessions/mc-alpha-worker-2222222222"
if hermetic_access_denied r "$fleet/mission-control/sessions/mc-alpha-worker-2222222222"; then
  keeper_as alpha 5150
  expect_out "with the launcher's list unreadable, a registered worker's prompt is still raised" "announced${tab}pending-prompt-overdue${tab}mc-alpha-worker-1111111111"
  expect_no_out "and it is not called row-less" "stream-json-worker-unregistered${tab}mc-alpha-worker-1111111111"
else
  echo "skip: the unreadable launcher list case (the mode does not deny reading here)"
fi
chmod 600 "$fleet/mission-control/sessions/mc-alpha-worker-2222222222"
rm -f "$fleet/mission-control/sessions/mc-alpha-worker-2222222222" "$fleet/mission-control/sessions/mc-alpha-worker-1111111111"
rm -rf "$fleet/streamjson/mc-alpha-worker-1111111111"

# No owner derivable: the hub hears each request, as unowned, naming the worker.
pp_req stray-polish none
keeper_as alpha 5200
expect_out "an unowned worker's request is raised" "announced${tab}stream-json-worker-unowned${tab}stray-polish"
expect_no_out "but not as the finding program's own prompt" "pending-prompt-overdue${tab}stray-polish"
keeper_as hub 5210
expect_no_out "and only once, whichever keeper sees it" "stray-polish"
case $(ev_of hub stray-polish) in
  *"stream-json-worker-unowned${tab}stray-polish${tab}stream-json worker stray-polish has request aaaa1111"*"raised here as unowned"*) ok "the hub's event names the worker and its request as unowned" ;;
  *) fail "the hub's events for the unowned worker: $(ev_of hub stray-polish)" ;;
esac
pp_fresh stray-fresh 5 5250 none
keeper_as hub 5260
expect_out "a fresh request on an unowned worker reaches the hub as it arrives" "announced${tab}stream-json-worker-unowned${tab}stray-fresh"
keeper_as beta 5270
expect_no_out "and no other program's keeper raises its prompts" "pending-prompt"

# The parent comes before the name: a sub-session whose parent's record names
# beta is beta's, though its name says alpha.
own_worker mc-alpha-worker-0a1b2c3d4e-step mission-control:beta
pp_req mc-alpha-worker-0a1b2c3d4e-step-polish none
printf 'mc-alpha-worker-0a1b2c3d4e-step\n' >"$fleet/streamjson/mc-alpha-worker-0a1b2c3d4e-step-polish/parent"
keeper_as alpha 5280
expect_no_out "a sub-session with a parent is not its name's program's" "mc-alpha-worker-0a1b2c3d4e-step-polish"
keeper_as beta 5290
expect_out "it is its parent's program's" "announced${tab}pending-prompt-overdue${tab}mc-alpha-worker-0a1b2c3d4e-step-polish"
expect_out "with its own no-row event there" "announced${tab}stream-json-worker-unregistered${tab}mc-alpha-worker-0a1b2c3d4e-step-polish"
case $(ev_of beta mc-alpha-worker-0a1b2c3d4e-step-polish) in
  *"since its parent's row or record gives beta"*) ok "the no-row event says the parent gave the program" ;;
  *) fail "the parent-routed no-row event: $(ev_of beta mc-alpha-worker-0a1b2c3d4e-step-polish)" ;;
esac
rm -rf "$fleet/streamjson/mc-alpha-worker-0a1b2c3d4e-step-polish" "$fleet/dispatch-markers/mc-alpha-worker-0a1b2c3d4e-step"

# A name-derived owner whose mission control is gone escalates each request
# to the hub, as any owner does.
mc_row alpha dead
pp_req mc-alpha-worker-0a1b2c3d4e-orphan none
keeper_as hub 5295
expect_out "an unreachable name-derived owner's request is raised to the hub" "announced${tab}stream-json-worker-unowned${tab}mc-alpha-worker-0a1b2c3d4e-orphan"
case $(ev_of hub mc-alpha-worker-0a1b2c3d4e-orphan) in
  *"the mission control of its program alpha is gone"*) ok "and the event says its owner's mission control is gone" ;;
  *) fail "the escalation for the unreachable owner: $(ev_of hub mc-alpha-worker-0a1b2c3d4e-orphan)" ;;
esac
mc_row alpha live
rm -rf "$fleet/streamjson/mc-alpha-worker-0a1b2c3d4e-orphan"

# A registered worker is unchanged: its row's program hears it, with no no-row event.
pp_req mc-beta-worker-0123456789 -
printf 'format\t1\nname\tmc-beta-worker-0123456789\nprogram\tbeta\nkind\tworker\nscope\tx\nbackend\tstream-json\nlaunched\t1\n' \
  >"$fleet/mission-control/sessions/mc-beta-worker-0123456789"
keeper_as beta 5300
expect_out "a registered worker's prompt reaches its row's program" "announced${tab}pending-prompt-overdue${tab}mc-beta-worker-0123456789"
expect_no_out "with no no-row event" "stream-json-worker-unregistered"
expect_no_out "nor an unowned one" "stream-json-worker-unowned"
keeper_as alpha 5310
expect_no_out "and no other program hears it" "mc-beta-worker-0123456789"

# A dead worker's leftover directory raises no prompt and no no-row event.
pp_req mc-alpha-worker-dead0dead0-polish -
printf '999999999\n' >"$fleet/streamjson/mc-alpha-worker-dead0dead0-polish/supervisor.pid"
printf '999999999\n' >"$fleet/streamjson/mc-alpha-worker-dead0dead0-polish/worker.pid"
keeper_as alpha 5400
expect_no_out "a dead worker's request is not raised as a prompt" "pending-prompt-overdue${tab}mc-alpha-worker-dead0dead0-polish"
expect_no_out "nor as a worker with no row" "stream-json-worker-unregistered${tab}mc-alpha-worker-dead0dead0-polish"
keeper_as alpha 5460
expect_no_out "and its leftover directory raises nothing on a later pass" "mc-alpha-worker-dead0dead0-polish"
pp_req stray-dead none
printf '999999999\n' >"$fleet/streamjson/stray-dead/supervisor.pid"
printf '999999999\n' >"$fleet/streamjson/stray-dead/worker.pid"
keeper_as hub 5500
expect_no_out "an unowned dead worker raises no prompt" "pending-prompt-overdue${tab}stray-dead"
expect_no_out "and no unowned event" "stream-json-worker-unowned${tab}stray-dead"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-rowless: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-rowless: all passed"
