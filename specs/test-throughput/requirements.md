# Test throughput — Requirements

**Status:** Ready
**Last reviewed:** 2026-10-09
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

An extension (2026-10-09) adds a sixth part. Once a unit's pull request
exists, a later run against it (a fix round after review or a red check)
should not re-run the full local suite. Under `local`, today it does,
queued behind every other suite on the host. On 2026-10-08 that stalled a
pull request for most of a day while its fixes sat unpushed. A third
setting value, `local-then-ci`, runs the full local suite once before the
pull request opens. After that, each fix round runs targeted tests plus
lint, pushes, and takes green CI on the pushed head as the gate of record.
The runner also gains a per-file deadline, so one hung test file cannot
hold its ticket, or any whole-suite lock its run holds, without bound. The
extension keeps D-1's altitude, restated with this repository's value
changed in D-15, which supersedes it in part.

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
- A `local-then-ci` value of `full_suite_evidence`: one full local suite
  before a unit's pull request opens, then fix rounds on that open pull
  request validated by targeted tests plus lint and gated on CI for the
  pushed head.
- Amending the Agent-resolvable predicate in
  `doctrine/finding-categorization.md` so green CI on a pushed head
  containing the fix counts as passing project CI.
- Switching this repository to `local-then-ci` and retiring the interim
  post-PR prompt step that only reminds fix rounds of the rule.
- A per-file deadline in `scripts/run-tests.sh`.

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
- Editing custom-steps' signed text. Its attachment-point moments place
  the run's first full CI run before `convergence`, which a fix round whose
  only CI run follows `pre-pr` cannot meet; that bundle's own delta changes
  them, and this bundle names that delta as a precondition
  (D-20).
- Amending bootstrap. Its requirement that `/execute-task` run full
  project CI is met by CI that the run triggers and waits for on its own
  pushed head (D-19).
- The worker-brief text operators hand dispatched workers. It lives
  outside the repository.

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
  **Superseded-by: REQ-B1.12** (2026-10-09) — the setting gains a second
  opt-in value, `local-then-ci`.
