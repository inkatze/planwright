# Model Allocation — Design

**Status:** Ready
**Last reviewed:** 2026-08-25
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision in this bundle.

## Decision log

### D-1: fleet-autonomy's resource-governance mechanisms are consumed contracts  (N)

**Decision:** The account-global `/usage` signal, the restriction ladder, the per-tier
caps, the downshift clamps, and the reactive throttle backstop are consumed as
authoritative, unmodified upstream contracts. This spec reads their outputs (current
rung, cap state, signal availability) and never alters their thresholds, cadence,
semantics, or scripts' contracts. Consuming a contract means honoring its **own**
semantics, including its conditionality: rung-conditional downshift binding,
signal-dependent cap activity, and the reserved-unit exemptions are part of what is
consumed (see D-8).

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
small. *(Amended at kickoff lens pass 2026-08-25: consume-with-conditionality
clarified.)*

### D-2: Event-triggered adaptation, not a confidence-calibrated cascade  (N)

**Decision:** Tier adaptation triggers exclusively on deterministic, observable
execution events: a step failure or retry, a flailing classification, review-sequence
non-convergence, and a valid worker petition. No confidence score, no calibrated
threshold, no LLM call in the resolution path. Trigger events are **work-shaped**:
infrastructure failures (a config hard-fail, an audit write failure, a git or backend
launch error) are not trigger events — no model tier fixes them, and counting them
would burn the adjustment cap on mechanism trouble.

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
cost-governance prior art (research: LLM cascade and routing prior art, Sources) with
the uncalibratable part cut out.

*(Amended at kickoff lens pass 2026-08-25: infra-failure exclusion pinned; research
source cited.)*

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
dispatch). Work already running inherits its session's model; the in-session
work-placement rung's inheritance is documented as its pinned degradation. No
mid-session switching, no in-session advisories.

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
deprecated fallback, never removed. The family carries all three columns of the
existing table — model, effort, and **command** — with the command column's closed
enum (`execute-task | orchestrate | drain`) carried forward unchanged as the new home
of the review-sequence-disjointness invariant; non-fleet surfaces do not consume the
command column, documented as such. Value enums (model aliases, effort levels, command
values), the shared knob resolver chain, and the by-layer malformed policy are
unchanged; numeric knobs (the adjustment cap, the feedback threshold) carry a pinned
validation grammar (non-negative integers, validated before any arithmetic use).

**Alternatives considered:**
- Extend the `fleet_*` namespace everywhere. Rejected because: the name would lie
  about scope for every non-fleet surface, permanently, in the options reference.
- Hard rename with a warning-driven migration. Rejected because: imposes a migration
  burden the feature does not need; fallback gives the same end state lazily.
- Leave the command column fleet-only. Rejected because: Task 1's equivalence
  criterion covers the whole shipped row, and the disjointness invariant needs a named
  carrier in the generalized path.

**Chosen because:** existing overlays keep working unchanged (default-preserving), new
surfaces get an honest name, and the resolver remains the single place selection logic
lives (the existing-seam-reuse disposition).

*(Amended at kickoff lens pass 2026-08-25: command column and numeric-knob grammar
included; "alias" corrected to "fallback".)*

### D-6: Adaptation state is a per-unit allocation ledger, audit-derived and memoryless  (N)

**Decision:** Every resolution and adjustment appends a structured row to a dedicated
**per-unit allocation ledger** — an append-only store keyed by unit identity, one
ledger file per unit under the fleet state home, with a pinned schema: sequence
number, unit, step, attempt, event class, proposed / clamped / resolved (model,
effort), scope (`unit` or `step`-scoped), and the inputs (trigger, rung, clamps
applied, fallback or inheritance taken). The unit's current tier is derived, at each
launch boundary, from its own ledger — memoryless: a relaunched resolver computes the
same tier from the same records and the same configuration. Derivation and append
happen under one hold of the ledger's per-unit lock (the derive-then-append discipline
fleet-audit's caller contract mandates for derived state, applied at per-unit scope,
so holds are short and cross-unit contention is zero). Within one launch boundary the
resolver MAY memoize its derivation (discarded at boundary end) — recompute-identical
is preserved. **Sparse mirror:** governance events (an escalation, a denial, a clamp
binding, an inheritance) additionally record one row each into the shared fleet-audit
trail, so fleet-wide dashboards and D-9's human-visible story stay on the existing
surface; routine resolutions do not touch the shared trail. **Degraded mode:** when a
unit's ledger is unreadable, corrupt, or its append fails, the unit launches at its
last recorded tier (or the configured starting tier when none is readable), all
adjustments are suspended, and the degradation is surfaced through the existing
attention path — never a silent partial derivation, never a blocked launch. A unit
with no ledger rows is at its starting tier. Selection remains a non-daemon action
outside the kill-switch's enumeration; **this carve-out is a governance-boundary
rule:** the ledger write is passive recording accompanying a launch, not an autonomous
act.

