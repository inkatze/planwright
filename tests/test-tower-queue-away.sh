#!/bin/bash
# Tests for scripts/tower-queue.sh away detection, the away push and the
# `knock` verb — REQ-C1.2, REQ-C1.6, REQ-C1.7, REQ-F1.1, REQ-F1.2, REQ-F1.3,
# REQ-F1.6 (D-6, D-7, D-9, D-19).
#
# Contract under test:
#   knock [--now <epoch>]
#       The one-line knock rendered from the store, lock-free: `knock`, the
#       top item's kind, its urgency, and how many items are waiting. The
#       same text `next` returns; `next` keeps the attention state and the
#       lease, this verb keeps none.
#   next [--tower <id>]
#       While the calling tower is away (its last knock unanswered past
#       tower_quiet_interval) and a blocking item is open, one away push per
#       item, deduped across towers under the fleet lock, routed through
#       fleet-attention.sh notify, its outcome logged as a `pushed` event.
#       After the first, only on worsening: a new blocking item, or an open
#       one passing tower_reknock_age. Never on a schedule. News never
#       pushes, whatever its urgency.
#   shelve <id> [--for <span>]
#       Returns at tower_shelve_return, or at the overridden span.
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
core_cfg="$tmp/core-defaults.yml"
local_cfg="$tmp/local.yml"
repo="$tmp/repo"
mkdir -p "$repo/.claude"
tracked_cfg="$repo/.claude/planwright.yml"

surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
push_dir="$home/attention/push"
content="$tmp/content"
mkdir -p "$content"
TAB=$(printf '\t')

# The core defaults the resolver falls back to, so the test never depends on
# the repo's own config/defaults.yml for the knobs it pins here.
printf 'notification_channel: none\ntower_hook_lock_wait: 2s\ntower_quiet_interval: 10m\ntower_lease_interval: 15m\ntower_catchup_limit: 20\ntower_shelve_return: 1h\ntower_reknock_age: 30m\ntower_tick_gap_max: 10m\ntower_log_rotate_age: 30d\ntower_report_window: 7d\n' >"$core_cfg"

