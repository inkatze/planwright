# Tower comms — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The order is the bundle's load-bearing claim
(D-15): the log and scorecard land first and measure today's tower; the
queue is wired in only after a baseline exists, so the experiment has an
honest before.

## Tasks

### Task 1 — The event log and the scorecard

- **Deliverables:** `scripts/tower-queue.sh` with its `log` and `report`
  verbs: one JSON line per event under the fleet home (schema version,
  monotonic sequence, kind, payload), written under the fleet lock; the
  scorecard computed from the log alone with the headline (items reached
  the operator per hour of fleet work against items settled without them)
  and the secondary measures (blocked-worker wait, multi-ask turns, friction
  moments, jargon counts over delivered text, items lost across restart);
  the jargon count implemented over a word list shipped with the script,
  which the rule doc cites once it lands (Task 7);
  unit tests for the log grammar, the sequence, and each measure; a
  `mise run tower:report` task; no CI wiring.
- **Done when:** the log verb refuses a control byte or a malformed field;
  the report over a fixture log reproduces hand-computed numbers for every
  measure; the tower loop can log a delivered turn and an operator reply
  with no queue present; `check-no-ci-evals.sh` and `mise run check` pass.
- **Dependencies:** none
- **Citations:** D-14, D-15 · REQ-D1.4, REQ-G1.1, REQ-G1.2, REQ-G1.5,
  REQ-H1.3, REQ-H1.4
- **Estimated effort:** 1 day

### Task 2 — Baseline sessions

- **Deliverables:** the log verb called from today's `/orchestrate` watch
  loop and step report for every delivered turn and every operator reply,
  with nothing else changed; a recorded baseline over real fleet sessions
  (the sessions counted, the scorecard per session, the aggregate), appended
  to the kickoff brief's risk register.
- **Done when:** the baseline entry names its sessions and numbers; the
  watch-loop change adds no queue behaviour (the diff touches only logging
  calls); `check:instructions` passes.
- **Dependencies:** Task 1
- **Citations:** D-15 · REQ-G1.3
- **Estimated effort:** half day plus the sessions' wall clock

### Task 3 — The queue store and script

- **Deliverables:** `scripts/tower-queue.sh` verbs `add`, `list`, `next`,
  `ack`, `shelve`, and `settle` over a queue store under the fleet home,
  written under the fleet lock with atomic rename; the five item kinds; the
  single-line record grammar with the closing-condition field and the
  refusal of a record promising an automatic step; content pointers to the
  home per kind; echo-safety on every rendered value; rebuild of the queue
  from the content homes when the store is absent; unit tests including a
  hostile-input table and a rebuild-after-loss case.
- **Done when:** every verb round-trips through the store under a
  concurrent-writer test with no torn record; `next` prints at most one
  item and orders by kind, urgency, then age; a deleted store rebuilds with
  no content lost; `mise run check` passes.
- **Dependencies:** Task 1
- **Citations:** D-2, D-3, D-4, D-6 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-C1.1, REQ-C1.5, REQ-C1.6, REQ-H1.3, REQ-H1.4
- **Estimated effort:** 2 days

### Task 4 — Settling and merging

- **Deliverables:** the settling pass in `scripts/tower-queue.sh`: reads the
  worker attention store's decision queue as an input, the reconcile
  sweep's evidence sources (PR state, branch commits, ledger closure,
  answered-by-another-route), and the standing decisions; settles items
  whose closing condition is met with a record naming the evidence; merges
  same-question items naming every source; pairs contradicting items as one
  decision; refuses to settle on a worker's completion report, result
  frame, or status line; a `settled` listing for the on-request view.
- **Done when:** fixtures for each evidence source settle the right item and
  nothing else; a worker "completed/success" fixture settles nothing; two
  same-question fixtures merge into one item with both sources; a
  contradicting pair delivers as one; `mise run check` passes.
- **Dependencies:** Task 3
- **Citations:** D-5, D-8 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5,
  REQ-F1.4, REQ-H1.2
- **Estimated effort:** 1.5 days

### Task 5 — Delivery, the knock, and away detection

- **Deliverables:** the `knock` verb producing the one-line knock (kind and
  urgency of what is waiting); away detection from the last knock and last
  reply against the quiet-interval knob; the re-knock rule (first blocking
  item, then only on more blocked workers or a blocked item passing the
  re-knock age knob); the push through `fleet-attention.sh notify` when
  away, with `none` leaving the item queued; shelve return; the two config
  knobs in `config/defaults.yml` with their `docs/options-reference.md`
  rows; unit tests for the away state machine and the re-knock rule.
- **Done when:** a fixture timeline produces exactly the knocks the rule
  allows and no fixed-interval repeat; a `none` channel queues without
  error; `check:options-reference` and `mise run check` pass.
- **Dependencies:** Task 3, Task 4
- **Citations:** D-6, D-7, D-9 · REQ-C1.2, REQ-C1.4, REQ-C1.7, REQ-F1.1,
  REQ-F1.2, REQ-F1.3
- **Estimated effort:** 1.5 days

### Task 6 — Inbound capture and standing decisions

