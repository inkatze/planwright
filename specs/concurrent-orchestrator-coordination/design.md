# Concurrent Orchestrator Coordination — Design

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** / **C, `<doctrine>`** —
carried: this bundle reuses an existing decision or doctrine floor from a named sibling rather than
inventing a parallel one.

## Correctness model (read this first)

The load-bearing question this bundle must answer — the one **three** kickoff halts turned on — is **what
is the authoritative guarantee that no unit is dispatched by more than one tower, is it live across
separate per-tower clones (D-3) at the moment of dispatch, and can a crashed tower's unit always be
recovered.** The answer is a **two-layer model**, stated here up front so every mechanism below is read
against it:

1. **Authoritative layer — the machine-local work-claim, keyed to the *worker's* liveness (D-5, D-7,
   D-11).** At dispatch, before any worker runs, a tower **atomically creates a unit-keyed claim object on
   the shared machine-local surface** (an exclusive create-with-content that exactly one racer wins — D-5),
   and that claim **records the dispatched worker's own reuse-resistant death handle** and **persists for
   the worker's entire run**. On the single-host co-location this bundle assumes (Scope; REQ-A1.4), that
   surface is **both cross-clone** (every co-located clone reads the same directory) **and death-surviving**
   (it is on disk, not in the tower's process), and the worker is a local process (a tmux window) whose
   liveness `fleet-death-evidence.sh` can **probe directly**. So the claim is the single authoritative
   no-duplicate-*dispatch* guarantee, and — because it tracks the *worker*, the thing actually in flight —
   it is also what makes a crashed tower's unit recoverable: reclaim removes the claim and re-dispatches
   **iff the worker is positively dead *and* no live completion artifact exists (an open PR, or commits on
   the origin ref)**; an unknown/unclassifiable liveness result is **failed closed and surfaced** for
   operator reclaim, never silently honored forever (D-7, REQ-C1.3).
2. **Hardening layer — the best-effort origin ref (D-8).** At dispatch the tower *also* pushes the unit's
   task-branch ref to `origin` by an expect-absent compare-and-swap, as a **belt-and-suspenders double-PR
   guard**: it catches the one case the machine-local claim cannot (the coordination surface wiped
   mid-flight). It is **not** the correctness floor — a mangled, absent, or lagging origin ref costs at
   most a redundant selection resolved by the authoritative claim, never a double dispatch and never a
   strand — so its garbage-collection, branch-naming, and base-commit concerns are **availability/hardening,
   not correctness**, and multi-tower coordination on one host needs **no reachable `origin`** at all.

**Why this shape, and why the earlier ones halted.** All three halts are one failure: the *authoritative*
signal was never natively **cross-clone *and* death-surviving for what it actually tracks**. Run 1's
serializer was the checkout-local advisory lock (a different path per clone — it cannot serialize peers).
Run 2's fence was the local task-branch ref (reaches `origin` only at PR-open — invisible cross-clone
during the run). Run 3 moved the fence to `origin` but left the *reaper* checkout-local **and** made a
*passive ref* authoritative — and a passive ref carries no liveness, so it cannot tell a dead worker's
zero-commit ref from a live worker's not-yet-pushed one, forcing a choice between never-reap (the run-3
strand) and reap-on-a-signal-that-must-be-cross-clone-anyway. There is **no liveness-free authoritative
floor**: any in-flight marker must eventually be reaped when the work dies, and reaping needs a liveness
signal keyed to the **worker**. This model puts *both* exclusion and the worker-liveness reaper on the one
substrate the single-host scope guarantees is cross-clone **and** death-surviving (the machine-local
surface), and keys the in-flight signal to the worker, whose liveness is directly probeable there — so no
authoritative signal is "assumed cross-clone but actually local," which is the class all three halts
belong to (D-11).

**Ledger governs *dispatchability*; the claim governs *concurrency*.** Whether a unit should be dispatched
at all is the ledger's (`tasks.md`) call — a completed, abandoned, or rejected unit is not Ready and is
never re-selected; the claim only answers "is a live worker on it right now." Keeping these separate is
what prevents a leaked or closed-PR origin ref from re-dispatching finished work (the residue is cosmetic,
not a strand), and it is why demoting the origin ref costs no correctness.

