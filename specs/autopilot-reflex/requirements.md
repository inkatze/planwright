# Autopilot Reflex — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-02
**Format-version:** 1

## Goal

planwright ships a versioned artifact (`.claude-plugin/plugin.json`) yet
releases are cut manually: a human must remember to prompt for a
version bump and a git tag. For a framework whose north star is "the human
keeps the reserved controls; planwright flies the rest", a recurring manual
ceremony that fires only when a human remembers it is a doctrine gap, and the
drafting session that produced this bundle found the gap is deeper than
release tagging. The durable asset is not any one release mechanism; it is the
**thought process** that closes ceremony gaps of this shape: name the
irreducible human gates, automate up to them, verify the burden was eliminated
rather than relocated, surface by push or forcing-function rather than pull,
put each piece at its right altitude, and capture the reasoning so the next
gap does not need re-deriving.

This bundle establishes that thought process as core doctrine — the
**autopilot reflex** (`doctrine/autopilot-reflex.md`) — and proves it with two
independent instantiations. **Instantiation A (a runtime ceremony):**
automatic release tagging — automated detection and proposal of releases via a
conventional-commit release PR, a human merge as the approval gate, a
signer-agnostic publish step that cuts a signed annotated tag plus GitHub
Release, and a forcing-function lock on the untagged window — culminating in
planwright's own next release being cut through the machinery. **Instantiation
B (an authoring ceremony):** the doctrine-altitude gate wired into
`/spec-draft` and `/spec-kickoff`, closing the meta-gap this very session
exhibited (the invocation said "that's a doctrine gap" and the elicitation
still spent most of the session solutioning before circling back to the
doctrine). The bundle self-demonstrates: its altitude trigger fired during
drafting, so D-1 is the altitude record REQ-A1.4 demands.

## Scope

### In scope

- `doctrine/autopilot-reflex.md`: the six-step reflex, the altitude triggers,
  the phase re-anchor discipline, and the altitude-record (D-ID) artifact rule.
- A release-tagging policy doctrine note citing the reflex (detection
  automated, publish human-gated, signed when the repo signs, untagged window
  locked, merge and publish human-reserved).
- A portable, signer-agnostic publish script (annotated tag honoring the
  repo's git signing config + GitHub Release), a release-pending comparator,
  and the `require_signed_tags` / `version_file` config knobs.
- release-please in PR-only mode on planwright's own repo (conventional-commit
  detection, version bump of `plugin.json` via the release PR, `CHANGELOG.md`),
  plus an opt-in adopter template of the same.
- The untagged-window lock: a required CI check that blocks merges to `main`
  while a version bump lacks its tag; merge serialization (merge queue /
  require-up-to-date) on planwright's repo, documented opt-in for adopters.
- Surfacing: release-PR body instructions, `/orchestrate --bookkeeping`
  release-pending report, a `mise run release` wrapper on this repo.
