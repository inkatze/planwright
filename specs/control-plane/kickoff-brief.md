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

### Amendment 2, 2026-11-19

Scope: the request ledger (REQ-J1.1 to REQ-J1.11, REQ-D1.6, D-22 to D-28,
Tasks 5 and 5.1 to 5.4 and the edits to Tasks 6 and 16), delta walk only, on
the Ready bundle, spec commit `c4bdd376` on
`planwright/control-plane/amendment-2`. Each question was put to the operator
through their mission control and answered in their own words. Validator at
pre-flight: one error, the expected anchor mismatch from the drafted delta,
carried as a must-fix item for this entry's anchor.

Drafting calls, answered by the operator (relayed by the hub, 2026-11-19):

- The ledger keeps a bounded, redacted excerpt with sender, time and id, the
  full text staying at its source (D-23): "Short redacted excerpt
  (Recommended)".
- A silent turn end is held once, then may end with the request raised (D-25,
  REQ-J1.6): "One hold (Recommended)".
- Capture stays on under the kill switch; only refusals and raises stand down
  (D-28, REQ-J1.10): "Keep recording (Recommended)".
- The unanswered windows (operator 15 minutes, session 20, pending prompt 10,
  repeated every 30) and a worker's pending prompt counted as a request (D-28,
  REQ-J1.1): "Yes, as drafted (Recommended)".

Inconsistency halt, resolved by spec edit: Task 5.1 had no dependency on
Task 1, yet it wires capture hooks into live sessions (and Task 5.2 adds the
turn-end hold), while REQ-E1.1 requires the baseline before the first slice's
code is wired and REQ-J1.11 measures against it. The operator chose "Wait for
baseline (Recommended)": Task 5.1 now waits on Task 1, so the baseline
precedes every slice-one wiring.

Mission-control Task 51's hold: it sat on Task 5.2, leaving Tasks 5.1 and 5.3
dispatchable while that task, which covers the same capture, turn-end check
and handover self-check, stayed open in its own bundle. The operator chose
"On the first ledger task (Recommended)": the Awaiting-input hold moves to
Task 5.1.

The excerpt's scrub: the drafting call above was put to the operator as
scrubbing secrets and personal data, while the draft redacted credential
shapes only (the reused screen matches nothing else), and the excerpt rides
the unanswered push. The operator chose "Secrets, emails, phones
(Recommended)": REQ-J1.4, D-23, Task 5.1 and the REQ-J1.4 test entry now
redact email addresses and phone numbers too, by a pattern set the ledger adds
beside the secret screen, and the stored-log check scans for all three.

The kill switch's reach: the turn-end hold (Task 5.2) and the handover
refusal (Task 5.3) were built before the only task that stood them down
(Task 5.4), and neither waited on the switch (Task 2), so between landings the
switch would not stop them (REQ-I1.2, REQ-J1.10). The operator chose "Wait and
obey it (Recommended)": Tasks 5.2 and 5.3 now wait on Task 2 and each proves
its own stand-down; Task 5.4 keeps the raises and the wake line.

A closed request's echo: REQ-D1.6 never dropped a request-bearing event,
while D-27 made a request stale once closed. The operator chose "Drop and
count (Recommended)": REQ-D1.6, D-27, Task 5 and the REQ-D1.6 test entry now
deliver every repeat, stale or off-order event while its request is open, and
drop and count one once the ledger has closed that request with checked
evidence.

The gate's read of the ledger: Task 5 now reads the ledger (open or closed,
and every id in a coalesced wake) but did not wait on Task 5.1, which builds
it. The operator chose "Yes, wait for ledger (Recommended)": Task 5 now waits
on Task 5.1. Task 6 already waited on Task 5.4, so the path to slice two is
unchanged; the gate now sits behind Task 5.1's mission-control hold.

Class: the operator classified the delta "Changes what's built
(Recommended)" (meaning-class).

