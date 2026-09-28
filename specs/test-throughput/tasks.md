# Test throughput — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-28
**Format-version:** 2
**Execution:** derived — see the status render

Ordering intent, so nobody "fixes" it: the ticket pool (Task 1) carries no
edge to the bash 3.2 guard, so the most urgent relief is not held behind
it; every other task that edits shell depends on Task 4, so its changes
land under the guard (drafting-session decision, 2026-09-28). Dependency
edges cross no bundle boundary; where a task needs another bundle's work
first, its `Done when:` names that precondition (D-7).

## Tasks

### Task 1 — Machine-wide ticket pool in the test runner

- **Deliverables:** `scripts/run-tests.sh` taking one ticket per test file
  from the pool at `${XDG_STATE_HOME:-$HOME/.local/state}/planwright/test-slots`
  (owner-only, refused when a symbolic link or not owned by the user,
  `PLANWRIGHT_TEST_SLOT_DIR` override) built on `scripts/lock-lib.sh`, with
  dead-holder reclaim, capacity from `PLANWRIGHT_TEST_SLOTS` defaulting to
  the core count (a malformed value taking `PLANWRIGHT_TEST_JOBS`'s fallback
  and clamp, with the pool warning), the one-warning unpooled fallback,
  per-file timing that starts after the ticket is held, the wait recorded
  in the timing report, and a named, runner-internal environment mark that
  makes a nested runner run unpooled; the timing report's version bumped,
  with `scripts/check-test-time.sh`, `tests/test-check-test-time.sh`, and
  the timing sections of `docs/CONTRIBUTING.md` updated to read it (the
  suite-wall row documented as including waiting); the runner's header
  documenting the new variables, the internal mark, and the
  largest-capacity-wins bound; the runner added to `lock-lib.sh`'s
  lock-holder list; tests covering each behavior.
- **Done when:** a test running two concurrent runner invocations against
  one pool with capacity K records at most K test files executing at any
  instant and reaches K at some instant; a test with runs at capacities K1
  below K2 records at most K2; with no override the capacity equals the
  probed core count, with `PLANWRIGHT_TEST_SLOTS` set it equals that value,
  and with `PLANWRIGHT_TEST_JOBS` below it one run never exceeds its job
  count; a test killing a runner mid-file shows the next run reclaims that
  ticket; with no fleet state, no plugin install, and no config the pool
  resolves and works; a fresh pool directory is created owner-only; tests
  show a symbolic-link pool path and a foreign-owned one each produce one
  warning and an unpooled run that still passes; the timing report carries
  the wait and `check:test-time` reads only the execution time; a test
  running the runner inside a pooled test file at capacity 1 shows the
  inner run completing unpooled with no pool warning;
  `scripts/check-lock-primitive.sh` reports the runner clean and
  `tests/test-lock-lib.sh` passes with the runner on the holder list;
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-4 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8
- **Estimated effort:** 2 days

### Task 2 — Runner scratch-directory failure as an environment error

- **Deliverables:** `scripts/run-tests.sh` checking its scratch directory
  around each file and stopping with exit 2 and a message naming the cause
  when it is gone or unwritable; the runner's header updated where it
  promises every file runs to completion, and its exit-2 list extended;
  tests removing the directory mid-run and making it unwritable mid-run.
- **Done when:** both tests show exit 2 with the named cause and no test
  file recorded as failed; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-10 · REQ-D1.3
- **Estimated effort:** half day

### Task 3 — bash 3.2 parse fixes

- **Deliverables:** `scripts/check-no-ci-evals.sh` and
  `scripts/tower-queue.sh` rewritten at the constructs that misparse under
  bash 3.2, behavior unchanged.
- **Done when:** both scripts pass `bash -n` and `bash --posix -n` under
  bash 3.2 (macOS `/bin/bash` or the `bash:3.2` image), both checked by
  this task directly; their existing tests pass on CI and on the operator's
  macOS host, the macOS run recorded in the PR body; `mise run check`
  passes.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.1
- **Estimated effort:** half day

### Task 4 — bash 3.2 regression guards

- **Deliverables:** a CI step in `.github/workflows/ci.yml` parsing every
  tracked shell file inside the `bash:3.2` image pinned by digest, dialect
  from the shebang else the `# shellcheck shell=` directive (`bash -n` for
  `bash`, `bash --posix -n` for `sh`), failing on any parse error and on a
  tracked `.sh` file declaring neither, and excluding one fixtures
  directory that holds its own misparsing fixtures; a local lint wired into
  `mise run check` flagging the constructs Task 3 fixed; fixtures for both.
