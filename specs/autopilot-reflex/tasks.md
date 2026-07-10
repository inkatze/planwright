# Autopilot Reflex — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-02
**Format-version:** 1

Dependency levels (the `Dependencies:` lines below are the source of truth):

- Level 0: T1
- Level 1: T2 (←T1), T8 (←T1)
- Level 2: T3 (←T2), T4 (←T2), T5 (←T2)
- Level 3: T6 (←T4, T5), T7 (←T4, T5), T9 (←T4)
- Level 4: T10 (←T4, T6), T11 (←T5, T6, T7, T9)

Critical path: T1 → T2 → T4 → T6 → T10 (5.5d). The organic proof T11's longest
chain is T1 → T2 → T4 → T6 → T11 (4.75d). T8 (instantiation B) is independent
of the release chain after T1 and can run in parallel throughout.

## Forward plan

### Task 1 — `doctrine/autopilot-reflex.md`

- **Deliverables:** The core doctrine doc: the six-step reflex (name the
  irreducible human gates; automate up to them; eliminated-not-relocated;
  push/forcing-function never pull; right-altitude
  impulse/capability/mechanism/value; reasoning-is-the-asset), the altitude
  triggers (seed claims + mid-flow signals), the phase re-anchor discipline,
  and the trigger-scoped altitude-D-ID rule. Linked from the doctrine index;
  resolvable via the rule-doc chain.
- **Done when:** The doc exists with all six steps, the trigger and re-anchor
  definitions, and the D-ID rule; `scripts/resolve-rule-doc.sh
  autopilot-reflex` resolves it; the doctrine link-check passes.
- **Dependencies:** none.
- **Citations:** D-1, D-2, D-11 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5
- **Estimated effort:** 1.0d
- **Last activity:** 2026-07-09

### Task 2 — Release-tagging policy doctrine note

- **Deliverables:** `doctrine/release-tagging.md` citing `autopilot-reflex`:
  detection/proposal automated; approval = human merge of the release PR;
  publish human-gated and signed per repo policy; untagged window locked;
  merge and publish never autonomous. Explicit capability / mechanism / value
  altitude table (REQ-B1.2). Linked from the doctrine index.
- **Done when:** The doc exists, cites `autopilot-reflex` and
  `customization-boundary`, states the five policy points and the altitude
  split; link-check passes.
- **Dependencies:** Task 1.
- **Citations:** D-2, D-3, D-5, D-7, D-13 · REQ-B1.1, REQ-B1.2
- **Estimated effort:** 0.5d
- **Last activity:** 2026-07-09

### Task 3 — Catalog entries: guard-catalog + decision-domains

- **Deliverables:** (a) A release-tagging breadth entry in
  `doctrine/guard-catalog.md` and its machine view
  `config/guard-catalog.yaml`: detection facet (versioned artifact + no
  release automation → recommend) and scaffold facet (release-PR mechanism
  template, lock workflow template, publish-script wiring), advisory-only per
  the builder's consent flow. (b) A versioning-scheme domain in
  `doctrine/decision-domains.md` and its machine view
  `config/decision-domains.yaml`: SemVer / CalVer / unversioned with
  artifact-type heuristics, planwright's D-9 SemVer call as the worked
  example.
- **Done when:** Both catalog entries exist with the facets/heuristics named;
  the builder skill's catalog walk and `/spec-draft`'s decision-domains walk
  pick them up without wiring changes; link-check passes.
- **Dependencies:** Task 2.
- **Citations:** D-9, D-13 · REQ-G1.1, REQ-G1.2, REQ-G1.3
- **Estimated effort:** 0.5d

### Task 4 — Publish + comparator scripts, config knobs, tests

