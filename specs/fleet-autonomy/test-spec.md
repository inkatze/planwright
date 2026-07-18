# Fleet Autonomy — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since the no-LLM-daemon-mechanics floor (REQ-G1.2) makes
nearly every mechanism in this bundle deterministic script logic, which is straightforwardly
fixture-testable — including negative assertions that no LLM/API call fires during a daemon
mechanism's resolution. `[manual]` is reserved for the small set of behaviors whose real signal is
either inherently visual (the `statusLine` rendering), depends on a live integration this bundle
doesn't fully control (an actual host crash and Claude Code relaunch, live `/context` UI-text
parsing against a real session), or concerns an agent's judgment under a doctrine instruction
rather than a mechanism's output (the tower non-authoring boundary).

## REQ-A — Liveness & recovery

### REQ-A1.1 — Hook-pushed worker liveness [test]

A fixture worker session with stubbed hook registrations for `Stop`, `PermissionRequest`, the
`PostToolUse` following a pending `PermissionRequest`, `SessionEnd`, and `StopFailure` asserts the
shared state store updates within one event cycle of each stub firing, never waiting for a tower
poll cycle. A second fixture on a backend without hook-registration support asserts the mechanism
falls back to capture-pane observation rather than failing.

### REQ-A1.2 — Five-state classification [test]

Unit tests feed synthetic heartbeat/progress sequences and assert the classifier resolves exactly
one of `working`/`idle`/`hung`/`awaiting-human`/`flailing` per sequence, including the boundary
between `hung` (heartbeat stopped) and `flailing` (heartbeat continues, no forward progress).

### REQ-A1.3 — Flailing escalates, never auto-resolved [test]

A fixture sequence classified `flailing` asserts exactly one decision-queue entry is created and
asserts no restart or nudge call is issued by the classifier.

### REQ-A1.4 — Crash-loop backoff and disable threshold [test]

A fixture injecting repeated worker crashes asserts the relaunch delay follows the configured
escalating schedule and asserts the worker is disabled (no further relaunch attempted) once the
configured consecutive-failure threshold is reached, with a decision-queue entry recording the
disable.

### REQ-A1.5 — Unattended tower-liveness watchdog [test + manual]

`[test]`: a fixture simulating a dead tower process plus ready work asserts the cron-triggered
check launches a fresh tower using only durable disk state (the snapshot test: the fixture asserts
no in-memory state is passed to the relaunch). `[manual]`: a periodic manual exercise confirms the
operator-scheduled cron/launchd entry actually fires the check on a live host, since real-world
scheduler timing is outside what a fixture can assert.

### REQ-A1.6 — Interactive tower crash-recovery signpost [test + manual]

`[test]`: a fixture simulating a `SessionStart` event with `source: "startup"` and an orphaned
interactive-tower marker asserts the surfaced message names the exact `claude --resume <id>`
command and asserts no auto-resume or auto-discard of the marker occurs. `[manual]`: a real crash
(killed terminal) followed by a real Claude Code startup confirms the human actually sees the
message as intended.

### REQ-A1.7 — Positive-evidence-of-death as the shared predicate [test]

A fixture reproducing the `2026-06-12` dead-tmux-socket/truncated-process-listing scenario asserts
the shared predicate refuses to report death from ambiguous or lost-observability signal alone,
and a second fixture with a clean, positive death signal asserts it correctly reports death.

### REQ-A1.8 — Reconcile-from-ground-truth backstop for missed pushes [test]

A fixture that deliberately drops a push event (simulating a failed hook execution) asserts the
next periodic reconcile sweep (Task 4) corrects the resulting state drift without a second push.

### REQ-A1.9 — Tower crash-loop backoff and disable threshold [test]

A fixture injecting repeated tower-relaunch failures (the cron watchdog relaunches a fresh tower
that immediately dies again) asserts the relaunch delay follows the same escalating schedule as
REQ-A1.4 and asserts the cron check stops relaunching (disables) once the configured
consecutive-failure threshold is reached, with a decision-queue entry recording the disable.

## REQ-B — Cleanup & housekeeping

### REQ-B1.1 — Deterministic cleanup with a self-targeting guard [test]

A fixture reproducing the `anthropics/claude-code#29787` scenario (a cleanup mechanism's target
resolving to its own hosting session) asserts the mechanism refuses to act, and a fixture with a
genuinely stale, non-self-hosting target asserts it acts correctly.

### REQ-B1.2 — Worktree lifecycle via `WorktreeCreate`/`WorktreeRemove` [test]

A fixture creating and then removing a worktree on a hook-supporting backend asserts both events
are tracked without a disk scan; a fixture on a backend without hook support asserts the fallback
disk-scan path is used instead.

### REQ-B1.3 — Dirty-tree sweep across every tracked working tree [test]

A fixture injecting a stale uncommitted/unpushed diff on a simulated tower's own checkout (not
just a worker worktree) asserts the periodic sweep detects it and escalates it to the decision
queue rather than leaving it unflagged.

## REQ-C — Context-budget corroboration

### REQ-C1.1 — Peer-pane `/context` corroboration [test + manual]

