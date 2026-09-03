# Prose disposition — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-03
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the guard's arithmetic,
suppression forms, audit and code-invariance modes, and the repository's
existing index, link, options, and instruction-budget checks, all run by
`mise run check` and the repository CI); `[Gherkin]` for the routing
scenarios the amended doctrine must produce, walked against the text at
Task 1 and exercised on the first review pass after the skills instantiate
them; `[manual]` for the reading-dependent halves of the cleanup
verification; `[design-level]` where a rule's presence in the named doc is
the verification.

## REQ-A — Documentation lens defect class

### REQ-A1.1 — Documentation lens defect classes [design-level + Gherkin]

The Documentation lens entry in `doctrine/discovery-rigor.md` names the three
classes. Scenario: given a diff whose script header claims a guarantee the
changed code no longer delivers, when the lens walks, then a finding of the
falsified class is recorded. Scenario: given a diff whose only documentation
delta is a sentence that could be sharper, when the lens walks, then no
finding is recorded and the coverage row reads `none` with the reason.

### REQ-A1.2 — Improvable prose is not a finding, in any set [design-level + Gherkin]

The cross-set sentence is present in `doctrine/artifact-lenses.md`.
Scenario: given a spec-class review of a doctrine doc where one sentence
reads awkwardly but no two readers would act differently on it, when the
spec lens set walks, then the sentence is not a finding; a sentence that two
readers would act differently on is a finding of the ambiguity lens naming
that fork.

### REQ-A1.3 — Coverage row carries the class [design-level]

The lens-coverage table's Documentation row format in
`doctrine/discovery-rigor.md` shows the class per finding, and the emitting
skills' audit records after Task 2 render it.

## REQ-B — Prose finding classification

### REQ-B1.1 — Classed on the amendment axis [design-level]

`doctrine/finding-categorization.md` states the expression-only versus
meaning-class test for prose findings with the normative-statement
definition, and cites the meta-spec's amendment axis rather than redefining
it.

### REQ-B1.2 — Expression-only prose is Auto-applicable [Gherkin]

Scenario (guard-grounded): given a doctrine doc whose index row omits a
decision the doc cites, when `check-doctrine-index` reports the mismatch,
then the fix is Auto-applicable with the guard rule as grounding and batches
into the iteration's action commit. Scenario (preservation-grounded): given a
heading missing the D-ID its `Done when:` requires, when the agent records
the passage's normative statements before and after as identical, then the
fix is Auto-applicable with the preservation check in its audit row and no
checklist entry is created.

### REQ-B1.3 — External contract defined for prose [design-level + Gherkin]

The clause is defined in `doctrine/finding-categorization.md`. Scenario:
given a gloss added to a term already defined in the glossary, when routed,
then it does not route to Needs sign-off on the external-contract clause
because no rule a reader relies on changed.

### REQ-B1.4 — PR-introduced prose surface [Gherkin]

Scenario: given a PR that adds a new doctrine doc, when the review loop
turns a MAY in that doc into a MUST, then the edit is applied and batched
with the action commit, no checklist entry is created, and the PR diff shows
the new doc whole. Scenario: given the same PR adds a new script, when the
loop changes one of its exit codes, then the existing code routes apply and
a checklist entry is created.

### REQ-B1.5 — Meaning-class prose keeps its route [Gherkin]

Scenario: given a doctrine doc that existed before the PR, when the loop
finds a duty stated where the governing requirement grants a permission,
then the fix is meaning-class and routes to Needs sign-off. Scenario: given
the surface is a signed spec bundle, when the same finding arises, then the
skill refuses the edit and names the kickoff re-walkthrough as the route.

## REQ-C — Commit discipline for prose

### REQ-C1.1 — Batched commit with manifest [Gherkin + manual]

Scenario: given an iteration producing three meaning-class prose findings
on pre-existing docs, when the iteration commits, then one commit carries
all three, its body lists three manifest lines (file, rule before, rule
after), and the marker appears once. Manual: the first review pass after
Task 2 is inspected for this shape.

### REQ-C1.2 — Batched checklist entry [design-level + manual]

`doctrine/gate-wiring.md`'s checklist format shows the batched entry with
sub-items, the revert command, and the hand-edit note. Manual: the first
review pass after Task 2 renders one entry per batch with its sub-items.

### REQ-C1.3 — Behaviour changes stay one per commit [Gherkin]

Scenario: given an iteration producing one meaning-class prose finding and
one Needs-sign-off code fix, when the iteration commits, then the code fix
is its own commit and the prose finding is in the prose batch (a batch of
one, still carrying its manifest line).

### REQ-C1.4 — Audit rows stay per finding [design-level + manual]

The Needs-sign-off table format in `doctrine/gate-wiring.md` shows rows
sharing a commit and checklist id. Manual: the first batched pass's audit
table has one row per finding.

## REQ-D — Skill instantiation

### REQ-D1.1 — Skills cite the amended sections [design-level]

Each of the three skills names the governing section for lens scoping,
prose classification, the PR-introduced-surface rule, and the commit
discipline, restating at most a one-line gist; verified by reading the
three files at Task 2 review.

### REQ-D1.2 — Straggler sweep [test + manual]

The Task 2 PR body lists the surface patterns searched; a repository grep
for the superseded phrasings returns hits only in spec changelogs and
observation fragments, run at Task 2 and repeatable by anyone.

