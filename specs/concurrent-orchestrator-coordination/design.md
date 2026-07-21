# Concurrent Orchestrator Coordination — Design

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** / **C, `<doctrine>`** —
carried: this bundle reuses an existing decision or doctrine floor from a named sibling rather than
inventing a parallel one.

The design leads with the altitude record (D-1), then the three mechanisms in impact order:
presence/awareness (D-2), the shared-`main` root fix (D-3), and the peer work-claim (D-4, D-5, plus its
lifecycle and safe-reclaim rules in D-7), closing with the scope boundary that keeps adjacent concerns
in their own homes (D-6). Every mechanism sits above `orchestration-concurrency`'s state-safety floor
and reuses `orchestration-fleet`'s relay and meta-tower selection rather than forking them.

**Decision-domains walk.** The feature crosses several catalogued stake-bearing domains, all decided
in-spec rather than auto-defaulted: **concurrency** (the central domain — shared coordination surfaces,
claim serialization across separate clones, crash-mid-flight reclaim; decided by the atomic
exclusive-create claim primitive in D-5 / REQ-C1.1 (which serializes cross-clone where the checkout-local
lock cannot), the death-evidence reclaim with concurrent-reclaimer serialization and a downstream-artifact
guard in D-7, and the presence/claim collision-semantics split); **integration surface** (the git
checkout / origin coordination topology and the hardened `main`-currency sync — decided in D-3);
**authentication / attribution** (tower identity on the presence and claim surfaces — decided by carrying
`inter-orchestrator-coordination`'s relay security bounds scoped to the same-operator single-host trust
model, enforced at the surface by user-private permissions and at the script boundary by the
framework-script security bars, REQ-D1.4, REQ-D1.5, REQ-A1.4); and **observability** (a broken presence
surface must not read as solitude, and a corrupt record must not read as absence — decided by the
fail-closed discovery and per-record fail-closed requirements REQ-A1.5, REQ-A1.6). Secrets/config is
conditional (documented in the options reference only if the surface path becomes configurable). No other
catalogued domain is touched-but-undecided.

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
are out of scope per Scope). Because that path is a single host-wide surface shared by *every*
repository's clones, it is partitioned by **repository identity**: records live under a per-repository
scope and each record carries its repo id, so discovery for one repository never mistakes another
repository's towers for peers (REQ-A1.1, REQ-A1.2). That repo id is derived from an **origin-anchored
signal** (a normalized `origin` remote URL or equivalent fingerprint) identical across separate clones
of the same repository — deliberately *not* the local checkout path, which differs per clone and would
make two genuine peers compute different ids, fail to see each other, and silently defeat the surface.
The surface further separates its two sub-surfaces
by their opposite collision semantics (the presence/claim discriminator): **presence** is
distinct-per-writer — one file per tower, keyed by tower identity, which must never collide — while
**claims** (D-5) are unit-keyed and must collide so exactly one tower wins a unit. The surface directory
is **user-private** (`0700`): that access control is what enforces the same-operator single-host trust
model (REQ-A1.4, REQ-D1.4). Each tower writes and heartbeat-refreshes its own record **atomically**
(write-temp-then-rename, so a reader never sees a torn record), carrying identity, repo id, checkout
path, spec(s) advanced, start time, last-beat, the positive-evidence-of-death handle by which a peer
confirms its liveness, and the `fleet-tower-marker.sh` meta-tower marker. A tower discovers peers by
scanning that directory, excluding its own record, and applying the positive-evidence-of-death liveness
predicate — which is tri-state (alive / positively-dead / unknown), and only *positively-dead* permits
reclaim (an unknown or errored result is treated as not-dead; a stale heartbeat alone never proves
death). No tower ever edits another *live* tower's file content, and there is no single registry file
that all towers mutate; a discovering tower MAY delete a positively-dead tower's entire file as garbage
collection (deleting a whole dead file is not editing a live peer's content, so it does not reintroduce
the shared-write corruption surface). A record that is malformed or truncated fails closed for that
record — skipped with a surfaced error, never read as "no such peer" (REQ-A1.6). The set of live towers
is *derived* from the scan on demand, never a committed or hand-maintained artifact. Discovery fails
closed on an absent-but-unreadable or misconfigured surface rather than reading emptiness as solitude;
a first-run surface that does not yet exist is the healthy-empty bootstrap case — the tower creates the
user-private directory and proceeds empty, ordered so it never reads the surface as absent between
creating and populating it (REQ-A1.5).

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

