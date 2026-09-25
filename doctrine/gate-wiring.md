# Gate Wiring: the Act-Then-Review Loop

[Finding Categorization](finding-categorization.md) defines the four buckets,
their predicates, and the gate's principles. This document is the operational
wiring a gate-wired skill (`/self-review`, `/polish`, and `/execute-task`'s
convergence phase) implements. The two share one contract; where this one names
a bucket, predicate, or zone, the categorization doctrine's definition governs.

Citations: REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6 ·
operator-dialogue REQ-I1.2, REQ-I1.4 · operator-dialogue D-14, D-15 ·
prose-disposition REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4 ·
prose-disposition D-5 · custom-steps REQ-D1.2, REQ-D1.5 · human-gates
REQ-B1.1, REQ-B1.9, D-3.
The PR-body assembly section additionally realizes output-hygiene
REQ-A1.1–REQ-A1.4 and D-2.

## Input contract

The wiring starts where [Validation Rigor](validation-rigor.md) ends: its
input is validated findings, each carrying the evidence that confirmed it. Its
output is a disposition per finding plus the audit record (four tables,
declined log, pending-sign-off checklist) the draft PR carries to review.

## Routing order

Route each validated finding through these steps in order. The zone screen
runs first: a hard-disqualifier zone forces a pause regardless of the finding's
bucket.

1. **Zone screen.** If the finding, or any file its fix would touch, falls in
   a hard-disqualifier zone (the categorization doctrine's list:
   security-sensitive code, migrations or destructive operations, CI
   configuration, lockfiles, secrets files), trigger a hard pause (see Pause
   protocol). Record the recommended fix; do not apply it.
2. **Bucket assignment** per the categorization predicates. When a predicate
   condition is uncertain, route downward exactly as the categorization
   doctrine directs (toward Needs sign-off or Needs human judgment), never
   upward.
3. **Disposition by bucket:**
   - *Auto-applicable* → apply now, audit row with the rule citation.
   - *Agent-resolvable* → resolve with the evidence row (failing-then-passing
     test, CI result, and a brief-alignment citation naming the brief section
     or REQ/D-ID it aligns with).
   - *Needs sign-off* → apply on the branch per the commit discipline below,
     add a pending-sign-off checklist entry.
   - *Needs-human-judgment candidate* → climb the resolution ladder (see
     below). A rung that answers re-routes the finding to the disposition the
     answer implies, with the rung's citation recorded. Only an irreducible
     fork stays in the bucket: it queues for loop end, or hard-pauses if it
     blocks further progress on the unit.
4. **Declined-with-rationale** is available at any step after validation,
   closing the finding without applying it and recording the reasoning in the
   declined log.

Every routed finding ends in exactly one of five terminal dispositions:
applied, resolved with evidence, applied pending sign-off, declined with
rationale, or queued for loop end. A hard pause is not a sixth ending; the
finding stays suspended until the human directs it into one of the five.
There is no silent drop.

## Commit discipline

Commit granularity is part of the contract, and the loop adds commits rather
than reshaping them ([Human Gates](human-gates.md)). A **loop iteration** is
one act-then-review cycle: the pass that discovers, validates, and
dispositions a set of findings, closing when the next review pass opens.

- **A Needs-sign-off fix that changes code behaviour commits on its own**, so
  `git revert <sha>` undoes exactly one finding. A fix that edits code and
  its prose together is that code fix's commit, never a batch member.
- **Needs-sign-off fixes that edit only prose batch** into one commit per
  loop iteration, carrying the manifest below. A partial revert there is a
  hand edit the manifest guides: the per-finding revert guarantee earns its
  cost for behaviour, where a partial revert can break things, and not for
  wording.
- Both sign-off shapes carry the sign-off trailer below, stamped once on a
  batch, so the branch itself identifies them.
- **Auto-applicable and Agent-resolvable items may batch** into one commit
  per loop iteration; their audit rows record the commit they landed in.
  Declared scoping (per [Proportionality](proportionality.md)): not pending a
  human decision, so iteration-granular revert suffices.
- Regression tests written for Agent-resolvable items land in the same
  commit as the fix they prove.

**The prose batch's manifest.** The commit body carries one line per fix: the
file, the rule as it read before (`absent` for an added passage), and the
rule as it reads after.

```text
- doctrine/proportionality.md — before: a declared scoping names the rung
  · after: a declared scoping names the doctrine it narrows
- doctrine/research-rigor.md — before: absent · after: a version-sensitive
  API is a research trigger
```

## The `Planwright-Sign-Off` trailer

A sign-off commit carries `Planwright-Sign-Off: PS-<n>` as a git trailer,
stamped through `scripts/planwright-commit-trailers.sh`, under a plain
conventional subject. `PS-<n>` is the branch's next free id, written once at
commit time and never recomputed from commit order. A later commit carrying
`Planwright-Sign-Off-Rejected: PS-<n>` rejects that one item where a plain
revert cannot (one finding of a commit several findings share, or a merge
resolution).

