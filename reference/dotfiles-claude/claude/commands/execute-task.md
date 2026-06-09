Implement one task (or a bundled set of tasks) from a signed-off pair-flow spec. Reads the kickoff brief slice for the task, writes a verifying or regression test first, implements until green, runs the project's full CI, invokes `/polish --nested` as the convergence step, then opens a draft PR.

`/execute-task` is the **workhorse of the autonomy pipeline**. It assumes the worktree already exists (created by `/orchestrate` or manually by the user) and that the spec has been signed off via `/spec-kickoff`. It never creates worktrees, never merges, and never marks PRs ready for review.

Sources: REQ-B1.1 through REQ-B1.11, REQ-A3.3, REQ-E3.1, D-19, D-21, D-25, D-33, D-36, D-39, D-44, D-53 in `specs/pair-flow/`.

## When to use

You have a spec at `Active` status with a signed-off kickoff brief and a specific task (or bundle) to implement. Two entry paths:

- **Via `/orchestrate`**: the orchestrator picks the task, creates the worktree, and dispatches `/execute-task`. You don't invoke it yourself.
- **Standalone**: you pick a task manually, create or navigate to the worktree, and invoke `/execute-task <task-id>` (or `/execute-task <id1> <id2>` for a bundle).

## Pre-flight (once per run)

### 1. Parse task IDs from `$ARGUMENTS`

Read `$ARGUMENTS`. Extract one or more task IDs (e.g., `5`, `3.5`, `5 6` for a bundle). If empty, halt with a clear error asking the user which task to execute.

### 2. Resolve the spec path

Try in order:

**a. From `$ARGUMENTS`.** If a path-like argument is present (e.g., `/execute-task 5 specs/pair-flow`), use it.

**b. From branch name.** Parse the current branch against D-32: `pair-flow/<spec>/task-<ids>`. The spec path is `specs/<spec>/` relative to the repo root.

**c. From cwd.** If the repo root contains exactly one `specs/*/` directory whose `requirements.md` has `Status: Active`, use that.

**d. Ask the user.** List available spec directories and ask.

Verify the directory exists and contains `requirements.md`, `tasks.md`, and `test-spec.md`.

### 3. Verify spec is Active (REQ-A3.3, D-33)

Read `requirements.md` and check the `**Status:**` line. If not `Active`, halt with a clear message explaining that `/execute-task` only operates on Active specs. Suggest `/spec-kickoff` if status is `Draft`. No bypass flag exists.

### 4. Verify kickoff brief exists (D-36)

Check for `specs/<spec>/kickoff-brief.md`. If absent or if it lacks the final "Sign-off" section (partial brief), halt with a clear message prompting the user to run `/spec-kickoff`.

### 5. Read the kickoff brief slice

Read `kickoff-brief.md`. Extract:

- The signed-off goal restatement (anchors the implementation)
- The task graph section (identifies dependencies and parallelism)
- The risk register entries relevant to the current task(s)
- Any explicit assumptions or overrides recorded during walkthrough

Also read the task block(s) from `tasks.md`: `Deliverables:`, `Done when:`, `Dependencies:`, `Citations:`.

Confirm all listed Dependencies are in the `Completed` section. If any dependency is not completed, halt and surface which dependency is blocking.

### 6. Resolve repo-class

Run:

```
~/.claude/scripts/pair-flow-config.sh repo-class
```

- Exit 0 with `solo` or `multi-reviewer`: record it.
- Exit 2 with `needs-confirmation:<inferred>`: surface the inferred value and ask the user to confirm per REQ-D9.1 / D-20. On confirmation, run `~/.claude/scripts/pair-flow-config.sh confirm-repo-class <value>`. On decline, continue without writing (repo-class affects only the Agent-resolvable bucket behavior in `/polish`).

### 7. Derive the CI command (D-19)

Inspect the project to derive the full-CI command. Check in order:

| Indicator | CI command |
|---|---|
| `mix.exs` with a `ci` alias in `aliases/0` | `mix ci` |
| `mix.exs` without a `ci` alias | `mix test && mix format --check-formatted && mix credo --strict` |
| `package.json` with a `ci` or `test` script | `npm run ci` or `npm test` |
| `Makefile` with a `ci` or `test` target | `make ci` or `make test` |
| `lefthook.yml` with a `pre-commit` hook | `lefthook run pre-commit` |
| `Cargo.toml` | `cargo test && cargo clippy -- -D warnings` |
| `pyproject.toml` or `setup.py` | derive from tool config (pytest, ruff, mypy) |

