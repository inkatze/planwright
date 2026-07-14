# Orchestration Concurrency

The dispatch-record and reconciliation law behind `/orchestrate`'s stateless
step machine: what the durable dispatch record is, why the task branch always
precedes the runtime marker, what the per-spec lock does and does not cover,
and the tightened predicate governing how in-flight work is reconciled or
orphaned. The skill body keeps the ordered steps; this doc keeps the law and
its reasons, read at the dispatch-record window and the reconcile sweep.

Citations: orchestration-concurrency REQ-A1.1, REQ-A1.2 ·
orchestration-concurrency D-1, D-3, D-10 · REQ-F1.1, REQ-F1.9.

## Progress state is a derived projection (D-1)

The durable evidence of orchestration progress is git (task branches, the
`Planwright-Task` trailers reachable from the base), the runtime dispatch
markers, `gh`'s PR state, and the process/window list. The committed
`tasks.md` sections are a discardable read-model snapshot a reconcile sweep
rebuilds from that evidence on the next run — never the authoritative record.
This is what makes the tower disposable (D-38): any step may die mid-flight
without losing work, because nothing the step held in memory was load-bearing.

`/orchestrate` therefore commits no dispatch or progress state to `tasks.md`
(REQ-A1.1): `main` carries no dispatch commit, so a worker worktree cut from
it inherits nothing foreign — cross-task and cross-spec contamination is
impossible **by construction** (REQ-A1.2), not merely mitigated. Section
placement is refreshed off the dispatch path, by the level-triggered
reconcile alone (D-3), never at dispatch.

## The dispatch record and the locked window (D-10)

The dispatch record is the **task branch** (the first durable act) plus the
**timestamped runtime marker** — never a `tasks.md` write. The **per-spec
advisory lock** is not part of the record; it is the mechanism that
serializes the freshness-gate-plus-branch-create-plus-marker-write window so
that window is atomic against a concurrent tower or the `tasks-pr-sync` hook.
The lock path and mkdir protocol are shared with `tasks-pr-sync.sh` so the
two exclude each other. An `acquire` exit 1 (another live holder) is a
**clean no-op**: skip the step — another tower or the hook holds it, and
`--bookkeeping` reconciles anything dropped. The lock is released the moment
the write window closes, before dispatch, and is never held across execution:
it must never serialize the workers.

## Branch-first is fail-safe (D-3)

The branch is cut from `main` — which carries no dispatch commit, so the
worker base is pristine (REQ-A1.2) — and it precedes the marker, never the
reverse: a crash after lock-acquire but before branch-create leaves *neither*
branch nor marker, so the task derives Ready and is cleanly re-dispatched.
Branch names are built only from grammar-validated spec and task ids
(validated at pre-flight before they appear in any path or command).

## Marker semantics (D-3)

The marker covers the branch-create → first-commit window: a zero-commit
branch is not yet In-progress evidence (REQ-C1.1), so the marker holds the
task In progress until its branch carries a commit, after which branch evidence
supersedes it — and a stale orphan marker (marker without a surviving branch)
reverts the task to Ready. A bundle writes one marker per component task id,
never a single `<id>-<id>` marker. The writer (`orchestrate-marker.sh`)
grammar-validates each id and containment-checks the marker path before the
write, dropping a discardable, gitignored local artifact: no `tasks.md`
write, no commit. From branch + marker, `orchestrate-state.sh` derives the
task In progress.

## The reconcile sweep: refresh, PR-state-first, the orphan predicate

**Refresh the remote view first (best-effort).** Before rebuilding, run
`git -C <primary-checkout> fetch origin --quiet` — name the remote explicitly
so a checkout whose current branch tracks a fork does not fetch the wrong
remote and leave `origin/main` stale. This writes remote-tracking refs only:
no local branch or working-tree change. It closes a staleness gap: a merged
PR's `Planwright-Task` trailer reaches the remote first, and without the
fetch a genuinely-merged task can derive not-done and be re-dispatched (the
paycalc-services grammar-backed-explain case). The derivation already scans
the **union** of the base and its remote-tracking ref, so the fetch is
consumed read-only — no local `main` merge, and a worktree's branch state is
never touched. Failure is non-fatal and offline is first-class: no remote, no
`gh`, or a failing fetch degrades exactly like the `gh` probe (derive from
local git + trailer + marker, no noise). The freshness gate's local-main view
is unaffected: it intentionally tracks the operator's checked-out brief, not
the remote tip.

**PR state first.** For each `## In progress` entry, a PR in any state for
the unit's branch takes precedence: **merged → move to Completed** (with the
merged annotation); **open → leave In progress**. Only when no PR resolves
the unit is orphaning considered.

**Orphan only when all three hold** (else leave the entry alone):

1. the entry is **older than the grace threshold** (default: the stale-lock
   threshold, D-10);
2. the backend's **liveness is observable from this session** — a worker
   dispatched by *another* tower is not yours to judge; **print-backend units
   are exempt**: no process exists until the human pastes the command, so
   they age out only via the threshold **plus a human confirm**;
3. there is **positive evidence of death** — the recorded worker
   handle/window is **gone**, not merely unobserved. A dead tmux socket or a
   truncated process listing is *lost observability*, not observed death
   (2026-06-12 field trial: that exact confusion nearly orphaned live
   workers). Distinguish the two before orphaning; when you cannot, do not
   orphan.

**An orphan moves to `## Awaiting input`** with an orphan note — never left
In progress silently (which would stall dependents invisibly) and **never
auto-re-dispatched**: re-dispatch is a human call after they see the note.
