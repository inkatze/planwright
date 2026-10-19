# Getting started with planwright

This guide takes a newcomer from a clean machine to a first draft pull
request: install planwright, start `/tower`, bring it a request, and review
what lands, then supply your project's own tooling and rigor without editing
planwright's core.

If you read only one thing: planwright is an **autopilot**, not a replacement
crew. You say what you want to the tower, it chooses how carefully the work
flies and tells you why, and it stops at the controls that are yours. Merging
is always one of them.

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
`CLAUDE_DIR`/`HOME`. When no env root is set (e.g. a skill Bash subshell that
does not inherit `CLAUDE_PLUGIN_ROOT`), the resolver falls back to locating the
core doctrine beside its own script. See
[`doctrine/README.md`](../doctrine/README.md) for the convention's details.

### Upgrading and cleaning up

- **Plugin:** upgrade through the marketplace; Claude Code manages versions.
- **Writer:** re-running `scripts/install.sh` refresh-copies but never deletes,
  so files removed or renamed in a newer planwright would linger. To upgrade
  cleanly, **delete `~/.claude/planwright/` first, then re-run the writer**
  (a clean reinstall). The writer's namespaced layout makes this safe: only
  the `planwright/` namespace is removed, and shipped skills/commands are
  re-copied by the next run.

#### Breaking: the convergence knob became a step list

The `review_sequence` config key is gone: rename it to `steps_convergence`
in every layer that sets it, keeping the value as an inline flow list
(`[polish]`, not a bare `polish`, and no empty entries). Both specless work
and spec tasks converge through that list. Its ids name entries in the `steps` catalog; the core
catalog seeds `polish` and `self-review` with `--nested`, so a list naming
them runs what it ran before. A layer still setting the old key is ignored,
with a warning naming the layer on every resolution. The new
list also admits steps planwright does not ship (your own review commands,
shell commands, prompts), declared in an overlay catalog; see
[overlays §8](overlays.md#8-worked-example-b--custom-steps-a-runnable-style-overlay).

#### One-time: re-anchor bundles signed before the anchor-scope change

Each spec bundle's kickoff brief records a **content anchor**, and the
execution freshness gate halts when it no longer recomputes. The anchor's scope
narrowed once: the per-file digests now exclude the header block's
`**Status:**` line, so a lifecycle flip stops false-halting the gate. Bundles
signed off before that change — and any bundle whose entry uses the interim
whole-file `git hash-object` form — hash a scope the current tool no longer
computes, so they halt on content nobody edited. planwright's own bundles were
swept when the change landed; yours need the same repair, once.

It is not a blind re-record, because a bare one would launder a real edit as if
it were the scope change. For each halting bundle:

1. Find the commit that introduced the brief's most recent `Anchor:` line and
   diff the bundle's **anchored** content from there to now (header `Status:`
   lines and `tasks.md` state annotations and block placement are excluded, so
   a diff confined to those counts as no change at all).
2. **Nothing but excluded content, or an expression-only edit** (a typo, a
   rewrap, a changelog line): append the machine `Class: expression-only`
   re-anchor entry to the brief's amendment log, citing the changelog line for
   the delta that actually moved the anchor. The amendment logs under
   `specs/*/kickoff-brief.md` in this repo are worked examples of the format.
3. **A meaning edit, or a delta you cannot confidently classify:** re-review
   instead. Run a `/spec-kickoff` delta re-walkthrough for a `Ready` or
   `Active` bundle; use the reopen cycle for a `Done` one. The gate stays
   failed closed for that bundle until the re-review signs it off, which is the
   intended outcome — an unreviewed meaning edit must not ride a mechanical
   sweep.

The rule and the halt guidance live in
[`doctrine/spec-format.md`](../doctrine/spec-format.md), *Execution validity*.

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

## 3. Start with the tower

Open Claude Code in your repository and type `/tower`. It is a standing
conversation: keep it open and bring it each request in your own words, the
way you would brief a colleague.

The first time, the tower checks that it runs under its own permission
profile, the guardrails that keep it from merging or rewriting history. If they
are missing, it says so once and names the step that wires them; until you take
it, or tell the tower to go ahead without them, it keeps answering questions
and starts no change.

What happens next depends on the ask.

- **A question** is answered in the conversation. One that needs a large look,
  such as reading a whole subsystem, is handed to a helper, and the answer
  comes back to you.
