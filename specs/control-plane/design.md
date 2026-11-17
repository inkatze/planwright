# Control plane — Design

**Status:** Draft
**Last reviewed:** 2026-11-15
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` = new to this bundle; `C, <namespace> <id>` = carried
from another bundle's decision, the foreign id namespace-qualified; `O` = an
open question for kickoff, with its recommended default drafted.

Slice one (D-4 to D-9, D-14, D-19) is designed in full. Slices two to four are
outlined (D-11, D-12, D-13); each carries a design walk (Tasks 6, 11, 16)
whose output amends this bundle before any build task of that slice starts.

## Decision log

### D-1: Altitude — a doctrine line enforced by mechanism, not one more script (N)

**Decision:** The deliverable is a layering rule with its enforcement: code
holds state and makes routine moves, models do judgment, the operator sees
gates (the doctrine), and the approval engine, dedupe gate, queue,
reconciler and packet renderer are the mechanism that makes the rule true.
The doctrine is stated in REQ-A and the mechanism is built slice by slice. The
altitude claim pinned in Sources (the cause is a design assumption, not a
missing feature) is why REQ-A comes first and every slice cites it.

**Alternatives considered:**
- Specify only mechanism (a script per rule). Rejected because: that is the
  disease this spec treats; each script would be one more patch with no rule
  saying where the next routine move goes.
- Specify only doctrine (a rewrite of the standing rules). Rejected because: a
  doctrine with no enforcing code is more prose for sessions to miss.

**Chosen because:** the failure pattern is that written rules without a
mechanism decay; a rule needs a code home (REQ-A1.4) before its prose can go.

### D-2: Every standing rule has exactly one home; prose retires only against proof (N)

**Decision:** Each rule kind maps to one home: ordering and limits to the
queue and dispatcher, continuous-integration hygiene to the reconciler, routine
approvals to the approval engine, reporting shape to the decision-packet
renderer, judgment to leaf skills run on a fresh model with the evidence
attached, taste and trust to written rules that stay. A rule leaves prose only
when its code home's tests have landed and a check proves the code refuses what
the rule forbade; until then both exist. The rule-enforcement field (REQ-H1.5)
makes the state measurable.

**Alternatives considered:**
- Delete prose rules as each slice lands. Rejected because: a rule deleted on
  the strength of code nobody has seen refuse leaves a window with neither.
- Keep all prose rules forever. Rejected because: the rule load itself lowers
  adherence; the memo's diagnosis.

**Chosen because:** retirement against a check is the only form that cannot
lose a protection, and it makes progress countable.

### D-3: Policy is data in layered catalogs with schemas; the floor is tighten-only (N)

**Decision:** Allow-lists, classes, limits, landing order, ranks, windows and
merge reach are YAML catalogs resolved through the existing catalog and
configuration resolvers (core seed, adopter, repository-tracked, machine-local),
each with a schema checked in CI and at load. An invalid entry is dropped from
its layer and the lower layers stay in force, except that an invalid value that
bounds a class makes the class refuse everything. The approval floor ships as
data no layer can loosen, and a layer entry that allows a floor act fails the
schema check. Scalar limits stay in `config/defaults.yml` with the options
reference; list-shaped policy (classes, ranks, order) is catalog data. Every
verdict records the policy digest, and `explain` names the supplying layer.

**Alternatives considered:**
- Policy in code with a few knobs. Rejected because: the operator's ask is that
  policy is data, and code-path policy is what makes each fix a pull request.
- A new bespoke config format. Rejected because: the catalog resolver already
  gives layering, supersede-by-id and explain; a second merge contract is a
  second place to be wrong.
- Let overlays remove floor entries. Rejected because: a machine-local file a
  session can write would then control the one list that must hold.

**Chosen because:** it reuses a tested merge contract, keeps tunables in one
place, and makes narrowing safe by construction.

### D-4: Three verdicts, fail-closed, and a deny always carries a message (N)

**Decision:** The engine returns `allow`, `deny` or `defer`. `allow` needs a
class and rule that name the request in full; `deny` is reserved for the floor
and carries a message naming the floor entry (a bare deny ends a streaming
worker's session); everything else, including every unreadable, unknown or
ambiguous input, is `defer`, which raises the event as today. An invalid policy
or an engine error is a `defer`. No verdict is produced by a model, and a model
classifier never sits in the approval path.

**Alternatives considered:**
- Two verdicts, allow and defer, with floor acts simply deferred. Rejected
  because: a floor act then costs a model turn every time, and the floor's
  count (REQ-C1.8) is the signal that a rule is too tight.
- Default-allow with a deny list. Rejected because: an enumerated deny list
  fails open on the next unlisted shape; the memo's rule is that the engine
  approves only what the allow-list names.

**Chosen because:** it matches the established approval-hook posture (allow
only the known-safe, defer the rest) and keeps the one irreversible class,
floor acts, out of any allow path.

### D-5: The engine is a pure function behind a language-neutral contract (N)

**Decision:** The engine and the dedupe gate are each one verb with a
structured stdin record, a structured stdout verdict and fixed exit codes. The
engine reads the request, the resolved policy and a read-only state snapshot
and writes only the decision log. Fixtures are data files, not tests written in
the implementation's language, so the implementation can be shell or a compiled
tier without touching a fixture. Matching is on the argument vector after
quote-aware splitting; a construct the matcher cannot fully read defers.

**Alternatives considered:**
- Embed the policy in the worker command guard. Rejected because: that guard
  answers a worker's own request at the worker; the engine answers at the event
  source for a supervising session. They share a classification (REQ-C1.10),
  not a process.
- Match on regular expressions over the command text. Rejected because: it is
  the false-allow class the adversarial suites keep finding.

**Chosen because:** purity makes the near-miss fixtures a complete test, and a
neutral contract keeps the language question (D-16) from blocking the slice.

### D-6: Classes ship in shadow; the operator's configuration moves them to enforce (N)

**Decision:** Each class carries `mode: off | shadow | enforce`, shipped as
`shadow`. In shadow the engine records its verdict beside the actual answer and
answers nothing. Enforcement is the operator's configuration of a class, taken
when the shadow log shows agreement and no near-miss allowed. The hub reads
each class's shadow log and brings the operator a one-line evidence summary
(would-have answers against actual answers, and each mismatch); that summary is
the gate for the operator's yes, so the operator reads no log. Every class,
`release-run` included, ships in shadow, and the `host-act` register ships
empty. Settled at kickoff (operator, 2026-11-16).

**Alternatives considered:**
- Ship the read-only class enforced. Rejected because: a first run in
  enforcement is the one with no evidence; an engine that has never been
  compared with a real answer has not been measured.
- Enforce by default and rely on tests. Rejected because: the memo's measure
  the claim rule asks for evidence before reliance.

**Chosen because:** it spends one observation window to buy the evidence that
lets enforcement be a decision rather than a hope, and the operator keeps the
authorization.

### D-7: Near-miss fixtures are data, and the check is shown to fail (N)

**Decision:** Every class has a fixture directory of `allow` and `near-miss`
requests with their expected verdicts. A check fails when a shipped class has no
near-miss fixture, when a fixture's verdict differs, and, in its own
self-test, when a rule is deliberately widened and the near-miss does not
fail. Fixtures are written before the rule they test (test-first), and the
engine and reconciler are registered in the guard catalog as safety-relevant.

**Alternatives considered:**
- Unit tests per rule only. Rejected because: they show a rule allows what it
  should, not that the next-nearest request is refused.
- Rely on review to catch widening. Rejected because: a check that has never
  failed measures nothing.

**Chosen because:** the safety claim of an allow-list is the refusals around
it, and only a failing fixture proves the check can see one.

### D-8: Dedupe at the source; failure is asymmetric (N)

**Decision:** One gate sits where an event is appended. It keys by kind,
subject and state version with a per-subject sequence, drops a repeat, a stale
event or an off-order event, counts each drop by reason, never drops the first
occurrence of a decision, blocker, failure or landed event, coalesces routine
events into one wake per window, and delivers any event whose state it cannot
read. A gate that drops a large share of a class raises its own event.

**Alternatives considered:**
- Dedupe in the consuming session. Rejected because: the cost is the turn the
  event wakes; a drop after the wake saves nothing.
- Fail closed (drop on doubt). Rejected because: a missed decision or blocker is
  the worst outcome here, where a spurious wake is a cost, not a loss.

**Chosen because:** an event dropped before any session sees it is the cheapest
saving, and an asymmetric failure rule keeps the gate's errors on the harmless
side.

### D-9: The claim is measured against a machine-local baseline (N)

**Decision:** Task 1 records the baseline (turns per day by role, spend split,
merges per day, operator interruptions) in machine-local data, with a method
document committed and no figures. Each slice names the one number it moves
and records the measured change at landing; an unmoved number reopens the
design.

**Alternatives considered:**
- Commit the baseline figures. Rejected because: they are machine content and
  would age; the method is what reproduces.
- Skip measurement and judge by feel. Rejected because: the diagnosis is a
  cost claim, and a cost claim is checkable.

**Chosen because:** it keeps the build honest about its own premise and keeps
machine data out of the repository.

### D-10: Merge mode reuses the existing policy values and adds only a reach (N)

**Decision:** Merge mode is data defaulting to the operator merging. It reuses
the existing merge policy values and adds one reach value (merge only, or merge
and publish a release), which takes effect only in an operator-owned repository
with no other person working in it, never for a spec pull request, a pull
request with an open sign-off item, or a merge that needs a bypass. It is read
only from the shipped and adopter layers. The reconciler prepares and reports
merge-ready and merges only where configured, each merge a recorded act
re-checked at its last step.

**Alternatives considered:**
- A separate auto-merge key. Rejected because: it creates a second authority
  next to the existing merge policy.
- Allow the machine-local layer to set the reach. Rejected because: a file a
  session can write would control the least reversible act.

**Chosen because:** it honors "defaults to operator merges, a class may allow
more" with one authority and the narrowest reach.

### D-11: The queue is a rebuildable cache of forge and git evidence; the dispatcher reads it (N) — outline

**Decision:** One store holds a row per unit and pull request, written only by
scripts, format-versioned and lock-protected, derived from branch, pull request
and merge evidence so a lost store is rebuilt. The dispatcher admits or refuses
a launch from the rows and the policy (landing order, work-in-progress limit,
host ceiling, ranks), and every launch goes through one seam that applies the
environment pins, resolves the fleet home once and verifies the worker's branch
against the row. Open for its design walk: the row schema, the lock and rebuild
mechanics, how it relates to the existing operator queue and orchestration
marker, and cross-spec edges (D-17).

**Alternatives considered:**
- Make the store the authority over pull request state. Rejected because: the
  forge is the authority; a cache that disagrees must lose.
- Extend the existing operator queue. Rejected because: that queue orders what
  the operator is owed, not what workers do; the walk decides whether they share
  a store.

**Chosen because:** it removes state from session context without creating a
second source of truth.

### D-12: The reconciler is a level-triggered loop of idempotent verbs (N) — outline

**Decision:** The reconciler reads queue state and the forge, and applies the
next idempotent verb for each row (sync, start or cancel checks, flip, retire,
record evidence, relabel), so a repeated or interrupted pass converges. A
host-level poller feeds it by diff and writes an event only on a change.
Evidence comes from machines (continuous integration, hooks), and a record the
recorder cannot establish is refused. Open for its design walk: the verb set's
order, the poller's host mechanism on each platform, and which existing
scripts it wraps.

**Alternatives considered:**
- Edge-triggered handlers per event. Rejected because: a missed or duplicated
  event then corrupts state; a level-triggered pass heals.
- Keep landing steps in supervising sessions. Rejected because: that is the
  failure the memo diagnoses.

**Chosen because:** idempotent, level-triggered verbs are the form that cannot
be left half-done by a crash, which is the property the control plane needs.

### D-13: Slices two to four are specified as outlines and each is walked before build (N)

**Decision:** The bundle carries slice one in full and slices two to four as
requirements, a design outline and task stubs. Each later slice starts with a
design walk task whose output amends the bundle through the amendment ritual,
turning the outline into full requirements; no build task of a slice is
dispatched before its walk task is complete. The slice's landing records the
measured change (REQ-E1.2).

**Alternatives considered:**
- Draft all four slices in full now. Rejected because: the later slices depend
  on what slice one measures; specifying them in detail now is the speculative
  design the memo warns against.
- Four separate specs. Rejected because: the operator chose one spec built and
  walked one slice at a time, and the slices share one policy model.

**Chosen because:** it keeps the whole shape visible and reviewable while not
committing detail the evidence has yet to inform.

### D-14: One kill switch restores today's behavior (N)

**Decision:** A single setting turns the control plane to defer everything:
the engine answers nothing, the gate delivers everything, the dispatcher
admits as today. Every verb reads it first, and the setting is readable from
the machine-local layer because turning the control plane off only narrows it.

**Alternatives considered:**
- Per-component switches only. Rejected because: in a fault the operator needs
  one act, not four.

**Chosen because:** a control plane that cannot be turned off is a risk of its
own, and off is the safe direction.

### D-15: Machine specifics live in overlays; the design is one for every machine (N)

**Decision:** Paths, tracker and chat names, thresholds and tiers are overlay
policy data; the core catalogs and fixtures carry none. The work machine adopts
slice by slice by the same files, and no work content enters this repository:
its asks are cited by drop number and described by capability only.

**Alternatives considered:**
- A work-machine variant. Rejected because: two designs double the policy
  surface and the work machine's asks map onto the same slices.

**Chosen because:** one design serves both, and the data-hygiene rule holds.

### D-16: Implementation language — shell now behind a neutral contract, swap later (N)

**Decision:** Settled at kickoff (operator, 2026-11-16). Slice one is written in
the shell the plugin already uses, behind the language-neutral contract
(REQ-I1.3, D-5), so a later rewrite changes no fixture or policy file. The
universal-binary verdict draft (pull request 1063, pending) recommends Go for
the library and skill-called tiers; this spec does not choose, and the engine
and gate adopt whatever that amendment decides.

**Alternatives considered:**
- Decide Go in this spec. Rejected because: the verdict is a draft in another
  amendment and a second authority would conflict with it.
- Always shell. Rejected because: the universal-binary spec records why the
  shell layer's defects cluster in the primitives this engine needs (parsing,
  locks, process cost).

**Chosen because:** a neutral contract lets slice one proceed while the
language question is settled where it belongs.

### D-17: Cross-spec dependencies and a refused-push rename (N)

**Decision:** Settled at kickoff (operator, 2026-11-16). Edges cross specs only
within the same spec root; only hard edges, written `<spec>:<id>`; the
validator warns on a prose-form edge and never rewrites it; selection fails
closed when the foreign bundle cannot be read; the amendment that owns the edge
syntax bumps the format version (the local branch to the invariant-tasks spec).
The queue (REQ-F1.2) reads a hard cross-spec edge under those rules. A refused
push whose message names the branch the helper accepts, when that branch does
not exist, is renamed to it and retried (REQ-G1.7), with these limits: only to
the exact name the refusal names, recorded, through the same guarded helper,
never with force, never to a protected or shared branch, and at most once per
refusal.

**Alternatives considered:**
- Allow edges across spec roots. Rejected because: the foreign bundle may not
  be readable on the machine, and the rule fails closed.
- Rewrite prose edges automatically. Rejected because: a rewrite changes
  signed content.

**Chosen because:** it keeps the queue's dependency read small and safe; the
format change itself lives in the invariant-tasks amendment.

### D-18: Main work and side work — hold with a lapse (N)

**Decision:** Settled at kickoff (operator, 2026-11-16). While a
higher-ranked unit is ready, the dispatcher holds a lower-ranked launch and
the hold lapses after an hour into a picklist for the operator; alert-and-launch
was the rejected alternative. Source: the local main-work amendment
(Amendment 14, question one). The hold and its lapse are policy data
(REQ-B1.5).

**Alternatives considered:**
- Alert only. Rejected as the default because: an alert asks the operator to
  police a limit that code can hold, and the pile-up that triggered this spec
  is the alert-only outcome.

**Chosen because:** the hold is the code-enforced form of the focus rule, and
the lapse stops it becoming a deadlock.

### D-19: Slice one covers the kinds of request that dominate approvals (N)

**Decision:** Beyond reads, own-branch pushes and bot replies, slice one ships
`test-run`, `lint-run` and `evidence-and-wait` classes (REQ-C1.11), each bound
to the worker's own worktree, each in shadow with near-miss fixtures. Slice one
is built first, and within it the approval engine follows the policy data task
directly; the baseline and the dedupe gate run beside it, not ahead of it.

**Alternatives considered:**
- Cover them through the `host-act` register of exact commands. Rejected
  because: the operator would maintain a list of commands that a class with a
  scope predicate describes once.
- Leave them to a later slice. Rejected because: the approval record shows
  them, with reads, to be nearly all of the roughly 1,100 daily requests and
  about 36 waiting hours.

**Chosen because:** the first slice should remove the bottleneck it was named
for, not only its easiest part.

### D-20: A program reads each repository's own spec root through one verb (C, mission-control D-100 to D-103)

**Decision:** Folded from Amendment 19 by the operator's ruling. With the
program's root unset, each listed repository's root is what the spec-root
resolver answers there, so no map or registry is added; a set root wins and
leaves every old configuration byte-identical. One program reader verb returns
each root with its repository, and a check fails on any other read of the root
field. An ambiguous spec name is refused until qualified by a repository alias,
the one thing taken from the work-repository registry. The queue (D-11) is the
reader that needs it.

**Alternatives considered:**
- Keep it a separate mission-control change. Rejected because: the operator
  folded it here, and the queue is its main consumer.
- A map from repository to root. Rejected because: it silently disagrees with
  the repository's own answer.

**Chosen because:** the root a session uses and the root the program reads
cannot differ, with no flag day.

### D-21: The panel reads from the queue; its changes are drafts until seen (C, mission-control D-85 to D-89)

**Decision:** Folded from Amendment 18 by the operator's ruling, as outlined
requirements for the last slice (REQ-H1.6 to REQ-H1.9) with its own design walk
before any build: titles in place of identifiers, all work in motion with age
and a fixed-vocabulary current step, an instrument and fuel-bar row, spend and
budget, spec progress, accessibility and a CI type check. The panel reads queue
rows rather than separate digests where the queue holds the fact. The standing
condition travels with it: a panel change stays a draft until the operator has
seen a screenshot of the real panel and said yes.

**Alternatives considered:**
- Keep it a separate mission-control change. Rejected because: the operator
  folded it here; most of what the panel shows is queue state.
- Build the panel before the queue. Rejected because: it would read a second
  copy of state the queue is to hold.

**Chosen because:** the panel is the operator-facing render of the state this
spec moves into code.

## Cross-cutting concerns

### The open-issue map

Each open issue the control plane can address is mapped to a requirement or
given a stated out-of-scope reason. The list is a snapshot of the open issues
on the drafting date; the rule is that a later-opened issue joins by the same
test (does a code home in this spec close it?).

| Issue | Disposition |
| --- | --- |
| 88 (dispatch record is branch plus marker) | REQ-F1.2: the queue derives from that evidence. The text amendment to the Done concurrency spec stays out of scope (a Done spec's wording is its own amendment). |
| 93 (status header excluded from the content anchor) | Out of scope: an anchor-format migration in the kickoff-lifecycle domain, not control-plane state. |
| 137 (ledger check against the leave-untouched stamp) | Out of scope: concerns version-one completion annotations, which the version-two ledger has no home for. |
| 173 (release helper does not relabel the release pull request) | REQ-G1.5: the reconciler advances the label after a publish. |
| 341 (offload tmux launch skips the environment pins) | REQ-F1.4: one launch seam applies the pins. |
| 342 (offload offers rungs it cannot dispatch for a petition) | REQ-F1.2: a petition is a queue unit kind the launch seam can dispatch. |
| 343 (parallel units share a test database and migration counters) | Out of scope: per-project resource isolation is a stack concern, not control-plane state; a resource-claim field on the row is a candidate for the queue's walk. |
| 379 (ready flip as policy) | REQ-G1.1: the reconciler flips under the existing ready-flip policy, once every check has finished. |
| 380 (a release can be silently dropped) | REQ-G1.5: the reconciler raises an event on a dropped or unreleased release; the window-lock design stays with release-hardening. |
| 383 (named lifecycle states and operator hooks) | REQ-F1.5. |
| 384 (sign-off at the merge as a trailer) | Out of scope: sign-off is a gate and stays the operator's; this spec adds nothing near it. |
| 385 (polish's local-only wording) | Out of scope: a skill-composition wording matter. |
| 388 (a rejected sign-off item double-counted) | Out of scope: sign-off marker mechanics. |
| 391 (comment volume) | Out of scope: code-hygiene, separate from control-plane state. |
| 393 (review sequence cannot reach outside skills) | Out of scope: review-skill reachability, a leaf-skill matter (REQ-A1.6). |
| 544 (flight record fails a lint on long quoted lines) | Out of scope: a flight-record formatting matter. |
| 545 (fleet home unresolved from a tower shell) | REQ-F1.4: the launch seam resolves the fleet home once. |
| 547 (a flight worker commits to a harness-created branch) | REQ-F1.4: the seam verifies the worker's branch against the row. |

### The closed drafts, and where they land

Each closed draft's behavior is a requirement of the slice that needs it, not a
separate build. The approval-answer drafts and the answer-owner draft frame
REQ-C; the denial-friction draft REQ-C1.5 and REQ-C1.8; the auto-merge draft
REQ-B1.7 and REQ-G1.5; the records, step-timeout, context-reading, duties and
adoption drafts REQ-G and REQ-H1.1; the admission draft REQ-F1.3; the goals
draft REQ-F1.6; the rule-enforcement, platform-class and cadence-line drafts
REQ-H. Their code is not carried: each slice's task re-implements the behavior
against the queue and policy data where its design walk says so, citing the
closed draft as a source.

### Existing parts the slices wrap

About half the parts exist as scripts (the launcher and registry, the event
runner and its event classes, the stall watcher, the readiness and merge-ready
checks, the conflict radar, the worker and tower guards, the ready-flip helper
and the orchestrator's selection). The slices add the missing core around them;
a slice's walk names which it wraps and which it replaces.

### Data-hygiene and security

The approval engine is authorization code over untrusted input (a worker's
command): the write-time security pass for untrusted input, subprocess
construction, path handling and authorization applies to every slice-one task.
The decision log and drop ledger hold identifiers, digests and bounded strings
only (REQ-I1.4).

## Open kickoff questions

All settled at kickoff by the operator, 2026-11-16 (see the changelog in
`requirements.md`): cross-spec dependencies and the refused-push rename (D-17),
main versus side work (D-18), the language (D-16), class modes with the hub
reading the shadow log (D-6), and the `release-run` class in shadow (REQ-C1.3).
None remains open.
