# Test throughput — Design

**Status:** Ready
**Last reviewed:** 2026-10-09
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` is a decision new in this bundle; `C, <bundle> <id>` is one
carried from another bundle and applied here.

## Decision log

### D-1: The worker policy is an opt-in core capability; the rest is this repository's mechanism  (N)

**Decision:** The bundle sits on two rungs of the altitude ladder. The
CI-first worker policy and the known-environmental list change how
`/execute-task` and the review loop behave in every adopter repository, so
they land in core as a capability behind the `full_suite_evidence` setting,
whose core default `local` reproduces today's behavior; planwright's own
value, `remote-ci`, lives in its repo-tracked overlay, and the list's
contents are machine-local values. The ticket pool, the test hardening, the
profiling, and the macOS fixes and guards change only planwright's own test
runner, tests, scripts, and CI, so they are repository mechanism. No
doctrine rule is minted for the worker policy: the evidence that CI-first
verification generalizes comes from one repository's fleet so far. (D-12's
invocation rule is different in kind: it extends the existing
script-invocation doctrine that already governs every skill.)

**Alternatives considered:**
- Make CI-first the core default for every adopter. Rejected because:
  customization-boundary requires a core behavior change to land as an
  opt-in, default-preserving knob until drain-loop evidence beyond one
  repository shows it generalizes; every adopter's workers would change
  behavior on upgrade.
- State it as a doctrine rule ("remote CI is the full-suite evidence of
  record") and make it the default. Rejected because: the same evidence
  bar applies, and a doctrine rule with one repository behind it would be
  a mechanism written into doctrine.
- Keep the whole policy as planwright-repository behavior with no core
  capability. Rejected because: the machine-only-failure ritual the seed
  names is not specific to this repository, and the mechanism is general
  even though the value is not.

**Chosen because:** the pinned seed claim (a manual ritual workers kept
repeating) asked for the ritual to be closed durably, and
customization-boundary splits the feature along its seam: the general
ability to take full-suite evidence from remote CI is core's, the choice to
use it is each repository's.

**Superseded-by: D-15** (2026-10-09), in part — this repository's own
value becomes `local-then-ci`, not `remote-ci`; the altitude split is
unchanged. D-18 amends one doctrine rule, the Agent-resolvable predicate's
evidence condition, so the no-doctrine sentence above no longer holds for
that condition.

### D-2: The ticket pool is a set of numbered lock-lib locks with dead-holder reclaim  (N)

**Decision:** The pool is a directory of numbered ticket paths, one per
unit of capacity. A ticket and a slot are the same thing: the prose says
ticket, and paths and variables say `slot`. A test worker takes a ticket by attempting each numbered
path with `lock-lib.sh`'s one-attempt acquire, holding it as the process
that runs the test file, and releases it with the ownership-verified
release when the file finishes. A path whose recorded owner is no longer
running is cleared and retaken, which is what makes the pool crash-safe. A
worker that finds no free ticket waits with a bounded backoff and tries
again.

**Alternatives considered:**
- `mkdir`-based slot locks. Rejected because: `lock-lib.sh` records `mkdir`
  losing mutual exclusion across the release-and-reacquire cycle, and
  `scripts/check-lock-primitive.sh` rejects it as an acquisition signal.
- `flock` on a shared file. Rejected because: `flock` is absent on macOS,
  which is inside the support bar.
- A named-pipe token pool (tokens written into a FIFO, read to acquire).
  Rejected because: a killed holder's token is lost for good, and nothing
  can tell which process held it.
- One counter file under a lock. Rejected because: a crash between
  increment and decrement leaks capacity, and recovering it needs the same
  per-holder identity the numbered locks carry for free.

**Chosen because:** the numbered locks reuse the one audited exclusion
primitive the script layer already has, carry each holder's identity, and
so make both exclusion and stale reclaim properties of existing code rather
than new code.

### D-3: The pool lives under the user's home state directory, owner-only  (N)

**Decision:** The pool directory is
`${XDG_STATE_HOME:-$HOME/.local/state}/planwright/test-slots`, created
owner-only on first use. It is refused, and the runner falls back to
unpooled with its one warning, when the path is a symbolic link or is not
owned by the running user. `PLANWRIGHT_TEST_SLOT_DIR` overrides the location
for the runner's own tests.

**Alternatives considered:**
- A per-user directory in `/tmp` (or `$XDG_RUNTIME_DIR` where set).
  Rejected because: `/tmp` is shared and world-writable, so another user
  can pre-create or plant a link at the path, and every run would depend on
  ownership checks to stay safe; macOS sets no `XDG_RUNTIME_DIR`.
- `$TMPDIR`. Rejected because: tests and workers override it, which would
  split one machine into several pools.
- The fleet state home, else the home path. Rejected because: the fleet
  home does not resolve from a plain checkout (obs:d399dff7), and two
  possible locations would let a fleet run and a non-fleet run use
  different pools.

**Chosen because:** a home-directory path is per-user by construction,
outside any world-writable directory, stable across checkouts and
worktrees, and resolvable with nothing installed (security-posture: guard
path access). It survives reboots, which is harmless because dead holders
are reclaimed.

### D-4: Capacity, per-run parallelism, degradation, and wait accounting  (N)

**Decision:** Capacity defaults to the core count the runner already
probes, overridable by `PLANWRIGHT_TEST_SLOTS` set in the machine-local
environment layer (`mise.local.toml`); a malformed value takes the same
fallback and clamp `PLANWRIGHT_TEST_JOBS` has, with the pool's one warning. A run still starts its own
`PLANWRIGHT_TEST_JOBS` (default core count) workers, and each blocks on a
ticket, so the per-run cap and the machine-wide cap both hold. Runs that
disagree on capacity use tickets numbered up to their own value; the
effective machine-wide bound is the largest value in use, which the runner
documents. An unusable pool (unresolvable, refused, unwritable, or a
`lock-lib.sh` real error) produces one warning naming the cause and an
unpooled run. Each worker records the time it waited for a ticket in its
own record, starts its file's timing only after it holds a ticket, and the
timing report carries the wait as its own field. That changes the report
format `scripts/check-test-time.sh` reads (a version-1 header with
three-field file rows, failing closed on anything else), so the report
bumps its version and the checker, its tests, and the contributor timing
docs move with it; the suite-wall row still includes waiting, documented as
such. The runner marks the
environment it gives each pooled test file, and a runner that finds the
mark runs unpooled: the parent's ticket already counts the file's work, and
a nested run that waited on the pool could wait on a ticket its own
ancestor holds, deadlocking at low capacity. The overshoot is bounded by
the nested run's own job count, and the only nesting today is the runner's
own tests over small fixture suites.

**Alternatives considered:**
- Fail the run when the pool is unusable. Rejected because: the operator
  chose never blocking testing over guaranteed exclusion
  (drafting-session decision, 2026-09-28).
- Count wait inside the per-file time. Rejected because: `check:test-time`
  budgets measure a file's cost, and a busy machine must not make a file
  look slow.
- Give a nested run its own fresh pool directory. Rejected because: its
  bound limits only itself, so it adds a directory per nested run without
  adding protection.
- Let a nested run inherit its parent's ticket as its first slot (the make
  jobserver model). Rejected because: it needs `lock-lib.sh`'s
  cross-process hold verbs and a token passed through the environment into
  every test file, for one test file's benefit.
- Leave nesting to each test's setup. Rejected because: the next test that
  nests the runner would reintroduce the deadlock silently.
- Replace `PLANWRIGHT_TEST_JOBS` with the pool. Rejected because: the
  serial fallback, the runner's own tests, and CI all depend on the per-run
  knob, and it costs nothing to keep.

**Chosen because:** it bounds the machine without changing a solitary
run's behavior, keeps every existing knob meaningful, and keeps the timing
budgets measuring what they were set from.

### D-5: `full_suite_evidence: remote-ci` opens the draft PR early and waits on PR CI by bounded polling  (N)

**Decision:** `full_suite_evidence` takes `local` (core default) or
`remote-ci`, and `pr_ci_wait` a duration (default `30m`); both resolve
through `scripts/resolve-config-knob.sh`, the shared knob resolver, a
malformed value falling back to its default with one warning. Under
`remote-ci`, `/execute-task`:
- validates each change with the targeted check (tests touching the
  changed files, plus the linters), reusing the diff-scoped check
  `scripts/check-diff-scoped.sh` that review-effectiveness Task 6 builds
  rather than a second selector;
- opens the draft PR once the first implementation passes it, and pushes
  every subsequent iteration; the parent skill opens it, never a per-step
  session, so Task 10 amends `/execute-task`'s rule that PR creation is its
  single terminal step to carve out this early open, and with no remote no
  early PR opens;
- takes a green PR CI run on the branch's final pushed head, after the
  review loop's fixes and the sync with main are pushed, as the full-suite
  evidence, and never reports convergence without it, except on the no-CI
  fallback below, where the green full local suite is the evidence;
- opens that early PR with a `Convergence: pending` line in its body, which
  the convergence handoff's normal body update replaces with the
  convergence summary, so an unconverged PR never reads as a finished unit
  (every task PR stays draft until the operator flips it, so draft state
  cannot carry this);
- waits through a new helper, `scripts/await-pr-ci.sh`, that polls the
  head's checks in foreground calls bounded under the tool-call limit and
  prints one verdict: green, red, pending past its bound, or no CI. It
  judges each poll with `scripts/release-lib.sh`'s `rl_ci_state`, the
  per-commit CI judge the release scripts already share, rather than a
  second evaluator. Before reading it, cheap local checks decide no CI: no
  git remote, no `gh`, or no workflow file in the local tree carrying a
  `pull_request` trigger. Then `green` and `failing` map to green and red,
  `pending` to pending, and `none` (no checks registered yet, or only
  skipped or neutral ones) to pending for a 3-minute grace window after the
  push and to no CI once it persists past it, which ends both the
  registration race and a filtered-out PR without a halt. `too-many`, and
  any failure of the read itself (`rl_ci_state` reports an outage, an
  expired login, and a bad query alike), halt the unit to Awaiting input;
- reads `full_suite_evidence` once at the unit's pre-flight, so a setting
  change, including planwright's own switch in Task 13, takes effect from
  the next unit and never mixes evidence kinds within one;
- on "pending past its bound", polls again until the `pr_ci_wait` total,
  counted per head and reset by each push, is spent, then halts the unit to an Awaiting-input entry
  naming the pending CI, the same bounded-wait-then-Awaiting-input shape
  kickoff's own ready-flip CI gate uses;
- on "no CI", falls back to the full local suite through the ticket pool
  and records which evidence it used in the convergence summary.

A red PR CI result goes through the existing failure classifier, exactly
as a local failure does today. Never marking a PR ready and never merging
are unchanged.

**Alternatives considered:**
- Open the draft PR once, before the final gate. Rejected because: review
  iterations would never see a full suite, and the operator chose the
  early PR (drafting-session decision, 2026-09-28).
- Add a push trigger for worker branches to `ci.yml`, keeping the PR where
  it opens today. Rejected because: it spends CI on every push to every
  branch and changes the CI trigger surface, where the early draft PR uses
  the trigger that already exists.
- Parse PR checks in the new helper. Rejected because: a second CI
  evaluator can drift from `rl_ci_state` on what counts as green.
- Treat an empty check list as no CI. Rejected because: checks register
  after the push, so an early poll would trigger the local fallback on an
  ordinary timing gap.
- Treat an authentication failure as provider unreachable. Rejected
  because: the fallback would hide an expired login behind slow local runs.
- Probe authentication and reachability before each read, falling back on
  an outage. Rejected because: `rl_ci_state` cannot tell the cases apart,
  and the probes add logic for a case the halt already handles safely.
- On a CI run pending past the wait, fall back to the full local suite.
  Rejected because: a slow runner queue would put workers back on the
  local-suite cost this bundle removes, on evidence the macOS-only failures
  make unequal to CI's.
- Halt to Awaiting input after a single bounded poll. Rejected because: an
  ordinarily busy runner queue would stop units routinely.
- Mark the early PR with a repository label. Rejected because: it needs the
  label provisioned on each repository and a fallback where it is absent,
  where the body line rides the body update the handoff already makes.
- Wait for CI by yielding the session to a notification. Rejected because:
  that is the stall obs:67861aa6 records, where a worker sits idle with
  work stranded.

**Chosen because:** CI on this repository already runs on every PR, so an
early draft PR turns it into a per-iteration full suite with no workflow
change, and bounded polling keeps the worker's session live.

**Superseded-by: D-16, D-20** (2026-10-09), in part — the setting gains a
third value, `local-then-ci`, and is read at each run's pre-flight; this
repository's switch moves from Task 13 to Task 17.

### D-6: The known-environmental list is one gitignored file per clone, proposed by workers and written on the operator's confirmation  (N)

**Decision:** The list lives at
`<primary checkout>/.claude/planwright.local/known-environmental.tsv`,
located from any worktree through git's common directory, and covered by
the existing `.claude/*.local/` ignore rule. Each line has four
tab-separated fields: test path, optional case label, reason, and date
recorded. It is read as data: paths are validated against the suite
directory before use, and no field is evaluated or used as a pattern.
Where no checkout sits above the common directory (a bare primary), the
reader warns once and treats the list as empty, so every failure is
handled as ordinary. The list is consulted only under `remote-ci`, so the
core default reproduces today's behavior (D-1). A local failure matching an
entry (the file, and where a case is named, an exact string match on the
runner's per-case failure label) is reported as known environmental and is
neither re-proven nor classified as logic. An entry never excuses a PR CI failure, and never
excuses a failure in any test the targeted check selects for the diff, so
"is this the worker's own change" is answered by the same selection that
chose what to run. A worker that shows a failure also fails
on a clean baseline proposes an entry through its normal operator channel
(the attended prompt, or an Awaiting-input entry when unattended); only the
operator's confirmation causes the skill's single list writer to add it,
by writing a temporary file and renaming it over the list so a concurrent
reader never sees a partial line. A listed test that passes locally is
flagged for removal in the worker's report, and removal takes the same
confirmation through the same writer.

**Alternatives considered:**
- Keys in the machine-local config overlay. Rejected because: the entries
  are a list of records with reasons and dates, not a scalar knob, and the
  overlay's config tooling resolves knobs.
- A per-worktree file. Rejected because: each fresh worktree would start
  empty and re-prove everything, which is the ritual being closed.
- Workers write entries themselves. Rejected because: a bad entry would
  hide a real failure until someone looked (drafting-session decision,
  2026-09-28).

**Chosen because:** one file per clone ends the re-proving everywhere at
once, the ignore rule keeps machine-specific detail out of commits, and
the operator's confirmation keeps a human judgment in front of anything
that silences a failure.

**Superseded-by: D-16** (2026-10-09), in part — the list is also
consulted in a fix round under `local-then-ci`.

### D-7: Review-loop wiring waits on the review-effectiveness amendment  (N)

**Decision:** The part of `remote-ci` that lets the review loop use PR CI as
its per-iteration full suite, and planwright's repository switching the
setting to `remote-ci`, form one task that is parked under `## Deferred`
with a free-text gate naming the review-effectiveness delta sign-off, and
whose `Done when:` names that precondition. The earlier tasks build the
setting and its `/execute-task` behavior with the core default untouched.

**Alternatives considered:**
- Wire the review loop now and amend review-effectiveness afterward.
  Rejected because: the loop would contradict a signed requirement
  (review-effectiveness REQ-D1.3) in the meantime.
- A structured gate. Rejected because: the gate grammar has no atom for "a
  delta re-sign-off landed", only bundle status and same-bundle tasks, and
  a status atom would not say it.
- A cross-bundle dependency edge. Rejected because: dependency edges cross
  no bundle boundary; a precondition on another bundle is stated in
  `Done when:`, as review-effectiveness's own tasks do.

**Chosen because:** it keeps every signed text true at every commit, while
the drain pass surfaces the gate verbatim so the parked task is not
forgotten.

**Superseded-by: D-20** (2026-10-09), in part — the parked task keeps the
review-loop wiring but no longer switches this repository to `remote-ci`.

### D-8: Long local runs use one portable detached recipe that proves it started  (N)

**Decision:** A documented helper runs the suite detached with `nohup` and
a backgrounded job, writing its log and an exit-code marker to fresh
per-run paths, then confirms before returning that the log exists and the
runner process is alive, failing loudly otherwise. It never removes an
earlier run's log, and a status verb reports running, finished with a code,
or never started. Every full local suite run `/execute-task` makes goes
through it, so no run depends on finishing inside one tool call.
`scripts/fleet-dispatch-headless.sh` already detaches with `nohup`, records
a launched marker and the runner pid, and handshakes on readiness; Task 12
reuses that detach-and-handshake step where it can be shared, and otherwise
records in its PR why it misfits.

**Alternatives considered:**
- `setsid nohup …`. Rejected because: `setsid` does not exist on macOS, and
  the launch fails silently inside a background job (obs:67861aa6).
- Leave it to each worker. Rejected because: the recorded failure is
  exactly a worker rediscovering it wrongly.
- Detach only runs predicted to exceed the tool-call limit. Rejected
  because: the prediction is the step workers got wrong, and detaching
  every run costs nothing.

**Chosen because:** an unverified launch is indistinguishable from no
launch, so the verification is the requirement, and `nohup` plus a
background job is portable to every platform in the support bar.

### D-9: Profile first; fix test-side causes; route production causes; enforce speed through CI later  (N)

**Decision:** The slowest files by the runner's timing report are profiled
on the operator's macOS host and on GitHub CI, attributing wall-clock to
process launches (including the first-execution assessment of freshly
written executables, D-14), fixture setup, sleeps and waits, and
production-script time, and measuring whether macOS per-process user or
group lookups inflate launch cost. The slowest files on a host are those
that, taken slowest first from an idle full run, make up the first half of
its total per-file wall-clock, including the file that crosses the halfway
mark, a rule that aims the effort where the time is and scales with the
suite. Where a candidate remedy costs nothing in the suite (a machine
setting), it is measured before any suite-wide change (D-14). The
measurements go in the profiling task's PR body.
Test-side causes are fixed or declined with a reason, including a sweep
replacing a test's own direct execution of copied fixtures with
interpreter invocation (PATH shims are D-14's).
Each production-side cause becomes an observation or a gated deferral
naming the owning bundle. No hand-measured speed target is set; a deferral
applies the existing `check:test-time` budgets to the macOS CI job once
universal-binary creates it.

**Alternatives considered:**
- Also optimize production hot paths the slow tests exercise. Rejected
  because: universal-binary's bake-off measures the shell layer's cost, and
  changing that baseline from outside would muddy its measurement
  (drafting-session decision, 2026-09-28).
- A fixed top-N of slow files. Rejected because: an enumerated count goes
  stale as the suite changes, where the cumulative-share rule does not.
- A target ratio of local idle time to CI time, measured by hand. Rejected
  because: `config/test-time-budget.yml` sets budgets only from the
  reference runner, and a target nobody re-measures rots.
- No link to the macOS job. Rejected because: macOS speed regressions
  would stay invisible until someone noticed.

**Chosen because:** attribution before fixing keeps effort on real causes,
the ownership split respects the bundle that owns the spawn-cost evidence,
and a CI-enforced budget cannot be forgotten.

### D-10: Busy-machine tolerance comes from one poll-until helper and a sweep; runner breakage is an environment error  (N)

**Decision:** A shared test helper polls a condition until a generous
deadline and, on timeout, fails with the elapsed time observed. A sweep
over the suite finds every assertion on elapsed time (fixed sleeps followed
by one check, wall-clock differences compared against a window) and
converts each wait for an event; an assertion that a minimum time elapsed
is not a wait and stays, listed with its reason; the fleet tests the seed names are where the sweep starts, not
its boundary. The runner checks its scratch directory before and after each
file and, when the directory is gone or unwritable, stops with exit 2
naming the cause instead of recording test failures.

**Alternatives considered:**
- Skip timing tests under detected high load. Rejected because: a skipped
  test proves nothing, and load detection is itself platform-specific.
- Rely on the ticket pool alone. Rejected because: the same windows break
  on a loaded CI runner or an adopter's busy machine, where no pool
  applies.

**Chosen because:** a poll-until-deadline check fails only when the event
really does not happen, and one helper keeps the sweep's conversions
uniform.

### D-11: macOS failures are fixed at their cause and guarded by a bash 3.2 parse check plus a pattern lint  (N)

**Decision:** The two scripts that do not parse under bash 3.2 are
rewritten so they do, Task 3 checking both the `bash` and the POSIX-mode
parse itself since the CI step parses each file in its one declared
dialect, and the symlinked-`TMPDIR` and Graphviz 15 test
failures are fixed in the tests (canonicalizing the temp path; making the
stub's precedence on `PATH` hold with a real `dot` installed). Two guards
follow. A CI step runs `bash -n` over every tracked file whose dialect is
`bash` and `bash --posix -n` over every one whose dialect is `sh`, inside
the official `bash:3.2` container image, pinned by digest. A file's dialect
is its shebang, else its `# shellcheck shell=` directive, which every
sourced library already carries; the step covers extension-less files such
as the git hooks, and fails on a tracked `.sh` file declaring neither, so a
new library cannot slip past it. The step's own misparsing fixtures live in
one excluded fixtures directory, and a test drives the step against them to
show it fails there. A local lint in
`mise run check` flags the specific constructs that misparsed, so a Linux
contributor catches them before pushing. Dependency adoption: the image is
Docker's official `library/bash` image, the same bash 3.2 release macOS
ships, used in CI only and never on an adopter's machine, pinned by digest
per the supply-chain discipline the workflow already follows.

**Alternatives considered:**
- Parse only shebanged files. Rejected because: the sourced libraries,
  the lock primitive among them, carry no shebang and would go unparsed.
- Add shebangs to the sourced libraries. Rejected because: it marks
  never-executed files as executables to every tool that reads shebangs.
- The lint alone. Rejected because: it catches only constructs someone
  already listed.
- The container check alone. Rejected because: it runs only in CI, after a
  push.
- Wait for universal-binary's macOS CI job. Rejected because: regressions
  would land unnoticed until it exists.

**Chosen because:** a real bash 3.2 parse is ground truth for this failure
class at a cost of seconds, and the lint moves the cheapest part of that
signal to before the push (operator's choice, 2026-09-28).

### D-12: Scripts are invoked the way their shebang says  (N)

**Decision:** A skill runs a repository script either by its resolved path,
so its shebang picks the interpreter, or through exactly the interpreter
the shebang names. The rule is stated in the existing script-invocation
doctrine that already governs every skill. A check in `mise run check`
reads each script's shebang and flags skill instructions that run a
bash-shebanged script through `sh`. Interpreter invocation of
`sh`-compatible test fixtures (D-9) is consistent with this rule.

**Alternatives considered:**
- Rewrite every bash script as POSIX sh. Rejected because: it is a large
  rewrite of working code in universal-binary's territory, and the failure
  is in the invocation, not the scripts.
- Document the rule without a check. Rejected because: the invocation
  convention already existed and was broken silently.

**Chosen because:** the shebang is already the source of truth for each
script's interpreter; the check makes the invocation agree with it
mechanically.

### D-13: Find the `core.hooksPath` writer first; wire at planwright's worktree creation; keep the check detect-only  (N)

**Decision:** An investigation task identifies, with evidence, what
rewrites the clone's `core.hooksPath` to an absolute path or clears it,
since no planwright script writes those forms. Where the writer is
planwright's, it is fixed; where it is outside planwright, it is recorded
as an observation for its owner. Either way, every worktree-creation path
planwright owns runs the existing wire step, so a fresh worktree starts
with `check:githooks` green whoever the writer is; Task 6 lists those
paths.
`scripts/check-githooks.sh` stays detect-only, as its own design requires.

**Alternatives considered:**
- Make the check accept an absolute path that resolves to the same
  directory. Rejected because: an absolute path makes every worktree run
  the primary checkout's hooks rather than its own branch's, which is the
  drift the check exists to report (obs:2f2cb594).
- Have the check wire on failure. Rejected because: the check's design
  keeps the fail-loud path reachable only while it never wires.
- Wire at every session start. Rejected because: it would mask the writer
  indefinitely instead of finding it.

**Chosen because:** repeated recorded recurrences without a known cause say
the remedy cannot be chosen before the cause is known, and wiring where
planwright creates worktrees fixes the symptom at the one point planwright
controls.

### D-14: First-execution stalls: measure the developer-tool exemption, then a warmed-shim helper only if it falls short  (N)

**Decision:** macOS assesses a freshly written executable the first time it
runs (the observations measured about 55 s under load, 0.3 s once
assessed), and the suite writes many: fixtures it runs and PATH shims the
code under test runs. The profile measures that stall with and without the
host's developer-tool exemption (the Privacy & Security setting that
exempts processes an app launches), for an attended run and for a
fleet-dispatched worker, since the exemption follows the app macOS holds
responsible for the process. Where it brings a freshly written
executable's first run within twice an already-assessed launch for both,
the remedy is a documented machine setup step and nothing ships in the
suite; where it falls short for either, the helper below ships.
Otherwise a shared test helper writes one executable per run, warms it
once, and makes every shim a symbolic link to it whose behavior lives in a
sourced, never-executed data file, so the assessment is paid once per run
rather than once per shim; a lint in `mise run check` flags a test marking
a file executable outside the helper. That task is parked behind the
profile's verdict.

**Alternatives considered:**
- Sign the fixtures. Rejected because: a script's signature lives in
  extended attributes that copies and fresh writes do not carry, so every
  shim would need a signing launch at creation, and a signature is not
  known to skip the assessment.
- Build the helper unconditionally. Rejected because: it migrates the whole
  suite before the cheaper machine-setting remedy is measured (D-9).
- Hard-link repository inodes, as the githooks test does. Rejected because:
  it covers only files that exist in the repository, not fabricated shims.
- Invoke every fixture through an interpreter. Rejected because: a PATH
  shim is run by the code under test, by name, so no interpreter prefix is
  possible.

**Chosen because:** it tries the remedy that costs nothing in the suite
first and commits to a suite-wide migration only on measured evidence that
the setting falls short for attended runs or fleet workers.

### D-15: The fix-round cadence is the same opt-in capability; this repository's value is `local-then-ci`  (N, supersedes D-1 in part)

**Decision:** The 2026-10-09 extension stays on D-1's rungs. The ability
to run fix rounds against CI on the pushed head is core capability,
behind `full_suite_evidence`, whose core default `local` keeps today's
behavior. The cadence this repository uses is its own value, set in its
repo-tracked overlay: `local-then-ci`, replacing the `remote-ci` D-1
named. The one doctrine change is the evidence rule inside the
Agent-resolvable predicate (D-18), because that predicate is doctrine every
value of the setting reads. The interim post-PR prompt step and the
worker-brief text are retired as the mechanism, because a prompt reaches
only the steps after it and cannot hold back `/execute-task`'s own suite.
The irreducible human gates are unchanged: the ready-flip still requires
green CI on the pull request's head, and merge stays the operator's.

**Alternatives considered:**
- State "after a pull request exists, CI on the pushed head is the gate of
  record" as a doctrine rule for every adopter. Rejected because: the
  evidence is still one repository's fleet (the seed and two
  observations), which customization-boundary does not let graduate a
  default.
- Keep the interim prompt step and strengthen the brief text. Rejected
  because: the seed's claim is that both run too late or only advise; a
  step at `post-pr` fires after the full suite already ran, and nothing
  enforces the brief.
- Keep `remote-ci` as this repository's end state. Rejected because: the
  operator's working rule keeps one full local suite before the pull
  request opens, which `remote-ci` drops (drafting-session decision,
  2026-10-09).

**Chosen because:** the pinned seed claim asks for enforcement, which a
setting value read by `/execute-task` gives, and D-1's
capability-versus-value split already places it.

### D-16: `local-then-ci` is a third value; a fix round is an open pull request at pre-flight  (N)

**Decision:** `full_suite_evidence` gains `local-then-ci` beside `local`
and `remote-ci`, resolved through `scripts/resolve-config-knob.sh` like the
other two, and read at each run's pre-flight rather than once per unit,
because a unit's fix rounds are separate runs. A run under it classifies
itself once, at pre-flight: a fix round when an open pull request exists
for the unit's branch, otherwise a first run that behaves exactly as
`local` (one full local suite, held in custom-steps' `full_suite_pool`
step pool when that wiring names one, then the draft pull request). The
read uses `gh` against the branch through a small classification helper
Task 16 ships, so the classification is testable with `gh` stubbed; when
the read fails (no remote, no `gh`, an authentication or network failure),
the run proceeds as `local` and records the reason in its convergence
summary. A fix round consults the known-environmental list as `remote-ci`
does, because its CI verdict is the same kind of evidence; a first run
does not, as under `local`.

**Alternatives considered:**
- A separate `fix_round_evidence` setting. Rejected because: under
  `remote-ci` it would do nothing, so two settings would carry one
  decision and a reader would have to resolve both (drafting-session
  decision, 2026-10-09).
- Change what `local` does on fix rounds. Rejected because: every
  adopter's workers would change behavior on upgrade (D-1).
- Halt to Awaiting input when the pull-request read fails, as REQ-B1.4
  does for an unreadable CI. Rejected because: falling back to `local`
  only adds verification, while a halt parks the unit over a transient
  read (drafting-session decision, 2026-10-09).
- Classify by whether the run is a re-dispatch of the unit. Rejected
  because: dispatch history does not say whether the pull request is
  still open; the pull request's state does.

**Chosen because:** the evidence source is one decision with three
cadences, and the pull request's existence is the line the operator's rule
draws.

### D-17: A fix round reuses `remote-ci`'s push-and-wait path after `post-pr`  (N)

**Decision:** Under `local-then-ci`, a fix round validates each change
and each review-loop fix with the targeted check
(`scripts/check-diff-scoped.sh`, as D-5 uses), runs no full local suite
anywhere in the run except the no-CI fallback below, and pushes at the
existing push step after `pre-pr`, writing the `Convergence: pending` line
REQ-B1.3 defines into the existing pull request's body. It runs the
`post-pr` point, then waits on CI for the branch's final head (a round
that added no commit gates the pull request's current head) through Task
10's `scripts/await-pr-ci.sh` under `pr_ci_wait`, with the verdicts, halts
and no-CI fallback REQ-B1.4 and REQ-B1.5 define. Before acting on a red
verdict it re-reads the head: CI cancels a superseded head's run and the
CI judge folds a cancellation into red, so a head that moved past the
gated one and contains it is awaited instead, and any other moved head
halts the round to Awaiting input naming both. A red verdict on an
unmoved head goes through the failure classifier exactly as a local
failure does: a logic failure halts to Awaiting input, a transient one is
retried under the adaptive policy. The round is handed off only on green
CI or on the no-CI fallback's green local suite, and the handoff replaces
the pending line with the convergence summary; a halted round leaves it.

**Alternatives considered:**
- Push each fix before convergence so the review loop sees CI per
  iteration, as `remote-ci` does. Rejected because: a fix round is
  usually small, so one CI run after the round's last fix is the cheaper
  proof, and a CI wait per iteration would multiply the round's wall
  time by its iteration count.
- A second wait helper for fix rounds. Rejected because: two pollers can
  drift on what counts as green; Task 10's helper already sources
  `rl_ci_state`.
- Run the full local suite once at the end of a fix round. Rejected
  because: that is the queued gate the seed records stalling a pull
  request for most of a day.
- Fix a logic failure forward, push it, and wait again. Rejected because:
  it departs from the escalate-immediately rule the retry policy and D-5
  apply to every run, and a fix round is no reason to retry a logic
  failure (delta re-walkthrough, 2026-10-09).
- Wait before the `post-pr` point. Rejected because: commits its steps
  push would go ungated.
- Write no `Convergence: pending` line, since the pull request carries the
  first run's summary. Rejected because: a halted round would leave a body
  reading converged over unverified commits.

**Chosen because:** every piece already exists or is already specified
(the push step, the targeted check, the wait helper, the pending line), so
the fix round is a branch in `/execute-task`'s CI and convergence steps,
not new machinery.

### D-18: Green CI on a pushed head containing the fix satisfies the predicate's project-CI condition  (N)

**Decision:** `doctrine/finding-categorization.md`'s Agent-resolvable
condition "Passing project CI" is amended to accept either a green full
local suite after the fix or a green CI run on a pushed head that contains
the fix, with no new regressions in either. A fix applied in a run whose
evidence is CI is applied on the targeted check and listed as awaiting
that run; it is reported resolved only once the run is green, and a red
run leaves it unresolved while the run handles the red verdict through the
failure classifier. Every other doctrine sentence that restates the
condition is amended in the same change. The reading is compatible with
review-effectiveness REQ-D1.3: CI on a head containing the fix runs the
full suite, so "the full suite" is met where it runs, the reading D-19
records for bootstrap; what D-20 still waits on is that requirement's
per-iteration cadence, not this predicate. The amendment also serves
`remote-ci`, which needs the same reading, so Task 10 takes an edge from
the task that lands it.

**Alternatives considered:**
- Keep the predicate and treat review fixes in a fix round as Needs
  sign-off. Rejected because: it moves every fix into the operator's
  checklist only because of where the suite ran, not because of what the
  fix is.
- Read "project CI" as already covering remote CI and change nothing.
  Rejected because: the condition's text says the full suite "passes after
  the fix", and a worker reading it literally runs the full suite locally,
  which is the behavior the seed reports.

**Chosen because:** the predicate's purpose is proof that the full suite
passes with the fix, and CI on a head containing the fix is that proof.

### D-19: Awaited CI on the run's own pushed head is "full project CI"  (N)

**Decision:** bootstrap REQ-E1.2 ("`/execute-task` SHALL run full project
CI") is met when the run triggers CI by pushing its head and waits for a
verdict on that head. This bundle records that reading and amends nothing
in bootstrap.

**Alternatives considered:**
- Amend bootstrap through its own delta. Rejected because: bootstrap is
  Done, so a delta would reopen it to Draft for a sentence the signed
  `remote-ci` design already reads this way (D-5), and the operator chose
  to record the reading instead (drafting-session decision, 2026-10-09).

**Chosen because:** the requirement's intent is that the full suite runs
and gates the unit; where it runs is not part of it, and D-5 already
relies on the same reading.

### D-20: Fix-round wiring waits on custom-steps and review-effectiveness; Task 13 keeps only the review-loop wiring  (N, supersedes D-7 in part)

**Decision:** The task that wires `local-then-ci` into `/execute-task`
(Task 16) is parked under `## Deferred` with a free-text gate naming two
delta sign-offs: custom-steps amending its attachment-point moments
(custom-steps D-3, REQ-A1.1) so a run whose first full CI run follows
`pre-pr` still has defined `pre-ci` and `convergence` moments, and
review-effectiveness amending its full-suite-per-iteration requirement
(review-effectiveness REQ-D1.3) to accept one CI run on the round's final
pushed head in place of a full suite per iteration. Its `Done when:` names both preconditions. Task 13 keeps the
review-loop wiring under `remote-ci` and its review-effectiveness gate
but no longer switches this repository's value; Task 17 sets
`local-then-ci` and removes the interim step once Task 16 lands.

**Alternatives considered:**
- Ship the `/execute-task` half now and wait only for the review-loop
  half. Rejected because: the operator accepted one gate for the whole
  value (drafting-session decision, 2026-10-09), and a value whose only CI
  run follows `pre-pr` while custom-steps still places the run's first full
  CI run before `convergence` would contradict signed text.
- Edit custom-steps' and review-effectiveness's text from this bundle.
  Rejected because: D-7's reason holds, signed text changes only through
  its owner's sign-off.
- A structured gate. Rejected because: D-7's reason holds, the gate
  grammar has no atom for another bundle's delta sign-off.

**Chosen because:** it keeps every signed text true at every commit, and
the drain pass surfaces the gate so the parked task is not forgotten.

### D-21: A per-file deadline in the runner, set by environment, 900 seconds by default  (N)

**Decision:** `scripts/run-tests.sh` runs each test file under a deadline
read from `PLANWRIGHT_TEST_FILE_DEADLINE` (a positive integer number of
seconds, default 900; anything else, `0` included, is malformed and falls
back to the default with one warning), using `timeout` or `gtimeout`,
whichever the host provides. A file
that passes the deadline is ended, recorded as failed with a message
naming the file and the deadline, and its ticket returned; with neither
tool on the host the runner warns once and runs files unbounded. A nested
runner exempted by REQ-A1.8 inherits the variable like any other.

**Alternatives considered:**
- A core config knob resolved through the overlays. Rejected because: the
  runner is this repository's mechanism (D-1), and the runner already
  takes environment knobs.
- A 1800-second default. Rejected because: a hung file would hold its
  run's whole-suite lock for up to half an hour (drafting-session decision,
  2026-10-09).
- A deadline on the whole suite instead. Rejected because: it cannot name
  the hung file, and a slow but healthy suite would trip it on a busy host.

**Chosen because:** the observed stall is one file that never returns,
and a per-file bound ends exactly that while naming it.

## Cross-cutting concerns

- **Data hygiene.** The known-environmental list and the ticket pool are
  machine-local and never committed; nothing in this bundle, its PRs, or
  its observations records machine paths beyond the documented
  home-relative defaults, hostnames, or user names.
- **Portability floor.** Every script change stays within the repository's
  bash 3.2 and BSD-tool floor; the D-11 guards exist to hold that floor.
- **Untrusted input.** The list's fields and the verdict `await-pr-ci.sh`
  reads from `rl_ci_state` are data: validated, never evaluated, and printed
  through the echo-safety sanitizer.
