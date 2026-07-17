# Fleet Autonomy — Kickoff Brief

## 1. Header block

- **Spec path:** `specs/fleet-autonomy`
- **Spec commit at walkthrough start:** `fd5724bbebc3203a8a68b90cc9f48c413d792b5d`
- **Walkthrough date(s):** 2026-07-14
- **Validator outcome (pre-flight):** `spec-validate.sh specs/fleet-autonomy` — 0 errors, 0 warnings (Draft bundle; findings would be warnings-only regardless).
- **Mode:** First activation (no prior brief; Status Draft on all four files).
- **Config read:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (both from `config/defaults.yml`; no `.claude/planwright.local.yml` present in this repo).
- **Working location:** already in the spec's own worktree (`.claude/worktrees/fleet-autonomy-spec`, branch `planwright/fleet-autonomy/spec`), clean.

## 2. Goal & glossary

**Restatement.** planwright's fleet mechanisms today are tower-loop-invoked:
housekeeping (heartbeat pushes, context-budget checks, stale-resource
cleanup) only happens when a tower's own `--watch` step remembers to call
it, and liveness is discovered by polling a pane (`capture-pane`) rather than
observed as an event. Two failure modes follow: routine drift goes unnoticed
until a tower happens to check, and an *ungraceful* tower death (host
reboot, killed terminal) leaves no path back to the human's actual
in-progress context — only the re-derived ledger state on disk. This spec
moves that housekeeping into independent, hook- and heartbeat-driven daemon
mechanisms that fire on real events or their own schedule, never on a
tower's polling loop remembering to call them.

Three floors constrain every mechanism this spec adds: (1) workers remain
full Claude Code sessions, never downgraded to a lighter script; (2) every
daemon decision is deterministic script logic, never in-context model
judgment (D-18/REQ-G1.2); (3) towers dispatch/monitor/reconcile only —
they don't author repo/config/content changes themselves except as an
explicitly-flagged, human-routed exception (D-17/REQ-G1.1).

**Rules out:** auto-merge (permanent floor), replacing workers with
non-agentic subprocesses, a GUI/web dashboard, a second multiplexer adapter,
a confidence-calibrated model-routing cascade, and a dollar-spend ceiling —
several named as "surveyed, no mature precedent, not worth building
speculatively" rather than decided against on principle (a distinction that
matters for how firmly closed each exclusion is).

**Assumes:** two already-`Done` sibling specs — `orchestration-fleet`
(backend capability contract, context-budget/auto-heal, attention seams) and
`orchestration-concurrency` (state-safety model, advisory lock) — are
consumed as authoritative and extended, never redefined.

**Implicit terms surfaced and resolved:**

1. **The `flailing`-classification threshold** (REQ-A1.2/REQ-A1.3, D-2): the
   number of no-forward-progress heartbeats before escalating is left as "a
   configured threshold" with no spec-pinned default anywhere in the
   bundle. **Resolution:** left open to Task 2's implementation by design —
   no mature precedent exists for this exact signal, the right value depends
   on the fleet's actual per-backend heartbeat cadence, and a wrong default
   is safe (it only shifts *when* a human escalation fires, never loses
   work). Task 2 picks a default and it resolves through Task 1's
   config-knob helper (D-22) like every other knob, so it is
   overlay-tunable, not hardcoded.
