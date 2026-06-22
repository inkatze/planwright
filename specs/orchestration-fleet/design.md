# Orchestration Fleet — Design

**Status:** Draft
**Last reviewed:** 2026-06-18
**Format-version:** 1

Origin-tag legend: `N` = new decision minted in this bundle; `N (extends
<foreign>)` = a new decision extending a foreign-namespace decision, named in
the body. Foreign IDs are namespace-qualified (for example `bootstrap D-38`,
`customization-overlay D-1`). This bundle was drafted autonomously (the spec-2
worker in a hybrid two-draft run); decisions whose default needs human
confirmation, and decisions that depend on the sibling `orchestration-concurrency`
spec, are flagged in the body and collected in the kickoff hand-off
open-questions list.

## Decision log

### D-1: Consume `orchestration-concurrency` as an authoritative-but-provisional contract  (N)

**Decision:** Fleet operation builds on the sibling `orchestration-concurrency`
spec's state-safe concurrency contract — a single idempotent merge-safe
`tasks.md` section writer, deterministic conflict regeneration from `gh`
PR/merge ground truth (not ours/theirs/union), dispatch-commit placement so
sibling/foreign-spec dispatch commits do not ride along as worker-branch
ancestors, and one advisory-lock primitive — and **consumes** it. This bundle
never re-decides a sibling state-safety internal. Where a fleet decision needs
sibling confirmation, it is recorded as an open question rather than resolved
here. The carried hard invariant **never auto-merge** rides along unchanged at
every fleet tier.

**Alternatives considered:**
- Re-specify the state-safety internals here so the fleet bundle is
  self-contained. Rejected because: it duplicates and would drift from the
  sibling's authoritative contract, and the seed brief explicitly scopes those
  internals out ("consume the contract, never redefine it").
- Defer all fleet work until `orchestration-concurrency` is merged. Rejected
  because: the two specs are drafted in parallel by design; the fleet layer can
  be specified against the contract's shape now, with sibling-dependent points
  marked, and executed once the contract lands.

**Chosen because:** the division mirrors the pipeline's own layering — a safety
foundation underneath, a capability layer on top — and keeps each spec
independently ownable. Treating the contract as *provisional* (open questions,
not silent assumptions) is the honest stance while the sibling is still in
draft.

### D-2: A backend capability contract, not a backend list  (N (extends bootstrap D-38))

**Decision:** Define a backend **capability contract** — the named capabilities
a dispatch backend must provide — rather than hardcoding a fixed set of
backends. The four capabilities: (a) **named, addressable units** (a stable
worker handle the tower can target); (b) **attributed message relay** (deliver a
clearly-attributed message to a named worker); (c) **positive-evidence-of-death
liveness** (distinguish an observed-dead worker from a merely-unobserved one,
the bootstrap REQ-F1.1 predicate); and (d) **spawn** (launch a worker for a unit
in its worktree). The existing backends (`subagent`, `tmux`, `print`,
`in-session`) are re-described as contract implementations with their declared
capability gaps; a new terminal/multiplexer becomes a backend by implementing
the contract. Backend selection stays in `dispatch_backend`, resolved through
the overlay layers.

**Alternatives considered:**
- Keep extending the hardcoded backend enum in bootstrap D-38 for each new
  tool. Rejected because: every new terminal forces a core edit to the dispatch
  skill, which is exactly the no-fork pressure the overlay mechanism exists to
  relieve; the capability surface is small and stable enough to name as a
  contract.
