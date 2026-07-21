#!/bin/bash
# Tests for scripts/fleet-usage-gate.sh — the proactive, shared-aware `/usage`
# budget gate and its restriction ladder (fleet-autonomy Task 9; D-23, D-28,
# D-12; REQ-E1.5, REQ-E1.6, REQ-E1.7, REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.3,
# REQ-G1.5).
#
# The gate reads Claude Code's own `/usage` render (fed on stdin here — the
# live throwaway-pane scrape is the version-fragile `[manual]` half, D-23),
# parses BOTH windows (session + weekly) by LABEL, plausibility-checks each,
# caches the signal per-tower with a TTL, and maps each window's percentage to
# a rung on the monotone restriction ladder
# (`normal`→`downshift`→`reduce-concurrency`→`defer-heavy`→`defer-all`). The
# more restrictive window governs; the session window is capped at
# `defer-heavy`; only the weekly window can reach `defer-all`. Each rung
# transition is a throttle-family daemon action — kill-switch-pausable
# (fleet-daemon-gate.sh) and audited (fleet-audit.sh) — and the ladder's live
# state (current rung, last transition) is DERIVED from the shared audit trail,
# not stored, so a memoryless relaunch recovers it and transitions are
# edge-triggered. Comparisons are deterministic; no LLM/API is ever invoked.
#
# What is covered (the REQ-E1.5/E1.6/E1.7 Done-when fixtures):
#   - the parser extracts BOTH window percentages deterministically, by label,
#     with a stubbed `claude`/network asserting zero LLM/API invocations;
#   - only one window rendered -> the missing window reports unavailable while
#     the present one parses;
#   - malformed/empty, out-of-range/implausible, and stale-beyond-TTL signals
#     each report the affected window unavailable (never a fabricated number),
#     and no per-orchestrator reservation state is written;
#   - an escape/control-laced render is stripped before parsing and cannot
#     smuggle a value past the plausibility/shape check;
#   - rising usage selects progressively heavier rungs, the more-restrictive
#     window governs (both directions), the session window never exceeds
#     `defer-heavy` while weekly reaches `defer-all`;
#   - `defer-heavy` withholds heavy/opus units while cheaper units dispatch;
#   - non-monotonic per-window thresholds are rejected;
#   - an unavailable signal does not block (governance falls to the reactive
#     backstop) and sustained unavailability fires the required operator surface;
#   - the per-window threshold and cadence/TTL knobs resolve through the overlay
#     (a machine-local override wins via config-get.sh);
#   - rung transitions log through the audit trail carrying ONLY the extracted
#     percentages and the rung decision (never the raw render), honor the
#     kill-switch, are edge-triggered (no row on an unchanged rung), and the
#     current rung is recovered by a fresh process from the trail alone;
#   - concurrent evaluations serialize under the advisory lock with no duplicate
#     rows.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-usage-gate.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FUG="$here/../scripts/fleet-usage-gate.sh"
FA="$here/../scripts/fleet-audit.sh"
ATTN="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FUG" ] || fail "scripts/fleet-usage-gate.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"

# A stub `claude` binary early on PATH: the gate must NEVER shell out to an LLM
# or the network. If any run invokes it, the marker file appears and the
# no-LLM assertions fail.
stub_bin="$tmp/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/claude" <<EOF
#!/bin/sh
echo invoked >>"$tmp/llm-invoked"
exit 0
EOF
chmod +x "$stub_bin/claude"

# Isolated config layers (the fleet-throttle test shape): the kill-switch
# resolves false unless a step flips it; thresholds and cadence/TTL are pinned
# to known values so the ladder maths are deterministic.
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_usage_read_cadence_seconds: 60
fleet_usage_signal_ttl_seconds: 300
fleet_usage_sustained_loss_count: 3
fleet_usage_session_downshift: 50
fleet_usage_session_reduce_concurrency: 70
fleet_usage_session_defer_heavy: 85
fleet_usage_weekly_downshift: 60
fleet_usage_weekly_reduce_concurrency: 75
fleet_usage_weekly_defer_heavy: 85
fleet_usage_weekly_defer_all: 95
EOF
mlocal_cfg="$repo/.claude/planwright.local.yml"

