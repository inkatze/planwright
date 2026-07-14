# Invariant Tasks — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-14
**Format-version:** 1

The canonical orchestration state record for `specs/invariant-tasks`.
Dependency edges are the sole source of truth for the task graph
(`scripts/spec-graph.sh` renders the view on demand). Guard-first note: the
validator task (Task 2) carries explicit edges from every task that produces
v2 content, so it cannot dispatch after the work it protects.

## Forward plan

### Task 1 — Meta-spec format-version 2

- **Deliverables:** The format-version 2 definition in
  `doctrine/spec-format.md`: the v2 `tasks.md` shape (single `## Tasks`
  section plus Awaiting input / Deferred / Out of scope), Awaiting-input
  reference bullets, the restricted stored-status vocabulary with the
  reopen cycle (Ready→Draft), the static `Execution:` pointer line, and
  derivation as the read surface — recorded via the meta-spec's own
  versioning ritual, v1 rules retained for v1 bundles.
- **Done when:** `doctrine/spec-format.md` defines format-version 2
  normatively (a reader can author a compliant v2 bundle from it alone);
  v1 text is unchanged in meaning; the meta-spec's versioning section
  records the bump; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-4, D-5 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-E1.1
- **Estimated effort:** 1 day

### Task 2 — Validator v2 rules

- **Deliverables:** `scripts/spec-validate.sh` enforcing the v2 invariants
  (no state sections, no state annotation bullets, stored header restricted
  to Draft/Ready/Retired/Superseded, pointer line present) as errors on
  non-Draft v2 bundles and warnings on Draft, with v1 rules unchanged for
  v1 bundles; fixture tests for both versions.
- **Done when:** a seeded v2 fixture with a state section, a state
  annotation, or an Active/Done header fails validation; a compliant v2
  fixture and every existing v1 bundle pass; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-7 · REQ-C1.5, REQ-D1.1
- **Estimated effort:** 1 day

### Task 3 — Derived status render surface

- **Deliverables:** The derivation engine (`scripts/orchestrate-state.sh`)
  surfaced as the canonical human status render: a command (wired as a mise
  task) that prints per-task execution status and the bundle's effective
  status (Active/Done) for a named spec, honoring Awaiting-input bullet
  authority (REQ-B1.4) and degrading with no remote configured.
- **Done when:** the render reports correct per-task and bundle status on
  fixtures covering merged-PR, open-PR, branch-only, marker-only,
  parked-task, and no-remote cases; an Awaiting-input bullet overrides git
  evidence for its task; nothing is written to any committed file;
  `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-6, D-3 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4
- **Estimated effort:** 1 day

### Task 4 — Writer retirement, version-keyed

- **Deliverables:** `scripts/tasks-pr-sync.sh` and its hook no-oping on v2
  bundles (no placement, annotation, or derived-header writes; v1 behavior
  unchanged); `scripts/check-ledger.sh` reduced to structural checks
  (canonical heading form, duplicate task ids) for v2 bundles; the
  churn-free property test: a full state transition exercised against a v2
  fixture produces zero diff under the spec directory and an unchanged
  content anchor.
- **Done when:** the churn-free fixture test passes; v1 fixture behavior
  of both scripts is unchanged; the hook fires harmlessly on v2 bundles;
  `mise run check` passes.
- **Dependencies:** 1, 2
- **Citations:** D-7, D-9 · REQ-C1.1, REQ-C1.4, REQ-C1.6, REQ-A1.2
- **Estimated effort:** 2 days

### Task 5 — Selector and gate re-sourcing

- **Deliverables:** `scripts/orchestrate-select.sh` computing v2 candidacy
  without committed placement (dependencies-met and
  not-completed/in-progress via the derivation engine; parked-ness via
  Awaiting-input bullets and the Deferred / Out of scope sections);
  `scripts/drain-gates.sh` resolving task-completion atoms through the
  derivation engine.
- **Done when:** selection on a v2 fixture picks the same candidates the
  v1 section model would have picked in equivalent states, including
  parked-task exclusion; drain-gate completion atoms resolve correctly on
  a v2 fixture with no `## Completed` section; v1 behavior unchanged;
  `mise run check` passes.
- **Dependencies:** 1, 3
- **Citations:** D-8 · REQ-C1.2, REQ-C1.3
- **Estimated effort:** 1 day

### Task 6 — Migration script and live-bundle migration

- **Deliverables:** A one-shot v1→v2 migration script (id-sorted section
  collapse, annotation strip, Awaiting-input block→bullet conversion,
  header restriction, pointer line, format bump) preserving task
  definition lines byte-for-byte, with fixture tests asserting the
  canonical `tasks.md` extraction digest is unchanged; planwright's own
  live (Ready/Active) bundles migrated, each with its expression-only
  re-anchor; orchestration-concurrency's Deferred "Maximal variant" entry
  annotated closed, citing this bundle.
- **Done when:** the migration fixture test proves an unchanged extraction
  digest and a valid v2 result; every live bundle in this repo validates
  as v2; Done/terminal bundles are byte-identical to before; the
  orchestration-concurrency Deferred entry carries the closure annotation;
  `mise run check` passes.
- **Dependencies:** 1, 2, 4, 5
- **Citations:** D-10 · REQ-D1.2, REQ-D1.3, REQ-E1.4
- **Estimated effort:** 1 day

### Task 7 — Skill reconciliation

- **Deliverables:** Every state-layer-touching skill reconciled for v2:
  `/spec-draft` authors v2 bundles (v2 section skeleton, pointer line, no
  state sections); `/execute-task` drops the `Last activity` write and
  keeps committed Awaiting-input writes in bullet form; `/orchestrate`,
  `/resume`, and `/drain` read execution status through the render;
  `/spec-kickoff`'s Draft→Ready flip documented as the header's resting
  state.
- **Done when:** each named skill's instructions reference the render (not
  committed sections) for v2 execution status; `/spec-draft`'s emitted
  skeleton validates as v2; no skill instructs writing a state section,
  state annotation, or derived header value to a v2 bundle;
  `mise run check` (including the instruction-budget guards) passes.
- **Dependencies:** 1, 2, 3
- **Citations:** D-6, D-7, D-3 · REQ-E1.2
- **Estimated effort:** 2 days

### Task 8 — Docs, config, and supersessions

- **Deliverables:** `docs/options-reference.md` marking
  `commit_on_state_move` v1-only; adopter-facing docs describing the v2
  model and the render; the output-hygiene completion-annotation
  supersession recorded per the ritual (D-11 cited from a dated changelog
  entry; output-hygiene's text not retroactively edited).
- **Done when:** the options reference row carries the v1-only note; docs
  describe reading status via the render; the supersession record exists
  and `check:specs` passes; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-11, D-7 · REQ-E1.3, REQ-C1.7
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

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
