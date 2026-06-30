# Orchestration Concurrency — Requirements

**Status:** Done
**Last reviewed:** 2026-06-30
**Format-version:** 1

## Goal

Running more than one orchestrator concurrently — across different specs, or
even on multiple tasks of a single spec — drives shared orchestration state into
corruption: the `tasks.md` ledger mis-sorts, dispatch metadata lands on the
wrong task block, and worker branches drag sibling or foreign-spec dispatch
commits in as ancestors. Today the only repair is manual (merging intermediate
PRs to flush unpushed local-`main` bookkeeping, hand-resorting the ledger).

This spec makes concurrent orchestration **state-safe**: any number of
orchestrators advancing tasks across one or many specs can move ledger state,
record dispatch, and open PRs without corrupting the shared `tasks.md` ledger or
contaminating worker branches, with every conflict resolved deterministically
from authoritative PR/merge and commit ground truth rather than hand-merges. The
root fix is architectural: orchestration progress state stops being
hand-maintained mutable state that each tower edits, and becomes a **derived
projection** of observable git + GitHub evidence — the read-model pattern proven
in event sourcing and the level-triggered reconciliation proven in Kubernetes
controllers. The model is required to work with **no remote configured** so the
solo / prototyping flow is first-class, not an afterthought.

This is the state-safety foundation of a two-spec family; the scaling /
resilience / UX layer is the sibling `orchestration-fleet` spec, which consumes
this contract.

## Scope

### In scope

- Dispatch-commit isolation: worker worktrees never inherit sibling or
  foreign-spec dispatch commits.
- Progress state as a derived projection, never committed at dispatch.
- A single, idempotent, level-triggered writer of `tasks.md` section placement.
- Authoritative-state derivation from observable evidence (PR/merge state,
  commit/branch reachability, a commit trailer, a runtime dispatch marker), with
  a defined precedence and a no-remote fallback.
- Deterministic conflict resolution that regenerates placement from ground truth.
- Advisory-lock correctness: one lock primitive, sound stale-break.
- Corruption / drift guards wired into CI.
- A `/spec-kickoff` amendment to `bootstrap` reconciling its "`tasks.md` is the
  canonical state record" contract with the derived-snapshot model.

### Out of scope

- **The scaling / resilience / UX layer** — pluggable & autodetected backends,
  orchestrator self-management (context budget, auto-heal handover),
  meta-orchestration, inter-orchestrator coordination protocol, approachability.
  All of it is the sibling `orchestration-fleet` spec (Sources).
- **Anchor-drift / kickoff-freshness false-halts.** A distinct subsystem (the
  brief↔content anchor, not the `tasks.md` ledger) with a single-editor cause;
  a separate fast-follow, not this spec.
- **Auto-merge at any tier.** Merge is a reserved human control, permanent —
  carried in unchanged from bootstrap.
- **Selection policy** (critical-path / guard-first ordering). This spec changes
  how state is *represented and derived*, not which ready unit is *chosen*.
- **The Maximal variant** (dropping the `tasks.md` section snapshot entirely and
  the spec-format meta-spec change it implies). Deferred as the sanctioned future
  graduation if the fleet spec demands it (D-1).

## REQ-A — Dispatch-commit isolation & derived progress state

- **REQ-A1.1** `/orchestrate` SHALL NOT commit dispatch or progress state to
  `tasks.md`. The **task branch** — created as the first durable act of dispatch
  — together with the **per-spec advisory lock** SHALL be the dispatch record.
  *(Cites: D-1.)*
- **REQ-A1.2** A worker worktree SHALL be cut from a base carrying no dispatch
  commits, so it inherits no sibling or foreign-spec dispatch commit as an
  ancestor; a worker's PR diff SHALL contain only that worker's own changes.
  *(Cites: D-1; the dispatch-commit-contamination observations (Sources).)*
- **REQ-A1.3** The model SHALL function with **no remote configured**: progress
  state SHALL derive from local git and the runtime marker alone when no remote
  or PR exists, and SHALL use `origin`/PR signals when present without ever
  requiring them. Solo and prototyping flows are a supported path, not a
  degraded one. A remote that is configured but whose `gh` query fails (auth,
  network, rate-limit, or `gh` absent) SHALL degrade to the same git-only
  derivation and **surface** the degradation, never wedge a task or silently
  corrupt state.
  *(Cites: D-1; D-3; drafting-session decision (2026-06-26); kickoff lens pass (2026-06-26).)*

