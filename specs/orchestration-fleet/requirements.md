# Orchestration Fleet — Requirements

**Status:** Draft
**Last reviewed:** 2026-06-29
**Format-version:** 1

## Goal

planwright's multi-orchestration already works in practice: an operator runs
several `/orchestrate` towers in tmux, they coordinate by hand-relayed
messages, they make safe routine decisions while the human is away, and one
tower can launch others to drain multiple active specs. Those are *emergent*
behaviors of a skilled tmux operator, not first-class capabilities — they
depend on the human relaying messages, on tribal knowledge of the relay
mechanics, and on tmux fluency most adopters do not have.

This spec productizes those emergent behaviors into reliable, accessible,
resilient **fleet operation**, built on the state-safe concurrency foundation
its sibling spec `orchestration-concurrency` provides. The quality of that
emergent fleet does **not** come from tmux as such: it comes from
**session-grade workers** (separate top-level Claude Code sessions, full
context and harness, committing as principals) that the tower can
**observe in flight** and **steer in flight** (course-correct or answer a
running, busy worker without killing it), with **externally-imposed stage
sequencing** (context clears between stages). tmux is one substrate that
delivers those properties; headless `claude -p` keeps session-grade but loses
live observe/steer and sits near the safe fallback, not in the quality tier.

The spec separates **two seams** that tmux conflates today: the **execution
substrate** (how workers are hosted, addressed, observed, steered) and the
**attention surface** (what the human watches). Quality lives on the execution
seam; approachability lives on the attention seam; they do not trade off. The
execution seam is a backend **capability contract** with **capability
advertisement** (backends self-describe what they can do; the orchestrator
adapts) and a **graceful-degradation ladder** (attempt the richest available
backend, fall back to the safest-that-cannot-fail; **degrade capability, never
safety**). The attention seam is a substrate-agnostic **decision queue** —
the legible default for every persona — backed by a cross-session
attention/notification capability **lifted into core**. The four facets:

- **B — pluggable, autodetected execution backend:** a capability contract
  (named/addressable units, observe-in-flight, steer-in-flight,
  positive-evidence-of-death liveness, session-grade spawn), capability
  advertisement, autodetect-and-ask selection, and a graceful-degradation
  ladder with a synchronous terminal rung that always works.
- **C — orchestrator self-management:** a context-budget monitor and a
  disposable-tower auto-heal handover (a fresh tower continues from durable
  state — Temporal `continue-as-new`), plus a `dispatch_isolation` knob for
  fresh-session-per-step dispatch.
- **D — meta-orchestration, coordination & autonomy:** a tower of towers
  across multiple active specs, an attributed non-impersonating
  inter-orchestrator relay, and an autonomous-safe-decision policy wired to the
  existing finding-categorization gate.
- **E — approachability:** the two-seam decoupling surfaced as UX — one entry
  command, the decision queue as the default attention surface, a
  substrate-agnostic attention/notification capability in core, and a
  persona→(execution backend × attention surface) mapping that lets a
  non-terminal operator get full fleet quality with the multiplexer as
  invisible background plumbing.

The hard invariant carried in unchanged: **never auto-merge, at any tier.**

## Scope

### In scope

- A backend **capability contract** naming the capabilities a dispatch backend
  provides — named/addressable units, **observe-in-flight**, **steer-in-flight**,
  positive-evidence-of-death liveness, and **session-grade spawn** — with
  **capability advertisement** (each backend self-describes its capability set;
  the orchestrator adapts to what is advertised), extending the existing
  `dispatch_backend` config.
- A path to plug in other terminals/multiplexers exposing a CLI or API of
  tmux-comparable capability, by implementing/advertising the contract, with no
  edit to the consuming skills.
- **Autodetection** of candidate backends on the host: present what was found
  and ask; never silently pick.
- A **graceful-degradation ladder**: attempt the richest available backend; on
  unavailability or runtime failure, fall back down a defined chain to a
  synchronous terminal rung that needs no external substrate. Capability
  degrades down the ladder; safety never does.
