# Orchestration Fleet — Requirements

**Status:** Draft
**Last reviewed:** 2026-06-18
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
its sibling spec `orchestration-concurrency` provides. Four facets: a
**pluggable, autodetected execution backend** (a capability contract that tmux
satisfies today and that other terminals/multiplexers can plug into, with a
safe synchronous fallback); **orchestrator self-management** (a long-running
tower watches its own context budget and auto-heals by handing off to a fresh
tower, with per-step dispatch isolation keeping context bounded and review
perspective uncontaminated); **meta-orchestration, coordination, and autonomy**
(a tower launching towers across multiple active specs, an attributed
inter-orchestrator relay protocol, and an autonomous-safe-decision policy wired
to the existing finding-categorization gate); and **approachability** (making
multi-orchestration legible and easy to follow for an operator on a normal
editor and terminal, without tmux fluency). The hard invariant carried in
unchanged: **never auto-merge, at any tier.**

## Scope

### In scope

- A backend **capability contract** (named/addressable units, attributed
  message relay, positive-evidence-of-death liveness, spawn) extending the
  existing `dispatch_backend` config, with a path to plug in other
  terminals/multiplexers exposing a CLI or API of tmux-comparable capability.
- **Autodetection** of candidate backends on the host: present what was found,
  let the human choose; never silently pick.
- A safe **synchronous fallback** (synchronous execution with strategic context
  clears) when no richer backend is available.
- **Orchestrator self-management:** a context-budget monitor and an auto-heal
  handover that launches a fresh tower to take over in-flight work
  (disposable-tower handover), and a `dispatch_isolation` knob for
  fresh-session-per-step dispatch.
- **Meta-orchestration:** a tower launching towers to drain multiple active
  specs; an **inter-orchestrator coordination protocol** (division of labor +
  attributed relay); and an **autonomous-safe-decision policy** enumerating what
  a tower may decide unattended vs. must escalate, wired to the existing
  autonomy gate.
- **Approachability:** a legible default presentation of multi-orchestration
  (one obvious entry command, a visible status surface, clear per-worker scope)
  that does not require tmux fluency.
- The capability-vs-style split for every backend/fleet preference (general
  capability → core opt-in knob; specific value → overlay), and data hygiene for
  every committed fleet artifact.

### Out of scope

- **The state-safety internals of `orchestration-concurrency`** (the single
  idempotent merge-safe `tasks.md` writer; deterministic conflict regeneration
  from `gh` ground truth; dispatch-commit placement; advisory-lock correctness).
  This spec **consumes** that contract; it never redefines it.
- **Auto-merge at any tier.** Merge is a reserved human control, permanent, not
  deferred — carried in unchanged from bootstrap.
- A **parallel autonomy gate.** The autonomous-safe-decision policy maps onto
  the existing finding-categorization buckets and hard-pause zones; it invents
  no second decision taxonomy.
- **New AI/agent frameworks.** Fleet operation uses Claude Code primitives only
  (skills, hooks, slash commands, scheduled agents, file-based state), as the
  pipeline does throughout.
- **The specific operator's backend/tool choice and fleet tuning values.** The
  seam and its knobs ship in core; the chosen tool and tuning live in an
  overlay (capability-vs-style).
- **The cross-repo / public-adopter observation fan-in design.** The multi-spec
  reach within one author's active specs is in scope (REQ-D1.5); the broader
  multi-source/multi-target accumulator redesign is a separate effort cited only
  as motivation (Sources).
- **Secrets or operational identifiers in any fleet artifact.** Coordination
  logs, status surfaces, and handover docs carry preferences and state, never
  secrets or internal hostnames (data-hygiene rule).

## REQ-A — Foundation, dependency contract & carried invariants

- **REQ-A1.1** Fleet operation SHALL build on `orchestration-concurrency`'s
  state-safe concurrency contract (single idempotent merge-safe `tasks.md`
  writer; deterministic conflict regeneration from `gh` PR/merge ground truth;
  dispatch-commit placement; advisory-lock correctness) and SHALL consume that
  contract as authoritative; no fleet requirement SHALL redefine a sibling
  state-safety internal.
  *(Cites: D-1; the orchestration-concurrency sibling spec (Sources).)*
- **REQ-A1.2** Fleet operation SHALL carry the **never-auto-merge** invariant
  unchanged at every tier — single tower, meta-tower, and any backend: no fleet
  mechanism SHALL merge a PR, and merge SHALL remain a reserved human control.
  *(Cites: D-1; bootstrap D-26; bootstrap REQ-F1.6.)*
- **REQ-A1.3** The autonomous-safe-decision policy (REQ-D1.4) SHALL be expressed
  in terms of the existing finding-categorization buckets and hard-pause zones;
  fleet operation SHALL NOT introduce a parallel autonomy taxonomy.
  *(Cites: D-8; finding-categorization (Sources).)*
