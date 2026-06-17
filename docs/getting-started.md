# Getting started with planwright

This guide takes a non-author from a clean machine to operating planwright's
**pilot-in-command** model: install it, confirm it resolves its own rule docs,
understand the controls you keep, and supply your project's own tooling and
rigor without editing planwright's core.

If you read only one thing: planwright is an **autopilot**, not a replacement
crew. It flies a spec once you have signed it off, and it stops at the controls
that are yours — **sign-off** and **merge**. How well it flies is bounded by
how good the spec is.

## 1. Install

planwright ships two ways. The plugin is primary; the writer is the fallback
for environments without plugin support.

### Option A — Claude Code plugin (primary)

The repository root *is* the plugin: the manifest is at
[`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json), and skills,
hooks, and doctrine docs resolve plugin-relative at runtime. The repo also
ships a marketplace manifest
([`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json)) so it
installs through Claude Code's standard marketplace flow — add the repo as a
marketplace, then install the plugin (`<plugin>@<marketplace>`, both named
`planwright`):

```text
/plugin marketplace add inkatze/planwright
/plugin install planwright@planwright
```

For local development against a checkout, launch with the plugin directory
flag instead:

```bash
claude --plugin-dir /path/to/planwright
```

Validate a manifest you are hacking on with `claude plugin validate
/path/to/planwright` (add `--strict` to treat unknown fields as errors).

### Option B — `~/.claude/` writer (fallback)

[`scripts/install.sh`](../scripts/install.sh) copies the same content into
namespaced paths under your Claude config dir. It depends only on portable
shell — **no fish, mise, tmux, Ansible, or symlink materialization** — and it
never edits `settings.json` or anything outside its namespace.

```bash
scripts/install.sh            # installs into ~/.claude/planwright/
CLAUDE_DIR=/custom scripts/install.sh   # override the destination
```

It writes rule docs to `~/.claude/planwright/doctrine/`, scripts and config
alongside, and any shipped skills/commands into `~/.claude/skills/` and
`~/.claude/commands/`. Hook wiring needs a `settings.json` merge and is
**printed as a manual step** rather than performed (the writer never edits
files it does not own); the plugin install gets hooks automatically via
`hooks/hooks.json`.

### Confirm rule-doc resolution

Both delivery modes resolve externalized rule docs through one stable path:

```text
${PLANWRIGHT_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_DIR:-$HOME/.claude}/planwright}}/doctrine/<doc>.md
```

Confirm it works after install:

```bash
scripts/resolve-rule-doc.sh validation-rigor   # prints the resolved doc path
```

A plugin install resolves via `CLAUDE_PLUGIN_ROOT`; the writer resolves via
`CLAUDE_DIR`/`HOME`. See [`doctrine/README.md`](../doctrine/README.md) for the
convention's details.

### Upgrading and cleaning up

- **Plugin:** upgrade through the marketplace; Claude Code manages versions.
- **Writer:** re-running `scripts/install.sh` refresh-copies but never deletes,
  so files removed or renamed in a newer planwright would linger. To upgrade
  cleanly, **delete `~/.claude/planwright/` first, then re-run the writer**
  (a clean reinstall). The writer's namespaced layout makes this safe: only
  the `planwright/` namespace is removed, and shipped skills/commands are
  re-copied by the next run.

## 2. The GitHub requirement, and what happens without it

v1 targets **GitHub through the `gh` CLI** for pull-request operations (D-35,
REQ-K1.6). Other git hosts (GitLab, Bitbucket) are out of v1 scope.

planwright **degrades gracefully** when GitHub is not reachable (REQ-K1.6,
REQ-K1.7) — it never fails opaquely:

- **No `gh`, or `gh` not authenticated:** all local work proceeds (specs,
  worktrees, commits, tests, the convergence loop). The push/PR step records an
  *Awaiting input* note naming the pending step, surfaces it, and stops.
- **No git remote at all:** the same — local work completes; the remote-bound
  steps degrade with a clear message.
- **Not a git repository / missing validator on a non-dispatch path:** a clear
  message rather than a crash.

So you can run the comprehension and execution phases offline; only the
PR-creation tail needs `gh`. Authenticate with `gh auth login` when you are
ready to push and open draft PRs.

## 3. Operating the pilot-in-command model

You keep two controls, permanently. Everything between them the framework
handles once a spec is signed off.

