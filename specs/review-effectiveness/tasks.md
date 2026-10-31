# Review effectiveness — Tasks

**Status:** Ready
**Last reviewed:** 2026-10-21
**Format-version:** 2
**Execution:** derived — see the status render

Dependency edges cross no bundle boundary; where a task needs another
bundle's work merged first, its `Done when:` names that precondition (D-10).
Every task that changes reviewer behaviour as a skill instantiates it
replays the backtest rows in the classes it targets before it lands (D-9).

## Tasks

### Task 1 — Backtest corpus, replay harness, cost metric, and baselines

- **Deliverables:** the committed, versioned corpus under the test
  fixtures, one row per fixed external finding with PR, pre-fix commit
  hash, path, line, category, miss reason, paraphrased gist, and replayable
  flag (and a paraphrased dismissal for a declined row), built from the
  research seed's datasets under `v1`, labels assigned from the seed with
  the label source recorded, and `declined` rows derived from each PR
  body's declined log; the hygiene screen
  (public-repository data only, no reviewer text or login, and no product
  named in a machine-local name list); `scripts/review-backtest.sh`
  (replay: one review pass per row in an isolated copy, `declined` rows
  seeded with their dismissal, seeded random sampling with a per-class cap
  and a documented default, unreplayable rows excluded and counted, the
  zero-row refusal applied after exclusion, the cap and seed printed,
  the 10-line catch rule, recall per class against a same-version,
  same-model baseline, and a non-zero exit when a targeted class catches
  fewer rows than the baseline), with a reviewer-stub seam (recorded
  findings per row) its tests run against offline;
  `scripts/review-backtest-refresh.sh` (operator-local: rebuild into a new
  corpus version from the PR history plus the miss ledger, integer PR
  numbers, head-ref fetch, unreplayable marking, the `other` fallback
  matched on PR and path with its count reported); `scripts/review-cost.sh`
  (tokens per convergence run from the transcripts and fleet events, and
  the post-convergence finding rate from the miss ledger and PR history,
  runnable at any time); the replay, refresh, and metric entry points
  registered as `eval:` tasks so `check:no-ci-evals` keeps them out of CI;
  offline test fixtures (a recorded-JSON PR history and a local bare remote
  with pull-request head refs, one pointing at a missing commit); the
  baseline values recorded as decided values in a fixture the harness and
  the closeout compare against; a baseline replay of today's pass (its lens
  fan-out without a gate or bundle) over the default sample, recording its
  model, seed, cap, and plugin commit; tests for the corpus schema, the
  hygiene screen, the refresh (fragment ingest, integer PR numbers, the
  fallback count), the harness's row floor, gate, catch rule, and
  cross-model refusal, and `review-cost.sh` over fixture transcripts, fleet
  events, ledger, and PR history.
- **Done when:** the corpus passes its schema test and the hygiene screen;
  the harness refuses a sample with zero replayable rows and exits non-zero
  on a fixture drop; the refresh test marks the missing-commit row
  unreplayable, derives an unrecorded finding as `other`, and reports the
  fallback count, offline; the gate, catch-rule, and cross-model tests pass
  offline against the stub; the baseline replay and baseline values are
  committed; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-7, D-9, D-16 · REQ-E1.5, REQ-E1.7, REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4
- **Estimated effort:** 3 days

### Task 1.1 — Corpus refresh to a second version from the external review threads

- **Deliverables:** an operator-local full run of
  `scripts/review-backtest-refresh.sh --label-reasons` over this
  repository's PR history, producing the `v2` corpus directory: the first
  version's rows carried, the fixed external findings merged since its cut
  added, each new row lacking a ledger entry labelled by the annotator
  under D-8's tokens as Task 5.1 extends them and its gist paraphrased; the
  hygiene screen run over the new version; a baseline replay over the
  second version's default sample of the same pre-bundle configuration
  the first version's baseline ran (that run's plugin commit), recorded
  with its model, seed, cap and plugin commit, so Task 13 compares like
  with like; nothing from the audit's own datasets committed.
- **Done when:** the `v2` directory passes the schema test and the hygiene
  screen; the refresh run, the second version's row counts per class, and
  the `other` fallback count are recorded in the PR body; the baseline
  replay over the second version is committed; `mise run check` passes. A
  dispatched worker parks the task as Awaiting input for the operator's
  run until that run is recorded.
