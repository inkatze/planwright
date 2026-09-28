# Test throughput — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-28
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` for the runner, the helpers, the guards, and the
fixtures, all run by `mise run check` in the repository CI, with the bash
3.2 parse step running as its own CI step; `[Gherkin]` for the
`/execute-task` behaviors a fixture unit exercises end to end, recorded in
the PR body; `[manual]` for the macOS-host measurements and the
real-Graphviz run, which need the operator's machine because the CI runner
is Linux; `[design-level]` where the artifact's content is the
verification.

## REQ-A — Machine-wide test ticket pool

### REQ-A1.1 — Concurrent runs share one bound [test]

Two runner invocations started together against one pool (via
`PLANWRIGHT_TEST_SLOT_DIR`) with capacity K, over a fixture suite whose
files record their start and end instants: the recorded intervals never
overlap more than K deep.

### REQ-A1.2 — Capacity default and override [test]

With no override the pool capacity equals the core count the runner
probes; with `PLANWRIGHT_TEST_SLOTS` set it equals that value; with
`PLANWRIGHT_TEST_JOBS` below the capacity a single run never exceeds its
job count.

### REQ-A1.3 — Dead holders are reclaimed [test]

A runner killed while holding tickets; the next run over the same pool
reaches full concurrency and completes, and the killed run's tickets are
cleared.

### REQ-A1.4 — No fleet, no config, and a broken pool degrade gracefully [test]

With no fleet state, no plugin install, and no config, the pool resolves
and works. With an unwritable pool directory the run prints exactly one
warning naming the cause, runs unpooled, and its verdict is the suite's
own.

### REQ-A1.5 — Built on the shared lock primitive [test + design-level]

`check:lock-primitive` passes over the runner, and the runner appears on
`lock-lib.sh`'s lock-holder list, which `tests/test-lock-lib.sh` pins
against the tree.

### REQ-A1.6 — Waiting is not test time [test]

A fixture file run while the pool is saturated for a known interval: its
timing-report execution time excludes the wait, the wait column records
it, and `check:test-time` reads the execution time only.

### REQ-A1.7 — Pool location is owner-only and refuses hostile paths [test]

A fresh pool directory is created owner-only under the home state path; a
symbolic link at the path, and a directory owned by another user
(simulated through the ownership check's injectable probe), each produce
the one-warning unpooled fallback.

## REQ-B — CI-first worker verification

### REQ-B1.1 — The setting resolves with a preserving default [test]

`full_suite_evidence` resolves to `local` with no overlay, to `remote-ci`
when an overlay sets it, and a malformed value follows the config
layer's malformed-value policy; the options reference documents it
(checked by the options-reference guard).

### REQ-B1.2 — Targeted check while iterating [Gherkin]

Given a fixture unit under `remote-ci`, when `/execute-task` validates a
change, then it runs the tests touching the changed files and the linters,
and not the full suite. Recorded in Task 10's PR body.

### REQ-B1.3 — Early draft PR and green CI on the current head [Gherkin]

Given a fixture unit under `remote-ci`, when the first implementation
passes its targeted check, then the draft PR opens and each later
iteration is pushed; when CI on the current head is red or pending, then
no convergence is reported. Recorded in Task 10's PR body.

### REQ-B1.4 — Local fallback when no PR CI exists [test + Gherkin]

`await-pr-ci.sh` prints "no CI" for a fixture with no remote and for one
whose PR has no checks; given that verdict, `/execute-task` runs the full
local suite through the pool and records the evidence used.

### REQ-B1.5 — Bounded polling to a verdict [test]

`await-pr-ci.sh` against recorded check fixtures prints green, red, and no
CI for the matching fixtures, and "pending past bound" for a fixture that
never completes, each call returning inside its bound.

### REQ-B1.6 — Listed failures are reported, not re-proven [test]

A fixture failure matching a list entry (file-level, and case-level where
a case is named) is reported as known environmental and never reaches the
baseline re-run or the logic classification; the list is found from a
worktree through git's common directory.

### REQ-B1.7 — The list never excuses CI or changed code [test]

A PR CI failure on a listed test, and a local failure in a listed test
the targeted check selected for the diff (because the diff changed the
test, and because it changed a script the test covers): each is treated as
an ordinary failure.

### REQ-B1.8 — Entries are proposed, never self-written [test + Gherkin]

No code path in the reader or the skill's helpers writes the list; given a
failure that also fails on a clean baseline, the worker's output carries a
proposal (unattended: an Awaiting-input entry), and the file is unchanged.

### REQ-B1.9 — Passing listed tests are flagged [test]

A listed test that passes locally appears in the worker's report as a
removal candidate.

### REQ-B1.10 — Detached runs prove they started [test]

The helper reports failure for a launch whose runner cannot start; the
status verb reports running, finished with its code, and never started for
the matching fixtures; a previous run's log survives a new launch.

### REQ-B1.11 — Review-loop wiring waits on the amendment [design-level]

Task 13 is parked under `## Deferred` with the free-text gate naming the
review-effectiveness amendment, and its `Done when:` names that
precondition; the drain pass surfaces the gate verbatim.

