# Execution Backends — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-22
**Format-version:** 2
**Execution:** derived — see the status render

Task 1 carries no dependencies by design (drafting-session decision, 2026-07-21): the idle
oracle is the highest-value, lowest-risk unit and protects the existing tmux fleet, so it
dispatches ahead of the contract work. Task 2 is the hub the backend work fans out from; the
critical path is 2 → 4 → 7 → 8 (derived from the `Dependencies:` lines; render via
`scripts/spec-graph.sh`).

## Tasks

### Task 1 — agents-json idle oracle

- **Deliverables:** `fleet-liveness.sh` consults `claude agents --json` as the primary
  busy/blocked evidence, capability-probed at call time, with pane-scrape heuristics demoted to
  fallback when the oracle is unavailable; shim-fixture tests extending
  `tests/test-fleet-liveness.sh`; a documented manual probe path against the running CLI.
- **Done when:** the liveness classify path prefers oracle evidence whenever the probe
  succeeds; a shim fixture demonstrates a pane-scrape false-idle case that the oracle corrects;
  the fallback path is exercised by a fixture with the oracle absent; the documented manual
  live-probe run is recorded in the task's PR; the full check suite is green.
- **Dependencies:** none
- **Citations:** D-11 · REQ-F1.1
- **Estimated effort:** 1 day

### Task 2 — capability contract & registry extension

- **Deliverables:** `doctrine/backend-capability-contract.md` amended in place: `overhead` and
  `hook_registration` advertised properties with evaluable definitions; `headless-oneshot` and
  `stream-json-persistent` rows with advertised sets; the `subagent` row corrected
  (steer-via-resume-with-context, not session-grade); the session-grade-as-recoverable nuance
  recorded on the stream-json row and in the session-grade evaluable definition itself; the
  pinned advertised sets for both new rows, the pinned ladder ordering, and the pinned
  `overhead` enum (REQ-A1.8); the non-`--bare` pinning rule; the 6→8-field back-compatible
  adapter grammar with visible malformed-line diagnosis and advertise-line input hygiene
  (REQ-A1.9). `scripts/orchestrate-backends.sh` extended in lockstep;
  `docs/options-reference.md` and `docs/fleet.md` backend rows updated; drift-guard and
  adapter-grammar tests (legacy six-field acceptance, malformed fail-closed).
- **Done when:** the contract doc and `orchestrate-backends.sh` agree under the drift guard for
  all rows and fields; adapter-grammar fixtures pass for eight-field, legacy six-field, and
  malformed lines; `fleet-liveness.sh` push-capable reads `hook_registration` from the contract
  instead of backend names; the full check suite is green.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-5, D-6, D-7, D-12, D-13 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-A1.9
- **Estimated effort:** 2 days

### Task 3 — headless-oneshot dispatch support

- **Deliverables:** dispatch support for `headless-oneshot`: detached `claude -p` launch with
  non-`--bare` pinned, launch construction passing prompt and task text as data (REQ-A1.9), a
  completion signal the tower can consume, the one-shot permission posture defined (no pend
  path: one-shots never attach a stdio permission-prompt tool, so an unauthorized ask fails
  under `-p`'s non-interactive default — visible in the worker's result and completion signal,
  never a pend), and liveness wiring per the advertised set; launch-pin guard coverage
  extended; fixture tests.
- **Done when:** a dispatched unit launches detached with the pinned flags, its completion is
  observable by the tower, its liveness answers positive-evidence-of-death, and the launch-pin
  guard rejects an unpinned launch site; the full check suite is green.
- **Dependencies:** 2
- **Citations:** D-3, D-12 · REQ-A1.2, REQ-A1.5, REQ-A1.9
- **Estimated effort:** 1 day

### Task 4 — stream-json-persistent backend

