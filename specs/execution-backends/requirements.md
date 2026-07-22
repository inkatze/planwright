# Execution Backends — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-22
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's rich fleet capabilities — observe-in-flight, steer-in-flight, session-grade,
human-attachable — are today delivered by exactly one backend: `tmux`. The backend capability
contract (orchestration-fleet, `doctrine/backend-capability-contract.md`) made the seam pluggable,
but every shipped non-tmux rung sacrifices session grade or observability, so execution *and*
observation stay coupled to one substrate and one operator persona. Verified research against the
installed CLI (v2.1.217; summarized in the primary seed, obs:3414579b) proved a stream-json worker
is the same binary, same harness, and full session grade — SessionStart hooks fire under `-p`, the
`session_id` persists, `--resume` recovers, and the event stream carries structured observe and
steer surfaces — and that `claude agents --json` is an authoritative busy/blocked oracle even for
the existing tmux fleet. This spec extends the contract and registry with the verified backend
rungs, pins the task-execution backend as an operator-default config knob (default: full-session;
never per-task auto-picked or prompted), adds an on-demand offload command whose adaptive
selection is governed by the tower-frugality and smallest-sufficient-rung axioms (altitude: D-1),
and gives non-tmux operators a backend-agnostic worker status view.

## Scope

### In scope

- Contract extension in `doctrine/backend-capability-contract.md`: two new backend values —
  `headless-oneshot` (`claude -p` one-shot) and `stream-json-persistent` — with advertised sets;
  new advertised properties `overhead` and `hook_registration`; correction of the `subagent` row
  (steerable via resume-with-context, still not session-grade); explicit non-`--bare` launch
  pinning; back-compatible adapter-grammar growth.
- The task-execution backend as an operator-default config knob (default `full-session`),
  overridable globally and per-spec; no per-task auto-selection, no per-task prompts.
- A standalone on-demand `/offload` skill for ad-hoc petitions; adaptive backend selection lives
  only there, governed by the two work-placement axioms recorded as doctrine.
- A backend-agnostic worker status view sourced from `claude agents --json`, the stream-json
  event stream, and the attention store — phased: the CLI table first, then a rendered
  dashboard for non-terminal operators as planned follow-on work (Task 8).
- The stream-json harness contract: `can_use_tool` receipt coupled to a decision-queue item plus a
  pending-age alarm; AskUserQuestion↔decision-queue 1:1 mapping; `--resume` recovery.
- The `claude agents --json` idle-oracle quick win for the existing tmux fleet, dispatched first.

### Out of scope