- **Dependencies:** 1, 5.1
- **Citations:** D-7, D-9, D-16, D-22 · REQ-H1.2, REQ-H1.5, REQ-H1.7
- **Estimated effort:** half day

### Task 2 — Skill diet and the composed-chain charge

- **Deliverables:** `skills/self-review/SKILL.md` and
  `skills/polish/SKILL.md` with their run-start manifests reduced to what
  the pre-flight needs and every other doc point-of-use where
  instruction-headroom's safety-floor test allows, the frontmatter
  descriptions no longer restating the audit artifacts; the budget guard
  charging the nested chain (polish, self-review, the doctrine both load)
  as one closure with its own error threshold, a knob beside
  `instruction_budget_closure_error` with its options-reference row; the
  guard tests for the chain charge; the measured start-loads before and after
  recorded in the PR body.
- **Done when:** instruction-headroom Task 10 and prose-disposition Task 11 are merged on main; both start-loads are below their warn lines
  after the diet; the chain closure is charged and reported by
  `mise run check:instructions`; no declared exception is added.
- **Dependencies:** none
- **Citations:** D-12 · REQ-G1.1, REQ-G1.2, REQ-G1.3
- **Estimated effort:** 1.5 days

### Task 3 — Discovery doctrine amendments

- **Deliverables:** `doctrine/discovery-rigor.md` amended word-neutrally
  with the reviewer-basics gate as the step before the fan-out, the
  handoff bundle as what every lens receives, delta attention from the
  second pass, claim-versus-code executed
  from both sides, the sibling sweep as a lens and a post-fix step,
  root-cause clustering before disposition with raw and clustered counts,
  the reviewer-basics gate's checks listed (so the blind skill reads them
  from doctrine), a failed lens retried once then run inline, with
  `failed` as the row's value only when the retry and the inline run both
  fail, lens briefs citing the miss ledger's recurring classes, and the self-critique pass in an independent agent; `doctrine/artifact-lenses.md` naming the
  skills' selection duty; the doctrine index rows (the operator's lens-list
  copy is the gated Deferred entry below).
- **Done when:** prose-disposition Task 1, Task 2, Task 11, and Task 12
  are merged on main; every rule a `[design-level]` test-spec entry assigns
  to these docs appears in them; the two docs' word counts are no larger
  than before; `check:doctrine-index`, `check:links`, `lint:md`, and
  `check:instructions` pass with no new exception.
- **Dependencies:** 2
- **Citations:** D-2, D-3, D-4, D-8, D-14 · REQ-A1.1, REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-E1.5
- **Estimated effort:** 1.5 days

### Task 3.1 — Guard-bypass, procedure-tracing and host-dependence rules in the discovery doctrine

- **Deliverables:** `doctrine/discovery-rigor.md` amended word-neutrally
  with the guard-bypass sub-lens under Security (its trigger, the spelling
  classes, the matcher-or-harness isolation, the recorded-spellings rule)
  and the host-dependence rule under Tests / verification;
  `doctrine/artifact-lenses.md` with procedure tracing in the spec set and
  its finding shapes (REQ-B1.10); `doctrine/guard-catalog.md` with the
  guard-authoring rules in its extension prose, cited from
  `docs/permission-matcher-model.md`; the doctrine index rows; the lens
  briefs the `/self-review` and `/polish` fan-out writes naming the
  sub-lens trigger, word-neutral per REQ-G1.3; the targeted replay per
  REQ-H1.3 over the second corpus version, targeting the miss-reason tokens
  Task 5.1 adds for the guard-bypass, procedure-order and host-dependence
  categories.
- **Done when:** every rule a `[design-level]` test-spec entry assigns to
  these docs appears in them; the word counts of `discovery-rigor.md` and
  `artifact-lenses.md` are no larger than before, and `guard-catalog.md`
  stays below its doctrine warn line; both skills' start-loads are no
  larger than before and the PR body names the text each addition
  replaces; `check:doctrine-index`, `check:links`, `lint:md`, and
  `check:instructions` pass with no new exception; the targeted replay's
  recall is recorded in the PR body with no targeted class below its
  baseline; every Gherkin scenario `test-spec.md` assigns to this task is
  recorded in the PR body.
