# Orchestration Fleet — Tasks

**Status:** Ready
**Last reviewed:** 2026-06-29
**Format-version:** 1

Dependency view (derived; the `Dependencies:` lines are authoritative). Task 1
(the backend capability contract + advertisement) is the foundational seam almost
everything else builds on. Task 8 (the autonomous-safe-decision policy) is a
safety artifact that gates the unattended meta-tower, so it carries an explicit
edge from Task 6. The two seams of facet E are split: Task 12 builds the
attention/notification substrate (decision queue, portable status renderer,
heartbeat-in-core, notification seam) and Task 10 surfaces it as the approachable
default UX. The facets sit on the foundation:

- **Foundation:** T1 (contract + advertisement); T8 (autonomy policy) and T9
  (cross-spec fleet-state home) are the other early, gating pieces.
- **Backend (B):** T2 (autodetect + ask), T3 (degradation ladder + synchronous
  terminal rung + runtime failover), both on T1.
- **Self-management (C):** T4 (`dispatch_isolation`) and T5 (context-budget +
  auto-heal), on T1.
- **Meta/coordination/autonomy (D):** T6 (meta-tower; on T1, T2, T8), T7
  (coordination protocol; on T1, T6).
- **Approachability (E):** T12 (attention/notification capability; on T9), T10
  (entry command + two-seam UX + persona mapping; on T2, T6, T9, T12).
- **Docs:** T11, on everything.

Several tasks carry cross-spec edges to `orchestration-concurrency` (now Active
and partly shipped — its `orchestrate-state.sh`, `orchestrate-marker.sh`,
`orchestrate-lock.sh`, `tasks-pr-sync.sh` are in core) and a required `bootstrap`
D-38 amendment; those are recorded as risk-register rows at kickoff, not as task
dependencies (a sibling spec's task ids are not in this bundle's dependency
space).

## Forward plan

### Task 1 — Backend capability contract & advertisement

- **Deliverables:** A definition of the backend **capability contract** — the
  capabilities a dispatch backend provides: named/addressable units,
  **observe-in-flight**, **steer-in-flight**, positive-evidence-of-death
  liveness, and **session-grade spawn** (a separate top-level session, not an
  in-harness subagent) — as a resolvable doctrine doc (or a normative section in
  an existing dispatch doc), plus the **advertisement** mechanism: a backend
  self-describes its capability set (`{ interactive, can_observe,
  can_steer_inflight, provides_attention_surface, supports_parallel }`) and the
  orchestrator adapts to what is advertised. A mapping table re-describes each
  existing backend (`subagent`, `tmux`, `print`, `in-session`) by its advertised
  set including its gaps. The `dispatch_backend` config documentation references
  the contract.
- **Done when:** the contract names each capability with an evaluable definition;
  observe-in-flight and steer-in-flight are first-class (not folded into a generic
  relay); spawn is defined as session-grade; the advertisement set is named and
  every existing backend is mapped to it (capabilities provided and lacked); the
  orchestrator's adapt-to-advertised behavior is specified (no-steer routes to the
  queue; `provides_attention_surface` suppresses planwright's own rendering); the
  doc resolves via the rule-doc path; `check-doc-links.sh` and the doc linters
  pass.
- **Dependencies:** none
- **Citations:** D-2 · REQ-B1.1, REQ-B1.2, REQ-B1.3
- **Estimated effort:** 1.5 days
- **Last activity:** 2026-07-02

### Task 8 — Autonomous-safe-decision policy

- **Deliverables:** A doctrine/skill description of the autonomous-safe-decision
  policy expressed as a *mapping onto* the finding-categorization buckets and
  hard-pause zones: an enumeration of what an unattended tower MAY decide
  (act-then-review buckets + routine operational hygiene) and what it MUST
  escalate/pause (hard-pause zones + irreducible Needs-human-judgment forks),
  each item citing the gate concept it maps to, escalations surfaced via the
  decision queue (Task 12). No new decision taxonomy.
