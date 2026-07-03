#!/bin/bash
# Tests for scripts/context-budget-monitor.sh — the long-running tower's
# context-budget monitor (Task 5: D-4, REQ-C1.1).
#
# The monitor answers one question for a tower each step: given how many
# orchestration steps I have completed, am I nearing my context budget and so
# should I auto-heal (hand off to a fresh tower, the continue-as-new pattern)?
# It resolves the configured completed-step threshold via
# resolve-context-budget-threshold.sh (the four-layer config knob) and compares
# the caller-supplied step count against it. The step count is the portable,
# tower-controllable proxy for context pressure because Claude Code exposes no
# supported live token-usage introspection (Task 5 research, brief §7).
#
# stdout contract: exactly one of `near-limit` | `ok` | `disabled`, one line.
#   - near-limit: steps completed have reached the threshold; hand off now.
#   - ok:         below the threshold; keep going.
#   - disabled:   auto-heal is turned off (threshold `off`); never hand off.
# Exit: 0 on a successful evaluation (any of the three words); 2 usage error;
# the resolver's hard-fail (exit 4, broken shared config) is propagated.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-context-budget-monitor.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
MON="$here/../scripts/context-budget-monitor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$MON" ] || fail "scripts/context-budget-monitor.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
tracked_cfg="$repo/.claude/planwright.yml"

# run <steps> [more-args...] — evaluate against the current fixture config.
run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$MON" "$@"
}

set_threshold() { printf 'context_budget_threshold: %s\n' "$1" >"$core_cfg"; }
reset_layers() { rm -f "$tracked_cfg"; }

# 1. Below the threshold → ok.
set_threshold 50
reset_layers
got=$(run 10)
[ "$got" = ok ] || fail "below threshold: expected 'ok', got '$got'"
echo "ok: a step count below the threshold reports ok"

# 2. Exactly at the threshold → near-limit (the comparison is >=).
got=$(run 50)
[ "$got" = near-limit ] || fail "at threshold: expected 'near-limit', got '$got'"
echo "ok: a step count exactly at the threshold reports near-limit"

# 3. Above the threshold → near-limit.
got=$(run 73)
[ "$got" = near-limit ] || fail "above threshold: expected 'near-limit', got '$got'"
echo "ok: a step count above the threshold reports near-limit"

# 4. Zero steps (a fresh tower) with a positive threshold → ok.
got=$(run 0)
[ "$got" = ok ] || fail "zero steps: expected 'ok', got '$got'"
echo "ok: zero completed steps reports ok"

# 5. Threshold `off` → disabled, regardless of the step count.
set_threshold off
got=$(run 100000)
[ "$got" = disabled ] || fail "off: expected 'disabled' regardless of steps, got '$got'"
echo "ok: an 'off' threshold reports disabled and never hands off"

# 6. An overlay threshold is honored through config resolution (integration).
set_threshold 50
printf 'context_budget_threshold: 5\n' >"$tracked_cfg"
got=$(run 6)
[ "$got" = near-limit ] || fail "overlay threshold not honored: expected 'near-limit' at steps=6 vs threshold=5, got '$got'"
reset_layers
echo "ok: the monitor honors an overlay-set threshold via config resolution"

# 7. Usage errors → exit 2.
set_threshold 50
reset_layers
for badargs in "" "abc" "-1" "3.5" "10 20"; do
  rc=0
  # shellcheck disable=SC2086 # deliberate word-splitting to exercise arg counts
  run $badargs >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for args '[$badargs]': exit $rc, expected 2"
done
echo "ok: a missing, non-integer, negative, decimal, or extra argument is a usage error (exit 2)"

# 8. A malformed repo-tracked threshold hard-fails: the resolver's exit 4 is
#    propagated (a broken shared config never silently degrades the tower).
set_threshold 50
printf 'context_budget_threshold: nonsense\n' >"$tracked_cfg"
rc=0
run 10 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "malformed repo-tracked threshold: exit $rc, expected 4 (propagated resolver hard-fail)"
reset_layers
echo "ok: a malformed repo-tracked threshold propagates the resolver hard-fail (exit 4)"

# 9. Output contract: exactly one line.
set_threshold 50
lines=$(run 10 | wc -l | tr -d ' ')
[ "$lines" = 1 ] || fail "output is not exactly one line (got $lines lines)"
echo "ok: the output is a single newline-terminated line"

echo "PASS: context-budget-monitor.sh"
