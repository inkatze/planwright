#!/bin/bash
# Tests for scripts/tower-queue.sh `log` — the critical section: the fleet
# lock, the sequence counter, rotation, and the owner-only surface
# (REQ-A1.4, REQ-G1.1, REQ-G1.7). The line grammar, redaction and tick
# coalescing are in test-tower-queue-log.sh; split so each file stays
# inside the per-file wall-clock budget.
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
dropped_file="$log_dir/events.dropped"

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

# --- sequence monotonic across two writers under the lock ---------------------

rm -f "$log_file" "$seq_file"
(
  i=0
  while [ "$i" -lt 15 ]; do
    run log born --now 7000 item="a$i" >/dev/null 2>&1
    i=$((i + 1))
  done
) &
(
  i=0
  while [ "$i" -lt 15 ]; do
    run log born --now 7000 item="b$i" >/dev/null 2>&1
    i=$((i + 1))
  done
) &
wait
[ "$(line_count "$log_file")" = 30 ] || fail "two writers: $(line_count "$log_file") lines, expected 30"
seqs=$(sed -e 's/^{"v":1,"seq":\([0-9]*\),.*/\1/' "$log_file")
[ "$(printf '%s\n' "$seqs" | sort -n | uniq | wc -l | tr -d ' ')" = 30 ] || fail "two writers: duplicate sequence numbers"
[ "$(printf '%s\n' "$seqs" | sort -n | tail -n 1)" = 30 ] || fail "two writers: max seq is not 30"
printf '%s\n' "$seqs" | sort -n -c 2>/dev/null || fail "two writers: sequence not monotonic in file order"
while IFS= read -r l; do
  case "$l" in
    '{"v":1,"seq":'*'}') ;;
    *) fail "torn line under two writers: $l" ;;
  esac
done <"$log_file"
echo "ok: 30 lines from two writers, sequence monotonic and untorn"

# --- the bounded lock wait ----------------------------------------------------

printf 'tower_hook_lock_wait: 200ms\n' >"$local_cfg"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock for the saturation case"
before=$(line_count "$log_file")
start=$(date +%s)
rc=0
run log born --now 8000 item=late >/dev/null 2>"$tmp/err" || rc=$?
end=$(date +%s)
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
[ "$rc" = 3 ] || fail "saturated lock: exit $rc, expected 3"
[ "$(line_count "$log_file")" = "$before" ] || fail "saturated lock: a line was written unlocked"
grep -q 'lock' "$tmp/err" || fail "saturated lock: expiry not reported on stderr"
[ "$(line_count "$dropped_file")" = 1 ] || fail "saturated lock: dropped-line counter is $(line_count "$dropped_file"), expected 1"
[ $((end - start)) -le 5 ] || fail "saturated lock: waited $((end - start))s on a 200ms bound"
: >"$local_cfg"
run log born --now 8001 item=after >/dev/null || fail "write after unlock: exit"
echo "ok: the lock wait is bounded by tower_hook_lock_wait, the expiry is an error, the line is dropped and counted"

# A malformed team-shared value is a hard fail (the REQ-E1.4 by-layer policy).
mkdir -p "$tmp/.claude"
printf 'tower_hook_lock_wait: soon\n' >"$tmp/.claude/planwright.yml"
rc=0
run log born --now 8002 item=x >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "malformed repo-tracked knob: exit $rc, expected 4"
rm -f "$tmp/.claude/planwright.yml"
echo "ok: a malformed repo-tracked knob hard-fails"

# --- rotation by age inside the critical section ------------------------------

rm -f "$log_file" "$seq_file"
now=$(date +%s)
old=$((now - 40 * 86400))
recent=$((now - 3 * 86400))
{
  printf '{"v":1,"seq":1,"ts":%s,"kind":"born","item":"old"}\n' "$old"
  printf '{"v":1,"seq":2,"ts":%s,"kind":"tick","tower":"t","live":1,"until":%s}\n' "$old" "$((old + 60))"
  printf '{"v":1,"seq":3,"ts":%s,"kind":"born","item":"recent"}\n' "$recent"
} >"$log_file"
printf '3\n' >"$seq_file"
chmod 0600 "$log_file" "$seq_file"
run log born item=new || fail "rotation write: exit"
[ "$(line_count "$log_file")" = 2 ] || fail "rotation: $(line_count "$log_file") lines, expected 2"
grep -q '"item":"old"' "$log_file" && fail "rotation kept a line older than tower_log_rotate_age"
grep -q '"item":"recent"' "$log_file" || fail "rotation dropped a line inside the age"
grep -q '"seq":4,' "$log_file" || fail "rotation reset the sequence"
echo "ok: lines past tower_log_rotate_age rotate out on the next write, the sequence continues"

# The floor: the report window keeps the experiment's own sessions readable
# even when the rotation age is configured shorter than it.
printf 'tower_log_rotate_age: 1h\ntower_report_window: 5d\n' >"$local_cfg"
run log born item=again || fail "floored rotation write: exit"
grep -q '"item":"recent"' "$log_file" || fail "rotation floor: a line inside tower_report_window was rotated out"
printf 'tower_log_rotate_age: 1h\ntower_report_window: 1h\n' >"$local_cfg"
run log born item=once-more || fail "short rotation write: exit"
grep -q '"item":"recent"' "$log_file" && fail "rotation: a line past both the age and the window survived"
: >"$local_cfg"
echo "ok: rotation never cuts below tower_report_window"

# --- owner-only surface -------------------------------------------------------

# shellcheck disable=SC2012
dir_mode=$(ls -ldn "$log_dir" | awk '{print $1}')
case "$dir_mode" in
  d???------*) ;;
  *) fail "sub-surface mode is $dir_mode, expected owner-only" ;;
esac
for f in "$log_file" "$seq_file" "$dropped_file"; do
  # shellcheck disable=SC2012
  m=$(ls -ln "$f" | awk '{print $1}')
  case "$m" in
    -???------*) ;;
    *) fail "$f mode is $m, expected owner-only" ;;
  esac
done
echo "ok: the sub-surface, the log, the counter and the dropped counter are owner-only"

chmod 0750 "$log_dir"
before=$(line_count "$log_file")
rc=0
run log born --now 9000 item=loose >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "loosened directory mode: exit $rc, expected 4"
[ "$(line_count "$log_file")" = "$before" ] || fail "loosened directory mode: the write went through"
chmod 0700 "$log_dir"
chmod 0640 "$log_file"
rc=0
run log born --now 9001 item=loose >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "loosened log mode: exit $rc, expected 4"
chmod 0600 "$log_file"
rm -rf "$log_dir"
ln -s "$tmp" "$log_dir"
rc=0
run log born --now 9002 item=redirect >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "symlinked sub-surface: exit $rc, expected 4"
[ ! -e "$tmp/events.log" ] || fail "symlinked sub-surface: the write followed the link"
rm -f "$log_dir"
echo "ok: a loosened mode or a redirected surface refuses the write"

# --- no repo file changes -----------------------------------------------------

case "$log_file" in
  "$home"/*) ;;
  *) fail "log path is not under the fleet home" ;;
esac
echo "ok: the log lives under the fleet home"

echo "ALL PASS: tower-queue log lock"
