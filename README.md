# planwright

An autopilot for spec-driven development, built as an opinionated Claude Code
framework.

planwright pairs a human and an agent from comprehension through execution.
The human is **pilot-in-command**: they must still know how to operate the
machine, and they keep the reserved controls. Once a spec is signed off, the
framework flies it: advancing tasks, opening draft pull requests, and
converging review without further human keystrokes. How accurately the system
flies is bounded by how good the spec is, so planwright's primary investment
is making specs as correct as possible before any code is written.

In current terms, planwright is **loop engineering with guardrails**: it runs
the agent in autonomous review-and-execute loops (bounded by iteration caps,
convergence criteria, and no-progress detection), while every irreversible
action stays a **human-in-the-loop** checkpoint. The two checkpoints,
**sign-off** and **merge**, are described below under
[The pilot-in-command model](#the-pilot-in-command-model).

> **Status: v1, self-hosting.** The founding spec (`specs/bootstrap/`) that
> defines planwright v1 is complete, and planwright now develops itself through
> the same pipeline it ships. It is young software — expect rough edges.

**New here?** [docs/getting-started.md](docs/getting-started.md) walks a
non-author from a clean machine through installing planwright, confirming
rule-doc resolution, operating the pilot-in-command model, and supplying your
own tooling and rigor without editing core.

## Install

planwright installs through Claude Code's standard marketplace flow:

```text
/plugin marketplace add inkatze/planwright
/plugin install planwright@planwright
```

That is the whole quick start. For the `~/.claude/` writer fallback (no plugin
support required) and the full walkthrough, see
[docs/getting-started.md](docs/getting-started.md) and
[Delivery modes](#delivery-modes) below.

## The pilot-in-command model

planwright is an autopilot, not a replacement crew. Two controls are
human-reserved, permanently:

- **Sign-off.** A spec executes only after the human walks it section by
  section at kickoff and signs the resulting brief. No sign-off, no
  execution; there is no bypass flag.
- **Merge.** Every PR the framework creates is a draft. The human's
  draft→ready flip is the universal review gate, and merge is always a human
  action. planwright never auto-merges, at any tier.

Between those two controls the intervention contract has three phases:
sign-off before execution, rare hard pauses during it (security-sensitive
zones, destructive operations, irreducible judgment forks), and PR review
plus merge after it. Everything the agent applied on a branch is one revert
from undone until the human merges.

Invariants the framework holds everywhere: never auto-merge; never act on a
non-Active spec; never force-push, amend, squash, or rebase (new commits
only); all framework-created PRs are drafts.

## The four-file spec and the pipeline

Every feature is specified before it is built, as four files under
`specs/<feature>/`:

- `requirements.md` — what must be true (REQ-IDs), carrying a `Status:` that
  moves `Draft` → `Active` → `Done`.
- `design.md` — the decisions and the alternatives weighed (D-IDs).
- `tasks.md` — the work as stable-ID tasks with `Done when:` /
  `Dependencies:`; it doubles as the orchestration ledger.
- `test-spec.md` — each requirement pinned to how it is verified.

You drive five steps; planwright does the work between your two controls:

1. **`/spec-draft <feature>`** — elicit the four-file bundle at Status `Draft`.
2. **`/spec-kickoff <spec-path>`** — walk it to mutual understanding and sign
   the kickoff brief, which flips the spec to `Active`. *(your first control)*
3. **`/orchestrate <spec-path>`** — pick the next ready task, create or reuse
   its worktree, and dispatch execution. Stateless: one step per invocation,
   run it in several sessions for parallelism.
4. **`/execute-task <ids>`** — test-first implementation, full CI with adaptive
   retry, convergence via `/polish`, then a **draft PR**.
5. **Review and merge.** *(your second control)*

[docs/getting-started.md](docs/getting-started.md) covers each step in depth.

## Delivery modes

planwright ships two ways (the plugin is primary):

1. **Claude Code plugin.** The repo root is the plugin: the manifest lives at
   `.claude-plugin/plugin.json`, and skills, hooks, and doctrine docs resolve
   plugin-relative at runtime.
2. **`~/.claude/` writer (fallback).** `scripts/install.sh` copies the same
   content into namespaced paths under your Claude config dir
   (`~/.claude/planwright/`, plus skills and commands when present). It
   depends only on portable shell: no fish, mise, tmux, Ansible, or symlink
   materialization. It never edits `settings.json` or any file outside its
   namespace. To upgrade cleanly, delete `~/.claude/planwright/` first, then
   re-run the writer (a re-install refresh-copies but never deletes); see
   [docs/getting-started.md](docs/getting-started.md) for the full install and
   upgrade walkthrough.

### Rule-doc resolution

Skills reference externalized rule docs (the rigor doctrine, finding
categorization, engineering doctrine) through one stable path that works in
both delivery modes:

```text
${PLANWRIGHT_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_DIR:-$HOME/.claude}/planwright}}/doctrine/<doc>.md
```

`scripts/resolve-rule-doc.sh <doc-name>` implements the chain. The writer
arm requires `CLAUDE_DIR` or `HOME` to be set; in environments with neither
(minimal containers), resolution uses the first two arms only. See
[`doctrine/README.md`](doctrine/README.md) for the convention's details.

## Configuration

Universal defaults are tracked in [`config/defaults.yml`](config/defaults.yml).
Per-repo and personal overrides live in `<repo>/.claude/planwright.local.yml`
(gitignored, agent-maintained; per-repo entries are written only on human
confirmation). Every option is documented in the canonical
[options reference](docs/options-reference.md); an option missing from the
reference fails planwright's own CI.

## Repository layout

```text
.claude-plugin/plugin.json   plugin manifest
.claude-plugin/marketplace.json  marketplace manifest (the GitHub install path)
config/defaults.yml          tracked default config
doctrine/                    externalized rule docs (the framework doctrine)
docs/options-reference.md    canonical config options reference
skills/                      planwright skills (one directory per skill)
scripts/                     portable-shell entry points (writer, resolver, checks)
tests/                       shell tests for the scripts
specs/                       planwright's own specs (bootstrap = the founding spec)
```

## Development

The repo pins its quality toolchain with [mise](https://mise.jdx.dev)
(`mise.toml`): `mise install` once, then `mise run check` runs everything
(shell tests, shellcheck, shfmt, markdownlint, yamllint, manifest validation,
the doctrine link-check, conventional-commit lint, the options-reference drift
check, the spec validator (`scripts/spec-validate.sh` over `specs/`,
REQ-A2.1), and a gitleaks history scan). This is dev-tooling
only: planwright's runtime scripts stay plain portable bash with no mise
dependency (REQ-K1.5). GitHub Actions (`.github/workflows/ci.yml`) runs the
same `mise run check` gate on every pull request.

## License

[MIT](LICENSE). See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the
contribution model and [docs/release-checklist.md](docs/release-checklist.md)
for the public-release readiness gate.