2. **"Ready work exists"** (REQ-A1.5, the cron watchdog's relaunch gate):
   **Resolution:** this means whatever `/orchestrate`'s own ready-task
   selection logic currently resolves as ready — the watchdog calls through
   to that selection mechanism rather than re-deriving readiness by reading
   `tasks.md`'s committed shape directly. This matters concretely right now:
   `specs/invariant-tasks` (Status Ready, PR #171 open, awaiting merge)
   graduates `tasks.md` to format-version 2 and removes the committed
   `## Forward plan` section entirely, making readiness fully derived —
   `invariant-tasks` explicitly scopes "selection policy (which ready unit
   is chosen) — unchanged" out of its own bundle. Because REQ-A1.5 is
   specified as a call-through and not a re-implementation, it is naturally
   robust to `invariant-tasks` landing either before or after this bundle's
   Task 3 is implemented. Flagged for Task 3's citations and the risk
   register (§7): the implementation must call the live selection
   mechanism, never hand-roll a check against `tasks.md`'s current
   committed sections.
3. **"The existing autonomous-safe-decision policy"** (Goal, paragraph 3):
   **Resolution:** confirmed this refers to `finding-categorization.md`'s
   bucket dispositions and hard-disqualifier zones. The bundle's own
   REQ-G1.2/D-18 language ("deterministic script logic operating on
   structured signals") is the Auto-applicable bucket's
   tool-grounded/mechanical/no-user-observable-change shape, and D-6/D-19
   explicitly reason from the hard-disqualifier zones. The brief cites
   `finding-categorization.md` directly rather than leaving the reference
   implicit.

Signed off: 2026-07-14

## 3. Requirements walkthrough

**REQ-A — Liveness & recovery (8→9 reqs).** Restatement: worker state
transitions push via native hooks the instant they occur, falling back to
capture-pane polling only where a backend can't register hooks. Exactly one
of five states; `flailing` (heartbeating, no progress) escalates to a human,
never auto-nudged. Crashes back off on an escalating schedule and disable
after a threshold. Tower death recovers mode-aware (cron-relaunch for
unattended, signposted `--resume` for interactive, never auto-resumed).
Every kill/cleanup/restart mechanism gates on positive evidence of death.
Push is a latency optimization; a periodic ground-truth reconcile is the
correctness backstop regardless.

Gaps surfaced and resolved:
- **"idle/done" terminology** — confirmed "done" was shorthand for the
  existing merged-and-idle cleanup case (REQ-B1.1), not a distinct liveness
  state. Fixed (expression-only): REQ-A1.1 and D-1 reworded
  "working→idle/done" to "working→idle."
- **No crash-loop backoff for towers** — REQ-A1.4/D-3's escalating
  backoff/disable applied only to workers; REQ-A1.5/D-4's cron watchdog had
  no analogous treatment, so a crash-looping tower would be relaunched every
  cron tick forever with no human escalation. Fixed (meaning-class, new
  requirement): added **REQ-A1.9**, amended D-4 with the added alternative,
  updated Task 3's deliverables/done-when/citations, added a test-spec.md
  entry.

**REQ-B — Cleanup & housekeeping (3 reqs).** Restatement: deterministic
cleanup with a self-targeting guard (closes the `#29787` postmortem
directly); worktree lifecycle hook-pushed instead of disk-scanned; a
periodic sweep covers every tracked working tree, including the tower's own
checkout on whatever branch, escalating stale diffs rather than letting
them silently ride through a handover or crash.

Gap surfaced and resolved:
- **REQ-B1.2's fallback wasn't stated in the REQ text** — `test-spec.md`
  already tested a disk-scan fallback and D-7's alternatives-considered
  implied one, but the REQ itself only specified the hook-push path.
  Fixed (expression-only): added the explicit graceful-degradation clause,
  matching REQ-A1.1's pattern.

**REQ-C — Context-budget corroboration (2 reqs).** Restatement: a peer-pane
`/context` capture corroborates the step-count proxy, capability-gated and
idle-only; a parse failure degrades to the proxy with a warning, never an
opaque halt. No gaps surfaced.

**REQ-D — Relay hygiene (2 reqs).** Restatement: ghost-text prevented at the
source via an environment variable on every fleet-launched session read via
pane capture; the backspace-probe detection method stays documented as an
optional, undispatched fallback, never the required path. No gaps
surfaced.

**REQ-E — Resource governance (4 reqs).** Restatement: model/effort/command
selection is a deterministic rule table, never a confidence-calibrated
cascade (the survey found calibration an open, disproportionate problem
here); throttling is reactive off Claude Code's own rate-limit signal (no
proactive quota API exists, confirmed against three closed GitHub issues);
`auto` permission mode is rejected for worker dispatch on two independent
grounds. No gaps surfaced.

**REQ-F — Operator control & observability (4 reqs).** Restatement: stats
derived/rendered on demand, never a new shared-write file (avoiding the
concurrent-write class `observation-recording` already hit); a `statusline`
value added to the existing `notification_channel` enum; an operator
kill-switch pauses every daemon action without disabling the fleet; every
daemon action logs to an audit trail. No gaps surfaced.

**REQ-G — Fleet coordination floor (5 reqs).** Restatement: towers
dispatch/monitor/reconcile only, never author changes except as a flagged
human-routed exception; no daemon/hook/cron mechanism invokes an LLM for a
routine decision; multi-tower coordination reuses the existing advisory
lock; fleet sessions are session-per-tower isolated; every new knob
resolves through the existing overlay mechanism. **Flagged, not resolved
here:** the bundle's Sources cite "the doctrine-gap(tower-role)
observation" verbatim — a "that's a doctrine gap"-shaped seed claim per
`autopilot-reflex.md` — which should trigger an altitude check on D-17/D-18.
Deferred to §4 (Design walkthrough), where D-17/D-18 are reviewed directly.

**Consolidated spec-edit list (this section):**
1. `requirements.md`: REQ-A1.1 reworded (idle/done → idle), REQ-A1.9 added,
   REQ-B1.2's fallback clause added, Changelog entry added.
2. `design.md`: D-1 reworded to match, D-4 amended with the added
   alternative, Changelog entry added.
3. `tasks.md`: Task 3's Deliverables/Done-when/Citations updated for
   REQ-A1.9.
4. `test-spec.md`: REQ-A1.9 entry added, Changelog entry added.

Signed off: 2026-07-14

## 4. Design walkthrough

**Reconciled ledger — all 22 D-IDs accounted for:**

| D-ID | Decision | Status |
| --- | --- | --- |
| D-1 | Push-first liveness, reconcile backstop | Amended (idle/done → idle wording) |
| D-2 | Four distinct worker states incl. `flailing` | Confirmed |
| D-3 | Escalating worker crash-loop backoff + disable | Confirmed |
| D-4 | Mode-aware tower-liveness recovery | Amended (added tower backoff/disable, REQ-A1.9) |
| D-5 | Positive-evidence-of-death shared predicate (C, orchestration-fleet D-2) | Confirmed |
| D-6 | Deterministic-script cleanup, self-targeting guard | Confirmed |
| D-7 | `WorktreeCreate`/`WorktreeRemove` hook-driven tracking | Confirmed |
| D-8 | Dirty-tree sweep scope incl. tower's own checkout | Confirmed |
| D-9 | Context-budget corroboration via peer-pane `/context` | Confirmed |
| D-10 | Ghost-text prevention via env var at dispatch | Confirmed |
| D-11 | Rule-based model/effort/command selection | Confirmed |
| D-12 | Reactive throttling off native rate-limit signal | Confirmed |
| D-13 | Fleet stats as a derived, rendered view | Confirmed |
| D-14 | `statusline` value on `notification_channel` | Confirmed |
| D-15 | Operator kill-switch for daemon layer | Confirmed |
| D-16 | Audit trail for daemon actions | Confirmed |
| D-17 | Tower non-authoring boundary | **Amended** — recorded as the altitude D-ID for the doctrine-gap(tower-role) seed-claim trigger (autopilot-reflex — Seed claims), now cited inline from the Goal |
| D-18 | No-LLM-daemon-mechanics invariant | Confirmed — separately motivated (the rate-limit bootstrapping-absurdity rationale), not itself an altitude decision |
| D-19 | Reject `auto` permission mode for fleet dispatch | Confirmed |
| D-20 | Multi-tower coordination reuses advisory lock (C, orchestration-concurrency D-4) | Confirmed |
| D-21 | Session-per-tower tmux isolation | Confirmed |
| D-22 | Every new knob resolves through overlay mechanism (C, customization-overlay D-1) | Confirmed |

**The altitude trigger, resolved.** `autopilot-reflex.md` names an explicit
"that's a doctrine gap" seed claim as a trigger requiring the bundle to
record its altitude call as an early D-ID cited from the goal. This
bundle's Sources cite "the doctrine-gap(tower-role) observation" verbatim —
a trigger of exactly this shape. The bundle already made the correct
substantive call (Task 1 commits to landing doctrine statements, not a
per-repo mechanism), but the citation artifact was missing. Fixed: D-17 is
now explicitly recorded as the altitude decision, cited inline as `(D-17)`
from the Goal's tower-non-authoring sentence — giving the sign-off lens
pass's altitude check (`autopilot-reflex` REQ-H1.3) a concrete D-ID, goal citation, and task
decomposition (Task 1) to verify against.

No other D-ID required amendment or carried a design decision that
contradicted a walked requirement (which would have been an inconsistency,
not a ledger entry).

Signed off: 2026-07-14

## 5. Verification approach

**Coverage.** All 29 REQs (including the kickoff-added REQ-A1.9) carry at
least one `test-spec.md` entry — full REQ↔test-spec coverage confirmed
(see `test-spec.md` for the authoritative per-REQ tags; not transcribed
here, per the cite-don't-copy convention).

**Coverage mix.** Predominantly `[test]`: the no-LLM-daemon-mechanics floor
(REQ-G1.2) makes nearly every mechanism deterministic script logic,
straightforwardly fixture-testable, including negative "zero LLM/API
calls" assertions. `[manual]` is reserved for behavior that is either
inherently visual (`statusLine` rendering), depends on a live integration
outside fixture control (a real host crash and relaunch, live `/context`
UI-text parsing), or concerns doctrine-judgment under a loose request
rather than a mechanism's output (the tower non-authoring boundary drill).
`[design-level]` entries are verified by artifact existence (a doctrine
statement, a documented Deferred gate, absence of a non-test caller).

**Dead-path check.** No REQ's named verification is unrunnable — every
`[design-level]` entry resolves to a concrete file/absence check, not
something that silently can't execute.

**Verification ownership gap, surfaced and recorded.** Five REQs carry
`[manual]` (A1.5, A1.6, C1.1, F1.2, G1.1) with no stated owner or cadence
anywhere in the bundle. **Resolution:** no formal owner/cadence is assigned
— the human operator (the bundle's author) will exercise these ad hoc as
the fleet mechanisms come into real use, rather than the brief inventing a
rotation or schedule this repo doesn't otherwise have. Carried to the risk
register (§7) as an open risk rather than left silently unstated.

Signed off: 2026-07-14

## 6. Task graph

**Reconstructed from `tasks.md`'s `Dependencies:` lines** (the sole source
of truth; no hand-drawn rendering kept here per `spec-format.md` —
`scripts/spec-graph.sh` renders the on-demand view):

- **Task 1** (2 days) is the sole foundational node. Every task except Task
  6 depends on it.
- **Task 6** (half day) has **no dependency on Task 1** — a deliberate
  non-edge: ghost-text prevention is a static env-var set unconditionally
  at dispatch, never a runtime kill/cleanup/restart/throttle decision, so
  it needs none of Task 1's kill-switch or audit-trail infrastructure.
  Recorded explicitly (and the intro prose, which previously claimed "every
  other task consumes its shared helpers," corrected to match) so this
  isn't mistaken for an oversight later.
- **Tasks 2, 3, 4, 5, 7** depend only on Task 1 and are otherwise mutually
  independent — the parallel fan-out.
- **Task 8** depends on **1, 2, 3, 4, 7** (corrected — see below).

**Effort-weighted critical path:** Task 1 (2d) → max(Task 2: 3d, Task 3:
3d, Task 4: 2d, Task 7: 2d) = 3d → Task 8 (1.5d) = **6.5 days**. Task 7's
addition to Task 8's dependencies doesn't change this figure (2d doesn't
exceed the existing 3d max). Tasks 5 (2d) and 6 (0.5d) run with slack off
the critical path. Wall-clock caveat: `max_parallel_units` defaults to 3,
so the post-Task-1 fan-out doesn't all run simultaneously in practice —
scheduling, not a graph property.

**Gap surfaced and resolved: Task 8 was missing a dependency on Task 7.**
Task 8's own Deliverables text renders "throttle-engaged state," which is
Task 7's output (REQ-E1.3's reactive throttling), not Tasks 2–4's — but
its `Dependencies:` line and Done-when fixture reference covered only
Tasks 2 and 4. Fixed (meaning-class): `tasks.md` Task 8's Dependencies
now reads `1, 2, 3, 4, 7`, its Deliverables/Done-when text updated to cite
Task 7, and the bundle-wide Changelog in `requirements.md` records the
amendment.

Signed off: 2026-07-14

## 7. Risk register

**Decision-domains gap check** (11 seed domains, `doctrine/decision-domains.md`
via `scripts/resolve-catalog.sh decision-domains`; no adopter/team overlay
additions present in this repo). Not triggered: caching, authentication &
authorization, dependency adoption, versioning scheme, data storage &
modeling (no new persistent store — reuses existing heartbeat-file/state-store
patterns), API surface design (the `statusline` enum addition follows the
existing options-reference convention). Triggered and already decided,
citing the governing D-ID: secrets & configuration (D-22/REQ-G1.5 — every
new knob resolves through the overlay mechanism and is documented),
observability (D-16/REQ-F1.4 — audit trail for every daemon action), deploy
& migration strategy (D-15 — the operator kill-switch is the rollback
lever: no atomic-rollout question left open). Triggered and **not yet
decided**: Concurrency / Queues & async — see Risk 1 below.

**Rows 5–39 added post-walkthrough, from the sign-off lens pass.** The
Discovery-Rigor fan-out below (nine parallel lenses over the finalized
bundle) surfaced roughly 35 additional findings beyond what the guided
walkthrough itself caught. Mechanical bugs in this session's own edits were
fixed directly (see the Changelog entries in `requirements.md`,
`design.md`, `test-spec.md`); the "nudge" phantom-mechanism finding was
resolved by striking it everywhere (same Changelog entry). Everything else
— concurrency races, missing cadence/cost bounds, security-enforcement
gaps, unspecified partial-failure paths, and additional correctness/test
gaps — is recorded below as accepted, Task-level risk, each citing the
existing floor it should resolve under, consistent with how Risk 1 was
already handled rather than expanding the spec's REQ count by ~35 for gaps
the bundle's existing floors (D-1, D-5, D-18, D-20) already partially
constrain.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | REQ-A1.5's cron-scheduled tower-liveness check may not be idempotent under its own overlapping invocations: two cron ticks close together could both observe "no live process" and both launch a fresh tower for the same dead tower — a different failure class from the bundle's general "reconcile heals a stale read next sweep" posture (D-1/REQ-A1.8), since a duplicate live tower isn't a stale read. **Decision-domains gap check:** Concurrency / Queues & async fires, undecided in the bundle. | Task 3 implements this using the existing advisory lock (D-20) or an equivalent re-verify-before-act guard, reusing D-5's positive-evidence-of-death check to re-confirm death immediately before relaunch rather than trusting the first observation. Early signal: two live tower processes observed for one spec in the wild. Accepted risk, not escalated to a new REQ — mechanism-level detail for Task 3's design, not a new architectural decision. **Sign-off lens pass note:** nothing in Task 3's Done-when or test-spec.md's REQ-A1.5 entry currently requires or tests this guard — Task 3's implementation should extend its own Done-when to cover it, since an accepted risk with no acceptance criterion can silently ship unmitigated. |
| 2 | Five `[manual]` verification entries (A1.5, A1.6, C1.1, F1.2, G1.1) have no assigned owner or cadence (§5). | No formal rotation exists in this repo to slot into; the human operator will exercise these ad hoc as the fleet mechanisms come into real use. Early signal: a real crash, throttle event, or `statusLine` regression going unnoticed for longer than feels acceptable — the trigger to revisit and assign a cadence. |
| 3 | The `flailing`-classification threshold (no-forward-progress heartbeat count) has no spec-pinned default (§2); a miscalibrated default could delay a genuine escalation or fire too eagerly. | Task 2 picks a default, resolved through Task 1's config-knob helper (D-22) — overlay-tunable, not hardcoded. Early signal: a flailing escalation firing on workers that were actually still progressing (too aggressive) or a genuinely stuck worker running unescalated for an uncomfortable stretch (too lax). |
| 4 | Task 3's REQ-A1.5 "ready work exists" check must call through to `/orchestrate`'s live ready-task selection rather than re-deriving readiness from `tasks.md`'s committed shape — `specs/invariant-tasks` (Status Ready, PR #171 open) is about to graduate `tasks.md` to format-version 2 and remove the committed `## Forward plan` section entirely (§2). | Already reflected in Task 3's Deliverables text (call-through, not re-implementation). Early signal: Task 3's implementation grepping `tasks.md` directly for section headings instead of calling the selection function — a code-review-time check, not a runtime one. |
| 5 | **Concurrency:** push (REQ-A1.1) and the periodic ground-truth reconcile (REQ-A1.8) write the same worker-state store with no specified precedence rule; a reconcile sweep that started before a fresher push completes could overwrite correct, newer state with stale data. | Task 2's implementation adopts last-write-wins-by-timestamp (or an equivalent sequence marker) between push and reconcile writes. Early signal: worker state observed flapping or regressing shortly after a legitimate transition. |
| 6 | **Concurrency:** REQ-A1.9's tower-relaunch failure counter is shared state with a read-modify-write race under overlapping cron ticks (the same root cause as Risk 1), distinct from the double-launch scenario — could double-count one crash (premature disable) or lose an increment (delayed disable). | Task 3 makes the counter update atomic (e.g. guarded by the same lock/re-verify step as Risk 1's mitigation). Early signal: the tower disabling after fewer relaunches than the configured threshold, or more. |
| 7 | **Concurrency:** no specified mutual exclusivity between the cron-relaunch path (REQ-A1.5) and the interactive-signpost path (REQ-A1.6) for the same dead tower if the unattended/interactive mode marker is stale, missing, or ambiguous at the moment of death — both could fire, producing two live actors reconciling the same spec's state. | Task 3 treats the mode marker itself as subject to REQ-A1.7's positive-evidence gate before choosing a recovery path, not just before acting within one. Early signal: a fresh cold-started tower and a human-resumed session observed active on the same spec simultaneously. |
| 8 | **Concurrency:** REQ-G1.3's advisory-lock reuse is cited by Task 3 only; Tasks 1, 2, 4, 7, and 8 write fleet-shared state (the audit trail, the decision queue, the throttle flag) without citing D-20, and REQ-G1.3's own test-spec entry only exercises a generic two-tower fixture that could pass while verifying just Task 3's lock use. | Task-level implementations of the audit-trail writer, decision-queue writer, and throttle-flag writer serialize through the same advisory lock D-20 already establishes; REQ-G1.3's test-spec entry is extended at Task-implementation time to name which mechanism it's exercising rather than staying generic. Early signal: interleaved or lost entries in the audit trail or decision queue under concurrent multi-tower load. |
| 9 | **Concurrency:** REQ-E1.3's reactive throttling has no conflict-resolution rule for multiple towers independently detecting the shared rate-limit signal with differing parsed reset times. | Task 7 resolves to the max of observed reset times (the conservative direction) rather than last-write-wins, which could resume dispatch before the account-level limit actually clears. Early signal: dispatch resuming and immediately re-triggering the same throttle. |
| 10 | **Concurrency:** the dirty-tree sweep (REQ-B1.3) has no re-verify-before-escalate step (unlike Risk 1's mitigation for tower relaunch) and no stated handling for git-lock contention when it reads a worktree another process is actively committing to — a naive implementation could misclassify a transient lock error as "no diff found," undermining REQ-B1.3's own escalate-don't-silently-persist mandate. | Task 4 re-checks dirty/clean immediately before writing a decision-queue entry, and treats a git-lock-contention error as retry-next-tick rather than clean. Early signal: a stale-diff finding escalated for a worktree that was actually clean by the time a human looks. |
| 11 | **Performance:** no REQ, design decision, task Done-when, or test fixture bounds the cadence or per-tick cost of any periodic sweep (the reconcile backstop REQ-A1.8, the dirty-tree sweep REQ-B1.3, the cron watchdog REQ-A1.5) — cost as fleet size grows is unverifiable and un-gated. | Task 3/4 pick and document a concrete interval at implementation time, resolved through the overlay mechanism (D-22) like every other knob. Early signal: sweep wall-clock cost growing visibly as tracked-worktree count grows. |
| 12 | **Performance:** Task 4 conflates two independent O(n)-per-tracked-tree jobs (the dirty-tree sweep and the REQ-A1.8 liveness reconcile) into one sweep with no discussion of compounded per-tree cost or incremental/changed-only scoping. | Task 4's implementation considers batching, caching, or changed-only re-checks (e.g. by mtime or heartbeat-file change) rather than a full linear pass on every tick. Early signal: sweep duration scaling faster than tracked-tree count would suggest. |
| 13 | **Performance:** REQ-A1.5's cron check runs per-spec and calls through to `/orchestrate`'s live ready-task selection on every tick — cost scales with the number of concurrently active specs, unbounded by anything in this bundle. | Task 3 treats this as a known scaling factor to measure at implementation time rather than a correctness concern; `/orchestrate`'s own selection cost (Risk 4's call-through) is the actual bound to watch. Early signal: cron-check duration growing with active-spec count. |
| 14 | **Performance:** D-13's "render on demand, same shape as `fleet-attention.sh`" analogy may not hold for cumulative counters (nudge — now removed — watchdog-trip, etc.) if they're computed by scanning the full audit trail rather than an incrementally-maintained value; REQ-F1.2 wires this into `statusLine`, a high-frequency-invoked surface, compounding any per-render scan cost. | Task 8 either maintains lightweight incremental counters alongside the audit trail (not a new shared-write file — still derived, just cheaper to derive) or explicitly bounds the scan window (e.g. only recent history) rather than a full-log scan on every `statusLine` invocation. Early signal: `statusLine` rendering latency growing with fleet operating history length. |
| 15 | **Performance:** the peer-pane `/context` corroboration mechanism (REQ-C1.1) is, mechanically, exactly the capture-pane polling pattern the Goal names as the problem this spec eliminates — no cadence, debounce, or acknowledgment of the tension is stated anywhere. | Task 5 states an explicit cadence (e.g. once per idle-transition, not continuous-while-idle) and the design accepts this one first-class mechanism is poll-shaped by nature, distinct from the fallback paths. Early signal: peer-pane resource usage or turn cost from this mechanism growing disproportionately at fleet scale. |
| 16 | **Performance:** REQ-A1.1's capture-pane fallback for hook-incapable backends is named but which of the four backends (`subagent`/`tmux`/`print`/`in-session`) actually lack hook support — and what fraction of a typical fleet that represents — is never stated or bounded. | Documented at Task 2 implementation time: which backends fall back, and an acknowledgment that a fleet composed significantly of that backend reverts to the pre-spec polling cost for that slice. Early signal: a fleet running mostly on a fallback backend seeing no liveness-latency improvement. |
| 17 | **Performance/Tests:** the dirty-tree/reconcile sweep's fixtures (Task 4, REQ-A1.8, REQ-B1.3) are all single-item (one stale tree, one dropped push) — no fixture exercises cost or correctness at multi-worktree scale. | Task 4 adds at least one multi-worktree fixture at implementation time as a regression gate for scaling behavior, not just per-item correctness. Early signal: none currently possible — this is a test-coverage gap, not a runtime signal. |
| 18 | **Performance:** the audit trail (D-16/REQ-F1.4) is written on every daemon action, fleet-wide, indefinitely, with no stated retention, rotation, or indexing strategy, despite REQ-F1.4/test-spec's "queryable by mechanism and time range" implying range-scan support. | Task 1's audit-trail helper adopts a rotation or windowing policy at implementation time (e.g. time-bounded files), resolved through the overlay mechanism if made configurable. Early signal: audit-trail query latency or storage size growing unbounded over the fleet's operating lifetime. |
| 19 | **Security:** REQ-E1.4/D-19's `auto`-permission-mode rejection is specified in terms of a launched process's `--permission-mode` flag; a `subagent`-backend worker (an in-process Task-tool invocation, not a freshly launched process) inherits its permission mode from the hosting tower session, with no guard or test covering this path. | Task 7's auto-mode guard is extended to check the *effective* inherited mode for in-process dispatch, not just an explicit launch flag. Early signal: a `subagent`-backend worker observed operating under an inherited `auto` mode. |
| 20 | **Security:** D-19 itself documents that `defaultMode: "auto"` is settable in an operator's own `~/.claude/settings.json`; nothing requires dispatch to explicitly force a non-auto mode to override that ambient default for `tmux`/`print`/`in-session` backends — only the explicit-flag case is guarded/tested. | Task 7's dispatch invocation explicitly passes a non-auto mode rather than relying on absence of the auto flag. Early signal: a worker observed running under an operator's ambient `auto` default despite no explicit flag being passed. |
| 21 | **Security:** the operator kill-switch's (D-15) resolving config layer has no stated write-authorization boundary, unlike `config/worker-settings.json` which D-19 explicitly restricts to human-reviewed/human-installed status. | Task 1 documents (and ideally enforces) that the kill-switch's config layer is restricted the same way `worker-settings.json` is, so a dispatched worker's allowlisted git-write permissions can't flip the fleet's own emergency-stop lever. Early signal: a kill-switch state change traced to a worker-authored commit rather than a human. |
| 22 | **Security:** the orphaned-tower marker (REQ-A1.6/D-4) that produces the human-facing `claude --resume <session-id>` recovery command has no stated format-validation or write-restriction, and workers share the same fleet state area as the tower. | Task 3 validates the marker's `session-id` field against an expected format before surfacing it, and applies Task 1's control-free text grammar (already required for the audit trail) to this surface too. Early signal: a surfaced resume command that doesn't match any real session ID. |
| 23 | **Security:** pane-captured UI text (the `/context` corroboration, the general capture-pane liveness fallback, the rate-limit-prompt text) is not required to be stripped of control/ANSI escape sequences before being re-displayed in a warning, decision-queue entry, or `statusline` render — unlike the audit-trail write path, which Task 1 already grammar-validates. | Task 5/2/7's capture-pane consumers apply the same control-free sanitization discipline Task 1 established for the audit trail before any captured text is re-displayed to the operator. Early signal: unexpected terminal rendering artifacts in a decision-queue entry or `statusline` line. |
| 24 | **Security:** the rate-limit-prompt parse path (D-12/REQ-E1.3) has no stated malformed-input degrade behavior, unlike its `/context`-parsing sibling (REQ-C1.2 explicitly degrades with a warning, never halts opaquely). | Task 7 applies the same degrade-with-warning discipline REQ-C1.2 already establishes to a malformed or unexpected rate-limit-prompt rendering. Early signal: fleet-wide dispatch pausing indefinitely or resuming immediately due to a garbage parsed reset time. |
| 25 | **Security:** no requirement states that the new hook payloads this bundle wires up (`Stop`, `PermissionRequest`, `PostToolUse`-after-pending, `SessionEnd`, `StopFailure`, `WorktreeCreate`, `WorktreeRemove`) must be parsed as JSON and their fields quoted/escaped before use in a shell command, file path, or state-store write. | Task 1's shared helpers (or each task's own hook-consuming code) treat inbound hook payload fields as data, never interpolated unescaped into a command — the same discipline `security-posture.md` already requires framework-wide. Early signal: a hook script observed constructing a command via string interpolation of a payload field. |
| 26 | **Error handling:** aside from REQ-A1.1/A1.8 (push failure) and REQ-C1.2 (`/context` parse failure), nearly every other daemon mechanism's partial-failure path is unspecified: audit-trail write failure, decision-queue write failure, kill-switch resolution failure, advisory-lock acquisition failure, worktree-hook write failure on a capable backend, sweep-internal per-tree exceptions, the death-predicate's own error path, capture-pane command failure (vs. parse failure), unmapped rule-table entries, the auto-mode guard's own bypass path, and session-isolation creation failure. | Each Task's implementation states what happens on its own mechanism's partial failure, following the same pattern REQ-A1.1/A1.8/C1.2 already established (degrade with a warning or escalate to the decision queue, never fail opaquely). Early signal: any of the above failing silently in practice — the pattern to watch for during Task-level implementation review. |
| 27 | **Correctness:** REQ-A1.1 defines a target state for four of five hook events but not `StopFailure` — unclear whether it maps to `hung`, `idle`, or something else in the five-state classifier. | Task 2 picks and documents the mapping (most naturally `hung`, given "turn ended on an API error" resembles a stopped-responding worker) as part of its implementation, resolved through Task 1's classifier design. Early signal: a `StopFailure` event observed leaving a worker's classified state unclear or unchanged. |
| 28 | **Correctness:** REQ-A1.1 defines `awaiting-human→working` via the next `PostToolUse` after a pending `PermissionRequest`, but not what happens when the human denies the request and the turn ends with no further tool use — a worker could stay classified `awaiting-human` indefinitely pending REQ-A1.8's reconcile sweep (itself under-specified per Risk 26). | Task 2 relies on REQ-A1.8's reconcile sweep to resolve this via ground-truth (e.g. `SessionEnd` or a subsequent `Stop` clears it), and documents that reliance explicitly rather than leaving it implicit. Early signal: a worker observed stuck `awaiting-human` after a denied permission with no further activity. |
| 29 | **Correctness:** REQ-A1.2 cites REQ-A1.7's positive-evidence-of-death predicate for classification itself, but REQ-A1.7's own text scopes to mechanisms that "kill, clean up, or restart" — not mere classification, which is inherently timeout-adjacent (a stopped heartbeat is detected by elapsed time). | Task 2's classifier documents its own timeout-vs-evidence boundary for `hung`/`flailing` classification specifically, rather than relying on REQ-A1.7's destructive-action-scoped language to cover it by extension. Early signal: none currently testable — a spec-clarity gap to resolve during Task 2's design. |
| 30 | **Correctness:** Task 7 has no audit-trail Done-when clause (unlike Tasks 2/3/4) and doesn't cite D-16/REQ-F1.4, yet Task 8 depends on Task 7 and expects to render its throttle-engagement audit data. | Task 7's Done-when is extended at implementation time to require throttle-engagement events log through Task 1's audit-trail helper, matching Tasks 2–4's pattern. Early signal: Task 8's throttle-engaged-state rendering having no audit data to draw from. |
| 31 | **Correctness:** Task 2's Done-when as written ("every classification and backoff action logs through Task 1's audit-trail helper") over-scopes REQ-F1.4, which only requires logging for nudge (removed)/cleanup/restart/throttle actions — not routine, continuous state classification. | Task 2's implementation logs backoff/restart actions per REQ-F1.4 but not every classification transition, avoiding the high-frequency shared-write pattern D-13 was designed to avoid for stats. Early signal: audit-trail volume dominated by routine classification noise rather than actual daemon actions. |
| 32 | **Correctness/Tests:** REQ-A1.9/D-4's tower crash-loop backoff is specified as "the same escalating schedule as REQ-A1.4" without stating whether towers and workers share one counter/config or have independently-configured, structurally-identical schedules — given REQ-G1.5 requires independent knob resolution and very different cardinality (many workers, one tower per spec), a shared counter would be a real bug. | Task 3 documents that the tower schedule uses its own independently-configured knob (per REQ-G1.5), structurally identical to REQ-A1.4's but not sharing state with it. Early signal: a worker crash observed affecting the tower's own backoff counter or vice versa. |
| 33 | **Correctness:** REQ-A1.2's "exactly one of five states" has no defined initial/default state for a freshly-dispatched worker between dispatch and its first hook/heartbeat event. | Task 2 documents the startup default (most naturally `working`, since dispatch implies immediate activity). Early signal: none currently testable — a minor spec-clarity gap. |
| 34 | **Correctness:** Task 5 (context-budget corroboration) has no audit-trail requirement and, unlike Task 6's explicit deliberate-non-edge justification, no stated rationale for the omission. | Task 5's scope note documents that corroboration isn't a "daemon action" under REQ-F1.4's enumeration (it doesn't nudge/cleanup/restart/throttle), matching the same reasoning Task 6 already states explicitly for its own omission. Early signal: none — a documentation-completeness gap. |
| 35 | **Tests:** Task 1's Done-when requires audit-trail writes be "validated against a control-free text grammar before write," but REQ-F1.4's test-spec entry only asserts a normal write succeeds and is queryable — no fixture exercises the rejection/sanitization path for a malformed (control-character-containing) trigger/reasoning string. | Task 1's test-spec entry (or a Task 1 fixture) is extended at implementation time to cover the rejection path, not just the happy path. Early signal: none currently testable — a test-coverage gap. |
| 36 | **Tests:** REQ-B1.3's only fixture covers the tower's-own-checkout case (the newer, riskier D-8 addition); no fixture explicitly covers a plain worker-worktree stale diff, even though REQ-B1.3's own text scopes to "every worker worktree and the tower's own checkout." | Task 4 adds a worker-worktree fixture alongside the tower-checkout one at implementation time. Early signal: none currently testable — a test-coverage gap. |
| 37 | **Tests:** REQ-A1.2's classifier and REQ-A1.7's positive-evidence predicate each have their own isolated test coverage, but no fixture proves the classifier is actually wired to call through to the predicate rather than a bare timeout, which is the composed behavior REQ-A1.2's own text demands. | Task 2 adds an integration-level fixture proving the classifier calls REQ-A1.7's predicate, not just that each piece behaves correctly standalone. Early signal: none currently testable — a test-coverage gap. |
| 38 | **Tests:** REQ-F1.2's test-spec entry doesn't assert the `docs/options-reference.md` documentation or `check-options-reference.sh` pass that Task 8's own Done-when requires for the new `statusline` enum value — the convention exists elsewhere in the same file (REQ-G1.5 does assert it) but wasn't applied here. | Task 8's REQ-F1.2 test-spec entry is extended at implementation time to match REQ-G1.5's existing convention. Early signal: none currently testable — a test-coverage gap. |
| 39 | **Documentation:** `test-spec.md`'s coverage-mix intro paragraph defines `[test]` and `[manual]` but never defines `[design-level]`, despite it being used four times in the file (the definition currently lives only in this brief's §5, outside `test-spec.md` itself). | `test-spec.md`'s intro paragraph is extended at the next `test-spec.md` edit to define `[design-level]` inline, matching this brief's §5 definition. Early signal: none — a documentation-completeness gap. |

