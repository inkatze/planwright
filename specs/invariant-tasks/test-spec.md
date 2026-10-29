# Invariant Tasks — Test Spec

**Status:** Ready
**Last reviewed:** 2026-10-29
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the machinery requirements (REQ-B, REQ-C, REQ-D) verify as
`[test]` entries in the shell suite under `tests/`, run by `mise run check`
in CI; the format and doctrine requirements (REQ-A, REQ-E1.1) are
`[design-level]` against the meta-spec text plus validator fixtures; the
migration of this repo's own bundles and the skill reconciliation carry a
`[manual]` arm where a human exercises the surface.

## REQ-A — The invariant committed ledger (format-version 2)

### REQ-A1.1 — v2 tasks.md content [test + design-level]

Format-version 2's shape is normatively defined in `doctrine/spec-format.md`
(Task 1, design-level); mechanically enforced by validator fixtures (Task 2):
a v2 fixture carrying a placement section or a state annotation bullet fails
validation, a compliant v2 fixture passes.

### REQ-A1.2 — no commits for derived execution-state changes [test]

The churn-free fixture test (Task 4): a full state transition (dispatch →
in-progress evidence → merged-PR evidence, plus a parking and an unparking
write) exercised against a v2 fixture bundle produces zero diff under the
spec directory for the derived transitions; the parking/unparking commits
are asserted to be legitimate human-payload writes that leave the content
anchor unchanged. Runs in `mise run check`.

### REQ-A1.3 — restricted stored header [test]

Validator fixtures (Task 2): a v2 fixture with a stored `Active` or `Done`
header value fails; Draft/Ready/Retired/Superseded pass. The render (Task 3)
reports derived Active/Done on fixtures whose stored header reads Ready. A
reopen fixture (Ready→Draft header write) validates cleanly and is the
re-anchoring lifecycle write D-9 names.

### REQ-A1.4 — format continuity [test]

Migration fixture test (Task 6): the canonical `tasks.md` extraction digest
is byte-identical before and after v1→v2 migration, proving IDs, definition
fields, and dependency lines survive unchanged.

## REQ-B — Derived status as the read surface

### REQ-B1.1 — derived render [test]

Render fixture tests (Task 3): merged-PR, open-PR, branch-only, marker-only,
commit-trailer, and parked-task fixtures each derive the expected per-task
status and bundle effective status; the merged-PR fixture asserts the PR
number and merge date are rendered (REQ-C1.7's completion-readability
successor leans on this); the render writes no file.

### REQ-B1.2 — no-remote degradation [test]

Render fixture with no remote configured (Task 3): status derives from
branch/commit evidence with the documented degraded outputs; exit code and
the derived status facts pinned (not literal render text, per D-6's
no-stability promise).

### REQ-B1.3 — render as canonical read surface [design-level + manual]

Design-level: Task 7's done-when requires every reconciled skill to
reference the correct read surface (the render for human-facing status, the
derivation engine for machine logic, per REQ-E1.2), and no committed or
remote-mirrored status artifact exists in the design (D-6). Manual: a human
reads a live v2 bundle's status via the render and confirms no other
surface claims to show it.

### REQ-B1.4 — reference-bullet authority [test]

Render fixtures (Task 3): a task with completed-PR git evidence plus a live
Awaiting-input bullet derives as awaiting-input, not completed (and is
flagged as a stale-bullet anomaly); removing the bullet restores
evidence-derived status; Deferred and Out-of-scope reference bullets park
their tasks the same way.

### REQ-B1.5 — transient evidence failure fails closed [test]

Fixtures with a configured-but-failing remote (Tasks 3 and 5): the render
reports the fetch failure distinctly from the no-remote mode (exit code
pinned) instead of presenting partial evidence as status; the selector
dispatches nothing; gate completion atoms resolve as unresolved; a
no-PR-found response derives branch-only evidence (not failure); and
reference-bullet parked state, which needs no remote, still reports during
the failure.

### REQ-B1.7 — transient evidence failure fails closed per task [test]

Supersedes the REQ-B1.5 entry above for new fixtures. Single-repository
fixtures with a configured-but-failing remote keep every REQ-B1.5
assertion (with one repository, every task is in the failing one). The
two-repository fixture (Task 11) adds the per-task scope, asserted under
REQ-F1.6: tasks drawing only on a healthy repository keep selecting and
rendering, tasks whose own or direct dependency's repository failed are
withheld, and the render names the failing repository.

