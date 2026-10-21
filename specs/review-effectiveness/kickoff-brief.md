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

### Execution notes: Task 1 (2026-10-11)

Recorded by the executing task after sign-off; no row above is changed.

- **The research seed's datasets were gone.** They lived only in the
  drafting session's scratchpad. Corpus v1 was rebuilt from this public
  repository's PR review threads (`gh api graphql`) by the refresh script,
  with `--label-reasons` standing in for the seed's labels: the category,
  class, and paraphrased gist come from a model annotator, recorded as label
  source `model`. This is the label noise row 16 anticipates, not a new risk;
  the catch rule still reads only file and line.
- **Pull requests from before the history rewrite are unreplayable.** Their
  commits share no history with today's main, so a replay has no base to
  diff against; the refresh marks them unreplayable and the replay excludes
  them.
- **`declined` and `lintable` rows are scarce** (row 17): the declined-log
  match found few rows, so a targeted replay of either class is a small
  sample. The zero-row refusal still applies.
- **A refresh carries labels forward.** A row the previous version already
  holds (same PR, path, line, and commit) keeps its category, gist, class, and
  dismissal; a ledger entry for its PR and path that now exists replaces only
  the class. A drained ledger therefore never relabels it `other`; the `other` fallback applies to
  findings new to the refresh with no ledger entry.
- **The baseline reviewer walks the lenses inline** (operator decision,
  2026-10-12). Task 1's deliverable and D-7 say "its lens fan-out"; the
  default reviewer walks every lens in one session instead, because that is
  how most measured nested convergence runs walked them and it costs about a
  ninth of the tokens. A reviewer change that fans out is replayed through its
  own reviewer command against the same corpus.
- **Replay cost, measured** (row 6): one row of today's pass costs from a
  few hundred thousand to over a million tokens and a minute or several; the
  baseline result records the run's total.

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

## 9. Amendment log

### 2026-10-20 — Delta re-walkthrough: the external review audit extension

#### Header

- **Mode:** delta re-walkthrough of an Active bundle (status render:
  Active, derived); the anchor recomputed at pre-flight no longer matched
  the sign-off record above.
- **Delta scope (operator-confirmed):** both extension commits on the spec
  branch, walked and signed as one delta: the five audit classes, the
  second corpus version, and standing rules, plus the expression-only
  respelling of every task's `Dependencies:` field as bare ids. The delta
  is the spec files' diff from the merge base with main to
  `46a32239`; its contents are the two 2026-10-19 Changelog entries in
  `requirements.md`.
- **Spec commit at walkthrough start:** `46a32239`
- **Walkthrough dates:** 2026-10-20 to 2026-10-21
- **Validator outcome (pre-flight):** `scripts/spec-validate.sh` — 0
  errors, 0 warnings
- **Config:** unchanged from section 1
- **Decision/transcript log:** no harness-provided log path; the mirror is
  skipped, as in section 1
- **Independent cold read:** `/spec-walkthrough specs/review-effectiveness`
  offered as an optional complement

#### Goal & glossary (delta)

**Restatement.** The extension keeps the bundle's purpose (fewer defects
reaching external review, cheaper convergence) and widens what "defects
the passes miss" covers. An audit of the external review threads posted
after the first corpus cut found classes the signed scope does not reach:
tests that pass only on the author's host, guards a different spelling
walks past, ordered procedures whose steps run out of order, observation
fragments that duplicate an earlier one or misquote their source, and twin
sites left unswept (the last already the sibling sweep's). Each new class
gets a review rule and, where the shape is mechanical, a guard. Standing
rules add a way for an operator's recorded decisions to be applied at
triage instead of re-litigated every pass. It rules out the hosted
reviewer's own request and vendor tuning (the operator's review-skills
bundle) and where an adopter's rules file comes from. It assumes the first
corpus version and the handoff builder have landed (Tasks 1 and 6, both
merged per the status render).

**Implicit terms resolved.**

- *Standing rule*: one entry of the operator-curated rules file (REQ-J1.1);
  distinct from the loop's decline ledger, which is per-loop and minted by
  the loop.
- *Guard-bypass sweep*: the Security lens's conditioned walk of evasion
  spellings against a guard's matching surface (REQ-B1.9).
- *Procedure tracing*: walking ordered prose as control flow (REQ-B1.10).
- *Clearing library*: the new `tests/lib/hermetic-env.sh`, the single list
  of configuration and root variables a suite clears or pins (D-17).
