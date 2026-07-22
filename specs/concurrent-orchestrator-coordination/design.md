# Concurrent Orchestrator Coordination — Design

**Status:** Ready
**Last reviewed:** 2026-07-21
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** / **C, `<doctrine>`** —
carried: this bundle reuses an existing decision or doctrine floor from a named sibling rather than
inventing a parallel one.

## Correctness model (read this first)

The load-bearing question this bundle must answer — the one **four** kickoff halts turned on — is **what is
the authoritative guarantee that no unit is dispatched by more than one tower, and is it live across
separate per-tower clones (D-3) at the moment of dispatch.** The answer, after run 4 re-opened it honestly,
is **one correctness floor plus a bounded-or-surfaced residue model** (Architecture B), stated here up front
so every mechanism below is read against it:

1. **The one correctness floor — a per-unit fence ref on `origin`, created at dispatch (D-5, D-8, D-11).**
   Before any worker runs, a tower fences the unit by an **atomic expect-absent compare-and-swap** creating
   `refs/planwright-fence/<spec>/<unit-id>` on `origin` (the all-zeros OID as the must-be-absent
   expectation). `origin` is the one substrate every co-located clone already shares, and git serializes ref
   updates on it, so exactly one tower wins the fence per unit; a loser's push is rejected and it selects
   another unit. `origin` is **natively both cross-clone and death-surviving** — the ref persists after the
   creating tower dies, and every clone reads the same ref set — so **nothing has to fake that locality**.
   The fence is keyed by **unit id** and created by the **tower before the worker forks**: it references no
   worker identity, so it has no pre-fork-pid lifecycle problem and no worker death handle to parse.
2. **The residue model — bounded-and-swept or durably-surfaced, never silent (D-13).** No exclusion floor
   over an open-ended partial-failure substrate can promise an absolute; what it *can* promise is that every
   residue it cannot exclude is either **swept** (a terminal unit's fence is GC'd, REQ-C1.5) or **durably
   surfaced to the operator** through a dedup'd sink (a dead-owner strand, an unknown-owner orphan, an
   unclassifiable-liveness or version-skewed record — REQ-C1.3, REQ-C1.7), and **never silently honored
   forever or silently dropped**. Reclaim of a dead-owner strand is a **reserved operator decision**, not an
   automatic probe: the common tower-turnover case is graceful self-refresh that never strands, so the rare
   hard-crash strand is surfaced rather than auto-recovered on a guess.

**Correctness depends only on the fence; the presence surface is off the correctness path.** No-duplicate-
dispatch is delivered entirely by the `origin` CAS (self-sufficient). The machine-local presence surface
(D-2, REQ-A) is used only to **attribute** an orphan fence to a dead owner so a strand can be surfaced; if
presence is missing, unreadable, or version-skewed, the fallback is to surface the orphan as unknown-owner —
safe, never a double dispatch. This split is what makes the run-4 version/schema-skew safety bug
**impossible here**: a git ref has no record schema to skew, and the only schema-bearing records (presence)
cannot free a fenced unit.

**Why this shape, and why the earlier ones halted (the multi-axis diagnosis).** Correctness of this
primitive is **multi-axis** — {locality, worker-lifecycle, keying/granularity, the death-state machine,
version/schema skew, a defined recovery action per fail-closed path, a durable sink per residue} — and each
of the first three kickoff runs validated only the **locality** axis that bit it last: run 1's serializer
was the checkout-local advisory lock (a different path per clone); run 2's fence was the local task-branch
ref (reaches `origin` only at PR-open); run 3 moved authority to a machine-local worker-keyed claim to get
locality *and* a death-surviving reaper on one substrate. Run 3 got locality right — and run 4's full-bundle
lens then found holes on the axes it never checked (a claim needs a pre-fork pid; a unit-keyed claim cannot
fence a cohesion bundle; a commits-no-PR worker is neither reclaimed nor GC'd nor surfaced; a version-skewed
claim is quarantined and its unit double-dispatched; a reused pid reads confidently alive). The lesson
(D-12): stop hunting the next interleaving and instead **enumerate the axes once and answer every cell** — a
finite, checkable contract. Architecture B answers them by *removing* rather than hardening: the fence is a
git ref, so worker-lifecycle and version/schema skew **dissolve** (no worker handle, no record schema on the
correctness path); it is keyed per unit and cohesion-bundle members are fenced together atomically, so
keying is answered by construction; the death-state machine collapses to {proceed, honor, surface, GC}; and
reclaim being the operator's removes the per-unit reclaim lock, under-lock re-read, four-residue GC, and
quarantine that were Architecture A's seam surface. The coverage matrix below is the audit of every cell.

**Ledger governs *dispatchability*; the fence governs *concurrency*.** Whether a unit should be dispatched
at all is the ledger's (`tasks.md`) call — a completed, abandoned, or rejected unit is not Ready and is
never re-selected; the fence only answers "has a tower already taken this unit right now." Keeping these
separate is what makes a leaked fence on a finished unit a **GC case, not a strand** (REQ-C1.5).

**The one load-bearing assumption:** single-host co-location (Scope; REQ-A1.4) — but now it bounds only
**strand attribution and the sink**, not correctness. The `origin` fence itself would work across machines;
what stays single-host is the presence surface and the death-evidence predicate (PIDs / tmux) used to
*attribute* an orphan fence to a dead owner. Cross-*host* peer towers remain out of scope.

