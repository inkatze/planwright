# Test throughput — Requirements

**Status:** Ready
**Last reviewed:** 2026-09-28
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

On 2026-09-24 a fleet run spent hours bound on local testing: a full local
suite that takes minutes on GitHub CI took hours on the operator's Mac
(the measurements are in Sources). Two causes compounded. First,
every worktree's test runner started one test file per core with no
knowledge of the others, so a handful of workers checking at once put
several times the core count of test scripts on the machine. Second,
workers re-ran the full suite locally several times per task and
re-proved the same machine-only failures against clean `main` on every run.
This bundle makes local testing on a shared development host fast and
trustworthy while a fleet runs, and keeps it that way. It has five parts:
a machine-wide ticket pool that caps concurrent test files across every
worktree; an opt-in worker policy that runs targeted tests locally, treats
the pull request's GitHub CI as the full-suite verdict, and consults a
per-clone list of known environmental failures instead of re-proving
them; a profile of the slowest test files, with the test-side causes fixed,
the production-side causes routed elsewhere, and macOS's first-execution
stall on freshly written executables measured before any remedy is built; hardening of tests that
assert on tight time windows; and fixes for the known macOS-only failures,
with guards that stop them returning. The altitude call, placing the
worker policy as an opt-in core capability and everything else as this
repository's own mechanism, is D-1.

## Scope

### In scope

- A machine-wide, per-user ticket pool in `scripts/run-tests.sh` bounding
  concurrent test files across every checkout and worktree.
- An opt-in `/execute-task` and review-loop policy: targeted local checks
  while iterating, an early draft PR marked `Convergence: pending`, the
  PR's CI on the final pushed head as the full-suite evidence within a bounded
  `pr_ci_wait` that ends in Awaiting input, a pooled local fallback where
  no PR CI exists, and a portable recipe for long local runs.
- A machine-local, gitignored list of known environmental test failures,
  written only on the operator's confirmation, that never excuses a CI
  failure or a failure in code the worker changed.
- Profiling the slowest test files, fixing the causes that live in the
  tests, and routing the causes that live in production scripts.
- Measuring macOS's first-execution stall with and without the
  developer-tool exemption, and, only if the exemption falls short, a
  warmed-shim test helper and a lint keeping executable fixtures on it.
- Making elapsed-time test assertions tolerant of scheduling delay, and
  reporting a broken runner scratch directory as an environment error.
- Fixing the known macOS-only failures (the bash 3.2 parse failures, the
  bash-only scripts invoked through `sh`, the `check:githooks` worktree
  failure, the symlinked-`TMPDIR` and Graphviz 15 test failures) and adding
  a CI bash 3.2 parse check plus a local lint against their return.

### Out of scope

- A macOS CI job. It stays with universal-binary Tasks 4 and 4.1; this
  bundle only defers applying the time budgets to it once it exists.
- Editing review-effectiveness's signed text. Its full-suite-per-iteration
  requirement is amended through its own `/spec-kickoff` delta; this bundle
  depends on that amendment and does not make it.
- Reducing the process-spawn cost of production scripts. universal-binary
  owns that evidence class; this bundle records findings and routes them.
- Passing multi-line awk values portably. PR #508 landed that on `main`
  (obs:8c364933).
- Carrying the operator's login-shell environment into dispatched workers.
  That is a dispatch-environment concern for the fleet bundles
  (obs:ada69b21).
- Changing the default verification behavior for adopters. The worker
  policy ships behind a setting whose default preserves today's behavior.

## REQ-A — Machine-wide test ticket pool

