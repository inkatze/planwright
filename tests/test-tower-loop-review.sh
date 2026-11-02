#!/bin/bash
# A scripted tower session over a fixture fleet: batches, the reviewable kinds
# and the wake (tower-comms Task 14; D-20, D-21, D-23, D-24 · REQ-A1.10,
# REQ-B1.8, REQ-C1.12, REQ-F1.9). The verbs are unit-tested in their own files;
# this exercises what scripts/tower-loop-comms.sh hands the tower and the
# replies it names for the tower to record.
#
# Contract under test:
#   step --checkout <dir> --tower <id> --evidence <file> [--now <epoch>]
#       A subject batch arrives as one hand-over, each member's content fenced.
#       A reviewable item carries a `review` record (what it settled on, what
#       undoes it) and two `reply` records naming the verb that records a
#       review (`ack`) and an undo (`revoke`). A step run when a wake arrives
#       hands over what the wake announced without waiting for the loop's tick.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TLC="$here/../scripts/tower-loop-comms.sh"
TQ="$here/../scripts/tower-queue.sh"
TLL="$here/../scripts/tower-loop-log.sh"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$TLC" ] || fail "scripts/tower-loop-comms.sh missing or not executable"
[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$TLL" ] || fail "scripts/tower-loop-log.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
errf="$tmp/stderr"

home="$tmp/fleet-home"
mkdir -p "$home"
chmod 0700 "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"

surface="$home/tower-comms"
log_file="$surface/events.log"
content="$tmp/content"
mkdir -p "$content"
ev="$tmp/evidence"
: >"$ev"
chmod 0600 "$ev"

attn_dir="$home/attention"
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
attn_store="$attn_dir/state"
: >"$attn_store"
chmod 0600 "$attn_store"

TAB=$(printf '\t')
A=tower-a

env_run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$here/../config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    PLANWRIGHT_ACTION_LEDGER="" \
    PLANWRIGHT_ATTENTION_SURFACE_PROVIDED="" \
    PLANWRIGHT_TOWER_ID="" \
    PLANWRIGHT_TOWER_SESSION_ID="" \
    PLANWRIGHT_TOWER_PID="" \
    "$@"
}

q() {
  : >"$errf"
  env_run /bin/sh "$TQ" "$@" 2>"$errf"
}

step() { # step <now> — one loop step by tower A
  : >"$errf"
  env_run /bin/sh "$TLC" step --checkout "$tmp" --tower "$A" --evidence "$ev" --now "$1" 2>"$errf"
}

reply_at() { # reply_at <epoch> — what the prompt-submit hook writes for tower A
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$1" >"$surface/attention/$A"
  chmod 0600 "$surface/attention/$A"
}

row() { # row <worker> <epoch> <question> <options> — a worker blocks
  printf '%s\tspec\tawaiting-input\t%s\tnormal\t%s\t-\t%s\t-\t-\n' "$1" "$2" "$3" "$4" >>"$attn_store"
}

