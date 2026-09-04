# Fleet lifecycle closure — Kickoff brief

**Spec path:** `specs/fleet-lifecycle-closure`
**Spec commit at walkthrough start:** `6da0a95b96adade8ba0f737d6a3a15f25bea4606`
**Walkthrough dates:** 2026-08-18 – 2026-08-19
**Mode:** first activation (Status Draft, no prior brief)
**Format-version:** 2 (bundle declares v2; stored status rests at Ready, execution derived)
**Validator outcome at pre-flight:** `spec-validate: 0 error(s), 0 warning(s)`
**Config:** `commit_on_kickoff: true` · `mark_spec_pr_ready_on_kickoff: true` · `kickoff_ready_ci_wait: 10m`

## 2. Goal & glossary

**Restated goal.** planwright can start a worker on every rung and cannot end
one on any of them. Both session-grade rungs ship a launch verb and no stop;
`fleet-cleanup.sh` reclaims `window` and `worktree` but never a process; the
attention store already names terminal states that assume a teardown verb
nobody built. The leak is path-dependent — a worker reaching SessionEnd exits
cleanly, so the common path looks tidy and only abandoned or hard-killed
workers leak, silently. Detection fails in the same shape: nothing separates a
working worker from one blocked at a permission prompt, because every stuck
state looks like silence. The remedy is stated as a doctrine floor first
(D-1), with the verbs, the detector, and the sweep as its instantiations.

**Rules out.** Auto-merge (permanent). Reclaiming a dead tower's unit — this
bundle releases processes, never units (D-2). Worktree reclamation from the
close verb (D-3). Tower-to-tower messaging (D-7). Two pieces routed to their
doctrinal owners as scoped amendments (D-9); general supervisor hardening left
as cited residue (D-10).

**Assumes.** Towers are multiple by default, so every destructive verb is
defined under concurrency. `fleet-presence.sh` and the per-unit `origin` fence
are extended, never duplicated. Single-host. Positive evidence is the only
admissible basis for a destructive act; unknown and errored both mean alive.

**Glossary — terms resolved without operator input.** *tower* (an orchestrator
instance) · *rung* (a backend tier in the capability contract) · *unit* (a
dispatched piece of work) · *fence* (the per-unit `origin` marker, the sole
exclusion object) · *strand* (an unfinished unit surfaced for the operator's
reserved reclaim decision) · *death handle* (the backend-supplied token
`fleet-death-evidence.sh` reads) · *session-grade rung*
(`stream-json-persistent` and `headless-oneshot`).

### Resolution 2.1 — "worker lifecycle phase" means one phase per resource class

The floor's quantifier was undefined: REQ-A1.1 and D-1 promise three parts per
"phase", the bundle never enumerates the phases, Task 1 builds a per-backend
table instead, and REQ-C1.7 uses "phase" in an unrelated second sense.

**Decided:** a phase is **one resource class a worker acquires**. Each owes a
start-record, a release that survives a hard kill, and a stuck-signal. The
floor's table is per resource class, not per backend; empty cells stay visible
as gaps. REQ-A1.5's per-backend obligation composes onto it: a backend
declares, for each resource class it acquires, its open, close, and detector.

**Chosen because** the resource classes are already enumerated in the spec's
own release set (REQ-B1.4), so the phases are read off the bundle rather than
invented — and enumerating them immediately surfaced a class the release set
omits (Finding 2.2), which the per-backend framing would not have exposed.

### Finding 2.2 — the concurrency-slot counter is a resource class with no close

`fleet-state.sh` keeps a fleet-wide slot counter: `bound-incr` grants a
dispatch slot, `bound-decr` returns it. A worker that leaks never decrements,
so the fleet believes it is at capacity and silently stops dispatching. The
symptom differs from the leaked-hours class that motivated the bundle: it is a
denial of new work rather than wasted spend. REQ-B1.4's release set does not
include it, so `stop` as specified would not release it.

**Decided:** the slot counter joins the release set. Carried into the section 3
consolidated edit list.

