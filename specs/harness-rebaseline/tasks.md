# Harness rebaseline — Tasks

**Status:** Ready
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. Every experiment task produces a report and candidate diffs
only; adoption is routed to the owning bundle, or to the operator for the
worker briefs (D-10).

## Tasks

### Task 1 — Measurement kit

- **Deliverables:** A script that turns one worker run into one
  machine-readable record from the fleet's shipped logs (worker event logs,
  the allow-audit logs, the local gate output): tool calls, prompts,
  denials, tokens (input, output and cache, over the session and its
  subagents), wall time, polish rounds, lens agents, the run outcome
  (completed, rate-limited, crashed, timed out) and the local gate result,
  plus the harness identity (planwright commit as the pinned plugin build's
  source commit, plugin build, claude CLI version, resolved model map,
  worker-brief variant, permission arm, known-bad set hash, candidate diff
  hash, changed knobs); token-value scrubbing; a compare mode that refuses
  two records differing in more than the named variable or in the
  known-bad set hash; a shared report writer every experiment task uses,
  which emits no recorded command, machine path or token; tests on
  synthetic fixtures in the fleet's log formats.
- **Done when:** A synthetic fixture run yields a record with every field;
  a record missing a source log names the missing source instead of
  writing zeros; a fixture carrying a token value yields a record without
  it; compare refuses a pair differing in two variables and a pair with
  different known-bad hashes; a report written from fixture records holds
  no command text, absolute home path or token value; the tests run in CI.
- **Dependencies:** none
- **Citations:** D-2, D-6 · REQ-A1.1, REQ-A1.2, REQ-A1.7, REQ-B1.7
- **Estimated effort:** 2 days

### Task 2 — Benchmark replay runner

- **Deliverables:** A benchmark definition naming three to five merged
  tasks with their base commits and original briefs; a replay runner that
  starts each from a fresh disposable worktree, home, fleet home and
  overlay cloned with no push remote, inside its own process namespace,
  loads the pinned plugin build plus the arm's candidate diff from the
  disposable worktree, sets the worker-brief lines the arm names,
  authenticates from a subscription OAuth token in its environment, runs
  the local gate through `scripts/full-suite-run.sh` on the real fleet's
  suite pool, waits until the real fleet's live workers plus running trial
  runs are under `fleet_concurrency_normal`, aborts at a wall-time limit,
  harvests the run's logs into the machine-local state home before
  teardown, re-runs invalid runs, and grades each run against the merged PR
  (the merged PR's added tests on the replay, failing is worse; diff-size
  distance from the merged diff, larger is worse); a single-case entry that
  runs one disposable bundle state through a skill and reports the step it
  stopped at, for the execution eval; a backtest wrapper that points
  `--remote` at a local bare mirror and `BACKTEST_PLANWRIGHT_ROOT` at the
  arm's disposable worktree.
- **Done when:** One benchmark task replays end to end in a disposable
  environment and produces a graded record through the Task 1 kit; the
  runner refuses a benchmark with fewer than three or more than five tasks,
  a home, fleet home, overlay or remote that resolves to the real one, and
  a start with no token in the environment; after a fixture run the
  disposable home holds no credential file, the clone has no push remote,
  and no GitHub credential was in the run's environment; a fixture run's
  processes sit in their own namespace; a fixture replay is graded with the
  stated directions; rate-limited, crashed and timed-out fixture runs are
  each re-run, not graded; the gate goes through the pool, a start waits
  while the fleet is at its cap, and an over-limit fixture run is recorded
  as timed out; the single-case entry reports a fixture case's stopping
  step; the backtest wrapper never passes the real remote; the tests run in
  CI on synthetic fixtures.
- **Dependencies:** Task 1
- **Citations:** D-3, D-6, D-2 · REQ-A1.3, REQ-A1.5, REQ-A1.6, REQ-A1.7,
  REQ-B1.7