- **REQ-A1.1** `scripts/run-tests.sh` SHALL take a ticket from one
  machine-wide, per-user pool before it starts each test file and SHALL
  return the ticket when that file finishes, so that every run on the host
  together executes at most the largest capacity any concurrent run uses
  (the pool's capacity when all runs agree) of test files at once, apart
  from the nested runs REQ-A1.8 exempts.
  *(Cites: D-2, obs:cc9a73d6, obs:edf96ce1, obs:fc3cdfde, obs:0044e073.)*
- **REQ-A1.2** The pool's capacity SHALL default to the host's core count
  and SHALL be overridable from the machine-local environment layer;
  `PLANWRIGHT_TEST_JOBS` SHALL continue to cap a single run's own
  parallelism beneath the pool.
  *(Cites: D-4.)*
- **REQ-A1.3** A ticket whose holding process is no longer running SHALL be
  reclaimable by the next run that needs one, so a killed runner never
  permanently reduces the pool's capacity.
  *(Cites: D-2.)*
- **REQ-A1.4** The pool SHALL resolve and work with no fleet running, no
  plugin installed, and no configuration present; when the pool cannot be
  used, the runner SHALL print one warning naming the cause and run
  unpooled, and SHALL NOT block or fail the run on that account.
  *(Cites: D-3, D-4, obs:d399dff7.)*
- **REQ-A1.5** The pool SHALL be built on the shared advisory-lock
  primitive `scripts/lock-lib.sh`, in portable shell with no new runtime
  dependency.
  *(Cites: D-2, universal-binary Task 1 (Sources).)*
- **REQ-A1.6** Time a test file spends waiting for a ticket SHALL be
  reported separately and SHALL NOT be counted in the per-file wall-clock
  that `check:test-time` reads.
  *(Cites: D-4.)*
- **REQ-A1.7** The pool's directory SHALL live under the user's home state
  directory, SHALL be created owner-only, and SHALL be refused, with the
  unpooled fallback of REQ-A1.4, when it is a symbolic link or is not owned
  by the running user; a test-only override SHALL be able to point it
  elsewhere.
  *(Cites: D-3.)*
- **REQ-A1.8** A runner started from inside a test file that a pooled run
  is executing SHALL run unpooled, since its parent's ticket already
  accounts for that file's work, so a nested run never waits on a ticket
  its own ancestor holds; this deliberate unpooled run SHALL NOT print
  REQ-A1.4's warning.
  *(Cites: D-4.)*

## REQ-B — CI-first worker verification

- **REQ-B1.1** A config setting `full_suite_evidence` SHALL select where a
  worker's full-suite evidence comes from, with the value `local` (today's
  behavior) as the core default and `remote-ci` as the opt-in value; it
  SHALL resolve through the config overlay layers and be documented in the
  canonical options reference; a malformed value SHALL fall back to `local`
  with one warning. A worker SHALL read it once at the unit's pre-flight,
  so a change takes effect from the next unit and never mid-way through
  one.
  *(Cites: D-1, D-5.)*
- **REQ-B1.2** Under `remote-ci`, `/execute-task` SHALL validate each change
  while iterating with a targeted local check (the tests touching the
  changed files, plus the linters) instead of the full suite.
  *(Cites: D-5, the drafting seed (Sources).)*
- **REQ-B1.3** Under `remote-ci`, `/execute-task` SHALL open its draft PR as
  soon as the first implementation passes its targeted check, SHALL push
  each subsequent iteration, and SHALL treat a green PR CI run on the
  branch's final pushed head (after the review loop's fixes and the sync
  with main) as the full-suite evidence; a unit SHALL NOT be reported
  converged without that green run on that head, except where REQ-B1.4's
  fallback applies and the green full local suite is the evidence. With no
  remote, no draft PR is opened early. Until the unit converges, the early
  PR's body SHALL carry a `Convergence: pending` line, which the
  convergence handoff's body update SHALL replace.
  *(Cites: D-5, drafting-session decision (2026-09-28).)*
- **REQ-B1.4** Under `remote-ci`, the head has no CI when the clone has no
  git remote, `gh` is not installed, no workflow file in the local tree
  carries a `pull_request` trigger, or the CI judge's no-positive-result
  verdict (no checks registered, or only skipped or neutral ones) persists
  for a grace window of 3 minutes after the push. On no CI the worker SHALL
  fall back to the full local suite through the ticket pool and SHALL say
  which evidence it used. Any other failure to read CI (an authentication
  failure, an outage, a read that cannot be judged) SHALL halt the unit to
  an Awaiting-input entry naming it, not fall back.
  *(Cites: D-5.)*
- **REQ-B1.5** Waiting for PR CI SHALL be done by bounded foreground polling
  that ends in a stated verdict (green, red, pending past its bound, or no
  CI), never by yielding a session to wait for a notification. On "pending
  past its bound" the worker SHALL poll again until a total wait set by a
  `pr_ci_wait` config setting (default `30m`, counted per head and reset by
  each push, resolved through the config overlay layers with a malformed
  value falling back to the default with one warning, and documented in the
  canonical options reference) is spent, and past it SHALL halt the unit to an Awaiting-input entry naming
  the pending CI rather than converge or fall back to the local suite.
  *(Cites: D-5, obs:67861aa6.)*
