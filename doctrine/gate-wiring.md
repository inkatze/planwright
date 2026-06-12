# Gate Wiring: the Act-Then-Review Loop

[Finding Categorization](finding-categorization.md) defines the four buckets,
their predicates, and the gate's principles. This document is the operational
wiring: the routing order, commit discipline, record formats, ladder
procedure, and pause protocol that a gate-wired skill (`/self-review`,
`/polish`, and the convergence step inside `/execute-task`) implements. The
two documents share one contract; where this one names a bucket, predicate,
or zone, the categorization doctrine's definition governs.

Citations: REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6.

## Input contract

The wiring starts where [Validation Rigor](validation-rigor.md) ends: its
input is validated findings, each carrying the validation evidence that
confirmed it. Its output is a disposition per finding plus the audit record
(four tables, declined log, pending-sign-off checklist) the draft PR carries
to review. Discovery and validation are upstream concerns; nothing in this
document re-litigates whether a finding is real.

## Routing order

Route each validated finding through these steps, in order. The zone screen
runs first because a hard-disqualifier zone forces a pause regardless of
which bucket the finding would otherwise land in.

1. **Zone screen.** If the finding, or any file its fix would touch, falls in
   a hard-disqualifier zone (the categorization doctrine's list:
   security-sensitive code, migrations or destructive operations,
   CI configuration, lockfiles, secrets files), trigger a hard pause
   (see Pause protocol).
   Record the recommended fix; do not apply it.
2. **Bucket assignment** per the categorization predicates. When a predicate
   condition is uncertain, route downward exactly as the categorization
   doctrine directs (toward Needs sign-off or Needs human judgment), never
   upward.
3. **Disposition by bucket:**
   - *Auto-applicable* → apply now, audit row with the rule citation.
   - *Agent-resolvable* → resolve with the evidence row (failing-then-passing
     test, CI result, and a brief-alignment citation naming the brief
     section or REQ/D-ID the fix aligns with).
   - *Needs sign-off* → apply on the branch in its own commit, add a
     pending-sign-off checklist entry (see below).
   - *Needs-human-judgment candidate* → climb the resolution ladder (see
     below). A rung that answers re-routes the finding to the disposition the
     answer implies, with the rung's citation recorded. Only an irreducible
     fork stays in the bucket: it queues for loop end, or hard-pauses if it
     blocks further progress on the unit.
4. **Declined-with-rationale** is available at any step after validation: the
   agent may close the finding without applying it, recording the reasoning
   in the declined log. Declining is a disposition, not an exemption from
   recording.

Every routed finding ends in exactly one of five terminal dispositions:
applied, resolved with evidence, applied pending sign-off, declined with
rationale, or queued for loop end. A finding at a hard pause is not a sixth
ending: it stands suspended until the human directs it into one of the
five. There is no silent drop.

## Commit discipline

The gate's review mechanic depends on revertability, so commit granularity is
part of the contract (and history is never rewritten; new commits only).

- **Needs-sign-off items commit one per finding**, never batched. The
  checklist entry names the commit, so "approve by leaving it, reject with
  one revert" is literally true per item: `git revert <sha>` undoes exactly
  one finding. The commit subject ends with the `[pending-sign-off]`
  marker, so the branch itself identifies these commits.
- **Auto-applicable and Agent-resolvable items may batch** into one commit
  per loop iteration. Their audit rows record the commit they landed in.
  Declared scoping (per [Proportionality](proportionality.md)): these items
  are not pending a human decision, so iteration-granular revert is
  sufficient; the per-finding guarantee is reserved for the bucket whose
  checklist asks the human to judge each item.
- Regression tests written for Agent-resolvable items land in the same
  commit as the fix they prove.

## Pending-sign-off checklist

The canonical format for the draft PR description (REQ-C1.3). Generated, not
hand-edited; a loop exit regenerates the whole section in place, so re-runs
never duplicate entries. The branch is the source of truth for
regeneration, scoped to the PR's commit range: the section is rebuilt from
the `[pending-sign-off]`-marked commits ahead of the base branch, minus any
commit a revert inside the same range has undone, never from a side state
file. Marked commits that arrive through a merge from the base branch were
approved when their own PR merged; they never re-enter the checklist.

```markdown
## Pending sign-off

- [ ] **PS-1** <one-line finding and the fix applied> · commit `<sha>`
  - Route reason: <which Needs-sign-off route matched>
  - Reject with: `git revert <sha>`
```

- IDs are `PS-<n>`, assigned in first-applied order, stable across
  regenerations, never reused on the branch.
- The operative semantics are the doctrine's: the human approves an item by
  leaving its commit in place and rejects it with the named revert, at PR
  review. The draft→ready flip with the commit still present is the
  approval. The checkbox is a reading aid for tracking review progress, not
  the approval mechanism.
- An empty checklist still emits, with a single `none` row (the same
  anti-silent-pruning guard as the four tables).

