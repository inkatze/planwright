# Kickoff Lifecycle — Tasks

**Status:** Draft
**Last reviewed:** 2026-06-26
**Format-version:** 1

Dependency view (derived; the `Dependencies:` lines are authoritative). Task 1
(meta-spec) is the root: the validator (Task 2), kickoff changes (Task 3), the
orchestration gate (Task 5), and the downstream renderers (Task 7) all key off the
six-status lifecycle it defines. Task 4 (spec-PR-ready) extends Task 3. Task 6 (the
derived reconcile) extends Task 5 and carries a **hard cross-spec dependency** on
`orchestration-concurrency` Task 1 (derivation engine) and Task 4 (single reconcile
writer). Task 8 (migration + docs) closes the bundle and depends on the validator
(Task 2), the kickoff/PR work (Task 4), and the reconcile (Task 6). The
human-gated and meta-spec/validator/docs path (Tasks 1–5, 7) does not depend on the
sibling spec and can land first; only Tasks 6 and 8 wait on it.

## Forward plan

### Task 1 — Meta-spec: six-status lifecycle + bootstrap supersede pointers

- **Deliverables:** `doctrine/spec-format.md` status table and transitions updated
  to Draft → Ready → Active → Done (Retired/Superseded terminal), with `Ready`
  defined ("signed off, validated, executable, no work started") and `Active`
  narrowed to "work in flight"; the validator-invariants section noting Ready
  errors-block; glossary updated. `bootstrap` `design.md` decisions D-40, D-44, and
  D-26 annotated `Superseded-by: kickoff-lifecycle D-1 / D-6 / (D-5 ritual)` per the
  supersede-pointer ritual, landed in this PR, with matching dated `## Changelog`
  entries in both bundles.
- **Done when:** `spec-format.md` lists six statuses with the Draft→Ready→Active→Done
  transitions and the Ready meaning; bootstrap D-40/D-44/D-26 carry the supersede
  pointers and changelog entries; nothing reopens bootstrap (its Status stays Done).
- **Dependencies:** none.
- **Citations:** D-1, D-5 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-B1.1
- **Estimated effort:** half day

### Task 2 — Status-aware validator recognizes Ready (errors-block)

- **Deliverables:** `scripts/spec-validate.sh` updated so `Ready` is a recognized
  status (status enum) and `Ready` findings map to errors-block severity alongside
  Active and Done; Draft→Ready and Ready→Active accepted as valid transitions;
  terminal-state discipline unchanged; header documentation updated. Tests in
  `tests/test-spec-validate.sh`: a Ready bundle with a structural error errors out
  (written failing-first); valid Draft→Ready and Ready→Active bundles pass; the
  unknown-status path is unchanged.
- **Done when:** the validator recognizes Ready and blocks execution on Ready
  findings; the new tests pass and the suite is green.
- **Dependencies:** Task 1.
- **Citations:** D-1 · REQ-B1.2, REQ-B1.3
- **Estimated effort:** half day

### Task 3 — `/spec-kickoff` flips Draft→Ready; change-handling scales by lifecycle stage

- **Deliverables:** the `spec-kickoff` skill updated so sign-off flips Draft→`Ready`
  (not Active), mirrors Status across all four files, bumps `Last reviewed`, and
  writes the sign-off record with the content anchor last (unchanged ordering);
  a Ready bundle's pre-merge changes go through delta re-walkthrough / re-sign-off
  (expression: changelog + self-re-anchor; meaning: + delta lens pass), the
  amendment ritual keys off Active (work in flight), and a Done bundle reopens to
  Draft.
- **Done when:** kickoff writes `Status: Ready` on sign-off across the four files;
  a Ready bundle's pre-merge change re-signs-off the delta without invoking the
  amendment ritual; amendment mode operates on Active bundles; the reopen path
  (Done→Draft) is intact; verified by the skill's tests/manual checks.
- **Dependencies:** Task 1.
- **Citations:** D-1, D-2, D-6, D-7 · REQ-D1.1, REQ-A1.4, REQ-D1.4, REQ-A1.6
- **Estimated effort:** half day

### Task 4 — `/spec-kickoff` marks the spec PR ready (terminal step) + D-26 exception

- **Deliverables:** the `spec-kickoff` skill marks the spec PR ready (un-draft) as
  the terminal step of clean completion, after the configured verification has
  converged; it does not flip if sign-off parked on a fork or verification did not
  converge, and never auto-merges. A config opt-out `mark_spec_pr_ready_on_kickoff`
  (default true) added to `config/defaults.yml` with a row in
  `docs/options-reference.md`. The flip restricted to the spec PR; the "gauntlet"
  documented as the configurable `review_sequence`-class verification.
