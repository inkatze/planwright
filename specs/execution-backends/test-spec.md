# Execution Backends — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]` via the repo's fixture-driven shell suites (drift guards,
resolver matrices, supervisor shims, launch-pin greps), all running under `mise run check` in CI.
`[manual]` is reserved for the two real-CLI end-to-end paths whose behavior is version-sensitive
(`--resume` recovery, the live agents-json oracle) and the dashboard's phone/browser glance
check, per the prefer-end-to-end validation posture.
One `[Gherkin]` scenario covers the ask-when-unsure dialogue. `[design-level]` is confined to
doctrine and skill prose whose existence-plus-coverage is the verification.

## REQ-A — Backend capability contract & registry extension

### REQ-A1.1 — overhead and hook_registration properties [test + design-level]

Design-level: the amended contract doc defines both properties with evaluable definitions.
Test: the doc-table ↔ `orchestrate-backends.sh` drift guard — a **new** doc-table parser added
to `tests/test-orchestrate-backends.sh` (the existing test hardcodes expected rows and reads
no doc) — parses all columns including the two new properties and asserts parity for every
row.

### REQ-A1.2 — headless-oneshot backend value [test]

`tests/test-orchestrate-backends.sh` asserts the advertised set answered for `headless-oneshot`
equals the values REQ-A1.2 pins (not merely doc↔script parity); Task 3's dispatch fixtures
verify detached launch, completion signal, and liveness behavior match the advertised set, and
a fixture asserts a permission ask in a one-shot fails visibly (no stdio prompt tool attached;
the failure lands in the result/completion signal) rather than pending.

### REQ-A1.3 — stream-json-persistent backend value [test]

`tests/test-orchestrate-backends.sh` asserts the advertised set answered for
`stream-json-persistent` equals the values REQ-A1.3 pins; Task 4's supervisor shim fixtures
verify the observe (event-stream capture) and steer (message-in) surfaces exist and the
session-grade-as-recoverable property holds (see REQ-E1.3).

### REQ-A1.4 — subagent row correction [test + design-level]

The amended contract doc records steer-via-resume-with-context on the `subagent` row while
keeping session-grade `no`; the drift guard covers the row's machine-readable mirror.

### REQ-A1.5 — non-bare launch pinning [test]

The launch-pin guard — a **new** `-p`-family suite added to `tests/test-dispatch-launch-pin.sh`
(which today covers ghost-text env pinning only, not launch-site greps) — greps every
`-p`-family launch site and fails on an unpinned invocation; a site-inventory assertion
(minimum expected match count) prevents a vacuous pass when discovery drifts; fixtures include
one deliberately-unpinned negative case.

### REQ-A1.6 — contract/registry lockstep [test]

The drift guard parses the contract doc's backend table (all rows, all fields, including the two
new properties) and asserts `orchestrate-backends.sh` answers identically; a seeded divergence
fixture fails the guard; an unparseable contract table fails the guard rather than passing on
an empty row set.

### REQ-A1.7 — back-compatible adapter grammar [test]

Adapter-grammar fixtures: an eight-field line parses fully; a legacy six-field line is accepted
with fail-safe defaults (`hook_registration=false`, most-conservative `overhead`); a
seven-field (and nine-or-more-field) line is malformed; a malformed line fails closed (backend
never selected), asserted by exit code, absence from the candidate set, and the visible
diagnostic REQ-A1.7 requires.

### REQ-A1.8 — pinned ladder ordering and overhead enum [test]

The drift guard asserts the contract records the pinned ladder ordering and the pinned
`overhead` enum values; Task 5's resolver fixtures consume the ordering (a fixture reorders
two rungs and the resolution result changes accordingly).

### REQ-A1.9 — launch and advertise input hygiene [test]

Launch-construction fixtures assert petition/task text reaches the worker as argv/stdin data —
a metacharacter fixture (`$(...)`, quotes, newlines) never reaches a shell interpolation.
Advertise-line fixtures assert length-bounding, non-printable stripping before echo, and
grammar validation before use.

## REQ-B — Task-execution backend knob

### REQ-B1.1 — full-session semantic value and default flip [test]

Resolver fixtures: `full-session` resolves against synthetic advertised sets to the richest
non-interactive session-grade backend per the pinned ladder; an assertion (not only doc
parity) verifies `config/defaults.yml` carries `full-session`, and the options-reference guard
(`tests/test-check-options-reference.sh`) holds doc parity. An unanswered tmux-context ask
resolves unattended immediately (fixture); re-ask suppression within one tower session via the
spec-local ask-state (fixture).

### REQ-B1.2 — operator-default only [test + design-level]

Test: the resolver takes only config input (no per-task parameter exists in its interface),
asserted by fixture. Design-level: the dispatch skill prose contains no per-task backend prompt
step, covered by the structural skill guards.

### REQ-B1.3 — per-spec override map [test]

`tests/test-config-get.sh`-family fixtures: the per-spec map wins over the global value in every
layer combination (defaults < adopter < repo-tracked < machine-local), and an absent per-spec
entry falls through to the global value.

### REQ-B1.4 — capability-not-safety degradation [test]

Unattended-resolution matrix fixtures: for every advertised-set combination, unattended
resolution never yields an `interactive: true` backend without an explicit configured value;
degradation order follows the ladder. Attended-resolution fixtures: inside tmux context
(`$TMUX` set) the resolver surfaces the once-per-run ask; outside tmux context attended
resolution matches the unattended result.