- **A change** takes a route. The tower picks one of two flight rules for each
  request and states it with its grounds in one line, for example *"visual
  flight: a one-line copy fix, one revert from undone"*. The names are the
  aviation analogy: visual rules when conditions are clear enough to fly by
  what you can see, instrument rules when you file a plan and trust the gauges.
  - **Visual flight** is clear, reversible work with no spec. An isolated agent
    makes the change, runs the project's checks, reviews its own work until it
    converges, and lands it with an audit record: what you asked, what it heard,
    what changed, and how it was verified. The record lives in a draft pull
    request once you allow flights to push to your host, and stays local until
    then; the tower tells you which before the flight leaves.
  - **Instrument flight** is risky or unclear work: security-sensitive code,
    anything not one revert from undone, or an ask without a clear "done when".
    The tower first makes a one-page case for writing a spec, alternatives
    included. On your yes it starts drafting one with your ask as the seed; you
    walk the draft with `/spec-kickoff` and sign it off. After sign-off, tell
    the tower to go, and the work is built task by task, each task landing as
    its own draft pull request.
- **Disagree with a route?** One sentence moves it either way (*"just do it"*,
  *"this needs a spec"*). The tower states any reservation in one line and
  complies; no override reaches the controls in the next section.
- **Ask for status** whenever you like (*"what's in flight?"*). The tower
  answers from what is recorded, decisions waiting on you first.

Then you review. Each draft pull request explains itself and lists anything it
needs you to approve; merge it when you are satisfied. You can also skip the
tower for spec work: `/spec-draft <feature>` drafts a spec directly,
`/spec-walkthrough <spec-path>` renders one as a plain-language read, and
`/drain` reviews the decisions deferred across specs. What runs underneath,
and how to drive it by hand, is in [Architecture](architecture.md).

## 4. The controls you keep

The same controls hold on both flight rules, and the tower changes none of
them:

- **Merge.** On visual flight and instrument flight alike, every pull request
  opens as a draft and merge stays yours. Authorizing it is the approval act,
  which also signs off every item a PR lists for your approval.
- **The draft→ready flip.** It moves a finished draft in front of reviewers and
  approves nothing. The tower never performs it; whether a task's own run may
  flip a converged PR, or the flip stays yours alone, is a policy you set.
- **Sign-off, on instrument flight.** A spec executes only after you walk it at
  kickoff and sign the resulting brief; there is no bypass flag. Visual flight
  has no shadow sign-off: its audit record carries the trust.

Between them, the intervention contract has three phases: sign-off before
execution on instrument flight, **rare hard pauses during** it on either rule
(security-sensitive zones, destructive operations, irreducible judgment forks),
and **PR review plus merge after**. Everything an agent applied on a branch is
one revert from undone until you merge. The authoritative list of what stays
yours, what is a policy, and which skill owns which act is
[the human-gates doctrine](../doctrine/human-gates.md).

## 5. Supplying your own tooling and rigor (without editing core)

planwright core ships **general** doctrine and skills. Your project carries its
own preferences — which review steps run and when, a dispatch-isolation default,
project-specific decision-domain entries, extra linters or rigor — and you must
be able to add them **without editing planwright's core rule docs** (REQ-D2.2 /
REQ-I1.4). Editing core would make it less general for everyone and pollute the
observation stream meant to merge upstream.

Three customization mechanisms exist, all of which avoid editing core:

- **The overlay mechanism (the general seam).** A fixed four-layer precedence
  model — `core defaults < adopter overlay < repo-tracked overlay <
  machine-local overlay` — lets you layer **config values, doctrine/process
  docs, and data catalogs** without touching planwright's core. Adding a
  preference is a **file placement**, never a core edit. Each kind keeps its
  native shape and merges in the way that fits it (config last-layer-wins,
  doctrine whole-doc shadow, catalog append/union), and each resolver has an
  `--explain` mode that names the winning layer. The full reference — per-layer
  locations, merge rules, the malformed-by-layer policy, the secret-scanner
  caveat, and worked examples — is in
  [`docs/overlays.md`](overlays.md). For *what belongs in an overlay versus
  core*, see
  [`doctrine/customization-boundary.md`](../doctrine/customization-boundary.md).
