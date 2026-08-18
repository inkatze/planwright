# Fleet lifecycle closure — Tasks

**Status:** Draft
**Last reviewed:** 2026-08-18
**Format-version:** 2
**Execution:** derived — see the status render

Task blocks are listed in dependency order as authoring guidance; the
`Dependencies:` field is the sole source of the task graph. Render it with
`scripts/spec-graph.sh`.

## Tasks

### Task 1 — The lifecycle-closure floor and the altitude record

- **Deliverables:** a fifth floor in `doctrine/fleet-coordination-floor.md`
  stating the open/close/stuck-detector contract, its incident grounding, and
  what it means in practice, in the same shape as the four floors it joins;
  the explicit statement that reaping releases processes and never units,
  cross-referenced to `concurrent-orchestrator-coordination`'s
  never-auto-reclaim rule so the two cannot be collapsed; a per-backend table
  naming each rung's open, close, and detector, including the trivial cases
  (`subagent`, `in-session`) and the deferred one (`print`), so no rung is
  silently exempt and a new backend must declare all three; the D-1 altitude
  record and D-2 verified present and consistent in `design.md`; the citation
  wiring from this bundle's REQ-A group. No executable behaviour in this
  task.
- **Done when:** the floor is present in `doctrine/fleet-coordination-floor.md`
  and cited by REQ-A1.1–A1.5; the reaping-is-not-reclaiming boundary is stated
  in the doctrine with its cross-reference; the per-backend table covers every
  rung in the capability contract with no omissions; `scripts/spec-validate.sh`
  and `mise run check` pass over the bundle;
  `scripts/check-doctrine-manifest.sh`
  and the doc-link check pass; no script under `scripts/` is modified.
- **Dependencies:** none
- **Citations:** REQ-A1.1 · REQ-A1.2 · REQ-A1.3 · REQ-A1.4 · REQ-A1.5 ·
  REQ-D1.3 · D-1 · D-2 · obs:b63a8778
- **Estimated effort:** 1 day

### Task 2 — Hook payload-shape fixtures and the decision-control contract check

- **Deliverables:** a fixture per registered hook event pinning that event's
  actual stdin schema, including the `WorktreeCreate`/`WorktreeRemove`
  asymmetry (`name` versus `worktree_path`) that caused the outage; a check,
  wired into `mise run check`, that every hook planwright registers as
  decision-control satisfies its event's output contract and that no hook is
  registered as decision-control where only passive observation is wanted;
  correction of the recorded `WorktreeCreate` contract in the doctrine and
  docs; supersession of obs:a6f5511b's contract reading, recorded in the
  observation trail; a refusal path that surfaces its reason where the
  operator sees it rather than on discarded stderr.
- **Done when:** each registered hook event has a payload fixture that fails
  if its schema key set diverges; the decision-control check flags a hook that
  exits 0 without satisfying its output contract, proven by a deliberately
  broken fixture; the corrected `WorktreeCreate` contract appears in the
  doctrine with obs:a6f5511b marked superseded; a hook refusal is visible to
  the operator in a manual exercise; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** REQ-H1.1 · REQ-H1.2 · REQ-H1.3 · REQ-H1.4 · REQ-K1.1 · D-11 ·
  obs:f51f6b6e · obs:a6f5511b
- **Estimated effort:** 2 days

### Task 3 — Registry live writer and the dispatch owner token

- **Deliverables:** dispatch-time registration wired at every dispatch seam
  (`fleet-dispatch-worktree.sh`, `fleet-dispatch-headless.sh`,
  `fleet-streamjson.sh`, `offload-dispatch.sh`, and the print rung's
  deferred-launch record), writing through the existing
  `fleet-state.sh register` primitive with no second store; an owner token
  field identifying the dispatching tower, resolved from the presence
  surface's tower identity; the record fields a close verb needs without its
  dispatcher (handle, owner token, state directory, backend, death handle);
  graceful degradation so a failed registry write warns and never fails a
  dispatch, self-healing on the next scan.
- **Done when:** a dispatch on each seam produces a registry record carrying
  all five fields plus the owner token; `fleet-status.sh` renders the registry
  as present rather than absent; a simulated registry-write failure leaves the
  dispatch successful and emits a visible warning; two dispatches from
  distinct tower identities produce records distinguishable by owner token;
  `mise run check` passes.
- **Dependencies:** 1, 2
- **Citations:** REQ-E1.1 · REQ-E1.2 · REQ-E1.4 · REQ-D1.5 · REQ-K1.4 · D-12 ·
  obs:b9c7e6c5 · obs:10407a5e · obs:69eeac0c
- **Estimated effort:** 2 days

### Task 4 — `stop` on `fleet-streamjson.sh`, and the two verb-wedging lock defects

