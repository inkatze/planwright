# Quota handling — Tasks

**Status:** Draft
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. Tasks that write the `limited` outcome or read the new
step fields wait on the custom-steps amendment (D-3), which is tracked as
Awaiting-input entries rather than as a task, because it is signed through
that bundle's own kickoff.

## Tasks

### Task 1 — The vendors catalog and its resolver

- **Deliverables:** `config/vendors.yaml` carrying the core `claude`
  entry; `vendors` resolution through `scripts/resolve-catalog.sh` with
  the by-layer malformed-entry policy; a validator for entry fields
  (id grammar, fixed-string recognizers, evidence kind from the closed
  set, controls, choice rules over the closed condition set, bot login);
  `docs/quota.md` documenting the adapter contract, with example entries
  for a PR-comment review bot and an external model CLI; options-reference
  rows for every knob the bundle adds.
- **Done when:** a test resolves an adapter across all four layers with
  provenance, rejects each malformed field with a named reason, and
  confirms no third-party entry is active in core; `mise run check` passes
  with the new docs and options rows.
- **Dependencies:** none
- **Citations:** D-9, D-10 · REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5,
  REQ-C1.6
- **Estimated effort:** 1 day

### Task 2 — The limit classifier and the `limited` outcome

- **Deliverables:** a core classifier script matching captured output
  against a vendor's recognizers and emitting `limited` with recognizer
  id, screened excerpt, and stated reset time; `scripts/step-record.sh`
  accepting `limited`; the runner calling the classifier for every
  vendor-bound step and applying `on-limit` (`hold`, `continue`,
  `alternate`) with the flip-point refusal; resolution refusing an
  invalid alternate; the custom-steps doctrine pointer line.
- **Done when:** fixtures show a recognized refusal from each step kind
  classified `limited`, an unrecognized one keeping its custom-steps
  outcome, `continue` and `alternate` behaving as declared, a `limited`
  record refusing a flip, and the three invalid alternates refused at
  resolution.
- **Dependencies:** Task 1
- **Citations:** D-3, D-4, D-5 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.5,
  REQ-B1.2
- **Estimated effort:** 1 day

### Task 3 — The hold store and the per-vendor ledger

- **Deliverables:** a core script with `hold`, `resume`, `status`, and
  `prune` verbs over a per-vendor hold directory and ledger file in the
  fleet home, written under the lock library; the operator resume command
  documented in `docs/quota.md`; the ledger retention knob; the vendor
  view on the status surface.
- **Done when:** tests cover concurrent holds on one vendor from two
  units, resume releasing every holder, retention pruning, the status
  view rendering hold state and windowed counts, and hostile vendor ids
  refused before any path use.
- **Dependencies:** Task 1
- **Citations:** D-6, D-7, D-13 · REQ-B1.3, REQ-B1.5, REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 4 — Holding and resuming units

- **Deliverables:** the runner parking a unit on a `hold` posture with an
  Awaiting-input entry naming vendor, step, reason, and reset time, and an
  attention push; the pre-request hold check for every vendor-bound step;
  release unparking held units and re-dispatching them; the resumed run
  skipping steps recorded `passed` or `applied` on the same head; a
  renewed refusal renewing the hold.
- **Done when:** fixtures show a held unit parked with the named fields
  and an attention event, a second unit taking its posture without
  sending a request, a resume skipping same-head completed steps and
  re-running everything after a head move, and a refused resume renewing
  the hold with no further attempt.
- **Dependencies:** Task 2, Task 3
- **Citations:** D-5, D-6, D-7, D-8 · REQ-B1.1, REQ-B1.3, REQ-B1.6,
  REQ-B1.7
- **Estimated effort:** 2 days

### Task 5 — Worker-death classification and the Claude throttle

- **Deliverables:** the stream-json status, its exit fallback, the
  headless rung's completion reader, and the stuck detector reading the
  error signal and event-stream error text; a rate-limit death classified
  `limited` against `claude`, recorded as a hold, and engaging the
  throttle through its existing verb; any other API error a failure naming
  its cause.
- **Done when:** fixtures for each rung show a 529 death recorded as a
  named failure and a rate-limit death recorded as `limited` with the
  throttle engaged, and no fixture yields a clean completion for either.
- **Dependencies:** Task 1, Task 3
- **Citations:** D-15 · REQ-A1.4, REQ-E1.6
- **Estimated effort:** 1 day

### Task 6 — The Claude usage producer

- **Deliverables:** the stream-json supervisor persisting each worker's
  newest rate-limit frame; the `claude-frames` evidence kind and the usage
  gate's capture path reading across those frames with the staleness rule
  and the lowest-rung threshold; the account-wide label on every
  rendering; unmeasured reported for frameless backends and for no live
  frame.
- **Done when:** fixtures cover a dead worker's past-reset frame ignored,
  the furthest-future frame chosen, recovery refused above the lowest rung
  and granted below it, a subagent-only fleet reported unmeasured, and the
  gate's proactive path running from persisted frames.
- **Dependencies:** Task 3
- **Citations:** D-14 · REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-B1.4
- **Estimated effort:** 1 day

### Task 7 — Evidence-based automatic resume

- **Deliverables:** the resume sweep in the attention watcher's reconcile
  pass, asking each held vendor's evidence kind and releasing on positive
  evidence; `none` vendors left for the operator; a push when a vendor is
  released.
- **Done when:** fixtures show a `claude` hold released on a fresh
  low-utilization frame and kept on a passed reset time alone, a `none`
  hold never released by the sweep, and each release pushing an event.
- **Dependencies:** Task 4, Task 6
- **Citations:** D-7, D-14 · REQ-B1.4
- **Estimated effort:** half day

### Task 8 — The head-moved signal and final-head ordering

- **Deliverables:** the runner recording previous and new heads after a
  head-moving post-pr step and exposing them in the fixed step context;
  the `moves-head` and `final-head` fields honoured; resolution refusing a
  `final-head` step placed before a `moves-head` step.
- **Done when:** fixtures show the signal reaching a later step after a
  push, absent when the head did not move, and a misordered list refused
  with both step ids named.
- **Dependencies:** none
- **Citations:** D-12 · REQ-D1.1, REQ-D1.4
- **Estimated effort:** 1 day

### Task 9 — The review-request command

- **Deliverables:** the core command step script: hold check, same-head
  skip, bot-account confirmation, control or choice-rule resolution from
  the ledger, comment posted from a file, request recorded with its head,
  bounded wait for the bot's next comment, reply printed screened for the
  classifier.
- **Done when:** tests with a stubbed GitHub client show a first request
  using the choice rule's first-review control and a later one its
  follow-up control, a same-head request skipped, a human login refused, a
  quota reply classified `limited`, and no reply within the timeout
  `failed`.
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
  using only shipped mechanisms and overlay entries; the fixture shows the
  run holding at the bot step with no `failed` outcome, no second request,
  the PR still a draft, the flip point not reached, the reason pushed, and
  the order completing after an operator resume.
- **Dependencies:** Task 4, Task 7, Task 9
- **Citations:** D-11, D-12 · REQ-F1.1, REQ-F1.2
- **Estimated effort:** 1 day

## Awaiting input

- **Task 2** waits on the custom-steps amendment adding the `limited`
  outcome, the `vendor`, `control`, and `on-limit` step fields, and the
  same-head resume skip landing on main (D-3).
- **Task 8** waits on the same custom-steps amendment adding the
  `moves-head` and `final-head` step fields landing on main (D-3).

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