- **Estimated effort:** 3 days

### Task 4 — Known-bad set, classifier and offline replay

- **Deliverables:** The fixed known-bad call set as synthetic fixtures; one
  deterministic category classifier, independent of any hook code; the
  scripted vetter that stands in for the tower in today's arm (allows calls
  outside the set, denies calls in it, counts each as a prompt); the local,
  uncommitted, owner-only snapshot of the 2026-11-03 recorded calls; an
  offline replay that feeds the snapshot plus the known-bad set through
  today's allowlist and guards; the replay report for today's arm.
- **Done when:** Every known-bad category has a fixture with its expected
  decision; the classifier assigns every fixture its category; the scripted
  vetter allows a fixture call outside the set, denies one inside it, and
  counts each as a prompt; the replay
  reports per-category prompt, allow and deny counts for today's arm and no
  command text; the replay refuses an auto-mode arm; the snapshot sits
  outside the repository with owner-only permissions; changing the
  known-bad set changes its hash, so every earlier record compares stale;
  the tests run in CI on synthetic fixtures.
- **Dependencies:** Task 1
- **Citations:** D-4, D-6 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-A1.7
- **Estimated effort:** 2 days

### Task 3 — Baseline run

- **Deliverables:** The baseline report: today's arm (with the scripted
  vetter), with worker briefs minus the 2026-11-03 quick wins, on every
  benchmark task and on the review backtest, three runs of each, with the
  records it rests on and the pinned harness identity every later arm must
  match.
- **Done when:** Every benchmark task has three valid baseline records; the
  review backtest has three recorded runs with per-class catches; the
  harness identity records briefs without the two-round polish stop and the
  mktemp-probe rule; the committed report carries no recorded command,
  machine path or token (REQ-A1.7).
- **Dependencies:** Task 2, Task 4
- **Citations:** D-2, D-3, D-9 · REQ-A1.4, REQ-F1.2
- **Estimated effort:** 1 day

### Task 5 — Sandbox and hook profile

- **Deliverables:** A trial profile for disposable environments: today's
  allowlist and guards plus sandbox settings with denyRead over secret
  locations named by absolute real-home path, and a deterministic
  PermissionRequest hook ordered after the fleet's liveness
  PermissionRequest hook, built by calling the existing guard scripts and
  the Task 4 classifier, deciding allow or deny with a reason; a test
  fixture pinning the expected secret locations independent of the settings
  generator; a pre-run check for the sandbox's runtime dependencies that
  parks for the operator rather than installing one; the Task 4 replay run
  through the hook arm; the hook-arm replay report, noting why a
  PermissionRequest hook is needed beside the existing allow-only hook.
- **Done when:** The hook denies every known-bad fixture; every deny
  carries a reason naming the rule and a permitted alternative or stating
  that none exists; an unclassifiable call is denied with such a reason; no
  fixture path produces an ask; a static check over the hook and every script it calls finds no model
  invocation, and the fixtures pass with a failing `claude` stub on PATH; a
  static CI check finds every pinned secret location under denyRead and
  none in the allowlist; the replay report gives the hook arm's prompts
  plus denials of calls outside the known-bad set against today's arm's
  prompts; a live read of a secret location fails under the sandbox,
  recorded in the report; a missing runtime dependency parks the task.
- **Dependencies:** Task 3, Task 4
- **Citations:** D-4, D-5 · REQ-B1.2, REQ-B1.4, REQ-B1.5
- **Estimated effort:** 2 days

### Task 6 — Live permission trial

- **Deliverables:** A scripted canary probe session per known-bad category
  (a decoy process the runner spawned, a decoy path in the disposable home,
  a runner-made decoy path the classifier treats as live configuration, a
  bounded load), with tests on synthetic targets; live runs of the benchmark under the hook arm and under
  auto mode through the Task 2 runner, three per task; the probes run
  under every arm; the trial report
  with a keep or revert verdict and an adoption recommendation per arm, a
  hook-arm recommendation stated as worker-permission-ergonomics D-3 and
  fleet-autonomy D-19 deltas and an auto-mode one as a fleet-autonomy D-19
  delta.
