#!/bin/bash
# Tests for scripts/tower-loop-log.sh — the tower loop's two event-log
# writers (tower-comms D-14, D-15; REQ-G1.1, REQ-G1.3, REQ-G1.6, REQ-H1.4).
#
# Contract under test:
#   tick [--tower <id>] [--now <epoch>]
#       Count the live workers in the fleet's attention store (every row in a
#       live state: working, idle, hung, awaiting-input, pr-ready) and append
#       one `tick` line
#       carrying that count through `tower-queue.sh log`, which coalesces it
#       with the previous tick when the count is unchanged.
#   delivered [--tower <id>] [--asks <n>] [--now <epoch>]  < text
#       Flatten the delivered turn's text read on stdin (control bytes to
#       spaces, bounded to the log's value cap) and append one `delivered`
#       line with no item, which the scorecard counts as a prose delivery.
#   The tower identity is --tower, else PLANWRIGHT_TOWER_ID, else
#   PLANWRIGHT_TOWER_SESSION_ID; none resolvable is a refusal (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TL="$here/../scripts/tower-loop-log.sh"
TQ="$here/../scripts/tower-queue.sh"
FA="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TL" ] || fail "scripts/tower-loop-log.sh missing or not executable"
[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

log_file="$home/tower-comms/events.log"
tower="p123.t456.c789"
uuid="4c3d2e1f-0a9b-4c8d-9e7f-6a5b4c3d2e1f"

# The tower identity env is dropped first: this test runs inside dispatched
# workers, where the tower exports its own PLANWRIGHT_TOWER_ID, and the cases
# below set exactly the identity they mean to test.
run() {
  env -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID \
    PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    "$@"
}

attn() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FA" "$@" >/dev/null
}

line_count() {
  if [ -f "$1" ]; then
    wc -l <"$1" | tr -d ' '
  else
    printf '0'
  fi
}

last_line() {
  tail -n 1 "$log_file"
}

# --- static guards ----------------------------------------------------------

if grep -E -q '(^|[^a-z-])claude( |$|")' "$TL"; then
  fail "the script invokes the CLI binary (REQ-H1.4: no model invocation)"
fi
grep -q 'jq' "$TL" && fail "the script mentions jq"
echo "ok: no model invocation, no jq"

# --- identity resolution ------------------------------------------------------

rc=0
run /bin/sh "$TL" tick --now 9000 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "no identity: exit $rc, expected 2"
grep -q 'identity' "$tmp/err" || fail "no identity: the refusal does not name the identity"
[ ! -e "$log_file" ] || fail "no identity: a line was written"
rc=0
run /bin/sh "$TL" tick --tower 'bad/id' --now 9000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed --tower: exit $rc, expected 2"
rc=0
run env PLANWRIGHT_TOWER_ID='../x' /bin/sh "$TL" tick --now 9000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed PLANWRIGHT_TOWER_ID: exit $rc, expected 2"
rc=0
run env PLANWRIGHT_TOWER_SESSION_ID='not-a-uuid' /bin/sh "$TL" tick --now 9000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed PLANWRIGHT_TOWER_SESSION_ID: exit $rc, expected 2"
[ ! -e "$log_file" ] || fail "malformed identities: a line was written"
echo "ok: a missing or malformed tower identity is refused and nothing is written"

# --- one pass over an empty fleet: one tick at live=0 ---------------------------

run /bin/sh "$TL" tick --tower "$tower" --now 9000 >"$tmp/out" || fail "empty fleet tick: exit"
[ "$(line_count "$log_file")" = 1 ] || fail "empty fleet: $(line_count "$log_file") lines, expected 1"
case "$(last_line)" in
  *'"kind":"tick"'*'"live":0'*) ;;
  *) fail "empty fleet: not a tick at live=0: $(last_line)" ;;
esac
grep -q '^tick	live=0$' "$tmp/out" || fail "empty fleet: the pass did not report its count: $(cat "$tmp/out")"
echo "ok: a pass over an empty fleet writes one tick at live=0"

# --- a fixture fleet: the count matches, one tick per pass, coalesced ------------

attn heartbeat w-working tc:task-1 working || fail "fixture: heartbeat working"
attn heartbeat w-idle tc:task-2 idle || fail "fixture: heartbeat idle"
attn heartbeat w-hung tc:task-3 hung || fail "fixture: heartbeat hung"
attn heartbeat w-ready tc:task-4 pr-ready || fail "fixture: heartbeat pr-ready"
attn decide w-blocked tc:task-5 'which way?' a 'a|b' || fail "fixture: decide"
attn heartbeat w-ended tc:task-6 ended || fail "fixture: heartbeat ended"
attn heartbeat w-merged tc:task-7 merged || fail "fixture: heartbeat merged"
attn heartbeat w-done tc:task-8 'done' || fail "fixture: heartbeat done"

