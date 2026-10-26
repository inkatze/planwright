#!/bin/bash
# Tests for scripts/mc-shadow.sh — the shadow lifecycle: a shadow duty's
# operator items become would-have entries and nothing is raised, a live
# duty's reach the attention store, and promotion is suggested after the
# configured count of agreed entries (mission-control REQ-C1.6).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-shadow.sh
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

[ -f "$repo_root/scripts/mc-shadow.sh" ] || {
  echo "FAIL: scripts/mc-shadow.sh missing" >&2
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
# shellcheck source=tests/lib/mc-autonomy-fixture.sh
. "$here/lib/mc-autonomy-fixture.sh"

tab=$(printf '\t')
shadow() { mc_run mc-shadow.sh "$@"; }
field() { printf '%s\n' "$1" | cut -f "$2"; }
month=$(date -u '+%Y-%m')
events() { mc_run mc-event.sh list --program alpha; }

# ---------------------------------------------------------------------------
# REQ-C1.6: a shadow duty writes would-have entries and raises nothing.
# ---------------------------------------------------------------------------
shadow raise --program alpha --duty gamma-duty -- gamma-item pr-12 "would ask the operator to merge"
expect_rc "a shadow duty's item is accepted" 0
expect_out "it becomes a would-have entry" "would-have${tab}would-have-"
w1=$(field "$OUT" 2)
case $(cat "$kb/would-have-$month.log") in
  *"$w1${tab}"*"${tab}pr-12${tab}gamma-item: would ask the operator to merge${tab}"*"${tab}gamma-duty") ok "the entry names the duty, the item kind and its text" ;;
  *) fail "the would-have entry is not as expected: $(cat "$kb/would-have-$month.log")" ;;
esac
events
expect_eq "nothing was raised for the shadow duty" ""

shadow raise --program alpha --duty alpha-duty -- alpha-item pr-12 "merge order changed"
expect_rc "a live duty's item is raised" 0
expect_out "it is reported as raised" "raised${tab}e"
events
expect_out "the live item is in the attention store" "${tab}alpha-item${tab}pr-12${tab}merge order changed"

shadow raise --program alpha --duty beta-duty -- beta-item pr-12 "x"
expect_rc "an off duty raises nothing" 1
shadow raise --program alpha --duty gamma-duty -- alpha-item pr-12 "x"
expect_rc "a kind the duty does not declare is refused" 2
shadow raise --program alpha --duty gamma-duty -- gamma-item "pr 12" "x"
expect_rc "a subject outside the event grammar is refused in shadow too" 2

# ---------------------------------------------------------------------------
# Promotion is suggested after the configured count of agreed entries.
# ---------------------------------------------------------------------------
printf '%s\n' "mission_control_shadow_promote_after: 2" >>"$tracked"
shadow promotion --program alpha
expect_rc "promotion reads" 0
expect_eq "a shadow duty short of the count stays in shadow" "shadow${tab}gamma-duty${tab}0${tab}2"
shadow agree --program alpha "$w1"
expect_rc "the operator's agreement is recorded" 0
shadow agree --program alpha "$w1"
expect_rc "an entry is agreed once" 1
shadow agree --program alpha would-have-190001-1
expect_rc "agreeing with no such entry is refused" 1
shadow raise --program alpha --duty gamma-duty -- gamma-item pr-13 "would ask again"
w2=$(field "$OUT" 2)
shadow agree --program alpha "$w2"
shadow promotion --program alpha
expect_eq "the configured count suggests promotion" "promote${tab}gamma-duty${tab}2${tab}2"
if grep -q 'lifecycle: shadow' "$repo/.claude/catalogs/duties.yaml"; then
  ok "promotion is a suggestion: the catalog is untouched"
else
  fail "promotion edited the catalog"
fi
events
expect_no_out "agreement and promotion raise nothing" "gamma"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-shadow tests passed"
