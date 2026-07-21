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
fix); Task 4 (the peer work-claim) reuses Task 2's repository-scoped machine-local surface and tower
identity — building the claims sub-surface (unit-keyed atomic-create objects) beside Task 2's presence
sub-surface (distinct-per-writer records) — so it depends on Task 2. Task 3 is independent of Task 2.
All tasks depend on Task 1. The critical path is Task 1 → Task 2 → Task 4; Task 3 and Task 5 run in
parallel after Task 1.

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
  directory as one file per tower, carrying repository identity, tower identity, checkout path, spec(s)
  advanced, start time, heartbeat, the positive-evidence-of-death handle, and the `fleet-tower-marker.sh`
  meta-tower marker; each record written **atomically** (write-temp-then-rename). A deterministic
  discovery scan that scopes to the current repository by repo id, excludes the tower's own record,
  enumerates peer records, and applies the tri-state `fleet-death-evidence.sh` predicate (alive /
  positively-dead / unknown) to classify each — only positively-dead reclaimable, unknown treated as
  not-dead — with a per-record parse that fails closed (a malformed record is skipped with an error,
  never read as "no such peer"). First-run bootstrap creates the user-private surface directory and
  proceeds empty (healthy), distinct from an existing-but-unreadable surface which fails closed;
  publish-then-discover ordered so the surface is never read as absent mid-bootstrap. Integration so a
  tower runs discovery at startup and on its heartbeat. No shared registry file, no LLM on the
  discovery/reclaim path, no new committed state artifact (the live-tower set is derived on demand).
- **Done when:** a fixture with N per-tower record files resolves exactly the live subset via the
  death-evidence predicate (a positively-dead tower's record is classified reclaimable, a heartbeating
  one live, an unknown/errored death result treated as not-dead), and records for a *different*
  repository id are excluded from the peer set, and the tower's own record is excluded; concurrent
  writers are shown to land distinct files with no collision (no shared-registry write path exists) and
  a reader never observes a torn record (atomic write asserted); a malformed record fails closed (skipped
  with a surfaced error, never read as absent); the surface directory is created `0700`; the discovery
  scan invokes no LLM and issues no backend-specific pane/process scrape; a tower that finds ≥1 live peer
  does not behave as sole tower (asserted via the selection path in Task 4, or a standalone flag until
  then); discovery distinguishes a healthy-but-empty surface (including the first-run bootstrap where the
  directory is created) from an absent / unreadable / misconfigured one and fails closed on the latter
  (an explicit error or "unknown peer status", never read as solitude); the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-1, D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6
- **Estimated effort:** 2 days

### Task 3 — Per-tower checkout model, migration path & cross-checkout `main` currency

- **Deliverables:** The documented per-tower-checkout topology (each tower a separate checkout with a
  private mutable local `main`, coordinating via `origin` and the presence/claim surfaces); a defined
  adoption / migration path from the single-checkout + reconcile-via-quick-PR model, with that model
  retained as the sanctioned degraded fallback; and the cross-checkout `main`-currency sync path using
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
  them under fast-forward), to run only with `main` checked out (never a merge onto a worker branch), and
  to fail closed on a fetch failure rather than proceed on a stale `main`; the degraded single-checkout
  fallback is explicitly documented as sanctioned; a fresh
  per-tower clone is confirmed (manual sweep) to sign and fetch through its own repo-root machine-local
  env file and the stable `auth_sock` symlink indirection, without inheriting a dead session's plumbing;
  the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4
- **Estimated effort:** 2 days

### Task 4 — Peer work-claim (claim-before-dispatch, death-evidence reclaim)

- **Deliverables:** A work-claim mechanism keyed by unit id under the repository scope on Task 2's
  machine-local surface (`<surface>/<repo-id>/claims/<unit-id>`): a tower claims a unit before dispatch by
  an **atomic exclusive-create** (`mkdir`) of that unit-keyed claim object — the create is the serializer,
  so a losing tower's create fails atomically and it reads the existing claim and skips (no double-dispatch
  across separate clones, where the checkout-local per-spec lock cannot serialize). Each claim object
  records the claiming tower's identity and its self-contained positive-evidence-of-death handle. A
  selection guard skips any unit with a live claim. **Reclaim** removes a positively-dead tower's claim and
  re-takes it by the same atomic create (serializing concurrent reclaimers), gated on the tri-state death
  predicate (only positively-dead; unknown treated as not-dead) **and** on confirming no live downstream
  dispatch artifact (branch / open PR, the branch-as-fence) exists for the unit, so a dead tower whose
  worker outlived it is not re-dispatched. **Lifecycle:** the tower releases its claim on handoff (worker
  dispatched / branch exists) and immediately on dispatch failure, and dead-tower claims are GC'd on
  discovery — no held critical section around the death check (the create returns immediately; liveness /
  artifact checks run after). All record and reclaim-unlink paths are canonicalized and containment-checked
  to the surface before any create or `rm`. The mechanism composes with `orchestration-fleet`'s meta-tower
  selection where a meta-tower is present (distinguished by the presence-schema marker).