The design then leads with the altitude record (D-1), the coverage matrix, the three mechanisms in impact
order — presence/awareness (D-2), the shared-`main` root fix (D-3), and the peer fence (D-4, its exclusion
primitive in **D-5**, its authority on `origin` in **D-8** and **D-11**, and its lifecycle and strand
surfacing in **D-7**) — the fail-closed recovery actions that say what a tower *does* after each refusal
(D-10), the numbered home for the framework-script security bars and the attribution model (D-9), the scope
boundary that keeps adjacent concerns in their own homes (D-6), and the two structural decisions that make
this rework different in kind from the prior four — the axis-matrix coverage contract (D-12) and the
guarantee downgrade (D-13). Every mechanism sits above `orchestration-concurrency`'s state-safety floor and
reuses `orchestration-fleet`'s relay and meta-tower selection rather than forking them.

## Failure-axis coverage matrix

The anti-recurrence contract of **D-12**: every failure axis of the dispatch-exclusion primitive is
enumerated once, and the spec answers **every cell**. A kickoff lens verifies **cell-completeness** rather
than hunting the next interleaving. Two cells **dissolve** under Architecture B because the correctness floor
is a git ref rather than a parsed machine-local record.

| Axis | Architecture-B answer | Covered by |
| --- | --- | --- |
| **Locality** | The floor is a per-unit ref on `origin`; git serializes its expect-absent CAS cross-clone, and the ref survives the creating tower's death — no machine-local surface fakes locality. | REQ-C1.1 · D-8 · D-11 |
| **Worker-lifecycle** | *Dissolved.* The fence is keyed by unit id and created by the tower **before** the worker forks; it carries no worker identity or death handle, so there is no pre-fork-pid problem. | REQ-C1.1 · REQ-C1.2 · D-5 |
| **Keying / granularity** | One fence ref per member unit-id; a cohesion bundle is fenced with `git push --atomic` over all members, so any member a peer selects collides and no non-lead member is left unfenced. | REQ-C1.2 |
| **Death-state machine** | Small and enumerable (classified **terminal-first, then liveness**): died-before-push → no residue; unit-**terminal** (**merged** PR / ledger-done) → GC the fence regardless of owner liveness; else owner-live → honor (regardless of any *non-merged* downstream artifact); owner-dead + **not-terminal** (no artifact, commits-no-PR, **or** an open-unmerged PR — none of which a live tower will carry to merge) → surface; owner-unclassifiable / unknown-owner orphan → surface (after a one-pass grace re-check for the orphan case). No auto-reclaim. | REQ-C1.3 · REQ-C1.5 |
| **Version / schema skew** | *Dissolved.* The correctness floor is git-ref existence (no schema). A version-skewed presence record is awareness-only (assume-live, surface), never on the correctness path, so it can never free a fenced unit. | REQ-A1.6 · REQ-C1.1 |
| **Recovery action per fail-closed path** | Pinned per path in D-10: no-`origin` → solo dispatch; rejected CAS → back off unit; transient `origin` → fail closed + retry; orphan fence → surface; terminal fence → GC; broken presence surface → **surface unknown-peer-status, degrade awareness, dispatch proceeds** (the fence, not the surface, is the floor). | REQ-C1.6 · D-10 |
| **Durable sink per residue** | Every strand and unclassifiable anomaly lands in a durable, dedup'd, operator-facing sink delivered by push (attention path), keyed for dedup and named with a defined operator action. | REQ-C1.7 |

## Decision-domains walk

