Interactively elicit a spec from the user, producing the four-file bundle (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) at `specs/{feature-name}/` with status `Draft`. The skill guides the user through structured thinking about goals, requirements, design decisions, task decomposition, and verification paths.

`/spec-draft` is a **collaborative authoring tool**, not a one-shot generator. Each section pauses for user input, red-lining, and confirmation before proceeding. The output is a spec bundle ready for `/spec-kickoff` sign-off.

Sources: REQ-A1.1 through REQ-A1.7, REQ-A3.1, REQ-A3.2 in `specs/pair-flow/`.

## When to use

You want to create a new spec for a feature, improvement, or system change. Two entry paths:

- **From scratch**: you have an idea and want to structure it.
- **From seed material** (REQ-A1.7): you have notes at `specs/_pending/notes.md`, a spike doc, partial requirements, or a conversation transcript. The skill uses these as input to bootstrap the draft.

After `/spec-draft` produces the bundle, the next step is `/spec-kickoff` to walk through and sign off.

## Pre-flight (once per run)

### 1. Parse the feature name from `$ARGUMENTS`

Read `$ARGUMENTS`. If a feature name is provided (e.g., `/spec-draft handover-brief`), use it as the directory name: `specs/<feature-name>/`. If empty, ask the user for a short kebab-case name.

Verify the target directory does not already exist. If it does, ask whether to overwrite (destructive) or resume from the existing partial state.

### 2. Check for seed sources (REQ-A1.7)

Look for seed material in order:

1. `specs/_pending/notes.md` — a staging area for unstructured ideas.
2. A file path provided in `$ARGUMENTS` (e.g., `/spec-draft handover-brief ~/notes/handover-ideas.md`).
3. Ask the user if they have any existing notes, spike docs, or conversation transcripts to seed from.

If seed material exists, read it and use it as the starting point for the requirements elicitation. Cite the seed in requirements where applicable.

If no seed material exists, start from the user's verbal description.

## Interaction style

The drafting process is heavy by nature. These rules keep cognitive load manageable without sacrificing rigor.

**Progress indicator.** Show a persistent progress line at the start of every message during the drafting process:

```
── spec-draft ── Phase 2 of 5: Requirements ── [██████░░░░] 3/7 REQs confirmed ──
```

The bar shows: current phase, phase name, and a granular count within the phase (REQs confirmed, decisions confirmed, tasks confirmed, etc.). Update it every message.

**Progressive disclosure.** Lead with the summary or the artifact, not the reasoning. Show a table, a draft, or a one-liner first. Expand reasoning only when the user asks "why?" or when a non-obvious tradeoff needs flagging. The default is: show the thing, ask the question.

**Visual aids.** Use tables for structured comparisons (alternatives, REQ lists, task summaries). Use ASCII dependency graphs for task ordering. Use markdown formatting (bold for decisions, bullets for options) to create scannable structure. Avoid multi-paragraph prose when a table communicates the same information.

**Selectors over open-ended questions.** When asking the user to choose or confirm, use `AskUserQuestion` with concrete options. Include your recommendation as the first option with "(Recommended)" appended. Reserve open-ended questions for Phase 1 (goal elicitation) and genuinely open-ended moments where you cannot enumerate options.

**Smart defaults.** When you have a strong recommendation, present it as the default: "I'd go with X because Y. OK?" The user confirms or redirects. Don't make the user read three alternatives when one is clearly better.

**Draft-then-refine.** Show the output artifact early (even partial). It is easier to react to "change this line" than to answer "what should the requirement say?" When proposing REQs, show the actual `requirements.md` text, not a description of what it would say.

**Running summary.** At each phase transition, show a compact status table of what has been decided so far:

```
| Phase | Status | Items |
|---|---|---|
| Goal & scope | ✓ confirmed | 1 goal, 3 out-of-scope |
| Requirements | ✓ confirmed | 7 REQs across 3 groups |
| Design | ◆ in progress | 2/5 decisions confirmed |
| Tasks | ○ pending | — |
| Verification | ○ pending | — |
```

**Small bites.** Present 2-4 items at a time for confirmation, not the full list. A batch of 3 REQs with selectors is faster than 7 REQs with open-ended discussion.

## The drafting process

The drafting process has **five phases**, each producing content for one or more of the four output files. Each phase is interactive: propose, discuss, revise, confirm.

