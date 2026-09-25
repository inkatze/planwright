# Review effectiveness — Kickoff brief

## 1. Header

- **Spec path:** `specs/review-effectiveness`
- **Spec commit at walkthrough start:** `5590ba8`
- **Walkthrough date:** 2026-09-24
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `scripts/spec-validate.sh` — 0 errors,
  0 warnings (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (core defaults; no machine-local override present; the repo-tracked
  overlay sets none of the three)
- **Working location:** spec branch `planwright/review-effectiveness/spec`,
  worktree `.claude/worktrees/review-effectiveness-spec`
- **Doctrine resolution:** all nine rule docs the skill names resolved under
  this checkout's `doctrine/` via `scripts/resolve-rule-doc.sh`; the
  decision-domains catalog resolved through `scripts/resolve-catalog.sh`
- **Cross-bundle preconditions checked at start:** custom-steps,
  prose-disposition, instruction-headroom, model-allocation, and
  merge-currency-guard are all Ready on main; every task the `Done when:`
  lines name in those bundles exists
- **Decision/transcript log:** no harness-provided log path in this session;
  the structured-log mirror is skipped, per `interaction-style`'s turn-mirror
  rule (never improvised into the repository)
- **Independent cold read:** `/spec-walkthrough specs/review-effectiveness`
  offered as an optional complement; not a dependency of this walkthrough

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).** The review
passes say a branch is clean, and then the bot reviewer finds real bugs on
most PRs, which costs extra review rounds and fix commits. The passes are
also expensive: about half of what a unit spends goes to reviewing, and most
of that is the parent session re-reading its own long history. This spec
fixes both and measures that it did. On catching more: a short checklist of
reviewer basics runs before any reviewer looks (does the change cover what
the task asked, does the PR text match the diff, do the tests actually test
it, are copies of a changed fact updated, are callers updated, did anything
outside the task change, do earlier fixes still hold); every reviewer gets
the same prepared packet (the diff, the changed files in full, who calls
what changed, the task's contract, the tool output) instead of fetching a
diff slice of its own; a reviewer looks for twins of every problem found;
a bug is confirmed by running the thing, not by a unit test alone; and the
last word is a reviewer who starts fresh, sees only the branch and the
packet, and never the author's history or list of dismissed findings. On
cost: each review starts fresh and small, later iterations look only at what
changed since the last iteration, the doctrine and brief are read once per
loop, the full test suite runs once per iteration, the audit record is written
as deltas, and the review skills shed instructions before any new rule is
added. Small mechanical checks catch the shell and prose mistakes that keep
recurring. A committed collection of past bot findings lets each change to
a reviewer prove it now catches them before it lands, and a measurement
window after everything lands decides whether the spec is Done.

**Rules out.** The operator's own review commands in dotfiles; how steps are
attached to a run; who may mark a PR ready and who merges; syncing with
main mid-loop; which model tier a step gets; how prose findings are
dispositioned and the four buckets; the CI gate's false-red rate; unit
sizing; the implementation phase's own context; anything specific about the
private reviewer.

**Assumes.** custom-steps' convergence and post-pr points and its steps
catalog, the tier resolver's step keys, the observation helper and its
drain ritual, the instruction-budget guard and its exemptions file, and the
polish audit file's home under the worktree's `.claude/` all exist as those
Ready bundles describe them.

**Implicit terms, resolved.**

1. *Loop ledger* (REQ-C1.3, REQ-D1.6) — the per-loop record of findings and
   what was done with each, across iterations. The polish audit file under the
   worktree's `.claude/`, extended so dispositions survive a kill; not a
   new store.
2. *Pass, iteration, loop* — a pass is one review run (a fan-out or one
   blind run); an iteration is a pass plus its fixes; a loop is the whole
   convergence of one unit.
3. *"The bundle SHALL record the baselines"* (REQ-H1.1) — "bundle" means
   this spec's deliverables (Task 1's fixture), not the spec files; the
   goal cites the research seed rather than copying its figures.
4. *Executable surface* (REQ-C1.1) — a script, command, or skill step that
   can be run with the input that triggers the finding; prose and doctrine
   have none.
5. *Miss-reason codes* — D-8's eight names are the research seed's six
   lettered reasons plus `declined` and `other`.

