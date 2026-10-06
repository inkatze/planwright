# Review effectiveness — Requirements

**Status:** Ready
**Last reviewed:** 2026-09-24
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's convergence passes (`/self-review`, `/polish`, and the
convergence phase of `/execute-task`) declare a branch clean, and the bot
reviewer then finds real defects on most reviewed PRs, driving extra bot
rounds and fix commits (research seed §1). The same convergence costs about
half of a unit's tokens, most of it the parent session re-reading its own
implementation transcript. The research
seed measured both and found separate causes: misses concentrate in runtime
behaviour that needs a trace, sibling sites left unswept after a fix,
claims that disagree with the code they describe, and findings wrongly
pruned or declined; cost concentrates in the accumulated parent context and
in re-fanning every lens over the whole branch on every pass.

This bundle raises the recall of the convergence passes on those classes
and cuts the cost of each pass, each measured against the baselines the
research seed records, so a unit reaches its PR with fewer
post-convergence findings, fewer external review rounds, and fewer tokens.
It is a doctrine change as much as a skill change: the reviewer-basics
gate, the blind review, and the sibling sweep are rules about how a review
must think, the blind step and the miss ledger are core seams, and the
scripts are the mechanisms filling them (D-1, the altitude record).

## Scope

### In scope

- Reviewer basics run as a gate before the lens fan-out: acceptance
  coverage against the task contract, the would-be PR description against
  the diff, tests that exercise the change, copies of a changed claim,
  callers and consumers of a changed contract, a scope fence, and
  re-verification of earlier iterations' fixes.
- Discovery context and lenses: a handoff bundle assembled once and shared
  by every lens, claim-versus-code executed by reading both sides, a
  sibling sweep as both a lens and a post-fix step, root-cause clustering,
  delta-scoped re-discovery, visible lens failure, artifact-class lens
  selection instantiated in the skills, and an independent self-critique.
- Validation: whole-system reproduction as the first pass on executable
  surfaces, a declared bi-directional adversarial pass, resurrection of
  declined findings across iterations, evidence that names its producing
  process, and proportional validation for tool-cited findings.
- Loop economics: a bounded fresh context for every review pass, doctrine
  and brief resolved once per loop, the full suite once per iteration with
  a diff-scoped check per fix, the audit record written as deltas, the loop
  bounds restated around the blind pass, and resume after a killed loop.
- Blind review: the concept defined in doctrine on the context and
  generator axes, a blind pass as the convergence's confirming pass
  realized through a handoff bundle and a fresh agent on every backend,
  generator independence when an external backend is attached, the output
  contract planwright requires of any external review step it consumes, a
  miss ledger fed by external findings, and convergence evidence in the PR
  body.
- Mechanical guards for the recurring shell defect classes, emitter output
  linting, a count-versus-list guard, and a test-vacuity guard, entered in
  the guard catalog.
- The review skills' instruction diet: run-start docs reclassified to
  point-of-use within instruction-headroom's floors, the nested chain
  charged as one closure, and word-neutral landing of every new rule.
- Measurement: the baselines, a committed backtest corpus of fixed external
  findings with a replay harness and a refresh script, a tokens-per-pass
  metric, and a closeout window that judges Done.

### Out of scope

- Editing the operator's dotfiles review commands (the external review
  loops); their adoption of this bundle's external step output contract is
  a gated Deferred entry in `tasks.md`.
- Step attachment mechanics and the point vocabulary (custom-steps); this
  bundle attaches to the convergence and post-pr points it defines and
  never touches the retired review-sequence knob.
- The ready-flip and merge policies (human-gates) and the never-auto-merge
  invariant.
- Main synchronization inside the loop (merge-currency-guard).
- Model and effort tier resolution (model-allocation); the blind pass
  resolves its tier through that resolver and adds no selection logic.
- Prose-finding disposition, prose batching, and the four-bucket taxonomy
  (prose-disposition, bootstrap); no fifth bucket is minted.
- The CI gate's false-red rate under load and unit sizing; both stay
  observation backlog.
- Any detail of the private reviewer beyond generic design lessons; it is
  never named in a committed artifact.
- Context engineering of the implementation phase itself; only the review
  pass's context is bounded here.

## REQ-A — Reviewer basics

