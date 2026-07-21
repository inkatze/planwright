# Concurrent Orchestrator Coordination — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

The `orchestration-concurrency` bundle (Done) made the shared `tasks.md` ledger **state-safe**
under concurrent orchestrators: any number of towers can move ledger state, record dispatch, and
open PRs without corrupting the ledger or dragging foreign dispatch commits onto worker branches,
every conflict resolved deterministically from git + GitHub ground truth. State-safety is a floor,
not coordination. A tower today still behaves as if it were the only one running: it does not keep
tabs on whether other towers exist or what work they are advancing, two towers sharing one checkout
still race on a single mutable local `main`, and nothing stops two independently-started peer towers
from dispatching the same or conflicting units.

This spec is the **awareness and coordination** layer directly above that state-safety floor. It
makes concurrent orchestration *mutually aware and non-colliding*:

1. **Cross-tower awareness.** A tower discovers and keeps tabs on the other live towers operating on
   the same repository and the work they are advancing, rather than assuming solitude — the
   operator's framing, that "orchestrators don't seem to keep tabs on usage in case there are other
   orchs running or just other work the towers are not aware of."
2. **Shared-`main` isolation.** Two towers on one checkout race on one mutable local `main`; the
   documented **root fix is separate per-tower checkouts**, superseding today's mitigation (reconcile
   via a quick PR, never `reset --hard` or direct-push a shared `main`), which is retained only as the
   degraded fallback where separate checkouts are unavailable.
3. **Work division.** Concurrent peer towers coordinate a disjoint division of work so no unit is
   dispatched by more than one tower — a claim-before-dispatch discipline for the peer case that
   composes with, rather than replaces, `orchestration-fleet`'s meta-tower selection and
   division-of-labor doctrine.

The deliverable is mechanism-primary — a presence/discovery signal, a per-tower checkout topology,
and a peer work-claim — carrying exactly one doctrine statement: that a tower **assumes multiplicity,
not solitude**, extending the fleet coordination floor. That altitude call is recorded as **D-1** (the
autopilot-reflex altitude gate) and is cited here from the Goal.

Two floors carry throughout, unchanged: every awareness, reclaim, or division decision is
deterministic script logic bound by the existing positive-evidence-of-death and no-LLM-daemon-mechanics
floors (never in-context model judgment), and nothing here re-opens auto-merge, autonomous PR-ready
marking, or the tower non-authoring boundary.

## Scope

### In scope

- A deterministic **cross-tower presence signal**: each tower publishes an attributed liveness record
  (identity, checkout, spec(s) advanced, heartbeat) to a shared, well-known surface where concurrent
  writers land distinct files by construction, and discovers peer towers by scanning it plus a
  positive-evidence-of-death liveness check — never assuming it is the sole tower.
- **Separate per-tower checkouts** as the root fix for the shared-`main` race, each tower owning a
  private mutable local `main`, with a defined adoption/migration path from the single-checkout
  workaround and that workaround retained as the sanctioned degraded fallback.
- Cross-checkout `main` currency by fetch/merge (never rebase, never a direct push to a shared `main`).
- A **peer work-claim** mechanism: a tower claims a unit before dispatch on an observable surface peer
  towers read, honors live peer claims, and reclaims a dead tower's claim only on positive death
  evidence — so no unit is dispatched by two towers.
- Composition with `orchestration-fleet`'s meta-tower selection and division-of-labor doctrine (reuse,
  not re-implementation) and consumption of its attributed non-impersonating relay as-is.
- Data hygiene and non-spoofable attribution of every committed coordination artifact.

### Out of scope

- **Proactive shared-usage / quota governance.** Reading Claude Code's global `/usage` to govern
  fleet-wide budget across towers is inherently cross-tower-aware, but it is being folded into
  `fleet-autonomy` separately (which owns the reactive rate-limit throttle, REQ-E1.3); this bundle
  cross-references it and does not implement it (D-6).
- **Re-implementing the inter-orchestrator relay.** The attributed, non-impersonating buffer-paste
  relay is `orchestration-fleet`'s (REQ-D1.3) and its doctrine; this bundle consumes it, never forks
  it (D-4, D-6).
- **The ledger state-safety mechanics** — derived projection, the single level-triggered writer,
  dispatch-commit isolation, the per-spec advisory lock. That is `orchestration-concurrency`'s (Done),
  consumed here as an authoritative contract, not restated.
