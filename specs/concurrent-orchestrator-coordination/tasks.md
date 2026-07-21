# Concurrent Orchestrator Coordination — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Five tasks. Task 1 (the coordination-floor doctrine statement and the D-1 altitude record) is
foundational: every other task cites it, so it dispatches first. Task 5 (the coordination-artifact
hygiene guard) protects every committed presence/claim artifact and, per the
guard-infrastructure-first selection rule, outranks the critical path once Task 1 lands. The top
mechanism wins are Task 2 (the cross-tower presence signal) and Task 3 (the per-tower checkout root
fix); Task 4 (the peer work-claim) reuses Task 2's presence identity and land-distinct-files surface,
so it depends on Task 2. Task 3 is independent of Task 2. All tasks depend on Task 1. The critical path
is Task 1 → Task 2 → Task 4; Task 3 and Task 5 run in parallel after Task 1.

## Tasks

### Task 1 — Coordination-floor doctrine statement & altitude record

- **Deliverables:** The assume-multiplicity coordination-floor statement (a tower keeps tabs on peer
  towers and coordinates division rather than assuming solitude), written as an extension of
  `fleet-coordination-floor.md` and recorded as the D-1 altitude record cited from the Goal; the carried
  floors stated with citations (positive-evidence-of-death and no-LLM-daemon-mechanics for all reclaim /
  discovery paths; the no-auto-merge / no-autonomous-ready / tower-non-authoring boundaries unchanged,
  REQ-D1.3); and the scope-boundary statement (D-6) naming `fleet-autonomy` as usage-governance owner and
  `orchestration-fleet` as relay owner. No new mechanism — this task fixes the altitude and the floors the
  other tasks build on.
- **Done when:** the doctrine statement exists and is cited by REQ-A1.1 and from the Goal as the D-1
  altitude record; the carried floors and the D-6 boundary are stated with their citations; the spec
  validator passes on the bundle; CI passes.
- **Dependencies:** none
- **Citations:** D-1, D-6 · REQ-A1.1, REQ-D1.3
- **Estimated effort:** 1 day

### Task 2 — Cross-tower presence signal (publish, discover, liveness)

- **Deliverables:** A per-tower presence record written to a shared, well-known directory as one file
  per tower (identity, checkout path, spec(s) advanced, start time, heartbeat), refreshed on a heartbeat;
  a deterministic discovery scan that enumerates peer records and applies the `fleet-death-evidence.sh`
  predicate to classify each as live or reclaimable; and integration so a tower runs discovery at startup
  and on its heartbeat. No shared registry file, no LLM on the discovery/reclaim path, no new committed
  state artifact (the live-tower set is derived on demand).
- **Done when:** a fixture with N per-tower record files resolves exactly the live subset via the
  death-evidence predicate (a positively-dead tower's record is classified reclaimable, a heartbeating
  one live); concurrent writers are shown to land distinct files with no collision (no shared-registry
  write path exists); the discovery scan invokes no LLM and issues no backend-specific pane/process scrape;
  a tower that finds ≥1 live peer does not behave as sole tower (asserted via the selection path in Task 4,
  or a standalone flag until then); the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-1, D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4
- **Estimated effort:** 2 days

### Task 3 — Per-tower checkout model, migration path & cross-checkout `main` currency

- **Deliverables:** The documented per-tower-checkout topology (each tower a separate checkout with a
  private mutable local `main`, coordinating via `origin` and the presence/claim surfaces); a defined
  adoption / migration path from the single-checkout + reconcile-via-quick-PR model, with that model
  retained as the sanctioned degraded fallback; and the cross-checkout `main`-currency sync path using
  explicit `git fetch origin main && git merge FETCH_HEAD` (never rebase, never a direct push to a shared
  `main`), accounting for the `branch.autosetuprebase=always` pitfall that turns a bare `git pull` into a
  forbidden rebase.
- **Done when:** the per-tower-checkout model and its migration/fallback path are documented and
  verified against `orchestration-concurrency`'s derived-projection and never-rewrite-history invariants
  (no invariant weakened); the sync path is demonstrated to fetch-then-merge and to refuse / avoid a
  rebase even under `branch.autosetuprebase=always` (a fixture asserts the resulting operation is a merge,
  not a rebase); the degraded single-checkout fallback is explicitly documented as sanctioned; the
  validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4
- **Estimated effort:** 2 days

### Task 4 — Peer work-claim (claim-before-dispatch, death-evidence reclaim)

- **Deliverables:** A work-claim mechanism: a tower writes a distinct-per-writer claim record for a unit
  (unit id, claiming-tower identity, timestamp) on the shared blackboard before dispatch, reusing Task 2's
  presence identity and land-distinct-files surface; a selection guard that skips any unit carrying a live
  peer claim; and reclaim of a claim only on positive evidence of the claiming tower's death via
  `fleet-death-evidence.sh`. The claim sits above `orchestration-concurrency`'s per-spec lock (it gates
  selection, not the ledger write) and composes with `orchestration-fleet`'s meta-tower selection where a
  meta-tower is present.
- **Done when:** a fixture with two towers shows the second skips a unit the first has live-claimed (no
  double-dispatch); a live claim is honored and a claim from a positively-dead tower is reclaimable (never
  on a bare timeout); reclaim invokes no LLM; the mechanism writes only distinct-per-writer records and
  never mutates a peer's or worker's branch state; the meta-tower-present path defers to meta-tower
  selection (asserted or documented-and-delegated); the validator and CI pass.
- **Dependencies:** 2
- **Citations:** D-4, D-5 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 2 days

### Task 5 — Coordination-artifact hygiene guard & cross-reference wiring

- **Deliverables:** A guard covering every committed coordination artifact (presence and claim records
  that land in a committed log, coordination/handover documents) for secrets, credentials, internal
  hostnames, and sensitive operational detail — wired into `mise run check` alongside the existing
  secret-scan coverage of fleet artifacts; attribution-validation of a peer's tower identity before it is
  acted on (the relay handle-validation discipline applied to presence/claim records); and the
  cross-reference wiring into `orchestration-concurrency` (state-safety floor), `orchestration-fleet`
  (relay + meta-tower), and `fleet-autonomy` (usage-governance boundary) so the seams are legible.
- **Done when:** the hygiene guard flags a seeded secret in a coordination artifact and passes a clean
  one; a malformed / hostile tower-identity token is refused before use (validated against a declared
  grammar, never interpolated); peer output consumed for awareness is treated as data (no `eval` /
  unquoted-expansion path); the cross-references resolve to the named bundles; the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-6 · REQ-D1.1, REQ-D1.2, REQ-D1.4
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
