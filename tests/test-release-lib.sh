#!/bin/bash
# Tests for scripts/release-lib.sh — the version comparator rl_version_gt, the
# layer below the release "pending" definition (release-hardening Task 1; D-6;
# REQ-E1.1, REQ-E1.2).
#
# Contract under test (semver.org 2.0.0 §11 precedence, the surface the
# `pending` comparator never reaches — `pending` only ever compares
# release-vs-release, so a prerelease-ordering regression ships silently
# without this suite):
#   - two prereleases: `-rc.1 < -rc.2` (numeric identifiers compared
#     numerically);
#   - a numeric identifier ranks BELOW an alphanumeric one (`-1 < -alpha`);
#   - fewer prerelease fields rank lower when the shared prefix is equal
#     (`-alpha < -alpha.1`);
#   - a prerelease ranks below its associated release (`1.0.0-rc.1 < 1.0.0`);
#   - build metadata is accepted and ignored for precedence
#     (`1.0.0+build == 1.0.0`).
# Plus a boundary case at a safe, non-overflowing numeric-identifier width
# (REQ-E1.2): the 64-bit overflow is a documented in-code limit, not guarded,
# so this asserts current ranking well within the signed-64-bit range rather
# than probing the overflow itself.
#
# This unit adds no behavior: D-6 mandates no change to the comparator's
# arithmetic. These assertions pin the currently-correct precedence surface so
# a future regression is caught; each was validated non-vacuous by mutation
# injection during development (a deliberately broken comparator turns the
# matching assertion red).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
LIB="$here/../scripts/release-lib.sh"
failures=0

[ -r "$LIB" ] || {
  echo "FAIL: scripts/release-lib.sh missing or not readable" >&2
  exit 1
}

# shellcheck source=/dev/null
. "$LIB"

# assert_gt <desc> <a> <b> — expect rl_version_gt <a> <b> to succeed (a > b).
assert_gt() {
  if rl_version_gt "$2" "$3"; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$2] > [$3]" >&2
    failures=$((failures + 1))
  fi
}

# assert_not_gt <desc> <a> <b> — expect rl_version_gt <a> <b> to fail (a !> b).
assert_not_gt() {
  if rl_version_gt "$2" "$3"; then
    echo "FAIL: $1 — expected [$2] NOT > [$3]" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}

# assert_lt <desc> <lower> <higher> — assert <lower> ranks strictly below
# <higher>: the higher IS greater, and the lower is NOT greater (both
# directions, so a comparator that returned 0 unconditionally cannot pass).
assert_lt() {
  assert_gt "$1 — higher > lower" "$3" "$2"
  assert_not_gt "$1 — lower !> higher" "$2" "$3"
}

# assert_eq_prec <desc> <a> <b> — assert equal precedence: neither is greater.
assert_eq_prec() {
  assert_not_gt "$1 — a !> b" "$2" "$3"
  assert_not_gt "$1 — b !> a" "$3" "$2"
}

# --- Case 1: two prereleases, -rc.1 < -rc.2 (numeric identifiers numerically).
assert_lt "rc.1 < rc.2 (numeric prerelease identifiers compared numerically)" \
  "1.0.0-rc.1" "1.0.0-rc.2"
# Numeric, not lexical: 11 > 2 numerically (a lexical compare would rank "11"
# below "2").
assert_lt "beta.2 < beta.11 (numeric, not lexical, ordering)" \
  "1.0.0-beta.2" "1.0.0-beta.11"

# --- Case 2: a numeric identifier ranks BELOW an alphanumeric one.
assert_lt "numeric identifier ranks below alphanumeric (1 < alpha)" \
  "1.0.0-1" "1.0.0-alpha"

# --- Case 3: fewer prerelease fields rank lower (shared prefix equal).
assert_lt "fewer fields rank lower (alpha < alpha.1)" \
  "1.0.0-alpha" "1.0.0-alpha.1"

# --- Case 4: a prerelease ranks below its associated release.
assert_lt "prerelease ranks below its release (1.0.0-rc.1 < 1.0.0)" \
  "1.0.0-rc.1" "1.0.0"

# The full semver.org §11 worked example, as a chain, to lock the ordering
# these individual cases compose into.
assert_lt "chain: alpha < alpha.1" "1.0.0-alpha" "1.0.0-alpha.1"
assert_lt "chain: alpha.1 < alpha.beta" "1.0.0-alpha.1" "1.0.0-alpha.beta"
assert_lt "chain: alpha.beta < beta" "1.0.0-alpha.beta" "1.0.0-beta"
assert_lt "chain: beta < beta.2" "1.0.0-beta" "1.0.0-beta.2"
assert_lt "chain: beta.2 < beta.11" "1.0.0-beta.2" "1.0.0-beta.11"
assert_lt "chain: beta.11 < rc.1" "1.0.0-beta.11" "1.0.0-rc.1"
assert_lt "chain: rc.1 < 1.0.0" "1.0.0-rc.1" "1.0.0"