- **Done when:** the policy enumerates the may-decide and must-escalate sets;
  every item cites a finding-categorization bucket or hard-pause zone (no
  free-standing category); the never-auto-merge invariant is named as the floor;
  escalations route to the decision queue; the doc resolves via the rule-doc
  path; doc linters pass.
- **Dependencies:** none
- **Citations:** D-8 · REQ-A1.3, REQ-D1.4
- **Estimated effort:** half day
- **Last activity:** 2026-07-02

### Task 9 — Cross-spec fleet coordination-state home

- **Deliverables:** Resolution of the durable **cross-spec**
  fleet-coordination-state location through the `${CLAUDE_PLUGIN_DATA}` chain
  (with the writer-mode fallback the overlay resolvers use), and a small store
  for the worker/scope registry the attention surface reads. This is explicitly
  distinct from the sibling's **per-spec** orchestration state (the advisory lock
  and runtime dispatch marker, which the sibling ships spec-dir-local at
  `<spec-dir>/.orchestrate.lock` and `<spec-dir>/.orchestrate/markers/`); a
  comment/citation records the split and that the lock home is the sibling's
  decision, not re-decided here. Because the cross-spec store is read by the
  attention surface (Task 12) and written by the meta-tower's fleet-bound
  accounting (Task 6) concurrently, this task also provides a **named cross-spec
  concurrency-control primitive** — a fleet-level advisory lock (à la the
  sibling's `orchestrate-lock.sh`) or atomic-append registry semantics — that
  Task 6 and Task 12 consume for a race-free check-and-increment of the
  fleet-concurrency bound and for read-during-write safety on the registry. This
  is the resolution of the signed brief's reshaped R1 (the cross-spec store must
  not be a lockless shared-mutable surface).
- **Done when:** the cross-spec fleet-state root resolves in both delivery modes
  (plugin and writer) and survives a simulated plugin-version change; distinct
  plugin namespaces resolve to distinct roots; the registry store round-trips a
  worker/scope record; the named concurrency-control primitive serializes (or
  makes atomic) concurrent registry writes and the fleet-bound
  check-and-increment, so two concurrent towers cannot corrupt the registry or
  exceed the bound; the split from the sibling's spec-local lock/marker is
  documented and no fleet path writes into the sibling's `.orchestrate/` dir;
  hostile identifiers are rejected before any path use; tests pass under
  `mise run check`.
- **Dependencies:** 1
- **Citations:** D-11 · REQ-D1.6, REQ-A1.6
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-02

### Task 3 — Degradation ladder, synchronous terminal rung & runtime failover

- **Deliverables:** The **graceful-degradation ladder** (richest to safest:
  interactive-multiplexer-with-steer → multiplexer-without-steer or headless
  `claude -p` pool → in-harness subagent → synchronous in-session with strategic
  context clears), the synchronous terminal rung as a contract implementation
  (units, and under per-step isolation steps, run one at a time with a context
  clear between them), and **runtime failover**: on a chosen backend dying mid-run,
  descend one rung with a logged note + `## Awaiting input` entry, recording the
  effective backend **spec-locally alongside the sibling's dispatch marker**
  (`<spec-dir>/.orchestrate/`), never in `tasks.md`. The descent honors
  **degrade-capability-never-safety**: a descent that would drop a guard
  (worker-settings deny, never-auto-merge, never-force-push, the freshness gate)
  aborts instead.
- **Done when:** with no rich backend available or selected, ready units execute
  via the synchronous terminal rung with bounded-context clears; runtime failover
  descends exactly one rung with a logged note + Awaiting-input entry (never a
  silent downgrade) and records the effective backend spec-locally, not in
  `tasks.md`; a descent that would drop a named guard is refused; the
  never-auto-merge invariant and the sibling state-safety contract hold on every
  rung; tests cover the single-stream run, a simulated failover, and a
  safety-abort; tests pass under `mise run check`.
