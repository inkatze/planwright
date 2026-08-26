#!/bin/bash
# Tests for the turn/artifact arbitration landing in doctrine (operator-dialogue
# Task 7; REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.5, REQ-J1.3; D-14,
# D-15, D-20, D-21).
#
# Task 7 lands five rules in doctrine/interaction-style.md — the arbitration
# itself, the bounded-projection shape, the qualitative density bound, the
# no-monotonic-summary rule, and self-containment-as-a-floor — and amends the
# three docs whose emit mandates collided with it (discovery-rigor,
# finding-categorization, gate-wiring) to declare a destination side and cite
# the arbitration.
#
# REQ-I1.1's test-spec entry is [design-level] and the REQ-I1.2/I1.3/I1.5/J1.3
# arms grade eval transcripts against fixtures another task owns. The
# assertions here are the cheap mechanical floor under that review, the same
# role tests/test-inception-doctrine.sh plays for its design-level arms: they
# pin that each rule is stated, that the amended docs point at the arbitration
# from the mandate that collided with it, and that the superseded "cumulative"
# running-summary wording does not creep back. They do not judge the prose.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTRINE="$REPO_ROOT/doctrine"

failures=0
assert_contains() {
  # assert_contains <description> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2')" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  # assert_absent <description> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (expected NOT to find '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

flatten() {
  # Collapse every run of whitespace to one space. Doctrine prose wraps at
  # markdownlint's column, so a phrase the rule states is routinely split
  # across two lines; without this, every multi-word needle here would be
  # asserting a wrap position rather than the rule.
  tr '\n' ' ' | tr -s '[:space:]' ' '
}

section() {
  # section <file> <heading-text> -> the body from that heading to the next
  # heading at the same or a shallower level, flattened. Empty output means the
  # heading is gone, which every caller below turns into a failed assertion.
  awk -v want="$2" '
    /^#+ / {
      line = $0
      sub(/^#+ +/, "", line)
      hashes = index($0, " ") - 1
      if (line == want) { depth = hashes; on = 1; next }
      if (on && hashes <= depth) { on = 0 }
    }
    on { print }
  ' "$1" | flatten
}

for doc in interaction-style discovery-rigor finding-categorization gate-wiring; do
  if [ ! -f "$DOCTRINE/$doc.md" ]; then
    echo "FAIL: doctrine/$doc.md missing" >&2
    exit 1
  fi
done

style="$(flatten <"$DOCTRINE/interaction-style.md")"

# ---------------------------------------------------------------------------
# 1. REQ-I1.1 / D-14 — the arbitration is stated: completeness governs
#    artifacts, progressive disclosure governs the turn, and withholding from a
#    turn while recording in the artifact is not pruning.
# ---------------------------------------------------------------------------
arb="$(section "$DOCTRINE/interaction-style.md" "The turn/artifact arbitration")"
assert_contains "arbitration: the section exists" "artifact" "$arb"
assert_contains "arbitration: completeness governs artifacts" "artifacts" "$arb"
assert_contains "arbitration: disclosure governs the turn" "turn" "$arb"
assert_contains "arbitration: withholding-while-recording is not pruning" \
  "not pruning" "$arb"

# ---------------------------------------------------------------------------
# 2. REQ-I1.4 / D-14 — every emit mandate declares its destination side, and an
#    ambiguous one is a defect rather than latitude.
# ---------------------------------------------------------------------------
assert_contains "arbitration: emit mandates declare a side" "emit mandate" "$arb"
assert_contains "arbitration: an ambiguous side is a defect" "defect" "$arb"

# ---------------------------------------------------------------------------
# 3. REQ-I1.2 / REQ-I1.3 / D-15 — the projection shape: actionability-ordered,
#    counts standing in for audit tables, the full record one request away.
# ---------------------------------------------------------------------------
proj="$(section "$DOCTRINE/interaction-style.md" "Turn projection")"
assert_contains "projection: the section exists" "projection" "$proj"
assert_contains "projection: decisions and questions lead" "Decisions" "$proj"
assert_contains "projection: bookkeeping last" "bookkeeping" "$proj"
assert_contains "projection: counts stand in for tables" "Counts" "$proj"
assert_contains "projection: the whole record is one request away" \
  "one request away" "$proj"

# ---------------------------------------------------------------------------
# 4. REQ-I1.5 / D-20 — the density bound is qualitative and stated as an
#    extension of the shipped Small-bites rule, not a new peer rule. It lives
#    under that heading, and the numbers stay in the eval fixtures.
# ---------------------------------------------------------------------------
bites="$(section "$DOCTRINE/interaction-style.md" "Small bites")"
assert_contains "density: bounded to one decision cluster per turn" \
  "decision cluster" "$bites"
assert_contains "density: identifiers only where traceability needs them" \
  "traceability" "$bites"
assert_contains "density: numbers live in fixtures, not doctrine" \
  "fixture" "$bites"

# ---------------------------------------------------------------------------
# 5. REQ-J1.3 / D-21 — the running summary is delta-plus-open, and the
#    superseded "cumulative" wording is gone from the rule.
# ---------------------------------------------------------------------------
summary="$(section "$DOCTRINE/interaction-style.md" "Running summary")"
assert_contains "summary: presents the delta since the previous summary" \
  "since the previous summary" "$summary"
assert_contains "summary: plus what remains open" "remains open" "$summary"
assert_contains "summary: no repeated summary grows monotonically" \
  "monotonic" "$summary"
assert_absent "summary: the superseded cumulative wording is gone" \
  "cumulative summary" "$summary"

# ---------------------------------------------------------------------------
# 6. REQ-I1.5 — self-containment is a floor (the decision plus each option's
#    action and consequence), never a license for unbounded density. The rule
#    lives under the selector heading, so the scoped section is what is read:
#    "a floor" appears elsewhere in the file about a different rule.
# ---------------------------------------------------------------------------
sel="$(section "$DOCTRINE/interaction-style.md" "Selectors with recommendations")"
assert_contains "self-containment: stated as a floor, not a ceiling" \
  "floor, not a ceiling" "$sel"
assert_contains "self-containment: comparative content goes to previews" \
  "option previews" "$sel"
assert_contains "self-containment: not a license for unbounded density" \
  "never a license" "$sel"

# ---------------------------------------------------------------------------
# 7. REQ-I1.1 / REQ-I1.4 — each colliding doc points at the arbitration from
#    the mandate that collided with it, and names a destination side there.
#    check-doc-links.sh separately proves the link target resolves.
# ---------------------------------------------------------------------------
lens="$(section "$DOCTRINE/discovery-rigor.md" "Lens-coverage table (canonical output)")"
assert_contains "discovery-rigor: the lens table cites the arbitration" \
  "interaction-style.md" "$lens"
assert_contains "discovery-rigor: the lens table declares its side" \
  "artifact-side" "$lens"

pres="$(section "$DOCTRINE/finding-categorization.md" "Presentation (REQ-C1.5)")"
assert_contains "finding-categorization: presentation cites the arbitration" \
  "interaction-style.md" "$pres"
assert_contains "finding-categorization: the in-turn composition is bounded" \
  "projection" "$pres"

handoff="$(section "$DOCTRINE/gate-wiring.md" "Loop-end handoff")"
assert_contains "gate-wiring: the loop-end handoff cites the arbitration" \
  "interaction-style.md" "$handoff"
assert_contains "gate-wiring: the full record is artifact-side" \
  "artifact-side" "$handoff"
assert_contains "gate-wiring: the turn gets the projection" \
  "projection" "$handoff"

# ---------------------------------------------------------------------------
# 8. The doc that gained the rules cites the requirements they come from, so a
#    later reader can trace the arbitration back to its bundle.
# ---------------------------------------------------------------------------
assert_contains "interaction-style cites the arbitration requirements" \
  "REQ-I1.1" "$style"
assert_contains "interaction-style cites the summary requirement" \
  "REQ-J1.3" "$style"

# ---------------------------------------------------------------------------
# 9. The arbitration is law for every attended flow, not an optional extra.
#    The doc's own closing scope note enumerates what a flow must instantiate,
#    and the doctrine README row is how a reader finds the doc at all; a rule
#    absent from both reads as optional however well the body states it.
# ---------------------------------------------------------------------------
notes="$(section "$DOCTRINE/interaction-style.md" "Application notes")"
assert_contains "application notes: the arbitration binds every attended flow" \
  "arbitration" "$notes"

readme="$(grep -F '[interaction-style.md](interaction-style.md)' \
  "$DOCTRINE/README.md" | flatten)"
assert_contains "doctrine README: the row names the arbitration" \
  "arbitration" "$readme"
assert_contains "doctrine README: the row carries the arbitration citations" \
  "REQ-I1.1" "$readme"

if [ "$failures" -ne 0 ]; then
  echo "test-operator-dialogue-doctrine: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-operator-dialogue-doctrine: all assertions passed"
