#!/bin/bash
# Tests for scripts/tower-queue.sh's subject batch: `next` handing over one
# item, one pair, or one batch of the items on the top item's subject per call,
# capped at tower_batch_max with a pair counting two and joining whole, the
# free-text subject compared after case-folding and whitespace collapse, an item
# with no subject going alone, every member leased so a second tower gets none
# of them, `ack` closing one member at a time, the knock naming the batch, the
# batch logged with its members, and the consequence order with the two
# reviewable kinds (tower-comms REQ-C1.12, REQ-C1.13, REQ-C1.14, REQ-C1.15,
# REQ-C1.16, REQ-G1.9).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"
FIX="$here/fixtures/tower-comms"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

tmp=$(mktemp -d)
tmp=$(cd -P -- "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
errf="$tmp/stderr"

adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
content="$tmp/content"
mkdir -p "$content"
TAB=$(printf '\t')
A=tower-a
B=tower-b

# reset_home <name> — a fresh fleet home, so one section's queue never ranks
# against another's.
reset_home() {
  home="$tmp/$1"
  mkdir -p "$home"
  chmod 0700 "$home"
  surface="$home/tower-comms"
  store="$surface/queue"
  log_file="$surface/events.log"
  attn_dir="$home/attention"
  attn_store="$attn_dir/state"
}

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@" 2>"$errf"
}

# attention_row <worker> <scope> <state> <ts> <prio> <q> <def> <opts> [<reason> [<iid>]]
attention_row() {
  mkdir -p "$attn_dir"
  chmod 0700 "$attn_dir"
  {
    printf '%s' "$1"
    shift
    for f in "$@"; do printf '\t%s' "$f"; done
    printf '\n'
  } >>"$attn_store"
}

