# Model Allocation — Tasks

**Status:** Ready
**Last reviewed:** 2026-08-25
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Generalized selection resolver and the `allocation_*` knob family

- **Deliverables:** The fleet selection table generalized into a surface-agnostic
  resolver callable from every launch point, covering all three columns (model,
  effort, command — the command enum closed, carrying the review-sequence-disjointness
  invariant); the `allocation_*` knob family in `config/defaults.yml` with `fleet_*`
  fallback resolution and the explicit `inherit` sentinel for non-fleet surfaces; the
  pinned numeric-knob validation grammar; a captured golden-baseline fixture of the
  current shipped table; options-reference rows for every knob this task introduces;
  deprecated-fallback documentation for the `fleet_*` family; tests covering fallback
  precedence, enum validation (all three columns), numeric-grammar rejection, and
  default preservation against the golden baseline.
- **Done when:** the resolver returns the golden baseline's exact model/effort/command
  for every existing task type with an empty config; a set `allocation_*` knob wins
  over its `fleet_*` counterpart and an unset one falls back; the `inherit` sentinel
  resolves as inherit at non-fleet surfaces; malformed values follow the by-layer
  policy per the existing resolver tests and malformed numerics are rejected before
  arithmetic; `check-options-reference` passes.
- **Dependencies:** none
- **Citations:** D-5, D-13 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-E1.1,
  REQ-E1.2
- **Estimated effort:** 2 days

### Task 2 — Adaptation engine: per-unit ledger, event-triggered resolution, clamps

- **Deliverables:** The per-unit allocation ledger (pinned schema: seq, unit, step,
  attempt, event class, proposed/clamped/resolved tier, scope, inputs) with per-unit
  lock derive+append discipline, within-boundary memoization, and degraded mode
  (unhealthy ledger → last recorded or starting tier, adjustments suspended,
  surfaced); tier derivation memoryless from ledger plus config, including reversal
  derivation (most recent unreversed escalation step); escalation on the work-shaped
  event set with idempotency keys and per-event-class stacking at a boundary; the
  per-unit adjustment cap (net displacement, both directions); clamp composition per
  the upstream contracts' own semantics (withheld outcome at defer rungs,
  signal-dependent caps with nearest-surviving-model effort-preserved clamping,
  rung-conditional downshift, reserved-unit exemption pass-through, fail-closed
  unreadable inputs); signal-unavailable escalation denial with hold-no-claw-back; the
  sparse governance-event mirror into fleet-audit; ledger-size and derivation-latency
  surfacing through the stats path; the `allocation_adaptation` master knob and
  adjustment-cap knob with options-reference rows; tests for derivation convergence,
  reversal ordering, stacking counts (N classes → N steps, N rows), cap bounds and
  refunds, each clamp's conditional semantics and their composition, degraded-mode
  behavior, concurrent same-unit launches (serialized by the per-unit lock), a
  crash-replay idempotency fixture, a scale/latency fixture, and
  denial-folds-into-crash-loop behavior.
- **Done when:** a fixture ledger plus a trigger event yields the same resolved tier
  across repeated invocations; stacked distinct event classes climb one step each with
  one row each while same-incident classes collapse; each clamp is shown to bind per
  its own upstream conditionality and composition picks the cheapest survivor; an
  unavailable-signal fixture denies escalation and holds an already-escalated unit; an
  unhealthy-ledger fixture launches degraded with adjustments suspended and the
  degradation surfaced; fleet dispatch resolves through the adaptation-aware path with
  golden-baseline behavior when the master knob is off; `check-options-reference`
  passes for the introduced knobs.
- **Dependencies:** 1
- **Citations:** D-2, D-6, D-8, D-9, D-13 · REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5,
  REQ-D1.1, REQ-D1.2, REQ-F1.1, REQ-F1.3
- **Estimated effort:** 3 days

### Task 3 — Worker petition: grammar, screening, and policy consumption

- **Deliverables:** The petition artifact grammar (direction enum, single-line
  reason, unit and step identity, 1 KiB cap, `LC_ALL=C` parsing) and its pinned
  worktree filename; parser with strict validation and untrusted-input screening
  (contained regular-file-only path handling, no symlink following, bounded read,
  sanitized echo, no interpolation); temp-then-rename write contract for workers and
  atomic rename-claim consumption for the policy; single-consumption lifecycle
  (weighed once, ledger row, artifact removed — invalid, stale, torn, and
  out-of-grammar petitions also consumed and ignored with a ledger row); policy
  consumption at launch boundaries as one trigger input, hint-only under all clamps
  and the adjustment cap; the petition-policy knob
  (`on | off | escalate-only | de-escalate-only`) with its options-reference row;
  worker instruction prose for when to petition; the no-worktree degradation
  documented; tests including hostile-input fixtures (oversize, out-of-grammar,
  control bytes, path tricks, symlink at the pinned path, FIFO/non-regular file,
  stale cross-task petition, torn read, claim-race with two readers,
  crash-between-claim-and-ledger reconciliation).