- *Perturbed run*: the extra CI suite run under decoy variables, an odd
  temporary root, a non-C locale, a non-UTC timezone, and root (REQ-F1.6).
- *Recurrence*: a fragment that deliberately repeats an earlier one,
  linked by `--recurrence <uid>` (REQ-I1.1).

**Edit applied.** The Goal gains one sentence naming the audit's further
classes and standing rules (operator decision). Classed as a consistency
gap-fill (the scope list already carried the items), so no mid-walk lens
ran; the terminal delta lens covers it.

Signed off: 2026-10-20

#### Requirements walkthrough (delta)

**Per-group outcomes.**

- **Discovery (REQ-B1.9 to B1.11).** The guard-bypass sweep runs only when
  a change touches a guard and must list the spellings it tried; procedure
  tracing joins the spec lens set with four finding shapes; the Tests lens
  gains the host-dependence rule. Confirmed as written.
- **Guards (REQ-F1.5 to F1.8).** A static hermeticity guard for three named
  shapes, a perturbed CI run for the unnamed ones, a usage-header check of
  script invocations in prose, and two guard-authoring rules in the
  catalog. Confirmed as written.
- **Measurement (REQ-H1.5).** A second corpus version from the threads
  since the first cut, Task 13 replaying against it. Confirmed; the task
  graph section takes up which tasks the replay and closeout measure.
- **Observation hygiene (REQ-I).** Amended: duplicate refusal no longer
  matches on the slug (below). The fragment review before commit confirmed.
- **Standing rules (REQ-J).** Amended: the blind pass never reads the
  rules (below). File format, knob, triage semantics and exporter
  confirmed.

**Decisions taken.**

1. *Inconsistency halt, resolved by spec edit.* REQ-I1.1's slug match
   contradicted REQ-E1.5: every miss-ledger row is recorded under the
   shared `review-miss` slug, and every skill's drift check under
   `skill-drift`, so the second of either would be refused. Readings
   offered: match on content only; keep the slug match with an exemption
   list; or record an override. Operator chose content only: the duplicate
   the audit saw carried a new slug, which a slug key misses anyway.
2. *The blind pass never reads standing rules.* As written, REQ-J1.2 handed
   the rules to the blind pass as context, which REQ-E1.1 and REQ-C1.3 keep
   free of earlier declines so they cannot anchor it. Operator chose to
   omit them from the blind pass's bundle; triage still applies them to
   blind findings, so the cost is audit rows, not operator work.

**Consolidated spec edits (this section).**

- `requirements.md` REQ-I1.1, `design.md` D-20, `tasks.md` Task 15.1,
  `test-spec.md` REQ-I1.1: the slug is no longer a match key; the
  shared-slug case is a written-not-refused test.
- `requirements.md` REQ-J1.2, `design.md` D-21, `tasks.md` Task 6.1,
  `test-spec.md` REQ-J1.2: the blind pass's bundle omits the rules member,
  with a scenario for it.

**Mid-walk lens (both edits, inline: two narrow deltas).** One note,
accepted: with the slug key gone, a duplicate observation that names no
test path is never refused; the audit's duplicate class was a repeated
test failure, and the fragment review before commit (REQ-I1.2) still reads
for duplication. No other finding: the omitted rules member leaves REQ-B1.1's
bundle contents for ordinary passes unchanged, and REQ-J1.3's triage applies
to blind findings as written.

Signed off: 2026-10-21

#### Design walkthrough (delta)

Ledger for the delta's decisions (the D-1 to D-16 ledger in section 4
stands unchanged):

- **D-17** (hermeticity: lens rule, static guard, perturbed CI run):
  confirmed.
- **D-18** (guard-bypass sub-lens; authoring rules in the guard catalog):
  confirmed.
- **D-19** (procedure tracing in the spec set; usage-header guard):
  confirmed.
- **D-20** (duplicate refusal in the recorder; fragment review before
  commit): amended, the slug dropped as a match key (requirements decision
  1).
- **D-21** (standing rules): amended, the blind pass's bundle omits the
  rules (requirements decision 2).

No design decision contradicts a walked requirement.

Signed off: 2026-10-21

#### Verification approach (delta)

