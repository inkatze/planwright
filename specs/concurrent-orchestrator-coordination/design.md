# Concurrent Orchestrator Coordination — Design

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** / **C, `<doctrine>`** —
carried: this bundle reuses an existing decision or doctrine floor from a named sibling rather than
inventing a parallel one.

## Correctness model (read this first)

The load-bearing question this bundle must answer — the one two kickoff halts turned on — is **what is
the authoritative guarantee that no unit is dispatched by more than one tower, and is it live across
separate per-tower clones (D-3) at the moment of dispatch.** The answer is a **two-layer model**, stated
here up front so every mechanism below is read against it:

1. **Authoritative layer — the dispatch-time origin fence (D-8).** At dispatch, before any worker runs, a
   tower **atomically creates the unit's task-branch ref on `origin`** by a compare-and-swap that
   succeeds only if the ref does not already exist (`git push --force-with-lease=refs/heads/<branch>:`
   with an empty expected value; `origin` accepts exactly one such create per unit, rejecting every
   subsequent one). Because the ref lives on `origin`, this fence is **live cross-clone from the instant
   of dispatch** — not from PR-open hours later — and it **survives the dispatching tower's death**
   (the ref persists on `origin` regardless of the tower's fate). It is the single authoritative
   no-duplicate-*dispatch* guarantee, and it is what the reclaim path's downstream-artifact guard (D-7)
   reads to know a unit is in flight.
2. **Best-effort layer — the machine-local work-claim (D-5, D-7).** The unit-keyed atomic claim on the
   shared machine-local surface is a **pre-selection optimization above the fence**: it keeps two peer
   towers from usually *selecting* one unit and racing to the fence at all. Every residual filesystem
   race in the claim/reclaim layer (GC, stale-lock-break, process-pause) therefore degrades to at most
   **wasted selection work resolved by the fence**, never a double dispatch.

This corrects the pre-rework framing, which named `orchestration-concurrency`'s branch-as-fence as
authoritative but relied on the **local** task-branch ref — invisible across separate clones until
PR-open — so a claim lost in the dispatch→first-push window let a peer clone dispatch a *second full
worker* (a double **dispatch**, not "wasted selection work"). D-8 closes that window by moving the fence
to `origin` at dispatch. **Preconditions D-8 requires:** a reachable `origin` (separate-clone multi-tower
is an origin-coordinated topology; the no-remote case is the single-checkout solo flow, where one tower
needs no cross-clone fence — REQ-C1.6, REQ-B1.4), and **byte-identical task-branch names across clones**
so both clones contend for the *same* `origin` ref (the `claude --worktree` name-mangling pitfall is
accounted for — REQ-C1.6).

The design then leads with the altitude record (D-1), the three mechanisms in impact order —
presence/awareness (D-2), the shared-`main` root fix (D-3), and the peer work-claim (D-4, D-5, its
authoritative dispatch fence in **D-8**, and its lifecycle and safe-reclaim rules in D-7) — the
fail-closed recovery actions that say what a tower *does* after each refusal (D-10), the numbered home
for the framework-script security bars and the attribution model (D-9), and the scope boundary that
keeps adjacent concerns in their own homes (D-6). Every mechanism sits above
`orchestration-concurrency`'s state-safety floor and reuses `orchestration-fleet`'s relay and meta-tower
selection rather than forking them.

**Decision-domains walk.** The feature crosses several catalogued stake-bearing domains, all decided
in-spec rather than auto-defaulted: **concurrency** (the central domain — shared coordination surfaces,
claim serialization across separate clones, crash-mid-flight reclaim; decided by a two-layer model — the
authoritative no-duplicate-dispatch guarantee is the **dispatch-time origin fence** (an atomic
compare-and-swap task-branch-ref create on `origin`, live cross-clone from dispatch and death-surviving,
D-8), with the machine-local claim + reclaim-lock as a best-effort optimization above it (D-5, REQ-C1.1,
REQ-C1.6) — plus the atomic create-with-content claim primitive (which serializes cross-clone where the
checkout-local lock cannot), the death-evidence reclaim serialized by a per-unit lock with an under-lock
re-read and an origin-ref downstream-artifact guard in D-7, and the presence/claim collision-semantics
split); **integration surface** (the git
checkout / origin coordination topology and the hardened `main`-currency sync — decided in D-3);
**authentication / attribution** (tower identity on the presence and claim surfaces — decided by carrying
`inter-orchestrator-coordination`'s relay security bounds scoped to the same-operator single-host trust
model, enforced at the surface by user-private permissions and at the script boundary by the
framework-script security bars, REQ-D1.4, REQ-D1.5, REQ-A1.4); and **observability** (a broken presence
surface must not read as solitude, and a corrupt record must not read as absence — decided by the
fail-closed discovery and per-record fail-closed requirements REQ-A1.5, REQ-A1.6, with the **defined
recovery action after each fail-closed refusal** — halt-dispatch vs degrade-to-solo vs surface — pinned
per path in D-10 so "fail closed" never means "and then what?"). Secrets/config is
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
model (REQ-A1.4, REQ-D1.4). The surface directory is created with an atomic, mode-explicit `mkdir` and,
because the `0700` bit is *the* trust enforcement, a pre-existing surface directory whose mode is
**over-broad** (group/other-accessible) is **refused, not silently reused** — verify-or-refuse, so an
attacker-planted or mis-permissioned surface can never quietly widen the trust boundary (REQ-A1.4).

Each tower writes and heartbeat-refreshes its own record **atomically** (write-temp-then-rename, so a
reader never sees a torn record), keyed by a **tower identity** and carrying that identity, the repo id,
the checkout path, spec(s) advanced, start time, last-beat, a positive-evidence-of-death handle, and a
**meta-tower marker that is the presence record's own field** (a validated boolean the tower stamps from
its own `--meta` mode — *not* `fleet-tower-marker.sh`, whose stored field is the `unattended|interactive`
recovery mode, an orthogonal axis; the earlier draft mis-cited it). **Tower identity** is derived from
the Claude **session id (UUID)** where present — unique per session, the natural per-tower key on which
both distinct-per-writer publication and self-exclusion rest — falling back, where no session id is
available, to a composite of pid + process start-time + a checkout-path hash (never the bare pid, which
is reuse-prone, and never the checkout path alone, which two towers on one checkout would share);
the derivation is specified so two towers never compute one identity (collision → overwrite a peer's
record) and a tower never mistakes a peer for itself (REQ-A1.7). The **death handle** is one of exactly
the two forms `fleet-death-evidence.sh` accepts — `process <pid>` or `tmux-window <session> <window>` —
and a tower **publishes the reuse-resistant `tmux-window` handle where it runs under tmux** (the fleet
norm; the tmux server is authoritative and its window ids are not reused the way pids are), keeping the
bare-`process <pid>` form as the documented degraded fallback for a tower not under tmux, whose residual
PID-reuse *strand* (a reused pid reading as alive → a dead tower's record honored) is availability-only
and operator-recoverable under the authoritative D-8 fence, never a double dispatch (REQ-A1.3, D-7).

A tower discovers peers by scanning that directory, excluding its own record, and applying the
positive-evidence-of-death liveness predicate — which is tri-state (alive / positively-dead / unknown),
and only *positively-dead* permits reclaim (an unknown or errored result is treated as not-dead; a stale
heartbeat alone never proves death). To bound the per-record subprocess cost (the death predicate is a
subprocess per record), discovery **caches each peer's liveness verdict for the pass** and runs on a
capped heartbeat cadence rather than fanning out unboundedly per record per beat (REQ-A1.1). No tower
ever edits another *live* tower's file content, and there is no single registry file that all towers
mutate; a discovering tower may garbage-collect a positively-dead tower's entire file, but — symmetric
with the hardened claim GC (D-7) and unlike the earlier unguarded `rm` — **only under a re-read that
re-confirms the record is still that same positively-dead tower's** immediately before the unlink, so a
dead-then-restarted tower's *fresh live* record (same identity, new session) is never deleted out from
under it (REQ-A1.3). Deleting a whole dead file is not editing a live peer's content, so it does not
reintroduce the shared-write corruption surface. A record that is malformed or truncated fails closed
for that record — skipped with a surfaced error, never read as "no such peer" (REQ-A1.6). The set of
live towers is *derived* from the scan on demand, never a committed or hand-maintained artifact.
Discovery fails closed on an absent-but-unreadable or misconfigured surface rather than reading emptiness
as solitude; a first-run surface that does not yet exist is the healthy-empty bootstrap case — the tower
creates the user-private directory and proceeds empty, ordered so it never reads the surface as absent
between creating and populating it, and a **persistence sentinel** distinguishes a genuine first run
(no surface ever existed) from a surface that existed and then *vanished* (which fails closed rather than
reading as first-run solitude — REQ-A1.5, D-10).

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

**Decision:** The authoritative no-duplicate-dispatch guarantee is **not** the claim — it is the
**dispatch-time origin fence (D-8)**: at dispatch a tower atomically creates the unit's task-branch ref
on `origin` (compare-and-swap, succeeds only if the ref is absent), which `origin` arbitrates to exactly
one winner, live cross-clone from the instant of dispatch and death-surviving. (This supersedes the
pre-rework framing that named the *local* branch-ref as the fence — that ref never reached `origin` until
PR-open, so it fenced nothing across separate clones during the whole worker run, the run-2 halt.) The
claim layer this decision builds is a **best-effort optimization above that fence**: it keeps two peer
towers from usually *selecting* the same unit and racing to the fence, but is not relied on for
correctness, because a filesystem claim on a shared surface cannot be authoritative under
garbage-collection, stale-lock-break, and process-pause races (three rounds of review converged on this;
every such race degrades to at most wasted selection work, never a double dispatch, precisely because the
D-8 origin fence catches the duplicate before a second worker starts). Within that best-effort role: a
tower claims a unit before dispatch by an **atomic, exclusive create-with-content of a unit-keyed claim
object** on the shared machine-local surface. The claim object is keyed by the unit's
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
A claim is reclaimable **only** when the claiming tower is positively dead per `fleet-death-evidence.sh`.
Unlike the initial claim, reclaim is a read → check → swap that cannot be a single atomic filesystem
step, so it is serialized by a **per-unit reclaim lock held only across the fast swap**, with the slow
death/artifact checks outside it and an under-lock re-verification that the claim is still the same dead
owner (D-7 governs the reclaim's safety and explains why the lock-free schemes — the original in-lock
ordering and the rename-aside — do not hold).

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
- **Optimistic dispatch, then detect-and-resolve the conflict afterward** (let two branches exist, then
  reconcile). Rejected because: two towers launch two workers on one unit, burning worker cycles and
  risking two PRs for one task; the operator's framing is that peer towers already race today, so
  preventing the collision beats reconciling it after the fact. (The origin fence of D-8 *is* the
  authoritative anti-collision mechanism, applied atomically **at dispatch** so no second worker ever
  launches — not an after-the-fact reconcile; the machine-local claim of D-5 is the cheap pre-selection
  optimization that keeps towers from racing to that fence in the first place.)
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
  — its worker is dispatched and the **origin task-branch ref exists (D-8)**, so the origin fence takes
  over the "already in flight" signal — and releases it *immediately* on a dispatch failure, so a failed
  dispatch never leaves a live-tower claim stranding the unit. A release `rm` that *fails* (a live tower
  that cannot remove its own claim) does not strand the unit: the tower surfaces the failure and retries,
  and the claim is backstopped by the discovery GC once the tower is positively dead — a release failure
  degrades to a bounded delay, never a permanent block. Independently, the discovery sweep garbage-collects
  three residues, each under the **same per-unit reclaim lock and under-lock re-read as the reclaim path**
  (an unguarded GC `rm` would delete a claim a concurrent reclaimer had just swapped for a fresh live one,
  so every GC remove is a locked, identity-verified remove):
  1. **Dead-tower claims** — any claim whose owner is positively dead — symmetric with the presence-file
     GC (D-2), *not* only along the reclaim path of a unit some peer happens to re-select. Without this,
     a claim left by a tower that died after dispatch (whose worker may already have completed the unit,
     so no peer ever re-selects it) would leak forever.
  2. **Stale reclaim locks** — a per-unit reclaim lock left by a reclaimer that crashed mid-swap, broken
     past the stale threshold by the same `mkdir`-plus-stale-break discipline the per-spec advisory lock
     uses, so a crashed reclaimer never wedges a unit's reclaim path permanently.
  3. **Orphan temp files** — a temp file from an interrupted atomic create-with-content (the tower died
     between writing the temp and hardlinking it into the unit-keyed name), swept past a threshold so
     abandoned temps do not accumulate and poison the scan. The temp is created **inside the surface
     directory** (same filesystem as the claim name) so the hardlink/rename is atomic and cannot hit
     `EXDEV`.

  Distinct from all three: a **corrupt (unparseable) claim record** cannot be liveness-checked at all
  (GC must parse the owner + death handle to prove death), so under the fail-closed rule (REQ-A1.6) it
  would be honored forever and strand its unit. On repeated parse failure across discovery passes the
  sweep **quarantines** it — moves it to a containment-checked dead-letter sub-surface and surfaces it
  for the operator — so the unit becomes re-selectable rather than permanently blocked, without a blind
  delete of a record whose contents cannot be trusted. Under the D-8 fence this strand was
  availability-only (never a double dispatch); the quarantine converts it from permanent to
  operator-visible-and-recoverable (REQ-A1.6, REQ-C1.5). Claims thus do not outlive their coordination
  need and the claims surface does not grow unbounded (REQ-C1.5).
- **Serialized, artifact-guarded reclaim.** Reclaim is a read → check → swap that *cannot* be collapsed
  into a single atomic filesystem step (the way the initial claim can), so it is serialized by a
  **per-unit reclaim lock held only across the fast swap**: (1) read the claim; a live or unknown owner
  is honored, no mutation; (2) **outside the lock**, confirm the owner positively dead and that no live
  downstream dispatch artifact exists — **the unit's task-branch ref on `origin` (D-8) or an open PR** —
  because `fleet-death-evidence` proves the *tower* dead, not its *worker*: a tower can die after
  dispatching a worker that still runs, and because the D-8 fence pushes the ref to `origin` **at
  dispatch** (not at PR-open), that ref is present from the moment the orphan worker started, so the
  guard sees the in-flight worker and does **not** re-dispatch (the run-2 orphan-worker finding; the
  pre-rework local-branch guard was blind to a not-yet-pushed orphan). (3) acquire the
  per-unit reclaim lock (a `mkdir` lock on the surface, stale-broken by the same discipline the per-spec
  advisory lock uses; a busy lock → a peer is mid-swap → skip this round); (4) **under the lock, re-read
  the claim** and proceed only if it is still exactly that dead owner's claim — else abort untouched —
  then remove it and compete for the unit by the normal create-with-content (D-5), which yields a single
  holder even against a fresh claimant; (5) release the lock. The under-lock re-read is the safety
  hinge, and the death check stays *outside* the lock so no lock is ever held across a subprocess.
- **Tri-state liveness, never a guess.** Honoring and reclaim both run on the tri-state death predicate
  (alive / positively-dead / unknown): only positively-dead permits reclaim; unknown or errored is
  treated as not-dead. A live-but-hung tower is *alive*, so its claim is honored and never
  auto-reclaimed — recovering that unit is an operator-intervention case, not an automatic one. This is
  the deliberate scoping of REQ-C1.3's guarantee: a *crashed* tower never strands a unit, but the design
  does not (and safely cannot) auto-recover a *live-but-hung* one without risking double-dispatch.
- **No lock across a subprocess.** The initial claim's serializer is a single atomic filesystem step
  (create-with-content), so it holds nothing. The reclaim's per-unit lock is held only across the fast
  under-lock swap (re-read + remove + compete-to-create), never across the subprocess-heavy death /
  artifact check, which runs *before* the lock is acquired — so the death predicate never sits inside a
  critical section (no livelock, no critical-section cost).
- **Best-effort under the origin fence.** The reclaim lock and the GC lock are best-effort serializers,
  not authoritative ones. A stale-break of a paused holder, or any lost lock, can let two towers proceed
  toward dispatch — but the **dispatch-time origin fence (D-8, REQ-C1.6)** resolves that to a single
  dispatch, so the residual filesystem-lock race costs at most wasted selection work, never a double
  dispatch. The lock exists to make that waste rare, not to be the correctness boundary.

**Alternatives considered:**
- Keep the death handle only in the presence record (the pre-rework shape). Rejected because: presence
  GC deletes it, leaving a surviving claim un-reclaimable — the kickoff §8 finding #3.
- Lock-free rename-aside reclaim (`mv claims/<unit>` aside, then confirm death, then take). Rejected
  (panel-review iteration 2): it moves the claim *before* confirming death, destroying a *live* claim if
  it is ever contested, and it frees the unit during the slow check, letting a fresh claimant
  double-dispatch — the rename serializes reclaimers against each other but not against fresh claimants.
- Lock-free delete-then-recreate reclaim (`rm` the dead claim, then atomic create). Rejected because: the
  `rm` preceding the create is unguarded, so two concurrent reclaimers can each delete the other's freshly
  created claim and both proceed (the panel-review G5 finding). These two lock-free schemes, plus the
  walkthrough's checkout-local in-lock ordering (S3, the original §8 halt), are why reclaim takes a
  scoped per-unit lock: reclaim is a read-check-swap whose check is slow, so it cannot be a single atomic
  filesystem step the way the initial claim is. The lock is confined to reclaim; initial claims stay
  lock-free.
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

### D-8: The authoritative cross-clone fence is an atomic origin task-branch-ref create at dispatch (N)

**Decision:** The single authoritative guarantee that no unit is dispatched by more than one tower is a
**compare-and-swap creation of the unit's task-branch ref on `origin`, performed at dispatch, before any
worker runs.** The tower pushes the ref with an *expect-absent* precondition
(`git push --force-with-lease=refs/heads/<branch>: <base-sha>:refs/heads/<branch>`, whose empty expected
value means "succeed only if the ref does not yet exist"); `origin` serializes concurrent creators to
exactly one winner and rejects every other, whereupon a losing tower treats the rejection as
"already dispatched by a peer" and aborts without launching a worker. This ref is the durable,
peer-visible, **death-surviving** in-flight marker the whole coordination layer rests on: it is live
cross-clone from the instant of dispatch, and the reclaim path's downstream-artifact guard (D-7) reads
it to know a unit is in flight even when the dispatching tower has since died leaving a still-running
orphan worker.

Two preconditions are explicit:
- **A reachable `origin` is required for separate-clone multi-tower.** The fence *is* origin arbitration;
  separate per-tower clones (D-3) coordinate through `origin` by construction. The **no-remote case is the
  single-checkout solo flow** — one tower, no peer, no cross-clone fence needed — so this bundle does not
  claim multi-tower coordination without a remote (REQ-C1.6, REQ-B1.4); that is a documented boundary,
  not a silent gap. The repository identity's no-`origin` fingerprint (D-2) is only ever exercised in that
  solo flow.
- **Task-branch names must be byte-identical across clones.** Both clones must contend for the *same*
  `origin` ref, so the branch name is derived by a **canonical, deterministic function of the unit id**
  (`planwright/<spec>/task-<id>`), *not* by `claude --worktree`'s name-mangling — which the repo has been
  observed to rewrite into divergent branch names, which would create two distinct refs, two PRs, and
  defeat the fence entirely (REQ-C1.6). Dispatch renames the worktree branch to the canonical name before
  the fence push.

**Alternatives considered:**
- **Keep the fence at the local task-branch ref / PR-open push (the pre-rework design).** Rejected: the
  local ref never reaches `origin` until PR-open (post-convergence, hours after dispatch — confirmed
  against `execute-task`), so across separate clones there is *no* fence during the entire worker run;
  a claim lost in the dispatch→first-push window lets a peer dispatch a second full worker. This is the
  run-2 halt.
- **Push a bookkeeping commit to `main` at dispatch to mark the unit taken.** Rejected: this is exactly
  what `orchestration-concurrency` forbids (dispatch writes no authoritative committed state; `main`
  carries no dispatch commit). D-8 pushes a *task-branch ref*, not a commit to `main` — a ref pointing at
  the existing base commit, adding no history to `main` — so it is compatible with that floor
  (the distinction the operator drew: a ref, not a commit to `main`).
- **Rely on the machine-local claim as authoritative.** Rejected across three review rounds and both
  halts: a filesystem claim cannot be authoritative under GC / stale-break / pause races. The claim is
  demoted to a best-effort optimization (D-5); correctness moves to `origin`.
- **Optimistic dispatch, reconcile two PRs after the fact.** Rejected: two workers burn cycles and risk
  two PRs per unit; preventing the collision at dispatch beats reconciling it after.

**Chosen because:** moving the fence to an `origin` ref created at dispatch makes the no-duplicate-dispatch
guarantee both **cross-clone-live** and **death-surviving** using git's own atomic ref arbitration — no
new lock, no standing service, no commit to `main` — resolving in one mechanism the double-dispatch
window and the orphan-worker reclaim blind spot that the two halts turned on, and letting every residual
filesystem-claim race honestly degrade to wasted selection work.

### D-9: Numbered home for the framework-script security bars and the same-operator attribution model (N)

**Decision:** The framework-script security bars applied to the coordination scripts (every parsed field
grammar-validated before use; path access canonicalized and containment-checked before any read / write /
`mkdir` / `rm`; untrusted fields echo-sanitized) and the **same-operator, single-host attribution model**
(peer towers are the operator's own co-located sessions; validation guards against accident and malformed
input, not an adversarial peer forging identity) are recorded **here, as their own decision**, and
REQ-D1.4 / REQ-D1.5 / Task 5 cite **D-9** for them. Previously they cited D-6, whose decision is only the
*scope boundary* (usage-governance and the relay stay in their own bundles) — so the security posture had
no numbered decision home and lived only in un-numbered Cross-cutting prose.

**Alternatives considered:**
- **Leave the bars in Cross-cutting prose, cited as D-6.** Rejected: D-6 does not decide the security
  model, so the citation was a dangling attribution and the load-bearing trust decisions were unminuted
  (the run-2 cross-file finding). A security posture that gates three REQs deserves a decision record.
- **Fold the bars into D-2 (presence) and D-5 (claim) separately.** Rejected: the bars are one coherent
  posture spanning both surfaces and both scripts; splitting them invites drift between two half-statements
  of the same rule.

**Chosen because:** the security bars and the attribution model are a single deliberate decision (adopt
`security-posture`'s framework-script bars and scope attribution to the same-operator single-host trust
model), so they get one numbered home the REQs can honestly cite, closing the "no decision record" gap.

### D-10: Fail-closed refusals name their recovery action — "and then what" is defined per path (N)

**Decision:** Every fail-closed refusal in this bundle pairs its refusal with the **defined action the
tower takes next**, so "fail closed" is never a dead end. The per-path map:
- **`git fetch` failure during `main` sync (REQ-B1.4).** Distinguish **no `origin` configured** (a
  configuration state, detected by inspecting the remote, → the tower runs the *single-checkout solo
  flow*: no cross-clone currency to maintain, no multi-tower) from a **transient fetch failure against a
  configured `origin`** (→ fail closed: surface the failure and do **not** proceed on a silently-stale
  `main`; retry on the next cycle). The blanket "a failed fetch fails closed" is thus split so the
  no-remote solo case is not mis-treated as a transient error.
- **A `--ff-only` merge refusal (REQ-B1.4).** A non-fast-forward means unexpected divergence on a private
  `main` that should only ever fast-forward → surface for the operator; do not force, rebase, or reset
  (the never-rewrite-history floor).
- **A broken/unreadable presence or claim surface (REQ-A1.5, REQ-A1.6).** → the tower reports "unknown
  peer status" and **halts dispatch for this step** rather than taking the sole-tower path — because the
  claim surface shares the directory, an unreadable surface means the coordination layer is down, and
  dispatching blind is exactly the collision this bundle prevents. It does *not* fall back to solo
  dispatch on a *configured-multi-tower* host (that would reintroduce the race); solo dispatch is only the
  genuine no-remote single-checkout posture.
- **The absent-vs-vanished surface ambiguity (REQ-A1.5).** A **persistence sentinel** dropped at first-run
  bootstrap distinguishes "never existed" (healthy first run, proceed empty) from "existed and vanished"
  (fail closed — do not read a disappeared surface as solitude), since a bare `ENOENT` cannot tell them
  apart.
- **A concurrent first-run `mkdir` race (REQ-A1.5).** An `EEXIST` from a peer that bootstrapped the
  surface a moment earlier is **success, not an error** — the create is idempotent, order-independent.
- **A live tower's own release `rm` failure (REQ-C1.5).** Surface and retry; the discovery GC backstops
  it once the tower is positively dead — a bounded delay, never a permanent strand.

**Alternatives considered:**
- **Leave "fail closed" as the terminal statement (the pre-rework shape).** Rejected: the run-2
  error-handling lens found ~6 paths where the refusal was defined but the *next action* was not, so the
  same `ENOENT` could read as solitude on one path and break bootstrap on another, and the no-remote
  degrade contradicted a blanket fetch-fail rule. Naming the action per path removes the ambiguity.
- **One global recovery policy for all refusals.** Rejected: the correct action genuinely differs by path
  (solo-degrade for no-remote, halt-dispatch for a broken surface, idempotent-success for the bootstrap
  race), so a single policy would be wrong for most of them.

**Chosen because:** the safety value of failing closed is only realized if the tower knows what to do
next; pinning the recovery action per path turns a set of "and then what?" gaps into a defined,
testable behavior, and keeps the one genuinely-different case (no-remote solo) from being mis-handled as
an error.

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
  out of scope, not a mechanism here). This posture — the framework-script bars plus the same-operator
  attribution model — is recorded as **D-9**, which REQ-D1.4 and REQ-D1.5 cite. Because the coordination
  scripts parse records other sessions wrote, they meet planwright's **framework-script security bars**
  (REQ-D1.5): *every* parsed field consumed by the coordination logic is grammar-validated before use,
  not only the tower token — the tower id, the repository id, the unit id, the spec id, the timestamps,
  the **meta-tower marker** (it drives the defer-to-authority decision, D-4), the **checkout path**, and
  the **death handle** (whose grammar is exactly the two `fleet-death-evidence.sh` forms — `process <pid>`
  with a bounded positive integer, or `tmux-window <session> <window>` on that predicate's tmux charset —
  read from an untrusted peer record and passed to the predicate); a field that fails its grammar is
  refused, not coerced. Path access is **canonicalized and containment-checked** before any read, write,
  `mkdir`, or unlink — the surface directory itself (so a **surface-root symlink** cannot redirect
  containment outside it), each record path, the per-unit reclaim lock, the quarantine dead-letter path,
  and the claim object a reclaim removes — so a crafted unit/tower id can never drive the reclaim path's
  `rm` or a record write outside the surface. Untrusted record fields echoed to a terminal or log pass
  the echo-discipline sanitizer (`scripts/echo-safety.sh`, `sanitize_printable`). Three further surfaces
  of the trust model: the surface directory is **user-private** (`0700`, REQ-A1.4) with a pre-existing
  over-broad surface **refused, not reused** — access control is what actually enforces "same operator";
  and both a peer tower's machine-local **checkout path** *and* its **death handle** (a pid, or a tmux
  session+window name) are operational detail that must not leak from the surfaces into a committed
  artifact such as a PR body (REQ-D1.4).
