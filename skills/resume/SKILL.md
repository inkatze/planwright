---
name: resume
description: >-
  Load context for a fresh session in a worktree with in-flight pair-flow
  work. Reads the kickoff brief (the contract), tasks.md state, recent git
  log, the open PR state, and an optional handover brief, then surfaces
  uncommitted changes and asks before proceeding. Read-only: it never
  stashes, commits, cleans, pushes, or merges.
---

# /resume — read-only context loader

`/resume` rehydrates a session that lands in an in-flight worktree with no
memory of how the work got there (REQ-F2.1, D-30). It gathers the durable
context a worker needs — the kickoff brief, `tasks.md` state, the branch's
git log, the PR state, and an optional handover brief — surfaces the
working tree's uncommitted state, and asks before any work continues.

It is strictly read-only. It surfaces information and defers every decision
to the human: it never auto-stashes, auto-commits, or auto-cleans (D-30),
and as a read-only loader it never pushes or merges (REQ-F2.1). The point is
to make the situation legible, not to act on it.

This is a read-only, non-dispatching path: missing prerequisites (not a git
repo, no remote, `gh` absent, a brief that is not there yet) degrade with a
clear note and a still-useful partial load, never a hard halt (REQ-K1.7).

## Doctrine

This skill is procedure, not doctrine. One rule doc informs it; resolve it
at run start via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright
root, or the documented `PLANWRIGHT_ROOT` / `CLAUDE_PLUGIN_ROOT` chain):

- `spec-format` — the two-brief model (kickoff = durable contract, handover
  = optional in-worktree cache), the kickoff-brief structure, and the
  `planwright/<spec>/task-<id-or-ids>` branch convention this skill parses
  to locate the spec.

Because `/resume` is a read-only loader, a doc that does not resolve is a
one-line degradation note, not a halt: fall back to reading the brief and
`tasks.md` directly and proceed (REQ-K1.7).

## Procedure

### 1. Establish location and prerequisites

Confirm the current directory is inside a git repository and resolve its
top level. If it is not a git repo, say so plainly and stop — there is no
in-flight worktree to resume. Note (do not fail on) the absence of a remote
or of the `gh` CLI; those only narrow the PR-state step below.

### 2. Identify the in-flight unit

Read the current branch name and parse it against the convention
`planwright/<spec>/task-<id-or-ids>`. The `<spec>` segment names the spec
bundle (`specs/<spec>/`); the `<id-or-ids>` segment names the task or
bundle being executed. If the branch does not match the convention (e.g. a
spec branch `planwright/<spec>/spec`, or an unrelated branch), say which
branch you are on and load what you can from the repository's `specs/`
without assuming a task; do not invent a unit.

### 3. Load the kickoff brief (the contract)

Read `specs/<spec>/kickoff-brief.md` — the durable contract downstream work
executes against. Surface the signed-off goal restatement, the task-graph
slice for the in-flight unit, and the risk-register entries that touch it
(when unsure whether an entry is relevant, include it rather than omit it).
If the brief is absent or has no final sign-off section, note that the work
predates a signed brief (or the brief is partial) and continue with the
rest of the load; do not stop.

### 4. Load tasks.md state

Read `specs/<spec>/tasks.md`. Surface the in-flight unit's block (its
section — In progress / Awaiting input / etc., its `Status:` and
`Last activity:` annotations, `Done when:`, and `Dependencies:`), and note
whether each dependency sits in `Completed`. This is the canonical
orchestration state record; report it as found, without editing it.

### 5. Load the git log

Show the recent commits on this branch (most recent first), and the
branch's relationship to its base (commits ahead / behind where that is
observable). This is what reconstructs what the prior session actually did.

### 6. Load the PR state

If a remote and the `gh` CLI are available, read the PR for this branch
(`gh pr view` on the current branch): its number, draft/ready state, title,
and review/CI status. If `gh` is absent or unauthenticated, or there is no
remote, record that the PR state could not be read and proceed — local
context is still complete (REQ-K1.6, REQ-K1.7).

### 7. Load the optional handover brief

If `<worktree>/.claude/handover.md` exists, read it and fold its in-flight
notes into the summary. It is an optional best-effort cache (D-3), not a
contract: its absence is normal and never an error.

### 8. Surface the working tree and ask before proceeding

Run `git status` and surface the working tree exactly as it is: staged,
unstaged, and untracked changes. Do not stash, commit, clean, or otherwise
touch the working tree — the decision about uncommitted state belongs to
the human (D-30).

Then present the consolidated context (unit, brief slice, task state, git
log, PR state, handover notes, working-tree status) and **ask the human how
they want to proceed** before doing any further work. `/resume` ends here;
continuing the work is a separate, human-initiated step.

## Invariants

These hold at every step:

- **Never** modify the working tree: no stash, commit, clean, checkout, or
  reset. `/resume` only reads (REQ-F2.1); D-30 specifically forbids
  auto-resolving uncommitted state.
- **Never** push, create or update a PR, or merge. `/resume` only reads.
- **Never** edit `tasks.md`, the brief, or any spec file. State moves belong
  to `/orchestrate` and `/execute-task`, not to a context loader.
- **Never** hard-fail on a missing prerequisite. Degrade with a clear note
  and load what is available (REQ-K1.7); this is a read-only path.

## Maintenance

After each run, compare these instructions against the doctrine and spec
they implement: REQ-F2.1 (the read-only loader contract), D-30 (surface,
do not auto-resolve), and the `spec-format` doc's two-brief model, brief
structure, and branch convention. If the brief structure, the handover-brief
location, or the branch convention have drifted from what this skill
describes, append a one-line drift observation to
`specs/_observations/opportunities.md` in the standard format
(`- <YYYY-MM-DD> [<repo>] skill-drift(resume): <what>`) and commit the
append as its own chore commit, per REQ-B3.2 / D-42. In repositories
without `specs/`, surface the drift to the user instead of writing the log.
Do not edit this skill or the doctrine docs to resolve the drift; the
observation log's reader owns folding drift into spec amendments.
</content>