- **Done when:** Each arm has three valid records per benchmark task
  comparable to the baseline; the report states for each arm, per known-bad
  category, that a probe was attempted and whether it was blocked (a deny or
  sandbox refusal, never a prompt); it states each arm's prompts plus
  denials of calls outside the known-bad set per benchmark task, averaged
  over three runs, against the baseline's average prompts; it applies the
  keep rule to quality, recording the backtest clause as not applicable; it
  states tokens spent; a probe refuses a synthetic target the runner did
  not create, in a test run in CI.
- **Dependencies:** Task 5
- **Citations:** D-4, D-6, D-11, D-2 · REQ-B1.2, REQ-B1.6, REQ-B1.7,
  REQ-B1.8, REQ-F1.1, REQ-F1.2
- **Estimated effort:** 2 days

### Task 7 — Verification-loop cuts

- **Deliverables:** A candidate list for operator approval before any run
  (the diff-size curve for polish rounds and lens fan-out, default cap two
  rounds; the self-check spawn sites, excluding the lens fan-out); three
  arms, each applying only its own variable to the baseline harness: the
  2026-11-03 brief quick wins, diff-size scaling, and self-check removal;
  three benchmark runs per task per arm, and three review backtest runs for
  an arm whose variable reaches the backtest reviewer (the lens fan-out
  scaling, through a stated `--reviewer`); the experiment report.
- **Done when:** The operator approved the candidate list before the first
  run; each arm has three valid records per benchmark task, comparable to
  the baseline; each arm has three backtest runs or the backtest clause
  recorded as not applicable with its reason; the report gives a keep or
  revert verdict per arm under the keep rule, with tokens spent; the
  quick-win verdict is flagged for the operator as owner of the briefs.
- **Dependencies:** Task 3
- **Citations:** D-9, D-2, D-10 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-F1.1,
  REQ-F1.2, REQ-F1.4
- **Estimated effort:** 2 days

### Task 8 — Review-doctrine cuts

- **Deliverables:** A candidate list for operator approval before any run,
  naming each doctrine section cut; candidate diffs, each measured in a
  disposable worktree with three review backtest runs and three benchmark
  runs per task; the experiment report.
- **Done when:** The operator approved the candidate list before the first
  run; each candidate has per-class backtest catches from three runs and
  three valid records per benchmark task; the report gives a keep or revert
  verdict for each, with tokens spent; no merged PR of this task edits a
  shipped surface (REQ-D1.3).
- **Dependencies:** Task 3
- **Citations:** D-7, D-1, D-2 · REQ-D1.1, REQ-D1.3, REQ-F1.1, REQ-F1.2,
  REQ-F1.4
- **Estimated effort:** 2 days

### Task 9 — Execution eval

- **Deliverables:** An `/execute-task` eval covering at least its invariant
  refusals (the freshness-gate halt, a non-Ready spec refused, a Ready spec
  accepted), each case a disposable bundle state driven through the real
  skill by the Task 2 runner's single-case entry, acceptance judged at the
  first step after the freshness gate, before any push; a CI structural
  check that every case definition is present and well formed; the recorded
  results.
- **Done when:** The structural check runs in CI; every case passes under
  today's harness, recorded with its harness identity; each case fails when
  its refusal is removed from a disposable copy of the skill, each failing
  run recorded.
- **Dependencies:** Task 2
- **Citations:** D-7 · REQ-D1.2
- **Estimated effort:** 2 days

### Task 10 — Execution-doctrine cuts

- **Deliverables:** A re-run of the execution eval under the baseline's
  harness identity; a candidate list for operator approval before any
  candidate run, naming each doctrine or skill section cut; candidate diffs,
  each measured against the execution eval and three benchmark runs per
  task, plus three review backtest runs when its diff touches a file the
  backtest reviewer loads; the experiment report.
