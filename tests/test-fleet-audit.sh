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

# 2b. The row is structurally a 6-field TSV in the documented order
#     (epoch, iso, mechanism, action, trigger, reasoning) — substring
#     presence alone would pass a query that merged or reordered columns.
row_check=$(run query --mechanism stale-cleanup | awk -F '	' '
  NF == 6 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]{4}-/ && $3 == "stale-cleanup" && $4 == "cleanup" { print "shape-ok" }')
[ "$row_check" = shape-ok ] || fail "queried row is not the documented 6-field TSV shape"
echo "ok: the queried row has the documented 6-field TSV shape"

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

# 5b. --mechanism combined with a time range ANDs the predicates (REQ-F1.4:
#     "queryable by mechanism and time range").
out=$(run query --mechanism throttle-watch --since $((now - 100)) --until $((now + 100)))
case $out in
  *throttle-watch*) ;;
  *) fail "combined mechanism+range query missed the matching row" ;;
esac
case $out in
  *stale-cleanup*) fail "combined mechanism+range query leaked another mechanism" ;;
  *) ;;
esac
out=$(run query --mechanism throttle-watch --since $((now + 100)))
[ -z "$out" ] || fail "combined query ignored the range bound when the mechanism matched"
echo "ok: query ANDs the mechanism and time-range filters"

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
rc=0
run query --since 1234567890123456 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "over-length (16-digit) --since: exit $rc, expected 2"
rc=0
run query --frobnicate >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown query flag: exit $rc, expected 2"
for flag in --mechanism --since --until; do
  rc=0
  run query "$flag" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "query $flag with no value: exit $rc, expected 2"
done
echo "ok: query arguments are validated (exit 2)"

# 7. Sequential records accumulate — no lost update.
for i in 1 2 3 4 5; do
  run record accumulate-check cleanup "trigger $i" "reasoning $i" \
    || fail "record $i failed"
done
count=$(run query --mechanism accumulate-check | wc -l | tr -d ' ')
[ "$count" = 5 ] || fail "expected 5 accumulated rows, got $count"
echo "ok: sequential records accumulate without loss"

# 7b. CONCURRENT writers all land (kickoff risk row 8: writes serialize
#     through the advisory lock). Eight simultaneous records; without real
#     serialization the copy-append-rename write path would lose rows.
conc_home="$tmp/conc-fleet"
i=1
while [ "$i" -le 8 ]; do
  PLANWRIGHT_FLEET_STATE_DIR="$conc_home" /bin/bash "$FA" \
    record concurrent-check cleanup "trigger $i" "reasoning $i" &
  i=$((i + 1))
done
wait
count=$(PLANWRIGHT_FLEET_STATE_DIR="$conc_home" /bin/bash "$FA" query --mechanism concurrent-check | wc -l | tr -d ' ')
[ "$count" = 8 ] || fail "concurrent writers: expected 8 rows, got $count (lost update under contention)"
malformed=$(PLANWRIGHT_FLEET_STATE_DIR="$conc_home" /bin/bash "$FA" query --mechanism concurrent-check \
  | awk -F '	' 'NF != 6 { n++ } END { print n + 0 }')
[ "$malformed" = 0 ] || fail "concurrent writers: $malformed malformed rows (torn write)"
echo "ok: eight concurrent writers all land whole rows (lock serialization, risk 8)"

# 7c. A fleet home whose path contains whitespace round-trips record and
#     query (the query file-listing must not word-split the directory
#     prefix).
sp_home="$tmp/fleet home sp"
PLANWRIGHT_FLEET_STATE_DIR="$sp_home" /bin/bash "$FA" \
  record space-check cleanup "trigger sp" "reasoning sp" \
  || fail "record failed under a whitespace fleet home"
out=$(PLANWRIGHT_FLEET_STATE_DIR="$sp_home" /bin/bash "$FA" query --mechanism space-check 2>&1) \
  || fail "query failed under a whitespace fleet home (got: '$out')"
case $out in
  *space-check*) ;;
  *) fail "query under a whitespace fleet home returned no row (got: '$out')" ;;
