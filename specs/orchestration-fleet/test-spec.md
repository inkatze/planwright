# Orchestration Fleet — Test Spec

**Status:** Ready
**Last reviewed:** 2026-06-29
**Format-version:** 1

Coverage mix: the fleet layer is skills + portable scripts over backends, so the
mix leans `[design-level]` and `[manual]`/`[Gherkin]` for skill-orchestrated
behavior (backend selection flow, capability advertisement, the degradation
ladder, meta-orchestration, relay discipline, the decision queue), with `[test]`
where a unit is genuinely script-testable (autodetection reporting, advertisement
parsing, the synchronous terminal rung's single-stream run, runtime-failover
descent and the spec-local effective-backend record, the `dispatch_isolation`
resolution half, the cross-spec fleet-state resolution, the status renderer /
decision-queue ordering, options-reference coverage). Several behavioral entries
name a `[manual]` whole-system exercise because the assembled fleet behavior
changes when towers, workers, and backends are chained — a fragment test cannot
stand in. Every REQ is pinned to at least one path below.

## REQ-A — Foundation, dependency contract & carried invariants

### REQ-A1.1 — Consume the sibling derived-projection contract [design-level]

Design-level audit: every fleet write of `tasks.md` state routes through the
sibling's level-triggered reconcile, and no fleet path commits dispatch/progress
state to `tasks.md`; the task branch + per-spec advisory lock + `Planwright-Task`
trailer + runtime marker are the dispatch record. Verified by tracing each
state-writing path (auto-heal, per-step sessions, meta-tower moves) to the
sibling's `orchestrate-state.sh` reconcile and `orchestrate-lock.sh`, recorded in
the kickoff verification approach. No fleet requirement re-specifies a sibling
state-safety internal.

### REQ-A1.2 — Never-auto-merge at every tier [design-level + manual]

Design-level: no fleet code path invokes a merge; the meta-tower and every ladder
rung create draft PRs only. Manual: an unattended fleet run is observed to stop at
draft-PR-ready and never merge, at both the single-tower and meta-tower tiers.

### REQ-A1.3 — No parallel autonomy taxonomy [design-level]

Design-level audit of the Task 8 policy: every may-decide / must-escalate item
cites an existing finding-categorization bucket or hard-pause zone; no
free-standing fleet-only decision category is introduced.

### REQ-A1.4 — Proportionate, opt-in machinery [test + manual]

Test: with no rich backend configured or detected, a single spec's units execute
via the synchronous terminal rung (REQ-B1.5 path) with no tmux/multiplexer
present. Manual: ordinary single-spec execution is exercised with none of the
rich-backend / meta-orchestration capabilities engaged.

### REQ-A1.5 — Capability-vs-style split for every knob [design-level]

Design-level: each fleet knob (`dispatch_backend`, `dispatch_isolation`, the
context-budget threshold, the fleet concurrency bound, the notification channel)
lands in core as an opt-in, default-preserving option resolved through the four
overlay layers, with its specific value documented as overlay-owned. Audited
against `customization-boundary` at kickoff.

### REQ-A1.6 — Data hygiene in fleet artifacts [manual + design-level]

Manual: a reviewer confirms no coordination/relay log, persisted status/queue
state, the worker/scope registry, the effective-backend failover record, a
handover doc, or a PR body carries secret-shaped content, internal hostnames, or
sensitive operational detail. Design-level: the data-hygiene rule is stated for
fleet artifacts and the secret-scan guard covers committed ones.

## REQ-B — Pluggable & autodetected execution backend

### REQ-B1.1 — Backend capability contract defined [design-level]

The contract doc exists and names each capability — named/addressable units,
observe-in-flight, steer-in-flight, positive-evidence-of-death liveness, and
session-grade spawn — with an evaluable definition of each; observe and steer are
first-class (not folded into a generic relay) and spawn is defined as
session-grade. Existence-plus-coverage is the verification.

### REQ-B1.2 — Capability advertisement & adaptation [test + design-level]

