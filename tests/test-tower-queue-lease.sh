#!/bin/bash
# Tests for scripts/tower-queue.sh `next` across two towers — the per-tower
# lease, its renewal, expiry and preemption, the owner label and its
# session-scoped fallback, the attention-pointer refresh, and the
# write-failure dispositions (REQ-A1.3, REQ-A1.7, REQ-A1.8, REQ-A1.9,
# REQ-C1.11). The single-tower attention state machine and `ack` are in
# test-tower-queue-next.sh; split so each file stays inside the per-file
# wall-clock budget.
#
# Contract under test:
#   next [--tower <id>] [--now <epoch>]
#       At most one line: `knock<TAB>...` when a knock is due, `item<TAB>...`
#       when the calling tower's attention is confirmed by its marker
#       (a reply at or after its last knock and later than its last
#       hand-over, within tower_quiet_interval), else nothing. Leases the
#       item it names.
#   ack <id> [--tower <id>] [--now <epoch>]
#       Closes the item; refused (exit 1, logged) without a lease; a logged
#       no-op on a closed item; never releases the next.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
# A tower session exports its own identity; the owner-label cases below set
# each rung of the ladder themselves.
unset PLANWRIGHT_TOWER_ID PLANWRIGHT_TOWER_SESSION_ID PLANWRIGHT_TOWER_PID

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
chmod 0700 "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
attn_dir="$home/attention"
attn_store="$attn_dir/state"
content="$tmp/content"
mkdir -p "$content"
TAB=$(printf '\t')

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

# run_outside <args> — the same, invoked from a directory that is no
# repository, where the presence script can resolve no identity.
run_outside() {
  (cd "$tmp" && run "$@")
}

marker() {
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

field() { printf '%s\n' "$1" | cut -f "$2"; }
rec() { grep "^$1$TAB" "$store"; }
lease_of() { rec "$1" | cut -f 19; }

add_req() { # add_req <name> <urgency> <now>
  printf 'request %s\n' "$1" >"$content/$1"
  run add --kind request --root "$content" --pointer "$1" --origin operator --urgency "$2" --closes 'the operator decides' --now "$3"
}

# --- quiet and lease intervals short enough to test, the lease floored ---------

printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
A=tower-a
B=tower-b

# --- two towers: one delivery per item, each its own attention (REQ-A1.7) -----------

z1=$(add_req z1 normal 3000)
out=$(run next --tower $A --now 3001) || fail "A knock z1"
[ "$(field "$out" 1)" = knock ] || fail "A did not knock: '$out'"
marker $A 3002
out=$(run next --tower $A --now 3003) || fail "A deliver z1"
[ "$(field "$out" 2)" = "$z1" ] || fail "A did not get z1: '$out'"
out=$(run next --tower $B --now 3004) || fail "B next: exit"
[ -z "$out" ] || fail "B knocked on an item an attended tower holds: '$out'"
marker $B 3005
out=$(run next --tower $B --now 3006) || fail "B next attended: exit"
[ -z "$out" ] || fail "B's own marker advancing released a leased item, or confirmed attention with no knock of its own: '$out'"
z2=$(add_req z2 normal 3007)
out=$(run next --tower $B --now 3008) || fail "B knock z2"
[ "$(field "$out" 1)" = knock ] || fail "B did not knock for the unleased item: '$out'"
[ "$(lease_of "$z2")" = $B ] || fail "B's knock did not lease z2"
marker $B 3009
out=$(run next --tower $B --now 3010) || fail "B deliver z2"
[ "$(field "$out" 2)" = "$z2" ] || fail "B did not get z2: '$out'"
[ "$(lease_of "$z1")" = $A ] || fail "z1's lease moved off A"
run ack "$z2" --tower $B --now 3011 >/dev/null || fail "ack z2"
# B attended (a reply after its hand-over) while A, whose operator replied
# within the quiet interval, still holds z1: B receives nothing.
marker $B 3012
out=$(run next --tower $B --now 3013) || fail "B attended while A holds z1"
[ -z "$out" ] || fail "B, attended, was handed an item a present tower holds: '$out'"
[ "$(lease_of "$z1")" = $A ] || fail "z1's lease moved off A while A's operator was present"
[ "$(grep -c "\"kind\":\"delivered\".*\"item\":\"$z1\"" "$log_file")" = 1 ] || fail "z1 was delivered more than once"
echo "ok: two towers each hold their own attention state and never receive the same item"

# --- the lease renews on the holder's reply and expires only as a backstop ---------

# A's lease on z1 was taken at 3003 and backstops at 3203; a reply from A at
# 3100 carries it to 3300, so at 3250 B (A's operator away by then, 150s of
# silence against a 100s quiet interval) may knock about it but not take
# it, and an older reply leaves the lease expired and released.
marker $A 3100
out=$(run next --tower $B --now 3250 2>/dev/null) || fail "B after A's reply"
[ "$(field "$out" 1)" = knock ] || fail "B did not knock about an item whose holder is away: '$out'"
[ "$(lease_of "$z1")" = $A ] || fail "B's knock took a lease A's reply had renewed"
marker $A 3000
out=$(run next --tower $B --now 3251 2>/dev/null) || fail "B after A's lease lapsed"
[ -z "$out" ] || fail "B repeated its outstanding knock: '$out'"
[ "$(lease_of "$z1")" = - ] || fail "an expired lease was not released"
rc=0
run ack "$z1" --tower $A --now 3251 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 1 ] || fail "an ack after the backstop released the lease: exit $rc, expected 1"
grep -q 'lapsed' "$tmp/err" || fail "an ack after the backstop did not say the lease lapsed: $(cat "$tmp/err")"
marker $B 3252
out=$(run next --tower $B --now 3253) || fail "B delivers z1"
[ "$(field "$out" 2)" = "$z1" ] || fail "B was not handed the released item on its reply: '$out'"
[ "$(lease_of "$z1")" = $B ] || fail "the hand-over did not lease z1 to B"
echo "ok: a reply from the holder renews its lease; an expired lease releases the item"

