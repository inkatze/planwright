# Prose disposition — open ambiguity findings

**Status:** Open — input for a `/spec-kickoff` delta re-walkthrough
**Raised:** 2026-09-13, by the convergence pass on Task 1
**Owner:** the operator; nothing here is actionable from execution

These came out of a four-lens review fan-out over the Task 1 branch. Each one
is a question about what an amended rule *means*, not a defect in how it was
written down, so acting on any of them would change what REQ-A, REQ-B or
REQ-C requires. That is meaning-class contract drift, which execution does not
get to decide — hence this file rather than a fix.

The bundle has no existing convention for parking meaning-class questions
(`## Deferred` in `tasks.md` is for gated work items with a resolution
condition, and the observations accumulator takes one fragment per
out-of-scope notice). This file was chosen over stretching either.

**Genuine fork** means two careful readers would act differently and both
readings survive scrutiny. **Underspecified** means the text leaves something
open but practice would converge; these are cheaper to leave alone.

Where a finding attaches to text that moved to Task 10, it is marked
**[Task 10]** — those need answering before that task lands, not before this
one merges.

---

## A. Genuine forks — on text this PR lands

### A1. "it changes meaning when it is added, removed, or altered" swallows the expression-only lane

`doctrine/finding-categorization.md`, Prose findings:

> A **normative statement** is any obligation, permission, or prohibition
> however worded, plus any threshold, enumerated value, or interface fact; it
> changes meaning when it is added, removed, or altered.

Read literally, *altering* a sentence that carries a normative statement is a
meaning change — so every reword of a rule is meaning-class and no rule-bearing
passage can ever be expression-only. Reader A applies that and routes all
doctrine rewording to sign-off. Reader B reads "altered" as "its content
altered", so a pure reword stays expression-only, which is what the
normative-preservation check presupposes.

The branches: (a) keep the literal reading and accept that only non-rule prose
is ever expression-only; (b) say "added, removed, or its content changed; a
restatement that preserves the obligation, permission, prohibition, threshold,
value or fact is not a change". This is the single most consequential fork in
the added text — it decides the bucket for the most common prose fix in the
repo.

### A2. "interface fact" is undefined and appears nowhere else in the doctrine

`doctrine/finding-categorization.md`, same sentence. Reader A takes it as a
function signature, a flag name, a file path. Reader B takes it as anything a
reader could rely on, including default values and output formats — which then
overlaps "threshold, enumerated value" and widens meaning-class considerably.

The branches: define it, replace it with the concrete list, or drop it as
subsumed by the two terms beside it.

### A3. The classification has no tiebreak, and the axis it borrows has one

The word list is explicitly "never as the definition: a rule stated in none of
those words is still a normative statement", so the classifier will regularly
be uncertain. `doctrine/spec-format.md` resolves exactly this for its own axis:
"any delta the classification cannot resolve … defaults to meaning-class". The
new section borrows the axis without the default.

Reader A imports the default (same axis, same problem). Reader B reads the
doc's own "a predicate condition that is uncertain routes the finding downward"
as applying only to the four *bucket* predicates, which are downstream of the
classification, so an uncertain classification has no rule and lands
expression-only — the opposite disposition.

The branches: state "an unresolvable classification defaults to meaning-class",
or state that the downward-routing rule reaches the classification too.

### A4. "A finding whose fix edits only prose" is undecided for a mixed fix

`doctrine/finding-categorization.md`, Prose findings, opening sentence.

Reader A: the finding is the unit; if its fix edits a script's logic *and* the
comment above it, it is not a prose finding and the section is inapplicable.
Reader B: splits it into a code finding and a prose finding, so the comment half
batches into the prose sign-off commit while the code half commits alone.

Both readings are consistent with the sentence, and they produce different
commit graphs, different checklist entries and different audit-row counts.
`doctrine/gate-wiring.md`'s "a fix that edits code and its prose together is
that code fix's commit" presupposes reader A, but nothing says so and nothing
forbids the split.

