# Prose disposition — Instruction-budget measurement record

The measurement behind Task 10's escalation, kept so the operator decision it
asks for can be audited rather than taken on trust, and so whoever funds the
task later does not re-derive it. Every figure this record measures itself was
produced by a command this file names; nothing is asserted from reading.

Two figures are **carried from earlier tasks** rather than measured here, and
are marked as such where they appear in *Rung 1* below: Task 1's fifteen
restored rules and Task 2's 27 safe words. Their evidence lives with the task
that produced it. Task 1's is PR #457 and the 2026-09-13 amendment-log entry in
`kickoff-brief.md`; Task 2's candidate table, with the manifest grep per
candidate, is in PR #478's body. Task 2's 27 is also re-counted first-hand
below, since its two phrases are still in the tree; Task 1's fifteen is not
reproducible without replaying that task's dedupe diet, so it stands on its
record.

This file is **not part of the content anchor** (`scripts/spec-anchor.sh`
covers `requirements.md`, `design.md`, `tasks.md` and `test-spec.md` only), so
appending a section neither moves the anchor nor needs a re-anchor entry. Same
arrangement as `specs/concurrent-orchestrator-coordination/verification-notes.md`
and `specs/prompt-hygiene/diet-plans.md`.

**What lives where.** The observation fragment
`specs/_observations/entries/2026-09-21-prose-lane-budget-wall-7c02f52b.md`
carries the conclusion and the load-bearing figures, for mining. PR #483's body
carries the argument. This file carries the derivation: the raw guard output,
the per-surface margins beside the ratchet pins they are measured against, the
diet survey candidate by candidate, and the independent verification pass.
`task-10-auto-lane.patch`, beside it, is the text the measurements were taken
on.

Task 12 carries the same obligation on the same two surfaces. When it measures,
its record belongs in this file as a second section, not as a sibling file.

## Provenance

Every command below is run from the repository root.

