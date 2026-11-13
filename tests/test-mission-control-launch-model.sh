#!/bin/bash
# Tests for the per-launch tier flags of scripts/mission-control-launch.sh
# (--model, --effort, --reserved, --keep-config-env): the flags apply to one
# launch only and write no knob or overlay, an invalid value is refused before
# anything starts, a lowered tier is never silent, the choice is recorded
# where the tier is recorded, and a one-launch config overlay never reaches the
# worker's environment.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
export PLANWRIGHT_USAGE_MIRROR=""
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

write_mc_posture_pass

launch_worker() { # <scope> <rec> [launcher args...]
  lw_scope=$1
  lw_rec=$2
  shift 2
  mkdir -p "$lw_rec"
  SHIM_RECORD_DIR=$lw_rec ml launch --program alpha --kind worker --scope "$lw_scope" --brief "$tmp/brief.md" "$@"
}

# --- 1. --model/--effort apply to this launch alone -------------------------
launch_worker model-a "$tmp/rec-a" --model sonnet --effort low
if [ "$RC" = 0 ] && wait_for "$tmp/rec-a/argv"; then
  na=$(field name)
  case " $(cat "$tmp/rec-a/argv") " in
    *" --model sonnet --effort low "*) ok "--model/--effort set this launch's tier" ;;
    *) fail "the session's argv lacks --model sonnet --effort low: $(cat "$tmp/rec-a/argv")" ;;
  esac
  [ "$(field tier)" = sonnet/low ] && ok "the launch output reports the tier it applied" \
    || fail "the launch output reports tier '$(field tier)', not sonnet/low"
  awk -F "$TAB" '$1 == "tier" && $2 == "sonnet/low" { f = 1 } END { exit !f }' "$fleet/mission-control/sessions/$na" \
    && ok "the registry row's tier field records the chosen tier" || fail "the registry row does not record sonnet/low"
  ml list
  printf '%s\n' "$OUT" | awk -F "$TAB" -v n="$na" '$1 == n && $7 == "sonnet/low" { f = 1 } END { exit !f }' \
    && ok "list shows the chosen tier" || fail "list does not show sonnet/low for $na: $OUT"
  [ "$(cat "$fleet/streamjson/$na/tier_model" 2>/dev/null)" = sonnet ] && [ "$(cat "$fleet/streamjson/$na/tier_effort" 2>/dev/null)" = low ] \
    && ok "the launch records the chosen tier for a relaunch" || fail "tier_model/tier_effort were not recorded under the worker's state"
  wait_done "$na"
else
  fail "the --model launch exited $RC: $ERR"
fi
grep -qE 'allocation_(model|effort)_execution|fleet_(model|effort)_execution' "$tracked" \
  && fail "the --model launch wrote a knob" || ok "the --model launch wrote no knob or overlay"

# --- 2. the next launch, without the flags, keeps the knob's tier -----------
launch_worker model-b "$tmp/rec-b"
if [ "$RC" = 0 ] && wait_for "$tmp/rec-b/argv"; then
  case " $(cat "$tmp/rec-b/argv") " in
    *" --model opus --effort high "*) ok "a launch without the flags keeps its key's tier" ;;
    *) fail "a later launch did not keep opus/high: $(cat "$tmp/rec-b/argv")" ;;
  esac
  [ ! -e "$fleet/streamjson/$(field name)/tier_model" ] && ok "a launch without the flags records no override" \
    || fail "an override leaked into the next launch's state"
  wait_done "$(field name)"
else
  fail "the plain launch exited $RC: $ERR"
fi

# --- 3. an invalid value is refused before anything starts ------------------
before=$(find "$fleet/mission-control/sessions" -type f | wc -l)
for bad in 'gpt5' 'Opus' 'opus;x' '' 'inherit'; do
  launch_worker model-bad "$tmp/rec-bad" --model "$bad"
  [ "$RC" != 0 ] && printf '%s\n' "$ERR" | grep -q -- '--model' \
    && ok "--model '$bad' is refused naming the flag" || fail "--model '$bad' exited $RC: $ERR"
done
launch_worker model-bad "$tmp/rec-bad" --effort extreme
[ "$RC" != 0 ] && printf '%s\n' "$ERR" | grep -q -- '--effort' \
  && ok "--effort extreme is refused naming the flag" || fail "--effort extreme exited $RC: $ERR"
after=$(find "$fleet/mission-control/sessions" -type f | wc -l)
[ "$before" = "$after" ] && [ ! -e "$tmp/rec-bad/argv" ] && ok "a refused value starts nothing and reserves no name" \
  || fail "a refused value left a row or started a session"

# --- 4. a lowered tier is never silent --------------------------------------
PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-audit.sh" record usage-gate downshift test-seed "seed the rung" >"$tmp/seed.out" \
  || fail "seeding the downshift rung failed"