**The one load-bearing assumption:** single-host co-location (Scope; REQ-A1.4). It is what makes the
machine-local surface a complete cross-clone substrate and the worker directly probeable; cross-*host*
peer towers remain out of scope, and `origin`'s reach is not repurposed to cover them (the hardening ref
is not a cross-host floor).

The design then leads with the altitude record (D-1), the three mechanisms in impact order —
presence/awareness (D-2), the shared-`main` root fix (D-3), and the peer work-claim (D-4, D-5, its
authoritative worker-liveness model in **D-11**, its best-effort origin double-PR guard in D-8, and its
lifecycle and safe-reclaim rules in D-7) — the
fail-closed recovery actions that say what a tower *does* after each refusal (D-10), the numbered home
for the framework-script security bars and the attribution model (D-9), and the scope boundary that
keeps adjacent concerns in their own homes (D-6). Every mechanism sits above
`orchestration-concurrency`'s state-safety floor and reuses `orchestration-fleet`'s relay and meta-tower
selection rather than forking them.

**Decision-domains walk.** The feature crosses several catalogued stake-bearing domains, all decided
in-spec rather than auto-defaulted: **concurrency** (the central domain — shared coordination surfaces,
claim serialization across separate clones, crash-mid-flight reclaim; decided by a two-layer model — the
authoritative no-duplicate-dispatch guarantee is the **machine-local work-claim keyed to the worker's
liveness** (an atomic create-with-content that serializes co-located clones where the checkout-local lock
cannot, carrying the worker's reuse-resistant death handle and persisting for the worker run, D-5, D-11,
REQ-C1.1, REQ-C1.2), with the **origin ref demoted to a best-effort double-PR guard** above it (D-8,
REQ-C1.6) — plus the worker-liveness reclaim serialized by a per-unit lock with an under-lock re-read and
a completion-artifact guard (open PR / origin-ref commits) in D-7, the ledger-governs-dispatchability /
claim-governs-concurrency separation, and the presence/claim collision-semantics split); **integration
surface** (the git
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

**Decision:** This bundle is primarily three concrete mechanisms (D-2 through D-5) plus two
coordination-floor doctrine statements. The primary one: a tower **assumes multiplicity, not solitude** —
it keeps tabs on peer towers and coordinates division rather than behaving as the sole orchestrator. A
narrower **companion doctrine** rides alongside it, on the tower→human axis: a **reserved-human moment (a
merge-ready PR) reaches the operator by deterministic push, with an LLM tower polling GitHub as the
*fallback*, never the sole path** — the same "don't rely on a single fragile actor" discipline as
assume-multiplicity, applied to attention rather than coordination. Both statements extend the fleet
coordination floor (`fleet-coordination-floor.md`) and are the altitude decision this bundle records per
the autopilot-reflex altitude gate, cited from the Goal. The companion doctrine's **mechanism** (the
deterministic ready-surface hook and the attention-surface actionable reclassification) is **out of scope
here and owned elsewhere** — cross-referenced, not implemented (D-6, REQ-D1.6); only the doctrine line
lands in this bundle.

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
recorded rather than retrofitted; a **second altitude trigger** fired during the run-3 rework (a live
proof that LLM-tower-poll as the sole path to a merge-ready PR *does* fail — ready PRs going un-surfaced
because a tower did not poll in time — "hooks should push, tower-poll is the fallback"), recorded as the
companion doctrine line above; and the honest weight is **two doctrine lines** on top of three mechanisms
— the second a scoped-out-mechanism cross-reference (D-6, REQ-D1.6), so it adds a floor without adding
mechanism here — scoped per proportionality to the risk this bundle actually exhibits.

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
PID-reuse *ambiguity* (a reused pid reading as alive) makes the worker's liveness **unclassifiable** rather
than falsely reclaimable — so under the worker-keyed authoritative claim (D-11) it is **surfaced for
operator reclaim, never silently honored forever and never a double dispatch** (REQ-A1.3, REQ-C1.3, D-7).

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

