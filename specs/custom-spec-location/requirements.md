# Custom spec location — Requirements

**Status:** Ready
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
capability seam plus the doctrine amendments it needs, with the specific
locations staying overlay values.

**Terms used throughout.** The **work repository** is the git repository
whose code the tasks change and from whose branches, PRs, and commit
trailers task state is derived; its **primary checkout root** is the
worktree owning the common git directory, and the two phrases name the same
repository. A **holder** is a second git repository whose job is to hold one
spec root per project it serves. The **spec store** (unqualified "the
store") is the resolved spec root and everything under it; the
**observation store** is its `_observations/` child. A **posture** is the
spec store's git relationship to the work repository (REQ-E1.1). The
**checkout-local view** of the root is the current checkout's own copy and
the **primary view** is the primary checkout's (or the holder's) copy
(REQ-A1.9); "canonicalize" means filesystem path normalization only
(symlinks and `..` resolved) and is never a view.

## Scope

### In scope

- A `spec_root` config option resolved through the four overlay layers, with a
  default that reproduces today's behaviour byte for byte.
- One shared resolver for the three roots (install, primary checkout, spec),
  and the migration of every script, hook, skill, and build-config task that
  composes `specs/` or re-derives a root onto it.
- A marker file identifying a non-default root, so a mistyped pointer refuses
  instead of resolving to an empty root.
- The git posture ladder of the spec store (`same-repo`, `separate-repo`,
  `plain`) and how the authoring skills, the execution skills, the freshness
  gate, the hooks, and the worker permission guard behave on each rung.
- Spec addressing: the bare identifier as the canonical form on skill
  arguments and identity seams, with today's `specs/<id>` accepted as an
  alias.
- The observation accumulator and `_pending/` following the spec root, plus
  named observation targets so a fragment surfaced in one repository can be
  routed to another project's accumulator on the same machine.
- The install-root chain: one helper, every consumer including both command
  guards reading the chain from it, and a self-hosting pin so a planwright
  checkout resolves its own tree.
- Guards, CI wiring, the options reference, adopter docs, and the doctrine
  amendments the new shape needs.

### Out of scope

- Notion, Google Drive, or any SaaS store as the spec store: a plain
  directory is in scope, a non-filesystem store is not. This is narrower than
  the exclusion `inception` carries, which also rules out any non-git store;
  this spec admits a non-git store for bundles.
- Execution without a git work repository. Task state stays derived from the
  work repository's branches, PRs, and commit trailers; a store with no git
  is supported for the bundles, never as an execution evidence source.
- A reverse registry mapping a root back to its work repository: not
  delivered here, deferred behind a gate (see `tasks.md`); every dispatching
  session today starts in the work repository that owns the pointer.
- Public-adopter observation fan-in (repositories the operator cannot read,
  issue-based submission). Named targets cover one operator's own machine.
- Any change to sign-off, merge, or the never-auto-merge invariants.

## REQ-A — The spec root

- **REQ-A1.1** With `spec_root` unset in every layer, the resolved root SHALL
  be `<checkout>/specs`, and every spec path, message, branch, and commit
  planwright produces SHALL be identical to the pre-feature behaviour except
  for named corrections. Every behaviour change with the option unset SHALL be
  a named correction carried in the compatibility fixture's expected-change
  set (REQ-H1.1), never a silent one. The corrections this spec names: the
  two worktree corrections (REQ-B1.2, REQ-B1.3); the narrowing of
  `PLANWRIGHT_REPO_ROOT` to the primary root (REQ-B1.1); the install-root
  chain convergence, under which consumers running a shorter chain today gain
  the documented arms and the content-check warning (REQ-C1.1, REQ-C1.3);
  and, inside a planwright checkout only, the self-hosting pin (REQ-C1.2).
  *(Cites: D-3, D-7, D-8, D-9, D-10; kickoff §3 REQ-H (2026-09-22); kickoff
  §8 K7 (2026-09-22).)*
