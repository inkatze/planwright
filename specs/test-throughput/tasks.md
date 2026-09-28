# Test throughput — Tasks

**Status:** Draft
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
  the core count, the one-warning unpooled fallback, per-file timing that
  starts after the ticket is held, and a wait column in the timing report;
  the runner's header documenting the new variables and the
  largest-capacity-wins bound; the runner added to `lock-lib.sh`'s
  lock-holder list; tests covering each behavior.
- **Done when:** a test running two concurrent runner invocations against
  one pool with capacity K records at most K test files executing at any
  instant; a test killing a runner mid-file shows the next run reclaims
  that ticket; tests show a symbolic-link pool path and a foreign-owned one
  each produce one warning and an unpooled run that still passes; the
  timing report carries the wait column and `check:test-time` reads only
  the execution time; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-4 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-A1.7
- **Estimated effort:** 2 days

### Task 2 — Runner scratch-directory failure as an environment error

- **Deliverables:** `scripts/run-tests.sh` checking its scratch directory
  around each file and stopping with exit 2 and a message naming the cause
  when it is gone or unwritable; a test removing the directory mid-run.
- **Done when:** the test shows exit 2 with the named cause and no test
  file recorded as failed; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-10 · REQ-D1.3
- **Estimated effort:** half day

### Task 3 — bash 3.2 parse fixes

- **Deliverables:** `scripts/check-no-ci-evals.sh` and
  `scripts/tower-queue.sh` rewritten at the constructs that misparse under
  bash 3.2, behavior unchanged.
- **Done when:** both scripts pass `bash -n` and `bash --posix -n` under
  bash 3.2 (macOS `/bin/bash` or the `bash:3.2` image), their existing
  tests pass on macOS and on CI, and `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.1
- **Estimated effort:** half day

### Task 4 — bash 3.2 regression guards

- **Deliverables:** a CI step in `.github/workflows/ci.yml` parsing every
  repository shell script inside the `bash:3.2` image pinned by digest
  (`bash -n` for bash shebangs, `bash --posix -n` for `sh` shebangs),
  failing on any parse error; a local lint wired into `mise run check`
  flagging the constructs Task 3 fixed; fixtures for both.
- **Done when:** the CI step passes on the branch and fails on a fixture
  script carrying either construct Task 3 fixed; a test asserts the step's
  image reference carries a `@sha256:` digest and fails on a fixture
  without one; the lint fails on the same fixtures and passes on the tree;
  `mise run check` passes.
- **Dependencies:** 3
- **Citations:** D-11 · REQ-E1.6, REQ-E1.7
- **Estimated effort:** 1 day

### Task 5 — Shebang-honoring invocation rule and check

- **Deliverables:** the invocation rule stated beside the existing
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
  where the writer is planwright's; otherwise the planwright-owned
  worktree-creation paths running `scripts/wire-githooks.sh`, and an
  observation naming the outside writer; `scripts/check-githooks.sh`
  unchanged in its detect-only behavior.
- **Done when:** a test creating a worktree through each planwright-owned
  creation path, from a clone whose `core.hooksPath` was set absolute or
  cleared, shows `check:githooks` passing inside the new worktree; the PR
  body names the writer or states the evidence that rules out each
  candidate examined; `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-13 · REQ-E1.3
- **Estimated effort:** 1 day

### Task 7 — Symlinked `TMPDIR` and Graphviz 15 test fixes

- **Deliverables:** `tests/test-fleet-dispatch-worktree.sh` canonicalizing
  its temp paths; `tests/test-spec-graph.sh` keeping its `dot` stub first
  with a real `dot` installed.
