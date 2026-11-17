# Control plane — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-15
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 1 to 5 are slice one, specified in full. Each later slice opens with a
design walk task (a human-gated amendment of this bundle); its build tasks are
stubs until that walk turns the outline into full requirements, and a stub's
fields are a starting point the walk may rewrite. Every policy task starts with
its failing fixtures (REQ-I1.1). Slice one waits on the universal-binary
amendment only for its language (D-16); the contract is neutral.

## Tasks

### Task 1 — Record the measurement baseline and its method

- **Deliverables:** A method document and a machine-local recording script that
  reads local session logs and the forge and writes the baseline: model turns
  per day by session role, the spend split, merges per day and operator
  interruptions, to machine-local data never committed. The slice-to-metric
  table naming the one number each slice is expected to move.
- **Done when:** the script runs on a fixture log set and reproduces the
  fixture's recorded numbers; a run against real logs writes only to the
  machine-local location; a check fails if a committed file holds a recorded
  figure; the method document names the metric per slice.
- **Dependencies:** none
- **Citations:** D-9 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 2 — Policy data: schemas, shipped catalogs, floor and the kill switch

- **Deliverables:** The schemas and shipped core seeds for the approval classes
  (with their modes and scope predicates), the approval floor, the dedupe
  horizons and windows, and the merge-mode reach; the schema check wired into
  CI and at load; the layering through the catalog and configuration
  resolvers; the `explain` verb; the kill-switch setting; the options-reference
  rows. The near-miss fixture directories (empty of rules, each class
  declared) and the check that fails when a class has none.
- **Done when:** an entry failing its schema is dropped while the lower layers
  stay in force, and a class-bounding failure makes the class refuse
  everything (both shown by fixture); a layer entry allowing a floor act fails
  the check by name; `explain` names the supplying layer for a fixture
  verdict; with the kill switch set every verb defers; the near-miss check
  fails against a class declared with no near-miss fixture and passes once one
  exists; the merge-mode reach value takes effect only from the shipped and
  adopter layers (a machine-local value is ignored and reported).
- **Dependencies:** none
- **Citations:** D-3, D-7, D-10, D-14 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-B1.6, REQ-B1.7, REQ-C1.7, REQ-I1.2
- **Estimated effort:** 2 days

### Task 3 — The approval engine and its classes, fixtures first

- **Deliverables:** The engine verb in shell behind the language-neutral
  contract (a structured request on stdin, a verdict on stdout, fixed exit
  codes), the quote-aware argument-vector matcher, the `read-only`,
  `own-branch-push`, `automated-reviewer-reply`, `release-run`, `host-act`,
  `test-run`, `lint-run` and `evidence-and-wait` classes (all in shadow) and the
  floor refusals, the owner check and the self-describing answer line, and the
  request-id keyed answer. The allow and near-miss fixtures for every class,
  written before the rule they test, and the drift check against the worker
  command guard's read-only set. Registration of the engine in the guard
  catalog.
- **Done when:** a test or lint command naming a path outside the worktree and
  a CI wait with no bound each return defer; every class's allow fixtures return allow and every near-miss
  fixture returns defer or deny as recorded; every floor act returns deny with
  a message naming its entry; every input with a substitution, an unreadable
  construct, an unknown policy format or a missing request id defers; an answer
  for a worker the caller's program does not own is refused and changes
  nothing; the near-miss check has been shown to fail against a deliberately
  widened rule; the drift check fails on a command one classification admits
  and the other refuses; the write-time security pass for untrusted input,
  subprocess construction, path handling and authorization is recorded; the
  suite runs in CI.
- **Dependencies:** Task 2
- **Citations:** D-4, D-5, D-7, D-16, D-19 · REQ-C1.1, REQ-C1.2, REQ-C1.3,
  REQ-C1.4, REQ-C1.5, REQ-C1.7, REQ-C1.10, REQ-C1.11, REQ-I1.1, REQ-I1.3
