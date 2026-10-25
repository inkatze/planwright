# Tower comms — Requirements

**Status:** Ready
**Last reviewed:** 2026-10-25
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
  through the existing notification channel, the session-relayed `push`
  channel, and rebuild after a tower dies.
- The event log, the scorecard, and the experiment that decides whether the
  rules spread.
- The doctrine home for the conversation rules and the instruction-budget
  change that lets the tower skills cite it.
- The tower sessions this governs: the single-spec `/orchestrate` tower, the
  meta-tower and `--fleet` loop, and the `/tower` front door once it ships.
- The queue changes mission control depends on (added 2026-10-25): a
  presence input a producer writes, with the quiet interval as its
  fallback; picklist windows that end on a declared default or a park; two
  reviewable item kinds, settled-by-default and decided-by-mission-control;
  the rule that nothing leaves the queue except by an answer or by evidence,
  with the reason recorded; and delivery batched by subject.

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
  existing seam and adds no channel of its own, with one carve-out: the
  session-relayed `push` channel of REQ-F1.6, which carries no transport
  and only marks a file the tower session relays.
- Any change to the reserved human controls: never auto-merge, never mark a
  PR ready without the operator's answer, never force-push, amend, squash,
  or rebase. Permanent.
- Any weakening of artifact completeness: the queue changes what a turn
  shows, never what the bundle, the PR body, or the audit record contains.
  Permanent.
- The presence producer itself (the mission-control panel and its prompt
  events), when mission control may decide on its own, and running the
  reversal of a decision it took. Owned by mission-control; this spec only
  reads the presence marker, records the decision as a reviewable item, and
  carries the pointer to its reversal.

## REQ-A — The operator queue

- **REQ-A1.1** Every item headed to the operator SHALL be held in one
  operator queue, and no such item SHALL exist only in conversation prose.
  *(Cites: D-2, D-3; obs:4b14e93a.)*