- Adopter path via existing channels: a guard-catalog release-tagging breadth
  entry (with a detection facet: versioned artifact + no release automation →
  recommend) and a decision-domains versioning-scheme entry (SemVer/CalVer
  heuristics, planwright's SemVer call as the worked example).
- Instantiation B: `/spec-draft` seed-claim pinning + altitude triggers +
  phase re-anchor; `/spec-kickoff` lens-pass check of the altitude record.
- Signing prerequisites and enforcement on planwright's repo
  (`require_signed_tags: require`, tag-signing config, GitHub signing-key
  registration, a signed-tag verification step for our releases).
- Armed/watch mode for the publish flow, sequenced as a follow-up task inside
  this bundle (not a separate spec).
- The organic proof: planwright's own next release cut end-to-end through this
  machinery (human-gated by construction).

### Out of scope

- Auto-merge of anything, including the release PR. Merge remains an
  absolutely human act; no `/approve-release`-style merge-bearing command
  ships (considered and rejected, D-5). The carried hard invariant is intact,
  unrefined.
- Background auto-sign: any flow where the signer is pre-authorized and a
  release publishes without a conscious per-release human act.
- A dedicated CI signing key, sigstore/keyless signing, or any signing secret
  in CI. planwright's zero-CI-secrets posture is unchanged (D-4).
- CalVer for planwright (D-9 chooses SemVer; CalVer lives in the
  decision-domains entry as an alternative for other artifact types).
- The one-time private→public release gate (bootstrap REQ-J1.5, D-27,
  `scripts/release-checklist.sh`). Adjacent but distinct: that gate governs
  going public once; this bundle governs the recurring release loop. Nothing
  here modifies it.
- Multi-package / monorepo release orchestration.
- The plugin upgrade/ghost-file cleanup story (a bootstrap packaging concern;
  fold-detection adjacency only).
- Retrofitting the altitude gate into skills beyond `/spec-draft` and
  `/spec-kickoff`'s lens pass.
- An LLM `/release` skill. The publish step is judgment-free and ships as a
  mechanical script (D-8); a thin skill wrapper is deferred unless usage
  demands it.

## REQ-A — The autopilot-reflex doctrine

- **REQ-A1.1** A core doctrine doc `doctrine/autopilot-reflex.md` SHALL exist
  defining the six-step reflex for closing recurring-manual-ceremony gaps:
  (1) name the irreducible human gates first (judgment calls and
  reserved/irreversible/external acts stay human and conscious); (2) automate
  up to the gates, never through them; (3) verify the burden was eliminated,
  not relocated (a step a human must remember to initiate is not closed);
  (4) surface by push or forcing-function, never by pull; (5) right-altitude
  the solution (impulse/doctrine vs capability vs mechanism vs local value,
  preferring mechanical tools over LLM judgment where no judgment exists);
  (6) capture the reasoning as the reusable asset.
  *(Cites: D-1, D-2; drafting-session decision (2026-07-01).)*
- **REQ-A1.2** The doctrine SHALL define **altitude triggers**: explicit seed
  or invocation claims about the deliverable's nature (e.g. "doctrine gap",
  "first-class concern", "we keep doing X manually") and mid-flow signals
  (recurring capability-vs-style calls, "is this even core?" moments). When a
  trigger fires during spec work, the deliverable's altitude MUST be resolved
  before proceeding to solution design.
  *(Cites: D-11.)*
- **REQ-A1.3** The doctrine SHALL define the **phase re-anchor**: each
  phase-end running summary during drafting restates the claimed altitude and
  flags drift between it and what the elicitation is currently producing.
  *(Cites: D-11.)*
- **REQ-A1.4** When an altitude trigger has fired, the resulting bundle MUST
  record the altitude call as an early design decision (an altitude D-ID)
  cited from its goal. When no trigger fired, no record is required
  (proportionality).
  *(Cites: D-11; proportionality doctrine.)*
- **REQ-A1.5** The doctrine SHALL resolve through the standard rule-doc
  resolution chain and be linked from the doctrine index so the repo's
  link-check covers it.
  *(Cites: D-2.)*

## REQ-B — Release-tagging policy (instantiation A, doctrine layer)

- **REQ-B1.1** A release-tagging policy doctrine note SHALL exist, citing
  `autopilot-reflex`, stating: release detection and proposal are automated;
  release approval is a human merge; the publish (tag + Release) is
  human-gated and signed when the repo signs; the untagged window is locked by
  forcing-function; merge and publish are never performed autonomously.
  *(Cites: D-2, D-3, D-5, D-7.)*
- **REQ-B1.2** The policy SHALL separate the three altitudes explicitly: the
  **capability** (publish script, comparator, doctrine) is core; the
  **mechanism** (release-please config, lock workflow, merge queue) is
  per-repo and template-shipped opt-in; the **value** (require signing, the
  version file, the scheme) is configuration.
  *(Cites: D-13; customization-boundary doctrine.)*

## REQ-C — Release detection & proposal

- **REQ-C1.1** On planwright's repo, releasable changes SHALL be detected from
  conventional commits on `main` and proposed as an automatically maintained
  release PR (release-please in PR-only mode) that bumps the version source of
  truth and updates `CHANGELOG.md`. Editing the PR corrects the proposal;
  closing it cancels; no human initiation is required for the proposal to
  exist.
  *(Cites: D-3.)*
- **REQ-C1.2** The version source of truth SHALL be `.claude-plugin/plugin.json`
  `version`, versioned by SemVer; the release PR SHALL be its only automated
  writer.
  *(Cites: D-9; drafting-session decision (2026-06-30).)*