count_tag() { printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t { n++ } END { print n + 0 }'; }
lines_of() { printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t'; }
log_count() { grep -c "\"kind\":\"$1\"" "$log_file" || true; }

# --- a subject batch is one hand-over (REQ-C1.12) -------------------------------

# The store exists before any row does: a rebuild over an absent store would
# register the row first, without the subject the add below gives it.
printf 'seed\n' >"$content/seed"
seed=$(q add --kind request --root "$content" --pointer seed --origin operator --closes 'the operator decides' --now 900) \
  || fail "seed the store"
q settle "$seed" --reason 'the seed is not under test' --now 901 >/dev/null || fail "settle the seed"

row w-b1 1000 'keep the flaky test on PR 12?' 'keep|drop'
b1=$(q add --kind question --worker w-b1 --origin w-b1 --closes 'the operator answers' --subject pr:12 --now 1000) \
  || fail "add the batch question"
printf 'Approve the release notes for PR 12.\n' >"$content/notes"
b2=$(q add --kind approval --root "$content" --pointer notes --origin operator --closes 'the operator approves' \
  --subject pr:12 --now 1001) || fail "add the batch approval"
printf 'Rerun the PR 12 benchmarks.\n' >"$content/bench"
b3=$(q add --kind request --root "$content" --pointer bench --origin operator --closes 'the operator decides' \
  --subject pr:12 --now 1002) || fail "add the batch request"

out=$(step 1010) || fail "the knock step: exit"
[ "$(count_tag "$out" knock)" = 1 ] || fail "no knock before the batch: '$out'"
[ "$(lines_of "$out" knock | cut -f 5)" = 3 ] || fail "the knock did not name a hand-over of three: '$out'"
reply_at 1020
out=$(step 1030) || fail "the batch step: exit"
[ "$(count_tag "$out" batch)" = 1 ] || fail "the batch did not arrive as one hand-over: '$out'"
[ "$(lines_of "$out" batch | cut -f 2)" = 3 ] || fail "the batch line does not count three: '$out'"
[ "$(count_tag "$out" item)" = 3 ] || fail "the batch did not carry its three items: '$out'"
for id in "$b1" "$b2" "$b3"; do
  printf '%s\n' "$out" | grep -q "^content${TAB}$id${TAB}[a-z]*${TAB}read${TAB}" || fail "batch member $id had no content: '$out'"
done
[ "$(count_tag "$out" review)" = 0 ] || fail "a batch of plain kinds carried a review record: '$out'"
[ "$(grep '"kind":"delivered"' "$log_file" | grep -c '"batch":')" = 1 ] || fail "the batch was not logged as one delivered line"
out=$(step 1040) || fail "the step after the batch: exit"
[ "$(count_tag "$out" item)" = 0 ] && [ "$(count_tag "$out" knock)" = 0 ] \
  || fail "a second hand-over followed the batch with no reply: '$out'"
for id in "$b1" "$b2" "$b3"; do
  q ack "$id" --tower "$A" --now 1050 >/dev/null || fail "ack batch member $id"
done
echo "ok: a subject batch arrives as one hand-over with each member's content, and nothing follows it unanswered"

# --- a settled-by-default item waits for review on the operator's return -------

row w-p 2000 'keep the retry loop?' 'keep|drop'
p=$(q add --kind question --worker w-p --origin w-p --closes 'the operator answers' \
  --options 'keep|drop' --end keep --gate none --window 60s --now 2000) || fail "add the picklist question"
out=$(step 2010) || fail "the knock for the picklist question: exit"
[ "$(count_tag "$out" knock)" = 1 ] || fail "no knock for the picklist question: '$out'"
# The operator does not answer; the window ends while they are away.
out=$(step 2100) || fail "the step past the window end: exit"
printf '%s\n' "$out" | grep -q "^window${TAB}$p${TAB}default${TAB}keep${TAB}" || fail "the window did not end on its default: '$out'"
[ "$(count_tag "$out" item)" = 0 ] || fail "a review was handed over while the operator was away: '$out'"
# They come back and answer the knock that is still outstanding: that reply
# releases the review.
reply_at 2300
out=$(step 2310) || fail "the step on the operator's return: exit"
[ "$(lines_of "$out" item | cut -f 2)" = "$p" ] || fail "the settled-by-default item was not handed over: '$out'"
[ "$(lines_of "$out" item | cut -f 3)" = settled-by-default ] || fail "the item was not handed over as settled-by-default: '$out'"
printf '%s\n' "$out" | grep -q "^content${TAB}$p${TAB}ledger${TAB}read${TAB}no$" || fail "the review content did not read from the ledger: '$out'"
printf '%s\n' "$out" | grep -q 'ended on its default: keep' || fail "the review content does not say which option was applied: '$out'"
rv=$(lines_of "$out" review)
[ "$(printf '%s\n' "$rv" | cut -f 2,3)" = "$p${TAB}settled-by-default" ] || fail "no review record for $p: '$out'"
printf '%s\n' "$rv" | cut -f 4 | grep -q 'default: keep' || fail "the review record does not say what was applied: '$rv'"
[ "$(printf '%s\n' "$rv" | cut -f 5)" = reopen ] || fail "the review record does not carry the reversal: '$rv'"
[ "$(lines_of "$out" reply | cut -f 2,3,4)" = "$p${TAB}review${TAB}ack
$p${TAB}revoke${TAB}revoke" ] || fail "the reply records do not name ack and revoke: '$out'"
echo "ok: a default applied while away is handed over for review on the return, with the replies that close it"

# --- the operator's undo is recorded through the verb the reply record names ---

verb=$(lines_of "$out" reply | awk -F "$TAB" '$3 == "revoke" { print $4 }')
rout=$(q "$verb" "$p" --tower "$A" --now 2320) || fail "the revoke reply: exit"
[ "$(printf '%s\n' "$rout" | cut -f 1,2)" = "reopened${TAB}$p" ] || fail "the revoke did not reopen the question: '$rout'"
grep '"kind":"revoked"' "$log_file" | grep -q "\"item\":\"$p\"" || fail "the revoke reply did not reach the event log"
[ "$(q show "$p" | awk -F "$TAB" '$1 == "item" { print $3 }')" = question ] || fail "the revoked item is not back to its question"
q settle "$p" --reason 'the fixture answers the reopened question elsewhere' --now 2330 >/dev/null \
  || fail "settle the reopened question"
echo "ok: an undo reply is recorded through revoke and reopens the question"

# --- a wake runs the hand-over without waiting for the tick (REQ-F1.9) ---------

reply_at 3000
env_run /bin/sh "$TLL" tick --tower "$A" --now 3000 >/dev/null 2>"$errf" || fail "the loop's tick: exit"
out=$(step 3000) || fail "the quiet step: exit"
[ "$(count_tag "$out" item)" = 0 ] && [ "$(count_tag "$out" knock)" = 0 ] || fail "the quiet step handed something over: '$out'"
ticks=$(log_count tick)
# A worker blocks and mission control wakes the tower. The tower runs the step
# on the wake, five seconds later, with no tick in between.
row w-wake 3002 'which branch should the hotfix target?' 'main|release'
wq=$(q add --kind question --worker w-wake --origin w-wake --closes 'the operator answers' --now 3002) \
  || fail "add the question the wake announces"
out=$(step 3005) || fail "the step on the wake: exit"
[ "$(lines_of "$out" item | cut -f 2)" = "$wq" ] || fail "the step on the wake did not hand over what it announced: '$out'"
[ "$(log_count tick)" = "$ticks" ] || fail "a tick was written between the wake and its hand-over"
grep '"kind":"delivered"' "$log_file" | grep -q "\"item\":\"$wq\"" || fail "the wake's hand-over was not logged against its item"
echo "ok: a step run on a wake hands over the new item with no tick in between"

echo "PASS: tower-loop review"