- **Estimated effort:** 4 days

### Task 4 — Wire the engine at the event source, in shadow, with the decision log

- **Deliverables:** The engine consulted by the stall watcher before a
  pending-prompt event is raised; an allow delivered through the worker's own
  answer channel with its owner check; a defer raising the event as today;
  the per-class mode (off, shadow, enforce) honored; the redacted decision log
  with the policy digest; the denial counts by floor entry and class; the
  shadow-versus-actual comparison report the hub reads, and the one-line
  evidence summary per class it brings the operator as the gate for enforcing
  that class; the token-shape scan of the log.
- **Done when:** in shadow no answer is sent and the log records the engine's
  verdict beside the actual answer; in enforce an allowed prompt is answered
  with no event raised, a deferred one raises the event unchanged, and a floor
  act is denied with a message; the answer-owner check has landed before this
  wiring is enabled; the comparison report is produced from a fixture log; the
  log scan fails on a planted token-shaped value; the kill switch returns
  today's behavior; a fixture run counts the denials by entry.
- **Dependencies:** Task 3
- **Citations:** D-4, D-6, D-14 · REQ-C1.6, REQ-C1.8, REQ-C1.9, REQ-I1.2,
  REQ-I1.4
- **Estimated effort:** 3 days

### Task 5 — The event dedupe gate and routine coalescing

- **Deliverables:** The gate verb at the event-append point keyed by kind,
  subject, state version and sequence; the repeat, stale and off-order drops;
  the never-drop rule for the first decision, blocker, failure and landed
  event; delivery on unreadable state; the drop ledger and the
  over-keen-gate event; the routine coalescing window per session and the
  no-timer-wake rule; fixtures for each, written first.
- **Done when:** a repeat inside the horizon, a stale event and an off-order
  event are each dropped and counted; the first decision, blocker, failure or
  landed event is delivered; an event whose state is unreadable is delivered;
  routine events inside one window produce one wake; the over-keen event fires
  on a fixture that drops past the configured share; the ledger holds keys and
  no payload; the suite runs in CI.
- **Dependencies:** Task 2
- **Citations:** D-8 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 3 days

### Task 6 — Slice two design walk: the queue (human-gated amendment)

- **Deliverables:** A walked amendment of this bundle that turns the queue
  outline into full requirements and decisions: the row schema, the lock and
  rebuild mechanics, the relation to the existing operator queue and
  orchestration marker, the cross-spec edge read (D-17) and the main-versus-side
  rule (D-18) settled, and the measured result of slice one recorded against
  the baseline.
- **Done when:** the amendment is signed off by the operator through the
  kickoff ritual, the slice-one measured change is recorded (REQ-E1.2), and
  the slice-two build tasks are rewritten from stubs to full definitions.
- **Dependencies:** Task 4, Task 5
- **Citations:** D-11, D-13, D-17, D-18 · REQ-A1.5, REQ-E1.2
- **Estimated effort:** 1 day

### Task 7 — The queue store and its verbs (stub; after Task 6)

- **Deliverables:** The single versioned, locked store of unit and pull request
  rows written only through verbs, rebuildable from branch, pull request and
  merge evidence, with unit kinds of every sort.
- **Done when:** a store deleted and rebuilt from fixture evidence equals the
  original; an unknown format is refused; a hand edit is detected; to be
  tightened by the walk.
- **Dependencies:** Task 6
- **Citations:** D-11 · REQ-F1.1, REQ-F1.2
- **Estimated effort:** 4 days

### Task 8 — The dispatcher's admission rules (stub; after Task 6)

- **Deliverables:** Admission by landing order, work-in-progress limit, host
  ceiling and the account, load and memory holds, from policy data; the
  main-work and side-work hold per D-18; the refusal naming rule and blocker.
- **Done when:** a launch that breaks each limit is refused with the rule named
  and one that does not is admitted; the lower-ranked hold lapses per policy;
  to be tightened by the walk.
