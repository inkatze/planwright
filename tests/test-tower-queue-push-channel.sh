#!/bin/bash
# Tests for where the away push goes — the notification channels, the
# session-relayed pending-push marker, and the shelve return — REQ-C1.6,
# REQ-F1.2, REQ-F1.6 (D-9, D-19). The away state machine and the knock itself
# are in test-tower-queue-away.sh.
#
# Contract under test:
#   next [--tower <id>]
#       The away push is routed through fleet-attention.sh notify. `none` and
#       `statusline` are push-less: the item stays queued, nothing is
#       transported, and the attempt is still logged. On `push` the seam
#       writes one owner-only pending-push marker per item under the fleet
#       home, and no more. Every attempt's outcome reaches the event log,
#       including the ones that fail.
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

# --- a statusline channel queues without error and without a push ------------

channel statusline
q5=$(add_q w5 high 6000)
run next --tower $A --now 6010 >/dev/null 2>&1 || fail "statusline channel knock: exit"
rc=0
run next --tower $A --now 6200 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "the statusline channel made the away pass fail (exit $rc)"
[ "$(pushes_for "$q5")" = 1 ] || fail "the statusline channel did not log the push attempt's outcome"
grep -q '"kind":"pushed".*"channel":"statusline".*"outcome":"push-less"' "$log_file" \
  || fail "the statusline channel's push-less outcome is not in the log"
[ ! -d "$push_dir" ] || fail "the statusline channel wrote a pending-push marker"
[ "$(rec "$q5" | cut -f 12)" = open ] || fail "the statusline channel did not leave the item queued"
echo "ok: a statusline channel queues the item and pushes nothing"

# --- a none channel does the same -------------------------------------------

: >"$log_file"
channel none
run settle "$q5" --reason 'the worker landed it' --now 6300 >/dev/null 2>&1 || fail "settling q5"
qn=$(add_q wn high 6400)
run next --tower $A --now 6410 >/dev/null 2>&1 || fail "none channel knock: exit"
run next --tower $A --now 6600 >/dev/null 2>&1 || fail "none channel away pass: exit"
grep -q '"kind":"pushed".*"channel":"none".*"outcome":"push-less"' "$log_file" \
  || fail "the none channel's push-less outcome is not in the log"
[ ! -d "$push_dir" ] || fail "the none channel wrote a pending-push marker"
[ "$(rec "$qn" | cut -f 12)" = open ] || fail "the none channel did not leave the item queued"
echo "ok: a none channel queues the item and pushes nothing"

# --- the push channel writes one pending-push marker per item, and no more ----
# (REQ-F1.6, D-19)

: >"$log_file"
channel push
run settle "$qn" --reason 'the worker landed it' --now 6900 >/dev/null 2>&1 || fail "settling qn"
q6=$(add_q w6 high 7000)
run next --tower $A --now 7010 >/dev/null 2>&1 || fail "push channel knock: exit"
run next --tower $A --now 7200 >/dev/null 2>&1 || fail "push channel away pass: exit"
[ -f "$push_dir/$q6" ] || fail "the push channel wrote no pending-push marker for $q6"
[ "$(markers)" = 1 ] || fail "the push channel wrote more than one marker ($(markers))"
grep -q "\"kind\":\"pushed\".*\"item\":\"$q6\".*\"stage\":\"first\".*\"outcome\":\"queued\"" "$log_file" \
  || fail "the push channel's queued outcome is not in the log"
# `ls -l` over a known-good literal path: the portable mode read on the
# macOS + Linux support bar (`stat` disagrees between BSD and GNU).
# shellcheck disable=SC2012
mode=$(ls -l "$push_dir/$q6" | cut -c1-10)
case "$mode" in -rw-------) ;; *) fail "the pending-push marker is not owner-only: $mode" ;; esac
# shellcheck disable=SC2012
dmode=$(ls -ld "$push_dir" | cut -c1-10)
case "$dmode" in drwx------) ;; *) fail "the pending-push directory is not owner-only: $dmode" ;; esac
line=$(cat "$push_dir/$q6")
case "$line" in *planwright*) ;; *) fail "the marker carries no relayable line: '$line'" ;; esac
[ "$(printf '%s' "$line" | wc -c)" -lt 200 ] || fail "the relayed line is 200 characters or more"
[ "$(printf '%s\n' "$line" | grep -c .)" = 1 ] || fail "the relayed line is more than one line"

