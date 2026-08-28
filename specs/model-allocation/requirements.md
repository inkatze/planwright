# Model Allocation — Requirements

**Status:** Ready
**Last reviewed:** 2026-08-25
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright resolves a model and reasoning effort per dispatched unit, but only per
task *type* (execution, bookkeeping, drain) and only at fleet dispatch. Nothing weighs
how hard an individual task actually is, nothing re-weighs it when execution reveals the
estimate was wrong, and the non-fleet launch points — single-spec `/orchestrate`
dispatch, `/execute-task`'s per-step sessions, `/offload` — do no model selection at all.

This spec makes selection effort-aware and universal: every point where planwright
launches work resolves its tier — a joint (model, effort) point — through one
configurable, deterministic policy. The starting tier comes from per-type
configuration; execution-time evidence (step failure, flailing, review
non-convergence, a structured worker petition) adjusts the tier at relaunch boundaries;
and every adjustment is clamped by the account-global usage signal, restriction
ladder, and per-tier caps that `fleet-autonomy` already ships and this spec consumes
as unmodified contracts. Because the usage signal is account-global, selection is
shared-aware by construction: it reflects every concurrent orchestrator and all
non-planwright work on the same account. The capability lands in core as opt-in,
default-preserving configuration — shipped defaults change no behavior at any surface
(D-13); policy values stay overlay-owned.

## Scope

### In scope

- One deterministic, surface-agnostic selection resolver, generalized from the existing
  fleet selection table (all three columns: model, effort, command), with a new general
  knob family and back-compat fallback.
- Effort-aware adaptation: tier re-resolution at launch boundaries on deterministic
  execution events, plus a structured worker petition (both directions), gated behind a
  master adaptation knob shipping off.
- Wiring every launch point — fleet dispatch, single-spec `/orchestrate`,
  `/execute-task` per-step sessions, `/offload` — through the shared policy.
- Budget clamping of every selection and adjustment via the consumed `fleet-autonomy`
  usage-gate contracts, applied with their own semantics.
- A per-unit allocation ledger as the structured audit trail for selections and
  adjustments, a sparse governance-event mirror into the shared fleet-audit trail, and
  an observation-fragment feedback loop for chronically under-estimated tasks.

### Out of scope

- Token-usage and context-size reduction (context engineering). A separate future spec;
  the `ctxeng-*` observation fragments remain unconsumed as its seeds.
- Changes to the `/usage` gate, restriction ladder, per-tier caps, or their thresholds.
  `fleet-autonomy` owns them; this spec consumes them as contracts.
- Currency-denominated spend accounting, per-model reservation ledgers, and any change
  to the credit-continuation spend policy.
- Any degrade that touches a safety floor: workers stay full session-grade, the
  determinism floor holds, and `auto` permission mode is never engaged.
- LLM judgment in the resolution path. Model output may supply a *signal* (the
  petition); resolution itself stays deterministic script logic.
- Mid-session model switching and in-session advisories. Selection applies where a
  session or agent is launched; running sessions inherit.

## REQ-A — Selection policy

- **REQ-A1.1** A single deterministic resolver SHALL produce the tier — the joint
  (model, effort) point, plus the command column where the surface consumes it — for
  every unit or step launch from configurable rules; no LLM call SHALL be in the
  resolution path.
  *(Cites: D-2, D-5; fleet-autonomy REQ-E1.1.)*
- **REQ-A1.2** Shipped defaults SHALL reproduce current selection behavior exactly at
  every surface: an operator who configures nothing observes no selection-behavior
  change (new ledger and audit rows are additive telemetry and exempt). Equivalence
  SHALL be measured against a captured golden baseline of the current shipped table,
  never against the new implementation's own output.
  *(Cites: D-3, D-5, D-13; the customization-boundary doctrine (Sources).)*
- **REQ-A1.3** New policy knobs SHALL live in a general, surface-agnostic
  `allocation_*` knob family covering all three selection columns (model, effort,
  command) plus the adaptation controls; where a general knob is unset the resolver
  SHALL fall back to the corresponding legacy `fleet_*` knob, and the legacy family
  SHALL remain documented as a deprecated fallback, never removed. At surfaces that
  perform no selection today the shipped default SHALL be the explicit `inherit`
  sentinel, and adaptation SHALL be gated behind the `allocation_adaptation` master
  knob shipping `off`.
  *(Cites: D-5, D-13; drafting-session decision (2026-08-24).)*
