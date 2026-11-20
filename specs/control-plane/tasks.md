# Control plane — Tasks

**Status:** Ready
**Last reviewed:** 2026-11-19
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 1 to 5.4 are slice one, specified in full (Tasks 5.1 to 5.4 are the
request ledger). Each later slice opens with a
design walk task (a human-gated amendment of this bundle); its build tasks are
stubs until that walk turns the outline into full requirements, and a stub's
fields are a starting point the walk may rewrite. Every policy task starts with
its failing fixtures (REQ-I1.1). Slice one is written in shell behind a neutral
contract (D-16), so nothing waits on the language decision. A stub is not
dispatchable until its slice's walk task rewrites its Done-when; the walk
tasks' dependency edges make that mechanical. REQ-A1.1 to REQ-A1.3, REQ-A1.6
and REQ-E1.3 hold across every task and are checked where Tasks 2, 3 and 5
name them.

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
- **Citations:** D-9, D-15 · REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 1 day

### Task 2 — Policy data: schemas, shipped catalogs, floor and the kill switch

- **Deliverables:** The schemas and shipped core seeds for the approval classes
  (with their modes and scope predicates), the approval floor, the dedupe
  horizons and windows, and the merge-mode reach; the schema check wired into
  CI and at load; the layering through the catalog and configuration
  resolvers; the `explain` verb; the kill-switch setting; the options-reference
  rows. The near-miss fixtures for each class and the check that fails when a
  class has none (the fixtures ship here, the rules that satisfy them in Task
  3). A `doctrine/` document stating the three-layer line, the one-home rule
  and the asymmetric-failure rule, registered in the doctrine index, and the
  scans for a policy literal in code and a machine-specific value in a catalog
  or fixture.
- **Done when:** an entry failing its schema is dropped while the lower layers
  stay in force, and a class-bounding failure makes the class defer
  everything (both shown by fixture), the drop counted, shown by `explain`
  and exposed for the wake report Task 4 emits, naming its file and entry; a planted policy literal and a planted
  machine path each fail their scan; a changed policy value changes the
  digest; a machine-local `enforce` or merge-mode value is ignored and
  reported; the doctrine document is indexed and a check proves it and the
  mechanism name the same layers; a layer entry allowing a floor act fails
  the check by name; `explain` names the supplying layer for a fixture
  verdict; with the kill switch set in a shipped or adopter layer every verb defers, and a machine-local value of it is ignored and reported; the near-miss check
  fails against a class declared with no near-miss fixture and passes once one
  exists; the merge-mode reach value takes effect only from the shipped and
  adopter layers (a machine-local value is ignored and reported).
- **Dependencies:** none
- **Citations:** D-1, D-3, D-7, D-10, D-14 · REQ-A1.1, REQ-A1.4, REQ-B1.1,
  REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.6, REQ-B1.7 (layer restriction only;
  merge eligibility is Task 15), REQ-C1.7, REQ-I1.2
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
- **Done when:** a test or lint command naming a path outside the worktree, a
  full suite, a rewriting lint and a CI wait with no bound each return defer;
  every class's allow fixtures return allow and every near-miss
  fixture returns defer or deny as recorded; every floor act returns deny with
  a message naming its entry and a bare deny is never emitted; every input with
  a substitution, an unreadable construct, an unknown policy format, a request
  built from pane text or a missing request id defers; the engine opens no
  network socket and the engine, gate and dispatcher import no model client; no
  verb invokes a merge or sign-off helper outside the merge mode; an answer
  for a worker the caller's program does not own is refused and changes
  nothing, and an answer for a request no longer pending changes nothing and
  the answer line names the worker, program and first command; the fixtures
  hold no implementation-language code; the near-miss check has been shown to fail against a deliberately
  widened rule; the drift check fails on a command one classification admits
  and the other refuses; the write-time security pass for untrusted input,
  subprocess construction, path handling and authorization is recorded; the
  guard-catalog check lists the engine; the suite runs in CI.