run() {
  PATH="$stub_bin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FUG" "$@"
}

audit_query() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" query "$@"
}

attn_queue() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$ATTN" queue "$@"
}

reset_state() {
  rm -rf "$fleet_home"
  rm -f "$mlocal_cfg"
  rm -f "$tmp/llm-invoked"
}

# A representative captured /usage render (ANSI already implied; the control
# variant is exercised separately). Labels carry the window name; the percent
# lands on the following line — the by-label, not by-position, contract.
usage_render() {
  # $1 = session percent, $2 = weekly percent
  printf 'Usage\n\nCurrent session\n%s%% used\nResets 3:00pm\n\nCurrent week (all models)\n%s%% used\nResets Monday\n' "$1" "$2"
}

no_llm() {
  [ ! -f "$tmp/llm-invoked" ] || fail "$1: the gate invoked the stub claude/LLM (must be a pure text parse)"
}

# --- 1. Usage errors are refused (exit 2). ---
reset_state
for args in "" "bogus" "admit" "admit not-a-model" "capture --nope"; do
  rc=0
  # shellcheck disable=SC2086
  run $args </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
echo "ok: usage errors exit 2"

# --- 2. The parser extracts BOTH windows deterministically, by label, with no
#        LLM/API invocation. Same input twice -> byte-identical output. ---
reset_state
out1=$(usage_render 52 38 | run capture) || fail "read (both windows) failed"
out2=$(usage_render 52 38 | run capture) || fail "read (repeat) failed"
[ "$out1" = "$out2" ] || fail "read is not deterministic: '$out1' vs '$out2'"
case $out1 in
  *session*52*) ;;
  *) fail "read did not extract the session window (got: $out1)" ;;
esac
case $out1 in
  *weekly*38*) ;;
  *) fail "read did not extract the weekly window (got: $out1)" ;;
esac
no_llm "read"
echo "ok: parser extracts both windows deterministically, by label, with no LLM call"

# --- 3. Only one window rendered: the missing one is unavailable, the present
#        one parses. ---
reset_state
only_session=$(printf 'Current session\n61%% used\nResets 4pm\n' | run capture) \
  || fail "read (session only) failed"
case $only_session in
  *session*61*) ;;
  *) fail "session-only render lost the session window (got: $only_session)" ;;
esac
case $only_session in
  *weekly*unavailable*) ;;
  *) fail "session-only render should mark weekly unavailable (got: $only_session)" ;;
esac
echo "ok: a single-window render reports the missing window unavailable"

# --- 4. Malformed/empty and out-of-range/implausible values report the window
#        unavailable — never a fabricated number. ---
reset_state
empty_out=$(printf 'nothing to see here\n' | run capture) || fail "read (empty) failed"
case $empty_out in
  *session*unavailable*weekly*unavailable* | *weekly*unavailable*session*unavailable*) ;;
  *) fail "malformed render should mark both windows unavailable (got: $empty_out)" ;;
esac
impl_out=$(usage_render 250 38 | run capture) || fail "read (implausible) failed"
case $impl_out in
  *session*unavailable*) ;;
  *) fail "an out-of-range session percent (250) must be unavailable, not acted on (got: $impl_out)" ;;
esac
case $impl_out in
  *weekly*38*) ;;
  *) fail "the plausible weekly window should still parse alongside an implausible session (got: $impl_out)" ;;
esac
# No per-orchestrator reservation/accounting state is ever written.
[ ! -e "$fleet_home/usage/reservation" ] || fail "the gate wrote per-orchestrator reservation state (forbidden by REQ-E1.5)"
echo "ok: malformed and implausible values report unavailable, no reservation state written"