The feature crosses several catalogued stake-bearing domains, all decided in-spec rather than
auto-defaulted: **concurrency** (the central domain — shared coordination surfaces, dispatch exclusion
across separate clones, crash-mid-flight residue; decided by one correctness floor plus a bounded-or-surfaced
residue model — the authoritative no-duplicate-dispatch guarantee is the **per-unit `origin` fence ref**
created at dispatch by an atomic expect-absent CAS (D-5, D-8, D-11, REQ-C1.1, REQ-C1.2), with the
**machine-local presence surface off the correctness path** and used only to attribute orphan fences; a
dead-owner strand is **surfaced to the operator, not auto-reclaimed** (D-7, REQ-C1.3, REQ-C1.7); the
ledger-governs-dispatchability / fence-governs-concurrency separation holds); **integration surface** (the
git checkout / `origin` coordination topology and the hardened `main`-currency sync — decided in D-3, with
`origin` reachability now the fence's precondition, classified per D-10); **authentication / attribution**
(tower identity on the presence surface and the strand sink — decided by carrying
`inter-orchestrator-coordination`'s relay security bounds scoped to the same-operator single-host trust
model, enforced at the surface by user-private permissions and at the script boundary by the
framework-script security bars, REQ-D1.4, REQ-D1.5, REQ-A1.4); and **observability** (a broken presence
surface must not read as solitude, a corrupt record must not read as absence, and every residue must be
durably surfaced — decided by the fail-closed discovery and per-record fail-closed requirements REQ-A1.5,
REQ-A1.6, the defined recovery action per fail-closed path in D-10, and the durable dedup'd sink REQ-C1.7).
Secrets/config is conditional (documented in the options reference only if the surface path becomes
configurable). No other catalogued domain is touched-but-undecided.

## Decision log

### D-1: Deliverable altitude — mechanism-primary with two coordination-floor doctrine statements (N)

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
The machine-local surface holds two derived
sub-surfaces, both awareness-only and off the correctness path (D-5, D-11): **presence** is
distinct-per-writer — one file per tower, keyed by tower identity, which must never collide — and the
**durable strand sink** (REQ-C1.7) is dedup'd by anomaly key. The dispatch-exclusion object is **not** here:
it is the per-unit fence ref on `origin` (D-8), so the machine-local surface never carries a
correctness-bearing record. The surface directory is **user-private** (`0700`): that access control is what enforces the same-operator single-host trust
model (REQ-A1.4, REQ-D1.4). The surface directory is created with an atomic, mode-explicit `mkdir` and,
because the `0700` bit is *the* trust enforcement, a pre-existing surface directory whose mode is
**over-broad** (group/other-accessible) is **refused, not silently reused** — verify-or-refuse, so an
attacker-planted or mis-permissioned surface can never quietly widen the trust boundary (REQ-A1.4).

Each tower writes and heartbeat-refreshes its own record **atomically** (write-temp-then-rename, so a
reader never sees a torn record), keyed by a **tower identity** and carrying that identity, the repo id,
the checkout path, spec(s) advanced, the **unit-ids it currently holds an `origin` fence for** (the
strand-attribution field: a peer maps an orphan fence ref back to its owner through this list, and a fence
no live record lists is an unknown-owner orphan — REQ-C1.3, D-7), start time, last-beat, a
positive-evidence-of-death handle, and a **meta-tower marker that is the presence record's own field** (a
validated boolean the tower stamps from
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
PID-reuse *ambiguity* (a reused pid reading as alive) makes a fence owner's liveness **unclassifiable** rather
than falsely reclaimable — so under the origin-fence floor (D-11), where presence is off the correctness
path, it is **surfaced as a strand anomaly, never silently honored forever and never a double dispatch**
(REQ-A1.3, REQ-C1.3, REQ-C1.7).

A tower discovers peers by scanning that directory, excluding its own record, and applying the
positive-evidence-of-death liveness predicate — which is tri-state (alive / positively-dead / unknown),
and only *positively-dead* permits reclaim (an unknown or errored result is treated as not-dead; a stale
heartbeat alone never proves death). To bound the per-record subprocess cost (the death predicate is a
subprocess per record), discovery **caches each peer's liveness verdict for the pass** and runs on a
capped heartbeat cadence rather than fanning out unboundedly per record per beat (REQ-A1.1). No tower
ever edits another *live* tower's file content, and there is no single registry file that all towers
mutate; a discovering tower may garbage-collect a positively-dead tower's entire file, but only under a
re-read that **re-confirms the record is still that same positively-dead tower's** immediately before the
unlink (unlike an unguarded `rm`), so a
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
PRs) and the presence surface (and durable strand sink) rather than through a shared local `main`. Today's mitigation
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

### D-4: Reuse the meta-tower selection and the attributed relay; the peer fence is additive (C, `orchestration-fleet D-7`)

**Decision:** Coordination reuses `orchestration-fleet`'s two shipped coordination surfaces unchanged —
the meta-tower's cross-spec selection under the fleet bound, and the attributed, non-impersonating
buffer-paste relay — and adds **only** the missing piece: a peer fence for the case where towers are
started independently with no meta-tower assigning disjoint slices. The fence mechanism composes with the
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
gap for the peer case is *fencing a unit before dispatch*, so the honest design is an additive fence
layer, not a parallel coordination stack.

### D-5: The exclusion primitive — an atomic expect-absent CAS creating a per-unit fence ref on `origin` at dispatch (N)

**Decision:** The exclusion primitive **is** the authoritative no-duplicate-dispatch guarantee (D-11), and
it is a **per-unit fence ref on `origin`**, not a machine-local object. At dispatch, before any worker
runs, a tower creates `refs/planwright-fence/<spec>/<unit-id>` by an **atomic expect-absent
compare-and-swap** (`git push --force-with-lease=refs/planwright-fence/<spec>/<unit-id>:$ZERO_OID origin
<origin/main-tip>:refs/planwright-fence/<spec>/<unit-id>` — the `--force-with-lease` names the fence ref and
its must-be-absent expectation `$ZERO_OID` (**the object-format's all-zeros object id**, 40 hex zeros under
SHA-1 / 64 under SHA-256, **never the bare-empty `<ref>:` nothing-after-the-colon form** some git builds
treat as unchecked), while the trailing `origin <origin/main-tip>:refs/planwright-fence/<spec>/<unit-id>` is
the refspec actually pushed — creating the fence ref at the current `origin/main` tip, an existing commit, so no
history is added to `main`). The push **is** the serializer: `origin` serializes ref updates, so the first
tower's create-ref succeeds and it owns the unit, while a losing tower's push is **rejected**, whereupon it
selects another unit. This is authoritative because `origin` is **natively both cross-clone** (every
co-located clone — indeed every clone anywhere — reads and writes the same ref set) **and death-surviving**
(the ref is on the server, not in the creating tower's process, so it persists when that tower dies) — the
two properties the four prior kickoff runs each failed to get from a single substrate without *faking* one
of them (D-11, D-12). The fence is keyed by **unit id** and created by the **tower before the worker forks**,
so it references **no worker identity and no death handle**: there is no pre-fork-pid problem (the run-4
worker-lifecycle hole) and no claim record whose schema a version-skewed peer could corrupt (the run-4
version-skew hole) — both axes **dissolve** because the correctness object is a git ref, which either
exists or does not.

A fence is a **dedicated-namespace** ref (`refs/planwright-fence/<spec>/<unit-id>`), deliberately **not**
the unit's task-branch ref: keying the fence to the unit id under its own namespace lets the fence exist
before the worker's task branch does, be garbage-collected independent of that branch (D-7, REQ-C1.5), and
be pushed by the tower under the canonical name **directly** — so no dispatch backend's branch-naming
behavior is anywhere in the fencing path. That removes the run-4 phantom entirely: the earlier draft modeled
"two dispatch backends, one that mangles slashed names and `git branch -m` renames to canonical," but only
`fleet-dispatch-worktree.sh` ships and it direct-creates the canonical branch; the mangle is the native
`claude --worktree` behavior that primitive was built to eliminate, and `git branch -m` appears nowhere. A
dedicated fence ref the tower pushes by canonical name sidesteps the whole rename/verify burden by
construction. For a **cohesion bundle**, the tower fences **every member unit-id** in a single
`git push --atomic`: if any member is already fenced, the whole push is rejected atomically and the tower
backs off the entire bundle, so no non-lead member is ever left unfenced (the run-4 cohesion-keying hole,
closed by construction — REQ-C1.2).

Where `origin` is unreachable, the fence cannot be created, and that condition is **classified, never
failed open** (D-10, REQ-C1.6): no-`origin`-configured is the genuine no-remote single-host solo posture
(no peers, dispatch without a fence); a transient error fails closed and retries; a rejected CAS is a
back-off. Reclaim of a dead-owner fence is **not** part of this primitive: it is the operator's, surfaced
per D-7, so D-5 owns only the create-and-exclude half and carries **none** of Architecture A's reclaim
machinery.

**Alternatives considered:**
- **A machine-local atomic create-with-content claim keyed to the worker's liveness** (the run-3/run-4
  Architecture A). Rejected because: to be authoritative it must be *both* cross-clone and death-surviving,
  which a machine-local surface only achieves by leaning on the single-host assumption to *fake* the
  locality `origin` has natively — and run 4 showed that even granting the locality, the claim still strands
  on worker-lifecycle (a claim needs a pre-fork pid), cohesion-bundle keying, permanent-`origin`-error, and
  pid-reuse, while paying heavy standing complexity (worker-handle provenance, a per-unit reclaim lock,
  under-lock re-reads, four-residue GC, version quarantine) that is itself the surface area the next seam
  hides in. The `origin` ref pays none of that and dissolves two of those axes outright.
- **Keep the origin ref best-effort and the claim authoritative** (invert of this decision). Rejected
  because: that is the run-4 design; the lens showed the claim does not deliver the "always reclaimed"
  guarantee it was chosen for, so the complexity buys nothing correctness cannot get more simply from the
  ref (D-11 records the inversion).
- **Use the unit's task-branch ref as the fence** (the run-2/run-3 origin-fence variant). Rejected
  because: it requires the worker's branch to exist and be byte-identical across clones (the run-4 fence
  finding), drags dispatch-backend branch-naming into the fencing path (the phantom), and conflates the
  work branch with the claim; a dedicated `refs/planwright-fence/` namespace keyed by unit id is keyable
  and GC-able without any of that.