# --- an attended tower preempts an unattended tower's lease --------------------------

run ack "$z1" --tower $B --now 3254 >/dev/null || fail "ack z1"
p1=$(add_req p1 normal 4000)
out=$(run next --tower $A --now 4001) || fail "A knock p1"
[ "$(field "$out" 1)" = knock ] || fail "A did not knock for p1: '$out'"
[ "$(lease_of "$p1")" = $A ] || fail "A's knock did not lease p1"
out=$(run next --tower $B --now 4002) || fail "B knock p1 (pin without lease)"
[ "$(field "$out" 1)" = knock ] || fail "B could not knock about an item leased by an unattended tower: '$out'"
[ "$(lease_of "$p1")" = $A ] || fail "B's knock stole the lease before its attention was confirmed"
marker $B 4003
out=$(run next --tower $B --now 4004) || fail "B preempts"
[ "$(field "$out" 2)" = "$p1" ] || fail "an attended tower did not preempt the unattended holder's lease: '$out'"
[ "$(lease_of "$p1")" = $B ] || fail "the preempted lease did not move to B"
marker $A 4005
out=$(run next --tower $A --now 4006) || fail "A after preemption"
case "$out" in *"$p1"*) fail "A was handed p1 after B, attended, had taken it" ;; esac
echo "ok: a tower whose attention is confirmed preempts a lease held by one whose attention is not"

# --- the lease's owner label: presence identity or a session-scoped fallback ----------

run ack "$p1" --tower $B --now 4007 >/dev/null
f1=$(add_req f1 normal 5000)
out=$(PLANWRIGHT_TOWER_ID=uuid-tower-1 run next --now 5001) || fail "next via PLANWRIGHT_TOWER_ID"
[ "$(lease_of "$f1")" = uuid-tower-1 ] || fail "the lease owner is not the identity from the environment"
run ack "$f1" --tower uuid-tower-1 --now 5002 >/dev/null
f2=$(add_req f2 normal 5003)
# A pid resolves through the presence script (the composite identity the
# tower published under) when the checkout can answer; from a directory that
# is no repository the presence script refuses, and the session-scoped
# fallback is minted from the pid instead.
out=$(PLANWRIGHT_TOWER_PID=$$ run next --now 5004 2>"$tmp/err") || fail "next with a pid identity"
[ "$(field "$out" 1)" = knock ] || fail "no knock under the pid identity: '$out'"
owner=$(lease_of "$f2")
case "$owner" in
  p$$.t*.c*) ;;
  *) fail "a pid in a checkout did not resolve to the presence identity: '$owner'" ;;
esac
grep -q 'fallback' "$tmp/err" && fail "a resolved presence identity was announced as a fallback"
run ack "$f2" --tower "$owner" --now 5005 >/dev/null || fail "ack under the presence identity"
f3=$(add_req f3 normal 5006)
out=$(PLANWRIGHT_TOWER_PID=$$ run_outside next --now 5007 2>"$tmp/err") || fail "next with no identity outside a checkout"
[ "$(field "$out" 1)" = knock ] || fail "no knock under the fallback identity: '$out'"
owner=$(lease_of "$f3")
case "$owner" in
  fallback.p$$.t[0-9]*) ;;
  *) fail "the fallback identity is not session-scoped: '$owner'" ;;
