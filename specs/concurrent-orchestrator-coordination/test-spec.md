# Concurrent Orchestrator Coordination — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since every mechanism is deterministic script logic over
structured signals (per-tower record files, the `fleet-death-evidence` predicate, git state) and is
fixture-testable, including the negative assertions that carry the design (no shared-registry write path,
no LLM on discovery/reclaim, no rebase under `autosetuprebase`, no double-dispatch, no `eval` of peer
output). `[manual]` is reserved for the genuinely multi-checkout / multi-tower end-to-end confirmations
that a fixture cannot fully stand in for (two real towers on two checkouts). `[design-level]` covers the
checks whose signal is a design judgment rather than a mechanism's output — the doctrine statement
(REQ-A1.1's floor half, REQ-D1.3) and the scope-boundary cross-references (REQ-D1.1, REQ-D1.2).

## REQ-A — Cross-tower awareness

### REQ-A1.1 — Tower discovers peers, never assumes solitude [test + design-level]

`[test]`: a discovery fixture seeded with ≥1 live peer record asserts the tower's discovery scan returns
a non-empty live-peer set and the selection path does not take the sole-tower branch. `[design-level]`:
the assume-multiplicity floor statement (Task 1, D-1) exists and is cited from the Goal and by this REQ —
the doctrine half is verified by the artifact's existence and citation, not a runtime assertion.

### REQ-A1.2 — Per-tower record published, distinct-per-writer [test]

A fixture asserts a tower writes its own presence record (identity, checkout path, spec(s), start time,
heartbeat) as a single file in the shared directory, and that two concurrent writers land two distinct
files with no shared-registry write path invoked (grep-level assertion that no single-registry-file edit
exists on the publish path).

### REQ-A1.3 — Reclaim on positive death evidence only, no LLM [test]

Fixtures: (a) a heartbeating peer record classifies **live** (not reclaimable); (b) a record whose tower
is positively dead per `fleet-death-evidence.sh` classifies **reclaimable**; (c) a record that is merely
stale-by-timeout but not positively dead does **not** classify reclaimable; and an assertion that the
discovery / reclaim path invokes no LLM (no model-call in the code path).

### REQ-A1.4 — Presence is derived on demand, no new shared-write accumulator [test]

A fixture asserts the live-tower set is computed by scanning the record directory on demand and that no
committed or hand-maintained registry artifact is produced (no new shared-write accumulator file is
written); the publish path uses only the per-writer file form.

## REQ-B — Shared-`main` isolation

### REQ-B1.1 — Separate per-tower checkouts, private mutable `main` [manual + design-level]

`[design-level]`: the per-tower-checkout topology (each tower a separate checkout owning a private local
`main`) is documented (Task 3). `[manual]`: two real towers on two separate checkouts advance work
concurrently and neither observes the other's local-`main` state change — the shared-`main` race cannot
occur because there is no shared mutable `main` — confirmed once against the running setup.

### REQ-B1.2 — Invariants preserved [test + design-level]

`[design-level]`: a documented cross-check that the per-tower-checkout model leaves
`orchestration-concurrency`'s derived-projection state model and the never-`reset --hard` /
never-force-push / never-rebase / never-amend invariants intact (no invariant weakened). `[test]`: where
the sync path is scripted, a fixture asserts it performs no history-rewriting operation.

### REQ-B1.3 — Migration path and sanctioned fallback [design-level]

The adoption / migration path from single-checkout reconcile-via-quick-PR to per-tower checkouts is
documented, and the single-checkout reconcile model is explicitly documented as the sanctioned degraded
fallback where separate checkouts are unavailable (Task 3) — verified by the document's existence and
coverage.

### REQ-B1.4 — Fetch-then-merge sync, rebase refused under `autosetuprebase` [test]

A fixture configures `branch.autosetuprebase=always` and asserts the sync path's `main`-currency
operation resolves to a **merge** of `FETCH_HEAD` (explicit `git fetch origin main && git merge
FETCH_HEAD`), not a rebase, and that no direct push to a shared `main` occurs on the path.

## REQ-C — Work division across peer towers

### REQ-C1.1 — Claim before dispatch, no double-dispatch [test]

A two-tower fixture asserts tower B, selecting work, skips a unit tower A has recorded a live claim for,
so the unit is never dispatched twice; and that a tower records its claim before the dispatch step, not
after.

### REQ-C1.2 — Claim is distinct-per-writer, no direct peer mutation [test]

A fixture asserts a claim is written as a distinct-per-writer record (one file per claim/tower, no
collision) and that the claim path never writes into a peer tower's or a worker's branch state (no
cross-slice mutation on the path).

### REQ-C1.3 — Live claim honored, dead-tower claim reclaimable [test]

Fixtures: a live claiming tower's claim is honored (a peer skips the unit); a claim whose tower is
positively dead per `fleet-death-evidence.sh` is reclaimable (a peer may take the unit); a claim that is
stale-by-timeout but not positively dead is **not** reclaimable — so a crashed tower never permanently
strands a unit and a live one is never preempted on a guess.

### REQ-C1.4 — Composes with meta-tower selection [test + design-level]

`[design-level]`: a documented statement that the peer work-claim composes with, and never contradicts,
`orchestration-fleet`'s division-of-labor doctrine and meta-tower cross-spec selection. `[test]` (where
scriptable): a meta-tower-present fixture asserts division defers to meta-tower selection and the peer
claim does not double-assign.

## REQ-D — Carried floors, boundaries & hygiene

### REQ-D1.1 — Relay is consumed, not re-implemented [design-level]

Verified by review + cross-reference: this bundle introduces no relay implementation and cites
`orchestration-fleet`'s attributed non-impersonating relay (REQ-D1.3) as its channel — a grep confirms no
`send-keys` / relay-mechanics code is added here.

### REQ-D1.2 — Usage governance stays in `fleet-autonomy` [design-level]

Verified by review + cross-reference: this bundle implements no global-`/usage` reading or quota
governance and cross-references `fleet-autonomy` REQ-E1.3 as the owner — a grep confirms no usage/quota
mechanism is added here.

### REQ-D1.3 — Reserved floors carried unchanged [design-level]

The no-auto-merge, no-autonomous-PR-ready (beyond the sanctioned kickoff exception), and
tower-non-authoring boundaries are stated as carried-unchanged (Task 1, D-1) and no mechanism in this
bundle re-opens them — verified by the floor statement's existence and a review that no task crosses it.

### REQ-D1.4 — Attribution, data-not-code, artifact hygiene [test]

Fixtures: a seeded secret / internal hostname in a committed coordination artifact is flagged by the
hygiene guard and a clean artifact passes; a malformed / hostile tower-identity token is refused before
use (validated against a declared grammar, never interpolated); and peer output consumed for awareness is
handled as data with no `eval` / unquoted-expansion path (source-audit assertion).
