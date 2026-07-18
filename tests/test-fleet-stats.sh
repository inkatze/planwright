#!/bin/bash
# Tests for scripts/fleet-stats.sh — the on-demand DERIVED fleet-stats renderer
# and the human-facing audit-trail render (fleet-autonomy Task 8: D-13, D-16,
# REQ-F1.1, REQ-F1.4).
#
# WHAT TASK 8 REQUIRES (tasks.md Task 8 Done-when + test-spec REQ-F1.1/REQ-F1.4):
#   - the stats view reflects REAL activity from a fixture run of Tasks 2, 3, 4,
#     and 7's mechanisms (last-cleanup time from Task 4, watchdog-trip count from
#     Task 3, throttle-engaged state from Task 7), with NO intermediate file
#     written solely for stats (the D-13 no-new-shared-write-file floor);
#   - the audit-trail render is human-facing and queryable by mechanism and time
#     range (REQ-F1.4).
#
# The stats are DERIVED on demand: `last cleanup` and `watchdog trips` are read
# back out of the shared audit trail (scripts/fleet-audit.sh, the exact seam
# Tasks 3/4 write through), and `throttle` is read live from Task 7's throttle
# state (scripts/fleet-throttle.sh check). This test drives the REAL producers —
# fleet-throttle.sh engage for the throttle state and fleet-audit.sh record with
# the byte-identical mechanism/action tokens Tasks 3/4 use — then asserts the
# rendered stats reflect them. Nothing here writes a stats file; the design-level
# no-new-file guard is enforced by snapshotting the fleet home around a render.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-stats.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FS="$here/../scripts/fleet-stats.sh"
FA="$here/../scripts/fleet-audit.sh"
FT="$here/../scripts/fleet-throttle.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FS" ] || fail "scripts/fleet-stats.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-audit.sh missing or not executable"
[ -x "$FT" ] || fail "scripts/fleet-throttle.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fleet_home="$tmp/fleet"

# Every fleet script resolves its cross-spec home from PLANWRIGHT_FLEET_STATE_DIR
# (fleet-state.sh). Pin it so this test never touches a real fleet home.
stats() { PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FS" "$@"; }
audit() { PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" "$@"; }
throttle() { PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FT" "$@"; }

# --- 1. Empty state: render succeeds and reports the derived-nothing baseline.
out=$(stats render) || fail "render on an empty home failed"
case $out in
  *"last cleanup"*never*) ;;
  *) fail "empty render did not report 'last cleanup: never' (got: $out)" ;;
esac
case $out in
  *"watchdog trips"*" 0"*) ;;
  *) fail "empty render did not report zero watchdog trips (got: $out)" ;;
esac
case $out in
  *throttle*idle*) ;;
  *) fail "empty render did not report throttle idle (got: $out)" ;;
esac
echo "ok: an empty fleet home renders the derived-nothing baseline"

# --- 2. Drive Task 3's watchdog activity through the REAL audit seam, using the
#       byte-identical mechanism/action tokens scripts/fleet-tower-watchdog.sh
#       records (relaunch, relaunch-failed, disable are trips; reset-backoff is
#       the healthy tower-alive path, NOT a trip and must not be counted).
audit record tower-watchdog relaunch "tower-dead-ready-work" "cold-started a fresh tower for spec demo" \
  || fail "recording a watchdog relaunch failed"
audit record tower-watchdog relaunch-failed "tower-dead-ready-work" "relaunch attempt failed, backing off" \
  || fail "recording a watchdog relaunch-failed failed"
audit record tower-watchdog reset-backoff "tower-alive" "tower found alive; healthy backoff reset" \
  || fail "recording a watchdog reset-backoff failed"

out=$(stats render)
case $out in
  *"watchdog trips"*" 2"*) ;;
  *) fail "watchdog trips did not count 2 real trips excluding reset-backoff (got: $out)" ;;
esac
echo "ok: watchdog-trip count reflects real relaunch/relaunch-failed activity, excludes healthy reset-backoff"