# The second stage is a distinct attempt and reaches the log as one, even
# though the marker per item is the contract and so is not written twice.
stamp=$(cat "$push_dir/$q6")
run next --tower $A --now 8500 >/dev/null 2>&1 || fail "push channel re-knock pass: exit"
[ "$(markers)" = 1 ] || fail "the re-push wrote a second marker for the same item"
[ "$(cat "$push_dir/$q6")" = "$stamp" ] || fail "the re-push overwrote the pending marker"
[ "$(pushes_for "$q6")" = 2 ] || fail "the worsening push was not logged as its own attempt ($(pushes_for "$q6"))"
grep -q '"kind":"pushed".*"stage":"aged"' "$log_file" || fail "the second attempt does not name the aged stage"
echo "ok: the push channel writes one pending-push marker per item and no more"

# --- a push the seam refuses is logged as failed, and the item stays queued ---
# The marker path is made unwritable, which is the one failure a fixture can
# stage without reaching into the seam: the channel resolves, the transport
# runs, and the write is what fails.

: >"$log_file"
run settle "$q6" --reason 'the worker landed it' --now 8600 >/dev/null 2>&1 || fail "settling q6"
rm -rf "$push_dir"
: >"$push_dir"
chmod 0600 "$push_dir"
qf=$(add_q wf high 8700)
# A is already away here, so this one pass both knocks and makes the first
# push attempt for the new item.
run next --tower $A --now 8710 >/dev/null 2>&1 || true
grep -q "\"kind\":\"pushed\".*\"item\":\"$qf\".*\"outcome\":\"failed\"" "$log_file" \
  || fail "a refused push was not logged as failed"
[ "$(rec "$qf" | cut -f 12)" = open ] || fail "a refused push did not leave the item queued"
rm -f "$push_dir"
echo "ok: a push the seam refuses is logged as failed and leaves the item queued"

# --- an unresolvable channel is logged as failed too -------------------------
# A repo-tracked malformed value is the resolver's hard-fail (it refuses to
# silently degrade a shared team value), so nothing can be transported.

: >"$log_file"
run settle "$qf" --reason 'the worker landed it' --now 9000 >/dev/null 2>&1 || fail "settling qf"
channel not-a-channel
qu=$(add_q wu high 9010)
run next --tower $A --now 9020 >/dev/null 2>&1 || true
grep -q "\"kind\":\"pushed\".*\"item\":\"$qu\".*\"channel\":\"-\".*\"outcome\":\"failed\"" "$log_file" \
  || fail "an unresolvable channel was not logged as a failed attempt"
[ "$(rec "$qu" | cut -f 12)" = open ] || fail "an unresolvable channel did not leave the item queued"
channel none
echo "ok: an unresolvable channel is logged as a failed attempt and leaves the item queued"

# --- shelve returns at the knob's interval and at an overridden one -----------
# (REQ-C1.6), and both knobs take a sub-second span.

: >"$log_file"
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 1000s\ntower_shelve_return: 500s\n' >"$local_cfg"
run settle "$qu" --reason 'the worker landed it' --now 9300 >/dev/null 2>&1 || fail "settling qu"
q7=$(add_q w7 high 9400)
run shelve "$q7" --now 9440 >/dev/null 2>&1 || fail "shelve: exit"
[ "$(rec "$q7" | cut -f 16)" = 9940 ] || fail "shelve did not use tower_shelve_return: $(rec "$q7" | cut -f 16)"
[ "$(run counts --now 9900 | awk -F '\t' '$1 == "question" { print $2 }')" = 0 ] \
  || fail "a shelved item still counts as waiting before its return"
[ "$(run counts --now 10000 | awk -F '\t' '$1 == "question" { print $2 }')" = 1 ] \
  || fail "the shelved item did not return at tower_shelve_return"

q8=$(add_q w8 high 10100)
run shelve "$q8" --for 60s --now 10110 >/dev/null 2>&1 || fail "shelve --for: exit"
[ "$(rec "$q8" | cut -f 16)" = 10170 ] || fail "--for did not override tower_shelve_return: $(rec "$q8" | cut -f 16)"

# Sub-second spans are legal for both knobs the delivery task owns, and a span
# that silently parsed as zero would park an item until the next second rather
# than for the span asked for.
printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\ntower_reknock_age: 250ms\ntower_shelve_return: 1500ms\n' >"$local_cfg"
q9=$(add_q w9 high 10200)
run shelve "$q9" --now 10210 >/dev/null 2>&1 || fail "shelve with a sub-second return: exit"
[ "$(rec "$q9" | cut -f 16)" = 10211 ] || fail "a sub-second tower_shelve_return did not park for its own span: $(rec "$q9" | cut -f 16)"
echo "ok: a shelved item returns at tower_shelve_return, at an overridden span, and at a sub-second one"

echo "PASS: the away push's channels, its pending-push marker, and the shelve return"