- **Deliverables:** a `stop <worker>` subcommand terminating the supervisor
  and its children, SIGTERM then SIGKILL after a bounded grace, matching on
  the worker's state-directory path and never a bare process name; release of
  the runtime set (process tree, locks, scratch temp, attention record) with a
  partial release reported as partial; idempotent re-invocation returning a
  distinct already-closed result; a stale-break for `recover.lock` on the same
  pattern its sibling `journal_lock` already uses, so a SIGKILL mid-recovery
  cannot wedge the verb permanently; a single-initiator lock on `launch` using
  the atomic `mkdir` pattern `recover` already elects with, refusing the second
  concurrent caller.
- **Done when:** `stop` terminates a live worker and its children and leaves
  no process referencing the state directory; a stop against an operator
  session whose command merely resembles a worker's is refused by the
  state-dir match, asserted by fixture; a second `stop` returns already-closed
  with exit 0; a `recover.lock` left behind by a killed recovery is broken on
  the documented stale age and recovery succeeds; two concurrent `launch`
  calls for one worker leave exactly one supervisor and one pid file;
  `mise run check` passes.
- **Dependencies:** 1, 3
- **Citations:** REQ-B1.1 · REQ-B1.2 · REQ-B1.3 · REQ-B1.4 · REQ-B1.7 ·
  REQ-A1.3 · REQ-D1.6 · D-3 · D-10 · obs:b63a8778 · obs:81ba2dce · obs:917e384e
- **Estimated effort:** 3 days

### Task 5 — `stop` on `fleet-dispatch-headless.sh`

- **Deliverables:** a `stop <worker>` subcommand on the headless rung with
  the same release semantics, the same state-dir process matching, the same
  partial-release reporting, and the same idempotence as Task 4, so the two
  session-grade rungs are symmetric rather than similar; shared release logic
  factored where the two rungs genuinely coincide, without extracting the
  security-critical guard engines this bundle keeps out of scope.
- **Done when:** `stop` on the headless rung passes the same behavioural
  fixture table as Task 4's, parameterised by rung; a documented comparison
  shows the two surfaces expose the same verb set for the lifecycle
  operations; `mise run check` passes.
- **Dependencies:** 1, 3, 4
- **Citations:** REQ-B1.1 · REQ-B1.2 · REQ-B1.3 · REQ-B1.4 · REQ-B1.7 · D-3 ·
  obs:b63a8778
- **Estimated effort:** 1.5 days

### Task 6 — `process` as a reclaimable class in `fleet-cleanup.sh`

- **Deliverables:** a `process` subcommand reclaiming a leaked worker process
  under the same self-targeting guard, audit trail, and `fleet_daemon_pause`
  kill-switch gating the existing `window` and `worktree` classes carry;
  positive-evidence gating so an unknown or errored liveness verdict refuses;
  refusal to act on a process whose unit is fenced by a live peer tower;
  refusal to act on a `print`-backend unit, which has no process to terminate;
  preservation of any surfaced strand entry when the worker's attention record
  is cleared; an explicit statement in the subcommand's contract that it
  releases the process only and touches no fence, branch, or worktree.
- **Done when:** `process` reclaims a leaked worker process and writes its
  audit record; it refuses on an unknown liveness verdict, on a live-peer
  fence, on a `print`-backend unit, and on a self-target, each with a distinct
  exit and message; the kill-switch pauses it; a fixture asserts no fence,
  branch, or worktree is modified on any path, and that a surfaced strand
  entry survives the reap; `mise run check` passes.
- **Dependencies:** 1, 3
- **Citations:** REQ-B1.5 · REQ-D1.2 · REQ-D1.3 · REQ-D1.4 · REQ-D1.8 ·
  REQ-D1.9 · REQ-F1.2 · REQ-K1.1 · D-2 · D-3 · obs:b63a8778 · obs:ef2cfd5a
- **Estimated effort:** 2 days

### Task 7 — The four-state stuck-detector and the attribution axis

- **Deliverables:** a detector establishing each of `working`,
  `waiting-on-a-human`, `finished-but-unreaped`, and `dead` from its own
  positive signal, with `dead` gated on the positive-evidence predicate and
  `waiting-on-a-human` established by a hook push or a positively matched
  prompt signature rather than elapsed time; the unlanded-work check that
  prevents a self-reported completion from classifying as finished while its
  work is uncommitted, unpushed, or PR-less; the owner-attribution axis
  resolved from the presence surface; a work-progress signal derived from the
  event stream; a stable, script-parseable output surface; wiring into the
  existing attention store with no second store.
- **Done when:** each of the four states is produced from its own signal in a
  fixture, and no state is produced by absence of change; a worker frozen at a
  permission prompt classifies `waiting-on-a-human` rather than `working`,
  asserted against a captured prompt fixture; a worker reporting success with
  an uncommitted tree does not classify finished; each state renders with its
  owner attribution; the output parses with no LLM in the path, asserted
  negatively; `mise run check` passes.
