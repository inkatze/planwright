# Output & Accumulator Hygiene — Design

**Status:** Ready
**Last reviewed:** 2026-07-07
**Format-version:** 1

Five load-bearing decisions. The recurring shape they answer: an artifact was written for
the convenience of the process that emitted it, and the reader — human or tool, sometimes
weeks later, sometimes a concurrent run — pays for it. The recurring answers: one normative
home per contract; collision-free by construction rather than by etiquette; enforcement at
the moment the author can still act; derived content cited or regenerated, never
hand-copied.

## Decision log

### D-1: Observations recording — per-run fragment files, `opportunities.md` mutated by a single writer (the reconcile)  (drafting-session decision (2026-07-02); reworked at kickoff §Cluster-1 2026-07-07; single-writer-total redesign at 2nd delta re-walkthrough 2026-07-07 after the panel pass)

**Decision:** Sessions record observations as individual fragment files under
`specs/_observations/queue/`, **one file per run**, named `<YYYY-MM-DD>-<taskid>-<run-nonce>.md`.
The `<taskid>` prefix is the run's task/branch id (readable and traceable to the writing
run); `<run-nonce>` is a run-unique token chosen **once at run start** — a stable
run/dispatch id where one exists, otherwise a short random token. All of a run's
observations append to that one file; two distinct runs on the same task and date (a retry,
or a separately-invoked `/self-review`) draw different nonces, so they cannot collide on or
clobber each other's fragment. Both slug components are validated against their declared
charsets (task-id grammar; the nonce against `^[a-z0-9]+$`) **before** the name is
interpolated into a path, and the derived path is containment-checked after
canonicalization (REQ-B1.5) — hostile input is a clean refusal, never a path.

**The load-bearing invariant: `opportunities.md` has exactly one writer — the reconcile**
(second delta re-walkthrough, 2026-07-07, replacing the union/regenerate model that the
panel pass showed unsound). *Every* mutation of the log — appending newly recorded
observations **and** archiving/trimming consumed ones — is performed only by the
`/orchestrate --bookkeeping` reconcile on the default branch. No other skill, run, or branch
writes `opportunities.md`. This makes the log's no-loss guarantee (REQ-B1.3) hold **by
construction** (a single serial writer never races itself), rather than by any merge-time
resolution rule.

- **Record** (concurrent, any branch): a skill **drops a queue fragment** (distinct
  `<date>-<taskid>-<run-nonce>` filename — REQ-B1.5) and **never touches `opportunities.md`**.
  Distinct filenames make the write side collision-free by construction; a feature-branch
  merge therefore never conflicts on the log (this is exactly what would have prevented the
  #124 conflict — the direct appends every recording skill does today become fragment drops,
  Task 2).
- **Consolidate** (reconcile only): **one atomic commit** appends the queued fragments'
  entries to `opportunities.md` in filename-sorted order and deletes the consumed fragments.
  Idempotency is by **fragment presence**: the single serial writer consolidates a fragment
  exactly once (delete-after-consolidate), so a crash-retry is a no-op — no embedded
  fragment-ids or dedup ledger are needed in the sanctioned single-writer flow. Each entry
  carries its own date in its text; entries are never re-sorted by date.
- **Archive / consume** (the panel-F2/F4 fix): `/spec-draft`, when it consumes observations
  into a new bundle, **records which entries it consumed** (a consumption marker) rather than
  editing the log; the **reconcile** performs the archive-move (to `archive.md`) + trim on the
  default branch. So `/spec-draft` never writes `opportunities.md` on its feature branch.
- **Conflict on `opportunities.md`** signals a **violated invariant** (a stray direct-writer,
  or two reconcile actors across checkouts) — it does not happen in the sanctioned flow. It is
  therefore **never auto-resolved by union** (which would resurrect archived deletions — the
  panel finding) **nor by blind regenerate** (the log has no external source). The reconcile
  **rebuilds the log from its authoritative components** — `committed log ∪ unconsolidated
  queue − recorded-archived-set` — which respects deletions, or **fails loud** for a human if
  the components cannot reconcile. The **global `_observations` advisory lock** serializes
  reconcile runs (so it is now a correctness serializer, not merely a perf guard); cross-
  checkout reconcile is the only residual concurrency, and if it is ever enabled the rebuild
  keys on fragment identity — a bounded, named extension, not a load-bearing requirement here.

