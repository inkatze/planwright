# The Inception Bundle Format

**Format-version:** 1.0

This document is the canonical, normative definition of the inception bundle:
the single source the inception validator, the renderer, and the `/inception`
skill parse (inception REQ-I1.1). The bundle is a sibling of the four-file spec
format, not a reuse of it (inception D-1): it inherits the meta-spec's
conventions ([spec-format.md](spec-format.md)) — stable IDs, append-only
supersession, mirrored status headers, a changelog, a sources register —
without its files. A reader should be able to author a compliant bundle from
this document alone.

Citations: inception REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5,
REQ-C1.6, REQ-C1.7, REQ-C1.8, REQ-C1.9, REQ-C1.10, REQ-C1.11, REQ-E1.2,
REQ-E1.5, REQ-I1.1, REQ-I1.4 · inception D-1, D-18.

## Overview

An inception bundle lives at the root of a venture repository and comprises
exactly five authored files plus two directories (REQ-C1.1):

| Entry | Role |
| --- | --- |
| `brief.md` | The opportunity brief and the venture's state home: status, success metric, kill criteria, gate decider, tracks, sources register, gate log, changelog. |
| `disciplines.md` | The discipline map, the staffing table, and the stakeholder / decision-rights map. |
| `assumptions.md` | The assumption and risk register: falsifiable, graded, thresholded entries. |
| `decisions.md` | The decision backlog: open forks and taken decisions, MADR-shaped. |
| `plan.md` | The validation plan: capped, evaluable tasks tracing to assumptions and forks. |
| `spikes/` | Disposable prototype work. Findings graduate; spike code never does. |
| `exports/` | Derived, regenerable render output. Never hand-edited, never the truth store. |

The file set defines bundle membership, not the repository root: scaffold
files, code, and a README may sit beside it unvalidated. The two directories
are created on first use; their absence is not a finding (git does not track
empty directories).

The five `.md` files open with the same header block, the file-role token
drawn from `Brief | Disciplines | Assumptions | Decisions | Plan`:

```markdown
# <Venture title> — <File role>

**Status:** <Exploring|On-hold|Graduated|Killed|Abandoned>
**Last reviewed:** <YYYY-MM-DD>
**Format-version:** 1.0
```

`brief.md` is the authoritative home of `Status:`; the other four mirror it,
updated in the same change that changes the status. `Format-version:` must be
identical across the five files. A mirror mismatch of either line is a
validation finding. `Last reviewed:` is per-file, bumped when that file is
materially edited. `<Venture title>` is free prose; the venture *identifier*
is the venture repository's directory name (under the configured
`ventures_root`) and is not restated inside the bundle.

## Identifiers and ID grammar

The venture identifier matches the anchored, full-string pattern
`^[a-z0-9][a-z0-9-]*$`, maximum length 64, validated before any use in paths,
branch names, or repository names.

Register IDs are typed, integer-numbered, and never reused:

| ID | Names | Lives in |
| --- | --- | --- |
| `A-<n>` | an assumption | `assumptions.md` |
| `DEC-<n>` | a decision (open fork or taken decision) | `decisions.md` |
| `T-<n>` | a validation-plan task | `plan.md` |
| `KC-<n>` | a kill criterion | `brief.md` |

`<n>` is a positive integer, assigned in authoring order, append-only. No two
entries of a type may share a number, live or superseded; gaps in a sequence
are legal (numbers are never reassigned). IDs are stable forever (REQ-C1.7):
a changed-meaning entry mints a new ID and marks the old one superseded — for
an H3 entry, a final `- **Superseded-by:** <ID> (<date>)` bullet; for a
`KC-<n>` bullet, the same marker appended to the bullet text. The old entry's
body is never edited. Citations to a superseded ID stay valid as lineage.

**Field conventions (all H3 entry templates below).** Field bullets appear in
template order; every field is required unless marked optional. A required
field with nothing to record carries the literal `none`, never an omission
(status-gated exceptions are stated per file).

**Track labels** (REQ-C1.11) are optional. A label matches
`^[a-z0-9][a-z0-9-]*$`, maximum length 32. A venture that uses tracks declares
them in `brief.md` under `## Tracks`, one bullet per label with a one-line
description; assumptions, decisions, and plan tasks may then carry a
`- **Track:** <label>` field (only in a tracked venture) referencing a
declared label. A single-track venture declares no tracks and writes no
`Track:` fields. A track that ends gets its declaration bullet annotated
`— graduated <date>` or `— ended <date> (<reason>)`; gate records may carry
per-track outcomes, and partial graduation keys on these labels.

## Venture lifecycle

Five statuses (REQ-C1.6). Abandoned and On-hold are first-class, not
annotations:

| Status | Meaning |
| --- | --- |
| `Exploring` | Live venture: elicitation, validation, or gate cycles in progress. The initial status. |
| `On-hold` | Parked by a gate Hold outcome or operator act; kill criteria keep their dates. |
| `Graduated` | Closed by graduation: every declared track graduated or explicitly ended (annotated as above). Partial graduation does not close the venture; it stays `Exploring` until closed explicitly. |
| `Killed` | Closed by a gate Kill outcome, recorded in the gate log. |
| `Abandoned` | Closed by operator declaration without a gate run. |

Gate outcomes map to status as follows: `Graduate` closes the venture (or
only its track) as above; `Hold` moves it to `On-hold`; `Recycle` keeps it
`Exploring` (the registers and plan are re-scoped); `Kill` moves it to
`Killed`. Only the record's top-level `Outcome:` moves the venture status;
per-track outcomes annotate tracks and never change `Status:`. An `On-hold`
venture resumes to `Exploring` by operator act, or closes via a gate run or
operator declaration. Killed and Abandoned ventures are archived with a brief
post-mortem note appended to the changelog. Every status change is a
changelog entry. No transition out of `Graduated`, `Killed`, or `Abandoned`
is accepted; a revived idea starts a new venture citing the old one in its
sources register.

**Kill criteria** are pre-committed state-plus-date pairs in `brief.md` under
`## Kill criteria`. The section opens with the venture's named gate decider
(REQ-C1.6), then one bullet per criterion:

```markdown
**Gate decider:** <a Decides name from the stakeholder map>

- **KC-1:** <observable state that must hold> — by <YYYY-MM-DD>
```

A criterion whose date passes with the state unmet is *tripped*; one whose
date is within 30 days is *approaching*. Tripped and approaching criteria
surface at every gate run and status view; a tripped criterion prompts
kill-or-re-scope and never auto-kills.

## `brief.md`

Required sections, in this relative order: the header block, `## Opportunity`,
`## Success metric`, `## Appetite` (the time and money the operator will
spend before the gate forces a decision), `## Kill criteria`, `## Tracks`
(only when tracks are declared), `## Existing alternatives` (landscape),
`## Business viability` (market, pricing, channels), `## Strategy fit`
(adjacent initiatives, inherited constraints), `## Sources`, `## Gate log`,
`## Changelog`. Sections a minor version or a venture adds may appear between
required ones without breaking the order check. An optional
`## Minimum core check` may appear anywhere before `## Sources`; its content
is a convenience render the validator ignores.

`## Opportunity` carries four bolded field bullets (REQ-C1.2), in order:

- `**Framing:**` the opportunity framing, with evidence.
- `**Who hurts:**` stated as a job-in-circumstance.
- `**No-gos & sketch:**` the no-gos and a rough solution sketch.
- `**Chain:**` the actor → behavior change → goal chain.

The three landscape/viability/fit sections and the non-core `## Opportunity`
fields are **prompt** content: they guide elicitation and may be skipped.
Only the minimum core (below) is mandatory. A skipped prompt section keeps
its heading and replaces its body with an explicit one-line reason, never
silently and never by omitting the heading:

```markdown
_Skipped: <one-line reason>._
```

The skip form applies to prompt sections only; register entry fields are
never skipped (they carry `none` per the field conventions instead).

**Sources register** (REQ-C1.9). `## Sources` lists the seed and evidence
material the venture rests on, one bullet per source:

```markdown
- **<name>** — <what it is> — <where it lives, or `held out: <reason>` when
  the repo's visibility does not match the material's sensitivity>
```

The bold lead is the entry's name; citations elsewhere in the bundle refer to
entries by that name.

**Gate log.** `## Gate log` holds the gate records, newest last, in the form
defined under *Gate records* below.

**Changelog.** `## Changelog` holds dated bullets, appended chronologically:
status changes, supersessions, format-version migrations, post-mortem notes.

## `disciplines.md`

Three H2 sections, in order, after the header block:

**`## Discipline map`.** One row per discipline the venture touches; the
open-decision cell references `decisions.md` entries:

```markdown
| Discipline | Touches | Undecided decisions |
| --- | --- | --- |
| <discipline> | <what it touches here> | <DEC-IDs, or none> |
```

**`## Staffing table`** (one row per touched discipline; the staffing token
is `agent-persona | named-human | unstaffed`):

```markdown
| Discipline | Staffing | Card / person |
| --- | --- | --- |
| <discipline> | <token> | <card name, person, or none> |
```

At staffing time the skill auto-files every unstaffed senior discipline
(senior: one whose calls carry stake for this venture — a staffing-table
judgment) as a coverage-risk entry in the assumption register; a deliberate
zero-seat run collapses those into a single register entry, "personas waived
(zero-seat); N disciplines unstaffed".

