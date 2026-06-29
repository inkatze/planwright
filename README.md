# planwright

[![CI](https://github.com/inkatze/planwright/actions/workflows/ci.yml/badge.svg)](https://github.com/inkatze/planwright/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://claude.com/plugins)

planwright is an opinionated Claude Code framework for **spec-driven
development**: you specify a feature precisely, sign it off, and the framework
builds it — advancing tasks, opening draft pull requests, and converging review
on its own — while you keep the two controls that matter: **sign-off** and
**merge**.

Think autopilot, not a replacement crew. How well it flies is bounded by how
good your spec is, so planwright's whole investment is getting the spec right
before any code is written. Under the hood it is **loop engineering with
guardrails**: the agent runs in autonomous review-and-execute loops (bounded by
iteration caps, convergence criteria, and no-progress detection), and every
irreversible action stops at a human checkpoint.

> **Status: v1, self-hosting.** The founding spec (`specs/bootstrap/`) that
> defines planwright v1 is complete, and planwright now develops itself through
> the same pipeline it ships. It is young software — expect rough edges, and
> please report what you find.

**New here?** The [getting-started guide](docs/getting-started.md) takes you
from a clean machine to running the pipeline end to end.

## Why planwright

- **Specs before code.** Every feature is four files — requirements, design,
  tasks, tests — reviewed and signed off before a line is written. The spec is
  the contract the agent executes against, not an afterthought.
- **You keep the controls.** Two actions are human-reserved, permanently:
  **sign-off** (no spec runs until you have walked it and signed the brief) and
  **merge** (every PR is a draft; planwright never auto-merges). Everything in
  between is one revert from undone.
- **Guardrailed autonomy.** Review and execution run in bounded loops —
  iteration caps, convergence criteria, no-progress detection — with hard pauses
  at security-sensitive or irreversible steps.
- **Adapts to your project.** Supply your own linters, test commands, and review
  rigor through layered overlays, without editing planwright's core.
- **Claude Code only.** Built entirely on Claude Code primitives (skills, hooks,
  subagents, file-based state) — there is no second agent framework to install.

## Requirements

- **Claude Code** — a recent version with the plugin and skill system.
- **git**, and a **GitHub repository** with the
  [**`gh`** CLI](https://cli.github.com/) authenticated — planwright opens draft
  PRs through `gh`. Without GitHub/`gh` the pipeline degrades gracefully, but the
  pull-request flow is unavailable; see
  [the GitHub requirement](docs/getting-started.md#2-the-github-requirement-and-what-happens-without-it).

## Install

planwright installs through Claude Code's standard marketplace flow:

```text
/plugin marketplace add inkatze/planwright
/plugin install planwright@planwright
```

For environments without plugin support there is a no-plugin **`~/.claude/`
writer** (`scripts/install.sh`, portable shell only). Both modes, and the
upgrade path, are covered in [Install](docs/getting-started.md#1-install).

## Quickstart

Once installed, you drive five steps; planwright does the work between your two
controls:

```text
   /spec-draft  →  /spec-kickoff  →  /orchestrate  →  /execute-task  →  review & merge
                        ▲                                                      ▲
                    sign-off                                                 merge
                  (gate 1: no spec                                    (gate 2: planwright
                   runs unsigned)                                      never auto-merges)

   └──── you author ────┘   └──── planwright runs the middle ────┘   └─── you decide ───┘
```

1. **`/spec-draft <feature>`** — interactively elicit the four-file spec bundle
   (Status `Draft`).
2. **`/spec-kickoff <spec-path>`** — walk the spec section by section to mutual
   understanding and sign the kickoff brief. Sign-off flips the spec to
   `Active`. *(your first control)*
3. **`/orchestrate <spec-path>`** — pick the next ready task, create its
   worktree, and dispatch execution. Stateless: one step per call, so you can
   run it in several sessions for parallelism.
4. **`/execute-task <ids>`** — test-first implementation, full CI with adaptive
   retry, convergence via `/polish`, then a **draft PR**.
5. **Review and merge.** *(your second control)*

The [getting-started guide](docs/getting-started.md) walks each step in depth.

## How it works

### The two controls

planwright is an autopilot, not a replacement crew. Two controls are
human-reserved, permanently:

- **Sign-off** — a spec executes only after you walk it at kickoff and sign the
  resulting brief. There is no bypass flag.
- **Merge** — every PR the framework creates is a draft; your draft→ready flip is
  the universal review gate, and merge is always your action.

Between them, the intervention contract has three phases: sign-off before
execution, rare hard pauses during it (security-sensitive zones, destructive
operations, irreducible judgment forks), and review plus merge after. Invariants
the framework holds everywhere: never auto-merge; never act on a non-Active spec;
never force-push, amend, squash, or rebase (new commits only).

### The four-file spec

Every feature lives in `specs/<feature>/` as four files:

- `requirements.md` — what must be true (REQ-IDs), with a `Status:` that moves
  `Draft` → `Active` → `Done`.
- `design.md` — the decisions and the alternatives weighed (D-IDs).
- `tasks.md` — the work as stable-ID tasks with `Done when:` / `Dependencies:`;
  it doubles as the orchestration ledger.
- `test-spec.md` — each requirement pinned to how it is verified.

The format is specified in full in
[the spec-format doctrine](doctrine/spec-format.md).

## Commands

planwright ships ten skills; each is a slash command in Claude Code.

| Stage | Command | What it does |
| --- | --- | --- |
| **Author** | `/spec-draft` | Interactively elicit a four-file spec bundle (Status Draft). |
| | `/spec-kickoff` | Walk a spec to sign-off and flip it Active. *(your first control)* |
| | `/spec-walkthrough` | Render a spec into a plain-language artifact for an unaided cold read. |
| **Execute** | `/orchestrate` | Pick the next ready task, create its worktree, dispatch execution. |
| | `/execute-task` | Test-first build of one task → full CI → draft PR. |
| | `/resume` | Load context for a fresh session in an in-flight worktree. |
| **Converge** | `/self-review` | Discovery + validation review of the branch; opens or updates a draft PR. |
| | `/polish` | Autonomous review loop that drains every fixable finding, locally. |
| **Maintain** | `/drain` | Evaluate deferred gate conditions across spec bundles. |
| | `/builder` | Detect the project's stack and recommend or apply the quality-guard catalog. |

## Customize without forking

planwright adapts to your project through **overlays** — layered config,
doctrine, and catalog files that override the core defaults without editing
planwright itself. Supply your own linters, test commands, and review rigor in a
gitignored machine-local layer or a repo-tracked layer, and the framework merges
them over its core. Defaults live in
[`config/defaults.yml`](config/defaults.yml) and every option is documented in
the [options reference](docs/options-reference.md) (an undocumented option fails
CI). See [Customizing with overlays](docs/overlays.md) for the full model.

## Documentation

- [Getting started](docs/getting-started.md) — install, the GitHub requirement,
  operating the pipeline, and supplying your own tooling.
- [Customizing with overlays](docs/overlays.md) — the four-layer model and
  per-kind merge rules.
- [Conventions](docs/conventions.md) — branch, worktree, and repo conventions.
- [Orchestration state](docs/orchestration-state.md) — the derived-projection
  model: how progress is derived from git/GitHub evidence, the single-writer
  reconcile, and the no-remote flow.
- [Options reference](docs/options-reference.md) — every configuration option.
- [Doctrine](doctrine/README.md) — the framework's rule docs: validation and
  discovery rigor, finding categorization, engineering decisions, security
  posture, and more.
- [Contributing](docs/CONTRIBUTING.md) ·
  [Release checklist](docs/release-checklist.md)

## Project layout

```text
.claude-plugin/   plugin + marketplace manifests (the install path)
skills/           the ten planwright skills (one directory each)
doctrine/         the framework rule docs
scripts/          portable-shell entry points (installer, resolver, checks)
config/           tracked default config
docs/             guides (getting-started, overlays, conventions, options)
specs/            planwright's own specs (bootstrap = the founding spec)
tests/            shell tests for the scripts
```

## Development

planwright pins its toolchain with [mise](https://mise.jdx.dev): run
`mise install` once, then `mise run check` runs the full gate — shell tests,
shellcheck, shfmt, markdownlint, yamllint, conventional-commit lint, manifest +
link + options-reference checks, the ledger structural-corruption +
duplicate-Status guard, the spec validator, and a gitleaks scan. It is the
same gate CI runs on every pull request. This is dev tooling only;
planwright's runtime scripts stay plain portable bash. See
[Contributing](docs/CONTRIBUTING.md) for the workflow.

## License

[MIT](LICENSE).