**Mining reads the consolidated log plus a read-only queue preview** (the panel-F3 fix):
`/spec-draft` (the canonical reader) mines and archives from the consolidated log
(`opportunities.md`), and **additionally reads the queue read-only** so observations recorded
on the current branch but not yet consolidated are still visible to the drafter (no
blind-spot). Consumption/archival always routes through the reconcile (via the consumption
marker), so a fragment is never both mined-raw and re-consolidated (no double-surface). The
drain pass still counts queue entries (plus unconsolidated log entries) in the unmined-surface
figures.

**Alternatives considered:**

- *`.gitattributes merge=union` on the log.* Rejected on research: GitHub does not honor
  merge drivers — including built-in union — on PR merges (GitHub community discussion
  9288), which is exactly where our collisions occur; kubernetes removed their union
  driver for this reason (kubernetes/kubernetes PR 70576). The driver would fix only
  local merges.
- *Directory as the permanent log (no consolidation).* Rejected: converts every reader
  (drain surface, mining, archive ritual, human chronological reading) to a
  multi-file walk, for no gain over consolidate-on-a-single-writer.
- *Status quo plus worker merge etiquette.* Rejected: the union-merge self-sync ritual
  (observations log 2026-06-12) is the etiquette that kept failing under real concurrency.
- *Two consolidation writers (`/spec-draft` + reconcile) coordinated by a lock.* Rejected
  at kickoff (§Cluster-1): `/spec-draft` runs in a feature-branch worktree, so consolidating
  there rides that branch's PR and collides at squash-merge — the very problem D-1 exists to
  kill — and the per-spec advisory-lock primitive cannot even key on `_observations`
  (leading-underscore names fail its charset). Consolidation must be a default-branch
  operation, so the reconcile is the only sound writer.
- *Chronological-by-fragment-date ordering.* Rejected: sub-day fragments carry no time key,
  and inserting a late, earlier-dated fragment ahead of existing entries would rewrite
  committed content (violates REQ-B1.3). Append-in-consolidation-order is monotonic and
  reorder-free.
- *Task-id-only fragment name (the initial kickoff §3 choice).* Rejected once the lens pass
  showed branch/task id is not run-unique (a retry or a separate same-branch run collides);
  the per-run nonce closes that hole while keeping the readable task-id prefix.
- *Regenerate-from-current-state on conflict (mirroring `tasks.md`).* Rejected: `tasks.md` is
  a derived read-model; `opportunities.md` is a durable accumulator with no source to
  regenerate from, so regenerate would **delete** entries on conflict (REQ-B1.3).
- *Union-of-appends on conflict (the first delta's fix).* Rejected on the panel pass (2nd
  delta): the log is **not** append-only — the archive-on-consume ritual **deletes** consumed
  entries — so "union (keep every entry from both sides)" would **resurrect archived
  deletions**. Union is only correct for a pure-append log; this log has deletes.
- *Content-based / fragment-id idempotency at merge.* Rejected: both presuppose concurrent
  writers to `opportunities.md`. The redesign removes concurrent writers entirely (single-writer
  invariant), so idempotency is by fragment-presence in a serial writer — no dedup at merge
  is needed in the sanctioned flow.
- *`/spec-draft` writes the log (mines the raw queue, or trims on its branch).* Rejected: any
  feature-branch write to `opportunities.md` reintroduces the collision. `/spec-draft` records
  a consumption marker and previews the queue read-only; the reconcile owns every log write.