### REQ-B1.5 — explicit-but-unavailable fails closed [test]

Resolver fixture: an explicitly configured backend (global and per-spec variants) absent from
the host's advertised set halts the dispatch to Awaiting input naming the missing backend,
asserted by exit path and message; no fixture cell substitutes a different backend.

## REQ-C — The offload command

### REQ-C1.1 — standalone /offload skill [test + design-level]

Design-level: the skill exists as the sole home of adaptive selection (no other skill's prose
performs backend adaptation for petitions). Test: the structural skill guards and
`check:instructions` pass for the new SKILL.md.

### REQ-C1.2 — tower-frugality axiom [test + design-level]

Design-level: `doctrine/work-placement.md` states the axiom with the inline/offload boundary.
Test: the doc-link guard resolves the skill's citation of the doctrine doc, and a grep guard
asserts the skill cites `work-placement`.

### REQ-C1.3 — smallest-sufficient-rung axiom [test + design-level]

Same verification shape as REQ-C1.2: the axiom is stated in `doctrine/work-placement.md` and the
skill's citation is guard-checked.

### REQ-C1.4 — ask when under-determined [Gherkin]

Scenario 1: Given a petition that does not determine whether the work must survive the tower,
be human-attachable, or run beyond the session, When `/offload` selects a rung, Then it
presents the rung choice to the operator and does not dispatch until answered.
Scenario 2: Given a petition whose determined sufficient rung is not advertised on the host,
When `/offload` selects a rung, Then it presents the situation to the operator and does not
silently dispatch to an insufficient rung.

### REQ-C1.5 — report handle and attach hint [test]

The offload dispatch primitive's fixture asserts the report output carries the worker handle and
an observe/attach hint appropriate to the selected backend (a rung with no observe surface
reports that fact); a failed-dispatch fixture asserts a failure report is produced, never a
silent drop.

## REQ-D — Backend-agnostic status view

### REQ-D1.1 — CLI status view with graceful degrade [test]

Renderer fixtures cover the source present/absent matrix for all three sources
(`claude agents --json` shim, event-stream capture, attention store): each cell renders workers
from the available sources and marks a missing source visibly rather than omitting it silently.
A print-backend unit renders from dispatch records or a visible not-applicable marker; an
escape-sequence fixture asserts worker-authored strings pass the echo-safety sanitizer before
rendering.

### REQ-D1.2 — rendered dashboard [test + manual]

Test: dashboard render fixtures assert the output is produced from the shared source-merging
layer (no second source-reading implementation) and covers the same source-availability matrix
as the CLI view, missing sources marked visibly; an output-encoding fixture asserts
script-tag/markup content in worker-authored strings renders inert; the surface exposes no
state-mutating endpoint (read-only assertion). Manual: a phone/browser glance check of the
rendered surface, documented in the task's PR, recording the exposure mechanism and confirming
no unauthenticated network surface.

## REQ-E — Stream-json harness contract

### REQ-E1.1 — can_use_tool coupling and pending-age alarm [test]

Supervisor shim fixture: an injected `can_use_tool` control_request produces exactly one
decision-queue item, and advancing past the pending threshold fires the alarm; a duplicate
delivery of the same request produces no second item (request-identity dedup, per REQ-E1.5); a
second fixture asserts no code path auto-answers the request.

### REQ-E1.2 — AskUserQuestion 1:1 mapping [test]

Supervisor shim fixture: an injected AskUserQuestion control_request produces exactly one
decision-queue item carrying the question payload; advancing past the pending threshold fires
the alarm for an unanswered question item (same coupling as REQ-E1.1); duplicate delivery,
deduplicated on request identity, does not produce a second item.

### REQ-E1.3 — resume recovery [test + manual]

Test: a killed-supervisor fixture (CLI shim) recovers the session via `--resume` on the
persisted `session_id`; a failed-`--resume` fixture surfaces a halt rather than a silent loss;
recovery checks the orphaned worker's liveness before resuming (fixture). Manual: one real-CLI
end-to-end resume probe against the running CLI version, documented in the task's PR
(version-sensitive surface).

### REQ-E1.4 — answer delivery [test]

Supervisor shim fixture: an operator answer recorded on a queue item is delivered as the
control_response to the pending request; an undeliverable answer (dead channel, request gone
after recovery) surfaces a visible failure (an attention-store item naming the undeliverable
answer, asserted by the fixture), never a silent drop or a silent re-application.

### REQ-E1.5 — crash-window invariants [test]

Crash-window fixtures, one per clause: receipt state survives a supervisor kill (durable
receipt); a pending item's alarm is re-armed after `--resume`; a `can_use_tool` arriving in
the supervisor-down window is covered after recovery; dedup on request identity holds across
the resume boundary; a second concurrent recovery attempt is refused (single initiator).

## REQ-F — Idle oracle

### REQ-F1.1 — agents-json authoritative oracle [test + manual]

Test: `tests/test-fleet-liveness.sh` fixtures with an `agents --json` shim assert oracle
evidence is preferred when the probe succeeds, a recorded pane-scrape false-idle case is
corrected by the oracle, and the fallback engages when the oracle is absent; a malformed-output
fixture asserts fallback engages (never an empty-fleet read); a tracked worker absent from
oracle output is not classified dead on that absence alone (positive-evidence-of-death
preserved). Manual: one live probe against the running CLI, documented in the task's PR
(version-sensitive surface).
