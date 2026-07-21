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
   dispatched by more than one tower. The **authoritative** guarantee is a **machine-local work-claim
   keyed to the dispatched worker's liveness** (D-5, D-11): at dispatch a tower claims the unit by an
   atomic create-with-content on the shared machine-local surface — which, on the single-host co-location
   this bundle assumes, is both cross-clone and death-surviving — and the claim records the worker's own
   death handle and persists for the worker's run, so a crashed tower's unit is recovered by probing the
   *worker* directly (positively dead + no completion artifact → reclaim; unclassifiable → surfaced). The
   **origin ref is demoted to a best-effort double-PR guard** above that claim (D-8), not the correctness
   floor. The claim composes with, rather than replaces, `orchestration-fleet`'s meta-tower selection and
   division-of-labor doctrine.

The deliverable is mechanism-primary — a presence/discovery signal, a per-tower checkout topology, and a
worker-liveness-keyed peer work-claim — carrying **two doctrine statements**: that a tower **assumes
multiplicity, not solitude** (the primary altitude call), and a narrower companion on the tower→human
axis — a **merge-ready PR reaches the operator by deterministic push, LLM-poll being the fallback**
(mechanism owned elsewhere, REQ-D1.6). Both extend the fleet coordination floor; the altitude call is
recorded as **D-1** (the autopilot-reflex altitude gate) and cited here from the Goal.

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
- A **worker-liveness-keyed machine-local work-claim** as the authoritative no-duplicate-dispatch-and-no-
  strand guarantee: at dispatch, before any worker runs, a tower claims the unit by an atomic
  create-with-content on the shared machine-local surface (which, single-host, serializes co-located clones
  where the checkout-local lock cannot); the claim records the *worker's* death handle and persists for the
  worker's run, so it is both the cross-clone exclusion primitive and the recovery signal — reclaim on the
  worker positively dead + no completion artifact, unclassifiable liveness surfaced (REQ-C1.1, REQ-C1.3,
  D-11).
- A **best-effort origin double-PR guard** above that claim: at dispatch the tower also pushes the unit's
  task-branch ref to `origin` (expect-absent) as belt-and-suspenders for the surface-wiped-mid-flight case —
  **not** the correctness floor, so a reachable `origin` is **not** required for multi-tower correctness and
  no-remote multi-tower on one host does not fail open (REQ-C1.6, D-8).
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
- **The deterministic PR-ready-push mechanism.** The hook mapping a worker's ready-flip (`gh pr ready` /
  the GitHub MCP draft→ready path) to a record on the attention surface, plus the reclassification of that
  surface's `pr-ready` state from non-actionable to actionable, is owned by a separate `merge-currency-guard`
  spec (which also owns the stale/DIRTY-flip guard intercepting the same two surfaces, so one hook does
  both). This bundle carries only the companion doctrine line motivating it (D-1) and cross-references the
  mechanism (REQ-D1.6, D-6); it implements none of it.
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
  assume it is the only tower running. The surface is a single host-wide machine-local path shared by
  every repository's clones on the host (REQ-A1.4), partitioned into **one sub-surface per repository
  identity** (`<surface>/<repo-id>/`, matching the claims layout `<surface>/<repo-id>/claims/<unit-id>`,
  D-2); discovery SHALL scope to the current repository by **scanning only the current repo id's
  sub-surface**, with the repository identity carried in each record (REQ-A1.2) verified as a defensive
  cross-check rather than by filtering the entire host surface — the two descriptions are reconciled to
  the per-`<repo-id>` sub-surface as canonical. Discovery SHALL exclude the tower's own record (by tower
  identity, REQ-A1.7), so a tower never counts itself as a peer. To bound cost, discovery SHALL run on a
  **capped heartbeat cadence** and SHALL **cache each peer's liveness verdict for the pass** rather than
  invoking the death-evidence subprocess more than once per record per pass, so the per-record subprocess
  fan-out is bounded, not unbounded per beat.
  *(Cites: D-1, D-2.)*
