# Gate Wiring: the Act-Then-Review Loop

[Finding Categorization](finding-categorization.md) defines the four buckets,
their predicates, and the gate's principles. This document is the operational
wiring a gate-wired skill (`/self-review`, `/polish`, and `/execute-task`'s
convergence step) implements. The two share one contract; where this one names
a bucket, predicate, or zone, the categorization doctrine's definition governs.

Citations: REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6.
The PR-body assembly section additionally realizes output-hygiene
REQ-A1.1–REQ-A1.4 and D-2.

## Input contract

The wiring starts where [Validation Rigor](validation-rigor.md) ends: its
input is validated findings, each carrying the evidence that confirmed it. Its
output is a disposition per finding plus the audit record (four tables,
declined log, pending-sign-off checklist) the draft PR carries to review.
Discovery and validation are upstream.

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
rationale, or queued for loop end. A hard pause is not a sixth ending; the
finding stays suspended until the human directs it into one of the five.
There is no silent drop.

## Commit discipline

Commit granularity is part of the contract; history is never rewritten (new
commits only).

- **Needs-sign-off items commit one per finding**, never batched, so
  `git revert <sha>` undoes exactly one finding. The commit subject ends with
  the `[pending-sign-off]` marker, so the branch itself identifies these
  commits.
- **Auto-applicable and Agent-resolvable items may batch** into one commit
  per loop iteration; their audit rows record the commit they landed in.
  Declared scoping (per [Proportionality](proportionality.md)): not pending a
  human decision, so iteration-granular revert suffices; the per-finding
  guarantee is reserved for the sign-off bucket.
- Regression tests written for Agent-resolvable items land in the same
  commit as the fix they prove.

## The `[pending-sign-off]` marker

**Canonical placement (REQ-C1.1).** The marker sits at the very end of the
subject, after the conventional prefix and description:

```text
type(scope): description [pending-sign-off]
```

End-of-subject is the one canonical position; a pre-prefix marker
(`[pending-sign-off] type(scope): …`) or a mid-subject marker breaks the
conventional format or slips the format check.

**Emit-time guard (REQ-C1.3), not range-time.** A skill writing a marked
commit self-lints the subject before committing, while it can still reword —
`printf '%s\n' "$subject" | scripts/check-commit-msgs.sh --marker subject --stdin` —
requiring the canonical placement (misplaced and duplicate markers fail) on
top of the conventional check. It is deliberately *not* wired
into the CI commit-range lint (history is never rewritten); that range lint
stays marker-agnostic.

**Branch-scoped consumption (REQ-C1.4).** The marker is meaningful only on the
PR branch. Its sole consumer is the pending-sign-off checklist regeneration
(below), which rebuilds from the `[pending-sign-off]`-marked commits in the
PR's `base..head` range, never from mainline. Markers arriving through a merge
from the base were approved when their own PR merged and never re-enter the
checklist. The marker must never appear in the **PR title** (it becomes the
squash-merge subject, landing on mainline); the PR-title lint rejects it there
(`--marker title`).

**Merge-strategy matrix.** Where a branch's marked subjects end up depends on
the merge strategy:

| Strategy | Marked subjects | Merge subject |
| --- | --- | --- |
| Squash (sanctioned) | concatenated into the squash **body** as relic text | the PR title — kept marker-free by `--marker title` |
| Merge commit | persist as ancestor history (an accurate record) | the merge subject itself is clean |
| Rebase-merge | would land marked subjects directly on mainline | **forbidden framework-wide** (never rebase); excluded by invariant, not handled |

## Pending-sign-off checklist

The canonical format for the draft PR description (REQ-C1.3). Generated, not
hand-edited; a loop exit regenerates the whole section in place, so re-runs
never duplicate entries. It rebuilds from the branch per the marker's
branch-scoped consumption, minus any commit a revert in the same range undid,
never from a side state file.

```markdown
## Pending sign-off

- [ ] **PS-1** <one-line finding and the fix applied> · commit `<sha>`
  - Route reason: <which Needs-sign-off route matched>
  - Reject with: `git revert <sha>`
```

- IDs are `PS-<n>`, a pure function of the branch: every
  `[pending-sign-off]` commit in the range is numbered in commit order,
  *including* commits a later revert undid (a reverted item drops out of the
  rendered checklist but keeps its number as a gap). IDs are thus stable
  across regenerations and never reused, with no side state persisted.
- The operative semantics are the doctrine's: the human approves an item by
  leaving its commit in place (the draft→ready flip with the commit still
  present is the approval) and rejects it with the named revert, at PR review.
  The checkbox is a reading aid for review progress, not the approval
  mechanism.
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
row's Outcome names the rung and the disposition it re-routed to (e.g.
"resolved at rung 1; re-routed to Needs sign-off #2"); its Options column is
empty. Only irreducible rows carry bespoke options and queue.

The **declined log** accompanies the tables wherever they emit:

| Table | Columns |
| --- | --- |
| Declined log | # · Finding · Validation summary · Rationale · Where re-raisable |

Declined findings remain re-raisable at PR review (REQ-C1.6).

The tables and declined log emit both in the handoff summary and in the draft
PR body (REQ-E1.5). Table content is a committed artifact: finding text and
captured output must respect artifact data-hygiene
([Security Posture](security-posture.md)) before landing in a PR body.

## Resolution ladder procedure

For each Needs-human-judgment candidate, climb in order and stop at the first
rung that answers (REQ-C1.7). A lower rung never second-guesses a higher one.

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
record in the judgment table must show which rungs were climbed and what each
returned. Irreducible forks queue for loop end with bespoke options per the
categorization doctrine (the actual decision branches, never timing labels); a
fork blocking further progress on the unit hard-pauses instead of queuing.