- **Orchestrator self-management:** a context-budget monitor and an auto-heal
  handover that launches a fresh tower to continue in-flight work
  (disposable-tower / `continue-as-new`), and a `dispatch_isolation` knob for
  fresh-session-per-step dispatch.
- **Meta-orchestration:** a tower launching towers to drain multiple active
  specs; an **inter-orchestrator coordination protocol** (division of labor +
  attributed, non-impersonating relay working against a live, busy worker); and
  an **autonomous-safe-decision policy** wired to the existing autonomy gate.
- **Approachability:** the execution-substrate / attention-surface decoupling
  made first-class; a **decision queue** as the legible default attention
  surface; a **substrate-agnostic attention/notification capability lifted into
  core** (heartbeat state under the durable plugin-data home, a portable status
  renderer, a notification seam whose channel is an overlay value); and a
  persona→(backend × surface) mapping including the multiplexer-as-background
  -plumbing path for non-terminal operators.
- The capability-vs-style split for every backend/fleet preference (general
  capability → core opt-in knob; specific value → overlay), and data hygiene for
  every committed fleet artifact.

### Out of scope

- **The state-safety internals of `orchestration-concurrency`** (progress state
  as a derived projection never committed at dispatch; the runtime dispatch
  marker; the single advisory-lock primitive with the branch ref as fence;
  level-triggered reconcile from `gh`/branch/trailer ground truth). This spec
  **consumes** that contract; it never redefines it.
- **Auto-merge at any tier.** Merge is a reserved human control, permanent, not
  deferred — carried in unchanged from bootstrap.
- A **parallel autonomy gate.** The autonomous-safe-decision policy maps onto
  the existing finding-categorization buckets and hard-pause zones; it invents
  no second decision taxonomy.
- **New AI/agent frameworks.** Fleet operation uses Claude Code primitives only
  (skills, hooks, slash commands, scheduled agents, file-based state). Prior art
  (Temporal, LSP/DAP, ISA-18.2, Kubernetes, the actor model) is mined for
  *patterns only*; no second framework is installed.
- **The specific operator's backend/tool choice and fleet tuning values.** The
  seams and their knobs ship in core; the chosen tool, the chosen notification
  channel, and the tuning values live in an overlay (capability-vs-style).
- **A concrete second-multiplexer adapter** (Zellij, cmux, WezTerm, …) and an
  **editor-rendered surface** (Cursor-style). The spec ships the contract,
  advertisement, ladder, and the decision-queue *renderer seam* that make these
  possible; a specific adapter or editor integration is built to a concrete
  adopter need, not speculatively.
- **The cross-repo / public-adopter observation fan-in design.** The multi-spec
  reach within one author's active specs (and, where the operator runs them,
  multiple checkouts of one author's repos) is in scope (REQ-D1.5); the broader
  multi-source/multi-target accumulator redesign is a separate effort cited only
  as motivation (Sources).
- **A GUI/web fleet dashboard.** The attention surface is built on Claude Code
  primitives and is legible from a terminal/editor; a richer rendering follows
  only if the legible surface proves insufficient in practice.
- **Secrets or operational identifiers in any fleet artifact.** Coordination
  logs, status/queue surfaces, and handover docs carry preferences and state,
  never secrets or internal hostnames (data-hygiene rule).

## REQ-A — Foundation, dependency contract & carried invariants

- **REQ-A1.1** Fleet operation SHALL build on `orchestration-concurrency`'s
  state-safe concurrency contract and SHALL consume it as authoritative: under
  that contract dispatch and progress state are a **derived projection** —
  `/orchestrate` writes no dispatch/progress state to `tasks.md`; the task
  branch plus the per-spec advisory lock (and the `Planwright-Task` trailer and
  runtime dispatch marker) are the dispatch record, and `tasks.md` section
  placement is a level-triggered read-model snapshot reconciled from
  `gh`/branch/trailer ground truth off the worker's critical path. No fleet
  requirement SHALL redefine a sibling state-safety internal; where a fleet
  decision needs sibling confirmation it is recorded as an open question, not
  resolved here.
  *(Cites: D-1; orchestration-concurrency D-1, D-3, D-4 (Sources).)*
