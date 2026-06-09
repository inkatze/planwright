Advance work on a pair-flow spec by selecting the next ready task (or bundle), creating or reusing a worktree (D-54), and dispatching `/execute-task`. Each invocation is a **stateless step machine** (D-5): read `tasks.md`, compute the next legal move, perform it, update state, exit. Multiple invocations across sessions or hosts accumulate naturally.

`/orchestrate` picks at most one task (or one bundle per D-11) per invocation (D-52). Intra-spec parallelism is achieved by running `/orchestrate` in multiple sessions; each picks the next independent task.

Sources: REQ-D1.1 through REQ-D12.1, REQ-A3.3, D-5, D-11, D-15, D-17, D-19, D-21, D-24, D-31, D-32, D-33, D-36, D-37, D-44, D-52, D-54 in `specs/pair-flow/`.

## When to use

You have a spec at `Active` status with a signed-off kickoff brief and want the system to pick and execute the next ready task autonomously. Two common entry paths:

- **Manual**: you invoke `/orchestrate specs/<name>` in a tmux pane. It picks a task, creates or reuses a worktree (D-54), executes, opens a draft PR, then exits.
- **Scheduled**: Task 12's bookkeeping runner invokes `/orchestrate` on its cadence. Bookkeeping moves (PR-merge reconciliation, pickup advancement) happen without spawning a full execution.

## Pre-flight (once per run)

### 1. Resolve the spec path

Read `$ARGUMENTS`. Ignore any flags (e.g., `--bookkeeping`) when resolving the spec path; the path is the first non-flag token. If a path token is present (e.g., `/orchestrate specs/pair-flow` or `/orchestrate --bookkeeping specs/pair-flow`), use it. If no path token is present, check:

- Current branch matches D-32 (`pair-flow/<spec>/task-<ids>`) and derive the spec.
- Repo root contains exactly one `specs/*/requirements.md` with `Status: Active`.
- Otherwise, list available specs and ask.

Verify the directory exists and contains the four-file bundle.

### 2. Verify spec is Active (REQ-A3.3, D-33)

Read `requirements.md`. If status is not `Active`:

- `Draft`: halt with a clear message suggesting `/spec-kickoff`. Do not auto-chain into kickoff (D-36).
- `Done`: halt with "spec is complete, no tasks remain."

No bypass flag exists.

### 3. Verify kickoff brief exists (D-36)

Check for `specs/<spec>/kickoff-brief.md` with a final "Sign-off" section (not a partial brief). If absent or partial, halt and prompt the user to invoke `/spec-kickoff`. Do not auto-chain.

### 4. Run the spec validator (D-45)

```
~/.claude/scripts/spec-validate.sh <spec-path>
```

Since the spec is Active, validator failures are errors (exit 1). If errors exist, halt and surface them. The spec must be structurally sound before orchestration proceeds.

### 5. Acquire the advisory lockfile (D-17, D-37)

The lockfile is at `specs/<spec>/.orchestrate.lock`. It serializes state-changing moves (task selection, `tasks.md` updates) but is released before `/execute-task` runs, allowing intra-spec parallelism.

**Acquire:**
- If the file does not exist, create it with: `{ "host": "<hostname>", "session": "<session-id>", "acquired": "<ISO timestamp>" }`.
- If the file exists and its `acquired` timestamp is older than the stale-lock threshold (default 15 minutes per `~/.claude/pair-flow.yml`), treat it as stale: log a warning, remove it, and re-acquire.
- If the file exists and is fresh (another runner holds it), exit cleanly with reason: "lock held by <host>/<session> since <time>; another orchestration is in progress." This is a no-op, not an error.

**Release:** delete the file after `tasks.md` is updated and before `/execute-task` is dispatched.

## Task selection

### 1. Build the dependency graph

Read `tasks.md`. Parse each task's `Dependencies:` line. Build a dependency graph where:

- **Completed tasks** are satisfied nodes.
- **In progress tasks** are in-flight (not available for pickup).
- **Awaiting input tasks** are blocked (not available).
- **Forward plan tasks** are candidates.

### 2. Identify ready tasks (REQ-D3.1)

A task is ready if:

- All its `Dependencies:` are listed in the `Completed` section.
- It is not currently in `In progress` or `Awaiting input`.

If no tasks are ready:

- If all tasks are in `Completed`: this is the final state. Flip spec status to `Done` (D-31) by editing `requirements.md` `**Status:** Active` to `**Status:** Done` and updating `Last reviewed:` to today. Release the lock and exit with a message: "All tasks complete. Spec status flipped to Done."
- Otherwise: some tasks are blocked (dependencies in progress or awaiting input). Release the lock and exit with reason: "No ready tasks. Blocked on: <list of blocking tasks>."

### 3. Evaluate bundling (D-11, D-24)

If multiple ready tasks exist, evaluate whether any subset forms a valid bundle:

**Bundling rule (D-11):** all must hold:
- Tasks touch the same module or context.
- Tasks share dependencies.
- Combined diff is likely to stay under ~700 lines.

**Sizing estimate (D-24):**
1. Count files in each candidate task's `Citations:`.
2. Look up similar past PRs via `gh pr list --search` keyed on cited files/module.
3. Sum the median PR size of matched past PRs.
4. Bundle is approved if estimate is ≤ 700 lines and the other D-11 conditions hold.

Log the sizing estimate and reasoning for telemetry tuning (even if no bundle is formed).

If no valid bundle exists, pick the single highest-priority ready task (first in `Forward plan` order that is ready).

### 4. Record the selection

Note the selected task ID(s) for the dispatch phase.

## Dispatch

### 1. Resolve the worktree — reuse or create (D-44, D-54)

Do **not** unconditionally `git worktree add`. First decide where the work should run, then reuse or create.

**a. Detect whether you are already in a worktree.** Use the worktree predicate (same one the worktree-bootstrap hook uses):

```
[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ] && echo worktree || echo primary
```

`worktree` means the session is in a linked worktree; `primary` means the main checkout.

**b. Reuse a clean worktree (confirm only).** If you are already in a worktree and it is clean (`git status --porcelain` is empty), reuse it. Surface its path and branch and ask the user for a one-line confirmation, e.g. *"Already in worktree `<path>` on branch `<branch>` — run task `<ids>` here? (y/n)"*. On yes, skip creation and go to step 2 with this worktree. Do not pose the full where-to-work prompt.

**c. Ask where to work (primary checkout, or a worktree the user declines to reuse).** Ask the user: (a) work in the **current checkout/branch**, or (b) create a **fresh worktree**. If the invocation already pre-directed this (e.g. the user passed "implement in the current branch" / "use this worktree"), take that as the answer and pose no question. If the answer is the current checkout/branch, skip creation and go to step 2.

**d. Create a fresh worktree.** Create a branch following D-32 naming: `pair-flow/<spec>/task-<ids>`.

Examples:
- Single task: `pair-flow/auth/task-3`
- Bundle: `pair-flow/auth/task-3-4`
- Dotted ID: `pair-flow/pair-flow/task-3.5`

Place the worktree under the Claude-native path so `claude --worktree` and the `EnterWorktree` tool can discover it (D-54). `<branch-suffix>` is the part after the last `/` in the branch name (e.g. `task-3`):

```
git worktree add <repo-root>/.claude/worktrees/<branch-suffix> -b <branch-name>
```

Do **not** use the legacy sibling `<repo-root>--claude-worktrees-<branch-suffix>` path; it is invisible to Claude Code's native worktree tooling.

**e. Tell the user how to re-open it.** After creating or reusing a worktree, print the exact re-open command so a backgrounded task is resumable in a fresh session:

```
cd <repo-root>/.claude/worktrees/<branch-suffix> && claude
```

(`claude --worktree <name>` always *creates* a new worktree rather than attaching, so the `cd` + `claude` form is the correct re-open path.)

### 2. Update tasks.md (REQ-E3.1)

Move the selected task block(s) from `Forward plan` to `In progress`. Add annotation lines:

```
- **Status:** implementing
- **Last activity:** <today's date>
```

### 3. Release the advisory lock

Delete `specs/<spec>/.orchestrate.lock`. From this point, another `/orchestrate` invocation can acquire the lock and pick the next ready task (intra-spec parallelism per D-52).

### 4. Dispatch `/execute-task`

