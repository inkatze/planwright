#!/bin/bash
# Tests for scripts/tower-queue.sh's queue store under the fleet lock: the
# concurrent-writer and lock-saturation cases, the owner-only surface, and
# the rebuild from the content homes when the store is lost (REQ-A1.4,
# REQ-A1.5, REQ-F1.5, REQ-G1.1). Split from test-tower-queue-store.sh so each
# file stays inside the per-file wall-clock budget.
#
# Contract under test:
#   Every write rides the fleet advisory lock, bounded by tower_hook_lock_wait
#   (exit 3 at expiry, nothing written), and lands by temp and atomic rename
#   after the store is re-read and compared. The store, the delivery records
#   and the attention markers are owner-only inside the 0700 sub-surface, a
#   loosened mode refusing the write (exit 4). An absent store is rebuilt
#   inside the lock from the attention rows and the event log's born lines,
#   with the same identifiers, a delivered-but-open item delivered once more,
#   a shelved item returning at once, a settled item absent, and an
#   attention-sourced item whose row moved on dropped and logged.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"
FS="$here/../scripts/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"

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
record_count() { if [ -f "$store" ]; then grep -c . "$store" || true; else printf 0; fi; }
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

add_req() { # add_req <name> <now>
  printf 'request %s\n' "$1" >"$content/$1"
  run add --kind request --root "$content" --pointer "$1" --origin operator --closes 'the operator decides' --now "$2"
}

A=tower-a

# --- concurrent writers: every record lands whole (REQ-A1.4) -----------------------

(
  i=0
  while [ "$i" -lt 8 ]; do
    printf 'a%s\n' "$i" >"$content/a$i"
    run add --kind request --root "$content" --pointer "a$i" --origin operator --closes 'the operator decides' --now $((100 + i)) >/dev/null 2>&1
    i=$((i + 1))
  done
) &
(
  i=0
  while [ "$i" -lt 8 ]; do
    printf 'b%s\n' "$i" >"$content/b$i"
    run add --kind approval --root "$content" --pointer "b$i" --origin tower --closes 'the operator gives the go-ahead' --now $((200 + i)) >/dev/null 2>&1
    i=$((i + 1))
  done
) &
wait
[ "$(record_count)" = 16 ] || fail "two writers: $(record_count) records, expected 16"
while IFS= read -r l; do
  nf=$(printf '%s\n' "$l" | awk -F '\t' '{ print NF }')
  [ "$nf" = 25 ] || fail "torn record under two writers ($nf fields): $l"
  case "$l" in
    i[0-9a-f]*"$TAB"open"$TAB"*) ;;
    *) fail "malformed record under two writers: $l" ;;
  esac
done <"$store"
[ "$(cut -f 1 "$store" | sort | uniq -d | wc -l | tr -d ' ')" = 0 ] || fail "duplicate identifiers under two writers"
[ "$(grep -c '"kind":"born"' "$log_file")" = 16 ] || fail "two writers: $(grep -c '"kind":"born"' "$log_file") born lines, expected 16"
echo "ok: sixteen records from two concurrent writers, none torn, every birth logged"

