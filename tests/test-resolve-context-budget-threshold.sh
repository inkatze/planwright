#!/bin/bash
# Tests for scripts/resolve-context-budget-threshold.sh — the
# context_budget_threshold knob resolver (Task 5: D-4, REQ-C1.1).
#
# context_budget_threshold is the long-running tower's auto-heal trigger: the
# number of completed orchestration steps after which the tower hands off to a
# fresh tower (the continue-as-new pattern), or the sentinel `off` to disable
# auto-heal. The signal is a completed-step-count proxy because Claude Code
# exposes no supported live token-usage introspection (Task 5 research; brief
# §7). It is *config*, so it is resolved THROUGH config-get (the Task 3
# four-layer overlay reader — no layer logic is re-implemented here, REQ-D1.1);
# this resolver adds only the value validation (a positive integer or `off`)
# and the REQ-E1.4 by-layer malformed policy that config-get cannot apply
# because the value test is semantic, not structural. Output is the single
# validated value on stdout.
#
# What is covered:
#   - the default (no overlays) resolves to the safe conservative default;
#   - the knob resolves across all four layers via config-get (last-layer-wins);
#   - the sentinel `off` is a legal value;
#   - a trailing comment and surrounding whitespace are tolerated;
#   - a positive integer of any width validates; 0, negatives, and non-numeric
#     values are malformed;
#   - the REQ-E1.4 by-layer policy on a bad value: adopter/machine-local
#     degrade+warn to the core default, repo-tracked hard-fails (exit 4);
#   - a structurally malformed repo-tracked config file still hard-fails;
#   - the knob absent in every layer (broken/partial install) degrades to the
#     safe default with a loud warning (exit 0);
#   - the output contract: a single newline-terminated value line.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-context-budget-threshold.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RCB="$here/../scripts/resolve-context-budget-threshold.sh"

# The shipped-style safe default (kept in sync with config/defaults.yml and the
# resolver's own fallback constant).
SAFE_DEFAULT=50

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RCB" ] || fail "scripts/resolve-context-budget-threshold.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- Config layer fixtures, wired through config-get's env overrides exactly as
#     test-resolve-dispatch-isolation.sh does (hermetic: no $HOME, no git top).
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped-style core default: the safe conservative step budget.
printf 'context_budget_threshold: %s\n' "$SAFE_DEFAULT" >"$core_cfg"

# The resolver takes no arguments (the key is fixed), so `run` passes none.
run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RCB"
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# 1. Default (no overlays) resolves to the safe conservative default.
reset_layers
got=$(run)
[ "$got" = "$SAFE_DEFAULT" ] \
  || fail "default did not resolve to the safe default (expected '$SAFE_DEFAULT', got '$got')"
echo "ok: the default context_budget_threshold is the safe conservative default"

# 2. Four-layer resolution via config-get: a machine-local value wins.
reset_layers
printf 'context_budget_threshold: 25\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = 25 ] || fail "machine-local value not honored (expected '25', got '$got')"
echo "ok: an overlay-set value resolves through the four layers"

# 2b. Last-layer-wins: repo-tracked overrides adopter overrides core.
reset_layers
printf 'context_budget_threshold: 10\n' >"$adopter_cfg"
printf 'context_budget_threshold: 30\n' >"$tracked_cfg"
got=$(run)
[ "$got" = 30 ] || fail "repo-tracked did not win over adopter (got: '$got')"
rm -f "$tracked_cfg"
got=$(run)
[ "$got" = 10 ] || fail "adopter did not win over core after repo-tracked removed (got: '$got')"
echo "ok: context_budget_threshold obeys last-layer-wins (core < adopter < repo-tracked < machine-local)"

# 3. The `off` sentinel disables auto-heal and is a legal value.
reset_layers
printf 'context_budget_threshold: off\n' >"$tracked_cfg"
got=$(run)
[ "$got" = off ] || fail "the 'off' sentinel was not honored (got: '$got')"
echo "ok: the 'off' sentinel is a legal value (auto-heal disabled)"

# 4. A trailing comment and surrounding whitespace are tolerated.
reset_layers
printf 'context_budget_threshold:   80   # roomy host\n' >"$tracked_cfg"
got=$(run)
[ "$got" = 80 ] || fail "whitespace/comment not tolerated (got: '$got')"
echo "ok: inner whitespace and a trailing comment are tolerated"

# 4b. A wide positive integer validates (no arbitrary upper clamp).
reset_layers
printf 'context_budget_threshold: 100000\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = 100000 ] || fail "a wide positive integer did not validate (got: '$got')"
echo "ok: a positive integer of any width validates"

