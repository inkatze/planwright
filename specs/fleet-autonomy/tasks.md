# Fleet Autonomy — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-14
**Format-version:** 2
**Execution:** derived — see the status render

Eight tasks. Task 1 is foundational and is dispatched first per the guard-infrastructure-first
selection rule; every task except Task 6 depends on it (Task 6's ghost-text prevention is a static
env-var set unconditionally at dispatch, never a runtime kill/cleanup/restart/throttle decision, so
it needs none of Task 1's kill-switch or audit-trail infrastructure — a deliberate non-edge, not an
oversight). Tasks 2, 3, 4, 5, and 7 are otherwise independent of one another; Task 8
(observability/rendering) depends on Tasks 2, 3, 4, and 7's real daemon activity existing to
render.

## Tasks

### Task 1 — Shared floors & daemon infrastructure

- **Deliverables:** The doctrine statements for the tower non-authoring boundary and the
  no-LLM-daemon-mechanics invariant; a shared config-knob resolution helper following the
  existing `config-get.sh`/`resolve-*.sh` pattern for every new knob this bundle introduces; a
  thin wrapper exposing `orchestration-fleet`'s existing positive-evidence-of-death predicate for
  reuse by every kill/cleanup/restart mechanism in this bundle; the operator kill-switch knob and
  its check helper; the shared audit-trail write helper every daemon mechanism logs through.