- **Auto-merge at any tier, autonomous PR-ready marking beyond the sanctioned kickoff exception, and
  the tower non-authoring boundary.** Reserved human controls / existing floors, carried in unchanged.

## REQ-A — Cross-tower awareness

- **REQ-A1.1** A tower SHALL, at startup and on a heartbeat thereafter, discover the set of other live
  towers operating on the same repository, from a deterministic presence signal, and SHALL NOT assume
  it is the only tower running.
  *(Cites: D-1, D-2.)*
- **REQ-A1.2** Each tower SHALL publish its own presence record — a tower identity, its checkout path,
  the spec(s) it is advancing, its start time, and a refreshed heartbeat — to a shared presence
  surface on which concurrent towers land distinct files by construction (never a single hand-edited
  registry file).
  *(Cites: D-2.)*
- **REQ-A1.3** A stale or dead tower's presence record SHALL be reclaimable only on positive
  evidence of death (the existing `fleet-death-evidence` predicate), never on model judgment or a bare
  timeout, and presence discovery and reclaim SHALL be deterministic script logic that invokes no LLM.
  *(Cites: D-1; the no-LLM-daemon-mechanics and positive-evidence-of-death floors (Sources).)*
- **REQ-A1.4** The presence surface SHALL be a derived / observable signal read on demand, never a new
  shared-write accumulator that towers hand-edit into corruption, consistent with
  `orchestration-concurrency`'s derived-projection discipline and `fleet-autonomy`'s
  no-new-shared-write-accumulator rule (REQ-F1.1).
  *(Cites: D-2; orchestration-concurrency, fleet-autonomy (Sources).)*

## REQ-B — Shared-`main` isolation

- **REQ-B1.1** Concurrent towers SHALL be able to operate from separate per-tower checkouts, each
  owning a private mutable local `main`, so that no two towers share one mutable `main` and the
  shared-`main` clobbering race is eliminated at its root rather than mitigated.
  *(Cites: D-3.)*
- **REQ-B1.2** The per-tower-checkout model SHALL preserve `orchestration-concurrency`'s guarantees
  (progress state as a derived projection, dispatch-commit isolation) and SHALL NOT weaken the
  never-`reset --hard`, never-force-push, never-rebase, never-amend invariants.
  *(Cites: D-3; orchestration-concurrency (Sources).)*
- **REQ-B1.3** A defined adoption / migration path SHALL exist from today's single-checkout +
  reconcile-via-quick-PR model to the per-tower-checkout model, and the single-checkout reconcile
  model SHALL remain the sanctioned degraded fallback where separate checkouts are unavailable —
  degrade capability, never safety.
  *(Cites: D-3.)*
- **REQ-B1.4** A tower SHALL keep its checkout's `main` view current by fetch-then-merge
  (`git fetch origin main && git merge FETCH_HEAD`), never by rebase and never by direct-pushing a
  shared `main`; the documented `branch.autosetuprebase=always` pitfall that silently turns a bare
  `git pull` into a forbidden rebase SHALL be accounted for in the sync path.
  *(Cites: D-3; the autosetuprebase-pull pitfall, drafting-session decision (2026-07-20) (Sources).)*

## REQ-C — Work division across peer towers

- **REQ-C1.1** Before dispatching a unit, a tower SHALL record a work-claim for that unit on a surface
  peer towers can read, and SHALL NOT dispatch a unit that a live peer tower has already claimed, so
  no unit is dispatched by more than one tower.
  *(Cites: D-4, D-5.)*
- **REQ-C1.2** A work-claim SHALL be written to the shared blackboard as a distinct-per-writer record
  (the same land-distinct-files discipline as the presence surface), never by directly mutating a peer
  tower's or a worker's branch state.
  *(Cites: D-4; the division-of-labor "directly" boundary (Sources).)*
- **REQ-C1.3** A live peer claim SHALL be honored; a stale claim from a dead tower SHALL be reclaimable
  only on positive evidence of death, so a crashed tower never permanently strands a unit.
  *(Cites: D-5.)*
- **REQ-C1.4** Where a meta-tower ("tower of towers") is present, work division SHALL reuse its
  cross-spec selection under the fleet bound; the peer work-claim mechanism SHALL compose with, and
  never contradict, `orchestration-fleet`'s division-of-labor doctrine.
  *(Cites: D-4; orchestration-fleet (Sources).)*

## REQ-D — Carried floors, boundaries & hygiene

