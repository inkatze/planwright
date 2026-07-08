# Prompt Hygiene — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

Dependency view (derived; the `Dependencies:` lines are authoritative):
Task 1 feeds everything; Task 2 (guard) precedes every diet it protects;
Task 4's baseline must exist before Task 5 edits the file it measures.
Critical path: 1 → 2 → 3 → 5 → 8.

## Forward plan

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

### Task 2 — Guard script, knobs, and audit mode

- **Deliverables:** `scripts/check-instructions.sh` (per-file budgets,
  manifest-derived start-load and closure budgets, resolution check,
  exemption handling, `--audit` mode emitting the ranked report and
  offender shortlist); `instruction_budget_*` knobs in
  `config/defaults.yml` with `docs/options-reference.md` rows; the tracked
  exemption list seeded with current offenders annotated
  `pending diet (Task 5|6|7)`; a `check:instructions` task in the
  `mise run check` aggregate; seeded-violation fixtures and
  `tests/test-check-instructions.sh`; the initial audit run's diet plans
  recorded for Tasks 5–7.
- **Done when:** `mise run check` passes on the repo with the transitional
  exemptions in place; the seeded-violation fixture suite proves error,
  warn, exemption (including reason-less error and closure-not-suppressed),
  and unresolvable-manifest-reference behavior; a knob override via
  `.claude/planwright.local.yml` changes the outcome in a test.
- **Dependencies:** Task 1
- **Citations:** D-1, D-2, D-4, D-5 · REQ-A1.1, REQ-A1.3, REQ-B1.1,
  REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6
- **Estimated effort:** 2 days

### Task 3 — Doctrine manifests in all skills

- **Deliverables:** the Task 1 manifest added to every `skills/*/SKILL.md`
  (run-start and point-of-use classification of each skill's current
  doctrine reads; no slimming yet), making start-load and closure budgets
  computable corpus-wide.
- **Done when:** `scripts/check-instructions.sh` computes start-load and
  closure for all ten skills with zero missing-manifest errors; the
  resolution check passes; `mise run check` stays green.
- **Dependencies:** Task 1, Task 2
- **Citations:** D-3 · REQ-A1.2, REQ-B1.6
- **Estimated effort:** half day

### Task 4 — Kept-eval runner, /orchestrate fixtures, baseline

- **Deliverables:** `tests/prompt-evals/` layout and fixture format; the
  POSIX-sh runner (hermetic `claude -p --bare --plugin-dir` runs, init-event
  plugin verification, jq assertions, pass^k aggregation, budget caps,
  worktree teardown, per-run cost capture); a stubbed-`claude` test suite
  covering the runner's logic deterministically; an `eval:skill` mise task;
  `/orchestrate` fixture scenarios (print backend: correct unit selected,
  dispatch marker written, launch command printed, non-Ready/non-Active
  spec refused); the pre-diet baseline run recorded.
- **Done when:** the stubbed suite passes in `mise run test`; a real
  baseline run against the pre-diet `/orchestrate` completes pass^3 with
  its results and cost recorded under `tests/prompt-evals/`; the eval task
  is absent from the `check` aggregate.
- **Dependencies:** Task 1
- **Citations:** D-6, D-7, D-8, D-12 · REQ-C1.4, REQ-D1.3
- **Estimated effort:** 2 days

### Task 5 — Diet /orchestrate, post-diet eval, pilot verdict

- **Deliverables:** `/orchestrate` slimmed per its Task 2 diet plan (law
  moved to rule docs verbatim in meaning, restatements collapsed, rare
  branches deferred to point of use, manifest updated); the post-diet eval
  run on the Task 4 fixtures; the paired before/after comparison recorded;
  its `pending diet` exemption removed.
- **Done when:** `/orchestrate` passes the guard with no exemption; the
  post-diet eval passes pass^3 with no regression against the baseline on
  paired fixtures; `mise run check` green.
- **Dependencies:** Task 2, Task 3, Task 4
- **Citations:** D-9, D-12 · REQ-D1.1, REQ-D1.2, REQ-D1.3
- **Estimated effort:** 2 days

### Task 6 — Diet /execute-task

- **Deliverables:** `/execute-task` slimmed per its diet plan (same moves
  as Task 5; manifest updated); its `pending diet` exemption removed.
- **Done when:** `/execute-task` passes the guard with no exemption;
  `mise run check` green.
- **Dependencies:** Task 2, Task 3
- **Citations:** D-9 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 1 day

### Task 7 — Diet /spec-kickoff; spec-format disposition

- **Deliverables:** `/spec-kickoff` slimmed per its diet plan (manifest
  updated; exemption removed); an explicit disposition for
  `doctrine/spec-format.md` (trim under the doctrine budget, or a
  permanent recorded exemption citing its authorable-from-alone contract).
- **Done when:** `/spec-kickoff` passes the guard with no exemption;
  `spec-format.md` either passes or carries a permanent reasoned
  exemption; `mise run check` green.
- **Dependencies:** Task 2, Task 3
- **Citations:** D-5, D-9 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 1 day

### Task 8 — Guard-catalog entry, docs, closeout audit

- **Deliverables:** the `instruction-hygiene` guard-catalog entry (doc +
  `config/guard-catalog.yaml`); pointers from `docs/conventions.md` and
  the doctrine README narrative; a closing `--audit` re-run recorded; the
  exemption list verified to carry only permanent reasoned entries.
- **Done when:** `scripts/resolve-catalog.sh guard-catalog` (or the
  catalog's documented merged view) contains id `instruction-hygiene`;
  grep finds no `pending diet` exemption; the closing audit shows every
  skill under start-load error thresholds; `mise run check` green.
- **Dependencies:** Task 5, Task 6, Task 7
- **Citations:** D-10 · REQ-C1.5, REQ-D1.4
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

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
