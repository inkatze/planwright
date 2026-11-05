# Review desk — Design

**Status:** Draft
**Last reviewed:** 2026-11-05
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `S` shaped by a seed or the
operator's earlier practice; `C, <spec> D-<n>` carried from another
bundle.

## Decision log

### D-1: Altitude — a mission-control duty plus a format seam, no new doctrine  (N)

**Decision:** The review desk is a capability built on mission control's
seams: one duty catalog entry, deterministic scripts for every mechanic,
on-demand reviewer sessions for the judgment, the queue for delivery and
the follow-up and undo ledgers for what comes after. The one new
extension point is a format-profile catalog (D-8), whose capability lands
in core and whose values live in overlays. No doctrine is added: the
autopilot reflex already says to automate up to the gate and never
through it, and the gate here (posting a review, a message to a person)
is already a human gate. Walking the reflex: the irreducible human acts
are the yes on each review's exact text and every judgment the operator
keeps (declining, editing, the format itself); everything before them
(noticing, holding, reviewing, drafting, re-checking) is automated;
nothing the operator must remember to start remains, since the desk
brings each batch to them.

**Alternatives considered:**
- A review skill the operator runs when they remember. Rejected because:
  it relocates the burden the operator asked to remove ("constantly look
  for reviews and do them automatically").
- New doctrine for outbound review. Rejected because: the rules the desk
  needs (exact-text yes, untrusted input as data, automate up to the gate)
  already exist as doctrine; restating them would create a second home.
- Folding the desk into mission-control itself. Rejected because:
  mission-control scoped it out as independently ownable and not every
  operator runs one (mission-control D-1, D-27).

**Chosen because:** the seed claims pin a duty-shaped ceremony and a
capability-versus-style call, and mission control's seams already carry
every mechanic the desk needs except formats.

### D-2: The desk is the outbound direction; the inbound cadence stays where it is  (N)

**Decision:** The desk reviews other people's pull requests. On the
operator's own pull requests, requesting automated reviewers, triaging
their findings and recording review rounds stay with the execution
cadence (the convergence and post-PR steps) and the operator-level review
skills; the desk adds only the body-finding read the readiness walk lacks
(D-13). The seed's question of what counts as a round when a merge forces
a full re-review is answered by the floor already in force: review
evidence counts only at the current head (mission-control D-25), so a
merge that moves the head needs a new round, and this bundle does not
carry evidence across heads.

**Alternatives considered:**
- Both directions as one duty, moving the bot-review triage into the
  desk's watchers. Rejected because: the triage already runs as cadence
  steps every unit executes, and a second owner would split one
  responsibility across a duty and a step.
- Carrying review evidence across a head whose patch is unchanged.
  Rejected because: it lowers a readiness floor, and a weakened gate is
  not traded for a saved review round.

**Chosen because:** the operator's request is the outbound job, and the
inbound job already has an owner that works.

### D-3: A watcher over the shared snapshot fires one reviewer per pull request per patch  (S)

**Decision:** The desk's watcher is a script on the duty runner at a
declared cadence and cost class. It reads mission control's forge
snapshot, never the forge directly, so the snapshot's tracked set grows to
include the pull requests that request the operator's review, with the
fields the desk needs (review requests including teams, the review
decision, the operator's latest review and whether it was dismissed,
automated threads and review bodies, the head and base, the patch id).
For each pull request it applies the scope rules (D-4), advances the
queue (D-5) and, for a record that needs a review, emits a trigger the
launcher turns into one reviewer session for that pull request. A record
already reviewing starts no second session; a patch already reviewed
starts none.

**Alternatives considered:**
- A standing reviewer session that polls all day. Rejected because: the
  operator's earlier practice measured it as the costliest part of the
  desk, and mission-control forbids standing watcher sessions
  (mission-control REQ-C1.5).
- The watcher querying the forge itself. Rejected because: one snapshot
  per source per program is the rule (mission-control REQ-M1.1), and two
  pollers over the same pull requests is the failure it exists to
  prevent.
- Forge webhooks. Rejected because: they need a reachable endpoint on the
  operator's machine; the snapshot's cadence plus mission control's push
  path is the existing route.

**Chosen because:** scripts outlive sessions and cost nothing between
events, and the snapshot already carries a patch id, which is exactly the
"has this changed" test the desk needs.

### D-4: Scope rules are data, with a default that works for any operator  (S)

**Decision:** Scope rules are entries in a `review-scope` catalog merged
through the four overlay layers, one entry per program, optionally
narrowed to a repository: repositories, whether team requests count,
labels and paths to include or exclude, authors to skip, whether drafts
are reviewed, whether a pull request already approved by others is
skipped, and whether unanswered automated findings hold it. A catalog,
not a knob, because most of these are sets and the flat knob file has no
list encoding (obs:08213768). The default reviews open, non-draft pull requests in the
program's repositories that request the operator's account directly or
through a team, never the operator's own, skips one whose forge review
decision is already approved, and holds one with an unanswered automated
finding (classified by D-13's shared classifier). A head change with an
unchanged patch id is a restack and never starts a review. The entry
grammar is fixed by Task 4 in the catalog's header, the way the duty
catalog documents its own.

**Alternatives considered:**
- Review every pull request in the program's repositories. Rejected
  because: it spends reviews nobody asked for and drafts messages to
  people who did not request them.
- Hardcoded scope in the watcher. Rejected because: scope is the most
  operator-specific part of the desk (REQ-B1.1), and mission-control makes
  every preference configurable (mission-control D-20).
- A `mission_control_review_scope` knob. Rejected because: set-valued
  knobs must be space-separated single-line values (obs:08213768), which
  cannot carry per-repository rule sets readably.
- Skipping only when another reviewer approved, ignoring branch
  protection. Rejected because: the forge's review decision already
  accounts for required approvals, so it is the honest "nothing left for
  you here" signal.

**Chosen because:** the default reproduces what an operator means by
"review what I'm asked to", and everything else is a setting.

### D-5: One durable record per pull request, seven states, scripted transitions  (S)

**Decision:** The queue is one record per tracked pull request under the
duty's owned files in the program home, written only by the desk's queue
script under the knowledge-base lock, with an append-only transition log.
The states are the operator's: new, held, reviewing, awaiting-operator,
submitted, re-review, done. Allowed transitions:

| From | To | Cause |
| --- | --- | --- |
| (none) | new | a pull request enters scope |
| new, re-review | held | an automated finding is unanswered |
| held | new, re-review | every automated finding is answered |
| new, re-review | reviewing | a reviewer session is launched |
| reviewing | awaiting-operator | a valid structured review is rendered and checked |
| reviewing | new, re-review | the session failed or its result was refused |
| awaiting-operator | submitted | the post succeeded |
| awaiting-operator, submitted | re-review | the patch changed, or an approval was dismissed |
| awaiting-operator | awaiting-operator | the pre-post re-check found new reviews, or the operator edited the draft |
| any | done | merged, closed, out of scope, approved by others, or settled by the operator |

Every write records the time, the cause and the head. A transition not in
the table is refused. A record never disappears: done carries its settling
reason. In shadow, the same transitions are computed and logged as
would-have entries, and no item is raised.

**Alternatives considered:**
- Keeping review state in the operator queue's items. Rejected because:
  the queue holds what waits on the operator, while most of a record's
  life (new, held, reviewing, submitted) waits on someone else; one store
  per concern is the knowledge base's existing layout (mission-control
  D-9).
- Deriving state from the forge on every tick with no store. Rejected
  because: the operator's yes, the reviewed head and the draft digest
  exist nowhere on the forge.

**Chosen because:** the operator named the states from practice, and an
explicit transition table makes every move checkable by a test.

### D-6: Review material comes from the forge API into a private export  (S)

**Decision:** A script builds the reviewer's material from the forge API
only: the pull request's metadata, the diff between the reviewed head and
its comparison point (D-11), and the contents of changed files at the
head, written into a fresh private temporary directory outside every
checkout, with every path validated and containment-checked after
canonicalization and every file written as data (no executable bits, no
symlinks followed). Nothing is fetched into a local repository, and
nothing from the pull request runs. The export is deleted when the
session ends.

**Alternatives considered:**
- Fetching the head into a bare cache repository. Rejected because: the
  operator's practice keeps git read-only, and a fetched ref is one
  `checkout` away from running hostile hooks or tooling.
- Exporting a fetched head with `git archive`. Rejected because: it still
  needs the fetch.
- Running the project's tooling on the export. Rejected because: its
  configuration is the pull request author's, and running it is executing
  untrusted input.

**Chosen because:** the forge API gives every byte a review needs, and
data that never touches a checkout cannot change one.

### D-7: The review is a pluggable step with a shipped default reviewer  (N)

**Decision:** The reviewer session is launched through the launcher as a
reviewer-kind session with a read-only permission profile (no forge
writes, no git network operations, reads confined to its export and the
planwright install) and a brief naming the pull request, its export and
the review step. The step resolves through the steps catalog from the
`mission_control_review_step` knob, so an operator can plug in their own
review command. The shipped default is a reviewer brief that applies
planwright's discovery and validation doctrine to the export (its lens
list, validated findings only) and returns the structured review: the
head covered, a verdict (approve, comment, request changes), each finding
with severity, file and line, evidence and a suggested comment, and a
security-blocker flag. A result that is not valid against that contract
is refused and the record returns to new or re-review with the reason.
The session never posts; it cannot.