**Alternatives considered:**
- Append allocation rows to the shared fleet-audit trail as the authoritative store.
  Rejected because: the trail's fixed six-field row carries no unit or step identity
  and no row sequence (per-unit derivation would be free-text matching), its per-append
  whole-day-file copy makes per-launch appends quadratic within a day (the recorded
  write-amplification observation, Sources), its retention prunes whole days out from
  under derived tier state, and derive+append under the shared lock at this write rate
  contends with the upstream ladder's own writes.
- A mutable per-unit runtime state file. Rejected because: a second source of truth
  beside an audit record, with the crash-consistency questions the audit-derived
  pattern exists to avoid. (The append-only ledger is the audit-derived pattern,
  partitioned per unit — not this alternative.)
- Execution-state annotations in `tasks.md`. Rejected because: format-version 2 stores
  no execution state in bundles by design.

**Chosen because:** fleet-autonomy D-28 established audit-derived state so memoryless
relaunches converge; partitioning the ledger per unit keeps that recovery story while
giving derivation a real key, bounded scans, short locks, and retention decoupled from
the shared trail.

*(Amended at kickoff lens pass 2026-08-25: dedicated per-unit ledger with sparse
fleet-audit mirror replaces shared-trail appends; schema, lock discipline, memo
allowance, and degraded mode pinned.)*

### D-7: The petition is a strict-grammar marker artifact, hint-only  (N)

**Decision:** A worker signals "harder/easier than estimated" by writing a structured
petition artifact at a pinned filename in its own worktree at a step boundary. The
grammar is pinned and closed: direction (an enum: `escalate | de-escalate`), a
single-line reason, the unit id, and the step or attempt identity it was written
under; at most 1 KiB; parsed under `LC_ALL=C`; anything else is invalid. The
deterministic policy reads it at the next launch boundary and weighs a valid petition
as one trigger input. **Path posture:** the reader takes the pinned path only as a
regular file (no symlink following, `lstat`-checked), containment-checked within the
worker's worktree, read bounded at the size cap. **Atomicity:** the worker writes
temp-then-rename; the policy consumes by atomically renaming the file out of the
pinned path (the claim) before validating — two racing readers cannot double-consume,
and a crash after the claim reconciles as ignored-with-audit at the next boundary.
**Consumption:** weighing consumes the petition — recorded in the ledger, the claimed
file removed — so one petition moves the tier at most one step, ever; signaling again
requires a fresh petition. An invalid, stale (wrong unit or step), torn, or
out-of-grammar petition is also consumed and ignored with a ledger row, never acted
on, never interpolated, never echoed unsanitized. Rungs with no worktree (in-session
work) have no petition channel; that absence is a documented degradation, not an
error. A petition can never override a clamp, a cap, or the adjustment bound.

**Alternatives considered:**
- Parsing petitions out of worker stdout/transcripts. Rejected because: fragile,
  version-sensitive surface (the same fragility class as the `/usage` render), and a
  wider injection surface than a pinned-path file with a strict grammar.
- No petition (events only). Rejected because: the operator chose it in scope — it is
  the only signal that captures "the remaining steps are mechanical", the
  budget-saving direction events cannot see.
- Leaving invalid petitions in place. Rejected because: an unconsumed invalid file is
  re-parsed and re-audited at every subsequent boundary — unbounded ledger spam from
  one hostile write.

**Chosen because:** judgment supplies a signal while resolution stays deterministic —
the determinism floor holds with the LLM kept out of the decision path.

*(Amended at kickoff walkthrough 2026-08-25: single-consumption lifecycle pinned.
Amended at kickoff lens pass 2026-08-25: grammar bounds, path posture, claim
atomicity, unit/step binding, and invalid-consumption pinned.)*

### D-8: The tier ladder, adjustment bounds, clamp composition, and flap resistance  (N)

**Decision:** A tier is a joint (model, effort) point. The rules, one per bullet:

- **Movement (the successor rule).** Escalation raises effort one level until `high`,
  then raises the model one alias keeping effort `high`
  (`(m, e) → (m, e+1)` while `e < high`; `(m, high) → (m+1, high)` while
  `m < fable`). At the ladder top a further escalation is a no-op with a ledger row.
- **Cost order.** "Cheaper than" comparisons use model-major, effort-minor order.
  Movement and comparison are deliberately **two different orderings**: the successor
  path skips cost-order points (a model jump carries effort), and that is intended —
  the ladder is the path, the cost order is the comparator.
- **Event stacking.** Trigger events carry idempotency identity (unit, step, attempt,
  event class). At one launch boundary, each distinct event **class** contributes at
  most one ladder step; classes derived from the same incident (a failure and the
  retry it caused) do not stack, independent classes (a failure plus a petition) do.
  Each applied step appends its own ledger row.
