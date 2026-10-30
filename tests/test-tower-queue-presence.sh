#!/bin/bash
# Tests for scripts/tower-queue.sh presence: the `presence` verb and the
# presence read `next` and the away push take — REQ-F1.7, REQ-F1.9, REQ-G1.9
# (D-23).
#
# Contract under test:
#   presence --tower <id> --producer <name> (--last-prompt <epoch> | --away)
#            [--now <epoch>]
#       Writes the per-tower presence marker owner-only under the fleet
#       home's 0700 sub-surface, refusing a loosened directory mode, a control
#       byte, an unknown producer or a malformed field, then runs the settling
#       pass in the same call.
#   next [--tower <id>]
#       Reads presence from the marker first while it is fresh within
#       tower_presence_ttl, else from the quiet-interval rule; a reply on the
#       attention marker later than the presence marker's write is present;
#       hands nothing over while the operator is away; logs each switch of
#       source once. The marker never confirms attention: content still
#       waits for a reply on the attention marker.
#
# The marker written here is a fixture standing in for the mission-control
# panel, which builds the real producer.
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
git init -q "$repo"
printf 'notification_channel: none\n' >"$repo/.claude/planwright.yml"

surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
pdir="$surface/presence"
TAB=$(printf '\t')

printf 'notification_channel: none\ntower_hook_lock_wait: 2s\ntower_quiet_interval: 10m\ntower_lease_interval: 15m\ntower_catchup_limit: 20\ntower_shelve_return: 1h\ntower_reknock_age: 30m\ntower_presence_ttl: 2m\ntower_tick_gap_max: 10m\ntower_log_rotate_age: 30d\ntower_report_window: 7d\n' >"$core_cfg"

knobs() { # knobs <presence ttl>
  printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 1000s\ntower_presence_ttl: %s\n' "$1" >"$local_cfg"
}
knobs 60s

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

# pres <tower> <args...> — the fixture producer's write.
pres() {
  p_t=$1
  shift
  run presence --tower "$p_t" --producer mission-control "$@"
}