**`## Stakeholder map`** (REQ-C1.10). One row per decision area: who
**decides** (a named person), who must be **aligned**, who is **informed**.
Multiple names in a cell are comma-separated. The venture's gate decider and
every `Deciders:` name must appear in a Decides cell; alignment-task targets
name a row.

```markdown
| Decision area | Decides | Aligned | Informed |
| --- | --- | --- | --- |
| <area> | <name> | <names or none> | <names or none> |
```

## `assumptions.md`

After the header block, one H3 block per assumption (REQ-C1.3). The
`Statement:` keywords and semicolons are literal and mandatory:

```markdown
### A-<n> — <short name>

- **Statement:** believe <claim>; verify <test>; measure <observable>;
  right if <pre-committed condition>.
- **Risk-if-wrong:** <what breaks>
- **Risk-tag:** <value | usability | feasibility | viability>
- **Threshold:** <pass/fail line, fixed before the test runs, expressible as a
  fail condition>
- **Evidence:** <grade> — <a sources-register name, or `T-<n> findings`>
- **Blocking:** <yes | no>
- **Tasks:** <T-IDs, or none>
- **Status:** <open | testing | validated | invalidated | waived>
- **Track:** <label>            (only in a tracked venture; optional)
```

`Blocking: yes` means the venture cannot responsibly graduate while this
assumption is unresolved; gate readiness keys on it. `Threshold:` and
`Evidence:` may carry the literal `none` only while `Status:` is `open`
(nothing tested yet); `validated` and `invalidated` require a real threshold
and a cited, graded evidence field. `waived` records its one-line reason in
the `Status:` field body: `waived — <reason>`. A coverage-risk entry (the
auto-filed unstaffed-discipline case) uses this same form, its `Statement:`
carrying the coverage claim and its `Threshold:`/`Evidence:` at `none` while
open. A task's findings document is committed in the venture repo and cited
as `T-<n> findings`.

The **evidence grade** is one token from the commitment-weighted ladder,
ordered weakest to strongest:

`synthetic` < `opinion` < `stated-intent` < `costly-signal` < `behavior`

`synthetic` is the named grade for simulated evidence (persona-panel output):
above pure reasoning — which is not citable evidence; an entry backed only by
reasoning carries `Evidence: none` — and below a real human's stated opinion
(REQ-I1.4). At the gate, a `synthetic`-graded entry cannot count as `pass`
toward a `Graduate` outcome on a value- or usability-tagged (desirability)
assumption. Grading semantics — what earns each grade — are governed by the
evidence-quality doctrine (a planned planwright rule doc; until it lands,
these tokens, this ordering, and that exclusion are the whole normative
surface).

## `decisions.md`

The decision *backlog*: open forks are first-class entries, not only decisions
already taken. After the header block, one H3 block per decision, shaped after
MADR (Markdown Any Decision Records) (REQ-C1.4):

```markdown
### DEC-<n> — <decision title>

- **Status:** <open | decided | deferred>
- **Door:** <one-way | two-way>
- **Discipline:** <owning discipline, from the discipline map>
- **Deciders:** <named people, each in a Decides cell of the stakeholder map>
- **Options:**
  - <option> — <one-line tradeoff>
- **Outcome:** <the decision and date, when decided; open questions otherwise>
- **Consequences:** <what follows from the outcome>
- **Feed-forward:** <what future spec or artifact consumes this decision>
- **Track:** <label>            (only in a tracked venture; optional)
```

`Options:` holds one indented sub-bullet per considered alternative. `Door:`
classifies reversibility; one-way-door decisions are always human-authority
(reserved to a named human, never the agent). On a remote-backed venture,
merging the change that records an `Outcome:` is that decision's
ratification; on a local-only venture the operator's recording commit is. A
`deferred` decision states its revisit condition in the `Outcome:` field.

## `plan.md`

After the header block, one H3 block per validation task (REQ-C1.5):

```markdown
### T-<n> — <title>

- **Kind:** <spike | research | analysis | demand-signal | alignment>
- **Tests:** <A-IDs and/or DEC-IDs; every task traces to at least one>
- **Target:** <a stakeholder-map row>   (required when Kind is alignment;
  omitted otherwise)
- **Done when:** <conditions an agent can evaluate>
- **Cap:** <pre-committed time or cost budget>
- **Status:** <planned | running | delivered | accepted | dropped>
- **Track:** <label>            (only in a tracked venture; optional)
```

