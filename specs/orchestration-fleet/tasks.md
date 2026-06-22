# Orchestration Fleet — Tasks

**Status:** Draft
**Last reviewed:** 2026-06-18
**Format-version:** 1

Dependency view (derived; the `Dependencies:` lines are authoritative). Task 1
(the backend capability contract) is the foundational seam almost everything
else builds on. Task 8 (the autonomous-safe-decision policy) is a safety
artifact that gates the unattended meta-tower, so it carries an explicit edge
from Task 6. The four facets sit on the foundation:

- **Foundation:** T1 (contract); T8 (autonomy policy) and T9 (fleet-state home)
  are the other early, gating pieces.
- **Backend (B):** T2 (autodetect + ask) and T3 (synchronous fallback), both on T1.
- **Self-management (C):** T4 (`dispatch_isolation`) and T5 (auto-heal), on T1.
- **Meta/coordination/autonomy (D):** T6 (meta-tower; on T1, T2, T8), T7
  (coordination protocol; on T1, T6).
- **Approachability (E):** T10 (entry command + status surface; on T2, T6, T9).
- **Docs:** T11, on everything.

Several tasks carry cross-spec edges to `orchestration-concurrency` and a
required `bootstrap` D-38 amendment; those are recorded as risk-register rows at
kickoff, not as task dependencies (a sibling spec's task ids are not in this
bundle's dependency space).

## Forward plan

### Task 1 — Backend capability contract

- **Deliverables:** A definition of the backend **capability contract** — the
  four capabilities (named/addressable units, attributed message relay,
  positive-evidence-of-death liveness, spawn) — as a resolvable doctrine doc (or
  a normative section in an existing dispatch doc), plus a mapping table
  re-describing each existing backend (`subagent`, `tmux`, `print`,
  `in-session`) as a contract implementation with its declared capability gaps.
  The `dispatch_backend` config option's documentation updated to reference the
  contract.
- **Done when:** the contract names all four capabilities with an evaluable
  definition of each; every existing backend is mapped to the capabilities it
  provides and the ones it lacks; the doc resolves via the rule-doc resolution
  path; `check-doc-links.sh` and the doc linters pass.
- **Dependencies:** none
- **Citations:** D-2 · REQ-B1.1, REQ-B1.2
- **Estimated effort:** 1 day

### Task 8 — Autonomous-safe-decision policy

- **Deliverables:** A doctrine/skill description of the autonomous-safe-decision
  policy expressed as a *mapping onto* the finding-categorization buckets and
  hard-pause zones: an enumeration of what an unattended tower MAY decide
  (act-then-review buckets + routine operational hygiene) and what it MUST
  escalate/pause (hard-pause zones + irreducible Needs-human-judgment forks),
  each item citing the gate concept it maps to. No new decision taxonomy.
- **Done when:** the policy enumerates the may-decide and must-escalate sets;
  every item cites a finding-categorization bucket or hard-pause zone (no
  free-standing category); the never-auto-merge invariant is named as the floor;
  the doc resolves via the rule-doc path; doc linters pass.
- **Dependencies:** none
- **Citations:** D-8 · REQ-A1.3, REQ-D1.4
- **Estimated effort:** half day

### Task 9 — Fleet coordination-state home

- **Deliverables:** Resolution of the durable fleet-coordination-state location
  through the `${CLAUDE_PLUGIN_DATA}` chain (with the writer-mode fallback the
  overlay resolvers use), and a small store for the worker/scope registry the
  status surface reads. The advisory-lock home is explicitly NOT decided here
  (left to `orchestration-concurrency`); a comment/citation records the deferral.
- **Done when:** the fleet-state root resolves in both delivery modes
  (plugin and writer) and survives a simulated plugin-version change; distinct
  plugin namespaces resolve to distinct roots; the registry store round-trips a
  worker/scope record; hostile identifiers are rejected before any path use;
  tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-11 · REQ-D1.5, REQ-A1.6
- **Estimated effort:** 1 day

### Task 2 — Backend autodetection & present-and-ask selection

- **Deliverables:** A host-backend autodetection step (`scripts/`-level
  detection of tmux, the subagent runtime, and any configured pluggable
  backend), wired into `/orchestrate` so it presents the detected set and asks
  the operator which to use; in unattended mode, selection comes from resolved
  config and a missing rich backend degrades to the synchronous fallback. Never
  silently picks.
- **Done when:** autodetect reports the backends actually present on the host;
  attended dispatch presents the set and asks (no silent pick); unattended
  dispatch reads config and degrades a missing rich backend to the synchronous
  fallback (never to an interactive backend); the selection path is covered by
  tests; tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-B1.5
- **Estimated effort:** 1 day

### Task 3 — Synchronous fallback backend

- **Deliverables:** The synchronous-execution backend as a contract
  implementation: units (and, under per-step isolation, steps) run one at a time
  in the dispatching session with a context clear between them, so context stays
  bounded with no multiplexer. Declares its capability profile against the Task 1
  contract.
- **Done when:** with no rich backend available or selected, a spec's ready
  units execute one at a time synchronously with a context clear between units;
  the backend declares its capability profile; the never-auto-merge invariant and
  the state-safety contract hold on this path; tests cover the single-stream run;
  tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-B1.4, REQ-A1.4
- **Estimated effort:** 1 day

### Task 4 — `dispatch_isolation` knob & per-step dispatch

- **Deliverables:** The `dispatch_isolation` config option (`per-step` |
  `per-unit`, default `per-step` per the assigned human decision), documented in
  `docs/options-reference.md`, and `/execute-task` rewired so that under
  `per-step` each step — implementation, then each review skill in
  `review_sequence` — runs in its own fresh `/resume`-seeded session; other
  backends approximate as their substrate allows. Carries the required
  `bootstrap` D-38 amendment as a risk-register row (cross-spec).
- **Done when:** `dispatch_isolation` resolves through all four overlay layers;
  under `per-step` the implementation and each review skill run in distinct
  fresh sessions seeded by `/resume`; under `per-unit` today's single-session
  behavior holds; the per-step path preserves the state-safety contract
  (REQ-C1.4); `check-options-reference.sh` passes; tests pass under
  `mise run check`.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-C1.3, REQ-C1.4
- **Estimated effort:** 2 days

### Task 5 — Context-budget monitor & auto-heal handover

- **Deliverables:** A context-budget monitor for a long-running tower (threshold
  configurable via a documented knob) and the auto-heal handover: on nearing the
  limit the tower launches a fresh tower that rebuilds from durable state, with
  the standing-instructions/wake prompt serving as the handover document; the
  retiring tower starts the replacement and stops. The exact budget signal is
  resolved against Claude Code's available capability (risk-register row /
  research).