- **Dependencies:** Task 2
- **Citations:** D-1, D-4, D-5, D-7, D-16, D-19 · REQ-A1.1, REQ-A1.2,
  REQ-A1.3, REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.7,
  REQ-C1.10, REQ-C1.11, REQ-I1.1, REQ-I1.3
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
  verdict beside the actual answer and its source, and an allow in shadow
  records its would-have answer; in enforce an allowed prompt is answered
  with no event raised, a deferred one raises the event unchanged, and a floor
  act is denied with a message; the wiring refuses to enable, and says so,
  when the answer-owner check is absent; the comparison report is produced
  from a fixture log, and a fixture with N matches and M mismatches yields a
  one-line summary per class carrying the counts and sample size with the
  mismatches listed on request, and a class with no records says so; no class
  mode moves from shadow without that summary; a log record holds its listed
  fields and a command within its bound; the log scan fails on a planted
  token-shaped value; the log is appended one locked line per record, shown by
  a separate-process concurrent-writer fixture, a torn-last-line fixture and a
  lock-timeout fixture; the kill switch returns today's behavior and a switch
  left on is reported at the wake, together with the count of dropped policy
  entries and each one's file and entry (read from the `explain` data Task 2
  exposes); a fixture run counts the denials by entry and class.
- **Dependencies:** Task 1, Task 3
- **Citations:** D-3, D-4, D-6, D-14 · REQ-A1.6, REQ-B1.3, REQ-C1.6, REQ-C1.8,
  REQ-C1.9, REQ-C1.11, REQ-I1.2, REQ-I1.4, REQ-I1.5
- **Estimated effort:** 3 days

### Task 5 — The event dedupe gate and routine coalescing

- **Deliverables:** The gate verb at the event-append point keyed by kind,
  subject, state version and sequence; the repeat, stale and off-order drops;
  the never-drop rule for the first decision, blocker, failure and landed
  event; delivery on unreadable state; the drop ledger and the
  over-keen-gate event; the routine coalescing window per session and the
  no-timer-wake rule; the rule that an event carrying an open request is
  never dropped and only coalesced, with its request ids attached to the
  coalesced event, and an echo of a closed one is dropped and counted, read
  from the class registry's request-bearing flag (Task 5.1) and the ledger's
  open set; fixtures for each, written first.
- **Done when:** a repeat inside the horizon, a stale event and an off-order
  event are each dropped and counted; the first decision, blocker, failure or
  landed event is delivered; for an operator message, a cross-session message
  and a request-bearing event kind, a repeated, a stale and an off-order event
  are each delivered, never dropped, while its request is open, and each is
  dropped and counted as a drop once the ledger has closed every request it
  carries (a fixture ledger seeded with close records); a burst of
  open-request events inside one window yields one coalesced event carrying
  every request id, counted as coalesced and not as a drop; an event whose
  state is unreadable is delivered;
  routine events inside one window produce one wake; the over-keen event fires
  on a fixture that drops past the configured share and is itself never
  dropped; a stale first failure event is delivered; every event writer calls
  the gate (a check); an idle session is not woken by a timer; with the kill
  switch set the gate delivers everything; the ledger holds keys and no
  payload and the token-shape scan passes over it; the ledger is appended one
  locked line per record, shown by the same concurrent-writer and
  torn-last-line fixtures; the suite runs in CI.
- **Dependencies:** Task 1, Task 2, Task 5.1
- **Citations:** D-8, D-27 · REQ-A1.3, REQ-D1.1, REQ-D1.2, REQ-D1.4,
  REQ-D1.5, REQ-D1.6, REQ-I1.2, REQ-I1.4, REQ-I1.5
- **Estimated effort:** 3.5 days

### Task 5.1 — The request ledger store and its capture seams, probe first

- **Deliverables:** A probe, recorded in a research note, of which hook sees
  each kind of arrival (an operator prompt, a delivered cross-session message,
  a pane relay, a stream-json steer) on each launch rung, and whether a sender
  can name the receiver's program. The ledger: the append-only monthly log in
  the program's knowledge base through the existing segment writer (arrival,
  link and close records, the derived open set, the id form the handover
  picture takes); the arrival record's fields with the bounded, sanitized,
  redacted excerpt and the transcript pointer. The capture seams: the
  prompt-submit hook for sessions that hold a program name, the event writer
  for request-bearing kinds (a request-bearing column added to
  `config/mc-event-classes.tsv` with its reader, the pending prompt and the
  relayed question flagged), the two send scripts and a hook on the model's
  send tool, the skip of composer-written and hook-injected text; the linker;
  the per-session spool and its capture-failed event; the doctor line for a
  kind no seam sees; the redaction and pattern check over the stored log; a
  check that no skill instruction asks the model to write an arrival; the
  ledger's knobs in `config/defaults.yml` with their options rows (the
  excerpt bound and the link window; scalars, so this task needs none of
  Task 2's catalogs). Fixtures first, derived from the committed probe note.