- **Dependencies:** 3, 1.1
- **Citations:** D-17, D-18, D-19, D-22 · REQ-B1.9, REQ-B1.10, REQ-B1.11, REQ-F1.8, REQ-G1.3, REQ-H1.3, REQ-H1.5
- **Estimated effort:** 1 day

### Task 4 — Validation and loop doctrine amendments

- **Deliverables:** `doctrine/validation-rigor.md` amended word-neutrally
  with reproduction through the real surface, in an isolated copy, as the
  first pass on executable surfaces, the bi-directional adversarial pass's default and
  declaration rule, evidence naming its producing process, and the
  tool-cited carve-out; `doctrine/finding-categorization.md`'s
  Agent-resolvable predicate reworded word-neutrally to the diff-scoped
  check per fix and the full suite per iteration, and validation-rigor's
  wider-check angle restated to the same cadence;
  `doctrine/gate-wiring.md` with the audit record as per-iteration deltas
  regenerated at loop end and the convergence criterion stated around
  the blind pass as polish's confirming pass (an applied blind finding
  returns the loop to iterating; each blind pass counts against the cap);
  the doctrine index rows.
- **Done when:** prose-disposition Task 1 and human-gates Task 1 are
  merged on main; every rule a
  `[design-level]` test-spec entry assigns to these docs appears in them;
  the word counts of the three docs are no
  larger than before; `check:doctrine-index`, `check:links`, `lint:md`,
  and `check:instructions` pass with no new exception.
- **Dependencies:** 2
- **Citations:** D-11, D-12, D-14 · REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5, REQ-D1.3, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 1 day

### Task 5 — The blind-review rule doc and the miss-ledger grammar

- **Deliverables:** `doctrine/review-independence.md` stating the two axes
  of a blind review, what the blind reviewer sees and never sees, the
  generator-independence rule and its fallback through the allocation
  resolver's step keys, the external step output contract (non-empty
  structured result, citations traceable to the prompt, body findings
  read, self-resolved threads not counted), the convergence-evidence
  record for the PR body (angles named by role), the miss-ledger grammar
  keyed on PR number and path with its lens and reason vocabularies, the
  versioned finding fields of the external step output contract, and the
  recording duty of any planwright flow that applies a post-convergence
  fix; the doctrine index row; `scripts/check-review-miss.sh`, wired under
  `mise run check:obs`, refusing a malformed `review-miss` text, with its
  test; `scripts/review-step-verify.sh`, applied to an external review
  step's output by the convergence and post-pr step handling: an empty
  result is recorded as failed, and a finding citing a path absent from
  the step's recorded prompt inventory is dropped and flagged; its tests,
  including a result whose findings sit in the body with no threads and a
  thread the reviewer resolved itself.
- **Done when:** every rule a `[design-level]` test-spec entry assigns to
  the doc appears in it; the grammar test and the verify script's tests
  pass; `check:doctrine-index`, `check:links`, and `lint:md` pass.
- **Dependencies:** 1
- **Citations:** D-5, D-8, D-16 · REQ-E1.1, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-E1.7
- **Estimated effort:** 1 day

### Task 5.1 — Miss-reason and lens tokens for the audit's categories

- **Deliverables:** `doctrine/review-independence.md`'s miss grammar
  extended with a reason token for each of the host-dependent test, guard
  bypass, and ordered-procedure categories and a lens token for procedure
  tracing, no existing token changed; `scripts/check-review-miss.sh` and
  the shared ledger reader accepting them, with a test per new token and
  one showing an existing-token fragment still accepted; the annotator's
  reason list in the corpus refresh carrying them.
- **Done when:** the grammar tests pass; every rule the `[design-level]`
  test-spec entry assigns to the doc appears in it; `check:obs`,
  `check:doctrine-index`, `lint:md` and `mise run check` pass.
- **Dependencies:** 5
- **Citations:** D-8, D-22 · REQ-E1.5, REQ-H1.7
- **Estimated effort:** half day

### Task 6 — The handoff bundle builder and the review scripts

