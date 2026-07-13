# Prompt Hygiene — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-09
**Format-version:** 1

Dependency view (derived; the `Dependencies:` lines are authoritative):
Task 1 feeds everything; Task 2 (guard) precedes every diet it protects;
Task 4's baseline must exist before Task 5 edits the file it measures;
Task 7.5 (residual start-load diets) depends on Task 3's manifest computation
plus the per-file diets and feeds the Task 8 closeout.
Critical path: 1 → 2 → 3 → 5 → 7.5 → 8.

## Forward plan

### Task 3 — Doctrine manifests in all skills

- **Deliverables:** the Task 1 manifest added to every `skills/*/SKILL.md`
  (run-start and point-of-use classification of each skill's current
  doctrine reads; no slimming yet), making mandatory-at-start and
  reachable-closure budgets computable corpus-wide; the guard's
  manifest-completeness assertion (REQ-A1.2) wired in the **same PR** so a
  future manifest-less skill cannot silently under-report start-load. In the
  **same PR**, seed a transitional `pending diet (Task 7.5)` allowance
  (REQ-B1.3b) for every start-load offender the computation now surfaces
  (notably `/spec-draft`) — and, should the computation surface a
  reachable-closure offender (none expected at kickoff), a transitional closure
  allowance likewise (REQ-B1.3b) — and record their
  point-of-use-reclassification diet plans for Task 7.5 — the start-load (and
  any closure) offenders that Task 2's pre-manifest audit could not yet see.
- **Done when:** the manifest-completeness assertion confirms all ten skills
  declare a manifest (zero absent); `scripts/check-instructions.sh` computes
  mandatory-at-start and reachable-closure for all ten skills; every surfaced
  start-load (and any closure) offender carries its transitional allowance; the
  resolution check passes; `mise run check` stays green **with the transitional
  allowances in place**.
- **Dependencies:** Task 1, Task 2
- **Citations:** D-3, D-1 · REQ-A1.2, REQ-A1.3, REQ-B1.3, REQ-B1.6
- **Estimated effort:** half day
- **Last activity:** 2026-07-12

### Task 4 — Kept-eval runner, /orchestrate fixtures, baseline

- **Deliverables:** `tests/prompt-evals/` layout and fixture format; the
  POSIX-sh runner (hermetic `claude -p --bare --plugin-dir` runs, init-event
  plugin verification, jq assertions, pass^k aggregation, budget caps,
  worktree teardown, per-run cost capture); a stubbed-`claude` test suite
  covering the runner's logic deterministically; an `eval:skill` mise task;
  `/orchestrate` fixture scenarios (print backend: correct unit selected,
  dispatch marker written, launch command printed, non-Ready/non-Active
  spec refused); artifact-hygiene scrubbing so recorded results/cost carry
  the per-fixture graded outcome, the fixture identifier, and cost, stripped of
  machine-local paths, usernames, and session ids (REQ-C1.6; the fixture
  identifier is retained so the paired before/after comparison is not broken by
  the scrub); a standing CI-exclusion guard that fails if an eval
  task is wired into the CI workflow files (REQ-C1.6, not mere absence from
  the aggregate); the pre-diet baseline run recorded.
- **Done when:** the stubbed suite passes in `mise run test`; a real
  baseline run against the pre-diet `/orchestrate` completes pass^3 with
  its scrubbed results and cost recorded under `tests/prompt-evals/`; the
  CI-exclusion guard passes (no eval task in the workflow) and is itself part
  of `mise run check`; the eval task is absent from the `check` aggregate.
- **Dependencies:** Task 1
- **Citations:** D-6, D-7, D-8, D-12 · REQ-C1.4, REQ-C1.6, REQ-D1.3
- **Estimated effort:** 2 days
- **Last activity:** 2026-07-12

### Task 5 — Diet /orchestrate, post-diet eval, pilot verdict

- **Deliverables:** `/orchestrate` slimmed per its Task 2 diet plan (law
  moved to rule docs verbatim in meaning, restatements collapsed, rare
  branches deferred to point of use, manifest updated); the post-diet eval
  run on the Task 4 fixtures; the paired before/after comparison recorded;
  its transitional `pending diet` allowance removed.
