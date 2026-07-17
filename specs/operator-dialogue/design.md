# Operator dialogue — Design

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` — new decision minted in this bundle (in the drafting
session, or at a later kickoff / amendment; the decision body dates it).

## Decision log

### D-1: Doctrine altitude — widen `interaction-style`, do not hand-patch skills  (N)

**Decision:** The fix lands at doctrine altitude: `interaction-style` is
widened to govern every attended human surface and is given three named
disciplines, which the skills then instantiate. This is the altitude record
for the pinned seed claim (the operator's "made for a bot, not a peer"
framing; see `## Sources`), which is a doctrine-gap trigger under
`autopilot-reflex`.

**Alternatives considered:**
- Hand-patch the five skills individually to read less mechanically. Rejected
  because: the same failure recurs at five surfaces from one shared root cause
  (a doctrine scoped to only the two authoring skills, leaving `/spec-draft` the
  lone colleague-like outlier); five independent rewrites would drift and
  re-diverge, the exact failure `proportionality` warns about.
- Mint a new "peer-review" doctrine doc alongside `interaction-style`.
  Rejected because: it would state the same principle at a second address and
  front-load a second doc against the skills' start-load budgets; the existing
  doc already holds the good rules and only needs its scope and its three
  disciplines added.

**Chosen because:** the evidence is that one principle is missing, not that
five skills are each independently broken; a doctrine the surfaces inherit is
the smallest change that cannot silently re-diverge.

### D-2: In-band comprehension over an out-of-band artifact  (N)

**Decision:** Comprehension happens in-band, inside the live dialogue where
the operator already is, and a skill comprehends the spec faithfully before it
interviews. No separate command or generated file the operator must remember
to run and open is on the critical path.

**Alternatives considered:**
- Reuse the `/spec-walkthrough` model (a standalone command emitting an HTML
  artifact). Rejected because: that is exactly what failed — it shipped
  out-of-band and on-demand-only and went unused; ceremony nobody pays does not
  build comprehension (the spec-walkthrough failure, Sources).
- Auto-invoke a comprehension artifact from kickoff. Rejected because: it
  violates the never-auto-chain invariant and re-imports the out-of-band
  problem; kickoff teaching in-band is kickoff doing its own job, not chaining.

**Chosen because:** the walkthrough's failure is direct evidence that
comprehension has to live where the decision is being made, not in a separate
artifact.

### D-3: The independence firewall stays; the line is information-versus-advice  (N)

**Decision:** No skill delivers a verdict, score, or quality assessment of the
spec on its own behalf. Teaching and interviewing are reconciled with that
firewall by the information-versus-advice line: the skill presents information
*about* the spec but never an outcome-driven verdict — with an escape valve so
that withholding a *verdict* never means withholding *information the operator
asked for*.

