# Output & Accumulator Hygiene — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-08
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
fixed). This spec makes the pipeline outputs it governs human-first — the PR bodies emitted
by `/execute-task` and `/self-review` (REQ-A scopes the contract to those two skills; other
generated surfaces are out of this spec's frame) — and the shared accumulator surface it
retains, the `tasks.md` annotation layer, drift-free and format-stable under concurrent
runs. The conflict-free observations-recording concern (REQ-B, D-1, Tasks 1–2) was carved
out to `specs/observation-recording` on 2026-07-08 and is superseded there (its REQ-E1.4 /
D-9 record the supersession); this bundle retains the other four concerns.

## Scope

### In scope

- **A human-first PR-body contract** for `/execute-task` and `/self-review`: concise summary
  first, the full audit record collapsed, prose not hard-wrapped, one normative home.
- **Pending-sign-off marker canonicalization**: one placement, defined in doctrine, emitted
  by skills, guarded at a moment the author can still fix it, branch-scoped for consumers.
- **Committed-reference integrity**: no reference in a committed or delivered artifact that
  its intended reader cannot resolve (machine-local `[[name]]` links, links dead in the
  delivered layout), with a mechanical guard.
- **Derived-content hygiene**: derivable content in committed artifacts is cited or
  regenerated, never hand-copied without a named refresh owner (completion annotations,
  brief-embedded stats, hand-drawn dependency graphs).

### Out of scope

- **Conflict-free observations recording.** Carved out to `specs/observation-recording`
  (merged Ready 2026-07-08), which supersedes REQ-B, D-1, and Tasks 1–2
  (observation-recording REQ-E1.4 / D-9 record the supersession; its fragment substrate
  owns recording, the conflict-freedom invariants, readers/drain, the security guards,
  and migration of the existing log).
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
  left unowned — additively, filling the unowned completion-annotation gap, contradicting
  no `orchestration-concurrency` requirement (see D-5; kickoff §4, 2026-07-06).
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

*(Group superseded 2026-07-08: the observations-recording concern moved to
`specs/observation-recording` — see Out of scope. Each requirement below carries its
supersede pointer; bodies are frozen per the stable-ID rule (bootstrap D-20).)*

- **REQ-B1.1** Concurrent runs SHALL be able to record observations without colliding on a
  shared textual append point: each run writes to a distinct per-run fragment file (a
  run-unique name — REQ-B1.5), and consolidation of fragments into the shared log SHALL be a
  single-writer, default-branch operation that is idempotent and, on any log conflict,
  regenerates from current state rather than resolving by ours/theirs/union.
  **Superseded-by: REQ-A1.1 (observation-recording)** (2026-07-08) — per-entry fragments
  replace per-run fragments plus consolidation; conflict-freedom by construction is
  observation-recording REQ-B1.1, the derived view observation-recording REQ-B1.3.
  *(Cites: the drafting invocation (Sources); research: GitHub merge-driver support
  (Sources); D-1.)*
- **REQ-B1.2** The recording mechanism SHALL preserve the accumulator-taxonomy class-3
  contract for the observations log: a durable home, the canonical reader (`/spec-draft`),
  and a drain ritual — here, drain-pass surfacing (unmined count and oldest age) plus the
  observations log's archive-on-consume. The queue SHALL be named in the accumulator-taxonomy
  doctrine as a class-3 surface with those three attributes stated.
  **Superseded-by: REQ-C1.1 (observation-recording)** (2026-07-08) — the class-3
  contract restated for the fragment layout.
  *(Cites: observations log 2026-06-12 (archive-ritual home) (Sources); D-1.)*
- **REQ-B1.3** Existing log entries SHALL never be lost, reordered, or rewrapped by the
  mechanism's consolidation: consolidation appends only (in consolidation order, never
  re-sorted by fragment date) and moves entry text verbatim, never redacting or rewrapping
  it.
  **Superseded-by: REQ-E1.1 (observation-recording)** (2026-07-08) — consolidation is
  dissolved in the fragment model; the existing log is dedup-then-frozen with entries
  preserved in place.
  *(Cites: D-1.)*
- **REQ-B1.4** The existing consumers (the drain pass's observation surface, `/spec-draft`
  mining and archive trim) SHALL read the new layout with unchanged reported semantics.
  **Superseded-by: REQ-C1.2 (observation-recording)** (2026-07-08) — mining and the
  drain surface read the fragment layout (with observation-recording REQ-C1.3).
  *(Cites: D-1; accumulator-taxonomy doctrine (Sources).)*