### Terminology collision

"Phase" is used in a second, unrelated sense in REQ-C1.7 ("which phase of its
unit a worker is in"). Renamed in the consolidated edit list so the floor's
term is unambiguous.

Signed off: 2026-08-18

## 3. Requirements walkthrough

Ten groups walked. Per-group outcome, then the consolidated edit list.

| Group | Outcome |
| --- | --- |
| REQ-A — lifecycle-closure contract | Amended. The floor's quantifier was undefined; resolved to one phase per resource class (Resolution 2.1). REQ-A1.5's per-backend obligation composes onto it. |
| REQ-B — deterministic close | Confirmed. Release set unchanged; see Correction 3.1 for the class considered and excluded. |
| REQ-C — stuck-detector | Confirmed, one wording edit: REQ-C1.7's second sense of "phase" renamed to "stage". |
| REQ-D — multi-tower safety | Confirmed. The REQ-B1.4 / REQ-D1.3 conflict was already resolved at drafting by REQ-D1.9. |
| REQ-E — enumeration and inventory | Confirmed, and the premise verified: no dispatch-path script calls `fleet-state.sh register` today, so the registry genuinely has no live writer. Task 3's five seams match the four spawning scripts plus the print rung; the remaining `*dispatch*` scripts are helpers, not seams. |
| REQ-F — periodic sweep | Confirmed. |
| REQ-G — steer | Confirmed. |
| REQ-H — lifecycle-open correctness | Confirmed, and the recorded outage verified still live (Finding 3.2). |
| REQ-J — carried floors | Confirmed. |
| REQ-K — cross-cutting quality | Confirmed. |

### Correction 3.1 — the reservation slot is residue, not a release-set omission

Finding 2.2 held that the concurrency-slot counter was a resource class missing
from REQ-B1.4's release set. Direct inspection of `scripts/fleet-state.sh` and
`scripts/orchestrate-meta-select.sh` corrected it on three points:

- `bound-incr`/`bound-decr` is a **same-instant reservation** primitive, not a
  capacity ledger. Its role is closing the sub-second window between a tower
  deciding to dispatch and the worker's durable artifact existing.
- The authoritative in-flight count **already derives** from live git state,
  level-triggered and self-healing. The selector reads that and deliberately
  does not read the counter.
- The slot leak is already recorded in the script's own header, with a
  redesign named, tracked as `fleet-bound-slot-leak`.

So there was nothing to move, and deleting the counter would have removed
cover for a race the derivation cannot see, because it fires before the
artifact the derivation reads exists.

**Decided:** the leak is a genuine open with no crash-surviving close, and the
REQ-A1.1 floor names it in principle — but by D-10's own scoping rule (does the
defect disable or corrupt a lifecycle verb this bundle defines?) it is residue.
Recorded as a gated Deferred entry rather than prose, matching the form the
bundle's three existing residue items already use, so it cannot rot unnoticed.

### Finding 3.2 — the `WorktreeCreate` outage D-11 records is still live

`hooks/hooks.json` registers `WorktreeCreate`, and
`scripts/fleet-worktree-track.sh hook-create` extracts `.worktree_path` from a
payload that carries `name`. It warns to discarded stderr and echoes nothing,
so the harness refuses creation. D-11 states the minimal unblocking fix "ships
out of band as a chore PR"; that PR has not landed. Because a registered
`WorktreeCreate` hook replaces native worktree creation, this is broken on
every installed machine — including the path by which this bundle's own tasks
would be dispatched. Carried to section 5 as a dispatch-readiness gate.

### Consolidated spec edits applied

1. `requirements.md` REQ-A1.1 and the Goal — the floor's quantifier defined as
   one resource class a worker acquires.
2. `requirements.md` REQ-A1.5 — a backend declares all three for every
   resource class it acquires.
