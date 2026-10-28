#!/bin/bash
# Tests for scripts/mc-handover.sh — mission control's succession, from the
# trigger to the resume (mission-control REQ-A1.1, REQ-A1.7, REQ-B1.7,
# REQ-L1.3, REQ-L1.5, REQ-L1.6). Successors launch on the stream-json rung
# against a CLI shim that reads its first message and exits, so each
# registry row is real and each retire goes through the launcher.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
tab=$(printf '\t')
suite=test-mc-handover

# shellcheck source=tests/lib/mc-handover-fixture.sh
. "$here/lib/mc-handover-fixture.sh"

run mc-rules.sh add alpha --text "Never hand the operator a pane" --subject panes --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the rule was not added: $ERR"
run mc-kb.sh init --program alpha
[ "$RC" = 0 ] || fail "fixture: the knowledge base was not initialised: $ERR"
run mc-rules.sh load alpha
digest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#digest}" = 64 ] || fail "fixture: no rules digest from the load: $OUT"
printf '%s\n' "item q-1" "session mc-worker-1" >"$tmp/picture"
printf '%s\n' "item q-1" >"$tmp/picture-short"
: >"$tmp/empty"

# ---------------------------------------------------------------------------
# REQ-L1.3, REQ-L1.5: each trigger source fires from its fixture; the
# compaction ceiling fires whatever the other two read.
# ---------------------------------------------------------------------------
ho due --program alpha --context 70 --wakes 0 --compactions 0
[ "$OUT" = "due${tab}context at 70%" ] && ok "context at the threshold triggers the handover" || fail "context at 70: $OUT $ERR"
ho due --program alpha --context 69 --wakes 999 --compactions 0
[ "$OUT" = not-due ] && ok "a context reading below the threshold is not due, whatever the wakes" || fail "context at 69: $OUT"
ho due --program alpha --context - --wakes 150 --compactions 0
[ "$OUT" = "due${tab}150 wakes" ] && ok "with no context reading the wake count triggers it" || fail "150 wakes: $OUT $ERR"
ho due --program alpha --context - --wakes 149 --compactions 1
[ "$OUT" = not-due ] && ok "below every threshold it is not due" || fail "149 wakes: $OUT"
ho due --program alpha --context 5 --wakes 0 --compactions 2
[ "$OUT" = "due${tab}2 compactions" ] && ok "the compaction ceiling fires regardless of the other two" || fail "2 compactions: $OUT"

# ---------------------------------------------------------------------------
# A first start: no holder, so a plain launch runs and takes the name.
# ---------------------------------------------------------------------------
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "the first launch exited $RC: $ERR"
n1=$(col successor 2)
wait_done "$n1"
grep -qF 'Run program alpha.' "$fleet/mission-control/launch/$n1/brief.md" \
  && grep -qF 'no handover file' "$fleet/mission-control/launch/$n1/brief.md" \
  && ok "the successor's brief carries the brief and its succession note" \
  || fail "the composed brief lacks the brief or the note"
ho verify --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest" --ledger - --durable "$tmp/picture"
[ "$RC" = 0 ] && ok "a first start verifies against the durable picture" || fail "the first verify exited $RC: $OUT $ERR"
ho take --program alpha --session "$n1" --window 1s
[ "$(col took 2)" = "$n1" ] && [ "$(col took 3)" = - ] && ok "the first start takes the name from nobody" || fail "the first take: $RC $OUT $ERR"
holder_is "the name resolves to the first session" "$n1"

# ---------------------------------------------------------------------------
# REQ-A1.1: a launch with neither the ask nor a live handover refuses,
# naming the holder.
# ---------------------------------------------------------------------------
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "a second unattended start is refused (exit 3)" || fail "a second start exited $RC: $OUT"
case $ERR in *"held by $n1"*) ok "the refusal names the holder" ;; *) fail "the refusal does not name $n1: $ERR" ;; esac
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a handover launch with no handover file is refused" || fail "a fileless handover exited $RC"
case $ERR in *"$n1"*) ok "that refusal names the holder too" ;; *) fail "the fileless refusal does not name $n1: $ERR" ;; esac
ho write --program alpha --session mc-not-holder --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 1 ] && ok "only the holder writes the handover file" || fail "a non-holder's write exited $RC"