- **Dependencies:** Task 7
- **Citations:** D-11, D-18 · REQ-B1.5, REQ-F1.3
- **Estimated effort:** 3 days

### Task 9 — The launch seam: pins, fleet home and branch verification (stub; after Task 6)

- **Deliverables:** One launch seam every rung goes through, applying the
  environment pins, resolving the fleet home once, dispatching a petition, and
  verifying the worker's branch and worktree against the row.
- **Done when:** a launch through each rung carries the pins; the fleet home
  resolves under a plain marketplace install from a tower shell; a worker that
  committed on another branch is flagged; to be tightened by the walk.
- **Dependencies:** Task 7
- **Citations:** D-11 · REQ-F1.2, REQ-F1.4
- **Estimated effort:** 3 days

### Task 10 — Named lifecycle states, hooks and done-when checks (stub; after Task 6)

- **Deliverables:** The named queue states, operator-attached transition hooks
  from policy data, and the goal and done-when attribute with its
  confirmation.
- **Done when:** a configured hook runs on its transition and only then; a unit
  is not reported done until its confirmed check passes; to be tightened by
  the walk.
- **Dependencies:** Task 7
- **Citations:** D-11 · REQ-F1.5, REQ-F1.6
- **Estimated effort:** 3 days

### Task 11 — Slice three design walk: the reconciler (human-gated amendment)

- **Deliverables:** A walked amendment turning the reconciler outline into full
  requirements: the verb set and its order, the poller's host mechanism per
  platform, which existing scripts it wraps, and the slice-two measured result.
- **Done when:** signed off through the kickoff ritual, the slice-two measured
  change recorded, and the slice-three stubs rewritten to full definitions.
- **Dependencies:** Task 8, Task 9, Task 10
- **Citations:** D-12, D-13 · REQ-A1.5, REQ-E1.2
- **Estimated effort:** 1 day

### Task 12 — Reconciler core: sync, continuous-integration hygiene and retirement (stub; after Task 11)

- **Deliverables:** The level-triggered loop with the sync verb that refuses a
  diff beyond the pull request's own files, the start, cancel and
  no-double-run verbs, the macOS-on-draft run, the ready flip under policy once
  every check has finished, worker retirement on landing, and the refused-push
  rename with its limits.
- **Done when:** each verb is idempotent over a repeated or interrupted pass on
  fixtures; a sync that would sweep in unrelated files is refused; a refused
  push renames once to the exact name it names when that branch is absent and
  never with force, to a protected branch or twice; to be tightened by the walk.
- **Dependencies:** Task 11
- **Citations:** D-12, D-17 · REQ-G1.1, REQ-G1.7
- **Estimated effort:** 5 days

### Task 13 — Evidence recorded by machines (stub; after Task 11)

- **Deliverables:** Step records written from continuous integration and hooks,
  refusing a record whose start, head or outcome cannot be established, and the
  bounded watcher steps, context and cost readings and the adoption of a live
  session.
- **Done when:** a record with an invented start or a moved head is refused; a
  hung watcher step is stopped; a handover is triggered by a reading; to be
  tightened by the walk.
- **Dependencies:** Task 12
- **Citations:** D-12 · REQ-G1.2, REQ-G1.6
- **Estimated effort:** 4 days

### Task 14 — Procedure verbs and the event-only poller (stub; after Task 11)

- **Deliverables:** The idempotent procedure verbs (post-flip checks, merge
  order, stale pull requests, post-merge bookkeeping, why each unit waits) and
  the host-level poller that appends an event only on a change.
- **Done when:** each verb returns the same result when run twice; the poller
  appends nothing on an unchanged fixture state and one event on a change;
  to be tightened by the walk.
- **Dependencies:** Task 12
- **Citations:** D-12 · REQ-G1.3, REQ-G1.4
- **Estimated effort:** 4 days

### Task 15 — Landing under the merge mode and release follow-through (stub; after Task 11)

