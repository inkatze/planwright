# Output & Accumulator Hygiene — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-02
**Format-version:** 1

## Goal

planwright's pipeline emits artifacts that humans and tools consume downstream — PR bodies,
commit subjects, committed spec prose, generated views — and accumulates shared state across
concurrent runs — the observations log, `tasks.md` annotations. Today several outputs are
optimized for the machine that writes them rather than the reader (PR bodies dump the full
audit record flat and hard-wrapped to a column GitHub reflows anyway), and the accumulators
collide or drift under fleet concurrency: every concurrent PR fights over the observations
log's single append point at GitHub merge time, ledger annotations go stale with no named
refresh owner, and a mis-placed `[pending-sign-off]` commit-subject marker can redden CI
permanently (history rewrites are forbidden, so a bad subject in the PR range cannot be
fixed). This spec makes every generated output human-first and every shared accumulator
conflict-free and format-stable under concurrent runs.

## Scope

### In scope

- **A human-first PR-body contract** for `/execute-task` and `/self-review`: concise summary
  first, the full audit record collapsed, prose not hard-wrapped, one normative home.
- **Conflict-free observations recording**: concurrent runs record observations without
  colliding on a shared textual append point, preserving the accumulator-taxonomy class-3
  invariants (durable home, canonical reader, drain surfacing, archive-on-consume).
- **Pending-sign-off marker canonicalization**: one placement, defined in doctrine, emitted
  by skills, guarded at a moment the author can still fix it, branch-scoped for consumers.
- **Committed-reference integrity**: no reference in a committed or delivered artifact that
  its intended reader cannot resolve (machine-local `[[name]]` links, links dead in the
  delivered layout), with a mechanical guard.
- **Derived-content hygiene**: derivable content in committed artifacts is cited or
  regenerated, never hand-copied without a named refresh owner (completion annotations,
  brief-embedded stats, hand-drawn dependency graphs).

### Out of scope

- **Cross-repo / multi-target observation routing.** The multi-source, multi-target
  accumulator design (observations log 2026-06-17, deliberately deferred by its author)
  is a separate effort; this spec fixes intra-repo recording only.
- **Input-side parser consolidation.** The spec-parse and scope-grammar duplication
  entries (2026-06-17, 2026-06-18) are shared-library concerns, not output hygiene.
- **Fleet attention surfaces.** How a human watches running work is `orchestration-fleet`'s
  seam; this spec governs what the pipeline writes down, not what it displays live.
- **Retroactive fixes to already-merged PR bodies.** The contract applies from adoption
  forward; history is never rewritten.
- **The `tasks.md` placement derivation.** `orchestration-concurrency`'s derived-state
  contract is consumed as-is; this spec touches only the annotation layer it deliberately
  left unowned (with one narrow, pointered supersession — see D-5).
- **The escaper/sanitizer consolidation.** Extracted to a standalone chore
  (`chore/esc-consolidation`, 2026-07-02) before drafting; the related log entries resolve
  there.

## REQ-A — Human-first PR bodies

- **REQ-A1.1** PR bodies emitted by `/execute-task` and `/self-review` SHALL lead with a
  concise human summary: what changed, why, how to review, the task IDs, the REQs
  satisfied, and open pending-sign-off items.
  *(Cites: the drafting invocation (Sources); D-2.)*
- **REQ-A1.2** The full audit record SHALL remain in the body, complete, but collapsed
  (a `<details>` block or equivalent) so it never buries the summary; no audit content is
  dropped relative to the pre-existing contract.
  *(Cites: the drafting invocation (Sources); D-2.)*
- **REQ-A1.3** Generated PR-body prose SHALL NOT be hard-wrapped to a fixed column; line
  breaks appear only where markdown is structural (lists, tables, code fences).
  *(Cites: the drafting invocation (Sources); D-2.)*
- **REQ-A1.4** The contract SHALL hold on body updates as on creation, and its normative
  home SHALL be a single shared definition the emitting skills cite rather than copy.
  *(Cites: D-2; drafting-session decision (2026-07-01).)*

## REQ-B — Conflict-free observations recording

- **REQ-B1.1** Concurrent runs SHALL be able to record observations without colliding on a
  shared textual append point.
  *(Cites: the drafting invocation (Sources); research: GitHub merge-driver support
  (Sources); D-1.)*
