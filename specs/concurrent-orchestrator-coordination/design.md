# Concurrent Orchestrator Coordination — Design

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** / **C, `<doctrine>`** —
carried: this bundle reuses an existing decision or doctrine floor from a named sibling rather than
inventing a parallel one.

The design leads with the altitude record (D-1), then the three mechanisms in impact order:
presence/awareness (D-2), the shared-`main` root fix (D-3), and the peer work-claim (D-4, D-5),
closing with the scope boundary that keeps adjacent concerns in their own homes (D-6). Every
mechanism sits above `orchestration-concurrency`'s state-safety floor and reuses `orchestration-fleet`'s
relay and meta-tower selection rather than forking them.

**Decision-domains walk.** The feature crosses several catalogued stake-bearing domains, all decided
in-spec rather than auto-defaulted: **concurrency** (the central domain — shared coordination surfaces,
the claim read-modify-write, crash-mid-critical-section reclaim; decided by the in-lock claim ordering
in D-5 / REQ-C1.1, the death-evidence reclaim, and the reused per-spec lock); **integration surface**
(the git checkout / origin coordination topology — decided in D-3); **authentication / attribution**
(tower identity on the presence and claim surfaces — decided by carrying
`inter-orchestrator-coordination`'s relay security bounds scoped to the same-operator single-host trust
model, REQ-D1.4); and **observability** (a broken presence surface must not read as solitude — decided
by the fail-closed discovery requirement REQ-A1.5). Secrets/config is conditional (documented in the
options reference only if the surface path becomes configurable). No other catalogued domain is
touched-but-undecided.

## Decision log

### D-1: Deliverable altitude — mechanism-primary with one coordination-floor doctrine statement (N)

**Decision:** This bundle is primarily three concrete mechanisms (D-2 through D-5) plus exactly one
doctrine statement: that a tower **assumes multiplicity, not solitude** — it keeps tabs on peer towers
and coordinates division rather than behaving as the sole orchestrator. That statement extends the
fleet coordination floor (`fleet-coordination-floor.md`) and is the altitude decision this bundle
records per the autopilot-reflex altitude gate, cited from the Goal.

**Alternatives considered:**
- Pure mechanism, no doctrine statement. Rejected because: the assume-multiplicity principle is the
  through-line under all three mechanisms and generalizes beyond this repo — the same shape as
  `fleet-hardening` D-1 and the two existing fleet-coordination floors, which each landed a doctrine
  statement alongside their mechanisms. Leaving it implicit is how the next tower ships assuming it is
  alone.
- Doctrine-only reframe (elevate the floor, defer the mechanisms). Rejected because: the operator's
  concern is concrete and current — two towers already run against one checkout and race — so the honest
  call is mechanism-primary with a single carried floor, not a floor awaiting future instantiation.

**Chosen because:** an altitude trigger fired (a seed framing this as a first-class cross-tower concern —
"orchestrators don't seem to keep tabs … in case there are other orchs running"), so the call is
recorded rather than retrofitted; and the honest weight is one doctrine line on top of three mechanisms,
scoped per proportionality to the risk this bundle actually exhibits.

### D-2: Cross-tower presence as a per-tower heartbeat file scanned on demand, not a shared registry (N)

**Decision:** Presence is a directory of **one file per tower** at a fixed machine-local path outside
every checkout — so all co-located peer clones on one host read the same directory (cross-machine peers
are out of scope per Scope). Each tower writes and heartbeat-refreshes its own record (identity,
checkout path, spec(s) advanced, start time, last-beat), and a tower discovers peers by scanning that
directory and applying the positive-evidence-of-death liveness predicate to each record. No tower ever
edits another *live* tower's file content, and there is no single registry file that all towers mutate;
a discovering tower MAY delete a positively-dead tower's entire file as garbage collection (deleting a
whole dead file is not editing a live peer's content, so it does not reintroduce the shared-write
corruption surface). The set of live towers is *derived* from the scan on demand, never a committed or
hand-maintained artifact. Discovery fails closed on an absent or unreadable surface rather than reading
emptiness as solitude (REQ-A1.5).

**Alternatives considered:**
- A single shared registry file all towers append to / edit. Rejected because: it reintroduces exactly
  the shared-write corruption surface `orchestration-concurrency` was built to eliminate — concurrent
  editors racing on one file — and `fleet-autonomy` REQ-F1.1 already forbids new shared-write
  accumulators.
