# Test throughput — Kickoff brief

## 1. Header

- **Spec path:** `specs/test-throughput`
- **Spec commit at walkthrough start:** `a7c5d51`
- **Walkthrough date:** 2026-09-28
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `scripts/spec-validate.sh` — 0 errors,
  0 warnings (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (core defaults; no machine-local override present)
- **Working location:** spec branch `planwright/test-throughput/spec`, in the
  existing worktree `.claude/worktrees/spec-test-throughput` (the branch the
  skill expects; the worktree directory name differs from the
  `<spec>-spec` convention and was reused rather than recreated)
- **Doctrine resolution:** all nine rule docs the skill names resolved under
  this checkout's `doctrine/` via `scripts/resolve-rule-doc.sh`
- **Cross-bundle preconditions checked at start:** review-effectiveness and
  universal-binary are both stored Ready on this branch's base;
  universal-binary Task 1 (the lock primitive) is completed, its Tasks 4 and
  4.1 are not; review-effectiveness Task 6 (the diff-scoped check) is not
  yet completed, and `scripts/check-diff-scoped.sh` does not exist yet
- **Decision/transcript log:** no harness-provided log path in this session;
  the structured-log mirror is skipped, per `interaction-style`'s turn-mirror
  rule (never improvised into the repository)
- **Independent cold read:** `/spec-walkthrough specs/test-throughput`
  offered as an optional complement; not a dependency of this walkthrough

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).** A fleet
testing at once on the operator's Mac turns a suite that takes minutes on CI
into hours locally, and workers spend time re-proving the same machine-only
failures. The bundle fixes this in five parts: a machine-wide ticket pool
capping concurrent test files across every worktree; an opt-in CI-first
worker policy (targeted local tests, an early draft PR, the PR's CI on the
current head as the full-suite verdict, a pooled local fallback when no PR
CI exists, and an operator-confirmed per-clone list of known machine-only
failures); profiling the slowest test files, fixing test-side causes and
routing production-side causes to universal-binary; busy-machine hardening
(poll-until-deadline instead of tight timing windows, and a lost runner
scratch directory reported as an environment error); and the known macOS
fixes with a CI bash 3.2 parse step and a local lint guarding their return.

