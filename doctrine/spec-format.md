# The Four-File Spec Format (Meta-Spec)

**Format-version:** 2

This document is the canonical, versioned definition of the planwright spec
format: version 1 (the body of this document) and version 2 (its own
section below, stated as deltas). A spec bundle declares the format-version
it targets; the validator keys its rules off that declaration, and a future
format change ships as a new version of this document rather than as a
silent breaking change. A reader should be able to author a compliant
bundle, at either version, from this document alone.

Citations: REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6,
REQ-A1.7, REQ-A1.8, REQ-B2.2 · D-1, D-20, D-25, D-40, D-45.

## Overview

A spec is a directory `specs/<spec>/` containing exactly four authored files:

| File | Role |
| --- | --- |
| `requirements.md` | What must be true: stable REQ-IDs in SHALL/MUST language, the bundle's Status, the Changelog, the Sources. |
| `design.md` | Why it is shaped this way: stable D-IDs, each a recorded decision with alternatives and rationale. |
| `tasks.md` | How it gets built, and where the build currently stands: the canonical orchestration state record. |
| `test-spec.md` | How each requirement is verified: every REQ pinned to at least one verification path. |

A fifth file, `kickoff-brief.md`, is added by `/spec-kickoff` at sign-off. It
is not part of the authored bundle (it records the walkthrough, so it cannot
be authored with it), but its structure is part of this format and is
specified below.

All four files open with the same header block:

```markdown
# <Spec title> — <File role>

**Status:** <Draft|Ready|Active|Done|Retired|Superseded>
**Last reviewed:** <YYYY-MM-DD>
**Format-version:** 1
```

`requirements.md` is the authoritative home of `Status:`; the other three
mirror it and are kept in sync at sign-offs and amendments. `Last reviewed:`
is per-file and is bumped whenever that file is materially reviewed or
edited. A `Superseded` bundle additionally carries a mandatory
`**Superseded-by:** specs/<spec>/` pointer line in the header block.

**Header-block extent.** The header block is the leading region of the file made
up of nothing but the H1 title line, `**<Key>:** <value>` lines, and blank lines;
it ends at the first line that is none of those. Blank lines between or among the
key lines do not end it, and a column-0 fence line does end it (a fence is none
of the three). A conforming file opens with its H1, but the H1 is not what
*constitutes* the block: parsers accept a file that opens with the key lines
themselves, so partial files and fixtures parse rather than failing closed for a
reason the format does not care about. The extent is **positional**: a file has at most one
header block, the one opening its content, so a key-line run appearing anywhere
later — in body prose or inside a fence — is not a header block at all.
`Format-version:` and `Status:` are recognized only inside the block; a body line
carrying either literal is inert content, and it never shadows the real
declaration nor masks a missing one. A block is **malformed** when there is no
such region at all, or when it reaches end of file with no body content after it;
what a consumer does with a malformed block is that consumer's rule (the content
anchor's is stated with the `Status` exclusion below).

**A duplicate declaration of either load-bearing key is unparseable.** More than
one `Format-version:` or `Status:` line inside the header block makes that
declaration unparseable: every parser keyed on it fails closed (never a
positional winner, never a fall-open to the version-1 write path), and the
validator reports an error at every status, Draft included. Two contradictory
declarations mean the value is unknown, and no position — first or last — is an
honest way to pick one. `scripts/spec-parse.sh` is where the format's parsers get
this: its header parse is strict for exactly these two keys and refuses on a
duplicate, and non-load-bearing keys keep first-match-wins.

## Spec identifiers

The `<spec>` segment (used in `specs/<spec>/`, branch names, worktree paths,
lock paths, and printed launch commands) matches the anchored, full-string
pattern `^[a-z0-9][a-z0-9-]*$`, maximum length 64. Substring matching is
non-conforming: an identifier is valid only if the whole string matches. No
skill or hook interpolates a failing identifier into a path or command;
identifiers proposed by accumulator contents (seeds) are re-validated at
consumption before any interpolation.

Direct children of `specs/` with a leading underscore are **reserved
non-spec accumulators** (`_pending/`, `_observations/`). They are never
validated as bundles, but their names must match `^_[a-z0-9][a-z0-9-]*$`
(≤64): exemption from bundle validation is not exemption from hostile-name
screening.

## Path-placeholder convention

Documentation and skill prose write path and identifier placeholders in
angle brackets: `<spec>`, `<id>`, `<branch-suffix>`, `<date>`. A placeholder
stands for exactly one segment; literal text outside the brackets is literal.

## Fenced illustration

A code-fence line toggles illustration mode, and **no line inside a fence parses
as any element of this format, in any parser of spec bundles**. Headings,
requirement bullets, reference bullets, gate entries, header-block key lines,
task-definition field bullets, and `Dependencies:`/`Citations:` tokens are the
illustrative cases; the rule is universal rather than an enumeration, because a
fenced line is example text and a format that lists its exceptions grows a new
one with every parser. This is the single normative definition: fence-aware
parsers cite it instead of each re-deriving the rule, which is how the shipped
divergence arose.

**The marker is pinned to what the parsers lex:** a line beginning, at column 0,
with three or more backticks. Indentation matters — an indented fence is ordinary
content, which is how a fence can be shown as an example without opening one. A
tilde fence (`~~~`) is deliberately *not* a toggle: the parsers are line-oriented
awk and one marker keeps the lexer trivial, so bundles write their fences with
backticks and a tilde fence protects nothing inside it.

An unbalanced column-0 fence count is a **malformation, never a silent
illustration-to-end-of-file**. The validator flags the file, and the shared parse
library (`scripts/spec-parse.sh`) treats end of file inside an open fence as
malformed input and fails closed, so the derivation path is guarded where it
parses and not only where it validates. One stray fence must not be able to
swallow the remainder of a bundle from every reader with no signal at all.

## Decided rules over enumerated claims

Anchored deliverable prose — REQ bodies, decision text, task fields,
test-spec entries — states **decided rules**, not enumerated counts or corpus
lists whose truth depends on a surface outside the bundle (anchor-integrity
D-8, REQ-E1.1). Write "every doctrine-relative link of this class is a
violation", not "the sole real violation is `X`"; write "the fixture corpus is
whatever the sweep's baseline froze", not "the corpus is these N fixtures". A
decided rule ages with the decision it records. An enumeration goes stale the
moment the surface it counted changes, and it goes stale silently, inside
content the anchor has already frozen and a reader is entitled to trust.

Where an enumeration is genuinely unavoidable, it follows the cite-don't-copy
convention (cite the surface rather than transcribing it) or carries its own
cross-check naming what must be re-verified and when. `/spec-draft` at
drafting and `/spec-kickoff` at sign-off run the enumeration cross-check,
verifying each enumeration against the surface it enumerates or converting it
to a decided rule (REQ-E1.2).

## `requirements.md`

Required sections, in order: the header block, `## Goal`, `## Scope` (with
`### In scope` and `### Out of scope`), one or more REQ group sections,
`## Changelog`, `## Sources`.

**REQ-ID convention.** Requirement IDs are `REQ-<Group><N>.<M>` (for example
`REQ-A1.2`), where `<Group>` is a capital letter naming a thematic group,
declared as a section heading `## REQ-<Group> — <theme>`. Each requirement is
a single top-level bullet beginning `- **REQ-<id>**` and written in SHALL /
MUST / SHALL NOT language. IDs are stable and never reused (see *Stable IDs
and supersession*).

