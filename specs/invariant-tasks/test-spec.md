# Invariant Tasks — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-14
**Format-version:** 1

Coverage mix: the machinery requirements (REQ-B, REQ-C, REQ-D) verify as
`[test]` entries in the shell suite under `tests/`, run by `mise run check`
in CI; the format and doctrine requirements (REQ-A, REQ-E1.1) are
`[design-level]` against the meta-spec text plus validator fixtures; the
migration of this repo's own bundles and the skill reconciliation carry a
`[manual]` arm where a human exercises the surface.

### REQ-A1.1 — v2 tasks.md content [test + design-level]

Format-version 2's shape is normatively defined in `doctrine/spec-format.md`
(Task 1, design-level); mechanically enforced by validator fixtures (Task 2):
a v2 fixture carrying a placement section or a state annotation bullet fails
validation, a compliant v2 fixture passes.

### REQ-A1.2 — no commits for execution-state changes [test]

The churn-free fixture test (Task 4): a full state transition (dispatch →
in-progress evidence → merged-PR evidence) exercised against a v2 fixture
bundle produces zero diff under the spec directory. Runs in `mise run check`.

### REQ-A1.3 — restricted stored header [test]

Validator fixtures (Task 2): a v2 fixture with a stored `Active` or `Done`
header value fails; Draft/Ready/Retired/Superseded pass. The render (Task 3)
reports derived Active/Done on fixtures whose stored header reads Ready.

### REQ-A1.4 — format continuity [test]

Migration fixture test (Task 6): the canonical `tasks.md` extraction digest
is byte-identical before and after v1→v2 migration, proving IDs, definition
fields, and dependency lines survive unchanged.

### REQ-B1.1 — derived render [test]

Render fixture tests (Task 3): merged-PR, open-PR, branch-only, marker-only,
and parked-task fixtures each derive the expected per-task status and bundle
effective status; the render writes no file.

### REQ-B1.2 — no-remote degradation [test]

Render fixture with no remote configured (Task 3): status derives from
branch/commit evidence with the documented degraded outputs; exit code and
output pinned.

### REQ-B1.3 — render as canonical read surface [design-level + manual]

Design-level: Task 7's done-when requires every reconciled skill to
reference the render, and no committed or remote-mirrored status artifact
exists in the design (D-6). Manual: a human reads a live v2 bundle's status
via the render and confirms no other surface claims to show it.

### REQ-B1.4 — Awaiting-input authority [test]

Render fixture (Task 3): a task with completed-PR git evidence plus a live
Awaiting-input bullet derives as awaiting-input, not completed; removing the
bullet restores evidence-derived status.

### REQ-C1.1 — version-keyed writer [test]

`tasks-pr-sync` fixture tests (Task 4): on a v1 fixture the reconcile
behavior is unchanged (existing tests stay green); on a v2 fixture the
writer performs no write (directory digest unchanged after invocation).

### REQ-C1.2 — selection without placement [test]

Selector fixtures (Task 5): a v2 fixture with equivalent state to a v1
fixture yields the same candidate set; parked tasks (Awaiting-input bullet,
Deferred, Out of scope) are excluded; completed/in-progress exclusion comes
from derivation evidence, not sections.

### REQ-C1.3 — gate evaluation via derivation [test]

Drain-gate fixtures (Task 5): task-completion atoms resolve on a v2 fixture
with no `## Completed` section, from merged-PR evidence; v1 fixture behavior
unchanged.

### REQ-C1.4 — ledger guard scope [test]

check-ledger fixtures (Task 4): on v2, structural violations (malformed
heading, duplicate id) still fail while placement/annotation coherence
checks do not fire; on v1, existing coherence tests stay green.

### REQ-C1.5 — validator v2 invariants [test]

Validator fixtures (Task 2): each v2 invariant violation (state section,
state annotation, non-restricted header, missing pointer line) fails as an
error on a Ready fixture and warns on a Draft fixture; v1 bundles validate
under v1 rules.

### REQ-C1.6 — churn-free anchor [test]

The Task 4 churn-free test additionally recomputes the content anchor
(canonical form) before and after the exercised state transition and asserts
equality.

### REQ-C1.7 — completion-annotation supersession [design-level]

The supersession record is the verification artifact (Task 8): D-11 plus the
dated changelog entry recording that the normative completion annotation
does not apply to v2 bundles, with output-hygiene's text unedited. Completion
readability on v2 is covered functionally by REQ-B1.1's render fixtures
(merged-PR case shows PR number and merge date).

### REQ-D1.1 — coexistence [test]

Version-keying tests across Tasks 2, 4, 5: every touched script asserts both
a v1-fixture arm (behavior unchanged) and a v2-fixture arm (new behavior);
`specs/` in this repo holds both versions during migration and
`mise run check` passes throughout.

### REQ-D1.2 — migration path [test]

Migration fixtures (Task 6): a seeded v1 bundle (with relocated
Awaiting-input block, annotations, Active header) migrates to a v2 bundle
that validates cleanly; the extraction digest is unchanged; the re-anchor
entry is written as expression-only.

### REQ-D1.3 — own-bundle migration [test + manual]

Test: after Task 6, `spec-validate` passes every bundle in `specs/`, live
bundles at v2, Done/terminal bundles byte-identical (git diff empty for
them). Manual: the human reviews the migration PR's diff confirming only
live bundles changed.

### REQ-E1.1 — meta-spec v2 [design-level]

The artifact's existence and coverage is the verification: the
format-version 2 section in `doctrine/spec-format.md` defines the v2 shape,
vocabulary, pointer line, and read surface such that a compliant bundle can
be authored from it alone; reviewed at the Task 1 PR.

### REQ-E1.2 — skill reconciliation [design-level + manual]

Design-level: Task 7's done-when enumerates the per-skill conditions (no
state-section writes, render-based reads, v2 authoring skeleton). Manual:
one end-to-end pass — draft a toy v2 bundle, dispatch a task, park it,
complete it — confirming no committed state writes occur and status reads
correctly at each step.

### REQ-E1.3 — options-reference note [test]

`scripts/check-options-reference.sh` (already in `mise run check`) keeps the
`commit_on_state_move` row present; the Task 8 change adds the v1-only note
and the docs check passes.

### REQ-E1.4 — lineage closure [design-level]

The annotation on orchestration-concurrency's Deferred "Maximal variant"
entry, citing this bundle, is the verification artifact; its presence is
asserted in the Task 6 done-when and reviewed at that PR.
