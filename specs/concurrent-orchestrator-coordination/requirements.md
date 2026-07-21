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
  evidence — a best-effort optimization that keeps two towers from usually selecting one unit, above
  `orchestration-concurrency`'s branch-as-fence, which remains the authoritative guarantee that no unit
  is *dispatched* by two towers (REQ-C1.1).
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
- **Cross-machine / distributed peer towers.** The coordination surfaces (presence, work-claim) are a
  fixed machine-local path shared by co-located clones on one host; peer towers on separate machines
  are out of scope, since the death-evidence predicate (PIDs / tmux) is host-local and cannot classify
  a remote peer. Single-host co-location is an assumed precondition, not a mechanism this bundle builds.

## REQ-A — Cross-tower awareness

- **REQ-A1.1** A tower SHALL, at startup and on a heartbeat thereafter, discover the set of other live
  towers operating on the **same repository**, from a deterministic presence signal, and SHALL NOT
  assume it is the only tower running. Because the surface is a single host-wide machine-local path
  shared by every repository's clones on the host (REQ-A1.4), discovery SHALL scope to the current
  repository by the repository identity carried in each record (REQ-A1.2) — records for other
  repositories are not peers — and SHALL exclude the tower's own record, so a tower never counts itself
  as a peer.
  *(Cites: D-1, D-2.)*
- **REQ-A1.2** Each tower SHALL publish its own presence record — a **repository identity**, a tower
  identity, its checkout path, the spec(s) it is advancing, its start time, a refreshed heartbeat, the
  positive-evidence-of-death handle by which a peer confirms its liveness, and a marker distinguishing a
  meta-tower from an ordinary tower (`fleet-tower-marker.sh`) — to a shared presence surface on which
  concurrent towers land distinct files by construction (one file per tower, never a single hand-edited
  registry file). The **repository identity SHALL be derived from an origin-anchored signal** (a
  normalized `origin` remote URL, or an equivalent repository fingerprint) that is **identical across
  separate clones of the same repository**, and SHALL NOT be the local checkout path — otherwise two
  peer clones would compute different repository identities, fail to recognize each other as peers, and
  silently defeat cross-clone coordination (the whole point of the machine-local shared surface). Each
  record SHALL be written **atomically** (write-to-temp-then-rename) so a concurrent reader never
  observes a torn or partially-written record.
  *(Cites: D-2.)*
- **REQ-A1.3** A stale or dead tower's presence record SHALL be reclaimable only on positive
  evidence of death (the existing `fleet-death-evidence` predicate), never on model judgment, a bare
  timeout, or a stale heartbeat alone; a heartbeat's freshness is a hint, not a death proof. The
  liveness predicate has three outcomes — alive, positively-dead, and unknown/errored — and only
  **positively-dead** permits reclaim; an unknown or errored result is treated as not-dead (fail
  closed). Presence discovery and reclaim SHALL be deterministic script logic that invokes no LLM.
  Reclaim MAY include deleting the positively-dead tower's entire presence file (garbage collection on
  discovery); deleting a whole dead file is distinct from, and does not violate, the prohibition on
  editing a *live* peer's file content.
  *(Cites: D-1, D-2; the no-LLM-daemon-mechanics and positive-evidence-of-death floors (Sources).)*
- **REQ-A1.4** The presence surface SHALL be a derived / observable signal read on demand, never a new
  shared-write accumulator that towers hand-edit into corruption, consistent with
  `orchestration-concurrency`'s derived-projection discipline and `fleet-autonomy`'s
  no-new-shared-write-accumulator rule (REQ-F1.1). The surface SHALL be a fixed machine-local path
  outside every checkout, so all co-located peer clones on one host read the same directory (the
  single-host co-location assumption; cross-machine peers are out of scope, see Scope). The surface
  directory SHALL be **user-private** (owner-only permissions, e.g. `0700`): its access control is the
  mechanism that enforces the same-operator single-host trust model (REQ-D1.4), keeping the coordination
  surfaces readable and writable only by the operator whose sessions the peer towers are.
  *(Cites: D-2; orchestration-concurrency, fleet-autonomy (Sources).)*
