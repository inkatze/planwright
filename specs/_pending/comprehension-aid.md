# Seed: spec cold-start comprehension aid

Captured 2026-06-09 during the bootstrap drafting session. A seed for a future
`/spec-draft` (likely a fast-follow to the bootstrap spec, not a fold — it is
independently ownable and needs its own design + research).

## The problem

Before `/spec-kickoff` (the guided sign-off walkthrough), the recommended step is an
*independent cold read* of the spec bundle. Its value is independence: a pass nobody
steers, catching what the author + the kickoff dialogue would rationalize away. But
the current implementation is "read 37 design decisions as raw text," which is brutal
and text-only. Most people are visual. The independence is worth keeping; the
brutality is not.

## The idea

A **cold-start comprehension aid**: render a spec bundle in a digestible, visual,
didactic form so a human can evaluate it quickly and independently.

**Hard design constraint:** the aid must *augment the human's independent judgment, not
perform the comprehension for it.* If the agent does the understanding, the cold read
collapses back into "the authoring agent reviewed its own spec" and the independence
firewall is lost. The aid presents; the human judges.

Candidate forms (to be designed/researched, not yet decided):
- The dependency graph drawn (not ASCII), critical path highlighted.
- A decision-tree / map view of the D-log.
- A one-page "spec at a glance."
- A teach-back quiz: "here are N claims this spec makes — agree / disagree / unsure."
- A redline / diff view for amendments.

## Relationship to `/spec-kickoff`

Cold read = independent, unaided human pass (this aid serves it). Kickoff = guided
collaborative dialogue that produces the signed brief. They are complementary; the aid
makes the independent pass tractable without replacing it. Open question: should the
aid be a standalone `/comprehend`-style move, or a pre-flight stage of `/spec-kickoff`
that still preserves independence?

## Prior art to mine (cold-start read-evaluation strategies in high-stakes fields)

- Aviation pre-flight briefings + checklists (on-metaphor with the autopilot model).
- Clinical "teach-back" (confirm understanding by having the reader explain it back).
- Amazon "working backwards" silent-reading meeting over a PR/FAQ narrative.
- Legal contract review: redlining + plain-language clause-by-clause summaries.
- C4 model / architecture diagrams: visual system comprehension over prose.
- Concept maps (education); Feynman technique (explain-to-learn).
- Spec-driven AI tools (Kiro, Spec Kit) — any comprehension/review features.

Research question: how do high-stakes domains make a cold *first* read both tractable
and independent, and what is the minimal didactic tool planwright should adopt?

## Note

The bootstrap spec itself can't use this aid (it doesn't exist yet) — that's the
bootstrap paradox. For reviewing the bootstrap bundle now, use a manual cold read or an
agent-run adversarial critique (human adjudicates).
