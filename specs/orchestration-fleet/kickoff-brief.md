# Orchestration Fleet — Kickoff Brief

The durable contract between human and agent for the `orchestration-fleet`
spec. Downstream skills (`/orchestrate`, `/execute-task`) operate from this
brief, not by re-reading the spec bundle.

## 1. Header

- **Spec path:** `specs/orchestration-fleet/`
- **Spec commit at walkthrough start:** `0b356d3` (`0b356d373ca91ad29258c5ee95fae8d88d5bc103`)
- **Walkthrough date:** 2026-06-29
- **Mode:** First activation (Status Draft, no prior signed brief)
- **Validator outcome (pre-flight, Draft enforcement):** 0 errors, 0 warnings
  (`scripts/spec-validate.sh specs/orchestration-fleet`)
- **Doctrine resolution:** all six rule docs resolved from the repo's own
  `doctrine/` via `PLANWRIGHT_ROOT=<repo>` (this is the planwright repo; the
  installed plugin copy was not used).
- **Decision-domains catalog:** resolves (merged view via
  `scripts/resolve-catalog.sh decision-domains`); gap check will run.
- **Content anchor (pre-flight smoke):**
  `c35ec1c8af78beed1a57baf07d3e080fcb57f42f` via
  `scripts/spec-anchor.sh specs/orchestration-fleet` (recomputed at sign-off).

## 2. Goal & glossary

### Goal (agent restatement)

planwright already does fleet orchestration, but only as the emergent behavior
of a skilled tmux operator (hand-relayed messages, tribal relay mechanics, tmux
fluency most adopters lack). This spec **productizes** those emergent behaviors
into first-class, reliable, accessible capabilities, on top of the
`orchestration-concurrency` state-safety foundation it **consumes** and never
redefines.

The load-bearing insight: **the quality of the emergent fleet is not from tmux.**
It comes from **session-grade workers**, **observe-in-flight**, and
**steer-in-flight**, plus externally-imposed stage sequencing. tmux is one
substrate that delivers them. The spec therefore splits **two seams tmux
conflates**:

- **Execution substrate** (how workers are hosted, addressed, observed, steered)
  — where *quality* lives — as a backend **capability contract** with
  **advertisement** and a **graceful-degradation ladder**.
- **Attention surface** (what the human watches) — where *approachability* lives
  — as a substrate-agnostic **decision queue** lifted into core.

The two seams **do not trade off**. The ladder's governing rule is **degrade
capability, never safety**. The one carried hard invariant is **never
auto-merge, at any tier**.

**Rules out:** redefining sibling state-safety internals; auto-merge; a parallel
autonomy taxonomy; new agent frameworks (Claude Code primitives only; prior art
mined for patterns); concrete second-multiplexer adapters, editor integrations,
or a GUI dashboard (ships the *seams and renderer model*, not specific
renderers); the operator's specific tool/channel/tuning values (overlay-owned).

**Assumes:** the sibling `orchestration-concurrency` contract is authoritative
and shipped (derived projection, advisory lock, dispatch marker, level-triggered
reconcile); `${CLAUDE_PLUGIN_DATA}` is the durable cross-spec home; the four-layer
overlay model and the finding-categorization gate exist to build on.

### Glossary (implicit terms surfaced)

- **session-grade** — a worker launched as a separate top-level Claude Code
  session: full context window and harness surface, commits as a principal, and
  **survives the tower's death** (the load-bearing half — it is what makes
  workers disposable-tower-safe). Antithesis: a context-sharing in-harness
  subagent. *Field note (Diego, kickoff §2):* headless `claude -p` was tried and
  is also session-grade, but the inability to steer it degraded
  quality/usability/ergonomics — this is the operator experience behind placing
  `claude -p` at ladder rung 2 (near the fallback), not as a quality-equivalent
  middle rung (D-3).
- **observe-in-flight** — read a *running* worker's current state mid-task, not
  only its final output. First-class capability, not folded into a generic relay.