- **REQ-B1.6** A machine-local, gitignored list of known environmental
  failures SHALL exist per clone, readable from every worktree of that
  clone, each entry naming a test file (optionally one case within it), the
  environmental reason, and the date recorded. Under `remote-ci` only, a
  local failure matching an entry (the file, and where a case is named, an
  exact match on the runner's per-case failure label) SHALL be reported as
  known environmental and SHALL NOT be re-proven against a baseline or
  classified as a logic failure; under `local` the list is not consulted.
  *(Cites: D-6, obs:76435039, the drafting seed (Sources).)*
- **REQ-B1.7** A known-environmental entry SHALL NOT excuse any failure in
  the PR's CI, and SHALL NOT excuse a local failure in any test the
  targeted check selects for the worker's diff.
  *(Cites: D-6.)*
- **REQ-B1.8** A worker SHALL NOT write a known-environmental entry without
  the operator's confirmation; a worker that shows a failure also fails on
  a clean baseline MAY propose an entry, and only the operator's
  confirmation SHALL cause the skill's single list writer to add it.
  Removing an entry SHALL take the same confirmation through the same
  writer.
  *(Cites: D-6, drafting-session decision (2026-09-28).)*
- **REQ-B1.9** When a test named by a known-environmental entry passes
  locally, the worker SHALL flag that entry for removal in its report.
  *(Cites: D-6.)*
- **REQ-B1.10** Every full local suite run `/execute-task` makes SHALL use
  one documented, portable detached-run recipe, so no run depends on
  finishing inside a single tool call's time limit; the recipe that verifies the run started before anything relies on it and
  that never deletes a previous run's log before the new run starts.
  *(Cites: D-8, obs:67861aa6.)*
- **REQ-B1.11** The review loop's use of PR CI as its per-iteration full
  suite SHALL NOT be enabled before review-effectiveness's full-suite
  requirement has been amended, through that bundle's own delta sign-off,
  to accept it.
  *(Cites: D-7, review-effectiveness REQ-D1.3 (Sources).)*

## REQ-C — Slow-test profiling and test-side speedups

- **REQ-C1.1** The slowest test files by the runner's timing report, on the
  operator's macOS host and on GitHub CI, SHALL be profiled and their
  wall-clock attributed to causes (process launches, including the
  first-execution assessment of freshly written executables, fixture setup,
  sleeps and waits, and time inside the production scripts they exercise),
  with the measurements recorded. The slowest files on a host are those
  that, taken slowest first from an idle full run's timing report, together
  make up the first half of that host's total per-file wall-clock,
  including the file that crosses the halfway mark.
  *(Cites: D-9, D-14, obs:cc9a73d6, the drafting seed (Sources).)*
- **REQ-C1.2** Every cause the profile attributes to the tests themselves
  SHALL be fixed or explicitly declined with a recorded reason; in
  particular, tests SHALL invoke fabricated or copied script fixtures that
  the test itself runs through an interpreter rather than executing them
  directly. PATH shims the code under test runs by name are REQ-C1.5's.
  *(Cites: D-9, obs:c82f6661.)*
- **REQ-C1.3** Every cause the profile attributes to production scripts
  SHALL be recorded as an observation or a gated deferral naming the owning
  bundle, and SHALL NOT be fixed in this bundle.
  *(Cites: D-9, obs:4f021236.)*
- **REQ-C1.4** The profile SHALL record a measured verdict on whether macOS
  per-process user or group lookups amplify process-launch cost under the
  suite, and the test-side mitigation where one exists.
  *(Cites: D-9, the drafting seed (Sources).)*
- **REQ-C1.5** The profile SHALL measure the first-execution stall of
  freshly written executables (fixtures a test runs, and PATH shims the
  code under test runs) with and without the macOS developer-tool
  exemption, for an attended run and for a fleet-dispatched worker. Where
  the exemption brings a freshly written executable's first run within
  twice an already-assessed launch for both, the remedy SHALL be a
  documented machine setup step. Otherwise tests SHALL create executable
  fixtures only through one shared helper that pays the assessment once per
  run, and a lint in `mise run check` SHALL flag a test marking a file
  executable outside that helper.
  *(Cites: D-14, obs:c82f6661, obs:6bd8df61, obs:7f432dea.)*

## REQ-D — Tests that hold up on a busy machine

- **REQ-D1.1** A test that waits for an event SHALL poll until a generous
  deadline rather than assert the event occurred inside a narrow window,
  and on failure SHALL report the elapsed time it observed. An assertion
  that a minimum time elapsed (a backoff that waited at least N) is not a
  wait for an event and is out of this requirement's scope.
  *(Cites: D-10, obs:edf96ce1, obs:fc3cdfde, obs:0044e073.)*
- **REQ-D1.2** REQ-D1.1 SHALL apply to every test that asserts on elapsed
  time, identified by a sweep of the suite rather than by a fixed list; the
  sweep SHALL list each minimum-elapsed assertion it leaves unconverted,
  with its reason.
  *(Cites: D-10.)*
- **REQ-D1.3** When the runner's own scratch directory becomes unusable
  mid-run, the runner SHALL report an environment error (exit 2) naming the
  cause, rather than recording a failure against a test file.
  *(Cites: D-10, obs:0044e073.)*

## REQ-E — macOS portability fixes and guards

- **REQ-E1.1** `scripts/check-no-ci-evals.sh` and `scripts/tower-queue.sh`
  SHALL parse under macOS's bash 3.2 both as `bash` and in POSIX mode (as
  `/bin/sh`), and their existing tests SHALL pass on macOS.
  *(Cites: D-11, obs:ec9904c6, obs:297401ec.)*