No open question remains unresolved: every item above either cites its
mitigation and early signal (accepted risk) or was already fixed directly
(the mechanical bugs and the "nudge" strike, both recorded in
`requirements.md`'s Changelog).

### Task 1 execution research notes (2026-07-16)

Appended by `/execute-task` per REQ-D1.5/REQ-E1.3 (research scoping declared
light per `proportionality`: no new dependency, no external API; sources are
in-repo precedent plus POSIX/tool semantics).

- **Death-evidence probes.** `kill -0` (EPERM = exists) and the targeted
  `ps -p <pid>` exit contract (0 found / 1 not found) are POSIX-specified and
  stable on the macOS/Linux support bar; a per-pid query was chosen over any
  process-listing scan because a truncated listing is exactly the 2026-06-12
  failure source. tmux probes (`ls` / `has-session` / `list-windows`, `=`
  exact-match targets) follow `orchestrate-relay.sh`'s existing handle
  discipline; any server-level probe failure is treated as lost observability
  (`unknown`, refuse) rather than parsing version-sensitive tmux error text.
  Addresses risk row 26's death-predicate error path.
- **Audit-trail windowing (risk 18).** UTC daily files
  (`audit/audit-<YYYY-MM-DD>.tsv`) adopted as the rotation policy: retention
  is whole-file pruning, operator-owned; no retention knob shipped until a
  consumer needs one (growable via the shared resolver).
- **Lock serialization (risk 8).** Audit writes serialize through
  `fleet-state.sh`'s existing advisory lock (the same cross-spec primitive
  `fleet-attention.sh` holds for the same store area — the per-spec D-20
  lock cannot serialize cross-spec writers, so no second primitive is
  introduced), with the timestamp stamped under the lock and the
  fleet-attention signal-trap release discipline installed. Each write lands
  via copy-append-rename (the fleet-state register discipline), so lockless
  readers always see a complete file; a bare append has no atomicity
  guarantee at this row size.