# --- 5. An escape/control-laced render is stripped before parsing and cannot
#        smuggle a value past the plausibility/shape check. ---
reset_state
esc=$(printf '\033[31m')
laced=$(printf 'Current session\n%s999%% used\nResets 4pm\n\nCurrent week\n%s41%% used\n' "$esc" "$esc")
laced_out=$(printf '%s' "$laced" | run capture 2>/dev/null) || fail "read (escape-laced) failed"
# The escape bytes must not reach stdout.
case $laced_out in
  *$'\033'*) fail "an escape byte survived into the parsed output (got: $laced_out)" ;;
esac
# 999% is implausible -> session unavailable (the smuggled value is refused).
case $laced_out in
  *session*unavailable*) ;;
  *) fail "the escape-laced implausible session value must be refused (got: $laced_out)" ;;
esac
echo "ok: control/escape bytes are stripped and cannot smuggle a value past the shape check"

# --- 6. A cached signal older than its TTL is treated as unavailable. The gate
#        then does not block: it reports unavailable and defers to the backstop. ---
reset_state
usage_render 52 38 | run capture >/dev/null || fail "read (for TTL test) failed"
# Backdate the cache read epoch well past the 300s TTL.
signal_file="$fleet_home/usage/signal"
[ -f "$signal_file" ] || fail "read did not write the signal cache at $signal_file"
stale_epoch=$(($(date +%s) - 100000))
{
  echo "$stale_epoch"
  tail -n +2 "$signal_file"
} >"$signal_file.new"
mv "$signal_file.new" "$signal_file"
rc=0
stale_out=$(run evaluate 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "evaluate over a stale cache must not block (exit $rc, expected 0)"
case $stale_out in
  *unavailable*) ;;
  *) fail "a stale-beyond-TTL cache should evaluate unavailable (got: $stale_out)" ;;
esac
# No rung transition was recorded off a stale (unavailable) signal.
rows=$(audit_query --mechanism usage-gate 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = 0 ] || fail "a stale/unavailable signal must not record a rung transition (found $rows rows)"
echo "ok: a cache older than its TTL is unavailable and does not block or transition"

# --- 7. Rising usage selects progressively heavier rungs (weekly window, both
#        windows below their higher rungs so weekly governs cleanly). ---
reset_state
rung_of() {
  # Feed session=$1 weekly=$2, evaluate, print the resulting rung token.
  usage_render "$1" "$2" | run capture >/dev/null || fail "read failed for $1/$2"
  ro=$(run evaluate) || fail "evaluate failed for $1/$2"
  # evaluate prints `rung<TAB><name>...`; extract the rung name field.
  printf '%s\n' "$ro" | awk -F'\t' '/^rung/{print $2; exit}'
}
# session held low (10) so weekly governs; weekly thresholds 60/75/85/95.
reset_state
[ "$(rung_of 10 10)" = normal ] || fail "weekly 10% should be normal"
reset_state
[ "$(rung_of 10 65)" = downshift ] || fail "weekly 65% should be downshift"
reset_state
[ "$(rung_of 10 78)" = reduce-concurrency ] || fail "weekly 78% should be reduce-concurrency"
reset_state
[ "$(rung_of 10 88)" = defer-heavy ] || fail "weekly 88% should be defer-heavy"
reset_state
[ "$(rung_of 10 97)" = defer-all ] || fail "weekly 97% should be defer-all"
echo "ok: rising weekly usage selects progressively heavier rungs"

# --- 8. The more restrictive window governs, both directions. ---
reset_state
# session high (88 -> defer-heavy), weekly low (10 -> normal): session governs.
[ "$(rung_of 88 10)" = defer-heavy ] || fail "session-above should govern (expected defer-heavy)"
reset_state
# session low (10 -> normal), weekly high (97 -> defer-all): weekly governs.
[ "$(rung_of 10 97)" = defer-all ] || fail "weekly-above should govern (expected defer-all)"
echo "ok: the more restrictive window governs in both directions"