- **Coverage mix.** Every delta REQ has a `test-spec.md` entry (validator
  coverage check). The mechanical guards (REQ-F1.5, F1.7), the recorder
  (REQ-I1.1) and the exporter (REQ-J1.4) are `[test]`; the doctrine rules
  are `[design-level]`, most with a Gherkin scenario; the `[manual]` halves
  are the entries `test-spec.md` tags so.
- **Ownership.** `[test]` entries run under `mise run check` in this
  repository's CI; the perturbed run is its own CI job (REQ-F1.6); the
  `[manual]` halves (the perturbed job's verdict set and its one-off
  can-fail proof, the corpus refresh run) are read at the task PR's review
  from its body; Gherkin scenarios are recorded in the owning task's PR
  body.
- **Dead paths found and fixed.** The Gherkin scenarios for REQ-B1.9 to
  B1.11 (Task 3.1) and REQ-J1.2, J1.3 (Task 6.1) had no `Done when:` that
  required recording them; both tasks now carry the bundle's standing
  "every Gherkin scenario ... recorded in the PR body" condition
  (consistency edit, resolved and reported). The sign-off lens pass found
  the same gap on Task 15.1 (REQ-I1.2) and closed it there.

Signed off: 2026-10-21

#### Task graph (delta)

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
the status render reads the same lines, now spelled as bare ids).

- **New edges.** 5.1 after 5; 1.1 after 1 and 5.1; 3.1 after 3 and 1.1;
  6.1 after 6 and 8; 11.2 after 11.1; 15.1 after 2; 11.1 and 12.1 have
  none. Task 13 now also waits for 1.1, 3.1, 6.1 and 15.1, and Task 14 for
  11.1, 11.2 and 12.1 (operator decision: the final evaluation covers the
  extension). The edges after 5.1, 1.1 and 8 and the Task 11.2 split came
  from the sign-off lens pass below.
- **Parallelism.** 5.1, 11.1, 12.1 and 15.1 are dispatchable once this
  delta merges (their dependencies are merged, per the status render);
  1.1 follows 5.1 and parks for the operator's refresh run; 3.1 follows 3
  and 1.1; 6.1 follows the blind skill (Task 8).
- **Critical path.** Unchanged: the gate, loop and wiring chain through
  Tasks 3, 7, 9, 13 and 14 (effort per `tasks.md`); every extension task
  joins it with slack before Task 13.
- **Deliberate non-edges.** 6.1 does not wait for 3, and 15.1 does not
  wait for 9 or 10, although each pair edits the same doctrine or skill
  files: the overlap is a rebase, not an ordering need, and REQ-G1.3's
  word-neutral rule binds each landing on its own. 3.1 does not wait for
  6.1: its rules do not read standing rules, and the lens briefs it edits
  are written by the skills' fan-out, not by either task's builder change.

**Spec edits (this section).** `requirements.md`: REQ-H1.4 marked
superseded by the new REQ-H1.6, whose window opens after every task the
closeout depends on, directly or transitively, has landed (the old text's
"Tasks 1 to 12" no longer reached the extension and read ambiguously
beside the point-one tasks). `tasks.md`: Task 13 and Task 14 dependencies
widened, Task 14's window reworded and cited to REQ-H1.6. `test-spec.md`:
REQ-H1.6 entry added; REQ-H1.4's entry notes the supersession.

Signed off: 2026-10-21

#### Risk register (delta)