- **REQ-A1.2** A `spec_root` config option SHALL resolve through the four
  overlay layers with last-layer-wins. Its value is an absolute path, a
  `~/`-prefixed path (`~` alone names `HOME`; `~user` forms are refused), or
  a path relative to the primary checkout root; surrounding whitespace is
  trimmed before any other reading.
  *(Cites: D-3.)*
- **REQ-A1.3** An empty value in a layer SHALL mean unset in that layer: the
  resolution falls through to the next lower layer and, with no layer
  setting a value, to the default root. Only the winning non-empty value is
  validated. A value carrying a non-printable byte is malformed text and
  follows the customization-overlay by-layer policy (warn and fall through
  for the adopter and machine-local layers, hard-fail for the repo-tracked
  layer). The resolver SHALL canonicalize a well-formed value before use and
  SHALL then refuse it, with a non-zero exit, no root printed, and a message
  naming the supplying layer, in every layer alike, when it names a path
  that does not exist, is not a directory, or, being relative, escapes the
  primary checkout after canonicalization; a refused value SHALL never fall
  back to the default root, because a wrong root is the fail-open shape D-4
  exists to stop.
  *(Cites: D-3; obs:e64d26ff; kickoff §8 K1 (2026-09-22).)*
- **REQ-A1.4** A root other than the default SHALL carry the root marker
  file `planwright-spec-root.yml`. A configured root without it is refused
  in every layer, never treated as an empty root. The default root needs no
  marker. "The default" is decided by the resolved path, not by whether the
  option is set: a value whose primary view (REQ-A1.9) is
  `<primary checkout>/specs` is the default root and needs no marker,
  exactly as an unset option does.
  *(Cites: D-4; obs:c922e401; kickoff §2 (2026-09-22).)*
- **REQ-A1.5** `_observations/`, `_pending/`, and every other reserved
  accumulator the meta-spec defines SHALL be direct children of the resolved
  root under its checkout-local view, and the reserved-accumulator name
  grammar SHALL be unchanged. Off the default root, the marker init SHALL
  write the ignore rules that keep the local-only entries (`_pending/notes.md`
  and per-spec runtime files) out of git wherever the root lies in a git
  repository.
  *(Cites: D-4, D-5; kickoff §8 K10 (2026-09-22).)*
- **REQ-A1.6** Every script, hook, skill step, and build-config task that
  locates a bundle or an accumulator SHALL obtain the root from the shared
  resolver; no code path SHALL compose the literal `specs/` as a filesystem
  path. A namespace literal (REQ-D1.2) is not a path and is allowlisted by
  line in the guard (REQ-G1.1).
  *(Cites: D-2, D-11; obs:cf3fd0b5, obs:41b74b2c; drafting-session decision
  (2026-09-21).)*
- **REQ-A1.7** No consumer SHALL infer the checkout root from the spec root's
  parent directory: every script that asserts the root's parent is named
  `specs` SHALL drop the assertion, and every script that derives a checkout
  from the root's parent SHALL take it from the primary-root helper
  (REQ-B1.1) instead.
  *(Cites: D-2; the code map (Sources); orchestration-concurrency REQ-F1.1
  for the lock containment the assertion used to serve.)*
- **REQ-A1.8** The resolver SHALL offer an `--explain` mode on every root
  kind, naming the arm or layer that supplied the value (or `default`), the
  canonicalized path, and, for the spec kind, the posture and the view.
  *(Cites: D-6; customization-overlay D-9.)*