# --- 9. The session window is capped at defer-heavy; only weekly reaches
#        defer-all. ---
reset_state
# session at 99 (well past any threshold) with weekly normal: capped at
# defer-heavy, never defer-all.
[ "$(rung_of 99 10)" = defer-heavy ] || fail "the session window must cap at defer-heavy even at 99% (got $(rung_of 99 10))"
echo "ok: the session window caps at defer-heavy; only weekly can reach defer-all"

# --- 10. defer-heavy withholds heavy/opus units while cheaper units dispatch. ---
reset_state
usage_render 10 88 | run capture >/dev/null || fail "read (defer-heavy) failed"
run evaluate >/dev/null || fail "evaluate (defer-heavy) failed"
[ "$(run rung)" = defer-heavy ] || fail "expected defer-heavy rung"
rc=0
run admit opus >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "defer-heavy must withhold an opus (heavy) unit (admit exit $rc, expected 1)"
rc=0
run admit sonnet >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "defer-heavy must still admit a sonnet (cheap) unit (admit exit $rc, expected 0)"
# defer-all withholds everything.
reset_state
usage_render 10 97 | run capture >/dev/null || fail "read (defer-all) failed"
run evaluate >/dev/null || fail "evaluate (defer-all) failed"
rc=0
run admit sonnet >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "defer-all must withhold even a cheap unit (admit exit $rc, expected 1)"
echo "ok: defer-heavy withholds heavy units while admitting cheap ones; defer-all withholds all"

# --- 11. Non-monotonic per-window thresholds are rejected. ---
reset_state
cat >"$mlocal_cfg" <<'EOF'
fleet_usage_weekly_reduce_concurrency: 50
fleet_usage_weekly_downshift: 60
EOF
usage_render 10 40 | run capture >/dev/null || fail "read (non-monotonic setup) failed"
rc=0
run evaluate >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "non-monotonic weekly thresholds (reduce 50 < downshift 60) must be rejected"
rm -f "$mlocal_cfg"
echo "ok: non-monotonic per-window thresholds are rejected"

# --- 12. A machine-local threshold override wins (four-layer overlay). ---
reset_state
cat >"$mlocal_cfg" <<'EOF'
fleet_usage_weekly_downshift: 20
EOF
# weekly 25% would be normal under the core default (60) but downshift under
# the machine-local override (20).
[ "$(rung_of 10 25)" = downshift ] || fail "a machine-local weekly_downshift override (20) should win (expected downshift at 25%)"
rm -f "$mlocal_cfg"
echo "ok: a machine-local threshold override wins via config-get.sh"

# --- 13. Rung transitions are edge-triggered and derived from the audit trail;
#         a fresh process recovers the rung; only the percentages + decision are
#         recorded (never the raw render). ---
reset_state
usage_render 10 65 | run capture >/dev/null || fail "read (edge 1) failed"
run evaluate >/dev/null || fail "evaluate (edge 1) failed"
# A second identical evaluate must NOT add a row (edge-triggered).
run evaluate >/dev/null || fail "evaluate (edge 2) failed"
rows=$(audit_query --mechanism usage-gate 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = 1 ] || fail "an unchanged rung must not add a row (expected 1 transition row, found $rows)"
# A FRESH process (no in-memory state) recovers the current rung from the trail.
[ "$(run rung)" = downshift ] || fail "a fresh process should derive downshift from the audit trail"
# The audit row carries only the percentages + rung decision, never the render.
row=$(audit_query --mechanism usage-gate 2>/dev/null)
case $row in
  *Resets* | *"Current week"* | *"used"*) fail "the audit row leaked raw /usage render text: $row" ;;
esac
case $row in
  *65*) ;;
  *) fail "the audit row should carry the extracted weekly percentage (got: $row)" ;;