- **REQ-A1.5** Presence discovery SHALL distinguish a healthy-but-empty presence surface (no peers
  currently live) from an absent, unreadable, or misconfigured one, and SHALL fail closed on the
  latter — surfacing an explicit error or an "unknown peer status" result — rather than reading a
  broken surface as evidence of solitude. A tower SHALL NOT take the sole-tower path on an unreadable
  surface. A **first-run bootstrap** where the surface directory does not yet exist SHALL be treated as
  the healthy-empty case: the tower creates the user-private directory (REQ-A1.4) and proceeds with an
  empty peer set — distinct from an existing surface path that cannot be read or is malformed, which
  fails closed. Publishing the tower's own record and discovering peers SHALL be ordered so a tower does
  not read the surface as absent between creating it and populating it.
  *(Cites: D-2; the fail-closed / degrade-capability-never-safety floor (Sources).)*
- **REQ-A1.6** Presence and claim records SHALL be parsed defensively: a record that is malformed,
  truncated, or otherwise unparseable SHALL fail closed for that record — it is skipped with a surfaced
  error and never interpreted as absent, empty, or "no such peer/claim" — so a corrupt record can never
  cause a tower to conclude a live peer or claim does not exist. This is the per-record analog of
  REQ-A1.5's surface-level fail-closed rule.
  *(Cites: D-2; the fail-closed / degrade-capability-never-safety floor (Sources).)*

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
  (`git fetch origin main && git merge --ff-only FETCH_HEAD`), never by rebase and never by
  direct-pushing a shared `main`; the documented `branch.autosetuprebase=always` pitfall that silently
  turns a bare `git pull` into a forbidden rebase SHALL be accounted for in the sync path. The merge
  SHALL be **fast-forward-only** (`--ff-only`): a per-tower private `main` is never directly committed
  to (commits ride task branches; merges reach `origin` via PR), so currency is always a fast-forward,
  and `--ff-only` surfaces any unexpected divergence as an explicit refusal rather than a silent merge
  commit. Because a plain `git merge FETCH_HEAD` always merges into the currently checked-out branch, the
  sync SHALL either run with `main` as the checked-out branch, or update the `main` ref without a checkout
  via a fast-forward-only ref update (`git fetch origin main:main`, which refuses a non-fast-forward by
  nature) — never a bare `git merge` while a worker branch is checked out, which would merge `origin/main`
  onto that worker branch. A failed `git fetch` SHALL fail closed — the tower SHALL NOT proceed on a
  silently-stale `main` — surfacing the fetch failure rather than treating the pre-fetch state as current.
  *(Cites: D-3; the autosetuprebase-pull pitfall, drafting-session decision (2026-07-20) (Sources).)*

## REQ-C — Work division across peer towers

