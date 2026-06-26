# Orchestration Concurrency — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-26
**Format-version:** 1

Coverage mix: this spec is portable scripts + hook/skill behavior over git and
`gh`, so it leans `[test]` — most requirements are script-testable against fixture
repos with crafted evidence (commits, branches, trailers, markers, `gh` stubs).
A few carry a `[manual]` whole-system exercise (the solo no-remote flow, the
contamination reproduction at orchestration scale) or a `[design-level]` audit
(single-writer exclusivity, CI wiring) where a fragment test cannot stand in.
Every REQ is pinned to at least one path below.

**Verification ownership.** `[test]` arms run in the project's CI via
`mise run check` and gate every PR (per-PR regression net). `[design-level]`
arms are audited at PR review. `[manual]` arms are swept by the human as
acceptance gates, timed per arm rather than per worker PR: **A1.3** (solo
no-remote) is swept when **Task 3 reaches PR-ready** (the dispatch rework is
where the solo flow first runs end-to-end); **A1.2**'s two-tower-at-scale arm is
the **pre-Done capstone**, swept on `main` after Tasks 3 + 4 (and the Task 7
guards) merge, before the spec is flipped Done. The automated `[test]` arm of
A1.2 (the scripted contamination reproduction) carries per-PR regression
coverage in the meantime.

## REQ-A — Dispatch-commit isolation & derived progress state

### REQ-A1.1 — Dispatch writes no `tasks.md`; branch + lock are the record [test]

Dispatch a task in a fixture spec and assert: zero new commits touch `tasks.md`;
the task branch exists; the runtime dispatch marker exists; and the task derives
as In progress from branch + marker alone. Ordering: the branch is created
**before** the marker (branch-first); a dispatch interrupted after lock-acquire
but before branch-create leaves **neither** branch nor marker, so the task
derives Ready (fail-safe).

### REQ-A1.2 — Worker inherits no foreign dispatch commits [test + manual]

Test (the contamination reproduction): dispatch task A, then task B (sibling or a
different spec), cut B's worktree, and assert B's diff against its base contains
only B's own changes — no A/foreign `tasks.md` edits. Manual: at orchestration
scale, run two towers and confirm no worker PR carries a foreign spec's
bookkeeping.

### REQ-A1.3 — Works with no remote [test + manual]

Test: with no remote configured, the derivation and dispatch run end-to-end —
state derives from git + trailer + marker, `gh` is skipped, nothing errors on the
missing remote. A configured remote whose `gh` query fails (stubbed to error)
degrades to the same git-only derivation and surfaces the degradation rather than
wedging or corrupting state. Manual: a solo prototyping session drives a spec
forward with no PRs and the ledger stays correct.

## REQ-B — Single idempotent level-triggered projector

### REQ-B1.1 — `tasks-pr-sync` is the sole section writer [test + design-level]

Design-level audit: no skill, hook, or tower path other than the reconcile writes
`tasks.md` section placement (repo-wide trace). Test: the reconcile is exercised
as the writer and the dispatch path is confirmed to write none.

### REQ-B1.2 — Level-triggered & idempotent [test]

Run the reconcile twice against unchanged truth and assert the second run is a
no-op (no diff). Drop an event (skip a reconcile), run the next reconcile, and
assert placement self-heals to correct from current truth.

### REQ-B1.3 — Snapshot is a discardable derivation [test]

Delete the `tasks.md` section snapshot entirely, run the reconcile, and assert it
is rebuilt identically from truth with no data loss.

## REQ-C — Authoritative-state derivation & deterministic conflict resolution

### REQ-C1.1 — Derivation from observable evidence [test]

Against a fixture matrix (merged PR, merge-reachable branch, trailer-only base
commit, open PR, fresh-marker-only ⇒ In progress, stale-marker-only-no-commits ⇒
Ready, no-evidence-with-deps-met, no-evidence-with-deps-unmet), assert each task
derives to the correct state. The stale-marker case (a timestamped marker past
the configured threshold whose branch has no commits) confirms a crashed
pre-first-commit dispatch does not wedge the task In progress.

### REQ-C1.2 — Git-truth precedence; contradictions flagged [test]

Test: a closed-unmerged PR whose work is nonetheless reachable in the base derives
as Completed (reality wins over PR metadata). A genuine contradiction (e.g. a
trailer claiming completion with no reachable work) is reported to the guard, not
silently resolved. The contradiction appears as a tagged record on the
derivation's output stream (the defined channel), assertable without the guard
wired.

### REQ-C1.3 — Conflict resolution regenerates from truth [test]

Simulate a `tasks.md` merge conflict and assert resolution regenerates placement
from the derivation and validates — never `ours`/`theirs`/`union`. A crafted
interleave that would mis-sort under union resolves correctly here.

### REQ-C1.4 — `Planwright-Task` trailer round-trips [test]

`/execute-task` emits the `Planwright-Task: <spec>/<id>` footer trailer (one per
task for a bundled commit); the derivation parses it via git's trailer mechanism;
a commit with the trailer but a deleted branch still derives Completed.

## REQ-D — Advisory-lock correctness

### REQ-D1.1 — One lock primitive, no duplication [test + design-level]

Design-level: `orchestrate-lock.sh` and the hook resolve to a single lock
implementation; the previously-duplicated inline lock logic is gone (audit).
Test: both call sites acquire/break through the one primitive.

### REQ-D1.2 — Mutual exclusion + sound stale-break [test]

Concurrent acquirers of the same per-spec lock exclude (one wins); a lock older
than the configured threshold breaks; a fresh lock does not. The branch-ref-as-
fence reasoning is recorded design-level (D-4) since D-1 removes the holder's
authoritative-write path.

## REQ-E — Corruption & drift guards

### REQ-E1.1 — Structural-corruption guard [test]

A committed `tasks.md` snapshot carrying a **structural corruption** the
reconcile would never produce (a task in a section its own evidence contradicts,
a mis-sort, a malformed/duplicated block) fails the guard with a clear message.
A well-formed snapshot that is merely **lagging** live truth (a not-yet-
reconciled in-flight task still shown Forward) **passes** — intentional lag is
not corruption; freshness is the reconcile pass's job, not the guard's. The
write path is asserted atomic (write-temp-then-rename) so a torn file cannot
result from concurrent reconcile.

### REQ-E1.2 — `>1 Status line` lint [test]

A task block carrying two `Status` lines (the duplicate-dispatch-metadata
signature) fails the lint; a well-formed block passes.

### REQ-E1.3 — Guards wired into CI [design-level + test]

Design-level: both guards are registered in the project's CI / pre-commit
configuration. Test: the CI entry point invokes them and fails the run on a
corrupt or drifted ledger fixture.

## REQ-F — Robustness & framework-script safety

### REQ-F1.1 — Parsed identifiers validated; derived paths contained [test]

A `Planwright-Task` trailer carrying a malformed or hostile `<spec>/<id>` (path
traversal like `../../x`, shell metacharacters, or an id failing the grammar) is
refused/flagged and never used to build a branch, ref, marker path, or lock path;
a derived marker/lock path that would escape its base directory after
canonicalization is refused. Well-formed identifiers pass through unchanged.
