#!/bin/bash
# Tests for scripts/resolve-notification-channel.sh — the notification_channel
# knob resolver (orchestration-fleet Task 12: D-13, REQ-E1.4, REQ-A1.5).
#
# notification_channel is the attention/notification capability's SEAM: which
# channel a fleet notification is pushed through — `none` (the pull-only
# default: the operator reads the decision queue, nothing is pushed),
# `tmux-popup` (a multiplexer popup), `os-notify` (an OS notification), or
# `editor-toast` (an editor toast the editor tails). It is the capability-vs-
# style split (REQ-A1.5): the capability (a notification seam) lives in core;
# the specific channel VALUE is overlay-owned. It is *config*, so it resolves
# THROUGH config-get (the four-layer overlay reader — no layer logic is
# re-implemented here, REQ-D1.1); this resolver adds only the enum validation
# and the REQ-E1.4 by-layer malformed policy config-get cannot apply because the
# test is semantic (the legal enum), not structural. Output is the single
# validated channel on stdout. Mirrors resolve-context-budget-threshold.sh /
# resolve-dispatch-isolation.sh.
#
# What is covered:
#   - the default (no overlays) resolves to the safe `none` channel;
#   - the knob resolves across all four layers via config-get (last-layer-wins);
#   - every legal channel value validates;
#   - a trailing comment and surrounding whitespace are tolerated;
#   - the REQ-E1.4 by-layer policy on a bad value: adopter/machine-local
#     degrade+warn to the core default, repo-tracked hard-fails (exit 4);
#   - a structurally malformed repo-tracked config file still hard-fails;
#   - the knob absent in every layer (broken/partial install) degrades to the
#     safe default with a loud warning (exit 0);
#   - the output contract: a single newline-terminated value line.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-notification-channel.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RNC="$here/../scripts/resolve-notification-channel.sh"

# The shipped-style safe default (kept in sync with config/defaults.yml and the
# resolver's own fallback constant): the pull-only, dependency-free channel.
SAFE_DEFAULT=none

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RNC" ] || fail "scripts/resolve-notification-channel.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- Config layer fixtures, wired through config-get's env overrides exactly as
#     test-resolve-context-budget-threshold.sh does (hermetic: no $HOME, no git
#     top).
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped-style core default: the safe pull-only channel.
printf 'notification_channel: %s\n' "$SAFE_DEFAULT" >"$core_cfg"

# The resolver takes no arguments (the key is fixed), so `run` passes none.
run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$RNC"
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# 1. Default (no overlays) resolves to the safe pull-only channel.
reset_layers
got=$(run)
[ "$got" = "$SAFE_DEFAULT" ] \
  || fail "default did not resolve to the safe default (expected '$SAFE_DEFAULT', got '$got')"
echo "ok: the default notification_channel is the safe pull-only channel"

# 2. Four-layer resolution via config-get: a machine-local value wins.
reset_layers
printf 'notification_channel: os-notify\n' >"$mlocal_cfg"
got=$(run)
[ "$got" = os-notify ] || fail "machine-local value not honored (expected 'os-notify', got '$got')"
echo "ok: an overlay-set value resolves through the four layers"

# 2b. Last-layer-wins: repo-tracked overrides adopter overrides core.
reset_layers
printf 'notification_channel: tmux-popup\n' >"$adopter_cfg"
printf 'notification_channel: editor-toast\n' >"$tracked_cfg"
got=$(run)
[ "$got" = editor-toast ] || fail "repo-tracked did not win over adopter (got: '$got')"
rm -f "$tracked_cfg"
got=$(run)
[ "$got" = tmux-popup ] || fail "adopter did not win over core after repo-tracked removed (got: '$got')"
echo "ok: notification_channel obeys last-layer-wins (core < adopter < repo-tracked < machine-local)"

# 3. Every legal channel value validates.
for ch in none tmux-popup os-notify editor-toast; do
  reset_layers
  printf 'notification_channel: %s\n' "$ch" >"$tracked_cfg"
  got=$(run)
  [ "$got" = "$ch" ] || fail "legal channel '$ch' did not validate (got: '$got')"
done
echo "ok: every legal channel value (none, tmux-popup, os-notify, editor-toast) validates"

# 4. A trailing comment and surrounding whitespace are tolerated.
reset_layers
printf 'notification_channel:   os-notify   # laptop\n' >"$tracked_cfg"
got=$(run)
[ "$got" = os-notify ] || fail "whitespace/comment not tolerated (got: '$got')"
echo "ok: inner whitespace and a trailing comment are tolerated"

# 5. Bad value in the adopter overlay: malformed, degrade to the core default
#    with a loud warning, exit 0. A near-miss (wrong case, a plausible typo, an
#    empty value) is malformed too.
for bad in slack Os-Notify tmuxpopup ''; do
  reset_layers
  printf 'notification_channel: %s\n' "$bad" >"$adopter_cfg"
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
echo "ok: invalid values in the adopter overlay degrade to core with a warning"

# 5b. Bad value in machine-local also degrades.
reset_layers
printf 'notification_channel: pushover\n' >"$mlocal_cfg"
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
printf 'notification_channel: slack\n' >"$tracked_cfg"
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
printf 'notification_channel:\n  - none\n' >"$tracked_cfg"
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] \
  || fail "structurally malformed repo-tracked file: exit $rc, expected 4 (propagated hard-fail)"
echo "ok: a structurally malformed repo-tracked config file hard-fails (exit 4 propagated)"

# 7b. Documented degrade target — the CORE DEFAULT, not a strict per-layer
#     cascade (config-get exposes only the merged winning value). A malformed
#     winning layer with a valid lower layer still degrades to the core default.
reset_layers
printf 'notification_channel: os-notify\n' >"$adopter_cfg" # valid, lower layer
printf 'notification_channel: bad\n' >"$mlocal_cfg"        # malformed, winning layer
rc=0
out=$(run 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "degrade-to-core (valid lower layer): exit $rc, expected 0"
[ "$out" = "$SAFE_DEFAULT" ] \
  || fail "degrade target was not the core default (got '$out'; documented behavior is core, not the valid adopter 'os-notify')"
echo "ok: a malformed winning layer degrades to the core default (documented, not strict next-lower)"

# 8. The knob absent in every layer (broken/partial install) degrades to the
#    safe default with a loud warning, exit 0.
reset_layers
core_omit="$tmp/core-omit.yml"
printf 'max_parallel_units: 3\n' >"$core_omit"
rc=0
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RNC" 2>/dev/null) || rc=$?
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$RNC" 2>&1 >/dev/null) || true
[ "$rc" = 0 ] || fail "knob absent everywhere: exit $rc, expected 0 (degrade)"
[ "$out" = "$SAFE_DEFAULT" ] || fail "knob absent everywhere: did not fall back to the safe default (got '$out')"
case $err in
  *broken* | *partial* | *fall*) ;;
  *) fail "knob absent everywhere: warning is not loud about the broken/partial install (got: '$err')" ;;
esac
echo "ok: the knob absent in every layer falls back to the safe default with a loud warning"

# 9. Output contract: a single newline-terminated value line, nothing else.
reset_layers
printf 'notification_channel: editor-toast\n' >"$tracked_cfg"
lines=$(run | wc -l | tr -d ' ')
[ "$lines" = 1 ] || fail "output is not exactly one line (got $lines lines)"
echo "ok: the output is a single newline-terminated value line"

echo "PASS: resolve-notification-channel.sh"
