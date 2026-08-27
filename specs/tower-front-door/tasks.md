# Tower front door — Tasks

**Status:** Draft
**Last reviewed:** 2026-08-27
**Format-version:** 2
**Execution:** derived — see the status render

Twelve tasks in dependency order. The eval task deliberately gates the
docs task (D-13): no doc surface claims routing behavior the router has
not demonstrated.

## Tasks

### Task 1 — Flight-rules doctrine doc

- **Deliverables:** `doctrine/flight-rules.md`: the per-request routing
  rule (automatic, judgment, and advisory signals; stated grounds; the
  one-sentence two-way override with stated reservation), the audit-record
  content contract and specless-traceability definition, and the
  bounded-or-surfaced statement of the survival guarantees.
- **Done when:** the doc resolves through the rule-doc chain; every rule
  in it cites this bundle's D-IDs; the word-budget guard passes with the
  doc enrolled.
- **Dependencies:** none
- **Citations:** D-1, D-4, D-5, D-6, D-10 · REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-E1.1, REQ-E1.4, REQ-F1.6
- **Estimated effort:** 1 day

### Task 2 — Vocabulary inversion, definitional sites

- **Deliverables:** the glossary supersession in
  `doctrine/spec-format.md` (Tower re-defined, Orchestrator minted, the
  transitional note), the consumer-naming update in
  `doctrine/work-placement.md`, and the opening-vocabulary update in
  `docs/fleet.md`; a dated meta-spec changelog entry (no version bump —
  no authoring rule changes).
- **Done when:** the three definitional sites use the new vocabulary; the
  transitional note is present; lint and the word-budget guard pass.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-H1.1, REQ-H1.2, REQ-H1.4
- **Estimated effort:** half day

### Task 3 — Flight branch and worktree grammar

- **Deliverables:** the additive spec-format grammar amendment for
  `planwright/flight/<flight-id>` and the `flight-<flight-id>` worktree
  suffix; `flight` reserved against spec identifiers in the validator's
  screening; the flight-id format (kebab slug plus short uid) defined;
  the `specs/_flights/` record directory classified
  (underscore-screened, skipped by bundle validation); branch-parser
  cases added where `planwright/` branches are parsed.
- **Done when:** a flight branch parses everywhere a task branch parses;
  a spec named `flight` is refused by the validator; unit tests cover the
  new grammar cases.
- **Dependencies:** none
- **Citations:** D-11 · REQ-C1.1
- **Estimated effort:** half day

### Task 4 — The `/tower` skill core

- **Deliverables:** `skills/tower/SKILL.md`: session bring-up (posture
  check, start-of-session reconstruction hook point), the router with
  stated grounds, the two-way override, the conversational contract per
  the operator-dialogue disciplines, and the escalation/offer language;
  the description authored as a selector; the skill enrolled in the
  instruction-budget guard.
- **Done when:** the skill invokes clean in a fresh session; routing
  statements carry grounds on every route; the budget guard passes with
  the new surface enrolled.
- **Dependencies:** 1, 2
- **Citations:** D-1, D-3, D-4, D-5, D-15 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-B1.1, REQ-B1.3, REQ-B1.4, REQ-D1.2, REQ-D1.3, REQ-D1.4
- **Estimated effort:** 2 days

### Task 5 — Visual-flight dispatch path

- **Deliverables:** the flight dispatch flow: worktree and branch
  creation through the sanctioned primitive using the Task 3 grammar,
  rung selection through `/offload`'s placement logic and the backend
  seam, and the worker brief carrying doctrine load, the configured
  `review_sequence`, and the audit-record instructions.
- **Done when:** a small ask dispatches end-to-end into an isolated
  worktree worker that converges and lands a draft PR; no placement
  logic exists outside the `/offload` seam.
- **Dependencies:** 3, 4
- **Citations:** D-7, D-11 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 1 day

### Task 6 — Flight record and PR body

- **Deliverables:** the flight record template implementing the REQ-E1.1
  content contract on the existing PR-body conventions; the adaptive-home
  selection (PR body with remote and `gh`; the committed per-flight
  record file at `specs/_flights/<flight-id>.md` on the flight branch
  otherwise), declared at routing time.
- **Done when:** both arms produce the full content contract; the
  no-remote arm commits exactly one record file on the flight branch;
  template structure is unit-tested.
- **Dependencies:** 1, 5
- **Citations:** D-6 · REQ-E1.1, REQ-E1.2, REQ-E1.4
- **Estimated effort:** 1 day

### Task 7 — Shared flight sweep and derived index

- **Deliverables:** one sweep implementation (script) deriving in-flight
  state from durable evidence (flight branches, PRs, worker liveness
  including backend runtime evidence, record files); the derived
  never-committed index under the fleet home; tower start-of-session
  sweep wiring.
