# Control plane — Kickoff brief

## 1. Header

- Spec: `specs/control-plane`
- Spec commit at walkthrough start: the drafted bundle's commit on
  `planwright/control-plane/spec` (`git log` of the branch names it).
- Walkthrough: 2026-11-16, first activation, full bundle, run through the
  operator's mission control: each question put to the operator one at a time,
  their answers relayed in their own words.
- Validator at pre-flight: no errors, no warnings.
- Inputs folded at kickoff: the spec-roots draft and the panel-gaps draft,
  local mission-control amendment branches named in `requirements.md` Sources.
  Neither branch was touched.

Signed off: 2026-11-16

## 2. Goal and glossary

The spec moves routine control-plane decisions (approving a worker's routine
prompt, dropping repeat or stale events, ordering and limits on launches,
evidence recording, decision-packet shape) out of model sessions into
deterministic code, in four slices built one at a time and each measured against
a machine-local baseline. It rules out code that merges, signs off, marks a
spec pull request ready or messages a person; it assumes the operator's
mission-control session (the hub) remains the operator's single contact.

Glossary resolutions: **hub** is the operator's mission-control session.
**Shadow** is a class mode in which the engine records what it would have
answered and answers nothing; **enforce** answers; **off** defers. **Spec
root** is the folder holding a repository's specs, answered by the resolver.

Operator decisions (2026-11-16, relayed):

- Spec roots fold into the queue part (REQ-F1.7 to REQ-F1.9, D-20).
- Panel gaps fold into the last part as outlined requirements (REQ-H1.6 to
  REQ-H1.9, D-21), keeping the screenshot-before-leaving-draft condition.
- Language: shell now behind a neutral contract, swap later (D-16).
- Cross-spec edges: same root, hard, fail closed; refused-push rename with its
  limits (D-17, REQ-G1.7).
- Main versus side work: hold up to an hour, then ask (D-18).
- Tests, lint, step-record writes and bounded CI waits join slice one (D-19,
  REQ-C1.11).
- Every class, `release-run` included, ships in shadow (REQ-C1.3, REQ-C1.6).
- Hub refinement, to be confirmed at sign-off: the hub, not the operator, reads
  each class's shadow log and brings the operator a one-line evidence summary,
  which gates the operator's yes to enforce (REQ-C1.6, D-6).

Signed off: 2026-11-16

## 3. Requirements walkthrough

Per-group outcomes (counts and lists derive from `requirements.md`):

- REQ-A, B, D, E, I: confirmed; lens fixes tightened REQ-B1.3 (defer, not
  refuse), D1.3 (stale first event delivered; gate-origin events bypass), E1.1
  (baseline before wiring) and I1.2 (kill switch defers floor acts too, and is
  reported when left on).
- REQ-C: C1.3, C1.5, C1.6, C1.8, C1.9 amended; C1.11 added. The floor gained
  marking a spec pull request ready and showing the operator outside the render
  gate, scoped to what a worker asks the engine to approve.
- REQ-F: F1.2 and F1.3 settled (D-17, D-18); F1.7 to F1.9 added from the
  spec-roots draft.
- REQ-G: G1.1 excludes spec pull requests and panel pull requests carrying the
  screenshot condition; G1.7 added (refused-push rename).
- REQ-H: H1.6 to H1.9 added from the panel-gaps draft.

Where each folded piece landed: spec-roots draft requirements T1.1 to T1.5 into
REQ-F1.7 to REQ-F1.9 and its decisions into D-20, its tasks into Tasks 21 and
22 (the third, skill prose and docs, is a deliverable of Task 22). Panel-gaps
draft requirements S1.1 to S1.10 into REQ-H1.6 to REQ-H1.8 and the standing
condition into REQ-H1.9, its decisions into D-21, its tasks into Tasks 23 to 25
(the type check is Task 25), its six deferred gaps into the Deferred section.
Nothing was dropped silently.

Consolidated spec-edit list: see the two commits on the branch after the
drafted bundle's commit.

Signed off: 2026-11-16

## 4. Design walkthrough

Every D-ID accounted for: D-1 to D-5, D-7 to D-9, D-11 to D-15 confirmed;
D-6 amended (every class in shadow, the hub reads the log); D-10 confirmed;
D-14 amended (floor acts defer under the kill switch); D-16 to D-18 settled
(were open); D-19 to D-21 new. No decision contradicts a walked requirement
after the lens fixes.

Signed off: 2026-11-16

## 5. Verification approach

Slice one is `[test]` over language-neutral fixtures; the hub bringing a class
summary to the operator and the panel screenshot are `[manual]`. Dead paths
found by the lens pass (checks no task built) were assigned to Tasks 2 to 5 and
12; the stale test-spec entries for `release-run` and the class modes were
corrected. CI runs the `[test]` entries; the operator sweeps `[manual]`.

Signed off: 2026-11-16

## 6. Task graph

Derived from `tasks.md` `Dependencies:` lines. Slice one's critical path is
Task 2, then Task 3, then Task 4; Task 1 and Task 5 run beside them, and
Tasks 4 and 5 wait on Task 1 so the baseline precedes any wiring (REQ-E1.1)
without delaying the engine. Deliberate non-edges: Task 3 does not wait on
Task 1 (the engine is built and fixtured before it is wired); Tasks 21 and 22
do not gate Tasks 8 to 10 (the roots reader is needed by the queue consumers,
and Task 22 gates only the slice-three walk).

