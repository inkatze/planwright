# Tower comms — Test Spec

**Status:** Draft
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
text. Tested over a fixture session in Task 8.

### REQ-A1.2 — Five kinds, each with a closing condition [test]

The `add` verb accepts exactly the five kinds and refuses any other; a
record without a closing condition, or with one naming a future automatic
step, is refused with a message. Unit tests in Task 3.

### REQ-A1.3 — Content in its home, delivery state in the store [test]

For each kind, a fixture `add` writes the content to the named home and the
store record carries a pointer and the delivery fields only; a grep of the
store finds no content text. Unit tests in Task 3.

### REQ-A1.4 — Under the fleet home and lock, surviving the tower [test]

Concurrent-writer test: two writers add and ack under the lock and the
store holds every record untorn; a store written by one process is read
intact by another after the first exits. Unit tests in Task 3.

### REQ-A1.5 — Loss costs one redelivery [test + Gherkin]

Scenario: given a populated queue, when the store file is deleted and the
script runs `next`, then the queue is rebuilt from the content homes, every
item is present, and at most one previously acknowledged item is delivered
again. Unit test in Task 3.

### REQ-A1.6 — Constrained grammar and echo safety [test]

A hostile-input table (traversal tokens, embedded tabs and newlines,
control bytes, over-long fields) is refused at every verb; a hand-corrupted
store line renders with no control byte on stdout. Unit tests in Task 3.

## REQ-B — Settling and merging

### REQ-B1.1 — The settling pass before delivery [test + Gherkin]

Scenario: given a parked question whose PR has since merged, when `next`
runs, then the question is settled with a record naming the merge and is
not delivered. Fixtures in Task 4.

### REQ-B1.2 — Only evidence settles [test + Gherkin]

One fixture per evidence source settles the matching item and nothing
else. Scenario: given a worker whose status reports completed and success
while its branch has no commits and no PR, when the settling pass runs,
then its item stays open. Fixtures in Task 4.

### REQ-B1.3 — Merge duplicates, pair contradictions [test + Gherkin]

Scenario: given two workers asking the same permission, when the settling
pass runs, then one item remains naming both sources. Scenario: given two
items whose answers would contradict, when `next` runs, then they are
delivered as one decision. Fixtures in Task 4.

### REQ-B1.4 — Self-settled items available, never pushed [test + Gherkin]

Scenario: given three items settled by evidence since the last delivery,
when `next` runs, then it hands over the next open item and no settled
item; when `settled` runs, then all three appear with their reasons.
Fixtures in Task 4.

### REQ-B1.5 — Mentioning is not deciding [test]

An item delivered but not acknowledged stays open across turns and across
a restart; only an ack or a matching standing decision closes it. Unit
tests in Tasks 3, 4, and 6.

## REQ-C — Attention and delivery

### REQ-C1.1 — At most one item per call [test]

`next` prints one item or nothing, under every queue size in the fixture
set. Unit test in Task 3.

### REQ-C1.2 — Knock first, content after attention [test + Gherkin]

Scenario: given an open question, when the tower turn runs, then the first
emission is the one-line knock and no item content appears until an
operator reply is logged. Fixture session in Task 8; the knock text
grammar unit-tested in Task 5.

### REQ-C1.3 — Answerable alone, context on request [design-level + manual]

The rule doc states the answerable-alone and one-layer-on-request rules
(Task 7). Manually checked on the experiment sessions: each delivered item
was answerable from its message, recorded in the Task 9 entry.

### REQ-C1.4 — Any reply releases the next item [test + Gherkin]

Scenario: given two open items, when the operator replies to the first with
anything, then the next is delivered; when no reply is logged, then no
second item is delivered. Fixture session in Task 8.

### REQ-C1.5 — Ordered by consequence [test]

A mixed fixture queue orders blocked workers, approvals, requests, then
news, with urgency then age inside each kind. Unit test in Task 3.

### REQ-C1.6 — Shelve with bounded return [test]

A shelved item is absent from `next` until its return time and present
after; no verb drops a shelved item. Unit test in Task 3.

### REQ-C1.7 — News is urgency-gated [test + Gherkin]

Scenario: given a non-urgent news item and no operator engagement, when
time passes, then no knock fires; given an urgent one, then a knock fires
and the content is delivered only after a reply. Fixtures in Task 5.

### REQ-C1.8 — The first turn after silence explains state [design-level + manual]

The rule is stated in the rule doc (Task 7). The catch-up view the tower
reads for that turn is produced by the script (Task 8). Manually checked on
the experiment sessions: the first turn after an autonomous stretch
described state, not the tower's actions; recorded in the Task 9 entry.

## REQ-D — Speech

### REQ-D1.1 — The register [design-level + test]

The rule doc names the assumed reader and the words that need no gloss
(Task 7). The scorecard's jargon count reads the doc's word list (Task 1).

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
no confirmation prompt. Fixture session in Task 8; the capture verb
unit-tested in Task 6.

### REQ-E1.2 — Content in the ledger or its fallback [test]

With ledger helpers present, capture writes a ledger item; without them, an
observation fragment tagged as a capture; the queue record points at
whichever was written. Unit tests in Task 6.

