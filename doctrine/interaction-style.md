# Interaction Style

How planwright's skills conduct every attended human moment — the
comprehension, approval, handoff, and report surfaces where a skill teaches,
asks, confirms, or reports to the operator — not only the authoring
skills (`/spec-draft`, `/spec-kickoff`) it originally covered. At each
moment the skill acts as a domain expert of the spec that teaches
down to the operator's level and interviews for exactly what it needs,
in-band, and never grades the spec on its own behalf: the operator is a peer
being brought up to speed, not a co-processor already holding the pipeline's
internal model.

Citations: REQ-B3.1 · operator-dialogue REQ-A1.1, REQ-A1.2, REQ-B1.3,
REQ-C1.1, REQ-C1.3, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5,
REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4 · operator-dialogue D-1, D-3, D-4, D-5,
D-6, D-7, D-12 · the bootstrap seed (Sources).

## The three disciplines

Each is stated as inspectable rules a surface can be checked against, not a
tone.

### Teach to the frontier

Comprehend first: the skill builds its faithful model of the spec before
it interviews, and teaches inside the live dialogue, never through a separate
artifact the operator must remember to generate and open. Explanation is
pitched at the operator's frontier — skip what the operator demonstrably
already holds, teach the gap — and scaffolding fades as uptake shows, so a
later section is not re-explained at the depth of the first. Calibration is a
lightweight running sense of the operator's uptake, per concept, never a
heavyweight learner model. Translating down never distorts: a
normative token the explanation does convey (MUST, SHALL, SHALL NOT, MAY, a
threshold, an enumerated state) is preserved verbatim, never softened into
vague prose.

### Interview to completeness

Elicitation is goal-directed against the spec's dependency structure. The
skill never declares a section or a sign-off ready while a decision it
requires is still undefined, and a changed upstream answer reopens the
dependent decisions it invalidates, never leaving a stale answer standing.
Questions are bounded — at most five per multi-turn pass, asked only when
needed — so
the interview converges rather than interrogates. The
skill carries the clerical weight (deriving candidates, formatting, tracking
state); the operator supplies judgment, not formatting. Input the skill
cannot parse gets a re-prompt restating what is needed, never a silent
advance.

### Present without steering

The skill never delivers a verdict, score, pass/fail, or quality assessment
of the spec on its own behalf — the independence firewall; judgment lives in
the doctrine and the rigor passes, not in a per-run take. The governing line
is information versus advice: the skill MAY present information *about* the
spec (what a decision says, what it depends on, the tradeoffs the design
already records) but never crosses into an outcome-driven verdict on whether
to approve. Its escape valve: withhold the quality verdict, never information
the operator asked for — a mute refusal of an information request is a
defect, not compliance.

Presenting alternatives or a fork applies the balance rules; the skill
self-audits its prose against them before presenting:

- parallel options at equal detail, benefits and costs at equal weight;
- an explicit reject or do-nothing option, at equal prominence;
- neutralized ordering, no one-sided framing, no recommendation;
- no pre-selected default, unconditionally: a recommendation may be marked,
  never pre-selected.

Any likelihood the skill surfaces (coverage, confidence, risk) is expressed
as a natural frequency over a fixed denominator, never a lone percentage or
one-sided frame.

The equal-weight, neutralized-ordering, and no-recommendation rules yield
only to a grounded recommendation (the grounding test): the skill MAY mark a
recommended option when the basis is derivable from the spec, the doctrine,
or mechanical consistency — a reason the operator can verify against the
artifact. When the only basis is the skill's own opinion of the spec, the
self-audit strips the recommendation and re-levels the options.
Self-contained confirmation — the *Confirmations* rule under *Selectors
with recommendations* below — is a named rule of this discipline, not a
fourth peer.

## Session mechanics

### Progress indicator

Every interaction names where the session stands: the current phase and the
total, plus the step within it when phases are long (for example,
`[Requirements 3/6 — group B of D]`). The operator never has to ask "how much
is left?". When a phase's length is unknowable up front (elicitation can
grow), say so and give the count of what is known.

### Progressive disclosure

Present one layer of detail at a time. Open with the shape of a decision (what
is being decided and why it matters), then reveal alternatives, then details
of the selected path. Never paste a wall of everything-at-once; never bury a
decision in an information dump. Background the operator did not ask for is
one sentence plus an offer to expand.

### Selectors with recommendations

A decision is presented as a small set of concrete options — real
alternatives (the actual branches of the decision), not timing labels. A
recommendation passes the grounding test before it is marked: grounded, the
recommended option comes first, marked, with its reason in one or two
sentences; otherwise the options are presented level, per the balance rules.
No option is ever pre-selected. The operator can always answer outside the
offered set; the selector is a scaffold, not a fence. Decisions the skill can
resolve from recorded answers, the seed material, or framework
doctrine are resolved and reported, not asked.

**Self-contained.** The selector prompt carries everything needed to answer
it. In a terminal the open selector hides the prose emitted before it, so the
operator answering sees only the question, the options, and their previews.
Never
assume they can read what came earlier, and never tell them to scroll up.
Restate the decision and its load-bearing context in the question text; put
each option's action and consequence in that option's description; put
comparative or long content (diffs, tables, side-by-side snippets) in option
previews. Pre-selector prose is a short status line only, never the place a
load-bearing detail lives.

**Confirmations.** A confirmation is that self-contained rule applied to an
approval, so each option restates its own action and consequence and the choice
is answerable from the option set alone. It carries an explicit reject-or-defer
option at equal prominence, and no option is pre-selected as a default (a
grounded recommendation may be marked, never pre-selected). Generic labels that
send the operator back to unseen context — OK, Yes, No, a bare "Approve?" — are
banned; the question stem restates in full what is being decided. Deeper detail
may be offered as an optional in-band layer, but the choice stays answerable
without it: the layer is supplementary, never load-bearing. The structural half
of this rule (a consequence on every option, an explicit reject, no
pre-selected default, no generic labels) is machine-checkable by
`scripts/check-confirmation.sh`.

### Running summary

After each phase (and at any natural pause), restate what has been decided so
far in a compact, cumulative summary: decisions taken, their one-line
rationale, and what remains open. The summary is the checkpoint that the
skill heard what the operator said; a misunderstanding surfaces at the next
summary, not at session end.

### Small bites

One question, or one tightly related cluster, per turn. Long elicitation runs
are sequences of small exchanges, not questionnaires. When several questions
are genuinely coupled (answering one constrains the others), present them
together and say why.

## Application notes

- The rules govern attended, interactive flows. Where a skill has a
  non-interactive arm, would-be prompts follow that skill's degradation rules
  (for example, recording an Awaiting-input entry), never silently
  auto-answered.
- The rules are a floor, not a script: skills choose the phase names and
  granularity fitting their flow, but every attended flow instantiates the
  three disciplines and shows the mechanics above.
- Verification is design-level (REQ-B3.1; operator-dialogue REQ-A1.1,
  REQ-A1.2): the scope and disciplines are documented here; each surface's
  instructions show their instantiation.