- **Done when:** `/orchestrate` passes the guard with no suppression of its
  own; the post-diet eval passes pass^3 with no regression against the
  baseline on paired fixtures; `mise run check` green (its allowance removed;
  the remaining offenders' transitional allowances still in place).
- **Dependencies:** Task 2, Task 3, Task 4
- **Citations:** D-9, D-12 · REQ-D1.1, REQ-D1.2, REQ-D1.3
- **Estimated effort:** 2 days
- **Last activity:** 2026-07-13

### Task 6 — Diet /execute-task

- **Deliverables:** `/execute-task` slimmed per its diet plan (same moves
  as Task 5; manifest updated); its transitional `pending diet` allowance
  removed.
- **Done when:** `/execute-task` passes the guard with no suppression of its
  own; `mise run check` green (remaining transitional allowances still in
  place).
- **Dependencies:** Task 2, Task 3
- **Citations:** D-9 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 1 day

### Task 7 — Diet /spec-kickoff; spec-format disposition

- **Deliverables:** `/spec-kickoff` slimmed per its diet plan (manifest
  updated; exemption removed); an explicit disposition for
  `doctrine/spec-format.md` (trim under the doctrine budget, or a
  permanent recorded exemption citing its authorable-from-alone contract).
  The disposition SHALL record its (limited) coupling: `spec-format.md` is the
  dominant run-start load for `/spec-draft` and `/spec-kickoff`, but a
  compliant trim removes only ~99 words (floor 4,000) — far short of what those
  dependents must shed — so their start-load compliance rests on Task 7.5's
  point-of-use reclassification **regardless** of the trim-vs-exempt choice
  here. Task 7's disposition is therefore largely independent of Task 7.5.
- **Done when:** `/spec-kickoff` passes the guard with no permanent exemption
  of its own body; `spec-format.md` either passes or carries a permanent
  reasoned exemption whose text names the start-load coupling; `mise run check`
  green (any remaining transitional allowances still in place).
- **Dependencies:** Task 2, Task 3
- **Citations:** D-5, D-9 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 1 day

### Task 7.5 — Diet residual start-load offenders

- **Deliverables:** for every skill carrying a transitional start-load
  `pending diet (Task 7.5)` allowance (seeded at Task 3) and not already
  brought under budget by Tasks 5/6/7 — notably `/spec-draft`
  (mandatory-at-start ≈10,460 at kickoff) — the run-start doctrine loads
  reclassified to point-of-use in the skill's manifest until the
  mandatory-at-start budget passes on its own (law moved verbatim in meaning,
  no contract change; gating law is never deferred, REQ-C1.2), and the
  transitional allowance removed. (Reclassification reduces start-load, not
  closure; a closure offender — none surfaced at kickoff — would need a
  content diet, not this task's mechanism, and would carry a transitional
  closure allowance (REQ-B1.3b) until that diet lands.)
- **Done when:** every skill passes the mandatory-at-start error threshold
  with no transitional allowance remaining; `mise run check` green.
- **Dependencies:** Task 3, Task 5, Task 6, Task 7
- **Citations:** D-1, D-9 · REQ-A1.3, REQ-B1.3, REQ-D1.1, REQ-D1.4
- **Estimated effort:** 1 day

### Task 8 — Guard-catalog entry, docs, closeout audit

- **Deliverables:** the `instruction-hygiene` guard-catalog entry (doc +
  `config/guard-catalog.yaml`); pointers from `docs/conventions.md` and
  the doctrine README narrative; a closing `--audit` re-run recorded; the
  suppression list verified to carry only permanent reasoned exemptions, with
  no transitional `pending diet` allowances (per-file, start-load, or closure)
  remaining.
- **Done when:** `scripts/resolve-catalog.sh guard-catalog` (or the
  catalog's documented merged view) contains id `instruction-hygiene`;
  grep finds no `pending diet` allowance (per-file, start-load, or closure); the
  closing audit shows every skill under the mandatory-at-start error threshold;
  `mise run check` green.
- **Dependencies:** Task 5, Task 6, Task 7, Task 7.5
- **Citations:** D-10 · REQ-C1.5, REQ-D1.4
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

### Task 1 — Instruction-hygiene doctrine doc

- **Deliverables:** `doctrine/instruction-hygiene.md` carrying the
  authoring rule (flow in skills, law in rule docs, references one level
  deep), the doctrine-manifest convention (run-start and point-of-use
  classes, exact machine-parseable syntax), the loading convention with
  the safety floor (gating law never deferred), the test-and-measure
  principle, the kept prompt-eval convention (fixture format, runner
  contract, pass^k, cadence, cost capture), and the degradation citation
  set; registered in `doctrine/README.md`.
- **Done when:** the doc resolves via `scripts/resolve-rule-doc.sh
  instruction-hygiene`; `doctrine/README.md` has its index row; `mise run
  check` doc guards (lint:md, check:links) pass; the doc itself is under
  the doctrine per-file budget it defines.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-6, D-7, D-8, D-9, D-10, D-11 ·
  REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** half day
- **Status:** Completed · PR #133 merged 2026-07-10
- **Last activity:** 2026-07-09

### Task 2 — Guard script, knobs, and audit mode

- **Deliverables:** `scripts/check-instructions.sh` (per-file budgets with
  the `doctrine/README.md` index excluded, manifest-derived start-load and
  closure budgets (a skill declaring no manifest scores start-load body-only,
  not an error, REQ-A1.2/B1.8 — so the guard wires cleanly into `check` at this
  task before Task 3 adds manifests), resolution check, the two suppression forms (permanent
  exemption + transitional `pending diet` allowance, REQ-B1.3),
  injected-context measurement over `hooks.json`-registered hooks read
  statically (interpolation lines excluded, REQ-A1.4) with a warn-only floor,
  `--audit` mode emitting the ranked report — every registered hook a row,
  including the injected-context class — and offender shortlist);
  `instruction_budget_*`
  knobs in `config/defaults.yml` (including the injected-context warn floor)
  with `docs/options-reference.md` rows; the suppression list (REQ-B1.3)
  seeded with the **per-file** offenders annotated `pending diet (Task 5|6|7)`
  (the transitional start-load allowance for `/spec-draft` is seeded at Task 3,
  when manifests first make start-load computable — not here, where the
  manifests do not yet exist); fail-loud handling of malformed manifest /
  exemption / allowance / knob input and boundary-defined thresholds (REQ-B1.8),
  with the injected-context hook carved out — an unextractable hook is a
  parse-failure *warning*, never a hard error (REQ-B1.7); untrusted-input safety
  over PR-controllable content (REQ-B1.9);
  a `check:instructions` task in the `mise run check`
  aggregate; seeded-violation fixtures and `tests/test-check-instructions.sh`;
  the initial per-file audit run's diet plans recorded for Tasks 5-7.
- **Done when:** `mise run check` passes on the repo with the transitional
  per-file allowances in place; the seeded-violation fixture suite proves
  error, warn, at-threshold boundary (REQ-B1.8), permanent exemption
  (including reason-less error and start-load/closure-not-suppressed),
  transitional allowance (per-file, start-load, and closure), fail-loud on each
  malformed-input class, absent-manifest scored body-only (no error), an
  injected-context hook parse-failure reported as a warning (not a hard error),
  injected-context warn-floor (reported, non-failing, always-a-row), and
  unresolvable-manifest-reference behavior; a knob override via
  `.claude/planwright.local.yml` changes the outcome in a test.
- **Dependencies:** Task 1
- **Citations:** D-1, D-2, D-4, D-5, D-13 · REQ-A1.1, REQ-A1.3, REQ-A1.4,
  REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7,
  REQ-B1.8, REQ-B1.9
- **Estimated effort:** 2 days
- **Status:** Completed · PR #157 merged 2026-07-12
- **Last activity:** 2026-07-12

## Deferred

- **Full instruction drift lint.** Deterministic checks that skill prose
  names only existing config knobs, current status vocabulary, and
  resolvable REQ/D-IDs. Deferred pending evidence the diets did not fix
  drift's root cause (skills restating doctrine is what goes stale).
  Confidence: medium.
  **Gate:** two or more new skill-drift observations recorded against
  dieted instruction files after this spec completes.
  Citations: REQ-B1.6, drafting-session decision (2026-07-08).
- **Section-scoped resolver mode.** A resolver mode loading one named
  section of a rule doc instead of the whole file. Confidence: low.
  **Gate:** point-of-use reads repeatedly load a whole reference doc for
  a single section (observed during or after the diets).
  Citations: D-9, drafting-session decision (2026-07-08).

## Out of scope

- Per-commit CI execution of behavioral evals (cost, nondeterminism,
  API-key-in-CI). Permanent; evals are on-demand by design (D-8).
- Eval-framework adoption (promptfoo, DeepEval, Braintrust, Inspect);
  promptfoo `exec:` is the documented escalation path, not a plan (D-6).
- Output-artifact hygiene (PR bodies, accumulators): `specs/output-hygiene`.
- Budgets for human-facing docs (`docs/*.md`, `README.md`) and spec
  bundles under `specs/`.
- Semantic-quality enforcement in CI.
