# Concurrent Orchestrator Coordination — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Five tasks. Task 1 (the coordination-floor doctrine statement and the D-1 altitude record) is
foundational: every other task cites it, so it dispatches first. Task 5 (the coordination-artifact
hygiene guard) protects every committed presence/claim artifact and, per the
guard-infrastructure-first selection rule, outranks the critical path once Task 1 lands. The top
mechanism wins are Task 2 (the cross-tower presence signal) and Task 3 (the per-tower checkout root
fix). Task 4 (the peer work-claim) carries the **authoritative dispatch-time origin fence (D-8,
REQ-C1.6)** plus the best-effort claim layer above it: it reuses Task 2's repository-scoped machine-local
surface and tower identity — building the claims sub-surface (unit-keyed atomic-create objects) beside
Task 2's presence sub-surface (distinct-per-writer records) — **and** the origin fence relies on Task 3's
per-tower-checkout / `origin` topology and its canonical byte-identical branch naming, so Task 4 depends
on **both Task 2 and Task 3**. Task 3 is independent of Task 2. All tasks depend on Task 1. The critical
path is Task 1 → {Task 2, Task 3} → Task 4; Task 5 runs in parallel after Task 1.

## Tasks

### Task 1 — Coordination-floor doctrine statement & altitude record

- **Deliverables:** The assume-multiplicity coordination-floor statement (a tower keeps tabs on peer
  towers and coordinates division rather than assuming solitude), written as an extension of
  `fleet-coordination-floor.md` and recorded as the D-1 altitude record cited from the Goal; the carried
  floors stated with citations (positive-evidence-of-death and no-LLM-daemon-mechanics for all reclaim /
  discovery paths; the no-auto-merge / no-autonomous-ready / tower-non-authoring boundaries unchanged,
  REQ-D1.3); and the scope-boundary statement (D-6) naming `fleet-autonomy` as usage-governance owner and
  `orchestration-fleet` as relay owner. No new mechanism — this task fixes the altitude and the floors the
  other tasks build on.
- **Done when:** the doctrine statement exists and is cited by REQ-A1.1 and from the Goal as the D-1
  altitude record; the carried floors and the D-6 boundary are stated with their citations; the spec
  validator passes on the bundle; CI passes.
- **Dependencies:** none
- **Citations:** D-1, D-6 · REQ-A1.1, REQ-D1.3
- **Estimated effort:** 1 day

### Task 2 — Cross-tower presence signal (publish, discover, liveness)

- **Deliverables:** A per-tower presence record written to a shared, user-private (`0700`) machine-local
  directory as one file per tower under the current repo id's sub-surface, carrying repository identity,
  a **tower identity** (session UUID where present, else a pid + start-time + checkout-hash composite —
  never the bare pid or checkout path alone, REQ-A1.7), checkout path, spec(s) advanced, start time,
  heartbeat, a **death handle in one of the two `fleet-death-evidence.sh` forms** — the reuse-resistant
  `tmux-window <session> <window>` preferred where the tower runs under tmux, `process <pid>` the
  degraded fallback — and a **meta-tower marker that is the record's own validated boolean field** (from
  the tower's `--meta` mode; **not** `fleet-tower-marker.sh`, whose field is the orthogonal
  `unattended|interactive` recovery mode); each record written **atomically** (write-temp-then-rename).
  The surface directory created with an atomic mode-explicit `mkdir`, a pre-existing over-broad surface
  **refused not reused** (verify-or-refuse), and a **persistence sentinel** dropped at bootstrap. A
  deterministic discovery scan that scopes to the current repository by scanning the per-`<repo-id>`
  sub-surface (repo id in-record verified as a cross-check), excludes the tower's own record by tower
  identity, enumerates peer records, and applies the tri-state `fleet-death-evidence.sh` predicate
  (alive / positively-dead / unknown) to classify each — only positively-dead reclaimable, unknown
  treated as not-dead — **caching each verdict for the pass** and running on a **capped heartbeat
  cadence** (bounded per-record subprocess fan-out), with a per-record parse that fails closed (a
  malformed record is skipped with an error, never read as "no such peer"). A positively-dead tower's
  file is GC'd on discovery **under an under-lock re-read** that re-confirms it is still that dead
  tower's record before unlinking (so a dead-then-restarted tower's fresh live record is never deleted).
  First-run bootstrap (no surface ever existed, per the sentinel) creates the user-private surface
  directory and proceeds empty (healthy); an existing-but-unreadable surface, or a vanished surface
  (sentinel present, directory gone), fails closed; a concurrent-bootstrap `mkdir` `EEXIST` is success;
  publish-then-discover ordered so the surface is never read as absent mid-bootstrap. Integration so a
  tower runs discovery at startup and on its heartbeat. No shared registry file, no LLM on the
  discovery/reclaim path, no new committed state artifact (the live-tower set is derived on demand).