# Concurrent acks against concurrent adds: the store is read intact by every
# later process and every record keeps its shape.
marker $A 300
run next --tower $A --now 301 >/dev/null || fail "knock before the mixed round"
marker $A 302
first=$(run next --tower $A --now 303) || fail "deliver before the mixed round"
# The eight approvals share a subject, so the hand-over is a pair (REQ-B1.3):
# the `item` line first, then its `pair` line. This round is about the store
# under concurrency, so it acts on the item line alone.
fid=$(field "$first" 2 | head -n 1)
ids=$(cut -f 1 "$store" | grep -v "^$fid$" | head -n 4)
(
  run ack "$fid" --tower $A --now 304 >/dev/null 2>&1
  for id in $ids; do
    run settle "$id" --reason 'evidence: merged' --now 305 >/dev/null 2>&1
  done
) &
(
  i=0
  while [ "$i" -lt 4 ]; do
    printf 'c%s\n' "$i" >"$content/c$i"
    run add --kind request --root "$content" --pointer "c$i" --origin operator --closes 'the operator decides' --now $((400 + i)) >/dev/null 2>&1
    i=$((i + 1))
  done
) &
wait
[ "$(record_count)" = 20 ] || fail "mixed round: $(record_count) records, expected 20"
[ "$(rec "$fid" | cut -f 12)" = closed ] || fail "mixed round: the acknowledged item is not closed"
closed=$(awk -F '\t' '$12 == "closed"' "$store" | grep -c . || true)
[ "$closed" = 5 ] || fail "mixed round: $closed closed records, expected exactly 5 (the ack and four settles)"
echo "ok: acks and settles interleaved with adds leave every record whole"

# --- the bounded lock wait: expiry is an error, nothing written (REQ-A1.4) ---------

printf 'tower_hook_lock_wait: 200ms\n' >"$local_cfg"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock for the saturation case"
before=$(cat "$store")
start=$(date +%s)
rc=0
printf 'late\n' >"$content/late"
run add --kind request --root "$content" --pointer late --origin operator --closes 'the operator decides' --now 500 >/dev/null 2>"$tmp/err" || rc=$?
end=$(date +%s)
[ "$rc" = 3 ] || fail "saturated lock (add): exit $rc, expected 3"
[ "$(cat "$store")" = "$before" ] || fail "saturated lock: the store changed"
grep -q 'lock' "$tmp/err" || fail "saturated lock: the expiry was not reported as an error"
[ $((end - start)) -le 2 ] || fail "saturated lock: waited $((end - start))s on a 200ms bound"
rc=0
run next --tower $A --now 501 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 3 ] || fail "saturated lock (next): exit $rc, expected 3"
rc=0
run ack "$fid" --tower $A --now 502 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 3 ] || fail "saturated lock (ack): exit $rc, expected 3"
rc=0
run shelve "$fid" --tower $A --now 502 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 3 ] || fail "saturated lock (shelve): exit $rc, expected 3"
rc=0
run settle "$fid" --reason x --now 502 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 3 ] || fail "saturated lock (settle): exit $rc, expected 3"
[ "$(cat "$store")" = "$before" ] || fail "saturated lock: a verb changed the store"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
: >"$local_cfg"
run add --kind request --root "$content" --pointer late --origin operator --closes 'the operator decides' --now 503 >/dev/null || fail "add after unlock: exit"
[ ! -e "$home/.fleet.lock" ] && [ ! -L "$home/.fleet.lock" ] || fail "a completed write left the fleet lock standing"
echo "ok: every verb bounds its lock wait, reports the expiry, and writes nothing unlocked"

# --- the owner-only surface (REQ-A1.4) -------------------------------------------------

[ "$(mode_of "$surface")" = 700 ] || fail "the sub-surface is not 0700 (mode $(mode_of "$surface"))"
[ "$(mode_of "$store")" = 600 ] || fail "the store is not owner-only (mode $(mode_of "$store"))"
[ "$(mode_of "$surface/delivery")" = 700 ] || fail "the delivery sub-surface is not 0700"
[ "$(mode_of "$surface/delivery/$A")" = 600 ] || fail "the delivery record is not owner-only"

chmod 0755 "$surface"
rc=0
run add --kind request --root "$content" --pointer late --origin operator --closes 'the operator decides' >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 4 ] || fail "widened sub-surface: exit $rc, expected 4"
grep -q 'owner-only' "$tmp/err" || fail "widened sub-surface: not reported"
rc=0
run next --tower $A --now 600 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "widened sub-surface (next): exit $rc, expected 4"
rc=0
run list >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "widened sub-surface (list, the read path): exit $rc, expected 4"
chmod 0700 "$surface"

