# Harness rebaseline — Test Spec

**Status:** Draft
**Last reviewed:** 2026-11-03
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` in planwright's CI for what a script owns (the
measurement kit, the replay and its known-bad fixtures, the hook, the
step-record check); `[manual]` for live runs that spend tokens or need a
disposable environment (the benchmark, the live trial, the experiment runs),
each verified by its report and the records it rests on; `[design-level]`
for the rules carried by the reports and the routing (the keep rule,
operator adoption, no direct doctrine edits).

## REQ-A — Baseline

### REQ-A1.1 — One record per run from the fleet's own logs [test]

A recorded fixture run (event log, approval statistics, PR and CI data)
yields a record with every listed field; removing one source log makes the
kit name the missing source rather than write zeros.

### REQ-A1.2 — Records name their harness; compare refuses mixed variables [test]

Two fixture records differing only in the permission arm compare; two
differing in arm and model are refused with both variables named.

### REQ-A1.3 — Benchmark replays merged tasks from their base commits [test + manual]

`[test]`: the runner refuses a non-disposable home or overlay and refuses a
benchmark with fewer than three or more than five tasks. `[manual]`: one
benchmark task replays end to end and its graded record is attached to the
baseline report.

### REQ-A1.4 — Baseline recorded before any experiment [manual + design-level]

The baseline report exists with records for every benchmark task and the
review eval catch count, and every experiment report cites it.

## REQ-B — Permission trial

### REQ-B1.1 — Known-bad set fixed first [test]

Each known-bad category has a fixture with its expected decision; changing
the set marks earlier replays stale.

### REQ-B1.2 — Three arms compared [manual]

The trial report carries comparable records for today's arm, the hook arm
and auto mode.

### REQ-B1.3 — Offline replay before live [test]

The replay feeds recorded calls through today's guards and the hook and
reports per-category decisions; it refuses an auto-mode arm.

### REQ-B1.4 — The hook decides without the tower, denying the unknown [test]

Known-bad fixtures are denied with a reason; an unclassifiable call is denied
with a reason; no fixture path produces an ask; a static check finds no model
invocation in the hook.

### REQ-B1.5 — Secrets behind denyRead [test]

Under the trial profile in a disposable environment, a read of a fixture
secret location fails through the sandbox while the allowlist is unchanged.

### REQ-B1.6 — Adoption bar and the D-19 delta [manual + design-level]

The trial report states, per arm, known-bad blocked (all or not) and prompts
per task against the baseline; an auto-mode recommendation is worded as a
fleet-autonomy D-19 delta for the operator.

### REQ-B1.7 — Disposable environments only [test]

The trial and benchmark runners refuse to start when the home, overlay or
git ledger path resolves to the real one.

## REQ-C — Verification-loop cuts

### REQ-C1.1 — Diff-size scaling measured [manual]

The verification-loop report carries baseline-comparable records for the
scaled candidate and a verdict.

### REQ-C1.2 — Self-check removal measured [manual]

The same report carries records and a verdict for the self-check removal
candidate.

## REQ-D — Doctrine cuts

### REQ-D1.1 — Review cuts measured against the eval set [manual]

The review-doctrine report gives each candidate's eval catch count and
benchmark records beside the baseline's.

### REQ-D1.2 — Execution eval precedes execution cuts [test + manual]

`[test]`: the execution eval's cases exist under the behavioral-eval harness
(run on demand, never in CI). `[manual]`: each case passes on the baseline
and fails with its refusal removed, recorded before the execution-doctrine
report.

### REQ-D1.3 — No doctrine commits to main [design-level]

The bundle's merged PRs touch no doctrine or skill file outside the
harness's own fixtures; candidate diffs live in the reports.

## REQ-E — Guards

### REQ-E1.1 — Catch and friction log [test + manual]

`[test]`: a fixture guard firing lands in the log with its outcome.
`[manual]`: the guard report covers every guard that fired in the window.

### REQ-E1.2 — Hard limits kept [design-level]

The guard report lists merge, protected-branch push and force push as kept,
with no removal candidate among them.

### REQ-E1.3 — Removal only on evidence [manual]

Every removal candidate in the guard report shows zero real catches and
recorded friction.

### REQ-E1.4 — Step-record check refuses a faked record [test]

The 2026-11-03 faked-record fixture is refused; genuine fixture records
pass.

## REQ-F — Results

### REQ-F1.1 — A report per experiment [manual]

Every experiment task has a report with before and after records and a
verdict.

### REQ-F1.2 — The keep rule [design-level + manual]

No report keeps a cut whose eval catches fall below the baseline or whose
benchmark quality drops, whatever its savings.

### REQ-F1.3 — Operator adoption, routed to owners [design-level]

Every approved cut has a pending note or amendment request naming its owning
bundle; no cut was applied by this bundle.
