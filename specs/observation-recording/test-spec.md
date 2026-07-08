# Observation Recording — Test Spec

**Status:** Ready
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
component: valid names pass; malformed date (wrong shape, and well-shaped
but non-calendar such as `2026-02-30` — rejected by the calendar-validity
step the grammar alone cannot perform), uppercase or underscore slug,
overlong slug, wrong-length or non-hex UID all refuse. The `check:obs`
guard (Task 2) re-validates committed names under `LC_ALL=C`.

### REQ-A1.3 — fail-on-exists collision retry [test]

`tests/test-obs-record.sh`: a pre-created colliding filename forces the
retry path; the original file's bytes are untouched and the new fragment
lands under a fresh UID. A UID colliding only with an *archived* fragment
(`archive/*-<uid>.md`) also forces the retry, as does a same-directory
collision under a *different slug* (proving the check keys on the UID,
not the full filename). Retry exhaustion against a fully pre-seeded UID
space exits non-zero with no path created.

### REQ-A1.4 — entry-form content shape [test]

`check:obs` fixtures (Task 2): a fragment whose first content line does not
match the `- <date> [<scope>]` entry prefix fails; a fragment with a
trailing `Consumed-by:` metadata line passes; a fragment carrying free
prose beyond the entry line and recognized metadata lines fails; a
fragment carrying an unrecognized `Key: value`-shaped metadata line fails
(whitelist exactness). `tests/test-obs-record.sh`: entry text containing a
newline or control character is refused at write time.

### REQ-A1.5 — UID as durable identity [test]

`tests/test-obs-consume.sh`: rename a fragment's slug, then consume by UID —
the consume succeeds and the archived filename preserves the UID; edit a
fragment's entry text, then consume by UID — the consume succeeds
(identity is never keyed on entry text); a citation string built as
`obs:<uid>` still greps to exactly one file across `entries/` + `archive/`
after the move.

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
file changed in the consume commit. A same-fragment double-consume
two-branch fixture produces a merge conflict confined to that one
fragment (verifying the design's small-and-self-limiting claim).

### REQ-B1.3 — derived view, never committed [test + design-level]

`[test]` `tests/test-obs-render.sh`: two runs over the same fragment set are
byte-identical (pure function). The `check:obs` unexpected-file fixture
(Task 2): a seeded compiled-view file under `specs/_observations/` fails
the guard — the standing enforcement. `[design-level]` No task in this
bundle (nor any reconciled skill text) writes a compiled view to the tree;
the render script writes only to stdout.

## REQ-C — Readers, drain, and the class-3 contract

### REQ-C1.1 — class-3 contract restated in doctrine [design-level]

The Task 5 accumulator-taxonomy amendment names all four tuple elements
(class, durable home, canonical reader, drain ritual) for the fragment
layout, states archive-on-consume as this accumulator's *specific* ritual —
not a universal class-3 attribute (the promotion REQ-C1.1 forbids) — and
defines the `obs:<uid>` citation form; existence plus coverage of that
doctrine section is the verification.

### REQ-C1.2 — mining and consumption semantics [test + manual]

`[test]` `tests/test-obs-consume.sh`: annotate-then-move ordering (the
crash-window fixture finds an annotated-but-unmoved fragment and completes
it idempotently, leaving exactly one `Consumed-by:` line — the annotate is
conditional); legacy in-place annotation fixture appends `— consumed-by:`
to a frozen-log line without reordering the file.
`tests/test-drain-gates.sh`: an annotated-but-unmoved fragment is excluded
from the unmined count and surfaced as a stuck consume. `[manual]` The
first real `/spec-draft` mining pass after cutover exercises the combined
candidate set (fragments + legacy) end-to-end.

### REQ-C1.3 — drain surfaces both sources [test]

`tests/test-drain-gates.sh`: a fixture tree with N fragments and M
unconsumed legacy lines reports count N+M and the correct oldest age
(clock pinned via `--today`), and names both surfaces; with the legacy
file fully consumed, the report shows fragments only; with zero unmined
entries it reports the zero count and omits the age line (null-safe
globs).

### REQ-C1.4 — deterministic chronological render [test]

`tests/test-obs-render.sh`: fixture fragments across multiple dates (plus a
same-date pair ordered by UID, and a same-date legacy-line-plus-fragment
pair ordered legacy-first per the defined total order) render in order,
byte-matched against a golden file; the `--archived` flag includes
`archive/` entries; the legacy interleave fixture merges frozen-log lines
chronologically; an annotated-but-unmoved fragment is excluded from the
live view.

## REQ-D — Security, hygiene, and guards

### REQ-D1.1 — validate, contain, refuse [test]

`tests/test-obs-record.sh` hostile-input fixtures: path traversal in slug or
date, absolute-path injection, control characters, locale-dependent
uppercase under a UTF-8 locale (asserting `LC_ALL=C` behavior) — each exits
non-zero, creates no path, and prints a sanitized message; plus a direct
unit test of the containment check with a grammar-valid composed path only
containment could refuse. `tests/test-obs-consume.sh` mirrors the bar on
the consume surface: hostile UID and spec-identifier arguments (traversal,
glob, newline injection into the `Consumed-by:` line) refuse cleanly, and
a symlinked fragment is refused before annotate or move.

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
fixture pattern used by the gate evaluator's tests); a hostile *legacy*
line interleaved by render/drain gets the same treatment.
`tests/test-obs-consume.sh`: consuming a fragment with hostile content
moves it verbatim with no expansion side effects.

### REQ-D1.4 — standing CI guard [test]

Task 2's seeded-violation fixtures: bad name, traversal-shaped name,
non-calendar date, multi-entry file, missing entry line, free-prose body,
unrecognized metadata key, duplicate UID across `entries/` + `archive/`,
and an unexpected top-level file under `specs/_observations/` each fail
`check:obs` (run under `LC_ALL=C`); a clean tree passes; the task is wired
into the aggregate `mise run check` that CI runs.

## REQ-E — Migration and cross-spec coordination

### REQ-E1.1 — dedup then freeze [manual + test]

`[manual]` The migration PR lists every removed line beside its `archive.md`
consumed-by record; the human verifies the one-to-one pairing before merge,
re-checks the recomputed set immediately before merging (appends continue
until the flip lands), and keeps any candidate plausibly a legitimate
textual re-occurrence.
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

`[design-level]` The Deferred entry with the free-text gate
`**Gate:** the output-hygiene carve-out amendment has landed` exists in
`tasks.md` — plain prose after `**Gate:**`, per the accumulator-taxonomy
grammar; wrapped in `GATE(when: …)` it would parse as a structured gate
with an unrecognized atom and report as MALFORMED instead of surfacing.
As a free-text gate the drain pass surfaces (not evaluates) it
on every pass until the human resolves it (free-text surfacing covered
generically by `tests/test-drain-gates.sh`), so the hold stays visible for
its whole window — including after this spec completes.
`[manual]` The human performs the output-hygiene carve-out amendment and
holds its Tasks 1–2 undispatched until then.