**Decision:** The claim **is** the authoritative no-duplicate-dispatch guarantee (D-11), not a best-effort
optimization beneath something else. At dispatch a tower claims a unit by an **atomic, exclusive
create-with-content of a unit-keyed claim object** on the shared machine-local surface, and — the change
from the run-3 framing — that claim **records the dispatched worker's own reuse-resistant death handle**
(not only the tower's) and **persists for the worker's entire run** (it is *not* released at dispatch).
This is authoritative because the single-host co-location (Scope; REQ-A1.4) makes the surface both
cross-clone and death-surviving, and because keying the claim to the *worker* — the process actually in
flight, directly probeable by `fleet-death-evidence.sh` on the same host — is what lets a crashed tower's
unit be recovered without ever re-dispatching onto a live orphan worker (D-7, D-11). The **origin ref is
demoted to a best-effort double-PR guard (D-8)**: it is belt-and-suspenders for the surface-wiped-mid-flight
case, never the correctness floor, so its GC / naming / base concerns are availability, not correctness,
and multi-tower coordination on one host needs no reachable `origin`. (This supersedes the run-2/run-3
framing that named the origin fence authoritative — a *passive ref* carries no liveness, so it cannot tell
a dead worker's zero-commit ref from a live worker's not-yet-pushed one, which is exactly the run-3 strand;
D-11 records the inversion.) The claim object is keyed by the unit's stable id under the repository scope
(`<surface>/<repo-id>/claims/<unit-id>`); the create **is** the serializer: the first tower's create
succeeds and it owns the unit, while a losing tower's create fails atomically, whereupon it reads the
existing claim and skips the unit. Crucially the create is *both* exclusive (fails if the name exists)
*and* atomic-with-content (the claim carries the owner identity, the worker's death handle, and — for a
cohesion bundle — the full set of member unit-ids it covers, the instant it appears): a bare `mkdir` gives
exclusivity but leaves a crash window in which the claim exists empty (a tower dying between `mkdir` and
populating it would strand the unit, since an empty claim fails closed under REQ-A1.6 and cannot be
liveness-checked), while a plain temp-then-rename gives atomic content but not exclusivity (rename
overwrites, so two towers both "succeed"). The primitive that gives both is a **hardlink of a fully-written
temp** into the unit-keyed name — `link(2)` fails if the name already exists (exclusive) yet the name
resolves to complete content the instant it exists (atomic-with-content). Because the surface is
machine-local and shared by all co-located clones, this serializes peer towers **across separate per-tower
checkouts (D-3)** — precisely where the checkout-local per-spec lock cannot, because each clone's lock is a
different filesystem path. A claim is reclaimable **only** when the claiming unit's **worker** is positively
dead per `fleet-death-evidence.sh` **and** no live completion artifact exists (D-7). Unlike the initial
claim, reclaim is a read → check → swap that cannot be a single atomic filesystem step, so it is serialized
by a **per-unit reclaim lock held only across the fast swap**, with the slow death/artifact checks outside
it and an under-lock re-verification that the claim is still the same dead owner (D-7 governs the reclaim's
safety and explains why the lock-free schemes — the original in-lock ordering and the rename-aside — do not
hold).

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

### D-6: Scope boundary — usage governance, the relay, and the ready-push mechanism stay in their own bundles (N)

**Decision:** Three adjacent, tempting-to-absorb concerns are held **out of scope** with a single owner
each: (a) proactive shared-usage / quota governance (reading global `/usage`) is `fleet-autonomy`'s, which
already owns the reactive rate-limit throttle; (b) the attributed non-impersonating relay is
`orchestration-fleet`'s; and (c) the **deterministic PR-ready-push mechanism** — the hook that maps a
worker's ready-flip (`gh pr ready` / the GitHub MCP draft→ready path) to a record on the attention surface,
plus the reclassification of that surface's `pr-ready` state from non-actionable to actionable — is a **new
`merge-currency-guard` spec's**, which already owns the ready-surface interception (a stale/DIRTY-flip
guard on the *same* two surfaces, so one hook does both and the interception is not duplicated). This bundle
carries only the **companion doctrine line** that motivates that mechanism (D-1, REQ-D1.6) and
cross-references the mechanism; it implements none of the three.

**Alternatives considered:**
- Absorb usage governance here, since reading `/usage` is inherently cross-tower-aware. Rejected because:
  it is already being folded into `fleet-autonomy`, and splitting it across two bundles creates two owners
  for one mechanism — the opposite of the single-owner discipline; awareness of *peers* and awareness of
  *shared quota* are separable, and only the former is this bundle's job.
