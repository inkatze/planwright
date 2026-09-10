# Tower comms — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the queue script's
grammar, verbs, ordering, settling fixtures, the away state machine, the
log and scorecard arithmetic, and the repository's existing index, link,
options, and instruction-budget checks, all run by `mise run check` and the
repository CI); `[Gherkin]` for the delivery and settling scenarios the
script must produce, exercised as fixtures in the same tests; `[manual]`
for the real-session halves of the baseline and the experiment, run and
recorded by the worker for the reviewer to re-read; `[design-level]` where
a rule's presence in the named doc is the verification.

## REQ-A — The operator queue

### REQ-A1.1 — One queue for everything [test + Gherkin]

Scenario: given a worker question, an approval the tower proposes, and an
operator request captured in the same session, when the queue is listed,
then all three appear as items and none exists only in the session's turn
text. The scorecard's "items delivered in prose with no queue record"
measure counts the negative case over the same session's log (Task 1).
Tested over a fixture session in Task 8.

### REQ-A1.2 — Five kinds, each with a closing condition [test]

The `add` verb accepts exactly the five kinds and refuses any other; a
record without a closing condition, or with one naming a future automatic
step, is refused with a message; an urgency outside `high`, `normal`, `low`
is refused, and a worker-question item inherits its attention-store row's
priority; a standing decision is accepted, never appears in `next` or in the
ranking, and its closing condition reads as the operator's revocation. Unit
tests in Task 3.

### REQ-A1.3 — Content in its home, delivery state in the store [test]

For each kind, a fixture `add` writes the content to the named home before
it writes the index record, and the store record carries a pointer and the
delivery fields only; a request, an approval, and a standing decision land
in the pre-ship fallback file with the ledger helpers absent; a parked
worker question's record points at both the attention-store row and the
Awaiting-input bullet, and an unparked one at the row alone, carrying that
row's instance identifier, on whose mismatch `next` refreshes or refuses; a
grep of the store finds no content text; a settled record older than the
catch-up window is absent from the store while the open items remain. Unit
tests in Tasks 3 and 6.

### REQ-A1.4 — Under the fleet home and lock, surviving the tower [test]

Concurrent-writer test: two writers add and ack under the lock and the
store holds every record untorn; a store written by one process is read
intact by another after the first exits; the store, the log, the attention
markers, and the fallback file are owner-only inside a `0700` sub-surface,
and a loosened mode refuses the write; a lock-saturation test holds the lock
past `tower_hook_lock_wait` and the blocked verb reports the expiry as an
error rather than writing. Unit tests in Task 3.

### REQ-A1.5 — Loss costs one redelivery per open item [test + Gherkin]

Scenario: given a populated queue, when the store file is deleted and the
script runs `next`, then the queue is rebuilt from the content homes and at
most one previously delivered-but-open item is delivered again. Scenario:
given a shelved item and a settled item with its reason, when the store is
deleted and rebuilt, then the shelved item returns at once and the settled
history is read back from the event log instead. Scenario: given an
undelivered attention-sourced item whose row has since moved on, when the
store is rebuilt, then that item is absent and its log line is present.
Unit tests in Task 3.

### REQ-A1.6 — Constrained grammar and echo safety [test]

A hostile-input table (traversal tokens, embedded tabs and newlines,
control bytes, over-long fields, a leading-whitespace prefix, and a content
pointer that canonicalises outside the declared root) is refused at every
verb; a hand-corrupted store line renders with no control byte on stdout.
Unit tests in Task 3.

### REQ-A1.7 — One delivery per item across towers [test + Gherkin]

Scenario: given one open item and two callers of `next` with distinct
presence identities and attention confirmed for both, when both call, then
exactly one receives the item, the store's lease record names that caller,
and the other receives nothing or a different item. Scenario: given a caller
on a second host, then it is outside what this bundle claims and no test
asserts it. Unit tests in Task 3.

### REQ-A1.8 — The lease's lifecycle [test + Gherkin]

Scenario: given an attention session's first item, when the knock goes out,
then the lease is already taken and pins that item, and when a
higher-ranking item arrives before the reply, then `next` knocks again
naming the new top item. Scenario: given a leased item, when its holder
acknowledges, shelves it, settles it, absorbs it into a merge, is shown
positively dead, or loses its live presence, then the lease is released
without waiting for `tower_lease_interval`. Scenario: given a lease and a
reply from its holder, then the lease's deadline moves out. Scenario: given
a lease held by a tower whose attention is unconfirmed and a second tower
whose attention is confirmed, when the second calls `next`, then it preempts
the lease. A configuration setting `tower_lease_interval` below
`tower_quiet_interval` is refused. Unit tests in Task 3.