Rows continue section 7's numbering.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 21 | Task 12.1's header work is larger than its estimate: the check needs a stated header grammar, and the headers vary in shape; at this walk most scripts carried a `# Usage` header, and about a quarter of the scripts skill and doctrine prose names carried none, some of them sourced libraries the check skips (sign-off lens pass measurement) | The check's first run lists the invoked scripts the grammar cannot parse; signal: that list at task start. Split the normalisation into its own task through the amendment ritual if it outgrows the estimate |
| 22 | The perturbed run (Task 11.1) surfaces many existing failures at once, root and a decoy root variable being new to every suite | Exclusions are allowed only by name with a reason; signal: the first perturbed run's failure count, recorded in the PR body |
| 23 | A wrong standing rule disposes of a real finding at triage (domain 17) | The finding stays in the audit record with the rule id; new evidence routes to Needs sign-off (REQ-J1.3); the blind pass never reads the rules (REQ-J1.2), so a rule-covered finding still reaches triage from an unanchored reviewer |
| 24 | Two fleet workers record the same duplicate observation at the same moment and both pass the check (domain 7) | Accepted: the cost is one duplicate fragment, and the fragment review before commit (REQ-I1.2) reads for duplication |
| 25 | Tasks 6.1 and 15.1 add prose to `/self-review` and `/polish` under a saturated instruction budget, alongside Tasks 9 and 10 | REQ-G1.3's word-neutral rule and the closure charge (REQ-G1.2) refuse growth; signal: `check:instructions` on each task PR |
| 26 | Task 1.1's annotator and refresh are operator-local, so a dispatched worker cannot finish it | The task parks as Awaiting input for the operator's run, as Task 1's refresh did; signal: the dispatch's first park |
| 27 | Task 12.1 builds a second reader of script invocations in skill and doctrine prose beside `scripts/check-script-invocation.sh` (domain 19) | Resolved at the sign-off lens pass: Task 12.1 extends that script (D-19) |
| 28 | The perturbed run as root (Task 11.2) needs a toolchain and home that resolve under root, which the existing jobs avoid | Task 11.2 states how root is reached; signal: the job's first run on the task PR |
| 29 | A standing rule edited on the branch under review would judge that branch (domain 5) | Rules are read from the base ref, and an edit to the rules file is a Needs-sign-off finding (REQ-J1.2) |

