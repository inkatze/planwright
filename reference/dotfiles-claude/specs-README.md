# Specs

This directory holds plan-only specifications for improvements to the dotfiles
repo. Each spec follows a four-file convention (requirements.md, design.md,
tasks.md, test-spec.md) borrowed from another project. A spec is plan-only
until its tasks.md is implemented. New sessions working on improvements start
from this README as the planning surface.

## Spec status lifecycle

Each spec declares its status in `requirements.md` as `**Status:** Draft|Active|Done`:

- `Draft` — being authored or revised. Mutable. Validator runs task-structure checks as warnings.
- `Active` — signed off (via `/spec-kickoff` when pair-flow ships) and under execution. Validator runs task-structure checks as errors that block dependent skills.
- `Done` — all tasks moved to `Completed`. Historical artifact; brief retained indefinitely.

Status controls the severity of the task-structure checks only. The four-file presence check (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) always errors and exits 1 regardless of status, since it runs before status is even detected.

## Task conventions

Tasks in `tasks.md` shall have a stable ID (e.g., `Task 3`, `Task 3.5`), explicit `Deliverables:`, `Done when:`, `Dependencies:`, `Citations:`, and `Estimated effort:`. Tasks that introduce measurable behavior shall also include a `Measurement plan:` line listing metric, source, and baseline comparison — same shape and discipline as `Citations:`.

## `tasks.md` state sections

`tasks.md` is the canonical state record for orchestration (REQ-E1.1 in `pair-flow/`). It shall use H2 section headers naming the queue and the five state sections below; the ordering is presentation choice, not contract. Additional sections (e.g., `Open questions`) are allowed:

| Section | Purpose | Convention |
|---|---|---|
| `Forward plan` | Dependency-ordered queue of tasks not yet picked up. | Full task block (`### Task <id> — <title>` with `Deliverables:`, `Done when:`, `Dependencies:`, `Citations:`, `Estimated effort:`, optional `Measurement plan:`). |
| `In progress` | Tasks currently being implemented (one branch + draft PR per task or bundle). | Same block form as Forward plan, plus two annotation lines right after the H3: `- **Status:** <phase>` and `- **Last activity:** <YYYY-MM-DD>`. The phase value tracks the current step: `implementing`, `polish iter N`, or `PR #M draft`. The auto-update hook below writes the `PR #M draft` phase; `/execute-task` (when shipped) writes the earlier phases. |
| `Completed` | Tasks that have shipped. | One-line bullet per task: `- **Task <id> — <title>.** <one-sentence summary>. Completed in PR #<N> (<URL or PR ref>). See PR description for details.` The auto-merge hook writes a stub; the human is free to flesh out the summary with what was actually built (e.g., paths, validation notes, "verification deferred to user"). |
| `Awaiting input` | Tasks blocked on a human decision. | Bullet per task, with the question stated. |
| `Deferred` | Tasks consciously postponed with an explicit gate. | Bullet per task, including `**Gate:**` (the condition that re-opens the task). |
| `Out of scope` | Tasks excluded by design. | Bullet per task. Permanent, not deferred. |

## `tasks.md` auto-update hook

`roles/osx/files/claude/scripts/tasks-pr-sync.sh` is wired from `roles/osx/files/claude/settings.json` under `hooks.PostToolUse` with matcher `Bash`. It fires after every Bash tool call; the script itself filters to `gh pr create` and `gh pr merge` and parses the current branch against the pair-flow naming convention (D-32: `pair-flow/<spec>/task-<ids>`, where `<ids>` is either a single id like `3` / `3.5` or a bundle like `3-4` / `3.5-4`).

- **On `gh pr create`**: the matching task block(s) move from `Forward plan` to `In progress`. Two annotation lines (`Status: PR #N draft`, `Last activity: <today>`) are inserted right after the H3 header. Existing Status/Last-activity lines are stripped first, so the hook is idempotent.
- **On `gh pr merge`**: the matching task block(s) move from wherever they are (typically `In progress`) to `Completed` as one-line bullets referencing the PR. The original task block (with `Deliverables:`, etc.) is removed; the PR carries the implementation detail.

The hook is silent on no-op cases (non-Bash tool, non-matching command, branch not in D-32 format, no matching task block in `tasks.md`). Out-of-session merges (the user clicks Merge in the GitHub web UI) are reconciled by the scheduled remote agent runner per D-29 once that ships (Task 12). The hook does not commit the change; it leaves a `git status` diff for the next commit boundary.

| Spec | Status | Purpose | Cold-start next step |
|---|---|---|---|
| `claude-context/` | Done | Repo-root `CLAUDE.md` giving Claude Code the minimum non-obvious context to act correctly in this repo. | N/A |
| `metrics-baseline/` | Done | Structured baseline snapshot of Claude Code usage metrics for measuring improvement deltas. | N/A |
| `pair-flow/` | Active | Spec-driven pipeline that pairs human and agent from comprehension through execution and orchestration. Defines `/spec-draft`, `/spec-kickoff`, `/execute-task`, `/orchestrate`, `/resume`, the new `Agent-resolvable` finding bucket, and the inbox + tmux dashboard substrate. | Read `pair-flow/kickoff-brief.md` for the signed-off contract, then `tasks.md` for current state (Completed / In progress / Forward plan). `requirements.md` and `design.md` are the underlying spec. |
