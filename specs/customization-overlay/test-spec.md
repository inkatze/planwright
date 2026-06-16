# Customization & Overlay Mechanism — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

Coverage mix: predominantly `[test]` — the resolvers are portable shell, unit
-testable in `tests/` under `mise run check` / CI. `[design-level]` covers the
boundary doctrine doc (existence plus coverage is the verification). A few
`[manual]` / `[Gherkin]` entries cover skill behavior and data-hygiene that do
not unit-test cleanly. Every REQ is pinned to at least one path below.

## REQ-A — Overlay model, layers & precedence

### REQ-A1.1 — Four-layer precedence order [test]

Fixture sets the same key in all four layers; assert the highest-precedence
layer wins and that the resolved order is core < adopter < repo-tracked <
machine-local. Exercised through `config-get` (config kind) with the layer
roots from `resolve-overlay-root.sh`.

### REQ-A1.2 — Uniform precedence across kinds [test + design-level]

Each kind's resolver test (`config-get`, `resolve-rule-doc`, catalog
discovery) exercises the same four-layer order. Design-level: the precedence is
one documented rule (D-1) the three resolvers share, not three independent
orderings.

### REQ-A1.3 — No-fork invariant [test + design-level]

Overlay-resolution tests place adopter/repo/machine-local overlays and observe
their effect without editing any core doctrine doc or skill (the fixtures never
touch `config/defaults.yml` or core `doctrine/`). Design-level: adding an
overlay is a file placement, not a core edit.

### REQ-A1.4 — Absent layer degrades [test]

Resolver tests with one or more layers absent return the next-lower layer's
value (or empty for the lowest) with a zero exit and no error.

### REQ-A1.5 — Adopter overlay per namespace, both modes [test]

`resolve-overlay-root.sh` tests: plugin mode with two distinct
`CLAUDE_PLUGIN_DATA` ids resolves to two distinct adopter roots (no collision);
writer mode resolves a namespace directory; the explicit
`$PLANWRIGHT_ADOPTER_OVERLAY` override arm wins when set.

### REQ-A1.6 — Tracked team vs gitignored machine-local [test + design-level]

Test: `<repo>/.claude/planwright.local.yml` is read as the machine-local layer
(highest precedence) and `<repo>/.claude/planwright.yml` as the repo-tracked
layer. Design-level: `.gitignore` covers `planwright.local.yml` but not the
tracked `planwright.yml`.

## REQ-B — Resolution & merge semantics

### REQ-B1.1 — Config last-layer-wins across four layers [test]

`config-get` fixtures across all four layers assert per-key last-layer-wins,
extending the existing two-layer behavior without regressing it.

### REQ-B1.2 — Doctrine whole-doc shadow [test]

`resolve-rule-doc` returns the whole highest-precedence doc of a given name; a
test asserts the returned path is the overlay doc in full and that no fragment
merge occurs (a core-only section absent from the overlay doc does not appear).

### REQ-B1.3 — Catalog append/union and supersede-by-id [test]

Catalog discovery unions core seed entries with overlay entries; a test with an
overlay supersede-by-id entry asserts it replaces its target while other core
entries survive.

### REQ-B1.4 — Stable per-kind resolution path [design-level]

Skills call the three resolvers (`config-get`, `resolve-rule-doc`, catalog
discovery); design-level audit confirms no skill re-implements layer merging.

### REQ-B1.5 — Deterministic, order-independent resolution [test]

Resolution is invariant under shuffled filesystem enumeration order: a test
that randomizes discovery order asserts the same resolved result for config and
catalog kinds. Doctrine resolution is excluded by design: it is single-doc
first-hit by fixed layer order (no within-layer enumeration choice and no
merge), so it is inherently order-independent.

### REQ-B1.6 — Provenance `--explain` [test]

Each resolver's `--explain` mode names the winning layer: `config-get --explain`
per key, `resolve-rule-doc --explain` for the resolved doc, catalog discovery
`--explain` per merged entry.