Signed off: 2026-11-16

## 7. Risk register

1. Shadow answers nothing, so slice one's approval half moves no turn count
   until a class goes live; mitigation: the would-have-answered share is the
   shadow-period number and the turn change is recorded at the first enforce
   (REQ-E1.2).
2. A machine-local file could loosen a class; mitigation: `enforce` and the
   merge reach are read from shipped and adopter layers only.
3. A worker edits the repository's own test or lint entry point to widen its
   class; mitigation: entry points come from the base commit or operator
   policy, never the worker's branch (REQ-C1.11).
4. The engine's log and dedupe state are written by concurrent watchers.
   Decision-domain gap (concurrency): locking, append atomicity and crash
   behavior are undecided; to settle in Task 3 and Task 5 design, with the
   queue's lock mechanics at the slice-two walk.
5. Decision-domain gap (auth): how a session proves its program to the answer
   verb beyond the launcher registry; settled by the answer-owner draft.
6. Decision-domain gap (queues-async): coalescing's kept-or-merged semantics,
   ordering within a window and crash behavior are undecided; Task 5.
7. Decision-domain gap (knowledge-engineering): the event taxonomy (decision,
   blocker, failure, landed, routine) has no owner and no default for an
   unmapped kind (it should deliver); Task 5.
8. Decision-domain gap (observability): a dropped policy entry or an
   engine-error defer degrades silently; mitigation: the denial and drop counts
   and the kill-switch report, with a signal for a dropped entry to be added in
   Task 2.
9. Decision-domain gaps (data-storage, api-surface, versioning-scheme,
   secrets-config, dependency-adoption, deploy-migration, existing-seam-reuse):
   the log, ledger and baseline locations, the verb contract and exit codes,
   the format marker, the token-shape definition, the schema validator and the
   promotion criterion, and reuse of the existing audit, usage and event
   scripts are undecided; each is a Task 2 or Task 3 design item, to be
   recorded as decisions before those tasks' code.
10. Decision-domain gap (llm-output-quality, human-comprehension): the hub's
    evidence summary is computed by code (REQ-C1.6), not written by a model.
11. Panel pull requests wait on the operator's screenshot approval; the
    reconciler never flips them (REQ-G1.1, REQ-H1.9).

Signed off: 2026-11-16

## 8. Sign-off

Signed off by the operator, 2026-11-16, relayed through their mission control
in their own words ("Approve (Recommended)"), including the hub reading the
watch-only logs and bringing the one-line evidence summary as the gate.
Validator: no errors, no warnings; markdown lint, count-versus-list and spec
literal checks clean. Draft to Ready flipped on all four spec files.

Lens pass: full-bundle Discovery-Rigor review on the spec lens set (contract
correctness, ambiguity, citation and coverage, verification paths and
testability, decision-domain gaps with the altitude and ship-gate checks,
cross-file and glossary drift), one read-only agent per lens, run foreground.
Performance, concurrency and error-handling code lenses are not applicable to a
spec. Findings were applied as spec edits (the two commits after the drafted
bundle), except the decision-domain gaps, recorded as risk rows 4 to 10; no
finding was declined. Altitude: D-1 present and now cited from the Goal; the
doctrine document is a Task 2 deliverable. Ship-gate: out-of-band follow-ups
now carry Awaiting-input, Deferred or Out-of-scope entries.

Class: meaning
Lens-pass: section 8 above (full-bundle review, all findings dispositioned)
Anchor: `342acb672c7dd4a36d2f75c9c15812c3b3b1d7fe` — computed as
`scripts/spec-anchor.sh specs/control-plane`

## 9. Amendment log

### Amendment 1, 2026-11-18

Scope: three gaps a review bot raised on the spec pull request before it
merged, delta walk only. Each decision was put to the operator one at a time
through their mission control and answered in their own words ("Shipped + your
config only (Recommended)", "Drop, report every wake (Recommended)", "Locked
one-line appends (Recommended)"), then signed off ("Sign off (Recommended)").

- Kill switch: read from the shipped and adopter layers only; a machine-local
  value is ignored and reported (REQ-I1.2, D-14, Task 2).
- Dropped policy entries: still dropped, now counted, shown by `explain` and
  reported at each wake with file and entry, the wake line owned by Task 4
  (REQ-B1.3, D-3, Task 2, Task 4). Risk row 8's pending signal is settled.
- Decision log and drop ledger: one complete line per record appended under a
  file lock, a torn last line skipped and repaired by the next write, a bounded
  lock wait that never changes a verdict or a delivery (new REQ-I1.5, Task 4,
  Task 5). Risk row 4's concurrency gap is settled for locking, append
  atomicity and crash behavior; the queue's lock mechanics stay with the
  slice-two walk.

Lens pass: delta-scoped review by two read-only agents run foreground (contract
and cross-file drift; verification paths and decision-domain gaps). Six findings,
all applied as spec edits and none declined: test-spec heading order, an
untested `explain` clause, the wake report's carrier (Task 4), the lock-failure
behavior, a crash-simulating fixture and separate-process writers, and one
re-wrap. None changed a decision the operator had signed.

Validator: no errors after re-anchor.

Class: meaning
Lens-pass: this entry (delta review, all findings dispositioned)
Anchor: `e266ba56d9c54a99aee982b66100ecff4b141c49` — computed as
`scripts/spec-anchor.sh specs/control-plane`