# ---------------------------------------------------------------------------
# REQ-L1.6: the handover file carries its format; a successor refuses one
# whose format it does not know; a failed self-check keeps the predecessor.
# ---------------------------------------------------------------------------
run mc-kb.sh append decisions --program alpha --subject fixture --act "merged nothing" --no-reversal
led1=$(printf '%s\n' "$OUT" | head -n 1)
ho write --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "the holder's write exited $RC: $ERR"
hf="$home/handover.tsv"
[ "$(head -n 1 "$hf")" = "format${tab}1" ] && ok "the handover file opens with its format field" || fail "the file opens with '$(head -n 1 "$hf")'"
grep -qx "ledger${tab}$led1" "$hf" && grep -qx "predecessor${tab}$n1" "$hf" && grep -qx "item${tab}q-1" "$hf" \
  && grep -qx "session${tab}mc-worker-1" "$hf" \
  && ok "it records the last ledger sequence, the predecessor, the open items and the live sessions" || fail "the file is incomplete: $(cat "$hf")"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 0 ] || fail "the handover launch exited $RC: $ERR"
grep -qF "the handover file is $hf" "$fleet/mission-control/launch/$(col successor 2)/brief.md" \
  && ok "the successor's brief names the handover file" || fail "the successor's brief lacks the handover file's path"
n2=$(col successor 2)
wait_done "$n2"
[ "$n2" != "$n1" ] && ok "the successor has a name of its own" || fail "the successor reused $n1"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a second successor is refused while one is pending" || fail "a second successor exited $RC"

cp "$hf" "$tmp/hf.keep"
{
  printf 'format\t9\n'
  tail -n +2 "$tmp/hf.keep"
} >"$hf"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 1 ] && ok "a handover file of an unknown format is refused" || fail "the unknown format exited $RC"
case $OUT in *"format field is 9"*) ok "the refusal names the format field" ;; *) fail "the refusal does not name the format: $OUT" ;; esac
cp "$tmp/hf.keep" "$hf"

before=$(count_of handover-failed)
ho verify --program alpha --session "$n2" --picture "$tmp/picture-short" --digest "$digest" --ledger "$led1"
[ "$RC" = 1 ] && ok "a self-check missing a live session fails" || fail "the short picture exited $RC: $OUT"
case $OUT in "item${tab}"*mc-worker-1*) ok "it prints the item naming what is missing" ;; *) fail "no item line names the session: $OUT" ;; esac
[ "$(count_of handover-failed)" = $((before + 1)) ] && ok "the failed self-check raises one operator item" || fail "the self-check failure raised no item"
other=$(printf '%064d' 0)
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$other" --ledger "$led1"
[ "$RC" = 1 ] && ok "rules that are not the predecessor's fail the self-check" || fail "the digest mismatch exited $RC"
case $OUT in "item${tab}handover${tab}rules${tab}"*) ok "the item names the rules" ;; *) fail "no rules item: $OUT" ;; esac
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger -
[ "$RC" = 1 ] && ok "a ledger position behind the predecessor's last entry fails" || fail "the stale ledger exited $RC"
case $OUT in "item${tab}handover${tab}ledger${tab}"*) ok "the item names the ledger" ;; *) fail "no ledger item: $OUT" ;; esac
ho take --program alpha --session "$n2" --window 1s
[ "$RC" = 1 ] && ok "an unverified successor cannot take the name" || fail "an unverified take exited $RC"
holder_is "after the failed self-check the predecessor keeps the name" "$n1"
[ -f "$(rowfile "$n1")" ] && ok "and its registry row stays" || fail "the predecessor's row went"