- **REQ-A1.2** Fleet operation SHALL carry the **never-auto-merge** invariant
  unchanged at every tier — single tower, meta-tower, and any backend or ladder
  rung: no fleet mechanism SHALL merge a PR, and merge SHALL remain a reserved
  human control.
  *(Cites: D-1; bootstrap D-26; bootstrap REQ-F1.6.)*
- **REQ-A1.3** The autonomous-safe-decision policy (REQ-D1.4) SHALL be expressed
  in terms of the existing finding-categorization buckets and hard-pause zones;
  fleet operation SHALL NOT introduce a parallel autonomy taxonomy.
  *(Cites: D-8; finding-categorization (Sources).)*
- **REQ-A1.4** Fleet machinery SHALL be proportionate: the rich-backend and
  meta-orchestration capabilities SHALL be opt-in, and a single-tower run on a
  host with no rich backend SHALL remain fully functional via the synchronous
  terminal rung of the degradation ladder (REQ-B1.5). The spec SHALL NOT require
  tmux, a multiplexer, or multiple towers for ordinary single-spec execution.
  *(Cites: D-3; proportionality (Sources).)*
- **REQ-A1.5** Every fleet/backend preference SHALL be classified on the
  capability-vs-style boundary: the general *capability* (a backend seam,
  advertisement, autodetect, the degradation ladder, a self-management or
  coordination mechanism, the attention/notification capability) lands in core
  as an opt-in, default-preserving config knob, while the specific *value*
  (which backend, which notification channel, which tuning) stays in an overlay.
  The default tilt is overlay when in doubt.
  *(Cites: D-10; customization-boundary (Sources); customization-overlay D-1.)*
- **REQ-A1.6** Every committed fleet artifact (coordination/relay logs, the
  attention surface's persisted state, the decision queue, handover documents,
  PR bodies) SHALL carry no secrets, credentials, internal hostnames, or
  sensitive operational detail; the artifact data-hygiene rule applies, and the
  secret-scan guard covers committed fleet artifacts.
  *(Cites: D-7; security-posture (Sources).)*

## REQ-B — Pluggable & autodetected execution backend

- **REQ-B1.1** planwright SHALL define a backend **capability contract** naming
  the capabilities a dispatch backend provides: (a) **named, addressable units**
  (each worker has a stable handle the tower can target); (b) **observe-in-flight**
  (the backend can read a worker's *current* state mid-task, not only its final
  output); (c) **steer-in-flight** (the backend can deliver a clearly-attributed
  message into a *running, busy* worker to course-correct or answer, without
  killing and restarting it); (d) **positive-evidence-of-death liveness** (the
  backend can distinguish an observed-dead worker from a merely-unobserved one);
  and (e) **session-grade spawn** (the backend can launch a worker for a unit in
  its worktree as a separate top-level session — full context window and harness
  surface, committing as a principal, surviving the tower's death — not a
  context-sharing in-harness subagent). Observe-in-flight and steer-in-flight are
  first-class capabilities, not folded into a generic "relay".
  *(Cites: D-2; bootstrap D-38, REQ-F1.8; the operational-protocol seed; the
  backend-direction addendum §A (Sources).)*
- **REQ-B1.2** Each backend SHALL **advertise its capability set** — at minimum
  `{ interactive, can_observe, can_steer_inflight, provides_attention_surface,
  supports_parallel }` — and the orchestrator SHALL adapt to what is advertised
  rather than special-casing backends by name: a backend advertising
  `can_steer_inflight: false` routes ambiguity to the decision queue instead of
  attempting a live nudge; a backend advertising `provides_attention_surface:
  true` makes planwright suppress its own decision-queue rendering and defer to
  that backend's surface. Advertisement composes with autodetect (autodetect
  discovers candidates; each candidate self-describes; present + ask).
  *(Cites: D-2; the backend-direction addendum §D; LSP/DAP prior art (Sources).)*
