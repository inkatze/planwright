# Customizing planwright with overlays

planwright core ships **general** doctrine and skills. Your project carries
preferences that are not general — a review-gauntlet ordering, a
dispatch-isolation default, project-specific decision-domain entries, a tweaked
rule doc. You must be able to add these **without editing planwright's core**.
Editing core would make it less general for everyone and pollute the
observation stream meant to merge upstream.

Overlays are the sanctioned seam for that. An overlay is a **file placement**,
never a core edit: you drop a file at a defined location and a higher layer
takes precedence over a lower one. This is the **no-fork invariant** — adding a
preference never requires forking or hand-editing a shipped doc, script, or
config (REQ-A1.3).

This guide is the adopter-facing reference for the mechanism: the four layers,
where each overlayable thing lives per layer, how layers merge, what happens
when an overlay is malformed, how to debug resolution with `--explain`, and the
data-hygiene rule that is the **only** guard against secrets in your
uncommitted overlays. Two worked examples close it out.

For the decision-time rule on *what belongs in an overlay versus core*, see the
[`customization-boundary`](../doctrine/customization-boundary.md) doctrine doc.
Overlays carry **personal/team style**; a **general capability** belongs in
core, exposed through a config knob.

## 1. The four layers

Every overlayable thing resolves through four layers in one fixed precedence
order, lowest to highest (D-1, REQ-A1.1):

| Layer | Owner | Scope | Tracked? |
| --- | --- | --- | --- |
| **core** | planwright | the shipped defaults | tracked in planwright |
| **adopter** | you, the operator | all your repos | per-operator, outside any repo |
| **repo-tracked** | the team | one repo, everyone on it | committed to the repo |
| **machine-local** | you, on one machine | one repo, one machine | gitignored (see §6) |

A higher layer overrides a lower layer for the same setting. **An absent layer
degrades to the next lower one; it is never an error** (REQ-A1.4) — you only
create the layers you need, and out of the box only `core` exists.

The two repo-side layers are deliberately distinct trust classes:
`repo-tracked` is a committed team file everyone inherits; `machine-local` is
gitignored and yours alone. That split is what lets the malformed-overlay
policy (§4) treat a broken team file more strictly than a broken personal one.

### Where the adopter layer lives

The adopter overlay root is resolved through a chain (D-3), so it works in both
delivery modes without configuration:

```text
$PLANWRIGHT_ADOPTER_OVERLAY            # explicit override (tests, advanced setups)
  → $CLAUDE_PLUGIN_DATA/overlay/       # plugin mode: the <id> segment IS your namespace
  → <claude-dir>/planwright/<name>/overlay/   # writer mode: <name> from the plugin manifest
```

In **plugin mode**, `$CLAUDE_PLUGIN_DATA` already carries a per-plugin
namespace, so a public install and a work fork resolve to *distinct* adopter
overlays automatically — they never collide (REQ-A1.5). In **writer mode** the
`<name>` segment is read from the plugin manifest `name` field that
`scripts/install.sh` copies into place. `<claude-dir>` is `$CLAUDE_DIR` if set, else
`$HOME/.claude`. If the manifest is missing or unreadable, the adopter layer is
simply treated as absent and resolution falls through to the next lower layer —
never an error.

## 2. Where each kind lives, per layer

There is **no single overlay-root directory**. Each of the three overlayable
*kinds* keeps its own native shape and has its own per-layer locations, all
obeying the precedence order above (D-2, D-4). `<repo>` is the repository root;
`<adopter-root>` is the resolved adopter overlay root from §1.

### Config values — `scripts/config-get.sh`

| Layer | Location |
| --- | --- |
| core | `config/defaults.yml` (in planwright) |
| adopter | `<adopter-root>/planwright.yml` |
| repo-tracked | `<repo>/.claude/planwright.yml` |
| machine-local | `<repo>/.claude/planwright.local.yml` |

Every option is listed in the [options reference](options-reference.md); an
undocumented option fails planwright's own CI. Set an option in any layer with
a flat `key: value` line.

### Doctrine / process docs — `scripts/resolve-rule-doc.sh`

| Layer | Location |
| --- | --- |
| core | `doctrine/<name>.md` (in planwright) |
| adopter | `<adopter-root>/doctrine/<name>.md` |
| repo-tracked | `<repo>/.claude/doctrine/<name>.md` |
| machine-local | `<repo>/.claude/doctrine.local/<name>.md` |

The repo-side pair shares `<repo>/.claude/` and is distinguished by the
`doctrine.local/` versus `doctrine/` subdirectory, mirroring the
`planwright.local.yml` / `planwright.yml` config split.

### Data catalogs — `scripts/resolve-catalog.sh`

| Layer | Location |
| --- | --- |
| core | `config/<name>.yaml` (the shipped seed, e.g. `config/decision-domains.yaml`, `config/guard-catalog.yaml`) |
| adopter | `<adopter-root>/catalogs/<name>.yaml` |
| repo-tracked | `<repo>/.claude/catalogs/<name>.yaml` |
| machine-local | `<repo>/.claude/catalogs.local/<name>.yaml` |