6. *Bundle* — bare "bundle" means this spec; the review input is always
   the "handoff bundle". Added at sign-off.
7. *Plain terms used in this brief* — the prepared packet is the handoff
   bundle; the fresh reviewer or fresh review is the blind pass; the
   checklist is the reviewer-basics gate; the twin sweep is the sibling
   sweep; the looks are the independent angles. Added at sign-off.

**Operator note.** Brief prose and turns stay in plain words; spec
vocabulary (lens, handoff bundle, disposition) appears only where the
identifier is needed for traceability.

Signed off: 2026-09-24

## 3. Requirements walkthrough

Each group was restated to the operator in plain words, with its open
points probed. The operator's decisions are recorded per group and cited
from the spec as `kickoff §3 REQ-<group> (2026-09-24)`.

### REQ-A — Reviewer basics

- **Unattended checklist findings.** A worker treats a checklist finding
  like any other finding under the existing buckets. It fixes what has
  one clear fix and queues the rest for loop end (Awaiting input only
  when it blocks the unit), and the reviewers
  do not start until every checklist item is fixed or parked. No spec
  edit is needed, because REQ-A1.1's "dispositioned" already covers both
  outcomes.
- **"A test that fails without the change" (REQ-A1.4).** The checklist
  judges this by reading. The run-it proof is required only when a
  finding is applied, which REQ-C1.4 already asks for.
- **Re-checks after a fix (REQ-A1.7)** run against a fresh isolated copy
  of the current head. Added by the lens pass, because the recorded
  reproduction's copy predates the fix.

### REQ-B — What reviewers see and how they look

- **A reviewer that dies (REQ-B1.6)** is retried once, then run inline
  from the prepared packet, with its row recording each attempt. An
  inline run is recorded as not independent of the session's context. A
  row still `failed` ends the enclosing convergence early with a report,
  never running to the cap.

### REQ-C — Confirming a finding

- **Reproduction (REQ-C1.1)** runs in an isolated copy: a fixture tree,
  or a fresh clone with the home directory and machine-local state home
  redirected, no push remote, removed on exit. It never runs in the live
  worktree, the remote, or the state home. The operator chose a copy over
  the live checkout, and the lens pass sharpened "temporary worktree" to
  a fresh clone, because a worktree shares refs, remotes, and credentials
  with the live checkout. Where no safe copy exists, a targeted test runs
  and the evidence line says why.

### REQ-D — What the loop costs

- **After the fresh reviewer (REQ-D1.5).** The operator chose `/polish`
  to own the fresh reviewer as its confirming pass. custom-steps rules
  out re-running earlier steps, so a separate step after polish could
  not loop back. An applied fresh-review finding returns polish to
  iterating until quiet. The next fresh review looks only at the delta
  since the previous one, while still receiving the whole branch. Each
  fresh review counts against the cap of ten. A finding dismissed
  without a change counts as nothing new.
- **Efficiency.** The operator asked whether this is efficient. It is.
  In the common case the fresh review replaces today's extra full
  confirming review, so the loop is one full review cheaper than now.
  Only an applied fresh-review finding adds a delta-scoped iteration and
  a delta-scoped repeat review.
- **Convergence criterion.** Written as "zero new dispositions", polish's
  existing criterion, so REQ-D1.5's "otherwise unchanged" holds.

### REQ-E — The fresh reviewer and outside signals

- **The miss ledger's writer (REQ-E1.5)** is any planwright flow that
  applies a post-convergence fix. Fixes made outside planwright reach
  the corpus through the refresh script's fallback: reason `other`,
  matched on PR number and path, with the fallback count reported so
  ledger coverage is visible. The miss grammar carries the PR number and
  path for that match.
- **The "which looks happened" record (REQ-E1.6)** is re-emitted after
  the post-pr step list completes, whether or not the head moved. It
  names each look by its role, never by step or product name. It is the
  one part this spec adds to custom-steps' post-pr regeneration
  (REQ-D1.4).
- **Naming (D-16).** The operator ruled that no committed artifact names
  the bot reviewer or the external model backend unless the operator
  says otherwise for that artifact. Such an exception is recorded in that
  artifact's PR body. The rule covers this spec, its research notes
  (scrubbed in this kickoff before any push), and the observation
  fragments already on main (the operator chose to reword those too;
  see the open item below). A machine-local name list, never a committed
  one, backs the corpus hygiene screen. The spec's private-reviewer
  Source entry and Deferred entry were reworded to generic terms.
  Naming the operator's public dotfiles repository is kept, since that
  repository is public.