- **Optimistic dispatch, then detect-and-resolve** (let two branches exist, then reconcile). Rejected
  because: two towers launch two workers on one unit, burning cycles and risking two PRs; the operator's
  framing is that peer towers already race, so preventing the collision at dispatch beats reconciling it
  after.

**Chosen because:** the `origin` expect-absent CAS is a genuine cross-clone serializer on the one substrate
every clone already shares, is death-surviving by construction, and — keyed per unit id under a dedicated
namespace, created before the worker forks — dissolves the worker-lifecycle, version-skew, cohesion-keying,
and backend-rename axes that Architecture A had to spend mechanism on, leaving reclaim as the only residue,
handled by surfacing (D-7) rather than by a standing lock-and-GC apparatus.

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
  (the axis whose scope-precision the prior kickoff halts turned on — widening it mid-rework is the exact
  muddle to avoid), and its hook must **share the ready-surface interception** with `merge-currency-guard`'s proposed
  stale-flip guard, so the two belong in one place. Only the *doctrine line* is at this bundle's altitude.

**Chosen because:** each adjacent concern already has a home and an owner; this bundle stays exactly the
awareness + checkout-isolation + peer-claim layer the fold-detection identified, and the cross-references
keep the seams legible without duplicating mechanism. The ready-push split is the same discipline applied
to the newest concern: the doctrine floor lands here, the mechanism lands where the interception it shares
already lives.

### D-7: Fence lifecycle and strand handling — GC on terminal, orphans surfaced not reclaimed, durable dedup'd sink (N)

**Decision:** The fence ref (D-5) carries the rules that keep it correct and bounded across the unit's whole
lifecycle, and — the load-bearing shift from Architecture A — **reclaim of a dead-owner unit is the
operator's, not the tower's**, so the standing reclaim apparatus is absent:

- **Persist until terminal; GC on terminal.** A fence persists from dispatch until its unit reaches a
  terminal state (its **PR merged**, or the ledger marks it done — an **open, unmerged PR is not terminal**,
  so the fence persists across the whole open-PR window), then the fence ref is deleted from
  `origin`. GC runs both on the owning tower's own completion path (the normal cleanup) and on the discovery
  sweep (the backstop for a tower that exited before its unit finished), and is **idempotent** — deleting an
  already-absent ref is success, so two towers GC'ing the same terminal fence never error and never race
  destructively (a ref delete has no torn-read window a machine-local `rm` would). A GC that fails on a
  transient `origin` error is surfaced and retried next pass. This is the only sweep the design needs: the
  fence namespace on `origin` is bounded because every fence is deleted when its unit turns terminal
  (REQ-C1.5) — closing the run-4 no-origin-ref-GC gap with **no** machine-local residue GC at all.
