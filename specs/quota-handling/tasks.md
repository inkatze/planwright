# Quota handling — Tasks

**Status:** Ready
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. Tasks that write a `limited` step record or read the new
step fields wait on the custom-steps amendment (D-3), which is tracked as
Awaiting-input entries rather than as a task, because it is signed through
that bundle's own kickoff. Runner behaviour (in Tasks 2, 4, 8, and 10) is
verified by fixture overlays run on the terminal rung and recorded in the
PR body, as custom-steps verified its runner; script behaviour is verified
by `scripts/run-tests.sh`.

## Tasks

### Task 1 — The vendors catalog, its resolver, and the limit classifier

- **Deliverables:** `config/vendors.yaml` carrying the core `claude`
  adapter as flat per-part entries (D-9); `vendors` resolution through
  `scripts/resolve-catalog.sh`, unchanged, with the by-layer
  malformed-entry policy, grouped by vendor after merge; a validator for
  entry fields
  (id grammar, fixed-string recognizers, evidence kind from the closed
  set, controls, choice rules over the closed condition set, bot login);
  `docs/quota.md` documenting the adapter contract, with placeholder
  example vendors for a PR-comment review bot and an external model CLI; options-reference
  rows for the knobs this task adds; a core classifier script matching
  captured output against a vendor's recognizers and reporting a match
  with recognizer id, screened excerpt, and stated reset time, usable by
  the step runner and the worker completion readers alike.
- **Done when:** a test resolves an adapter across all four layers with
  provenance, an overlay superseding one recognizer of a core vendor
  without restating the rest, rejects a part whose vendor has no vendor
  entry, rejects each malformed field with a named reason (a comment
  body mentioning a foreign handle or carrying a reference, an oversized
  body, a CLI argument outside the plain-word grammar among them), and
  confirms no third-party entry is in core and that the examples in
  `docs/quota.md` use invented placeholder vendors only; classifier fixtures
  show a recognized text reported with its fields, the reset time omitted
  when the locator finds none or finds an unparseable, past, or
  beyond-ceiling value, no match on unrecognized text, and
  identical output on identical input; `mise run check` passes with the
  new docs and options rows.
- **Dependencies:** none
- **Citations:** D-4, D-9, D-10 · REQ-A1.2, REQ-A1.5, REQ-C1.1, REQ-C1.5,
  REQ-C1.6
- **Estimated effort:** 1.5 days

### Task 2 — The `limited` outcome and the on-limit postures

- **Deliverables:** `scripts/step-record.sh` accepting `limited` with the
  vendor id and the classifier's recognizer id, screened excerpt, and
  stated reset time; the runner calling the classifier (Task 1) for every
  vendor-bound step and applying `on-limit` (`hold`, `continue`,
  `alternate`) with the flip refusal on any `limited` record of the run on
  the flipped head; resolution refusing an invalid alternate, and treating
  a step bound to an undeclared vendor or control as non-resolving under
  custom-steps' missing-step matrix; `<vendor>:<control>` resolving to that
  vendor's declared invocation.
- **Done when:** fixtures show a recognized refusal from each step kind
  classified `limited`, an unrecognized one keeping its custom-steps
  outcome, `continue` and `alternate` behaving as declared (a `limited`
  alternate taking `hold`), a `limited` record from an earlier point
  refusing a flip, the three invalid alternates refused at resolution, an
  undeclared vendor and an undeclared control each printing the matrix
  token for its layer and attendance, and a control declared only by
  another vendor not resolving.
- **Dependencies:** Task 1
- **Citations:** D-3, D-4, D-5, D-9, D-10 · REQ-A1.1, REQ-A1.3, REQ-A1.5,
  REQ-B1.2, REQ-C1.2, REQ-C1.4
- **Estimated effort:** 1 day

### Task 3 — The hold store and the per-vendor ledger

- **Deliverables:** a core script with `hold`, `resume`, `status`, and
  `prune` verbs over a per-vendor hold directory and ledger file in the
  fleet home, written under the lock library, the `hold` verb pushing the
  attention event for every caller; field grammars checked on write and
  failing lines skipped on read; the operator resume command documented
  in `docs/quota.md`; the `quota_ledger_retention_days` knob with its
  options-reference row; the vendor view in `scripts/fleet-stats.sh
  render`.