## REQ-B — Single idempotent level-triggered projector

- **REQ-B1.1** The reconcile pass (`tasks-pr-sync`) SHALL be the **sole writer**
  of `tasks.md` section *placement* (which section a task block occupies); no
  other skill, hook, or tower SHALL hand-edit section placement. This is distinct
  from task-*definition* authoring (creating/editing task blocks and the Forward
  plan), which remains the authoring skills' role (`/spec-draft`,
  `/spec-kickoff`); `/orchestrate` and `/execute-task` SHALL write no section
  placement. The writer SHALL update the snapshot **atomically**
  (write-temp-then-rename) so a racy stale lock-break cannot tear `tasks.md`
  under concurrent reconcile.
  *(Cites: D-1; D-4; the lock/writer-duplication observations (Sources).)*
- **REQ-B1.2** The projector SHALL be **level-triggered and idempotent**: it
  SHALL recompute the full placement from current observed truth rather than
  applying per-event deltas, and a second run against unchanged truth SHALL be a
  no-op. A missed event SHALL self-heal on the next reconcile.
  *(Cites: D-1; the edge-triggered ledger-drift observation (Sources);
  Kubernetes level-triggered reconciliation (Sources).)*
- **REQ-B1.3** The committed `tasks.md` sections SHALL be a **derived snapshot**,
  refreshed only by the reconcile / `--bookkeeping` pass and never at dispatch
  time; the snapshot SHALL be discardable and rebuildable from truth without
  data loss.
  *(Cites: D-1; D-3; event-sourcing read-model projections (Sources).)*

## REQ-C — Authoritative-state derivation & deterministic conflict resolution

