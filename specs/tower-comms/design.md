# Tower comms — Design

**Status:** Ready
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle (drafting session
2026-09-08 unless dated otherwise). Foreign IDs are namespace-qualified.

## Decision log

### D-1: Altitude — doctrine, a capability, a mechanism, and local values  (N)

**Decision:** Both pinned seed claims are altitude triggers under the
autopilot reflex, so the altitude is recorded before any mechanism. The
conversation rules (knock first, one item per turn, plain speech, explain
where things stand after silence) are **doctrine**: rules about how to think
at an attended surface, owned by the framework. The operator queue is a
**capability**: a seam every tower session consumes. The store, the script,
and the event log are the **mechanism** filling it. A standing decision is a
**local value**. Existing seams are consumed, never re-owned: the fleet home
and lock, the notification seam, the ledger, the rule-doc resolution chain.

**Alternatives considered:**
- Mechanism only: a queue script wired into the tower loop. Rejected
  because: the failures on record are as much about phrasing and turn shape
  as about lost items, and a rule buried in a script is invisible to the
  session that needs it.
- Doctrine only: extend the interaction doctrine with the queue rules and
  trust the tower to follow them. Rejected because: the doctrine already
  says one question per turn and the walls came back within a month; an
  instruction the model follows can be pencil-whipped, a script that hands
  over one item cannot.

**Chosen because:** the operator's framing was a principle with the queue as
one suggestion, and the reflex's fifth step places each piece at its own
altitude rather than promoting the mechanism into doctrine or burying the
doctrine in the mechanism.

### D-2: A sibling queue above the worker attention store  (N)

**Decision:** The operator queue is a new store and script under the same
fleet home and advisory lock as the worker attention store, consuming that
store's decision queue as one of its inputs. The worker store keeps its
one-row-per-worker shape and its writers untouched. The existing-seam-reuse
domain fires on minting a store; the nearest seam is the attention store,
and it does not fit because its identity is the worker handle with
last-write-wins per row, while four of the five item kinds have no worker.

**Alternatives considered:**
- Extend the attention store with the other kinds. Rejected because: it
  reshapes a shipped, tested store that other bundles write to, and
  forces operator requests into a per-worker row model.
- Replace the worker decision queue outright. Rejected because: it touches
  other bundles' contracts and the backend capability contract's
  surface-provided deferral, for no gain the sibling does not deliver.

**Chosen because:** the operator chose it on blast radius: the worker seam
stays the worker seam, and the operator-facing layer is separate and small.

### D-3: Content in existing homes; delivery state under the fleet home  (N)

**Decision:** The queue store holds the index and delivery state only.
Each item's content lives where its kind already lives: a worker's question
in the worker attention store row and, when parked, the owning spec's
Awaiting-input bullet; a request, an approval, or a standing decision in the
action-item ledger, or in the pre-ship fallback until it ships; news in the
attention store. The store is framework runtime state in the storage-classes
sense: losable, rebuilt from the content homes, costing at most one
redelivery per delivered-but-open item, plus the shelve deadlines and
settling reasons that live nowhere else and any undelivered
attention-sourced item whose source row moved on. It keeps only the open
items and the settled ones still inside the catch-up window, so its size
tracks what is live rather than everything that ever happened.
*(Amended at kickoff 2026-09-09: worker-question home and the
dropped-news exception.)*
*(Amended at kickoff sign-off lens 2026-09-09: the fallback home, the honest
loss budget, and retention to the catch-up horizon.)*

**Alternatives considered:**
- One store under the fleet home holding content too. Rejected because: a
  request spoken mid-run cannot be rebuilt from anything, so the store would
  hold information whose loss loses information, which the storage rule
  places in a repo, not in machine-local state.
- One committed fragment store holding delivery state too. Rejected because:
  every knock and acknowledgement becomes a commit on a shared repo, the
  churn the derived-state design exists to end.

**Chosen because:** the operator wanted the queue to survive a tower dying,
the fleet home survives that, and the split keeps the storage rule and the
ledger's ownership intact with nothing new to keep consistent.

### D-4: Five item kinds, one constrained record grammar  (N)