chmod 0644 "$store"
rc=0
run next --tower $A --now 601 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "widened store: exit $rc, expected 4"
rc=0
run counts >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "widened store (counts, the read path): exit $rc, expected 4"
chmod 0600 "$store"

chmod 0644 "$surface/attention/$A"
rc=0
run next --tower $A --now 602 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "a widened attention marker (a self-satisfiable gate): exit $rc, expected 4"
chmod 0600 "$surface/attention/$A"

chmod 0755 "$surface/attention"
rc=0
run next --tower $A --now 603 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "a widened marker directory: exit $rc, expected 4"
chmod 0700 "$surface/attention"
run next --tower $A --now 604 >/dev/null 2>&1 || fail "next after the modes were restored: exit"
mv "$store" "$tmp/store.real"
ln -s "$tmp/store.real" "$store"
rc=0
run next --tower $A --now 605 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "a store that is a symlink: exit $rc, expected 4"
rm -f "$store"
mv "$tmp/store.real" "$store"
mkdir -p "$tmp/.claude"
printf 'tower_quiet_interval: soon\n' >"$tmp/.claude/planwright.yml"
rc=0
run next --tower $A --now 606 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 4 ] || fail "a malformed repo-tracked knob: exit $rc, expected 4"
grep -q 'tower_quiet_interval' "$tmp/err" || fail "the malformed knob was not named"
rm -f "$tmp/.claude/planwright.yml"
echo "ok: the store, the delivery records and the markers are owner-only, and a loosened mode refuses the verb"

# --- a store written by one process is read intact by the next -------------------------

n1=$(run list | grep -c .)
n2=$(run list | grep -c .)
[ "$n1" = "$n2" ] && [ "$n1" -gt 0 ] || fail "list is not stable across processes ($n1 vs $n2)"
echo "ok: a store one process wrote is read intact by another"

# --- rebuild from the content homes when the store is lost (REQ-A1.5, REQ-F1.5) --------

rm -rf "$surface" "$attn_dir"
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
printf 'w-keep\tspec/t1\tawaiting-input\t1000\thigh\tQ1?\ta\ta|b\tfork\tiid-k\n' >"$attn_store"
printf 'w-gone\tspec/t2\tawaiting-input\t1001\tnormal\tQ2?\ta\ta|b\tfork\tiid-g\n' >>"$attn_store"
printf 'w-news\tspec/t3\tpr-ready\t1002\tnormal\t-\t-\t-\n' >>"$attn_store"
qk=$(run add --kind question --worker w-keep --origin w-keep --closes 'the operator answers' --now 1010 2>/dev/null)
qg=$(run add --kind question --worker w-gone --origin w-gone --closes 'the operator answers' --now 1011 2>/dev/null)
nn=$(run add --kind news --worker w-news --origin w-news --closes 'the operator has read it' --now 1012)
printf 'open request\n' >"$content/r-open"
ro=$(run add --kind request --root "$content" --pointer r-open --origin operator --closes 'the operator decides' --now 1013)
printf 'delivered request\n' >"$content/r-deliv"
rd=$(run add --kind request --root "$content" --pointer r-deliv --origin operator --urgency high --closes 'the operator decides' --now 1014)
printf 'shelved request\n' >"$content/r-shelf"
rs=$(run add --kind request --root "$content" --pointer r-shelf --origin operator --closes 'the operator decides' --now 1015)
printf 'settled request\n' >"$content/r-settled"
rt=$(run add --kind request --root "$content" --pointer r-settled --origin operator --closes 'the operator decides' --now 1016)
printf 'vanished request\n' >"$content/r-vanish"
rv=$(run add --kind request --root "$content" --pointer r-vanish --origin operator --closes 'the operator decides' --now 1017)
[ "$(record_count)" = 8 ] || fail "rebuild fixture: $(record_count) records, expected 8"