- **Config overrides.** Universal defaults live in
  [`config/defaults.yml`](../config/defaults.yml); the overlay mechanism's
  config layers (above) layer on top — set a personal default across all your
  repos in `<adopter-root>/planwright.yml` (the adopter overlay root, defined in
  [overlays.md §1](overlays.md#1-the-four-layers)), a repo-shared override in
  `<repo>/.claude/planwright.yml`, or a machine-local one in
  `<repo>/.claude/planwright.local.yml` (gitignored where your `.gitignore`
  covers it, agent-maintained; entries are written only on your confirmation).
  Every option is documented in the [options reference](options-reference.md); an
  undocumented option fails planwright's own CI. This covers thresholds and
  commit/dispatch toggles.
- **Project tooling discovery.** planwright's SessionStart hook detects your
  project's linters, formatters, and type-checkers and feeds them into
  Discovery Rigor and the builder, so your stack's tools ground reviews without
  any core edit.

> **Secrets never go in overlays.** Your adopter overlay lives outside any repo,
> and your machine-local overlay is meant to stay uncommitted (gitignored — but
> only where your `.gitignore` covers it; see overlays.md §6's caveat), so planwright's
> secret scanner (`gitleaks`, which scans committed files only) never sees them.
> The data-hygiene rule is the only guard there — keep secrets in your
> environment layer and reference them indirectly. See [`docs/overlays.md`
> §6](overlays.md#6-secrets-and-data-hygiene--read-this).

## 6. Releasing planwright

Cutting a release follows the [release-tagging policy](../doctrine/release-tagging.md):
detection and proposal are automated, **approval is your merge** of the release
PR, and **publish is a conscious, signed, human-run step**. Nothing is tagged or
published by CI. This section is the operational how-to for a publisher; the
policy and the altitude split behind it live in the doctrine.

### The flow, end to end

1. **A release PR is proposed automatically.** release-please runs in PR-only
   mode: conventional commits landing on `main` open (or update) a standing
   release PR that bumps the version of truth
   (`.claude-plugin/plugin.json`) and updates `CHANGELOG.md`. Editing the PR
   corrects the proposal; closing it cancels. CI never creates a tag or Release.
2. **You merge the release PR.** The merge *is* the release approval, and it
   stays a human act in GitHub's UI (or, under `merge_policy: on-approval`,
   your enabling auto-merge) under every `merge_policy` value: the policy class
   admits only task branches, so a release PR is never a class admission and no
   planwright command merges it. Merging
   lands the version bump on `main` and opens the **untagged window**.
3. **The untagged window is locked by a required CI check.** This is the
   [release-tagging policy](../doctrine/release-tagging.md)'s forcing function:
   once the untagged-window lock is enabled as a required check on the repo,
   any time the version of truth is ahead of the latest release tag the check
   fails on `main` and names the publish command in its output, so the pending
   publish is pushed to you by a red check rather than left to memory.
4. **You publish.** Run the publish command (below) after the merge. It cuts the
   signed annotated tag on the observed release-merge commit, verifies the
   signature, pushes the tag, creates the GitHub Release from the version's
   `CHANGELOG.md` section, and relabels the merged release PR from
   `autorelease: pending` to `autorelease: tagged` (best-effort — a failure here
   only warns, it never blocks the publish) so release-please's own state
   tracking stays in sync and doesn't deadlock on the next run. The window
   closes and the required check goes green.

Merge (step 2) and publish (step 4) are the two irreversible, externally-visible
acts; both are always conscious human steps. planwright automates everything up
to them and nothing through them — no agent merge, no background auto-sign, no
bypass flag.

### The publish command

```sh
scripts/release-publish.sh
```

The script is signer-agnostic and refuses **without side effects** on any safety
gate: a dirty tree, a local `main` out of sync with `origin/main`, the target
tag already present locally or on `origin` (idempotency), the target version not
strictly greater than the latest release tag (monotonicity), or GitHub CI not
green on the release commit (checked against the real external state via `gh`). A
partial publish — tag pushed but its Release missing — resumes by creating the
Release rather than refusing. It tags the observed release-merge commit, never
`HEAD`.

### Armed mode (optional — shrinks the locked window)

The publish above runs *after* you merge, so the untagged window stays open for
however long it takes you to come back and publish. If you would rather shrink
that window to merge-to-sign, **arm** the release before you merge:

```sh
scripts/release-arm.sh <release-pr-number>
```

Armed mode pre-validates everything checkable ahead of the merge (the PR is
open, its release-gating CI is green, the proposed version is monotonic and
untagged, your `main` is clean and synced), **refuses to arm with a reason if any
pre-check fails**, then watches the release PR. The moment it observes the merge
it fast-forwards `main`, waits for the merged commit's release-gating CI to go
green, and runs the publish — so the tag lands on the observed merge commit with
the smallest possible gap. Throughout, arm's CI check **excludes the untagged-
window lock**, which is red by design once a release is pending (it gates further
merges, not the publish); it only ever requires the *quality* checks to be green.
It is a convenience wrapper, not a new authority: it merges nothing (your merge is
still the approval), and on the observed merge it delegates to
`scripts/release-publish.sh`, which re-enforces every safety gate and does the
signing. If the PR is closed without merging, arm disarms and publishes nothing.
The post-merge command above remains the unchanged fallback — use it directly
whenever you do not want to hold a watching session.

### The signing policy

This repo requires **genuinely signed** annotated release tags. The
`require_signed_tags` knob is set to `require` in this repo's repo-tracked
overlay ([`.claude/planwright.yml`](../.claude/planwright.yml)), so the publish
script **refuses to tag unless git signing is configured and the signature
succeeds**, and it verifies the tag with `git tag -v` before pushing it (the
[`require_signed_tags` option](options-reference.md) documents the `auto` /
`require` / `never` modes).

Signing is delegated **entirely to this repo's git config** — no signer is named
in the script and **no signing material ever enters CI**. planwright's own
publisher signs SSH tags via 1Password's `op-ssh-sign` (the same key that signs
commits); the per-release biometric tap is itself the conscious human gate on the
irreversible publish. Any git-supported signer works: GPG, a plain SSH key, or an
agent-held key. The relevant git config is `gpg.format`, `user.signingkey`, and
(for SSH) `gpg.ssh.program`.

**Manual prerequisite — register your SSH key as a GitHub *signing* key.** For a
signed tag to render **Verified** on GitHub, the public key must be added to your
GitHub account as a **Signing Key** (Settings → *SSH and GPG keys* → *New SSH
key* → **Key type: Signing Key**). This is separate from an *Authentication Key*:
the key you already use to `git push` over SSH does **not** make signatures render
Verified until the same public key is also added with the *Signing Key* type. Do
this once per signing key; it is an account action planwright cannot perform for
you.

> **Release-tag pushes vs. the worker push guardrails.** planwright's
> [worker-settings profile](../config/worker-settings.json) denies force pushes
> and any push whose destination is `main`, `master`, or a spec branch, to keep
> the never-force-push / never-touch-`main` invariants intact for autonomous workers. A release-tag push
> (`git push origin <tag>`, e.g. `git push origin v0.2.1`; the publish step pushes the
> same tag ref via `git push origin refs/tags/<tag>`) matches none of those deny rules
> and stays allowed — the guardrails and the human publish path coexist. The publish
> step is a conscious human action and does not run under the worker profile in any case.

## 7. Where to go next

- [`README.md`](../README.md) — the one-screen overview and repository layout.
- [`docs/architecture.md`](architecture.md) — the pipeline under the tower:
  the commands it drives, both flight rules end to end, and running them by
  hand.
- [`docs/overlays.md`](overlays.md) — customizing planwright with overlays: the
  four layers, per-kind locations, merge rules, and worked examples.
- [`doctrine/`](../doctrine/) — the rule docs skills cite (rigor, finding
  categorization, engineering doctrine, spec format).
- [`docs/conventions.md`](conventions.md) — repository and workflow
  conventions.
- [`docs/orchestration-state.md`](orchestration-state.md) — the derived-projection
  model behind concurrent orchestration (derivation, single-writer reconcile,
  the trailer, no-remote flow), version-keyed off each bundle's
  `Format-version:` — a format-version 2 bundle drops the committed snapshot and
  reads status through the render.
- [`docs/fleet.md`](fleet.md) — fleet operation: the one entry command, the
  execution-backend seam (autodetect, the degradation ladder, plugging in your
  own backend), the decision queue you watch, and what an unattended fleet
  decides without you — no multiplexer knowledge required.
- [`docs/per-tower-checkouts.md`](per-tower-checkouts.md) — one clone per tower:
  the topology that removes the shared-`main` race, the reachable-`origin`
  precondition, the fast-forward-only currency sync, and the migration path
  (repo-root machine-local env file, stable `auth_sock` indirection).
- [`docs/CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute changes.
- [`docs/release-checklist.md`](release-checklist.md) — the public-release
  readiness gate (for maintainers).
