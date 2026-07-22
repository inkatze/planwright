# Concurrent Orchestrator Coordination — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-21
**Format-version:** 2
**Execution:** derived — see the status render

Five tasks. Task 1 (the coordination-floor doctrine statement, the D-1 altitude record, and the
correctness-model framing — the failure-axis coverage matrix D-12 and the guarantee downgrade D-13) is
foundational: every other task cites it, so it dispatches first. Task 5 (the coordination-artifact
hygiene guard) protects every committed presence / strand-sink artifact and, per the
guard-infrastructure-first selection rule, outranks the critical path once Task 1 lands. The top
mechanism wins are Task 2 (the cross-tower presence signal) and Task 3 (the per-tower checkout root
fix). Task 4 (the peer fence) carries the **authoritative per-unit `origin` fence ref (D-5, D-8, D-11,
REQ-C1.1)** plus operator-surfaced strand handling (D-7, REQ-C1.3, REQ-C1.7): the fence lives on `origin`,
so Task 4's **correctness depends on Task 3** (the per-tower-checkout / `origin` topology and its
reachable-`origin` precondition); strand *attribution* reads Task 2's presence surface (mapping an orphan
fence to a dead owner) and surfaces to the durable sink, so Task 4's **attribution and surfacing depend on
Task 2**. Task 4 therefore depends on **both Task 2 and Task 3**, and — the inversion from the run-3/run-4
draft — the critical *correctness* path now runs through **Task 3** (`origin`), while Task 2 gates
awareness and strand-attribution rather than exclusion. Task 3 is independent of Task 2. All tasks depend
on Task 1. The critical path is Task 1 → {Task 2, Task 3} → Task 4; Task 5 runs in parallel after Task 1.

## Tasks

### Task 1 — Coordination-floor doctrine statement & altitude record

- **Deliverables:** The **two** coordination-floor doctrine statements, written as extensions of
  `fleet-coordination-floor.md` and recorded under the D-1 altitude record cited from the Goal: (1) the
  primary **assume-multiplicity** statement (a tower keeps tabs on peer towers and coordinates division
  rather than assuming solitude); and (2) the narrower **companion** statement on the tower→human axis — a
  **reserved-human moment (a merge-ready PR) reaches the operator by deterministic push, LLM-poll being the
  fallback** — recorded as a doctrine line only, with its mechanism cross-referenced to the planned
  `merge-currency-guard` spec (REQ-D1.6, D-6), **not** implemented here. The carried floors stated with
  citations (positive-evidence-of-death and no-LLM-daemon-mechanics for all reclaim / discovery paths; the
  no-auto-merge / no-autonomous-ready / tower-non-authoring boundaries unchanged, REQ-D1.3); and the
  scope-boundary statement (D-6) naming `fleet-autonomy` as usage-governance owner, `orchestration-fleet` as
  relay owner, and `merge-currency-guard` as the ready-push-mechanism owner. This task also lands the
  **correctness-model framing** the other tasks build against: the one-floor-plus-bounded-residue model, the
  **failure-axis coverage matrix** (D-12) with every cell answered, and the **downgraded top-level
  guarantee** (D-13, "best-effort exclusion + every residue bounded-and-swept OR durably-surfaced, never
  silent"), all in `design.md` and cited from the Goal. No new *mechanism* — this task fixes the altitude,
  the guarantee, the coverage contract, and the floors the other tasks build on.
- **Done when:** both doctrine statements exist and are cited from the Goal under the D-1 altitude record
  (the assume-multiplicity statement also cited by REQ-A1.1, the companion by REQ-D1.6); the carried floors
  and the D-6 boundary (three owners) are stated with their citations; the failure-axis coverage matrix
  (D-12) is present with **every cell answered** and the downgraded guarantee (D-13) stated and cited from
  the Goal; the spec validator passes on the bundle; CI passes.
- **Dependencies:** none
- **Citations:** D-1, D-6, D-12, D-13 · REQ-A1.1, REQ-C1.1, REQ-D1.3, REQ-D1.6
- **Estimated effort:** 1 day

### Task 2 — Cross-tower presence signal (publish, discover, liveness)

- **Deliverables:** A per-tower presence record written to a shared, user-private (`0700`) machine-local
  directory as one file per tower under the current repo id's sub-surface, carrying repository identity,
  a **tower identity** (session UUID where present, else a pid + start-time + checkout-hash composite —
  never the bare pid or checkout path alone, REQ-A1.7), checkout path, spec(s) advanced, the **set of
  unit-ids the tower currently holds an `origin` fence for** (the strand-attribution field, refreshed on the
  heartbeat, by which a peer maps an orphan fence ref to this owner — REQ-A1.2, REQ-C1.3, Task 4), start
  time, heartbeat, a **death handle in one of the two `fleet-death-evidence.sh` forms** — the reuse-resistant
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
  file is GC'd on discovery under a **best-effort re-read-and-skip** (skip the delete if the file no longer
  looks like the classified dead record; **no lock** — a benign TOCTOU remains) before unlinking; because
  presence is off the correctness path and every live tower re-publishes each heartbeat, a rare racing delete
  of a dead-then-restarted tower's fresh record **self-heals within one heartbeat** (awareness-only, never a
  correctness effect).
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
  meta/ordinary distinction is not read from `fleet-tower-marker.sh`); the record carries the tower's
  **currently-fenced unit-ids** refreshed on the heartbeat, and a fixture shows a peer resolving a fence
  ref's owner from that field (and classifying a unit no live record lists as unknown-owner — REQ-C1.3,
  Task 4); a malformed record fails closed (skipped with a surfaced error, never read as absent); the
  surface directory is created `0700` and a
  **pre-existing over-broad surface is refused, not reused**; a positively-dead tower's file GC racing a
  re-publish of that tower's **fresh live** record is best-effort-skipped by the re-read (no lock), and any rare racing delete self-heals on the next heartbeat re-publish (awareness-only);
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
  private mutable local `main`, coordinating via `origin` and the presence surface); the documented
  **reachable-`origin` precondition** for separate-clone multi-tower — the topology coordinates through
  `origin` for **both the correctness floor** (the D-8 per-unit dispatch fence, REQ-C1.6) **and** `main`
  currency, so `origin` reachability is now the fence's precondition and the **no-remote case is the
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
  **and (REQ-B1.1 manual anchor, so it is not silently droppable) a dated entry in this task's verification
  notes records a two-checkout run — the two tower identities and that no shared-`main` mutation was
  observed — the task is not complete until that note exists**; the validator and CI pass.
