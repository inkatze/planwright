# Fleet lifecycle closure — Requirements

**Status:** Ready
**Last reviewed:** 2026-08-19
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright can start a worker on every rung and cannot reliably end one on
any of them. Both session-grade rungs expose a launch verb and no stop:
`fleet-streamjson.sh` is `launch | answer | recover | alarm-scan | status`,
`fleet-dispatch-headless.sh` is `launch | run-worker | status`, and neither
has a stop, kill, reap, or teardown. `fleet-cleanup.sh` reclaims `window` and
`worktree` and no subcommand reaps a process. The attention store already
*models* `merged`/`done` as "terminal; surfaced as status, then cleared on
teardown" — the vocabulary assumes a teardown verb that was never built.

The consequence is invisible by construction. A worker that reaches
SessionEnd exits cleanly, so the common path looks tidy and an operator who
spot-checks after a normal run concludes the fleet tidies up after itself;
only workers abandoned mid-flight or hard-killed leak, and they leak
silently. That path-dependence is how roughly 95 cumulative hours of leaked
worker time accumulated before anyone noticed (obs:b63a8778).

Detection fails in the same shape. Nothing separates a working worker from
one blocked at a permission prompt: a deferred guard prompt stranded a
dispatched worker for 55 minutes with no signal (obs:4c25e743), and a monitor
sampling the last pane line reported eleven identical heartbeats for a frozen
worker, because the line was stable *precisely because* it was stuck
(obs:50eac4ac). Meanwhile `status` can report `completed result=success` over
work that never landed (obs:cc13d432).

This bundle gives every worker lifecycle phase — every resource class a
worker acquires — three deterministic things: an
**open** that starts the phase and records that it started, a **close** that
ends it and releases its resources, and a **stuck-detector** that positively
separates working / waiting-on-a-human / finished-but-unreaped / dead. All
three are script logic over structured signals; "the tower should notice" is
neither a close nor a detector, it is the failure mode being reported
(fleet-coordination-floor, no-LLM-daemon-mechanics). The deliverable's
altitude — a doctrine floor first, capability and mechanism beneath it — is
recorded in D-1, which the altitude trigger in the drafting brief required.

Because towers assume multiplicity, every verb here is defined under
concurrency: a close must never reach into a peer tower's worker, and
releasing a process must never be confused with reclaiming a unit of work
(D-2).

## Scope

### In scope

- The lifecycle-closure floor as doctrine: open, close, and stuck-detector
  for every worker lifecycle phase — every resource class a worker acquires —
  each deterministic script logic.
- A symmetric `stop` verb on both session-grade rungs, terminating the
  supervisor and its children and releasing the runtime resource set
  (process, tmux window, locks, scratch temp, attention record).
