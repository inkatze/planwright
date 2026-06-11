# planwright Doctrine

These documents are planwright's framework doctrine: the rules its skills apply
at runtime. They are owned by planwright, not by any adopter's personal
configuration (REQ-D1.4). Skills reference them via the stable rule-doc
resolution path (plugin-relative in plugin delivery, `~/.claude/` in writer
delivery; the convention is a Task 1 deliverable of the bootstrap spec).

| Doc | Covers | Primary citations |
| --- | --- | --- |
| [finding-categorization.md](finding-categorization.md) | The four finding buckets, their predicates, and the act-then-review autonomy gate | REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6 |
| [discovery-rigor.md](discovery-rigor.md) | Making the finding list complete: lens checklist, coverage table, tool-grounded discovery, fan-out, self-critique | REQ-D1.1 |
| [validation-rigor.md](validation-rigor.md) | Confirming findings are real (three passes) and solutions are right (including the altitude check) | REQ-D1.2 |
| [refactor-instinct.md](refactor-instinct.md) | Small continuous refactors; low bar in implementation mode, high bar in review mode | REQ-D1.3 |
| [research-rigor.md](research-rigor.md) | When and how to research: triggers, source hierarchy, recency discipline, antipattern check, risk-register recording | REQ-D1.5 |
| [security-posture.md](security-posture.md) | Write-time security triggers, artifact data-hygiene, framework-script security | REQ-D1.6 |
| [proportionality.md](proportionality.md) | Rigor scales with stake and reversibility; scoping must be declared | REQ-D1.7 |
| [composability.md](composability.md) | Composability by default, in adopter code and in planwright itself | REQ-D2.1 |
| [engineering-decisions.md](engineering-decisions.md) | The engineering decision process: idioms first, tooling deference, the ecosystem-research move, the no-flattening escalation rule, the dependency-adoption checklist, priority balancing | REQ-G1.1, REQ-G1.3, REQ-G1.6 · D-15, D-16 |
| [decision-domains.md](decision-domains.md) | The decision-domains catalog: entry format (trigger + considerations + disposition), lifecycle wiring, growth mechanics, the ten seed domains | REQ-G1.8, REQ-G1.4 · D-39, D-16 |

## How the docs relate

[Discovery Rigor](discovery-rigor.md) produces the finding list.
[Validation Rigor](validation-rigor.md) confirms each finding and each fix.
[Finding Categorization](finding-categorization.md) routes confirmed findings
through the autonomy gate that decides what the agent applies versus what
waits for the human. [Research Rigor](research-rigor.md) and the
[Security Posture](security-posture.md) fire on their triggers at any point in
that flow. [Refactor Instinct](refactor-instinct.md) and
[Composability](composability.md) shape the code being written.
[Engineering Decisions](engineering-decisions.md) governs the choices made
while writing it, and the [Decision-Domains Catalog](decision-domains.md)
supplies the triggers that route load-bearing choices to the human instead
of a default. [Proportionality](proportionality.md) governs how strictly
all of the above scale with what is at stake.

## Adopter extension

Adopters supply project-specific tooling and rigor through their own project
configuration (project memory files, the tool-discovery hook's detected
toolchain, project config for thresholds and toggles), never by editing these
docs. The docs define the framework's invariant behavior; the project supplies
the ground the behavior runs on.
