# Execution Backends — Design

**Status:** Draft
**Last reviewed:** 2026-07-21
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle; `C, <namespace> <id>` = carried from a
foreign bundle, namespace-qualified. The primary seed is obs:3414579b (see `requirements.md`
Sources).

## Decision log

### D-1: Altitude — the work-placement axioms are doctrine  (N)

**Decision:** The tower-frugality and smallest-sufficient-rung axioms land as a doctrine doc
(`doctrine/work-placement.md`) that `/offload` and the tower's operational-heartbeat guidance
cite; the contract extension is capability-seam doctrine (an amendment to
`doctrine/backend-capability-contract.md`); the backends, idle oracle, and status view are
mechanisms (scripts and skill surfaces); the knob default is a config value. Recorded as the
altitude D-ID for the pinned seed claims (autopilot-reflex trigger fired: the seed states the
substrate coupling as a first-class concern and states the selection rules as axioms).

**Alternatives considered:**
- Axioms as `/offload` skill prose only. Rejected because: doctrine buried in a skill is
  invisible (autopilot-reflex step 5), the skill instruction budgets are chronically saturated,
  and the axioms have two consumers (the offload skill and the tower's own inline-vs-offload
  behavior).
- Axioms as a section of the backend capability contract. Rejected because: the contract
  describes what backends *are*; work placement is a rule about how a tower *thinks* — different
  altitude, different consumers.

**Chosen because:** each piece sits at its right altitude: rules about thinking in doctrine,
seams in the contract, tools as scripts, values in config.

### D-2: Extend the shipped contract doc in place  (N)

**Decision:** Amend `doctrine/backend-capability-contract.md` (owned by orchestration-fleet,
Done) in place from this bundle's tasks, citing orchestration-fleet D-2 and REQ-B1.x as the
extended base, rather than reopening that bundle or shipping a second registry doc.

**Alternatives considered:**
- `--extend specs/orchestration-fleet`. Rejected because: it reopens an entire Done bundle
  (Done→Draft on all headers) for a delta a reader holds separately, and the fold-detection
  spin-new triggers fire (new external interfaces: `/offload`, the status view, two backend
  values).
- A new registry doc layered beside the contract. Rejected because: a second overlapping
  contract surface recreates exactly the duplication the contract doc was created to eliminate.

**Chosen because:** the operator confirmed this shape at fold-detection; one contract doc stays
the single vocabulary, and the amendment is one revert from undone.

### D-3: New backends ship as first-class rows, not external adapters  (N)

**Decision:** `headless-oneshot` and `stream-json-persistent` ship as first-class contract rows
plus core dispatch support, not as external `planwright-backend-<name>` adapter executables.

**Alternatives considered:**
- External adapters via the pluggable-adapter protocol. Rejected because: the adapter path
  exists for third-party substrates planwright cannot know about; these two rungs are
  core-verified and available wherever the installed CLI is — which is everywhere planwright
  runs.

**Chosen because:** first-class rows get the contract-table documentation, the lockstep guard,
and the degradation-ladder ordering for free, with no PATH-discovery failure mode.

### D-4: The stream-json driver is the installed CLI, never SDK-as-library  (N)

**Decision:** All stream-json and headless workers are driven through the installed `claude`
CLI. SDK-as-library drivers are out of scope while subscription-auth terms are unsettled.
Behaviors are pinned to the verified findings at CLI v2.1.217 (obs:3414579b); execution
re-verifies against the running CLI version (Research Rigor: version-sensitive API).

**Alternatives considered:**
- SDK-as-library (agent SDK linked into a driver process). Rejected because: subscription-auth
  terms for library use are unsettled — an adoption gamble planwright's install base cannot
  absorb.
- Claude Code dynamic workflows as the multi-agent substrate. Rejected because: workflows are
  user-initiated only and not plugin-invocable (recorded 2026-06-23 in the observations log),
  which already vindicated the Claude-Code-primitives-only principle.

**Chosen because:** the installed CLI is the one substrate every adopter already has,
authenticated, and the research proved it delivers full harness parity.

### D-5: The stream-json harness contract  (N)

**Decision:** A supervisor process owns the worker's stdio channel. Every `can_use_tool`
control_request receipt writes a decision-queue item and arms a pending-age alarm — never
auto-answered, never left pending unobserved (the verified indefinite-pend gotcha:
`--permission-prompt-tool stdio` pends forever if unanswered). AskUserQuestion control_requests
map 1:1 onto decision-queue items. Crash recovery is `--resume` against the persisted
`session_id`; session-grade for this backend therefore means *recoverable* — the session
survives supervisor death via `--resume` — and the contract row records that nuance explicitly.

**Alternatives considered:**
- Auto-answering permission control_requests from an allowlist inside the supervisor. Rejected
  because: the static worker allowlist already runs inside the worker's own harness; a second
  approval engine in the supervisor would duplicate a security-critical surface.
- Treating supervisor death as worker death. Rejected because: the research verified `--resume`
  recovers the session; conflating the two would forfeit the session-grade property that
  motivates the backend.

**Chosen because:** it converts the one verified deadlock (indefinite pend) into the existing
attention-store discipline, and makes the recovery story explicit instead of implied.

### D-6: `overhead` is a qualitative cost class  (N)

**Decision:** The `overhead` advertised property is a small qualitative enum (a fixed
per-dispatch cost class), not a latency measurement.

**Alternatives considered:**
- Milliseconds/benchmark numbers. Rejected because: not evaluable as a stable yes/no contract
  answer; host-dependent and instantly stale.

**Chosen because:** the contract requires evaluable definitions; a cost class is decidable per
backend and is exactly the granularity the smallest-sufficient-rung selection needs.

### D-7: `hook_registration` is an advertised boolean  (N)