If multiple indicators are present, prefer the most comprehensive one (e.g., `mix ci` over `mix test` alone). If the CI command cannot be derived, ask the user what command runs the project's full CI.

Record the derived command for use in the implementation phase.

### 8. Update tasks.md to In progress (REQ-E3.1)

Move the task block(s) from `Forward plan` to `In progress`. Add the annotation lines:

```
- **Status:** implementing
- **Last activity:** <today's date>
```

## Implementation

### Step 1: Read the test-spec entries

Read `test-spec.md` for the current task's cited REQs. These describe the verification path: what test to write, what behavior to check, what edge cases matter.

### Step 2: Test-first development (REQ-B1.3, REQ-B1.4)

For each piece of new behavior or bug fix the task introduces:

**a. Write the test.** Based on `test-spec.md` entries and the `Done when:` conditions. The test should be specific enough to fail for the intended reason and pass only when the implementation is correct.

**b. Run the test and confirm it fails.** The test must fail, and the failure message must correspond to the behavior being implemented (not a syntax error, import error, or unrelated failure). If the test passes immediately, the test is not testing what it should; revise it.

**c. Implement.** Write the implementation code to make the test pass. Consult the kickoff brief's goal restatement and risk register to stay aligned with the contract.

**d. Run the test and confirm it passes.** The same test, unchanged, now passes. If it does not, iterate on the implementation (not the test) until it does.

For tasks that are primarily configuration, documentation, or infrastructure (no testable behavior per `test-spec.md`), skip the test-first loop and proceed directly to implementation. Note in the PR body why no test was added.

### Step 3: Research when needed (REQ-B1.5, D-53)

When the implementation requires understanding external APIs, library behavior, or system constraints:

- Consult project docs and source code first.
- Use reputable external sources: official documentation, the library's own tests, deepwiki MCP for repo-specific facts, GitHub issues, RFCs.
- Weigh performance, security, and system-wide implications.
- Record findings and tradeoffs in the kickoff brief's risk register section (append, do not overwrite existing entries).

### Step 4: Run the full project CI (REQ-B1.6)

Run the CI command derived in pre-flight step 7. The full suite must pass before proceeding.

### Step 5: Handle CI failures (REQ-B1.9, D-25)

If CI fails, classify the failure:

**Transient indicators** (retry up to 2 times with exponential backoff):
- Network errors, connection timeouts, DNS failures
- Infrastructure errors (container pull failures, service unavailable)
- Known-flaky test patterns (timing-dependent tests that pass on retry)
- Exit codes indicating infrastructure issues (not test failures)

**Logic indicators** (escalate immediately, no retry):
- Assertion failures, expectation mismatches
- Type errors, compilation errors
- Lint/format violations
- Any deterministic, reproducible failure

**Unknown patterns** default to logic (safer to escalate than burn retries).

On transient retry:
- Wait 30 seconds before first retry, 90 seconds before second retry.
- If any retry succeeds, proceed normally.
- If all retries fail, reclassify as logic and escalate.

On logic failure escalation:
- Update `tasks.md`: change Status to `Awaiting input`, add a description of the failure.
- Write an inbox entry via `~/.claude/scripts/inbox-write.sh hook-event awaiting-input` if the inbox substrate is available.
- Surface the failure to the user with the full CI output and halt.

## Convergence (REQ-B1.7, D-39, REQ-B1.11)

After CI passes, invoke `/polish --nested` as the final convergence step.

Polish runs as an in-session sub-step (D-39): it has access to the same context, fires hooks normally, and returns control when done. Because `--nested` is passed, Polish does not push or create a PR.

After Polish returns:

- If Polish exited normally (success or human-attention-required): proceed to PR creation. Any Needs sign-off or Needs human judgment items from Polish are included in the PR body for the reviewer.
- If Polish hit a safety stop: surface the stop reason to the user and halt. Do not proceed to PR creation when the branch is in a known-broken state.

## PR creation (REQ-B1.8, D-21)

### 1. Push the branch

Push to the remote:

```
git push origin <branch-name>
```

If the push fails (e.g., `gh` not authenticated, remote rejected), halt and surface the error. Update `tasks.md` Status to `Awaiting input` with the reason.

### 2. Open a draft PR