- **REQ-A1.9** The resolver SHALL return the checkout-local root by default
  (in the `same-repo` posture, the current worktree's own copy) and the
  primary view (`--primary`: the primary checkout's copy in `same-repo`, the
  holder's in `separate-repo`, the directory itself in `plain`) on request. A
  relative value, or an absolute value that lies inside the primary checkout,
  SHALL be re-based onto the current checkout for the checkout-local view.
  Config values SHALL always resolve from the primary checkout, whichever
  view is asked for.
  *(Cites: D-7.)*

## REQ-B — The primary checkout root

- **REQ-B1.1** One shared helper SHALL return the primary checkout root (the
  worktree that owns the common git directory) on `--primary`, honouring
  `PLANWRIGHT_REPO_ROOT` first when it names an existing git toplevel and
  refusing it otherwise, and the current toplevel on `--checkout`, which the
  variable never affects. Every script that today calls
  `git rev-parse --show-toplevel` to find "the repository" SHALL call the
  helper, asking explicitly for one of the two.
  *(Cites: D-8; obs:fd4c2ad6.)*
- **REQ-B1.2** The repo-side overlay layers (repo-tracked and machine-local)
  SHALL resolve against the primary checkout root, so a session in a
  worktree reads the same machine-local values the primary checkout does.
  *(Cites: D-8; obs:4467db6b, obs:65fea955.)*
- **REQ-B1.3** Worktree placement under `<repo>/.claude/worktrees/` SHALL
  resolve against the primary checkout root of the repository that owns the
  worktree (the work repository for task worktrees, the holder for the spec
  worktree in `separate-repo`), never the process working directory.
  *(Cites: D-8, D-12; obs:de85a7f0.)*
- **REQ-B1.4** Outside any git repository, or inside a bare repository with
  no primary working tree, the helper SHALL exit non-zero with a message
  naming the case, and its callers SHALL degrade per bootstrap REQ-K1.7
  rather than compose a path from an empty root.
  *(Cites: D-8; bootstrap REQ-K1.7.)*

## REQ-C — The install root

- **REQ-C1.1** One shared helper SHALL own the core root chain
  (`PLANWRIGHT_ROOT`, then `CLAUDE_PLUGIN_ROOT`, then the writer-mode
  directory, then self-location), and every consumer of that chain SHALL
  obtain it from the helper, including every command guard. A guard composes
  its trust set from the helper's chain plus its own per-guard policy (the
  worker guard's installed-roots arm; the tower guard's distinct, tighter set
  per fleet-hardening REQ-C1.2); the guards SHALL share the chain, not the
  set.
  *(Cites: D-9; obs:92809aad, obs:0aaad2ef; fleet-hardening REQ-C1.2.)*
- **REQ-C1.2** The chain order SHALL stay as documented (explicit environment
  first, self-location last), and a planwright checkout SHALL pin
  `PLANWRIGHT_ROOT` to its own root through its tracked tool configuration
  as a config-root expansion, so every checkout of the tree, each worktree
  included (each carries its own tracked copy), resolves itself rather than
  the installed plugin. The pin's test SHALL be non-vacuous: it sets a decoy
  `CLAUDE_PLUGIN_ROOT` and asserts the pinned root wins.
  *(Cites: D-10; obs:4fe3d8a4, obs:945a1b04, obs:54e8035d; kickoff §8 K6
  (2026-09-22).)*
- **REQ-C1.3** A chain arm that resolves to a directory lacking the expected
  content (no `doctrine/` and no `scripts/`) SHALL be skipped with a warning
  and never returned as the install root.
  *(Cites: D-9; obs:c922e401.)*

## REQ-D — Spec identity

- **REQ-D1.1** Every skill argument and every identity seam that names a spec
  (dispatch, scope, fetch, trailers, consume, lock and marker names) SHALL
  accept the bare identifier as the canonical form and `specs/<id>` as an
  alias mapped to the same identifier, a single trailing slash tolerated on
  either form as shell completion produces it, and SHALL accept no other
  form. A script that operates on a bundle directory keeps taking that
  directory, produced by the resolver, and gains no alias handling.
  *(Cites: D-11; kickoff §3 REQ-D (2026-09-22); kickoff §8 K2 (2026-09-22).)*
- **REQ-D1.2** Branch names, worktree names, lock paths, commit trailers,
  and the `Consumed-by: specs/<id>` annotation SHALL stay keyed on the
  identifier and unchanged in form.
  *(Cites: D-11.)*
- **REQ-D1.3** The dispatch scope grammar SHALL keep its field grammar and
  take the bare identifier; every caller that names a unit scope SHALL pass
  that form, and the usage and error text SHALL name the expected shape.
  *(Cites: D-11; obs:16a87c48.)*

## REQ-E — The git posture ladder

- **REQ-E1.1** The resolver SHALL classify the spec store by repository
  identity: `same-repo` when the repository containing the root's primary
  view shares the work repository's common git directory (another worktree
  of the same repository counts), `separate-repo` when it has a different
  one, `plain` when the root lies in no git repository. An in-repo root that
  git ignores classifies `same-repo`, and the authoring commit step is where
  that surfaces. The posture SHALL be exposed through `--posture` and
  `--explain`; the default output stays the bare path.
  *(Cites: D-6; kickoff §8 K10, K12 (2026-09-22).)*