### REQ-B1.6 — derived-status determination rules [test]

Render fixtures (Task 3): a stored-Draft, Retired, or Superseded fixture
renders its stored state with no execution claim; a zero-task v2 fixture
reports no tasks and never derives Done; an all-completed fixture with a
live Awaiting-input bullet derives not-Done at the bundle level; an
all-completed fixture with one task parked by a Deferred bullet derives
Done (excluded from the Done universe, not blocking).

## REQ-C — Machinery reconciliation

### REQ-C1.1 — version-keyed writer [test]

`tasks-pr-sync` fixture tests (Task 4): on a v1 fixture the reconcile
behavior is unchanged (existing tests stay green); on a v2 fixture the
writer performs no write (directory digest unchanged after invocation).

### REQ-C1.2 — selection without placement [test]

Selector fixtures (Task 5): a v2 fixture with equivalent state to a v1
fixture yields the same candidate set; parked tasks (a live reference
bullet in any human-payload section) are excluded; completed/in-progress
exclusion comes from derivation evidence, not sections.

### REQ-C1.3 — gate evaluation via derivation [test]

Drain-gate fixtures (Task 5): task-completion atoms resolve on a v2 fixture
with no `## Completed` section, from merged-PR evidence; v1 fixture behavior
unchanged.

### REQ-C1.4 — ledger guard scope [test]

check-ledger fixtures (Task 4): on v2, structural violations (malformed
heading, duplicate id, a task block outside any recognized section) still
fail — with `## Tasks` recognized — while placement/annotation coherence
checks do not fire; on v1, existing coherence tests stay green.

### REQ-C1.5 — validator v2 invariants [test]

Validator fixtures (Task 2): each v2 invariant violation fails as an error
on a Ready fixture and warns on a Draft fixture — per-token fixtures for
each banned placement heading (Forward plan, In progress, Completed) and
each banned annotation (Status, Last activity, Dispatch), a non-restricted
header, a missing pointer line, a pointer line with non-canonical
vocabulary, and reference-bullet integrity violations (unknown task id,
duplicate bullet, the same task named in two human-payload sections); v1
bundles validate under v1 rules.

### REQ-C1.6 — churn-free anchor [test]

The Task 4 churn-free test additionally recomputes the content anchor
(canonical form) before and after the exercised state transitions —
including the parking/unparking writes — and asserts equality.

### REQ-C1.7 — completion-annotation supersession [design-level]

The supersession record is the verification artifact (Task 8): D-11 plus the
dated changelog entry recording that the normative completion annotation
does not apply to v2 bundles, with output-hygiene's text unedited. Completion
readability on v2 is covered functionally by REQ-B1.1's render fixtures
(merged-PR case shows PR number and merge date).

### REQ-C1.8 — fail-closed version keying [test]

Fixtures with a missing or unparseable `Format-version:` line (Tasks 2–6):
every version-keyed script — the validator, the sync writer, the ledger
guard, the render, the selector, the gate evaluator, and the migration —
fails closed on it: no write is performed (spec-directory digest unchanged
after invocation), an error is reported, and no script applies the v1
write path.

### REQ-C1.9 — security binding [test]

Migration fixtures (Task 6): hostile identifiers and out-of-containment
paths are refused with a clean error whose output is sanitized. Render and
guard fixtures (Tasks 3, 4) and validator fixtures (Task 2): embedded
terminal-escape bytes in bullet text, header values, branch names, and
remote error text are stripped from echoed output (`sanitize_printable`);
a reference bullet whose task id violates the task-id grammar is rejected.

## REQ-D — Migration & coexistence

### REQ-D1.1 — coexistence [test]

Version-keying tests across Tasks 2, 4, 5: every touched script asserts both
a v1-fixture arm (behavior unchanged) and a v2-fixture arm (new behavior);
the Task 4 parser-family sweep asserts `spec-model.sh` and its consumers
tolerate the v2 shape; `specs/` in this repo holds both versions during
migration and `mise run check` passes throughout.

### REQ-D1.2 — migration path [test]

Migration fixtures (Task 6): a seeded v1 bundle (with relocated
Awaiting-input block, a parked block under Deferred/Out of scope,
annotations, Active header) migrates to a v2 bundle that validates cleanly
with the parked blocks converted to reference bullets; the extraction
digest is unchanged; a raw line-level diff confirms the definition lines
survive byte-for-byte; running the migration a second time is a byte-level
no-op; the re-anchor entry is written as expression-only and cites the
dated changelog line the migration appends; a seeded partial-run fixture
(file migrated to v2, re-anchor entry missing) is completed — not
skipped — by a re-run.

