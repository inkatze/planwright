# Harness Rebaseline — Kickoff Brief

## 1. Header

- **Spec path:** `specs/harness-rebaseline`
- **Spec commit at walkthrough start:** `68debea6`
- **Walkthrough date:** 2026-11-03
- **Mode:** First activation (Status Draft, no prior brief)
- **Validator outcome (pre-flight):** clean, 0 errors and 0 warnings
  (`scripts/spec-validate.sh`)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no local override)
- **Working location:** spec worktree on branch
  `planwright/harness-rebaseline/spec`, clean tree; `origin` remote configured.
- **Doctrine resolution:** every rule doc the skill names resolved through the
  overlay chain.
- **Decision/transcript log:** no harness-provided log path in this session;
  the turn mirror is skipped (not improvised into the repository).
- **Operator channel:** the operator answers through the tower; every question
  went through a relayed selector.

## 2. Goal & glossary

**Goal (restated).** planwright's permission layer, verification loops,
doctrine and guards grew one failure at a time and nobody has measured which
parts still pay. This bundle builds the instruments (a per-run measurement
kit, a replay benchmark of real merged tasks, an offline permission replay,
an execution eval, a guard catch log), records a baseline of today's harness,
runs one experiment per candidate cut, and reports keep or revert for each.
Its outputs are the harness and the reports.

**Rules out:** editing doctrine, skills, guards or settings on main (every
adopted cut routes to its owning bundle; the one exception, decided in
section 3, is the step-record hardening, which only tightens); removing a hard limit (merge,
protected-branch push, force push); changing any fleet dispatch setting,
including auto mode (a win is reported as a fleet-autonomy D-19 delta); the
cloud backend, the company thin version, the review desk and
tower-control-plane.

**Assumes:** the fleet's shipped logs (worker event logs, allow-audit logs,
the local gate output) are rich enough to fill a run record without asking
the worker; merged tasks can be replayed from their base commits with their
original briefs; every run can be isolated in a disposable worktree, home,
fleet home and overlay with no push remote. (Revised at the sign-off lens
pass, section 8: approval statistics and PR CI data were dropped as
sources.)

**Glossary and resolutions.** Entries marked *revised* were changed by the
sign-off lens dispositions recorded in section 8.

- **Review eval set** — the review backtest (`scripts/review-backtest.sh`
  over its corpus). Operator-confirmed. The copied "five of nine at
  drafting" figure was dropped (cite-don't-copy). *Revised:* it is compared
  per class, three runs per arm, and it does not grade benchmark replays.
- **Benchmark quality drop** — every benchmark task runs three times per arm,
  baseline included. Operator-decided. *Revised:* the graded measures are the
  merged PR's added tests passing on the replay and the diff-size distance
  from the merged diff (larger is worse); on diff size a drop is any run
  worse than the baseline's worst run on that task; on tests-pass a drop is
  any failing run where the baseline passed in at least two of three;
  aborted runs are re-run, never graded.
- **Real catch vs legitimate work stopped** — a firing on a known-bad-category
  call is a real catch by rule; the operator labels every other firing before
  any removal is recommended. Operator-decided. *Revised:* labels apply per
  distinct call shape per guard, with a third label (benign); probe firings
  are excluded; one classifier decides category membership.
- **Trial window** — every baseline, replay, trial and experiment run this
  bundle executes. Resolved from the task list; written into REQ-E1.1.
- **Self-check subagent** — an agent spawned only to re-verify the parent's
  own work (defined in REQ-C1.2; no edit).
- **Disposable environment** — a worktree, home and overlay created for the
  run and never the real ones (REQ-B1.7). *Revised:* also a disposable fleet
  home, and a clone with no push remote.