- **REQ-E1.2** In `separate-repo`, the spec branch, the spec worktree (at
  `<holder>/.claude/worktrees/<id>-spec`), the bundle commits, the consume
  commits, and the spec PR SHALL target the holder repository; task
  branches, task PRs, and commit trailers SHALL stay in the work repository.
  *(Cites: D-12.)*
- **REQ-E1.3** In `plain`, the authoring skills SHALL write the files, SHALL
  create no spec branch or worktree in any repository, and SHALL skip every
  commit, push, and PR step, naming each skipped step in the handoff; no
  state file SHALL be introduced to stand in for git.
  *(Cites: D-13.)*
- **REQ-E1.4** The execution skills and the derivation scripts they run SHALL
  derive task state from the work repository (REQ-B1.1) in every posture,
  never from the repository containing the spec directory; the spec store's
  posture SHALL never block a dispatch.
  *(Cites: D-13; kickoff §8 K8 (2026-09-22).)*
- **REQ-E1.5** The execution freshness gate SHALL read the bundle from the
  primary view: the default branch's committed view of the primary checkout
  in `same-repo` and of the holder in `separate-repo`, and the directory
  itself in `plain`. The default branch is the remote's HEAD branch where a
  remote exists, else the branch the local HEAD names, never assumed to be
  called `main`. The sanctioned anchor command forms are unchanged.
  *(Cites: D-14; anchor-integrity REQ-B1.1, REQ-F1.1.)*
- **REQ-E1.6** The `tasks-pr-sync` hook and every fleet dispatcher SHALL
  locate the bundle through the resolver.
  *(Cites: D-2.)*
- **REQ-E1.7** The worker permission guard's sanctioned write zone SHALL
  include the resolved spec root when it lies in a different repository from
  the work repository or in none; the root is computed once by the
  dispatcher and handed to the guard through the settings it already reads.
  *(Cites: D-15; worker-permission-ergonomics REQ-A1.10.)*
- **REQ-E1.8** A holder repository MAY carry planwright's spec guards by the
  recipe the spec-location guide documents; `/builder` does not carry them,
  since they are project-bespoke extensions outside the guard catalog. In
  `plain` no guard runs, and the authoring handoff SHALL say so.
  *(Cites: D-16; kickoff §8 K9 (2026-09-22).)*
- **REQ-E1.9** In `separate-repo` and `plain`, a halting execution skill's
  Awaiting-input and Deferred writes SHALL land as uncommitted files in the
  store's primary view working tree, and the handoff SHALL name each such
  file; no execution skill SHALL commit, branch, or push in the holder on a
  halt. Authoring halts follow the authoring commit rules of D-12 and D-13.
  *(Cites: D-13; kickoff §3 REQ-E (2026-09-22).)*

## REQ-F — Observations across roots

- **REQ-F1.1** Every observation script (record, consume, render, carry, the
  store guard, and any later one) SHALL default its store to
  `_observations/` under the resolved root's checkout-local view. In `plain`
  the carry step, a git mechanism, SHALL be a no-op that says so.
  *(Cites: D-17.)*
- **REQ-F1.2** An `observation_targets` config option SHALL map aliases to
  roots, and `obs-record --target <alias>` SHALL write the fragment into the
  named root's accumulator after validating the alias grammar and that the
  target is, by shape, a marker-bearing root or the default root of a git
  checkout; the target checkout's own configuration is not consulted.
  *(Cites: D-18; legacy L79 (Sources); observation-recording D-9.)*