Lens pass (spec artifact class, delta-scoped): one read-only agent per lens,
run foreground. The walk's own edits were reviewed in this terminal pass, not
by a separate mid-walk pass at each application.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness | 8 | burst link vs two ids; Task 5.2 and Task 5 needing Task 5.4's composer; windows in no task; raise emitter and repeat drop; capture-failed raise under the switch; close-record free text; stale "proposed" and "go to the operator" text |
| Ambiguity | 24 | holder, request-bearing set, request vs arrival, relayed operator words, wake prompts captured, turn scope, linker, excerpt cut order, patterns, clocks, MAY vs SHALL, evidence predicates, spool ids, resume, wake bound, measures |
| Citation and coverage | 6 | changelog omits the walk; registry flag built by no task; Task 6 and 5.4 citations; test fixtures missing from Done-when |
| Verification and testability | 12 | unfixtured "never closed by age"; refusal fixture per evidence kind; spool in every check; resume and self-check; probe note; raise push and clock; panel render; J1.11 owner |
| Decision-domain gaps (with altitude, ship-gate) | 24 + 2 | storage, concurrency, config layering, redaction failure, evidence provenance, verbs, repeat flood, rollout and backfill, seam reuse; altitude passes (D-22 cited from the goal, mechanism tasks); ship-gate: the miss ledger REQ-J1.11 writes to is unbuilt (mission-control Task 83) |
| Cross-file and glossary drift | 7 | "never dropped" left in six places; Task 5.4 Done-when; brief task graph; capture-timing wording; markdown lint clean |
| Rendered-content safety | n/a | the prose is not rendered into an executing context; the excerpt's display is a spec'd behavior, covered under contract and gaps |
| Performance, concurrency, error handling (code lenses) | n/a | a spec has no execution path |

Dispositions. Findings were validated against the bundle and deduped (one
miss-ledger claim confirmed: no script hosts it yet). The operator chose
"Yes, apply both (Recommended)" for the two groups below; the six judgment
calls follow them.

Applied as spec edits (agent-resolvable, one obvious answer):

- "Never dropped" restated as "never dropped while open, an echo of a
  closed one dropped and counted" in the scope bullet, changelog, D-8 note,
  D-27 title, Task 5 and the REQ-D1.6 test heading; REQ-D1.6 split into two
  sentences, its MAY made SHALL, and droppable only once every request an
  event carries is closed.
- Stale "proposed" and "go to the operator" text in D-23, D-28 and the open
  questions paragraph replaced by the settled values.
- D-23's link is two sightings of one message only; a coalesced burst is
  wake composition, each request closed on its own (it contradicted "two
  sends keep two ids").
- Definitions in REQ-J's preamble: request (every arrival), holds a program
  name (the live holder, mission-control REQ-A1.1), request-bearing kind (a
  registry flag; pending prompt and relayed question shipped), turn, wake;
  composer-written and hook-injected text never captured (REQ-J1.1).
- Ordering: the gate attaches request ids to its coalesced event and the
  composer lists them (Task 5 no longer needs Task 5.4); the turn-end hold
  marks a held request and the next wake lists it (Task 5.2 no longer needs
  Task 5.4); the window, interval and wake-bound knobs moved into Task 5.4,
  `request_ledger_wake_lines` default 10; REQ-J1.9 names knobs, not REQ-B1.1
  policy files.
- The unanswered raise is emitted by the keeper's sweep, each repeat with a
  new state version so the gate never drops it.
- Redaction runs before the cut; close records' quoted words and reasons are
  bounded and redacted; the evidence predicates (answer addressed to the
  sender, repeat not closed as a repeat, non-empty no-ask reason, a machine
  evidence kind); spool lines carry their id and every spool is read; age
  from the earliest sighting; the window runs until the close; the repeat
  counts from the previous raise; a relayed question takes the session
  window.
- REQ-J1.11's misses are recorded as unavailable until mission-control's
  miss ledger (its Task 83) lands; daily counts per local day from Task 5.4's
  merge.
- Coverage: the registry flag, probe note, no-model-write check, field,
  straddling-token, spool-everywhere, per-kind refusal, aged-truncated-handed
  over, resume and self-check, injected clock, push, gate delivery, panel
  render, unreadable preview and knob-default fixtures copied into the Done
  when lines and test entries; Task 6 and Task 5.4 citations; the superseded
  REQ-D1.3 test entry marked not run; the capture-timing wording unified.
- Declined: moving REQ-D1.3's superseded pointer above its citation, which
  the meta-spec does not order and the validator accepts.

Task graph after the walk: Task 1, then Task 5.1 (also held on mission-control
Task 51), then Task 5 (with Task 2), Task 5.2 and Task 5.3 (each with Task 2),
then Task 5.4, then Task 6 with Task 4.

Risk register additions (deferred to the task that designs each):

- **Risk 12.** Data storage: the ledger's retention, how the open set is
  found across monthly segments (a close in a later month than its arrival),
  and the per-month id counter under the lock; Task 5.1.
- **Risk 13.** Versioning: whether the three record kinds join the knowledge
  base's format 1 or bump it, and how a reader treats an unknown record kind;
  Task 5.1.
- **Risk 14.** Concurrency: the linker's pairing (when it runs, under which
  lock, one-to-one in time order for identical bursts), the digest's input,
  and the link window's default; Task 5.1, with an identical-burst fixture.
