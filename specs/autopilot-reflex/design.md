# Autopilot Reflex — Design

**Status:** Draft
**Last reviewed:** 2026-07-01
**Format-version:** 1

Origin-tag legend: `N` new decision. Foreign decision IDs are
namespace-qualified (`bootstrap D-27`).

## Decision log

### D-1: Deliverable altitude — doctrine-first, machinery as proof  (N)

**Decision:** This bundle's primary deliverable is doctrine (the autopilot
reflex, REQ-A), with the release-tagging machinery (REQ-C through REQ-G) and
the authoring altitude gate (REQ-H) as the two instantiations that prove it.
This is the bundle's altitude record per REQ-A1.4: the invocation's "that's a
doctrine gap" claim was the trigger.

**Alternatives considered:**
- A mechanism-first spec titled `release-tagging`, with the doctrine as a
  side-note. Rejected because: the concrete release solution turned out to be
  mostly repo-local configuration around an external tool (D-3, D-8, D-13);
  the durable, reusable asset is the thought process that shaped it. Shipping
  the mechanism without the doctrine would repeat the exact under-capture the
  seed named.
- Two separate specs (doctrine now, release machinery later). Rejected
  because: planwright's ethos is doctrine proven by a clean run, never loose
  prose; the doctrine should land with the instantiations that demonstrate it.

**Chosen because:** the seed said "capture this framing — it's the point", and
the drafting session validated it: every load-bearing design choice below is
an application of a reflex step, and the reflex generalizes to the next
ceremony gap while the release mechanics do not.

### D-2: The reflex is its own doctrine doc  (N)

**Decision:** Author the six-step reflex as a standalone
`doctrine/autopilot-reflex.md`, linked from the doctrine index, resolved via
the standard rule-doc chain; the release-tagging policy note cites it.

**Alternatives considered:**
- Extend `proportionality.md` or `engineering-decisions.md` with a section.
  Rejected because: the reflex is independently ownable (D-21-style spin-out
  test), spans authoring and runtime ceremonies, and will be cited by skills
  (`/spec-draft`, `/spec-kickoff`) and catalogs on its own.
- Its own separate spec with release tagging downstream. Rejected in D-1.

**Chosen because:** one concept, one doc, one resolution path — the same shape
every other planwright rule doc follows; consumers cite it without importing a
larger doc's unrelated content.

### D-3: Detection & proposal via release-please in PR-only mode  (N)

**Decision:** On planwright's repo, a CI workflow runs release-please in
PR-only mode: it computes the next SemVer from conventional commits, maintains
a release PR that bumps `.claude-plugin/plugin.json` `version` (JSON-path
extra-file) and updates `CHANGELOG.md` plus its manifest. It never creates
tags or GitHub Releases; the exact PR-only invocation is pinned at
implementation (the action's PR-only path, falling back to the
`release-please release-pr` CLI if the pinned action version lacks it).

**Alternatives considered:**
- A bespoke planwright detection script (conventional-commit walk + bump
  proposal). Rejected because: it re-implements a mature, fleet-proven tool;
  the reflex's step 5 prefers delegating mechanism to the substrate that
  already owns it.
- Compute the bump in-session at publish time (no standing PR). Rejected
  because: it relocates the burden — nothing accrues or surfaces until a human
  initiates (reflex step 3), and there is no reviewable, correctable proposal
  artifact.
- Trigger on a spec flipping Done. Rejected because: not every completed spec
  warrants a release, and adopters without a full spec habit would get no
  releases at all.
- Full release-please (let it tag and create Releases on merge). Rejected
  because: its tags are lightweight and unsigned — verified on a fleet repo
  (`git cat-file -t <tag>` → `commit`; only GitHub's web-flow key signs the
  release commit) — which fails the signed-tag requirement (D-4).

**Chosen because:** proven in the author's fleet; conventional commits are the
reliable spine planwright's commit lint already enforces; the release PR is
simultaneously the detection surface, the correction surface (edit), the
cancellation surface (close), and the approval gate (merge) — four needs, one
standing artifact, zero human initiation.

### D-4: Signing delegated to git config; signer-agnostic; policy knob  (N)

**Decision:** The publish script signs via `git tag -s`, delegating entirely
to the repo's git signing configuration; it never names a signer. A
`require_signed_tags` knob (`auto` default / `require` / `never`) governs
policy; planwright's own repo sets `require` (its config: SSH signing via
1Password's `op-ssh-sign`, the same key that signs commits). Signed tags are
verified (`git tag -v`) before push. No signing material ever enters CI.

**Alternatives considered:**
- Hardcode the author's signer (op-ssh-sign) in the flow. Rejected because:
  that is a local **value**, not the capability (reflex step 5 /
  customization-boundary); adopters without 1Password would fork the script.
