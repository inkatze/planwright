# Fleet Autonomy — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Eleven tasks. Task 1 is foundational and is dispatched first per the guard-infrastructure-first
selection rule; every task except Task 6 depends on it (Task 6's ghost-text prevention is a static
env-var set unconditionally at dispatch, never a runtime kill/cleanup/restart/throttle decision, so
it needs none of Task 1's kill-switch or audit-trail infrastructure — a deliberate non-edge, not an
oversight). Tasks 2, 3, 4, 5, and 7 are otherwise independent of one another; Task 8
(observability/rendering) depends on Tasks 2, 3, 4, and 7's real daemon activity existing to
render. Tasks 9, 10, and 11 are the 2026-07-20 resource-governance extension: Task 9 (proactive
usage gate) depends on Task 1's daemon/audit infrastructure and Task 7's throttle mechanism; Task 10
(configurable budget-aware allocation) depends on Task 1, on Task 7's selection table, and on Task
9 — the degrade ladder cannot downshift without Task 9's usage signal; Task 11 (credit-continuation
recovery) depends on Task 1 and Task 7 (it reacts to the wall prompt, not the proactive read, so it
is independent of Task 9 and can run in parallel with it).

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

- **Deliverables:** An external, cron/launchd-scheduled liveness check (a deterministic
  operator-scheduled script, never another tower and never an LLM — D-4, REQ-G1.2) for unattended
  towers, relaunching a fresh memoryless tower on
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
  session; an overlapping-invocation fixture proves the relaunch path serializes on the existing
  per-spec advisory lock (D-20) and re-verifies positive evidence of death under the lock before
  acting (risk register rows 1 and 6: a concurrent tick is a clean no-op, a tower alive at the
  re-check is left alone, and no double-launch occurs); every watchdog action logs through
  Task 1's audit-trail helper; tests/CI pass.
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

### Task 9 — Proactive shared-aware usage gate