marker() {
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

rec() { grep "^$1$TAB" "$store" || true; }
fld() { rec "$1" | cut -f "$2"; }
lines_of() { printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t'; }
count_of() { lines_of "$1" "$2" | grep -c . || true; }
ids_of() { lines_of "$1" "$2" | cut -f 2 | tr '\n' ' '; }

add_path() { # add_path <name> <kind> <urgency> <now> [<flag>...]
  _n=$1
  _k=$2
  _u=$3
  _t=$4
  shift 4
  printf '%s %s\n' "$_k" "$_n" >"$content/$_n"
  run add --kind "$_k" --root "$content" --pointer "$_n" --origin operator --urgency "$_u" \
    --closes 'the operator decides' --now "$_t" "$@"
}

seed_store() { # the store exists before any row does, so no rebuild adds a row early
  printf 'seed request\n' >"$content/seed-$1"
  _s=$(run add --kind request --root "$content" --pointer "seed-$1" --origin operator --closes 'the operator decides' --now 900) || fail "seed the store"
  run settle "$_s" --reason 'the seed is not under test' --now 901 >/dev/null || fail "settle the seed"
}

# hand <tower> <knock-at> — knock, reply, and hand over; prints the hand-over.
hand() {
  run next --tower "$1" --now "$2" >"$tmp/knock" || fail "the knock for $1 at $2"
  grep -q "^knock$TAB" "$tmp/knock" || fail "no knock for $1 at $2: $(cat "$tmp/knock")"
  marker "$1" $(($2 + 1))
  run next --tower "$1" --now $(($2 + 2)) || fail "the hand-over for $1 at $(($2 + 2))"
}

printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"

# --- the Done-when fixture: four kinds on one PR, one on another (REQ-C1.14) ---------

reset_home done-when
seed_store dw
attention_row w-q spec/t1 awaiting-input 1000 normal 'Which base?' main 'main|dev' fork iid-q
attention_row w-s spec/t2 awaiting-input 1000 normal 'Keep the name?' A 'A|B' fork iid-s
attention_row w-n spec/t3 'done' 1000 normal - - - - iid-n
q=$(run add --kind question --worker w-q --origin w-q --closes 'the operator answers' --subject pr:7 --now 1000) || fail "add the question"
ap=$(add_path ap approval normal 1000 --subject pr:7) || fail "add the approval"
s=$(run add --kind question --worker w-s --origin w-s --closes 'the operator answers' \
  --options 'A|B' --end B --gate none --window 500ms --subject pr:7 --now 1000) || fail "add the picklist question"
nw=$(run add --kind news --worker w-n --origin w-n --closes 'the operator reads it' --subject pr:7 --now 1000) || fail "add the news"
r8=$(add_path r8 request normal 1000 --subject pr:8) || fail "add the other PR's request"
run settle --now 1001 >/dev/null || fail "the settling pass that applies the window"
[ "$(fld "$s" 2)" = settled-by-default ] || fail "the fixture's window did not default: '$(fld "$s" 2)'"

out=$(run knock --now 1009) || fail "the knock verb"
[ "$(printf '%s\n' "$out" | cut -f 5)" = 3 ] || fail "the knock verb does not name a batch of three: '$out'"
out=$(run next --tower $A --now 1010) || fail "the batch knock"
[ "$(lines_of "$out" knock | cut -f 5)" = 3 ] || fail "the knock does not name a batch of three: '$out'"
case "$out" in *pr:7* | *"$q"*) fail "the knock leaked the batch's subject or an item" ;; esac
echo "ok: the knock names the batch by its size and nothing more"

marker $A 1011
out=$(run next --tower $A --now 1012) || fail "the batch hand-over"
[ "$(count_of "$out" batch)" = 1 ] || fail "no batch line heads the hand-over: '$out'"
[ "$(lines_of "$out" batch | cut -f 2)" = 3 ] || fail "the batch line does not count three: '$out'"
[ "$(ids_of "$out" item)" = "$q $ap $s " ] || fail "the batch is not the first PR's top three in consequence order: '$(ids_of "$out" item)'"
[ "$(lines_of "$out" batch | cut -f 3)" = "$q,$ap,$s" ] || fail "the batch line does not list its members in order: '$out'"
for m in "$q" "$ap" "$s"; do
  [ "$(fld "$m" 19)" = $A ] || fail "batch member $m is not leased to the calling tower"
  [ "$(fld "$m" 14)" = 1012 ] || fail "batch member $m was not stamped delivered"
done
for m in "$nw" "$r8"; do
  [ "$(fld "$m" 19)" = - ] || fail "$m is leased though it is not in the batch"
  [ "$(fld "$m" 14)" = 0 ] || fail "$m was stamped delivered though it is not in the batch"
done
grep -q "\"kind\":\"delivered\",\"tower\":\"$A\".*\"batch\":\"$q,$ap,$s\"" "$log_file" \
  || fail "the delivered line does not carry the batch's members"
grep -q "\"kind\":\"delivered\",\"tower\":\"$A\".*\"size\":3" "$log_file" || fail "the delivered line does not carry the batch's size"
echo "ok: the first PR's top three go over as one batch, leased and logged with their members; the fourth and the other PR's item wait"

# One hand-over per call: the batch was it, and nothing more without a reply
# (REQ-C1.12, REQ-C1.15).
out=$(run next --tower $A --now 1013) || fail "next after the batch"
[ -z "$out" ] || fail "a second hand-over followed the batch with no reply: '$out'"

# A second tower never receives a member of a leased batch.
out=$(hand $B 1020)
got=$(ids_of "$out" item)
case "$out" in *"$q"* | *"$ap"* | *"$s"*) fail "tower B was handed a member of tower A's batch: '$out'" ;; esac
marker $B 1030
out=$(run next --tower $B --now 1031) || fail "tower B's second hand-over"
got="$got $(ids_of "$out" item)"
case "$out" in *"$q"* | *"$ap"* | *"$s"*) fail "tower B was handed a member of tower A's batch: '$out'" ;; esac
case "$got" in *"$r8"*) ;; *) fail "tower B was not handed the other PR's item: '$got'" ;; esac
case "$got" in *"$nw"*) ;; *) fail "tower B was not handed the item the batch left waiting: '$got'" ;; esac
echo "ok: a second tower receives none of a leased batch's members"

