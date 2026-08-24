# Model Allocation — Tasks

**Status:** Draft
**Last reviewed:** 2026-08-24
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Generalized selection resolver and the `allocation_*` knob family

- **Deliverables:** The fleet selection table generalized into a surface-agnostic
  resolver callable from every launch point; the `allocation_*` knob family in
  `config/defaults.yml` with `fleet_*` fallback resolution; options-reference rows for
  every new knob; deprecated-alias documentation for the `fleet_*` family; tests
  covering fallback precedence, enum validation, and default preservation.
- **Done when:** the resolver returns today's exact model/effort/command for every
  existing task type with an empty config; a set `allocation_*` knob wins over its
  `fleet_*` counterpart and an unset one falls back; malformed values follow the
  by-layer policy per the existing resolver tests; `check-options-reference` passes.
- **Dependencies:** none
- **Citations:** D-5 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-E1.1, REQ-E1.2
- **Estimated effort:** 2 days

### Task 2 — Adaptation engine: event-triggered tier resolution with clamps and audit

- **Deliverables:** Tier derivation from audit records (memoryless, per-unit);
  escalation on the deterministic event set (step failure/retry, flailing,
  non-convergence) one tier per event under the configurable per-unit cap; the fixed
  clamp order (rung, caps, downshift) applied to every proposal; signal-unavailable
  escalation denial; structured audit rows for every resolution and adjustment,
  including clamped and inheritance outcomes; tests for derivation convergence, clamp
  order, cap bounds, and denial-folds-into-crash-loop behavior.
- **Done when:** a fixture audit trail plus a trigger event yields the same resolved
  tier across repeated invocations; each clamp is individually shown to bound a
  proposal in tests; an unavailable-signal fixture denies escalation; fleet dispatch
  resolves through the adaptation-aware path with unchanged defaults-only behavior.
- **Dependencies:** 1
- **Citations:** D-2, D-6, D-8, D-9 · REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5,
  REQ-D1.1, REQ-D1.2, REQ-F1.1
- **Estimated effort:** 3 days

### Task 3 — Worker petition: grammar, screening, and policy consumption

- **Deliverables:** The petition artifact grammar (direction, one-line reason) and its
  pinned worktree path; parser with strict validation and untrusted-input screening
  (sanitized echo, no interpolation); policy consumption at launch boundaries as one
  trigger input, hint-only under all clamps; invalid-petition ignore-with-audit; worker
  instruction prose for when to petition; tests including hostile-input fixtures.
- **Done when:** a valid escalate/de-escalate petition adjusts the next launch's tier
  within bounds; every hostile fixture (oversize, out-of-grammar, control bytes, path
  tricks) is ignored with an audit row and clean output; a petition never exceeds a
  clamp in tests.
- **Dependencies:** 2
- **Citations:** D-7, D-8 · REQ-C1.3, REQ-C1.6
- **Estimated effort:** 2 days

### Task 4 — Escalation feedback observation

- **Deliverables:** Threshold evaluation (unit ended above starting tier, or
  escalation count at the configured threshold) wired to the shared observation
  recording helper; the observation text shape naming task, spec, starting and final
  tiers; tests for threshold firing and non-firing.
- **Done when:** a fixture unit crossing the threshold produces a grammar-valid
  observation fragment via the shared helper, and a unit below it produces none.
- **Dependencies:** 2
- **Citations:** D-11 · REQ-F1.2
- **Estimated effort:** half day

### Task 5 — Per-step selection keys

- **Deliverables:** Step-type tier keys (implementation step, each review-sequence
  step class) resolvable per launch under per-step isolation; step-type de-escalation
  per the adaptation policy; defaults reproducing today's behavior (all steps at the
  unit's tier); options-reference rows; tests.
- **Done when:** with defaults only, every step of a unit resolves to the same tier as
  today; a configured cheaper review-step tier takes effect only at that step's launch
  and is restored after; the sequencing dependency on Task 2 is honored in dispatch
  order.
- **Dependencies:** 1, 2
- **Citations:** D-8, D-12 · REQ-C1.3, REQ-E1.1
- **Estimated effort:** 1 day

### Task 6 — Launch-point wiring beyond the fleet

- **Deliverables:** Single-spec `/orchestrate` dispatch, `/execute-task` per-step
  session launches, and `/offload` dispatch resolving through the shared resolver;
  application per the backend's advertised capability with inheritance-with-audit for
  backends that cannot set model/effort; the in-session rung's inheritance documented
  as its pinned degradation; skill-prose updates; tests where the surface is
  scriptable.
- **Done when:** each named launch point demonstrably consults the resolver (test or
  recorded invocation path per surface); a capability-lacking backend fixture yields
  an inheritance audit row, never a silent ambient launch; defaults-only behavior is
  unchanged at every surface.
- **Dependencies:** 1, 2
- **Citations:** D-4, D-10, D-12 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-A1.2
- **Estimated effort:** 2 days

### Task 7 — Operator documentation

- **Deliverables:** Operator-facing docs covering the allocation policy: the knob
  family and fallback, the adaptation model and its triggers, the petition contract,
  the audit trail and how to read "why did this unit run on that model", and the
  feedback loop; cross-links from the existing fleet docs.
- **Done when:** the docs answer, without reading source: how to set a starting tier,
  how to cap escalation, how a clamp decision is audited, and how the `fleet_*` alias
  relates to `allocation_*`; doc-link checks pass.
- **Dependencies:** 3, 4, 5, 6
- **Citations:** D-5, D-11 · REQ-E1.2, REQ-F1.1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Authored per-task complexity tier.** An optional authored field (mechanical |
  standard | hard) in task blocks as the starting-tier signal, deliberately kept out of
  this bundle ahead of evidence. Confidence: medium.
  **Gate:** GATE(when: recurring REQ-F1.2 escalation observations show starting tiers
  chronically wrong for a task class the config prior cannot express).
  Citations: D-3, REQ-F1.2.

## Out of scope

- Token-usage and context-size reduction — a separate future spec seeded by the
  `ctxeng-*` observation fragments (requirements `### Out of scope`).
- Changes to the usage gate, restriction ladder, caps, spend accounting, or
  credit-continuation policy (requirements `### Out of scope`; D-1).
