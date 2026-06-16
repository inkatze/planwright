# Customization & Overlay Mechanism — Design

**Status:** Draft
**Last reviewed:** 2026-06-15
**Format-version:** 1

Origin-tag legend: `N` = new decision minted in this bundle; `N (extends
<foreign>)` = new decision extending a foreign-namespace decision, which is
named in the body. Foreign IDs are namespace-qualified (for example
`bootstrap D-33`).

## Decision log

### D-1: Four-layer precedence model  (N (extends bootstrap D-33))

**Decision:** Define four configuration layers in fixed precedence order,
lowest to highest: core defaults (`config/defaults.yml`, tracked) < adopter
overlay (per-operator, cross-repo) < repo-tracked overlay (team-shared,
version-controlled) < machine-local overlay (`<repo>/.claude/planwright.local.yml`,
gitignored, per-machine). A higher layer overrides a lower layer for the same
setting. An absent layer degrades to the next lower; it is never an error.

**Alternatives considered:**
- Two layers (the status quo: defaults < `planwright.local.yml`). Rejected
  because: it cannot host a per-operator cross-repo preference nor a
  team-shared tracked overlay, which are the two layers the seed needs.
- Three layers (core < adopter < repo, collapsing tracked and machine-local
  into one "repo overlay"). Rejected because: planwright's own machine-local
  doctrine makes `.local` files gitignored and per-machine, which is a
  different trust and sharing class than a tracked team file. Collapsing them
  breaks the malformed-overlay policy (D-7), which must treat a team-shared
  config differently from one operator's machine-local file.

**Chosen because:** four layers cleanly separate the three preference owners
(operator across repos, team within a repo, one machine) on top of core
defaults, and the separation is exactly what the malformed-by-layer policy and
the machine-local doctrine require. It extends bootstrap D-33's two-layer
config model rather than replacing it.

### D-2: Kind-native mechanisms unified by one precedence rule  (N)

**Decision:** The three overlayable kinds keep their kind-native mechanisms —
config values extend `config-get.sh`, doctrine/process overlays extend
`resolve-rule-doc.sh`, data catalogs use per-catalog discovery — and are
unified only by the shared four-layer precedence rule (D-1) and a per-kind
merge (D-5). There is no single unified overlay store; each kind has its own
per-layer locations (D-4). No skill implements its own layer merging; each
reads through the kind's stable resolution path.

**Alternatives considered:**
- One unified overlay store plus a single merge engine producing one
  effective-config object. Rejected because: it reinvents the config layering
  `planwright.local.yml`/`config-get.sh` already does, forces doctrine prose
  into a structured store, and is a larger build for no gain over reusing the
  existing per-kind mechanisms.

**Chosen because:** less new machinery, composes with what exists, and keeps
each kind's resolution honest to its native shape (a YAML value, a Markdown
doc, a list of catalog entries). The cost — a per-kind merge rule that must be
specified for each kind — is paid once in D-5.

### D-3: Adopter overlay home via the CLAUDE_PLUGIN_DATA chain  (N)

**Decision:** Resolve the adopter overlay root through a chain mirroring
`resolve-rule-doc.sh`: `$PLANWRIGHT_ADOPTER_OVERLAY` (explicit override) →
`$CLAUDE_PLUGIN_DATA/overlay/` (plugin mode; the `<id>` segment of
`CLAUDE_PLUGIN_DATA` is the plugin namespace and persists across plugin
updates) → `<claude-dir>/planwright/overlay/` (writer mode). In plugin mode
namespace separation is automatic, so a public install and a work fork resolve
to distinct adopter overlays; writer mode derives a namespace directory.

**Alternatives considered:**
- A uniform `<claude-dir>/planwright/<namespace>/overlay/` for both modes,
  with `<namespace>` derived from the plugin manifest name. Rejected because:
  it reinvents the per-plugin separation `CLAUDE_PLUGIN_DATA` already provides
  for free in plugin mode and adds an explicit namespace-derivation and
  storage rule.

**Chosen because:** it reuses the durable, already-researched plugin-data
location (the `<id>` segment IS the namespace, satisfying REQ-A1.5's
multi-install requirement at no cost), parallels the existing rule-doc
resolver, and keeps an explicit override arm for tests and adopters.

