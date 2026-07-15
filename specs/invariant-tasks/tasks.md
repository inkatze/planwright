# Invariant Tasks — Tasks

**Status:** Active
**Last reviewed:** 2026-07-14
**Format-version:** 1

The canonical orchestration state record for `specs/invariant-tasks`.
Dependency edges are the sole source of truth for the task graph
(`scripts/spec-graph.sh` renders the view on demand). Guard-first note:
every task that produces committed v2 spec content carries an explicit
edge to the validator task (Task 2), so none of them can dispatch before
the guard that protects their output exists.

## Forward plan

### Task 2 — Validator v2 rules

- **Deliverables:** `scripts/spec-validate.sh` enforcing the v2 invariants
  (no placement sections, no state annotation bullets, stored header
  restricted to Draft/Ready/Retired/Superseded, pointer line present in
  its fixed vocabulary, reference-bullet integrity: existing task ids, no
  duplicates) as errors on non-Draft v2 bundles and warnings on Draft,
  failing closed on a missing/unparseable `Format-version:`, with v1 rules
  unchanged for v1 bundles and echoed values on the new v2 error paths
  routed through `sanitize_printable`; fixture tests for both versions.
- **Done when:** each banned placement heading (Forward plan, In progress,
  Completed) and each banned annotation token (Status, Last activity,
  Dispatch) has its own failing v2 fixture; an Active/Done header, a
  missing or non-canonical pointer line, an unknown-id, duplicate, or
  grammar-violating reference bullet, and an unparseable `Format-version:`
  each fail; each v2-invariant violation warns rather than errors on a
  Draft fixture, except the unparseable-`Format-version:` case, which
  errors at every status (REQ-C1.8 — the rules to apply cannot be known
  without a parsed version); escape-byte fixtures confirm sanitized error
  output for bullet text and header values; a compliant v2 fixture and
  every existing v1 bundle pass; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-7, D-5, D-3 · REQ-C1.5, REQ-C1.8, REQ-C1.9, REQ-D1.1
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-15

### Task 3 — Derived status render surface

- **Deliverables:** The derivation engine (`scripts/orchestrate-state.sh`)
  surfaced as the canonical human status render: a command (wired as a
  mise task) that prints per-task execution status and the bundle's
  effective status (Active/Done) for a named spec. Includes porting the
  bundle-status determination from the sync writer's awk and re-sourcing
  it from reference bullets (D-6); stored-status gating and the zero-task
  rule (REQ-B1.6); bullet authority for all three sections (REQ-B1.4); a
  stale-bullet anomaly flag (a bullet on a task whose evidence derives
  completed); fail-closed transient-failure reporting distinct from the
  no-remote degradation (REQ-B1.5); and `sanitize_printable` on all echoed
  spec content (REQ-C1.9).
- **Done when:** the render reports correct per-task and bundle status on
  fixtures covering merged-PR, open-PR, branch-only, marker-only,
  commit-trailer, parked-task, and no-remote cases; a reference bullet
  overrides git evidence for its task and a bullet on a completed task is
  flagged as an anomaly; a stored-Draft/Retired/Superseded fixture renders
  its stored state with no execution claim; a zero-task fixture reports no
  tasks and never Done; an all-completed fixture with a live
  Awaiting-input bullet derives not-Done; a configured-but-failing remote
  reports the failure (distinct exit) instead of partial status; a fixture
  with a missing or unparseable `Format-version:` fails closed; embedded
  terminal-escape bytes in bullet text, branch names, and remote error
  text are sanitized in output; nothing is written to any committed file;
  `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-6, D-3, D-4, D-12 · REQ-B1.1, REQ-B1.2, REQ-B1.3,
  REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-C1.8, REQ-C1.9
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-15

### Task 4 — Writer version-keyed no-op and guard scope

- **Deliverables:** `scripts/tasks-pr-sync.sh` and its hook no-oping on v2
  bundles (no placement, annotation, or derived-header writes; fail-closed
  on an unparseable `Format-version:`; v1 behavior unchanged);
  `scripts/check-ledger.sh` reduced to structural checks for v2 bundles
  (canonical heading form, duplicate task ids, `## Tasks` recognized as a
  valid section, the orphan-block-outside-any-section check retained),
  with echoed values on new v2 paths sanitized (REQ-C1.9); a sweep
  verifying the read-only `tasks.md` parser family (`spec-model.sh` and
  its consumers) tolerates the v2 shape; the churn-free property test: a
  full state transition — dispatch, in-progress evidence, merged-PR
  evidence, plus a parking and an unparking write — exercised against a v2
  fixture produces zero diff under the spec directory for the derived
  transitions, and the parking/unparking commits leave the content anchor
  unchanged.
