---
name: resume
description: >-
  Load context for a fresh session in a worktree with in-flight pair-flow
  work. Reads the kickoff brief (the contract), tasks.md state, recent git
  log, the open PR state, and an optional handover brief, then surfaces
  uncommitted changes and asks before proceeding. Read-only over your
  in-flight work: no stash, clean, push, merge, or commit of it. The skill's
  only write is the standard self-healing drift-log note.
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

This is a read-only, non-dispatching path. Outside a git repository there is
nothing to resume, so it stops with a clear message (Step 1); every other
missing prerequisite (no remote, `gh` absent, a brief that is not there yet)
degrades with a clear note and a still-useful partial load rather than a hard
halt. Both arms are graceful per REQ-K1.7: a clear message, never an opaque
failure.

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
`planwright/<spec>/task-<id-or-ids>`. Before interpolating the parsed
`<spec>` into any path, validate it against the REQ-A1.8 spec-identifier
charset (`^[a-z0-9][a-z0-9-]*$`, max 64 chars); no skill interpolates a
failing identifier into a path or command (REQ-A1.8), so a segment that
fails is treated as no match. The `<spec>` segment names the spec bundle
(`specs/<spec>/`); the `<id-or-ids>` segment names the task or bundle being
executed. If the branch does not match the convention or `<spec>` fails
validation (e.g. a spec branch `planwright/<spec>/spec`, a hostile branch
name, or an unrelated branch), do not guess a task: say which branch you are
on and try to resolve `<spec>` only when it is unambiguous — a single spec
bundle under `specs/` (a direct child whose name passes the REQ-A1.8 charset;
the reserved underscore-prefixed accumulators `_pending/` and `_observations/`
are not bundles and are skipped), or a single bundle whose `requirements.md`
carries the literal `**Status:** Active` marker and that has a kickoff brief.
Both arms consider only directory names that pass REQ-A1.8 (an Active bundle
has already passed validation, so its name conforms). If that inference is
unambiguous, continue with the resolved `<spec>`. If it is not — zero
candidates (no `specs/` directory, or no bundle directory passes REQ-A1.8) or
several candidates — say so plainly and proceed with no resolved `<spec>`
(Steps 3-4 below degrade to a spec-less partial load, a clear message rather
than an opaque failure per REQ-K1.7) rather than inventing a unit.

### 3. Load the kickoff brief (the contract)

If Step 2 resolved a `<spec>`, read `specs/<spec>/kickoff-brief.md` — the
durable contract downstream work executes against. Surface the signed-off
goal restatement, the task-graph slice for the in-flight unit, and the
risk-register entries that touch it (when unsure whether an entry is
relevant, include it rather than omit it). If the brief is absent or has no
final sign-off section, note that the work predates a signed brief (or the
brief is partial) and continue with the rest of the load; do not stop. If no
`<spec>` was resolved, note that and move on — Steps 5-8 still produce a
useful spec-less partial load.

### 4. Load tasks.md state

If a `<spec>` was resolved, read `specs/<spec>/tasks.md`. Surface the
in-flight unit's block — and when the branch encodes a cohesion bundle
(`task-<id-or-ids>`, e.g. `task-3-4`), every task block the bundle covers,
not just one — including each block's section (In progress / Awaiting input /
etc.), its `Status:` and `Last activity:` annotations, `Done when:`, and
`Dependencies:`, and note whether each dependency sits in `Completed`. This
is the canonical orchestration state record; report it as found, without
editing it. With no resolved `<spec>`, skip this step.

### 5. Load the git log

Show the recent commits on this branch (most recent first), and the
branch's relationship to its base (commits ahead / behind where that is
observable). This is what reconstructs what the prior session actually did.

### 6. Load the PR state

If a remote and the `gh` CLI are available, read the PR for this branch
(`gh pr view` on the current branch): its number, draft/ready state, title,
and review/CI status. If `gh` is absent or unauthenticated, there is no
remote, or the branch simply has no PR yet, record that no PR state is
available and proceed with a partial load: everything except the PR state is
still available (REQ-K1.6, REQ-K1.7). A branch with no PR is a normal pre-PR
state, not an error.

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
they want to proceed** before doing any further work. When a `<spec>` was
resolved, also recommend — as an **optional independent step** — that the
human may run `/spec-walkthrough specs/<spec>` themselves for an unaided,
plain-language re-read of the bundle to re-orient (REQ-F1.1, REQ-F1.2, D-11).
It is a suggestion only, never a step this skill performs, and as a read-only
loader `/resume` neither runs it nor depends on it. `/resume` ends here;
continuing the work is a separate, human-initiated step.

## Invariants

These hold at every step. The skill's one and only write is the REQ-B3.2
self-healing drift-log note (Maintenance section): recording one observation
fragment through `scripts/obs-record.sh` and committing it as its own chore
commit. That chore never touches the resumed work; every invariant below
describes the read-only guarantee over that work, and the drift-log note is
the sole carved-out exception.

- **Never** modify the working tree of the resumed work: no stash, clean,
  checkout, reset, or commit of in-flight changes. `/resume` only reads it
  (REQ-F2.1); D-30 specifically forbids auto-resolving uncommitted state.
- **Never** push, create or update a PR, or merge.
- **Never** edit `tasks.md`, the brief, or any spec bundle file. The
  observations fragment store under `specs/_observations/` is the carved-out
  drift-log exception above, not a spec file. State moves belong to
  `/orchestrate` and `/execute-task`, not to a context loader.
- **Never** hard-fail opaquely on a missing prerequisite: outside a git repo,
  stop with a clear message (Step 1); for every other missing prerequisite,
  degrade with a clear note and load what is available (REQ-K1.7).

## Maintenance

After each run, compare these instructions against the doctrine and spec
they implement: REQ-F2.1 (the read-only loader contract), D-30 (surface,
do not auto-resolve), REQ-A1.8 (the spec-identifier charset gate on `<spec>`
before path use), and the `spec-format` doc's two-brief model, brief
structure, and branch convention. If the brief structure, the handover-brief
location, the identifier charset, or the branch convention have drifted from
what this skill describes, record a one-line drift observation through the
shared helper (`scripts/obs-record.sh --slug skill-drift --scope <repo>
--text 'skill-drift(resume): <what>'` — the entry text keeps the
`skill-drift(...)` prefix) and commit the fragment as its own chore commit,
per REQ-B3.2 / D-42; surface a non-zero helper exit rather than silently
dropping the observation. In repositories without `specs/`, surface the
drift to the user instead of recording it. Do not edit this skill or the
doctrine docs to resolve the drift; the accumulator's canonical reader
(`/spec-draft`) owns folding drift into spec amendments.