- **Deliverables:** `scripts/review-handoff.sh` writing the bundle into the
  worktree-local `.claude/` directory: the diff against the captured base,
  every changed file whole, the callers of every changed symbol found by a
  grep-based search over the tracked tree (its per-language limits
  recorded), the unit's task contract slice, the would-be PR title and
  body, the tooling output, and the resolved doctrine and brief paths; a
  `--delta <previous-head>` mode that also writes the delta since the
  previous pass and the files a fix touched; the gitignore entry;
  `scripts/review-scope-fence.sh` (files outside the deliverables) and
  `scripts/review-reverify.sh` (re-run each recorded reproduction, or the
  targeted test or tool rule that validated a finding) with the
  recorded-reproduction format they read; `scripts/check-diff-scoped.sh`
  (tests touching the changed files plus the linters); tests for a changed shell
  function's callers, a renamed script's consumers, an empty delta, a
  bundle path containment check, the fence, a regressed reproduction, and
  the diff-scoped check's test selection.
- **Done when:** the tests pass; a bundle for a fixture branch contains
  every caller the fixture plants; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-11, D-14 · REQ-A1.6, REQ-A1.7, REQ-B1.1, REQ-B1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3
- **Estimated effort:** 2.5 days

### Task 6.1 — Standing rules: file format, knob, handoff and routing consumption, exporter

