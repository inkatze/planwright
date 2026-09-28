# Test throughput — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-28
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` for the runner, the helpers, the guards, and the
fixtures, all run by `mise run check` in the repository CI, with the bash
3.2 parse step running as its own CI step; `[Gherkin]` for the
`/execute-task` behaviors a fixture unit exercises end to end, recorded in
the PR body; `[manual]` for the macOS-host measurements and the
real-Graphviz run, which need the operator's machine because the CI runner
is Linux, and for the sweep search records the operator reviews at PR
review; `[design-level]` where the artifact's content is the
verification.

## REQ-A — Machine-wide test ticket pool

### REQ-A1.1 — Concurrent runs share one bound [test]

Two runner invocations started together against one pool (via
`PLANWRIGHT_TEST_SLOT_DIR`) with capacity K, over a fixture suite whose
files record their start and end instants: the recorded intervals never
overlap more than K deep and reach K at some instant. Two runs at
capacities K1 below K2: the intervals never overlap more than K2 deep.

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

`scripts/check-lock-primitive.sh` reports the runner clean, and the runner
appears on `lock-lib.sh`'s lock-holder list, which `tests/test-lock-lib.sh`
pins against the tree.

### REQ-A1.6 — Waiting is not test time [test]

A fixture file run while the pool is saturated for a known interval: its
timing-report execution time excludes the wait, the report's wait field records
it, and `check:test-time` reads the execution time only.

### REQ-A1.7 — Pool location is owner-only and refuses hostile paths [test]

A fresh pool directory is created owner-only under the home state path; a
symbolic link at the path, and a directory owned by another user
(simulated through the ownership check's injectable probe), each produce
the one-warning unpooled fallback.

### REQ-A1.8 — A nested runner never waits on its ancestor's ticket [test]

At pool capacity 1, a pooled run executing a fixture file that itself runs
the runner over a fixture suite: the inner run completes unpooled with no
pool warning printed, and the outer run finishes rather than hanging. A
pool test that clears the mark still exercises pooling.

## REQ-B — CI-first worker verification

### REQ-B1.1 — The setting resolves with a preserving default [test + Gherkin]

`full_suite_evidence` resolves to `local` with no overlay, to `remote-ci`
when an overlay sets it, and to `local` with one warning when malformed;
the options reference documents it (checked by the options-reference
guard). Given a fixture unit whose setting changes mid-unit, the change
takes effect only at the next unit's pre-flight, recorded in Task 10's PR
body.

### REQ-B1.2 — Targeted check while iterating [Gherkin]

Given a fixture unit under `remote-ci`, when `/execute-task` validates a
change, then it runs the tests touching the changed files and the linters,
and not the full suite. Recorded in Task 10's PR body.

### REQ-B1.3 — Early draft PR and green CI on the final head [Gherkin]

Given a fixture unit under `remote-ci`, when the first implementation
passes its targeted check, then the parent skill opens the draft PR with a
`Convergence: pending` line in its body and each later iteration is
pushed; when the review loop's fixes and the sync with main are pushed,
then green CI is awaited on that final pushed head, and while it is red or
pending no convergence is reported; when the unit converges, then the
handoff's body update replaces the pending line. Given no remote, no early
PR opens. Recorded in Task 10's PR body.

### REQ-B1.4 — No CI, the grace window, and halts [test + Gherkin]

`await-pr-ci.sh` prints "no CI" for a fixture with no remote, one with no
`gh`, and one whose workflow files carry no `pull_request` trigger; for a
head with no checks registered it prints pending inside the 3-minute grace
window and "no CI" after it, and the same for a head whose checks are all
skipped. A failed read and a `too-many` read each halt. Given "no CI",
`/execute-task` runs the full local suite through the pool, converges on
it, and records the evidence used in the convergence summary.

### REQ-B1.5 — Bounded polling to a verdict [test]

`await-pr-ci.sh` against recorded check fixtures prints green, red, and no
CI for the matching fixtures, and "pending past bound" for a fixture that
never completes, each call returning inside its bound. A fixture unit
whose CI stays pending re-polls until `pr_ci_wait` is spent on that head,
a push resetting the count, and then halts to an Awaiting-input entry
naming the pending CI; `pr_ci_wait` resolves to `30m` with no overlay, to
an overlay's value when set, and to `30m` with one warning when malformed,
and the options-reference guard passes with it documented.

### REQ-B1.6 — Listed failures are reported, not re-proven [test]

Under `remote-ci`, a fixture failure matching a list entry (file-level,
and case-level on an exact match of the runner's per-case failure label)
is reported as known environmental and never reaches the baseline re-run
or the logic classification; a near-miss case label does not match; the
list is found from a worktree through git's common directory; with a bare
primary the reader warns once and matches nothing. Under `local` the list
is not consulted.

### REQ-B1.7 — The list never excuses CI or changed code [test]

A PR CI failure on a listed test, and a local failure in a listed test
the targeted check selected for the diff (because the diff changed the
test, and because it changed a script the test covers): each is treated as
an ordinary failure.

### REQ-B1.8 — Entries are written only on confirmation [test + Gherkin]

The list writer adds or removes an entry only when given the operator's
confirmation, by temporary file and rename, and no other code path writes
the list; given a failure that also fails on a clean baseline, the
worker's output carries a proposal (unattended: an Awaiting-input entry),
and the file is unchanged until confirmation.

### REQ-B1.9 — Passing listed tests are flagged [test]

A listed test that passes locally appears in the worker's report as a
removal candidate.

### REQ-B1.10 — Detached runs prove they started [test]

The helper reports failure for a launch whose runner cannot start; the
status verb reports running, finished with its code, and never started for
the matching fixtures; a previous run's log survives a new launch; the
helper passes on the Linux CI runner without `setsid`; `/execute-task`'s
CI step routes every full local suite run through it (checked in Task 12's
diff).

### REQ-B1.11 — Review-loop wiring waits on the amendment [design-level]

Task 13 is parked under `## Deferred` with the free-text gate naming the
review-effectiveness amendment, and its `Done when:` names that
precondition; the drain pass surfaces the gate verbatim.

