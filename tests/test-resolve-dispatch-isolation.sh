#!/bin/bash
# Tests for scripts/resolve-dispatch-isolation.sh — the dispatch_isolation knob
# resolver (Task 4: D-5, REQ-C1.3, REQ-C1.4).
#
# dispatch_isolation controls how /execute-task sequences a unit's steps:
# `per-step` runs implementation and each configured review_sequence skill in
# its own fresh /resume-seeded session (the assigned-decision default);
# `per-unit` keeps today's single-session behavior. It is *config*, so it is
# resolved THROUGH config-get (the Task 3 four-layer overlay reader — no layer
# logic is re-implemented here, REQ-D1.1); this resolver adds only the enum
# validation (`per-step` | `per-unit`) and the REQ-E1.4 by-layer malformed
# policy that config-get cannot apply because the enum test is semantic, not
# structural. Output is the single validated value on stdout.
#
# What is covered:
#   - the default (no overlays) resolves to the assigned decision, `per-step`;
#   - dispatch_isolation resolves across all four layers via config-get
#     (last-layer-wins), so an overlay-set value wins in precedence order;
#   - a trailing comment and surrounding whitespace are tolerated (config-get
#     strips the comment; the resolver trims the value);
#   - the REQ-E1.4 by-layer policy on a bad value (not `per-step`/`per-unit`):
#     adopter/machine-local degrade+warn to the core default, repo-tracked
#     hard-fails (exit 4);
#   - a structurally malformed repo-tracked config file still hard-fails
#     (config-get's exit 4 propagates);
#   - dispatch_isolation absent in every layer (broken/partial install) degrades
#     to the safe default `per-step` with a loud warning (exit 0);
#   - the output contract: a single newline-terminated value line.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-dispatch-isolation.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RDI="$here/../scripts/resolve-dispatch-isolation.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RDI" ] || fail "scripts/resolve-dispatch-isolation.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- Config layer fixtures, wired through config-get's env overrides exactly as
#     test-config-get.sh / test-resolve-review-sequence.sh do (hermetic: no
#     $HOME, no git toplevel).
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped-style core default: the assigned-decision default, per-step.
printf 'dispatch_isolation: per-step\n' >"$core_cfg"

# The resolver takes no arguments (the key is fixed), so `run` passes none.
run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RDI"
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# 1. Default (no overlays) resolves to the assigned decision: per-step.
reset_layers
got=$(run)
[ "$got" = per-step ] \
  || fail "default did not resolve to the assigned decision (expected 'per-step', got '$got')"
echo "ok: the default dispatch_isolation is the assigned decision, per-step"

# 2. Four-layer resolution via config-get: a machine-local value wins.
reset_layers
printf 'dispatch_isolation: per-unit\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = per-unit ] \
  || fail "machine-local value not honored (expected 'per-unit', got '$got')"
echo "ok: an overlay-set value resolves through the four layers"

# 2b. Last-layer-wins across layers: repo-tracked overrides adopter overrides core.
reset_layers
printf 'dispatch_isolation: per-unit\n' >"$adopter_cfg"
printf 'dispatch_isolation: per-step\n' >"$tracked_cfg"
got=$(run)
[ "$got" = per-step ] \
  || fail "repo-tracked did not win over adopter (got: '$got')"
rm -f "$tracked_cfg"
got=$(run)
[ "$got" = per-unit ] \
  || fail "adopter did not win over core after repo-tracked removed (got: '$got')"
echo "ok: dispatch_isolation obeys last-layer-wins (core < adopter < repo-tracked < machine-local)"

# 3. A trailing comment and surrounding whitespace are tolerated (config-get
#    strips the comment; the resolver trims the value).
reset_layers
printf 'dispatch_isolation:   per-unit   # constrained host\n' >"$tracked_cfg"
got=$(run)
[ "$got" = per-unit ] \
  || fail "whitespace/comment not tolerated (got: '$got')"
echo "ok: inner whitespace and a trailing comment are tolerated"

# 4. Bad value in the adopter overlay: malformed, degrade to the core default
#    with a loud warning, exit 0.
reset_layers
printf 'dispatch_isolation: per-monkey\n' >"$adopter_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "bad-value adopter: exit $rc, expected 0 (degrade)"
[ "$out" = per-step ] || fail "bad-value adopter: did not degrade to core default (got '$out')"
case $err in
  *adopter*) ;;
  *) fail "bad-value adopter: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid value in the adopter overlay degrades to the core default with a warning"

# 4b. Bad value in machine-local also degrades.
reset_layers
printf 'dispatch_isolation: yes\n' >"$mlocal_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "bad-value machine-local: exit $rc, expected 0 (degrade)"
[ "$out" = per-step ] || fail "bad-value machine-local: did not degrade to core (got '$out')"
case $err in
  *machine-local*) ;;
  *) fail "bad-value machine-local: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid value in machine-local degrades to the core default with a warning"

# 5. Bad value in the repo-tracked (team-shared) overlay hard-fails (exit 4): a
#    broken shared value never silently degrades a team.
reset_layers
printf 'dispatch_isolation: per-monkey\n' >"$tracked_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "bad-value repo-tracked: exit $rc, expected 4 (hard-fail)"
case $err in
  *repo-tracked*) ;;
  *) fail "bad-value repo-tracked: error does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid value in the repo-tracked overlay hard-fails (exit 4)"

