# Tower comms — Requirements

**Status:** Draft
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

A planwright tower talks to its operator the way a default chat does:
everything the fleet produces streams down as it happens, in whatever size
it arrives, in the framework's own vocabulary, and the operator is expected
to hold the context of every worker to answer any of it. That does not scale
past one worker, and the accumulator records how it fails: a blocked worker
sat nine hours on one unanswered prompt; four workers spent a night producing
nothing because their first prompts were never seen; near-identical relay
turns flooded a fleet review; the first turn after hours of autonomous work
was a ledger of identifiers instead of a picture of where things stood; the
operator asked what a test's ordinal meant three times before the tower
stopped saying it; standing decisions the operator gave were re-asked, or
answered by the tower's own judgment with no record that a rule existed.

This spec makes the tower the buffer between the fleet and the operator. The
tower keeps one durable queue of everything headed to the operator (news,
questions, actions it wants approval for, the operator's own requests, and
the operator's standing decisions), settles or merges what it can as events
land, secures the operator's attention before it asks, hands over one item at
a time with only the context needed to answer it, gives deeper context on
request and waits for it to land, and speaks as a developer on the team
would. The operator's load scales with the decisions only they can make; the
tower never drops an item and never buries itself.

The deliverable sits at four altitudes at once, recorded as D-1: the
conversation rules are doctrine, the operator queue is a capability every
tower session consumes, the store, script, and log are the mechanism, and a
standing decision is a local value. It is built smallest-first and measured:
the event log ships before the queue, real sessions are compared on the
log's scorecard, and the rules spread to other attended surfaces only on
measured evidence (D-15, D-16).
*(Cites: D-1, D-15, D-16; the invocation and the pinned seed claims
(Sources).)*

## Scope

### In scope

- The operator queue: one durable, ordered set of items headed to the
  operator, its five item kinds, its store, and the script that owns it.
- Settling and merging: what closes an item without the operator, how
  duplicates and contradictions collapse, and the evidence that counts.
- Attention and delivery: the knock, one item per turn, ordering by
  consequence, context on request, and the first turn after silence.
- The speech register the tower uses in conversation, and the test for a
  word it may say.
- Inbound capture: the operator's requests, questions, and standing
  decisions enter the queue in the turn they are said.
- Unattended operation: accumulation while the operator is away, the knock
  through the existing notification channel, and rebuild after a tower dies.
- The event log, the scorecard, and the experiment that decides whether the
  rules spread.
- The doctrine home for the conversation rules and the instruction-budget
  change that lets the tower skills cite it.
- The tower sessions this governs: the single-spec `/orchestrate` tower, the
  meta-tower and `--fleet` loop, and the `/tower` front door once it ships.

### Out of scope

- Adoption of the conversation rules by `/spec-kickoff`, `/spec-draft`,
  `/resume`, and `/drain`. Gated on the experiment (`tasks.md` Deferred);
  the operator-dialogue bundle keeps ownership of those surfaces' turn shape
  meanwhile.
- Durable tracking and closure of items the operator owes or is owed. Owned
  by the action-item-ledger bundle; this queue writes to it and reads from
  it, and carries the ledger's pre-ship fallback rather than a substitute.
- Worker permission allowlists, guard shapes, and the relay volume they
  cause. Owned by worker-permission-ergonomics; this spec only decides how a
  prompt that does reach the tower is handled.
- The truth of a worker's liveness or completion. Owned by
  fleet-lifecycle-closure and the stream-json fixes; this spec treats those
  events as claims until evidence backs them.
- Notification channel adapters and message transport. Owned by the
  attention capability and fleet-messaging; this spec pushes through the
  existing seam and adds no channel.
- Any change to the reserved human controls: never auto-merge, never mark a
  PR ready without the operator's answer, never force-push, amend, squash,
  or rebase. Permanent.
- Any weakening of artifact completeness: the queue changes what a turn
  shows, never what the bundle, the PR body, or the audit record contains.
  Permanent.

## REQ-A — The operator queue

- **REQ-A1.1** Every item headed to the operator SHALL be held in one
  operator queue, and no such item SHALL exist only in conversation prose.
  *(Cites: D-2, D-3; obs:95b7a18d.)*
- **REQ-A1.2** An item SHALL be one of five kinds: news (nothing needed from
  the operator), question (an answer only the operator can give), approval
  (an action the tower proposes to take), request (something the operator
  asked for), and standing decision (a rule the operator declared). Each
  item SHALL state what closes it.
  *(Cites: D-4; drafting-session decision (2026-09-08).)*
- **REQ-A1.3** An item's content SHALL live in the durable home its kind
  already has (a worker's question in the owning spec's Awaiting-input
  list and the worker attention store; a request or standing decision in
  the action-item ledger or its pre-ship fallback; news in the attention
  store), and the queue store SHALL hold only the index and the delivery
  state: order, urgency, knocked, delivered, acknowledged, shelved, and what
  settled what.
  *(Cites: D-3; storage-classes doctrine (Sources).)*
- **REQ-A1.4** The queue store SHALL live under the cross-spec fleet home,
  SHALL be written only under the fleet advisory lock, and SHALL survive the
  death of the tower session that wrote it, so that a successor tower
  resumes the same queue.
  *(Cites: D-2, D-3; drafting-session decision (2026-09-08).)*
- **REQ-A1.5** Losing the queue store SHALL cost at most a repeated delivery:
  a successor tower SHALL rebuild the queue from the content homes, and no
  item content SHALL be recoverable only from the store.
  *(Cites: D-3; storage-classes doctrine (Sources).)*
- **REQ-A1.6** Queue records SHALL be single-line, constrained-field records
  with a stable identifier, validated against a declared grammar before any
  write, and every rendered value SHALL pass the echo-safety sanitizer.
  *(Cites: D-4; security-posture doctrine (Sources).)*

## REQ-B — Settling and merging

- **REQ-B1.1** Before any item is delivered, the tower SHALL run the queue
  against the events that arrived since the last pass, and an item whose
  closing condition is now met SHALL be settled with a record naming what
  settled it.
  *(Cites: D-5; obs:5756e0af.)*
- **REQ-B1.2** Only evidence SHALL settle an item: an open or merged PR,
  commits on the branch, a closed ledger item, a worker's question answered
  by another route, or a matching written standing decision. A worker's own
  report of completion or success SHALL NOT settle an item.
  *(Cites: D-5; obs:b23d6ea9, obs:05313aff, obs:6712b6d1.)*
- **REQ-B1.3** Items asking the operator the same thing SHALL be merged into
  one item that names every source; items whose answers would contradict
  each other SHALL be delivered together as one decision.
  *(Cites: D-5; obs:332374a2.)*
- **REQ-B1.4** An item the tower settles without the operator SHALL be
  recorded with its reason and SHALL be available on request and in the
  catch-up after an absence; it SHALL NOT be pushed at the operator.
  *(Cites: D-8; drafting-session decision (2026-09-08).)*
- **REQ-B1.5** Mentioning an item in a turn SHALL NOT count as the operator
  deciding it; an item is decided only when the operator's reply closes it
  or a written standing decision covers it.
  *(Cites: D-5, D-12; obs:4b14e93a.)*

## REQ-C — Attention and delivery

- **REQ-C1.1** The tower SHALL obtain the next item from the queue script,
  which SHALL hand over at most one item per call, so that the number of
  items in a turn is bounded by mechanism rather than by instruction.
  *(Cites: D-6; autopilot-reflex doctrine (Sources).)*
- **REQ-C1.2** Delivery SHALL be knock first: one line naming the kind and
  urgency of what is waiting, then nothing more until the operator replies.
  Item content SHALL NOT be delivered before the operator has confirmed
  attention.
  *(Cites: D-6, D-7; drafting-session decision (2026-09-08).)*
- **REQ-C1.3** A delivered item SHALL be answerable from the delivering
  message alone, with the shortest context that makes it answerable; deeper
  context SHALL be given one layer at a time on request, and the tower SHALL
  wait for a reply after each layer.
  *(Cites: D-6; interaction-style doctrine (Sources).)*
- **REQ-C1.4** Any reply from the operator SHALL release the next item;
  the tower SHALL NOT volunteer a second item before the operator has
  replied to the first.
  *(Cites: D-6; drafting-session decision (2026-09-08).)*
- **REQ-C1.5** Items SHALL be ordered by consequence: blocked workers first,
  then approvals, then the operator's requests, then news; within a kind,
  higher urgency first, then oldest first.
  *(Cites: D-6; attention-notification-capability doctrine (Sources).)*
- **REQ-C1.6** The operator MAY shelve an item with a reply meaning "later";
  a shelved item SHALL return on its own after a bounded interval and SHALL
  never be dropped by shelving.
  *(Cites: D-6; research: ISA-18.2 shelving (Sources).)*
- **REQ-C1.7** A news item SHALL carry an urgency; an urgent news item MAY
  knock, but its content SHALL be delivered only once attention is
  confirmed, and a non-urgent news item SHALL wait for the operator's next
  engagement or request.
  *(Cites: D-7; drafting-session decision (2026-09-08).)*
- **REQ-C1.8** After an autonomous stretch with no operator turn, the first
  attended turn SHALL explain where things stand in plain words and SHALL
  NOT report what the tower did; the record of what it did stays in the log
  and is available on request.
  *(Cites: D-6; obs:95b7a18d.)*

## REQ-D — Speech

- **REQ-D1.1** In conversation the tower SHALL write for a developer who
  knows planwright's basics: tower, worker, spec, task, PR, branch, and
  worktree need no explanation; store names, script names, spec identifiers,
  and doctrine terms SHALL be avoided or explained in plain words the first
  time they appear.
  *(Cites: D-10; obs:478f36fc.)*
- **REQ-D1.2** The tower SHALL name things by what the operator can see: a
  PR by its number and title, a branch by its name, a task by its title, a
  worker by its job. A label that denotes only a position in a file SHALL
  NOT be spoken.
  *(Cites: D-10; obs:478f36fc.)*
- **REQ-D1.3** The test for a word SHALL be taken from the listener's side:
  if answering "what is that?" would need the operator to open a file, it is
  not a word to say to them. When the operator asks what a name means, the
  name is the defect, and the tower SHALL drop it rather than explain around
  it.
  *(Cites: D-10; obs:478f36fc.)*
- **REQ-D1.4** Delivered text SHALL be lintable after the fact: every
  delivered item's text is in the event log, and the scorecard SHALL count
  spec identifiers, internal names, and doctrine terms in it.
  *(Cites: D-10, D-14; obs:478f36fc.)*

## REQ-E — Inbound capture and standing decisions

- **REQ-E1.1** Anything the operator says that asks for something SHALL
  become a queue item in the same turn, and the tower SHALL echo in one line
  what it recorded; no confirmation SHALL be required, and the operator
  corrects the echo only if it is wrong.
  *(Cites: D-11; operator-dialogue REQ-L1.1 (Sources).)*
- **REQ-E1.2** A request's content SHALL be written to the action-item
  ledger when it exists and to an observation fragment tagged as a capture
  until it does; the queue record SHALL point at that home.
  *(Cites: D-11; operator-dialogue REQ-L1.2 (Sources).)*
- **REQ-E1.3** A reply meaning "always" or "from now on" SHALL become a
  standing decision: a ledger item of the standing kind (an observation
  fragment tagged as standing until the ledger ships) carrying the rule in
  the operator's words, what it covers, and when it was said.
  *(Cites: D-11; obs:4b14e93a, obs:fea82b1c.)*
- **REQ-E1.4** Whenever the tower settles an item against a standing
  decision, the settling record and the log SHALL name that decision, so
  every self-settled item traces to a rule the operator wrote.
  *(Cites: D-11, D-12; obs:4b14e93a.)*
- **REQ-E1.5** A worker's harness permission prompt MAY be answered from a
  standing decision only when the prompt falls strictly inside the written
  rule; a prompt outside every written standing decision SHALL reach the
  operator, and the tower SHALL NOT answer one from its own judgment.
  *(Cites: D-12; autonomous-safe-decision doctrine (Sources).)*
- **REQ-E1.6** An operator's question SHALL be answered in the turn; when the
  answer needs work, that work SHALL become a request item.
  *(Cites: D-11; drafting-session decision (2026-09-08).)*

## REQ-F — Unattended operation and survival

- **REQ-F1.1** The tower SHALL treat the operator as away when a knock in
  the conversation receives no reply within a configured quiet interval,
  and as present again on any reply; the interval SHALL be a config knob
  with a documented default.
  *(Cites: D-9; drafting-session decision (2026-09-08).)*
- **REQ-F1.2** While the operator is away, a knock SHALL also go through the
  configured notification channel via the existing notification seam; a
  channel of `none` leaves the item in the queue.
  *(Cites: D-9; attention-notification-capability doctrine (Sources).)*
- **REQ-F1.3** An away knock SHALL fire once when the first blocking item
  appears and again only when the situation worsens: more blocked workers,
  or a blocked item passing a configured age. It SHALL NOT repeat on a fixed
  schedule.
  *(Cites: D-9; research: PagerDuty acknowledgement timeout (Sources).)*
- **REQ-F1.4** Items SHALL accumulate and settle among themselves while the
  operator is away exactly as when present; nothing SHALL be dropped or
  auto-answered for lack of attention.
  *(Cites: D-5, D-9; obs:eea622de.)*
- **REQ-F1.5** A fresh tower session SHALL resume the queue from the store
  and the content homes at session start, and the operator's return SHALL
  be met with the REQ-C1.8 picture followed by the first item.
  *(Cites: D-3, D-6; tower-front-door REQ-F1.4 (Sources).)*

## REQ-G — Measurement and the experiment

- **REQ-G1.1** Every queue event (item born, settled, merged, knocked,
  delivered, acknowledged, shelved, and each operator reply) SHALL be
  appended as one line to an event log under the fleet home, never
  committed, with a schema version and a monotonic sequence.
  *(Cites: D-14; kickoff-dialogue doctrine (Sources).)*
- **REQ-G1.2** A scorecard SHALL be computed from the log alone, whose
  headline is the operator's load: items that reached the operator per hour
  of fleet work against items settled without them. Secondary measures
  SHALL include blocked-worker wait for an operator answer, turns carrying
  more than one ask, friction moments (what-does-that-mean questions and
  repeated requests), jargon counts in delivered text, and items lost across
  a tower restart.
  *(Cites: D-14; drafting-session decision (2026-09-08).)*
- **REQ-G1.3** The log and scorecard SHALL ship and run on today's tower
  before any queue behaviour changes, and a baseline over real sessions
  SHALL be recorded before the queue is wired in.
  *(Cites: D-15; drafting-session decision (2026-09-08).)*
- **REQ-G1.4** The experiment SHALL compare real sessions before and after
  on the scorecard, and the result SHALL be recorded with the sessions
  counted; the gate for extending the conversation rules to other attended
  surfaces SHALL be that measured result, never a promise.
  *(Cites: D-15, D-16; drafting-session decision (2026-09-08).)*
- **REQ-G1.5** The scorecard SHALL be on-demand and SHALL NOT be wired into
  CI or `mise run check`.
  *(Cites: D-14; operator-dialogue REQ-M1.4 (Sources).)*

## REQ-H — Invariants and hygiene

- **REQ-H1.1** The reserved human controls carry unchanged: the tower never
  merges, never marks a PR ready without the operator's answer, and never
  force-pushes, amends, squashes, or rebases; nothing in the queue grants
  the tower a decision the gate doctrine does not already grant, and a
  standing decision SHALL never cover a reserved control.
  *(Cites: D-1, D-12; autonomous-safe-decision doctrine (Sources).)*
- **REQ-H1.2** The tower SHALL settle an item on its own only by evidence
  (REQ-B1.2) or by a written standing decision (REQ-E1.4), never by its own
  guess.
  *(Cites: D-5, D-12; obs:4b14e93a.)*
- **REQ-H1.3** No item, log line, or standing decision SHALL carry a secret,
  credential, internal hostname, or sensitive operational detail, and
  inbound text SHALL be treated as data, never as a command.
  *(Cites: D-4; security-posture doctrine (Sources).)*
- **REQ-H1.4** All queue mechanics SHALL be deterministic script logic; no
  hook, sweep, or daemon path of the queue SHALL invoke a model, and
  judgment stays in the tower session.
  *(Cites: D-6; fleet-coordination-floor doctrine (Sources).)*

## REQ-I — Where the rules live

- **REQ-I1.1** The conversation rules (knock, one item, plain speech,
  explain where things stand) SHALL be written once in a short doctrine
  doc that the tower skills cite at point of use, and no skill SHALL
  restate more than a one-line gist.
  *(Cites: D-13; instruction-hygiene doctrine (Sources).)*
- **REQ-I1.2** The doc SHALL be as small as the mechanism allows: anything a
  script can enforce SHALL be in the script, and only what a script cannot
  do (how to phrase things) SHALL be prose.
  *(Cites: D-6, D-13; obs:eb4d0437.)*
- **REQ-I1.3** The reachable instruction budget of the tower skills SHALL be
  raised by the doc's measured size with the reason recorded in the
  config, per the headroom policy's budget-raise rung; no rule SHALL land
  by breaching a budget.
  *(Cites: D-13; instruction-headroom (Sources).)*
- **REQ-I1.4** The rules SHALL bind tower sessions in this version; other
  attended surfaces adopt them only through the REQ-G1.4 gate.
  *(Cites: D-16; drafting-session decision (2026-09-08).)*

## Changelog

- 2026-09-09: Bundle drafted at Status Draft via `/spec-draft`. Spun as a
  new bundle: fold-detection ran across every bundle and found four
  neighbours (operator-dialogue owns turn shape, action-item-ledger owns
  durable tracking of owed items, the attention capability owns the worker
  decision queue, tower-front-door owns the tower's push posture); the
  spin-new triggers fire (a new operator-facing interface, independently
  ownable, an orthogonal decision space), so each is cited as a Source
  rather than extended. Consumes obs:95b7a18d, obs:4b14e93a, obs:9dfdea07,
  obs:1647f9ed, obs:b86077b3; obs:478f36fc is cited and consumed once its
  chore branch lands. D-1 through D-16 recorded; Tasks 1 through 10
  defined.

## Sources

- **The invocation (2026-09-08)** — the operator's framing: the tower should
  keep a queue of items to relay, resolve them internally as events happen,
  secure the operator's attention, ask one question at a time with the
  necessary context, transmit context after asking and wait for it to be
  absorbed, absorb as much cognitive load as possible, never lose track
  when the operator makes requests or asks questions. Pinned seed claim
  (altitude): the deliverable is a principle (the tower absorbs cognitive
  load), with the queue "just a suggestion" for its mechanism.
- **The operator's addendum (2026-09-08)** — the tower should communicate as
  the average software developer would, avoid internals, spec identifiers,
  and words a human would never remember or use. Pinned seed claim
  (altitude): a rule about how the tower speaks, framework-wide in nature.
- **Drafting-session decisions (2026-09-08)** — the operator's answers during
  elicitation: scope to tower sessions with an experiment deciding the
  boundary; a durable store of the queue's own; standing decisions in scope
  minimally with the mechanism chosen by experiment; urgent news knocks but
  delivers only on confirmed attention; self-settled items available, never
  pushed; any reply releases the next item; the register of a developer who
  knows planwright's basics; one-line echo without confirmation; away knocks
  once and again only on worsening; the headline measure is the operator's
  load; a standing decision may answer a permission prompt strictly inside
  its rule; the rules live in a small doc with the budget raised by its
  size; content in existing homes with delivery state under the fleet home;
  standing decisions as ledger items; a sibling queue above the worker
  attention store; away detection by a configurable quiet interval; the log
  ships first with baseline sessions before the queue.
- **obs:478f36fc** — the plain-speech rule covered every artifact surface and
  not conversation; the doctrine edit could not land for budget. Cited;
  the fragment lives on an unmerged chore branch, so it is consumed by this
  bundle once it reaches main.
- **obs:95b7a18d** — after an autonomous stretch the first attended turn
  reported the agent's own work instead of teaching the current state.
  Consumed.
- **obs:4b14e93a** — standing operator policy is unmodelled; surfacing in a
  turn is not the operator deciding. Consumed.
- **obs:9dfdea07** — a park note promised an automatic step the contract
  forbids; an ask must name the human action that resolves it. Consumed.
- **obs:1647f9ed** — the intervention contract's enumeration is incomplete
  and its site is owned by no task. Consumed.
- **obs:b86077b3** — the attention capability doc's writer enumeration is
  stale. Consumed.
- **obs:eb4d0437**, **obs:37c2711e**, **obs:14d6ef9f** — the attended-surface
  instruction budgets are saturated; the tower's relay bullet was condensed
  to pay for other words. Evidence for REQ-I; owned by instruction-headroom.
- **obs:8b0691cd**, **obs:65c35236**, **obs:332374a2**, **obs:1f1141ec**,
  **obs:01629047**, **obs:eea622de** — the measured cost of every item put
  in front of the operator and the volume of near-identical relay turns.
  Evidence for REQ-B and REQ-G; owned by worker-permission-ergonomics.
- **obs:8a99fb7d**, **obs:b23d6ea9**, **obs:05313aff**, **obs:6712b6d1** — a
  worker's reports and result frames lie about completion. Evidence for
  REQ-B1.2; owned by fleet-lifecycle-closure and the stream-json fixes.
- **obs:2e9b7741**, **obs:77e452b4**, **obs:ff5ca260**, **obs:5756e0af** —
  the moment of decision is illegible and a queued question nothing
  liquidates. Evidence for REQ-B1.1 and REQ-C1.3; owned by gate-wiring and
  polish.
- **obs:87570535**, **obs:fea82b1c**, **obs:7bc2494a** — operator requests
  and decisions with no durable home; things the tower must remember by
  hand. Evidence for REQ-E; owned elsewhere.
- **obs:c24a01af**, **obs:7e67fe74** — the tower's own headroom signal has
  no producer and misled it once. Evidence for the Out-of-scope boundary;
  owned by model-allocation.
- **Legacy observations (`specs/_observations/opportunities.md`, unconsumed)**
  — the human-comprehension decision domain gap (since catalogued), inbox
  and dashboard states as a first-class surface, the attention store versus
  coordination registry naming, and a silently dropped human decision on
  the attention surface.
- **Prior bundles**: operator-dialogue (the interaction disciplines, the
  turn/artifact arbitration, capture at birth: REQ-L1.1, REQ-L1.2, REQ-M1.4),
  action-item-ledger (Draft; the durable home for requests and standing
  decisions), orchestration-fleet and fleet-autonomy (the attention store,
  the decision queue, the fleet home and lock), fleet-hardening (the
  answerable fork and claim primitives), tower-front-door (the tower's push
  posture, REQ-F1.4 reconstruction), fleet-messaging (transport, out of
  scope here), instruction-headroom (the budget-raise rung),
  worker-permission-ergonomics and fleet-lifecycle-closure (owners of
  adjacent fixes).
- **Doctrine consulted**: `interaction-style`, `kickoff-dialogue`,
  `attention-notification-capability`, `autonomous-safe-decision`,
  `fleet-coordination-floor`, `orchestration-modes`, `storage-classes`,
  `accumulator-taxonomy`, `instruction-hygiene`, `context-budget-autoheal`,
  `autopilot-reflex`, `engineering-decisions`, `customization-boundary`,
  `decision-domains` (queues and async work, concurrency, human
  comprehension and information UX, existing-seam reuse),
  `research-rigor`, `security-posture`, `proportionality`, `spec-format`.
- **Research: ISA-18.2 (IEC 62682) alarm management** — every annunciated
  alarm must be actionable; acknowledgement is logged; shelving is
  time-limited with automatic return; suppression by design traces to a
  documented philosophy. Consulted 2026-09-09: the ISA-18 series page
  (isa.org), the Emerson alarm-rationalization white paper, and the
  ANSI/ISA-18.2-2016 standard text.
- **Research: PagerDuty incident semantics** — acknowledging halts
  escalation; an acknowledged incident re-triggers after an acknowledgement
  timeout; an unacknowledged one escalates after an escalation timeout.
  Consulted 2026-09-09: PagerDuty support docs on expected notification
  behaviour, incidents, and escalation policies.
