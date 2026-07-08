# Observation Recording — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-08
**Format-version:** 1

Dependency shape (derived view; the `Dependencies:` lines are authoritative):
Task 1 is the substrate root; Task 2 is the guard and deliberately precedes
every task whose verification it protects (guard-infrastructure-first); Tasks
3 and 4 build the readers and the consumption mechanics; Task 5 reconciles doctrine and
skill text; Task 6 is the cutover and must land with Task 5 as one unit
(REQ-E1.2) — dispatch Tasks 5–6 as a cohesion bundle.

## Forward plan

### Task 1 — Recording substrate and helper

- **Deliverables:** `scripts/obs-record.sh` (UID minting from a system
  entropy source, anchored-grammar validation of every filename component
  under `LC_ALL=C` plus calendar-date validity, containment check after
  canonicalization, bounded fail-on-exists collision retry with clean
  refusal on exhaustion or entropy failure, clean refusal on hostile input
  and on entry text carrying newlines or control characters, atomic
  exclusive fragment write — temp file, then a fail-on-exists publish,
  never a destination-replacing rename — with the one-line entry form);
  `tests/test-obs-record.sh` covering the happy path, collision retry, and
  hostile-input refusals (traversal, uppercase, control characters,
  overlong slug, malformed and non-calendar date, multi-line entry text),
  plus a direct unit test of the containment check (grammar-valid input
  that only the containment step could refuse).
