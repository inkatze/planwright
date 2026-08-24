# Operator dialogue — Design

**Status:** Draft
**Last reviewed:** 2026-08-24
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

### D-13: Extension altitude — the disciplines stand; arbitration and enforcement were the missing layers  (N)

**Decision:** The extension's altitude call (the operator report's claims are
altitude triggers under `autopilot-reflex`): D-1's doctrine-altitude bet
stands and is not re-litigated. What failed is that the doctrine shipped
without a tie-breaker against the completeness rules and without output-side
measurement. The delta therefore lands at three altitudes deliberately: the
arbitration is **doctrine** (a rule about how to think about a turn); the
enforcement is **mechanism** (an eval and a check that cannot be
pencil-whipped, per the reflex's prefer-mechanical-over-LLM-restraint rung);
and any density numbers are **values** kept out of doctrine (in eval
fixtures). Origin: extension drafting session (2026-08-24).

**Alternatives considered:**
- Treat the recurrence as skill drift and re-patch the offending skills.
  Rejected because: the base bundle already proved per-skill patching
  re-diverges (D-1), and the recurrence happened *with* the doctrine shipped —
  the gap is structural, not editorial.
- Escalate to stricter doctrine (more MUSTs about restraint). Rejected
  because: the colliding rules are both already mandatory; adding a third
  mandate without an arbitration rule leaves the collision in place, and an
  instruction an LLM follows can be pencil-whipped where a mechanical check
  cannot.

**Chosen because:** the evidence is a month of both rule sets shipped and one
silently winning; only an explicit arbitration plus a measurement changes the
equilibrium.

### D-14: The arbitration — completeness governs the artifact, disclosure governs the turn, sidedness is declared  (N)

**Decision:** One rule resolves the collision: no-silent-pruning and
completeness mandates govern **artifacts** (bundles, PR bodies, audit
records); progressive disclosure governs the **attended turn**; withholding
from a turn while recording in the artifact is not pruning. Corollary: every
emit mandate in doctrine or skill prose declares its destination side, so the
"present the four tables" class of ambiguity cannot recur.

**Alternatives considered:**
- Priority ordering (disclosure always outranks rigor at attended surfaces).
  Rejected because: it invites real pruning — a skill could withhold from the
  artifact citing disclosure; the side-split keeps both rules fully in force
  on their own territory.
- Per-skill exception lists (enumerate which surfaces may compress). Rejected
  because: an enumeration goes stale silently and re-creates the drift D-1
  exists to prevent; a decided rule ages with the decision.

**Chosen because:** it is the smallest rule that keeps every completeness
guarantee intact while making the turn governable, and the repo already
proved the two coexist in one place (the PR-body collapse discipline).

### D-15: Projection shape — bounded, actionable, one request from the whole  (N)

**Decision:** A turn-side projection leads with decisions and questions, then
supporting state, with bookkeeping last or left in the artifact; counts stand
in for tables; the full record is reachable in one request or already sits in
an artifact. The shape generalizes the two disciplines the repo has already
proven: the decision queue's load-bounded-by-actionability rule and the
PR-body's summary-first / collapsed-is-not-abridged rule.

**Alternatives considered:**
- Fixed turn templates per skill (a rigid schema each surface fills).
  Rejected because: surfaces differ too much (a drain report is not a
  sign-off), and templates re-create the checklist-walking that produced the
  walls.
- Leave "bounded" to judgment with no stated shape. Rejected because: that is
  the status quo — the doctrine already said "never paste a wall" and it did
  not hold without a stated, checkable shape.

**Chosen because:** both source disciplines are shipped, observed to work,
and cited by the operator's own recovery experience (one question per turn,
identifiers parked).

### D-16: `/polish`'s full audit record lives in a worktree-local cache file  (N)