3. `requirements.md` REQ-C1.7 — second sense of "phase" renamed to "stage".
4. `design.md` D-1 — quantifier matched to REQ-A1.1.
5. `tasks.md` Task 1 — deliverable and Done-when moved from a per-backend
   table to a resource-class table crossed with the rungs, with declared gaps
   distinguished from absent rows.
6. `tasks.md` Task 7 — "or PR-less" dropped from the unlanded-work check; it
   contradicted REQ-C1.4's deliberate narrowing to locally observable git
   state, recorded in the drafting changelog.
7. `tasks.md` Deferred — the dispatch reservation-slot leak added as a gated
   entry (Correction 3.1).
8. `test-spec.md` REQ-A1.1, REQ-A1.5, REQ-C1.7 — matched to the above.

Validator re-run after the edits: `0 error(s), 0 warning(s)`.

Signed off: 2026-08-18

## 4. Design walkthrough

Twelve decisions, all accounted for. One amended, eleven confirmed with
rationale intact.

| D-ID | Disposition |
| --- | --- |
| D-1 — altitude, doctrine floor first | **Amended.** Quantifier defined as one resource class a worker acquires. The altitude argument, the rejected alternatives, and the chosen-because are untouched; only the scope of "phase" was under-specified. |
| D-2 — reaping is not reclaiming | Confirmed. Load-bearing for REQ-D1.2, REQ-D1.3, REQ-D1.9 and the Task 11 matrix. |
| D-3 — close releases runtime resources, never the worktree | Confirmed. Release set unchanged (Correction 3.1). |
| D-4 — detector enumerates positively, on two axes | Confirmed. |
| D-5 — sweep periodically, never on a threshold | Confirmed. |
| D-6 — supervisor-native steer primary, messaging secondary | Confirmed. |
| D-7 — no tower-to-tower messaging arm | Confirmed. |
| D-8 — messaging is a probed transport, not a backend row | Confirmed. |
| D-9 — one new bundle plus two scoped amendments | Confirmed. |
| D-10 — lock defects scoped to those wedging a lifecycle verb | Confirmed, and exercised: its rule decided Correction 3.1 mechanically rather than by judgment, which is the property D-10 claims for itself. |
| D-11 — `WorktreeCreate` corrected, hooks get payload fixtures | Confirmed, and its premise verified still live (Finding 3.2). |
| D-12 — dispatch record gains an owner token | Confirmed. |

