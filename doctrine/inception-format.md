# The Inception Bundle Format

**Format-version:** 1.0

This document is the canonical, normative definition of the inception bundle:
the single source the inception validator, the renderer, and the `/inception`
skill parse (inception REQ-I1.1). The bundle is a sibling of the four-file spec
format, not a reuse of it (inception D-1): it inherits the meta-spec's
conventions — stable IDs, append-only supersession, mirrored status headers, a
changelog, a sources register — without its files. A reader should be able to
author a compliant bundle from this document alone.

Citations: inception REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5,
REQ-C1.6, REQ-C1.7, REQ-C1.8, REQ-C1.9, REQ-C1.10, REQ-C1.11, REQ-I1.1 ·
inception D-1, D-18.

## Overview

An inception bundle lives at the root of a venture repository and comprises
exactly five authored files plus two directories (REQ-C1.1):

| Entry | Role |
| --- | --- |
| `brief.md` | The opportunity brief and the venture's state home: status, success metric, kill criteria, tracks, sources register, gate log, changelog. |
| `disciplines.md` | The discipline map, the staffing table, and the stakeholder / decision-rights map. |
| `assumptions.md` | The assumption and risk register: falsifiable, graded, thresholded entries. |
| `decisions.md` | The decision backlog: open forks and taken decisions, MADR-shaped. |
| `plan.md` | The validation plan: capped, evaluable tasks tracing to assumptions and forks. |
| `spikes/` | Disposable prototype work. Findings graduate; spike code never does. |
| `exports/` | Derived, regenerable render output. Never hand-edited, never the truth store. |

The five `.md` files open with the same header block:

```markdown
# <Venture title> — <File role>

**Status:** <Exploring|On-hold|Graduated|Killed|Abandoned>
**Last reviewed:** <YYYY-MM-DD>
**Format-version:** 1.0
```

`brief.md` is the authoritative home of `Status:`; the other four mirror it.
`Last reviewed:` is per-file, bumped when that file is materially edited.

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

`<n>` is a positive integer, assigned in authoring order, append-only. IDs are
stable forever (REQ-C1.7): a changed-meaning entry mints a new ID and marks the
old one `**Superseded-by: <ID>** (<date>)`; the old entry's body is never
edited. Citations to a superseded ID stay valid as lineage.

**Track labels** (REQ-C1.11) are optional. A label matches
`^[a-z0-9][a-z0-9-]*$`, maximum length 32. A venture that uses tracks declares
them in `brief.md` under `## Tracks`, one bullet per label with a one-line
description; assumptions, decisions, and plan tasks may then carry a
`- **Track:** <label>` field referencing a declared label. A single-track
venture declares no tracks and writes no `Track:` fields. Gate records may
carry per-track outcomes; partial graduation keys on labels where present.

## Venture lifecycle

Five statuses (REQ-C1.6). Abandoned and On-hold are first-class, not
annotations:

| Status | Meaning |
| --- | --- |
| `Exploring` | Live venture: elicitation, validation, or gate cycles in progress. The initial status. |
| `On-hold` | Parked by a gate Hold outcome or operator act; kill criteria keep their dates. |
| `Graduated` | Closed by graduation: every live track graduated or explicitly ended. Partial graduation does not close the venture; it stays `Exploring` until closed explicitly. |
| `Killed` | Closed by a gate Kill outcome, recorded in the gate log. |
| `Abandoned` | Closed by operator declaration without a gate run. |

Killed and Abandoned ventures are archived with a brief post-mortem note
appended to the changelog. Every status change is a changelog entry. No
transition out of `Graduated`, `Killed`, or `Abandoned` is accepted; a revived
idea starts a new venture citing the old one in its sources register.

**Kill criteria** are pre-committed state-plus-date pairs in `brief.md` under
`## Kill criteria`, one bullet per criterion:

```markdown
- **KC-1:** <observable state that must hold> — by <YYYY-MM-DD>
```

A criterion whose date passes with the state unmet is *tripped*. Tripped and
approaching criteria surface at every gate run and status view; a tripped
criterion prompts kill-or-re-scope and never auto-kills.

## `brief.md`