- **REQ-A1.1** Every convergence pass SHALL run a reviewer-basics gate
  before the lens fan-out, and a gate finding SHALL halt the pass until it
  is dispositioned; the lenses review only a change the gate has passed.
  *(Cites: D-2, the research seed (Sources).)*
- **REQ-A1.2** The gate SHALL trace every `Done when:` condition, every
  deliverable, and every REQ the unit cites to at least one diff hunk, or
  report the item as not covered; an uncovered item is a finding, never a
  note.
  *(Cites: D-2, the invocation (Sources).)*
- **REQ-A1.3** The gate SHALL check the would-be PR title and body (the
  summary and every claim about what changed) against the diff before the
  PR opens; a claim the diff contradicts is a finding.
  *(Cites: D-2, the research seed (Sources).)*
- **REQ-A1.4** The gate SHALL judge, by reading, that each behaviour the
  change introduces has a test that fails without it, and SHALL flag an
  assertion with no positive control or a status read from a command
  other than the one under test.
  *(Cites: D-2, obs:af6048cb, obs:e9f5cc37, obs:e25c7458, kickoff §3 REQ-A
  (2026-09-24).)*
- **REQ-A1.5** When a behaviour, default, count, or contract changes, the
  gate SHALL sweep every other place that states it (documentation,
  headers, usage text, the options reference, doctrine index rows) and
  flag each stale copy.
  *(Cites: D-2, obs:587d7d7b, the research seed (Sources).)*
- **REQ-A1.6** When a signature, output format, or exit-code contract
  changes, the gate SHALL check every caller and consumer of it and flag
  each one not updated.
  *(Cites: D-2, D-3.)*
- **REQ-A1.7** The gate SHALL flag, as a finding, every file the change
  touches outside the unit's deliverables, and after any fix iteration
  SHALL re-verify that each earlier finding's fix still holds, by re-running
  what validated it (the recorded reproduction against a fresh isolated
  copy (REQ-C1.1) of the current head, or else the targeted test or tool
  rule).
  *(Cites: D-2, D-14, obs:a0add2f0, kickoff §3 REQ-A (2026-09-24), kickoff §8 (2026-09-24).)*

## REQ-B — Discovery context and lenses

- **REQ-B1.1** The coordinator SHALL assemble one handoff bundle per pass —
  the diff, every changed file whole, the callers of every changed symbol,
  the unit's task contract, the would-be PR title and body, and the tooling
  output — and every lens agent SHALL receive that bundle rather than
  fetching a diff slice itself.
  *(Cites: D-3, the research seed (Sources), the dotfiles code-review
  command (Sources), kickoff §8 (2026-09-24).)*
- **REQ-B1.2** A claim-versus-code finding SHALL be produced by reading
  both the claim and the code it describes, and SHALL cite both sides; the
  Documentation lens's falsified-prose class is executed this way, never
  from the diff slice alone.
  *(Cites: D-3, the research seed (Sources).)*
- **REQ-B1.3** The lens set SHALL include a sibling sweep that, for every
  property the diff introduces, asks where else that property should hold (the
  same file, sibling scripts, parallel branches) and flags each twin site
  lacking it; and every applied fix SHALL trigger the same sweep over the
  property the fix corrected.
  *(Cites: D-4, obs:749d937c, obs:15a7fdcb, obs:587d7d7b.)*
- **REQ-B1.4** Merged findings SHALL be clustered by root cause before
  disposition, disposition SHALL be recorded per cluster, and the audit
  record SHALL report both the raw and the clustered counts.
  *(Cites: D-3, obs:19ec8cd4, obs:c10c0a24.)*
- **REQ-B1.5** After the first pass of a loop, each later pass except a
  loop's first blind pass (REQ-E1.2) SHALL direct
  the lenses at the delta since the previous pass's head plus the files a
  fix touched, over the whole-branch handoff for context, with REQ-A1.7's
  re-verification covering the rest of the branch.
  *(Cites: D-14, the research seed (Sources).)*
