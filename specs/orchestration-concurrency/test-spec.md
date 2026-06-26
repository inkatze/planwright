# Orchestration Concurrency — Test Spec

**Status:** Draft
**Last reviewed:** 2026-06-26
**Format-version:** 1

Coverage mix: this spec is portable scripts + hook/skill behavior over git and
`gh`, so it leans `[test]` — most requirements are script-testable against fixture
repos with crafted evidence (commits, branches, trailers, markers, `gh` stubs).
A few carry a `[manual]` whole-system exercise (the solo no-remote flow, the
contamination reproduction at orchestration scale) or a `[design-level]` audit
(single-writer exclusivity, CI wiring) where a fragment test cannot stand in.
Every REQ is pinned to at least one path below.

## REQ-A — Dispatch-commit isolation & derived progress state

### REQ-A1.1 — Dispatch writes no `tasks.md`; branch + lock are the record [test]

Dispatch a task in a fixture spec and assert: zero new commits touch `tasks.md`;
the task branch exists; the runtime dispatch marker exists; and the task derives
as In progress from branch + marker alone.

### REQ-A1.2 — Worker inherits no foreign dispatch commits [test + manual]

Test (the contamination reproduction): dispatch task A, then task B (sibling or a
different spec), cut B's worktree, and assert B's diff against its base contains
only B's own changes — no A/foreign `tasks.md` edits. Manual: at orchestration
scale, run two towers and confirm no worker PR carries a foreign spec's
bookkeeping.

### REQ-A1.3 — Works with no remote [test + manual]

Test: with no remote configured, the derivation and dispatch run end-to-end —
state derives from git + trailer + marker, `gh` is skipped, nothing errors on the
missing remote. Manual: a solo prototyping session drives a spec forward with no
PRs and the ledger stays correct.

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
commit, open PR, marker-only, no-evidence-with-deps-met, no-evidence-with-deps-
unmet), assert each task derives to the correct state.

### REQ-C1.2 — Git-truth precedence; contradictions flagged [test]

Test: a closed-unmerged PR whose work is nonetheless reachable in the base derives
as Completed (reality wins over PR metadata). A genuine contradiction (e.g. a
trailer claiming completion with no reachable work) is reported to the guard, not
silently resolved.

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

### REQ-E1.1 — Snapshot-vs-truth drift guard [test]

A committed `tasks.md` snapshot deliberately out of sync with the live derivation
fails the drift guard with a clear message; an in-sync bundle passes.

### REQ-E1.2 — `>1 Status line` lint [test]

A task block carrying two `Status` lines (the duplicate-dispatch-metadata
signature) fails the lint; a well-formed block passes.

### REQ-E1.3 — Guards wired into CI [design-level + test]

Design-level: both guards are registered in the project's CI / pre-commit
configuration. Test: the CI entry point invokes them and fails the run on a
corrupt or drifted ledger fixture.