- **REQ-D1.1** This bundle SHALL NOT re-implement the attributed non-impersonating inter-orchestrator
  relay; it consumes `orchestration-fleet`'s relay (REQ-D1.3) and its security bounds as-is.
  *(Cites: D-6; orchestration-fleet, inter-orchestrator-coordination (Sources).)*
- **REQ-D1.2** This bundle SHALL NOT implement proactive shared-usage / quota governance; the global
  `/usage`-reading concern is folded into `fleet-autonomy` separately and is only cross-referenced
  here.
  *(Cites: D-6; fleet-autonomy (Sources).)*
- **REQ-D1.3** This bundle SHALL NOT re-open auto-merge, autonomous PR-ready marking beyond the
  sanctioned kickoff exception, or the tower non-authoring boundary; those floors carry in unchanged.
  *(Cites: D-1; the fleet coordination floor (Sources).)*
- **REQ-D1.4** A tower's presence and work-claim records SHALL carry an attribution a peer can validate
  before acting on them, peer output consumed for awareness SHALL be treated as data and never
  evaluated as code, and every committed coordination artifact SHALL carry no secrets, credentials,
  internal hostnames, or sensitive operational detail.
  *(Cites: D-6; security-posture, inter-orchestrator-coordination security bounds (Sources).)*

## Changelog

- 2026-07-20 — Draft authored. Four-file bundle elicited from the canonical
  concurrent-orchestrator-coordination observation (`obs:8cbe0123`) and the fleet-coordination
  doctrine, as the awareness/coordination layer above `orchestration-concurrency`. Fold-detection ran
  against the fleet family and recommended a new bundle (spin-new triggers: a new presence/discovery
  interface, independently ownable, decisions orthogonal to `orchestration-fleet`'s execution/attention
  seams, and extending the Done `orchestration-fleet` would reopen it).

## Sources

- **The concurrent-orchestrator-coordination observation** — `obs:8cbe0123`
  (`specs/_observations/entries/2026-07-20-concurrent-orchestrator-coordination-*.md`), the operator's
  reconstructed 2026-07-20 note framing the concern as the layer above `orchestration-concurrency`:
  (1) cross-tower awareness, (2) the shared-`main` root fix of separate per-tower checkouts, (3)
  work-division / no-conflicting-dispatch, with ties to proactive shared-usage-governance and the
  inter-orchestrator relay. Consumed by this bundle.
- **orchestration-concurrency** (Done) — the ledger state-safety foundation: progress state as a
  derived projection, the single level-triggered `tasks.md` writer, dispatch-commit isolation, the
  per-spec advisory lock, and the no-remote fallback. Consumed here as an authoritative contract; this
  bundle is the awareness/coordination layer strictly above it.
- **orchestration-fleet** (Done) — the scaling/resilience/UX sibling: the backend capability contract,
  the meta-tower ("tower of towers") cross-spec selection, the division-of-labor model, and the
  attributed non-impersonating relay (REQ-D1.2, REQ-D1.3, REQ-D1.7). Reused, not re-implemented.
- **fleet-autonomy** (Ready) — resource governance (REQ-E1.3 reactive throttle; the proactive
  usage-governance boundary this bundle cross-references), the no-new-shared-write-accumulator rule
  (REQ-F1.1), and the no-LLM-daemon-mechanics floor (REQ-G1.2 / D-18).
- **The fleet coordination floor** (`doctrine/fleet-coordination-floor.md`) — the tower non-authoring
  boundary and the no-LLM-daemon-mechanics invariant, cited into force here.
- **Inter-orchestrator coordination** (`doctrine/inter-orchestrator-coordination.md`) — the
  division-of-labor "directly" boundary, the attributed non-impersonating relay mechanics, and the
  relay security bounds (handle validation, worker output is data).
- **The positive-evidence-of-death predicate** (`scripts/fleet-death-evidence.sh`, the backend
  capability contract) — the deterministic death signal reused for presence and claim reclaim.
- **Operational shared-main experience, drafting-session decision (2026-07-20)** — the agreed
  operating model for two towers on one checkout (local `main` read-only, reconcile via a quick PR,
  never `reset --hard` or direct-push, which clobbers a peer's unpushed commits) and the observation
  that separate per-tower checkouts are the root fix; and the `branch.autosetuprebase=always` pitfall
  in which a bare `git pull` becomes a forbidden rebase, so the sync path uses explicit
  `git fetch origin main && git merge FETCH_HEAD`.