- **REQ-E1.2** A skill SHALL invoke a repository script in a way that
  honors the interpreter its shebang names, and a check in
  `mise run check` SHALL flag skill instructions that run a bash-shebanged
  script through `sh`.
  *(Cites: D-12, obs:3225e01f.)*
- **REQ-E1.3** Whatever rewrites or clears the clone's `core.hooksPath`
  SHALL be identified with evidence, fixed where the writer is
  planwright's, and every worktree-creation path planwright owns SHALL
  wire the clone to the tracked `githooks` value whoever the writer is, so `check:githooks` passes in a freshly created worktree;
  `scripts/check-githooks.sh` SHALL remain detect-only.
  *(Cites: D-13, obs:68e0e504, obs:1ee82cd7, obs:2f2cb594, obs:b951f234,
  obs:f02b11d8, obs:f6f2d27f, obs:aef227b0, obs:82e88ffb, obs:359a9d5f,
  obs:871fa85d, obs:db015ded.)*
- **REQ-E1.4** `tests/test-fleet-dispatch-worktree.sh` SHALL pass when
  `TMPDIR` resolves through a symbolic link.
  *(Cites: D-11, obs:f334f13e.)*
- **REQ-E1.5** `tests/test-spec-graph.sh` SHALL pass on a host with a real
  Graphviz 15 `dot` on `PATH`.
  *(Cites: D-11, obs:76435039.)*
- **REQ-E1.6** CI SHALL parse every tracked shell file under a real bash
  3.2 in a pinned container image, and SHALL fail on any parse error. A
  file's dialect is its shebang, else its `# shellcheck shell=` directive;
  a `bash` dialect parses as `bash`, an `sh` dialect in POSIX mode. The
  step covers every tracked file declaring either, whatever its extension,
  and SHALL fail on a tracked `.sh` file declaring neither.
  *(Cites: D-11, research: Docker Hub official bash image (Sources).)*
- **REQ-E1.7** A local lint in `mise run check` SHALL flag the shell
  constructs known to misparse under bash 3.2 that REQ-E1.1 fixed, so a
  Linux-only local run catches their return before a push.
  *(Cites: D-11.)*

## Changelog

- 2026-09-28 — Drafted from the drafting seed, the observations log, and
  the drafting session; Status Draft. Fold-detection ran over every
  existing bundle; the operator's recorded decisions placed the macOS CI
  job with universal-binary and the review-loop full-suite change with a
  review-effectiveness delta, and otherwise kept this a new bundle.
- 2026-09-28 — Kickoff walkthrough edits (the kickoff brief records each
  decision): nested runs unpooled (REQ-A1.8); the CI-first policy's
  pending, no-CI, authentication, and fallback-convergence rules, the
  `Convergence: pending` marker, and `pr_ci_wait` (REQ-B1.3–B1.5); the
  list consulted under `remote-ci` only, with a single confirmed writer
  (REQ-B1.6, REQ-B1.8); the cumulative-half slowest-file rule and the
  first-execution measurement (REQ-C1.1, REQ-C1.5); the bash 3.2 dialect
  rule (REQ-E1.6); always wiring at worktree creation (REQ-E1.3); two
  observations recorded as sources for REQ-E1.1 and REQ-E1.4.

