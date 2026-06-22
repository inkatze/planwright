# Orchestration Fleet — Test Spec

**Status:** Draft
**Last reviewed:** 2026-06-18
**Format-version:** 1

Coverage mix: the fleet layer is skills + portable scripts over backends, so the
mix leans `[design-level]` and `[manual]`/`[Gherkin]` for skill-orchestrated
behavior (backend selection flow, meta-orchestration, relay discipline,
approachable presentation), with `[test]` where a unit is genuinely
script-testable (autodetection reporting, fleet-state resolution, the
synchronous-fallback single-stream run, the `dispatch_isolation` resolution
half, options-reference coverage). Several behavioral entries name a `[manual]`
whole-system exercise because the assembled fleet behavior changes when towers,
workers, and backends are chained — a fragment test cannot stand in. Every REQ
is pinned to at least one path below.

## REQ-A — Foundation, dependency contract & carried invariants

### REQ-A1.1 — Build on the sibling state-safety contract [design-level]

Design-level audit: every fleet write of `tasks.md` state routes through the
`orchestration-concurrency` single-writer contract; no fleet requirement or task
re-specifies a sibling state-safety internal. Verified by tracing each
state-writing path (auto-heal, per-step sessions, meta-tower moves) to the
sibling's writer, recorded in the kickoff verification approach.

### REQ-A1.2 — Never-auto-merge at every tier [design-level + manual]

Design-level: no fleet code path invokes a merge; the meta-tower and every
backend create draft PRs only. Manual: an unattended fleet run is observed to
stop at draft-PR-ready and never merge, at both the single-tower and meta-tower
tiers.

### REQ-A1.3 — No parallel autonomy taxonomy [design-level]

Design-level audit of the Task 8 policy: every may-decide / must-escalate item
cites an existing finding-categorization bucket or hard-pause zone; no
free-standing fleet-only decision category is introduced.

### REQ-A1.4 — Proportionate, opt-in machinery [test + manual]

Test: with no rich backend configured or detected, a single spec's units execute
via the synchronous fallback (REQ-B1.4 path) with no tmux/multiplexer present.
Manual: ordinary single-spec execution is exercised with none of the rich-backend
/ meta-orchestration capabilities engaged.

### REQ-A1.5 — Capability-vs-style split for every knob [design-level]

Design-level: each fleet knob (`dispatch_backend`, `dispatch_isolation`, the
context-budget threshold, the fleet concurrency bound) lands in core as an
opt-in, default-preserving option resolved through the four overlay layers, with
its specific value documented as overlay-owned. Audited against
`customization-boundary` at kickoff.

### REQ-A1.6 — Data hygiene in fleet artifacts [manual + design-level]

Manual: a reviewer confirms no coordination/relay log, persisted status-surface
state, handover doc, or PR body carries secret-shaped content, internal
hostnames, or sensitive operational detail. Design-level: the data-hygiene rule
is stated for fleet artifacts and the secret-scan guard covers committed ones.

## REQ-B — Pluggable & autodetected execution backend

### REQ-B1.1 — Backend capability contract defined [design-level]

The contract doc exists, names all four capabilities (named/addressable units,
attributed relay, positive-evidence-of-death liveness, spawn) with an evaluable
definition of each, and maps every existing backend to the capabilities it
provides and lacks. Existence-plus-coverage is the verification.

### REQ-B1.2 — Extends `dispatch_backend`, maps existing backends [design-level]

Design-level: the contract is an extension of the existing `dispatch_backend`
config (not a replacement), and each of `subagent`, `tmux`, `print`,
`in-session` is mapped to the contract's capabilities including its gaps.

### REQ-B1.3 — Pluggable backend path [design-level + Gherkin]

Design-level: a new terminal/multiplexer becomes a backend by implementing the
contract and is selected through config, with no edit to the consuming skills.
Gherkin: given a config naming a contract-implementing backend, when
`/orchestrate` dispatches, then it uses that backend through the same code path
the built-in backends use.

### REQ-B1.4 — Synchronous fallback [test]

With no rich backend available or selected, a spec's ready units run one at a
time in the dispatching session with a context clear between units; a test
asserts the single-stream ordering and the bounded-context clears, and that the
state-safety contract and never-auto-merge hold on this path.

### REQ-B1.5 — Autodetect, present, ask — never silent [test + Gherkin]

Test: autodetection reports exactly the backends present on the host fixture.
Gherkin: given multiple backends detected, when `/orchestrate` runs attended,
then it presents the set and asks (no silent pick); and given unattended mode
with no configured rich backend, then selection degrades to the synchronous
fallback, never to a silently-chosen interactive backend.