### REQ-F and REQ-G — Mechanical checks and the instruction diet

- **The count-versus-list check (REQ-F1.3)** covers doctrine, skills,
  docs, Draft bundles, and pending notes. It skips any bundle at another
  status, whose enumerations the sign-off cross-check owns. The operator
  chose this over auto-fixing signed specs, since an auto-fix could not
  tell whether the count or the list is wrong, and over report-only,
  which costs an amendment cycle per nit.
- **REQ-G** stands as drafted.

### REQ-H — Measuring it

- **One replay row (REQ-H1.2)** is one review pass: the pre-review
  checklist plus one fan-out, no fixes, no loop, in an isolated copy.
  Findings of the dismissed class are replayed with the recorded
  dismissal seeded into the coordinator's ledger (never the fresh
  reviewer's input, corrected at sign-off), which the operator chose over dropping the class or
  replaying a short loop.
- **Sampling and the pass rule (REQ-H1.3, D-9).** Sampling is seeded
  random, one run per row, with a default of five rows per class. The
  operator chose the rule that a task may not land while any class it
  targets catches fewer sampled rows than the baseline did. Improvement
  is recorded, not required, and the rule is fixed before the first run.
- **The corpus** is versioned, and every before-and-after comparison is
  made within one version. The refresh runs on the operator's machine,
  never in CI. It validates PR numbers as integers, fetches each PR's
  head ref, and marks a row unreplayable when its pre-fix commit is not
  in that ref's history. The zero-row refusal applies after that
  exclusion. Reviewer instructions cite the ledger's classes, never its
  rows, so no corpus row reaches a prompt.

### Consolidated spec edits (applied in place, Draft, unsigned)

The requirements Changelog carries the two dated kickoff entries. The
edits:

1. REQ-A1.7 — re-check against a fresh copy of the current head.
2. REQ-B1.6, D-3 — retry, then inline, then early end; the inline run
   recorded as not independent.
3. REQ-C1.1, D-11 — isolated-clone reproduction and the evidence line.
4. REQ-D1.4, D-12 — the angles record as the one post-pr exception.
5. REQ-D1.5, REQ-E1.2, D-5, D-6, D-15 — the fresh reviewer inside polish;
   the repeat review delta-scoped; cap accounting; a new rejected
   alternative in D-5.
6. REQ-E1.5, D-8 — the in-scope writer; the grammar keyed on PR and path;
   the reported fallback.
7. REQ-E1.6 — role-named angles, re-emitted after the post-pr list.
8. REQ-F1.3 — scope and status skip.
9. REQ-H1.2, REQ-H1.3, REQ-H1.4, D-7, D-9 — one-pass replay, the seeded
   dismissal, sampling, the no-drop gate, corpus versions, the refresh
   rules, and the metric's PR-history input.
10. D-16, the Sources entry, and the Deferred entry — the naming rule and
    the generic rewording.
11. Tasks 1, 3, 4, 5, 8, 9, 10, 12, 13 — deliverables, Done-when lines,
    citations, and Task 9's new dependency on Task 8, paired with the
    edits above.
12. The paired `test-spec.md` entries for every edited REQ.
13. `specs/_pending/review-effectiveness-research.md` — product names
    replaced with role terms.

### Mid-walk delta lens pass (applied edits, 2026-09-24)

Scope: the first set of walkthrough edits and what depends on them. Fan-out
ran as four read-only reviewers over the spec lens set.

