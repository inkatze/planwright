# Guard Coverage — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Eleven tasks. The dependency edges are authoritative in each block's
`Dependencies:` field (rendered on demand via `scripts/spec-graph.sh`);
in prose, most tasks are parallel roots, Task 3 builds on Task 2's hook,
Task 7 gates on the full fixture-bearing suite, and Task 11 closes over
the guard-shipping tasks. Per the guard-infrastructure-first selection
preference, roots are all dispatchable immediately.

## Tasks

### Task 1 — Permission-matcher fixture test

- **Deliverables:** A documented re-implementation of Claude Code's
  permission-matcher semantics (literal-substring globs,
  deny-before-allow, per-subcommand compound parsing) as a test helper,
  with the modeled behavior version stated; a fixture table of `git push`
  and `git commit` invocations (force forms, `+refspec`, every `main`
  destination spelling, flag-after-arg amend/squash/fixup forms,
  hook-bypass forms — `--no-verify` in any position; `git -c` and
  `git config` `core.hooksPath` spellings crossed with the push-to-main,
  force, and amend families; the `--amend -m`/`--amend -F` family; and
  `--fixup=amend:`/`--fixup=reword:` producing `amend!` subjects — and
  legitimate feature-branch operations) with expected deny/allow
  outcomes; deny-glob additions to `config/worker-settings.json`
  covering the hook-bypass spellings (including a categorical
  `git -c core.hooksPath*` / `--hooks-path` deny and end-wildcarded
  `main`-destination denies so flags after `main` cannot evade); a test
  asserting `config/worker-settings.json`'s rules against the table,
  wired into the test suite.
- **Done when:** The test fails when a deny rule covering a fixture
  evasion is removed from `config/worker-settings.json` and passes on
  the current config; each fixture row is marked load-bearing
  (expected-deny regression guard) or honest documentation of a current
  allow, and the test asserts the parsed deny-rule set is non-empty and
  errors on unparseable config; the known evasions (flag-after-arg
  amend, `HEAD:refs/heads/main`) appear with their current matcher
  outcome recorded honestly; the hook-bypass rows (`--no-verify`,
  `git -c`/`git config` hooksPath, `--amend -m`, flag-after-`main`) are
  denied under the edited config; the matcher model doc names the Claude
  Code documentation consulted and the version modeled, and those
  sources are also recorded in the kickoff brief risk register per D-4.
- **Dependencies:** none
- **Citations:** D-4 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 1 day

### Task 2 — Git hook backstop

- **Deliverables:** Tracked `githooks/` directory (distinct from the
  existing `hooks/` plugin-manifest dir) with extensionless
  portable-shell `pre-push` (reject any refspec updating
  `refs/heads/main`; fail closed on an unparseable stdin refspec),
  `pre-rebase` (reject), `prepare-commit-msg` (abort when source arg is
  `commit` with a `HEAD`-equal SHA — the detectable amend signature),
  and `commit-msg` (reject `squash!`/`fixup!`/`amend!` subjects); a
  dedicated idempotent wire step setting `core.hooksPath githooks`
  (a `scripts/` helper invoked from the local check path plus an
  explicit CI step — not `install.sh`), with the hooks no-op cleanly
  when their files are absent on a branch; the extensionless hooks added
  to `lint:shell`/`lint:fmt` (shebang enumeration); a check detecting an
  unwired or half-wired clone; `docs/CONTRIBUTING.md` /
  `docs/getting-started.md` updated for hook enforcement, human-binding,
  and the `--no-verify` escape hatch; git-fixture tests (asserting
  fixture setup succeeded before proceeding).
- **Done when:** In a fixture repo with hooks wired, `git commit --amend`
  (positions the hook can detect), `git commit --squash`/`--fixup` (any
  position), `git rebase`, and every fixture `main`-push spelling from a
  pinned minimum set (`HEAD:refs/heads/main`, `HEAD:main`,
  `+refs/heads/main`, feature branch whose upstream is main, `HEAD`
  while on main) are rejected non-zero while normal commits and
  feature-branch pushes succeed; the detection check fails on a clone
  with `core.hooksPath` unset, pointing elsewhere, or missing/
  non-executable hook files, and passes only on a fully wired clone; its
  CI behavior is a decidable predicate (CI wires-then-verifies), never a
  silent skip.