The branches: (a) "a finding is a prose finding only if the whole fix edits no
line of code; a mixed fix is never split for routing"; (b) allow the split and
say how the two halves' audit rows relate.

### A5. "configuration commentary" sweeps in behaviourally live directives

`doctrine/finding-categorization.md`, the surfaces list. This repo carries
`# shellcheck disable=…` in 33 script files, plus lint directives in YAML.

Reader A: a comment is prose, so moving or reflowing a `shellcheck disable` is
expression-only and therefore auto-applied. Reader B: a directive the toolchain
parses is configuration the runtime reads, which `doctrine/artifact-lenses.md`
puts in the **code** class. Reader A's application silently changes lint
coverage.

The branches: exclude comments any tool parses as a directive, or say they are
in and accept the exposure.

### A6. "skill instructions" are prose here and executable elsewhere

`doctrine/finding-categorization.md`, the surfaces list. `skills/*/SKILL.md` is
the agent's program.

Reader A: a rewrite of a skill step carrying no MUST/SHALL/only is
expression-only, so auto-applied with no sign-off. Reader B: the file is
executed, so an edit to it is a behaviour change and the Auto-applicable
condition "no user-observable behavior change" fails.

This branch is its own test case: `skills/self-review/SKILL.md` lost an
explicit "one commit per Needs-sign-off finding" instruction and gained
"committed per that same discipline". Reader A would have classed that
expression-only and applied it unreviewed.

The branches: say whether a normative skill step counts as behaviour for that
condition.

### A7. "merely improvable prose is not a finding, in any set" collides with the human-facing and inception sets

`doctrine/artifact-lenses.md`, the cross-set rule, against that same doc's own
lens sets.

The human-facing set's lenses are *by construction* phrasing and emphasis
judgments: above-the-fold summary, reader-not-writer formatting, comprehension.
A report that buries its answer has no code falsifying it, no sibling it
contradicts, and no reader who would *act* differently — they would just read
longer.

Reader A: those three lenses are now unreportable and must show `none` every
run. Reader B stretches "act differently" to "has to work harder", and the
lenses survive — at which point the rule suppresses nothing. The inception
set's falsifiability lens (is each assumption in the believe/verify/measure
skeleton) has the same shape, being a form requirement.

The branches: scope the rule to the code and spec sets, carve out the named
lenses, or accept the suppression.

### A8. The improvable-prose test is three negatives the finder cannot establish

`doctrine/artifact-lenses.md`:

> A phrasing, an emphasis, or a precision preference — one with no code that
> falsifies it, no sibling statement it contradicts, and no reader who would act
> differently on it — is a preference, not a defect

Reader A puts the burden on the finder: a documentation finding must exhibit the
falsifying code, the contradicted sibling, or the two readings, else it is
suppressed. Reader B reads it as a disqualifier that fires only when all three
negatives are *shown*, and "no reader who would act differently" is
unfalsifiable, so nothing is ever suppressed and the rule is inert.

The branches: restate positively — "a documentation finding must name one of:
the code that falsifies the prose, the sibling statement it contradicts, or two
concrete readings and the different action each produces; a finding that names
none is not reported" — or keep the negative form and accept reader B.

### A9. "no sibling statement it contradicts": sibling scope undefined

`doctrine/artifact-lenses.md`, same sentence. Reader A: another statement in the
same document. Reader B: anywhere in `doctrine/`, `skills/` and `specs/`, since
this repo is built on cross-doc normative statements and the cross-file lens
exists for exactly that. Opposite verdicts for a README paragraph contradicting
a doctrine rule three files away.

The branches: "in the artifact under review", "in any artifact under review or
any doc it cites", or repo-wide.

### A10. Documentation-lens defect classes 3 and 4 carry no change-scope qualifier

`doctrine/discovery-rigor.md`, lens 7. Classes 1 and 2 say "the change
falsifies", "the change introduces". Classes 3 and 4 — a guard-reported
violation, and prose two readers would act differently on — do not.