- **Done when:** the probe note is committed and names, per launch rung, the
  seam that sees each arrival kind and whether the sender can name the
  receiver's program; an operator prompt, a cross-session message and a
  request-bearing event each append one arrival with its own id and every
  field REQ-J1.4 lists before the receiving model turn acts on it, shown by
  fixture for each seam the probe found; composer-written and hook-injected
  text appends nothing; a session that holds no program name appends nothing;
  the registry's request-bearing column reads the two shipped kinds as
  flagged and an unflagged kind as not; the no-model-write check goes red on
  a seeded instruction; one message seen on both sides
  yields two sightings linked under one open request, and a pair the linker
  cannot match stays two open requests; two identical messages sent in one
  burst keep two ids; a failed append leaves a spool line with its id counted
  as open, is retried at the next capture and at the next wake, raises its
  event and never blocks or changes the prompt, and a held lock delays the
  prompt no longer than the hook's bound; a planted token in a message is
  redacted in the excerpt by the existing secret screen, a planted email
  address and phone number by the ledger's personal-data patterns, a token
  straddling the cut is still redacted, and the log's check fails on each
  planted past the screen; with the screen or the pattern pass failing or
  missing, the arrival is written with no excerpt, counted open, and a
  failure-class event raised; an excerpt past its bound is cut on a character
  boundary; a machine-local value of either ledger knob is ignored and
  reported while a shipped or adopter value is read; a separate-process
  concurrent-writer fixture and a torn-last-line fixture keep every record
  whole; a kind the probe found no seam for is named by the doctor; nothing
  is written inside a repository; the suite runs in CI.
- **Dependencies:** Task 1
- **Citations:** D-22, D-23, D-24 · REQ-J1.1, REQ-J1.2, REQ-J1.3, REQ-J1.4,
  REQ-I1.4, REQ-I1.5
- **Estimated effort:** 3 days

### Task 5.2 — Close with checked evidence, and the turn-end hold

- **Deliverables:** The close verb, owner-checked against the holder record,
  taking one or more ids and one evidence of the kinds D-25 names, each
  verified against its source before the close is written; the code close of
  a request-bearing event whose subject resolved by machine evidence; the
  `noask` listing in the next status; the turn-end hook's single hold with
  its `shadow` or `enforce` mode (shipped `shadow`, enforce read from the
  shipped and adopter layers only), its would-have-held record and the
  code-computed one-line summary the hub brings the operator; the verbs
  list, the mission-control skill's prose inside its instruction budget, and
  the guide.
- **Done when:** each evidence kind closes a fixture request when its source
  confirms it and is refused when it does not (an unmerged pull request; an
  answer older than the arrival or addressed to someone other than the
  sender; a quote absent from the cited message; a quote from a relay with no
  matching send record by the hub's live holder, while one typed into the
  session or from a matched hub relay closes; an unknown follow-up id; a
  repeat citing an unknown id, itself or a request closed as a repeat; an
  empty no-ask reason); a close with no evidence is refused; a close from a
  session that does not hold the program is refused; a fixture request aged
  past every window, its log line truncated and its event delivered and
  handed over stays open; a spooled arrival closes with the same verb; a
  close record's quoted words and reason are bounded and redacted; a pending
  prompt the stall watcher records as no longer pending closes by code as a
  machine evidence citing that record (and a seeded answer record); a `noask`
  close of an operator message appears in the next status; in `enforce`, a
  turn ending with an open request from that turn (the arrival that began
  it, or a spooled one) is held once, naming it, any later stop ends the
  turn, and the request is marked as held past a turn end; in the shipped
  `shadow` the same turn is not held and the would-have-held record names it;
  a machine-local `enforce` is ignored and reported; the summary is computed
  from that record; a turn whose requests are all closed is not held; with
  the kill switch set in a shipped or adopter layer
  the turn is not held and capture still appends; the instruction-budget and
  verbs checks pass; the suite runs in CI.
