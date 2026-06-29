# Orchestration state: the derived-projection model

How planwright tracks which tasks are pending, in flight, or done when several
`/orchestrate` towers run concurrently against one checkout. The short version:
orchestration progress is **not** hand-maintained state that each tower edits.
It is a **derived projection** of observable git and GitHub evidence, recomputed
idempotently from ground truth. The committed `tasks.md` sections are a
discardable, rebuildable snapshot of that projection, never the source of truth.

This is the conceptual companion to [`conventions.md`](conventions.md), which
documents the operational surface (branch names, the `tasks-pr-sync` hook, the
commit trailer). Read this for the *why* and the model; read conventions for the
*what* a skill or hook touches.

## The problem it solves

Before this model, `tasks.md` doubled as the canonical orchestration record
(bootstrap D-2): each tower hand-edited section placement at dispatch. With one
tower that is fine. With several towers sharing a checkout, it corrupts shared
state three ways:

- the `tasks.md` ledger mis-sorts when two towers move blocks concurrently;
- dispatch metadata lands on the wrong block or duplicates (the `>1 Status line`
  signature);
- a worker branch cut from `main` inherits sibling or foreign-spec dispatch
  commits as ancestors, polluting the worker's PR diff.

The only repair was manual: merge intermediate PRs to flush unpushed local-`main`
bookkeeping, then hand-resort the ledger.

## The model (D-1)

`/orchestrate` writes **no** dispatch or progress state to `tasks.md`. Two
mechanisms replace the hand-maintained ledger:

1. **The dispatch record is the task branch plus the per-spec advisory lock.**
   The branch is created as the first durable act of dispatch. Because `main`
   carries no dispatch commit, a worker worktree cut from it inherits nothing
   foreign, so cross-task and cross-spec contamination is impossible **by
   construction**, not merely mitigated.
2. **Section placement is a read-model snapshot**, recomputed from authoritative
   evidence by a single level-triggered reconcile, off the worker's critical
   path.

The design borrows three pieces of well-proven prior art:

- **Event-sourcing read-model projections.** The snapshot is a cache derived
  from the log of events (commits, branches, PRs); it is discardable and rebuilds
  from truth, so a deleted or scrambled snapshot is not data loss.
- **Kubernetes level-triggered reconciliation.** The reconcile recomputes *full*
  placement from current observed state, not per-event deltas. A missed event
  self-heals on the next reconcile; a re-run against unchanged truth is a no-op.
- **Git's own reachability-derived notion of "merged".** "Done" is something you
  *observe* from the graph, not a flag someone sets.

It deliberately avoids the Terraform authoritative-mutable-state-file failure
mode, which had to bolt on state locking, drift detection, and refresh to make a
mutable shared state file safe.

## Authoritative evidence and precedence

`scripts/orchestrate-state.sh` is the derivation engine: for each task in a spec
it reads observable evidence and emits a tagged record (task id, derived state,
and the evidence that decided it). It checks **git ground truth before any `gh`
query**, so when signals disagree git wins. The completion signals, in the order
the engine applies them, are:

1. **Commit / branch merge-reachability** (`git merge-base --is-ancestor`).
2. **The `Planwright-Task` trailer** on a reachable base commit.
3. **PR / merge state** via `gh` (only when a remote is configured).

If none of those marks the task done, the in-progress signals are, in order: a
**branch carrying commits**, an **open PR** (via `gh`), and finally a **fresh
runtime dispatch marker** (covering the pre-first-commit window).

Because git ground truth is checked first, a closed-unmerged PR whose work is
nonetheless reachable in the base derives as **Completed** (reality wins over PR
metadata). And a git-confirmed completion (a reachable merged branch or trailer)
while `gh` still reports the PR open is **flagged** as a contradiction on the
derivation's output stream rather than silently resolved, so the corruption guard
(and a human) can see it.