- Absorb the relay, since coordination uses it. Rejected because: it would fork audited code and the
  never-impersonate discipline; consuming it as a contract keeps one tested implementation.
- Absorb the deterministic ready-push mechanism here, since the attention surface is part of the same
  fleet-awareness infrastructure this bundle's presence signal builds on. Rejected because: it is a
  tower→human *attention* mechanism, a different axis from this bundle's tower↔tower presence / work-division
  (the axis whose scope-precision the three halts turned on — widening it mid-rework is the exact muddle to
  avoid), and its hook must **share the ready-surface interception** with `merge-currency-guard`'s proposed
  stale-flip guard, so the two belong in one place. Only the *doctrine line* is at this bundle's altitude.

**Chosen because:** each adjacent concern already has a home and an owner; this bundle stays exactly the
awareness + checkout-isolation + peer-claim layer the fold-detection identified, and the cross-references
keep the seams legible without duplicating mechanism. The ready-push split is the same discipline applied
to the newest concern: the doctrine floor lands here, the mechanism lands where the interception it shares
already lives.

### D-7: Claim lifecycle and safe reclaim — self-contained worker handle, worker-lifetime persistence, worker-liveness-guarded (N)

**Decision:** The claim object (D-5) carries the rules that keep it correct across the *worker's* whole
lifecycle, not just at the instant of the create:

- **Self-contained worker death handle.** Each claim object records the claiming tower's identity and,
  as the reclaim discriminant, the **dispatched worker's own positive-evidence-of-death handle**
  (`tmux-window <session> <window>` for the fleet norm, `process <pid>` degraded — REQ-A1.2's grammar,
  REQ-D1.5) *inside the claim itself*, independent of any presence record. This is the run-3 correction:
  reclaim keys on the **worker's** liveness, not the tower's, because the tower is a disposable/stateless
  step machine that exits normally while its worker runs for hours — keying on tower-death would GC a live
  worker's claim (the orphan-worker double-dispatch), and keying on a passive origin ref cannot tell a
  dead worker from a live-not-yet-pushed one (the run-3 strand). The worker is a local process on the same
  host, so `fleet-death-evidence.sh` probes it **directly** — no proxy. Reclaim never depends on the
  presence file still existing (presence GC, D-2, may have deleted it).