**Rules out.** A macOS CI job (universal-binary Tasks 4 and 4.1); editing
review-effectiveness's signed text; reducing production-script spawn cost;
multi-line awk portability (PR #508); carrying the operator's login-shell
environment into workers; any change to the adopter default.

**Assumes.** universal-binary's lock primitive is on main (verified:
`scripts/lock-lib.sh`, universal-binary Task 1 completed). Review-effectiveness
Task 6 ships `scripts/check-diff-scoped.sh` (not yet built; Task 10's
`Done when:` names it). Review-effectiveness amends its full-suite-per-iteration
requirement through its own delta (Task 13's gate names it).

**Implicit terms surfaced.**

- **Ticket:** one unit of pool capacity. Paths and variables name it a
  *slot* (`test-slots`, `PLANWRIGHT_TEST_SLOTS`); the two words are the same
  thing.
- **Full-suite evidence:** what proves the whole suite green for a head: a
  local run (`local`) or the PR's CI run on that head (`remote-ci`).
- **Targeted check:** review-effectiveness's diff-scoped check, the tests
  touching the changed files plus the linters.
- **Known environmental failure:** a local failure that also fails on a clean
  baseline on this machine, operator-confirmed, listed per clone.
- **Clone:** the primary checkout and every worktree sharing its git common
  directory.

**Resolutions.**

- REQ-A1.1's "at most the pool's capacity" is read through D-4: with runs
  using different capacities, the bound is the largest capacity in use.
  Carried to the requirements walkthrough as a wording fix.

Signed off: 2026-09-28

## 3. Requirements walkthrough

**REQ-A — Machine-wide test ticket pool.** Intent confirmed: one per-user
pool bounds concurrent test files across every worktree, crash-safe through
the lock primitive's owner-liveness reclaim (verified in
`scripts/lock-lib.sh`: staleness is owner-process absence, never age), and
never blocks testing. Probing found that `tests/test-run-tests.sh` runs the
runner inside a test file, so a nested run could wait on a ticket its own
ancestor holds and deadlock at low capacity. Decision: a runner started
inside a pooled test file runs unpooled, silently (operator's choice, on
D-4's recorded never-block priority); the make-jobserver inheritance model
was weighed and rejected. REQ-A1.1's bound reworded to D-4's
largest-capacity-in-use rule.

**REQ-B — CI-first worker verification.** Intent confirmed. Checked:
`ci.yml` runs on every `pull_request` (drafts included), so early draft PRs
get CI with no workflow change; the list path is already ignored by
`.claude/*.local/`; `scripts/ready-guard.sh` checks currency and
mergeability only. Decisions: a CI run pending past one bounded poll is
re-polled until a new `pr_ci_wait` total (default `30m`) is spent, then the
unit halts to Awaiting input (mirroring kickoff's own bounded CI gate; the
local fallback was rejected as reintroducing the local-suite cost); an early
PR carries a `Convergence: pending` body line until the handoff's body
update replaces it (a label was rejected as needing provisioning).

**REQ-C — Slow-test profiling and test-side speedups.** Intent confirmed.
Decisions: "slowest" is a decided rule, the files making up the first half
of each host's total per-file wall-clock, slowest first. Probing found the
first-execution assessment stall hits far more than directly executed
fixtures: most executable test fixtures are PATH shims the code under test
runs by name. The operator asked whether signing would avoid it; signing
was judged not close (signatures ride extended attributes fresh writes do
not carry) and the macOS developer-tool exemption surfaced as the cheaper
candidate. Decision: the profile measures the stall with and without the
exemption, attended and fleet-dispatched (REQ-C1.5, D-14); a covering
exemption becomes a documented setup step, otherwise the gated Task 9.2
ships a warmed-shim helper and a lint.

**REQ-D — Tests that hold up on a busy machine.** Intent confirmed; no
gaps.

**REQ-E — macOS portability fixes and guards.** Intent confirmed. Probing
found the bash 3.2 parse step would miss the shebang-less sourced libraries
(the lock primitive and the spec parser among them) and was silent on the
extension-less git hooks; every such library already carries a
`# shellcheck shell=` directive. Decision: dialect is the shebang, else that
directive; the step covers every tracked file declaring either and fails on
a tracked `.sh` file declaring neither.

**Mid-walk lens passes.** Each agent-authored meaning-class edit got a
delta-scoped pass at application. Group A's pass found two knock-ons, both
applied: REQ-A1.1 names the nested exemption, and the nested unpooled run
prints no REQ-A1.4 warning. The group B and the group C/E passes found
nothing further.

**Consolidated spec-edit list (applied in place, Draft bundle).**

1. REQ-A1.1 reworded to the largest-capacity-in-use bound, naming the
   REQ-A1.8 exemption.
2. REQ-A1.8 added (nested runner runs unpooled, no warning); D-4 extended
   with its rationale and three rejected alternatives; Task 1 deliverable,
   `Done when:` line, and citation; test-spec entry.
3. REQ-B1.3 gains the `Convergence: pending` body line; REQ-B1.5 gains the
   `pr_ci_wait` re-poll and Awaiting-input halt; D-5 extended with three
   rejected alternatives; Task 10 deliverables and `Done when:`; test-spec
   REQ-B1.3 and REQ-B1.5 entries.
4. REQ-C1.1 gains the cumulative-half rule and the first-execution cause;
   REQ-C1.5 added; D-9 extended; D-14 added; Task 9 deliverables, `Done
   when:`, and citations; Task 9.2 added and parked under `## Deferred`
   with a free-text gate; test-spec REQ-C1.1 and REQ-C1.5 entries; two
   observation sources cited.
5. REQ-E1.6 re-scoped to shebang-else-directive dialect; D-11 extended with
   two rejected alternatives; Task 4 deliverables and `Done when:`;
   test-spec REQ-E1.6 entry.

Signed off: 2026-09-28

## 4. Design walkthrough

Every D-ID in `design.md` accounted for; no decision contradicts a walked
requirement.

| D-ID | Outcome | Note |
| --- | --- | --- |
| D-1 | Confirmed | Altitude split: worker policy an opt-in core capability, the rest repository mechanism |
| D-2 | Confirmed | Each test-file worker is its own process, satisfying the lock library's hold-belongs-to-the-taker rule |
| D-3 | Confirmed | Home state directory, owner-only |
| D-4 | Amended | Nested runs unpooled (REQ-A1.8) |
| D-5 | Amended | `pr_ci_wait` re-poll then Awaiting input; `Convergence: pending` body line |
| D-6 | Confirmed | `.claude/planwright.local/` does not collide with the overlay layers, which read only `doctrine.local/` and `catalogs.local/` |
| D-7 | Confirmed | Review-loop wiring parked behind the review-effectiveness amendment |
| D-8 | Confirmed | Portable detached recipe |
| D-9 | Amended | Cumulative-half rule for "slowest" |
| D-10 | Confirmed | Poll-until helper and sweep |
| D-11 | Amended | Parse dialect from shebang, else the shellcheck directive |
| D-12 | Confirmed | Shebang-honoring invocation |
| D-13 | Confirmed | Find the `core.hooksPath` writer first |
| D-14 | Added | Measure the developer-tool exemption; warmed-shim helper only if it falls short |

Residue carried to the risk register: D-6 locates the primary checkout
through git's common directory, assuming a non-bare primary checkout.

Signed off: 2026-09-28

## 5. Verification approach

**Coverage mix** (per `test-spec.md`'s tags). `[test]` covers the runner,
helpers, guards, and fixtures; `[Gherkin]` covers the `/execute-task`
behaviors a fixture unit exercises end to end; `[manual]` covers what needs
the operator's macOS host; `[design-level]` where the artifact is the
verification.

**Ownership.** `[test]` entries run in the repository CI through
`mise run check`; the bash 3.2 parse runs as its own CI step (Task 4).
`[Gherkin]` fixture-unit results are recorded by the implementing worker in
Task 10's and Task 11's PR bodies. `[manual]` entries (the macOS profile and
user-lookup verdict, the first-execution-stall measurement including a
fleet-dispatched worker, the real Graphviz 15 run, and the busy-machine
sweep's search record) are swept by the operator at PR review.

**Paths checked.** `tests/test-lock-lib.sh` pins the lock-holder list;
`check:options-reference` is wired into `mise run check`; every REQ carries
an entry (validator clean).

**Dead path found and fixed.** Task 8's `Done when:` and the REQ-D1.2 entry
required converted tests to pass under load "where they failed before",
unsatisfiable when a flaky before-run passes. Replaced (operator-approved):
the converted tests pass under the load run, and the PR body records the
unconverted tests' result under the same load. Expression-only in effect
(no requirement's meaning changed).

Signed off: 2026-09-28

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
efforts per each block's `Estimated effort:`).

```
1 ──────────────┬─→ 2
3 → 4 ──────────┼─→ 2, 5, 6, 7, 8, 12
                ├─→ 10 → 11 → 13 (parked)
1 ──────────────┤   (10 and 12 also need 1)
9 → 9.1 → 9.2 (parked)   (9.1 and 9.2 also need 4)
```

**Parallelism.** Tasks 1, 3, and 9 start together; Task 4's landing opens
Tasks 5, 6, 7, 8, and 12 at once.

**Critical path.** Effort-weighted, 1 → 10 → 11 → 13. Its real pacing is
external: Task 10's `Done when:` needs review-effectiveness Task 6
(`scripts/check-diff-scoped.sh`) on main, and Task 13's gate needs
review-effectiveness's delta amendment.

**Deliberate non-edges (do not "fix").**

- Task 1 carries no edge to Task 4, so pool relief is not held behind the
  guard (the `tasks.md` ordering-intent note).
- Task 9 carries no edge to Task 4: it is measurement plus a documentation
  line, not a shell edit.
- No edge crosses a bundle boundary; cross-bundle preconditions live in
  `Done when:` lines (D-7).

Signed off: 2026-09-28

## 7. Risk register

Inputs: risks surfaced during the walk, and the decision-domains gap check
(core seed catalog through `scripts/resolve-catalog.sh decision-domains`;
no overlay layers present).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | review-effectiveness Task 6 (`scripts/check-diff-scoped.sh`) paces Task 10 and everything behind it | Tasks 1, 3, 4, 9 and the Task-4 fan-out run meanwhile. Signal: review-effectiveness's status render still shows Task 6 unstarted when Task 1 lands |
| 2 | review-effectiveness's full-suite amendment may land late or differently, leaving Task 13 parked | The drain pass surfaces Task 13's gate verbatim (D-7). Signal: the gate still pending when Task 11 lands |
| 3 | The developer-tool exemption may not reach tmux or headless fleet workers, since macOS attributes it to the responsible app | Task 9 measures attended and fleet-dispatched runs separately (REQ-C1.5); Task 9.2 unparks on a shortfall. Signal: Task 9's fleet-dispatched stall measurement |
| 4 | The nested-run mark could leak into a non-test environment and make ordinary runs silently unpooled | Task 1 sets the mark only in the environment given to test files and names it as runner-internal. Signal: host oversubscription returning with no pool warning |
| 5 | Runs with different capacities make the machine-wide bound the largest value in use | Documented in the runner header (D-4); capacity comes from one machine-local layer. Signal: a timing report whose wait field stays near zero under a busy fleet |
| 6 | The list location assumes a non-bare primary checkout found through git's common directory (D-6) | Where no checkout sits above the common directory, the reader warns once and treats the list as empty (D-6, Task 11; operator-approved edit). Signal: that warning on a new clone layout |
| 7 | A known-environmental entry could mask a regression in a test the targeted check did not select | Entries never excuse PR CI (REQ-B1.7), which runs the whole suite on Linux. Signal: CI red on a test listed locally |
| 8 | The `bash:3.2` image digest pin ages | Refreshed deliberately, like the workflow's other digest pins (D-11). Signal: the image's upstream update without a pin bump |
| 9 | The early draft PR exposes an unconverged unit to reviewers and bots | `Convergence: pending` body line until handoff (REQ-B1.3); the ready flip stays the operator's. Signal: a review thread opened on a PR still marked pending |

**Gap-check outcomes applied as spec edits (operator-approved).**

- *existing-seam-reuse:* `scripts/await-pr-ci.sh` judges CI through
  `scripts/release-lib.sh`'s `rl_ci_state` rather than a second evaluator
  (D-5, Task 10).
- *observability / correctness:* an empty check list on a head whose
  repository has a PR-triggered workflow counts as pending, not no CI
  (REQ-B1.4, D-5, Task 10, test-spec). *(Refined at the sign-off lens pass:
  pending for a 3-minute grace window, then no CI; see section 8.)*
- *auth:* a GitHub authentication failure, or an unjudgeable CI read,
  halts the unit to Awaiting input rather than falling back (REQ-B1.4, D-5).
  *(Widened at the sign-off lens pass to every failed CI read, outages
  included; see section 8.)*
- *deploy-migration:* `full_suite_evidence` is read once at the unit's
  pre-flight, so planwright's own switch in Task 13 never changes evidence
  mid-unit (REQ-B1.1, D-5, Task 10, test-spec).

A mid-walk lens pass over these edits found one knock-on, applied: REQ-B1.4
names the unjudgeable-read halt that D-5 introduced.

Domains checked with nothing undecided: data-storage, queues-async,
api-surface, secrets-config, concurrency, dependency-adoption, org-design,
human-comprehension. Not applicable: caching, versioning-scheme,
product-strategy, packaging-pricing, knowledge-engineering, ip-posture,
llm-output-quality.

Signed off: 2026-09-28

## 8. Sign-off

### Lens review (first activation, full bundle)

Artifact class: **spec** (`artifact-lenses` spec set). Fan-out: one
read-only sub-agent per lens (seven agents; decision-domain gaps and the
security reframe folded into their nearest lens), then a coordinator merge,
dedupe, and verification of each load-bearing claim against the
repository. The kickoff altitude check and ship-gate check ran inline.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 9 | Fallback vs green-CI convergence; `/execute-task`'s terminal-PR rule; D-4's misstatement of lock-lib; Task 9.2's gate narrower than REQ-C1.5; REQ-C1.2 vs PATH shims; REQ-E1.1 vs the dialect rule; the parse step failing on its own fixtures; REQ-E1.3 vs D-13; a nonexistent `check:lock-primitive` task |
| Ambiguity and interpretation forks | 8 | The CI failure and skipped-check rule; the list's writer and mode; `pr_ci_wait` per head; the idle-run slowest set; minimum-elapsed assertions; the timing-report format change; knob resolution; when to detach |
| Citation and coverage integrity | 3 | review-effectiveness Task 6 missing from Sources; REQ-E1.1 and REQ-E1.4 lacked a traceable source (two observations recorded and reproduced at kickoff); two uncited observations |
| Dead verification paths | 3 | Folded into contract rows (parse-step fixtures, `check:lock-primitive`) and the Graphviz-15 evidence |
| Decision-domain gaps | 3 | Existing-seam reuse (`resolve-config-knob.sh`, `fleet-dispatch-headless.sh`); list write concurrency; timing-report schema |
| Testability | 1 | One sweep: every task's `Done when:` now carries the checks its cited REQs need |
| Cross-file consistency | 2 | Runner header vs Task 2's mid-run stop; Scope and Goal drift |
| Documentation and glossary drift | 2 | Goal "per-machine" vs per clone, "four parts", ticket = slot, D-1's doctrine sentence vs Task 5; missing usage and operator docs |
| Rendered-content safety and data hygiene | 1 | A local unpushed commit and worktree name in Sources, removed |

Raw agent findings deduped to 36 and re-validated adversarially; 4 were
declined as implementation detail an existing guard or convention settles
(script exit codes and names, the lock-holder list's placeholder marker,
already caught by `tests/test-lock-lib.sh`, the malformed-capacity
fallback, exact deadline and load numbers). The remaining 32 were
dispositioned by the operator in six decisions, all applied:

1. **CI verdict rule:** no CI means no remote, no `gh`, no
   `pull_request` trigger in the local workflow files, or a
   no-positive-result verdict persisting past a 3-minute grace window;
   every other failed read halts (REQ-B1.4, D-5).
2. **List writer:** the skill's single writer adds or removes an entry only
   on confirmation, by temporary file and rename; the list is consulted
   under `remote-ci` only (REQ-B1.6, REQ-B1.8, D-6).
3. **Sources:** no observation existed on any branch; both failures were
   reproduced on the operator's macOS host and recorded
   (obs:297401ec, obs:f334f13e), and REQ-E1.1 and REQ-E1.4 cite them.
4. **Nine contradictions:** applied as listed in the lens table's first row.
5. **Seven ambiguities:** applied (per-head `pr_ci_wait`, idle-run slowest
   set, minimum-elapsed scope, versioned timing report, shared knob
   resolver, the headless detach seam, detach every full local run).
6. **Completeness and documentation sweep:** applied.

**Altitude check.** Triggered (pinned seed claim in Sources); D-1 exists
and is cited from the Goal; the decomposition matches its claimed split
(core capability Tasks 10, 11, 13; repository mechanism elsewhere). D-1's
"no doctrine rule is minted" is now scoped to the worker policy, since
Task 5 extends existing invocation doctrine.

**Ship-gate check.** Every out-of-band item carries a tracked record: Task
13 and Task 9.2 are gated deferrals, the macOS budgets a gated deferral,
production causes and an outside `core.hooksPath` writer observations
their tasks record, and the Developer Tools setup step a Task 9
deliverable.

**Post-lens stale-reference sweep.** Run once over the bundle and brief
sections 2 to 7 for the terms the edits retired; three stragglers
reconciled, and section 7's two gap-check bullets annotated with their
refinements.

### Sign-off record

Signed off 2026-09-28 by the operator after the shared-understanding
summary: Status flipped Draft→Ready on all four spec files, `Last
reviewed:` 2026-09-28 on each, validator re-run clean (0 errors, 0
warnings).

Class: meaning
Lens-pass: the lens review recorded in this section (full bundle, spec lens set, fan-out, findings dispositioned)
Anchor: `145382e20837ade338225b1099010d78d5bf1bd9` — computed as
`scripts/spec-anchor.sh specs/test-throughput`
