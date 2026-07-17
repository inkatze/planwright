# Guard Coverage — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Eleven tasks. Tasks 1–6 and 8–10 are parallel roots; Task 7 needs Task
6's post-split baseline; Task 11 closes over the guard-shipping tasks.
Per the guard-infrastructure-first selection preference, roots are all
dispatchable immediately.

## Tasks

### Task 1 — Permission-matcher fixture test

- **Deliverables:** A documented re-implementation of Claude Code's
  permission-matcher semantics (literal-substring globs,
  deny-before-allow, per-subcommand compound parsing) as a test helper,
  with the modeled behavior version stated; a fixture table of `git push`
  and `git commit` invocations (force forms, `+refspec`, every `main`
  destination spelling, flag-after-arg amend/squash/fixup forms,
  legitimate feature-branch operations) with expected deny/allow
  outcomes; a test asserting `config/worker-settings.json`'s rules
  against the table, wired into the test suite.
- **Done when:** The test fails when a deny rule covering a fixture
  evasion is removed from `config/worker-settings.json` and passes on
  the current config; the known evasions (flag-after-arg amend,
  `HEAD:refs/heads/main`) appear in the table with their current
  matcher outcome recorded honestly; the matcher model doc names the
  Claude Code documentation consulted and the version modeled.
- **Dependencies:** none
- **Citations:** D-4 · REQ-A1.1
- **Estimated effort:** 1 day

### Task 2 — Git hook backstop

- **Deliverables:** Tracked `hooks/` directory with portable-shell
  `pre-push` (reject any refspec updating `refs/heads/main`),
  `pre-rebase` (reject), `prepare-commit-msg` (abort on amend invocation
  signature), and `commit-msg` (reject `squash!`/`fixup!` subjects);
  `core.hooksPath` wiring in the install/worktree setup path; a check
  detecting an unwired clone; git-fixture tests.
- **Done when:** In a fixture repo with hooks wired, `git commit --amend`
  (any flag position), `git commit --squash`/`--fixup` (any position),
  `git rebase`, and every fixture `main`-push spelling are rejected
  non-zero while normal commits and feature-branch pushes succeed; the
  unwired-clone check fails on a clone without `core.hooksPath` and
  passes on a wired one, and cannot silently pass in CI.
- **Dependencies:** none
- **Citations:** D-2, D-3 · REQ-A1.2, REQ-A1.3
- **Estimated effort:** 2 days

### Task 3 — Purged-identifier check

- **Deliverables:** `check:purged-identifiers` in the `check` aggregate:
  a committed seed file of SHA-256 hashes over normalized identifiers, a
  checker that tokenizes tracked text, normalizes identically, and
  compares hashes; documented normalization rules; fixture tests using
  test-only planted tokens; the human-provisioning step for the real
  seeds documented in the check's header.
- **Done when:** A fixture tree containing a planted seeded token fails
  the check and a clean tree passes; the committed seed file contains no
  plaintext identifier (the real seeds are provisioned by the human
  out-of-band and only their hashes land in the repo); the check runs
  green in fork-PR CI; `scan:secrets` and `mise run check` pass on the
  result.
- **Dependencies:** none
- **Citations:** D-5 · REQ-B1.1, REQ-B1.2
- **Estimated effort:** 1 day

### Task 4 — Fork-PR isolation audit and workflow-posture check

- **Deliverables:** The REQ-C1.1 audit of the `pull_request` execution
  path (permissions, secret references, cache poisoning, artifact
  writes), recorded in the kickoff brief risk register with sources
  consulted, confirming or falsifying D-6; a
  `check:workflow-posture` script asserting no `pull_request_target`
  in any workflow, explicit read-only permissions on workflows with
  `pull_request` triggers, and no `secrets.*` reachable from
  `pull_request`; fixture tests.
- **Done when:** The audit record exists in the brief risk register and
  names its conclusion against D-6 (a falsifying finding is surfaced as
  a design amendment, never absorbed); fixture workflows containing
  `pull_request_target`, a `secrets.*` reference, or missing read-only
  permissions each fail the check; the repo's real workflows pass.
- **Dependencies:** none
- **Citations:** D-6 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** 1 day

### Task 5 — Transitive CI-eval exclusion

- **Deliverables:** A task-graph closure pass in
  `scripts/check-no-ci-evals.sh`: parse `mise.toml` `depends` edges,
  root set = tasks invoked from workflow files, fail if the closure
  reaches an `eval:`-namespace task; the existing workflow-text pass
  retained; fixture tests with synthetic `mise.toml` graphs.
- **Done when:** A fixture graph where a CI-run task transitively
  depends on an `eval:` task fails; a clean graph passes; the current
  repo passes; the guard's description documents both passes.