# `ack` acts on one member: the others stay open and nothing is released.
run ack "$ap" --tower $A --now 1040 >/dev/null || fail "ack one member"
[ "$(fld "$ap" 12)" = closed ] || fail "ack did not close the member"
[ "$(fld "$q" 12)" = open ] || fail "ack on one member closed another"
[ "$(fld "$s" 12)" = open ] || fail "ack on one member closed another"
[ "$(fld "$q" 19)" = $A ] || fail "ack on one member released another's lease"
out=$(run next --tower $A --now 1041) || fail "next after the member ack"
[ -z "$out" ] || fail "acknowledging a member released a hand-over: '$out'"
run revoke "$s" --tower $A --now 1042 >/dev/null || fail "revoke one member"
[ "$(fld "$q" 12)" = open ] || fail "revoking one member closed another"
echo "ok: ack and revoke act on one member at a time and release nothing"

# --- the free-text subject: case and spacing fold, a word does not -------------------

reset_home topic
seed_store tp
t1=$(add_path t1 request normal 1000 --topic 'Release  Notes') || fail "add t1"
t2=$(add_path t2 approval normal 1001 --topic 'release notes') || fail "add t2"
t3=$(add_path t3 request normal 1002 --topic 'release plans') || fail "add t3"
out=$(hand $A 1010)
[ "$(ids_of "$out" item)" = "$t2 $t1 " ] || fail "two topics differing only in case and spacing did not batch: '$(ids_of "$out" item)'"
case "$out" in *"$t3"*) fail "a topic differing in one word joined the batch" ;; esac
[ "$(fld "$t3" 19)" = - ] || fail "the other topic's item was leased"
echo "ok: free-text subjects batch after case-folding and whitespace collapse, and a different word does not"

# --- an item with no subject goes alone ---------------------------------------------

reset_home nosubject
seed_store ns
u1=$(add_path u1 request normal 1000) || fail "add u1"
u2=$(add_path u2 request normal 1001) || fail "add u2"
[ "$(fld "$u1" 21)" = - ] && [ "$(fld "$u1" 32)" = - ] || fail "the fixture item carries a subject"
out=$(hand $A 1010)
[ "$(count_of "$out" item)" = 1 ] || fail "an item with no subject was batched: '$out'"
[ "$(count_of "$out" batch)" = 0 ] || fail "a lone item carried a batch line: '$out'"
[ "$(ids_of "$out" item)" = "$u1 " ] || fail "the wrong item went alone: '$out'"
[ "$(fld "$u2" 19)" = - ] || fail "a second item with no subject was leased"
echo "ok: an item naming no subject is handed over alone"

# --- a pair that would overflow the cap waits whole ---------------------------------

reset_home overflow
seed_store ov
attention_row w-o spec/t1 awaiting-input 1000 high 'Ship it?' yes 'yes|no' fork iid-o
oq=$(run add --kind question --worker w-o --origin w-o --closes 'the operator answers' --subject pr:9 --now 1000) || fail "add the question"
oa=$(add_path oa approval normal 1001 --subject pr:9) || fail "add the approval"
p1=$(add_path p1 request normal 1002 --subject pr:9) || fail "add p1"
p2=$(add_path p2 request normal 1003 --subject pr:9) || fail "add p2"
out=$(hand $A 1010)
[ "$(ids_of "$out" item)" = "$oq $oa " ] || fail "the batch before the pair is not the question and the approval: '$(ids_of "$out" item)'"
[ "$(count_of "$out" pair)" = 0 ] || fail "a pair that would overflow the cap joined: '$out'"
[ "$(fld "$p1" 19)" = - ] && [ "$(fld "$p2" 19)" = - ] || fail "a member of the overflowing pair was leased"
run ack "$oq" --tower $A --now 1020 >/dev/null || fail "ack oq"
run ack "$oa" --tower $A --now 1021 >/dev/null || fail "ack oa"
marker $A 1022
out=$(run next --tower $A --now 1023) || fail "the pair's hand-over"
[ "$(ids_of "$out" item)" = "$p1 " ] || fail "the pair did not lead the next hand-over: '$out'"
[ "$(ids_of "$out" pair)" = "$p2 " ] || fail "the pair did not go over whole: '$out'"
[ "$(count_of "$out" batch)" = 0 ] || fail "a lone pair carried a batch line: '$out'"
[ "$(grep -c '"kind":"knocked"' "$log_file")" = 1 ] || fail "the second hand-over of the attention session knocked afresh"
echo "ok: a pair counts two, waits whole when it would overflow, and follows on the next reply with no fresh knock"