- **Dependencies:** Task 2, Task 5.1
- **Citations:** D-25, D-28, D-29 · REQ-J1.5, REQ-J1.6, REQ-J1.10,
  REQ-J1.12, REQ-I1.2
- **Estimated effort:** 2.5 days

### Task 5.3 — The handover refuses what the successor's picture lacks

- **Deliverables:** Verify, take, resume and the rules self-check reading the
  ledger's open set and spools from the store at the moment each runs; take's
  second read after the release wait; the refusal naming each missing id;
  take's backlog marking skipping events whose request is open; an unreadable
  ledger refusing the take through the existing handover failure; the
  refusal's `shadow` or `enforce` mode (shipped `shadow`, enforce read from
  the shipped and adopter layers only), its would-have-refused record and the
  code-computed one-line summary the hub brings the operator. The backlog
  marking's skip is not a refusal and runs from landing.
- **Done when:** in `enforce`, a successor's picture missing an open request
  fails verify, take, resume and the rules self-check, naming the id, and
  passes once the picture holds it; in the shipped `shadow` the same picture
  passes and the would-have-refused record names the id; a machine-local
  `enforce` is ignored and reported; the summary is computed from that
  record; in `enforce`, a request
  appended between a passing verify and the take refuses the take until a
  second verify includes it (the mid-handover relay as the fixture); a
  spooled arrival counts as open; a picture checked against a handover file
  that lacks a request the ledger holds still fails; take marks no event
  whose request is open; an unreadable ledger refuses the take with the
  handover's existing failure and leaves the predecessor holding the name;
  with the kill switch set in a shipped or
  adopter layer verify and take do not refuse on the ledger; the existing
  handover suites pass; the suite runs in CI.
- **Dependencies:** Task 2, Task 5.1
- **Citations:** D-26, D-28, D-29 · REQ-J1.7, REQ-J1.10, REQ-J1.12,
  REQ-I1.2
- **Estimated effort:** 2 days

### Task 5.4 — Every wake re-reads the ledger; the panel; the unanswered raise

- **Deliverables:** The one composer verb for the wake's open-request block
  and its call from every wake path, with the check that fails on a path that
  does not, the dedupe gate's coalesced wake included; the panel and
  text-panel line beside the overdue follow-ups; the `request-unanswered`
  event in the class registry (blocker class) raised by the keeper's sweep
  past each kind's window and repeated with a new state version each raise;
  the windows, the repeat interval and the wake-list bound as knobs in
  `config/defaults.yml` with their options rows (defaults per D-28); the
  kill-switch behavior of REQ-J1.10 for the unanswered raises, the
  capture-failure raises and the wake line (Tasks
  5.2 and 5.3 already stand down their refusals); the landing measures of
  REQ-J1.11 as machine-local data. A preview of the real panel and text panel
  rendered over fixture data, the unreadable state included, for the
  operator.
- **Done when:** a wake composed over a fixture ledger shows the count, then
  every open request oldest first with its sender, excerpt and age, a
  held-past-turn-end mark where set, a spooled arrival among them, and an
  "and N more" past the bound, and an unreadable ledger shows as unreadable;
  the check goes red on a seeded wake path that skips the composer; the panel
  line's render over fixture data shows the open count and the oldest
  request, and unreadable when the ledger is; with an injected clock, a
  request past its window raises one blocker event naming it, its sender,
  age and excerpt, handed to the notification channel once; with three
  requests overdue, each interval yields one combined repeat naming the open
  count and the oldest, delivered through the gate, until the last closes;
  neither renders as a routine line; a request closed before its window
  raises nothing; the shipped knob defaults equal D-28's, and a machine-local
  value of any of these knobs is ignored and reported while a shipped or
  adopter value is read; with the kill switch set, capture still appends,
  the unanswered raises stand down to one wake line naming the open count,
  and both capture-failure events (Task 5.1's failed append and failed
  redaction) are still raised; a fixture
  run writes the daily counts with their values only to the machine-local
  location; the operator has seen the preview and said yes before the pull
  request leaves draft; the suite runs in CI.
- **Dependencies:** Task 2, Task 5.1, Task 5.2, Task 5.3
- **Citations:** D-22, D-28 · REQ-J1.8, REQ-J1.9, REQ-J1.10, REQ-J1.11,
  REQ-D1.5, REQ-I1.2