- **Worker-lifetime persistence + discovery GC.** The claim is **not released at dispatch** — releasing
  it there and handing the in-flight signal to the origin ref is exactly the run-3 orphan-worker strand.
  It **persists for the worker's whole run** and is removed on one of two terminal transitions, both keyed
  to the worker: (i) the tower removes the claim itself when it observes its **worker terminated on a
  resolved unit** (its PR merged, or the ledger marks the unit done) — the normal in-tower cleanup; and
  (ii) if dispatch **fails before the worker ever launches**, the tower removes the claim immediately,
  since no worker exists to track — a failed dispatch never leaves a claim stranding the unit. A removal
  `rm` that *fails* does not strand the unit: the tower surfaces the failure and retries, backstopped by
  the discovery GC once the worker is positively dead — a bounded delay, never a permanent block. Because
  a tower may exit before its worker finishes, path (i) is **backstopped by the discovery sweep**, which
  garbage-collects four residues, each under the **same per-unit reclaim lock and under-lock re-read as
  the reclaim path** (an unguarded GC `rm` would delete a claim a concurrent reclaimer had just swapped
  for a fresh live one, so every GC remove is a locked, identity-verified remove):
  1. **Terminated-worker claims on a resolved unit** — a claim whose **worker** is positively dead **and**
     whose unit is resolved (its PR merged / present, or the ledger marks it done) — removed even when no
     peer re-selects the unit, so a claim left by a tower that exited after its worker completed does not
     leak. (A dead worker on an *un*resolved unit — one that died before PR-open — is the *reclaim* path,
     not GC: that unit is re-dispatched, §Serialized reclaim below.)
  2. **Stale reclaim locks** — a per-unit reclaim lock left by a reclaimer that crashed mid-swap, broken
     past the stale threshold by the same `mkdir`-plus-stale-break discipline the per-spec advisory lock
     uses, so a crashed reclaimer never wedges a unit's reclaim path permanently.
  3. **Orphan temp files** — a temp file from an interrupted atomic create-with-content (the tower died
     between writing the temp and hardlinking it into the unit-keyed name), swept past a threshold so
     abandoned temps do not accumulate and poison the scan. The temp is created **inside the surface
     directory** (same filesystem as the claim name) so the hardlink is atomic and cannot hit `EXDEV`.
  4. **Aged dead-letter records** — quarantined records (below) past a TTL, so the dead-letter sub-surface
     itself does not grow unbounded (the residue the run-3 lens flagged as un-GC'd, REQ-C1.5).

  Distinct from all four: a **corrupt (unparseable) claim record** cannot be liveness-checked at all (GC
  must parse the owner + worker handle to prove death), so under the fail-closed rule (REQ-A1.6) it would
  be honored forever and strand its unit. Because the claim's atomic create-with-content (D-5) means **a
  reader never observes a transient torn or half-written claim** — a parse failure is therefore genuine
  corruption, not a mid-write artifact — the sweep **quarantines it on the first parse failure** (moves it
  to a containment-checked dead-letter sub-surface and surfaces it for the operator), rather than waiting
  for "repeated" failures across passes, which a stateless/disposable tower has no store to count (the
  run-3 Q1 finding: the counter reset every pass, so the corrupt claim never reached the threshold and was
  honored forever, an invisible permanent strand). Quarantine-on-first makes the strand
  **operator-visible-and-recoverable immediately**, without a blind delete of untrusted content (REQ-A1.6,
  REQ-C1.5). Claims thus do not outlive their coordination need, and neither the claims surface nor the
  dead-letter sub-surface grows unbounded (REQ-C1.5).
- **Serialized, worker-liveness-guarded reclaim.** Reclaim is a read → check → swap that *cannot* be
  collapsed into a single atomic filesystem step (the way the initial claim can), so it is serialized by a
  **per-unit reclaim lock held only across the fast swap**: (1) read the claim; a live or unknown **worker**
  is honored, no mutation; (2) **outside the lock**, confirm the claim's **worker is positively dead**
  (probed directly on the same host via its recorded death handle) **and** that **no live completion
  artifact exists** — where `origin` is configured, an open PR or commits on the unit's origin ref (read
  live via `ls-remote`; a *transient* origin read error fails closed → do not reclaim, retry), and where
  no `origin` is configured (no-remote mode) no such artifact can exist, so reclaim proceeds on positive
  worker-death alone (the no-remote-vs-transient split of D-10). This two-part test is the run-3 correction:
  the direct worker
  probe replaces the broken "origin-ref-exists = in flight" proxy — a passive ref cannot distinguish a dead
  worker's zero-commit ref from a live worker's not-yet-pushed one — and the completion-artifact check
  distinguishes the two ways a worker can be dead: **died before PR-open** (no artifact → the unit is
  unfinished → reclaim and re-dispatch) versus **exited after opening its PR** (artifact present → the work
  is in review or merged → do **not** reclaim; that is the terminated-worker GC path, not reclaim). (3)
  acquire the per-unit reclaim lock (a `mkdir` lock on the surface, stale-broken by the same discipline the
  per-spec advisory lock uses; a busy lock → a peer is mid-swap → skip this round); (4) **under the lock,
  re-read the claim** and proceed only if it is still exactly that dead worker's claim — else abort
  untouched — then remove it and compete for the unit by the normal create-with-content (D-5), which yields
  a single holder even against a fresh claimant; (5) release the lock. The under-lock re-read is the safety
  hinge, and the death/artifact check stays *outside* the lock so no lock is ever held across a subprocess.
- **Tri-state liveness, never a guess.** Honoring and reclaim both run on the tri-state death predicate
  (alive / positively-dead / unknown) applied to the **worker**: only a positively-dead worker permits
  reclaim; unknown or errored is treated as not-dead. This is the deliberate, *achievable* scoping of
  REQ-C1.3: a unit whose worker is **positively dead is always reclaimed** (the crash case the guarantee
  must cover), while a unit whose worker liveness is **unclassifiable** — an unknown/errored probe, or a
  degraded bare-pid handle a reused pid renders ambiguous — is **surfaced for operator reclaim, never
  silently honored forever**. A live-but-hung worker (or its tower) is *alive*, so its claim is honored and
  never auto-reclaimed; recovering that unit is an operator-intervention case. The design does not (and
  safely cannot) auto-recover an unclassifiable or live-but-hung case without risking double-dispatch — so
  it surfaces rather than guesses. (This replaces the absolute "a crashed tower never strands a unit"; the
  honest guarantee is positively-dead-always-reclaimed, unclassifiable-always-surfaced — closing the run-3
  Q2 invisibility gap.)
