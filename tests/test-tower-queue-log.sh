#!/bin/bash
# Tests for scripts/tower-queue.sh `log` — the tower-comms event log
# (REQ-A1.4, REQ-G1.1, REQ-G1.6, REQ-G1.7, REQ-G1.8, REQ-H1.3, REQ-H1.4).
#
# Contract under test:
#   log <kind> [--tower <id>] [--now <epoch>] [<key>=<value> ...]
#       Append one flat JSON line (schema version, monotonic sequence,
#       timestamp, kind, payload of string and number values) to the event
#       log under a 0700 sub-surface of the fleet home, under the fleet lock,
#       the sequence read and bumped from a counter file inside the same
#       critical section, age rotation inside it too, every string value
#       passed through the secret-shaped redaction.
#   Exit codes: 0 written (or a tick coalesced); 2 usage / refused input;
#       3 the bounded lock wait expired (the line is dropped and the
#       dropped-line counter bumped); 4 the surface is not verifiably
#       owner-only.
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
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

log_dir="$home/tower-comms"
log_file="$log_dir/events.log"
seq_file="$log_dir/events.seq"

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
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

tower="p123.t456.c789"

# --- static guards ----------------------------------------------------------

grep -q 'jq' "$TQ" && fail "the script mentions jq (REQ-G1.7: the script's own awk reads and writes the log)"
echo "ok: no jq in the script"

if grep -E -q '(^|[^a-z-])claude( |$|")' "$TQ"; then
  fail "the script invokes the CLI binary (REQ-H1.4: no model invocation)"
fi
echo "ok: no model invocation in the script"

# --- usage / refused input, nothing written -----------------------------------

rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no args: exit $rc, expected 2"
[ ! -e "$log_file" ] || fail "no args wrote a log"
echo "ok: no args refused"

rc=0
run log >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "log with no kind: exit $rc, expected 2"
echo "ok: log with no kind refused"

rc=0
run log sideways >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown kind: exit $rc, expected 2"
echo "ok: unknown kind refused"

rc=0
run log born item=q1 "text=$(printf 'a\tb')" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "control byte (tab): exit $rc, expected 2"
rc=0
run log born item=q1 "text=$(printf 'a\033[31mb')" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "control byte (ESC): exit $rc, expected 2"
echo "ok: control bytes refused"

rc=0
run log born item=q1 'Bad-Key=1' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed key: exit $rc, expected 2"
rc=0
run log born item=q1 '=orphan' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "empty key: exit $rc, expected 2"
rc=0
run log born item=q1 'noequals' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "field with no '=': exit $rc, expected 2"
rc=0
run log born item=q1 'seq=9' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "reserved key: exit $rc, expected 2"
echo "ok: malformed fields refused"

rc=0
run log born item=q1 'payload={"a":1}' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "nested object value: exit $rc, expected 2"
rc=0
run log born item=q1 'payload=[1,2]' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "nested array value: exit $rc, expected 2"
echo "ok: nested JSON values refused"

rc=0
run log tick --now 1000 live=1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "tick without --tower: exit $rc, expected 2"
rc=0
run log tick --tower "$tower" --now 1000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "tick without live: exit $rc, expected 2"
rc=0
run log tick --tower "$tower" --now 1000 live=many >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "tick with non-numeric live: exit $rc, expected 2"
for k in reply acknowledged delivered knocked; do
  rc=0
  run log "$k" --now 1000 item=q1 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "$k without --tower: exit $rc, expected 2"
done
rc=0
run log session --tower "$tower" event=sideways >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "session with unknown event: exit $rc, expected 2"
rc=0
run log born --tower '../x' item=q1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "hostile tower id: exit $rc, expected 2"
rc=0
run log born --now 0123 item=q1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "leading-zero --now: exit $rc, expected 2"
[ ! -e "$log_file" ] || fail "a refused write still created the log"
echo "ok: per-kind required fields and hostile flags refused before any write"

# --- the line grammar -------------------------------------------------------

run log born --now 1000 item=q1 item_kind=question worker=w1 || fail "born: exit"
[ -f "$log_file" ] || fail "log file not created"
l=$(last_line)
[ "$l" = '{"v":1,"seq":1,"ts":1000,"kind":"born","item":"q1","item_kind":"question","worker":"w1"}' ] \
  || fail "born line: $l"
echo "ok: a born line is one flat JSON object with v, seq, ts, kind"

run log tick --tower "$tower" --now 1100 live=2 || fail "tick: exit"
l=$(last_line)
[ "$l" = '{"v":1,"seq":2,"ts":1100,"kind":"tick","tower":"p123.t456.c789","live":2,"until":1100}' ] \
  || fail "tick line: $l"
echo "ok: a numeric value is written as a JSON number, the tower id as a string"

run log delivered --tower "$tower" --now 1200 item=q1 'text=He said "yes" \ done' asks=1 \
  || fail "delivered: exit"
l=$(last_line)
[ "$l" = '{"v":1,"seq":3,"ts":1200,"kind":"delivered","tower":"p123.t456.c789","item":"q1","text":"He said \"yes\" \\ done","asks":1}' ] \
  || fail "delivered line (escaping): $l"
echo "ok: quotes and backslashes are escaped, never refused"

run log born --now 1300 item=x version=007 || fail "born 007: exit"
case "$(last_line)" in
  *'"version":"007"'*) ;;
  *) fail "a leading-zero value must stay a string: $(last_line)" ;;
