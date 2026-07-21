#!/bin/bash
# Tests for scripts/fleet-credit-continuation.sh — credit-continuation
# recovery at the rate-limit wall (fleet-autonomy Task 11; D-27, REQ-E1.11,
# REQ-E1.7, REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.5).
#
# When Claude Code's rate-limit wall offers a credit-continuation prompt
# ("spend credits / extra usage to continue"), the fleet's DEFAULT response
# is to decline and wait for the window to reset (the REQ-E1.7 reactive
# backstop). Auto-spend is NEVER the shipped default (D-27): spending credits
# to continue requires explicit operator opt-in through the overlay
# (fleet_credit_continuation_spend). The decision is a deterministic reaction
# to the detected prompt (no LLM/API call — REQ-G1.2), audited (REQ-F1.4) and
# kill-switch-gated (REQ-F1.3). This is a spend-AVOIDANCE default, not a
# spend-accounting ceiling.
#
# What is covered (the REQ-E1.11 test-spec fixtures):
#   - a representative credit-continuation prompt with nothing configured
#     decides `decline` — no credits spent — and the stubbed outbound clients
#     are never invoked (zero LLM/API calls in the decision path);
#   - the overlay opt-in (fleet_credit_continuation_spend: true) decides
#     `spend`, and a machine-local override wins (config-get resolution);
#   - the shipped default (nothing configured) never spends;
#   - the decline/spend decision logs through the shared audit trail and the
#     operator kill-switch short-circuits it (no decision, no audit row);
#   - an adversarial/garbled wall variant is NOT recognized — the fleet falls
#     through to the plain reactive backstop (fleet-throttle observe), with no
#     accidental spend;
#   - captured text is control-free-sanitized before recognition, display, and
#     audit (no raw control byte reaches stderr/stdout or the trail);
#   - usage errors are refused (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-credit-continuation.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FCC="$here/../scripts/fleet-credit-continuation.sh"
FA="$here/../scripts/fleet-audit.sh"
FT="$here/../scripts/fleet-throttle.sh"

TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FCC" ] || fail "scripts/fleet-credit-continuation.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"

# Isolated config layers: the kill-switch resolves false and the credit-spend
# opt-in resolves false unless a step flips them in the machine-local layer.
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_credit_continuation_spend: false
fleet_throttle_default_hold: 120
EOF
mlocal_cfg="$repo/.claude/planwright.local.yml"

# Stub outbound clients: any invocation is an LLM/API call in the decision
# path, which REQ-G1.2 forbids. Each stub records its invocation.
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget gh; do
  cat >"$stubbin/$c" <<EOF
#!/bin/sh
echo "$c" >>"$tmp/invocations"
exit 0
EOF
  chmod +x "$stubbin/$c"
done

run() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FCC" "$@"
}

throttle() {
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
  rm -f "$mlocal_cfg" "$tmp/invocations"
}

# A representative credit-continuation prompt (the "spend credits to continue"
# offer at the wall). Version-sensitive UI text — the recognizer keys on the
# spend-offer + continuation phrasing, not an exact string.
CREDIT_PROMPT='Claude usage limit reached. You can spend credits to continue past the limit, or wait for the window to reset.'
# A second recognizable variant, phrased around "extra usage".
CREDIT_PROMPT_2="You've hit your usage limit. Continue with extra usage? Additional charges apply."

# 1. Usage errors are refused (exit 2).
reset_state
for args in "" "bogus" "decide --nope"; do
  rc=0
  # shellcheck disable=SC2086
  run $args </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
echo "ok: usage errors exit 2"

# 2. The REQ-E1.11 default fixture: a representative credit-continuation prompt
#    with NOTHING configured decides decline-and-wait — no credits spent — and
#    the stubbed outbound clients are never invoked (no LLM/API call).
reset_state
out=$(printf '%s\n' "$CREDIT_PROMPT" | run decide) \
  || fail "decide on the credit prompt exited nonzero"
[ "$out" = "decision${TAB}decline" ] \
  || fail "default decision: expected 'decision<TAB>decline', got '$out'"
[ ! -f "$tmp/invocations" ] \
  || fail "an outbound client was invoked in the decision path: $(sort -u "$tmp/invocations" | tr '\n' ' ')"
rows=$(audit_query --mechanism credit-continuation)
# Match the tab-delimited ACTION column, not the trigger excerpt (which itself
# quotes "spend credits" from the prompt).
case $rows in
  *"${TAB}decline${TAB}"*) ;;
  *) fail "default decline did not log through the audit trail (got: '$rows')" ;;
esac
case $rows in
  *"${TAB}spend${TAB}"*) fail "default decision must never spend (got a spend action row: '$rows')" ;;
  *) ;;
esac
echo "ok: default credit-continuation response is decline-and-wait, audited, no LLM call"

# 3. The shipped default (nothing configured) never spends — the second
#    recognizable variant also decides decline.
reset_state
out=$(printf '%s\n' "$CREDIT_PROMPT_2" | run decide) \
  || fail "decide on the 'extra usage' variant exited nonzero"
