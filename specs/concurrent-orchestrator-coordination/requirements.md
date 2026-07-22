# Concurrent Orchestrator Coordination — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-21
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
   dispatched by more than one tower. The **authoritative** guarantee is an **origin fence ref created at
   dispatch** (D-5, D-8, D-11): before any worker runs, a tower fences the unit by an atomic expect-absent
   compare-and-swap creating a per-unit ref (`refs/planwright-fence/<spec>/<unit-id>`) on `origin` — the one
   substrate that is **natively both cross-clone and death-surviving**, so no machine-local surface has to
   *fake* that locality (the class of failure the four prior kickoff runs each halted on). The fence is
   keyed by **unit id** and created by the **tower before the worker forks**, so it carries no worker death
   handle and has no pre-fork lifecycle problem. A crashed tower's in-flight unit is **surfaced to the
   operator** for a reclaim decision, **not auto-recovered** — the common tower-turnover case is graceful
   self-refresh that never strands, so the rarer hard-crash strand is surfaced rather than probed-and-
   reclaimed on a guess. The machine-local presence surface (mechanism 1) is used only to **attribute** an
   orphan fence to a dead owner; it is **never on the correctness path**. The fence composes with, rather
   than replaces, `orchestration-fleet`'s meta-tower selection and division-of-labor doctrine.

The top-level guarantee is stated to what the mechanism can deliver over an open-ended partial-failure
substrate: **best-effort exclusion (authoritative while `origin` is reachable) plus every residue
bounded-and-swept or durably-surfaced to the operator, never silent** (D-13) — not the absolute "always
reclaimed / no unit ever dispatched twice" that four prior kickoff runs each asserted and each found a new
interleaving under. To make that guarantee checkable rather than a moving target, the bundle enumerates a
**failure-axis matrix** once — {locality, worker-lifecycle, keying/granularity, the death-state machine,
version/schema skew, a defined recovery action per fail-closed path, a durable sink per residue} — and
answers **every cell** (the coverage matrix in `design.md`, D-12); several cells (worker-lifecycle,
version/schema skew) **dissolve** because the correctness floor is a git ref, not a parsed machine-local
record keyed to worker liveness.

The deliverable is mechanism-primary — a presence/discovery signal, a per-tower checkout topology, and a
per-unit origin fence — carrying **two doctrine statements**: that a tower **assumes multiplicity, not
solitude** (the primary altitude call), and a narrower companion on the tower→human axis — a **merge-ready
PR reaches the operator by deterministic push, LLM-poll being the fallback** (mechanism owned elsewhere,
REQ-D1.6). Both extend the fleet coordination floor; the altitude call is recorded as **D-1** (the
autopilot-reflex altitude gate) and cited here from the Goal.

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
- A **per-unit origin fence ref** as the authoritative no-duplicate-dispatch guarantee: at dispatch, before
  any worker runs, a tower creates `refs/planwright-fence/<spec>/<unit-id>` on `origin` by an atomic
  expect-absent compare-and-swap (all-zeros OID); `origin` serializes ref updates, so exactly one tower
  fences a given unit, cross-clone and death-surviving by construction, with cohesion-bundle members fenced
  together by `git push --atomic` (REQ-C1.1, REQ-C1.2, D-8, D-11).
- **Operator-surfaced strand handling, not auto-reclaim**: a fence whose owning tower is positively dead
  and whose unit is **not terminal** (no merged PR, not ledger-done — including one carrying only commits or
  an open, unmerged PR, since no live tower will carry it to merge) — or any unclassifiable owner /
  unknown-owner orphan — is surfaced to a durable, dedup'd operator sink for a reclaim decision; the fence of
  a **terminal** unit (PR **merged** / ledger-done) is garbage-collected; neither the fence namespace nor the sink grows unbounded (REQ-C1.3,
  REQ-C1.5, REQ-C1.7).
- **`origin`-reachability classification**: no-`origin` is the genuine solo posture (dispatch without a
  fence, no peers to collide with); a transient `origin` failure or a rejected CAS fails closed / backs off,
  never failing open into a collision (REQ-C1.6, D-10).
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
- **Automatic reclaim of a dead tower's in-flight unit.** A hard-crashed tower's fenced-but-unfinished
  unit is *surfaced to the operator* for a reclaim decision (REQ-C1.3, REQ-C1.7), never auto-probed and
  auto-reclaimed. Auto-recovery was the Architecture-A design of the run-3/run-4 draft; it required a worker
  death handle knowable only post-fork and still stranded the unclassifiable case, so under the downgraded
  guarantee (D-13) it is deliberately out of scope (D-7, D-11).