- **The per-unit adjustment cap.** One configurable cap bounds **net displacement in
  each direction**: at most N steps of net climb above, and at most N steps below, the
  unit's starting tier. Reversals refund; the ladder ends are hard stops.
- **De-escalation.** Only two causes, and clamping is not one of them (a clamped
  proposal is recorded as *clamped*, never as de-escalation): a valid de-escalate
  petition reverses the unit's most recent unreversed escalation step (ledger-derived);
  with none to reverse, it steps below the starting tier by the mirror rule (lower
  effort one level until `low`, then lower the model one alias keeping effort `low`),
  floored at the ladder bottom and bounded by the adjustment cap. Escalation events
  re-raise a lowered tier — along the successor path, not necessarily retracing the
  downward path. A configured step-type tier **cheaper** than the unit's current tier
  applies for that step's launch only (scope-marked in the ledger, never becoming the
  unit's tier); a step-type tier equal to or more expensive than the current tier is
  ignored with a ledger row — step-type keys are one-directional by design.
- **Clamp composition.** Clamps are the consumed upstream contracts applied with
  their **own** semantics: the restriction-ladder rung (an admission decision at the
  defer rungs — a withheld unit is returned as *withheld* to the existing defer path,
  never resolved to a tier), the per-tier caps (active only while the usage signal is
  available; a binding cap moves the proposal to the nearest surviving cheaper model
  with effort preserved), and the downshift values (binding at the `downshift` rung
  and heavier, per upstream). Reserved-unit exemptions pass through untouched. The
  effective tier is the cheapest of the surviving proposals, and every clamp that
  bound is recorded in the ledger row — which is also what makes composition testable.
- **Fail closed.** An unreadable or unrecognized clamp input resolves in the spend-safe
  direction: escalation denied, downshift values applied, the degraded read recorded.
  While the usage signal is unavailable, escalation above the starting tier is denied;
  a unit already above it holds (no claw-back), per the upstream hold-then-decay
  posture.
- **Flap resistance.** All re-resolution happens only at launch boundaries; there is
  no mid-step oscillation surface.

**Alternatives considered:**
- Multi-tier jumps on severe events. Rejected because: one-step moves keep the ledger
  explanatory and the cost surface predictable; a severe event recurs and climbs
  again if genuinely needed.
- Time-based dwell hysteresis (mirroring the rung ladder). Rejected because: launch
  boundaries are already discrete and infrequent; a second dwell mechanism adds knobs
  without an observed flapping mode. Revisit only on drain-loop evidence of flapping.
- A single unified ordering for movement and comparison. Rejected because: the
  operator chose effort-first movement, and forcing comparisons onto the path order
  would misrank points the path skips.

**Chosen because:** bounded, explainable, and conservative in the spend direction under
uncertainty.

*(Amended at kickoff walkthrough 2026-08-25: joint ladder and step rule pinned.
Amended at kickoff lens pass 2026-08-25: restructured; per-class stacking with
idempotency keys, net-displacement cap, upstream-semantics clamp composition,
withheld outcome, and fail-closed inputs pinned.)*

### D-9: Denied or exhausted escalation folds into the existing failure machinery  (N)

**Decision:** When a unit keeps failing and cannot escalate — whether a clamp denied
the escalation, the adjustment cap is exhausted, or the unit sits at the ladder top —
the existing crash-loop backoff, disable threshold, and decision-queue escalation
govern unchanged. This spec adds no parallel "stuck because budget" mechanism; the
ledger (and the mirrored fleet-audit governance rows) record why escalation was
unavailable, which is what the human sees when the existing escalation fires.

**Alternatives considered:**
- A dedicated budget-blocked hold state. Rejected because: a second stuck-state
  machine to reconcile with liveness classification; the existing path already ends at
  a human with the audit trail explaining why.

**Chosen because:** existing-seam-reuse; fewer states, one escalation story.

*(Amended at kickoff lens pass 2026-08-25: cap-exhaustion and ladder-top stuck states
folded into the same path.)*

### D-10: Application follows the backend capability contract  (N)

**Decision:** The resolver only *chooses*; applying model/effort at launch belongs to
the dispatching backend per its advertised capability (CLI launch flags for session
backends, the subagent launch parameters for in-process agents). The backend
capability contract gains a model/effort-set capability column (a Task 6 deliverable —
the contract does not advertise it today). Capability is per dimension: a backend that
can set the model but not the effort applies the model and inherits ambient effort,
with the partial inheritance marked in the ledger row; a backend that can set neither
inherits both, marked likewise. A capability probe that errors is treated as
no-capability (inherit, audited). Resolved values reach a backend only as discrete,
quoted argv elements or launch parameters — never interpolated into a command string.
No backend is special-cased by name.

