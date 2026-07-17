#!/bin/bash
# Tests for scripts/fleet-throttle.sh — reactive fleet-wide dispatch
# throttling off Claude Code's native rate-limit signal (fleet-autonomy
# Task 7; D-12, REQ-E1.3; kickoff risk rows 9, 23, 24, 30).
#
# No supported machine-readable way exists to query Claude Code's own
# account-level usage, so throttling is REACTIVE: detect the native
# rate-limit prompt/retry text a session renders, parse the signaled reset
# time, pause fleet-wide dispatch until it, and resume at it (D-12 — the
# amux precedent). The throttle flag lives under the cross-spec fleet home,
# writes serialize through fleet-state.sh's advisory lock (risk 8's floor),
# engagement is a daemon action (kill-switch-gated, audit-logged — risk 30),
# and captured text is control-free-sanitized before parse or re-display
# (risk 23).
#
# What is covered (the REQ-E1.3 fixture plus the risk-row mitigations):
#   - a simulated native rate-limit prompt pauses fleet-wide dispatch
#     (`check` exits 1, throttled) and dispatch RESUMES at the signaled reset
#     time with no dispatch allowed in between;
#   - `observe` parses relative ("try again in N minutes") and wall-clock
#     ("resets 3am") reset forms; non-signal text is a clean no-op (exit 3);
#   - conflicting observations resolve to the MAX of the observed reset
#     times, never last-write-wins (risk 9);
#   - a signal with an unparseable reset time degrades to a bounded default
#     hold with a warning — never an indefinite pause, never an immediate
#     resume, never an opaque halt (risk 24);
#   - captured text is sanitized: an escape-bearing prompt still parses and
#     no control byte reaches stderr/stdout or the audit trail (risk 23);
#   - engagement short-circuits when the operator kill-switch is set (the
#     Task 1 daemon-gate contract);
#   - every engagement/clear logs through the shared audit trail (risk 30);
#   - `clear` resumes dispatch immediately (the operator path);
#   - usage errors are refused (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-throttle.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FT="$here/../scripts/fleet-throttle.sh"
FA="$here/../scripts/fleet-audit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FT" ] || fail "scripts/fleet-throttle.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"

# Isolated config layers: the kill-switch resolves false unless a step flips
# it, and the default-hold knob is pinned small so degrade tests are fast.
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_throttle_default_hold: 120
EOF
mlocal_cfg="$repo/.claude/planwright.local.yml"

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FT" "$@"
}

audit_query() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" query "$@"
}

reset_state() {
  rm -rf "$fleet_home"
  rm -f "$mlocal_cfg"
}

now() { date +%s; }

# 1. Usage errors are refused.
reset_state
for args in "" "bogus" "engage" "engage --until" "engage --until notanumber"; do
  rc=0
  # shellcheck disable=SC2086
  run $args </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
echo "ok: usage errors exit 2"

# 2. No throttle state: check allows dispatch (exit 0, silent).
reset_state
rc=0
out=$(run check) || rc=$?
[ "$rc" = 0 ] || fail "check with no state: exit $rc, expected 0"
[ -z "$out" ] || fail "check with no state: unexpected stdout '$out'"
echo "ok: no throttle state allows dispatch"

# 3. The REQ-E1.3 fixture: a simulated native rate-limit prompt pauses
#    fleet-wide dispatch, and dispatch resumes at the signaled reset time
#    with no dispatch allowed in between. Uses a near-future reset (now+3s)
#    via the relative form so the fixture is deterministic.
reset_state
started=$(now)
printf "5-hour limit reached %s try again in 3 seconds\n" "$(printf '\342\210\231')" \
  | run observe >/dev/null 2>&1 || fail "observe (relative form) failed"
resumed=""
allowed_early=0
while :; do
  t=$(now)
  rc=0
  run check >/dev/null || rc=$?
  if [ "$rc" = 0 ]; then
    resumed=$t
    break
  fi
  [ "$rc" = 1 ] || fail "check while throttled: exit $rc, expected 1"
  # Paused while the reset time is still in the future: expected. A pause
  # observed AFTER started+3 has not resumed yet — tolerate scheduling up to
  # a bound, then fail.
  [ $((t - started)) -le 15 ] || fail "dispatch did not resume within 15s of a 3s reset"
  sleep 0.3
done
[ $((resumed - started)) -ge 2 ] || allowed_early=1
[ "$allowed_early" = 0 ] || fail "dispatch resumed ${resumed}s vs start ${started}s — before the signaled reset"
echo "ok: rate-limit signal pauses dispatch and resumes at the signaled reset time"

