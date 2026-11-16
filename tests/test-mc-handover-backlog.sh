#!/bin/bash
# Tests for what scripts/mc-handover.sh's take and resume leave the new
# holder: the events its predecessor's picture accounts for are marked
# submitted for it, except the open items the picture names, and no retired
# holder stays a wake target. The fixture is tests/lib/mc-handover-fixture.sh.
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
suite=test-mc-handover-backlog

# shellcheck source=tests/lib/mc-handover-fixture.sh
. "$here/lib/mc-handover-fixture.sh"

run mc-kb.sh init --program alpha
run mc-rules.sh load alpha
digest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#digest}" = 64 ] || fail "fixture: no rules digest from the load: $OUT"
: >"$tmp/empty"
# The backlog is stamped in the past, so the handover file written after it
# is later by whole seconds, as a predecessor's picture always is.
base=$(($(date +%s) - 600))

emit() { # emit <kind> <subject> [<epoch>]: sets EV to the new event's id
  run mc-event.sh emit --program alpha ${3:+--now "$3"} -- "$1" "$2" "fixture event"
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
emit session-landed handled-1 "$base"
done1=$EV
emit decision handled-2 "$base"
done2=$EV
emit blocker still-open "$base"
open1=$EV
printf '%s\n' "item $open1" >"$tmp/picture"
ho write --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest" --now $((base + 10))
[ "$RC" = 0 ] || fail "fixture: the handover file was not written: $ERR"
ledger=$(awk -F '\t' '$1 == "ledger" { print $2 }' "$home/handover.tsv")
# Raised after the picture was written, so the predecessor may not have seen it.
emit blocker after-picture $((base + 20))
unseen=$EV

# The predecessor's mod woke under the program-named target, and staged one
# event there it never acknowledged.
run mc-wake.sh target add --program alpha alpha
run mc-event.sh mark --program alpha --target alpha staged "$done1"
ho launch --program alpha --brief "$tmp/brief.md" --handover
n2=$(col successor 2)
wait_done "$n2"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$ledger"
[ "$RC" = 0 ] || fail "fixture: the successor's verify exited $RC: $OUT $ERR"
# The predecessor's row went without the launcher removing its target, as a
# retire that holds part of a session back leaves it.
run mission-control-launch.sh retire "$n1"
run mc-wake.sh target add --program alpha "$n1"
has "$(targets)" "$n1" || fail "fixture: the leftover target was not recorded: $(targets)"

ho take --program alpha --session "$n2" --window 1s
[ "$RC" = 0 ] || fail "the take exited $RC: $OUT $ERR"
holder_is "fixture: the successor holds the name" "$n2"
after=$(pending_for "$n2")
! has "$after" "$done1" && ! has "$after" "$done2" \
  && ok "the take marks the backlog its predecessor's picture accounts for submitted for the successor" \
  || fail "the handled backlog is still pending for $n2: $after"
has "$after" "$open1" && ok "and keeps pending an open item the handover file names" || fail "the open item $open1 is not pending for $n2: $after"
has "$after" "$unseen" && ok "and an event raised after the handover file was written" || fail "the unseen event $unseen was marked for $n2"
prog_after=$(pending_for alpha)
! has "$prog_after" "$done1" && ! has "$prog_after" "$done2" && has "$prog_after" "$open1" \
  && ok "the program-named target gets the same marks, a staged event becoming submitted" \
  || fail "the program-named target's pending set: $prog_after"
emit decision raised-after-take $((base + 30))
late=$EV
has "$(pending_for "$n2")" "$late" && ok "an event raised after the take is pending for the successor" || fail "the late event $late is not pending"
now_targets=$(targets)
! has "$now_targets" "$n1" && ok "the retired holder is no longer a wake target" || fail "the retired holder $n1 is still a wake target: $now_targets"
has "$now_targets" "$n2" && ok "the successor stays a wake target" || fail "the successor's own target went: $now_targets"
has "$now_targets" alpha && ok "the program-named target every mod holder wakes under stays" || fail "the program-named target went: $now_targets"

# The operator's resume shares the transfer: the open items of its --durable
# picture and of a handover file left behind are kept, the rest of what was
# raised before it began is marked, the old holder's target goes.
emit decision handled-3 $((base + 40))
done3=$EV
emit blocker still-open-2 $((base + 40))
open2=$EV
emit blocker still-open-3 $((base + 40))
open3=$EV
printf '%s\n' "item $open3" >"$tmp/left"
ho write --program alpha --session "$n2" --picture "$tmp/left" --digest "$digest"
[ "$RC" = 0 ] || fail "fixture: the left-behind handover file was not written: $ERR"
printf '%s\n' "item $open2" >"$tmp/durable"
ho resume --program alpha --session operator-term --picture "$tmp/durable" --digest "$digest" --durable "$tmp/durable" --window 1s
[ "$RC" = 0 ] || fail "the resume exited $RC: $OUT $ERR"
holder_is "fixture: the operator's session holds the name" operator-term
for t in operator-term alpha; do
  r_after=$(pending_for "$t")
  ! has "$r_after" "$done3" && ! has "$r_after" "$late" && ! has "$r_after" "$open1" && ! has "$r_after" "$unseen" \
    && ok "the resume marks the backlog for $t" || fail "the resume left $t's handled backlog pending: $r_after"
  has "$r_after" "$open2" && has "$r_after" "$open3" \
    && ok "keeping the open items of --durable and of the handover file left behind" || fail "the resume marked an open item for $t: $r_after"
done
r_targets=$(targets)
! has "$r_targets" "$n2" && ok "the resume leaves no retired holder a wake target" || fail "the resume left $n2 a target: $r_targets"

# With no list of open items there is nothing to keep by, so a take leaves the
# backlog as it was rather than marking an open item handled.
emit blocker unlisted $((base + 50))
unlisted=$EV
ho launch --program alpha --brief "$tmp/brief.md" --asked
n3=$(col successor 2)
wait_done "$n3"
ho verify --program alpha --session "$n3" --picture "$tmp/durable" --digest "$digest" --ledger - --durable "$tmp/durable"
[ "$RC" = 0 ] || fail "fixture: the fileless verify exited $RC: $OUT $ERR"
ho take --program alpha --session "$n3" --window 1s
[ "$RC" = 0 ] || fail "the fileless take exited $RC: $OUT $ERR"
has "$(pending_for "$n3")" "$unlisted" && has "$(pending_for alpha)" "$unlisted" \
  && ok "a take with no handover file marks nothing" || fail "the fileless take marked $unlisted"
case $ERR in *"no handover file"*) ok "and says why on stderr" ;; *) fail "the fileless take did not say it left the backlog: $ERR" ;; esac
run mission-control-launch.sh retire "$n3"

echo
if [ "$failures" -gt 0 ]; then
  echo "$suite: $failures failure(s)" >&2
  exit 1
fi
echo "$suite: all passed"