- **Dependencies:** none
- **Citations:** D-2, D-3 · REQ-A1.2, REQ-A1.3
- **Estimated effort:** 2 days

### Task 3 — Purged-identifier check

- **Deliverables:** `check:purged-identifiers` in the `check` aggregate:
  a committed seed file of SHA-256 hashes over normalized identifiers, a
  checker that tokenizes tracked text-file content (binary exclusion
  documented), normalizes identically — emitting boundary-split and
  embedded-form candidates (identifier inside a URL, `mailto:`, slug) —
  and compares hashes in a single batched pass (no per-token fork);
  documented normalization rules with in/out-of-scope reintroduction
  shapes; fail-closed on a missing/malformed/zero-hash seed file plus a
  committed minimum-real-seed count as the non-vacuity floor; an
  extension of Task 2's `commit-msg` hook screening commit messages
  against the same hashed seed list, backed by a CI-side scan over the
  PR commit-message range (reusing `check-commit-msgs.sh`'s range walk)
  so unwired clones and fork PRs are covered; a test-only seed namespace
  for fixtures distinct from the production seed file; the
  human-provisioning step documented in the check's header as a
  non-logging stdin path (never argv/history).
- **Done when:** A fixture tree containing a planted seeded token fails
  the check and a clean tree passes; a normalization-equivalent variant
  (case/separator/embedding) of a seeded token is still caught, and a
  deliberately out-of-scope variant passes (pinning the boundary both
  ways); a fixture commit whose message contains a planted token is
  rejected by both the `commit-msg` hook and the CI-side range scan; a
  missing/empty/zero-hash seed file fails the check (not a vacuous
  pass); the committed seed file contains no plaintext identifier and
  meets the minimum-seed floor; the check runs green in fork-PR CI;
  `scan:secrets` and `mise run check` pass on the result.
- **Dependencies:** 2
- **Citations:** D-5 · REQ-B1.1, REQ-B1.2, REQ-H1.3
- **Estimated effort:** 1 day

### Task 4 — Fork-PR isolation audit and workflow-posture check

- **Deliverables:** The REQ-C1.1 audit of the `pull_request` execution
  path (permissions, secret references, cache poisoning, artifact
  writes), recorded in the kickoff brief risk register with sources
  consulted, confirming or falsifying D-6; a
  `check:workflow-posture` script asserting no `pull_request_target` in
  any workflow; read-only *effective* per-job permissions (job-level
  overrides computed) on every job reachable from `pull_request`; no
  stored-secret `secrets.*` reference (excluding `secrets.GITHUB_TOKEN`)
  and no `secrets: inherit` reachable from `pull_request`, followed
  through reusable-workflow `uses:` calls; and that any `workflow_run`
  workflow holding write permissions or secrets keeps its base-branch
  filter and consumes no PR-produced artifacts; the check fails closed
  on any workflow file it
  cannot parse; fixture tests. The cache/artifact posture is covered by
  the REQ-C1.1 audit record only (D-6 accepted residual), not a standing
  assertion.
- **Done when:** The audit record exists in the brief risk register and
  names its conclusion against D-6, covering `pull_request` and
  `workflow_run` reachability (a falsifying finding is surfaced as a
  design amendment, never absorbed); fixture workflows containing
  `pull_request_target`, a non-`GITHUB_TOKEN` `secrets.*` or
  `secrets: inherit` reachable from `pull_request`, a job-level
  write-permission escalation, or an unparseable body each fail the
  check; a fixture with only `secrets.GITHUB_TOKEN` under read-only
  permissions passes, and a non-`GITHUB_TOKEN` secret in a
  push/`workflow_run`-only workflow (no `pull_request` trigger) passes;
  the repo's real workflows pass.
- **Dependencies:** none
- **Citations:** D-6 · REQ-C1.1, REQ-C1.2, REQ-H1.3
- **Estimated effort:** 1 day

### Task 5 — Transitive CI-eval exclusion

- **Deliverables:** A task-graph closure pass in
  `scripts/check-no-ci-evals.sh`: parse `mise.toml` task-graph edges
  (`depends`, `depends_post`, `wait_for`), root set = tasks invoked
  from workflow files, fail if the closure reaches an `eval:`-namespace
  task; a run-body pass scanning `mise.toml` task run bodies with the
  same invocation-form matching as the workflow pass, treating a
  run-body `mise run <task>` as an edge feeding the closure; the
  existing workflow-text pass retained; fail-closed on an unparseable or
  zero-task `mise.toml` and on zero workflow roots when workflows exist;
  the `mise.toml`-only parse boundary documented; fixture tests with
  synthetic `mise.toml` graphs.
- **Done when:** A fixture graph where a CI-run task transitively
  reaches an `eval:` task via `depends`, `depends_post`, or `wait_for`
  fails; a fixture task whose run body invokes `mise run eval:…` fails,
  as does one whose run body invokes an intermediate task that reaches
  `eval:`; an unparseable/zero-task `mise.toml` fails closed; a clean
  graph passes; the current repo passes; the guard's description
  documents all passes and the parse boundary.
- **Dependencies:** none
- **Citations:** D-7 · REQ-D1.1, REQ-H1.3
- **Estimated effort:** half day

### Task 6 — Straggler test-file split

- **Deliverables:** `test-check-instructions.sh`,
  `test-orchestrate-select.sh`, and `test-obs-consume.sh` split into
  smaller files (or slimmed where fixtures are redundant) so no
  resulting file exceeds the per-file *split target* (proposed in this
  PR from split feasibility and accepted at review — distinct from
  Task 7's enforced budget); runner discovery picks up the new files.
- **Done when:** The full suite passes with the assertion count — the
  count of emitted verdict lines, a mechanically defined metric — not
  reduced from the pre-split baseline; per-file wall-clock is measured
  across all test files (not only the three stragglers) on the
  reference runner (GitHub Actions CI) with a best-of-N to bound noise,
  and no file exceeds the accepted split target; the measured
  per-file and total times are recorded in the PR for Task 7 to budget
  against.
- **Dependencies:** none
- **Citations:** D-9 · REQ-E1.2
- **Estimated effort:** 2 days

### Task 7 — check:test-time budget gate

- **Deliverables:** Sub-second per-file timing capture in the test
  runner, written concurrency-safely under the parallel runner (each
  worker emits its own record — per-file line or temp file — with no
  shared-file append race) and persisted to a committed report path
  (not the ephemeral log dir) with positive accounting (a file with a
  verdict but no timing entry counts as a failure); a committed budget
  config (per-file and
  suite-total budgets, set from the post-split, post-fixture baseline
  plus 30–50% headroom, values recorded with derivation) as a separate
  file, not `config/defaults.yml` keys; `check:test-time` in the `check`
  aggregate ordered after `test` via `depends`, reading the report
  (never re-running the suite), hard-failing in CI and warning locally
  when a measured time is `>=` a budget; fixture tests.
- **Done when:** A fixture timing report at-or-over the per-file or
  total budget fails the check and an under-budget report passes; a
  report missing an entry for a discovered file, or an empty/malformed
  report, fails closed; the real suite runs green under the committed
  budgets in CI without a second suite invocation; the budget file's
  header documents the bump-consciously rule and the CI-hard/local-warn
  split. Task 11 is deliberately *not* a dependency (that would cycle,
  since Task 11 depends on Task 7): Task 11's own registration-check
  fixture is the one fixture landing after this budget is set, so if it
  pushes the suite-total over budget, Task 11 applies the conscious bump
  in its own PR (the D-8 discipline), since Task 11 runs last and sees
  the true total.
- **Dependencies:** 1, 2, 3, 4, 5, 6, 9, 10
- **Citations:** D-8 · REQ-E1.1, REQ-H1.3
- **Estimated effort:** 1 day

### Task 8 — Performance-lens doctrine amendment

- **Deliverables:** `doctrine/discovery-rigor.md` amended so the
  Performance lens explicitly names test/CI ergonomics (suite
  wall-clock, CI latency) a lens target for reviewers, with the
  whole-system framing (not diff-scoped only) and noting the mechanical
  catch is REQ-E1.1's gate; the amendment cited back to this bundle.
- **Done when:** The lens text names the target; `mise run check`
  passes; the change is recorded in this bundle's Changelog as the
  REQ-E1.3 delivery.
- **Dependencies:** none
- **Citations:** D-1 · REQ-E1.3
- **Estimated effort:** half day

### Task 9 — Drift tethers

- **Deliverables:** `check:doctrine-index` asserting every
  `doctrine/*.md` (minus README) has a `doctrine/README.md` index row
  (fail closed on a missing README, unparseable index table, or empty
  doctrine-doc set); a test parsing the backend-capability-contract
  prose table and asserting both `caps_for()` in
  `scripts/orchestrate-backends.sh` and `docs/fleet.md`'s
  backend-capability table match it under the specified normalization
  contract (`n/a`↔`na`, annotations/backticks stripped), failing closed
  if either side parses to zero rows; `check-options-reference.sh`
  widened to compare `docs/fleet.md`'s knobs-table defaults against
  `config/defaults.yml` with a symmetric zero-row guard on the
  fleet-table side; fixture tests for each (including a per-knob
  divergence proving all six fleet knobs are individually tethered);
  all wired into the `check` aggregate.
- **Done when:** Each tether fails on a fixture divergence (unindexed
  doctrine doc, mismatched capability row in the doc/`caps_for()`/
  fleet-table triangle, each of the six drifted knob defaults) and
  passes on the current tree; a zero-row parse on any side fails closed
  rather than passing; removing a `doctrine/README.md` row or editing a
  `caps_for()` value locally makes `mise run check` fail.
- **Dependencies:** none
- **Citations:** D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-H1.3
- **Estimated effort:** 1 day

### Task 10 — Template lint scope and CDPATH check

- **Deliverables:** `templates/**/*.md` added to the `lint:md` glob,
  with a scoped `templates/.markdownlint.jsonc` only if placeholder
  syntax requires it, plus a committed assertion that the resolved
  `lint:md` target set includes a `templates/**/*.md` path (so a future
  glob narrowing fails a test, not silently passes); a CDPATH
  house-pattern check flagging `cd` inside command substitutions in
  `scripts/`, `tests/`, and `githooks/` files lacking a top-level
  `unset CDPATH`, enumerating by shebang (so extensionless hooks are
  covered) and failing closed if the enumeration yields zero files (a
  broken enumeration, not a clean tree), wired into the `check`
  aggregate, its doc noting the CDPATH=. regression-test convention with
  one representative cd-resolving script exercised under `CDPATH=.`;
  fixture tests (including an offending extensionless hook and the
  zero-enumeration case).
- **Done when:** `lint:md` covers the template READMEs, the target-set
  assertion passes, and `mise run check` passes; a fixture script (and
  an extensionless hook) with `$(cd ...)` and no `unset CDPATH` fails
  the check, a zero-file enumeration fails closed, and the current tree
  passes.
- **Dependencies:** none
- **Citations:** D-11, D-12 · REQ-G1.1, REQ-G1.2
- **Estimated effort:** half day

### Task 11 — Guard-catalog entries and registration sweep

- **Deliverables:** Pinned-action-freshness entry in
  `doctrine/guard-catalog.md` and `config/guard-catalog.yaml`
  (signal-only, no auto-bump; degraded-network posture = loud unknown),
  plus catalog entries for the generalizable guard classes this spec
  shipped (test-time budget, CDPATH house pattern); each entry declares
  `category` and core-vs-breadth, with the `doctrine/guard-catalog.md`
  §"Guard categories" enum amended where no category fits and
  `tests/test-builder-guards.sh` kept green; a standing registration
  check asserting every `check:`/`lint:`/`scan:` task is wired into the
  `check` aggregate (with fixtures: an unregistered guard fails, and a
  zero-task parse of `mise.toml` fails closed rather than passing
  vacuously); the
  quality-gate enumeration in `docs/CONTRIBUTING.md` and the
  guard-catalog §"Dogfooding" list updated for the new guards; a
  registration sweep confirming every guard from Tasks 1–5, 7, 9, 10 is
  wired and documented.
- **Done when:** The catalog prose and yaml entries exist with declared
  category/placement and pass the (new or existing) schema check; the
  standing registration check fails on a fixture unregistered guard and
  passes on the real tree; `docs/CONTRIBUTING.md` and the dogfooding
  list name the new guards; a written sweep result in the PR maps each
  shipped guard to its `check` aggregate entry and doc location, with
  none missing.
- **Dependencies:** 1, 2, 3, 4, 5, 7, 9, 10
- **Citations:** D-13 · REQ-H1.1, REQ-H1.2, REQ-H1.3
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