**Decision:** `/polish` writes its accumulated audit record to a
worktree-local cache file beside the handover brief (uncommitted, in the
worktree's `.claude/` directory); the turn shows the projection. The record
is cache, not source of truth, matching the two-brief model's class for
exactly this kind of artifact.

**Alternatives considered:**
- Commit the audit record on the feature branch. Rejected because: it adds
  bookkeeping commits to every polish run and changes the local-only
  contract's shape; the record's authority never exceeds cache.
- No artifact; print the full record only on request. Rejected because: the
  record dies with the session, and a safety-stop's audit trail is lost
  exactly when it is most needed.

**Chosen because:** the operator chose it on the mechanical-consistency
ground: the two-brief model already classes in-worktree session records as
cache, the local-only contract stays intact, and the record survives the
session.

### D-17: `/orchestrate`'s step report — named slots, defined at last  (N)

**Decision:** The step report (a term the skill used but nothing defined)
becomes a bounded, named structure with three slots: **state** (what
happened, level-triggered), **reasoning** (one or two lines, or absent), and
**requests** (what the operator is asked, each item decision-shaped).
Anything decision-shaped routes through the capture rule rather than sitting
in prose. Batched halts render inside the same structure.

**Alternatives considered:**
- Leave the report free-form and rely on the projection rule alone. Rejected
  because: `/orchestrate` is the surface where information, thinking, and
  requests demonstrably blur; an undefined surface cannot be eval-graded, and
  "undefined-by-omission" is the failure mode the sweep found here.
- A machine-readable report format (JSON/YAML) rendered for the human.
  Rejected because: disproportionate — the consumer is the operator, not a
  parser; the structured decision log the eval reads already exists.

**Chosen because:** naming the slots is what makes "never mix the three" both
followable and assertable, and it is the smallest definition that closes the
sweep's "define a bounded report" gap.

### D-18: Capture-at-birth with a degradation path; tracking stays downstream  (N)

**Decision:** An attended skill captures every dialogue-born action item into
tracked state at birth — proposing the tracked form itself (a task block, an
Awaiting-input or gated Deferred entry, or an observation fragment) so the
operator confirms rather than transcribes — and maintains a session-visible
ledger of open items. Out-of-band fixes always get a ship-gate record. The
capture *interface* lives here; the downstream tracking mechanism (ledger,
roadmap updates, closure) is the companion bundle's, and until it ships,
captures target the existing accumulator surfaces.

**Alternatives considered:**
- Own the whole tracking mechanism in this bundle. Rejected because: it
  re-mixes the two decision spaces the split deliberately separated, and
  state-tracking mechanics collide with `invariant-tasks`' derived-state
  design in ways that deserve their own bundle.
- Capture into prose with a convention (a bolded "Action item:" marker).
  Rejected because: prose has no named reader and no drain ritual — it is
  exactly the write-only deferral the accumulator taxonomy forbids, and the
  fleet-lifecycle-closure failure shipped through precisely that gap.

**Chosen because:** the operator chose the split; capture is an attended-turn
discipline (this bundle's domain) while tracking is a state mechanism (the
companion's), and the degradation path means neither blocks the other.

### D-19: Enforcement — extend the shipped eval to turn shape; sidedness check stays advisory  (N)

**Decision:** The behavioral eval harness (Task 5's scaffold, shipped) gains
turn-shape invariants graded from the structured decision/transcript log:
no turn-side multi-table dump, projection present, decisions-first ordering,
no monotonic summary growth, bounded identifier density, and the
capture-at-birth assertion. A separate static check flags emit mandates with
no declared side — advisory, never a gate. Evals stay on-demand, never CI.

**Alternatives considered:**
- A new harness purpose-built for turn grading. Rejected because: the shipped
  harness already drives real TTY sessions with personas and grades durable
  artifacts; a second harness doubles maintenance for no new capability.
- Make the sidedness check a blocking gate in `mise run check`. Rejected
  because: prose analysis has false positives, and the repo's recorded stance
  is that density-class metrics inform rather than block; a wrong gate
  teaches gate-dodging.

**Chosen because:** reuse is the proportionate move, and the split (behavioral
invariants assertable on-demand, static check advisory) puts each check where
its signal is honest.

### D-20: The density bound is qualitative in doctrine, numeric only in fixtures  (N)

**Decision:** Doctrine states the bound qualitatively — one decision cluster
per turn, identifiers only where traceability needs them, plain language
first — and the eval grades conformance; any concrete numbers live in eval
fixtures, tunable without touching doctrine.

**Alternatives considered:**
- Numeric caps in doctrine. Rejected because: the numbers are arbitrary
  today, and doctrine-frozen numbers rot (the fragile-filler failure).
- A core config knob carrying numeric bounds. Rejected because: a knob on one
  operator's evidence is the exact unproven preference the customization
  boundary parks in overlays; the capability can graduate later if drain-loop
  evidence shows adopters want differing terseness.

**Chosen because:** the operator chose it on the customization-boundary
ground; it keeps doctrine durable and the tuning surface cheap.

### D-21: No monotonic accumulator reaches a turn  (N)

**Decision:** Any repeatedly-emitted summary at an attended surface is
bounded by construction: a running summary presents the delta since the last
summary plus what remains open; a resume path confirms signed sections at one
line each. The full cumulative record, where one is needed, is an artifact.

**Alternatives considered:**
- Keep cumulative summaries but cap their length. Rejected because: a cap on
  a monotonic input forces silent dropping — the exact ambiguity the
  arbitration exists to remove; delta-plus-open is bounded without dropping
  anything (the artifact holds the whole).
- Drop running summaries entirely. Rejected because: the summary is the
  checkpoint that the skill heard the operator; the defect is its monotonic
  growth, not its existence.

**Chosen because:** delta-plus-open preserves the summary's checkpoint value
at constant size, and it is the direct fix for the two accumulators the
evidence names (`/spec-draft` phase summaries, `/spec-kickoff` resume
replay).

## Cross-cutting concerns

**The wall-manufacturer sweep record (2026-08-21).** The evidenced instance
set behind REQ-J1.1, recorded at drafting time; repairs verify against the
surfaces, not against this frozen list. Turn-side mandates found: the
gate-wiring loop-end handoff (four tables + declined log + checklist + forks
emitted both to the PR body, collapsed, and at the operator, uncollapsed) as
inherited by `/self-review` (which prepends the lens-coverage table and
appends a pass summary), `/polish` (accumulated across up to ten iterations,
with no artifact home), `/execute-task` (whose handoff also nests the
checklist and forks, and which routes full CI output at the operator on an
attended halt), and `/builder` (four tables as the standalone product, also
composed in-session inside `/spec-draft`'s design phase); `/spec-draft`'s
phase-6 read-through (assembled bundle + cumulative summary + disposition
list in one turn) and its monotonic running summary; `/spec-kickoff`'s
resume-replay of every signed section, its nine-item handoff report, and the
lens-coverage table emitted mid-dialogue; `/resume`'s seven-element context
dump with the question last and an explicit include-when-unsure bias;
`/drain`'s six lanes with per-item detail (exactly one lane already has the
counts-with-detail-on-request form); the fleet/watch mode's unconditional
full re-render each iteration; `/orchestrate`'s batched-halts mandate with no
bound and its nowhere-defined "step report"; the `finding-categorization`
"present the four tables" sidedness ambiguity; and, inside
`interaction-style` itself, the self-containment rule mandating unbounded
selector density against the same file's no-walls rule, plus the unbounded
"cumulative" running-summary rule. Two shipped disciplines were found that
already embody the fix and are cited as Sources: the decision queue's
actionability bound and the PR body's collapse discipline.