- **Cross-machine / distributed peer towers.** The coordination surfaces (presence, the strand sink, and
  the fence-attribution read) are single-host: the presence surface is a fixed machine-local path shared by
  co-located clones on one host, and the death-evidence predicate (PIDs / tmux) is host-local and cannot
  classify a remote peer, so peer towers on separate machines are out of scope. (The origin fence itself is
  substrate-shared and would work cross-machine; strand *attribution* is what the single-host assumption
  bounds.) Single-host co-location is an assumed precondition, not a mechanism this bundle builds.

## REQ-A — Cross-tower awareness

- **REQ-A1.1** A tower SHALL, at startup and on a heartbeat thereafter, discover the set of other live
  towers operating on the **same repository**, from a deterministic presence signal, and SHALL NOT
  assume it is the only tower running. The surface is a single host-wide machine-local path shared by
  every repository's clones on the host (REQ-A1.4), partitioned into **one sub-surface per repository
  identity** (`<surface>/<repo-id>/`, holding the per-tower presence records and the durable strand sink —
  there is no `claims/` sub-surface under Architecture B, D-2); discovery SHALL scope to the current repository by **scanning only the current repo id's
  sub-surface**, with the repository identity carried in each record (REQ-A1.2) verified as a defensive
  cross-check rather than by filtering the entire host surface — the two descriptions are reconciled to
  the per-`<repo-id>` sub-surface as canonical. Discovery SHALL exclude the tower's own record (by tower
  identity, REQ-A1.7), so a tower never counts itself as a peer. To bound cost, discovery SHALL run on a
  **capped heartbeat cadence** and SHALL **cache each peer's liveness verdict for the pass** rather than
  invoking the death-evidence subprocess more than once per record per pass, so the per-record subprocess
  fan-out is bounded, not unbounded per beat.
  *(Cites: D-1, D-2.)*
- **REQ-A1.2** Each tower SHALL publish its own presence record — a **repository identity**, a **tower
  identity** (REQ-A1.7), its checkout path, the spec(s) it is advancing, the set of **unit-ids it
  currently holds an `origin` fence for** (refreshed on the heartbeat, so a peer can attribute an orphan
  fence ref to this tower — or, when no live record lists the unit, to an unknown owner — for strand
  detection, REQ-C1.3), its start time, a refreshed heartbeat, a positive-evidence-of-death handle by which
  a peer confirms its liveness, and a **meta-tower marker that is the record's own validated field** stamped
  from the tower's `--meta` mode —
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
  editing a *live* peer's file content. The GC delete SHALL be guarded by a **stateless
  re-stat-and-compare** — **no machine-local lock** (Architecture B keeps none; this is a presence-surface
  awareness guard, *not* a resurrection of the removed correctness-path reclaim lock): immediately before the
  unlink the sweep re-reads the file and deletes it **only if it is byte-identical to the positively-dead
  record it classified** (equivalently, an atomic `rename`-aside of that exact content then unlink), so a
  **dead-then-restarted** tower's *fresh live* record (same tower identity, new session, different content) is
  never deleted out from under it — an unguarded `rm` would be that bug. Where a tower's death handle is the degraded bare-`process <pid>` form (REQ-A1.2), a **reused pid**
  can read as alive and cause the dead tower's record to be honored rather than reclaimed; this is an
  **availability-only** effect (a stale presence record merely over-counts peers, and for a fence's owner
  the same handle ambiguity makes the owner's liveness *unclassifiable* → surfaced as a strand anomaly
  (REQ-C1.3, REQ-C1.7), never auto-reclaimed and never double-dispatched — the fence itself, a git ref, is
  unaffected by pid reuse), never a safety failure, and is why the `tmux-window` handle is preferred where
  available.
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
  attacker-planted surface can never quietly widen the trust boundary. On that refusal the tower SHALL
  **halt its coordination-surface use and surface a security error for the operator** (a louder stop than
  REQ-A1.5's awareness-degradation, since an over-broad surface is a trust-boundary breach, not a mere
  read failure); it SHALL NOT chmod-narrow and reuse the surface on a guess.
  *(Cites: D-2; orchestration-concurrency, fleet-autonomy (Sources).)*