- **Dependencies:** 1
- **Citations:** D-3, D-8, D-10 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-C1.6
- **Estimated effort:** 2 days

### Task 4 — Peer fence (per-unit origin CAS at dispatch, operator-surfaced strands)

- **Deliverables:** The work-division mechanism: an **authoritative per-unit `origin` fence ref** plus
  **operator-surfaced strand handling**, with **no machine-local claim, reclaim lock, four-residue GC, or
  quarantine** (all removed with Architecture A). **The fence (REQ-C1.1, REQ-C1.2, D-5, D-8, D-11):** at
  dispatch, before any worker runs, the tower fences the unit by an **atomic expect-absent
  compare-and-swap** creating `refs/planwright-fence/<spec>/<unit-id>` on `origin` (`git push
  --force-with-lease=refs/planwright-fence/<spec>/<unit-id>:$ZERO_OID origin
  <origin/main-tip>:refs/planwright-fence/<spec>/<unit-id>`, where the `--force-with-lease` names the fence
  ref and its must-be-absent expectation `$ZERO_OID` (**the object-format's all-zeros object id**, 40 hex
  zeros under SHA-1 / 64 under SHA-256, **never the bare-empty nothing-after-colon form**) and the trailing
  `origin <origin/main-tip>:refs/planwright-fence/<spec>/<unit-id>` is the refspec actually pushed — creating
  the fence ref at the current `origin/main` tip so no history is added to `main`). The
  push **is** the serializer: `origin` serializes ref updates, so exactly one tower wins the fence per unit
  and a rejected push means the unit is taken → select another. The fence is keyed by **unit id** and
  created by the **tower before the worker forks** (no worker death handle, no pre-fork-pid problem); it is
  a **dedicated-namespace** ref pushed by the tower under the canonical name **directly** (no worker branch,
  no dispatch-backend rename in the fencing path — the run-4 phantom is gone). A **cohesion bundle** is
  fenced with a single **`git push --atomic`** over every member unit-id, so any member already fenced by a
  peer rejects the whole push and the tower backs off the entire bundle (no unfenced non-lead member). A
  selection guard skips any unit whose fence ref exists. **`origin`-reachability classification (REQ-C1.6,
  D-10):** no-`origin` is the genuine no-remote single-host solo posture (dispatch without a fence); a
  transient push failure fails closed (do not dispatch this unit, surface, retry); a rejected CAS backs off
  the unit; the tower never `--force`s a fence it did not create. **Strand handling (REQ-C1.3, D-7) —
  surface, never auto-reclaim:** the discovery sweep attributes each `origin` fence ref to its owner via the
  presence surface's currently-fenced-unit field (Task 2); classification is **terminal-first, then
  liveness** — a **terminal** unit (merged PR / ledger-done) is GC'd regardless of owner liveness; else a
  fence whose owner is **live** is honored; a fence whose owner is **positively dead** and whose unit is
  **not terminal** (no merged PR, not ledger-done; a dead owner's **non-merged** artifact — task-branch
  commits or an **open, unmerged PR** — does **not** suppress the strand, since no live tower will carry it
  to merge; refs read live via `ls-remote`, PR merge state via `gh`; transient `origin` read fails closed),
  or that is unclassifiable (unknown/errored owner probe, unknown-owner orphan after a one-pass grace
  re-check, or reused-pid ambiguity), is **surfaced to the durable operator sink (REQ-C1.7), never
  auto-reclaimed** — reclaim is the operator's decision. **Fence GC (REQ-C1.5):** a fence whose unit is
  **terminal** (PR **merged** or ledger-done; an open, unmerged PR is **not** terminal) is deleted from
  `origin` on both the owning tower's completion path and the discovery sweep; the delete is **idempotent**
  (an already-absent ref is success), and a transient failure is surfaced and retried — so the fence
  namespace stays bounded with no machine-local residue GC. **The durable sink (REQ-C1.7):** surfaced
  strands and awareness anomalies land in a durable, **deduplicated** operator-facing entry delivered by
  **push** through `orchestration-fleet`'s attention surface (dedup key = fence-ref + owner for a strand,
  record id for an anomaly), each naming the unit, the dead/unknown owner, and a defined operator action
  (reclaim / investigate / dismiss); no checkout path or death handle leaks into a committed artifact
  (REQ-D1.4). The **fence-ref name and unit id** are grammar-validated and containment-checked to the
  `refs/planwright-fence/<spec>/` namespace before any push or delete (REQ-D1.5), so a crafted id can never
  drive a ref operation outside it. The mechanism composes with `orchestration-fleet`'s meta-tower selection
  where a meta-tower is present (distinguished by the presence record's own validated meta marker, REQ-A1.2),
  and only creates / reads / deletes fence refs and reads the presence surface — never mutating a peer's or
  worker's branch state.
- **Done when:** the **authoritative per-unit fence (REQ-C1.1, D-5, D-8, D-11)** is asserted against a
  **local bare-repo `origin` fixture** — two towers racing to fence one unit both attempt the expect-absent
  all-zeros CAS, exactly one succeeds and the loser backs off, yielding a **single dispatch including across
  separate clones**; a **cohesion-bundle** dispatch fences every member with `git push --atomic` and a peer
  selecting **any** member (lead or non-lead) collides and backs off the whole bundle (no unfenced member);
  the fence targets an existing commit and adds **no history to `main`** (asserted); the fence ref lives in
  the dedicated `refs/planwright-fence/<spec>/` namespace, pushed by canonical name with **no worker branch
  and no backend rename** in the fencing path (a fixture asserts the tower's fence push produces the canonical
  fence ref **independent of the dispatch backend** — the fence never passes through
  `fleet-dispatch-worktree.sh` or the `claude --worktree`/tmux path); **`origin`-reachability is
  classified** — no-`origin` dispatches solo without a fence, a rejected CAS backs off the unit, and a
  transient push failure fails closed (surface + retry, never dispatch blind, never `--force`); a fence
  whose **owner is live** is honored (while non-terminal), a fence whose **owner is positively dead and whose
  unit is not terminal** (no merged PR, not ledger-done — **including** one carrying only task-branch commits
  or an **open, unmerged PR**, since no live tower will carry it to merge) is **surfaced (not reclaimed)** to
  the durable sink, and a fence whose unit is **terminal** (a **merged** PR, read via `gh`, or ledger-done) is
  **GC'd**, not surfaced (fixtures for dead-owner+no-artifact → surface, dead-owner+commits-no-PR → surface,
  dead-owner+open-unmerged-PR → surface, dead-owner+merged-PR → GC/no-surface, unknown-owner orphan → surface
  after grace re-check); unclassifiable cases (unknown/errored owner probe, reused-pid ambiguity,
  unknown-owner orphan) are **surfaced, never silently honored and never auto-reclaimed** (REQ-C1.3);
  strand attribution resolves a fence's owner from the presence currently-fenced-unit field and falls back
  to unknown-owner when no live record lists the unit; the durable sink is **dedup'd** (the same strand on
  successive discovery passes is raised once, keyed by fence-ref + owner) and names a defined operator
  action, and no checkout path / death handle reaches a committed artifact; a **terminal** unit's fence is
  **GC'd idempotently** on both the completion path and the sweep (deleting an already-absent ref is
  success), a transient GC failure is surfaced-and-retried, and the fence namespace is shown bounded; a
  crafted unit/tower id cannot drive a ref push or delete outside `refs/planwright-fence/<spec>/`
  (containment asserted); the mechanism invokes **no LLM**, creates/reads/deletes only fence refs and reads
  presence, and never mutates a peer's or worker's branch state; the meta-tower-present path defers to
  meta-tower selection **via a fixture**; **and (REQ-C1.6 manual anchor, so it is not silently droppable) a
  dated entry in this task's verification notes records a two-clone run sharing one `origin` — the two tower
  identities, the single winning fence ref, and that only one worker/PR resulted — the task is not complete
  until that note exists**; the validator and CI pass. There is **no** machine-local claim,
  reclaim lock, under-lock re-read, four-residue GC, or quarantine to test — their absence is asserted
  (a grep/source check that no `claims/` sub-surface or reclaim-lock path is constructed).