- **REQ-B1.5** Fragment names SHALL be built only from components validated against their
  declared grammars **before** any path interpolation (the task-id grammar for the
  `<taskid>` segment; `^[a-z0-9]+$` for the `<run-nonce>`), and the derived fragment path
  SHALL be containment-checked after canonicalization before any read or write; hostile or
  malformed input is a clean refusal (the observation is dropped and flagged, never written
  to an out-of-tree path). Slug- and branch-derived names echoed into reports or commit
  output SHALL be passed through the printable-sanitizer (`scripts/echo-safety.sh`) first.
  **Superseded-by: REQ-D1.1 (observation-recording)** (2026-07-08) — the
  validate/contain/refuse and printable-sanitize posture carried to the fragment
  substrate (with observation-recording REQ-D1.3).
  *(Cites: security-posture (Sources); orchestration-concurrency REQ-F1.1 (Sources); D-1.)*

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
  (writer-install or plugin) layout. Enforcement is mechanical and forward-standing: a
  `check:*` guard under `mise run check` SHALL flag any `[[name]]` token in a committed
  spec file (so a future writer that skips neutralization fails CI), and writers neutralize
  before commit (REQ-D1.2). The standing guard's scope is the four spec files; already-signed
  kickoff-brief bodies are append-only (their historical `[[…]]` are a bounded, named
  carve-out reconciled only where the amendment ritual reaches spec files — REQ-D1.4).
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
  `## Completed` when merged-PR evidence is in hand. With no remote configured it degrades
  to exactly one of two pinned outputs — the date-only form `Completed · merged <YYYY-MM-DD>`
  (from branch evidence), or leaving the annotation untouched when even the date is unknown —
  never an invented PR number and never a third free-form variant (two fixed outputs, so the
  two-coexisting-styles drift cannot reappear).
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
  accumulator redesign; bootstrap D-21 spin-new triggers fire). The escaper/sanitizer
  consolidation scope item was extracted to a live chore pre-draft. Nine observations-log
  entries consumed and archived.
- 2026-07-06 — Kickoff walkthrough (section 3) edits, Draft-in-place: D-1 + Task 1 pin a
  run-unique fragment-name component (branch/task id, content-hash fallback) so concurrent
  same-date runs cannot collide; D-4 + Task 5 + REQ-D1.3 widen the doctrine link allowlist
  to include `../scripts/` (a verified co-located delivery sibling), leaving `../skills/`
  as the sole real violation; Task 6 scopes the `[[name]]` sweep to the four spec files
  (already-signed brief bodies are append-only, out of scope). No REQ meaning changed;
  clarifications and one design-rule widening. Full sign-off is meaning-class (first
  activation).
- 2026-07-06 — Kickoff walkthrough (section 4) correction, resolution (A): D-5 item 1 +
  Task 7 + the Out-of-scope note reframed from "narrowly supersedes `orchestration-concurrency`
  REQ-B1.1's annotations-preserved-byte-for-byte clause" to **additive**. Grounding: that
  clause does not exist — the anchor-stability guarantee over the five definition fields
  lives in the content-anchor doctrine (realized by `tasks-pr-sync.sh`), not in REQ-B1.1's
  text, and the completion annotation is an unowned gap (observations log 2026-06-29), not
  an existing owner. No cross-bundle `Superseded-by:` pointer is written; Task 7 instead
  corrects the stale `tasks-pr-sync.sh` implementation comment. No edit to any Done
  `orchestration-concurrency` spec file.
- 2026-07-06 — Kickoff walkthrough (sections 5, 7): REQ-C1.4 dead-path fix and Task 6
  fleet-coordination note (both superseded / corrected by the 2026-07-07 lens-pass entry
  below; see there).
