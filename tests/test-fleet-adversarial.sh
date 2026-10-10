#!/bin/bash
# The multi-tower adversarial matrix: every destructive verb against real
# workers on both session-grade rungs, crossed with the owning tower's
# liveness and the worker session's state (fleet-lifecycle-closure Task 11;
# REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.7, REQ-D1.8, REQ-D1.9,
# REQ-B1.4, REQ-J1.4, REQ-K1.5).
#
# The verbs: the cleanup class's reap (`fleet-cleanup.sh process`) of a worker
# on each rung, the periodic sweep's reap pass, and each rung's own `stop`.
# The axes for a reap: the owning tower {live, dead, unknown, errored} — what
# the presence surface answers, the one scripted surface — crossed with the
# session {ended, running, unknown}, plus a live peer's worker whose session
# is positively dead. Only a dead owner crossed with an ended session reaps;
# a live peer's worker is refused under every session state; every other cell
# refuses with the axis it lacked named.
#
# On every cell, refusals included: the unit's fence ref, its branch tip and
# its worktree (uncommitted work too) are byte-identical, and the strand entry
# surfaced for the operator survives untouched. A refused worker is still
# running and no termination is recorded for it.
#
# Completeness is enforced by the literal expected-cell manifest at the end: a
# cell that stops running, or a new one run without being listed, fails.
#
# Closing assertions: no decision-path run reached an outbound client (a
# runtime recorder with a positive control, and a source audit), presence is
# read only for attribution, and nothing here added a second registry,
# presence or exclusion store.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-adversarial.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-adversarial-fixture.sh
. "$here/lib/fleet-adversarial-fixture.sh"

# --- the workers -------------------------------------------------------------
# Per rung: one whose session ended (finished, never exited), one running, one
# whose session no probe can establish, one whose processes are gone. Every
# one is owned by the peer tower, so presence alone decides the tower axis.

sj_launch sjE "$ev_done" "$peer_id"
sjE_sup=$sup
sjE_wrk=$wrk
sj_launch sjR "$ev_init" "$peer_id"
sjR_sup=$sup
sjR_wrk=$wrk
sj_launch sjU "$ev_init" "$peer_id"
sjU_sup=$sup
sjU_wrk=$wrk
unobservable sjU
sj_launch sjD "$ev_init" "$peer_id"
kill -9 "$sup" "$wrk" 2>/dev/null
wait_until 30 gone "$sup" || fail "fixture: sjD's supervisor survived SIGKILL"

hl_launch 4 "$peer_id"
hlE=$hw
hlE_run=$runner
attn heartbeat "$hlE" demo:4 ended
hl_launch 5 "$peer_id"
hlR=$hw
hlR_run=$runner
attn heartbeat "$hlR" demo:5 working
hl_launch 6 "$peer_id"
hlU=$hw
hlU_run=$runner
unobservable "$hlU"
hl_launch 7 "$peer_id"
hlD=$hw
kill -9 "$runner" 2>/dev/null
wait_until 30 gone "$runner" || fail "fixture: $hlD's runner survived SIGKILL"

for w in sjE:finished-but-unreaped sjR:working sjU:unclassified sjD:dead \
  "$hlE:finished-but-unreaped" "$hlR:working" "$hlU:unclassified" "$hlD:dead"; do
  wait_until 30 classified "${w%%:*}" "${w#*:}" || fail "fixture: ${w%%:*} never classified ${w#*:}"
done

# pids_of <worker> — the processes a refusal must leave running.
pids_of() {
  case $1 in
    sjE) echo "$sjE_sup $sjE_wrk" ;;
    sjR) echo "$sjR_sup $sjR_wrk" ;;
    sjU) echo "$sjU_sup $sjU_wrk" ;;
    "$hlE") echo "$hlE_run" ;;
    "$hlR") echo "$hlR_run" ;;
    "$hlU") echo "$hlU_run" ;;
    *) echo "" ;;
  esac
}

# worker_for <rung> <session> — the fixture worker carrying that session.
worker_for() {
  case $1/$2 in
    sj/ended) echo sjE ;;
    sj/running) echo sjR ;;
    sj/unknown) echo sjU ;;
    sj/dead) echo sjD ;;
    hl/ended) echo "$hlE" ;;
    hl/running) echo "$hlR" ;;
    hl/unknown) echo "$hlU" ;;
    hl/dead) echo "$hlD" ;;
  esac
}