- **Dependencies:** none
- **Citations:** D-7 · REQ-D1.1
- **Estimated effort:** half day

### Task 6 — Straggler test-file split

- **Deliverables:** `test-check-instructions.sh`,
  `test-orchestrate-select.sh`, and `test-obs-consume.sh` split into
  smaller files (or slimmed where fixtures are redundant) so no
  resulting file exceeds the per-file target that Task 7's budget will
  encode; runner discovery picks up the new files.
- **Done when:** The full suite passes with assertion count not reduced
  from the pre-split baseline; no single test file's wall-clock exceeds
  the agreed per-file target on the reference runner; the measured
  post-split per-file and total times are recorded in the PR for Task 7
  to budget against.
- **Dependencies:** none
- **Citations:** D-9 · REQ-E1.2
- **Estimated effort:** 2 days

### Task 7 — check:test-time budget gate

- **Deliverables:** Per-file timing capture in the test runner; a
  committed budget config (per-file budget and suite-total budget, set
  from Task 6's post-split baseline plus 30–50% headroom, values
  recorded with their derivation); `check:test-time` in the `check`
  aggregate, hard-failing when either budget is exceeded; fixture
  tests.
- **Done when:** A fixture timing report exceeding the per-file or the
  total budget fails the check and an in-budget report passes; the real
  suite runs green under the committed budgets; the budget file's
  header documents the bump-consciously rule.
- **Dependencies:** 6
- **Citations:** D-8 · REQ-E1.1
- **Estimated effort:** 1 day

### Task 8 — Performance-lens doctrine amendment

- **Deliverables:** `doctrine/discovery-rigor.md` amended so the
  Performance lens explicitly names test/CI ergonomics (suite
  wall-clock, CI latency) a lens target, with the whole-system framing
  (not diff-scoped only); the amendment cited back to this bundle.
- **Done when:** The lens text names the target; `mise run check`
  passes; the change is recorded in this bundle's Changelog as the
  REQ-E1.3 delivery.
- **Dependencies:** none
- **Citations:** D-1 · REQ-E1.3
- **Estimated effort:** half day

### Task 9 — Drift tethers

- **Deliverables:** `check:doctrine-index` asserting every
  `doctrine/*.md` (minus README) has a `doctrine/README.md` index row;
  a test parsing the backend-capability-contract prose table and
  asserting `caps_for()` in `scripts/orchestrate-backends.sh` matches
  it; `check-options-reference.sh` widened to compare `docs/fleet.md`'s
  knobs-table defaults against `config/defaults.yml`; fixture tests for
  each; all wired into the `check` aggregate.
- **Done when:** Each tether fails on a fixture divergence (unindexed
  doctrine doc, mismatched capability row, drifted knob default) and
  passes on the current tree; removing a `doctrine/README.md` row or
  editing a `caps_for()` value locally makes `mise run check` fail.
- **Dependencies:** none
- **Citations:** D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.3
- **Estimated effort:** 1 day

### Task 10 — Template lint scope and CDPATH check

- **Deliverables:** `templates/**/*.md` added to the `lint:md` glob,
  with a scoped `templates/.markdownlint.jsonc` only if placeholder
  syntax requires it; a CDPATH house-pattern check flagging `cd` inside
  command substitutions in `scripts/`/`tests/` files lacking a
  top-level `unset CDPATH`, wired into the `check` aggregate, its doc
  noting the CDPATH=. regression-test convention; fixture tests.
- **Done when:** `lint:md` covers the template READMEs and `mise run
  check` passes; a fixture script with `$(cd ...)` and no
  `unset CDPATH` fails the check, and the current tree passes.
- **Dependencies:** none
- **Citations:** D-11, D-12 · REQ-G1.1, REQ-G1.2
- **Estimated effort:** half day

### Task 11 — Guard-catalog entries and registration sweep

- **Deliverables:** Pinned-action-freshness entry in
  `doctrine/guard-catalog.md` and `config/guard-catalog.yaml`
  (signal-only, no auto-bump), plus catalog entries for the
  generalizable guard classes this spec shipped (test-time budget,
  CDPATH house pattern); a registration sweep confirming every guard
  from Tasks 1–5, 7, 9, 10 is wired into the `check` aggregate and
  documented where the guard inventory lives.
- **Done when:** The catalog prose and yaml entries exist and pass
  schema/lint checks; a written sweep result in the PR maps each
  shipped guard to its `check` aggregate entry and doc location, with
  none missing.
- **Dependencies:** 1, 2, 3, 4, 5, 7, 9, 10
- **Citations:** D-13 · REQ-H1.1, REQ-H1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
