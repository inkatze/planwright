# Model Allocation — Test Spec

**Status:** Draft
**Last reviewed:** 2026-08-24
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the resolver, adaptation, clamp, petition, and feedback logic are
deterministic shell scripts and verify as `[test]` shell suites under `tests/`, run by
`mise run test` in this repo's CI workflows. Consumed-contract and
documented-degradation requirements verify as `[design-level]`; skill-prose wiring that
no script exercises end to end carries a `[manual]` component.

## REQ-A — Selection policy

### REQ-A1.1 — single deterministic resolver [test]

Resolver tests assert pure table/config/event-record resolution: identical inputs yield
identical output across repeated invocations, and the implementation review confirms no
LLM invocation or network call exists on the resolution path (asserted the same way the
existing selection-table tests pin determinism).

### REQ-A1.2 — defaults preserve behavior [test]

With an empty config, the resolver's output for every existing task type equals the
current shipped table row, at every wired surface's invocation path (fixture-driven);
Task 6's per-surface tests re-assert defaults-only equivalence.

### REQ-A1.3 — general family with legacy fallback [test]

Fixtures set `allocation_*` only, `fleet_*` only, both, and neither: the general knob
wins when set, the legacy knob is used when the general one is unset, and shipped
defaults apply when neither is set. Docs mark `fleet_*` deprecated (checked by the
options-reference/doc entries of Task 1).

### REQ-A1.4 — enum and malformed-value policy [test]

Out-of-enum model and effort values, and malformed values at each overlay layer,
follow the by-layer policy exactly as the existing resolver tests specify (reused
fixture style).

## REQ-B — Launch-point coverage

### REQ-B1.1 — every launch point resolves through the policy [test + manual]

Scriptable surfaces (fleet dispatch, single-spec dispatch selection, offload's
dispatch step) assert the resolver invocation in tests; skill-prose launch paths that
only an interactive session exercises are verified by a recorded manual pass at Task 6
review.

### REQ-B1.2 — capability-aware application, audited inheritance [test]

A fixture backend advertising no model-set capability yields a launch without model
flags plus an inheritance audit row; a capable fixture yields the flagged launch. No
silent ambient launch exists in any branch of the dispatch tests.

### REQ-B1.3 — in-session inheritance documented [design-level]

The in-session rung's documentation states the inheritance degradation; verified by
the Task 6/7 doc deliverables existing and the doc-link check passing.

## REQ-C — Execution-time adaptation

### REQ-C1.1 — launch-boundary-only, audit-derived, memoryless [test]

Derivation tests replay a fixture audit trail: repeated derivation is stable, no state
survives outside the records, and no code path adjusts tier except at a launch
boundary resolution.

### REQ-C1.2 — event-triggered escalation, bounded [test]

Each trigger event fixture (failure/retry, flailing, non-convergence, escalate
petition) climbs exactly one tier; a burst of events cannot exceed the per-unit cap;
no confidence-shaped input exists in the trigger grammar.

### REQ-C1.3 — de-escalation paths [test]

A de-escalate petition and a cheaper configured step-type each lower the next launch's
tier; no other fixture lowers it.

### REQ-C1.4 — clamps always win [test]

For each clamp (rung, per-tier cap, downshift values), a proposal above the clamp
resolves to the clamped tier with a clamped audit row; a petition fixture attempting
to exceed a clamp is bounded identically.

### REQ-C1.5 — denied escalation folds into crash-loop machinery [test]

A fixture with denied escalation and repeated failures reaches the existing disable
threshold and decision-queue escalation with no new hold state introduced; the audit
trail carries the denial records the human sees.

### REQ-C1.6 — petition screening [test]

Hostile petition fixtures (oversize, out-of-grammar, control bytes, path tricks) are
ignored with an audit row, produce sanitized output only, and are never interpolated
(assertion style follows the existing echo-safety tests).

## REQ-D — Budget integration

### REQ-D1.1 — contracts consumed unmodified [design-level]

The bundle and implementation touch no upstream threshold, cadence, or semantic:
verified at review by the absence of edits to the consumed scripts' contracts and by
this spec's Out-of-scope statement; the integration tests read rung/cap fixtures
through the upstream scripts' documented interfaces only.

### REQ-D1.2 — unavailable signal denies escalation [test]

An unavailable-signal fixture denies escalation above the starting tier while leaving
starting-tier selection and upstream hold/decay behavior untouched.

## REQ-E — Configurability

### REQ-E1.1 — every policy value overlay-configurable [test]

Each introduced knob is exercised through the overlay layers by the shared-resolver
fixture pattern; defaults preserve shipped behavior (joint coverage with REQ-A1.2).

### REQ-E1.2 — options-reference rows [test]

`check-options-reference` passes with every introduced knob present; the guard run in
CI is the enforcement.

## REQ-F — Observability and feedback

### REQ-F1.1 — structured audit records [test]

Every resolution/adjustment path in the adaptation tests asserts an appended audit row
carrying unit, step, chosen model/effort, and inputs (trigger, rung, clamps, fallback
or inheritance), including the ignore and denial cases.

### REQ-F1.2 — feedback observation on threshold [test]

A fixture unit ending above its starting tier (and one reaching the escalation-count
threshold) produces a grammar-valid observation fragment via the shared helper; a unit
below both thresholds produces none.
