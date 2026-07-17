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
  # observed AFTER started+3 has not resumed yet — tolerate loaded-CI
  # scheduling up to a generous bound, then fail.
  [ $((t - started)) -le 30 ] || fail "dispatch did not resume within 30s of a 3s reset"
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

# 17. Corrupt state fails loud (exit 2) on both readers: a regression
#     swallowing corruption as "allowed" would silently un-throttle the
#     fleet.
reset_state
mkdir -p "$fleet_home/throttle"
printf 'garbage\n' >"$fleet_home/throttle/until"
rc=0
run check >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "check on corrupt state: exit $rc, expected 2"
rc=0
run engage --until "$(($(now) + 900))" --trigger corrupt-fixture >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "engage on corrupt state: exit $rc, expected 2"
echo "ok: corrupt state fails loud on check and engage"

# 17b. An oversized all-digit value is corrupt too: without a magnitude cap
#      on the state reader the integer comparison errors under bash and
#      check falls through to exit 0 — the fail-OPEN direction test 17
#      exists to prevent. The CLI --until digit cap guards caller input
#      only; stored state read back must carry the same 15-digit guard.
reset_state
mkdir -p "$fleet_home/throttle"
printf '99999999999999999999\n' >"$fleet_home/throttle/until"
rc=0
run check >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "check on oversized numeric state: exit $rc, expected 2 (fail loud, never fail open)"
rc=0
run engage --until "$(($(now) + 900))" --trigger oversized-fixture >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "engage on oversized numeric state: exit $rc, expected 2"
echo "ok: oversized numeric state fails loud on check and engage"

# 17c. Internal whitespace is corruption, not a value to normalize: a
#      space-separated pair like "1710000 999" must fail loud (exit 2), never
#      be collapsed into a single plausible-looking epoch that silently
#      un-throttles the fleet. Regression guard for the read_until
#      surrounding-whitespace-only trim.
reset_state
mkdir -p "$fleet_home/throttle"
printf '1710000 999\n' >"$fleet_home/throttle/until"
rc=0
run check >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "check on internal-whitespace state: exit $rc, expected 2 (fail loud, never collapse whitespace-separated digits)"
echo "ok: internal-whitespace numeric state fails loud on check"

# 18. Audit action vocabulary: a later reset logs `extend`; an earlier or
#     equal reset changes nothing and logs nothing (risk 31's audit-noise
#     posture).
reset_state
run engage --until "$(($(now) + 1800))" --trigger "first" >/dev/null 2>&1 || fail "engage (first) failed"
run engage --until "$(($(now) + 5400))" --trigger "later" >/dev/null 2>&1 || fail "engage (later) failed"
rows=$(audit_query --mechanism throttle)
case $rows in
  *extend*later*) ;;
  *) fail "a later reset should log an extend row (got: '$rows')" ;;
esac
count_before=$(printf '%s\n' "$rows" | grep -c .)
run engage --until "$(($(now) + 60))" --trigger "earlier" >/dev/null 2>&1 || fail "engage (earlier) failed"
count_after=$(audit_query --mechanism throttle | grep -c .)
[ "$count_after" = "$count_before" ] \
  || fail "an earlier/equal reset must log no new row ($count_before -> $count_after)"
echo "ok: extend is logged, a no-op engagement is not"

# 19. Gate hard-fails propagate: a malformed team-shared kill-switch value
#     blocks engagement with the resolver's exit 4, never a proceed.
reset_state
printf 'fleet_daemon_pause: banana\n' >"$tmp/repo/.claude/planwright.yml"
rc=0
run engage --until "$(($(now) + 900))" --trigger gated4 >/dev/null 2>&1 || rc=$?
rm -f "$tmp/repo/.claude/planwright.yml"
[ "$rc" = 4 ] || fail "malformed repo-tracked kill-switch: exit $rc, expected 4"
run check >/dev/null || fail "gate hard-fail must not have written state"
echo "ok: a malformed team-shared kill-switch blocks engagement (exit 4)"