### REQ-A1.9 — The lease's owner label [test]

`next` resolves the presence identity once per tower with the flags the
presence publish uses and writes it into the lease record; a caller with no
resolvable presence identity leases under a tower-session-scoped fallback
identity, which is written into the store and read back by a later caller.
Unit tests in Task 3.

## REQ-B — Settling and merging

### REQ-B1.1 — The settling pass is level-triggered [test + Gherkin]

Scenario: given a parked question whose PR has since merged, when `settle`
runs, then the question is settled with a record naming the merge and is not
delivered. Scenario: given an item whose closing condition was already met
before the previous pass ran and no new event since, when the pass runs
again, then it is still settled, because the pass reads the condition rather
than a stream of events. Scenario: given one tower-loop iteration, then
exactly one pass runs and the `next` that follows reuses it rather than
running its own. The pass reads the reconcile sweep's derived evidence and
its TTL-stamped fetch (no second poll appears in the trace), and the fleet
lock's hold time over a large fixture stays inside the stated bound.
Fixtures in Task 4.

### REQ-B1.2 — Only evidence settles [test + Gherkin]

One fixture per evidence source settles the matching item and nothing
else, and the three routes counted as answered-by-another-route (an
acknowledgement on the item, a `claim` close on the worker's record, a
matching standing decision) each settle while a worker's own output settles
nothing. Scenario: given a worker whose status reports completed and success
while its branch has no commits and no PR, when the settling pass runs, then
its item stays open. Scenario: given an evidence source that cannot be
reached, when the pass runs, then it is logged as unavailable, nothing is
settled from its silence, and a worsening re-knock that depends on it is
held. Scenario: given an item whose content home has been removed, when the
pass runs, then the item is settled with that reason and the reason is
logged. Fixtures in Task 4.

### REQ-B1.3 — Merge duplicates, pair contradictions [test + Gherkin]

Scenario: given two workers asking the same permission with prompts that
differ only in worker handle and worktree path, when the settling pass
runs, then one item remains naming both sources, carrying the higher
urgency and the older age. Scenario: given two command-bearing items
differing only in letter case or spacing, then they do not merge. Scenario:
given two open items of the same kind naming the same subject key (worker
handle, PR number, or branch), when `next` runs, then they are handed over
as one item naming both sources and a third on the same subject waits;
given two items with different subjects, two items of different kinds on
the same subject, or a candidate that is leased or already delivered, then
they are not paired. A large fixture confirms merging and pairing are one
keyed pass. Fixtures in Task 4.

### REQ-B1.4 — Self-settled items available, never pushed [test + Gherkin]

Scenario: given three items settled by evidence since the last delivery,
when `next` runs, then it prints one open item, one knock line, or nothing,
and never a settled item; when `catchup` runs, then all three appear with
their reasons. Scenario: given more settled items than
`tower_catchup_limit`, when `catchup` runs, then it lists that many and then
a count of the remainder. Scenario: given an item settled while the operator
was away, then its record says so, for the tower to say in the next turn.
Fixtures in Task 4.

### REQ-B1.5 — Mentioning is not deciding [test]

An item delivered but not acknowledged stays open across turns and across
a restart; only an ack or a matching standing decision closes it. Unit
tests in Tasks 3, 4, and 6.

## REQ-C — Attention and delivery

### REQ-C1.1 — At most one hand-over per call [test]

`next` prints one item, one knock line, or nothing, under every queue size
in the fixture set; a paired contradiction prints as the one item it is
handed over as, not two; two towers calling in the same window each get
their own one, which is the accepted per-conversation reading of the bound.
Unit test in Task 3.

### REQ-C1.2 — Knock first, content after attention [test + Gherkin]

Scenario: given an open question and no confirmed attention, when `next`
runs, then it prints the one-line knock and no item content; when the
attention marker advances and `next` runs again, then the item content is
printed; given the quiet interval has passed since the last reply, then
`next` knocks again before any content; given a knock the REQ-F1.3 rule does
not allow yet, then `next` prints nothing at all rather than a knock.
Scenario: given a store that cannot be written, when `next` runs, then the
turn carries an error and no item is silently skipped. Unit test in Task 3;
the knock text grammar unit-tested in Task 5; the whole turn exercised over
the fixture session in Task 8.

