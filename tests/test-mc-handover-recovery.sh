#!/bin/bash
# Tests for scripts/mc-handover.sh's recovery and edge paths: a dead
# predecessor, a misdirected or stale release, a launch in flight, a
# resume that gives up, and the usage contract (mission-control REQ-A1.1,
# REQ-A1.7, REQ-L1.5, REQ-L1.6). The fixture is tests/lib/mc-handover-fixture.sh.
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
suite=test-mc-handover-recovery

# shellcheck source=tests/lib/mc-handover-fixture.sh
. "$here/lib/mc-handover-fixture.sh"
# ---------------------------------------------------------------------------
# A second program: recovery and edge paths.
# ---------------------------------------------------------------------------
run mc-kb.sh init --program beta
run mc-rules.sh load beta
bdigest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#bdigest}" = 64 ] || fail "fixture: no rules digest for beta: $OUT"
printf '%s\n' "item b-1" >"$tmp/bpic"
bhf="$bhome/handover.tsv"
ho holder --program beta
[ "$OUT" = "holder${tab}-" ] && ok "a program nobody holds says so" || fail "the empty holder: $OUT"
ho launch --program beta --brief "$tmp/brief.md"
b1=$(col successor 2)
wait_done "$b1"
ho verify --program beta --session "$b1" --picture "$tmp/bpic" --digest "$bdigest" --ledger - --durable "$tmp/bpic"
ho take --program beta --session "$b1" --window 1s
holder_is "fixture: beta's first session holds its name" "$b1" beta
ho path --program beta
[ "$OUT" = "path${tab}unattended" ] && ok "a launched holder hands over unattended" || fail "path: $OUT"

run mc-kb.sh append decisions --program beta --subject fixture --act "noted" --no-reversal
bled=$(printf '%s\n' "$OUT" | head -n 1)
# A decisions log that cannot be read is never written down as no ledger.
if [ "$(id -u)" != 0 ]; then
  for seg in "$bhome"/kb/decisions-*.log; do chmod 000 "$seg"; done
  ho write --program beta --session "$b1" --picture "$tmp/bpic" --digest "$bdigest"
  [ "$RC" != 0 ] && [ ! -f "$bhf" ] && ok "an unreadable ledger fails the write" || fail "the write over an unreadable ledger exited $RC"
  for seg in "$bhome"/kb/decisions-*.log; do chmod 600 "$seg"; done
fi
# A relative picture shaped like an awk assignment is still read as a file.
printf '%s\n' "item b-1" >"$repo/item=a"
OUT=$(printf '%s\n' "item injected" | {
  ho write --program beta --session "$b1" --picture item=a --digest "$bdigest"
  printf '%s\n' "$RC"
})
grep -qx "item${tab}b-1" "$bhf" && ! grep -q injected "$bhf" && ok "the picture is read from its file, never stdin" || fail "the picture was not read from its file: $(cat "$bhf")"
rm -f "$repo/item=a"

# A predecessor that died after writing its handover file: the successor
# verifies against that file and takes the name without waiting.
run mission-control-launch.sh retire "$b1"
ho holder --program beta
[ "$(col holder 6)" = stale ] && ok "a holder whose row is gone is stale" || fail "the dead holder: $OUT"
ho launch --program beta --brief "$tmp/brief.md" --handover
b2=$(col successor 2)
wait_done "$b2"
ho verify --program beta --session "$b2" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled"
[ "$RC" = 0 ] && ok "the successor of a dead predecessor verifies against its file" || fail "the dead predecessor's successor: $RC $OUT $ERR"
t0=$(date +%s)
ho take --program beta --session "$b2" --window 30s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && [ "$(col retire 3)" = gone ] && ok "it takes the name from the dead predecessor" || fail "the take from the dead predecessor: $RC $OUT"
[ $(($(date +%s) - t0)) -lt 10 ] && ok "without waiting out the window" || fail "the take waited for a predecessor already gone"

# A release made to one successor never lets another take the name.
ho write --program beta --session "$b2" --picture "$tmp/bpic" --digest "$bdigest"
ho launch --program beta --brief "$tmp/brief.md" --handover
b3=$(col successor 2)
wait_done "$b3"
ho verify --program beta --session "$b3" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled"
ho release --program beta --session "$b2"
[ "$(col released 3)" = "$b3" ] || fail "fixture: the release did not name $b3: $OUT $ERR"
run mission-control-launch.sh retire "$b3"
ho launch --program beta --brief "$tmp/brief.md" --handover
b4=$(col successor 2)
wait_done "$b4"
ho verify --program beta --session "$b4" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled"
ho take --program beta --session "$b4" --window 1s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && ok "a release to another successor does not count as this one's" || fail "the misdirected release: $RC $OUT"

# REQ-A1.1: the operator-asked launch against a live holder ends with one
# holder, the successor; with no handover file its ledger is checked
# against the log.
ho launch --program beta --brief "$tmp/brief.md" --asked
[ "$RC" = 0 ] && ok "the operator's ask launches over a live holder" || fail "the asked launch exited $RC: $ERR"
b5=$(col successor 2)
wait_done "$b5"
ho verify --program beta --session "$b5" --picture "$tmp/bpic" --digest "$bdigest" --ledger - --durable "$tmp/bpic"
[ "$RC" = 1 ] && ok "a ledger behind the log fails a durable self-check" || fail "the durable stale ledger exited $RC"
ho verify --program beta --session "$b5" --picture "$tmp/bpic" --digest "$bdigest" --ledger "$bled" --durable "$tmp/bpic"
[ "$RC" = 0 ] || fail "the asked successor's verify exited $RC: $OUT $ERR"
ho take --program beta --session "$b5" --window 1s
[ "$RC" = 0 ] && [ ! -f "$(rowfile "$b4")" ] && ok "the asked successor ends as the one holder" || fail "the asked take: $RC $OUT"
holder_is "the name resolves to the asked successor" "$b5" beta