# ---------------------------------------------------------------------------
# REQ-L1.6, REQ-A1.1: the predecessor releases after the successor's pass;
# the name moves, the predecessor's row goes, the successor announces.
# ---------------------------------------------------------------------------
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 0 ] && ok "the successor's self-check matches the handover file" || fail "the matching verify exited $RC: $OUT $ERR"
ho release --program alpha --session "$n1"
[ "$RC" = 0 ] && [ "$(col released 3)" = "$n2" ] && ok "the predecessor releases the name to the verified successor" || fail "release: $RC $OUT $ERR"
ho take --program alpha --session "$n2" --window 5s
[ "$RC" = 0 ] || fail "the take exited $RC: $OUT $ERR"
[ "$(col took 4)" = released ] && ok "the successor takes the name on the release" || fail "the take did not see the release: $OUT"
[ "$(col retire 3)" = released ] && [ ! -f "$(rowfile "$n1")" ] && ok "the predecessor's registry row is gone" || fail "the predecessor was not retired: $OUT"
[ -n "$(col line 2)" ] && [ "$(printf '%s\n' "$OUT" | grep -c "^line$tab")" = 1 ] && ok "the operator sees one line" || fail "not one line: $OUT"
holder_is "the name resolves to the successor only" "$n2"
[ -n "$(events_of mission-control-announce)" ] && ok "the successor announces itself" || fail "no announce event"
[ ! -f "$hf" ] && ok "the consumed handover file is gone" || fail "the handover file outlived the take"

# A file naming a predecessor already retired authorises nothing.
cp "$tmp/hf.keep" "$hf"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a handover file naming a retired predecessor is refused" || fail "the stale file exited $RC"
case $ERR in *"held by $n2"*) ok "that refusal names the holder" ;; *) fail "the stale-file refusal does not name $n2: $ERR" ;; esac
rm -f "$hf"

# ---------------------------------------------------------------------------
# REQ-A1.7: a predecessor that cannot release within the window is retired
# by the successor.
# ---------------------------------------------------------------------------
ho write --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest"
ho launch --program alpha --brief "$tmp/brief.md" --handover
n3=$(col successor 2)
wait_done "$n3"
ho verify --program alpha --session "$n3" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 0 ] || fail "the third verify exited $RC: $OUT $ERR"
[ -f "$(rowfile "$n2")" ] || fail "fixture: the predecessor's row is missing before the hung take"
before=$(count_of handover-requested)
ho take --program alpha --session "$n3" --window 1s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && ok "a predecessor silent past the window is retired" || fail "the hung take: $RC $OUT $ERR"
[ "$(col retire 3)" = released ] && ok "the launcher retired it" || fail "the hung predecessor's retire line: $OUT"
[ "$(count_of handover-requested)" = $((before + 1)) ] && ok "the take asked the live predecessor to release" || fail "no handover-requested event for the take"
[ ! -f "$(rowfile "$n2")" ] && ok "the hung predecessor's row is gone" || fail "the hung predecessor's row stayed"
holder_is "the name resolves to the successor" "$n3"