- **Kill-switch write authorization (risk 21).** Documented (options
  reference + gate header + defaults comment): the knob's resolving layers
  are human-owned surfaces outside a dispatched worker's allowlisted write
  set, matching `config/worker-settings.json`'s posture. Filesystem-level
  enforcement is not possible from a config reader; the boundary is the
  worker permission allowlist, unchanged by this task.

### Task 2 execution research notes (2026-07-17)

Appended by `/execute-task` per REQ-D1.5 (research scoping declared light
per `proportionality`: no new dependency; the one version-sensitive surface
is the Claude Code hook-event contract, verified against the current
official docs rather than model memory).

- **Hook-event contract re-verified (D-1).** All five events REQ-A1.1 names
  exist under those exact names in the current hooks reference (`Stop`,
  `SessionEnd`, `PostToolUse`, `PermissionRequest`, `StopFailure`;
  code.claude.com/docs/en/hooks, fetched 2026-07-17). Every payload carries
  `session_id`/`hook_event_name`; `SessionEnd` carries a `reason`;
  `StopFailure` supports an `error_type` matcher. A plugin's
  `hooks/hooks.json` may register all five with the settings.json schema and
  `${CLAUDE_PLUGIN_ROOT}` expansion, and hook commands inherit the launched
  process's environment — which is what makes the dispatch-time
  worker-identity env contract (`PLANWRIGHT_WORKER_HANDLE`/`_SCOPE`) viable
  as the hook handler's gate.