# 20. clear with nothing engaged is a clean no-op: exit 0, no audit row.
reset_state
rc=0
run clear >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "no-op clear: exit $rc, expected 0"
rows=$(audit_query --mechanism throttle | grep -c . || true)
[ "$rows" = 0 ] || fail "no-op clear must write no audit row (got $rows)"
echo "ok: a no-op clear is silent"

# 21. clear is deliberately ungated: the operator's emergency resume works
#     even while the kill-switch pauses the autonomous daemon layer.
reset_state
run engage --until "$(($(now) + 900))" --trigger pre-pause >/dev/null 2>&1 || fail "engage before pause failed"
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rc=0
run clear --trigger paused-resume >/dev/null 2>&1 || rc=$?
rm -f "$mlocal_cfg"
[ "$rc" = 0 ] || fail "clear under the kill-switch: exit $rc, expected 0 (ungated)"
run check >/dev/null || fail "clear under the kill-switch must resume dispatch"
echo "ok: clear stays ungated by the kill-switch"

# 22. The 24-hour wall-clock form parses (the third awk branch): until in
#     (now, now+86400].
reset_state
printf 'usage limit reached. try again 14:30\n' | run observe >/dev/null 2>&1 \
  || fail "observe (24-hour form) failed"
out=$(run check) && fail "24-hour observe should throttle" || true
until_parsed=$(printf '%s\n' "$out" | tr -d -c '0-9')
t=$(now)
[ "$until_parsed" -gt "$t" ] && [ "$until_parsed" -le $((t + 86400)) ] \
  || fail "24-hour observe: until $until_parsed not within (now, now+24h]"
echo "ok: the 24-hour wall-clock form parses to the next occurrence"

# 23. Relative minutes multiply by 60 (a swapped unit multiplier would slip
#     through the seconds-only fixtures).
reset_state
started=$(now)
printf 'rate limit reached, try again in 5 minutes\n' | run observe >/dev/null 2>&1 \
  || fail "observe (minutes) failed"
out=$(run check) && fail "minutes observe should throttle" || true
until_parsed=$(printf '%s\n' "$out" | tr -d -c '0-9')
delta=$((until_parsed - started))
[ "$delta" -ge 295 ] && [ "$delta" -le 330 ] \
  || fail "minutes observe: expected ~300s hold, got ${delta}s"
echo "ok: relative minutes scale correctly"

# 24. observe under the set kill-switch short-circuits (exit 1) with no
#     state written — the documented observe arm of the gate.
reset_state
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rc=0
printf 'rate limit reached, try again in 600 seconds\n' | run observe >/dev/null 2>&1 || rc=$?
rm -f "$mlocal_cfg"
[ "$rc" = 1 ] || fail "gated observe: exit $rc, expected 1"
run check >/dev/null || fail "gated observe must not have written state"
echo "ok: the kill-switch short-circuits observe"

# 25. Throttle rows are queryable by time range (the REQ-F1.4 Done-when),
#     and the raw daily file — the durable store, unlike the re-sanitizing
#     query view — carries no raw escape byte from a hostile capture.
reset_state
before=$(now)
printf 'usage limit reached%s[31m try again in 900 seconds\n' "$esc" | run observe >/dev/null 2>&1 \
  || fail "observe for range query failed"
after=$(now)
rows=$(audit_query --mechanism throttle --since "$((before - 1))" --until "$((after + 1))")
case $rows in
  *throttle*engage*) ;;
  *) fail "time-range query missed the engage row (got: '$rows')" ;;
esac
rows=$(audit_query --mechanism throttle --since "$((after + 3600))")
[ -z "$rows" ] || fail "an out-of-range query must return nothing (got: '$rows')"
if grep -q "$esc" "$fleet_home"/audit/audit-*.tsv 2>/dev/null; then
  fail "a raw escape byte reached the durable audit store"
fi
echo "ok: throttle rows are range-queryable and the raw store is escape-free"

