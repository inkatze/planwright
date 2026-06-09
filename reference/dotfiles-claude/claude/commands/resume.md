Load context for a fresh session in a worktree with in-flight pair-flow work. Reads the kickoff brief, spec bundle `tasks.md`, recent git log on the current branch, open PR state, and (optionally) a handover brief. Produces a concise summary sufficient to continue work without re-reading the spec.

`/resume` is a **read-only context loader**, not an executor. It never edits files, runs tests, or changes git state. Its only output is a structured summary presented to the user.

Sources: REQ-E2.1, REQ-E2.2, REQ-E5.1, D-2, D-43, D-47 in `specs/pair-flow/`.

## When to use

You open a fresh Claude Code session in a worktree where pair-flow work is in flight (or was recently active) and you need to pick up where you left off. Common scenarios:

- Returning to a worktree after a break or session crash.
- Switching between multiple in-flight tasks across worktrees.
- Onboarding to a task someone else (or a scheduled runner) advanced.

`/resume` does **not** require a handover brief (REQ-E2.2). It reconstructs context from the authoritative sources (kickoff brief, `tasks.md`, git, PR). If a handover brief exists at `.claude/handover.md`, it layers on the non-obvious context found there, but its absence is never an error.

## Steps

### 1. Detect current branch and worktree context

Read the current branch name and worktree root:

```
git rev-parse --abbrev-ref HEAD
git rev-parse --show-toplevel
```

Record both for the summary output. If `HEAD` is detached, surface this to the user and ask whether to proceed (detached HEAD is unusual for pair-flow work).

### 2. Check for uncommitted changes (REQ-E5.1, D-47)

Run `git status --short`. If the output is non-empty:

- Surface the full `git status` output to the user.
- Ask whether to proceed with the context load or stop here so they can handle the uncommitted changes first.
- **Never** auto-stash, auto-commit, auto-clean, or suggest doing so on the user's behalf. The decision is theirs.
- If the user chooses to stop, exit cleanly with no further output.

If the working tree is clean, proceed silently.

### 3. Resolve the spec path

Try the following in order; stop at the first match:

**a. From `$ARGUMENTS`.** If the user passed a spec path (e.g., `/resume specs/pair-flow`), verify the directory exists and contains `tasks.md`. If it does not, halt with a clear error.

**b. From branch name.** Parse the current branch against the D-32 naming convention: `pair-flow/<spec>/task-<ids>`. If matched, the spec path is `specs/<spec>/` relative to the repo root. Verify the directory exists.

**c. From cwd heuristic.** If the cwd is inside a `specs/<name>/` directory (or the repo root contains exactly one `specs/*/tasks.md` with an `In progress` section that has entries), use that spec.

**d. Ask the user.** If none of the above resolved, list the available spec directories (`specs/*/`) and ask the user which spec this worktree is working on. If no specs exist, inform the user that `/resume` requires a spec bundle and exit cleanly.

### 4. Read context sources

Read the following sources in order. Each is optional except `tasks.md`; missing sources are noted in the summary but do not halt the skill.

**a. Kickoff brief** (`specs/<spec>/kickoff-brief.md`). If present, read it. Extract: the signed-off goal restatement, the risk register entries, any open questions recorded during walkthrough. If absent, note "no kickoff brief" in the summary (the spec may still be in Draft status).

**b. `tasks.md`** (`specs/<spec>/tasks.md`). This is the canonical state record. Read the full file. Identify:

- Tasks in `In progress` (the current work): extract their title, Status phase, Last activity date, Deliverables, and Done-when conditions.
- Tasks in `Awaiting input`: extract the blocking question.
- Tasks in `Completed`: count them and note the most recent (context for "where we are in the graph").
- Tasks in `Forward plan` whose Dependencies are all satisfied: these are the "ready next" candidates.

**c. Recent git log.** Run:

```
git log --oneline -20
```

Summarize the trajectory: what was the last thing committed, how recently, and what pattern emerges (e.g., "5 commits over 2 days implementing Task 3, last commit 3 hours ago").

**d. Open PR state.** Run:

```
gh pr view --json number,title,state,isDraft,reviewDecision,statusCheckRollup,url 2>/dev/null
```

If `gh` is not authenticated or no PR exists for the branch, note this gracefully and continue (D-43). If a PR exists, extract: PR number, title, draft status, review decision, CI status, URL.

**e. Handover brief** (`.claude/handover.md` relative to the worktree root). If present, read it and extract non-obvious context (assumptions, rejected approaches, tricky areas). If absent, skip silently (REQ-E2.2).

### 5. Produce the summary

Present a structured summary with the following sections. Keep each section concise (2-4 sentences or a short list). The goal is density, not exhaustiveness: the user should be able to read this in under 30 seconds and know exactly where they are.

```
## Context: <spec-name> / <branch>

### Current task
<Task ID and title, phase, last activity>

### What's been done
<Git log highlights: recent commits, trajectory>

### What's next
<Remaining work per the Done-when conditions of the in-flight task>

### PR status
<PR number, state, CI, review status — or "no PR yet">

### Blockers
<Awaiting-input items, open questions from kickoff brief, or "none">

### Ready after this
<Next tasks whose deps will be satisfied when the current task completes>
```

If a handover brief was found, append:

```
### Non-obvious context (from handover brief)
<Key points from the handover>
```

After the summary, end with a single line asking the user how they want to proceed: "Ready to continue. What would you like to work on?" This keeps control with the human.

## Invariants

These hold at every step:

- **Never** auto-stash, auto-commit, auto-clean, or modify the working tree in any way. `/resume` is read-only.
- **Never** require a handover brief to function. Its absence is always acceptable (REQ-E2.2).
- **Never** require `gh` authentication. PR state is a nice-to-have; its absence degrades gracefully (D-43).
- **Never** gate on spec status. `/resume` works on Draft, Active, and Done specs alike. A Done spec may still have useful context for the user.
- **Never** invoke other pair-flow skills (`/execute-task`, `/orchestrate`, `/polish`, `/spec-kickoff`). Resume loads context; execution is the user's next move.
- **Never** edit `tasks.md` or any other file. State updates are the responsibility of execution skills.

$ARGUMENTS