| Lens (spec class) | Findings | Notes |
| --- | --- | --- |
| Contract correctness, internal consistency | 11 | Replay pass shape, the post-blind loop's owner, regeneration timing, naming versus the angles record |
| Ambiguity, interpretation forks | 10 | Retry row value, loop scope, copy definition, hash and fetch meaning, the per-class cap, zero-row order, status coverage, naming reach |
| Citation and coverage integrity | 12 | Tasks not paired with the edits; the kickoff citation unresolved; no check behind the naming rule |
| Dead verification paths | 6 | Offline fixtures for the refresh, a fault seam for lens failure, unrecorded scenarios |
| Testability | 7 | Negative clauses untested, "back to back" unobservable, the writer duty unevaluable |
| Decision-domain gaps | 9 | Worktree isolation (concurrency), CI auth for the refresh, the corpus shape, the LLM-quality gate, held-out rows, retry cost, the PR-body rewrite, invisible human fixes |
| Rendered-content safety, data hygiene | 7 | Identifying detail on the private reviewer and a product name, product names in derived rows, untrusted PR input, absolute paths |
| Cross-file consistency | 9 | Tasks 1 and 12 stale, D-7 and D-9 stale, the loop-end regeneration rule, the custom-steps regeneration trigger |
| Documentation and glossary drift | 5 | "external reviewer" overloaded, "shared state home", round versus iteration, singular versus plural bot |
| Performance, concurrency, error handling | n/a | Spec class: no execution path |

There were 76 raw findings, clustered into 14 root causes. Each finding was
checked against the files before being dispositioned. Four clusters needed the
operator's judgment: the loop-back owner, the dismissed-class replay, the
replay gate, and the naming reach. The rest follow mechanically from those
decisions or from decisions taken earlier in the walk. All 14 were applied,
except one finding that was declined: naming the dotfiles repository, which
is public. The one captured item is below.

### Captured item

- **Rewording the merged observation fragments.** The operator chose to
  reword the observation fragments on main that name the bot. It is
  tracked as Task 15 in this spec, chosen over an Awaiting-input entry or
  a separate chore PR because a task blocks Done until it lands.

Signed off: 2026-09-24

## 4. Design walkthrough

Every D-ID is accounted for. None was superseded. The reconciled ledger:

| D-ID | Outcome | What changed and why |
| --- | --- | --- |
| D-1 | Confirmed | The altitude placement stands; the sign-off altitude check verifies it against the task list |
| D-2 | Confirmed | The pre-review checklist as a gate; the unattended reading from §3 REQ-A needs no design text |
| D-3 | Amended | The retry order for a failed reviewer, and the inline run recorded as not independent (§3 REQ-B) |
| D-4 | Confirmed | The twin sweep as both a lens and a post-fix step |
| D-5 | Amended | The fresh reviewer is polish's confirming pass; the loop-back, the delta-scoped repeat, and cap accounting; a new rejected alternative (a separate step after polish) (§3 REQ-D) |
| D-6 | Amended | Invoked by polish and still in the steps catalog; its closure is charged alone, since it runs in its own agent |
| D-7 | Amended | Corpus fields, versions, the operator-local refresh, one-pass replay in isolated copies, the seeded dismissal (§3 REQ-H) |
| D-8 | Amended | The miss grammar keyed on PR number and path (§3 REQ-E) |
| D-9 | Amended | Seeded per-class sampling, the default of five, and the no-drop gate fixed in advance (§3 REQ-H) |
| D-10 | Amended | The precondition rule stated generally: a task editing a file another Ready bundle's task edits names that task. Applied to the diet task (waits on prose-disposition's `/polish` task, not yet merged), the validation doctrine task, and the execute-task wiring (both already satisfied) |
| D-11 | Amended | Reproduction in an isolated clone, with the reason a worktree is not enough (§3 REQ-C) |
| D-12 | Amended | The angles record as the one post-pr exception; the diet-first rule scoped to the doctrine polish and self-review load |
| D-13 | Confirmed | Mechanical checks in the guard catalog; the count check's scope lives in REQ-F1.3 |
| D-14 | Confirmed | Delta attention with whole-branch context; D-5 reuses it for the repeat fresh review |
| D-15 | Amended | "The blind step's presence in the default list" reworded to its place as polish's confirming pass |
| D-16 | Amended | The no-product-name rule, its enforcement, and its reach (§3 REQ-E) |

**Operator decision in this section.** REQ-G1.1's "diet before any
doctrine growth" is scoped to the doctrine polish and self-review load.
The fresh reviewer's rule doc is loaded only by that reviewer, in its own
agent, and by `/execute-task`, so it never enters the zero-slack budget
the rule protects. Task 5 stays parallel with the diet. The operator chose
this over making Task 5 wait.

**No contradictions** between a design decision and a walked requirement
remain open.

Signed off: 2026-09-24

## 5. Verification approach