Required sections, in order: the header block, `## Opportunity`, `## Success
metric`, `## Appetite`, `## Kill criteria`, `## Tracks` (only when tracks are
declared), `## Minimum core check` (optional; the gate recomputes it), the
prompt sections below, `## Sources`, `## Gate log`, `## Changelog`.

`## Opportunity` carries the framing fields (REQ-C1.2), each an H3 or bolded
bullet: opportunity framing with evidence; who-hurts stated as a
job-in-circumstance; no-gos and a rough solution sketch; and the
actor-to-behavior-change-to-goal chain. The prompt sections are
`## Existing alternatives` (landscape), `## Business viability` (market,
pricing, channels), and `## Strategy fit` (adjacent initiatives, inherited
constraints).

Only the minimum core (below) is mandatory. Any other section or field may be
skipped with an explicit one-line reason in place of its body, never silently:

```markdown
_Skipped: <one-line reason>._
```

**Sources register** (REQ-C1.9). `## Sources` lists the seed and evidence
material the venture rests on, one bullet per source: a name, what it is, and
where it lives (or "held out": named but not stored, when the repo's
visibility does not match the material's sensitivity). Citations elsewhere in
the bundle refer to these entries by name.

**Gate log.** `## Gate log` holds the gate records, newest last, in the form
defined under *Gate records* below.

**Changelog.** `## Changelog` holds dated bullets, appended chronologically:
status changes, supersessions, format-version migrations, post-mortem notes.

## `disciplines.md`

Three parts, in order, after the header block:

1. **Discipline map.** One row per discipline the venture touches:
   the discipline, what it touches in this venture, and every decision the
   venture touches but does not decide (recorded as an open `DEC-<n>` entry
   and referenced here by ID).
2. **Staffing table.** One row per touched discipline: `agent-persona` (with
   the card name), `named-human` (with the person), or `unstaffed`. Every
   unstaffed senior discipline auto-files an assumption-register risk; a
   deliberate zero-seat run collapses those into a single "personas waived
   (zero-seat); N disciplines unstaffed" row.
3. **Stakeholder / decision-rights map** (REQ-C1.10). One row per decision
   area: who **decides** (a named person), who must be **aligned**, who is
   **informed**. The gate decider and alignment-task targets reference rows of
   this map; a gate record's `Decider:` must name a *decides* entry.

```markdown
| Decision area | Decides | Aligned | Informed |
| --- | --- | --- | --- |
| <area> | <name> | <names or none> | <names or none> |
```

## `assumptions.md`

After the header block, one H3 block per assumption (REQ-C1.3):

```markdown
### A-<n> — <short name>

- **Statement:** believe <claim>; verify <test>; measure <observable>;
  right if <pre-committed condition>.
- **Risk-if-wrong:** <what breaks>
- **Risk-tag:** <value | usability | feasibility | viability>
- **Threshold:** <pass/fail line, fixed before the test runs, expressible as a
  fail condition>
- **Evidence:** <grade> — <citation into the sources register or a task
  finding; or none>
- **Blocking:** <yes | no>
- **Tasks:** <T-IDs, or none>
- **Status:** <open | testing | validated | invalidated | waived>
- **Track:** <label>            (only in a tracked venture; optional)
```

The **evidence grade** is one token from the commitment-weighted ladder,
ordered weakest to strongest:

`reasoning` < `synthetic` < `opinion` < `stated-intent` < `costly-signal` <
`behavior`

`synthetic` is the named grade for simulated evidence (persona-panel output):
above pure reasoning, below a real human's stated opinion. A `synthetic`-graded
entry cannot satisfy a Graduate threshold on a value- or usability-tagged
(desirability) assumption. Grading semantics — what earns each grade — are
governed by the evidence-quality doctrine; this format fixes the tokens, the
ordering, and that exclusion. A `validated` or `invalidated` status requires a
cited, graded `Evidence:` field; `waived` requires a one-line reason in the
field body.

## `decisions.md`

The decision *backlog*: open forks are first-class entries, not only decisions
already taken. After the header block, one H3 block per decision, MADR-shaped
(REQ-C1.4):

```markdown
### DEC-<n> — <decision title>

- **Status:** <open | decided | deferred>
- **Door:** <one-way | two-way>
- **Discipline:** <owning discipline, from the discipline map>
- **Deciders:** <named people, from the stakeholder map>
- **Options:** <the considered alternatives, each with a one-line tradeoff>
- **Outcome:** <the decision and date, when decided; open questions otherwise>
- **Consequences:** <what follows from the outcome>
- **Feed-forward:** <what future spec or artifact consumes this decision>
- **Track:** <label>            (optional)
```

`Door:` classifies reversibility; one-way-door decisions are always
human-authority. On a remote-backed venture, merging the change that records
an `Outcome:` is that decision's ratification. A `deferred` decision states
its revisit condition in the `Outcome:` field.

## `plan.md`

After the header block, one H3 block per validation task (REQ-C1.5):

```markdown
### T-<n> — <title>

- **Kind:** <spike | research | analysis | demand-signal | alignment>
- **Tests:** <A-IDs and/or DEC-IDs; every task traces to at least one>
- **Done when:** <conditions an agent can evaluate>
- **Cap:** <pre-committed time or cost cap, stated alongside the threshold the
  linked assumption tests>
- **Status:** <planned | running | delivered | accepted | dropped>
- **Track:** <label>            (optional)
```

Tasks are ordered lowest-confidence, highest-blocking assumptions first; the
single limiting constraint — the one assumption gating the others — is the
tie-breaker. `delivered` means findings are written and awaiting human
acceptance; register updates land only on `accepted`. A task that exhausts its
cap without resolution stops and surfaces, making "Hold because tests got
expensive" detectable.

## `spikes/` and `exports/`

Spike code lives in `spikes/`, marked disposable. Findings graduate into the
registers; prototype code never graduates. `exports/` holds derived render
output only (the HTML export, the materialized frame): regenerated by the
renderer, staged by the pre-commit step, never hand-edited, never cited as
evidence.

## The frame

The frame is the specification every persona seat consumes (inception D-18):
a derived document compiled from the bundle at fan-out time, confirmed by the
human at Gate 1, and regenerable at will. When materialized it lives at
`exports/frame.md` (derived content). It is not one of the five authored files
and is never edited by hand. Template, in order:

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

Everything else is a prompt: skippable with an explicit one-line reason
(`_Skipped: …_`), never silently. The gate evaluates the core from the
registers; a stored `## Minimum core check` section is a convenience render,
not the source of truth.

## Gate records

Gate runs are recorded in `brief.md` `## Gate log` as dated, structured,
machine-readable entries — the venture's audit trail. One H3 block per run,
fields one per line, in this order:

```markdown
### Gate <n> — <YYYY-MM-DD>

Outcome: <Graduate | Hold | Recycle | Kill>
Date: <YYYY-MM-DD>
Decider: <a decides entry from the stakeholder map>
Evidence: <A-IDs with grades, e.g. A-3 (costly-signal), A-5 (behavior)>
Thresholds: <per evaluated assumption: A-<n> pass | fail | waived>
Kill-criteria: <per criterion: KC-<n> clear | approaching | tripped>
Tracks: <per-track outcomes, e.g. checkout=Graduate, billing=Hold>
Rationale: <free text, one or more lines, last>
```

`Tracks:` appears only in a tracked venture. `<n>` is a positive integer,
sequential, append-only. Gate records and register IDs are untouchable by
stakeholder edits and adapter re-imports; the validator guards them.

## Format-version rules

The format is versioned `<major>.<minor>`, declared by every authored file's
`Format-version:` header (REQ-C1.7). This document defines 1.0.

- **Additive within a major.** New fields and sections are optional; existing
  fields are never renamed or repurposed. An additive change bumps the minor
  version. A reader encountering an unknown field or section within a
  supported major ignores it and parses on.
- **Readers gate on the major.** The validator, the renderer, and the skill
  each check the header before parsing. On an unsupported major, or a missing
  or unparseable `Format-version:` line, they fail closed — a non-zero exit
  and a plain-language message naming the found and supported versions — and
  never silently misparse. The renderer and skill defer to the validator's
  check rather than re-implementing it.
- **Breaking changes.** A breaking change increments the major version and
  owns its migration path, shipped as a new version of this document.

A bundle migrates by updating its `Format-version:` lines and conforming to
the new rules; the migration records itself in the bundle's changelog.