## Sources

- **The drafting seed (2026-09-28)** — the operator's scoping note for this
  bundle: measurements from the 2026-09-24 fleet run (suite wall about
  9,100 s locally against about 5 to 7 minutes on GitHub CI and a committed
  600 s budget; the allocation-feedback family and fleet tests slowest
  under load; 219 test files; `opendirectoryd` near 84% CPU), the parts it
  proposed, and the fold-detection and seed-consumption decisions the
  operator made before drafting.
- **Pinned altitude claim (seed)** — "workers repeatedly re-proved
  machine-only failures against a clean baseline" and the request for a
  "long-term fix": a recurring manual ritual, pinned as an altitude
  trigger and resolved in D-1.
- **obs:cc9a73d6** — fleet CI oversubscribing the host through per-worktree
  `xargs -P` (recorded on the worktree-tower branch; cited, not archived
  from this branch).
- **obs:edf96ce1**, **obs:fc3cdfde**, **obs:0044e073** — concurrent suites
  manufacturing timing failures in the fleet tests, and the runner scratch
  directory vanishing under load.
- **obs:67861aa6** — full CI exceeding a single tool call's limit, and the
  detached-launch trap where `setsid` is absent on macOS.
- **obs:76435039** — a machine-only `test-spec-graph.sh` failure with
  Graphviz 15 installed.
- **obs:68e0e504**, **obs:1ee82cd7**, **obs:2f2cb594**, **obs:b951f234**,
  **obs:f02b11d8**, **obs:f6f2d27f**, **obs:aef227b0**, **obs:82e88ffb**,
  **obs:359a9d5f**, **obs:871fa85d**, **obs:db015ded** — `check:githooks`
  failing in worktrees as the clone's `core.hooksPath` drifts from the
  tracked relative value, with no known writer.
- **obs:3225e01f** — bash-only scripts invoked through `sh` by skills.
- **obs:ec9904c6** — `check-no-ci-evals.sh` failing to parse under macOS
  bash 3.2 (worktree-tower branch; cited, not archived).
- **obs:297401ec** — `tower-queue.sh` and `check-no-ci-evals.sh` reproduced
  failing to parse under macOS bash 3.2, as `bash` and as `/bin/sh`
  (recorded at kickoff, 2026-09-28).
- **obs:f334f13e** — `test-fleet-dispatch-worktree.sh` reproduced failing
  on macOS's symbolically linked default `TMPDIR` (recorded at kickoff,
  2026-09-28).
- **obs:8c364933** — BSD awk rejecting multi-line `-v` values (worktree-tower
  branch; resolved on `main` by PR #508).
- **obs:c82f6661** — macOS Gatekeeper stalling the first direct execution
  of a freshly copied script.
- **obs:6bd8df61**, **obs:7f432dea** — the first-execution assessment
  stall measured on freshly created scripts, including freshly written PATH
  shims run by the code under test.
- **obs:4f021236** — process-spawn cost on the allocation launch path;
  cited, not consumed, because universal-binary claims it.
- **obs:d399dff7** — the fleet home not resolving from a plain checkout
  (worktree-tower branch; cited, not archived).
- **obs:ada69b21** — workers not inheriting the operator's login-shell tool
  resolution (worktree-tower branch; cited, not archived; out of scope
  here).
- **review-effectiveness REQ-D1.3** — the signed requirement that the full
  suite run once per review-loop iteration, which REQ-B1.11 waits on.
- **review-effectiveness Task 6** — delivers `scripts/check-diff-scoped.sh`,
  the targeted check D-5 reuses and Task 10's `Done when:` waits on.
- **universal-binary Task 1, Tasks 4 and 4.1** — the shared lock primitive
  this bundle builds on, and the macOS CI job it defers to. A narrow
  macOS-awk CI job exists on a local, unpushed branch, a possible starting
  point for Task 4.1.
- **PR #508** — portable multi-line awk values, merged to `main`.
- **Research: Docker Hub official bash image** — the `library/bash`
  repository's `3.2` tag, multi-architecture, last updated 2026-09-19
  (consulted 2026-09-28).
