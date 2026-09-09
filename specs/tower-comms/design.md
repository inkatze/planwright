# Tower comms — Design

**Status:** Draft
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-09-08). Foreign IDs are namespace-qualified.

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
in the owning spec's Awaiting-input list and the attention store; a request
or a standing decision in the action-item ledger, or in an observation
fragment tagged as a capture or as standing until the ledger ships; news in
the attention store. The store is framework runtime state in the
storage-classes sense: losable, rebuilt from the content homes, costing at
most one repeated delivery.

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
attention and registry stores already use: stable identifier, kind, urgency,
origin (source worker or operator turn, timestamp), pointer to the content
home, closing condition, and delivery state. Every field is validated
against its grammar before a write, and every rendered value passes the
echo-safety sanitizer. The closing condition names the human action that
resolves the item (an answer, a go-ahead, a shelve) or the evidence that
settles it; a record promising a future automatic step is refused.

**Alternatives considered:**
- Free-form markdown per item. Rejected because: unparseable by the settling
  pass, which turns evidence-based settling back into reading.
- Full YAML records. Rejected because: the repo's parsers are constrained
  portable-shell readers; YAML brings a parser dependency and an injection
  surface for no field this record needs.

**Chosen because:** it is the proven local idiom, and the refused-promise
rule closes the park-note failure on record.

### D-5: Settling by evidence; process events are claims  (N)

**Decision:** Before any delivery, a settling pass runs the queue against
the events since the last pass. An item settles only on evidence the
reconcile sweep already trusts (an open or merged PR, commits on the branch,
a closed ledger item, a worker's question answered by another route) or on a
matching written standing decision. A worker's completion report, a result
frame, or a status line is a claim and settles nothing. Same-question items
merge into one that names every source; contradicting items deliver as one
decision. Every settled item records what settled it.

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
then urgency, then age); `ack` records the operator's reply; `shelve` parks
an item with a bounded return. The tower knocks with one line, waits for a
reply, delivers the item, and waits again; any reply releases the next item.
After an autonomous stretch the first turn explains where things stand, not
what the tower did. The vocabulary is borrowed from the process-industry
alarm standard (every surfaced item actionable; acknowledgement logged;
shelving time-limited with automatic return; suppression by design traces to
a written rule) and from on-call tooling (acknowledging halts escalation; an
acknowledged item re-triggers after a timeout).

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

**Decision:** A news item carries an urgency. An urgent one may knock; a
non-urgent one waits for the operator's next engagement or for a request.
In either case the content is delivered only once the operator has
confirmed attention, so news never interrupts and never lands where it will
not be read.

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

**Decision:** A conversation knock with no reply within a configured quiet
interval marks the operator away; any reply marks them present. While away,
a knock also goes through the configured notification channel via the
existing notification seam. It fires once when the first blocking item
appears and again only when the situation worsens: more blocked workers, or
a blocked item passing a configured age. Two knobs: the quiet interval and
the re-knock age, each with a documented default and an options-reference
row.

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
same turn, echoed in one line, with no confirmation required. Its content is
written to the action-item ledger when it exists, and to an observation
fragment tagged as a capture until then. A reply meaning "always" or "from
now on" becomes a standing decision: a ledger item of the standing kind (an
observation fragment tagged as standing until the ledger ships), carrying
the rule in the operator's words, what it covers, and when it was said. This
bundle therefore depends on the ledger's substrate task for the durable
home, and carries the fallback so that nothing blocks on that bundle.

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
names the rule. A prompt outside every written standing decision reaches
the operator. The tower never answers one from its own judgment, a
standing decision never covers a reserved control (the ready flip, the
merge), and mentioning a prompt in a turn does not count as the operator
deciding it.
The invariant that a tower never answers a permission prompt is read as
"never from its own judgment"; the standing decision is the operator's
recorded answer, which the answer channel already requires as input.

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

**Decision:** Every queue event is one JSON line under the fleet home, in
the shape the kickoff dialogue's decision log already uses (schema version,
monotonic sequence, kind, payload), never committed. The scorecard is
computed from the log alone: the headline is the operator's load (items that
reached the operator per hour of fleet work against items settled without
them); secondary measures are blocked-worker wait, multi-ask turns, friction
moments, jargon counts over delivered text, and items lost across restarts.
It runs on demand and never in CI.

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

## Cross-cutting concerns

- **Decision domains walked.** Queues and async work: delivery is at least
  once, keyed by stable identifier, so redelivery is idempotent; ordering is
  load-bearing and owned by `next`. Concurrency: every store write rides the
  fleet advisory lock; a crash mid-write leaves an atomically renamed
  complete file. Human comprehension and information UX: the surface is
  novel, so research ran first (D-6, D-9). Existing-seam reuse: the minted
  store is recorded with its nearest seam and why it does not fit (D-2).
- **Intervention contract.** The finding-categorization doctrine states the
  contract "in full" as sign-off, hard pauses, review and merge. Task 10
  amends it to state the two routes it now has and the knock as the way a
  hard pause reaches the operator, closing the unowned site on record.
- **Attention capability doc.** Its writer enumeration is stale; Task 10
  refreshes it while adding the sibling queue as a reader.
- **Tower headroom.** The tower's own context budget is the step-count proxy
  the context-budget doctrine defines; this bundle adds no signal and
  changes nothing there. A queue whose settling pass runs each step keeps
  the tower's per-step reading bounded, which is the only headroom effect
  intended.
