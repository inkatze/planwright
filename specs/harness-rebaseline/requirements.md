# Harness rebaseline — Requirements

**Status:** Draft
**Last reviewed:** 2026-11-03
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
it never edits doctrine, skills or guards itself; an adopted cut lands
through the bundle that owns the surface (D-1, D-10).

## Scope

### In scope

- A measurement kit that reads what the fleet already records (approval
  statistics, worker event logs, PR and CI data) into one record per run.
- A benchmark of recent merged tasks replayed from fresh worktrees at their
  base commits, graded against what actually merged.
- A baseline run of today's harness on the benchmark and the review eval set.
- A permission trial with three arms: today's allowlist and tower vetting; a
  sandbox plus a deterministic PermissionRequest hook; Claude Code's auto
  mode. Recorded calls replay offline first, then the arms run live.
- Verification-loop cuts: polish rounds and lens fan-out scaled to diff
  size, and self-check subagents removed where the measurements allow.
- Doctrine cuts: review doctrine measured against the review eval set; an
  execution eval built first, then execution doctrine cuts.
- Guards: a catch and friction log for every guard, the hard limits kept,
  friction guards removable on evidence, and the evidence-integrity checks
  hardened.
- A results report per experiment and an operator decision per adoption.

### Out of scope

- The cloud backend.
- The company thin version (guards as hooks, spec templates, a measured
  review gate); it waits for this bundle's results.
- The review desk.
- tower-control-plane, on hold until the permission trial reports.
- Editing doctrine, skills, guards or settings on main directly: every
  adopted cut is routed to its owning bundle (D-10).
- Removing a hard limit (merge, push to a protected branch, force push),
  whatever its measured friction (D-8).

## REQ-A — Baseline

- **REQ-A1.1** A measurement kit SHALL turn each worker run into one
  machine-readable record holding at least: tool calls, permission prompts,
  denials, tokens, wall time, polish rounds, lens agents spawned, and the
  resulting PR's CI outcome, read from what the fleet already writes, never
  from a worker's own account of itself.
  *(Cites: D-2; the approval-stats baseline (Sources).)*
- **REQ-A1.2** Every record SHALL name the harness under test (planwright
  commit, plugin version, model, permission arm, and the knobs a cut changes)
  so two records are compared only when they differ in the one variable an
  experiment changes.
  *(Cites: D-2.)*
- **REQ-A1.3** A benchmark SHALL replay a fixed set of recent merged tasks,
  at least three and at most five, each from a fresh worktree at its
  original base commit, grading each replay against the merged PR: its tests
  pass, the review eval set's findings on it, and its diff size relative to
  the merged one.
  *(Cites: D-3.)*
- **REQ-A1.4** A baseline run of today's harness on the benchmark and on the
  review eval set SHALL be recorded before any experiment runs, and every
  experiment's verdict SHALL be judged against it.
  *(Cites: D-2, D-3.)*

## REQ-B — Permission trial

- **REQ-B1.1** The known-bad call set SHALL be fixed before any arm runs and
  SHALL hold at least: a kill of an exited or reused PID, a pattern kill, a
  write outside the worker's worktree, a write to live configuration or the
  real home, a load generator, and a read of another process's environment.
  Adding to it after an arm has run SHALL re-run every arm.
  *(Cites: D-4; the 2026-11-03 tower analysis (Sources).)*
- **REQ-B1.2** The trial SHALL compare three arms: today's allowlist with
  tower vetting; a sandbox plus a PermissionRequest hook carrying the
  deterministic guards; and auto mode.
  *(Cites: D-4.)*
- **REQ-B1.3** The recorded calls from the 2026-11-03 baseline SHALL be
  replayed offline through each arm that decides deterministically before
  any arm runs live; auto mode, which is not deterministic, runs live only.
  *(Cites: D-6.)*
- **REQ-B1.4** The hook arm SHALL decide every call without asking the
  tower: allow, or deny with a reason the worker can act on. A call it
  cannot classify SHALL be denied with a reason. The hook SHALL be
  deterministic script logic with no model call.
  *(Cites: D-5; fleet-autonomy D-18.)*
- **REQ-B1.5** The sandbox arm SHALL deny reads of secret locations
  (credential stores, key files, token caches) through the sandbox's
  denyRead, not through the allowlist.
  *(Cites: D-4; research: Claude Code sandboxing docs.)*