- **REQ-C1.1** No unit SHALL be dispatched by more than one tower. That guarantee is **authoritative in
  `orchestration-concurrency`'s branch-as-fence**: a unit's dispatch creates a branch / PR whose
  existence on `origin` is the durable, cross-clone single-dispatch fence (origin accepts exactly one
  branch push per unit; a losing tower's push is rejected and it does not open a duplicate PR). A tower
  SHALL verify that no live branch / PR exists for a unit **immediately before dispatching it**, so a
  duplicate never reaches a worker even if the claim layer below races. The **work-claim is a best-effort
  optimization above that fence**: before dispatching, a tower claims the unit on the shared machine-local
  surface and skips a unit a live peer already holds, so peer towers rarely both select one unit and burn
  worker cycles — but the claim is **not** the correctness guarantee. A filesystem claim on a shared
  surface cannot be made authoritative under garbage-collection, stale-lock-break, and process-pause
  races (each such race degrades to at most wasted selection work, never a double dispatch, precisely
  because the branch-as-fence catches the duplicate before a second worker starts). The claim SHALL be
  taken by an **atomic, exclusive create-with-content** of a unit-keyed claim object on that surface: the
  claim object SHALL appear
  complete (carrying its owner identity and death handle, REQ-C1.2) in a single indivisible step, and
  the create SHALL fail if the unit-keyed object already exists — so the create itself is the serializer
  (the first tower's create succeeds and holds the unit; a losing tower's create fails, whereupon it
  reads the existing claim and skips), and no reader ever observes a claim lacking its contents. A bare
  `mkdir` provides the exclusivity but leaves a crash window in which the claim exists empty (REQ-A1.6
  would then fail it closed and strand the unit), and a plain temp-then-rename provides the atomic
  content but not the exclusivity (rename overwrites); the primitive SHALL provide both (e.g. a hardlink
  of a fully-written temp into the unit-keyed name, which fails if the name exists yet is complete the
  instant it appears). Because the surface is machine-local and shared by all co-located clones, this
  serializes peer towers **across separate per-tower checkouts**, where the checkout-local per-spec
  advisory lock cannot (that lock fences intra-clone ledger writes only, not cross-clone claim
  selection).
  *(Cites: D-4, D-5.)*
- **REQ-C1.2** A work-claim SHALL be a **unit-keyed** object (keyed by the unit's stable id under the
  repository scope), contended by construction so exactly one tower can hold a given unit — the inverse
  of the presence surface's distinct-per-writer discipline, which exists so tower records never collide.
  Each claim object SHALL carry, as part of its atomic create-with-content (REQ-C1.1), the claiming
  tower's identity and a **self-contained positive-evidence-of-death handle**, so a peer can evaluate the
  claimant's liveness from the claim alone — independent of the claimant's presence record, which
  presence GC may have already deleted. Claiming SHALL never directly mutate a peer tower's or a worker's
  branch state; a tower coordinates only by creating, reading, and (on positive death evidence, under the
  per-unit reclaim lock of REQ-C1.3) removing claim objects on the shared surface.
  *(Cites: D-4, D-5; the division-of-labor "directly" boundary (Sources).)*
- **REQ-C1.3** A live peer claim SHALL be honored; a claim SHALL be reclaimable only on **positive
  evidence of death** of the claiming tower (the `fleet-death-evidence` predicate), never on a bare
  timeout, a stale heartbeat alone, or an "unknown" liveness result — an unknown or errored death
  result SHALL be treated as not-dead (fail closed: never reclaim on a guess). Reclaim is a
  read → check → swap that cannot be collapsed into a single atomic filesystem step (unlike the initial
  claim), so it SHALL be serialized by a **per-unit reclaim lock held only across the fast swap, with the
  slow checks outside it**: (1) a tower reads the claim and its owner; a live or unknown owner is honored
  and the unit skipped, with no mutation whatsoever; (2) **outside any lock**, it confirms the owner is
  positively dead and that no live downstream dispatch artifact for the unit exists (a branch or open PR,
  per `orchestration-concurrency`'s branch-as-fence — death proves the *tower* dead, not its *worker*, so
  a tower that died after dispatching a still-running worker is not re-dispatched into duplicate work);
  (3) it acquires the per-unit reclaim lock (a `mkdir` lock on the surface, broken when stale by the same
  discipline `orchestration-concurrency`'s advisory lock uses; a busy lock means a peer is mid-swap, so
  the tower skips this round); (4) **under the lock it re-reads the claim** and proceeds only if it is
  still exactly the same dead owner's claim — if the claim has since changed, been released, or is now a
  live owner's, it aborts without mutating — then removes the dead claim and competes for the unit by the
  normal atomic create-with-content (REQ-C1.1), which yields a single holder even against a fresh
  claimant; (5) it releases the lock. The under-lock re-read is what makes reclaim safe: a reclaimer
  SHALL NOT remove or move a claim before confirming death (which would destroy a live claim), and SHALL
  NOT assume the claim is unchanged across the slow check (a fresh claimant may have taken the freed
  unit). The death check SHALL remain **outside** the lock, so the lock is never held across a subprocess
  (no livelock, no critical-section cost). The reclaim lock is a best-effort serializer, not an
  authoritative one: should it be stale-broken while a paused holder still intends to swap, or otherwise
  lost, the worst case is two towers proceeding toward dispatch — which the **pre-dispatch branch-as-fence
  check (REQ-C1.1) resolves to a single dispatch**, so the race degrades to wasted selection work, never a
  double dispatch. A live-but-hung tower's claim is honored and SHALL NOT be
  auto-reclaimed (it is not dead); recovering such a unit is an operator-intervention case, not an
  automatic one — so a *crashed* tower never strands a unit, while a *live* tower is never preempted on
  a guess.
  *(Cites: D-5, D-7; the positive-evidence-of-death floor, orchestration-concurrency's advisory-lock
  stale-break discipline and branch-as-fence (Sources).)*
- **REQ-C1.4** Where a meta-tower ("tower of towers") is present, work division SHALL reuse its
  cross-spec selection under the fleet bound; the peer work-claim mechanism SHALL compose with, and
  never contradict, `orchestration-fleet`'s division-of-labor doctrine. A meta-tower SHALL be
  distinguishable on the presence surface by the existing tower-marker (`fleet-tower-marker.sh`, carried
  in the presence schema, REQ-A1.2); where a meta-tower assigns disjoint slices, towers honor that
  assignment, and the peer claim is the mechanism for the independently-started, no-meta-tower case.
  *(Cites: D-4; orchestration-fleet (Sources).)*
- **REQ-C1.5** A tower SHALL release its claim on a unit when the unit is handed off (its worker is
  dispatched and its branch/PR exists, so the branch-as-fence takes over) or immediately on a dispatch
  failure, so claims do not outlive their coordination need and a dispatch failure never leaves a
  live-tower claim stranding the unit. Independently, **dead-tower claims SHALL be garbage-collected
  during discovery** — any claim whose owning tower is positively dead is removed when the surface is
  scanned, symmetric with the presence-file GC (REQ-A1.3) — not only along the reclaim path of a unit a
  peer happens to re-select. The discovery GC of a claim SHALL take the **same per-unit reclaim lock and
  under-lock re-read as the reclaim path (REQ-C1.3)** before unlinking: an unguarded GC `rm` would delete
  a claim a concurrent reclaimer had just swapped for a fresh live one, so the GC removes a claim only
  while holding the lock and only if it is still that same positively-dead owner's. A claim left by a
  tower that died after dispatch (whose worker may already have completed the unit, so no peer ever
  re-selects it) is therefore reclaimed by the locked discovery sweep rather than leaking on the surface
  forever.
  *(Cites: D-5, D-7.)*

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
  internal hostnames, or sensitive operational detail — **including the machine-local checkout path of a
  peer tower**, which is operational detail that SHALL NOT leak from the presence/claim surfaces into a
  committed artifact (a PR body, an audit log). Attribution validation is scoped to the same-operator,
  single-host trust model (peer towers are the operator's own co-located sessions): it SHALL
  grammar-validate the tower-identity token and refuse a malformed one before use, but is NOT required
  to defend against an adversarial peer forging another tower's identity.
  *(Cites: D-6; security-posture, inter-orchestrator-coordination security bounds (Sources).)*
- **REQ-D1.5** The coordination scripts (presence publish/discover, claim take/reclaim/release) SHALL
  meet planwright's framework-script security bars, since they parse records other sessions write to a
  shared surface: (a) **every parsed field consumed by the coordination logic SHALL be validated against
  its declared grammar before any use** — not only the tower identity, but the repository identity, the
  unit id, the spec id, the timestamps (start time and heartbeat, validated as well-formed timestamps),
  and in particular the **positive-evidence-of-death handle** (read from an untrusted peer record and
  passed to `fleet-death-evidence.sh`); a field that fails its grammar is refused, not coerced;
  (b) **path access SHALL be canonicalized and containment-checked**
  before any read, write, or unlink — the surface directory, each record path, the per-unit reclaim lock,
  and in particular the claim object a reclaim removes SHALL be confirmed to resolve inside the
  surface, so a crafted unit/tower id can never drive a delete or write outside it; (c) untrusted record fields echoed to a
  terminal or log SHALL pass the echo-discipline sanitizer (`scripts/echo-safety.sh`,
  `sanitize_printable`), so an embedded escape sequence in a peer record cannot drive the terminal.
  These are the enforcement of the same-operator trust model at the script boundary, complementing the
  user-private surface (REQ-A1.4).
  *(Cites: D-6; security-posture framework-script bars (Sources).)*

## Changelog

- 2026-07-20 — Draft authored. Four-file bundle elicited from the canonical
  concurrent-orchestrator-coordination observation (`obs:8cbe0123`) and the fleet-coordination
  doctrine, as the awareness/coordination layer above `orchestration-concurrency`. Fold-detection ran
  against the fleet family and recommended a new bundle (spin-new triggers: a new presence/discovery
  interface, independently ownable, decisions orthogonal to `orchestration-fleet`'s execution/attention
  seams, and extending the Done `orchestration-fleet` would reopen it).
- 2026-07-20 — Kickoff walkthrough (pre-merge, in place). Applied clarifications from the guided
  walkthrough: pinned the coordination surface to a fixed machine-local path with a single-host
  co-location assumption and added the cross-machine exclusion to Scope; made presence-GC-by-deletion
  of a positively-dead peer's file explicit in REQ-A1.3; made the in-lock claim ordering explicit in
  REQ-C1.1; scoped REQ-D1.4 attribution to the same-operator single-host anti-accident trust model;
  added the fail-closed-discovery requirement REQ-A1.5, so a broken presence surface is never read as
  solitude; hardened the Task 3 migration path with the per-clone env / stable `auth_sock`
  requirement; refocused the Task 5 hygiene guard on the commit-independent core; and broadened the
  design decision-domains walk to name concurrency and observability.
- 2026-07-20 — Kickoff halted (not signed off). The sign-off Discovery-Rigor lens pass surfaced a
  genuine inconsistency (the per-spec advisory lock is checkout-local, so the claim serialization does
  not hold across D-3's separate per-tower clones) plus a set of coordination-mechanics design gaps
  (claim lifecycle and reclaim serialization, death-evidence-handle location vs presence GC, repository
  identity in the presence schema, atomic writes / per-record corruption, meta-tower marker, git-sync
  edge cases, and the un-imported security-posture bars). Bundle-hygiene slips from the walkthrough
  edits were fixed. The design gaps are deferred to a `/spec-draft` rework (see `kickoff-brief.md`
  §8 and the recorded observation); the bundle stays Draft, no Draft→Ready flip.
- 2026-07-20 — `/spec-draft` rework (in place, Draft) closing the kickoff §8 backlog (`obs:3ecf4293`).
  **Keystone (operator decision, 2026-07-20):** the claim TOCTOU is closed by making the claim itself
  the serializer — an atomic, exclusive create of a unit-keyed claim object on the shared machine-local
  surface — rather than by the checkout-local per-spec lock, which cannot serialize separate-clone peers.
  (The exact create/reclaim primitives were hardened in the panel-review pass below.) This reverses the
  walkthrough's in-lock-ordering edit (S3) and its distinct-per-writer-for-claims premise: claims are now
  unit-keyed and contended-by-construction (REQ-C1.1, REQ-C1.2, D-5), and the presence/claim
  collision-semantics split (distinct-per-writer vs unit-keyed) gives the two surfaces a natural
  discriminator. Doctrine-resolved gaps folded in: claim lifecycle — release on
  handoff/dispatch-failure, dead-claim GC, reclaim gated on no-live-branch/PR downstream artifact so a
  dead tower's surviving worker is not double-dispatched, a self-contained death handle in each record,
  and a live-but-hung tower honored not auto-reclaimed (REQ-C1.3, REQ-C1.5, D-5, D-7); repository
  identity, self-exclusion, meta-tower marker, atomic writes, and a user-private surface in the presence
  schema (REQ-A1.1, REQ-A1.2, REQ-A1.4), first-run bootstrap vs fail-closed and per-record fail-closed
  parsing (REQ-A1.5, REQ-A1.6), death-predicate tri-state with unknown-≠-dead (REQ-A1.3); git-sync
  hardening — `--ff-only`, a `main`-checked-out precondition, and fetch-failure fail-closed (REQ-B1.4);
  and the framework-script security bars — echo-discipline, all-identifier grammar validation, path
  canonicalization + containment on record and reclaim-unlink paths, and the checkout-path
  no-leak rule (REQ-D1.4, REQ-D1.5). The bundle stays Draft; re-run `/spec-kickoff` for sign-off.
- 2026-07-20 — `/panel-review --nested` (gemini backend) hardening pass over the atomic-claim rework.
  The independent-model pass found the claim primitive was locality-correct but not fully atomic, and
  six confirmed design gaps were folded in: (G5, critical) reclaim was delete-then-recreate, which
  double-dispatches when concurrent reclaimers race — replaced with an **atomic rename-aside** so
  exactly one reclaimer wins (REQ-C1.3, D-5, D-7); (G3) a bare-`mkdir` claim left a crash window in
  which the claim exists without its death handle and strands the unit — replaced with an **atomic,
  exclusive create-with-content** (e.g. hardlink of a populated temp), aligning the claim write with the
  presence record's atomic-write discipline (REQ-C1.1, REQ-C1.2, D-5); (G4) dead claims were GC'd only
  along the reclaim path, leaking a completed-unit claim forever — now GC'd during **discovery**,
  symmetric with presence GC (REQ-C1.5, D-7); (G10) the death handle, read from an untrusted peer record
  and passed to a script, was not grammar-validated — added to REQ-D1.5's validated-field list; (S-A,
  self-critique) the **repository identity** was underspecified and, if keyed off the checkout path,
  would give separate clones different ids and silently defeat cross-clone peering — pinned to an
  origin-anchored signal identical across clones (REQ-A1.2, D-2); (G8) added the
  atomic-create-with-content and rename-aside-reclaim test coverage (test-spec REQ-C1.1, REQ-C1.3).
  Bundle stays Draft; re-run `/spec-kickoff` for sign-off.
- 2026-07-20 — `/panel-review --nested` iteration 2 (gemini) — reclaim safety corrected. The
  confirmatory pass found the iteration-1 rename-aside reclaim was **itself unsafe**: it moved the claim
  before confirming death (destroying a live claim if contested) and freed the unit during the slow
  death/artifact check (letting a fresh claimant double-dispatch). Reclaim is a read → check → swap whose
  check is slow, so it cannot be a single atomic filesystem step the way the initial claim is.
  **Operator decision (2026-07-20):** serialize reclaim with a **per-unit reclaim lock** held only across
  the fast swap — slow death/artifact checks outside it, an under-lock re-verification that the claim is
  still the same dead owner, then remove-and-compete via the normal create-with-content; initial claims
  stay lock-free (REQ-C1.2, REQ-C1.3, D-5, D-7). This is a deliberate, reclaim-scoped reintroduction of a
  lock, walking back Option 1's "no second lock" only where the lock-free schemes provably fail. Also
  folded in: grammar-validation generalized to **every** parsed field including the timestamps
  (REQ-D1.5); the `main`-currency sync tightened so a non-checked-out `main` is updated via
  `git fetch origin main:main` rather than a bare merge onto a worker branch (REQ-B1.4). Bundle stays
  Draft; re-run `/spec-kickoff` for sign-off.
- 2026-07-20 — `/panel-review --nested` iteration 3 (gemini) — the branch-as-fence reframe. The pass
  found two further reclaim races: the discovery GC's unguarded `rm` could delete a claim a reclaimer had
  just swapped for a fresh live one (I3a, Critical), and a stale-broken/paused reclaim-lock holder could
  clobber a live claim and double-dispatch (I3b, High). Root cause, converged across three rounds: a
  filesystem claim on a shared surface **cannot** be the authoritative no-duplicate-dispatch guarantee
  under GC / stale-break / pause races. **Operator decision (2026-07-20):** reframe to a two-layer model
  — `orchestration-concurrency`'s **branch-as-fence** (origin arbitrates one branch push per unit),
  verified immediately before every dispatch, is the authoritative guarantee; the claim + reclaim-lock is
  a **best-effort optimization** above it, so every residual filesystem-lock race degrades to wasted
  selection work, never a double dispatch (REQ-C1.1, D-5, D-7). Also folded in: the discovery GC takes
  the same per-unit reclaim lock and under-lock re-read as the reclaim path, so it never deletes a
  freshly-swapped live claim (I3a fix, REQ-C1.5). This closes the whole filesystem-claim race class by
  delegating correctness to the proven Done foundation rather than trying to make the claim airtight.
  Bundle stays Draft; re-run `/spec-kickoff` for sign-off.

## Sources

- **The concurrent-orchestrator-coordination observation** — `obs:8cbe0123`
  (`specs/_observations/entries/2026-07-20-concurrent-orchestrator-coordination-*.md`), the operator's
  reconstructed 2026-07-20 note framing the concern as the layer above `orchestration-concurrency`:
  (1) cross-tower awareness, (2) the shared-`main` root fix of separate per-tower checkouts, (3)
  work-division / no-conflicting-dispatch, with ties to proactive shared-usage-governance and the
  inter-orchestrator relay. Consumed by this bundle.
- **The kickoff-halt rework seed** — `obs:3ecf4293` (recorded 2026-07-20 by the halted
  `/spec-kickoff`), the coordination-mechanics backlog this rework closes: the checkout-local-lock
  inconsistency and the ~20 design gaps on two root axes (machine-local vs checkout-local surface;
  death-handle location + claim/presence lifecycle). Full detail in `kickoff-brief.md` §8. Consumed by
  this rework.
- **orchestration-concurrency** (Done) — the ledger state-safety foundation: progress state as a
  derived projection, the single level-triggered `tasks.md` writer, dispatch-commit isolation, the
  per-spec advisory lock (a `mkdir`-atomicity directory lock at `<spec-dir>/.orchestrate.lock`, broken
  when stale past a threshold, checkout-local — it fences intra-clone ledger writes, not cross-clone
  claim selection; the per-unit reclaim lock of REQ-C1.3 reuses the same `mkdir`-plus-stale-break
  discipline at the machine-local surface), the
  **branch-as-fence** dispatch discipline (a live branch / open PR for a unit is the durable evidence
  the unit is already in flight — reused by the reclaim guard, REQ-C1.3), and the no-remote fallback.
  Consumed here as an authoritative contract; this bundle is the awareness/coordination layer strictly
  above it. The claim mechanism (D-5) reuses the same class of atomic filesystem primitive at the correct
  (machine-local) locality: an atomic, exclusive create-with-content for the initial claim, and — because
  reclaim is a read-check-swap whose check is slow — the same `mkdir`-plus-stale-break lock discipline,
  scoped per unit, for reclaim.
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
- **security-posture** (`doctrine/security-posture.md`) — the artifact data-hygiene rule (committed
  artifacts carry no secrets, credentials, internal hostnames, or sensitive operational detail) and the
  framework-script security bars (never execute untrusted input, guard path access with
  canonicalization + containment, echo discipline via `sanitize_printable`). Cited by REQ-D1.4.
- **The fail-closed / degrade-capability-never-safety floor** (bootstrap REQ-K1.6/K1.7) — a
  broken, absent, or unavailable surface is a clean refusal or an explicit "unknown" result, never a
  silent wrong answer; capability degrades, safety never does. Cited by REQ-A1.5.
- **Operational shared-main experience, drafting-session decision (2026-07-20)** — the agreed
  operating model for two towers on one checkout (local `main` read-only, reconcile via a quick PR,
  never `reset --hard` or direct-push, which clobbers a peer's unpushed commits) and the observation
  that separate per-tower checkouts are the root fix; and the `branch.autosetuprebase=always` pitfall
  in which a bare `git pull` becomes a forbidden rebase, so the sync path uses explicit
  `git fetch origin main && git merge FETCH_HEAD`.