If step 1 **created a fresh worktree you are not already in**, switch into it using `EnterWorktree` (load the tool schema via `ToolSearch` first if needed) so that `/execute-task`'s file reads, edits, git operations, and CI runs all target the task branch, not the original checkout. If step 1 **reused the current worktree or chose the current checkout/branch**, you are already in the right place — skip `EnterWorktree`.

Then invoke `/execute-task <task-ids>` with the spec path. This runs in-session (D-39): same context, hooks fire normally, inbox state belongs to this session.

After `/execute-task` returns, if you called `EnterWorktree`, use `ExitWorktree` to return to the original checkout. This ensures `tasks.md` updates (which live in the spec directory of the main checkout) are written to the right place. If you never switched (reuse / current-checkout path), there is nothing to exit.

### 5. Exit after `/execute-task` returns

`/execute-task` exits in one of two states:

- **Draft PR opened**: the task is done pending review. `tasks.md` already updated by `/execute-task`.
- **Awaiting input**: something blocked execution. `tasks.md` already updated by `/execute-task`.

In either case, `/orchestrate` exits. The next invocation (manual or scheduled) will read the updated `tasks.md` and compute the next move.

**Looping across tasks.** Each `/orchestrate` invocation handles one task (D-52). To advance through the full task graph autonomously, wrap with `/loop /orchestrate <spec-path>`. The loop self-paces: each iteration picks the next ready task, and the loop terminates when orchestrate exits with "no ready tasks" or "all complete."

## Bookkeeping mode (for Task 12's scheduled runner)

When `$ARGUMENTS` contains `--bookkeeping`:

Skip the full dispatch flow. Instead, perform only reconciliation moves:

1. **PR-merge reconciliation.** For each task in `In progress` whose annotation shows `PR #N draft`, check PR state via `gh pr view <N> --json state`. If `MERGED`, move the task to `Completed` with the standard one-line bullet.
2. **Stale In-progress detection.** If a task's `Last activity:` is older than 48 hours and its PR is not in `MERGED` or `OPEN` state, move it to `Awaiting input` with a note: "stale, PR not found."
3. **Advance pickups.** After reconciliation, check if new tasks are now ready (deps just moved to Completed). Post an inbox entry for each newly-ready task.
4. **Spec completion check.** If all tasks are now Completed, flip status to Done (D-31).

Bookkeeping mode still acquires and releases the lock. It exits after reconciliation without dispatching `/execute-task`.

## Stop conditions (mandatory human handoff)

| Condition | Trigger |
|---|---|
| **Spec not Active** | Pre-flight step 2. Halt with suggestion. |
| **No kickoff brief** | Pre-flight step 3. Halt with prompt. |
| **Validator errors** | Pre-flight step 4. Halt with error list. |
| **Lock contention** | Pre-flight step 5. Clean no-op exit. |
| **No ready tasks** | Task selection step 2. Informational exit. |
| **`gh` not authenticated** | Worktree creation or PR steps. Halt with "run `gh auth login`" message (D-43). |
| **Worktree creation fails** | Git error during `git worktree add`. Surface error and halt. |

## Invariants

These hold at every step:

- **Stateless across invocations** (D-5). No in-memory state persists. Each run reads `tasks.md` fresh.
- **One task or bundle per invocation** (D-52). Never fan-out within a single invocation.
- **Lock held only during state-changing moves** (D-17, D-37). Released before `/execute-task` runs.
- **Never auto-merge** (D-21). PRs are always drafts. Merge is a reserved human action.
- **Never auto-chain into `/spec-kickoff`** (D-36). Halt and prompt instead.
- **Cross-spec independence** (D-37). Each spec has its own lockfile. Concurrent invocations on different specs proceed independently.
- **Never bypass the Active status gate** (D-33). No flag, no escape hatch.
- **Never force-push, amend, squash, or rebase.** Create new commits only.
- **Never write to `~/.claude/pair-flow.local.yml` without confirmation** (REQ-D9.1).

## Maintenance

After completing an orchestration run (or halting), check if any part of these instructions seems outdated or misaligned with: changes to REQ-D1-D12, D-5, D-11, D-17, D-21, D-24, D-31, D-32, D-33, D-36, D-37, D-44, D-52, D-54; changes to `/execute-task`'s interface; changes to the lockfile or `tasks.md` format; changes to `pair-flow-config.sh` subcommands. If something looks off, flag it and offer a ready-to-use prompt to update this command.

$ARGUMENTS