# 4. While throttled, check prints the until-epoch so a tower can render it.
reset_state
until_epoch=$(($(now) + 3600))
run engage --until "$until_epoch" --trigger "test engagement" >/dev/null 2>&1 \
  || fail "engage --until failed"
rc=0
out=$(run check) || rc=$?
[ "$rc" = 1 ] || fail "check while engaged: exit $rc, expected 1"
case $out in
  *"$until_epoch"*) ;;
  *) fail "check while engaged: stdout should carry the until-epoch, got '$out'" ;;
esac
echo "ok: a throttled check reports the reset time"

# 5. Risk 9: conflicting reset observations resolve to the MAX, never
#    last-write-wins. An earlier reset must not shorten the pause; a later
#    one extends it.
reset_state
t1=$(($(now) + 3600))
t0=$(($(now) + 60))
t2=$(($(now) + 7200))
run engage --until "$t1" --trigger "tower A" >/dev/null 2>&1 || fail "engage t1 failed"
run engage --until "$t0" --trigger "tower B earlier" >/dev/null 2>&1 || fail "engage t0 failed"
out=$(run check) && fail "check should still be throttled" || true
case $out in
  *"$t1"*) ;;
  *) fail "an earlier observation must not shorten the pause (expected until=$t1, got '$out')" ;;
esac
run engage --until "$t2" --trigger "tower C later" >/dev/null 2>&1 || fail "engage t2 failed"
out=$(run check) && fail "check should still be throttled after extension" || true
case $out in
  *"$t2"*) ;;
  *) fail "a later observation must extend the pause (expected until=$t2, got '$out')" ;;
esac
echo "ok: conflicting reset times resolve to the max (risk 9)"

# 6. Wall-clock reset forms parse to the NEXT local occurrence (a future
#    epoch within 24h). "resets 3am" cannot be asserted against a fixed
#    epoch, so assert the parsed until is in (now, now+86400].
reset_state
printf 'You have reached your usage limit. Your limit resets 3am.\n' \
  | run observe >/dev/null 2>&1 || fail "observe (wall-clock form) failed"
out=$(run check) && fail "wall-clock observe should throttle" || true
until_parsed=$(printf '%s\n' "$out" | tr -d -c '0-9')
t=$(now)
[ -n "$until_parsed" ] || fail "wall-clock observe: no until-epoch in '$out'"
[ "$until_parsed" -gt "$t" ] || fail "wall-clock observe: until $until_parsed not in the future"
[ "$until_parsed" -le $((t + 86400)) ] || fail "wall-clock observe: until $until_parsed more than 24h out"
echo "ok: a wall-clock reset parses to the next occurrence"

# 7. Non-signal text is a clean no-op: exit 3, no state written, dispatch
#    stays allowed.
reset_state
rc=0
printf 'Compiling module foo... done in 3 seconds\n' | run observe >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "observe on non-signal text: exit $rc, expected 3"
run check >/dev/null || fail "non-signal observe must not throttle"
echo "ok: non-signal text is a clean no-op (exit 3)"

# 8. Risk 24: a rate-limit signal with an unparseable reset time degrades to
#    the bounded default hold (fleet_throttle_default_hold, pinned 120s) with
#    a warning — never indefinite, never immediate resume.
reset_state
rc=0
err=$(printf 'Rate limit reached. Please slow down.\n' | run observe 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "degrade observe: exit $rc, expected 0"
case $err in
  *arn*) ;; # "warning" / "Warning"
  *) fail "degrade observe: expected a warning on stderr, got '$err'" ;;
esac
out=$(run check) && fail "degrade observe should throttle" || true
until_parsed=$(printf '%s\n' "$out" | tr -d -c '0-9')
t=$(now)
[ "$until_parsed" -gt "$t" ] || fail "degrade hold not in the future"
[ "$until_parsed" -le $((t + 130)) ] || fail "degrade hold exceeds the configured default (until $until_parsed, now $t)"
echo "ok: an unparseable reset time degrades to the bounded default hold (risk 24)"

# 9. Risk 23: captured text is control-free-sanitized — an escape-bearing
#    prompt still parses, and no raw control byte reaches stdout, stderr, or
#    the audit trail.
reset_state
esc=$(printf '\033')
rc=0
all_out=$(printf 'usage limit reached%s[2J try again in 1800 seconds\n' "$esc" | run observe 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "sanitize observe: exit $rc, expected 0"
case $all_out in
  *"$esc"*) fail "sanitize observe: a raw escape byte reached the output" ;;
esac
out=$(run check) && fail "sanitize observe should throttle" || true
audit_rows=$(audit_query --mechanism throttle)
case $audit_rows in
  *"$esc"*) fail "sanitize observe: a raw escape byte reached the audit trail" ;;