- **Deliverables:** `scripts/release-publish.sh` (signer-agnostic annotated
  tag honoring repo git config; tags the observed release-merge SHA; safety
  gates: tag-absent both sides, monotonic version, clean tree, synced main,
  GitHub CI green on the SHA via `gh`; `git tag -v` before push when signed;
  `gh release create --verify-tag` from the CHANGELOG section) and
  `scripts/release-pending.sh` (version-of-truth vs latest release tag).
  `require_signed_tags` (default `auto`) and `version_file` (default
  `.claude-plugin/plugin.json` / `$.version`) knobs in `config/defaults.yml`
  with `docs/options-reference.md` rows. Unit tests (fixture repos with a
  throwaway SSH signing key — no 1Password dependency in tests) wired into
  `mise run check`. Repo portability conventions (bash 3.2, `LC_ALL=C`,
  `unset CDPATH`). Input validation per `security-posture`'s
  framework-script rules: version strings validated against the SemVer
  grammar before any use; the `version_file` selector treated as data, never
  executed.
- **Done when:** Every safety gate has a failing-fixture test; the three
  signing modes are each exercised; the SHA-selection race fixture (extra
  commit after the release merge) tags the merge SHA; options-reference drift
  check passes; `mise run check` green.
- **Dependencies:** Task 2.
- **Citations:** D-4, D-6, D-8, D-13 · REQ-D1.1, REQ-D1.2, REQ-D1.3,
  REQ-D1.4, REQ-D1.5, REQ-D1.6, REQ-D1.7, REQ-D1.8, REQ-D1.9, REQ-E1.4
- **Estimated effort:** 2.0d
- **Last activity:** 2026-07-09

### Task 5 — release-please PR-only config on this repo + adopter template

- **Deliverables:** release-please configured PR-only for planwright's repo
  (pinned action or CLI; config + manifest targeting `plugin.json` via
  JSON-path; CHANGELOG path; gated on CI success on `main`), with the
  release-PR body carrying the merge-then-publish instructions (REQ-F1.1).
  Verified: no tag/Release is ever created by CI. The same config packaged as
  the opt-in adopter template the guard catalog's scaffold facet references.
- **Done when:** A conventional-commit landing on `main` yields/updates a
  release PR bumping `plugin.json` and CHANGELOG with the instruction body;
  no CI-created tag exists after a test cycle; the template ships in the
  opt-in location.
- **Dependencies:** Task 2.
- **Citations:** D-3, D-10, D-13 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-C1.5, REQ-F1.1, REQ-G1.3
- **Estimated effort:** 1.0d

### Task 6 — Untagged-window lock + merge serialization

- **Deliverables:** A required CI check (reusing `release-pending.sh`) that
  fails on `main` and PRs while the version of truth is ahead of the latest
  release tag, naming the publish command in its failure output; branch
  protection updated (required check + merge queue, require-up-to-date as
  minimum) on planwright's repo; adopter guidance documenting the lock and
  when a merge queue is proportionate. Opt-in workflow template for
  adopters.
- **Done when:** The check's logic has unit tests (in-window fails with the
  command named, out-of-window passes, non-bump PRs unaffected); repo branch
  protection shows the check required and the queue enabled; guidance and
  template shipped.
- **Dependencies:** Task 4, Task 5.
- **Citations:** D-7 · REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 1.0d

### Task 7 — Bookkeeping surfacing + mise wrapper

- **Deliverables:** `/orchestrate --bookkeeping` reports a pending release
  via `release-pending.sh` (belt-and-suspenders); a `mise run release` task
  wrapping the publish script on this repo.
- **Done when:** A bookkeeping run in the untagged window reports the pending
  version and publish command; `mise run release` invokes the script; outside
  the window bookkeeping stays silent on releases.
- **Dependencies:** Task 4, Task 5.
- **Citations:** D-7, D-8 · REQ-F1.2, REQ-F1.3
- **Estimated effort:** 0.5d

### Task 8 — Altitude gate in `/spec-draft` + `/spec-kickoff` lens check