- **Done when:** the monitor surfaces a near-limit condition against the
  configured threshold; auto-heal launches a fresh tower that reconstructs the
  in-flight picture from `tasks.md` + `gh` + the worker list with no in-memory
  state passed; the handover uses the wake prompt (no second artifact); the
  handover preserves the state-safety contract (REQ-C1.4); the threshold knob is
  in `docs/options-reference.md`; tests/manual exercise cover the handover; CI
  passes.
- **Dependencies:** 1
- **Citations:** D-4 · REQ-C1.1, REQ-C1.2, REQ-C1.4
- **Estimated effort:** 2 days

### Task 6 — Meta-orchestration (tower of towers)

- **Deliverables:** A meta-tower mode that selects ready units across multiple
  active specs, launches/retires subordinate single-spec towers via the backend
  contract, and enforces a fleet-level concurrency bound (a documented knob)
  distinct from per-spec `max_parallel_units`. Each subordinate tower stays an
  independent disposable step machine; the meta-tower holds no cross-spec state
  beyond the current step. Honors the autonomous-safe-decision policy (Task 8) in
  unattended mode.
- **Done when:** the meta-tower selects across the active specs it supervises,
  respecting each spec's per-spec lock; the fleet concurrency bound caps total
  concurrent units across specs and resolves through the overlay layers; subordinate
  towers run independently and rebuild from disk; unattended decisions follow the
  Task 8 policy; never-auto-merge holds at the meta tier; the fleet-bound knob is
  documented; tests/manual cover multi-spec selection; CI passes.
- **Dependencies:** 1, 2, 8
- **Citations:** D-6 · REQ-D1.1, REQ-D1.5, REQ-A1.2
- **Estimated effort:** 2 days

### Task 7 — Inter-orchestrator coordination protocol

