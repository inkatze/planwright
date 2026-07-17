#!/bin/bash
# Tests for scripts/resolve-config-knob.sh — the SHARED config-knob resolver
# the fleet-autonomy bundle introduces (Task 1: D-22, REQ-G1.5).
#
# Every new knob this bundle adds resolves through this one helper instead of
# copying the ~180-line per-knob resolver shape (resolve-dispatch-isolation.sh
# et al.). It is *config*, so it resolves THROUGH config-get (the four-layer
# overlay reader — no layer logic re-implemented, customization-overlay
# REQ-D1.1); this helper adds only the semantic validation (an enum member set
# or a positive integer) and the REQ-E1.4 by-layer malformed policy the
# per-knob siblings already apply:
#   - repo-tracked malformed value or file: hard-fail, exit 4;
#   - adopter / machine-local malformed value: warn + degrade to the CORE
#     default (re-resolved with the overlay layers neutralized);
#   - core default malformed: broken install, exit 5;
#   - key absent in every layer: warn + emit the caller's --fallback, exit 0.
#
# What is covered:
#   - value resolution across all four layers via config-get (last-layer-wins);
#   - comment/whitespace tolerance;
#   - the by-layer malformed-value policy (same shape review_sequence has);
#   - the posint type (leading zero, zero, negative, oversize all malformed);
#   - usage validation (key charset, type set, missing/invalid fallback);
#   - the output contract (single newline-terminated value);
#   - the REQ-G1.5 bundle-knob sweep: every knob the fleet-autonomy bundle
#     introduces is present in config/defaults.yml, documented in
#     docs/options-reference.md, and resolves through this helper with the
#     by-layer policy.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-config-knob.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RCK="$here/../scripts/resolve-config-knob.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RCK" ] || fail "scripts/resolve-config-knob.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- Config layer fixtures, wired through config-get's env overrides exactly as
#     test-resolve-dispatch-isolation.sh does (hermetic: no $HOME, no git
#     toplevel).
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

printf 'fleet_daemon_pause: false\n' >"$core_cfg"

# run — resolve the fleet_daemon_pause enum knob against the fixture layers.
run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback false
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# 1. Default (no overlays) resolves to the core value.
reset_layers
got=$(run)
[ "$got" = false ] || fail "core default did not resolve (expected 'false', got '$got')"
echo "ok: the core default resolves"

# 2. Four-layer resolution: a machine-local value wins.
reset_layers
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = true ] || fail "machine-local value not honored (expected 'true', got '$got')"
echo "ok: an overlay-set value resolves through the four layers"

# 2b. Last-layer-wins: repo-tracked over adopter over core.
reset_layers
printf 'fleet_daemon_pause: true\n' >"$adopter_cfg"
printf 'fleet_daemon_pause: false\n' >"$tracked_cfg"
got=$(run)
[ "$got" = false ] || fail "repo-tracked did not win over adopter (got '$got')"
rm -f "$tracked_cfg"
got=$(run)
[ "$got" = true ] || fail "adopter did not win over core after repo-tracked removed (got '$got')"
echo "ok: the knob obeys last-layer-wins (core < adopter < repo-tracked < machine-local)"

# 3. A trailing comment and surrounding whitespace are tolerated.
reset_layers
printf 'fleet_daemon_pause:   true   # debugging the daemon layer\n' >"$tracked_cfg"
got=$(run)
[ "$got" = true ] || fail "whitespace/comment not tolerated (got '$got')"
echo "ok: inner whitespace and a trailing comment are tolerated"

# 4. Bad value in the adopter overlay: degrade to the core default with a
#    warning naming the layer, exit 0.
reset_layers
printf 'fleet_daemon_pause: maybe\n' >"$adopter_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "bad-value adopter: exit $rc, expected 0 (degrade)"
[ "$out" = false ] || fail "bad-value adopter: did not degrade to core default (got '$out')"
case $err in
  *adopter*) ;;
  *) fail "bad-value adopter: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid adopter value degrades to the core default with a warning"

# 4b. Bad value in machine-local also degrades.
reset_layers
printf 'fleet_daemon_pause: yes\n' >"$mlocal_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
out=$(run 2>/dev/null)
[ "$rc" = 0 ] || fail "bad-value machine-local: exit $rc, expected 0 (degrade)"
[ "$out" = false ] || fail "bad-value machine-local: did not degrade to core (got '$out')"
case $err in
  *machine-local*) ;;
  *) fail "bad-value machine-local: warning does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid machine-local value degrades to the core default with a warning"

# 5. Bad value in the repo-tracked (team-shared) overlay hard-fails (exit 4).
reset_layers
printf 'fleet_daemon_pause: maybe\n' >"$tracked_cfg"
rc=0
err=$(run 2>&1 >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "bad-value repo-tracked: exit $rc, expected 4 (hard-fail)"
case $err in
  *repo-tracked*) ;;
  *) fail "bad-value repo-tracked: error does not name the layer (got: '$err')" ;;
esac
echo "ok: an invalid repo-tracked value hard-fails (exit 4)"

