# Orchestration Concurrency — Design

**Status:** Draft
**Last reviewed:** 2026-06-26
**Format-version:** 1

Origin-tag legend: `N` = new decision minted in this bundle; `N (extends
<foreign>)` = a new decision extending a foreign-namespace decision named in the
body (for example `bootstrap D-38`). The load-bearing decision (D-1) was reached
with the human after explicit prior-art research; alternatives and the rejected
endpoints are recorded so the reasoning survives.

## Decision log

### D-1: Progress state is a derived projection, never committed at dispatch  (N (extends bootstrap D-38))

**Decision:** `/orchestrate` never writes dispatch or progress state to
`tasks.md`. The **task branch** (created as the first durable act of dispatch)
plus the **per-spec advisory lock** are the dispatch record. `tasks.md` section
placement (Completed / In progress / Forward plan / …) is a **read-model
snapshot**, reconciled idempotently and level-triggered from authoritative
evidence — {PR/merge state, commit/branch reachability, the `Planwright-Task`
trailer, the runtime dispatch marker} — off the worker's critical path. Because
`main` carries no dispatch commits, a worker worktree cut from it inherits
nothing foreign, so cross-task and cross-spec contamination is impossible by
construction. The committed `tasks.md` keeps its sections (no spec-format
change); they are a derived snapshot, not hand-maintained truth.

**Alternatives considered:**
- **Minimal — keep committing placement via a single idempotent projector.**
  Rejected: it still commits a volatile ledger to `main`, so contamination is
  only *mitigated* (it relocates to the projector's own commits) and still needs
  a base-ref resolution and a remote for clean worker diffs; it under-delivers on
  the no-remote / solo requirement.
- **Maximal — drop the volatile sections from the committed `tasks.md`
  entirely**, holding only stable task defs and rendering status to an on-demand
  uncommitted view. Deferred, not rejected: it is the *same engine* as the chosen
  option minus the snapshot, but it ripples into the spec-format meta-spec + the
  validator and retires the hook's role. It is the sanctioned future graduation
  if the `orchestration-fleet` spec's scale demands it.
- **Push dispatch commits to `origin/main` immediately.** Rejected: a
  direct-push of bookkeeping to the default branch hits the two-tower
  clobber hazard, needs a remote, and needs a push-retry loop on concurrent
  pushes — while still not embracing the projection principle.

**Chosen because:** it eliminates the contamination root cause *by construction*
rather than relocating it; it works with no remote configured (the solo /
prototyping flow is first-class); and it matches well-proven prior art —
event-sourcing read-model projections (discardable, rebuildable from the log),
Kubernetes level-triggered idempotent reconciliation (status derived from
observed state, missed events self-heal), and git's own reachability-derived
notion of "merged" — while deliberately avoiding the Terraform
authoritative-mutable-state-file failure mode (which had to bolt on state
locking + drift detection + refresh). It keeps the meta-spec untouched, and
Maximal stays a clean later graduation.

### D-2: Task reference via a discreet commit trailer  (N)

**Decision:** Commits carry a `Planwright-Task: <spec>/<id>` trailer (for example
`orchestration-concurrency/3`) in the commit-message footer — the same mechanism
as `Signed-off-by:`. `/execute-task` emits it automatically; it is recommended
for manual / solo commits. It is unambiguous across specs, survives branch
deletion, is parsed via git's native trailer support
(`git interpret-trailers` / `git log --format='%(trailers:key=Planwright-Task)'`),
and a bundled commit carries one trailer per task. It is discreet by design —
footer only, never the subject line.

**Alternatives considered:**
- **Reuse the existing `(Task N)` commit-subject convention.** Rejected: it is
  ambiguous across specs (Task 9 of which spec?), looser to parse, and was never
  designed as a machine signal.
- **Branch-reachability only, with no commit convention.** Rejected: it breaks
  the moment a merged task branch is deleted, and cannot see solo work committed
  straight to `main` without a task branch.

**Chosen because:** the trailer is the durable, cross-flow completion anchor.
Branch reachability and PR state are richer when present, but only the trailer
survives branch deletion *and* covers solo direct-to-`main` commits — the exact
flexibility the no-remote requirement (REQ-A1.3) needs.

*(Note: distinct from the no-Claude-attribution commit convention — this is a
functional machine signal, not authorship.)*

### D-3: Reconciliation & selection mechanics  (N)

**Decision:** Three mechanics fall out of D-1 and are fixed here.
- **Runtime dispatch marker.** A durable, local marker lives in the advisory-lock
  directory (`${CLAUDE_PLUGIN_DATA}` is the home under plugin delivery, with the
  writer-mode fallback the resolvers use). It covers only the sub-second window
  between lock-acquire and branch-create; once the branch exists, branch
  evidence supersedes it.
- **Snapshot refresh.** The committed `tasks.md` snapshot is refreshed only by
  the reconcile / `--bookkeeping` pass, level-triggered from truth, never at
  dispatch.
- **Selection reads live truth.** `orchestrate-select` consumes the live
  derivation (not the possibly-stale committed snapshot), so a task that is
  in-flight or already Completed is never re-dispatched.

**Alternatives considered:**
- **A separate, bespoke dispatch ledger file as the marker.** Rejected: the
  advisory-lock dir already exists and is the natural home; a second store is
  redundant machinery.
- **Selection reads the committed snapshot.** Rejected: a stale snapshot would
  let two towers dispatch the same unit — the precise race this spec exists to
  prevent.

**Chosen because:** the marker covers exactly the gap branch evidence cannot, and
no longer; refreshing the snapshot off the dispatch path is what makes worker
diffs pristine; and selecting against live truth closes the double-dispatch race
without any new coordination protocol.

### D-4: One advisory-lock primitive; the branch ref is the fence  (N (extends bootstrap D-10))

**Decision:** Collapse the duplicated advisory-lock logic
(`orchestrate-lock.sh` and the `tasks-pr-sync` hook's inline lock) into one
primitive used by both. It provides per-spec mutual exclusion for state moves and
a sound stale-break at the configured threshold. No fencing tokens are added: the
task branch ref is the natural fence, and because a lock holder writes no
authoritative state (D-1), a stale holder acting after lease expiry cannot
corrupt the derived ledger.

**Alternatives considered:**
- **Add Kleppmann-style fencing tokens.** Rejected as unnecessary here: fencing
  exists to stop a stale holder from corrupting the protected resource, but D-1
  removes the holder's ability to write authoritative state at all, so the hazard
  the token guards against does not arise.
- **Leave the two lock implementations and document the shared protocol.**
  Rejected: two encodings of one primitive drift; the observation that flagged
  the duplication explicitly asks for one primitive.

**Chosen because:** one primitive removes the drift risk, and D-1 shrinks the
lock's correctness burden enough that the simpler design is also the safe one.

### D-5: Reconcile bootstrap's canonical-record contract by amendment  (N (extends bootstrap))

**Decision:** D-1 softens bootstrap's "`tasks.md` doubles as the canonical
orchestration state record" into "`tasks.md` sections are a derived snapshot;
the canonical state is the live derivation." Rather than leave the two specs
disagreeing, this spec amends bootstrap through a `/spec-kickoff` delta
(changelog entry + re-anchor), performed as part of Task 8.

**Alternatives considered:**
- **A forward-note only**, leaving bootstrap's wording and reconciling later.
  Rejected by the human: the contract genuinely changes meaning, so it is amended
  properly rather than left contradictory.

**Chosen because:** the amendment ritual is the sanctioned path for a contract
that changes meaning across an Active sibling; doing it in-spec keeps the two
bundles consistent at merge time instead of accruing a known disagreement.
