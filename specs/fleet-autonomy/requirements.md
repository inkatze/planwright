# Fleet Autonomy — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's fleet mechanisms today are all tower-loop-invoked: `fleet-attention.sh`,
`context-budget-monitor.sh`, and the relay protocol run only when a tower's own `--watch` step
remembers to call them, and routine liveness checks still poll worker panes via `capture-pane`.
Nothing watches whether the fleet's own housekeeping — or a tower's own working tree, or the tower
process itself — has quietly drifted out of whack, and a full ungraceful crash (a host reboot, a
killed terminal) leaves no path back to an actively-led session's actual context, only to
re-derived ledger state.

This spec moves that mechanical load into software: independent, hook- and heartbeat-driven
self-maintenance, so towers and workers spend their attention on task work, not clerical upkeep.
Three floors hold throughout: workers remain full session-grade Claude Code sessions the tower
drives, never downgraded to lighter-weight scripts; every autonomous cleanup, kill, or
restart decision is deterministic script logic bound by the existing autonomous-safe-decision
policy, never in-context model judgment; and towers dispatch, monitor, and reconcile, but do not
author repo/config/content changes themselves except as a narrow, explicitly-flagged exception
(D-17).

It builds on `orchestration-fleet`'s execution/attention seams and `orchestration-concurrency`'s
state-safety as consumed, authoritative contracts, and is informed by prior art surveyed across
process supervision (systemd, Kubernetes, CI-runner fleets), the young Claude-Code-fleet-tooling
ecosystem, and LLM cost-governance practice — three areas surveyed and found thin, without a
mature precedent this spec can simply defer to wholesale.

**Resource-governance extension (2026-07-20).** This bundle's `REQ-E — Resource governance` group
is extended to close two coupled gaps that surfaced in fleet operation after the original bundle
shipped. First, the fleet's usage governance is **reactive only**: `REQ-E1.3`/D-12's throttle
waits until a session *hits* the wall and renders the retry text before pausing, on the premise
that "no supported machine-readable way exists to proactively query account-level usage." That
premise is now stale — the `/usage` command output is capturable and parseable, and because
`/usage` is **account-global** it is inherently shared-aware (it reflects every concurrent tower,
all workers, and unrelated non-planwright work on the same account), which is exactly the
cross-orchestrator blind spot the reactive-only model cannot see. Second, the `REQ-E1.1`/D-11
model/effort/command selection table is deterministic but not operator-configurable for **smart,
budget-aware allocation** (per-task model by complexity, per-model budget caps/shares of the
shared limit, a degrade-to-cheaper ladder when budget is tight). The two are coupled: budget-aware
allocation needs the proactive usage read to decide *when* to downshift. The extension lands as
opt-in, default-preserving configuration knobs and deterministic script logic within this
mechanism-primary bundle — a capability in core, its policy values in overlays — not as new
doctrine (the altitude call, D-26).

## Scope

### In scope

- Heartbeat-based worker liveness, pushed via native Claude Code hooks wherever a real event
  exists, replacing routine `capture-pane` polling; graceful across every dispatch backend
  (`subagent`, `tmux`, `print`, `in-session`).
- A three-way idle / hung / awaiting-human classification, plus a fourth, distinct **flailing**
  state (heartbeating, no forward progress) and escalating crash-loop backoff for stuck or
  repeatedly-failing workers.
- A tower-liveness watchdog covering ungraceful tower death, mode-aware: an external
  cron-scheduled check for unattended towers (relaunching a fresh, memoryless tower — never
  another tower watching a tower), and a `SessionStart` hook signposting the exact native
  `--resume` command for an interactively-led tower that died unexpectedly.
- Stale window/pane/worktree cleanup beyond the existing merged-and-idle case, and a sweep for
  stale uncommitted/unpushed diffs across every working tree the fleet tracks — including a
  tower's own checkout, on whatever branch it is on — all deterministic and
  positive-evidence-of-death gated.
- A corroborating direct context-budget signal (a peer pane running `/context`, capture-paned),
  capability-gated, with the existing step-count proxy retained as the portable fallback.
- Ghost-text prevention at dispatch, not detection at runtime, for every fleet-launched session
  read via pane capture.
- Rule-based per-task selection of model, reasoning effort, and which slash command(s) (generic
  or custom) a dispatched unit runs.