- **Deliverables:** the stream-json supervisor primitive: worker launch (non-`--bare` pinned,
  prompt and task text passed as data per REQ-A1.9), stdio ownership, event-stream capture (in
  a gitignored location outside committed paths, named in the secret-scan surface),
  `can_use_tool` receipt coupled to a decision-queue item plus a pending-age alarm,
  AskUserQuestion↔decision-queue 1:1 mapping, answer delivery per REQ-E1.4, the crash-window
  invariants per REQ-E1.5, and `--resume` recovery against the persisted `session_id`;
  completion and liveness for this backend surfaced from the supervisor and event stream (its
  completion/liveness source, the sibling of Task 3's completion signal);
  shim-fixture tests for each contract clause and a documented manual end-to-end resume probe.
- **Done when:** fixtures demonstrate a `can_use_tool` receipt producing a queue item and the
  alarm firing past the pending threshold; an AskUserQuestion control_request maps to exactly one
  queue item; a killed-supervisor fixture recovers the session via `--resume`; no code path
  auto-answers a permission control_request; the documented manual resume probe is recorded in
  the task's PR; the full check suite is green.
- **Dependencies:** 2
- **Citations:** D-4, D-5 · REQ-A1.3, REQ-A1.9, REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4,
  REQ-E1.5
- **Estimated effort:** 3 days

### Task 5 — full-session knob and default flip

- **Deliverables:** the `full-session` semantic value on `dispatch_backend` with
  non-interactive-first unattended resolution; the shipped default flipped
  `subagent`→`full-session` with a migration note; the per-spec override map resolved through
  the config overlay layers; degradation-ladder wiring from the pinned ordering (REQ-A1.8);
  the tmux-context ask-state persisted in the spec-local runtime dir; docs (options-reference,
  fleet) and resolver fixtures.
- **Done when:** resolution fixtures cover the unattended matrix (never an interactive backend
  without explicit config), the tmux-context attended ask (including re-ask suppression within
  one tower session and the unanswered arm) and the explicit-but-unavailable fail-closed halt
  are fixture-covered, the per-spec map wins over the global value in every layer combination,
  the default flip is documented with its declared-departure rationale, and the full check
  suite (including the options-reference guard) is green.
- **Dependencies:** 2, 4
- **Citations:** D-8, D-9 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5
- **Estimated effort:** 1 day

### Task 6 — work-placement doctrine and /offload skill

- **Deliverables:** `doctrine/work-placement.md` recording the tower-frugality and
  smallest-sufficient-rung axioms; the standalone `/offload` skill (free-form petition → rung
  selection per the axioms, ask-when-unsure, dispatch through the backend seam, report the
  handle plus an observe/attach hint); structural guard coverage and instruction-budget
  compliance for the new skill; a Gherkin scenario for the under-determined-petition ask.
- **Done when:** the doctrine doc exists and the skill cites it; the skill passes the structural
  skill guards and `check:instructions`; the offload dispatch primitive's report carries handle
  and attach hint under a fixture; the ask-when-unsure scenario is recorded in the bundle's
  test-spec form; the full check suite is green.
- **Dependencies:** 2
- **Citations:** D-1 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5
- **Estimated effort:** 2 days

### Task 7 — backend-agnostic CLI status view

- **Deliverables:** a CLI status renderer listing every in-flight worker across backends,
  sourced from `claude agents --json`, the stream-json event stream, and the attention store,
  with per-source graceful degrade and worker-authored strings passed through the echo-safety
  discipline; fixture tests covering the source present/absent matrix; docs.
- **Done when:** the renderer produces a correct table under fixtures for each cell of the
  source-availability matrix, a missing source degrades with a visible marker rather than a
  silent omission, and the full check suite is green.
- **Dependencies:** 1, 4
- **Citations:** D-10 · REQ-D1.1
- **Estimated effort:** 1 day

### Task 8 — rendered status dashboard

- **Deliverables:** a rendered dashboard (browser/phone-glanceable) presenting the merged
  worker state for non-terminal operators, reusing Task 7's source-merging layer
  (`claude agents --json` + the stream-json event stream + the attention store) rather than a
  second source-reading implementation; read-only, no unauthenticated network exposure (the
  exposure mechanism decided in this task), worker-authored strings HTML-encoded; render
  fixtures covering the source-availability matrix; docs.
- **Done when:** the dashboard renders the same source-availability matrix as the CLI view from
  the shared merge layer; a missing source shows a visible marker rather than a silent
  omission; render output is verified by fixture; a manual phone/browser glance check is
  documented in the task's PR; the full check suite is green.
- **Dependencies:** 7
- **Citations:** D-10 · REQ-D1.2
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

- **Rendered status dashboard — promoted.** The original Draft carried this as a gated deferral
  (gate condition: "the CLI view proves insufficient"); promoted to Task 8 as planned work by
  operator decision (2026-07-21): the operator's away-workflow is phone/browser-based, so the
  dashboard is not a contingency. Recorded here so the promotion is visible; no gate remains.

## Out of scope

- Model/effort allocation and budget-aware model degradation — fleet-autonomy's axis.
- Cross-tower coordination — concurrent-orchestrator-coordination owns it; this bundle shares
  only the dispatch layer.
- Agent Teams adoption — experimental (one team per session, no resumption); watch, do not
  adopt.
- SDK-as-library drivers — subscription-auth terms unsettled; drive the installed CLI (D-4).
- Per-task automatic backend selection for spec tasks — operator-rejected in the primary seed.
- Replacing or deprecating the tmux rung — it stays first-class.
- The machine-local-config-in-worktrees resolution gap — recorded as a risk; owned by config
  territory.