- **Done when:** Every execution-eval case passes under the baseline's
  harness identity before the first candidate run; the operator approved
  the candidate list; each candidate has eval results, three valid records
  per benchmark task, and per-class backtest catches or the backtest clause
  recorded as not applicable with its reason; the report gives a keep or
  revert verdict for each, with tokens spent; no merged PR of this task
  edits a shipped surface (REQ-D1.3).
- **Dependencies:** Task 9, Task 3
- **Citations:** D-7, D-1, D-2 · REQ-D1.2, REQ-D1.3, REQ-F1.1, REQ-F1.2,
  REQ-F1.4
- **Estimated effort:** 2 days

### Task 11 — Guard log builder

- **Deliverables:** A guard inventory naming every guard that fires on a
  tool call or a PR flip and its firing source; a log builder that reads
  each guard's firings back from the harvested run logs, groups them by
  distinct normalized call shape per guard, excludes firings on scripted
  probes, labels a shape the Task 4 classifier matches as a real catch, and
  leaves every other shape for the operator to label (real catch,
  legitimate work stopped, or benign); tests on synthetic firings.
- **Done when:** A synthetic firing lands in the log under its shape; a
  known-bad-category shape is labelled a real catch; a probe firing is
  excluded; any other shape is left unlabelled; a guard with no firings
  appears as unexercised; the tests run in CI.
- **Dependencies:** Task 1, Task 4
- **Citations:** D-8 · REQ-E1.1
- **Estimated effort:** 1 day

### Task 12 — Step-record check hardening

- **Deliverables:** A hardened step-record check (custom-steps' surface)
  that refuses a record whose head, run or outcome does not match the
  branch it claims, landed on main in this bundle (the D-1 exception);
  refused fixtures for each mismatch kind, a fixture reproducing the faked
  step record from 2026-11-03, and a genuine fixture that passes; a
  read-only run of the hardened check over the fleet's current records.
- **Done when:** Each mismatch fixture and the 2026-11-03 reproduction are
  refused; the genuine fixture passes; the read-only run reports zero false
  refusals, or the PR lists each one; the tests run in CI.
- **Dependencies:** none
- **Citations:** D-1, D-8 · REQ-E1.4
- **Estimated effort:** 1 day

### Task 14 — Guard report

- **Deliverables:** The guard log built over the whole trial window; the
  guard report naming the hard limits and the step-record check as kept and
  each removal candidate with its evidence, after the operator has labelled
  every shape the classifier did not.
- **Done when:** Every inventoried guard has a row, unexercised ones
  included; every shape is labelled; the report lists the hard limits and
  the step-record check as kept regardless; a removal candidate appears only
  with zero real catches and at least one shape labelled legitimate work
  stopped; the committed report carries no recorded command, machine path
  or token (REQ-A1.7).
- **Dependencies:** Task 6, Task 7, Task 8, Task 10, Task 11
- **Citations:** D-8 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-A1.7
- **Estimated effort:** 1 day

### Task 13 — Results and handoff

- **Deliverables:** A results summary across the experiment reports of
  Tasks 6, 7, 8 and 10 and the guard report of Task 14, recording the
  operator's approve or decline decision for every keep verdict, adoption
  recommendation and removal candidate; for each approval, a pending note or
  amendment request filed for the owning bundle, or a report to the
  operator for the worker briefs.
- **Done when:** Every listed report has a verdict and a recorded operator
  decision; every approval has a routed note naming its owner, or an
  operator report; no merged PR of this bundle edited a shipped surface
  (REQ-D1.3) except Task 12's step-record check.
- **Dependencies:** Task 6, Task 7, Task 8, Task 10, Task 12, Task 14
- **Citations:** D-10, D-2 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-D1.3
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
