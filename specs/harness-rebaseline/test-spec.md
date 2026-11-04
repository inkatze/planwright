# Harness rebaseline — Test Spec

**Status:** Ready
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` in planwright's CI for what a script owns (the
measurement kit, the replay runner's refusals and isolation, the known-bad
fixtures, classifier and replay, the hook, the static sandbox-settings
check, the canary probes' target checks, the guard log builder, the execution eval's structural check, the
step-record check), always on synthetic fixtures; `[manual]` for live runs
that spend tokens or need a disposable environment (the benchmark, the
backtest runs, the live trial, the experiment runs, the execution eval's
live cases), each verified by its report and the records under it;
`[design-level]` for the rules carried by the reports and the routing (the
keep rule, operator adoption and candidate approval, the hard limits, no
direct edits on main).

## REQ-A — Baseline

### REQ-A1.1 — One record per run from the fleet's own logs [test]

A synthetic fixture run (event log, allow-audit log, local gate output)
yields a record with every listed field, the run outcome included; removing
one source log makes the kit name the missing source rather than write
zeros.

### REQ-A1.2 — Records name their harness; compare refuses mixed variables [test]

Two fixture records differing only in the permission arm compare; two
differing in arm and model are refused with both variables named; two
differing only in the known-bad set hash are refused; every identity field
(including the claude CLI version, worker-brief variant and candidate diff
hash) is present.

### REQ-A1.3 — Benchmark replays merged tasks from their base commits [test + manual]

`[test]`: the runner refuses a benchmark with fewer than three or more than
five tasks, and grades a fixture replay on the tests-pass and diff-size
measures with the stated directions. `[manual]`: one benchmark task replays
end to end and its graded record is attached to the baseline report.

### REQ-A1.4 — Baseline recorded before any experiment [manual + design-level]

The baseline report exists with three records for every benchmark task and
three backtest runs with per-class catches; its harness identity shows
briefs without the quick wins; every experiment report cites it.

### REQ-A1.5 — Aborted runs re-run, never graded [test]

A rate-limited, a crashed and a timed-out fixture run are each marked
invalid and re-run, and none appears in a graded comparison.

### REQ-A1.6 — Live runs share the host's serialization [test]

The runner sends its gate through `scripts/full-suite-run.sh` on the real
pool, waits to start while the real fleet's live workers plus running trial
runs reach `fleet_concurrency_normal`, and records a fixture run that
exceeds the wall-time limit as timed out.

### REQ-A1.7 — Local snapshot, machine-local records, count-only reports [test + design-level]

`[test]`: the snapshot is written outside the repository with owner-only
permissions, and a report generated from fixture records by the shared
report writer holds no command text, absolute home path or token value.
`[design-level]`: no committed report carries a recorded command, machine
path, token or private-repository detail.

## REQ-B — Permission trial

### REQ-B1.1 — Known-bad set fixed first, one classifier [test]

Each known-bad category has a fixture with its expected decision; the
classifier assigns every fixture its category; changing the set changes its
hash, so records made under the earlier set compare stale.

### REQ-B1.2 — Three arms compared [test + manual]

`[test]`: the scripted vetter allows a fixture call outside the known-bad
set, denies one inside it, and counts each as a prompt. `[manual]`: the
trial report carries comparable records for today's arm, the hook arm and
auto mode, each arm's layers as REQ-B1.2 lists them.

### REQ-B1.3 — Offline replay before live [test]

On synthetic fixture calls, the replay feeds calls through today's
allowlist and guards and through the hook and reports per-category
decisions; it refuses an auto-mode arm; its report output carries counts and
no command text.

### REQ-B1.4 — The hook decides without the tower, denying the unknown [test]

Known-bad fixtures are denied with a reason naming the rule and an
alternative or stating that none exists; an unclassifiable call is denied
the same way; no fixture path produces an ask; a static check over the hook
and every script it calls finds no model invocation, and the fixtures pass
with a failing `claude` stub on PATH.

### REQ-B1.5 — Secrets behind denyRead [test + manual]

`[test]`: a static check of the generated trial settings finds every
location in the pinned secret-location fixture under the sandbox's denyRead
by absolute real-home path and none covered by the allowlist. `[manual]`:
under the trial profile in a disposable environment, a read of a fixture
secret location fails through the sandbox, recorded in the Task 5 report (a
live session needs a model, which CI never runs).

### REQ-B1.6 — Adoption bar and the deltas [manual + design-level]

The trial report states, per arm: each known-bad category attempted and
blocked (a deny or sandbox refusal, never a prompt); prompts plus denials of
calls outside the known-bad set per benchmark task, averaged over three
runs, against the baseline's average prompts; and the keep-rule comparison.
An auto-mode recommendation is worded as a fleet-autonomy D-19 delta and a
hook-arm recommendation as worker-permission-ergonomics D-3 and
fleet-autonomy D-19 deltas, for the operator.

### REQ-B1.7 — Disposable, unpublished, credential-safe runs [test]

The runner refuses to start when the home, fleet home, overlay or remote
resolves to the real one, and when no token is in the environment; after a
fixture run, the disposable home holds no credential file, the clone has no
push remote, no GitHub credential was in the run's environment, and the
run's processes sat in their own namespace; the kit's record of a fixture
carrying the token value omits it; a backtest invocation from the harness
passes a local bare mirror as `--remote`, never the real remote.

### REQ-B1.8 — Live known-bad checks hit only canaries [test + manual]

`[test]`: each category's probe script targets only a decoy the runner
created (a spawned process, a path in the disposable home, a decoy path the
classifier treats as live configuration, a bounded load), and refuses a
target it did not create. `[manual]`: the trial report shows each category
probed under each arm.

## REQ-C — Verification-loop cuts

### REQ-C1.1 — Diff-size scaling measured [manual]

The verification-loop report carries baseline-comparable records for the
scaled candidate and a verdict.

### REQ-C1.2 — Self-check removal measured [manual]

The same report carries records and a verdict for the self-check removal
candidate, whose spawn sites exclude the lens fan-out.

### REQ-C1.3 — The 2026-11-03 quick wins measured [manual]

The baseline report's harness identity shows briefs without the quick wins;
the verification-loop report carries baseline-comparable records and a keep
or revert verdict for the quick-win arm, flagged for the operator.

## REQ-D — Doctrine cuts

### REQ-D1.1 — Review cuts measured against the eval set [manual]

The review-doctrine report gives each candidate's per-class backtest catches
and benchmark records beside the baseline's.

### REQ-D1.2 — Execution eval precedes execution cuts [test + manual]

`[test]`: a CI structural check finds every execution-eval case definition
present and well formed. `[manual]`: each case, driven through the real
skill, passes under today's harness and fails with its refusal removed,
recorded before the execution-doctrine report; Task 10 re-confirms the pass
under the baseline's harness identity before its first candidate run.

### REQ-D1.3 — No protected edits on main [design-level]

The bundle's merged PRs edit no shipped surface (doctrine, skills,
`hooks/hooks.json`, the installed guard scripts, shipped settings and
config), except Task 12's step-record check; the harness's own tooling,
trial profile and fixtures are not shipped surfaces; candidate diffs live in
the reports.

## REQ-E — Guards

### REQ-E1.1 — Inventory, catch and friction log [test + manual]

`[test]`: a synthetic firing lands in the log under its call shape; a shape
the known-bad classifier matches is labelled a real catch; a probe firing is
excluded; any other shape is left unlabelled for the operator; a guard with
no firings appears as unexercised. `[manual]`: the guard report has a row for
every inventoried guard, with every shape labelled.

### REQ-E1.2 — Hard limits and the step-record check kept [design-level]

The guard report lists merge, protected-branch push, force push and the
step-record check as kept, with no removal candidate among them.

### REQ-E1.3 — Removal only on evidence [manual]

Every removal candidate in the guard report shows zero real catches and at
least one shape labelled legitimate work stopped; no unexercised guard is a
candidate.

### REQ-E1.4 — Step-record check refuses a faked record [test + manual]

`[test]`: a fixture per mismatch kind (head, run, outcome) and the
2026-11-03 faked-record reproduction are refused; the genuine fixture
passes. `[manual]`: the PR records the read-only run over the fleet's
current records, with zero false refusals or each one listed.

## REQ-F — Results

### REQ-F1.1 — A report per experiment [manual]

Every experiment task has a report with before and after records, the
tokens spent, and a verdict.

### REQ-F1.2 — The keep rule [design-level + manual]

No report keeps a cut whose backtest catches fall, in any of its three runs,
below the baseline's worst run for any class (where the reviewer can see the
arm's variable; otherwise the report records the clause as not applicable
with its reason); whose execution-eval case
fails (execution cuts); or whose benchmark quality drops: a diff-size run
worse than the baseline's worst on that task, or a failing tests-pass run
where the baseline passed in at least two of three. Savings never override.

### REQ-F1.3 — Operator adoption, routed to owners [design-level]

The results summary records an operator decision for every keep verdict and
recommendation; every approval has a pending note or amendment request
naming its owning bundle, or an operator report for the worker briefs; no
cut was applied by this bundle.

### REQ-F1.4 — Candidates approved before runs [design-level]

Tasks 7, 8 and 10 each record the operator's approval of their candidate
list before their first run.
