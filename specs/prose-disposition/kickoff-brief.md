# Prose disposition — Kickoff brief

## 1. Header

- **Spec path:** `specs/prose-disposition`
- **Spec commit at walkthrough start:** `5b3b61a`
- **Walkthrough date:** 2026-09-03
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors, 0 warnings
  (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (defaults; no local override present)
- **Working location:** spec branch `planwright/prose-disposition/spec`,
  worktree `.claude/worktrees/prose-disposition-spec`
- **Doctrine resolution:** all nine docs the skill names resolved from the
  worktree's own `doctrine/` (self-location arm; no `PLANWRIGHT_ROOT` or
  `CLAUDE_PLUGIN_ROOT` set)

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).** The spec
is not about comments costing tokens. It is about what happens after a
reviewer notices prose that could be better: three doctrine rules compose so
that every such notice becomes a finding (the unscoped Documentation lens in
`discovery-rigor`), routes to a human (doctrine wording read as an "external
contract" in `finding-categorization`), and lands as its own commit and
checklist item (one Needs-sign-off finding per commit in `gate-wiring`).
One wording nit, one human decision. The bundle attacks the machinery before
the surface, in a load-bearing order: amend the three rules (lens scoped to
a defect class, prose findings on the meta-spec's expression-only versus
meaning-class axis, a PR-introduced surface carries no external contract
until merge, meaning-class prose batches per loop iteration with a
manifest); skills cite the amended sections and a grep sweep fixes
stragglers; a new rule doc states what a comment is for, bans provenance in
source, and gives the five-reason disposition taxonomy and the block-budget
model; a guard measures the largest contiguous `#` block per file and lands
green behind a generated transitional baseline with an audit and a
code-invariance mode; a two-phase cleanup of planwright's own scripts runs
under the new rules; closeout passes `--closeout`. Altitude: doctrine first,
the guard as a core capability, the cleanup as repo-local work (D-1).

**Rules out:** the pending-sign-off marker's carrier and merge-as-approval
(issue #384), lifecycle hooks (#383), spec and doctrine body prose as a budgeted
surface, JSON `_about` strings and the two adjacent detectors, a fifth
finding bucket, the operator's personal rigor-section copies, adopter
guard-catalog enrollment (Deferred in `tasks.md`).

**Assumes:** the meta-spec's amendment axis applies cleanly to non-spec
prose; an independent reading pass (fresh session or non-Anthropic backend)
is available for Phase B; the `v0.36.0` tag exists so the inventory can be
re-run against it (confirmed present in the worktree).

**Implicit terms surfaced, and their resolutions:**

- **Code line.** Undefined for the audit's code-line count and for
  `--code-invariant`. Resolved: a code line is a non-blank, non-comment
  line, and `--code-invariant` compares the sequence of non-blank
  non-comment lines. Reason: deleting a block usually deletes its trailing
  blank line, and REQ-G1.4 must pass on that. Spec edit carried in section
  3's consolidated list.
- **Rationale language / cites a spec** (the audit's evidence classes).
  The 2026-09-03 figures came from classifier patterns that live only in
  the drafting session; the agent checked issue #391's correction comment
  and obs:a81cee76 and neither records them. Resolved: REQ-F1.5's
  reproduction target narrows to the pattern-independent figures, and the
  Task 4 audit run becomes the recorded baseline the closeout compares
  against. Spec edit carried in section 3's consolidated list. Noted in
  passing: the largest-block figure reads 251 in the bundle and 252 in both
  sources. *(Reconciled at the sign-off lens pass: the largest block left
  the reproduction target and is recorded by the Task 4 audit instead.)*
- **The 28-script list** (REQ-G1.6, Tasks 6 to 8, Task 9). Sources gives
  the count and the method's two halves in prose, but no names and no
  reproducible method. Resolved: the spec states the recomputation method
  (script basename searched across every bundle's `tasks.md` and
  `design.md`; the commit history of the file searched for a task trailer)
  and each Phase B task recomputes for its family; Task 9 recomputes the
  whole. Grounded in the meta-spec's cite-the-source rule. Spec edit
  carried in section 3's consolidated list.
- **Loop iteration**, **pending-sign-off marker**, **own-surface contract**,
  **cross-file protocol**, **normative statement**: defined by their
  governing doc (`gate-wiring`, `spec-format`) or by example in D-8 and
  REQ-B1.1. No ambiguity found.

Signed off: 2026-09-03

## 3. Requirements walkthrough

Walked group by group in the didactic shape (what the rule does today,
what the amendment changes, what a reviewer experiences, then one
question). The walk began in an auditor shape (several gaps per turn, each
posed as a ruling); the operator asked whether it was still didactic, the
root cause was recorded as obs:5f82af96 and committed, and the walk reset.

**REQ-A (Documentation lens).** Intent confirmed: the lens gets a
definition of wrong, and merely improvable prose is not a finding in any
set. Gap found: REQ-A1.2's "no reader would act differently" conjunct had
no class in REQ-A1.1 under the code set. Decision: a fourth class,
prose two readers would act differently on (an interpretation fork), the
code set's counterpart of the spec set's ambiguity lens.

**REQ-B (prose classification).** Intent confirmed: prose fixes ride the
meta-spec's expression-only versus meaning-class axis. Gap found: the
drafted normative-statement definition keyed on the RFC keywords, and a
count over `doctrine/` found 12 keyword lines against 615 plain-imperative
lines, so most rule changes would have classified expression-only. The
operator asked for the implications of each definition and for the
long-term shape; decision: a normative statement is any obligation,
permission, or prohibition however worded, with a word list kept in the
categorization doc as the preservation check's search aid, and a Deferred
entry for a future normative-diff guard that list seeds. Settled by
mechanical consistency: a moved or renamed file is pre-existing under
rename detection; the preservation check is self-attested and goes to the
risk register.

**REQ-C (commit discipline).** Intent confirmed. Two fold-ins: a manifest
before-value reads `absent` for an added passage; a fix that edits code and
its prose together routes as a code fix, one per commit.

**REQ-D (skill instantiation).** Intent confirmed; no decision. Fact for
the sweep: the superseded one-commit-per-finding wording is in three files
today (the gate-wiring doc, the polish skill, the self-review skill), the
unscoped lens wording in one (discovery-rigor).

**REQ-E (comment hygiene doctrine).** Intent confirmed. Decision (from
section 2): REQ-E1.5 states the script-to-spec link test, basename in any
bundle's `tasks.md` or `design.md`, or a `Planwright-Task:` trailer on any
commit touching the file; the unlinked set is recomputed, per family and at
closeout, never carried as a list.

**REQ-F (comment-block budget guard).** Intent confirmed. Decision: the
surface adds the root-level tool configuration (`lefthook.yml`, 34 comment
lines today; `mise.toml`, 9) and the workflow YAML under `.github/`, since
they share the syntax and the workflow-header drift in Sources is the
guard's defect class. From section 2: code line defined as non-blank
non-comment for the audit and the invariance check; the reproduction target
narrowed to the pattern-independent figures with the Task 4 audit as the
baseline of record. Fold-in: a transitional entry is removed by its named
task's PR at the latest, an earlier cleanup PR may remove it, the
stale-entry warning is the signal. Noted: `hooks/` holds only a JSON file
today, so its membership in the surface is currently empty and harmless.

**REQ-G (cleanup and verification).** Intent confirmed; no decision.
Fold-ins: REQ-G1.2 carries Task 5's spot-check sample so requirement and
task agree; REQ-G1.7 compares against the Task 4 baseline of record.

**Consolidated spec edits (applied in place, Draft bundle; changelog entry
dated 2026-09-04 in `requirements.md`):**

1. REQ-A1.1: fourth defect class (interpretation fork). D-2 amended; a
   scenario added to test-spec REQ-A1.1; Task 1 deliverables say four.
2. REQ-B1.1: meaning-based normative-statement definition with the word
   list as search aid. D-3 amended; test-spec REQ-B1.1 names the list.
3. REQ-B1.4: absent from base under rename detection; renamed file is
   pre-existing. Scenario added to test-spec REQ-B1.4.
4. REQ-C1.1: manifest before-value `absent` for an added passage.
5. REQ-C1.3: a code-and-prose fix routes as code. Clause added to
   test-spec REQ-C1.3.
6. REQ-E1.5: the two-part link test and the recompute rule. Test-spec
   REQ-E1.5 and Tasks 6 and 9 reworded to recompute rather than carry a
   list.
7. REQ-F1.1 and REQ-F1.6: code line defined; invariance compares code
   lines. Test-spec REQ-F1.6 admits blank-line moves.
8. REQ-F1.2 and D-10 (heading and decision): root tool config and workflow
   YAML join the surface. Test-spec REQ-F1.2 adds a root fixture; Task 8
   names the files.
9. REQ-F1.3: transitional-entry removal timing.
10. REQ-F1.5, Sources, REQ-G1.7, Task 4, Task 9: reproduction target
    narrowed to the pattern-independent figures; the Task 4 audit is the
    baseline of record; Sources notes the 251 versus 252 boundary
    difference and the unrecorded patterns.
11. REQ-G1.2: spot-check sample named in the Phase A PR.
12. `tasks.md` Deferred: normative-diff prose guard, free-text gate.
13. Test-spec REQ-G1.1: the Phase B edges on Tasks 2 and 4 are through
    Task 5 (an expression fix found while pairing edits, ahead of section
    6).

**Mid-walk delta-scoped lens pass** (inline; the delta is thirteen
bounded edits across the four files, no fan-out). Lenses walked:
correctness, security, error handling, performance, concurrency, naming,
documentation, tests, cross-file consistency. Findings, all applied in the
same change: the D-10 heading still named the directory-only surface;
Task 1's deliverables still said three classes; REQ-B1.4's rename rule and
REQ-C1.3's mixed-fix rule had no paired test-spec scenario (the
requirement/test-spec pairing item). One accepted looseness, recorded and
not changed: the link test counts a basename mentioned anywhere in a
bundle's `design.md` as linked, including in a rejected alternative; it is
the method the Sources count used, and the closure act names the owning
bundle regardless. Validator after the edits: 0 errors, 0 warnings.

Signed off: 2026-09-04

## 4. Design walkthrough

Every D-ID accounted for against the amended requirements.

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 | confirmed | altitude: doctrine first, guard as core capability, cleanup as local work |
| D-2 | amended | four classes; the interpretation-fork class added (annotation in place) |
| D-3 | amended | normative statement defined by meaning; word list as search aid; normative-diff guard deferred (annotation in place) |
| D-4 | confirmed | PR-introduced surface; rename detection settled in REQ-B1.4 |
| D-5 | confirmed | batching with manifest; marker named abstractly against issue #384 |
| D-6 | confirmed | skills cite; straggler sweep; three files carry the old wording today |
| D-7 | confirmed | a new rule doc, no run-start consumer |
| D-8 | confirmed | five-reason taxonomy decides destination |
| D-9 | confirmed | largest-block model, two suppression forms |
| D-10 | amended | root tool config and workflow YAML join the surface (heading and annotation in place) |
| D-11 | confirmed | lands green with the generated transitional baseline |
| D-12 | amended | three-legged verification; the CI-enforced invariance leg (section 5), and at the sign-off lens pass the code-line wording, Phase A's sample scope, and the operator's merge as binding approval |
| D-13 | confirmed | ordering; the task graph now enforces it (below) |
| D-14 | amended | provenance leaves source; gap closed at its source. *(Sign-off lens pass: the fixed 28-script list replaced by REQ-E1.5's recomputed test.)* |

**D-13 and the graph.** The decision says the rule doc and the guard
follow the doctrine and skill tasks; the drafted graph let Tasks 3 and 4
run in parallel with Tasks 1 and 2. The operator asked whether there was
one correct answer, and there is: a live guard reports warn-level blocks
as tool-grounded findings, which the old disposition rules route to
sign-off on every PR touching a script, so the guard cannot be live until
the skills instantiate the amended rules, and the rule doc has no consumer
until the guard cites it. The graph was corrected: Task 3 depends on the
instantiation tasks, Task 4 on Tasks 2 and 3; the `tasks.md` intro and
test-spec REQ-G1.1 say so. D-13 itself is unchanged. Inconsistency halt:
none. *(At sign-off the instantiation was Task 2 alone; the 2026-09-13 and
2026-09-20 amendments moved it to Tasks 10, 11 and 12, and Task 3's
`Dependencies:` line names them. The `Dependencies:` lines stay
authoritative.)*

Signed off: 2026-09-04

## 5. Verification approach

**Coverage mix.** Derived from the tags in `test-spec.md` (cite, do not
copy): `[test]` for the guard's arithmetic, suppression forms, audit and
invariance modes, wiring, and the existing index, link, options,
anchor-freshness, and instruction-budget checks; `[Gherkin]` for the
routing scenarios the amended doctrine must produce; `[manual]` for the
reading-dependent halves of the cleanup verification and the one-time
recorded commands; `[design-level]` where a rule's presence in the named
doc is the verification.

**Ownership.** `[test]` entries run under `mise run check` in the single
CI workflow on every PR; the workflow checks out full history, so the
`v0.36.0` tag is available and the audit-reproduction test is runnable.
`[Gherkin]` scenarios are walked against the amended text at Task 1 review
and exercised on the first review pass after Task 2, inspected by the
operator. `[manual]` entries are swept by the operator at PR review from
the PR body. `[design-level]` entries are verified by reading the named
doc at the owning task's review.

**Dead paths checked.** The audit reproduction against `v0.36.0`: runnable
in CI (full-history checkout). The straggler grep (REQ-D1.2) and the
unlinked-set recompute (REQ-E1.5): one-time commands the worker runs and
records, retagged `[manual]` with the command recorded, since the
test-spec defines `[test]` as run by the aggregate and CI. The
code-invariance check (REQ-G1.4): nothing in the aggregate knew the PR
base, so no CI owner existed. The operator asked for the long-term shape;
resolved from D-12 (a cheap exact leg belongs in a gate) and the repo's
existing plumbing (PR-only base-ref steps, the conventional title lint):
cleanup PRs declare a `comments` title scope, a PR-only CI step added in
Task 4 runs the invariance mode against the base on declared PRs, and the
worker records the result in the PR body for the second reader. Edits:
REQ-G1.4, REQ-F1.7, D-12 (annotation), Task 4 deliverables, Tasks 5 and 6
done-when (Tasks 7 and 8 inherit by reference), test-spec REQ-D1.2,
REQ-E1.5, REQ-F1.7, REQ-G1.4; changelog line extended.

Operator instruction for the remaining verification steps of this kickoff:
any sub-agent the sign-off lens pass fans out runs on Opus.

Signed off: 2026-09-04

## 6. Task graph

**Graph** (reconstructed from the `Dependencies:` lines in `tasks.md`,
which stay authoritative; this rendering is derived):

```text
                       ┌→ 10 auto lane ──┐
1 doctrine → 2 sweep ──┼→ 11 /polish ────┼→ 3 rule doc → 4 guard → 5 Phase A
                       └→ 12 self-review ┘

5 Phase A ─┬→ 6 fleet ──────────┐
           ├→ 7 orch/alloc/spec ├→ 9 closeout
           └→ 8 guards/rest ────┘
```

**Parallelism.** Two-way among the instantiation tasks: Tasks 11 and 12 share
no file and may run together once Task 2 lands, while Task 10 runs alone
against either of them, which is row 12's ordering rule. Three-way among the
Phase B families (Tasks 6, 7, 8), which is where three workers pay off. The
rest serializes.

**Critical path** (effort-weighted from the `Estimated effort:` lines; cite,
do not copy): the front chain plus the longest Phase B family plus closeout,
about eleven working days with three workers on the families. The
instantiation tasks contribute a day and a half rather than Task 12's day
alone, because row 12 keeps Task 10 out of the slot Tasks 11 and 12 share.
With a single worker throughout, those tasks and the families serialize too,
to about sixteen and a half.

**Deliberate non-edges.**

- Tasks 6, 7, and 8 carry no edges among themselves: their script families
  are disjoint. Do not add one.
- Task 3 carries no edge on Task 1 directly: it waits for the skills
  applying the amended rules, not for the rules alone (D-13, section 4), and
  it reaches Task 1 through them. Those skills are Tasks 10, 11 and 12 since
  the 2026-09-13 and 2026-09-20 amendments; Task 2's edge stays because the
  `skills/` straggler sweep is the other half of what the instantiation had
  to land before the guard goes live.
- Task 9 waits for all three families, not for a subset, because closeout
  refuses any transitional entry left.

**Shared write surfaces among the parallel tasks.** The Phase B ones are
carried to the risk register: `config/comment-budget-exemptions.txt` (each
family removes its own lines) and any owning bundle two families both amend
for the deliverables gap (two expression-only re-anchors of one bundle in
flight). The instantiation tasks add a third: Task 10 edits all three skill
files and Tasks 11 and 12 edit two of them, with no edge ordering the three.
The operator decided on 2026-09-21 to coordinate that one the same way, with
a register rule rather than a dependency edge, which is row 12.

Signed off: 2026-09-04

## 7. Risk register

**Decision-domains gap check** (core catalog via the merged resolver
`scripts/resolve-catalog.sh decision-domains`; no overlay entries present).
The design's cross-cutting walk stands with two moves: `concurrency` moves
from not-applicable to touched (shared write surfaces among the parallel
Phase B PRs), decided by row 3 below; `knowledge-engineering` moves from
not-applicable to touched and decided (the five-reason taxonomy is a
vocabulary the surviving comments and verification records are written
in; decided with the operator at drafting, D-8). No other domain moved.
The design's cross-cutting note was updated to match. Cold-review
questions: none on file (the optional cold read was not run).
*(Amended at the 2026-09-21 amendment: the concurrency domain gained a
second instance, the skill files Tasks 10, 11 and 12 share, decided by
row 12 below. The domain was already touched and decided, so it does not
move again.)*

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | The expression-only preservation check (REQ-B1.2) is self-attested; a missed normative statement lets a rule change Auto-apply. | The word list in the categorization doc is the search aid; the audit row carries the check for later audit. Signal: a reader or a later pass finds a missed statement, which is the Deferred normative-diff guard's gate. |
| 2 | Over-classification: agents treat every sentence as normative, and the reclassification buys nothing. | REQ-B1.1 says the list is a search aid, never the definition. Signal: the first batched checklists after Task 2 are dominated by glosses and citations; record an observation if so. |
| 3 | Parallel Phase B PRs (Tasks 6, 7, 8) write `config/comment-budget-exemptions.txt` and may each re-anchor the same owning bundle (decision domain: concurrency). | Each family removes only its own lines. Ordering rule: the second PR to merge re-runs its recompute and its expression-only re-anchor after the first lands, new commits only, never a rebase. Signal: a merge conflict on the exemptions file or a `check:anchor-freshness` failure on an owning bundle. |
| 4 | Tasks 1 and 2 are themselves reviewed under the old disposition rules, so their PRs can show the thirty-item sign-off shape one last time. | Accepted, bounded to two PRs; the operator reviews each checklist in one sitting. Signal: the checklist length on those two PRs. |
| 5 | The Task 4 audit over `v0.36.0` may not reproduce even the pattern-independent figures if its comment-line definition differs from the session's. | REQ-F1.5 narrowed the target; the Task 4 run is the baseline of record regardless, and its PR body explains any gap by the definition. Signal: a mismatch at Task 4 review. |
| 6 | A heredoc body of `#` lines trips the guard falsely (the named limit in D-10). | An `exempt` entry naming the limit. Signal: a false error at guard landing or on a template-bearing script. |
| 7 | `doctrine/gate-wiring.md` sits at its warn threshold; the batching text pushes it over. | REQ-D1.3's diet rung in the same change, never a raise. Signal: a `check:instructions` warning on the Task 1 PR. |
| 8 | Issue #384 (marker carrier) rewrites the same commit-discipline and checklist sections. | D-5 names the carrier abstractly; whichever lands second re-reads the other's text before editing. Signal: a conflict in gate-wiring between the two branches. |
| 9 | The cleanup deletes a genuine why or a caller-relied contract. | The three-legged verification (D-12): invariance proves code untouched, the independent reader confirms recoverability. Signal: reader disagreements in a Phase B PR's record. |
| 10 | Independent reader availability and cost per Phase B PR (fresh session or non-Anthropic backend). | The panel-review backends already configured on this machine serve as the non-Anthropic pass. Signal: a Phase B PR opened without its verification record. |
| 11 | A cleanup PR reverted after closeout leaves the guard red, since closeout admits no transitional entry (raised by the sign-off lens pass under the deploy-migration domain; the domain stays not applicable because nothing is irreversible). | Rollback story: the revert lands together with a re-added `pending-cleanup` entry naming a follow-up task, and closeout is re-run once the re-clean lands. Signal: `check:comment-budget` red on a revert PR. |
| 12 | The instantiation tasks (10, 11, 12) write the same skill files with no edge ordering them: Task 10 edits `skills/polish/SKILL.md`, `skills/self-review/SKILL.md` and `/execute-task`'s convergence prose, Task 11 edits the first and Task 12 the other two, so a selector may dispatch Task 10 beside either and two worktrees write one file at once (decision domain: concurrency). | Each task writes only its own rules' citations, and they do not overlap: Tasks 11 and 12 land lens scoping, prose classification and the batched commit discipline, Task 10 lands the PR-introduced-surface rule. Ordering rule: a dispatcher runs at most one of the three against any one file at a time, so Task 10 never runs beside Task 11 nor beside Task 12; Tasks 11 and 12 share no file and may run together. The second of a pair to be dispatched re-reads the file after the first has merged and adds its citation as new commits, never a rebase. Signal: a merge conflict in a skill file between two instantiation PRs, or a `check:instructions` measurement on one that does not match what its PR body recorded. *(Added at the 2026-09-21 amendment: the operator chose this coordination over a dependency edge on Tasks 11 and 12, the shape row 3 already uses for the Phase B families.)* |

Signed off: 2026-09-04

## 8. Sign-off

### Lens review pass (first activation, full bundle)

Artifact class: **spec** (the lens set from `doctrine/artifact-lenses.md`).
Path taken: fan-out, one read-only sub-agent per lens, each run on Opus per
the operator's instruction in section 5, over all five files with the
shared tooling output (validator clean, doc links resolve, markdown lint
clean on the four spec files). Rendered-content safety was walked inline
by the coordinator (the bundle is committed markdown; data hygiene is the
live question). Validation per `validation-rigor`: each finding was
re-read at its cited lines (pass 1, the non-testable substitute), checked
against the sibling files and the brief (pass 2), and where it named a
repo fact checked against that source (pass 3: the meta-spec's citation
kinds, the instruction guard's exit behaviour, the observation and issue
text, the workflow file, the title lint). The adversarial sweep refuted
one finding and resurrected none.

| Lens (spec set) | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 12 | reproduction scope vs surface; Goal percentage; sweep placement; closeout vs stale entry; words per block; Task 1 scenario list; test list completeness; invariance claim; link-test population; surface definition; guard header threshold; exempt reserve vs heredoc |
| Ambiguity and interpretation forks | 12 | surface qualifier; warn exit; block floor; reproduction scope; merge-base and added files; Phase A block floor; Phase B block set timing; owning-bundle selector; closeout PR scope; "genuinely long"; closeout refusal semantics; sample rule |
| Citation and coverage integrity | 14 | Goal figure attributions; uncited Sources entries; D-1 uncited by a task; words per block; Task 4's edge on 3; REQ-G1.1 scope; coverage-mix intro; kickoff citation form; Sources-only observations; changelog clause; 252 in both sources |
| Dead verification paths | 8 | audit over a tag tree; instruction-budget clauses; header citation runner; workflow-step assertion shape; REQ-A1.3 tag; first-batched-pass owner; Phase A independent pass; closeout PR-body clause |
| Decision-domain gaps | 5 | org-design (binding disposition); deploy-migration (refuted, see below); llm-output-quality acceptance bars; word-list ratification; human-comprehension for the audit and relocated pages |
| Testability | 16 | Task 1 diet and scenario record; Task 2 patterns and gist; Task 4 scope and largest block; Task 5 completeness and sample; Task 6 recompute, bounded, record contents, disagreements; Task 7 wording; Task 8 collapsed paragraphs; Task 9 command and exempt list |
| Cross-file consistency | 9 | D-14 list wording; D-12 non-comment wording; Last reviewed (deferred to the flip); coverage-mix intro; REQ-B1.3 clause names; inception owns artifact-lenses; REQ-C1.1, REQ-G1.7, REQ-F1.3 test-spec pairing |
| Documentation and glossary drift | 15 | baseline; surface; block; manifest; axis extension; link test; pending-cleanup remover; reasons vs taxonomy; independent pass scope; family; loop iteration; prose includes spec bundles; marker name; Goal percentage; largest block in target |
| Rendered-content safety | none | committed markdown rendered only by the forge; no secrets, hostnames, or session paths in the bundle or this brief |

Raw findings: 91 across the eight fan-out lenses; after cross-lens dedup,
20 clusters. The full per-finding reports are in the session's
sub-agent transcripts (run-local, not committed); the clusters and their
edits are listed in the 2026-09-04 changelog entry's sign-off clause in
`requirements.md`.

**Dispositions.** Applied as spec edits: every cluster but one, as the
smallest edit the lens proposed, with five judgment calls resolved from
the bundle's own logic and confirmed by the operator in one bulk decision:
the reproduction run scoped to `scripts/*.sh` at the tag with the largest
block recorded rather than reproduced; the guard's own header under the
warn threshold; the straggler sweep split by surface between Tasks 1 and
2; Phase A's independent pass on a named sample with an observable
completeness test; the author resolves reader disagreements and the
operator's merge is the binding approval. **Declined with rationale:** the
deploy-migration finding (closeout is one-way, so the domain applies).
Reverting a cleanup PR after closeout is two commits, the revert plus a
re-added transitional entry, so nothing is irreversible; the domain stays
not applicable and the rollback story is risk row 11. **Accepted
looseness, recorded:** the link test counts a basename mentioned anywhere
in a bundle's `design.md` as linked, the method the Sources count used
(section 3). **Deferred:** none.

**Kickoff-specific altitude check (REQ-H1.3).** Determined bundle-locally:
`requirements.md`'s Sources carries a "Pinned altitude seed claims" entry,
so the trigger fired at drafting. D-1 exists, is titled as the altitude
call, and is cited from the goal (the goal's closing sentence and its
Cites line). The task decomposition matches the claimed altitude: Tasks 1
to 3 are doctrine and skill work, Task 4 the core capability, Tasks 5 to 9
repo-local cleanup. Pass.

**Post-lens stale-reference sweep** (the lens pass re-scoped several
REQs): a fixed-string grep over the bundle and this brief for the
superseded terms (three classes, the 28-script list, the 2026-09-03
baseline as comparator, the unqualified marker name, non-comment-line
wording, "genuinely long", unqualified "baseline") found three stragglers,
all reconciled: Task 5's and test-spec REQ-F1.7's baseline qualifier, and
this brief's section 2 marker name. Earlier brief sections carry
reconciliation notes where the pass changed a recorded resolution (section
2's largest-block note, section 4's D-12 and D-14 rows).

### Pre-flip verification

- **Lint (REQ-B1.2):** `spec-validate.sh` 0 errors, 0 warnings;
  `markdownlint-cli2` over the five bundle files 0 errors;
  `check-doc-links.sh` all links resolve. Run after every edit of this run.
- **Recorded claims re-derived (REQ-B1.3):** the doctrine keyword count and
  plain-imperative count (section 3), the root config comment-line counts
  and the `hooks/` contents (section 3), the straggler file counts
  (section 3), the effort-weighted critical path (section 6), and the
  gate-wiring word count against its warn knob (section 7) were each
  recomputed by the same fixed-string command family immediately before
  the flip and matched the recorded values. Figures the lens pass changed
  in the bundle (the Goal percentage, the reproduction target) are cited
  to their Sources entry rather than transcribed.

### Record

Approved by the operator on 2026-09-04 after the shared-understanding
summary (what is approved: the restated goal, the requirement and design
ledgers, the task graph, and the eleven-row risk register; what changes:
the first key of the two-key launch, the merge staying the operator's).
Status flipped Draft→Ready and `Last reviewed:` bumped to 2026-09-04 on
all four spec files; the validator re-run at Ready reports 0 errors, 0
warnings. Format-version 2: Ready is the header's resting state, Active
and Done are derived.

Class: meaning
Lens-pass: the lens review pass recorded in this section
Anchor: `b506544c0d609f9cbb88525f8df145ae2f933ab0` — computed as
`scripts/spec-anchor.sh specs/prose-disposition`

## 9. Amendment log

### 2026-09-13 — Task 1 execution: the prose Auto-applicable lane deferred to Task 10

Task 1's amendments to `doctrine/finding-categorization.md` could not all land
under the instruction budget. `/self-review`'s mandatory-at-start closure sits
on the margin its declared exception pins it to, so the doc could not grow by
the full amount; the compensating trim that would have funded it was taken,
measured, and found by the convergence pass to have cut fifteen rules rather
than restatement, all of which were restored. The operator's disposition was
to split rather than fund: REQ-B1.2, REQ-B1.3 and REQ-B1.4 move to a new
Task 10 that funds its own budget within what REQ-D1.3 permits, and Task 1
lands the remaining rules honestly complete. No REQ or D-ID changes meaning:
`design.md` is untouched and `requirements.md` gains only its changelog entry.
Two consequences the changelog records rather than hides: REQ-D1.3's
same-change diet clause is delivered by no task, so `doctrine/gate-wiring.md`
lands over its per-file warn threshold by the operator's decision, superseding
risk row 7's mitigation; and until Task 10 lands, the expression-only class
reaches no bucket of its own, so both classes terminate in Needs sign-off and
the classification is vocabulary rather than routing. Cites the changelog
line: the `## Changelog` entry in `requirements.md` dated 2026-09-13 ("Task 1
execution: the Auto-applicable lane for expression-only prose … moves out of
Task 1 into a new Task 10").

Class: expression-only
Anchor: `6ab09f85968fbcd59ec93037a3695c5ea0c86d3d` — computed as
`scripts/spec-anchor.sh specs/prose-disposition`

### 2026-09-20 — Task 2 execution: the skill instantiation split per surface

Task 2's instantiation of REQ-D1.1 in the three skills did not fit the
instruction budget. Two decisions followed, by two different parties, and
this record keeps them apart. First, the tower chose park-and-report in the
operator's absence: it landed Task 2's REQ-D1.2 sweep with the instantiation
clause undone rather than trimming to make room, following the operator's
recorded 2026-09-13 disposition on the identical Task 1 fork. The operator
had not seen the question, and nothing about that park was operator-approved,
which is why PR #478's body says so in bold and why it is repeated here.
Second, the operator, shown the funding fork afterwards, chose today to split
per surface and land `/polish` first. Two measurements decided the second,
both in PR #478's body and cited rather than recopied. The three-skill gist
runs to 224 words (87 in `/self-review`, 83 in `/polish`, 54 in
`/execute-task`), of which 180 must be freed from the surfaces it lands on;
the restoration ladder's diet rung yields
27 safe ones, because three of the five candidates found were the last copy
of a rule in a doc the affected skill actually loads, and a trim that drops
the last copy buys budget by deleting law. Rung 2 is inapplicable, nothing in
the shortfall being deferrable bulk, and rung 3 is the raise Task 2's
`Done when:` forbids. The surfaces are also asymmetric: `/polish`'s overrun is
a below-target warning the doctrine answers with a recorded declared
exception, while `/self-review`'s and `/execute-task`'s are hard errors that
stop `mise run check`. So `/polish` moves to a new Task 11 that lands alone
behind its declared exception, and `/self-review` and `/execute-task` move to
a new Task 12 whose Deliverables name the funding as part of its work, since
assuming the funding is precisely what Task 2 could not do. Expression-only on
both of the meta-spec's prongs. No REQ's meaning changes: `design.md` is
untouched, `requirements.md` gains only its changelog entry, and REQ-D1.1
keeps its delivery under different tasks. No accepted decision is
contradicted either: D-13 says the cleanup tasks carry explicit dependency
edges on the doctrine tasks and REQ-G1.1 says the same, and Task 3's
`Dependencies:` line now names every task that does the instantiation, so the
ordering is enforced by an edge rather than left to dispatch order. No lens
pass is required.

What the split had to carry with it, recorded rather than hidden. Task 3's
edge on Task 2 stopped covering the skill instantiation REQ-G1.1 names, which
is the shape the 2026-09-13 split had already left behind for Task 10, so
Task 3 now carries `Dependencies: 2, 10, 11, 12` and the edges REQ-G1.1
demands exist again; Tasks 4 and 5 through 8 inherit them through Task 3, and
test-spec REQ-G1.1 was restated to name them. Tasks 11 and 12 instantiate the
three rules Task 2 owned, not four: the PR-introduced-surface rule stays
Task 10's to land in the same files, since its doctrine section does not exist
until Task 10 writes it. REQ-D1.2's same-change binding follows the
instantiation rather than staying behind with Task 2's one-off sweep, so both
new tasks re-run the `skills/` sweep against their own addition. Seven stale
verification pointers were repaired under the contract-reword straggler rule,
the whole class swept rather than the instances first noticed: `test-spec.md`'s
REQ-D1.1, REQ-A1.3 and REQ-C1.1 entries each named a Task 2 review as their
verification occasion, and now name the task that lands the thing they check
(`/polish` at Task 11, `/self-review` and `/execute-task` at Task 12);
REQ-C1.2's and REQ-C1.4's occasions follow REQ-C1.1's by reference and needed
no edit of their own; REQ-D1.1's entry additionally named only those two
tasks for a four-rule reading whose fourth citation lands at Task 10, so it
now names Task 10 for that rule and says the reading completes at whichever
of the two tasks touching a file lands second; REQ-D1.3's test clause named
Tasks 1 and 2 alone for a guard that every instruction-amending task has to
pass, and now names Tasks 10, 11 and 12 too, with Task 11's declared
exception read at its own review; and the two ordering rationales that named
Task 2 as what Task 3 waits for (sections 4 and 6) now name the
instantiation tasks. Section 6's derived renderings follow the
`Dependencies:` and `Estimated effort:` lines rather than staying as drafted:
the graph shows the instantiation tasks between Tasks 2 and 3, the
parallelism note stops saying the front chain has none, and the critical path
is recomputed, the instantiation tasks adding Task 12's day so the
three-worker figure is about ten and a half days rather than nine and a half
and the single-worker figure about sixteen and a half rather than fourteen
and a half. (The 2026-09-21 entry below moves the three-worker figure again,
to about eleven, once row 12's ordering rule is taken into account.) The one
thing the renderings did not decide is the write surface
Tasks 10, 11 and 12 share, which section 6 named and left to the operator;
the 2026-09-21 entry below records what they decided. Cites the
changelog line: the `## Changelog` entry in
`requirements.md` dated 2026-09-20 ("Task 2 execution: REQ-D1.1's
instantiation … moves out of Task 2 into a new Task 11 … and a new Task 12").

Class: expression-only
Anchor: `9890a441277b6971a24511dd2a548e7568adb1d2` — computed as
`scripts/spec-anchor.sh specs/prose-disposition`

### 2026-09-21 — Coordinating the instantiation tasks' shared skill files

The per-surface split left Tasks 10, 11 and 12 writing the same three skill
files with nothing ordering them. Task 10 edits `skills/polish/SKILL.md`,
`skills/self-review/SKILL.md` and `/execute-task`'s convergence prose to land
the PR-introduced-surface rule; Task 11 edits the first and Task 12 the other
two to land the three rules they own. All three depend on Tasks 1 and 2 and on
nothing else, so a selector can dispatch Task 10 beside either and two
worktrees can write one file at once. A Copilot review of PR #479 raised it as
two threads asking for a dependency edge on Task 10.

**The operator decided today, and this entry is theirs, not the tower's.**
They were shown three options: a dependency edge from Tasks 11 and 12 onto
Task 10, a risk-register row with an ordering rule, or leaving the hazard
recorded but uncoordinated. They chose the register row, which is the shape
row 3 already uses for the Phase B families' shared write surface. Keep this
distinct from the park recorded in the 2026-09-20 entry above: that one was
the tower's call in the operator's absence, this one is the operator's own.
Row 12 is the result, and section 6's shared-write-surfaces note now points
at it instead of leaving the question open.

The edge was refused on the merits before the operator saw the options, and
the refusal stands. Copilot's stated premise, that Tasks 11 and 12 rely on
Task 10 having written its doctrine section, does not hold: their three
citations all point at sections Task 1 writes, and they never cite Task 10's,
so each reads correctly in either order. What does hold is the concurrency
hazard, and an edge would answer it by adding an ordering no requirement
states. That is what separates this from the 2026-09-20 entry's edge change on
Task 3, where REQ-G1.1 demanded the edges outright and restoring them was
expression-only.

**Class, re-tested on both prongs rather than inherited.** No REQ's meaning
changes: `requirements.md` gains only its changelog entry, `design.md`,
`tasks.md` and `test-spec.md` are untouched by this entry, and REQ-G1.1 still
requires exactly the edges it required. No accepted decision is contradicted:
the row adds a coordination rule where none existed and overturns nothing. The
close call is the third clause of the axis, which makes additions
meaning-class for new REQs and new D-IDs. A risk-register row is neither, and
this bundle already treats the register as where a concurrency-domain decision
is carried rather than as design: section 7's gap check says the domain is
"decided by row 3 below", and row 3 holds an ordering rule of exactly this
shape with no D-ID behind it. Adding a second instance under a domain already
touched and decided is the gap-fill the expression-only arm names. So:
expression-only. The argument against, recorded so the next walkthrough can
overturn it rather than rediscover it, is that the row states a duty binding
future dispatch that nothing stated before, and the operator weighed
alternatives to reach it, which is the shape of a design decision even though
the register is where this bundle keeps it.

**What the row costs the schedule.** Row 12 is an ordering rule, so section
6's derived figures had to follow it rather than the `Dependencies:` lines
alone, and the first draft of this entry did not. The parallelism note said
the instantiation tasks run three-way, which row 12 forbids: Tasks 11 and 12
share no file and may run together, but Task 10 runs alone against either.
The note now says so, and the critical path follows, the instantiation block
costing a day and a half rather than Task 12's day alone and the three-worker
figure landing at about eleven days rather than ten and a half. Copilot
caught the contradiction on the review of `1e94d6d`; it was the bundle's own
new rule disagreeing with a figure derived before the rule existed.

**The overlap the split left in Task 10, narrowed.** Task 10's Deliverables
still claimed "the instantiation of these three rules" in the three skill
files, wording from 2026-09-13 when Task 10's three doctrine rules were all
it had to place there. The split then wrote the narrow partition into Tasks
11 and 12 ("the fourth rule REQ-D1.1 names, the PR-introduced-surface rule,
is Task 10's"), into test-spec REQ-D1.1, and into the 2026-09-20 changelog
entry, and left Task 10's own clause behind. Two tasks therefore claimed the
same skill edits, which a selector can schedule twice.

The requirements settle which reading is right, and it is the narrow one.
REQ-D1.1 is the only requirement that mandates a skill instantiation at all,
and its four named rules are lens scoping, prose classification, the
PR-introduced-surface rule and the commit discipline. Of Task 10's three
doctrine rules only REQ-B1.4 is among them; REQ-B1.2 governs how an
expression-only prose fix satisfies the Auto-applicable tool-grounding
condition and REQ-B1.3 defines the external-contract clause, and neither asks
for a per-skill restatement of anything. Task 10's own `Done when:` already
said "the governing section", singular, so the block disagreed with itself.
The Deliverables now say one gist per skill rather than three, and the
`Done when:` names which rule.

This has a consequence outside the spec worth stating plainly: the
instruction-budget shortfall Task 10 records was measured against three gists
per skill, so the task now says it is re-measured against one before being
treated as a shortfall. Copilot found this on the review of `5cc5dd9`, inside
a collapsed block, with its own finding counter reading none.

The same task was missing the other half of what REQ-D1.2 binds it to. Task 10
lands doctrine text and edits all three skill files, so both limbs of REQ-D1.2
reach it, the `doctrine/` and `docs/` sweep for the amendment and the
`skills/` sweep for the instantiation. Task 1 carries the first, and the
2026-09-20 split gave Tasks 11 and 12 the second on the reasoning that the
same-change binding follows the instantiation; Task 10 instantiates too and
was passed over. Its `Done when:` now carries the sweep for all three
surfaces and its `Citations:` name REQ-D1.2.

Cites the changelog line: the `## Changelog` entry in `requirements.md` dated
2026-09-21 ("the shared write surface Tasks 10, 11 and 12 have … is
coordinated by a new kickoff-brief risk row 12").

Class: expression-only
Anchor: `d8908e9b5edb30719ace8d87d7a3a1776544efba` — computed as
`scripts/spec-anchor.sh specs/prose-disposition`
