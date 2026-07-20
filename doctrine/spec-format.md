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

**Blocks move whole; definition fields are never deleted.** A state move
relocates the entire block between sections and adjusts annotations. In
format-version 1 a completed task keeps its full block (annotated, not
collapsed to a summary bullet): the content anchor's canonical extraction
(below) requires that definition content survive every state move, so that
orchestration moves never change the anchor. Implementation detail lives in
the PR; the block stays the durable definition record.

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

After the header block and an intro stating the coverage mix, every REQ is
pinned to at least one verification path as an H3 entry:

```markdown
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
four H2 sections: `## Tasks` (all task blocks, in dependency order, never
moving), `## Awaiting input`, `## Deferred`, and `## Out of scope`
(`(none yet)` when empty). The placement sections (`## Forward plan`,
`## In progress`, `## Completed`) and the state annotation bullets
(`Status`, `Last activity`, `Dispatch`) do not exist: a task block carries
its five definition fields and nothing else. A block is edited only for
definition changes via the amendment ritual; derived execution-state
changes never produce commits. Parking and unparking writes (by the human
or a halting skill) are human-owned payload, not execution state.

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

**Read surface and anchor.** The status render (the derivation engine
surfaced as a command) is the canonical execution-status read surface; no
derived-status artifact is committed or remote-mirrored. The normative
completion annotation has no v2 home (the 2026-07-10 entry below is scoped
to version 1; D-11). Anchor mechanics are unchanged — the canonical
extraction selects `### Task` blocks wherever they sit — and with no
derived writes, no orchestration or execution act moves the anchor.

**Validation.** The validator enforces these invariants as errors on
non-Draft v2 bundles and warnings on Draft; a missing or unparseable
`Format-version:` errors at every status, and every version-keyed script
fails closed on it, never falling open to the v1 write path.

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
  dispositioned lens pass.
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

### The content anchor

The anchor (REQ-F1.9, D-45) is the hash of the per-file digest list: each
file hashed with `git hash-object`, the four digests in canonical order
(requirements, design, tasks, test-spec) hashed as a stream. Manifest-style
hashing is boundary-safe, unlike hashing a bare concatenation.

`tasks.md` contributes its **task-definition content only**, per the
canonical extraction below, so `/orchestrate`'s own state moves never trip
the freshness gate while meaning edits always do.

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
   expression-only re-anchor.

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

Guidance refinements that do not change a format version's rules are
recorded here without a version bump — a bundle authored to the affected
version stays conformant:

- 2026-07-10 — Derived-content authoring guidance. The `tasks.md` guidance no
  longer suggests a hand-drawn dependency graph in intro prose (`Dependencies:`
  lines are the sole source of truth; `scripts/spec-graph.sh` renders the
  on-demand view); the kickoff-brief guidance gains the cite-don't-copy
  convention for derived figures; and the
  `Completed · PR #<n> merged <YYYY-MM-DD>` completion annotation is promoted
  from illustrative to normative, with its single degraded form
  `Completed · merged <YYYY-MM-DD>` and the unstamped fallback pinned.
  *(Scoped to format-version 1 bundles by the 2026-07-14 entry.)*