- A presence daemon or network service towers register with. Rejected because: it needs standing infra,
  breaks the local-first / no-remote-required posture `orchestration-concurrency` guarantees, and would
  itself be an LLM-free daemon the fleet has to supervise — heavier than the problem.
- Infer peers from scanning tmux sessions / process tables directly. Rejected because: it is
  backend-specific (only works under tmux), fragile screen/process scraping of the exact kind the fleet
  doctrine replaces with deterministic signals, and carries no spec-attribution.

**Chosen because:** the land-distinct-files-per-writer pattern is already proven twice in the codebase —
the observations fragment store and the attention store — so concurrent towers never collide by
construction; discovery stays a deterministic on-demand scan; and reusing `fleet-death-evidence.sh` for
liveness keeps reclaim on positive evidence, never a bare timeout.

### D-3: Separate per-tower checkouts as the shared-`main` root fix; single-checkout reconcile is the fallback (N)

**Decision:** The root fix for the shared-`main` clobbering race is **one checkout per tower** — separate
working copies, each with its own private mutable local `main`, coordinating through `origin` (fetch,
PRs) and the presence/claim surfaces rather than through a shared local `main`. Today's mitigation
(local `main` kept read-only, reconcile via a quick PR, never `reset --hard` or direct-push) is
superseded as the *primary* model and retained only as the sanctioned **degraded fallback** for
environments where separate checkouts are unavailable. The per-tower-checkout model changes nothing
about `orchestration-concurrency`'s derived-projection state model or the never-rewrite-history
invariants; it removes the shared mutable `main` those guarantees have to defend on a single checkout.

**Alternatives considered:**
- Keep single-checkout reconcile-via-quick-PR as the primary model. Rejected because: it is a mitigation,
  not a fix — both towers still share one mutable local `main` and depend on every tower's discipline to
  never `reset --hard` or direct-push; a single lapse clobbers a peer's unpushed commits, which is the
  incident this concern was mined from. A root fix removes the shared mutable surface instead of policing
  writes to it.
- Serialize `main` behind a single-writer lock across towers. Rejected because: it defeats the
  concurrency the fleet exists to provide (towers block on one lock) and still leaves one corruption
  surface; the per-spec advisory lock already scopes ledger writes and should not be widened into a
  global `main` mutex.
- Multiple `git worktree`s of one clone, one per tower. Rejected because: git forbids checking out the
  same branch (`main`) in two worktrees, and all worktrees still share the single `main` ref and object
  store — so the shared-`main` reconcile collision is not removed, only relocated. Separate checkouts
  (separate clones) are what give each tower a genuinely private `main`.

**Chosen because:** separate checkouts hand each tower a private mutable `main` using git's own isolation
model, with no new lock and no standing service; the operational experience of running two towers on one
checkout already pointed to separate per-tower checkouts as the documented root fix; and the fallback rung
keeps the single-checkout flow working where a second checkout cannot be provisioned (degrade capability,
never safety).

### D-4: Reuse the meta-tower selection and the attributed relay; the peer work-claim is additive (C, `orchestration-fleet D-7`)