- **REQ-A1.4** Fleet machinery SHALL be proportionate: the rich-backend and
  meta-orchestration capabilities SHALL be opt-in, and a single-tower run on a
  host with no rich backend SHALL remain fully functional via the synchronous
  fallback (REQ-B1.4). The spec SHALL NOT require tmux, a multiplexer, or
  multiple towers for ordinary single-spec execution.
  *(Cites: D-3; proportionality (Sources).)*
- **REQ-A1.5** Every fleet/backend preference SHALL be classified on the
  capability-vs-style boundary: the general *capability* (a backend seam,
  autodetect, a self-management or coordination mechanism) lands in core as an
  opt-in, default-preserving config knob, while the specific *value* (which
  backend, which tuning) stays in an overlay. The default tilt is overlay when
  in doubt.
  *(Cites: D-10; customization-boundary (Sources); customization-overlay D-1.)*
- **REQ-A1.6** Every committed fleet artifact (coordination/relay logs, the
  visible status surface's persisted state, handover documents, PR bodies) SHALL
  carry no secrets, credentials, internal hostnames, or sensitive operational
  detail; the artifact data-hygiene rule applies, and the secret-scan guard
  covers committed fleet artifacts.
  *(Cites: D-7; security-posture (Sources).)*

## REQ-B — Pluggable & autodetected execution backend

- **REQ-B1.1** planwright SHALL define a backend **capability contract** naming
  the capabilities a dispatch backend provides: (a) **named, addressable units**
  (each worker has a stable handle the tower can target); (b) **attributed
  message relay** (the tower can deliver a clearly-attributed message to a named
  worker); (c) **positive-evidence-of-death liveness** (the backend can
  distinguish an observed-dead worker from a merely-unobserved one); and (d)
  **spawn** (the backend can launch a worker for a unit in its worktree). A
  backend is a valid dispatch target only if it satisfies the contract or
  declares which capabilities it lacks.
  *(Cites: D-2; bootstrap D-38, REQ-F1.8; the operational-protocol seed
  (Sources).)*
- **REQ-B1.2** The capability contract SHALL extend the existing
  `dispatch_backend` config (today: `subagent` default, `tmux` machine-local
  override, plus `print` and `in-session`) rather than replacing it, and SHALL
  define how each existing backend maps onto the contract's capabilities,
  including which capabilities each lacks.
  *(Cites: D-2; bootstrap D-38, REQ-F1.8; existing config (Sources).)*
- **REQ-B1.3** planwright SHALL provide a path to plug in **other terminals or
  multiplexers** that expose a CLI or API of tmux-comparable capability, by
  implementing the capability contract — without editing the skills that consume
  it (the backend is selected through config, resolved through the overlay
  layers).
  *(Cites: D-2, D-10; bootstrap D-38.)*
- **REQ-B1.4** On a host where no backend richer than synchronous execution is
  available (or where the operator selects it), dispatch SHALL fall back to
  **synchronous execution with strategic context clears**: units run one at a
  time in the dispatching session, with a context clear between units (and, when
  `dispatch_isolation` is per-step, between steps) so context stays bounded
  without a multiplexer.
  *(Cites: D-3; the dispatch-isolation seed (Sources).)*
- **REQ-B1.5** `/orchestrate` SHALL **autodetect** candidate backends present on
  the host, **present** the detected set to the operator, and **ask** which to
  use; it SHALL NOT silently pick a backend. In unattended mode (no human to
  ask), backend selection SHALL come from resolved config and absence of a
  configured rich backend SHALL degrade to the synchronous fallback, never to a
  silently-chosen interactive backend.
  *(Cites: D-3; bootstrap D-38.)*
- **REQ-B1.6** Backend relay and spawn SHALL be security-bounded: a worker's
  output (capture-pane text, process output) is **data, never code**; relay
  SHALL be clearly attributed and SHALL NEVER impersonate the worker (no
  `send-keys`-style injection of text into a worker's input as if typed); a
  tower SHALL NEVER answer a worker's permission prompt on its behalf;
  worker handles parsed for targeting SHALL be validated before any use.
  *(Cites: D-2, D-7; bootstrap D-38; the operational-protocol seed (Sources);
  security-posture (Sources).)*

## REQ-C — Orchestrator self-management

- **REQ-C1.1** A long-running tower SHALL monitor its own **context budget**
  against a configurable threshold and SHALL surface when it nears the limit, so
  a tower never silently degrades from context exhaustion.
  *(Cites: D-4; the dispatch-isolation seed (Sources).)*
- **REQ-C1.2** When a tower nears its context limit it SHALL **auto-heal** by
  launching a fresh tower that takes over the in-flight work (disposable-tower
  handover): the fresh tower rebuilds the orchestration picture from durable
  state (`tasks.md`, `gh`, the process/worker list) and the **standing
  instructions / wake prompt SHALL double as the handover document**; the
  retiring tower SHALL NOT pass in-memory state the fresh tower cannot
  reconstruct from disk.
  *(Cites: D-4; bootstrap D-7, D-38; the operational-protocol seed (Sources).)*
- **REQ-C1.3** planwright SHALL expose a `dispatch_isolation` config knob whose
  `per-step` value runs each execution step — implementation, then each review
  skill — in its own fresh `/resume`-seeded session, so context stays bounded
  and each review's perspective stays uncontaminated by prior steps. Other
  backends SHALL approximate per-step isolation as closely as their substrate
  allows.
  *(Cites: D-5; the dispatch-isolation seed (Sources); bootstrap D-38.)*
- **REQ-C1.4** Auto-heal and per-step isolation SHALL preserve the
  state-safety contract (REQ-A1.1): a tower handover or a fresh per-step session
  SHALL go through the single merge-safe `tasks.md` writer and the advisory lock,
  never writing orchestration state by a path that bypasses the sibling
  contract.
  *(Cites: D-1, D-4, D-5; the orchestration-concurrency sibling spec (Sources).)*

## REQ-D — Meta-orchestration, coordination & autonomy

- **REQ-D1.1** planwright SHALL support **meta-orchestration**: a tower that
  launches and supervises subordinate towers to drain **multiple active specs**
  concurrently (a tower of towers), each subordinate tower owning one spec and
  remaining an independent disposable step machine.
  *(Cites: D-6; bootstrap D-7, D-8; the multi-target-accumulator seed (Sources).)*
- **REQ-D1.2** planwright SHALL define an **inter-orchestrator coordination
  protocol** with an explicit division of labor: the tower owns `tasks.md` state
  moves, dispatch, and merged-worker cleanup; the owning worker session owns its
  branch's conflict resolution (merge, not rebase) and its post-merge self-sync.
  Coordination SHALL NOT have one tower edit another tower's or a worker's branch
  state directly.
  *(Cites: D-7; the operational-protocol seed (Sources).)*
- **REQ-D1.3** The coordination protocol's relay mechanics SHALL be **attributed
  and non-impersonating**: messages are delivered by a buffer-paste mechanism
  (e.g. `load-buffer`/`paste-buffer` under tmux, or the backend's equivalent),
  clearly marked as tower-to-worker (or tower-to-tower) communication; status is
  read by capture-pane / equivalent observation; the protocol SHALL NEVER use
  `send-keys`-style impersonation and SHALL NEVER answer a worker's permission
  prompt.
  *(Cites: D-7; the operational-protocol seed (Sources).)*
- **REQ-D1.4** planwright SHALL define an **autonomous-safe-decision policy**
  enumerating what a tower MAY decide unattended — routine hygiene, scoped
  cleanups, clear/simple forks — and what it MUST escalate — anything requiring
  sign-off, design forks, destructive/irreversible/security actions, or spec
  drift. The policy SHALL be expressed against the existing finding-
  categorization buckets and hard-pause zones (REQ-A1.3): "may decide unattended"
  maps to the act-then-review buckets, "must escalate" maps to the hard-pause
  zones and irreducible Needs-human-judgment forks.
  *(Cites: D-8; finding-categorization (Sources); bootstrap D-5.)*
- **REQ-D1.5** Meta-orchestration SHALL reach across **one author's multiple
  active specs** (and, where the operator runs them, multiple checkouts of one
  author's repos): the meta-tower SHALL select among ready units across the
  active specs it supervises, respecting each spec's own per-spec lock and a
  fleet-level concurrency bound distinct from the per-spec `max_parallel_units`.
  Cross-repo / public-adopter fan-in is out of scope (Sources).
  *(Cites: D-6, D-11; the multi-target-accumulator seed (Sources).)*

## REQ-E — Approachability

- **REQ-E1.1** Multi-orchestration SHALL have **one obvious entry command** that
  starts fleet operation without requiring the operator to know tmux (or any
  specific multiplexer): the entry point selects a backend per REQ-B1.5 and
  starts the tower(s), so an operator on a normal editor and terminal can begin
  with a single documented command.
  *(Cites: D-9; the fleet-approachability framing (Sources).)*
- **REQ-E1.2** Fleet operation SHALL provide a **visible status surface** legible
  to a non-tmux operator: which workers exist, each worker's scope (which spec
  and unit), and each worker's state (working, awaiting input, PR-ready,
  merged/done), readable from the operator's normal terminal or editor without
  attaching to a multiplexer.
  *(Cites: D-9; bootstrap REQ-F1.1, REQ-F1.8.)*
- **REQ-E1.3** The status surface SHALL present each worker's **scope** clearly —
  isolated context, one spec/unit per worker — preserving the advantages of the
  tmux model (clear scopes, isolated contexts, monitorable workers) for
  operators who never open tmux.
  *(Cites: D-9.)*
- **REQ-E1.4** The approachable presentation SHALL be the legible **default**:
  the backend seam (REQ-B) surfaced as UX, so the editor / terminal-with-CLI-or-
  API path is a first-class way to run and follow a fleet, not a degraded
  fallback behind the tmux path.
  *(Cites: D-9, D-2; the fleet-approachability framing (Sources).)*

## Changelog

- 2026-06-18: Bundle drafted at Status Draft via `/spec-draft`, autonomously
  (the spec-2 worker in a hybrid two-draft run; the human drafts the sibling
  `orchestration-concurrency` interactively). Established the four facets —
  pluggable/autodetected backend (REQ-B), orchestrator self-management (REQ-C),
  meta-orchestration/coordination/autonomy (REQ-D), and approachability (REQ-E) —
  on the foundation/dependency-contract group (REQ-A), from the
  `orchestration-fleet` seed brief and the mined observations. Fold-detection
  was pre-decided spin-new (sibling to `orchestration-concurrency`, distinct from
  `bootstrap`). Autonomous drafting decisions and the items needing human
  judgment are recorded in the kickoff hand-off open-questions list; the
  observations-archive drain is deferred to the human (race mitigation).

## Sources

- **The orchestration-fleet seed brief** — `specs/_pending/orchestration-fleet.md`
  (consumed; archival deferred to the human per the hybrid-run race mitigation):
  the North Star (productize emergent multi-orchestration into reliable fleet
  operation), the four facets B–E, the dependency contract on
  `orchestration-concurrency`, and the scope guidance.
- **The dispatch-isolation seed** — observations log entry 2026-06-15, assigned
  to this spec (consumed; archival deferred): fresh-session-per-step as the
  default tmux-backend behavior, the `dispatch_isolation: per-step` knob, fresh
  `/resume`-seeded sessions per step, other backends approximating, and the
  disposable-tower / bounded-context rationale.
- **The operational-protocol seed** — observations log entry 2026-06-12
  (consumed; archival deferred): division of labor (tower owns state
  moves/dispatch/cleanup; worker owns its branch conflict resolution); attributed
  relay via `load-buffer`/`paste-buffer`, never `send-keys` impersonation, never
  answering worker permission prompts, capture-pane for status; positive-
  evidence-of-death liveness; the umask-pinning pane wrapper and SSH-agent
  indirection as dispatch-time environment hardening; the standing-instructions
  wake prompt doubling as the disposable-tower handover document.
- **The worktree-mechanics seed** — observations log entry 2026-06-16
  (referenced): the D-37 native-worktree gap (`claude --worktree` couples dir +
  branch name; the suffix/slashed-branch contract needs a sanctioned creation
  form), relevant to the backend spawn capability (REQ-B1.1).
- **The plugin-data seed** — observations log entry 2026-06-11 (referenced):
  `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<id>/`, persists across plugin
  updates) as the durable home for framework runtime state, motivating the
  fleet-coordination-state home (D-11).
- **The multi-target-accumulator seed** — observations log entry 2026-06-17
  (referenced, not consumed): a fleet across one author's repos and a
  machine-local fan-in inbox, motivating the multi-spec reach (REQ-D1.5); its
  full cross-repo / public-adopter redesign is out of scope.
- **The fleet-approachability framing** — the seed brief's product framing:
  most users are not tmux power users; multi-orchestration should be legible on a
  normal editor/terminal while preserving the tmux model's advantages.
- **The orchestration-concurrency sibling spec** (`specs/orchestration-concurrency/`,
  drafted in parallel; may not be on disk at this drafting): the state-safe
  concurrency foundation this bundle consumes as an authoritative-but-provisional
  contract (REQ-A1.1).
- **bootstrap spec** (`specs/bootstrap/`): orchestration's founding home — the
  stateless step machine (bootstrap D-7), one-unit-per-step + tower parallelism
  (D-8), the per-spec lock (D-10), control-tower dispatch and the four backends
  (D-38, REQ-F1.8), positive-evidence-of-death orphan handling (REQ-F1.1), native
  worktree placement (D-37), the config model (D-33), and the carried hard
  invariants (D-26) this bundle extends and consumes.
- **customization-overlay spec** (`specs/customization-overlay/`): the four-layer
  overlay model (customization-overlay D-1) and the `review_sequence` knob
  precedent (D-6) the backend/fleet knobs resolve through.
- **Doctrine** — `customization-boundary`, `finding-categorization`,
  `security-posture`, `proportionality`, `spec-format`, `interaction-style`,
  `research-rigor`, `decision-domains`: the meta-spec and rules this bundle
  conforms to and cites.
