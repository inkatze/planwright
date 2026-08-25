# Model Allocation — Test Spec

**Status:** Ready
**Last reviewed:** 2026-08-25
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the resolver, adaptation, clamp, petition, and feedback logic are
deterministic shell scripts and verify as `[test]` shell suites under `tests/`, run by
`mise run test` in this repo's CI workflows. Consumed-contract and
documented-degradation requirements verify as `[design-level]`; skill-prose wiring that
no script exercises end to end carries a `[manual]` component; mixed cases carry a
compound tag (e.g. `[test + manual]`) per the spec-format convention. Where an entry
defers to an existing suite it names the file, so upstream drift is visible.

## REQ-A — Selection policy

### REQ-A1.1 — single deterministic resolver [test + design-level]

Resolver tests assert pure table/config/ledger-record resolution: identical inputs
yield identical output across repeated invocations (the determinism style of
`tests/test-fleet-resource-select.sh`). The no-LLM/no-network property is verified
`[design-level]` by a structural guard over the resolver's call surface (no network
or model-invoking command appears in its script), not by reviewer attention alone.

### REQ-A1.2 — defaults preserve behavior [test]

With an empty config, the resolver's output for every existing task type equals a
**captured golden-baseline fixture** of the current shipped table (recorded before the
generalization, so the test never compares the implementation to itself), at every
wired surface's invocation path; Task 6's per-surface tests re-assert defaults-only
equivalence, and Task 2's master-knob-off fixture pins that adaptation ships inert.

### REQ-A1.3 — general family with legacy fallback and inherit sentinel [test]

Fixtures set `allocation_*` only, `fleet_*` only, both, and neither, for all three
columns: the general knob wins when set, the legacy knob is used when the general one
is unset, and shipped defaults apply when neither is set; the `inherit` sentinel at a
non-fleet surface resolves to inheritance with a ledger row. Docs mark `fleet_*` as
the deprecated fallback (checked by the options-reference/doc entries of Task 1); the
fallback's continued resolution is itself a pinned fixture, so removing `fleet_*`
resolution fails a test rather than only a doc check.

### REQ-A1.4 — enum, numeric grammar, and malformed-value policy [test]

Out-of-enum model, effort, and command values, malformed numeric knob values
(rejected before arithmetic), and malformed values at each overlay layer follow the
by-layer policy exactly as the existing resolver tests
(`tests/test-fleet-resource-select.sh`, fixture style reused) specify; the command
enum's closed set is asserted so review-sequence disjointness keeps its carrier.

## REQ-B — Launch-point coverage

### REQ-B1.1 — every launch point resolves through the policy [test + manual]

Scriptable surfaces (fleet dispatch, single-spec dispatch selection, offload's
dispatch step) assert the resolver invocation in tests; the `[manual]` remainder is
enumerated by name in Task 6 (skill-prose launch paths that only an interactive
session exercises) and verified by a recorded manual pass at Task 6 review — an
unenumerated surface cannot be silently reclassified as manual.

### REQ-B1.2 — capability-aware application, audited inheritance [test]

The fixture-backend set is pinned: a fully capable backend (flagged launch), a
no-capability backend (full inheritance plus ledger row), a partially capable backend
(model set, effort inherited, partial-inheritance row), and an errored capability
probe (treated as no-capability, audited). Each branch asserts its ledger row, so an
un-audited ambient launch fails a named fixture rather than a universal claim.
Resolved values are asserted to reach the launch as discrete argv elements.

### REQ-B1.3 — in-session inheritance documented [design-level]

The in-session work-placement rung's documentation states the inheritance
degradation; verified by a content check that the Task 7 doc states it (not existence
alone) plus the doc-link check passing.

## REQ-C — Execution-time adaptation

### REQ-C1.1 — launch-boundary-only, ledger-derived, memoryless [test]

Derivation tests replay a fixture ledger: repeated derivation is stable given the
same records and config; a zero-history unit derives its starting tier; a config
change between launches changes the derivation (records-plus-config is the pinned
input set). The boundary-only property is verified by a structural guard: the tier
write path exists only in the launch-boundary resolver, asserted over the shipped
scripts.

### REQ-C1.2 — event-triggered escalation, keyed, class-stacked, capped [test]

Each trigger-event class fixture (failure/retry, flailing, non-convergence, escalate
petition) climbs exactly one ladder step along the successor rule, with the hinge
pinned: an effort bump within a model, and a model bump at `high` that keeps effort
`high` (not the next model's configured or lowest effort). N distinct classes at one
boundary climb N steps and append N ledger rows (the counts asserted); same-incident
classes (a failure and its retry) collapse to one step via their idempotency keys; a
crash-replay fixture re-derives without double-counting. A burst cannot exceed the
per-unit adjustment cap; a fixture already at the ladder top no-ops with a ledger
row; an infrastructure-failure fixture (audit write error, config hard-fail) triggers
no escalation. The trigger grammar is a closed allowlist (asserted as a set), which
is what keeps confidence-shaped inputs out.

### REQ-C1.3 — de-escalation paths [test]

A de-escalate petition reverses the most recent unreversed escalation step (a
two-step escalated fixture un-bumps the model before the effort — the ordering
asserted); a never-escalated fixture steps below its starting tier by the D-8 mirror
rule with its hinge pinned (effort to `low`, then model at `low`), down to the ladder
floor where a further petition no-ops with a ledger row; a below-starting unit
re-escalates on a failure event (the safety-valve fixture). A weighed petition is
consumed — the artifact is gone and it does not re-apply at the following boundary. A
cheaper configured step-type tier applies at that step's launch only (scope-marked;
the unit's derived tier after the step equals its pre-step tier — the restore-after
fixture), and it may jump multiple cost-order positions; an equal-or-more-expensive
step-type fixture is ignored with a ledger row. The "cheaper than" comparator is
exercised directly on cross-ordering pairs (e.g. `(sonnet, high)` vs `(opus, low)`).
No other fixture lowers the tier.

