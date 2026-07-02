# Output & Accumulator Hygiene — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-02
**Format-version:** 1

Eight tasks. The `Dependencies:` lines are authoritative (no drawn graph — REQ-E1.4
applied to this bundle from birth). The guard-first lesson (bootstrap selection-policy
observation, 2026-06-11) is encoded as edges: Task 5's link lint protects every
doc-writing task, so Tasks 3, 4, 6, and 8 depend on it explicitly. Critical path:
Task 1 → Task 2.

## Forward plan

### Task 1 — Fragment queue and consolidation primitive

- **Deliverables:** `specs/_observations/queue/` convention (fragment filename grammar
  `<YYYY-MM-DD>-<slug>.md` with hostile-name screening); a lock-guarded, idempotent
  consolidation routine (append fragment entries to `opportunities.md` chronologically,
  delete consumed fragments, one commit; crash-safe ordering — append before delete);
  accumulator-taxonomy doctrine amendment naming the queue surface, its class, reader,
  and drain ritual.
- **Done when:** a test creates two fragments as concurrent writers would and
  consolidation produces a conflict-free, chronologically ordered log with the fragments
  deleted; a test proves existing log entries survive byte-for-byte apart from appends;
  the doctrine names the queue surface; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1 · REQ-B1.1, REQ-B1.2, REQ-B1.3
- **Estimated effort:** 2 days

### Task 2 — Consumer wiring for the queue

- **Deliverables:** `/orchestrate --bookkeeping` runs consolidation; `/spec-draft` mines
  queue plus log and consolidates opportunistically at mining time; the drain pass's
  observation surface counts queue entries in the unmined count and oldest-age figures.
- **Done when:** a drain-report fixture with queue entries shows them in the unmined
  surface; the two skills' instructions name the queue in their mining/bookkeeping steps;
  `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-B1.2, REQ-B1.4
- **Estimated effort:** 1 day

### Task 3 — PR-body contract

- **Deliverables:** a PR-body assembly section in the gate-wiring doctrine (summary-first
  content list, complete audit record collapsed in `<details>`, no hard-wrapped prose,
  update-in-place keeps the structure), with an example body; `/execute-task` and
  `/self-review` emission steps rewritten to cite the section instead of carrying their
  own body lists.
- **Done when:** the section exists with the example; both skills cite it and carry no
  duplicated body-content list; the example body contains no hard-wrapped prose;
  `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4
- **Estimated effort:** 1 day

### Task 4 — Marker canonicalization and emit-time guard

- **Deliverables:** gate-wiring doctrine pins the canonical end-of-subject placement, the
  branch-scoped consumption rule, and the merge-strategy matrix; a `--marker` mode in
  `scripts/check-commit-msgs.sh` (canonical placement passes; pre-prefix, mid-subject,
  and marker-in-PR-title rejected); skills that write marked commits self-lint via the
  `--marker` mode before committing; the CI commit-range invocation unchanged.
- **Done when:** `--marker` fixtures cover the four placements plus the PR-title case;
  the CI workflow and range-lint invocation are diff-identical apart from any PR-title
  `--marker` addition; emitting skills' instructions name the self-lint step;
  `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-3 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 1 day

### Task 5 — Reference-integrity lint

- **Deliverables:** `scripts/check-doc-links.sh` rule: relative links leaving `doctrine/`
  other than to `../config/` are errors (sibling doctrine links and in-page anchors
  unaffected); the guard-catalog delivered-dead link fixed to conform.
- **Done when:** fixtures show a doctrine→`../skills/` link failing and sibling-doctrine
  plus `../config/` links passing; repo-wide `check:links` is green; `mise run check`
  passes.
- **Dependencies:** none
- **Citations:** D-4 · REQ-D1.1, REQ-D1.3, REQ-D1.4
- **Estimated effort:** half day

### Task 6 — `[[name]]` neutralization and fleet-citation reconciliation

- **Deliverables:** a `/spec-draft` completion-step rule neutralizing `[[name]]` links
  into prose plus a `## Sources` pointer (the sanctioned observations-log citation form);
  the orchestration-fleet bundle's `[[…]]` citations reconciled via the expression-only
  amendment ritual (dated changelog entry, re-anchor).
- **Done when:** the skill step exists; a repo-wide search finds no `[[name]]` token in
  committed spec artifacts; the fleet bundle's changelog records the amendment and its
  brief anchor matches `scripts/spec-anchor.sh` output; `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-4 · REQ-D1.1, REQ-D1.2, REQ-D1.4
- **Estimated effort:** 1 day

### Task 7 — Organic completion-annotation stamping

- **Deliverables:** the level-triggered reconcile stamps
  `Completed · PR #<n> merged <YYYY-MM-DD>` in the same write that places a
  completion-evidenced task in `## Completed`, reusing the derivation's existing
  merged-PR evidence batch; honest no-remote degradation (date-only or no stamp);
  the supersede pointer on `orchestration-concurrency`'s annotations-preserved clause
  per the ritual (pointer annotation, no prose edits in the Done bundle).
- **Done when:** a fixture with merged-PR evidence yields the canonical string on the
  moved block; a no-remote fixture shows the degraded behavior and no invented PR
  number; non-completion annotations remain byte-for-byte; the supersede pointer exists;
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-5 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 8 — Derived-content authoring guidance

- **Deliverables:** meta-spec (`doctrine/spec-format.md`) guidance edits: hand-drawn
  dependency graphs dropped from the `tasks.md` intro-prose description in favor of
  `Dependencies:` lines plus the on-demand graph view; kickoff-brief guidance gains the
  cite-don't-copy convention for derived figures.
- **Done when:** the meta-spec no longer suggests a drawn graph and names the
  cite-don't-copy convention; the meta-spec versioning note records the guidance change;
  `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-5 · REQ-E1.1, REQ-E1.3, REQ-E1.4
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

- Cross-repo / multi-target observation routing — the deferred accumulator redesign
  (see requirements Out of scope).
- Input-side parser consolidation (spec-parse and scope-grammar duplication entries).
- Retroactive edits to already-merged PR bodies.
- The escaper/sanitizer consolidation — extracted to the standalone
  `chore/esc-consolidation` (2026-07-02).