**Superseding-REQ placement.** A REQ that supersedes another sits adjacent to
the REQ it supersedes, marked
`(supersedes REQ-<old>)` in its body, with the old REQ marked
`**Superseded-by: REQ-<new>** (<date>)`. Adjacency keeps the lineage readable
without renumbering.

**Citation per requirement.** Every live requirement carries at least one
citation identifying where it came from: its governing decision, framing
source, or the event that introduced it. The citation is a trailing italic
annotation ending the requirement bullet, written on its own continuation
line:

```markdown
- **REQ-K1.8** Every config option SHALL be documented in a single canonical
  options reference …
  *(Cites: D-43.)*
```

Records frozen by supersession before a citation convention applied to them
are exempt from retroactive backfill: a superseded REQ's body is never edited
(D-20), and the supersede pointer is its lineage record.

**Changelog.** The bundle's changelog lives in `requirements.md` under
`## Changelog`, as dated bullets appended in chronological order. Every
amendment (meaning-class or expression-only, pre-merge or post-merge) gets an
entry naming the date, the class or triggering event, and what changed.

**Sources.** `## Sources` lists the framing inputs the bundle was elicited
from (seed notes, prior bundles, research, reference material). Source
citations elsewhere in the bundle refer to these entries.

## Citation syntax and kinds

A citation is a comma- or semicolon-separated list of citation tokens. It
appears in four places: the per-REQ `*(Cites: …)*` annotation, a design
decision's origin tag, a task's `**Citations:**` field, and test-spec entry
bodies. The recognized kinds:

| Kind | Form | Example |
| --- | --- | --- |
| Decision | `D-<n>` in the same bundle | `D-43` |
| Requirement cross-reference | `REQ-<id>` in the same bundle | `REQ-D2.2` |
| Task reference | `Task <id>` in the same bundle | `Task 5` |
| Source | a named `## Sources` entry, optionally with a foreign ID qualified by its namespace | `pair-flow REQ-B1.5`, `the bootstrap seed (Sources)` |
| Drafting-session decision | `drafting-session decision (<date>)` — a choice made during `/spec-draft` that did not mint a D-ID | `drafting-session decision (2026-06-08)` |
| Kickoff / brief | a kickoff-brief section or recorded decision | `kickoff §2 REQ-D (2026-06-10)` |
| Amendment / re-walkthrough | a brief amendment or re-walkthrough entry | `brief Amendment 5 (2026-06-11)`, `delta re-walkthrough (2026-06-11)` |
| Research | an external document, named inline | `research: TC39 process doc` |
| Observation | `obs:<uid>` — a recorded observation's fragment UID (durable across slug rename, content edit, and the archive move) | `obs:9f3c21ab` |

The lightweight kinds (drafting-session decision, kickoff, amendment,
research) exist so adopters can satisfy the citation-per-requirement rule
without minting a D-ID for every small choice. Foreign IDs are always
namespace-qualified (`pair-flow D-25` has no correspondence to a local
`D-25`).

## `design.md`

After the header block, an optional intro paragraph may define the bundle's
origin-tag legend, followed by `## Decision log` and optionally
`## Cross-cutting concerns`.

**D-ID convention.** Each decision is a section:

```markdown
### D-<n>: <Decision title>  (<origin tag>)

**Decision:** <what was decided>

**Alternatives considered:**
- <alternative>. Rejected because: <reason>.

**Chosen because:** <rationale>.
```

All three fields are required (REQ-A1.3). The origin tag cites the decision's
provenance (for example `N` for new, `C, pair-flow D-2` for carried, with the
foreign namespace qualified). D-IDs are stable and never reused; a reversed
decision is superseded, not rewritten (see *Stable IDs and supersession*).
Amendments to a decision's text are annotated in place per the
amendment-annotation format below.

## `tasks.md`

`tasks.md` is the canonical orchestration state record: there is no parallel
state file (D-2). After the header block and optional intro prose, it contains
these H2 state sections:

| Section | Holds |
| --- | --- |
| `## Forward plan` | Task blocks not yet picked up, in dependency order. |
| `## In progress` | Task blocks currently dispatched, with state annotations. |
| `## Awaiting input` | Task blocks blocked on a human decision, with the question stated. |
| `## Completed` | Task blocks that have merged, with completion annotations. |
| `## Deferred` | Deferral bullets with an explicit `**Gate:**` and a confidence level. |
| `## Out of scope` | Exclusion bullets. Permanent, not deferred. |

Empty sections are written with a `(none yet)` placeholder rather than
omitted. Section *order* is presentation choice; section *membership* is the
state machine.

**No hand-drawn dependency graph.** Each task block's `Dependencies:` field is
the sole source of truth for the task graph; intro prose does not embed a
drawn rendering of it, which drifts the moment a block is added or an edge
changes. The on-demand `scripts/spec-graph.sh` view renders the graph from
the `Dependencies:` lines, so no committed copy has to be kept fresh.

**Task block format.** A task is an H3 block carrying five definition fields:

```markdown
### Task <id> — <title>

- **Deliverables:** <what the task produces>
- **Done when:** <conditions an agent can evaluate>
- **Dependencies:** <task ids, or "none">
- **Citations:** <D-IDs> · <REQ-IDs>
- **Estimated effort:** <half day | N days>
```

Task IDs are stable and never reused. A single task id is `<n>` or `<n>.<m>`
(dotted ids insert between existing tasks without renumbering). Wrapped field
text continues on indented lines.

`### Task <id> — <title>`, with the em dash, is the **only** recognized heading
form (`scripts/check-ledger.sh` already flags deviations). A heading that begins
`### Task` and deviates from it — a colon separator, a missing title — is
malformed, never silently parsed into a wrong id: `### Task 1: title` otherwise
yields the id `1:`, and the gate evaluator then reports a false unknown-task
error against a task that is plainly there.

**Blocks move whole; definition fields are never deleted.** A state move
relocates the entire block between sections and adjusts annotations. In
format-version 1 a completed task keeps its full block (annotated, not
collapsed to a summary bullet): the content anchor's canonical extraction
(below) requires that definition content survive every state move, so that
orchestration moves never change the anchor. Implementation detail lives in
the PR; the block stays the durable definition record.

**Superseded and retired tasks keep their block.** Work that is abandoned or
replaced is represented, not deleted. In version 1 the whole block stays in the
state section it already sits in, gaining the annotation as `Status:` phase text
(`superseded by Task <id>` or `retired — <reason>`); it does not move to
`## Deferred` or `## Out of scope`, which hold bullets rather than blocks. In
version 2 the block stays in `## Tasks` and a reference bullet parks it under
`## Out of scope` (a permanent retirement) or `## Deferred` (one that may
return), the bullet's free text carrying that same annotation. Where a block
genuinely must leave the file, a dated `## Changelog` entry naming the retired id
authorizes the removal — the escape REQ supersession already has, and the only
one the stable-ID check accepts. The named token is a task id in the task-id
grammar, written in the `Task <id>` citation form this format already defines for
task references, because an unqualified number is indistinguishable from a date
component or any other digit in the prose; and it must be the id of the block
that actually left: an unnamed
removal, or one naming a different id, stays a renumbered-or-removed error. When a whole REQ
group is superseded, its `test-spec.md` entries are removed rather than left as
orphans pointing at retired IDs, with the tombstone recorded in the same dated
changelog entry, so REQ↔test-spec coverage stays exact in both directions.