- **REQ-A1.4** Model values SHALL be restricted to the stable Claude Code model
  aliases, effort values to the established effort enum, and command values to the
  closed command enum (`execute-task | orchestrate | drain`) that carries the
  review-sequence-disjointness invariant; numeric knobs SHALL be validated against a
  pinned grammar before any arithmetic use; every knob SHALL resolve through the
  shared knob resolver under the established by-layer malformed policy.
  *(Cites: D-5; fleet-autonomy REQ-E1.8; the customization-overlay by-layer policy
  (Sources).)*

## REQ-B — Launch-point coverage

- **REQ-B1.1** Fleet dispatch, single-spec `/orchestrate` dispatch, `/execute-task`
  per-step session launches, and `/offload` dispatch SHALL each resolve model and
  effort through the shared policy before launching work.
  *(Cites: D-4, D-5, D-12; the operator invocation (Sources).)*
- **REQ-B1.2** The resolved choice SHALL be applied per the launching backend's
  advertised capability, per dimension: a backend lacking a dimension inherits the
  ambient value for that dimension (model, effort, or both), and every inheritance —
  full or partial, including a capability probe that errors — SHALL be recorded in
  the ledger, never silent. Resolved values SHALL reach backends only as discrete
  quoted argv elements or launch parameters, never interpolated into a command string.
  *(Cites: D-10; the backend capability contract (Sources).)*
- **REQ-B1.3** Work running in the operator's own session (the in-session
  work-placement rung, in `/offload`'s sense — not a restriction-ladder rung)
  inherits the session's model; this SHALL be documented as the pinned degradation of
  the in-session rung.
  *(Cites: D-4; drafting-session decision (2026-08-24).)*

## REQ-C — Execution-time adaptation

- **REQ-C1.1** Tier adjustment SHALL occur only at launch boundaries (a unit's first
  launch, a step relaunch, or a retry), and the unit's current tier SHALL be derived
  from its allocation ledger, memoryless: a relaunched resolver computes the same tier
  from the same records and the same configuration. A unit with no ledger rows is at
  its configured starting tier.
  *(Cites: D-6; fleet-autonomy D-28 (Sources).)*
- **REQ-C1.2** Escalation SHALL trigger only on deterministic, work-shaped execution
  events — a step failure or retry, a flailing classification, review-sequence
  non-convergence, or a valid escalate petition — carrying idempotency identity
  (unit, step, attempt, event class); at one launch boundary each distinct event
  class SHALL contribute at most one ladder step, and infrastructure failures SHALL
  NOT be trigger events. Total adjustment SHALL be bounded by the configurable
  per-unit adjustment cap (net displacement, each direction). Confidence-calibrated
  escalation SHALL NOT be used.
  *(Cites: D-2, D-8; fleet-autonomy D-11 (Sources).)*
- **REQ-C1.3** De-escalation SHALL occur only on a valid de-escalate petition or when
  the next step's configured step-type tier is cheaper than the unit's current tier
  (a clamped proposal is recorded as clamped, never as de-escalation; a step-type
  tier that is not cheaper is ignored with a ledger row). A petition reverses the
  unit's most recent unreversed escalation step; with none to reverse it steps below
  the starting tier by the D-8 mirror rule, floored at the ladder bottom and bounded
  by the adjustment cap. A step-type tier applies to that step's launch only,
  scope-marked in the ledger.
  *(Cites: D-7, D-8; drafting-session decision (2026-08-24).)*
- **REQ-C1.4** Every selection and every adjustment SHALL be clamped by the consumed
  upstream contracts applied with their own semantics — the restriction-ladder rung
  (defer rungs SHALL yield a withheld unit, not a tier), the per-tier caps (active per
  their signal-availability contract), the downshift values (binding per their rung
  contract), and the reserved-unit exemptions passed through; an unreadable or
  unrecognized clamp input SHALL fail closed in the spend-safe direction. A clamp
  SHALL never be bypassed, and a petition is a hint the policy weighs, never an
  authority that overrides a clamp.
  *(Cites: D-1, D-7, D-8.)*
- **REQ-C1.5** When a unit keeps failing and cannot escalate — a clamp denial, an
  exhausted adjustment cap, or the ladder top — the existing crash-loop backoff and
  disable thresholds SHALL govern, escalating to the human decision queue through the
  existing path; no parallel mechanism SHALL be introduced.
  *(Cites: D-9; fleet-autonomy REQ-A1.4.)*