- **steer-in-flight** — deliver a clearly-attributed message into a *running,
  busy* worker to course-correct or answer, without killing and restarting it.
  First-class; never `send-keys`-style impersonation.
- **tower** — a dispatching `/orchestrate` session (control tower); holds no
  in-memory state beyond the current step and is disposable.
- **meta-tower** — a tower that launches and supervises subordinate towers to
  drain multiple active specs (a tower of towers).
- **two seams** — execution substrate vs. attention surface (D-12), decoupled as
  a first-class design property.
- **decision queue** — one ordered, alarm-rationalized queue of actionable items
  across all active specs, each a structured choice; human load bounded by the
  `## Awaiting input` count, not the worker count.
- **degradation ladder / rung** — the richest-to-safest backend chain (REQ-B1.5);
  rung 4 (synchronous in-session with context clears) needs no external substrate
  and always works.
- **capability advertisement** — a backend self-describes its capability set
  (`{ interactive, can_observe, can_steer_inflight, provides_attention_surface,
  supports_parallel }`); the orchestrator adapts to what is advertised rather
  than special-casing backends by name (the LSP/DAP lesson).

### Ambiguity resolutions

- The skill's "Draft→Active" flip is superseded by the spec-format six-status
  lifecycle: sign-off flips **Draft→Ready**; Active is derived later by the first
  task to start. Recorded as skill drift (see Maintenance).

Signed off: 2026-06-29

## 3. Requirements walkthrough

### Per-group outcomes

- **REQ-A (foundation, dependency, carried invariants).** Confirmed. Consumes the
  sibling derived-projection contract as authoritative (A1.1), carries
  never-auto-merge at every tier (A1.2), no parallel autonomy taxonomy (A1.3),
  proportionate/opt-in with a single-tower run fully functional on rung 4 (A1.4),
  capability-vs-style on every knob (A1.5), data hygiene on every artifact (A1.6).
  Internally consistent; no edits.
- **REQ-B (pluggable & autodetected backend).** Confirmed. The capability contract
  (B1.1), advertisement + adapt-to-advertised (B1.2), extends `dispatch_backend`
  + pluggable path (B1.3), autodetect-present-ask (B1.4), the ladder + runtime
  failover + degrade-capability-never-safety (B1.5), spec-local effective-backend
  record (B1.6), relay/spawn security bounds (B1.7). Edit applied to B1.7 (see
  consolidated list). Open edge carried to risk register: repeated runtime
  failures descend one rung *per* failure down to rung 4 (always-works floor).
- **REQ-C (orchestrator self-management).** Confirmed. Context-budget monitor
  (C1.1), auto-heal `continue-as-new` handover (C1.2), `dispatch_isolation`
  per-step (C1.3), preserve state-safety (C1.4). Two decisions taken below.
- **REQ-D (meta-orchestration, coordination & autonomy).** Confirmed. Meta-tower
  across active specs (D1.1), division of labor (D1.2), attributed
  non-impersonating relay (D1.3), autonomous-safe-decision policy mapped onto the
  gate (D1.4), multi-spec reach + fleet bound (D1.5), cross-spec state home
  (D1.6). Edit applied to D-8 (see consolidated list).
- **REQ-E (approachability).** Confirmed. Two separable seams (E1.1), one entry
  command (E1.2), decision queue as default surface (E1.3), attention/notification
  in core (E1.4), per-worker scope legible & default (E1.5), persona×seam mapping
  (E1.6). Open edge carried to risk register: the default notification channel
  when no overlay sets one (must be the safe/quiet default per the
  decision-domains secrets-&-config rule).

### Decisions taken

1. **The "prompt" vocabulary collision is resolved by a clarifying spec edit**
   (kickoff §3, 2026-06-29). D-8's "answering routine worker prompts" and
   REQ-B1.7's "never answer a worker's permission prompt" are two senses: a
   routine *worker question to the tower* (which the autonomy policy MAY answer)
   vs. the *harness tool-permission gate* (which a tower NEVER answers). Edited
   both records to make the senses non-overlapping. Consistent with the standing
   [[handle-routine-worker-prompts]] guidance. Not an inconsistency halt — the
   records did not contradict, they shared a word.
