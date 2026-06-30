# Orchestration Fleet — Design

**Status:** Ready
**Last reviewed:** 2026-06-29
**Format-version:** 1

Origin-tag legend: `N` = new decision minted in this bundle; `N (extends
<foreign>)` = a new decision extending a foreign-namespace decision, named in
the body. Foreign IDs are namespace-qualified (for example `bootstrap D-38`,
`orchestration-concurrency D-1`, `customization-overlay D-1`). This bundle was
drafted and re-drafted at Status Draft and never activated, so its decisions were
edited in place as drafting iteration rather than via the supersede/amendment
ritual that governs Active/Done bundles; sign-off (2026-06-29) flipped it to Ready.
The 2026-06-29 re-draft folded the seed brief's 2026-06-26 design addendum
(§A–§G) and reconciled every sibling-dependent decision against the now-Active
`orchestration-concurrency` contract.

## Decision log

### D-1: Consume `orchestration-concurrency`'s derived-projection contract  (N)

**Decision:** Fleet operation builds on the sibling `orchestration-concurrency`
spec's state-safe concurrency contract and **consumes** it. The sibling's
contract, as shipped: progress/dispatch state is a **derived projection** —
`/orchestrate` writes no dispatch or progress state to `tasks.md`; the **task
branch** (the first durable act of dispatch) plus the **per-spec advisory lock**,
the **`Planwright-Task` trailer**, and a **runtime dispatch marker** in the lock
directory are the dispatch record; `tasks.md` section placement is a
level-triggered read-model snapshot reconciled from `gh`/branch/trailer ground
truth, off the worker's critical path. Because `main` carries no dispatch
commits, a worker (or subordinate-tower, or per-step) worktree cut from it
inherits nothing foreign — contamination is impossible by construction. This
bundle never re-decides a sibling state-safety internal; sibling-dependent fleet
points are recorded as open questions. The carried hard invariant **never
auto-merge** rides along unchanged at every fleet tier.

**Alternatives considered:**
- Re-specify the state-safety internals here so the fleet bundle is
  self-contained. Rejected: it duplicates and would drift from the sibling's
  authoritative contract, and the seed brief explicitly scopes those internals
  out ("consume the contract, never redefine it").