**Alternatives considered:**
- A new planwright review skill. Rejected because: a skill costs
  instruction budget on a saturated surface, and the reviewer's job is a
  brief plus existing doctrine.
- Requiring the operator's own review command. Rejected because: an
  operator new to planwright has none, and what is shown as working must
  work with no setup (mission-control D-40).
- Letting the session post on a yes it relays. Rejected because: a
  session reading untrusted content must not hold write access; posting
  is a separate script after the operator's yes (D-10).

**Chosen because:** the default makes the desk work everywhere, the step
seam keeps an expert's own reviewer usable, and the read-only profile
contains whatever the pull request's content tries.

### D-8: Review formats are profiles in a catalog; the format's details are open  (N)

**Decision:** A review's text is rendered from the structured review
through a **format profile**. Profiles are entries in a `review-formats`
catalog merged through the four overlay layers like steps and duties. The
profile for a review is selected by the reviewing account and the
repository, most specific first: that account's profile for that
repository, the account's profile, the program's profile, then the
shipped default. Each profile entry carries the selectors it applies to
(a reviewer, a repository, a program), so selection needs no separate
mapping knob, which the flat knob file could not hold (obs:08213768). A
deterministic renderer turns the structured review into
text under the profile, the reviewer session supplying only the wording a
template cannot (the summary, each finding's comment) in the profile's
tone; a deterministic check then verifies the draft against the
profile's mechanical rules before it reaches the operator.

What a profile can express is the operator's list: structure, tone,
severity labels, length, and what to include or leave out. **Open,
awaiting the operator** (recorded as the Awaiting-input entry on Task 8):
the profile's fields and their grammar; the shipped default profile's
values; whether "reviewer" keys on the posting account, on a reviewer
persona the operator names, or both; whether findings post as inline line
comments, in the review body, or as a profile choice; and which rules the
check enforces mechanically. Until the operator answers, no field or
default value is fixed by this bundle.

**Alternatives considered:**
- A free-form style prompt per reviewer. Rejected because: prose cannot be
  checked, and a profile the check can verify is what keeps a draft
  inside the format the reviewer set.
- One knob per format dimension. Rejected because: formats differ per
  account and repository as whole units, which is a catalog entry, not a
  set of scalar knobs.
- Guessing the fields now. Rejected because: the operator said they will
  send the details, and a guessed grammar becomes a migration later.

**Chosen because:** the customization boundary runs through this feature:
the ability to set a format is general (core catalog and resolver), the
format a reviewer wants is style (an overlay entry).

### D-9: Batched delivery, and a yes bound to the exact text  (S)

**Decision:** Finished reviews reach the operator as one queue item per
batch, one line per pull request (title, link, verdict, finding count),
each draft's full text one request away. A security-blocker flag also
raises an immediate heads-up through the notification seam, which posts
nothing. A yes binds a digest of the exact rendered text, the recipient
pull request, the verdict and the head the review covered. A batch yes
covers exactly the drafts whose full text the operator was shown in that
batch, recorded by digest; a draft shown only as its one line needs its
own yes. Any edit produces a new digest and needs a new yes. A decline
settles the record with the operator's reason.

**Alternatives considered:**
- One item per review. Rejected because: the operator's practice batched
  them, and per-review items flood the inbox.
- A batch yes covering every line in the batch. Rejected because: the
  operator would be approving texts they had not read, which is not a yes
  on the exact text (mission-control REQ-I1.3).

**Chosen because:** batching keeps the inbox small, and the digest makes
"the exact text" mechanical rather than a matter of trust.

### D-10: Re-check, then post exactly the approved text through one script  (S)

**Decision:** One post script, run only from an approved item, re-reads
the pull request from the forge immediately before posting: it must be
open, its head must equal the reviewed head, and its reviews since the
draft are compared. A moved head lapses the yes and moves the record to
re-review; a new review by anyone (including the operator posting by
hand) returns the draft to the operator with what changed; a closed pull
request settles the record. On a clean re-check the script posts the
approved text, verdict and line comments under the operator's own forge
account, verifies the posted body's digest matches, and appends an undo
entry naming the act and its reversal where one exists (a line comment
can be deleted; a submitted review can be edited or, for an approval,
dismissed where the account may).

**Alternatives considered:**
- Posting from the reviewer session. Rejected because: D-7.
- Trusting the snapshot's age for the re-check. Rejected because: the
  window between the yes and the post is exactly when a push lands.

**Chosen because:** a post is the one irreversible-to-a-person act, so it
gets a fresh read and a single audited writer.

### D-11: After the post — re-review, dismissed approvals, follow-ups  (S)

**Decision:** A changed patch on a submitted or awaiting-operator record
moves it to re-review; the re-review covers the change since the last
reviewed head when that head is an ancestor of the new one (the forge's
compare between the two heads), and the whole pull request otherwise. When
the operator's approval was dismissed and the re-review keeps the verdict,
the desk restores the approval with an empty body only under the
`mission_control_review_reapprove` standing exception, off by default;
otherwise it asks the operator with a one-line item. A changed verdict
is a new draft like a first review. The author's replies on the
operator's review threads arrive as items with a drafted answer, posted
only on a yes. A promise in a draft or reply (the operator's own edit
included) is proposed with it as a structured field carrying its trigger
(a head change, a date, a reply, another pull request merging), listed on
the yes item so the operator confirms it with the text, and written to
the follow-up ledger with its owner when the post lands (confirm, then
write); a due follow-up starts its act through the desk. A record is
done when its pull request merges or closes.

**Alternatives considered:**
- Re-approving automatically, as the earlier practice did. Rejected as
  the default because: an approval notifies the author, so it is a
  message, and standing exceptions exist only as named configuration
  (mission-control REQ-I1.3); the knob gives the operator that practice
  back in one setting.
- Full re-reviews on every change. Rejected because: a delta review is
  cheaper and is what a human reviewer does.

**Chosen because:** it matches the operator's practice inside the
message rule, and every later act rides an existing ledger.

### D-12: Cost, admission and quiet hours  (S)

**Decision:** The watcher declares a low cost class at a cadence tied to
the snapshot's. Each reviewer launch passes mission control's launch
admission (host load and the usage limit, mission-control D-41) and the
program budget; a launch that cannot be admitted waits in the queue and is
never dropped. A `mission_control_review_quiet_hours` knob, unset by
default, names local time windows in which no reviewer starts and no
standing-exception post goes out; a post the operator says yes to in the
window still goes out, since the operator is present and asked for it.
Records keep advancing through the scripted states meanwhile. In shadow
the reviewer sessions do run, since the would-have drafts are what the
operator compares before promoting the desk; that spend is the price of
earning trust and is admitted like any other launch.
Reviewer sessions run on the model tier the allocation seam gives the
reviewer kind.

**Alternatives considered:**
- A fixed daily review window. Rejected because: quiet hours are the
  operator's to set, and none is the honest default.
- Dropping launches over budget. Rejected because: nothing is dropped
  (mission-control REQ-F1.5).

**Chosen because:** the desk spends only when there is a new patch and
room to spend.

### D-13: One automated-finding classifier, with body findings  (N)

**Decision:** The readiness walk's thread rule (a thread an automated
reviewer opened is a finding, answered once resolved or replied to by a
person other than the author) moves into a shared classifier the desk's
hold also uses. The classifier gains body findings: an automated
reviewer's configuration may declare a pattern that marks a finding in its
review body (a bot reviewer can return findings only there, with no
thread at all, obs:8b24690f) and a marker that marks one answered (a reply carrying the
marker, beside the reviewer's existing finding-key pattern). A configured
body finding counts for readiness until answered. When an automated
reviewer posted a body at the current head and has no body configuration,
the walk's verdict says in plain words that the body was not read for
findings.

**Alternatives considered:**
- Failing closed on every review body. Rejected because: summary bodies
  are universal, so every pull request would block (the review-body
  findings seed).
- Leaving body findings to the desk alone. Rejected because: the gap is on
  the operator's own pull requests, which the desk does not review (D-2).

**Chosen because:** one classifier keeps the two readers agreeing, and the
named gap stops the silent pass without blocking on summaries.

### D-14: Company data stays in the program home  (C, mission-control D-8)

**Decision:** Every desk artifact holding pull request content (the
queue, exports, drafts, follow-ups, would-have entries) lives in the
program home or a private temporary directory, never in a committed file.
The operator's past positions are read from the forge at review time (the
operator's earlier reviews in that repository), not copied into a
committed store; the knowledge base may hold a bounded local note only
where the operator asks.

**Alternatives considered:**
- A committed record of the operator's positions. Rejected because: it
  copies company data out of company systems (mission-control REQ-I1.6).

**Chosen because:** the forge already holds the operator's history, and
reading it live keeps it where it belongs.

### D-15: Decision-domain walk  (N)

**Decision:** The domains this bundle touches and how each is settled:

- **Authentication and authorization.** The desk posts under the
  operator's own forge account through the forge CLI's existing
  authentication; no new credential is minted or stored. Authority to post
  is the operator's per-text yes (D-9); the reviewer session holds no write
  permission (D-7). Escalated: the one standing exception (D-11) is off
  until the operator turns it on.
- **Untrusted input.** Every pull request byte is untrusted: exports are
  data (D-6), the reviewer cannot write (D-7), drafts pass a mechanical
  check (D-8), and nothing posts without the yes. A prompt planted in a
  diff can at worst skew a draft the operator reads before it goes out.
- **Data storage.** Program-home records under the duty's files and the
  knowledge-base lock (D-5, D-14).
- **Concurrency.** One session per pull request; every queue write takes
  the lock; the pre-post re-check closes the yes-to-post window (D-10).
- **LLM output quality.** A review is model output made load-bearing only
  through the operator's yes, so the yes is the acceptance gate. The
  shadow period is the measure: promotion to live is suggested after the
  configured count of would-have reviews the operator agreed with
  (mission-control D-15). No separate eval set is introduced here; a
  default-reviewer eval is a candidate once shadow records exist.
- **Human comprehension.** The batch line, the full-text layer and the
  heads-up follow the inbox's existing register (mission-control D-19);
  the reviews-at-a-glance view gains state and waiting columns rather
  than a new surface (D-16).
- **Existing-seam reuse.** Reused: the duty catalog, the launcher and
  admission, the forge snapshot, the queue, the notification seam, the
  follow-up and undo ledgers, the steps catalog, the catalog resolver,
  the config-knob seam. Minted: the per-pull-request queue store, because
  the operator queue holds only what waits on the operator (D-5); the
  `review-scope` catalog, because scope rules are per-repository sets the
  knob file cannot encode (D-4); and the `review-formats` catalog, because
  no catalog holds rendering profiles (D-8). Both catalogs ride the
  existing catalog resolver, so they are new entries in an existing seam,
  not a new seam.
- **Secrets and configuration.** No secret is read or stored; formats,
  scope and quiet hours are knob values and catalog entries.

**Alternatives considered:**
- Leaving the walk implicit in the other decisions. Rejected because: the
  catalog asks that stake-bearing domains be named, and authorization and
  untrusted input both are.

**Chosen because:** it records where each stake-bearing call sits so a
kickoff can check it.

### D-16: What a merge waits on from people is shown, never treated as ready  (S)

**Decision:** From the snapshot's forge fields (the review decision, the
requested reviewers and whether each is a code owner, the latest review
per reviewer, the merge state), the desk derives for every tracked open
pull request what its merge waits on from people: a required approval not
yet given, changes requested, a code-owner review outstanding, another
required human review the forge reports, or nothing; with whom it waits on
and since when. The waiting reason is a read-only derivation, not a queue
state: it rides beside the seven states for reviewed pull requests and
stands alone for the operator's own. Wherever mission control would
present a pull request as ready to merge (the merge recommendation, the
prepared packet, status), a waiting reason replaces that with a plain
statement of what it waits on and from whom; at the guided level it also
says why that matters, per mission-control D-31. The reviews view shows
the reason, the person and the wait. A pull request waiting only on the
operator is said so in the batch line.