- **Deliverables:** The reconciler's landing step under the merge mode (prepare
  and report by default; a recorded, re-checked merge only where configured),
  the release label advance after a publish, and the dropped-release event.
- **Done when:** with the operator merging, no merge is ever performed; a
  configured reach merges only an eligible pull request and records the act; a
  spec pull request and a pull request with an open sign-off item are never
  merged; the release label advances after a publish on a fixture; to be
  tightened by the walk.
- **Dependencies:** Task 12
- **Citations:** D-10, D-12 · REQ-B1.7, REQ-G1.5
- **Estimated effort:** 4 days

### Task 16 — Slice four design walk: briefs from state and a thin hub (human-gated amendment)

- **Deliverables:** A walked amendment turning the slice-four outline into full
  requirements: the brief generation, the decision packet shape and its answer
  record, the optional-supervisor topology, the per-wake tier policy, and the
  slice-three measured result.
- **Done when:** signed off through the kickoff ritual, the slice-three measured
  change recorded, and the slice-four stubs rewritten to full definitions.
- **Dependencies:** Task 13, Task 14, Task 15
- **Citations:** D-13 · REQ-A1.5, REQ-E1.2
- **Estimated effort:** 1 day

### Task 17 — Brief generation and queue reporting (stub; after Task 16)

- **Deliverables:** A worker launched from a queue row with a brief generated
  from state and kept in the program home, reporting back to the queue.
- **Done when:** a brief is generated from a fixture row and survives the loss of
  a scratch directory; the worker's report updates the row; to be tightened by
  the walk.
- **Dependencies:** Task 16
- **Citations:** D-13 · REQ-H1.1
- **Estimated effort:** 3 days

### Task 18 — The decision-packet renderer and answer record (stub; after Task 16)

- **Deliverables:** One packet per decision built from state (what it is, why
  it matters, options, recommendation, evidence links, the cadence line) and
  the recording of the operator's answer against the row.
- **Done when:** a fixture decision renders one packet with every field and the
  answer is recorded on the row; nothing reaches the operator outside the
  render gate; to be tightened by the walk.
- **Dependencies:** Task 16
- **Citations:** D-13 · REQ-H1.2
- **Estimated effort:** 3 days

### Task 19 — The thin hub, optional supervisors and per-wake tiers (stub; after Task 16)

- **Deliverables:** The hub launching workers from the queue directly, the
  supervisor made optional, the per-wake-class tier policy with a triage tier,
  and the size-resolved launch effort.
- **Done when:** a program with no standing supervisor runs a fixture unit to
  landing; a wake class resolves its tier from policy data; a size hint
  resolves the effort; to be tightened by the walk.
- **Dependencies:** Task 17, Task 18
- **Citations:** D-13 · REQ-H1.3, REQ-H1.4
- **Estimated effort:** 4 days

### Task 20 — Rule retirement against proof (stub; after Task 16)

- **Deliverables:** The enforcement field on every standing rule, the doctor
  listing the prose-only ones, the state-source map's platform class, and the
  retirement of each prose rule whose code home has landed with its proving
  check.
- **Done when:** the doctor lists the prose-only rules on a fixture store; a
  rule is retired only with its proving check green; to be tightened by the
  walk.
- **Dependencies:** Task 19
- **Citations:** D-2 · REQ-A1.4, REQ-H1.5
- **Estimated effort:** 3 days

### Task 21 — A program reads each repository's own spec root (stub; after Task 6)

- **Deliverables:** The program reader verb returning each listed repository
  with its resolved root, the root field optional (set wins, old configurations
  byte-identical), per-repository posture, the validation finding for a refused
  or missing root, the ambiguity refusal naming both roots, and the options
  rows. Tests of each.
- **Done when:** a program with the root set reads byte-identically to before;
  an unset one resolves each repository's own root; an ambiguous spec name is
  refused naming both roots; a refused root is flagged naming the repository;
  to be tightened by the walk.