- **Deliverables:** the `capture` verb for requests, questions-needing-work,
  and standing decisions; the one-line echo text; the content write to the
  action-item ledger when its helpers exist and to an observation fragment
  tagged as a capture or as standing otherwise; the standing-decision
  record (rule in the operator's words, coverage, date); the permission
  prompt match: strictly inside a written standing decision answers through
  the sanctioned answer channel with the log naming the rule, anything else
  queues for the operator; unit tests including a prompt just outside a
  rule.
- **Done when:** a captured request appears in its content home and in the
  queue with a pointer; a prompt inside a standing decision is answered and
  the log names the rule; a prompt one token outside it reaches the queue;
  no path answers from anything but a written rule; `mise run check`
  passes.
- **Dependencies:** Task 3
- **Citations:** D-11, D-12 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4,
  REQ-E1.5, REQ-E1.6, REQ-H1.1, REQ-H1.2
- **Estimated effort:** 1.5 days

### Task 7 — The conversation rule doc and its budget

- **Deliverables:** `doctrine/tower-comms.md`, the short rule doc: the
  knock-then-deliver ritual, one item per turn, any reply releases the
  next, the speech register and the listener-side word test, the
  first-turn-after-silence rule, and a pointer to the jargon word list the
  scorecard reads; its row in the doctrine README index; the reachable-budget knob
  raised by the doc's measured size with the reason recorded in the config
  comment, per the headroom policy's budget-raise rung; no restatement
  beyond a one-line gist in any skill.
- **Done when:** the doc holds no rule a script in Tasks 3 through 6
  enforces; `check:doctrine-index`, `check:links`, and `check:instructions`
  pass with the raise recorded and no floor-breach warning; the doc's word
  count is printed in the PR body beside the raise.
- **Dependencies:** none
- **Citations:** D-10, D-13 · REQ-C1.3, REQ-C1.8, REQ-D1.1, REQ-D1.2,
  REQ-D1.3, REQ-I1.1, REQ-I1.2, REQ-I1.3
- **Estimated effort:** 1 day

### Task 8 — Wiring into the tower loop

- **Deliverables:** `/orchestrate`'s watch loop, `--fleet` loop, and step
  report route every operator-bound item through the queue: the settling
  pass each iteration, `next` for the requests slot, `knock` before any
  delivery, `capture` for operator input, the first-turn-after-silence
  picture from the queue's catch-up view; the attention render no longer
  re-rendering items the queue already delivered; the `tower-comms` doc
  cited at point of use in the skill manifest.
- **Done when:** a scripted tower session over a fixture fleet delivers one
  item per turn, knocks before each, and captures an operator request in
  the same turn; `check:instructions` passes at the raised budget with no
  floor-breach warning; `mise run check` passes.
- **Dependencies:** Task 2, Task 5, Task 6, Task 7
- **Citations:** D-6, D-13, D-16 · REQ-A1.1, REQ-C1.1, REQ-C1.2, REQ-C1.4,
  REQ-C1.8, REQ-E1.1, REQ-F1.5, REQ-I1.4
- **Estimated effort:** 1.5 days

### Task 9 — The experiment and the extension gate

- **Deliverables:** real fleet sessions run with the queue wired in, the
  scorecard per session and aggregate, the comparison against the Task 2
  baseline, and the recorded result in the kickoff brief's risk register;
  the standing-decision mismatch rate reported from the log; the Deferred
  extension entry's gate evaluated against the result and the outcome
  written into the entry.
- **Done when:** the risk-register entry names the sessions on both sides
  and every measure; the Deferred entry carries the measured outcome; no
  spec or doctrine file outside this bundle is edited by this task.
- **Dependencies:** Task 2, Task 8
- **Citations:** D-15, D-16 · REQ-G1.4, REQ-I1.4
- **Estimated effort:** half day plus the sessions' wall clock

### Task 10 — Docs and doctrine reconciliation

- **Deliverables:** a fleet guide section on the operator queue (what the
  operator sees, the replies the tower understands, the two knobs, the
  scorecard command); the attention capability doc's writer enumeration
  refreshed and the sibling queue named as a reader; the intervention
  contract in the finding-categorization doctrine amended to state its two
  routes and the knock as the way a hard pause reaches the operator; the
  autonomous-safe-decision doctrine's permission-prompt sentence amended
  to name the standing-decision case.
- **Done when:** `check:links`, `check:doctrine-index`, and
  `check:instructions` pass with no floor-breach warning; the REQ-D1.3 word
  test is stated in the fleet guide in the operator's terms.
- **Dependencies:** Task 8
- **Citations:** D-2, D-12 · REQ-E1.5, REQ-F1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

- **Extend the conversation rules to `/spec-kickoff`, `/spec-draft`,
  `/resume`, and `/drain`.** The rules are universal in content but bound to
  towers in this version; they spread when the experiment shows they helped.
  Confidence: medium.
  **Gate:** GATE(when: task 9 completed).
  Citations: D-16, REQ-G1.4, REQ-I1.4.
- **Wire the queue into the `/tower` front door.** The skill does not exist
  yet; the wiring is the same as Task 8's.
  Confidence: high.
  **Gate:** tower-front-door Task 4 merged.
  Citations: D-16, REQ-F1.5.
- **Cut over standing decisions and captures from observation fragments to
  the action-item ledger.** The ledger bundle owns the cutover; this bundle
  writes to the fallback until then.
  Confidence: high.
  **Gate:** action-item-ledger Task 1 merged.
  Citations: D-11, REQ-E1.2, REQ-E1.3.

## Out of scope

- **Worker permission allowlists and guard shapes.** Owned by
  worker-permission-ergonomics. Citations: REQ-E1.5.
- **Worker liveness and completion truth.** Owned by fleet-lifecycle-closure
  and the stream-json fixes. Citations: REQ-B1.2.
- **Notification channel adapters and transport.** Owned by the attention
  capability and fleet-messaging. Citations: REQ-F1.2.
- **Durable tracking and closure of owed items.** Owned by
  action-item-ledger. Citations: REQ-E1.2.
- **The reserved human controls and artifact completeness.** Unchanged,
  permanently. Citations: REQ-H1.1.