- **REQ-A1.2** Each tower SHALL publish its own presence record — a **repository identity**, a **tower
  identity** (REQ-A1.7), its checkout path, the spec(s) it is advancing, its start time, a refreshed
  heartbeat, a positive-evidence-of-death handle by which a peer confirms its liveness, and a
  **meta-tower marker that is the record's own validated field** stamped from the tower's `--meta` mode —
  **not** `fleet-tower-marker.sh`, whose stored field is the orthogonal `unattended|interactive` recovery
  mode, never a meta/ordinary distinction — to a shared presence surface on which concurrent towers land
  distinct files by construction (one file per tower, never a single hand-edited registry file). The
  **death handle SHALL be one of the two forms `fleet-death-evidence.sh` accepts** — `process <pid>` or
  `tmux-window <session> <window>` — and a tower running under tmux (the fleet norm) SHALL publish the
  **reuse-resistant `tmux-window` handle** (the tmux server is authoritative and its window ids are not
  pid-reused), keeping `process <pid>` as the documented degraded fallback for a tower not under tmux
  (REQ-A1.3, D-2). The **repository identity SHALL be derived from an origin-anchored signal** (a
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
  editing a *live* peer's file content. The GC delete SHALL take the **same under-lock re-read guard as
  the claim GC** (REQ-C1.5): the sweep re-confirms, immediately before the unlink, that the file is still
  that same positively-dead tower's record, so a **dead-then-restarted** tower's *fresh live* record
  (same tower identity, new session) is never deleted out from under it — an unguarded `rm` would be that
  bug. Where a tower's death handle is the degraded bare-`process <pid>` form (REQ-A1.2), a **reused pid**
  can read as alive and cause the dead tower's record to be honored rather than reclaimed; this is an
  **availability-only** effect (a stale presence record merely over-counts peers, and for a work-claim the
  same handle ambiguity makes the worker's liveness *unclassifiable* → surfaced for operator reclaim, never
  double-dispatched, REQ-C1.3, D-11), never a safety failure, and is why the `tmux-window` handle is
  preferred where available.
  *(Cites: D-1, D-2; the no-LLM-daemon-mechanics and positive-evidence-of-death floors (Sources).)*
- **REQ-A1.4** The presence surface SHALL be a derived / observable signal read on demand, never a new
  shared-write accumulator that towers hand-edit into corruption, consistent with
  `orchestration-concurrency`'s derived-projection discipline and `fleet-autonomy`'s
  no-new-shared-write-accumulator rule (REQ-F1.1). The surface SHALL be a fixed machine-local path
  outside every checkout, so all co-located peer clones on one host read the same directory (the
  single-host co-location assumption; cross-machine peers are out of scope, see Scope). The surface
  directory SHALL be **user-private** (owner-only permissions, `0700`): its access control is the
  mechanism that enforces the same-operator single-host trust model (REQ-D1.4), keeping the coordination
  surfaces readable and writable only by the operator whose sessions the peer towers are. Because that
  permission bit *is* the trust enforcement, the surface SHALL be created with an **atomic, mode-explicit
  `mkdir`**, and a **pre-existing surface directory whose mode is over-broad** (group- or
  other-accessible) SHALL be **refused, not silently reused** — verify-or-refuse, so a mis-permissioned or
  attacker-planted surface can never quietly widen the trust boundary.
  *(Cites: D-2; orchestration-concurrency, fleet-autonomy (Sources).)*
- **REQ-A1.5** Presence discovery SHALL distinguish a healthy-but-empty presence surface (no peers
  currently live) from an absent, unreadable, or misconfigured one, and SHALL fail closed on the
  latter — surfacing an explicit error or an "unknown peer status" result — rather than reading a
  broken surface as evidence of solitude. On a fail-closed surface error the tower SHALL take the
  **defined recovery action of D-10: halt dispatch for the step** (report "unknown peer status") rather
  than the sole-tower path — because the claim surface shares the directory, a broken surface means the
  coordination layer is down, so dispatching blind is the exact collision this bundle prevents; solo
  dispatch is reserved for the genuine no-remote single-checkout posture, never a coordination-surface
  failure on a multi-tower host. A **first-run bootstrap** where the surface directory does not yet exist
  SHALL be treated as the healthy-empty case: the tower creates the user-private directory (REQ-A1.4) and
  proceeds with an empty peer set. Because a bare `ENOENT` cannot distinguish "never existed" (healthy
  first run) from "existed and then vanished" (a surface that must fail closed, not read as solitude), a
  **persistence sentinel** dropped at bootstrap SHALL make that distinction — its presence means the
  surface once existed, so a missing directory alongside a surviving sentinel fails closed. A
  **concurrent first-run `mkdir` that returns `EEXIST`** because a peer bootstrapped the surface a moment
  earlier SHALL be treated as **success, not an error** (the create is idempotent and order-independent,
  D-10). Publishing the tower's own record and discovering peers SHALL be ordered so a tower does not read
  the surface as absent between creating it and populating it.
  *(Cites: D-2, D-10; the fail-closed / degrade-capability-never-safety floor (Sources).)*
- **REQ-A1.6** Presence and claim records SHALL be parsed defensively: a record that is malformed,
  truncated, or otherwise unparseable SHALL fail closed for that record — it is skipped with a surfaced
  error and never interpreted as absent, empty, or "no such peer/claim" — so a corrupt record can never
  cause a tower to conclude a live peer or claim does not exist. This is the per-record analog of
  REQ-A1.5's surface-level fail-closed rule. Because a corrupt **claim** record cannot be
  liveness-checked at all (garbage collection must parse the owner and death handle to prove death), the
  fail-closed rule alone would honor it forever and strand its unit; because the atomic create-with-content
  (REQ-C1.1) means a reader never observes a transient torn claim, a parse failure is genuine corruption,
  so on the **first** parse failure the sweep SHALL **quarantine** the record per REQ-C1.5 (move it to a
  containment-checked dead-letter sub-surface and surface it for the operator) rather than waiting for
  repeated failures a stateless tower cannot count, so the unit becomes re-selectable rather than
  permanently and invisibly blocked (the run-3 Q1 strand). Under the authoritative worker-claim (D-11) this
  residual strand is availability-only, never a double dispatch; quarantine-on-first converts it from a
  permanent invisible block to an operator-visible, recoverable one.
  *(Cites: D-2; the fail-closed / degrade-capability-never-safety floor (Sources).)*
- **REQ-A1.7** The **tower identity** on which distinct-per-writer publication (REQ-A1.2) and
  self-exclusion (REQ-A1.1) both rest SHALL be derived by a specified, deterministic function, so two
  towers never compute one identity (a collision would let one overwrite a peer's record) and a tower
  never mistakes a peer for itself (which would drop a real peer from the set). The identity SHALL be the
  Claude **session id (UUID)** where present — unique per session, validated against the UUID grammar
  `fleet-tower-marker.sh` already enforces — falling back, where no session id is available, to a
  composite of **pid + process start-time + a checkout-path hash**; it SHALL NOT be the bare pid (reuse
  makes it non-unique over time) nor the checkout path alone (two towers on one checkout would collide,
  the single-checkout degraded fallback case). The chosen identity is the presence record's key and the
  self-exclusion discriminant.
  *(Cites: D-2.)*

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
  onto that worker branch. A `git fetch` failure SHALL be **classified before acting** (D-10): **no
  `origin` configured** is a configuration state — the tower runs the single-checkout **solo flow**
  (no cross-clone currency to maintain, no multi-tower), not an error — while a **transient fetch failure
  against a configured `origin`** fails closed: the tower surfaces the failure and SHALL NOT proceed on a
  silently-stale `main`, retrying on the next cycle. The blanket "a failed fetch fails closed" is split
  this way so the no-remote solo posture is never mis-treated as a transient error. A **`--ff-only` merge
  refusal** (a non-fast-forward, i.e. unexpected divergence on a private `main` that should only ever
  fast-forward) SHALL be **surfaced for the operator**; the tower SHALL NOT force, rebase, or reset to
  resolve it (the never-rewrite-history floor).
  *(Cites: D-3, D-10; the autosetuprebase-pull pitfall, drafting-session decision (2026-07-20) (Sources).)*

## REQ-C — Work division across peer towers

- **REQ-C1.1** No unit SHALL be dispatched by more than one tower. That guarantee is **authoritative in
  the machine-local work-claim, keyed to the dispatched worker's liveness (REQ-C1.2, D-5, D-11)**: at
  dispatch, before any worker runs, a tower claims the unit by an **atomic, exclusive create-with-content**
  of a unit-keyed claim object on the shared machine-local surface, and that claim records the worker's own
  reuse-resistant death handle and **persists for the worker's whole run**. Because the surface is
  machine-local and shared by all co-located clones (the single-host co-location assumption, REQ-A1.4), the
  create is an atomic **cross-clone** serializer — the first tower's create succeeds and holds the unit; a
  losing tower's create fails, whereupon it reads the existing claim and skips — precisely where the
  checkout-local per-spec advisory lock cannot serialize separate-clone peers (that lock fences intra-clone
  ledger writes only). The claim object SHALL appear complete (carrying its owner identity, the worker
  death handle of REQ-C1.2, and — for a cohesion bundle — the full set of member unit-ids it covers) in a
  single indivisible step, and the create SHALL fail if the unit-keyed object already exists, so no reader
  ever observes a claim lacking its contents. A bare `mkdir` provides the exclusivity but leaves a crash
  window in which the claim exists empty (REQ-A1.6 would then fail it closed and strand the unit), and a
  plain temp-then-rename provides the atomic content but not the exclusivity (rename overwrites); the
  primitive SHALL provide both (e.g. a hardlink of a fully-written temp into the unit-keyed name, which
  fails if the name exists yet is complete the instant it appears). The **origin task-branch ref (REQ-C1.6,
  D-8) is a best-effort double-PR guard above this claim, not the correctness floor**: it backstops only
  the coordination-surface-wiped-mid-flight case, so a mangled, absent, lagging, or never-reaped origin ref
  costs at most a redundant selection resolved by the authoritative claim, never a double dispatch and
  never a strand. This is the run-3 inversion of the prior "origin fence authoritative" framing: a passive
  ref carries no worker liveness, so it can neither reap a crashed worker's unit nor distinguish it from a
  live one (D-11).
  *(Cites: D-4, D-5, D-8, D-11.)*
- **REQ-C1.2** A work-claim SHALL be a **unit-keyed** object (keyed by the unit's stable id under the
  repository scope), contended by construction so exactly one tower can hold a given unit — the inverse
  of the presence surface's distinct-per-writer discipline, which exists so tower records never collide.
  Each claim object SHALL carry, as part of its atomic create-with-content (REQ-C1.1), the claiming tower's
  identity and the **dispatched worker's self-contained positive-evidence-of-death handle** (one of the two
  `fleet-death-evidence.sh` forms, REQ-A1.2 / REQ-D1.5), so a peer can evaluate the *worker's* liveness
  from the claim alone — independent of any presence record, which presence GC may have already deleted.
  The handle SHALL be the **worker's**, not merely the dispatching tower's: the tower is a disposable step
  machine that exits while its worker runs, so keying liveness on the tower would strand or double-dispatch
  the unit (D-7, D-11). When the claim covers a **cohesion bundle** (a task set dispatched to one worker
  under a lead branch/PR), it SHALL enumerate **every member unit-id** it covers, so a peer selecting any
  member — lead or non-lead — finds the unit claimed; no non-lead bundle member is left unfenced. Claiming
  SHALL never directly mutate a peer tower's or a worker's branch state; a tower coordinates only by
  creating, reading, and (on positive worker-death evidence, under the per-unit reclaim lock of REQ-C1.3)
  removing claim objects on the shared surface.
  *(Cites: D-4, D-5, D-11; the division-of-labor "directly" boundary (Sources).)*
- **REQ-C1.3** A live worker's claim SHALL be honored; a claim SHALL be reclaimable only on **positive
  evidence of death of the claim's *worker*** (the `fleet-death-evidence` predicate applied to the worker's
  recorded death handle, probed directly on the same host) **and** only when **no live completion artifact
  for the unit exists**. Where `origin` is configured, that artifact is an **open PR or commits on the
  unit's origin ref**, read **live** (`ls-remote`, never a possibly-stale checkout-local remote-tracking
  ref); a **transient `origin` read error fails closed** (treat as possibly-in-review, do not reclaim,
  retry next pass), but where **no `origin` is configured** (no-remote mode) no such artifact can exist, so
  reclaim proceeds on positive worker-death alone — a dead no-remote worker's local-only work was never
  durable (the no-remote-vs-transient split of D-10, mirroring the `fetch` case). Reclaim SHALL NOT fire on
  a bare timeout, a stale heartbeat, an
  "unknown" liveness result, or the *tower's* death alone — an unknown or errored death result SHALL be
  treated as not-dead (fail closed: never reclaim on a guess). The worker-and-artifact test distinguishes
  the two ways a worker can be dead: **died before opening its PR** (no artifact → the unit is unfinished →
  reclaim and re-dispatch) versus **exited after opening its PR** (artifact present → the work is in review
  or merged → do NOT reclaim; that unit is cleaned up by the discovery GC, REQ-C1.5, not reclaimed). Keying
  on the **worker** — not the tower, and not the passive origin ref — is the run-3 correction: the tower
  exits normally while its worker runs, and a zero-commit origin ref cannot tell a dead worker's ref from a
  live worker's not-yet-pushed one (D-7, D-11).
  Reclaim is a read → check → swap that cannot be collapsed into a single atomic filesystem step (unlike the
  initial claim), so it SHALL be serialized by a **per-unit reclaim lock held only across the fast swap,
  with the slow checks outside it**: (1) a tower reads the claim; a live or unknown **worker** is honored and
  the unit skipped, no mutation; (2) **outside any lock**, it confirms the worker positively dead and no live
  completion artifact; (3) it acquires the per-unit reclaim lock (a `mkdir` lock on the surface, broken when
  stale by the same discipline `orchestration-concurrency`'s advisory lock uses; a busy lock means a peer is
  mid-swap, so the tower skips this round); (4) **under the lock it re-reads the claim** and proceeds only if
  it is still exactly the same dead worker's claim — if the claim has since changed, been released, or is now
  a live worker's, it aborts without mutating — then removes the dead claim and competes for the unit by the
  normal atomic create-with-content (REQ-C1.1), which yields a single holder even against a fresh claimant;
  (5) it releases the lock. The under-lock re-read is what makes reclaim safe: a reclaimer SHALL NOT remove
  or move a claim before confirming the worker's death (which would destroy a live claim), and SHALL NOT
  assume the claim is unchanged across the slow check. The death/artifact check SHALL remain **outside** the
  lock, so the lock is never held across a subprocess (no livelock, no critical-section cost). The reclaim
  lock is a best-effort serializer, not the authoritative one: should it be stale-broken while a paused
  holder still intends to swap, the worst case is two towers competing to re-create the claim — which the
  **authoritative atomic create-with-content (REQ-C1.1) resolves to a single holder**, so the race degrades
  to wasted selection work, never a double dispatch.
  The guarantee this SHALL provide, stated to what the mechanism can actually deliver: **a unit whose worker
  is positively dead is always reclaimed (or GC'd, if its unit is already resolved), and a unit whose worker
  liveness is unclassifiable — an unknown/errored probe, or a degraded bare-pid handle rendered ambiguous by
  pid reuse — is surfaced for operator reclaim, never silently honored forever.** A live-but-hung worker (or
  its tower) is *alive*, so its claim is honored and SHALL NOT be auto-reclaimed; recovering that unit is an
  operator-intervention case. (This replaces the earlier absolute "a crashed tower never strands a unit,"
  which the mechanism cannot deliver for the unclassifiable case; the honest guarantee is
  positively-dead-always-reclaimed, unclassifiable-always-surfaced — closing the run-3 Q2 invisibility gap.)
  *(Cites: D-5, D-7, D-11; the positive-evidence-of-death floor, orchestration-concurrency's advisory-lock
  stale-break discipline (Sources).)*
- **REQ-C1.4** Where a meta-tower ("tower of towers") is present, work division SHALL reuse its
  cross-spec selection under the fleet bound; the peer work-claim mechanism SHALL compose with, and
  never contradict, `orchestration-fleet`'s division-of-labor doctrine. A meta-tower SHALL be
  distinguishable on the presence surface by the existing tower-marker (`fleet-tower-marker.sh`, carried
  in the presence schema, REQ-A1.2); where a meta-tower assigns disjoint slices, towers honor that
  assignment, and the peer claim is the mechanism for the independently-started, no-meta-tower case.
  *(Cites: D-4; orchestration-fleet (Sources).)*
- **REQ-C1.5** A tower SHALL **not** release its claim at dispatch; the claim **persists for the worker's
  whole run** (releasing at dispatch and handing the in-flight signal to the origin ref is the run-3
  orphan-worker strand). The claim is removed on one of two worker-keyed terminal transitions: (i) the tower
  removes it when its **worker has terminated on a resolved unit** (its PR merged / present, or the ledger
  marks the unit done); or (ii) the tower removes it immediately on a **dispatch failure before the worker
  launches**, since no worker exists to track, so a failed dispatch never leaves a claim stranding the unit.
  A removal `rm` that fails SHALL be surfaced and retried, not silently dropped; the unit is not stranded,
  since the discovery GC backstops it once the worker is positively dead — a bounded delay, never a permanent
  block. Independently, the discovery sweep SHALL **garbage-collect four residues**, each under the **same
  per-unit reclaim lock and under-lock re-read as the reclaim path (REQ-C1.3)** before unlinking (an
  unguarded GC `rm` would delete a claim a concurrent reclaimer had just swapped for a fresh live one, so
  every GC remove holds the lock and re-verifies identity):
  (a) **terminated-worker claims on a resolved unit** — any claim whose **worker** is positively dead and
  whose unit is resolved (PR merged/present or ledger-done) — symmetric with the presence-file GC (REQ-A1.3),
  not only along the reclaim path of a unit a peer happens to re-select, so a claim left by a tower that
  exited after its worker completed does not leak forever (a dead worker on an *un*resolved unit is the
  reclaim path of REQ-C1.3, not GC); (b) **stale per-unit reclaim locks** — a reclaim lock left by a
  reclaimer that crashed mid-swap, broken past the stale threshold by the same `mkdir`-plus-stale-break
  discipline the per-spec advisory lock uses, so a crashed reclaimer never wedges a unit's reclaim path
  permanently; (c) **orphan temp files** — a temp from an interrupted atomic create-with-content (the tower
  died between writing the temp and hardlinking it), swept past a threshold so abandoned temps do not
  accumulate and poison the scan (the temp SHALL be created **inside the surface directory**, same filesystem
  as the claim name, so the hardlink is atomic and cannot hit `EXDEV`); and (d) **aged dead-letter records**
  — quarantined records (below) past a TTL, so the dead-letter sub-surface itself does not grow unbounded
  (the run-3 Q2 residue). Distinct from these, a **corrupt (unparseable) claim record** cannot be
  liveness-checked at all; because the atomic create-with-content (REQ-C1.1) means a reader never observes a
  transient torn claim, a parse failure is genuine corruption, so the sweep SHALL **quarantine it on the
  first parse failure** — move it, under a containment-checked path, to a dead-letter sub-surface and surface
  it for the operator — rather than waiting for **repeated** failures across passes, which a
  stateless/disposable tower has no store to count (the run-3 Q1 strand). Quarantine-on-first makes the unit
  re-selectable and operator-visible immediately, without a blind delete of untrusted content (REQ-A1.6).
  Neither the claims surface nor the dead-letter sub-surface SHALL grow unbounded.
  *(Cites: D-5, D-7, D-11.)*
- **REQ-C1.6** At **dispatch**, before any worker runs, a tower SHALL **additionally** push the unit's
  task-branch ref to `origin` by an **atomic expect-absent compare-and-swap** (`git push
  --force-with-lease=refs/heads/<branch>:` with the **explicit all-zeros OID** as the must-be-absent
  expectation, hardened against any git build that treats the bare-empty form as unchecked; pushing the
  branch's **current local tip**, so an adopted worker-tip is fenced at its own base and does not later
  non-fast-forward) as a **best-effort double-PR guard** above the authoritative work-claim (REQ-C1.1, D-8,
  D-11) — **not** the correctness floor. Where reachable, `origin` arbitrates a single ref creator per unit,
  backstopping the one case the machine-local claim cannot: the coordination surface wiped or unavailable
  mid-flight. Because the guard is best-effort, its imperfections are **availability, not correctness**:
  (1) a **reachable `origin` is NOT required for multi-tower correctness** — the authoritative claim is the
  floor, so when `origin` is unreachable the guard simply **degrades to absent** (not attempted, nothing
  fails closed on its account), and no-remote multi-tower on one host does not fail open (the run-3 A3 fix);
  (2) the guard is most effective when both clones push the **same canonical ref name**
  (`planwright/<spec>/task-<id>`), which the two shipped dispatch backends reach differently —
  `fleet-dispatch-worktree.sh` creates the canonical branch **directly** (no post-launch rename), while the
  `claude --worktree` / tmux backend mangles slashed names and SHALL **rename to canonical before the guard
  push** — and where a rename occurs the tower SHALL **verify the pushed refname equals canonical or drop
  the guard for this unit** (fail *the guard*, not the dispatch — the claim is authoritative); (3) the guard
  push SHALL be sequenced **after the authoritative claim (REQ-C1.1) and before worker launch** in both
  backends, so a **lost or errored guard-push result never affects correctness** — the claim already holds
  the unit, dissolving the lost-CAS-ACK strand where a tower that wins the ref but loses the ACK would
  otherwise be unable to prove ownership. A divergent, absent, or never-reaped origin ref merely weakens
  the belt-and-suspenders; it never causes a double dispatch or a strand. The
  guard establishes no committed state on `main` (a task-branch ref at an existing commit, no history
  added), so it does not violate `orchestration-concurrency`'s no-dispatch-commit-on-`main` floor.
  *(Cites: D-8, D-11; orchestration-concurrency's no-dispatch-commit-on-main floor (Sources).)*

## REQ-D — Carried floors, boundaries & hygiene

- **REQ-D1.1** This bundle SHALL NOT re-implement the attributed non-impersonating inter-orchestrator
  relay; it consumes `orchestration-fleet`'s relay (`orchestration-fleet` REQ-D1.3) and its security
  bounds as-is.
  *(Cites: D-4, D-6; orchestration-fleet, inter-orchestrator-coordination (Sources).)*
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
  internal hostnames, or sensitive operational detail — **including both the machine-local checkout path
  and the death handle of a peer tower** (a pid, or a tmux session+window name), which are operational
  detail that SHALL NOT leak from the presence/claim surfaces into a committed artifact (a PR body, an
  audit log). Attribution validation is scoped to the same-operator, single-host trust model (peer towers
  are the operator's own co-located sessions): it SHALL grammar-validate the tower-identity token and
  refuse a malformed one before use, but is NOT required to defend against an adversarial peer forging
  another tower's identity.
  *(Cites: D-9; security-posture, inter-orchestrator-coordination security bounds (Sources).)*
- **REQ-D1.5** The coordination scripts (presence publish/discover, claim take/reclaim/release) SHALL
  meet planwright's framework-script security bars, since they parse records other sessions write to a
  shared surface: (a) **every parsed field consumed by the coordination logic SHALL be validated against
  its declared grammar before any use** — not only the tower identity, but the repository identity, the
  unit id, the spec id, the timestamps (start time and heartbeat, validated as well-formed timestamps),
  the **meta-tower marker** (a validated boolean; it drives the defer-to-authority decision, so an
  unvalidated value could mis-route division — REQ-A1.2, REQ-C1.4), the **checkout path**, and the
  **positive-evidence-of-death handle**, whose **declared grammar is exactly the two
  `fleet-death-evidence.sh` forms** — `process <pid>` (a positive integer, no leading zero, ≤10 digits)
  or `tmux-window <session> <window>` (that predicate's tmux charset, ≤128, no leading dash) — since the
  handle is read from an untrusted peer record and passed straight to `fleet-death-evidence.sh`; a field
  that fails its grammar is refused, not coerced; (b) **path access SHALL be canonicalized and
  containment-checked** before any read, write, `mkdir`, or unlink — the surface directory itself (so a
  **surface-root symlink** cannot redirect containment outside it), each record path, the per-unit
  reclaim lock, the quarantine dead-letter path, and in particular the claim object a reclaim removes
  SHALL be confirmed to resolve inside the surface, so a crafted unit/tower id can never drive a delete or
  write outside it; (c) untrusted record fields echoed to a terminal or log SHALL pass the echo-discipline
  sanitizer (`scripts/echo-safety.sh`, `sanitize_printable`), so an embedded escape sequence in a peer
  record cannot drive the terminal. These are the enforcement of the same-operator trust model at the
  script boundary, complementing the user-private surface (REQ-A1.4).
  *(Cites: D-9; security-posture framework-script bars (Sources).)*
- **REQ-D1.6** This bundle SHALL record — as a **coordination-floor doctrine line only, not a mechanism** —
  that a **reserved-human moment (a merge-ready PR) reaches the operator by a deterministic push, with an
  LLM tower polling GitHub as the *fallback*, never the sole path** (the companion doctrine of D-1, on the
  tower→human attention axis: the same "don't rely on a single fragile actor" discipline as
  assume-multiplicity). The **mechanism** that realizes it — the hook mapping a worker's ready-flip
  (`gh pr ready` / the GitHub MCP draft→ready path) to a record on the attention surface, and the
  reclassification of that surface's `pr-ready` state from non-actionable to actionable — SHALL be **owned
  by a separate `merge-currency-guard` spec** (which also owns the stale/DIRTY-flip guard intercepting the
  same two ready surfaces, so one hook does both and the interception is not duplicated) and is only
  **cross-referenced** here. This bundle SHALL NOT implement that mechanism (D-1, D-6).
  *(Cites: D-1, D-6; the fleet coordination floor, the deterministic-pr-ready-push observation (Sources).)*

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
- 2026-07-21 — `/spec-draft` rework (run 2, in place, Draft) closing the kickoff §8 run-2 backlog
  (`obs:7dd7eb45`, ~39 findings). **Keystone (operator decision, 2026-07-21): Option A — the fence at
  dispatch.** Kickoff run 2 halted on a second inconsistency on the same work-division correctness axis:
  the iteration-3 reframe (entry above) named `orchestration-concurrency`'s branch-as-fence authoritative,
  but that fence rode the **local** task-branch ref, which reaches `origin` only at PR-open — so across
  D-3's separate clones there is no fence during the whole worker run, and a claim lost in the
  dispatch→first-push window is a genuine double **dispatch**, not "wasted selection work" (REQ-C1.1's
  claim, contradicted by Task 4's own "rejected origin push" Done-when). This rework **leads with the
  correctness model** (design.md's new "Correctness model" preamble) rather than re-mechanizing the claim
  primitive (the pattern behind both halts): the authoritative guarantee is now the **dispatch-time origin
  fence** — an atomic compare-and-swap task-branch-ref create on `origin` at dispatch, live cross-clone
  from dispatch and death-surviving (new **D-8**, **REQ-C1.6**; REQ-C1.1 / REQ-C1.3 / REQ-C1.5 and D-5 /
  D-7 repointed from the local branch-as-fence to it). Closes the double-dispatch window (#1) and the
  orphan-worker reclaim blind spot (#2), and corrects the REQ-C1.1↔Task-4 contradiction (#3). Preconditions
  stated: reachable `origin` required for separate-clone multi-tower (no-remote is the single-checkout
  solo flow, #5), byte-identical canonical branch names, not `claude --worktree` mangling (#4). Also folded
  in from the backlog: **fail-closed recovery actions** given a numbered home (new **D-10**) —
  no-remote-vs-transient fetch split, `--ff-only` refusal, broken-surface halt-dispatch, absent-vs-vanished
  persistence sentinel, concurrent-bootstrap `EEXIST`-is-success, release-`rm` retry (#6–#12);
  **corrupt-claim quarantine** and **orphan-temp / stale-reclaim-lock discovery GC** (#13, #14, #35,
  REQ-A1.6, REQ-C1.5); **`tmux-window` death handle preferred** over the reuse-prone bare-pid, residual
  strand framed availability-only under the fence (#16, REQ-A1.2, REQ-A1.3); **death-handle grammar
  declared** as the two `fleet-death-evidence.sh` forms and added to the no-leak set (#17, #18);
  **tower-identity derivation specified** (session UUID, fallback composite; new **REQ-A1.7**, #19);
  **presence-GC guarded** with the claim GC's under-lock re-read (#20); **`0700` verify-or-refuse + atomic
  create** (#21); the security bars + attribution model given a numbered home (new **D-9**;
  REQ-D1.4 / REQ-D1.5 / Task 5 repointed from the mis-cited D-6, #34), the **meta-tower marker corrected**
  to the presence record's own field (not `fleet-tower-marker.sh`) and added — with the checkout path and
  surface-root containment — to the validated-field list (#22, #23, #24); **discovery cadence cap +
  per-pass liveness cache** (#25); **scan-scope reconciled** to the per-`<repo-id>` sub-surface (#26).
  Test-spec hardened: structural atomicity assertions (#27), the `git fetch origin main:main` and
  origin-fence harnesses (#28, #31), the two-tower manual proof anchored (#29), positive relay/usage
  consumption assertions (#30), the meta-tower test committed to one form (#32). Hygiene batch: dangling
  `orchestration-fleet REQ-D1.7` → REQ-D1.3 with external refs namespaced (#33, #39), non-resolving `obs:`
  seed sources corrected (#36, #38), REQ-D1.1 cites D-4 (#37). The bundle stays Draft; re-run
  `/spec-kickoff` for sign-off.
- 2026-07-21 — `/spec-draft` rework (run 3, in place, Draft) closing the kickoff §8 run-3 backlog
  (`obs:c2270479`, ~18 findings). **Keystone (operator decision, 2026-07-21): Architecture A — the
  authoritative floor is the worker-liveness machine-local claim; `origin` is demoted.** Kickoff run 3
  halted on a third inconsistency on the same work-division correctness axis: the run-2 fence-at-dispatch
  design (entry above) made a **passive `origin` ref** authoritative, but that ref is zero-commit until
  PR-open and carries no worker liveness, so it cannot distinguish a dead worker's ref from a live worker's
  not-yet-pushed one, and its stale-break/reaper stayed checkout-local — so a crashed tower strands its unit
  (violating REQ-C1.3's "never strands"), the mirror image of the run-2 halt. Root diagnosis, converged
  across three runs: **there is no liveness-free authoritative floor**, and the authoritative signal must be
  cross-clone *and* death-surviving *for what it tracks* — the **worker**. This rework **inverts the
  authority** (new **D-11**): the machine-local work-claim, keyed to the dispatched worker's reuse-resistant
  death handle and persisting for the worker run, is the authoritative no-duplicate-dispatch-and-no-strand
  guarantee — the single-host surface is both cross-clone and death-surviving, and the worker is directly
  probeable there; the **origin ref is demoted to a best-effort double-PR guard** (D-8 rewritten, REQ-C1.6,
  REQ-C1.1). Backlog closed: the origin-reaper / no-origin-GC findings dissolve as correctness issues
  (H1–H3), the lost-CAS-ACK live-tower strand disappears (A1 — no network-ACK in the authoritative path),
  no-remote multi-tower no longer fails open (A3 — `origin` not required for correctness), cohesion-bundle
  members are covered by the one claim enumerating all member unit-ids (A2, REQ-C1.2); the fence
  naming/sequencing/adopt-base/verify-refname findings become hardening notes on the demoted guard, modeled
  against **both shipped dispatch backends** (`fleet-dispatch-worktree.sh` direct-create vs `claude
  --worktree`/tmux rename) (S1–S5, D-8, REQ-C1.6); quarantine fires on the **first** parse failure (atomic
  writes preclude transient torn reads; a stateless tower has no store to count repeated failures — Q1,
  REQ-A1.6, REQ-C1.5); the dead-letter sub-surface gets a TTL sweep (Q2, REQ-C1.5); the reclaim artifact
  check reads live via `ls-remote`, fail-closed on `origin` error (U2); the all-zeros-OID CAS hardening is
  pinned (U1, D-8). **REQ-C1.3 tightened** from the absolute "a crashed tower never strands a unit" to the
  achievable "positively-dead worker always reclaimed; unclassifiable-liveness surfaced, never silently
  honored," closing the Q2 invisibility gap. Also folded: the **companion doctrine line** (new **REQ-D1.6**,
  D-1) — a merge-ready PR reaches the operator by deterministic push, LLM-poll the fallback — with its
  **mechanism cross-referenced out to a new `merge-currency-guard` spec** (D-6 extended), not implemented
  here. The bundle stays Draft; re-run `/spec-kickoff` for sign-off.

## Sources

- **The concurrent-orchestrator-coordination framing note** — the operator's reconstructed 2026-07-20
  note (drafting-session provenance; the originally-cited `obs:8cbe0123` fragment resolves to no
  committed file under `specs/_observations/`, so it is recorded here as prose rather than a dangling
  `obs:` citation) framing the concern as the layer above `orchestration-concurrency`: (1) cross-tower
  awareness, (2) the shared-`main` root fix of separate per-tower checkouts, (3) work-division /
  no-conflicting-dispatch, with ties to proactive shared-usage-governance and the inter-orchestrator
  relay. Framed this bundle.
- **The run-2 kickoff-halt rework seed** — `obs:7dd7eb45`
  (`specs/_observations/entries/2026-07-21-coc-fence-at-dispatch-halt2-7dd7eb45.md`), recorded 2026-07-21
  by the halted `/spec-kickoff` run 2, the backlog this rework closes: the dispatch-time no-authoritative-
  cross-clone-fence inconsistency resolved by Option A (fence at dispatch, D-8), plus the ~39-finding
  design/hygiene backlog. Full detail in `kickoff-brief.md` §8 (run 2). Consumed by this rework. (The
  run-1 halt seed originally cited as `obs:3ecf4293` likewise resolves to no committed fragment; its
  backlog was closed by the prior rework and its detail lives in the changelog and `kickoff-brief.md` §8
  run 1, so it is noted here as prose, not a dangling citation.)
- **The run-3 kickoff-halt rework seed** — `obs:c2270479`
  (`specs/_observations/entries/2026-07-21-coc-fence-reaper-halt3-c2270479.md`), recorded 2026-07-21 by the
  halted `/spec-kickoff` run 3, the ~18-finding backlog this rework closes: the death-surviving origin fence
  with no cross-clone reaper inconsistency (H1–H3), the new authoritative-guarantee breaks (A1–A3), the
  spec-vs-shipped-dispatch-code contradictions (S1–S5), and the quarantine/residue gaps (Q1, Q2). Resolved
  by Architecture A (worker-liveness claim authoritative; `origin` demoted — D-11). Full detail in
  `kickoff-brief.md` §8 (run 3). Consumed by this rework.
- **`merge-currency-guard`** (planned, not yet drafted) — the owner of the deterministic PR-ready-push
  mechanism this bundle cross-references but does not implement (REQ-D1.6, D-6): a PreToolUse guard
  intercepting the two ready surfaces (`gh pr ready` and the GitHub MCP draft→ready path) that both blocks a
  stale/DIRTY ready-flip and records a `pr-ready` heartbeat, plus the attention-surface reclassification of
  `pr-ready` from non-actionable to actionable. Named here so its future fold-detection resolves against
  this cross-reference.
- **The deterministic-pr-ready-push tower context (2026-07-21)** — operator/tower context recorded during
  this rework (slug `deterministic-pr-ready-push`; filed by a concurrent tower against a `main` this spec
  branch predates, so it is noted here as prose rather than a resolvable `obs:` citation until it lands):
  a live proof that LLM-tower-poll as the *sole* path to a merge-ready PR fails (ready PRs going un-surfaced
  because a tower did not poll in time), with `fleet-attention.sh` already modeling a non-actionable
  `pr-ready` state and nothing firing it deterministically. Motivated the companion doctrine line (D-1,
  REQ-D1.6) and seeds the `merge-currency-guard` spec.
- **orchestration-concurrency** (Done) — the ledger state-safety foundation: progress state as a
  derived projection, the single level-triggered `tasks.md` writer, dispatch-commit isolation, the
  per-spec advisory lock (a `mkdir`-atomicity directory lock at `<spec-dir>/.orchestrate.lock`, broken
  when stale past a threshold, checkout-local — it fences intra-clone ledger writes, not cross-clone
  claim selection; the per-unit reclaim lock of REQ-C1.3 reuses the same `mkdir`-plus-stale-break
  discipline at the machine-local surface), the
  **branch-as-fence** dispatch discipline (a task-branch ref / open PR for a unit is durable evidence the
  unit is already in flight), which this bundle **consumes as a *completion*-artifact signal** in the
  reclaim guard (an open PR / origin-ref commits mean the worker's work is in review or merged, so the unit
  is not reclaimed — REQ-C1.3), **not** as the authoritative dispatch fence: run 3 found a passive origin
  ref cannot carry worker liveness, so authority moved to the worker-keyed machine-local claim (D-11) and
  the origin ref is demoted to a best-effort double-PR guard (D-8, REQ-C1.6). The no-remote single-checkout
  solo flow needs no cross-clone guard at all.
  Consumed here as an authoritative contract; this bundle is the awareness/coordination layer strictly
  above it. The claim mechanism (D-5) reuses the same class of atomic filesystem primitive at the correct
  (machine-local) locality: an atomic, exclusive create-with-content for the initial claim, and — because
  reclaim is a read-check-swap whose check is slow — the same `mkdir`-plus-stale-break lock discipline,
  scoped per unit, for reclaim.
- **orchestration-fleet** (Done) — the scaling/resilience/UX sibling: the backend capability contract,
  the meta-tower ("tower of towers") cross-spec selection (`orchestration-fleet` REQ-D1.1), the
  inter-orchestrator coordination protocol and division-of-labor model (`orchestration-fleet` REQ-D1.2),
  and the attributed non-impersonating relay (`orchestration-fleet` REQ-D1.3). Reused, not
  re-implemented. (The prior draft cited a non-existent `orchestration-fleet REQ-D1.7`; that spec defines
  only REQ-D1.1–D1.6.)
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