- **Done when:** the churn-free fixture test passes (including the
  parking-commit anchor-equality arm); on v2 fixtures, structural
  violations still fail check-ledger while placement/annotation coherence
  checks do not fire; the writer and guard fail closed on an unparseable
  `Format-version:` fixture (no write, error reported); v1 fixture
  behavior of both scripts is unchanged; the hook fires harmlessly on v2
  bundles; `mise run check` passes.
- **Dependencies:** 1, 2
- **Citations:** D-7, D-9 · REQ-C1.1, REQ-C1.4, REQ-C1.6, REQ-C1.8,
  REQ-C1.9, REQ-A1.2
- **Estimated effort:** 2 days

### Task 5 — Selector and gate re-sourcing

- **Deliverables:** `scripts/orchestrate-select.sh` computing v2 candidacy
  without committed placement (dependencies-met and
  not-completed/in-progress via the derivation engine; parked-ness via
  reference bullets in the human-payload sections, with bullet task ids
  validated against the grammar before use, REQ-C1.9);
  `scripts/drain-gates.sh` resolving task-completion atoms through the
  derivation engine.
- **Done when:** selection on a v2 fixture picks the same candidates the
  v1 section model would have picked in equivalent states, including
  parked-task exclusion; drain-gate completion atoms resolve correctly on
  a v2 fixture with no `## Completed` section; on a failing-remote fixture
  the selector dispatches nothing and completion atoms resolve as
  unresolved; both scripts fail closed on an unparseable `Format-version:`
  fixture; v1 behavior unchanged; `mise run check` passes.
- **Dependencies:** 1, 3
- **Citations:** D-8, D-3 · REQ-C1.2, REQ-C1.3, REQ-B1.5, REQ-C1.8,
  REQ-C1.9
- **Estimated effort:** 1 day

### Task 6 — Migration script and live-bundle migration

- **Deliverables:** A one-shot v1→v2 migration script (id-sorted section
  collapse, annotation strip, parked block→reference-bullet conversion for
  every human-payload section, header restriction, pointer line, format
  bump) preserving task definition lines byte-for-byte — idempotent
  (already-v2 input is a clean no-op), per-bundle atomic, re-runnable
  after a partial run, and refusing hostile identifiers or
  out-of-containment paths with a clean error — with fixture tests
  asserting the canonical `tasks.md` extraction digest is unchanged;
  planwright's own live (Draft/Ready/Active) bundles migrated, each signed
  bundle with its expression-only re-anchor and the dated changelog line
  it cites (a Draft has neither);
  orchestration-concurrency's Deferred "Maximal variant" entry annotated
  closed, citing this bundle.
- **Done when:** the migration fixture test proves an unchanged extraction
  digest and a valid v2 result, including a seeded parked block under
  Deferred/Out of scope converting to a reference bullet; a second run on
  the migrated fixture is a byte-level no-op; a hostile-input fixture is
  refused cleanly; a bundle with an unparseable `Format-version:` is
  refused (fail closed); every live bundle in this repo validates as v2;
  Done/terminal bundles are byte-identical to before; the
  orchestration-concurrency Deferred entry carries the closure annotation
  (mechanically present-checked in the fixture suite);
  `mise run check` passes.
- **Dependencies:** 1, 2, 4, 5
- **Citations:** D-10, D-3 · REQ-D1.2, REQ-D1.3, REQ-E1.4, REQ-C1.8,
  REQ-C1.9
- **Estimated effort:** 1 day

### Task 7 — Skill reconciliation

- **Deliverables:** Every state-layer-touching skill reconciled for v2:
  `/spec-draft` authors v2 bundles (v2 section skeleton, pointer line, no
  placement sections); `/execute-task` drops the `Last activity` write and
  keeps committed Awaiting-input writes in bullet form; `/resume` and
  human-facing status summaries read the render, while `/orchestrate`'s
  selection and `/drain`'s gate evaluation read the derivation engine via
  their scripts (D-6, D-8); `/orchestrate`'s dead-worker orphan reconcile
  parks via an Awaiting-input bullet; `/spec-kickoff`'s Draft→Ready flip
  documented as the header's resting state and its delta/amendment mode
  selection reading derived status.