### REQ-B1.6 — Relay/spawn security bounds [test + manual]

Test: worker handles parsed for targeting are validated before use and hostile
handles are rejected; worker output is treated as data (no `eval`/expansion
path). Manual: no `send-keys`-style impersonation path exists and the tower never
auto-answers a worker permission prompt — confirmed by code audit and a manual
relay exercise.

## REQ-C — Orchestrator self-management

### REQ-C1.1 — Context-budget monitoring [design-level + manual]

Design-level: a tower monitors its context budget against a configurable
threshold and surfaces a near-limit condition. Manual: a tower driven toward the
threshold is observed to surface the near-limit condition rather than silently
degrade.

### REQ-C1.2 — Auto-heal disposable handover [manual + Gherkin]

Gherkin: given a tower at its context limit, when auto-heal fires, then a fresh
tower is launched that rebuilds the in-flight picture from `tasks.md` + `gh` +
the worker list with no in-memory state passed, using the wake prompt as the
handover document, and the retiring tower stops. Manual: the handover is
exercised end-to-end and the fresh tower continues the work correctly.

### REQ-C1.3 — `dispatch_isolation` per-step [test + design-level + manual]

Test: `dispatch_isolation` resolves through all four overlay layers; the default
is `per-step`. Design-level: under `per-step` the `/execute-task` convergence
path runs implementation and each `review_sequence` skill in distinct fresh
`/resume`-seeded sessions; under `per-unit` today's single-session behavior
holds. Manual: a per-step run is observed to seed each step's session fresh.

### REQ-C1.4 — Self-management preserves state-safety [design-level]

Design-level audit: the auto-heal handover and every per-step session write
`tasks.md` state only through the sibling's merge-safe writer and the advisory
lock — never by a bypassing path.

## REQ-D — Meta-orchestration, coordination & autonomy

### REQ-D1.1 — Meta-orchestration across active specs [manual + Gherkin]

Gherkin: given two or more active specs with ready units, when the meta-tower
runs, then it launches subordinate single-spec towers that drain their specs
concurrently within the fleet concurrency bound, each subordinate an independent
disposable step machine. Manual: a two-spec meta-run is exercised and observed to
progress both specs without cross-spec state leakage.

### REQ-D1.2 — Division of labor [design-level]

Design-level: the protocol assigns `tasks.md` state moves / dispatch / merged-
worker cleanup to the tower and branch conflict resolution / post-merge self-sync
to the owning worker; an audit confirms no path has one tower edit another
tower's or a worker's branch state directly.

### REQ-D1.3 — Attributed, non-impersonating relay [manual + design-level]

Design-level: relay uses the buffer-paste mechanism and capture-pane/equivalent
status reads, with no `send-keys` impersonation and no auto-answering of worker
permission prompts. Manual: a relay exercise confirms messages arrive attributed
and the worker's input line is never driven by the tower.

### REQ-D1.4 — Autonomous-safe-decision policy [design-level]

Design-level: the policy enumerates the may-decide-unattended set (act-then-
review buckets + routine hygiene) and the must-escalate set (hard-pause zones +
irreducible Needs-human-judgment forks), each item mapped to the existing gate;
existence-plus-coverage against `finding-categorization` is the verification.

### REQ-D1.5 — Multi-spec reach + fleet bound [test + manual]

Test: the meta-tower's selection considers ready units across the supervised
active specs, and the fleet concurrency bound (resolved through the overlay
layers, distinct from per-spec `max_parallel_units`) caps total concurrent units.
Manual: a multi-spec run respects both each spec's per-spec lock and the fleet
bound.

## REQ-E — Approachability

### REQ-E1.1 — One obvious entry command [manual + design-level]

Design-level: a single documented entry command selects a backend (autodetect-
and-ask) and starts the tower(s). Manual: an operator who does not use tmux
starts fleet operation with the one command and no multiplexer knowledge.

### REQ-E1.2 — Visible status surface [test + manual]

Test: the status surface, reading the fleet-state registry, lists each worker
with its scope (spec + unit) and state (working / awaiting input / PR-ready /
merged). Manual: the surface is read from a normal terminal/editor without
attaching to a multiplexer.

### REQ-E1.3 — Per-worker scope legible [design-level + manual]

Design-level: the surface presents each worker's isolated scope (one spec/unit,
isolated context). Manual: a non-tmux operator can tell, from the surface, what
each worker is doing and in what scope.

### REQ-E1.4 — Approachable path is the default [design-level]

Design-level: the editor/terminal-with-CLI-or-API presentation is the default
surface (the backend seam surfaced as UX), not a degraded fallback gated behind
the tmux path; audited against the entry-command and status-surface deliverables.
