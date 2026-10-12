# Review effectiveness — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-24
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
- **Dependencies:** Task 2
- **Citations:** D-2, D-3, D-4, D-8, D-14 · REQ-A1.1, REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-E1.5
- **Estimated effort:** 1.5 days

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
- **Dependencies:** Task 2
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
- **Dependencies:** Task 1
- **Citations:** D-5, D-8, D-16 · REQ-E1.1, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-E1.7
- **Estimated effort:** 1 day

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
- **Dependencies:** Task 1, Task 3, Task 6
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
- **Dependencies:** Task 3, Task 5, Task 6
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
- **Dependencies:** Task 3, Task 4, Task 6, Task 7, Task 8
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
- **Dependencies:** Task 4, Task 5
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

### Task 13 — Backtest evaluation of the landed pass

- **Deliverables:** one replay of the full default sample (the default
  per-class cap over every class) with the landed gate, lenses, and
  handoff, every other row through `/self-review --nested`'s first pass and
  declined rows through the blind pass; the recall per class against the
  baseline replay recorded in the corpus fixture's results file; a short
  results section in the PR body naming the classes that improved, held,
  or regressed.
- **Done when:** the replay ran over the full default sample; the results
  file is committed with per-class recall against the baseline, or with
  the baseline re-run on the current model and both recorded; every
  regressed class is carried as a gated Deferred follow-up (the PR body
  may also explain it).
- **Dependencies:** Task 7, Task 8, Task 9, Task 10
- **Citations:** D-7, D-9 · REQ-H1.2, REQ-H1.3
- **Estimated effort:** half day

### Task 14 — Closeout measurement window

- **Deliverables:** the metric script run over a window of at least 15 PRs
  the bot reviewer reviewed, merged after the last of Tasks 1 to 12 lands,
  with the window's first and last PR and the run date stated; the
  post-convergence finding rate and tokens per convergence run recorded
  against the baselines in the corpus fixture's results file, with the
  bar's verdict (both below baseline); on a missed bar, a miss observation
  through the observation helper and a gated Deferred follow-up naming the
  metric that missed; a Changelog entry naming the window and the verdict.
- **Done when:** the window holds at least 15 such PRs; the results file
  carries both metrics and the verdict; a missed bar has its observation
  and follow-up; the Changelog entry exists; `mise run check` passes.
- **Dependencies:** Task 13, Task 11, Task 12
- **Citations:** D-7 · REQ-H1.4
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
- **Dependencies:** Task 1
- **Citations:** D-16 · REQ-E1.7
- **Estimated effort:** half day

## Awaiting input

(none yet)

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