- Model/effort allocation and budget-aware model degradation (fleet-autonomy's axis).
- Cross-tower coordination (concurrent-orchestrator-coordination; this spec shares only the
  dispatch layer).
- Agent Teams adoption (experimental: one team per session, no resumption — watch, do not adopt).
- SDK-as-library drivers (subscription-auth terms unsettled — drive the installed CLI; D-4).
- Per-task automatic backend selection for spec tasks (operator-rejected in the primary seed).
- Replacing or deprecating the tmux rung (it stays first-class).
- The machine-local-config-in-worktrees resolution gap (recorded as a risk; owned by config
  territory, not this bundle).

## REQ-A — Backend capability contract & registry extension

- **REQ-A1.1** The capability contract SHALL gain two advertised properties — `overhead` (the
  backend's fixed per-dispatch cost class) and `hook_registration` (whether the backend can
  register for and receive hook pushes) — each with an evaluable yes/no (or enumerated) definition.
  *(Cites: D-6, D-7, obs:4dc16740, obs:3414579b.)*
- **REQ-A1.2** The contract SHALL define `headless-oneshot` (`claude -p` one-shot) as a backend
  value with this pinned advertised set: `interactive: false`, `can_observe: false`,
  `can_steer_inflight: false`, `provides_attention_surface: false`, `supports_parallel: true`,
  session-grade **yes** (a detached non-`--bare` one-shot has its own full context window and
  harness, commits as principal, survives the tower, and its session persists and is
  resumable), `hook_registration: true`, `overhead: full-session`.
  *(Cites: D-3, obs:3414579b, kickoff lens pass (2026-07-22).)*
- **REQ-A1.3** The contract SHALL define `stream-json-persistent` as a session-grade backend
  value: same binary and harness (SessionStart hooks fire under `-p`), persistent `session_id`,
  `--resume` recovery, structured observe (event stream) and steer (message-in) surfaces, with
  this pinned advertised set: `interactive: false`, `can_observe: true`,
  `can_steer_inflight: true`, `provides_attention_surface: false`, `supports_parallel: true`,
  session-grade **yes** (as *recoverable*, per D-5), `hook_registration: true`,
  `overhead: full-session+supervisor`.
  *(Cites: D-4, D-5, obs:3414579b, kickoff lens pass (2026-07-22).)*
- **REQ-A1.4** The `subagent` row SHALL record that a subagent is steerable via
  resume-with-context while remaining not session-grade (it dies with the tower).
  *(Cites: obs:3414579b, drafting-session decision (2026-07-21).)*
- **REQ-A1.5** Every headless and stream-json launch invocation planwright emits SHALL pin
  non-`--bare` behavior explicitly, so a future CLI default flip cannot silently change worker
  harness surface. *(Cites: D-12, obs:3414579b.)*
- **REQ-A1.6** The contract table and the machine-readable advertisement source
  (`scripts/orchestrate-backends.sh`) SHALL be extended in lockstep, with the drift between them
  guarded by an automated check. *(Cites: D-2, D-13.)*
- **REQ-A1.7** The pluggable-adapter `advertise` line grammar SHALL grow to carry the new fields
  back-compatibly: a legacy six-field line remains valid with fail-safe defaults, any other
  arity (seven, nine or more) is malformed, and a malformed line SHALL fail closed with a
  visible diagnostic, never a silent absence. *(Cites: D-13.)*
- **REQ-A1.8** The contract SHALL pin the degradation-ladder ordering with the new rows,
  richest to safest — `tmux` > `stream-json-persistent` > `headless-oneshot` > `subagent` >
  `print`/`in-session` — and SHALL pin the `overhead` enum to the classes `none` | `light` |
  `full-session` | `full-session+supervisor`, with "most conservative" (the D-13 legacy
  default) defined as the highest class.
  *(Cites: D-6, D-8, kickoff lens pass (2026-07-22).)*
- **REQ-A1.9** Worker launch construction SHALL pass petitions, task prose, and any other
  untrusted text to workers as data (argv elements or stdin), never interpolated into a shell
  command line; adapter `advertise` lines SHALL be validated against the grammar,
  length-bounded, and stripped of non-printable bytes before any use or echo.
  *(Cites: D-13, kickoff lens pass (2026-07-22).)*

## REQ-B — Task-execution backend knob

- **REQ-B1.1** `dispatch_backend` SHALL gain the semantic value `full-session`, resolving at
  dispatch time to the richest session-grade backend advertised on the host via the degradation
  ladder (unattended: the richest *non-interactive* session-grade backend, per D-8 and
  REQ-B1.4; attended: a configured semantic value is the operator's standing answer — no
  re-ask except D-8's tmux-context ask, once per tower session, non-blocking — a declared
  narrowing of orchestration-fleet REQ-B1.4's attended present-and-ask), and the shipped
  default SHALL flip from `subagent` to `full-session` (a declared departure from the
  default-preserving rule, the departure operator-approved in the primary seed).
  *(Cites: D-8, obs:3414579b, kickoff lens pass (2026-07-22).)*
- **REQ-B1.2** Task-execution backend selection SHALL be operator-default only: no per-task
  auto-selection and no per-task prompts. *(Cites: obs:3414579b.)*
- **REQ-B1.3** The knob SHALL be overridable globally and per-spec, the per-spec override carried
  by a per-spec map in the config overlay layers. *(Cites: D-9, obs:3414579b.)*
- **REQ-B1.4** Backend degradation SHALL degrade capability, never safety, and unattended
  selection SHALL never silently resolve to an interactive backend (carrying forward
  orchestration-fleet REQ-B1.4's never-silently-interactive clause and orchestration-fleet
  REQ-B1.5/D-3's degrade-capability-never-safety rule). *(Cites: D-8, orchestration-fleet
  REQ-B1.4 (Sources).)*
- **REQ-B1.5** An explicitly configured `dispatch_backend` value (global or per-spec) that is
  not advertised on the host SHALL fail closed: the dispatch halts to Awaiting input naming the
  missing backend, never silently substituting another backend. Degradation ladders apply only
  to semantic values (`full-session`), never to explicit literals. This rule is
  **dispatch-time only** — a declared narrowing of orchestration-fleet REQ-B1.4's
  degrade-on-absence clause for explicit literals; mid-run runtime failover keeps
  orchestration-fleet REQ-B1.5's descend-one-rung-with-logged-note semantics.
  *(Cites: D-8, kickoff §3 (2026-07-22), kickoff lens pass (2026-07-22).)*

## REQ-C — The offload command

- **REQ-C1.1** A standalone `/offload` skill SHALL accept a free-form petition and dispatch it to
  a backend; adaptive backend selection SHALL exist only in this skill.
  *(Cites: D-1, obs:3414579b, drafting-session decision (2026-07-21).)*
- **REQ-C1.2** The tower-frugality axiom SHALL govern what stays inline: the tower does work
  inline only for pure reasoning over existing context and the operational heartbeat (bounded
  small-result state checks and reserved decision-maker actions — sub-1KB lookups are negative-ROI
  to offload, and decision-critical verification evidence stays first-hand); everything with large
  or unpredictable context ingestion SHALL offload. *(Cites: D-1, obs:3414579b.)*
- **REQ-C1.3** The smallest-sufficient-rung axiom SHALL govern rung choice: subagent unless the
  work must survive the tower, be human-attachable, or run beyond the session.
  *(Cites: D-1, obs:3414579b.)*
- **REQ-C1.4** When a petition under-determines the rung, `/offload` SHALL ask the operator and
  SHALL NOT silently guess; when the determined sufficient rung is not advertised on the host,
  `/offload` SHALL likewise ask — dispatch to an insufficient rung is never silent.
  *(Cites: D-1, obs:3414579b, kickoff lens pass (2026-07-22).)*
- **REQ-C1.5** `/offload` SHALL report the dispatched worker's handle and how to observe or attach
  to it (as advertised by the selected backend; a rung with no observe surface reports that
  fact), and a failed dispatch SHALL be reported with its failure, never silently dropped.
  *(Cites: drafting-session decision (2026-07-21), kickoff lens pass (2026-07-22).)*

## REQ-D — Backend-agnostic status view

- **REQ-D1.1** A backend-agnostic CLI status view SHALL render every in-flight worker regardless
  of backend, sourced from `claude agents --json`, the stream-json event stream, and the attention
  store, degrading gracefully when any source is absent. Workers on backends with no runtime
  presence (`print`) render from dispatch records or a visible not-applicable marker, never a
  silent omission; worker-authored strings pass the echo-safety discipline before terminal
  rendering. *(Cites: D-10, obs:3414579b, kickoff lens pass (2026-07-22).)*
- **REQ-D1.2** A rendered dashboard SHALL present the same merged worker state as the CLI view
  as a glanceable browser/phone surface for non-terminal operators, reusing the CLI renderer's
  source-merging layer rather than a second source-reading implementation. The dashboard SHALL
  be read-only, SHALL NOT be exposed on an unauthenticated network surface (the exposure
  mechanism is decided at Task 8), and SHALL encode worker-authored strings for HTML output.
  *(Cites: D-10, drafting-session decision (2026-07-21), kickoff lens pass (2026-07-22).)*

## REQ-E — Stream-json harness contract

- **REQ-E1.1** The stream-json supervisor SHALL couple every `can_use_tool` control_request
  receipt to a decision-queue item plus a pending-age alarm; no permission request may pend
  unobserved (the verified indefinite-pend gotcha). *(Cites: D-5, obs:3414579b.)*
- **REQ-E1.2** AskUserQuestion control_requests SHALL map 1:1 onto decision-queue items.
  *(Cites: D-5, obs:3414579b.)*
- **REQ-E1.3** Worker recovery SHALL use `--resume` against the persisted `session_id`.
  *(Cites: D-5, obs:3414579b.)*
- **REQ-E1.4** The supervisor SHALL deliver the operator's recorded answer for a queue item as
  the control_response to the pending control_request; an answer that can no longer be
  delivered (dead channel, request re-issued or gone after recovery) SHALL be surfaced to the
  operator, never silently dropped and never silently re-applied to a different request.
  *(Cites: D-5, kickoff lens pass (2026-07-22).)*
- **REQ-E1.5** The no-pend-unobserved guarantee SHALL hold across supervisor crash and resume
  windows: receipt state SHALL be durable, pending-age alarms SHALL be re-armed on recovery,
  duplicate delivery SHALL be deduplicated on request identity for both control_request types,
  recovery SHALL have a single initiator that checks the orphaned worker's liveness before
  `--resume`, and a failed `--resume` SHALL surface as a halt, never a silent loss.
  *(Cites: D-5, kickoff lens pass (2026-07-22).)*

## REQ-F — Idle oracle

- **REQ-F1.1** Fleet idle/busy detection SHALL treat `claude agents --json` as the authoritative
  busy/blocked oracle when available, demoting pane-scrape heuristics to fallback-only. A probe
  that exits non-zero, hangs past its bounded timeout, or returns unparseable output SHALL be
  treated as oracle-unavailable (fallback engages), never as an empty fleet; absence of a
  tracked worker from oracle output is not positive evidence of death.
  *(Cites: D-11, obs:3414579b, kickoff lens pass (2026-07-22).)*

## Changelog

- 2026-07-21 — Bundle drafted by `/spec-draft` (Status Draft). Fold verdict: new bundle amending
  `doctrine/backend-capability-contract.md`, citing orchestration-fleet as the extended base;
  supersedes the empty `planwright/background-agent-backend/spec` branch stub. Seeds consumed:
  obs:3414579b, obs:4dc16740.
- 2026-07-21 — Pre-kickoff Draft amendment (operator decision, relayed from the tower): the
  rendered dashboard promoted from a Deferred gate to planned Task 8 (dependency on Task 7,
  reusing its source-merging layer), because the operator's away-workflow is phone/browser-based
  and the dashboard is planned work, not a contingency. Adds REQ-D1.2; D-10 amended in place;
  the Deferred gate entry converted to a promotion note.
- 2026-07-22 — Kickoff walkthrough edits (Draft, pre-sign-off, operator-decided): D-8 amended
  in place (attended-resolution ask pinned to tmux-context detection; explicit-but-unavailable
  fail-closed rule); REQ-B1.5 added with a test-spec entry and Task 5 coverage; D-5 clarified
  (decision-queue = the existing attention store, no new surface); test-spec coverage-mix intro
  updated for the third `[manual]` entry the Task 8 promotion added (expression-only).
- 2026-07-22 — Kickoff sign-off lens-pass edits (meaning-class, operator-dispositioned):
  advertised sets pinned for both new rows and `headless-oneshot` classified session-grade
  (matching the contract's evaluable definition and its headless-pool example); ladder
  ordering and the `overhead` enum pinned (REQ-A1.8); launch/advertise input hygiene
  (REQ-A1.9); attended configured-standing-answer narrowing and dispatch-time-only fail-closed
  scope recorded as declared narrowings of orchestration-fleet REQ-B1.4/B1.5 (REQ-B1.1,
  REQ-B1.5, D-8); the tmux-context ask defined (once per tower session, non-blocking,
  spec-local ask-state); REQ-E1.4 (answer delivery) and REQ-E1.5 (crash-window invariants)
  added; render/capture/dashboard security clauses (REQ-D1.1, REQ-D1.2, Task 4); offload
  unavailable-rung ask and failure reporting (REQ-C1.4, REQ-C1.5); oracle failure semantics
  (REQ-F1.1); citation and wording corrections (D-1 quote scope, knob provenance,
  orchestration-fleet REQ-B1.5 attribution, Task 2 citations gain D-5, test-spec guard-wording
  honesty, REQ-A1.4 tag, GATE-token defused in the promotion note, worktree-gap obs UIDs).

## Sources

- **obs:3414579b** — the operator-scoped execution-backends observation (2026-07-21): the full
  approved scope (contract extension, operator-default knob, offload command with the two axioms,
  status view), the verified stream-json research findings (CLI v2.1.217), and the risk/watch
  items (`--bare` default risk, Agent Teams not ready, SDK auth terms unsettled). Primary seed;
  consumed 2026-07-21.
- **obs:4dc16740** — backend-hook-capability fragment (2026-07-17): the contract lacks a
  `hook_registration` field, forcing `fleet-liveness.sh` to key hook-push support by backend name.
  Consumed 2026-07-21.
- **Pinned altitude claims** (autopilot-reflex seed-claim pinning, from obs:3414579b): (1)
  "planwright hard-codes tmux as both execution and observation substrate" — a first-class
  substrate concern; (2) the tower-frugality and smallest-sufficient-rung selection rules are
  stated as *axioms* — doctrine-grade rules, not skill mechanics. Both resolved by D-1.
- **orchestration-fleet** (`specs/orchestration-fleet/`, Done) — owner of the backend seam this
  bundle extends: the capability contract, advertisement, the degradation ladder, and the
  extension of the `dispatch_backend` knob (the knob itself was minted by bootstrap D-38 /
  REQ-F1.8; orchestration-fleet extends it). Foreign IDs cited from it are namespace-qualified.
- **orchestration-fleet REQ-B1.4** — the never-silently-interactive unattended-selection
  invariant, carried forward by REQ-B1.4 of this bundle.
- **fleet-autonomy** (`specs/fleet-autonomy/`, Ready) — sibling owner of the model/effort axis;
  named here to record the boundary, not extended.
- **Worktree config-layer gap** (recorded observations obs:65fea955, obs:fd4c2ad6,
  2026-07-15/2026-07-20, unconsumed): the
  machine-local overlay does not propagate to task worktrees, so a machine-local
  `dispatch_backend` value may not reach workers. Cited as a risk for the kickoff risk register;
  the fix is config territory, out of scope here.
- **Drafting-session decisions (2026-07-21)** — the four elicitation forks: standalone `/offload`
  skill; phased CLI-first status view (the dashboard phase subsequently promoted from a Deferred
  gate to planned Task 8 by operator decision the same day — see Changelog); idle oracle as
  Task 1 with no dependencies; `full-session` as a semantic value on the existing
  `dispatch_backend` knob with the default flipped.