**State annotations.** Annotation bullets appear after the definition fields
and are excluded from the content anchor:

- `- **Status:** <phase>` — a short free-form phase descriptor. Conventional
  values: `implementing`, `polish iter <n>`, `PR #<n> draft`,
  `draft-pr-ready · PR #<n> (draft)`, `awaiting input — <reason>`,
  `Completed · PR #<n> merged <YYYY-MM-DD>`. The list is illustrative, not
  exhaustive: the canonical extraction excludes all annotations, so new phase
  vocabulary never affects the anchor; exact values are the dispatch and
  sync-hook tooling's concern.
- `- **Last activity:** <YYYY-MM-DD>`
- `- **Dispatch:**` — dispatch metadata, in the form
  `backend=<subagents|tmux|print|in-session> · <handle> · dispatched
  <ISO-8601 UTC> · branch <branch> · worktree <path>`, where `<handle>` is
  the backend's worker handle (`window=<name>` for tmux, an agent id for
  subagents; omitted for print, which has no process until the human launches
  one). No live writer records it (a dispatch is the task branch plus the
  timestamped runtime marker, never a `tasks.md` write); the form stays
  defined so historical blocks parse.

**The completion annotation is normative.** The
`Completed · PR #<n> merged <YYYY-MM-DD>` value is the one **normative** entry
in the otherwise-illustrative `Status:` list: the canonical completion
annotation, stamped by the level-triggered reconcile in the same write that
places a block in `## Completed` from merged-PR evidence — regenerated, never
hand-copied. With no remote configured it degrades to exactly one of two
pinned outputs: the date-only `Completed · merged <YYYY-MM-DD>` (from branch
evidence), or left unstamped when even the date is unknown — never an invented
PR number, never a third free-form variant. (Other phase vocabulary stays
illustrative; only the completion annotation is pinned.)

**Deferred entries.** A deferral is a bullet (not a task block) carrying a
bolded title, the rationale, a structured gate, a confidence level where the
deferral is a decision, and citations:

```markdown
- **<Title>.** <rationale>. Confidence: <high|medium|low>.
  **Gate:** <GATE(when: …) condition or surfaced free-text condition>.
  Citations: <tokens>.
```

The gate grammar itself is defined in the accumulator-taxonomy doctrine
(Task 10, REQ-H1.3); this format only fixes where gates live in `tasks.md`.

## `test-spec.md`

After the header block and an intro stating the coverage mix, entries are grouped
under the same `## REQ-<Group> — <theme>` H2 headings `requirements.md` declares,
and every REQ is pinned to at least one verification path as an H3 entry beneath
its group's heading. Two separate points: an H2 layer is *mechanically* required,
because an H3 sitting directly under the H1 skips a heading level and trips the
MD001 heading-increment lint `mise run lint:md` runs; that the H2 must be the
matching group heading is this format's rule, which no lint checks — MD001 is
satisfied by any H2 at all.

```markdown
## REQ-<Group> — <theme>

### REQ-<id> — <short name> [<tags>]

<what is verified and how; fixtures, scenarios, or the artifact whose
existence-plus-coverage is the verification>
```

Tags, one or more per entry: `[test]` (automated, runs in the repo's CI),
`[manual]` (human-exercised), `[design-level]` (the artifact's existence and
coverage is the verification), `[Gherkin]` (state/trigger/outcome scenarios).
Mixed tags are written `[test + manual]`. Tags carry only tag words: sweep
tooling greps for whether a tag *includes* `[manual]` or `[Gherkin]`, so
prose belongs in the entry body, not the bracket. Two REQs stating one
requirement in two group views may share a joint entry titled with both IDs;
the entry states which REQ carries the normative text.

## Status lifecycle

Six statuses (kickoff-lifecycle D-1, superseding bootstrap D-40's five-status
set):

| Status | Meaning |
| --- | --- |
| `Draft` | Being authored or revised. Validator findings are warnings. |
| `Ready` | Signed off via `/spec-kickoff`, validated, and executable, with no execution work started. Validator findings are errors that block execution. |
| `Active` | Execution work in flight: at least one task has started. Validator findings are errors that block execution. |
| `Done` | All Forward plan / In progress / Awaiting input tasks completed. Validator findings are errors that block execution. |
| `Retired` | Terminal: abandoned or withdrawn, no replacement. |
| `Superseded` | Terminal: replaced by another bundle; `Superseded-by:` pointer mandatory. |

`Ready` carries the meaning bootstrap's `Active` carried at sign-off ("signed
off and executable"); `Active` is narrowed to strictly "execution work in
flight", so no signed-off-unstarted bundle is labelled `Active` (kickoff-lifecycle
D-1).

Transitions: `/spec-draft` writes Draft; `/spec-kickoff` flips Draft→Ready
on sign-off (and the human's merge of the spec PR makes the Ready spec
operational, D-44); a spec derives Ready→Active on the first task to start —
the first to derive In-progress per `orchestration-concurrency` REQ-C1.1, not
the dispatch act itself (kickoff-lifecycle D-2); a spec flips to Done when its
last Forward-plan / In-progress / Awaiting-input task moves to Completed —
from `Active`, directly from `Ready` if all tasks complete at once, or at
sign-off if it has no startable tasks (Done determination takes precedence over
the Ready↔Active derivation). The Draft→Ready flip is stored and human-gated;
Ready↔Active is derived (not stored) and written only by
`orchestration-concurrency`'s single level-triggered reconcile writer
(kickoff-lifecycle D-2, D-3). Open Deferred gates do not block Done, and the
gate evaluator continues sweeping gates in Done specs. **Reopen cycle:**
extending a Done bundle flips Done→Draft; scoped kickoff of the delta flips
back to Ready. Retired and Superseded are human-set terminal states; no
skill-driven transition out of a terminal state is accepted.

## Format-version 2 — the invariant ledger

Format-version 2 stores only what cannot be derived (invariant-tasks
D-2–D-5, D-11 · REQ-A1.1–A1.4, REQ-C1.9, REQ-E1.1). A bundle opts in by
declaring `**Format-version:** 2`; v1 bundles stay valid indefinitely.
Everything version 1 defines carries over unchanged except these deltas.

**Header block (all four files, mirrored).** The stored `Status:` set is
restricted to the human-gated states — Draft, Ready, Retired, Superseded
(with its `Superseded-by:` line) — and this exact line follows
`Format-version:`:

```markdown
**Execution:** derived — see the status render
```

Fixed vocabulary, never per-bundle prose: it points the reader at the
render. Active and Done are derived on demand, never stored, and only for
stored-Ready bundles (Draft, Retired, and Superseded render their stored
state, no execution claim): a bundle is **Active** iff any task derives
In-progress, or Completed with work remaining; **Done** when every task in
the Done universe derives Completed and no live Awaiting-input bullet
remains — Deferred- and Out-of-scope-parked tasks are excluded from the
Done universe rather than blocking it, and a zero-task bundle never derives
Done. The reopen cycle is Ready→Draft.