# Deliver the question, then the high request (both leased to A and in hand),
# shelve one, settle one, then lose the store and move two homes on.
run next --tower $A --now 1020 >/dev/null || fail "fixture knock"
marker $A 1021
out=$(run next --tower $A --now 1022) || fail "fixture deliver 1"
[ "$(field "$out" 2)" = "$qk" ] || fail "fixture: expected $qk first, got '$out'"
marker $A 1023
out=$(run next --tower $A --now 1024) || fail "fixture deliver 2"
[ "$(field "$out" 2)" = "$qg" ] || fail "fixture: expected $qg second, got '$out'"
marker $A 1025
out=$(run next --tower $A --now 1026) || fail "fixture deliver 3"
[ "$(field "$out" 2)" = "$rd" ] || fail "fixture: expected $rd third, got '$out'"
run ack "$qg" --tower $A --now 1027 >/dev/null || fail "fixture ack qg"
run shelve "$rs" --tower $A --for 1h --now 1028 >/dev/null || fail "fixture shelve"
run settle "$rt" --reason 'evidence: PR merged' --now 1029 >/dev/null || fail "fixture settle"
before_ids=$(cut -f 1 "$store" | sort)
rebuilds_before=$(grep -c '"event":"rebuild"' "$log_file" || true)

# Three more log lines before the loss: a forged birth whose pointer escapes
# its root (a writer can append any key=value through `log`), one whose id
# does not derive from its key, and a settle-then-re-add of one request, so
# the rebuild must honour event order rather than "ever closed".
run log born --now 1029 item=ic0ffee11 item_kind=request urgency=normal origin=operator home=path pointer=../secret root="$content" closes=done >/dev/null || fail "plant a forged born line"
run log born --now 1029 item=i0badbad0 item_kind=request urgency=normal origin=operator home=path pointer=r-open root="$content" closes=done >/dev/null || fail "plant a born line whose id does not derive from its key"
run settle "$ro" --reason 'closed once' --now 1029 >/dev/null || fail "settle ro"
ro2=$(run add --kind request --root "$content" --pointer r-open --origin operator --closes 'the operator decides' --now 1030) || fail "re-add ro"
[ "$ro2" = "$ro" ] || fail "re-adding r-open changed its id"
rm -f "$store"
printf 'w-gone\tspec/t2\tworking\t1030\tnormal\t-\t-\t-\n' >"$tmp/row"
awk -F '\t' '$1 != "w-gone"' "$attn_store" >"$tmp/attn.new"
cat "$tmp/row" >>"$tmp/attn.new"
mv "$tmp/attn.new" "$attn_store"
printf 'w-news\tspec/t3\tmerged\t1031\tnormal\t-\t-\t-\n' >"$tmp/row"
awk -F '\t' '$1 != "w-news"' "$attn_store" >"$tmp/attn.new"
cat "$tmp/row" >>"$tmp/attn.new"
mv "$tmp/attn.new" "$attn_store"
rm -f "$content/r-vanish"
printf 'w-new\tspec/t4\tawaiting-input\t1032\tlow\tQ4?\ta\ta|b\tfork\tiid-n\n' >>"$attn_store"

out=$(run next --tower $A --now 1040 2>"$tmp/err") || fail "next over the lost store: exit"
grep -q 'rebuilt' "$tmp/err" || fail "the rebuild was not announced"
[ -f "$store" ] || fail "no store after the rebuild"
grep -q '"kind":"session".*"event":"rebuild"' "$log_file" || fail "no session rebuild event logged"