- **Dependencies:** 1, 3
- **Citations:** REQ-C1.1 · REQ-C1.2 · REQ-C1.3 · REQ-C1.4 · REQ-C1.5 ·
  REQ-C1.6 · REQ-C1.7 · REQ-C1.8 · REQ-K1.5 · D-4 · obs:50eac4ac ·
  obs:4c25e743 · obs:cc13d432 · obs:22b2475d · obs:b63a8778
- **Estimated effort:** 3 days

### Task 8 — The periodic sweep, its audit trail, and the worktree scan

- **Deliverables:** the sweep moved onto a schedule as its trigger of record,
  replacing threshold-triggered sweeping, closing what the tower did not; a
  `fleet-audit` record per autonomous termination naming worker, owner,
  evidence class, and what was released; a declined-actions report so a
  refusal is visible rather than indistinguishable from an empty sweep; the
  periodic worktree disk-scan reconcile wired in so the self-healing floor
  holds without a manual invocation; trap-owned temp cleanup across
  INT/TERM/HUP at every `mktemp`-beside-target site the sweep touches; the
  scheduling knob resolved through the four overlay layers and documented in
  the options reference.
- **Done when:** the sweep fires on schedule with no threshold precondition
  and reaps a leaked process left by a dead owner; each termination has a
  matching audit record naming its evidence class; a sweep that declines every
  candidate reports why rather than printing nothing; the worktree scan runs
  as part of the cycle and reconciles a registry gap; a SIGTERM mid-sweep
  leaves no temp artifact behind, asserted by fixture; the knob has a row in
  `docs/options-reference.md` and `scripts/check-options-reference.sh` passes;
  `mise run check` passes.
- **Dependencies:** 4, 5, 6, 7
- **Citations:** REQ-F1.1 · REQ-F1.2 · REQ-F1.3 · REQ-F1.4 · REQ-F1.5 ·
  REQ-B1.6 · REQ-E1.3 · REQ-K1.6 · D-5 · obs:b63a8778 · obs:15ac3bc6 ·
  obs:16170b3f · obs:f669d96c · obs:162f7106 · obs:1fc61ad9 · obs:49b457dc
- **Estimated effort:** 2.5 days

### Task 9 — The supervisor-native `steer` subcommand and fifo write discipline

- **Deliverables:** a `steer <worker>` subcommand on `fleet-streamjson.sh`
  writing an attributed frame into the worker's input fifo, carrying the same
  tower-originated attribution header the buffer-paste relay uses and reading
  the message body from a file so message text is never spliced into a
  command; a write discipline asserting newline termination and JSON validity
  before every fifo write, applied to every existing fifo writer and not only
  the new one; a refusal, never a partial write, when either assertion fails.
- **Done when:** `steer` delivers an attributed message to a live busy worker
  which consumes it without restarting; an unterminated or invalid frame is
  refused before any bytes reach the fifo, asserted by fixture; a message
  containing shell metacharacters is delivered verbatim and never evaluated; a
  source audit confirms no `send-keys`-equivalent impersonation path;
  `mise run check` passes.
- **Dependencies:** 1
- **Citations:** REQ-G1.1 · REQ-G1.2 · REQ-G1.3 · REQ-G1.9 · REQ-K1.3 ·
  REQ-K1.4 · D-6 · obs:cc13d432 · obs:33c821b8
- **Estimated effort:** 2 days

### Task 10 — Messaging as a probed steer transport, and `--name` pinning

- **Deliverables:** a steer-transports section in
  `doctrine/backend-capability-contract.md` describing messaging as a
  host-probed transport that upgrades the effective steer of the two
  non-interactive session-grade rungs when present, with no table row and no
  advertised-boolean change, classified as a latency and capability
  optimization and never correctness; a deterministic availability probe whose
  negative result degrades visibly to the printed table; `--name` pinned at
  both worker launch sites from the already-validated unit handle, with the
  launch-arg allowlists extended to admit exactly that form and no other; the
  recorded bound that messaging can neither answer a permission prompt nor
  reach a blocked session; the worker profile configured not to message
  off-machine without approval; inbound message text classified as untrusted
  data at both ends.
- **Done when:** the contract section is present and the probe reports
  presence and absence correctly on a host with the feature disabled; a
  dispatched worker is addressable by its pinned name and receives an
  attributed message while busy; a launch-arg fixture accepts the pinned
  `--name` form and refuses a free-form one; the bound is recorded in the
  contract prose; the off-machine setting is present in the worker profile;
  `mise run check` passes.
