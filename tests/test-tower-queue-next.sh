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
run ack i00000000 --tower $A --now 1610 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "ack of an unknown item: exit $rc, expected 2"
out=$(run next --tower $A --now 1610) || fail "next after the refused acks: exit"
[ -z "$out" ] || fail "a refused or no-op ack released a further item: '$out'"
[ "$(rec "$x2" | cut -f 12)" = open ] || fail "the delivered, unacknowledged item did not stay open"
echo "ok: ack is refused without a lease and a logged no-op on a closed item, and neither releases anything"

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
add_req y1 low 2000 >/dev/null
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

# --- a lapsed lease makes the item deliverable again to the same tower ------------

# y2 and y3 are in A's hands (delivered 2005 and 2008, no ack). The leases
# backstop at 2205 and 2208 and A's last reply (2007) renews them to 2207 at
# most; at 2300 both have lapsed, so the hand-overs are void and the older
# of the two high items is A's to knock about and receive again.
out=$(run next --tower $A --now 2300) || fail "next after the lease lapsed"
[ "$(field "$out" 1)" = knock ] || fail "a lapsed hand-over was not knocked about again: '$out'"
marker $A 2301
out=$(run next --tower $A --now 2302) || fail "redeliver after lapse"
[ "$(field "$out" 2)" = "$y2" ] || fail "the same tower was not handed its lapsed item again: '$out'"
[ "$(grep -c "\"kind\":\"delivered\".*\"item\":\"$y2\"" "$log_file")" = 2 ] || fail "the lapsed item was not delivered exactly twice"
run ack "$y2" --tower $A --now 2303 >/dev/null || fail "ack y2 after redelivery"
marker $A 2304
out=$(run next --tower $A --now 2305) || fail "redeliver y3"
[ "$(field "$out" 2)" = "$y3" ] || fail "the second lapsed item did not follow: '$out'"
run ack "$y3" --tower $A --now 2306 >/dev/null || fail "ack y3 after redelivery"
echo "ok: a hand-over whose lease lapsed is deliverable again, to the same tower included"

# --- a reply stamped in the knock's own second confirms attention -----------------

# Past the quiet interval since the last hand-over, so the knock is fresh.
w1=$(add_req w1 normal 2499)
out=$(run next --tower $A --now 2500) || fail "knock w1"
[ "$(field "$out" 1)" = knock ] || fail "expected a knock for w1: '$out'"
marker $A 2500
out=$(run next --tower $A --now 2501) || fail "deliver w1"
[ "$(field "$out" 2)" = "$w1" ] || fail "a reply in the knock's own second did not confirm attention: '$out'"
run ack "$w1" --tower $A --now 2502 >/dev/null
echo "ok: a reply stamped in the same second as the knock releases the item"

# --- one reply releases one item; the next needs a later reply (REQ-C1.10) ----------

# Past the quiet interval since the last hand-over. The reply in the knock's
# second confirms attention and releases v1; a hand-over stamped in that
# same second is then the tower's last outbound, and the same reply must
# not release v2 behind it.
v1=$(add_req v1 normal 2600)
v2=$(add_req v2 normal 2601)
add_req v3 normal 2602 >/dev/null
out=$(run next --tower $A --now 2610) || fail "knock v1"
[ "$(field "$out" 1)" = knock ] || fail "expected a knock for v1: '$out'"
waiting=$(field "$out" 4)
marker $A 2610
out=$(run next --tower $A --now 2610) || fail "deliver v1"
[ "$(field "$out" 2)" = "$v1" ] || fail "a reply in the knock's second did not release v1: '$out'"
out=$(run next --tower $A --now 2611) || fail "next after v1 with no new reply"
[ -z "$out" ] || fail "the reply that released v1 released a second item: '$out'"
marker $A 2611
out=$(run next --tower $A --now 2612) || fail "deliver v2"
[ "$(field "$out" 2)" = "$v2" ] || fail "a later reply did not release v2: '$out'"
# Attention lapses with v1 and v2 unacknowledged and in hand: the knock about
# v3 counts what is waiting for this tower, not what it already holds.
out=$(run next --tower $A --now 2720 2>/dev/null) || fail "knock v3 after the quiet interval"
[ "$(field "$out" 1)" = knock ] || fail "expected a knock for v3: '$out'"
[ "$(field "$out" 4)" = $((waiting - 2)) ] || fail "the knock's waiting count includes items already in this tower's hand: '$out' (was $waiting before two hand-overs)"
echo "ok: one reply releases one item, the next hand-over needs a later reply, and the knock counts only what is waiting"

# --- a marker stamped in the future confirms nothing ----------------------------------

# A skewed clock or a planted marker can stamp a reply past now; until the
# clock reaches it, it is no reply.
run ack "$v2" --tower $A --now 2721 >/dev/null || fail "ack v2"
marker $A 99999
out=$(run next --tower $A --now 2722) || fail "next with a future marker"
[ -z "$out" ] || fail "a marker stamped in the future confirmed attention: '$out'"
echo "ok: a marker stamped in the future confirms nothing"

echo "ALL PASS: tower-queue next"
