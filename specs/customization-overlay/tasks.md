# Customization & Overlay Mechanism — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

Dependency view (derived; the `Dependencies:` lines are authoritative): T2 is
the foundational primitive the three resolvers share. T1 is independent. T3,
T4, T5 each depend on T2. T6 depends on T3. T7 depends on T3, T4, T5, T6.

## Forward plan

### Task 6 — `review_sequence` config knob

- **Deliverables:** The `review_sequence` config option (an ordered list of
  nestable review-skill names) with a default reproducing today's convergence
  behavior, documented in `docs/options-reference.md`, and `/execute-task`'s
  convergence phase rewired to read it through the four-layer config resolution
  and run the named review skills in order. Verification of the ordering
  scenario.
- **Done when:** `review_sequence` resolves through all four layers; the
  default leaves `/execute-task`'s behavior unchanged; an overlay-set ordering
  is honored in order by the convergence phase; an entry naming an unknown or
  non-nestable review skill is handled as a malformed value under the REQ-E1.4
  by-layer policy; `check-options-reference.sh` passes; the ordering scenario
  is verified.
- **Dependencies:** 3
- **Citations:** D-6 · REQ-C1.3, REQ-D1.3, REQ-E1.3, REQ-E1.4
- **Estimated effort:** 1 day

### Task 7 — Adopter docs & onboarding

- **Deliverables:** Adopter-facing documentation of the overlay mechanism: the
  four layers, each kind's per-layer locations, the merge rules, the
  malformed-by-layer policy, the `--explain` affordance, the two worked
  examples (dispatch-isolation and the `review_sequence` gauntlet), and an
  explicit warning that secrets in adopter and machine-local (uncommitted)
  overlays are NOT covered by the secret scanner (which scans committed files
  only) — the data-hygiene rule is the only guard there. Hand-off note for
  bootstrap Task 19 onboarding.
- **Done when:** the overlay mechanism and per-layer locations are documented
  for adopters; the worked examples appear; the uncommitted-overlay secret
  warning is present; the bootstrap Task 19 hand-off is recorded;
  `check-doc-links.sh` and the doc linters pass.
- **Dependencies:** 3, 4, 5, 6
- **Citations:** D-1, D-4, D-5, D-7, D-9 · REQ-B1.6, REQ-C1.3, REQ-E1.1,
  REQ-E1.3, REQ-E1.4
- **Estimated effort:** half day

## In progress

### Task 3 — Four-layer config resolution

- **Status:** implementing
- **Last activity:** 2026-06-17
- **Dispatch:** tmux backend; dispatched 2026-06-17; worker window `co-task-3` (branch `planwright/customization-overlay/task-3`, worktree `.claude/worktrees/customization-overlay-task-3`, branched off origin/main `6a26164`).
- **Deliverables:** `config-get.sh` extended to read the adopter and
  repo-tracked layers through the Task 2 primitive (four-layer
  last-layer-wins), the malformed-by-layer policy (degrade+warn for
  adopter/machine-local, hard-fail for repo-tracked), and a `--explain`
  provenance mode. Any new option documented in `docs/options-reference.md`.
  Tests under `tests/`.
- **Done when:** a key set in all four layers resolves to the highest-precedence
  value; absent layers degrade; a malformed adopter/machine-local file
  degrades with a stderr warning and the malformed repo-tracked file exits
  nonzero; `--explain` names the winning layer per key; `check-options-reference.sh`
  passes; tests pass under `mise run check`.
- **Dependencies:** 2
- **Citations:** D-4, D-5, D-7, D-9 · REQ-A1.2, REQ-B1.1, REQ-B1.4, REQ-B1.5,
  REQ-B1.6, REQ-E1.3, REQ-E1.4
- **Estimated effort:** 1 day

### Task 4 — Doctrine-overlay resolution

- **Status:** PR #39 draft
- **Last activity:** 2026-06-17
- **Dispatch:** tmux backend; dispatched 2026-06-17; worker window `co-task-4` (branch `planwright/customization-overlay/task-4`, worktree `.claude/worktrees/customization-overlay-task-4`, branched off origin/main `6a26164`).
- **Deliverables:** `resolve-rule-doc.sh` extended to insert the adopter,
  repo-tracked, and machine-local doctrine roots (`doctrine/` for adopter and
  repo-tracked, `doctrine.local/` for machine-local, per D-4) into its
  precedence chain (whole-doc shadow),
  with path-traversal confinement, the malformed-by-layer policy, the
  protected-doc warn-but-allow behavior (loud stderr warning when an overlay
  shadows a protected core governance/security doc), and a `--explain`
  provenance mode. Tests under `tests/`.
- **Done when:** the highest-precedence overlay doc of a name wins in full;
  no fragment merge occurs; a path escaping the overlay root (`../`, absolute,
  symlink-escape) is rejected with a clear message; malformed-by-layer matches
  D-7; shadowing a protected core doc resolves *and* emits the warning while a
  non-protected shadow is silent; `--explain` names the supplying layer; tests
  pass under `mise run check`.
- **Dependencies:** 2
- **Citations:** D-4, D-5, D-7, D-8, D-9, D-11 · REQ-A1.2, REQ-B1.2, REQ-B1.4,
  REQ-B1.6, REQ-B1.7, REQ-D1.2, REQ-E1.4, REQ-E1.5
- **Estimated effort:** 1 day

### Task 5 — Catalog-overlay resolution