The four derived states map to sections like this (see the hook contract in
[conventions.md](conventions.md#the-tasks-pr-sync-hook-contract-req-k12-req-b11)
for the full table):

| Derived state | Section |
| --- | --- |
| `completed` | `## Completed` |
| `in-progress` | `## In progress` |
| `ready` / `blocked` | `## Forward plan` |

The human-owned sections (`## Awaiting input`, `## Deferred`, `## Out of scope`)
are sticky: the derivation never relocates their blocks.

## The runtime dispatch marker (D-3)

A branch with zero commits is not yet evidence of work in flight (the derivation
counts a branch *with commits*). The runtime marker covers exactly that gap: the
window between branch-create and the branch acquiring its first commit.

It is a durable, timestamped marker file, one per task, in the spec's runtime
orchestration-state directory (`<spec-dir>/.orchestrate/markers/<id>` by default,
overridable with the `PLANWRIGHT_ORCH_STATE_DIR` environment variable). The
per-spec advisory lock lives beside it at `<spec-dir>/.orchestrate.lock`, not
under the markers directory.

Branch-first ordering is also fail-safe: a dispatch that crashes after acquiring
the lock but before creating the branch leaves **neither** branch nor marker, so
the task derives **Ready** and is cleanly re-dispatched.

The marker is timestamped so it cannot wedge a task forever. A marker older than
the configured staleness threshold whose branch still carries no commits is
treated as **stale**: the derivation reverts the task to Ready. This closes the
crash-after-marker-before-first-commit wedge, and it is safe precisely because
dispatch writes no authoritative state, so re-dispatching costs nothing. The
threshold is the [`stale_marker_threshold`](options-reference.md) option.

## The commit trailer (D-2)

Commits carry a `Planwright-Task: <spec>/<id>` footer trailer, the same
mechanism as `Signed-off-by:`. It is the durable completion anchor for the cases
branch-reachability cannot prove done: it survives branch deletion, and it lets
solo work committed straight to `main` (with no task branch at all) still derive
as Completed. `/execute-task` stamps it automatically; for manual or solo
commits, add it yourself. The full convention, including the manual-commit forms,
is in [conventions.md](conventions.md#commit-trailer-d-2-req-c14).

## The single writer (D-1, REQ-B1.1)

`scripts/tasks-pr-sync.sh` (the reconcile) is the **sole writer** of `tasks.md`
section placement. No other skill, hook, or tower hand-edits which section a
derivable task block occupies. This is distinct from task-*definition* authoring
(creating and editing task blocks and the Forward plan), which remains the
authoring skills' role (`/spec-draft`, `/spec-kickoff`). `/orchestrate` and
`/execute-task` write the per-block `Status` / `Last activity` annotations (which
are excluded from the spec content anchor and ride along with the block), but
they do **not** move blocks between sections; the reconcile derives placement.

The reconcile is:

- **Level-triggered and idempotent.** A second run against unchanged truth is a
  byte-identical no-op; a scrambled, flattened, or conflict-marked snapshot
  reconciles to the same canonical placement.
- **Conflict-safe.** A git-conflicted `tasks.md` is regenerated from the
  derivation, never resolved by `ours` / `theirs` / `union`.
- **Atomic.** The rewrite is a same-directory temp file renamed into place, so a
  racy stale lock-break cannot tear `tasks.md` under concurrent reconcile.

It runs two ways: the `tasks-pr-sync` hook fires on `gh pr create` / `gh pr
merge` for a convention-named branch; the same script's direct form,
`tasks-pr-sync.sh reconcile <spec-dir>`, is what `/orchestrate --bookkeeping`
drives for events the hook dropped on a busy lock. A single advisory lock
(`scripts/orchestrate-lock.sh`) serializes both, so a busy lock is a clean no-op
that the next `--bookkeeping` pass reconciles.

Because the snapshot is intentionally allowed to lag live truth between
reconciles, the structural-corruption guard (`scripts/check-ledger.sh`) fails
only on signatures the reconcile would *never* produce (a block in a section its
own evidence contradicts, a mis-sort, a malformed or duplicated block, more than
one `Status` line on a block). A well-formed snapshot that merely lags an
in-flight task **passes**: freshness is the reconcile's job, not the guard's.

## No remote (solo and prototyping)

Working with no remote configured is a **first-class** path, not a degraded one.
With no `origin` and no PRs (or no `gh` on PATH at all), the derivation runs
end-to-end from local git plus the trailer plus the marker: the `gh` probe is
skipped silently, nothing errors on the missing remote, and the ledger stays
correct as a solo session drives a spec forward.

A remote that *is* configured, with `gh` on PATH, but whose `gh` query fails
(auth, network, rate-limit) degrades to the **same** git-only derivation and
surfaces a `degraded` record, rather than wedging a task or corrupting state. A
missing `gh` binary is not this degraded case: like a missing remote, it takes
the silent first-class path above and emits no `degraded` record.

## The squash / rebase-merge caveat (risk R2)

Branch merge-reachability is one of the completion signals, and a squash or
rebase merge defeats it: the merged commit is a new commit, so the original task
branch is no longer an ancestor of `main`.

- **With a remote**, this is covered: the merged-PR signal via `gh` derives the
  task as Completed regardless of how it was merged.
- **Solo, with no remote**, completion then relies on the `Planwright-Task`
  trailer **surviving the squash**. A squash merge preserves the footer only if
  the squashed commit message keeps it. If you squash-merge solo work, keep the
  `Planwright-Task` trailer in the resulting commit message (GitHub's squash UI
  lets you edit it; a local squash should carry the trailer forward), or the task
  will not derive as Completed from git alone.

A related failure (risk R1): solo work whose branch was deleted *and* whose
trailer is missing or mistyped derives as deps-met-but-no-evidence. The
corruption guard flags that case so it does not silently under-complete.

## Configuration

The thresholds this model relies on, with safe defaults, are in the
[options reference](options-reference.md):

- `stale_lock_threshold`: when a per-spec advisory lock is treated as stale.
- `stale_marker_threshold`: when a runtime marker whose branch has no commits is
  treated as stale, reverting the task to Ready.

Every option in `config/defaults.yml` has a row there;
`scripts/check-options-reference.sh` fails CI on an undocumented option.