- **Done when:** tests cover concurrent holds on one vendor from two
  units, a hold pushing its event naming the resume command, resume
  releasing every holder, retention pruning, the status view rendering
  hold state and counts over the retention period, hostile vendor, unit,
  and recognizer ids, PR numbers, and heads refused before any path or
  ledger use, and a forged line (an embedded newline in a reason) skipped
  on read.
- **Dependencies:** Task 1
- **Citations:** D-6, D-7, D-13 · REQ-B1.1, REQ-B1.3, REQ-B1.5, REQ-E1.1,
  REQ-E1.2
- **Estimated effort:** 1 day

### Task 4 — Holding and resuming units

- **Deliverables:** the runner recording a unit on a `hold` posture in the
  hold store with vendor, step, reason, and reset time, and an attention
  push; `scripts/orchestrate-select.sh` skipping a held unit and the status
  render showing it held; the pre-request hold check for every vendor-bound
  step; the staged release (the longest-held unit first, the rest after
  its first vendor request ends other than `limited`, none on a renewed
  refusal), with no commit; the resumed run recording `skipped` for each step recorded
  `passed` or `applied` whose recorded head (the head after the step) is
  the current head; a renewed refusal renewing the hold.
- **Done when:** fixtures show a held unit recorded in the hold store with
  the named fields, not selected while held, no `tasks.md` write, and an
  attention event, a second unit taking its posture without sending a
  request, a resume skipping same-head completed steps and re-running
  everything after a head move, the branch's commit list unchanged by a
  release, a release of three held units sending exactly one request
  before the probe answers, the other two released after an answer and
  never sent after a refusal, and a refused resume renewing the hold with
  no further attempt.
- **Dependencies:** Task 2, Task 3
- **Citations:** D-5, D-6, D-7, D-8 · REQ-B1.1, REQ-B1.3, REQ-B1.6,
  REQ-B1.7
- **Estimated effort:** 2 days

### Task 5 — Worker-death classification and the Claude throttle

