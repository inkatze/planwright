# Tower front door — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-01
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (grammar, sweep, guard,
record-template, and budget checks run by `mise run check` and the repo
CI; behavioral-eval fixtures on the plugin eval harness, whose
operability caveat is recorded at Task 11), `[Gherkin]` for the five
acceptance scenarios, `[manual]` for the demo script (a Task 13
deliverable) and conversational posture, `[design-level]` where an
artifact's existence and coverage is the verification. Eval-backed
`[test]` entries run on the eval harness outside the repo CI — the
standing `check-no-ci-evals.sh` guard structurally keeps evals out of
CI — and are exercised on demand, not on the merge gate.

## REQ-A — The entrance

### REQ-A1.1 — One conversational front door [Gherkin + manual]

Scenario (chat-only demo): given a small, safe ask in plain language,
when the tower routes and dispatches, then the user's next interaction
is a draft-PR link, no spec file was created, and no pipeline machinery
was named in the conversation (the flight-rule words with their gloss
are permitted, per REQ-A1.1). Manual: the demo script exercises the same
flow live.

### REQ-A1.2 — Tower frugality [manual]

Reviewed against the work-placement axiom during the demo runs: heavy
ingestion (diffs, sweeps, reviews) is observed dispatching to workers;
inline turns stay at reasoning plus bounded state checks.

### REQ-A1.3 — Posture floor [test]

Guard tests (Task 10) assert the extension adds allow shapes only and
the deny floor is unchanged or strictly wider; zero false-allows on the
new shapes by construction.

### REQ-A1.4 — Primitives only [design-level]

The shipped implementation consists of skills, hooks, scripts, and
file-based state; the review confirms no second framework or daemon
beyond the fleet layer's existing definitions.

### REQ-A1.5 — The window, without supervision [manual + design-level]

Demo: mid-orchestration, asking the tower about that spec's status
yields an on-demand answer from durable evidence with no machinery
knowledge required; review confirms no code path polls or renders
spec-mode execution unprompted.

## REQ-B — The router

### REQ-B1.1 — Flight rules per request, never modes [test + design-level]

Eval fixtures include consecutive asks of different stakes in one
session routing differently with no mode state; the skill text contains
no mode flag or persistent setting.

### REQ-B1.2 — The escalation rule [test + Gherkin]

Scenario (escalation demo): given two asks back to back, when the small
one is routed, then it flies visual; when the ask centered on an auth
boundary is routed, then the tower produces the one-page case and a spec
draft. Eval fixtures cover a zone ask, an irreversible-beyond-zones ask,
an ambiguous ask, and a large-but-safe ask (which must NOT auto-file on
size alone).

### REQ-B1.3 — Grounds stated [test]

Every eval fixture asserts the routing statement names the route and its
grounds; a fixture with a silent route fails.

### REQ-B1.4 — One-sentence override [test]

Fixtures: "just do it" on a zone-triggered ask flies visual with a
stated reservation; "write this one up" on a trivial ask files; an
override attempting to cross a hard invariant (a merge request) is
refused.

### REQ-B1.5 — Hard pauses regardless of route [test]

An overridden zone ask dispatched visually still hard-pauses in the
worker on the zone finding (asserted against the gate-wiring pause
behavior in the dispatch-path tests).

### REQ-B1.6 — Eval gates the docs [design-level]

Task 12 depends on Task 11 in `tasks.md`; the dependency edge is the
verification that no user-facing doc claim precedes the passing gate
(doctrine and skill text state the routing rule as law, which the
rescoped REQ permits ahead of the eval).

## REQ-C — Visual flight

### REQ-C1.1 — Flight branch and worktree isolation [test]

Unit tests (Task 3): the flight grammar parses everywhere task branches
parse; two concurrent flights never collide; a spec named `flight` is
refused by the validator.

### REQ-C1.2 — Placement through the existing seam [test + design-level]

Dispatch-path tests stub the backend seam and assert rung selection is
delegated to the `/offload` placement logic; review confirms no second
placement implementation exists.

### REQ-C1.3 — Convergence with declared scoping [test + manual]

Dispatch tests assert the worker brief carries the configured
`review_sequence`; manual review of flight audit records confirms any
rigor scoping is declared, never silent.

### REQ-C1.4 — Always a draft PR [test + Gherkin]

Scenario (split-screen demo): given a second pane on `.claude/worktrees/`,
when a flight runs, then the worktree appears, the worker converges, and
a draft PR opens. Tests assert the PR is created draft and never flipped
by the tower.

### REQ-C1.5 — Governed parallelism [test]

Dispatch tests assert a flight beyond the existing `max_parallel_units`
value is declined at dispatch with a stated re-ask path — no durable
queue, no new store, no new knob — and that a freed slot makes the
re-asked flight dispatchable.

### REQ-C1.6 — Flight boundary [test + design-level]

Dispatch tests assert a read-only offload creates no flight branch,
worktree, draft PR, or record and returns its result to the
conversation; that a mid-offload mutation need returns as a new routed
request; and that a decomposed ask yields one routed flight per unit.
The flight-rules doctrine doc states the boundary (mutating work only),
and review confirms no code path mints flight identity for read-only
work.

## REQ-D — Instrument flight

### REQ-D1.1 — Escalation through /spec-draft [Gherkin]

Scenario: given an ask that files, when the tower escalates, then the
spec bundle is produced by the existing `/spec-draft` machinery with
fold-detection run (an overlapping existing spec yields an extend
recommendation, not a duplicate bundle).