- **Done when:** the CI step passes on the branch; a test drives the step
  against the fixtures directory and shows it failing on a fixture carrying
  each construct Task 3 fixed and on a fixture `.sh` file declaring no
  dialect; the step's file list includes the shebang-less libraries and the
  extension-less git hooks; a test asserts the step's image reference
  carries a `@sha256:` digest and fails on a fixture without one; the lint
  fails on each construct fixture and passes on the tree; `mise run check`
  passes.
- **Dependencies:** 3
- **Citations:** D-11 · REQ-E1.6, REQ-E1.7
- **Estimated effort:** 1 day

### Task 5 — Shebang-honoring invocation rule and check

- **Deliverables:** the invocation rule stated in the existing
  script-invocation doctrine; every skill instruction that runs a
  bash-shebanged script through `sh` corrected; a check in
  `mise run check` reading each script's shebang and flagging such
  instructions; fixtures for the check.
- **Done when:** the check passes on the tree and fails on a fixture skill
  that runs a bash-shebanged script through `sh`; `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-12 · REQ-E1.2
- **Estimated effort:** 1 day

### Task 6 — Find the `core.hooksPath` writer and wire fresh worktrees

- **Deliverables:** an investigation, recorded in the PR body, naming what
  rewrites or clears the clone's `core.hooksPath` and the evidence; the fix
  where the writer is planwright's, or an observation naming an outside
  writer; every planwright-owned worktree-creation path running
  `scripts/wire-githooks.sh` whoever the writer is, the paths listed in
  the PR body with the search that found them; `scripts/check-githooks.sh`
  unchanged in its detect-only behavior.
- **Done when:** a test creating a worktree through each listed creation
  path, from a clone whose `core.hooksPath` was set absolute or cleared,
  shows `check:githooks` passing inside the new worktree;
  `scripts/check-githooks.sh` still fails on an absolute value; the PR body
  names the writer or states the evidence that rules out each candidate
  examined; `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-13 · REQ-E1.3
- **Estimated effort:** 1 day

### Task 7 — Symlinked `TMPDIR` and Graphviz 15 test fixes

- **Deliverables:** `tests/test-fleet-dispatch-worktree.sh` canonicalizing
  its temp paths; `tests/test-spec-graph.sh` keeping its `dot` stub first
  with a real `dot` installed.
- **Done when:** the first test passes with `TMPDIR` pointed through a
  symbolic link; the second passes on a host with a real Graphviz `dot` on
  `PATH` whose `dot -V` reports version 15, the run and that output recorded
  in the PR body, and passes on CI, which exercises the stub only;
  `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-11 · REQ-E1.4, REQ-E1.5
- **Estimated effort:** half day

### Task 8 — Busy-machine sweep over elapsed-time assertions

- **Deliverables:** a shared poll-until-deadline test helper reporting the
  elapsed time on timeout, its default deadline documented in the helper;
  the sweep's list of every elapsed-time assertion in the suite, recorded
  in the PR body with the search that found them; each wait for an event
  converted to the helper, and each minimum-elapsed assertion left
  unconverted listed with its reason; the search re-run after conversion,
  its result recorded.
- **Done when:** every wait-for-an-event assertion the sweep lists uses the
  helper, and the re-run of the recorded search finds none outside it and
  the listed minimum-elapsed exceptions; the converted tests pass under an
  artificial load test (the suite run with several times the core count of
  busy loops alongside, the factor recorded in the PR body), and the PR
  body records the unconverted tests' result under the same load;
  `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-10 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 2 days

### Task 9 — Profile the slowest test files

- **Deliverables:** a profile of the slowest files (per REQ-C1.1's
  cumulative-half rule, from an idle full run on each host) on the
  operator's macOS host and on GitHub CI, attributing wall-clock to process
  launches, fixture setup, sleeps and waits, and production-script time;
  the measured user-lookup verdict and its test-side mitigation where one
  exists; the first-execution stall measured with and without the
  developer-tool exemption, attended and fleet-dispatched, with its verdict
  and, where the exemption covers both, the setup step documented in
  `docs/CONTRIBUTING.md`; the measurements in the PR body; one observation
  or gated deferral per production-side cause, naming the owning bundle; a
  list of test-side causes for Task 9.1.
