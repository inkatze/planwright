# Model Allocation — Design

**Status:** Draft
**Last reviewed:** 2026-08-24
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision in this bundle.

## Decision log

### D-1: fleet-autonomy's resource-governance mechanisms are consumed contracts  (N)

**Decision:** The account-global `/usage` signal, the restriction ladder, the per-tier
caps, the downshift clamps, and the reactive throttle backstop are consumed as
authoritative, unmodified upstream contracts. This spec reads their outputs (current
rung, cap state, signal availability) and never alters their thresholds, cadence,
semantics, or scripts' contracts.

**Alternatives considered:**
- Extend fleet-autonomy instead of consuming it. Rejected because: the spin-new
  triggers fire — this capability is independently ownable, spans non-fleet surfaces
  orthogonal to fleet self-maintenance, and fleet-autonomy is already past
  one-feature-in-the-head size.
- Re-implement a budget signal locally. Rejected because: the existing signal is
  account-global and therefore already shared-aware; a second reader with its own
  thresholds would disagree with the first.

**Chosen because:** consuming contracts is how fleet-autonomy itself builds on
orchestration-fleet; it keeps one authoritative budget reader and lets this spec stay
small.

### D-2: Event-triggered adaptation, not a confidence-calibrated cascade  (N)

**Decision:** Tier adaptation triggers exclusively on deterministic, observable
execution events: a step failure or retry, a flailing classification, review-sequence
non-convergence, and a valid worker petition. No confidence score, no calibrated
threshold, no LLM call in the resolution path.

**Alternatives considered:**
- Confidence-calibrated cascade (route by a model's self-reported or scored
  confidence). Rejected because: fleet-autonomy D-11 records calibrating the
  escalation threshold as an open problem it deliberately declined; that reasoning
  still holds, and this spec routes around the declined territory rather than
  reopening it.
- Static selection only (no adaptation). Rejected because: the operator's seed
  explicitly names execution-time factors that make drafting-time estimates wrong;
  static selection systematically misprices those units.

**Chosen because:** events are ground truth the fleet already observes (the flailing
classifier, retry counters, convergence state) — the cascade *shape* from LLM
cost-governance prior art with the uncalibratable part cut out.

### D-3: Starting tier from configuration; no authored complexity field  (N)

**Decision:** A unit's starting tier comes from per-type configuration (the existing
task-type keys, extended by per-step keys). No new authored field is added to the task
block format in this spec.

**Alternatives considered:**
- An optional authored complexity tier (mechanical | standard | hard) in task blocks.
  Rejected for now because: it amends the meta-spec's task-block grammar, validator,
  and anchor extraction ahead of evidence; the customization-boundary tilt says a
  preference graduates into core only with drain-loop evidence. The REQ-F1.2 feedback
  loop is exactly the evidence channel; chronic starting-tier misses recorded there
  are the graduation case for a future amendment.
- Deriving a tier from the existing `Estimated effort` duration. Rejected because:
  duration conflates size with difficulty — a long mechanical task and a short hard
  task both get mispriced by construction.

**Chosen because:** zero format surgery now, adaptation absorbs estimate error at run
time, and the graduation path is explicit rather than foreclosed.

### D-4: Selection applies at launch points only  (N)

**Decision:** Model/effort resolution happens wherever planwright launches a session or
agent (fleet dispatch, single-spec dispatch, per-step session launches, offload
dispatch). Work already running inherits its session's model; the in-session rung's
inheritance is documented as its pinned degradation. No mid-session switching, no
in-session advisories.

**Alternatives considered:**
- In-session advisories ("consider /model sonnet for this step"). Rejected because:
  adds an interaction surface to attended flows for marginal value; the operator chose
  launch-points-only.
- Mid-session model switching. Rejected because: not mechanically supported as a
  programmatic act; pretending otherwise would make the policy's coverage claim false.

**Chosen because:** matches what the platform mechanically supports; per-step isolation
already makes launch boundaries frequent enough for adaptation to bite.

