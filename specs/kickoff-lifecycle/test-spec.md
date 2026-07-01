# Kickoff Lifecycle — Test Spec

**Status:** Done
**Last reviewed:** 2026-06-29
**Format-version:** 1

Coverage mix: the validator and reconcile behaviors are automated `[test]`
(they are scripts with deterministic input/output); the skill-prose changes
(`/spec-kickoff`, `/orchestrate`, `/spec-walkthrough` behavior) are
`[test + manual]` where a fixture bundle exercises them and a manual pass
confirms the operator-facing behavior; the meta-spec and boundary decisions are
`[design-level]` (the artifact's existence and coverage is the verification).
The migration is `[test + manual]`. End-to-end lifecycle behavior is given as
`[Gherkin]` scenarios.

## REQ-A — The Ready status & lifecycle

### REQ-A1.1 — Ready recognized as a sixth status [design-level + test]

`doctrine/spec-format.md` lists `Ready` in the status table with the meaning
"signed off, validated, executable, no work started"; the validator's status
enum accepts it (covered concretely by REQ-B1.2's test). Verification: the
meta-spec table contains the row, and `scripts/spec-validate.sh` does not flag a
`Ready` bundle as unknown-status.

### REQ-A1.2 — Draft → Ready → Active → Done lifecycle [Gherkin]

Given a Draft bundle, when `/spec-kickoff` signs it off, then its Status is
`Ready`. Given a Ready bundle, when `/orchestrate` dispatches its first task and
the reconcile runs, then its Status derives to `Active`. Given an Active bundle,
when its last Forward/In-progress/Awaiting-input task moves to Completed, then its
Status is `Done`. Given a Ready bundle whose tasks all complete in one reconcile
pass (none ever observed In-progress), then its Status derives directly to `Done`
(no Active intermediate), Done determination taking precedence (REQ-A1.5). Retired
and Superseded remain reachable only by human action.

### REQ-A1.3 — Ready carries the old sign-off meaning; Active narrowed [design-level]

The meta-spec and the kickoff/orchestrate skill prose define `Ready` as
"signed off, executable" and `Active` as "work in flight". Verification: no core
doc or skill describes a signed-off-unstarted bundle as Active; a grep of core
status prose shows Ready, not Active, for the post-sign-off pre-dispatch state.

### REQ-A1.4 — Draft→Ready is a stored human flip, not derived [test + manual]

A fixture Draft bundle taken through `/spec-kickoff` sign-off has `Status: Ready`
written to all four files by the skill (stored), with no dependence on task-state
derivation. Manual: confirm the flip is authored by kickoff and survives with no
tasks dispatched. Test: assert the four files read `Ready` after the sign-off
write.

### REQ-A1.5 — Ready↔Active derived by the single writer [test]

Against fixture bundles, the extended reconcile (Task 6) computes `Active` iff at
least one task derives In-progress or Completed, else `Ready` when signed off, and
writes the bundle `Status:` header; a second, independent writer of the header is
absent. Test: feed task-state fixtures (no progress → Ready; one In-progress →
Active; one Completed → Active; all Completed → Done; a signed-off bundle with no
startable tasks → Done) and assert the derived Status; assert (by code audit / grep
test) that only the reconcile writer mutates the header. Also assert the Done
mirror-completion clause: a bundle already `Done` with a partially-applied
four-file mirror (an earlier sibling write refused, e.g. a symlinked target)
converges every file to `Done` on the next reconcile when the derived value is
still `Done`, and the writer never reopens a stored `Done` to `Ready`/`Active`
(covered by the partial-mirror self-heal and symlink-refusal cases in
`tests/test-tasks-pr-sync.sh`).

### REQ-A1.6 — Reopen cycle flips to Ready, not Active [test + manual]

Extending a Done bundle flips it Done→Draft; the scoped delta kickoff flips it to
`Ready`; the delta's first dispatch derives `Active`. Test: a fixture Done bundle
through extend + scoped sign-off reads `Ready`. Manual: confirm the reopen path is
unchanged except for the Ready landing state.

### REQ-A1.7 — Migration: Active-with-no-progress → Ready [test + manual]

The one-time migration (Task 8) applied to a corpus containing an Active bundle
with zero tasks in flight (the `orchestration-concurrency` shape) sets it to
`Ready`, and an Active bundle with an in-flight or completed task stays `Active`.
Test: run the sweep over fixtures and assert per-bundle Status. Manual: confirm the
real in-repo bundles (`orchestration-concurrency`, `orchestration-fleet`) land on
the expected Status.

### REQ-A1.8 — Ready lifecycle ships atomically; producer gated behind drainer [design-level]

The task graph sequences the Draft→Ready producer (Task 3) behind the derived
reconcile (Task 6), so no release can ship a `Ready`-producing flip without the
`Ready`→`Active` drainer. Verification: Task 3's `Dependencies:` line names Task 6
with the D-9 rationale, and D-9 records the atomic-delivery decision; a reader (or a
grep of `tasks.md`) confirms the producer cannot land before the reconcile. The
inert recognition-only tasks (2, 5, 7) carry no such dependency.

## REQ-B — Validator & meta-spec format

### REQ-B1.1 — Meta-spec six-status update + bootstrap supersede pointers [design-level]

`doctrine/spec-format.md` carries the six-status table and transitions; `bootstrap`
`design.md` D-40/D-44/D-26 carry `Superseded-by: kickoff-lifecycle …` pointers with
dated changelog entries in both bundles; bootstrap's Status stays Done.
Verification: the pointers and changelog entries exist and the validator passes
both bundles (a supersede with a changelog entry is accepted, spec-format
invariant 8).

### REQ-B1.2 — Validator treats Ready as errors-block [test]

`tests/test-spec-validate.sh`: a `Ready` bundle containing a structural violation
(for example a task missing a definition field) exits non-zero (errors), the same
as an Active bundle; the test is written failing-first against the pre-change
validator. A clean `Ready` bundle passes; a `Draft` bundle with the same violation
warns (exit 0).

### REQ-B1.3 — Valid transitions accepted; terminal discipline preserved [test]

`tests/test-spec-validate.sh`: Draft→Ready, Ready→Active, Ready→Done (direct
completion), Active→Done, and Done→Draft baseline-diff cases pass; a transition out
of Retired or Superseded is still rejected as a hard finding.

## REQ-C — Orchestration gates

### REQ-C1.1 — `/orchestrate` acts on Ready or Active [test + manual]

A fixture `Ready` spec is dispatchable by `/orchestrate`; a fixture `Active` spec
still is; `Draft`, `Done`, `Retired`, and `Superseded` are refused with a clear
message; no bypass flag exists; `/orchestrate` does not auto-chain into
`/spec-kickoff`. Test: the selection/refusal path over status fixtures. Manual:
the refusal message names Ready-or-Active as the executable set.

### REQ-C1.2 — Ready→Active via the derived reconcile, no independent writer [test]

On the first dispatch creating In-progress evidence for a Ready spec, the reconcile
renders `Active`; `/orchestrate` itself writes no Status flip. Test: simulate first
dispatch, run the reconcile, assert `Active`, and assert `/orchestrate` did not
write the header (single-writer audit). Shares the Task 6 harness with REQ-A1.5.

### REQ-C1.3 — Freshness gate composes with the Ready gate [test + manual]

A `Ready` spec with a stale content anchor is refused by the freshness gate exactly
as an Active spec would be, halting to Awaiting input with the documented remedy.
Test: a stale-anchor Ready fixture halts. Manual: confirm the halt message is the
freshness-gate remedy, not a status refusal.

## REQ-D — Kickoff sign-off & spec-PR ready-flip

### REQ-D1.1 — Kickoff sign-off writes Ready across four files [test + manual]

Covered jointly with REQ-A1.4: sign-off writes `Status: Ready` to all four files,
bumps `Last reviewed`, and writes the sign-off record with the anchor last. Test:
post-sign-off file assertions. Manual: the kickoff handoff reports Ready, not
Active.

### REQ-D1.2 — Spec PR marked ready as the terminal step; never auto-merge [manual + test]

On clean completion `/spec-kickoff` marks the spec PR ready as its last action;
a parked-on-fork or non-converged completion leaves it draft; the skill never
merges. Test (mockable git/gh surface): the ready-flip is invoked only on the
clean path and a merge call is never issued; a ready-flip failure (no remote / gh
auth / PR not found) degrades to Awaiting input, not a crash; `config/worker-settings.json`
permits `gh pr ready` (no longer in `deny`). Manual: exercise a clean kickoff and a
parked kickoff and confirm the PR draft/ready state.

### REQ-D1.3 — Only the spec PR is auto-readied; opt-out gates it [test + manual]

Task PRs remain drafts; only the spec PR is readied; `mark_spec_pr_ready_on_kickoff:
false` suppresses the flip. `bootstrap D-26` carries the narrowing supersede
pointer. Test: the opt-out path skips the flip; `scripts/check-options-reference.sh`
passes with the new option documented. Manual: a task PR created elsewhere is
unaffected.

### REQ-D1.4 — Change-handling scales with lifecycle stage [test + manual]

A `Ready` bundle's pre-merge change is handled as a delta re-walkthrough / re-sign-off
(expression: changelog + self-re-anchor; meaning: delta lens pass + re-sign-off +
fresh anchor), not the amendment ritual, and the spec PR stays ready; an `Active`
bundle's change goes through the amendment ritual; a `Done` bundle reopens to Draft.
Test: mode dispatch over Ready/Active/Done status fixtures asserts the path taken
(re-sign-off vs amendment vs reopen). Manual: a meaning change to a Ready bundle
re-signs-off the delta — running its delta lens pass — without invoking in-flight
amendment coordination, and does not demand a reopen.

### REQ-D1.5 — "Gauntlet" is the configurable verification; flip is terminal [design-level + manual]

The skill docs express the pre-flip verification as the `review_sequence`-class
mechanism, not a hardcoded gauntlet; the ready-flip is documented as the terminal
step after it. Verification: the kickoff skill prose and `docs/options-reference.md`
describe the configurable verification and the flip ordering; manual confirmation
that an overlay review pass, when configured, precedes the flip.

## REQ-E — Downstream status surfaces & boundary

### REQ-E1.1 — Core renderers recognize Ready [test + manual]

`/spec-walkthrough` frames a `Ready` bundle with stage-appropriate language (its
stage-aware framing learns the new stage), and validator/skill status enumerations
include Ready. Test: the walkthrough renderer over a Ready fixture emits Ready-stage
framing; a grep test asserts status enumerations include Ready. Manual: read the
Ready-stage framing for tone/accuracy.

### REQ-E1.2 — Ready is a substrate-agnostic core value; dashboard rendering is overlay [design-level]

Core exposes `Ready` as a plain status value with no dashboard-specific coupling;
the cross-session inbox/heartbeat Ready rendering is documented as an overlay
concern. Verification: the design boundary (D-8) is recorded, and no core file
implements the heartbeat Ready rendering (grep shows the dashboard surface remains
absent from core, per bootstrap's out-of-scope).