- **Done when:** a fixture with N per-tower record files resolves exactly the live subset via the
  death-evidence predicate (a positively-dead tower's record is classified reclaimable, a heartbeating
  one live, an unknown/errored death result treated as not-dead), and records under a *different*
  repo-id sub-surface are excluded from the peer set, and the tower's own record is excluded **by tower
  identity** (REQ-A1.7 — a fixture shows two towers on one checkout compute distinct identities, no
  collision, no self-as-peer); concurrent writers are shown to land distinct files with no collision (no
  shared-registry write path exists) and the write primitive is asserted **structurally** to be
  write-temp-then-rename (not a mkdir-then-populate), so no torn record can exist; the **death handle** is
  one of the two `fleet-death-evidence.sh` forms with the `tmux-window` form preferred under tmux; the
  **meta-tower marker is the record's own validated field** (a source/grep assertion that the
  meta/ordinary distinction is not read from `fleet-tower-marker.sh`); a malformed record fails closed
  (skipped with a surfaced error, never read as absent); the surface directory is created `0700` and a
  **pre-existing over-broad surface is refused, not reused**; a positively-dead tower's file GC racing a
  re-publish of that tower's **fresh live** record does not delete the fresh record (under-lock re-read);
  discovery **caches liveness per pass** (≤1 death-predicate subprocess per record per pass) on a capped
  cadence; the discovery scan invokes no LLM and issues no backend-specific pane/process scrape; a tower
  that finds ≥1 live peer does not behave as sole tower (asserted via the selection path in Task 4, or a
  standalone flag until then); discovery distinguishes a healthy-but-empty **first-run** surface (no
  sentinel, directory created) from a **vanished** surface (sentinel present, directory gone → fail
  closed) and from an absent / unreadable / misconfigured one, failing closed on those (an explicit error
  or "unknown peer status", never read as solitude), and a concurrent-bootstrap `mkdir` `EEXIST` is
  treated as success; the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-1, D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7
- **Estimated effort:** 2 days

### Task 3 — Per-tower checkout model, migration path & cross-checkout `main` currency

- **Deliverables:** The documented per-tower-checkout topology (each tower a separate checkout with a
  private mutable local `main`, coordinating via `origin` and the presence/claim surfaces); the documented
  **reachable-`origin` precondition** for separate-clone multi-tower — the topology coordinates through
  `origin` (both the D-8 dispatch fence, REQ-C1.6, and `main` currency), so the **no-remote case is the
  single-checkout solo flow**, not a multi-tower configuration; a defined adoption / migration path from
  the single-checkout + reconcile-via-quick-PR model, with that model retained as the sanctioned degraded
  fallback; and the cross-checkout `main`-currency sync path using
  explicit `git fetch origin main && git merge --ff-only FETCH_HEAD` (fast-forward-only, never rebase,
  never a direct push to a shared `main`), which runs only with `main` as the checked-out branch (or
  operates on the `main` ref explicitly) so it never merges `origin/main` onto a worker branch, and which
  fails closed on a failed `git fetch` (surfacing the failure rather than proceeding on a silently-stale
  `main`), accounting for the `branch.autosetuprebase=always` pitfall that turns a bare `git pull` into a
  forbidden rebase. The migration path SHALL cover each clone's own repo-root machine-local env file and
  a stable `auth_sock` symlink indirection (never a captured ephemeral forwarded socket), so a fresh
  per-tower clone signs and fetches without inheriting a dead session's plumbing.
