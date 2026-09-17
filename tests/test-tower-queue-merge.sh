#!/bin/bash
# Tests for scripts/tower-queue.sh's merging and pairing (REQ-B1.3) — the
# duplicate questions the settling pass collapses into one item naming every
# source, the command-bearing items it refuses to collapse on anything but
# byte equality, and the shared-subject pair `next` hands over as one unit.
# The settling pass itself is in test-tower-queue-settle.sh.
#
# Contract under test:
#   settle (no id)   merges open, unleased, undelivered candidates of one kind
#                    whose normalised question text and option set are
#                    identical; the survivor carries the highest urgency, the
#                    oldest birth, and every source; the others close as
#                    `merged into <id>`. An item carrying a worker command
#                    merges only on byte equality after the same removal.
#   next             pairs at most two open, unleased, undelivered items of one
#                    kind naming the same subject key and hands them over as
#                    one unit: the `item` line naming both sources at the
#                    higher urgency and the older age, then a `pair` line. The
#                    partner is the oldest candidate on the subject.
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

adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
content="$tmp/content"
mkdir -p "$content"
ev="$tmp/evidence"
: >"$ev"
chmod 0600 "$ev"

TAB=$(printf '\t')

# reset_home <name> — a fresh fleet home, so one section's queue never ranks
# ahead of the next section's fixtures.
reset_home() {
  home="$tmp/$1"
  mkdir -p "$home"
  chmod 0700 "$home"
  surface="$home/tower-comms"
  store="$surface/queue"
  attn_dir="$home/attention"
  attn_store="$attn_dir/state"
}

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

# attention_row <worker> <scope> <state> <ts> <prio> <question> <default> <options> [<reason> <iid> <claim> <command>]
attention_row() {
  mkdir -p "$attn_dir"
  chmod 0700 "$attn_dir"
  printf '%s' "$1" >>"$attn_store"
  shift
  for f in "$@"; do printf '\t%s' "$f" >>"$attn_store"; done
  printf '\n' >>"$attn_store"
}