rec "$qk" >/dev/null || fail "rebuild lost the open question whose row still awaits input"
[ "$(rec "$qk" | cut -f 8)" = iid-k ] || fail "rebuild lost the question's instance id"
[ "$(rec "$qk" | cut -f 14)" = 0 ] || fail "a rebuilt item should be undelivered (delivered once more, inside the budget)"
rec "$qg" >/dev/null && fail "rebuild resurrected an acknowledged item"
rec "$nn" >/dev/null && fail "rebuild kept a news item whose row moved on"
grep -q "\"kind\":\"dropped\".*\"item\":\"$nn\".*\"reason\":\"rebuild\"" "$log_file" || fail "the dropped news item was not logged"
rec "$ro" >/dev/null || fail "rebuild lost an open request whose content is still at its home (re-opened after a settle, so event order matters)"
[ "$(rec "$ro" | cut -f 12)" = open ] || fail "the re-opened request was rebuilt closed"
grep -q 'ic0ffee11' "$store" && fail "rebuild re-admitted a forged born line whose pointer escapes its root"
grep -q '\.\./secret' "$store" && fail "a traversal pointer reached the store through the rebuild"
[ "$(cut -f 3 "$surface/delivery/$A")" = 0 ] || fail "the rebuild kept a hand-over stamp that described the lost store"
rec "$rd" >/dev/null || fail "rebuild lost the delivered-but-open request"
[ "$(rec "$rd" | cut -f 14)" = 0 ] || fail "the delivered-but-open request was not reset for one redelivery"
rec "$rs" >/dev/null || fail "rebuild lost the shelved request"
[ "$(rec "$rs" | cut -f 16)" = 0 ] || fail "a shelved item did not return at once after the rebuild (its deadline is the store's alone)"
rec "$rt" >/dev/null && fail "rebuild resurrected a settled item (the settled history is the log's)"
rec "$rv" >/dev/null && fail "rebuild kept a request whose content home vanished"
grep -q "\"kind\":\"dropped\".*\"item\":\"$rv\".*\"reason\":\"rebuild\"" "$log_file" || fail "the vanished request's drop was not logged"
new_row=$(awk -F '\t' '$2 == "question" && $7 == "w-new"' "$store")
[ -n "$new_row" ] || fail "rebuild missed an awaiting-input row with no record yet"
[ "$(field "$new_row" 3)" = low ] || fail "the row-derived question did not inherit the row's priority"
nid=$(field "$new_row" 1)
grep -q "\"kind\":\"born\".*\"item\":\"$nid\"" "$log_file" || fail "the row-derived question's birth was not logged"
grep "\"kind\":\"born\".*\"item\":\"$nid\"" "$log_file" | grep -q '"ts":1032,' || fail "the row-derived question's born line does not carry the row's own stamp as its birth"
grep -q 'i0badbad0' "$store" && fail "rebuild re-admitted a born line whose id does not derive from its key"
grep -q '"kind":"dropped".*"item":"i0badbad0".*"reason":"rebuild"' "$log_file" || fail "a born line whose id does not derive from its key was skipped without a dropped line"
after_ids=$(cut -f 1 "$store" | sort)
for id in $qk $ro $rd $rs; do
  printf '%s\n' "$after_ids" | grep -q "^$id$" || fail "identifier $id was not derived identically at rebuild"
done
printf '%s\n' "$before_ids" | grep -q "^$qk$" || fail "fixture: $qk missing before the loss"
[ "$(record_count)" = 5 ] || fail "rebuilt store holds $(record_count) records, expected 5 (the open question, three requests, the new row)"
echo "ok: a lost store rebuilds from the content homes with the same identifiers, redelivering at most once and dropping only what moved on"

# The rebuild cleared the tower's own delivery record with the store, so the
# rebuilt queue starts with a knock; the reply then releases the rebuilt
# question once more.
[ "$(field "$out" 1)" = knock ] || fail "the first next after the rebuild did not knock: '$out'"
marker $A 1041
out=$(run next --tower $A --now 1042) || fail "next after rebuild"
[ "$(field "$out" 2)" = "$qk" ] || fail "after the rebuild the open question was not delivered first: '$out'"
[ "$(grep -c "\"kind\":\"delivered\".*\"item\":\"$qk\"" "$log_file")" = 2 ] || fail "the question was delivered other than exactly twice across the loss"
echo "ok: a delivered-but-open item is delivered again exactly once across a store loss"