- **REQ-B1.12** (supersedes REQ-B1.1) A config setting
  `full_suite_evidence` SHALL select where a worker's full-suite evidence
  comes from, with the value `local` (today's behavior) as the core default
  and `remote-ci` and, once REQ-F1.8's preconditions hold,
  `local-then-ci` (REQ-F1.1) as the opt-in values; it
  SHALL resolve through the config overlay layers and be documented in the
  canonical options reference; a malformed value SHALL fall back to `local`
  with one warning. A worker SHALL read it once at each run's pre-flight,
  so a change takes effect from the next run and never mid-way through
  one.
  *(Cites: D-1, D-5, D-16, delta re-walkthrough (2026-10-09).)*
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
  **Superseded-by: REQ-B1.13** (2026-10-09) — the list is also consulted
  in a fix round under `local-then-ci`.
- **REQ-B1.13** (supersedes REQ-B1.6) A machine-local, gitignored list of
  known environmental failures SHALL exist per clone, readable from every
  worktree of that clone, each entry naming a test file (optionally one
  case within it), the environmental reason, and the date recorded. Under
  `remote-ci`, and in a fix round under `local-then-ci` (REQ-F1.3), a local
  failure matching an entry (the file, and where a case is named, an exact
  match on the runner's per-case failure label) SHALL be reported as known
  environmental and SHALL NOT be re-proven against a baseline or classified
  as a logic failure; under `local`, and in a first run under
  `local-then-ci`, the list is not consulted.
  *(Cites: D-6, D-16, obs:76435039, the drafting seed (Sources),
  delta re-walkthrough (2026-10-09).)*
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
- **REQ-D1.4** The runner SHALL end any test file still running past a
  per-file deadline, SHALL record that file as failed with a message
  naming the file and the deadline, and SHALL return the file's ticket,
  so a hung file cannot hold its ticket, or any whole-suite lock its run
  holds, past the deadline. With no way to bound a process on the host, the
  runner SHALL run files unbounded and warn once.
  *(Cites: D-21, obs:9393af12.)*

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

## REQ-F — Fix rounds on an open pull request

- **REQ-F1.1** `full_suite_evidence` SHALL accept a third value,
  `local-then-ci`, opt-in like `remote-ci`, resolved, documented, read once
  at each run's pre-flight, and falling back on a malformed value exactly
  as REQ-B1.12 requires.
  *(Cites: D-15, D-16.)*
- **REQ-F1.2** Under `local-then-ci`, a run for a unit whose branch has no
  open pull request SHALL behave as under `local`: its full local suite,
  held in custom-steps' `full_suite_pool` step pool when that wiring names
  one, is the run's full-suite evidence, and the draft pull request opens
  after it.
  *(Cites: D-16, the fix-round seed (Sources).)*
- **REQ-F1.3** Under `local-then-ci`, a run SHALL be a fix round when, at
  pre-flight, an open pull request exists for the unit's branch; the classification SHALL be made
  once per run and SHALL NOT change mid-run. When the pull-request read
  fails, the run SHALL proceed as under `local` and SHALL say why in its
  convergence summary.
  *(Cites: D-16, drafting-session decision (2026-10-09).)*
- **REQ-F1.4** Under `local-then-ci`, a fix round SHALL validate each
  change with the targeted check (the tests touching the changed files,
  plus the linters) and SHALL NOT run the full local suite at any point in
  the run, its pre-convergence CI step included, except as REQ-F1.5's no-CI
  fallback.
  *(Cites: D-17, obs:9b52ed36, obs:0670aadb.)*
- **REQ-F1.5** Under `local-then-ci`, a fix round SHALL push its branch at
  the push step after the `pre-pr` point, SHALL run the `post-pr` point,
  and SHALL then take a green CI run on the branch's final head as the gate
  of record, waiting, halting and falling back to the full local suite
  through the runner's ticket pool on no CI exactly as REQ-B1.4 and
  REQ-B1.5 define; a round that added no commit SHALL gate the pull
  request's current head. It SHALL NOT hand the round off as converged
  without that green run or the fallback's green local suite. Before
  acting on a red verdict it SHALL re-read the head: a head that moved past
  the gated one and contains it SHALL be awaited instead, and any other
  moved head SHALL halt the round to Awaiting input naming both heads. A red
  verdict on an unmoved head SHALL go through the existing failure
  classifier exactly as a local failure does: a logic failure halts to
  Awaiting input, and a transient one is retried under the adaptive policy.
  *(Cites: D-17, the fix-round seed (Sources), delta re-walkthrough
  (2026-10-09).)*
- **REQ-F1.6** In a fix round under `local-then-ci`, the review loop SHALL
  validate each fix with the targeted check and SHALL take the round's CI
  run on the final pushed head as its full-suite evidence instead of a
  full local suite per iteration.
  *(Cites: D-17, D-20.)*
- **REQ-F1.7** The Agent-resolvable predicate's passing-project-CI
  condition SHALL be met by a green CI run on a pushed head that contains
  the fix, as well as by a green full local suite; a finding whose fix
  awaits that run SHALL NOT be reported resolved until the run is green.
  *(Cites: D-18.)*
- **REQ-F1.8** `local-then-ci` SHALL NOT be offered as a valid value before
  custom-steps' attachment-point moments and review-effectiveness's
  full-suite-per-iteration requirement have each been amended, through
  that bundle's own delta sign-off, to accept a run whose full-suite
  evidence is CI on its pushed head.
  *(Cites: D-20, custom-steps D-3, REQ-A1.1 (Sources),
  review-effectiveness REQ-D1.3 (Sources).)*
- **REQ-F1.9** When this repository sets `full_suite_evidence:
  local-then-ci`, the interim post-PR prompt step that reminds fix rounds
  of the rule SHALL be removed from its configuration and from its
  repo-tracked steps catalog in the same change.
  *(Cites: D-15, D-20, the fix-round seed (Sources).)*
- **REQ-F1.10** Under `local-then-ci`, a fix round's push SHALL set the
  pull request body's `Convergence: pending` line (REQ-B1.3's line), the
  round's handoff SHALL replace it with the convergence summary, and a
  halted round SHALL leave it in place.
  *(Cites: D-17, delta re-walkthrough (2026-10-09).)*

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
- 2026-10-09 — Extended by `/spec-draft` (meaning-class: new REQs and
  D-IDs). Added REQ-D1.4 (per-file test deadline) and the REQ-F group
  (fix rounds on an open pull request under a new `local-then-ci` value);
  D-15 supersedes D-1 in part and D-20 supersedes D-7 in part, changing this repository's
  own value from `remote-ci` to `local-then-ci`; D-16 to D-19 and D-21 are
  new. Task 13 drops its repository switch, Task 10 gains a dependency on
  the new Task 15, and Tasks 14 to 17 are new. Fold-detection placed the
  idea here because REQ-B owns where full-suite evidence comes from. The
  bundle stays Active; the delta is signed off through `/spec-kickoff`'s
  delta re-walkthrough.
- 2026-10-09 — Delta re-walkthrough edits (meaning-class). REQ-F1.4 gains
  the carve-out for REQ-F1.5's no-CI fallback, with D-17, Task 16 and its
  test-spec entry aligned; REQ-B1.12 supersedes REQ-B1.1, listing
  `local-then-ci` beside `remote-ci` as an opt-in value, with Task 10's
  citation and the test-spec entry moved to it; test-spec REQ-F1.9 is
  retagged `[manual]`, recorded in Task 17's PR, since no CI step checks
  this repository's own steps configuration; Task 16 gains a dependency
  on Task 13, so the two review-loop edits land in sequence.
- 2026-10-09 — Delta re-walkthrough lens-pass dispositions
  (meaning-class). A fix round waits on CI after the `post-pr` point,
  re-reads a moved head before acting on red, escalates a logic failure as
  every run does, gates the current head when it added no commit, and
  carries `Convergence: pending` until handoff (REQ-F1.5, new REQ-F1.10,
  D-17); REQ-B1.13 supersedes REQ-B1.6 so a fix round consults the
  known-environmental list; the setting is read per run (REQ-B1.12, Task
  10, D-5 in part); D-18 records its compatibility with
  review-effectiveness REQ-D1.3; Task 16 gains a classification helper; plus
  wording, citation and testability fixes recorded in the brief's
  Amendment 1.

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
- **The fix-round seed (2026-10-09)** — the operator's decision behind
  the 2026-10-09 extension: one full local gate before a pull request
  opens; once it exists, each fix round runs targeted tests plus lint,
  pushes, and CI on the pushed head is the gate of record. The seed named
  the conflicting texts (custom-steps' pre-convergence suite, bootstrap's
  full-project-CI requirement, the Agent-resolvable predicate), the
  interim repo-tracked post-PR prompt step and worker-brief text as too
  late or advisory, and a fix round's full local gate queued on the host
  lock that stalled a pull request for most of 2026-10-08.
- **Pinned altitude claim (fix-round seed)** — the interim measures are
  "advisory" and run "too late": an enforcement claim, pinned as an
  altitude trigger and resolved in D-15.
- **obs:0670aadb** — the tower's trial policy of targeted suites while
  iterating and GitHub CI on the draft pull request as the one full-suite
  run, asking for built-in support.
- **obs:9b52ed36** — workers re-running the whole suite at every
  checkpoint, review rounds included, where a human runs covering tests
  while iterating and the full suite once at a strategic point.
- **obs:9393af12** — a full gate holding the host lock for over 40 minutes
  behind one hung test file, with no per-file deadline.
- **custom-steps D-3, REQ-A1.1** — the attachment-point moments that
  place `pre-ci` before the run's first full CI run and `convergence`
  after it is green, which REQ-F1.8 waits on.
- **bootstrap REQ-E1.2** — `/execute-task` runs full project CI, read by
  D-19.