- A dedicated release signing key in GitHub Actions secrets for end-to-end CI
  signing. Rejected because: it breaks the repo's zero-CI-secrets posture,
  adds key-management surface, and the tag would be signed by a bot identity,
  not the author.
- Sigstore/gitsign keyless signing in CI. Rejected because: it signs as the
  workflow's OIDC identity, verification needs cosign rather than
  `git tag -v`, and it is still not the author's key.
- Match the fleet repo: unsigned lightweight tags, GitHub-signed release
  commit. Rejected because: the human explicitly requires genuinely signed
  annotated tags, verifiable with stock git.

**Chosen because:** an interactive, vault-held signer physically cannot run on
a hosted runner, so the signing act is local by nature; delegating to git
config makes the script portable to GPG, plain SSH keys, agent-held keys, or
no signing at all, while the knob lets planwright's repo enforce the strict
value. The per-release biometric tap doubles as the conscious human gate on
the irreversible publish (reflex step 1).

### D-5: The framework never merges; the human merges the release PR  (N)

**Decision:** Release approval is the human merging the release PR in
GitHub's UI. No planwright command, script, or skill merges it — the carried
never-auto-merge invariant stays absolute and unrefined. The publish step
only *reacts* to an observed merge.

**Alternatives considered:**
- An `/approve-release` command that merges on explicit in-session
  confirmation, guarded as human-only. Seriously explored; rejected because:
  it softens a bright-line invariant ("no code path merges, ever") into a
  guarded one ("no autonomous merge"), trading auditability for convenience —
  and the same no-gap outcome is achievable by lock + armed mode without
  touching the invariant.
- Fully automatic publish once guardrails pass (no human act at all).
  Rejected because: it removes the human gate from an irreversible external
  publish, violating reflex step 1 and the framework's reserved-controls
  model.

**Chosen because:** merge-as-approval reuses the one gate the human already
exercises everywhere else in planwright; keeping the invariant bright-line
means its enforcement stays trivially checkable (no merge call sites exist).

### D-6: Tag the observed release-merge SHA, never HEAD  (N)

**Decision:** The publish script resolves the commit where the release PR's
version bump landed on `main` (the observed merge SHA) and tags exactly that
commit, refusing if it cannot identify it unambiguously.

**Alternatives considered:**
- Tag current `origin/main` HEAD at publish time. Rejected because: a feature
  PR landing between merge and publish would be silently swept into the
  release, and the tag would not point at the commit whose tree carries the
  released version.

**Chosen because:** it makes the publish correct under any merge interleaving,
independent of the lock (REQ-E1.4) — correctness by construction, with the
lock as ergonomics rather than a correctness dependency.

### D-7: Lock the untagged window; push and forcing-function, never pull  (N)

**Decision:** Surfacing is layered per reflex step 4: (push) the release PR
itself is the standing notification and its body carries the
merge-then-publish instructions; (forcing-function) a required CI check fails
while `main` carries a version bump with no matching tag, blocking all
further merges until the publish runs; (serialization) planwright's repo
enables the GitHub merge queue (require-up-to-date as minimum) so concurrent
merges cannot race the release PR; (belt-and-suspenders) `/orchestrate
--bookkeeping` reports pending releases via the shared comparator.

**Alternatives considered:**
- Rely on the bookkeeping sweep alone. Rejected because: it is pull — the
  human must remember to run it, which relocates the original burden (the
  exact failure the human caught during drafting).
- A CI check on the release PR itself requiring the tag to exist. Rejected
  because: unsolvable chicken-and-egg — the signed tag can only exist after
  the bump lands, so the release PR could never merge.
- Mandatory merge queue for all adopters. Rejected because: disproportionate
  for low-concurrency repos; the check + require-up-to-date already closes
  the common case (proportionality).

**Chosen because:** after a release merges, the red required check makes
"publish the tag" the only path forward — forgetting is structurally
impossible rather than merely discouraged; the merge queue fits this repo's
real concurrent-tower merge pattern.

### D-8: The publish is a mechanical script, not an LLM skill  (N)

**Decision:** Ship the publish as `scripts/release-publish.sh` plus a
`release-pending` comparator — deterministic, tested shell in the repo's
portable-bash conventions — wrapped by `mise run release` on this repo and
invokable directly anywhere. No `/release` LLM skill ships in this bundle.

**Alternatives considered:**
- A `/release` skill as the primary interface. Rejected because: every step
  (gate checks, tag, push, `gh release create`) is judgment-free; the
  judgment that exists (release now? correct version? notes prose?) is
  already exercised on the release PR. Tool-grounded over vibes; an LLM in a
  mechanical path adds variance, cost, and a place to hallucinate.
- A thin skill wrapper over the script for in-session ergonomics. Deferred,
  not rejected: add later if usage shows in-session invocation matters.

**Chosen because:** reflex step 5 — right-altitude the solution; planwright
already ships mechanical guards as scripts, and a script is what the guard
catalog can scaffold into adopter repos.

