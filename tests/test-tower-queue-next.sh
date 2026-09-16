#!/bin/bash
# Tests for scripts/tower-queue.sh `next` and `ack` — knock-first delivery
# gated on the harness-written attention marker, the per-tower lease, and
# the acknowledgement that never releases the next item (REQ-A1.7, REQ-A1.8,
# REQ-A1.9, REQ-B1.5, REQ-C1.1, REQ-C1.2, REQ-C1.10). The store grammar and
# the other verbs are in test-tower-queue-store.sh.
#
# Contract under test:
#   next [--tower <id>] [--now <epoch>]
#       At most one line: `knock<TAB>...` when a knock is due, `item<TAB>...`
#       when the calling tower's attention is confirmed by its marker
#       (a reply later than its last knock and last hand-over, within
#       tower_quiet_interval), else nothing. Leases the item it names.
#   ack <id> [--tower <id>] [--now <epoch>]
#       Closes the item; refused (exit 1, logged) without a lease; a logged
#       no-op on a closed item; never releases the next.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

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

# --- knock first, content after a reply (REQ-C1.2, REQ-C1.10) ---------------------

x1=$(add_req x1 normal 1000)
out=$(run next --tower $A --now 1010) || fail "next #1: exit"
[ "$(field "$out" 1)" = knock ] || fail "first next with no marker did not knock: '$out'"
[ "$(field "$out" 2)" = request ] || fail "the knock names the wrong kind: '$out'"
[ "$(field "$out" 3)" = normal ] || fail "the knock names the wrong urgency: '$out'"
[ "$(field "$out" 4)" = 1 ] || fail "the knock's open count is wrong: '$out'"
[ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] || fail "the knock is more than one line"
case "$out" in *x1*) fail "the knock leaked the item's content pointer" ;; esac
[ "$(lease_of "$x1")" = $A ] || fail "the knock did not lease the item it named"
grep -q "\"kind\":\"knocked\",\"tower\":\"$A\".*\"item\":\"$x1\"" "$log_file" || fail "no knocked event with the tower's identity"
echo "ok: the first next knocks with kind and urgency, leases the item, and prints no content"

out=$(run next --tower $A --now 1020 2>"$tmp/err") || fail "next #2: exit"
[ -z "$out" ] || fail "a second next with the knock unanswered printed: '$out'"
grep -q 'marker' "$tmp/err" || fail "an absent marker after a knock is not reported"
out=$(run next --tower $A --now 1500 2>/dev/null) || fail "next #3: exit"
[ -z "$out" ] || fail "an unanswered knock repeated after the quiet interval (a fixed-schedule repeat): '$out'"
[ "$(grep -c '"kind":"knocked"' "$log_file")" = 1 ] || fail "the knock was logged more than once"
echo "ok: while a knock is outstanding next prints nothing and never repeats on a schedule"

marker $A 1005
out=$(run next --tower $A --now 1510) || fail "next #4: exit"
[ -z "$out" ] || fail "a reply OLDER than the knock confirmed attention: '$out'"
marker $A 1600
out=$(run next --tower $A --now 1601) || fail "next #5: exit"
[ "$(field "$out" 1)" = item ] || fail "a reply after the knock did not release the item: '$out'"
[ "$(field "$out" 2)" = "$x1" ] || fail "the wrong item was handed over: '$out'"
[ "$(field "$out" 3)" = request ] || fail "the item line lacks the kind"
case "$(field "$out" 7)" in
  path:"$content"/x1) ;;
  *) fail "the item line's pointer is wrong: '$(field "$out" 7)'" ;;
esac
[ "$(rec "$x1" | cut -f 14)" = 1601 ] || fail "the hand-over was not stamped on the record"
grep -q "\"kind\":\"delivered\",\"tower\":\"$A\".*\"item\":\"$x1\"" "$log_file" || fail "no delivered event with the tower's identity"
echo "ok: a reply later than the knock releases the item, stamped and logged"

out=$(run next --tower $A --now 1602) || fail "next #6: exit"
[ -z "$out" ] || fail "a second next with no new reply handed over: '$out'"
x2=$(add_req x2 high 1603)
out=$(run next --tower $A --now 1604) || fail "next #7: exit"
[ -z "$out" ] || fail "a new item was volunteered before the operator replied to the first: '$out'"
echo "ok: nothing is handed over until the marker shows a later reply"

# --- ack closes, never releases the next (REQ-C1.10) -------------------------------

run ack "$x1" --tower $A --now 1605 >/dev/null || fail "ack: exit"
[ "$(rec "$x1" | cut -f 12)" = closed ] || fail "ack did not close the item"
[ "$(rec "$x1" | cut -f 15)" = 1605 ] || fail "ack did not stamp the record"
[ "$(lease_of "$x1")" = - ] || fail "ack did not release the lease"
grep -q "\"kind\":\"acknowledged\",\"tower\":\"$A\".*\"item\":\"$x1\"" "$log_file" || fail "no acknowledged event"
out=$(run next --tower $A --now 1606) || fail "next after ack: exit"
[ -z "$out" ] || fail "ack released the next item: '$out'"
marker $A 1607
out=$(run next --tower $A --now 1608) || fail "next after reply: exit"
[ "$(field "$out" 2)" = "$x2" ] || fail "the reply after the ack did not release the next item: '$out'"
[ "$(grep -c '"kind":"knocked"' "$log_file")" = 1 ] || fail "a fresh knock was made inside an attention session"
echo "ok: ack closes and releases nothing; the next reply releases the next item with no fresh knock"