2. **`dispatch_isolation` default = `per-step` stands** (REQ-C1.3, D-5; Diego's
   2026-06-15 assigned decision). This is a default-behavior change (today's
   behavior is per-unit) and requires a cross-spec `bootstrap` D-38 amendment,
   carried as a risk-register row + a Task 4 deliverable. `per-unit` remains a
   supported value.
3. **The context-budget signal is a research item, not pinned now** (C1.1, D-4).
   How a tower measures "nearing the limit" against Claude Code's actual
   context-introspection capability is an open question → risk-register row; Task 5
   researches and picks the signal at execution.

### Consolidated spec-edit list (applied in place, Draft)

| File | Record | Edit |
| --- | --- | --- |
| `design.md` | D-8 | Disambiguated "routine worker question to the tower" (may answer) from "harness permission prompt" (never answer); cross-ref REQ-B1.7/D-7. |
| `requirements.md` | REQ-B1.7 | Marked the never-answer target as the *harness permission prompt* and cross-referenced the may-answer routine worker question (REQ-D1.4, D-8). |
| `requirements.md` | Changelog | Added a 2026-06-29 kickoff-clarification entry recording the disambiguation. |

Re-validated after edits: 0 errors, 0 warnings (Draft). No inconsistency halt
triggered.

Signed off: 2026-06-29

## 4. Design walkthrough

Every D-ID accounted for. The 2026-06-29 re-draft already reconciled the
sibling-dependent decisions; this walkthrough confirms each and caught one stale
rationale (D-11).

### Decision ledger

| D-ID | Decision | Disposition |
| --- | --- | --- |
| D-1 | Consume sibling derived-projection contract | Confirmed (rationale intact) |
| D-2 | Backend capability contract + advertisement | Confirmed |
| D-3 | Autodetect-and-ask over the degradation ladder | Confirmed |
| D-4 | Context-budget self-monitoring + auto-heal (`continue-as-new`) | Confirmed; budget signal = research/risk row |
| D-5 | Per-step dispatch isolation, default `per-step` | Confirmed; cross-spec bootstrap D-38 amendment = risk row |
| D-6 | Meta-orchestration as a tower of disposable towers | Confirmed |
| D-7 | Inter-orchestrator coordination — division of labor + attributed relay | Confirmed |
| D-8 | Autonomous-safe-decision policy mapped onto the gate | Confirmed; **clarified** (prompt-sense disambiguation, §3) |
| D-9 | Approachability — two-seam UX, decision queue default | Confirmed |
| D-10 | Capability-vs-style split for every preference | Confirmed |
| D-11 | Durable home for fleet coordination/runtime state | Confirmed; **corrected** (stale Chosen-because, §4) |
| D-12 | Two separable seams — execution substrate vs attention surface | Confirmed |
| D-13 | Substrate-agnostic attention/notification capability in core | Confirmed |

### Reconciliation notes

- **No design decision contradicts a walked requirement.** The two records edited
  this run (D-8 §3, D-11 §4) were a vocabulary collision and a factual straggler,
  not contradictions with requirements — neither triggered the inconsistency halt.
- **D-11 correction (validated three ways).** The shipped sibling sites its lock
  at `<spec-dir>/.orchestrate.lock` and its marker at
  `<spec-dir>/.orchestrate/markers` (verified in `orchestrate-lock.sh` /
  `orchestrate-marker.sh`), spec-dir-local, never under `${CLAUDE_PLUGIN_DATA}`.
  D-11's body and the Cross-cutting section already stated this; only the
  Chosen-because lagged. Corrected in place; failover record clause fixed too (it
  is per-spec, sits spec-locally with the marker, not in the cross-spec store).
