#!/bin/bash
# Tests for scripts/mission-control-launch.sh: the host-wide bound on live
# sessions and the move of a live session between programs (mission-control
# REQ-L1.7, REQ-D1.16).
#
# Split from tests/test-mission-control-launch.sh so each file fits the
# per-file test-time budget; the shared fixture is
# tests/lib/mc-launch-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
# The usage gate reads the status-line mirror when present; a fixture never
# reads the host's real one.
export PLANWRIGHT_USAGE_MIRROR=""
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

# ---------------------------------------------------------------------------
# REQ-L1.7: a host-wide bound on live sessions across every program's rows in
# the shared registry (fleet_host_max_live_workers), mission-control sessions
# excluded, the operator-asked override kept, a remote host's rows never ours.
# ---------------------------------------------------------------------------
fleet="$tmp/fleet-cap"
mkdir -p "$fleet/mission-control/sessions"
capreg="$fleet/mission-control/sessions"
# seed_row <name> <program> <kind> — a registered session of another program.
seed_row() {
  printf '%s\n' "format${TAB}1" "name${TAB}$1" "state${TAB}launched" "token${TAB}seed-$1" "pid${TAB}1" \
    "program${TAB}$2" "owner${TAB}mission-control:$2" "kind${TAB}$3" "scope${TAB}seed" "backend${TAB}stream-json" \
    "handle${TAB}$1" "profile${TAB}worker" "tier${TAB}-" "brief${TAB}-" "cwd${TAB}-" "task${TAB}-" "primary${TAB}-" \
    "marker${TAB}-" "launched${TAB}1" >"$capreg/$1"
}
seed_row mc-beta-worker-0000000001 beta worker
seed_row mc-gamma-reviewer-0000000002 gamma reviewer
seed_row mc-beta-mission-control-0000000003 beta mission-control
set_cap() { printf 'fleet_host_max_live_workers: %s\n' "$1" >"$tmp/absent.yml"; }
ml_cap() { ml "$@"; }
cap_launch() { # <scope> [extra launch args...]
  cl_scope=$1
  shift
  rec="$tmp/rec-cap-$cl_scope"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ml_cap launch --program alpha --kind worker --scope "spec:cap-$cl_scope" --brief "$tmp/brief.md" "$@"
}

set_cap 2
cap_launch full
cap_name=$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind worker --scope spec:cap-full)
if [ "$RC" = 4 ] && [ ! -e "$capreg/$cap_name" ]; then
  ok "a launch past the host-wide bound is refused (exit 4) and leaves no row"
else
  fail "a launch past the host bound exited $RC with row present=$([ -e "$capreg/$cap_name" ] && echo yes || echo no): $ERR"
fi
case $ERR in
  *"beta 1"*"gamma 1"* | *"gamma 1"*"beta 1"*) ok "the refusal names each program and how many it holds" ;;
  *) fail "the refusal does not name the programs and counts: $ERR" ;;
esac
case $ERR in
  *fleet_host_max_live_workers*"--operator-asked"*) ok "the refusal names the knob and the operator-asked path" ;;
  *) fail "the refusal does not name the knob and the override: $ERR" ;;
esac
[ ! -e "$fleet/mission-control/launch/$cap_name" ] && ok "a refused launch leaves no launch directory" \
  || fail "a refused launch left its launch directory"

set_cap 3
cap_launch room
if [ "$RC" = 0 ]; then
  ok "a mission-control row is not counted against the bound"
  wait_done "$(field name)"
else
  fail "two live workers and a mission-control row refused a launch under a bound of 3: $ERR"
fi

# Three live workers now; the bound of 3 holds the next one, and an
# operator-asked launch goes past it with the bypass recorded first.
cap_launch held
[ "$RC" = 4 ] && ok "the bound counts the launched session too" || fail "a fourth worker under a bound of 3 exited $RC: $ERR"
cap_launch asked --operator-asked
if [ "$RC" = 0 ]; then
  ok "an operator-asked launch goes past the host-wide bound"
  wait_done "$(field name)"
  asked_name=$(field name)
  ml_out=$(cd "$repo" && env PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" HOME="$fixhome" \
    /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null)
  case $ml_out in
    *"${TAB}host-cap-bypass${TAB}$asked_name${TAB}"*) ok "the bypass is recorded as a host-cap-bypass event" ;;
    *) fail "no host-cap-bypass event for $asked_name: $ml_out" ;;
  esac
else
  fail "the operator-asked launch past the host bound exited $RC: $ERR"