- **Backend fallback boundary (risk 16).** Hook-push covers only the `tmux`
  backend: it is the one backend whose dispatched process planwright itself
  launches, so the identity env is inherited and plugin hooks fire. The
  `subagent` backend runs workers in-process (per-worker session hooks do
  not exist; `SubagentStart`/`SubagentStop` fire in the parent session),
  `in-session` shares the tower's own session, and `print` spawns no
  process at all — the human runs the printed command by hand, so the
  dispatch env is never injected, and the backend capability contract
  already exempts print-backend units from the liveness predicate. (Hooks
  do fire in `-p` sessions generally, per the current docs; that is
  irrelevant to `print` because the launch is not dispatch-controlled —
  corrected against `doctrine/backend-capability-contract.md` during the
  Task 2 convergence pass.) All three fall back to the existing observation
  path (`orchestrate-relay.sh observe-command` / tower-inline); a fleet
  composed mostly of those backends keeps pre-spec observation latency for
  that slice.
- **Backoff schedule precedent (D-3).** Exponential doubling from a
  configurable base with a hard cap, disable at a configurable consecutive-
  failure threshold (default 3): the PM2 `exp-backoff-restart-delay` /
  supervisord `startretries` / claude_code_agent_farm 3-strike shape D-3
  already cites; no newer precedent found that changes it.

