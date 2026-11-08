#!/bin/bash
# Tests for scripts/mc-event.sh's bounded list and its filtered prune: a
# flooded store is compacted by kind, age or submission, and list stays
# bounded on a large one (mission-control REQ-E1.3).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-event.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-event.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$tmp/work]
program_alpha_spec_root: $repo
program_alpha_home: $tmp/mchome
EOF
mkdir -p "$tmp/work"

count_lines() { printf '%s\n' "$1" | grep -c .; }

# Thirty conflict-predicted events and one of another kind, emitted a second
# apart so their ids sort by emission.
for i in $(seq 1 30); do
  mc_run mc-event.sh emit --program alpha --now $((1000 + i)) -- conflict-predicted "conflict-$i" "pair $i"
done
mc_run mc-event.sh emit --program alpha --now 1100 -- pr-ready pr-9 "nine is ready"
other_id=$OUT

mc_run mc-event.sh list --program alpha --limit 5
expect_rc "list takes a limit" 0
if [ "$(count_lines "$OUT")" -eq 5 ]; then
  ok "list stops at its limit"
else
  fail "list printed $(count_lines "$OUT") events under a limit of 5"
fi
case $ERR in
  *"31"*) ok "list says how many events it did not print" ;;
  *) fail "list did not say it stopped at its limit: $ERR" ;;
esac
mc_run mc-event.sh list --program alpha
expect_rc "list with no limit" 0
if [ "$(count_lines "$OUT")" -eq 31 ]; then
  ok "list with no limit prints every event under the default bound"
else
  fail "list printed $(count_lines "$OUT") of 31 events under the default bound"
fi

mc_run mc-event.sh prune --program alpha --kind conflict-predicted --dry-run
expect_out "a dry run names what it would prune" "would-prune${tab}30"
mc_run mc-event.sh list --program alpha
if [ "$(count_lines "$OUT")" -eq 31 ]; then
  ok "a dry run removes nothing"
else
  fail "a dry run changed the store: $(count_lines "$OUT") events left"
fi

mc_run mc-event.sh prune --program alpha --kind conflict-predicted
expect_out "a kind prune removes that kind" "pruned${tab}30"
mc_run mc-event.sh list --program alpha
if [ "$OUT" = "$other_id${tab}1100${tab}pr-ready${tab}pr-9${tab}nine is ready" ]; then
  ok "the other kinds stay"
else
  fail "the store after a kind prune: $OUT"
fi

# Age: events older than the window go; the newer one stays.
mc_run mc-event.sh emit --program alpha --now 1001 -- old-kind old-one "old"
mc_run mc-event.sh emit --program alpha --now 9000 -- old-kind new-one "new"
new_id=$OUT
mc_run mc-event.sh prune --program alpha --older-than 1h --now 10000
expect_out "an age prune removes what is older than its window" "pruned${tab}2"
mc_run mc-event.sh list --program alpha
case $OUT in
  *"$new_id"*) ok "an age prune keeps the newer events" ;;
  *) fail "an age prune removed a newer event: $OUT" ;;
esac

# Submission: only the events a target has marked submitted go.
mc_run mc-event.sh emit --program alpha --now 9100 -- conflict-predicted c-a "a"
a_id=$OUT
mc_run mc-event.sh emit --program alpha --now 9101 -- conflict-predicted c-b "b"
b_id=$OUT
mc_run mc-event.sh emit --program alpha --now 9102 -- conflict-predicted c-c "c"
c_id=$OUT
mc_run mc-event.sh mark --program alpha --target t1 submitted "$a_id" "$b_id"
mc_run mc-event.sh prune --program alpha --kind conflict-predicted --submitted --target t1
expect_out "a submitted prune removes what the target marked submitted" "pruned${tab}2"
mc_run mc-event.sh list --program alpha
case $OUT in
  *"$c_id"*) ok "a submitted prune keeps what the target has not submitted" ;;
  *) fail "a submitted prune removed an event the target had not submitted: $OUT" ;;
esac
case $OUT in
  *"$a_id"* | *"$b_id"*) fail "a submitted prune kept a submitted event" ;;
  *) ok "a submitted prune removes its submitted events" ;;
esac

# A submitted prune keeps an event a target that holds marks has not submitted.
mc_run mc-event.sh emit --program alpha --now 9200 -- conflict-predicted c-d "d"
d_id=$OUT
mc_run mc-event.sh mark --program alpha --target t2 staged "$d_id"
mc_run mc-event.sh mark --program alpha --target t1 submitted "$d_id"
mc_run mc-event.sh prune --program alpha --kind conflict-predicted --submitted --target t1
expect_out "a submitted prune skips an event another target has not submitted" "pruned${tab}0"
mc_run mc-event.sh list --program alpha
case $OUT in
  *"$d_id"*) ok "the event another target has not submitted stays" ;;
  *) fail "a submitted prune removed an event another target has not submitted" ;;
esac

# An empty filter value is refused, never read as no filter.
mc_run mc-event.sh prune --program alpha --kind ""
expect_rc "an empty kind is refused" 2
mc_run mc-event.sh prune --program alpha --kind conflict-predicted --older-than ""
expect_rc "an empty age is refused" 2

# The default bound on a store larger than it.
rm -rf "$fleet/attention/mission-control/alpha"
ev="$fleet/attention/mission-control/alpha/events"
mkdir -p "$ev"
for i in $(seq 1 501); do
  printf '2000\tbulk-kind\tbulk-%s\tbulk\n' "$i" >"$ev/e2000.$(printf '%x' "$i")"
done
mc_run mc-event.sh list --program alpha
expect_rc "list over a larger store" 0
if [ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 500 ]; then
  ok "the default bound prints 500 of a larger store"
else
  fail "the default bound printed $(printf '%s\n' "$OUT" | grep -c .) of 501 events"
fi
case $ERR in
  *"listed the first 500 of 501"*) ok "and says how many it left out" ;;
  *) fail "the default bound did not say what it left out: $ERR" ;;
esac

if [ "$failures" -ne 0 ]; then
  echo "test-mc-event: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-event: all passed"
