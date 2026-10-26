#!/bin/bash
# Tests for scripts/mc-snapshot.sh and scripts/mc-adapter-forge.sh — one
# age-stamped snapshot per snapshot-mode source per program, shared by every
# duty, through a source-agnostic adapter seam (mission-control REQ-M1.1,
# REQ-H1.4, REQ-A1.2, REQ-L1.2; D-12).
#
# The forge is faked by a gh shim on PATH that logs each call; a second
# source is a fixture adapter registered through the repo-tracked overlay.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-snapshot.sh
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
# REQ-M1.1: one forge read per cadence however many duties read it; each
# snapshot carries its age; a second source refreshes through the same seam.
# ---------------------------------------------------------------------------
setup
mc_run mc-snapshot.sh refresh --program alpha --now 1000
expect_rc "REQ-M1.1: the first refresh" 0
expect_out "REQ-M1.1: the forge is read" "refreshed${tab}forge"
expect_out "REQ-H1.4: the fixture second source produces its own snapshot" "refreshed${tab}tracker"
if [ "$(gh_calls 'api graphql')" -eq 1 ]; then
  ok "REQ-M1.1: one GraphQL read for the forge"
else
  fail "REQ-M1.1: expected one GraphQL read, got $(gh_calls 'api graphql')"
fi
if [ "$(gh_calls 'pr diff')" -eq 2 ]; then
  ok "REQ-M1.1: one diff read per new head, for its patch id"
else
  fail "REQ-M1.1: expected two diff reads, got $(gh_calls 'pr diff')"
fi

mc_run mc-snapshot.sh read --program alpha forge --now 1060
expect_rc "REQ-M1.1: a duty reads the forge snapshot" 0
expect_out "REQ-M1.1: the snapshot reports its age and mode" "source${tab}forge${tab}mode${tab}snapshot${tab}age${tab}60${tab}cadence${tab}300${tab}fresh"
expect_out "REQ-M1.1: the forge row carries head, draft, mergeability, review, threads, checks, reviews, comments" \
  "pr${tab}acme/widgets${tab}7${tab}${head1}${tab}false${tab}MERGEABLE${tab}APPROVED${tab}2${tab}SUCCESS${tab}3${tab}4${tab}"
expect_out "REQ-M1.1: a draft with no decision and no checks reads NONE" \
  "pr${tab}acme/widgets${tab}9${tab}${head1}${tab}true${tab}UNKNOWN${tab}NONE${tab}0${tab}NONE${tab}0${tab}1${tab}"
first=$OUT
patch7=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "pr" && $3 == 7 { print $12 }')
case $patch7 in
  "" | - | *[!0-9a-f]*) fail "REQ-M1.1: no patch id on #7 ($patch7)" ;;
  *) ok "REQ-M1.1: the row carries a patch id" ;;
esac
mc_run mc-snapshot.sh read --program alpha forge --now 1061
mc_run mc-snapshot.sh refresh --program alpha --now 1100
expect_out "REQ-M1.1: a second refresh inside the cadence does not read" "fresh${tab}forge${tab}100"
if [ "$(gh_calls 'api graphql')" -eq 1 ]; then
  ok "REQ-M1.1: two duties and two refreshes inside one cadence cost one forge read"
else
  fail "REQ-M1.1: the forge was read $(gh_calls 'api graphql') times inside one cadence"
fi
if [ "$(tracker_reads)" -eq 1 ]; then
  ok "REQ-M1.1: the second source was read once"
else
  fail "REQ-M1.1: the tracker was read $(tracker_reads) times"
fi

mc_run mc-snapshot.sh read --program alpha forge --now 1301
expect_out "REQ-M1.1: a snapshot older than its cadence reports its age as stale" "age${tab}301${tab}cadence${tab}300${tab}stale"

mc_run mc-snapshot.sh refresh --program alpha --now 1400
expect_out "REQ-M1.1: the forge refreshes on its cadence" "refreshed${tab}forge"
expect_out "REQ-M1.1: the tracker refreshes on its own, longer cadence" "fresh${tab}tracker${tab}400"
if [ "$(gh_calls 'pr diff')" -eq 2 ]; then
  ok "D-12: an unchanged head carries its patch id with no diff read"
else
  fail "D-12: an unchanged head cost $(($(gh_calls 'pr diff') - 2)) diff read(s)"
fi
mc_run mc-snapshot.sh read --program alpha forge --now 1400
if [ "$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "pr" && $3 == 7 { print $12 }')" = "$patch7" ]; then
  ok "D-12: the carried patch id is the same"
else
  fail "D-12: the patch id changed over an unchanged head"
fi
GH_HEAD=$head2
mc_run mc-snapshot.sh refresh --program alpha --now 1800
if [ "$(gh_calls 'pr diff')" -eq 4 ]; then
  ok "D-12: a moved head re-reads its diff"
else
  fail "D-12: expected a diff read per moved head, total $(gh_calls 'pr diff')"