- **Status:** implementing
- **Last activity:** 2026-06-17
- **Dispatch:** tmux backend; dispatched 2026-06-17; worker window `co-task-5` (branch `planwright/customization-overlay/task-5`, worktree `.claude/worktrees/customization-overlay-task-5`, branched off origin/main `6a26164`).
- **Deliverables:** A catalog discovery path that unions core seed entries
  with overlay entries (append/union, supersede-by-id) for the decision-domains
  catalog and the guard catalog, with a `--explain` provenance mode, the
  malformed-by-layer policy for catalog parsing (a catalog overlay not
  parseable into entries degrades+warns for adopter/machine-local and
  hard-fails for repo-tracked, per D-7/REQ-E1.4), and the
  consuming skills wired to read the merged catalog through it. This task
  **pins the supersede-by-id syntax** (overlay entry carries the target id plus
  a supersede marker) as the merge contract bootstrap Task 16 consumes. Tests
  under `tests/`.
- **Done when:** overlay entries append to the core seed; a supersede-by-id
  entry replaces its target; the supersede-by-id syntax is documented as the
  contract, including the behavior when a supersede-by-id entry names a
  non-existent target (pinned, not left implementation-defined); resolution is
  order-independent of filesystem enumeration; the
  decision-domains consumer reads the merged path with no single-layer
  hardcoding; the guard-catalog consumer is wired the same way *if* bootstrap
  Task 16's guard catalog exists at execution time (else that wiring defers per
  the risk-register row, and the merge mechanism plus decision-domains consumer
  still ship); a malformed (unparseable) adopter or machine-local catalog
  overlay degrades to the next lower layer with a stderr warning and a
  malformed repo-tracked catalog overlay exits nonzero (REQ-E1.4 by-layer
  policy); `--explain` names each entry's layer; tests pass under
  `mise run check`.
- **Dependencies:** 2
- **Citations:** D-2, D-4, D-5, D-7, D-9 · REQ-A1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5,
  REQ-B1.6, REQ-D1.1, REQ-E1.4
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Completed

### Task 1 — Capability-vs-style boundary doctrine

- **Status:** Completed — PR #28 merged 2026-06-17 (merge commit `480cf64`).
- **Deliverables:** A new doctrine doc `customization-boundary.md` defining the
  capability-vs-style rule, its decision-time criteria, the default tilt toward
  overlay, and the two worked examples (review-gauntlet ordering as style;
  dispatch-isolation default as core capability). Cite-wiring so `/spec-draft`'s
  design phase consults it.
- **Done when:** `customization-boundary.md` resolves via
  `resolve-rule-doc.sh`; it states the criteria, the default tilt, and both
  worked examples; `/spec-draft`'s design-phase instructions reference it;
  `check-doc-links.sh` and the doc linters pass.
- **Dependencies:** none
- **Citations:** D-10 · REQ-C1.1, REQ-C1.2, REQ-C1.3
- **Estimated effort:** half day

### Task 2 — Overlay-root resolution primitive

- **Status:** Completed — PR #29 merged 2026-06-17 (merge commit `ccb7b55`).
- **Deliverables:** `scripts/resolve-overlay-root.sh` resolving the four layer
  roots — core, adopter (via the `$PLANWRIGHT_ADOPTER_OVERLAY` →
  `$CLAUDE_PLUGIN_DATA/overlay/` → `<claude-dir>/planwright/<name>/overlay/`
  chain, where writer mode's `<name>` is the plugin manifest `name`),
  repo-tracked, and machine-local — with identifier/namespace validation and a
  shared canonicalize-then-contain path-confinement helper. In writer mode the
  manifest `name` is read from `<claude-dir>/planwright/plugin.json`, so
  `install.sh` copies that manifest into place (D-3). Unit tests under
  `tests/`.
- **Done when:** the script resolves each layer root in both delivery modes;
  distinct `CLAUDE_PLUGIN_DATA` ids resolve to distinct adopter roots; writer
  mode derives the adopter namespace from the manifest `name` (charset-validated);
  absent layers resolve to empty/next-lower without error; hostile identifiers
  and traversing/escaping paths are rejected with a clear message and nonzero
  exit; tests pass under `mise run check`.
- **Dependencies:** none
- **Citations:** D-1, D-3, D-4, D-8 · REQ-A1.1, REQ-A1.3, REQ-A1.4, REQ-A1.5,
  REQ-A1.6, REQ-E1.2, REQ-E1.5
- **Estimated effort:** 1 day

## Deferred

- **Doctrine fragment/section merge.** Whole-doc shadow (D-5) covers v1;
  splicing overlay sections into a core doc is drift-prone and deferred.
  Confidence: high. **Gate:** GATE(when: a concrete adopter need for
  partial-doc override is observed in the drain loop). Citations: D-5,
  REQ-B1.2.
- **Aggregate `overlay explain` tool.** Per-resolver `--explain` (D-9) covers
  v1; a single cross-kind provenance command can follow if demand appears.
  Confidence: medium. **Gate:** GATE(when: per-resolver provenance proves
  insufficient in practice). Citations: D-9, REQ-B1.6.

## Out of scope

- Changing any specific default (for example dispatch-isolation per-step): this
  spec ships the seam, not the overlays that ride it.
- The work fork's company-standard overlay content.
- Wholesale migration of personal memory / dotfiles `CLAUDE.md` into overlays.
- Secrets or credentials in overlays.
- Per-machine environment plumbing (`mise.local.toml`).
- Executable plugin / code-injection extensions (overlays stay declarative).