- **No lock across a subprocess.** The initial claim's serializer is a single atomic filesystem step
  (create-with-content), so it holds nothing. The reclaim's per-unit lock is held only across the fast
  under-lock swap (re-read + remove + compete-to-create), never across the subprocess-heavy death /
  artifact check, which runs *before* the lock is acquired — so the death predicate never sits inside a
  critical section (no livelock, no critical-section cost).
- **Best-effort locks under the authoritative claim.** The reclaim lock and the GC lock are best-effort
  serializers, not authoritative ones. A stale-break of a paused holder, or any lost lock, can let two
  towers proceed toward re-dispatch — but each ends its reclaim by **competing via the normal atomic
  create-with-content (D-5), which yields exactly one holder even against a fresh claimant**, so the
  residual lock race costs at most wasted selection work, never a double dispatch. The authoritative
  boundary is the atomic claim create itself (D-11), not the lock and not the origin ref; the lock exists
  only to make that waste rare.

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
- Reclaim on **tower**-death, or on the **origin ref's existence**, instead of the **worker's** liveness.
  Rejected because: tower-death re-dispatches whenever a dead tower's worker outlived it (the orphan-worker
  double-dispatch — the tower is a disposable step machine that exits while its worker runs); and the origin
  ref is a *passive* marker that, zero-commit until PR-open, cannot distinguish a dead worker's ref from a
  live worker's not-yet-pushed one (the run-3 strand). Keying reclaim on the **worker's** direct same-host
  liveness plus a completion-artifact check (open PR / origin-ref commits) is what resolves both.
- Release the claim at dispatch and hand the in-flight signal to the origin ref (the run-2/run-3 shape).
  Rejected because: the tower exits normally after dispatch while the worker runs, so releasing at dispatch
  GC's a *live* worker's claim — the exact orphan-worker window; the claim must persist for the worker run.
- Quarantine a corrupt claim only after *repeated* parse failures across passes. Rejected because: a
  stateless/disposable tower has no store for the per-claim count (it resets every pass/restart), so the
  threshold is never reached and the corrupt claim is honored forever (the run-3 Q1 invisible strand);
  because atomic create-with-content means no transient torn read exists, first-failure quarantine is safe.
- Auto-reclaim a hung-but-alive worker after a timeout. Rejected because: it violates the
  positive-evidence-of-death floor and races the still-live worker into double-dispatch; stranding on a
  genuine hang is the safer failure, surfaced for operator intervention.

**Chosen because:** the claim's correctness lives across the **worker's** lifetime, not just at the create;
folding the worker death handle, the persist-until-worker-terminates lifetime, the serialized
worker-liveness-guarded reclaim, quarantine-on-first, and the tri-state liveness into one decision keeps
D-5 focused on the serialization primitive while D-7 carries the safety envelope the run-3 backlog
(H1–H3, A1, Q1, Q2) and the earlier §8 findings demanded.

### D-8: The origin ref is a best-effort double-PR guard, not the authoritative fence (N)

**Decision:** At dispatch, in addition to the authoritative machine-local claim (D-5, D-11), a tower
pushes the unit's task-branch ref to `origin` by an *expect-absent* compare-and-swap
(`git push --force-with-lease=refs/heads/<branch>: <base-sha>:refs/heads/<branch>` — with the explicit
all-zeros OID as the "must be absent" expectation, hardened against any git build that treats the bare
empty form as unchecked, the run-3 U1 note), pushing the branch's **current local tip** (whatever base the
worktree was created from, so an *adopted* worker-tip is fenced at its own base and does not later
non-fast-forward, the run-3 S4 note). `origin` serializes concurrent creators to one winner. This is a
**best-effort double-PR guard**, not the correctness floor: it catches the one case the machine-local claim
cannot — the coordination surface wiped or unavailable mid-flight — so two towers that both lost their
claims still cannot both open a PR. It is **not** relied on for correctness (D-11): a mangled, absent,
lagging, or never-reaped origin ref costs at most a redundant selection resolved by the authoritative
claim, never a double dispatch and never a strand.

