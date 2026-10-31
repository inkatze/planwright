#!/bin/bash
# Tests for per-task repositories on a format-version 3 bundle: the
# derivation (scripts/orchestrate-state.sh), selection
# (scripts/orchestrate-select.sh), the gate sweep (scripts/drain-gates.sh),
# and the status render (scripts/spec-status.sh), over the shared
# two-repository fixture (tests/lib/two-repo-fixture.sh). Task 1 names
# `alpha`, Task 2 names `beta` and depends on Task 1, Task 3 names `alpha` and
# depends on Task 2; the bundle sits in a holder, which is its work
# repository. Plain bash 3.2, inline asserts.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPTS=$REPO_ROOT/scripts
TAB=$(printf '\t')
# shellcheck source=tests/lib/two-repo-fixture.sh
. "$REPO_ROOT/tests/lib/two-repo-fixture.sh"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
assert_has() {
  case $3 in
    *"$2"*) pass "$1" ;;
    *) fail "$1 (expected to contain '$2', got: $3)" ;;
  esac
}
assert_not() {
  case $3 in
    *"$2"*) fail "$1 (did not expect '$2' in: $3)" ;;
    *) pass "$1" ;;
  esac
}

trf_setup "$SCRIPTS" || {
  echo "FAIL: the two-repository fixture could not be built" >&2
  exit 1
}
trap trf_teardown EXIT
BUNDLE=$TRF_ROOT/demo

block() {
  printf '### Task %s — %s\n\n- **Deliverables:** work.\n- **Done when:** done.\n- **Dependencies:** %s\n- **Citations:** REQ-X\n- **Estimated effort:** 1 day\n%s\n' \
    "$1" "$2" "$3" "$4"
}
GATES='## Deferred

- **Gate on the beta task.** Waits for Task 2.
  **Gate:** GATE(when: task 2 completed). Citations: REQ-X.
- **Gate on the alpha task.** Waits for Task 1.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.'
write_bundle() {
  trf_bundle "$(block 1 'Alpha first' none "$1")
$(block 2 'Beta second' 1 "$2")
$(block 3 'Alpha third' 2 "$3")
$GATES"
}
write_bundle '- **Repository:** alpha' '- **Repository:** beta' '- **Repository:** alpha'