### REQ-C1.4 — clamps compose per upstream semantics [test]

Each clamp is tested per its own conditionality: downshift binds at the `downshift`
rung and not at `normal`; caps bind while the signal is available and are inactive
when it is not; a defer-rung fixture yields a withheld unit, never a tier; a
reserved-unit fixture passes through exempt. Composition fixtures set two or three
clamps in conflict and assert the cheapest survivor wins with every binding clamp
recorded in the ledger row; a cap-clamp fixture asserts nearest-surviving-model with
effort preserved. An unreadable clamp-input fixture fails closed (escalation denied,
downshift values applied, degraded read recorded). A petition fixture attempting to
exceed a clamp is bounded identically.

### REQ-C1.5 — stuck states fold into crash-loop machinery [test]

Fixtures for each cannot-escalate door — clamp denial, exhausted adjustment cap, and
ladder top — with repeated failures reach the existing disable threshold and
decision-queue escalation (the existing crash-loop suite's thresholds, exercised
through its own interface); the ledger carries the denial/no-op records the human
sees. The no-new-hold-state property is design-level: the bundle introduces no state
machine, verified at review.

### REQ-C1.6 — petition screening [test]

Hostile petition fixtures — oversize, out-of-grammar, control bytes, path tricks, a
symlink at the pinned path, a non-regular file (FIFO), a stale petition bound to a
previous task or step, and a torn (mid-write) read — are each consumed and ignored
with a ledger row, produce sanitized output only, and are never interpolated
(assertion style follows `tests/test-echo-safety.sh`). A claim-race fixture with two
concurrent consumers moves the tier at most one step. The unit/step binding is
asserted positively (a matching petition is weighed) and negatively (a mismatch is
ignored).

### REQ-C1.7 — single consumption [test]

A weighed valid petition's artifact is removed and a re-armed identical petition is a
fresh signal (one step each); a crash between the atomic claim and the ledger row
reconciles as ignored-with-audit at the next boundary; an invalid petition is also
removed, so no fixture re-audits the same artifact twice. The no-worktree degradation
is `[design-level]`: the in-session rung's documentation states the absent channel.

## REQ-D — Budget integration

### REQ-D1.1 — contracts consumed unmodified [test + design-level]

The bundle and implementation touch no upstream threshold, cadence, or semantic:
verified at review by the absence of edits to the consumed scripts' contracts, and
mechanically by an untouched-interface guard that fails when this spec's changes edit
the consumed fleet-autonomy scripts (the tripwire behind risk row 4's early signal);
the integration tests read rung/cap fixtures through the upstream scripts' documented
interfaces only.

### REQ-D1.2 — unavailable signal denies escalation, holds altitude [test]

An unavailable-signal fixture denies escalation above the starting tier; an
already-escalated unit holds its tier (no claw-back) and a below-starting unit may
still climb back to its starting tier; a signal reader that errors or returns
garbage is treated as unavailable (its own fixture). Upstream hold/decay behavior is
exercised only through the upstream interface, against the same golden expectations
its own suite pins.

## REQ-E — Configurability

### REQ-E1.1 — every policy value overlay-configurable [test]

Each named knob — the adaptation master knob, starting tiers (three columns),
step-type tiers, the adjustment cap, the petition policy (all four enum states), and
the feedback threshold (default and non-default values) — is exercised through the
overlay layers by the shared-resolver fixture pattern; defaults preserve shipped
behavior (joint coverage with REQ-A1.2's golden baseline).

### REQ-E1.2 — options-reference rows [test]

`check-options-reference` passes with every introduced knob present; the guard run in
CI is the enforcement.

## REQ-F — Observability and feedback

### REQ-F1.1 — structured ledger records and sparse mirror [test]

Every resolution/adjustment path in the adaptation tests asserts an appended ledger
row carrying the pinned schema fields, including the ignore, denial, no-op, clamped,
scope-marked, and inheritance cases; stacked events assert one row per step; a
governance event (escalation, denial, clamp binding, inheritance) asserts its mirror
row in fleet-audit while a routine resolution asserts none; a failed ledger append
asserts degraded mode (launch at last recorded tier, adjustments suspended, the
failure surfaced non-zero — the negative fixture behind "never silent").

### REQ-F1.2 — feedback observation on threshold [test]

A fixture unit ending above its starting tier, one reaching the escalation-count
threshold (at default and at a non-default configured value), and a crash-loop
disabled fixture each produce exactly one grammar-valid observation fragment via the
shared helper; a unit below both thresholds, and a unit that escalated then reverted
to its starting tier, produce none; re-evaluation after the ledger mark does not
re-record; a helper failure surfaces non-zero; the fragment carries the named fields
and no petition text.

### REQ-F1.3 — ledger instrumentation [test]

The stats path surfaces ledger size and derivation latency for a fixture ledger; a
scale fixture (a long multi-day unit history) bounds derivation within the pinned
budget, so a scan-cost regression fails a test rather than surfacing in operation.
