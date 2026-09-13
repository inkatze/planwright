#!/bin/bash
# Tests for scripts/tower-queue.sh `report` — the tower-comms scorecard
# (REQ-D1.1, REQ-D1.4, REQ-G1.2, REQ-G1.5, REQ-G1.7).
#
# Contract under test:
#   report [--log <path>] [--now <epoch>] [--window <duration>]
#          [--tick-gap-max <duration>]
#       Read the event log (the live one under the fleet home, or --log)
#       lock-free, keep the lines inside the report window, and print the
#       scorecard as `<measure><TAB><value>` lines: the headline (items that
#       reached the operator per hour of fleet work, against items settled
#       without them, with tick gaps beside it) and the secondary measures.
#   Exit codes: 0 printed; 1 no log to read; 2 usage.
#
# The fixture logs and their hand-computed scorecards live under
# tests/fixtures/tower-comms/ (its README shows the arithmetic).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
TQ="$root/scripts/tower-queue.sh"
FS="$root/scripts/fleet-state.sh"
fixtures="$here/fixtures/tower-comms"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"
[ -f "$root/scripts/tower-jargon.txt" ] || fail "scripts/tower-jargon.txt (the jargon word list) is missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

value_of() {
  # value_of <key> <report-output>
  printf '%s\n' "$2" | awk -F '\t' -v k="$1" '$1 == k { print $2; found = 1 } END { if (!found) exit 1 }'
}

# --- on demand only (REQ-G1.5) --------------------------------------------------

grep -q '^\[tasks."tower:report"\]' "$root/mise.toml" || fail "mise.toml has no tower:report task"
if grep -R -q 'tower:report' "$root/.github/workflows"; then
  fail ".github/workflows references the tower:report task (the scorecard is on demand only)"
fi
/bin/sh "$root/scripts/check-no-ci-evals.sh" >/dev/null 2>&1 || fail "check-no-ci-evals.sh fails with the tower:report task present"
echo "ok: tower:report exists, no workflow references it, check-no-ci-evals passes"

# --- usage ----------------------------------------------------------------------

rc=0
run report --now 1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "report with no log: exit $rc, expected 1"
rc=0
run report --log "$fixtures/baseline.log" --now 0123 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "leading-zero --now: exit $rc, expected 2"
rc=0
run report --log "$fixtures/baseline.log" --now 908000 --window soon >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed --window: exit $rc, expected 2"
rc=0
run report --sideways >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown flag: exit $rc, expected 2"
rc=0
run report --log "$fixtures/baseline.log" --now '' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "empty --now: exit $rc, expected 2 (refused, not silently ignored)"
echo "ok: usage errors and an absent log are refused"

# A clock that will not answer must stop the verb: a window ending at the
# epoch with zero fleet hours reads exactly like a genuinely idle fleet.
stub_bin="$tmp/stub-bin"
mkdir -p "$stub_bin"
printf '#!/bin/sh\nexit 1\n' >"$stub_bin/date"
chmod 0755 "$stub_bin/date"
rc=0
PATH="$stub_bin:$PATH" \
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  PLANWRIGHT_REPO_ROOT="$tmp" \
  PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  /bin/sh "$TQ" report --log "$fixtures/baseline.log" >"$tmp/noclock.out" 2>/dev/null || rc=$?
[ "$rc" = 6 ] || fail "no clock: exit $rc, expected 6"
grep -q 'window_end	0' "$tmp/noclock.out" && fail "no clock: a fabricated scorecard was printed"
echo "ok: an unreadable clock stops report instead of printing an empty window"

# A span the validator accepted must not reach the report as zero: it checks
# the literal, and the conversion rounds to milliseconds.
got=$(run report --log "$fixtures/baseline.log" --now 908000 --window 0.0004s) || fail "sub-millisecond window: exit"
[ "$(value_of window_start "$got")" != 908000 ] \
  || fail "a sub-millisecond window rounded to zero: window_start $(value_of window_start "$got")"
echo "ok: a positive span never arrives at the consumer as zero"

# --- the committed fixtures reproduce their hand-computed numbers ----------------

for name in baseline two-tower gap; do
  case "$name" in
    baseline) now=908000 ;;
    two-tower) now=906000 ;;
    gap) now=905000 ;;
  esac
  got=$(run report --log "$fixtures/$name.log" --now "$now") || fail "$name: report exit"
  if [ "$got" != "$(cat "$fixtures/$name.expected")" ]; then
    printf '%s\n' "--- expected ($name)" >&2
    cat "$fixtures/$name.expected" >&2
    printf '%s\n' "--- got" >&2
    printf '%s\n' "$got" >&2
    fail "$name: the report differs from the hand-computed scorecard"
  fi
  echo "ok: $name fixture reproduces its hand-computed scorecard"
