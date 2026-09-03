#!/bin/bash
# Tests for the enumeration cross-check step at drafting and at sign-off
# (Task 7 of specs/anchor-integrity; D-8, REQ-E1.1, REQ-E1.2).
#
# Anchored deliverable prose that states a count or a corpus list ("the sole
# violation is X", "these N fixtures") freezes a claim whose truth lives on a
# surface outside the bundle. The anchor then guarantees the words have not
# changed while the thing they counted moves underneath them, silently. D-8's
# answer is a step in the two skills that write and seal a bundle: /spec-draft
# checks at drafting, where the count is born, and /spec-kickoff checks again at
# sign-off, the last moment before the anchor freezes it.
#
# Both halves of REQ-E1.2's verification path are [design-level + manual], so
# the live exercise is the human's at the next drafting and kickoff sessions.
# This test is the structural guard underneath that: the step is skill prose the
# agent reads, not a script, so it is fenced the same way the sibling prose
# guards fence theirs (tests/test-spec-kickoff-ready-flip.sh,
# tests/test-execute-task-status-gate.sh) — assert the properties are stated, and
# let the manual pass judge how well they run.
#
# Asserted properties:
#   - the doctrine home exists (Task 1's guidance refinement): spec-format.md
#     carries the decided-rule section the two skills cite, and that section
#     names the cross-check the skills owe (REQ-E1.1);
#   - each skill names an enumeration cross-check step (REQ-E1.2);
#   - each skill states BOTH dispositions — verify the enumeration against the
#     surface it enumerates, OR convert it to a decided rule. A skill stating
#     only "flag enumerations" leaves the agent no resolution, so the pair is
#     asserted rather than the flag alone;
#   - each skill cites REQ-E1.2, so the prose is traceable to the contract, and
#     cites the doctrine section by name, so the rule is read from its normative
#     home rather than re-stated (and drifting) in two skill bodies.
#
# Runs standalone: ./tests/test-enumeration-cross-check.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
doctrine="$REPO_ROOT/doctrine/spec-format.md"
draft="$REPO_ROOT/skills/spec-draft/SKILL.md"
kickoff="$REPO_ROOT/skills/spec-kickoff/SKILL.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

for f in "$doctrine" "$draft" "$kickoff"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: expected instruction file missing at $f" >&2
    exit 1
  fi
done

# Flatten newlines and squeeze whitespace runs to a single space so the prose
# assertions match across markdown line-wraps and the indentation that follows
# them; the raw files stay available for single-line checks.
flatten() {
  tr '\n' ' ' <"$1" | tr -s '[:space:]' ' '
}

doctrine_flat="$(flatten "$doctrine")"

# REQ-E1.1: the Task 1 guidance refinement is the normative home the skills
# cite. Guard the heading itself, since both skills name it as a section
# reference — a rename here silently breaks both citations.
if grep -q '^## Decided rules over enumerated claims$' "$doctrine"; then
  ok "spec-format carries the 'Decided rules over enumerated claims' section (REQ-E1.1)"
else
  fail "spec-format is missing the '## Decided rules over enumerated claims' section (REQ-E1.1)"
fi

# REQ-E1.1/REQ-E1.2: that section is where the two skills' obligation is
# stated. Bind the skill names to the cross-check so the doctrine cannot keep
# the heading while dropping the step it delegates.
if printf '%s' "$doctrine_flat" \
  | grep -qE '/spec-draft.{0,60}/spec-kickoff.{0,80}enumeration cross-check'; then
  ok "the doctrine section assigns the cross-check to /spec-draft and /spec-kickoff (REQ-E1.2)"
else
  fail "the doctrine section does not assign the enumeration cross-check to both skills (REQ-E1.2)"
fi

# Per-skill structural assertions. The two skills carry the same four
# properties at different moments (drafting vs sign-off), so they are checked by
# one routine rather than two divergent copies.
check_skill() {
  # check_skill <path> <label>
  _cs_file="$1"
  _cs_label="$2"
  _cs_flat="$(flatten "$_cs_file")"

  # REQ-E1.2: the step is named. Case-insensitive on the leading word so a
  # heading ("Enumeration cross-check") and a mid-sentence mention both count;
  # the phrase itself is the contract's own name for the step.
  if printf '%s' "$_cs_flat" | grep -qiE 'enumeration cross-check|cross-check enumerations'; then
    ok "$_cs_label names the enumeration cross-check step (REQ-E1.2)"
  else
    fail "$_cs_label does not name an enumeration cross-check step (REQ-E1.2)"
  fi

  # REQ-E1.2: the verify disposition, bound to the surface being enumerated.
  # The bounded gap keeps the verb and its object inside one clause, so an
  # unrelated co-occurrence of "verify" cannot satisfy it.
  if printf '%s' "$_cs_flat" \
    | grep -qE 'verify it.{0,60}against the surface it enumerates'; then
    ok "$_cs_label states the verify-against-the-surface disposition (REQ-E1.2)"
  else
    fail "$_cs_label does not state verifying an enumeration against the surface it enumerates (REQ-E1.2)"
  fi

  # REQ-E1.2: the convert disposition. Asserted separately from the verify half
  # so a skill offering only one of the two resolutions fails.
  if printf '%s' "$_cs_flat" | grep -qE 'convert it to a decided rule'; then
    ok "$_cs_label states the convert-to-a-decided-rule disposition (REQ-E1.2)"
  else
    fail "$_cs_label does not state converting an enumeration to a decided rule (REQ-E1.2)"
  fi

  # Traceability: the citation ties the prose to the requirement, matching the
  # citation convention the sibling steps in these skills already follow.
  if grep -q 'REQ-E1\.2' "$_cs_file"; then
    ok "$_cs_label cites REQ-E1.2"
  else
    fail "$_cs_label does not cite REQ-E1.2"
  fi

  # The rule is read from its doctrine home, not restated in the skill body.
  # Guarding the section reference is what keeps the two skill copies from
  # drifting apart from each other and from the meta-spec.
  if printf '%s' "$_cs_flat" | grep -qE 'Decided rules over enumerated claims'; then
    ok "$_cs_label cites the doctrine section by name (REQ-E1.1)"
  else
    fail "$_cs_label does not cite spec-format's 'Decided rules over enumerated claims' (REQ-E1.1)"
  fi
}

check_skill "$draft" "/spec-draft"
check_skill "$kickoff" "/spec-kickoff"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all enumeration cross-check tests passed"