**Decision-domain gap check** (catalog resolved through
`scripts/resolve-catalog.sh decision-domains`, walked against the delta,
then completed by the sign-off lens pass): API surface (the rules file's
JSON form, version key, repository form and export hash, REQ-J1.1 and
REQ-J1.4; the recorder's refusal and recurrence contract, REQ-I1.1),
secrets and configuration (the `review_rules_file` knob, its layer, path
base and missing-file refusal, REQ-J1.1), authorization (rules read from
the base ref; hard-disqualifier zones override a rule, REQ-J1.2 and
REQ-J1.3), versioning (the rules file and corpus `v2`), IP posture
(paraphrased corpus rows and a product-free export), LLM output quality
(the replay gate over `v2`, Task 6.1's replay, the new miss tokens,
REQ-H1.5 and REQ-H1.7), dependency adoption (none: the rules file is JSON
read with the `jq` the repository already requires), and existing-seam
reuse (the clearing library absorbs the existing pinning seams, D-17; the
usage check extends `check-script-invocation.sh`, D-19; the rules file
weighed against the catalog overlay seam, D-21) are decided. Concurrency
(row 24) is an accepted risk. No other catalogued domain is touched.

Signed off: 2026-10-21

#### Sign-off lens pass (delta-scoped)

Class (operator): meaning. Scope: the spec delta from the merge base with
main, with this entry's walk edits, and this entry itself; spec lens set.
Fan-out: five read-only reviewers on Opus, four taking two or three lenses
each and the fifth running the kickoff check items and the self-critique.

| Lens (spec class) | Findings | Notes |
| --- | --- | --- |
| Contract correctness, internal consistency | 15 | Runner pinning made the decoys vacuous; the recurrence marker broke the miss grammar; no blind pass to attach the rules omission to; no miss class for the new rules; a Done-when nothing could meet |
| Ambiguity, interpretation forks | 12 | Duplicate keys and "scope"; the guard trigger; where the spellings go; rule dispositions vs the categorization; repository form; product-name handling; the knob's path base; the baseline's configuration |
| Citation and coverage integrity | 7 | finding-categorization cited for rules it lacks; citation labels with no Sources entry; coverage map vs task citations; the design's reuse claim |
| Requirement/test-spec pairing | 5 | The perturbed run's test covered two of five perturbations; Task 13 never bound to the second corpus version; test cases no task delivered |
| Dead verification paths | 3 | REQ-I1.2's scenario unrecorded; the refresh run's records; a lens brief no artifact emits |
| Testability | 3 | A byte-identical bundle against a per-build id; an undefined replay class set; "the plain job" across three shards |
| Cross-file consistency | 25 | Existing seams for the clearing list and the prose invocation reader; sourced libraries counted as invocations; the perturbed job not gating; the refresh script's real options; the audit's dates; supersession adjacency; fragment commits per iteration |
| Documentation and glossary drift | 9 | Bare "bundle"; "triage"; "hosted reviewer"; "class" vs audit category; "scope" twice; the canonical lens name |
| Decision-domain gaps | 11 | The rules surface (format, hash, repository form, knob layer); the recorder's refusal contract; Task 6.1's model judgment ungated; a rule over a hard-disqualifier zone; rules editable by the branch they judge |
| Rendered-content safety, data hygiene | 4 | Rule text and fragment text into prompts as data; bypass inputs run against a live hook. No product names, personal paths or private-repo detail found |
| Enumerated claims | 8 | "nine-lens", "tenth lens", "four finding shapes", "the three rules", "every hosted reviewer"; brief lists that went stale within the walk |
| Performance, concurrency, error handling | n/a | Spec class: no execution path |

**Kickoff check items** (23 findings). *Altitude:* triggered (the audit's
pinned claim in Sources); D-1 exists and the Goal cites it, but D-1 did
not place the extension, and two of its rules (standing-rules routing,
the fragment review) landed only in skills. *Ship-gate:* the rule
proposal step lived only in a rejected alternative; Task 3.1's lens-brief
fallback was a PR-body note; risk row 27 was deferred to this pass; the
dotfiles routing records exist but are local to that repository; the
lens-list mirror entry's premise is gone. *Self-critique:* Task 11.1's
effort, the perturbed run's cost bound, Task 1.1's operator-only run,
the knob's name, the hash, and the items above from other lenses.

**Totals.** 125 raw findings (the table's 102 plus the check items' 23),
clustered into the root causes listed below. Each was checked against the
files and against main by its reviewer, with quotes; the load-bearing ones
(the runner's sentinel arms, the miss grammar's first-line check, the
handoff manifest's build id, the `check` job's needs, the refresh
script's options, the dates of the first corpus version) were re-checked
here before disposition.

**Operator decision at sign-off.** The audit's categories get their own
miss-reason tokens (new REQ-H1.7, D-22, Task 5.1), chosen over mapping them
to existing tokens and over exempting Task 3.1 from the replay gate,
because the goal asks for each improvement measured.

**Dispositions by root cause.** Applied as spec edits:

1. The recurrence marker sits after a kind prefix; miss-ledger fragments
   are exempt from duplicate refusal (REQ-I1.1, D-20, Task 15.1).
2. Duplicate keys defined (scope token, test path, quoted string), the
   recurrence uid bound to the matched fragment, and a refused caller's
   duty stated (REQ-I1.1, D-20).
3. The perturbed run switches the runner's pinning off so decoys reach the
   suites (REQ-F1.6, D-17, Task 11.2).
4. The perturbed run is sharded, gating, skip-tolerant by name, root
   mechanics stated, its test covering every perturbation; split into
   Task 11.2 (REQ-F1.6, Tasks 11.1, 11.2, 14).
5. The unsupported second-shell claim and its citation dropped (D-17,
   REQ-F1.6).
6. The clearing library absorbs the existing pinning helper and scrub
   lists (D-17, Task 11.1).
7. The usage check extends `scripts/check-script-invocation.sh`; an
   invocation is a shebanged script in command position; the header
   grammar is stated in the catalog entry (REQ-F1.7, D-19, Task 12.1).
8. REQ-F1.5's third shape aligned with D-17.
9. REQ-H1.5 restated against the refresh script's real behaviour (full
   refresh, this repository only, annotator labelling, the pre-bundle
   baseline configuration, later gates on `v2`); Task 1.1's records and
   operator park; Task 13 bound to `v2`.
10. The blind pass's rules-free handoff bundle given a mechanism (a
    `--rules` builder input), Task 6.1 sequenced after the blind skill,
    and the never-sees list extended (REQ-J1.2, D-21, Task 6.1).
11. Lens briefs named where the skills' fan-out writes them (Tasks 3.1,
    6.1).
12. Task 6.1's doctrine homes named; satisfied or duplicate `Done when:`
    preconditions dropped (Tasks 3.1, 6.1, 15.1).
13. The unset-knob check compares the builder's output to a golden file,
    the build line excepted (Task 6.1, REQ-J1.1 entry).
14. Task 6.1 takes a targeted replay with a seeded rules file (REQ-H1.3).
15. The finding-categorization citation corrected; new-evidence routing
    attributed to REQ-C1.3 and this walk (Sources, REQ-J1.3, D-21).
16. The rules surface decided: JSON, `review_rules_file`, its layer and
    path base, a missing file refused, `<owner>/<name>` repositories, rule
    ids never reused, SHA-256 over the block headed by the version key
    (REQ-J1.1, REQ-J1.4, D-21).
