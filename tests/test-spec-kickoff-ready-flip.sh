#!/bin/bash
# Tests for the /spec-kickoff Draft→Ready flip and stage-scaled change-handling
# (Task 3 of specs/kickoff-lifecycle; REQ-D1.1, REQ-A1.4, REQ-D1.4, REQ-A1.6,
# D-1). The kickoff-lifecycle bundle inserts a `Ready` status between Draft and
# Active: sign-off now stores a Draft→Ready flip (the only stored, human-gated
# transition), Ready↔Active is derived by the reconcile (Task 6, not written
# here), and change-handling scales by the bundle's lifecycle stage. This is a
# skill-prose change: the sign-off flip and the mode selection are procedure the
# agent reads, not a script, so the [test] half of REQ-D1.1 / REQ-A1.4 /
# REQ-D1.4 / REQ-A1.6's verification paths is a structural guard over
# skills/spec-kickoff/SKILL.md (the same shape as
# tests/test-orchestrate-status-gate.sh, Task 5's symmetric guard). The [manual]
# halves (the kickoff handoff reports Ready; the reopen reads cleanly) are
# exercised by the human at review; this test fences the structural properties
# against a regression.
#
# Asserted properties:
#   - sign-off's first-activation flip stores Draft→Ready, not Draft→Active
#     (REQ-D1.1, REQ-A1.4), and writes it across all four spec files (stored,
#     not derived);
#   - change-handling scales by lifecycle stage (REQ-D1.4): a Ready bundle's
#     pre-merge change is a delta re-walkthrough / re-sign-off, not the amendment
#     ritual; the amendment ritual is reserved for an Active bundle (work in
#     flight); a Done bundle reopens to Draft;
#   - the reopen cycle (REQ-A1.6) lands a reopened bundle's sign-off at Ready
#     (Done→Draft, then the scoped delta sign-off flips Draft→Ready again);
#   - the new requirement citations (REQ-D1.1, REQ-A1.4, REQ-D1.4, REQ-A1.6) are
#     present so the prose is traceable to the contract;
#   - the superseded operative flip phrasings ("Draft→Active", the words "Draft
#     to Active", "Active flip") are gone, so no stale Draft→Active flip remains.
#     The token "Active" still appears where it names the narrowed work-in-flight
#     status or the derived Ready→Active transition — those references are
#     desirable, not a regression.
#
# Runs standalone: ./tests/test-spec-kickoff-ready-flip.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/spec-kickoff/SKILL.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

if [ ! -f "$skill" ]; then
  echo "FAIL: spec-kickoff SKILL.md missing at $skill" >&2
  exit 1
fi

# Flatten newlines and squeeze runs of whitespace to a single space so the
# multi-line prose assertions match across markdown line-wraps and the
# indentation that follows them; the raw file is used for single-line and
# absence checks.
flat="$(tr '\n' ' ' <"$skill" | tr -s '[:space:]' ' ')"

# REQ-D1.1 / REQ-A1.4: the sign-off flip stores Draft→Ready. Positive presence
# of the new flip target.
if grep -q 'Draft→Ready' "$skill"; then
  ok "sign-off flip names Draft→Ready (REQ-D1.1, REQ-A1.4)"
else
  fail "sign-off flip does not name 'Draft→Ready' (REQ-D1.1, REQ-A1.4)"
fi

# REQ-A1.4: the flip is stored across all four spec files (no dependence on
# task-state derivation). Bind the flip target to the four-file mirror via the
# conjunction so the two phrases stay semantically adjacent (a bounded gap, not
# an open-ended one, so a reordered/unrelated co-occurrence cannot satisfy it).
if printf '%s' "$flat" | grep -qE 'Draft→Ready and .{0,80}on all four spec files'; then
  ok "Draft→Ready is written across all four spec files (stored flip, REQ-A1.4)"
else
  fail "the Draft→Ready flip is not bound to 'all four spec files' (REQ-A1.4)"
fi

# REQ-A1.4 / REQ-A1.5: Draft→Ready is the ONLY stored flip. Re-walkthroughs and
# amendments on an in-flight bundle bump Last reviewed but do NOT re-flip the
# status (Ready↔Active is derived by the reconcile, never re-written here); guard
# that the no-re-flip property is stated so a regression re-introducing a flip on
# the re-walk path is caught.
if printf '%s' "$flat" | grep -qE 'Re-walkthroughs and amendments.{0,120}with no status flip'; then
  ok "re-walkthroughs/amendments bump Last reviewed with no status flip (REQ-A1.4, REQ-A1.5)"
else
  fail "the re-walkthrough/amendment path is not bound to 'no status flip' (REQ-A1.4, REQ-A1.5)"
fi

# REQ-D1.4: change-handling scales by lifecycle stage. The Ready path is a delta
# re-walkthrough / re-sign-off, explicitly NOT the amendment ritual.
if printf '%s' "$flat" | grep -qE 'Ready bundle.*delta re-walkthrough.*not the amendment ritual'; then
  ok "a Ready bundle's pre-merge change is a delta re-walkthrough, not the amendment ritual (REQ-D1.4)"
else
  fail "the Ready-bundle change path is not tied to delta re-walkthrough / not-amendment (REQ-D1.4)"
fi

# REQ-D1.4: the amendment ritual is reserved for an Active bundle (work in
# flight). Bind the verb to Active so an inverted-semantics regression cannot
# pass.
if printf '%s' "$flat" | grep -qE 'amendment ritual is reserved for an Active bundle \(work in flight\)'; then
  ok "the amendment ritual is reserved for an Active bundle (work in flight) (REQ-D1.4)"
else
  fail "the amendment ritual is not bound to an Active (work-in-flight) bundle (REQ-D1.4)"
fi

# REQ-A1.6 / REQ-D1.4: a Done bundle reopens to Draft (the reopen cycle), rather
# than being amended in place.
if printf '%s' "$flat" | grep -qE 'Done bundle reopens to Draft'; then
  ok "a Done bundle reopens to Draft (REQ-A1.6 reopen cycle)"
else
  fail "the Done-bundle path does not state it 'reopens to Draft' (REQ-A1.6)"
fi

# REQ-A1.6: the reopened-bundle sign-off lands at Ready, not Active.
if printf '%s' "$flat" | grep -qE 'sign-off flips Draft→Ready again'; then
  ok "the reopened-bundle sign-off flips Draft→Ready again (REQ-A1.6)"
else
  fail "the reopened-bundle sign-off does not land at Ready ('Draft→Ready again') (REQ-A1.6)"
fi

# The new requirement citations are present so the prose traces to the contract.
for req in REQ-D1.1 REQ-A1.4 REQ-D1.4 REQ-A1.6; do
  if grep -q "$req" "$skill"; then
    ok "requirement $req is cited"
  else
    fail "requirement $req is not cited"
  fi
done

# Regression fence: the superseded operative Draft→Active flip phrasings are gone.
if grep -q 'Draft→Active' "$skill"; then
  fail "stale flip target 'Draft→Active' still present (REQ-D1.1 supersede)"
else
  ok "stale flip target 'Draft→Active' removed"
fi
if grep -q 'Draft to Active' "$skill"; then
  fail "stale flip phrasing 'Draft to Active' still present (REQ-D1.1 supersede)"
else
  ok "stale flip phrasing 'Draft to Active' removed"
fi
if grep -q 'Active flip' "$skill"; then
  fail "stale 'Active flip' phrasing still present (REQ-D1.1 supersede)"
else
  ok "stale 'Active flip' phrasing removed"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all spec-kickoff Ready-flip tests passed"