# A pair that fits joins as its pair: one item line and one pair line inside the batch.
reset_home pairfits
seed_store pf
fa=$(add_path fa approval normal 1000 --subject pr:10) || fail "add fa"
f1=$(add_path f1 request normal 1001 --subject pr:10) || fail "add f1"
f2=$(add_path f2 request normal 1002 --subject pr:10) || fail "add f2"
fz=$(add_path fz request normal 999) || fail "add fz"
out=$(hand $A 1010)
[ "$(ids_of "$out" item)" = "$fa $f1 " ] || fail "the batch with a fitting pair is wrong: '$(ids_of "$out" item)'"
[ "$(ids_of "$out" pair)" = "$f2 " ] || fail "the fitting pair did not join as its pair: '$out'"
[ "$(lines_of "$out" batch | cut -f 2)" = 3 ] || fail "the pair did not count two: '$out'"
[ "$(lines_of "$out" batch | cut -f 3)" = "$fa,$f1,$f2" ] || fail "the batch line does not list the pair partner: '$out'"
[ "$(fld "$fz" 19)" = - ] || fail "an item naming no subject joined a subject batch"
echo "ok: a pair that fits joins the batch as its pair, counting two"

# A rule on the subject goes over once with a lone pair, as with a batch.
reset_home pairrule
seed_store pr
prule=$(run capture --kind standing --text 'always prefer the smaller PR on pr 30' \
  --covers 'anything about pr 30' --subject pr:30 --now 1000 | cut -f 2) || fail "capture the rule"
pa=$(add_path pa approval normal 1001 --subject pr:30) || fail "add pa"
pb=$(add_path pb approval normal 1002 --subject pr:30) || fail "add pb"
out=$(hand $A 1010)
[ "$(ids_of "$out" item)" = "$pa " ] && [ "$(ids_of "$out" pair)" = "$pb " ] || fail "the two approvals did not go over as a pair: '$out'"
[ "$(count_of "$out" rule)" = 1 ] || fail "the subject's rule was not printed exactly once beside the pair: '$out'"
[ "$(lines_of "$out" rule | cut -f 2)" = "$prule" ] || fail "the rule line names the wrong decision: '$out'"
echo "ok: a lone pair prints its subject's rule once"

# The cap is the knob's.
reset_home cap
seed_store cp
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_batch_max: 2\n' >"$local_cfg"
attention_row w-c spec/t1 awaiting-input 1000 normal 'Ship it?' yes 'yes|no' fork iid-c
c1=$(run add --kind question --worker w-c --origin w-c --closes 'the operator answers' --subject pr:11 --now 1000) || fail "add c1"
c2=$(add_path c2 approval normal 1001 --subject pr:11) || fail "add c2"
c3=$(add_path c3 request normal 1002 --subject pr:11) || fail "add c3"
out=$(hand $A 1010)
[ "$(ids_of "$out" item)" = "$c1 $c2 " ] || fail "tower_batch_max 2 did not bound the batch: '$out'"
[ "$(fld "$c3" 19)" = - ] || fail "the item past the cap was leased"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
echo "ok: tower_batch_max bounds the batch"

# --- the consequence order with the two reviewable kinds (REQ-C1.13) ----------------

reset_home order
seed_store od
MC=mc-fixture-mission-control-0a1b2c3d4e
reg="$home/mission-control/sessions"
mkdir -p "$reg"
chmod 0700 "$home/mission-control" "$reg"
cp "$FIX/registry-mission-control.row" "$reg/$MC"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/tmux" <<'STUB'
case $1 in
  list-windows) printf '@7\n@8\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH"