### D-9: SemVer for planwright  (N)

**Decision:** planwright versions by SemVer (`vX.Y.Z` tags, `plugin.json`
continuing from `0.1.0`): feat→minor, fix→patch, breaking→major.

**Alternatives considered:**
- CalVer (`YYYY.MINOR.PATCH`), fleet-consistent with the author's Elixir
  application repo. Rejected because: a plugin is a compatibility-bearing
  artifact — consumers (and the marketplace) reason about breaking changes,
  which SemVer signals and CalVer does not; the fleet repo is a
  continuously-shipped application where "when did this ship" matters more.

**Chosen because:** artifact type decides the scheme (the heuristic REQ-G1.2
generalizes into the decision-domains entry, with this call as the worked
example); it also avoids resetting the existing `0.1.0` lineage.

### D-10: Notes from merged PRs, spec-enriched, never spec-dependent  (N)

**Decision:** Release notes derive from merged PRs since the last release,
grouped by conventional-commit type (release-please's changelog mechanism),
enriched with spec/task references where PR bodies already carry them. The
GitHub Release body is the released version's CHANGELOG section.

**Alternatives considered:**
- Spec-centric notes (organized around bundles that reached Done). Rejected
  because: not every PR maps to a spec, hotfixes and chores would vanish, and
  adopters without the spec habit would get empty notes.
- No generated notes (tag only). Rejected because: the release PR already
  produces the changelog for free; discarding it wastes the proposal
  artifact.

**Chosen because:** conventional commits are the enforced, reliable spine;
spec references degrade gracefully from enrichment to absence.

### D-11: Altitude triggers + phase re-anchor, doctrine-defined, skill-wired  (N)

**Decision:** The altitude discipline lives in `doctrine/autopilot-reflex.md`
and is wired into skills the way research-rigor already is: `/spec-draft`
pins seed claims about the deliverable's nature during seed gathering,
resolves altitude before design when a trigger fires, and restates the
claimed altitude in every phase-end summary; `/spec-kickoff`'s lens pass
checks that a triggered bundle carries the altitude D-ID and that tasks match
it. The record is required only when a trigger fired.

**Alternatives considered:**
- A fixed altitude question in phase 1 of every draft. Rejected because: it
  taxes trivial specs with ceremony and would not have caught this session's
  failure, which was mid-design drift after a correct-sounding start.
- Conversation discipline with no artifact. Rejected because: an instruction
  an LLM follows can be pencil-whipped; the D-ID is what downstream checks
  can verify.
- A required meta-spec field ("Deliverable altitude") in every bundle's goal.
  Rejected because: touches `spec-format` and the validator for all bundles;
  disproportionate when the trigger-scoped D-ID achieves the teeth.

**Chosen because:** the session's failure had two distinct modes — an
under-weighted explicit seed claim, and gradual drift — and this pairing
covers both (pinning + trigger for the first, re-anchor for the second) at
zero cost to specs where no trigger fires.

### D-12: Armed mode is a sequenced follow-up task, in this bundle  (N)

**Decision:** An armed/watch mode for the publish flow — run before the merge,
pre-validate, watch the release PR, fire the publish the moment the merge is
observed — ships as a task sequenced after the post-merge core (Task 10,
dependent on Tasks 4 and 6), not in the first wave and not as a separate
spec.

**Alternatives considered:**
- Armed mode in the first wave. Rejected because: the post-merge script plus
  the lock already close the forget-gap completely; armed mode only shrinks
  the lock window's duration, an ergonomic optimization.
- A separate future spec. Rejected because: it shares every design decision
  with the core publish; a bundle-internal dependency edge is the honest
  representation.

**Chosen because:** sequencing keeps momentum without gating the core on the
harder piece (merge-event watching, held session).

### D-13: Adopter path through builder/catalogs; capability core, mechanism template, value config  (N)

**Decision:** The adopter-facing shape is: **capability** in core (the
publish + comparator scripts, the doctrine); **mechanism** as opt-in
templates the guard catalog's new release-tagging entry scaffolds
(release-PR workflow config, lock workflow, merge-queue guidance);
**value** as configuration (`require_signed_tags`, `version_file`, the
scheme choice guided by the new decision-domains entry). No new top-level
command ships.

**Alternatives considered:**
- Ship the full release-please flow as core (workflows landed by default).
  Rejected because: assumes GitHub Actions, imposes a third-party action and
  a write-token posture on every adopter — mechanism forced to capability
  altitude.
- planwright-repo-only (no adopter path). Rejected because: the detection
  facet ("you ship a versioned artifact with no release automation") is
  exactly the kind of recommendation the builder exists to make; withholding
  it re-opens the gap for every adopter.

**Chosen because:** it is the customization-boundary pattern applied
verbatim, and the builder/guard-catalog channel already exists — the reflex's
own step 5, practiced.