fi

# A mission-control launch is never held by the bound.
SHIM_RECORD_DIR="$tmp/rec-cap-mc" ml_cap launch --program alpha --kind mission-control --scope cap-mc --brief "$tmp/brief.md"
[ "$RC" = 0 ] && ok "a mission-control launch is not held by the host-wide bound" || fail "a mission-control launch under the bound exited $RC: $ERR"
wait_done "$(field name)"

# A reservation made after this launch is not counted against it, so two
# concurrent launches near the bound admit the first rather than refusing both.
seed_row mc-delta-worker-0000000009 delta worker
sed "s/^launched${TAB}.*/launched${TAB}99999999999/" "$capreg/mc-delta-worker-0000000009" >"$capreg/mc-delta-worker-0000000009.tmp.sed" \
  && mv "$capreg/mc-delta-worker-0000000009.tmp.sed" "$capreg/mc-delta-worker-0000000009"
set_cap 5
cap_launch before-later
[ "$RC" = 0 ] && ok "a later reservation is not counted against an earlier launch" || fail "a later reservation held an earlier launch: $ERR"
wait_done "$(field name)"
rm -f "$capreg/mc-delta-worker-0000000009"

# An operator-asked launch with room records no bypass.
set_cap off
cap_launch asked-room --operator-asked
room_name=$(field name)
wait_done "$room_name"
ml_out=$(cd "$repo" && env PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" HOME="$fixhome" \
  /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null)
case $ml_out in
  *"${TAB}host-cap-bypass${TAB}$room_name${TAB}"*) fail "an operator-asked launch with room recorded a bypass" ;;
  *) ok "an operator-asked launch with room records no bypass" ;;
esac

# off: no bound.
set_cap off
cap_launch unlimited
[ "$RC" = 0 ] && ok "off lifts the host-wide bound" || fail "off still held a launch: $ERR"
wait_done "$(field name)"

# The shipped default bound holds with no machine-local setting: the registry
# holds the default six by now.
rm -f "$tmp/absent.yml"
sed "/^fleet_host_max_live_workers:/d" "$tracked" >"$tracked.sed" && mv "$tracked.sed" "$tracked"
cap_launch default-held
[ "$RC" = 4 ] && ok "the shipped default bound holds a launch at six sessions" || fail "the shipped default let a launch through (exit $RC)"

# A malformed value is a refusal, never an unbounded launch.
set_cap lots
cap_launch malformed
[ "$RC" -ne 0 ] && ok "a malformed bound refuses the launch" || fail "a malformed bound let a launch through"

# A kind whose profile runs no tests or builds (the tower profile) is never
# held by the bound, so a host full of heavy units still takes a cheap
# read-only session; every kind under the worker profile stays held, and the
# exemption leaves no bypass event.
set_cap 2
kind_launch() { # <kind> <scope> [extra launch args...]
  kl_kind=$1
  kl_scope=$2
  shift 2
  rec="$tmp/rec-cap-$kl_kind-$kl_scope"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ml_cap launch --program alpha --kind "$kl_kind" --scope "$kl_scope" --brief "$tmp/brief.md" --cwd "$repo" "$@"
}
for light_kind in tower orchestrator; do
  kind_launch "$light_kind" "light-$light_kind"
  if [ "$RC" = 0 ]; then
    ok "a $light_kind launch is not held by a full host"
    light_name=$(field name)
    wait_done "$light_name"
    ml_out=$(cd "$repo" && env PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" HOME="$fixhome" \
      /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null)
    case $ml_out in
      *"${TAB}host-cap-bypass${TAB}$light_name${TAB}"*) fail "the $light_kind exemption recorded a host-cap-bypass event" ;;
      *) ok "the $light_kind exemption records no bypass event" ;;
    esac
  else
    fail "a $light_kind launch on a full host exited $RC: $ERR"
  fi
done
for heavy_kind in worker reviewer ad-hoc; do
  kind_launch "$heavy_kind" "heavy-$heavy_kind"
  [ "$RC" = 4 ] && ok "a $heavy_kind launch is still held by a full host" || fail "a $heavy_kind launch on a full host exited $RC: $ERR"
done
fleet="$tmp/fleet"

# A session on another host (fleet-remote.sh) lives in that host's registry,
# so the near side never reads this host's rows for it.
if grep -q 'mission-control/sessions\|fleet_host_max_live_workers' "$repo_root/scripts/fleet-remote.sh"; then
  fail "fleet-remote.sh consults this host's registry or bound"