- 2026-07-07 — Kickoff sign-off lens pass (first activation, full-bundle fan-out) findings
  dispositioned across six clusters. **Cluster 1 (D-1 rework):** consolidation reworked to a
  single default-branch writer (`/spec-draft` mines read-only), one atomic append+delete
  commit, idempotent-regenerate-on-conflict, a dedicated global `_observations` advisory
  lock (perf only), append-in-consolidation-order, and a per-run-nonce fragment name
  (`<date>-<taskid>-<run-nonce>`) superseding the task-id-only naming. **Cluster 2
  (security):** new REQ-B1.5 (charset-validate-before-path-use, containment check, clean
  refusal, printable-sanitize) mirroring `orchestration-concurrency` REQ-F1.1; the
  re-screen-on-boundary claim corrected to write-time-only (consolidation moves text
  verbatim, per REQ-B1.3). **Cluster 3:** REQ-C1.4 §5 dead-path fix **reverted** — a marker
  consumer does exist (the pending-sign-off checklist regeneration, gate-wiring); `design.md`
  restructured to conformant `### D-N:` + colon labels (a validator blind spot on H2 headings
  had masked the non-conformance — logged as an observation); this Changelog reordered to
  chronological. **Cluster 4:** a standing mechanical `[[name]]` guard added (REQ-D1.1);
  test-spec assertions for distinct-filename and anchor-unchanged added. **Cluster 5:**
  citation/format fixes incl. the pinned degraded annotation string (REQ-E1.2) and a doctrine
  home for the canonical annotation format (Task 8). **Cluster 6:** goal/collision claims
  scoped, two Sources relabeled consumed, `queue/` name kept.

- 2026-07-08 — Scope-down delta re-walkthrough (meaning-class): the conflict-free
  observations-recording concern carved out to `specs/observation-recording` (merged Ready
  2026-07-08), which supersedes it (observation-recording REQ-E1.4 / D-9). REQ-B1.1,
  REQ-B1.2, REQ-B1.3, REQ-B1.4, and REQ-B1.5 marked `Superseded-by` observation-recording
  REQ-A1.1 / REQ-C1.1 / REQ-E1.1 / REQ-C1.2 / REQ-D1.1 respectively (bodies frozen); D-1
  marked `Superseded-by: observation-recording D-1` in place; Tasks 1 and 2 moved whole to
  `tasks.md` `## Out of scope` (blocks preserved, never dispatched); the REQ-B test-spec
  entries removed with the group; the Scope In-scope bullet dropped and an Out-of-scope
  pointer added; the Goal notes the carve-out and scopes its accumulator claim to the
  retained `tasks.md` annotation layer; the `tasks.md` intro dependency note updated
  (remaining graph: Task 5 → {3, 4, 6, 8}; Task 7 standalone). The pointer form
  `**Superseded-by: REQ-<id> (observation-recording)**` places the foreign namespace in a
  trailing qualifier because the validator's supersede marker is anchored on the literal
  `Superseded-by: REQ-` prefix; D-pointers use the namespace-first precedent form.

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
- **Observations log 2026-06-16 (catalog-gap)** — the human-comprehension / information-UX
  decision domain has no entry in the decision-domains catalog; left unconsumed for the
  catalog's own amendment (grounds D-2's domain note; routed to an observation, not decided
  in this bundle).
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
- **Observations log 2026-06-12 (worker union-merge ritual)** — the append-collision
  workaround under concurrency; grounds D-1's rejected "worker merge etiquette" alternative.
  Consumed; archived 2026-07-02.
- **Observations log 2026-06-17 (multi-target accumulator)** — unconsumed boundary: the
  deferred cross-repo routing design this spec deliberately does not enter.
- **Observations log 2026-07-01 (trailer squash relocation)** — squash merges relocate
  branch commit-message content into the merge commit body; grounds D-3 / REQ-C1.4's
  branch-scoped-consumption rule. Consumed; archived 2026-07-02.
- **Research: GitHub merge-driver support** — GitHub ignores `.gitattributes` merge
  drivers, including built-in `merge=union`, on PR merges (GitHub community discussion
  9288; kubernetes/kubernetes PR 70576 removed their union driver for this reason).
- **Research: news-fragment changelog pattern** — towncrier's per-PR fragment files
  compiled by a single writer (python/cpython PR 552; attrs, PyInstaller, Prefect issue
  2311). Pattern adopted; the tool is not.
- **Sibling bundles and doctrine** — bootstrap (gate-wiring, the log's origin),
  orchestration-concurrency (reconcile sole-writer contract; **REQ-F1.1**, the
  validate-identifiers-before-path-use / containment-check / clean-refusal data-not-code
  rule that REQ-B1.5 mirrors), orchestration-fleet (fleet boundary), the accumulator-taxonomy
  doctrine (class-3 contract).
- **security-posture (doctrine)** — artifact data-hygiene (write-time screening; no secrets
  or internal detail in committed artifacts) and framework-script security (identifiers
  validated before path use; paths containment-checked after canonicalization;
  branch-derived text printable-sanitized before echo). Grounds REQ-B1.5 and the data-hygiene
  cross-cutting note.
- **The esc()/sanitizer consolidation chore (2026-07-02)** — the extracted sibling chore;
  the echo-discipline and esc() duplication entries resolve there, not here.