- **REQ-F1.3** Every write made with `--target` SHALL pass a hygiene screen
  matching three fixed pattern classes, an absolute path, a `~`-prefixed
  path, and a dotted hostname ending in a public suffix or in `.local` or
  `.internal`; a fragment matching any SHALL be refused with a message
  naming the screen, never rewritten, and nothing written. Whether a
  repository name the fragment carries is private is the consumer's read at
  consumption, not the writer's.
  *(Cites: D-18; bootstrap REQ-D1.6; kickoff §8 K4 (2026-09-22).)*
- **REQ-F1.4** No fragment SHALL be sent to a public surface without an
  explicit human act; the routing tests SHALL assert that no observation
  script invokes a remote write.
  *(Cites: D-18.)*
- **REQ-F1.5** Fragment identity and the duplicate-UID refusal SHALL hold per
  accumulator, and the carry mechanism SHALL work in the `separate-repo`
  posture.
  *(Cites: D-17.)*

## REQ-G — Guards and documentation

- **REQ-G1.1** A CI check SHALL flag every non-comment occurrence of the
  literal `specs/` used as a path in `scripts/`, `githooks/`, the `mise.toml`
  task bodies, `lefthook.yml`, `.gitignore`, and the CI workflows, outside
  the resolver; the allowlist is by line and admits exactly three classes:
  the resolver, the namespace literals REQ-D1.2 keeps, and a static glob
  whose limitation D-19 states.
  *(Cites: D-19; kickoff §8 K11 (2026-09-22).)*
- **REQ-G1.2** The spec checks `mise run check` runs SHALL obtain the root
  from the resolver in their task bodies, and the scoped lint relaxation the
  bundles rely on SHALL travel with the root.
  *(Cites: D-19.)*
- **REQ-G1.3** Every doc that states the spec home normatively (illustrative,
  not exhaustive: the options reference, the overlays guide, the conventions
  doc, getting-started, the README's index and layout, and a new
  spec-location guide) SHALL document the option, the marker, the posture
  ladder, the named targets, and the holder guard recipe.
  *(Cites: D-20.)*
- **REQ-G1.4** Every doctrine doc that states the spec home or the
  accumulator home normatively SHALL be amended in one task before any
  posture-dependent skill ships: `storage-classes` (the class-3 home as a
  location the human owns, the "committed" attribute scoped to the git
  postures, the posture ladder, the marker as class-1 config, and the
  class-2 interim note re-anchored on this bundle), `spec-format` (every
  `specs/` site, including the reserved-children list coordinated with the
  sibling specs that extend or amend it), `accumulator-taxonomy`,
  `orchestration-modes`, and the invocation example in
  `plugin-script-invocation`.
  *(Cites: D-1, D-20; kickoff §8 K3 (2026-09-22).)*

## REQ-H — Compatibility

- **REQ-H1.1** With every new option unset, a golden fixture SHALL record
  each migrated script's paths and messages before the migration, from both
  the primary checkout and a worktree of the fixture repository, and replay
  them after every migration task; a difference outside that task's declared
  expected-change set SHALL fail, and every named correction (REQ-A1.1)
  SHALL appear in exactly one task's set, so an unintended change and an
  intended one are told apart. The baseline is recorded once the resolver
  exists, so the option's presence in `config/defaults.yml` and the
  self-hosting pin are inside it and named as such; the pin's own assertion
  is REQ-C1.2's test.
  *(Cites: D-3; kickoff §3 REQ-H (2026-09-22); kickoff §8 K7 (2026-09-22).)*
- **REQ-H1.2** Existing bundles, kickoff briefs, and archived fragments SHALL
  stay valid without edits, their content anchors recorded in the fixture's
  baseline and unchanged after it; no migration step SHALL be required of an
  adopter who keeps the default.
  *(Cites: D-3, D-4.)*
- **REQ-H1.3** Every option this spec introduces SHALL ship dark: `spec_root`
  absent from `config/defaults.yml` (absent is unset; its options-reference
  row states the default), `observation_targets` empty.
  *(Cites: D-3; customization-boundary criterion 5.)*

## Changelog

- 2026-09-22 — Initial draft: bundle elicited from the invocation, the code
  map, and the observation fragments and legacy line listed under Sources,
  all consumed;
  scope widened during elicitation to the three roots and cross-repo
  observation targets; the work-repo mapping settled as pointer plus marker
  with the reverse registry deferred.