# Every run starts in the holder, the bundle's work repository.
derive() { state=$(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/orchestrate-state.sh" "$BUNDLE" 2>&1); }
select_unit() {
  sel_rc=0
  sel=$(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/orchestrate-select.sh" "$BUNDLE" 2>"$TRF/sel.err") || sel_rc=$?
  sel_err=$(cat "$TRF/sel.err")
}
render() {
  st_rc=0
  status=$(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/spec-status.sh" "$BUNDLE" 2>&1) || st_rc=$?
}
gates() { report=$(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/drain-gates.sh" --today 2026-10-30 "$TRF_ROOT" 2>&1); }
# rec <tag> <col2> — the first such record's remaining columns.
rec() {
  printf '%s\n' "$state" | awk -F"$TAB" -v t="$1" -v i="$2" \
    '$1 == t && $2 == i { s = $3; for (k = 4; k <= NF; k++) s = s "\t" $k; print s; exit }'
}
gate_row() { printf '%s\n' "$report" | grep -F "Gate on the $1 task"; }

# --- REQ-F1.4: per-task derivation and dependencies ---------------------------
trf_branch alpha 1
derive
assert_eq "F1.4 each aliased task names its repository" "alpha beta alpha" \
  "$(rec repository 1) $(rec repository 2) $(rec repository 3)"
assert_eq "F1.4 Task 1's branch in alpha is in-progress evidence" "in-progress${TAB}branch-commits" "$(rec task 1)"
select_unit
assert_eq "F1.4 Task 1's branch alone in alpha does not make Task 2 selectable (exit)" 1 "$sel_rc"
assert_eq "F1.4 nothing is selected while Task 1 is in flight" "" "$sel"
trf_reset_evidence

# A same-named branch and merged PR in beta: were they read for Task 1, it
# would not be the pick.
trf_branch beta 1
trf_pr beta 1 MERGED 41
select_unit
assert_eq "F1.4 beta's same-named Task 1 evidence is no evidence for it" 1 "$sel"
trf_reset_evidence

trf_pr alpha 1 MERGED 42
select_unit
assert_eq "F1.4 Task 1's merged PR in alpha makes Task 2 selectable" 2 "$sel"

# A merged Task 2 PR in alpha would complete it; beta's open one is the truth.
trf_pr alpha 2 MERGED 43
trf_pr beta 2 OPEN 44
derive
assert_eq "F1.4 Task 1's merged PR in alpha completes it" "completed${TAB}pr-merged" "$(rec task 1)"
assert_eq "F1.4 the completion stamp comes from alpha's PR" "42${TAB}2026-10-30" "$(rec completion 1)"
assert_eq "F1.4 Task 2 derives from beta only" "in-progress${TAB}pr-open" "$(rec task 2)"
render
assert_eq "F1.4 the render exits 0" 0 "$st_rc"
assert_has "F1.4 the render shows Task 1's alias" "task 1 completed · PR #42 merged 2026-10-30 (pr-merged) · repository alpha" "$status"
assert_has "F1.4 the render shows Task 2's alias" "task 2 in-progress (pr-open) · repository beta" "$status"
assert_has "F1.4 the render shows Task 3's alias" "task 3 blocked (deps-unmet) · repository alpha" "$status"
assert_has "F1.4 the bundle derives Active" "bundle status: Active (derived)" "$status"
trf_reset_evidence

# --- REQ-F1.5: an unresolved field fails closed --------------------------------
trf_pr alpha 1 MERGED 42
# The work repository's own completion trailer for Task 2: never read for it.
trf_git -C "$TRF/holder" commit -q --allow-empty -m "stray" -m "Planwright-Task: demo/2"
trf_unregister beta
derive
assert_eq "F1.5 Task 1 still derives from alpha" "completed${TAB}pr-merged" "$(rec task 1)"
assert_eq "F1.5 Task 2 derives repository-unresolved" "repository-unresolved${TAB}alias-unresolved" "$(rec task 2)"
assert_eq "F1.5 the record names the alias" beta "$(rec repository-unresolved 2 | cut -f1)"
if [ -n "$(rec repository-unresolved 2 | cut -f2)" ]; then pass "F1.5 the record carries a reason"; else fail "F1.5 the record carries no reason"; fi
assert_eq "F1.5 Task 3 is unmet behind it" "blocked${TAB}deps-unmet" "$(rec task 3)"
select_unit
assert_eq "F1.5 nothing is selected (exit)" 1 "$sel_rc"
assert_eq "F1.5 Task 2 is never selected" "" "$sel"
gates
assert_has "F1.5 the gate on Task 2 is pending" "PENDING" "$(gate_row beta)"
assert_has "F1.5 the gate atom on Task 2 resolves unresolved" "unresolved" "$(gate_row beta)"
assert_has "F1.5 the sweep names the unresolved repository" "task 2 names repository beta, which does not resolve here" "$report"
assert_has "F1.5 the gate on alpha's Task 1 still evaluates" "SATISFIED" "$(gate_row alpha)"
trf_pr alpha 3 MERGED 45
render
assert_has "F1.5 the render names the unresolved alias" "task 2 repository-unresolved (alias-unresolved) · repository beta:" "$status"
assert_has "F1.5 the bundle does not derive Done" "bundle status: Active (derived)" "$status"
# Deferring the unresolved task does not let the bundle derive Done either.
trf_bundle "$(block 1 'Alpha first' none '- **Repository:** alpha')
$(block 2 'Beta second' 1 '- **Repository:** beta')
$(block 3 'Alpha third' 2 '- **Repository:** alpha')
## Deferred

- **Task 2** waits on beta's registration."
render
assert_has "F1.5 a deferred unresolved task still shows its alias" "task 2 deferred (bullet: waits on beta's registration.) · repository beta:" "$status"
assert_not "F1.5 a deferred unresolved task keeps the bundle from Done" "bundle status: Done" "$status"
write_bundle '- **Repository:** alpha' '- **Repository:** beta' '- **Repository:** alpha'

trf_reset_evidence
trf_pr alpha 1 MERGED 42
for variant in malformed duplicate; do
  if [ "$variant" = malformed ]; then
    write_bundle '- **Repository:** alpha' '- **Repository:** acme/beta' '- **Repository:** alpha'
    code=alias-malformed
  else
    write_bundle '- **Repository:** alpha' '- **Repository:** alpha
- **Repository:** beta' '- **Repository:** alpha'
    code=alias-duplicate
  fi
  derive
  assert_eq "F1.5 a $variant field derives repository-unresolved, never the work repository" \
    "repository-unresolved${TAB}$code" "$(rec task 2)"
  assert_eq "F1.5 a $variant field leaves Task 3 unmet" "blocked${TAB}deps-unmet" "$(rec task 3)"
  gates
  if [ "$variant" = malformed ]; then
    assert_has "F1.5 the sweep names the malformed field" "task 2 has a Repository: value that is not a single alias" "$report"
  else
    assert_has "F1.5 the sweep names the duplicate field" "task 2 carries more than one Repository: field" "$report"
  fi
done
write_bundle '- **Repository:** alpha' '- **Repository:** beta' '- **Repository:** alpha'
trf_register beta

mv "$TRF_ROOT/planwright-spec-root.yml" "$TRF/marker.bak"
derive
assert_eq "F1.5 under an unmarked root Task 1 is unresolved" "repository-unresolved${TAB}alias-unresolved" "$(rec task 1)"
assert_eq "F1.5 under an unmarked root Task 2 is unresolved" "repository-unresolved${TAB}alias-unresolved" "$(rec task 2)"
assert_has "F1.5 the reason names the missing marker" "marker" "$(rec repository-unresolved 1)"
mv "$TRF/marker.bak" "$TRF_ROOT/planwright-spec-root.yml"
trf_reset_evidence

# A field under a declaration that cannot say whether fields are meant fails
# closed rather than deriving from the work repository.
sed 's/^\*\*Format-version:\*\* 3$/**Format-version:** three/' "$BUNDLE/tasks.md" >"$TRF/tasks.tmp"
cp "$BUNDLE/tasks.md" "$TRF/tasks.keep"
mv "$TRF/tasks.tmp" "$BUNDLE/tasks.md"
derive_rc=0
(cd "$TRF/holder" && trf_env /bin/sh "$SCRIPTS/orchestrate-state.sh" "$BUNDLE" >/dev/null 2>&1) || derive_rc=$?
assert_eq "a field under an undefined Format-version fails closed" 2 "$derive_rc"
mv "$TRF/tasks.keep" "$BUNDLE/tasks.md"

# A base that resolves in no task's repository is a misconfiguration, not a
# transient failure.
derive_rc=0
(cd "$TRF/holder" && trf_env PLANWRIGHT_BASE_REF=no-such-base /bin/sh "$SCRIPTS/orchestrate-state.sh" "$BUNDLE" >/dev/null 2>&1) || derive_rc=$?
assert_eq "an unresolvable base in an aliased repository fails closed" 2 "$derive_rc"

# --- REQ-F1.6 / REQ-B1.7: a transient failure is keyed per task ---------------
trf_fail_gh beta
derive
assert_eq "F1.6 the failure names beta" "beta${TAB}gh query failed; deriving git-only" "$(rec degraded repository)"
assert_eq "F1.6 Task 2 is withheld on its own repository" "own${TAB}beta" "$(rec withheld 2)"
assert_eq "F1.6 Task 3 is withheld on its dependency's repository" "dependency${TAB}beta" "$(rec withheld 3)"
assert_eq "F1.6 Task 1 is not withheld" "" "$(rec withheld 1)"
select_unit
assert_eq "F1.6 Task 1 stays selectable" 1 "$sel"
assert_has "F1.6 selection reports the failing repository" "transient evidence failure in repository beta" "$sel_err"
render
assert_eq "F1.6 the render exits with the transient-failure status" 3 "$st_rc"
assert_has "F1.6 the render names beta" "spec-status: transient evidence failure in repository beta" "$status"
assert_has "F1.6 Task 1 renders from healthy evidence" "task 1 ready (deps-met) · repository alpha" "$status"
assert_has "F1.6 Task 2's partial evidence is not shown as status" "task 2 withheld (evidence unavailable: repository beta failed) · repository beta" "$status"
assert_not "F1.6 no derived bundle status is claimed" "(derived)" "$status"

trf_pr alpha 1 MERGED 42
gates
assert_has "F1.6 the gate atom on Task 2 resolves unresolved" "unresolved" "$(gate_row beta)"
assert_has "F1.6 the sweep names the failing repository" "transient evidence failure in repository beta" "$report"
assert_has "F1.6 the gate on alpha's Task 1 still evaluates" "SATISFIED" "$(gate_row alpha)"
select_unit
assert_eq "F1.6 with only withheld work left, selection reports the transient failure" 3 "$sel_rc"
assert_eq "F1.6 nothing is selected then" "" "$sel"

# Task 2 completed by git evidence in beta: Task 3's dependency is met, yet
# its repository failed, so Task 3 is still never selected.
trf_git -C "$TRF/src/beta" commit -q --allow-empty -m "task 2 landed" -m "Planwright-Task: demo/2"
derive
assert_eq "F1.6 Task 2 completes from beta's git evidence" "completed${TAB}trailer" "$(rec task 2)"
assert_eq "F1.6 Task 3's dependency is met" "ready${TAB}deps-met" "$(rec task 3)"
select_unit
assert_eq "F1.6 a dependent of a failed repository is never selected" "" "$sel"
assert_eq "F1.6 and that is the transient failure" 3 "$sel_rc"
trf_bundle "$(block 1 'Alpha first' none '- **Repository:** alpha')
$(block 2 'Beta second' 1 '- **Repository:** beta')
$(block 3 'Alpha third' 2 '- **Repository:** alpha')
## Awaiting input

- **Task 3** waits on a decision."
select_unit
assert_eq "F1.6 withheld work that is parked is no transient failure" 1 "$sel_rc"
write_bundle '- **Repository:** alpha' '- **Repository:** beta' '- **Repository:** alpha'
trf_branch alpha 3
select_unit
assert_eq "F1.6 withheld work that is already in flight is no transient failure" 1 "$sel_rc"
trf_heal_gh beta
trf_reset_evidence

# --- A bundle naming no repository derives as before --------------------------
write_bundle '' '' ''
derive
assert_eq "no field: no repository records" "" "$(printf '%s\n' "$state" | awk -F"$TAB" '$1 == "repository" || $1 == "withheld" || $1 == "repository-unresolved"')"
assert_eq "no field: Task 1 derives from the work repository" "ready${TAB}deps-met" "$(rec task 1)"
trf_fail_gh holder
trf_git -C "$TRF/holder" remote add origin https://example.invalid/acme/holder.git
derive
assert_eq "no field: a failure is the bundle-wide record" "gh query failed; deriving git-only" "$(rec degraded gh)"

echo
if [ "$failures" -eq 0 ]; then
  echo "all per-task repository tests passed"
  exit 0
fi
echo "$failures per-task repository test(s) failed" >&2
exit 1