export PATH
attention_row w-oq spec/t1 awaiting-input 1000 normal 'Which base?' main 'main|dev' fork iid-oq
attention_row w-os spec/t2 awaiting-input 1000 normal 'Keep the name?' A 'A|B' fork iid-os
attention_row w-on spec/t3 'done' 1000 normal - - - - iid-on
run add --kind news --worker w-on --origin w-on --closes 'the operator reads it' --now 1000 >/dev/null || fail "add news"
PLANWRIGHT_MC_TOKEN="100-fixture""-mc" run add --kind decided-by-mission-control --origin mission-control --tower "$MC" \
  --text 'retried the flaky job' --grounds undo:u-17 --reversal undo:u-17 --gate none --now 1000 >/dev/null || fail "add the decided item"
run add --kind question --worker w-os --origin w-os --closes 'the operator answers' \
  --options 'A|B' --end B --gate none --window 500ms --now 1000 >/dev/null || fail "add the picklist question"
add_path o_r request normal 1000 >/dev/null || fail "add the request"
add_path o_a approval normal 1000 >/dev/null || fail "add the approval"
run add --kind question --worker w-oq --origin w-oq --closes 'the operator answers' --now 1000 >/dev/null || fail "add the question"
run settle --now 1001 >/dev/null || fail "the settling pass"
printf 'tower_quiet_interval: 2h\ntower_lease_interval: 2h\n' >"$local_cfg"
run next --tower $A --now 1010 >/dev/null || fail "the order knock"
order=""
t=1011
while :; do
  marker $A "$t"
  out=$(run next --tower $A --now $((t + 1))) || fail "next at $((t + 1))"
  [ -n "$out" ] || break
  [ "$(count_of "$out" item)" = 1 ] || fail "items on distinct subjects were batched: '$out'"
  order="$order $(lines_of "$out" item | cut -f 3)"
  t=$((t + 2))
done
[ "$order" = " question approval request settled-by-default decided-by-mission-control news" ] \
  || fail "the consequence order is wrong:$order"
echo "ok: blocked worker, approval, request, settled-by-default, decided-by-mission-control, news"

# A batch ranks as its highest member: news riding a question's subject goes
# over ahead of an approval on another subject.
reset_home rank
seed_store rk
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
attention_row w-rq spec/t1 awaiting-input 1000 normal 'Which base?' main 'main|dev' fork iid-rq
attention_row w-rn spec/t2 'done' 1000 normal - - - - iid-rn
rq=$(run add --kind question --worker w-rq --origin w-rq --closes 'the operator answers' --subject pr:20 --now 1000) || fail "add rq"
rn=$(run add --kind news --worker w-rn --origin w-rn --closes 'the operator reads it' --subject pr:20 --now 1000) || fail "add rn"
ra=$(add_path ra approval high 990 --subject pr:21) || fail "add ra"
out=$(hand $A 1010)
[ "$(ids_of "$out" item)" = "$rq $rn " ] || fail "the batch did not rank as its highest member: '$(ids_of "$out" item)'"
[ "$(fld "$ra" 19)" = - ] || fail "the approval on another subject was handed over with the batch"
echo "ok: a batch ranks as its highest member"

# The knock pins its item: a higher-ranked member arriving on the same subject
# between the knock and the reply joins the hand-over behind it, never ahead.
reset_home pin
seed_store pn
attention_row w-pq spec/t1 awaiting-input 1000 normal 'Which base?' main 'main|dev' fork iid-pq
pa=$(add_path pa approval normal 1000 --subject pr:30) || fail "add pa"
run next --tower $A --now 1010 >"$tmp/knock" || fail "the knock on pa"
grep -q "^knock$TAB" "$tmp/knock" || fail "no knock on pa: $(cat "$tmp/knock")"
pq=$(run add --kind question --worker w-pq --origin w-pq --closes 'the operator answers' --subject pr:30 --now 1011) || fail "add pq"
marker $A 1012
out=$(run next --tower $A --now 1013) || fail "the hand-over after the reply"
[ "$(ids_of "$out" item)" = "$pa $pq " ] || fail "the knock's pinned item did not lead the hand-over: '$(ids_of "$out" item)'"
echo "ok: the knock's pinned item leads the hand-over"

echo "ALL PASS: tower-queue batch"