- **Risk 15.** Concurrency: spool retry idempotency (a stable arrival key so
  a landed append is not duplicated), who drains a dead session's spool, and
  the hook's own lock-wait bound; Task 5.1.
- **Risk 16.** Data hygiene: the personal-data pattern set's minimum formats
  (email, international and national phone numbers); Task 5.1.
- **Risk 17.** Api surface: the new verbs' names, evidence grammar and exit
  codes (refused-unverifiable, error, not-holder), and a close whose forge
  read fails (refused, the safe side); Tasks 5.1 and 5.2.
- **Risk 18.** Existing-seam reuse: `answer:` by a reply turn reads the
  harness's transcript, a format the harness owns, and the transcript
  pointer's stability is unstated; Task 5.2 records the nearest seam (the
  messaging transport's persisted answer artifact) and why it does or does
  not serve.
- **Risk 19.** Noise: every operator message is a request, so a one-word
  "ok" needs a no-ask close before the turn may end without a hold; accepted
  as the cost of the forcing function, measured by REQ-J1.11's close-kind
  counts.

Judgment calls (decision-domain gaps the operator settled):

1. Rollout: the hold and the handover refusal would refuse from landing,
   across sessions not all yet capturing, with no copy of asks open before
   landing. The operator chose "Record-only first (Recommended)": new
   REQ-J1.12 and D-29 ship both in shadow, enforcing only on the operator's
   yes after the hub's code-computed summary (as REQ-C1.6 gates a class);
   capture, closes, wakes, the panel and the raise run from landing; no
   backfill, the handover file's items covering earlier asks. Tasks 5.2 and
   5.3 and a new REQ-J1.12 test entry carry it.
2. Knob layers: any layer, the session-writable machine-local file included,
   could set the windows, interval, excerpt, link window and wake-list bound,
   so a session could silence its own alerts. The operator chose "Defaults +
   repo config (Recommended)": every ledger knob is read from the shipped and
   adopter layers only, a machine-local value ignored and reported (REQ-J1.9,
   D-28, Tasks 5.1 and 5.4, the REQ-J1.9 test entry).
3. Quote provenance: any same-user process can claim to relay the operator,
   so a quote close could be forged. The operator chose "Typed or matching
   relay (Recommended)": an operator message is text typed into the session
   or a hub relay linked to the hub holder's own send record; any other
   claimed relay is a cross-session message (REQ-J preamble, D-25, Task 5.2,
   the REQ-J1.5 test entry).
4. Scrub failure: undecided whether a failed redaction stores raw text,
   drops the ask, or neither. The operator chose "Record, no text
   (Recommended)": the arrival is written without its excerpt, still open,
   and the failure raised (REQ-J1.4, D-23, Task 5.1, the REQ-J1.4 test
   entry).
5. Alert flood: each overdue request repeated its own push every interval.
   The operator chose "One combined repeat (Recommended)": one push per
   request when it first goes overdue, then one combined repeat per program
   each interval naming the open count and the oldest (REQ-J1.9, D-28, Task
   5.4, the REQ-J1.9 test entry).
6. Kill switch and capture failures: whether "its raises stand down" covered
   a failed append or redaction. The operator chose "Yes, still alert
   (Recommended)": only the unanswered raises stand down; capture failures
   are still raised (REQ-J1.10, D-28, Task 5.4, the REQ-J1.10 test entry).

Altitude: D-22 resolves the pinned claim, is cited from the goal, and the
tasks are mechanism. Ship-gate: mission-control's own amendment recording its
Task 51 as carried is held by the Task 5.1 Awaiting-input entry and recorded
as an observation; the miss ledger REQ-J1.11 writes to is named unavailable
until mission-control Task 83 lands. Stale-reference sweep run for the minted
REQ-J1.12 and D-29. Out of scope, recorded as an observation: the
mission-control amendment itself.

Signed off by the operator, 2026-11-19, relayed by the hub in their own
words ("Sign off"), after the approval summary. No status flip (the bundle
stays Ready); `Last reviewed:` is 2026-11-19 on all four spec files.
Validator: no errors besides the anchor this entry replaces; markdown lint
and the memory-link check clean.

Class: meaning
Lens-pass: this entry (delta review, all findings dispositioned)
Anchor: `c15a141b7d5ed16b4864485f42981d35a2e336eb` — computed as
`scripts/spec-anchor.sh specs/control-plane`