- **Dependencies:** Task 6
- **Citations:** D-20 · REQ-F1.7, REQ-F1.8
- **Estimated effort:** 1.5 days

### Task 22 — The readers take the verb and a check closes the seam (stub; after Task 21)

- **Deliverables:** The queue, the readiness check and the deadline scan moved
  onto the verb; the repository-scoped check that fails on a direct read of the
  program's root field; the skill prose and docs; a test that the resolver and
  the work-repository registry are untouched and no root registry is written.
- **Done when:** a three-repository program scans each repository from its own
  root; the check goes red on a seeded direct read; to be tightened by the walk.
- **Dependencies:** Task 21, Task 7
- **Citations:** D-20 · REQ-F1.8, REQ-F1.9
- **Estimated effort:** 1.5 days

### Task 23 — Panel: titles, all work in motion and current steps (stub; after Task 16)

- **Deliverables:** The panel naming every item by title with no identifiers,
  the in-flight section read from the queue (grouped, with state, why waiting
  and age, items needing the operator first), the step hook and fixed step
  vocabulary, the merge command moved into the opened detail. A screenshot of
  the real panel over fixture data for the operator.
- **Done when:** fixtures show no identifier in any row; a waiting item says
  why; a step older than its state is not shown; the screenshot is shown and
  the operator's yes recorded before the pull request leaves draft; to be
  tightened by the walk.
- **Dependencies:** Task 17
- **Citations:** D-21 · REQ-H1.6, REQ-H1.9
- **Estimated effort:** 4 days

### Task 24 — Panel: instruments, usage, spend and progress (stub; after Task 16)

- **Deliverables:** The instrument row, the usage fuel bar with reset time,
  dollar spend and the optional monthly budget, spec progress and
  pull-request pipeline counts from aged snapshots off the redraw path, and the
  screenshot for the operator.
- **Done when:** an unreadable reading draws unknown; a redraw never waits on a
  refresh; the screenshot is shown and the operator's yes recorded before the
  pull request leaves draft; to be tightened by the walk.
- **Dependencies:** Task 23
- **Citations:** D-21 · REQ-H1.7, REQ-H1.9
- **Estimated effort:** 5 days

### Task 25 — Panel: accessibility and the CI type check (stub; after Task 16)

- **Deliverables:** A symbol and a word for every state, no colour under
  `NO_COLOR` or the colour knob, a colour-blind-safe palette, the plain mode
  knob, and the panel mod's type check in CI with a seeded error it must fail
  on.
- **Done when:** the fixtures pass over every section; the type check goes red
  on the seeded error; the screenshot is shown and the operator's yes recorded
  before the pull request leaves draft; to be tightened by the walk.
- **Dependencies:** Task 24
- **Citations:** D-21 · REQ-H1.8, REQ-H1.9
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

- **Panel gaps not folded now.** A widget catalogue with per-operator on, off
  and order; density by guidance level and width layouts; drill-down keys on
  every section; the band leading by urgency; proposed sections (burn-rate
  sparkline, release, recent activity, other programs, observations backlog,
  presence); docs on what the panel API cannot draw. Deferred because: no
  operator has asked, each reshapes sections that do not yet exist, and
  they land as widgets once the panel tasks have. Confidence: medium.
  **Gate:** surfaced free-text condition — the operator asks to hide, reorder
  or resize a panel section, or Tasks 23 to 25 have landed.
  Citations: D-21.

## Out of scope

- **Merging, signing off and messaging a person by code.** Permanent: these are
  the operator's gates (REQ-A1.2); the engine's floor lists them. Citations:
  D-4; REQ-A1.2.
- **Choosing the implementation language.** Left to the universal-binary
  amendment; this bundle's contract is neutral. Citations: D-16; REQ-I1.3.
- **The open issues the map in `design.md` names as out of scope.** Each has
  its stated reason there. Citations: D-2.