# 5. Bad value in the adopter overlay: malformed, degrade to the core default
#    with a loud warning, exit 0. `0` is malformed (hand-off-immediately is
#    nonsensical); a negative and a non-numeric are malformed too.
for bad in 0 -5 lots 4.5; do
  reset_layers
  printf 'context_budget_threshold: %s\n' "$bad" >"$adopter_cfg"
  rc=0
  err=$(run 2>&1 >/dev/null) || rc=$?
  out=$(run 2>/dev/null)
  [ "$rc" = 0 ] || fail "bad-value ('$bad') adopter: exit $rc, expected 0 (degrade)"
  [ "$out" = "$SAFE_DEFAULT" ] \
    || fail "bad-value ('$bad') adopter: did not degrade to core default (got '$out')"
  case $err in
    *adopter*) ;;
    *) fail "bad-value ('$bad') adopter: warning does not name the layer (got: '$err')" ;;
  esac
done
echo "ok: invalid values (0, negative, non-numeric, decimal) in the adopter overlay degrade to core with a warning"

# 5b. Bad value in machine-local also degrades.
reset_layers
printf 'context_budget_threshold: nope\n' >"$mlocal_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "bad-value machine-local: exit $rc, expected 0 (degrade)"
[ "$out" = "$SAFE_DEFAULT" ] || fail "bad-value machine-local: did not degrade to core (got '$out')"
case $err in
  *machine-local*) ;;
  *) fail "bad-value machine-local: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid value in machine-local degrades to the core default with a warning"

# 6. Bad value in the repo-tracked (team-shared) overlay hard-fails (exit 4).
reset_layers
printf 'context_budget_threshold: 0\n' >"$tracked_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "bad-value repo-tracked: exit $rc, expected 4 (hard-fail)"
case $err in
  *repo-tracked*) ;;
  *) fail "bad-value repo-tracked: error does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid value in the repo-tracked overlay hard-fails (exit 4)"

# 7. A structurally malformed repo-tracked config FILE (a YAML block sequence,
#    which config-get rejects) propagates the hard-fail (exit 4).
reset_layers
printf 'context_budget_threshold:\n  - 50\n' >"$tracked_cfg"
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] \
  || fail "structurally malformed repo-tracked file: exit $rc, expected 4 (propagated hard-fail)"
echo "ok: a structurally malformed repo-tracked config file hard-fails (exit 4 propagated)"

# 7b. Documented degrade target — the CORE DEFAULT, not a strict per-layer
#     cascade (config-get exposes only the merged winning value). A malformed
#     winning layer with a valid lower layer still degrades to the core default.
reset_layers
printf 'context_budget_threshold: 20\n' >"$adopter_cfg" # valid, lower layer
printf 'context_budget_threshold: bad\n' >"$mlocal_cfg" # malformed, winning layer
rc=0
out=$(run 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "degrade-to-core (valid lower layer): exit $rc, expected 0"
[ "$out" = "$SAFE_DEFAULT" ] \
  || fail "degrade target was not the core default (got '$out'; documented behavior is core, not the valid adopter '20')"
echo "ok: a malformed winning layer degrades to the core default (documented, not strict next-lower)"

# 8. The knob absent in every layer (broken/partial install) degrades to the
#    safe default with a loud warning, exit 0.
reset_layers
core_omit="$tmp/core-omit.yml"
printf 'max_parallel_units: 3\n' >"$core_omit"
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCB" 2>/dev/null) || rc=$?
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCB" 2>&1 >/dev/null) || true
[ "$rc" = 0 ] || fail "knob absent everywhere: exit $rc, expected 0 (degrade)"
[ "$out" = "$SAFE_DEFAULT" ] || fail "knob absent everywhere: did not fall back to the safe default (got '$out')"
case $err in
  *broken* | *partial* | *fall*) ;;
  *) fail "knob absent everywhere: warning is not loud about the broken/partial install (got: '$err')" ;;
esac
echo "ok: the knob absent in every layer falls back to the safe default with a loud warning"

# 9. Output contract: a single newline-terminated value line, nothing else.
reset_layers
printf 'context_budget_threshold: 42\n' >"$tracked_cfg"
lines=$(run | wc -l | tr -d ' ')
[ "$lines" = 1 ] || fail "output is not exactly one line (got $lines lines)"
echo "ok: the output is a single newline-terminated value line"

echo "PASS: resolve-context-budget-threshold.sh"
