# Model Allocation — Requirements

**Status:** Draft
**Last reviewed:** 2026-08-24
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright resolves a model and reasoning-effort tier per dispatched unit, but only per
task *type* (execution, bookkeeping, drain) and only at fleet dispatch. Nothing weighs
how hard an individual task actually is, nothing re-weighs it when execution reveals the
estimate was wrong, and the non-fleet launch points — single-spec `/orchestrate`
dispatch, `/execute-task`'s per-step sessions, `/offload` — do no model selection at all.

This spec makes selection effort-aware and universal: every point where planwright
launches work resolves model and effort through one configurable, deterministic policy.
The starting tier comes from per-type configuration; execution-time evidence (step
failure, flailing, review non-convergence, a structured worker petition) adjusts the
tier at relaunch boundaries; and every adjustment is clamped by the account-global usage
signal, restriction ladder, and per-tier caps that `fleet-autonomy` already ships and
this spec consumes as unmodified contracts. Because the usage signal is account-global,
selection is shared-aware by construction: it reflects every concurrent orchestrator and
all non-planwright work on the same account. The capability lands in core as opt-in,
default-preserving configuration; policy values stay overlay-owned.

## Scope

### In scope

- One deterministic, surface-agnostic selection resolver, generalized from the existing
  fleet selection table, with a new general knob family and back-compat fallback.
- Effort-aware adaptation: tier re-resolution at launch boundaries on deterministic
  execution events, plus a structured worker petition (both directions).
- Wiring every launch point — fleet dispatch, single-spec `/orchestrate`,
  `/execute-task` per-step sessions, `/offload` — through the shared policy.
- Budget clamping of every selection and adjustment via the consumed `fleet-autonomy`
  usage-gate contracts.
- A structured audit trail for selections and adjustments, and an observation-fragment
  feedback loop for chronically under-estimated tasks.

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

- **REQ-A1.1** A single deterministic resolver SHALL produce the model and
  reasoning-effort tier for every unit or step launch from configurable rules; no LLM
  call SHALL be in the resolution path.
  *(Cites: D-2, D-5; fleet-autonomy REQ-E1.1.)*
- **REQ-A1.2** Shipped defaults SHALL reproduce current selection behavior exactly at
  every surface: an operator who configures nothing observes no change.
  *(Cites: D-3, D-5; the customization-boundary doctrine (Sources).)*
- **REQ-A1.3** New policy knobs SHALL live in a general, surface-agnostic knob family;
  where a general knob is unset the resolver SHALL fall back to the corresponding
  legacy `fleet_*` knob, and the legacy family SHALL remain documented as a deprecated
  alias, never removed.
  *(Cites: D-5; drafting-session decision (2026-08-24).)*
- **REQ-A1.4** Model values SHALL be restricted to the stable Claude Code model aliases
  and effort values to the established effort enum; every knob SHALL resolve through
  the shared knob resolver under the established by-layer malformed policy.
  *(Cites: D-5; fleet-autonomy REQ-E1.8.)*

## REQ-B — Launch-point coverage

- **REQ-B1.1** Fleet dispatch, single-spec `/orchestrate` dispatch, `/execute-task`
  per-step session launches, and `/offload` dispatch SHALL each resolve model and
  effort through the shared policy before launching work.
  *(Cites: D-4, D-5, D-12; drafting-session decision (2026-08-24).)*
- **REQ-B1.2** The resolved choice SHALL be applied per the launching backend's
  advertised capability; a backend that cannot set model or effort at launch SHALL
  inherit the ambient model, and that degradation SHALL be surfaced in the audit
  record, never silent.
  *(Cites: D-10; fleet-autonomy REQ-E1.1.)*
- **REQ-B1.3** Work running in the operator's own session (the in-session rung)
  inherits the session's model; this SHALL be documented as the pinned degradation of
  the in-session rung.
  *(Cites: D-4; drafting-session decision (2026-08-24).)*

## REQ-C — Execution-time adaptation

- **REQ-C1.1** Tier adjustment SHALL occur only at launch boundaries (a step relaunch
  or a retry), and the unit's current tier SHALL be derived from the audit trail,
  memoryless: a relaunched resolver computes the same tier from the same records.
  *(Cites: D-6; fleet-autonomy D-28 (Sources).)*
- **REQ-C1.2** Escalation SHALL trigger only on deterministic execution events — a step
  failure or retry, a flailing classification, review-sequence non-convergence, or a
  valid escalate petition — one tier per triggering event, bounded by a configurable
  per-unit escalation cap. Confidence-calibrated escalation SHALL NOT be used.
  *(Cites: D-2, D-8; fleet-autonomy D-11 (Sources).)*
- **REQ-C1.3** De-escalation SHALL occur only on a valid de-escalate petition or when
  the next step's configured step-type tier is cheaper than the unit's current tier.
  *(Cites: D-8; drafting-session decision (2026-08-24).)*
- **REQ-C1.4** Every selection and every adjustment SHALL be clamped by the current
  restriction-ladder rung, the per-tier caps, and the downshift tier values; a clamp
  SHALL never be bypassed, and a petition is a hint the policy weighs, never an
  authority that overrides a clamp.
  *(Cites: D-1, D-7, D-8.)*