- **Dependencies:** 1, 2
- **Citations:** D-3 · REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-A1.4
- **Estimated effort:** 2 days

### Task 4 — `dispatch_isolation` knob & per-step dispatch

- **Deliverables:** The `dispatch_isolation` config option (`per-step` |
  `per-unit`, default `per-step` per the assigned human decision), documented in
  `docs/options-reference.md`, and `/execute-task` rewired so that under
  `per-step` each step — implementation, then each review skill in the configured
  `review_sequence` — runs in its own fresh `/resume`-seeded session; other
  backends approximate as their substrate allows. Carries the required `bootstrap`
  D-38 amendment as a risk-register row (cross-spec).
- **Done when:** `dispatch_isolation` resolves through all four overlay layers;
  under `per-step` the implementation and each review skill run in distinct fresh
  sessions seeded by `/resume`; under `per-unit` today's single-session behavior
  holds; the per-step path preserves the state-safety contract (REQ-C1.4);
  `check-options-reference.sh` passes; tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-C1.3, REQ-C1.4
- **Estimated effort:** 2 days
- **Last activity:** 2026-07-02

### Task 6 — Meta-orchestration (tower of towers)

- **Deliverables:** A meta-tower mode that selects ready units across multiple
  active specs (reading each spec's live derivation via the sibling's
  `orchestrate-state.sh`, not the committed snapshot), launches/retires
  subordinate single-spec towers via the backend contract, and enforces a
  fleet-level concurrency bound (a documented knob) distinct from per-spec
  `max_parallel_units`. Each subordinate tower stays an independent disposable step
  machine; the meta-tower holds no cross-spec state beyond the current step.
  Honors the autonomous-safe-decision policy (Task 8) in unattended mode.
- **Done when:** the meta-tower selects across the active specs it supervises,
  respecting each spec's per-spec lock; the fleet concurrency bound caps total
  concurrent units across specs and resolves through the overlay layers;
  subordinate towers run independently and rebuild from disk; unattended decisions
  follow the Task 8 policy; never-auto-merge holds at the meta tier; the fleet-bound
  knob is documented; tests/manual cover multi-spec selection; CI passes.
- **Dependencies:** 1, 2, 8
- **Citations:** D-6 · REQ-D1.1, REQ-D1.5, REQ-A1.2
- **Estimated effort:** 2 days
- **Last activity:** 2026-07-03

### Task 7 — Inter-orchestrator coordination protocol