- **Done when:** the PR body carries the selected file set with the rule
  applied, the attribution, the user-lookup verdict with any mitigation,
  and the first-execution-stall verdict, with the measurements behind them;
  where the exemption covers both, `docs/CONTRIBUTING.md` carries the setup
  step; every production-side cause has its observation UID or deferral
  named in the PR body, and the diff touches no production script for a
  performance reason; the test-side list is recorded for Task 9.1;
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-9, D-14 · REQ-C1.1, REQ-C1.3, REQ-C1.4, REQ-C1.5
- **Estimated effort:** 2 days

### Task 9.1 — Test-side speed fixes

- **Deliverables:** each test-side cause on Task 9's list fixed or declined
  with a recorded reason, including the sweep converting a test's own
  direct execution of copied or fabricated script fixtures to interpreter
  invocation (PATH shims excluded, per REQ-C1.5).
- **Done when:** the PR body dispositions every cause on Task 9's list and
  shows before-and-after timings for each fixed file; the PR body records
  the search for a test directly executing a copied or fabricated fixture
  and its empty result; `mise run check` passes.
- **Dependencies:** 9, 4
- **Citations:** D-9 · REQ-C1.2
- **Estimated effort:** 2 days

### Task 9.2 — Warmed-shim helper and executable-fixture lint

- **Deliverables:** a shared test helper that writes one executable per
  run, warms it once, and gives each shim as a symbolic link to it with
  its behavior in a sourced data file; every test that marks a file
  executable migrated to the helper; a lint in `mise run check` flagging a
  test that marks a file executable outside it; fixtures for the lint.
- **Done when:** Task 9's PR records that the developer-tool exemption
  falls short of REQ-C1.5's threshold for attended runs or for
  fleet-dispatched workers; the PR body shows, on the operator's macOS
  host, the stall paid once per run rather than once per shim, with
  before-and-after suite timings; the lint passes on the tree and fails on
  a fixture test marking a file executable directly; `mise run check`
  passes.
- **Dependencies:** 9, 9.1, 4
- **Citations:** D-14 · REQ-C1.5
- **Estimated effort:** 3 days

### Task 10 — The `full_suite_evidence` setting in `/execute-task`

- **Deliverables:** the `full_suite_evidence` key (`local` default,
  `remote-ci` opt-in) and the `pr_ci_wait` key (default `30m`, per head) in
  `config/defaults.yml` and the options reference, both resolved through
  `scripts/resolve-config-knob.sh`; `scripts/await-pr-ci.sh` with a usage
  header documenting its verdicts and exit codes (bounded foreground
  polling of the head's checks judged by `rl_ci_state`; one verdict of
  green, red, pending past bound, or no CI; no CI decided by the local
  no-remote, no-`gh`, and no-`pull_request`-trigger checks or by a
  no-positive-result verdict persisting past the 3-minute grace window;
  `too-many` and any failed read halting to Awaiting input; output
  sanitized); `skills/execute-task/SKILL.md` amended so that under
  `remote-ci` the parent skill (never a per-step session) opens the early
  draft PR, carved out of its PR-is-the-terminal-step rule, runs the
  targeted check per change, pushes each iteration, pushes the review
  loop's fixes and the sync with main, and takes green CI on that final
  pushed head as the full-suite evidence, re-polling a pending run until
  `pr_ci_wait` is spent and then halting to Awaiting input, carrying
  `Convergence: pending` in the early PR body until the handoff replaces
  it, and falling back to the pooled local suite on "no CI" with the
  evidence used recorded in the convergence summary; the setting read once
  at the unit's pre-flight; tests for the helper and both settings'
  resolution.
- **Done when:** review-effectiveness Task 6's
  `scripts/check-diff-scoped.sh` is on `main` and is the targeted check
  used; helper tests cover each verdict against recorded check fixtures,
  each call returning inside its bound, including a head with no checks
  registered reading pending inside the grace window and no CI after it, a
  no-remote fixture reading no CI, and a failed read and a `too-many` read
  each halting; the helper sources `rl_ci_state` rather than parsing checks
  itself; both keys resolve to their defaults with no overlay, to an
  overlay's value when set, and to the default with one warning when
  malformed, and the options-reference guard passes with both documented;
  a fixture unit under `remote-ci` shows the targeted check run per change,
  the early draft PR carrying `Convergence: pending` until the handoff
  replaces it, no convergence report without green CI on the final pushed
  head, the no-CI fallback converging on the local suite with its evidence
  recorded, and CI pending past `pr_ci_wait` halting to an Awaiting-input
  entry; a setting changed mid-unit takes effect only at the next unit's
  pre-flight; under `local` a fixture unit's recorded steps match the same
  unit run before the change; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-1, D-5 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5
