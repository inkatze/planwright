# Test throughput — Design

**Status:** Draft
**Last reviewed:** 2026-09-28
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
doctrine rule is minted: the evidence that CI-first verification
generalizes comes from one repository's fleet so far.

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

### D-2: The ticket pool is a set of numbered lock-lib locks with dead-holder reclaim  (N)

**Decision:** The pool is a directory of numbered ticket paths, one per
unit of capacity. A test worker takes a ticket by attempting each numbered
path with `lock-lib.sh`'s one-attempt acquire, holding it as the process
that runs the test file, and releases it with the ownership-verified
release when the file finishes. A path whose recorded owner is no longer
running is cleared and retaken, which is what makes the pool crash-safe. A
worker that finds no free ticket waits with a bounded backoff and tries
again.

**Alternatives considered:**
- `mkdir`-based slot locks. Rejected because: `lock-lib.sh` records `mkdir`
  losing mutual exclusion across the release-and-reacquire cycle, and
  `check:lock-primitive` rejects it as an acquisition signal.
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
environment layer (`mise.local.toml`). A run still starts its own
`PLANWRIGHT_TEST_JOBS` (default core count) workers, and each blocks on a
ticket, so the per-run cap and the machine-wide cap both hold. Runs that
disagree on capacity use tickets numbered up to their own value; the
effective machine-wide bound is the largest value in use, which the runner
documents. An unusable pool (unresolvable, refused, unwritable, or a
`lock-lib.sh` real error) produces one warning naming the cause and an
unpooled run. Each worker records the time it waited for a ticket in its
own record, starts its file's timing only after it holds a ticket, and the
timing report carries the wait as its own column.

**Alternatives considered:**
- Fail the run when the pool is unusable. Rejected because: the operator
  chose never blocking testing over guaranteed exclusion
  (drafting-session decision, 2026-09-28).
- Count wait inside the per-file time. Rejected because: `check:test-time`
  budgets measure a file's cost, and a busy machine must not make a file
  look slow.
- Replace `PLANWRIGHT_TEST_JOBS` with the pool. Rejected because: the
  serial fallback, the runner's own tests, and CI all depend on the per-run
  knob, and it costs nothing to keep.

**Chosen because:** it bounds the machine without changing a solitary
run's behavior, keeps every existing knob meaningful, and keeps the timing
budgets measuring what they were set from.

### D-5: `full_suite_evidence: remote-ci` opens the draft PR early and waits on PR CI by bounded polling  (N)

**Decision:** `full_suite_evidence` takes `local` (core default) or
`remote-ci`. Under `remote-ci`, `/execute-task`:
- validates each change with the targeted check (tests touching the
  changed files, plus the linters), reusing the diff-scoped check
  `scripts/check-diff-scoped.sh` that review-effectiveness Task 6 builds
  rather than a second selector;
- opens the draft PR once the first implementation passes it, and pushes
  every subsequent iteration;
- takes a green PR CI run on the branch's current head as the full-suite
  evidence, and never reports convergence without it;
- waits through a new helper, `scripts/await-pr-ci.sh`, that polls the
  PR's checks in foreground calls bounded under the tool-call limit and
  prints one verdict: green, red, pending past its bound, or no CI;
- on "no CI" (no remote, no PR-triggered workflow, the provider
  unreachable), falls back to the full local suite through the ticket pool
  and records which evidence it used.

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
- Wait for CI by yielding the session to a notification. Rejected because:
  that is the stall obs:67861aa6 records, where a worker sits idle with
  work stranded.

**Chosen because:** CI on this repository already runs on every PR, so an
early draft PR turns it into a per-iteration full suite with no workflow
change, and bounded polling keeps the worker's session live.

### D-6: The known-environmental list is one gitignored file per clone, proposed by workers and written by the operator  (N)

