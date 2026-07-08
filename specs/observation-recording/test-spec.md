# Observation Recording — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

Coverage mix: 21 REQs. The substrate, guard, render, drain, and consumption
mechanics verify as `[test]` shell fixtures under `tests/`, run by
`mise run check` in the repo's GitHub Actions CI (`ci.yml`). Doctrine and
skill-text reconciliation verifies as `[design-level]` artifact checks
backed by mechanical greps where honest. The migration and cross-spec
coordination carry `[manual]` halves: a human reviews the dedup line-by-line
at the migration PR and owns the output-hygiene coordination.

## REQ-A — Fragment recording substrate

### REQ-A1.1 — fragments only, no shared log [test + design-level]

`[test]` `tests/test-obs-record.sh`: the helper writes exactly one file
under `entries/` per invocation and touches no other path (asserted against
a before/after tree listing). `[design-level]` Task 5's done-when grep: no
shipped skill or doctrine text instructs appending to `opportunities.md`.

### REQ-A1.2 — filename grammar [test]

`tests/test-obs-record.sh` acceptance/rejection fixtures for every
component: valid names pass; malformed date (non-calendar, wrong shape),
uppercase or underscore slug, overlong slug, wrong-length or non-hex UID
all refuse. The `check:obs` guard (Task 2) re-validates committed names.

### REQ-A1.3 — fail-on-exists collision retry [test]

`tests/test-obs-record.sh`: a pre-created colliding filename forces the
retry path; the original file's bytes are untouched and the new fragment
lands under a fresh UID.

### REQ-A1.4 — entry-form content shape [test]

`check:obs` fixtures (Task 2): a fragment whose first content line does not
match the `- <date> [<scope>]` entry prefix fails; a fragment with a
trailing `Consumed-by:` metadata line passes.

### REQ-A1.5 — UID as durable identity [test]

`tests/test-obs-consume.sh`: rename a fragment's slug, then consume by UID —
the consume succeeds and the archived filename preserves the UID; a citation
string built as `obs:<uid>` still greps to exactly one file across
`entries/` + `archive/` after the move.

### REQ-A1.6 — single recording helper [design-level]

Task 5's reconciliation: every recording skill's instructions invoke
`obs-record.sh` (mechanical grep across `skills/`); no skill text composes a
fragment path by hand.

## REQ-B — Conflict-freedom invariants

### REQ-B1.1 — concurrent adds never conflict [test]

`tests/test-obs-record.sh`: two branches from a common base each record an
observation (same day, same slug); `git merge` of the second branch
completes with no conflict and both fragments exist.

### REQ-B1.2 — archive-on-consume is a single-file move [test]

`tests/test-obs-consume.sh`: the simulated two-branch fixture (one branch
adds a fragment, the other consumes a different one) merges clean; the
consumed fragment exists only in `archive/`, same filename, and no other
file changed in the consume commit.

### REQ-B1.3 — derived view, never committed [test + design-level]

`[test]` `tests/test-obs-render.sh`: two runs over the same fragment set are
byte-identical (pure function). `[design-level]` No task in this bundle (nor
any reconciled skill text) writes a compiled view to the tree; the render
script writes only to stdout.

## REQ-C — Readers, drain, and the class-3 contract

### REQ-C1.1 — class-3 contract restated in doctrine [design-level]

The Task 5 accumulator-taxonomy amendment names all four tuple elements
(durable home, canonical reader, drain ritual, archive ritual) for the
fragment layout and defines the `obs:<uid>` citation form; existence plus
coverage of that doctrine section is the verification.

### REQ-C1.2 — mining and consumption semantics [test + manual]

`[test]` `tests/test-obs-consume.sh`: annotate-then-move ordering (the
crash-window fixture finds an annotated-but-unmoved fragment and completes
it idempotently); legacy in-place annotation fixture appends `— consumed-by:`
to a frozen-log line without reordering the file. `[manual]` The first real
`/spec-draft` mining pass after cutover exercises the combined candidate set
(fragments + legacy) end-to-end.

### REQ-C1.3 — drain surfaces both sources [test]

`tests/test-drain-gates.sh`: a fixture tree with N fragments and M
unconsumed legacy lines reports count N+M and the correct oldest age, and
names both surfaces; with the legacy file fully consumed, the report shows
fragments only.

### REQ-C1.4 — deterministic chronological render [test]

`tests/test-obs-render.sh`: fixture fragments across multiple dates (plus a
same-date pair ordered by UID) render in order, byte-matched against a
golden file; the `--archived` flag includes `archive/` entries; the legacy
interleave fixture merges frozen-log lines chronologically.

## REQ-D — Security, hygiene, and guards

### REQ-D1.1 — validate, contain, refuse [test]

`tests/test-obs-record.sh` hostile-input fixtures: path traversal in slug or
date, absolute-path injection, control characters, locale-dependent
uppercase under a UTF-8 locale (asserting `LC_ALL=C` behavior) — each exits
non-zero, creates no path, and prints a sanitized message.

### REQ-D1.2 — write-time data hygiene [design-level + manual]

`[design-level]` The recording instructions in every skill (Task 5) state
the write-time screen per the security-posture artifact rule; consumption
paths contain no re-screen step (verbatim move asserted by the REQ-B1.2
fixture). `[manual]` Prose-shaped leaks remain a write-time human/agent
judgment; the repo's `scan:secrets` guard covers token-shaped leaks in CI.

### REQ-D1.3 — content is data only [test]

`tests/test-obs-render.sh` and `tests/test-drain-gates.sh`: a fragment whose
content carries control bytes and shell metacharacters renders/reports with
non-printables stripped and no expansion side effects (the hostile-content
fixture pattern used by the gate evaluator's tests).

### REQ-D1.4 — standing CI guard [test]

Task 2's seeded-violation fixtures: bad name, traversal-shaped name,
multi-entry file, missing entry line each fail `check:obs`; a clean tree
passes; the task is wired into the aggregate `mise run check` that CI runs.

## REQ-E — Migration and cross-spec coordination

### REQ-E1.1 — dedup then freeze [manual + test]

`[manual]` The migration PR lists every removed line beside its `archive.md`
consumed-by record; the human verifies the one-to-one pairing before merge.
`[test]` Post-state: `check:obs` passes over the created directories, and a
fixture asserts both frozen files open with their freeze headers.

### REQ-E1.2 — no split-brain window [design-level + manual]

`[design-level]` Tasks 5 and 6 are declared a cohesion bundle in `tasks.md`
(one dispatch unit, one PR). `[manual]` The human confirms at that PR that
the flip and the freeze land together.

### REQ-E1.3 — doctrine and skill reconciliation [test + design-level]

`[test]` Task 5's done-when grep is run as part of its verification: zero
matches for append-to-`opportunities.md` instructions in shipped `skills/`
and `doctrine/` text; `check:links` and `check:specs` green. `[design-level]`
The amended accumulator-taxonomy and spec-format glossary sections exist and
name the fragment substrate.

### REQ-E1.4 — supersession and coordination gate [design-level + manual]

`[design-level]` The Deferred entry with
`GATE(when: spec observation-recording active)` exists in `tasks.md` and the
drain pass surfaces it (covered generically by `tests/test-drain-gates.sh`).
`[manual]` The human performs the output-hygiene carve-out amendment and
holds its Tasks 1–2 undispatched until then.