The two growable catalogs are **decision-domains** (the catalog behind the
drift triggers) and the builder's **guard catalog**.

## 3. How each kind merges

Each kind merges in the way that fits its native shape (D-5). The precedence
order is the same for all three; only the *merge rule* differs.

- **Config — last-layer-wins, per key.** The highest layer that sets a key
  wins for that key; other keys fall through independently. Setting one option
  in `machine-local` does not discard the rest of the lower layers.
- **Doctrine — whole-doc shadow.** The highest-precedence doc of a given name
  wins **in full**. There is no fragment or section merge: if your overlay
  `validation-rigor.md` omits a section the core doc had, that section is gone
  for you. Override a doc by copying it whole and editing, not by splicing.
- **Catalog — append / union, with supersede-by-id.** Overlay entries **add**
  to the core seed list. An overlay entry that carries `supersede: true` and an
  `id:` matching a lower-precedence entry **replaces** that one entry while the
  rest of the seed survives. A `supersede: true` entry whose `id` matches *no*
  lower entry is an error handled by the by-layer policy in §4 (a repo-tracked
  overlay hard-fails; an adopter or machine-local overlay warns and skips that
  entry). Resolution is order-independent of filesystem enumeration (REQ-B1.5).

## 4. When an overlay is malformed

A malformed overlay (unparseable config, an unreadable catalog, a
supersede-of-nothing) is handled **by layer**, matching each layer's blast
radius (D-7, REQ-E1.4):

| Layer | A malformed overlay there … |
| --- | --- |
| **adopter** | degrades to the next lower layer with a **loud stderr warning** |
| **machine-local** | degrades to the next lower layer with a **loud stderr warning** |
| **repo-tracked** | **hard-fails** with a nonzero exit |

Degrading never aborts the run, but it does not force a zero exit either: the
resolver carries on from the lower layers and returns its **normal** resolution
status. A key or doc still absent in every remaining layer exits with the usual
not-found code (`scripts/config-get.sh` exits 3, `scripts/resolve-rule-doc.sh`
exits 1), independent of the degraded overlay.

The asymmetry is deliberate. One operator's broken personal or machine-local
file should never block their run — a warning is proportionate, the blast
radius is one machine. A broken **team-shared** (`repo-tracked`) file that
silently degraded would mean an entire team unknowingly runs unintended
behavior, the worst failure mode for a versioned shared file, so it hard-fails
loudly instead.

### Shadowing a protected core doc warns

A small set of core governance/security docs is **protected** (D-11):
`spec-format`, `security-posture`, `validation-rigor`, `discovery-rigor`,
`finding-categorization`, and `gate-wiring`. You *may* shadow one with a
doctrine overlay — you own your fork — but `scripts/resolve-rule-doc.sh` emits a loud
stderr warning naming the doc and the risk when you do. Shadowing a
non-protected doc is silent. The warning exists because silently replacing a
framework-guarantee doc (the meta-spec, the security posture, the rigor gates)
would remove a guarantee invisibly; warn-but-allow keeps you in control while
making the highest-stakes override visible.

## 5. Debugging resolution with `--explain`

When you cannot tell which layer is winning, ask. Each resolver has an
`--explain` provenance mode that names the supplying layer (D-9, REQ-B1.6).
The layer is always one of `core | adopter | repo-tracked | machine-local`.

```bash
# Which layer set this config key, and to what value? (one TAB-separated line)
scripts/config-get.sh --explain review_sequence
#   core<TAB>[polish]

# Which layer supplied the resolved doctrine doc?
scripts/resolve-rule-doc.sh --explain validation-rigor
#   core<TAB>/path/to/doctrine/validation-rigor.md

# Which layer did each merged catalog entry come from? (one line per entry)
scripts/resolve-catalog.sh decision-domains --explain
#   data-storage<TAB>core
#   ...
```

The line formats are pinned contracts you (or a skill) may parse:
`config-get` prints `<layer>\t<value>`, `resolve-rule-doc` prints
`<layer>\t<path>`, and `resolve-catalog` prints one `<id>\t<layer>` line per
merged entry.

## 6. Secrets and data hygiene — read this

> **Warning.** planwright's secret scanner (`gitleaks`) scans **committed
> files only** (`mise run scan:secrets` runs `gitleaks detect` over the git
> history). Your **adopter** overlay lives outside any repo, and your
> **machine-local** overlay is meant to stay uncommitted (gitignored — but see
> the caveat below). When they are uncommitted, **the scanner never sees
> them**, so a secret you drop into either one is caught by no automated guard.

The **only** guard for those two uncommitted layers is the artifact
data-hygiene rule (see [`security-posture`](../doctrine/security-posture.md)),
applied by hand at write time: overlays carry **no secrets, credentials,
tokens, internal hostnames, or sensitive operational detail**. Keep secrets in
your environment layer (`mise.local.toml`, `.envrc.local`, the OS keychain) and
reference them indirectly — never inline them into an overlay file.