launch_worker model-lowered "$tmp/rec-lo"
if [ "$RC" = 0 ] && wait_for "$tmp/rec-lo/argv"; then
  case " $(cat "$tmp/rec-lo/argv") " in
    *" --model sonnet --effort medium "*) ok "above the downshift rung an ordinary launch is lowered (the policy stays)" ;;
    *) fail "the downshift did not lower the ordinary launch: $(cat "$tmp/rec-lo/argv")" ;;
  esac
  printf '%s\n' "$OUT" | awk -F "$TAB" '$1 == "launch" && $2 == "tier-note" && /opus\/high/ && /downshift/ { f = 1 } END { exit !f }' \
    && ok "the launch output says the tier was lowered, from what, and why" || fail "the lowered tier was not reported: $OUT"
  wait_done "$(field name)"
else
  fail "the launch under the downshift rung exited $RC: $ERR"
fi
launch_worker model-refused "$tmp/rec-re" --model fable
if [ "$RC" != 0 ] && printf '%s\n' "$ERR" | grep -q 'fable' && printf '%s\n' "$ERR" | grep -q -- '--reserved' && [ ! -e "$tmp/rec-re/argv" ]; then
  ok "a --model the downshift would lower is refused, naming --reserved"
else
  fail "an unreserved --model fable under the downshift was not refused as expected (exit $RC): $ERR"
fi
launch_worker model-reserved "$tmp/rec-rs" --model fable --reserved
if [ "$RC" = 0 ] && wait_for "$tmp/rec-rs/argv"; then
  nr=$(field name)
  case " $(cat "$tmp/rec-rs/argv") " in
    *" --model fable --effort high "*) ok "a reserved --model fable resolves to fable above the cap" ;;
    *) fail "a reserved fable launch did not run at fable/high: $(cat "$tmp/rec-rs/argv")" ;;
  esac
  rows=$(PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/allocation-ledger.sh" rows "mission-control:$nr")
  printf '%s\n' "$rows" | grep -q 'reserved' && printf '%s\n' "$rows" | grep -q 'fable' \
    && ok "the allocation ledger records the reserved override" || fail "the ledger lacks the reserved fable row: $rows"
  [ "$(cat "$fleet/streamjson/$nr/tier_reserved" 2>/dev/null)" = yes ] && ok "the reservation is recorded for a relaunch" \
    || fail "tier_reserved was not recorded"
  wait_done "$nr"
else
  fail "the reserved fable launch exited $RC: $ERR"
fi
launch_worker model-after "$tmp/rec-af"
if [ "$RC" = 0 ] && wait_for "$tmp/rec-af/argv"; then
  case " $(cat "$tmp/rec-af/argv") " in
    *" --model sonnet --effort medium "*) ok "an ordinary launch after the reserved one still downshifts" ;;
    *) fail "the reserved launch changed another launch: $(cat "$tmp/rec-af/argv")" ;;
  esac
  wait_done "$(field name)"
else
  fail "the follow-up launch exited $RC: $ERR"
fi

# --- 5. a one-launch overlay does not reach the worker ----------------------
mkdir -p "$tmp/rec-env"
SHIM_RECORD_DIR="$tmp/rec-env" ml launch --program alpha --kind ad-hoc --scope env-default --brief "$tmp/brief.md"
if [ "$RC" = 0 ] && wait_for "$tmp/rec-env/localcfg"; then
  [ "$(cat "$tmp/rec-env/localcfg")" = '<unset>' ] && ok "PLANWRIGHT_LOCAL_CONFIG does not reach the worker" \
    || fail "the worker inherited PLANWRIGHT_LOCAL_CONFIG='$(cat "$tmp/rec-env/localcfg")'"
  wait_done "$(field name)"
else
  fail "the env launch exited $RC: $ERR"
fi
mkdir -p "$tmp/rec-keep"
SHIM_RECORD_DIR="$tmp/rec-keep" ml launch --program alpha --kind ad-hoc --scope env-keep --brief "$tmp/brief.md" --keep-config-env
if [ "$RC" = 0 ] && wait_for "$tmp/rec-keep/localcfg"; then
  [ "$(cat "$tmp/rec-keep/localcfg")" = "$tmp/absent.yml" ] && ok "--keep-config-env passes the overlay variables on purpose" \
    || fail "--keep-config-env did not pass the overlay: '$(cat "$tmp/rec-keep/localcfg")'"
  wait_done "$(field name)"
else
  fail "the --keep-config-env launch exited $RC: $ERR"
fi

# --- 6. the tmux rung refuses what it cannot apply --------------------------
ml launch --program alpha --kind ad-hoc --scope model-tmux --brief "$tmp/brief.md" --backend tmux --model fable
[ "$RC" != 0 ] && printf '%s\n' "$ERR" | grep -q 'stream-json rung only' && ok "--model on the tmux rung is refused, not dropped" \
  || fail "--model on the tmux rung exited $RC: $ERR"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch model tests passed"