- **REQ-B1.6** A lens agent that dies, times out (past the execution
  backend's own agent timeout), or returns nothing SHALL be retried once
  and, on a second failure, run inline from the handoff bundle; its
  lens-coverage row SHALL record each attempt, its value being the first
  successful attempt's result or `failed` when none succeeded, never
  `none`; an inline run SHALL be recorded as not context-independent
  (REQ-D1.1); and a row still `failed` SHALL keep the pass from presenting
  as clean and SHALL end the enclosing convergence early with the failure
  reported, never running to the cap.
  *(Cites: D-3, the fan-out partial-failure line (Sources), kickoff §3 REQ-B (2026-09-24).)*
- **REQ-B1.7** `/self-review` and `/polish` SHALL select the lens set by
  the artifact class of the change under review, as the artifact-lenses
  doctrine already requires, and SHALL name the selection in the audit
  record.
  *(Cites: D-3, obs:3672d83d, obs:38f3809f.)*
- **REQ-B1.8** The self-critique pass over the merged finding list SHALL
  run in an agent that did not produce the list, with the handoff bundle
  and the list as its only inputs.
  *(Cites: D-3.)*

## REQ-C — Validation

- **REQ-C1.1** Outside REQ-C1.5's carve-out, on an executable surface, the
  first validation pass SHALL reproduce the finding through the real
  surface (the command invoked with the triggering input, its exit code,
  output, and side effects observed), run in an isolated copy: a fixture
  tree or a fresh clone in a temporary directory, with the home directory
  and the machine-local state home redirected into it for every command
  the pass executes, no push remote, removed on exit; never the live
  worktree, the remote, or the machine-local state home. The reviewing
  session keeps its own home and credentials, and no credential is copied
  into the clone. A targeted unit test is the first pass only where no
  executable surface exists or none can be copied safely, and the evidence
  line SHALL name the copy used or the condition that forced the unit test.
  *(Cites: D-11, the validation thoroughness gap line (Sources),
  kickoff §3 REQ-C (2026-09-24), kickoff §8 (2026-09-24).)*
- **REQ-C1.2** Every act-on-findings skill SHALL declare its scoping of the
  bi-directional adversarial pass (refute each kept finding, resurrect each
  finding in validation-rigor's decline set), and the default where none is declared SHALL be the full
  pass over both sets.
  *(Cites: D-11, the review/disposition asymmetry line (Sources), the
  bi-directional re-validation scoping line (Sources).)*
- **REQ-C1.3** A declined finding SHALL stay in the loop ledger with its
  decline reason; the blind pass never reads that ledger, and a blind
  finding matching a declined one SHALL NOT be suppressed by it but SHALL
  enter disposition, reopening the decline when it carries evidence the
  decline did not consider.
  *(Cites: D-5, D-11, the research seed (Sources), kickoff §8 (2026-09-24).)*
- **REQ-C1.4** A positive validation result SHALL name the process that
  produced it: a regression test states that it failed before the fix, a
  corpus or fuzz run states how many inputs could have failed, an isolation
  claim shows the run log; a result without its process is not evidence.
  *(Cites: D-11, obs:af6048cb, obs:ef2549c2, obs:b7d3e2a1.)*
- **REQ-C1.5** A finding grounded in a cited tool rule with a mechanical
  fix SHALL be validated by the tool's rule plus the diff-scoped check, and SHALL
  NOT require the three-pass validation; the skill's declared scoping names
  this carve-out.
  *(Cites: D-11, proportionality (Sources).)*

## REQ-D — Loop economics

- **REQ-D1.1** Every review pass SHALL start from the handoff bundle in a
  fresh, bounded context on every execution backend, never on top of the
  implementation transcript: a fresh sub-agent given only the handoff
  bundle path, in the foreground under stream-json; where no agent can be
  spawned at all the pass runs inline from the bundle and the
  convergence evidence records it as not context-independent.
  *(Cites: D-6, obs:54b2c3b6, obs:7da1eedb, the research seed (Sources),
  kickoff §8 (2026-09-24).)*
- **REQ-D1.2** Doctrine and the kickoff brief SHALL be resolved once per
  loop, their resolved paths recorded for every pass and lens; a pass SHALL
  NOT re-resolve them. The handoff bundle is rebuilt per pass (REQ-B1.1)
  from those paths, in delta mode after an iteration's fixes.
  *(Cites: D-3, D-12, kickoff §8 (2026-09-24).)*
- **REQ-D1.3** The full test suite SHALL run once per loop iteration after
  that iteration's fixes; each fix SHALL be validated by a diff-scoped
  check (the tests touching the changed files and the linters), and the
  Agent-resolvable predicate SHALL read the diff-scoped check per fix and
  the full suite per iteration.
  *(Cites: D-11, obs:7fe26f10, obs:0c4456bb.)*
- **REQ-D1.4** The loop's audit record SHALL be written once per loop and
  appended per iteration with the iteration's deltas and counts; the full
  tables SHALL be regenerated only at loop end for the PR body (the angles
  record is the one part this bundle adds to custom-steps' post-pr
  regeneration, REQ-E1.6), and the
  PR-body presentation contract SHALL be unchanged apart from the additions
  REQ-B1.4, REQ-B1.7, and REQ-E1.6 make.
  *(Cites: D-12, output-hygiene (Sources).)*
- **REQ-D1.5** Convergence SHALL be an iteration producing zero new
  dispositions (the loop's existing criterion) followed, back to back, by a
  blind pass that raises nothing new. The blind pass SHALL run as
  `/polish`'s confirming pass: the quiet iteration before it is
  delta-directed (REQ-B1.5), so the blind pass is the only whole-branch
  pass after the first, replacing the whole-branch confirming iteration
  the loop runs today. A blind finding that is applied SHALL return the loop to
  iterating until an iteration produces nothing new, followed by a new
  blind pass directed at the delta since the previous blind pass over the
  whole-branch handoff; a blind finding dispositioned without a change
  counts as nothing new. Each blind pass SHALL count as an iteration
  against the cap; the cap and loop detection SHALL be otherwise unchanged.
  *(Cites: D-5, the polish loop-bounds line (Sources), kickoff §3 REQ-D (2026-09-24).)*
- **REQ-D1.6** The loop ledger SHALL persist across a killed session, and
  a resumed loop SHALL continue from the last recorded iteration with its
  dispositions intact.
  *(Cites: D-12, the polish resume-after-kill line (Sources),
  operator-dialogue (Sources).)*

## REQ-E — Blind review and external signals

- **REQ-E1.1** The review doctrine SHALL define a blind review on two axes:
  context independence (the reviewer sees the repository at the branch
  head and the handoff bundle, which carries the diff, the would-be PR
  body, and the task contract, never the implementation transcript or the
  loop's decline ledger) and generator independence (a model of a
  different family).
  *(Cites: D-5, obs:01b3a1eb, obs:3ed95276, the dispatch-isolation decision
  line (Sources), kickoff §8 (2026-09-24).)*
- **REQ-E1.2** A blind pass SHALL be `/polish`'s confirming pass and a
  declared entry in the steps catalog for standalone use; its first run in
  a loop SHALL run the reviewer-basics gate (without REQ-A1.7's
  re-verification, which the loop's gate owns) and the full lens set over
  the branch from the handoff bundle, and its findings SHALL enter
  disposition unfiltered by the loop ledger.
  *(Cites: D-5, D-6, custom-steps (Sources), kickoff §3 REQ-D (2026-09-24),
  kickoff §8 (2026-09-24).)*
- **REQ-E1.3** When an external backend is attached at the convergence or
  post-pr point, its pass SHALL count as the generator-independent angle;
  when none is attached, the blind pass SHALL resolve its tier through the
  allocation resolver's step keys and SHALL be recorded as
  context-independent only.
  *(Cites: D-5, model-allocation (Sources).)*
- **REQ-E1.4** An external review step planwright consumes SHALL return a
  non-empty structured result (the finding fields the independence rule
  doc versions) or be recorded as failed; a finding citing a path absent
  from the prompt inventory the step handling recorded at dispatch SHALL
  be dropped and flagged; findings SHALL be read from the review body as
  well as its threads; and a thread the reviewer resolved itself SHALL NOT
  count toward convergence.
  *(Cites: D-5, obs:03653377, obs:4f7c2e91, obs:8b24690f, obs:51b53aa5,
  kickoff §8 (2026-09-24).)*
- **REQ-E1.5** Every post-convergence finding raised by the bot reviewer,
  an external backend, or a human and then fixed SHALL be recorded in the miss ledger
  with its lens, miss reason, PR number, and path, through the
  observation-recording helper under the fixed grammar D-8 defines, by any
  planwright flow that applies the fix (the post-pr step handling when a
  post-pr step's fix lands); lens briefs SHALL cite the ledger's recurring
  classes, never its rows; and the refresh script SHALL derive a fixed
  finding with no ledger entry (matched on PR number and path) from the PR
  history alone, with reason `other`, reporting how many rows took that
  fallback.
  *(Cites: D-8, the research seed (Sources), kickoff §3 REQ-E (2026-09-24),
  kickoff §8 (2026-09-24).)*
- **REQ-E1.6** The PR body's audit record SHALL name which independent
  angles ran on the unit and which did not — blind (the fresh-context
  pass), generator-independent (an attached external backend), and
  external (a reviewer outside the convergence, such as the bot reviewer
  after the PR opens) — each by its role and never by step or product
  name, rendered per output-hygiene's collapsed-detail convention; it SHALL
  be re-emitted after the post-pr step list completes, whether or not the
  head moved; and it SHALL NOT claim an angle that did not run.
  *(Cites: D-5, output-hygiene (Sources), kickoff §3 REQ-E (2026-09-24),
  kickoff §8 (2026-09-24).)*
- **REQ-E1.7** No artifact this bundle commits or edits SHALL name the
  bot reviewer product or an external model backend; they are named by
  role, an operator exception is recorded in that artifact's PR body, and
  the observation fragments already merged SHALL be reworded to role terms.
  *(Cites: D-16, kickoff §3 REQ-E (2026-09-24).)*

## REQ-F — Mechanical guards

- **REQ-F1.1** The guard catalog SHALL carry a shell lint rule set with a
  rule for each recurring shell defect class in the research seed that a
  mechanical check can own, each rule cited so its finding is tool-grounded
  (Auto-applicable where the categorization's conditions and disqualifiers
  allow), and this repository SHALL run the set under its check task.
  *(Cites: D-13, the research seed (Sources), kickoff §8 (2026-09-24).)*
- **REQ-F1.2** A script that emits an artifact (YAML, Markdown, shell)
  SHALL lint that output in its own tests, and the guard catalog SHALL
  name emitter output linting as a guard.
  *(Cites: D-13, obs:8c6fdca5.)*
- **REQ-F1.3** A stated count in the sentence introducing a Markdown list
  or table that immediately follows SHALL equal the list's length,
  enforced by a guard over the doctrine, skill, docs, Draft-bundle, and
  `specs/_pending/` prose this repository tracks; a bundle at any other
  status is skipped, a signed bundle's enumerations being the sign-off
  cross-check's.
  *(Cites: D-13, the research seed (Sources), kickoff §3 REQ-F (2026-09-24),
  kickoff §8 (2026-09-24).)*
- **REQ-F1.4** A test assertion that cannot fail — one with no positive
  control, a status read after a pipe from a stage other than the one
  under test, an asserted command masked by an always-true alternative, or
  a constant compared to itself — and a corpus harness with a zero row
  floor SHALL fail the suite, enforced by a guard over the test surface.
  *(Cites: D-13, obs:e9f5cc37, obs:af6048cb, kickoff §8 (2026-09-24).)*

## REQ-G — Skill diet

- **REQ-G1.1** `/self-review` and `/polish` SHALL load at run-start only
  the doctrine their pre-flight needs, with every other doc reclassified to
  point-of-use where instruction-headroom's safety-floor test allows, and
  the diet SHALL land before any doctrine growth this bundle adds to the
  doctrine those two skills load.
  *(Cites: D-12, obs:d2abb33d, obs:97e811db, instruction-headroom
  (Sources).)*
- **REQ-G1.2** The instruction-budget guard SHALL charge the nested chain
  (`/polish`, `/self-review`, and the doctrine both load) as one closure,
  with its own error threshold as a config knob beside the existing
  closure-error knob, any exception to it recorded in the exemptions file.
  *(Cites: D-12, obs:15240f38, kickoff §8 (2026-09-24).)*
- **REQ-G1.3** Every requirement of this bundle that adds skill prose SHALL
  land word-neutral: the task names what it replaces, and the skill's
  start-load SHALL be no larger after the task than before it (a new skill
  is held to its warn line instead).
  *(Cites: D-12, obs:4034976f, kickoff §8 (2026-09-24).)*

## REQ-H — Measurement

- **REQ-H1.1** The bundle SHALL record the research seed's baselines as
  decided values: the share of externally reviewed PRs with a fixed
  external finding, the median fixed findings and review rounds per such
  PR, the median tokens per convergence run and its share of a unit, and
  the share of fixed findings whose lens row the audit record marked
  `none`.
  *(Cites: D-7, the research seed (Sources).)*
- **REQ-H1.2** A committed, versioned backtest corpus SHALL hold, for each
  fixed external finding the research mined, the PR, the pre-fix commit's
  hash, the file and line, the category, the miss reason, a one-line
  paraphrased gist (never reviewer text or a reviewer login), and a
  replayable flag; a hygiene screen SHALL refuse a row naming the bot
  reviewer or backend product, read from a machine-local name list; a
  `declined`-class row also holds its recorded dismissal, paraphrased. A
  refresh script, run operator-local and never in CI, SHALL rebuild it into
  a new corpus version from the repository's PR history plus the miss
  ledger (a corpus version is a `v<N>` directory), validating each PR
  number as an integer, fetching the PR's head
  ref, and marking a row unreplayable when its pre-fix commit is absent
  from that ref's history. A replay harness SHALL run one review pass (the
  pass under test's pre-fan-out steps plus one lens fan-out, no fixes and
  no loop; a `declined`-class row seeded with its recorded dismissal)
  against the pre-fix state of a seeded random sample capped per class, in
  the isolated copy REQ-C1.1 defines; it SHALL exclude unreplayable rows
  and report their count, refuse a sample with zero replayable rows overall
  or in a targeted class, print the cap and seed it used, and report recall
  per class against a baseline from the same corpus version and model,
  refusing a comparison across either. A class is a row's miss reason; a
  row is caught when any finding cites its file within 10 lines of its
  line, a mechanical rule fixed before the baseline run.
  *(Cites: D-7, D-9, the LLM-quality decision domain (Sources),
  kickoff §3 REQ-H (2026-09-24).)*
- **REQ-H1.3** A task that changes reviewer behaviour as a skill
  instantiates it (a lens, the gate, or the handoff's consumption) SHALL
  replay the corpus rows in the classes it targets before it lands, with
  the baseline's recorded seed and cap restricted to those classes; its PR
  body SHALL state the recall it achieved against the baseline replay; and
  it SHALL NOT land while any targeted class catches fewer sampled rows
  than the baseline did.
  *(Cites: D-9, kickoff §3 REQ-H (2026-09-24), kickoff §8 (2026-09-24).)*
- **REQ-H1.4** A metric script, runnable at any time, SHALL compute tokens
  per convergence run and the post-convergence finding rate from the
  transcripts, the fleet events, the miss ledger, and the PR history. The
  bundle's closeout task SHALL run it over a window of at least 15 PRs the
  bot reviewer reviewed, merged after the last of Tasks 1 to 12 lands, and
  record the result against REQ-H1.1's baselines under a bar fixed now:
  both the post-convergence finding rate and the tokens per convergence
  run below baseline. A missed bar SHALL be recorded as a miss observation
  and a gated follow-up, and does not hold Done; Done derives only when the
  record exists.
  *(Cites: D-7, the invocation (Sources), kickoff §8 (2026-09-24).)*

## Changelog

- 2026-09-24 — Drafted from the research seed and the drafting session;
  Status Draft.
- 2026-09-24 — Kickoff walkthrough edits: REQ-B1.6 retry order, REQ-C1.1
  copy-not-live reproduction, REQ-D1.5 post-blind iteration, REQ-E1.5 refresh
  fallback, REQ-E1.6 post-pr regeneration, REQ-F1.3 signed-bundle skip,
  REQ-H1.2 one-pass replay and unreplayable rows, D-16 no-product-name
  rule; paired test-spec entries.
- 2026-09-24 — Kickoff sign-off: Status Ready (`kickoff-brief.md` §8).
- 2026-09-24 — Kickoff sign-off lens pass: the goal's figures cited, not
  copied; the blind pass never reads the decline ledger (REQ-C1.3); the
  bundle rebuilt per pass (REQ-D1.2) and carrying the PR body; fresh
  context for every pass; generator independence as a different model
  family only; no claimed angle that did not run; the catch rule; the
  closeout bar and window; REQ-E1.7 for the naming rule; the replay
  trigger and seed reuse; the guard definitions; the closure entry kind.
- 2026-09-24 — Kickoff risk walk: baselines pinned to the model they ran
  on; no re-rolled seed without the operator; the product-name list's home
  and its fail-closed refresh; the replay framed as a regression guard,
  the closeout window as the held-out measure.
- 2026-09-24 — Kickoff task-graph walk: Task 7 depends on Task 1 (its
  replay needs the harness and baseline); Task 9 depends on Task 7 (both
  edit `/self-review`).
- 2026-09-24 — Kickoff design and verification walk: REQ-G1.1's diet
  precondition scoped to the doctrine the two review skills load; the
  test-spec's coverage note states where a replay runs.
- 2026-09-24 — Kickoff design walk: D-10's precondition rule stated
  generally and applied to the diet, validation-doctrine, and execute-task
  wiring tasks; D-6 notes the blind skill's closure is charged alone.
- 2026-09-24 — Kickoff mid-walk lens pass: task deliverables paired with
  the edits; the blind pass moved inside `/polish` as its confirming pass;
  isolated-clone reproduction; the declined class replayed with a seeded
  dismissal; the no-targeted-class-drops replay gate; corpus versions and
  the product-name screen; the miss grammar keyed on PR and path.

## Sources

- **The research seed** — `specs/_pending/review-effectiveness-research.md`
  (2026-09-24): research tracks over the skill text, the observation
  accumulator, every spec bundle, the repository's PR history, and the
  session transcripts; every baseline, miss-reason count, and cost figure
  this bundle cites. Pinned altitude claims from the invocation: "the
  review skills burn a lot of tokens" and "they don't get results that
  prevent long review cycles with external reviewers", both measured true
  and both statements about the review passes as a class, not one skill.
  Mid-flow signal: elicitation kept producing doctrine-shaped rules (the
  gate, the sweep, the blind pass).
- **The invocation** (2026-09-24) — the operator's ask to revamp the
  review skills for efficiency and effectiveness, to research what the
  bots caught that the passes missed, and (mid-session) to use merged PRs
  as the record of what worked; the reviewer-basics gap ("confirm the PR
  covers the task and its acceptance criteria") raised in elicitation.
- **A private reviewer** — a reviewer the operator can consult that
  catches defects the passes miss; referenced generically only,
  never named, and its material was not available to the drafting session;
  its design lessons are a Deferred entry.
- **The kickoff walkthrough** (2026-09-24) — `kickoff-brief.md` §3, the
  operator's decisions per REQ group, cited as `kickoff §3 REQ-<group>`;
  and §8, the sign-off lens pass's dispositions, cited as `kickoff §8`.
- **bootstrap** REQ-C, REQ-D, REQ-E (Done) — the historical owner of the
  categorization, the rigor doctrine, and the review core.
- **custom-steps** (Ready) — the convergence and post-pr points, the steps
  catalog, and the retirement of the review-sequence knob; this bundle's
  blind step is an entry in that catalog.
- **prose-disposition** (Ready) — the Documentation lens's four defect
  classes and prose batching; edits the same files, sequenced first (D-10).
- **instruction-headroom** (Ready) — the budget floors, the safety-floor
  test, and the research-rigor reclassification in the review skills.
- **model-allocation** (Ready) — the tier resolver and its step keys; its
  scope names a future spec as the consumer of the context-engineering
  fragments, which this bundle is for the review pass only.
- **operator-dialogue** (Done) — D-16's framing of the polish audit file
  as a per-run cache, which REQ-D1.6 amends for the loop ledger.
- **output-hygiene** (Done) — the PR-body presentation contract the audit
  record keeps.
- **merge-currency-guard** (Ready) — the main sync at each convergence
  iteration, consumed unchanged.
- **The dotfiles code-review command** — its acceptance-criteria lens and
  read-each-full-file rule, the pattern the reviewer-basics gate and the
  context handoff generalize.
- **The LLM-quality decision domain** — `doctrine/decision-domains.md`
  domain 17: a load-bearing LLM step needs a versioned, held-out eval set
  with a pre-committed gate; the backtest corpus is that set.
- **obs:01b3a1eb**, **obs:972182f6**, **obs:3e8a5d60**, **obs:97dc8742**,
  **obs:8fdca68f**, **obs:749d937c**, **obs:247c430b**, **obs:7003944a**,
  **obs:b11b9175**, **obs:c50cc98d**, **obs:a682c3fc**, **obs:8c6fdca5**,
  **obs:587d7d7b**, **obs:d45387c2**, **obs:51fe1178**, **obs:bf59017f**,
  **obs:5b1c9e77**, **obs:3ed95276**, **obs:15a7fdcb**, **obs:75c25c5d**,
  **obs:98a155ab** — misses external reviewers or a later pass caught after
  the convergence passes declared clean.
- **obs:a0add2f0**, **obs:f03a7e23**, **obs:b23d6ea9**, **obs:54b2c3b6** —
  loop behaviour: defects relocating across rounds, a pure-dedupe trim
  dropping rules, a worker reporting success with findings uncommitted, a
  background fan-out lost at turn end.
- **obs:8b24690f**, **obs:51b53aa5**, **obs:67aafd6a** — the bot
  reviewer's signal mechanics: body findings, self-resolved threads,
  polling.
- **obs:03653377**, **obs:361dd7e5**, **obs:fbf43658**, **obs:4f7c2e91**,
  **obs:b7d3e2a1** — external backend reliability: empty exit-zero output,
  size ceiling, sigil expansion, fabricated citations, compliment-filled
  `none` rows.
- **obs:19ec8cd4**, **obs:8dcf0f7c**, **obs:9c3cf221**, **obs:c10c0a24**,
  **obs:7da1eedb**, **obs:3672d83d**, **obs:38f3809f**, **obs:614d4db7** —
  lens fan-out mechanics: raw-to-root-cause collapse, no degrade path
  without sub-agents, artifact-class selection unnamed in the skills, a
  stale plugin resolving old doctrine.
- **obs:af6048cb**, **obs:e9f5cc37**, **obs:6a2d1abd**, **obs:e25c7458**,
  **obs:ef2549c2** — vacuous evidence: a fuzz with nothing that could fail,
  a harness with three ways to pass while testing nothing, a real race
  dismissed as load, a before/after with no positive control, an isolation
  claim nobody checked.
- **obs:7fe26f10**, **obs:0c4456bb**, **obs:67861aa6**, **obs:66ae088f** —
  the CI gate inside the convergence loop: concurrent full suites, wrong
  verdicts under load, over-timeout runs, the false-red rate.
- **obs:d2abb33d**, **obs:97e811db**, **obs:4a3e2947**, **obs:fb7cd43e**,
  **obs:8905e6b9**, **obs:15240f38**, **obs:7c02f52b**, **obs:8d2f1a63**,
  **obs:d20e8988**, **obs:34cae1db**, **obs:4034976f** — the review skills'
  instruction budget: the run-start docs, zero slack, the point-of-use
  lever and its safety-floor and overlay-protection constraints.
- **The fan-out partial-failure line** — the frozen legacy observation of
  2026-06-11 that a lens sub-agent which dies leaves a silent coverage hole
  the lens-coverage table cannot show.
- **The polish loop-bounds line** — the frozen legacy observation of
  2026-06-12 that `/polish` operationally pinned convergence as an
  iteration with zero new dispositions and a cap of ten.
- **The polish resume-after-kill line** — the frozen legacy observation of
  2026-06-12 that the loop ledger has no resume semantics.
- **The self-hosting rigor gap line** — the frozen legacy observation of
  2026-06-15 that an installer defect was caught only by an external
  consumer's review.
- **The dispatch-isolation decision line** — the frozen legacy observation
  of 2026-06-15 recording the operator's decision that each review step
  runs in its own fresh session for an uncontaminated perspective.
- **The review/disposition asymmetry line** — the frozen legacy observation
  of 2026-06-16 that a single pass validates the keep set and rubber-stamps
  the decline set, and that re-validating in both directions reliably does
  better.
- **The validation thoroughness gap line** — the frozen legacy observation
  of 2026-06-16 that whole-system reproduction is the operator's wanted
  first confirmation, not an optional third angle.
- **The bi-directional re-validation scoping line** — the frozen legacy
  observation of 2026-06-16 that the act-on-findings skills declare
  three-pass scoping but say nothing about the adversarial pass.
- **proportionality** — `doctrine/proportionality.md`: rigor scales with
  stake and reversibility, and every scoping is declared.