Test: a backend's advertised capability set (`{ interactive, can_observe,
can_steer_inflight, provides_attention_surface, supports_parallel }`) parses, and
the orchestrator's adaptation is exercised — `can_steer_inflight: false` routes
ambiguity to the decision queue; `provides_attention_surface: true` suppresses
planwright's own queue rendering. Design-level: the orchestrator adapts to the
advertised set rather than special-casing backends by name.

### REQ-B1.3 — Extends `dispatch_backend`; pluggable backend path [design-level + Gherkin]

Design-level: the contract extends the existing `dispatch_backend` config (not a
replacement); each of `subagent`, `tmux`, `print`, `in-session` is mapped to its
advertised capability set including gaps; a new terminal/multiplexer becomes a
backend by implementing/advertising the contract, selected through config with no
edit to the consuming skills. Gherkin: given a config naming a
contract-advertising backend, when `/orchestrate` dispatches, then it uses that
backend through the same code path the built-in backends use.

### REQ-B1.4 — Autodetect, present, ask — never silent [test + Gherkin]

Test: autodetection reports exactly the backends present on the host fixture with
their advertised capabilities. Gherkin: given multiple backends detected, when
`/orchestrate` runs attended, then it presents the set and asks (no silent pick);
and given unattended mode with no configured rich backend, then selection degrades
down the ladder, never to a silently-chosen interactive backend.

### REQ-B1.5 — Degradation ladder & runtime failover [test + manual]

Test: with no rich backend, ready units run on the synchronous terminal rung one
at a time with bounded-context clears; a simulated mid-run backend death triggers
a one-rung descent with a logged note + `## Awaiting input` entry (never silent);
a descent that would drop a named guard (worker-settings deny, never-auto-merge,
never-force-push, the freshness gate) is refused. Manual: the ladder is exercised
end-to-end across at least two rungs and the degrade-capability-never-safety floor
is observed to hold.

### REQ-B1.6 — Spec-local effective-backend failover record [test]

Test: after a runtime failover the effective backend is recorded spec-locally in
`<spec-dir>/.orchestrate/` alongside the dispatch marker (not in `tasks.md`), the
record is readable by a reconcile sweep, and a fleet path is asserted never to
write into `tasks.md` for this purpose.

### REQ-B1.7 — Relay/spawn security bounds [test + manual]

Test: worker handles parsed for targeting are validated before use and hostile
handles are rejected; worker output is treated as data (no `eval`/expansion path).
Manual: no `send-keys`-style impersonation path exists and the tower never
auto-answers a worker permission prompt — confirmed by code audit and a manual
observe/steer exercise against a running worker.

## REQ-C — Orchestrator self-management

### REQ-C1.1 — Context-budget monitoring [design-level + manual]

Design-level: a tower monitors its context budget against a configurable
threshold and surfaces a near-limit condition. Manual: a tower driven toward the
threshold is observed to surface the near-limit condition rather than silently
degrade.

### REQ-C1.2 — Auto-heal disposable handover (`continue-as-new`) [manual + Gherkin]

Gherkin: given a tower at its context limit, when auto-heal fires, then a fresh
tower is launched that rebuilds the in-flight picture from the `tasks.md` snapshot
+ `gh` + the branch/marker/worker list with no in-memory state passed, using the
wake prompt as the handover document, and the retiring tower stops. Manual: the
handover is exercised end-to-end and the fresh tower continues the work correctly
(the "could a fresh tower resume from this alone?" check).

### REQ-C1.3 — `dispatch_isolation` per-step [test + design-level + manual]

Test: `dispatch_isolation` resolves through all four overlay layers; the default
is `per-step`. Design-level: under `per-step` the `/execute-task` convergence path
runs implementation and each configured `review_sequence` skill in distinct fresh
`/resume`-seeded sessions; under `per-unit` today's single-session behavior holds.
Manual: a per-step run is observed to seed each step's session fresh.

### REQ-C1.4 — Self-management preserves state-safety [design-level]

Design-level audit: the auto-heal handover and every per-step session drive
`tasks.md` placement only through the sibling's level-triggered reconcile and
acquire the per-spec advisory lock for any state move — never writing
dispatch/progress state to `tasks.md` by a bypassing path.

## REQ-D — Meta-orchestration, coordination & autonomy

### REQ-D1.1 — Meta-orchestration across active specs [manual + Gherkin]

Gherkin: given two or more active specs with ready units, when the meta-tower
runs, then it launches subordinate single-spec towers that drain their specs
concurrently within the fleet concurrency bound, each subordinate an independent
disposable step machine. Manual: a two-spec meta-run is exercised and observed to
progress both specs without cross-spec state leakage.

### REQ-D1.2 — Division of labor [design-level]

