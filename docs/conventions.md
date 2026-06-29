# Branch-naming & worktree-placement conventions

The operational conventions every planwright skill and hook agrees on
(REQ-K1.4; D-36, D-37, D-44). The `tasks-pr-sync` hook parses these; the
dispatch layer creates worktrees by them; `claude --worktree` discovers the
result.

## Branch naming (D-36)

Orchestrator-created task branches:

```text
planwright/<spec>/task-<id-or-ids>
```

- `<spec>` is the spec's directory name under `specs/`, matching the
  REQ-A1.8 identifier charset: `^[a-z0-9][a-z0-9-]*$`, 64 characters max.
- `<id-or-ids>` matches the task-id grammar
  `^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$`: a single task (`3`), a dotted
  task (`3.5`), or a cohesion bundle of two (`3-4`, `3.5-4`).

Examples: `planwright/bootstrap/task-6`, `planwright/checkout/task-3.5`,
`planwright/checkout/task-3-4`.

### Reserved spec-authoring namespace (D-44)

```text
planwright/<spec>/spec
```

carries spec authoring (`/spec-draft` creates it; `/spec-kickoff` pushes it
and opens the spec's draft PR). It is not a task branch: the `tasks-pr-sync`
hook no-ops on it by name.

### The `tasks-pr-sync` hook contract (REQ-K1.2)

On `gh pr create` / `gh pr merge` for a convention-named branch, the hook
moves the matching task block(s) in the spec's `tasks.md`:

| PR event | Target section | Status annotation |
| --- | --- | --- |
| `gh pr create` | `## In progress` | `- **Status:** PR #<n> draft` |
| `gh pr merge` | `## Completed` | `- **Status:** Completed · PR #<n> merged <date>` |

The block moves whole: definition content is preserved byte-for-byte, so a
hook move never changes the spec's content anchor (REQ-F1.9). Worker
sessions inside worktrees write the canonical `tasks.md` in the primary
checkout, under the spec's advisory lock; a busy lock is a clean no-op that
`/orchestrate --bookkeeping` reconciles. Both parsed segments are validated
against the grammars above and the resolved path is containment-checked
under `<repo>/specs/` before any write — a branch that fails validation
(wrong charset, `..`, extra path separators, metacharacters) is a clean
no-op and never reaches a filesystem path.

## Worktree placement (D-37)

Worktrees always land at:

```text
<repo>/.claude/worktrees/<branch-suffix>
```

where `<branch-suffix>` is the branch's final segment (`task-6`, `spec`).
The placement convention is the contract; the launch mechanism is
incidental — any worktree placed there is attachable with
`claude --worktree <name>` regardless of which backend created it.

Creation goes through Claude Code's native mechanisms (`claude --worktree`,
`EnterWorktree`, the Agent tool's worktree isolation); planwright never
shells out to `git worktree`. `.claude/worktrees/` is gitignored (working
copies, not source).

## Commit trailer (D-2, REQ-C1.4)

Every planwright-related commit carries a `Planwright-Task: <spec>/<id>`
trailer in the message footer:

```text
feat(orchestrate): unify the advisory-lock primitive

Body paragraphs as usual.

Planwright-Task: orchestration-concurrency/6
```

- `<spec>` is the spec directory name (`^[a-z0-9][a-z0-9-]*$`, ≤64); `<id>`
  is the task id (`^[0-9]+(\.[0-9]+)?$`). A commit that lands a **bundle**
  carries one trailer line per task.
- It is footer-only (never the subject line) and uses git's native trailer
  mechanism, so the orchestration-state derivation reads it with
  `git log --format='%(trailers:key=Planwright-Task)'`. As a real commit
  trailer it is the durable completion anchor that **survives branch
  deletion and a squash/rebase merge** (where branch-reachability no longer
  proves completion) and lets solo work committed straight to `main` — with
  no task branch at all — still be seen as done.

`/execute-task` stamps the trailer automatically. For **manual or solo
commits**, add it yourself — either with git's native flag:

```sh
git commit -m "fix(lock): break a stale lock at the threshold" \
  --trailer "Planwright-Task: orchestration-concurrency/6"
```

or through the shared helper, which grammar-validates each ref and emits one
trailer per task (handy for a bundle):

```sh
printf '%s\n' "$message" \
  | scripts/planwright-commit-trailers.sh orchestration-concurrency/3 \
  | git commit -F -
```

The trailer is additive: it introduces no Claude or co-author attribution, so
the project's no-attribution commit rule is unaffected.