### Task 3 execution research notes (2026-07-17)

Appended by `/execute-task` per REQ-D1.5/REQ-E1.3 (research scoping declared
light-to-moderate per `proportionality`: no new dependency; the
version-sensitive surface is Claude Code's own hook/session contract, so the
official docs were consulted rather than model memory).

- **SessionStart hook contract (REQ-A1.6), verified against the hooks doc.**
  `SessionStart` supports a `matcher` filtering on the `source` field
  (`startup`/`resume`/`clear`/`compact`); the signpost registers under
  matcher `startup` and re-checks a provided stdin `source` defensively.
  Plain hook stdout is added to the session's context (exit 0), so the
  signpost needs no jq dependency; hook failures are non-blocking, and the
  script additionally always exits 0 (a broken fleet home must never break
  someone's session startup).
- **Resume semantics (REQ-A1.6), verified against the sessions doc.**
  `claude --resume <session-id>` restores the full transcript after a hard
  crash, but must run from the directory the session started in — which is
  why markers record a canonical checkout path and the signpost matches it
  byte-for-byte against the starting session's project dir before surfacing
  anything.
- **Session-id capture (risk row 22).** The hook input's `session_id` and
  headless `--output-format json`'s `session_id` are the documented id
  surfaces; the only env surface exposed to Bash/hook subprocesses is
  `CLAUDE_CODE_BRIDGE_SESSION_ID` (v2.1.199+), documented in a `session_`-
  prefixed form that may not equal the resume UUID verbatim. The marker
  helper therefore validates `--session-id` strictly as a UUID and treats
  the field as optional; a sessionless or malformed field is never surfaced
  as a resume command. Recorded as an observation for later hardening of
  the capture path.
- **Detached relaunch shape (REQ-A1.5, REQ-G1.4).** The continue-as-new doc
  names headless `claude -p` as the documented launch path, but a cron
  watchdog must not block for the tower's whole lifetime, and D-21 requires
  session-per-tower isolation anyway — so the default launcher starts a
  DETACHED tmux session (`tmux new-session -d -s planwright-tower-<spec> -c
  <checkout>`) wrapped in `fleet-dispatch-env.sh` (D-10), waking
  `/orchestrate --watch --unattended`. A session-name collision refuses the
  launch rather than reusing or targeting an existing session.

### Task 7 execution research notes (2026-07-17)

Appended by `/execute-task` per REQ-D1.5/REQ-E1.3 (research scoping declared
light per `proportionality`: no new dependency, no external network API;
sources are D-12's already-recorded external research — Claude Code
issues #38380/#40793/#33820, the amux fleet-recovery precedent — plus in-repo
precedent and POSIX/tool semantics).

- **Rate-limit parse grammar (risk 24).** The native rate-limit prompt is
  version-sensitive UI text with no stable spec, so `fleet-throttle.sh
  observe` recognizes a deliberately small grammar (relative "in N
  seconds/minutes/hours"; wall-clock "resets [at] H[:MM]am/pm" and 24-hour
  "HH:MM", computed as next local occurrence without `date -d`/`-j`, which
  differ across BSD/GNU) and degrades any other rendering to the bounded
  `fleet_throttle_default_hold` with a warning. An 8-day sanity ceiling
  refuses garbage epochs outright (the longest native limit window is
  weekly). DST can skew a next-occurrence computation by an hour; accepted —
  a too-early resume just re-fires the native signal and re-engages
  (self-healing, the conservative max rule preserved).
- **Max-of-resets under the fleet lock (risk 9).** The throttle flag lives
  under the fleet home and its read-modify-write serializes through
  `fleet-state.sh`'s cross-spec advisory lock (risk 8's floor; no second
  primitive), landing via write-temp-rename so lockless `check` readers
  never see a torn value. Audit rows are written **after** lock release:
  `fleet-audit.sh` takes the same lock, so recording under it would
  deadlock — the ordering is deliberate, not an oversight.