- **REQ-C1.6** The worker petition SHALL be a structured artifact with a strict,
  pinned grammar (direction enum, single-line reason, unit and step identity, size
  cap, `LC_ALL=C` parsing), screened as untrusted input with the pinned path taken
  only as a contained regular file (no symlink following, bounded read), written
  temp-then-rename and consumed by atomic claim; an invalid, stale, torn, or
  out-of-grammar petition SHALL be consumed, ignored, and recorded in the ledger,
  never acted on and never interpolated. (The worker petition is distinct from
  `/offload`'s petition-of-work.)
  *(Cites: D-7; the security-posture doctrine (Sources).)*
- **REQ-C1.7** A valid petition SHALL be consumed when weighed — recorded in the
  ledger, the artifact removed — so one petition moves the tier at most one step,
  ever; signaling again requires a fresh petition. Rungs without a worktree have no
  petition channel, documented as a degradation.
  *(Cites: D-7; kickoff §7 (2026-08-25).)*

## REQ-D — Budget integration

- **REQ-D1.1** Selection SHALL consume the account-global usage signal, restriction
  ladder, and per-tier caps as authoritative upstream contracts, unmodified; this spec
  SHALL NOT alter their thresholds, cadence, or semantics.
  *(Cites: D-1; fleet-autonomy REQ-E1.5, REQ-E1.6, REQ-E1.9.)*
- **REQ-D1.2** While the usage signal is unavailable — including a signal reader that
  errors, hangs past its timeout, or returns unparseable output, which SHALL be
  treated as unavailable — escalation above the unit's starting tier SHALL be denied;
  a unit already above its starting tier SHALL hold its tier (no claw-back).
  Signal-unavailable rung behavior otherwise follows the upstream hold-then-decay
  contract.
  *(Cites: D-1, D-8; fleet-autonomy REQ-E1.10.)*

## REQ-E — Configurability

- **REQ-E1.1** Every policy value this spec introduces — the adaptation master knob,
  starting tiers (model, effort, command), step-type tiers, the per-unit adjustment
  cap, the petition policy (`on | off | escalate-only | de-escalate-only`,
  subordinate to the master knob), and the feedback threshold — SHALL be
  operator-configurable through the config overlay layers, with core defaults
  preserving shipped behavior.
  *(Cites: D-3, D-5, D-8, D-13.)*
- **REQ-E1.2** Every knob this spec introduces SHALL carry a row in the canonical
  options reference, enforced by the existing options-reference guard.
  *(Cites: D-5; bootstrap D-43 (Sources).)*

## REQ-F — Observability and feedback

- **REQ-F1.1** Every resolution and every adjustment SHALL append a structured row to
  the unit's allocation ledger naming the unit, step, attempt, event class, the
  proposed / clamped / resolved tier, scope, and the inputs that produced the choice
  (trigger, rung, clamps applied, fallback or inheritance taken), including ignore,
  denial, no-op, and inheritance outcomes; governance events (escalation, denial,
  clamp binding, inheritance) SHALL additionally mirror one row each into the shared
  fleet-audit trail. When the ledger is unhealthy the unit SHALL launch in degraded
  mode (last recorded tier or starting tier, adjustments suspended) with the
  degradation surfaced through the existing attention path, never silently.
  *(Cites: D-6; drafting-session decision (2026-08-24).)*
- **REQ-F1.2** A unit whose terminal state — completion or crash-loop disable —
  leaves it at a higher tier than it started, or whose escalation count reached the
  configured feedback threshold, SHALL be recorded as an observation fragment through
  the standard recording ritual, once per unit (ledger-marked), carrying no
  worker-authored free prose; a recording failure SHALL be surfaced. Chronic
  under-estimation thereby reaches future drafting through the drain loop.
  *(Cites: D-11; the observation-recording accumulator ritual (Sources).)*
- **REQ-F1.3** Ledger size and derivation latency SHALL be surfaced through the
  existing stats path as the instrument behind the risk register's growth signal.
  *(Cites: D-6; kickoff §7 (2026-08-25).)*

## Changelog

- 2026-08-24 — Initial draft, elicited via `/spec-draft`. Fold-detection found heavy
  overlap with fleet-autonomy's resource-governance group; spun new per the
  spin-new triggers (independently ownable, spans non-fleet surfaces, bundle-size),
  consuming that group's mechanisms as contracts.
- 2026-08-25 — Kickoff walkthrough edits: D-8 pins the joint (model, effort) ladder
  and its step rule (effort-first escalation, audit-derived petition de-escalation
  with the below-starting mirror rule, model-major cost order, cumulative event
  stacking); a Deferred entry gates a future `allocation_ladder` knob on drain-loop
  evidence (kickoff §4); D-7 pins the single-consumption petition lifecycle — weighed
  once, then consumed with an audit row (kickoff §7); test-spec gains the ladder-top
  no-op and below-starting mirror-rule fixtures (kickoff §5).
- 2026-08-25 — Kickoff lens-pass revision (kickoff sign-off, nine clusters): fully
  opt-in defaults (D-13 minted: inherit sentinel, `allocation_adaptation` master knob
  off, golden-baseline equivalence); clamp model rewritten to defer to upstream
  semantics (rung-conditional downshift, signal-dependent caps, reserved exemptions,
  withheld outcome, fail-closed inputs); the shared-trail audit store replaced by a
  per-unit allocation ledger with a sparse fleet-audit mirror (D-6 amended); petition
  hardening (grammar bounds, path posture, claim atomicity, unit/step binding,
  REQ-C1.7 minted) and one symmetric adjustment cap; per-event-class stacking with
  idempotency keys (refines the kickoff §3 cumulative-stacking record); degraded-mode
  failure posture; command column joins the `allocation_*` family; normative-layer
  sync, task/test traceability, and instrumentation (REQ-F1.3 minted) edits applied
  across all four files.

## Sources

- **The operator invocation (2026-08-24)** — the seed ask: evaluate effort at any point
  a task runs, configurable, best model per estimated effort within budget and usage
  quotas; token-usage reduction possibly a separate spec. Pinned claims: selection must
  apply "at any point we need to run a task" (drove REQ-B; cited from REQ-B1.1), and
  "other processes and operations use tokens" so governance must stay shared-aware
  (satisfied by consuming the account-global usage signal, REQ-D1.1).
- **The fleet-autonomy bundle** (`specs/fleet-autonomy/`) — the consumed upstream
  contracts: the `/usage` gate and restriction ladder (REQ-E1.5, REQ-E1.6), the
  reactive throttle backstop (REQ-E1.7), per-tier caps and allocation clamps
  (REQ-E1.9, REQ-E1.10), the selection table and its knobs (REQ-E1.1, REQ-E1.8), the
  determinism floor (D-18), the ladder-state precedent (D-28), and the declined
  confidence-calibrated cascade (D-11) this spec's D-2 deliberately routes around.
- **The customization-overlay bundle** (`specs/customization-overlay/`) — the config
  overlay layers and the by-layer malformed policy REQ-A1.4 resolves under.
- **The backend capability contract** (`doctrine/backend-capability-contract.md`;
  bootstrap D-38) — the advertised-capability table D-10 extends with the
  model/effort-set column.
- **The configurable-model-allocation observation** — `obs:9af1f82f` (consumed by
  `specs/fleet-autonomy`; framing context for the per-task, budget-aware allocation
  ask behind the Goal).
- **The proactive-shared-usage-governance observation** — `obs:5d6d206c` (consumed by
  `specs/fleet-autonomy`; framing context for the shared-aware budget signal behind
  REQ-D1.1).
- **The fleet-audit write-amplification observation** —
  `obs:2bea1358` (2026-07-16): the shared trail's copy-append-rename write cost,
  flagged to revisit under real volume — the recorded evidence behind D-6's rejection
  of shared-trail appends as the allocation store.
- **The bootstrap bundle** (`specs/bootstrap/`) — the options-reference rule
  (bootstrap D-43, REQ-K1.8) that REQ-E1.2 applies to this spec's knobs.
- **research: LLM cascade and routing prior art** — the FrugalGPT-style
  cheap-first-escalate-on-evidence cascade and router systems (RouteLLM), read against
  fleet-autonomy's recorded survey of LLM cost-governance practice (found thin, no
  mature precedent to defer to wholesale). This spec adopts the cascade *shape* with
  event triggers, not confidence calibration (cited from D-2).
- **Doctrine** — `doctrine/customization-boundary.md` (the overlay-first tilt that kept
  the authored complexity field out of scope for now), `doctrine/security-posture.md`
  (petition screening), `doctrine/spec-format.md` (the bundle conventions this spec is
  authored under), the observation-recording accumulator ritual
  (`scripts/obs-record.sh`).