channel() { printf 'notification_channel: %s\n' "$1" >"$tracked_cfg"; }
channel none

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" \
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
pushed_at() { rec "$1" | cut -f 25; }
push_count() { rec "$1" | cut -f 26; }
pushes() { grep -c '"kind":"pushed"' "$log_file" || true; }
markers() { # how many pending-push markers exist
  m_n=0
  for m_f in "$push_dir"/*; do
    [ -e "$m_f" ] || continue
    m_n=$((m_n + 1))
  done
  printf '%s\n' "$m_n"
}
pushes_for() { grep -c "\"kind\":\"pushed\".*\"item\":\"$1\"" "$log_file" || true; }

# Each question asks something of its own, so two blocked workers are two
# items: identical text and option set is what the merge rule collapses (and
# it removes the origin handle before comparing, so naming the worker would
# not be enough), and these fixtures are about the push, not about merging.
add_q() { # add_q <worker> <urgency> <now>
  printf '%s\tspec\tawaiting-input\t%s\t%s\tquestion raised at %s\t-\tA|B\t-\t-\n' \
    "$1" "$3" "$2" "$3" >>"$attn_store"
  run add --kind question --worker "$1" --origin "$1" --closes 'the operator answers' --now "$3"
}

add_news() { # add_news <worker> <urgency> <now>
  printf '%s\tspec\tidle\t%s\t%s\tthe run finished\t-\t-\t-\t-\n' "$1" "$3" "$2" >>"$attn_store"
  run add --kind news --worker "$1" --origin "$1" --urgency "$2" --closes 'the operator has seen it' --now "$3"
}

attn_dir="$home/attention"
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
attn_store="$attn_dir/state"
: >"$attn_store"
chmod 0600 "$attn_store"

# Short enough to test; the lease is floored at the quiet interval.
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 1000s\n' >"$local_cfg"
A=tower-a
B=tower-b

# --- the knock verb renders the line, keeping no state (REQ-C1.2) -------------

out=$(run knock --now 900) || fail "knock on an empty queue: exit"
[ -z "$out" ] || fail "knock printed a line with nothing waiting: '$out'"

q1=$(add_q w1 high 1000)
out=$(run knock --now 1010) || fail "knock: exit"
[ "$(field "$out" 1)" = knock ] || fail "knock did not render a knock line: '$out'"
[ "$(field "$out" 2)" = question ] || fail "knock names the wrong kind: '$out'"
[ "$(field "$out" 3)" = high ] || fail "knock names the wrong urgency: '$out'"
[ "$(field "$out" 4)" = 1 ] || fail "knock's waiting count is wrong: '$out'"
case "$out" in *w1*) fail "the knock leaked the item's content pointer" ;; esac
[ -f "$store" ] || fail "the fixture did not create a store"
[ "$(rec "$q1" | cut -f 13)" = 0 ] || fail "knock stamped the record (it keeps no state)"
[ "$(rec "$q1" | cut -f 19)" = - ] || fail "knock took a lease (next keeps the lease)"
echo "ok: knock renders the line from the store and keeps neither state nor lease"

nl=$(run next --tower $A --now 1010)
[ "$nl" = "$out" ] || fail "next's knock line differs from the knock verb's: '$nl' vs '$out'"
echo "ok: next returns the same line the knock verb renders"

# --- away needs a knock that went unanswered past the quiet interval ----------
# (REQ-F1.1). Inside the interval the operator is simply not back yet.

out=$(run next --tower $A --now 1050 2>/dev/null) || fail "next inside the quiet interval: exit"
[ -z "$out" ] || fail "next spoke while a knock was outstanding: '$out'"
[ "$(pushes)" = 0 ] || fail "a push fired inside the quiet interval (not away yet)"
[ "$(pushed_at "$q1")" = 0 ] || fail "the item was stamped pushed inside the quiet interval"
echo "ok: an unanswered knock inside the quiet interval is not away and does not push"

# --- the push fires on the transition into away with a blocking item open -----
# (REQ-F1.2), routed through the notify seam, its outcome logged.

out=$(run next --tower $A --now 1200 2>/dev/null) || fail "next past the quiet interval: exit"
[ -z "$out" ] || fail "the away pass printed a delivery line: '$out'"
[ "$(pushes_for "$q1")" = 1 ] || fail "no pushed event on the transition into away"
[ "$(pushed_at "$q1")" = 1200 ] || fail "the away push was not stamped on the record: '$(pushed_at "$q1")'"
grep -q '"kind":"pushed".*"channel":"none"' "$log_file" || fail "the pushed event does not name the channel"
grep -q '"kind":"pushed".*"outcome":"' "$log_file" || fail "the pushed event does not record an outcome"
echo "ok: the away push fires on the transition into away and logs its outcome"

# --- never on a fixed schedule (REQ-F1.3) ------------------------------------

for t in 1300 1900; do
  out=$(run next --tower $A --now $t 2>/dev/null) || fail "next after the push: exit"
  [ -z "$out" ] || fail "the knock repeated on a schedule at $t: '$out'"
done
[ "$(pushes_for "$q1")" = 1 ] || fail "the away push repeated on a schedule ($(pushes_for "$q1") pushes)"
[ "$(push_count "$q1")" = 1 ] || fail "the push count is not 1: '$(push_count "$q1")'"
echo "ok: neither the knock nor the away push repeats on a schedule"

# --- a `none` channel queues without error and without a transport -----------

[ ! -d "$push_dir" ] || fail "the none channel wrote a pending-push marker"
[ "$(rec "$q1" | cut -f 12)" = open ] || fail "the none channel closed the item instead of leaving it queued"
echo "ok: a none channel queues the item and pushes nothing"

# --- worsening: a second blocked worker pushes on its own (REQ-F1.3) ---------

q2=$(add_q w2 normal 1950)
run next --tower $A --now 1960 >/dev/null 2>&1 || fail "next with a second blocking item: exit"
[ "$(pushes_for "$q2")" = 1 ] || fail "a new blocked worker did not push"
[ "$(pushes_for "$q1")" = 1 ] || fail "the new blocked worker re-pushed the first item too"
echo "ok: more blocked workers is a worsening that pushes, once, for the new item"

# --- worsening: an open blocked item passing tower_reknock_age pushes once ----

# q1 was born at 1000 and tower_reknock_age is 1000s, so it crosses at 2000;
# the pass at 1960 above is the last one before the crossing and left it at
# one push. The crossing is read once, so the first pass past it re-pushes and
# no later one does.
run next --tower $A --now 2200 >/dev/null 2>&1 || fail "next past the re-knock age: exit"
[ "$(pushes_for "$q1")" = 2 ] || fail "the item passing tower_reknock_age did not re-push ($(pushes_for "$q1"))"
run next --tower $A --now 2400 >/dev/null 2>&1 || fail "next well past the re-knock age: exit"
[ "$(pushes_for "$q1")" = 2 ] || fail "the re-knock age push repeated on a schedule ($(pushes_for "$q1"))"
echo "ok: a blocked item passing tower_reknock_age re-pushes exactly once"

# --- the worsening re-knock is held while an evidence source is unavailable ---
# (REQ-F1.3, REQ-B1.2)

q3=$(add_q w3 normal 2400)
ev_hold="$tmp/evidence-hold"
printf 'unavailable\tgithub\n' >"$ev_hold"
chmod 0600 "$ev_hold"
run next --tower $A --evidence "$ev_hold" --now 3500 >/dev/null 2>&1 || fail "next with an unavailable source: exit"
[ "$(pushes_for "$q3")" = 1 ] || fail "the hold suppressed a first push, which it must not"
[ "$(pushes_for "$q2")" = 1 ] || fail "the worsening re-push was not held while a source was unavailable"
[ -f "$surface/reknock.hold" ] || fail "the pass that found a source unavailable did not publish the hold"
run next --tower $A --now 3600 >/dev/null 2>&1 || fail "next after the source answers: exit"
[ "$(pushes_for "$q2")" = 2 ] || fail "the worsening re-push did not resume once the source answered"
[ ! -e "$surface/reknock.hold" ] || fail "the pass that found every source answering left the hold on disk"
echo "ok: a worsening re-push is held while an evidence source is unavailable, and resumes after"

# --- one item open in two towers pushes once (REQ-F1.2) ----------------------

: >"$log_file"
q4=$(add_q w4 high 4000)
run next --tower $A --now 4010 >/dev/null 2>&1 || fail "tower A knocks: exit"
run next --tower $B --now 4020 >/dev/null 2>&1 || fail "tower B knocks: exit"
run next --tower $A --now 4200 >/dev/null 2>&1 || fail "tower A goes away: exit"
run next --tower $B --now 4210 >/dev/null 2>&1 || fail "tower B goes away: exit"
[ "$(pushes_for "$q4")" = 1 ] || fail "one item open in two towers pushed $(pushes_for "$q4") times"
echo "ok: one item open in two towers pushes once"

# --- urgent news knocks but never pushes while away (REQ-C1.7, D-7) ----------

: >"$log_file"
run settle "$q1" --reason 'the worker landed it' --now 5000 >/dev/null 2>&1 || fail "settling q1"
run settle "$q2" --reason 'the worker landed it' --now 5000 >/dev/null 2>&1 || fail "settling q2"
run settle "$q3" --reason 'the worker landed it' --now 5000 >/dev/null 2>&1 || fail "settling q3"
run settle "$q4" --reason 'the worker landed it' --now 5000 >/dev/null 2>&1 || fail "settling q4"
n1=$(add_news w9 high 5100)
out=$(run next --tower $B --now 5110 2>/dev/null) || fail "next with urgent news: exit"
[ "$(field "$out" 1)" = knock ] || fail "urgent news did not knock in the conversation: '$out'"
[ "$(field "$out" 2)" = news ] || fail "the knock does not name the news item: '$out'"
run next --tower $B --now 5400 >/dev/null 2>&1 || fail "next with urgent news past the quiet interval: exit"
[ "$(pushes_for "$n1")" = 0 ] || fail "urgent news pushed while the operator was away"
[ "$(pushed_at "$n1")" = 0 ] || fail "urgent news was stamped as pushed"
echo "ok: urgent news knocks in the conversation and never pushes while away"

# --- the operator's return ends the episode; leaving again pushes again -------
# (REQ-F1.2: the push fires on THE TRANSITION into away, and a second
# departure is a second transition.)

: >"$log_file"
run settle "$n1" --reason 'the operator has read it' --now 5500 >/dev/null 2>&1 || fail "settling n1"
e1=$(add_q we high 5600)
run next --tower $A --now 5610 >/dev/null 2>&1 || fail "episode knock: exit"
run next --tower $A --now 5800 >/dev/null 2>&1 || fail "first departure: exit"
[ "$(pushes_for "$e1")" = 1 ] || fail "the first departure did not push"
[ "$(push_count "$e1")" = 1 ] || fail "the push count after one departure is '$(push_count "$e1")'"

marker $A 5810
run next --tower $A --now 5820 >/dev/null 2>&1 || fail "the return pass: exit"
[ "$(push_count "$e1")" = 0 ] || fail "the operator's return did not end the episode: count '$(push_count "$e1")'"
[ "$(pushed_at "$e1")" = 0 ] || fail "the operator's return left a push stamp behind"

run next --tower $A --now 5830 >/dev/null 2>&1 || fail "the second knock: exit"
run next --tower $A --now 6100 >/dev/null 2>&1 || fail "second departure: exit"
[ "$(pushes_for "$e1")" = 2 ] || fail "the second departure did not push ($(pushes_for "$e1"))"
echo "ok: the operator's return ends the episode and a second departure pushes again"

# --- the two-push bound survives a change to tower_reknock_age ----------------
# A bound expressed as a comparison against a threshold recomputed from the
# knob re-arms every time the knob is raised, so this drives the knob in both
# directions across an item that has already had both of its pushes.

: >"$log_file"
run settle "$e1" --reason 'the worker landed it' --now 6200 >/dev/null 2>&1 || fail "settling e1"
k1=$(add_q wk high 6300)
run next --tower $A --now 6310 >/dev/null 2>&1 || fail "knob knock: exit"
run next --tower $A --now 6600 >/dev/null 2>&1 || fail "knob first departure: exit"
[ "$(pushes_for "$k1")" = 1 ] || fail "the knob fixture did not get its first push"
run next --tower $A --now 7400 >/dev/null 2>&1 || fail "knob crossing pass: exit"
[ "$(pushes_for "$k1")" = 2 ] || fail "the knob fixture did not cross tower_reknock_age ($(pushes_for "$k1"))"

printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 5000s\n' >"$local_cfg"
run next --tower $A --now 12000 >/dev/null 2>&1 || fail "raised-knob pass: exit"
[ "$(pushes_for "$k1")" = 2 ] || fail "raising tower_reknock_age re-armed a spent push ($(pushes_for "$k1"))"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 1000s\n' >"$local_cfg"
echo "ok: raising tower_reknock_age does not re-arm a push the episode already spent"

# --- lowering it brings the crossing forward ---------------------------------
# The complement of the case above, pinned rather than caught: with the
# crossing still ahead of the first push, a lowered knob makes the worsening
# push land sooner. (An item whose first push already happened after the
# LOWERED crossing has had nothing worsen, so it stays at one push for the
# episode; the operator's return is what re-arms it.)

: >"$log_file"
run settle "$k1" --reason 'the worker landed it' --now 12100 >/dev/null 2>&1 || fail "settling k1"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 4000s\n' >"$local_cfg"
k2=$(add_q wl high 12200)
run next --tower $A --now 12210 >/dev/null 2>&1 || fail "lowered-knob knock: exit"
run next --tower $A --now 12400 >/dev/null 2>&1 || fail "lowered-knob first departure: exit"
[ "$(pushes_for "$k2")" = 1 ] || fail "the lowered-knob fixture did not get its first push"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 300s\n' >"$local_cfg"
run next --tower $A --now 12600 >/dev/null 2>&1 || fail "lowered-knob crossing pass: exit"
[ "$(pushes_for "$k2")" = 2 ] || fail "lowering tower_reknock_age deleted the worsening push ($(pushes_for "$k2"))"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 1000s\n' >"$local_cfg"
echo "ok: lowering tower_reknock_age brings the worsening push forward rather than deleting it"

# --- knock and counts skip what next would not hand over ---------------------
# An item whose attention row has moved on is one `next` will never deliver.
# Naming it in the knock, or counting it on the status line, is the same lie
# told on two surfaces.

: >"$log_file"
run settle "$k2" --reason 'the worker landed it' --now 12700 >/dev/null 2>&1 || fail "settling k2"
add_q ws high 12800 >/dev/null
[ "$(run knock --now 12810 | cut -f 4)" = 1 ] || fail "the fixture item is not in the knock"
[ "$(run counts --now 12810 | awk -F '\t' '$1 == "question" { print $2 }')" = 1 ] \
  || fail "the fixture item is not in the counts"
printf 'ws\tspec\tworking\t12820\thigh\tquestion raised at 12800\t-\tA|B\t-\t-\n' >>"$attn_store"
[ -z "$(run knock --now 12830)" ] || fail "knock named an item whose row moved on: '$(run knock --now 12830)'"
[ "$(run counts --now 12830 | awk -F '\t' '$1 == "question" { print $2 }')" = 0 ] \
  || fail "counts counted an item whose row moved on"
[ -z "$(run next --tower $B --now 12830 2>/dev/null)" ] || fail "next handed over an item whose row moved on"
echo "ok: knock and counts skip what next would not hand over"

# --- an absent attention store is not proof every row is gone ----------------
# Reading it that way would silence the knock the moment the file went missing.

mv "$attn_store" "$tmp/attn.aside"
[ "$(run knock --now 12900 | cut -f 4)" = 1 ] || fail "an absent attention store silenced the knock"
[ "$(run counts --now 12900 | awk -F '\t' '$1 == "question" { print $2 }')" = 1 ] \
  || fail "an absent attention store zeroed the counts"
mv "$tmp/attn.aside" "$attn_store"
echo "ok: an absent attention store is a source that cannot be reached, not an empty queue"

# --- a present conversation is not an away operator (REQ-F1.1, REQ-F1.2) -----
# The budget lives on the item and the states on the conversations. With the
# operator answering in A while B's knock sits unanswered, A's pass ends the
# episode and B's pass would start it again, on every alternation: a phone
# push per poll for as long as the operator keeps working in A. The push is
# for an operator who is gone, and an operator replying anywhere is not.

: >"$log_file"
ws_id=$(awk -F '\t' '$12 == "open" { print $1 }' "$store")
run settle "$ws_id" --reason 'the worker landed it' --now 13000 >/dev/null 2>&1 || fail "settling ws"
marker $A 13090 # the operator is at the keyboard in A before the item appears
p1=$(add_q wp high 13100)
run next --tower $A --now 13110 >/dev/null 2>&1 || fail "storm fixture: A knocks"
run next --tower $B --now 13120 >/dev/null 2>&1 || fail "storm fixture: B knocks"
t=13300
n=0
while [ "$n" -lt 5 ]; do
  marker $A "$t"
  run next --tower $A --now $((t + 1)) >/dev/null 2>&1 || fail "storm fixture: A's pass at $t"
  run next --tower $B --now $((t + 2)) >/dev/null 2>&1 || fail "storm fixture: B's pass at $t"
  t=$((t + 10))
  n=$((n + 1))
done
[ "$(pushes_for "$p1")" = 0 ] \
  || fail "an operator replying in one conversation was pushed $(pushes_for "$p1") times by another"
# The operator leaves A as well: no conversation is present, and B's pass is
# the transition into away. A's own pass after it is the cross-tower dedupe.
run next --tower $B --now $((t + 200)) >/dev/null 2>&1 || fail "storm fixture: B's away pass"
[ "$(pushes_for "$p1")" = 1 ] || fail "leaving the last present conversation did not push ($(pushes_for "$p1"))"
run next --tower $A --now $((t + 210)) >/dev/null 2>&1 || fail "storm fixture: A's away pass"
[ "$(pushes_for "$p1")" = 1 ] || fail "the second away conversation re-pushed ($(pushes_for "$p1"))"
echo "ok: a conversation the operator is answering in holds every other conversation's push"

# --- the hold reads this pass's evidence, not the previous pass's file -------
# (REQ-F1.3, REQ-B1.2) `reknock.hold` is what the settling pass WRITES after
# it runs, so a `next` that runs that pass itself has fresher knowledge than
# the file: the pass that first finds a source unavailable must hold on that
# finding, and the pass that finds it answering again must not stay held on
# a file written before it answered.

: >"$log_file"
run settle "$p1" --reason 'the worker landed it' --now 13900 >/dev/null 2>&1 || fail "settling p1"
rm -f "$surface/reknock.hold"
h1=$(add_q wh high 14000)
run next --tower $A --now 14010 >/dev/null 2>&1 || fail "hold fixture: A knocks"
run next --tower $A --now 14200 >/dev/null 2>&1 || fail "hold fixture: A goes away"
[ "$(pushes_for "$h1")" = 1 ] || fail "the hold fixture did not get its first push ($(pushes_for "$h1"))"
[ ! -e "$surface/reknock.hold" ] || fail "the hold fixture starts with a hold on disk"
ev="$tmp/evidence"
printf 'unavailable\tgithub\n' >"$ev"
chmod 0600 "$ev"
run next --tower $A --evidence "$ev" --now 15100 >/dev/null 2>&1 || fail "hold fixture: the pass that finds the source unavailable"
[ "$(pushes_for "$h1")" = 1 ] || fail "the pass that first found a source unavailable pushed on the stale reading ($(pushes_for "$h1"))"
[ -f "$surface/reknock.hold" ] || fail "the pass that found a source unavailable did not write the hold"
: >"$ev"
run next --tower $A --evidence "$ev" --now 15200 >/dev/null 2>&1 || fail "hold fixture: the pass that finds the source answering"
[ "$(pushes_for "$h1")" = 2 ] || fail "the pass that found the source answering again stayed held on the previous pass's file ($(pushes_for "$h1"))"
echo "ok: the worsening hold follows the evidence of the pass that decides, not the file of the pass before"

# --- the lock-free reads verify the attention store like the locked ones -----
# knock and counts filter on the attention rows; a redirected or foreign store
# would decide what is deliverable for them, so it is refused the way `next`
# refuses it, and an owned file that will not read is a failed read, never a
# knock line or a count.

mv "$attn_store" "$tmp/attn.aside"
ln -s "$tmp/attn.aside" "$attn_store"
rc=0
run knock --now 15300 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "knock read the attention store through a symlink (exit $rc)"
rc=0
run counts --now 15300 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "counts read the attention store through a symlink (exit $rc)"
rm -f "$attn_store"
# An owned path that is not a regular file is corruption, not absence: the
# absent-store reading counts everything as waiting on purpose, and a
# directory at that name must not inherit it.
mkdir "$attn_store"
rc=0
run knock --now 15300 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "knock read a directory at the attention store's name as an absent store (exit $rc)"
rc=0
run counts --now 15300 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "counts read a directory at the attention store's name as an absent store (exit $rc)"
rmdir "$attn_store"
mv "$tmp/attn.aside" "$attn_store"
if [ "$(id -u)" != 0 ]; then
  chmod 0000 "$attn_store"
  rc=0
  out=$(run knock --now 15400 2>/dev/null) || rc=$?
  [ "$rc" = 6 ] || fail "knock over an unreadable attention store did not fail the read (exit $rc, output '$out')"
  rc=0
  out=$(run counts --now 15400 2>/dev/null) || rc=$?
  [ "$rc" = 6 ] || fail "counts over an unreadable attention store did not fail the read (exit $rc, output '$out')"
  chmod 0600 "$attn_store"
fi
[ "$(run knock --now 15500 | cut -f 4)" = 1 ] || fail "knock is wrong once the attention store is back: '$(run knock --now 15500)'"
echo "ok: knock and counts refuse a redirected attention store and fail an unreadable one"

# --- only an answer ends the episode, not a fresh knock (REQ-F1.2) -----------
# present() is the lease predicate and reads a recent knock with no reply as
# presence, which is right for a lease and wrong for the episode: a tower the
# operator has never typed in, knocking while they are away, would end the
# episode on its next pass and push "first" again in the same departure.

: >"$log_file"
run settle "$h1" --reason 'the worker landed it' --now 15900 >/dev/null 2>&1 || fail "settling h1"
C=tower-c
n1=$(add_q wn high 16000)
run next --tower $A --now 16010 >/dev/null 2>&1 || fail "episode fixture: A knocks"
run next --tower $A --now 16200 >/dev/null 2>&1 || fail "episode fixture: A goes away"
[ "$(pushes_for "$n1")" = 1 ] || fail "the episode fixture did not get its first push ($(pushes_for "$n1"))"
run next --tower $C --now 16210 >/dev/null 2>&1 || fail "episode fixture: C knocks"
run next --tower $C --now 16220 >/dev/null 2>&1 || fail "episode fixture: C's pass inside its own quiet interval"
[ "$(push_count "$n1")" = 1 ] || fail "a fresh knock with no reply behind it ended the episode: count '$(push_count "$n1")'"
run next --tower $C --now 16400 >/dev/null 2>&1 || fail "episode fixture: C goes away"
[ "$(pushes_for "$n1")" = 1 ] || fail "a second conversation re-pushed the same departure ($(pushes_for "$n1"))"
echo "ok: a knock the operator has not answered does not end the episode"

echo "PASS: tower-queue away detection, the away push and the knock verb"