- **Estimated effort:** 3 days

### Task 6 — Slice two design walk: the queue (human-gated amendment)

- **Deliverables:** A walked amendment of this bundle that turns the queue
  outline into full requirements and decisions: the row schema, the lock and
  rebuild mechanics, the relation to the existing operator queue and
  orchestration marker, a resource-claim field on the row (issue 343), the
  spec-roots reader (D-20) and the settled cross-spec edge read (D-17) and
  main-versus-side hold (D-18) turned into full requirements, and the measured
  result of slice one recorded against the baseline (a re-run of the baseline
  script after the shadow window, and the request ledger's measures of
  REQ-J1.11).
- **Done when:** the amendment is signed off by the operator through the
  kickoff ritual, the slice-one measured change is recorded (REQ-E1.2), and
  the slice-two build tasks are rewritten from stubs to full definitions.
- **Dependencies:** Task 4, Task 5, Task 5.4
- **Citations:** D-11, D-13, D-17, D-18, D-22 · REQ-A1.5, REQ-E1.2,
  REQ-J1.11
- **Estimated effort:** 1 day

### Task 7 — The queue store and its verbs (stub; after Task 6)

- **Deliverables:** The single versioned, locked store of unit and pull request
  rows written only through verbs, rebuildable from branch, pull request and
  merge evidence, with unit kinds of every sort.
- **Done when:** a store deleted and rebuilt from fixture evidence equals the
  original; an unknown format is refused; a hand edit is detected; a hard
  same-root edge is read, and an edge to an unreadable or other-root spec
  fails closed and is flagged; the token-shape scan passes over a fixture
  store; to be tightened by the walk.
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
- **Dependencies:** Task 8, Task 9, Task 10, Task 22
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
  never with force, to a protected branch or twice; the reconciler is listed in
  the guard catalog; to be tightened by the walk.
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
  record, the optional-supervisor topology, the per-wake tier policy, the
  panel requirements (D-21), the handover's reading of the queue and the
  request ledger together (D-22) and the slice-three measured result.
- **Done when:** signed off through the kickoff ritual, the slice-three measured
  change recorded, and the slice-four stubs rewritten to full definitions.
- **Dependencies:** Task 13, Task 14, Task 15
- **Citations:** D-13, D-22 · REQ-A1.5, REQ-E1.2
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
- **Done when:** a program with the root set reads byte-identically to a
  recorded golden output; an unset one resolves each repository's own root; an
  ambiguous spec name is refused naming every root that holds it; a refused or
  non-directory root is flagged naming the repository;
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
  vocabulary, the merge command moved into the opened detail. A script that
  renders the real panel over fixture data to a screenshot for the operator
  (reused by Tasks 24 and 25), and a check that a panel pull request body
  quotes the operator's yes.
- **Done when:** a scanner finds no identifier, hash, branch or path in any
  fixture row, and the merge command appears only in the opened detail; a
  waiting item says why and an overflow keeps operator-needed items first; a step older than its state is not shown; the screenshot is shown and
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

- **Task 4** Do the answer-owner draft and the operator-signed answer-verb
  fixes (Sources) land before the wiring is enabled? The wiring refuses to
  enable without the owner check.
- **Task 7** Has the local invariant-tasks amendment (Sources) settled the
  cross-spec edge syntax? The queue ships without cross-spec edges until it
  has.
- **Task 5.1** Has the mission-control bundle recorded its Task 51 (the
  intake rows, turn-end check and handover self-check of its REQ-F1.19) as
  carried by this spec (D-22)? Until it has, both bundles list the same work
  as undone and either could be dispatched for it; the hold sits on the
  first ledger task, so no ledger task starts before it clears.

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
- **Choosing the compiled-tier language.** Slice one is shell behind a neutral
  contract; a later rewrite is the universal-binary amendment's decision.
  Citations: D-16; REQ-I1.3.
- **The window-lock design for dropped releases** (issue 380) stays with the
  release-hardening spec. Citations: D-12.
- **The Done concurrency spec's text amendment** (issue 88). A Done spec's
  wording is its own amendment. Citations: D-11.
- **The open issues the map in `design.md` names as out of scope.** Each has
  its stated reason there. Citations: D-2.
