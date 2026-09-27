# Review effectiveness — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-24
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` for the harness, the handoff builder, the guards,
the metric scripts, and the instruction-budget checks, all run by
`mise run check` and the repository CI; `[Gherkin]` for the skill-wired
behaviours a fixture unit exercises end to end, recorded in the PR body;
`[design-level]` for each doctrine rule's presence in its named doc;
`[manual]` for the closeout measurement window, which needs PRs merged
after the changes land, and for the start-load figures read at PR review.
The replay harness's mechanics are `[test]` under CI against fixtures; a
backtest replay itself needs model access, so it runs in the executing
task's session, never in CI, and its result and the no-drop gate's verdict
are recorded in that task's PR body.

## REQ-A — Reviewer basics

### REQ-A1.1 — The gate runs first and halts [Gherkin + design-level]

Scenario: given a fixture unit whose branch leaves one `Done when:`
condition uncovered, when `/self-review --nested` runs, then the pass halts
at the gate with that item as a finding and no lens agent is spawned until
it is dispositioned. `doctrine/discovery-rigor.md` names the gate as the
step before the fan-out. Task 3, Task 7.

### REQ-A1.2 — Acceptance coverage [Gherkin]

Scenario: given a unit citing three REQs and two deliverables, when the
gate runs, then each is traced to a hunk or reported as not covered, and a
not-covered item appears in the finding list. Task 7.

### REQ-A1.3 — Description versus diff [Gherkin]

Scenario: given a would-be PR body claiming no dependency line changed
while the diff changes one, and no PR yet open, when the gate runs, then
the claim is a finding citing the body line and the hunk. Task 7.

### REQ-A1.4 — Tests exercise the change [Gherkin]

Scenario: given a change whose test asserts on a status read from a
command other than the one under test, when the gate runs, then the
assertion is a finding; given a before-and-after assertion with no positive
control, then it is a finding; given a behaviour with no
failing-without-it test, then the missing test is a finding. Task 7.

### REQ-A1.5 — Copies of a changed claim [Gherkin]

Scenario: given a default value changed in a script but not in its options
reference row, when the gate runs, then the stale copy is a finding naming
the row; given a changed count whose doctrine index row still states the
old one, then that row is a finding. Task 7.

### REQ-A1.6 — Callers and consumers [Gherkin + test]

Scenario: given a script whose exit-code contract changes while one caller
still reads the old code, when the gate runs, then the caller is a finding.
The handoff builder's test plants a caller and asserts the bundle lists it.
Task 6, Task 7.

### REQ-A1.7 — Scope fence and regression re-check [test + Gherkin]

The scope-fence script's test reports a file outside the deliverables and
stays silent on one inside; the re-verify script's test re-runs a recorded
reproduction against a fresh copy of the current head and fails when the
fix regressed, and re-runs the targeted test for a finding with no
reproduction. Scenario: given a second iteration whose fix regresses an
earlier finding, when the gate runs, then the regression is a finding
before any lens runs; given a file outside the deliverables, then it is a
finding. Task 6, Task 7, Task 9.

## REQ-B — Discovery context and lenses

### REQ-B1.1 — One handoff bundle for every lens [test + Gherkin]

The builder's tests assert the bundle carries the diff, each changed file
whole, the planted callers, the contract slice, the would-be PR title and
body, and the tooling output. Scenario: given a pass with its full lens
set, when it runs, then each lens agent's prompt names the bundle path and
no lens runs a diff command of its own. Task 3, Task 6, Task 9.

### REQ-B1.2 — Claim-versus-code from both sides [Gherkin + design-level]

Scenario: given a header comment saying a script fails closed while the
code ignores a failure, when the Documentation lens runs from the bundle,
then the finding cites the comment line and the code line. The discovery
doctrine states the both-sides rule. Task 3, Task 9.

### REQ-B1.3 — Sibling sweep as lens and post-fix step [Gherkin + design-level]

Scenario: given a diff guarding one of two twin `awk` blocks, when the
sweep lens runs, then the unguarded twin is a finding; given a fix applied
to one site, when the post-fix sweep runs, then the sibling site with the
same defect is a finding in the next iteration. The discovery doctrine
names both moments. Task 3, Task 9.

### REQ-B1.4 — Root-cause clustering [Gherkin + design-level]

Scenario: given the lens set raising twelve findings over three root
causes, when the coordinator merges, then the audit record shows twelve
raw and three clustered and disposition is recorded per cluster. The
discovery doctrine states the clustering step. Task 3, Task 9.

### REQ-B1.5 — Delta-scoped re-discovery [Gherkin + test]

Scenario: given a second iteration after one fix, when the lenses run,
then their attention is the delta since the previous head plus the fixed
file, while the bundle still carries the whole branch. The builder's
delta-mode test asserts an empty delta and a one-file delta. Task 3,
Task 6, Task 9.

### REQ-B1.6 — Lens failure is visible [Gherkin + design-level]

Scenario: given a fixture lens brief that returns nothing, and separately a
lens agent killed mid-run, when the coordinator proceeds, then the lens is
retried once, then run inline, the row records each attempt, and the
inline run is recorded as not context-independent; given the inline run
also fails, then the row reads `failed`, the pass summary is not clean, and
the enclosing convergence ends with the failure reported. The discovery
doctrine states the row value and the retry order. Task 3, Task 8,
Task 9.

### REQ-B1.7 — Artifact-class lens selection [Gherkin + design-level]

Scenario: given a doctrine-only diff, when `/self-review` runs, then the
audit record names the spec lens set and no code-only lens runs. The
artifact-lenses doctrine names the skills' duty. Task 3, Task 9.

### REQ-B1.8 — Independent self-critique [Gherkin + design-level]

Scenario: given a merged finding list, when the self-critique runs, then it
runs in a separate agent whose inputs are the bundle path and the list.
The discovery doctrine states the independence rule. Task 3, Task 9.

## REQ-C — Validation

### REQ-C1.1 — Reproduction first on executable surfaces [Gherkin + design-level]

Scenario: given a finding against a script's fail-open path, when
validation runs, then the first pass invokes the script with the triggering
input in a fresh clone with the home and state home redirected and no push
remote, records exit code and output, and the live worktree's status, the
remote's refs, and the state home are unchanged afterwards; given a
surface with no safe copy, then the first pass is a targeted test and the
evidence line names the condition. The validation doctrine states the
order and the copy rule. Task 4, Task 9.

### REQ-C1.2 — The adversarial pass is declared [design-level]

Each act-on-findings skill carries a declared scoping of the bi-directional
pass in its validation section; the validation doctrine states the
full-pass default. Task 4, Task 9.

### REQ-C1.3 — Declined findings are kept, never handed on [Gherkin]

Scenario: given a finding declined in iteration one, when the blind pass
runs, then the decline ledger is absent from its inputs; given the blind
pass re-raises the finding, then it enters disposition unsuppressed, and
given it carries evidence the decline did not consider, then the decline
reopens. Task 9.

### REQ-C1.4 — Evidence names its process [design-level + Gherkin]

The validation doctrine states the rule. Scenario: given a regression test
recorded without a pre-fix failure, when the audit row is written, then the
result is marked as lacking its process and the finding is not applied.
Task 4, Task 9.

### REQ-C1.5 — Proportional validation for tool-cited findings [design-level + Gherkin]

The validation doctrine states the carve-out and each skill declares it.
Scenario: given a linter-cited unused variable, when validation runs, then
one rule check and the wider check are recorded, not three passes. Task 4,
Task 9.

## REQ-D — Loop economics

### REQ-D1.1 — A fresh bounded context on every backend [Gherkin]

Scenario: given a unit under each backend the capability contract defines,
when a review pass or the blind pass starts, then its agent's first
request carries the bundle path and none of the implementation
transcript, and where the backend hosts no fresh session the agent runs in
the foreground; given no agent can be spawned, then the pass runs inline
and the convergence evidence says it was not context-independent. Task 6,
Task 8, Task 9.

### REQ-D1.2 — Resolved once per loop, bundle per pass [Gherkin + test]

Scenario: given a three-iteration loop, when it runs, then doctrine and the
brief are resolved once and their paths read from the bundle by every
pass, and the bundle is rebuilt in delta mode after each iteration's
fixes. The builder's test asserts the resolved paths are in the bundle.
Task 6, Task 9.

### REQ-D1.3 — Suite cadence [test + Gherkin + design-level]

The diff-scoped check's tests select the tests touching a changed file and
run the linters. Scenario: given an iteration applying two fixes, when it
runs, then two diff-scoped checks and one full suite run are recorded. The
categorization doctrine's predicate reads the new cadence. Task 4, Task 6,
Task 9.

### REQ-D1.4 — Audit record as deltas [Gherkin + design-level]

Scenario: given a three-iteration loop, when it ends, then the audit file
holds one header, three delta sections, and one regenerated table set per
loop, and
the PR body's presentation is unchanged. The gate-wiring doctrine states
the form. Task 4, Task 9.

### REQ-D1.5 — Convergence criterion [design-level + Gherkin]

The gate-wiring doctrine states convergence as a quiet iteration followed
back to back by a clean blind pass. Scenario: given an iteration producing
nothing new, when polish proceeds, then it invokes the blind skill with no
other step between them in the audit record, and no further self-review
fan-out runs; given the blind pass raises a finding that is applied, then
polish iterates until quiet, the next blind pass is directed at the delta
since the previous one, and the audit record counts each blind pass toward
the cap; given the blind pass raises a finding that is declined, then the
loop ends converged. Task 4, Task 9.

### REQ-D1.6 — Resume after kill [Gherkin]

Scenario: given a loop killed after iteration two, when the skill is
re-invoked on the same branch, then it resumes at iteration three with the
two iterations' dispositions intact. Task 9.

## REQ-E — Blind review and external signals

### REQ-E1.1 — Blind review defined [design-level]

`doctrine/review-independence.md` states the two axes, what the reviewer
sees and never sees, and generator independence as a model of a different
family only; the doctrine index lists it. Task 5.

### REQ-E1.2 — The blind pass as polish's confirming pass [Gherkin + test]

Scenario: given polish reaching a quiet iteration, when it proceeds, then
the blind skill runs the reviewer-basics gate without the re-verification
step and the full lens set from the bundle over the whole branch, and its
findings enter disposition with the decline ledger absent from its inputs.
The steps resolver test asserts the catalog entry resolves for standalone
use. Task 8, Task 9.

### REQ-E1.3 — Generator independence when available [Gherkin]

Scenario: given an external backend step attached at convergence, when the
unit converges, then the record names it as the generator-independent
angle by its role, never by step or product name; given none attached,
then the blind pass's tier is read from its own step keys and the record
says context-independent only. Task 8, Task 10.

### REQ-E1.4 — External step output contract [design-level + test + Gherkin]

The independence doctrine states the four rules and versions the finding
fields. The verify script's tests record a fixture external step's empty
result as failed, drop and flag a finding citing a path absent from the
prompt inventory, read findings from a body with no threads, and do not
count a self-resolved thread. Scenario: given an attached external step at
post-pr, when it returns, then its prompt inventory was recorded at
dispatch and the verify script ran on its output. Task 5, Task 10.

### REQ-E1.5 — The miss ledger [test + design-level + Gherkin]

The grammar check refuses a malformed miss text (including one without a
PR number and path) and accepts a conforming one; the refresh script's test
ingests a conforming fragment into the corpus, derives a fixture PR's fixed
finding with no matching fragment as a row with reason `other`, and reports
the fallback count. The independence doctrine states the grammar and the
recording duty; the discovery doctrine's lens briefs cite the ledger's
classes and no row. Scenario: given a post-pr step whose fix lands, when
the step handling finishes, then a conforming `review-miss` fragment is
recorded. Task 1, Task 3, Task 5, Task 10.

### REQ-E1.6 — Convergence evidence in the PR body [Gherkin + design-level]

Scenario: given a unit that ran only the blind pass, when the PR body is
assembled, then the angles record names blind as run and the others as not
run, and claims no other angle; given a post-pr external step then
finishes without moving the head, then the record is re-emitted after the
list completes, naming it by role. The independence doctrine states the
record's fields. Task 5, Task 10.

### REQ-E1.7 — No product names in committed artifacts [test + manual]

The corpus hygiene screen refuses a fixture row naming a product from a
fixture name list; the operator-local screen over the observation
fragments reports no listed name, its run recorded in Task 15's PR body.
Task 1, Task 15.

## REQ-F — Mechanical guards

### REQ-F1.1 — Shell rule set [test]

One true-positive and one true-negative fixture per rule; `mise run check`
runs the set; the guard catalog lists each rule id with its
categorization. Task 11.

### REQ-F1.2 — Emitter output linting [test]

Each of this repository's emitters has a test that lints its output; the
guard catalog names the guard. Task 11.

### REQ-F1.3 — Count-versus-list guard [test]

Fixture prose whose introducing sentence's count matches the list below it
passes, and a mismatched count fails, in doctrine, a skill, docs, a Draft
bundle, and a `specs/_pending/` note; a mismatched count in fixture
bundles at Ready, Active, and Done is skipped; the check is wired under
`mise run check`. Task 12.

### REQ-F1.4 — Test-vacuity guard [test]

A fixture of each listed shape (no positive control, a piped status from
the wrong stage, a masked asserted command, a self-comparison) and a
harness with a zero row floor each fail the check; a conforming test
passes. Task 12.

## REQ-G — Skill diet

### REQ-G1.1 — Run-start set reduced [test]

The instruction-budget audit shows both start-loads below their warn lines
and the reclassified docs point-of-use in the manifests. Task 2.

### REQ-G1.2 — Composed-chain charge [test]

The guard's test charges a fixture chain and reports its closure against
the chain's error-threshold knob. Task 2.

### REQ-G1.3 — Word-neutral landing [manual + test]

Each skill-editing task's PR body names the text it replaces and records
the start-load before and after, read at PR review; the instruction-budget
check keeps every touched skill below its warn line, and a new skill below
its own. Task 2, Task 7, Task 8, Task 9, Task 10.

## REQ-H — Measurement

### REQ-H1.1 — Baselines recorded [test]

The baseline fixture exists with the decided values and the harness's
comparison reads it. Task 1.

### REQ-H1.2 — Corpus, refresh, and harness [test]

The corpus passes its schema test (including the dismissal field on a
declined row) and hygiene screen, which refuses a fixture row naming a
product from a fixture name list; the refresh test, offline against
recorded PR history and a local bare remote, rejects a non-integer PR
number, ingests a fragment, records each row's pre-fix hash, and marks the
row whose commit is missing unreplayable; the harness, against the reviewer
stub, refuses a sample with zero replayable rows after exclusion, overall
and in a targeted class, reports the excluded count, prints the per-class
cap and seed it used, seeds a declined row's dismissal into the
coordinator's ledger, scores a finding 10 lines from a row's line as
caught and 11 lines away as missed, runs its executed commands in the
isolated copy, reports recall per class, and refuses a baseline recorded
on another model or corpus version. Task 1, Task 13.

### REQ-H1.3 — Replay per task [test + manual]

The harness exits non-zero on a fixture replay whose targeted class catches
fewer rows than its baseline, and reuses the baseline's seed and cap;
each task that changes reviewer behaviour records the targeted replay's
recall and the gate's verdict in its PR body, read at PR review; the
landed-pass backtest records the full sample. Task 1, Task 7, Task 8,
Task 9, Task 13.

### REQ-H1.4 — Closeout window [manual + test]

The metric script's tests compute tokens and the finding rate over fixture
transcripts, fleet events, a fixture ledger, and fixture PR history. The
closeout run over a window of at least 15 bot-reviewed PRs merged after
the last of Tasks 1 to 12 is human-exercised; its results file records
both metrics, the bar's verdict, and, on a miss, the observation and the
follow-up. Task 1, Task 14.
