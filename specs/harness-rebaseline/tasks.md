# Harness rebaseline — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-03
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. Every experiment task produces a report and candidate diffs
only; adoption is routed to the owning bundle (D-10).

## Tasks

### Task 1 — Measurement kit

- **Deliverables:** A script that turns one worker run into one
  machine-readable record from the fleet's own logs (worker event logs,
  approval statistics, PR and CI data): tool calls, prompts, denials,
  tokens, wall time, polish rounds, lens agents, CI outcome, plus the
  harness identity (planwright commit, plugin version, model, permission
  arm, changed knobs); a compare mode that refuses two records differing in
  more than the named variable; tests on recorded fixtures.
- **Done when:** A recorded fixture run yields a record with every field;
  a record missing a source log names the missing source instead of
  writing zeros; compare refuses a pair differing in two variables; the
  tests run in CI.
- **Dependencies:** none
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 2 days

### Task 2 — Benchmark replay

- **Deliverables:** A benchmark definition naming three to five recent
  merged tasks with their base commits and original briefs; a replay
  runner that starts each from a fresh disposable worktree at its base
  commit and grades the result against the merged PR (tests pass, the
  review eval set's findings, diff size relative to the merged diff).
- **Done when:** One benchmark task replays end to end in a disposable
  worktree and produces a graded record through the Task 1 kit; the runner
  refuses to start against a non-disposable home or overlay.
- **Dependencies:** Task 1
- **Citations:** D-3, D-6 · REQ-A1.3, REQ-B1.7
- **Estimated effort:** 2 days

### Task 3 — Baseline run

- **Deliverables:** The baseline report: today's harness on every benchmark
  task and on the review eval set, with the records it rests on.
- **Done when:** Every benchmark task has a baseline record; the review eval
  set's catch count is recorded; the report names the harness identity it
  measured.
- **Dependencies:** Task 2
- **Citations:** D-2, D-3 · REQ-A1.4
- **Estimated effort:** 1 day

### Task 4 — Known-bad set and offline replay

- **Deliverables:** The fixed known-bad call set as a fixture; an offline
  replay that feeds the recorded calls from the 2026-11-03 baseline, plus
  the known-bad set, through today's guards and returns each call's
  decision; the replay report for today's arm.
- **Done when:** Every known-bad call is a fixture with its expected
  decision; the replay reports per-category prompt, allow and deny counts
  for today's arm; changing the known-bad set marks every earlier replay
  stale.
- **Dependencies:** Task 1
- **Citations:** D-4, D-6 · REQ-B1.1, REQ-B1.3
- **Estimated effort:** 1 day

### Task 5 — Sandbox and hook profile

- **Deliverables:** A trial profile for disposable environments: sandbox
  settings with denyRead over secret locations, and a deterministic
  PermissionRequest hook carrying the guards that decides allow or deny
  with a reason, denying what it cannot classify; the Task 4 replay run
  through it.
- **Done when:** The hook blocks every known-bad fixture; an unclassifiable
  call gets a deny with a reason; the hook makes no model call; the
  offline replay reports the hook arm's prompt reduction against today's;
  a read of a secret location fails under the sandbox.
- **Dependencies:** Task 3, Task 4
- **Citations:** D-4, D-5 · REQ-B1.2, REQ-B1.4, REQ-B1.5
- **Estimated effort:** 2 days

### Task 6 — Live permission trial

- **Deliverables:** Live runs of the benchmark under the hook arm and under
  auto mode, in disposable environments, with the known-bad set exercised;
  the trial report with the adoption recommendation, stating any auto-mode
  recommendation as a fleet-autonomy D-19 delta.
- **Done when:** Each arm has benchmark records comparable to the baseline;
  the report states for each arm whether it blocked every known-bad call
  and its prompts per task against the baseline; benchmark quality is
  compared under the keep rule.
- **Dependencies:** Task 5
- **Citations:** D-4, D-6, D-11 · REQ-B1.2, REQ-B1.6, REQ-B1.7, REQ-F1.1
- **Estimated effort:** 2 days

### Task 7 — Verification-loop cuts

- **Deliverables:** Candidate diffs scaling polish rounds and lens fan-out
  to diff size (default cap two rounds) and removing self-check subagents;
  benchmark and review-eval runs of each; the experiment report.
- **Done when:** Each candidate has records comparable to the baseline; the
  report gives a keep or revert verdict for each under the keep rule.
- **Dependencies:** Task 3
- **Citations:** D-9, D-2 · REQ-C1.1, REQ-C1.2, REQ-F1.1, REQ-F1.2
- **Estimated effort:** 2 days

### Task 8 — Review-doctrine cuts

- **Deliverables:** Candidate diffs cutting review doctrine, each measured
  in a disposable worktree against the review eval set and the benchmark;
  the experiment report.
- **Done when:** Each candidate has an eval catch count and benchmark
  records; the report gives a keep or revert verdict for each; nothing is
  committed to doctrine on main.
- **Dependencies:** Task 3
- **Citations:** D-7, D-1 · REQ-D1.1, REQ-D1.3, REQ-F1.2
- **Estimated effort:** 2 days

### Task 9 — Execution eval

- **Deliverables:** An `/execute-task` eval covering its invariant
  refusals: the freshness-gate halt, a non-Ready spec refused, and a Ready
  spec accepted, under the existing behavioral-eval harness.
- **Done when:** Every case passes on the baseline harness; each case fails
  when its refusal is removed from a disposable copy of the skill.
- **Dependencies:** none
- **Citations:** D-7 · REQ-D1.2
- **Estimated effort:** 1 day

### Task 10 — Execution-doctrine cuts

- **Deliverables:** Candidate diffs cutting execution doctrine, each
  measured against the execution eval and the benchmark; the experiment
  report.
- **Done when:** Each candidate has eval and benchmark records; the report
  gives a keep or revert verdict for each; nothing is committed to doctrine
  on main.
- **Dependencies:** Task 9, Task 3
- **Citations:** D-7, D-1 · REQ-D1.2, REQ-D1.3, REQ-F1.2
- **Estimated effort:** 2 days

### Task 11 — Guard catch and friction log

- **Deliverables:** A log recording every guard firing during trial and
  benchmark runs with its outcome (real catch or legitimate work stopped);
  the guard report naming the hard limits as kept and each removal
  candidate with its evidence.
- **Done when:** Every guard firing in the trial window lands in the log;
  the report lists the hard limits as kept regardless; a removal candidate
  appears only with zero real catches and recorded friction.
- **Dependencies:** Task 1
- **Citations:** D-8 · REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 1 day

### Task 12 — Evidence-integrity checks

- **Deliverables:** A hardened step-record check that refuses a record
  whose head, run or outcome does not match the branch it claims; a
  fixture reproducing the faked step record from 2026-11-03; the change
  proposed to the owning bundle.
- **Done when:** The fixture is refused; genuine records still pass; the
  change is routed to its owner as an amendment request with the fixture.
- **Dependencies:** Task 1
- **Citations:** D-8, D-10 · REQ-E1.4, REQ-F1.3
- **Estimated effort:** 1 day

### Task 13 — Results and handoff

- **Deliverables:** A results summary across every experiment report; for
  each cut the operator approves, a pending note or amendment request filed
  for its owning bundle.
- **Done when:** Every experiment has a report with a verdict; every
  approved cut has a routed note naming its owner; no cut was applied by
  this bundle.
- **Dependencies:** Task 6, Task 7, Task 8, Task 10, Task 11, Task 12
- **Citations:** D-10, D-2 · REQ-F1.1, REQ-F1.2, REQ-F1.3
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