**Decision:** Coordination reuses `orchestration-fleet`'s two shipped coordination surfaces unchanged —
the meta-tower's cross-spec selection under the fleet bound, and the attributed, non-impersonating
buffer-paste relay — and adds **only** the missing piece: a peer work-claim for the case where towers are
started independently with no meta-tower assigning disjoint slices. The claim mechanism composes with the
division-of-labor doctrine (each actor owns a disjoint slice; no tower writes into another's slice); it
never introduces a second relay or a competing division authority.

**Alternatives considered:**
- Build a new coordination channel for peer towers. Rejected because: it would duplicate the audited
  relay (`scripts/orchestrate-relay.sh`) and split the never-impersonate discipline across two
  implementations — the exact single-tested-place property the relay doctrine was built to preserve.
- Require a meta-tower always, so division is always assigned top-down. Rejected because: two
  independently-started peer towers on one repo are a real, supported, documented pattern; forcing a
  meta-tower for every concurrent run is heavier than the case needs and does not match how operators
  actually run fleets.

**Chosen because:** the relay and meta-tower selection already exist and are audited; the only genuine
gap for the peer case is *claiming a unit before dispatch*, so the honest design is an additive claim
layer, not a parallel coordination stack.

### D-5: Work-claim before dispatch, reclaimable only on positive evidence of death (C, `fleet-death-evidence`)

**Decision:** A tower writes a **claim record for a unit before dispatching it** (a distinct-per-writer
file on the shared blackboard, naming the unit, the claiming tower's identity, and a timestamp). A peer
tower selecting work honors any live claim and skips that unit; a claim is reclaimable **only** when the
claiming tower is positively dead per `fleet-death-evidence.sh`, never on a bare timeout or model
judgment. The claim read-check-write is performed **within** `orchestration-concurrency`'s per-spec
advisory lock window: two towers targeting the same unit both operate on that unit's spec and so
serialize on that spec's lock, the second observing the first's claim — closing the claim TOCTOU that
distinct-per-writer files alone would leave open. The claim is a coarser coordination signal than the
ledger write the lock also guards: it prevents two towers from *selecting* the same unit, where the
lock additionally serializes the resulting bookkeeping write.

**Alternatives considered:**
- Optimistic dispatch, then detect-and-resolve the conflict afterward. Rejected because: two towers
  would launch two workers on one unit, burning worker cycles and risking two PRs for the same task —
  the conflict is far cheaper to prevent at selection than to reconcile after two branches exist.
- A hard per-unit lock with no death-based reclaim. Rejected because: a tower that crashes holding the
  lock strands its unit permanently, the failure mode `fleet-death-evidence` exists to prevent; a claim
  reclaimable on positive death evidence self-heals.

**Chosen because:** claim-before-dispatch converts an expensive after-the-fact conflict into a cheap
pre-selection check, and reusing the positive-evidence-of-death predicate keeps a crashed tower from
stranding work while still never reclaiming a live tower's unit on a guess.

### D-6: Scope boundary — usage governance and the relay stay in their own bundles (N)

**Decision:** Two adjacent, tempting-to-absorb concerns are held **out of scope** with a single owner
each: (a) proactive shared-usage / quota governance (reading global `/usage`) is `fleet-autonomy`'s, which
already owns the reactive rate-limit throttle; (b) the attributed non-impersonating relay is
`orchestration-fleet`'s. This bundle cross-references both and implements neither.

**Alternatives considered:**
- Absorb usage governance here, since reading `/usage` is inherently cross-tower-aware. Rejected because:
  it is already being folded into `fleet-autonomy`, and splitting it across two bundles creates two owners
  for one mechanism — the opposite of the single-owner discipline; awareness of *peers* and awareness of
  *shared quota* are separable, and only the former is this bundle's job.
- Absorb the relay, since coordination uses it. Rejected because: it would fork audited code and the
  never-impersonate discipline; consuming it as a contract keeps one tested implementation.

**Chosen because:** each adjacent concern already has a home and an owner; this bundle stays exactly the
awareness + checkout-isolation + peer-claim layer the fold-detection identified, and the cross-references
keep the seams legible without duplicating mechanism.

## Cross-cutting concerns

- **State-safety is assumed, never restated.** Every mechanism here sits on top of
  `orchestration-concurrency`'s derived-projection ledger and per-spec lock. This bundle adds no new
  writer to `tasks.md` and no new committed state artifact; presence and claims are derived, on-demand,
  distinct-per-writer surfaces.
- **Determinism floor.** Presence discovery, liveness, claim honoring, and reclaim are all deterministic
  script logic over structured signals (files, PIDs, git/`gh` state, the death-evidence predicate). No
  awareness or division decision invokes an LLM (the no-LLM-daemon-mechanics floor).
- **Security.** Tower identity on the presence and claim surfaces is attributed and validated before a
  peer acts on it; peer output consumed for awareness is data, never code; committed coordination
  artifacts are secret-clean (the `security-posture` artifact-hygiene rule and the relay security bounds,
  carried). Attribution is scoped to the **same-operator, single-host** trust model — peer towers are the
  operator's own co-located sessions — so validation grammar-checks the identity token and refuses a
  malformed one, but does not defend against an adversarial peer forging identity (a co-tenant threat is
  out of scope, not a mechanism here).
