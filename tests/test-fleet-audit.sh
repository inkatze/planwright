#!/bin/bash
# Tests for scripts/fleet-audit.sh — the shared audit-trail write helper every
# autonomous daemon mechanism logs through (Task 1: D-16, REQ-F1.4).
#
# Every daemon action (a cleanup, a restart, a throttle engagement) records
# its trigger and reasoning; the trail is queryable by mechanism and time
# range. Writes are validated against the fleet field/text grammar BEFORE
# write — byte-identical discipline to fleet-attention.sh's valid_field /
# valid_text (kickoff risk row 35 covers the rejection path explicitly) — and
# serialized through fleet-state.sh's advisory lock (risk row 8). Storage is
# time-bounded daily files under <fleet-home>/audit/ (risk row 18's windowing
# policy), so a query's scan cost is bounded by its time range, not the
# fleet's operating lifetime.
#
# Record format (one TSV row per action):
#   <epoch>\t<utc-iso8601>\t<mechanism>\t<action>\t<trigger>\t<reasoning>
#
# What is covered:
#   - a recorded action is queryable, and the daily file exists under the
#     fleet home's audit/ dir with a UTC date name;
#   - the rejection path: hostile mechanism/action tokens and
#     control-character / tab / newline / oversize / empty trigger or
#     reasoning are refused (exit 2) with NO partial row written;
#   - query filters by mechanism and by --since/--until epoch range, and
#     validates its own arguments;
#   - multiple records accumulate (no lost update across sequential writes);
#   - usage errors are refused (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-audit.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FA="$here/../scripts/fleet-audit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FA" ] || fail "scripts/fleet-audit.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" "$@"
}

# 1. Usage: no subcommand, unknown subcommand, missing record fields.
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no subcommand: exit $rc, expected 2"
rc=0
run shred >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown subcommand: exit $rc, expected 2"
rc=0
run record stale-cleanup cleanup >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "record with missing fields: exit $rc, expected 2"
echo "ok: usage errors are refused (exit 2)"

# 2. Happy path: record, then query — the row carries every field, and the
#    store is a UTC-dated daily file under <fleet-home>/audit/.
run record stale-cleanup cleanup "window worker-3 gone" "merged PR #12, idle 40m, death evidence positive" \
  || fail "record (happy path) failed"
out=$(run query)
case $out in
  *stale-cleanup*cleanup*"window worker-3 gone"*"merged PR #12, idle 40m, death evidence positive"*) ;;
  *) fail "query did not return the recorded row (got: '$out')" ;;
esac
utc_day=$(TZ=UTC date +%Y-%m-%d)
[ -f "$fleet_home/audit/audit-$utc_day.tsv" ] \
  || fail "daily audit file audit-$utc_day.tsv not found under the fleet home"
echo "ok: a recorded action is queryable and lands in a UTC daily file"

# 3. The rejection path (risk row 35): a malformed mechanism/action token or a
#    control-bearing / oversize / empty trigger or reasoning is refused BEFORE
#    write — the store must not gain a row.
rows_before=$(cat "$fleet_home"/audit/*.tsv | wc -l | tr -d ' ')
esc=$(printf '\033')
tab=$(printf '\t')
nl=$(printf '\nx')
long=$(awk 'BEGIN { for (i = 0; i < 513; i++) printf "a" }')
refuse() {
  rc=0
  run record "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "record $*: exit $rc, expected 2 (refused)"
}
refuse '../evil' cleanup trigger reasoning
refuse 'mech anism' cleanup trigger reasoning
refuse stale-cleanup 'clean;up' trigger reasoning
refuse stale-cleanup cleanup "bad${esc}[31mtrigger" reasoning
refuse stale-cleanup cleanup "tab${tab}torn" reasoning
refuse stale-cleanup cleanup trigger "torn${nl}row"
refuse stale-cleanup cleanup "" reasoning
refuse stale-cleanup cleanup trigger ""
refuse stale-cleanup cleanup "$long" reasoning
rows_after=$(cat "$fleet_home"/audit/*.tsv | wc -l | tr -d ' ')
[ "$rows_before" = "$rows_after" ] \
  || fail "a refused record still wrote to the store ($rows_before -> $rows_after rows)"
echo "ok: the control-free grammar refuses hostile writes with no partial row (risk 35)"

# 4. Query filters by mechanism.
run record throttle-watch throttle "429 rate-limit prompt seen" "pausing dispatch until reset" \
  || fail "second record failed"
out=$(run query --mechanism throttle-watch)
case $out in
  *throttle-watch*) ;;
  *) fail "mechanism filter returned nothing for throttle-watch" ;;
esac
case $out in
  *stale-cleanup*) fail "mechanism filter leaked another mechanism's rows" ;;
  *) ;;
esac
echo "ok: query filters by mechanism"

# 5. Query filters by time range (epoch seconds).
now=$(date +%s)
out=$(run query --since $((now + 100)))
[ -z "$out" ] || fail "--since in the future returned rows"
out=$(run query --until $((now - 100)))
[ -z "$out" ] || fail "--until in the past returned rows"
out=$(run query --since $((now - 100)) --until $((now + 100)))
case $out in
  *stale-cleanup*) ;;
  *) fail "a covering --since/--until window is missing the stale-cleanup row (got: '$out')" ;;
esac
case $out in
  *throttle-watch*) ;;
  *) fail "a covering --since/--until window is missing the throttle-watch row (got: '$out')" ;;
esac
echo "ok: query filters by --since/--until time range"

# 6. Query argument validation: hostile mechanism filter and non-numeric
#    range bounds are refused.
rc=0
run query --mechanism 'x;rm' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "hostile --mechanism: exit $rc, expected 2"
rc=0
run query --since yesterday >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "non-numeric --since: exit $rc, expected 2"
rc=0
run query --until '10; rm' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "non-numeric --until: exit $rc, expected 2"
echo "ok: query arguments are validated (exit 2)"

# 7. Sequential records accumulate — no lost update.
for i in 1 2 3 4 5; do
  run record accumulate-check cleanup "trigger $i" "reasoning $i" \
    || fail "record $i failed"
done
count=$(run query --mechanism accumulate-check | wc -l | tr -d ' ')
[ "$count" = 5 ] || fail "expected 5 accumulated rows, got $count"
echo "ok: sequential records accumulate without loss"

# 8. An empty store queries clean (exit 0, no output) rather than erroring.
fresh_home="$tmp/fresh-fleet"
rc=0
out=$(PLANWRIGHT_FLEET_STATE_DIR="$fresh_home" /bin/bash "$FA" query 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "query on an empty store: exit $rc, expected 0"
[ -z "$out" ] || fail "query on an empty store produced output: '$out'"
echo "ok: an empty store queries clean"

echo "ALL PASS: fleet-audit"