- **Model knobs as stable aliases (D-11/D-22).** The per-tier model knobs
  validate against the Claude Code alias enum (`fable opus sonnet haiku`)
  rather than dated model ids: aliases track model releases without a
  config or script edit, and the shared resolver's enum type gives the
  customization-overlay REQ-E1.4 by-layer malformed policy for free (that
  bundle's REQ-E1.4, not this one's auto-mode REQ-E1.4). Effort and command
  are fixed
  table cells — config can retune cost, only a reviewed code change can
  alter what commands the fleet dispatches.
- **Auto-mode guard's inherited-mode proxy (risks 19, 20).** No supported
  introspection exposes a live session's effective permission mode, and
  D-19 records that `defaultMode: "auto"` is honored only from the
  operator's own user settings (deliberately ignored in project settings).
  The deterministic checkable proxy is therefore that file:
  `check-inherited` refuses in-process dispatch when the user settings pin
  auto, and `check-launch` demands an explicit non-auto mode source in the
  launch argv (flag or a readable settings fragment pinning a non-auto
  `defaultMode`) so the ambient user-settings default can never leak into a
  launched worker. The settings peek is a read-only grep-shaped scan (no
  jq on the support bar); the fragment path from the argv is never
  executed, only read, and all diagnostics pass the echo-discipline
  sanitizer.

### Task 4 execution research notes (2026-07-17)

Appended by `/execute-task` per REQ-D1.5 (research scoping declared light per
`proportionality`: no new dependency; the one external fact is a
version-sensitive Claude Code hook contract, verified against the official
docs — `https://code.claude.com/docs/en/hooks.md` — not model memory).