**Branch-scoped consumption.** The trailer's sole consumer is the checklist
regeneration below, which reads it through git's trailer parser over the PR's
`base..head` range, never from mainline, and from subject text only through
the legacy line below. Trailers arriving
through a merge from the base were approved when their own PR merged and never
re-enter the checklist. A trailer line never appears in a PR title; the
PR-title lint (`--marker title`, kept one release) rejects it there.

**Merge-strategy matrix.** A squash merge folds the trailers into the squash
body under the PR title, which must stay free of them since it becomes the
mainline subject; a merge commit keeps them as ancestor history.

A legacy `[pending-sign-off]` subject suffix counts as a `Planwright-Sign-Off` trailer
taking the next free id; no history is rewritten and no branch is swept. Until
the trailer helper ships, a skill writing the suffix conforms through that line.

## Pending-sign-off checklist

The canonical format for the draft PR description (REQ-C1.3). Generated, not
hand-edited; a loop exit regenerates the whole section in place, so re-runs
never duplicate entries. It rebuilds from the trailers, minus any commit a
revert in the same range undid (paired by git's `This reverts commit <sha>`
body line) and any item a rejected trailer names, never from a side state
file. A range it cannot resolve fails by name, never as an empty checklist.

```markdown
## Pending sign-off

- [ ] **PS-1** <one-line finding and the fix applied> · commit `<sha>`
  - Route reason: <which Needs-sign-off route matched>
  - Reject with: `git revert <sha>`
```

- IDs are the trailer values, so they are stable across regenerations and
  never reused: a reverted or rejected item drops out of the rendered
  checklist and its number stays a gap.
- The checkbox is a reading aid, not the approval: the human approves every
  item by the approval act [Human Gates](human-gates.md) names, never by the
  draft→ready flip, and rejects one before that act by its recipe.
- An empty checklist still emits, with a single `none` row.

A batched prose commit renders as **one entry with one sub-item per manifest
line**:

```markdown
- [ ] **PS-2** 2 meaning-class prose fixes · commit `<sha>`
  - Route reason: meaning-class prose on surfaces that predate the PR
  - `<file>` — before: `<rule>` · after: `<rule>`
  - `<file>` — before: absent · after: `<rule>`
  - Reject with: `git revert <sha>`; rejecting one sub-item is a hand edit
    the manifest guides
```

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
row's Outcome names the rung and the disposition it re-routed to (e.g.
"resolved at rung 1; re-routed to Needs sign-off #2"); its Options column is
empty. Only irreducible rows carry bespoke options and queue.

The **declined log** accompanies the tables wherever they emit:

| Table | Columns |
| --- | --- |
| Declined log | # · Finding · Validation summary · Rationale · Where re-raisable |

A batched prose commit keeps **one Needs-sign-off row per finding**, the rows
sharing a Commit and a Checklist ID: batching changes the commit, never the
audit record's granularity.

Table content is a committed artifact: finding text and captured output must
respect artifact data-hygiene ([Security Posture](security-posture.md)) before
landing in a PR body.

## Resolution ladder procedure

For each Needs-human-judgment candidate, climb the categorization doctrine's
three rungs in order and stop at the first that answers (REQ-C1.7). A lower
rung never second-guesses a higher one. Answered → adopt, recording the rung
that answered: `rung 1: <brief section or REQ/D-ID>`,
`rung 2: <sources consulted>`, `rung 3: <precedent cited>`.

Recording is mandatory at every consulted rung, answered or not: the ladder
record in the judgment table must show which rungs were climbed and what each
returned. Irreducible forks queue for loop end with bespoke options per the
categorization doctrine (the actual decision branches, never timing labels); a
fork blocking further progress on the unit hard-pauses instead of queuing.

## Pause protocol

Exactly two triggers interrupt mid-loop (REQ-C1.4): the zone screen fires,
or an irreducible fork blocks progress. Everything else flows to loop end. A
custom step ending its in-run point under `on-failure: halt`
([custom-steps](custom-steps.md)) takes the destinations below with the
entry contents its posture rule pins, a dispatched worker's launch-record
attendance (interactive asks, headless parks), never a loop trigger.

- **Attended session.** Stop the loop and present the finding, the zone or
  fork, and the recommended fix or alternatives. Wait for direction; apply
  nothing in the zone until directed.
- **Dispatched or unattended worker.** Record the unit to `tasks.md` Awaiting
  input (the halt destination REQ-F1.5 defines), with the finding, the
  trigger, and the recommended fix or alternatives, then end the step. Work
  already applied stays on the branch as committed: a pause never resets,
  stashes, or rewrites prior dispositions. The pause content respects artifact
  data-hygiene ([Security Posture](security-posture.md)): describe the
  finding without reproducing secrets or sensitive operational detail.

The human's direction is the finding's disposition: the finding does not
re-enter the routing order and the zone screen does not fire again. The agent
carries it out with the directed disposition's mechanics and records it in
its table row. A directed application in a zone still follows
the commit discipline above (its own commit when directed to apply pending
sign-off).

## Loop-end handoff

