#!/bin/bash
# Tests for the snapshot adapters behind scripts/mc-snapshot.sh: the shipped
# forge adapter (scripts/mc-adapter-forge.sh), a failing or rate-limited
# fixture adapter, the throttle, and the adapter catalog's grammar
# (mission-control REQ-M1.1, REQ-H1.4, REQ-L1.2; D-12).
#
# The forge is faked by a gh shim on PATH that logs each call; a second
# source is a fixture adapter registered through the repo-tracked overlay.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-snapshot-adapters.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-snapshot.sh" ] || {
  echo "FAIL: scripts/mc-snapshot.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

# shellcheck source=tests/lib/mc-snapshot-fixture.sh
. "$here/lib/mc-snapshot-fixture.sh"

# ---------------------------------------------------------------------------
# The forge adapter's own reads: the tracked set, the rate-limit epoch, an
# unreadable diff.
# ---------------------------------------------------------------------------
setup
printf '%s\n' "mission_control_forge_tracked: authored" >>"$tracked"
mc_run mc-snapshot.sh refresh --program alpha --source forge --now 1000
mc_run mc-snapshot.sh read --program alpha forge --now 1000
expect_out "D-12: the authored set keeps the viewer's pull request" "pr${tab}acme/widgets${tab}7${tab}"
expect_no_out "D-12: and drops another author's" "pr${tab}acme/widgets${tab}9${tab}"

setup
GH_REMAINING=10 mc_run mc-adapter-forge.sh refresh --program alpha --out "$tmp/forge.out"
expect_out "the adapter reports the reset as an epoch" "ratelimit${tab}10${tab}9000000"

setup
GH_DIFF_FAIL=1 mc_run mc-snapshot.sh refresh --program alpha --source forge --now 1000
expect_out "an unreadable diff does not fail the snapshot" "refreshed${tab}forge"
mc_run mc-snapshot.sh read --program alpha forge --now 1000
expect_out "its patch id is unknown" "${tab}SUCCESS${tab}3${tab}4${tab}-"
mc_run mc-snapshot.sh refresh --program alpha --source forge --now 1400
if [ "$(gh_calls 'pr diff')" -eq 4 ]; then
  ok "an unknown patch id is read again next time"
else
  fail "an unknown patch id was not re-read ($(gh_calls 'pr diff') diff reads)"
fi

# ---------------------------------------------------------------------------
# The --source filter; a failed adapter; a cleared hold; the throttle.
# ---------------------------------------------------------------------------
setup
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
expect_eq "REQ-M1.1: --source refreshes that source alone" "refreshed${tab}tracker"
if [ "$(gh_calls 'api graphql')" -eq 0 ]; then
  ok "REQ-M1.1: a second source refreshes without a forge read"
else
  fail "REQ-M1.1: refreshing the tracker read the forge"
fi
TRACKER_EXIT=1 mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 2000
expect_rc "a failed adapter fails the refresh" 1
expect_out "and is reported" "failed${tab}tracker${tab}1"
mc_run mc-snapshot.sh read --program alpha tracker --now 2000
expect_out "the last good snapshot stays, aging" "age${tab}1000${tab}"

setup
TRACKER_RL="0${tab}2500" mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
TRACKER_RL="900${tab}9000" mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 2600
expect_out "a read past the reset lands" "refreshed${tab}tracker"
if [ ! -f "$fleet/mission-control/alpha/snapshots/tracker.hold" ]; then
  ok "headroom above the floor clears the hold"
else
  fail "the hold outlived a read with headroom"
fi

setup
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1900 --rung throttle
expect_out "REQ-L1.2: at a rung above normal every cadence doubles" "fresh${tab}tracker${tab}900"
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1900 --rung normal
expect_out "at normal it does not" "refreshed${tab}tracker"

# A truncated snapshot is refused, never read as age zero.
setup
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
printf 'format\t1\n' >"$fleet/mission-control/alpha/snapshots/tracker"
mc_run mc-snapshot.sh read --program alpha tracker --now 1000
expect_rc "a snapshot cut short is refused" 1

# ---------------------------------------------------------------------------
# REQ-H1.4: the adapter catalog's own grammar fails the check, named.
# ---------------------------------------------------------------------------
bad_adapter() { # bad_adapter <label> <needle> <entry fields...>
  ba_label=$1
  ba_needle=$2
  shift 2
  setup
  {
    printf 'adapters:\n  - id: tracker\n'
    printf '    %s\n' "$@"
  } >"$repo/.claude/catalogs/snapshot-adapters.yaml"
  mc_run mc-snapshot.sh check --program alpha
  expect_rc "REQ-H1.4: $ba_label" 1
  expect_err "REQ-H1.4: $ba_label, named" "$ba_needle"
}
bad_adapter "an adapter with no summary" "summary: missing" "script: scripts/tracker-adapter.sh" "cadence: 10m"
bad_adapter "an adapter script climbing out" "script: not a relative path" 'summary: "x"' "script: ../tracker-adapter.sh" "cadence: 10m"
bad_adapter "an adapter with a bad cadence" "cadence '10 minutes'" 'summary: "x"' "script: scripts/tracker-adapter.sh" 'cadence: "10 minutes"'

if [ "$failures" -ne 0 ]; then
  echo "test-mc-snapshot-adapters: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-snapshot-adapters: all passed"