- **Deliverables:** The coordination protocol made first-class: the division of
  labor (tower owns state moves/dispatch/merged-worker cleanup; worker owns its
  branch's conflict resolution and post-merge self-sync) and the attributed,
  non-impersonating relay (buffer-paste delivery, capture-pane/equivalent status
  reads, never `send-keys` impersonation, never answering worker permission
  prompts), encoded in the orchestrate/meta skills and a doctrine description.
  Worker output handled as data; handles validated before use.
- **Done when:** the division of labor is documented and enforced (no tower edits
  another tower's/worker's branch state directly); relay is attributed and uses
  the buffer-paste mechanism, with a test/manual check that no `send-keys`
  impersonation path exists and worker permission prompts are never auto-answered;
  worker output/handles are treated as data with validation before use; doc
  linters and CI pass.
- **Dependencies:** 1, 6
- **Citations:** D-7 · REQ-D1.2, REQ-D1.3, REQ-B1.6, REQ-A1.6
- **Estimated effort:** 2 days

### Task 10 — Approachability: entry command, status surface, per-worker scope

- **Deliverables:** One obvious entry command that selects a backend
  (autodetect-and-ask) and starts the tower(s); a visible status surface reading
  the Task 9 registry (workers, each worker's scope = spec+unit, each worker's
  state) legible from a normal terminal/editor without attaching to a
  multiplexer; clear per-worker scope presentation. The approachable path is the
  default presentation. The concrete surface form is settled at execution per the
  open-question disposition recorded at kickoff.
- **Done when:** a single documented command starts fleet operation without
  requiring tmux knowledge; the status surface shows each worker's scope and
  state from a normal terminal/editor; per-worker scope (isolated context, one
  spec/unit) is legible; the path is the default, not gated behind tmux; tests/
  manual cover the surface; CI passes.
- **Dependencies:** 2, 6, 9
- **Citations:** D-9 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4
- **Estimated effort:** 2 days

### Task 11 — Adopter docs, options reference & onboarding handoff

- **Deliverables:** Adopter-facing documentation of fleet operation — the
  backend capability contract and how to plug in a backend, autodetect-and-ask,
  the synchronous fallback, `dispatch_isolation`, the context-budget/auto-heal
  self-management, meta-orchestration and the coordination protocol, the
  autonomous-safe-decision policy, and the approachable status surface — with
  every new config option present in `docs/options-reference.md` and a hand-off
  note for the packaging/onboarding docs.
- **Done when:** every new option (`dispatch_isolation`, the context-budget
  threshold, the fleet concurrency bound, any backend-selection option) has a
  row in `docs/options-reference.md` and `check-options-reference.sh` passes; the
  fleet capabilities are documented for an adopter who is not a tmux user; the
  capability-vs-style split (core knob vs overlay value) is stated for each knob;
  `check-doc-links.sh` and the doc linters pass.
- **Dependencies:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
- **Citations:** D-10 · REQ-A1.5, REQ-E1.4
- **Estimated effort:** 1 day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **A concrete non-tmux/non-subagent backend adapter.** Task 1's contract and
  Task 2's selection ship the *path* to plug in another terminal/multiplexer; a
  specific second-multiplexer adapter is built when a concrete adopter need
  appears, not speculatively. Confidence: high.
  **Gate:** a concrete adopter need for a specific non-tmux backend is observed
  in the drain loop. Citations: D-2 · REQ-B1.3.
- **Richer status rendering beyond the terminal/editor-legible surface.** The
  default approachable surface (Task 10) is terminal/editor-legible; a richer
  rendering follows only if the legible surface proves insufficient in practice.
  Confidence: medium.
  **Gate:** the terminal/editor-legible status surface proves insufficient for
  non-tmux operators in practice. Citations: D-9 · REQ-E1.2.

## Out of scope

- The state-safety internals of `orchestration-concurrency` (consumed as a
  contract, never redefined here).
- Auto-merge at any tier (permanent carried invariant).
- A parallel autonomy taxonomy (the autonomous-safe-decision policy maps onto the
  existing finding-categorization gate).
- A GUI/web fleet dashboard (a status surface built on Claude Code primitives,
  legible from a terminal/editor, is the chosen form).
- Cross-repo / public-adopter observation fan-in (a separate effort; only the
  within-one-author multi-spec reach is in scope).
- New AI/agent frameworks (Claude Code primitives only).