# ---------------------------------------------------------------------------
# REQ-A1.7: resume by name in the operator's session: what changed since the
# last operator turn, an announcement to every live session, the holder
# releasing on request.
# ---------------------------------------------------------------------------
run mission-control-launch.sh launch --program alpha --kind worker --scope fixture-worker --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the worker did not launch: $ERR"
worker=$(printf '%s\n' "$OUT" | awk -F '\t' '$2 == "name" { print $3 }')
wait_done "$worker"
run mc-kb.sh append decisions --program alpha --subject "before the last turn" --act "held a branch" --no-reversal
sleep 1
run mc-panel.sh presence --program alpha --prompt --now "$(date +%s)"
[ "$RC" = 0 ] || fail "fixture: the presence marker was not written: $ERR"
sleep 1
run mc-kb.sh append decisions --program alpha --subject "after the last turn" --act "retargeted a branch" --no-reversal
ho resume --program alpha --session operator-term --picture "$tmp/picture-short" --digest "$digest" --durable "$tmp/picture"
[ "$RC" = 1 ] && ok "a resume whose self-check fails is refused" || fail "the failing resume exited $RC"
holder_is "and the name stays where it was" "$n3"
(
  n=0
  until [ -f "$fleet/mission-control/alpha/release-request" ] || [ "$n" -ge 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  RUN_ERR="$tmp/stderr-helper" run mc-handover.sh release --program alpha --session "$n3"
) &
helper=$!
ho resume --program alpha --session operator-term --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 10s
wait "$helper"
[ "$RC" = 0 ] || fail "the resume exited $RC: $OUT $ERR"
[ "$(col took 3)" = "$n3" ] && [ "$(col took 4)" = released ] && ok "the holder releases the name on the resume's request" || fail "the resume did not see the release: $OUT"
[ ! -f "$(rowfile "$n3")" ] && ok "the released holder's row is gone" || fail "the released holder's row stayed"
case $OUT in *"changed${tab}decision${tab}"*"after the last turn${tab}retargeted a branch"*) ok "the resume reports what changed since the last turn" ;; *) fail "no change reported: $OUT" ;; esac
case $OUT in *"held a branch"* | *"merged nothing"*) fail "a decision before the last turn was reported as changed" ;; *) ok "a decision before the last turn is not reported" ;; esac
case $OUT in *"announce${tab}$worker"*) ok "it announces itself to every live session" ;; *) fail "the worker was not announced to: $OUT" ;; esac
[ -n "$(events_of handover-requested)" ] && ok "the request reached the holder as an event" || fail "no handover-requested event"
holder_is "the name resolves to the operator's session" operator-term
# A session without the mod writes no lease, so nothing proves it gone.
ho holder --program alpha
[ "$(col holder 6)" = live ] && ok "an attended holder with no lease counts as live" || fail "the leaseless holder: $OUT"
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "so a plain launch over it is refused" || fail "a launch over the leaseless holder exited $RC"
mkdir -p "$fleet/mission-control/alpha/leases"
printf "%s\n" "$(($(date +%s) - 600))" >"$fleet/mission-control/alpha/leases/operator-term"
ho holder --program alpha
[ "$(col holder 6)" = stale ] && ok "a lease older than the bound makes it stale" || fail "the old lease: $OUT"

# ---------------------------------------------------------------------------
# REQ-L1.6: where the holder is the operator's own session the
# harness cannot swap it, so the handover is one operator act on the panel.
# ---------------------------------------------------------------------------
printf "%s\n" "$(date +%s)" >"$fleet/mission-control/alpha/leases/operator-term"
ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "an attended holder's path is the operator's act" || fail "path: $OUT $ERR"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 4 ] && ok "no successor is launched over an attended holder" || fail "a launch over the attended holder exited $RC"
ho offer --program alpha
[ "$RC" = 0 ] && [ -n "$(events_of handover-act)" ] && ok "the act is offered as an operator item" || fail "offer: $RC $OUT $ERR"

# A record's handles reach paths and the launcher, so one outside the
# grammar is refused, never followed.
printf 'format\t1\nsession\tmc-x\npredecessor\t../../escape\npredecessor-kind\tregistry\nlaunched\t1\nmode\thandover\nverified\t1\n' \
  >"$fleet/mission-control/alpha/successor"
ho take --program alpha --session mc-x --window 1s
[ "$RC" = 1 ] && ok "a successor record naming a handle outside the grammar is refused" || fail "the tampered record's take exited $RC: $OUT"
holder_is "and the name stays put" operator-term

echo
if [ "$failures" -gt 0 ]; then
  echo "test-mc-handover: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-handover: all passed"