esac
echo "ok: a whitespace fleet-home path round-trips record and query"

# 7d. A hand-corrupted store line cannot drive the terminal (read-side
#     re-sanitization) and a truncated row is skipped with a warning, never
#     emitted as data.
cor_home="$tmp/corrupt-fleet"
PLANWRIGHT_FLEET_STATE_DIR="$cor_home" /bin/bash "$FA" \
  record corrupt-check cleanup "clean trigger" "clean reasoning" \
  || fail "seed record for corruption test failed"
cor_file=$(find "$cor_home/audit" -name 'audit-*.tsv' | head -1)
esc2=$(printf '\033')
printf '1700000000\t2023-11-14T00:00:00Z\tcorrupt-check\tcleanup\tbad%s[31mtrigger\thand-edited\n' "$esc2" >>"$cor_file"
printf 'short\trow\n' >>"$cor_file"
q_out=$(PLANWRIGHT_FLEET_STATE_DIR="$cor_home" /bin/bash "$FA" query --mechanism corrupt-check 2>"$tmp/q-err")
case $q_out in
  *"$esc2"*) fail "query emitted a raw control byte from a corrupted store line" ;;
  *) ;;
esac
case $q_out in
  *"bad[31mtrigger"*) ;;
  *) fail "query dropped the sanitized corrupted row instead of stripping it (got: '$q_out')" ;;
esac
case $q_out in
  *short*) fail "query emitted a truncated (non-6-field) row as data" ;;
  *) ;;
esac
grep -q "skipp" "$tmp/q-err" || fail "query did not warn about the skipped truncated row"
echo "ok: read-side sanitization strips control bytes and truncated rows are skipped with a warning"

# 7e. The query view is printable ASCII while the store is byte-exact: the
#     write grammar admits bytes >= 0xA0 (sanitize_printable strips only
#     C0/DEL/C1), the daily file keeps them, and the query's in-awk
#     [[:print:]] strip (echo-safety.sh's documented awk-form posture) drops
#     them from the OUTPUT only — the store, not the query, is the durable
#     record.
u_home="$tmp/utf8-fleet"
u_reason=$(printf 'caf\303\251 nominal')
PLANWRIGHT_FLEET_STATE_DIR="$u_home" /bin/bash "$FA" \
  record utf8-check cleanup "trigger ok" "$u_reason" \
  || fail "record refused an admissible >=0xA0 byte sequence"
u_file=$(find "$u_home/audit" -name 'audit-*.tsv' | head -1)
grep -q "$u_reason" "$u_file" || fail "store did not keep the admitted >=0xA0 bytes byte-exact"
u_out=$(PLANWRIGHT_FLEET_STATE_DIR="$u_home" /bin/bash "$FA" query --mechanism utf8-check 2>/dev/null)
case $u_out in
  *"caf nominal"*) ;;
  *) fail "query output is not the printable-ASCII view (got: '$u_out')" ;;
esac
echo "ok: query output is printable ASCII while the store keeps admitted bytes"

# 7f. A store match that is not a regular file (a directory named
#     audit-*.tsv) is a corrupted home and fails the query loudly BEFORE any
#     row is emitted — awk's handling of a directory operand is
#     platform-variant (BSD awk silently tolerates it, gawk warns or fails),
#     so the pre-check must refuse deterministically, and partial output
#     must never look like a complete answer.
nf_home="$tmp/nonfile-fleet"
PLANWRIGHT_FLEET_STATE_DIR="$nf_home" /bin/bash "$FA" \
  record nonfile-check cleanup "clean trigger" "clean reasoning" \
  || fail "seed record for non-regular-file test failed"
mkdir "$nf_home/audit/audit-9999-12-31.tsv"
rc=0
nf_out=$(PLANWRIGHT_FLEET_STATE_DIR="$nf_home" /bin/bash "$FA" query 2>"$tmp/nf-err") || rc=$?
[ "$rc" = 2 ] || fail "query with a directory store match: exit $rc, expected 2"
[ -z "$nf_out" ] || fail "query with a directory store match emitted partial rows (got: '$nf_out')"
grep -q "not a regular file" "$tmp/nf-err" || fail "query did not name the non-regular-file store match"
echo "ok: a non-regular-file store match fails the query loudly with no partial output"