# --- Case 5: build metadata is accepted and ignored for precedence.
assert_eq_prec "build metadata ignored (1.0.0+build.99 == 1.0.0)" \
  "1.0.0+build.99" "1.0.0"
assert_eq_prec "differing build metadata compares equal (1.0.0+a == 1.0.0+b)" \
  "1.0.0+a" "1.0.0+b"
assert_eq_prec "build metadata does not leak into prerelease compare" \
  "1.0.0-rc.1+build" "1.0.0-rc.1"
# Accepted: a build-metadata-bearing version still ranks by its core.
assert_lt "build metadata accepted, core still ranks (1.0.0+b < 1.0.1+b)" \
  "1.0.0+b" "1.0.1+b"

# --- Core major/minor/patch precedence (the numeric arithmetic path).
assert_lt "patch ordering (1.0.0 < 1.0.1)" "1.0.0" "1.0.1"
assert_lt "minor ordering (1.0.9 < 1.1.0)" "1.0.9" "1.1.0"
assert_lt "major ordering (1.9.9 < 2.0.0)" "1.9.9" "2.0.0"
# Numeric, not lexical, on the core too (10 > 2 numerically).
assert_lt "minor numeric not lexical (0.2.0 < 0.10.0)" "0.2.0" "0.10.0"
assert_eq_prec "identical releases are equal (1.2.3 == 1.2.3)" "1.2.3" "1.2.3"

# --- Case 6 (REQ-E1.2): boundary at a safe, non-overflowing numeric width.
# 18-digit numeric prerelease identifiers sit well inside the signed 64-bit
# range (max 9223372036854775807, 19 digits), so the comparator's `10#`
# arithmetic ranks them correctly. This asserts current behavior below the
# documented overflow limit; it does NOT probe the overflow, which is an
# unguarded documented limit (D-6, and the in-code comment on rl_version_gt).
assert_lt "safe wide numeric prerelease width (18 digits, below 2^63)" \
  "1.0.0-rc.999999999999999998" "1.0.0-rc.999999999999999999"
# Same safe-width comparison on the core numeric (major) path.
assert_lt "safe wide numeric core width (18 digits, below 2^63)" \
  "999999999999999998.0.0" "999999999999999999.0.0"

# --- Case 7 (REQ-A1.1, D-2): the comparator-error status. rl_version_gt
# validates both operands against rl_valid_semver at entry and signals a distinct
# exit 2 for a malformed or unusable operand — separate from a valid "not
# greater" (exit 1) and a valid "greater" (exit 0) — so a caller can tell a
# comparator failure from a negative comparison and fail closed on it. Every
# caller pre-validates its operands today, so this status is unreachable via real
# inputs; this unit test drives it directly (the defense-in-depth contract).
#
# assert_status <desc> <expected-status> <a> <b>. rl_version_gt's stderr is
# discarded: a malformed operand also trips bash's `10#` arithmetic in the
# pre-change comparator (the exact noise this exit-2 contract replaces), and the
# assertion is on the STATUS, three-way.
assert_status() {
  local got=0
  rl_version_gt "$3" "$4" 2>/dev/null || got=$?
  if [ "$got" = "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected status $2, got $got" >&2
    failures=$((failures + 1))
  fi
}

assert_status "malformed first operand → error status 2" 2 "not-a-version" "1.0.0"
assert_status "malformed second operand → error status 2" 2 "1.0.0" "not-a-version"
assert_status "both operands malformed → error status 2" 2 "nope" "nope"
assert_status "empty first operand → error status 2" 2 "" "1.0.0"
assert_status "empty second operand → error status 2" 2 "1.0.0" ""
# A leading-zero numeric prerelease identifier is malformed SemVer (§9): it must
# reach the error status, not be silently compared (the same malformed spelling
# rl_valid_semver rejects for the callers).
assert_status "malformed (leading-zero prerelease) operand → error status 2" \
  2 "1.0.0-01" "1.0.0"
# The error status is DISTINCT from both valid comparison results, so a caller
# switching on it three-way (0 pending · 1 none · 2 fail-closed) is well-defined.
assert_status "valid, not greater → status 1 (distinct from the error status)" \
  1 "1.0.0" "1.0.0"
assert_status "valid, strictly greater → status 0 (distinct from the error status)" \
  0 "1.0.1" "1.0.0"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-lib.sh"
