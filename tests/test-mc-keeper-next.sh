#!/bin/bash
# Tests for `scripts/mc-keeper.sh next`: the dispatch suggestions come from
# the orchestrator's own selection, so a task whose own or whose dependency's
# repository the selection withholds is never suggested
# (mission-control REQ-M1.9; D-40).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-next.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SCRIPTS=$repo_root/scripts
TAB=$(printf '\t')
# shellcheck source=tests/lib/two-repo-fixture.sh
. "$here/lib/two-repo-fixture.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

trf_setup "$SCRIPTS" || {
  echo "FAIL: the two-repository fixture could not be built" >&2
  exit 1
}
trap trf_teardown EXIT
BUNDLE=$TRF_ROOT/demo

# The fixture's work repository is the program's repository; its adopter layer
# carries the program, the shipped mission-control knobs the core layer.
grep -E '^(mission_control_|fleet_daemon_pause:|quota_ledger_retention_days:)' "$repo_root/config/defaults.yml" >"$TRF/core.yml"
cat >"$TRF/adopter/planwright.yml" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$TRF/holder]
program_alpha_spec_root: $TRF_ROOT
program_alpha_home: $TRF/mchome
program_alpha_budget: {host_load: 1000000}
EOF

block() {
  printf '### Task %s — %s\n\n- **Deliverables:** work.\n- **Done when:** done.\n- **Dependencies:** %s\n- **Citations:** REQ-X\n- **Estimated effort:** 1 day\n%s\n' \
    "$1" "$2" "$3" "$4"
}

keeper_next() {
  KOUT=$(cd "$TRF/holder" && trf_env env PLANWRIGHT_FLEET_STATE_DIR="$TRF/fleet" \
    /bin/bash "$SCRIPTS/mc-keeper.sh" next --program alpha --spec "$BUNDLE" 2>"$TRF/keeper.err")
  KRC=$?
}
selection() {
  SOUT=$(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/orchestrate-select.sh" "$BUNDLE" 2>/dev/null)
}
ready_list() {
  ROUT=$(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/orchestrate-select.sh" --ready "$BUNDLE" 2>/dev/null)
}
dispatched() { printf '%s\n' "$KOUT" | awk -F"$TAB" '$1 == "dispatch" { sub(/^demo:task-/, "", $2); printf "%s ", $2 }'; }

# Task 1 is alpha's, Task 2 beta's, both ready; Task 3 is alpha's and waits on
# Task 2.
trf_bundle "$(block 1 'Alpha first' none '- **Repository:** alpha')
$(block 2 'Beta second' none '- **Repository:** beta')
$(block 3 'Alpha third' 2 '- **Repository:** alpha')"

keeper_next
assert_eq "REQ-M1.9: next succeeds with every repository healthy" 0 "$KRC"
assert_eq "both ready units are suggested, the critical path first" "2 1 " "$(dispatched)"
selection
ready_list
assert_eq "the selection's pick is the first ready unit" "2" "$SOUT"
assert_eq "the selection lists the ready units" "2
1" "$ROUT"

# Beta's evidence fails: Task 2 (its own repository) and Task 3 (its
# dependency's) are withheld by the selection.
trf_fail_gh beta
keeper_next
assert_eq "REQ-M1.9: next still succeeds" 0 "$KRC"
assert_eq "REQ-M1.9: a task whose own repository is withheld is not suggested" "1 " "$(dispatched)"
case $KOUT in
  *"demo:task-3"*) fail "a task whose dependency's repository is withheld is suggested" ;;
  *) ok "REQ-M1.9: nor one whose dependency's repository is withheld" ;;
esac
selection
assert_eq "REQ-M1.9: the suggestion equals the selection's output" "$SOUT" "$(dispatched | tr -d ' ')"
ready_list
assert_eq "and the selection's ready list" "1" "$ROUT"
case $KOUT in
  *"held${TAB}demo:task-2${TAB}"*) ok "the withheld unit is named held, with its reason" ;;
  *) fail "the withheld unit is not named held: $KOUT" ;;
esac

# Alpha fails too: nothing is ready, and nothing is suggested.
trf_fail_gh alpha
keeper_next
assert_eq "with every repository withheld next still succeeds" 0 "$KRC"
assert_eq "and suggests nothing" "" "$(dispatched)"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