## REQ-C — Slow-test profiling and test-side speedups

### REQ-C1.1 — Attribution is recorded [manual + design-level]

Task 9's PR body carries the selected file set (those making up the first
half of each host's total per-file wall-clock in an idle full run, slowest
first, including the file crossing the halfway mark) and per-file
attribution across the named causes, on the operator's macOS host and on
GitHub CI, with the measurements behind it; the operator reviews it at PR
review.

### REQ-C1.2 — Test-side causes dispositioned; no direct fixture execution [manual + design-level]

Task 9.1's PR body records the sweep's search for a test's own direct
execution of copied or fabricated script fixtures (PATH shims excluded),
with its result (none remaining), and dispositions every test-side cause
with before-and-after timings; the operator reviews both at PR review.

### REQ-C1.3 — Production causes routed, not fixed [design-level]

Every production-side cause in Task 9's PR body names its observation UID
or deferral and the owning bundle, and the task's diff touches no
production script for a performance reason.

### REQ-C1.4 — User-lookup verdict measured [manual]

Task 9's PR body records the measured verdict on user or group lookup
amplification on the operator's macOS host, with the measurement method.

### REQ-C1.5 — First-execution stalls measured, then remedied [manual + test]

Task 9's PR body records the stall with and without the developer-tool
exemption, attended and fleet-dispatched, against REQ-C1.5's
twice-an-assessed-launch threshold, and its verdict; where the exemption
meets it for both, `docs/CONTRIBUTING.md` carries the setup step.
Otherwise Task 9.2's lint passes on the tree and fails on a fixture test
marking a file executable outside the helper, and its PR body shows the
stall paid once per run.

## REQ-D — Tests that hold up on a busy machine

### REQ-D1.1 — Poll until a generous deadline [test]

The helper's own tests: a condition that becomes true late but inside the
deadline passes; one that never does fails with the observed elapsed time
in the message; the default deadline is documented in the helper.

### REQ-D1.2 — The sweep covers every elapsed-time assertion [test + manual]

Task 8's PR body records the sweep's search, its list, each
minimum-elapsed assertion left unconverted with its reason, and a re-run of
the search after conversion finding none outside the helper and those
exceptions; the converted tests pass under the artificial-load run (its
factor recorded), and the PR body records the unconverted tests' result
under the same load.

### REQ-D1.3 — Runner breakage is an environment error [test]

A fixture that removes the runner's scratch directory mid-run: the runner
exits 2 naming the cause and records no test as failed.

## REQ-E — macOS portability fixes and guards

### REQ-E1.1 — The two scripts parse under bash 3.2 [test + manual]

Task 3 parses both scripts under bash 3.2 as `bash` and in POSIX mode and
the Task 4 CI step parses them in their declared dialect; their existing
tests pass in CI and on the operator's macOS host, the macOS run recorded
in Task 3's PR body.

### REQ-E1.2 — Invocation honors the shebang [test]

The Task 5 check passes on the tree and fails on a fixture skill running a
bash-shebanged script through `sh`.

### REQ-E1.3 — Fresh worktrees pass `check:githooks` [test + design-level]

A worktree created through each planwright-owned creation path Task 6
lists, from a clone with `core.hooksPath` absolute or cleared, passes
`check:githooks`; `scripts/check-githooks.sh` still fails on an absolute
value; Task 6's PR body names the writer or the evidence ruling out each
candidate, and the search that found the creation paths.

### REQ-E1.4 — Symlinked `TMPDIR` passes [test]

`tests/test-fleet-dispatch-worktree.sh` passes with `TMPDIR` pointed
through a symbolic link created by the test.

### REQ-E1.5 — Real Graphviz 15 passes [test + manual]

`tests/test-spec-graph.sh` passes in CI (the stub path), and on a host with
a real Graphviz `dot` on `PATH` whose `dot -V` reports version 15, the run
and that output recorded in Task 7's PR body.

### REQ-E1.6 — CI parses every script under bash 3.2 [test]

The CI step passes on the branch; a test drives it against its excluded
fixtures directory and shows it failing on a fixture carrying each
construct Task 3 fixed and on a fixture `.sh` file declaring no dialect;
its file list includes the shebang-less libraries and the extension-less
git hooks; a test in Task 4 asserts the step's image reference carries a
`@sha256:` digest and fails on a fixture reference without one.

### REQ-E1.7 — The local lint catches the known constructs [test]

The lint fails on each construct fixture REQ-E1.6 uses and passes on the
tree, running inside `mise run check`.