Reader A: all four inherit the diff scope. Reader B: a guard violation or an
interpretation fork anywhere in the repo's docs is a Documentation finding on
every review, which is an unbounded lens on a one-line diff. Lens 6 in the same
list resolves exactly this ("only flag when the change under review worsens
it"); lens 7 does not.

The branches: add the diff-scope qualifier to classes 3 and 4, or state that
they are deliberately repo-wide.

### A11. "nothing else" is a closure claim with no escape hatch

`doctrine/discovery-rigor.md`, lens 7: "flagged for four defect classes and
nothing else". A README documenting a flag that never existed fits none of the
four — the change did not falsify it, the change introduced nothing, no guard
reports it, and no two readers *act* differently, they both just fail. It is
also not reportable as "merely improvable".

Reader A drops it. Reader B stretches "leaves stale" to cover pre-existing
falsity. The branches: add a fifth class ("prose that is false independent of
the change"), or say the closure is deliberate and such defects are out of
review scope.

### A12. The Documentation Notes-cell rule names classes that have no names

`doctrine/discovery-rigor.md`: "The **Documentation** row's Notes cell names the
defect class behind each finding it counts." The four classes are described,
never labelled.

Reader A writes `2 stale, 1 fork`; reader B writes `class 1 ×2, class 4 ×1`;
reader C writes a prose summary and considers the class implied. Nothing lets a
reviewer decide which complies. Compounding it, the canonical table declares
Notes to be a `<one-line summary or reason for none>`, so a row counting six
findings must carry six class labels in a cell the same doc bounds to one line.

The branches: give the four classes short canonical labels and state the
Notes-cell form (`stale:2 missing:1 guard:0 fork:3`), or drop the per-finding
requirement to a per-row one.

### A13. "reads as a scoping violation" states an appearance, not an obligation

`doctrine/discovery-rigor.md`, the sentence after A12's.

Reader A treats a Documentation row whose findings are all preferences as a
conformance failure: drop them and re-record the row as `none`. Reader B treats
the clause as rationale for the naming requirement and takes no action. The rule
cannot be checked for compliance because it never says what compliance is.

The branches: state the consequence ("a Documentation finding whose Notes cell
names no class is dropped before the record is written"), or mark the sentence
as rationale.

### A14. The Notes-cell rule assumes the code set's table

`doctrine/discovery-rigor.md`. The row is called "Documentation", which exists
only in the code lens set; the spec set has "documentation and glossary drift"
and the inception and human-facing sets have no documentation row at all.

Reader A applies the rule to whatever row is nearest in the selected set; reader
B applies it only under the code set, so a spec-class review carries no class
naming — contradicting `artifact-lenses.md`'s "every documentation finding names
the defect class it belongs to".

The branches: key the rule to the finding rather than the row name.

### A15. The spec-set class list is three names for a nine-lens set

`doctrine/artifact-lenses.md`: "(… ambiguity, citation integrity, or glossary
drift in the spec set)". The spec set also contains contract correctness, dead
verification paths, decision-domain gaps, testability, cross-file consistency
and rendered-content safety.

Reader A treats the three as closed, so a dead-verification-path finding has no
nameable class and is suppressed as merely improvable. Reader B treats them as
examples. The branches: say "the lens it was found under" instead of a partial
enumeration. The inception and human-facing sets get no class vocabulary at all,
which has the same shape.

### A16. Two sign-off commit shapes that do not cover the middle case

`doctrine/gate-wiring.md`, Commit discipline. Bullet 1 covers a Needs-sign-off
fix that changes code behaviour; bullet 2 covers fixes that edit only prose. A
Needs-sign-off fix that edits code *without* changing behaviour — the
"multi-step or non-mechanical but the path is unambiguous" route, say an
internal restructure across three files — is in neither, while bullet 3's "Both
sign-off shapes" asserts the taxonomy is closed.

Reader A gives it its own commit by analogy to bullet 1. Reader B batches it,
since the per-finding guarantee is stated to earn its cost "for behaviour …
and not for wording".

The branches: make bullet 1 "edits any code" and bullet 2 the exception, or add
the third shape explicitly.

### A17. "never a batch member" is either bullet-scoped or global

`doctrine/gate-wiring.md`: "A fix that edits code and its prose together is that
code fix's commit, never a batch member."

Reader A scopes it to its bullet (Needs sign-off). Reader B reads "never a batch
member" absolutely, so an Auto-applicable fix touching a line and its comment
may not go in the iteration's action commit either — contradicting "Auto-
applicable and Agent-resolvable items may batch" four bullets down. "That code
fix's commit" also presupposes the code fix has a dedicated commit, which is
false when it is Auto-applicable.

The branches: "…is committed with its code fix, wherever that fix commits".

### A18. "changes code behaviour" is a third term for a concept stated twice elsewhere

`doctrine/gate-wiring.md` says "changes code behaviour", unqualified.
`doctrine/finding-categorization.md` says "user-observable behavior change",
twice. Reader A: any behaviour change, internal included. Reader B: only
user-observable, matching the doctrine that governs — except the governing
clause reaches "a bucket, predicate, or zone", and "behaviour" is none of the
three, so it does not reach.

The branches: use the categorization doctrine's exact phrase.

### A19. "one line per fix" breaks when a fix changes two rules or touches two files

`doctrine/gate-wiring.md`, the prose batch's manifest: one file slot, one rule
slot.

Reader A: one line per fix, picking the most salient file and rule — a reviewer
reverting cannot see the second file. Reader B: one line per changed rule, so
the line count exceeds the finding count, and the checklist's "one sub-item per
manifest line" and the audit table's "one row per finding" then produce
different counts for the same batch, which the reviewer cannot reconcile.

The branches: state the manifest's unit explicitly and say how it maps to audit
rows.

### A20. The batched checklist entry cannot be regenerated from the branch

`doctrine/gate-wiring.md`. The section opens "Generated, not hand-edited; …
rebuilds from the branch … never from a side state file". The batched entry's
sub-items rebuild from the commit-body manifest, but its **Route reason** line
appears nowhere in the manifest, which specifies file / before / after only.

Reader A: the route reason must be added to the manifest or the entry cannot be
regenerated in a fresh session. Reader B: regeneration re-derives it by
re-classifying the diff — a different answer each run, so the checklist stops
being "a pure function of the branch".

The branches: add the route reason to the manifest line, or state that
regeneration re-derives it and how.

### A21. The batched checklist template hardcodes a classification the rule does not require

`doctrine/gate-wiring.md`, the batched entry: "2 meaning-class prose fixes" /
"Route reason: meaning-class prose on surfaces that predate the PR". The
commit-discipline bullet admits *any* Needs-sign-off fix that edits only prose,
and expression-only prose reaches Needs sign-off by at least two routes
(uncertain validation convergence; the multi-step non-mechanical route).

Reader A follows the canonical template literally and labels an expression-only
fix "meaning-class", corrupting the audit record. Reader B writes a bespoke
entry, departing from a format the doc calls canonical and generated.
Relatedly, the Needs-sign-off table carries a Route reason per *row* while the
entry carries one for the whole batch, so a mixed-route batch can only be wrong.

The branches: make the descriptor and route reason derived fields and say what
happens on a mixed-route batch, or forbid mixed-route batches.

### A22. "closing when the next review pass opens" never closes in a single-pass run

`doctrine/gate-wiring.md`, the definition of a loop iteration. `/self-review`
standalone is one pass by design.

Reader A: the iteration closes at loop exit and the commits are made there.
Reader B: the closing condition never occurs, so the rule gives no commit point.
Reader C counts Discovery Rigor's mandatory self-critique pass as "the next
review pass", closing the iteration mid-cycle and producing two batch commits
where reader A produces one.

A related deadlock is reachable from the literal reading: if the batch stays
uncommitted until the next pass begins, the branch is dirty at the moment
`/self-review` pre-flight demands a clean working tree, and the next pass halts.

The branches: define the boundary by an event the committing skill observes —
"an iteration closes when its dispositioning finishes; the self-critique and
validation passes are inside it" — and say what a single-pass run does.

### A23. The prose-batching bullet narrows a guarantee without the declared-scoping label its sibling carries

`doctrine/gate-wiring.md`. The Auto/Agent bullet labels itself "Declared scoping
(per Proportionality)". The prose bullet gives a rationale but no label, and
`doctrine/proportionality.md` requires the declaration to sit "in the skill".

Reader A: doctrine-level rationale is enough. Reader B: every skill implementing
this wiring must declare the prose-batch scoping in its own body, and none of
the three do.

The branches: label it the same way, and say whether a skill-side declaration is
additionally owed.

---

## B. Genuine forks — on text deferred to Task 10

These attach to REQ-B1.2, REQ-B1.3 and REQ-B1.4, which moved out of Task 1.
They should be settled before Task 10 lands.

### B1. [Task 10] "only tool-grounding is in question" discharges two conditions it does not address

Deferred text: "Its fix is mechanical and no rule changed, so only
tool-grounding is in question."

Auto-applicable condition 2 defines mechanical by enumeration — "a rename,
reformat, drop-unused, missing import, missing newline, typo, inferable type
annotation, or similar **single-step transform**". A three-paragraph clarity
rewrite that preserves every normative statement is expression-only but is not a
single-step transform. Reader A accepts the assertion and auto-applies it;
reader B holds condition 2 against it and routes to Needs sign-off. Condition 4
(all three validation passes converged) is likewise not implied and not
mentioned: reader A skips the convergence check for prose, reader B does not.

The branches: enumerate which of the four conditions the classification
discharges and which must still be checked independently.

### B2. [Task 10] A self-performed check offered as satisfying a condition named "Tool-grounded"

Condition 1's whole content is "a named rule from a tool the project ships does
[qualify]; 'this looks like a bug' does not". The normative-preservation check is
the agent's own reading, recorded.

Reader A: the new text creates a second, non-tool grounding, and condition 1's
name is now a misnomer. Reader B: a self-check cannot satisfy a tool-grounding
condition, so the recorded check only supports a Needs-sign-off route. Two
buckets for every prose fix with no guard hit, which is most of them.

The branches: rename the condition ("Grounded") and state the two admissible
groundings there, rather than asserting equivalence from a distant section.

### B3. [Task 10] "listed before and after and shown identical" is not evaluable

Three separate gaps. *Passage*: reader A lists the statements in the edited
lines, reader B for the whole section, because a reword can shift a neighbouring
statement's scope. *Identical*: if the lists are verbatim text, a reword is never
identical and the check can never pass; if they are paraphrases, "identical" is
the very judgment the check was meant to replace. *Recorded where*: the before
and after lists have no named artifact, so a reviewer at PR time cannot verify
the check happened — and the Auto-applicable audit column is "Tool + rule
cited", which has no slot for a non-tool grounding.

The branches: define the passage as the diff hunk plus its enclosing section;
define identity as "same obligation and same subject, restatement permitted";
name where the lists land; widen the audit column.

### B4. [Task 10] Unpinned rename detection

Deferred text: "a documentation, doctrine, or skill file absent from the PR's
base under rename detection". No command, no similarity threshold, no statement
of whether copy detection counts. Git's rename detection is threshold-based
(`-M50%` by default) and off for copies unless `-C` is passed.

Concretely: a new `doctrine/comment-hygiene.md` seeded by copying
`doctrine/instruction-hygiene.md` and rewriting 55% of it. Reader A runs
`git diff --find-renames origin/main...HEAD`, sees an added file, and treats it
as PR-introduced — internal, batched, no checklist entry. Reader B runs it with
`-M30%` or `--find-copies-harder`, sees a rename, and treats it as pre-existing
— meaning-class, Needs sign-off, checklist entry. Same branch, opposite PR
bodies. The term appears exactly once in the repo and nothing else defines it.

The branches: pin the command and threshold ("absent from
`git diff --name-status -M50% <base>...HEAD` as anything other than `A`") and
say whether a copy counts as a rename.

### B5. [Task 10] "the PR's base" is unavailable in the runs the rule fires in

`/polish` is local-only and never creates a PR; `/self-review --nested`
likewise. Reader A substitutes the remote-tracking base the skills' pre-flight
records. Reader B finds no PR, cannot evaluate the rule, and defaults every file
to pre-existing, so the PR-introduced-surface rule never fires in nested runs —
which is most runs. `gate-wiring.md` elsewhere uses `base..head`; the new rule
uses a different noun.

The branches: use the same base the checklist regeneration uses, and define it
for the pre-PR case.

### B6. [Task 10] "whole" excludes the case with identical rationale

Deferred text: "a documentation, doctrine, or skill file absent from the PR's
base …, whole". Reader A: only entire new files qualify, so a new section added
by the same PR to a pre-existing doc is pre-existing surface and review-loop
edits to it need a checklist entry. Reader B applies the rationale — nobody
outside relies on text the PR itself wrote — and treats PR-added sections the
same as PR-added files.

Reader A's reading means this branch's own added section could not have been
polished internally; reader B's means the "whole" qualifier is dead text.

The branches: say explicitly that a new section in a pre-existing file is not
PR-introduced surface and why, or extend the rule to hunks.

### B7. [Task 10] PR-introduced prose gets a commit destination but no bucket

Deferred text: "Review-loop edits to it are internal: applied and batched with
the iteration's action commit, no checklist entry". No bucket is named.

Reader A infers Auto-applicable — but then condition 1 (tool-grounding) and
condition 4 (three passes converged) must still hold, and a meaning-class
rewrite of a new doctrine file satisfies neither, so it cannot be
Auto-applicable. Reader B infers a fifth, unnamed disposition, which collides
with "every routed finding ends in exactly one of five terminal dispositions …
There is no silent drop", and leaves the finding with no audit table to sit in.
"The iteration's action commit" is also undefined in `gate-wiring.md`; it
appears only in three SKILL.md files.

The branches: name the bucket these findings land in, and define "action
commit" in the wiring doc.

### B8. [Task 10] The expression-only lane is reachable for signed spec bundles

`doctrine/spec-format.md` imposes three writer obligations in order: a
stale-anchor pre-flight before the first edit; for an expression-only edit, the
edit plus a dated Changelog entry plus a marked re-anchor **in one commit**; and
refusal for meaning-class. The landed prose section names only the third.

Reader A: prose findings on signed bundles owe all three, and the one-commit
ritual constrains what may share a commit with them. Reader B: the section is
the complete rule, so an expression-only fix to a signed bundle is
Auto-applicable and batches into the iteration's action commit with no anchor
pre-flight and no Changelog entry — the exact drift `spec-format.md` says makes
a bundle unrecoverable.

This is live, not theoretical: expression-only spec-bundle prose is the most
likely prose finding to be classed Auto-applicable.

The branches: name all three obligations in the prose section, and state whether
the one-commit ritual permits unrelated batch members.

### B9. [Task 10] "a reader outside the PR relies on" is unbounded in both directions

Reader A: a *current* consumer — another repo, an adopter, a script that parses
the doc. Reader B: any future reader of merged doctrine, which is every doctrine
statement, making every meaning-class doctrine edit an external-contract change
and the definition a no-op. "Relies on" has no evidence standard either:
demonstrated dependency versus conceivable dependency.

The branches: anchor it — "a reader outside this PR's branch who can observe the
rule today" — with an example of each side.

### B10. [Task 10] "neither … alone sends it to Needs sign-off" leaves three routes live but unmentioned

Reader A reads "alone" precisely: the other Needs-sign-off routes still fire, so
a multi-step prose rewrite still routes to sign-off. Reader B reads the
paragraph as the disposition for prose external-contract questions and treats
the whole sign-off list as neutralized for wording.

The branches: state which of the four sign-off routes remain available to prose
findings.

### B11. [Task 10] "until it merges" has no re-evaluation point on stacked work

A branch whose base is another unmerged feature branch: the file is absent from
both, so it is internal — until the lower PR merges mid-loop and the file
becomes pre-existing, changing the disposition of a finding already applied and
committed. Nothing says whether dispositions are re-evaluated.

The branches: fix the evaluation moment ("as of the pass's recorded base SHA")
and say dispositions are not revisited.

---

## C. Underspecified, but practice would converge

- **C1. "a documentation guard the project ships" is enumerated only in a doc
  that does not cite it.** `doctrine/discovery-rigor.md` names the category;
  the only list is in `doctrine/finding-categorization.md`, which
  `discovery-rigor.md` never cites. A reader could reasonably include
  `check:options`, `check:obs`, `check:memory-links`,
  `check:doctrine-manifest`, `check:anchor-freshness`. Converges in practice
  because all of them are prose guards; worth naming the set once.
- **C2. Documentation overlaps Cross-file consistency.** "Prose the change
  falsifies or leaves stale" is also lens 9's territory. The dedupe rule lets a
  finding carry both labels, so nothing is lost; only the Notes-cell class rule
  then applies to one of them.
- **C3. "the ordinary doctrine-edit route" is undefined.** Reader A: a
  Needs-sign-off prose fix on any PR. Reader B: a `/spec-draft` +
  `/spec-kickoff` bundle. Low stakes — the word list grows rarely.
- **C4. "routes the finding downward … never upward" has no defined bottom.**
  From Needs human judgment there is nowhere lower, so the rule is vacuous
  there. Stating the ordering once and marking the last bucket terminal would
  close it.
- **C5. "the meta-spec" used as a bare term.** `spec-format.md` is linked five
  lines earlier but the doc never equates the two names.
- **C6. "Validation Rigor's non-testable substitute" is a loose label.** The
  target section is `## Non-testable changes` and the phrase appears nowhere in
  it; the target also does not mention the preservation check it is now the
  home of. [Task 10]
- **C7. The summary line and the checklist entry label the same batch
  differently** in the worked example ("2 prose fixes" versus "2 meaning-class
  prose fixes"), and nothing says whether the summary must carry the
  classification.
- **C8. "changes code behaviour" versus "user-observable".** Listed as A18 for
  the fork; the underspecified half is that the governing clause covers only
  buckets, predicates and zones.
- **C9. `absent` is defined only on the before side of a manifest line.** A
  prose fix that *deletes* a stale rule has no notation for the after side.
- **C10. before/after: verbatim or paraphrase.** The example lines are
  unquoted lowercase paraphrases; nothing says which is required, or what
  happens when the rule is longer than a line.
- **C11. Bare `REQ-C1.x` in `doctrine/gate-wiring.md` now has three possible
  owners** — bootstrap's, output-hygiene's, and prose-disposition's — and
  output-hygiene's are not declared in the Citations line at all. Pre-existing,
  worsened by one more family.
- **C12. The comment-block guard is named as a shipped grounding but does not
  exist yet.** Task 4 of this bundle builds it and Task 3 writes its rule doc.
  REQ-B1.2 names it, so this is spec-sanctioned ordering, not a defect — but a
  reader at this commit has a grounding they cannot run. [Task 10]
- **C13. `specs/output-hygiene` names "the merge-strategy matrix"** as
  `gate-wiring.md` content in its Deliverables and its REQ-C1.4 verification.
  This branch replaced the table with prose and kept the name on it; if that
  bundle wanted the table shape specifically, the name alone may not satisfy
  it.
- **C14. `docs/getting-started.md`: "Everything the agent applied on a branch
  is one revert from undone until you merge."** True of the branch as a whole,
  false read per-finding now that prose batches — which is the reading the
  sign-off contract around it invites.
