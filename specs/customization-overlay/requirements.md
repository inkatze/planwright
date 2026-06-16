# Customization & Overlay Mechanism — Requirements

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Goal

planwright core ships general doctrine and skills. Adopters and the author
carry personal and team preferences — a review-gauntlet ordering, a
dispatch-isolation default, project-specific decision-domain entries — that
today live ad hoc in personal memory and dotfiles `CLAUDE.md`. That has two
costs: skills cannot apply those preferences systematically, and the only way
to bake them in is editing core doctrine or skills, which makes core less
general for adopters and pollutes the observation stream that is meant to
merge upstream.

This spec defines a sanctioned **overlay** mechanism: a fixed precedence model
(`core defaults < adopter overlay < repo-tracked overlay < machine-local
overlay`), defined overlay locations, a per-kind resolution and merge contract
that skills read through, and a documented boundary rule separating a *general
capability* (lands in core, exposed via a config knob, opt-in) from a
*personal/team style* (stays in an overlay). Core stays general; personal and
team layers compose on top without forking core, keeping each fork's
observations mergeable upstream. The mechanism ships before bootstrap Task 19
(packaging/onboarding documents it) and before the work fork diverges, so the
work fork can layer company standards as overlays rather than hard-editing
core.

## Scope

### In scope

- The four-layer precedence model: the layers, their fixed order, and
  conflict resolution.
- Overlay locations for each layer and each kind, and how they relate to the
  existing `planwright.local.yml` config model (bootstrap D-33).
- The per-kind resolution and merge contract skills use to compute effective
  configuration (config-value override, doctrine whole-doc shadow, catalog
  append/union).
- The boundary doctrine separating general capability (core + config knob)
  from personal/team style (overlay).
- Resolution provenance (which layer set each effective value).
- Overlay data hygiene, identifier and path-traversal security, and adopter
  documentation.

### Out of scope

- Changing any specific default (for example dispatch-isolation per-step):
  this spec ships the seam, not the overlays that ride it.
- The work fork's actual company-standard overlay content (the fork populates
  its own overlays).
- Wholesale migration of personal memory or dotfiles `CLAUDE.md` into
  overlays (enabled here, executed downstream).
- Secrets or credentials in overlays (overlays carry preferences; secrets
  stay out per the data-hygiene rule).
- Per-machine environment plumbing (`mise.local.toml`): already solved, a
  distinct layer.
- Executable plugin or code-injection extensions: overlays stay declarative
  (config values, doctrine-doc overrides, catalog data), not arbitrary code.
- Doctrine fragment/section merge: **deferred** for v1 (whole-doc shadow
  only), gated in `tasks.md` under `## Deferred` — listed here to mark the v1
  scope boundary, not as a permanent exclusion (D-5).

## REQ-A — Overlay model, layers & precedence

- **REQ-A1.1** planwright SHALL define four configuration layers in fixed
  precedence order, lowest to highest: core defaults, adopter overlay
  (per-operator, cross-repo), repo-tracked overlay (team-shared,
  version-controlled), and machine-local overlay (gitignored, per-machine). A
  higher layer SHALL override a lower layer for the same setting.
  *(Cites: D-1; the customization-overlay seed (Sources); orchestrator review
  (2026-06-15).)*
- **REQ-A1.2** Each overlayable kind (config values, doctrine/process docs,
  data catalogs) SHALL retain its kind-native mechanism; the four layers and
  their precedence order SHALL apply uniformly across all kinds — one
  precedence rule, a per-kind merge.
  *(Cites: D-2; drafting-session decision (2026-06-15).)*
- **REQ-A1.3** Adding an adopter, repo-tracked, or machine-local overlay SHALL
  require no edits to core doctrine docs or skills (the no-fork invariant):
  core stays general and overlays compose on top.
  *(Cites: D-1, D-2; the customization-overlay seed (Sources).)*
- **REQ-A1.4** An absent overlay layer SHALL be a normal state — resolution
  degrades to the next lower layer — never an error.
  *(Cites: D-1; the customization-overlay seed (Sources).)*
- **REQ-A1.5** The adopter overlay SHALL be scoped per plugin namespace, so a
  public planwright install and a divergent work fork never share one adopter
  overlay, and SHALL be resolvable in both delivery modes (plugin and writer).
  When the writer-mode namespace cannot be derived (the plugin manifest `name`
  is absent or unresolvable), the adopter layer SHALL be treated as absent and
  resolution degrades per REQ-A1.4 — never an error.
  *(Cites: D-3; the multi-install coexistence seed (Sources).)*
- **REQ-A1.6** The mechanism SHALL distinguish the tracked team overlay from
  the gitignored machine-local overlay: `<repo>/.claude/planwright.local.yml`
  IS the machine-local layer (gitignored, per-machine, highest precedence),
  and the team overlay SHALL be a separate tracked file
  (`<repo>/.claude/planwright.yml`). The malformed-overlay policy (REQ-E1.4)
  depends on this distinction.
  *(Cites: D-1, D-4; the machine-local env observation (Sources); orchestrator
  review (2026-06-15).)*