### REQ-E1.3 — Standing decisions recorded [test]

A reply containing an always-form creates a standing record carrying the
rule text, coverage, and date, in the ledger or the tagged fragment. Unit
tests in Task 6.

### REQ-E1.4 — Settling names the rule [test]

Every settle-by-standing-decision record and its log line carry the
decision's identifier. Unit tests in Tasks 4 and 6.

### REQ-E1.5 — Permission prompts strictly inside a rule [test + Gherkin]

Scenario: given a standing decision covering a command shape and a prompt
inside it, when the settling pass runs, then the prompt is answered through
the answer channel and the log names the rule. Scenario: given a prompt one
token outside every rule, then it is queued for the operator and nothing
answers it. Fixtures in Task 6.

### REQ-E1.6 — Questions answered, work captured [design-level + manual]

Stated in the rule doc (Task 7); checked manually on the experiment
sessions and recorded in the Task 9 entry.

## REQ-F — Unattended operation and survival

### REQ-F1.1 — Away by quiet interval [test]

The away state machine: a knock with no reply past the knob's interval
yields away; any reply yields present; the knob's default and a `<n>m`
override both parse. Unit tests in Task 5.

### REQ-F1.2 — Knock through the notification seam when away [test]

With a channel configured, an away knock calls the notify seam once with a
control-free summary; with `none`, no call and the item stays queued. Unit
tests in Task 5.

### REQ-F1.3 — Once, then only on worsening [test + Gherkin]

Scenario: a fixture timeline of blocking items arriving, ageing, and
clearing produces exactly the knocks the rule allows: one at the first
blocking item, one when a second worker blocks, one when an item passes the
re-knock age, and none at any fixed interval. Unit test in Task 5.

### REQ-F1.4 — Nothing dropped or auto-answered while away [test]

Over a long fixture timeline with no operator reply, every item remains open
or evidence-settled; no item is answered or dropped. Unit test in Task 4.

### REQ-F1.5 — A fresh tower resumes the queue [test + Gherkin]

Scenario: given a queue with open items and a settled history, when a new
tower session starts, then `next` delivers the catch-up view and then the
first open item, and nothing is redelivered that was acknowledged. Fixture
session in Task 8.

## REQ-G — Measurement and the experiment

### REQ-G1.1 — One line per event [test]

Every verb appends exactly one log line with schema version, sequence, and
kind; the sequence is monotonic across two writers under the lock; the log
path is under the fleet home and no repo file changes. Unit tests in Task 1.

### REQ-G1.2 — The scorecard [test]

Over a fixture log the report reproduces hand-computed values for the
headline and each secondary measure. Unit test in Task 1.

### REQ-G1.3 — Log first, baseline before the queue [manual + design-level]

The Task 2 diff touches only logging calls, verified at review; the
baseline entry in the kickoff brief's risk register names its sessions and
numbers, and Task 8's dependency on Task 2 keeps the queue from being wired
in before it exists.

### REQ-G1.4 — Before and after, recorded, gating extension [manual]

The Task 9 risk-register entry names sessions on both sides and every
measure; the Deferred extension entry carries the measured outcome.

### REQ-G1.5 — On demand only [test]

`check-no-ci-evals.sh` passes with the report task present; no workflow
under `.github/workflows` invokes it. Existing check, run by `mise run
check`.

## REQ-H — Invariants and hygiene

### REQ-H1.1 — Reserved controls unchanged [test + design-level]

The queue script contains no `gh pr merge`, `gh pr ready`, force-push,
amend, squash, or rebase invocation (a grep in the script's tests); the
existing ready-guard and worker deny rules are untouched by every task's
diff, verified at review.

### REQ-H1.2 — Settle only by evidence or written rule [test]

The settling pass's fixture set covers every settle path and each names an
evidence source or a standing decision identifier; a fixture with neither
leaves the item open. Unit tests in Task 4.

### REQ-H1.3 — Hygiene [test]

The hostile-input table in Task 3 and the secret-shaped-content refusal in
the capture verb (Task 6); the repository secret scan under `mise run
check`.

### REQ-H1.4 — Deterministic mechanics [design-level + test]

The script is plain portable shell with no model invocation (a grep in its
tests for the CLI's binary name); the fleet daemon gate is not extended by
any task.

## REQ-I — Where the rules live

### REQ-I1.1 — One short doc, cited at point of use [test + design-level]

The doc exists with its index row (`check:doctrine-index`); each tower
skill's manifest names it as point-of-use (`check:instructions`' use-site
check); a grep of the skills finds at most a one-line gist.

### REQ-I1.2 — As small as the mechanism allows [manual]

At Task 7 review: every sentence in the doc is checked against Tasks 3
through 6's verbs, and any rule a verb enforces is removed from the prose;
the check is recorded in the PR body.

### REQ-I1.3 — Budget raised by measured size, reason recorded [test]

`check:instructions` passes with no floor-breach warning after Tasks 7 and
8; the raise appears in the config with its reason and matches the doc's
word count printed in the Task 7 PR body.

### REQ-I1.4 — Bound to towers now [design-level]

The doc's own scope statement names tower sessions; the Deferred extension
entry carries the gate.