### REQ-D1.3 — own-bundle migration [test + manual]

Test: after Task 6, `spec-validate` passes every bundle in `specs/`, live
bundles at v2, Done/terminal bundles byte-identical (git diff empty for
them). Manual: the human reviews the migration PR's diff confirming only
live bundles changed.

## REQ-E — Doctrine, skills, config, and lineage

### REQ-E1.1 — meta-spec v2 [design-level]

The artifact's existence and coverage is the verification: the
format-version 2 section in `doctrine/spec-format.md` defines the v2 shape,
vocabulary, pointer line, reference-bullet forms with their data-hygiene
note (REQ-C1.9), and read surface such that a compliant bundle can
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
and the docs check asserts the note's content is present in the row.

### REQ-E1.4 — lineage closure [design-level + test]

The annotation on orchestration-concurrency's Deferred "Maximal variant"
entry, citing this bundle, is the verification artifact; its presence is
mechanically checked in the Task 6 fixture suite and reviewed at that PR.

## REQ-F — Per-task repositories (format-version 3)

### REQ-F1.1 — version 3 field and coexistence [test + design-level]

Validator fixtures (Task 10): a version 3 bundle with a valid
`Repository:` field passes; the same field in a version 2 bundle fails;
every in-repo version 1 and 2 bundle still validates. The version 3
definition in `doctrine/spec-format.md` (Task 9) is the design-level
artifact. The holder-arm resolution of a field-less task is exercised by
`custom-spec-location`'s holder-dispatch fixtures on the shared harness.
Runs in `mise run check`.

### REQ-F1.2 — alias grammar, one per block, marker precondition [test]

Validator fixtures (Task 10): two fields in one block, a list value, a
path value, a URL value, and an alias outside the identifier grammar each
fail on a signed fixture and warn on a Draft one; a version 3 field under
a spec root without a marker warns. The derivation fixtures (Task 11)
resolve the alias only through the fixture registry; no fixture bundle
names a checkout.

### REQ-F1.3 — field in the extraction [test]

Extraction fixtures (Task 10): a version 3 bundle with no field produces
the same digest as its version 2 copy; adding a field, changing its alias,
or removing it each change the digest; `scripts/spec-anchor.sh` still
reads no `Format-version:`.

### REQ-F1.4 — per-task derivation and dependencies [test]

The two-repository fixture (Task 11): Task 1 names `alpha`, Task 2 names
`beta` and depends on Task 1, Task 3 names `alpha` and depends on Task 2.
A merged pull request for Task 1 in `alpha` makes Task 2 selectable, and
Task 1's branch alone does not; a same-named task branch in `beta` is not
evidence for Task 1; Task 2 derives from `beta` only; the render prints
each task's alias; a bundle with no field derives exactly as before on the
existing render fixtures.

### REQ-F1.5 — unresolved field fails closed [test]

The two-repository fixture with `beta` removed from the fixture registry
(Task 11): Task 2 derives `repository-unresolved` naming `beta`, is never
selected, leaves Task 3 unmet, resolves its gate atoms unresolved, and the
bundle does not derive Done; Task 1 still derives from `alpha`. Variants
with a malformed value and with a duplicate field derive the same state
and never derive from the work repository.

### REQ-F1.6 — transient failure keyed per task [test]

The two-repository fixture with a failing remote stub in `beta` (Task 11):
the render reports the failure naming `beta`; Task 2 (its own repository
failed) and Task 3 (its dependency's repository failed) are never
selected, while Task 1 stays selectable; gate atoms on Task 2 resolve
unresolved; no derived bundle status is claimed.

### REQ-F1.7 — validator severities and version keying [test]

Validator fixtures (Task 10) at Draft, signed, and terminal statuses
assert the REQ-C1.5 severities for each field rule; an escape-byte alias
is sanitized in the error; a version 3 fixture gets its version 2 behavior
from every script that reads `Format-version:`, the equality-keyed park
helpers included; a version 4 declaration fails closed in every such
script.

### REQ-F1.8 — doctrine and authoring [design-level + manual]

The version 3 entry in the meta-spec's versioning section (Task 9) is the
design-level artifact. `/spec-draft`'s version 3 skeleton with one field
validates (Task 12, a fixture); a human drafts a two-repository bundle and
confirms the skill offers the field and declares version 3 only then.