# --- reap cells: refusals ----------------------------------------------------
# refusal_cell <rung> <tower> <session> <exit> <reason-text>
refusal_cell() {
  rc_w=$(worker_for "$1" "$3")
  case $2 in
    errored) owner_is ERRORED ;;
    *) owner_is "$2" ;;
  esac
  rc_before=$(reaps_of "$rc_w")
  icleanup "$rc_w"
  rc_cell="reap:$1:$2:$3"
  [ "$rc" = "$4" ] || fail "$rc_cell: exit $rc, expected $4 ($err)"
  case $err in
    *"$5"*) ;;
    *) fail "$rc_cell: the refusal does not name what was missing ('$5'): $err" ;;
  esac
  for p in $(pids_of "$rc_w"); do
    alive "$p" || fail "$rc_cell: a refused reap terminated pid $p"
  done
  [ "$(reaps_of "$rc_w")" = "$rc_before" ] || fail "$rc_cell: a refused reap was recorded as a termination"
  untouched "$rc_cell"
  strand_intact "$rc_cell"
  ran "$rc_cell"
}

for rung in sj hl; do
  # A live peer's worker is refused under every session state, a positively
  # dead session included.
  for session in ended running unknown dead; do
    refusal_cell "$rung" live "$session" 7 'live peer'
  done
  for tower in unknown errored; do
    for session in ended running unknown; do
      refusal_cell "$rung" "$tower" "$session" 5 'no positive evidence its owning tower is gone'
    done
  done
  for session in running unknown; do
    refusal_cell "$rung" dead "$session" 5 'no positive evidence its session ended'
  done
done
echo "ok: every refusal cell, on both rungs, terminates nothing, records no reap, and leaves the fence, branch, worktree and strand untouched"

# --- print units: registered, never reaped ------------------------------------
ienv PLANWRIGHT_TOWER_ID="$peer_id" -- fleet-register.sh --handle wprint --scope demo:6 \
  --backend print --state-dir "$wt" --death-handle none >/dev/null 2>&1 \
  || fail "fixture: the print record was not written"
for tower in dead live; do
  owner_is "$tower"
  icleanup wprint
  [ "$rc" = 8 ] || fail "reap:print:$tower: exit $rc, expected 8 ($err)"
  case $err in
    *print*) ;;
    *) fail "reap:print:$tower: the refusal does not name the print exemption: $err" ;;
  esac
  untouched "reap:print:$tower"
  strand_intact "reap:print:$tower"
  ran "reap:print:$tower"
done
echo "ok: a print unit is refused with its own exemption under a dead and a live owner"

# --- the sweep's reap pass, observing ---------------------------------------
owner_is dead
rc=0
decide -- fleet-sweep.sh --repo "$main_repo" --tower-id "$self_id" >"$tmp/out" 2>"$tmp/err" || rc=$?
out=$(cat "$tmp/out")
[ "$rc" = 0 ] || fail "sweep: exit $rc ($(cat "$tmp/err"))"
reap_line() {
  printf '%s\n' "$out" | awk -F'\t' -v w="$1" '$1 == "reap" && $2 == w { print $3 }'
}
for w in sjE "$hlE"; do
  [ "$(reap_line "$w")" = observed ] || fail "sweep: $w was not observed: $out"
done
# A print unit is never a reap candidate; were it one, the actuator declines it.
case $(reap_line wprint) in
  '' | declined) ;;
  *) fail "sweep: the print unit was acted on: $out" ;;
esac
for p in "$sjE_sup" "$sjE_wrk" "$hlE_run"; do
  alive "$p" || fail "sweep: the observing sweep terminated pid $p"
done
[ "$(reaps_recorded)" = 0 ] || fail "sweep: the observing sweep recorded a termination"
for c in sweep:sj:observe sweep:hl:observe sweep:print:declined; do
  untouched "$c"
  strand_intact "$c"
  ran "$c"
done
echo "ok: the observing sweep records the dead owner's ended workers, kills nothing, declines the print unit, and touches no unit"

# --- reap cells: the one that reaps, per rung --------------------------------
owner_is dead
attn heartbeat sjE demo:4 ended
icleanup sjE
[ "$rc" = 0 ] || fail "reap:sj:dead:ended: exit $rc ($err)"
if ! gone "$sjE_sup" || ! gone "$sjE_wrk"; then
  fail "reap:sj:dead:ended: the worker survived the reap"
fi
[ "$(reaps_of sjE)" = 1 ] || fail "reap:sj:dead:ended: expected one termination record, got $(reaps_of sjE)"
grep -q "^sjE$tab" "$store" && fail "reap:sj:dead:ended: the worker's attention row was not released"
untouched "reap:sj:dead:ended"
strand_intact "reap:sj:dead:ended"
ran reap:sj:dead:ended