- **Cross-cutting concerns confirmed:** the sibling-reconciliation block (three
  previously-open points now closed), the decision-domains walk (API surface,
  secrets & config, observability decided; authn/z and concurrency reused via the
  gate and the sibling), the security surface, proportionality, and the
  patterns-only prior-art stance all hold. One sibling-touching open point
  (whether the failover record's format warrants a cross-spec note against the
  sibling's marker schema) carries to the risk register.

### Consolidated spec-edit list (design, applied in place, Draft)

| File | Record | Edit |
| --- | --- | --- |
| `design.md` | D-11 | Corrected the Chosen-because: sibling lock/marker are spec-dir-local (not `${CLAUDE_PLUGIN_DATA}`); failover record is per-spec/spec-local. |
| `requirements.md` | Changelog | Added a 2026-06-29 kickoff factual-correction entry. |

Re-validated after edits: 0 errors, 0 warnings (Draft).

Signed off: 2026-06-29

## 5. Verification approach

### Coverage mix reviewed

Skills + portable scripts over backends, so the mix leans `[design-level]` and
`[manual]`/`[Gherkin]` for skill-orchestrated behavior, with `[test]` where a
unit is genuinely script-testable. All 11 `[test]`-tagged REQs (A1.4, B1.2, B1.4,
B1.5, B1.6, B1.7, C1.3, D1.5, D1.6, E1.3, E1.4) map to real script-testable units;
no dead paths found (every named verification can actually run).

### Verification ownership

- **`[test]`** → the project CI (`mise run check`); the per-task PR is gated on it.
- **`[design-level]`** → existence-plus-coverage audited at kickoff (here) and at
  per-task review; the artifact's existence + coverage is the verification.
- **`[manual]`** → swept by the operator (Diego); these exercise the assembled
  fleet end-to-end and cannot be CI-gated.
- **`[Gherkin]`** → state/trigger/outcome scenarios, exercised manually or scripted
  per the task.

### REQ-A1.1 trace audit (discharged here, as the test-spec entry directs)

Every fleet state-writing path was traced to the sibling's reconcile:
- **auto-heal handover** (C1.2): the fresh tower rebuilds from the `tasks.md`
  snapshot + `gh` + branch/marker; placement only via reconcile (D-4, REQ-C1.4).
- **per-step sessions** (C1.3): fresh `/resume`-seeded sessions drive placement
  via reconcile + lock, never a direct write (D-5, REQ-C1.4).
- **meta-tower moves** (D1.1): subordinate towers are ordinary disposable towers;
  each state move goes through the per-spec lock + reconcile (D-6).
No fleet requirement re-specifies a sibling state-safety internal, and no fleet
path commits dispatch/progress state to `tasks.md`. **Audit passes.**

### Dead-path check

None. The only deferred verification (A1.1's trace) is discharged above. The
`[test]` units are all runnable under `mise run check`.

### Verification risk (→ risk register)

The load-bearing behaviors (ladder end-to-end, relay against a live busy worker,
the two-spec meta-run, auto-heal handover) are `[manual]` because they need the
assembled fleet a fragment test cannot stand in for. The most important behaviors
are therefore the least automatable; the `[manual]` sweep owner is the operator.
Carried as a risk-register row.

Signed off: 2026-06-29

## 6. Task graph

Reconstructed from the authoritative `Dependencies:` lines (the tasks.md
dependency-view prose is derived).

### Dependency edges

| Task | Effort | Depends on |
| --- | --- | --- |
| T1 — backend capability contract & advertisement | 1.5d | none (root) |
| T8 — autonomous-safe-decision policy | 0.5d | none (root) |
| T2 — autodetect + present-and-ask | 1d | T1 |
| T9 — cross-spec fleet-state home | 1d | T1 |
| T4 — `dispatch_isolation` knob & per-step | 2d | T1 |
| T5 — context-budget monitor & auto-heal | 2d | T1 |
| T3 — degradation ladder + runtime failover | 2d | T1, T2 |
| T6 — meta-orchestration (tower of towers) | 2d | T1, T2, T8 |
| T12 — attention/notification capability | 2d | T9 |
| T7 — inter-orchestrator coordination | 2d | T1, T6 |
| T10 — approachability: entry command, two-seam UX | 2d | T2, T6, T9, T12 |
| T11 — adopter docs, options reference | 1d | T1–T10, T12 |

### Parallelism & critical path

- **Roots:** T1 and T8 start at t=0.
- **Fan-out after T1:** T2, T9, T4, T5 are mutually independent tracks.
- **Effort-weighted critical path ≈ 7.5 days:** `T1 → T2 → T6 → {T7 | T10} → T11`
  (1.5 + 1 + 2 + 2 + 1). Serial total is 19 days, so the graph compresses ~2.5×.

### Deliberate non-edges / edges (recorded so they are not "fixed")

1. **T12 → T9 only (no edge to T1/T2/T6).** The attention seam depends on the
   cross-spec state home, not the execution contract — the two-seam decoupling
   (D-12) expressed structurally. Preserve this non-edge.
2. **T4, T5 → T1 only.** Self-management is independent of backend selection and
   of each other. Deliberate non-edges.
3. **T6 → T8 is a deliberate edge.** The meta-tower depends on the autonomy
   *policy* (a doctrine artifact) because an unattended meta-tower must not
   dispatch without the safety artifact; the edge is a safety gate, not a build
   dependency.
4. **Cross-spec edges are not task deps.** The `bootstrap` D-38 amendment (T4) and
   the consumed sibling scripts (T1/T3/T6/T9) are risk-register rows; a sibling's
   task IDs are not in this bundle's dependency space.

Signed off: 2026-06-29

## 7. Risk register

Inputs: risks surfaced during the walk, the operator's cold review (register
confirmed complete), and the decision-domains gap check (merged catalog via
`scripts/resolve-catalog.sh decision-domains` — planwright's 10 seed domains, no
overlay additions in this repo). Catalog walk: API-surface, secrets-&-config, and
observability are decided in the bundle (D-2, D-10, D-13); authn/z and concurrency
are reused via the gate and the sibling (D-7, D-8, D-1); data-storage is a small
file-backed registry, no schema/migration (D-11); caching, deploy/migration, and
dependency-adoption domains are not crossed. The gaps below are the residue.

| # | Risk / gap | Mitigation / early signal |
| --- | --- | --- |
| R1 | **Fleet-bound enforcement under-specified (concurrency).** D-6/D-11 assert the fleet concurrency bound does not collide with the per-spec lock, but the mechanism for atomically enforcing one bound across N independent towers is unspecified. Disposition (Diego, kickoff §7): risk row; Task 6 specifies. | Task 6 pins the enforcement primitive (own advisory lock / atomic counter under the cross-spec home). Early signal: two towers exceed the bound in a multi-spec test. |
| R2 | **Context-budget signal undefined (C1.1/D-4).** How a tower measures "nearing the limit" against Claude Code's introspection capability. | Task 5 researches and picks the signal. |
| R3 | **Cross-spec `bootstrap` D-38 amendment (D-5).** per-step default requires amending a sibling spec. | Task 4 carries the amendment; tracked cross-spec. |
| R4 | **per-step default-flip rollout.** Flipping `dispatch_isolation` default changes behavior for existing operators. | Document the flip in options-reference + changelog; `per-unit` stays available. |
| R5 | **Safe defaults for new knobs.** notification channel, fleet bound, context-budget threshold (secrets-&-config: the unread default must be the safe one). | Each default must be quiet/safe; audited in the Task 11 options-reference. |
| R6 | **Ladder repeated-descent semantics.** Multiple runtime failures descend one rung per failure down to rung 4. | Task 3 tests a multi-failure descent reaching the always-works floor. |
| R7 | **Auto-heal / meta-launch handover window.** Retiring tower dies after deciding to hand over but before the fresh tower starts. | Level-triggered reconcile re-derives on any restart; Task 5 tests the dead-window. |
| R8 | **Failover-record format vs sibling marker schema.** Whether the spec-local effective-backend record warrants a cross-spec note against the sibling marker schema (cross-cutting open point). | Confirm against the sibling marker schema at Task 3. |
| R9 | **Dispatch-time environment hardening** (umask pane wrapper, SSH-agent indirection liveness, pre-trusted worktree config paths) — operational hardening of an existing mechanism, carried not minted. | Execution skills apply at Task 3/7; from the operational-protocol seed. |
| R10 | **D-37 native-worktree gap for session-grade spawn (REQ-B1.1).** | Verify the native-worktree path supports session-grade spawn at Task 1/3. |
| R11 | **Manual-heavy verification of load-bearing behaviors (§5).** The riskiest behaviors can't be CI-gated. | Operator-owned `[manual]` sweep; sequence the manual exercises per task. |

No open question remains unresolved: each row is a decision (proceed with the
named mitigation) or an explicit accepted risk with an early signal. The gap check
ran against the merged catalog; no catalogued domain the spec touches is left
undecided beyond the rows above.

Signed off: 2026-06-29

### Lens-pass additions to the risk register (2026-06-29 sign-off)

The sign-off Discovery-Rigor lens pass (recorded in full in §8) reshaped R1 and
added rows R12–R17. These append to the §7 register; they do not overwrite it.

- **R1 (reshaped).** The gap is broader than fleet-bound enforcement: the
  **cross-spec store under `${CLAUDE_PLUGIN_DATA}` (Task 9) has no named
  concurrency-control primitive.** The fleet-bound check-and-increment race, the
  registry read-during-write (attention surface reads while a meta-tower writes),
  two-meta-tower mutual exclusion, and the auto-heal handover-counter consistency
  are all instances of this one root. Disposition (Diego, kickoff §8): **Task 9
  owns a named primitive** (advisory lock à la `orchestrate-lock.sh`, or
  atomic-append registry semantics) that **Task 6** (fleet bound) and **Task 12**
  (registry) consume. Early signal: two towers exceed the bound, or a torn
  registry read, in a multi-spec test.
- **R12 — Failover/auto-heal error paths (Task 3/5).** Beyond the pinned
  logged-note surface (spec edit): failover-record write-failure handling (abort
  to the always-works floor rather than proceed unrecorded), note-before-record
  ordering/atomicity, fresh-tower-fails-during-auto-heal (don't retire the old
  tower until the fresh one is running; else escalate), terminal-rung fatal-crash
  escalation (no lower rung exists), and decision-queue durability across a tower
  restart during a failover cascade. Early signal: a simulated mid-descent crash
  leaves no operator-visible signal.
- **R13 — Alarm-rationalization mechanism unpinned (Task 12).** "Human load
  bounded by `## Awaiting input` count" holds only if the queue actively dedups;
  the dedup/ordering rule is unspecified. Task 12 must define it (one decision per
  (spec, unit) regardless of failure count; order by consequence then age). Early
  signal: a worker failing N times produces N queue entries.
- **R14 — Security under-spec (Task 1/7/9).** Worker-handle grammar undeclared
  (Task 1 mints it; security-posture requires validation against a declared
  grammar before use); plugin-namespace path canonicalization + containment on the
  `${CLAUDE_PLUGIN_DATA}` resolution (Task 9); prose-shaped data-hygiene leaks
  (hostnames, private-repo detail) that the secret-scan guard misses (Task 11
  audit / documented rule); permission-prompt pattern enumeration so the
  never-answer gate is testable (Task 7/8). Early signal: a hostile handle or a
  traversal namespace reaches a path op.
- **R15 — Resource bounds (Task 9/12/7).** Cross-spec registry retention/TTL (no
  unbounded growth across merge cycles); observe-in-flight polling interval
  (human-perceptible, not sub-second IO storm); reconcile cost amplified by
  per-step isolation × meta-tower scale (monitor tower-startup time; the reconcile
  is inherited from the sibling). Early signal: registry or startup time grows
  with history.
- **R16 — Multi-descent failover test coverage (Task 3).** The test-spec exercises
  a single descent; the repeated-descent-to-floor behavior (R6) is not tested.
  Task 3 adds the multi-failure case. Early signal: a second failover behaves
  differently than specified.
- **R17 — Definition evaluability at execution (Task 1/2/3/7).** Terms the spec
  uses but leaves for the implementing task to make evaluable — "ambiguity"
  (B1.2 routing), "strategic context clears" (B1.5 rung 4), "directly" (D1.2
  no-cross-tower-edits boundary). Declined as spec edits (correctly task-defined);
  captured here so each task pins its term with a test. Early signal: a reviewer
  cannot evaluate a Done-when because the term is still abstract.

## 8. Sign-off

### Lens review pass (Discovery Rigor)

- **Scope:** full bundle (first activation).
- **Path:** parallel fan-out — **nine read-only sub-agents, one per canonical
  lens** (the bundle is ~100 KB across four files, well beyond the inline
  threshold). Shared tooling context passed to every agent: the validator ran
  clean (0/0) and the shipped sibling scripts (`orchestrate-lock.sh`,
  `orchestrate-marker.sh`, `orchestrate-state.sh`) were the ground-truth source
  for sibling-claim checks.
- **Findings validated** per validation-rigor (three passes + adversarial
  refute/resurrect). The adversarial pass dropped two false positives: the
  "test-spec names only 2/4 ladder guards" claim (all four *are* named, verified)
  and the "config knobs missing from options-reference" claim (Task 11's
  deliverable; expected-empty at kickoff).

#### Canonical lens-coverage table

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 5 | Failover repeat-descent, queue ordering, fleet-bound check timing, undefined terms, failover-record path → risk rows R12/R13/R16/R17 |
| Security | 5 | Handle grammar, path canonicalization, data-hygiene-beyond-secret-scan, permission-prompt enumeration, audit logging → risk row R14 |
| Error handling & failure modes | 6 | "Logged note" surface (spec-edited); record-write/atomicity, fresh-tower-fail, terminal-rung crash, cascade durability → risk row R12 |
| Performance | 4 | Registry TTL, alarm-rationalization mechanism, reconcile cost, observe-polling → risk rows R13/R15 |
| Concurrency / state | 1 root + cluster | Cross-spec store has no named concurrency-control primitive → **R1 reshaped** (Task 9 owns the primitive) |
| Naming, readability, structure | 3 | "portable renderer"→"status renderer" (applied); option/knob (declined, both valid) |
| Documentation | 1 + 1 FP | `[[ ]]` memory-links don't resolve (declined, low severity); options-reference rows = **false positive** (Task 11) |
| Tests / verification | 5 + 1 FP | Multi-descent (R16), alarm-rationalization (R13), notification test mis-tag; "2/4 guards" = **false positive** |
| Cross-file consistency | 1 | Sources-491 stale `${CLAUDE_PLUGIN_DATA}` marker claim (applied fix) |

#### Dispositions

**Applied as spec edits** (verified, this run; recorded in the requirements
Changelog):
1. REQ-B1.5 — pinned the runtime-failover "logged note" to the decision queue's
   `## Awaiting input` surface (REQ-E1.3).
2. Sources — corrected the sibling D-3 marker description (spec-dir-local, not
   `${CLAUDE_PLUGIN_DATA}`) — same class as the §4 D-11 correction, verified
   against the shipped scripts.
3. tasks.md — "portable renderer" → "portable status renderer" (consistency).

**Deferred to named risk-register rows** (execution defines, with an early
signal — see "Lens-pass additions" under §7): R1 reshaped (Task 9 owns a named
cross-spec concurrency-control primitive consumed by Task 6/12); R12 failover/
auto-heal error paths (Task 3/5); R13 alarm-rationalization mechanism (Task 12);
R14 security under-spec (Task 1/7/9); R15 resource bounds (Task 9/12/7); R16
multi-descent test coverage (Task 3); R17 definition evaluability (per task).

**Declined with rationale:** options-reference rows (false positive —
Task 11 deliverable, expected-empty at kickoff); `[[workflows-not-plugin-invocable]]`
/ `[[handle-routine-worker-prompts]]` memory-links (authorial convention
referencing recorded guidance, low severity); option-vs-knob wording (both terms
valid; "options-reference" entrenches "option"); pure Task-level definitions
("ambiguity", "strategic clears", "directly" — correctly defined by the
implementing task, captured as R17). No undispositioned finding remains.

### Status flip

`Status:` flipped **Draft → Ready** on all four spec files (not Active — Active is
derived later by the first task to start, per spec-format's kickoff-lifecycle
D-1/D-2). `Last reviewed:` is 2026-06-29 on all four. Re-validated under Ready
(error) enforcement after the flip: **0 errors, 0 warnings**.

### Sign-off record

Class: meaning
Lens-pass: recorded above (this section), full-bundle nine-lens fan-out, findings
validated and dispositioned 2026-06-29.
Anchor: `70edfab2b0bbcf798725a044efc78bfa6198e1d0` — computed as
`scripts/spec-anchor.sh specs/orchestration-fleet`
(re-anchored 2026-06-29 for an expression-only fix; see Amendment log. Original
sign-off anchor: `6ab1f63975714c68a00be55e3aa115ec54c3af42`.)

## Amendment log

Post-sign-off changes to the anchored spec bundle. Signed sections 1–8 above are
unchanged except the `Anchor:` pointer in §8; entries here record expression-only
edits that re-anchor the bundle. A meaning-class change is never recorded here —
it requires a delta re-walkthrough by the kickoff owner.

- **2026-06-29 — expression-only re-anchor (finishing gauntlet, `/panel-pairing`
  stage).** Fixed six markdown soft-wrap rendering defects where a hyphenated
  compound was split across a line break and rendered with a spurious space:
  `requirements.md` (`multiplexer-as-background-plumbing`,
  `derived-projection contract`), `tasks.md` (`fleet-coordination-state`,
  `multiplexer-as-detached-background-plumbing`), and `test-spec.md`
  (`marketplace-install`, `Design-level`). No REQ/D-ID/task meaning changed; the
  fixes bring the defective spots into line with the already-correct usages
  elsewhere in the bundle. Validator re-run clean (0 errors, 0 warnings, Ready
  enforcement). Anchor recomputed
  `6ab1f63975714c68a00be55e3aa115ec54c3af42` → `e6ead4184ca0a72c380657529b7fef1b30dc18a2`.
- **2026-06-29 — expression-only re-anchor (finishing gauntlet, `/copilot-pairing`
  stage).** `design.md`'s decision-log preamble still read "This bundle is Draft
  and has never been activated" (present tense) while the `Status:` header reads
  Ready — a straggler the kickoff Draft→Ready flip left behind, surfaced by a
  Copilot review thread. Reframed the preamble to past tense: the decisions were
  edited in place as drafting iteration while the bundle was Draft, and sign-off
  flipped it to Ready (so future edits follow the amendment/re-anchor process this
  log records). No D-ID decision content changed. Validator re-run clean (0/0,
  Ready enforcement); doc-links resolve. Anchor recomputed
  `e6ead4184ca0a72c380657529b7fef1b30dc18a2` → `ac6d52181395098f4c2c0ad824ae11c5ce6321a4`.
- **2026-06-29 — expression-only re-anchor (finishing gauntlet, `/copilot-pairing`
  stage, second re-review).** A Copilot thread flagged a verb-gapped sentence in
  `tasks.md`'s Deferred section ("Task 12 ships … and Task 10 the persona mapping
  …") as reading like a missing verb. Inserted the elided verb — "Task 10 **ships**
  the persona mapping" — so the clause is unambiguous. Grammatically the gapping
  was valid; the edit is a pure readability fix, no task meaning changed. Validator
  re-run clean (0/0, Ready enforcement); doc-links resolve. Anchor recomputed
  `ac6d52181395098f4c2c0ad824ae11c5ce6321a4` → `70edfab2b0bbcf798725a044efc78bfa6198e1d0`.