esac
echo "ok: a leading-zero value stays a string"

[ "$(cat "$seq_file")" = 4 ] || fail "counter file holds '$(cat "$seq_file")', expected 4"
echo "ok: the sequence counter file tracks the last sequence"

# Every line is a flat object: no nested brace or bracket after the opening.
while IFS= read -r l; do
  inner=${l#\{}
  inner=${inner%\}}
  case "$inner" in
    *'{'* | *'['*) fail "nested value in the log: $l" ;;
  esac
done <"$log_file"
echo "ok: no line in the log carries a nested value"

# --- the tower loop with no queue present -------------------------------------

run log reply --tower "$tower" --now 1400 text=yes || fail "reply with no queue: exit"
run log delivered --tower "$tower" --now 1500 text='Two workers finished' asks=1 \
  || fail "prose delivery with no queue: exit"
case "$(last_line)" in
  *'"kind":"delivered"'*'"text":"Two workers finished"'*) ;;
  *) fail "prose delivery line: $(last_line)" ;;
esac
echo "ok: a delivered turn and an operator reply log with no queue present"

# --- every event kind writes, and redaction covers all of them ----------------

# Every secret-shaped fixture is spelled as two adjacent strings so the
# literal never appears contiguously in the source or the scanner's history
# walk (the house pattern, see tests/test-inception-secret-screen.sh).
secret_token="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcd"
kinds="born settled merged knocked delivered acknowledged shelved pushed session tick reply dropped unavailable refused"
before=$(line_count "$log_file")
n=0
for k in $kinds; do
  n=$((n + 1))
  case "$k" in
    tick) run log tick --tower "$tower" --now $((2000 + n)) live=$n "note=$secret_token" || fail "tick: exit" ;;
    session) run log session --tower "$tower" --now $((2000 + n)) event=start "note=$secret_token" || fail "session: exit" ;;
    *) run log "$k" --tower "$tower" --now $((2000 + n)) item=q9 "note=$secret_token" || fail "$k: exit" ;;
  esac
  l=$(last_line)
  case "$l" in
    *"$secret_token"*) fail "$k: secret-shaped value survived redaction: $l" ;;
  esac
  case "$l" in
    *'[redacted:github-token]'*) ;;
    *) fail "$k: redaction marker missing: $l" ;;
  esac
done
after=$(line_count "$log_file")
[ "$((after - before))" = "$n" ] || fail "expected $n new lines for $n kinds, got $((after - before))"
echo "ok: every event kind appends one line and the secret-shaped value is redacted in each"

for v in \
  "AKIA""ABCDEFGHIJKLMNOP" \
  "xoxb-""0123456789abcdef" \
  "sk-""abcdefghijklmnopqrstuvwxyz" \
  "password=""abcdefghijklmnopqrstuvwxyz" \
  "-----BEGIN RSA ""PRIVATE KEY-----"; do
  run log born --now 3000 item=s "text=before $v after" || fail "born with '$v': exit"
  l=$(last_line)
  case "$l" in
    *'[redacted:'*) ;;
    *) fail "shape '$v' not redacted: $l" ;;
  esac
  case "$l" in
    *'"text":"before [redacted:'*' after"'*) ;;
    *) fail "redaction did not keep the surrounding text: $l" ;;
  esac
done
echo "ok: each built-in secret shape is redacted inside its surrounding text"

# --- tick coalescing ----------------------------------------------------------

rm -f "$log_file" "$seq_file"
run log tick --tower "$tower" --now 5000 live=2 || fail "tick 1: exit"
run log tick --tower "$tower" --now 5060 live=2 || fail "tick 2: exit"
[ "$(line_count "$log_file")" = 1 ] || fail "a same-count tick appended instead of coalescing"
[ "$(last_line)" = '{"v":1,"seq":1,"ts":5000,"kind":"tick","tower":"p123.t456.c789","live":2,"until":5060}' ] \
  || fail "coalesced tick did not advance until: $(last_line)"
[ "$(cat "$seq_file")" = 1 ] || fail "a coalesced tick consumed a sequence number"
run log tick --tower "$tower" --now 5120 live=3 || fail "tick 3: exit"
[ "$(line_count "$log_file")" = 2 ] || fail "a changed-count tick did not append"
run log tick --tower "other-tower" --now 5130 live=3 || fail "tick other tower: exit"
[ "$(line_count "$log_file")" = 3 ] || fail "another tower's tick coalesced into this tower's"
# A gap wider than tower_tick_gap_max (default 10m) never coalesces, so the
# gap stays visible to the report.
run log tick --tower "other-tower" --now 6000 live=3 || fail "tick after gap: exit"
[ "$(line_count "$log_file")" = 4 ] || fail "a tick after a gap past tower_tick_gap_max coalesced"
# A non-tick line between two same-count ticks ends the coalescing run.
run log reply --tower "other-tower" --now 6010 text=hi || fail "reply: exit"
run log tick --tower "other-tower" --now 6020 live=3 || fail "tick after reply: exit"
[ "$(line_count "$log_file")" = 6 ] || fail "a tick coalesced across an intervening line"
echo "ok: ticks coalesce on an unchanged count within the gap bound, per tower, only against the last line"

echo "ALL PASS: tower-queue log"
