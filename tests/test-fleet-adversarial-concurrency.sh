#!/bin/bash
# The multi-tower adversarial suite, concurrency half: N towers sweeping one
# fleet at once (fleet-lifecycle-closure Task 11; REQ-D1.6, REQ-D1.3,
# REQ-D1.4, REQ-K1.5).
#
# A reap is the sweep's terminating step, `fleet-cleanup.sh process`, so N
# towers sweeping in terminate mode is N actuators racing over the same
# candidates. Asserted on real workers on both rungs:
#   - no double-reap: N concurrent reaps of one worker close it once, and the
#     audit trail records one termination;
#   - no lost sweep: N sweepers walking several candidates in different orders
#     leave every candidate closed, each once;
#   - both again under induced contention: the fleet lock held across the
#     race, and a reap lock left behind by a killed reaper;
#   - N concurrent observing sweeps (the shipped mode) all complete, kill
#     nothing, and record every candidate.
# Every cell keeps the unit untouched and the strand standing, and the
# literal expected-cell manifest at the end must match what ran.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-adversarial-concurrency.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-adversarial-fixture.sh
. "$here/lib/fleet-adversarial-fixture.sh"

owner_is dead
N=6

# race <outdir> <worker>... — one actuator per argument, all started together
# behind a barrier, each one's exit code and result written under <outdir>.
race() {
  ra_dir=$1
  shift
  mkdir -p "$ra_dir"
  ra_go="$ra_dir/go"
  ra_i=0
  ra_pids=''
  for ra_w in "$@"; do
    ra_i=$((ra_i + 1))
    (
      while [ ! -e "$ra_go" ]; do sleep 0.01; done
      r=0
      decide -- fleet-cleanup.sh process "$ra_w" 'periodic sweep' 'concurrent towers' \
        --tower-id "$self_id" --grace 1 >"$ra_dir/out.$ra_i" 2>"$ra_dir/err.$ra_i" || r=$?
      printf '%s %s\n' "$ra_w" "$r" >"$ra_dir/rc.$ra_i"
    ) &
    ra_pids="$ra_pids $!"
  done
  : >"$ra_go"
  for p in $ra_pids; do wait "$p" || :; done
}