### Phase 1: Goal and scope (feeds `requirements.md` header)

**a. Ask the user to describe the feature.** Open-ended: "What problem does this solve? Who benefits? What does success look like?" This is the one phase where open-ended questions are the right tool.

**b. Propose a one-paragraph goal statement.** Show it as the actual `requirements.md` header text (draft-then-refine). It should be specific enough that someone could tell whether the system achieves it.

**c. Surface scope boundaries.** Use `AskUserQuestion` to propose candidate out-of-scope items as a multi-select checklist. Add your reasoning as the description for each option. The user confirms, adds, or removes.

**d. Confirm.** User red-lines the goal and scope. Revise until confirmed.

### Phase 2: Requirements elicitation (feeds `requirements.md`)

**a. Extract requirement candidates.** From the goal, scope, and seed material, propose REQ candidates in batches of 3-4. Show each batch as the actual `requirements.md` text:

```markdown
## REQ-A — Lifecycle

- **REQ-A1.1** The system SHALL ...
- **REQ-A1.2** The system SHALL ...
```

Each REQ gets a stable ID (`REQ-<Group><N>.<M>`), SHALL/MUST language, and a citation.

**b. Socratic checks via selectors.** For each batch, surface edge cases and ambiguities as `AskUserQuestion` selectors, not open-ended prose. Example: instead of "Are there edge cases?", ask "REQ-A1.1 says SHALL refresh every 30s. What happens on kill -9?" with options like `[Silent drop (Recommended)]`, `[Stale entry persists until sweep]`, `[Add explicit cleanup requirement]`.

**c. Iterate.** After each batch is confirmed, show the running REQ count in the progress indicator. Continue until the user confirms the set is complete. Use `AskUserQuestion` to ask "These N REQs cover the scope. Add more, or move to design?" with options.

**d. Organize into groups.** Show the proposed grouping as a table. Confirm with a selector if the grouping is non-obvious.

### Phase 3: Design decisions (feeds `design.md`)

**a. Identify decision points.** From the requirements, identify places where alternatives exist. Present the full list as a numbered table first (one line per decision), then walk through each.

**b. For each decision point, show a comparison table:**

```
| Option | Pros | Cons |
|---|---|---|
| **A: <name> (Recommended)** | <pro> | <con> |
| B: <name> | <pro> | <con> |
| C: <name> | <pro> | <con> |
```

Use `AskUserQuestion` with the options and your recommendation. The description for each option carries the rationale so the user gets the context without reading a paragraph.

**c. Surface cross-cutting concerns.** Present as a bulleted list, not prose. Confirm with a single selector.

**d. Confirm.** After all decisions, show the running summary table and confirm the full design section.

### Phase 4: Task decomposition (feeds `tasks.md`)

**a. Propose tasks.** Show the task list as a summary table first:

```
| ID | Title | Deps | Effort | Citations |
|---|---|---|---|---|
| 1 | <title> | none | half day | REQ-A1.1, D-1 |
| 2 | <title> | 1 | 1 day | REQ-B1.1 |
```

Then show the dependency graph as ASCII:

```
Task 1 ──→ Task 3 ──→ Task 5
Task 2 ──→ Task 4 ──┘
```

Each task must have: stable ID, title, deliverables, Done-when, Dependencies, Citations, Estimated effort. The full task blocks (as they will appear in `tasks.md`) are shown after the summary table is confirmed, for final red-line.

**b. Order by dependency.** Tasks with no dependencies come first. Critical-path tasks highlighted in the graph.

**c. Identify parallelism.** Annotate the ASCII graph with parallel lanes where tasks can run concurrently.

**d. Confirm.** Use `AskUserQuestion` per batch of 2-3 tasks for fine-grained confirmation. Show the full `tasks.md` text at the end for final red-line.

**e. Add state sections.** Write the `tasks.md` with the standard sections per `specs/README.md`: `Forward plan` (all tasks initially), `Completed`, `In progress`, `Awaiting input`, `Deferred`, `Out of scope`.

### Phase 5: Verification paths (feeds `test-spec.md`)

**a. Pin each REQ to a verification path** (REQ-A1.5). Show the coverage as a matrix table:

```
| REQ | Verification | Type |
|---|---|---|
| REQ-A1.1 | `test_heartbeat_refresh/1` | test |
| REQ-A1.2 | Gherkin: inbox sweep on stale | Gherkin |
| REQ-A2.1 | Cold-read of brief by user | manual |
| REQ-C1.6 | Existing buckets unchanged by design | design-level |
```

Use `AskUserQuestion` per batch of 3-4 rows to confirm or adjust. For REQs where the verification path is non-obvious, propose options.

**b. Use Gherkin selectively** (per D-8). Use `Given / When / Then` format when the behavior benefits from explicit state/trigger/outcome separation. Not required for every entry.

**c. Confirm coverage.** Every REQ must appear in `test-spec.md`. Surface any REQ that has no clear verification path and ask the user how to verify it.

## Writing the bundle

After all five phases are confirmed, write the four files:

### `requirements.md`

```markdown
# <Feature Name> — Requirements

**Status:** Draft
**Last reviewed:** <today's date>

## Goal

<goal statement from Phase 1>

## <Group A name>

- **REQ-A1.1** <requirement text>
...

## Sources

<citations to seed material, conversations, docs>
```

### `design.md`

```markdown
# <Feature Name> — Design

**Status:** Draft
**Last reviewed:** <today's date>

## Decision log

### D-1: <decision title>

**Decision:** <what was chosen>

**Alternatives considered:**
- <alternative 1>. Rejected because: <reason>.

**Chosen because:** <rationale>

...

## Cross-cutting concerns

<themes from Phase 3c>
```

### `tasks.md`

```markdown
# <Feature Name> — Tasks

**Status:** Draft
**Last reviewed:** <today's date>

## Forward plan

### Task 1 — <title>

- **Deliverables:** <artifacts>
- **Done when:** <conditions>
- **Dependencies:** <task IDs or "none">
- **Citations:** <REQ-IDs, D-IDs>
- **Estimated effort:** <estimate>

...

## Completed

(none yet)

## In progress

(none yet)

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
```

### `test-spec.md`

```markdown
# <Feature Name> — Test Spec

**Status:** Draft
**Last reviewed:** <today's date>

## <Group A name>

### REQ-A1.1 — <short description> [manual|test|Gherkin]

<verification path>

...
```

## Post-write validation (REQ-A1.6)

After writing all four files, run the spec validator:

```
~/.claude/scripts/spec-validate.sh specs/<feature-name>
```

- **0 errors, 0 warnings:** the spec meets the structural bar. Declare it stakeholder-ready.
- **Warnings:** surface them to the user. These are non-blocking but worth addressing. Offer to fix them inline.
- **Errors:** surface them. These must be fixed before the spec is usable by `/spec-kickoff`. Fix inline and re-run.

Do not declare the spec stakeholder-ready until the validator passes with 0 errors.

## Final output

After validation passes, tell the user:

1. The bundle is at `specs/<feature-name>/` with status `Draft`.
2. Next step: review the bundle cold, then invoke `/spec-kickoff specs/<feature-name>` to walk through and sign off (flips to Active).
3. The files are in the working tree (not committed). The user should review and commit at their discretion.

## Invariants

These hold at every step:

- **Status is always `Draft`** (REQ-A3.1). Only `/spec-kickoff` flips to Active.
- **All four files produced as a bundle.** No partial output (either all four or none).
- **Every REQ has a stable ID, SHALL/MUST language, and a citation.**
- **Every D-ID has Decision, Alternatives considered, and Chosen because.**
- **Every task has Deliverables, Done when, Dependencies, Citations, and Estimated effort.**
- **`test-spec.md` covers every REQ** with at least one verification path entry.
- **Interactive throughout.** Never generate the full bundle without user confirmation at each phase. The value is in the user thinking through the structure, not in the generated text.
- **Never commit or push.** The user handles that.
- **Never invoke `/spec-kickoff` or any execution skill.** Drafting and sign-off are separate concerns.
- **Validator must pass** before declaring the spec stakeholder-ready (REQ-A1.6).

## Maintenance

After completing a draft (or halting), check if any part of these instructions seems outdated or misaligned with: changes to the four-file format in `specs/README.md`, changes to the validator's checks, changes to the `tasks.md` section conventions, or changes to REQ-A1.x in the pair-flow spec. If something looks off, flag it and offer a ready-to-use prompt to update this command.

$ARGUMENTS
