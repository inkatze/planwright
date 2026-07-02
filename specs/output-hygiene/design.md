# Output & Accumulator Hygiene — Design

**Status:** Draft
**Last reviewed:** 2026-07-02
**Format-version:** 1

Five load-bearing decisions. The recurring shape they answer: an artifact was written for
the convenience of the process that emitted it, and the reader — human or tool, sometimes
weeks later, sometimes a concurrent run — pays for it. The recurring answers: one normative
home per contract; collision-free by construction rather than by etiquette; enforcement at
the moment the author can still act; derived content cited or regenerated, never
hand-copied.

## D-1: Observations recording via per-run fragment files with single-writer consolidation  (drafting-session decision (2026-07-02))

**Decision.** Sessions record observations as individual fragment files under
`specs/_observations/queue/`, one file per run (`<YYYY-MM-DD>-<slug>.md`, slug screened
against the reserved-accumulator name rule; append within a run, never across runs).
`opportunities.md` remains the canonical consolidated log and the only surface the archive
ritual touches. Consolidation — append fragment entries to the log in chronological order,
delete the consumed fragment files, one commit — is performed by a single writer on the
default branch: the `/orchestrate --bookkeeping` reconcile, and opportunistically
`/spec-draft` at mining time. Consolidation is idempotent and runs under the existing
advisory lock, so either actor may run it without coordination. The drain pass counts
queue entries plus unconsolidated log entries as the unmined surface.

**Alternatives considered.**

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

**Chosen because.** Distinct filenames make collisions impossible by construction rather
than by discipline; the single-file reader experience survives; the consolidation writer
mirrors the sole-writer pattern `orchestration-concurrency` proved for `tasks.md`
placement; and the pattern is proven at ecosystem scale by towncrier's news fragments
(CPython, attrs, PyInstaller, Prefect). The pattern is adopted, the tool is not — Claude
Code primitives only. Class-3 accumulator invariants (durable home, canonical reader,
drain surfacing, archive-on-consume) are preserved by keeping `opportunities.md`
canonical; the accumulator-taxonomy doctrine gains the queue as a named surface with its
class, reader, and drain ritual stated (REQ-B1.2).

## D-2: The PR-body contract has one normative home in gate-wiring  (drafting-session decision (2026-07-01))

**Decision.** The PR-body layout — human summary first (what / why / how to review, task
IDs, REQs, open pending-sign-off items), the complete audit record collapsed in a
`<details>` block, prose never hard-wrapped — is defined once, as a PR-body assembly
section in the gate-wiring doctrine (which already owns the audit-record formats).
`/execute-task` and `/self-review` cite that section instead of carrying their own copies.

**Alternatives considered.**

- *Per-skill emission instructions.* Rejected: one rule in N copies drifting is the
  failure shape half this spec's seed observations document.
- *A body-rendering script.* Rejected: machinery disproportionate to prose assembly; the
  contract is judgment-applied by the emitting skill, not template-expanded.