- **Done when:** the two doctrine statements exist and are cited by REQ-G1.1/REQ-G1.2; a new
  config knob added under this pattern resolves through all four overlay layers with the same
  malformed-value-by-layer policy `review_sequence` already has; the positive-evidence-of-death
  wrapper has a unit test proving it refuses to act on a timeout alone; the kill-switch, once set,
  is observably checked (a stubbed daemon call short-circuits) before any daemon action; the
  audit-trail helper's writes are validated against a control-free text grammar before write
  (mirroring `fleet-attention.sh`'s `valid_text` discipline); CI passes.
- **Dependencies:** none
- **Citations:** D-5, D-15, D-16, D-17, D-18, D-22 · REQ-A1.7, REQ-F1.3, REQ-F1.4, REQ-G1.1,
  REQ-G1.2, REQ-G1.5
- **Estimated effort:** 2 days

### Task 2 — Push-based worker liveness, state classification & crash-loop backoff

- **Deliverables:** Hook wiring (`Stop`, `PermissionRequest`, `PostToolUse`-after-pending-request,
  `SessionEnd`, `StopFailure`) writing worker state transitions to `fleet-attention.sh`'s state
  store the instant they occur, with graceful fallback to capture-pane observation on a backend
  that cannot register hooks; the five-state classifier (`working`/`idle`/`hung`/
  `awaiting-human`/`flailing`); the escalating crash-loop backoff with a disable threshold.
- **Done when:** each hookable transition in REQ-A1.1 is observably pushed (a test worker session
  fixture proves the state store updates within one event cycle, not on the next tower poll); a
  `flailing` classification never triggers an automatic restart (test proves it only queues a
  human decision); a repeated-crash fixture proves the backoff schedule escalates and the worker
  is disabled after the configured threshold rather than looping; every classification and backoff
  action logs through Task 1's audit-trail helper; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-1, D-2, D-3 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4
- **Estimated effort:** 3 days

### Task 3 — Tower-liveness watchdog, crash recovery & session-per-tower isolation

- **Deliverables:** An external, cron-scheduled liveness check (via Claude Code's scheduled-agent
  primitive, never another tower) for unattended towers, relaunching a fresh memoryless tower on
  positive evidence of death when ready work exists (readiness resolved by calling through to
  `/orchestrate`'s own ready-task selection, never a hand-rolled check against `tasks.md`'s
  committed shape); the same escalating backoff and disable-after-threshold schedule as Task 2's
  worker crash-loop handling, applied to repeated tower-relaunch failure (REQ-A1.9); a
  `SessionStart` (`source: "startup"`) hook surfacing the exact `claude --resume <session-id>`
  command for an interactively-led tower found dead; the session-per-tower (or equivalent)
  launch-structure change keeping fleet activity out of the operator's own tmux windows.
- **Done when:** a killed unattended-tower fixture is relaunched by the cron check with no human
  present, using only durable disk state (the same "could a fresh tower resume from this alone?"
  snapshot test the existing auto-heal handover uses); a repeated-tower-crash fixture proves the
  relaunch backoff schedule escalates and the cron check disables (stops relaunching) after the
  configured consecutive-failure threshold, with a decision-queue entry recording the disable; a
  killed interactive-tower fixture produces the exact resume command on the next `startup`, with no
  auto-resume and no auto-discard of the marker; a fresh tower launch lands in its own
  session/isolation unit, verified not to create a window inside a pre-existing, unrelated tmux
  session; every watchdog action logs through Task 1's audit-trail helper; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-4, D-20, D-21 · REQ-A1.5, REQ-A1.6, REQ-A1.9, REQ-G1.3, REQ-G1.4
- **Estimated effort:** 3 days

### Task 4 — Cleanup, housekeeping sweep & reconcile backstop

- **Deliverables:** Stale window/pane/worktree cleanup beyond the existing merged-and-idle case,
  as deterministic script logic with an explicit self-targeting guard; `WorktreeCreate`/
  `WorktreeRemove` hook wiring for worktree lifecycle tracking; the periodic dirty-tree sweep
  across every tracked working tree (worker worktrees and the tower's own checkout, whatever
  branch); this sweep doubles as the REQ-A1.8 reconcile-from-ground-truth backstop for missed
  pushes.
- **Done when:** a cleanup fixture proves the mechanism refuses to target its own hosting session
  (the anthropics/claude-code#29787 failure mode, reproduced and shown blocked); worktree
  create/remove events are observably tracked via the hook pair on a backend that supports it,
  falling back to a disk scan where it does not; a fixture with a deliberately-injected stale
  uncommitted diff on a tower's own checkout is caught by the sweep and escalated to the decision
  queue, not silently left; a fixture with a deliberately-dropped push is shown corrected on the
  sweep's next cycle; every action logs through Task 1's audit-trail helper; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-1, D-6, D-7, D-8 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-A1.8
- **Estimated effort:** 2 days

### Task 5 — Context-budget corroboration

- **Deliverables:** A peer-pane `/context` capture mechanism offering a corroborating direct
  context-budget signal alongside the existing step-count proxy, capability-gated to backends
  supporting a peer observation pane, running only against an idle observed session.
- **Done when:** the mechanism is skipped (not attempted) against a busy session; a fixture with a
  deliberately malformed/unexpected `/context` rendering degrades to the step-count proxy with a
  warning rather than halting opaquely; the capability gate correctly reports the mechanism absent
  on a backend with no peer-pane capability; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-9 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** 2 days

### Task 6 — Ghost-text prevention at dispatch

- **Deliverables:** `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` set in the environment of every
  fleet-launched session read via pane capture (dispatched workers, and any tower a meta-tower
  observes); the backspace-probe disambiguation documented as an explicit, undispatched
  defense-in-depth fallback (see Deferred).
- **Done when:** a launched worker and a launched, meta-tower-observed tower both show the
  environment variable set (a fixture inspects the launched process's environment); no
  runtime ghost-text detection code ships as a required path; the fallback is documented in
  `docs/fleet.md` with its gate condition; tests/CI pass.
- **Dependencies:** none
- **Citations:** D-10 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** half day

### Task 7 — Resource governance: model/effort/command selection, reactive throttling, auto-mode guard

- **Deliverables:** A rule-based, task-type-keyed heuristic table resolving per-task model,
  reasoning effort, and slash-command selection; reactive fleet-wide dispatch throttling triggered
  by detecting Claude Code's own native rate-limit signal; a dispatch-time guard/lint proving
  worker sessions are never launched with `--permission-mode auto`.
- **Done when:** the heuristic table resolves a model/effort/command choice deterministically for
  a representative set of task-type fixtures with no LLM call in the resolution path; a fixture
  simulating Claude Code's native rate-limit prompt/retry event shows fleet-wide dispatch pausing
  and resuming at the signaled reset time; throttle-engagement events log through Task 1's
  audit-trail helper (a fixture proves the engage/clear rows are queryable); the auto-mode guard
  fails a fixture that attempts to
  launch a worker with `--permission-mode auto`; the guard/heuristic never overlaps
  `review_sequence`'s convergence-phase scope (a cross-check against `resolve-review-sequence.sh`'s
  nestable-skill set); tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-11, D-12, D-16, D-19 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-F1.4
- **Estimated effort:** 2 days

### Task 8 — Operator observability: fleet stats & the `statusline` channel

- **Deliverables:** Derived fleet-stats rendering (last-cleanup time, watchdog-trip
  count, throttle-engaged state) computed on demand from Tasks 2–4 and 7's state and audit-trail
  data, never captured into a new shared-write file; a `statusline` value added to the existing
  `notification_channel` enum, rendering the stats natively via Claude Code's `statusLine`
  feature, composing with `fleet-attention.sh`'s existing render/queue functions; a human-facing
  render of the Task 1 audit trail.
- **Done when:** the stats view reflects real activity from a fixture run of Tasks 2, 3, 4, and 7
  with no intermediate file written solely for stats; `notification_channel: statusline` renders
  correctly in a `statusLine`-invoking fixture and is documented in `docs/options-reference.md`
  alongside the existing enum values; `check-options-reference.sh` passes for the new value; the
  audit-trail render is queryable by mechanism and time range; tests/CI pass.
- **Dependencies:** 1, 2, 3, 4, 7
- **Citations:** D-13, D-14, D-16 · REQ-F1.1, REQ-F1.2, REQ-F1.4
- **Estimated effort:** 1.5 days

## Awaiting input

(none yet)

## Deferred

- **The backspace-probe ghost-text disambiguation fallback.** Task 6 ships prevention via the
  environment variable; the folklore backspace-probe detection method (REQ-D1.2) stays documented
  but unimplemented until prevention proves insufficient. Confidence: high.
  **Gate:** a concrete case where `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` fails to prevent
  ghost-text ambiguity is observed in the drain loop. Citations: D-10 · REQ-D1.2.
- **Local-transcript (`ccusage`-style) usage estimation as a throttle corroborating signal.** Task
  7 ships reactive throttling off Claude Code's native rate-limit signal alone; a supplementary
  local-transcript-based estimate of past consumption is not built until the reactive-only signal
  proves insufficient. Confidence: medium.
  **Gate:** a concrete case where the reactive signal fires too late relative to actual quota
  exhaustion is observed in the drain loop. Citations: D-12 · REQ-E1.3.
- **A non-Claude-Code-native scheduling fallback for the tower-liveness watchdog.** Task 3 uses
  Claude Code's own scheduled-agent primitive; a plain OS-level cron (or equivalent) fallback for
  an adopter without access to that primitive is not built speculatively. Confidence: medium.
  **Gate:** a concrete adopter need for a non-Claude-Code-native scheduling path is observed in the
  drain loop. Citations: D-4 · REQ-A1.5.

## Out of scope

- Auto-merge at any tier (permanent carried invariant).
- Replacing a worker's Claude Code session with a lighter-weight script or non-agentic subprocess.
- A GUI/web fleet dashboard (`orchestration-fleet`'s existing `Deferred` call stands; the
  `statusline` channel meets the need without reopening it).
- A second-multiplexer adapter (still gated on a concrete adopter need, per `orchestration-fleet`).
- `orchestration-concurrency`'s state-safety internals (consumed as authoritative, never
  redefined here).
- A parallel autonomy taxonomy (the existing finding-categorization mapping is reused).
- New AI/agent frameworks (Claude Code primitives only).
- A confidence-calibrated model-routing cascade (D-11).
- A self-imposed dollar-spend ceiling, distinct from rate-limit throttling (parked as a pending
  seed).
- Extending `review_sequence` to chain post-PR autonomous-loop skills or introducing
  task-PR-ready-marking automation (parked as the `review-gauntlet` pending seed).