### REQ-B1.7 — Protected-doc shadow warns [test]

`resolve-rule-doc` with an overlay shadowing a protected core doc (for example
`security-posture`) returns the overlay doc AND emits a stderr warning naming
the doc and the risk; shadowing a non-protected doc resolves with no warning.
Asserts warn-but-allow: the resolved path is the overlay's, exit is zero, and
the warning fires only for the protected set.

## REQ-C — Capability-vs-style boundary doctrine

### REQ-C1.1 — Boundary rule with decision-time criteria [design-level]

`customization-boundary.md` exists and states criteria an author applies at
decision time to classify a preference as general capability vs personal style.

### REQ-C1.2 — Default tilt to overlay [design-level]

The boundary doc states the default tilt toward overlay when in doubt and the
drain-loop graduation path to core.

### REQ-C1.3 — Worked examples [design-level]

The boundary doc carries the review-gauntlet (overlay) and dispatch-isolation
(core + knob) worked examples; the `review_sequence` knob is the runnable
instance cross-referenced from the doc.

## REQ-D — Skill integration & consumption

### REQ-D1.1 — Skills read merged catalog path [test + design-level]

The decision-domains and guard-catalog consumers read the merged catalog
through the shared discovery path (test). Design-level audit: no consumer
hardcodes a single-layer read.

### REQ-D1.2 — Doctrine overlays consumable, no new per-skill wiring [design-level]

Existing `resolve-rule-doc.sh` callers gain overlay resolution through the
resolver change alone; design-level confirms no per-skill wiring was added.

### REQ-D1.3 — `review_sequence` expressible and honored [test + Gherkin + manual]

Test: `review_sequence` resolves across all four layers via `config-get`
(the resolution half is fully automated). The behavioral half — that
`/execute-task`'s convergence phase *honors* the ordering — is skill-driven
and not unit-testable: it is verified design-level (the convergence-phase
instructions read the knob and iterate the list in order) plus a manual
exercise once. Gherkin: given an overlay sets `review_sequence` to an
ordering, when
`/execute-task` reaches its convergence phase, then it runs the named review
skills in that order; and given no overlay, the default reproduces today's
convergence behavior; and given an overlay names an unknown or non-nestable
review skill, then the value is treated as malformed under the REQ-E1.4
by-layer policy (degrade+warn for adopter/machine-local, hard-fail for
repo-tracked).

## REQ-E — Data hygiene, validation, security & documentation

### REQ-E1.1 — No secrets in overlays [design-level + manual]

The data-hygiene rule for overlays is documented; the gitleaks secret-scan
guard covers committed (repo-tracked) overlays. Manual: reviewer confirms no
overlay fixture or doc carries secret-shaped content.

### REQ-E1.2 — Identifier charset validation [test]

Hostile overlay identifiers (out-of-charset names, leading dash, traversal
segments) are rejected before interpolation, with a clear message and nonzero
exit.

### REQ-E1.3 — Options reference and adopter docs [test + design-level]

Test: `check-options-reference.sh` passes for every new overlayable option.
Design-level: the adopter overlay documentation (mechanism plus per-layer
locations) exists and the bootstrap Task 19 hand-off is recorded.

### REQ-E1.4 — Malformed overlay by layer [test + Gherkin]

Test: a malformed adopter or machine-local overlay degrades to the next lower
layer with a stderr warning and zero exit; a malformed repo-tracked overlay
exits nonzero. Gherkin: the three scenarios (adopter malformed → degrade;
machine-local malformed → degrade; repo-tracked malformed → hard-fail) as
state/trigger/outcome.

### REQ-E1.5 — Path-traversal confinement [test]

A doctrine-overlay override path escaping the overlay root — `../` traversal,
an absolute path, or a symlink that escapes after canonicalization — is
rejected with a clear message and never read.