- Reactive fleet-wide dispatch throttling keyed off Claude Code's own native rate-limit signal,
  retained as the hard backstop beneath the proactive gate below.
- A proactive, shared-aware usage gate: reading real account-level usage from the capturable
  `/usage` command output and gating heavy/opus dispatch on a configurable budget threshold (a
  percentage of the account's own rate-limit window), warning earlier, ahead of the reactive wall.
- Operator-configurable, budget-aware model/effort/command allocation: the selection policy tunable
  through the overlay layers, per-model budget caps/shares of the shared limit, and a
  degrade-to-cheaper-tier ladder driven by the proactive gate — degrading capability, never any
  carried safety floor.
- An operator kill-switch pausing the autonomous daemon layer without disabling the fleet, and an
  audit trail for every autonomous daemon action.
- Lightweight fleet stats, derived and rendered on demand (never a new shared-write accumulator),
  surfaced through a new `statusline` value on the existing `notification_channel` overlay knob —
  a native-in-terminal surface, not a GUI/web dashboard.
- A tower non-authoring boundary, a blanket no-LLM-daemon-mechanics invariant, and an explicit
  rejection of Claude Code's `auto` permission mode for fleet dispatch, all as carried floors.
- Every knob this spec introduces resolving through the existing four-layer overlay mechanism.

### Out of scope

- Auto-merge at any tier (permanent floor, carried unchanged).
- Replacing a worker's Claude Code session with a lighter-weight script or non-agentic subprocess.
- A GUI/web fleet dashboard (`orchestration-fleet`'s existing `Deferred` call stands; the
  `statusline` channel meets the "visible in Claude Code" need without reopening it).
- A second-multiplexer adapter (still gated on a concrete adopter need, per `orchestration-fleet`).
- `orchestration-concurrency`'s state-safety internals (consumed as authoritative, never
  redefined here).
- A parallel autonomy taxonomy (the existing finding-categorization mapping is reused, not
  replaced).
- New AI/agent frameworks (Claude Code primitives only).
- A confidence-calibrated model-routing cascade (a rule-based heuristic is in scope; the
  calibration problem the cascade literature flags as hard is not).
- A self-imposed **dollar-spend** ceiling, distinct from both the reactive rate-limit throttle and
  the proactive usage gate this bundle adds (parked as a pending seed; no framework surveyed has a
  mature precedent to build on). The proactive gate added here reads the account's own usage
  percentage against its rate-limit window — it is not a currency-denominated budget.
- Extending the `review_sequence` knob to chain post-PR autonomous-loop skills
  (`/panel-pairing`, `/copilot-pairing`) or introducing task-PR-ready-marking automation (parked
  as the `review-gauntlet` pending seed — a different decision domain, task-execution convergence
  architecture rather than fleet/worker/tower orchestration).

## REQ-A — Liveness & recovery

- **REQ-A1.1** Worker state transitions SHALL be pushed via native Claude Code hook events at the
  instant they occur, wherever a real event exists, rather than discovered by a tower polling a
  worker's pane: `Stop` for working→idle, `PermissionRequest` for working→awaiting-human,
  the next `PostToolUse` after a pending `PermissionRequest` for awaiting-human→working,
  `SessionEnd` for session termination, and `StopFailure` for a turn ending on an API error. This
  mechanism SHALL degrade gracefully on a backend that cannot register hooks on a dispatched
  session, falling back to the existing capture-pane observation.
  *(Cites: D-1.)*
- **REQ-A1.2** A worker's state SHALL be classified as exactly one of: `working`, `idle`,
  `hung`, `awaiting-human`, or `flailing`. `flailing` SHALL be distinguished from `hung`: a
  `flailing` worker is heartbeating (harness responsive) but shows no forward progress (no new
  commit, no state change) across a configured threshold of heartbeats; a `hung` worker has
  stopped heartbeating entirely. Neither state SHALL be inferred from a timeout alone where a
  positive-evidence check (REQ-A1.7) is available.
  *(Cites: D-2.)*