marker() { # the prompt-submit hook's attention marker: a reply
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

field() { printf '%s\n' "$1" | cut -f "$2"; }
rec() { grep "^$1$TAB" "$store"; }
state_of() { rec "$1" | cut -f 12; }
push_count() { rec "$1" | cut -f 26; }
pushes_for() { grep -c "\"kind\":\"pushed\".*\"item\":\"$1\"" "$log_file" || true; }
switches() { # switches <tower> <to>
  grep "\"kind\":\"presence\"" "$log_file" | grep "\"tower\":\"$1\"" | grep -c "\"to\":\"$2\"" || true
}
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

attn_dir="$home/attention"
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
attn_store="$attn_dir/state"
: >"$attn_store"
chmod 0600 "$attn_store"

add_q() { # add_q <worker> <urgency> <now> [<subject>]
  printf '%s\tspec\tawaiting-input\t%s\t%s\tquestion raised at %s\t-\tA|B\t-\t-\n' \
    "$1" "$3" "$2" "$3" >>"$attn_store"
  if [ -n "${4:-}" ]; then
    run add --kind question --worker "$1" --origin "$1" --subject "$4" --closes 'the operator answers' --now "$3"
  else
    run add --kind question --worker "$1" --origin "$1" --closes 'the operator answers' --now "$3"
  fi
}

A=tower-a
B=tower-b
C=tower-c

# --- the presence verb writes the marker owner-only (REQ-F1.7) ---------------

out=$(pres $A --last-prompt 995 --now 1000) || fail "a well-formed presence write: exit"
[ -f "$pdir/$A" ] || fail "the presence write left no marker"
[ "$(mode_of "$pdir")" = 700 ] || fail "the presence directory is not 0700 ($(mode_of "$pdir"))"
[ "$(mode_of "$pdir/$A")" = 600 ] || fail "the presence marker is not 0600 ($(mode_of "$pdir/$A"))"
[ "$(cat "$pdir/$A")" = "mission-control${TAB}1000${TAB}995" ] \
  || fail "the marker does not carry producer, write time and last prompt: '$(cat "$pdir/$A")'"
pres $A --away --now 1001 >/dev/null || fail "an away presence write: exit"
[ "$(cut -f 3 "$pdir/$A")" = away ] || fail "the away write did not record away: '$(cat "$pdir/$A")'"
echo "ok: the presence verb writes the producer, the write time and the last prompt or away, owner-only"

# --- malformed writes are refused and leave the marker as it was -------------

before=$(cat "$pdir/$A")
refused() { # refused <expected exit> <what> <args...>
  r_want=$1
  r_what=$2
  shift 2
  r_rc=0
  run presence "$@" >/dev/null 2>&1 || r_rc=$?
  [ "$r_rc" = "$r_want" ] || fail "$r_what was not refused with exit $r_want (exit $r_rc)"
  [ "$(cat "$pdir/$A")" = "$before" ] || fail "$r_what changed the marker"
}
refused 2 "an unknown producer" --tower $A --producer someone-else --last-prompt 1000 --now 1002
refused 2 "a producer carrying a control byte" --tower $A --producer "$(printf 'mission-control\001')" --last-prompt 1000 --now 1002
refused 2 "a last prompt carrying a control byte" --tower $A --producer mission-control --last-prompt "$(printf '1000\033')" --now 1002
refused 2 "an unknown field" --tower $A --producer mission-control --last-prompt 1000 --mood calm --now 1002
refused 2 "both a last prompt and away" --tower $A --producer mission-control --last-prompt 1000 --away --now 1002
refused 2 "neither a last prompt nor away" --tower $A --producer mission-control --now 1002
refused 2 "a last prompt later than the write" --tower $A --producer mission-control --last-prompt 1003 --now 1002
refused 2 "no tower" --producer mission-control --last-prompt 1000 --now 1002
refused 2 "a tower that is no identity" --tower ../$A --producer mission-control --last-prompt 1000 --now 1002
chmod 0750 "$pdir"
refused 4 "a write under a loosened directory mode" --tower $A --producer mission-control --last-prompt 1000 --now 1002
chmod 0700 "$pdir"
mv "$pdir/$A" "$tmp/marker.aside"
ln -s "$tmp/marker.aside" "$pdir/$A"
rc=0
run presence --tower $A --producer mission-control --last-prompt 1000 --now 1002 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "a write through a symlinked marker was not refused (exit $rc)"
rm -f "$pdir/$A"
mv "$tmp/marker.aside" "$pdir/$A"
echo "ok: a loosened directory, a redirect, a control byte, an unknown producer or field, and a malformed time are refused"

# --- a presence write runs the settling pass in the same call (REQ-F1.9) -----

qe=$(add_q wev normal 1100 pr:7)
printf 'stamp\t1100\npr\t7\tmerged\n' >"$surface/evidence"
chmod 0600 "$surface/evidence"
out=$(pres $A --last-prompt 1105 --now 1110) || fail "the presence write over arrived evidence: exit"
[ "$(state_of "$qe")" = closed ] || fail "the presence write did not settle an item whose evidence had arrived"
printf '%s\n' "$out" | grep -q "^settled${TAB}$qe${TAB}" || fail "the presence write did not report the settlement: '$out'"
rm -f "$surface/evidence"
echo "ok: a presence write runs the settling pass and settles an item whose evidence has arrived"

# --- a fresh present marker: present, and a due knock is returned -----------
# It never releases content: that still waits for a reply on the attention
# marker (knock-first, D-6).

: >"$log_file"
q1=$(add_q w1 high 2000)
pres $A --last-prompt 2000 --now 2001 >/dev/null || fail "present write: exit"
out=$(run next --tower $A --now 2005 2>/dev/null) || fail "next with a fresh present marker: exit"
[ "$(field "$out" 1)" = knock ] || fail "a fresh present marker did not get the due knock: '$out'"
[ "$(switches $A marker)" = 1 ] || fail "the first read of a fresh marker was not logged as a switch to it"
pres $A --last-prompt 2015 --now 2020 >/dev/null || fail "present refresh: exit"
out=$(run next --tower $A --now 2025 2>/dev/null) || fail "next with the knock unanswered: exit"
[ -z "$out" ] || fail "a present marker released something with no reply on the attention marker: '$out'"
marker $A 2030
out=$(run next --tower $A --now 2035 2>/dev/null) || fail "next after the reply: exit"
[ "$(field "$out" 1)" = item ] || fail "the reply on the attention marker did not release the item: '$out'"
[ "$(field "$out" 2)" = "$q1" ] || fail "the wrong item was handed over: '$out'"
run ack "$q1" --tower $A --now 2040 >/dev/null 2>&1 || fail "ack q1"
[ "$(switches $A marker)" = 1 ] || fail "an unchanged source was logged again"
echo "ok: a fresh present marker reads present and gets the knock, and content still waits for a reply"

# --- the marker is read first: present overrides the quiet rule's away -------
# With the knock unanswered past the quiet interval the fallback reads away and
# pushes; a fresh present marker holds the push. Once that marker goes stale,
# the quiet rule is back and the push fires, the switch logged once.

q2=$(add_q w2 high 2200)
pres $A --last-prompt 2200 --now 2202 >/dev/null || fail "present refresh before the q2 knock: exit"
out=$(run next --tower $A --now 2205 2>/dev/null) || fail "q2 knock: exit"
[ "$(field "$out" 1)" = knock ] || fail "q2 was not knocked: '$out'"
pres $A --last-prompt 2395 --now 2399 >/dev/null || fail "present refresh past the quiet interval: exit"
run next --tower $A --now 2400 >/dev/null 2>&1 || fail "next with a present marker past the quiet interval: exit"
[ "$(pushes_for "$q2")" = 0 ] || fail "the quiet rule pushed over a fresh present marker"
run next --tower $A --now 2500 >/dev/null 2>&1 || fail "next with the marker stale: exit"
[ "$(pushes_for "$q2")" = 1 ] || fail "with the marker stale the quiet rule did not take over and push"
[ "$(switches $A fallback)" = 1 ] || fail "the switch to the fallback was not logged once ($(switches $A fallback))"
run next --tower $A --now 2510 >/dev/null 2>&1 || fail "next with the marker still stale: exit"
[ "$(switches $A fallback)" = 1 ] || fail "the switch to the fallback was logged again with no switch"
run settle "$q2" --reason 'the worker landed it' --now 2600 >/dev/null 2>&1 || fail "settling q2"
echo "ok: a fresh marker is read before the quiet rule, and a stale one falls back to it, logged once"

# --- a fresh away marker: nothing handed over, the away push fires -----------
# (REQ-F1.2 through the presence input) and a reply after the marker's write
# makes the operator present again.

: >"$log_file"
q3=$(add_q w3 high 3000)
pres $B --away --now 3001 >/dev/null || fail "away write: exit"
out=$(run next --tower $B --now 3002 2>/dev/null) || fail "next with a fresh away marker: exit"
[ -z "$out" ] || fail "next handed something over while the marker says away: '$out'"
[ "$(pushes_for "$q3")" = 1 ] || fail "the away marker did not fire the away push ($(pushes_for "$q3"))"
grep -q '"kind":"pushed".*"outcome":"' "$log_file" || fail "the away push's outcome was not logged"
run next --tower $B --now 3010 >/dev/null 2>&1 || fail "next while still away: exit"
[ "$(pushes_for "$q3")" = 1 ] || fail "the away push repeated while nothing worsened ($(pushes_for "$q3"))"
marker $B 3020
out=$(run next --tower $B --now 3025 2>/dev/null) || fail "next after a reply later than the marker: exit"
[ "$(field "$out" 1)" = knock ] || fail "a reply later than the away marker's write did not make the operator present: '$out'"
[ "$(push_count "$q3")" = 0 ] || fail "the operator's return did not end the push episode"
marker $B 3030
pres $B --away --now 3040 >/dev/null || fail "second away write: exit"
out=$(run next --tower $B --now 3045 2>/dev/null) || fail "next with a reply older than the away marker: exit"
[ -z "$out" ] || fail "a reply older than the away marker's write released content: '$out'"
[ "$(state_of "$q3")" = open ] || fail "the away read closed the item"
echo "ok: a fresh away marker hands nothing over and pushes; a later reply marks the operator present"

# --- stale, deleted, or corrupt: the quiet rule, each switch logged once -----

run next --tower $B --now 3200 >/dev/null 2>&1 || fail "next with B's marker stale: exit"
run next --tower $B --now 3210 >/dev/null 2>&1 || fail "next with B's marker still stale: exit"
[ "$(switches $B fallback)" = 1 ] || fail "a stale marker's switch was not logged exactly once ($(switches $B fallback))"
pres $B --last-prompt 3300 --now 3300 >/dev/null || fail "fresh write after stale: exit"
run next --tower $B --now 3301 >/dev/null 2>&1 || fail "next back on the marker: exit"
rm -f "$pdir/$B"
run next --tower $B --now 3302 >/dev/null 2>&1 || fail "next with the marker deleted: exit"
run next --tower $B --now 3303 >/dev/null 2>&1 || fail "next with the marker still deleted: exit"
[ "$(switches $B fallback)" = 2 ] || fail "a deleted marker's switch was not logged exactly once ($(switches $B fallback))"
pres $B --last-prompt 3400 --now 3400 >/dev/null || fail "fresh write after delete: exit"
run next --tower $B --now 3401 >/dev/null 2>&1 || fail "next back on the marker again: exit"
printf 'someone-else\t3402\t3402\n' >"$pdir/$B"
run next --tower $B --now 3402 >/dev/null 2>&1 || fail "next with a marker naming an unknown producer: exit"
pres $B --last-prompt 3403 --now 3403 >/dev/null || fail "fresh write after a planted marker: exit"
run next --tower $B --now 3404 >/dev/null 2>&1 || fail "next back on the marker a third time: exit"
printf 'not a marker\n' >"$pdir/$B"
run next --tower $B --now 3405 >/dev/null 2>&1 || fail "next with a corrupt marker: exit"
run next --tower $B --now 3406 >/dev/null 2>&1 || fail "next with the marker still corrupt: exit"
[ "$(switches $B fallback)" = 4 ] || fail "corrupt markers' switches were not logged once each ($(switches $B fallback))"
[ "$(switches $B marker)" = 4 ] || fail "the returns to the marker were not logged once each ($(switches $B marker))"
grep '"kind":"presence"' "$log_file" | grep -q '"from":"marker"' || fail "a switch line does not name the source it left"
echo "ok: a stale, deleted or corrupt marker falls back to the quiet rule, each switch logged once"

# --- tower_presence_ttl accepts a sub-second value ---------------------------

knobs 500ms
pres $C --last-prompt 4000 --now 4000 >/dev/null || fail "write under a sub-second ttl: exit"
run next --tower $C --now 4001 >/dev/null 2>&1 || fail "next under a sub-second ttl: exit"
[ "$(switches $C marker)" = 0 ] || fail "a marker a second old was read as fresh under a 500ms ttl"
knobs 60s
run next --tower $C --now 4002 >/dev/null 2>&1 || fail "next back under the 60s ttl: exit"
[ "$(switches $C marker)" = 1 ] || fail "a two-second-old marker was not fresh under a 60s ttl"
echo "ok: tower_presence_ttl takes a sub-second value"

# --- a prompt event is not an answer: it never ends the push episode ---------
# The marker going stale and fresh again while the operator never replies must
# not re-arm the first push: only worsening pushes again (REQ-F1.3).

D=tower-d
qd=$(add_q wd high 5000)
run next --tower $D --now 5001 >/dev/null 2>&1 || fail "D's knock: exit"
pres $D --last-prompt 5150 --now 5150 >/dev/null || fail "D present write: exit"
run next --tower $D --now 5160 >/dev/null 2>&1 || fail "next with D's marker fresh: exit"
run next --tower $D --now 5220 >/dev/null 2>&1 || fail "next with D's marker stale: exit"
[ "$(pushes_for "$qd")" = 1 ] || fail "the stale marker's fallback did not push once ($(pushes_for "$qd"))"
pres $D --last-prompt 5150 --now 5225 >/dev/null || fail "D present refresh: exit"
run next --tower $D --now 5226 >/dev/null 2>&1 || fail "next with D's marker fresh again: exit"
run next --tower $D --now 5290 >/dev/null 2>&1 || fail "next with D's marker stale again: exit"
[ "$(pushes_for "$qd")" = 1 ] || fail "a prompt event with no reply re-armed the first push ($(pushes_for "$qd"))"
run settle "$qd" --reason 'the worker landed it' --now 5300 >/dev/null 2>&1 || fail "settling qd"
echo "ok: a prompt event on the marker never ends the push episode; only an answer does"

# --- a reply outranks the marker only within the quiet interval --------------
# With tower_presence_ttl above tower_quiet_interval, a reply later than an
# away marker still lapses after the quiet interval, as it does in the
# fallback, rather than reading present for as long as the marker is fresh.

knobs 300s
E=tower-e
qe2=$(add_q we high 6000)
pres $E --away --now 6000 >/dev/null || fail "E away write: exit"
marker $E 6001
run next --tower $E --now 6002 >/dev/null 2>&1 || fail "next with E's reply after the away marker: exit"
[ "$(pushes_for "$qe2")" = 0 ] || fail "a reply later than the away marker did not read present"
run next --tower $E --now 6250 >/dev/null 2>&1 || fail "next with E's reply past the quiet interval: exit"
[ "$(pushes_for "$qe2")" = 1 ] || fail "a reply older than the quiet interval still outranked a fresh away marker ($(pushes_for "$qe2"))"
run settle "$qe2" --reason 'the worker landed it' --now 6300 >/dev/null 2>&1 || fail "settling qe2"
knobs 60s
echo "ok: a reply outranks a fresh marker only while it is within the quiet interval"

# --- a failed switch record leaves the store untouched -----------------------
# When the delivery record cannot take the new source, `next` fails before the
# store commits, so the away push it stamped is not spent unsent.

if [ "$(id -u)" != 0 ]; then
  F=tower-f
  qf=$(add_q wf high 7000)
  pres $F --away --now 7000 >/dev/null || fail "F away write: exit"
  chmod 0500 "$surface/delivery"
  rc=0
  run next --tower $F --now 7001 >/dev/null 2>&1 || rc=$?
  chmod 0700 "$surface/delivery"
  [ "$rc" = 6 ] || fail "a delivery record that cannot be written did not fail next (exit $rc)"
  [ "$(push_count "$qf")" = 0 ] || fail "the failed next spent the away push without sending it"
  run next --tower $F --now 7002 >/dev/null 2>&1 || fail "next after the delivery directory was restored: exit"
  [ "$(pushes_for "$qf")" = 1 ] || fail "the away push was lost to the failed switch record ($(pushes_for "$qf"))"
  run settle "$qf" --reason 'the worker landed it' --now 7100 >/dev/null 2>&1 || fail "settling qf"
  echo "ok: a switch record that cannot be written fails next before the store commits"
fi

# --- the knob ships with its default and its options-reference row -----------

grep -q '^tower_presence_ttl: 2m$' "$here/../config/defaults.yml" || fail "config/defaults.yml does not ship tower_presence_ttl: 2m"
grep -qF "| \`tower_presence_ttl\` | \`2m\` |" "$here/../docs/options-reference.md" || fail "docs/options-reference.md has no tower_presence_ttl row"
echo "ok: tower_presence_ttl ships with its default and its reference row"

echo "PASS: tower-queue presence"