**Reconciliation.** No design decision contradicts a walked requirement. The
one apparent conflict at drafting (REQ-B1.4's attention-record release versus
REQ-D1.3's surfaced strand) was already resolved by REQ-D1.9 before this
walkthrough, and D-2 states the boundary the two rest on.

**Deliberate non-decisions confirmed.** D-7 rejects a standing amendment
rather than deferring it, and records why, so a later reader re-deriving the
research report's recommendation finds the rejection attached.

Signed off: 2026-08-18

## 5. Verification approach

**Coverage mix.** Derived from `test-spec.md`'s tag annotations rather than
transcribed; re-derive with a tag tally over that file. The bundle is
overwhelmingly shell mechanism over structured signals, so fixture entries
dominate, with a design-level tail for the doctrine group, a manual half on the
entries depending on a live session or host capability, and one opt-in
rehearsal tier added by this walkthrough.

**Every REQ is pinned.** Checked mechanically at kickoff by diffing the REQ-ID
set defined in `requirements.md` against the set carrying a `test-spec.md`
entry; the two matched exactly, including the requirements this walkthrough
added.

**Verification ownership.**
- `[test]` — the project's shell suite, run by `mise run check` and project CI.
- `[design-level]` — review assertion at PR time, plus
  `scripts/check-doctrine-manifest.sh` and the doc-link check where the claim
  is existence and citation.
- `[manual]` — swept by the operator; each names why CI cannot pin it (a
  platform-rendered prompt shape, a live session, a host-side feature flag).
- `[rehearsal]` — new tier (Resolution 5.1). Opt-in, operator-run, outside
  ordinary CI.

**Dead paths.** None. No requirement names a verification that cannot run. The
`[rehearsal]` entries depend on a harness that does not exist yet, but it is a
Task 12 deliverable rather than an assumed capability.

### Resolution 5.1 — the floor is proven by a deliberate-wedge rehearsal

Raised by the operator: the bundle should test as far as it can that a real
worker on a real spec does not get stuck. The bundle as drafted verified almost
entirely through fixtures, which cannot falsify its own central claim — the
Goal argues the leak is invisible *because* the common path looks tidy, and a
fixture exercises the path its author imagined.

**Decided:** a repeatable, opt-in rehearsal dispatches a real worker against a
throwaway spec bundle on each session-grade rung, wedges it deliberately at a
permission prompt, and asserts it classifies `waiting-on-a-human`, closes on
`stop`, and leaves every resource class empty. Recorded as REQ-A1.6 and D-13,
built by Task 12, verified under a new `[rehearsal]` tag. A run that cannot
establish a live session reports a visible skip, never a pass.

### Finding 5.2 — dispatch is gated on an unshipped chore fix

Carried from Finding 3.2. Recorded as a **dispatch gate** in `tasks.md`'s intro
prose, because it blocks every task rather than any one of them, and it lives
outside this bundle's task graph — so nothing here fails if it never lands.

Signed off: 2026-08-18

## 6. Task graph

Reconstructed from the `Dependencies:` fields, which are authoritative; render
with `scripts/spec-graph.sh`.

```
1 ── 2 ── 3 ─┬─ 4 ── 5 ─┬─ 6 ─┬─ 8 ─┬─ 11
             │          │     │     └─ 12
             │          └─────┘
             └─ 7 ──────────────┘
1 ── 9 ── 10   (10 also depends on 3)
```

**Critical path.** `1 → 2 → 3 → 4 → 5 → 6 → 8 → 11`, and `12` finishes
alongside `11`. Path length and serial total are derived from the
`Estimated effort:` fields; re-derive from `tasks.md` rather than trusting a
transcribed figure. Parallelism is roughly 1.6×, mechanically re-derived at
sign-off (an earlier draft of this section carried 1.8×, which the
re-derivation gate caught).

**Parallelism.** Task 9 (steer) forks immediately after Task 1 and runs
alongside the registry chain. Task 7 (detector) runs alongside Tasks 4–6 after
Task 3. Task 10 joins the registry and steer chains.

### Deliberate non-edges — recorded so nobody "fixes" them

- **Task 9 does not depend on Task 3.** Steer reaches a live worker through its
  own input fifo by handle; it needs no registry record. Adding the edge would
  serialize the steer work behind the registry for no reason.
- **Task 12 does not depend on Task 11.** The rehearsal proves the close and
  detector end to end; the adversarial matrix is fixture-driven concurrency
  coverage. They are complementary, and coupling them would delay the
  rehearsal's feedback behind the largest fixture suite in the bundle.
- **Task 2 precedes Task 3 deliberately.** The worktree-tracking hook feeds the
  registry, so its payload contract must be correct before the registry gains a
  live writer — otherwise Task 3 builds on the contract D-11 corrects.

### Finding 6.1 — a missing edge, added

Task 6 (`process` as a cleanup class) depended only on Tasks 1 and 3, so it
could be built before either `stop` existed — which would have given the fleet
two kill paths, each with its own state-dir match, signal escalation, and
release set. The bundle already cites a duplicated security-critical tokenizer
as residue it regrets (obs:30159d5c, obs:92809aad).

**Decided:** Task 6 now depends on Tasks 4 and 5 and delegates termination to
the rungs' `stop`, with a source audit in its Done-when asserting there is no
second implementation. Costs roughly two days on the critical path.

Signed off: 2026-08-18

## 7. Risk register

Rows are appended by execution skills (research, performance, and security
findings) and never overwritten.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | The `WorktreeCreate` chore fix gates every dispatch but sits outside this bundle's task graph, so nothing here fails if it never lands. | Recorded as a dispatch gate in `tasks.md` intro prose. Early signal: the first dispatch attempt refuses, visibly, rather than hanging. |
| 2 | `waiting-on-a-human` rests on positively matching a prompt signature — a platform-rendered surface that can change without notice. planwright has already been burned by exactly this class (D-11). A silent divergence would degrade the detector to the blind spot the bundle exists to close. | The REQ-C1.2 manual half and the REQ-A1.6 rehearsal both assert against the running CLI rather than a captured fixture. Early signal: the rehearsal failing on an unchanged codebase. |
| 3 | The sweep is the one destructive mechanism here, and a reap already performed cannot be undone by pausing future ones. | D-14: ships observing-only, promoted per machine by an explicit reversible knob; REQ-F1.7 keeps the shipped mode exercised. Early signal: the dry-run audit trail disagreeing with operator expectation before anything is promoted. |
| 4 | The dispatch reservation slot leaks on a tower crash, tightening admission against a bound that no longer reflects reality. Out of scope by the D-10 rule. | Gated Deferred entry; the authoritative in-flight count is the live git derivation, not this counter, so the blast radius is admission tightness rather than over-dispatch. Early signal: the gate firing, or admission refusing against an apparently idle fleet. |
| 5 | Messaging availability is a host and session property that several environment variables can remove silently, and it is the only steer `headless-oneshot` has. | REQ-G1.5's deterministic probe with visible degradation; REQ-G1.6 keeps it off the correctness path; REQ-G1.8 records the bound. Early signal: the probe reporting absent on a host that previously had it. |
| 6 | Twelve tasks over a long critical path give the bundle time to drift from the signed anchor during execution. | The execution freshness gate recomputes the anchor and refuses on mismatch. Early signal: a dispatch refusing on a stale anchor. |
| 7 | Task 12's rehearsal consumes a live session and model budget, so it may be skipped in practice and quietly stop being run. | REQ-A1.6 requires a visible skip rather than a silent pass, so a never-run rehearsal is legible rather than mistaken for coverage. |

### Decision-domains gap check

Walked the merged catalog (`scripts/resolve-catalog.sh decision-domains`,
eleven seed domains, no overlay additions on this host) against the bundle.

Ten domains are touched and decided: `data-storage` (registry shape, REQ-E1.2,
with the absent-token compat rule in REQ-D1.5), `queues-async` (the scheduled
sweep, REQ-B1.7 and REQ-D1.6), `api-surface` (the new subcommands, REQ-K1.1),
`auth` (the owner token as an attribution primitive, REQ-D1.5), `secrets-config`
(REQ-K1.2, REQ-K1.6, REQ-G1.10), `concurrency` (the whole REQ-D group, D-2,
D-10), `observability` (REQ-F1.2, REQ-F1.4, REQ-C1.8), `dependency-adoption`
(D-8 adopts a platform feature, not a library). `caching` and
`versioning-scheme` are not touched.

**One gap found and closed:** `deploy-migration`. The bundle flips the sweep to
a schedule and makes it autonomously terminate processes — a fleet-wide change
that cannot roll back atomically — while deciding only the pause switch and the
schedule knob, never the rollout. Resolved into D-14, REQ-F1.6, and REQ-F1.7
rather than accepted as a standing risk; risk-register row 3 carries the
residual.

Signed off: 2026-08-18

## 8. Sign-off

### Lens review pass

Discovery-Rigor review of the full bundle (first activation scope).
**Path: walked inline, not fanned out** — this session is configured not to
spawn sub-agents, so the coverage table below reflects a single-context walk
and is declared as such rather than implying a fan-out it did not receive.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 2 | L-1 sweep capability vs. activation; L-2 partial-close retry undefined. |
| Security | none | Untrusted-input, echo-discipline, and identifier-validation rules already cover the surfaces this walkthrough added; the rehearsal's kill path inherits REQ-B1.3's state-dir match rather than introducing one. |
| Error handling and failure modes | none | Refusal, partial, and degradation paths covered by REQ-A1.3, REQ-F1.4, REQ-K1.1, REQ-K1.7. |
| Performance | none | REQ-C1.4 explicitly bars per-worker forge queries; the rehearsal's cost is bounded by being opt-in and outside ordinary CI. |
| Concurrency / state | none | REQ-D1.6 and REQ-B1.7 cover concurrent sweeps and idempotence; the observing-only mode adds only duplicate would-have records under concurrent towers, which is noise rather than corruption. |
| Naming, readability, structure | 1 | L-3 close/stop/reap used interchangeably, never distinguished. |
| Documentation | none | Origin-tag legend, changelog, and in-scope list reconciled by the stale-reference sweep below. |
| Tests / verification | none | Every REQ pinned, checked mechanically; both sweep modes rehearsed (REQ-F1.7). |
| Cross-file consistency | 1 | L-1, counted once under correctness and tagged here. |

**Altitude check (REQ-H1.3).** Determined bundle-locally from the pinned seed
claims in `requirements.md`'s Sources. The bundle **is** altitude-triggered:
the drafting brief carries altitude assertions about the deliverable's nature.
D-1 exists, is cited from the Goal, and the decomposition matches the claimed
altitude — Task 1 is doctrine-only with no executable behaviour, and the
mechanism tasks sit beneath it. Not a finding.

**Dropped after validation.** Two candidates did not survive: a branch with no
remote-tracking ref making every commit "absent" turns out to be correct
behaviour (the work genuinely is unlanded), and the rehearsal harness's kill
path is already scoped by REQ-B1.3's state-dir match rather than needing its
own guard.

### Lens findings and dispositions

| ID | Lens | Finding | Disposition |
| --- | --- | --- | --- |
| L-1 | Correctness · cross-file | REQ-B1.6 required the sweep to close what the tower did not, while REQ-F1.6 (added earlier in this same walkthrough) ships it observing-only — so at ship the sweep closes nothing and the two requirements contradict. | **Applied.** REQ-B1.6 restated as a capability requirement, with termination explicitly gated by REQ-F1.6's promotion knob and an observing-only sweep satisfying it by recording what it would have closed. test-spec entry updated so a dry-run cannot be mistaken for discharging it. |
| L-2 | Correctness | REQ-B1.7 required a second stop to report already-closed, but REQ-A1.3 allows a first close to be partial — so the second stop would abandon the classes that were never released. | **Applied.** Idempotence redefined over the release set rather than the invocation: a second stop retries exactly the classes still held and may not report already-closed while any remain, sending no signal to a process tree already gone. test-spec and Task 4's Done-when updated. |
| L-3 | Naming, readability, structure | "Close", "stop", and "reap" used interchangeably throughout, though the distinction is load-bearing — REQ-D1.4's both-towers death-evidence bar, REQ-D1.2's live-peer refusal, and D-2's reaping-is-not-reclaiming all attach to one of the three and not the others. | **Applied.** A Vocabulary section added to `requirements.md`: close is the contract concept, stop is the named verb for a worker this tower owns or an operator names, reap is the autonomous close of a dead-or-unknown owner's worker and the only one carrying the evidence bar. A reap performs a close rather than being a second mechanism. |

No finding was declined or deferred; the anchor below is therefore
execution-valid under REQ-F1.10.

### Post-lens stale-reference sweep

The lens pass re-scoped REQ-B1.6 and REQ-B1.7 and minted no REQ, so the sweep
ran over the walkthrough's earlier mints (REQ-A1.6, REQ-F1.6, REQ-F1.7, D-13,
D-14, Task 12, the `[rehearsal]` tag). Reconciled:

- `requirements.md` in-scope list — the observing-only sweep default and the
  rehearsal added; the floor's quantifier matched to REQ-A1.1.
- `requirements.md` Changelog — kickoff entry recording every edit below.
- `requirements.md` Sources — `decision-domains` added, since the gap check
  against it produced D-14.
- `design.md` origin-tag legend — extended to cover a kickoff-session decision,
  which D-13 and D-14 are and the legend did not admit.
- `test-spec.md` preamble — the transcribed "three requirements" count removed
  in favour of the rule, and the `[rehearsal]` tier described.
- `tasks.md` Task 4 Done-when — partial-close retry added alongside the
  already-closed assertion.

### Pre-flip verification

- **Lint (REQ-B1.2).** `mise run lint:md` over the brief and every edited spec
  file: clean. Three errors were fixed to get there, one of them in
  `specs/_pending/merge-currency-guard-amendment.md`, which this branch's
  drafting commit introduced and which would have failed CI on the spec PR.
- **Full gate.** `mise run check` green: 144 test files passed, all lints and
  guards clean.
- **Recorded-claim re-derivation (REQ-B1.3, D-4).** Re-derived mechanically
  from the bundle, treating its content as data:
  - REQ-ID set defined in `requirements.md` vs. the set carrying a
    `test-spec.md` entry — equal, no unpinned requirement and no orphan entry.
  - Task graph parsed from the `Dependencies:` fields with effort from
    `Estimated effort:` — critical chain `1 → 2 → 3 → 4 → 5 → 6 → 8 → 11`,
    with Task 12 finishing alongside Task 11.
  - **One mismatch caught and corrected:** section 6 carried a transcribed
    parallelism figure of 1.8× against a 29-day serial total; the derivation
    returns 1.6× against 26.5. Section 6 corrected before the anchor.