- **Strand detection is attribution, not a correctness read.** Classification is **terminal-first**: a
  terminal unit (merged PR / ledger-done) is GC'd regardless of owner liveness (bullet above); otherwise a
  fence whose owning tower is still **live** is honored (the unit is in flight, while non-terminal). A fence
  becomes a **strand candidate** only when its owner is
  **positively dead** — the presence surface's `fleet-death-evidence` verdict on the owner's recorded death
  handle (REQ-A1.2, REQ-A1.3) — **and** the unit is **not terminal** (no merged PR, not ledger-done; read
  live — refs via `ls-remote`, PR merge state via `gh`; a transient `origin` read fails closed). A dead
  owner's **non-merged** downstream artifact — commits, or an **open, unmerged PR** — does **not** suppress
  the strand (no live tower will carry it to merge), so it is surfaced, not silently honored (D-13). The presence
  read here is **attribution only**: it maps an orphan fence to a (dead) owner so the strand can be named. If
  presence is missing, unreadable, or version-skewed, the fence is surfaced as an **unknown-owner orphan** —
  the fallback is safe because presence is never on the correctness path (D-5, D-11); no presence failure can
  free a fenced unit.
- **Surface, never auto-reclaim.** On a strand candidate — and on every case the tower cannot classify: an
  unknown/errored owner-liveness probe, an unknown-owner orphan, or a reused-pid ambiguity on a degraded
  bare-`process <pid>` owner handle — the tower **surfaces the strand to the durable operator sink and does
  not act**. Reclaiming a dead owner's in-flight unit is a **reserved operator decision** (Scope; REQ-C1.3),
  because the common tower-turnover case is graceful self-refresh that never strands, so the rarer hard-crash
  strand does not justify an automatic probe-and-reclaim that would risk double-dispatch on a
  misclassification. The honest guarantee is therefore **surfaced, not reclaimed**: a dead-owner unit that is
  **not terminal** is always surfaced (bounded delay) — including one carrying only commits or an open,
  unmerged PR — a terminal (merged / ledger-done) unit's fence is always swept, and no strand is ever silently
  honored forever (D-13, REQ-C1.3). Because reclaim is the operator's, there is **no
  per-unit reclaim lock, no under-lock re-read, no completion-artifact-guarded auto-swap, no four-residue
  machine-local GC, and no version-quarantine** — the entire Architecture-A safety apparatus is unneeded, and
  with it goes the seam surface run 4 found holes in.
- **The durable, dedup'd sink.** "Surfaced" means a durable, deduplicated, operator-facing entry, delivered
  by **push** through `orchestration-fleet`'s attention surface (surface-by-push per the autopilot-reflex
  forcing-function discipline, never poll-only, never a transient log line — REQ-C1.7). The dedup key is the
  fence-ref name plus owner identity for a strand, the record identity for an awareness anomaly, so the same
  anomaly re-observed each discovery pass is raised once. Each entry names the unit, the dead-or-unknown
  owner, and a defined operator action (reclaim / investigate / dismiss). The sink carries no checkout path
  or death handle into any committed artifact (REQ-D1.4), and is bounded because entries are operator-resolved
  or swept when their unit turns terminal. This is the durable-sink axis the run-4 lens flagged as missing.

**Alternatives considered:**
- **Auto-reclaim a dead owner's unit by probing the worker directly** (Architecture A's D-7). Rejected
  because: it requires a worker death handle knowable only *after* the worker forks (the run-4 lifecycle
  hole), it still strands the unclassifiable case (an unknown probe, a reused pid), and the common
  tower-turnover case is graceful self-refresh that never strands — so the auto-recovery it buys is for a
  rare hard-crash case, at the cost of a standing reclaim-lock / under-lock-re-read / four-residue-GC /
  quarantine apparatus that is itself where the next seam hides. Surfacing is simpler and honest under the
  downgraded guarantee (D-13).
- **Never GC a fence ref** (leave them on `origin`). Rejected because: the fence namespace grows unbounded
  across the repo's whole history (the run-4 H3 no-GC finding); GC-on-terminal with an idempotent delete
  bounds it.
- **Surface strands to a transient log line.** Rejected because: without a durable dedup'd sink, a strand is
  either lost (a log line nobody reads) or re-raised every discovery pass (noise) — the run-4 no-durable-sink
  gap; the dedup'd attention-surface entry is durable and raised once.

**Chosen because:** keying the fence by unit id created before the worker forks dissolves the lifecycle and
keying axes; GC-on-terminal with an idempotent `origin` ref delete bounds the one real residue surface; and
making reclaim the operator's — surfaced through a durable dedup'd sink rather than auto-probed — delivers
the downgraded guarantee (bounded-or-surfaced, never silent) while removing the entire reclaim apparatus that
was Architecture A's seam surface.

### D-8: The origin fence ref is the authoritative cross-clone exclusion floor (N)

**Decision:** The per-unit fence ref on `origin` (D-5) is the **authoritative** no-duplicate-dispatch
guarantee (D-11) — not a best-effort guard beneath a machine-local claim, the **inversion of the run-3/run-4
design**. At dispatch a tower creates `refs/planwright-fence/<spec>/<unit-id>` by an expect-absent
compare-and-swap (the explicit all-zeros OID as the must-be-absent expectation, hardened against any git
build that treats the bare-empty form as unchecked; targeting the current `origin/main` tip, an existing
commit, so no history is added to `main` — REQ-C1.2). `origin` serializes concurrent creators to exactly one
winner, cross-clone by construction and death-surviving because the ref lives on the server, not in the
creating tower's process. Correctness holds **while `origin` is reachable**; unreachability is classified,
never failed open (D-10, REQ-C1.6). The fence uses a **dedicated namespace** (`refs/planwright-fence/…`), not
the unit's task-branch ref, so it is keyable per unit and GC-able (D-7) independent of whether the worker's
task branch exists — which is also what removes the run-4 "dispatch backend that renames the branch"
phantom: the tower pushes the fence by canonical name directly, with no worker branch in the fencing path.