### D-5: One generalized resolver; `allocation_*` knobs with `fleet_*` fallback  (N)

**Decision:** The fleet selection table generalizes into a surface-agnostic resolver
that every launch point calls. Knobs this spec introduces live in a new general
`allocation_*` family; where a general knob is unset the resolver falls back to the
corresponding legacy `fleet_*` knob, and the `fleet_*` family stays documented as a
deprecated alias, never removed. Value enums (model aliases, effort levels), the shared
knob resolver chain, and the by-layer malformed policy are unchanged.

**Alternatives considered:**
- Extend the `fleet_*` namespace everywhere. Rejected because: the name would lie
  about scope for every non-fleet surface, permanently, in the options reference.
- Hard rename with a warning-driven migration. Rejected because: imposes a migration
  burden the feature does not need; fallback gives the same end state lazily.

**Chosen because:** existing overlays keep working unchanged (default-preserving), new
surfaces get an honest name, and the resolver remains the single place selection logic
lives (the existing-seam-reuse disposition).

### D-6: Adaptation state is audit-derived and memoryless  (N)

**Decision:** The unit's current tier is derived, at each resolution, from the
structured audit records of prior resolutions and trigger events. No separate state
file, no `tasks.md` annotation, no in-memory dependency: a relaunched resolver computes
the same tier from the same records. Selection and adjustment events append audit rows
(this is new behavior relative to the current table, which writes no audit row;
selection remains a non-daemon action outside the kill-switch's enumeration — the audit
write is passive recording, not an autonomous act).

**Alternatives considered:**
- A per-unit runtime state file. Rejected because: a second source of truth beside the
  audit trail, with crash-consistency questions the audit-derived pattern already
  solved for ladder state.
- Execution-state annotations in `tasks.md`. Rejected because: format-version 2 stores
  no execution state in bundles by design.

**Chosen because:** fleet-autonomy D-28 established audit-derived state exactly so
memoryless relaunches converge; reusing the pattern keeps one recovery story.

### D-7: The petition is a strict-grammar marker artifact, hint-only  (N)

**Decision:** A worker signals "harder/easier than estimated" by writing a structured
petition artifact (direction, one-line reason) at a pinned path in its own worktree at
a step boundary. The deterministic policy reads it at the next launch boundary,
validates it against a strict grammar, and weighs it as one trigger input. Petition
content is untrusted input: screened before any echo, never interpolated, never
executed; an invalid petition is ignored with an audit record. A petition can never
override a clamp, a cap, or the escalation bound.

**Alternatives considered:**
- Parsing petitions out of worker stdout/transcripts. Rejected because: fragile,
  version-sensitive surface (the same fragility class as the `/usage` render), and a
  wider injection surface than a pinned-path file with a strict grammar.
- No petition (events only). Rejected because: the operator chose it in scope — it is
  the only signal that captures "the remaining steps are mechanical", the
  budget-saving direction events cannot see.

**Chosen because:** judgment supplies a signal while resolution stays deterministic —
the determinism floor holds with the LLM kept out of the decision path.

### D-8: Escalation bounds, clamp order, and flap resistance  (N)

**Decision:** Adjustment moves one tier per triggering event along the fixed alias
ladder. A configurable per-unit escalation cap bounds total climb. Clamps apply in
fixed order after the trigger policy proposes a tier: restriction-ladder rung, then
per-tier caps, then downshift values — the cheapest surviving tier wins, and a clamped
proposal is recorded as clamped. De-escalation occurs only via petition or a cheaper
configured step-type tier (no speculative decay). While the usage signal is
unavailable, escalation above the starting tier is denied. All re-resolution happens
only at launch boundaries, which is the flap resistance: there is no mid-step
oscillation surface.

**Alternatives considered:**
- Multi-tier jumps on severe events. Rejected because: one-tier steps keep the audit
  trail explanatory and the cost surface predictable; a severe event recurs and climbs
  again if genuinely needed.