### D-4: Kind-native per-layer overlay locations  (N)

**Decision:** Each kind has its own per-layer locations, all obeying D-1's
order. Config: `config/defaults.yml` < adopter `planwright.yml` (under the
D-3 adopter root) < `<repo>/.claude/planwright.yml` (tracked team file) <
`<repo>/.claude/planwright.local.yml` (gitignored machine-local). Doctrine: a
`doctrine/` directory under each overlay root, inserted into the
`resolve-rule-doc.sh` chain at the right precedence. Catalog: a per-catalog
discovery convention under each overlay root. There is no single overlay-root
directory per layer.

**Alternatives considered:**
- One overlay-root directory per layer with a fixed internal layout
  (`<root>/config.yml`, `<root>/doctrine/`, `<root>/catalogs/`). Rejected
  because: it forces the existing flat config files (`defaults.yml`,
  `planwright.local.yml`) into a new directory structure, breaking
  `config-get.sh`'s current paths and adding a migration for no functional
  gain.

**Chosen because:** it is consistent with the kind-native architecture (D-2),
disrupts no existing config path, and lets each kind use the location shape
that fits it. The cost — three location conventions to document — is absorbed
by the adopter docs (REQ-E1.3).

### D-5: Per-kind merge semantics  (N)

**Decision:** Config values merge by last-layer-wins override per key.
Doctrine/process overlays merge by whole-doc shadow: the highest-precedence
doc of a name wins in full (no fragment or section merge). Data catalogs merge
by append/union: overlay entries add to the core seed list, additive unless an
entry explicitly supersedes a prior entry by id; this applies to both the
decision-domains catalog and the guard catalog.

**Alternatives considered:**
- Doctrine fragment/section merge (splice overlay sections into a core doc).
  Rejected because: it is fragile and drift-prone — a core doc edit silently
  changes what an overlay fragment lands next to — and `resolve-rule-doc.sh`
  is already first-hit-wins, so whole-doc shadow is the smaller, consistent
  change. Deferred, not foreclosed.
- Catalog full-replace (an overlay catalog file replaces the core seed list).
  Rejected because: it loses the core seed entries an adopter still wants;
  append/union with explicit supersede-by-id preserves them while allowing
  targeted overrides.

**Chosen because:** each merge rule matches its kind's native shape and the
least-surprising behavior for that kind, and all three obey the one precedence
rule from D-1.

### D-6: Review-gauntlet ordering as a config list-knob  (N)

**Decision:** Express the review-gauntlet ordering as `review_sequence`, a
config option holding an ordered list of nestable review-skill names, resolved
through all four layers. `/execute-task`'s convergence phase reads it and runs
the named review skills in order, replacing today's hardcoded
`/polish --nested` step. The default `review_sequence` reproduces current
behavior (the review skills that ship in core today), so out-of-the-box
behavior is unchanged; an overlay can reorder or extend it (for example a
full panel/copilot gauntlet) once those skills exist.

**Alternatives considered:**
- A doctrine-doc override expressing the ordering. Rejected because: an
  ordered list of skill names is structured config, not prose; modeling it as
  a doctrine override would drag in doctrine-merge machinery for what is
  cleanly a config value.
- Deferring the consumer wiring (define the knob, wire no skill). Rejected
  because: REQ-D1.3 requires the knob be honored by a real skill, and
  `/execute-task`'s convergence step is a shipped, testable consumer.

**Chosen because:** it keeps the ordering in the config kind (no new merge
machinery), and `/execute-task` is a genuine core consumer, making this the
runnable worked example of the D-10 capability-vs-style rule: the ordering
*capability* lands in core as a knob; the specific *ordering* lives in an
overlay.

### D-7: Malformed-overlay policy split by layer  (N)

**Decision:** Handle a malformed overlay by layer. A malformed adopter or
machine-local overlay degrades to the next lower layer with a loud warning on
stderr (do not block one operator). A malformed repo-tracked (team-shared)
overlay hard-fails with a nonzero exit, because a broken shared config that
silently degrades means an entire team runs unintended behavior. A malformed
core defaults file is a broken install, surfaced as such (the existing
`config-get.sh` behavior).