- **Dependencies:** 3, 9
- **Citations:** REQ-G1.4 · REQ-G1.5 · REQ-G1.6 · REQ-G1.7 · REQ-G1.8 ·
  REQ-G1.9 · REQ-G1.10 · REQ-K1.7 · D-6 · D-7 · D-8 ·
  the messaging research report (Sources) · obs:384e3ba2 · obs:f037fb47 ·
  obs:4ad7c094
- **Estimated effort:** 2.5 days

### Task 11 — The multi-tower adversarial suite

- **Deliverables:** a fixture-driven suite exercising every destructive verb
  under concurrency: a live peer's worker is never terminated; a
  dead-or-unknown owner's process is reaped only on positive death evidence
  for both tower and session, and never on an unknown or errored verdict; N
  concurrent sweeps produce no double-reap and no lost sweep; no reap path
  modifies a fence, branch, or worktree on any branch of the matrix; presence
  stays off the correctness path; negative assertions confirming no model or
  API call in any decision path this bundle ships.
- **Done when:** the suite is green in project CI; every matrix cell is
  asserted across both rungs and the cleanup class, and its completeness is
  mechanically enforced by an expected-cell manifest; the fence-and-worktree
  untouched assertion holds on every path including refusals; the no-LLM
  negative assertions pass; `mise run check` passes.
- **Dependencies:** 4, 5, 6, 8
- **Citations:** REQ-D1.1 · REQ-D1.2 · REQ-D1.3 · REQ-D1.4 · REQ-D1.6 ·
  REQ-D1.7 · REQ-D1.8 · REQ-D1.9 · REQ-J1.4 · REQ-K1.5 · D-2 · obs:5f0e1976 ·
  obs:ce589542 · obs:ef2cfd5a
- **Estimated effort:** 2.5 days

## Awaiting input

(none yet)

## Deferred

- **General stream-json supervisor concurrency hardening.** The recorded
  defects that do not wedge a lifecycle verb: the `journal_lock` rmdir spin,
  the lock ownership tokens, start-time-checked pid liveness, the
  non-blocking fifo open in `answer`, the torn `result` read, and the
  `alarm-scan` field-guard asymmetry. Confidence: high.
  **Gate:** a dedicated supervisor-hardening bundle is drafted, or any one of
  these defects is observed firing in a live run.
  Citations: D-10 · obs:8f7bd38f · obs:95ecef76 · obs:f5884930 · obs:ed0c7477.
- **The shared command-guard library extraction.** The two guards duplicate a
  security-critical tokenizer and now resolve the trusted root differently, so
  a tokenizer fix must be applied twice. Confidence: high.
  **Gate:** a dedicated refactor bundle owning both guards, which the
  `worker-permission-ergonomics` amendment may surface as a prerequisite if
  its screen changes prove unmaintainable across the duplicate engines.
  Citations: obs:30159d5c · obs:92809aad · obs:026930ca.
- **Worker scratch isolation via a per-worker `TMPDIR`.** Concurrently
  dispatched workers collide on identical `/tmp` filenames because they follow
  the same skill instructions and pick the same obvious names; the durable fix
  is a private scratch directory set at dispatch rather than per-callsite
  discipline. Confidence: medium — the mechanism is clear, its placement
  between this bundle and the dispatch layer is not.
  **Gate:** the Task 3 dispatch-seam work lands and shows whether the env
  contract is the natural home for it.
  Citations: obs:dc8998dd.

## Out of scope

- **Auto-merge at any tier.** Permanent floor, carried unchanged from
  `autonomous-safe-decision`. Citations: REQ-J1.1.
- **Reclaiming a dead tower's unit of work.** A fenced-but-unfinished unit is
  surfaced for the operator's reserved reclaim decision; this bundle releases
  processes only. Citations: D-2 · REQ-D1.3.
- **Worktree reclamation from the close verb.** Stays with
  `fleet-cleanup.sh worktree` and its positive-evidence checks.
  Citations: D-3.
- **Tower-to-tower messaging and any `REQ-D1.1` amendment.** The attributed
  buffer-paste relay already serves peer towers sharing a tmux server.
  Citations: D-7.
- **A backend-table row for messaging, and any advertised-boolean change.**
  Citations: D-8.
- **The worker command-guard screens and worker-settings profile delivery.**
  Owned by `worker-permission-ergonomics`; routed there as a scoped amendment
  seeded at `specs/_pending/`. Citations: D-9 · obs:814c6ba9.
- **The deterministic PR-ready attention record.** Owned by
  `merge-currency-guard`, which `fleet-coordination-floor` names as owner of
  the deterministic PR-ready push; routed there as a scoped amendment seeded
  at `specs/_pending/`. Citations: D-9 · obs:bfc6faf0.
- **Cross-machine and containerised peer awareness.** Single-host scope,
  inherited from the presence surface.