- **Sign-off (before execution).** A spec executes only after you walk it
  section by section at kickoff and sign the resulting brief. No sign-off, no
  execution — there is no bypass flag.
- **Merge (after execution).** Every PR the framework opens is a **draft**.
  Your draft→ready flip is the universal review gate, and merge is always
  yours. planwright never auto-merges, at any tier.

Between those, the intervention contract has three phases: **sign-off before**
execution, **rare hard pauses during** it (security-sensitive zones,
destructive operations, irreducible judgment forks), and **PR review plus
merge after**. Everything the agent applied on a branch is one revert from
undone until you merge.

### The pipeline, end to end

You drive these in order; planwright does the work between your two controls:

1. **`/spec-draft <feature>`** — elicit the four-file spec bundle
   (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) at Status
   `Draft`. Never commits a flip to Active.
2. **`/spec-kickoff <spec>`** — walk the spec to mutual understanding,
   producing the signed-off **kickoff brief** (the durable contract every
   downstream skill executes from). On your sign-off it flips Draft → Active.
   *This is your first control.*
3. **`/orchestrate <spec>`** — pick the next ready task, create or reuse its
   worktree, and dispatch execution. Stateless: one step per invocation; run it
   in several sessions for intra-spec parallelism. Never merges, never marks a
   PR ready.
4. **`/execute-task <ids>`** — the execution workhorse: test-first, full CI with
   adaptive retry, convergence via `/polish`, then a **draft PR** referencing
   the brief, task IDs, REQs, tests, and the pending-sign-off checklist.
5. **Review and merge** — review the draft PR, flip it to ready, and merge.
   *This is your second control.*

`/resume` reloads context for a fresh session in an in-flight worktree, and
`/drain` evaluates deferred gate conditions across specs. Both are read-only.

### Invariants the framework holds everywhere

Never auto-merge; never act on a non-Active spec; never force-push, amend,
squash, or rebase (new commits only); all framework-created PRs are drafts.
These are constraints, not future capabilities.

## 4. Supplying your own tooling and rigor (without editing core)

planwright core ships **general** doctrine and skills. Your project carries its
own preferences — a review-gauntlet ordering, a dispatch-isolation default,
project-specific decision-domain entries, extra linters or rigor — and you must
be able to add them **without editing planwright's core rule docs** (REQ-D2.2 /
REQ-I1.4). Editing core would make it less general for everyone and pollute the
observation stream meant to merge upstream.

Two layers exist today, and a third (the general overlay mechanism) is on the
way:

- **Config overrides (available now).** Universal defaults live in
  [`config/defaults.yml`](../config/defaults.yml). Per-repo and personal
  overrides go in `<repo>/.claude/planwright.local.yml` (gitignored,
  agent-maintained; per-repo entries are written only on your confirmation).
  Every option is documented in the
  [options reference](options-reference.md); an undocumented option fails
  planwright's own CI. This covers thresholds and commit/dispatch toggles.
- **Project tooling discovery (available now).** planwright's SessionStart hook
  detects your project's linters, formatters, and type-checkers and feeds them
  into Discovery Rigor and the builder, so your stack's tools ground reviews
  without any core edit.

> **Forward reference (not yet shipped).** The general seam for layering
> *doctrine and catalog* preferences — a fixed four-layer precedence model
> (`core defaults < adopter overlay < repo-tracked overlay < machine-local
> overlay`), defined overlay locations, and a per-kind merge contract skills
> read through — is specified in
> [`specs/customization-overlay/`](../specs/customization-overlay/requirements.md)
> and is **Active but not yet built** as of this writing. Until it lands, layer
> *doctrine/catalog* preferences through your project's own conventions and the
> config overrides above; this section will be revised to describe the shipped
> overlay mechanism once it ships. Do not edit planwright's core `doctrine/`
> docs to encode project- or team-specific style.

## 5. Where to go next

- [`README.md`](../README.md) — the one-screen overview and repository layout.
- [`doctrine/`](../doctrine/) — the rule docs skills cite (rigor, finding
  categorization, engineering doctrine, spec format).
- [`docs/conventions.md`](conventions.md) — repository and workflow
  conventions.
- [`docs/CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute changes.
- [`docs/release-checklist.md`](release-checklist.md) — the public-release
  readiness gate (for maintainers).