- **Deliverables:** the standing-rules file format (JSON, its version key
  and per-rule fields, the disposition mapping) in
  `doctrine/review-independence.md`, whose never-sees list gains the
  standing rules, and the routing rule (REQ-J1.3) stated word-neutrally in
  `doctrine/finding-categorization.md`; the `review_rules_file` knob in
  `config/defaults.yml` (default none) with its options-reference row;
  `scripts/review-rules.sh` (validate a file against the format and
  select the rules whose scope matches a path set and repository, reading
  the file from the base ref; the file is data, never evaluated) and
  `scripts/review-rules-export.sh` (the vendor-neutral block, grouped by
  disposition, headed by the version key, its SHA-256 printed, a
  statement naming a product on the machine-local name list refused, no
  list refused); `scripts/review-handoff.sh` taking a `--rules <file>`
  input that adds the matched rules as a handoff-bundle member, the lens
  briefs citing them as quoted context, and the blind pass's invocation
  building its handoff bundle without that input; a change editing the
  named rules file surfaced as a Needs-sign-off finding; the routing and
  disposition step in `/self-review` and `/polish` applying a matching
  rule's disposition with the rule id in the audit row, routing new
  evidence to Needs sign-off, and leaving a hard-disqualifier pause in
  place, word-neutral per REQ-G1.3; fixture tests (an unknown version
  refused, a rule missing a field refused, a missing named file refused, a
  conforming file accepted, scope matching by glob and repository, a
  repository subset exported, a finding decided by a rule with the id in
  its row, a finding with new evidence routed to sign-off, a
  hard-disqualifier finding still paused, the blind bundle without a rules
  member, the export's grouping, neutrality, name refusal and stable hash).
- **Done when:** the fixture tests pass; with the knob unset the handoff
  builder's output for a fixture branch is identical, apart from the
  MANIFEST build line, to a golden file captured at the task's base
  commit; every rule a `[design-level]` test-spec entry assigns to the two
  docs appears in them; a targeted replay per REQ-H1.3 with a seeded
  rules file over the `declined` and `pruned` classes records its recall
  in the PR body with no targeted class below its baseline;
  `check:options`, `check:instructions`, `lint:md` and `mise run check`
  pass with no new exception; both skills' start-loads are no larger than
  before and the PR body names the text each addition replaces; every
  Gherkin scenario `test-spec.md` assigns to this task is recorded in the
  PR body.
- **Dependencies:** 6, 8
- **Citations:** D-21 · REQ-G1.3, REQ-H1.3, REQ-J1.1, REQ-J1.2, REQ-J1.3, REQ-J1.4
- **Estimated effort:** 2 days

### Task 7 — The reviewer-basics gate in self-review

- **Deliverables:** `skills/self-review/SKILL.md` running the gate before
  the fan-out from the handoff bundle, word-neutral against the diet:
  acceptance coverage against `Done when:`, deliverables, and cited REQs;
  the would-be PR body against the diff; tests exercising the change
  (judged by reading); copies of a changed claim; callers and consumers;
  the scope fence; and earlier findings' re-verification, calling Task 6's
  scripts; the replay of the corpus rows in the claim-versus-code and
  pruned classes, with recall recorded.
- **Done when:** every Gherkin scenario `test-spec.md` assigns to this task
  is recorded in the PR body; the targeted replay passes the no-drop gate
  against the baseline; the start-load is no larger than before the task.
- **Dependencies:** 1, 3, 6
- **Citations:** D-2, D-9 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-G1.3, REQ-H1.3
- **Estimated effort:** 1.5 days

### Task 8 — The blind-review skill and its step entry

- **Deliverables:** `skills/blind-review/SKILL.md`, a thin nestable skill
  declaring `--nested`, reading only the handoff bundle, running the
  reviewer-basics gate as the discovery doctrine lists it (without the
  loop's re-verification) and the lens fan-out from the bundle as fresh
  agents on each backend the capability contract defines, inline with the
  record saying the blind angle did not run where no agent can be spawned,
  resolving its tier through its own allocation step keys, handling a
  failed lens by the discovery doctrine's retry order, a
  `--delta <previous-blind-head>` mode for a repeat blind pass, and
  returning findings unfiltered by any ledger; the
  `allocation_{model,effort}_step_blind_review` keys in the defaults with
  their options-reference rows; its entry in the steps catalog for
  standalone use, with a resolver test; the overlays documentation row;
  the replay of the corpus rows in the declined (dismissal seeded into the
  coordinator's ledger) and outside-diff classes, with recall recorded.
- **Done when:** custom-steps Task 2 and Task 3 are merged on main; the
  skill's start-load is below its warn line; every Gherkin scenario
  `test-spec.md` assigns to this task is recorded in the PR body, run on
  each backend the worker's host offers, a backend the host lacks parking
  the task as Awaiting input for the operator's run until that run is
  recorded; the resolver test passes; the targeted replay passes the
  no-drop gate against the baseline.
- **Dependencies:** 3, 5, 6
- **Citations:** D-5, D-6, D-9, D-15 · REQ-B1.6, REQ-D1.1, REQ-E1.2, REQ-E1.3, REQ-H1.3
- **Estimated effort:** 1.5 days

### Task 9 — Loop instantiation in polish and self-review

- **Deliverables:** `skills/polish/SKILL.md` and
  `skills/self-review/SKILL.md`, word-neutral against the diet: doctrine
  and brief resolved once per loop and the bundle rebuilt per pass (delta
  mode after fixes); every pass started as a fresh agent from the bundle,
  the inline fallback recorded; delta-scoped lensing from the second pass;
  claim-versus-code from both sides; the sibling sweep lens and post-fix
  step; root-cause clustering; a failed lens retried then run inline, a
  still-failed row ending the loop early as a safety condition;
  artifact-class lens selection named in the audit record; the independent
  self-critique agent; reproduction-first validation in an isolated copy,
  reproductions recorded in Task 6's format; the declared adversarial
  pass; declined findings kept in the ledger and never passed to the blind
  pass; evidence naming its process; the tool-cited carve-out; the full
  suite once per iteration and Task 6's `scripts/check-diff-scoped.sh` per
  fix; the
  audit record as deltas; the ledger persisted and resumed
  (operator-dialogue D-16's per-run overwrite replaced by
  resume-when-present); `/polish`
  invoking the blind skill as its confirming pass, looping back on an
  applied blind finding with the next blind pass delta-directed, each
  blind pass counted against the cap; the replay of the corpus rows in the
  runtime-tracing and pruned classes, with recall recorded.
- **Done when:** every Gherkin scenario `test-spec.md` assigns to this task
  is recorded in the PR body; every skill-side rule a `[design-level]`
  entry assigns to this task appears in the skills; both start-loads are
  no larger than before the task; the targeted replay passes the no-drop
  gate against the baseline.
- **Dependencies:** 3, 4, 6, 7, 8
- **Citations:** D-3, D-4, D-5, D-9, D-11, D-12, D-14 · REQ-A1.7, REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5, REQ-D1.6, REQ-E1.2, REQ-G1.3, REQ-H1.3
- **Estimated effort:** 2.5 days

### Task 10 — Convergence wiring in execute-task

- **Deliverables:** `skills/execute-task/SKILL.md`'s convergence phase folding the convergence-evidence record (which
  independent angles ran, named by role, the blind angle read from
  polish's record) into the PR body and re-emitting it after the post-pr
  step list completes, whether or not the head moved; the post-pr step
  handling recording each attached external step's prompt inventory at
  dispatch, applying `scripts/review-step-verify.sh` to its output, and
  recording a miss through the observation helper under D-8's grammar
  when a post-pr step's fix lands; this repository's convergence setting
  in `.claude/planwright.yml` changed to run `/polish` (which carries the
  blind pass), with its comment updated.
- **Done when:** custom-steps Task 5 and prose-disposition Task 12 are
  merged on main; every Gherkin scenario `test-spec.md` assigns to this
  task is recorded in the PR body; the execute-task start-load is no larger than before the task.
- **Dependencies:** 4, 5
- **Citations:** D-5, D-8 · REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-G1.3
- **Estimated effort:** 1.5 days

### Task 11 — Shell guard rules and emitter output linting

- **Deliverables:** the shell rule set for the recurring classes the
  research seed names that a mechanical check can own: shell-lint
  configuration where the linter carries the rule, and small checks under
  `scripts/` where it does not (pipeline status from the wrong stage,
  ignored command-substitution status, fail-open no-op alternative,
  temporary file without a template, GNU-only flags, leading-dash argument
  to a directory or file primitive, raw echo of untrusted input, unpinned
  config read, a lock-creation failure read as contention), each entered in the guard catalog with its rule id and
  wired under `mise run check`; the emitter output linting guard with its
  catalog entry and the tests for this repository's own emitters; fixture
  tests with one true positive and one true negative per rule; the
  existing scripts brought to green or each exclusion recorded with its
  reason.
- **Done when:** every rule's fixture pair passes; `mise run check` is
  green with the new checks wired; the guard catalog lists each rule.
- **Dependencies:** none
- **Citations:** D-13 · REQ-F1.1, REQ-F1.2
- **Estimated effort:** 1.5 days

### Task 11.1 — The hermetic test libraries and the test-hermeticity guard

- **Deliverables:** `tests/lib/hermetic-env.sh`, clearing or pinning the
  listed configuration and root variables and holding that list as the one
  source the guard, the runner and the perturbed run read, absorbing
  `tests/lib/fleet-home.sh`'s pinning helper, with the per-suite scrub
  lists migrated to it; a dead-owner PID helper in `tests/lib/` yielding a
  PID above the host's assignable range;
  `scripts/check-test-hermeticity.sh` failing the three shapes REQ-F1.5
  names, with a true-positive and a true-negative fixture per shape (the
  dead-owner negatives covering both the helper's PID and a lock-library
  token), its guard catalog entry and `mise run check` wiring; the existing
  suites brought to green (a suite reading a listed variable sources the
  library; a mode-bit fixture gated on an access probe; a dead-owner
  fixture drawing from the helper) or each exclusion recorded with its
  reason; `scripts/run-tests.sh` pinning the same list per file through its
  sentinel arms, with a switch that turns that pinning off for the
  perturbed run.
- **Done when:** the fixture pairs pass; `mise run check` is green with the
  guard wired; the guard catalog lists the guard; no second variable list
  remains under `tests/`.
- **Dependencies:** none
- **Citations:** D-13, D-17 · REQ-F1.5
- **Estimated effort:** 1.5 days

### Task 11.2 — The perturbed CI run

- **Deliverables:** the perturbed job in `.github/workflows/ci.yml`,
  sharded like the plain test jobs, feeding the same timing reports, and
  added to the `check` job's needs so it gates the merge: a decoy value per
  listed variable pointing at a fixture whose use changes a result, with
  the runner's pinning switched off; a `TMPDIR` reached through a symlink
  and containing a space; a non-C locale; a non-UTC timezone; the suite run
  as root, the job stating how root is reached and how the toolchain and
  home resolve under it; named skips only; a test asserting the job's
  perturbation set matches the library's list and carries each of the
  other perturbations and the root user, and that every skip in its log
  names a case and a reason.
- **Done when:** the job's test passes; the perturbed shards pass on the
  task PR with the same verdict set as the plain test shards on the same
  head, named skips excepted; the one-off proof that it can fail (a
  fixture suite depending on the temporary root's shape, and one reading a
  listed variable without sourcing the library, each run under the job
  before the fixture is removed) is recorded in the PR body.
- **Dependencies:** 11.1
- **Citations:** D-17 · REQ-F1.6
- **Estimated effort:** 1 day

### Task 12 — The count-versus-list and test-vacuity guards

- **Deliverables:** `scripts/check-counts.sh` (a stated count adjacent to a
  parseable list equals its length, over the tracked doctrine, skill,
  docs, Draft-bundle, and `specs/_pending/` prose, skipping a bundle at any
  other status) and `scripts/check-test-vacuity.sh` (an assertion that cannot
  fail, and a corpus harness with a zero row floor, fail the suite), each
  with fixture tests, a guard catalog entry, and a `mise run check` wiring;
  the existing surfaces brought to green or each exclusion recorded with
  its reason.
- **Done when:** both fixture suites pass; `mise run check` is green with
  the new checks wired; the guard catalog lists both.
- **Dependencies:** none
- **Citations:** D-13 · REQ-F1.3, REQ-F1.4
- **Estimated effort:** 1 day

### Task 12.1 — The skill-command usage check

- **Deliverables:** `scripts/check-script-invocation.sh` extended with the
  usage-header check, reusing its reading of skill and doctrine prose:
  each invoked script's `# Usage` header parsed into its subcommands, flags
  and required arguments under a grammar the guard catalog entry states
  (the header is data, never executed), and every invocation REQ-F1.7
  defines checked against it, an angle-bracket placeholder standing for a
  required argument, a bare mention and a sourced library skipped; a usage
  header added or normalised for every invoked script the grammar cannot
  parse; fixture pairs (an unknown subcommand, a flag the header lacks, a
  missing required argument, an invoked script without a parseable header,
  a bare mention and a sourced library not checked, and a conforming
  invocation); the guard catalog entry updated; the tracked prose brought
  to green or each exclusion recorded with its reason.
- **Done when:** the fixture pairs pass; the check reports no finding over
  the tracked skills and doctrine; `mise run check` is green with it
  wired; the guard catalog entry states the header grammar.
- **Dependencies:** none
- **Citations:** D-13, D-19 · REQ-F1.7
- **Estimated effort:** 1 day

### Task 13 — Backtest evaluation of the landed pass

- **Deliverables:** one replay of the second corpus version's full
  default sample (the default per-class cap over every class) against Task
  1.1's baseline, with the landed gate, lenses, and handoff, every other row through `/self-review --nested`'s first pass and
  declined rows through the blind pass; the recall per class against the
  baseline replay recorded in the corpus fixture's results file, which
  names the corpus version; a short
  results section in the PR body naming the classes that improved, held,
  or regressed.
- **Done when:** the replay ran over the full default sample; the results
  file is committed with per-class recall against the baseline, or with
  the baseline re-run on the current model and both recorded; every
  regressed class is carried as a gated Deferred follow-up (the PR body
  may also explain it).
- **Dependencies:** 1.1, 3.1, 6.1, 7, 8, 9, 10, 15.1
- **Citations:** D-7, D-9 · REQ-H1.2, REQ-H1.3, REQ-H1.5
- **Estimated effort:** half day

### Task 14 — Closeout measurement window

- **Deliverables:** the metric script run over a window of at least 15 PRs
  the bot reviewer reviewed, merged after every task this one depends on,
  directly or transitively, has landed,
  with the window's first and last PR and the run date stated; the
  post-convergence finding rate and tokens per convergence run recorded
  against the baselines in the corpus fixture's results file, with the
  bar's verdict (both below baseline); on a missed bar, a miss observation
  through the observation helper and a gated Deferred follow-up naming the
  metric that missed; a Changelog entry naming the window and the verdict.
- **Done when:** the window holds at least 15 such PRs; the results file
  carries both metrics and the verdict; a missed bar has its observation
  and follow-up; the Changelog entry exists; `mise run check` passes.
- **Dependencies:** 13, 11, 11.1, 11.2, 12, 12.1
- **Citations:** D-7 · REQ-H1.6
- **Estimated effort:** half day

### Task 15 — Reword merged observation fragments to role terms

- **Deliverables:** every observation fragment on main (live, archived, and
  the frozen legacy log) that names the bot reviewer product or an external
  model backend reworded to role terms ("the bot reviewer", "the external
  backend"), UIDs, dates, and `Consumed-by:` lines untouched; the product
  names read from a machine-local name list, never committed; the hygiene
  screen from Task 1 run over the fragment directories.
- **Done when:** the operator-local hygiene screen over the observation
  fragments reports no listed product name, its run recorded in the PR
  body; `mise run check:obs` and `mise run check` pass.
- **Dependencies:** 1
- **Citations:** D-16 · REQ-E1.7
- **Estimated effort:** half day

### Task 15.1 — Observation hygiene: duplicate refusal and the fragment review step

- **Deliverables:** `scripts/obs-record.sh` refusing a duplicate per
  REQ-I1.1 (the same `[<scope>]` token, and a shared test path and quoted
  string under the REQ's extraction rules, read across live and archived
  fragments, miss-ledger fragments exempt), naming the match, with
  `--recurrence <uid>` as the escape for the matched fragment and the
  `recurrence of obs:<uid>:` marker written after a kind prefix where the
  text has one; its tests (a shared slug alone written, a path-plus-quote
  match against a live and against an archived fragment refused, a
  recurrence accepted with the marker after a `skill-drift(...)` prefix, a
  uid the refusal did not match refused, a miss-ledger fragment not
  refused, no match across scopes); `scripts/check-obs.sh` and the
  `skill-drift` prefix rules accepting the marker; the Observations and
  Maintenance steps of `skills/self-review/SKILL.md` and
  `skills/polish/SKILL.md` reviewing the pass's fragments with the spec lens
  set plus a duplication check before each commit of them (per iteration in
  `/polish`), recording the dispositions in the audit record and a refused
  record's recurrence or withdrawal, landed word-neutral per REQ-G1.3; the
  accumulator-taxonomy doctrine stating the review-before-commit rule and
  naming the recurrence form in its drain ritual.
- **Done when:** the recorder tests pass; both skills' start-loads are no
  larger than before and the PR body names the text each addition
  replaces; every rule a `[design-level]` test-spec entry assigns to this
  task appears in the skills and the doctrine; every Gherkin scenario
  `test-spec.md` assigns to this task is recorded in the PR body;
  `mise run check` passes.
- **Dependencies:** 2
- **Citations:** D-20 · REQ-G1.3, REQ-I1.1, REQ-I1.2
- **Estimated effort:** 1 day

## Awaiting input

- **Task 15** — post-pr: the post-PR bot-reviewer step halted (its
  workspace quota is exhausted until 2026-11-05, operator ruling); record
  `.claude/steps/000001/008-step-post-pr.rec`.

## Deferred

- **The private reviewer's design lessons.** A private reviewer the
  operator can consult catches defects these passes miss; its
  documentation was not available to the drafting session. When a permitted
  read happens, whatever generic lessons it offers are folded into an
  amendment of the discovery and independence doctrine, never citing the
  tool. Confidence: medium.
  **Gate:** surfaced free-text condition — a permitted read of the private
  reviewer's documentation has been recorded by the operator.
  Citations: D-16, a private reviewer (Sources).
- **Mirror the discovery-doctrine changes into the operator's lens-list
  copy.** The operator's global instructions keep a copy of the lens list
  and require a lens-list change to land in both places; Task 3's
  amendments are mirrored there. Confidence: high.
  **Gate:** GATE(when: task 3 completed).
  Citations: D-2, D-4, kickoff §8 (2026-09-24).
- **The operator's own review commands adopt the output contract.** The
  review commands outside planwright adopt the external step output
  contract and write `review-miss` fragments under D-8's grammar, so their
  fixes reach the corpus with a lens and reason instead of the `other`
  fallback. Confidence: high.
  **Gate:** GATE(when: task 5 completed).
  Citations: D-5, D-8, kickoff §8 (2026-09-24).
- **The CI gate's false-red rate under load.** Out of scope here; the
  suite cadence change reduces exposure but not the rate.
  Confidence: high.
  **Gate:** surfaced free-text condition — a bundle consuming the gate
  false-red observations has been drafted.
  Citations: obs:66ae088f, obs:0c4456bb.

## Out of scope

- Editing the dotfiles review commands (their adoption of the output
  contract is the gated Deferred entry above).
- Step attachment mechanics, the ready-flip and merge policies, main
  synchronization, tier resolution, prose disposition, the four-bucket
  taxonomy, unit sizing, and the implementation phase's context.