esac
case $row in
  *downshift*) ;;
  *) fail "the audit row should carry the rung decision (got: $row)" ;;
esac
# Climbing to a heavier rung adds exactly one more row.
usage_render 10 88 | run capture >/dev/null || fail "read (edge climb) failed"
run evaluate >/dev/null || fail "evaluate (edge climb) failed"
rows=$(audit_query --mechanism usage-gate 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = 2 ] || fail "a real rung change should add exactly one row (expected 2 total, found $rows)"
echo "ok: transitions are edge-triggered, derived from the trail, and hygienic"

# --- 14. An unavailable signal fires the required operator surface only after
#         sustained loss (the configured consecutive-cadence count = 3). ---
reset_state
# First two unavailable evaluations warn but do NOT park.
printf 'garbage\n' | run capture >/dev/null || fail "read (unavail 1) failed"
run evaluate >/dev/null 2>&1 || fail "evaluate (unavail 1) should not block"
printf 'garbage\n' | run capture >/dev/null || fail "read (unavail 2) failed"
run evaluate >/dev/null 2>&1 || fail "evaluate (unavail 2) should not block"
q=$(attn_queue --count 2>/dev/null || echo 0)
[ "${q:-0}" = 0 ] || fail "the operator surface must not fire before the sustained-loss count (queue=$q)"
# The third consecutive unavailable trips the required Awaiting-input hold.
printf 'garbage\n' | run capture >/dev/null || fail "read (unavail 3) failed"
run evaluate >/dev/null 2>&1 || fail "evaluate (unavail 3) should not block"
q=$(attn_queue --count 2>/dev/null || echo 0)
[ "${q:-0}" -ge 1 ] || fail "sustained unavailability must fire the Awaiting-input hold (queue=$q)"
echo "ok: sustained unavailability fires the required operator surface, not before"

# --- 15. The kill-switch pauses the gate: no transition is recorded while set. ---
reset_state
cat >"$mlocal_cfg" <<'EOF'
fleet_daemon_pause: true
EOF
usage_render 10 88 | run capture >/dev/null || fail "read (kill-switch) failed"
rc=0
run evaluate >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "evaluate under the kill-switch should short-circuit (exit $rc, expected 1)"
rows=$(audit_query --mechanism usage-gate 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = 0 ] || fail "the kill-switch must prevent any rung transition (found $rows rows)"
rm -f "$mlocal_cfg"
echo "ok: the kill-switch pauses the gate — no transition recorded"

# --- 16. Concurrent evaluations serialize under the advisory lock: a single
#         real transition, no duplicate rows, and EVERY concurrent evaluate exits
#         cleanly (the winner records, the losers no-op — a non-zero exit would
#         mean a lock-acquisition or contention bug, not just an extra row). ---
reset_state
usage_render 10 88 | run capture >/dev/null || fail "read (concurrency) failed"
pids=""
for _i in 1 2 3 4 5; do
  run evaluate >/dev/null 2>&1 &
  pids="$pids $!"
done
conc_rc=0
for p in $pids; do wait "$p" || conc_rc=1; done
[ "$conc_rc" = 0 ] || fail "a concurrent evaluate exited non-zero — contention handling bug (winner should record, losers no-op, all exit 0)"
rows=$(audit_query --mechanism usage-gate 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = 1 ] || fail "concurrent evaluations must yield exactly one transition row (found $rows)"
echo "ok: concurrent evaluations serialize under the advisory lock (one row, all exit 0)"