### REQ-C1.3 — Answerable alone, context on request [design-level + manual]

The rule doc states the answerable-alone and one-layer-on-request rules
(Task 7). Manually checked on the experiment sessions: each delivered item
was answerable from its message, recorded in the Task 9 entry.

### REQ-C1.4 — Any reply releases the next item [test + Gherkin]

Scenario: given two open items, when the operator replies to the first with
anything and the attention marker advances, then the next is delivered; when
the marker has not advanced, then no second item is delivered, whatever else
the turn contained. Fixture session in Task 8.

### REQ-C1.5 — Ordered by consequence [test]

A mixed fixture queue, run with attention confirmed so `next` prints one
item rather than the knock line, orders blocked workers, approvals,
requests, then news, with urgency then age inside each kind; a standing
decision in the same fixture never appears in the ordering at all. Unit test
in Task 3.

### REQ-C1.6 — Shelve with bounded return [test]

A shelved item is absent from `next` until its return time and present
after; the return time follows the shelve-return knob's default and an
override; no verb drops a shelved item. Unit tests in Tasks 3 and 5.

### REQ-C1.7 — News is urgency-gated [test + Gherkin]

Scenario: given a non-urgent news item and no operator engagement, when
time passes, then no knock fires; given an urgent one and an attended
conversation, then a knock fires there and the content is delivered only
after a reply. Scenario: given an urgent news item and the operator away,
then nothing is pushed on any channel and the item waits for the attended
knock. The urgency field accepts exactly the three values. Fixtures for
each of these in Task 5.

### REQ-C1.8 — The first turn after silence explains state [design-level + manual]

The rule is stated in the rule doc (Task 7). The list the tower reads to
compose that picture is produced by the `catchup` verb (Task 4) and wired
into the first turn in Task 8, where a fixture session shows the picture in
plain words and the list itself only when the operator asks for it. Manually
checked on the experiment sessions: the first turn after an autonomous
stretch described state, not the tower's actions, which is recorded in the
Task 9 entry.

### REQ-C1.9 — The native queue indicator [test]