- **REQ-A1.5** Presence discovery SHALL distinguish a healthy-but-empty presence surface (no peers
  currently live) from an absent, unreadable, or misconfigured one, and SHALL fail closed on the
  latter — surfacing an explicit error or an "unknown peer status" result — rather than reading a
  broken surface as evidence of solitude. On a fail-closed surface error the tower SHALL take the
  **defined recovery action of D-10: surface "unknown peer status" and degrade awareness and
  strand-attribution for the step, while dispatch still proceeds** — because under the origin-fence floor
  (REQ-C1.1, D-11) the exclusion guarantee is the `origin` fence, **independent of this surface**, so a
  broken presence surface can no longer cause a double dispatch; it only blinds the tower to peers and
  leaves an orphan fence attributable to "unknown owner" (REQ-C1.3). Halting dispatch would degrade
  throughput for no safety gain (degrade capability, never safety). A broken surface is nonetheless **never
  read as solitude** (it is surfaced, not silently treated as "no peers"); solo dispatch is reserved for the
  genuine no-remote single-checkout posture, never a coordination-surface failure. A **first-run bootstrap**
  where the surface directory does not yet exist
  SHALL be treated as the healthy-empty case: the tower creates the user-private directory (REQ-A1.4) and
  proceeds with an empty peer set. Because a bare `ENOENT` cannot distinguish "never existed" (healthy
  first run) from "existed and then vanished" (a surface that must fail closed, not read as solitude), a
  **persistence sentinel** dropped at bootstrap SHALL make that distinction — its presence means the
  surface once existed, so a missing directory alongside a surviving sentinel fails closed. The sentinel
  SHALL live at a fixed machine-local path **outside the surface directory** (a sibling under the host-wide
  root, not inside `<surface>/<repo-id>/`), so that deleting the surface directory cannot also delete the
  sentinel that proves it once existed, and SHALL be **written before the surface directory is created** at
  bootstrap, so a crash *between* the two never leaves a sentinel-less directory that a later deletion would
  render indistinguishable from a healthy first run; a sentinel **write failure at bootstrap SHALL itself
  fail closed** (surface the error; do not proceed as if bootstrapped), never leaving a later vanished
  surface to be misread as a healthy first run. This first-run-vs-vanished distinction applies at **both
  levels** — the host-wide surface root **and each per-`<repo-id>` sub-surface**: a per-repo sentinel
  distinguishes a genuine first discovery of a repo id (healthy empty, create the sub-surface) from a
  **vanished `<repo-id>/` sub-surface** (sentinel present, sub-dir gone → fail closed), so a disappeared
  per-repo sub-surface is never read as solitude. Because the sentinel is a stat'd leaf, a **corrupt-but-present** sentinel
  still reads as "present" (fail closed), and there is no meta-sentinel regress. A
  **concurrent first-run `mkdir` that returns `EEXIST`** because a peer bootstrapped the surface a moment
  earlier SHALL be treated as **success, not an error** (the create is idempotent and order-independent,
  D-10). Publishing the tower's own record and discovering peers SHALL be ordered so a tower does not read
  the surface as absent between creating it and populating it.
  *(Cites: D-2, D-10; the fail-closed / degrade-capability-never-safety floor (Sources).)*
- **REQ-A1.6** Presence records SHALL be parsed defensively: a record that is malformed, truncated, or
  otherwise unparseable SHALL fail closed for that record — it is skipped with a surfaced error and never
  interpreted as absent, empty, or "no such peer" — so a corrupt record can never cause a tower to conclude
  a live peer does not exist. This is the per-record analog of REQ-A1.5's surface-level fail-closed rule. A
  record the tower cannot parse well enough to attribute — including a **schema-skewed record written by a
  different-planwright-version peer** — SHALL be treated as **a peer that exists but whose details are
  unreadable**: assume-live for awareness, never GC'd on a guess, and surfaced as an unclassifiable
  awareness anomaly to the durable sink (REQ-C1.7). This is safe precisely because presence is
  **awareness-only and never on the correctness path** (REQ-C1.1): a version-skewed presence record can
  never free a fenced unit, so the run-4 "well-formed-but-unparseable claim → quarantine → double dispatch"
  safety bug **does not exist under the origin-fence floor** — the correctness floor is git-ref existence,
  which has no record schema to skew (D-12, D-13). There is no claim record to quarantine and no dead-letter
  sub-surface: the only correctness object is the fence ref, and a ref either exists or it does not.
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