- **Deliverables:** the stream-json status, its exit fallback, the
  headless rung's new `result.json` reader, and the stuck detector
  reading the error signal and the error text (event stream, or the
  headless result's `is_error` and result text); a rate-limit death
  classified `limited` against `claude`, recorded as a hold whose step is
  `worker`, and engaging the throttle through `engage --until` with the
  stated reset time, or `observe` when none was stated; any other API
  error a failure naming its cause.
- **Done when:** fixtures for each reader (a stream-json event stream and
  a headless `result.json`) show a 529 death recorded as a named failure
  and a rate-limit death recorded as `limited` with the throttle engaged,
  and no fixture yields a clean completion for either.
- **Dependencies:** Task 1, Task 3
- **Citations:** D-4, D-6, D-15 · REQ-A1.4, REQ-B1.1, REQ-E1.6
- **Estimated effort:** 1 day

### Task 6 — Claude clearance evidence from worker frames

- **Deliverables:** the stream-json supervisor persisting each worker's
  newest rate-limit frame; the `claude-frames` evidence kind reading
  across those frames per window with the staleness rule, the
  post-hold-reading requirement, and each window's lowest-rung descend
  threshold; the account-wide label on every rendering; unmeasured
  reported for frameless backends and for no live frame.
- **Done when:** fixtures cover a dead worker's past-reset reading
  ignored, the furthest-future reading chosen per window, clearance
  refused when either window is above its threshold or lacks a post-hold
  reading and granted when both are below with post-hold readings, a
  subagent-only fleet reported unmeasured, and the usage gate's state
  unchanged by any frame.
- **Dependencies:** Task 3
- **Citations:** D-14 · REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-B1.4
- **Estimated effort:** 1 day

### Task 7 — Evidence-based automatic resume

- **Deliverables:** the resume sweep in the attention watcher's reconcile
  pass, asking each held vendor's evidence kind and releasing on positive
  evidence; `none` vendors left for the operator; a push when a vendor is
  released.
- **Done when:** fixtures show a `claude` hold released on a reading
  received after the hold began with every governed window below its
  lowest-rung descend threshold, kept on a passed reset time alone, kept
  when only the weekly window has a post-hold reading, a `none` hold never
  released by the sweep, and each release pushing an event.
- **Dependencies:** Task 4, Task 6
- **Citations:** D-7, D-14 · REQ-B1.4
- **Estimated effort:** half day

### Task 8 — The head-moved signal and final-head ordering

- **Deliverables:** the runner recording previous and new heads after a
  head-moving post-pr step and exposing them in the fixed step context;
  the `moves-head`, `final-head`, and `drains` fields honoured; resolution
  refusing a `final-head` step placed before a `moves-head` step unless
  that step drains it, and refusing a `drains` that names a missing or
  non-final-head step.
- **Done when:** fixtures show the signal reaching a later step after a
  push, absent when the head did not move, a misordered list refused with
  both step ids named, a drain naming its final-head step accepted after
  it, and a drain naming another step refused.
- **Dependencies:** none
- **Citations:** D-12 · REQ-D1.1, REQ-D1.4
- **Estimated effort:** 1 day

### Task 9 — The review-request command

- **Deliverables:** the core command step script: hold check, same-head
  skip, bot-account confirmation, control or choice-rule resolution from
  the ledger, history rebuilt from the bot's PR comments when the ledger
  holds nothing for the PR, comment posted from a file, request recorded
  with its head, a wait bounded by its required `--wait` argument, a reply
  counted only from the bot login and after the request, reply printed
  screened for the classifier, an answer line recorded for a non-limited
  reply.
- **Done when:** tests with a stubbed GitHub client show a request before
  any answered one using the choice rule's first-review control and one
  after an answered request its follow-up control, a same-head request
  skipped once answered and re-sent after a refused or unanswered one, an
  empty ledger rebuilt from prior bot comments, a human login refused, a
  human comment carrying refusal text ignored with no answer or hold
  written, a quota reply classified `limited`, and no reply within
  `--wait` `failed`.
- **Dependencies:** Task 2, Task 3, Task 8
- **Citations:** D-10, D-11, D-13 · REQ-C1.3, REQ-D1.2, REQ-D1.3,
  REQ-D1.5
- **Estimated effort:** 1 day

### Task 10 — The acceptance scenario

- **Deliverables:** a documented overlay example in `docs/quota.md`
  expressing the acceptance order; an end-to-end fixture running that
  order against a stubbed bot that refuses with a quota message, then is
  released.
- **Done when:** the example resolves with `scripts/resolve-steps.sh`
  using only shipped mechanisms and overlay entries, the panel and drain
  pass named as operator commands and stubbed on PATH in the fixture, the
  bot step `final-head` and the drain `moves-head` with `drains` naming
  it; the fixture
  shows the run holding at the bot step with no `failed` outcome, no
  second request before the resume, the PR still a draft, the flip point
  not reached, the reason pushed, and the order completing after an
  operator resume; the REQ-F1.2 `[manual]` entry is listed in `/drain`'s
  manual inventory.
- **Dependencies:** Task 4, Task 7, Task 9
- **Citations:** D-11, D-12 · REQ-F1.1, REQ-F1.2
- **Estimated effort:** 1 day

## Awaiting input

- **Task 2** waits on the custom-steps amendment adding the `limited`
  outcome (with its doctrine outcome-list entry), the `vendor`, `control`,
  and `on-limit` step fields, `skipped` produced outside the missing-step
  matrix, and the resume-continuation rule its dependent Task 4 builds on,
  landing on main (D-3).
- **Task 8** waits on the same custom-steps amendment adding the
  `moves-head`, `final-head`, and `drains` step fields and the previous
  and new head context fields landing on main (D-3).

## Deferred

- **Forecasting non-Claude quotas.** No observed vendor offers a supported
  quota readout, so forecasting has nothing to read. Confidence: high.
  **Gate:** a vendor an operator uses offers a supported, documented way
  to read remaining quota.
  Citations: D-16.
- **A probe-command evidence kind.** An operator-declared executable as an
  evidence kind would let vendors with a status CLI resume automatically,
  at the cost of trusting overlay code. Confidence: medium.
  **Gate:** a recorded observation of a vendor hold that a status CLI
  could have released.
  Citations: D-9.

## Out of scope

- **Re-firing earlier points after a post-pr commit.** Owned by the
  expensive-check ask (obs:6c3342a8) for a custom-steps extension.
- **Spend controls for non-Claude vendors.** D-16.
