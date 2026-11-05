# planwright

[![CI](https://github.com/inkatze/planwright/actions/workflows/ci.yml/badge.svg)](https://github.com/inkatze/planwright/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://claude.com/plugins)

**Come back to a few draft pull requests that were already tested and
reviewed. You still merge.**

planwright is a Claude Code plugin. Type **`/tower`** in your repository and
say what you want in your own words. Questions get an answer in the
conversation. A change goes to an isolated agent that builds it, tests it,
reviews its own work until the review stops finding problems it can fix, and
opens a **draft pull request** (once you let it push to your GitHub account;
until then the work stays on your machine). Work built from a spec is marked
ready for you only once CI is green on it, and by default nothing merges until
you do.

**Placeholder, not yet measured:** on a public demo repository and a fixed
set of tasks, *[N]%* of planwright's draft pull requests merged with no
further change, at *[M]* reviewer minutes per merged pull request, against
plain Claude Code on the same tasks.

> **Status: young and solo-maintained.** One person maintains planwright, it
> runs on Claude Code only, and it builds itself with its own commands. Expect
> rough edges, and please
> [report what you find](https://github.com/inkatze/planwright/issues/new/choose).

**New here?** The [getting-started guide](docs/getting-started.md) takes you
from a clean machine to your first draft PR.

## Why planwright

- **Rules the agent cannot argue with.** Claude Code's auto mode asks a model
  to judge each action. Every agent session planwright starts runs under hooks,
  plain scripts that run before that judgment, which refuse a push to `main` or
  any other protected branch, a pull-request merge, and a rewrite of history
  someone already pushed. The few exceptions are yours to grant, and
  [Human Gates](doctrine/human-gates.md) lists them all.
  **Placeholder, not yet measured:** on a published replay of risky git and
  file commands, the hooks block *[N]%* against *[M]%* for auto mode alone,
  and wrongly block *[K]%* of a normal session's commands.
- **Right-sized for each request.** A small, reversible fix becomes one draft
  pull request with a record of what was asked, what was done, and how it was
  checked. A risky feature, or one without a clear finish line, gets a written
  spec first, which you read and sign before any code is written; size alone
  never decides it. planwright tells you which it chose and why
  in one line, and one sentence from you overrides it.
  **Placeholder, not yet measured:** on a public sample of requests, a small
  fix reaches a draft pull request in a median of *[T]* minutes, and *[P]%*
  of requests are routed to a spec.
- **Review that stops.** Its review loops have iteration caps and stop when no
  progress is made, and they hand you the questions that need your judgment
  rather than deciding them on their own.
- **Your project's own checks.** Supply your linters, test commands, and review
  rigor through layered overlays, without editing planwright's core.
- **Built on Claude Code itself.** Skills, hooks, subagents, and plain files;
  there is no second agent framework to install.
- **More repositories when you want them.** An optional standing session can
  keep work moving across several of your repositories and bring you only the
  decisions; see [the guide](docs/mission-control.md).

## Requirements

- **Claude Code** — a recent version with the plugin and skill system.
- **git**, and a **GitHub repository** with the
  [**`gh`** CLI](https://cli.github.com/) authenticated — planwright opens draft
  PRs through `gh`. Without GitHub/`gh` the work still happens locally, but the
  pull-request flow is unavailable; see
  [the GitHub requirement](docs/getting-started.md#2-the-github-requirement-and-what-happens-without-it).

## Install

planwright installs through Claude Code's standard marketplace flow:

```text
/plugin marketplace add inkatze/planwright
/plugin install planwright@planwright
```

For environments without plugin support there is a portable no-plugin
installer. Both modes, and the upgrade path, are covered in
[Install](docs/getting-started.md#1-install).

## Quickstart

Open Claude Code in your repository and type `/tower`:

```text
/tower
```

Then say what you want, the way you would to a colleague: *"the CLI's help
text has a typo in the export command"*, *"why does the nightly job retry
three times?"*, *"add rate limiting to the public API"*.

- **A question** gets an answer in the conversation.
- **A change** gets a route and its grounds in one line, then flies under one
  of two flight rules. The names are the aviation analogy: visual rules when
  conditions are clear enough to fly by what you can see, instrument rules
  when you file a plan and trust the gauges.
  - **Visual flight** — clear, reversible work. An isolated agent makes the
    change, reviews it until it converges, and lands it with an audit record
    of what was asked, what was done, and how it was checked: in a draft PR
    once you allow flights to push to your host, kept local until then (the
    tower says which before the flight leaves).
  - **Instrument flight** — risky or unclear work. The tower makes the case
    for writing a spec first; on your yes it starts drafting one, and you walk
    it and sign it off with `/spec-kickoff` before anything is built.
- **Disagree with the route?** Say so in one sentence (*"just do it"*, *"write
  a spec for this"*) and the tower flies it your way, stating any reservation.
- **Ask what is happening** at any time; the tower reports the status of
  everything in flight.

Review the draft PR, and merge it when you are satisfied. The
[getting-started guide](docs/getting-started.md#3-start-with-the-tower) walks
a first session in more depth.

## How it works

### Flight rules

The tower chooses the route for each request; it is never a mode you set.
Work in a hard-disqualifier zone (security-sensitive code, migrations and
destructive operations, CI configuration, lockfiles, secrets) or otherwise not
one revert from undone files instrument flight automatically; work the tower
cannot state a clear "done when" for escalates by judgment; size alone never
decides. The full rule is in [the flight-rules doctrine](doctrine/flight-rules.md).

### The controls you keep

The same controls hold on both flight rules, and the tower changes none of
them. On visual flight and instrument flight alike, every PR opens as a draft
and **merge** stays yours: authorizing it is the approval act that also signs
off anything a PR asks you to approve. The **draft→ready flip** moves a
finished draft in front of reviewers; the tower never performs it, and whether
a unit's own run may flip a converged PR or the flip stays yours alone is a
policy you set (it approves nothing either way). Instrument flight adds
**sign-off**: a spec executes only after you walk it at kickoff and sign the
resulting brief, with no bypass flag; visual flight has no shadow sign-off, and
its audit record carries the trust. Rare hard pauses stop a run at
security-sensitive or irreversible steps on either rule. The authoritative list
of what stays yours, what is a policy, and who owns what is
[the human-gates doctrine](doctrine/human-gates.md).

### The four-file spec

An instrument flight files a spec in `specs/<feature>/` (the default spec
root; the `spec_root` option moves it, see
[Spec location](docs/spec-location.md)) as four files:

- `requirements.md` — what must be true (REQ-IDs), with a `Status:` that moves
  `Draft` → `Ready` → `Active` → `Done`.
- `design.md` — the decisions and the alternatives weighed (D-IDs).
- `tasks.md` — the work as stable-ID tasks with `Done when:` / `Dependencies:`.
- `test-spec.md` — each requirement pinned to how it is verified.

The format is specified in full in
[the spec-format doctrine](doctrine/spec-format.md).

## Commands

Each is a slash command in Claude Code. `/tower` is the one to start with; the
rest are there when you want to drive a stage yourself.

| Stage | Command | What it does |
| --- | --- | --- |
| **Start** | `/tower` | The front door: ask in plain language; it answers, routes changes, and reports status. |
| | `/mission-control` | One standing conversation for a program spanning repositories: it runs every session for you and brings you only what needs your judgment ([guide](docs/mission-control.md)). |
| **Orient** | `/inception` | Turn a product-level idea with no repo yet into a venture repo and its inception bundle ([guide](docs/inception.md)). |
| **Author** | `/spec-draft` | Interactively elicit a four-file spec bundle (Status Draft). |
| | `/spec-kickoff` | Walk a spec to sign-off and flip it Ready. *(your sign-off)* |
| | `/spec-walkthrough` | Render a spec into a plain-language artifact for an unaided cold read. |
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

## How it compares

Spec-driven development has many good tools; most stop at the spec. planwright's
bet is that the spec is only half the story: the other half is the guardrailed
harness that takes a request, specced or not, all the way to reviewed draft
PRs, at fleet scale if you want it.

| | [GitHub Spec Kit](https://github.com/github/spec-kit) | [Kiro](https://kiro.dev) | [OpenSpec](https://github.com/Fission-AI/OpenSpec) | planwright |
| --- | --- | --- | --- | --- |
| Spec authoring | ✅ specify / plan / tasks | ✅ spec-first IDE | ✅ lightweight change deltas | ✅ four-file bundle with a human sign-off gate |
| Autonomous execution | hands off to your agent | inside the IDE | hands off to your agent | ✅ test-first, full CI, bounded loops |
| Review convergence | — | — | — | ✅ autonomous review-and-fix until clean |
| Delivery | — | — | — | ✅ draft PRs; merge stays human |
| Parallel orchestration | — | — | — | ✅ multi-spec fleet mode |
| Runs on | agent-agnostic CLI | AWS IDE | agent-agnostic CLI | Claude Code, natively (no second framework) |

If you want an agent-agnostic spec format, Spec Kit and OpenSpec are excellent.
If you live in Claude Code and want the work *executed*, reviewed, and
delivered while you keep sign-off and merge, that is planwright.

## Under the hood

The tower drives a pipeline you can also drive by hand. These commands keep
their names; they are the machinery the tower and its workers use, documented
in [Architecture](docs/architecture.md):

| Command | What it does |
| --- | --- |
| `/orchestrate` | Pick a signed spec's next ready task, create its worktree, and dispatch execution. |
| `/execute-task` | Test-first build of one task → full CI → convergence → draft PR. |
| `/resume` | Load context for a fresh session in an in-flight worktree; `/resume tower` surfaces the checkout's flights needing attention and a count per state. |
| `/offload` | Place one free-form petition on the smallest sufficient execution rung. |

**Run it as a software factory.** One signed-off spec is autopilot; several at
once is a factory floor. `/orchestrate --fleet` autodetects the execution
backends on your host, supervises every Ready or Active spec with one isolated
worker per task under a fleet-wide concurrency bound, and renders a single
attention surface: a decision queue plus per-worker heartbeats. The same
controls hold at fleet scale. See [Fleet operation](docs/fleet.md).

## Documentation

- [Getting started](docs/getting-started.md) — install, the GitHub requirement,
  your first tower session, the controls you keep, and supplying your own
  tooling.
- [Architecture](docs/architecture.md) — the pipeline under the tower: the
  commands it drives, both flight rules end to end, and how to run them by
  hand.
- [Customizing with overlays](docs/overlays.md) — the four-layer model and
  per-kind merge rules.
- [Conventions](docs/conventions.md) — branch, worktree, and repo conventions.
- [Orienting an idea with `/inception`](docs/inception.md) — the venture
  lifecycle, the non-engineer and expert modes, the stakeholder surfaces, the
  persona layer and its boundaries, and the settings it adds.
- [Spec location](docs/spec-location.md) — where bundles live: the
  `spec_root` option and its marker, the three postures and how authoring
  works in each, holder layout and guards, running from a holder (the
  work-repository registry and per-task repositories), and named
  observation targets.
- [Orchestration state](docs/orchestration-state.md) — how progress is derived
  from git/GitHub evidence rather than kept in a mutable ledger.
- [Fleet operation](docs/fleet.md) — the approachable path: the one entry
  command, the decision queue, the persona-to-seams mapping, and the
  execution-backend seam (autodetect, the degradation ladder, plugging in
  your own backend) — no multiplexer knowledge required.
- [Mission control](docs/mission-control.md) — running a whole program from
  one conversation: the first run, where the program's state lives, duties,
  proposals, preferences, resuming and handover.
- [Per-tower checkouts](docs/per-tower-checkouts.md) — running several towers
  on one repository without them racing over a shared local `main`.
- [Model allocation](docs/allocation.md) — which model and effort a unit runs
  on, how that adapts to what execution reveals, and how to read the ledger
  that explains it.
- [Options reference](docs/options-reference.md) — every configuration option.
- [Doctrine](doctrine/README.md) — the framework's rule docs: validation and
  discovery rigor, finding categorization, engineering decisions, security
  posture, and more.
- [Contributing](docs/CONTRIBUTING.md) ·
  [Release checklist](docs/release-checklist.md)

## Project layout

```text
.claude-plugin/   plugin + marketplace manifests (the install path)
skills/           the planwright skills (one directory each)
doctrine/         the framework rule docs
scripts/          portable-shell entry points (installer, resolver, checks)
config/           tracked default config
docs/             guides (getting-started, architecture, overlays, conventions, spec location, options)
specs/            planwright's own specs, at the default spec root (bootstrap = the founding spec)
tests/            shell tests for the scripts
```

## Development

planwright pins its toolchain with [mise](https://mise.jdx.dev): run
`mise install` once and `scripts/wire-githooks.sh` once per clone (the
tracked git-hook backstop; the gate fails loudly on an unwired clone), then
`mise run check` runs the full gate: tests, linters and formatters, the spec
and manifest validators, and a secret scan. It is the same gate CI runs on
every pull request (`mise tasks` lists each check). This is dev tooling only;
planwright's runtime scripts stay plain portable bash. See
[Contributing](docs/CONTRIBUTING.md) for the workflow.

## License

[MIT](LICENSE).