## REQ-B — Resolution & merge semantics

- **REQ-B1.1** Config values SHALL resolve by last-layer-wins override per
  key, extending `config-get.sh` from its current two layers to all four
  (inserting the adopter and repo-tracked layers between core defaults and
  machine-local).
  *(Cites: D-5; bootstrap D-33.)*
- **REQ-B1.2** Doctrine/process overlays SHALL resolve by whole-doc shadow:
  the highest-precedence overlay doc of a given name wins in full, extending
  `resolve-rule-doc.sh`'s first-hit-wins chain. Fragment or section merge is
  out of scope.
  *(Cites: D-5; orchestrator review (2026-06-15).)*
- **REQ-B1.3** Data catalogs SHALL resolve by append/union: overlay entries
  add to the core seed list, additive unless an entry explicitly supersedes a
  prior entry by id. This SHALL apply to both growable catalogs — the
  decision-domains catalog and the guard catalog (the engineering-builder
  guard catalog from bootstrap Task 16).
  *(Cites: D-5; the decision-domains adopter seed (Sources).)*
- **REQ-B1.4** Effective configuration SHALL be computable by a skill or hook
  through a stable per-kind resolution path (`config-get`, `resolve-rule-doc`,
  catalog discovery); no skill SHALL implement its own layer merging.
  *(Cites: D-2.)*
- **REQ-B1.5** Resolution SHALL be deterministic, governed by the defined
  layer order, not by filesystem enumeration order.
  *(Cites: D-2.)*
- **REQ-B1.6** Each resolver SHALL provide a provenance mode (`--explain`)
  that names which layer set each effective config value and which layer
  supplied each resolved doc or catalog entry.
  *(Cites: D-9; orchestrator review (2026-06-15).)*
- **REQ-B1.7** Doctrine/process overlay resolution SHALL emit a loud stderr
  warning when an overlay shadows a protected core governance or security doc
  (the protected set is defined normatively in D-11: `spec-format`,
  `security-posture`, `validation-rigor`, `discovery-rigor`,
  `finding-categorization`), naming the shadowed doc and the risk; the override
  still resolves (warn-but-allow), so a legitimate fork keeps full control
  while a shadow of a framework-guarantee doc is never silent.
  *(Cites: D-11; kickoff §3 REQ-B (2026-06-16).)*

## REQ-C — Capability-vs-style boundary doctrine

- **REQ-C1.1** planwright SHALL define a boundary rule distinguishing a
  general capability (lands in core, exposed via a config knob, opt-in) from a
  personal/team style (stays in an overlay), with criteria an author can apply
  at decision time.
  *(Cites: D-10.)*
- **REQ-C1.2** The boundary rule SHALL state the default tilt: when in doubt,
  one-operator-specific, or unproven, a preference stays in an overlay; it
  graduates to core only when it generalizes, with drain-loop evidence (the
  same growth model the decision-domains catalog uses).
  *(Cites: D-10; the decision-domains adopter seed (Sources).)*
- **REQ-C1.3** The boundary doctrine SHALL carry two worked examples:
  review-gauntlet ordering as personal style (overlay), and the
  dispatch-isolation default as a candidate core capability exposed via a
  config knob. The `review_sequence` knob (REQ-D1.3) is the runnable instance.
  *(Cites: D-10; the dispatch-isolation observation (Sources); the
  customization-overlay seed (Sources).)*

## REQ-D — Skill integration & consumption

- **REQ-D1.1** Skills and hooks that read config, resolve doctrine, or consume
  a data catalog (the decision-domains catalog and the guard catalog) SHALL do
  so through the shared resolution paths, so overlays apply automatically; no
  skill SHALL hardcode a single-layer read.
  *(Cites: D-2, D-5; the decision-domains adopter seed (Sources).)*
- **REQ-D1.2** Doctrine/process overlays SHALL be consumable with no new
  per-skill wiring beyond the resolver change: existing `resolve-rule-doc.sh`
  callers gain overlay resolution for free.
  *(Cites: D-2; bootstrap REQ-I1.1.)*
- **REQ-D1.3** The review-gauntlet ordering SHALL be expressible as a config
  list-knob (`review_sequence`, an ordered list of nestable review-skill
  names — a *nestable* review skill is one invocable with `--nested`, e.g.
  `/polish`, `/self-review`), resolved through all four layers, and honored by
  `/execute-task`'s
  convergence phase, default-preserving (the default reproduces today's
  behavior). A `review_sequence` entry naming an unknown or non-nestable
  review skill SHALL be treated as a malformed overlay value under the
  REQ-E1.4 by-layer policy (degrade+warn for adopter/machine-local, hard-fail
  for repo-tracked).
  *(Cites: D-6; the customization-overlay seed (Sources); kickoff §3 REQ-D
  (2026-06-16).)*

## REQ-E — Data hygiene, validation, security & documentation