# 6. A structurally malformed repo-tracked config FILE (a YAML block sequence,
#    which config-get rejects) propagates the hard-fail (exit 4).
reset_layers
printf 'dispatch_isolation:\n  - per-step\n' >"$tracked_cfg"
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] \
  || fail "structurally malformed repo-tracked file: exit $rc, expected 4 (propagated hard-fail)"
echo "ok: a structurally malformed repo-tracked config file hard-fails (exit 4 propagated)"

# 6b. Documented degrade target — the CORE DEFAULT, not a strict per-layer
#     cascade. When the winning (highest) layer's value is malformed and a LOWER
#     overlay layer holds a *valid* value, the resolver still degrades to the
#     core default (config-get exposes only the merged winning value, not
#     per-layer values; the core default is the always-valid, behavior-preserving
#     base). Locks the limitation the script header documents.
reset_layers
printf 'dispatch_isolation: per-unit\n' >"$adopter_cfg"  # valid, lower layer
printf 'dispatch_isolation: per-monkey\n' >"$mlocal_cfg" # malformed, winning layer
rc=0
out=$(run 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "degrade-to-core (valid lower layer): exit $rc, expected 0"
[ "$out" = per-step ] \
  || fail "degrade target was not the core default (got '$out'; documented behavior is core, not the valid adopter 'per-unit')"
echo "ok: a malformed winning layer degrades to the core default (documented, not strict next-lower)"

# 7. A malformed adopter FILE (block sequence) degrades to the core default
#    (config-get degrades adopter; the resolver still yields a usable value).
reset_layers
printf 'dispatch_isolation:\n  - per-step\n' >"$adopter_cfg"
rc=0
out=$(run 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "malformed adopter file: exit $rc, expected 0 (degrade)"
[ "$out" = per-step ] || fail "malformed adopter file: did not degrade to core (got '$out')"
echo "ok: a malformed adopter config file degrades to the core default"

# 7b. Malformed overlay value AND the core omits the key: the degrade re-resolve
#     finds no core default (config-get exit 3), so it falls back to the safe
#     default `per-step` with a second warning, exit 0. Covers the partial-install
#     branch this resolver adds over resolve-review-sequence.sh (which treats a
#     non-zero re-resolve as a broken install); without it /execute-task would
#     halt on a corner that is recoverable.
reset_layers
core_omit="$tmp/core-omit.yml"
printf 'max_parallel_units: 3\n' >"$core_omit"            # a core file that omits dispatch_isolation
printf 'dispatch_isolation: per-monkey\n' >"$adopter_cfg" # malformed winning value
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RDI" 2>/dev/null) || rc=$?
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RDI" 2>&1 >/dev/null) || true
[ "$rc" = 0 ] || fail "malformed overlay + core omits key: exit $rc, expected 0 (degrade)"
[ "$out" = per-step ] \
  || fail "malformed overlay + core omits key: did not fall back to per-step (got '$out')"
case $err in
  *"core default dispatch_isolation is also unset"*) ;;
  *) fail "malformed overlay + core omits key: warning does not flag the absent core default (got: '$err')" ;;
esac
echo "ok: a malformed overlay with the key absent from core falls back to the safe default per-step"

# 8. Determinism: identical inputs yield identical output across repeated runs.
reset_layers
printf 'dispatch_isolation: per-unit\n' >"$tracked_cfg"
a=$(run)
b=$(run)
[ "$a" = "$b" ] || fail "resolution is not deterministic across runs"
echo "ok: resolution is deterministic across repeated runs"

# 9. Output contract: the emitted value is newline-terminated (a shell `read`
#    consumer would otherwise mis-handle the last byte). $()-based assertions
#    above cannot catch this (command substitution strips trailing newlines), so
#    check the raw bytes.
reset_layers
run >"$tmp/out.txt"
[ "$(tail -c1 "$tmp/out.txt" | wc -l | tr -d ' ')" = 1 ] \
  || fail "default output is not newline-terminated"
reset_layers
printf 'dispatch_isolation: per-unit\n' >"$tracked_cfg"
run >"$tmp/out.txt"
[ "$(tail -c1 "$tmp/out.txt" | wc -l | tr -d ' ')" = 1 ] \
  || fail "overlay-set output is not newline-terminated"
echo "ok: the emitted value is newline-terminated"

# 10. Usage guard: the resolver takes no arguments (the key is fixed); any
#     argument is a usage error (exit 2).
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RDI" some-arg >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "passing an argument did not produce a usage error (exit $rc, expected 2)"
echo "ok: passing any argument is a usage error (exit 2)"

# 11. Broken/partial install: dispatch_isolation absent in every layer (config-get
#     exits 3). The resolver degrades to the safe default `per-step` with a loud
#     stderr warning, exit 0, so /execute-task still runs.
reset_layers
core_empty="$tmp/core-empty.yml"
printf 'max_parallel_units: 3\n' >"$core_empty" # a core file that omits dispatch_isolation
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_empty" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RDI" 2>/dev/null) || rc=$?
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_empty" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RDI" 2>&1 >/dev/null) || true
[ "$rc" = 0 ] || fail "absent-in-every-layer: exit $rc, expected 0 (graceful degrade)"
[ "$out" = per-step ] || fail "absent-in-every-layer: did not fall back to per-step (got '$out')"
case $err in
  *) [ -n "$err" ] || fail "absent-in-every-layer: no warning emitted" ;;
esac
echo "ok: dispatch_isolation absent in every layer degrades to the safe default per-step with a warning"

echo "ALL PASS: resolve-dispatch-isolation"