## Pause protocol

Exactly two triggers interrupt mid-loop (REQ-C1.4): the zone screen fires,
or an irreducible fork blocks progress. Everything else flows to loop end.
What a pause does depends on who is watching:

- **Attended session.** Stop the loop. Present the finding, the triggering
  zone or fork, and the recommended fix or concrete alternatives. Wait for
  direction; apply nothing in the zone until the human directs it.
- **Dispatched or unattended worker.** No human is at the prompt: record the
  unit to `tasks.md` Awaiting input (the halt destination REQ-F1.5 defines),
  with the finding, the trigger, and the recommended fix or alternatives, then
  end the step. Work already applied stays on the branch as committed: a pause
  never resets, stashes, or rewrites prior dispositions. The pause content must
  respect artifact data-hygiene ([Security Posture](security-posture.md)):
  describe the zone finding without reproducing secrets or sensitive
  operational detail.

The human's direction is the finding's disposition: the finding does not
re-enter the routing order and the zone screen does not fire again. The agent
carries it out with the directed disposition's mechanics and records it in the
corresponding table row. A directed application in a zone still follows
the commit discipline above (its own commit when directed to apply pending
sign-off).

## Loop-end handoff

At loop end, emit in this order: the four tables, the declined log, the
pending-sign-off checklist, and the queued irreducible forks with their
bespoke options. The parent skill folds them into the draft PR body per the
PR-body assembly section below (REQ-E1.5).

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
2. **The complete audit record, collapsed** (REQ-A1.2): the loop-end handoff
   (the four bucket tables, the declined log, the pending-sign-off checklist,
   and any queued forks, plus `/self-review`'s lens-coverage table and pass
   summary) inside a `<details>` block, so it never buries the summary.
   Collapsed is not abridged: every table and row the wiring emits is present
   inside the block.

**Prose is never hard-wrapped** (REQ-A1.3): GitHub reflows markdown, so a
fixed-column wrap only inserts ragged mid-sentence breaks. Line breaks in the
emitted body appear only where markdown is structural (list items, table rows,
code fences, headings), never mid-paragraph. (This governs the emitted PR body,
not this file's own source,
which wraps per markdownlint; the example below is code-fenced so it shows the
unwrapped body verbatim.)

**Updates keep the structure** (REQ-A1.4). Re-emitting the body on a later
push regenerates the summary and the collapsed audit in place, preserving this
layout: never a second summary, never a second audit block, never the audit
flattened out of its `<details>`. Body content outside the generated sections
(handwritten notes) survives the update.

**Pending-sign-off items appear in both places**: named in the summary, so a
reviewer sees the open decisions without expanding the audit, and in full
inside the collapsed checklist (commit `sha` and named revert per item). The
summary lists them; the checklist is authoritative.

### Example

An `/execute-task` body follows; a `/self-review` body has the same shape,
adding the lens-coverage table and pass summary inside the collapsed record
and dropping the kickoff-brief and task-graph inputs from the summary. Its
completion stamp is **format-version 1**; a v2 bundle stamps none (derived),
per [`spec-format.md`](spec-format.md).

```markdown
## Summary

Closes the unowned-refresh gap REQ-E1 names: stamps the reconcile's completion annotation so a merged task's block gets `Completed · PR #<n> merged <YYYY-MM-DD>`, degrading with no remote to a date-only form or no stamp.

**How to review:** `scripts/tasks-pr-sync.sh` and its `tests/` fixtures.

- **Tasks:** output-hygiene/7 · **REQs:** REQ-E1.1, REQ-E1.2
- **Brief:** `specs/output-hygiene/kickoff-brief.md`
- **Tests:** `tests/tasks-pr-sync.bats` — merged-PR evidence yields the canonical string; a no-remote fixture yields the date-only form or no stamp, never an invented PR number.
- **Pending sign-off:** PS-1 (annotation-format wording) — see the collapsed checklist.

<details>
<summary>Audit record</summary>

## Auto-applicable

| # | Finding | Tool + rule | Fix | Commit |
| --- | --- | --- | --- | --- |
| 1 | unquoted expansion in the stamp path | shellcheck SC2086 | quoted it | `abc1234` |

## Agent-resolvable

| # | Finding | Test | Before → after | CI | Brief alignment | Commit |
| --- | --- | --- | --- | --- | --- | --- |
| none | | | | | | |

## Needs sign-off

| # | Finding | Fix applied | Route reason | Commit | Checklist ID |
| --- | --- | --- | --- | --- | --- |
| 1 | wording touches a documented output format | reworded the degraded-case string | user-observable doc contract | `def5678` | PS-1 |

## Needs human judgment

| # | Fork | Ladder record | Outcome | Options |
| --- | --- | --- | --- | --- |
| none | | | | |

## Declined log

| # | Finding | Validation summary | Rationale | Where re-raisable |
| --- | --- | --- | --- | --- |
| none | | | | |

## Pending sign-off

- [ ] **PS-1** annotation-format wording reworded for the no-remote case · commit `def5678`
  - Route reason: touches a documented output format a downstream reader parses
  - Reject with: `git revert def5678`

</details>
```

## Consumers and conformance

`/self-review` and `/polish` (Task 11) and `/execute-task`'s convergence step
(Task 12) implement this wiring. The conformance scenarios live in the
bootstrap test-spec's REQ-C1.3, REQ-C1.4, and REQ-C1.7 entries
(state/trigger/outcome), exercised by the manual-verification sweep the work
fork's first run carries, with the REQ-C1.5 and REQ-C1.6 manual entries.