- **REQ-C1.3** CI automation SHALL NOT create tags or GitHub Releases. The
  release PR is proposal only; tagging happens exclusively through the publish
  step (REQ-D).
  *(Cites: D-3, D-4.)*
- **REQ-C1.4** Merging the release PR SHALL be the release approval and SHALL
  remain a human act. No planwright code path merges the release PR (the
  carried never-auto-merge invariant, unrefined).
  *(Cites: D-5; bootstrap REQ-J1.1-class invariant.)*
- **REQ-C1.5** Release notes SHALL derive from merged PRs since the last
  release, grouped by conventional-commit type, enriched with spec/task
  references where PR bodies already carry them. Spec bundles SHALL NOT be a
  hard dependency of note generation.
  *(Cites: D-10.)*

## REQ-D — Signed publish

- **REQ-D1.1** A portable publish script (`scripts/release-publish.sh`) SHALL
  create the annotated release tag and the GitHub Release for an approved
  (merged) release proposal. It SHALL be signer-agnostic: signing is delegated
  entirely to the repo's git configuration (`gpg.format`, `gpg.ssh.program`,
  `user.signingkey`), never to a named signer in script logic.
  *(Cites: D-4, D-8.)*
- **REQ-D1.2** The script SHALL tag the observed release-merge commit SHA —
  the commit where the version bump landed on `main` — never the current
  HEAD. The target version SHALL be read from the version file in that
  commit's tree, never from the working tree or current HEAD.
  *(Cites: D-6; kickoff lens pass (2026-07-02).)*
- **REQ-D1.3** Before creating anything, the script SHALL enforce all safety
  gates and refuse without side effects if any fails: the target tag does not
  exist locally or on `origin` (idempotency); the target version is strictly
  greater than the latest release tag (monotonicity; with no existing release
  tags the gate passes vacuously — the first release); the working tree is
  clean; local `main` is synced with `origin/main`; GitHub CI is green on the
  release SHA, verified against the real external state via `gh`, not a local
  claim. Exception to the idempotency gate: when the target tag is already
  pushed but its GitHub Release is absent (a partial publish), the script
  SHALL resume by creating the Release (REQ-D1.7) rather than refuse.
  *(Cites: D-6, D-8; drafting-session decision (2026-06-30); kickoff lens
  pass (2026-07-02).)*
- **REQ-D1.4** A `require_signed_tags` config knob SHALL govern signing
  policy: `auto` (default — sign when the repo has signing configured,
  otherwise create an annotated unsigned tag with a warning), `require`
  (refuse to tag unless signing is configured and succeeds), `never` (always
  unsigned annotated). planwright's own repo SHALL set `require`.
  *(Cites: D-4.)*
- **REQ-D1.5** When a tag is signed, the script SHALL verify the signature
  (`git tag -v`) before pushing it.
  *(Cites: D-4.)*
- **REQ-D1.6** A `version_file` config knob (file path plus selector,
  defaulting to `.claude-plugin/plugin.json` / `$.version`) SHALL parameterize
  where the version of truth lives, so the script ports to repos versioning
  `package.json`, `mix.exs`-style files, or a plain `VERSION` file.
  *(Cites: D-13.)*
- **REQ-D1.7** The GitHub Release SHALL be created from the released version's
  `CHANGELOG.md` section and attached to the already-pushed tag
  (`gh release create --verify-tag`), never to a tag `gh` creates itself.
  *(Cites: D-10.)*
- **REQ-D1.8** A release-pending comparator script SHALL exist (version of
  truth vs latest release tag → pending/none), reusable by the bookkeeping
  surface and the untagged-window lock so both read one definition of
  "pending".
  *(Cites: D-7, D-8.)*
- **REQ-D1.9** Both scripts SHALL follow the repo's portability conventions
  (bash 3.2 / BSD tooling, `LC_ALL=C`, `unset CDPATH`, no fish/mise/tmux
  dependency) and carry unit tests run by the repo's aggregate check.
  *(Cites: bootstrap REQ-K1.5 (portability conventions); D-8.)*

## REQ-E — Untagged-window lock & race safety

- **REQ-E1.1** A required CI check SHALL fail on `main` and on PRs targeting
  `main` while the version of truth is ahead of the latest release tag (the
  untagged window), so that after a release PR merges, no further merge can
  land until the tag is published. The block message SHALL name the publish
  command.
  *(Cites: D-7.)*