- **REQ-A1.2** An item SHALL be one of five kinds: news (nothing needed from
  the operator), question (an answer only the operator can give), approval
  (an action the tower proposes to take), request (something the operator
  asked for), and standing decision (a rule the operator declared). Each
  item SHALL state what closes it. A standing decision SHALL be registered
  in the queue but SHALL never be delivered and never ranked for delivery,
  and what closes it SHALL be the operator's revocation of the rule.
  **Superseded-by: REQ-A1.10** (2026-10-25) — two reviewable kinds join the
  closed set.
  *(Cites: D-4; drafting-session decision (2026-09-08); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-A1.10** (supersedes REQ-A1.2) An item SHALL be one of seven kinds:
  the five REQ-A1.2 names (news, question, approval, request, and standing
  decision), each with the closing condition REQ-A1.2 gives it, plus
  settled-by-default (a question whose picklist window ended on its declared
  default, which was applied without the operator, REQ-A1.12) and
  decided-by-mission-control (a decision a mission-control session took on
  its own, recorded with its grounds, REQ-A1.14). Each item SHALL state what
  closes it. The two new kinds SHALL be visible (listed, counted, and
  delivered for review once the operator is present, never pushed while
  away) and reversible (each carries what reverses it), and what closes
  either SHALL be the operator's acknowledgement of the review or their
  revocation (REQ-B1.8). A standing decision SHALL be registered in the
  queue but SHALL never be delivered and never ranked for delivery, and what
  closes it SHALL be the operator's revocation of the rule.
  *(Cites: D-20; mission-control D-7, D-22 (Sources); drafting-session
  decision (2026-10-25).)*
- **REQ-A1.3** An item's content SHALL live in the durable home its kind
  already has: a worker's question in the worker attention store and, when
  parked, the owning spec's Awaiting-input bullet; a request, an approval,
  or a standing decision in the action-item ledger or, until that ledger
  ships, in the pre-ship fallback (a machine-local, untracked, owner-only
  ledger-shaped file under the fleet home holding captured requests,
  approvals, and standing decisions); news in the attention store. The queue
  store SHALL hold only the index and the delivery state: order, urgency,
  knocked, delivered, acknowledged, shelved, and what settled what. Content
  SHALL be written to its home before the index record that points at it,
  and a record pointing at an attention-store row SHALL carry that row's
  instance identifier, on whose mismatch `next` SHALL refresh the pointer or
  refuse the hand-over. The store SHALL hold the open items plus the closed
  ones (acknowledged or settled) inside the catch-up window, dropping a
  closed record once it falls past that horizon.
  *(Cites: D-3, D-11; storage-classes doctrine (Sources); kickoff sign-off
  lens (2026-09-09); delta re-walkthrough (2026-09-17).)*
- **REQ-A1.4** The queue store SHALL live under the cross-spec fleet home,
  SHALL be written only under the fleet advisory lock, and SHALL survive the
  death of the tower session that wrote it, so that a successor tower
  resumes the same queue. The store, the event log, the attention markers,
  and the pre-ship fallback SHALL be created owner-only inside a `0700`
  sub-surface of the fleet home, whose mode SHALL be verified before a write
  and the write refused when it does not hold. Every verb SHALL bound its
  wait for the lock by the `tower_hook_lock_wait` knob and SHALL report the
  expiry of that wait as an error rather than write unlocked. Because the
  advisory lock carries no holder token, a writer SHALL hold it far below
  the stale threshold and SHALL re-read and compare the store before the
  atomic rename.
  *(Cites: D-2, D-3; drafting-session decision (2026-09-08);
  security-posture doctrine (Sources); kickoff sign-off lens (2026-09-09).)*
- **REQ-A1.5** Losing the queue store SHALL cost at most one redelivery per
  delivered-but-open item, and every other loss it causes SHALL be stated
  rather than implied: a successor tower rebuilds the queue from the content
  homes, so no item content is recoverable only from the store, but shelve
  deadlines and settling reasons go with the store (a shelved item returns
  at once, and the catch-up reads the settled history from the event log),
  and any undelivered attention-sourced item whose source row has moved on
  is dropped. The event log still records each drop.
  **Superseded-by: REQ-A1.13** (2026-10-25) — a moved-on source settles
  with its reason instead of being dropped.
  *(Cites: D-3; storage-classes doctrine (Sources); kickoff §3 REQ-A
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-A1.13** (supersedes REQ-A1.5) Losing the queue store SHALL cost at
  most one redelivery per delivered-but-open item, and every other loss it
  causes SHALL be stated rather than implied. A successor tower rebuilds the
  queue from the content homes and the event log: shelve deadlines go with
  the store (a shelved item returns at once); settling reasons and each
  picklist's declaration are read back from the event log, and a picklist
  whose declaring line has rotated out of the log is rebuilt as a plain
  question with no window, so a loss never adds a default; the two
  reviewable kinds are rebuilt from their content home still awaiting
  review; and an attention-sourced item the log shows open but whose source
  row has moved on SHALL be recorded as settled with that reason, never
  dropped without a record.
  *(Cites: D-3, D-22; storage-classes doctrine (Sources); mission-control
  REQ-F1.5 (Sources).)*
- **REQ-A1.6** Queue records SHALL be single-line, constrained-field records
  with a stable identifier, validated against a declared grammar before any
  write, and every rendered value SHALL pass the echo-safety sanitizer. A
  content pointer SHALL be a relative path under a declared root,
  canonicalised and containment-checked before it is stored or followed;
  one that escapes the root SHALL be refused.
  *(Cites: D-4; security-posture doctrine (Sources); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-A1.7** When more than one tower session runs over the queue on one
  host, `next` SHALL lease the item it hands over to the calling tower under
  the fleet advisory lock, and another tower SHALL skip a leased item; an
  item SHALL NOT be delivered by two towers at once. Towers on different
  hosts are out of scope.
  *(Cites: D-18; kickoff §3 REQ-A (2026-09-09); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-A1.8** The lease SHALL be taken at every hand-over: at the knock for
  the first item of an attention session, and at each `next` for the items
  after it. The knock SHALL pin the item it named, and `next` SHALL knock
  again when the top item has changed since. A lease SHALL be released on
  acknowledgement, on a shelve, on settling, on absorption into a merge, on
  positive evidence of the holding tower's death, and on that tower having
  no live presence; the `tower_lease_interval` knob is only the backstop for
  what none of those reach. A lease SHALL be renewed on each reply of the
  tower holding it, and `tower_lease_interval` SHALL be at least
  `tower_quiet_interval`. A tower whose attention is confirmed MAY preempt a
  lease held by a tower whose attention is not.
  *(Cites: D-18; kickoff sign-off lens (2026-09-09).)*
- **REQ-A1.9** Mutual exclusion is the fleet advisory lock's; the lease's
  owner label is only the holding tower's presence identity, resolved once
  per tower with the same flags its presence publish used. When no presence
  identity resolves, `next` SHALL lease under a tower-session-scoped
  fallback identity and SHALL write that identity into the store, so a later
  reader can tell whose lease it is.
  *(Cites: D-18; kickoff §3 REQ-A (2026-09-09); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-A1.11** A question item MAY carry a picklist: a closed set of two or
  more options, a window, and the window's end, which SHALL be either one of
  those options (the declared default) or `park`. All three SHALL be
  declared when the item is added, validated against the record grammar,
  and SHALL NOT change afterwards except by the operator's answer. The
  window SHALL default to the `tower_picklist_window` knob, MAY be set per
  item, and SHALL run from the item's birth. `add` SHALL refuse a declared
  default, admitting only `park`, on an item that is a worker permission
  prompt (it carries the REQ-E1.8 marker), whose options name a reserved
  control (the REQ-E1.9 shapes), or that its adder declares a human gate or
  a hard-disqualifier zone.
  *(Cites: D-21; mission-control REQ-F1.6, REQ-G1.2 (Sources);
  drafting-session decision (2026-10-25).)*
- **REQ-A1.12** When a picklist's window has ended with no operator answer,
  the settling pass SHALL apply its end. On a declared default the item
  SHALL become settled-by-default, carrying the option applied and the
  window's end time, and SHALL stay visible (REQ-A1.10). On `park` the item
  SHALL stay an open question marked parked, the tower parking the unit it
  blocks through the existing Awaiting-input route, and nothing SHALL be
  answered. Neither end SHALL wait for the operator, and work the item does
  not block SHALL continue meanwhile. Expiry SHALL be evaluated against the
  window's end time on every pass, so a pass that runs late applies the end
  with the window's end time recorded, never the pass time.
  *(Cites: D-21; mission-control REQ-F1.6, REQ-M1.2 (Sources).)*
- **REQ-A1.14** `add` SHALL accept a decided-by-mission-control item only
  from a caller whose published presence record declares the mission-control
  session kind, only with a pointer to its grounds and a reversal field (a
  one-step reversal, or `none` when no one-step reversal exists), and SHALL
  refuse one whose subject is a worker permission prompt, a reserved
  control, a human gate, or a hard-disqualifier zone. The item records a
  decision already taken; the queue SHALL NOT be what grants it.
  *(Cites: D-20; mission-control D-13, D-24, REQ-F1.8 (Sources);
  drafting-session decision (2026-10-25).)*

## REQ-B — Settling and merging

- **REQ-B1.1** The settling pass, which the `settle` verb runs, SHALL be
  level-triggered: every pass SHALL re-evaluate every open item's closing
  condition against the evidence available now, and an item whose condition
  is met SHALL be closed without the operator (settled) with a record naming
  what settled it. One pass SHALL run per tower-loop iteration and SHALL
  serve both the loop and the delivery that follows it, consuming the
  reconcile sweep's already-derived evidence and its TTL-stamped fetch
  rather than re-polling. Evidence SHALL be gathered outside the fleet lock,
  which SHALL be taken only for the writes and held only for a stated bound.
  *(Cites: D-5; obs:5756e0af; kickoff sign-off lens (2026-09-09).)*
- **REQ-B1.2** Only evidence SHALL settle an item: an open or merged PR,
  commits on the branch, a closed ledger item, a worker's question answered
  by another route, or a matching written standing decision. Answered by
  another route means exactly one of an acknowledgement on the item, a
  `claim` close on the worker's record, or a matching standing decision, and
  never a worker's own output. A worker's own report of completion or
  success SHALL NOT settle an item. An evidence source that cannot be
  reached SHALL be distinguished from one reporting nothing and SHALL be
  logged as unavailable. An item whose content home has vanished SHALL be
  settled with that reason, and the reason SHALL be logged.
  *(Cites: D-5; obs:b23d6ea9, obs:05313aff, obs:6712b6d1; kickoff sign-off
  lens (2026-09-09).)*
- **REQ-B1.3** Items asking the operator the same thing SHALL be merged into
  one item that names every source; items whose answers would contradict
  each other SHALL be paired and delivered together as one item naming both
  sources, so a hand-over stays one unit. Merging and pairing SHALL consider
  only open items that are neither leased nor delivered, and SHALL be
  computed by keying every candidate in one pass. The script SHALL merge on
  identical normalised question text and option set, where normalised means
  case-folded, whitespace-collapsed, with the origin worker handle and
  worktree path removed by fixed-string replacement; an item carrying a
  worker command SHALL merge only on byte equality after that removal, with
  no case-folding and no whitespace collapse. It SHALL pair at most two open
  items of the same kind naming the same subject key (worker handle, PR
  number, or branch); subtler contradictions are the tower session's
  judgment at delivery. A merged or paired item SHALL carry the highest
  urgency and the oldest age of its sources.
  *(Cites: D-5; obs:332374a2; kickoff §3 REQ-B (2026-09-09); kickoff
  sign-off lens (2026-09-09).)*
- **REQ-B1.4** An item the tower settles without the operator SHALL be
  recorded with its reason and SHALL be available on request and in the
  catch-up, rendered by the `catchup` verb, after an absence; it SHALL NOT
  be pushed at the operator. The catch-up SHALL be bounded to the most
  recent `tower_catchup_limit` settled items plus a count of the remainder.
  An item settled while the operator was away SHALL be recorded as such and
  said in the next turn.
  *(Cites: D-8; drafting-session decision (2026-09-08); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-B1.5** Mentioning an item in a turn SHALL NOT count as the operator
  deciding it; an item is decided only when the operator's reply closes it
  or a written standing decision covers it.
  *(Cites: D-5, D-12; obs:4b14e93a.)*
- **REQ-B1.6** An open item SHALL leave the open set only by an operator
  answer or acknowledgement, by evidence that it no longer applies (REQ-B1.2,
  absorption into a merge under REQ-B1.3 included), by a matching written
  standing decision (REQ-E1.5), or by its picklist window's declared default
  (REQ-A1.12), which leaves it visible rather than gone. No timeout, shelve,
  lease expiry, rebuild, retention horizon, or unreachable source SHALL
  remove an open item: an item whose evidence source cannot be reached SHALL
  stay open, logged as unavailable, until evidence settles it. A reviewable
  item (REQ-A1.10) not yet reviewed is not closed and SHALL NOT fall past the
  retention horizon (REQ-A1.3).
  *(Cites: D-22; mission-control REQ-F1.5 (Sources).)*
- **REQ-B1.7** Every item that leaves the open set SHALL carry its settling
  reason in its record and its log line: the answer; the evidence, named
  with its source (a PR by number, a branch, a ledger item, a `claim`
  close); the standing decision's identifier; the item a merge absorbed it
  into; the vanished content home; the moved-on source row; or the window's
  default, with the option applied. `catchup`, and a `show` verb rendering
  one item, SHALL display that reason with the item.
  *(Cites: D-22; mission-control REQ-F1.5 (Sources).)*
- **REQ-B1.8** The operator SHALL be able to review or revoke a reviewable
  item with a reply the tower records through `ack` (reviewed) or a `revoke`
  verb. Revoking a settled-by-default item SHALL reopen it as the original
  question with no window, so it never defaults twice; revoking a
  decided-by-mission-control item SHALL close it as revoked. Every
  revocation SHALL be logged with the item's reversal pointer, for the
  session that owns the reversal to run; the script SHALL NOT run a
  reversal itself.
  *(Cites: D-20; mission-control D-13, D-24 (Sources).)*

## REQ-C — Attention and delivery

- **REQ-C1.1** The tower SHALL obtain the next item from the queue script,
  which SHALL hand over at most one item per call, so that the number of
  items in a turn is bounded by mechanism rather than by instruction. The
  unit is the hand-over: a paired contradiction (REQ-B1.3) counts as the one
  item it is delivered as. The bound is per tower conversation, so towers
  running at once each hold their own; the lease (REQ-A1.7) keeps them off
  the same item but does not make one conversation of two.
  **Superseded-by: REQ-C1.12** (2026-10-25) — a subject batch becomes a
  third shape of the one hand-over.
  *(Cites: D-6; autopilot-reflex doctrine (Sources); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-C1.12** (supersedes REQ-C1.1) The tower SHALL obtain the next
  hand-over from the queue script, which SHALL return at most one hand-over
  per call, so that what a turn carries is bounded by mechanism rather than
  by instruction. A hand-over SHALL be one item, one paired contradiction
  (REQ-B1.3), or one subject batch (REQ-C1.14), and each item inside it
  SHALL still be answered, acknowledged, or revoked on its own. The bound is
  per tower conversation, so towers running at once each hold their own;
  the lease (REQ-A1.7) keeps them off the same item but does not make one
  conversation of two.
  *(Cites: D-24; mission-control REQ-F1.4 (Sources).)*
- **REQ-C1.2** Delivery SHALL be knock first: one line naming the kind and
  urgency of what is waiting, then nothing more until the operator replies.
  Item content SHALL NOT be delivered before the operator has confirmed
  attention. The queue script SHALL enforce this: `next` SHALL return a
  knock line only when a knock is due (the calling tower's attention is
  unconfirmed and the REQ-F1.3 rule allows one) and otherwise return
  nothing, and SHALL hand over item content only once attention is
  confirmed.
  *(Cites: D-6, D-7; drafting-session decision (2026-09-08); kickoff §3
  REQ-C (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.3** A delivered item SHALL be answerable from the delivering
  message alone, with the shortest context that makes it answerable; deeper
  context SHALL be given one layer at a time on request, and the tower SHALL
  wait for a reply after each layer.
  *(Cites: D-6; interaction-style doctrine (Sources).)*
- **REQ-C1.4** Every reply from the operator (an advance of the REQ-C1.10
  attention marker) SHALL release the next item; the tower SHALL NOT
  volunteer a second item before the operator has replied to the first.
  *(Cites: D-6; drafting-session decision (2026-09-08); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-C1.5** Items SHALL be ordered by consequence: blocked workers first,
  then approvals, then the operator's requests, then news; within a kind,
  higher urgency first, then oldest first. Standing decisions are not ranked
  at all, because they are never delivered (REQ-A1.2).
  **Superseded-by: REQ-C1.13** (2026-10-25) — the two reviewable kinds take
  their place in the order.
  *(Cites: D-6; attention-notification-capability doctrine (Sources);
  kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.13** (supersedes REQ-C1.5) Items SHALL be ordered by
  consequence: blocked workers first, then approvals, then the operator's
  requests, then settled-by-default items, then decided-by-mission-control
  items, then news; within a kind, higher urgency first, then oldest first.
  A subject batch SHALL rank as its highest-ranked member. Standing
  decisions are not ranked at all, because they are never delivered
  (REQ-A1.10).
  *(Cites: D-20, D-24; mission-control REQ-F1.4 (Sources);
  drafting-session decision (2026-10-25).)*
- **REQ-C1.6** The operator MAY shelve an item with a reply meaning "later";
  a shelved item SHALL return on its own after the `tower_shelve_return`
  interval and SHALL never be dropped by shelving.
  *(Cites: D-6; research: ISA-18.2 shelving (Sources); kickoff §3 REQ-C
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.7** A news item SHALL carry an urgency on the attention store's
  scale (`high`, `normal`, `low`; urgent means `high`); an urgent news item
  MAY knock in the conversation, but its content SHALL be delivered only
  once attention is confirmed, and a non-urgent news item SHALL wait for the
  operator's next engagement or request. Urgent news SHALL never push while
  the operator is away: the attended knock is its only escalation.
  *(Cites: D-7; drafting-session decision (2026-09-08); kickoff §3 REQ-C
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.8** After an autonomous stretch with no operator turn, the first
  attended turn SHALL explain where things stand in plain words and SHALL
  NOT report what the tower did; the record of what it did stays in the log
  and is available on request. The catch-up list (REQ-B1.4) is what the
  tower reads to compose that picture, and the list itself is shown to the
  operator only on request.
  *(Cites: D-6; obs:95b7a18d; kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.9** The queue SHALL expose what is waiting through the existing
  `statusline` notification channel as a distinct field named `waiting`
  (never `queue`, which the fleet stats line already uses for the worker
  decision queue), under a label that unmistakably reads as planwright's,
  so the operator sees that decisions or actions are waiting without
  asking. The field's width SHALL be bounded to the top item's kind plus
  one total; per-kind counts are available from the `counts` verb, which
  feeds the field. The read SHALL be lock-free and best-effort, and a store
  that cannot be read, a torn or malformed line, or a kind outside the
  closed set SHALL degrade to a distinct unreadable marker, never a blank, a
  zero, or a failed render. The render is fleet-autonomy REQ-F1.2's and
  SHALL be extended in place; it SHALL read the store only, SHALL render
  only while a live tower presence exists, and renders only while that
  channel is selected, as the fleet stats do; that channel coupling is an
  accepted limitation of the seam.
  *(Cites: D-17; fleet-autonomy REQ-F1.2 (Sources); kickoff §3 REQ-C
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.10** Attention SHALL be confirmed only by a marker the harness
  wrote: the prompt-submit hook SHALL write the time of the operator's last
  reply to a per-tower marker file it alone owns under the fleet home,
  taking no shared lock so the write is never dropped, and `next` SHALL read
  that marker for the calling tower. Attention is per tower; it holds for
  one attention session opened by one knock, each reply releasing the next
  item without a fresh knock, and it lapses after the REQ-F1.1 quiet
  interval, after which the next delivery knocks again. `next` SHALL hand
  over nothing until the marker shows a reply later than its own last
  delivery to that tower. The `ack` verb SHALL close an item and SHALL NOT
  release the next; it SHALL refuse when the calling tower holds no lease on
  the item, logging that refusal as a duplicate no-op, and SHALL be a logged
  no-op on an item already closed.
  *(Cites: D-6; kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.11** A store, marker, or log that cannot be written SHALL be
  surfaced as an error in the turn, never silently skipped. A failed append
  of a delivery line SHALL be fail-open: the hand-over stands and the error
  is surfaced, and the redelivery that risks stays inside the REQ-A1.5
  budget.
  *(Cites: D-6; kickoff sign-off lens (2026-09-09).)*
- **REQ-C1.14** When the top item names a subject, `next` SHALL batch with
  it the other open, unleased, undelivered, deliverable items naming the
  same subject, of any kind, up to `tower_batch_max` items in all, ordered
  inside the batch by REQ-C1.13 and each leased to the calling tower, the
  rest waiting for a later call. A subject SHALL be a REQ-B1.3 subject key
  (worker handle, PR number, or branch) or a free-text subject its adder
  records, compared by byte equality after case-folding and whitespace
  collapse. A paired contradiction on that subject SHALL join the batch as
  its pair. An item naming no subject SHALL be handed over alone.
  *(Cites: D-24; mission-control REQ-F1.4, D-5 (Sources);
  drafting-session decision (2026-10-25).)*

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
  corrects the echo only if it is wrong. A question the tower answers inside
  the same turn is not an ask and SHALL NOT become an item on its own
  (REQ-E1.6).
  *(Cites: D-11; operator-dialogue REQ-L1.1 (Sources), whose confirmation
  clause this overrides while keeping its no-transcribe intent; kickoff
  sign-off lens (2026-09-09).)*
- **REQ-E1.2** A request's or an approval's content SHALL be written to the
  action-item ledger when it exists and to the pre-ship fallback (REQ-A1.3)
  until it does; the queue record SHALL point at that home.
  *(Cites: D-11; operator-dialogue REQ-L1.2 (Sources); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-E1.3** A reply meaning "always" or "from now on" SHALL become a
  standing decision: a ledger item of the standing kind (a record in the
  pre-ship fallback until the ledger ships) carrying the rule in the
  operator's words, what it covers, and when it was said. When the rule
  covers worker commands, its coverage SHALL be a list of literal command
  prefixes compared by fixed-string matching (never a pattern), each
  validated against the constrained grammar (non-empty, no control byte,
  no leading whitespace); otherwise coverage is free text in the operator's
  words, applied per REQ-E1.7. `capture` SHALL refuse a standing decision
  whose coverage reaches a reserved control (REQ-E1.9).
  *(Cites: D-11, D-12; obs:4b14e93a, obs:fea82b1c; kickoff §3 REQ-E
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-E1.4** Whenever the tower settles an item against a standing
  decision, the settling record and its log line SHALL carry that decision's
  identifier, so every self-settled item traces to a rule the operator
  wrote. What the tower speaks SHALL instead name the rule in the operator's
  own words, never by that identifier.
  *(Cites: D-11, D-12; obs:4b14e93a; kickoff sign-off lens (2026-09-09).)*
- **REQ-E1.5** A worker's harness permission prompt MAY be answered from a
  standing decision only when the prompt falls strictly inside the written
  rule; a prompt outside every written standing decision SHALL reach the
  operator, and the tower SHALL NOT answer one from its own judgment. A
  match requires the command to start with one of the rule's literal
  prefixes under fixed-string comparison and a token boundary after that
  prefix.
  *(Cites: D-12; autonomous-safe-decision doctrine (Sources);
  orchestration-fleet REQ-B1.7 (Sources); kickoff §3 REQ-E (2026-09-09);
  kickoff sign-off lens (2026-09-09).)*
- **REQ-E1.6** An operator's question SHALL be answered in the turn; when the
  answer needs work, that work SHALL become a request item.
  *(Cites: D-11; drafting-session decision (2026-09-08).)*
- **REQ-E1.7** Mechanical settling by a standing decision SHALL be confined
  to worker permission prompts. A standing decision that is not about a
  worker command SHALL NOT settle an item mechanically; the queue SHALL
  surface it beside an open item naming the same subject, and the tower's
  reply applying it SHALL name the rule. `capture` SHALL record an explicit
  subject key (a worker handle, a PR number, or a branch) whenever the
  operator names one; with no subject key recorded, whether to surface the
  rule beside an item is the tower session's judgment.
  *(Cites: D-11, D-12; kickoff §3 REQ-E (2026-09-09); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-E1.8** The command a match reads SHALL be a `command` field on the
  permission record, captured by the `PermissionRequest` hook from the
  harness payload, beside a positive marker the same hook stamps (the
  attention store's ninth field, `permission`). The match and the answer
  channel's re-match SHALL read only that field, and SHALL refuse a record
  that carries neither it nor the marker.
  *(Cites: D-12; kickoff sign-off lens (2026-09-09).)*
- **REQ-E1.9** After the matched prefix, the remainder of the command SHALL
  consist solely of an allowlisted token set (characters in
  `[A-Za-z0-9._/@:=+-]`, spaces, and the interiors of quoted strings);
  anything outside it SHALL refuse the match. A mechanical refusal SHALL run
  on the reserved-control shapes (merge, ready, force-push, amend, squash,
  rebase) regardless of what any rule's coverage claims. Command text shown
  to the operator for approval SHALL be ASCII-only, any other byte rendered
  as an escape beside a warning.
  *(Cites: D-12; security-posture doctrine (Sources); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-E1.10** The answer channel SHALL itself resolve the named decision,
  confirm it is of the standing kind, and re-run the match against the
  parked command before accepting. The item SHALL be settled only after the
  answer is confirmed to have exited zero; a non-zero exit SHALL leave the
  item open and SHALL log the attempt.
  *(Cites: D-12; kickoff sign-off lens (2026-09-09).)*

## REQ-F — Unattended operation and survival

- **REQ-F1.1** The operator is **away** in a tower's conversation when a
  knock there receives no reply within the `tower_quiet_interval`, and
  present again on any reply; away and present are per tower conversation,
  so one tower's silence says nothing about another's. The interval SHALL be
  a config knob with a documented default.
  **Superseded-by: REQ-F1.7** (2026-10-25) — a presence input is read
  first, the quiet interval becoming its fallback.
  *(Cites: D-9; drafting-session decision (2026-09-08); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-F1.7** (supersedes REQ-F1.1) The operator's presence in a tower's
  conversation SHALL be read first from a presence input: a per-tower
  presence marker inside the fleet home's owner-only sub-surface, written
  only through the queue script's `presence` verb by a presence producer
  (the mission-control panel, from its prompt events), carrying the
  producer, the time it was written, and either the time of the operator's
  last prompt event or an explicit away. While the marker is fresh (written
  within `tower_presence_ttl`), the operator SHALL be present when its last
  prompt event falls within `tower_quiet_interval`, and away otherwise or
  when it says away. When the marker is absent, stale, or unreadable,
  presence SHALL fall back to the quiet interval: a knock with no reply
  within `tower_quiet_interval` marks the operator away, and any reply marks
  them present. Each switch between the two sources SHALL be logged. Away
  and present stay per tower conversation, every interval SHALL be a config
  knob with a documented default, and `next` SHALL hand over nothing while
  the operator is away. The presence input SHALL NOT confirm attention:
  content still waits for the REQ-C1.10 marker.
  *(Cites: D-23; mission-control D-6, D-7, REQ-F1.4 (Sources).)*
- **REQ-F1.2** The away push SHALL fire on the transition into away while
  any blocking item is open, and after that only on worsening (REQ-F1.3),
  through the existing notification seam. Pushes SHALL be deduped per item
  across towers under the fleet lock. A channel of `none` and a channel of
  `statusline` are both push-less: the item stays in the queue and the
  operator reads it where that channel already shows things. The outcome of
  every push attempt SHALL be logged as its own event.
  *(Cites: D-9; attention-notification-capability doctrine (Sources);
  kickoff sign-off lens (2026-09-09).)*
- **REQ-F1.3** An away knock SHALL fire once when the first blocking item
  appears and again only when the situation worsens: more blocked workers,
  or a blocked item passing the `tower_reknock_age`. It SHALL NOT repeat on
  a fixed schedule, and a worsening re-knock SHALL be held while an evidence
  source the worsening reading depends on is unavailable (REQ-B1.2).
  *(Cites: D-9; research: PagerDuty escalation on state (Sources); kickoff
  sign-off lens (2026-09-09).)*
- **REQ-F1.4** Items SHALL accumulate and settle among themselves while the
  operator is away exactly as when present; nothing SHALL be dropped or
  auto-answered for lack of attention.
  **Superseded-by: REQ-F1.8** (2026-10-25) — a picklist window's declared
  default becomes the one answer taken for lack of attention.
  *(Cites: D-5, D-9; obs:eea622de.)*
- **REQ-F1.8** (supersedes REQ-F1.4) Items SHALL accumulate and settle while
  the operator is away exactly as when present, and nothing SHALL be dropped
  for lack of attention (REQ-B1.6). The one answer taken for lack of
  attention SHALL be a picklist window's declared default (REQ-A1.12),
  recorded as settled-by-default, visible, and revocable; a window ending in
  `park` answers nothing.
  *(Cites: D-21, D-22; mission-control REQ-F1.5, REQ-F1.6 (Sources).)*
- **REQ-F1.5** A fresh tower session SHALL resume the queue from the store,
  which is authoritative at session start, scanning the content homes only
  when the store is absent; the operator's return from away SHALL be met
  with the catch-up picture (REQ-C1.8), then a knock, then the first item on
  the operator's reply.
  *(Cites: D-3, D-6; tower-front-door REQ-F1.4 (Sources); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-F1.6** A `push` notification channel SHALL be added, relayed by the
  tower session rather than pushed by the script: on that channel the notify
  seam SHALL write a pending-push marker under the fleet home, deduped per
  item under the fleet lock, and the tower session SHALL relay it on its
  next step by calling Claude Code's push-notification tool, which reaches
  the operator's desktop and, when Remote Control is connected, their phone,
  and which itself skips the notification while the operator is active. The
  relayed line SHALL be one line under 200 characters in the REQ-D1.1 speech
  register.
  *(Cites: D-19; kickoff sign-off lens (2026-09-09).)*
- **REQ-F1.9** Events SHALL reach the queue by push first: the `presence`
  verb SHALL run the settling pass after each write, and a wake reaching the
  tower session SHALL call `next` at once, so window ends and deliveries
  follow the event rather than the next tick; the tower loop's tick SHALL
  remain the failsafe that runs both when no wake arrives.
  *(Cites: D-21, D-23; mission-control REQ-M1.2, D-6 (Sources).)*

## REQ-G — Measurement and the experiment

- **REQ-G1.1** Every queue event (item born, settled, merged, knocked,
  delivered, acknowledged, shelved, pushed, a session's start or its
  rebuild, each tower-loop pass's tick with the live-worker count, and each
  operator reply) SHALL be appended as one line to an event log under the
  fleet home, never committed, with a schema version and a monotonic
  sequence.
  *(Cites: D-14; kickoff-dialogue doctrine (Sources); kickoff §3 REQ-G
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
- **REQ-G1.2** A scorecard SHALL be computed from the log alone, whose
  headline is the operator's load: items that reached the operator per hour
  of fleet work (wall-clock time with at least one live worker) against
  items settled without them. Fleet hours SHALL be computed per tower from
  that tower's own tick stream and the per-tower intervals unioned, so an
  hour two towers both tick through counts once. An interval between
  consecutive ticks longer than `tower_tick_gap_max` SHALL be excluded from
  the denominator and reported as a gap beside the headline. Secondary
  measures SHALL include blocked-worker wait for an operator answer, turns
  carrying more than one ask, items delivered in prose with no queue record,
  friction moments (what-does-that-mean questions and repeated requests),
  jargon counts in delivered text, and items lost across a tower restart.
  *(Cites: D-14; drafting-session decision (2026-09-08); kickoff §3 REQ-G
  (2026-09-09); kickoff sign-off lens (2026-09-09).)*
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
  CI or `mise run check`, pinned by an explicit grep of `.github/workflows`
  for the `tower:report` task.
  *(Cites: D-14; operator-dialogue REQ-M1.4 (Sources); kickoff sign-off
  lens (2026-09-09).)*
- **REQ-G1.6** The log's writers SHALL be mechanical, so the record never
  depends on a session remembering to log: `next` writes each delivery,
  `ack` writes the `acknowledged` event naming the item, each tower-loop
  pass writes the tick (coalesced with the one before it when the
  live-worker count is unchanged), and a deterministic prompt-submit hook
  active only in tower sessions writes each operator reply as a `reply`
  event through the `log` verb, inheriting the lock and the sequence,
  waiting for the lock no longer than `tower_hook_lock_wait` and then
  dropping the line and bumping a dropped-line counter rather than delaying
  the operator's turn. Every `reply`, `acknowledged`, `delivered`,
  `knocked`, and `tick` line SHALL carry the identity of the tower that
  wrote it.
  *(Cites: D-14; kickoff sign-off lens (2026-09-09).)*
- **REQ-G1.7** Each log line SHALL be a flat JSON object of string and
  number values with no nesting, written and read by the script's own awk
  with no `jq` dependency. The sequence SHALL be held in a counter file read
  and bumped under the fleet lock, and the log SHALL rotate by age with a
  floor that keeps the experiment's own sessions readable, the rotation
  happening inside that same critical section; `report` SHALL read the
  window bounded by `tower_report_window`.
  *(Cites: D-14; kickoff sign-off lens (2026-09-09).)*
- **REQ-G1.8** The `log` verb SHALL apply the secret-shaped redaction to
  every event kind it writes, and the prompt-submit hook and `capture` SHALL
  reuse that one helper rather than carry their own.
  *(Cites: D-14; security-posture doctrine (Sources); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-G1.9** Beside the REQ-G1.1 events, the log SHALL record a
  picklist's declaration with its item's birth, a window ending on a default
  or a park, a decided-by-mission-control item's birth, each review and each
  revocation of a reviewable item, each switch of presence source, and each
  batch handed over with its members. The scorecard SHALL break out
  settled-by-default and decided-by-mission-control items from items settled
  by evidence, counting both on the headline's settled-without-the-operator
  side, and SHALL report each reviewable kind's revocation rate.
  *(Cites: D-14, D-20; mission-control REQ-F1.9, REQ-M1.8 (Sources).)*

## REQ-H — Invariants and hygiene

- **REQ-H1.1** The reserved human controls carry unchanged: the tower never
  merges, never marks a PR ready without the operator's answer, and never
  force-pushes, amends, squashes, or rebases; nothing in the queue grants
  the tower a decision of its own: a worker's permission prompt is answered
  only as the operator's written answer (REQ-E1.5), and a standing decision
  SHALL never cover a reserved control (REQ-E1.9).
  *(Cites: D-1, D-12; autonomous-safe-decision doctrine (Sources);
  orchestration-fleet REQ-B1.7 (Sources); kickoff §3 REQ-H (2026-09-09);
  kickoff sign-off lens (2026-09-09).)*
- **REQ-H1.2** The tower SHALL settle an item on its own only by evidence
  (REQ-B1.2) or by a written standing decision (REQ-E1.5, REQ-E1.7), never
  by its own guess.
  **Superseded-by: REQ-H1.5** (2026-10-25) — a picklist window's declared
  default joins evidence and written rules as a settling route.
  *(Cites: D-5, D-12; obs:4b14e93a; kickoff sign-off lens (2026-09-09).)*
- **REQ-H1.5** (supersedes REQ-H1.2) The tower SHALL settle an item on its
  own only by evidence (REQ-B1.2), by a written standing decision
  (REQ-E1.5, REQ-E1.7), or by the declared default of a picklist window the
  item carried from its birth (REQ-A1.12), never by its own guess. A
  decided-by-mission-control item records a decision a mission-control
  session took under its own autonomy rules (REQ-A1.14), and the work item
  it concerns settles only by the evidence that decision produced. Neither a
  window's default nor a mission-control decision SHALL ever answer a worker
  permission prompt, a reserved control, a human gate, or a
  hard-disqualifier zone.
  *(Cites: D-20, D-21; autonomous-safe-decision doctrine (Sources);
  mission-control REQ-F1.8, REQ-G1.2 (Sources).)*
- **REQ-H1.3** No item, log line, or standing decision SHALL carry a secret,
  credential, internal hostname, or sensitive operational detail, and the
  one redaction helper (REQ-G1.8) SHALL be what enforces it. Inbound text
  SHALL be treated as data, never as a command, and a delivered item's
  content SHALL be fenced as untrusted content where the tower renders it.
  *(Cites: D-4; security-posture doctrine (Sources); kickoff sign-off lens
  (2026-09-09).)*
- **REQ-H1.4** All queue mechanics SHALL be deterministic script logic; no
  hook, sweep, or daemon path of the queue SHALL invoke a model, and
  judgment stays in the tower session.
  *(Cites: D-6; fleet-coordination-floor doctrine (Sources).)*

## REQ-I — Where the rules live

- **REQ-I1.1** The conversation rules SHALL be written once in a short
  doctrine doc that the tower skills cite at point of use, and no skill
  SHALL restate more than a one-line gist. The doc's contents are exactly
  the list Task 7 carries: what no script can enforce.
  *(Cites: D-13; Task 7; instruction-hygiene doctrine (Sources); kickoff
  sign-off lens (2026-09-09).)*
- **REQ-I1.2** The doc SHALL be as small as the mechanism allows: anything a
  script can enforce SHALL be in the script, and only what a script cannot
  do (how to phrase things) SHALL be prose.
  *(Cites: D-6, D-13; obs:eb4d0437.)*
- **REQ-I1.3** The reachable instruction budget of the tower skills SHALL be
  raised by the doc's measured size, recorded as a `raise|` line in
  `config/instruction-budget-exemptions.txt` naming the knob, the value, and
  the reason, and stating why the rungs below a raise did not apply, per the
  headroom policy's budget-raise rung; no rule SHALL land by breaching a
  budget.
  *(Cites: D-13; instruction-headroom (Sources); kickoff sign-off lens
  (2026-09-09).)*
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
- 2026-09-09: Kickoff walkthrough edits via `/spec-kickoff`. Minted
  REQ-A1.7 (delivery lease across concurrent towers, D-18), REQ-C1.9
  (native queue indicator on the statusline channel, D-17), and REQ-E1.7
  (non-command standing decisions surfaced, never settled mechanically,
  D-11, D-12); named the urgency scale (REQ-C1.7, D-4), the fleet-hours
  denominator and the tick event (REQ-G1.1, REQ-G1.2, D-14), the log
  writers (a prompt-submit hook and `next`), the merge and pairing rules
  (REQ-B1.3, D-5), the knock-first enforcement in `next` (REQ-C1.2, D-6),
  the `catchup` verb (D-6), the shelve return knob (REQ-C1.6, D-9), the
  standing-decision coverage grammar (REQ-E1.3, D-12), news losable at
  rebuild (REQ-A1.5), a worker question's home as the attention store row
  and, when parked, the Awaiting-input bullet (REQ-A1.3, D-3), and the
  REQ-H1.1 reading under which a standing decision is the operator's
  written answer (the orchestration-fleet REQ-B1.7 override is recorded in
  the kickoff brief), and pinned the log line to a flat JSON object of
  string and number values the script parses itself. The kickoff lens pass
  hardened the prefix match,
  keyed attention and the lease per tower, split `reply` and
  `acknowledged` events, and added log retention. Tasks 1 through 6, 8 and
  10 and the paired test-spec entries updated.
- 2026-09-09: Kickoff sign-off lens pass. Minted D-19 (a session-relayed
  push channel) and REQ-F1.6 for it; split the packed requirements into
  REQ-A1.8 and REQ-A1.9 (the lease's lifecycle and its owner label),
  REQ-C1.10 and REQ-C1.11 (the attention marker and the write-failure
  disposition), REQ-E1.8, REQ-E1.9 and REQ-E1.10 (the command field the
  match reads, the allowlist and the reserved-control refusal, the answer
  channel's own re-match), and REQ-G1.6, REQ-G1.7 and REQ-G1.8 (the log's
  writers, its format and rotation, its redaction). Settled the attention
  model on a harness-written marker, made the settling pass level-triggered
  and once per loop iteration, replaced the observation-fragment fallback
  with a machine-local ledger-shaped file under the fleet home, named the
  nine config keys, and stated the loss budget honestly. Every task, every
  decision touched, and the paired test-spec entries updated.
- 2026-09-12 — Task 7 expression-only edit. Task 7's `Citations:` line now
  names REQ-E1.7 and REQ-I1.4, whose test-spec entries already pin the
  no-subject judgment sentence and the scope statement to the rule doc the
  task delivers; the citations were the only place the pairing was missing.
  No REQ, D-ID, or `Done when:` condition changes meaning.
- 2026-09-12 — Task 7 expression-only edit, second. Task 7's `Citations:`
  line now names D-16, the scope decision the rule doc's own scope
  statement and its doctrine index row already cite; the task line was the
  one surface that did not. No REQ, D-ID, or `Done when:` condition changes
  meaning.
- 2026-09-17 — Delta re-walkthrough via `/spec-kickoff`, settling the two
  spec-level forks parked against Task 3 and pinning the pairing tie-break.
  Task 4's `Deliverables` and `Done when:` now say which of three or more
  candidates on one subject key becomes the partner (the oldest of those the
  top item leaves, the lower identifier breaking a tie) and why, a rule the
  cardinality sentence left
  to whoever implemented it. Store retention is reworded from the settled
  records to the closed ones (acknowledged or settled) in REQ-A1.3, D-3,
  Task 3's `Deliverables`, and REQ-A1.3's test-spec entry, matching what
  `tower_catchup_limit` has always bounded; REQ-B1.4 is untouched, because
  the catch-up list does render the settled records alone. Task 3's three
  recorded deviations stay recorded in the kickoff risk register rather
  than being folded into its block. No task is added, removed, or
  re-scoped.
- 2026-10-25 — Extended via `/spec-draft --extend tower-comms` (Draft
  delta, meaning-class; awaits a `/spec-kickoff` delta re-walkthrough), the
  amendment mission-control routes here (its D-7, D-22 and Task 6). Minted
  D-20 through D-24; REQ-A1.10 (supersedes REQ-A1.2), REQ-A1.11, REQ-A1.12,
  REQ-A1.13 (supersedes REQ-A1.5), REQ-A1.14, REQ-B1.6, REQ-B1.7, REQ-B1.8,
  REQ-C1.12 (supersedes REQ-C1.1), REQ-C1.13 (supersedes REQ-C1.5),
  REQ-C1.14, REQ-F1.7 (supersedes REQ-F1.1), REQ-F1.8 (supersedes
  REQ-F1.4), REQ-F1.9, REQ-G1.9, and REQ-H1.5 (supersedes REQ-H1.2); D-3,
  D-4, D-5, D-6 and D-9 marked superseded in part. Added Tasks 11 through
  14 and their test-spec entries; the superseded REQs' entries stay beside
  their successors. Drafted by an unattended worker: every choice the
  mission-control spec did not settle is listed under design.md's *Open
  questions for the delta kickoff* for the kickoff to confirm or overturn.
  The altitude is unchanged (D-1): the delta is capability and mechanism
  inside the existing queue, and no doctrine rule is added.

## Sources

- **mission-control (2026-10-24, Ready)** — the bundle that routes this
  delta here: D-7 (the queue stays the single delivery authority; it gains
  a presence input, picklist windows, and the two reviewable kinds), D-22
  (cross-bundle edges), D-5 (the free-text `subject` key), D-6 (the panel as
  presence producer and primary wake), D-13 (autonomy and calibration), D-24
  (the undo ledger and its reversals), REQ-F1.4, REQ-F1.5, REQ-F1.6,
  REQ-F1.8, REQ-F1.9, REQ-G1.2, REQ-M1.2 and REQ-M1.8, and its Task 6.
- **Drafting-session decisions (2026-10-25)** — no operator was present; an
  unattended fleet worker took the choice the mission-control spec most
  directly implies wherever it left one open, and recorded each as an open
  question in design.md for the delta kickoff.

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
  the decision queue, the fleet home and lock, and fleet-autonomy REQ-F1.2,
  which owns the `statusline` render this bundle extends in place) and
  orchestration-fleet
  REQ-B1.7, whose never-answer rule D-12 reads as never-from-own-judgment,
  an override recorded in the kickoff brief, fleet-hardening (the
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