### REQ-D1.2 — The one-page case [manual]

The escalation demo's filing case is reviewed against the seed's
contract: why this ask files, in one page, before any kickoff offer.

### REQ-D1.3 — Kickoff offered, never started [test + Gherkin]

Scenario: after drafting, the tower offers `/spec-kickoff` and stops; an
eval fixture asserts no kickoff activity occurs without the human
starting it.

### REQ-D1.4 — Orchestration on explicit go only [test]

Fixtures: sign-off completion alone triggers no dispatch; the spec PR's
merge alone triggers no dispatch; an explicit "go" dispatches through
the existing machinery.

## REQ-E — The audit record

### REQ-E1.1 — The content contract [test + manual]

Template unit tests assert every contract element (ask, route and
grounds, audit tables, declined log, pending-sign-off checklist, any
rigor scoping applied, worker handle, revert path) is present; manual PR
inspection on the demo flights.

### REQ-E1.2 — Adaptive home, declared [test]

With a stubbed remote, the record lands in the PR body; with none, the
flight branch carries exactly one committed record file at
`specs/_flights/<flight-id>.md`; both arms emit the declared-home
statement at routing time.

### REQ-E1.3 — Derived index is cache [test]

Delete-and-resweep reproduces the index equivalently (stable
serialization; timestamps excluded) from evidence; the index path is
never tracked; no code path treats the index as authoritative over git
or forge evidence.

### REQ-E1.4 — Specless traceability [design-level]

The flight-rules doctrine doc states the definition (ask, route and
grounds, evidence, revert path), and the record template implements it;
existence plus the REQ-E1.1 tests are the verification.

### REQ-E1.5 — Human-first record rendering [test + manual]

Template unit tests assert, in both homes, that the lead carries no
restated prompt and the collapsed section carries every REQ-E1.1
contract element with the ask sanitized and markup-neutralized (an ask
containing a fence or closing tag cannot break the collapse or the
sweep's parse); manual review of demo-flight PRs confirms the lead reads
as a human author's what/why/verification.

## REQ-F — Attention and survival

### REQ-F1.1 — Decision-queue posture [manual + test]

Attention tests assert only actionable items and lifecycle events are
pushed; the demo runs confirm status is available on demand and each
completion reports its landing reference (PR link, or branch and record
path on the no-remote arm).

### REQ-F1.2 — Deterministic push [test]

A flight completion reaches the attention store with the tower process
stopped (no polling in the loop); the push originates from hooks and
scripts.

### REQ-F1.3 — Work survives the tower [Gherkin]

Scenario (walk-away demo): given a flight in the air, when the tower
session is killed, then the worker keeps flying and the worktree,
branch, and record remain.

### REQ-F1.4 — Reconstruction, one sweep [test + Gherkin]

Scenario continued: a fresh tower session reports what landed and what
is queued, from durable evidence alone. Tests assert `/resume`'s tower
mode and the tower start sweep call the same implementation, and that
the sweep consults backend liveness before declaring a flight dead.

### REQ-F1.5 — Crash policy inherited [test]

A killed worker relaunches under the fleet backoff knobs and surfaces to
the human at the disable threshold, using the existing fleet mechanisms.

### REQ-F1.6 — Bounded-or-surfaced [design-level]

The doctrine doc and every guarantee-bearing surface state the
bounded-or-surfaced form; review confirms no absolute survival claim
ships.

## REQ-G — Hard invariants

### REQ-G1.1 — Never auto-merge [test + Gherkin]

Scenario (refusal demo): "looks good, merge it" is declined
conversationally with the reserved-control statement and the PR link
handed back. Guard tests assert the merge deny rules hold under the
tower posture.

### REQ-G1.2 — No shadow sign-off [design-level]

Review of the shipped flow confirms the specless path contains no
sign-off-like gate and the spec path's sign-off is unmodified; no bypass
flag exists in any shipped surface.

### REQ-G1.3 — New commits only [test]

Guard tests (Task 10) assert force-push, amend, squash, and rebase
remain denied under the tower and worker postures (the deny rules are
branch-agnostic, so flight branches are covered by construction).

### REQ-G1.4 — Drafts always [test]

PR creation on both paths is asserted draft; the ready-flip deny holds
under the tower and worker postures; the kickoff spec-PR exception is
untouched by this bundle (asserted by absence of change to that flow's
tests).

### REQ-G1.5 — Seams reused [design-level]

The design review walks the five named seams and confirms consumption,
not duplication; the two minted pieces carry their seam-misfit notes
(D-6, D-11).

## REQ-H — Vocabulary and docs

### REQ-H1.1 — Glossary supersession [test + design-level]

The Task 2 pin-check pins the glossary's Tower and Orchestrator entries,
the transitional note (older prose and tower-named scripts/config both
covered), and the Orchestrator-vs-Operator distinction line; the
meta-spec changelog entry exists with no version bump.

### REQ-H1.2 — Definitional sites only in v1 [design-level]

The Task 2 diff touches exactly the named sites; the prose sweep remains
a live Deferred entry with its gate.

### REQ-H1.3 — README leads with /tower [test + manual]

The Task 12 pin-checks pin the README lead, the demotion placements, and
the two-controls restatement; manual read of the newcomer path confirms
no pipeline machinery is required knowledge.

### REQ-H1.4 — Flight-rules naming and gloss [test]

Lint-level check: each doc surface introducing the flight rules carries
the one-sentence gloss at first use.