marker() {
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

rec() { grep "^$1$TAB" "$store" || true; }
state_of() { rec "$1" | cut -f 12; }
field() { printf '%s\n' "$1" | cut -f "$2"; }
line_of() { printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t { print; exit }'; }

# --- two workers asking the same thing merge into one naming both -----------------

reset_home merge
attention_row w-alpha /wt/w-alpha awaiting-input 1000 normal 'Should I rebase w-alpha onto main?' yes 'yes,no'
attention_row w-beta /wt/w-beta awaiting-input 1010 high 'should i rebase  w-beta   onto main?' yes 'YES,no'
qa=$(run add --kind question --worker w-alpha --origin w-alpha --closes 'the operator answers' --now 1000) || fail "add w-alpha question"
qb=$(run add --kind question --worker w-beta --origin w-beta --closes 'the operator answers' --now 1010) || fail "add w-beta question"

out=$(run settle --evidence "$ev" --now 1100 2>/dev/null) || fail "the merging pass exited non-zero"
# w-beta's high urgency ranks it first, so it is the survivor.
[ "$(state_of "$qb")" = open ] || fail "the better-ranked source did not survive the merge"
[ "$(state_of "$qa")" = closed ] || fail "the duplicate question was not merged away"
[ "$(rec "$qa" | cut -f 18)" = "merged into $qb" ] || fail "the merged-away item does not name its survivor: '$(rec "$qa" | cut -f 18)'"
[ "$(rec "$qb" | cut -f 3)" = high ] || fail "the merged item does not carry the highest urgency of its sources"
[ "$(rec "$qb" | cut -f 5)" = 1000 ] || fail "the merged item does not carry the oldest age of its sources: born $(rec "$qb" | cut -f 5)"
[ "$(rec "$qb" | cut -f 23)" = w-alpha ] || fail "the merged item does not name every source: '$(rec "$qb" | cut -f 23)'"
printf '%s\n' "$out" | grep -q "^merged${TAB}$qa${TAB}$qb${TAB}question$" || fail "the pass printed no merged line: '$out'"
grep -q "\"kind\":\"merged\".*\"item\":\"$qa\".*\"into\":\"$qb\"" "$surface/events.log" || fail "the merge was not logged"

# The hand-over names both sources.
marker tower-a 1200
run next --tower tower-a --evidence "$ev" --now 1201 >/dev/null 2>&1 || fail "the knock after the merge"
marker tower-a 1202
out=$(run next --tower tower-a --evidence "$ev" --now 1203 2>/dev/null) || fail "the hand-over after the merge"
[ "$(field "$out" 5)" = "w-beta,w-alpha" ] || fail "the delivered merged item does not name both sources: '$(field "$out" 5)'"
echo "ok: two workers asking the same thing merge into one item naming both sources, at the higher urgency and the older age"

# --- a worker command merges only on byte equality -------------------------------

reset_home command
attention_row w-c1 /wt/c1 awaiting-input 1000 normal 'run it?' yes 'yes,no' '' '' '' 'git push origin main'
attention_row w-c2 /wt/c2 awaiting-input 1000 normal 'run it?' yes 'yes,no' '' '' '' 'GIT push origin main'
attention_row w-c3 /wt/c3 awaiting-input 1000 normal 'run it?' yes 'yes,no' '' '' '' 'git  push origin main'
c1=$(run add --kind question --worker w-c1 --origin w-c1 --closes 'the operator answers' --now 1000) || fail "add c1"
c2=$(run add --kind question --worker w-c2 --origin w-c2 --closes 'the operator answers' --now 1000) || fail "add c2"
c3=$(run add --kind question --worker w-c3 --origin w-c3 --closes 'the operator answers' --now 1000) || fail "add c3"
run settle --evidence "$ev" --now 1100 >/dev/null 2>&1 || fail "the command pass exited non-zero"
for id in $c1 $c2 $c3; do
  [ "$(state_of "$id")" = open ] || fail "a command-bearing item merged on a case or spacing difference"
done

attention_row w-c4 /wt/c4 awaiting-input 1000 normal 'run it?' yes 'yes,no' '' '' '' 'git push origin main'
c4=$(run add --kind question --worker w-c4 --origin w-c4 --closes 'the operator answers' --now 1000) || fail "add c4"
run settle --evidence "$ev" --now 1200 >/dev/null 2>&1 || fail "the byte-equal command pass exited non-zero"
merged=0
[ "$(state_of "$c1")" = closed ] && merged=$((merged + 1))
[ "$(state_of "$c4")" = closed ] && merged=$((merged + 1))
[ "$merged" = 1 ] || fail "two byte-identical commands did not merge into exactly one survivor"
[ "$(state_of "$c2")" = open ] || fail "the case-different command was merged away"
[ "$(state_of "$c3")" = open ] || fail "the spacing-different command was merged away"
echo "ok: command-bearing items merge only on byte equality — case and spacing differences do not"

# --- pairing: one hand-over, both sources, a third waits --------------------------

reset_home pair
add_req() { # add_req <name> <origin> <subject> <urgency> <now> [<kind>]
  printf 'request %s\n' "$1" >"$content/$1"
  run add --kind "${6:-request}" --root "$content" --pointer "$1" --origin "$2" \
    --subject "$3" --urgency "$4" --closes 'the operator decides' --now "$5"
}
# The top item and the oldest on its subject go over together; the third
# waits. p2 leads on urgency and p3 is the oldest of the three.
p1=$(add_req p1 w-one pr:500 low 1020) || fail "add p1"
p2=$(add_req p2 w-two pr:500 high 1010) || fail "add p2"
p3=$(add_req p3 w-three pr:500 normal 1000) || fail "add p3"

marker tower-a 1100
run next --tower tower-a --evidence "$ev" --now 1101 >/dev/null 2>&1 || fail "the pairing knock"
marker tower-a 1102
out=$(run next --tower tower-a --evidence "$ev" --now 1103 2>/dev/null) || fail "the paired hand-over"
item=$(line_of "$out" item)
pair=$(line_of "$out" pair)
[ -n "$pair" ] || fail "a shared-subject pair was not handed over as one unit: '$out'"
[ "$(field "$item" 2)" = "$p2" ] || fail "the pair's item line is not the better-ranked source: '$item'"
[ "$(field "$pair" 2)" = "$p3" ] || fail "the pair line does not name the second source: '$pair'"
[ "$(field "$item" 4)" = high ] || fail "the pair does not carry the higher urgency of its sources"
[ "$(field "$item" 5)" = "w-two,w-three" ] || fail "the pair does not name both sources: '$(field "$item" 5)'"
[ "$(field "$item" 6)" = "$((1103 - 1000))" ] || fail "the pair does not carry the older age of its sources: '$(field "$item" 6)'"
[ "$(printf '%s\n' "$out" | grep -c "^item${TAB}" || true)" = 1 ] || fail "the pair was handed over as two items"

run ack "$p2" --tower tower-a --now 1104 >/dev/null 2>&1 || fail "ack the pair's item"
run ack "$p3" --tower tower-a --now 1105 >/dev/null 2>&1 || fail "ack the pair's partner"
marker tower-a 1106
out=$(run next --tower tower-a --evidence "$ev" --now 1107 2>/dev/null) || fail "the third on the subject"
[ "$(field "$(line_of "$out" item)" 2)" = "$p1" ] || fail "the third item on the subject did not wait its turn: '$out'"
[ -z "$(line_of "$out" pair)" ] || fail "a third item on one subject was paired"
run ack "$p1" --tower tower-a --now 1108 >/dev/null 2>&1 || fail "ack the third"
echo "ok: a shared-subject pair is handed over as one item naming both sources, and a third on that subject waits"

# --- two kinds on one subject, and two subjects, do not pair ----------------------

a1=$(add_req a1 w-four pr:600 normal 1200 approval) || fail "add a1"
q1=$(add_req q1 w-five pr:600 normal 1210) || fail "add q1"
marker tower-a 1300
out=$(run next --tower tower-a --evidence "$ev" --now 1301 2>/dev/null) || fail "the mixed-kind hand-over"
[ "$(field "$(line_of "$out" item)" 2)" = "$a1" ] || fail "the approval did not rank ahead of the request"
[ -z "$(line_of "$out" pair)" ] || fail "two items of different kinds on one subject were paired"
run ack "$a1" --tower tower-a --now 1302 >/dev/null 2>&1 || fail "ack a1"

add_req d1 w-six pr:701 normal 1400 >/dev/null || fail "add d1"
add_req d2 w-seven pr:702 normal 1410 >/dev/null || fail "add d2"
marker tower-a 1500
out=$(run next --tower tower-a --evidence "$ev" --now 1501 2>/dev/null) || fail "the distinct-subject hand-over"
[ "$(field "$(line_of "$out" item)" 2)" = "$q1" ] || fail "the oldest open request was not handed over"
[ -z "$(line_of "$out" pair)" ] || fail "two items with different subjects were paired"
marker tower-a 1502
out=$(run next --tower tower-a --evidence "$ev" --now 1503 2>/dev/null) || fail "the hand-over after a leased candidate"
[ -z "$(line_of "$out" pair)" ] || fail "an item paired with a leased or already-delivered candidate"
echo "ok: different kinds on one subject, different subjects, and a leased candidate do not pair"

# --- the partner is the oldest candidate, not the best-ranked one -----------------

# t-young outranks t-old on urgency but is younger; the partner rule is age,
# so t-old goes over with the top item and t-young waits.
t_top=$(add_req t-top w-top pr:800 high 2000) || fail "add t-top"
t_young=$(add_req t-young w-young pr:800 high 2100) || fail "add t-young"
t_old=$(add_req t-old w-old pr:800 low 1900) || fail "add t-old"
marker tower-a 2200
out=$(run next --tower tower-a --evidence "$ev" --now 2201 2>/dev/null) || fail "the age tie-break hand-over"
item=$(line_of "$out" item)
pair=$(line_of "$out" pair)
[ "$(field "$item" 2)" = "$t_top" ] || fail "the top item changed: '$item'"
[ "$(field "$pair" 2)" = "$t_old" ] || fail "the partner is not the oldest candidate on the subject: '$pair'"
[ "$(field "$item" 6)" = "$((2201 - 1900))" ] || fail "the pair does not carry the oldest age: '$(field "$item" 6)'"
run ack "$t_top" --tower tower-a --now 2202 >/dev/null 2>&1 || fail "ack t-top"
run ack "$t_old" --tower tower-a --now 2203 >/dev/null 2>&1 || fail "ack t-old"
marker tower-a 2204
out=$(run next --tower tower-a --evidence "$ev" --now 2205 2>/dev/null) || fail "the younger candidate's turn"
[ "$(field "$(line_of "$out" item)" 2)" = "$t_young" ] || fail "the younger candidate did not follow: '$out'"
run ack "$t_young" --tower tower-a --now 2206 >/dev/null 2>&1 || fail "ack t-young"
echo "ok: the partner on a subject is the oldest candidate, so neither inherited field goes stale and nothing starves"

# --- merging and pairing are one keyed pass over a large fixture ------------------

reset_home bulk
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
mkdir -p "$surface"
chmod 0700 "$surface"
i=0
while [ "$i" -lt 30 ]; do
  attention_row "w-l$i" "/wt/l$i" awaiting-input 2000 normal "Deploy batch $i?" yes 'yes,no'
  attention_row "w-r$i" "/wt/r$i" awaiting-input 2000 normal "deploy  batch $i?" yes 'YES,no'
  printf 'i%08x\tquestion\tnormal\tw-l%s\t2000\tattention\tw-l%s\t-\t-\t-\tthe operator answers\topen\t0\t0\t0\t0\t0\t-\t-\t0\tworker:w-l%s\t0\t-\n' \
    "$((i * 2))" "$i" "$i" "$i" >>"$store"
  printf 'i%08x\tquestion\tnormal\tw-r%s\t2000\tattention\tw-r%s\t-\t-\t-\tthe operator answers\topen\t0\t0\t0\t0\t0\t-\t-\t0\tworker:w-r%s\t0\t-\n' \
    "$((i * 2 + 1))" "$i" "$i" "$i" >>"$store"
  i=$((i + 1))
done
chmod 0600 "$store"
out=$(run settle --evidence "$ev" --now 2100 2>/dev/null) || fail "the bulk pass exited non-zero"
[ "$(printf '%s\n' "$out" | grep -c "^merged${TAB}" || true)" = 30 ] \
  || fail "the bulk pass merged $(printf '%s\n' "$out" | grep -c "^merged${TAB}" || true) of 30 pairs — merging is not one keyed pass"
held=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "held" { print $2 }')
awk -v h="$held" 'BEGIN { exit (h < 2) ? 0 : 1 }' || fail "the bulk merge held the fleet lock ${held}s, past the 2s bound"
echo "ok: sixty candidates merge into thirty in one keyed pass, inside the lock-hold bound (${held}s)"

echo "PASS: tower-queue merging and pairing"