run env PLANWRIGHT_TOWER_ID="$tower" /bin/sh "$TL" tick --now 9100 >"$tmp/out" || fail "fixture tick: exit"
[ "$(line_count "$log_file")" = 2 ] || fail "fixture tick: $(line_count "$log_file") lines, expected 2 (exactly one new tick)"
case "$(last_line)" in
  *'"kind":"tick"'*"\"tower\":\"$tower\""*'"live":5'*'"until":9100}') ;;
  *) fail "fixture tick: expected live=5 (working, idle, hung, pr-ready, awaiting-input) for this tower: $(last_line)" ;;
esac
grep -q '^tick	live=5$' "$tmp/out" || fail "fixture tick: reported '$(cat "$tmp/out")'"
echo "ok: one pass emits one tick whose live count matches the fleet (ended, merged, done excluded)"

# A second pass at the same count coalesces: no new line, `until` advances.
run env PLANWRIGHT_TOWER_ID="$tower" /bin/sh "$TL" tick --now 9160 >/dev/null || fail "coalesced tick: exit"
[ "$(line_count "$log_file")" = 2 ] || fail "coalesced tick: $(line_count "$log_file") lines, expected 2 (coalesced, not appended)"
case "$(last_line)" in
  *'"live":5,"until":9160}') ;;
  *) fail "coalesced tick: until did not advance: $(last_line)" ;;
esac
echo "ok: a second pass at the same count coalesces rather than appending"

# The count changing lands a new line; the session-id identity form is accepted.
attn heartbeat w-working tc:task-1 ended || fail "fixture: end a worker"
run env PLANWRIGHT_TOWER_SESSION_ID="$uuid" /bin/sh "$TL" tick --now 9220 >/dev/null || fail "changed tick: exit"
[ "$(line_count "$log_file")" = 3 ] || fail "changed tick: $(line_count "$log_file") lines, expected 3"
case "$(last_line)" in
  *"\"tower\":\"$uuid\""*'"live":4,"until":9220}') ;;
  *) fail "changed tick: expected live=4 under the session identity: $(last_line)" ;;
esac
echo "ok: a changed count appends, and the session-id identity form is accepted"

# --- delivered: the turn's text flattened, bounded, redacted, counted as prose ---

token="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij0123"
printf 'Step report.\n\nDispatched task 3.\tToken %s.\nTwo asks?\n' "$token" \
  | run /bin/sh "$TL" delivered --tower "$tower" --asks 2 --now 9300 >"$tmp/out" || fail "delivered: exit"
[ "$(line_count "$log_file")" = 4 ] || fail "delivered: $(line_count "$log_file") lines, expected 4"
last=$(last_line)
case "$last" in
  *'"kind":"delivered"'*"\"tower\":\"$tower\""*'"text":"Step report.  Dispatched task 3. Token [redacted:github-token]. Two asks?"'*'"asks":2'*) ;;
  *) fail "delivered: text not flattened/redacted, or asks missing: $last" ;;
esac
case "$last" in
  *'"item"'*) fail "delivered: a prose delivery must carry no item: $last" ;;
esac
[ ! -s "$tmp/out" ] || fail "delivered: unexpected stdout: $(cat "$tmp/out")"
echo "ok: a delivered turn lands flattened and redacted, with its ask count and no item"

rc=0
printf 'x\n' | run /bin/sh "$TL" delivered --tower "$tower" --asks two --now 9301 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "delivered --asks two: exit $rc, expected 2"
rc=0
printf '' | run /bin/sh "$TL" delivered --tower "$tower" --now 9302 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "delivered with empty text: exit $rc, expected 2"
[ "$(line_count "$log_file")" = 4 ] || fail "refused deliveries: a line was written"
echo "ok: a non-numeric ask count and an empty turn are refused"

# Over-long text is bounded to the log's value cap and the line still parses.
awk 'BEGIN { for (i = 0; i < 700; i++) printf "word%04d ", i; printf "\n" }' \
  | run /bin/sh "$TL" delivered --tower "$tower" --now 9400 >/dev/null || fail "long delivered: exit"
last=$(last_line)
text_len=$(printf '%s' "$last" | awk -F'"text":"' '{ x = $2; sub(/"}$/, "", x); split(x, a, "\","); print length(a[1]) }')
[ "$text_len" -le 4096 ] || fail "long delivered: text is $text_len bytes, above the 4096 cap"
[ "$text_len" -ge 4000 ] || fail "long delivered: text is $text_len bytes, truncated far below the cap"
echo "ok: an over-long turn is bounded to the value cap"

# --- the scorecard reads what the loop wrote ------------------------------------

report=$(run /bin/sh "$TQ" report --log "$log_file" --now 9500 --window 1h --tick-gap-max 10m) || fail "report failed"
for want in "malformed	0" "prose_deliveries	2" "delivered_items	2" "tick_gaps	0" "jargon_identifiers	0"; do
  case "$report" in
    *"$want"*) ;;
    *) fail "report: expected '$want' in: $report" ;;
  esac
done
case "$report" in
  *"fleet_hours	0.0"[0-9]*) ;;
  *) fail "report: fleet hours should cover the tick spans (roughly 9100-9400): $report" ;;
esac
echo "ok: the scorecard reads the ticks as fleet hours and the turns as prose deliveries"

echo "ALL PASS: tower loop log"