- **REQ-C1.1** planwright SHALL derive each task's state from observable
  evidence: **Completed** when any strong signal holds (a merged PR via `gh`, OR
  the task branch is merge-reachable into the base, OR a base commit carries the
  task's `Planwright-Task` trailer); **In progress** when an open PR, an
  unmerged task branch with commits, or a **fresh** runtime dispatch marker is
  present (a timestamped marker older than the configured staleness threshold
  whose branch carries no commits is **stale**: it does NOT hold the task In
  progress, and the task reverts to Ready — safe because dispatch writes no
  authoritative state); otherwise **Ready** or **Forward** per dependency state.
  *(Cites: D-1; D-2; D-3; D-4.)*
- **REQ-C1.2** Derivation precedence SHALL favor git ground truth: when the work
  is reachable in the base, the task SHALL read Completed regardless of PR
  metadata; a genuine contradiction between signals SHALL be surfaced to the
  corruption guard (REQ-E1.x), never silently resolved. The derivation SHALL
  surface a contradiction on a defined, machine-readable channel (a tagged
  record in its output stream) that the corruption guard consumes; this channel
  SHALL exist independently of whether the guard is wired, so a contradiction is
  never silently dropped during the guard-first transition.
  *(Cites: D-1; kickoff lens pass (2026-06-26).)*
- **REQ-C1.3** On any `tasks.md` merge conflict, placement SHALL be regenerated
  from the authoritative derivation and validated; it SHALL NOT be resolved by
  `ours`, `theirs`, or `union`.
  *(Cites: D-1; the multi-day ledger-drift observation (Sources).)*
- **REQ-C1.4** Commits SHALL carry a `Planwright-Task: <spec>/<id>` trailer in
  the message footer; `/execute-task` SHALL emit it (one trailer per task for a
  bundled commit), and the derivation SHALL read it via git's trailer mechanism.
  The trailer is the durable, cross-flow completion anchor that survives branch
  deletion and solo direct-to-`main` commits.
  *(Cites: D-2.)*

## REQ-D — Advisory-lock correctness

- **REQ-D1.1** A **single** advisory-lock primitive SHALL be shared by
  `/orchestrate` and the `tasks-pr-sync` hook; the acquire / stale-break logic
  SHALL NOT be duplicated across implementations.
  *(Cites: D-4; the duplicated-lock observation (Sources).)*
- **REQ-D1.2** The per-spec lock SHALL provide mutual exclusion for state moves
  and a sound stale-break at the configured threshold. The task branch ref SHALL
  serve as the natural fence: because a lock holder writes no authoritative state
  (D-1), a stale holder that acted after its lease expired cannot corrupt derived
  state, so full fencing tokens are unnecessary.
  *(Cites: D-4; D-1; distributed-locking / fencing prior art (Sources).)*

## REQ-E — Corruption & drift guards

- **REQ-E1.1** A guard SHALL detect **structural corruption** in the committed
  `tasks.md` snapshot — placement/state signatures the level-triggered reconcile
  would never produce from any evidence (a task placed in a section its own
  evidence contradicts, a mis-sort, a malformed or duplicated block) — and SHALL
  fail loudly at commit / CI time. The guard SHALL NOT fail on the snapshot's
  **intentional lag** behind live truth: the snapshot is refreshed only at
  reconcile (D-1, D-3), so a well-formed snapshot merely trailing a not-yet-
  reconciled in-flight task is correct, not corrupt. Freshness is the reconcile
  pass's responsibility (REQ-B1.2), not the guard's.
  *(Cites: D-1; D-3; drafting-session decision (2026-06-26).)*
- **REQ-E1.2** A lint SHALL detect the residual corruption signature of more than
  one `Status` line per task block.
  *(Cites: D-1; the duplicate-dispatch-metadata observation (Sources).)*
- **REQ-E1.3** The guards SHALL be wired into the project's CI / pre-commit
  checks so a corrupt or drifted ledger blocks merge.
  *(Cites: D-1.)*

## REQ-F — Robustness & framework-script safety

- **REQ-F1.1** The derivation, dispatch, and lock scripts SHALL treat all parsed
  evidence as data, never code. The `<spec>/<id>` parsed from a `Planwright-Task`
  trailer, and any spec/task identifier used to construct a branch name, ref
  pattern, marker path, or lock path, SHALL be validated against its declared
  grammar (the spec-id pattern `^[a-z0-9][a-z0-9-]*$`; the task-id grammar
  `^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$`, per D-36 / `doctrine/spec-format.md`)
  **before use**, and every derived marker/lock path SHALL be
  containment-checked after canonicalization **before any read or write**.
  Malformed or hostile input is a clean refusal (the task is skipped and flagged,
  not dispatched/completed), never an executed command or an out-of-tree path.
  *(Cites: security-posture; kickoff lens pass (2026-06-26).)*

## Sources

- **Drafting session with Diego (2026-06-25 / 2026-06-26).** Scope-shape (two-spec
  family, foundation first), the derived-projection decision and its endpoint
  analysis, the commit-trailer choice, and the no-remote / solo requirement were
  decided live; choices made in session that mint no D-ID are cited as
  `drafting-session decision (<date>)`.
- **The orchestration-state observations** in `specs/_observations/opportunities.md`:
  dispatch-commit contamination of worker branches (2026-06-16, 2026-06-17);
  multi-day `tasks.md` ledger drift from edge-triggered merge interleaving
  (2026-06-15); state-move corruption — wrong-block / duplicate dispatch metadata
  (2026-06-12); advisory-lock duplication across `orchestrate-lock.sh` and the
  hook (2026-06-12); `${CLAUDE_PLUGIN_DATA}` as a durable runtime-state home
  (2026-06-11).
- **Prior art (research, 2026-06-25).** Event sourcing — projections / read
  models as discardable derivations of an authoritative event log. Kubernetes
  controllers — level-triggered, idempotent reconciliation; status derived from
  observed state; missed events self-heal. Martin Kleppmann, *How to do
  distributed locking* — leases and fencing tokens; the stale-holder hazard.
  Terraform's authoritative mutable state file is cited as the cautionary
  counter-example the derived-projection model avoids.
- **The `orchestration-fleet` sibling spec.** The scaling / resilience / UX layer
  that consumes this state-safety contract.
- **The `bootstrap` spec.** The founding spec where `/orchestrate`,
  `tasks-pr-sync`, the advisory lock, and the "`tasks.md` as canonical
  orchestration state record" contract originate; this spec hardens that
  machinery and amends that contract (D-5).