- **Done when:** a valid escalate/de-escalate petition adjusts the next launch's tier
  within bounds and its artifact is gone afterward; every hostile fixture is consumed
  and ignored with a ledger row and clean output; two racing consumers move the tier
  at most one step; a petition never exceeds a clamp or the adjustment cap in tests;
  the petition-policy knob's off and direction-filtered states ignore valid petitions
  with a ledger row.
- **Dependencies:** 2
- **Citations:** D-7, D-8 · REQ-C1.3, REQ-C1.6, REQ-C1.7, REQ-E1.1, REQ-E1.2
- **Estimated effort:** 2 days

### Task 4 — Escalation feedback observation

- **Deliverables:** Terminal-state evaluation (completion or crash-loop disable; unit
  ended above starting tier, or escalation count at the configured feedback
  threshold) wired to the shared observation recording helper, emitted once per unit
  (ledger-marked); the observation text shape naming task, spec, starting and final
  tiers, carrying no worker-authored free prose; the feedback-threshold knob with its
  options-reference row; helper-failure surfacing; tests for threshold firing at
  default and non-default values, non-firing, the disabled-unit terminal state, the
  escalated-then-reverted boundary case, and emission idempotency across re-derivation.
- **Done when:** a fixture unit crossing either threshold produces exactly one
  grammar-valid observation fragment via the shared helper (including a crash-loop
  disabled fixture), a unit below both produces none, re-evaluation does not
  re-record, and a helper failure surfaces non-zero.
- **Dependencies:** 2
- **Citations:** D-11 · REQ-F1.2, REQ-E1.1, REQ-E1.2
- **Estimated effort:** half day

### Task 5 — Per-step selection keys

- **Deliverables:** Step-type tier keys (implementation step, each review-sequence
  step class) resolvable per launch under per-step isolation; step-type application
  strictly one-directional (a cheaper configured tier applies for that step's launch
  only, scope-marked in the ledger; an equal or more expensive one is ignored with a
  ledger row); defaults reproducing today's behavior (all steps at the unit's tier);
  options-reference rows; tests including the restore-after fixture (the unit's
  derived tier after a scope-marked step launch equals its pre-step tier).
- **Done when:** with defaults only, every step of a unit resolves to the unit's tier
  per the golden baseline; a configured cheaper review-step tier takes effect only at
  that step's launch, is scope-marked, and the unit's derived tier is unchanged after;
  a more-expensive step-type fixture is ignored with a ledger row;
  `check-options-reference` passes.
- **Dependencies:** 1, 2
- **Citations:** D-8, D-12 · REQ-C1.3, REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 6 — Launch-point wiring beyond the fleet

- **Deliverables:** Single-spec `/orchestrate` dispatch, `/execute-task` per-step
  session launches, and `/offload` dispatch resolving through the shared resolver
  with the `inherit` sentinel as shipped default; application per the backend's
  advertised capability, per dimension, with inheritance ledger rows for full and
  partial inheritance and errored capability probes; the backend capability
  contract amended with the model/effort-set capability column; resolved values
  passed as discrete quoted argv elements or launch parameters only; the in-session
  work-placement rung's inheritance documented as its pinned degradation;
  skill-prose updates; tests where the surface is scriptable, with the
  non-scriptable remainder enumerated by name in the test spec.
- **Done when:** each named launch point demonstrably consults the resolver (a test
  per scriptable surface; the enumerated manual surfaces verified by a recorded
  manual pass at this task's review); with defaults only every surface launches
  exactly as today (inherit, with a ledger row); a capability-lacking and a
  partially-capable backend fixture each yield the correct inheritance ledger row,
  never a silent ambient launch; the capability-contract column lands.
- **Dependencies:** 1, 2
- **Citations:** D-4, D-10, D-12, D-13 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-A1.2
- **Estimated effort:** 2 days

### Task 7 — Operator documentation

- **Deliverables:** Operator-facing docs covering the allocation policy: the knob
  family, fallback, and the `inherit`/master-knob opt-in posture; the ladder step
  rule and event stacking (the adaptation model and its triggers); the petition
  contract including its single-consumption lifecycle and the no-worktree
  degradation; the ledger and how to read "why did this unit run on that model",
  including degraded mode; the feedback loop; why the escalation path is fixed (the
  deferred `allocation_ladder` gate); cross-links from the existing fleet docs.
- **Done when:** the docs answer, without reading source: how to enable adaptation
  and set a starting tier, how the ladder steps and stacks, how to cap adjustment,
  how a clamp or degraded-mode decision is read from the ledger, what happens to a
  petition after it is weighed, and how the `fleet_*` fallback relates to
  `allocation_*`; doc-link checks pass.
- **Dependencies:** 3, 4, 5, 6
- **Citations:** D-5, D-8, D-11, D-13 · REQ-E1.2, REQ-F1.1, REQ-B1.3, REQ-C1.7
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Configurable ladder knob (`allocation_ladder`).** The escalation path is pinned by
  rule in D-8; an ordered-list knob whose shipped default equals the pinned path stays
  out until evidence shows the path shape itself misfits — the same evidence-first
  graduation pattern as D-3. Confidence: medium.
  **Gate:** GATE(when: REQ-F1.2 escalation observations show a task class needing a
  different escalation path than the pinned D-8 successor rule).
  Citations: D-8, REQ-F1.2, kickoff §4 (2026-08-25).
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