- **REQ-B1.2** The recording mechanism SHALL preserve the accumulator-taxonomy class-3
  invariants: a durable home, the canonical reader (`/spec-draft`), drain-pass surfacing
  (unmined count and oldest age), and the archive-on-consume ritual.
  *(Cites: observations log 2026-06-12 (archive-ritual home) (Sources); D-1.)*
- **REQ-B1.3** Existing log entries SHALL never be lost, reordered, or rewrapped by the
  mechanism's merges or consolidation.
  *(Cites: D-1.)*
- **REQ-B1.4** The existing consumers (the drain pass's observation surface, `/spec-draft`
  mining and archive trim) SHALL read the new layout with unchanged reported semantics.
  *(Cites: D-1; accumulator-taxonomy doctrine (Sources).)*

## REQ-C — Pending-sign-off marker canonicalization

- **REQ-C1.1** One canonical marker placement SHALL be defined in the gate-wiring doctrine,
  and it SHALL be a placement that passes the conventional-commit lint (a marker before the
  `type(scope):` prefix is the confirmed unfixable-CI-red trap).
  *(Cites: observations log 2026-06-29 (marker placement) (Sources); D-3.)*
- **REQ-C1.2** Every skill that writes the marker SHALL emit the canonical placement.
  *(Cites: D-3.)*
- **REQ-C1.3** A guard SHALL catch non-canonical placement at a moment the author can still
  fix it; enforcement SHALL NOT create a new unfixable-red class for commits already made
  (no new placement rule over the CI commit range).
  *(Cites: D-3; drafting-session decision (2026-07-01).)*
- **REQ-C1.4** The marker SHALL be branch-scoped: it SHALL NOT appear in the PR title (the
  squash-merge subject), and marker-consuming tooling SHALL scan only the PR branch range,
  never merged mainline history, because squash merges relocate branch subjects into the
  merge commit body as relic text.
  *(Cites: D-3; observations log 2026-07-01 (trailer squash relocation) (Sources);
  drafting-session decision (2026-07-02).)*

## REQ-D — Committed-reference integrity

- **REQ-D1.1** Committed artifacts SHALL NOT carry references their intended readers cannot
  resolve — machine-local `[[name]]` memory links, or links dead in the delivered
  (writer-install or plugin) layout.
  *(Cites: observations log 2026-06-29 ([[name]] links) (Sources); observations log
  2026-06-16 (delivered-layout links) (Sources); D-4.)*
- **REQ-D1.2** `/spec-draft` and kickoff-brief writers SHALL neutralize `[[name]]` links
  into plain prose plus a `## Sources` pointer before commit; the sanctioned citation form
  for an observations-log entry is a Sources entry naming the log line.
  *(Cites: D-4.)*
- **REQ-D1.3** Cross-tree documentation references SHALL follow a convention valid in every
  delivery mode, and the link checker SHALL enforce that convention mechanically rather
  than validating the in-repo layout alone.
  *(Cites: observations log 2026-06-16 (delivered-layout links) (Sources); observations log
  2026-06-12 (resolution-path-only rule) (Sources); D-4.)*
- **REQ-D1.4** The known existing violations (the guard-catalog delivered-dead link, the
  orchestration-fleet `[[…]]` citations) SHALL be reconciled, the latter via the
  expression-only amendment ritual on that bundle.
  *(Cites: D-4.)*

## REQ-E — Derived-content hygiene

- **REQ-E1.1** Derivable content in committed artifacts SHALL be cited or regenerated,
  never hand-copied without a named refresh owner.
  *(Cites: D-5; observations log 2026-06-17 (brief derived-stat drift) (Sources).)*
- **REQ-E1.2** Completion annotations in `tasks.md` SHALL have one canonical format
  (`Completed · PR #<n> merged <YYYY-MM-DD>`) and a named organic refresh owner: the
  level-triggered reconcile stamps the annotation in the same write that places a task in
  `## Completed` when merged-PR evidence is in hand, degrading honestly when no remote is
  configured (date-only from branch evidence, or leave the annotation untouched — never an
  invented PR number).
  *(Cites: observations log 2026-06-29 (annotation ownership) (Sources); observations log
  2026-06-28 (annotation drift) (Sources); D-5.)*