- A full plugin-API with code injection. Rejected because: planwright stays
  declarative (config + scripts), not an arbitrary-code extension host
  (proportionality, and the overlay mechanism's declarative-only posture); a
  capability contract satisfied by a small adapter is the lighter seam.

**Chosen because:** naming the capabilities turns "which backends exist" into
"what a backend must do", so tmux, subagents, and a future terminal are all
just contract implementations — and the contract is the precise surface the
approachability facet (D-9) and the autodetect step (D-3) build on. It extends
bootstrap D-38 (which already enumerates four backends and their capability
gaps) into an open contract rather than replacing it.

### D-3: Autodetect-and-ask, with a synchronous safe fallback  (N)

**Decision:** `/orchestrate` autodetects candidate backends present on the host
(is tmux available? a subagent runtime? a configured pluggable backend?),
presents the detected set, and **asks** the operator which to use — it never
silently picks. When nothing richer than synchronous execution is available, or
the operator chooses it, dispatch falls back to **synchronous execution with
strategic context clears**: units (and, under per-step isolation, steps) run one
at a time in the dispatching session with a context clear between them, so
context stays bounded without any multiplexer. In unattended mode the selection
comes from resolved config and a missing rich backend degrades to the
synchronous fallback — never to a silently-chosen interactive backend.

**Alternatives considered:**
- Silently pick the richest detected backend. Rejected because: backend choice
  has operator-visible consequences (windows spawned, context model, where
  prompts surface); the seed brief is explicit ("present what was found, and
  ask — don't silently pick"), and silent selection violates the
  interaction-style decisions-as-selectors posture.
- No fallback: require a rich backend. Rejected because: it breaks
  proportionality and the approachability goal — an operator on a plain terminal
  with no multiplexer must still be able to run a spec.

**Chosen because:** autodetect removes the configuration burden (the operator
sees what their host offers), asking keeps the operator-visible choice with the
operator, and the synchronous fallback guarantees fleet operation degrades to a
working single-stream mode everywhere. The fallback's strategic context clears
are the substrate-appropriate form of the per-step isolation D-5 generalizes.

### D-4: Context-budget self-monitoring + disposable-tower auto-heal  (N (extends bootstrap D-7))

**Decision:** A long-running tower monitors its own **context budget** against a
configurable threshold and, as it nears the limit, **auto-heals** by launching a
fresh tower that takes over the in-flight work. The handover carries no
in-memory state: the fresh tower rebuilds the orchestration picture from durable
state (`tasks.md`, `gh`, the process/worker list), exactly as the disposable
tower already does on any restart, and the tower's **standing instructions /
wake prompt doubles as the handover document** (no second artifact to keep in
sync). The retiring tower's only job is to start the replacement and stop.

**Alternatives considered:**
- A long-lived tower that compacts/summarizes its own context in place.
  Rejected because: it reintroduces the fragile long-running-state model
  bootstrap D-7 exists to avoid, and summarization silently loses fidelity the
  next decision may need; rebuild-from-disk is lossless because the disk is the
  source of truth.
- A dedicated handover artifact distinct from the wake prompt. Rejected
  because: two artifacts drift; the operational-protocol seed already found that
  the standing-instructions wake prompt *is* the handover document, so reuse it.

**Chosen because:** auto-heal is just "the disposable tower, triggered by a
context-budget signal instead of a human": it reuses bootstrap D-7's
rebuild-from-disk statelessness, so the resilience property falls out of the
existing design rather than needing new state machinery. The exact
context-budget signal (how "nearing the limit" is measured) is a Claude-Code-
capability question flagged as an open question.

### D-5: Per-step dispatch isolation as a core knob, default `per-step`  (N (extends bootstrap D-38))

**Decision:** Expose a `dispatch_isolation` config knob. Its `per-step` value
runs each execution step — implementation, then each review skill in the
`review_sequence` gauntlet — in its own fresh `/resume`-seeded session, so
context stays bounded and each review's perspective stays uncontaminated by the
implementation's (or a prior review's) context. The other dispatch backends
approximate per-step isolation as closely as their substrate allows (the
synchronous fallback via context clears between steps, D-3). Per the recorded
human decision (the dispatch-isolation seed, Diego 2026-06-15), the **default is
`per-step`** for backends that support session isolation; `per-unit` (one worker
session for the whole unit, today's behavior) remains a supported value.

**Alternatives considered:**
- Default `per-unit` (strictly default-preserving, per the customization-
  boundary tilt), with `per-step` opt-in. Rejected as the *recorded* default
  because: the seed is an explicit human decision assigned to this spec to make
  per-step the default; but this is the live tension (a default behavior
  change), so it is carried as an open question for confirmation at kickoff, and
  it requires a bootstrap D-38 amendment.
- Per-step isolation hardcoded (no knob). Rejected because: capability-vs-style
  (D-10) puts the *mechanism* in core as a knob; an operator on a constrained
  host may want `per-unit`, so the value must stay settable.

**Chosen because:** per-step isolation is the customization-boundary doc's own
named candidate core capability — mechanism and intended default both general —
so it lands as a core knob, and the assigned human decision sets its default to
`per-step`. The two flagged caveats (the default-vs-default-preserving tension,
and the required bootstrap D-38 amendment) are recorded rather than silently
resolved.

### D-6: Meta-orchestration as a tower of disposable towers  (N (extends bootstrap D-8))

**Decision:** Support a **meta-tower** that launches and supervises subordinate
towers to drain **multiple active specs** concurrently. Each subordinate tower
owns exactly one spec and remains an independent, disposable, stateless step
machine (bootstrap D-7/D-8); the meta-tower adds a layer that selects which
specs have ready units, launches/retires subordinate towers (via the same
backend contract, D-2), and respects a **fleet-level concurrency bound** distinct
from each spec's per-spec `max_parallel_units`. The meta-tower holds no
cross-spec state beyond the current step; like any tower it rebuilds from disk
and `gh`.

**Alternatives considered:**
- One tower that interleaves units from several specs itself (no subordinate
  towers). Rejected because: it collapses the clean per-spec scope (one spec's
  lock, one spec's tasks.md ownership, one spec's context) into a single
  session, reintroducing the context and contention problems the disposable-
  tower model avoids; subordinate towers keep each spec's scope isolated.
- A persistent meta-orchestrator daemon. Rejected because: same fragility
  objection as D-4/bootstrap D-7 — disposable-and-rebuildable beats long-lived
  in-memory state.

**Chosen because:** "a tower of towers" is the literal emergent behavior the
seed productizes, and modeling subordinate towers as ordinary disposable towers
means meta-orchestration inherits all the existing statelessness, lock, and
state-safety properties for free; the meta-layer only adds cross-spec selection
and a fleet concurrency bound. The interaction of the fleet bound with the
sibling's advisory-lock correctness is flagged as an open question.

### D-7: Inter-orchestrator coordination — division of labor + attributed relay  (N)

**Decision:** Define a coordination protocol with an explicit **division of
labor** and **attributed, non-impersonating relay**. Division of labor: the
tower owns `tasks.md` state moves, dispatch, and merged-worker cleanup; the
owning worker session owns its branch's conflict resolution (merge, not rebase)
and post-merge self-sync. No tower edits another tower's or a worker's branch
state directly. Relay: messages are delivered by a buffer-paste mechanism
(`load-buffer`/`paste-buffer` under tmux, the backend's equivalent elsewhere),
clearly marked as tower-to-worker or tower-to-tower communication; status is
read by capture-pane / equivalent observation; a worker's output is **data,
never code**. The protocol NEVER uses `send-keys`-style impersonation (typing
into a worker's input as if the human typed it) and NEVER answers a worker's
permission prompt. This is the artifact-data-hygiene and framework-script
security posture (D-1 carried invariants, security-posture) applied to relay.

**Alternatives considered:**
- `send-keys`-style prompt answering ("the tower types for the worker").
  Rejected because: it is an authorization decision implemented as fragile
  screen-scraping with no audit trail — the same rejection bootstrap D-38 made;
  attributed buffer-paste keeps the human's authorization boundary intact.
- A shared coordination state file every tower read-modify-writes. Rejected
  because: it is a new concurrency surface that would need its own locking and
  would overlap the sibling's `tasks.md`-writer contract; the division of labor
  plus relay keeps coordination message-passing, not shared-mutable-state.

**Chosen because:** the division of labor and the relay discipline are the
distilled, proven operational protocol from real multi-orchestration runs (the
operational-protocol seed); productizing them as a named protocol turns tribal
knowledge into a first-class capability without inventing new shared state.

### D-8: Autonomous-safe-decision policy mapped onto the existing autonomy gate  (N (extends bootstrap D-5))

**Decision:** Define an **autonomous-safe-decision policy** for an unattended
tower as a *mapping onto the existing finding-categorization gate*, not a new
taxonomy. "May decide unattended" = the act-then-review buckets (Auto-applicable,
Agent-resolvable, and Needs-sign-off applied-on-branch-with-checklist) plus
routine operational hygiene (scoped cleanups of merged workers, answering
routine worker prompts pre-approved by the worker-settings profile).
"Must escalate / pause" = the existing hard-pause zones (security-sensitive code,
migrations/destructive ops, CI config, lockfiles, secrets) and irreducible
Needs-human-judgment forks (design forks, spec drift, sign-off-class decisions
the human reserves). The policy is a doctrine/skill description that *cites* the
gate's buckets and zones; it adds no parallel decision categories.

**Alternatives considered:**
- A fresh "fleet autonomy" taxonomy enumerating tower-specific safe/unsafe
  actions. Rejected because: the seed brief is explicit ("wire this to the
  finding-categorization autonomy gate, do not invent a parallel one"), and a
  second taxonomy would drift from the first and double the maintenance surface.
- Allow the unattended tower to decide everything short of merge. Rejected
  because: the hard-pause zones exist precisely because some decisions are
  unsafe to take autonomously regardless of tier; the never-auto-merge invariant
  is the floor, not the whole ceiling.

**Chosen because:** the autonomy gate already encodes "what an agent may do
without asking", so the tower's unattended policy is that same gate read at the
orchestration tier; reusing it keeps one source of truth for autonomy and
inherits its hard-pause safety zones unchanged.

### D-9: Approachability — a legible default presentation over the backend seam  (N)

**Decision:** Make multi-orchestration legible to a non-tmux operator with three
elements, all built on the backend seam (D-2): **one obvious entry command**
that selects a backend (autodetect-and-ask, D-3) and starts the tower(s); a
**visible status surface** showing which workers exist, each worker's scope
(spec + unit), and each worker's state (working / awaiting input / PR-ready /
merged), readable from a normal terminal or editor without attaching to a
multiplexer; and a clear **per-worker scope** presentation preserving the tmux
model's advantages (isolated context, monitorable workers) for operators who
never open tmux. This approachable path is the **default** presentation, not a
degraded fallback behind the tmux path. The concrete surface form (a new
`/fleet`-style entry skill vs. a flag on `/orchestrate`; a CLI status command
vs. a rendered file vs. the existing inbox/status-bar mechanism) is flagged as
an open question; the requirement fixes the capability, not the rendering.

**Alternatives considered:**
- Document the tmux workflow better and stop there. Rejected because: the seed's
  product framing is that most users are not tmux power users; better docs for
  tmux do not make the editor/terminal operator first-class.
- A full GUI/web dashboard. Rejected for v1 because: it is disproportionate to
  the need and pulls in a delivery surface (a server, a browser) the pipeline
  deliberately avoids; a terminal/editor-legible status surface meets the goal
  with Claude Code primitives.

**Chosen because:** the backend seam already abstracts "how workers run", so
surfacing it as UX — one entry command, a legible status view, clear scopes — is
the smallest thing that makes the editor/terminal operator first-class while
preserving the tmux model's real advantages. Fixing the capability and deferring
the rendering keeps the requirement honest about what is decided.

### D-10: Capability-vs-style split for every backend/fleet preference  (N (extends customization-overlay D-1))

**Decision:** Every fleet/backend preference is classified on the
capability-vs-style boundary. The general *capability* — the backend seam,
autodetect, the self-management and coordination mechanisms, the knobs
themselves (`dispatch_backend`, `dispatch_isolation`, the context-budget
threshold, the fleet concurrency bound) — lands in core as opt-in,
default-preserving config knobs resolved through the four overlay layers
(customization-overlay D-1). The specific *value* — which backend, which tuning
numbers, which isolation mode on this machine — stays in an overlay. Default
tilt is overlay when in doubt.

**Alternatives considered:**
- Bake a specific backend/tuning default into core (e.g. hardcode tmux as the
  rich backend). Rejected because: it makes core less general for adopters
  without tmux and pushes one operator's taste into the shared observation
  stream — exactly the cost customization-boundary warns against.
- Leave fleet preferences in personal memory / dotfiles `CLAUDE.md` (the status
  quo). Rejected because: that is the ad-hoc home the overlay mechanism exists to
  replace, and skills cannot apply preferences they cannot resolve.

**Chosen because:** the boundary runs *through* each fleet feature (a general
mechanism plus a specific value), which is exactly the customization-boundary
doc's central insight; putting the mechanism in core as a knob and the value in
an overlay keeps core general and each fork's observations mergeable upstream.
This is the `review_sequence` precedent (customization-overlay D-6) applied to
the fleet's knobs.

### D-11: A durable home for fleet coordination/runtime state  (N)

**Decision:** Fleet coordination and runtime state that must persist across
tower restarts and plugin updates (the worker/scope registry the status surface
reads, the fleet-level concurrency accounting, any meta-tower bookkeeping) lives
in a durable, plugin-update-stable location resolved through the
`${CLAUDE_PLUGIN_DATA}` chain (`~/.claude/plugins/data/<id>/`, with the
writer-mode fallback the overlay resolvers already use), **not** under the
ephemeral plugin root. The **advisory-lock home itself is the sibling
`orchestration-concurrency`'s decision** (one lock primitive); this bundle only
sites the *fleet-coordination* state and defers the lock-home question to the
sibling to avoid two specs deciding one location.

**Alternatives considered:**
- Store fleet state under the plugin install root. Rejected because: the plugin
  root is ephemeral per version (the plugin-data seed); state there is lost on
  update.
- Reuse the existing `~/.claude/inbox/` heartbeat location for everything.
  Rejected (for the durable registry) because: the inbox is a cross-session
  awareness signal, not the authoritative fleet registry; the status surface
  needs a stable home it owns. (The inbox may still be a *rendering* input, D-9.)

**Chosen because:** `${CLAUDE_PLUGIN_DATA}` is the already-researched durable,
namespace-separated home for framework runtime state, and siting fleet state
there (while leaving the lock home to the sibling) keeps the two specs from
colliding on one location — the coordination this whole bundle is about, applied
to its own artifacts.

## Cross-cutting concerns

- **Coordination with the sibling, not duplication.** This bundle consumes
  `orchestration-concurrency`'s state-safety contract (D-1) and never re-decides
  it. Every point where a fleet behavior touches that contract — auto-heal and
  per-step sessions writing `tasks.md` (REQ-C1.4), the meta-tower's fleet bound
  vs. the advisory lock (D-6), the fleet-state home vs. the lock home (D-11) — is
  recorded as an open question for sibling confirmation rather than assumed.
- **Decision-domains walk.** The design phase walked the decision-domains
  catalog. Domains this spec touches and decides: *API surface design* (the
  backend capability contract is a new external interface — decided as an opt-in
  seam, D-2); *secrets & configuration* (new knobs — each must land in the
  canonical options reference, documented, default-preserving; D-10). Domains it
  touches but defers to the sibling: *concurrency* (the fleet bound and lock
  interaction — D-6, D-11, open questions). Domains where the existing gate is
  reused, not re-decided: *authn/z* (the autonomous-safe-decision policy maps
  onto the finding-categorization hard-pause zones — D-8, never a new auth
  primitive). Domains touched lightly and following convention: *observability*
  (the status surface surfaces existing state legibly — D-9). No
  storage/migration domain is crossed (no schema, no data migration).
- **Security surface.** Backend relay/spawn parses worker output and worker
  handles from potentially adversarial terminal content; the security-posture
  framework-script rules apply (worker output is data, handles validated before
  use, no impersonation, no answering permission prompts — REQ-B1.6, D-7). The
  dispatch-time environment hardening from the operational-protocol seed
  (umask-pinning pane wrapper, SSH-agent indirection liveness, pre-trusted
  worktree config paths) is the execution-time companion the execution skills
  apply; it is noted here and carried to the kickoff risk register rather than
  minted as its own requirement, since it is operational hardening of an existing
  mechanism.
- **Proportionality.** Rich backend, meta-orchestration, and the status surface
  are opt-in capabilities; ordinary single-spec execution requires none of them
  and degrades to the synchronous fallback (REQ-A1.4, D-3). The spec deliberately
  fixes capabilities and defers concrete renderings/forms (D-9) and
  sibling-dependent internals (D-1) rather than over-building.