icleanup "$hlE"
[ "$rc" = 0 ] || fail "reap:hl:dead:ended: exit $rc ($err)"
wait_until 10 gone "$hlE_run" || fail "reap:hl:dead:ended: the runner survived the reap"
[ "$(reaps_of "$hlE")" = 1 ] || fail "reap:hl:dead:ended: expected one termination record, got $(reaps_of "$hlE")"
grep -q "^$hlE$tab" "$store" && fail "reap:hl:dead:ended: the worker's attention row was not released"
untouched "reap:hl:dead:ended"
strand_intact "reap:hl:dead:ended"
ran reap:hl:dead:ended
echo "ok: only a dead owner's ended worker is reaped, once, on each rung; the strand survives and the unit is untouched"

# --- each rung's own stop ----------------------------------------------------
# stop_cells <rung> <worker> <pids...> — close, repeat, refuse a hostile handle.
stop_cells() {
  sc_rung=$1
  sc_w=$2
  shift 2
  case $sc_rung in
    sj) sc_s=fleet-streamjson.sh ;;
    hl) sc_s=fleet-dispatch-headless.sh ;;
  esac
  sc_rc=0
  sc_out=$(decide -- "$sc_s" stop "$sc_w" --grace 1 2>&1) || sc_rc=$?
  [ "$sc_rc" = 0 ] || fail "stop:$sc_rung:close: exit $sc_rc ($sc_out)"
  case $sc_out in
    *"stop $sc_w stopped released="*process*) ;;
    *) fail "stop:$sc_rung:close: unexpected result: $sc_out" ;;
  esac
  for p in "$@"; do
    wait_until 10 gone "$p" || fail "stop:$sc_rung:close: pid $p survived"
  done
  untouched "stop:$sc_rung:close"
  strand_intact "stop:$sc_rung:close"
  ran "stop:$sc_rung:close"
  sc_rc=0
  sc_out=$(decide -- "$sc_s" stop "$sc_w" --grace 1 2>&1) || sc_rc=$?
  [ "$sc_rc" = 0 ] || fail "stop:$sc_rung:repeat: exit $sc_rc ($sc_out)"
  case $sc_out in
    *"stop $sc_w already-closed"*) ;;
    *) fail "stop:$sc_rung:repeat: a repeat stop did not report already-closed: $sc_out" ;;
  esac
  untouched "stop:$sc_rung:repeat"
  strand_intact "stop:$sc_rung:repeat"
  ran "stop:$sc_rung:repeat"
  sc_rc=0
  decide -- "$sc_s" stop '../demo' --grace 1 >/dev/null 2>&1 || sc_rc=$?
  [ "$sc_rc" = 2 ] || fail "stop:$sc_rung:refuse-handle: a traversal handle exited $sc_rc"
  untouched "stop:$sc_rung:refuse-handle"
  strand_intact "stop:$sc_rung:refuse-handle"
  ran "stop:$sc_rung:refuse-handle"
}
stop_cells sj sjR "$sjR_sup" "$sjR_wrk"
stop_cells hl "$hlR" "$hlR_run"
echo "ok: each rung's stop closes, repeats as already-closed, and refuses a hostile handle, never touching the unit"