**Coverage mix.** Every REQ has a `test-spec.md` entry (source:
`test-spec.md`'s headings against `requirements.md`'s REQ list). Most
skill-wired behaviour is verified by Gherkin scenarios that a fixture unit
exercises and records in its PR body. Scripts, guards, and budget checks
are `[test]`; doctrine presence is `[design-level]`; `[manual]` covers the
closeout window and the start-load figures read at PR review.

**Ownership.**

- `[test]` entries run under `mise run check` and the repository CI,
  against offline fixtures (the recorded PR history and the local bare
  remote from Task 1).
- A backtest replay needs model access, so it never runs in CI. The
  executing task runs it in its own session and records the recall and
  the no-drop verdict in its PR body. The coverage note in `test-spec.md`
  now says so; before this walk it counted a replay as a CI-run `[test]`,
  which was a dead path.
- `[Gherkin]` scenarios are run by the executing task against fixtures
  and read at PR review. The per-backend scenario (REQ-D1.1, Task 8)
  needs every execution backend installed, so the executing worker runs
  the backends its host offers and the operator runs the rest before the
  PR is marked ready (risk register row 2).
- `[design-level]` entries are checked by each doctrine task's
  `Done when:`.
- `[manual]`: the operator runs the closeout window (Task 14) and reads
  the start-load figures in each skill-editing PR body.

**Dead paths checked.** The lens pass found six dead verification paths:
offline fixtures for the refresh, a fault seam for reviewer failure, and
scenarios no task recorded. All are now built by a named task and listed
in its `Done when:`. The CI-replay dead path above was fixed in this
section. None remain.

