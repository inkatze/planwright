# Engineering Decisions

planwright's skills make engineering choices constantly: which idiom to
follow, which tool to defer to, which library to adopt, which decision to
refuse to make alone. This doc encodes the decision process those choices
run through. It is the doctrine half of the engineering builder (D-15); the
builder skill applies it mechanically where it can and escalates where it
must, and the [decision-domains catalog](decision-domains.md) supplies the
triggers that activate the escalation rule.

Citations: REQ-G1.1, REQ-G1.3, REQ-G1.6 · D-15, D-16.

## The decision process

When an implementation choice arises, work down this ladder. Each rung
resolves most choices; the next rung exists for what the previous one
leaves open.

1. **Prefer the framework, language, and stack idioms.** Code at the
   framework boundary should look like what someone fluent in that stack
   expects: the framework's routing, config, persistence, and dependency
   conventions, not a parallel structure invented beside them. Domain logic
   stays composable within that frame (see
   [composability.md](composability.md)): small units, data in and data
   out, composed through the language's natural mechanism. The idiom
   decides the shape of the boundary; composability decides the shape of
   what lives inside it.

2. **Defer to tooling and ecosystem standards.** Where a formatter,
   linter, type checker, or community-standard configuration has an
   opinion, take it. A choice a tool can enforce is a choice nobody should
   spend judgment on, and tool-grounded conventions transfer between
   contributors in a way personal taste does not. This is the same
   tool-grounding rule [Discovery Rigor](discovery-rigor.md) and the
   [Refactor Instinct](refactor-instinct.md) apply to findings, pointed
   at decisions.

   Two companion principles keep the deference honest. **Pin the
   toolchain.** Tool-grounded discovery is only as trustworthy as the
   toolchain is reproducible: different tool versions fire different
   rules, so an unpinned tool is a moving target wearing a green
   checkmark. Pin quality tools through the ecosystem-native mechanism
   (the manifest's dev dependencies, a toolchain file, a polyglot pinner
   where the stack has none), so contributors and CI run the same
   versions. **Own the defaults you adopt.** A tool's defaults encode the
   tool author's context, not the project's. At adoption, review the
   handful of conventions-bearing defaults (line lengths, formatting
   shapes, output filtering), record deviations with their rationale in
   tracked config, and accept the rest. Only conventions-bearing defaults
   surface as decisions; everything else is exactly the kind of choice
   deference exists to absorb.

3. **Research how mature projects solve it.** When no clean best practice
   is apparent from the first two rungs, the question becomes "how do
   mature projects in this ecosystem solve this" — the ecosystem-research
   move. This is [Research Rigor](research-rigor.md)'s mature-project
   comparison trigger: consult the source hierarchy (official docs, the
   exemplar projects' own source and tests, issues and RFCs), check the
   pattern against the antipattern list, and record what was weighed in
   the risk register. A pattern three healthy projects converged on
   independently is evidence; a pattern one blog post recommends is a
   lead.

## Stake awareness: the no-flattening rule

Some decisions look mechanical and are not. The escalation rule (REQ-G1.3,
D-16): a decision that appears mechanical but carries technical plus
business or domain stakes is escalated as a design decision / Needs human
judgment and routed into the deferral mechanism as a gate entry — never
auto-defaulted, however idiomatic the default looks.

The canonical example is authentication. "Add auth" reads like a
scaffolding checkbox next to "add a linter", and every stack has a default
answer one command away. But the actual choices underneath (session versus
token, identity provider versus owned credentials, how tenancy is drawn)
are architecture-defining and often business differentiators. Auto-stamping
the stack default flattens a load-bearing decision into a checkbox. The
same flattening risk applies to data modeling, security posture, and
integration surface — the [decision-domains catalog](decision-domains.md)
enumerates the domains and their triggers.

Recognizing which seemingly-mechanical decisions are load-bearing is the
process's primary intelligence; it is what separates an engineering
builder from an "add a linter" scaffolder. When in doubt about whether a
decision carries stakes, it does: escalating a mechanical decision costs a
sign-off; auto-defaulting a load-bearing one costs an architecture.

## Dependency adoption

Adopting a dependency is signing up for someone else's roadmap. Before
adding a library, service, or tool the project does not already use, run
this checklist (it pairs with [Research Rigor](research-rigor.md)'s
new-dependency trigger, which fires at the same moment):

- **Supply chain.** Provenance and publisher trust; install-time script
  behavior; typosquatting distance from better-known names; whether the
  registry artifact matches the public source.
- **Maintenance status.** Release cadence, recency of the last release,
  responsiveness to issues, bus factor. A dependency abandoned upstream
  becomes the project's own code the day it breaks.
- **License.** Compatible with the project's license and its distribution
  model, including the licenses the dependency itself pulls in.
- **Transitive weight.** The full tree the dependency drags in: each
  transitive node is supply-chain surface, upgrade friction, and audit
  burden. Prefer the standard library or an existing dependency when the
  gap is small.

The checklist is stake-escalated per the no-flattening rule: a dev-only
formatter plugin needs the checklist recorded and little else, while a
runtime dependency on the request path, a crypto or auth library, or
anything handling untrusted input escalates the adoption itself as a
design decision. The findings and the tradeoffs weighed are recorded in
the risk register per Research Rigor.

## Priority balancing

This doctrine advises and weighs; it does not rigidly enforce. The rungs
and rules above are defaults with reasons attached, not a constraint
solver: idioms can be outgrown, tooling opinions can be wrong for a
specific file, the mature-project pattern can be wrong for this project's
scale. When principles conflict — idiom versus composability, consistency
versus a measurably better local choice, shipping versus polishing — the
resolution is a weighed tradeoff, taken at the altitude of what is at
stake and how reversible the choice is (see
[proportionality.md](proportionality.md)).

What nuance never licenses is silence. Departing from a rung, skipping a
checklist, or trading one priority against another is fine exactly when
the departure is declared and the reasoning is recorded where the next
reader will find it (the risk register, the PR body, the decision's
gate entry). An undeclared departure is indistinguishable from an
oversight, and gets reviewed as one.