- **Done when:** on clean completion the spec PR is ready; a parked/forked
  completion leaves it draft; task PRs are unaffected; the opt-out suppresses the
  flip; no auto-merge path exists; the option is documented and
  `scripts/check-options-reference.sh` passes.
- **Dependencies:** Task 3.
- **Citations:** D-6, D-7 · REQ-D1.2, REQ-D1.3, REQ-D1.5
- **Estimated effort:** 1 day

### Task 5 — `/orchestrate` gate: Ready or Active

- **Deliverables:** the `orchestrate` skill's pre-flight refusal updated from
  "non-Active" to "not Ready or Active": it acts on Ready or Active specs, refuses
  Draft/Done/Retired/Superseded, keeps the no-auto-chain and no-bypass invariants,
  and composes with the freshness gate (a Ready spec is executable only if its
  anchor is execution-valid). Skill prose and any status-naming messages updated.
- **Done when:** `/orchestrate` dispatches against a Ready or Active spec and
  refuses the others with a clear message; the freshness gate still applies to
  Ready; no bypass flag; verified by the skill's tests/manual checks.
- **Dependencies:** Task 1.
- **Citations:** D-1 · REQ-C1.1, REQ-C1.3
- **Estimated effort:** half day

### Task 6 — Derived reconcile of the bundle `Status:` header (extend the single writer)

- **Deliverables:** `orchestration-concurrency`'s single level-triggered reconcile
  writer extended to compute and reconcile the bundle `Status:` header from the
  task-state derivation: `Active` iff any task derives In-progress or Completed,
  else `Ready` when signed off; mirrored across the four files; idempotent; no
  independent status writer introduced (single-writer invariant preserved). This
  realizes the Ready→Active transition on first dispatch (REQ-C1.2) and the derived
  rule (REQ-A1.5).
- **Done when:** the reconcile renders `Status: Ready` for a signed-off bundle with
  no task in flight and `Status: Active` once any task derives In-progress/Completed;
  the header is written only by the single reconcile writer; the reconcile is
  idempotent and covered by tests.
- **Dependencies:** Task 5; plus cross-spec (hard): `orchestration-concurrency`
  Task 1 (derivation engine) and Task 4 (single reconcile writer) — see design
  Cross-cutting concerns.
- **Citations:** D-2, D-3 · REQ-A1.5, REQ-C1.2
- **Estimated effort:** 1 day

### Task 7 — Downstream core status surfaces recognize Ready

- **Deliverables:** `/spec-walkthrough`'s stage-aware framing extended to frame the
  `Ready` stage (its renderer and any status switch); validator and skill messages
  that enumerate statuses updated to include Ready; any core status-printing path
  audited for the five→six status set.
- **Done when:** `/spec-walkthrough` frames a Ready bundle with stage-appropriate
  language; status enumerations across core name Ready; covered by the relevant
  tests.
- **Dependencies:** Task 1.
- **Citations:** D-1, D-8 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** half day

### Task 8 — Migration sweep + docs + changelog reconcile

- **Deliverables:** a one-time migration applying the derived rule to existing
  bundles (Active-with-no-progress → Ready; for example `orchestration-concurrency`,
  and `orchestration-fleet` if merged by adoption); `docs/getting-started.md` and
  any lifecycle-naming
  docs updated to the six-status model; the glossary/options docs reconciled; dated
  `## Changelog` entries finalized in this bundle.
- **Done when:** every pre-adoption Active-with-no-progress spec is migrated to
  Ready and in-flight specs stay Active; the docs describe Draft→Ready→Active→Done;
  CI doc/link/options checks pass.
- **Dependencies:** Task 2, Task 4, Task 6.
- **Citations:** D-4 · REQ-A1.7
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

- The cross-session inbox/heartbeat dashboard's Ready rendering — dotfiles-local
  overlay, not core (D-8; bootstrap Scope — out of scope).
- A hardcoded core "gauntlet" review step — the verification is the configurable
  `review_sequence`-class mechanism (D-7).
- Fully deriving the bundle `Status:` header (dropping the stored value) — that is
  `orchestration-concurrency`'s deferred "Maximal" graduation, not this bundle.
- Re-deciding `orchestration-concurrency`'s derivation internals — consumed, not
  redefined.
- Auto-merge at any tier — permanent carried invariant.