## Audit record formats

The four tables emit in fixed order at every loop exit, an empty bucket as a
single `none` row (REQ-C1.5). Canonical columns:

| Table | Columns |
| --- | --- |
| Auto-applicable | # · Finding · Tool + rule cited · Fix · Commit |
| Agent-resolvable | # · Finding · Test (path + name) · Before → after output · CI result · Brief alignment · Commit |
| Needs sign-off | # · Finding · Fix applied · Route reason · Commit · Checklist ID |
| Needs human judgment | # · Fork · Ladder record · Outcome · Options |

The **Needs human judgment table is the ladder audit**: every finding that
entered the ladder gets a row, including those a rung resolved. A resolved
row's Outcome names the rung and the disposition it re-routed to (for
example: "resolved at rung 1, brief Section 2; re-routed to
Needs sign-off #2"); its Options column is empty. Only irreducible rows carry bespoke
options and queue. This is what makes "a fork answerable from the brief never
reaches the human" verifiable after the fact rather than asserted.

The **declined log** accompanies the tables wherever they emit:

| Table | Columns |
| --- | --- |
| Declined log | # · Finding · Validation summary · Rationale · Where re-raisable |

Declined findings remain visible at PR review and are re-raisable there
(REQ-C1.6); the log in the PR body is what makes the re-raise possible.

Both the tables and the declined log emit twice: in the loop's handoff
summary, and in the draft PR body as the audit record review works from
(assembling the PR body is the parent skill's job per REQ-E1.5; this
document defines the formats it assembles). Table content is a committed
artifact: finding text and captured output must respect artifact
data-hygiene ([Security Posture](security-posture.md)) before they land in
a PR body.

## Resolution ladder procedure

For each Needs-human-judgment candidate, climb in order and stop at the
first rung that answers (REQ-C1.7). Stopping at the first answering rung is
also the precedence rule: a lower rung is never consulted to second-guess a
higher one.

1. **Brief or spec citation.** Search the kickoff brief and the spec bundle
   for a decision, constraint, or REQ that answers the fork. Answered →
   adopt, record `rung 1: <brief section or REQ/D-ID>`.
2. **Research.** Apply [Research Rigor](research-rigor.md): official docs,
   the library's own source and tests, issues and RFCs. Answered → adopt,
   record `rung 2: <sources consulted>`.
3. **Project convention.** Search the project's established patterns and
   sibling implementations. Answered → adopt, record
   `rung 3: <precedent cited>`.

Recording is mandatory at every consulted rung, answered or not: the ladder
record in the judgment table must show which rungs were climbed and what
each returned, so an irreducible fork demonstrably exhausted all three
before queuing. Irreducible forks queue for loop end with bespoke options
per the categorization doctrine (the actual decision branches, never timing
labels); a fork that blocks further progress on the unit hard-pauses instead
of queuing.

## Pause protocol

Exactly two triggers interrupt mid-loop (REQ-C1.4): the zone screen fires,
or an irreducible fork blocks progress. Everything else flows to loop end.
What a pause does depends on who is watching:

- **Attended session.** Stop the loop. Present the finding, the zone or fork
  that triggered the pause, and the recommended fix or the concrete
  alternatives. Wait for direction; apply nothing in the zone until the
  human directs it.
- **Dispatched or unattended worker.** No human is at the prompt: record the
  unit to `tasks.md` Awaiting input (the halt destination REQ-F1.5
  defines) with the finding,
  the trigger, and the recommended fix or alternatives, then end the step.
  Work already applied in this loop stays on the branch as committed: a
  pause never resets, stashes, or rewrites prior dispositions (each remains
  one revert from undone at review).
  The pause content must respect artifact data-hygiene
  ([Security Posture](security-posture.md)): describe the zone finding
  without reproducing secrets or sensitive operational detail.

The human's direction is the finding's disposition: the finding does not
re-enter the routing order and the zone screen does not fire again. The
agent carries the direction out with the directed disposition's own
mechanics and records it in the corresponding table row. A directed
application in a zone still follows the commit discipline above (its own
commit when the direction is to apply it pending sign-off).

## Loop-end handoff

At loop end, emit in this order: the four tables, the declined log, the
pending-sign-off checklist, and the queued irreducible forks with their
bespoke options. The forks are the only items that ask the human a question
at handoff; everything else is audit. The parent skill folds the checklist,
tables, and declined log into the draft PR body it owns (REQ-E1.5).

## Consumers and conformance

`/self-review` and `/polish` (Task 11) and `/execute-task`'s convergence
step (Task 12) implement this wiring. The conformance scenarios live in the
bootstrap test-spec's REQ-C1.3, REQ-C1.4, and REQ-C1.7 entries
(state/trigger/outcome), exercised by the manual-verification sweep
(Task 18) together with the REQ-C1.5 and REQ-C1.6 manual entries.