**Chosen because:** the real defect was that `opportunities.md` had **many writers on many
branches** — appends by every recording skill *and* deletes by `/spec-draft`'s archive ritual
— which no merge-time rule (union or regenerate) can reconcile correctly (union resurrects
deletes; regenerate has no source). Making the log **single-writer for every mutation** (the
reconcile) removes concurrent writes at the root, so no-loss holds by construction and there is
no conflict to resolve in the sanctioned flow — the honest fallback for a *violated* invariant
is rebuild-from-components (respecting deletions) or fail-loud, never a silently-wrong auto-merge.
Distinct per-run fragment filenames keep the **record** side collision-free; the reconcile
mirrors `orchestration-concurrency`'s sole-writer discipline (here applied to *all* log
mutation, appends and deletes alike); and the fragment pattern is
proven at ecosystem scale by towncrier's news fragments (CPython, attrs, PyInstaller,
Prefect) — the pattern is adopted, the tool is not (Claude Code primitives only). The
accumulator-taxonomy doctrine gains the queue as a named class-3 surface with its durable
home, canonical reader (`/spec-draft`), and drain ritual stated (REQ-B1.2);
archive-on-consume remains the *observations log's* specific ritual, preserved by keeping
`opportunities.md` canonical, not asserted as a universal class-3 invariant.

### D-2: The PR-body contract has one normative home in gate-wiring  (drafting-session decision (2026-07-01))

**Decision:** The PR-body layout — human summary first (what / why / how to review, task
IDs, REQs, open pending-sign-off items), the complete audit record collapsed in a
`<details>` block, prose never hard-wrapped — is defined once, as a PR-body assembly
section in the gate-wiring doctrine (which already owns the audit-record formats).
`/execute-task` and `/self-review` cite that section instead of carrying their own copies.

**Alternatives considered:**

- *Per-skill emission instructions.* Rejected: one rule in N copies drifting is the
  failure shape half this spec's seed observations document.
- *A body-rendering script.* Rejected: machinery disproportionate to prose assembly; the
  contract is judgment-applied by the emitting skill, not template-expanded.