- **Estimated effort:** 3 days

### Task 11 — The known-environmental list

- **Deliverables:** the list format and location
  (`<primary checkout>/.claude/planwright.local/known-environmental.tsv`,
  found through git's common directory), documented for operators in
  `docs/CONTRIBUTING.md`; a reader validating each field as data, warning
  once and treating the list as empty where no checkout sits above the
  common directory; the skill's single list writer, adding or removing an
  entry only on the operator's confirmation, by temporary file and rename;
  `/execute-task` under `remote-ci` only reporting a matching local failure
  (a case matched exactly on the runner's per-case failure label) as known
  environmental without re-proving it, refusing the match for CI failures
  and for any test the targeted check selects for the diff, proposing new
  entries for operator confirmation (an Awaiting-input entry when
  unattended), and flagging entries whose test passed; tests for the reader,
  the writer, and each refusal.
- **Done when:** tests show a matching failure reported as known
  environmental, at file level and at case level on an exact label match,
  with the list found from a worktree through git's common directory; under
  `local` the list is not consulted; a CI failure, and failures in tests
  the targeted check selected for the diff, each refused the match; a
  malformed or path-escaping entry rejected; a bare-primary fixture warning
  once and matching nothing; the writer adds or removes an entry only on a
  confirmation input, and an unattended proposal yields an Awaiting-input
  entry with the list unchanged; a passing listed test flagged;
  `mise run check` passes.
- **Dependencies:** 10
- **Citations:** D-6 · REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-B1.9
- **Estimated effort:** 2 days

### Task 12 — Portable detached long-run recipe

- **Deliverables:** a helper, with a usage header, running the suite
  detached with `nohup` and a background job to fresh per-run log and
  exit-code paths, confirming the log exists and the runner is alive before
  returning, with a status verb (running, finished with its code, never
  started), reusing `scripts/fleet-dispatch-headless.sh`'s
  detach-and-handshake step where it can be shared, or recording in the PR
  body why it misfits; `skills/execute-task/SKILL.md`'s CI step running
  every full local suite through it.
- **Done when:** tests show a launch whose runner cannot start reports
  failure rather than success, the status verb reports each state, an
  earlier run's log survives a new launch, and the helper passes on the
  Linux CI runner without `setsid`; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-8 · REQ-B1.10
- **Estimated effort:** 1 day

### Task 13 — Review-loop wiring and planwright's `remote-ci` value

- **Deliverables:** the review loop (the nested `/polish` and
  `/self-review` convergence) taking PR CI on the iteration's pushed head as
  its per-iteration full suite under `remote-ci`, with the diff-scoped
  check per fix unchanged; `.claude/planwright.yml` setting
  `full_suite_evidence: remote-ci` for this repository.
- **Done when:** review-effectiveness's full-suite requirement has been
  amended through its own delta sign-off to accept PR CI, and that
  amendment is on `main`; a fixture unit under `remote-ci` shows the loop
  reading PR CI per iteration; `full_suite_evidence` resolves to
  `remote-ci` in this repository; `mise run check` passes.
- **Dependencies:** 10, 11
- **Citations:** D-1, D-7 · REQ-B1.11
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Task 13** — parked until review-effectiveness is amended to accept PR
  CI as the review loop's per-iteration full suite. Confidence: high.
  **Gate:** review-effectiveness's delta re-sign-off amending its
  full-suite-per-iteration requirement to accept the PR's CI run on the
  iteration's pushed head is recorded and merged to main.
  Citations: D-7, REQ-B1.11.
- **Task 9.2** — parked until the profile shows the developer-tool
  exemption falls short. Confidence: medium.
  **Gate:** Task 9's PR records that the developer-tool exemption falls
  short of REQ-C1.5's threshold for attended runs or for fleet-dispatched
  workers, and that PR is merged to main.
  Citations: D-14, REQ-C1.5.
- **Apply the test-time budgets to the macOS CI job.** Once
  universal-binary's macOS CI job exists, run `check:test-time` there in CI
  mode so macOS speed regressions fail CI, rather than setting a
  hand-measured local target. Confidence: high.
  **Gate:** universal-binary Task 4.1 completed (the macOS job runs on every
  pull request).
  Citations: D-9.

## Out of scope

(none yet)
