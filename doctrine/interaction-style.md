# Interaction Style for Spec-Authoring Skills

How planwright's spec-authoring skills (`/spec-draft`, `/spec-kickoff`)
conduct a long interactive session without losing the human. Authoring a spec
is hours of joint decision-making; these rules keep the human oriented,
informed, and in control of every decision while the agent carries the
clerical weight.

Citations: REQ-B3.1 · the bootstrap seed (Sources).

## The rules

### Progress indicator

Every interaction names where the session stands: the current phase and the
total, plus the step within the phase when phases are long (for example
`[Requirements 3/6 — group B of D]`). The human should never have to ask "how
much is left?". When a phase's length is unknowable up front (elicitation can
grow), say so and give the count of what is known.

### Progressive disclosure

Present one layer of detail at a time. Open with the shape of a decision (what
is being decided and why it matters), then reveal alternatives, then details
of the selected path. Never paste a wall of everything-at-once; never bury a
decision inside an information dump. Background the human did not ask for is
one sentence plus an offer to expand.

### Selectors with recommendations

A decision is presented as a small set of concrete options, with the agent's
recommended option first and marked as such, plus the reason for the
recommendation in one or two sentences. Options are real alternatives (the
actual branches of the decision), not timing labels. The human can always
answer outside the offered set; the selector is a scaffold, not a fence.
Decisions the agent can resolve from already-recorded answers, the seed
material, or framework doctrine are resolved and reported, not asked.

### Self-contained selectors

The selector prompt carries everything needed to answer it. In a terminal the
open selector hides the prose emitted before it, so the human answering sees
only the question, the options, and their previews. Never assume they can read
what came earlier, and never tell them to scroll up. Restate the decision and
its load-bearing context in the question text; put each option's consequence
in that option's description; put comparative or long content (diffs, tables,
side-by-side snippets) in option previews. Pre-selector prose is a short status
line only, never the place a load-bearing detail lives.

### Running summary

After each phase (and at any natural pause), restate what has been decided so
far in a compact, cumulative summary: decisions taken, their one-line
rationale, and what remains open. The summary is the human's checkpoint that
the agent heard what they said; a misunderstanding surfaces at the next
summary, not at the end of the session.

### Small bites

One question, or one tightly related cluster, per turn. A turn that asks five
unrelated things gets degraded answers to four of them. Long elicitation runs
are sequences of small exchanges, not questionnaires. When several questions
are genuinely coupled (answering one constrains the others), present them
together and say why.

## Application notes

- The rules govern attended, interactive flows. Where a skill has a
  non-interactive arm, would-be prompts follow that skill's degradation rules
  (for example recording an Awaiting-input entry) rather than being silently
  auto-answered.
- The rules are a floor, not a script: skills choose the phase names and
  granularity that fit their flow, but every authoring flow shows the
  indicator, discloses progressively, offers recommended selectors that are
  self-contained, keeps a running summary, and works in small bites.
- Verification is design-level (REQ-B3.1): the rules are documented here, and
  each authoring skill's instructions show the indicator and selectors.
