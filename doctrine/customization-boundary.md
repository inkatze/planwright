# Capability vs Style: the customization boundary

planwright core ships *general* doctrine and skills. The author and adopters
carry preferences that are not general — a review-gauntlet ordering, a
dispatch-isolation default, project-specific decision-domain entries. The
overlay mechanism gives those preferences a sanctioned home (`core defaults <
adopter overlay < repo-tracked overlay < machine-local overlay`). This doc is
the rule for the question that mechanism raises: when a new preference appears,
*which side of the seam* does it belong on — a general capability that lands in
core, exposed as an opt-in config knob, or a personal/team style that stays in
an overlay?

It is a product/scoping rule, applied at design time — distinct from
[engineering-decisions.md](engineering-decisions.md), which operates at
implementation-choice altitude (which idiom, which tool, which dependency).
Capability-vs-style decides *whether a behavior is core's to have at all*;
engineering-decisions decides *how* a behavior core already owns is built. The
`/spec-draft` design phase consults this doc when a candidate feature looks like
a packaged preference.

Citations: REQ-C1.1, REQ-C1.2, REQ-C1.3 · D-10.

## The boundary

Every customizable preference resolves to one of two things:

- **General capability** → lands in **core**, exposed via an **opt-in config
  knob** whose default preserves existing behavior. The capability is the
  *mechanism*: the ability to do the thing. It earns a place in core because it
  generalizes — independent adopters would plausibly want it.
- **Personal/team style** → stays in an **overlay** (adopter, repo-tracked, or
  machine-local, per the layer's blast radius). Style is the *value* or
  *content*: the specific thing one operator or one team wants. It stays out of
  core because baking it in would make core less general for every other
  adopter and would pollute the upstream observation stream meant to merge back.

The decisive insight: the boundary usually runs *through* a feature, not around
it. A single feature splits into a general capability (the mechanism → core
knob) and a personal style (the value the knob is set to → overlay). The
question is rarely "core or overlay for the whole thing"; it is "what is the
general mechanism here, and what is the specific value riding it." Put the knob
in core; put your value in your overlay.

## Decision-time criteria

Work down these when classifying a preference. The first that resolves the call
usually settles it.

1. **Generality.** Would an *independent* adopter — not you, not your team —
   plausibly want this? If only you or your team would, it is style → overlay.
   If many would, the *capability* may belong in core.
2. **Mechanism vs value.** Separate the ability to do X from the specific X you
   want. The mechanism, if general, is the core capability (a knob); the
   specific X is style (an overlay value). When a preference contains both —
   most do — split it along this line rather than forcing the whole feature to
   one side.
3. **Evidence.** Is the preference proven, or a hunch? A one-off or unproven
   preference stays in an overlay until evidence shows it generalizes. A
   capability earns its core knob with the same drain-loop evidence the
   [decision-domains catalog](decision-domains.md) uses to earn a new entry.
4. **Cost of baking.** Would hardcoding this in core make core less general for
   other adopters, or push one operator's taste into the shared observation
   stream? If yes, it is style → overlay (or, if the mechanism is general, a
   core knob with a default-preserving default — never a baked-in behavior
   change).
5. **Shape in core.** A capability that lands in core lands as an **opt-in
   config knob** with a default that reproduces today's behavior. A core
   capability is never a silent behavior change forced on every adopter; it is a
   seam they may set. If the only way to express it is editing core doctrine or
   a skill, it is not yet shaped as a capability — keep it in an overlay until
   it is.

## Default tilt

**When in doubt, it stays in an overlay.** A preference that is
one-operator-specific, unproven, or whose generality you cannot yet argue
belongs in an overlay, not in core. The cost of a wrong overlay call is one
operator's file; the cost of a wrong core call is a less-general framework and a
polluted upstream observation stream.

A preference **graduates** from overlay to core only when it generalizes, and
only with evidence — the same growth model as the decision-domains and guard
catalogs. Recurring [drain-loop](accumulator-taxonomy.md) observations that
multiple contexts want the same thing are the evidence; on graduation the
preference enters core as an opt-in, default-preserving knob (the *capability*),
while the operator's specific value stays in their overlay (the *style*).
Graduation is additive: it never removes the overlay path, it adds the core
mechanism beneath it.

## Worked examples

### Review-gauntlet ordering — capability in core, ordering in an overlay

An operator runs a specific sequence of *nestable* review skills at convergence
(the default is today's single `/polish` pass; one operator might run
`/self-review` then `/polish`, another a longer in-house ordering of the
nestable review skills available). The boundary runs straight through this
feature:

- The **capability** — expressing a review ordering and having
  `/execute-task`'s convergence phase honor it — is general: any operator
  benefits from being able to set their own convergence sequence. So it lands in
  core as the `review_sequence` config knob
  (REQ-D1.3), an ordered list of nestable review-skill names, resolved through
  all four layers. Its default reproduces today's convergence behavior, so
  out-of-the-box behavior is unchanged. `review_sequence` is the **runnable
  instance** of this doc's rule.
- The **style** — the *specific ordering* a given operator or team prefers — is
  not general; it is that operator's taste. It lives in an overlay: an adopter
  overlay for a personal gauntlet, a repo-tracked overlay for a team-shared one.

Core gains the mechanism; nobody's particular gauntlet is baked into core. This
is the canonical demonstration that capability and style are different layers of
the *same* feature.

### Dispatch-isolation default — a candidate core capability

`/orchestrate` could dispatch each task into an isolated worktree by default
(per-step dispatch isolation). This is a candidate **general capability**: any
operator running tasks in parallel benefits from isolation, so the preference
generalizes rather than encoding one operator's taste. The right home is
therefore a core config knob (opt-in, default-preserving), not a hardcoded
default forced on every adopter and not bespoke overlay behavior.

This example is **illustrative, not shipped** by the customization-overlay spec:
that spec ships the seam (the overlay mechanism and the boundary rule), not this
particular knob. It is named here to show the other shape — a preference whose
*mechanism and intended default* are both general, so the whole thing tilts
toward core-as-knob — in contrast to the review-gauntlet case, where only the
mechanism is general and the value stays in an overlay.