done

# --- the window ---------------------------------------------------------------

got=$(run report --log "$fixtures/baseline.log" --now 908000 --window 2h) || fail "windowed report: exit"
[ "$(value_of window_start "$got")" = 900800 ] || fail "window_start: $(value_of window_start "$got")"
# Lines at or after 900800, plus the live tick that started before the window
# and reaches into it.
[ "$(value_of lines "$got")" = 13 ] || fail "windowed lines: $(value_of lines "$got"), expected 13"
# 900800..903600 clipped (2800 s) + 1800 + 300 + 300 = 5200 s.
[ "$(value_of fleet_hours "$got")" = 1.44 ] || fail "windowed fleet_hours: $(value_of fleet_hours "$got"), expected 1.44"
[ "$(value_of delivered_items "$got")" = 1 ] || fail "windowed delivered_items: $(value_of delivered_items "$got"), expected 1"
[ "$(value_of friction_meaning "$got")" = 0 ] || fail "windowed friction_meaning: expected the pre-window reply excluded"
echo "ok: --window clips the report to the window, ticks included by their span"

printf 'tower_report_window: 2h\n' >"$local_cfg"
got=$(run report --log "$fixtures/baseline.log" --now 908000) || fail "configured window report: exit"
[ "$(value_of window_start "$got")" = 900800 ] || fail "tower_report_window not honoured: $(value_of window_start "$got")"
: >"$local_cfg"
echo "ok: report reads the tower_report_window window"

printf 'tower_tick_gap_max: 2h\n' >"$local_cfg"
got=$(run report --log "$fixtures/gap.log" --now 905000) || fail "configured gap report: exit"
[ "$(value_of tick_gaps "$got")" = 0 ] || fail "tower_tick_gap_max not honoured: gaps $(value_of tick_gaps "$got")"
[ "$(value_of fleet_hours "$got")" = 1.33 ] || fail "bridged hours: $(value_of fleet_hours "$got"), expected 1.33"
: >"$local_cfg"
got=$(run report --log "$fixtures/gap.log" --now 905000 --tick-gap-max 2h) || fail "flag gap report: exit"
[ "$(value_of tick_gaps "$got")" = 0 ] || fail "--tick-gap-max not honoured"
echo "ok: the tick-gap bound comes from tower_tick_gap_max or --tick-gap-max"

# --- resilience -----------------------------------------------------------------

{
  cat "$fixtures/gap.log"
  printf 'this is not a log line\n'
  printf '{"v":1,"seq":9,"ts":904400,"kind":"delivered","tower":"T1","nested":{"a":1}}\n'
  printf '{"v":1,"seq":10,"ts":904500,"kind":"delivered","tower":"T1","item":"z","text":"x\n'
} >"$tmp/dirty.log"
got=$(run report --log "$tmp/dirty.log" --now 905000) || fail "dirty log: exit"
[ "$(value_of malformed "$got")" = 3 ] || fail "malformed count: $(value_of malformed "$got"), expected 3"
[ "$(value_of delivered_items "$got")" = 1 ] || fail "a malformed line leaked into a measure"
echo "ok: malformed lines are counted and skipped, never fatal"