- **REQ-E1.2** Outside the untagged window the check SHALL pass; ordinary PRs
  that do not bump the version never trip it.
  *(Cites: D-7.)*
- **REQ-E1.3** planwright's repo SHALL serialize merges (GitHub merge queue,
  with require-branches-up-to-date as the minimum fallback) so a concurrent
  merge cannot land against a stale pre-bump base. For adopters this is
  documented guidance and opt-in, scaled to their merge concurrency.
  *(Cites: D-7; proportionality doctrine.)*
- **REQ-E1.4** Publish correctness SHALL NOT depend on the lock: REQ-D1.2 +
  REQ-D1.3 alone guarantee the tag lands on the true release commit under any
  merge interleaving. The lock exists to close the forget-window, not to make
  tagging correct.
  *(Cites: D-6, D-7.)*

## REQ-F — Surfacing & ergonomics

- **REQ-F1.1** The release PR body SHALL state the full flow ("merging
  approves release X.Y.Z; then run `<publish command>` to sign and publish
  the tag") and carry the notes preview, so approval and publish read as one
  adjacent act.
  *(Cites: D-3, D-7.)*
- **REQ-F1.2** `/orchestrate --bookkeeping` SHALL report a pending release
  (via the REQ-D1.8 comparator) as a belt-and-suspenders surface; the primary
  mechanisms remain the PR body (push) and the lock (forcing-function).
  *(Cites: D-7, D-8.)*
- **REQ-F1.3** planwright's repo SHALL wrap the publish script in a
  `mise run release` task (repo-local ergonomics only; the script itself has
  no mise dependency per REQ-D1.9).
  *(Cites: D-8.)*

## REQ-G — Adopter path (builder & catalogs)

- **REQ-G1.1** The guard catalog SHALL gain a release-tagging breadth entry
  with a detection facet (the repo ships a versioned artifact and has no
  release automation → recommend the guard) and a scaffold facet (release-PR
  mechanism template, untagged-window lock template, publish-script wiring).
  Recommendations are advisory; nothing is applied without the builder's
  existing consent flow.
  *(Cites: D-13.)*
- **REQ-G1.2** The decision-domains catalog SHALL gain a **versioning scheme**
  domain: the SemVer / CalVer / unversioned alternatives with artifact-type
  heuristics (compatibility-signaling artifacts → SemVer;
  continuously-shipped applications → CalVer), carrying planwright's own
  SemVer call (D-9) as the worked example.
  *(Cites: D-9, D-13.)*
- **REQ-G1.3** The adopter-facing mechanism templates SHALL ship in an opt-in
  location resolved by the builder, never auto-landing in an adopter repo.
  *(Cites: D-13; customization-boundary doctrine.)*

## REQ-H — Authoring altitude gate (instantiation B)

- **REQ-H1.1** `/spec-draft` SHALL pin seed claims during seed gathering:
  explicit statements about the deliverable's nature found in the invocation
  or seeds are extracted as anchors the elicitation must reconcile against,
  and an altitude trigger firing SHALL force the altitude resolution before
  the design phase begins. Pinned claims SHALL be recorded in the bundle's
  `## Sources` entries, so the REQ-H1.3 kickoff check is bundle-local rather
  than dependent on drafting-session memory.
  *(Cites: D-11; drafting-session decision (2026-07-01); kickoff §3 REQ-A
  (2026-07-02).)*
- **REQ-H1.2** `/spec-draft`'s phase-end running summaries SHALL restate the
  claimed altitude and flag drift (the re-anchor of REQ-A1.3).
  *(Cites: D-11.)*
- **REQ-H1.3** `/spec-kickoff`'s Discovery-Rigor lens pass SHALL verify, for a
  bundle whose drafting fired an altitude trigger, that the altitude D-ID
  exists, is cited from the goal, and that the task decomposition matches the
  claimed altitude (a doctrine-first bundle whose tasks are all mechanism is a
  finding).
  *(Cites: D-11.)*

## REQ-I — Organic proof

- **REQ-I1.1** planwright's own next release SHALL be cut end-to-end through
  this machinery — release PR proposed automatically, human merge as approval,
  publish script producing a signed annotated tag (verifiable by
  `git tag -v`) and a GitHub Release on the observed merge SHA. This is an
  organic, human-gated acceptance step: the framework prepares and verifies;
  the human merges and signs.
  *(Cites: D-1, D-3, D-4, D-5; drafting-session decision (2026-06-30).)*
- **REQ-I1.2** This bundle SHALL itself carry the altitude record (D-1) cited
  from its Goal, demonstrating REQ-A1.4 on the very session that authored the
  rule.
  *(Cites: D-1, D-11.)*

## Changelog

- 2026-07-01 — Initial draft (spec-draft session, 2026-06-30 → 2026-07-01).
- 2026-07-02 — Kickoff walkthrough + lens-pass edits (in place; Draft):
  Goal version staleness un-pinned; REQ-H1.1 pins seed claims in Sources;
  REQ-D1.2 version read from the release-merge commit's tree; REQ-D1.3
  first-release base case + partial-publish resume exception; T3 names the
  catalog yaml machine views; T4 cites security-posture input validation;
  T8/REQ-H1.3 altitude check clarified kickoff-local; test-spec: first-release
  and partial-publish fixtures, H1.3 positive case, six verification moments
  moved from "kickoff walkthrough" to task-PR review. See
  `kickoff-brief.md` §3/§8 for the consolidated list.
- 2026-07-02 — Panel-pairing corrections (delta re-walkthrough, pre-approved;
  expression-only): Task 5 now cites REQ-C1.4 so the "merge is human / no
  merge call sites" requirement has a task owner (every pinned REQ is now
  cited by ≥1 task); `kickoff-brief.md` §4 cross-check reworded to document
  D-12 (armed mode, cited by Task 10 / verified by T10's Done-when) as the
  sole task-only D-ID; §5 coverage count corrected 30 → 36. See
  `kickoff-brief.md` §9 amendment log.
- 2026-07-02 — Self-review corrections (delta re-walkthrough, pre-approved;
  expression-only): `design.md` D-2 qualifies the foreign ref as
  `bootstrap D-21`; `design.md` D-9 rewords the `0.1.0` mentions to read as
  the version-lineage origin, not a current-version claim; `test-spec.md`
  REQ-E1.3 verification moment corrected to "T6 (settings land), observed
  live at T11"; `kickoff-brief.md` §5 `[test]` sub-count corrected 17 → 18;
  `kickoff-brief.md` §2 stale "0.2.2 / v0.2.1" figure reconciled to the
  verified v0.2.6. See `kickoff-brief.md` §9 amendment log.

## Sources

- **The `/spec-draft` invocation seed (2026-06-30).** The motivation framing
  ("planwright HAS a version but releases are tagged MANUALLY… that's a
  doctrine gap"), the probe areas (trigger conditions, version source, tag
  convention, notes, idempotency/safety, doctrine placement), and the
  fold-awareness instruction. The "doctrine gap" claim is the altitude trigger
  this bundle's D-1 records.
- **Comparative research: a sibling repo in the author's fleet (Elixir,
  release-please, CalVer; examined 2026-06-30).** Its `release.yml`
  (release-please on `workflow_run` after CI), release-PR approval UX, and the
  verified finding that release-please's tags are lightweight and unsigned
  (`git cat-file -t` → `commit`; the release commit is signed by GitHub's
  web-flow key, not the author's) — the finding that motivated splitting
  detection (CI) from signed publish (local, D-4).
- **The `bootstrap` spec bundle (`specs/bootstrap/`).** Adjacency only: the
  one-time private→public release gate (`bootstrap REQ-J1.5`, `bootstrap
  D-27`, `scripts/release-checklist.sh`) is a distinct, unchanged concern;
  this bundle's recurring loop begins after it. Also the portability
  conventions (`bootstrap REQ-K1.5`) REQ-D1.9 carries.
- **The `customization-boundary` and `proportionality` doctrines.** Govern the
  capability/mechanism/value split (REQ-B1.2, D-13) and the
  trigger-scoped-record rule (REQ-A1.4).
- **drafting-session decisions (2026-06-30 and 2026-07-01).** The fork
  resolutions made live in this session and minted as D-1 through D-13,
  including the doctrine-first reframe, the rejection of a merge-bearing
  command, and the altitude-gate design.