# 26. The no-LLM floor (REQ-G1.2) holds for the throttle mechanism too:
#     an observe/engage cycle invokes no outbound client.
reset_state
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget gh; do
  printf '#!/bin/sh\necho "%s" >>"%s/invocations"\nexit 0\n' "$c" "$tmp" >"$stubbin/$c"
  chmod +x "$stubbin/$c"
done
rm -f "$tmp/invocations"
PATH="$stubbin:$PATH" run engage --until "$(($(now) + 600))" --trigger no-llm >/dev/null 2>&1 \
  || fail "stubbed engage failed"
printf 'rate limit reached, try again in 600 seconds\n' | PATH="$stubbin:$PATH" run observe >/dev/null 2>&1 \
  || fail "stubbed observe failed"
[ ! -f "$tmp/invocations" ] \
  || fail "an outbound client was invoked by the throttle mechanism: $(sort -u "$tmp/invocations" | tr '\n' ' ')"
# Positive control: the stub is actually reachable on this PATH.
PATH="$stubbin:$PATH" claude >/dev/null 2>&1 || true
[ -f "$tmp/invocations" ] || fail "stub positive control failed (stub not on PATH)"
echo "ok: no outbound client in the throttle paths (stub verified reachable)"

# 27. Meridiem normalization: the am/pm branch must agree with the 24-hour
#     branch on the same wall target (equivalence pins pm+12, the 12am->0 /
#     12pm->12 normalization, and the :MM capture on the meridiem branch
#     without duplicating the script's clock math). The engaged epoch is the
#     absolute next occurrence of the target, so both forms must yield the
#     until value up to a +-2s skew (one observe reads the epoch and the
#     H:M:S wall clock as two separate date calls, so a second may tick
#     between them); targets are placed ~30min/6h away from now so no
#     observation pair can straddle its own wall boundary.
mm2=$(printf '%02d' $(((10#$(date +%M) + 30) % 60)))
h24=$(((10#$(date +%H) + 6) % 24))
h12=$((h24 % 12))
[ "$h12" -ne 0 ] || h12=12
if [ "$h24" -lt 12 ]; then ap=am; else ap=pm; fi
wall_until() {
  # observe the given reset phrase from a clean state, print the until epoch
  reset_state
  printf 'You have reached your usage limit. Your limit resets %s.\n' "$1" \
    | run observe >/dev/null 2>&1 || fail "observe ('resets $1') failed"
  wu_out=$(run check) && fail "'resets $1' should throttle" || true
  printf '%s\n' "$wu_out" | tr -d -c '0-9'
}
same_wall() {
  # equal up to the +-2s two-clock-read skew; a real normalization bug is
  # off by >= 3600s (an hour) or 43200s (a meridiem), far outside it
  [ -n "$1" ] && [ -n "$2" ] || return 1
  sw_d=$(($1 - $2))
  [ "$sw_d" -ge -2 ] && [ "$sw_d" -le 2 ]
}
uA=$(wall_until "${h12}:${mm2}${ap}")
uB=$(wall_until "${h24}:${mm2}")
same_wall "$uA" "$uB" \
  || fail "meridiem branch disagrees with the 24-hour branch (${h12}:${mm2}${ap} -> '$uA' vs ${h24}:${mm2} -> '$uB')"
uA=$(wall_until "12:${mm2}am")
uB=$(wall_until "0:${mm2}")
same_wall "$uA" "$uB" \
  || fail "12am must normalize to hour 0 (12:${mm2}am -> '$uA' vs 0:${mm2} -> '$uB')"
uA=$(wall_until "12:${mm2}pm")
uB=$(wall_until "12:${mm2}")
same_wall "$uA" "$uB" \
  || fail "12pm must normalize to hour 12 (12:${mm2}pm -> '$uA' vs 12:${mm2} -> '$uB')"
echo "ok: meridiem forms agree with their 24-hour equivalents"

# 27b. The stale-prompt grace window (tower direction on gauntlet finding
#      F1): a wall-clock reset observed AT/just after its own stated minute
#      is effectively now — it engages the bounded default hold (120s here),
#      never the next-day occurrence (a ~24h over-hold the max rule could
#      never shorten).
reset_state
rc=0
printf 'You have reached your usage limit. Your limit resets %s.\n' "$(date +%H:%M)" \
  | run observe >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "observe (current-minute wall reset): exit $rc, expected 0"
out=$(run check) && fail "current-minute wall reset should hold briefly" || true
u=$(printf '%s\n' "$out" | tr -d -c '0-9')
t=$(now)
[ -n "$u" ] && [ "$u" -gt "$t" ] && [ "$u" -le $((t + 130)) ] \
  || fail "current-minute wall reset must engage the grace hold, not next day (until '$u', now $t)"
echo "ok: a wall reset at its own minute engages the grace hold, not next day"

# 28. The in-parser relative ceiling: a relative reset beyond MAX_HOLD is
#     routed to the unparsed degrade (bounded default hold + warning), not
#     engaged as an over-hold — the awk-level clamp, distinct from the CLI
#     refuse (test 14) and the shared-path clamp (test 15).
reset_state
rc=0
printf 'Rate limit reached. Try again in 9999999 seconds.\n' \
  | run observe >/dev/null 2>"$tmp/stderr28" || rc=$?
[ "$rc" = 0 ] || fail "observe (beyond-ceiling relative): exit $rc, expected 0 (degrade)"
grep -q 'could not be parsed' "$tmp/stderr28" \
  || fail "beyond-ceiling relative reset must warn about the degrade (stderr: $(cat "$tmp/stderr28"))"
out=$(run check) && fail "beyond-ceiling relative reset should still throttle (default hold)" || true
u=$(printf '%s\n' "$out" | tr -d -c '0-9')
t=$(now)
[ -n "$u" ] && [ "$u" -gt "$t" ] && [ "$u" -le $((t + 130)) ] \
  || fail "beyond-ceiling relative reset must degrade to the 120s default hold (until '$u', now $t)"
echo "ok: a beyond-ceiling relative reset degrades to the bounded default hold"

# 29. Broken install is exit 5, never a proceed: a tree missing the daemon
#     gate (engage path) and the shared resolver (observe degrade path)
#     refuses with the documented broken-install code — the sibling posture
#     test-fleet-resource-select.sh proves for the select table.
broken="$tmp/broken-tree"
mkdir -p "$broken"
cp "$FT" "$broken/fleet-throttle.sh"
cp "$here/../scripts/echo-safety.sh" "$broken/echo-safety.sh"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
  /bin/bash "$broken/fleet-throttle.sh" engage --until "$(($(now) + 900))" >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "engage with no daemon gate: exit $rc, expected 5 (broken install)"
rc=0
printf 'Rate limit reached. Try again in soon.\n' \
  | PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    /bin/bash "$broken/fleet-throttle.sh" observe >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "observe degrade with no resolver: exit $rc, expected 5 (broken install)"
echo "ok: a broken install (missing gate or resolver) is exit 5"

# 30. An audit-write failure is surfaced (exit 2), never swallowed — the
#     header's explicit contract. The state change itself persists (the
#     fleet stays safely paused / resumed); only the missing trail row is
#     the surfaced failure.
audtree="$tmp/audit-fail-tree"
mkdir -p "$audtree"
cp "$FT" "$audtree/fleet-throttle.sh"
cp "$here/../scripts/echo-safety.sh" "$audtree/echo-safety.sh"
cp "$here/../scripts/fleet-state.sh" "$audtree/fleet-state.sh"
printf '#!/bin/sh\nexit 0\n' >"$audtree/fleet-daemon-gate.sh"
printf '#!/bin/sh\nexit 1\n' >"$audtree/fleet-audit.sh"
chmod +x "$audtree/fleet-daemon-gate.sh" "$audtree/fleet-audit.sh"
af_home="$tmp/af-fleet"
rm -rf "$af_home"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="$af_home" \
  /bin/bash "$audtree/fleet-throttle.sh" engage --until "$(($(now) + 900))" --trigger audit-fail \
  >/dev/null 2>"$tmp/stderr30" || rc=$?
[ "$rc" = 2 ] || fail "engage with a failing audit helper: exit $rc, expected 2 (surfaced)"
grep -q 'refused the engage record' "$tmp/stderr30" \
  || fail "audit failure must be surfaced on stderr (got: $(cat "$tmp/stderr30"))"
[ -f "$af_home/throttle/until" ] \
  || fail "the engagement itself must persist when only the audit record fails"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="$af_home" \
  /bin/bash "$audtree/fleet-throttle.sh" clear >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "clear with a failing audit helper: exit $rc, expected 2 (surfaced)"
echo "ok: an audit-write failure is surfaced, never swallowed"

# 31. Remaining usage arms are refused (exit 2): extra args to the
#     zero-arg subcommands, a --trigger with no value, an unknown clear flag.
reset_state
for args in "check extra" "observe extra" "clear --bogus"; do
  rc=0
  # shellcheck disable=SC2086
  run $args </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
rc=0
run engage --until "$(($(now) + 100))" --trigger >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "engage --trigger with no value: exit $rc, expected 2"
echo "ok: remaining usage arms exit 2"

# 32. Anchor-on-first-observation (tower direction on gauntlet finding F2):
#     a relative reset converts to an absolute time ONCE per prompt-event.
#     Re-observing the IDENTICAL excerpt while the anchor is unelapsed is a
#     no-op (no ratchet, no extra audit row); a genuinely new event (the
#     excerpt changed, or the prior reset elapsed) re-anchors.
reset_state
sig='Rate limit reached. Try again in 9000 seconds.'
printf '%s\n' "$sig" | run observe >/dev/null 2>&1 || fail "observe (anchor) failed"
out=$(run check) && fail "anchored observe should throttle" || true
u1=$(printf '%s\n' "$out" | tr -d -c '0-9')
rows_before=$(audit_query --mechanism throttle | grep -c .)
sleep 2
printf '%s\n' "$sig" | run observe >/dev/null 2>&1 || fail "observe (identical re-observation) failed"
out=$(run check) && fail "still throttled after re-observation" || true
u2=$(printf '%s\n' "$out" | tr -d -c '0-9')
[ "$u1" = "$u2" ] \
  || fail "identical prompt re-observation must keep the first anchor (was $u1, ratcheted to $u2)"
rows_after=$(audit_query --mechanism throttle | grep -c .)
[ "$rows_before" = "$rows_after" ] \
  || fail "a dedup no-op must not log an audit row ($rows_before -> $rows_after)"
printf 'Rate limit reached. Try again in 3 hours.\n' \
  | run observe >/dev/null 2>&1 || fail "observe (new event) failed"
out=$(run check) && fail "still throttled after the new event" || true
u3=$(printf '%s\n' "$out" | tr -d -c '0-9')
[ "$u3" -gt "$u2" ] \
  || fail "a changed excerpt with a later reset must re-anchor via the max rule ($u2 -> $u3)"
echo "ok: relative resets anchor once per prompt-event (no ratchet)"

# 33. Re-anchor after elapse: the same excerpt observed again after its
#     anchored reset has passed is a fresh event and engages anew.
reset_state
sig='5-hour limit reached. Try again in 3 seconds.'
printf '%s\n' "$sig" | run observe >/dev/null 2>&1 || fail "observe (short anchor) failed"
started=$(now)
while :; do
  rc=0
  run check >/dev/null || rc=$?
  [ "$rc" != 1 ] && break
  [ $(($(now) - started)) -le 30 ] || fail "3s anchor did not elapse within 30s"
done
printf '%s\n' "$sig" | run observe >/dev/null 2>&1 || fail "observe (post-elapse re-observation) failed"
rc=0
run check >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] \
  || fail "the same excerpt after elapse is a fresh event and must re-engage (check exit $rc)"
echo "ok: an elapsed anchor re-engages on the next observation"

echo "ALL PASS: fleet-throttle"