esac
echo "ok: captured text is sanitized before parse, display, and audit (risk 23)"

# 10. Risk 30: engagements and clears log through the shared audit trail.
reset_state
run engage --until "$(($(now) + 900))" --trigger "audit fixture" >/dev/null 2>&1 \
  || fail "engage for audit fixture failed"
rows=$(audit_query --mechanism throttle)
case $rows in
  *throttle*engage*"audit fixture"*) ;;
  *) fail "engage did not log through the audit trail (got: '$rows')" ;;
esac
run clear --trigger "operator resume" >/dev/null 2>&1 || fail "clear failed"
rows=$(audit_query --mechanism throttle)
case $rows in
  *throttle*clear*"operator resume"*) ;;
  *) fail "clear did not log through the audit trail (got: '$rows')" ;;
esac
run check >/dev/null || fail "clear must resume dispatch"
echo "ok: engage and clear log through the audit trail (risk 30); clear resumes dispatch"

# 11. The daemon-gate contract: with the operator kill-switch set, engagement
#     short-circuits (exit 1) and writes no throttle state; check remains a
#     read (allowed, since nothing engaged).
reset_state
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rc=0
run engage --until "$(($(now) + 900))" --trigger "gated" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "gated engage: exit $rc, expected 1 (kill-switch short-circuit)"
rm -f "$mlocal_cfg"
run check >/dev/null || fail "gated engage must not have written throttle state"
echo "ok: the operator kill-switch short-circuits engagement"

# 12. A past --until is a caller bug: refused (exit 2), no state written.
reset_state
rc=0
run engage --until 1000 --trigger "stale" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "past --until: exit $rc, expected 2"
run check >/dev/null || fail "past --until must not throttle"
echo "ok: a past --until is refused"

# 13. An absurdly-far --until (beyond the 8-day sanity ceiling) is refused
#     rather than engaged: a garbage reset time must never park the fleet
#     indefinitely (risk 24's other arm).
reset_state
rc=0
run engage --until "$(($(now) + 3000000))" --trigger "garbage" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "far-future --until: exit $rc, expected 2"
run check >/dev/null || fail "far-future --until must not throttle"
echo "ok: a beyond-ceiling --until is refused"

# 14. Risk 24's other arm on the SHARED path: the 8-day ceiling must bind
#     engage_until itself, not just the engage CLI's argument check — a
#     misconfigured default hold (valid posint, absurd magnitude) must not
#     park the fleet past the ceiling via the observe degrade path.
reset_state
printf 'fleet_throttle_default_hold: 99999999\n' >"$mlocal_cfg"
printf 'Rate limit reached. Please slow down.\n' | run observe >/dev/null 2>&1 \
  || fail "huge-hold degrade observe failed"
rm -f "$mlocal_cfg"
out=$(run check) && fail "huge-hold degrade should throttle" || true
until_parsed=$(printf '%s\n' "$out" | tr -d -c '0-9')
t=$(now)
[ "$until_parsed" -le $((t + 691200 + 60)) ] \
  || fail "the ceiling must bind the shared engage path (until $until_parsed vs now $t + 8d)"
echo "ok: the 8-day ceiling binds the shared engage path (risk 24)"

# 15. An over-long --until value is refused by the digit cap (the
#     shell-arithmetic overflow guard fleet-audit already carries), with a
#     diagnostic naming the cap — never fed to arithmetic comparison.
reset_state
rc=0
err=$(run engage --until 99999999999999999999 --trigger overflow 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "20-digit --until: exit $rc, expected 2"
case $err in
  *digit*) ;;
  *) fail "20-digit --until: diagnostic should name the digit cap, got '$err'" ;;
esac
run check >/dev/null || fail "20-digit --until must not throttle"
echo "ok: an over-long --until is refused by the digit cap"

# 16. Multi-unit relative resets sum ("in 2 hours 30 minutes" is 9000s, not
#     7200s): an under-hold resumes dispatch before the account limit
#     clears — the direction the max rule exists to prevent.
reset_state
started=$(now)
printf 'rate limit reached, try again in 2 hours 30 minutes\n' | run observe >/dev/null 2>&1 \
  || fail "multi-unit relative observe failed"
out=$(run check) && fail "multi-unit relative observe should throttle" || true
until_parsed=$(printf '%s\n' "$out" | tr -d -c '0-9')
delta=$((until_parsed - started))
[ "$delta" -ge 8990 ] && [ "$delta" -le 9070 ] \
  || fail "multi-unit relative reset: expected ~9000s hold, got ${delta}s"
echo "ok: multi-unit relative resets sum to the full hold"

echo "ALL PASS: fleet-throttle"