- **Done when:** the per-tower-checkout model and its migration/fallback path are documented and
  verified against `orchestration-concurrency`'s derived-projection and never-rewrite-history invariants
  (no invariant weakened); the sync path is demonstrated to fetch-then-merge (`--ff-only`) and to refuse
  / avoid a rebase even under `branch.autosetuprebase=always` (a fixture asserts the invoked operation is
  a fast-forward merge, not a rebase, at the command level — the graph shape alone cannot distinguish
  them under fast-forward), to run only with `main` checked out **or** to update the `main` ref without a
  checkout via `git fetch origin main:main` (that non-checked-out ref-update path is exercised by a
  fixture, not left untested), never a bare merge onto a worker branch, and to **classify a fetch failure
  before acting** — a **no-`origin`-configured** state degrades to the single-checkout solo flow while a
  **transient fetch failure against a configured `origin`** fails closed (surface, do not proceed on a
  stale `main`), and a `--ff-only` refusal is surfaced for the operator (never force/rebase/reset); the
  degraded single-checkout fallback is explicitly documented as sanctioned; a fresh
  per-tower clone is confirmed (manual sweep) to sign and fetch through its own repo-root machine-local
  env file and the stable `auth_sock` symlink indirection, without inheriting a dead session's plumbing;
  the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-3, D-8, D-10 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-C1.6
- **Estimated effort:** 2 days

### Task 4 — Peer work-claim (claim-before-dispatch, death-evidence reclaim)