# 6. A structurally malformed repo-tracked config FILE propagates the hard-fail.
reset_layers
printf 'fleet_daemon_pause:\n  - true\n' >"$tracked_cfg"
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "structurally malformed repo-tracked file: exit $rc, expected 4"
echo "ok: a structurally malformed repo-tracked config file hard-fails (exit 4 propagated)"

# 7. Degrade target is the CORE DEFAULT, not the next-lower overlay (the
#    documented limitation the per-knob siblings share).
reset_layers
printf 'fleet_daemon_pause: true\n' >"$adopter_cfg" # valid, lower layer
printf 'fleet_daemon_pause: maybe\n' >"$mlocal_cfg" # malformed, winning layer
rc=0
out=$(run 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "degrade-to-core: exit $rc, expected 0"
[ "$out" = false ] || fail "degrade target was not the core default (got '$out')"
echo "ok: a malformed winning layer degrades to the core default"

# 8. Key absent in every layer: warn + emit the caller's --fallback, exit 0.
reset_layers
core_omit="$tmp/core-omit.yml"
printf 'max_parallel_units: 3\n' >"$core_omit"
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback false 2>/dev/null) || rc=$?
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback false 2>&1 >/dev/null) || true
[ "$rc" = 0 ] || fail "absent-in-every-layer: exit $rc, expected 0 (fallback)"
[ "$out" = false ] || fail "absent-in-every-layer: did not emit the fallback (got '$out')"
[ -n "$err" ] || fail "absent-in-every-layer: no warning emitted"
echo "ok: a key absent in every layer emits the caller's fallback with a warning"

# 8b. Malformed overlay value AND the core omits the key: degrade lands on the
#     fallback (the recoverable partial-install corner), exit 0.
reset_layers
printf 'fleet_daemon_pause: maybe\n' >"$adopter_cfg"
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback false 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "malformed overlay + core omits key: exit $rc, expected 0"
[ "$out" = false ] || fail "malformed overlay + core omits key: did not fall back (got '$out')"
echo "ok: a malformed overlay with the key absent from core falls back to the caller's fallback"

# 8c. The emitter contract holds on the FALLBACK paths too: a padded but
#     type-legal --fallback validates (the validator trims before checking)
#     and must emit TRIMMED, exactly like a resolved value — a gate-shaped
#     caller comparing "$(...)" = true would otherwise misfire on the
#     fail-safe path.
reset_layers
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback ' true ' 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "padded fallback (absent key): exit $rc, expected 0"
[ "$out" = true ] || fail "padded fallback (absent key) emitted untrimmed (got '$out')"
printf 'fleet_daemon_pause: maybe\n' >"$adopter_cfg"
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback ' true ' 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "padded fallback (degrade, core omits): exit $rc, expected 0"
[ "$out" = true ] || fail "padded fallback (degrade, core omits) emitted untrimmed (got '$out')"
echo "ok: the fallback paths emit trimmed (the sibling emitter contract)"

# 9. A malformed CORE default is a broken install (exit 5).
reset_layers
core_bad="$tmp/core-bad.yml"
printf 'fleet_daemon_pause: maybe\n' >"$core_bad"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_bad" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback false \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "malformed core default: exit $rc, expected 5 (broken install)"
echo "ok: a malformed core default is a broken install (exit 5)"

# 9b. The COMPOUND broken-install corner: a malformed winning overlay whose
#     degrade-to-core re-resolve finds the core default itself malformed is a
#     broken install (exit 5) — the degrade path's own failure arm, distinct
#     from test 9's direct core arm (no overlay) and 8b's core-omits arm.
reset_layers
printf 'fleet_daemon_pause: nope\n' >"$mlocal_cfg"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_bad" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values 'true false' --fallback false \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "malformed overlay + malformed core: exit $rc, expected 5 (broken install)"
echo "ok: a malformed overlay degrading onto a malformed core default is a broken install (exit 5)"

# 9c. Broken install: config-get missing entirely. A copy of the resolver
#     (with its sourced sanitizer, without config-get.sh) simulates it —
#     the same lonely-copy shape test-fleet-daemon-gate.sh uses.
mkdir -p "$tmp/lonely"
cp "$RCK" "$here/../scripts/echo-safety.sh" "$tmp/lonely/"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$tmp/lonely/resolve-config-knob.sh" --key fleet_daemon_pause --type enum --values 'true false' --fallback false \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "missing config-get: exit $rc, expected 5 (broken install)"
echo "ok: a missing config reader is a broken install (exit 5)"

# 10. The posint type: positive integers pass; zero, a leading zero, a negative,
#     a non-integer, and an overflow-risk value (>15 digits) are malformed.
posint_core="$tmp/core-posint.yml"
run_posint() {
  PLANWRIGHT_CONFIG_DEFAULTS="$posint_core" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RCK" --key flail_threshold --type posint --fallback 3
}
reset_layers
printf 'flail_threshold: 7\n' >"$posint_core"
got=$(run_posint)
[ "$got" = 7 ] || fail "posint: valid value did not resolve (got '$got')"
for bad in 0 05 -3 3.5 abc 1234567890123456; do
  printf 'flail_threshold: %s\n' "$bad" >"$posint_core"
  rc=0
  run_posint >/dev/null 2>&1 || rc=$?
  # A malformed value in CORE is a broken install (exit 5).
  [ "$rc" = 5 ] || fail "posint: '$bad' in core was not treated as malformed (exit $rc, expected 5)"