The cap is the budget only; the threshold it buys evidence against lives on
the linked assumption, and the pair is read together at gate time. Tasks are
ordered lowest-confidence, highest-blocking assumptions first, the single
limiting constraint (the one assumption gating the others) as tie-breaker.
`delivered` means findings are written and awaiting human acceptance;
register updates land only on `accepted`. A task that exhausts its cap
without resolution stops and surfaces, making "Hold because tests got
expensive" detectable.

## `spikes/` and `exports/`

Spike code lives in `spikes/`, marked disposable. Findings graduate into the
registers (this file-level sense — findings copied into the registers — is
distinct from the `Graduate` gate outcome and the `Graduated` status);
prototype code never graduates. `exports/` holds derived render output only:
the HTML export (`exports/venture.html`) and the materialized frame,
regenerated by the renderer via the pre-commit regeneration step the venture
scaffold installs at repo creation, never hand-edited, never cited as
evidence.

## The frame

The frame is the specification every persona seat consumes (inception D-18):
a derived document compiled from the bundle at fan-out time, confirmed by the
human at Gate 1, and regenerable at will. (Gate 1 — the `/inception` skill's
pre-fan-out frame-and-staffing confirmation — and persona seats are skill
concepts; this doc fixes only the frame's content. Gate 1 is not a
`### Gate <n>` log entry.) When materialized it lives at `exports/frame.md`
(derived content). It is not one of the five authored files and is never
edited by hand. Template, in order:

1. **Problem statement** — from the brief's opportunity framing.
2. **Evidence pointers** — the sources-register entries in play.
3. **Constraints** — appetite, no-gos, inherited constraints.
4. **Door-classified decisions** — the open `DEC-<n>` entries with their
   `Door:` class.
5. **Discipline staffing table** — from `disciplines.md`, as staffed for this
   run.
6. **Current success-metric and kill-criteria state** — the metric, each
   `KC-<n>` with clear / approaching / tripped.

## The minimum core

The gate-enforced floor (REQ-C1.8). A bundle meets the minimum core when:

1. every blocking assumption is enumerated in `assumptions.md`
   (`Blocking: yes`, any status);
2. every open fork is recorded as a `DEC-<n>` entry;
3. at least one kill criterion is set as a state-plus-date pair;
4. the success metric is named in `brief.md`.

The validator checks the structural shadow of 1–2 (registers present and
parseable, required fields carried) plus 3–4 as entry presence; whether the
*enumeration* is complete is the gate decider's substantive judgment, aided
by the gate's completeness check. Everything else is a prompt: skippable with
an explicit one-line reason (`_Skipped: …_`), never silently.

## Gate records

Gate runs are recorded in `brief.md` `## Gate log` as dated, structured,
machine-readable entries — the venture's audit trail. One H3 block per run,
fields one per line, in this order:

```markdown
### Gate <n> — <YYYY-MM-DD>

Outcome: <Graduate | Hold | Recycle | Kill>
Date: <YYYY-MM-DD>
Decider: <the venture's gate decider, from the stakeholder map>
Evidence: <comma-separated `A-<n> (<grade>)` items>
Thresholds: <comma-separated `A-<n> pass | fail | waived` items>
Kill-criteria: <comma-separated `KC-<n> clear | approaching | tripped` items>
Tracks: <comma-separated `<label>=<Outcome token>` items>
Rationale: <free text, one or more lines, always last>
```

The heading date and `Date:` must match; `Date:` is authoritative for
parsers. `Thresholds:` covers every `Blocking: yes` assumption plus any
other assumption cited in `Evidence:`; `Kill-criteria:` covers every
`KC-<n>`. `Tracks:` is optional and appears only in a tracked venture
(REQ-C1.11); its outcome tokens are the four `Outcome:` tokens.
`Rationale:` runs to the end of the block. `<n>` is a positive integer,
sequential, append-only. Gate records and register IDs are untouchable by
stakeholder-surface edits and harvested external feedback (the adapter
seam); the validator guards them.

## Format-version rules

The format is versioned `<major>.<minor>`, declared by every authored file's
`Format-version:` header (REQ-C1.7). This document defines 1.0.

- **Additive within a major.** New fields and sections are optional; existing
  fields are never renamed or repurposed. An additive change bumps the minor
  version. A reader encountering an unknown field or section within a
  supported major ignores it and parses on.
- **Readers gate on the major.** The validator, the renderer, and the skill
  each refuse an unsupported major, and a missing or unparseable
  `Format-version:` line, with a fail-closed non-zero exit and a
  plain-language message naming the found and supported versions — never a
  silent misparse. The renderer and skill invoke the validator's check
  rather than re-implementing it.
- **Breaking changes.** A breaking change increments the major version and
  owns its migration path, shipped as a new version of this document.

A bundle migrates by updating its `Format-version:` lines and conforming to
the new rules; the migration records itself in the bundle's changelog.