esac
grep -q 'fallback' "$tmp/err" || fail "leasing under a fallback identity was not announced"
mkdir -p "$surface/attention"
printf '5008\n' >"$surface/attention/$owner"
chmod 0600 "$surface/attention/$owner"
out=$(PLANWRIGHT_TOWER_PID=$$ run_outside next --now 5009 2>/dev/null) || fail "next again under the fallback"
[ "$(field "$out" 2)" = "$f3" ] || fail "a later caller did not read the fallback identity back: '$out'"
PLANWRIGHT_TOWER_PID=$$ run_outside ack "$f3" --now 5010 >/dev/null 2>&1 || fail "ack under the fallback identity was refused"
sleep 30 &
other=$!
f4=$(add_req f4 normal 5011)
out=$(PLANWRIGHT_TOWER_PID=$other run_outside next --now 5012 2>/dev/null) || fail "next under another pid"
kill "$other" 2>/dev/null || true
[ "$(lease_of "$f4")" != "$owner" ] || fail "two different tower pids minted one fallback identity"
case "$(lease_of "$f4")" in fallback.p$other.t*) ;; *) fail "the fallback does not name its own pid: '$(lease_of "$f4")'" ;; esac
run ack "$f4" --tower "$(lease_of "$f4")" --now 5013 >/dev/null || fail "ack f4 under the other fallback identity"
rc=0
PLANWRIGHT_TOWER_SESSION_ID=not-a-uuid run next --now 5013 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a session id that is no UUID: exit $rc, expected 2"
echo "ok: the lease owner is the presence identity, else a session-scoped fallback read back by a later caller"

# --- a store that cannot be written is an error in the turn (REQ-C1.11) --------------

g1=$(add_req g1 normal 6000)
mv "$store" "$tmp/store.bak"
mkdir "$store"
printf 'g2\n' >"$content/g2"
for verb in "next --tower $A" "add --kind request --root $content --pointer g2 --origin operator --closes done" "ack $g1 --tower $A" "shelve $g1 --tower $A" "settle $g1 --reason x"; do
  rc=0
  # shellcheck disable=SC2086
  run $verb --now 6001 >/dev/null 2>"$tmp/err" || rc=$?
  [ "$rc" = 6 ] || fail "$verb over an unwritable store: exit $rc, expected 6"
  grep -q 'store' "$tmp/err" || fail "$verb: the unwritable store was not reported"
done
rmdir "$store"
mv "$tmp/store.bak" "$store"
echo "ok: an unwritable store surfaces an error rather than a silent skip"

# --- a delivery whose log append fails still hands the item over (fail-open) ----------

# The log stays a verifiably owner-only file (a widened or redirected one is
# refused before anything happens); it just cannot take the append.
run next --tower $A --now 6002 >/dev/null || fail "A knock g1"
marker $A 6003
chmod 0400 "$log_file"
rc=0
out=$(run next --tower $A --now 6004 2>"$tmp/err") || rc=$?
chmod 0600 "$log_file"
[ "$rc" = 0 ] || fail "a delivery whose log append fails: exit $rc, expected 0 (fail-open)"
[ "$(field "$out" 2)" = "$g1" ] || fail "the hand-over did not stand when the log append failed: '$out'"
grep -q 'delivered' "$tmp/err" || fail "the failed delivery-line append was not surfaced"
echo "ok: a failed delivery-line append is fail-open: the hand-over stands and the error is surfaced"

# --- attention pointers: a re-forked row refreshes, a moved row refuses ----------------

run ack "$g1" --tower $A --now 6005 >/dev/null
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
printf 'w-q\tspec/t\tawaiting-input\t7000\tnormal\tQ?\ta\ta|b\tfork\tiid-old\n' >"$attn_store"
q1=$(run add --kind question --worker w-q --origin w-q --closes 'the operator answers' --now 7001)
[ "$(rec "$q1" | cut -f 8)" = iid-old ] || fail "the question did not record the row's instance id"
printf 'w-q\tspec/t\tawaiting-input\t7002\thigh\tQ2?\ta\ta|b\tfork\tiid-new\n' >"$attn_store"
out=$(run next --tower $A --now 7003) || fail "next over a re-forked row"
[ "$(field "$out" 1)" = knock ] || fail "expected a knock: '$out'"
[ "$(rec "$q1" | cut -f 8)" = iid-new ] || fail "a re-forked row's instance id was not refreshed"
[ "$(rec "$q1" | cut -f 3)" = high ] || fail "a re-forked row's priority was not refreshed"
printf 'w-q\tspec/t\tworking\t7004\tnormal\t-\t-\t-\n' >"$attn_store"
marker $A 7005
out=$(run next --tower $A --now 7006 2>"$tmp/err") || fail "next over a moved row"
[ -z "$out" ] || fail "a question whose row moved on was handed over: '$out'"
grep -q "$q1" "$tmp/err" || fail "the refused hand-over was not reported"
echo "ok: a re-forked row refreshes the pointer; a row that moved on refuses the hand-over"