done
echo "ok: the posint type validates (zero, leading zero, negative, non-integer, oversize all malformed)"

# 10b. The posint type through the OVERLAY layers: a valid machine-local
#      value wins; a malformed adopter value degrades to the core default; a
#      malformed repo-tracked value hard-fails — the by-layer policy is not
#      enum-only.
reset_layers
printf 'flail_threshold: 5\n' >"$posint_core"
printf 'flail_threshold: 9\n' >"$mlocal_cfg"
got=$(run_posint)
[ "$got" = 9 ] || fail "posint: machine-local value not honored (expected 9, got '$got')"
reset_layers
printf 'flail_threshold: nope\n' >"$adopter_cfg"
rc=0
out=$(run_posint 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "posint: malformed adopter value: exit $rc, expected 0 (degrade)"
[ "$out" = 5 ] || fail "posint: malformed adopter value did not degrade to core (got '$out')"
reset_layers
printf 'flail_threshold: nope\n' >"$tracked_cfg"
rc=0
run_posint >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "posint: malformed repo-tracked value: exit $rc, expected 4 (hard-fail)"
reset_layers
echo "ok: the posint type honors the by-layer policy through the overlay layers"

# 11. Usage validation: missing/invalid arguments are usage errors (exit 2).
for args in \
  "" \
  "--key fleet_daemon_pause" \
  "--key fleet_daemon_pause --type enum --fallback false" \
  "--key fleet_daemon_pause --type enum --values 'true false'" \
  "--key Bad-Key --type enum --values 'a b' --fallback a" \
  "--key bad-key --type enum --values 'a b' --fallback a" \
  "--key fleet_daemon_pause --type banana --values 'a b' --fallback a" \
  "--key fleet_daemon_pause --type enum --values 'true false' --fallback maybe" \
  "--key fleet_daemon_pause --type enum --values 'a;b c' --fallback c" \
  "--key flail_threshold --type posint --values '1 2' --fallback 1" \
  "--key flail_threshold --type posint --fallback 0"; do
  rc=0
  # shellcheck disable=SC2086
  eval set -- $args
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RCK" "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage: args '$args' exited $rc, expected 2"
done
long_member=$(printf '%065d' 0)
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RCK" --key fleet_daemon_pause --type enum --values "true $long_member" --fallback true \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "over-length enum member: exit $rc, expected 2"
echo "ok: missing or invalid arguments are usage errors (exit 2)"

# 12. Output contract: the emitted value is newline-terminated.
reset_layers
run >"$tmp/out.txt"
[ "$(tail -c1 "$tmp/out.txt" | wc -l | tr -d ' ')" = 1 ] \
  || fail "output is not newline-terminated"
echo "ok: the emitted value is newline-terminated"

# 13. REQ-G1.5 bundle-knob sweep: every config knob the fleet-autonomy bundle
#     introduces is (a) present in the shipped config/defaults.yml, (b)
#     documented with a row in docs/options-reference.md, and (c) resolvable
#     through this shared helper against the REAL shipped defaults. Grow this
#     list as later fleet-autonomy tasks add knobs.
BUNDLE_KNOBS="fleet_daemon_pause"
shipped_defaults="$here/../config/defaults.yml"
options_ref="$here/../docs/options-reference.md"
[ -f "$shipped_defaults" ] || fail "shipped config/defaults.yml not found"
[ -f "$options_ref" ] || fail "docs/options-reference.md not found"
for knob in $BUNDLE_KNOBS; do
  grep -q "^${knob}:" "$shipped_defaults" \
    || fail "bundle knob '$knob' is not in config/defaults.yml"
  grep -q "| \`$knob\` |" "$options_ref" \
    || fail "bundle knob '$knob' has no docs/options-reference.md row"
  rc=0
  got=$(PLANWRIGHT_CONFIG_DEFAULTS="$shipped_defaults" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RCK" --key "$knob" --type enum --values 'true false' --fallback false 2>/dev/null) || rc=$?
  [ "$rc" = 0 ] || fail "bundle knob '$knob' did not resolve against the shipped defaults (exit $rc)"
  [ -n "$got" ] || fail "bundle knob '$knob' resolved to an empty value"
done
# REQ-G1.5's documentation clause is asserted by RUNNING the shipped checker
# over the real defaults + reference (a presence-grep would miss the
# consistency failures the checker exists to catch).
/bin/bash "$here/../scripts/check-options-reference.sh" >/dev/null 2>&1 \
  || fail "scripts/check-options-reference.sh failed over the shipped defaults + options reference"
echo "ok: every bundle knob is shipped, documented, and resolvable (REQ-G1.5 sweep incl. check-options-reference)"

echo "ALL PASS: resolve-config-knob"