**`tasks.md`.** After the header block and optional intro prose, exactly
four H2 sections: `## Tasks` (all task blocks, never moving),
`## Awaiting input`, `## Deferred`, and `## Out of scope`
(`(none yet)` when empty). The placement sections (`## Forward plan`,
`## In progress`, `## Completed`) and the state annotation bullets
(`Status`, `Last activity`, `Dispatch`) do not exist: a task block carries
its five definition fields and nothing else. A block is edited only for
definition changes via the amendment ritual; derived execution-state
changes never produce commits. Parking and unparking writes (by the human
or a halting skill) are human-owned payload, not execution state.

Block order inside `## Tasks` carries no meaning. `Dependencies:` lines are the
sole source of the task graph, so ordering is presentation: dependency order is
recommended authoring guidance because it reads as a narrative, and the id-sorted
order `scripts/migrate-format-version.sh` emits is equally conformant. No
validator rule enforces either, and the canonical extraction id-sorts regardless.

**Reference bullets.** Parking writes a bullet whose bolded lead is exactly
`**Task <id>**` (task-id grammar, naming an existing block); the block
stays in `## Tasks`; unparking removes the bullet. The free text is the
payload: the blocking question (Awaiting input), the version 1 deferral
fields (Deferred), or the exclusion rationale (Out of scope).
`## Awaiting input` holds reference bullets only; the other two sections
may also hold plain non-task bullets as in version 1, which never count in
the derivation. Every reference bullet names an existing task id; at most
one per task across the three sections. A live bullet on the derivation's
read surface (the primary checkout's main view) outranks git evidence; a
bullet only on an unmerged branch takes effect when it lands. Bullet
free text is committed, remotely visible content: no secrets, credentials,
internal hostnames, or sensitive operational detail.

**Two readers of "completed", deliberately asymmetric.** Reference-bullet
authority governs gate atoms in `scripts/drain-gates.sh`, where a task re-parked
after its PR merged stays unmet; it does *not* govern dependency satisfaction in
`scripts/orchestrate-select.sh`, which reads the derivation engine's raw
completed set. Each side preserves its own version-1 semantics — v1 gates read
`## Completed` membership, v1 dependencies already read engine evidence — so
neither is "fixed" into the other, and a future reader should not unify them.
The accepted consequence, stated so nobody reads it as a bug: the two evaluators
may disagree about the same re-parked task at the same instant, leaving a
dependent dispatchable while the gate on that same task reports PENDING.

**Read surface and anchor.** The status render (the derivation engine
surfaced as a command) is the canonical execution-status read surface; no
derived-status artifact is committed or remote-mirrored. The normative
completion annotation has no v2 home (the 2026-07-10 entry below is scoped
to version 1; D-11). Anchor mechanics are unchanged — the canonical
extraction selects `### Task` blocks wherever they sit — and with no
derived writes, no orchestration or execution act moves the anchor.

**Validation.** The validator enforces these invariants as errors on
non-Draft v2 bundles and warnings on Draft. Two carve-outs error at *every*
status, Draft included: a missing or unparseable `Format-version:` — and every
version-keyed script fails closed on it, never falling open to the v1 write path
— and a duplicate in-header declaration of either load-bearing key
(*Header-block extent*), which is unparseable by the same reasoning.

## Stable IDs and supersession

REQ-IDs, D-IDs, and task IDs are stable and never reused (D-20). A
changed-meaning requirement or decision mints a new ID and marks the old one
`Superseded-by`; the old record's body is never edited. This is the
traceability primitive everything else leans on: citations stay valid
forever, and the why-it-changed survives in place.

## The amendment ritual

The amendment axis (REQ-A3.3, D-19) is: **does the change contradict an
accepted decision or alter a REQ's meaning?**

- **Expression-only** (typo, ambiguity, gap-fill consistent with accepted
  decisions): fixed in place with a mandatory dated Changelog entry and no
  re-approval. Re-anchoring still applies before the next dispatch (see
  *Content anchors*).
- **Meaning-class** (contradicts an accepted decision or alters a REQ's
  meaning; additions of new REQs or D-IDs also count as meaning-class): the
  human classifies at sign-off, recorded per the sign-off record format.

**Scope rule:** the supersede ritual governs **post-merge** changes (the
bundle has merged to main): a new ID supersedes the old, the kickoff brief is
re-synced by diff-review, and a scoped re-sign-off covers the moved decision.
**Pre-merge** corrections on the spec's own PR amend in place with a
changelog entry plus a recorded re-sign-off (the PR is the review surface;
nothing signed has shipped).

**Amendment-annotation format.** A record amended in place carries a trailing
italic annotation: `*(Amended at <event> <date>: <summary>.)*` — for example
`*(Amended at polish review 2026-06-10: exemption added.)*`. The annotation
names the event so the changelog entry and brief record are findable.

In-flight amendments ride the task PR that triggered them; supersede-class
amendments get their own spec PR; expression-only fixes may commit directly
with a changelog line plus the marked self-re-anchor entry (D-44).

## The kickoff brief

`specs/<spec>/kickoff-brief.md`, written by `/spec-kickoff`, is the durable
contract between human and agent (two-brief model, D-3: kickoff brief is
contract; an optional handover brief at `<worktree>/.claude/handover.md` is
cache, not source of truth). Downstream skills operate from the brief, not by
re-reading the spec. Required structure:

1. **Header block:** spec path, spec commit at walkthrough start, walkthrough
   date(s), and any pre-flight determinations the format's skills require.
2. **Goal & glossary section:** the agent's restatement of the goal, what it
   rules out, what it assumes, implicit terms surfaced, and recorded
   resolutions. Signed off per section.
3. **Requirements walkthrough:** per-group outcomes, decisions taken, and the
   consolidated spec-edit list.
4. **Design walkthrough:** every D-ID accounted for (confirmed / amended /
   superseded), with a reconciled ledger.
5. **Verification approach:** the coverage mix reviewed, verification
   ownership stated, dead paths checked.
6. **Task graph section:** the dependency graph reconstructed from
   `Dependencies:` lines, parallelism and critical path identified,
   deliberate non-edges recorded so nobody "fixes" them.
7. **Risk register:** numbered rows of risk + mitigation / early signal.
   Execution skills append research, performance, and security findings here
   (REQ-E1.3); appended rows never overwrite existing ones.
8. **Sign-off section:** the final sign-off record. Everything above the
   amendment log is append-only after sign-off; later contract changes
   travel as amendment entries below it.
9. **Amendment log:** appended amendment, re-walkthrough, and re-anchor
   entries, each carrying a sign-off record (below).

**Cite derived figures; do not copy them.** Where a brief section reports a
figure derived from the bundle — a task count, a REQ tally, a field or ID
list, the parallelism and critical-path summary of section 6 — it cites the
source file or section it is derived from rather than transcribing the value.
A copied tally drifts from its source the moment the bundle changes; citing
the source keeps the brief and the bundle in agreement.

## Sign-off records and content anchors

Every brief sign-off, amendment, re-walkthrough, and self-re-anchor ends with
a machine-checkable record (REQ-F1.10):

```markdown
Class: <meaning | expression-only>
Lens-pass: <reference to the lens review recorded in the same section>   (meaning-class only)
Anchor: `<hash>` — computed as
`<exact sanctioned command>`
```

- **`Class:`** classifies the change on the REQ-A3.3 axis. The human
  classifies at sign-off; additions count as meaning-class.
- **`Lens-pass:`** (meaning-class only) references the Discovery-Rigor lens
  review pass recorded in the same brief section: the canonical lens-coverage
  table, fan-out for non-trivial deltas, full bundle at first activation,
  delta-scoped at re-walkthroughs and amendments, findings dispositioned.
  `/spec-kickoff` refuses to record a meaning-class anchor without a
  dispositioned lens pass. Two checklist items belong to this format rather
  than to the general lens list, both under the cross-file-consistency lens:
  - **Qualified cross-spec citations.** Read every namespace-qualified foreign
    citation and confirm it resolves to the record the sentence relies on. The
    division of labour is deliberate: mechanical range and qualifier checking of
    *unqualified* tokens is the validator's (a hardening rule, not yet landed),
    while whether `bootstrap D-25` is the decision being leaned on is a judgment
    no structural check can make — a keyword heuristic would false-positive on
    legitimate cites while lulling readers on subtle ones. A misattributed
    qualified citation is therefore invisible to tooling at every stage, and this
    item is its only guard.
  - **Requirement/test-spec pairing.** A disposition that adds a requirement or
    extends an existing one carries the paired `test-spec.md` edit in the same
    disposition. Coverage checking only asks whether an entry exists, so a
    requirement whose verification path was never updated passes on a stale
    entry; pairing them at disposition time is what keeps that dead path from
    forming.
- **`Anchor:`** the content anchor plus the exact sanctioned command used
  (self-describing, so recomputation is deterministic). The anchor line is
  written **last**, after the sign-off record and lens-pass disposition, so a
  killed session fails closed (a record without its anchor line is treated as
  absent-anchor).

**Writers.** Meaning-class entries are written only by `/spec-kickoff`'s
sign-off flow. Expression-only edits may self-re-anchor via a machine-written
entry explicitly marked `Class: expression-only` and citing the changelog
line; misclassification is auditable and one revert from undone. Execution
skills' brief writes are confined to named sections (risk register,
observations) and never produce anchor entries.