## REQ-C — Slow-test profiling and test-side speedups

### REQ-C1.1 — Attribution is recorded [manual + design-level]

Task 9's PR body carries per-file attribution across the named causes for
the slowest files, on the operator's macOS host and on GitHub CI, with the
measurements behind it; the operator reviews it at PR review.

### REQ-C1.2 — Test-side causes dispositioned; no direct fixture execution [manual + design-level]

Task 9.1's PR body records the sweep's search for direct execution of
copied or fabricated script fixtures, with its result (none remaining),
and dispositions every test-side cause with before-and-after timings; the
operator reviews both at PR review.

### REQ-C1.3 — Production causes routed, not fixed [design-level]

Every production-side cause in Task 9's PR body names its observation UID
or deferral and the owning bundle, and the task's diff touches no
production script for a performance reason.

### REQ-C1.4 — User-lookup verdict measured [manual]

Task 9's PR body records the measured verdict on user or group lookup
amplification on the operator's macOS host, with the measurement method.

## REQ-D — Tests that hold up on a busy machine

### REQ-D1.1 — Poll until a generous deadline [test]

The helper's own tests: a condition that becomes true late but inside the
deadline passes; one that never does fails with the observed elapsed time
in the message.

### REQ-D1.2 — The sweep covers every elapsed-time assertion [test + manual]

Task 8's PR body records the sweep's search, its list, and a re-run of the
search after conversion finding none outside the helper; the converted
tests pass under the artificial-load run where they failed before.

### REQ-D1.3 — Runner breakage is an environment error [test]

A fixture that removes the runner's scratch directory mid-run: the runner
exits 2 naming the cause and records no test as failed.

## REQ-E — macOS portability fixes and guards

### REQ-E1.1 — The two scripts parse under bash 3.2 [test]

The Task 4 CI step parses both scripts under bash 3.2 as `bash` and in
POSIX mode; their existing tests pass in CI and on the operator's macOS
host.

### REQ-E1.2 — Invocation honors the shebang [test]

The Task 5 check passes on the tree and fails on a fixture skill running a
bash-shebanged script through `sh`.

### REQ-E1.3 — Fresh worktrees pass `check:githooks` [test + design-level]

A worktree created through each planwright-owned creation path, from a
clone with `core.hooksPath` absolute or cleared, passes `check:githooks`;
`scripts/check-githooks.sh` still fails on an absolute value; Task 6's PR
body names the writer or the evidence ruling out each candidate.

### REQ-E1.4 — Symlinked `TMPDIR` passes [test]

`tests/test-fleet-dispatch-worktree.sh` passes with `TMPDIR` pointed
through a symbolic link created by the test.

### REQ-E1.5 — Real Graphviz 15 passes [test + manual]

`tests/test-spec-graph.sh` passes in CI, and on a host with a real
Graphviz 15 `dot` on `PATH`, recorded in Task 7's PR body.

### REQ-E1.6 — CI parses every script under bash 3.2 [test]

The CI step passes on the branch and fails on fixture scripts carrying
each construct Task 3 fixed; a test in Task 4 asserts the step's image
reference carries a `@sha256:` digest and fails on a fixture reference
without one.

### REQ-E1.7 — The local lint catches the known constructs [test]

The lint fails on the same fixtures as REQ-E1.6 and passes on the tree,
running inside `mise run check`.