- **Done when:** each named skill's instructions reference the correct
  read surface for v2 execution status (the render for human-facing
  status, the derivation engine for machine logic — never committed
  sections); every reconciliation is version-keyed (skill instructions
  branch on the declared `Format-version:`; v1-bundle behavior is
  unchanged); `/spec-draft`'s emitted skeleton validates as v2; no skill
  instructs writing a placement section, state annotation, or derived
  header value to a v2 bundle; `mise run check` (including the
  instruction-budget guards) passes.
- **Dependencies:** 1, 2, 3
- **Citations:** D-6, D-7, D-3, D-8 · REQ-E1.2
- **Estimated effort:** 2 days
- **Last activity:** 2026-07-15

### Task 8 — Docs, config, and supersessions

- **Deliverables:** `docs/options-reference.md` marking
  `commit_on_state_move` v1-only; the adopter-facing doc surfaces that
  describe the committed state layer reconciled for v2 — specifically
  `docs/orchestration-state.md` (the state-model writeup),
  `docs/conventions.md` (the tasks-pr-sync hook contract),
  `doctrine/gate-wiring.md` (the completion-annotation stamp entry gains
  its v2 scoping pointer), and the `README.md` / `docs/getting-started.md`
  / `docs/fleet.md` pointers to them; the output-hygiene
  completion-annotation supersession recorded per the ritual (D-11 cited
  from a dated changelog entry, naming both normative homes;
  output-hygiene's text not retroactively edited).
- **Done when:** the options reference row carries the v1-only note; each
  named doc surface describes the v2 model (or carries a version-scoped
  caveat) and reading status via the render; the supersession record
  exists and `check:specs` passes; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-11, D-7 · REQ-E1.3, REQ-C1.7
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

### Task 1 — Meta-spec format-version 2

- **Deliverables:** The format-version 2 definition in
  `doctrine/spec-format.md`: the v2 `tasks.md` shape (single `## Tasks`
  section plus Awaiting input / Deferred / Out of scope), reference-bullet
  forms for all three human-payload sections (with the artifact
  data-hygiene note for bullet free text), the restricted stored-status
  vocabulary with the reopen cycle (Ready→Draft), the static `Execution:`
  pointer line (fixed vocabulary), and derivation as the read surface —
  recorded via the meta-spec's own versioning ritual, v1 rules retained
  for v1 bundles; the 2026-07-10 normative completion-annotation entry
  scoped to v1; the stale `Dispatch`-annotation writer claim corrected.
- **Done when:** `doctrine/spec-format.md` defines format-version 2
  normatively (a reader can author a compliant v2 bundle from it alone);
  the v2 definition carries the bullet data-hygiene note (REQ-C1.9);
  v1 text is unchanged in meaning; the meta-spec's versioning section
  records the bump and the v1 scoping of the completion-annotation entry;
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-4, D-5, D-11 · REQ-A1.1, REQ-A1.2,
  REQ-A1.3, REQ-A1.4, REQ-E1.1, REQ-C1.9
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-15
- **Status:** Completed · PR #181 merged 2026-07-15

## Deferred

- **Wholesale retirement of the v1 state-sync machinery.** The version-keyed
  v1 arms (`tasks-pr-sync.sh` reconcile, ledger coherence checks, the
  status-lifecycle migration) stay functional while any live v1 bundle can
  exist. Retirement is a deletion pass, not a redesign. Confidence: high.
  **Gate:** GATE(when: planwright's own repo carries no non-terminal v1
  bundle and a released deprecation window for adopter v1 bundles has
  passed).
  Citations: D-7.

## Out of scope

- Moving the human-payload sections (Awaiting input, Deferred, Out of
  scope) out of the committed file — their content is human-authored and
  not derivable (D-2).
- Selection policy changes (which ready unit is chosen) — this bundle
  changes where state is read from, not how units are ranked.
- Rewriting Done or terminal bundles to v2 (D-10).
- Auto-merge at any tier — permanent carried invariant.