# --- presence is attribution, never authority -------------------------------
S="$here/../scripts"
strip() { sed -E -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//' "$1"; }
for f in orchestrate-select.sh orchestrate-meta-select.sh orchestrate-marker.sh orchestrate-marker-home.sh orchestrate-lock.sh \
  fleet-dispatch-worktree.sh fleet-dispatch-headless.sh fleet-streamjson.sh offload-dispatch.sh \
  flight-dispatch.sh fleet-registry-reconcile.sh fleet-cleanup.sh fleet-sweep.sh fleet-stop-lib.sh; do
  [ -f "$S/$f" ] || fail "presence audit: $f is gone; update the audited set"
  strip "$S/$f" | grep -q 'fleet-presence' \
    && fail "presence audit: $f reads the presence surface; dispatch, exclusion and reap decisions take presence only through the detector's owner attribution"
done
# Where presence is called, it is asked who a tower is, whether it is alive,
# or who is around: the attribution questions. Nothing asks it to decide or
# exclude. Call sites are the quoted script path or its variable.
# shellcheck disable=SC2016 # the scripts' own source text, matched literally
verbs=$(for f in "$S"/*.sh; do strip "$f"; done \
  | grep -oE '("\$FP"|fleet-presence\.sh") [a-z-]+' | awk '{ print $2 }' | sort -u)
[ -n "$verbs" ] || fail "presence audit: found no presence call site at all (the scan has drifted)"
for v in $verbs; do
  case $v in
    identity | liveness | attribute | publish | discover) ;;
    *) fail "presence audit: a script asks presence '$v', which is not an attribution question" ;;
  esac
done
ran presence:off-correctness-path
echo "ok: presence is read only through attribution questions, and no dispatch, exclusion or reap script reads it directly"

# --- one registry, one presence, one exclusion object -----------------------
# The reconcile writes the registry only through the register seam, and no
# script this bundle ships keeps a second inventory or fence.
# shellcheck disable=SC2016 # the script's own source text, matched literally
strip "$S/fleet-registry-reconcile.sh" | grep -nE '>>?[[:space:]]*"?\$(root|dir)/registry|fleet-state\.sh"? (register|retire)|"\$FS" (register|retire)' \
  && fail "store audit: the reconcile writes the registry itself"
# The cleanup actuator's worktree class removes worktrees by design; its
# process arm, the reap, is the part audited.
parm=$(awk '/^  process\)$/ { on = 1 } on { print } on && /^    ;;$/ { exit }' "$S/fleet-cleanup.sh" \
  | sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//')
[ -n "$parm" ] || fail "store audit: no process arm found in fleet-cleanup.sh"
touches='refs/planwright-fence|git[^|]* (update-ref|push|branch -[dD]|worktree remove)'
printf '%s\n' "$parm" | grep -nE "$touches" && fail "store audit: the reap arm touches a fence, a branch or a worktree"
for f in fleet-registry-reconcile.sh fleet-sweep.sh fleet-stop-lib.sh fleet-register.sh; do
  strip "$S/$f" | grep -nE "$touches" && fail "store audit: $f touches a fence, a branch or a worktree"
done
ran store:no-second-mechanism
echo "ok: the reconcile writes the registry only through the register seam, and no reap path touches a fence, branch or worktree"

# --- no model or API call on any decision path ------------------------------
nollm_check
# Every fleet script and the lock library, less the ones whose job is to start
# a worker session (or to print the command for one): the launch is the worker,
# not a decision. Their decision paths are covered by the runtime recorder.
# Each exemption must still match, so a stale one fails here.
launchers='fleet-dispatch-headless.sh fleet-dispatch-worktree.sh fleet-tower-signpost.sh fleet-tower-watchdog.sh'
client='(^|[^A-Za-z0-9_./-])(claude|anthropic|curl|wget)([[:space:]]|$|")|api\.anthropic'
for p in "$S"/fleet-*.sh "$S/lock-lib.sh"; do
  f=${p##*/}
  hits=$(strip "$p" | grep -nE "$client" || :)
  case " $launchers " in
    *" $f "*)
      [ -n "$hits" ] || fail "no-LLM audit: $f is exempt as a launcher but launches nothing; drop the exemption"
      ;;
    *) [ -z "$hits" ] || fail "no-LLM audit: $f reaches a model or network client: $hits" ;;
  esac
done
for f in fleet-stuck-detector.sh fleet-registry-reconcile.sh fleet-register.sh fleet-stop-lib.sh fleet-sweep.sh; do
  strip "$S/$f" | grep -nE '(^|[^A-Za-z0-9_./-])gh([[:space:]]|$)' \
    && fail "no-LLM audit: $f queries the forge on a decision path"
done
printf '%s\n' "$parm" | grep -nE '(^|[^A-Za-z0-9_./-])(gh|claude|curl|wget)([[:space:]]|$)' \
  && fail "no-LLM audit: the reap arm reaches a model or network client"
ran nollm:decision-paths
echo "ok: no decision path invoked a model or network client (runtime recorder with a positive control, and a source audit)"

# --- the expected-cell manifest ---------------------------------------------
manifest_check "
reap:sj:live:ended
reap:sj:live:running
reap:sj:live:unknown
reap:sj:live:dead
reap:sj:unknown:ended
reap:sj:unknown:running
reap:sj:unknown:unknown
reap:sj:errored:ended
reap:sj:errored:running
reap:sj:errored:unknown
reap:sj:dead:running
reap:sj:dead:unknown
reap:sj:dead:ended
reap:hl:live:ended
reap:hl:live:running
reap:hl:live:unknown
reap:hl:live:dead
reap:hl:unknown:ended
reap:hl:unknown:running
reap:hl:unknown:unknown
reap:hl:errored:ended
reap:hl:errored:running
reap:hl:errored:unknown
reap:hl:dead:running
reap:hl:dead:unknown
reap:hl:dead:ended
reap:print:dead
reap:print:live
sweep:sj:observe
sweep:hl:observe
sweep:print:declined
stop:sj:close
stop:sj:repeat
stop:sj:refuse-handle
stop:hl:close
stop:hl:repeat
stop:hl:refuse-handle
presence:off-correctness-path
store:no-second-mechanism
nollm:decision-paths
"
echo "ok: every cell in the expected-cell manifest ran, and no other"