Signed off: 2026-09-24

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md`, which are
authoritative. Efforts are the tasks' own `Estimated effort:` lines; the
figures below are derived from them, not copied into the spec. Updated at
sign-off after the lens pass moved work between tasks (§8).

**Edges added in the walk.** Task 7 depends on Task 1, because its
targeted replay needs the harness and the baseline (REQ-H1.3). Task 9
depends on Task 7, because both edit `/self-review` (D-10's same-file rule
applied inside the bundle).

**Edges added at sign-off.** Task 8 depends on Task 3, because the blind
skill reads the reviewer-basics checks from the discovery doctrine. Task
10 depends on Task 5 instead of Task 8, because it wires the verify script
and the miss grammar Task 5 defines. The gate's scripts and the
diff-scoped check moved into Task 6, so Task 9 does not wait on Task 10.

**Start immediately.** Tasks 1, 6, 11, and 12 have no dependencies and no
cross-bundle precondition. Task 2 has no in-bundle dependency but waits
for prose-disposition's `/polish` task to merge (ready, not yet
dispatched).

**Critical path (effort-weighted).** Task 1 → Task 5 → Task 8 → Task 9 →
Task 13 → Task 14. The in-bundle arithmetic understates the real pacing:
Task 8 waits for custom-steps' catalog task (in progress) and its
knob-removal task (blocked on its own dependencies); Task 10 waits for
custom-steps' execute-task wiring; Task 4 waits for human-gates' doctrine
rewrite (in progress). custom-steps is the long pole for the fresh
reviewer and everything after it.

**Parallel lanes.**

- The measurement lane: Task 1, then Tasks 5 and 15.
- The diet and doctrine lane: Task 2, then Tasks 3 and 4.
- The scripts lane: Task 6 (handoff builder, gate scripts, diff-scoped
  check).
- The guard lane: Tasks 11 and 12, which join only at Task 14.
- They converge at Task 7 (checklist), Task 8 (fresh reviewer), Task 9
  (the loop), Task 10 (execute-task wiring), then Tasks 13 and 14.

**Deliberate non-edges.** Nobody should "fix" these:

- **Task 5 does not depend on Task 2.** The fresh reviewer's doc is
  outside the review skills' budget (§4).
- **Tasks 3 and 6 do not replay the corpus.** Doctrine and scripts change
  no reviewer's behaviour until a skill instantiates them, so the replay
  gate runs at Tasks 7, 8, and 9 (REQ-H1.3 now says so).
- **Tasks 11 and 12 do not gate Tasks 7 to 10 or 13.** The guards change
  no reviewer, so the replay is independent of them. They gate only the
  closeout window, which measures the post-convergence finding rate they
  affect.
- **Tasks 13 and 14 do not depend on Task 15.** The reword changes no
  behaviour; it blocks Done only as a task.
- **Task 10 does not depend on Task 9, nor Task 9 on Task 10.**
  Execute-task reads polish's angles record through the record format
  Task 5 defines, and polish takes the diff-scoped check from Task 6.

Signed off: 2026-09-24

## 7. Risk register

Inputs: risks surfaced during the walk, the lens pass, and the
decision-domains gap check (core seed catalog through
`scripts/resolve-catalog.sh decision-domains`; no overlay layers present).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | custom-steps paces the fresh reviewer: Task 8 waits on its catalog and knob-removal tasks, and Task 10 on its execute-task wiring | The diet, doctrine, handoff, guard, and measurement lanes run meanwhile. Early signal: custom-steps' status render still shows its catalog task in progress when Tasks 5 and 6 land |
| 2 | The per-backend scenario (REQ-D1.1) needs every execution backend, and one worker's host may offer only some | The worker runs what its host offers, and the operator runs the rest before the PR is marked ready (§5). Signal: a Task 8 PR body with a backend row marked not run |
| 3 | Most skill behaviour is verified by scenarios recorded in PR bodies, which guard nothing after landing | The backtest replay is the durable regression net for reviewer behaviour (Task 13 and every later reviewer change); the closeout window measures the live effect |
| 4 | Word-neutral landing at zero slack: the doctrine and skill tasks may not fit their rules without growing the start-load | The diet lands first (Task 2); the instruction-headroom ladder applies if a task cannot fit. Signal: `check:instructions` red on Task 3 or Task 9 |
| 5 | The diet waits on prose-disposition's `/polish` task, which is ready but not yet dispatched | Dispatch that task early. Signal: Task 2 blocked on its precondition at the first orchestrate step |
| 6 | Replay cost: each row is one full review pass, so a targeted replay over several classes costs several passes' tokens | Task 1's baseline replay measures per-row cost; the per-class cap is a command-line value the operator can lower. Signal: the baseline's recorded cost |
| 7 | The replay gate is noisy: one run per row at five rows per class | Seed recorded; a failed gate is not re-rolled with a new seed without the operator (D-9); the closeout window is the larger sample. Signal: a task failing its gate by a single row |
| 8 | A model change moves recall in every class, making a before-and-after comparison meaningless (domain 17) | Baselines record their model; a cross-model comparison is refused and the baseline re-run (REQ-H1.2, D-9, added in this section) |
| 9 | The corpus is not held out from this spec's own reviewer design: the research that shaped the lenses mined the same findings (domain 17) | Accepted by the operator: the replay is a regression guard only (the no-drop rule), and the closeout window over PRs merged after landing is the held-out effectiveness measure that decides Done (D-9) |
| 10 | The miss grammar is a contract that the operator's outside review commands write to (domain 4) | The grammar check refuses malformed text, so a drift fails loudly; a grammar change is a meaning-class amendment of the independence rule doc |
| 11 | The product-name list is a new machine-local input (domains 6 and 19) | It lives in the machine-local state home; the refresh refuses to run without it; CI runs the rest of the screen (D-16, added in this section) |
| 12 | Task 15 rewrites committed observation text (domain 9's data-edit zone) | One commit, reviewed as a normal PR, revertable; UIDs, dates, and consumption lines untouched |
| 13 | Replay and reproduction execute historical or finding-triggering code | Isolated clones with the home and state home redirected and no push remote (REQ-C1.1) |
| 14 | With no external backend attached, the fresh reviewer is the same model family, independent in context only | Accepted: the PR body says so per unit (REQ-E1.3, REQ-E1.6); this repository's overlay may attach an external backend |
| 15 | The private reviewer's design lessons are unread | Deferred entry, gated on a permitted read; never cited by name |
| 16 | The corpus labels (category, miss reason) were model- or rule-assigned and about one in five wrong in the research's spot check (domain 14) | The catch rule matches on file and line, not labels; the corpus records each label's source; per-class noise is read with row 7 |
| 17 | `declined` rows may be scarce: the research folded declines into the pruned reason | Task 1 derives them from each PR body's declined log; a targeted class with zero replayable rows is refused loudly (REQ-H1.2). Signal: Task 1's per-class row counts |
| 18 | The corpus paraphrases third-party review text (domain 16) | Only paraphrased gists and dismissals, never reviewer text or logins (D-7, D-16); provenance is this public repository's own PRs |
| 19 | Switching this repository's convergence to `/polish` (Task 10) costs a loop where one self-review pass ran | Delta scoping keeps later passes small; the closeout's cost metric measures it against the baseline |
| 20 | The replay's model session and the isolated copy's redirected home could collide (domains 5 and 6) | Only executed commands see the copy's home; the reviewing session keeps its own credentials, none copied (REQ-C1.1) |

**Gap check, domains with no row** (corrected at sign-off). Data storage (the corpus, ledger,
and bundle shapes are decided in D-3, D-7, D-8). Caching (the bundle is
assembled per pass, and doctrine is resolved by path, so in-loop content
edits are read fresh). Queues (the retry order is decided in REQ-B1.6).
Authentication (the refresh uses the operator's existing GitHub login,
operator-local, D-7). Concurrency (isolated clones per run; the post-pr
re-emit is serial within custom-steps' list). Observability (failed
reviewers, unreplayable rows, and the `other` fallback are all counted and
reported). Dependency adoption (caller search is a grep heuristic, no new
dependency, D-3). Versioning (a corpus version is a `v<N>` directory and a
baseline records its model id, D-7). Domain modelling (the miss-reason
tokens are fixed in D-8; label noise is row 16). Organization design (the
operator's added steps are named in §5 and D-9). Information UX (the
angles record follows output-hygiene's collapsed-detail convention,
REQ-E1.6). Product strategy and packaging do not apply.

Signed off: 2026-09-24

## 8. Sign-off

### Lens review pass (full bundle, first activation)

Scope: the whole bundle and this brief, spec lens set. The pass fanned out to
five read-only reviewers on Opus. Four took one or two lenses each, and the
fifth ran the kickoff check items: the altitude check, the ship-gate check,
and a self-critique sweep.

| Lens (spec class) | Findings | Notes |
| --- | --- | --- |
| Contract correctness, internal consistency | 21 | The blind pass handed the decline ledger it must not see; the bundle built per pass and per loop; fresh context delivered for the blind pass only; a replay class the vocabulary lacks; generator fallback versus context-only; a single-angle ban the core default cannot meet |
| Ambiguity, interpretation forks | 17 | Test judged by reading or running; the scope fence as note or finding; the replay's seed reuse; the redirected home and the model session; "last mechanism task"; vacuous-assertion shapes; angle vocabulary |
| Citation and coverage integrity | 30 | Task citations not paired with test-spec entries; fresh context unowned for ordinary passes; the verify script unwired; no dismissal field; no blind-review step keys; REQ clauses no scenario checked |
| Dead verification paths | 9 | No reviewer stub for offline harness tests; "never in CI" unenforced; the baseline unrepeatable after doctrine moves; scenarios no Done-when recorded; a resolver test never built |
| Testability | 8 | An exemptions entry kind that does not exist; an empty closeout window; recall stated in a `Done when:`; no-drop missing from two tasks |
| Cross-file consistency | 28 | This repository never runs polish; the audit file's per-run overwrite (operator-dialogue D-16); the per-fix full suite in validation-rigor; the error threshold is a config knob; D-6 choosing its own rejected shape; D-15's origin tag |
| Documentation and glossary drift | 11 | "Round" at two levels; bare "bundle" and "handoff"; three names for the loop ledger; "external reviewer"; "declined" twice; plain brief terms unmapped |
| Decision-domain gaps | 12 | The catch rule undefined; the closeout judges nothing; model credentials under a redirected home; the output contract's shape; label noise; corpus version identity; caller search; audit-file rollout; IP provenance |
| Rendered-content safety, data hygiene | 10 | The draft commit on this branch still names the product; vendor and workplace hints; a spend figure; a private-memory citation; raw PR text into a prompt |
| Enumerated claims | 16 | The goal's copied figures; stale run-start and track counts; a closed shell-class list; backend and lens counts; research figures uncited |
| Performance, concurrency, error handling | n/a | Spec class: no execution path |

**Kickoff check items.** The altitude check fired. D-1 exists and the
Goal cites it, and every rung now has a task: this repository's
convergence switch (Task 10) is the local-value rung, and the mid-flow
signal is pinned in Sources. The ship-gate check found four
out-of-band items named only in prose. The lens-list copy and the review
commands' contract adoption are now gated Deferred entries. The operator's
backend runs park Task 8, and a regressed class becomes a gated follow-up.
The self-critique sweep added a missing human-gates precondition on
Task 4, the grammar check's owner, and the runtime wiring for the output
contract and the miss ledger.

**Totals.** 176 raw findings (the table's 162 plus the check items' 14), clustered into 31 root causes. Each was
checked against the files before disposition, with the other bundles'
task state checked through the status render.

**Operator decisions at sign-off.**

- The branch is re-cut from main before the push: the old local branch is
  renamed aside untouched and the clean files land as new commits. Chosen
  over pushing the draft commit, which names the product, and over leaving
  the fix to the operator.
- The replay's catch rule: same file, within 10 lines. Chosen over
  category matching, whose labels were about one in five wrong, and over a
  model judge.
- The closeout: at least 15 bot-reviewed PRs after Tasks 1 to 12 land, a
  bar fixed now (finding rate and cost per unit both below baseline), and a
  missed bar recorded as a miss and a gated follow-up rather than holding
  Done. The operator asked which option is better long-term; this one
  keeps the verdict fixed in advance without stranding the spec.
- All three follow-ups tracked (the lens-list copy, the review commands'
  contract adoption, and the operator's backend runs).
- This repository's convergence moves from `/self-review` to `/polish`, so
  the blind pass runs here and the closeout measures it.

**Dispositions.** Every finding is applied except those below, each
declined with its reason.

- **Precondition on prose-disposition's instantiation task.** Declined:
  the status render shows it merged, and D-10 now scopes the rule to
  unmerged tasks.
- **Precondition on instruction-headroom's gate-wiring diet.** Declined:
  merged, per the status render.
- **Unifying "loop ledger" and "decline ledger".** Declined: "the loop's
  decline ledger" names the ledger's declined entries, a part, not a
  second store.
- **Dropping "ignored command-substitution status" from the shell
  classes.** Declined: an observation grounds it, and Task 11 carries the
  classes as its own list, with REQ-F1.1 now a decided rule rather than
  an enumeration.
- **Naming the public dotfiles repository.** Declined, per the earlier
  operator decision.
- **Research-seed figures kept as measured.** "Nine lenses" and "a tenth
  lens" are facts at the time of measurement, in a note the spec cites
  rather than copies.

### Pre-flip verification

- **Stale-reference sweep.** The lens pass minted REQ-E1.7 and re-scoped
  REQ-B1.1, C1.1, C1.3, D1.1, D1.2, E1.1, E1.2, E1.4 to E1.6, F1.1, F1.3,
  F1.4, G1.2, G1.3, and H1.2 to H1.4. A sweep over the bundle and brief
  sections 2 to 7 reconciled the brief's regeneration claim, the seeded
  dismissal, the hygiene row, section 6's edges and critical path, section
  7's rows and gap-check text, and a remaining lens count in `test-spec.md`.
- **Lint.** `mise run lint:md` passes over the brief and the four spec
  files.
- **Recorded claims, re-derived.** The design ledger rows match the
  design's D-IDs, and `test-spec.md` headings match `requirements.md`'s REQ
  list (the validator's coverage check agrees). The mid-walk lens totals
  sum to the recorded raw count. The sign-off totals are this section's
  own table sums.
- **Enumeration cross-check.** Enumerations in the anchored files were
  verified against their surface or converted to decided rules: the goal
  cites the seed, REQ-F1.1 and REQ-F1.4 state rules, D-1 and D-6 drop
  their closed lists, and the research figures cite their seed sections.
  The remaining counts (the seven reviewer basics, the four rules of
  REQ-E1.4, the three docs of Task 4, the four buckets) match the list
  beside them or the live doctrine.

### Sign-off record

Signed off 2026-09-24 by the operator after the approval summary: all four
spec files flipped Draft to Ready with `Last reviewed:` 2026-09-24, and the
validator re-run at Ready severity with 0 errors and 0 warnings.

Class: meaning
Lens-pass: the full-bundle lens review recorded in this section (spec lens
set, five-reviewer fan-out, every finding dispositioned)
Anchor: `11f7348f27c992f03f67d01e73a4b272f94573e1` — computed as
`scripts/spec-anchor.sh specs/review-effectiveness`
