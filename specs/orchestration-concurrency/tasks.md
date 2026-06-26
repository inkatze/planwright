# Orchestration Concurrency — Tasks

**Status:** Draft
**Last reviewed:** 2026-06-26
**Format-version:** 1

Dependency view (the `Dependencies:` lines are authoritative). Task 1 (the
task-state derivation engine) is the backbone almost everything else reads
through; Task 6 (the unified lock primitive) is the other foundational, ungated
piece. The two run early and in parallel:

- **Foundation:** T1 (derivation engine), T6 (lock primitive), T2 (trailer
  emission) — all dependency-free.
- **On T1:** T3 (dispatch rework; also on T6), T4 (idempotent reconcile), T5
  (selection reads live truth), T7 (drift/corruption guards).
- **Docs + cross-spec:** T8, on T1/T3/T4.

**Guard-first ordering.** T7 ships the drift/corruption guards. It depends on T1
(it needs the live truth to compare against), but it SHOULD land before T3, T4,
and T5 merge, so their placement-affecting changes validate under the guard.
This ordering is a should-precede preference recorded here (the task format has
no soft-ordering edge); it is not encoded as a dependency, which would invert the
real data dependency on T1.

## Forward plan

### Task 1 — Task-state derivation engine

- **Deliverables:** A `scripts/orchestrate-state.sh` that derives each task's
  state for a spec from observable evidence — merged PR via `gh`, task-branch
  merge-reachability (`git merge-base --is-ancestor`), a `Planwright-Task`
  trailer on a base commit, and the runtime dispatch marker — applying the
  REQ-C1.2 precedence (git ground truth wins; contradictions flagged). Emits a
  tagged record stream (task id → state + the evidence that decided it). The
  shared backbone consumed by the reconcile (T4), selection (T5), and the guards
  (T7).
- **Done when:** against a fixture spec with mixed evidence (merged PR, reachable
  branch, trailer-only base commit, open PR, marker-only, none), it returns the
  correct state for each task; it is idempotent; it runs with no remote (skips
  `gh`, derives from git + trailer + marker); a signal contradiction is reported,
  not silently resolved; tests pass under `mise run check`.
- **Dependencies:** none
- **Citations:** D-1 · D-2 · REQ-C1.1, REQ-C1.2, REQ-A1.3
- **Estimated effort:** 2 days

### Task 2 — Commit-trailer emission

- **Deliverables:** `/execute-task` (and the shared commit helpers) emit a
  `Planwright-Task: <spec>/<id>` trailer in the commit footer — one trailer per
  task for a bundled commit — plus documentation of the convention for manual /
  solo commits.
- **Done when:** `/execute-task` commits carry the trailer in the footer; a
  bundled commit carries one per task; Task 1's engine parses them via git's
  trailer mechanism; the no-Claude-attribution rule is unaffected; tests pass
  under `mise run check`.
- **Dependencies:** none
- **Citations:** D-2 · REQ-C1.4
- **Estimated effort:** half day

### Task 3 — Dispatch rework: branch-as-record, no `tasks.md` writes

- **Deliverables:** `/orchestrate` dispatch rewired to: acquire the per-spec lock
  → create the task branch as the first durable act → write the runtime dispatch
  marker → release; with **all** dispatch-time `tasks.md` section moves and
  status annotations removed. Worker worktrees are cut from a base that carries
  no dispatch commits.
- **Done when:** dispatching a task creates the branch + marker and makes **zero**
  `tasks.md` commits; a worker worktree cut immediately after has no sibling or
  foreign-spec dispatch commit in its diff (the contamination reproduction now
  passes clean); the in-flight task is derivable as In progress from branch +
  marker; tests pass under `mise run check`.
- **Dependencies:** 1, 6
- **Citations:** D-1 · D-3 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 2 days

### Task 4 — Level-triggered idempotent reconcile (single writer)

- **Deliverables:** `tasks-pr-sync` reworked into the **sole** writer of
  `tasks.md` section placement: a level-triggered, idempotent pass that recomputes
  full placement from Task 1's derivation. On any `tasks.md` merge conflict, it
  regenerates placement from the derivation and validates, never resolving by
  `ours`/`theirs`/`union`. Dispatch-time section writing is gone (Task 3); this is
  the only path that writes sections.