[ "$out" = "decision${TAB}decline" ] \
  || fail "shipped-default decision for variant 2: expected decline, got '$out'"
echo "ok: the shipped default never spends"

# 4. The overlay opt-in: with fleet_credit_continuation_spend set true in the
#    machine-local layer, the decision is spend (machine-local override wins,
#    resolved via config-get). The audit trail records the permit.
reset_state
printf 'fleet_credit_continuation_spend: true\n' >"$mlocal_cfg"
out=$(printf '%s\n' "$CREDIT_PROMPT" | run decide) \
  || fail "decide with the opt-in set exited nonzero"
[ "$out" = "decision${TAB}spend" ] \
  || fail "opt-in decision: expected 'decision<TAB>spend', got '$out'"
rows=$(audit_query --mechanism credit-continuation)
case $rows in
  *"${TAB}spend${TAB}"*) ;;
  *) fail "opt-in spend did not log through the audit trail (got: '$rows')" ;;
esac
rm -f "$mlocal_cfg"
echo "ok: the machine-local opt-in permits spend and wins (config-get resolution)"

# 5. The operator kill-switch honored: with fleet_daemon_pause set, the
#    decision short-circuits (exit 1), makes no decision, and writes no audit
#    row — the Task 1 daemon-gate contract.
reset_state
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rc=0
out=$(printf '%s\n' "$CREDIT_PROMPT" | run decide 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "gated decide: exit $rc, expected 1 (kill-switch short-circuit)"
[ -z "$out" ] || fail "gated decide printed a decision: '$out'"
rm -f "$mlocal_cfg"
rows=$(audit_query --mechanism credit-continuation 2>/dev/null || true)
[ -z "$rows" ] || fail "gated decide wrote an audit row: '$rows'"
echo "ok: the operator kill-switch short-circuits the credit-continuation decision"

# 6. Adversarial/garbled wall variant A: a PLAIN rate-limit wall (no
#    credit-continuation offer) is NOT recognized (exit 3, clean no-op), so the
#    fleet falls through to the reactive backstop — proven by the same text
#    engaging fleet-throttle. No decision, no audit row, no spend.
reset_state
plain_wall='Rate limit reached. Please try again in 30 minutes.'
rc=0
out=$(printf '%s\n' "$plain_wall" | run decide 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "plain wall: exit $rc, expected 3 (unrecognized, fall through)"
[ -z "$out" ] || fail "plain wall produced a decision: '$out'"
rows=$(audit_query --mechanism credit-continuation 2>/dev/null || true)
[ -z "$rows" ] || fail "plain wall wrote a credit-continuation audit row: '$rows'"
# End-to-end: the SAME wall text engages the reactive backstop.
printf '%s\n' "$plain_wall" | throttle observe >/dev/null 2>&1 \
  || fail "the reactive backstop did not engage on the plain wall"
throttle check >/dev/null 2>&1 && fail "the reactive backstop should be throttled after the wall"
echo "ok: an unrecognized wall falls through to the reactive backstop (no spend)"

# 7. Adversarial variant B: text containing "continue" but NO credit/extra-usage
#    offer must NOT be mistaken for a spend offer (no accidental spend even with
#    the opt-in armed).
reset_state
printf 'fleet_credit_continuation_spend: true\n' >"$mlocal_cfg"
not_offer='Session ended. Press enter to continue.'
rc=0
out=$(printf '%s\n' "$not_offer" | run decide 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "non-offer 'continue' text: exit $rc, expected 3 (unrecognized)"
rm -f "$mlocal_cfg"
rows=$(audit_query --mechanism credit-continuation 2>/dev/null || true)
[ -z "$rows" ] || fail "non-offer text wrote an audit row (accidental spend risk): '$rows'"
echo "ok: 'continue' without a credit offer is not mistaken for a spend offer"

# 8. Non-signal / empty text is a clean no-op (exit 3).
reset_state
rc=0
printf '' | run decide >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "empty text: exit $rc, expected 3"
echo "ok: non-signal text is a clean no-op"

# 9. Sanitization (REQ-G1.2 echo discipline): an escape-bearing credit prompt
#    is still recognized (decline by default), and no raw control byte reaches
#    stdout, stderr, or the audit trail.
reset_state
esc=$(printf '\033')
prompt_esc=$(printf 'Usage limit reached. \033[31mSpend credits to continue\033[0m past the limit.\n')
out=$(printf '%s\n' "$prompt_esc" | run decide 2>"$tmp/err") \
  || fail "escape-bearing credit prompt was not recognized"
[ "$out" = "decision${TAB}decline" ] \
  || fail "escape-bearing prompt: expected decline, got '$out'"
case $out in
  *"$esc"*) fail "sanitize: a raw escape byte reached stdout" ;;
esac
case $(cat "$tmp/err") in
  *"$esc"*) fail "sanitize: a raw escape byte reached stderr" ;;
esac
rows=$(audit_query --mechanism credit-continuation)
case $rows in
  *"$esc"*) fail "sanitize: a raw escape byte reached the audit trail" ;;
esac
echo "ok: captured text is sanitized before recognition, display, and audit"

echo "ALL PASS: fleet-credit-continuation"