- **REQ-C1.1** No unit SHALL be dispatched by more than one tower. That guarantee is **authoritative in the
  origin fence ref created at dispatch (D-5, D-8, D-11)**: at dispatch, before any worker runs, a tower
  fences the unit by an **atomic expect-absent compare-and-swap** creating a **per-unit fence ref on
  `origin`** (`refs/planwright-fence/<spec>/<unit-id>`, REQ-C1.2), pushed with the **explicit all-zeros OID**
  as the must-be-absent expectation. Because `origin` is the one substrate every co-located clone already
  shares and git serializes ref updates on it, exactly one tower's create-ref succeeds per unit and holds
  it; a losing tower's push is **rejected**, whereupon it selects another unit. This is the substrate the
  four prior kickoff halts were reaching for: `origin` is **natively both cross-clone and death-surviving**
  — the ref persists after the creating tower dies, and every clone reads the same ref set — so no
  machine-local surface has to *fake* that locality (the run-1→run-4 failure class, D-11, D-12). The fence
  is keyed by **unit id**, created by the **tower before the worker forks**, so it references **no worker
  identity or death handle** and has no pre-fork-pid lifecycle problem. The machine-local presence surface
  (REQ-A) is **never on this correctness path**: it is used only to *attribute* an orphan fence to a dead
  owner for surfacing (REQ-C1.3), and if it is missing or unreadable the fallback is to surface the orphan
  as unknown-owner — safe, never a double dispatch.
  This guarantee is **bounded, not absolute** (D-13): it holds **while `origin` is reachable**; when
  `origin` is unreachable the tower **fails closed and surfaces** rather than dispatching blind, except the
  genuinely-solo no-remote single-host case where there is no peer to collide with (REQ-C1.6). Every residue
  the mechanism cannot exclude is **bounded-and-swept or durably-surfaced to the operator, never silent**
  (REQ-C1.3, REQ-C1.5, REQ-C1.7).
  *(Cites: D-5, D-8, D-11, D-12, D-13.)*