# --- 3. Drive Task 4's cleanup activity through the REAL audit seam, using the
#       byte-identical tokens scripts/fleet-cleanup.sh records (a reclaim is
#       mechanism window-cleanup/worktree-cleanup, action `cleanup`). The
#       last-cleanup stat is the most recent such row's UTC timestamp.
audit record window-cleanup cleanup "window worker-3 gone" "merged PR #12, idle 40m, death evidence positive" \
  || fail "recording a window cleanup failed"
cleanup_iso=$(audit query --mechanism window-cleanup | awk -F '	' '$4 == "cleanup" { print $2 }' | tail -1)
[ -n "$cleanup_iso" ] || fail "could not read back the recorded cleanup iso"

out=$(stats render)
case $out in
  *"last cleanup"*"$cleanup_iso"*) ;;
  *) fail "last-cleanup stat did not reflect the real reclaim timestamp $cleanup_iso (got: $out)" ;;
esac
echo "ok: last-cleanup time reflects the real reclaim's audit timestamp"

# --- 3b. A later worktree-cleanup reclaim moves last-cleanup forward (most
#         recent across cleanup mechanisms wins).
sleep 1
audit record worktree-cleanup cleanup "worktree gone" "worktree merged and pushed, safe to reclaim" \
  || fail "recording a worktree cleanup failed"
later_iso=$(audit query --mechanism worktree-cleanup | awk -F '	' '$4 == "cleanup" { print $2 }' | tail -1)
out=$(stats render)
case $out in
  *"last cleanup"*"$later_iso"*) ;;
  *) fail "last-cleanup did not advance to the newer reclaim $later_iso (got: $out)" ;;
esac
echo "ok: last-cleanup advances to the most recent reclaim across cleanup mechanisms"

# --- 4. Drive Task 7's throttle state through the REAL producer. engage writes
#       the live throttle state (read back by `check`) AND an audit row.
now=$(date +%s)
until=$((now + 3600))
throttle engage --until "$until" --trigger "rate-limit-prompt-seen" >/dev/null \
  || fail "engaging the throttle failed"
out=$(stats render)
case $out in
  *throttle*engaged*"$until"*) ;;
  *) fail "throttle stat did not reflect the live engaged state until $until (got: $out)" ;;
esac
echo "ok: throttle-engaged state reflects Task 7's live throttle state"

# clearing the throttle returns the stat to idle (live state, not a stale row).
throttle clear >/dev/null || fail "clearing the throttle failed"
out=$(stats render)
case $out in
  *throttle*idle*) ;;
  *) fail "throttle stat did not return to idle after clear (got: $out)" ;;
esac
echo "ok: throttle stat returns to idle after a live clear"

# --- 5. THE NO-NEW-SHARED-WRITE-FILE FLOOR (D-13, REQ-F1.1 design-level).
#        A render must derive on demand and write NOTHING: snapshot the fleet
#        home's file inventory around a render and assert it is byte-identical.
before=$(cd "$fleet_home" && find . -type f | LC_ALL=C sort)
stats render >/dev/null || fail "render (no-write check) failed"
stats line >/dev/null || fail "line (no-write check) failed"
after=$(cd "$fleet_home" && find . -type f | LC_ALL=C sort)
[ "$before" = "$after" ] \
  || fail "a stats render wrote to the fleet home (D-13 no-new-file floor violated):
before:
$before
after:
$after"
echo "ok: rendering derives on demand and writes no stats file (D-13 floor)"

# --- 6. The compact single-line render (for the statusLine surface) carries the
#        same derived stats on one control-free line.
line=$(stats line) || fail "line render failed"
[ "$(printf '%s' "$line" | wc -l | tr -d ' ')" = 0 ] \
  || fail "line render emitted more than a single line"
case $line in
  *trips*2*) ;;
  *) fail "line render missing the trip count (got: $line)" ;;
esac
echo "ok: the compact line render is a single line carrying the derived stats"

# --- 6b. The queue field distinguishes a healthy DEFERRED queue from a read
#         failure. When a backend advertises provides_attention_surface (ambient
#         PLANWRIGHT_ATTENTION_SURFACE_PROVIDED, or --surface-provided), planwright
#         suppresses its own decision queue and fleet-attention's `queue --count`
#         exits 0 with EMPTY stdout — a healthy deferral, not a failure. The line
#         must render `queue deferred`, never the `?` failure token (fleet-autonomy
#         Task 8 tower decision; the durable producer-side fix is tracked as an
#         observation).
deferred_line=$(PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  PLANWRIGHT_ATTENTION_SURFACE_PROVIDED=1 /bin/bash "$FS" line) \
  || fail "line render (deferred queue) failed"
