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

### The `tasks-pr-sync` hook contract (REQ-K1.2, REQ-B1.1)

On `gh pr create` / `gh pr merge` for a convention-named branch, the hook
triggers a **level-triggered reconcile** of that spec's `tasks.md`: it is the
**sole writer of section placement** and recomputes the placement of every task
block from the derivation engine (`scripts/orchestrate-state.sh`), not just the
one task named by the PR event. Each `### Task <id>` block is relocated by its
derived state:

| Derived state | Target section |
| --- | --- |
| `completed` (merged PR, merge-reachable branch, or a `Planwright-Task` trailer) | `## Completed` |
| `in-progress` (open PR, unmerged branch with commits, or a fresh dispatch marker) | `## In progress` |
| `ready` / `blocked` (by dependency state) | `## Forward plan` |

The human-owned sections (`## Awaiting input`, `## Deferred`, `## Out of scope`)
are **sticky**: their bodies are preserved without data loss and their blocks are
never relocated by the derivation. "Without data loss" is not byte-for-byte:
blank-line whitespace is normalized to the canonical form (leading/trailing
blanks trimmed, blank runs collapsed) so the snapshot stays idempotent; the
content lines themselves are kept intact. The reconcile writes **placement
only** — the
per-block `Status` / `Last activity` annotations ride along untouched (those are
`/execute-task`'s to write, and are excluded from the content anchor), so a
reconcile never changes the spec's content anchor (REQ-F1.9). It is
**idempotent**: a second run against unchanged truth is a byte-identical no-op,
and a scrambled, flattened, or conflict-marked snapshot reconciles to the same
canonical placement (a git-conflicted `tasks.md` is regenerated from the
derivation, never resolved by `ours`/`theirs`/`union`). The rewrite is atomic
(a same-directory temp renamed into place).

**Format-version scope.** The reconcile above is the **format-version 1**
contract. On a **format-version 2** bundle the hook is version-keyed: it detects
`Format-version: 2` and **no-ops** — it writes no placement, no annotation, and
no completion stamp, because a v2 bundle commits no derived execution state at
all (there are no placement sections to relocate a block into). Execution status
for a v2 bundle is read through the on-demand status render backed by the same
derivation engine, never a committed snapshot; see the
[derived-projection model](orchestration-state.md#format-version-2-no-committed-snapshot)
and the normative v2 shape in
[`doctrine/spec-format.md`](../doctrine/spec-format.md). A missing or unparseable
`Format-version:` fails closed (no write). v1 bundles keep the reconcile behavior
described above.

The same script also exposes a direct form, `tasks-pr-sync.sh reconcile
<spec-dir>`, that `/orchestrate --bookkeeping` and the tests drive. Worker
sessions inside worktrees reconcile the canonical `tasks.md` in the primary
checkout, under the spec's advisory lock (the one shared
`scripts/orchestrate-lock.sh` primitive); a busy lock is a clean no-op that
`/orchestrate --bookkeeping` reconciles. The parsed `<spec>` / `<id>` segments
are validated against the grammars above and the resolved path is
containment-checked under `<repo>/specs/` before any write — a branch that fails
validation (wrong charset, `..`, extra path separators, metacharacters) is a
clean no-op and never reaches a filesystem path.

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
- Stamp it in the message footer (never the subject line), the same position
  as `Signed-off-by:`; `/execute-task` emits it there automatically. The
  orchestration-state derivation does **not** depend on footer position when
  *reading*, though: it scans the whole commit message for `Planwright-Task:`
  lines, so a trailer that a squash or rebase merge relocates mid-body is still
  recognized (git's own `%(trailers)` parser reads only the last paragraph and
  would miss it). As a completion anchor it covers the cases branch-reachability
  can no longer prove done: it **survives branch deletion**, and it lets solo
  work committed straight to `main` — with no task branch at all — still be
  seen as done. (See the risk-R2 caveat with
  [the derived-state model](orchestration-state.md#the-squash--rebase-merge-caveat-risk-r2)
  for how this interacts with squash/rebase merges and the `gh` head-ref
  mapping.)

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

## Instruction-authoring hygiene (prompt-hygiene D-10)

The skills and doctrine docs here are runtime artifacts, so they carry an
authoring convention of their own: flow lives in skills, law lives in rule
docs referenced one level deep, each skill declares a doctrine manifest
(run-start vs point-of-use), and every file stays within a measured word
budget. The full law is [instruction-hygiene.md](../doctrine/instruction-hygiene.md);
the size guard that enforces it is
[`scripts/check-instructions.sh`](../scripts/check-instructions.sh), wired into
`mise run check` (with `--closeout` so no transitional `pending-diet` allowance
lingers past a diet). The builder recommends this dimension to adopters through
the `instruction-hygiene` [guard-catalog entry](../doctrine/guard-catalog.md#instruction-hygiene).
