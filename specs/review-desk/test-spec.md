# Review desk — Test Spec

**Status:** Draft
**Last reviewed:** 2026-11-05
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` in planwright's own CI (the sharded `test` task and
the lint job's checks) for everything a script owns: the snapshot fields,
the classifier, the queue store, scope rules, the watcher, the export, the
contract validator, format resolution, rendering and checking, the post
script and the after-post handling, all against recorded forge fixtures
with no live forge call; `[test]` through `claude plugin test` for the
panel; `[Gherkin]` for operator-facing state-trigger-outcome behaviours,
run as queue fixtures where a script produces the outcome and under the
behavioral-eval harness where a session's turn does (on demand, never in
CI, per the repository's CI-eval exclusion guard); `[manual]` for one live
shadow run on a real program before promotion, inventoried by the manual
sweep; `[design-level]` where the artifact is the verification.

## REQ-A — The desk duty

### REQ-A1.1 — One duty entry, nothing armed while off [test]

The duty validator accepts the `review-desk` entry with every field; with
the desk disabled, and separately with lifecycle `off`, the watcher list
and the owned-files list for the program contain nothing of the desk's,
and a fixture run writes no file and raises no item.

### REQ-A1.2 — Ships in shadow [test + Gherkin]

The core entry's lifecycle is `shadow`. Given a fixture snapshot with a
new in-scope pull request, when the desk runs in shadow, then would-have
entries record the review and draft, no queue item is raised and the post
script is never invoked.

### REQ-A1.3 — No standing session [test]

The duty's watcher is a script entry; a fixture run from trigger to result
shows one reviewer session launched for the one pull request and its exit
after returning the review; the watcher makes no forge call (asserted by a
stubbed forge CLI that fails on any call from it).

### REQ-A1.4 — One session per pull request, one per patch [test]

Fixtures: a record already reviewing gets no second trigger; a head change
with an unchanged patch id gets none; a changed patch id gets exactly one.

### REQ-A1.5 — Admission and budget, never dropped [test]

With admission refusing, the trigger is deferred and the record stays in
new; with admission granted on the next run, the trigger is emitted once.
The same for an exhausted program budget.

### REQ-A1.6 — Quiet hours [test]

With quiet hours set over the fixture clock, no trigger is emitted and a
standing-exception post is deferred, while a post carrying a fresh
operator yes goes out; after the window the deferred trigger is emitted.
With the knob unset, no window applies.

### REQ-A1.7 — Every preference a documented knob [test]

The mission-control knob check finds every desk knob in the knob
inventory with an options-reference row naming its default; resolution
through each overlay layer changes the value read.

## REQ-B — What gets reviewed

### REQ-B1.1 — Scope as configuration [test]

The evaluator reads its rules only from the resolved scope catalog; a
fixture overlay entry changing the repository list changes which records
enter scope, with no script edit, and an entry narrowed to one repository
changes only that repository.

### REQ-B1.2 — The default scope [test]

Under the default rules: a direct request and a team request enter scope;
the operator's own pull request, a draft, and a pull request outside the
program's repositories do not.

### REQ-B1.3 — Skip what others approved [test]

A pull request whose review decision is approved is skipped with the
reason recorded; with the rule turned off it enters scope.

### REQ-B1.4 — Restacks start nothing [test]

A fixture head change with the patch id unchanged, on a new and on a
submitted record, starts neither a review nor a re-review.

### REQ-B1.5 — Hold on unanswered automated findings [test]

A pull request with an unanswered thread finding, and one with an
unanswered configured body finding, is held; answering the finding
releases it; the classifier output equals the readiness walk's for the
same fixture; with the hold off, it enters review.

### REQ-B1.6 — Leaving scope settles the record [test]

Closing, merging, withdrawing the request and turning draft each settle
the record to done with the reason; a result arriving afterwards is kept
on the record and raises no item.

## REQ-C — The queue

### REQ-C1.1 — One record, one of seven states [test]

The store refuses a state outside the seven and a second record for the
same pull request.

### REQ-C1.2 — Only defined transitions, under the lock [test]

Every transition in the design's table succeeds and logs time, cause and
head; every other pair is refused; two concurrent writers under the lock
leave a consistent record and log.

### REQ-C1.3 — Nothing dropped [test]

No operation removes a record; a done record carries a settling reason,
and a write to done without one is refused.

### REQ-C1.4 — Program home only [test]

The store's resolved path is inside the program home; a fixture program
home pointed into a checkout is refused.

### REQ-C1.5 — State shown in the reviews view [test]

Through `claude plugin test`, the view renders each state for a waiting
pull request and none for one with no record, and a redraw makes no forge
read; the text fallback carries the same states.

## REQ-D — The review itself

### REQ-D1.1 — Forge API only, private export [test]

The export script, run against a stubbed forge CLI and a stubbed git that
fails on any network subcommand, writes the metadata, diff and files into
a fresh private temporary directory outside every checkout and invokes no
git network command.

### REQ-D1.2 — Nothing executed, content is data [test + Gherkin]

Exported files carry no executable bit and no symlink; hostile paths are
refused. Under the behavioral-eval harness: given a fixture diff with a
planted instruction, when the default reviewer reviews it, then the
instruction is reported as content and not followed.

### REQ-D1.3 — Read-only reviewer profile [test]

The reviewer profile the launcher delivers denies a forge write command, a
git fetch and a read outside the export and the install, and allows reads
inside the export.

### REQ-D1.4 — Pluggable step, working default [test]

With no overlay, the step resolves to the shipped default; a fixture
overlay step entry replaces it through the steps catalog.

### REQ-D1.5 — Structured review contract [test]

The contract validator accepts a complete result and refuses one missing
the head, the verdict, a finding's severity, location or evidence, or the
security flag; a refused result returns the record to new or re-review
with the reason.

### REQ-D1.6 — Delta or whole re-review [test]

With the last reviewed head an ancestor of the new one, the export's diff
runs from that head; with a force-pushed history, from the base.

### REQ-D1.7 — Past positions read live, never committed [test + design-level]

The reviewer brief names the forge read of the operator's earlier reviews
in the repository; a fixture run writes nothing from them outside the
program home and the temporary export.

## REQ-E — Review format

### REQ-E1.1 — Rendered through a profile [test]

The renderer produces the draft from the structured review and the
profile; a draft whose text did not come through the renderer is refused
by the delivery step.

### REQ-E1.2 — Profiles through the overlay layers [test]

A profile added in each overlay layer is resolved; a supersede-by-id entry
replaces the shipped one.

### REQ-E1.3 — Most specific profile wins [test]

Fixtures at every specificity resolve to the expected profile, and the
shipped default is used when nothing matches. The reviewer key's form is
fixed when the operator's format details land (D-8).

### REQ-E1.4 — What a profile can set [test]

Once the fields are fixed (D-8), fixture profiles varying structure, tone,
severity labels, length and include/exclude rules each produce the
expected difference in the rendered draft.

### REQ-E1.5 — A working default [test]

With no profile configured, every fixture review renders and passes the
check under the shipped default.

### REQ-E1.6 — The mechanical check [test]

A draft violating each mechanical rule the profile declares is refused
and re-rendered or reported; it never reaches the operator item as
passing.

### REQ-E1.7 — A broken profile keeps the lower layer [test]

A malformed overlay profile is refused with a message naming it, and the
lower layer's profile renders.

## REQ-F — Approval and posting

### REQ-F1.1 — One batch, one line each [Gherkin]

Given three finished reviews, when the batch is delivered, then the
operator sees one item with three lines (title, link, verdict, finding
count) and each draft's full text on request.

### REQ-F1.2 — Security heads-up [Gherkin]

Given a review with the security flag, when it finishes, then a
notification fires at once naming the pull request, and nothing posts.

### REQ-F1.3 — Exact-text yes; batch yes covers only texts shown [Gherkin]

Given a batch where two of three drafts were shown in full, when the
operator answers yes to the batch, then the two shown post and the third
stays awaiting-operator.

### REQ-F1.4 — The yes binds the digest [test]

An edited draft under the earlier yes is refused by the post script; a new
yes on the edited text posts it.

### REQ-F1.5 — The pre-post re-check [Gherkin]

Given an approved draft, when the head moved, then the yes lapses and the
record goes to re-review; when a new review appeared, then the draft
returns to the operator with what changed; when the pull request closed,
then the record settles and nothing posts.

### REQ-F1.6 — Exact text, one script, undo entry [test]

Against a stubbed forge, the post sends the approved text and verdict
byte for byte, the read-back digest matches, and the undo ledger gains an
entry naming the act and its reversal.

### REQ-F1.7 — Declined or edited drafts never post as before [test]

A declined draft settles with the reason and the post script refuses it;
an edited draft's earlier digest is refused.

## REQ-G — After the post

### REQ-G1.1 — New commit, re-review [test]

A changed patch on a submitted record moves it to re-review and emits one
trigger.

### REQ-G1.2 — Dismissed approval [Gherkin]

Given a dismissed approval and a re-review that keeps the verdict, when
the standing exception is off, then the operator gets a one-line item;
when it is on, then an empty approval posts with an undo entry.

### REQ-G1.3 — Changed verdict, new draft [test]

A re-review with a different verdict raises a draft item like a first
review.

### REQ-G1.4 — Promises become follow-ups [test + Gherkin]

A draft carrying a fixture promise lists it on the yes item; after the
post, a follow-up ledger row exists with owner and trigger, and a declined
draft writes none; given the trigger fires, then the promised act starts.

### REQ-G1.5 — Author replies [Gherkin]

Given an author reply on the operator's review thread, when the snapshot
shows it, then the operator gets an item with a drafted answer, and
nothing posts without a yes.

### REQ-G1.6 — Done [test]

Merge, close, leaving scope and an operator settle each move the record to
done with the reason.

## REQ-H — Automated findings in review bodies

### REQ-H1.1 — One shared classifier [test]

The readiness walk and the desk's hold produce identical classifications
for the same fixture threads and bodies, through the one classifier.

### REQ-H1.2 — Body-finding configuration [test]

A reviewer configured with a body pattern and an answered marker yields
body findings, and a reply with the marker answers one.

### REQ-H1.3 — Body findings block readiness until answered [test]

A configured unanswered body finding at the head makes the walk refuse
ready; answering it clears the refusal.

### REQ-H1.4 — The unread body is named [test]

An automated reviewer's body at the head with no body configuration
produces a plain-words line in the verdict saying the body was not read
for findings, and does not by itself refuse ready.

## REQ-I — Waiting on people before merge

### REQ-I1.1 — The waiting reason, person and age [test]

Fixture snapshots for a required approval not given, changes requested, a
code-owner review outstanding and nothing pending each derive that reason,
the person or team it waits on and the wait's start.

### REQ-I1.2 — Never presented as ready to merge [Gherkin]

Given a ready, green pull request with a required approval pending, when
mission control presents a merge recommendation, a packet or status at
each guidance level, then it says what the pull request waits on and from
whom and never calls it ready to merge; at guided it also says why.

### REQ-I1.3 — Shown in the reviews view [test]

Through `claude plugin test`, the view shows the reason, the person and
the wait for each fixture, and nothing for a pull request waiting on no
one.

### REQ-I1.4 — Waiting only on the operator [test]

A reviewed pull request whose only pending human gate is the operator's
review carries that statement in its batch line.

### REQ-I1.5 — Moving a waiting pull request needs a yes [Gherkin]

Given the operator's pull request waiting on another person and a policy
that offers a reminder, when the offer fires, then a drafted reminder
reaches the operator and goes out only on a yes to its exact text and
recipient. The policy's fields are fixed when the operator answers (D-16).