`counts` over a fixture queue prints the open count per kind and the top
item's kind, which is what feeds the field (Task 3); with
`notification_channel: statusline` the status line render includes a field
named `waiting` (the top item's kind plus one total) under the planwright
label, an absent store, a torn or malformed line, and a kind outside the
closed set each render one distinct unreadable marker rather than a blank or
a zero while the rest of the line still renders, the read takes no lock, the
field renders only while a live tower presence exists, the render completes
inside its stated latency ceiling over a full-sized store, and with any
other channel the render includes nothing from the queue (Task 5).

### REQ-C1.10 — Attention comes from the harness marker [test + Gherkin]

Scenario: given a tower whose marker file has not advanced since its last
delivery, when `next` runs, then it hands over nothing, however many replies
the event log happens to hold. Scenario: given the prompt-submit hook runs
on an operator turn, then the marker advances even when the log line is
dropped for a lock wait. Scenario: given two towers, when one's marker
advances, then only that tower's attention is confirmed. Scenario: given an
attention session already knocked, when the operator replies, then the next
item is handed over with no fresh knock, until the quiet interval passes and
the next delivery knocks again. Scenario: given `ack` called by a tower
holding no lease on the item, then it is refused and logged as a duplicate
no-op; given `ack` on an already-closed item, then it is a logged no-op; in
neither case, nor on a successful `ack`, is a further item released. Unit
tests in Tasks 2 and 3.

### REQ-C1.11 — Write failures surface [test]

An unwritable store, an unwritable marker, and an unwritable log each make
the verb report an error the turn carries, with no silent skip; a delivery
whose log append fails still hands the item over and surfaces the error, and
the redelivery it can cause is the one REQ-A1.5 already budgets. Unit tests
in Task 3.

## REQ-D — Speech

### REQ-D1.1 — The register [design-level + test]

The rule doc names the assumed reader and the words that need no gloss
(Task 7). The jargon word list ships with the script and the scorecard's
count reads it (Task 1); the doc cites that list rather than restating it.

### REQ-D1.2 — Name things by what the operator sees [design-level + manual]

Stated in the rule doc (Task 7). Manually checked on experiment sessions;
positional labels found are counted in the Task 9 entry.

### REQ-D1.3 — The listener-side word test [design-level]

Stated in the rule doc and restated in the operator's terms in the fleet
guide (Tasks 7 and 10).

### REQ-D1.4 — Delivered text is lintable [test]

The scorecard counts spec identifiers, internal names, and listed doctrine
terms in a fixture log's delivered text and reproduces hand-computed
counts. Unit test in Task 1.

## REQ-E — Inbound capture and standing decisions

### REQ-E1.1 — Capture in the same turn, echo one line [test + Gherkin]

Scenario: given an operator message asking for something, when the turn
runs, then a request item exists and the turn contains a one-line echo and
no confirmation prompt. Scenario: given an operator question the tower
answers inside the same turn, then no item is created for the question
itself. Fixture session in Task 8; the capture verb unit-tested in Task 6.

### REQ-E1.2 — Content in the ledger or its fallback [test]

With ledger helpers present, capture writes a ledger item; without them, a
record in the pre-ship fallback file under the fleet home, which is created
untracked and owner-only; a request and an approval each land there; the
queue record points at whichever home was written. Unit tests in Task 6.

### REQ-E1.3 — Standing decisions recorded [test]

A reply containing an always-form creates a standing record carrying the
rule text, coverage, and date, in the ledger or the fallback file; a
command-coverage value that is a glob, a regex, empty, carries a control
byte, or begins with whitespace is refused; a coverage naming a reserved
control (merge, ready, force-push, amend, squash, rebase) is refused at
`capture`; a non-command rule is stored with free coverage text and, when
the operator named one, an explicit subject key. Unit tests in Task 6.

### REQ-E1.4 — Settling names the rule [test]

Every settle-by-standing-decision record and its log line carry the
decision's identifier, and the text the tower speaks for that settle names
the rule in the operator's words with no identifier in it. Unit tests for
both halves in Task 6.

### REQ-E1.5 — Permission prompts strictly inside a rule [test + Gherkin]

Scenario: given a standing decision whose coverage lists a literal command
prefix and a permission record whose `command` field starts with it, when
the settling pass runs, then the prompt is answered through the answer
channel and the log names the rule. Scenario: given a prompt one token
outside every rule, or one whose command shares only part of a token with a
prefix, then it is queued for the operator and nothing answers it.
Scenario: given a covered prefix followed by more of the same token, then
it does not match. Fixtures in Task 6.

### REQ-E1.6 — Questions answered, work captured [design-level + manual]

Stated in the rule doc (Task 7); checked manually on the experiment
sessions and recorded in the Task 9 entry.

### REQ-E1.7 — Non-command rules surfaced [test + design-level + manual]

Scenario: given a standing decision with free coverage text, an explicit
subject key, and an open item naming that subject, when `next` runs, then
the item is delivered with the rule beside it and the item stays open; when
the tower's reply applying the rule names it, then the settling record
carries the decision's identifier. Scenario: given a permission prompt, then
it is the only place a rule settles mechanically; every other kind stays
open. With no subject key recorded, surfacing is the tower session's
judgment: the rule doc states it (Task 7) and the experiment sessions record
what was surfaced (Task 9). Fixtures in Task 6.

### REQ-E1.8 — The command a match reads [test]

The `PermissionRequest` hook writes the harness payload's command text into
the record's `command` field and stamps the `permission` marker in field 9;
a record carrying neither, or carrying the field with no marker, is refused
by both the match and the answer channel's re-match rather than matched from
any other text on the record. Unit tests in Task 6, with the hook's payload
fixture from Task 2.

### REQ-E1.9 — The allowlist and the reserved controls [test + Gherkin]

Scenario: given a command that starts with a covered prefix and continues
with `;`, `|`, `&&`, a newline, a backtick, `$(`, or any other byte outside
`[A-Za-z0-9._/@:=+-]`, spaces, and quoted-string interiors, when the
settling pass runs, then it is queued and never answered. Scenario: given a
rule that somehow covers a reserved-control shape, then the mechanical
refusal fires at match time regardless of that coverage. A command carrying
non-ASCII bytes renders for approval as escapes beside a warning. Fixtures
in Task 6.

### REQ-E1.10 — The answer channel's own check [test + Gherkin]

Scenario: given an answer to a permission-park that names no standing
decision, when the answer channel is called, then it is refused as today;
given an answer whose named decision is not of the standing kind, or does
not cover the parked command on the channel's own re-match, then it is
refused. Scenario: given an accepted answer, then the item settles only
after the channel is confirmed to have exited zero, and a non-zero exit
leaves it open with the attempt logged. Fixtures in Task 6.

## REQ-F — Unattended operation and survival

### REQ-F1.1 — Away by quiet interval [test]

The away state machine: a knock with no reply past `tower_quiet_interval`
yields away for that tower's conversation; any reply yields present; a
second tower's state is unaffected by the first's; the knob's default, a
`<n>m` override, and a sub-second value all parse. Unit tests in Task 5.

### REQ-F1.2 — The away push [test + Gherkin]

Scenario: given a blocking item open and no reply past the quiet interval,
when the transition into away happens, then the notify seam is called once
with a control-free summary and the attempt's outcome is logged as its own
event. Scenario: given the same item open in two towers, then it is pushed
once, deduped under the lock. Scenario: given `none` or `statusline`, then
no call is made and the item stays queued. Unit tests in Task 5.

### REQ-F1.3 — Once, then only on worsening [test + Gherkin]

Scenario: a fixture timeline of blocking items arriving, ageing, and
clearing produces exactly the knocks the rule allows: one at the first
blocking item, one when a second worker blocks, one when an item passes
`tower_reknock_age`, and none at any fixed interval. Scenario: given the
evidence source that would show worsening is unavailable, then the re-knock
is held rather than fired on a stale reading. Unit test in Task 5.

### REQ-F1.4 — Nothing dropped or auto-answered while away [test]

Over a long fixture timeline with no operator reply, every item remains open
or evidence-settled; no item is answered or dropped. Unit test in Task 4.

### REQ-F1.5 — A fresh tower resumes the queue [test + Gherkin]

Scenario: given a queue with open items and a settled history, when a new
tower session starts, then the store is read as authoritative and no
content-home scan runs; `catchup` renders the settled history with reasons
and the open counts, the tower composes the picture from it, `next` then
knocks and waits for a reply, `next` after the reply delivers the first open
item, and nothing acknowledged is redelivered. Scenario: given the store is
absent, then and only then does the content-home scan run. Fixture session
in Task 8.

### REQ-F1.6 — The session-relayed push channel [test + design-level]

With `notification_channel: push`, the notify seam writes exactly one
pending-push marker per item under the fleet home, deduped under the lock,
and pushes nothing itself (Task 5). The relay is the tower session's: Task
8's fixture session calls Claude Code's push-notification tool once per
marker and clears it, with the line one line under 200 characters and free
of spec identifiers, verified at that task's review.

## REQ-G — Measurement and the experiment

### REQ-G1.1 — One line per event [test]

Every verb appends exactly one log line with schema version, sequence, and
kind, and the event kinds cover item born, settled, merged, knocked,
delivered, acknowledged, shelved, pushed, `session` (start and rebuild),
`tick`, and `reply`; the sequence is monotonic across two writers under the
lock; the log path is under the fleet home and no repo file changes at all.
Unit tests in Task 1.

### REQ-G1.2 — The scorecard [test]

Over the committed fixture log the report reproduces hand-computed values
for the headline and each secondary measure, the prose-delivery measure
among them; the headline's denominator counts only the wall-clock spanned by
ticks with at least one live worker, so a fixture with an idle gap excludes
it; a two-tower fixture whose tick streams overlap counts the shared hour
once, from the union of the per-tower intervals; a fixture with a tick gap
longer than `tower_tick_gap_max` excludes that interval and reports one gap
beside the headline. Unit test in Task 1.

### REQ-G1.3 — Log first, baseline before the queue [manual + design-level]

The Task 2 diff touches only logging calls, verified at review; the
baseline entry in the kickoff brief's risk register names its sessions and
numbers, and Task 8's dependency on Task 2 keeps the queue from being wired
in before it exists.

### REQ-G1.4 — Before and after, recorded, gating extension [manual]

The Task 9 risk-register entry names sessions on both sides and every
measure; the Deferred extension entry carries the measured outcome.

### REQ-G1.5 — On demand only [test]

`check-no-ci-evals.sh` passes with the report task present, and an explicit
grep of `.github/workflows` finds no reference to the `tower:report` task.
Existing check plus the added grep, both run by `mise run check` and owned
by Task 1.

### REQ-G1.6 — The log's writers [test]

The prompt-submit hook appends exactly one `reply` line per operator message
in a tower session, through the `log` verb so the sequence stays monotonic,
and nothing outside one; when the lock wait expires the line is dropped and
the dropped-line counter moves. `ack` appends one `acknowledged` line naming
the item, `next` appends one delivery line per hand-over, and each loop pass
appends one `tick`, coalesced when the live-worker count is unchanged. Every
`reply`, `acknowledged`, `delivered`, `knocked`, and `tick` line carries the
writing tower's identity, and a two-tower fixture's lines are separable by
it. Unit tests in Tasks 2 and 3.

### REQ-G1.7 — Line format, sequence, and rotation [test]

A line with a nested JSON value is refused, and a grep of the script finds
no `jq`; the sequence counter file is read and bumped under the lock and
stays monotonic across two writers; a fixture log past
`tower_log_rotate_age` rotates inside the same critical section, with the
floor keeping the experiment's own sessions readable, and `report` reads
only the `tower_report_window` window. Unit tests in Task 1.

### REQ-G1.8 — Redaction lives in the log verb [test]

A secret-shaped value is redacted in every event kind the `log` verb writes,
including a `reply` line from the hook and a line from `capture`, and a grep
finds one redaction helper rather than a copy per caller. Unit tests in
Tasks 1, 2, and 6.

## REQ-H — Invariants and hygiene

### REQ-H1.1 — Reserved controls unchanged [test + design-level + manual]

The queue script contains no `gh pr merge`, `gh pr ready`, force-push,
amend, squash, or rebase invocation (a grep in the script's tests); a
permission-park answered with no named standing decision is refused by the
answer channel, one answered inside a rule names it in the log, and a rule
whose coverage reaches a reserved control is refused at `capture` while the
mechanical refusal still fires at match time (Task 6); the existing
ready-guard and worker deny rules are untouched by every task's diff,
verified by a human at each task's review.

### REQ-H1.2 — Settle only by evidence or written rule [test]

The settling pass's fixture set covers every settle path and each names an
evidence source or a standing decision identifier; a fixture with neither
leaves the item open; the only rule-driven settle is a permission prompt's
(REQ-E1.5), and a non-command rule beside a matching item settles nothing
(REQ-E1.7). Unit tests in Tasks 4 and 6.

### REQ-H1.3 — Hygiene [test]

The hostile-input table in Task 3; the one redaction helper applied to every
event kind, including `next`'s delivery lines and everything `capture`
writes (Tasks 1 and 6); a fixture item whose content addresses instructions
to the tower is rendered as fenced data and acted on by nobody (Task 8); the
repository secret scan under `mise run check`.

### REQ-H1.4 — Deterministic mechanics [design-level + test + manual]

The script is plain portable shell with no model invocation (a grep in its
tests for the CLI's binary name); the fleet daemon gate is not extended by
any task, checked by a human at each task's review. Owned by Task 3, with
the hook's half in Task 2.

## REQ-I — Where the rules live

### REQ-I1.1 — One short doc, cited at point of use [test + design-level]

The doc exists with its index row (`check:doctrine-index`); each tower
skill's manifest names it as point-of-use (`check:instructions`' use-site
check), and any use-site warning it raises is reviewed and either cleared or
carried as a `declared-exception` line with its reason; a grep of the skills
finds at most a one-line gist; the doc's contents are the list Task 7
carries and nothing a Task 3 through 6 verb enforces. Owned by Task 7.

### REQ-I1.2 — As small as the mechanism allows [manual]

At Task 7 review: every sentence in the doc is checked against Tasks 3
through 6's verbs, and any rule a verb enforces is removed from the prose;
the check is recorded in the PR body.

### REQ-I1.3 — Budget raised by measured size, reason recorded [test + manual]

`check:instructions` passes with no floor-breach warning after Tasks 7 and
8; a `raise|` line in `config/instruction-budget-exemptions.txt` names the
knob, the value, and the reason, its value matches the effective knob, and
the doc's word count printed in the Task 7 PR body accounts for it. A human
reads that line's record of why the rungs below a raise did not apply, at
the Task 7 review.

### REQ-I1.4 — Bound to towers now [design-level]

The doc's own scope statement names tower sessions (Task 7); the Deferred
extension entry carries the gate, which Task 9 leaves for the drain pass to
evaluate against its recorded result.
