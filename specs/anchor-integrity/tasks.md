# Anchor integrity — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Task blocks below sit in dependency order. Execution state is derived, never
authored; see the status render.

## Tasks

### Task 1 — Meta-spec anchor amendments

- **Deliverables:** Amendments to `doctrine/spec-format.md`: the
  header-block `**Status:**` exclusion rule for the v1 per-file digests
  (bounded by the header-block scope; defer to format-grammar's scope
  definition where landed, else define the bound inline with a reconcile
  note); the committed-main frame statement in the execution-validity
  prose; the third sanctioned resolution-aware command form and the
  resolution chain it names; the decided-rule authoring-guidance
  refinement (no format-version bump). Dated meta-spec changelog entries
  for each.
- **Done when:** the meta-spec states all four amendments with changelog
  entries; `mise run check` documentation and lint tasks pass.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-4, D-7, D-8 · REQ-A1.1, REQ-A1.2, REQ-B1.1,
  REQ-E1.1, REQ-F1.1
- **Estimated effort:** half day

### Task 2 — Anchor tool hash-scope change

- **Deliverables:** The D-2 exclusion implemented for the
  `requirements.md` / `design.md` / `test-spec.md` digests, inside the
  shared extraction library if format-grammar's re-point has landed, else
  in `scripts/spec-anchor.sh` with a reconcile note; the script's header
  self-description corrected; the `scripts/tasks-pr-sync.sh` "NOT yet
  anchor-excluded" caveat comment updated; verification that
  `scripts/migrate-format-version.sh`'s written anchor entries remain
  sanctioned under the amended forms. Unit tests: anchor invariance under
  Draft→Ready and derived Ready↔Active header flips across all four
  files' mirrors; meaning-edit sensitivity unchanged; header-block
  bounding (a body-prose or fenced `**Status:**` line still moves the
  anchor when edited).
- **Done when:** the new tests pass alongside the existing
  `tests/test-spec-anchor.sh` suite; recomputed anchors move only for
  bundles whose Status line previously rode the hash.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3
- **Estimated effort:** 1 day

### Task 3 — Coordinated v1 re-anchor sweep

- **Deliverables:** Marked `Class: expression-only` re-anchor entries,
  citing the Task 1 amendment's changelog line, appended to the kickoff
  brief of every in-repo bundle whose anchor the Task 2 change moves; a
  one-shot landing proof that every bundle under `specs/` with a brief
  recomputes equal to its brief's most recent anchor entry after the
  sweep; adopter remedy documented (docs plus the freshness gate's v1
  halt-guidance prose naming the one-time self-re-anchor).
- **Done when:** the landing proof is green in the same PR as Task 2's
  change; the adopter remedy prose exists in both named places.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-A1.4, REQ-A1.5
- **Estimated effort:** half day

### Task 4 — Anchor-freshness guard

- **Deliverables:** A guard script (working name
  `scripts/check-anchor-freshness.sh`) asserting, for every non-Draft
  bundle with a kickoff brief: the brief's most recent anchor entry
  parses, uses a sanctioned command form, and recomputes equal against the
  checked tree; and that an edit to anchored content since the baseline
  ref carries a dated Changelog entry in that bundle. Draft and brief-less
  bundles skipped with a notice. Wired as a `mise run check` task (the
  normative merge gate) and as a best-effort lefthook pre-commit mirror.
  Unit tests covering the green, stale-anchor, non-sanctioned-form,
  missing-changelog, and skip paths.
- **Done when:** the guard is red on a synthesized stale-anchor fixture,
  green on the swept repo, wired into `mise run check` and `lefthook.yml`,
  and its tests pass in CI.
- **Dependencies:** 2, 3
- **Citations:** D-6 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4
- **Estimated effort:** 1 day

### Task 5 — Act-on-findings re-anchor ritual

- **Deliverables:** `/self-review`, `/polish`, and `/execute-task`'s
  convergence step gain the three D-5 behaviors: stale-anchor pre-flight
  before any signed-bundle edit; the expression-only self-re-anchor ritual
  (dated Changelog entry plus marked anchor entry, same change);
  meaning-class refusal with routing to `/spec-kickoff`. The doctrine
  statement binding act-on-findings skills generally (external families
  included) lands in the meta-spec's writer prose or `gate-wiring.md`
  (placement decided at execution, cited back here). Gherkin
  state/trigger/outcome scenarios recorded in `test-spec.md` verification
  homes.
- **Done when:** all three behaviors appear in each named skill's prose;
  the doctrine statement exists; skill instruction-budget checks stay
  green.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-C1.1, REQ-C1.2, REQ-C1.3
- **Estimated effort:** 1 day

### Task 6 — Kickoff terminal re-anchor

- **Deliverables:** `/spec-kickoff`'s finishing ritual gains the terminal
  recompute: any edit to anchored content after the sign-off record is
  written (post-sign-off review or panel fixes on the spec PR included)
  re-triggers the anchor recompute and re-record as the final pre-push
  step. Gherkin scenario recorded in `test-spec.md`.
- **Done when:** the skill prose states the terminal recompute; the
  scenario is recorded; skill instruction-budget checks stay green.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-C1.4
- **Estimated effort:** half day

### Task 7 — Enumeration cross-check at draft and kickoff

- **Deliverables:** `/spec-draft` and `/spec-kickoff` gain the enumeration
  cross-check step: flag enumerated counts and corpus claims in bundle
  prose, verify each against the surface it enumerates or convert it to a
  decided-rule statement, citing the Task 1 guidance refinement.
- **Done when:** both skills state the check; skill instruction-budget
  checks stay green.
- **Dependencies:** 1
- **Citations:** D-8 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