- **`WorktreeCreate` is a decision-control hook, not a passive observer
  (extends risk 25).** The verified contract: `WorktreeCreate` receives
  `worktree_path` + `isolation` on stdin, and **"any non-zero exit code causes
  worktree creation to fail"** — the command hook is expected to print the
  worktree path on stdout, and "hook failure or missing path fails creation."
  `WorktreeRemove` receives `worktree_path` and is fire-and-forget ("failures
  are logged in debug mode only"). Risk 25 anticipated the payload-as-data
  concern but not this failure mode: a naive tracking command wired into
  `WorktreeCreate` would **break all worktree creation fleet-wide** if it ever
  exited non-zero or emitted no path. Mitigation shipped: the `WorktreeCreate`
  handler (`fleet-worktree-track.sh hook-create`) is a strict pass-through — it
  echoes back exactly the stdin `worktree_path` and **always exits 0**, doing
  the registry write as a fully isolated best-effort side effect whose failure
  can change neither stdout nor the exit code (degrade capability, never
  safety). Because wiring a decision-control hook has a fleet-wide blast radius,
  the `hooks.json` `WorktreeCreate` entry is surfaced as a **Needs-sign-off**
  item in the PR — the human approves the decision-control wiring by leaving the
  commit, or reverts that single entry. Correction (self-review, 2026-07-17):
  worktree lifecycle tracking as shipped in Task 4 is **hook-driven only**
  (`WorktreeCreate`/`WorktreeRemove`); the REQ-B1.2 / D-7 disk-`scan`
  self-healing fallback exists as a manual `fleet-worktree-track.sh scan` CLI but
  is **not wired to run periodically** — the housekeeping sweep reads the
  registry (`list`), it does not `scan`. So reverting the `WorktreeCreate` entry
  drops automatic creation-tracking until the scan fallback is wired (removal
  tracking via `WorktreeRemove` is unaffected). Wiring that fallback is a
  follow-up (recorded as an observation).
- **Payload fields are data (risk 25).** Both handlers parse the JSON with `jq`
  (present) or a bounded `sed` fallback (the same jq-with-graceful-degrade
  pattern `tasks-pr-sync.sh`'s PostToolUse hook already uses), then run the
  extracted path through the same validation the direct CLI applies before it
  reaches any git command or the registry — never interpolated unescaped.
- **Sweep re-verify + git-lock contention (risks 10, 30/error-handling).** The
  dirty-tree sweep re-checks dirty/clean immediately before writing a
  decision-queue entry, and treats an unreadable/locked working tree as
  retry-next-tick (it escalates a "could not inspect" note rather than
  misreading contention as clean) — REQ-B1.3's escalate-don't-silently-persist
  mandate holds even under a concurrent committer.
- **Multi-worktree + worker-worktree fixtures (risks 12, 17, 36).** The sweep's
  test suite exercises multiple tracked trees in one pass and covers a plain
  worker-worktree stale diff alongside the tower's-own-checkout case, closing
  the single-item-fixture and worker-worktree coverage gaps.

Signed off: 2026-07-14

## 8. Sign-off

**Lens review pass.** First activation — full-bundle scope. Fanned out one
read-only sub-agent per canonical lens (nine lenses: correctness/edge
cases, security, error handling, performance, concurrency/state,
naming/readability, documentation, tests/verification, cross-file
consistency) over the finalized five-file bundle. One finding (a citation
the cross-file lens flagged) was checked against `spec-format.md`'s
citation-kind table directly and confirmed a false positive — declined.
All other findings were merged, deduped across overlapping lenses, and
dispositioned with the human: five mechanical bugs fixed directly, the
"nudge" phantom-mechanism finding resolved by striking it everywhere, and
~35 architecture-level findings (concurrency, performance, security,
error-handling, additional correctness/test gaps) recorded as accepted,
Task-level risks in §7 rows 5–39, each citing an existing floor (D-1, D-5,
D-18, D-20) or an early signal to watch for.

Lens-coverage table:

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 17 | Merged into §7 rows 5–6, 27–34 and the Task 8/test-spec staleness fix (Cluster 1 item 3); one (the `flailing`/`hung` timeout-vs-evidence scope question, row 29) is a spec-clarity gap, not yet a bug. |
| Security | 8 | Merged into §7 rows 19–25; no artifact self-leakage found (no secrets/credentials/hostnames in any of the five files). |
| Error handling and failure modes | 1 (consolidated) | Merged into §7 row 26 — a single cross-mechanism finding naming every under-specified partial-failure path at once. |
| Performance | 8 | Merged into §7 rows 11–18. |
| Concurrency / state | 8 | Merged into §7 rows 5–10 and Risk 1's strengthened mitigation note. |
| Naming, readability, structure | 6 | Two real (the "six/five" miscount, Cluster 1 item 1; the "nudge" phantom category, Cluster 2), one declined as covered elsewhere (D-4's split Alternatives-considered structure — cosmetic, not reflagged as a separate fix), three confirmed clean (ID consistency, terminology stability, Changelog accuracy baseline). |
| Documentation | 3 | All fixed: two Changelog-completeness gaps and the missing `#29787` Sources entry (Cluster 1 items 4–5). |
| Tests / verification | 8 | One fixed as a live staleness bug (Task 8/test-spec `Tasks 2, 3, 4, 7` fix, Cluster 1 item 3); seven merged into §7 rows 35–38 plus the `[design-level]`-tag documentation gap (row 39). |
| Cross-file consistency | 4 | One declined false positive (REQ-A1.9's citation kind); three real, all fixed (Task 8/test-spec staleness — same finding as the Tests lens hit independently; the REQ-H1.3 phantom citation, Cluster 1 item 2). |

**Kickoff-specific altitude check (`autopilot-reflex` REQ-H1.3).** Triggered:
the bundle's Sources cite "the doctrine-gap(tower-role) observation"
verbatim, a "that's a doctrine gap"-shaped seed claim per
`autopilot-reflex.md`. Verified in §4: the altitude D-ID (D-17) exists, is
now cited inline from the Goal (`(D-17)`), and the task decomposition
matches the claimed altitude (Task 1 commits to landing doctrine
statements for the tower non-authoring boundary and the
no-LLM-daemon-mechanics invariant, not a per-repo mechanism).

All findings dispositioned. No inconsistency halt, no carried open
question, no undispositioned finding.

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-14.
Anchor: `ab8a99987ec6145f6c134da8130347bdd73e5a56` — computed as
`scripts/spec-anchor.sh specs/fleet-autonomy`

## 9. Amendment log

### 2026-07-15 — Expression-only self-re-anchor (format-version 2 migration)

Machine-written entry per REQ-F1.10's expression-only lane, recorded by
`scripts/migrate-format-version.sh` (invariant-tasks D-10, REQ-D1.2).

**Trigger:** the one-shot v1→v2 migration converted this bundle to
format-version 2: placement sections collapsed into `## Tasks`, state
annotation bullets stripped, any parked task blocks converted to reference
bullets, the stored header restricted to the human-gated set, the
`**Execution:**` pointer line added, and `Format-version:` bumped on all
four files. Task definition lines are byte-for-byte unchanged (the
canonical `tasks.md` extraction digest was verified equal before
writing), so no requirement, design decision, task definition, or test
semantics changed — the required re-anchor rides the migration as
expression-only (REQ-A3.3, REQ-D1.2).

**Cites the changelog line:** the 2026-07-15 `## Changelog` entry in
`requirements.md` ("Migrated to format-version 2").

Class: expression-only
Anchor: `90d0fb54cf53d9fac5945349a6f53cf24d38b788` — computed as
`scripts/spec-anchor.sh specs/fleet-autonomy`

### 2026-07-17 — Expression-only self-re-anchor (Task 3 Done-when gap-fill)

Written by `/execute-task` during Task 3 execution, per REQ-F1.10's
expression-only lane (the one anchor entry an execution skill may write).

**Trigger:** the risk register's row 1 sign-off note directed Task 3's
implementation to extend its own `Done when` with the overlapping-invocation
guard (the existing per-spec advisory lock D-20 plus a re-verify of positive
death evidence under the lock), because an accepted risk with no acceptance
criterion can silently ship unmitigated. `tasks.md` Task 3's `Done when` now
carries that criterion; the guard itself ships in
`scripts/fleet-tower-watchdog.sh` with fixtures in
`tests/test-fleet-tower-watchdog.sh`. A gap-fill consistent with the
accepted decisions (the mitigation was decided and signed off in §7 row 1);
no requirement, design decision, or test semantics changed.

**Cites the changelog line:** the 2026-07-17 `## Changelog` entry in
`requirements.md` ("Task 3 execution (expression-only, riding the Task 3
PR)").

Class: expression-only
Anchor: `6867415b094fcc85d2580567623417ef0f5d6c65` — computed as
`scripts/spec-anchor.sh specs/fleet-autonomy`

### 2026-07-17 — Expression-only self-re-anchor (Task 7 Done-when audit clause)

Machine-written entry per REQ-F1.10's expression-only lane, recorded by
`/execute-task` during Task 7's implementation (riding Task 7's PR).

**Trigger:** kickoff risk row 30 (§7) directs Task 7's implementation to
extend its own `Done when` with the throttle-audit acceptance criterion
("an accepted risk with no acceptance criterion can silently ship
unmitigated") and notes the missing D-16/REQ-F1.4 citations. `tasks.md`
Task 7's `Done when` now requires throttle-engagement events to log through
Task 1's audit-trail helper (with a queryable-rows fixture), and its
`Citations:` adds D-16 · REQ-F1.4 — a gap-fill consistent with the accepted
decisions (Tasks 2–4 already carry the same pattern) that contradicts no
decision and alters no REQ's meaning.

**Cites the changelog line:** the 2026-07-17 `## Changelog` entry in
`requirements.md` ("Task 7 implementation (expression-only): extended Task
7's `Done when` …").

Class: expression-only
Anchor: `a9b4689f3b01b24374531bcdaab72821f48c8340` — computed as
`scripts/spec-anchor.sh specs/fleet-autonomy`
