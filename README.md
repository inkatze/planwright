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

> **Status: bootstrapping.** planwright is building itself through its own
> founding spec (`specs/bootstrap/`). The skills and doctrine docs land task
> by task; this scaffold is the packaging skeleton they land on.

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
   namespace.

### Rule-doc resolution

Skills reference externalized rule docs (the rigor doctrine, finding
categorization, engineering doctrine) through one stable path that works in
both delivery modes:

```text
${PLANWRIGHT_ROOT:-${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/planwright}}/doctrine/<doc>.md
```

`scripts/resolve-rule-doc.sh <doc-name>` implements the chain. See
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
config/defaults.yml          tracked default config
doctrine/                    externalized rule docs (the framework doctrine)
docs/options-reference.md    canonical config options reference
scripts/                     portable-shell entry points (writer, resolver, checks)
tests/                       shell tests for the scripts
specs/                       planwright's own specs (bootstrap = the founding spec)
reference/                   transient migration source material (purged before any public release)
```

## License

[MIT](LICENSE). Contribution model lands with the packaging task.