- **Deliverables:** The coordination protocol made first-class: the division of
  labor (tower owns `tasks.md` reconcile/dispatch/merged-worker cleanup; worker
  owns its branch's conflict resolution and post-merge self-sync) and the
  attributed, non-impersonating relay that works **against a live, busy worker**
  (buffer-paste/steer-in-flight delivery, capture-pane/observe-in-flight status
  reads, never `send-keys` impersonation, never answering worker permission
  prompts), encoded in the orchestrate/meta skills and a doctrine description.
  Worker output handled as data; handles validated before use.
- **Done when:** the division of labor is documented and enforced (no tower edits
  another tower's/worker's branch state directly); relay is attributed, uses the
  buffer-paste/steer-in-flight mechanism, and works against a running worker, with
  a test/manual check that no `send-keys` impersonation path exists and worker
  permission prompts are never auto-answered; worker output/handles are treated as
  data with validation before use; doc linters and CI pass.
- **Dependencies:** 1, 6
- **Citations:** D-7 · REQ-D1.2, REQ-D1.3, REQ-B1.7, REQ-A1.6
- **Estimated effort:** 2 days

### Task 10 — Approachability: entry command, two-seam UX, persona mapping

- **Deliverables:** One obvious entry command that autodetects/selects a backend
  (Task 2) and starts the tower(s), rendering the decision queue (Task 12) as the
  default attention surface; the **execution-substrate / attention-surface
  decoupling** surfaced as UX, including the
  multiplexer-as-detached-background-plumbing path (the tower drives a detached
  server; the human sees only the
  attention surface); clear per-worker scope presentation; and the documented
  **persona → (execution backend × attention surface)** mapping (multiplexer
  users, non-terminal users, editor-feedback users). The approachable path is the
  default presentation, not a fallback behind tmux.
- **Done when:** a single documented command starts fleet operation without
  requiring tmux knowledge; quality (session-grade, steerable workers) is available
  with the multiplexer running as invisible background plumbing; the decision queue
  is the default surface readable from a normal terminal/editor; per-worker scope
  (isolated context, one spec/unit) is legible; the persona×seam mapping is
  documented; the path is the default, not gated behind tmux; tests/manual cover
  the surface; CI passes.
- **Dependencies:** 2, 6, 9, 12
- **Citations:** D-9, D-12 · REQ-E1.1, REQ-E1.2, REQ-E1.5, REQ-E1.6
- **Estimated effort:** 2 days

### Task 11 — Adopter docs, options reference & onboarding handoff

- **Deliverables:** Adopter-facing documentation of fleet operation — the backend
  capability contract + advertisement and how to plug in a backend,
  autodetect-and-ask, the degradation ladder and runtime failover, the synchronous
  terminal rung, `dispatch_isolation`, the context-budget/auto-heal
  self-management, meta-orchestration and the coordination protocol, the
  autonomous-safe-decision policy, the attention/notification capability and the
  decision queue, and the persona×seam mapping — with every new config option
  present in `docs/options-reference.md` and a hand-off note for the
  packaging/onboarding docs.
- **Done when:** every new option (`dispatch_isolation`, the context-budget
  threshold, the fleet concurrency bound, the notification channel, any
  backend-selection option) has a row in `docs/options-reference.md` and
  `check-options-reference.sh` passes; the fleet capabilities are documented for an
  adopter who is not a tmux user; the capability-vs-style split (core knob vs
  overlay value) is stated for each knob; `check-doc-links.sh` and the doc linters
  pass.
- **Dependencies:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12
- **Citations:** D-10 · REQ-A1.5, REQ-E1.4
- **Estimated effort:** 1 day

## In progress

### Task 2 — Backend autodetection & present-and-ask selection

- **Deliverables:** A host-backend autodetection step (`scripts/`-level detection
  of tmux, the subagent runtime, and any configured pluggable backend) that
  collects each candidate's advertised capability set (Task 1), wired into
  `/orchestrate` so it presents the detected set and asks the operator which to
  use; in unattended mode, selection comes from resolved config and a missing rich
  backend degrades down the ladder (Task 3), never silently picking an interactive
  backend.
- **Done when:** autodetect reports the backends actually present and their
  advertised capabilities; attended dispatch presents the set and asks (no silent
  pick); unattended dispatch reads config and degrades a missing rich backend down
  the ladder (never to an interactive backend); the selection path is covered by
  tests; tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-B1.4
- **Estimated effort:** 1 day
- **Status:** PR #112 draft
- **Last activity:** 2026-07-02

### Task 5 — Context-budget monitor & auto-heal handover (`continue-as-new`)

- **Deliverables:** A context-budget monitor for a long-running tower (threshold
  configurable via a documented knob) and the auto-heal handover (the
  `continue-as-new` pattern): on nearing the limit the tower launches a fresh
  tower that rebuilds from durable state (the `tasks.md` snapshot, `gh`, the
  branch/marker/process and worker list), with the standing-instructions/wake
  prompt serving as the handover document; the retiring tower starts the
  replacement and stops. The exact budget signal is resolved against Claude Code's
  available capability (risk-register row / research).
- **Done when:** the monitor surfaces a near-limit condition against the
  configured threshold; auto-heal launches a fresh tower that reconstructs the
  in-flight picture from durable state with no in-memory state passed (testable by
  "could a fresh tower resume from this alone?"); the handover uses the wake prompt
  (no second artifact); the handover preserves the state-safety contract
  (REQ-C1.4); the threshold knob is in `docs/options-reference.md`; tests/manual
  exercise cover the handover; CI passes.
- **Dependencies:** 1
- **Citations:** D-4 · REQ-C1.1, REQ-C1.2, REQ-C1.4
- **Estimated effort:** 2 days
- **Status:** PR #115 draft
- **Last activity:** 2026-07-02

### Task 12 — Attention/notification capability in core

- **Deliverables:** The substrate-agnostic attention/notification capability
  lifted into core (paralleling the execution capability), depending on no
  dotfiles-local mechanism: heartbeat/awareness state under the cross-spec
  fleet-state home (Task 9); a **portable status renderer** reading the
  worker/scope registry (each worker's scope = spec + unit, state = working /
  awaiting input / PR-ready / merged / done); the **decision queue** — one
  ordered, alarm-rationalized queue of actionable items across all active specs,
  each a structured choice (spec/task, question, recommended default, concrete
  options), human load bounded by `## Awaiting input` count, non-actionable signal
  suppressed; and a **notification seam** whose channel (multiplexer popup / OS
  notify / editor toast) is the overlay value.
- **Done when:** heartbeat/registry state lives under the Task 9 cross-spec home
  and a marketplace-install user gets the capability from core (no dotfiles
  dependency); the renderer lists each worker's scope and state; the decision
  queue orders actionable items across active specs as structured choices and its
  length tracks `## Awaiting input` count (not worker count); the notification
  seam's channel resolves as an overlay value through the four layers; a backend
  advertising `provides_attention_surface: true` suppresses planwright's own queue
  rendering; tests/manual cover the renderer and queue; `check-options-reference.sh`
  passes for the notification-channel knob; CI passes.
- **Dependencies:** 9
- **Citations:** D-13 · REQ-E1.3, REQ-E1.4, REQ-A1.6
- **Estimated effort:** 2 days
- **Status:** PR #116 draft
- **Last activity:** 2026-07-03

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **A concrete non-tmux/non-subagent backend adapter.** Task 1's contract +
  advertisement and Task 2's selection ship the *path* to plug in another
  terminal/multiplexer; a specific second-multiplexer adapter (Zellij, cmux,
  WezTerm, …) is built when a concrete adopter need appears, not speculatively.
  Confidence: high.
  **Gate:** a concrete adopter need for a specific non-tmux backend is observed in
  the drain loop. Citations: D-2 · REQ-B1.3.
- **An editor-rendered attention surface (Cursor-style).** Task 12 ships the
  portable status renderer + decision-queue model and Task 10 ships the persona
  mapping that names the editor-feedback persona; a concrete editor integration
  (the editor rendering the queue + diffs with a steer-in-flight affordance) is
  built to a concrete adopter need. All durable fleet state is files, so this is a
  renderer, not a new execution model. Confidence: medium.
  **Gate:** a concrete editor-integration adopter need is observed in the drain
  loop. Citations: D-9, D-12 · REQ-E1.6.
- **Richer status rendering beyond the terminal/editor-legible surface.** The
  default approachable surface (Task 10/12) is terminal/editor-legible; a richer
  rendering (e.g. a dashboard) follows only if the legible surface proves
  insufficient in practice. Confidence: medium.
  **Gate:** the terminal/editor-legible decision queue proves insufficient for
  non-tmux operators in practice. Citations: D-9 · REQ-E1.3.

## Out of scope

- The state-safety internals of `orchestration-concurrency` (consumed as the
  derived-projection contract, never redefined here).
- Auto-merge at any tier (permanent carried invariant).
- A parallel autonomy taxonomy (the autonomous-safe-decision policy maps onto the
  existing finding-categorization gate).
- A GUI/web fleet dashboard (a decision queue built on Claude Code primitives,
  legible from a terminal/editor, is the chosen form).
- Cross-repo / public-adopter observation fan-in (a separate effort; only the
  within-one-author multi-spec reach is in scope).
- New AI/agent frameworks (Claude Code primitives only; prior art mined for
  patterns, not installed).