### REQ-D1.3 — Instruction budget holds [test]

`check:instructions` passes after Tasks 1 and 2 with no new `raise` entry
in the suppression list and no floor-breach warning, in `mise run check`.

## REQ-E — Comment hygiene doctrine

### REQ-E1.1 — What a comment is for [design-level]

`doctrine/comment-hygiene.md` states the earn-its-place rule with its four
admitted reasons and its three prohibitions (restatement, narration,
provenance).

### REQ-E1.2 — The five-reason taxonomy [design-level]

The doc states the five reasons and the destination each implies, and the
Phase B verification records (Tasks 6 through 8) classify every surviving
block by one of them.

### REQ-E1.3 — The budget model stated [design-level]

The doc states the unit, the line-based boundary-inclusive thresholds, the
overlay-tunable knobs, and the two suppression forms with the
recorded-reason requirement.

### REQ-E1.4 — Index enrollment and guard citation [test]

`check:doctrine-index` passes with the new row; the guard's header names the
doc; the guard run over its own file reports its largest block under the
error threshold, in `mise run check`.

### REQ-E1.5 — Where the link lives instead [design-level + test]

The doc names the commit trailer and the bundle deliverables as the link,
and the deliverables-gap rule. Test: the Task 9 completeness check
recomputes the neither-trailer-nor-deliverables list and finds it empty.

## REQ-F — Comment-block budget guard

### REQ-F1.1 — Largest-block measurement and thresholds [test]

Fixtures with known block lengths: a block exactly at the warn threshold
warns, one below does not, one exactly at the error threshold errors; the
shebang is not counted; a blank line and a code line each end a run; the
reported starting line matches the fixture.

### REQ-F1.2 — Surface and the heredoc limit [test]

Fixtures under each surface directory are measured and a fixture outside
them is not; a heredoc body line beginning with `#` is counted and the test
asserts that documented behaviour so a future change to it is deliberate.

### REQ-F1.3 — Suppression forms [test]

An `exempt` entry suppresses the named file; a `pending-cleanup` entry
suppresses it and `--closeout` refuses it; a reason-less entry and a
malformed entry each fail loud; an entry whose file no longer trips emits
the named cleanup warning and exit stays zero.

### REQ-F1.4 — Knobs [test]

Knob values resolve through the configuration chain (an overlay fixture
overrides the default); a missing or non-numeric knob aborts fail-loud;
`check:options` passes with the two new rows.

### REQ-F1.5 — Audit reproduces the baseline [test]

`--audit` over the fixture tree emits the per-file rows ranked by largest
block, the corpus totals, and each block's evidence class from the stated
patterns; run against the `v0.36.0` tree it reproduces the headline figures
in Sources.

### REQ-F1.6 — Code invariance [test]

`--code-invariant` against a fixture base passes when only comment lines
changed and fails, naming the file, when one code line changed.

### REQ-F1.7 — Wiring [test]

`check:comment-budget` appears in the `check` aggregate's dependency list
(the same assertion shape the existing wiring tests use) and the `lefthook`
job is scoped to the surface globs; `mise run check` passes with the
baseline in place.

### REQ-F1.8 — Untrusted input [test]

Fixtures with a path-traversal entry in the suppression list, a filename
carrying an escape sequence, and shell metacharacters in a comment line are
refused or sanitized: no path outside the root is read, and the emitted
output contains no non-printable bytes.

### REQ-F1.9 — Test coverage list [design-level]

The test file's sections map one-to-one onto the list in REQ-F1.9, verified
at Task 4 review.

### REQ-F1.10 — Defaults and the generated baseline [test]

The shipped defaults are 12 and 25; the baseline file lists a
`pending-cleanup` entry naming a cleanup task for every file the error
threshold catches at landing, and `mise run check` is green with it.

## REQ-G — Cleanup and verification

### REQ-G1.1 — Ordering [design-level]

Tasks 5 through 8 carry dependency edges on Tasks 2 and 4 in `tasks.md`;
the selector cannot dispatch them earlier.

### REQ-G1.2 — Phase A disposition and figures [test + manual]

Test: `--code-invariant` passes on the Phase A PR and `mise run check` is
green with the reduced baseline. Manual: the PR body carries before and
after audit figures and the remaining evidence-free count; the independent
pass spot-checks the named sample.

### REQ-G1.3 — Phase B disposition [manual]

Each Phase B PR's verification record classifies every surviving block in
its family by taxonomy reason, names each relocation's destination, and
lists each `exempt` entry with its reason.

### REQ-G1.4 — Comments only [test]

`--code-invariant` against the base passes on every cleanup PR;
`lint:shell` and `lint:fmt` pass.

### REQ-G1.5 — Independent verification [manual]

Each Phase B PR body carries the second pass's record (fresh session or
non-Anthropic backend named), confirming recoverability of every removed
line and the reason of every surviving block, with disagreements
dispositioned before merge.

### REQ-G1.6 — Deliverables gap closed [test + manual]

Test: `check:anchor-freshness` passes after each owning bundle's
expression-only amendment. Manual: each amendment carries its changelog
entry and self-re-anchor and names the script in the task's deliverables.

### REQ-G1.7 — Closeout [test]

`mise run check` passes with `--closeout` and zero `pending-cleanup`
entries; the closeout PR body records the final figures beside the baseline.