- **Done when:** running the reconcile twice against unchanged truth is a no-op
  the second time; a simulated merge-interleave (the multi-day-drift scenario)
  reconciles to correct placement from truth; no path other than this writes
  section placement; the committed snapshot is refreshed off the dispatch path
  only; tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-1 · D-3 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-C1.3
- **Estimated effort:** 2 days

### Task 5 — Selection reads live truth

- **Deliverables:** `orchestrate-select` rewired to consume Task 1's live
  derivation (rather than the committed snapshot) when choosing the next ready
  unit, so an in-flight or already-Completed task is never re-dispatched.
- **Done when:** with a task mid-flight (branch + marker present, snapshot not yet
  refreshed), the selector does not re-dispatch it; with a task Completed by
  reachable-but-snapshot-stale evidence, the selector treats it as done;
  selection output is unchanged for the clean steady state; tests pass under
  `mise run check`.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-B1.2
- **Estimated effort:** 1 day

### Task 6 — Unify the advisory-lock primitive

- **Deliverables:** One advisory-lock primitive shared by `/orchestrate` and the
  `tasks-pr-sync` hook (collapsing `orchestrate-lock.sh` and the hook's inline
  lock), with per-spec mutual exclusion and a sound stale-break at the configured
  threshold. No fencing tokens (the branch ref is the natural fence, D-4).
- **Done when:** both `/orchestrate` and the hook acquire through one primitive;
  concurrent acquirers exclude; a stale lock breaks at the threshold; the
  duplicated lock logic is gone; tests pass under `mise run check`.
- **Dependencies:** none
- **Citations:** D-4 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 1 day

### Task 7 — Drift / corruption guards + CI

- **Deliverables:** Guards wired into CI / pre-commit: (a) a **snapshot-vs-live-
  truth drift** check (the committed `tasks.md` sections must match Task 1's
  derivation), and (b) a **`>1 Status line` per task block** lint. See the
  guard-first ordering note above: this SHOULD land before T3/T4/T5 merge.
- **Done when:** a hand-corrupted snapshot (drift, or two Status lines on a block)
  fails the guard with a clear message; a clean, in-sync bundle passes; both
  guards run in the project's CI and pre-commit; tests pass under `mise run check`.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 1 day

### Task 8 — Docs, options & bootstrap canonical-record amendment

- **Deliverables:** Documentation of the derived-state model (the derivation, the
  trailer convention, the single-writer reconcile, the marker, the no-remote
  flow); any new option rows in `docs/options-reference.md`; and a `/spec-kickoff`
  delta **amendment to `bootstrap`** (changelog entry + re-anchor) reconciling its
  "`tasks.md` is the canonical state record" wording with the derived-snapshot
  model (D-5).
- **Done when:** the derived-state model and trailer convention are documented for
  an adopter; every new option has a row and `check-options-reference.sh` passes;
  the bootstrap amendment lands via `/spec-kickoff` with a dated changelog entry
  and a re-anchor (no out-of-flow edit to an Active bundle); `check-doc-links.sh`
  and the doc linters pass.
- **Dependencies:** 1, 3, 4
- **Citations:** D-5 · REQ-A1.3, REQ-B1.1
- **Estimated effort:** 1 day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **The Maximal variant (drop committed `tasks.md` sections entirely).** The
  derived engine (T1) is shared with this variant; only the snapshot rendering
  differs. Built only if the `orchestration-fleet` spec's scale makes the
  committed snapshot a liability. Confidence: high.
  **Gate:** the fleet spec surfaces a concrete need to drop the committed
  snapshot (and absorb the spec-format meta-spec change it requires).
  Citations: D-1.

## Out of scope

- The scaling / resilience / UX layer (pluggable & autodetected backends,
  self-management, meta-orchestration, coordination protocol, approachability):
  the `orchestration-fleet` sibling spec.
- Anchor-drift / kickoff-freshness false-halts (a distinct subsystem; separate
  fast-follow).
- Selection *policy* (critical-path / guard-first ordering); this spec changes how
  state is represented and derived, not which ready unit is chosen.
- Auto-merge at any tier (permanent carried invariant).