# race_ok <cell> <dir> — every racer either closed the worker, found it
# already closed, or stood down for the one closing it; none failed or
# reported a partial close.
race_ok() {
  for f in "$2"/rc.*; do
    read -r rw rr <"$f"
    n=${f##*.}
    case $rr/$(cat "$2/out.$n") in
      0/*"stop $rw stopped"* | 0/*"stop $rw already-closed"*) ;;
      5/*)
        grep -qE 'already in progress|changed while waiting' "$2/err.$n" \
          || fail "$1: racer $n on $rw refused for another reason: $(cat "$2/err.$n")"
        ;;
      *) fail "$1: racer $n on $rw exited $rr: $(cat "$2/out.$n") $(cat "$2/err.$n")" ;;
    esac
  done
}

# --- no double-reap, per rung ------------------------------------------------
sj_launch cA "$ev_done" "$peer_id"
cA_pids="$sup $wrk"
hl_launch 4 "$peer_id"
cB=$hw
cB_pids=$runner
attn heartbeat "$cB" demo:4 ended
wait_until 30 classified cA finished-but-unreaped || fail "fixture: cA never finished"
wait_until 30 classified "$cB" finished-but-unreaped || fail "fixture: $cB never finished"

for spec in "sj:cA" "hl:$cB"; do
  rung=${spec%%:*}
  w=${spec#*:}
  args=''
  for _ in $(seq 1 "$N"); do args="$args $w"; done
  # shellcheck disable=SC2086 # one argument per racer, by design
  race "$tmp/race-$rung" $args
  race_ok "conc:$rung:double-reap" "$tmp/race-$rung"
  [ "$(reaps_of "$w")" = 1 ] || fail "conc:$rung:double-reap: $N concurrent reaps recorded $(reaps_of "$w") terminations"
  case $rung in
    sj) pids=$cA_pids ;;
    hl) pids=$cB_pids ;;
  esac
  for p in $pids; do
    wait_until 10 gone "$p" || fail "conc:$rung:double-reap: pid $p survived $N concurrent reaps"
  done
  untouched "conc:$rung:double-reap"
  strand_intact "conc:$rung:double-reap"
  ran "conc:$rung:double-reap"
done
echo "ok: $N concurrent reaps of one worker close it once on each rung, with one termination record"

# --- no lost sweep: several candidates, sweepers in different orders --------
sj_launch cC1 "$ev_done" "$peer_id"
c1p="$sup $wrk"
sj_launch cC2 "$ev_done" "$peer_id"
c2p="$sup $wrk"
hl_launch 5 "$peer_id"
c3=$hw
c3p=$runner
attn heartbeat "$c3" demo:5 ended
for w in cC1 cC2 "$c3"; do
  wait_until 30 classified "$w" finished-but-unreaped || fail "fixture: $w never finished"
done
# Four sweepers released together, each walking all three candidates one
# after another from a different start, the way a terminating sweep does.
sweeper() {
  sw_dir=$1
  shift
  mkdir -p "$sw_dir"
  while [ ! -e "$tmp/lost-go" ]; do sleep 0.01; done
  sw_i=0
  for sw_w in "$@"; do
    sw_i=$((sw_i + 1))
    r=0
    decide -- fleet-cleanup.sh process "$sw_w" 'periodic sweep' 'concurrent towers' \
      --tower-id "$self_id" --grace 1 >"$sw_dir/out.$sw_i" 2>"$sw_dir/err.$sw_i" || r=$?
    printf '%s %s\n' "$sw_w" "$r" >"$sw_dir/rc.$sw_i"
  done
}
(sweeper "$tmp/lost-a" cC1 cC2 "$c3") &
la=$!
(sweeper "$tmp/lost-b" cC2 "$c3" cC1) &
lb=$!
(sweeper "$tmp/lost-c" "$c3" cC1 cC2) &
lc=$!
(sweeper "$tmp/lost-d" cC1 "$c3" cC2) &
ld=$!
: >"$tmp/lost-go"
wait "$la" "$lb" "$lc" "$ld" || :
for d in a b c d; do race_ok "conc:no-lost-sweep" "$tmp/lost-$d"; done
for w in cC1 cC2 "$c3"; do
  [ "$(reaps_of "$w")" = 1 ] || fail "conc:no-lost-sweep: $w has $(reaps_of "$w") terminations, expected exactly one"
done
for p in $c1p $c2p $c3p; do
  wait_until 10 gone "$p" || fail "conc:no-lost-sweep: pid $p was left running by every sweeper"
done
untouched "conc:no-lost-sweep"
strand_intact "conc:no-lost-sweep"
ran conc:no-lost-sweep
echo "ok: four sweepers over three candidates in different orders close each candidate exactly once, none lost"

# --- induced contention: the fleet lock held across the race ----------------
sj_launch cD "$ev_done" "$peer_id"
cDp="$sup $wrk"
wait_until 30 classified cD finished-but-unreaped || fail "fixture: cD never finished"
ienv -- fleet-state.sh lock || fail "fixture: could not take the fleet lock"
args=''
for _ in $(seq 1 "$N"); do args="$args cD"; done
# shellcheck disable=SC2086 # one argument per racer, by design
(race "$tmp/race-held" $args) &
rh=$!
sleep 2
ienv -- fleet-state.sh unlock || fail "fixture: could not release the fleet lock"
wait "$rh" || :
race_ok "conc:contended:fleet-lock" "$tmp/race-held"
[ "$(reaps_of cD)" = 1 ] || fail "conc:contended:fleet-lock: $(reaps_of cD) terminations under a held fleet lock"
for p in $cDp; do
  wait_until 10 gone "$p" || fail "conc:contended:fleet-lock: pid $p survived"
done
untouched "conc:contended:fleet-lock"
strand_intact "conc:contended:fleet-lock"
ran conc:contended:fleet-lock

# --- induced contention: a reap lock left by a killed reaper -----------------
# A reaper SIGKILLed mid-reap leaves its hold standing; the next sweep must
# break it on the holder's absence and close the worker, once.
sj_launch cE "$ev_done" "$peer_id"
cEp="$sup $wrk"
wait_until 30 classified cE finished-but-unreaped || fail "fixture: cE never finished"
sleep 0 &
dead_holder=$!
wait "$dead_holder" || :
mkdir -p "$ihome/reap-locks"
ln -s "$dead_holder-1700000000-1" "$ihome/reap-locks/cE"
args=''
for _ in $(seq 1 "$N"); do args="$args cE"; done
# shellcheck disable=SC2086 # one argument per racer, by design
race "$tmp/race-stale" $args
race_ok "conc:contended:stale-reap-lock" "$tmp/race-stale"
[ "$(reaps_of cE)" = 1 ] || fail "conc:contended:stale-reap-lock: $(reaps_of cE) terminations past a dead reaper's lock"
for p in $cEp; do
  wait_until 10 gone "$p" || fail "conc:contended:stale-reap-lock: pid $p survived"
done
[ ! -L "$ihome/reap-locks/cE" ] || fail "conc:contended:stale-reap-lock: the reap lock was left held"
untouched "conc:contended:stale-reap-lock"
strand_intact "conc:contended:stale-reap-lock"
ran conc:contended:stale-reap-lock
echo "ok: a held fleet lock and a dead reaper's lock each still yield exactly one termination"

# --- N concurrent observing sweeps ------------------------------------------
sj_launch cF "$ev_done" "$peer_id"
cFp="$sup $wrk"
hl_launch 6 "$peer_id"
cG=$hw
cGp=$runner
attn heartbeat "$cG" demo:6 ended
wait_until 30 classified cF finished-but-unreaped || fail "fixture: cF never finished"
wait_until 30 classified "$cG" finished-but-unreaped || fail "fixture: $cG never finished"
before=$(reaps_recorded)
sw_pids=''
for i in $(seq 1 4); do
  (
    r=0
    decide -- fleet-sweep.sh --repo "$main_repo" --tower-id "$self_id" >"$tmp/sweep.$i" 2>"$tmp/sweep-err.$i" || r=$?
    printf '%s\n' "$r" >"$tmp/sweep-rc.$i"
  ) &
  sw_pids="$sw_pids $!"
done
for p in $sw_pids; do wait "$p" || :; done
for i in 1 2 3 4; do
  [ "$(cat "$tmp/sweep-rc.$i")" = 0 ] || fail "conc:observing-sweeps: sweep $i exited $(cat "$tmp/sweep-rc.$i"): $(cat "$tmp/sweep-err.$i")"
done
[ "$(reaps_recorded)" = "$before" ] || fail "conc:observing-sweeps: an observing sweep recorded a termination"
for p in $cFp $cGp; do
  alive "$p" || fail "conc:observing-sweeps: an observing sweep terminated pid $p"
done
observed=$(ienv -- fleet-audit.sh query --mechanism process-cleanup 2>/dev/null | awk -F'\t' '$4 == "would-cleanup"')
for w in cF "$cG"; do
  printf '%s\n' "$observed" | grep -q "worker=$w " \
    || fail "conc:observing-sweeps: no sweep recorded $w, so every one of them lost it"
done
untouched "conc:observing-sweeps"
strand_intact "conc:observing-sweeps"
ran conc:observing-sweeps
echo "ok: four concurrent observing sweeps complete, kill nothing, and record every candidate"

nollm_check
ran nollm:concurrent-paths

manifest_check "
conc:sj:double-reap
conc:hl:double-reap
conc:no-lost-sweep
conc:contended:fleet-lock
conc:contended:stale-reap-lock
conc:observing-sweeps
nollm:concurrent-paths
"
echo "ok: every cell in the expected-cell manifest ran, and no other"