- **Arm** — *revised:* one harness configuration under test: the baseline, a
  permission configuration (today's arm, the hook arm, auto mode), or an
  experiment candidate. "Permission arm" keeps the narrow sense.
- **Baseline** — *revised:* always the Task 3 run. The 2026-11-03 fleet data
  is "the 2026-11-03 recorded calls".

Signed off: 2026-11-04

## 3. Requirements walkthrough

**Per-group outcomes.**

- **REQ-A (Baseline):** confirmed. The kit reads only what the fleet writes,
  every record names its harness, the benchmark is three to five merged tasks
  replayed at their base commits, and the baseline precedes every experiment.
  The review eval set is pinned to the review backtest (section 2).
- **REQ-B (Permission trial):** amended twice.
  1. *Adoption bar.* The hook arm never prompts, so a prompts-only halving
     bar would pass it by construction. Decided: prompts plus denials of calls
     outside the known-bad set come to at most half the baseline's prompts
     per task, and benchmark quality does not drop under the keep rule.
  2. *Replay corpus hygiene.* The recorded calls are real commands with
     machine paths and private detail. Decided: read from the fleet's local
     logs at replay time and never committed; CI runs synthetic fixtures;
     reports carry per-category counts only.
- **REQ-C (Verification-loop cuts):** confirmed, no edits.
- **REQ-D (Doctrine cuts):** confirmed, no edits.
- **REQ-E (Guards):** inconsistency halt, resolved by spec edit. D-1 and the
  out-of-scope list forbade guard edits on main, while REQ-E1.4 required the
  step-record check hardened with a CI test (and Task 12 routed it to its
  owner). Operator chose: the hardening lands in this bundle as a named D-1
  exception, because it only tightens a check that was beaten. Task 12 no
  longer routes it. The labelling rule for catches (section 2) also landed
  here.
- **REQ-F (Results):** the keep rule gained the three-run, worst-baseline-run
  drop rule (section 2); otherwise confirmed.

*Revised at the sign-off lens pass (section 8):* several outcomes above were
superseded. The replay corpus is now read from a local snapshot (REQ-A1.7),
not the live logs; the keep rule compares the backtest per class, only for
arms the reviewer can see, and the tests-pass measure gates on the
baseline's majority; firings are labelled per call shape with a third label;
REQ-F gained the execution-eval clause and REQ-F1.4 (candidate approval);
REQ-A gained REQ-A1.5 to REQ-A1.7 and REQ-B gained REQ-B1.8. Section 8
carries the full disposition record.

**Consolidated spec-edit list** (all applied in place; the bundle is Draft):

1. REQ-A1.4: names the review eval set as the review backtest.
2. REQ-F1.2, D-2, Task 3 Done when, REQ-F1.2 test entry: three runs per task
   per arm; drop means worse than the baseline's worst run; the copied "five
   of nine" figure replaced by the baseline's recorded catch count.
3. REQ-E1.1, D-8, REQ-E1.1 test entry: known-bad matches are real catches by
   rule; the operator labels every other firing; the trial window defined.
4. REQ-B1.6, D-4, Task 6 Done when, REQ-B1.6 test entry: denials count
   against the adoption bar, plus the keep-rule quality check.
5. REQ-B1.3, D-6, REQ-B1.3 test entry: replay corpus local-only, synthetic
   CI fixtures, count-only reports; the copied "505" figure dropped from D-6.
6. Goal, out-of-scope list, D-1 (decision and a new rejected alternative),
   D-10, REQ-E1.4, Task 12: the step-record hardening lands here as the one
   exception to the no-guard-edits rule.

**Mid-walk delta lens** (inline, declared: the deltas are narrow and every
one applies an operator decision). Scope: edits 1 to 6 and what cites them.
Checked for cross-file consistency (each REQ edit paired with its D-ID, task
and test-spec entry), testability of every new SHALL, and contradiction with
unedited text.

- Finding: D-10 still said this bundle's only outputs were the harness and
  the reports, contradicting the D-1 exception. Applied: D-10 names the
  step-record hardening as an output.
- Finding: Task 11 labels firings by the known-bad set but does not depend on
  Task 4, which fixes that set, and its report needs the trial runs it does
  not depend on. Carried to section 6 (task graph).
- No finding: REQ-B1.3's "fixtures SHALL be synthetic" and REQ-E1.4's
  reproduced faked record do not conflict; the reproduction is a
  hand-written fixture, not a recorded command.

Signed off: 2026-11-04

## 4. Design walkthrough

**Reconciled ledger** (every D-ID in `design.md`; none superseded):

- **D-1** Altitude, a measurement harness plus reports: *amended* in section
  3, one named exception (the step-record hardening lands here, since it only
  tightens), with the routed alternative recorded as rejected.
- **D-2** The keep rule: *amended* in section 2 (three runs per task per arm,
  worst-baseline-run drop rule).
- **D-3** Benchmark replays recent merged tasks: *confirmed*. Both named
  candidates are merged (test-throughput Task 12 as #803, mission-control
  Task 13 as #804); the final set is Task 2's to fix.
- **D-4** Three permission arms, hook the main one: *amended* in section 3
  (denials count against the adoption bar).
- **D-5** The hook denies the unknown with a reason: *confirmed*.
- **D-6** Offline replay first, disposable live runs: *amended* in section 3
  (recorded calls local-only, synthetic CI fixtures, counts-only reports;
  copied "505" figure dropped).
- **D-7** An eval precedes every doctrine cut: *confirmed*.
- **D-8** Guards, hard limits fixed: *amended* in section 2 (known-bad
  matches are catches by rule, the operator labels the rest).
- **D-9** Verification loops scale to diff size: *amended* here. The
  two-round polish stop and the mktemp-probe rule went into worker briefs on
  2026-11-03 unmeasured, so a baseline of "today's harness" would compare the
  cap against itself. Operator chose: the baseline runs without those two
  brief lines and they become the first experiment. Minted **REQ-C1.3**
  (with its test entry); edited the scope list, REQ-A1.4, Task 3 and Task 7.
- **D-10** Findings land through owning bundles: *amended* in section 3
  (names the step-record hardening as an output).
- **D-11** Auto mode is a trial arm, not an adoption: *confirmed*.

Section 2's restatement ("a baseline of today's harness") now reads "today's
harness minus the 2026-11-03 brief quick wins".

*Revised at the sign-off lens pass (section 8):* the F1 to F16 and recheck
dispositions amended the D-IDs again. D-1 (the shipped-surface definition),
D-2 (per-class
backtest, execution-eval clause, majority rule for tests-pass, aborted runs,
pinning, shipped sources), D-3 (graded measures, harness under test, brief
lines by arm), D-4 (arm composition, scripted vetter, classifier, category
provenance, worker-permission-ergonomics deltas), D-5 (reason content), D-6
(storage, isolation, no push, token kind, suite pool and worker count,
backtest isolation, process namespace, canaries), D-7 (eval harness,
single-case entry, candidate approval), D-8 (labelling unit, probes excluded, inventory, step-record check
kept), D-9 (candidate approval), D-10 (custom-steps, operator-owned briefs),
D-11 (namespace-qualified citation only).

**Mid-walk delta lens** (inline, declared; narrow delta applying an operator
decision): REQ-C1.3 is paired with its test entry and cited by Task 7;
REQ-A1.4 cites D-9, which now carries the reason. No contradiction found with
the permission bar: the baseline's prompts come from briefs without the
mktemp rule, so the rule's own prompt savings show up in the quick-win arm.
REQ-C1.3 is newly minted, so the stale-reference sweep runs at sign-off.

Signed off: 2026-11-04

## 5. Verification approach

**Coverage mix** (tags per `test-spec.md`; tallies are the validator's, not
copied here): `[test]` for what a script owns (the kit, the benchmark
runner's refusals, the known-bad fixtures and replay, the hook, the static
sandbox-settings check, the guard log's labelling, the step-record check);
`[manual]` for live runs that spend tokens or need a disposable environment,
each verified by its report and the records under it; `[design-level]` for
the keep rule, operator adoption, the hard limits and the no-doctrine-on-main
rule.

**Ownership.** `[test]` entries run in planwright's CI through the project
gate. `[manual]` entries are swept by the task that produces each report and
checked by the operator when Task 13 collects the results; every live run
records its harness identity, so a reader can tell which runs a verdict
rests on. `[design-level]` entries are checked at each PR's review and again
in Task 13 (every approved cut routed, none applied here).

**Dead paths found and fixed.**

- REQ-B1.5's CI test needed a live sandboxed session, and CI runs no model.
  Operator chose a split: a static CI check of the generated trial settings
  (every secret location under denyRead, none in the allowlist) plus the live
  failed read as a manual check recorded in the Task 5 report. Edited the
  REQ-B1.5 test entry (now `[test + manual]`) and Task 5 Done when.
- REQ-D1.2's `[test]` half checks only that the eval cases exist; the cases
  themselves run on demand, never in CI (the standing no-evals-in-CI rule).
  Not a dead path: the pass/fail half is the `[manual]` entry. No edit.
  *Revised at the sign-off lens pass (section 8):* the `[test]` half is now a
  CI structural check of every case definition, and the live cases run
  through the benchmark's runner, because the behavioral-eval fixtures are
  stand-ins and the prompt-eval suite is inoperative.

*Revised at the sign-off lens pass:* the coverage preamble in `test-spec.md`
was rewritten to match; every `[test]` entry runs on synthetic fixtures.

Signed off: 2026-11-04

## 6. Task graph

**Graph** (reconstructed from the `Dependencies:` lines in `tasks.md`, which
stay authoritative; this rendering is derived):

*Revised at the sign-off lens pass (section 8):* Task 3 now also depends on
Task 4 (the known-bad set and the scripted vetter must exist before the
baseline runs), Task 9 depends on Task 2 (the execution eval drives the real
skill through the replay runner), and Tasks 2, 4 and 9 grew in effort. The
graph below is the revised one, written as each task's prerequisites.

```text
Task 1   <- (none)
Task 12  <- (none)
Task 2   <- Task 1
Task 4   <- Task 1
Task 3   <- Task 2, Task 4
Task 9   <- Task 2
Task 11  <- Task 1, Task 4
Task 5   <- Task 3, Task 4
Task 7   <- Task 3
Task 8   <- Task 3
Task 10  <- Task 9, Task 3
Task 6   <- Task 5
Task 14  <- Task 6, Task 7, Task 8, Task 10, Task 11
Task 13  <- Task 6, Task 7, Task 8, Task 10, Task 12, Task 14
```

**Edits made in this section.**

- Task 11 split (operator decision). As drafted it labelled firings without
  the known-bad set (Task 4) and reported on runs it did not wait for. Task
  11 now builds the log reader (depends on Tasks 1 and 4, CI-tested on
  fixtures); a new **Task 14** builds the log over the whole trial window
  and writes the guard report (depends on Tasks 6, 7, 8, 10 and 11); Task 13
  depends on Task 14 instead of Task 11. The log reads firings back from
  what runs already record, so nothing run before Task 11 lands is lost.
- Task 12 dropped its edge on Task 1 (operator decision): it shares no input
  with the kit, and the faked-record gap is live.

**Parallelism** (revised). Tasks 1 and 12 start at once. After Task 1, Tasks
2 and 4 run in parallel, then Task 11, and Task 9 once Task 2 lands. After
the baseline (Task 3), Tasks 5, 7, 8 and 10 (once Task 9 is in) run in
parallel. Task 14 then Task 13 close.

**Critical path** (effort-weighted, from the `Estimated effort:` fields):
Task 1 → Task 2 → Task 3 → Task 5 → Task 6 → Task 14 → Task 13, the
permission trial chain.

**Deliberate non-edges** (do not "fix" these):

- Task 4 does not wait for the baseline (Task 3): the offline replay reads
  recorded calls and today's guards, not benchmark runs.
- Tasks 7, 8 and 10 do not wait for the permission trial (Task 6): each
  experiment changes one variable and runs under today's permission arm, so
  they share only the baseline.
- Task 10 does not wait for Task 8: review and execution doctrine cuts are
  separate experiments against separate evals.
- Task 12 has no dependencies: the step-record hardening uses nothing the
  kit builds. (Task 9 had none as drafted; it now depends on Task 2.)
- Task 9 does not wait for the baseline (Task 3): it passes under today's
  harness first, and Task 10 re-confirms the pass under the baseline's
  identity before its first candidate run.

Signed off: 2026-11-04

## 7. Risk register

**Decision-domains gap check** (catalog resolved through
`scripts/resolve-catalog.sh decision-domains`). Domains the spec touches:
secrets and auth, data storage, concurrency, dependency adoption, LLM output
quality, existing-seam reuse, observability, human comprehension, org design.
Decided in the spec or this walk: secrets (denyRead; credentials, below), LLM
output quality (the keep rule and three-run drop rule are the gate, set by
the operator), observability (the kit), org design (D-10 names the owners),
human comprehension (reports by convention). The rest are rows below.

1. **Live-run credentials** (auth, secrets; escalated domain). A disposable
   home has no login. *Decided in this walk* (operator): a live run
   authenticates through a token in its environment, no credential is ever
   written into the disposable home, and the runner refuses to start without
   the token. Written into REQ-B1.7, D-6, the REQ-B1.7 test entry and Task 2.
   *Early signal:* a credential file appearing under a disposable home.
2. **Where records and reports live** (data storage). *Revised at the
   sign-off lens pass, now decided* (REQ-A1.7, D-6): the 2026-11-03 recorded
   calls are kept as a local, uncommitted, owner-only snapshot for the
   bundle's life; run records live in the machine-local state home; only
   reports carrying counts and harness identities are committed. *Early
   signal:* a committed report carrying an absolute home path.
3. **Trial runs compete with the live fleet** (concurrency). *Revised:* the
   original premise (runs share the host gate lock) was wrong under a
   disposable home. Now decided (REQ-A1.6, D-6): live runs take the gate lock
   at its real path, count toward the fleet's worker cap, and abort at a
   wall-time limit; rate-limited, crashed and timed-out runs are invalid and
   re-run (REQ-A1.5). *Early signal:* a run record with near-zero tool calls
   that is not marked invalid.
4. **Sandbox runtime dependency** (dependency adoption). Claude Code's Linux
   sandbox needs bubblewrap and socat; on this host bubblewrap is present and
   socat was not found at kickoff. *Mitigation, now a Task 5 deliverable:* a
   pre-run dependency check that parks for the operator rather than
   installing. *Early signal:* the sandbox refusing to start in the Task 5
   profile.
5. **A new hook beside the existing ones** (existing-seam reuse). The fleet
   already runs an allow-only PreToolUse hook (worker-permission-ergonomics
   D-3) and a liveness PermissionRequest hook (`hooks/hooks.json`).
   *Mitigation, now in Task 5 and D-4:* the trial hook calls the existing
   guard scripts and the Task 4 classifier, runs after the liveness hook, and
   its report says why a PermissionRequest hook is needed; adopting it is
   stated as worker-permission-ergonomics D-3 and fleet-autonomy D-19
   deltas. *Early signal:* the trial hook duplicating a guard's patterns
   instead of calling it, or park markers missing in hook-arm runs.
6. **Run noise beyond three runs.** Three runs per arm may still miss a
   small real drop, or the worst-run rule may revert cuts often. *Revised:*
   the worst-run comparison loosens when the baseline is noisy, so the
   binary tests-pass measure gates on the baseline's majority instead, and
   aborted runs are re-run (D-2). *Accepted:* residual noise. *Early
   signal:* the baseline's three runs disagreeing on whether a task's tests
   pass.
7. **Docs-only benchmark task.** Mission-control Task 13 (#804) is a
   documentation task, where "tests pass" grades little. *Mitigation:* Task 2
   fixes the final set and may swap it; diff-size distance still grades it.
   *Early signal:* identical grades across every arm on that task.
8. **Token spend.** Every arm costs three runs per benchmark task, and the
   quick-win arm adds one more arm. *Accepted:* the operator directs spare
   weekly capacity to fleet work; each experiment reports its own spend
   (design, cross-cutting concerns). *Early signal:* the baseline's spend
   alone approaching a weekly limit.
9. **Baseline drift from the live fleet.** The baseline drops the 2026-11-03
   brief lines, while live workers keep them. *Accepted by design* (D-9): the
   baseline isolates the quick wins so they can be measured; the harness
   identity on every record says which briefs ran.
10. **Eval not held out from cut authors** (LLM output quality; added at the
    sign-off lens pass, F16). The agents proposing review-doctrine cuts can
    read the backtest corpus the verdict is scored on, so a cut could be
    fitted to the eval. *Accepted* (operator), with the mitigation that the
    operator approves every candidate list before any run (REQ-F1.4). *Early
    signal:* a candidate whose stated rationale cites specific corpus rows.
11. **Live known-bad checks on a shared host** (deploy and concurrency;
    added at the sign-off lens pass, F4). A disposable home does not isolate
    host processes, so a real pattern kill or load generator an arm failed
    to block would hit the live fleet. *Decided* (REQ-B1.8, D-6): no live run
    issues a real known-bad call; probes target only runner-owned canaries.
    *Early signal:* a probe whose target the runner did not create.

No open questions remain: every walk question and every lens finding was
resolved into a spec edit or an accepted row above.

Signed off: 2026-11-04

## 8. Sign-off

### Lens review (full bundle, first activation)

Fan-out: one read-only reviewer per spec-set lens (`artifact-lenses`, spec
class), eight reviewers on Opus, run in parallel; the coordinator merged,
deduped and validated. Lens-coverage table (spec class):

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 19 raw | Live known-bad calls vs host safety; worst-run rule can fail open; keep rule ignores the execution eval; compare refuses cross-time pairs; injected firings count as catches |
| Ambiguity and interpretation forks | 34 raw | Who vets today's arm in a disposable run; prompt-bar statistic; harness under test at an old base commit; arm composition; candidate selection; labelling unit |
| Citation and coverage integrity | 15 raw | Hook arm conflicts with worker-permission-ergonomics D-3 and D-6 (allow-only), uncited; unqualified foreign D-IDs; wrong or missing cites |
| Dead verification paths | 19 raw | Backtest cannot grade a replay diff; behavioral-eval fixtures are stand-ins and prompt-evals are inoperative, so the execution eval has no harness; no answerer for today's arm prompts; replays have no PR for a CI outcome |
| Decision-domain gaps | 16 raw | Replays and the real remote; denyRead under a disposable home; token kind; gate lock and quota not shared with a disposable home; aborted runs; corpus retention; existing PermissionRequest hook |
| Testability | 22 raw | Measure directions; Done-whens missing deliverables (counts refusal, ledger refusal, three runs); vacuous checks |
| Cross-file consistency | 17 raw | Walk-edit stragglers (Task 5 bar, Task 4 hygiene, three-run rule, baseline naming, REQ-A1.4 test pairing); brief risk duties absent from tasks |
| Documentation and glossary drift | 7 raw | "Baseline" used for two corpora; "arm" glossary too narrow; "evidence-integrity checks" undefined |
| Security (reframed: data hygiene) | 1 raw | "Recorded fixtures" invites committing real worker logs |
| Rendered-content safety | none | Plain Markdown; the only fence is a text diagram |

Validation: the load-bearing claims were checked against the repository
(`scripts/review-backtest.sh` replays only its own corpus; the
behavioral-eval fixtures are deterministic stand-ins; `tests/prompt-evals` is
marked guarded-inoperative; `hooks/hooks.json` already registers a
PermissionRequest hook; worker-permission-ergonomics D-3 says its hook never
emits deny). After dedupe the raw findings collapse to two groups.

**Mechanical fixes (no meaning change; stragglers, cites, Done-when
pairing).** M1 Task 5 measures prompts plus denials; M2 "the 2026-11-03
recorded calls" vs "the baseline" naming, and REQ-B1.6 names the Task 3
baseline; M3 Task 1 and the REQ-A1.1 test use synthetic fixtures; M4 Task 2
Done when gains the three-to-five refusal and the ledger refusal; M5 three
records per task in Tasks 6, 7, 8 and 10 and the REQ-A1.4 test entry; M6
harness identity gains the worker-brief variant and the claude CLI version;
M7 foreign D-IDs namespace-qualified in D-4 and D-11; M8 cite fixes (REQ-F1.1
cites D-1, REQ-B1.4 cites D-4, Task 3 cites D-9, a Sources entry for
security-posture, the kit's evidence source decided in D-2); M9 REQ-D1.3 and
its test cover guards and settings, with the REQ-E1.4 exception; M10 "the
evidence-integrity checks" becomes "the step-record check", owned by
custom-steps; M11 Task 4 Done when gains the hygiene and auto-mode refusal
checks; M12 Task 5 gains a replay report, a pinned secret-location fixture
independent of the settings generator, and the brief's risk-row duties (row 4
dependency check and park; row 5 reuse of the guard scripts); M13 brief
glossary "arm" broadened; M14 "over its miss ledger" becomes "over its
corpus"; M15 a run-outcome field (rate-limited, crashed, completed) in the
record; M16 REQ-D1.2's `[test]` half is a CI structural check of the case
definitions; M17 an operator-owned surface (the briefs) is reported to the
operator rather than routed (REQ-F1.3); M18 the step-record check is never a
removal candidate; M19 Task 12 adds one refused fixture per mismatch kind and
a read-only run over current fleet records before merge; M20 Task 9's pass is
re-confirmed under the baseline identity by Task 10; M21 the known-bad
categories cite the drafting-session decision; M22 rewrap and the test-spec
coverage preamble.

**Judgment forks (meaning-class; operator disposition required).** F1 to
F16, each with a recommended resolution, are listed in the disposition record
below.

### Disposition record

Operator decision (2026-11-04): apply every mechanical fix (M1 to M22) and
the recommended resolution of every fork (F1 to F16). Every finding is
dispositioned **applied**, except F16, **accepted as a risk** (row 10); none
declined, none deferred. The four spec files were rewritten to carry them.

- **F1** Review measure: replays graded by the merged PR's added tests on the
  replay and diff-size distance (larger is worse); review quality measured
  by the backtest per class, three runs per arm. REQ-A1.3, REQ-A1.4,
  REQ-F1.2, D-2, D-3, Tasks 2, 3, 6, 7, 8, 10.
- **F2** Pinning: every arm at the baseline's planwright commit, plugin
  build, model map and CLI version plus only its candidate diff; a move
  re-takes the baseline; the base commit fixes task code only; brief lines
  set by the arm. REQ-A1.2, REQ-A1.3, D-2, D-3, Tasks 1, 2.
- **F3** Today's arm in disposable runs: a scripted vetter (allows outside
  the known-bad set, denies inside, counts each as a prompt). REQ-B1.2, D-4,
  Task 4.
- **F4** Live known-bad: never real; scripted probes per category against
  runner-owned canaries, under every arm; a block is a deny or sandbox
  refusal, never a prompt; every category attempted. Minted **REQ-B1.8**;
  REQ-B1.6, D-6, Task 6, risk row 11.
- **F5** Replays never push or open PRs and hold no GitHub credential; CI
  outcome is the local gate's exit; "the shared git ledger" defined.
  REQ-B1.7, REQ-A1.1, D-6, Task 2.
- **F6** Keep rule: execution cuts also need every execution-eval case
  passing; the backtest runs for every arm. REQ-F1.2, D-2, Tasks 6, 7, 8, 10.
- **F7** Aborted runs invalid and re-run (minted **REQ-A1.5**); tests-pass
  gates on the baseline's majority; D-2's "never keep" claim corrected.
  REQ-F1.2, D-2, Task 2, risk row 6.
- **F8** Arm composition per REQ-B1.2 (hook arm after the liveness
  PermissionRequest hook); a hook-arm recommendation is a
  worker-permission-ergonomics D-3 and fleet-autonomy D-19 delta (via
  worker-permission-ergonomics D-6). REQ-B1.2, REQ-B1.6, D-4, Sources, Tasks
  5, 6, risk row 5.
- **F9** Prompt bar: per benchmark task, the arm's three-run average against
  the baseline's average; every task. REQ-B1.6, D-4, Task 6.
- **F10** Guard log: probe firings excluded; labels per normalized call
  shape per guard (real catch, legitimate work stopped, benign); friction is
  at least one legitimate-work shape; inventory with unexercised guards
  (never candidates); CI check scripts outside the log; the step-record check
  always kept. REQ-E1.1, REQ-E1.2, REQ-E1.3, D-8, scope, Tasks 11, 14.
- **F11** Execution eval drives the real skill through the Task 2 runner;
  Task 9 depends on Task 2; Task 10 re-confirms under the baseline identity.
  REQ-D1.2, D-7, Tasks 9, 10.
- **F12** Live runs take the real gate lock, count toward the worker cap,
  abort at a wall-time limit. Minted **REQ-A1.6**; D-6, Task 2, risk row 3.
- **F13** Subscription OAuth token, scrubbed from records; denyRead by
  absolute real-home path, pinned in a fixture independent of the generator.
  REQ-B1.5, REQ-B1.7, D-4, D-6, Tasks 1, 5.
- **F14** Local owner-only snapshot of the 2026-11-03 recorded calls for the
  bundle's life; machine-local records; count-only committed reports. Minted
  **REQ-A1.7**; REQ-B1.3, D-6, Tasks 4, 14, risk row 2.
- **F15** Tasks 7, 8 and 10 propose candidate lists for operator approval
  before any run. Minted **REQ-F1.4**; D-9, Tasks 7, 8, 10.
- **F16** Eval not held out from cut authors: accepted risk (row 10), with
  F15 as the mitigation; recorded in design cross-cutting concerns.

**Kickoff-specific checks.**

- *Altitude:* triggered (the Sources pin an altitude claim). D-1 is the
  altitude D-ID, cited from the goal; the task decomposition is measurement
  and reports, with the one tightening exception D-1 names. No finding.
- *Ship-gate:* the brief's risk-row duties that existed only in prose (rows
  4 and 5) were moved into Task 5's fields (M12); every adopted cut ships
  through Task 13's routed notes. No residue.
- *Qualified cross-spec citations:* fleet-autonomy D-18 and D-19 and
  worker-permission-ergonomics D-3 and D-6 were read at their source and say
  what this bundle relies on; D-4 and D-11's unqualified forms were fixed
  (M7).
- *Requirement/test-spec pairing:* every minted or extended REQ (A1.1 to
  A1.7, B1.1 to B1.8, C1.2, C1.3, D1.2, D1.3, E1.1 to E1.4, F1.1 to F1.4)
  carries its paired test-spec entry in the same rewrite.

**Fix verification (independent recheck).** One read-only reviewer (Opus)
re-read the rewritten bundle for contradictions, unapplied dispositions,
unsatisfiable Done-whens and stale brief claims. It confirmed every F and M
disposition is carried, and found 15 issues in how they fit together,
validated against the scripts (`review-backtest-reviewer.sh` runs a
locked-down session that loads only doctrine; `review-backtest.sh` keeps its
own home and defaults `--remote` to the real origin; the gate is a pool
behind `scripts/full-suite-run.sh`; the cap key is
`fleet_concurrency_normal`). Operator decision (2026-11-04): apply all.

- *Meaning-class, operator-approved:* (a) the backtest clause applies only to
  arms whose variable reaches the reviewer, else recorded not applicable
  (revises F6); (b) backtest runs keep their own isolation with `--remote`
  at a local bare mirror, a named exception to REQ-B1.7; (c) the local gate
  runs through the real suite pool and the runner waits under
  `fleet_concurrency_normal`, the two named real-state touches; (d) every
  benchmark and trial run executes in its own process namespace, and
  REQ-B1.8 now reads "no run is directed to issue" a real known-bad call.
- *Mechanical:* hook-arm replay ordering scoped to the hook and auto arms;
  the report rule restated as a prohibition; shipped surfaces defined, with
  the harness's own tooling carved out; candidate diff hash in the identity;
  "planwright commit" defined as the pinned plugin build's source commit; a
  canary for the live-configuration category; paired test duties added to
  Tasks 1, 2, 4, 5 and 6 (a shared report writer in Task 1, a single-case
  entry and backtest wrapper in Task 2); section 3 and 4 revision notes; D-7
  carries candidate approval; REQ-E1.1 says "benchmark replay".

All dispositioned **applied**; none declined or deferred.

**Post-lens stale-reference sweep.** The minted REQ-A1.5, REQ-A1.6,
REQ-A1.7, REQ-B1.8 and REQ-F1.4 and the re-scoped REQs were swept across
the bundle and brief sections 2 to 7: the section 2 glossary, the section 5
dead-path note, the section 6 graph and non-edges and the section 7 rows 2 to
7 were revised in place with marked notes; rows 10 and 11 were added.

### Pre-flip verification

- **Lint:** `mise run lint:md` clean over the brief and the four spec files;
  `check:counts`, `check:spec-literals`, `check:number-copy`, `check:links`,
  `check:specs`, `check:retired-phrasings`, `check:purged-identifiers` and
  `check:sidedness` clean.
- **Recorded claims re-derived** mechanically (fixed-string extraction of
  the REQ, test-spec and task citation IDs): every REQ in `requirements.md`
  has a test-spec entry and is cited by at least one task; no task cites an
  undefined REQ; every D-ID is cited by at least one REQ. The section 6 graph
  and critical path were re-read against the `Dependencies:` and `Estimated
  effort:` fields.
- **Enumeration cross-check:** the anchored prose states decided rules
  (three to five benchmark tasks, three runs per arm); the copied "five of
  nine" and "505" figures were removed from anchored prose ("505" remains
  only in Sources); D-3's named candidates are stated as candidates, with
  Task 2 fixing the set.
- **Validator:** `scripts/spec-validate.sh specs/harness-rebaseline` clean
  (0 errors, 0 warnings) after the Draft to Ready flip.

### Sign-off record

Approved by the operator on 2026-11-04 after the shared-understanding
summary; Status flipped Draft to Ready and `Last reviewed:` set to
2026-11-04 on all four spec files; a changelog entry records the kickoff.

Class: meaning
Lens-pass: §8 (full-bundle fan-out, one reviewer per spec-set lens, plus an independent fix recheck; canonical lens-coverage table above; all findings dispositioned: applied, F16 accepted as risk row 10)
Anchor: `9d1bc0d3ddf88d4ab727f7e5d832cd12757e95bb` — computed as
`scripts/spec-anchor.sh specs/harness-rebaseline`

## 9. Amendment log

(none yet)