- **Done when:** a two-tower fixture shows two towers racing to claim one unit resolve to a single holder
  via the atomic create (the loser reads the winner's claim and skips — no double-dispatch), including
  across separate-clone surfaces; two towers reclaiming one positively-dead claim likewise resolve to a
  single holder (concurrent reclaimers serialized by the re-create); a live claim (including a live-but-hung
  tower's) is honored and never auto-reclaimed, a positively-dead tower's claim is reclaimable, and an
  unknown/errored death result is treated as not-dead (no reclaim on a guess); a reclaim whose unit has a
  live branch/PR does **not** re-dispatch (downstream-artifact guard); a claim is released on handoff and
  on dispatch failure (a failed dispatch strands nothing) and dead claims are GC'd; a crafted unit/tower id
  cannot drive a create or unlink outside the surface (containment asserted); reclaim invokes no LLM; the
  mechanism creates/reads/removes only claim objects and never mutates a peer's or worker's branch state;
  the meta-tower-present path defers to meta-tower selection (asserted or documented-and-delegated); the
  validator and CI pass.
- **Dependencies:** 2
- **Citations:** D-4, D-5, D-7 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-D1.5
- **Estimated effort:** 3 days

### Task 5 — Coordination-artifact hygiene guard & cross-reference wiring

- **Deliverables:** The commit-independent core first — the framework-script security bars (REQ-D1.5)
  applied to the coordination scripts that parse records other sessions wrote: **every** parsed
  identifier grammar-validated before use (tower id, repository id, unit id, spec id — not only the tower
  token), never interpolated; **path canonicalization + containment** on the surface, every record path,
  and the reclaim `rm` target, so a crafted id cannot drive a write or unlink outside the surface; the
  **echo-discipline sanitizer** (`scripts/echo-safety.sh`, `sanitize_printable`) on any untrusted record
  field echoed to a terminal or log; and the **data-not-code** discipline on peer records (no `eval` /
  unquoted-expansion path). Enforcement of the same-operator trust model at the surface: the coordination
  directory is created/verified **user-private** (`0700`, REQ-A1.4), and a peer tower's machine-local
  **checkout path is prevented from leaking** from the surfaces into any committed artifact (a PR body, an
  audit log — REQ-D1.4). Plus a *conditional* hygiene guard that scans any coordination record a
  deployment does commit (a committed audit / handover log, or a summary of presence/claims that lands in
  git) for secrets, credentials, internal hostnames, checkout paths, and sensitive operational detail,
  wired into `mise run check` alongside the existing secret-scan of fleet artifacts — noting that
  presence/claim records are normally machine-local and uncommitted, so the scan targets only what
  actually lands in git; and the cross-reference wiring into `orchestration-concurrency` (state-safety
  floor), `orchestration-fleet` (relay + meta-tower), and `fleet-autonomy` (usage-governance boundary) so
  the seams are legible.
- **Done when:** every parsed identifier is refused when malformed (validated against a declared grammar,
  never interpolated) and peer output consumed for awareness is treated as data (no `eval` /
  unquoted-expansion path); a crafted record path or reclaim target that would escape the surface is
  refused (canonicalized + containment-checked), and an embedded escape sequence in a record field is
  stripped before echo (`sanitize_printable`); the surface is confirmed `0700`; a peer checkout path is
  shown not to reach a committed artifact (PR body); the conditional hygiene guard flags a seeded secret /
  internal hostname / checkout path in a committed coordination artifact and passes a clean one, and is a
  no-op (not a false failure) when no coordination record is committed; the cross-references resolve to the
  named bundles; the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-6 · REQ-D1.1, REQ-D1.2, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