- `process` as a new reclaimable resource class in `fleet-cleanup.sh`.
- A four-state stuck-detector, each state carried by its own script-readable
  signal, crossed with an owner-attribution axis (mine / a live peer's / a
  dead-or-unknown owner's), surfaced on the existing attention surface.
- Multi-tower safety for every destructive verb, built on `fleet-presence.sh`
  and the per-unit `origin` fence as they stand.
- A live writer for the worker registry at every dispatch seam, and an owner
  token on the dispatch record.
- Periodic sweeping on a schedule, replacing threshold-triggered sweeping,
  with a `fleet-audit` record for every autonomous termination, shipping
  observing-only and promoted to terminating by an explicit per-machine knob.
- A repeatable, opt-in deliberate-wedge rehearsal that proves the floor
  end-to-end against a real worker rather than a fixture.
- A supervisor-native `steer` subcommand for `stream-json-persistent`, with
  newline framing asserted at the write.
- Cross-session messaging as an availability-probed steer transport for the
  two non-interactive session-grade rungs, and `--name` pinning at both
  launch sites to make workers addressable.
- Correctness of the lifecycle *open*: per-event hook payload-shape fixtures,
  and a check that a registered decision-control hook satisfies its event's
  contract.
- The two stream-json lock defects that wedge a lifecycle verb
  (obs:81ba2dce, obs:917e384e).

### Out of scope

- **Auto-merge at any tier.** Permanent floor, carried unchanged.
- **Reclaiming a dead tower's unit of work.** Explicitly out of scope in
  `concurrent-orchestrator-coordination`; a fenced-but-unfinished unit is
  surfaced for the operator's reserved reclaim decision. This bundle releases
  processes, never units (D-2).
- **Worktree reclamation from the close verb.** Stays with
  `fleet-cleanup.sh worktree` and its positive-evidence checks (D-3).
- **Tower-to-tower messaging.** The attributed buffer-paste relay already
  serves peer towers sharing a tmux server, which is the substrate towers run
  on; no second channel and no `REQ-D1.1` amendment (D-7).
- **Messaging on the correctness path, the attention/notification seam, or
  inside daemon mechanics**, and no backend-table row for it (D-8).
- **Replacing the buffer-paste relay under tmux.**
- **The worker command guard's screens and the worker-settings profile
  delivery.** Owned by `worker-permission-ergonomics`; routed there as a
  scoped amendment (D-9).
- **The deterministic PR-ready attention record.** Owned by
  `merge-currency-guard`, which `fleet-coordination-floor` names as the owner
  of the deterministic PR-ready push; routed there as a scoped amendment
  (D-9).
- **The shared command-guard library extraction** (obs:30159d5c,
  obs:92809aad) — a dedicated refactor owning both guards.
- **General supervisor concurrency hardening** beyond the two verb-wedging
  defects (obs:8f7bd38f, obs:95ecef76, obs:f5884930, obs:ed0c7477) — cited as
  known residue for a hardening bundle (D-10).
- **Cross-machine or containerised peer awareness.** Single-host scope,
  inherited from the presence surface.

## Vocabulary

Three terms name the ending of a worker and are not interchangeable:

- **Close** — the contract concept: the floor's second part, the obligation
  every lifecycle phase owes. Requirements state obligations in terms of a
  close.
- **Stop** — the named subcommand (REQ-B1.1) closing a worker this tower owns
  or an operator names. It needs no death evidence, because the caller is
  asserting the intent directly.
- **Reap** — the autonomous close of a worker whose owner is dead or unknown,
  performed by the sweep or `fleet-cleanup.sh process`. This is the only one
  gated on positive death evidence for **both** the owning tower and the worker
  session (REQ-D1.4), and the only one to which "reaping is not reclaiming"
  (D-2, REQ-D1.3) and the live-peer refusal (REQ-D1.2) attach.

A reap performs a close; it is not a second mechanism (REQ-B1.5's cleanup class
delegates to the rungs' `stop`). The distinction is about who authorized the
ending and what evidence that authorization required.

## REQ-A — The lifecycle-closure contract

- **REQ-A1.1** Every worker lifecycle phase SHALL have a deterministic open
  that starts the phase and records that it started, a deterministic close
  that ends it and releases its resources, and a script-readable
  stuck-detector. A **lifecycle phase** is one **resource class** a worker
  acquires — its process tree, its tmux window, the locks it holds, its
  scratch temp, its attention record — each acquired and released
  independently, so each owes the three parts in its own right. A phase
  missing any of the three is a defect, not a gap for operator vigilance to
  cover.
  *(Cites: D-1; the drafting brief (Sources); obs:b63a8778.)*
- **REQ-A1.5** The floor SHALL apply to every backend that hosts a **separate
  worker**. A rung with no separate process satisfies the close trivially and
  SHALL say so explicitly rather than being silently exempt; a rung whose
  worker exists only after a human acts SHALL declare which of the three parts
  it defers and to whom. A new backend SHALL declare all three at adoption.
  A backend SHALL declare all three **for every resource class it acquires**.
  *(Cites: D-1; backend-capability-contract (Sources).)*
- **REQ-A1.2** All three SHALL be deterministic script logic over structured
  signals — files, process ids, git state, positively matched known text. No
  lifecycle mechanism SHALL depend on an LLM reading a pane, on a tower
  remembering to look, or on elapsed silence.
  *(Cites: D-1; fleet-coordination-floor (Sources); obs:50eac4ac.)*
- **REQ-A1.3** A close SHALL enumerate every resource class it releases and
  SHALL report a release it could not complete. A partial close SHALL be
  reported as partial, never as success.
  *(Cites: D-3; obs:f133752c.)*
- **REQ-A1.4** The contract SHALL be recorded as doctrine, in
  `doctrine/fleet-coordination-floor.md`, as a floor alongside the four it
  already carries — not as prose inside a script header.
  *(Cites: D-1.)*

- **REQ-A1.6** The floor's instantiation SHALL be proven end-to-end by a
  repeatable **deliberate-wedge rehearsal**: a real worker dispatched against a
  throwaway spec bundle, wedged on purpose, then detected, closed, and
  confirmed to have released every resource class. Fixture coverage alone
  SHALL NOT be treated as discharging the floor, because the leak this bundle
  exists to close is invisible on the path a passing fixture exercises. The
  rehearsal SHALL be opt-in rather than gating ordinary CI, since it consumes
  a live session.
  *(Cites: D-13; the Goal's path-dependence argument; obs:b63a8778.)*

## REQ-B — Deterministic close

- **REQ-B1.1** `fleet-streamjson.sh` and `fleet-dispatch-headless.sh` SHALL
  each expose a `stop <worker>` subcommand, symmetrically, with the same
  release semantics and the same refusal semantics.
  *(Cites: D-3; obs:b63a8778.)*
- **REQ-B1.2** A stop SHALL terminate the worker's supervisor **and its
  children**, SIGTERM first and SIGKILL after a bounded grace period, because
  children do not reliably die with a parent SIGTERM.
  *(Cites: obs:b63a8778.)*
- **REQ-B1.3** Process matching SHALL key on the worker's **state-directory
  path**, never on a bare process name or command pattern, so a stop can
  never over-match an operator's own `claude` session.
  *(Cites: D-3; obs:b63a8778; security-posture (Sources).)*
- **REQ-B1.4** A stop SHALL release exactly: the worker process tree, the
  tmux window where one exists, locks the worker holds, its scratch temp, and
  its attention record. It SHALL NOT remove, move, or modify the worktree,
  the branch, or the unit's fence.
  *(Cites: D-2; D-3; obs:33c821b8.)*
- **REQ-B1.5** `fleet-cleanup.sh` SHALL gain `process` as a reclaimable
  resource class, subject to the same self-targeting guard, audit trail, and
  kill-switch gating as its existing classes.
  *(Cites: D-3; obs:b63a8778; obs:ef2cfd5a.)*
- **REQ-B1.6** The tower SHALL invoke the close verb when a unit completes,
  and the periodic sweep SHALL be **capable** of closing what the tower did
  not, so the leak's path-dependence is covered from both ends. This states the
  required capability; whether the sweep exercises it autonomously is gated by
  REQ-F1.6's promotion knob, and a sweep in observing-only mode satisfies this
  requirement by identifying and recording what it would have closed.
  *(Cites: D-5; D-14; obs:b63a8778.)*
- **REQ-B1.7** A close SHALL be idempotent: a second stop against a worker
  with nothing still held SHALL succeed with a distinct already-closed result,
  never an error and never a second kill. Idempotence is defined over the
  **release set, not the invocation**: where a prior close was partial
  (REQ-A1.3), a second stop SHALL retry exactly the classes still held and
  SHALL NOT report already-closed while any remain. A retry SHALL send no
  signal to a process tree already gone.
  *(Cites: D-3; REQ-A1.3.)*

## REQ-C — The stuck-detector

- **REQ-C1.1** The detector SHALL positively enumerate four states —
  `working`, `waiting-on-a-human`, `finished-but-unreaped`, `dead` — each
  carried by its own script-readable signal. Absence of change SHALL NOT be
  evidence for any state.
  *(Cites: D-4; obs:50eac4ac.)*
- **REQ-C1.2** `waiting-on-a-human` SHALL be established by a positive
  signal — a hook push, or a positively matched prompt signature — and SHALL
  NOT be inferred from elapsed time or from a quiet pane.
  *(Cites: D-4; obs:4c25e743; obs:50eac4ac.)*
- **REQ-C1.3** `finished-but-unreaped` SHALL be a first-class state: a worker
  whose session has ended while its process or resources persist. Nothing in
  the fleet models alive-but-finished today.
  *(Cites: D-4; obs:b63a8778.)*
- **REQ-C1.4** A worker reporting a successful completion SHALL NOT be
  classified finished while its work is demonstrably unlanded. The evidence
  SHALL be **locally observable git state** — an uncommitted tree, or commits
  absent from the remote-tracking ref — so the check is cheap and needs no
  network. Where PR state is already resolved by the existing reconcile, its
  absence MAY corroborate; the detector SHALL NOT itself query the forge per
  worker, and SHALL NOT infer a unit's PR obligation.
  *(Cites: D-4; obs:cc13d432.)*
- **REQ-C1.5** `dead` SHALL be established only by the positive-evidence
  predicate (`fleet-death-evidence.sh`); an unknown or errored verdict SHALL
  classify as not-dead.
  *(Cites: backend-capability-contract (Sources).)*
- **REQ-C1.6** Every state SHALL carry an owner attribution — this tower's, a
  live peer's, or a dead-or-unknown owner's — resolved from the presence
  surface, because the same signal means different things depending on who
  owns the worker.
  *(Cites: D-2; D-12; obs:10407a5e.)*
- **REQ-C1.7** The detector SHALL surface work-progress alongside liveness:
  which **stage** of its unit a worker is in (named `stage` to keep `phase`
  reserved for REQ-A1.1's resource-class sense), derived cheaply from the event
  stream (recent tool-use, task subtypes, commit count on the unit branch).
  *(Cites: obs:22b2475d.)*
- **REQ-C1.8** Detector output SHALL be consumable by a script — a stable,
  parseable surface — so no consumer needs an LLM to interpret it.
  *(Cites: REQ-A1.2.)*

## REQ-D — Multi-tower safety

- **REQ-D1.1** Every destructive verb SHALL consult `fleet-presence.sh` and
  the per-unit `origin` fence before acting. This bundle SHALL extend those
  surfaces and SHALL NOT introduce a second presence, registry, or exclusion
  mechanism.
  *(Cites: fleet-coordination-floor (Sources); concurrent-orchestrator-coordination (Sources).)*
- **REQ-D1.2** A process whose unit is fenced by a **live peer tower** SHALL
  never be terminated by this tower, under any evidence.
  *(Cites: D-2.)*
- **REQ-D1.3** A reap SHALL release the process only. The unit's fence,
  branch, and worktree SHALL be left untouched, and a strand SHALL still be
  surfaced for the operator's reserved reclaim decision. **Reaping is not
  reclaiming.**
  *(Cites: D-2; concurrent-orchestrator-coordination (Sources).)*
- **REQ-D1.4** A dead-or-unknown-owner process SHALL be auto-reaped only on
  positive death evidence for **both** the owning tower and the worker
  session. Unknown or errored evidence SHALL be treated as alive.
  *(Cites: D-2; D-5; obs:b63a8778.)*
- **REQ-D1.5** Dispatch records SHALL carry an **owner token** identifying
  the dispatching tower, so two towers cannot be confused for one another and
  a record's owner is attributable without inference.
  *(Cites: D-12; obs:10407a5e; obs:69eeac0c.)*
- **REQ-D1.6** Concurrent sweeps by any number of towers SHALL be safe: no
  double-reap, no lost sweep, and no reliance on a lock whose stale-break can
  admit two holders.
  *(Cites: D-10; obs:5f0e1976; obs:81ba2dce.)*
- **REQ-D1.7** Presence SHALL remain awareness-only and off the correctness
  path; the fence SHALL remain the sole exclusion object.
  *(Cites: concurrent-orchestrator-coordination (Sources).)*
- **REQ-D1.8** `print`-backend units SHALL be exempt from reaping, as they
  already are from the orphan and liveness predicates: the tower spawns no
  process, so there is nothing it may attribute or terminate. They SHALL still
  be registered (REQ-E1.1), since a dispatch record is the only evidence such
  a unit exists.
  *(Cites: D-2; orchestration-concurrency (Sources); obs:b9c7e6c5.)*
- **REQ-D1.9** Clearing a worker's attention record on close SHALL NOT clear
  or suppress a strand surfaced for the operator. The liveness record and the
  durable strand sink are distinct surfaces, and a reap SHALL leave the sink
  entry standing.
  *(Cites: D-2; concurrent-orchestrator-coordination (Sources).)*

## REQ-E — Enumeration and inventory

- **REQ-E1.1** Every dispatch seam SHALL write a registry record at dispatch,
  so the registry has a live writer and the fleet has an inventory of what
  exists. A close verb that can only reap what its caller names cannot reach
  the abandoned worker, which is the class that leaks.
  *(Cites: D-12; obs:b9c7e6c5; obs:b63a8778.)*
- **REQ-E1.2** The registry record SHALL carry enough to close the worker
  without its dispatcher: the handle, the owner token, the state directory,
  the backend, and the death handle.
  *(Cites: D-12; obs:b9c7e6c5.)*
- **REQ-E1.3** The worktree disk-scan reconcile SHALL run periodically as
  part of the sweep, so the self-healing floor holds without a manual
  invocation.
  *(Cites: D-5; obs:15ac3bc6.)*
- **REQ-E1.4** Registration SHALL degrade gracefully: a failed registry write
  SHALL NOT fail a dispatch, and SHALL self-heal on the next scan.
  *(Cites: obs:a6f5511b.)*

## REQ-F — Periodic sweep

- **REQ-F1.1** The sweep SHALL run on a schedule, not on a threshold.
  Waiting until a count is alarming is what produced the leaked hours.
  *(Cites: D-5; obs:b63a8778.)*
- **REQ-F1.2** Every autonomous termination SHALL write a `fleet-audit`
  record naming the worker, its owner, the evidence class that justified the
  kill, and what was released.
  *(Cites: D-5; fleet-coordination-floor (Sources).)*
- **REQ-F1.3** The sweep SHALL remain gated by the existing operator
  kill-switch and SHALL introduce no second pause mechanism.
  *(Cites: fleet-coordination-floor (Sources).)*
- **REQ-F1.4** The sweep SHALL report what it declined to act on and why, so
  a refusal is visible rather than indistinguishable from finding nothing.
  *(Cites: REQ-A1.3; obs:1fc61ad9; obs:49b457dc.)*
- **REQ-F1.5** Sweep temp artifacts SHALL be trap-owned across INT/TERM/HUP,
  since a watch loop stopped by signal is the normal way it ends.
  *(Cites: obs:16170b3f; obs:f669d96c; obs:162f7106.)*

- **REQ-F1.6** The sweep SHALL ship **observing-only**: it identifies
  candidates and writes the full `fleet-audit` record it would have written,
  and terminates nothing. Autonomous termination SHALL be enabled only by an
  explicit, per-machine knob, resolved through the four overlay layers, and
  the knob SHALL be reversible without a release. The dry-run record SHALL be
  distinguishable from a record of an actual termination, so the audit trail
  can never be read as evidence of a kill that did not happen.
  *(Cites: D-14; decision-domains `deploy-migration` (Sources).)*
- **REQ-F1.7** Both sweep modes SHALL be exercised by the REQ-A1.6 rehearsal,
  so the observing-only path cannot rot unexercised while the fleet waits for
  promotion.
  *(Cites: D-14; REQ-A1.6.)*

## REQ-G — Steer

- **REQ-G1.1** `fleet-streamjson.sh` SHALL expose a `steer` subcommand
  writing an attributed frame into the worker's input fifo, discharging the
  steer capability the contract already advertises for that rung.
  *(Cites: D-6; obs:cc13d432; backend-capability-contract (Sources).)*
- **REQ-G1.2** Every frame written to a worker's input fifo SHALL be
  newline-terminated, and the writer SHALL assert termination and JSON
  validity before the write. An unterminated frame concatenates with the
  supervisor's next line and **kills the worker**.
  *(Cites: D-6; obs:33c821b8.)*
- **REQ-G1.3** The supervisor-native steer SHALL be the **primary** steer
  path for that rung: it is script-auditable and delivery-guaranteed while
  the channel lives.
  *(Cites: D-6.)*
- **REQ-G1.4** Cross-session messaging SHALL be adopted as an
  availability-probed steer transport for the two non-interactive
  session-grade rungs — the only steer available to `headless-oneshot`, and
  the wake path for a yielded `stream-json-persistent` worker.
  *(Cites: D-6; D-8; the messaging research report (Sources); obs:cc13d432.)*
- **REQ-G1.5** Messaging availability SHALL be probed deterministically and
  its absence SHALL degrade visibly to the printed capability table, never
  silently.
  *(Cites: D-8; the messaging research report (Sources).)*
- **REQ-G1.6** Messaging SHALL be classified a latency and capability
  optimization, never a source of correctness, mirroring the hook-push
  language `fleet-autonomy` already uses.
  *(Cites: D-8.)*
- **REQ-G1.7** Both worker launch sites SHALL pin `--name` from the
  already-validated unit handle, so a worker is addressable; the launch-arg
  allowlists SHALL be extended to admit exactly that pinned form.
  *(Cites: D-8; the messaging research report (Sources).)*
- **REQ-G1.8** The bundle SHALL record as a **bound**, not a caveat, that
  messaging cannot answer a permission prompt and cannot reach a session that
  is blocked rather than working. It can therefore never close the
  permissions gap nor discharge the deterministic-attention floor.
  *(Cites: D-8; obs:4c25e743; attention-notification-capability (Sources).)*
- **REQ-G1.9** Inbound message text SHALL be treated as untrusted data at
  both ends, the worker-output-is-data rule extended verbatim.
  *(Cites: security-posture (Sources); inter-orchestrator-coordination (Sources).)*
- **REQ-G1.10** Workers SHALL be configured not to message off-machine
  without explicit approval.
  *(Cites: security-posture (Sources); the messaging research report (Sources).)*

## REQ-H — Lifecycle-open correctness

- **REQ-H1.1** Every hook planwright registers SHALL be covered by a
  payload-shape fixture pinned to the event's **actual** input schema, so a
  schema divergence fails a test rather than the fleet.
  *(Cites: D-11; obs:f51f6b6e.)*
- **REQ-H1.2** A registered **decision-control** hook — one whose failure or
  silence blocks the operation it guards — SHALL be verified to satisfy its
  event's output contract, and SHALL NOT be registered at all where planwright
  only wants passive observation.
  *(Cites: D-11; obs:f51f6b6e; obs:a6f5511b.)*
- **REQ-H1.3** A hook that refuses SHALL surface its reason on a channel the
  operator sees. A refusal explained only on discarded stderr is
  indistinguishable from an unexplained platform failure.
  *(Cites: D-11; obs:f51f6b6e; REQ-A1.3.)*
- **REQ-H1.4** The recorded `WorktreeCreate` contract SHALL be corrected: the
  event supplies a worktree **name** and the hook is the creator, expected to
  produce the worktree and report its path. The prior reading is superseded.
  *(Cites: D-11; obs:f51f6b6e; obs:a6f5511b.)*

## REQ-J — Carried floors

- **REQ-J1.1** Never auto-merge, at any tier. Carried unchanged.
  *(Cites: autonomous-safe-decision (Sources).)*
- **REQ-J1.2** No commit this bundle produces SHALL rewrite history: no
  force-push, amend, squash, or rebase.
  *(Cites: the bootstrap invariant family (Sources).)*
- **REQ-J1.3** The tower non-authoring boundary carries unchanged: closing
  and reaping are monitor-and-reconcile verbs, not authoring.
  *(Cites: fleet-coordination-floor (Sources).)*
- **REQ-J1.4** No mechanism this bundle ships SHALL invoke an LLM in a
  liveness, cleanup, throttle, or kill decision.
  *(Cites: REQ-A1.2; fleet-coordination-floor (Sources).)*

## REQ-K — Cross-cutting quality

- **REQ-K1.1** Every refusal, degradation, and partial result SHALL surface a
  clear, actionable, echo-safe message naming what could not be established.
  *(Cites: REQ-A1.3.)*
- **REQ-K1.2** No committed artifact of this bundle SHALL carry secrets,
  credentials, internal hostnames, or sensitive operational detail.
  *(Cites: security-posture (Sources).)*
- **REQ-K1.3** Untrusted content echoed into a terminal SHALL be stripped of
  control bytes through the canonical sanitizer.
  *(Cites: security-posture (Sources).)*
- **REQ-K1.4** Every handle, path, and identifier parsed from input SHALL be
  grammar-validated and containment-checked before use.
  *(Cites: security-posture (Sources).)*
- **REQ-K1.5** Negative assertions SHALL confirm no model or API call appears
  in any decision path this bundle ships.
  *(Cites: REQ-J1.4.)*
- **REQ-K1.6** Every knob introduced SHALL resolve through the four overlay
  layers and SHALL be documented in the canonical options reference.
  *(Cites: customization-boundary (Sources).)*
- **REQ-K1.7** Every mechanism SHALL degrade gracefully where a dependency is
  absent — no tmux, no remote, no `gh`, no messaging — surfacing the
  degradation rather than failing the run.
  *(Cites: REQ-G1.5.)*

## Changelog

- **2026-08-18** — Bundle drafted at Status Draft. Scope resolved as one new
  bundle plus two scoped amendments routed to their doctrinal owners (D-9).
  Messaging scoped to worker steer only, tower-to-tower rejected (D-7).
  Multi-tower safety added as a first-class group at the operator's direction
  during elicitation; reaping-is-not-reclaiming resolved from doctrine rather
  than asked (D-2). Close scoped to runtime resources, never the worktree
  (D-3). Lock defects scoped to those wedging a lifecycle verb (D-10).
  Self-critique pass over the assembled bundle added REQ-A1.5 (the floor's
  per-backend applicability, which was overclaimed as universal while the
  mechanism covered two rungs), REQ-D1.8 (`print` units register but are never
  reaped), and REQ-D1.9 (clearing a liveness record must not erase a surfaced
  strand — an unresolved conflict between REQ-B1.4 and REQ-D1.3 as first
  drafted); narrowed REQ-C1.4 to locally observable git state after it was
  found to require a per-worker forge query and an inference about a unit's PR
  obligation; and moved obs:efe0b752 from consumed to residue, having been
  listed as consumed without being resolved by any requirement.

- **2026-08-18** — Kickoff walkthrough (`kickoff-brief.md`). Defined the
  floor's quantifier as one resource class a worker acquires, which had been
  load-bearing and undefined (REQ-A1.1, D-1, Task 1, and their test-spec
  entries); renamed REQ-C1.7's colliding second sense of "phase" to "stage".
  Dropped "or PR-less" from Task 7, which contradicted REQ-C1.4's deliberate
  narrowing to locally observable git state. Added REQ-A1.6 and D-13, the
  deliberate-wedge rehearsal, after the operator observed the bundle verified
  almost entirely through fixtures that cannot falsify its own
  path-dependence claim. Added REQ-F1.6, REQ-F1.7, and D-14 — the sweep ships
  observing-only, promoted by an explicit knob — closing the
  `deploy-migration` gap the decision-domains check found. Added a Task 6
  dependency on both `stop` tasks so the fleet has one kill path rather than
  two. Recorded the dispatch reservation-slot leak as a gated Deferred entry
  after inspection showed it is a reservation primitive, not a capacity
  ledger, with the authoritative in-flight count already deriving from git.
  Recorded the unshipped `WorktreeCreate` chore fix as a dispatch gate.

- 2026-09-03 — Expression-only: D-10's rejected alternative cites the fold-vs-new test as `bootstrap D-21` instead of a bare `D-21`. Surfaced by the format-grammar validator's citation-range rule (format-grammar REQ-D1.3) on its all-bundle rollout (format-grammar D-9); no requirement or decision changes meaning.

## Sources

- **The drafting brief (2026-08-18).** The operator's framing of the
  complaint, the three-part open/close/detector thesis, the structural
  findings to verify, and the reserved decision list.
- **Structural verification (2026-08-18).** Direct inspection of the shipped
  subcommand surfaces: `fleet-streamjson.sh`, `fleet-dispatch-headless.sh`,
  `fleet-cleanup.sh`, `fleet-attention.sh`, `fleet-presence.sh`,
  `orchestrate-relay.sh`. Confirmed the absent stop verb on both rungs and
  the absent process resource class.
- **The cross-session messaging research report (2026-08-13).** An
  independent pass against CLI 2.1.231 with live experiments, concluding
  messaging is not a backend, gets no contract row, and is best adopted
  narrowly as a probed steer transport. Its tower-to-tower recommendation was
  rejected here (D-7).
- **`doctrine/fleet-coordination-floor.md`** — the four floors, especially
  no-LLM-daemon-mechanics, assume-multiplicity, and deterministic-attention;
  the scope-boundary section naming each adjacent mechanism's owner.
- **`doctrine/backend-capability-contract.md`** — the capability vocabulary,
  the advertised sets, and the positive-evidence-of-death predicate.
- **`doctrine/inter-orchestrator-coordination.md`** — the attributed,
  non-impersonating relay; the tmux buffer-paste mechanism serving
  tower-to-tower coordination, which is why D-7 rejects a messaging arm.
- **`specs/concurrent-orchestrator-coordination`** — the origin fence as sole
  exclusion object, presence as attribution-only, and the explicit
  out-of-scope status of auto-reclaiming a dead tower's unit.
- **`doctrine/decision-domains.md`** — the catalogued decision domains; the
  kickoff gap check against it surfaced the sweep's undecided rollout (D-14).
- **`doctrine/autonomous-safe-decision.md`**, **`doctrine/security-posture.md`**,
  **`doctrine/attention-notification-capability.md`**,
  **`doctrine/orchestration-concurrency.md`**,
  **`doctrine/customization-boundary.md`** — carried floors and boundaries.
- **The bootstrap invariant family** — never merge, never force-push, never
  amend, squash, or rebase.
- **Observations consumed.** obs:b63a8778, obs:cc13d432, obs:f133752c,
  obs:6e4d884f, obs:463cdde4, obs:ce589542, obs:917e384e, obs:81ba2dce,
  obs:33c821b8, obs:22b2475d, obs:b9c7e6c5, obs:15ac3bc6, obs:10407a5e,
  obs:384e3ba2, obs:dc8998dd, obs:16170b3f, obs:a6f5511b, obs:f037fb47,
  obs:4ad7c094, obs:1fc61ad9, obs:49b457dc, obs:ef2cfd5a,
  obs:f669d96c, obs:162f7106, obs:69eeac0c, obs:5f0e1976, obs:f51f6b6e,
  obs:4c25e743, obs:50eac4ac.
- **Observations cited as residue, not consumed.** obs:efe0b752 (a decision
  fork closed before its answer is delivered leaves a worker waiting on an
  answer that never arrives — this bundle's detector surfaces such a worker as
  `waiting-on-a-human`, but the delivery-confirmation fix belongs to the
  decision channel, not here); obs:8f7bd38f,
  obs:95ecef76, obs:f5884930, obs:ed0c7477 (supervisor hardening);
  obs:30159d5c, obs:92809aad (shared guard library); obs:814c6ba9,
  obs:33812f90, obs:5775c447, obs:026930ca, obs:eea622de, obs:a4a4fa59
  (routed to the `worker-permission-ergonomics` amendment); obs:bfc6faf0
  (routed to the `merge-currency-guard` amendment).