**Alternatives considered:**
- Let the skill voice its read and concerns, attributed ("this is my take, you
  judge"). Rejected because: the operator explicitly rejected this — the skill's
  opinion is the skill itself, and an attributed take collapses the
  independent review into "the agent reviewed its own spec."
- A hard, valveless "never give an opinion" rule. Rejected because: with no
  escape valve it reads as evasive and infuriating (the Khanmigo failure mode),
  and it would wrongly gag the skill from answering direct information requests.

**Chosen because:** the firewall is a correct, operator-endorsed constraint;
the information-vs-advice line makes it enforceable without making the skill
mute.

### D-4: Teach the frontier and fade, with a lightweight estimate  (N)

**Decision:** The skill infers the operator's frontier and adapts — teaching
the gap between what the operator already holds and the spec's concepts, and
fading scaffolding as uptake shows — backed by a lightweight running per-concept
estimate, not a formal learner model.

**Alternatives considered:**
- Ask the operator up front what depth they want. Rejected because: it is a
  crude one-shot setting that ignores per-concept variation and puts the
  calibration burden back on the operator.
- A fixed default level with a drill-down. Rejected because: static, it
  condescends on the familiar and loses the operator on the unfamiliar.
- A full learner model (knowledge tracing / knowledge-space lattice). Rejected
  because: disproportionate machinery for a text skill; the borrowable core is
  "teach the frontier, fade," not the HMM.

**Chosen because:** the tutoring evidence (KST/ZPD) favors assess-and-adapt to
the frontier; proportionality favors a lightweight estimate over a model.

### D-5: Completeness by backward-chaining over the spec's own graph  (N)

**Decision:** Elicitation is goal-directed: readiness cannot be declared while
a decision required by the spec's own dependency structure is undefined, a
changed upstream answer reopens its dependents, and questions are bounded per
pass and asked only when needed. The "dependency structure" is read per
lifecycle: at `/spec-draft` it is the task / `Done when:` graph being elicited;
at `/spec-kickoff` (which walks an already-authored bundle) it is the bundle's
open questions and cross-references — a "required decision left undefined" is an
open question or an unresolved inconsistency, and "reopen dependents" reopens the
brief decisions an amended answer invalidates. The check is not vacuous at
kickoff: it is the discipline behind the inconsistency-halt and the
no-sign-off-with-open-questions rule.

**Alternatives considered:**
- A fixed authored checklist of questions. Rejected because: it drifts from the
  spec and silently omits questions the spec actually requires.
- Unbounded interrogation until "done." Rejected because: it fatigues the
  operator and never signals convergence.

**Chosen because:** backward-chaining over the dependency graph (docassemble's
model) makes "collected every needed answer" a provable property, and it maps
onto planwright's existing `Dependencies:` / `Done when:` structure; the ≤5
per-pass cap (Spec Kit /clarify) keeps it converging.

### D-6: Present without steering via the IPDAS balance rules  (N)

**Decision:** When presenting alternatives or a fork, the skill applies
inspectable neutrality rules — parallel equal-detail options, equal-weight pros
and cons, neutralized ordering, an explicit equal-weight reject option, no
pre-selected default, and natural-frequency probabilities — and self-audits its
own prose against them before presenting.

**Alternatives considered:**
- Rely on the no-verdict rule alone for neutrality. Rejected because:
  no-verdict catches the loud steering (a stated recommendation) but not the
  subtle version — asymmetric detail, leading order, framing — which the IPDAS
  evidence shows measurably steers judgment.

**Chosen because:** the patient-decision-aid field has already reduced
"don't covertly steer" to an operationalizable, self-auditable checklist; that
is exactly what turns a vibe into a rule. *(Reconciled at kickoff 2026-07-17:
D-12 refines the boundary — the "loud steering" this discipline suppresses is an
*ungrounded* recommendation; a recommendation grounded in the spec, doctrine, or
mechanical consistency is admitted by D-12's grounding test and may be marked,
while no-pre-selected-default and the equal-weight rules for ungrounded forks
still hold.)*

### D-7: Self-contained confirmations — the decision lives in the options  (N)

**Decision:** Every confirmation is answerable from its option set alone. This
is a rule **under** *present without steering* (D-6), not a peer discipline. Each
option restates its action and consequence, an explicit equal-weight reject
option is always present, no default is pre-selected, generic OK/Yes/No labels
are banned, and any deeper detail is supplementary, never load-bearing for the
choice. Prose above the selector is treated as if it does not exist.

**Alternatives considered:**
- Render the needed context above the picker. Rejected because: the operator's
  terminal hides prose above an open selector (obs:d0753832), so the choice
  would reference something invisible.
- Push context into a generated artifact the operator opens alongside.
  Rejected because: that is the out-of-band failure again (D-2).

**Chosen because:** the confirmation-dialog literature (NN/G) is the only body
of work built for a medium where the label alone must carry the decision, which
is precisely the operator's constraint.

### D-8: Behavioral eval via a real TTY session and simulated-operator personas  (N)

**Decision:** The eval drives a skill through a real interactive TTY session
(not headless `-p`), answered by a simulated-operator driver parameterized by
expertise persona; it grades the durable artifacts the run writes (not a
scraped pane), with an independent grader; and it stays on-demand only, reusing
the prompt-eval isolation and hygiene disciplines.

**Alternatives considered:**
- The existing headless `prompt-eval.sh` path. Rejected because: headless
  `-p` cannot render a selector or an interactive dialogue — it cannot exercise
  the very surface this spec is about — and headless slash-command injection is
  a known blocker anyway (the headless skill-injection gap, Sources).
- Grade the scraped terminal pane. Rejected because: partial `capture-pane`
  frames, ANSI, ghost-suggestion noise, and spinner redraws make it unreliable
  (planwright's false-idle scar tissue); durable written artifacts are the
  stable observables.
- The same agent drives and grades. Rejected because: it rebuilds "the agent
  reviewed its own homework" — the firewall again — so the grader must be
  independent (a non-Anthropic panel backend, human as final rater).

**Chosen because:** it is the only approach that reaches the picker and
adaptive-level surfaces we most need to measure, and personas-by-expertise are
the only way to behaviorally test calibration; the on-demand posture matches
how planwright already fences evals.

### D-9: Approval-surfaces-first, kickoff-centered  (N)

**Decision:** Scope is the approval surfaces first, centered on
`/spec-kickoff`'s guided dialogue and sign-off. `/spec-walkthrough` and the
execution-side handoffs (`/orchestrate`, `/execute-task`, `/resume`, `/drain`)
are deferred to later passes.

**Alternatives considered:**
- Revamp all six attended surfaces at once. Rejected because: the pain and the
  measurable outcomes are sharpest at kickoff; proving the doctrine and the
  eval loop on one surface first de-risks the spread, and a single-surface
  first pass keeps the instruction-budget impact bounded.

**Chosen because:** the operator chose approval-surfaces-first; it is also the
sequencing the test-anchored method rewards — establish the eval pattern where
the signal is clearest before extending it.

### D-10: Instruction-budget compliance is a hard constraint  (N)

**Decision:** Every doctrine- and skill-prose change this spec makes must fit
the repo's start-load instruction budgets (`check:instructions`); the doctrine
stays terse and point-of-use, and kickoff prose is trimmed or relocated where
additions would breach the wall.

**Alternatives considered:**
- Add the disciplines as expansive prose wherever clearest. Rejected because:
  doctrine that skills front-load counts against their start-load budgets
  (the lesson `skill-rigor` names), and `spec-kickoff` is already budget-tight.

**Chosen because:** the budget is a shipped, enforced wall; a revamp that
breaches it does not land, so it is a first-class design constraint, not an
afterthought.

### D-11: Measurable acceptance split — assertable invariants versus rubric-scored quality  (N)

**Decision:** Each interaction quality is classified as either an assertable
invariant (pinned `[test]`, driven by the eval harness) or an experiential
quality (scored against named rubrics — CDC Clear Communication Index, IPDAS
balance — and pilots, human as final rater). `test-spec.md` reflects the split.

**Alternatives considered:**
- Pin the whole surface `[manual]`. Rejected because: it leaves the
  "feels bot-made" complaint unfalsifiable and lets the quality drift back; the
  root cause is that interaction quality never had acceptance criteria while the
  mechanics had hundreds.
- Claim everything is `[test]`. Rejected because: the experiential residue
  (is the level right for this person, did knowledge transfer) is not honestly
  unit-testable; over-claiming coverage is its own failure.

**Chosen because:** splitting the surface converts the subjective complaint
into criteria where it honestly can be, and names the rubric/pilot path where
it cannot, which is the structural cure for "built for a bot."

### D-12: Recommendation vs. present-without-steering — the grounding test  (N)

**Decision:** The reworked `interaction-style` doctrine keeps the existing
"selectors with a recommendation" rule and adds the present-without-steering
balance rules (D-6), and draws the boundary between them with a **grounding
test**: a skill MAY mark a recommended option when the basis for the
recommendation is derivable from the spec, the doctrine, or mechanical
consistency — a reason the operator can verify against the artifact — and MUST
present neutrally (parallel equal-detail options, equal-weight, neutralized
ordering, explicit equal-weight reject, no pre-selected default) when the only
basis would be the skill's own opinion of whether the spec is good. The
self-audit (REQ-D1.4) applies this test to each presented fork: if the stated
reason is the skill's taste rather than an artifact-grounded fact, the
recommendation is stripped and the options are re-leveled.

**Alternatives considered:**
- Approval surfaces never recommend (drop "recommended option first" at every
  present-without-steering surface). Rejected because: it over-rotates and
  collides with the clerical/judgment split (REQ-C1.4) — it would forbid a
  recommendation even on a harmless clerical pick the operator delegated,
  pushing that weight back onto the operator.
- Keep both rules in the doc without stating the boundary, leaving it to the
  Task 1 author. Rejected because: two rules that pull against each other with
  no stated switch read as contradictory and drift per surface — the exact
  re-divergence D-1 exists to prevent.

**Chosen because:** the boundary reuses D-3's information-versus-advice line as
its switch, so it is the smallest coherent addition rather than a new principle;
and expressing it as a grounding test unifies it with the escape valve (surface
what the operator can check against the artifact; withhold only the skill's own
verdict), which turns REQ-D1.4's self-audit into a concrete check instead of a
vibe. Origin: kickoff §4 (2026-07-17).