**What a writer owes when it acts on findings.** The permission above is one
half of the contract; this is the other. Two routes reach the same edit — a
skill applying a review finding to a signed (Ready or Active) bundle, and a
skill acting on an edit its own implementation work revealed — and both owe
the three things below, in order. What triggers them is an edit to **anchored
content**; the orchestration-state and placement writes the anchor excludes by
construction are bookkeeping, and a stale anchor never blocks one. First, a
**stale-anchor pre-flight** before the skill's first such edit to that bundle:
recompute with the brief's most recent recorded command and surface instead
of editing when the anchor mismatches, when the entry is absent or
unparseable, or when the recompute itself fails — all of them block alike,
because none of them can say what the recorded anchor covers, and editing on
top of an unknown baseline is what makes the drift unrecoverable. Second, for
an **expression-only** edit, the full ritual in the same change: the edit,
its dated Changelog entry, and the marked `Class: expression-only`
self-re-anchor entry citing that entry, landing in **one commit**, so no
commit in history carries an edited bundle under an anchor that no longer
describes it. Third, **refusal** of a meaning-class edit: the bundle stays
untouched and the handoff names a `/spec-kickoff` delta re-walkthrough as the
route, because meaning-class writership is `/spec-kickoff`'s alone. This binds
the act, not the shipping vehicle: a review skill delivered from another
repository owes the same three, and follows through its own repository.

### The content anchor

The anchor (REQ-F1.9, D-45) is the hash of the per-file digest list: each
file's digest taken in turn, the four digests in canonical order
(requirements, design, tasks, test-spec) hashed as a stream. Manifest-style
hashing is boundary-safe, unlike hashing a bare concatenation.

The digest is narrower than the files' bytes, so that the routine writes named
below never trip the freshness gate while meaning edits always do:

- `tasks.md` contributes its **task-definition content only**, per the
  canonical extraction below, so `/orchestrate`'s own state moves never trip
  the gate.
- `requirements.md`, `design.md`, and `test-spec.md` each contribute their
  content minus exactly one line — the header-block `**Status:**`
  declaration, removed together with its line terminator so the bytes around
  it join unchanged — hashed with `git hash-object` over that reduced content
  (anchor-integrity D-2, REQ-A1.1). Neither the stored Draft→Ready flip nor
  the derived Ready↔Active flip changes a bundle's anchor, and neither do the
  header mirrors those flips write into the other three files. An entry
  recorded with the interim whole-file form below is the exception: its digest
  still carries the Status line, so a flip stales it.

**The Status exclusion is universal.** It is defined here once, in the
version-1 body, and inherited unchanged by every later format version, so the
tool applies it without parsing `Format-version:` at all: version 1's stored
lifecycle flips are the motivating failure, and version 2's restricted stored
set is covered by the same rule. `tasks.md` needs no such carve-out — its
header block is already outside the canonical extraction.

**The exclusion is bounded to the header block.** Only the `**Status:**` line
inside the single leading header block — as *Header-block extent* above defines
it — is excluded. A `**Status:**` line in body prose or inside a fence is
ordinary anchored content: edit it and the anchor moves. The exclusion fails
closed on a block that extent definition calls malformed, and on a duplicated
`**Status:**` declaration inside it, yielding a non-zero exit and no anchor
rather than silently falling back to hashing the whole file. A well-formed block
carrying no `**Status:**` line is the one benign case: it excludes nothing and
hashes the whole file, matching the validator's warn-and-default posture on a
missing `Status:`. The rest of the header block stays anchored:
`Format-version:` and `Superseded-by:` are meaning-bearing, so a migration or a
supersession must never slip past the gate, and `Last reviewed:` moves only in
the same rituals that re-anchor anyway.

**Sanctioned command forms** (anything else in an `Anchor:` line is invalid):

1. **Canonical form:** `scripts/spec-anchor.sh <spec-dir>` — the reference
   implementation of the manifest anchor with the canonical `tasks.md`
   extraction, shipped with this meta-spec and unit-tested
   (`tests/test-spec-anchor.sh`). It fails closed (non-zero exit, message on
   stderr, no anchor printed) on a missing or unreadable spec file, a failed
   extraction, or duplicate task ids; a successful exit is the only state
   that yields an anchor.
2. **Interim whole-file form:**
   `git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
   — the pre-extraction form. Remains sanctioned (existing entries stay
   parseable; an environment without the script can still anchor), with the
   documented consequence that `tasks.md` state moves stale it and force an
   expression-only re-anchor. It also hashes the header `**Status:**` line the
   canonical form excludes, so a lifecycle flip stales it too.
3. **Resolution-aware logical form:** `spec-anchor.sh <spec-dir>` — the same
   reference implementation named without a repo-relative path, resolved
   through the documented core root chain, first hit winning
   (anchor-integrity D-7, REQ-F1.1):
   1. `$PLANWRIGHT_ROOT/scripts/` — explicit override (tests, adopters);
   2. `$CLAUDE_PLUGIN_ROOT/scripts/` — plugin delivery, set by Claude Code;
   3. `<claude-dir>/planwright/scripts/` — writer delivery, where
      `<claude-dir>` is `$CLAUDE_DIR` when set, else `~/.claude`;
   4. `<script-dir>/../scripts/` — self-location beside the resolving script,
      the final fallback.

   An arm whose root is unset or empty is **skipped**, never expanded into a
   bare `/scripts/…` path — so an environment with none of these variables set
   reaches the self-located arm, and a sanitized one resolves nothing at all
   rather than something surprising. An arm **hits** when an executable regular
   `spec-anchor.sh` sits at the resolved path. This is the core-layer chain
   `scripts/resolve-rule-doc.sh` already
   documents, so recomputability becomes a property of the delivery mode
   rather than of one repo's layout: an adopter repo that consumes planwright
   as a plugin and has no repo-root `scripts/` records this form. A gate
   consumer prepends the checked tree's own script to this chain (see
   *Execution validity*); where `scripts/spec-anchor.sh` exists in the checked
   tree the canonical form also stays preferred for new entries, and adding
   this form invalidates no existing entry. Recording an env-literal path
   (`"$PLANWRIGHT_ROOT/…"`) is **not** sanctioned: a stale or unset variable
   makes the recorded command resolve silently to the wrong version or to
   nothing. The chain's env roots are operator-owned trust inputs — whoever
   sets them chooses the program that computes the hash — which is the other
   reason a consumer prefers the checked tree's script; D-7 records that
   residual as accepted.

### Canonical `tasks.md` definition-content extraction

The extraction maps `tasks.md` to a normalized byte stream:

1. **Select task blocks.** A task block starts at a line matching
   `^### Task <id>` and ends at the next H2/H3 heading or end of file.
   Everything outside task blocks (header, intro prose, any pasted graph
   rendering, section headings, Deferred / Out-of-scope bullets, placeholders)
   is excluded.