**Alternatives considered:**
- **Origin ref demoted to a best-effort double-PR guard, machine-local claim authoritative** (the
  run-3/run-4 Architecture A, D-11 as previously written). Rejected because: run 4's lens showed the
  machine-local claim does not deliver the "always reclaimed" guarantee it was chosen for (it strands on
  lifecycle, keying, permanent-`origin`-error, and pid-reuse) while paying heavy standing complexity;
  `origin` reaches the exclusion guarantee natively and dissolves several of those axes, so authority belongs
  on the ref (D-11).
- **Push a bookkeeping commit to `main` at dispatch** (an older rejected variant). Rejected because:
  `orchestration-concurrency` forbids a dispatch commit on `main`; the fence pushes a *ref* at an existing
  commit, adding no history.
- **Use the task-branch ref itself as the fence.** Rejected because: it needs the worker's branch to exist
  and be byte-identical across clones (the run-4 fence finding) and conflates the work branch with the claim;
  a dedicated fence namespace is keyable and GC-able without either (see D-5).

**Chosen because:** `origin` is the one substrate that is both cross-clone and death-surviving without faking
either, so putting authority on a dedicated per-unit fence ref there is the honest floor — and it ends the
four-run pattern of a machine-local signal *assumed* cross-clone-and-death-surviving but not natively so
(D-11, D-12).

### D-9: Numbered home for the framework-script security bars and the same-operator attribution model (N)

**Decision:** The framework-script security bars applied to the coordination scripts (every parsed field
grammar-validated before use; path and ref access canonicalized and containment-checked before any read /
write / `mkdir` / unlink / `origin` ref push-or-delete; untrusted fields echo-sanitized) and the
**same-operator, single-host attribution model**
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
- **A broken/unreadable presence surface (REQ-A1.5, REQ-A1.6).** → the tower surfaces "unknown peer status"
  and **degrades awareness and strand-attribution** for the step, but **dispatch still proceeds**: under
  Architecture B the exclusion floor is the `origin` fence (D-8), independent of this surface, so a broken
  presence surface can no longer cause a double dispatch — it only blinds the tower to peers and leaves any
  orphan fence attributable to "unknown owner" rather than a named dead one. A broken surface is never read
  as **solitude** (it is surfaced, not silently treated as "no peers"); solo dispatch remains reserved for
  the genuine no-remote single-checkout posture, not a surface failure. (This is the Architecture-B change
  from the run-3 draft, where the claim surface *was* the correctness floor and a broken surface therefore
  had to halt dispatch; with correctness moved to `origin`, halting would degrade throughput for no safety
  gain — degrade capability, never safety.)
- **The absent-vs-vanished surface ambiguity (REQ-A1.5).** A **persistence sentinel** dropped at first-run
  bootstrap distinguishes "never existed" (healthy first run, proceed empty) from "existed and vanished"
  (surface it — do not read a disappeared surface as solitude), since a bare `ENOENT` cannot tell them
  apart.
- **A concurrent first-run `mkdir` race (REQ-A1.5).** An `EEXIST` from a peer that bootstrapped the
  surface a moment earlier is **success, not an error** — the create is idempotent, order-independent.
- **A fence push failure at dispatch (REQ-C1.6).** Split three ways: **no `origin` configured** → the
  genuine no-remote single-host solo posture, dispatch without a fence (no peers to collide with); a
  **rejected expect-absent CAS** (a peer already fenced the unit) → back off this unit and select another;
  a **transient push failure against a configured `origin`** → fail closed (do not dispatch this unit this
  pass, surface, retry), never dispatch blind against a possibly-fenced unit. The rejected-CAS and transient
  arms are **both a non-zero `git push`**, so the tower routes by the push's **per-ref rejection status**
  (`--porcelain` / stderr rejection reason), **not exit code alone** — a per-ref "rejected (stale info /
  already exists)" is the back-off, a transport/permission error with no per-ref rejection is the
  fail-closed-retry; a misclassification costs one wasted pass, never a double dispatch (the CAS re-adjudicates
  next pass).
- **A fence-ref GC failure (REQ-C1.5).** A transient `origin` error deleting a terminal unit's fence →
  surface and retry next pass; the delete is **idempotent**, so a fence a peer already GC'd is success,
  never an error.
- **A strand candidate the tower cannot resolve (REQ-C1.3).** A positively-dead owner with no completion
  artifact, an unknown/errored owner probe, or an unknown-owner orphan → **surface to the durable dedup'd
  sink** (REQ-C1.7) with a defined operator action; the tower never auto-reclaims. A transient `origin` read
  during the terminal/artifact check (merged-PR / ledger-done, read live) fails closed (do not act, retry next pass).

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

### D-11: The authoritative in-flight signal is the `origin` fence ref; no machine-local claim (N)

**Decision:** The authoritative no-duplicate-dispatch guarantee is the **per-unit fence ref on `origin`**,
created at dispatch by an atomic expect-absent CAS (D-5, D-8). There is **no machine-local work-claim** on
the correctness path; the machine-local presence surface is demoted to awareness/attribution only (D-2).
This **inverts the run-3/run-4 decision** that made a machine-local worker-liveness claim authoritative and
demoted `origin` — recorded as its own D-ID so the kickoff has a single anchor for the inversion and the
reasoning that finally closes the halt class. It is the load-bearing decision of the run-4→run-5 rework
(Architecture B).