- **Validator.** `spec-validate.sh`: 0 errors, 0 warnings.

### Sign-off record

**Mode:** first activation · **Scope:** full bundle, all seven sections walked
· **Spec edits applied:** the consolidated list in section 3, plus REQ-A1.6 /
D-13 (section 5), REQ-F1.6 / REQ-F1.7 / D-14 (section 7), the Task 6 dependency
edge (section 6), and the three lens findings above · **Open questions:** none
· **Inconsistency halts:** none.

Class: meaning
Lens-pass: the *Lens review pass* section above — full-bundle Discovery-Rigor
review, walked inline (path declared), canonical coverage table emitted, three
findings all applied, two dropped after validation, altitude check recorded.
Anchor: `e724c448699df69114a785d4b09b5ac8d9aa4ffc` — computed as
`scripts/spec-anchor.sh specs/fleet-lifecycle-closure`

## 9. Amendment log

### Re-anchor — anchor-scope exclusion sweep (2026-08-24)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by the coordinated sweep
that lands with the hash-scope change (anchor-integrity D-3, REQ-A1.4).

**Why the anchor moved:** the hash scope changed, not this bundle's
content. The per-file digests for `requirements.md`, `design.md`, and
`test-spec.md` now drop the header-block `**Status:**` line, so every
bundle carrying one recomputes to a new value. Verified by isolation:
recomputing under the amended semantics over this bundle as it stood at the
prior entry's commit (`db55986`) yields the same hash recorded below, so no
anchored byte has changed since that entry was written.

**Cites the changelog line:** the 2026-07-26 `## Changelog` entry in
`doctrine/spec-format.md` ("Anchor-scope exclusion"), the doctrine half of
the change this entry re-anchors against.

Class: expression-only
Anchor: `2fb577fe3f9a422e64c23cec511396f1c0c53777` — computed as
`scripts/spec-anchor.sh specs/fleet-lifecycle-closure`

### Re-anchor — foreign citations qualified (2026-09-03)

Marked self-re-anchor for the expression-only edit the format-grammar
validator's citation-range rule (format-grammar REQ-D1.3, D-13) surfaced on
its all-bundle rollout run (format-grammar D-9, REQ-D1.10): D-10's rejected alternative now cites the fold-vs-new test as `bootstrap D-21`.
A foreign id now carries its owning spec's name where the reader meets it; no
requirement or decision changes meaning.

**Cites the changelog line:** the 2026-09-03 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `64828f99a0d32842d3dd2607f7f5ebd9ca522786` — computed as
`scripts/spec-anchor.sh specs/fleet-lifecycle-closure`
