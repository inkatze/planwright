# Output & Accumulator Hygiene — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-08
**Format-version:** 1

Six live tasks (Tasks 1–2 were superseded 2026-07-08 — the observations-recording
concern moved to `specs/observation-recording`; their blocks are preserved under
`## Out of scope` and are never dispatched). The `Dependencies:` lines are authoritative
(no drawn graph — REQ-E1.4 applied to this bundle from birth). The guard-first lesson
(bootstrap selection-policy observation, 2026-06-11) is encoded as edges: Task 5's link
lint protects every doc-writing task, so Tasks 3, 4, 6, and 8 depend on it explicitly.
Remaining graph: Task 5 → {3, 4, 6, 8}; Task 7 standalone. Critical path:
Task 5 → any of {3, 4, 6} (1.5 days).

## Forward plan

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
  branch-scoped consumption rule (naming the existing consumer — the pending-sign-off
  checklist regeneration — whose base..head scan already implements it), and the
  merge-strategy matrix; a `--marker` mode in `scripts/check-commit-msgs.sh` that takes the
  check **context**: on a commit **subject** (`--stdin` emit-time path) it requires canonical
  end-of-subject placement (pre-prefix and mid-subject fail); on a **PR title** it rejects
  any marker; skills that write marked commits self-lint the subject via the `--marker` mode
  before committing; the CI commit-range invocation unchanged.
- **Done when:** `--marker` fixtures cover the four placements plus the PR-title case;
  the CI workflow and range-lint invocation are diff-identical apart from any PR-title
  `--marker` addition; emitting skills' instructions name the self-lint step;
  `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-3 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-10

### Task 5 — Reference-integrity lint

- **Deliverables:** `scripts/check-doc-links.sh` rule: relative links leaving `doctrine/`
  other than to `../config/` or `../scripts/` are errors (sibling doctrine links, in-page
  anchors, and the co-located `../config/` + `../scripts/` siblings unaffected); the
  guard-catalog `../skills/` delivered-dead link fixed to conform (it is the sole real
  violation — the four `../scripts/` links in `decision-domains.md` and `guard-catalog.md`
  are permitted siblings and stay as-is).
- **Done when:** fixtures show a doctrine→`../skills/` link failing and sibling-doctrine
  plus `../config/` and `../scripts/` links passing; repo-wide `check:links` is green (the
  guard-catalog `../skills/` fix plus the four permitted `../scripts/` links);
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-4 · REQ-D1.1, REQ-D1.3, REQ-D1.4
- **Estimated effort:** half day

### Task 6 — `[[name]]` neutralization and fleet-citation reconciliation

- **Deliverables:** a `/spec-draft` completion-step rule neutralizing `[[name]]` links
  into prose plus a `## Sources` pointer (the sanctioned observations-log citation form);
  a **standing mechanical guard** — a `check:*` under `mise run check` (in
  `check-doc-links.sh` or a sibling) that flags any `[[name]]` token in a committed spec
  file, so a future writer skipping neutralization fails CI rather than silently
  reintroducing the violation (REQ-D1.1); the orchestration-fleet bundle's `[[…]]` citations
  reconciled via the expression-only amendment ritual (dated changelog entry, re-anchor).
  **Coordination:** the fleet bundle
  is `Ready` and may derive `Active`; land the fleet amendment's re-anchor as its own
  expression-only entry (the sanctioned lane) and sequence it so a concurrent fleet
  execution does not observe an anchor mismatch — check the fleet spec's In-progress state
  before amending, and if fleet execution is in flight, coordinate the re-anchor with it
  rather than racing it.
- **Done when:** the skill step exists; the standing `[[name]]` guard fails on a fixture
  spec file carrying a `[[foo]]` token and passes on a clean bundle, and runs under
  `mise run check`; a repo-wide search finds no `[[name]]` token in the four spec files
  (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) of any bundle — already-signed
  kickoff-brief bodies are append-only and out of this sweep's scope (REQ-D1.2's
  writer-neutralization keeps new briefs clean going forward); the fleet bundle's
  `requirements.md` + `design.md` `[[…]]` citations are neutralized via the expression-only
  amendment ritual, its changelog records the amendment, and its brief anchor matches
  `scripts/spec-anchor.sh` output; `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-4 · REQ-D1.1, REQ-D1.2, REQ-D1.4
- **Estimated effort:** 1 day
- **Deferral note:** the REQ-D1.4 orchestration-fleet `[[…]]` reconciliation sub-deliverable
  is deferred (never-reopen-Done): the fleet bundle went `Done` (#123) after this spec was
  signed, and a `Done` bundle's contract is frozen — changing it requires a Done→Draft reopen
  plus a scoped `/spec-kickoff` (`doctrine/spec-format.md`), not the expression-only amendment
  lane this task assumed when the fleet was `Ready`. The two links (`requirements.md:569`,
  `design.md:542`) are owed that future reopen; deferral recorded in the observations log. The
  standing `check:memory-links` guard skips terminal bundles, so it re-engages automatically
  the moment the fleet reopens to Draft. The skill rule, the guard, and the output-hygiene
  self-re-anchor all land in this PR.
- **Last activity:** 2026-07-10

### Task 7 — Organic completion-annotation stamping

- **Deliverables:** the level-triggered reconcile stamps
  `Completed · PR #<n> merged <YYYY-MM-DD>` in the same write that places a
  completion-evidenced task in `## Completed`, reusing the derivation's existing
  merged-PR evidence batch; honest no-remote degradation (date-only or no stamp);
  the stale `tasks-pr-sync.sh` implementation comment attributing annotation authoring to
  `/execute-task` corrected to reflect the reconcile-owned completion stamp (no edit to any
  `orchestration-concurrency` spec file — the change is additive to its contract, D-5).