**Chosen because.** A single normative home makes the contract enforceable by citation
and updateable in one place; gate-wiring is where the audit record is already defined, so
the collapse rule sits next to the thing it collapses. This is a general capability (every
adopter's PR readers benefit; GitHub reflows markdown for everyone), not a personal style,
so it lands in core per the customization boundary. It is also another instance of the
uncatalogued human-comprehension / information-UX decision domain (observations log
2026-06-16 catalog-gap entry, left unconsumed for the catalog's own amendment).

## D-3: Marker canonical placement end-of-subject; enforcement at emit time; branch-scoped consumption  (drafting-session decision (2026-07-02))

**Decision.** The canonical `[pending-sign-off]` placement is the end of the subject:
`type(scope): description [pending-sign-off]`. Enforcement is emit-time: any skill writing
a marked commit validates the subject before committing — `check-commit-msgs.sh --stdin`
plus a marker-position check, implemented once as a `--marker` mode of that script. The
CI commit-range lint is unchanged. The marker is branch-scoped (REQ-C1.4): it must not
appear in the PR title (the squash subject — the PR-title lint path rejects it there,
safely, since titles are editable), and marker consumers scan only the PR branch range.

**Merge-strategy matrix.** Squash (the sanctioned flow): the title must be marker-free;
GitHub concatenates branch subjects into the squash commit body, so mainline history will
carry relic marker text — which is why consumers never scan mainline (the same relocation
that moved the `Planwright-Task` trailer mid-body, observations log 2026-07-01).
Merge-commit: marked subjects persist as ancestor history — an accurate record; the merge
subject itself is clean. Rebase-merge: would land marked subjects on the mainline
directly, but rebase is forbidden framework-wide; excluded by invariant rather than
handled.

**Alternatives considered.**

- *Enforce placement in the CI commit-range lint.* Rejected: recreates the exact
  unfixable-red trap being fixed — a historical commit with a mid-subject marker would
  redden the PR forever (history rewrites forbidden), violating REQ-C1.3.
- *A git pre-commit hook.* Rejected: the repo ships no git-hook framework (observations
  log 2026-06-28 notes the absence); introducing one for a single rule is
  disproportionate.
- *Placement-agnostic doctrine (relax the wording).* Rejected: leaves the pre-prefix trap
  live and keeps marker tooling grep-fragile.

**Chosen because.** End-of-subject matches the gate-wiring doctrine's existing wording and
majority practice; keeping the type prefix first means the conventional lint passes by
construction; emit-time self-linting catches the error while the author can still reword;
and a single `--marker` implementation avoids minting one more rule-in-N-copies.

## D-4: Reference integrity by restriction-plus-lint, not delivered-layout modeling  (drafting-session decision (2026-07-02))

**Decision.** Two rules, both mechanically guarded. (1) Doctrine files may markdown-link
only targets that ship beside them in every delivery mode — sibling doctrine docs and
`../config/` — and reference everything else by resolution path in backticks;
`check-doc-links.sh` enforces the restriction (flagging other relative links leaving
`doctrine/`). (2) `/spec-draft` gains a completion-step neutralization: any `[[name]]`
memory link in would-be-committed prose is rewritten to plain prose plus a `## Sources`
entry; the existing Source citation kind covers observations-log references, so no new
syntax is minted. Known violations are reconciled: the guard-catalog delivered-dead link
directly, the orchestration-fleet `[[…]]` citations via the expression-only amendment
ritual on that bundle (changelog entry plus re-anchor — it is signed off).

**Alternatives considered.**

- *Teach the link checker the full delivered-layout map.* More faithful, more machinery;
  deferrable — the restriction covers today's violation class with a fraction of the
  logic. Revisit if the delivery matrix grows.
- *Document-only convention.* Rejected: the convention already existed informally and
  observations log 2026-06-16 records it not holding.

**Chosen because.** The guard is cheap, the rule is teachable in one sentence, and both
halves fail loudly at authoring time instead of surfacing as a dead link in an adopter's
install.

## D-5: Derived content — organic owners and cite-don't-copy  (drafting-session decision (2026-07-02))

**Decision.** Three applications of one principle (REQ-E1.1: derived content is cited or
regenerated, never hand-copied without a named refresh owner).

1. *Completion annotations:* the level-triggered reconcile stamps
   `Completed · PR #<n> merged <YYYY-MM-DD>` in the same write that places a task in
   `## Completed`, reusing the merged-PR evidence batch the derivation already fetched —
   no new per-task lookups. Freshness is organic: every trigger of the reconcile (the
   `tasks-pr-sync` hook on PR events, `/orchestrate` steps, `--bookkeeping`) stamps as a
   side effect, so no scheduled pass has to be remembered. With no remote configured the
   stamp degrades honestly — date-only from branch evidence, or leave the annotation
   untouched; never an invented PR number. This narrowly supersedes
   `orchestration-concurrency` REQ-B1.1's annotations-preserved-byte-for-byte clause
   (placement plus the Status annotation of a completion-evidenced task, nothing else);
   that bundle is Done, so the supersede-pointer ritual applies — annotate the old
   decision with a `Superseded-by:` pointer to this D-ID, never editing its prose.
2. *Brief derived stats:* convention, not checker — kickoff-brief sections cite the source
   file or section for tallies and field lists instead of copying them; a recompute
   validator is deferred as disproportionate.
3. *Dependency graphs:* authoring guidance drops hand-drawn graphs from `tasks.md`;
   `Dependencies:` lines are the sole source of truth and the graph view
   (`scripts/spec-graph.sh`) renders them on demand.

**Alternatives considered.**

- *`--bookkeeping`-only stamping.* Rejected as the owner: it reintroduces a
  remember-to-run duty; retained as one trigger among several.
- *Merge-event hook refresh.* Rejected as the sole owner: merges commonly happen on the
  GitHub UI where no local hook fires; the level-triggered reconcile sees them regardless.
- *A brief-stat recompute checker.* Deferred: machinery disproportionate to the observed
  drift rate; the cite-don't-copy convention removes the copied figure entirely.
- *Generate the ASCII graph into `tasks.md`.* Rejected: a second committed rendering of
  the same truth is one more derived artifact to keep fresh; the on-demand view already
  exists.

**Chosen because.** Each derived surface gets the cheapest owner that requires no memory:
a write that rides an existing trigger, a convention that removes the copy, or deletion of
the redundant rendering.

## Cross-cutting notes

- **Decision-domains catalog walk (merged core + overlays, ten domains).** Touched and
  decided: data-storage (D-1 layout), concurrency (D-1 single writer), api-surface
  (D-1/D-2 consumed surfaces), observability (drain semantics preserved, REQ-B1.4).
  Explicitly declined: dependency-adoption — the news-fragment pattern is borrowed, no
  tool is added. Untouched: caching, queues-async, auth, secrets-config,
  deploy-migration.
- **Data hygiene.** Fragment files, PR bodies, and archived observation copies are
  committed artifacts: no secrets, credentials, internal hostnames, or sensitive
  operational detail; fragment consolidation and archive-on-consume re-screen entry text
  on the boundary (bootstrap REQ-D1.6 posture).
- **Concurrent-edit note for this bundle's own PR.** The extracted esc-consolidation chore
  annotates three `opportunities.md` entries this spec leaves unconsumed; this branch
  trims nine others. One entry pair is hunk-adjacent, so whichever PR merges second
  resolves a small conflict — accepted, and itself a live demonstration of REQ-B1.1's
  problem class.