case $deferred_line in
  *"queue deferred"*) ;;
  *) fail "a deferred-to-backend queue did not render 'queue deferred' (got: $deferred_line)" ;;
esac
case $deferred_line in
  *"queue ?"*) fail "a deferred-to-backend queue was mislabeled as the '?' read-failure token (got: $deferred_line)" ;;
esac
echo "ok: a deferred-to-backend queue renders 'deferred', not the '?' failure token"

# --- 6c. `?` stays reserved for a GENUINE read failure. With fleet-attention.sh
#         present but not executable (a broken install), queue_count cannot read a
#         count and must degrade to `?` (never 'deferred', never a wrong number).
qc_stub="$tmp/qc-stub"
mkdir -p "$qc_stub"
for _s in fleet-stats.sh echo-safety.sh fleet-audit.sh fleet-throttle.sh; do
  ln -s "$here/../scripts/$_s" "$qc_stub/$_s"
done
# present but NOT chmod +x -> the [ ! -x "$ATTN" ] failure branch
printf '#!/bin/sh\necho unreachable\n' >"$qc_stub/fleet-attention.sh"
failure_line=$(PLANWRIGHT_FLEET_STATE_DIR="$tmp/qc-fail-home" \
  /bin/bash "$qc_stub/fleet-stats.sh" line 2>/dev/null) \
  || fail "line render (broken-attention install) failed"
case $failure_line in
  *"queue ?"*) ;;
  *) fail "a genuine queue read failure did not degrade to '?' (got: $failure_line)" ;;
esac
case $failure_line in
  *"queue deferred"*) fail "a genuine read failure was mislabeled as the healthy 'deferred' token (got: $failure_line)" ;;
esac
echo "ok: a genuine queue read failure degrades to '?' (reserved for failures, not deferral)"

# --- 7. The human-facing AUDIT render (REQ-F1.4): formatted (not raw TSV) and
#        queryable by mechanism and by --since/--until time range.
rendered=$(stats audit) || fail "audit render failed"
# Human-facing: the mechanism/action appears as `mechanism/action`, not a bare
# tab-separated column, and each row shows its UTC time and reasoning.
case $rendered in
  *tower-watchdog/relaunch*) ;;
  *) fail "audit render is not human-facing (expected 'tower-watchdog/relaunch', got: $rendered)" ;;
esac
case $rendered in
  *window-cleanup/cleanup*) ;;
  *) fail "audit render omitted the cleanup row (got: $rendered)" ;;
esac
echo "ok: the audit render is human-facing (mechanism/action formatting)"

# queryable by mechanism: only tower-watchdog rows.
mech_only=$(stats audit --mechanism tower-watchdog) || fail "audit --mechanism failed"
case $mech_only in
  *window-cleanup*) fail "audit --mechanism tower-watchdog leaked a non-matching mechanism" ;;
esac
case $mech_only in
  *tower-watchdog*) ;;
  *) fail "audit --mechanism tower-watchdog returned nothing" ;;
esac
echo "ok: the audit render filters by mechanism"

# queryable by time range: a --since strictly after every recorded row is empty;
# an all-encompassing range returns rows.
future=$((now + 100000))
empty=$(stats audit --since "$future") || fail "audit --since failed"
[ -z "$empty" ] || fail "audit --since a future epoch should be empty (got: $empty)"
ranged=$(stats audit --since "$((now - 100000))" --until "$future") || fail "audit --since/--until failed"
case $ranged in
  *tower-watchdog*) ;;
  *) fail "audit time-range query returned no rows in an all-encompassing window" ;;
esac
echo "ok: the audit render filters by --since/--until time range (REQ-F1.4)"

# --- 8. Usage errors are refused (exit 2).
rc=0
stats >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no subcommand: exit $rc, expected 2"
rc=0
stats bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown subcommand: exit $rc, expected 2"
echo "ok: usage errors are refused (exit 2)"

echo "PASS: fleet-stats.sh"