# --- knob guards ----------------------------------------------------------------------

printf 'tower_quiet_interval: 5m\ntower_lease_interval: 1m\n' >"$local_cfg"
rc=0
run next --tower $A --now 8000 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 4 ] || fail "a lease interval below the quiet interval: exit $rc, expected 4"
grep -q 'tower_lease_interval' "$tmp/err" || fail "the floor refusal does not name the knob"
printf 'tower_quiet_interval: 500ms\ntower_lease_interval: 750ms\n' >"$local_cfg"
h1=$(add_req h1 normal 8000)
out=$(run next --tower $A --now 8001) || fail "sub-second intervals were refused"
[ "$(field "$out" 1)" = knock ] || fail "expected a knock under sub-second intervals: '$out'"
run list --now 8001 | grep -q "^$h1$TAB" || fail "a fractional lease made the record unparseable"
case "$(rec "$h1" | cut -f 20)" in
  "" | *[!0-9]*) fail "the lease expiry is not a whole epoch: '$(rec "$h1" | cut -f 20)'" ;;
esac
# A quiet interval under a second lapses across a one-second gap: the reply
# at 8001 confirms attention at 8001 and not at 8003.
marker $A 8001
out=$(run next --tower $A --now 8003) || fail "next after a sub-second lapse"
[ "$(field "$out" 1)" = knock ] || fail "a 500ms quiet interval did not lapse across two seconds: '$out'"
echo "ok: the lease interval is floored at the quiet interval, and both accept sub-second values"

# --- a holder with no marker yet is present for one quiet interval ---------------

printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
run settle "$h1" --reason 'fixture done' --now 8004 >/dev/null || fail "settle h1"
C=tower-c
k1=$(add_req k1 normal 9000)
out=$(run next --tower $C --now 9001 2>/dev/null) || fail "C knocks k1"
[ "$(field "$out" 1)" = knock ] || fail "C did not knock: '$out'"
run next --tower $B --now 9002 >/dev/null || fail "B knock while C holds"
marker $B 9003
out=$(run next --tower $B --now 9004) || fail "B attended while C, markerless, just knocked"
[ -z "$out" ] || fail "B preempted a lease whose holder knocked seconds ago and has no marker yet: '$out'"
[ "$(lease_of "$k1")" = $C ] || fail "the markerless holder lost its lease inside the quiet interval"
marker $B 9150
out=$(run next --tower $B --now 9151) || fail "B after C's quiet interval ran out"
[ "$(field "$out" 2)" = "$k1" ] || fail "B did not preempt once the markerless holder's quiet interval ran out: '$out'"
echo "ok: a holder whose marker has not appeared counts as present until its quiet interval runs out"

# --- a re-knock about a higher item releases the lease its earlier knock pinned ------

# The knock pins the item it named (REQ-A1.8); when the top changes and the
# tower knocks again, the earlier pin serves nothing: its lease goes, so the
# item is not held by a conversation that was never handed it.
run ack "$k1" --tower $B --now 9152 >/dev/null || fail "ack k1"
D=tower-d
p1=$(add_req pin-1 low 9500)
out=$(run next --tower $D --now 9501 2>/dev/null) || fail "D knocks pin-1"
[ "$(field "$out" 1)" = knock ] || fail "D did not knock for pin-1: '$out'"
[ "$(lease_of "$p1")" = $D ] || fail "D's knock did not pin pin-1"
p2=$(add_req pin-2 high 9502)
out=$(run next --tower $D --now 9503 2>/dev/null) || fail "D knocks pin-2"
[ "$(field "$out" 1)" = knock ] || fail "D did not knock again for the higher item: '$out'"
[ "$(lease_of "$p2")" = $D ] || fail "D's second knock did not pin pin-2"
[ "$(lease_of "$p1")" = - ] || fail "the lease from the superseded knock was kept: pin-1 is held by '$(lease_of "$p1")'"
echo "ok: a knock about a new top item releases the lease the superseded knock pinned"

# --- a holder's marker stamped in the future does not make it present ---------------

# D's pin on pin-2 stands; a marker past now is no reply, so D is away once its
# own knock ages out, and B, attended, takes the item D pinned rather than
# the one it released.
marker $D 99999
marker $B 9610
out=$(run next --tower $B --now 9611) || fail "B takes pin-2"
[ "$(field "$out" 2)" = "$p2" ] || fail "a holder with a marker stamped in the future counted as present: '$out'"
echo "ok: a marker stamped in the future does not make its tower present"

echo "ALL PASS: tower-queue lease"