Design-level: the protocol assigns `tasks.md` reconcile / dispatch / merged-worker
cleanup to the tower and branch conflict resolution / post-merge self-sync to the
owning worker; an audit confirms no path has one tower edit another tower's or a
worker's branch state directly.

### REQ-D1.3 — Attributed, non-impersonating relay against a live worker [manual + design-level]

Design-level: relay uses the buffer-paste / steer-in-flight mechanism and
capture-pane / observe-in-flight status reads, with no `send-keys` impersonation
and no auto-answering of worker permission prompts. Manual: a relay exercise
against a running, busy worker confirms messages arrive attributed and the
worker's input line is never driven by the tower.

### REQ-D1.4 — Autonomous-safe-decision policy [design-level]

Design-level: the policy enumerates the may-decide-unattended set (act-then-review
buckets + routine hygiene) and the must-escalate set (hard-pause zones +
irreducible Needs-human-judgment forks), each item mapped to the existing gate and
escalations routed to the decision queue; existence-plus-coverage against
`finding-categorization` is the verification.

### REQ-D1.5 — Multi-spec reach + fleet bound [test + manual]

Test: the meta-tower's selection considers ready units across the supervised
active specs (reading each spec's live derivation, not the committed snapshot),
and the fleet concurrency bound (resolved through the overlay layers, distinct
from per-spec `max_parallel_units`) caps total concurrent units. Manual: a
multi-spec run respects both each spec's per-spec lock and the fleet bound.

### REQ-D1.6 — Cross-spec fleet-state home [test]

Test: the cross-spec fleet-coordination root resolves in both delivery modes
(plugin and writer) through the `${CLAUDE_PLUGIN_DATA}` chain and survives a
simulated plugin-version change; distinct plugin namespaces resolve to distinct
roots; the worker/scope registry round-trips a record; the named cross-spec
concurrency-control primitive serializes concurrent registry writes and the
fleet-bound check-and-increment so two simulated concurrent towers produce no
torn record and no over-count past the bound; no fleet path writes into the
sibling's spec-local `.orchestrate/` dir; hostile identifiers are rejected before
any path use.

## REQ-E — Approachability

### REQ-E1.1 — Two separable seams [design-level + manual]

Design-level: the execution substrate and the attention surface are decoupled —
the capability contract drives execution, the decision queue is the attention
surface, and the two do not trade off. Manual: a multiplexer is run as a detached
background server nobody attaches to, and full execution quality (session-grade,
steerable workers) is observed with the human seeing only the attention surface.

### REQ-E1.2 — One obvious entry command [manual + design-level]

Design-level: a single documented entry command autodetects/selects a backend and
starts the tower(s), rendering the decision queue. Manual: an operator who does
not use tmux starts fleet operation with the one command and no multiplexer
knowledge.

### REQ-E1.3 — Decision queue as the default surface [test + manual]

Test: the decision queue, reading the fleet-state registry, orders actionable
items across active specs as structured choices (spec/task, question, recommended
default, options), and its length tracks the `## Awaiting input` count, not the
worker count; non-actionable signal is suppressed. Manual: the queue is read from
a normal terminal/editor without attaching to a multiplexer and renders the same
across a plain session and a detached-multiplexer popup.

### REQ-E1.4 — Attention/notification capability in core [test + design-level]

Test: heartbeat/registry state lives under the cross-spec fleet-state home and the
capability functions with no dotfiles-local mechanism present (a
marketplace-install user gets it from core); the notification-channel knob
resolves as an overlay value through the four layers and has an options-reference
row. Design-level: the portable status renderer reads the registry and the
capability parallels the execution capability.

### REQ-E1.5 — Per-worker scope legible & default [design-level + manual]

Design-level: the surface presents each worker's isolated scope (one spec/unit,
isolated context) and the approachable path is the default presentation (the
backend seam surfaced as UX), not a degraded fallback gated behind tmux. Manual: a
non-tmux operator can tell, from the surface, what each worker is doing and in
what scope.

### REQ-E1.6 — Persona × seam mapping [design-level]

Design-level: the documented persona → (execution backend × attention surface)
mapping covers the three target operators (multiplexer users; non-terminal users
with the multiplexer as background plumbing + the decision queue; editor-feedback
users), and audits that all durable fleet state is files so an editor surface is a
renderer, not a new execution model.