- **Dependencies:** 2, 3
- **Citations:** D-4, D-5, D-7, D-8, D-11, D-12, D-13 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-D1.5
- **Estimated effort:** 2 days

### Task 5 — Coordination-artifact hygiene guard & cross-reference wiring

- **Deliverables:** The commit-independent core first — the framework-script security bars (REQ-D1.5, D-9)
  applied to the coordination scripts that parse records other sessions wrote: **every** parsed field
  grammar-validated before use — tower id, repository id, unit id, spec id, timestamps, the **meta-tower
  marker**, the **checkout path**, and the **death handle** (whose declared grammar is the two
  `fleet-death-evidence.sh` forms, `process <pid>` or `tmux-window <session> <window>`) — plus the **unit id
  and spec id validated before any `origin` fence-ref push or delete** — not only the tower token, never
  interpolated; **path and ref canonicalization + containment** on the surface directory itself (so a
  **surface-root symlink** cannot redirect it), every presence record path, the strand-sink path, and the
  **fence-ref name** (confirmed inside `refs/planwright-fence/<spec>/` before any push or delete), so a
  crafted id cannot drive a write, `mkdir`, unlink, or ref operation outside its bounds; the
  **echo-discipline sanitizer** (`scripts/echo-safety.sh`,
  `sanitize_printable`) on any untrusted record field echoed to a terminal or log; and the
  **data-not-code** discipline on peer records (no `eval` / unquoted-expansion path). Enforcement of the
  same-operator trust model at the surface: the coordination directory is created/verified **user-private**
  (`0700`, REQ-A1.4) with a pre-existing over-broad surface **refused, not reused**, and both a peer
  tower's machine-local **checkout path** *and* its **death handle** (pid, or tmux session+window name)
  are prevented from leaking from the surfaces into any committed artifact (a PR body, an audit log —
  REQ-D1.4). Plus a *conditional* hygiene guard that scans any coordination record a
  deployment does commit (a committed audit / handover log, or a summary of presence records that lands in
  git) for secrets, credentials, internal hostnames, checkout paths, and sensitive operational detail,
  wired into `mise run check` alongside the existing secret-scan of fleet artifacts — noting that
  presence records and the strand sink are normally machine-local and uncommitted, so the scan targets only what
  actually lands in git; and the cross-reference wiring into `orchestration-concurrency` (state-safety
  floor), `orchestration-fleet` (relay + meta-tower), and `fleet-autonomy` (usage-governance boundary) so
  the seams are legible.
- **Done when:** **every** parsed field is refused when malformed — validated against a declared grammar,
  never interpolated — asserted **per field** including the meta-tower marker, the checkout path, and the
  death handle (against its two `fleet-death-evidence.sh` forms), plus the **unit id validated before any
  fence-ref push or delete**; peer output consumed for awareness is treated as data (no `eval` /
  unquoted-expansion path); a crafted record path, strand-sink path, or **fence-ref name** that would escape
  its bounds is refused (canonicalized + containment-checked, **including against a surface-root symlink**,
  and the fence ref confirmed inside `refs/planwright-fence/<spec>/`), and an embedded escape sequence in a
  record field is
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