The cross-checkout `main`-currency sync is hardened against three edge cases (REQ-B1.4): it is
**fast-forward-only** (`git fetch origin main && git merge --ff-only FETCH_HEAD`) — because a private
`main` is never directly committed to (commits ride task branches; merges reach `origin` via PR),
currency is always a fast-forward, so `--ff-only` costs nothing on the happy path and turns any
unexpected divergence into an explicit refusal instead of a silent merge commit; it runs only with
`main` as the checked-out branch (or operates on the `main` ref explicitly), so it can never merge
`origin/main` onto a worker branch (the "dragging foreign commits onto a worker branch" hazard); and a
failed `git fetch` fails closed — the tower surfaces the failure rather than proceeding on a
silently-stale `main`. The explicit `fetch … && merge` form (never a bare `git pull`) is also what
neutralizes the `branch.autosetuprebase=always` pitfall, in which a bare pull silently becomes a
forbidden rebase.

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

### D-5: Work-claim before dispatch, serialized by an atomic create-with-content on the machine-local surface (N)

**Decision:** A tower claims a unit before dispatch by an **atomic, exclusive create-with-content of a
unit-keyed claim object** on the shared machine-local surface. The claim object is keyed by the unit's
stable id under the repository scope (`<surface>/<repo-id>/claims/<unit-id>`); the create **is** the
serializer: the first tower's create succeeds and it owns the unit, while a losing tower's create fails
atomically, whereupon it reads the existing claim and skips the unit. Crucially the create is *both*
exclusive (fails if the name exists) *and* atomic-with-content (the claim carries the owner identity and
self-contained death handle the instant it appears): a bare `mkdir` gives exclusivity but leaves a crash
window in which the claim exists empty (a tower dying between `mkdir` and populating it would strand the
unit, since an empty claim fails closed under REQ-A1.6 and cannot be liveness-checked), while a plain
temp-then-rename gives atomic content but not exclusivity (rename overwrites, so two towers both
"succeed"). The primitive that gives both is a **hardlink of a fully-written temp** into the unit-keyed
name — `link(2)` fails if the name already exists (exclusive) yet the name resolves to complete content
the instant it exists (atomic-with-content). Because the surface is machine-local and shared by all
co-located clones, this serializes peer towers **across separate per-tower checkouts (D-3)** — precisely
where the checkout-local per-spec lock cannot, because each clone's lock is a different filesystem path.
A claim is reclaimable **only** when the claiming tower is positively dead per `fleet-death-evidence.sh`,
and reclaim is serialized by an **atomic rename-aside**, not a delete-then-recreate (D-7 governs the
reclaim's safety and explains why the naive delete-then-recreate reintroduces double-dispatch).

This corrects the walkthrough's earlier framing (S3), which put the claim read-check-write inside the
per-spec lock and modeled the claim as a distinct-per-writer record. Both were wrong for claims
specifically: the lock is checkout-local (so it never contends across separate clones — the kickoff §8
inconsistency), and distinct-per-writer is the collision semantics the *presence* surface needs (tower
records must never collide) but the exact inverse of what a *claim* needs (unit records must collide so
exactly one tower wins). Making the claim a unit-keyed atomic-create object fixes the locality and the
semantics together, and gives the presence/claim surfaces a structural discriminator (D-2) rather than a
by-convention one.

**Alternatives considered:**
- **A separate machine-local advisory lock** (a second `mkdir` lock keyed by unit at the surface) taken
  around a read-check-write of a still-distinct-per-writer claim record. Rejected because: it keeps two
  primitives where one suffices — a lock *and* a record, each with its own staleness-break and failure
  modes — and still owes a separate presence/claim discriminator. The atomic-create collapses the lock
  and the record into one object; there is no separate serializer to misplace, so the whole "lock says X
  but record says Y" skew class cannot exist. It is the same locality fix with strictly fewer moving
  parts.
- **Keep the checkout-local per-spec lock as the claim serializer** (the pre-rework design). Rejected
  because: that is exactly the kickoff §8 inconsistency — under D-3's separate clones the lock never
  contends across peers, so the TOCTOU is open under the primary topology.
- **Optimistic dispatch, then detect-and-resolve the conflict afterward** (rely on the branch-as-fence
  after two branches exist). Rejected because: two towers launch two workers on one unit, burning worker
  cycles and risking two PRs for one task; the operator's framing is that peer towers already race today,
  so preventing the collision at selection beats reconciling it after the fact. (The branch-as-fence is
  still reused, but as the reclaim *guard* in D-7, not as the primary anti-collision mechanism.)
- **A hard per-unit lock with no death-based reclaim.** Rejected because: a tower that crashes holding
  the claim strands its unit permanently — the failure mode `fleet-death-evidence` exists to prevent; a
  claim reclaimable on positive death evidence self-heals.

**Chosen because:** the atomic, exclusive create-with-content makes the claim its own serializer at the
correct (machine-local, cross-clone) locality, reusing the codebase's own filesystem-atomicity idiom
rather than inventing a new lock; it converts an expensive after-the-fact conflict into a cheap pre-selection check;
and reusing the positive-evidence-of-death predicate keeps a crashed tower from stranding work while
never reclaiming a live tower's unit on a guess.

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

### D-7: Claim lifecycle and safe reclaim — self-contained handle, bounded lifetime, downstream-artifact-guarded (N)

**Decision:** The claim object (D-5) carries the rules that keep it correct across a tower's whole
lifecycle, not just at the instant of the create:

- **Self-contained death handle.** Each claim object records the claiming tower's identity and its
  positive-evidence-of-death handle *inside the claim itself*, independent of that tower's presence
  record. Reclaim therefore never depends on the presence file still existing — presence garbage
  collection (D-2) can delete a dead tower's presence file without leaving its surviving claim
  permanently un-reclaimable.
- **Bounded lifetime (release + discovery GC).** A tower releases its claim once the unit is handed off
  — its worker is dispatched and a branch/PR exists, so `orchestration-concurrency`'s branch-as-fence
  takes over the "already in flight" signal — and releases it *immediately* on a dispatch failure, so a
  failed dispatch never leaves a live-tower claim stranding the unit. Independently, dead-tower claims
  are garbage-collected **during discovery** — any claim whose owner is positively dead is swept when
  the surface is scanned, symmetric with the presence-file GC (D-2) — *not* only along the reclaim path
  of a unit some peer happens to re-select. Without the discovery sweep, a claim left by a tower that
  died after dispatch (whose worker may already have completed the unit, so no peer ever re-selects it)
  would leak on the surface forever. Claims thus do not outlive their coordination need and the claims
  surface does not grow unbounded (REQ-C1.5).
- **Serialized, artifact-guarded reclaim.** Reclaim is serialized by an **atomic rename-aside**, not a
  delete-then-recreate: a reclaiming tower first atomically renames the dead claim aside to a
  reclaimer-owned name (`claims/<unit>` → `claims/.reclaiming-<unit>-<id>`), which by `rename(2)`'s
  atomicity exactly one concurrent reclaimer can perform (the source vanishes after the first rename, so
  every other reclaimer's rename fails and it re-reads). Only the rename winner then confirms death and
  takes the unit by the normal create-with-content (D-5). A **delete-then-recreate reclaim is unsafe**
  and is rejected: between one reclaimer's `rm` and its re-create, a second reclaimer's `rm` can delete
  the first's freshly created claim, so both proceed — the exact double-dispatch the mechanism exists to
  prevent (the atomic re-create alone does *not* serialize reclaimers, because the destructive `rm` that
  precedes it is unguarded). Before re-dispatching a reclaimed unit, the reclaim winner confirms **no
  live downstream dispatch artifact** exists for it — no branch, no open PR (the branch-as-fence) —
  because `fleet-death-evidence` proves the *tower* dead, not its *worker*: a tower can die after
  dispatching a worker that is still running or has already opened a PR, and re-dispatching then doubles
  the work. The artifact check closes that gap.
- **Tri-state liveness, never a guess.** Honoring and reclaim both run on the tri-state death predicate
  (alive / positively-dead / unknown): only positively-dead permits reclaim; unknown or errored is
  treated as not-dead. A live-but-hung tower is *alive*, so its claim is honored and never
  auto-reclaimed — recovering that unit is an operator-intervention case, not an automatic one. This is
  the deliberate scoping of REQ-C1.3's guarantee: a *crashed* tower never strands a unit, but the design
  does not (and safely cannot) auto-recover a *live-but-hung* one without risking double-dispatch.
- **No held critical section.** Because the serializer is an atomic filesystem step (the
  create-with-content for an initial claim, the rename-aside for a reclaim), there is no lock held across
  the subprocess-heavy death check: the atomic step returns immediately, and liveness/artifact checks run
  afterward on a claim already known to be contested — so the death predicate never sits inside a
  critical section (no livelock, no critical-section cost).

**Alternatives considered:**
- Keep the death handle only in the presence record (the pre-rework shape). Rejected because: presence
  GC deletes it, leaving a surviving claim un-reclaimable — the kickoff §8 finding #3.
- Delete-then-recreate reclaim (`rm` the dead claim, then atomic create). Rejected because: the `rm`
  preceding the create is unguarded, so two concurrent reclaimers can each delete the other's freshly
  created claim and both proceed — double-dispatch (the panel-review G5 finding). The atomic rename-aside
  makes the *right to break* the dead claim the serialized step, which the bare re-create is not.
- GC dead claims only lazily, when a peer re-selects the unit. Rejected because: a claim from a tower
  that died after dispatch, on a unit its worker then completed, is never re-selected and leaks forever
  (the panel-review G4 finding); the discovery sweep bounds the surface.
- Reclaim on tower-death alone, without the downstream-artifact check. Rejected because: it
  double-dispatches whenever a dead tower's worker outlived it (finding #5); the branch-as-fence check
  is cheap and already the state-safety contract.
- Auto-reclaim a hung-but-alive tower after a timeout. Rejected because: it violates the
  positive-evidence-of-death floor and races the still-live tower into double-dispatch; stranding on a
  genuine hang is the safer failure, surfaced for operator intervention.

**Chosen because:** the claim's correctness lives across the tower's lifetime, not just at the create;
folding the death handle, the release/GC lifetime, the serialized artifact-guarded reclaim, and the
tri-state liveness into one decision keeps D-5 focused on the serialization primitive while D-7 carries
the safety envelope the kickoff §8 backlog (#3, #4, #5, #12, #13, #14) demanded.

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
  out of scope, not a mechanism here). Because the coordination scripts nonetheless parse records other
  sessions wrote, they meet planwright's **framework-script security bars** (REQ-D1.5): *every* parsed
  identifier — tower id, repository id, unit id, spec id — is grammar-validated before use, not only the
  tower token; path access is **canonicalized and containment-checked** before any read, write, or
  unlink, so a crafted unit/tower id can never drive the reclaim path's `rm` or a record write outside
  the surface; and untrusted record fields echoed to a terminal or log pass the echo-discipline
  sanitizer (`scripts/echo-safety.sh`, `sanitize_printable`). Two further surfaces of the trust model:
  the surface directory is **user-private** (`0700`, REQ-A1.4) — access control is what actually enforces
  "same operator" — and a peer tower's machine-local **checkout path is operational detail that must not
  leak** from the surfaces into a committed artifact such as a PR body (REQ-D1.4).