**The diagnosis it rests on (multi-axis, not just locality).** The first three kickoffs each halted on the
**locality** axis: the authoritative signal was never natively **cross-clone *and* death-surviving**. Run
1's serializer (the advisory lock) was checkout-local; run 2's fence (the local task-branch ref) reached
`origin` only at PR-open; run 3 moved authority to a machine-local worker-keyed claim to get locality *and*
a death-surviving reaper on one substrate — and it **got locality right**. But correctness of this primitive
is multi-axis, and run 4's full-bundle lens found that the claim, having fixed locality, still failed on
axes nobody had checked: **worker-lifecycle** (the claim must contain the worker's death handle, but a
`process <pid>` is unknowable before the worker forks, and a pre-created tmux window reads alive-but-never-ran
→ a silent strand); **keying/granularity** (a unit-keyed claim cannot fence a cohesion bundle — a peer
selecting a non-lead member creates its own key and double-dispatches); **case-completeness** (a dead worker
that pushed commits but no PR is neither reclaimed nor GC'd nor surfaced); **version/schema skew** (a
well-formed-but-unparseable claim from a different-version peer is quarantined and its unit double-dispatched
— a *safety* bug); and **classification** (a reused pid reads confidently alive, so the bare-pid case is
silently honored). The lesson (D-12): the claim's complexity — worker-handle provenance, per-unit reclaim
locks, under-lock re-reads, four-residue GC, quarantine — was *itself the surface area* each new axis hid in.

**Why the `origin` fence satisfies it where the machine-local claim could not.** `origin` is **natively both
cross-clone and death-surviving** — every clone reads and writes the same ref set, and a ref persists on the
server after the creating tower dies — with **nothing to fake**. Keying the fence by **unit id**, created by
the **tower before the worker forks**, removes the two hardest axes outright: there is no worker death handle
to obtain pre-fork (worker-lifecycle **dissolves**) and no parsed record whose schema a peer's version could
skew (version/schema skew **dissolves**, because a git ref either exists or does not). Cohesion-bundle keying
is answered by fencing every member with `git push --atomic` (D-5). And crucially, the fence does **not**
carry the auto-reclaim burden that generated Architecture A's remaining strands: reclaim of a dead-owner unit
is the **operator's** (D-7), surfaced through a durable dedup'd sink rather than probed — which is honest
under the downgraded guarantee (D-13), since the machine-local claim did not actually deliver "always
reclaimed" either (it stranded the unclassifiable case), so the auto-recovery it paid heavy complexity for
was never reached. The one load-bearing scope assumption (single-host co-location) now bounds only strand
*attribution*, not correctness.

**Consequences (which this rework instantiates).** The double-dispatch guarantee (REQ-C1.1) rests on the
`origin` CAS; the ledger governs *dispatchability* while the fence governs *concurrency* (so a leaked fence
on a finished unit is a GC case, not a strand); no-remote multi-tower on one host is the genuine solo posture
(REQ-C1.6); cohesion-bundle members are fenced together atomically (REQ-C1.2); the version-skew safety bug
cannot occur (no record schema on the correctness path, REQ-A1.6); and every residue is bounded-and-swept or
durably-surfaced (D-13, REQ-C1.7), never silently honored forever.

**Alternatives considered:**
- **Keep the machine-local worker-liveness claim authoritative, `origin` demoted** (Architecture A, the
  run-3/run-4 design this supersedes). Rejected: run 4 showed it does not reach the "always reclaimed"
  guarantee it was chosen for (it strands on worker-lifecycle, case-completeness, and classification) while
  paying heavy standing complexity that is itself the next seam's hiding place; `origin` reaches the
  exclusion guarantee natively and dissolves several of those axes.
- **Two co-authoritative floors — the `origin` fence *and* a machine-local claim.** Rejected: two floors are
  two failure surfaces plus the reconciliation between them (which floor wins when they disagree?), and that
  reconciliation is exactly the kind of seam this rework is trying to remove. One floor, natively-correct
  locality, everything else demoted off the correctness path.
- **Keep a machine-local claim as a *fast-path* pre-selection above the fence** (a performance optimization,
  not authoritative). Rejected for this bundle: it re-introduces the parse/version/lifecycle surface for a
  throughput gain the operator did not ask for, and the rejected-CAS back-off already makes a losing tower's
  cost a single cheap push; a fast path can be added later behind evidence, not speculatively.

**Chosen because:** it stops the four-run pattern of a signal *assumed* cross-clone-and-death-surviving but
not natively so, puts authority on the one substrate that is both by construction, and — by keying the fence
per unit before the worker forks and making reclaim the operator's — dissolves or surfaces every axis rather
than hardening a growing apparatus against the next interleaving (D-12, D-13).

### D-12: The failure-axis matrix is a first-class coverage contract (N)

**Decision:** The dispatch-exclusion primitive's correctness is treated as **multi-axis**, and the axes are
enumerated **once** — {locality, worker-lifecycle, keying/granularity, the death-state machine, version/schema
skew, a defined recovery action per fail-closed path, a durable sink per residue} — with the spec required to
answer **every cell** (the *Failure-axis coverage matrix* section above). A kickoff lens verifies
**cell-completeness** against the matrix rather than hunting for the next interleaving. This is the structural
anti-recurrence device for a bundle that halted four times.

**Alternatives considered:**
- **Patch each halt's findings instance-by-instance** (the run 1–4 posture). Rejected because: it treats an
  unbounded search ("find the next interleaving") as if it were finite — each run validated only the axis
  that bit last (runs 1–3 all fixed *locality*), so a new axis surfaced every kickoff. The pattern was not
  bad luck; it was the absence of a completeness contract.