- 2026-09-22 — Kickoff sign-off (meaning-class, pre-merge, in place): the
  resolved-path definition of the default root (REQ-A1.4); the bad-value
  rule with empty as unset and refusal in every layer (REQ-A1.3); addressing
  scoped to skill arguments and identity seams (REQ-D1.1, REQ-D1.3);
  REQ-E1.9 minted for halt writes in a holder or plain store; posture by
  repository identity and the default-branch read surface (REQ-E1.1,
  REQ-E1.5); the hygiene screen's three pattern classes (REQ-F1.3); the
  expected-change-set fixture and the named corrections (REQ-A1.1,
  REQ-H1.1); the install-root chain shared by the guards with per-guard
  policy (REQ-C1.1); the doctrine amendments moved into their own task
  before the skill tasks (REQ-G1.4, Task 6.5); the marker renamed
  `planwright-spec-root.yml`; the primary view renamed from `--canonical` to
  `--primary`; enumerations converted to decided rules; citations repaired.
  Full ledger in `kickoff-brief.md` §8.

## Sources

- **The invocation** (2026-09-21): "make the spec location more flexible …
  custom locations inside or outside the repository; even another
  repository that holds multiple specs for other repos or projects …
  locations without git at all." Pinned altitude claims: the multi-project
  holder and the git-less store are both assertions about the deliverable's
  nature that collide with the `storage-classes` class-3 home, resolved in
  D-1.
- **The code map** (drafting-session research, 2026-09-21, corrected at
  kickoff 2026-09-22): a sweep of the scripts, hooks, skills, and docs for
  repo-root resolution and `specs/` literals. Findings: no shared repo-root
  helper and inline copies across the scripts disagreeing on worktree versus
  primary; the bundle-reading scripts take the spec directory as an
  argument, except the walkthrough script, which composes the path from an
  identifier; the unattended callers (the sync hook, the fleet dispatchers,
  the fetch script, the `mise.toml` task bodies) hardcode the path; some
  scripts assert the root's parent is named `specs` and some infer the
  checkout from it (REQ-A1.7 states the rule rather than the count); no
  existing config option takes an absolute or out-of-repo path (the release
  `version_file` knob is repo-relative and resolved by its own library; the
  fleet home and the adopter overlay root are out-of-repo locations but not
  config options), so `spec_root` is the first.
- **obs:4467db6b**, **obs:fd4c2ad6**, **obs:65fea955** — a worktree session
  loses the machine-local config layer because the repo root resolves to the
  worktree.
- **obs:de85a7f0** — worktree placement resolved against the process working
  directory.
- **obs:e64d26ff** — the existing path knob canonicalizes against the
  working directory while containing against the toplevel.
- **obs:e144633c** — the drain sweep's cost is almost entirely git
  evidence; a non-git tree sweeps in seconds (leaned on by D-13).
- **obs:16a87c48** — the dispatch scope grammar and its sibling seams
  disagree on spec path versus spec id.
- **obs:cf3fd0b5**, **obs:41b74b2c** — skills hardcode the observations
  path.
- **obs:4fe3d8a4**, **obs:945a1b04**, **obs:54e8035d** — self-hosted runs
  resolve the installed plugin instead of the checkout under test.
- **obs:c922e401** — an install-root arm resolved to a directory with no
  content and returned it at exit 0.
- **obs:92809aad**, **obs:0aaad2ef** — the two command guards resolve the
  trusted install root by divergent chains, the worker's carrying an
  installed-roots arm the tower's lacks.
- **Legacy L79** (`opportunities.md`, 2026-06-17): the accumulator is
  single-repo by construction; a planwright-about observation surfaced in a
  work repo never reaches planwright's log without a manual relocate. Its
  sub-problem (2) is delivered here; sub-problem (3) is out of scope;
  sub-problem (1) is deferred (see `tasks.md`).
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
  `storage-classes`, `decision-domains`, `accumulator-taxonomy`,
  `guard-catalog`.