**Alternatives considered:**
- Uniform degrade for all layers. Rejected because: a team-shared overlay that
  silently degrades hides a real, shared misconfiguration behind apparently
  normal behavior — the worst failure mode for a versioned team file.
- Uniform hard-fail for all layers. Rejected because: a single operator's
  malformed personal or machine-local file should not block their run; the
  blast radius is one machine, and a loud warning is proportionate.

**Chosen because:** the policy matches each layer's blast radius and trust
class, which is exactly why D-1 keeps the tracked team layer distinct from the
machine-local layer.

### D-8: Doctrine-overlay path-traversal confinement  (N)

**Decision:** Doctrine-overlay resolution resolves to file paths, so a
resolved override path is canonicalized and containment-checked under the
overlay root before any read. A path escaping the root (`../`, an absolute
path, or a symlink that escapes after canonicalization) is rejected with a
clear message, never read.

**Alternatives considered:**
- Identifier-charset validation alone (the existing `resolve-rule-doc.sh`
  name check). Rejected because: the charset check guards the doc *name*, but
  a repo-tracked overlay from an untrusted multi-contributor repo could still
  supply a traversing path or an escaping symlink; containment must be checked
  after canonicalization, per the security-posture path-handling rule.

**Chosen because:** the repo-tracked overlay is committed by potentially
untrusted contributors, making the doctrine-overlay path a genuine traversal
surface; canonicalize-then-contain is the framework-script security standard.

### D-9: Resolution provenance via per-resolver `--explain`  (N)

**Decision:** Each resolver provides a provenance mode: `config-get --explain`
names the winning layer for each key, `resolve-rule-doc --explain` names the
layer that supplied the resolved doc, and the catalog discovery `--explain`
names the layer each merged entry came from. There is no separate aggregate
tool.

**Alternatives considered:**
- One aggregate `overlay explain` command reporting all kinds and layers at
  once. Rejected for v1 because: it must itself call into each kind's resolver
  and is more to build; the per-resolver flag delivers the debugging
  affordance with the smallest change and can be aggregated later if needed.

**Chosen because:** with four layers and per-kind merges, provenance is the
single best debugging affordance, and a per-resolver flag is kind-native
(D-2), consistent with the rest of the design, and the smallest build.

### D-10: Capability-vs-style boundary doctrine in a new doc  (N)

**Decision:** Encode the capability-vs-style boundary rule in a new doctrine
doc, `customization-boundary.md`, resolved via `resolve-rule-doc.sh` and cited
by `/spec-draft`'s design phase. The rule distinguishes a general capability
(lands in core, exposed via a config knob, opt-in) from a personal/team style
(stays in an overlay), states the default tilt toward overlay when in doubt,
and carries the two worked examples (review-gauntlet ordering as style;
dispatch-isolation default as core capability).

**Alternatives considered:**
- A section inside `engineering-decisions.md`. Rejected because:
  engineering-decisions operates at implementation-choice altitude (which
  idiom, which tool, which dependency), while capability-vs-style is a
  product/scoping rule at a different altitude; co-locating them blurs both.

**Chosen because:** the boundary rule is a distinct, citable doctrine consumed
at a specific lifecycle point (the `/spec-draft` design phase), so it earns its
own resolvable doc rather than bloating an adjacent one.

## Cross-cutting concerns

- **Coordination with bootstrap, not duplication.** This bundle extends
  bootstrap's config model (D-33), rule-doc resolution (REQ-I1.1, D-24),
  options reference (D-43), and identifier discipline (REQ-A1.8) rather than
  re-deciding them. Fold-detection confirmed spin-new (a new external
  interface — overlay locations and the merge contract — independently
  ownable, orthogonal to bootstrap's build domain).
- **Security surface.** The resolvers parse overlay files (YAML, Markdown) and
  derive paths from potentially untrusted repo-tracked overlays. The
  security-posture write-time triggers fire on path handling (D-8),
  serialization/parsing, and subprocess construction; the execution skills run
  the focused security pass when implementing the resolvers.
- **`$CLAUDE_PLUGIN_DATA` risk.** D-3 leans on `CLAUDE_PLUGIN_DATA` semantics
  cited from 2026-06-11 repo research; the kickoff brief's risk register
  carries a row to re-verify those semantics at implementation.