- **Deliverables:** A two-layer work-division mechanism. **Authoritative layer — the dispatch-time origin
  fence (REQ-C1.6, D-8):** at dispatch, before any worker runs, the tower **atomically creates the unit's
  task-branch ref on `origin`** by a compare-and-swap that succeeds only if the ref is absent
  (`git push --force-with-lease=refs/heads/<branch>:` with an empty expected value), so `origin`
  arbitrates a single dispatcher per unit; a **losing tower treats the rejection as "already dispatched"
  and aborts without launching a worker**. The branch name is a **canonical, byte-identical-across-clones**
  derivation of the unit id (`planwright/<spec>/task-<id>`), with the worktree branch renamed to it before
  the fence push (never `claude --worktree`'s name-mangling, which would create divergent refs and defeat
  the fence). The ref lives on `origin` from the instant of dispatch (not PR-open) and survives the
  dispatching tower's death, so it is both the cross-clone fence and the reclaim guard's in-flight
  evidence. Requires a reachable `origin` (the no-remote single-checkout solo flow needs no cross-clone
  fence); a lost/errored fence result fails closed (treat the unit as possibly-taken, do not dispatch),
  never fail-open. **Best-effort claim layer** (keyed by
  unit id under the repository scope on Task 2's machine-local surface, `<surface>/<repo-id>/claims/<unit-id>`):
  a tower claims a unit before dispatch by an **atomic, exclusive create-with-content** of that unit-keyed
  claim object — exclusive (fails if the name exists) *and* complete the instant it appears (carrying the
  owner identity + death handle), e.g. a hardlink of a fully-written temp into the unit-keyed name; NOT a
  bare `mkdir` (which leaves an empty-claim crash window) and NOT a plain temp-then-rename (which
  overwrites, losing exclusivity). The create is the serializer, so a losing tower's create fails
  atomically and it reads the existing claim and skips (reducing double-*selection* across separate clones,
  where the checkout-local per-spec lock cannot serialize; duplicate *dispatch* is prevented by the
  authoritative **dispatch-time origin fence (D-8)**, not the claim). A selection guard skips any unit with a live claim. **Reclaim** — a read → check → swap
  that cannot be one atomic FS step — is serialized by a **per-unit reclaim lock** held only across the
  fast swap: (1) read the claim, honoring a live/unknown owner with no mutation; (2) *outside the lock*
  confirm the owner positively dead (tri-state; unknown treated as not-dead) and that **no live downstream
  dispatch artifact — the unit's task-branch ref on `origin` (D-8) or an open PR — exists**, so a dead
  tower whose worker outlived it is not re-dispatched (the origin ref is present from dispatch, closing
  the not-yet-pushed-orphan blind spot); (3) acquire the per-unit reclaim lock (a `mkdir` lock on the surface, reusing
  `orchestration-concurrency`'s `mkdir`-plus-stale-break discipline; busy → skip this round); (4) *under
  the lock* re-read the claim and proceed only if it is still the same dead owner's, else abort untouched,
  then remove it and compete for the unit via the normal create-with-content; (5) release the lock.
  Initial claims stay lock-free. **Lifecycle:** the tower releases its claim on handoff (worker dispatched
  / **origin task-branch ref exists**, so the D-8 fence takes over) and immediately on dispatch failure;
  a failed release `rm` is surfaced and retried, backstopped by the discovery GC once the tower is dead
  (bounded delay, never a permanent strand). The **discovery sweep GC's three residues** — dead-tower
  claims, stale per-unit reclaim locks, **and orphan temp files** (from an interrupted create-with-content;
  the temp is created *inside* the surface dir, same filesystem, so the hardlink is atomic and cannot hit
  `EXDEV`) — each **under the same per-unit reclaim lock and under-lock re-read** as the reclaim path
  before unlinking, so GC never deletes a claim a concurrent reclaimer just swapped for a fresh live one.
  A **corrupt (unparseable) claim** (which cannot be liveness-checked) is **quarantined** to a
  containment-checked dead-letter sub-surface on repeated parse failure and surfaced for the operator, so
  its unit is re-selectable rather than permanently blocked. The
  death / artifact check is never inside the lock. All record, reclaim-lock, quarantine, and unlink paths
  are canonicalized and containment-checked to the surface (including the surface root, so a surface-root
  symlink cannot redirect containment) before any create, `mkdir`, or `rm`. The mechanism composes with
  `orchestration-fleet`'s meta-tower selection where a meta-tower is present (distinguished by the
  presence record's own validated meta marker, REQ-A1.2).
- **Done when:** the **authoritative dispatch-time origin fence (REQ-C1.6, D-8)** is asserted against a
  **local bare-repo `origin` fixture** — two towers dispatching one unit both attempt the atomic
  expect-absent ref create, exactly **one succeeds and the loser's push is rejected**, and the loser
  **aborts before launching a worker** (not after a worker ran to push time), so a forced claim-layer
  failure (two towers made to both hold a claim, e.g. a simulated stale-broken reclaim lock) still yields
  a **single dispatch**, the race degrading to wasted *selection* work, never a double dispatch; the
  canonical branch name is **byte-identical across the two clones** (a fixture shows both contend for the
  *same* `origin` ref, and that `claude --worktree` mangling is not the naming path); a **lost/errored
  fence result fails closed** (unit treated as possibly-taken, not dispatched), never fail-open; the
  no-remote path is the documented single-checkout solo flow (no fence attempted); a two-tower fixture shows two towers racing to claim one unit resolve to a single holder
  via the atomic create-with-content (the loser reads the winner's claim and skips), including across
  separate-clone surfaces; a concurrent **discovery-GC racing a reclaimer** does not delete a
  freshly-swapped live claim (GC takes the reclaim lock and re-reads under it); a claim is never observed lacking its death handle (the create
  is atomic-with-content — no empty-claim window), and a bare-`mkdir` or plain-rename primitive is shown
  insufficient / not used; two towers reclaiming one positively-dead claim resolve to a single holder via
  the **per-unit reclaim lock** (concurrent reclaimers serialize on the lock; the loser skips the round),
  and a lock-free rename-aside or delete-then-recreate reclaim is shown to double-dispatch / destroy a
  live claim and is not used; the **under-lock re-read aborts** when the claim changed during the slow
  check (a fresh claimant that took the freed unit is not clobbered — no double-dispatch, no live claim
  destroyed); a live claim (including a live-but-hung tower's) is honored and never auto-reclaimed, a
  positively-dead tower's claim is reclaimable, and an unknown/errored death result is treated as not-dead
  (no reclaim on a guess); a reclaim whose unit has a **live `origin` task-branch ref or open PR** does
  **not** re-dispatch (the downstream-artifact guard, reading the ref live from dispatch — a fixture with
  a dead tower's *not-yet-PR'd* orphan ref on `origin` shows the guard sees it and does not re-dispatch);
  the death / artifact check is shown to run outside the reclaim lock (no
  subprocess under the lock); a claim is released on handoff and on dispatch failure (a failed dispatch
  strands nothing), a failed release `rm` is surfaced-and-retried not silently dropped, and the discovery
  GC sweeps all three residues — a dead tower's claim on an already-completed unit, a **stale reclaim
  lock**, and an **orphan temp file** — none left to leak; a **corrupt (unparseable) claim** is
  **quarantined** to the dead-letter sub-surface on repeated parse failure (unit re-selectable, not blindly
  deleted); a crafted unit/tower id cannot drive a create, `mkdir`, or unlink outside the surface
  (containment asserted, including against a surface-root symlink); reclaim invokes no LLM; the mechanism
  only creates / reads / removes claim objects and the reclaim lock, and never mutates a peer's or
  worker's branch state; the meta-tower-present path defers to meta-tower selection **via a fixture**
  (committed to the executable assertion, not hedged to documentation-only); the validator and CI pass.
- **Dependencies:** 2, 3
- **Citations:** D-4, D-5, D-7, D-8 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-D1.5
- **Estimated effort:** 3 days

### Task 5 — Coordination-artifact hygiene guard & cross-reference wiring

- **Deliverables:** The commit-independent core first — the framework-script security bars (REQ-D1.5, D-9)
  applied to the coordination scripts that parse records other sessions wrote: **every** parsed field
  grammar-validated before use — tower id, repository id, unit id, spec id, timestamps, the **meta-tower
  marker**, the **checkout path**, and the **death handle** (whose declared grammar is the two
  `fleet-death-evidence.sh` forms, `process <pid>` or `tmux-window <session> <window>`) — not only the
  tower token, never interpolated; **path canonicalization + containment** on the surface directory itself
  (so a **surface-root symlink** cannot redirect it), every record path, the per-unit reclaim lock, the
  quarantine dead-letter path, and the reclaim `rm` target, so a crafted id cannot drive a write, `mkdir`,
  or unlink outside the surface; the **echo-discipline sanitizer** (`scripts/echo-safety.sh`,
  `sanitize_printable`) on any untrusted record field echoed to a terminal or log; and the
  **data-not-code** discipline on peer records (no `eval` / unquoted-expansion path). Enforcement of the
  same-operator trust model at the surface: the coordination directory is created/verified **user-private**
  (`0700`, REQ-A1.4) with a pre-existing over-broad surface **refused, not reused**, and both a peer
  tower's machine-local **checkout path** *and* its **death handle** (pid, or tmux session+window name)
  are prevented from leaking from the surfaces into any committed artifact (a PR body, an audit log —
  REQ-D1.4). Plus a *conditional* hygiene guard that scans any coordination record a
  deployment does commit (a committed audit / handover log, or a summary of presence/claims that lands in
  git) for secrets, credentials, internal hostnames, checkout paths, and sensitive operational detail,
  wired into `mise run check` alongside the existing secret-scan of fleet artifacts — noting that
  presence/claim records are normally machine-local and uncommitted, so the scan targets only what
  actually lands in git; and the cross-reference wiring into `orchestration-concurrency` (state-safety
  floor), `orchestration-fleet` (relay + meta-tower), and `fleet-autonomy` (usage-governance boundary) so
  the seams are legible.
- **Done when:** **every** parsed field is refused when malformed — validated against a declared grammar,
  never interpolated — asserted **per field** including the meta-tower marker, the checkout path, and the
  death handle (against its two `fleet-death-evidence.sh` forms); peer output consumed for awareness is
  treated as data (no `eval` / unquoted-expansion path); a crafted record path, reclaim target, or
  quarantine path that would escape the surface is refused (canonicalized + containment-checked,
  **including against a surface-root symlink**), and an embedded escape sequence in a record field is
  stripped before echo (`sanitize_printable`); the surface is confirmed `0700` and a pre-existing
  over-broad surface is refused; **both** a peer checkout path **and** a death handle are shown not to
  reach a committed artifact (PR body); the conditional hygiene guard flags a seeded secret / internal
  hostname / checkout path / death handle in a committed coordination artifact and passes a clean one, and
  is a no-op (not a false failure) when no coordination record is committed; the cross-references resolve
  to the named bundles and a **positive** assertion confirms the relay is consumed (not merely a
  grep-for-absence — REQ-D1.1, REQ-D1.2); the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-6, D-9 · REQ-D1.1, REQ-D1.2, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