- Treat the sibling contract as provisional (its earlier "single merge-safe
  `tasks.md` writer" framing). Superseded by reality: the sibling shipped the
  derived-projection model (its D-1/D-3/D-4), which is stronger — it removes the
  contamination root cause rather than locking around it — so this bundle
  consumes the shipped contract, not the provisional sketch.

**Chosen because:** the division mirrors the pipeline's own layering — a safety
foundation underneath, a capability layer on top — and the sibling's
derived-projection model actively simplifies fleet concerns: subordinate towers
and fresh per-step sessions inherit no foreign dispatch state, auto-heal rebuilds
from the same level-triggered reconcile any restart uses, and dispatch-adjacent
fleet state (the effective-backend failover record) has a natural home outside
`tasks.md`.

### D-2: A backend capability contract with capability advertisement  (N (extends bootstrap D-38))

**Decision:** Define a backend **capability contract** — the named capabilities
a dispatch backend provides — and have each backend **advertise** which of them
it has, LSP/DAP-style, rather than hardcoding a fixed set of backends or a static
tier list. The contract is the shared **vocabulary**; advertisement is the
**negotiation**. Capabilities: (a) **named, addressable units** (a stable worker
handle); (b) **observe-in-flight** (read a worker's current state mid-task);
(c) **steer-in-flight** (inject an attributed message into a running, busy worker
without killing it); (d) **positive-evidence-of-death liveness** (the bootstrap
REQ-F1.1 predicate); and (e) **session-grade spawn** (launch a worker as a
separate top-level session — full context and harness, commits as a principal,
survives the tower's death — not a context-sharing in-harness subagent).
Observe-in-flight and steer-in-flight are first-class, not folded into a generic
"relay". Each backend advertises at minimum `{ interactive, can_observe,
can_steer_inflight, provides_attention_surface, supports_parallel }`; the
orchestrator adapts to what is advertised (a backend with `can_steer_inflight:
false` routes ambiguity to the decision queue; one with
`provides_attention_surface: true` makes planwright defer its own queue
rendering). The existing backends (`subagent`, `tmux`, `print`, `in-session`) are
re-described by their advertised sets with their declared gaps; a new
terminal/multiplexer becomes a backend by implementing/advertising the contract.
Backend selection stays in `dispatch_backend`, resolved through the overlay
layers.

**Alternatives considered:**
- Keep extending the hardcoded backend enum in bootstrap D-38 for each new tool.
  Rejected: every new terminal forces a core edit to the dispatch skill, the
  exact no-fork pressure the overlay mechanism exists to relieve.
- A fixed capability contract with no advertisement (the pre-addendum draft).
  Rejected: it special-cases backends by name and cannot express "this backend
  steers but that one only observes"; advertisement makes the orchestrator adapt
  to declared capability, collapsing N×M backend×skill integration to N+M (the
  LSP/DAP lesson) and composing cleanly with autodetect.
- A full plugin-API with code injection. Rejected: planwright stays declarative
  (config + scripts), not an arbitrary-code extension host; a capability contract
  satisfied by a small adapter is the lighter seam.

**Chosen because:** naming the capabilities turns "which backends exist" into
"what a backend must do and declare", so tmux, subagents, headless, and a future
terminal are all just advertised capability sets — and the contract is the
precise surface the approachability facet (D-9/D-12) and the degradation ladder
(D-3) build on. Splitting observe and steer out of "relay" is the addendum's
core finding: those two properties, not tmux, are what made the emergent fleet
good.

### D-3: Autodetect-and-ask, over a graceful-degradation ladder  (N)

**Decision:** `/orchestrate` autodetects candidate backends, collects each
candidate's advertised capabilities, **presents** the set, and **asks** which to
use — it never silently picks. Backends are ordered by a **graceful-degradation
ladder**, richest to safest: (1) interactive multiplexer with steer; (2)
interactive multiplexer without steer, or a headless `claude -p` session pool
(session-grade + parallel but no live steer — ambiguity routes to the queue, it
cannot be nudged once off-path, so it is **not** a quality-equivalent middle rung
and sits here, near the fallback); (3) in-harness background subagent
(constrained, parallel, no live observe/steer — today's default); (4)
**synchronous in-session execution with strategic context clears** (no
parallelism, no external substrate, so it always works — the terminal rung).
**Selection-time** descent asks. **Runtime failover** (a chosen backend dies
mid-run) descends one rung with a logged note and an `## Awaiting input` entry,
surfaced immediately when attended — never silent. The governing rule: **degrade
capability, never safety** — a descent never drops a guard (worker-settings deny
rules, never-auto-merge, never-force-push, the freshness gate); a descent that
would drop a safety property aborts instead. The effective backend after a
failover is recorded as dispatch-adjacent state spec-locally, alongside the
sibling's runtime dispatch marker (`<spec-dir>/.orchestrate/`), read by the
cross-spec attention surface via reconcile — never in `tasks.md` (D-1).

**Alternatives considered:**
- Silently pick the richest detected backend. Rejected: backend choice has
  operator-visible consequences; the seed brief is explicit ("present what was
  found, and ask"), and silent selection violates the decisions-as-selectors
  posture.
- A two-rung model (rich backend vs synchronous fallback), the pre-addendum
  draft. Rejected: it hides the real capability gradient (headless and subagent
  are distinct middle rungs with different steer/observe profiles) and has no
  runtime-failover semantics, so a mid-run backend death had no defined safe
  descent.
- Treat headless `claude -p` as the approachable-quality path. Rejected on
  operator field experience (addendum §A): headless loses live observe/steer and
  pause-ask, so it is closer to the fallback tier than to the steerable-session
  quality tier.

**Chosen because:** the ladder makes degradation a first-class, safety-preserving
behavior instead of an undefined edge; asking keeps the operator-visible choice
with the operator; and pinning the terminal synchronous rung guarantees fleet
operation always reduces to a working single-stream mode. "Degrade capability,
never safety" is the operator-stated principle that keeps failover from ever
trading correctness for liveness.

### D-4: Context-budget self-monitoring + disposable-tower auto-heal (`continue-as-new`)  (N (extends bootstrap D-7))

**Decision:** A long-running tower monitors its own **context budget** against a
configurable threshold and, as it nears the limit, **auto-heals** by launching a
fresh tower that takes over the in-flight work — the **`continue-as-new`** pattern
(Temporal): a fresh execution carrying only essential state, bounding history.
The handover carries no in-memory state: the fresh tower rebuilds from durable
state (`tasks.md` snapshot, `gh`, the branch/marker/process and worker list),
exactly as the disposable tower already does on any restart, and the tower's
**standing instructions / wake prompt doubles as the handover document** (no
second artifact to keep in sync). The handover is testable by the snapshot
question: "could a fresh tower resume from this alone?". The retiring tower's only
job is to start the replacement and stop.

**Alternatives considered:**
- A long-lived tower that compacts/summarizes its own context in place. Rejected:
  it reintroduces the fragile long-running-state model bootstrap D-7 avoids, and
  summarization silently loses fidelity; rebuild-from-disk is lossless because the
  disk is the source of truth.
- A dedicated handover artifact distinct from the wake prompt. Rejected: two
  artifacts drift; the operational-protocol seed already found the standing-
  instructions wake prompt *is* the handover document.

**Chosen because:** auto-heal is "the disposable tower, triggered by a
context-budget signal instead of a human", and the sibling's level-triggered
reconcile (D-1) means the fresh tower's rebuild is the same routine any restart
runs — the resilience property falls out of the existing design. The exact
context-budget signal (how "nearing the limit" is measured against Claude Code's
available capability) is flagged as an open question for the kickoff risk
register.

### D-5: Per-step dispatch isolation as a core knob, default `per-step`  (N (extends bootstrap D-38))

**Decision:** Expose a `dispatch_isolation` config knob. Its `per-step` value runs
each execution step — implementation, then each review skill in the
`review_sequence` gauntlet — in its own fresh `/resume`-seeded session, so context
stays bounded and each review's perspective stays uncontaminated by the
implementation's (or a prior review's) context. Other backends approximate as
their substrate allows (the synchronous terminal rung via context clears between
steps, D-3). Per the recorded human decision (the dispatch-isolation seed, Diego
2026-06-15), the **default is `per-step`** for backends that support session
isolation; `per-unit` (one worker session for the whole unit, today's behavior)
remains a supported value.

**Alternatives considered:**
- Default `per-unit` (strictly default-preserving), with `per-step` opt-in.
  Rejected as the *recorded* default: the seed is an explicit human decision
  assigned to this spec to make per-step the default. This is a default-behavior
  change carried as an open question for kickoff confirmation, and it requires a
  bootstrap D-38 amendment (cross-spec, risk-register row).
- Per-step isolation hardcoded (no knob). Rejected: capability-vs-style (D-10)
  puts the *mechanism* in core as a knob; an operator on a constrained host may
  want `per-unit`, so the value stays settable.

**Chosen because:** per-step isolation is the customization-boundary doc's own
named candidate core capability — mechanism and intended default both general —
so it lands as a core knob, and the assigned human decision sets its default. It
is also the live half of the addendum's "externally-imposed stage sequencing"
(§A): the tower owns the worker's lifecycle from outside, sequencing stages with
context clears.

### D-6: Meta-orchestration as a tower of disposable towers  (N (extends bootstrap D-8))

**Decision:** Support a **meta-tower** that launches and supervises subordinate
towers to drain **multiple active specs** concurrently. Each subordinate tower
owns exactly one spec and remains an independent, disposable, stateless step
machine (bootstrap D-7/D-8); the meta-tower adds a layer that selects which specs
have ready units (reading each spec's live derivation per the sibling D-3, not the
committed snapshot), launches/retires subordinate towers via the same backend
contract (D-2), and respects a **fleet-level concurrency bound** distinct from each
spec's per-spec `max_parallel_units`. The meta-tower holds no cross-spec state
beyond the current step; like any tower it rebuilds from disk and `gh`.

**Alternatives considered:**
- One tower that interleaves units from several specs itself (no subordinate
  towers). Rejected: it collapses the clean per-spec scope (one lock, one
  reconcile, one context) into a single session, reintroducing the context and
  contention problems the disposable-tower model avoids.
- A persistent meta-orchestrator daemon. Rejected: same fragility objection as
  D-4/bootstrap D-7 — disposable-and-rebuildable beats long-lived in-memory state.

**Chosen because:** "a tower of towers" is the literal emergent behavior the seed
productizes, and modeling subordinate towers as ordinary disposable towers means
meta-orchestration inherits all the existing statelessness, lock, and
derived-projection properties for free. The per-spec advisory lock (sibling D-4)
already serializes per-spec state moves; the fleet bound is a separate accounting
layer in the fleet-coordination state (D-11) that caps total concurrent units,
so the two do not collide — confirmed against the sibling contract rather than
left as an open question.

### D-7: Inter-orchestrator coordination — division of labor + attributed relay  (N)

**Decision:** Define a coordination protocol with an explicit **division of
labor** and **attributed, non-impersonating relay that works against a live, busy
worker**. Division of labor: the tower owns `tasks.md` reconcile (placement),
dispatch, and merged-worker cleanup; the owning worker session owns its branch's
conflict resolution (merge, not rebase) and post-merge self-sync. No tower edits
another tower's or a worker's branch state directly. Relay: messages are delivered
by a buffer-paste mechanism (`load-buffer`/`paste-buffer` under tmux, the
backend's steer-in-flight equivalent elsewhere), clearly marked as tower-to-worker
or tower-to-tower; status is read by capture-pane / equivalent observe-in-flight; a
worker's output is **data, never code**. The protocol NEVER uses `send-keys`-style
impersonation (typing into a worker's input as if the human typed it) and NEVER
answers a worker's permission prompt. This is the artifact-data-hygiene and
framework-script security posture applied to relay.

**Alternatives considered:**
- `send-keys`-style prompt answering ("the tower types for the worker"). Rejected:
  it is an authorization decision implemented as fragile screen-scraping with no
  audit trail — the same rejection bootstrap D-38 made; attributed buffer-paste
  keeps the human's authorization boundary intact.
- A shared coordination state file every tower read-modify-writes. Rejected: it is
  a new concurrency surface needing its own locking and would overlap the sibling's
  contract; the division of labor plus relay keeps coordination message-passing
  (the blackboard pattern — coordinate via shared `tasks.md` + observations log,
  never direct agent-to-agent calls), not shared-mutable-state.

**Chosen because:** the division of labor and the relay discipline are the
distilled, proven operational protocol from real multi-orchestration runs;
productizing them turns tribal knowledge into a first-class capability. The
addendum's actor-model lens (a worker = a mailbox + a status channel; Akka
ask-vs-tell = relay-question-and-await vs fire-a-nudge) is the conceptual model
for steer-in-flight; the relay's "classify capture-pane output, then respond" is
Expect's match-then-send, which guards against the lost-observability misread the
positive-evidence-of-death predicate exists to catch.

### D-8: Autonomous-safe-decision policy mapped onto the existing autonomy gate  (N (extends bootstrap D-5))

**Decision:** Define an **autonomous-safe-decision policy** for an unattended
tower as a *mapping onto the existing finding-categorization gate*, not a new
taxonomy. "May decide unattended" = the act-then-review buckets (Auto-applicable,
Agent-resolvable, Needs-sign-off applied-on-branch-with-checklist) plus routine
operational hygiene (scoped cleanups of merged workers, answering routine worker
**questions to the tower** — continue-prompts, hygiene confirmations — that the
worker-settings profile pre-approves). This is distinct from a worker's **harness
permission prompt** (the tool-permission gate), which a tower NEVER answers
(REQ-B1.7, D-7): the two senses of "prompt" do not overlap — the tower may answer
a routine *question the worker addresses to it*, never the *harness's
authorization gate*. "Must escalate / pause" =
the existing hard-pause zones (security-sensitive code, migrations/destructive
ops, CI config, lockfiles, secrets) and irreducible Needs-human-judgment forks
(design forks, spec drift, sign-off-class decisions the human reserves),
surfaced via the decision queue (D-13). The policy cites the gate's buckets and
zones; it adds no parallel categories.

**Alternatives considered:**
- A fresh "fleet autonomy" taxonomy enumerating tower-specific safe/unsafe
  actions. Rejected: the seed brief is explicit ("wire this to the
  finding-categorization gate, do not invent a parallel one"), and a second
  taxonomy would drift and double the maintenance surface.
- Allow the unattended tower to decide everything short of merge. Rejected: the
  hard-pause zones exist precisely because some decisions are unsafe to take
  autonomously regardless of tier; never-auto-merge is the floor, not the ceiling.

**Chosen because:** the autonomy gate already encodes "what an agent may do
without asking", so the tower's unattended policy is that same gate read at the
orchestration tier; reusing it keeps one source of truth and inherits its
hard-pause zones unchanged. ISA-18.2 alarm rationalization is the maturity model
behind surfacing escalations: every queued item must be actionable, prioritized by
consequence (D-13), and Sheridan's levels-of-automation is the vocabulary for
"may decide unattended" vs "must escalate".

### D-9: Approachability — the two-seam decoupling surfaced as UX, decision queue as default  (N)

**Decision:** Make multi-orchestration legible to a non-tmux operator by
surfacing the **execution-substrate / attention-surface decoupling** (D-12) as
UX: **one obvious entry command** that autodetects/selects a backend (D-3) and
starts the tower(s); the **decision queue** (D-13) as the **default** attention
surface — one ordered queue of actionable items across all active specs, each
entry a structured choice (spec/task, question, recommended default, concrete
options), human load bounded by `## Awaiting input` count rather than worker count;
and a clear **per-worker scope** presentation preserving the tmux model's
advantages (isolated context, monitorable workers) for operators who never open a
multiplexer. The approachable path is the default, not a degraded fallback behind
tmux. The **persona → (execution backend × attention surface)** mapping resolves
each operator as a combination of the two seams: multiplexer users attach directly
(and a cmux-class tool may own the attention surface, advertised so planwright
defers); non-terminal users get the multiplexer as invisible background plumbing +
the queue; editor users get the same plumbing with the editor rendering the queue
and a steer-in-flight affordance.

**Alternatives considered:**
- Document the tmux workflow better and stop there. Rejected: most users are not
  tmux power users; better tmux docs do not make the editor/terminal operator
  first-class.
- A full GUI/web dashboard. Rejected for this spec: disproportionate, and it pulls
  in a delivery surface the pipeline avoids; a terminal/editor-legible decision
  queue meets the goal with Claude Code primitives. (A richer rendering is a gated
  deferral, tasks.md.)
- Leave the surface form an open question (the pre-addendum draft). Resolved by
  the addendum: the decision queue *is* the default surface, because human load is
  bounded by actionable decisions, not worker count.

**Chosen because:** the backend seam already abstracts "how workers run", so
surfacing the two-seam split as UX — one entry command, one decision queue, clear
scopes — is the smallest thing that makes the editor/terminal operator first-class
while preserving the tmux model's real advantages, and it is honest about quality
(execution seam) and approachability (attention seam) not trading off.

### D-10: Capability-vs-style split for every backend/fleet preference  (N (extends customization-overlay D-1))

**Decision:** Every fleet/backend preference is classified on the
capability-vs-style boundary. The general *capability* — the backend seam,
advertisement, autodetect, the degradation ladder, the self-management and
coordination mechanisms, the attention/notification capability, and the knobs
themselves (`dispatch_backend`, `dispatch_isolation`, the context-budget
threshold, the fleet concurrency bound) — lands in core as opt-in,
default-preserving config knobs resolved through the four overlay layers. The
specific *value* — which backend, which notification channel, which tuning
numbers, which isolation mode on this machine — stays in an overlay. Default tilt
is overlay when in doubt.

**Alternatives considered:**
- Bake a specific backend/tuning default into core (e.g. hardcode tmux as the
  rich backend, or a specific notification channel). Rejected: it makes core less
  general for adopters without tmux and pushes one operator's taste into the
  shared observation stream.
- Leave fleet preferences in personal memory / dotfiles `CLAUDE.md` (the status
  quo). Rejected: that is the ad-hoc home the overlay mechanism exists to replace,
  and skills cannot apply preferences they cannot resolve. (This is exactly why
  the attention/notification layer is lifted into core — D-13 — so a marketplace
  user gets it.)

**Chosen because:** the boundary runs *through* each fleet feature (a general
mechanism plus a specific value), the customization-boundary doc's central
insight; putting the mechanism in core as a knob and the value in an overlay keeps
core general and each fork's observations mergeable upstream. This is the
`review_sequence` precedent applied to the fleet's knobs and the notification
channel.

### D-11: A durable home for fleet coordination/runtime state  (N)

**Decision:** **Cross-spec** fleet coordination state that must persist across
tower restarts and plugin updates — the worker/scope registry the attention
surface reads, the fleet-level concurrency accounting, and any meta-tower
bookkeeping — lives in a durable, plugin-update-stable location resolved through
the `${CLAUDE_PLUGIN_DATA}` chain (`~/.claude/plugins/data/<id>/`, with the
writer-mode fallback the overlay resolvers use), **not** under the ephemeral
plugin root. The reason is that this state **spans specs** (the meta-tower's
registry covers every supervised spec) and so cannot live under any one spec dir.
This is deliberately distinct from the sibling's **per-spec** orchestration
runtime state: the sibling shipped its advisory lock and runtime dispatch marker
**spec-dir-local and gitignored** (`<spec-dir>/.orchestrate.lock`,
`<spec-dir>/.orchestrate/markers/`, override `PLANWRIGHT_ORCH_STATE_DIR`), not
under `${CLAUDE_PLUGIN_DATA}` — its design prose named the plugin-data chain but
the implementation sites per-spec state next to the spec it guards, which works
in both repo and plugin delivery. The per-spec effective-backend failover record
(D-3) therefore sits spec-locally with the marker, not in this cross-spec store.

**Alternatives considered:**
- Store fleet state under the plugin install root. Rejected: the plugin root is
  ephemeral per version (the plugin-data seed); state there is lost on update.
- Reuse the existing `~/.claude/inbox/` heartbeat location for everything.
  Rejected for the durable registry: the dotfiles inbox is a cross-session
  awareness signal, not the authoritative fleet registry, and it is dotfiles-local
  so a marketplace user lacks it. The attention/notification capability is instead
  lifted into core under this same durable home (D-13).

**Chosen because:** `${CLAUDE_PLUGIN_DATA}` is the already-researched durable,
namespace-separated home for framework runtime state, and the fleet's cross-spec
registry genuinely needs a cross-spec home — it spans every supervised spec, so
it cannot live under any one spec dir the way the sibling's per-spec lock and
marker do. The sibling's lock and marker are correctly **spec-dir-local**
(`<spec-dir>/.orchestrate.lock`, `<spec-dir>/.orchestrate/markers/`, confirmed
against the shipped `orchestrate-lock.sh` / `orchestrate-marker.sh`), *not* under
`${CLAUDE_PLUGIN_DATA}`; the two homes are deliberately different because the
state they hold has different scope (per-spec vs cross-spec). The per-spec
effective-backend **failover record** (D-3) is per-spec, so it sits spec-locally
with the sibling's marker, **not** in this cross-spec store — and kept out of
`tasks.md`, which is what lets a reconcile sweep see the effective backend
without violating the sibling's derived-projection contract (D-1).

### D-12: Two separable seams — execution substrate vs attention surface  (N)

**Decision:** Treat the **execution substrate** (how workers are hosted,
addressed, observed, steered — the facet-B capability contract, D-2) and the
**attention surface** (what the human watches — the decision queue, D-13) as two
independent seams, decoupled as a first-class design property. tmux today does
both jobs at once; the `subagent` backend already proves they separate (execution
in background workers, attention in one session's prompt queue). A multiplexer
need not be a UI the human operates: tmux/Zellij run fine as a **detached
background server** nobody attaches to — the tower drives it, the human sees only
the attention surface. Quality is a property of the execution seam;
approachability is a property of the attention seam; the two do not trade off.

**Alternatives considered:**
- Keep execution and attention coupled (the implicit tmux model). Rejected: it
  forces tmux fluency on anyone wanting fleet quality, which is exactly the
  approachability problem this spec exists to solve.
- Decouple only conceptually, without a concrete capability seam. Rejected: the
  decoupling has to be advertised (`provides_attention_surface`, D-2) and backed
  by a real renderer (D-13) for the orchestrator to actually defer to a tool's UI
  or render its own.

**Chosen because:** the decoupling is what lets a non-terminal operator get full
execution quality (steerable session-grade workers via background plumbing) with
zero multiplexer fluency, and lets a cmux-class tool own the attention surface
while planwright still drives execution. It is the structural backbone of the
persona×seam mapping (D-9) and the reason "quality" and "approachability" stop
being in tension.

### D-13: A substrate-agnostic attention/notification capability in core  (N)

**Decision:** Lift a **substrate-agnostic attention/notification capability** into
core, paralleling the execution capability (D-2): (a) heartbeat/awareness state
under the durable plugin-data home (D-11); (b) a **portable status renderer**
reading the worker/scope registry — each worker's scope (spec + unit) and state
(working / awaiting input / PR-ready / merged / done); (c) the **decision queue** —
one ordered, alarm-rationalized queue of actionable items across all active specs,
each a structured choice, human load bounded by `## Awaiting input` count, with
non-actionable signal suppressed; and (d) a **notification seam** whose specific
channel (a multiplexer popup vs an OS notification vs an editor toast) is the
**overlay value** per D-10. The capability depends on no dotfiles-local mechanism;
a marketplace-install user gets it from core. A backend advertising
`provides_attention_surface: true` makes planwright suppress its own queue
rendering and defer to that backend's surface (D-2).

**Alternatives considered:**
- Leave the attention layer in dotfiles (the status quo: inbox/heartbeat, popup,
  statusline, macOS notifications). Rejected: it is dotfiles-local, so a
  marketplace-install user gets none of it, and facet E's whole point is a legible
  default for every persona.
- A worker-event stream (one signal per worker event). Rejected: human load
  scales with worker count, the flood ISA-18.2 alarm rationalization exists to
  prevent; the queue is bounded by *actionable decisions*, which is the load that
  actually matters.

**Chosen because:** the decision queue is the universal surface for every persona
(it renders identically in a plain session, a detached-multiplexer popup, or an
editor panel), and alarm rationalization — every surfaced item actionable,
prioritized by consequence, non-actionable signal suppressed — is the mature
discipline (ISA-18.2, Sheridan supervisory control) that agent tooling generally
ignores. Lifting it into core is what makes facet E real for adopters rather than
a description of the author's dotfiles.

## Cross-cutting concerns

- **Coordination with the sibling, not duplication.** This bundle consumes
  `orchestration-concurrency`'s derived-projection contract (D-1) and never
  re-decides it. The 2026-06-29 re-draft confirmed three previously-open points
  against the shipped sibling contract: auto-heal and per-step sessions drive
  `tasks.md` only through the level-triggered reconcile and the advisory lock
  (REQ-C1.4, sibling D-1/D-3/D-4); the fleet concurrency bound is a separate
  accounting layer that does not collide with the per-spec lock (D-6, sibling
  D-4); and the homes split cleanly — the sibling's **per-spec** lock and
  marker are spec-dir-local and gitignored (`<spec-dir>/.orchestrate.lock`,
  `.orchestrate/markers/`, confirmed against the shipped `orchestrate-lock.sh`
  for the lock and `orchestrate-marker.sh` for the marker), while this bundle's
  **cross-spec** fleet-coordination
  registry lives under `${CLAUDE_PLUGIN_DATA}` because it spans specs (D-11). The
  per-spec effective-backend failover record sits spec-locally with the marker,
  never in `tasks.md` (D-3, D-11). Remaining sibling-touching point carried to the
  kickoff risk register: whether the failover record's format warrants a
  cross-spec note against the sibling's marker schema.
- **Decision-domains walk.** Domains this spec touches and decides: *API surface
  design* (the backend capability contract + advertisement is a new external
  interface — decided as an opt-in, advertised seam, D-2); *secrets &
  configuration* (new knobs `dispatch_backend`, `dispatch_isolation`, the
  context-budget threshold, the fleet concurrency bound, the notification channel
  — each must land in the canonical options reference, documented,
  default-preserving; D-10); *observability* (the attention/notification
  capability and the decision queue are a new human-facing surface — decided as a
  core capability with the channel as overlay value, alarm-rationalized; D-13).
  Domains it reuses, not re-decides: *authn/z* (the autonomous-safe-decision
  policy maps onto the finding-categorization hard-pause zones — D-8, never a new
  auth primitive; relay never answers permission prompts — D-7). Domains consumed
  via the sibling: *concurrency* (the advisory lock, derived projection, dispatch
  marker — sibling D-1/D-3/D-4; the fleet bound is the only fleet-owned
  concurrency knob, D-6). *Data storage & modeling*: the fleet-coordination state
  is a small file-backed registry under `${CLAUDE_PLUGIN_DATA}` (D-11) — no schema,
  no migration. No deploy/migration domain is crossed.
- **Security surface.** Backend observe/steer and spawn parse worker output and
  worker handles from potentially adversarial terminal content; the
  security-posture framework-script rules apply (worker output is data, handles
  validated before use, no impersonation, no answering permission prompts —
  REQ-B1.7, D-7). The dispatch-time environment hardening from the
  operational-protocol seed (umask-pinning pane wrapper, SSH-agent indirection
  liveness, pre-trusted worktree config paths) is the execution-time companion the
  execution skills apply; it is carried to the kickoff risk register rather than
  minted as its own requirement, since it is operational hardening of an existing
  mechanism. Every committed fleet artifact (the decision queue, the registry, the
  failover record, handover docs, PR bodies) is covered by the data-hygiene rule
  and the secret-scan guard (REQ-A1.6).
- **Proportionality.** Rich backend, meta-orchestration, and the attention
  capability are opt-in; ordinary single-spec execution requires none of them and
  reduces to the synchronous terminal rung (REQ-A1.4, D-3). The spec fixes
  capabilities and defers concrete renderings (a specific second-multiplexer
  adapter, an editor integration, a richer dashboard — tasks.md deferrals) rather
  than over-building.
- **Prior art, patterns only (no framework added).** Temporal `continue-as-new`
  (D-4 auto-heal) and the workflow/activity split (orchestrator/worker); LSP/DAP
  capability negotiation (D-2 advertisement); ISA-18.2 alarm rationalization and
  Sheridan supervisory control (D-13 decision queue, D-8 autonomy vocabulary); the
  actor model and Jupyter kernel protocol (D-7 steer-in-flight); Kubernetes
  level-triggered reconcile (consumed via the sibling D-1). Per
  [[workflows-not-plugin-invocable]] and the seed brief's stance, these are mined
  for patterns; planwright stays Claude Code primitives only.
