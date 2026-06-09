Walk a spec at `<spec-path>` section by section with the human, producing a signed-off kickoff brief at `specs/{feature}/kickoff-brief.md`. The brief is the durable contract between human and agent: every downstream pair-flow skill (`/execute-task`, `/orchestrate`) operates from it, not by re-reading the spec.

`/spec-kickoff` is a **didactic walkthrough, not a checklist** (D-7). The value is in the agent restating each section in its own words, surfacing implicit domain terms, and posing Socratic checks the human can answer or red-line. Questions that surface things neither party realized needed to be said are the success signal. A walkthrough that flows without friction probably means the questions were too soft.

The brief is written **incrementally** (D-41): each signed-off section appends to `kickoff-brief.md` immediately, so a killed session leaves a partial brief that the next invocation resumes from. The spec status flips `Draft` → `Active` on the final sign-off (D-31, REQ-A3.2), and the spec is committed to git as part of the bundle (REQ-A2.11, D-49).

Sources: REQ-A2.1 through REQ-A2.12, REQ-A3.1, REQ-A3.2, REQ-D9.1, D-7, D-19, D-20, D-27, D-31, D-35, D-40, D-41, D-42, D-49, D-51 in `specs/pair-flow/`.

## When to use

You have an existing spec bundle (a `specs/{feature}/` directory with `requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) and you want to sign off on a shared understanding before letting `/execute-task` or `/orchestrate` run against it. Two paths converge here:

- **New spec.** Just drafted with `/spec-draft` (or by hand). No prior brief. Walk the whole thing.
- **Retrofit on an existing spec.** The spec predates pair-flow or its task structure does not meet D-15. The skill walks the spec normally, and at the task-graph step proposes the patches needed to make it orchestratable (stable IDs, `Done when:`, `Dependencies:`, `Citations:` per task).

A third path is **partial-invalidation re-walkthrough** (D-27, D-35): a previously signed-off brief exists, but the spec changed. The skill detects which sections of the brief are still valid and walks only the rest.

`/spec-kickoff` does **not** implement code, open PRs, or run tests. Its only output is the brief plus the status flip and, in retrofit mode, edits to the spec bundle itself.

## Pre-flight (once per run)

1. **Resolve the spec path.** Read `$ARGUMENTS`. If empty, ask the user for the spec path; do not guess from the cwd. Verify the path exists and is a directory. If not, halt with a clear error.

2. **Verify the four-file bundle.** Confirm `requirements.md`, `design.md`, `tasks.md`, `test-spec.md` all exist in the directory. If any is missing, halt and ask whether the user wants to invoke `/spec-draft` instead. `/spec-kickoff` does not create the bundle from scratch.

3. **Run the structural validator.**

   ```
   ~/.claude/scripts/spec-validate.sh <spec-path>
   ```

   Capture the full output and the exit code.

   - Exit 0 with 0 warnings: structure is clean; proceed.
   - Exit 0 with warnings (status is `Draft`): retrofit-mode candidate. Surface the warnings to the user, name this as retrofit mode, and confirm before proceeding. If the user declines, halt cleanly.
   - Exit 1 (status is `Active` with errors): refuse to proceed until the gaps are fixed. The spec is already Active per its header but does not meet the orchestration bar; do not produce a brief on a structurally broken Active spec.
   - Exit 2 or other: surface the error and halt.

4. **Resolve repo configuration.** Run:

   ```
   ~/.claude/scripts/pair-flow-config.sh repo-class
   ```

   - Exit 0 with a value (`solo` or `multi-reviewer`): use it.
   - Exit 2 with `needs-confirmation:<inferred>`: surface the inferred value and the reasoning ("inferred from PR review history: no non-author human reviewers seen in last 30 PRs" or equivalent), and ask the user to confirm or override per REQ-D9.1 / D-20. **Never** call `confirm-repo-class` without an explicit human confirmation. On confirmation, run:

     ```
     ~/.claude/scripts/pair-flow-config.sh confirm-repo-class <value>
     ```

   - On decline, continue without writing; the brief can still be produced. The next invocation will re-prompt.

   The repo-class is recorded in the brief's preamble. It does not gate anything in this skill; downstream skills (`/polish`, `/execute-task`) consult it for the Agent-resolvable bucket.

5. **Detect an existing brief and compute invalidation scope.** Check for `specs/{feature}/kickoff-brief.md`.

   - **No brief exists.** Walk the whole spec.

   - **Partial brief exists** (the file is present but missing the final "Sign-off" section). Treat the last successfully-written section as the resume point per D-41. Show the user a one-line summary of completed sections and ask whether to resume or restart. Restart deletes the partial file and walks from the top.

   - **Signed-off brief exists.** Look at the `**Spec commit:**` line in the brief. Diff the spec files since that commit. Apply the D-51 wholesale-rewrite trigger:

     1. Both `requirements.md` AND `design.md` changed in the same commit → whole-brief invalidation.
     2. More than 50% of REQ-IDs (or D-IDs) changed in a single commit (additions or modifications; pure removals do not count) → whole-brief invalidation.

     Otherwise apply section-scoped invalidation per D-27:

     - Change to `requirements.md` REQ-X → invalidate brief sections referencing REQ-X.
     - Change to `design.md` D-Y → invalidate brief sections referencing D-Y.
     - Change to `tasks.md` (reorder, retitle, add, remove) → invalidate the Task graph section only.
     - Change to `test-spec.md` → invalidate the Verification section only.

     Show the user a one-line summary of unchanged sections (anchor context per D-35) and confirm before walking only the invalidated set.

6. **Initialize the brief skeleton if needed.** If no brief exists, write the preamble (spec path, spec commit hash from `git rev-parse HEAD`, today's date, repo-class, retrofit-mode flag if any). Commit nothing yet; the skill writes to the working tree only.

## The walkthrough

The walkthrough has **seven sections** (the same sections become the brief's sections). Walk them in order. For each section, follow the per-section pattern below.

### Section order

1. **Goal and glossary** — restate the spec's stated goal; surface implicit domain terms; confirm the glossary covers what it needs to.
2. **Requirements walkthrough** — REQ by REQ. Restate, raise edge cases, surface implicit assumptions.
3. **Design walkthrough** — D by D. Restate the decision, restate alternatives and why this one was chosen, check whether the rationale still holds today.
4. **Verification approach** — walk `test-spec.md`. Confirm every REQ is pinned to a verification path. Surface REQs that are only `[design-level only]` or `[manual]` without a concrete check.
5. **Task graph reconstruction** — read `tasks.md`. Topologically order tasks by `Dependencies:`. Identify parallelizable tasks. Surface unstated dependencies (a task that obviously depends on another but does not list it). In retrofit mode, this is where structural patches to `tasks.md` are proposed.
6. **Risk register** — synthesize across the prior sections. What is underspecified? What depends on external systems? What could plausibly fail and how would we notice?
7. **Sign-off** — final confirmation. Status flip happens here.

### Interaction style

The walkthrough is cognitively heavy. These rules keep it focused and scannable.

**Progress indicator.** Show a persistent progress line at the start of every message:

```
── spec-kickoff ── Section 3 of 7: Design ── [████████░░░░░░] 12/23 D-IDs walked ──
```

The bar shows: current section, section name, and a granular count within the section (REQs walked, D-IDs walked, tasks reconstructed, etc.). Update it every message.

**Progressive disclosure.** Lead with the restatement summary (bullets or a short table), not multi-paragraph prose. Expand into full prose only for sections where nuance matters or when the user asks. The restatement should be substantive enough to spot a misread, but that does not require paragraphs; a structured list of "claims, rules out, assumes" often works better.

**Visual aids.** Use tables for REQ walkthroughs (one row per REQ: ID, summary, edge case, assumption). Use ASCII graphs for task dependency reconstruction. Use comparison tables for design decisions being re-evaluated. Avoid walls of prose when structured formats communicate the same content.

**Selectors over open-ended questions.** When posing Socratic checks, use `AskUserQuestion` with concrete options whenever the question has enumerable answers. Include your assessment as the first option with "(Recommended)" appended. Reserve open-ended questions for genuinely open-ended moments (risk register synthesis, ambiguity the agent cannot enumerate). Example: instead of "Does the Chosen-because still hold?", ask via selector: `[Yes, rationale holds (Recommended)]`, `[No, rationale changed — here's why]`, `[Partially — needs amendment]`.

**Smart defaults.** When the restatement is straightforward and no edge cases are apparent, say so: "This section is clear; no implicit terms or edge cases found. Confirm and move on?" Don't manufacture Socratic questions for sections that don't need them.

**Running summary.** At each section transition, show a compact status table:

```
| Section | Status | Key items |
|---|---|---|
| 1. Goal & glossary | ✓ signed off | 3 implicit terms surfaced |
| 2. Requirements | ✓ signed off | 12 REQs, 2 edge cases raised |
| 3. Design | ◆ in progress | 8/23 D-IDs walked |
| 4. Verification | ○ pending | — |
| 5. Task graph | ○ pending | — |
| 6. Risk register | ○ pending | — |
| 7. Sign-off | ○ pending | — |
```

**Small bites.** Walk REQs and D-IDs in batches of 3-5, not the entire section at once. Each batch gets its own restatement + Socratic checks + confirmation. This keeps each interaction short and focused.

### Per-section pattern

For each section:

**a. Read.** Read the relevant portion of the spec file(s) directly. Do not paraphrase from memory.

**b. Restate.** Restate the section in the agent's own words. Format as structured output (bullets, tables, or a short list of "claims / rules out / assumes"), not paragraphs. Name the thing the section is claiming, the thing it is ruling out, and the assumption it carries. Keep it scannable.

**c. Surface implicit terms and assumptions.** Show as a compact bulleted list: "Implicit term: X means Y" / "Assumption: Z". If none found, say so explicitly rather than manufacturing items.

**d. Pose Socratic checks.** Raise the relevant flavor per section type:

- **Goal section:** slicing sanity — scoped tight enough to ship? Conflating multiple goals?
- **Requirements section:** edge cases — what input or state makes this REQ ambiguous?
- **Design section:** decision rationale — does "Chosen because" still hold?
- **Verification section:** verifiability — is the path actually executable?
- **Task graph section:** unstated dependencies — does Task N depend on M without listing it?
- **Risk register:** failure modes — what causes silent failure? Who notices?

Use `AskUserQuestion` with concrete options when the check has enumerable answers. Open-ended only when genuinely open-ended. Questions must be specific: "REQ-X1.1 says SHALL refresh every 30s — what happens on kill -9?" not "Are there edge cases?"

**e. Surface inconsistencies (D-42 escalation gate).** If a genuine inconsistency emerges, **halt the walkthrough**. Do not write the section to the brief. Use `AskUserQuestion` to offer the two D-42 paths:

   - **(a) Edit the spec.** User edits the spec files, then re-runs `/spec-kickoff`. Partial brief preserved.
   - **(b) Record an explicit override.** The apparent inconsistency is intentional. Record the override in the brief with a one-line explanation.

   Do not silently proceed.

**f. Wait for sign-off on the section.** Confirm via `AskUserQuestion`: `[Sign off this section (Recommended)]`, `[Red-line — I have changes]`, `[Halt — need to think]`. Take the time the user needs.

**g. Write the signed-off section to the brief.** Append to `kickoff-brief.md` immediately (D-41). Include:

   - The structured restatement
   - Surfaced implicit terms (bulleted list)
   - Socratic checks raised and the user's answers
   - Explicit assumptions the user red-lined in
   - `Signed off: <YYYY-MM-DD>` at the end

   Do not commit yet. The brief lives in the worktree; a commit lands after the final sign-off.

   Update `Last reviewed:` on the spec files only when the kickoff edits them (retrofit mode, D-42 path-b override notes).

### Retrofit mode specifics

When the validator surfaced warnings about D-15 task structure (missing `Done when:`, `Dependencies:`, `Citations:`, or stable IDs in `tasks.md`), the **Task graph reconstruction** section also produces patches to `tasks.md`:

- Walk each task in order.
- Propose stable IDs in the form `Task N` or `Task N.M` consistent with existing tasks in the bundle.
- Propose `Done when:` conditions derived from the task description, surfaced to the user for red-line.
- Propose `Dependencies:` derived from the task graph reconstruction work just done.
- Propose `Citations:` derived from REQs and Ds the task touches.

Each proposed patch waits for user red-line before being applied. Apply patches via `Edit`; update `Last reviewed:` on `tasks.md` to today (REQ-A2.9, D-40). Re-run the validator after patches are applied to confirm structure now meets the bar.

### Partial-invalidation walk

When only some brief sections are invalidated (D-27, D-35):

- Show the user a one-line per unchanged section to anchor context ("Section 2 (Requirements walkthrough): unchanged, signed off 2026-05-08.").
- Walk only the invalidated sections, using the per-section pattern.
- Overwrite each invalidated section in `kickoff-brief.md` with the freshly-walked content and a new `Signed off:` date.
- Leave unchanged sections alone.

## Sign-off and status flip

After the seventh section (Sign-off) is confirmed:

1. **Final confirmation prompt.** Surface the brief's current state to the user: section count, retrofit-mode flag, override notes if any, spec commit hash. Ask for explicit "sign off" confirmation. Anything less than an explicit confirmation means do not flip status.

2. **Flip spec status to Active.** Edit each of the four spec files' `**Status:** Draft` line to `**Status:** Active`. Update each file's `**Last reviewed:**` to today (REQ-A2.9, D-40). Use `Edit` per file; do not rewrite the files wholesale.

3. **Re-run the validator** against the bundle. Status is now Active, so warnings have become errors. If the validator reports any error, **revert the status flip on all four files**, surface the error, and ask the user how to proceed. Do not leave the spec in an Active-but-invalid state.

4. **Write the brief's final preamble fields.** Spec commit hash (from `git rev-parse HEAD`), final sign-off date, status-flip confirmed.

5. **Stage the changes.** `git add` the four spec files and `kickoff-brief.md` (and `tasks.md` patches if retrofit mode). Do **not** commit and do **not** push; the user runs commit on their own to allow them to bundle other changes or inspect first. Print the staged file list and a suggested commit message: `docs(spec): {feature} kickoff-brief; status Draft -> Active`.

The brief is now the contract. Downstream pair-flow skills can run against this spec.

## Stop conditions (mandatory human handoff)

Halt and hand control back when any condition fires. Do not work around any of these.

| Condition | Trigger |
|---|---|
| **Inconsistency in the spec** | D-42 surfaced a genuine contradiction. User chose path (a) to edit the spec, or refused path (b). Brief is not written. |
| **Validator error after status flip** | Status flip produced errors. Revert and surface. |
| **Retrofit declined** | Validator reported D-15 gaps but user declined retrofit. Brief is not produced (cannot sign off on a spec the user does not want to fix). |
| **Repo-class not confirmed** | The user declined to confirm the inferred `repo-class`. Brief proceeds but downstream Agent-resolvable behavior degrades; flag this in the brief's preamble. |
| **Partial brief stale beyond resume** | The partial brief references a spec commit the agent cannot find (force-pushed, rebased away). Stop and surface the staleness. |
| **Ambiguity that cannot be resolved in walkthrough** | A Socratic check exposes a question the user genuinely cannot answer in this session. Record it as an open question in the brief's risk register and ask whether to halt or continue. Continuing means the brief is incomplete and the open question must be closed before `/execute-task` runs against the task that depends on it. |
| **Spec validation failed before walk** | Active spec with errors at pre-flight step 3. |

## Invariants

These hold at every step:

- **Never** write to `kickoff-brief.md` until the human signs off on the section (D-41 incremental, not eager).
- **Never** flip status to `Active` without explicit human sign-off at section 7.
- **Never** silently write to `~/.claude/pair-flow.local.yml`. Always confirm with the human before calling `confirm-repo-class` (REQ-D9.1, D-20).
- **Never** produce a brief on a spec with an unresolved inconsistency (D-42).
- **Never** treat retrofit-mode patches as auto-applicable. Each patch waits for human red-line.
- **Never** commit or push. The human runs commit at the end.
- **Never** invoke `/execute-task`, `/orchestrate`, `/polish`, or any other pair-flow skill from inside the walkthrough. Kickoff is its own concern.
- **Never** skip the validator pre-run or the validator post-flip. The status-aware enforcement (D-45) is load-bearing.
- **Never** rewrite the four spec files wholesale on the status flip. Use `Edit` so the diff is surgical.

## Maintenance

After completing the walkthrough (or halting), check if any part of these instructions seems outdated or misaligned with the current pair-flow spec at `specs/pair-flow/`: changes to D-7, D-15, D-27, D-31, D-35, D-41, D-42, D-49, or D-51; new fields in `tasks.md`'s task structure; changes to the helper scripts. If something looks off, flag it and offer a ready-to-use prompt I can paste into a new dotfiles session to update this command.

$ARGUMENTS