- Time-based dwell hysteresis (mirroring the rung ladder). Rejected because: launch
  boundaries are already discrete and infrequent; a second dwell mechanism adds knobs
  without an observed flapping mode. Revisit only on drain-loop evidence of flapping.

**Chosen because:** bounded, explainable, and conservative in the spend direction under
uncertainty.

### D-9: Denied escalation folds into the existing failure machinery  (N)

**Decision:** When a clamp denies escalation and the unit continues to fail, the
existing crash-loop backoff, disable threshold, and decision-queue escalation govern
unchanged. This spec adds no parallel "stuck because budget" mechanism; the audit trail
records that escalation was denied, which is what the human sees when the existing
escalation fires.

**Alternatives considered:**
- A dedicated budget-blocked hold state. Rejected because: a second stuck-state
  machine to reconcile with liveness classification; the existing path already ends at
  a human with the audit trail explaining why.

**Chosen because:** existing-seam-reuse; fewer states, one escalation story.

### D-10: Application follows the backend capability contract  (N)

**Decision:** The resolver only *chooses*; applying model/effort at launch belongs to
the dispatching backend per its advertised capability (CLI launch flags for session
backends, the subagent launch parameters for in-process agents). A backend that cannot
set model or effort inherits ambient values, and the audit record marks the
inheritance. No backend is special-cased by name.

**Alternatives considered:**
- Refusing dispatch on backends that cannot apply the choice. Rejected because:
  turns a capability gap into an availability failure; inheritance-with-audit degrades
  gracefully, matching the established degradation posture.

**Chosen because:** consistent with the existing choose/apply split and the
capability-contract direction the dispatch layer already documents.

### D-11: Feedback via the standard observation ritual  (N)

**Decision:** A unit ending above its starting tier, or hitting the configured
escalation threshold, records an observation fragment through the shared recording
helper. No new accumulator, no new reader: `/spec-draft`'s seed mining is the existing
drain path by which chronic under-estimation reaches future authoring — and supplies
the graduation evidence D-3 names.

**Alternatives considered:**
- Writing back into the task block or bundle. Rejected because: execution state never
  writes into v2 bundles, and a per-task annotation would be invisible to cross-spec
  pattern mining.
- No feedback. Rejected because: the operator chose the loop; without it the same
  under-estimates recur silently.

**Chosen because:** reuses the accumulator taxonomy end to end; zero new mechanism.

### D-12: Depth-first sequencing — adaptation before breadth  (N)

**Decision:** After the resolver task, the adaptation thread (engine, petition,
feedback) executes before the breadth thread (per-step keys, non-fleet launch-point
wiring). The breadth tasks carry an explicit dependency edge on the adaptation engine;
the edge is a deliberate sequencing decision, not a technical dependency, recorded here
so nobody removes it as spurious.

**Alternatives considered:**
- Breadth first (uniform static selection everywhere, adaptation last). Rejected
  because: if work pauses partway, uniform-but-static selection saves little; the
  fleet is where spend concentrates, so making its selection smart first captures the
  value earliest.
- No ordering (parallel threads). Rejected because: the operator expressed an explicit
  priority; encoding it in edges is the only way orchestration selection honors it.

**Chosen because:** the operator's call: the highest-spend surface gets governed first
if the spec pauses partway.

## Cross-cutting concerns

- **Concurrency.** Audit-trail appends from concurrent workers share the existing
  audit surface's append discipline; tier derivation reads are per-unit (keyed by unit
  identity), so cross-unit interleaving cannot corrupt a derivation. Race windows on
  the shared audit file follow whatever locking the audit surface already ships; this
  spec adds readers and appenders, not a new store.
- **Security.** The petition artifact is the one new untrusted-input surface: strict
  grammar, validated before use, sanitized before echo, never interpolated (the
  security-posture write-time triggers apply to its parser).
- **Determinism floor.** Every decision path in this bundle is table lookup, config
  read, and event-record read — verifiable by the same test style the existing
  resolver uses.