- **REQ-B1.3** The capability contract SHALL extend the existing
  `dispatch_backend` config (today: `subagent` default, `tmux` machine-local
  override, plus `print` and `in-session`) rather than replacing it, mapping each
  existing backend to its advertised capability set including the capabilities it
  lacks, and SHALL provide a path to plug in **other terminals or multiplexers**
  of tmux-comparable capability by implementing/advertising the contract —
  without editing the skills that consume it (the backend is selected through
  config, resolved through the overlay layers).
  *(Cites: D-2, D-10; bootstrap D-38, REQ-F1.8; existing config (Sources).)*
- **REQ-B1.4** `/orchestrate` SHALL **autodetect** candidate backends present on
  the host, collect each candidate's advertised capabilities, **present** the
  detected set to the operator, and **ask** which to use; it SHALL NOT silently
  pick a backend. In unattended mode (no human to ask), backend selection SHALL
  come from resolved config, and absence of a configured rich backend SHALL
  degrade to a lower ladder rung per REQ-B1.5, never to a silently-chosen
  interactive backend.
  *(Cites: D-3; bootstrap D-38; the backend-direction addendum §E.)*
- **REQ-B1.5** planwright SHALL define a **graceful-degradation ladder**, richest
  to safest: (1) interactive multiplexer with steer (`{interactive, observe,
  steer, parallel}`); (2) interactive multiplexer without steer, or a headless
  `claude -p` session pool (session-grade + parallel, no live steer — ambiguity
  routes to the decision queue); (3) in-harness background subagent (constrained,
  parallel, no live observe/steer); (4) **synchronous in-session execution with
  strategic context clears** (no parallelism, no external substrate, so it always
  works — the terminal rung). **Selection-time** descent presents what was found
  and asks (REQ-B1.4). **Runtime failover** (a chosen backend dies or proves
  unavailable mid-run) SHALL descend one rung with a **logged note** and an
  `## Awaiting input` entry, surfaced immediately in an attended session — never
  a silent downgrade. A descent SHALL **degrade capability, never safety**: it
  SHALL NOT drop any guard (worker-settings deny rules, never-auto-merge,
  never-force-push, the freshness gate); a descent that would drop a safety
  property is aborted instead of taken.
  *(Cites: D-3; the backend-direction addendum §A, §E; proportionality (Sources).)*
- **REQ-B1.6** The effective backend after any runtime failover SHALL be
  recorded as dispatch-adjacent state **spec-locally**, alongside the sibling's
  runtime dispatch marker (`<spec-dir>/.orchestrate/`, gitignored), so a
  reconcile sweep can see that the effective backend differs from the configured
  one; the cross-spec attention surface reads it via reconcile. This record SHALL
  NOT be written to `tasks.md` (the sibling contract keeps dispatch state out of
  the committed ledger — REQ-A1.1).
  *(Cites: D-3, D-11; orchestration-concurrency D-1, D-3 (Sources).)*