Its former "authoritative fence" role is **withdrawn** (D-11 records why): a passive ref carries no
liveness, so making it authoritative forced the run-3 dilemma — never-reap (strand) or reap-on-a-signal
that must be cross-clone anyway. Because it is now hardening, its previously-load-bearing concerns become
**availability, not correctness**, and are handled best-effort:
- **Branch naming across backends (run-3 S1, S5).** The guard is most effective when both clones push the
  *same* canonical ref name (`planwright/<spec>/task-<id>`). The two shipped dispatch backends reach that
  name differently: `fleet-dispatch-worktree.sh` creates the canonical branch **directly** (`git worktree
  add -b`, no post-launch rename), while the `claude --worktree` / tmux backend mangles slashed names and
  needs a **rename to canonical before the guard push**. Dispatch normalizes to the canonical name per
  backend and, where it renames, **verifies the pushed refname equals canonical or drops the guard for this
  unit** (fail *the guard*, not the dispatch — the claim is authoritative). A divergent ref merely weakens
  the belt-and-suspenders; it never breaks correctness.
- **Sequencing (run-3 S2).** The guard push is placed **before worker launch** in both backends; the
  authoritative claim already gates launch, so this is a hardening ordering, not a correctness gate.
- **No reachable `origin` (run-3 A3).** Multi-tower on one host needs **no** remote for correctness (the
  claim is the floor), so the guard simply **degrades to absent** when `origin` is unreachable — it is not
  attempted and nothing fails closed on its account. This is the A3 fix: no-remote multi-tower no longer
  fails open, because the authoritative layer never depended on `origin`.

The guard establishes no committed state on `main` (a task-branch ref at an existing commit, no history
added), so it remains compatible with `orchestration-concurrency`'s no-dispatch-commit-on-`main` floor.

**Alternatives considered:**
- **Keep the origin ref authoritative (the run-2/run-3 design).** Rejected — this *is* the run-3 halt: a
  passive ref pushed at dispatch is zero-commit until PR-open, so it cannot distinguish a dead worker's ref
  from a live worker's not-yet-pushed one; making it authoritative forces either never-reap (permanent
  strand) or a cross-clone reaper needing a worker-liveness signal the ref itself cannot carry. D-11 moves
  authority to the worker-keyed machine-local claim, which *does* carry that signal.
- **Drop the origin ref entirely.** Rejected: it is cheap and it is the only backstop for the
  coordination-surface-wiped-mid-flight case; keeping it demoted costs nothing in correctness (all its
  imperfections are now availability-only) and adds a real safety margin.
- **Push a bookkeeping commit to `main` at dispatch.** Rejected: `orchestration-concurrency` forbids it;
  the guard pushes a task-branch *ref*, not a commit to `main`.

**Chosen because:** the origin ref is genuinely useful as a second line of defense but a *terrible*
authoritative floor (a passive, liveness-free, zero-commit-until-PR-open marker); demoting it to a
best-effort guard keeps its value, dissolves the run-3 reaper / naming / no-remote findings (H1–H3, S1–S5,
A3) as correctness issues, and puts the authoritative guarantee on the substrate that can actually carry
worker liveness (D-11).

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
- **A tower's own claim-removal `rm` failure (REQ-C1.5).** Surface and retry; the discovery GC backstops
  it once the *worker* is positively dead — a bounded delay, never a permanent strand.
- **A reclaim completion-artifact check against `origin` (REQ-C1.3).** Split like the `fetch` case: **no
  `origin` configured** (no-remote mode) → no completion artifact can exist, so reclaim proceeds on positive
  worker-death alone (a no-remote unit is never stranded); a **transient `origin` read error** against a
  *configured* `origin` → **fail closed** (treat the unit as possibly-in-review, do not reclaim, retry next
  pass), never fail-open into re-dispatching an in-review unit.

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

### D-11: The authoritative in-flight signal is the worker-keyed machine-local claim; `origin` is demoted (N)