Check for an existing PR on this branch via `gh pr view`. If one exists, update it rather than creating a duplicate.

If no PR exists, create one:

```
gh pr create --draft --title "<title>" --body "<body>"
```

The PR title should be concise: `feat(<scope>): <task title>` or similar conventional-commit format.

The PR body must include:

- **Kickoff brief path**: `specs/<spec>/kickoff-brief.md`
- **Task IDs**: which tasks this PR implements
- **REQs satisfied**: from the task's `Citations:`
- **Test additions**: summary of tests written and what they verify
- **Polish notes**: any Needs sign-off or Needs human judgment items the reviewer should address
- **Implementation notes**: key decisions made during implementation, especially any that extend beyond the kickoff brief's assumptions

### 3. Update tasks.md (REQ-E3.1)

Update the task's `In progress` annotation:

```
- **Status:** PR #<N> draft
- **Last activity:** <today's date>
```

## Stop conditions (mandatory human handoff)

Halt and hand control back when any condition fires. Update `tasks.md` to `Awaiting input` with the reason for each.

| Condition | Trigger |
|---|---|
| **Spec not Active** | Pre-flight step 3 found non-Active status. |
| **No kickoff brief** | Pre-flight step 4 found no brief or partial brief. |
| **Dependency not completed** | Pre-flight step 5 found an incomplete dependency. |
| **CI logic failure** | Step 5 classified a CI failure as logic after exhausting retries. |
| **Test cannot fail for the right reason** | Step 2b: the test passes immediately or fails for the wrong reason and cannot be revised to isolate the intended behavior. |
| **Contract drift** | Implementation requires changes that conflict with the kickoff brief's signed-off assumptions or constraints. Surface the drift and ask the user to update the brief or adjust the approach. |
| **Ambiguity in task definition** | The `Done when:` condition or `Deliverables:` are ambiguous enough that multiple valid interpretations exist. Surface the ambiguity and ask for clarification. |
| **Hard-disqualifier finding in Polish** | Polish surfaced a finding in security-sensitive code, migrations, or public API contracts that it cannot resolve autonomously. |
| **`gh` not authenticated** | PR creation step cannot reach the GitHub API. Local work is complete; the PR step is what's blocked. |
| **Research reveals a risk not covered by the brief** | External research surfaced a significant concern (performance, security, compatibility) not anticipated in the kickoff. Record in risk register and halt for user decision. |

## Invariants

These hold at every step:

- **Never** act on a spec whose status is not `Active` (D-33). No bypass flag exists.
- **Never** create a non-draft PR (D-21). The PR is always draft.
- **Never** merge a PR or mark it ready for review. Merge is a reserved human action.
- **Never** create a worktree. Worktree creation is `/orchestrate`'s job or the user's manual step (D-44, REQ-B1.10).
- **Never** invoke `/polish` without `--nested`. The parent skill (this skill) owns PR creation (D-39, REQ-B1.11).
- **Never** skip the test-first loop for behavior-introducing tasks. If `test-spec.md` describes a verification path for the REQ, a test must be written first.
- **Never** retry a logic CI failure. Transient retries are capped at 2. Unknown failures default to logic.
- **Never** silently proceed past a kickoff-brief contract drift. Surface it and halt.
- **Never** force-push, amend, squash, or rebase. Create new commits.
- **Never** write to `~/.claude/pair-flow.local.yml` without user confirmation (REQ-D9.1).

## Observations

`/execute-task` only runs against an Active pair-flow spec, so the repo has necessarily adopted pair-flow and `specs/` already exists; writing observations here is always appropriate (unlike `/polish`, which can run in any repo and gates this step on adoption).

During implementation and polish, when you notice complexity growth, outdated patterns, newly available dependency features, or opportunities for improvement that are outside the current task's scope, append a one-liner to `specs/_observations/opportunities.md` (create the file if it does not exist). Format: `- <YYYY-MM-DD> [<repo>] <observation>`. These accumulate as seed material for future `/spec-draft` invocations. Do not act on observations during this task; they are a passive record.

## Maintenance

After completing a task execution (or halting), check if any part of these instructions seems outdated or misaligned with the current pair-flow spec: changes to REQ-B1.x, D-19, D-21, D-25, D-33, D-39, D-44, D-53; new CI command patterns; changes to the `/polish` interface (especially `--nested` semantics). If something looks off, flag it and offer a ready-to-use prompt to update this command.

$ARGUMENTS