# --- 17. The TTL knob resolves through the overlay: a machine-local TTL makes
#         an otherwise-fresh signal stale (so it evaluates unavailable). ---
reset_state
cat >"$mlocal_cfg" <<'EOF'
fleet_usage_read_cadence_seconds: 1
fleet_usage_signal_ttl_seconds: 2
EOF
usage_render 10 88 | run capture >/dev/null || fail "capture (ttl override) failed"
# Age the cache to 5s: past the 2s machine-local TTL, within the 300s core TTL.
signal_file="$fleet_home/usage/signal"
aged_epoch=$(($(date +%s) - 5))
{
  echo "$aged_epoch"
  tail -n +2 "$signal_file"
} >"$signal_file.new"
mv "$signal_file.new" "$signal_file"
ttl_out=$(run evaluate 2>/dev/null) || fail "evaluate (ttl override) should not block"
case $ttl_out in
  *unavailable*) ;;
  *) fail "a machine-local TTL override (2s) should render a 5s-old signal unavailable (got: $ttl_out)" ;;
esac
rm -f "$mlocal_cfg"
echo "ok: the TTL knob resolves through the overlay (a machine-local TTL wins)"

# --- 18. A cadence at or above the TTL is a rejected config bug (validated). ---
reset_state
cat >"$mlocal_cfg" <<'EOF'
fleet_usage_read_cadence_seconds: 900
fleet_usage_signal_ttl_seconds: 300
EOF
usage_render 10 88 | run capture >/dev/null || fail "capture (cadence>=ttl) failed"
rc=0
run evaluate >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "a cadence (900) >= the TTL (300) must be rejected as a config bug (exit $rc, expected 4)"
rm -f "$mlocal_cfg"
echo "ok: a read cadence at or above the TTL is rejected"

# --- 19. A percentage never bleeds across windows: a label with no percentage
#         of its own must not adopt the next window's number (by-label, not
#         by-position). ---
reset_state
bleed=$(printf 'Current session\n(quota resets 3pm)\nWeekly usage\n78%% used\n' | run capture) \
  || fail "capture (bleed) failed"
case $bleed in
  *session*unavailable*) ;;
  *) fail "a session label with no percentage must be unavailable, not the weekly value (got: $bleed)" ;;
esac
case $bleed in
  *weekly*78*) ;;
  *) fail "the weekly window should still parse its own 78 (got: $bleed)" ;;
esac
echo "ok: a percentage does not bleed from one window into the other"

# --- 20. The reset time is captured where the render shows it, and defaults to
#         '-' where absent (REQ-E1.5 / the Task 9 deliverable). ---
reset_state
withreset=$(usage_render 52 38 | run capture) || fail "capture (reset) failed"
case $withreset in
  *session*52*[Rr]esets*3:00pm*) ;;
  *) fail "the session reset time was not captured (got: $withreset)" ;;
esac
noreset=$(printf 'Current session\n52%% used\n' | run capture) || fail "capture (no reset) failed"
sline=$(printf '%s\n' "$noreset" | awk -F'\t' '$1=="session"{print $3}')
[ "$sline" = "-" ] || fail "a window with no reset time shown should record '-' (got: '$sline')"
echo "ok: the reset time is captured where shown and defaults to '-' where absent"

# --- 21. A future-dated cache (backward clock step / corrupt future epoch) is
#         treated as unavailable, not as fresh-forever. ---
reset_state
usage_render 10 88 | run capture >/dev/null || fail "capture (future) failed"
signal_file="$fleet_home/usage/signal"
future_epoch=$(($(date +%s) + 100000))
{
  echo "$future_epoch"
  tail -n +2 "$signal_file"
} >"$signal_file.new"
mv "$signal_file.new" "$signal_file"
fut_out=$(run evaluate 2>/dev/null) || fail "evaluate (future cache) should not block"
case $fut_out in
  *unavailable*) ;;
  *) fail "a future-dated cache should evaluate unavailable, not fresh-forever (got: $fut_out)" ;;
esac
rows=$(audit_query --mechanism usage-gate 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = 0 ] || fail "a future-dated (unavailable) cache must not record a rung transition (found $rows)"
echo "ok: a future-dated cache is treated as unavailable, not fresh"