- **Done when:** deleting the index and re-sweeping reproduces it; a
  fresh tower session reports what landed and what is queued from
  evidence alone; the sweep consults backend liveness before declaring a
  flight dead.
- **Dependencies:** 3, 6
- **Citations:** D-9 · REQ-E1.3, REQ-F1.3, REQ-F1.4
- **Estimated effort:** 1 day

### Task 8 — `/resume` tower mode

- **Deliverables:** the tower-level sweep mode in `/resume`, consuming
  the Task 7 sweep implementation unchanged.
- **Done when:** `/resume`'s tower mode and the tower's start sweep
  render from the same implementation with no second derivation path.
- **Dependencies:** 7
- **Citations:** D-9 · REQ-F1.4
- **Estimated effort:** half day

### Task 9 — Attention integration and crash policy

- **Deliverables:** deterministic flight lifecycle pushes into the
  attention store (dispatch, awaiting-decision, completion with PR link)
  via hooks and scripts; decision-queue and status-on-demand rendering in
  the tower conversation through the existing fleet-attention seam;
  flight registration so the fleet crash-loop knobs cover flight workers.
- **Done when:** a flight completion reaches the queue with no tower
  polling in the loop; a killed worker follows backoff then surfaces at
  the disable threshold; the guarantees are stated bounded-or-surfaced.
- **Dependencies:** 5
- **Citations:** D-8, D-10 · REQ-C1.5, REQ-F1.1, REQ-F1.2, REQ-F1.5,
  REQ-F1.6
- **Estimated effort:** 1 day

### Task 10 — Tower posture extension

- **Deliverables:** the reviewed extension of the tower permission
  posture for chat-tower shapes (allow additions or guard shapes only);
  the deny floor untouched; the allow/deny delta documented for human
  sign-off.
- **Done when:** the tower's routine flow runs without stochastic
  classifier stalls; the deny floor is byte-identical or strictly wider;
  guard tests assert zero false-allows on the new shapes.
- **Dependencies:** 4
- **Citations:** D-14 · REQ-A1.3, REQ-G1.1, REQ-G1.4
- **Estimated effort:** 1 day

### Task 11 — Routing behavioral eval

- **Deliverables:** eval fixtures derived from the five acceptance
  scenarios (chat-only, split-screen, refusal to merge, escalation,
  walk-away/resume), asserting route choice, stated grounds, override
  compliance with stated reservation, and the merge refusal.
- **Done when:** the fixtures run on the behavioral-eval harness and the
  router passes; the harness-operability caveat is recorded where the
  suite is wired.
- **Dependencies:** 4
- **Citations:** D-13 · REQ-B1.2, REQ-B1.5, REQ-B1.6, REQ-G1.1
- **Estimated effort:** 1 day

### Task 12 — Docs inversion

- **Deliverables:** README and getting-started led by `/tower`; the
  demotion moves (`/orchestrate`, `/execute-task`, `/resume`, `/offload`
  to advanced/architecture docs under existing names); the front-facing
  set unchanged; the two permanent human controls restated as unchanged
  on both flight rules; the first-use flight-rules gloss on each touched
  surface.
- **Done when:** a newcomer path exists that never names internal
  machinery; doc-drift tethers and lint pass; no demoted skill is
  renamed.
- **Dependencies:** 2, 4, 11
- **Citations:** D-2, D-3 · REQ-H1.3, REQ-H1.4
- **Estimated effort:** 1 day

## Awaiting input

- (none yet)

## Deferred

- **User-history / trust-ramp routing.** Static signals suffice to prove
  the routing; history adds statefulness and a where-does-it-live
  question. Confidence: high.
  **Gate:** operational evidence from real flights shows the static rule
  misroutes often enough to justify stateful history (surfaced free-text
  condition, evaluated at drain).
  Citations: D-4 · the tower-front-door seed (Sources).
- **Existing-skill renames.** Renames change the published command
  surface mid-review; the naming decisions themselves stay open until
  the review outcome is known. Confidence: high.
  **Gate:** the pending marketplace review of the plugin concludes
  (surfaced free-text condition, external event).
  Citations: D-2 · the tower-front-door seed (Sources).
- **The pervasive vocabulary prose sweep.** The definitional sites plus
  the transitional note carry v1; the full fleet-doc re-terming waits
  until the new vocabulary has been exercised. Confidence: medium.
  **Gate:** the Task 2 definitional sites are merged and no
  transitional-note confusion has been observed in use (surfaced
  free-text condition).
  Citations: D-2 · REQ-H1.2.

## Out of scope

- Multi-repo / cross-repo tower (one tower per repo checkout in v1).
- Fleet-mode integration beyond seam reuse: no supervision of spec-mode
  orchestrators, no `--meta` fold-in.
- Persistent flight memory beyond the audit trail (preference learning,
  style adaptation).
- Any change to sign-off or merge semantics.