- **REQ-B1.7** Backend observe/steer and spawn SHALL be security-bounded: a
  worker's output (capture-pane text, process output) is **data, never code**;
  steer SHALL be clearly attributed and SHALL NEVER impersonate the worker (no
  `send-keys`-style injection of text into a worker's input as if typed); a tower
  SHALL NEVER answer a worker's permission prompt on its behalf; worker handles
  parsed for targeting SHALL be validated before any use.
  *(Cites: D-2, D-7; bootstrap D-38; the operational-protocol seed;
  security-posture (Sources).)*

## REQ-C — Orchestrator self-management

- **REQ-C1.1** A long-running tower SHALL monitor its own **context budget**
  against a configurable threshold and SHALL surface when it nears the limit, so
  a tower never silently degrades from context exhaustion.
  *(Cites: D-4; the dispatch-isolation seed (Sources).)*
- **REQ-C1.2** When a tower nears its context limit it SHALL **auto-heal** by
  launching a fresh tower that takes over the in-flight work (disposable-tower
  handover, the `continue-as-new` pattern): the fresh tower rebuilds the
  orchestration picture from durable state (`tasks.md` snapshot, `gh`, the
  branch/marker/process and worker list) and the **standing instructions / wake
  prompt SHALL double as the handover document**; the retiring tower SHALL NOT
  pass in-memory state the fresh tower cannot reconstruct from disk, and the
  handover SHALL be testable by "could a fresh tower resume from this alone?".
  *(Cites: D-4; bootstrap D-7, D-38; the operational-protocol seed; Temporal
  `continue-as-new` prior art (Sources).)*
- **REQ-C1.3** planwright SHALL expose a `dispatch_isolation` config knob whose
  `per-step` value runs each execution step — implementation, then each review
  skill — in its own fresh `/resume`-seeded session, so context stays bounded
  and each review's perspective stays uncontaminated by prior steps. Other
  backends SHALL approximate per-step isolation as closely as their substrate
  allows (the synchronous terminal rung via context clears between steps).
  *(Cites: D-5; the dispatch-isolation seed (Sources); bootstrap D-38.)*
- **REQ-C1.4** Auto-heal and per-step isolation SHALL preserve the sibling
  state-safety contract (REQ-A1.1): a tower handover or a fresh per-step session
  SHALL drive `tasks.md` placement only through the level-triggered reconcile and
  SHALL acquire the per-spec advisory lock for any state move, never writing
  dispatch/progress state to `tasks.md` by a path that bypasses the derived
  -projection contract.
  *(Cites: D-1, D-4, D-5; orchestration-concurrency D-1, D-3, D-4 (Sources).)*

## REQ-D — Meta-orchestration, coordination & autonomy

- **REQ-D1.1** planwright SHALL support **meta-orchestration**: a tower that
  launches and supervises subordinate towers to drain **multiple active specs**
  concurrently (a tower of towers), each subordinate tower owning one spec and
  remaining an independent disposable step machine that rebuilds from disk.
  *(Cites: D-6; bootstrap D-7, D-8; the multi-target-accumulator seed (Sources).)*
- **REQ-D1.2** planwright SHALL define an **inter-orchestrator coordination
  protocol** with an explicit division of labor: the tower owns `tasks.md`
  reconcile (placement), dispatch, and merged-worker cleanup; the owning worker
  session owns its branch's conflict resolution (merge, not rebase) and its
  post-merge self-sync. Coordination SHALL NOT have one tower edit another
  tower's or a worker's branch state directly.
  *(Cites: D-7; the operational-protocol seed (Sources).)*
- **REQ-D1.3** The coordination protocol's relay mechanics SHALL be **attributed
  and non-impersonating** and SHALL work against a **live, busy worker mid-task**:
  messages are delivered by a buffer-paste mechanism (e.g. `load-buffer`/
  `paste-buffer` under tmux, or the backend's steer-in-flight equivalent),
  clearly marked as tower-to-worker (or tower-to-tower) communication; status is
  read by capture-pane / equivalent observe-in-flight; the protocol SHALL NEVER
  use `send-keys`-style impersonation and SHALL NEVER answer a worker's
  permission prompt.
  *(Cites: D-7; the operational-protocol seed; the backend-direction addendum §A
  (Sources).)*
- **REQ-D1.4** planwright SHALL define an **autonomous-safe-decision policy**
  enumerating what a tower MAY decide unattended — routine hygiene, scoped
  cleanups, clear/simple forks — and what it MUST escalate — anything requiring
  sign-off, design forks, destructive/irreversible/security actions, or spec
  drift. The policy SHALL be expressed against the existing finding-
  categorization buckets and hard-pause zones (REQ-A1.3): "may decide unattended"
  maps to the act-then-review buckets, "must escalate" maps to the hard-pause
  zones and irreducible Needs-human-judgment forks, surfaced via the decision
  queue (REQ-E1.3).
  *(Cites: D-8; finding-categorization (Sources); bootstrap D-5; ISA-18.2
  alarm-rationalization prior art (Sources).)*
- **REQ-D1.5** Meta-orchestration SHALL reach across **one author's multiple
  active specs** (and, where the operator runs them, multiple checkouts of one
  author's repos): the meta-tower SHALL select among ready units across the
  active specs it supervises, reading each spec's live derivation (not the
  possibly-stale committed snapshot), respecting each spec's own per-spec lock
  and a **fleet-level concurrency bound** distinct from the per-spec
  `max_parallel_units`. Cross-repo / public-adopter fan-in is out of scope.
  *(Cites: D-6, D-11; the multi-target-accumulator seed (Sources);
  orchestration-concurrency D-3, D-4 (Sources).)*
- **REQ-D1.6** Cross-spec fleet coordination state that must persist across
  tower restarts and plugin updates (the worker/scope registry the attention
  surface reads, the fleet-level concurrency accounting, any meta-tower
  bookkeeping) SHALL live in a durable, plugin-update-stable location resolved
  through the `${CLAUDE_PLUGIN_DATA}` chain (with the writer-mode fallback the
  overlay resolvers use), not under the ephemeral plugin root — because it spans
  specs and cannot live under any one spec dir. This is distinct from the
  sibling's *per-spec* orchestration runtime state (the advisory lock and the
  runtime dispatch marker), which is spec-dir-local and gitignored
  (`<spec-dir>/.orchestrate.lock`, `<spec-dir>/.orchestrate/markers/`); the
  per-spec effective-backend failover record (REQ-B1.6) sits there with the
  marker, not in this cross-spec store.
  *(Cites: D-11; the plugin-data seed; orchestration-concurrency D-3, D-4 (Sources).)*

## REQ-E — Approachability

- **REQ-E1.1** planwright SHALL make the **execution substrate** and the
  **attention surface** separable seams: a multiplexer MAY run as a detached
  background server nobody attaches to (the tower drives it; the human sees only
  the attention surface), so full execution quality (session-grade, steerable
  workers) is available with zero multiplexer fluency. Quality is a property of
  the execution seam; approachability is a property of the attention seam; the
  two SHALL NOT trade off.
  *(Cites: D-9, D-12; the backend-direction addendum §B (Sources).)*
- **REQ-E1.2** Multi-orchestration SHALL have **one obvious entry command** that
  starts fleet operation without requiring the operator to know tmux (or any
  multiplexer): the entry point autodetects and selects a backend per REQ-B1.4,
  starts the tower(s), and renders the attention surface, so an operator on a
  normal editor and terminal can begin with a single documented command.
  *(Cites: D-9; the fleet-approachability framing (Sources).)*
- **REQ-E1.3** Fleet operation SHALL provide a **decision queue** as the legible
  default attention surface: one ordered queue of actionable items across all
  active specs, each entry naming the spec/task, the question, the recommended
  default, and the concrete options (the structured-choice shape, not dense
  prose). Human load SHALL be bounded by the count of `## Awaiting input`
  decisions, not the worker count; non-actionable signal SHALL be suppressed
  (alarm-rationalization). The queue SHALL render identically across a plain
  Claude session, a detached-multiplexer operator's popup, and an editor panel.
  *(Cites: D-9, D-13; the backend-direction addendum §C; ISA-18.2 prior art
  (Sources).)*
- **REQ-E1.4** planwright SHALL **lift a substrate-agnostic attention/
  notification capability into core**, paralleling the execution capability:
  heartbeat/awareness state under the durable plugin-data home (REQ-D1.6), a
  portable status renderer reading the worker/scope registry (each worker's
  scope = spec + unit, each worker's state = working / awaiting input / PR-ready
  / merged / done), and a **notification seam** whose specific channel (a
  multiplexer popup vs an OS notification vs an editor toast) is the **overlay
  value** per the capability-vs-style split. This capability SHALL NOT depend on
  any dotfiles-local mechanism; a marketplace-install user gets it from core.
  *(Cites: D-13, D-10; the plugin-data seed; the backend-direction addendum §C
  (Sources).)*
- **REQ-E1.5** The attention surface SHALL present each worker's **scope**
  clearly — isolated context, one spec/unit per worker — preserving the tmux
  model's advantages (clear scopes, isolated contexts, monitorable workers) for
  operators who never open a multiplexer, and SHALL be the legible **default**
  presentation (the backend seam surfaced as UX), not a degraded fallback behind
  the tmux path.
  *(Cites: D-9; bootstrap REQ-F1.1, REQ-F1.8.)*
- **REQ-E1.6** planwright SHALL document the **persona → (execution backend ×
  attention surface)** mapping so each target operator resolves as a combination
  of the two seams, not a separate system: (a) multiplexer users attach directly
  and the multiplexer may own the attention surface (advertised, so planwright
  defers); (b) non-terminal users get the multiplexer as invisible background
  plumbing plus the decision queue as the only surface; (c) editor-feedback
  users get the same background plumbing with the editor rendering the queue and
  diffs and exposing a steer-in-flight affordance. All durable fleet state is
  files, so an editor surface is a renderer, not a new execution model.
  *(Cites: D-9, D-12; the backend-direction addendum §B, §F (Sources).)*

## Changelog

- 2026-06-18: Bundle drafted at Status Draft via `/spec-draft`, autonomously
  (the spec-2 worker in a hybrid two-draft run). Established the four facets —
  pluggable/autodetected backend (REQ-B), orchestrator self-management (REQ-C),
  meta-orchestration/coordination/autonomy (REQ-D), and approachability (REQ-E) —
  on the foundation/dependency-contract group (REQ-A), from the
  `orchestration-fleet` seed brief and the mined observations. Fold-detection
  was pre-decided spin-new (sibling to `orchestration-concurrency`).
- 2026-06-29: In-place Draft re-draft via `/spec-draft` to fold the seed brief's
  2026-06-26 design addendum (§A–§G) and reconcile against the now-Active sibling
  `orchestration-concurrency` contract. Reframed the Goal around session-grade +
  observe-in-flight + steer-in-flight as the quality property (not tmux) and the
  two-seam split; split observe/steer into first-class capabilities and made
  spawn session-grade (REQ-B1.1); added capability advertisement (REQ-B1.2), the
  graceful-degradation ladder with runtime failover and the degrade-capability-
  never-safety floor (REQ-B1.5), and the effective-backend failover record
  (REQ-B1.6); reconciled REQ-A1.1 / REQ-C1.4 to the sibling's derived-projection
  model (no dispatch state in `tasks.md`); promoted fleet-coordination-state home
  to a requirement (REQ-D1.6); rebuilt facet E around the two-seam decoupling
  (REQ-E1.1), the decision queue as the default attention surface (REQ-E1.3), the
  attention/notification capability lifted into core (REQ-E1.4), and the
  persona×seam mapping (REQ-E1.6). New decisions D-12, D-13; D-2, D-3, D-9, D-11
  revised in place (Draft, never activated, so edited as drafting rather than
  amended). Headless `claude -p` encoded as ladder rung 2.

## Sources

- **The orchestration-fleet seed brief** — `specs/_pending/orchestration-fleet.md`
  (consumed): the North Star (productize emergent multi-orchestration into
  reliable fleet operation), the four facets B–E, the dependency contract on
  `orchestration-concurrency`, and the scope guidance.
- **The backend-direction addendum** — `specs/_pending/orchestration-fleet.md`,
  section "Addendum (2026-06-26 design conversation)" (consumed): §A the
  quality-bearing property is session-grade + observe + steer (not tmux), headless
  `claude -p` near the fallback tier; §B the execution-substrate / attention-
  surface decoupling and multiplexer-as-background-plumbing; §C the decision
  queue and lifting the attention/notification layer into core; §D capability
  advertisement (LSP/DAP-style); §E the graceful-degradation ladder with runtime
  failover and the degrade-capability-never-safety floor; §F the persona×seam
  mapping; §G the prior-art map (Temporal `continue-as-new`, ISA-18.2 alarm
  rationalization, Kubernetes level-triggered reconcile, the actor model).
- **The dispatch-isolation seed** — observations log 2026-06-15: fresh-session-
  per-step as the default tmux-backend behavior, the `dispatch_isolation:
  per-step` knob, fresh `/resume`-seeded sessions per step, the disposable-tower
  / bounded-context rationale.
- **The operational-protocol seed** — observations log 2026-06-12: division of
  labor; attributed relay via `load-buffer`/`paste-buffer`, never `send-keys`
  impersonation, never answering worker permission prompts, capture-pane for
  status; positive-evidence-of-death liveness; the dispatch-time environment
  hardening (umask-pinning pane wrapper, SSH-agent indirection); the standing-
  instructions wake prompt doubling as the disposable-tower handover document.
- **The worktree-mechanics seed** — observations log 2026-06-16 (referenced):
  the D-37 native-worktree gap relevant to session-grade spawn (REQ-B1.1).
- **The plugin-data seed** — observations log 2026-06-11: `${CLAUDE_PLUGIN_DATA}`
  (`~/.claude/plugins/data/<id>/`, persists across plugin updates) as the durable
  home for framework runtime state, motivating the fleet-coordination-state and
  attention-state homes (REQ-D1.6, REQ-E1.4; D-11, D-13).
- **The multi-target-accumulator seed** — observations log 2026-06-17
  (referenced, not consumed): a fleet across one author's repos and a
  machine-local fan-in inbox, motivating the multi-spec reach (REQ-D1.5); its
  full cross-repo / public-adopter redesign is out of scope.
- **The fleet-approachability framing** — the seed brief's product framing: most
  users are not tmux power users; multi-orchestration should be legible on a
  normal editor/terminal while preserving the tmux model's advantages.
- **The `orchestration-concurrency` sibling spec** (`specs/orchestration-concurrency/`,
  now Active and partly executed): the state-safe concurrency foundation this
  bundle consumes — D-1 (progress state as a derived projection, never committed
  at dispatch), D-2 (the `Planwright-Task` trailer), D-3 (runtime dispatch marker
  in the advisory-lock dir under `${CLAUDE_PLUGIN_DATA}`; selection reads live
  truth; snapshot refreshed only by reconcile), D-4 (one advisory-lock primitive,
  branch ref as fence). REQ-A1.1 consumes this as authoritative.
- **bootstrap spec** (`specs/bootstrap/`): the stateless step machine (D-7),
  one-unit-per-step + tower parallelism (D-8), the per-spec lock (D-10),
  control-tower dispatch and the four backends (D-38, REQ-F1.8),
  positive-evidence-of-death orphan handling (REQ-F1.1), native worktree
  placement (D-37), the config model (D-33), and the carried hard invariants
  (D-26).
- **customization-overlay spec** (`specs/customization-overlay/`): the four-layer
  overlay model (D-1) and the `review_sequence` knob precedent (D-6) the
  backend/fleet knobs resolve through.
- **Prior art mined for patterns (no framework added)** — Temporal
  (`continue-as-new` = facet C auto-heal; workflow/activity = orchestrator/worker);
  LSP/DAP (capability advertisement, §D); ISA-18.2 alarm rationalization (the
  decision queue, facet E); Kubernetes level-triggered reconcile and the actor
  model (consumed via the sibling contract). See [[workflows-not-plugin-invocable]]:
  Claude Code primitives only.
- **Doctrine** — `customization-boundary`, `finding-categorization`,
  `security-posture`, `proportionality`, `spec-format`, `interaction-style`,
  `research-rigor`, `decision-domains`: the meta-spec and rules this bundle
  conforms to and cites.