- **REQ-C1.5** When escalation is denied by a clamp and the unit keeps failing, the
  existing crash-loop backoff and disable thresholds SHALL govern, escalating to the
  human decision queue through the existing path; no parallel mechanism SHALL be
  introduced.
  *(Cites: D-9; fleet-autonomy REQ-A1.4.)*
- **REQ-C1.6** The worker petition SHALL be a structured artifact with a strict,
  validated grammar, screened as untrusted input; an invalid or out-of-grammar petition
  SHALL be ignored and the ignore recorded in the audit trail, never acted on and never
  interpolated.
  *(Cites: D-7; the security-posture doctrine (Sources).)*

## REQ-D — Budget integration

- **REQ-D1.1** Selection SHALL consume the account-global usage signal, restriction
  ladder, and per-tier caps as authoritative upstream contracts, unmodified; this spec
  SHALL NOT alter their thresholds, cadence, or semantics.
  *(Cites: D-1; fleet-autonomy REQ-E1.5, REQ-E1.6, REQ-E1.9.)*
- **REQ-D1.2** While the usage signal is unavailable, escalation above the unit's
  starting tier SHALL be denied; signal-unavailable rung behavior otherwise follows the
  upstream hold-then-decay contract.
  *(Cites: D-1, D-8; fleet-autonomy REQ-E1.10.)*

## REQ-E — Configurability

- **REQ-E1.1** Every policy value this spec introduces — starting tiers, step-type
  tiers, escalation cap, petition policy, feedback threshold — SHALL be
  operator-configurable through the config overlay layers, with core defaults
  preserving shipped behavior.
  *(Cites: D-3, D-5, D-8.)*
- **REQ-E1.2** Every knob this spec introduces SHALL carry a row in the canonical
  options reference, enforced by the existing options-reference guard.
  *(Cites: D-5; bootstrap D-43 (Sources).)*

## REQ-F — Observability and feedback

- **REQ-F1.1** Every resolution and every adjustment SHALL append a structured audit
  record naming the unit, the step, the chosen model and effort, and the inputs that
  produced the choice (trigger event, rung, clamps applied, fallback taken).
  *(Cites: D-6; drafting-session decision (2026-08-24).)*
- **REQ-F1.2** A unit that ends at a higher tier than it started, or whose escalations
  reach a configurable threshold, SHALL be recorded as an observation fragment through
  the standard recording ritual, so chronic under-estimation reaches future drafting
  through the drain loop.
  *(Cites: D-11; the observation-recording accumulator ritual (Sources).)*

## Changelog

- 2026-08-24 — Initial draft, elicited via `/spec-draft`. Fold-detection found heavy
  overlap with fleet-autonomy's resource-governance group; spun new per the
  spin-new triggers (independently ownable, spans non-fleet surfaces, bundle-size),
  consuming that group's mechanisms as contracts.

## Sources

- **The operator invocation (2026-08-24)** — the seed ask: evaluate effort at any point
  a task runs, configurable, best model per estimated effort within budget and usage
  quotas; token-usage reduction possibly a separate spec. Pinned claims: selection must
  apply "at any point we need to run a task" (drove REQ-B), and "other processes and
  operations use tokens" so governance must stay shared-aware (satisfied by consuming
  the account-global usage signal, REQ-D1.1).
- **The fleet-autonomy bundle** (`specs/fleet-autonomy/`) — the consumed upstream
  contracts: the `/usage` gate and restriction ladder (REQ-E1.5–E1.7), per-tier caps and
  allocation clamps (REQ-E1.9, REQ-E1.10), the selection table and its knobs (REQ-E1.1,
  REQ-E1.8), the determinism floor (D-18), the ladder-state precedent (D-28), and the
  declined confidence-calibrated cascade (D-11) this spec's D-2 deliberately routes
  around.
- **The configurable-model-allocation observation** — `obs:9af1f82f` (consumed by
  `specs/fleet-autonomy`; cited here as framing context for the per-task, budget-aware
  allocation ask).
- **The proactive-shared-usage-governance observation** — `obs:5d6d206c` (consumed by
  `specs/fleet-autonomy`; framing context for the shared-aware budget signal).
- **The bootstrap bundle** (`specs/bootstrap/`) — the options-reference rule
  (bootstrap D-43, REQ-K1.8) that REQ-E1.2 applies to this spec's knobs.
- **research: LLM cascade and routing prior art** — the FrugalGPT-style
  cheap-first-escalate-on-evidence cascade and router systems (RouteLLM), read against
  fleet-autonomy's recorded survey of LLM cost-governance practice (found thin, no
  mature precedent to defer to wholesale). This spec adopts the cascade *shape* with
  event triggers, not confidence calibration.
- **Doctrine** — `doctrine/customization-boundary.md` (the overlay-first tilt that kept
  the authored complexity field out of scope for now), `doctrine/security-posture.md`
  (petition screening), `doctrine/spec-format.md` (bundle conventions), the
  observation-recording accumulator ritual (`scripts/obs-record.sh`).
