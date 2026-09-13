### Amendment 6 — expression-only self-re-anchor (2026-08-26, format-grammar Task 4)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by the execution skill that
lands the amendment (format-grammar REQ-A1.9, REQ-E1.3; the single re-anchor
entry that task owes this bundle).

**Why the anchor moved:** two edits to this bundle's content, both
expression-only. REQ-C1.5's severity phrasing now names the severities per
status instead of the "non-Draft" shorthand that read as covering the terminal
statuses, where the shipped validator and this bundle's own REQ-C1.5 test-spec
entry both say warnings. And the Deferred entry's free-text gate dropped a
parenthetical copy of the condition grammar's status literals — a fact
`doctrine/accumulator-taxonomy.md` owns, which format-grammar Task 4 made false
by adding `ready` to the evaluator's stored-status whitelists — in favor of
pointing at that doc.

Neither edit touches an accepted decision: the first states what bootstrap
D-25's severity model already decided, the second removes a stale restatement.
The gate condition itself is untouched, so the deferral surfaces for a human
each sweep exactly as before.

**Cites the changelog line:** the 2026-08-26 `## Changelog` entry in
`specs/invariant-tasks/requirements.md`, which carries both edits and closes
the ritual owed for the gate's earlier free-text conversion (PR #321).

Class: expression-only
Anchor: `70ef874889e98d3f3cb24951a460e41a7084e386` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`
