# Custom spec location — Requirements

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright hardwires the spec home to `specs/` under the git toplevel of the
checkout it runs in, and the scripts that need that root each re-derive it on
their own, disagreeing on whether "the repo" means the current worktree or the
primary checkout. This spec makes the spec home a resolved location. With
nothing configured it is exactly today's `specs/`; configured, it may sit
elsewhere in the repository, outside it, inside a separate repository that
holds one root per project it serves, or in a plain directory with no git at
all. Three roots are involved and each gets one resolver: the **install root**
(which planwright copy runs), the **primary checkout root** (which repository
the session belongs to, worktree-aware), and the **spec root** (where bundles
and the observation accumulator live). Every reader and writer of bundles and
fragments goes through those resolvers; the pieces that depend on git evidence
degrade by a stated ladder instead of failing or, worse, silently resolving to
an empty location. The altitude of the deliverable is recorded in D-1: a core
capability seam plus a doctrine amendment, with the specific locations staying
overlay values.

## Scope

### In scope

- A `spec_root` config option resolved through the four overlay layers, with a
  default that reproduces today's behaviour byte for byte.
- One shared resolver for the three roots (install, primary checkout, spec),
  and the migration of every script, hook, and skill that composes `specs/`
  or re-derives a root onto it.
- A marker file identifying a non-default root, so a mistyped pointer refuses
  instead of resolving to an empty root.
- The git posture ladder of the spec store (`same-repo`, `separate-repo`,
  `plain`) and how the authoring skills, the execution skills, the freshness
  gate, the hooks, and the worker permission guard behave on each rung.
- Spec addressing: the bare identifier as the canonical form, with today's
  `specs/<id>` accepted as an alias.
- The observation accumulator and `_pending/` following the spec root, plus
  named observation targets so a fragment surfaced in one repository can be
  routed to another project's accumulator on the same machine.
- The install-root chain: one helper, both command guards converged on it,
  and a self-hosting pin so a planwright checkout resolves its own tree.
- Guards, CI wiring, the options reference, adopter docs, and the
  `storage-classes` and `spec-format` doctrine amendments the new shape needs.

### Out of scope

- Notion, Google Drive, or any SaaS store as the spec store: a plain
  directory is in scope, a non-filesystem store is not (the same exclusion
  `inception` carries).
- Execution without a git work repository. Task state stays derived from the
  work repository's branches, PRs, and commit trailers; a store with no git
  is supported for the bundles, never as an execution evidence source.
- A reverse registry mapping a root back to its work repository. Deferred
  behind a gate (see `tasks.md`); every dispatching session today starts in
  the work repository that owns the pointer.
- Public-adopter observation fan-in (repositories the operator cannot read,
  issue-based submission). Named targets cover one operator's own machine.
- Any change to sign-off, merge, or the never-auto-merge invariants.

## REQ-A — The spec root

- **REQ-A1.1** With `spec_root` unset in every layer, the resolved root SHALL
  be `<checkout>/specs`, and every spec path, message, branch, and commit
  planwright produces from the primary checkout SHALL be identical to the
  pre-feature behaviour. The two worktree corrections (REQ-B1.2, REQ-B1.3)
  are the only behaviour changes with the option unset, and each is a named
  correction, never a silent one.
  *(Cites: D-3, D-7.)*
- **REQ-A1.2** A `spec_root` config option SHALL resolve through the four
  overlay layers with last-layer-wins. Its value is an absolute path, a
  `~/`-prefixed path, or a path relative to the primary checkout root.
  *(Cites: D-3.)*
- **REQ-A1.3** The resolver SHALL canonicalize the value before use and SHALL
  refuse, with a non-zero exit and no root printed, a value that is empty,
  carries a non-printable byte, or resolves to something other than a
  directory. A malformed value follows the customization-overlay by-layer
  policy: degrade with a warning for the adopter and machine-local layers,
  hard-fail for the repo-tracked layer.
  *(Cites: D-3, D-4; obs:e64d26ff.)*