- **Rely on the kickoff lens pass alone to find gaps.** Rejected because: a lens finds holes but does not
  certify the set is *complete* — it can only report what it happened to look at. The enumerated matrix is
  the completeness contract the lens checks against, converting "did we miss one?" into "is every cell
  answered?".

**Chosen because:** "fill every cell" is finite and checkable where "find the next interleaving" is not; the
matrix makes the coverage claim auditable at kickoff and is the reason Architecture B could be evaluated on
whether it *dissolves* axes rather than only on the axis that halted run 4.

### D-13: The top-level guarantee is bounded-or-surfaced, not absolute (N)

**Decision:** The bundle states its top-level guarantee as **"best-effort exclusion (authoritative while
`origin` is reachable) plus every residue bounded-and-swept OR durably-surfaced to the operator, never
silent,"** replacing the absolute "always reclaimed / no unit ever dispatched twice" that the prior four
drafts asserted. Under this framing the run-4 correctness HIGHs stop being spec-vs-mechanism inconsistencies
and become **verifiable coverage items**: each residue is checked for a bound-and-sweep or a durable surface,
not for an impossible absolute.

**Alternatives considered:**
- **Keep the absolute guarantee** ("a crashed tower never strands a unit; no unit is ever dispatched
  twice"). Rejected because: you cannot be *sure* an absolute holds over an open-ended partial-failure
  substrate (a dead process, an unreachable `origin`, a version-skewed peer), and the run-4 HIGHs were
  precisely the spec asserting an absolute its mechanism could not reach. An unreachable absolute reads as a
  bug on every interleaving that violates it.
- **Drop guarantees entirely — best-effort, no promises.** Rejected because: **"never silent"** *is* a hard,
  verifiable guarantee, and the load-bearing one — a silently-honored strand or a silently-dropped anomaly is
  the exact failure this bundle exists to prevent. Abandoning it reopens the invisible-strand class the run-3
  and run-4 lenses flagged.

**Chosen because:** a bounded-or-surfaced invariant is verifiable per residue where an absolute is not; run 3
already began this walk ("never strands" → "positively-dead-reclaimed / unclassifiable-surfaced"), and this
decision completes it — the remaining absolutes are exactly where run 4's HIGHs landed. (The principle —
correctness over an open-ended partial-failure substrate is bounded-or-surfaced, never absolute — has now
been re-derived across four halts and is a **doctrine-graduation candidate**; a drift observation seeds that
separately rather than promoting it unilaterally here.)

## Cross-cutting concerns

- **State-safety is assumed, never restated.** Every mechanism here sits on top of
  `orchestration-concurrency`'s derived-projection ledger and per-spec lock. This bundle adds no new
  writer to `tasks.md` and no new committed state artifact; the presence records and the strand sink are
  derived, on-demand, distinct-per-writer / dedup'd machine-local surfaces, and the fence is an `origin`
  ref (deleted on terminal), never committed repo state.
- **Determinism floor.** Presence discovery, liveness attribution, fence push/GC, and strand surfacing are
  all deterministic script logic over structured signals (files, PIDs, git/`gh` state, the death-evidence
  predicate). No awareness or division decision invokes an LLM (the no-LLM-daemon-mechanics floor).
- **Security.** Tower identity on the presence surface and the strand sink is attributed and validated
  before a peer acts on it; peer output consumed for awareness is data, never code; committed coordination
  artifacts are secret-clean (the `security-posture` artifact-hygiene rule and the relay security bounds,
  carried). Attribution is scoped to the **same-operator, single-host** trust model — peer towers are the
  operator's own co-located sessions — so validation grammar-checks the identity token and refuses a
  malformed one, but does not defend against an adversarial peer forging identity (a co-tenant threat is
  out of scope, not a mechanism here). This posture — the framework-script bars plus the same-operator
  attribution model — is recorded as **D-9**, which REQ-D1.4 and REQ-D1.5 cite. Because the coordination
  scripts parse records other sessions wrote and construct git ref operations from unit ids, they meet
  planwright's **framework-script security bars** (REQ-D1.5): *every* parsed field consumed by the
  coordination logic is grammar-validated before use, not only the tower token — the tower id, the
  repository id, the **unit id and spec id** (validated before any `origin` fence-ref push or delete), the
  timestamps, the **meta-tower marker** (it drives the defer-to-authority decision, D-4), the **checkout
  path**, and the **death handle** (whose grammar is exactly the two `fleet-death-evidence.sh` forms —
  `process <pid>` with a bounded positive integer, or `tmux-window <session> <window>` on that predicate's
  tmux charset — read from an untrusted peer presence record and passed to the predicate); a field that
  fails its grammar is refused, not coerced. Path and ref access is **canonicalized and containment-checked**
  before any read, write, `mkdir`, unlink, or ref push/delete — the surface directory itself (so a
  **surface-root symlink** cannot redirect containment outside it), each presence record path, the
  strand-sink path, and the **fence-ref name** (confirmed inside `refs/planwright-fence/<spec>/` before any
  push or delete) — so a crafted unit/tower id can never drive a write, delete, or ref operation outside its
  bounds. Untrusted record fields echoed to a terminal or log pass the echo-discipline sanitizer
  (`scripts/echo-safety.sh`, `sanitize_printable`). Three further surfaces of the trust model: the surface
  directory is **user-private** (`0700`, REQ-A1.4) with a pre-existing over-broad surface **refused, not
  reused** — access control is what actually enforces "same operator"; and both a peer tower's machine-local
  **checkout path** *and* its **death handle** (a pid, or a tmux session+window name) are operational detail
  that must not leak from the surfaces into a committed artifact such as a PR body (REQ-D1.4).