**Decision:** An item is news, question, approval, request, or standing
decision. A record is a single line of constrained fields, in the shape the
attention and registry stores already use: stable identifier, kind, urgency
(the attention store's `high` / `normal` / `low`; a worker question inherits
its row's priority), origin (source worker or operator turn, timestamp),
pointer to the content
home, closing condition, and delivery state. Every field is validated
against its grammar before a write, and every rendered value passes the
echo-safety sanitizer. The closing condition names the human action that
resolves the item (an answer, a go-ahead) or the evidence that settles it; a
record promising a future automatic step is refused. A standing decision is
registered like any other item and is the one kind never delivered and never
ranked: what closes it is the operator revoking the rule.
*(Amended at kickoff sign-off lens 2026-09-09: a shelve dropped from the
resolving actions, and the standing kind named as never delivered, with the
operator's revocation as what closes it.)*

**Alternatives considered:**
- Free-form markdown per item. Rejected because: unparseable by the settling
  pass, which turns evidence-based settling back into reading.
- Full YAML records. Rejected because: the repo's parsers are constrained
  portable-shell readers; YAML brings a parser dependency and an injection
  surface for no field this record needs.

**Chosen because:** it is the proven local idiom, and the refused-promise
rule closes the park-note failure on record (obs:9dfdea07).

### D-5: Settling by evidence; process events are claims  (N)

**Decision:** The settling pass, run by the `settle` verb, is
level-triggered: each pass re-evaluates every open item's closing condition
against the evidence available now, rather than replaying the events since
the last pass. One pass runs per tower-loop iteration and serves the
delivery that follows it, consuming the reconcile sweep's already-derived
evidence and its TTL-stamped fetch instead of polling again, and gathering
that evidence outside the fleet lock. An item settles only on evidence the
reconcile sweep already trusts (an open or merged PR, commits on the branch,
a closed ledger item, a worker's question answered by another route, which
means an acknowledgement on the item, a `claim` close on the worker's
record, or a matching standing decision) or on a matching written standing
decision. A worker's completion report, a result frame, or a status line is
a claim and settles nothing, and a source that cannot be reached is logged
as unavailable rather than read as silence. Same-question items merge into
one that names every source; contradicting items collapse into one delivered
item naming both. Both rules are mechanical, since the script never calls a
model: key every open, unleased, undelivered candidate in one pass; merge on
identical normalised question text and option set, where normalised means
case-folded, whitespace-collapsed, with the origin worker handle and
worktree path removed by fixed-string replacement, except that an item
carrying a worker command merges only on byte equality after that removal;
pair at most two items of the same kind naming the same subject key (worker
handle, PR number, or branch), the result carrying the highest urgency and
the oldest age of its sources; anything subtler is the tower session's
judgment at delivery. Every settled item records what settled it.
*(Amended at kickoff sign-off lens 2026-09-09: level-triggered and once per
loop iteration, evidence sourcing and unavailability, the merge and pair
keys, and the pair as one delivered item.)*

**Alternatives considered:**
- Trust the worker's own completion signal. Rejected because: three workers
  in one session reported success while alive and still working, and a
  network overload was recorded as a success.
- Never settle without the operator. Rejected because: the merge already is
  the answer in the recorded case, and re-asking answered questions is the
  load this spec exists to remove.

**Chosen because:** evidence is the only thing the recorded failures did not
falsify.

### D-6: The delivery protocol is a script, with vocabulary from alarm and on-call practice  (N)

**Decision:** The queue script owns delivery: `next` hands over at most one
item, ordered by consequence (blocked workers, approvals, requests, news;
then urgency, then age) and runs the settling pass before it selects;
`settle` runs that pass on its own; `list` prints the open set; `knock`
renders the line `next` returns, so the text has one home and `next` keeps
the state and the lease; `ack` closes an item; `shelve` parks an item with a
bounded return; `counts` gives the per-kind open counts the status-line
field reads; `catchup` renders the settled-since-last-reply picture with
reasons and the open counts by kind, bounded to the most recent
`tower_catchup_limit` items plus a remainder count, so `next` stays one
item. Knock-first is enforced by `next` itself, and the only thing that
confirms attention is a marker the harness wrote: the prompt-submit hook
stamps the operator's last reply time into a per-tower marker file it alone
owns, lock-free so the write is never dropped, and `next` reads that marker
and hands over nothing until it shows a reply later than its own last
delivery. Attention is tracked per tower and lapses after the quiet
interval. The cadence is one knock per attention session, not per item (a
knock per item would be the rejected go-ahead alternative under another
name): the tower knocks with one line, waits for a reply, delivers the item,
and waits again; each reply releases the next item without a fresh knock
until attention lapses. `ack` closes an item and never releases the next, so
a tower cannot open its own gate. A store, marker, or log that cannot be
written is surfaced as an error in the turn, never silently skipped; a
failed delivery-line append is the one fail-open case, because the
redelivery it risks is already inside the loss budget. After an autonomous
stretch the first turn explains where things stand, not what the tower did.
The vocabulary is borrowed from the
process-industry alarm standard (every surfaced item actionable;
acknowledgement logged; shelving time-limited with automatic return;
suppression by design traces to a written rule) and from on-call
tooling (acknowledging halts escalation; an acknowledged item
re-triggers after a timeout).
*(Amended at kickoff sign-off lens 2026-09-09: the verb list named once, the
harness-written attention marker, `ack` no longer releasing the next item,
and the fail-open delivery-line case.)*

**Alternatives considered:**
- A prose rule "one item per turn" and nothing mechanical. Rejected because:
  that rule already exists and is already contradicted by a sibling doc's
  "up to five per pass"; nothing measured it, and it did not hold.
- An explicit go-ahead word between items. Rejected because: it adds a
  message per item; the operator chose any reply as the release.

**Chosen because:** the reflex prefers a mechanism over model restraint
where no judgment is needed, and two fields that solved many-sources-one-
human long ago converge on the same verbs.

### D-7: News is queued and urgency-gated; content waits for confirmed attention  (N)

**Decision:** A news item carries an urgency. An urgent one may knock in the
conversation; a non-urgent one waits for the operator's next engagement or
for a request. In either case the content is delivered only once the
operator has confirmed attention, so news never interrupts and never lands
where it will not be read. No news pushes while the operator is away,
whatever its urgency: the attended knock is the whole escalation, because
waking someone for something they need do nothing about is the noise this
bundle exists to remove.
*(Amended at kickoff sign-off lens 2026-09-09: no news of any urgency
pushes while the operator is away.)*

**Alternatives considered:**
- Every report interrupts as it happens. Rejected because: it is today's
  behaviour, and the wall-of-status failure the fleet docs already warn
  about.
- News is never queued, status on demand only. Rejected because: the tower
  then cannot say what the operator missed while away.

**Chosen because:** the operator's answer: try for attention by urgency, but
rely on the information reaching them only when they will absorb it.

### D-8: Self-settled items are available, never pushed  (N)

**Decision:** An item the tower settles without the operator is recorded
with its reason and shown only on request or in the catch-up after an
absence.

**Alternatives considered:**
- One line per settled item in every turn. Rejected because: it grows every
  turn with bookkeeping the operator did not ask for.
- Tell only when a standing decision was applied. Rejected because: the
  operator chose the uniform rule; the catch-up and the log carry the
  standing-decision cases with the rule named.

**Chosen because:** attention is for decisions; the record is one request
away.

### D-9: Away detection by quiet interval; knock once, again only on worsening  (N)

**Decision:** A conversation knock with no reply within the quiet interval
marks the operator away in that tower's conversation; any reply marks them
present. Away and present are per tower conversation, because the knock that
went unanswered was one tower's; the push that follows is deduped per item
across towers under the fleet lock, so two towers holding the same item wake
the operator once. The push fires on the transition into away while a
blocking item is open, and again only when the situation worsens: more
blocked workers, or a blocked item passing the re-knock age. Channels of
`none` and `statusline` are push-less, so on those the item simply waits.

The knobs, named once here and used by that name everywhere:
`tower_quiet_interval` and `tower_lease_interval` (the queue-store task),
`tower_reknock_age` and `tower_shelve_return` (the delivery task),
`tower_tick_gap_max`, `tower_log_rotate_age`, `tower_report_window` and
`tower_hook_lock_wait` (the log and baseline tasks), and
`tower_catchup_limit` (the settling task). Each carries a documented default
and an options-reference row, and every interval among them accepts
sub-second values so the tests do not have to wait in real time.
*(Amended at kickoff sign-off lens 2026-09-09: away scoped per tower, the
push transition and its dedupe, the push-less channels, and the naming of
the config keys.)*

**Alternatives considered:**
- Only an explicit "I'm away" switches modes. Rejected because: a forgotten
  goodbye means a night of silent knocks, the failure on record.
- Every knock goes to both surfaces. Rejected because: the notification
  becomes noise while the operator is present.
- Repeat on a fixed schedule. Rejected because: hardest to miss and easiest
  to start ignoring; on-call practice escalates on state, not on a timer.

**Chosen because:** the operator chose the quiet interval, and the on-call
model's ack-halts-escalation shape maps onto it directly.

### D-10: Speech register — a developer who knows planwright's basics  (N)

**Decision:** The tower writes for a developer who knows tower, worker,
spec, task, PR, branch, and worktree. Everything below that (store names,
script names, spec identifiers, doctrine terms, positional labels) is
avoided or glossed in plain words on first use. The test is from the
listener's side: if "what is that?" needs a file open, it is not a word to
say. When the operator asks what a name means, the name is the defect.
Delivered text is logged, so the register is lintable after the fact.

**Alternatives considered:**
- Any developer, with tower and worker glossed too. Rejected because: safest
  for new adopters, more words for the operator; the operator chose the
  first level.
- An adjustable level per operator. Rejected because: it adds a config knob
  to this version for a preference with no evidence yet that it varies.

**Chosen because:** the operator chose it, and it matches the rule already
followed on PR bodies and commit messages, now extended to speech.

### D-11: Inbound capture — echo one line; standing decisions are ledger items  (N)

**Decision:** Anything the operator asks for becomes a queue item in the
same turn, echoed in one line, with no confirmation required; a question the
tower answers inside the turn is not an ask. That lighter form overrides
operator-dialogue REQ-L1.1's confirmation clause while keeping its intent,
which is that nothing the operator said gets transcribed away unrecorded.
Content is written to the action-item ledger when it exists, and until then
to the pre-ship fallback: one machine-local, untracked, owner-only
ledger-shaped file under the fleet home holding captured requests,
approvals, and standing decisions. A reply meaning "always" or "from now on"
becomes a standing decision: a ledger item of the standing kind, carrying
the rule in the operator's words, what it covers, and when it was said. When
the rule covers worker commands, its coverage is a list of literal command
prefixes, each validated against the constrained grammar (non-empty, no
control byte, no leading whitespace); otherwise coverage is free text in the
operator's words, and such a rule is surfaced beside an open item naming the
same subject rather than settling anything mechanically, with the tower's
reply that applies it naming the rule. Mechanical settling by a rule is
therefore confined to permission prompts. This bundle depends on the
ledger's substrate task for the durable home, and carries the fallback so
that nothing blocks on that bundle.
*(Amended at kickoff 2026-09-09: coverage grammar scoped to worker
commands; other rules surfaced, never settled mechanically.)*
*(Amended at kickoff sign-off lens 2026-09-09: the fallback moved to a
machine-local file under the fleet home, the REQ-L1.1 override recorded, and
mechanical settling confined to permission prompts.)*

**Alternatives considered:**
- Echo and wait for a yes, matching the operator-dialogue capture rule
  exactly. Rejected because: an extra message per request; the operator
  chose the lighter form, accepting that a mis-hearing survives until
  noticed.
- Standing decisions as a parsed config file in the overlay chain. Rejected
  because: the operator chose the ledger, keeping every operator-owed and
  operator-declared thing in one store; the cost is a dependency on an
  unmerged bundle, carried by the fallback.

**Chosen because:** the operator chose both; capture is the tower's clerical
weight, and the ledger is the home the companion bundle already claims.

### D-12: A standing decision may answer a permission prompt, strictly inside its rule  (N)

**Decision:** A worker's harness permission prompt that falls strictly
inside a written standing decision is answered as the operator's answer,
delivered by the tower through the sanctioned answer channel, and the log
names the rule. The command the match reads is not scraped from prose: the
`PermissionRequest` hook captures it from the harness payload into a
`command` field on the permission record, beside a positive marker (the
attention store's ninth field, `permission`) the same hook stamps, and a
record carrying neither is refused rather than guessed at. Strictly inside
means that command starts with one of the rule's literal prefixes under
fixed-string comparison, never a pattern, with a token boundary after the
prefix, and that everything after the prefix falls inside a conservative
allowlist (characters in `[A-Za-z0-9._/@:=+-]`, spaces, and quoted-string
interiors), which is what an enumerated denylist of shell operators could
never be: complete. A mechanical refusal runs on the reserved-control shapes
(merge, ready, force-push, amend, squash, rebase) whatever a rule's coverage
claims, and `capture` refuses to record a rule that reaches one. Command
text put in front of the operator is ASCII-only, any other byte shown as an
escape beside a warning, so no approval is given to text that renders as
something else. The answer channel, which today refuses every
permission-park, accepts such an answer only when it names the standing
decision, and at that boundary it resolves the named decision, confirms it
is of the standing kind, and re-runs the match against the parked command
itself; the item settles only once that answer is confirmed to have exited
zero, and a non-zero exit leaves it open with the attempt logged. A prompt
outside every written standing decision reaches the operator. The tower
never answers one from its own judgment, and mentioning a prompt in a turn
does not count as the operator deciding it. This overrides
orchestration-fleet REQ-B1.7 as written: its never-answer rule is read as
never-from-the-tower's-own-judgment, an override recorded in the kickoff
brief; the standing decision is the operator's recorded answer, which the
answer channel already requires as input.
*(Amended at kickoff sign-off lens 2026-09-09: the hook-captured `command`
field and its marker, the allowlist replacing the operator denylist, the
mechanical reserved-control refusal, ASCII-only display, and settling on a
confirmed exit-0 answer.)*

**Alternatives considered:**
- Permission prompts never touch standing decisions. Rejected because: it
  keeps the rule exactly as written and leaves unattended fleets at the
  measured escalation rate; the operator chose to legitimise the practice
  and make it auditable instead.
- Leave it as a fork for kickoff. Rejected because: the operator decided it
  in drafting; kickoff re-walks it like any decision.

**Chosen because:** the recorded failure was not that the tower answered
prompts but that it answered some outside any written rule with no record
that a rule existed; the strict-match plus named-rule form fixes exactly
that, and the experiment measures how often the match is wrong.

### D-13: The rules live in one short doc; the budget is raised by its size  (N)

**Decision:** The conversation rules are one short doctrine doc that the
tower skills cite at point of use. Because a point-of-use doc still counts
toward a skill's reachable budget and the tower skills sit at their floors,
this bundle raises the reachable-budget knob by the doc's measured size with
the reason recorded in the config, the budget-raise rung of the headroom
policy. The doc is as small as the mechanism allows: everything a script
enforces stays out of the prose.

**Alternatives considered:**
- Pay for the doc by trimming the orchestrate closure. Rejected because: the
  headroom bundle's diet already ran and the room was spent again; the trim
  may not find the words, and it is work in another bundle's territory.
- Home the rules only in the not-yet-built front-door skill. Rejected
  because: the experiment could not run on the fleet loop the operator uses
  today.

**Chosen because:** placement is a cost question, not an effectiveness one
(the same words load into the same session either way), and the honest
answer to cost is a recorded raise sized to the actual residue.

### D-14: The event log and the scorecard  (N)

**Decision:** Every queue event is one flat JSON line of string and number
values with no nesting, under the fleet home, in the shape the kickoff
dialogue's decision log already uses (schema version, monotonic sequence,
kind, payload), never committed, written and read by the script's own awk
with no `jq` dependency. The `log` verb is where the secret-shaped redaction
runs, for every event kind, so the hook and `capture` reuse one helper
instead of each carrying a copy. Operator replies are written as `reply`
events by a deterministic prompt-submit hook active only in tower sessions,
through the `log` verb so they inherit the lock and the sequence, waiting
for the lock no longer than `tower_hook_lock_wait` and then dropping the
line and bumping a dropped-line counter rather than delaying the turn.
Because a line can be dropped that way, the log is not what confirms
attention (D-6's marker is); deliveries are written by `next` and
`acknowledged` events by `ack`, distinct from replies, so the log does not
depend on the session remembering to log. Every `reply`, `acknowledged`,
`delivered`, `knocked`, and `tick` line carries the writing tower's
identity, without which two towers' lines are indistinguishable. Each
tower-loop pass writes a tick carrying the live-worker count, coalesced with
the previous one when that count is unchanged, which gives the headline its
denominator: fleet hours are computed per tower from its own tick stream and
the intervals unioned, and an interval between ticks longer than
`tower_tick_gap_max` is excluded and reported as a gap beside the headline.
The sequence lives in a counter file read and bumped under the lock; the log
rotates by age with a floor that keeps the experiment's own sessions
readable, rotating inside that same critical section, and `report` reads the
window bounded by `tower_report_window`. The scorecard is computed from the
log alone: the headline is the operator's load (items that reached the
operator per hour of fleet work, wall-clock with at least one live worker,
against items settled without them); secondary measures are blocked-worker
wait, multi-ask turns, items delivered in prose with no queue record,
friction moments, jargon counts over delivered text, and items lost across
restarts. It runs on demand and never in CI.
*(Amended at kickoff sign-off lens 2026-09-09: flat JSON read by the
script's own awk, redaction homed in the `log` verb, tower identity on every
line, per-tower fleet hours, the sequence counter and age rotation, and the
measure of items delivered in prose.)*

**Alternatives considered:**
- Grade from session transcripts. Rejected because: the transcript format is
  internal and version-unstable; the doctrine already rejects parsing it.
- Headline on blocked-worker wait or on friction moments. Rejected because:
  the operator chose load, the goal as stated; the others stay as secondary
  measures.

**Chosen because:** the log is the one artifact conversation has never had,
and it makes both the experiment and the speech rule measurable.

### D-15: The log ships first; baseline before the queue  (N)

**Decision:** The log and scorecard land and run on today's tower before any
queue behaviour changes; a baseline over real sessions is recorded in the
kickoff brief's risk register; only then is the queue wired in. The
experiment compares real sessions before and after on the scorecard.

**Alternatives considered:**
- Use the summer's observations as the baseline. Rejected because: they
  measure different things in different units; the comparison would be
  apples to oranges.
- Reconstruct the baseline from old transcripts. Rejected because: the same
  rejected antipattern as D-14.

**Chosen because:** the operator asked for an experiment that measures
effectiveness and finds the boundary; an honest before is the price of that.

### D-16: Scope — towers now; the rules spread on measured evidence  (N)

**Decision:** The queue, the knock, and inbound capture are tower-only by
nature. The conversation rules are universal in content but bound only to
tower sessions in this version. Kickoff, drafting, resume, and drain adopt
them behind a gated deferral whose gate is the experiment's measured result.

**Alternatives considered:**
- Rules bind every attended surface now. Rejected because: it reopens a
  Ready bundle's territory and forces the budget question on four more
  skills before the rules have proven anything.
- Towers only, rules included, no path outward. Rejected because: the
  recorded return-from-autonomy failure was at kickoff, so the rules
  evidently apply there; leaving no path wastes the experiment.

**Chosen because:** the operator asked to measure effectiveness before
doing more; the gate makes the boundary a finding, not a guess.

### D-17: A native queue indicator on the statusline channel  (N, kickoff 2026-09-09)

**Decision:** The queue exposes what is waiting through the existing
`statusline` notification channel: the Claude Code status line, driven by
planwright's own render script from the fleet home, which already composes
the worker decision queue's length under `queue`. The queue's field is a
distinct one named `waiting`, bounded in width to the top item's kind plus
one total (per-kind counts stay with the `counts` verb, which feeds it),
under a label that unmistakably reads as planwright's. The read is lock-free
and best-effort: a store that cannot be read, a torn or malformed line, or a
kind outside the closed set all degrade to one distinct unreadable marker,
never a blank or a zero, because a zero reads as "nothing waiting" and that
is the one thing a broken read cannot claim. The render is fleet-autonomy
REQ-F1.2's and is extended in place with that bundle's contract unchanged;
it reads the store only, renders only while a live tower presence exists,
and renders only while that channel is selected, exactly as the fleet stats
do today; that channel coupling is an accepted limitation of the seam. The
operator sees that decisions or actions are waiting without asking.
*(Amended at kickoff sign-off lens 2026-09-09: the unreadable marker, the
live-presence condition, and the owning requirement named.)*

**Alternatives considered:**
- Fold the counts into the one-line knock pushed through every channel.
  Rejected because: it changes the attention capability's transport
  contract, which this bundle consumes and never re-owns.
- No indicator; the knock is the only signal. Rejected because: the
  operator asked for a native signal that does not depend on reading the
  conversation.

**Chosen because:** the operator asked for it, the seam exists, and it is
pull-shaped, so it costs the session nothing and cannot interrupt.

### D-18: Delivery is leased per tower  (N, kickoff 2026-09-09)

**Decision:** The single-spec tower, the meta-tower, and the fleet loop can
run at once on one host over the one queue, so `next` leases the item it
hands over to the calling tower under the fleet advisory lock. The lease is
taken at every hand-over: at the knock for an attention session's first
item, at each `next` for the ones after it. The knock pins the item it
named, so an item arriving above it waits rather than silently replacing
what the operator was told about, and `next` knocks again when the top item
has changed. Release is by event, not by clock: acknowledgement, a shelve,
settling, absorption into a merge, positive evidence of the holder's death,
or the holder having no live presence; the lease interval is only the
backstop for what none of those reach, it is renewed on each reply of the
holding tower, and it is floored at the quiet interval so an attended
conversation never loses the item it is holding. A tower whose attention is
confirmed may preempt a lease held by one whose attention is not, since the
operator is demonstrably in the first conversation. Mutual exclusion is the
lock's; the tower's presence identity is only the lease's owner label,
resolved once per tower with the same flags its presence publish used, and a
caller with no presence identity leases under a tower-session-scoped
fallback identity written into the store. No item is delivered by two towers
at once on a host, and a tower that dies mid-delivery loses its lease rather
than the item. Towers on separate hosts are out of scope: the advisory lock
they would have to share is not.
*(Amended at kickoff sign-off lens 2026-09-09: leases taken at every
hand-over, the knock's pin, the event-driven release set, renewal and the
interval floor, preemption by an attended tower, and the scope narrowed to
one host.)*

**Alternatives considered:**
- Scope items to the tower's own specs, with meta and fleet towers taking
  everything. Rejected because: a single-spec tower running under a fleet
  tower still double-delivers that spec's items.
- Accept double delivery as a risk. Rejected because: the recorded failures
  are about the operator's load, and answering the same question twice in
  two terminals is that load.

**Chosen because:** it is the `claim` verb's first-answer-wins idiom applied
to delivery, over the presence seam the fleet already keeps.

### D-19: A session-relayed push channel  (N, kickoff sign-off lens 2026-09-09)

**Decision:** A `push` value joins the notification channel enum, and it is
the one channel this bundle adds. On it the notify seam writes a
pending-push marker under the fleet home, deduped per item under the fleet
lock, and does nothing else; the tower session relays the marker on its next
step by calling Claude Code's push-notification tool, which reaches the
operator's desktop, and their phone when Remote Control is connected, and
which suppresses itself while the operator is actively working. The relayed
line is one line under 200 characters in the D-10 register, so it reads on a
lock screen. The script therefore still owns no transport, which is what
keeps the out-of-scope boundary honest: the marker is a file, and the only
thing that can call the tool is a session.

**Alternatives considered:**
- Leave phone reach to the existing channel adapters. Rejected because: none
  of them reaches a phone, and the failure on record is a night of blocked
  workers nobody saw; the tool that does reach one can only be called from
  inside a session, so no adapter could have been written for it.
- Have the tower call the tool directly at the moment it decides to knock,
  with no marker. Rejected because: the decision to push happens inside the
  script, under the lock, where the dedupe lives; a session-side decision
  would push once per tower for the same item.

**Chosen because:** it is the only route to the operator's phone the harness
offers, it costs the script nothing but a marker file, and the tool already
declines to interrupt an operator who is present.

## Cross-cutting concerns

- **Decision domains walked.** Queues and async work: delivery is at least
  once, keyed by stable identifier, so redelivery is idempotent; ordering is
  load-bearing and owned by `next`. Concurrency: every store write rides the
  fleet advisory lock; a crash mid-write leaves an atomically renamed
  complete file; delivery across concurrent towers is leased (D-18). The
  advisory lock carries no holder token, so a writer holds it far below the
  stale threshold and re-reads and compares the store before the rename,
  which is the mitigation available rather than a fix. Human
  comprehension and information UX: the surface is
  novel, so research ran first (D-6, D-9). Existing-seam reuse: the minted
  store is recorded with its nearest seam and why it does not fit (D-2).
- **Intervention contract.** The finding-categorization doctrine states the
  contract "in full" as sign-off, hard pauses, review and merge. Task 10
  amends it to state the two routes it now has and the knock as the way a
  hard pause reaches the operator, closing the unowned site on record.
- **Attention capability doc.** Its writer enumeration is stale; Task 10
  refreshes it while adding the sibling queue as a reader.
- **Tower headroom.** The tower's own context budget is the step-count proxy
  the context-budget doctrine defines, and this bundle moves it in two
  directions at once: a hand-over of one item with the shortest context that
  answers it shrinks what each step reads, while the knock, the catch-up,
  and the capture echo add turns, and the step-count proxy counts turns. The
  intended net is smaller steps rather than fewer, and Task 8 measures the
  per-step context growth instead of asserting it.