- **REQ-A1.4** A root other than the default SHALL carry the root marker
  file. A configured root without it is refused, never treated as an empty
  root. The default root needs no marker.
  *(Cites: D-4; obs:c922e401.)*
- **REQ-A1.5** `_observations/` and `_pending/` SHALL be direct children of
  the resolved root, and the reserved-accumulator name grammar SHALL be
  unchanged.
  *(Cites: D-5.)*
- **REQ-A1.6** Every script, hook, and skill that locates a bundle or an
  accumulator SHALL obtain the root from the shared resolver; no code path
  SHALL compose the literal `specs/` itself.
  *(Cites: D-2; drafting-session decision (2026-09-21).)*
- **REQ-A1.7** No consumer SHALL infer the checkout root from the spec root's
  parent directory, and the assertion that the root's parent is named
  `specs` SHALL be removed from every script that carries it.
  *(Cites: D-2; the code map (Sources).)*
- **REQ-A1.8** The resolver SHALL offer an `--explain` mode naming the layer
  that supplied the value (or `default`), the canonical path, and the
  posture.
  *(Cites: D-6; customization-overlay D-9.)*
- **REQ-A1.9** The resolver SHALL return the checkout-local root by default
  (in the `same-repo` posture, the current worktree's own copy) and the
  canonical root (the primary checkout's main view, or the holder's) on
  request. Config values SHALL always resolve from the primary checkout.
  *(Cites: D-7.)*

## REQ-B — The primary checkout root

- **REQ-B1.1** One shared helper SHALL return the primary checkout root (the
  worktree that owns the common git directory), honouring
  `PLANWRIGHT_REPO_ROOT` first. Every script that today calls
  `git rev-parse --show-toplevel` to find "the repository" SHALL call it,
  asking explicitly for either the primary root or the current checkout root.
  *(Cites: D-8; obs:fd4c2ad6.)*
- **REQ-B1.2** The repo-side overlay layers (repo-tracked and machine-local)
  SHALL resolve against the primary checkout root, so a session in a
  worktree reads the same machine-local values the primary checkout does.
  *(Cites: D-8; obs:4467db6b, obs:65fea955.)*
- **REQ-B1.3** Worktree placement under `<repo>/.claude/worktrees/` SHALL
  resolve against the primary checkout root, never the process working
  directory.
  *(Cites: D-8; obs:de85a7f0.)*
- **REQ-B1.4** Outside any git repository the helper SHALL exit non-zero
  with a clear message, and its callers SHALL degrade per bootstrap
  REQ-K1.7 rather than compose a path from an empty root.
  *(Cites: D-8; bootstrap REQ-K1.7.)*

## REQ-C — The install root

- **REQ-C1.1** One shared helper SHALL own the core root chain
  (`PLANWRIGHT_ROOT`, then `CLAUDE_PLUGIN_ROOT`, then the writer-mode
  directory, then self-location), and every consumer of that chain SHALL
  call it, including both command guards.
  *(Cites: D-9; obs:92809aad, obs:0aaad2ef.)*
- **REQ-C1.2** The chain order SHALL stay as documented (explicit environment
  first, self-location last), and a planwright checkout SHALL pin
  `PLANWRIGHT_ROOT` to itself through its tracked tool configuration, so a
  self-hosted run or a test in a worktree resolves the tree under test.
  *(Cites: D-10; obs:4fe3d8a4, obs:945a1b04, obs:54e8035d.)*
- **REQ-C1.3** A chain arm that resolves to a directory lacking the expected
  content (no `doctrine/` and no `scripts/`) SHALL be skipped with a warning
  and never returned as the install root.
  *(Cites: D-9; obs:c922e401.)*

## REQ-D — Spec identity

- **REQ-D1.1** Every seam that takes a spec argument SHALL accept the bare
  identifier as the canonical form and `specs/<id>` as an alias mapped to
  the same identifier, and SHALL accept no other form.
  *(Cites: D-11.)*
- **REQ-D1.2** Branch names, worktree names, lock paths, commit trailers,
  and the `Consumed-by: specs/<id>` annotation SHALL stay keyed on the
  identifier and unchanged in form.
  *(Cites: D-11.)*
- **REQ-D1.3** The dispatch scope grammar and every sibling seam SHALL agree
  on the identifier form.
  *(Cites: D-11; obs:16a87c48.)*

## REQ-E — The git posture ladder

- **REQ-E1.1** The resolver SHALL classify the spec store as `same-repo`
  (the root lies inside the work repository's tree), `separate-repo` (inside
  a different git repository), or `plain` (inside no git repository), and
  SHALL print the posture with the root.
  *(Cites: D-6.)*
- **REQ-E1.2** In `separate-repo`, the spec branch, the spec worktree, the
  bundle commits, the consume commits, and the spec PR SHALL target the
  holder repository; task branches, task PRs, and commit trailers SHALL stay
  in the work repository.
  *(Cites: D-12.)*
- **REQ-E1.3** In `plain`, the authoring skills SHALL write the files and
  skip every branch, commit, push, and PR step, naming each skipped step in
  the handoff; no state file SHALL be introduced to stand in for git.
  *(Cites: D-13.)*
- **REQ-E1.4** The execution skills SHALL derive task state from the work
  repository in every posture; the spec store's posture SHALL never block a
  dispatch.
  *(Cites: D-13.)*
- **REQ-E1.5** The execution freshness gate SHALL read the bundle from the
  canonical root: the holder's main view in `separate-repo`, the directory
  itself in `plain`. The sanctioned anchor command forms are unchanged.
  *(Cites: D-14.)*
- **REQ-E1.6** The `tasks-pr-sync` hook and every fleet dispatcher SHALL
  locate the bundle through the resolver.
  *(Cites: D-2.)*
- **REQ-E1.7** The worker permission guard's sanctioned write zone SHALL
  include the resolved spec root when it lies outside the work repository.
  *(Cites: D-15.)*
- **REQ-E1.8** A holder repository MAY carry planwright's spec guards, wired
  through `/builder`; in `plain` no guard runs, and the authoring handoff
  SHALL say so.
  *(Cites: D-16.)*

## REQ-F — Observations across roots

- **REQ-F1.1** The observation scripts (record, consume, render, carry, and
  the store guard) SHALL default their store to `_observations/` under the
  resolved root.
  *(Cites: D-17; obs:cf3fd0b5, obs:41b74b2c.)*
- **REQ-F1.2** An `observation_targets` config option SHALL map aliases to
  roots, and `obs-record --target <alias>` SHALL write the fragment into the
  named root's accumulator after validating the alias grammar and that the
  target is a marker-bearing root or the default root of a git checkout.
  *(Cites: D-18; legacy L79 (Sources).)*
- **REQ-F1.3** A fragment written to a root other than the session's own
  SHALL carry no path, hostname, or private-repository identifier from the
  source; the writer SHALL refuse the write rather than launder one through.
  *(Cites: D-18; bootstrap REQ-D1.6.)*
- **REQ-F1.4** No fragment SHALL be sent to a public surface without an
  explicit human act.
  *(Cites: D-18.)*
- **REQ-F1.5** Fragment identity and the duplicate-UID refusal SHALL hold per
  accumulator, and the carry mechanism SHALL work in the `separate-repo`
  posture.
  *(Cites: D-17.)*

## REQ-G — Guards and documentation

- **REQ-G1.1** A CI check SHALL flag a literal `specs/` path composed in
  `scripts/` or `hooks/` code outside the resolver.
  *(Cites: D-19.)*
- **REQ-G1.2** The spec checks `mise run check` runs SHALL read the resolved
  root.
  *(Cites: D-19.)*
- **REQ-G1.3** The options reference, the overlays guide, the conventions
  doc, getting-started, and a spec-location guide SHALL document the option,
  the marker, the posture ladder, and the named targets; the meta-spec SHALL
  describe a spec as `<root>/<spec>/` with `specs/` as the default.
  *(Cites: D-20.)*
- **REQ-G1.4** The `storage-classes` doctrine SHALL state the class-3 home
  as a location the human owns, record the posture ladder, and classify the
  root marker as class-1 config.
  *(Cites: D-1, D-20.)*

## REQ-H — Compatibility

- **REQ-H1.1** With every new option unset, a fixture run of each migrated
  script from the primary checkout SHALL print the same paths and messages
  it printed before the migration; the fixture SHALL assert the two named
  worktree corrections (REQ-B1.2, REQ-B1.3) as changed, so an unintended
  change and an intended one are told apart.
  *(Cites: D-3.)*
- **REQ-H1.2** Existing bundles, kickoff briefs, and archived fragments SHALL
  stay valid without edits; no migration step SHALL be required of an
  adopter who keeps the default.
  *(Cites: D-11.)*
- **REQ-H1.3** Every option this spec introduces SHALL ship dark:
  `spec_root` unset, `observation_targets` empty.
  *(Cites: D-3; customization-boundary criterion 5.)*

## Changelog

- 2026-09-22 — Initial draft: bundle elicited from the invocation, the code
  map, and the observation fragments and legacy line listed under Sources,
  all consumed;
  scope widened during elicitation to the three roots and cross-repo
  observation targets; the work-repo mapping settled as pointer plus marker
  with the reverse registry deferred.

## Sources

- **The invocation** (2026-09-21): "make the spec location more flexible …
  custom locations inside or outside the repository; even another
  repository that holds multiple specs for other repos or projects …
  locations without git at all." Pinned altitude claims: the multi-project
  holder and the git-less store are both assertions about the deliverable's
  nature that collide with the `storage-classes` class-3 home, resolved in
  D-1.
- **The code map** (drafting-session research, 2026-09-21): a sweep of the
  scripts, hooks, skills, and docs for repo-root resolution and `specs/`
  literals. Findings: no shared repo-root helper and inline copies across the
  scripts disagreeing on worktree versus primary; the spec-reading scripts
  already take the spec directory as an argument; the unattended callers
  (the sync hook, the fleet dispatchers, the fetch script, the CI globs)
  hardcode the path; three scripts assert the root's parent is named `specs`
  and infer the checkout from it; the only path-valued knob precedent is
  `version_file`; the only out-of-repo absolute root precedent is the fleet
  home.
- **obs:4467db6b**, **obs:fd4c2ad6**, **obs:65fea955** — a worktree session
  loses the machine-local config layer because the repo root resolves to the
  worktree.
- **obs:de85a7f0** — worktree placement resolved against the process working
  directory.
- **obs:e64d26ff** — the existing path knob canonicalizes against the
  working directory while containing against the toplevel.
- **obs:e144633c** — the drain sweep's cost is almost entirely git
  evidence; a non-git tree sweeps in seconds.
- **obs:16a87c48** — the dispatch scope grammar and its sibling seams
  disagree on spec path versus spec id.
- **obs:cf3fd0b5**, **obs:41b74b2c** — skills hardcode the observations
  path.
- **obs:4fe3d8a4**, **obs:945a1b04**, **obs:54e8035d** — self-hosted runs
  resolve the installed plugin instead of the checkout under test.
- **obs:c922e401** — an install-root arm resolved to a directory with no
  content and returned it at exit 0.
- **obs:92809aad**, **obs:0aaad2ef** — the two command guards resolve the
  trusted install root by divergent chains.
- **Legacy L79** (`opportunities.md`, 2026-06-17): the accumulator is
  single-repo by construction; a planwright-about observation surfaced in a
  work repo never reaches planwright's log without a manual relocate.
- **research: adr-tools `_adr_dir`** — the record directory is located by a
  `.adr-dir` pointer file found by walking up from the working directory,
  its path relative to that file, default `doc/adr` when absent.
- **research: gitrepository-layout(5)** — a worktree points at its
  repository through a gitfile and a `commondir` entry whose paths are
  relative to the file holding them; the pointed-to location is a real
  repository, not a bare directory.
- **Doctrine consulted:** `interaction-style`, `research-rigor`,
  `security-posture`, `proportionality`, `spec-format`,
  `engineering-decisions`, `customization-boundary`, `autopilot-reflex`,
  `storage-classes`, `decision-domains`.