- **REQ-C1.2** A fence SHALL be a **per-unit-keyed** git ref under a **dedicated fence namespace**
  (`refs/planwright-fence/<spec>/<unit-id>`, **never** the unit's task-branch ref), so the fence is keyable
  and garbage-collectable independent of whether the worker's task branch yet exists — dissolving the run-4
  byte-identical-cross-clone-branch and dispatch-backend-rename concerns: the fence is pushed by the tower
  under the canonical unit-id name **directly**, with no worker branch and no backend rename anywhere in the
  fencing path. The push SHALL target a **fixed sentinel** (the current `origin/main` tip) with the
  expect-absent CAS of REQ-C1.1, so it adds **no commit and no history to `main`** (a ref at an existing
  commit), honoring `orchestration-concurrency`'s no-dispatch-commit-on-`main` floor. When a unit is a
  **cohesion bundle** (a task set dispatched to one worker under a lead branch/PR), the tower SHALL fence
  **every member unit-id** in a single **`git push --atomic`**: if any member is already fenced by a peer,
  the whole atomic push is **rejected** and the tower backs off the **entire bundle**, so a peer selecting
  **any** member — lead or non-lead — collides and no non-lead member is left unfenced (the run-4
  cohesion-bundle keying gap, closed by construction). A tower SHALL coordinate only by **creating, reading,
  and deleting fence refs** and reading the presence surface; it SHALL never directly mutate a peer tower's
  or a worker's branch state.
  *(Cites: D-5, D-8, D-12; the division-of-labor "directly" boundary (Sources).)*
- **REQ-C1.3** Classification is ordered **terminal first, then liveness**: a **terminal** unit (merged PR /
  ledger-done) is GC'd regardless of owner liveness (REQ-C1.5); otherwise a fence whose owning tower is
  **live** SHALL be honored (the unit is in flight), **regardless of any *non-merged* downstream artifact**
  (commits or an open, unmerged PR never make a live owner's fence reclaimable). A fence becomes a **strand
  candidate** when its owning tower is **positively
  dead** (the presence surface's `fleet-death-evidence` verdict on the owner's recorded death handle,
  REQ-A1.2 / REQ-A1.3) **and** the unit is **not terminal** — it has **no merged PR and is not ledger-done**,
  read **live** (refs via `ls-remote`, PR merge state via `gh`/GitHub; never a possibly-stale checkout-local
  remote-tracking ref), a transient `origin` read **failing closed** (do not act, retry next pass). A dead
  owner's **non-merged downstream artifact** — commits on the unit's task branch, **or an open, unmerged
  PR** — does **not** suppress the strand: no live tower will carry that work to merge (a dead tower cannot
  open or merge a PR, and this bundle never auto-authors), so under the "never silent" guarantee (D-13) it is
  **surfaced**, not silently honored. Only a **merged** PR or a ledger-done unit is terminal (→ GC, REQ-C1.5),
  which keeps this strand check and REQ-C1.5's terminal definition identical. On a strand candidate the tower SHALL **surface it to
  the durable operator sink (REQ-C1.7), never auto-reclaim it**: reclaiming a dead tower's in-flight unit is
  a **reserved operator decision** under the downgraded guarantee (D-13), because the common tower-turnover
  case is graceful self-refresh that never strands, so the rarer hard-crash strand is surfaced rather than
  probed-and-reclaimed on a guess. Cases the tower **cannot classify** — an **unknown/errored** owner
  liveness probe, a fence ref **owned by no discoverable presence record** (an unknown-owner orphan), or a
  **reused-pid ambiguity** on a degraded bare-`process <pid>` owner handle — SHALL **also be surfaced, never
  silently honored forever and never auto-reclaimed**. An **unknown-owner orphan SHALL be surfaced only after
  a one-pass grace re-check** confirms it is still unattributed on the *next* discovery pass, because a live
  owner's presence record lists its fenced unit-ids only as of its last **heartbeat** (REQ-A1.2) — so in the
  brief window between a live tower's fence push and its next heartbeat refresh the fence is momentarily
  attributable to no live record, and surfacing it immediately would raise a **false** strand on a legitimately
  in-flight unit. The tower itself stays **stateless** — the cross-pass "seen-unattributed-once" memory lives
  in the durable dedup'd sink (REQ-C1.7), not the tower (which keeps no local store): the first observation
  records a **tentative** sink entry keyed by the fence-ref name, a subsequent pass that still finds it
  unattributed **promotes** it to a surfaced strand, and a pass that attributes it (the owner's heartbeat
  having caught up, or the unit turning terminal) **sweeps** the tentative entry. The grace re-check thus
  collapses the heartbeat-lag window without weakening the dead-owner case (a genuinely orphaned fence stays
  unattributed across passes and still surfaces, bounded-delay). The one residue the sweep resolves **without** the
  operator is a fence whose **unit is already terminal** (PR merged / ledger-done): that is not a strand but
  completed work, and its fence is **garbage-collected** (REQ-C1.5). The honest guarantee, stated to what
  the mechanism delivers (D-13): **a dead-owner unit that is not terminal is always surfaced (bounded delay,
  dedup'd sink) — including one carrying only commits or an open, unmerged PR; a terminal (merged /
  ledger-done) unit's fence is always swept; and no strand is ever silently honored forever.** To bound
  network cost, the terminal-state check (`ls-remote` / `gh`) that classifies a dead-owner fence SHALL run on
  the **same capped cadence** as discovery (REQ-A1.1), and a fence **already surfaced in the dedup'd sink**
  (REQ-C1.7) SHALL NOT be re-checked every sweep — it is re-evaluated only once its cadence window elapses —
  so operator-unresolved strands accumulating in the sink never drive an unbounded per-pass fan-out of
  `origin` reads. Because reclaim is the operator's, there is **no per-unit reclaim lock, no under-lock re-read,
  and no worker-liveness probe on the correctness path** — the machinery Architecture A needed for
  auto-reclaim is **absent by design** (D-7, D-11).
  *(Cites: D-7, D-11, D-13; the positive-evidence-of-death floor (Sources).)*
- **REQ-C1.4** Where a meta-tower ("tower of towers") is present, work division SHALL reuse its
  cross-spec selection under the fleet bound; the peer **fence** mechanism SHALL compose with, and never
  contradict, `orchestration-fleet`'s division-of-labor doctrine. A meta-tower SHALL be distinguishable on
  the presence surface by the record's **own validated meta-tower marker** (REQ-A1.2, not
  `fleet-tower-marker.sh`); where a meta-tower assigns disjoint slices, towers honor that assignment, and
  the peer fence is the mechanism for the independently-started, no-meta-tower case.
  *(Cites: D-4; orchestration-fleet (Sources).)*
- **REQ-C1.5** A fence ref SHALL persist from dispatch until its unit reaches a **terminal state**, and
  SHALL be **garbage-collected** (the fence ref deleted from `origin`) when the unit is terminal — its **PR
  merged** or the ledger marks it done — so the fence namespace does not grow unbounded across the unit's
  whole history (the run-4 no-origin-ref-GC gap). An **open, unmerged PR is *not* terminal**: it does not
  trigger GC, and the fence persists across the whole open-PR window — for a *live* owner the fence is simply
  honored until merge, and for a *dead* owner the unit is a surfaced strand (REQ-C1.3), never silently
  GC'd out from under an unfinished unit. Because the fence lives until merge, the dispatch selection guard's
  fence-ref existence check (Task 4) is sufficient with no fence→branch-as-fence handoff gap. GC SHALL run both on the **discovery sweep** and on
  the **owning tower's own completion path**, and SHALL be **idempotent** (deleting an already-absent ref is
  success, so two towers GC'ing the same terminal fence never error). A fence GC that fails on a transient
  `origin` error SHALL be surfaced and retried next pass, never left to silently accumulate. Because reclaim
  is the operator's (REQ-C1.3), there is **no claim quarantine, no dead-letter sub-surface, and no
  four-residue machine-local GC**: the only swept residue is the terminal fence ref on `origin`, and the
  only other bounded surface is the durable strand sink (REQ-C1.7), which is dedup'd by key so it too cannot
  grow unbounded. A fence delete SHALL be **containment-checked** against the fence namespace (REQ-D1.5) so
  a crafted unit id can never drive a ref delete outside `refs/planwright-fence/<spec>/`.
  *(Cites: D-7, D-8, D-12.)*
- **REQ-C1.6** Because the fence lives on `origin`, `origin` reachability is the fence's precondition, and a
  failed fence push SHALL be **classified before acting** (D-10), mirroring the `fetch` split of REQ-B1.4:
  **no `origin` configured** is the genuine **no-remote single-host solo posture** — a single checkout with
  no peers to collide with — so the tower dispatches **without** a fence (there is no cross-clone contention
  to arbitrate), never failing open into a multi-tower collision; a **rejected expect-absent CAS** (a peer
  already fenced the unit) means **back off this unit and select another**; and a **transient push failure
  against a configured `origin`** **fails closed** (do not dispatch this unit this pass, surface, retry
  next pass), never dispatching blind against a possibly-fenced unit. Because a rejected CAS and a transient
  push failure are **both a non-zero `git push`**, the tower SHALL distinguish them by the push's **per-ref
  status** (`--porcelain` / `--push-option` reporting, or the stale-info/non-fast-forward rejection reason in
  stderr), **not by exit code alone**: a per-ref "rejected (stale info / already exists)" is the taken-unit
  back-off, while a connection/transport/permission error with no per-ref rejection is the transient
  fail-closed-and-retry path. Misclassifying either way costs at most one wasted pass (the authoritative CAS
  re-adjudicates next pass), never a double dispatch. The tower SHALL NOT treat a transient
  `origin` failure as the solo posture, and SHALL NOT `--force` or overwrite a fence ref it did not create
  (only the expect-absent lease is ever used). This is the bounded arm of the downgraded guarantee (D-13):
  correctness holds while `origin` is reachable; unreachability is surfaced or safely solo, never a silent
  double dispatch. The fence establishes no committed state on `main` (REQ-C1.2), so it does not violate
  `orchestration-concurrency`'s no-dispatch-commit-on-`main` floor.
  *(Cites: D-8, D-10, D-13; orchestration-concurrency's no-dispatch-commit-on-main floor (Sources).)*
- **REQ-C1.7** Every **strand** (REQ-C1.3) and every **unclassifiable awareness or fence anomaly** the
  coordination layer surfaces SHALL land in a **durable, deduplicated, operator-facing sink**, delivered by
  **push** through the existing `orchestration-fleet` attention surface (surface-by-push, per the
  autopilot-reflex forcing-function discipline), **never a transient log line and never a poll-only
  surface**. The sink SHALL **deduplicate** so the same anomaly re-observed on successive discovery passes
  is surfaced once, not re-raised every pass: the dedup key is the **fence-ref name plus owner identity**
  for a strand, and the **record identity** for an awareness anomaly. A surfaced entry SHALL name the unit,
  the dead-or-unknown owner, and the **defined operator action** (reclaim / investigate / dismiss), so
  "surfaced" is an actionable operator item, not noise. The sink SHALL carry **no secrets, credentials,
  internal hostnames, checkout paths, or death handles** into any committed artifact (REQ-D1.4); it is a
  runtime operator surface, not a committed record. Because it is dedup'd and its entries are resolved by
  the operator or swept when their unit turns terminal, the sink does not grow unbounded (the run-4
  no-durable-dedup'd-sink gap).
  *(Cites: D-7, D-12, D-13; orchestration-fleet (Sources).)*

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
- **REQ-D1.4** A tower's presence records and the durable strand-sink entries (REQ-C1.7) SHALL carry an
  attribution a peer or operator can validate before acting on them, peer output consumed for awareness
  SHALL be treated as data and never evaluated as code, and every committed coordination artifact SHALL
  carry no secrets, credentials, internal hostnames, or sensitive operational detail — **including both the
  machine-local checkout path and the death handle of a peer tower** (a pid, or a tmux session+window name),
  which are operational detail that SHALL NOT leak from the presence surface or the strand sink into a
  committed artifact (a PR body, an audit log). Attribution validation is scoped to the same-operator,
  single-host trust model (peer towers are the operator's own co-located sessions): it SHALL grammar-validate
  the tower-identity token and refuse a malformed one before use, but is NOT required to defend against an
  adversarial peer forging another tower's identity.
  *(Cites: D-9; security-posture, inter-orchestrator-coordination security bounds (Sources).)*
- **REQ-D1.5** The coordination scripts (presence publish/discover, fence push/GC, strand surfacing) SHALL
  meet planwright's framework-script security bars, since they parse records other sessions write to a
  shared surface and construct git ref operations from unit ids: (a) **every parsed field consumed by the
  coordination logic SHALL be validated against its declared grammar before any use** — not only the tower
  identity, but the repository identity, the **unit id and spec id** — each validated against a **declared
  identifier grammar** (the unit/spec-id charset `[A-Za-z0-9._-]`, no `..` component, no leading dash, bounded
  length) **before any `origin` fence-ref push or delete**, so a crafted id can never drive a ref operation
  outside `refs/planwright-fence/<spec>/` — the timestamps (start time and heartbeat, validated as well-formed
  timestamps), the **meta-tower marker**
  (a validated boolean; it drives the defer-to-authority decision, so an unvalidated value could mis-route
  division — REQ-A1.2, REQ-C1.4), the **checkout path**, and the **positive-evidence-of-death handle**,
  whose **declared grammar is exactly the two `fleet-death-evidence.sh` forms** — `process <pid>` (a
  positive integer, no leading zero, ≤10 digits) or `tmux-window <session> <window>` (that predicate's tmux
  charset, ≤128, no leading dash) — since the handle is read from an untrusted peer presence record and
  passed straight to `fleet-death-evidence.sh`, **and the currently-fenced-unit-ids list** (each entry
  validated against the unit-id grammar above, since the list is parsed from an untrusted peer record and
  consumed for orphan-fence attribution — REQ-A1.2, REQ-C1.3); a field that fails its grammar is refused, not coerced;
  (b) **path and ref access SHALL be canonicalized and containment-checked** before any read, write,
  `mkdir`, unlink, or ref push/delete — the presence surface directory itself (so a **surface-root symlink**
  cannot redirect containment outside it), each presence record path, the strand-sink path, and the
  **fence-ref name** (validated with **`git check-ref-format`** *and* a literal `refs/planwright-fence/<spec>/`
  prefix check — the containment primitive for a git *ref* name, distinct from the filesystem path
  canonicalization that applies to the surface directory and record paths — before any push or delete), so a
  crafted unit/tower id can never drive a write, delete, or ref operation outside its
  bounds; (c) untrusted record fields echoed to a terminal or log SHALL pass the echo-discipline sanitizer
  (`scripts/echo-safety.sh`, `sanitize_printable`), so an embedded escape sequence in a peer record cannot
  drive the terminal. These are the enforcement of the same-operator trust model at the script boundary,
  complementing the user-private surface (REQ-A1.4).
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
- 2026-07-21 — `/spec-draft` rework (run 4→5, in place, Draft) closing the kickoff run-4 multi-axis
  backlog (`obs:a45c20d6`, ~31 findings / 6 HIGH). **Keystone (operator decision, 2026-07-21):
  Architecture B — origin-fence-only.** Kickoff run 4 halted on a *fourth* inconsistency class: the run-3
  worker-liveness claim (Architecture A) got the locality axis right, but the full-bundle lens found
  new-axis holes it never checked — worker-lifecycle (the claim needs a pre-fork pid), keying/granularity
  (cohesion-bundle double-dispatch), case-completeness (a commits-no-PR strand neither reclaimed nor GC'd
  nor surfaced), version/schema skew (a well-formed-but-unparseable claim → quarantine → double dispatch),
  classification (a reused pid silently honored), and surfacing/bounding (no durable dedup'd sink).
  Diagnosis: runs 1–3 fixed one *locality* axis three times; correctness here is multi-axis. The rework
  applies three structural moves. (1) **Enumerate the failure-axis matrix** and answer every cell (new
  D-12, matrix in `design.md`), converting "find the next interleaving" into "fill every cell". (2)
  **Downgrade the top-level guarantee** from absolute to "best-effort exclusion (authoritative while
  `origin` reachable) + every residue bounded-and-swept OR durably-surfaced, never silent" (new D-13). (3)
  **Invert the architecture**: the per-unit **origin fence ref** is authoritative (D-8 and D-11 reframed;
  D-5 reframed to the fence primitive, D-7 to its lifecycle + strand surfacing), and the machine-local
  worker-liveness claim, per-unit reclaim lock, four-residue GC, and version quarantine are **removed**;
  dead-tower strands are **surfaced, not auto-reclaimed** (REQ-C reworked; new REQ-C1.7 durable dedup'd
  sink; REQ-A1.6 decoupled from claim quarantine). Several run-4 HIGHs **dissolve** (worker-lifecycle,
  keying, version skew) because the correctness floor is a git ref, not a parsed record. The phantom
  "second dispatch backend that renames" is removed (the tower pushes the fence by canonical unit-id name
  directly, with no worker branch in the fencing path). Full detail in `kickoff-brief.md` §8 (run 4). The
  bundle stays Draft; re-run `/spec-kickoff` for sign-off.

## Sources

- **The concurrent-orchestrator-coordination framing note** — the operator's reconstructed 2026-07-20
  note (drafting-session provenance; the originally-cited `obs:8cbe0123` fragment resolves to no
  committed file under `specs/_observations/`, so it is recorded here as prose rather than a dangling
  `obs:` citation) framing the concern as the layer above `orchestration-concurrency`: (1) cross-tower
  awareness, (2) the shared-`main` root fix of separate per-tower checkouts, (3) work-division /
  no-conflicting-dispatch, with ties to proactive shared-usage-governance and the inter-orchestrator
  relay. Framed this bundle.
- **The run-2 kickoff-halt rework seed** — `obs:7dd7eb45`
  (`specs/_observations/archive/2026-07-21-coc-fence-at-dispatch-halt2-7dd7eb45.md`), recorded 2026-07-21
  by the halted `/spec-kickoff` run 2, the backlog this rework closes: the dispatch-time no-authoritative-
  cross-clone-fence inconsistency resolved by Option A (fence at dispatch, D-8), plus the ~39-finding
  design/hygiene backlog. Full detail in `kickoff-brief.md` §8 (run 2). Consumed by this rework. (The
  run-1 halt seed originally cited as `obs:3ecf4293` likewise resolves to no committed fragment; its
  backlog was closed by the prior rework and its detail lives in the changelog and `kickoff-brief.md` §8
  run 1, so it is noted here as prose, not a dangling citation.)
- **The run-3 kickoff-halt rework seed** — `obs:c2270479`
  (`specs/_observations/archive/2026-07-21-coc-fence-reaper-halt3-c2270479.md`), recorded 2026-07-21 by the
  halted `/spec-kickoff` run 3, the ~18-finding backlog this rework closes: the death-surviving origin fence
  with no cross-clone reaper inconsistency (H1–H3), the new authoritative-guarantee breaks (A1–A3), the
  spec-vs-shipped-dispatch-code contradictions (S1–S5), and the quarantine/residue gaps (Q1, Q2). Resolved
  at the time by Architecture A (worker-liveness claim authoritative; `origin` demoted — D-11), **since
  superseded by the run-4 rework below**, which inverts back to the origin fence. Full detail in
  `kickoff-brief.md` §8 (run 3). Consumed by the prior rework.
- **The run-4 kickoff-halt rework seed** — `obs:a45c20d6`
  (`specs/_observations/archive/2026-07-21-coc-multiaxis-halt4-a45c20d6.md`), recorded 2026-07-21 by the
  halted `/spec-kickoff` run 4, the ~31-finding / 6-HIGH backlog this rework closes. Run 4 walked the
  Architecture-A (worker-liveness claim) design and the full-bundle lens found new-axis holes A never
  checked: worker-lifecycle (a claim needs a pre-fork pid), keying/granularity (cohesion-bundle
  double-dispatch), case-completeness (a commits-no-PR strand neither reclaimed nor GC'd nor surfaced),
  version/schema skew (a well-formed-but-unparseable claim → quarantine → double dispatch), classification
  (a reused pid silently honored), and surfacing/bounding (no durable dedup'd sink). Its diagnosis — runs
  1–3 fixed one *locality* axis three times, correctness here is multi-axis — plus its three structural
  moves (enumerate the axis matrix, downgrade the guarantee, re-open Architecture A vs B) are the framing
  this rework consumes. The operator chose **Architecture B — origin-fence-only** (drafting-session
  decision, 2026-07-21). Full detail in `kickoff-brief.md` §8 (run 4). Consumed by this rework.
- **`merge-currency-guard`** (drafted on its own branch, not yet merged to `main`) — the owner of the deterministic PR-ready-push
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
  when stale past a threshold, checkout-local — it fences intra-clone ledger writes, not cross-clone unit
  selection), the **no-dispatch-commit-on-`main`** floor (which the per-unit fence honors by pushing a ref
  at an existing commit, never new history — REQ-C1.2, REQ-C1.6), and the **branch-as-fence** dispatch
  discipline (a task-branch ref / open PR for a unit is durable evidence the unit is already in flight),
  which this bundle **consumes as an in-flight signal** in the strand check: for a **live** owner a
  task-branch ref / open PR corroborates that the unit is in flight (honored); for a **positively-dead**
  owner it is **not** treated as completion — only a **merged** PR or a ledger-done unit is terminal (→ GC),
  while commits or an **open, unmerged PR** from a dead owner is an **abandoned strand surfaced to the
  operator** (no live tower will carry it to merge), read live via `ls-remote` / `gh` — REQ-C1.3, REQ-C1.5. Consumed here as an authoritative
  contract; this bundle is the awareness/coordination layer strictly above it. The authoritative dispatch
  fence itself is **not** a machine-local primitive but the per-unit ref on `origin` (D-8, D-11), whose
  expect-absent compare-and-swap git serializes cross-clone by construction — the run-4 inversion of the
  run-3 machine-local claim, which had to *fake* a locality `origin` provides natively. The no-remote
  single-checkout solo flow needs no cross-clone fence at all (REQ-C1.6).
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
