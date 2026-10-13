#!/bin/bash
# discipline-card-fixture.sh — a golden discipline card for the card-lint
# tests. Sourced, never executed.
#
# write_golden_card <dir> [<card-id>] writes <dir>/<card-id>.md (default id
# fixture-discipline): a minimal card satisfying every rule in
# doctrine/discipline-cards.md, which each seeded-violation case then mutates
# one rule at a time.

write_golden_card() {
  _dir=$1
  _id=${2:-fixture-discipline}
  mkdir -p "$_dir"
  cat >"$_dir/$_id.md" <<CARD
# Fixture discipline — discipline card

**Card-format:** 1
**Card-id:** $_id
**Reviewed:** 2026-10-11
**Rot-rate:** slow
**Default-tier:** structure-only
**RAPID:** I
**Bench:** no
**Stance-axis:** optimist-skeptic

## Role

Frames the fixture discipline's options for this venture as falsifiable hypotheses.

## Mandate

1. Which problem named in the frame does this venture solve first?
2. What do the people in the frame do today instead, and what does it cost
   them in this venture's context?
3. Which constraint in the frame rules out the obvious option?

## Frameworks

1. **First method** (Author, *Book*, 2020) — run first to set the scope.
   Misuse: treating the output as a decision rather than an input.
2. **Second method** (Author, *Article*, 2021) — run on the first one's output.
   Misuse: skipping the evidence step it depends on.

## Grounding

- **Sources register** — every claim cites an entry.
- **Refuse without:** at least one sources-register entry on the problem; ask for one otherwise.

## Input subscription

- \`assumptions.md\`, entries tagged value or viability.

## Artifact template

\`\`\`markdown
## Findings

<findings, each citing a source>

## Decisions I cannot make

| Decision | Tier and reason | Owning role | Evidence needed |
| --- | --- | --- | --- |
\`\`\`

**Done when:** every mandate question has a finding or a stated refusal.

## Capability boundary

- **Per-activity exceptions:**
  - agent-senior: listing the alternatives the sources register already names.
  - human-authority: choosing which problem the venture solves first.
- **One-way doors:** human-authority — publishing a public commitment.
- **Out of scope:** legal interpretation and pricing numbers.

## Escalation contract

- **irreversibility** (powers: halt, override): the call publishes a commitment.
- **missing-domain-authority** (powers: disregard): the call needs a licensed opinion.
- **confidence-floor** (powers: override): the evidence is opinion-grade or weaker.
- **contract-policy-change** (powers: halt, reverse): the call changes an external term.

## Register rules

Proposes assumption entries with a risk tag and an evidence grade; never writes a register.

## Anti-patterns

A recommendation with no cited evidence.

## Blind spots

Implementation cost; the engineering seat covers it.

## Conflict and deference

Defers to the pricing seat on price levels.

## Independence

Cannot validate its own discipline's claims; the challenge pass and real evidence do.

## Sources

- Author, *Book*, 2020 — re-verified 2026-10-11.
CARD
}