# A second call finds the store present and rebuilds nothing.
marker $A 1043
run next --tower $A --now 1044 >/dev/null 2>"$tmp/err" || fail "next with the store present"
grep -q 'rebuilt' "$tmp/err" && fail "a present store was rebuilt"
[ "$(grep -c '"event":"rebuild"' "$log_file")" = $((rebuilds_before + 1)) ] || fail "the loss was rebuilt more than once"
echo "ok: a present store is authoritative and is never rescanned"

# --- a store that appears while a rebuild runs is never overwritten ----------------

# The snapshot guard covers a store that changed or vanished under the lock;
# one that appears while the rebuild runs (the lock broken) is the other half.
# A head on PATH that plants a store the moment the rebuild reads its
# candidate list (after its absent check, before its commit) stands in for
# the intruding writer.
shim="$tmp/shim"
mkdir -p "$shim"
real_head=$(command -v head)
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$3" in */cands) echo intruder >"%s" ;; esac\nexec "%s" "$@"\n' "$store" "$real_head" >"$shim/head"
chmod +x "$shim/head"
rm -f "$store"
rc=0
PATH="$shim:$PATH" run next --tower tower-x --now 7000 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 6 ] || fail "a store appearing under a rebuild: exit $rc, expected 6"
grep -q 'changed while this verb held the fleet lock' "$tmp/err" || fail "the rebuild did not name the broken lock"
[ "$(cat "$store")" = intruder ] || fail "the rebuild overwrote a store that appeared under the lock"
rm -f "$store"
# The same with a directory at the store's path: a rename would land the
# store inside it and leave the path non-regular.
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$3" in */cands) mkdir -p "%s" ;; esac\nexec "%s" "$@"\n' "$store" "$real_head" >"$shim/head"
rm -f "$surface/rebuild.debt"
rc=0
PATH="$shim:$PATH" run next --tower tower-x --now 7001 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 6 ] || fail "a directory appearing at the store path under a rebuild: exit $rc, expected 6"
[ -d "$store" ] && [ -z "$(ls -A "$store")" ] || fail "the rebuild renamed the store into a directory that appeared at its path"
rmdir "$store"
echo "ok: a store that appears while a rebuild runs is left alone and the verb refuses"

# --- the rebuild's log debt: durable before the store, paid once, never wedged ------

# The refused rebuild above left its debt behind (the debt lands first, so
# the safe failure is a debt with no store, never the reverse); clear it.
rm -f "$surface/rebuild.debt"
# A directory where the debt file goes: the rebuild must refuse before it
# commits a store whose births could then never be logged.
mkdir "$surface/rebuild.debt"
rc=0
run next --tower $A --now 9000 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 6 ] || fail "a rebuild that cannot write its log debt: exit $rc, expected 6"
[ ! -f "$store" ] || fail "a rebuild committed the store before its log debt was durable"
rmdir "$surface/rebuild.debt"

# A predecessor's debt with one line the log can never take: the payable
# lines land exactly once, the unpayable one is reported and dropped, the
# file goes, and the verb's own exit code is untouched.
printf 'session\nborn\ti0000000a\trequest\tnormal\toperator\t1000\tpath\tr-a\t-\t/r\t-\tdone\nborn\ti0000000b\trequest\tnormal\toperator\t1000\tpath\t{x}\t-\t/r\t-\tdone\n' >"$surface/rebuild.debt"
chmod 0600 "$surface/rebuild.debt"
rc=0
run settle i000000ff --reason x --now 9010 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "settling an absent item while paying a debt: exit $rc, expected the verb's own 2"
[ "$(grep -c '"kind":"born".*"item":"i0000000a"' "$log_file")" = 1 ] || fail "a payable debt line did not land exactly once"
grep '"kind":"born".*"item":"i0000000a"' "$log_file" | grep -q '"ts":1000,' || fail "a paid born line does not carry the item's own birth stamp"
grep -q '"item":"i0000000b"' "$log_file" && fail "an unpayable debt line reached the log"
grep -q 'i0000000b' "$tmp/err" || fail "the unpayable debt line was dropped silently"
[ ! -f "$surface/rebuild.debt" ] || fail "the debt file survived a drain that paid every payable line"
run settle i000000ff --reason x --now 9011 >/dev/null 2>&1 || true
[ "$(grep -c '"kind":"born".*"item":"i0000000a"' "$log_file")" = 1 ] || fail "a paid debt line was paid again"