**Decision:** The list lives at
`<primary checkout>/.claude/planwright.local/known-environmental.tsv`,
located from any worktree through git's common directory, and covered by
the existing `.claude/*.local/` ignore rule. Each line has four
tab-separated fields: test path, optional case label, reason, and date
recorded. It is read as data: paths are validated against the suite
directory before use, and no field is evaluated or used as a pattern. A
local failure matching an entry (the file, and the case where one is
named) is reported as known environmental and is neither re-proven nor
classified as logic. An entry never excuses a PR CI failure, and never
excuses a failure in any test the targeted check selects for the diff, so
"is this the worker's own change" is answered by the same selection that
chose what to run. A worker that shows a failure also fails
on a clean baseline proposes an entry through its normal operator channel
(the attended prompt, or an Awaiting-input entry when unattended); only the
operator's confirmation writes it. A listed test that passes locally is
flagged for removal in the worker's report.

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

### D-8: Long local runs use one portable detached recipe that proves it started  (N)

**Decision:** A documented helper runs the suite detached with `nohup` and
a backgrounded job, writing its log and an exit-code marker to fresh
per-run paths, then confirms before returning that the log exists and the
runner process is alive, failing loudly otherwise. It never removes an
earlier run's log, and a status verb reports running, finished with a code,
or never started.

**Alternatives considered:**
- `setsid nohup …`. Rejected because: `setsid` does not exist on macOS, and
  the launch fails silently inside a background job (obs:67861aa6).
- Leave it to each worker. Rejected because: the recorded failure is
  exactly a worker rediscovering it wrongly.

**Chosen because:** an unverified launch is indistinguishable from no
launch, so the verification is the requirement, and `nohup` plus a
background job is portable to every platform in the support bar.

### D-9: Profile first; fix test-side causes; route production causes; enforce speed through CI later  (N)

**Decision:** The slowest files by the runner's timing report are profiled
on the operator's macOS host and on GitHub CI, attributing wall-clock to
process launches, fixture setup, sleeps and waits, and production-script
time, and measuring whether macOS per-process user or group lookups inflate
launch cost. The measurements go in the profiling task's PR body.
Test-side causes are fixed or declined with a reason, including a sweep
replacing direct execution of copied fixtures with interpreter invocation.
Each production-side cause becomes an observation or a gated deferral
naming the owning bundle. No hand-measured speed target is set; a deferral
applies the existing `check:test-time` budgets to the macOS CI job once
universal-binary creates it.

**Alternatives considered:**
- Also optimize production hot paths the slow tests exercise. Rejected
  because: universal-binary's bake-off measures the shell layer's cost, and
  changing that baseline from outside would muddy its measurement
  (drafting-session decision, 2026-09-28).
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
converts it; the fleet tests the seed names are where the sweep starts, not
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
rewritten so they do, and the symlinked-`TMPDIR` and Graphviz 15 test
failures are fixed in the tests (canonicalizing the temp path; making the
stub's precedence on `PATH` hold with a real `dot` installed). Two guards
follow. A CI step runs `bash -n` over every bash-shebanged script and
`bash --posix -n` over every `sh`-shebanged one inside the official
`bash:3.2` container image, pinned by digest. A local lint in
`mise run check` flags the specific constructs that misparsed, so a Linux
contributor catches them before pushing. Dependency adoption: the image is
Docker's official `library/bash` image, the same bash 3.2 release macOS
ships, used in CI only and never on an adopter's machine, pinned by digest
per the supply-chain discipline the workflow already follows.

**Alternatives considered:**
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
the shebang names. A check in `mise run check` reads each script's shebang
and flags skill instructions that run a bash-shebanged script through
`sh`. Interpreter invocation of `sh`-compatible test fixtures (D-9) is
consistent with this rule.

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
since no planwright script writes those forms. The remedy follows the
evidence: where the writer is planwright's, it is fixed; where it is
outside planwright, the worktree-creation paths planwright owns run the
existing wire step so a fresh worktree starts with `check:githooks` green,
and the writer is recorded as an observation for its owner.
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

## Cross-cutting concerns

- **Data hygiene.** The known-environmental list and the ticket pool are
  machine-local and never committed; nothing in this bundle, its PRs, or
  its observations records machine paths beyond the documented
  home-relative defaults, hostnames, or user names.
- **Portability floor.** Every script change stays within the repository's
  bash 3.2 and BSD-tool floor; the D-11 guards exist to hold that floor.
- **Untrusted input.** The list's fields and the PR-check output that
  `await-pr-ci.sh` parses are data: validated, never evaluated, and printed
  through the echo-safety sanitizer.