- **REQ-B1.6** An arm SHALL be recommended for adoption only when it blocks
  every call in the known-bad set and at least halves the prompts per task
  against the baseline. Recommending auto mode SHALL be stated as a
  fleet-autonomy D-19 delta for the operator to decide, never applied by this
  bundle.
  *(Cites: D-4, D-11.)*
- **REQ-B1.7** Every trial run SHALL execute in a disposable worktree with a
  disposable home and overlay, never against the real overlay, the real
  home, or the shared git ledger.
  *(Cites: D-6.)*

## REQ-C — Verification-loop cuts

- **REQ-C1.1** An experiment SHALL measure polish rounds and lens fan-out
  scaled to diff size, with a default cap of two polish rounds, against the
  baseline.
  *(Cites: D-9; the 2026-11-03 tower analysis (Sources).)*
- **REQ-C1.2** An experiment SHALL measure removing self-check subagents
  (agents spawned only to re-verify the parent's own work) against the
  baseline.
  *(Cites: D-9; research: Anthropic Opus 5 prompting guidance.)*

## REQ-D — Doctrine cuts

- **REQ-D1.1** Review-doctrine cuts SHALL each be measured against the
  review eval set and the benchmark before they are recommended.
  *(Cites: D-7.)*
- **REQ-D1.2** An execution eval covering `/execute-task`'s invariant
  refusals (the freshness-gate halt, a non-Ready spec refused, a Ready spec
  accepted) SHALL exist and pass on the baseline before any execution
  doctrine cut is measured.
  *(Cites: D-7; obs:3d5b7d08; obs:260e0756.)*
- **REQ-D1.3** Each doctrine cut SHALL be expressed as a candidate diff
  measured in a disposable worktree; this bundle SHALL NOT commit a doctrine
  or skill edit to main.
  *(Cites: D-1, D-10.)*

## REQ-E — Guards

- **REQ-E1.1** Every guard (policy guards, command guards, the ready-guard,
  the check scripts) SHALL have a catch and friction log over the trial
  window: how often it fired, how many firings stopped real harm, and how
  many stopped legitimate work.
  *(Cites: D-8.)*
- **REQ-E1.2** The hard limits (no merge, no push to a protected branch, no
  force push) SHALL be kept whatever their measured friction.
  *(Cites: D-8.)*
- **REQ-E1.3** A friction guard SHALL be recommended for removal only when
  its log shows no real catch over the trial window and measurable friction.
  *(Cites: D-8.)*
- **REQ-E1.4** The evidence-integrity checks SHALL be hardened so a step
  record whose head, run or outcome does not match the branch it claims is
  refused, with a fixture reproducing the faked step record seen on
  2026-11-03.
  *(Cites: D-8; the 2026-11-03 tower analysis (Sources).)*

## REQ-F — Results

- **REQ-F1.1** Each experiment SHALL produce a report stating what changed,
  the before and after measurements, and a keep or revert verdict.
  *(Cites: D-2.)*
- **REQ-F1.2** A cut SHALL be kept only when the review eval set's catches
  stay at the baseline or better (five of nine at drafting) and benchmark
  quality does not drop; token or prompt savings SHALL be recorded and SHALL
  NOT override a drop.
  *(Cites: D-2.)*
- **REQ-F1.3** Every adoption SHALL be the operator's decision, and an
  approved cut SHALL be routed to its owning bundle as a pending note or
  amendment request, never applied by this bundle.
  *(Cites: D-10.)*

## Changelog

- 2026-11-03 — Drafted (`/spec-draft`) through the tower from the operator's
  answers, the 2026-11-03 tower analysis, Anthropic's 2026-11 guidance and two
  observations; the requirement groups and the task list were approved in the
  drafting session.

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
  the tower kept on 2026-11-03, the first measurement REQ-A1.1 generalizes.
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
- **fleet-autonomy D-18, D-19** — the no-LLM daemon mechanics invariant and
  the rejection of auto mode for fleet dispatch, which an auto-mode
  recommendation would reopen.
- **drafting-session decision (2026-11-03)** — the operator's answers on
  goal, altitude, the auto-mode bar, the keep rule, scope, the requirement
  groups, the benchmark and the task list.
