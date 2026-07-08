# Observation Recording — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

Dependency shape (derived view; the `Dependencies:` lines are authoritative):
Task 1 is the substrate root; Task 2 is the guard and deliberately precedes
every task whose verification it protects (guard-infrastructure-first); Tasks
3 and 4 build the readers on the substrate; Task 5 reconciles doctrine and
skill text; Task 6 is the cutover and must land with Task 5 as one unit
(REQ-E1.2) — dispatch Tasks 5–6 as a cohesion bundle.

## Forward plan

### Task 1 — Recording substrate and helper

- **Deliverables:** `scripts/obs-record.sh` (UID minting from a system
  entropy source, anchored-grammar validation of every filename component
  under `LC_ALL=C`, containment check after canonicalization, fail-on-exists
  collision retry, clean refusal on hostile input, fragment write with the
  one-line entry form); `tests/test-obs-record.sh` covering the happy path,
  collision retry, and hostile-input refusals (traversal, uppercase, control
  characters, overlong slug, malformed date).
- **Done when:** Two same-day, same-slug invocations produce distinct
  filenames and both files survive; a forced collision retries with a fresh
  UID and never overwrites; each hostile-input fixture exits non-zero with
  no path created; `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-2, D-6, D-7 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.6, REQ-B1.1, REQ-D1.1, REQ-D1.3
- **Estimated effort:** 1 day

### Task 2 — Fragment CI guard (`check:obs`)

- **Deliverables:** A guard script validating every file under
  `specs/_observations/entries/` and `specs/_observations/archive/` against
  the filename grammar and the one-entry-per-file content shape; a
  `check:obs` mise task wired into the aggregate `check`; seeded-violation
  fixtures in `tests/`.
- **Done when:** Each seeded violation (bad name, traversal-shaped name,
  multi-entry file, missing entry line) fails the guard; a clean tree
  passes; the task runs inside `mise run check` in CI.
- **Dependencies:** 1
- **Citations:** D-6, D-7 · REQ-D1.4, REQ-A1.2
- **Estimated effort:** half day

### Task 3 — Render command and drain surfacing

- **Deliverables:** `scripts/obs-render.sh` (chronological view ordered by
  date then UID, `--archived` flag, legacy-file interleave while unconsumed
  legacy entries exist, byte-deterministic, echo-discipline sanitized) plus
  a mise task (for example `obs:log`); `scripts/drain-gates.sh` observation
  surfacing reworked to derive unmined count and oldest-entry age from the
  `entries/` glob plus the frozen legacy file's unconsumed lines, naming
  both surfaces; tests updated (`tests/test-drain-gates.sh`, new
  `tests/test-obs-render.sh`).
- **Done when:** Render output matches fixtures byte-for-byte for a fixed
  fragment set, including the legacy interleave; the drain report shows the
  combined count and correct oldest age across both surfaces; `mise run
  check` is green.
- **Dependencies:** 1, 2
- **Citations:** D-4, D-7 · REQ-B1.3, REQ-C1.3, REQ-C1.4, REQ-D1.3
- **Estimated effort:** 1 day

### Task 4 — Consumption and archival mechanics

- **Deliverables:** `scripts/obs-consume.sh` (UID-keyed: append
  `Consumed-by: specs/<spec> (<date>)` inside the fragment, then move it to
  `archive/`; idempotent on re-run, including completion of a crashed
  half-consume left annotated in `entries/`); `tests/test-obs-consume.sh`
  covering the happy path, slug-renamed fragment consumed by UID, re-run
  idempotency, and the crash-window fixture.
- **Done when:** A consumed fragment sits in `archive/` with UID preserved
  and the annotation inside; consuming by UID works after a slug rename; a
  second run is a no-op; the annotated-but-unmoved fixture completes; a
  simulated two-branch merge (one branch adds, one consumes a different
  fragment) merges clean; `mise run check` is green.
- **Dependencies:** 1, 2
- **Citations:** D-3, D-7 · REQ-B1.2, REQ-C1.2, REQ-A1.5
- **Estimated effort:** half day

### Task 5 — Doctrine and skill reconciliation

- **Deliverables:** accumulator-taxonomy amended as the canonical home of
  the fragment drain ritual (4-tuple restated, `obs:<uid>` citation form);
  spec-format glossary "Observations log" entry updated; recording and
  reading instructions reconciled in `/spec-draft` (seed gathering +
  archive-on-consume sections), `/spec-kickoff`, `/execute-task`,
  `/self-review`, `/polish`, `/drain`, and `/orchestrate` (`--bookkeeping`
  surfacing), all pointing at the shared helpers.
- **Done when:** A repo-wide search finds no shipped skill or doctrine text
  instructing an append to `opportunities.md`; every recording skill names
  `obs-record.sh` and the mining path names `obs-consume.sh`;
  `mise run check` (including `check:links` and `check:specs`) is green.
- **Dependencies:** 1, 2, 3, 4
- **Citations:** D-8 · REQ-E1.3, REQ-C1.1, REQ-C1.2
- **Estimated effort:** 1 day

### Task 6 — Migration cutover (dedup, freeze, dirs)

- **Deliverables:** The one-time migration: remove each resurrected
  duplicate line from `opportunities.md` (each removal cited to its
  `archive.md` consumed-by record in the PR body); freeze headers on
  `opportunities.md` and `archive.md` naming the fragment substrate and this
  spec; `entries/` and `archive/` directories created; the four F1–F5
  chore-branch entries archived as consumed-by this spec if
  `chore/log-oh-findings` has merged by then (otherwise recorded as a
  remaining step in the PR body). Lands in the same PR as Task 5's flip
  (cohesion bundle, REQ-E1.2).
- **Done when:** The frozen files carry their headers; no removed line lacks
  a consumed-by citation; `check:obs` passes over the created directories;
  no skill text on the branch still appends to the frozen log (Task 5 in the
  same unit); `mise run check` is green.
- **Dependencies:** 2, 5
- **Citations:** D-5, D-9 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **Output-hygiene carve-out amendment.** Scoping REQ-B / D-1 / Tasks 1–2
  out of output-hygiene is a separate `/spec-kickoff` amendment per the seed
  charter; until it lands, output-hygiene Tasks 1–2 must not be dispatched
  (they would build the superseded design). Confidence: high.
  **Gate:** GATE(when: spec observation-recording active).
  Citations: D-9, REQ-E1.4, the seed brief (Sources).

## Out of scope

- Re-solving output-hygiene's four retained concerns (PR-body contract,
  marker canonicalization, committed-reference integrity, derived-content
  hygiene). Permanent: they are output-hygiene's scope.
- Multi-repo routing, fan-in inboxes, and consent-gated upstream channels —
  `observation-routing`'s domain (D-9 records the substrate adjacency).
- The reconcile-PR consolidation pattern — unnecessary under D-1; relevant
  to `autopilot-reflex`'s release work, not here.
- Adopting an external changelog/news-fragment tool — pattern borrowed,
  dependency declined (decision-domains walk, design.md Cross-cutting).
- Bulk conversion of legacy log entries into fragments (rejected in D-5).