else
  ok "a remote launch is counted on its own host, never against this host's bound"
fi

# ---------------------------------------------------------------------------
# REQ-D1.16: a live session moves between programs; routing follows the row.
# ---------------------------------------------------------------------------
set_cap off
grep -v '^mission_control_programs:' "$tracked" >"$tracked.new" && mv "$tracked.new" "$tracked"
cat >>"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_beta_repositories: [$repo]
program_beta_spec_root: $repo/specs
program_beta_home: $tmp/mc-home/beta
EOF
REG="$fleet/mission-control/sessions"
rp_field() { awk -F '\t' -v k="$2" '$1 == k { print $2; exit }' "$1"; }
rp_row() { # rp_row <name> <program> <kind> <state> — a registry row with pid, cwd and task fields
  mkdir -p "$REG"
  printf 'format\t1\nname\t%s\nstate\t%s\ntoken\ttok-%s\npid\t4242\nprogram\t%s\nowner\tmission-control:%s\nkind\t%s\nscope\tfold-1\nbackend\tstream-json\nhandle\t%s\nprofile\tp.json\ntier\topus\nbrief\t/b.md\ncwd\t/wt/one\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t100\n' \
    "$1" "$4" "$1" "$2" "$2" "$3" "$1" >"$REG/$1"
}
rp_decide() { # rp_decide <program> <act> <target> — log a decision, print its id
  mc_run mc-kb.sh append decisions --program "$1" --subject "operator order" --act "$2" --target "$3" --grounds "operator: fold it" --no-reversal
  printf '%s\n' "$OUT" | tail -n 1
}
rp_events() { mc_run mc-event.sh list --program "$1"; }
rp_pend() { # rp_pend <worker> <epoch> — a pending request under live pids
  mkdir -p "$fleet/streamjson/$1"
  printf 'cccc3333-bbbb-cccc-dddd-eeee00000001\tpermission\t%s\tpending\n' "$2" >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'spec:fold-1\n' >"$fleet/streamjson/$1/scope"
}
rp_watch() { # rp_watch <program> <now>
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM="$1" PLANWRIGHT_STREAMJSON_PENDING_AGE=900 \
    /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$2" 2>/dev/null)
}

fold_name=mc-alpha-worker-1000000001
rp_row "$fold_name" alpha worker launched
rp_row mc-alpha-tower-1000000002 alpha tower launched
rp_row mc-alpha-mission-control-1000000003 alpha mission-control launched
rp_row mc-alpha-worker-1000000004 alpha worker launching
cp "$repo_root/config/duties.yaml" "$core/config/duties.yaml"
for p in alpha beta; do
  mc_run mc-kb.sh init --program "$p"
  [ "$RC" = 0 ] || fail "fixture: kb init for $p: $ERR"
done
fold_id=$(rp_decide beta fold-in-order alpha)
yes_id=$(rp_decide beta reparent-yes "$fold_name")
[ -n "$fold_id" ] && [ -n "$yes_id" ] || fail "fixture: the decisions were not logged ($fold_id / $yes_id)"
before=$(cat "$REG/$fold_name")

ml reparent
[ "$RC" = 2 ] && ok "reparent with no arguments is a usage error" || fail "bare reparent exited $RC"
ml reparent "$fold_name" --program beta
[ "$RC" = 2 ] && ok "a move with no --authority is refused (exit 2)" || fail "a move without authority exited $RC"
[ "$(cat "$REG/$fold_name")" = "$before" ] && ok "and the row is unchanged" || fail "the no-authority refusal changed the row"
ml reparent "$fold_name" --program beta --authority decisions-209901-1
[ "$RC" = 4 ] && ok "an authority naming no decision is refused (exit 4)" || fail "an unknown authority exited $RC"
ml reparent mc-alpha-worker-9999999999 --program beta --authority "$fold_id"
[ "$RC" = 3 ] && ok "an unknown session is refused (exit 3)" || fail "an unknown session exited $RC"
ml reparent "$fold_name" --program nosuch --authority "$fold_id"
[ "$RC" = 4 ] && ok "an unknown program is refused (exit 4)" || fail "an unknown program exited $RC"
ml reparent "$fold_name" --program alpha --authority "$fold_id"
[ "$RC" = 4 ] && ok "the same program is refused (exit 4)" || fail "the same program exited $RC"
ml reparent mc-alpha-mission-control-1000000003 --program beta --authority "$fold_id"
[ "$RC" = 4 ] && ok "a mission-control session is refused (exit 4)" || fail "a mission-control session exited $RC"
ml reparent mc-alpha-worker-1000000004 --program beta --authority "$fold_id"
[ "$RC" = 4 ] && ok "a launch still in flight is refused (exit 4)" || fail "a launching row exited $RC"
ml reparent mc-alpha-tower-1000000002 --program beta --authority "$yes_id"
[ "$RC" = 4 ] && ok "a yes for one session does not move another (exit 4)" || fail "a yes covered another session: exit $RC"
[ "$(cat "$REG/$fold_name")" = "$before" ] && ok "none of the refusals changed the row" || fail "a refusal changed the row"