- **Deliverables:** `/spec-draft`: seed-claim pinning in seed gathering
  (explicit deliverable-nature claims extracted as anchors), the altitude
  trigger firing rule (resolve altitude before the design phase), and the
  phase-end re-anchor line in the running-summary convention.
  `/spec-kickoff`: the lens pass checks a triggered bundle for the altitude
  D-ID, its goal citation, and task-decomposition match. Both cite
  `doctrine/autopilot-reflex.md` rather than restating it.
- **Done when:** Both skill docs carry the wiring with doctrine citations; a
  fixture/manual drafting exercise with a trigger phrase produces the altitude
  resolution before design and the re-anchor lines in summaries; kickoff's
  lens-pass instructions name the altitude check as a kickoff-specific check
  item (the canonical lens list in `discovery-rigor` is untouched).
- **Dependencies:** Task 1.
- **Citations:** D-11 · REQ-H1.1, REQ-H1.2, REQ-H1.3
- **Estimated effort:** 1.0d

### Task 9 — Signing prerequisites & enforcement on this repo + docs

- **Deliverables:** `require_signed_tags: require` in this repo's planwright
  config layer; tag-signing wired (config or explicit `-s` — verified
  end-to-end once with `git tag -v`); the author's SSH key registered as a
  GitHub *signing* key so tags render Verified (documented as a manual
  prerequisite); the worker-settings push-deny globs audited to confirm
  release-tag pushes (`refs/tags/v*`) by the human path are not blocked while
  branch protections stay intact; docs updates (getting-started /
  conventions: the release flow, the publish command, the signing policy).
- **Done when:** A dry-run signed tag on a scratch ref verifies locally and
  renders Verified on GitHub; the deny-glob audit is recorded; docs describe
  the end-to-end flow; options-reference rows for the repo's `require` value
  present.
- **Dependencies:** Task 4.
- **Citations:** D-4 · REQ-D1.4, REQ-D1.5
- **Estimated effort:** 0.5d

### Task 10 — Armed/watch mode (sequenced follow-up)

- **Deliverables:** An armed mode for the publish flow: invoked before the
  merge, it pre-validates everything pre-validatable (CI on the PR head,
  monotonicity, no existing tag, clean state), watches the release PR, and on
  observing the merge runs the publish immediately (minimizing the locked
  window to merge-to-sign). Refuses to arm when pre-validation fails.
- **Done when:** Armed against a fixture/real release PR, the publish fires
  on merge with the tag on the observed merge SHA; a failed pre-validation
  refuses to arm with the reason; post-merge mode remains the unchanged
  fallback.
- **Dependencies:** Task 4, Task 6.
- **Citations:** D-12 · REQ-D1.2, REQ-D1.3
- **Estimated effort:** 1.0d

### Task 11 — Organic proof: planwright's first automated signed release

- **Deliverables:** planwright's next release cut end-to-end through the
  machinery: the release PR proposed automatically, the human merges it, the
  publish produces the signed annotated tag on the observed merge SHA and the
  GitHub Release from the CHANGELOG section; the lock observed red in the
  window and green after. Human-gated organic acceptance: the framework
  prepares and verifies; the human merges and signs.
- **Done when:** `git tag -v` verifies the published release tag; the GitHub
  Release exists with the CHANGELOG-section body; the tagged SHA is the
  release-merge SHA; `release-pending.sh` reports none; the required check is
  green on `main`.
- **Dependencies:** Task 5, Task 6, Task 7, Task 9.
- **Citations:** D-1, D-3, D-4, D-5, D-6 · REQ-I1.1, REQ-I1.2
- **Estimated effort:** 0.25d

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

- Auto-merge of anything including the release PR; background auto-sign;
  CI-held signing keys (see requirements Out of scope).
- A `/release` LLM skill (thin wrapper deferred unless usage demands it,
  D-8).
- The one-time private→public release gate (bootstrap T19 /
  `scripts/release-checklist.sh`) — adjacent, unchanged.
- Multi-package release orchestration; CalVer for planwright; the altitude
  gate beyond `/spec-draft` + `/spec-kickoff`.