# A resume while a successor is pending retires the stranded successor.
ho launch --program beta --brief "$tmp/brief.md" --asked
b6=$(col successor 2)
wait_done "$b6"
ho resume --program beta --session operator-b --picture "$tmp/bpic" --digest "$bdigest" --durable "$tmp/bpic" --window 1s
[ "$RC" = 0 ] || fail "the resume over a pending successor exited $RC: $OUT $ERR"
case $OUT in *"retire${tab}$b6${tab}released"*) ok "the stranded successor is retired" ;; *) fail "the stranded successor was not retired: $OUT" ;; esac
[ ! -f "$(rowfile "$b6")" ] && ok "and its row is gone" || fail "the stranded successor's row stayed"

ho release --program beta --session mc-nobody
[ "$RC" = 1 ] && ok "a session that does not hold the name cannot release it" || fail "a non-holder's release exited $RC"
ho release --program beta --session operator-b
[ "$RC" = 1 ] && ok "a release with no successor or request is refused" || fail "the orphan release exited $RC"
ho resume --program beta --session mc-unregistered --kind registry --picture "$tmp/bpic" --digest "$bdigest" --durable "$tmp/bpic"
[ "$RC" = 1 ] && ok "a registry resume needs the session's row" || fail "the rowless registry resume exited $RC"

# A lease stamped after now proves nothing, so the holder stays live.
mkdir -p "$fleet/mission-control/beta/leases"
printf '%s\n' "$(($(date +%s) + 600))" >"$fleet/mission-control/beta/leases/operator-b"
ho holder --program beta
[ "$(col holder 6)" = live ] && ok "a lease from the future leaves the holder live" || fail "the future lease: $OUT"
rm -f "$fleet/mission-control/beta/leases/operator-b"

# A reservation whose launch is still in flight counts as pending.
printf 'format\t1\nsession\tmc-in-flight\npredecessor\toperator-b\npredecessor-kind\tattended\nlaunched\t1\nmode\tasked\nverified\t-\nowner\t%s\n' "$$" \
  >"$fleet/mission-control/beta/successor"
ho launch --program beta --brief "$tmp/brief.md" --asked
[ "$RC" = 3 ] && ok "a launch meeting another launch's reservation is refused" || fail "the launch over an in-flight reservation exited $RC: $OUT"
rm -f "$fleet/mission-control/beta/successor"

# A resume beaten to the name exits 3 and takes its release request with it.
mc_env /bin/bash "$repo_root/scripts/mc-handover.sh" resume --program beta --session operator-c \
  --picture "$tmp/bpic" --digest "$bdigest" --durable "$tmp/bpic" --window 20s >"$tmp/beaten.out" 2>&1 &
beaten=$!
req="$fleet/mission-control/beta/release-request"
n=0
until [ -f "$req" ] || [ "$n" -ge 100 ]; do
  sleep 0.1
  n=$((n + 1))
done
[ -f "$req" ] || fail "fixture: the resume wrote no release request"
now=$(date +%s)
printf 'format\t1\nsession\tintruder\nkind\tattended\nsince\t%s\ngeneration\t99\n' "$now" >"$fleet/mission-control/beta/holder"
printf 'format\t1\nsession\toperator-b\nto\toperator-c\nat\t%s\n' "$now" >"$fleet/mission-control/beta/released"
wait "$beaten"
brc=$?
[ "$brc" = 3 ] && ok "a resume beaten to the name exits 3" || fail "the beaten resume exited $brc: $(cat "$tmp/beaten.out")"
[ ! -f "$req" ] && ok "and its release request goes with it" || fail "the beaten resume left its release request"
holder_is "the name stays with the session that took it" intruder beta

for c in "take --program beta --session operator-b --window bogus" \
  "launch --program beta --brief $tmp/brief.md --backend nowhere" \
  "due --program beta --context x --wakes 0 --compactions 0" \
  "verify --program beta --session operator-b --picture $tmp/bpic --digest abc --ledger -" \
  "due --program beta --context 101 --wakes 0 --compactions 0" \
  "frobnicate --program beta"; do
  # shellcheck disable=SC2086 # each case is a word list on purpose
  ho $c
  [ "$RC" = 2 ] && ok "usage: $c (exit 2)" || fail "usage: $c exited $RC"
done
ho holder --program gamma
[ "$RC" = 3 ] && ok "a program that is not configured exits 3" || fail "the unconfigured program exited $RC"

cp "$tracked" "$tmp/tracked.keep"
printf '%s\n' "mission_control_handover_context: 50" >>"$tracked"
ho due --program beta --context 50 --wakes 0 --compactions 0
[ "$OUT" = "due${tab}context at 50%" ] && ok "the context threshold is the knob's" || fail "the knob was not read: $OUT $ERR"
cp "$tmp/tracked.keep" "$tracked"

# A relaunch in the same second as a successor that died gets a name of its
# own, so a release to the dead one can never match it.
ho launch --program beta --brief "$tmp/brief.md" --asked --now 1800000000
s1=$(col successor 2)
wait_done "$s1"
run mission-control-launch.sh retire "$s1"
ho launch --program beta --brief "$tmp/brief.md" --asked --now 1800000000
s2=$(col successor 2)
wait_done "$s2"
[ -n "$s1" ] && [ -n "$s2" ] && [ "$s1" != "$s2" ] && ok "a same-second relaunch gets a name of its own" || fail "the relaunch reused $s1 (got '$s2')"
run mission-control-launch.sh retire "$s2"

echo
if [ "$failures" -gt 0 ]; then
  echo "test-mc-handover-recovery: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-handover-recovery: all passed"
