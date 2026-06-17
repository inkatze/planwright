# planwright Doctrine

These documents are planwright's framework doctrine: the rules its skills apply
at runtime. They are owned by planwright, not by any adopter's personal
configuration (REQ-D1.4). Skills reference them via the stable rule-doc
resolution path defined below (REQ-I1.1, D-24).

| Doc | Covers | Primary citations |
| --- | --- | --- |
| [finding-categorization.md](finding-categorization.md) | The four finding buckets, their predicates, and the act-then-review autonomy gate | REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6 |
| [gate-wiring.md](gate-wiring.md) | The gate's operational wiring: routing order, commit discipline, checklist and audit formats, ladder procedure, pause protocol | REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6 |
| [discovery-rigor.md](discovery-rigor.md) | Making the finding list complete: lens checklist, coverage table, tool-grounded discovery, fan-out, self-critique | REQ-D1.1 |
| [validation-rigor.md](validation-rigor.md) | Confirming findings are real (three passes plus adversarial bi-directional re-validation) and solutions are right (including the altitude check and surface-relative whole-system reproduction) | REQ-D1.2, REQ-D1.8, REQ-D1.9 |
| [refactor-instinct.md](refactor-instinct.md) | Small continuous refactors; low bar in implementation mode, high bar in review mode | REQ-D1.3 |
| [research-rigor.md](research-rigor.md) | When and how to research: triggers, source hierarchy, recency discipline, antipattern check, risk-register recording | REQ-D1.5 |
| [security-posture.md](security-posture.md) | Write-time security triggers, artifact data-hygiene, framework-script security | REQ-D1.6 |
| [proportionality.md](proportionality.md) | Rigor scales with stake and reversibility; scoping must be declared | REQ-D1.7 |
| [composability.md](composability.md) | Composability by default, in adopter code and in planwright itself | REQ-D2.1 |
| [engineering-decisions.md](engineering-decisions.md) | The engineering decision process: idioms first, tooling deference (toolchain pinned, defaults owned), the ecosystem-research move, the no-flattening escalation rule, the dependency-adoption checklist, priority balancing | REQ-G1.1, REQ-G1.3, REQ-G1.6 · D-15, D-16 |
| [customization-boundary.md](customization-boundary.md) | The capability-vs-style boundary: when a preference belongs in core (as an opt-in config knob) vs an overlay; decision-time criteria, the default tilt to overlay, two worked examples | REQ-C1.1, REQ-C1.2, REQ-C1.3 · D-10 (customization-overlay) |
| [decision-domains.md](decision-domains.md) | The decision-domains catalog: entry format (trigger + considerations + disposition), lifecycle wiring, growth mechanics, the ten seed domains | REQ-G1.8, REQ-G1.4 · D-39, D-16 |
| [guard-catalog.md](guard-catalog.md) | The builder's core guard catalog: guard categories, entry format, breadth dimensions, the extension model, the dogfood contract | REQ-G1.2, REQ-G1.5, REQ-G1.7 · D-15, D-16, D-32 |
| [accumulator-taxonomy.md](accumulator-taxonomy.md) | The three accumulator classes and their drain rituals, the `GATE(when:)` convention and its closed grammar (normative home), the shared drain pass behind `/drain` and `--bookkeeping` | REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-H1.5 · D-17, D-18, D-31 |
| [spec-format.md](spec-format.md) | The versioned four-file spec format meta-spec: per-file fields, ID and citation conventions, status lifecycle, amendment ritual, kickoff-brief structure, sign-off records and content anchors, glossary | REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-B2.2 · D-1, D-20, D-25, D-40, D-45 |
| [interaction-style.md](interaction-style.md) | How spec-authoring skills conduct interactive sessions: progress indicator, progressive disclosure, selectors with recommendations, running summary, small bites | REQ-B3.1 |

## Resolution convention

Skills, hooks, and scripts resolve a rule doc by basename through one stable
path that works in both delivery modes, with no mode detection:

```text
${PLANWRIGHT_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_DIR:-$HOME/.claude}/planwright}}/doctrine/<doc>.md
```

- **Plugin delivery (primary, D-24):** Claude Code sets `CLAUDE_PLUGIN_ROOT`
  to the plugin's install directory; docs resolve plugin-relative.
- **Writer delivery (fallback):** `scripts/install.sh` copies this directory
  to `<claude-dir>/planwright/doctrine/` (`<claude-dir>` is `$CLAUDE_DIR` when
  set, else `~/.claude`); the fallback arm of the chain finds it there.
- **Override:** `PLANWRIGHT_ROOT` pins an explicit root (tests, adopters
  embedding planwright elsewhere). It wins over both.

The writer arm requires `CLAUDE_DIR` or `HOME`; when neither is set
(minimal containers), the resolver skips that arm and resolution uses the
first two arms only.

`scripts/resolve-rule-doc.sh <doc-name>` implements the chain (validating the
name against the `^[a-z0-9][a-z0-9-]*$` identifier discipline before any path
is formed) and prints the resolved path; prefer it over hand-building paths.

Doc names are kebab-case basenames without the `.md` suffix, e.g.
`discovery-rigor`, `finding-categorization`.

## How the docs relate

[Discovery Rigor](discovery-rigor.md) produces the finding list.
[Validation Rigor](validation-rigor.md) confirms each finding and each fix.
[Finding Categorization](finding-categorization.md) routes confirmed findings
through the autonomy gate that decides what the agent applies versus what
waits for the human; [Gate Wiring](gate-wiring.md) is that gate's operational
procedure (how dispositions are applied, committed, recorded, and surfaced).
[Research Rigor](research-rigor.md) and the
[Security Posture](security-posture.md) fire on their triggers at any point in
that flow. [Refactor Instinct](refactor-instinct.md) and
[Composability](composability.md) shape the code being written.
[Engineering Decisions](engineering-decisions.md) governs the choices made
while writing it, and the [Decision-Domains Catalog](decision-domains.md)
supplies the triggers that route load-bearing choices to the human instead
of a default. The [Core Guard Catalog](guard-catalog.md) is the mechanical
counterpart: the universal quality guards the builder applies to a detected
stack, with the same no-flattening rule keeping it from auto-defaulting a
load-bearing decision. What any of these defer instead of deciding lands in an
accumulator, and the [Accumulator Taxonomy](accumulator-taxonomy.md)
guarantees it re-surfaces (no write-only deferral).
[Proportionality](proportionality.md) governs how strictly
all of the above scale with what is at stake. Upstream of execution,
[Interaction Style](interaction-style.md) governs how the spec-authoring
skills conduct the interactive sessions that produce the specs everything
above executes against, and the
[Customization Boundary](customization-boundary.md) governs a scoping call made
in those sessions: whether a candidate preference belongs in core (as an opt-in
config knob) or in an adopter/team overlay.

## Adopter extension

Adopters supply project-specific tooling and rigor through their own project
configuration (project memory files, the tool-discovery hook's detected
toolchain, project config for thresholds and toggles), never by editing these
docs (REQ-D2.2). The docs define the framework's invariant behavior; the
project supplies the ground the behavior runs on.