- **Deliverables:** A helper that captures Claude Code's own `/usage` output (via a throwaway-pane
  scrape of the live TUI — the mechanism a fleet tower has already used in operation) and parses
  **both** rendered windows — the session (~5-hour) and the weekly — each identified explicitly (by
  label, not position) with its percentage and reset time where shown, applying a plausibility check
  (0–100, expected render shape) and degrading to an explicit per-window "unavailable" on any
  capture, parse, or plausibility failure; the proactive gate that maps each window's percentage to
  a target rung on the restriction ladder (`normal` → `downshift` → `reduce-concurrency` →
  `defer-heavy` → `defer-all`), taking the more restrictive of the two windows, with the session
  window capped at `defer-heavy` and only the weekly window able to reach `defer-all`, evaluated by
  deterministic comparison, thresholds resolved through the four-layer overlay mechanism (the
  `downshift`/`reduce-concurrency` rung *values* are Task 10's); wiring so each rung transition is a
  first-class daemon action (kill-switch-pausable, audited); the Task 7 reactive throttle retained
  unchanged as the authoritative full-stop backstop the gate degrades to; rung engagement surfaces
  through the existing throttle-engaged stat channel Task 8 already renders (the gate is
  throttle-family, so it reuses that state rather than minting a new stat type).
- **Done when:** a fixture feeding a representative `/usage` render asserts the parser extracts
  **both** window percentages deterministically, each by label, with no LLM/API call in the path; a
  fixture asserts rising usage selects progressively heavier rungs and that the more restrictive
  window governs (session below / weekly above, and the reverse); a session-cap fixture asserts the
  session window never selects above `defer-heavy` while weekly can reach `defer-all`; a `defer-heavy`
  fixture asserts heavy/opus units are withheld while cheaper units still dispatch; a fixture asserts
  non-monotonic per-window rung thresholds are rejected; a fixture with unparseable or absent
  `/usage` asserts the signal reports unavailable and governance falls back to the reactive backstop
  (REQ-E1.7) — no block, no guessed number; a fixture with an out-of-range or otherwise implausible
  parsed value asserts it is treated as unavailable (never acted on); a fixture with a cached signal
  older than its configured TTL asserts it is treated as unavailable; a fixture holding the signal
  unavailable across the configured consecutive-cadence count asserts the required sustained-loss
  operator surface fires (warning → Awaiting-input hold); the read cadence/TTL and the
  per-window rung-threshold knobs resolve through the overlay (a machine-local override wins, verified
  via `config-get.sh`); rung-transition events log through Task 1's audit-trail helper and honor the
  kill-switch, and an audit-row assertion confirms rows carry only the extracted percentages and the
  rung decision, never the raw `/usage` render; a fixture asserts the current rung and last-transition
  timestamp are **derived from the audit trail** (a fresh process with no in-memory state recovers the
  rung) and that transitions are **edge-triggered** (no row on an unchanged rung); a two-tower fixture
  asserts rung transitions serialize under the advisory lock (REQ-G1.3) with no interleaved or
  duplicate rows; tests/CI pass.
- **Dependencies:** 1, 7
- **Citations:** D-23, D-28, D-12 · REQ-E1.5, REQ-E1.6, REQ-E1.7, REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.3, REQ-G1.5
- **Estimated effort:** 2.5 days

### Task 10 — Configurable, budget-aware model allocation & degrade ladder

- **Deliverables:** The Task 7 model/effort/command selection table made operator-configurable
  through the four-layer overlay mechanism, with shipped defaults that preserve current selection
  behavior; per-model budget caps/shares of the shared account limit, enforced by deterministic
  comparison against Task 9's usage signal; the `downshift` and `reduce-concurrency` rung *values*
  of the restriction ladder (which tier each downshift step selects, the concurrency limit per rung),
  keyed off Task 9's rung signal, with descend/restore when budget recovers and hysteresis on rung
  transitions; the per-model-reservation exemption (a pinned unit skips `downshift`/`defer-heavy` but
  not `defer-all`); a guard proving every degrade step degrades capability only — never below a full
  session-grade worker session, never relaxing the autonomous-safe-decision determinism floor, never
  engaging `auto` permission mode.
- **Done when:** a fixture asserts an operator overlay retunes the per-task-type model/effort
  mapping while the shipped defaults reproduce today's selection when nothing is configured; a
  fixture asserts per-tier caps (opus's global-usage threshold below sonnet's) withdraw expensive
  tiers from routine units sooner, by deterministic comparison against a stubbed signal with no LLM
  call and no per-model accounting state; a fixture asserts the signal-unavailable behavior — the
  ladder holds its last-known rung (recovered from the audit trail) within the grace window, then
  decays to `normal` — and that caps are inactive while unavailable; a fixture driving the rung
  signal up asserts allocation climbs one rung (`downshift`, then `reduce-concurrency`) and descends
  when budget recovers; a fixture driving the signal oscillating across a rung threshold asserts
  allocation does not flap (the configured hysteresis band / minimum dwell holds the rung); a
  reservation fixture asserts a pinned unit is exempt from `downshift`/`defer-heavy` but yields at
  `defer-all`, and that the shipped default reserves nothing; a guard fixture asserts every degrade
  step stays session-grade, never relaxes the determinism floor (REQ-G1.2), and never selects
  `--permission-mode auto` (REQ-E1.4); a stubbed-client assertion confirms the rung-transition logic
  is LLM-free; each rung transition logs through Task 1's audit trail and the kill-switch reverts to
  the `normal` policy; the knobs resolve through the overlay (machine-local wins); tests/CI pass.
- **Dependencies:** 1, 7, 9
- **Citations:** D-24, D-25, D-26, D-28 · REQ-E1.8, REQ-E1.9, REQ-E1.10, REQ-E1.5, REQ-E1.4, REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.3, REQ-G1.5
- **Estimated effort:** 2.5 days

### Task 11 — Credit-continuation recovery

- **Deliverables:** Detection of Claude Code's credit-continuation prompt at the rate-limit wall
  (the "spend credits / extra usage to continue" offer) as a deterministic recognizer over the wall
  surface, riding Task 7's reactive-wall detection; a default response that declines and waits for
  the window to reset (the reactive-backstop behavior), never auto-spending; an overlay opt-in knob
  that, only when explicitly set, permits spending credits to continue; wiring so the decision is an
  audited, kill-switchable daemon action, and never engages Claude Code's `auto` permission mode.
- **Done when:** a fixture feeding a representative credit-continuation prompt asserts the default
  response is decline-and-wait with no credits spent and no LLM/API call in the decision path; a
  fixture with the overlay opt-in set asserts credits are permitted (and a machine-local override
  wins, verified via `config-get.sh`); a fixture asserts the shipped default (nothing configured)
  never spends; the decline/opt-in decision logs through Task 1's audit-trail helper and honors the
  kill-switch; an adversarial/garbled prompt fixture asserts a non-recognized wall variant falls
  through to the plain reactive backstop (no accidental spend); tests/CI pass.
- **Dependencies:** 1, 7
- **Citations:** D-27 · REQ-E1.11, REQ-E1.7, REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.5
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **The backspace-probe ghost-text disambiguation fallback.** Task 6 ships prevention via the
  environment variable; the folklore backspace-probe detection method (REQ-D1.2) stays documented
  but unimplemented until prevention proves insufficient. Confidence: high.
  **Gate:** a concrete case where `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` fails to prevent
  ghost-text ambiguity is observed in the drain loop. Citations: D-10 · REQ-D1.2.
- **Local-transcript (`ccusage`-style) usage estimation as a corroborating signal.** Task 7 ships
  reactive throttling off Claude Code's native rate-limit signal, and the 2026-07-20 extension adds
  the proactive `/usage` gate (Task 9) as the ahead-of-the-wall mechanism — so the original "reactive
  fires too late" gap is now covered by the proactive gate, not by ccusage. A supplementary
  local-transcript estimate of past consumption stays deferred as a *corroborating* cross-check on
  the `/usage` read (never the gate input: it reconstructs past consumption, not remaining
  server-side quota), not built until the `/usage` read plus reactive backstop prove insufficient.
  Confidence: medium.
  **Gate:** a concrete case where the `/usage` read is unavailable or wrong often enough that a
  corroborating estimate would materially help is observed in the drain loop. Citations: D-12, D-23
  · REQ-E1.5, REQ-E1.7.
- **A turnkey scheduler-registration helper for the tower-liveness watchdog.** Task 3 ships the
  watchdog as a deterministic script the operator schedules from their own cron/launchd (the
  no-LLM-daemon floor, D-4/REQ-G1.2, is why it is never a Claude Code scheduled-agent); the operator
  wires the schedule by hand (docs/fleet.md gives the crontab example). A helper that registers that
  schedule for the operator is not built speculatively. Confidence: medium.
  **Gate:** a concrete adopter need for automated schedule registration is observed in the
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