**Decision:** The authoritative no-duplicate-dispatch-and-no-strand guarantee is the **machine-local
work-claim, keyed to the dispatched *worker's* liveness** (D-5, D-7). The origin ref (D-8) is demoted to a
best-effort double-PR guard. This inverts the run-2/run-3 decision that named the `origin` ref
authoritative, and it is the load-bearing decision of the run-3 rework — recorded as its own D-ID so the
kickoff has a single anchor for the inversion and the reasoning that closes the halt class.

**The diagnosis it rests on.** Three kickoffs halted on one shape: the *authoritative* signal was never
natively **cross-clone *and* death-surviving for what it actually tracks.** Run 1's serializer (the
advisory lock) was checkout-local. Run 2's fence (the local task-branch ref) reached `origin` only at
PR-open. Run 3's fence (the origin ref) was cross-clone and death-surviving, but is a **passive ref** that
tracks nothing about liveness — it is zero-commit for the whole worker run, so it cannot tell a dead
worker's ref from a live worker's not-yet-pushed one, and its reaper (`orchestration-concurrency`'s
zero-commit-branch stale-break) is itself checkout-local. The general truth under all three: **there is no
liveness-free authoritative floor.** Any in-flight marker must eventually be reaped when the work dies, and
reaping requires a liveness signal — keyed to the **worker**, the thing actually in flight, not the
disposable tower that dispatched it and exits, and not a passive ref.

**Why the worker-keyed claim satisfies it (where the others could not).** The load-bearing scope
assumption is **single-host co-location** (Scope; REQ-A1.4). On one host: (a) the machine-local surface is
read by every co-located clone, so it is **cross-clone**; (b) it is on disk, not in a tower's process, so
it is **death-surviving**; (c) the dispatched worker is a local process (a tmux window), so
`fleet-death-evidence.sh` can **probe its liveness directly** — no proxy. So a claim written to that
surface, keyed to the worker's death handle and persisting for the worker run, is simultaneously the atomic
cross-clone *exclusion* primitive (the create-with-content serializes co-located clones, D-5) and the
*recovery* signal (reclaim on positively-dead worker + no completion artifact, D-7). Both jobs land on the
one substrate that is cross-clone and death-surviving for the scope, and the signal tracks the worker — so
**no authoritative signal is "assumed cross-clone but actually local,"** which is precisely the class the
three halts belong to. `origin`'s reach was only ever needed for the *cross-host* case, which is explicitly
out of scope; repurposing a passive ref to stand in for worker-liveness is what generated the run-3 defect.

**Consequences (which this rework instantiates).** The double-dispatch guarantee (REQ-C1.1) and the
crashed-worker recovery guarantee (REQ-C1.3, tightened to positively-dead-reclaimed / unclassifiable-
surfaced) both rest on the claim; the ledger governs *dispatchability* while the claim governs
*concurrency* (so a leaked/closed-PR origin ref cannot re-dispatch finished work); no-remote multi-tower on
one host is safe (A3); cohesion-bundle members are covered by the one claim listing all member unit-ids
(A2); and the lost-CAS-ACK live-tower strand disappears, because the authoritative write is a local atomic
create with no network-ACK ambiguity (A1).

**Alternatives considered:**
- **Keep `origin` authoritative and add a cross-clone worker-liveness reaper (Architecture B).** Rejected:
  it needs *everything this decision needs* — the machine-local worker-liveness record, because `origin`
  cannot answer worker-liveness — **plus** a fully-hardened origin fence on top (owner-encoding for A1,
  bundle fencing for A2, no-remote enforcement for A3, reaper + terminal self-cleanup for H1–H3, backend
  naming/sequencing for S1–S5), each finding closed individually. It is strictly more mechanism, and every
  origin-mechanics finding stays live. This decision is Architecture B minus the parts that keep generating
  halts.
- **Rely on the machine-local claim as authoritative — as previously rejected "across three review rounds
  and both halts."** That rejection reasoned about a claim keyed to *tower* liveness and *released at
  dispatch*, which genuinely is not authoritative for the worker run (a normally-exiting tower GC's a live
  worker's claim). Keying to the **worker** and **persisting for the worker run** is a materially different
  object; the earlier objection does not reach it.

**Chosen because:** it stops fighting `origin`'s passivity and puts both exclusion and the worker-liveness
reaper on the substrate the single-host scope guarantees is cross-clone and death-surviving, keyed to the
worker — closing the whole locality class the three halts share rather than patching the newest instance.

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