# Nothing to rebuild from (no log, no rows): the rebuild still clears the
# delivery records that described the lost store and logs its session.
rm -f "$store" "$log_file"
: >"$attn_store"
mkdir -p "$surface/delivery"
printf '1000\ti00000001\t1001\ti00000001\n' >"$surface/delivery/$A"
chmod 0600 "$surface/delivery/$A"
run settle i000000ff --reason x --now 9020 >/dev/null 2>&1 || true
[ -f "$store" ] || fail "an empty rebuild wrote no store"
[ ! -f "$surface/delivery/$A" ] || fail "an empty rebuild kept a delivery record that described the lost store"
grep -q '"kind":"session".*"event":"rebuild"' "$log_file" || fail "an empty rebuild logged no session line"
echo "ok: the rebuild's log debt is durable before the store, paid exactly once, and an unpayable line never wedges the queue"

# --- a foreign-owned attention store is refused by name -------------------------------

shim2="$tmp/shim2"
mkdir -p "$shim2"
real_ls=$(command -v ls)
cat >"$shim2/ls" <<EOF
#!/bin/sh
case "\$*" in
  *"$attn_store") echo "-rw------- 1 99999 99999 0 Jan  1 00:00 $attn_store" ;;
  *) exec "$real_ls" "\$@" ;;
esac
EOF
chmod +x "$shim2/ls"
rc=0
PATH="$shim2:$PATH" run next --tower $A --now 9030 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 4 ] || fail "a foreign-owned attention store: exit $rc, expected 4"
grep -q "$attn_store" "$tmp/err" || fail "the refusal does not name the foreign-owned path: $(cat "$tmp/err")"
echo "ok: a foreign-owned attention store is refused by name"

# --- shelve validates its span before it takes the lock ------------------------------

rm -f "$store"
rc=0
run shelve i00000001 --for bogus --now 9040 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a malformed --for: exit $rc, expected 2"
[ ! -f "$store" ] || fail "a malformed --for took the lock and rebuilt the store before it was refused"
echo "ok: shelve refuses a malformed span before it touches the store"

# --- a store swapped for a link under the lock is refused even when it reads the same --

run settle i000000ff --reason x --now 9060 >/dev/null 2>&1 || true
[ -f "$store" ] || fail "fixture: no store to swap"
shim3="$tmp/shim3"
mkdir -p "$shim3"
real_sort=$(command -v sort)
cat >"$shim3/sort" <<EOF
#!/bin/sh
if [ -f "$store" ] && [ ! -L "$store" ]; then cp "$store" "$store.copy" && ln -sf "$store.copy" "$store"; fi
exec "$real_sort" "\$@"
EOF
chmod +x "$shim3/sort"
printf 'x\n' >"$content/r-link"
rc=0
PATH="$shim3:$PATH" run add --kind request --root "$content" --pointer r-link --origin operator --closes 'the operator decides' --now 9061 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 6 ] || fail "a store swapped for a link while the verb held the lock: exit $rc, expected 6"
[ -L "$store" ] || fail "the commit replaced a link that appeared at the store's path"
rm -f "$store"
mv "$store.copy" "$store"
echo "ok: a store swapped for a link under the lock is refused, however it reads"

echo "ALL PASS: tower-queue store lock"