# --- 22. The last-transition timestamp is derived from the audit trail and
#         surfaced by evaluate; a fresh process recovers it (D-28, Task 10 input). ---
reset_state
usage_render 10 88 | run capture >/dev/null || fail "capture (since) failed"
ev=$(run evaluate) || fail "evaluate (since) failed"
since=$(printf '%s\n' "$ev" | awk -F'\t' '/^rung/{for(i=1;i<=NF;i++) if($i=="since"){print $(i+1); exit}}')
case $since in
  "" | *[!0-9]*) fail "evaluate did not surface a numeric last-transition epoch (got: '$since')" ;;
esac
# It must equal the audit row's own epoch (field 1) — derived, not invented.
row_epoch=$(audit_query --mechanism usage-gate 2>/dev/null | awk -F'\t' 'END{print $1}')
[ "$since" = "$row_epoch" ] || fail "the surfaced since-epoch ($since) must equal the audit row epoch ($row_epoch)"
echo "ok: the last-transition timestamp is derived from the trail and recovered by a fresh process"

# --- 23. A corrupt/unknown last action fails loud rather than silently
#         collapsing to 'normal' (which would drop the fleet to unrestricted). ---
reset_state
# Seed a real transition, then append a row whose action is a garbled rung token.
usage_render 10 88 | run capture >/dev/null || fail "capture (corrupt) failed"
run evaluate >/dev/null || fail "evaluate (corrupt seed) failed"
PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" record usage-gate defer-hea \
  "garbled" "a truncated rung token" >/dev/null || fail "seeding a corrupt row failed"
rc=0
run rung >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "an unrecognized last action must fail loud, not derive a silent 'normal' (exit $rc, expected 2)"
echo "ok: a corrupt last action fails loud instead of collapsing to 'normal'"

# --- 24. Backstop composition (REQ-E1.7): when the gate signal is unavailable,
#         the reactive throttle remains the load-bearing floor — the gate does
#         not block, and an engaged reactive throttle still governs dispatch. ---
reset_state
THROTTLE="$here/../scripts/fleet-throttle.sh"
throttle() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" /bin/bash "$THROTTLE" "$@"
}
printf 'garbage\n' | run capture >/dev/null || fail "capture (composition) failed"
run evaluate >/dev/null 2>&1 || fail "evaluate must not block on an unavailable signal (backstop composes)"
# The gate abstained (no rung transition); now the reactive throttle engages and
# is the governing floor.
until_epoch=$(($(date +%s) + 3600))
throttle engage --until "$until_epoch" --trigger "rate-limit prompt" >/dev/null 2>&1 \
  || fail "engaging the reactive throttle failed"
rc=0
throttle check >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "with the gate signal unavailable, the reactive backstop must still govern (throttle check exit $rc, expected 1)"
echo "ok: the reactive backstop is load-bearing when the proactive signal is unavailable"

# --- 25. The first PLAUSIBLE percentage in a section wins: a garbled/implausible
#         leading token is skipped, not locked in (so it does not falsely mark a
#         window unavailable). A section whose ONLY value is implausible still
#         yields unavailable. ---
reset_state
skip=$(printf 'Current session\n[bar 999%%]\n52%% used\nResets 3pm\n\nCurrent week\n38%% used\n' | run capture) \
  || fail "capture (implausible-leading) failed"
case $skip in
  *session*52*) ;;
  *) fail "an implausible leading token (999%) should be skipped for the real 52% (got: $skip)" ;;
esac
# But a section whose only percentage is implausible stays unavailable.
onlybad=$(printf 'Current session\n250%% used\nCurrent week\n38%% used\n' | run capture) \
  || fail "capture (implausible-only) failed"
case $onlybad in
  *session*unavailable*) ;;
  *) fail "a section whose only value is implausible must be unavailable (got: $onlybad)" ;;
esac
echo "ok: the first plausible percentage wins; an implausible-only section is unavailable"

echo "ALL fleet-usage-gate tests passed"