**Alternatives considered:**
- Refusing dispatch on backends that cannot apply the choice. Rejected because:
  turns a capability gap into an availability failure; inheritance-with-audit degrades
  gracefully, matching the established degradation posture.

**Chosen because:** consistent with the existing choose/apply split and the
capability-contract direction the dispatch layer already documents.

*(Amended at kickoff lens pass 2026-08-25: per-dimension capability, probe-error
handling, contract-column deliverable, and argv discipline pinned.)*

### D-11: Feedback via the standard observation ritual  (N)

**Decision:** A unit whose terminal state leaves it above its starting tier, or whose
escalation count reached the configured feedback threshold, records an observation
fragment through the shared recording helper — once per unit (the emission is
ledger-marked so re-derivation and sweeps cannot re-record it). Terminal states
include completion **and** crash-loop disable, so chronically failing units feed the
loop they most need to feed. The fragment names the task, spec, starting and final
tiers, and carries no petition text or worker-authored free prose (artifact
data-hygiene). A helper failure is surfaced, never silently dropped. No new
accumulator, no new reader: `/spec-draft`'s seed mining is the existing drain path by
which chronic under-estimation reaches future authoring — and supplies the graduation
evidence D-3 names.

**Alternatives considered:**
- Writing back into the task block or bundle. Rejected because: execution state never
  writes into v2 bundles, and a per-task annotation would be invisible to cross-spec
  pattern mining.
- No feedback. Rejected because: the operator chose the loop; without it the same
  under-estimates recur silently.

**Chosen because:** reuses the accumulator taxonomy end to end; zero new mechanism.

*(Amended at kickoff lens pass 2026-08-25: once-per-unit emission, terminal-state
definition, and fragment hygiene pinned.)*

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

### D-13: Fully opt-in application — shipped defaults change nothing  (N)

**Decision:** The capability ships dark. At the three surfaces that perform no
selection today (single-spec `/orchestrate` dispatch, `/execute-task` per-step
sessions, `/offload` dispatch) the shipped default for every selection knob is an
explicit `inherit` sentinel: the resolver is consulted (REQ-B1.1 holds), applies
nothing, and the ledger records the inheritance. Adaptation is gated behind a master
knob, `allocation_adaptation`, shipping `off`; with it off, fleet dispatch keeps
today's static table selection exactly. New ledger and audit rows accompany the
capability and are explicitly exempt from the behavior-preservation claim — they are
additive telemetry, not selection behavior. The equivalence tests pin the current
shipped table as a captured golden baseline, so "unchanged" is measured against a
fixture, not against the new implementation's own output.

**Alternatives considered:**
- Governed selection and adaptation on by default. Rejected because: an observable
  change for every operator on upgrade, contradicting the Goal's opt-in,
  default-preserving posture and REQ-A1.2's plain meaning.
- Applied static selection on, adaptation off. Rejected because: still a behavior
  change at three surfaces on upgrade; the halfway point buys little over the master
  knob being one flip away.

**Chosen because:** it is what the Goal's "opt-in, default-preserving" sentence
promises; REQ-A1.2 stays literally true at every surface.

## Cross-cutting concerns

- **Concurrency.** Ledger derive+append runs under one hold of the per-unit lock
  (D-6), so same-unit racing launches serialize and cross-unit work never contends.
  The sparse fleet-audit mirror rows use the shared trail's existing lock discipline
  at a low, event-only write rate. Petition consumption is race-free by the atomic
  rename-claim (D-7). Clamp inputs (rung, caps, signal) are global reads: two units
  resolving concurrently may both see headroom the pair jointly exceeds — accepted,
  because the caps are consumed as advisory bounds evaluated per resolution (their
  own upstream semantics), and the reactive throttle backstop remains the hard stop.
- **Security.** The petition artifact is screened per D-7 (grammar bounds, path
  posture, claim atomicity, sanitized echo, no interpolation — the security-posture
  write-time triggers apply to its parser). The ledger read path treats rows as data
  under the same posture: derivation parses the pinned schema only, skips-and-surfaces
  malformed rows via degraded mode (D-6), and never evaluates row content. Numeric
  knobs are validated against their pinned grammar before any arithmetic use (D-5).
  Ledger rows, mirror rows, and observation fragments carry no secrets and no
  worker-authored free prose beyond the sanitized one-line petition reason, which
  never propagates into committed artifacts (D-11).
- **Determinism floor.** Every decision path in this bundle is table lookup, config
  read, and ledger-record read — verifiable by the same test style the existing
  resolver uses.
- **Performance.** Derivation scans one unit's ledger (bounded by that unit's own
  history), holds only that unit's lock, and may memoize within a boundary (D-6).
  The shared trail receives only sparse governance events. Ledger size and derivation
  latency are surfaced through the stats path as the instrument behind the risk
  register's early signal.
