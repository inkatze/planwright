# Harness rebaseline — Requirements

**Status:** Ready
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Measure what each part of planwright costs and catches, then cut what
doesn't earn its keep, keeping a cut only when the measurements don't get
worse.

planwright grew its permission layer, verification loops and doctrine one
observed failure at a time, under older models. Nobody has measured which
parts still pay for themselves: a third to half of every worker's tool calls
stop for the tower, polish can run five rounds on a small helper, and the
instruction budget is saturated, while the deterministic guards and the
tower's judgment still catch real harm. This bundle builds the measurement
harness, takes a baseline, runs one experiment per candidate cut, and reports
a keep-or-revert verdict for each. It is a measurement harness plus reports:
it never edits doctrine, skills, guards or settings itself, save one check it
only tightens; an adopted cut lands through the bundle that owns the surface
(D-1, D-10).

## Scope

### In scope

- A measurement kit that reads what the fleet already records (worker event
  logs, the fleet's allow-audit logs, the local gate result) into one record
  per run.
- A benchmark of merged tasks replayed from fresh disposable worktrees at
  their base commits, graded against what actually merged.
- A baseline run of today's harness, minus the unmeasured 2026-11-03 brief
  quick wins, on the benchmark and the review eval set.
- A permission trial with three arms: today's allowlist and guards; the same
  plus a sandbox and a deterministic PermissionRequest hook; Claude Code's
  auto mode. Recorded calls replay offline first, then the arms run live.
- Verification-loop cuts: polish rounds and lens fan-out scaled to diff
  size, and self-check subagents removed where the measurements allow.
- Doctrine cuts: review doctrine measured against the review eval set; an
  execution eval built first, then execution doctrine cuts.
- Guards: a catch and friction log for every guard that fires on a tool call
  or a PR flip, the hard limits kept, friction guards removable on evidence,
  and the step-record check hardened.
- A results report per experiment and an operator decision per adoption.

### Out of scope

- The cloud backend.
- The company thin version (guards as hooks, spec templates, a measured
  review gate); it waits for this bundle's results.
- The review desk.
- tower-control-plane, on hold until the permission trial reports.
- Editing doctrine, skills, guards or settings on main directly: every
  adopted cut is routed to its owning bundle (D-10). The one exception is
  the step-record hardening of REQ-E1.4, which only tightens (D-1).
- Removing a hard limit (merge, push to a protected branch, force push),
  whatever its measured friction (D-8).
- The CI check scripts (`scripts/check-*.sh`) as removal candidates: they do
  not fire on a tool call, so the catch and friction log does not cover them
  (D-8).

## REQ-A — Baseline

- **REQ-A1.1** A measurement kit SHALL turn each worker run into one
  machine-readable record holding at least: tool calls, permission prompts,
  denials, tokens (input, output and cache, totalled over the session and
  every subagent it spawned), wall time, polish rounds, lens agents spawned,
  the run outcome (completed, rate-limited, crashed or timed out), and the
  local gate result. It SHALL read the worker event logs, the fleet's
  allow-audit logs and the local gate output, never a worker's own account of
  itself, and SHALL name a missing source instead of writing zeros.
  *(Cites: D-2; the approval-stats baseline (Sources).)*
- **REQ-A1.2** Every record SHALL name the harness under test: planwright
  commit (the commit the pinned plugin build comes from; merges of this
  bundle's own harness tooling do not move it), plugin build, claude CLI
  version, resolved model map, worker-brief variant, permission arm, the
  known-bad set's hash, the candidate diff's hash, and the knobs a cut
  changes. Two records SHALL be compared only when they differ in
  the one variable an experiment changes. Every arm SHALL run at the
  baseline's planwright commit, plugin build, model map and CLI version with
  only its candidate change loaded; a change to any of those SHALL re-take
  the baseline before further experiments.
  *(Cites: D-2.)*
- **REQ-A1.3** A benchmark SHALL replay a fixed, named set of merged tasks,
  at least three and at most five. Each replay SHALL start from a fresh
  disposable worktree at the task's original base commit, with the task's
  original brief and the worker-brief lines the arm sets; the base commit
  fixes only the code the task edits, and the harness under test is the
  pinned plugin build plus the arm's candidate diff loaded from the
  disposable worktree. Each replay SHALL be graded against the merged PR on
  two measures: whether the merged PR's added tests pass on the replay
  (failing is worse), and the replay's diff-size distance from the merged
  diff, |replay lines - merged lines| / merged lines (larger is worse).
  *(Cites: D-3.)*
- **REQ-A1.4** A baseline run of today's harness on the benchmark and on the
  review eval set (the review backtest, `scripts/review-backtest.sh` over its
  corpus) SHALL be recorded before any experiment runs, three runs of each,
  and every experiment's verdict SHALL be judged against it. The baseline's
  worker briefs SHALL omit the 2026-11-03 quick wins (the two-round polish
  stop and the mktemp-probe rule), which are measured as an experiment
  (REQ-C1.3).
  *(Cites: D-2, D-3, D-9.)*
- **REQ-A1.5** A run whose outcome is rate-limited, crashed or timed out
  SHALL be invalid and re-run, never graded, in the baseline and in every
  arm.
  *(Cites: D-2.)*
- **REQ-A1.6** Each live run's local gate SHALL run through
  `scripts/full-suite-run.sh` on the real fleet's suite pool, and the runner
  SHALL wait to start a live run until the real fleet's live workers plus
  running trial runs number fewer than `fleet_concurrency_normal`. A live run
  SHALL abort at a wall-time limit, the abort recorded as timed out. The
  pool slot and the worker count are the only real fleet state a run
  touches, named exceptions to REQ-B1.7.
  *(Cites: D-6.)*
- **REQ-A1.7** The 2026-11-03 recorded calls SHALL be kept as a local,
  uncommitted, owner-only snapshot for the life of this bundle, and run
  records SHALL live in the machine-local state home. Committed reports
  SHALL NOT carry recorded commands, machine paths, tokens or
  private-repository detail.
  *(Cites: D-6; security-posture (Sources).)*

## REQ-B — Permission trial

- **REQ-B1.1** The known-bad call set SHALL be fixed before any arm runs,
  the baseline included, and SHALL hold at least: a kill of an exited or
  reused PID, a pattern kill, a write outside the worker's worktree, a write
  to live configuration or the real home, a load generator, and a read of
  another process's environment. One deterministic category classifier,
  independent of the hook's code, SHALL decide whether a call belongs to a
  category. Any change to the set SHALL mark every replay and live record made
  under the earlier set stale and re-run them.
  *(Cites: D-4; the 2026-11-03 tower analysis (Sources); drafting-session
  decision (Sources).)*
- **REQ-B1.2** The trial SHALL compare three arms. Today's arm: the static
  allowlist, the PreToolUse guards and allow hook, and, in a disposable run, a
  scripted vetter that allows every call outside the known-bad set, denies
  every call in it, and counts each as a prompt. The hook arm: today's
  allowlist and guards plus the sandbox and a PermissionRequest hook deciding
  the calls that would prompt, running after the fleet's liveness
  PermissionRequest hook. The auto arm: auto mode with today's guards and no
  sandbox.
  *(Cites: D-4.)*
- **REQ-B1.3** The 2026-11-03 recorded calls SHALL be replayed offline
  through today's allowlist and guards before any arm runs live, and through
  the hook arm before the hook or auto arm runs live; auto mode, which is not deterministic, runs live only and
  the replay SHALL refuse it. The recorded calls SHALL be read from the local
  snapshot (REQ-A1.7) and never committed; committed tests and fixtures SHALL
  be synthetic, and replay reports SHALL carry per-category counts, never
  recorded commands.
  *(Cites: D-6; security-posture (Sources).)*
- **REQ-B1.4** The hook arm SHALL decide every call that reaches it without
  asking the tower: allow, or deny with a non-empty reason naming the rule
  that fired and a permitted alternative form, or stating that none exists.
  A call it cannot classify SHALL be denied with such a reason. The hook and
  every script it calls SHALL be deterministic script logic with no model
  call.
  *(Cites: D-4, D-5; fleet-autonomy D-18.)*
- **REQ-B1.5** The sandbox arm SHALL deny reads of secret locations
  (credential stores, key files, token caches) through the sandbox's
  denyRead, not through the allowlist, naming each location by its absolute
  real-home path so a disposable home does not redirect it. The expected
  locations SHALL be pinned in a test fixture independent of the settings
  generator.
  *(Cites: D-4; research: Claude Code sandboxing docs.)*
- **REQ-B1.6** An arm SHALL be recommended for adoption only when: every
  known-bad category was attempted at least once and each attempt was
  blocked (a deny or a sandbox refusal, never a prompt); on every benchmark
  task, the arm's prompts plus denials of calls outside the known-bad set,
  averaged over its three runs, come to at most half the Task 3 baseline's
  average prompts on that task; and benchmark quality does not drop under
  the keep rule (REQ-F1.2). An auto-mode recommendation SHALL be stated as a
  fleet-autonomy D-19 delta, and a hook-arm recommendation as a
  worker-permission-ergonomics D-3 delta (a deny-capable hook) and a
  fleet-autonomy D-19 delta under worker-permission-ergonomics D-6, each for
  the operator to decide and never applied by this bundle.
  *(Cites: D-4, D-11.)*
- **REQ-B1.7** Every benchmark, trial and experiment run SHALL execute in a
  disposable worktree with a disposable home, fleet home and overlay, cloned
  with no push remote, inside its own process namespace, never against the
  real overlay, the real home, or the shared git ledger (the real remote, its
  `refs/planwright-fence/` refs and its PRs). A run SHALL NOT push or open a
  PR, and no GitHub credential SHALL enter its environment. A live run SHALL
  authenticate through a subscription OAuth token passed in its environment,
  SHALL NOT have any credential written into its disposable home, SHALL
  refuse to start without the token, and the kit SHALL scrub the token's
  value from records and reports. Two exceptions are named: the pool slot
  and worker count of REQ-A1.6, and review backtest runs, which keep the
  backtest's own isolation (a read-only reviewer session) with `--remote`
  pointed at a local bare mirror, never the real remote.
  *(Cites: D-6.)*
- **REQ-B1.8** No run SHALL be directed to issue a real known-bad call.
  Every arm's live known-bad check SHALL go through a scripted probe session
  per category that targets only canaries the runner owns: a decoy process
  it spawned, a decoy path inside the disposable home, a runner-made decoy
  path the classifier treats as live configuration, a bounded load. A
  known-bad call a model issues on its own during a run stays inside the
  run's process namespace and disposable home (REQ-B1.7).
  *(Cites: D-6.)*

## REQ-C — Verification-loop cuts

- **REQ-C1.1** An experiment SHALL measure polish rounds and lens fan-out
  scaled to diff size, with a default cap of two polish rounds, against the
  baseline.
  *(Cites: D-9; the 2026-11-03 tower analysis (Sources).)*
- **REQ-C1.2** An experiment SHALL measure removing self-check subagents
  (agents spawned only to re-verify the parent's own work, excluding the
  lens fan-out REQ-C1.1 measures) against the baseline.
  *(Cites: D-9; research: Anthropic Opus 5 prompting guidance.)*
- **REQ-C1.3** An experiment SHALL measure the 2026-11-03 brief quick wins
  (the two-round polish stop and the mktemp-probe rule) against the baseline
  under the keep rule; its verdict SHALL be reported to the operator, who
  owns the briefs.
  *(Cites: D-9, D-10.)*

## REQ-D — Doctrine cuts

- **REQ-D1.1** Review-doctrine cuts SHALL each be measured against the
  review eval set and the benchmark before they are recommended.
  *(Cites: D-7.)*
- **REQ-D1.2** An execution eval covering at least `/execute-task`'s
  invariant refusals (the freshness-gate halt, a non-Ready spec refused, a
  Ready spec accepted) SHALL drive the real skill through the benchmark's
  live runner, and SHALL pass under the baseline's harness identity before
  any execution doctrine cut is measured.
  *(Cites: D-7; obs:3d5b7d08; obs:260e0756.)*
- **REQ-D1.3** Each doctrine cut SHALL be expressed as a candidate diff
  measured in a disposable worktree; this bundle SHALL NOT commit an edit to
  a shipped surface on main (doctrine, skills, `hooks/hooks.json`, the
  installed guard scripts, or shipped settings and config), other than the
  step-record hardening of REQ-E1.4. The harness's own tooling, trial
  profile and fixtures are not shipped surfaces.
  *(Cites: D-1, D-10.)*

## REQ-E — Guards

- **REQ-E1.1** Every guard that fires on a tool call or a PR flip (the
  policy guards, the command guards, the ready-guard, the step-record check)
  SHALL appear in a guard inventory naming its firing source, and SHALL have
  a catch and friction log over the trial window (every baseline, benchmark
  replay, trial and experiment run this bundle executes), excluding firings on
  scripted probes (REQ-B1.8). Firings SHALL be labelled per distinct
  normalized call shape per guard, as a real catch, legitimate work stopped,
  or benign. A firing whose call the known-bad classifier (REQ-B1.1) matches
  SHALL be a real catch; the operator SHALL label every other shape before
  any removal is recommended. A guard that never fired SHALL be listed as
  unexercised.
  *(Cites: D-8.)*
- **REQ-E1.2** The hard limits (no merge, no push to a protected branch, no
  force push) and the step-record check SHALL be kept whatever their
  measured friction.
  *(Cites: D-8.)*
- **REQ-E1.3** A guard SHALL be recommended for removal only when its log
  shows no real catch over the trial window and at least one shape labelled
  legitimate work stopped; an unexercised guard is never a candidate.
  *(Cites: D-8.)*
- **REQ-E1.4** The step-record check (custom-steps' surface) SHALL be
  hardened so a step record whose head, run or outcome does not match the
  branch it claims is refused, with a refused fixture per mismatch kind, a
  fixture reproducing the faked step record seen on 2026-11-03, and a genuine
  fixture that passes. Before merge, a read-only run of the hardened check
  over the fleet's current records SHALL report zero false refusals or list
  each. The hardening SHALL land in this bundle, the one exception to the
  no-guard-edits rule.
  *(Cites: D-1, D-8; the 2026-11-03 tower analysis (Sources).)*

## REQ-F — Results

- **REQ-F1.1** Each experiment SHALL produce a report stating what changed,
  the before and after measurements, the tokens spent, and a keep or revert
  verdict.
  *(Cites: D-1, D-2.)*
- **REQ-F1.2** A cut SHALL be kept only when all of these hold, and token or
  prompt savings SHALL be recorded and SHALL NOT override a failure of any:
  - where the arm's diff touches a file the backtest reviewer loads, or the
    arm changes the reviewer (a stated `--reviewer`), the review backtest
    runs three times for the arm, and no class's catches in any run fall
    below the baseline's worst run for that class; for any other arm the
    clause is recorded as not applicable, since the reviewer cannot see its
    variable;
  - for an execution-doctrine cut, every execution-eval case passes;
  - benchmark quality does not drop. Every benchmark task runs three times
    per arm, baseline included. On the diff-size measure, any run worse than
    the baseline's worst run on that task is a drop. On the tests-pass
    measure, where the baseline passed in at least two of its three runs,
    any failing run is a drop.
  *(Cites: D-2.)*
- **REQ-F1.3** Every adoption SHALL be the operator's decision. An approved
  cut SHALL be routed to its owning bundle as a pending note or amendment
  request, or, where the operator owns the surface (the worker briefs),
  reported to the operator; it SHALL never be applied by this bundle.
  *(Cites: D-10.)*
- **REQ-F1.4** Before any run of a verification-loop or doctrine experiment,
  its task SHALL propose the candidate list (the diff-size curve, the
  self-check spawn sites, the doctrine sections cut) and the operator SHALL
  approve it.
  *(Cites: D-9, D-7.)*

## Changelog

- 2026-11-03 — Drafted (`/spec-draft`) through the tower from the operator's
  answers, the 2026-11-03 tower analysis, Anthropic's 2026-11 guidance and two
  observations; the requirement groups and the task list were approved in the
  drafting session.
- 2026-11-04 — First-activation kickoff (`/spec-kickoff`): walkthrough edits
  and the sign-off lens-pass dispositions, all operator-decided and recorded
  in the kickoff brief (sections 2 to 8). Minted REQ-A1.5 to REQ-A1.7,
  REQ-B1.8, REQ-C1.3 and REQ-F1.4 and Task 14; split Task 11; flipped
  Draft to Ready.

## Sources

- **The invocation seed (2026-11-03)** — "Cut planwright down by measured
  experiments instead of guesswork." Pinned altitude claim: the deliverable
  measures and reports; the operator answered that it never edits doctrine
  directly (D-1).
- **The 2026-11-03 tower analysis** — 505 permission prompts across five
  workers, prompting on 28-56% of tool calls with about 2% denied; prompt
  categories (probes in temp directories, tests and lint, own-branch git,
  inline heredocs, and kills, the only category with real catches); five
  polish rounds gold-plating a small helper; a faked step record; the guards
  that caught real harm.
- **The approval-stats baseline** — the per-worker tools-versus-prompts log
  the tower kept on 2026-11-03, the first measurement REQ-A1.1 generalizes
  from the fleet's own logs.
- **Anthropic's 2026-11 guidance** — research: Claude Code docs on headless
  auto mode, permission modes, the PermissionRequest hook, sandboxing, agent
  view and workflows; the Opus 5 and 5.5 prompting pages (remove
  instructions and add back only what the model misses, subagents multiply
  cost, keep CLAUDE.md short, audit scaffolding built for older models); the
  harness-design post (2026-03-24); the auto-mode engineering post
  (2026-03-25) and its false-negative rate on overeager actions.
- **obs:3d5b7d08** — an eval must precede any instruction trim, or the trim
  is guessed.
- **obs:260e0756** — `/execute-task` has no behavioral eval coverage.
- **fleet-autonomy D-18, D-19** — the no-LLM daemon mechanics principle, and
  D-19's rejection of auto mode with the static allowlist kept as the sole
  permission-approval mechanism for dispatched workers, which an auto-mode or
  hook-arm recommendation would reopen.
- **worker-permission-ergonomics D-3, D-6** — the existing PreToolUse hook is
  allow-only and never emits deny (D-3), which is how D-6 reconciled it with
  fleet-autonomy D-19; a deny-capable hook arm departs from both.
- **security-posture** — the doctrine's artifact data-hygiene section: no
  secrets, credentials, machine paths or private detail in committed
  artifacts.
- **drafting-session decision (2026-11-03)** — the operator's answers on
  goal, altitude, the auto-mode bar, the keep rule, scope, the requirement
  groups (the known-bad categories of REQ-B1.1 among them), the benchmark
  and the task list.