Acts that could move a waiting pull request of the operator's (requesting
a reviewer, a reminder to the person it waits on) are drafts that go out
only on the operator's yes. **Open, awaiting the operator** (the
Awaiting-input entry on Task 14): whether the desk offers a reminder at
all, after how long, to whom, and whether a pull request waiting on the
operator's own review should jump ahead of others in their queue.

**Alternatives considered:**
- A new queue state for waiting on approval. Rejected because: the seven
  states track the desk's own work on a review, while the wait is a fact
  about the pull request that also applies to pull requests the desk does
  not review (the operator's own).
- Leaving it to the readiness check. Rejected because: readiness decides
  whether a pull request may be flipped ready, while this is about what a
  ready pull request still waits on before it can merge.
- Sending reminders automatically after a timeout. Rejected because: a
  reminder is a message to a person (mission-control REQ-I1.3).

**Chosen because:** the forge already reports every input, and a merge
recommendation that hides a pending approval is the misleading moment the
operator priority names (telling a novice plainly what a pull request
still needs before they merge it).

## Cross-cutting concerns

- **Instruction budget.** The desk adds no skill; its judgment lives in a
  reviewer brief and existing doctrine, and mission control's own skill
  gains at most a word-neutral pointer to the desk's items.
- **Shadow first.** Every task's behaviour is testable in shadow with a
  fixture snapshot before any live forge write exists.
- **Portable shell.** Every script follows the repository's portable-shell
  and echo-discipline rules; forge reads go through the forge CLI's own
  authentication.