`[test]`: a fixture asserts the capability gate correctly reports the mechanism unavailable on a
backend without peer-pane support, and falls back to the step-count proxy. `[manual]`: a periodic
manual check against a real, live `/context` rendering confirms the parser still matches Claude
Code's current output format, since it is explicitly an unstable UI-text contract rather than a
stable API.

### REQ-C1.2 — Idle-only, graceful parse-failure degradation [test]

A fixture attempting the check against a busy session asserts it is skipped, not attempted; a
fixture feeding a malformed/unexpected `/context` rendering asserts a warning is emitted and the
step-count proxy is used, with no opaque halt.

## REQ-D — Relay hygiene

### REQ-D1.1 — Ghost-text prevention via environment variable [test]

A fixture launching a worker and a fixture launching a tower under meta-tower observation both
assert `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` is present in the launched process's
environment.

### REQ-D1.2 — Backspace-probe fallback stays documented, not required [design-level]

Verified by the existence of the Deferred entry (`tasks.md`) naming the gate condition and by
`docs/fleet.md` documenting the fallback; no required code path depends on it, checked by absence
of any non-test caller of the (unimplemented) probe.

## REQ-E — Resource governance

### REQ-E1.1 — Rule-based model/effort selection [test]

Fixtures across a representative set of task types assert the heuristic table resolves a
model/effort choice deterministically (same input, same output across repeated runs) and assert
no outbound LLM/API call occurs during resolution (a stubbed client asserts zero invocations).

### REQ-E1.2 — Rule-based command selection, disjoint from `review_sequence` [test]

A cross-check test asserts the heuristic's selectable command set and `resolve-review-sequence.sh`'s
nestable-skill set are disjoint, so the two mechanisms can never both claim the same skill.

### REQ-E1.3 — Reactive fleet-wide throttling [test]

A fixture simulating Claude Code's native rate-limit prompt/retry event asserts fleet-wide dispatch
pauses and asserts it resumes at the signaled reset time, with no dispatch attempted in between.

### REQ-E1.4 — Auto-mode guard [test]

A fixture attempting to launch a worker with `--permission-mode auto` asserts the guard refuses
the launch; a fixture launching with the standard worker-settings-profile allowlist asserts it
succeeds.

## REQ-F — Operator control & observability

### REQ-F1.1 — Derived, rendered fleet stats [test + design-level]

`[test]`: a fixture run of Tasks 2, 3, 4, and 7's mechanisms asserts the stats view's counters
reflect the real activity (including watchdog-trip count from Task 3 and throttle-engaged state
from Task 7). `[design-level]`: verified by absence of any new committed or shared-write file
introduced solely to hold stats (a repo-tree check).

### REQ-F1.2 — `statusline` notification channel [test + manual]

`[test]`: a fixture asserts `notification_channel: statusline` resolves through the overlay layers
and invokes the rendering function with the current stats. `[manual]`: a visual check confirms the
rendered line actually appears correctly at the bottom of a real Claude Code terminal.

### REQ-F1.3 — Operator kill-switch [test]

A fixture sets the kill-switch knob and asserts every daemon mechanism from Tasks 2–7 short-circuits
without acting; a fixture with the knob unset asserts normal operation.

### REQ-F1.4 — Audit trail for autonomous daemon actions [test]

A fixture triggers a daemon action (a cleanup, a restart, a throttle engagement) and
asserts a corresponding audit-trail entry exists, naming the trigger and reasoning, queryable by
mechanism and time range.

## REQ-G — Fleet coordination floor

### REQ-G1.1 — Tower non-authoring boundary [design-level + manual]

`[design-level]`: verified by the existence of the doctrine statement (Task 1) citing this
requirement. `[manual]`: a drill session presents a tower with a loose "can we just tweak this"
request against a rationale-documented decision and confirms it routes the request as a
Needs-human-judgment fork or delegates it as a worker chore, rather than editing directly —
reproducing and closing the `2026-07-10` incident this requirement was mined from.

### REQ-G1.2 — No-LLM-daemon-mechanics invariant [test + design-level]

`[test]`: for each daemon mechanism in Tasks 2–7, a fixture stubs the Anthropic client and asserts
zero invocations during the mechanism's execution. `[design-level]`: verified by the existence of
the doctrine statement (Task 1).

### REQ-G1.3 — Multi-tower coordination via the existing lock [test]

A concurrency fixture with two simulated towers asserts their daemon actions serialize through
`orchestration-concurrency`'s existing advisory lock, and asserts no new lock file or primitive is
created.

### REQ-G1.4 — Session-per-tower isolation [test]

A fixture asserts a fresh tower launch creates its own session/isolation unit and does not create
a window inside a pre-existing, unrelated tmux session.

### REQ-G1.5 — Every new knob resolves through the existing overlay mechanism [test]

A parametrized test over every config knob this bundle introduces asserts each resolves through
`config-get.sh` with the same four-layer precedence and by-layer malformed-value policy
`review_sequence` already has, and asserts `check-options-reference.sh` passes for each.

## Changelog

- 2026-07-14 — Initial draft.
- 2026-07-14 — Kickoff walkthrough: added the REQ-A1.9 entry (tower crash-loop backoff/disable).