rc=0
run ack "$x1" --tower $A --now 1609 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 0 ] || fail "ack on a closed item: exit $rc, expected 0 (a logged no-op)"
grep -q 'already closed' "$tmp/err" || fail "ack on a closed item did not say so"
grep -q "\"kind\":\"refused\".*\"item\":\"$x1\".*\"reason\":\"already-closed\"" "$log_file" || fail "the no-op ack was not logged"
rc=0
run ack "$x2" --tower $B --now 1610 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 1 ] || fail "ack by a tower holding no lease: exit $rc, expected 1"
grep -q 'no lease' "$tmp/err" || fail "the no-lease refusal did not say why"
grep -q "\"kind\":\"refused\",\"tower\":\"$B\".*\"item\":\"$x2\".*\"reason\":\"no-lease\"" "$log_file" || fail "the no-lease refusal was not logged"
[ "$(rec "$x2" | cut -f 12)" = open ] || fail "a refused ack closed the item"
rc=0
run ack i00000000 --tower $A >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "ack of an unknown item: exit $rc, expected 2"
echo "ok: ack is refused without a lease and a logged no-op on a closed item"

# --- attention lapses after the quiet interval; the next delivery knocks again -----

run ack "$x2" --tower $A --now 1611 >/dev/null || fail "ack x2"
x3=$(add_req x3 normal 1612)
marker $A 1613
out=$(run next --tower $A --now 1800) || fail "next after lapse: exit"
[ "$(field "$out" 1)" = knock ] || fail "after the quiet interval passed next did not knock again: '$out'"
marker $A 1801
out=$(run next --tower $A --now 1802) || fail "next after re-knock reply: exit"
[ "$(field "$out" 2)" = "$x3" ] || fail "the re-knock's reply did not release the item: '$out'"
echo "ok: attention lapses after the quiet interval and the next delivery knocks again"

# --- the knock pins its item; a changed top knocks again (REQ-A1.8) -----------------

run ack "$x3" --tower $A --now 1803 >/dev/null || fail "ack x3"
y1=$(add_req y1 low 2000)
out=$(run next --tower $A --now 2001) || fail "knock y1: exit"
[ "$(field "$out" 1)" = knock ] || fail "expected a knock for y1: '$out'"
y2=$(add_req y2 high 2002)
out=$(run next --tower $A --now 2003) || fail "re-knock: exit"
[ "$(field "$out" 1)" = knock ] || fail "a higher item arriving did not knock again: '$out'"
[ "$(field "$out" 3)" = high ] || fail "the second knock does not name the new top: '$out'"
[ "$(lease_of "$y2")" = $A ] || fail "the second knock did not lease the new top"
marker $A 2004
out=$(run next --tower $A --now 2005) || fail "deliver pinned: exit"
[ "$(field "$out" 2)" = "$y2" ] || fail "the reply did not deliver the item the last knock pinned: '$out'"
# The pin is consumed by the hand-over: the next reply releases the top item
# of that moment, not the low one that was queued first.
y3=$(add_req y3 high 2006)
marker $A 2007
out=$(run next --tower $A --now 2008) || fail "deliver after pin: exit"
[ "$(field "$out" 2)" = "$y3" ] || fail "after the pinned hand-over the next reply did not release the new top: '$out' (expected $y3)"
echo "ok: the knock pins its item and knocks again when the top changes; the pin is consumed by the hand-over"

# --- two towers: one delivery per item, each its own attention (REQ-A1.7) -----------

run ack "$y1" --tower $A --now 2009 >/dev/null
run ack "$y2" --tower $A --now 2010 >/dev/null
run ack "$y3" --tower $A --now 2011 >/dev/null
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
out=$(PLANWRIGHT_TOWER_PID=$$ run next --now 5004 2>"$tmp/err") || fail "next with no identity"
[ "$(field "$out" 1)" = knock ] || fail "no knock under the fallback identity: '$out'"
owner=$(lease_of "$f2")
case "$owner" in
  fallback.p$$.t[0-9]*) ;;
  *) fail "the fallback identity is not session-scoped: '$owner'" ;;
esac
grep -q 'fallback' "$tmp/err" || fail "leasing under a fallback identity was not announced"
mkdir -p "$surface/attention"
printf '5005\n' >"$surface/attention/$owner"
chmod 0600 "$surface/attention/$owner"
out=$(PLANWRIGHT_TOWER_PID=$$ run next --now 5006 2>/dev/null) || fail "next again under the fallback"
[ "$(field "$out" 2)" = "$f2" ] || fail "a later caller did not read the fallback identity back: '$out'"
PLANWRIGHT_TOWER_PID=$$ run ack "$f2" --now 5007 >/dev/null 2>&1 || fail "ack under the fallback identity was refused"
echo "ok: the lease owner is the presence identity, else a session-scoped fallback read back by a later caller"

# --- a store that cannot be written is an error in the turn (REQ-C1.11) --------------

g1=$(add_req g1 normal 6000)
mv "$store" "$tmp/store.bak"
mkdir "$store"
rc=0
run next --tower $A --now 6001 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 6 ] || fail "next over an unwritable store: exit $rc, expected 6"
grep -q 'store' "$tmp/err" || fail "the unwritable store was not reported"
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
run next --tower $A --now 8001 >/dev/null 2>&1 || fail "sub-second intervals were refused"
echo "ok: the lease interval is floored at the quiet interval, and both accept sub-second values"

echo "ALL PASS: tower-queue next"
