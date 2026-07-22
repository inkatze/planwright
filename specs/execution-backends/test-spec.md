# Execution Backends — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-21
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]` via the repo's fixture-driven shell suites (drift guards,
resolver matrices, supervisor shims, launch-pin greps), all running under `mise run check` in CI.
`[manual]` is reserved for the two real-CLI end-to-end paths whose behavior is version-sensitive
(`--resume` recovery, the live agents-json oracle), per the prefer-end-to-end validation posture.
One `[Gherkin]` scenario covers the ask-when-unsure dialogue. `[design-level]` is confined to
doctrine prose whose existence-plus-coverage is the verification.

## REQ-A — Backend capability contract & registry extension

### REQ-A1.1 — overhead and hook_registration properties [test + design-level]

Design-level: the amended contract doc defines both properties with evaluable definitions.
Test: the doc-table ↔ `orchestrate-backends.sh` drift guard (extending
`tests/test-orchestrate-backends.sh`) parses the new columns and asserts parity for every row.

### REQ-A1.2 — headless-oneshot backend value [test]

`tests/test-orchestrate-backends.sh` asserts the advertised set answered for `headless-oneshot`;
Task 3's dispatch fixtures verify detached launch, completion signal, and liveness behavior
match the advertised set.

### REQ-A1.3 — stream-json-persistent backend value [test]

`tests/test-orchestrate-backends.sh` asserts the advertised set answered for
`stream-json-persistent`; Task 4's supervisor shim fixtures verify the observe (event-stream
capture) and steer (message-in) surfaces exist and the session-grade-as-recoverable property
holds (see REQ-E1.3).

### REQ-A1.4 — subagent row correction [design-level]

The amended contract doc records steer-via-resume-with-context on the `subagent` row while
keeping session-grade `no`; the drift guard covers the row's machine-readable mirror.

### REQ-A1.5 — non-bare launch pinning [test]

The launch-pin guard (extending `tests/test-dispatch-launch-pin.sh`) greps every `-p`-family
launch site and fails on an unpinned invocation; fixtures include one deliberately-unpinned
negative case.

### REQ-A1.6 — contract/registry lockstep [test]

The drift guard parses the contract doc's backend table (all rows, all fields, including the two
new properties) and asserts `orchestrate-backends.sh` answers identically; a seeded divergence
fixture fails the guard.

### REQ-A1.7 — back-compatible adapter grammar [test]

Adapter-grammar fixtures: an eight-field line parses fully; a legacy six-field line is accepted
with fail-safe defaults (`hook_registration=false`, most-conservative `overhead`); a malformed
line fails closed (backend never selected), asserted by exit code and absence from the candidate
set.

## REQ-B — Task-execution backend knob

### REQ-B1.1 — full-session semantic value and default flip [test]

Resolver fixtures: `full-session` resolves against synthetic advertised sets to the richest
non-interactive session-grade backend; `config/defaults.yml` carries the flipped default and the
options-reference guard (`tests/test-check-options-reference.sh`) holds doc parity.

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
degradation order follows the ladder.

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

Scenario: Given a petition that does not determine whether the work must survive the tower, be
human-attachable, or run beyond the session, When `/offload` selects a rung, Then it presents
the rung choice to the operator and does not dispatch until answered.

### REQ-C1.5 — report handle and attach hint [test]

The offload dispatch primitive's fixture asserts the report output carries the worker handle and
an observe/attach hint appropriate to the selected backend.

## REQ-D — Backend-agnostic status view

### REQ-D1.1 — CLI status view with graceful degrade [test]

Renderer fixtures cover the source present/absent matrix for all three sources
(`claude agents --json` shim, event-stream capture, attention store): each cell renders workers
from the available sources and marks a missing source visibly rather than omitting it silently.

## REQ-E — Stream-json harness contract

### REQ-E1.1 — can_use_tool coupling and pending-age alarm [test]

Supervisor shim fixture: an injected `can_use_tool` control_request produces exactly one
decision-queue item, and advancing past the pending threshold fires the alarm; a second fixture
asserts no code path auto-answers the request.

### REQ-E1.2 — AskUserQuestion 1:1 mapping [test]

Supervisor shim fixture: an injected AskUserQuestion control_request produces exactly one
decision-queue item carrying the question payload; duplicate delivery does not produce a second
item.

### REQ-E1.3 — resume recovery [test + manual]

Test: a killed-supervisor fixture (CLI shim) recovers the session via `--resume` on the
persisted `session_id`. Manual: one real-CLI end-to-end resume probe against the running CLI
version, documented in the task's PR (version-sensitive surface).

## REQ-F — Idle oracle

### REQ-F1.1 — agents-json authoritative oracle [test + manual]

Test: `tests/test-fleet-liveness.sh` fixtures with an `agents --json` shim assert oracle
evidence is preferred when the probe succeeds, a recorded pane-scrape false-idle case is
corrected by the oracle, and the fallback engages when the oracle is absent. Manual: one live
probe against the running CLI, documented in the task's PR (version-sensitive surface).