# 8. An empty store queries clean (exit 0, no output) rather than erroring.
fresh_home="$tmp/fresh-fleet"
rc=0
out=$(PLANWRIGHT_FLEET_STATE_DIR="$fresh_home" /bin/bash "$FA" query 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "query on an empty store: exit $rc, expected 0"
[ -z "$out" ] || fail "query on an empty store produced output: '$out'"
echo "ok: an empty store queries clean"

# 8b. A fleet home whose audit PATH exists as a regular file (a corrupted
#     home) must not masquerade as an empty trail: query fails loudly
#     (exit 2), the fail-closed parity of record's own mkdir failure on the
#     same corrupted state.
notadir_home="$tmp/notadir-fleet"
mkdir -p "$notadir_home"
: >"$notadir_home/audit"
rc=0
err=$(PLANWRIGHT_FLEET_STATE_DIR="$notadir_home" /bin/bash "$FA" query 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "audit path as a regular file: query exit $rc, expected 2"
[ -n "$err" ] || fail "audit path as a regular file: no diagnostic emitted"
echo "ok: an audit path that is not a directory fails the query loudly (exit 2)"

# 8c. An UNREADABLE audit dir must not masquerade as an empty trail either
#     (the script's own fail-closed guard). Skipped under root, where mode
#     000 is still readable — the check-memory-links.sh test's idiom.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$fleet_home/audit"
  rc=0
  err=$(run query 2>&1 >/dev/null) || rc=$?
  chmod 755 "$fleet_home/audit"
  [ "$rc" = 2 ] || fail "unreadable audit dir: query exit $rc, expected 2"
  [ -n "$err" ] || fail "unreadable audit dir: no diagnostic emitted"
  echo "ok: an unreadable audit dir fails the query loudly (exit 2)"
fi

# 9. Caller-held-lock mode (fleet-autonomy Task 9; REQ-G1.3). A mechanism whose
#    state is DERIVED from this trail (the usage-gate ladder) holds the shared
#    advisory lock across its own derive+record critical section and sets
#    PLANWRIGHT_FLEET_LOCK_HELD=1 so record skips the nested acquire that would
#    deadlock on the same non-reentrant primitive. Prove it appends WITHOUT
#    acquiring: hold the lock ourselves, then record with the flag; without the
#    flag the same call would block on the held lock until it stale-breaks.
FS="$here/../scripts/fleet-state.sh"
held_home="$tmp/held-lock-home"
mkdir -p "$held_home"
# Acquire the shared lock as the "caller".
PLANWRIGHT_FLEET_STATE_DIR="$held_home" /bin/bash "$FS" lock >/dev/null 2>&1 \
  || fail "could not acquire the fleet-state lock for the held-lock test"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="$held_home" PLANWRIGHT_FLEET_LOCK_HELD=1 \
  /bin/bash "$FA" record usage-gate defer-heavy "held-lock trigger" "recorded while the caller held the lock" \
  >/dev/null 2>&1 || rc=$?
PLANWRIGHT_FLEET_STATE_DIR="$held_home" /bin/bash "$FS" unlock >/dev/null 2>&1 || true
[ "$rc" = 0 ] || fail "record with PLANWRIGHT_FLEET_LOCK_HELD=1 under a held lock: exit $rc, expected 0"
out=$(PLANWRIGHT_FLEET_STATE_DIR="$held_home" /bin/bash "$FA" query --mechanism usage-gate) \
  || fail "held-lock query failed"
case $out in
  *defer-heavy*) ;;
  *) fail "the held-lock record did not append the row (got: $out)" ;;
esac
echo "ok: record under a caller-held lock (PLANWRIGHT_FLEET_LOCK_HELD=1) appends without a nested acquire"

echo "ALL PASS: fleet-audit"