- **Done when:** the first test passes with `TMPDIR` pointed through a
  symbolic link; the second passes with a real Graphviz `dot` on `PATH`
  (exercised on a host that has one, recorded in the PR body) and on CI;
  `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-11 · REQ-E1.4, REQ-E1.5
- **Estimated effort:** half day

### Task 8 — Busy-machine sweep over elapsed-time assertions

- **Deliverables:** a shared poll-until-deadline test helper reporting the
  elapsed time on timeout; the sweep's list of every elapsed-time
  assertion in the suite, recorded in the PR body with the search that
  found them; each converted to the helper; the search re-run after
  conversion, its result recorded.
- **Done when:** every assertion the sweep lists uses the helper, and the
  re-run search finds none outside it; the
  converted tests pass under an artificial load test (the suite run with
  several times the core count of busy loops alongside) where they failed
  before; `mise run check` passes.
- **Dependencies:** 4
- **Citations:** D-10 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 2 days

### Task 9 — Profile the slowest test files

- **Deliverables:** a profile of the slowest files by the timing report, on
  the operator's macOS host and on GitHub CI, attributing wall-clock to
  process launches, fixture setup, sleeps and waits, and production-script
  time; the measured user-lookup verdict; the measurements in the PR body;
  one observation or gated deferral per production-side cause, naming the
  owning bundle; a list of test-side causes for Task 9.1.
- **Done when:** the PR body carries the attribution and the user-lookup
  verdict with the measurements behind them; every production-side cause
  has its observation UID or deferral named in the PR body; the test-side
  list is recorded for Task 9.1.
- **Dependencies:** none
- **Citations:** D-9 · REQ-C1.1, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 2 days

### Task 9.1 — Test-side speed fixes

- **Deliverables:** each test-side cause on Task 9's list fixed or declined
  with a recorded reason, including the sweep converting direct execution
  of copied or fabricated script fixtures to interpreter invocation.
- **Done when:** the PR body dispositions every cause on Task 9's list and
  shows before-and-after timings for each fixed file; no test directly
  executes a copied or fabricated script fixture; `mise run check` passes.
- **Dependencies:** 9, 4
- **Citations:** D-9 · REQ-C1.2
- **Estimated effort:** 2 days

### Task 10 — The `full_suite_evidence` setting in `/execute-task`

- **Deliverables:** the `full_suite_evidence` key (`local` default,
  `remote-ci` opt-in) in `config/defaults.yml` and the options reference;
  `scripts/await-pr-ci.sh` (bounded foreground polling of the PR's checks,
  one verdict of green, red, pending past bound, or no CI; output
  sanitized); `/execute-task` under `remote-ci` running the targeted check
  per change, opening the draft PR once the first implementation passes it,
  pushing each iteration, taking green CI on the current head as the
  full-suite evidence, and falling back to the pooled local suite on "no
  CI", recording which evidence it used; tests for the helper and the
  setting's resolution.
- **Done when:** review-effectiveness Task 6's
  `scripts/check-diff-scoped.sh` is on `main` and is the targeted check
  used; helper tests cover each verdict against recorded check fixtures; a fixture unit under `remote-ci` shows the early draft PR and no
  convergence report without green CI on the current head; under `local`
  the skill's behavior is unchanged; `mise run check` passes.
- **Dependencies:** 1, 4
- **Citations:** D-1, D-5 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5
- **Estimated effort:** 3 days

### Task 11 — The known-environmental list

- **Deliverables:** the list format and location
  (`<primary checkout>/.claude/planwright.local/known-environmental.tsv`,
  found through git's common directory); a reader validating each field
  as data; `/execute-task` reporting a matching local failure as known
  environmental without re-proving it, refusing the match for CI failures
  and for any test the targeted check selects for the diff, proposing new entries
  for operator confirmation (Awaiting-input when unattended), and flagging
  entries whose test passed; tests for the reader and each refusal.
- **Done when:** tests show a matching failure reported as known
  environmental; a CI failure, and failures in tests the targeted check
  selected for the diff, each refused the match; a malformed or
  path-escaping entry rejected; no code path writing an entry without
  confirmation; a passing listed test flagged; `mise run check` passes.
- **Dependencies:** 10
- **Citations:** D-6 · REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-B1.9
- **Estimated effort:** 2 days

### Task 12 — Portable detached long-run recipe

- **Deliverables:** a helper running the suite detached with `nohup` and a
  background job to fresh per-run log and exit-code paths, confirming the
  log exists and the runner is alive before returning, with a status verb
  (running, finished with its code, never started); the `/execute-task` CI
  step pointing at it for runs past a tool call's limit.
- **Done when:** tests show a launch whose runner cannot start reports
  failure rather than success, the status verb reports each state, and an
  earlier run's log survives a new launch; `mise run check` passes.
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
  reading PR CI per iteration; `mise run check` passes.
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
- **Apply the test-time budgets to the macOS CI job.** Once
  universal-binary's macOS CI job exists, run `check:test-time` there in CI
  mode so macOS speed regressions fail CI, rather than setting a
  hand-measured local target. Confidence: high.
  **Gate:** universal-binary Task 4.1 completed (the macOS job runs on every
  pull request).
  Citations: D-9.

## Out of scope

(none yet)