- **REQ-E1.1** Overlays SHALL carry no secrets or credentials; the artifact
  data-hygiene rule applies, and the secret-scan guard covers committed
  overlays.
  *(Cites: security-posture (Sources).)*
- **REQ-E1.2** Overlay identifiers (names, path segments) SHALL be validated
  against the identifier charset before any interpolation into a path or
  command.
  *(Cites: security-posture (Sources); bootstrap REQ-A1.8.)*
- **REQ-E1.3** Every overlayable config option SHALL remain documented in the
  canonical options reference, and the overlay mechanism plus its per-layer
  locations SHALL be documented for adopters (bootstrap Task 19 onboarding).
  *(Cites: bootstrap D-43; bootstrap REQ-K1.8.)*
- **REQ-E1.4** A malformed overlay SHALL be handled by layer (malformed =
  unreadable, or unparseable / structurally invalid for the kind's reader — for
  config, not flat `key: value`; for a catalog, not parseable into entries): a
  malformed adopter or machine-local overlay degrades to the next lower layer
  with a loud warning; a malformed repo-tracked (team-shared) overlay
  hard-fails, so a broken shared config never silently runs unintended behavior
  across a team.
  *(Cites: D-7; orchestrator review (2026-06-15).)*
- **REQ-E1.5** Doctrine-overlay resolution SHALL confine resolved override
  paths under the overlay root: a path escaping the root (`../`, absolute, or
  symlink-escape) SHALL be rejected with a clear message, canonicalized and
  containment-checked before any read.
  *(Cites: D-8; security-posture (Sources); orchestrator review (2026-06-15).)*

## Changelog

- 2026-06-15: Bundle drafted at Status Draft via `/spec-draft`. Four-layer
  precedence model, kind-native resolution, capability-vs-style boundary
  doctrine, and the security and provenance requirements established from the
  seed material and the orchestrator-relayed requirements review.
- 2026-06-16: Kickoff first-activation refinements (brief §3, still Draft):
  writer-mode adopter-overlay namespace pinned to the plugin manifest `name`
  (D-3); protected-doc shadow warn-but-allow added as REQ-B1.7 / D-11;
  catalog supersede-by-id syntax assigned to Task 5, with guard-catalog
  consumer wiring made contingent on bootstrap Task 16 (D-5); unknown or
  non-nestable `review_sequence` names routed through the REQ-E1.4
  malformed-by-layer policy (REQ-D1.3).
- 2026-06-16: Kickoff lens-pass refinements (brief §8, still Draft): defined
  "nestable" review skill (REQ-D1.3); defined "malformed" (REQ-E1.4); named the
  team overlay file and the absent-writer-namespace degrade (REQ-A1.5/A1.6,
  D-3); made D-11 the normative home of the protected-doc set (REQ-B1.7);
  standardized "guard catalog" naming (REQ-B1.3); reclassified doctrine
  fragment/section merge from Out-of-scope to Deferred-gated; noted Task 5 must
  pin supersede-of-nonexistent-target; added the uncommitted-overlay secret
  warning to Task 7; noted doctrine's exclusion from the determinism test.

## Sources

- **The customization-overlay seed** — observations log entry 2026-06-15
  (consumed; archived to `specs/_observations/archive.md`): the need for a
  sanctioned overlay mechanism with a `core < adopter < repo` precedence
  model, overlay locations, skill resolution, and the general-capability vs
  personal-style boundary.
- **The decision-domains adopter seed** — observations log entry 2026-06-11
  (consumed; archived): the decision-domains catalog's adopter-extension
  channel has no config-model home; a concrete instance of the overlay-merge
  problem.
- **The dispatch-isolation observation** — observations log entry 2026-06-15
  (referenced, not consumed): per-step dispatch isolation as a candidate core
  default, used here as a capability-vs-style worked example.
- **The machine-local env observation** — observations log entry 2026-06-12
  (referenced, not consumed): the gitignored repo-root machine-local config
  layer, distinct from a tracked team overlay.
- **The multi-install coexistence seed** — planwright PR #21
  (`chore/observations-coexistence`): a public install and a work fork must
  not collide; motivates per-plugin-namespace adopter-overlay scoping.
- **The orchestrator-relayed requirements review** — drafting-session review
  (2026-06-15): four-layer correction, malformed-by-layer policy,
  per-namespace adopter scoping, whole-doc shadow, gauntlet-as-config,
  provenance and path-confinement additions.
- **bootstrap spec** (`specs/bootstrap/`): the config model (bootstrap D-33),
  the rule-doc resolution layer (bootstrap REQ-I1.1, D-24), the options
  reference (bootstrap D-43, REQ-K1.8), and the identifier discipline
  (bootstrap REQ-A1.8) this bundle coordinates with and extends.
- **Doctrine** — `spec-format`, `engineering-decisions`, `decision-domains`,
  `security-posture`, `interaction-style`: the meta-spec and rules this bundle
  conforms to and cites.