# A registry the launcher cannot rewrite changes nothing.
if [ "$(id -u)" != 0 ]; then
  chmod 500 "$REG"
  ml reparent "$fold_name" --program beta --authority "$fold_id"
  chmod 700 "$REG"
  if [ "$RC" = 2 ] && [ "$(cat "$REG/$fold_name")" = "$before" ]; then
    ok "a row that cannot be rewritten refuses and changes nothing (exit 2)"
  else
    fail "an unwritable registry: exit $RC"
  fi
fi

# The move itself, authorised by the fold-in order.
ml reparent "$fold_name" --program beta --authority "$fold_id"
[ "$RC" = 0 ] && ok "a fold-in order moves a live session" || fail "the move exited $RC: $ERR"
case $OUT in
  "reparent${TAB}$fold_name${TAB}moved${TAB}alpha${TAB}beta"*) ok "the verb says what moved, from and to" ;;
  *) fail "the move's output: $OUT" ;;
esac
if [ "$(rp_field "$REG/$fold_name" program)" = beta ] && [ "$(rp_field "$REG/$fold_name" owner)" = mission-control:beta ]; then
  ok "the row's program and owner are the destination's"
else
  fail "the row after the move: $(cat "$REG/$fold_name")"
fi
grep -v -e "^program${TAB}" -e "^owner${TAB}" "$REG/$fold_name" >"$tmp/after.rows"
printf '%s\n' "$before" | grep -v -e "^program${TAB}" -e "^owner${TAB}" >"$tmp/before.rows"
cmp -s "$tmp/before.rows" "$tmp/after.rows" && ok "pid, cwd, branch and every other field are untouched" || fail "a field beyond program and owner changed"
ml list
case $OUT in *"$fold_name${TAB}beta${TAB}worker"*) ok "the destination's list shows the session" ;; *) fail "list after the move: $OUT" ;; esac
case $OUT in *"$fold_name${TAB}alpha"*) fail "the source's list still shows it" ;; *) ok "and the source's list does not" ;; esac
for p in alpha beta; do
  rp_events "$p"
  case $OUT in
    *"session-reparented${TAB}$fold_name${TAB}"*) ok "the move is an event in $p's log" ;;
    *) fail "no session-reparented event for $p: $OUT" ;;
  esac
done
mc_run mc-kb.sh query undo --program beta --subject "$fold_name"
case $OUT in
  *reparent*"$fold_name"*alpha*) ok "an undo entry names the source in the destination's log" ;;
  *) fail "the undo entry: $OUT" ;;
esac
undo_id=$(printf '%s\n' "$OUT" | awk -F '\t' '$4 == "reparent" { print $1; exit }')

# A prompt raised after the move reaches beta's events and not alpha's.
rp_pend "$fold_name" 9000
rp_watch alpha 9010
case $OUT in *"pending-prompt${TAB}$fold_name"*) fail "the source announced the moved session's prompt" ;; *) ok "the source program does not announce a prompt raised after the move" ;; esac
rp_watch beta 9010
case $OUT in *"announced${TAB}pending-prompt${TAB}$fold_name"*) ok "the destination announces it" ;; *) fail "the destination missed the prompt: $OUT" ;; esac
rp_events beta
case $OUT in *"pending-prompt${TAB}$fold_name"*) ok "the prompt is in the destination's events" ;; *) fail "not in beta's events: $OUT" ;; esac
rp_events alpha
case $OUT in *"pending-prompt${TAB}$fold_name"*) fail "the prompt is in the source's events" ;; *) ok "and not in the source's" ;; esac
rm -rf "$fleet/streamjson/$fold_name"

# One order covers every live session of the folded program.
ml reparent mc-alpha-tower-1000000002 --program beta --authority "$fold_id"
[ "$RC" = 0 ] && ok "one fold-in order covers a second session of the folded program" || fail "the second session exited $RC: $ERR"