The `repo-tracked` overlay (`<repo>/.claude/planwright.yml`,
`<repo>/.claude/doctrine/`, `<repo>/.claude/catalogs/`) *is* committed, so
`gitleaks` does cover it — but a committed secret is the worst place to put
one. The rule is the same for every layer: **secrets never go in overlays.**

### Keep your machine-local overlays actually uncommitted

The machine-local layer is only uncommitted if your repo's `.gitignore` says so.
planwright's own repo ignores both the machine-local **config** files
(`.claude/*.local.yml`, `.claude/*.local.json`) and the machine-local **doctrine**
and **catalog** overlay directories (`.claude/*.local/`, which covers
`.claude/doctrine.local/` and `.claude/catalogs.local/`). But a repo that adopts
planwright as a plugin does not inherit those ignore rules, so if you place
machine-local doctrine or catalog overlays, add those directories to your repo's
`.gitignore` yourself:

```gitignore
.claude/doctrine.local/
.claude/catalogs.local/
```

Otherwise those "machine-local" overlays get committed — sharing a per-machine
file you meant to keep private and dropping it into the very git history the
data-hygiene rule is there to keep clean.

## 7. Worked example A — dispatch-isolation (the illustrative core-capability shape)

This first example is **illustrative, not a shipped knob** — it shows the shape
of a preference that belongs in *core*, the opposite of the runnable overlay in
§8. It is the worked example carried by the
[`customization-boundary`](../doctrine/customization-boundary.md) doctrine doc;
the customization-overlay spec ships the *seam*, not this particular knob.

Consider per-step **dispatch isolation**: `/orchestrate` running each task in
its own isolated worktree by default. Any operator running tasks in parallel
benefits from isolation, so the preference **generalizes** — it does not encode
one operator's taste. By the capability-vs-style rule that makes it a **general
capability**, and a general capability's home is **core**, exposed as an opt-in,
default-preserving config knob — not a bespoke overlay, and not a hardcoded
default forced on every adopter.

The overlay angle is what this example teaches by contrast: you would **not**
ship a whole alternate orchestration doctrine doc (a doctrine overlay) to flip
an isolation default. Once such a capability lands in core as a config knob, it
resolves through the same four config layers as any other option, so an adopter
could still tune it per scope (a team default in `repo-tracked`, a one-machine
override in `machine-local`) — last-layer-wins, exactly like §8. The
capability is general and lives in core; only the *value* an adopter chooses
rides the overlay layers.

Contrast that with §8, where only the *mechanism* (an ordered review sequence)
is general enough for core while the *value* (the specific ordering) is personal
style that stays in an overlay. Dispatch isolation tilts further toward core
because both its mechanism and its intended default generalize.

## 8. Worked example B — the `review_sequence` gauntlet (a runnable style overlay)

A review-gauntlet **ordering** is **personal/team style**: which review skills
run, and in what order, during `/execute-task`'s convergence phase is a
preference, not a general capability. The *capability* (an ordered, overlayable
review sequence) ships in core as the `review_sequence` config knob; the
specific *ordering* lives in your overlay. This is the runnable instance of the
capability-vs-style boundary.

The knob holds an ordered list of **nestable** review-skill names (a nestable
skill is one invocable with `--nested`, e.g. `polish`, `self-review`). The core
default reproduces today's behavior exactly:

```bash
scripts/resolve-review-sequence.sh
#   polish            # the default: today's single `/polish --nested` convergence
```

Reorder or extend it by setting `review_sequence` in any layer. It resolves
through all four layers like any config value, and last-layer-wins applies:

```yaml
# <adopter-root>/planwright.yml   (your personal default across all repos)
review_sequence: [self-review, polish]

# <repo>/.claude/planwright.yml   (repo-tracked: overrides your adopter default here)
review_sequence: [polish, self-review]
```

With **only** the adopter layer set, `/execute-task`'s convergence phase runs
`self-review` then `polish`. Add the `repo-tracked` layer above and it wins
**outright** — config is last-layer-wins, so the higher layer's list replaces
the whole value rather than merging with it — and convergence runs `polish`
then `self-review`. Either way the order is preserved verbatim, not sorted.

An entry naming an **unknown or non-nestable** skill is a malformed value under
the same by-layer policy as §4: in an adopter or machine-local layer it warns
on stderr and degrades to the core default; in the repo-tracked layer it
hard-fails (a broken shared gauntlet never silently degrades a team).

```bash
# machine-local review_sequence: [polish, bogus-skill]
#   → stderr warning naming machine-local, degrades to core default `polish`, exit 0

# repo-tracked review_sequence: [polish, bogus-skill]
#   → hard-fail (nonzero exit) naming repo-tracked
```

## 9. Where to go next

- [`docs/getting-started.md`](getting-started.md) — installing planwright and
  operating the pilot-in-command model; §4 summarizes overlays and links here.
- [`doctrine/customization-boundary.md`](../doctrine/customization-boundary.md)
  — the decision-time rule for capability versus style.
- [`docs/options-reference.md`](options-reference.md) — every config option,
  including `review_sequence` and `dispatch_backend`.
- [`doctrine/security-posture.md`](../doctrine/security-posture.md) — the
  artifact data-hygiene rule that guards uncommitted overlays.