# A relative --log path whose text before the first `=` is an awk identifier
# is an assignment to awk, not a file: the scorecard printed all zeros at exit
# 0 for a log it never opened.
cp "$fixtures/baseline.log" "$tmp/data=x.log"
got=$(cd "$tmp" \
  && PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" report --log "data=x.log" --now 908000 </dev/null) \
  || fail "assignment-shaped --log path: exit"
[ "$(value_of lines "$got")" = 19 ] || fail "assignment-shaped --log path: lines $(value_of lines "$got"), expected 19"
echo "ok: a --log path shaped like an awk assignment is still read as a file"

# The lines `log` dropped at a lock-wait expiry are a measure of their own:
# without them the scorecard is the survivors' and says so nowhere.
mkdir -p "$tmp/drops"
cp "$fixtures/gap.log" "$tmp/drops/events.log"
{
  printf '904900\tborn\n'
  printf '100\tborn\n'
} >"$tmp/drops/events.dropped"
got=$(run report --log "$tmp/drops/events.log" --now 905000) || fail "dropped-count report: exit"
[ "$(value_of dropped_lines "$got")" = 1 ] \
  || fail "dropped_lines: $(value_of dropped_lines "$got"), expected 1 (the one inside the window)"
echo "ok: lines dropped at a lock-wait expiry are counted inside the window"

# A repeated term shares the delimiter between its two occurrences, so a
# counter that consumes the whole padded needle scores the worst offenders
# lowest.
printf '{"v":1,"seq":1,"ts":100,"kind":"delivered","tower":"T","text":"drain drain drain and the sweep sweep","asks":1}\n' >"$tmp/repeat.log"
got=$(run report --log "$tmp/repeat.log" --now 200) || fail "repeat report: exit"
[ "$(value_of jargon_terms "$got")" = 5 ] \
  || fail "jargon_terms over back-to-back repeats: $(value_of jargon_terms "$got"), expected 5"
echo "ok: back-to-back repeats of a listed term each count"

got=$(run report --log "$tmp/empty.log" --now 905000 2>/dev/null) && fail "a missing --log path reported"
: >"$tmp/empty.log"
got=$(run report --log "$tmp/empty.log" --now 905000) || fail "empty log: exit"
[ "$(value_of lines "$got")" = 0 ] || fail "empty log lines: $(value_of lines "$got")"
[ "$(value_of delivered_per_fleet_hour "$got")" = n/a ] || fail "zero-hour headline should be n/a, got $(value_of delivered_per_fleet_hour "$got")"
echo "ok: an empty log reports zeros and an n/a headline"

# --- the live log, read lock-free -----------------------------------------------

run log tick --tower T9 --now 800000 live=1 >/dev/null || fail "seed tick: exit"
run log delivered --tower T9 --now 800100 item=k text='The tests pass' asks=1 >/dev/null || fail "seed delivered: exit"
run log tick --tower T9 --now 800300 live=1 >/dev/null || fail "seed tick 2: exit"
run log tick --tower T9 --now 800500 live=2 >/dev/null || fail "seed tick 3: exit"
run log tick --tower T9 --now 800800 live=2 >/dev/null || fail "seed tick 4 (coalesced): exit"
# 300 s bridge, 200 s bridge, 300 s coalesced span: 800 s.
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock"
got=$(run report --now 804000) || {
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
  fail "report under a held lock: exit"
}
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
[ "$(value_of fleet_hours "$got")" = 0.22 ] || fail "live log fleet_hours: $(value_of fleet_hours "$got"), expected 0.22"
[ "$(value_of tick_gaps "$got")" = 0 ] || fail "live log tick_gaps: $(value_of tick_gaps "$got")"
[ "$(value_of delivered_items "$got")" = 1 ] || fail "live log delivered_items: $(value_of delivered_items "$got")"
echo "ok: report reads the live log under the fleet home without taking the lock"

# The verify-or-refuse gate is the read path's too: a redirected live log
# feeds the scorecard whatever it points at, and a fabricated scorecard at
# exit 0 reads exactly like a real one.
live_log="$home/tower-comms/events.log"
mv "$live_log" "$tmp/elsewhere.log"
ln -s "$tmp/elsewhere.log" "$live_log"
rc=0
run report --now 804000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "symlinked live log: exit $rc, expected 4"
rm -f "$live_log"
mv "$tmp/elsewhere.log" "$live_log"
chmod 0640 "$live_log"
rc=0
run report --now 804000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "loosened live log mode: exit $rc, expected 4"
chmod 0600 "$live_log"
run report --now 804000 >/dev/null || fail "report after the surface was put back: exit"
echo "ok: report refuses a live log that is redirected or not owner-only"

# --- the jargon list is what the count reads ------------------------------------

printf '{"v":1,"seq":1,"ts":100,"kind":"delivered","tower":"T","text":"The Attention Store and the fleet home; a worker; obs:4b14e93a; D-14; tower_report_window","asks":1}\n' >"$tmp/jargon.log"
got=$(run report --log "$tmp/jargon.log" --now 200) || fail "jargon report: exit"
[ "$(value_of jargon_terms "$got")" = 2 ] || fail "jargon_terms: $(value_of jargon_terms "$got"), expected 2 (case-folded phrases)"
[ "$(value_of jargon_identifiers "$got")" = 2 ] || fail "jargon_identifiers: $(value_of jargon_identifiers "$got"), expected 2"
[ "$(value_of jargon_internal "$got")" = 1 ] || fail "jargon_internal: $(value_of jargon_internal "$got"), expected 1"
echo "ok: jargon counts read the shipped list, spec identifiers and internal names"

echo "ALL PASS: tower-queue report"