**Decision:** The contract gains a `hook_registration` boolean; `fleet-liveness.sh` push-capable
reads the contract instead of special-casing backend names.

**Alternatives considered:**
- Keep name-keying in fleet-liveness. Rejected because: every new backend would need a
  fleet-liveness edit — the N×M shape the contract exists to collapse (obs:4dc16740).

**Chosen because:** it closes the recorded contract gap at the contract, not at the consumer.

### D-8: `full-session` resolution and the default flip  (N)

**Decision:** `dispatch_backend` gains the semantic value `full-session`. Unattended resolution
prefers the richest **non-interactive** session-grade backend (stream-json-persistent), never
silently resolving to tmux; attended runs may present tmux; an explicit configured value always
wins. The shipped default flips `subagent`→`full-session` — a declared departure from the
default-preserving rule (customization-boundary criterion 5), operator-scoped in the primary
seed, softened by the ladder: hosts without a session-grade rung degrade to today's behavior.

**Alternatives considered:**
- Resolve to the richest session-grade backend including tmux unattended. Rejected because: it
  weakens orchestration-fleet's never-silently-interactive invariant from absolute to
  config-mediated.
- Literal `stream-json-persistent` default. Rejected because: deterministic but broken until
  that backend ships, and hostile to tmux-preferring hosts.
- A new separate knob. Rejected because: two knobs governing one seam.
- `full-session` refuses to resolve unattended. Rejected because: makes the shipped default
  unusable for unattended fleets.

**Chosen because:** tasks are beefy enough to always warrant a full session (the seed's
operator decision); this shape delivers that while preserving the interactive-backend safety
invariant verbatim.

### D-9: Per-spec override rides the config overlays  (N)

**Decision:** The per-spec `dispatch_backend` override is a per-spec map in the config overlay
layers (e.g. a `per_spec.<spec>.dispatch_backend` key resolved through the existing four
layers), not a field in the spec bundle.

**Alternatives considered:**
- A spec-bundle header field. Rejected because: it changes the spec format and mixes execution
  policy into signed spec content; a backend preference is policy, not specification.
- Global-only. Rejected because: the seed explicitly requires per-spec overridability.

**Chosen because:** execution policy stays in config, resolved by the machinery that already
exists, and machine-local per-spec preferences become possible for free.

### D-10: Status view is a CLI table first; dashboard deferred  (N)

**Decision:** The backend-agnostic status view ships as a CLI table renderer over three sources
(`claude agents --json`, the stream-json event stream, the attention store) with per-source
graceful degrade. A rendered dashboard is a Deferred gate entry, not a task.

**Alternatives considered:**
- Dashboard only. Rejected because: heavier and less portable as the sole surface; fails the
  adopter-from-docs-alone criterion.
- Both in parallel. Rejected because: spends a task on an unproven surface before the CLI view
  demonstrates the gap.

**Chosen because:** matches orchestration-fleet's portable-status-renderer precedent; smallest
sufficient mechanism first, evidence gates the rest.

### D-11: `claude agents --json` is the primary idle oracle  (N)

**Decision:** `fleet-liveness.sh` consults `claude agents --json` as the primary busy/blocked
evidence, capability-probed at call time; pane-scrape heuristics demote to fallback when the
oracle is unavailable.

**Alternatives considered:**
- Keep pane-scrape primary, oracle as corroboration. Rejected because: the research verified
  the oracle is authoritative while pane-scrape has a recorded false-idle failure class; keeping
  the weaker signal primary inverts the evidence quality.

**Chosen because:** it retires a known false-idle class immediately, independent of any new
backend landing — which is why it is Task 1 with no dependencies.

### D-12: Pin non-`--bare` explicitly  (N)

**Decision:** Every `-p`-family launch invocation planwright emits pins non-`--bare` behavior
explicitly rather than relying on the current CLI default.

**Alternatives considered:**
- Rely on the default. Rejected because: the research flagged `--bare` may become the `-p`
  default; a silent flip would strip SessionStart hooks and harness surface from every headless
  worker at once.

**Chosen because:** one flag per launch site is the cheapest insurance against a
platform-default change (the same version-sensitivity class Research Rigor exists for).

### D-13: Adapter grammar grows back-compatibly, 6→8 fields  (N)

**Decision:** The pluggable-adapter `advertise` line grows from six to eight fields (`overhead`,
`hook_registration` appended). A legacy six-field line remains valid with fail-safe defaults
(`hook_registration=false`; `overhead` treated as the most conservative class); a malformed
line still fails closed (the backend is never selected).

**Alternatives considered:**
- Require eight fields, break legacy adapters. Rejected because: a silent breaking change to a
  published extension grammar; third-party adapters would stop being selectable with no
  diagnosis.
- Versioned advertise protocol (v1/v2 negotiation). Rejected because: two fields do not justify
  a negotiation protocol; append-with-fail-safe-defaults is the whole need.

**Chosen because:** additive growth with conservative defaults keeps every existing adapter
working while making the new fields expressible.

## Cross-cutting concerns

- **Decision-domains walked (2026-07-21):** fires on API surface (adapter grammar, knob value,
  skill shape — decided in D-3/D-6/D-7/D-13), concurrency (supervisor + decision-queue coupling,
  D-5), observability (D-10/D-11), secrets & configuration (knob layering, D-8/D-9; the worktree
  machine-local gap recorded as a risk), versioning (D-13). Not applicable: data storage,
  caching, queues (existing attention store reused), auth (scoped out via D-4),
  deploy/migration beyond the declared default flip in D-8, dependency adoption (no new
  dependencies — the installed CLI is already the substrate).
- **Data hygiene:** committed artifacts reference the research by its recorded observation
  (obs:3414579b) and CLI version, never by machine-local probe paths.