- **Done when:** Two same-day, same-slug invocations produce distinct
  filenames and both files survive; a forced collision retries with a fresh
  UID and never overwrites (including a UID colliding only with an archived
  fragment, and a same-directory collision under a different slug — proving
  the check keys on the UID); each hostile-input fixture exits non-zero
  with no path created; `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-6, D-7 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.6, REQ-B1.1, REQ-D1.1, REQ-D1.3
- **Estimated effort:** 1 day

### Task 2 — Fragment CI guard (`check:obs`)

- **Deliverables:** A guard script, running under `LC_ALL=C`, validating
  every file under `specs/_observations/entries/` and
  `specs/_observations/archive/` against the filename grammar (calendar
  dates included) and the one-entry-per-file content shape with an exact
  metadata whitelist, checking UID uniqueness across both directories, and
  failing on unexpected files under `specs/_observations/` (the two
  directories and the frozen legacy files are the only expected contents;
  null-safe over absent directories);
  a `check:obs` mise task wired into the aggregate `check`;
  seeded-violation fixtures in `tests/`.
- **Done when:** Each seeded violation (bad name, traversal-shaped name,
  non-calendar date, multi-entry file, missing entry line, free-prose
  body, unrecognized metadata key, duplicate UID across directories,
  unexpected top-level file) fails the guard; a clean tree passes; the
  task runs inside `mise run check` in CI.
- **Dependencies:** 1
- **Citations:** D-6, D-7 · REQ-D1.4, REQ-A1.2
- **Estimated effort:** half day

### Task 3 — Render command and drain surfacing

- **Deliverables:** `scripts/obs-render.sh` (chronological view in the
  defined total order — date, then same-date legacy lines in file order
  before same-date fragments by UID — `--archived` flag, legacy-file
  interleave while unconsumed legacy entries exist, byte-deterministic,
  echo-discipline sanitized for fragment *and* legacy content,
  skip-and-warn on invalid files, empty-state defined) plus the mise task
  `obs:log`; `scripts/drain-gates.sh` observation surfacing reworked to
  derive unmined count and oldest-entry age from the `entries/` glob
  (null-safe; `Consumed-by:`-bearing fragments excluded and surfaced as
  stuck consumes) plus the frozen legacy file's unconsumed lines, naming
  both surfaces; tests updated (`tests/test-drain-gates.sh`, new
  `tests/test-obs-render.sh`), age fixtures pinned via `--today`.
- **Done when:** Render output matches fixtures byte-for-byte for a fixed
  fragment set, including the legacy interleave and a same-date
  legacy-plus-fragment pair; a hostile legacy line renders sanitized; the
  drain report shows the combined count and correct oldest age (pinned
  `--today`) across both surfaces, reports zero-count with no age line on
  an empty set, and names a stuck consume; `mise run check` is green.
- **Dependencies:** 1, 2
- **Citations:** D-4, D-7 · REQ-B1.3, REQ-C1.3, REQ-C1.4, REQ-D1.3
- **Estimated effort:** 1 day

### Task 4 — Consumption and archival mechanics

- **Deliverables:** `scripts/obs-consume.sh` (UID-keyed: validate the UID
  and spec-identifier arguments against their anchored grammars under
  `LC_ALL=C`, containment-check composed paths, operate only on regular
  files — never through symlinks; append `Consumed-by: specs/<spec>
  (<date>)` atomically and conditionally — skipped when a same-spec line
  exists — then move to `archive/`; idempotent on re-run, including
  completion of a crashed half-consume left annotated in `entries/`; a
  line-content-keyed legacy arm annotating the frozen log in place);
  `tests/test-obs-consume.sh` covering the happy path, slug-renamed
  fragment consumed by UID, an entry whose text was edited then consumed
  by UID, re-run idempotency (single annotation; a fully archived
  same-spec consume is a clean no-op), the crash-window
  fixture, an unknown-UID refusal, a duplicate-UID refusal naming both
  matches, hostile UID/spec-id refusals (traversal, glob, newline
  injection), a symlinked fragment refused, hostile fragment content
  handled as data, and the legacy in-place annotation.
- **Done when:** A consumed fragment sits in `archive/` with UID preserved
  and exactly one annotation inside; consuming by UID works after a slug
  rename and after a content edit; a second run is a no-op; the
  annotated-but-unmoved fixture completes without duplicating the
  annotation; each hostile fixture exits non-zero with no path touched; a
  simulated two-branch merge (one branch adds, one consumes a different
  fragment) merges clean, and a same-fragment double-consume fixture
  produces a conflict confined to that one fragment; `mise run check` is
  green.
- **Dependencies:** 1, 2
- **Citations:** D-3, D-7 · REQ-B1.2, REQ-C1.2, REQ-A1.5
- **Estimated effort:** half day

### Task 5 — Doctrine and skill reconciliation

- **Deliverables:** accumulator-taxonomy amended as the canonical home of
  the fragment drain ritual (the class/home/reader/drain classification
  rule restated with archive-on-consume as this accumulator's specific
  ritual, the `obs:<uid>` citation form, and the "class-3" shorthand
  token); spec-format glossary "Observations log" entry rewritten per D-8
  (dropping "append-only"; the sibling "Accumulator" entry's reference
  updated) and the "Citation syntax and kinds" table given the `obs:<uid>`
  kind; `doctrine/decision-domains.md` and `docs/CONTRIBUTING.md` recording
  instructions reconciled; recording and reading instructions reconciled in
  all ten skills — `/spec-draft` (seed gathering + archive-on-consume
  sections), `/spec-kickoff`, `/execute-task`, `/self-review`, `/polish`,
  `/drain`, `/orchestrate` (`--bookkeeping` surfacing), `/builder`,
  `/resume`, and `/spec-walkthrough` (the drift-log Maintenance write in
  every skill routes through `obs-record.sh`, keeping the
  `skill-drift(...)` entry form and the no-`specs/` fallback) — all
  pointing at the shared helpers; the "shared blackboard" framing in
  `doctrine/inter-orchestrator-coordination.md` reviewed against the
  fragment model.
- **Done when:** A search across `skills/`, `doctrine/`, and `docs/` finds
  no shipped text instructing an append to `opportunities.md` or to a
  shared observations file; every recording skill names `obs-record.sh`
  and the mining path names `obs-consume.sh`;
  `mise run check` (including `check:links` and `check:specs`) is green.
- **Dependencies:** 1, 2, 3, 4
- **Citations:** D-8 · REQ-E1.3, REQ-C1.1, REQ-C1.2, REQ-D1.2
- **Estimated effort:** 1 day

### Task 6 — Migration cutover (dedup, freeze, dirs)

- **Deliverables:** The one-time migration: remove each resurrected
  duplicate line from `opportunities.md` (each removal cited to its
  `archive.md` consumed-by record in the PR body; the removal set
  recomputed against the branch's current state immediately before merge;
  any candidate plausibly a legitimate textual re-occurrence kept, not
  removed); freeze headers on `opportunities.md` and `archive.md` naming
  the fragment substrate and this spec (`entries/` and `archive/` need no
  migration step — the helpers create them on demand, never committed
  empty); the four log entries covering findings F1–F5
  annotated in place as consumed by this spec (the legacy-consume arm —
  they are frozen-log lines, not fragments, so the archive move does not
  apply) if `chore/log-oh-findings` has merged
  by then (otherwise recorded as a new Deferred entry in this `tasks.md`
  with a free-text gate on that branch's merge — never only PR-body
  prose). Lands in the same PR as Task 5's flip (cohesion bundle,
  REQ-E1.2).
- **Done when:** The frozen files carry their headers; no removed line lacks
  a consumed-by citation; `check:obs` passes over the tree (null-safe
  while either fragment directory is still absent);
  no skill text on the branch still appends to the frozen log (Task 5 in the
  same unit); the F1–F5 in-place consumption is either done or gated in
  Deferred; `mise run check` is green.
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
  brief; until it lands, output-hygiene Tasks 1–2 must not be dispatched
  (they would build the superseded design). The gate is free text by design:
  a status atom on this spec would fall silent once this spec completes,
  while the hold must persist until the amendment lands (kickoff lens pass
  2026-07-08). Confidence: high.
  **Gate:** the output-hygiene carve-out amendment has landed.
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