2. **Keep definition lines only.** Within a block, keep: the heading line,
   and the five definition field bullets — `Deliverables`, `Done when`,
   `Dependencies`, `Citations`, `Estimated effort` — each with its indented
   continuation lines. Exclude every other bullet (`Status`,
   `Last activity`, `Dispatch`, and any future annotation) and its
   continuations, and any blank or prose line.
3. **Sort by task id.** Records are ordered by task id, compared numerically
   component-wise (`2` < `2.5` < `3`), so document order — which changes when
   a block moves between sections — is irrelevant. Duplicate task ids are
   invalid input (the validator's never-reused rule).
4. **Emit.** Kept lines byte-for-byte as in the source, each terminated by a
   newline, records concatenated in sorted order. The stream is hashed with
   `git hash-object --stdin` and that digest stands in for `tasks.md` in the
   manifest.

Re-wrapping a definition field's lines changes the extraction (and the
anchor); that is an expression-only edit and re-anchors via the marked entry.

### Execution validity

`/orchestrate` (inside the per-spec lock window, immediately before the
`tasks.md` update) and `/execute-task` (at pre-flight) recompute the anchor
with the command recorded in the brief's most recent anchor entry and compare,
both read from the primary checkout's main view. All halt conditions fail
closed to Awaiting input, naming the remedy:

- **Anchor mismatch** (any anchored content changed since the entry,
  committed or not) → remedy: `/spec-kickoff` delta re-walkthrough.
- **No anchor entry / unparseable entry / non-sanctioned command form /
  entry from a non-sanctioned writer** → remedy: complete or repair the
  sign-off record per REQ-F1.10.
- **A sanctioned form that resolves to nothing** in the current environment —
  no `scripts/spec-anchor.sh` in the checked tree and no hit on any core
  root-chain arm — is treated as **absent-anchor-class**: the gate halts and
  never reads an unresolved command as a match (anchor-integrity REQ-F1.1).
  Remedy: make the tool resolvable, either by supplying the checked tree's
  canonical script or by setting a root the chain reads (the arms are listed
  under *Sanctioned command forms* above).

**Pre-change anchors: the one-time self-re-anchor.** An entry recorded before
the header-block `**Status:**` exclusion landed (the 2026-07-26 *Anchor-scope
exclusion* changelog entry), or recorded with the interim whole-file form,
covers a scope the canonical tool no longer computes — so it halts as a
mismatch over content nobody edited. planwright's own bundles were swept in the
change's own PR (anchor-integrity D-3, REQ-A1.4); an adopter bundle at either
format version carries the same repair, once, and it is the bundle owner's to
make. It is not a bare re-record: classify the bundle's anchored-content delta
since the recorded entry first, diffing from the commit that introduced that
entry's anchor line. A lifecycle-only or expression-only delta takes the
machine `Class: expression-only` entry, citing the delta that actually moved
the anchor rather than the scope change by reflex. A meaning-class delta — and
any delta the classification cannot resolve, which defaults to meaning-class —
takes the re-review ritual the bundle's status admits instead: a
`/spec-kickoff` delta re-walkthrough for `Ready` or `Active`, the reopen cycle
for `Done`. That is what keeps a one-time repair from laundering an unreviewed
meaning edit. An entry written under the amended semantics never needs the
remedy again.

**Resolving the recorded command.** All sanctioned forms are accepted, and the
form recorded in the entry is the one recomputed with — a consumer never
substitutes a different form for the one on record. For the two script-based
forms (the interim form invokes `git` directly and needs no resolution),
locating that one reference implementation runs the checked tree's
`scripts/spec-anchor.sh` where it is present and falls back to the core root
chain only where it is absent, so the checked tree's own script always wins over
an ambient root. Resolution finds the same tool; it never rewrites the recorded
form.

**Reference frame (version 1 bundles).** The comparison is framed on a single
pinned commit of the main view (anchor-integrity D-4, REQ-B1.1). Where the
checkout the gate reads diverges from that pinned view within anchored content
only by header `**Status:**` lines carrying sanctioned status values, across any
subset of the four files — the shape the single-writer derived mirror produces —
the gate compares against the pinned committed view instead of halting. The
tolerated shape is a **value substitution** in a declaration present on both
sides: the mirror rewrites a Status value and never adds or removes the
declaration, so an inserted or deleted Status line is another divergence, not
this one. The gate
accepts that **shape**, not a writer's identity: it cannot attribute a
divergence to a writer. Any other divergence, committed or not, halts exactly as
above, so an uncommitted meaning edit in the working tree still halts. The frame
stays load-bearing after the Status exclusion above, because an entry recorded
with the interim whole-file form has the Status line inside its digest.

There is no bypass flag (same class as the non-Active refusal). A
meaning-class entry is **execution-valid** only if it parses, uses a
sanctioned command form, was written by the sanctioned writer, and carries a
dispositioned lens-pass reference; an expression-only entry is execution-valid
with no lens pass if it is explicitly marked and cites its changelog line.
Validity conditions apply to entries recorded from the rule's adoption
onward (earlier entries are superseded by the adopting amendment's own
anchor).

## Branch, worktree, and task-id grammar

- **Branch naming (D-36):** orchestrator-created branches are
  `planwright/<spec>/task-<id-or-ids>`, where the `<id-or-ids>` segment
  matches `^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$` — a single id (`3`,
  `3.5`) or a bundle range (`3-4`, `3.5-4`).
- **Reserved spec namespace (D-44):** `planwright/<spec>/spec` is the spec
  bundle's own branch; the `tasks-pr-sync` hook no-ops on it.
- **Worktree placement (D-37):** `<repo>/.claude/worktrees/<branch-suffix>`,
  attachable via `claude --worktree` regardless of which backend launched the
  work.
- Parsed branch segments are validated (`<spec>` against the identifier
  charset, `<id>` against the task-id grammar) before any path use; a branch
  failing validation is a clean no-op (REQ-K1.2).

## Validator-enforceable invariants

The status-aware validator (REQ-A2.1, D-25; warnings on Draft, errors on
Ready, Active, and Done; Retired/Superseded terminal) enforces, keyed off
the declared format-version:

1. Four-file presence.
2. Header block: `Status:` declared (missing warns and defaults to Draft);
   one of the six statuses (unknown flagged); `Superseded` requires
   `Superseded-by:`; `Format-version:` declared.
3. Spec-identifier charset and length; underscore-accumulator name
   screening (accumulators are otherwise skipped, not validated as bundles).
4. REQ-ID convention: stable IDs, citation per live requirement.
5. D-ID structure: Decision / Alternatives considered / Chosen because all
   present.
6. Task structure: stable ID and the five definition fields per task block.
7. REQ↔test-spec coverage: every REQ has at least one test-spec entry.
8. Stable-ID discipline: a reused or renumbered ID is rejected; a supersede
   (new ID plus `Superseded-by` on the old) passes. A supersede newly
   introduced since the baseline ref must be named in a dated `## Changelog`
   entry (REQ-A3.3: the supersede pointer records lineage, the changelog
   records the why-it-changed); a supersede already recorded in the baseline
   is not re-flagged.
9. Terminal-state discipline: no transition out of Retired/Superseded.

## Glossary

- **Gate** carries three senses; context disambiguates, and doctrine names
  the sense when it matters:
  1. the **autonomy gate** — the act-then-review bucket dispatch deciding
     what the agent does with a finding;
  2. a **`GATE(when:)` entry** — a structured deferral condition on a
     Deferred item;
  3. the **release gate** — the conditions gating public release
     (REQ-J1.5).
- **Unit** — the orchestration quantum: a single task or one
  cohesion-bundle. One unit advances per dispatch step.
- **Drain** — the ritual by which an accumulator's contents reach a reader
  or decision. Nothing is auto-resolved or auto-dropped; draining surfaces.
- **Accumulator** — any surface that collects deferred work or decisions
  (`_pending/`, the observations fragment store, Deferred sections). Every
  accumulator has a named reader and a drain ritual (no write-only
  deferral).
- **Adopter** — the non-author operator persona: someone who installs
  planwright without inheriting the author's toolchain. The format's success
  criterion is that an adopter can operate it from the docs alone.
- **Brief** — the kickoff brief (`kickoff-brief.md`, the durable contract)
  or the handover brief (optional in-worktree cache). Unqualified, "the
  brief" means the kickoff brief.
- **Bucket** — one of the four finding categories of the autonomy gate:
  Auto-applicable, Agent-resolvable, Needs sign-off, Needs human judgment.
- **Tower** — the dispatching `/orchestrate` session (control tower). It
  holds no in-memory state beyond the current step and is disposable.
- **Observations log** — the canonical name for the observations
  accumulator: per-entry fragment files under
  `specs/_observations/entries/` (live) and `specs/_observations/archive/`
  (consumed), plus the frozen legacy `opportunities.md` while it drains,
  mined by `/spec-draft` (its canonical reader), with the chronological
  view rendered on demand and never committed. The accumulator-taxonomy
  doctrine carries the canonical class-3 definition and drain ritual.
- **Dispatch step** — one atomic `/orchestrate` step: select a ready unit,
  take the lock, move state, dispatch, release, exit.
- **Content anchor** — the manifest-style hash over the four spec files
  (with `tasks.md` reduced to definition content) recorded in brief sign-off
  records and recomputed by the execution freshness gate.
- **Execution-valid (anchor)** — an anchor entry satisfying the REQ-F1.10
  validity conditions, and therefore one the freshness gate will dispatch
  against.
- **Meaning-class vs expression-only** — the REQ-A3.3 amendment axis:
  whether a change contradicts an accepted decision or alters a REQ's
  meaning (meaning-class, human-classified at sign-off; additions included)
  or stays within accepted decisions (expression-only: typo, ambiguity,
  gap-fill).
- **Kicked off vs started** — the distinction the `Ready`/`Active` split
  encodes (kickoff-lifecycle D-1): a `Ready` bundle is signed off and
  executable but nothing has started; an `Active` bundle has execution work
  in flight. Sign-off makes a bundle `Ready` (stored, human-gated); the first
  task to derive In-progress derives it `Active` (orchestration-concurrency's
  single reconcile writer; never a second writer).

## Versioning of this meta-spec

This document is format-version 2 and defines versions 1 and 2. Changes to
the format bump the version; bundles keep working under the version they
declare, and the validator applies the rules for the declared version. A
bundle migrates by updating its `Format-version:` line and conforming to
the new version's rules.

For the v1→v2 migration specifically,
`scripts/migrate-format-version.sh <spec-dir>` performs the conversion
mechanically: it collapses the placement sections into a single `## Tasks`,
strips the state-annotation bullets while preserving each task-definition line
byte-for-byte (so the content anchor is unchanged), relocates parked blocks
behind reference bullets, bumps the `Format-version:` line, and inserts the
`**Execution:** derived` pointer. A signed bundle additionally gains a dated
changelog entry and the machine-written self-re-anchor. The transform is
mechanical or it refuses — content it cannot place deterministically stops the
bundle untouched.

- 2026-07-14 — **Format-version 2**: the invariant ledger (invariant-tasks
  D-1, D-2), defined in *Format-version 2 — the invariant ledger*; version 1
  rules are retained above, unchanged in meaning. This entry scopes the
  2026-07-10 completion-annotation promotion below to version 1 bundles
  (invariant-tasks D-11): under version 2, completion is derived render
  content.

Amendments that leave every format version's authoring rules intact are
recorded here without a version bump — a bundle authored to the affected
version stays conformant. Guidance refinements qualify; so does a change to a
mechanism this format defines *around* bundles rather than *inside* them (the
anchor computation, the sanctioned command forms), which by design applies to
bundles at every version at once and so must not be gated behind a version a
bundle would have to migrate to:

- 2026-07-10 — Derived-content authoring guidance. The `tasks.md` guidance no
  longer suggests a hand-drawn dependency graph in intro prose (`Dependencies:`
  lines are the sole source of truth; `scripts/spec-graph.sh` renders the
  on-demand view); the kickoff-brief guidance gains the cite-don't-copy
  convention for derived figures; and the
  `Completed · PR #<n> merged <YYYY-MM-DD>` completion annotation is promoted
  from illustrative to normative, with its single degraded form
  `Completed · merged <YYYY-MM-DD>` and the unstamped fallback pinned.
  *(Scoped to format-version 1 bundles by the 2026-07-14 entry.)*
- 2026-07-26 — Anchor-scope exclusion. The per-file digests for
  `requirements.md`, `design.md`, and `test-spec.md` exclude the header-block
  `**Status:**` line, bounded to the single leading header block and failing
  closed on a malformed, duplicated, or unterminated one, defined once in the
  version-1 body and inherited by every later version (*The content anchor*).
  Both the stored Draft→Ready flip and the derived Ready↔Active flip become
  anchor-invariant, so a lifecycle write can no longer false-halt the
  execution freshness gate. The tool-side change and the coordinated
  re-anchor sweep it requires land as their own tasks; this entry is the
  doctrine half. The interim whole-file form keeps the Status line inside its
  digest and is unaffected. *(anchor-integrity D-2, D-3 · REQ-A1.1, REQ-A1.2;
  the header-block extent this entry relied on a reconcile note for is now
  defined normatively — see the 2026-07-29 entry.)*
