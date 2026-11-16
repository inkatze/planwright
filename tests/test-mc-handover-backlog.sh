#!/bin/bash
# Tests for what scripts/mc-handover.sh's take and resume leave the new
# holder: the events raised before the name moved are marked submitted for
# it, except the open items its picture names, and no retired holder stays a
# wake target. The fixture is tests/lib/mc-handover-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
tab=$(printf '\t')
suite=test-mc-handover-backlog

# shellcheck source=tests/lib/mc-handover-fixture.sh
. "$here/lib/mc-handover-fixture.sh"

run mc-kb.sh init --program alpha
run mc-rules.sh load alpha
digest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#digest}" = 64 ] || fail "fixture: no rules digest from the load: $OUT"
: >"$tmp/empty"

emit() { # emit <kind> <subject>: sets EV to the new event's id
  run mc-event.sh emit --program alpha -- "$1" "$2" "fixture event"
  EV=$OUT
  [ "$RC" = 0 ] && [ -n "$EV" ] || fail "fixture: the $1 event was not raised: $ERR"
}
pending_for() { # pending_for <target>: the ids still pending for it
  run mc-event.sh list --program alpha --target "$1" --pending --limit 100000
  printf '%s\n' "$OUT" | awk -F '\t' 'NF { print $1 }'
}
has() { printf '%s\n' "$1" | grep -qxF "$2"; }
targets() {
  run mc-wake.sh target list --program alpha
  printf '%s\n' "$OUT" | awk -F '\t' 'NF { print $1 }'
}

# A first holder, then a backlog it handled and one item it leaves open.
ho launch --program alpha --brief "$tmp/brief.md"
n1=$(col successor 2)
wait_done "$n1"
ho verify --program alpha --session "$n1" --picture "$tmp/empty" --digest "$digest" --ledger - --durable "$tmp/empty"
ho take --program alpha --session "$n1" --window 1s
holder_is "fixture: the first session holds the name" "$n1"
emit session-landed handled-1
done1=$EV
emit decision handled-2
done2=$EV
emit blocker still-open
open1=$EV
printf '%s\n' "item $open1" >"$tmp/picture"
ho write --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "fixture: the handover file was not written: $ERR"
ledger=$(awk -F '\t' '$1 == "ledger" { print $2 }' "$home/handover.tsv")

# The released holder's mod hands its program-named target back to the relay.
run mc-wake.sh target add --program alpha alpha
ho launch --program alpha --brief "$tmp/brief.md" --handover
n2=$(col successor 2)
wait_done "$n2"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$ledger"
[ "$RC" = 0 ] || fail "fixture: the successor's verify exited $RC: $OUT $ERR"
# The predecessor's row went without the launcher removing its target, as a
# holder on a rung the launcher does not record a target for leaves it.
run mission-control-launch.sh retire "$n1"
run mc-wake.sh target add --program alpha "$n1"
has "$(targets)" "$n1" && has "$(targets)" alpha || fail "fixture: the leftover targets were not recorded: $(targets)"

ho take --program alpha --session "$n2" --window 1s
[ "$RC" = 0 ] || fail "the take exited $RC: $OUT $ERR"
holder_is "fixture: the successor holds the name" "$n2"
after=$(pending_for "$n2")
! has "$after" "$done1" && ! has "$after" "$done2" \
  && ok "the take marks the backlog its predecessor handled submitted for the successor" \
  || fail "the handled backlog is still pending for $n2: $after"
has "$after" "$open1" && ok "and keeps pending an open item the handover file names" || fail "the open item $open1 is not pending for $n2: $after"
prog_after=$(pending_for alpha)
! has "$prog_after" "$done1" && has "$prog_after" "$open1" \
  && ok "the program-named target the mod wakes under gets the same marks" \
  || fail "the program-named target's pending set: $prog_after"
emit decision raised-after-take
late=$EV
has "$(pending_for "$n2")" "$late" && ok "an event raised after the take is pending for the successor" || fail "the late event $late is not pending"
now_targets=$(targets)
! has "$now_targets" "$n1" && ok "the retired holder is no longer a wake target" || fail "the retired holder $n1 is still a wake target: $now_targets"
! has "$now_targets" alpha && ok "nor is the program-named target a released mod handed back" || fail "the handed-back target is still listed: $now_targets"
has "$now_targets" "$n2" && ok "the successor stays a wake target" || fail "the successor's own target went: $now_targets"

# The operator's resume shares the transfer: its --durable picture names the
# open items, the rest of the backlog is marked, the old holder's target goes.
emit decision handled-3
done3=$EV
emit blocker still-open-2
open2=$EV
printf '%s\n' "item $open2" >"$tmp/durable"
run mc-wake.sh target add --program alpha alpha
ho resume --program alpha --session operator-term --picture "$tmp/durable" --digest "$digest" --durable "$tmp/durable" --window 1s
[ "$RC" = 0 ] || fail "the resume exited $RC: $OUT $ERR"
holder_is "fixture: the operator's session holds the name" operator-term
for t in operator-term alpha; do
  r_after=$(pending_for "$t")
  ! has "$r_after" "$done3" && ! has "$r_after" "$late" && ! has "$r_after" "$open1" && has "$r_after" "$open2" \
    && ok "the resume marks the backlog for $t, keeping the open item its durable picture names" \
    || fail "the resume left $t's pending set: $r_after"
done
r_targets=$(targets)
! has "$r_targets" "$n2" && ok "the resume leaves no retired holder a wake target" || fail "the resume left $n2 a target: $r_targets"
# The operator's own session wakes under the program-named target its mod
# claims, so an attended resume keeps it.
has "$r_targets" alpha && ok "an attended resume keeps the program-named target, its own mod's" || fail "the attended resume dropped its own target: $r_targets"

# With no list of open items there is nothing to keep by, so a take leaves the
# backlog as it was rather than marking an open item handled.
emit blocker unlisted
unlisted=$EV
ho launch --program alpha --brief "$tmp/brief.md" --asked
n3=$(col successor 2)
wait_done "$n3"
ho verify --program alpha --session "$n3" --picture "$tmp/durable" --digest "$digest" --ledger - --durable "$tmp/durable"
[ "$RC" = 0 ] || fail "fixture: the fileless verify exited $RC: $OUT $ERR"
ho take --program alpha --session "$n3" --window 1s
[ "$RC" = 0 ] || fail "the fileless take exited $RC: $OUT $ERR"
has "$(pending_for "$n3")" "$unlisted" && ok "a take with no handover file marks nothing" || fail "the fileless take marked $unlisted"
case $ERR in *"no handover file"*) ok "and says why on stderr" ;; *) fail "the fileless take did not say it left the backlog: $ERR" ;; esac
! has "$(targets)" alpha && ok "a launched successor taking from the operator's session drops its program-named target" || fail "the attended predecessor's target stayed: $(targets)"
run mission-control-launch.sh retire "$n3"

echo
if [ "$failures" -gt 0 ]; then
  echo "$suite: $failures failure(s)" >&2
  exit 1
fi
echo "$suite: all passed"