17. Rule dispositions mapped onto the categorization (REQ-J1.1).
18. Rules read from the base ref, an edit to the rules file a
    Needs-sign-off finding, rule and fragment text presented as quoted
    data (REQ-J1.2, REQ-I1.2, design Security).
19. A hard-disqualifier pause holds whatever a rule decides (REQ-J1.3).
20. The exporter's product-name screen uses the corpus screen's
    machine-local list and refuses without it (REQ-J1.4).
21. Rule proposal stated as the adopter's overlay; the catalog overlay
    seam weighed and rejected (D-21).
22. The bypass sweep's trigger excludes argument validation, its inputs go
    to the matcher or harness, and its spellings sit in the row's Notes
    (REQ-B1.9, D-18).
23. The fragment review runs wherever fragments are committed, adds a
    duplication check, and is stated in the accumulator-taxonomy doctrine
    (REQ-I1.2, D-20, Task 15.1).
24. D-1 places the extension on the altitude ladder.
25. Coverage map and citations reconciled (REQ-G1.3, H1.2, H1.3, H1.4,
    H1.6 entries; Sources gains `kickoff §9` and drops an unmatched
    label; the audit's dates corrected).
26. Changelog entry, `Last reviewed:`, and REQ-H1.6's adjacency and
    supersession marker.
27. Glossary: "handoff bundle", "routing and disposition", "the bot
    reviewer", "standing-rules file", audit category vs corpus class, the
    canonical Tests / verification lens name.
28. Enumerations converted to rules or citations (D-17, D-18, D-21, Task
    3.1, test-spec).
29. The design's domain list now cites this entry's gap check; the
    Security and CI-cost notes updated.
30. The guard-authoring rules cited from the permission-matcher model doc
    (D-18, Task 3.1).
31. This entry's own stale lines corrected (verification list, Task 15.1's
    dead path, the task-graph edges, risk rows 21 and 27; rows 28 and 29
    added).

Declined, with reasons (root causes 32 and 33):

1. **Retiring the lens-list mirror Deferred entry.** Its premise (a copy
    of the lens list in the operator's global instructions) appears gone,
    but the entry is human-owned tracked state; its gate drain surfaces it
    to the operator, who closes it there.
2. **Pushing the dotfiles routing records.** The review-skills spec
    bundle's Tasks 11 and 12 exist on that repository's local spec
    branch; publishing it is the operator's act in that repository, out of
    this bundle's scope. Sources now names the tasks.

#### Pre-flip verification (delta)

- **Stale-reference sweep.** The walk and the lens pass minted REQ-H1.6,
  REQ-H1.7, D-22, Tasks 5.1 and 11.2, and re-scoped REQ-B1.9, B1.11, F1.5
  to F1.8, H1.5, I1.1, I1.2 and J1.1 to J1.4. A sweep of the four files
  and this entry for the changed terms and IDs (triage, the hosted
  reviewer, the rule ledger, the lens counts, "byte-identical", the
  builder's lens brief, the second reader, Task 11.1's old scope)
  reconciled the stragglers; the 2026-10-19 Changelog lines stay as
  history.
- **Lint.** `markdownlint-cli2` over the four spec files and this brief:
  0 errors.
- **Validator.** `scripts/spec-validate.sh`: 0 errors, 0 warnings after
  the edits.
- **Recorded claims, re-derived.** The lens table's rows sum to its stated
  figure and, with the check items, to the raw total; the root-cause list
  is this section's own numbered list. Counts left in the delta's anchored
  prose (the three hermeticity shapes, the two guard-authoring rules, the
  three ways D-17 catches the class, its two libraries) each match the
  list beside them.
- **Enumeration cross-check.** The remaining counts of a surface outside
  the bundle (the code-lens count, the canonical-lens ordinal, the
  reviewers a block serves) were converted to rules by root cause 28.

#### Sign-off record (amendment)

Signed off 2026-10-21 by the operator after the approval summary: a delta
re-walkthrough of an Active bundle, so no status flip; `Last reviewed:`
2026-10-21 on all four spec files, and the validator re-run at Ready
severity with 0 errors and 0 warnings.

Class: meaning
Lens-pass: the delta-scoped lens review recorded in this entry (spec lens
set, five-reviewer fan-out, every finding dispositioned)
Anchor: `fb6568f6f13ce151faf6d76077c92c2e94b5462b` — computed as
`scripts/spec-anchor.sh specs/review-effectiveness`