At loop end the full record — the four tables, the declined log, the
pending-sign-off checklist, then the queued forks and their bespoke options,
in that order — is **artifact-side** in full: the draft PR body per PR-body
assembly below (REQ-E1.5), or its skill's named artifact. The **turn** gets its
projection: per-bucket counts, the residue itself projected (each pending
sign-off and each open fork as one line, not its audit row), and where the full
record landed ([Interaction Style](interaction-style.md), the arbitration).

## PR-body assembly

This section is the single normative home (output-hygiene D-2) for how the
emitting skills (`/execute-task` and `/self-review`) assemble the draft PR body
from the loop-end handoff. Both skills **cite this section** rather than
carrying their own layout (REQ-A1.4). The layout is judgment-applied, not
template-expanded: each skill supplies its own summary inputs.

**Summary first, audit collapsed.**

1. **A human summary, above the fold** (REQ-A1.1): what changed and why, how to
   review it, the task IDs the PR implements, the REQs satisfied, and the open
   pending-sign-off items. Prose plus a short fact list a reviewer reads
   without expanding anything. Each emitting skill names which inputs feed the
   summary (its task IDs, REQ citations, test additions).
2. **The complete audit record, collapsed** (REQ-A1.2): the loop-end handoff,
   `/self-review`'s lens-coverage table and pass summary, and, for
   `/execute-task`, the per-point step tables
   ([custom-steps](custom-steps.md); a point whose list was empty emits a
   `none` row), inside a `<details>` block, so it never buries the summary.
   Collapsed is not abridged: every table and row the wiring emits is present
   inside the block.

**Prose is never hard-wrapped** (REQ-A1.3): GitHub reflows markdown, so a
fixed-column wrap only inserts ragged mid-sentence breaks. Line breaks in the
emitted body appear only where markdown is structural (list items, table rows,
code fences, headings), never mid-paragraph.

**Updates keep the structure** (REQ-A1.4). Re-emitting the body on a later
push regenerates the summary and the collapsed audit in place, preserving this
layout: never a second summary, never a second audit block, never the audit
flattened out of its `<details>`. Handwritten body content outside the
generated sections survives the update.

**Pending-sign-off items appear in both places**: named in the summary, so a
reviewer sees the open decisions without expanding the audit, and in full
inside the collapsed checklist, which is authoritative.

### Example

An `/execute-task` body follows; a `/self-review` body has the same shape,
adding the lens-coverage table and pass summary inside the collapsed record
and dropping the kickoff-brief and task-graph inputs and the step tables. Its
completion stamp is **format-version 1**; a v2 bundle stamps none (derived),
per [`spec-format.md`](spec-format.md).

```markdown
## Summary

Closes the unowned-refresh gap REQ-E1 names: a merged task's block gets `Completed · PR #<n> merged <YYYY-MM-DD>`, degrading to a date-only form with no remote.

**How to review:** `scripts/tasks-pr-sync.sh` and its `tests/` fixtures.

- **Tasks:** output-hygiene/7 · **REQs:** REQ-E1.1, REQ-E1.2
- **Brief:** `specs/output-hygiene/kickoff-brief.md`
- **Tests:** `tests/tasks-pr-sync.bats` — merged-PR evidence yields the canonical string; a no-remote fixture yields the date-only form, never an invented PR number.
- **Pending sign-off:** PS-1 (2 prose fixes) — see the collapsed checklist.

<details>
<summary>Audit record</summary>

## Auto-applicable

| # | Finding | Tool + rule | Fix | Commit |
| --- | --- | --- | --- | --- |
| 1 | unquoted expansion in the stamp path | shellcheck SC2086 | quoted it | `abc1234` |

## Needs sign-off

| # | Finding | Fix applied | Route reason | Commit | Checklist ID |
| --- | --- | --- | --- | --- | --- |
| 1 | the stamp's degraded case is documented as no stamp | reworded to the date-only form | meaning-class prose, pre-existing surface | `def5678` | PS-1 |
| 2 | the no-remote arm states a duty its REQ permits | reworded to the permission | meaning-class prose, pre-existing surface | `def5678` | PS-1 |

*(Elided for space, though a real record carries them in full: `Agent-resolvable`, `Needs human judgment`, the declined log, and the step tables, the convergence one carrying its `polish` row and the rest `none`.)*

## Pending sign-off

- [ ] **PS-1** 2 meaning-class prose fixes · commit `def5678`
  - Route reason: meaning-class prose on surfaces that predate the PR
  - `docs/annotations.md` — before: the degraded case prints no stamp · after: it prints the date-only form
  - `scripts/tasks-pr-sync.sh` header comment — before: the no-remote arm must stamp · after: it may stamp
  - Reject with: `git revert def5678`; rejecting one sub-item is a hand edit the manifest guides

</details>
```

## Conformance

The conformance scenarios live in the bootstrap test-spec's
REQ-C1.3, REQ-C1.4, and REQ-C1.7 entries
(state/trigger/outcome), exercised by the manual-verification sweep the work
fork's first run carries, with the REQ-C1.5 and REQ-C1.6 manual entries.