- **REQ-A1.3** A `flailing` classification SHALL escalate to a human decision (the fork "this
  task may be stuck") and SHALL NOT be resolved by an automatic nudge or restart.
  *(Cites: D-2.)*
- **REQ-A1.4** A worker that crashes and is relaunched repeatedly SHALL back off on an escalating
  schedule and SHALL be disabled after a configured consecutive-failure threshold, escalating to
  a human decision rather than restart-looping indefinitely.
  *(Cites: D-3.)*
- **REQ-A1.5** An external, cron-scheduled check (never another Claude Code tower session) SHALL
  periodically verify, per spec, that a live tower process exists whenever ready work exists; on
  positive evidence of tower death (REQ-A1.7) with no live process, it SHALL launch a fresh,
  memoryless tower per the existing `continue-as-new` auto-heal handover — the same disk-rebuild
  model the graceful context-budget handoff already uses. This check SHALL apply only to towers
  known to be running in unattended (`--watch`) mode.
  *(Cites: D-4; orchestration-fleet REQ-C1.1, REQ-C1.2 (Sources).)*
- **REQ-A1.6** For a tower known to have been running in interactively-led mode, a `SessionStart`
  hook with `source: "startup"` SHALL detect an orphaned tower marker for the current
  repo/worktree and surface the exact recovery command (`claude --resume <session-id>`) to the
  human. This mechanism SHALL NOT auto-resume the session and SHALL NOT auto-discard the marker;
  the human chooses.
  *(Cites: D-4.)*
- **REQ-A1.7** Every mechanism in this spec that kills, cleans up, or restarts a resource SHALL
  act only on positive evidence of death or staleness (reusing the backend capability contract's
  existing `positive-evidence-of-death` predicate), never on a timeout or ambiguous/lost
  observability alone.
  *(Cites: D-5; orchestration-fleet's backend capability contract (Sources).)*
- **REQ-A1.8** The push mechanisms in REQ-A1.1 SHALL be treated as a latency optimization, not
  the sole source of correctness: the health watchdog (REQ-B1.3, REQ-F1.1) SHALL periodically
  reconcile state from ground truth (git, process, heartbeat-file evidence) regardless of whether
  pushes appear to be arriving, self-healing a missed hook fire, a failed write, or a dropped
  event on its next sweep.
  *(Cites: D-1.)*
- **REQ-A1.9** A tower relaunched repeatedly by the REQ-A1.5 cron watchdog SHALL back off on the
  same escalating schedule as REQ-A1.4 and SHALL be disabled — the cron check stops relaunching —
  after a configured consecutive-failure threshold, escalating to a human decision rather than
  relaunching indefinitely on every cron tick.
  *(Cites: D-4; kickoff §3 REQ-A (2026-07-14).)*

## REQ-B — Cleanup & housekeeping

- **REQ-B1.1** Stale window, pane, and worktree cleanup beyond the existing merged-and-idle case
  SHALL run as deterministic script logic, never in-context model judgment, and SHALL refuse to
  target the process's own hosting session (a self-targeting guard).
  *(Cites: D-6; the anthropics/claude-code#29787 self-termination postmortem (Sources).)*
- **REQ-B1.2** Worktree lifecycle tracking SHALL be pushed via the `WorktreeCreate` and
  `WorktreeRemove` hook events at creation and removal, rather than discovered by periodic disk
  scanning, wherever the dispatch backend supports hook registration. This mechanism SHALL degrade
  gracefully on a backend that cannot register the hook pair, falling back to periodic disk
  scanning.
  *(Cites: D-7.)*
- **REQ-B1.3** A periodic sweep SHALL check every working tree the fleet is tracking — every
  worker worktree and the tower's own checkout, on whatever branch it is currently on — for
  uncommitted or unpushed diffs sitting stale past a configured threshold, and SHALL escalate any
  such finding to the decision queue rather than leaving it to silently persist through a
  handover or a crash.
  *(Cites: D-8.)*

## REQ-C — Context-budget corroboration

- **REQ-C1.1** A corroborating, direct context-budget signal SHALL be available: a peer pane
  running `/context`, capture-paned, offered alongside the existing completed-step-count proxy.
  This signal is capability-gated (available only where the dispatch backend supports a peer
  observation pane) and the step-count proxy SHALL remain the portable fallback in every case.
  *(Cites: D-9; the context-budget premise-challenge observation (Sources).)*
- **REQ-C1.2** The peer-pane `/context` check SHALL only be attempted while the observed session
  is idle; it SHALL NOT run against a busy session, and its parsed output SHALL be treated as
  UI text (an unstable contract), never a stable API — a parse failure SHALL degrade to the
  step-count proxy with a warning, never halt opaquely.
  *(Cites: D-9.)*

## REQ-D — Relay hygiene

- **REQ-D1.1** Every fleet-launched Claude Code session that another session reads via pane
  capture (a dispatched worker, and any tower a meta-tower observes) SHALL be launched with
  `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` set in its environment, preventing input-line
  ghost-text ambiguity at the source rather than detecting it at runtime.
  *(Cites: D-10.)*
- **REQ-D1.2** A backspace-probe disambiguation check MAY be implemented as a documented
  defense-in-depth fallback for the case where REQ-D1.1's environment variable was not applied
  (e.g. a future Claude Code surface renders suggestions somewhere this does not cover), but
  SHALL NOT be the primary or required mechanism.
  *(Cites: D-10; the ghost-text-disambiguation observation (Sources).)*

## REQ-E — Resource governance

- **REQ-E1.1** Per-task model and reasoning-effort selection SHALL be resolved by a rule-based,
  task-type-keyed heuristic table (a deterministic mapping), not a confidence-calibrated model
  cascade.
  *(Cites: D-11.)*
- **REQ-E1.2** Selection of which slash command(s) — generic or custom — a dispatched unit
  invokes SHALL be resolved by the same rule-based heuristic mechanism as REQ-E1.1, distinct from
  and never overlapping the existing `review_sequence` knob's convergence-phase scope.
  *(Cites: D-11.)*
- **REQ-E1.3** Fleet-wide dispatch throttling SHALL be reactive, triggered by detecting Claude
  Code's own native rate-limit signal (its rate-limit prompt/retry event) fleet-wide and pausing
  dispatch until the signaled reset time, since no supported machine-readable way exists to
  proactively query Claude Code's own account-level usage or rate-limit state.
  *(Cites: D-12.)*
  **Superseded-by: REQ-E1.7** (2026-07-20) — the "no machine-readable usage query" premise is
  stale (`/usage` is now capturable, D-23); reactive throttling is retained as the hard backstop
  but is no longer the sole governance mechanism.
- **REQ-E1.4** Fleet dispatch SHALL NOT use Claude Code's `auto` permission mode for worker
  sessions. The existing human-reviewed, human-installed static worker-settings-profile allowlist
  (`config/worker-settings.json`) SHALL remain the sole permission-approval mechanism for
  dispatched workers.
  *(Cites: D-19.)*
- **REQ-E1.5** A proactive account-usage read SHALL capture and parse Claude Code's own `/usage`
  command output into a machine-readable usage signal (at minimum the percentage consumed of the
  active rate-limit window). Because `/usage` is account-global, the read SHALL be treated as
  inherently shared-aware — reflecting every concurrent tower, all workers, and unrelated
  non-planwright work on the same account — and the mechanism SHALL NOT maintain any
  per-orchestrator usage reservation or accounting (the shared `/usage` figure is ground truth).
  The read SHALL degrade gracefully: when `/usage` output cannot be captured or parsed, the signal
  SHALL be reported unavailable and governance SHALL fall back to the reactive backstop (REQ-E1.7)
  rather than blocking or guessing.
  *(Cites: D-23; obs:5d6d206c.)*
- **REQ-E1.6** Fleet dispatch of heavy/expensive units SHALL be gated proactively on a
  configurable budget threshold evaluated against the REQ-E1.5 usage signal (for example, pause
  heavy/opus dispatch at a configured percentage of the weekly window, with an earlier warn
  threshold), so governance acts ahead of the reactive wall rather than only at it. The threshold(s)
  SHALL resolve through the four-layer overlay mechanism (REQ-G1.5), and the gate SHALL be a
  deterministic comparison, never an LLM judgment (REQ-G1.2). The gate is a throttle-family daemon
  action — a proactive dispatch pause — and SHALL be audited and kill-switchable on the same footing
  as the reactive throttle (REQ-F1.3, REQ-F1.4), so it does not introduce a new daemon-action type.
  *(Cites: D-23; obs:5d6d206c.)*
- **REQ-E1.7** Reactive fleet-wide dispatch throttling (the REQ-E1.3 mechanism: detect Claude
  Code's native rate-limit signal, pause fleet-wide, resume at the signaled reset time) SHALL be
  retained as the hard backstop beneath the proactive gate (REQ-E1.6). The two SHALL compose: the
  proactive gate aims to keep the fleet from reaching the wall, and the reactive throttle catches
  the case where it does anyway (including load the proactive read cannot see between reads). This
  requirement carries no premise about the (un)availability of a machine-readable usage query.
  *(Cites: D-12, D-23; supersedes REQ-E1.3.)*
- **REQ-E1.8** The per-task model/effort/command selection policy (the REQ-E1.1/REQ-E1.2 rule
  table) SHALL be operator-configurable through the four-layer overlay mechanism (REQ-G1.5), so an
  operator can tune per-task-type model and effort without code changes. The shipped defaults SHALL
  preserve the current selection behavior (opt-in, default-preserving): an operator who configures
  nothing gets today's mapping. The policy SHALL remain a deterministic rule table (REQ-E1.1's
  no-cascade, no-LLM property is preserved, REQ-G1.2).
  *(Cites: D-24; obs:9af1f82f.)*
- **REQ-E1.9** The allocation config SHALL support per-model budget caps / shares of the shared
  account limit (for example, reserving capacity on the most capable model for the single
  foundational or hardest unit per wave, rather than spending it on routine units). Caps/shares
  SHALL resolve through the overlay mechanism (REQ-G1.5) and SHALL be enforced by deterministic
  comparison against the REQ-E1.5 usage signal, never an LLM judgment (REQ-G1.2).
  *(Cites: D-24; obs:9af1f82f.)*
- **REQ-E1.10** When the proactive usage gate (REQ-E1.6) or a per-model cap (REQ-E1.9) signals the
  budget is tight, model/effort allocation SHALL degrade along a configured degrade ladder to a
  cheaper model/effort tier. The degradation SHALL degrade **capability only** and SHALL NEVER
  weaken a carried safety floor: it SHALL NOT downgrade a worker below a full session-grade Claude
  Code session (Out of scope: lighter-weight-script workers), SHALL NOT relax the
  autonomous-safe-decision determinism floor (REQ-G1.2), and SHALL NOT engage Claude Code's `auto`
  permission mode (REQ-E1.4). The ladder SHALL resolve through the overlay mechanism (REQ-G1.5) and
  each degrade step SHALL be an audited daemon action subject to the kill-switch (REQ-F1.3,
  REQ-F1.4) — engaging the kill-switch returns allocation to the default (un-degraded) policy.
  *(Cites: D-25; obs:9af1f82f, obs:5d6d206c.)*

## REQ-F — Operator control & observability

- **REQ-F1.1** Fleet health/activity statistics (last-cleanup time, watchdog-trip
  count, throttle-engaged state, and similar counters) SHALL be derived and rendered on demand
  from existing per-worker/per-daemon state, never captured into a new shared-write accumulator
  file.
  *(Cites: D-13.)*
- **REQ-F1.2** A `statusline` value SHALL be added to the existing `notification_channel` overlay
  knob's enum, rendering the REQ-F1.1 stats natively inside the operator's own Claude Code
  terminal via the `statusLine` mechanism, composing with the existing
  `fleet-attention.sh` render/queue functions rather than introducing a new surface.
  *(Cites: D-14.)*
- **REQ-F1.3** An operator-facing kill-switch config knob SHALL pause every autonomous daemon
  action (cleanup, restart, throttle) this spec introduces, without disabling fleet
  operation entirely.
  *(Cites: D-15.)*
- **REQ-F1.4** Every autonomous daemon action this spec introduces (a cleanup, a
  restart, a throttle engagement) SHALL log its trigger and reasoning to an audit trail available
  for human review.
  *(Cites: D-16.)*

## REQ-G — Fleet coordination floor

- **REQ-G1.1** A tower SHALL dispatch, monitor, and reconcile; it SHALL NOT author repo, config,
  or content changes itself except as a narrow, explicitly-flagged exception surfaced as a
  Needs-human-judgment fork — never as the default response to a "quick change" request.
  *(Cites: D-17; the doctrine-gap(tower-role) observation (Sources).)*
- **REQ-G1.2** No daemon, hook, or cron mechanism this spec introduces SHALL invoke an LLM to
  make a routine mechanical decision (a liveness check, a cleanup, a throttle decision).
  Every such mechanism SHALL be deterministic script logic operating on structured signals
  (files, process IDs, git state, pattern-matched known text); LLM invocation stays reserved for
  the tower and worker sessions doing the actual task work.
  *(Cites: D-18.)*
- **REQ-G1.3** Coordination among multiple concurrently-running towers' daemon actions SHALL
  serialize through `orchestration-concurrency`'s existing per-spec advisory lock; this spec SHALL
  NOT introduce a second lock primitive.
  *(Cites: D-20; orchestration-concurrency's advisory lock (Sources).)*
- **REQ-G1.4** Fleet-launched sessions SHALL be structured session-per-tower (or an equivalent
  isolation unit), so fleet activity does not land in a resident tmux operator's own windows or
  session.
  *(Cites: D-21.)*
- **REQ-G1.5** Every configuration knob this spec introduces SHALL resolve through the existing
  four-layer overlay mechanism (`config-get.sh` and the `resolve-*.sh` pattern), never a second
  config-resolution path.
  *(Cites: D-22; customization-overlay's overlay mechanism (Sources).)*

## Changelog

- 2026-07-14 — Initial draft.
- 2026-07-14 — Kickoff walkthrough: reworded REQ-A1.1's "working→idle/done" to "working→idle"
  (expression-only; "done" was shorthand for the existing merged-and-idle cleanup case, REQ-B1.1,
  not a distinct liveness state — confirmed with the human at kickoff). Added REQ-A1.9 (tower
  crash-loop backoff/disable, extending REQ-A1.4's pattern to REQ-A1.5's cron watchdog — a gap
  surfaced during the kickoff requirements walkthrough; `tasks.md` Task 3's Deliverables/Done-when
  updated to match). Added an explicit disk-scan-fallback
  clause to REQ-B1.2 (expression-only; test-spec.md and D-7 already assumed it, the REQ text did
  not state it). Cited D-17 inline from the Goal's tower-non-authoring sentence
  (expression-only), recording D-17 as the altitude D-ID for the doctrine-gap(tower-role)
  seed-claim trigger per `autopilot-reflex.md`. (Meaning-class) Added Task 7 to Task 8's
  `Dependencies:` in `tasks.md`: Task 8's own deliverables render Task 7's throttle-engaged state,
  which its dependency list had omitted — a task-graph gap surfaced during the kickoff task-graph
  walkthrough; `tasks.md`'s intro prose corrected to match (Task 6's no-dependency-on-Task-1
  non-edge stated explicitly; the prior "every other task consumes its shared helpers" claim
  contradicted it). Fixed a second staleness gap in the same area, surfaced by the sign-off lens
  pass: Task 8's own `Done when` in `tasks.md` still omitted Task 3 (source of "watchdog-trip
  count," one of Task 8's own rendered stats) after the Task 7 fix, and `test-spec.md`'s REQ-F1.1
  entry was never updated at all — both now read "Tasks 2, 3, 4, and 7." Namespace-qualified the
  "REQ-H1.3" citation in `design.md`'s D-17 amendment and this bundle's `kickoff-brief.md` to
  `autopilot-reflex REQ-H1.3` (confirmed via `specs/autopilot-reflex/requirements.md`; it
  referenced a foreign spec's requirement, unqualified). Added a
  `## Sources` entry for the `anthropics/claude-code#29787` postmortem REQ-B1.1 already cited
  (pre-existing gap, not introduced this session). Struck "nudge" from every enumeration of daemon
  action types (Goal, D-15, D-16, REQ-F1.1, REQ-F1.3, REQ-F1.4, REQ-G1.2, Task 8's Deliverables,
  test-spec.md's REQ-F1.4 entry) — surfaced by the sign-off lens pass: nudge was never defined by
  any REQ or task, and the one place it was discussed concretely (D-2) explicitly rejected
  automatic nudging. Cleanup, restart, and throttle remain as the three real daemon-action types
  throughout; REQ-A1.3's and D-2's own "SHALL NOT be resolved by an automatic nudge" language
  stays, since it explains a rejected alternative rather than asserting a shipped mechanism.
- 2026-07-15 — Post-PR CI fix: `design.md`'s pre-existing origin-tag legend had a placeholder
  split across two code spans, leaving part of it bare and tripping markdownlint's
  `MD033/no-inline-html` rule (the bare part read as an HTML-like tag). Fixed by widening the code
  span to cover the whole placeholder in one span, matching the safe pattern already used in
  `kickoff-lifecycle/design.md`.
  Pre-existing from the original draft, not introduced by the kickoff walkthrough; caught by CI
  after the PR was opened, not by the sign-off lens pass (which reviews doctrine/content, not
  markdownlint rules).
- 2026-07-17 — Task 7 implementation (expression-only): extended Task 7's `Done when` in
  `tasks.md` with the throttle-audit acceptance criterion ("throttle-engagement events log through
  Task 1's audit-trail helper") and added D-16 · REQ-F1.4 to its `Citations:` — the gap-fill the
  signed-off kickoff risk row 30 explicitly directs the implementation to make ("an accepted risk
  with no acceptance criterion can silently ship unmitigated"), consistent with Tasks 2–4's
  existing audit-trail Done-when pattern; no accepted decision contradicted, no REQ meaning
  altered.

- 2026-07-15 — Migrated to format-version 2 (invariant-tasks D-10, REQ-D1.3;
  one-shot `scripts/migrate-format-version.sh` run): placement sections
  collapsed into a single `## Tasks` section, state annotation bullets
  stripped, stored header restricted to the human-gated set, the
  `**Execution:**` pointer line added, `Format-version:` bumped to 2 on
  all four files. Task definition lines are preserved byte-for-byte (the
  canonical `tasks.md` extraction digest is unchanged), so the required
  re-anchor rides as expression-only: the kickoff brief's self-re-anchor
  entry cites this entry.

- 2026-07-17 — Task 3 execution (expression-only, riding the Task 3 PR):
  extended `tasks.md` Task 3's `Done when` with the overlapping-invocation
  guard criterion (relaunch serializes on the existing per-spec advisory
  lock D-20 and re-verifies positive evidence of death under it before
  acting). This is the gap-fill the kickoff risk register's row 1 sign-off
  note explicitly directed ("Task 3's implementation should extend its own
  Done-when to cover it") — an accepted-risk mitigation already decided at
  sign-off, given an acceptance criterion so it cannot silently ship
  unmitigated; no requirement, design decision, or test semantics changed.

- 2026-07-17 — Delta re-walkthrough reconciling re-anchor (expression-only):
  reconciled the kickoff brief's content anchor after Tasks 3 and 7's parallel
  task-PR merges (#217 and #213) left the amendment log's file-last anchor entry
  (Task 7's) computed on a branch that predated Task 3's merged changes, staling
  the freshness gate against combined main. No new content change: the
  underlying edits (Task 3's `Done when` overlapping-invocation guard and the
  D-4/REQ-G1.2-aligning scheduling reword from "Claude Code scheduled-agent
  primitive" to a deterministic operator-scheduled cron/launchd script) already
  merged and are recorded above. This entry re-anchors the brief to current main
  so dispatch of the next ready task (Task 8) is unblocked; no accepted decision
  contradicted, no REQ meaning altered.

- 2026-07-20 — Resource-governance extension (`/spec-draft` extend mode, delta at Status Draft;
  reopen cycle REQ-A3.1 flips stored Ready → Draft on all four headers). Two coupled dimensions
  added to `REQ-E`: (1) a proactive, shared-aware usage gate — REQ-E1.5 (parse `/usage`), REQ-E1.6
  (configurable budget-threshold dispatch gate), superseding REQ-E1.3 with REQ-E1.7 (reactive
  throttle retained as the hard backstop, premise dropped); (2) configurable budget-aware model
  allocation — REQ-E1.8 (overlay-configurable, default-preserving selection policy), REQ-E1.9
  (per-model budget caps/shares), REQ-E1.10 (capability-not-safety degrade ladder). Design adds
  D-23 (proactive `/usage` read, superseding D-12), D-24 (configurable budget-aware allocation,
  extending D-11), D-25 (degrade-capability-not-safety ladder), and D-26 (the altitude record:
  this extension lands as configurable mechanism, not new doctrine, cited from the Goal). Tasks 9
  and 10 appended; test-spec pins REQ-E1.5–E1.10; the `ccusage` Deferred entry updated to note the
  proactive gate now covers its "reactive fires too late" gate. The proactive gate is framed as a
  throttle-family daemon action (a proactive dispatch pause) and each degrade step as an audited,
  kill-switchable daemon action, so REQ-F1.3/REQ-F1.4's universal "every daemon action this spec
  introduces" coverage extends to both without minting a fourth daemon-action *type* — the
  "cleanup, restart, throttle" set established on 2026-07-15 stands. Seeds: obs:5d6d206c
  (proactive-shared-usage-governance) and obs:9af1f82f (configurable-model-allocation).

## Sources

- **The `fleet-autonomy` drafting session** (2026-07-14) — the full elicitation: the original
  free-form idea, the fold-detection pass against `orchestration-fleet`/`orchestration-concurrency`
  (both Done), the multi-agent prior-art research (process supervision, the Claude-Code-fleet-
  tooling ecosystem, LLM cost governance), and the live spikes/verifications against Claude Code's
  own documentation (`--resume`/`--continue`, the `SessionStart` hook `source` field, the full
  hook-event list, `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`, the `statusLine` feature, and the
  `auto` permission mode).
- **The ghost-text-disambiguation observation** — `specs/_observations/opportunities.md`, the
  2026-07-09 entry "fleet-relay gap (ghost text)" (consumed): an orchestrator reading a worker
  window cannot distinguish real typed input from Claude Code ghost suggestions without a positive
  disambiguation protocol. Superseded in this bundle's design by prevention-at-dispatch
  (REQ-D1.1) rather than the entry's own proposed detection protocol.
- **The context-budget premise-challenge observation** — `specs/_observations/opportunities.md`,
  the 2026-07-09 entry "context-budget premise challenge" (consumed): a peer window running
  `/context` and capture-paning the output offers direct measurement, capability-gated, with the
  step-count proxy retained as the portable fallback.
- **The doctrine-gap(tower-role) observation** — `specs/_observations/opportunities.md`, the
  2026-07-10 entry (consumed): the orchestrate/fleet doctrine never states that a tower does not
  author repo/config/content changes itself, surfaced when a tower directly reversed a
  rationale-documented decision instead of routing it as a fork.
- **orchestration-fleet** (Done) — the backend capability contract, the context-budget monitor
  and auto-heal handover, the attention/notification capability, meta-orchestration, and the
  inter-orchestrator relay protocol, consumed as authoritative and extended, not redefined.
- **orchestration-concurrency** (Done) — the derived-projection state model and the per-spec
  advisory lock, consumed as authoritative.
- **customization-overlay** (Done) — the four-layer overlay mechanism every knob in this bundle
  resolves through.
- **The `review-gauntlet` pending seed** — `specs/_pending/review-gauntlet.md`, written during
  this drafting session (2026-07-14): the post-PR review-gauntlet chaining and task-PR-ready-
  marking concerns scoped out of this bundle as a different decision domain.
- **The `anthropics/claude-code#29787` self-termination postmortem** — a real, documented incident
  where LLM-driven cleanup reasoning non-deterministically issued `tmux kill-session` against its
  own hosting pane, destroying the entire session. Consumed as the motivating precedent for
  REQ-B1.1's self-targeting guard and D-6's deterministic-script-only cleanup decision.
- **The proactive-shared-usage-governance observation** — `obs:5d6d206c`
  (`2026-07-20-proactive-shared-usage-governance-5d6d206c`): planwright's usage governance is
  reactive only; `fleet-throttle.sh` (D-12) waits until a session hits the rate limit before
  pausing, on a "no machine-readable usage query" premise that is now stale because `/usage` is
  capturable and parseable. Because `/usage` is account-global the read is inherently shared-aware.
  Frames REQ-E1.5–E1.7 and D-23. Recorded on the chore branch of PR #275 (not yet merged to
  `main`); the fragment's archive-move consumption is therefore deferred until #275 lands, at which
  point it should be consumed to this spec via `scripts/obs-consume.sh --uid 5d6d206c --spec
  fleet-autonomy` (the `obs:` citation is stable across the move).
- **The configurable-model-allocation observation** — `obs:9af1f82f`
  (`2026-07-20-configurable-model-allocation-9af1f82f`): `fleet-resource-select.sh` resolves a
  unit's model/effort but the policy is not operator-configurable for smart, budget-aware
  allocation; the operator wants per-task model by complexity, per-model budget caps/shares, and a
  degrade-to-cheaper ladder driven by the proactive usage gate, all configurable through the config
  layers, degrading capability never safety. Frames REQ-E1.8–E1.10 and D-24/D-25. Also recorded on
  PR #275 (not yet merged); consumption deferred identically, via `scripts/obs-consume.sh --uid
  9af1f82f --spec fleet-autonomy` once #275 lands.