**Chosen because:** A single normative home makes the contract enforceable by citation
and updateable in one place; gate-wiring is where the audit record is already defined, so
the collapse rule sits next to the thing it collapses. This is a general capability (every
adopter's PR readers benefit; GitHub reflows markdown for everyone), not a personal style,
so it lands in core per the customization boundary. It is also another instance of the
uncatalogued human-comprehension / information-UX decision domain (observations log
2026-06-16 (catalog-gap) (Sources), left unconsumed for the catalog's own amendment).

### D-3: Marker canonical placement end-of-subject; enforcement at emit time; branch-scoped consumption  (drafting-session decision (2026-07-02))

**Decision:** The canonical `[pending-sign-off]` placement is the end of the subject:
`type(scope): description [pending-sign-off]`. Enforcement is emit-time: any skill writing
a marked commit validates the subject before committing — `check-commit-msgs.sh --stdin`
plus a marker-position check, implemented once as a `--marker` mode of that script. The
mode takes the check target as context: on a **commit subject** (the emit-time `--stdin`
path) it *requires* the canonical end-of-subject placement (pre-prefix and mid-subject
fail); on a **PR title** it *rejects any* marker (titles are the squash subject and must be
marker-free). The CI commit-range lint is unchanged. The marker is branch-scoped (REQ-C1.4):
it must not appear in the PR title (the PR-title lint path rejects it there, safely, since
titles are editable), and marker consumers — the pending-sign-off checklist regeneration
(gate-wiring), which rebuilds from `[pending-sign-off]` commits ahead of the base and
already excludes merged-base relics — scan only the PR branch range.

**Merge-strategy matrix.** Squash (the sanctioned flow): the title must be marker-free;
GitHub concatenates branch subjects into the squash commit body, so mainline history will
carry relic marker text — which is why consumers never scan mainline (the same relocation
that moved the `Planwright-Task` trailer mid-body, observations log 2026-07-01).
Merge-commit: marked subjects persist as ancestor history — an accurate record; the merge
subject itself is clean. Rebase-merge: would land marked subjects on the mainline
directly, but rebase is forbidden framework-wide; excluded by invariant rather than
handled.

**Alternatives considered:**

- *Enforce placement in the CI commit-range lint.* Rejected: recreates the exact
  unfixable-red trap being fixed — a historical commit with a mid-subject marker would
  redden the PR forever (history rewrites forbidden), violating REQ-C1.3.
- *A git pre-commit hook.* Rejected: the repo ships no git-hook framework (observations
  log 2026-06-28 notes the absence); introducing one for a single rule is
  disproportionate.
- *Placement-agnostic doctrine (relax the wording).* Rejected: leaves the pre-prefix trap
  live and keeps marker tooling grep-fragile.

**Chosen because:** End-of-subject matches the gate-wiring doctrine's existing wording and
majority practice; keeping the type prefix first means the conventional lint passes by
construction; emit-time self-linting catches the error while the author can still reword;
and a single `--marker` implementation avoids minting one more rule-in-N-copies.

### D-4: Reference integrity by restriction-plus-lint, not delivered-layout modeling  (drafting-session decision (2026-07-02))

**Decision:** Two rules, both mechanically guarded. (1) Doctrine files may markdown-link
only targets that ship beside them in every delivery mode — sibling doctrine docs,
`../config/`, and `../scripts/` (all three are co-located under `<root>/planwright/` in
both the plugin layout and the writer-install layout, verified against `install.sh`) — and
reference everything else by resolution path in backticks; `check-doc-links.sh` enforces
the restriction (flagging other relative links leaving `doctrine/`, e.g. the `../skills/`
link, which does not ship as a doctrine sibling in writer-install). (2) `/spec-draft` gains
a completion-step neutralization: any `[[name]]` memory link in would-be-committed prose is
rewritten to plain prose plus a `## Sources` entry; the existing Source citation kind covers
observations-log references, so no new syntax is minted. A mechanical guard backs the rule
so it does not rot: `check-doc-links.sh` (or a sibling `check:*` under `mise run check`)
also flags any `[[name]]` token in a committed spec file **or `kickoff-brief.md`** (kickoff
§delta F5), so a future `/spec-draft` or `/spec-kickoff` that skips its neutralization step
fails CI rather than silently reintroducing the violation. The guard carries a **named
allowlist carve-out** for the pre-existing declined orchestration-fleet brief links, so it
fails on a *new* regression without reopening an already-signed brief's accepted exceptions.
Known violations are reconciled: the guard-catalog delivered-dead link directly, the
orchestration-fleet `[[…]]` citations in that bundle's **spec files** via the expression-only
amendment ritual (changelog entry plus re-anchor — it is signed off).

**Alternatives considered:**

- *Teach the link checker the full delivered-layout map.* More faithful, more machinery;
  deferrable — the restriction covers today's violation class with a fraction of the
  logic. Revisit if the delivery matrix grows.
- *Document-only convention.* Rejected: the convention already existed informally and
  observations log 2026-06-16 records it not holding.
- *`[[name]]` neutralization as a skill step only, no mechanical guard.* Rejected at
  kickoff (§Cluster-4): a behavioral-only rule has no standing reader, so the next skipped
  neutralization silently reintroduces the violation — the exact write-only-deferral the
  accumulator doctrine forbids.

**Chosen because:** The guard is cheap, the rule is teachable in one sentence, and both
halves fail loudly at authoring time (or in CI) instead of surfacing as a dead link — or a
reintroduced `[[name]]` — in an adopter's install.

### D-5: Derived content — organic owners and cite-don't-copy  (drafting-session decision (2026-07-02))

**Decision:** Three applications of one principle (REQ-E1.1: derived content is cited or
regenerated, never hand-copied without a named refresh owner).

1. *Completion annotations:* the level-triggered reconcile stamps the canonical
   `Completed · PR #<n> merged <YYYY-MM-DD>` in the same write that places a task in
   `## Completed`, reusing the merged-PR evidence batch the derivation already fetched —
   no new per-task lookups. Freshness is organic: every trigger of the reconcile (the
   `tasks-pr-sync` hook on PR events, `/orchestrate` steps, `--bookkeeping`) stamps as a
   side effect, so no scheduled pass has to be remembered. With no remote configured the
   stamp degrades to the pinned date-only form `Completed · merged <YYYY-MM-DD>` (from
   branch evidence), or leaves the annotation untouched when even the date is unknown;
   never an invented PR number, and never a third free-form variant (the two degradation
   outputs are exactly these, so no two-styles drift can reappear). This is **additive to,
   not a supersession of,** `orchestration-concurrency`'s contract (kickoff §4 finding,
   2026-07-06): the anchor-stability guarantee that the five task-**definition** fields move
   byte-for-byte lives in the content-anchor doctrine (`spec-format.md`) and is realized by
   the `tasks-pr-sync.sh` implementation — not in the text of `orchestration-concurrency`
   REQ-B1.1 (which is sole-writer-of-placement plus atomic write). The completion annotation
   is an **unowned gap** (observations log 2026-06-29: "nobody refreshes completion
   annotations"), not an existing owner to override, and stamping it touches no definition
   field, so the anchor is unchanged and **no cross-bundle `Superseded-by:` pointer is
   written**. The one stale artifact to correct is the `tasks-pr-sync.sh` implementation
   comment that attributes annotation authoring to `/execute-task`; Task 7 updates that
   comment as part of its own delivery, with no edit to the Done bundle's spec files.
2. *Brief derived stats:* convention, not checker — kickoff-brief sections cite the source
   file or section for tallies and field lists instead of copying them; a recompute
   validator is deferred as disproportionate.
3. *Dependency graphs:* authoring guidance drops hand-drawn graphs from `tasks.md`;
   `Dependencies:` lines are the sole source of truth and the graph view
   (`scripts/spec-graph.sh`) renders them on demand.

**Alternatives considered:**

- *`--bookkeeping`-only stamping.* Rejected as the owner: it reintroduces a
  remember-to-run duty; retained as one trigger among several.
- *Merge-event hook refresh.* Rejected as the sole owner: merges commonly happen on the
  GitHub UI where no local hook fires; the level-triggered reconcile sees them regardless.
- *A brief-stat recompute checker.* Deferred: machinery disproportionate to the observed
  drift rate; the cite-don't-copy convention removes the copied figure entirely.
- *Generate the ASCII graph into `tasks.md`.* Rejected: a second committed rendering of
  the same truth is one more derived artifact to keep fresh; the on-demand view already
  exists.

**Chosen because:** Each derived surface gets the cheapest owner that requires no memory:
a write that rides an existing trigger, a convention that removes the copy, or deletion of
the redundant rendering.

## Cross-cutting concerns

- **Decision-domains catalog walk (merged core + overlays, ten domains).** Touched and
  decided: data-storage (D-1 layout), concurrency (D-1 single-writer + idempotent-regenerate
  + global lock), queues-async (D-1 consolidation idempotency, ordering, and crash safety —
  a staging drop-dir, not an async job queue), api-surface (D-1/D-2 consumed surfaces),
  observability (drain semantics preserved, REQ-B1.4), secrets-config (data-hygiene
  screening + the REQ-B1.5 hostile-name / containment rule). Explicitly declined:
  dependency-adoption — the news-fragment pattern is borrowed, no tool is added. Untouched:
  caching, auth, deploy-migration. Catalog gap (routed to an observation, not decided here):
  the human-comprehension / information-UX domain has no catalog entry (D-2).
- **Data hygiene.** Fragment files, PR bodies, and archived observation copies are
  committed artifacts: no secrets, credentials, internal hostnames, or sensitive
  operational detail. Entry text is screened **at write time** by the recording skill
  (bootstrap REQ-D1.6 posture — the human-applied write-time rule); consolidation and
  archive-on-consume move entries **verbatim** and do not redact them (that would violate
  REQ-B1.3's never-rewritten guarantee), so the only screening boundary is the write. Slug
  and branch-derived names echoed into the drain report or consolidation output are passed
  through `sanitize_printable` (`scripts/echo-safety.sh`) first (REQ-B1.5).
- **Concurrent-edit note for this bundle's own PR.** The extracted esc-consolidation chore
  annotates three `opportunities.md` entries this spec leaves unconsumed; this branch
  trims nine others. One entry pair is hunk-adjacent, so whichever PR merges second
  resolves a small conflict — accepted, and itself a live demonstration of the collision
  class D-1 addresses. (The fragment queue removes *new-observation append* contention; the
  consolidation, archive, and trim writes to `opportunities.md` are all funneled through the
  **single reconcile writer** (2nd delta redesign), so they never race — "collision-free by
  construction" covers the record side (distinct fragments) and the mutation side (one writer),
  leaving only a *violated-invariant* conflict, which fails loud rather than auto-merging.)