fi
GH_HEAD=$head1
[ -n "$first" ] || fail "no first read"

mc_run mc-snapshot.sh list --program alpha --now 1900
expect_out "REQ-H1.4: list names each class's mode and age" "code-state${tab}forge${tab}snapshot${tab}100"
expect_out "REQ-H1.4: a record source has no age" "decisions${tab}specs${tab}record${tab}-"
expect_out "REQ-H1.4: a class the map leaves out is cited" "designs${tab}-${tab}cited${tab}-"

# ---------------------------------------------------------------------------
# REQ-M1.1: exhausted rate-limit headroom delays the next read instead of
# polling.
# ---------------------------------------------------------------------------
setup
TRACKER_RL="0${tab}4000" mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
expect_out "the read that reports exhausted headroom still lands" "refreshed${tab}tracker"
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 2000
expect_out "REQ-M1.1: past its cadence, the source waits for the reset" "held${tab}tracker${tab}4000"
if [ "$(tracker_reads)" -eq 1 ]; then
  ok "REQ-M1.1: a held source is not polled"
else
  fail "REQ-M1.1: a held source was polled ($(tracker_reads) reads)"
fi
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 4001
expect_out "REQ-M1.1: after the reset the source is read again" "refreshed${tab}tracker"

setup
TRACKER_EXIT=75 mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
expect_out "an adapter refused for its rate limit is held" "held${tab}tracker${tab}1600"
mc_run mc-snapshot.sh read --program alpha tracker --now 1000
expect_rc "a refused read leaves no snapshot" 3

setup
GH_LIMITED=1 mc_run mc-snapshot.sh refresh --program alpha --source forge --now 1000
expect_out "the forge adapter turns a rate-limit refusal into exit 75" "held${tab}forge${tab}1300"
setup
GH_REMAINING=10 mc_run mc-snapshot.sh refresh --program alpha --source forge --now 1000
mc_run mc-snapshot.sh refresh --program alpha --source forge --now 3000
expect_out "the forge's low headroom (under the floor) holds it, clamped to an hour" "held${tab}forge${tab}4600"

# ---------------------------------------------------------------------------
# REQ-L1.2: every snapshot-mode source's polls count against one cap.
# ---------------------------------------------------------------------------
setup 3
mc_run mc-snapshot.sh refresh --program alpha --now 1000
mc_run mc-snapshot.sh refresh --program alpha --now 1700
expect_out "REQ-L1.2: the third poll is the tracker's second" "refreshed${tab}tracker"
expect_out "REQ-L1.2: the forge's second read is over the shared cap" "capped${tab}forge"
if [ "$(gh_calls 'api graphql')" -eq 1 ]; then
  ok "REQ-L1.2: a capped source is not read"
else
  fail "REQ-L1.2: a capped source was read"
fi

# ---------------------------------------------------------------------------
# The daemon pause; an unknown snapshot format.
# ---------------------------------------------------------------------------
setup
printf '%s\n' "fleet_daemon_pause: true" >>"$tracked"
mc_run mc-snapshot.sh refresh --program alpha --now 1000
expect_eq "the daemon pause reads nothing" "paused"
if [ ! -f "$GH_LOG" ]; then
  ok "a paused refresh made no forge call"
else
  fail "a paused refresh called the forge"
fi

setup
mc_run mc-snapshot.sh refresh --program alpha --source tracker --now 1000
sed 's/^format\t1$/format\t7/' "$fleet/mission-control/alpha/snapshots/tracker" >"$tmp/s"
cp "$tmp/s" "$fleet/mission-control/alpha/snapshots/tracker"
mc_run mc-snapshot.sh read --program alpha tracker --now 1000
expect_rc "D-8: a snapshot of unknown format is refused" 1
expect_err "D-8: the refusal names the format" "format"

# ---------------------------------------------------------------------------
# REQ-H1.4: a snapshot source with no registered adapter fails check:duties,
# the source named.
# ---------------------------------------------------------------------------
setup
mc_run mc-snapshot.sh check --program alpha
expect_rc "REQ-H1.4: every snapshot source has an adapter" 0
mc_run mc-snapshot.sh check --defaults
expect_rc "REQ-H1.4: the default map's forge has the shipped adapter" 0
sed 's/tracker:snapshot/jira:snapshot/' "$tracked" >"$tmp/t" && cp "$tmp/t" "$tracked"
mc_run mc-snapshot.sh check --program alpha
expect_rc "REQ-H1.4: a snapshot source with no adapter fails the check" 1
expect_err "REQ-H1.4: the source is named" "alpha: sources: snapshot source 'jira' has no registered adapter"
mc_run mc-snapshot.sh refresh --program alpha --now 1000
expect_rc "REQ-H1.4: a refresh over an adapter-less source fails" 1
expect_out "REQ-H1.4: the sources that have adapters still refresh" "refreshed${tab}forge"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-snapshot: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-snapshot: all passed"