# A yes covers its own session only.
w5=mc-alpha-worker-1000000005
rp_row "$w5" alpha worker launched
w5_before=$(cat "$REG/$w5")
ml reparent "$w5" --program beta --authority "$yes_id"
[ "$RC" = 4 ] && ok "a yes naming another session does not cover this one" || fail "a yes for another session exited $RC"

# An order for another program, a record only in the source's log, a malformed
# id and --undo with --authority each refuse and leave the row alone.
other_id=$(rp_decide beta fold-in-order other)
ml reparent "$w5" --program beta --authority "$other_id"
[ "$RC" = 4 ] && ok "a fold-in order for another program does not cover this one" || fail "an order for another program exited $RC"
# Ids count per program's log, so log past the destination's last id to get one beta's log lacks.
for pad_n in 1 2 3; do rp_decide alpha reparent-yes "pad-$pad_n" >"$tmp/pad.$pad_n"; done
src_id=$(rp_decide alpha fold-in-order alpha)
mc_run mc-kb.sh entries decisions --program beta
case $OUT in *"$src_id"*) fail "fixture: $src_id is also an id in beta's log" ;; esac
ml reparent "$w5" --program beta --authority "$src_id"
[ "$RC" = 4 ] && ok "an order recorded only in the source's log does not authorise a move into beta" || fail "a source-log order exited $RC"
ml reparent "$w5" --program beta --authority 'Bad_Id'
[ "$RC" = 2 ] && ok "a malformed authority id is refused (exit 2)" || fail "a malformed authority exited $RC"
ml reparent "$w5" --program beta --undo --authority "$fold_id"
[ "$RC" = 2 ] && ok "--undo together with --authority is refused (exit 2)" || fail "--undo with --authority exited $RC"
ml reparent "$w5" --program beta --undo
[ "$RC" = 4 ] && ok "--undo with no recorded move is refused (exit 4)" || fail "an undo with no move exited $RC"
[ "$(cat "$REG/$w5")" = "$w5_before" ] && ok "none of those changed the row" || fail "a refusal changed $w5"

yes5=$(rp_decide beta reparent-yes "$w5")
ml reparent "$w5" --program beta --authority "$yes5"
[ "$RC" = 0 ] && ok "a yes naming the session moves it" || fail "a yes for its own session exited $RC: $ERR"
ml reparent "$w5" --program alpha --undo
if [ "$RC" = 0 ] && [ "$(rp_field "$REG/$w5" program)" = alpha ]; then
  ok "a hand-run undo restores the source with no authority"
else
  fail "the hand-run undo: exit $RC, $ERR"
fi
mc_run mc-kb.sh query undo --program alpha --subject "$w5"
case $OUT in *reparent*) fail "the reversal logged an undo entry of its own: $OUT" ;; *) ok "a reversal logs no undo entry, so it cannot be reversed back" ;; esac
ml reparent "$w5" --program beta --undo
[ "$RC" = 4 ] && ok "no move out of beta is recorded in alpha, so the session cannot be undone back to beta" || fail "an undo back to beta exited $RC"

# Reversal through the undo entry needs no authority and restores the source.
mc_run mc-kb.sh revert --program beta "$undo_id"
if [ "$RC" = 0 ] && [ "$(rp_field "$REG/$fold_name" program)" = alpha ] && [ "$(rp_field "$REG/$fold_name" owner)" = mission-control:alpha ]; then
  ok "the undo entry's reversal restores the source with no authority"
else
  fail "the reversal: exit $RC, $ERR; row: $(cat "$REG/$fold_name")"
fi
ml reparent "$fold_name" --program alpha --undo
[ "$RC" = 4 ] && ok "the undo of a move is refused once the session is back in the source" || fail "a replayed undo exited $RC"

# Retirement works from the destination: a real launched session.
SHIM_RECORD_DIR="$tmp/rec-rp" ml launch --program alpha --kind tower --scope fold-live --brief "$tmp/brief.md" --cwd "$repo"
[ "$RC" = 0 ] || fail "fixture: the live launch exited $RC: $ERR"
live=$(field name)
wait_done "$live"
live_id=$(rp_decide beta reparent-yes "$live")
ml reparent "$live" --program beta --authority "$live_id"
[ "$RC" = 0 ] && ok "a launched session moves" || fail "moving a launched session exited $RC: $ERR"
ml retire "$live"
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire${TAB}$live${TAB}released"; then
  ok "retire works from the destination"
else
  fail "retire after the move: exit $RC, $OUT $ERR"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