| | |
| --- | --- |
| Measured at | `7f2dde115ffd8274f59bb5d8a834bcb484ba93a0` (the branch's merge base with `origin/main`) |
| Branch | `planwright/prose-disposition/task-10` |
| PR | #483 |
| Guard | `scripts/check-instructions.sh` |
| Ratchet pins | `config/instruction-budget-exemptions.txt` |

The branch's own commits touch `specs/_observations/entries/` and this bundle
only, so the tree the guard sees at branch HEAD is identical to the tree at
that base for every surface measured here. Re-running any command below at
branch HEAD reproduces the figure.

`origin/main` has since advanced past that base. Re-measuring on a merged tree
is a different measurement; do not compare its numbers to these without saying
so.

## The artifact: `task-10-auto-lane.patch`

The three rules REQ-B1.2, REQ-B1.3 and REQ-B1.4 written out in
`doctrine/finding-categorization.md`, the `Citations:` line and
`doctrine/README.md` index row that Task 10's `Deliverables:` names, and one
gist per skill (`/self-review`, `/polish`, `/execute-task`) for the
PR-introduced-surface rule. It is the exact tree the Reading B figures below
were taken on.

```sh
git apply --check specs/prose-disposition/task-10-auto-lane.patch   # verify
git apply specs/prose-disposition/task-10-auto-lane.patch           # apply
```

Applying it without funding reproduces `EXIT=1` with the two ratchet errors in
[Reading B](#reading-b-the-patchs-scope) below. That is the escalation, not a
defect in the patch.

Its scope is one gist per skill, not three. That was a judgment when the patch
was drafted; `origin/main` has since settled it in the spec itself, Task 10's
`Deliverables:` now reading "One gist per skill, not three" (#479). The
over-scoped three-gist draft is **not** kept: the alternative it measured is no
longer live, and its only load-bearing output is the Reading A row in the table
below.

**One fidelity note for whoever applies it.** REQ-B1.4's parenthetical says a
PR-introduced doc file counts "whole". The drafted sentence carries that by
making the file the subject ("A file the PR itself introduces … carries no
external contract until merge") rather than the added lines, and the scenario's
"diff shows the new doc whole" is carried by "reviewed as new content in the
diff". A reviewer who prefers the literal word can add it for one word, which
moves no figure here.

## Baseline

```sh
./scripts/check-instructions.sh --audit
```

`EXIT=0`. The surfaces this task lands on, excerpted from the `Per-file` and
`Per-skill load` sections of that run:

```
  words=3999 lines=493 skills/execute-task/SKILL.md WARN margin-to-warn=-999 margin-to-error=251
  words=2041 lines=262 skills/self-review/SKILL.md ok margin-to-warn=959 margin-to-error=2209
  words=1613 lines=214 skills/polish/SKILL.md ok margin-to-warn=1387 margin-to-error=2637
  words=1488 lines=195 doctrine/finding-categorization.md ok margin-to-warn=1012 margin-to-error=2512

  builder       start-load=9297 (WARN) margin-to-error=703
  execute-task  start-load=8292 (WARN) margin-to-error=1708  closure=17592 (WARN) margin-to-error=2875
  polish        start-load=8981 (WARN) margin-to-error=1019
  self-review   start-load=9409 (WARN) margin-to-error=591
```

The start-load warnings are the standing state of these surfaces, not this
task's doing; the guard exits 0 on them.

### The pins, and why the margin is not the slack

Three of these surfaces carry a **ratcheted** `declared-exception` entry. A
ratchet is a fail-closed error, not a warning: a later run whose margin falls
below the granted one is a widening, and the entry's own text says so ("the
entry defers a restoration, it does not license further spending"). So the room
a surface actually has is its margin minus its pin, not its margin.

```sh
grep -E 'self-review|polish|builder|execute-task' config/instruction-budget-exemptions.txt
```

| Surface | Baseline margin | Pinned at | Real slack |
| --- | --- | --- | --- |
| `skills/execute-task/SKILL.md` (per-file) | 251 | `margin=251` | **0 words** |
| `start-load:self-review` | 591 | `margin=566` | **25 words** |
| `start-load:builder` | 703 | `margin=515` | 188 words |
| `start-load:polish` | 1019 | no entry; restoration target 1000 | 19 words, warn only |

The wall was reproduced directly before any rule text was drafted: 30 filler
words appended to `doctrine/finding-categorization.md` produce

```
ERROR: declared-exception widened: start-load:self-review margin=561 is below the 566 it was granted at
```

## Three measurements, smallest scope up

Each row is the same `./scripts/check-instructions.sh --audit` run against a
tree with the stated text applied and nothing else. "free N" is the words that
must be found before the ratchet is satisfied.

| Scope | `start-load:self-review` | `skills/execute-task/SKILL.md` | `start-load:polish` | `start-load:builder` |
| --- | --- | --- | --- | --- |
| Baseline | 591 (pin 566) | 251 (pin 251) | 1019 (target 1000) | 703 (pin 515) |
| Doctrine doc only, no gists | 424 — **free 142**, error | 251 — ok | 852 — warn | 536 — ok |
| **Reading B** (doc + 1 gist each) | 395 — **free 171**, error | 222 — **free 29**, error | 823 — warn | 536 — ok |
| Reading A (doc + 3 gists each) | 370 — free 196, error | 199 — free 52, error | 794 — warn | 536 — ok |

The headline is the middle row: **the doctrine doc's 167-word delta alone, with
zero per-skill gists, already puts `start-load:self-review` 142 words below its
pin.** (164 of those 167 are the three rule paragraphs; see *The two word
counts* below.)
`doctrine/finding-categorization.md` is front-loaded by `/self-review`, so its
words are charged whatever the skills do or do not say. Every scoping question
moves the total by tens of words; none of them reaches the wall.

### Reading B, the patch's scope

```sh
git apply specs/prose-disposition/task-10-auto-lane.patch
./scripts/check-instructions.sh --audit
```

```
check-instructions: ERROR: declared-exception widened: skills/execute-task/SKILL.md margin=222 is below the 251 it was granted at
check-instructions: WARN: floor-breach: skills/execute-task/SKILL.md margin=222 below headroom floor 250 (error threshold 4250, words 4028)
check-instructions: WARN: declared-exception escalated: skills/execute-task/SKILL.md has fallen past its headroom floor
check-instructions: ERROR: declared-exception widened: start-load:self-review margin=395 is below the 566 it was granted at
check-instructions: WARN: floor-breach: start-load:self-review margin=395 below headroom floor 500 (error threshold 10000, words 9605)
check-instructions: WARN: declared-exception escalated: start-load:self-review has fallen past its headroom floor
check-instructions: WARN: below-target: start-load:polish margin=823 below restoration target 1000 (headroom floor 500, error threshold 10000, words 9177)
EXIT=1
```

**Hard funding needed: 200 words**, 171 on `/self-review` and 29 on
`/execute-task`. `/polish` is warn-level only; `/builder` passes with 21 words
to spare.

Both error surfaces also fall past their **headroom floors**, which is the
branch of the restoration ladder `doctrine/instruction-hygiene.md` routes to a
human ("Below its floor and blocked ⇒ escalate to the human"). The guard says
the same in its own words on that run: `declared-exception escalated: … the
restoration it defers came due`.

Restore the tree after measuring, by reversing the patch rather than by
discarding the files:

```sh
git apply -R specs/prose-disposition/task-10-auto-lane.patch
```

Reversal undoes exactly what the apply step added and nothing else, and it
refuses to run when the hunks no longer match, so a tree that has drifted stops
the recipe instead of losing work. `git checkout --` over those five paths would
restore them to `HEAD` wholesale, silently destroying any unrelated uncommitted
edit anyone had in them. Do not simplify this back to a checkout.

### The two word counts, which are not the same number

| Figure | What it counts | Command |
| --- | --- | --- |
| **167** | the whole delta to `doctrine/finding-categorization.md`: the three paragraphs plus the three REQ-IDs added to its `Citations:` line | `start-load:builder` 9297 → 9464 under the patch; `/builder` loads that doc at run start and nothing else in the patch reaches it |
| **164** | the three rule paragraphs alone | `sed -n '152,170p' doctrine/finding-categorization.md \| wc -w`, with the patch applied |

The guard counts with `wc -w`, so the second command is the guard's own
arithmetic rather than an approximation of it. 167 is the figure the table
above and the observation fragment use, because charging is per file.

## Rung 1: the diet survey

`doctrine/instruction-hygiene.md`'s restoration ladder puts a compensating trim
first. Three independent surveys have now run it.

- **Task 1 (#457)** ran the run-start dedupe diet over this doc and its
  neighbours. It went green, and its own convergence pass then found the trim
  had cut **fifteen rules, not restatement**, each the last place a rule lived
  for at least one loading skill. All fifteen restored. Its record: "the
  remaining gap was not reachable by further dedupe without cutting law."
  *Carried, not measured here*: the evidence is PR #457 and the 2026-09-13
  amendment-log entry in `kickoff-brief.md`. Reproducing it means replaying
  that task's diet against that task's tree, which this record does not do.
- **Task 2 (#478)** surveyed the three skill bodies: five candidates, three
  rejected as last copies, **27 safe words** against a 180-word need.
  *Carried, not measured here*: the candidate table and the manifest grep per
  candidate are in PR #478's body. The total was re-counted first-hand against
  this tree, where both surviving candidates still sit
  (`skills/execute-task/SKILL.md` "so it trips neither corruption guard (full
  race rationale at PR step 3)" and `skills/self-review/SKILL.md` "one row per
  lens, empty lenses as `none` or `n/a` with a one-line reason"), each piped
  through `wc -w`, the guard's own arithmetic: 13 + 14 = 27. The 180-word need
  is Task 2's own measurement and is not re-derived here.
- **This task** surveyed the run-start doctrine docs, the surface Task 2 did
  not cover. Five candidates, below.

The test applied to each is not "does this rule appear elsewhere" but **"does
it appear in a doc the affected skill loads"**. A rule surviving in a doc the
losing skill does not load is, for that skill, gone. That is the error Task 1's
convergence caught, so every candidate carries the manifest check that was run
on it.

| # | Candidate | Words | Manifest check run | Verdict |
| --- | --- | --- | --- | --- |
| E1 | `finding-categorization.md` "Presentation" §, first para | ~55 | `gate-wiring.md:170-171,186,243` carries the emit rule, the `none` row, the declined log and artifact-side. `gate-wiring` is run-start for `/self-review` and `/polish`, point-of-use for `/builder`, so all three reach it. | **Rejected.** Task 1's convergence restored this class deliberately (its item #12: the projection rule was lost because "neither `/self-review` nor `/polish` loads `interaction-style`"). Re-cutting it repeats the error that pass caught. |
| E2 | `finding-categorization.md` projection paragraph | ~45 | `grep -rn projection doctrine/` → also `discovery-rigor.md:64` **and** `gate-wiring.md:244`, both run-start for `/self-review` and `/polish`. `/builder` is not symmetric with them: it loads `gate-wiring` **point-of-use** and does **not** load `discovery-rigor` at all, so it reaches the rule through `gate-wiring.md:244` and `interaction-style.md:103`, both point-of-use in its manifest. A genuine third copy, reachable by every loading skill. | **Safe.** The only new funding this survey found. |
| E3 | `finding-categorization.md` "Declined-with-rationale" § | ~60 | `gate-wiring.md:50-52` carries the disposition; the declined log's `Where re-raisable` column implies but does not state that declined findings stay visible and re-raisable **at PR review**. | **Rejected: last copy** of the PR-review visibility rule. |
| E4 | `finding-categorization.md` bucket 3, applied-on-branch / checklist / revert | ~50 | Task 1's convergence *added* this wording (#457: "the promise of one revert per finding is false for a member of a batched prose commit"). | **Rejected: just-landed law.** |
| E5 | `doctrine/gate-wiring.md`, any trim | — | Not attempted. | **Out of bounds.** The doc sits over its per-file warn threshold by the operator's recorded decision (#457's accepted deviation); this run treats that as accepted state, not a defect. |

**The `/builder` facts in E1 and E2 are the corrected ones.** Both rows first
justified themselves with "run-start for all three loading skills". That is
false: `/builder` carries `Doctrine: point-of-use gate-wiring` and no
`discovery-rigor` entry at all. The manifests were re-read for all three
loading skills and the verdicts hold anyway, for the reasons written into the
rows above. Recorded rather than silently fixed because the recurring error on
this work is treating the three loading skills as symmetric when their
manifests differ, and it has now produced two corrections in a row.

```sh
grep -n 'Doctrine:' skills/builder/SKILL.md skills/self-review/SKILL.md skills/polish/SKILL.md
```

### What the three surveys leave, by the surface it can be spent on

Safe diet does not fungibly move between surfaces: a word freed in a skill body
only relieves that file and the aggregates that load it.

| Surface | Needs freed (Reading B) | Safe diet available | Shortfall |
| --- | --- | --- | --- |
| `start-load:self-review` | 171 | 59 (Task 2's C4, 14 words in the skill body, plus E2's 45 in the doc) | **112** |
| `skills/execute-task/SKILL.md` | 29 | 13 (Task 2's C2) | **16** |

## Rungs 2 to 4

**Rung 2, point-of-use reclassification.** Inapplicable to the doc itself, and
recorded here because the ladder requires each rung be shown consulted: the
categorization predicates decide what `/self-review` and `/polish` may apply
autonomously, which is gating law, and "no rung defers gating law."

A rung-2 move that *would* work: reclassifying `doctrine/security-posture.md`
(467 words) or `doctrine/refactor-instinct.md` (422) out of `/self-review`'s
run-start manifest, each used at one named step, frees far more than 200 words.
Not taken here, because it rewrites a skill's doctrine manifest, which is
outside Task 10's `Deliverables:` and is a contract call rather than an
execution one. It is the strongest option on the menu below.

**Rung 3, deliberate budget raise.** Forbidden by Task 10's own `Done when:`
("the suppression list gains no `raise` entry").

**Rung 4, exemption.** Per-file only. `start-load:self-review` is an aggregate
surface, so the ladder tops out at rung 3 and, per
`doctrine/instruction-hygiene.md`, "escalates to the human thereafter."

## The operator decision this measurement asks for

Four options. Each is a contract call the execution run declined to make alone.
Option 1 or 2 is the recommendation; both leave every rule intact.

1. **Instruction-headroom relief.** All four declared exceptions in the
   suppression list already defer their diet "to instruction-headroom relief".
   It is the named, anticipated answer, and the only option that also unblocks
   Task 2's parked instantiation, Task 12's funding obligation, and whatever
   lands next on these surfaces.
2. **Rung-2 reclassification of `/self-review`'s manifest.** Move
   `security-posture` and/or `refactor-instinct` from run-start to
   point-of-use. Frees 422 to 889 words against a 200-word need, costs no
   doctrine text, and both are already used at a single named step. Needs a
   judgment on whether artifact data-hygiene is gating law at run start.
3. **Split the categorization doc.** Give the prose rules their own doc, loaded
   point-of-use by `/self-review` and `/polish`. Keeps every word of law and
   moves the charge to the closure aggregates, which under the patch still sit
   4,904 and 5,332 words under their warn thresholds. Costs a new doc and an
   index row.
4. **Narrow the requirement.** REQ-B1.2, REQ-B1.3 and REQ-B1.4 land in fewer
   than 167 words only by dropping clauses their `Done when:` names, so this is
   a `/spec-kickoff` delta re-walkthrough, not an execution trim.

One funding decision settles Tasks 10, 11 and 12 together; three separate ones
re-derive this measurement three times.

## Independent verification

A second worker re-ran every measurement in PR #483's body against the branch
before the operator decides on it. **All six claims reproduced, and every figure
this record measures stands unchanged.** Nothing in that pass asked for a number
to move. Its scope was the measurements taken here; the two figures carried from
Tasks 1 and 2 were outside it, as the opening says.

Three defects were found in the *record*, all corrected.

1. **The observation fragment's "under 15 percent" did not reproduce.** Against
   the denominators the fragment itself stated, Task 2 returned 27 of 180
   (15.0 percent, not under) and Task 10 returned 45 of 200 (22.5 percent). No
   stated denominator yields the claim. Fixed in `e1a62cb` by stating the raw
   shortfalls and adding the 200-word need the Task 10 survey was measured
   against, so both ratios are reproducible from the fragment alone. The
   conclusion that the rung is exhausted rests on the raw figures and never
   needed a ratio. This one mattered most: a fragment gets mined later by people
   without this context, so an unreproducible number is worse there than
   anywhere else.
2. **The patch omitted a named deliverable.** Task 10's `Deliverables:` asks for
   the `doctrine/README.md` index row alongside the `Citations:` entries. The
   first draft updated the citations inside `doctrine/finding-categorization.md`
   and never touched the index row, whose citations column still read
   `prose-disposition REQ-B1.1, REQ-B1.5`. `check:doctrine-index` checks
   bijection, not citation currency, so nothing caught it. The index row is in
   the committed patch. `doctrine/README.md` is excluded from the
   instruction-budget guard per REQ-A1.1, so no measured figure changes.
3. **E1 and E2 cited a wrong manifest fact**, corrected in place in the survey
   table above. The verdicts survive; the answer was right for a reason that was
   wrong.

Two label slips, minor, neither changing an arithmetic result:

- **167** is the delta on the doctrine doc, not the three paragraphs; the three
  rule paragraphs alone come to **164**. Both are derived in *The two word
  counts* above.
- "cheaper by 48" is the hard-funding delta between Reading A and Reading B, not
  a word count of text. The raw skill-body text difference is 77 words.

# Task 12 — the funding that landed

Task 10's section above escalated a fork; this section records how Task 12
answered it on the two hard-error surfaces, `/self-review` and `/execute-task`.
Measured at `0004276` (`origin/main` at dispatch), branch
`planwright/prose-disposition/task-12`. Guard: `./scripts/check-instructions.sh
--audit`, its own arithmetic throughout; no figure below is hand-counted.

## The correction that decided the route

The dispatch asked for a point-of-use split of `doctrine/finding-categorization.md`,
on the reasoning that the doc is run-start for `/self-review`, `/polish` and
`/builder` at once. That is true, and it funds `/self-review`. **It cannot fund
`/execute-task`**, and the reason is structural rather than a question of how
much gets split off:

- `/execute-task`'s binding surface is `skills/execute-task/SKILL.md`'s
  **per-file** count, pinned at `margin=251` with the per-file headroom floor at
  250. Baseline margin-to-error was 251: zero slack, and one added word breaches
  the floor as well as the ratchet.
- `finding-categorization` is already `point-of-use` in that skill's manifest
  (`skills/execute-task/SKILL.md`, the Doctrine block), so it is charged to
  closure, not start-load. Splitting it moves words between two closure members
  and leaves closure unchanged.
- No manifest change and no doctrine split reaches a per-file count. Only words
  physically leaving that file do.

So the two surfaces took different rungs, both inside what REQ-D1.3 and the
task's `Deliverables:` permit.

## `/self-review`: a manifest change (rung 2)

`doctrine/refactor-instinct.md` (422 words) moved from `run-start` to
`point-of-use` in `/self-review`'s manifest. This is Option 2 of the four the
Task 10 section put to the operator, which that section called the strongest on
the menu and declined only because a manifest rewrite was outside Task 10's
`Deliverables:`. Task 12's `Deliverables:` name "a manifest change" explicitly.

No prose was deleted or moved, so no rule can have been lost; the only question
is read-order, answered under *The safety floor* below.

**Why `refactor-instinct` and not `security-posture`.** Option 2 named both. The
first draft of this task took `security-posture` (467 words, the larger of the
two) and the convergence pass reversed it, for two independent reasons that
agreed.

- **The floor's own wording is stricter than the read-order test.**
  `doctrine/instruction-hygiene.md` says a rule that gates whether an action is
  permitted "belongs in the always-loaded core, **in the body or a run-start
  doc**". Artifact data-hygiene gates whether a secret may reach a committed
  artifact, so it is permission-gating law by that sentence's plain reading,
  even though a citation at the Routing step satisfies the read-order test.
  `refactor-instinct` is not: it scopes which refactor findings are *reported*,
  and a model that never opens it over-reports. Noise, never a forbidden
  action. That is `instruction-hygiene`'s "deferred bulk" category verbatim,
  "reference detail consulted at one step".
- **A prior pass decided this exact doc the other way.**
  `specs/prompt-hygiene/diet-plans.md` reclassified `discovery-rigor`,
  `autopilot-reflex` and `validation-rigor` out of `/spec-kickoff`'s run-start
  manifest and recorded that `spec-format`, `security-posture` and
  `interaction-style` **stay run-start**. Deferring `security-posture` here
  would reverse that judgment on the strength of a budget need, which is the
  erosion the floor exists to stop.

The smaller doc still clears the pin with room to spare, so the safer of the two
options was also sufficient: nothing was traded for the 45-word difference.

## `/execute-task`: a doctrine relocation

The `Planwright-Task` trailer convention moved out of the skill body into
`doctrine/spec-format.md`'s *Branch, worktree, and task-id grammar* section,
beside the branch-naming, worktree-placement and task-id grammars it belongs
with. The skill keeps the imperative and the helper invocation and cites the
section for the rest.

`spec-format` is permanently per-file exempt and charged to every dependent
aggregate at `min(actual, 4000)` under the capped-charge law, so the relocation
costs no aggregate anywhere. Reproduced rather than assumed: `closure:spec-kickoff`
reads 19432 before and after, and `start-load:builder` 9297 before and after.

This is the same path `config/instruction-budget-exemptions.txt`'s
`/spec-kickoff` entry records for anchor-integrity Task 6. It is **not** the
re-anchor ritual, the `main`-sync instruction, or the convergence law, which the
`/execute-task` entry names as off limits.

## Manifest check on the one passage that moved

The test is the one Task 1's convergence established: not "does this rule appear
elsewhere" but "does it appear in a doc the affected skill loads".

| Passage | From | To | Manifest check | Verdict |
| --- | --- | --- | --- | --- |
| The `Planwright-Task` trailer convention | `skills/execute-task/SKILL.md` § Commit convention | `doctrine/spec-format.md` § Branch, worktree, and task-id grammar | `grep -n 'Doctrine:' skills/execute-task/SKILL.md` → `Doctrine: run-start spec-format`. `/execute-task` was the only skill that carried the rule at all, and it still reads it, now at run start rather than mid-file. | **Safe.** Reachability strictly increased. |

`doctrine/refactor-instinct.md`'s reclassification moved no text, so it has no
row: nothing could be dropped. Its read-order is checked below instead.

## The safety floor

*Could the model reach the acting step without having read this rule, and if so
could it then take an action the rule forbids?*

| Rule | Skill | Acting step | Evidence it is read at or before that step |
| --- | --- | --- | --- |
| `Planwright-Task` trailer | `/execute-task` | every commit the skill authors; the earliest is pre-flight step 11's `Last activity` commit on a v1 bundle | `spec-format` is a **`run-start`** manifest entry, resolved at pre-flight step 3, before any step runs. Previously the rule sat in the body at the Implementation phase, *after* that pre-flight commit. The move closes a gap rather than opening one. |
| Refactor-flag scoping | `/self-review` | emitting a refactor finding, at the Discovery step's "Filter refactor flags in review mode" bullet | That bullet names the doc and is the only site that reads it; no earlier step of the pass emits a finding. It is also not permission-gating law: unread, it over-reports rather than permitting something forbidden, so the floor's "in the body or a run-start doc" clause does not reach it. |

One change in this diff is a widening rather than a deferral, and belongs here
for the same reason. `/self-review` previously cited artifact data-hygiene only
in *The audit record*, so the commits the Routing step lands and the observation
fragments it writes were uncovered. The citation now sits in the **Routing and
dispositions** intro, ahead of every disposition bullet, and names commit bodies,
audit rows, the PR body and observation fragments. `security-posture` stays
`run-start`.

Precedent for the test and the rung: `specs/prompt-hygiene/diet-plans.md`
records the same reclassification applied to `/spec-kickoff`'s and
`/spec-draft`'s manifests, with the same safety-floor question asked per doc.

## Before and after

Both readings from `./scripts/check-instructions.sh --audit`, `EXIT=0` on each.

| Surface | Pin | Before | After |
| --- | --- | --- | --- |
| `skills/execute-task/SKILL.md` (per-file) | `margin=251` | 251 (3999 words) | **261** (3989 words) |
| `start-load:self-review` | `margin=566` | 591 (9409 words) | **888** (9112 words) |
| `start-load:builder` | `margin=515` | 703 | 703 |
| `skills/orchestrate/SKILL.md` | `margin=251` | 255 | 255 |
| `skills/spec-kickoff/SKILL.md` | `margin=262` | 276 | 276 |
| `closure:orchestrate` | `margin=1002` | 1418 | 1418 |
| `closure:spec-kickoff` | `margin=1002` | 1035 | 1035 |

No suppression-list entry was added, edited, or widened, and no `raise` entry
exists. Both funded surfaces sit above their pins with room for Task 11's and
Task 10's additions to follow.

One warning was deliberately avoided rather than accepted. An earlier draft
added `Doctrine: point-of-use discovery-rigor` to `/execute-task`'s manifest so
the lens-scoping citation would resolve locally. That charges 1018 words to
`closure:execute-task`, taking it to margin 1861 and tripping a new below-target
warning. The entry was dropped: `/execute-task` never runs the lens, it reads
the Documentation row a review skill produced, and that skill loads
`discovery-rigor` at run start. The citation names the doc without the skill
loading it, which the use-site check does not flag in that direction.