- **Done when:** a fixture with merged-PR evidence yields the canonical string on the
  moved block; a no-remote fixture shows the degraded behavior and no invented PR
  number; non-completion annotations remain byte-for-byte; the five task-definition fields
  are untouched (the content anchor is unchanged, confirming no supersession); the
  `tasks-pr-sync.sh` comment reflects the new owner; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-5 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-09

### Task 8 — Derived-content authoring guidance

- **Deliverables:** meta-spec (`doctrine/spec-format.md`) guidance edits: hand-drawn
  dependency graphs dropped from the `tasks.md` intro-prose description in favor of
  `Dependencies:` lines plus the on-demand graph view; kickoff-brief guidance gains the
  cite-don't-copy convention for derived figures; the completion-annotation vocabulary
  promoted from illustrative to **normative** — `Completed · PR #<n> merged <YYYY-MM-DD>` is
  the canonical completion annotation and `Completed · merged <YYYY-MM-DD>` its only degraded
  form (giving REQ-E1.2's "canonical format" an actual doctrine home).
- **Done when:** the meta-spec no longer suggests a drawn graph, names the cite-don't-copy
  convention, and states the normative completion-annotation format + its one degraded form;
  the meta-spec versioning note records the guidance change; `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-5 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4
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

- Conflict-free observations recording — carved out to `specs/observation-recording`
  (2026-07-08); Tasks 1–2 below are superseded with it and preserved as frozen records
  (stable IDs, definition fields intact — bootstrap D-20), never dispatched.
- Cross-repo / multi-target observation routing — the deferred accumulator redesign
  (see requirements Out of scope).
- Input-side parser consolidation (spec-parse and scope-grammar duplication entries).
- Retroactive edits to already-merged PR bodies.
- The escaper/sanitizer consolidation — extracted to the standalone
  `chore/esc-consolidation` (2026-07-02).

### Task 1 — Fragment queue and consolidation primitive

- **Deliverables:** `specs/_observations/queue/` convention (fragment filename grammar
  `<YYYY-MM-DD>-<taskid>-<run-nonce>.md`: `<taskid>` from the run's task/branch id,
  `<run-nonce>` a run-unique token chosen once at run start — a stable run/dispatch id where
  one exists, else a short `^[a-z0-9]+$` random token — so two runs on the same task+date
  cannot collide; one file per run, all its observations appended to it; both components
  charset-validated before path interpolation and the derived path containment-checked, with
  a clean refusal on hostile/malformed input, per REQ-B1.5); a single-writer, idempotent
  consolidation routine (append the fragments' entries to `opportunities.md` in consolidation
  order **and** delete the consumed fragments as **one atomic commit**; idempotent — append
  only entries not already present, delete only fragments still present; on any
  `opportunities.md` conflict, regenerate from current state, never ours/theirs/union),
  guarded by a dedicated **global `_observations` advisory lock** (distinct from the per-spec
  lock — a performance guard against concurrent `--bookkeeping` retries, not the correctness
  mechanism); branch-/slug-derived names printable-sanitized before any echo (REQ-B1.5);
  accumulator-taxonomy doctrine amendment naming the queue as a class-3 surface (durable
  home, canonical reader `/spec-draft`, drain ritual).
- **Done when:** two runs with distinct identities on the same date produce **different**
  filenames (asserted directly), and consolidation produces a conflict-free append-ordered
  log with the fragments deleted; a concurrent-consolidation test proves idempotency (no
  duplicate entry) and regenerate-on-conflict (no union merge); a test proves existing log
  entries survive byte-for-byte apart from appends (verbatim, no rewrap); the atomic-commit
  case proves an interrupted run persists neither the append nor the delete; a traversal /
  metacharacter fragment name is a clean refusal writing no out-of-tree file, and an echoed
  name is printable-sanitized; the doctrine names the queue surface; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.5
- **Estimated effort:** 3 days
- **Status:** superseded — moved to `specs/observation-recording` (delta re-walkthrough
  2026-07-08); never dispatched.

### Task 2 — Consumer wiring for the queue

- **Deliverables:** `/orchestrate --bookkeeping` is the **sole consolidation writer** — it
  invokes Task 1's routine on the default branch; `/spec-draft` **mines** the queue plus the
  log (read-only) and never consolidates (it runs in a feature-branch worktree, where a
  consolidation write would ride the branch PR and collide at merge — D-1); the drain pass's
  observation surface counts queue entries in the unmined count and oldest-age figures.
- **Done when:** a drain-report fixture with queue entries shows them in the unmined
  surface; `--bookkeeping`'s instructions name it as the consolidation writer and
  `/spec-draft`'s name the queue as a read-only mining input (no consolidation write);
  `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-B1.2, REQ-B1.4
- **Estimated effort:** 1 day
- **Status:** superseded — moved to `specs/observation-recording` (delta re-walkthrough
  2026-07-08); never dispatched.