- 2026-07-26 — Gate reference frame stated. The version-1 execution-validity
  prose states the pinned committed-main frame and the one divergence shape it
  tolerates — header `**Status:**` lines carrying sanctioned values, across
  any subset of the four files — accepted by shape, since the gate cannot
  attribute a divergence to a writer (*Execution validity*). Records a
  resolution twice derived under dispatch pressure; changes no halt outcome
  for any other divergence. *(anchor-integrity D-4 · REQ-B1.1.)*
- 2026-07-26 — Third sanctioned command form. The resolution-aware logical
  `spec-anchor.sh <spec-dir>`, resolved through the documented core root
  chain, joins the sanctioned forms, with the consumer resolution order
  (checked-tree script first, chain only where absent) and the fail-closed
  absent-anchor-class halt for a form that resolves to nothing (*Sanctioned
  command forms*, *Execution validity*). Makes a recorded anchor recomputable
  in a plugin-consuming adopter repo with no `scripts/` directory; no existing
  entry is invalidated, and env-literal paths stay unsanctioned.
  *(anchor-integrity D-7 · REQ-F1.1.)*
- 2026-07-26 — Decided-rule authoring guidance. Anchored deliverable prose
  states decided rules rather than enumerated counts or corpus claims whose
  truth depends on a surface outside the bundle; unavoidable enumerations
  follow cite-don't-copy or carry their own cross-check, and `/spec-draft` and
  `/spec-kickoff` run the cross-check at drafting and sign-off (*Decided rules
  over enumerated claims*). As with the anchor-scope entry above, this is the
  doctrine half: the two skills gain the cross-check step as their own task, so
  the rule states the standard before the skill prose instantiates it.
  *(anchor-integrity D-8 · REQ-E1.1, REQ-E1.2.)*
- 2026-07-29 — Parse grammar made normative. Seven rules that parsers, tests, or
  lints already applied without a normative home are stated here, so every
  implementation cites one definition instead of re-deriving it: the fenced-
  illustration rule with its unbalanced-fence malformation (*Fenced
  illustration*); the header block's positional extent, and the fail-closed
  posture on a duplicate in-header `Format-version:` or `Status:` declaration
  (*Overview*), which supersedes and removes the reconcile note the 2026-07-26
  anchor-scope entry left in *The content anchor*; the canonical
  `### Task <id> — <title>` heading as the only recognized form, and the
  keep-the-block representation for a superseded or retired task with its
  changelog-named removal escape and test-spec tombstone (*`tasks.md`*); the
  required `## REQ-<Group>` grouping in `test-spec.md`, which reconciles the
  format example with the MD001 lint (*`test-spec.md`*); the version-2 `## Tasks`
  ordering as presentation rather than rule, resolving a contradiction between
  this doc's former "dependency order" wording and the id-sorted collapse
  `scripts/migrate-format-version.sh` ships (*Format-version 2*); and the
  deliberate asymmetry between the two readers of "task completed", with the
  disagreement it accepts (*Format-version 2*). The kickoff `Lens-pass:`
  definition gains the two checklist items this format needs a human for —
  qualified-cross-spec-citation review and requirement/test-spec pairing
  (*Sign-off records and content anchors*). **No version bump:** no rule makes a
  conforming bundle nonconforming — every in-repo bundle at both versions already
  satisfies all of them, verified before landing — so no bundle migrates.
  **Enforcement is deliberately behind the rule.** The fence rule generalizes
  what the version-2 parked-map family (`spec-parse.sh`, and through it
  `drain-gates.sh`, `spec-status.sh`, `orchestrate-select.sh`, `spec-validate.sh`)
  already implements and tests; the remaining parses — the canonical `tasks.md`
  extraction, and `spec-validate.sh`'s requirement, decision, and task-heading
  grammars — are *not* fence-aware yet and become so in lockstep as their own
  task, which is also where the unbalanced-fence validator flag lands. The
  duplicate-declaration error, the deviant-heading validator flag
  (`check-ledger.sh` already flags it; `spec-validate.sh` does not), the
  unqualified-citation range warning, and the changelog-named retirement escape
  are likewise their own tasks. As with the two 2026-07-26 doctrine-half entries
  above, the rule is stated before the tooling catches up; what is not claimed is
  that the tooling has already caught up.
  *(format-grammar D-1, D-5, D-6, D-7, D-10, D-11, D-12, D-13, D-14 · REQ-A1.1,
  REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8,
  REQ-A1.10, REQ-D1.4, REQ-D1.8.)*
- 2026-08-24 — Pre-change anchor remedy named. The execution-validity halt
  guidance states the one-time self-re-anchor for an entry recorded before the
  2026-07-26 anchor-scope exclusion or with the interim whole-file form, and
  pins the classification that gates it: lifecycle-only or expression-only
  takes the machine entry citing the delta that actually moved the anchor,
  while a meaning-class or unresolvable delta takes the status-apt re-review
  ritual instead (*Execution validity*). The in-repo corpus was swept under
  that rule in the same PR as the tool-side scope change; this entry names the
  remedy for bundles the sweep could not reach. **No version bump:** no rule
  changes — a halt case that already existed gains its remedy in writing.
  *(anchor-integrity D-3 · REQ-A1.5.)*
- 2026-08-24 — Fence enforcement caught up, and the retirement escape's form
  pinned. The 2026-07-29 entry above stated the fence rule while naming the
  parses that were not yet fence-aware; they now are. The canonical `tasks.md`
  extraction and `spec-validate.sh`'s requirement, decision, task-heading, and
  version-2 ledger grammars all read through one shared lexer in
  `scripts/spec-parse.sh`, so fenced illustration neither raises findings of its
  own nor satisfies a check a real record would; the unbalanced-fence flag and
  the changelog-named retirement escape ship with them. **No version bump:** no
  rule makes a conforming bundle nonconforming, and no in-repo bundle's content
  anchor moves (verified by a recompute over every bundle, before and after).
  The one authoring clarification: the retirement escape names its id in the
  `Task <id>` citation form this format already defines, because an unqualified
  number cannot be told apart from a date component or any other digit in the
  entry's prose (*`tasks.md`*, superseded and retired tasks).
  *(format-grammar D-5, D-9, D-12 · REQ-C1.2, REQ-C1.4, REQ-D1.6, REQ-D1.11.)*
- 2026-08-26 — What a writer owes when it acts on findings. The writer prose
  gains the obligation half of the anchor-writership contract, alongside the
  permission it already stated: a skill editing anchored content in a signed
  bundle — applying a review finding to it, or acting on an edit its own
  implementation work revealed — runs the stale-anchor pre-flight before its
  first such edit (blocking on a mismatch, an absent or unparseable entry, and
  a failed recompute alike), lands an expression-only edit with its Changelog
  entry and marked self-re-anchor entry in one commit, and refuses a
  meaning-class finding to a `/spec-kickoff` delta re-walkthrough (*Sign-off
  records and content anchors*). Stated here rather than in `gate-wiring.md`
  because that doc scopes itself to this repository's three gate-wired skills,
  while this obligation binds the act: a review skill shipped from another
  repository owes the same three and follows through its own. The named skills
  instantiate it in their own prose as the same task. **No version bump:** no
  authoring rule changes — a writer obligation that was already implied by the
  expression-only lane becomes explicit.
  *(anchor-integrity D-5 · REQ-C1.1, REQ-C1.2, REQ-C1.3.)*