- **REQ-E1.3** Kickoff-brief sections SHALL cite derived figures' source files or sections
  rather than copying tallies (convention; a recompute checker is deferred as
  disproportionate).
  *(Cites: observations log 2026-06-17 (brief derived-stat drift) (Sources); D-5.)*
- **REQ-E1.4** Authoring guidance SHALL drop hand-drawn dependency graphs from `tasks.md`:
  `Dependencies:` lines are the sole source of truth and the graph view renders them.
  *(Cites: observations log 2026-06-10 (graph drift) (Sources); D-5.)*

## Changelog

- 2026-07-02 — Initial Draft bundle elicited via `/spec-draft`. Fold-detection: new spec
  (orchestration-fleet's approachability facet is the live attention seam and defers the
  accumulator redesign; D-21 spin-new triggers fire). The escaper/sanitizer consolidation
  scope item was extracted to a live chore pre-draft. Nine observations-log entries
  consumed and archived.

## Sources

- **The drafting invocation (2026-07-01)** — Diego's seed brief: PR-body human-usability
  (bloat, hard-wrap) and observations-log append collisions from the day's orchestration
  run, plus the mining and fold-detection directives.
- **Observations log 2026-06-10 (graph drift)** — hand-drawn ASCII dependency graph drifted
  from `Dependencies:` lines on first authoring. Consumed; archived 2026-07-02.
- **Observations log 2026-06-12 (archive-ritual home)** — archive-on-consume mechanics and
  their canonical doctrine home. Consumed; archived 2026-07-02.
- **Observations log 2026-06-12 (resolution-path-only rule)** — skills cannot
  relative-link doctrine across delivery modes. Consumed; archived 2026-07-02.
- **Observations log 2026-06-16 (delivered-layout links)** — doctrine cross-references
  green in CI yet dead in writer delivery. Consumed; archived 2026-07-02.
- **Observations log 2026-06-17 (brief derived-stat drift)** — brief-embedded derived
  stats drifted from source files in three instances. Consumed; archived 2026-07-02.
- **Observations log 2026-06-28 (annotation drift)** — two manual completion-annotation
  styles coexisting in flight on one spec. Consumed; archived 2026-07-02.
- **Observations log 2026-06-29 (annotation ownership)** — reconcile preserves annotations;
  nobody refreshes completion annotations. Consumed; archived 2026-07-02.
- **Observations log 2026-06-29 (marker placement)** — `[pending-sign-off]` subject
  placement inconsistent across 19 commits. Consumed; archived 2026-07-02. Sharpened
  during drafting by reproduction: pre-prefix placement fails the conventional lint and is
  unfixable in a CI-linted range.
- **Observations log 2026-06-29 ([[name]] links)** — machine-local memory links in
  committed spec artifacts. Consumed; archived 2026-07-02.
- **Observations log 2026-06-12 (worker union-merge ritual)** — unconsumed context:
  evidence of the append-collision workaround under concurrency.
- **Observations log 2026-06-17 (multi-target accumulator)** — unconsumed boundary: the
  deferred cross-repo routing design this spec deliberately does not enter.
- **Observations log 2026-07-01 (trailer squash relocation)** — unconsumed context: squash
  merges relocate branch commit-message content into the merge commit body.
- **Research: GitHub merge-driver support** — GitHub ignores `.gitattributes` merge
  drivers, including built-in `merge=union`, on PR merges (GitHub community discussion
  9288; kubernetes/kubernetes PR 70576 removed their union driver for this reason).
- **Research: news-fragment changelog pattern** — towncrier's per-PR fragment files
  compiled by a single writer (python/cpython PR 552; attrs, PyInstaller, Prefect issue
  2311). Pattern adopted; the tool is not.
- **Sibling bundles and doctrine** — bootstrap (gate-wiring, the log's origin),
  orchestration-concurrency (reconcile sole-writer contract), orchestration-fleet (fleet
  boundary), the accumulator-taxonomy doctrine (class-3 invariants).
- **The esc()/sanitizer consolidation chore (2026-07-02)** — the extracted sibling chore;
  the echo-discipline and esc() duplication entries resolve there, not here.
